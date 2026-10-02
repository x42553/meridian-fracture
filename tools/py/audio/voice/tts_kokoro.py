"""tts_kokoro.py - Kokoro-82M (int8 ONNX) through kokoro-onnx: the shipped announcer voices.

Licences (audio spec 7.8, docs/spikes/audio.md 17): Kokoro-82M weights + voices Apache-2.0; kokoro-onnx MIT; onnxruntime MIT;
the grapheme-to-phoneme tools espeak-ng / phonemizer-fork are GPL-3.0+ and used at BUILD TIME ONLY (never linked into or shipped
with the game; the generated audio is not a derivative).  The model files live in .cache/tts (git-ignored):
kokoro-v1.0.int8.onnx + voices-v1.0.bin.  The session is pinned to ONE intra-op thread: results are bit-identical for any
thread count anyway (verified), and the build parallelises over lines with worker processes instead.
"""
from __future__ import annotations

import hashlib
from functools import lru_cache

import numpy as np

import manifest as mf
from voice import cache

TTS_DIR = mf.ROOT / ".cache" / "tts"
MODEL = TTS_DIR / "kokoro-v1.0.int8.onnx"
VOICES = TTS_DIR / "voices-v1.0.bin"
MODEL_NAME = "kokoro-v1.0.int8.onnx"
SR = 24000
ENGINE = "kokoro"
_K = None


def available() -> bool:
    try:
        import kokoro_onnx  # noqa: F401
        import onnxruntime  # noqa: F401
    except Exception:  # noqa: BLE001
        return False
    return MODEL.exists() and VOICES.exists()


@lru_cache(maxsize=1)
def model_sha256() -> str:
    h = hashlib.sha256()
    with open(MODEL, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def versions() -> dict:
    import importlib.metadata as md
    return {"kokoro_onnx": md.version("kokoro-onnx"), "onnxruntime": md.version("onnxruntime")}


def _engine():
    global _K
    if _K is None:
        import onnxruntime as ort
        from kokoro_onnx import Kokoro
        so = ort.SessionOptions()
        so.intra_op_num_threads = 1
        so.inter_op_num_threads = 1
        sess = ort.InferenceSession(str(MODEL), sess_options=so, providers=["CPUExecutionProvider"])
        _K = Kokoro.from_session(sess, str(VOICES))
    return _K


def voices() -> list[str]:
    return sorted(_engine().get_voices())


def synth(text: str, voice: str, speed: float = 1.0, lang: str = "en-us") -> tuple[np.ndarray, int]:
    """Cached synthesis -> (float64 mono samples, sample rate)."""
    k = cache.key(ENGINE, model_sha256(), voice, speed, lang, text)
    hit = cache.get(k)
    if hit is not None:
        return hit
    if not available():
        raise RuntimeError(f"Kokoro is not available (need kokoro-onnx, onnxruntime and {MODEL} / {VOICES}); "
                           "run: python3 tools/py/audio/bootstrap.py --voice")
    s, sr = _engine().create(text, voice=voice, speed=speed, lang=lang)
    x = np.asarray(s, dtype=np.float32)
    cache.put(k, x, sr)
    return x.astype(np.float64), int(sr)
