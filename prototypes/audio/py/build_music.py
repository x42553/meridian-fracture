"""build_music.py - render layered stems for the flagship tracks, export WAV+OGG, verify loops, tempo and scale hooks.

usage: python build_music.py [--tracks combat_tense,calm_buildup] [--demo] [--tag v1]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import numpy as np

import analyze
import dsp
import music
import oggtools
from dsp import SR

ROOT = Path(__file__).resolve().parent.parent
WAV, OGG, ANA = ROOT / ".build" / "wav" / "music", ROOT / "assets" / "audio" / "music", ROOT / "analysis"
TRACKS = {"combat_tense": dict(flavour="default", style="combat", bars=32), "calm_buildup": dict(flavour="calm", style="calm", bars=16)}
CL = 0.35   # libvorbis quality (~q6.5)


def estimate_bpm(x: np.ndarray, lo: float = 60, hi: float = 200) -> float:
    """Onset-envelope autocorrelation (numpy only).  Returns the BPM with the strongest periodicity in [lo, hi]."""
    m = dsp.to_mono(x)
    hop, nfft = 512, 1024
    fr = np.lib.stride_tricks.sliding_window_view(m, nfft)[::hop] * np.hanning(nfft)
    mag = np.abs(np.fft.rfft(fr, axis=1))
    flux = np.maximum(np.diff(np.log1p(mag * 50), axis=0), 0).sum(axis=1)
    flux = flux - flux.mean()
    ac = np.fft.irfft(np.abs(np.fft.rfft(flux, 2 * len(flux))) ** 2)[: len(flux)]
    fps = SR / hop
    best, bv = lo, -1.0
    for bpm in np.arange(lo, hi, 0.25):
        lag = 60.0 / bpm * fps
        i = int(round(lag))
        v = (ac[i] + ac[min(2 * i, len(ac) - 1)] * 0.5 + ac[min(4 * i, len(ac) - 1)] * 0.25) * np.exp(-0.5 * (np.log2(bpm / 120.0) / 0.6) ** 2)
        if v > bv:
            best, bv = float(bpm), v
    return best


def in_scale_pct(x: np.ndarray, root: int, mode: str) -> float:
    """Share of pitched energy (60-1400 Hz) that falls on the scale's pitch classes."""
    m = dsp.to_mono(x)
    nfft = 16384
    fr = np.lib.stride_tricks.sliding_window_view(m, nfft)[:: nfft // 2][:200] * np.hanning(nfft)
    ps = (np.abs(np.fft.rfft(fr, axis=1)) ** 2).mean(axis=0)
    f = np.fft.rfftfreq(nfft, 1 / SR)
    sel = (f > 60) & (f < 1400)
    pc = np.round(12 * np.log2(f[sel] / 440.0) + 69).astype(int) % 12
    chroma = np.bincount(pc, weights=ps[sel], minlength=12)
    ok = {(root + d) % 12 for d in music.SCALES[mode]}
    return float(100 * sum(chroma[i] for i in ok) / (chroma.sum() + 1e-12))


def loop_continuity(x: np.ndarray, win: float = 0.1) -> float:
    """Spectral distance across the loop seam relative to the median distance between adjacent windows elsewhere (~1 = seamless)."""
    m = dsp.to_mono(x)
    w = int(win * SR)
    hann = np.hanning(w)
    def sp(seg: np.ndarray) -> np.ndarray:
        return np.log10(np.abs(np.fft.rfft(seg * hann)) + 1e-5)
    d_seam = float(np.mean(np.abs(sp(m[-w:]) - sp(m[:w]))))
    ks = np.linspace(0, len(m) - 2 * w, 60).astype(int)
    d_base = float(np.median([np.mean(np.abs(sp(m[k:k + w]) - sp(m[k + w:k + 2 * w]))) for k in ks]))
    return d_seam / (d_base + 1e-9)


def export_track(name: str, spec: dict) -> dict:
    f = music.FLAVOURS[spec["flavour"]]
    t0 = time.time()
    stems = music.arrange(f, spec["style"], spec["bars"])
    stems, mix, gdb = music.mixdown(stems, spec["style"])
    t_render = time.time() - t0
    out: dict = {"flavour": f.name, "style": spec["style"], "bars": spec["bars"], "bpm": f.bpm, "beat_count": spec["bars"] * 4, "bar_beats": 4,
                 "mode": f.mode, "root_midi": f.root, "length_samples": int(len(mix)), "render_s": round(t_render, 1), "master_gain_db": round(gdb, 2), "stems": {}}
    items = []
    wd, od = WAV / name, OGG / name
    wd.mkdir(parents=True, exist_ok=True)
    od.mkdir(parents=True, exist_ok=True)
    for sname, x in list(stems.items()) + [("mix", mix)]:
        wp = wd / f"{sname}.wav"
        dsp.write_wav(str(wp), x, dither_seed=f"{name}.{sname}")
        xw = dsp.read_wav(str(wp))
        m = analyze.metrics(xw, loop=True)
        m["lufs_i"] = round(analyze.lufs_integrated(xw), 1)
        if sname == "mix":
            m.update(analyze.ffmpeg_ebur128(str(wp)))
        else:
            op = od / f"{sname}.ogg"
            m["ogg_bytes"] = oggtools.encode_vorbis(xw, op, CL)
            m.update(analyze.codec_roundtrip(str(wp), str(op), xw))
            dec = analyze.decode_ogg(str(op))
            m["seam_score_decoded"] = round(dsp.seam_score(dec), 2)
            m["loop_continuity_decoded"] = round(loop_continuity(dec), 2)
            m["sha256"] = hashlib.sha256(wp.read_bytes()).hexdigest()[:16]
        m["loop_continuity"] = round(loop_continuity(xw), 2)
        out["stems"][sname] = m
        items.append((f"{name}/{sname}", xw, f"pk {m['peak_db']} lufs {m['lufs_i']} seam {m['seam_score']} cont {m['loop_continuity']}"))
    out["bpm_est_drums"] = estimate_bpm(dsp.read_wav(str(wd / "drums.wav")))
    harm = dsp.read_wav(str(wd / "pads.wav")) + dsp.read_wav(str(wd / "lead.wav")) + dsp.read_wav(str(wd / "bass.wav"))
    out["in_scale_pct"] = round(in_scale_pct(harm, f.root, f.mode), 1)
    out["ogg_total_bytes"] = sum(s.get("ogg_bytes", 0) for s in out["stems"].values())
    analyze.contact_sheet(items, str(ANA / f"music_{name}_{ARGS.tag}.png"), cols=2, cell_w=640, cell_h=190)
    return out


def flavour_demo() -> dict:
    """8 factions x 8 bars: verifies that tempo / scale / timbre hooks are audible in objective terms."""
    res, items = {}, []
    for key in ("napc", "nec", "olm", "def", "pd", "han", "ae", "sap"):
        f = music.FLAVOURS[key]
        t0 = time.time()
        stems = music.arrange(f, "combat", 8, "demo")
        stems, mix, _ = music.mixdown(stems, "combat")
        harm = stems["pads"] + stems["lead"] + stems["bass"]
        r = {"bpm": f.bpm, "bpm_est": estimate_bpm(stems["drums"]), "mode": f.mode, "in_scale_pct": round(in_scale_pct(harm, f.root, f.mode), 1),
             "kit": f.kit, "bass": f.bass, "pad": f.pad, "lead": f.lead, "centroid_hz": analyze.metrics(mix, True)["centroid_hz"],
             "lufs_i": round(analyze.lufs_integrated(mix), 1), "render_s": round(time.time() - t0, 1)}
        res[key] = r
        items.append((f"{key}  {f.bpm:g} bpm {f.mode}", mix, f"est {r['bpm_est']} in-scale {r['in_scale_pct']}%  {f.kit}/{f.bass}/{f.pad}/{f.lead}"))
        print(f"  {key:5s} bpm {f.bpm:5.1f} est {r['bpm_est']:6.2f}  in-scale {r['in_scale_pct']:5.1f}%  centroid {r['centroid_hz']:6.0f}  lufs {r['lufs_i']:6.1f}  render {r['render_s']}s", flush=True)
    analyze.contact_sheet(items, str(ANA / f"music_flavours_{ARGS.tag}.png"), cols=2, cell_w=640, cell_h=170)
    return res


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    ap = argparse.ArgumentParser()
    ap.add_argument("--tracks", default=",".join(TRACKS))
    ap.add_argument("--demo", action="store_true")
    ap.add_argument("--tag", default="v1")
    ARGS = ap.parse_args()
    ANA.mkdir(exist_ok=True)
    report: dict = {}
    for name in [t for t in ARGS.tracks.split(",") if t]:
        r = export_track(name, TRACKS[name])
        report[name] = r
        print(f"{name}: {r['bars']} bars @ {r['bpm']} bpm ({r['length_samples'] / SR:.2f}s) render {r['render_s']}s master {r['master_gain_db']} dB  "
              f"mix LUFS {r['stems']['mix']['lufs_i']} TP {r['stems']['mix'].get('true_peak_db')} bpm_est {r['bpm_est_drums']} in-scale {r['in_scale_pct']}% ogg {r['ogg_total_bytes'] / 1e6:.2f} MB")
        for sn, m in r["stems"].items():
            print(f"    {sn:6s} pk {m['peak_db']:6.1f} lufs {m['lufs_i']:6.1f} crest {m['crest_db']:5.1f} seam {m['seam_score']:5.2f} cont {m['loop_continuity']:5.2f}"
                  + (f" | ogg seam {m['seam_score_decoded']:5.2f} cont {m['loop_continuity_decoded']:5.2f} len_delta {m['len_delta']} snr {m['snr_db']}" if 'seam_score_decoded' in m else ""))
    if ARGS.demo:
        report["flavour_demo"] = flavour_demo()
    (ANA / f"music_metrics_{ARGS.tag}.json").write_text(json.dumps(report, indent=1))
