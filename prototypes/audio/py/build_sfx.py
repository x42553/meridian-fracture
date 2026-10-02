"""build_sfx.py - render every SFX recipe -> WAV (16-bit/44.1k) -> Vorbis OGG (ffmpeg) -> metrics + spectrogram sheets.

usage: python build_sfx.py [--only name,name] [--tag v1] [--bitrate 160]
outputs (relative to prototypes/audio):
  .build/wav/<category>/<name>.wav          source masters (not shipped to Godot)
  assets/audio/<category>/<name>.ogg        Vorbis, imported by Godot
  analysis/sfx_metrics_<tag>.json           metrics per asset
  analysis/sfx_sheet_<tag>_<n>.png          spectrogram contact sheets
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

import analyze
import dsp
import oggtools
import sfx

ROOT = Path(__file__).resolve().parent.parent
WAV = ROOT / ".build" / "wav"
OGG = ROOT / "assets" / "audio"
ANA = ROOT / "analysis"


def encode_ogg(xw: np.ndarray, ogg_path: Path, category: str) -> None:
    """libvorbis via oggtools (see its docstring for why not ffmpeg).  Ambience/loops get a slightly lower rate."""
    oggtools.encode_vorbis(xw, ogg_path, 0.55 if category in ("ambience",) else 0.38)


def render(s: "sfx.Sound", variant: int) -> tuple[str, np.ndarray]:
    name = s.name if s.variants == 1 else f"{s.name}_{variant}"
    rng = dsp.rng_for(name)
    x = s.fn(rng, variant if s.variants > 1 else 1)
    x = dsp.to_stereo(x) if s.channels == "stereo" else dsp.to_mono(x)
    if not s.loop:
        x = x - np.mean(x, axis=0)                     # remove DC
    amt = sfx.EXCITER.get(s.name, 0.0)
    if amt:
        x = dsp.bass_exciter(x, amt, circ=s.loop)
    if x.ndim == 2:
        x = dsp.bass_mono(x, 140.0, circ=s.loop)       # everything below 140 Hz centred (mono-compatible)
    x = dsp.normalize(x, 0.0)
    if s.lufs is not None:                              # loudness target, but never above the peak ceiling
        gain_db = min(s.lufs - analyze.lufs_integrated(x), s.peak_db)
        x = x * dsp.db_to_lin(gain_db)
    else:
        x = dsp.normalize(x, s.peak_db)
    return name, x


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--tag", default="v1")
    ap.add_argument("--bitrate", type=int, default=160)
    a = ap.parse_args()
    only = {k for k in a.only.split(",") if k}
    ANA.mkdir(exist_ok=True)
    results: dict[str, dict] = {}
    sheet_items: list[tuple[str, np.ndarray, str]] = []
    t_all = time.time()
    for s in sfx.SOUNDS.values():
        for v in range(1, s.variants + 1):
            name = s.name if s.variants == 1 else f"{s.name}_{v}"
            if only and s.name not in only and name not in only:
                continue
            t0 = time.time()
            name, x = render(s, v)
            t_render = time.time() - t0
            wav_p = WAV / s.category / f"{name}.wav"
            wav_p.parent.mkdir(parents=True, exist_ok=True)
            dsp.write_wav(str(wav_p), x, dither_seed=name)
            xw = dsp.read_wav(str(wav_p))
            ogg_p = OGG / s.category / f"{name}.ogg"
            encode_ogg(xw, ogg_p, s.category)
            mono_bytes = 0
            if xw.ndim == 2 and s.category in ("weapons", "explosions", "energy", "air", "structures", "vehicles"):
                # AudioStreamPlayer3D does not downmix: an L-only stereo file stays in the left ear wherever the source is
                # (measured, tests/t_capture.gd).  Positional events therefore use this mono downmix.
                mono_bytes = oggtools.encode_vorbis(dsp.normalize(dsp.to_mono(xw), s.peak_db), OGG / s.category / f"{name}.mono.ogg", 0.38)
            m = analyze.metrics(xw, s.loop)
            m.update(analyze.ffmpeg_ebur128(str(wav_p)))
            m.update(analyze.codec_roundtrip(str(wav_p), str(ogg_p), xw))
            m.update({"category": s.category, "loop": s.loop, "render_s": round(t_render, 2),
                      "mono_variant_bytes": mono_bytes, "wav_bytes": wav_p.stat().st_size, "ogg_bytes": ogg_p.stat().st_size,
                      "sha256": hashlib.sha256(wav_p.read_bytes()).hexdigest()[:16], "notes": s.notes})
            results[name] = m
            sheet_items.append((f"{name} [{s.category}]", xw, f"{m['duration_s']}s pk {m['peak_db']} lufs {m['lufs_i']} crest {m['crest_db']}"
                                f"{' seam ' + str(m['seam_score']) if s.loop else ''}"))
            print(f"{name:26s} {m['duration_s']:6.2f}s pk {m['peak_db']:6.1f} lufs {str(m['lufs_i']):>6s} crest {m['crest_db']:5.1f} "
                  f"att {m['attack_ms']:6.1f}ms t40 {m['t40_ms']:6.0f}ms cen {m['centroid_hz']:6.0f} snr {m['snr_db']:5.1f} "
                  f"{('seam ' + str(m['seam_score'])) if s.loop else ''} render {t_render:4.1f}s", flush=True)
    (ANA / f"sfx_metrics_{a.tag}.json").write_text(json.dumps(results, indent=1))
    per = 8
    for i in range(0, len(sheet_items), per):
        analyze.contact_sheet(sheet_items[i:i + per], str(ANA / f"sfx_sheet_{a.tag}_{i // per + 1}.png"))
    print(f"TOTAL {len(results)} assets in {time.time() - t_all:.1f}s")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
