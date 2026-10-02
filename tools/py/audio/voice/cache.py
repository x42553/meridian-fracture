"""cache.py - hash cache of RAW TTS output (float32 at the engine's rate), .cache/audio/tts/<hash>.npz.

key = sha256(engine, model id / sha256, voice, speed, language, text as sent to the engine, CACHE_VERSION): only lines whose text, voice
or model changed are re-synthesised (spec 7.8).  The cache is a pure accelerator: the shipped OGGs depend on it only through the
synthesised samples, and Kokoro (int8, CPU) is deterministic and thread-count independent, so a cold rebuild reproduces them.
"""
from __future__ import annotations

import hashlib
import json
import numpy as np

import manifest as mf

CACHE_VERSION = 1
DIR = mf.ROOT / ".cache" / "audio" / "tts"


def key(engine: str, model: str, voice: str, speed: float, lang: str, text: str) -> str:
    blob = json.dumps({"e": engine, "m": model, "v": voice, "s": round(speed, 4), "l": lang, "t": text, "c": CACHE_VERSION}, sort_keys=True)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def get(k: str) -> tuple[np.ndarray, int] | None:
    p = DIR / f"{k}.npz"
    if not p.exists():
        return None
    try:
        with np.load(p) as z:
            return z["x"].astype(np.float64), int(z["sr"])
    except Exception:  # noqa: BLE001 - a torn write is simply re-synthesised
        return None


def put(k: str, x: np.ndarray, sr: int) -> None:
    DIR.mkdir(parents=True, exist_ok=True)
    tmp = DIR / f"{k}.tmp{hashlib.sha1(str(id(x)).encode()).hexdigest()[:6]}.npz"
    np.savez_compressed(tmp, x=np.asarray(x, dtype=np.float32), sr=np.int32(sr))
    tmp.replace(DIR / f"{k}.npz")
