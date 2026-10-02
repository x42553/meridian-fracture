"""oggtools.py - Vorbis encoding with reproducible bytes.

Why not ffmpeg?  The Homebrew ffmpeg 9.0.1 on the dev machine has no libvorbis; its experimental native encoder
(a) supports only 2 channels, (b) ignores -b:a (fixed quality), (c) pads the stream by 16-32 samples (breaks loop
lengths).  libsndfile (wheel bundled with the `soundfile` package) ships libvorbis: true mono, VBR quality control and
sample-exact length.  libsndfile picks a *random* Ogg stream serial, so we rewrite the serial + page CRCs afterwards to
make the build bit-reproducible.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np

import dsp

_SERIAL = 0x4D455249  # "MERI"


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


def _ogg_crc(data: bytes) -> int:
    crc = 0
    tbl = _TABLE
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ tbl[((crc >> 24) & 0xFF) ^ b]
    return crc


def fix_serial(path: str | Path, serial: int = _SERIAL) -> None:
    """Rewrite every page's stream serial and CRC in place (deterministic output)."""
    p = Path(path)
    data = bytearray(p.read_bytes())
    i = 0
    while i < len(data):
        assert data[i:i + 4] == b"OggS", "not an Ogg page"
        nseg = data[i + 26]
        plen = 27 + nseg + sum(data[i + 27:i + 27 + nseg])
        data[i + 14:i + 18] = serial.to_bytes(4, "little")
        data[i + 22:i + 26] = b"\0\0\0\0"
        data[i + 22:i + 26] = _ogg_crc(bytes(data[i:i + plen])).to_bytes(4, "little")
        i += plen
    p.write_bytes(bytes(data))


def encode_vorbis(x: np.ndarray, path: str | Path, compression: float = 0.4) -> int:
    """Encode float audio (mono (n,) or stereo (n,2)) to Ogg Vorbis with libvorbis.
    compression 0..1 (soundfile semantics: higher = smaller/worse; 0.3 ~ q7, 0.4 ~ q6, 0.5 ~ q5).  Returns bytes written."""
    import soundfile as sf  # build-time only (wheel bundles libvorbis)

    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(p), np.clip(x, -1.0, 1.0), dsp.SR, format="OGG", subtype="VORBIS", compression_level=compression)
    fix_serial(p)
    return p.stat().st_size
