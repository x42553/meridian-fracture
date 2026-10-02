"""tts_piper.py - Piper voices for FAST ITERATION (RTF 0.03 vs 1.5 for Kokoro): `build_all.py voice --engine piper`.

Only voices with a licence that permits shipping are accepted (audio spec 7.8 / spike 17): en_US-joe (CC0-1.0) and en_GB-cori
(public domain -> CC0-1.0 in PROVENANCE).  hfc_male / ryan (CC BY-NC-SA), lessac (Blizzard-2013) and every voice not listed here are
refused.  piper-tts itself is GPL-3.0+: it runs in its own venv (.cache/venv_piper) as a subprocess at build time and is never
imported by this toolchain, linked, or shipped.  The shipped announcer set is Kokoro (tts_kokoro.py); Piper output is written to
the same asset ids only when explicitly requested.
"""
from __future__ import annotations

import json
import subprocess
import wave

import numpy as np

import manifest as mf
from voice import cache

DIR = mf.ROOT / ".cache" / "tts" / "piper"
VENV_PY = mf.ROOT / ".cache" / "venv_piper" / "bin" / "python"
ALLOWED = {"en_US-joe-medium": "CC0-1.0", "en_GB-cori-medium": "CC0-1.0"}
ENGINE = "piper"
_BATCH = r"""
import json, sys, wave
from piper import PiperVoice
v = PiperVoice.load(sys.argv[1])
for job in json.loads(sys.argv[2]):
    with wave.open(job["out"], "wb") as wf:
        v.synthesize_wav(job["text"], wf)
"""


def available() -> bool:
    return VENV_PY.exists() and all((DIR / f"{v}.onnx").exists() for v in ALLOWED)


def synth(text: str, voice: str, speed: float = 1.0, lang: str = "en-us") -> tuple[np.ndarray, int]:
    if voice not in ALLOWED:
        raise ValueError(f"Piper voice {voice!r} is not licence-cleared for shipping (allowed: {sorted(ALLOWED)})")
    k = cache.key(ENGINE, voice, voice, speed, lang, text)
    hit = cache.get(k)
    if hit is not None:
        return hit
    if not available():
        raise RuntimeError(f"Piper is not set up ({VENV_PY} / {DIR})")
    out = cache.DIR / f"_piper_{k[:16]}.wav"
    cache.DIR.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(VENV_PY), "-c", _BATCH, str(DIR / f"{voice}.onnx"), json.dumps([{"text": text, "out": str(out)}])], check=True, capture_output=True)
    with wave.open(str(out), "rb") as w:
        sr, raw = w.getframerate(), w.readframes(w.getnframes())
    out.unlink()
    x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    cache.put(k, x, sr)
    return x.astype(np.float64), sr
