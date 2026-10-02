"""verify.py - objective checks of the shipped music files (audio spec 10.2 music row) and the audition sheets.

Measured on the DECODED OGGs, per track: exact length, channels (bass mono), source + decoded loop seam <= 4.0, spectral loop
continuity <= 3.0 (spectral distance across the seam relative to the distance between adjacent windows elsewhere), sum of the four
stems: LUFS window (combat -14.4 +-1, calm -16.1 +-1) and true peak <= -2.0 dBTP, per-stem balance +-1.5 LU against the master
reference, tempo estimated blindly from the drums (within 2 % of the catalog BPM or exactly half / double, the spike's estimator
ambiguity) and the share of pitched energy inside the track's scale (>= 75 %).  Stingers: length, first / last sample, true peak,
loudness window.  Also: the catalog agrees with game/data/audio/music.json, and the faction palettes stay distinguishable
(closest pair of the 8 combat mixes in a tempo / centroid / mode-histogram space must not shrink by > 20 % against the baseline
recorded in the manifest under qa.distinct_music).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

import analyze
import dsp
import oggtools
from catalog import music as cm
from dsp import SR

TEMPO_TOL = 0.02
SCALE_MIN = 75.0
CONT_MAX = 3.0
SEAM_MAX = 4.0
DISTINCT_DROP = 0.20
STINGER_LUFS_WINDOW = (-21.0, -10.0)      # risers are peak-limited crescendos (about -18 LUFS-I), hits about -14


def estimate_bpm(x: np.ndarray, lo: float = 60.0, hi: float = 200.0) -> float:
    """Onset-envelope autocorrelation (numpy only, fractional lags): the BPM with the strongest periodicity in [lo, hi],
    weakly biased to 120 (so half / double answers are the estimator's known ambiguity)."""
    m = dsp.to_mono(x)
    hop, nfft = 256, 1024
    fr = np.lib.stride_tricks.sliding_window_view(m, nfft)[::hop] * np.hanning(nfft)
    mag = np.abs(np.fft.rfft(fr, axis=1))
    flux = np.maximum(np.diff(np.log1p(mag * 50), axis=0), 0).sum(axis=1)
    flux = flux - flux.mean()
    ac = np.fft.irfft(np.abs(np.fft.rfft(flux, 2 * len(flux))) ** 2)[: len(flux)]
    fps = SR / hop
    lags = np.arange(len(ac), dtype=np.float64)

    def at(lag: float) -> float:
        return float(np.interp(min(lag, len(ac) - 1.0), lags, ac))
    best, bv = lo, -1.0
    for bpm in np.arange(lo, hi, 0.1):
        lag = 60.0 / bpm * fps
        v = (at(lag) + at(2 * lag) * 0.5 + at(4 * lag) * 0.25) * np.exp(-0.5 * (np.log2(bpm / 120.0) / 0.6) ** 2)
        if v > bv:
            best, bv = float(bpm), v
    return best


def tempo_ok(est: float, bpm: float) -> bool:
    return any(abs(est - bpm * r) / (bpm * r) <= TEMPO_TOL for r in (1.0, 0.5, 2.0))


def chroma(x: np.ndarray) -> np.ndarray:
    """12-bin pitch-class energy of the pitched range (60-1400 Hz), normalised."""
    m = dsp.to_mono(x)
    nfft = 16384
    fr = np.lib.stride_tricks.sliding_window_view(m, nfft)[:: nfft // 2][:200] * np.hanning(nfft)
    ps = (np.abs(np.fft.rfft(fr, axis=1)) ** 2).mean(axis=0)
    f = np.fft.rfftfreq(nfft, 1 / SR)
    sel = (f > 60) & (f < 1400)
    pc = np.round(12 * np.log2(f[sel] / 440.0) + 69).astype(int) % 12
    c = np.bincount(pc, weights=ps[sel], minlength=12)
    return c / (c.sum() + 1e-12)


def in_scale_pct(x: np.ndarray, root: int, mode: str) -> float:
    from music.flavours import SCALES
    c = chroma(x)
    ok = {(root + d) % 12 for d in SCALES[mode]}
    return float(100 * sum(c[i] for i in ok))


def loop_continuity(x: np.ndarray, win: float = 0.1) -> float:
    m = dsp.to_mono(x)
    w = int(win * SR)
    hann = np.hanning(w)

    def sp(seg: np.ndarray) -> np.ndarray:
        return np.log10(np.abs(np.fft.rfft(seg * hann)) + 1e-5)
    d_seam = float(np.mean(np.abs(sp(m[-w:]) - sp(m[:w]))))
    ks = np.linspace(0, len(m) - 2 * w, 60).astype(int)
    d_base = float(np.median([np.mean(np.abs(sp(m[k:k + w]) - sp(m[k + w:k + 2 * w]))) for k in ks]))
    return d_seam / (d_base + 1e-9)


def _dual(x: np.ndarray) -> np.ndarray:
    return np.stack([x, x], axis=1) if x.ndim == 1 else x


def analyze_track(root: Path, spec: cm.TrackSpec, assets: dict) -> tuple[dict, list[str]]:
    """Metrics + failures of one track from the shipped files."""
    fails: list[str] = []
    dec: dict[str, np.ndarray] = {}
    for stem in cm.STEMS:
        aid = f"{spec.folder}/{stem}"
        e = assets.get(aid)
        if e is None:
            return {}, [f"{aid}: missing from manifest"]
        p = root / e["file"]
        if not p.exists():
            return {}, [f"{aid}: file missing {e['file']}"]
        if hashlib_sha(p) != e["sha256"]:
            fails.append(f"{aid}: sha256 differs from manifest")
        dec[stem] = oggtools.decode(p)
    m: dict = {"stems": {}}
    for stem, x in dec.items():
        aid = f"{spec.folder}/{stem}"
        e = assets[aid]
        want_ch = 1 if stem in cm.MONO_STEMS else 2
        ch = 1 if x.ndim == 1 else x.shape[1]
        if ch != want_ch:
            fails.append(f"{aid}: {ch} channels, expected {want_ch}")
        if len(x) != spec.length_samples:
            fails.append(f"{aid}: {len(x)} samples, expected {spec.length_samples}")
        if e.get("len_delta", 0) != 0:
            fails.append(f"{aid}: OGG length delta {e['len_delta']}")
        if not np.all(np.isfinite(x)):
            fails.append(f"{aid}: NaN")
        seam = dsp.seam_score(x)
        if seam > SEAM_MAX:
            fails.append(f"{aid}: decoded seam {seam:.2f} > {SEAM_MAX}")
        if (e.get("seam_src") or 0) > SEAM_MAX:
            fails.append(f"{aid}: source seam {e['seam_src']} > {SEAM_MAX}")
        lu = analyze.lufs_integrated(_dual(x))
        ref = e.get("lufs_ref")
        if ref is not None and abs(lu - ref) > cm.STEM_TOL:
            fails.append(f"{aid}: stem loudness {lu:.1f} LUFS vs reference {ref} (tol {cm.STEM_TOL})")
        m["stems"][stem] = {"lufs": round(lu, 1), "seam": round(seam, 2), "bytes": e["bytes"]}
    mix = sum(_dual(v) for v in dec.values())
    m["mix_lufs"] = round(analyze.lufs_integrated(mix), 2)
    m["mix_tp"] = round(analyze.true_peak_db(mix), 2)
    if abs(m["mix_lufs"] - spec.lufs) > cm.MIX_TOL:
        fails.append(f"{spec.id}: mix {m['mix_lufs']} LUFS outside {spec.lufs} +-{cm.MIX_TOL}")
    if m["mix_tp"] > cm.MIX_TP_MAX:
        fails.append(f"{spec.id}: mix true peak {m['mix_tp']} > {cm.MIX_TP_MAX}")
    m["continuity"] = round(loop_continuity(mix), 2)
    if m["continuity"] > CONT_MAX:
        fails.append(f"{spec.id}: spectral loop continuity {m['continuity']} > {CONT_MAX}")
    est = estimate_bpm(dec["drums"])
    m["bpm_est"] = round(est, 2)
    if not tempo_ok(est, spec.bpm):
        fails.append(f"{spec.id}: tempo estimate {est:.1f} vs {spec.bpm} (not within {TEMPO_TOL:.0%} / half / double)")
    harm = dec["pads"] + dec["lead"] + _dual(dec["bass"])
    m["in_scale_pct"] = round(in_scale_pct(harm, spec.root_midi, spec.mode), 1)
    if m["in_scale_pct"] < SCALE_MIN:
        fails.append(f"{spec.id}: only {m['in_scale_pct']} % of pitched energy in {spec.mode} (< {SCALE_MIN})")
    m["centroid_hz"] = analyze.metrics(mix)["centroid_hz"]
    m["chroma"] = [round(float(v), 4) for v in np.roll(chroma(harm), -(spec.root_midi % 12))]
    m["_mix"] = mix
    return m, fails


def hashlib_sha(p: Path) -> str:
    import hashlib
    return hashlib.sha256(p.read_bytes()).hexdigest()


def analyze_stinger(root: Path, spec: cm.StingerSpec, assets: dict) -> tuple[dict, list[str]]:
    e = assets.get(spec.id)
    if e is None:
        return {}, [f"{spec.id}: missing from manifest"]
    p = root / e["file"]
    if not p.exists():
        return {}, [f"{spec.id}: file missing"]
    fails: list[str] = []
    if hashlib_sha(p) != e["sha256"]:
        fails.append(f"{spec.id}: sha256 differs from manifest")
    x = oggtools.decode(p)
    if x.ndim != 2:
        fails.append(f"{spec.id}: not stereo")
    m = analyze.metrics(x)
    if len(x) != spec.length_samples:
        fails.append(f"{spec.id}: {len(x)} samples, expected {spec.length_samples}")
    if e.get("len_delta", 0) != 0:
        fails.append(f"{spec.id}: OGG length delta {e['len_delta']}")
    if m["true_peak_db"] > cm.MIX_TP_MAX:
        fails.append(f"{spec.id}: true peak {m['true_peak_db']} > {cm.MIX_TP_MAX}")
    if not (STINGER_LUFS_WINDOW[0] <= m["lufs_i"] <= STINGER_LUFS_WINDOW[1]):
        fails.append(f"{spec.id}: loudness {m['lufs_i']} outside {STINGER_LUFS_WINDOW}")
    if m["x0"] > 0.02 or m["x_end"] > 0.003:
        fails.append(f"{spec.id}: edges x0 {m['x0']} x_end {m['x_end']}")
    if m["nan"] or m["clipped_samples"]:
        fails.append(f"{spec.id}: NaN or clipped samples")
    if spec.kind in ("victory", "defeat") and not (4.0 <= m["duration_s"] <= 9.0):
        fails.append(f"{spec.id}: length {m['duration_s']} s outside 4-9 s")
    m["_x"] = x
    return m, fails


def check_data(root_data: Path) -> list[str]:
    """The authored music.json must agree with the catalog (bpm, bars, lengths, modes, roots, stingers)."""
    p = root_data / "music.json"
    if not p.exists():
        return ["music.json missing"]
    d = json.loads(p.read_text(encoding="utf-8"))
    want = cm.music_json()
    fails = []
    for sec in ("tracks", "stingers"):
        for k, v in want[sec].items():
            got = d.get(sec, {}).get(k)
            if got != v:
                fails.append(f"music.json {sec}.{k}: {got} != catalog {v}")
        for k in d.get(sec, {}):
            if k not in want[sec]:
                fails.append(f"music.json {sec}.{k}: not in catalog")
    return fails


def distinct_vector(m: dict) -> np.ndarray:
    return np.concatenate([[np.log2(max(m["bpm_target"], 1.0)) * 1.5, np.log(max(m["centroid_hz"], 1.0)) * 1.2], np.array(m["chroma"]) * 6.0])


def distinctness(metrics: dict[str, dict]) -> dict:
    facs = [f for f in cm.FACTIONS if f"{f}.combat" in metrics]
    if len(facs) < 2:
        return {}
    v = np.stack([distinct_vector(metrics[f"{f}.combat"]) for f in facs])
    best, pair = 1e9, ("", "")
    for i in range(len(facs)):
        for j in range(i + 1, len(facs)):
            d = float(np.linalg.norm(v[i] - v[j]))
            if d < best:
                best, pair = d, (facs[i], facs[j])
    return {"min": round(best, 3), "pair": list(pair)}


def run(root: Path, man: dict, only: list[str] | None = None, sheets: bool = False, log=print) -> tuple[int, dict]:
    """All music checks.  Returns (failures, qa dict to merge into the manifest when everything passed)."""
    import manifest as mf
    assets = man["assets"]
    fails_total = 0
    tracks = [t for t in cm.tracks() if not only or any(t.id.startswith(o) or t.folder.startswith(o) or o in ("music", "mus") for o in only)]
    stingers = [s for s in cm.stingers() if not only or any(s.id.startswith(o) or o in ("music", "mus") for o in only)]
    for f in check_data(mf.ROOT / "game" / "data" / "audio"):
        log(f"FAIL  {f}")
        fails_total += 1
    metrics: dict[str, dict] = {}
    rows = []
    for t in tracks:
        m, fails = analyze_track(root, t, assets)
        for f in fails:
            log(f"FAIL  {f}")
            fails_total += 1
        if m:
            m["bpm_target"] = t.bpm
            metrics[t.id] = m
            rows.append(f"  {t.id:12s} {t.bpm:5.1f}bpm est {m['bpm_est']:6.1f}  mix {m['mix_lufs']:6.2f} LUFS {m['mix_tp']:5.2f} dBTP  cont {m['continuity']:4.2f}  "
                        f"scale {m['in_scale_pct']:4.1f}%  cen {m['centroid_hz']:5.0f}  {sum(s['bytes'] for s in m['stems'].values()) / 1e6:5.2f} MB")
    for r in rows:
        log(r)
    smetrics: dict[str, dict] = {}
    for s in stingers:
        m, fails = analyze_stinger(root, s, assets)
        for f in fails:
            log(f"FAIL  {f}")
            fails_total += 1
        if m:
            smetrics[s.id] = m
    if smetrics:
        log(f"stingers: {len(smetrics)} checked, " + ", ".join(f"{k.split('/')[-1]} {v['duration_s']}s {v['lufs_i']}LU" for k, v in list(smetrics.items())[:4]) + " ...")
    qa_update: dict = {}
    dist = distinctness(metrics)
    if dist:
        base = man.get("qa", {}).get("distinct_music")
        if base and dist["min"] < base["min"] * (1.0 - DISTINCT_DROP):
            log(f"FAIL  music palettes: closest pair {dist['pair']} distance {dist['min']} < 80% of baseline {base['min']}")
            fails_total += 1
        elif not base or dist["min"] > base["min"]:
            qa_update["distinct_music"] = dist
        log(f"music distinctiveness (closest pair of the 8 combat mixes): {dist['min']} {dist['pair']}")
    total = sum(e["bytes"] for k, e in assets.items() if k.startswith("mus/"))
    log(f"music total {total / 1e6:.2f} MB in {sum(1 for k in assets if k.startswith('mus/'))} files (budget 46 MB)")
    if total > 46_000_000:
        log("FAIL  music total exceeds the 46 MB budget")
        fails_total += 1
    if sheets:
        write_sheets(metrics, smetrics, tracks, stingers, root, assets)
    return fails_total, qa_update


def write_sheets(metrics: dict, smetrics: dict, tracks, stingers, root: Path, assets: dict) -> None:
    """Audition / analysis sheets in .cache/audio/sheets: one flavour sheet (8 combat mixes), one calm sheet, per-track stem
    sheets, one stinger sheet."""
    import manifest as mf
    out = mf.ROOT / ".cache" / "audio" / "sheets"
    out.mkdir(parents=True, exist_ok=True)

    def sub(m: dict) -> str:
        return f"{m['bpm_target']:g} bpm (est {m['bpm_est']:g})  {m['mix_lufs']} LUFS  {m['mix_tp']} dBTP  scale {m['in_scale_pct']}%  cont {m['continuity']}"
    for style in ("combat", "calm"):
        items = [(f"{t.id}  {t.mode} root {t.root_midi}", metrics[t.id]["_mix"], sub(metrics[t.id])) for t in tracks if t.style == style and t.id in metrics and t.faction]
        if items:
            analyze.contact_sheet(items, str(out / f"music_flavours_{style}.png"), cols=2, cell_w=640, cell_h=150)
    for t in tracks:
        if t.id not in metrics or t.faction not in ("napc", None):
            continue
        items = []
        for stem in cm.STEMS:
            x = oggtools.decode(root / assets[f"{t.folder}/{stem}"]["file"])
            items.append((f"{t.id}/{stem}", x, f"{metrics[t.id]['stems'][stem]['lufs']} LUFS  seam {metrics[t.id]['stems'][stem]['seam']}"))
        analyze.contact_sheet(items, str(out / f"music_stems_{t.id.replace('.', '_')}.png"), cols=2, cell_w=640, cell_h=150)
    if smetrics:
        items = [(sid.split("/")[-1], m["_x"], f"{m['duration_s']} s  {m['lufs_i']} LUFS  {m['true_peak_db']} dBTP") for sid, m in sorted(smetrics.items())]
        for i in range(0, len(items), 12):
            analyze.contact_sheet(items[i:i + 12], str(out / f"music_stingers_{i // 12 + 1}.png"), cols=3, cell_w=430, cell_h=120)
