"""oggtools.py - Vorbis encoding with reproducible bytes.

Why not ffmpeg?  The Homebrew ffmpeg 9.0.1 on the dev machine has no libvorbis; its experimental native encoder
(a) supports only 2 channels, (b) ignores -b:a (fixed quality), (c) pads the stream by 16-32 samples (breaks loop
lengths).  libsndfile (wheel bundled with the `soundfile` package) ships libvorbis: true mono, VBR quality control
and sample-exact length.  libsndfile picks a *random* Ogg stream serial, so the serial + page CRCs are rewritten
afterwards to make the build bit-reproducible.

QUALITY presets are `compression_level` values of soundfile (0 = best, 1 = smallest; 0.3 ~ q7, 0.4 ~ q6, 0.5 ~ q5).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np

import dsp

SERIAL = 0x4D455249  # "MERI"
QUALITY = {"sfx": 0.38, "ambience": 0.55, "voice": 0.50, "music": 0.45}


def _crc_table() -> list[int]:
    t = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if (r & 0x80000000) else (r << 1)
            r &= 0xFFFFFFFF
        t.append(r)
    return t


_TABLE = _crc_table()


def ogg_crc(data: bytes | bytearray | memoryview) -> int:
    crc = 0
    tbl = _TABLE
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ tbl[(crc >> 24) ^ b]
    return crc


def fix_serial(path: str | Path, serial: int = SERIAL) -> None:
    """Rewrite every page's stream serial and CRC in place (deterministic output)."""
    p = Path(path)
    data = bytearray(p.read_bytes())
    i = 0
    while i < len(data):
        if data[i:i + 4] != b"OggS":
            raise ValueError(f"{p}: not an Ogg page at byte {i}")
        nseg = data[i + 26]
        plen = 27 + nseg + sum(data[i + 27:i + 27 + nseg])
        data[i + 14:i + 18] = serial.to_bytes(4, "little")
        data[i + 22:i + 26] = b"\0\0\0\0"
        data[i + 22:i + 26] = ogg_crc(memoryview(data)[i:i + plen]).to_bytes(4, "little")
        i += plen
    p.write_bytes(bytes(data))


def encode_vorbis(x: np.ndarray, path: str | Path, compression: float = 0.4) -> int:
    """Encode float audio (mono (n,) or stereo (n,2)) to Ogg Vorbis with libvorbis.  Returns bytes written."""
    import soundfile as sf  # build-time only (wheel bundles libvorbis)

    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(p), np.clip(x, -1.0, 1.0), dsp.SR, format="OGG", subtype="VORBIS", compression_level=compression)
    fix_serial(p)
    return p.stat().st_size


def decode(path: str | Path) -> np.ndarray:
    """Decode an OGG to float64 (mono (n,) or stereo (n,2)) with the same libvorbis that encoded it (sample-exact)."""
    import soundfile as sf

    y, sr = sf.read(str(path), dtype="float64", always_2d=False)
    if sr != dsp.SR:
        raise ValueError(f"{path}: sample rate {sr} != {dsp.SR}")
    return y
