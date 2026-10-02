"""verify.py - objective QA of the shipped voice files (audio spec 10.2 rows "announcer lines" and "unit responses") + audition sheets.

Announcer lines: 0.3-6 s, mono, <= -1.5 dBTP, -18.0 +- 1.5 LUFS-I, codec SNR >= 18 dB, > 6 kHz energy share <= 8 % (computer / officer)
or <= 1 % (radio chain).  Unit responses: 0.15-0.7 s, mono, <= -2.0 dBTP, -20 +- 2 LUFS, squelch present (spectral flux and level in
the first 70 ms).  Every file: sha256 = manifest, length delta 0, no NaN, |DC| < 0.005, first / last sample, no clipping.  Catalogue:
every line of announcer.json has a caption (V-AUD-28) and a file for every pack and take; every response id exists; PROVENANCE
licence_model is one of the allowed set.  Response palettes: the 8 factions must stay distinguishable (closest pair of the
palette feature centroids must not shrink by > 20 % against the baseline recorded in the manifest under qa.distinct_resp).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

import analyze
import manifest as mf
import oggtools
import provenance
from catalog import voice as cv
from dsp import SR

DISTINCT_DROP = 0.20
ALLOWED_LICENCES = ("Apache-2.0", "MIT", "CC0-1.0", "CC-BY-4.0", "procedural")


def squelch_metrics(x: np.ndarray) -> tuple[float, float]:
    """(level of the first 70 ms relative to the loudest 20 ms window in dB, spectral flux of the first 70 ms)."""
    n70 = int(0.07 * SR)
    head = x[:n70]
    w = int(0.02 * SR)
    win_rms = [float(np.sqrt(np.mean(x[i:i + w] ** 2))) for i in range(0, max(len(x) - w, 1), w // 2)]
    rel = 20 * np.log10((float(np.sqrt(np.mean(head ** 2))) + 1e-9) / (max(win_rms) + 1e-9))
    n, hop = 256, 64
    fr = np.lib.stride_tricks.sliding_window_view(head, n)[::hop] * np.hanning(n)
    mag = np.log10(np.abs(np.fft.rfft(fr, axis=1)) + 1e-6)
    flux = float(np.maximum(np.diff(mag, axis=0), 0).sum(axis=1).mean()) if len(mag) > 1 else 0.0
    return float(rel), flux


def _common(aid: str, e: dict, root: Path, fails: list[str]):
    p = root / e["file"]
    if not p.exists():
        fails.append(f"{aid}: file missing {e['file']}")
        return None
    import hashlib
    if hashlib.sha256(p.read_bytes()).hexdigest() != e["sha256"]:
        fails.append(f"{aid}: sha256 differs from manifest")
    x = oggtools.decode(p)
    if x.ndim != 1:
        fails.append(f"{aid}: not mono")
        return None
    if not np.all(np.isfinite(x)):
        fails.append(f"{aid}: NaN")
    if e.get("len_delta", 0) != 0:
        fails.append(f"{aid}: OGG length delta {e['len_delta']}")
    if abs(float(np.mean(x))) >= 0.005:
        fails.append(f"{aid}: DC {np.mean(x):.4f}")
    if abs(x[0]) > 0.02 or abs(x[-1]) > 0.003:
        fails.append(f"{aid}: edges x0 {abs(x[0]):.4f} x_end {abs(x[-1]):.4f}")
    if int(np.sum(np.abs(x) >= 0.9999)):
        fails.append(f"{aid}: clipped samples")
    return x


def check_lines(root: Path, assets: dict, lines: list, log=print) -> tuple[int, dict]:
    fails: list[str] = []
    met: dict[str, dict] = {}
    for v in lines:
        e = assets.get(v.asset_id)
        if e is None:
            fails.append(f"{v.asset_id}: missing from manifest")
            continue
        x = _common(v.asset_id, e, root, fails)
        if x is None:
            continue
        m = analyze.metrics(x)
        d = m["duration_s"]
        if not (cv.LINE_SECONDS[0] <= d <= cv.LINE_SECONDS[1]):
            fails.append(f"{v.asset_id}: length {d}s outside {cv.LINE_SECONDS}")
        if m["true_peak_db"] > cv.LINE_TP:
            fails.append(f"{v.asset_id}: true peak {m['true_peak_db']} > {cv.LINE_TP}")
        if abs(m["lufs_i"] - cv.LINE_LUFS) > cv.LINE_LUFS_TOL:
            fails.append(f"{v.asset_id}: {m['lufs_i']} LUFS not within {cv.LINE_LUFS_TOL} of {cv.LINE_LUFS}")
        if e.get("snr_db", 99) < cv.LINE_SNR_MIN:
            fails.append(f"{v.asset_id}: codec SNR {e['snr_db']} dB < {cv.LINE_SNR_MIN}")
        if m["band_gt6k_pct"] > cv.HF_SHARE_MAX[v.chain]:
            fails.append(f"{v.asset_id}: {m['band_gt6k_pct']}% of the energy above 6 kHz (max {cv.HF_SHARE_MAX[v.chain]} for {v.chain})")
        met[v.asset_id] = {k: m[k] for k in ("duration_s", "lufs_i", "true_peak_db", "band_gt6k_pct", "centroid_hz")} | {"snr_db": e.get("snr_db"), "bytes": e["bytes"], "chain": v.chain}
    for f in fails:
        log(f"FAIL  {f}")
    return len(fails), met


def check_responses(root: Path, assets: dict, specs: list, log=print) -> tuple[int, dict, dict]:
    fails: list[str] = []
    met: dict[str, dict] = {}
    feats: dict[str, list[np.ndarray]] = {}
    from voice import responses
    for s in specs:
        e = assets.get(s.asset_id)
        if e is None:
            fails.append(f"{s.asset_id}: missing from manifest")
            continue
        x = _common(s.asset_id, e, root, fails)
        if x is None:
            continue
        m = analyze.metrics(x)
        d = m["duration_s"]
        if not (cv.RESP_SECONDS[0] <= d <= cv.RESP_SECONDS[1]):
            fails.append(f"{s.asset_id}: length {d}s outside {cv.RESP_SECONDS}")
        if m["true_peak_db"] > cv.RESP_TP:
            fails.append(f"{s.asset_id}: true peak {m['true_peak_db']} > {cv.RESP_TP}")
        if abs(m["lufs_i"] - cv.RESP_LUFS) > cv.RESP_LUFS_TOL:
            fails.append(f"{s.asset_id}: {m['lufs_i']} LUFS not within {cv.RESP_LUFS_TOL} of {cv.RESP_LUFS}")
        rel, flux = squelch_metrics(x)
        if rel < -26.0 or flux < 0.15:
            fails.append(f"{s.asset_id}: squelch not present in the first 70 ms (level {rel:.1f} dB, flux {flux:.2f})")
        feats.setdefault(s.faction, []).append(responses.features(x))
        met[s.asset_id] = {"duration_s": d, "lufs_i": m["lufs_i"], "true_peak_db": m["true_peak_db"], "squelch_db": round(rel, 1), "flux": round(flux, 2), "bytes": e["bytes"]}
    for f in fails:
        log(f"FAIL  {f}")
    return len(fails), met, feats


def check_barks(root: Path, assets: dict, barks: list, log=print) -> tuple[int, dict]:
    """Optional TTS barks (`resp/<f>/voice/...`): 0.25-2.5 s, -20 +- 2 LUFS, <= -2.0 dBTP, SNR >= 14 dB, radio band (> 6 kHz <= 1 %)."""
    fails: list[str] = []
    met: dict[str, dict] = {}
    for b in barks:
        e = assets.get(b.asset_id)
        if e is None:
            fails.append(f"{b.asset_id}: missing from manifest")
            continue
        x = _common(b.asset_id, e, root, fails)
        if x is None:
            continue
        m = analyze.metrics(x)
        if not (cv.BARK_SECONDS[0] <= m["duration_s"] <= cv.BARK_SECONDS[1]):
            fails.append(f"{b.asset_id}: length {m['duration_s']}s outside {cv.BARK_SECONDS}")
        if m["true_peak_db"] > cv.RESP_TP:
            fails.append(f"{b.asset_id}: true peak {m['true_peak_db']} > {cv.RESP_TP}")
        if abs(m["lufs_i"] - cv.RESP_LUFS) > cv.RESP_LUFS_TOL:
            fails.append(f"{b.asset_id}: {m['lufs_i']} LUFS not within {cv.RESP_LUFS_TOL} of {cv.RESP_LUFS}")
        if e.get("snr_db", 99) < cv.BARK_SNR_MIN:
            fails.append(f"{b.asset_id}: codec SNR {e['snr_db']} dB < {cv.BARK_SNR_MIN}")
        if m["band_gt6k_pct"] > cv.BARK_HF_MAX:
            fails.append(f"{b.asset_id}: {m['band_gt6k_pct']}% above 6 kHz")
        met[b.asset_id] = {"duration_s": m["duration_s"], "lufs_i": m["lufs_i"], "bytes": e["bytes"]}
    ids = {b.asset_id for b in barks}
    for aid in sorted(a for a in assets if a.startswith("resp/") and "/voice/" in a and a not in ids):
        fails.append(f"{aid}: stale bark (not in responses.json barks)")
    for f in fails:
        log(f"FAIL  {f}")
    return len(fails), met


def distinctness(feats: dict[str, list[np.ndarray]]) -> dict:
    facs = sorted(feats)
    if len(facs) < 2:
        return {}
    v = np.stack([np.mean(feats[f], axis=0) for f in facs])
    sd = np.maximum(v.std(axis=0), 0.05)
    z = v / sd
    best, pair = 1e9, ("", "")
    for i in range(len(facs)):
        for j in range(i + 1, len(facs)):
            d = float(np.linalg.norm(z[i] - z[j]))
            if d < best:
                best, pair = d, (facs[i], facs[j])
    return {"min": round(best, 3), "pair": list(pair)}


def check_catalogue(assets: dict, log=print) -> int:
    """Captions and coverage: announcer.json is the caption source (V-AUD-28); every pack has every line with all its takes."""
    from voice import lines
    ann, _ = lines.load()
    fails = 0
    for lid, ln in ann["lines"].items():
        if not str(ln.get("text", "")).strip():
            log(f"FAIL  announcer line {lid}: empty caption")
            fails += 1
    ids = {v.asset_id for v in lines.all_lines()}
    for aid in sorted(ids - set(assets)):
        log(f"FAIL  {aid}: announcer asset missing")
        fails += 1
    for aid in sorted(a for a in assets if a.startswith("vox/") and a not in ids):
        log(f"FAIL  {aid}: stale announcer asset (not in announcer.json)")
        fails += 1
    return fails


def check_provenance(root: Path, assets: dict, log=print) -> int:
    p = root / "provenance.json"
    if not p.exists():
        log("FAIL  provenance.json missing")
        return 1
    prov = {r["file"]: r for r in json.loads(p.read_text())["files"]}
    fails = 0
    for aid, e in assets.items():
        if not aid.startswith(("vox/", "resp/")):
            continue
        r = prov.get(provenance.REL + e["file"])
        if r is None:
            log(f"FAIL  {aid}: no PROVENANCE entry")
            fails += 1
        elif r["licence_model"] not in ALLOWED_LICENCES:
            log(f"FAIL  {aid}: licence {r['licence_model']}")
            fails += 1
        elif (aid.startswith("vox/") or "/voice/" in aid) and (not r.get("model_sha256") or not r.get("voice") or not r.get("text")) and r.get("licence_model") != "CC0-1.0":
            log(f"FAIL  {aid}: PROVENANCE lacks model / voice / text")
            fails += 1
    return fails


def run(root: Path, man: dict, only: list[str] | None = None, sheets: bool = False, log=print) -> tuple[int, dict]:
    from voice import lines, responses
    assets = man["assets"]
    fails = check_catalogue(assets, log)
    ls = [v for v in lines.all_lines() if not only or any(v.asset_id.startswith(o) or o in ("voice", "vox") for o in only)]
    rs = [s for s in responses.all_specs() if not only or any(s.asset_id.startswith(o) or o in ("responses", "resp") for o in only)]
    nf, lmet = check_lines(root, assets, ls, log)
    fails += nf
    nf, rmet, feats = check_responses(root, assets, rs, log)
    fails += nf
    if any("/voice/" in a for a in assets if a.startswith("resp/")):
        bs = [b for b in lines.all_barks() if not only or any(b.asset_id.startswith(o) or o in ("barks", "resp", "responses") for o in only)]
        nf, bmet = check_barks(root, assets, bs, log)
        fails += nf
        if bmet:
            d = [m["duration_s"] for m in bmet.values()]
            log(f"barks: {len(bmet)} checked, {sum(m['bytes'] for m in bmet.values()) / 1e6:.2f} MB, length {min(d):.2f}-{max(d):.2f} s")
    fails += check_provenance(root, assets, log)
    qa_update: dict = {}
    dist = distinctness(feats)
    if dist and len(feats) == 8:
        base = man.get("qa", {}).get("distinct_resp")
        if base and dist["min"] < base["min"] * (1.0 - DISTINCT_DROP):
            log(f"FAIL  response palettes: closest pair {dist['pair']} distance {dist['min']} < 80% of baseline {base['min']}")
            fails += 1
        elif not base or dist["min"] > base["min"]:
            qa_update["distinct_resp"] = dist
        log(f"response palette distinctiveness (closest pair of 8): {dist['min']} {dist['pair']}")
    vb = sum(e["bytes"] for k, e in assets.items() if k.startswith("vox/"))
    rb = sum(e["bytes"] for k, e in assets.items() if k.startswith("resp/") and "/voice/" not in k)
    nv = sum(1 for k in assets if k.startswith("vox/"))
    nr = sum(1 for k in assets if k.startswith("resp/") and "/voice/" not in k)
    if lmet:
        d = [m["duration_s"] for m in lmet.values()]
        log(f"announcer: {len(lmet)} lines checked, {nv} files {vb / 1e6:.2f} MB ({vb / max(nv, 1) / 1024:.1f} KB avg), length {min(d):.2f}-{max(d):.2f} s, "
            f"LUFS {min(m['lufs_i'] for m in lmet.values()):.1f}..{max(m['lufs_i'] for m in lmet.values()):.1f}, "
            f"SNR min {min(m['snr_db'] for m in lmet.values()):.1f} dB, >6k max {max(m['band_gt6k_pct'] for m in lmet.values()):.2f}%")
    if rmet:
        d = [m["duration_s"] for m in rmet.values()]
        log(f"responses: {len(rmet)} clips checked, {nr} files {rb / 1e6:.2f} MB ({rb / max(nr, 1) / 1024:.1f} KB avg), length {min(d):.2f}-{max(d):.2f} s, "
            f"LUFS {min(m['lufs_i'] for m in rmet.values()):.1f}..{max(m['lufs_i'] for m in rmet.values()):.1f}, squelch min {min(m['squelch_db'] for m in rmet.values())} dB")
    if sheets:
        write_sheets(root, assets)
    return fails, qa_update


def write_sheets(root: Path, assets: dict) -> None:
    """Audition sheets in .cache/audio/sheets: voice_<pack>.png (six representative lines per pack), voice_choice.png (the same line in
    every pack: the voice-selection sheet), resp_<faction>.png (vehicle class, every type)."""
    out = mf.ROOT / ".cache" / "audio" / "sheets"
    out.mkdir(parents=True, exist_ok=True)

    def tile(aid: str, title: str):
        e = assets[aid]
        x = oggtools.decode(root / e["file"])
        m = analyze.metrics(x)
        return (title, x, f"{m['duration_s']}s  {m['lufs_i']} LUFS  {m['true_peak_db']} dBTP  >6k {m['band_gt6k_pct']}%  cen {m['centroid_hz']:.0f}")
    sample = ["base_under_attack", "construction_complete", "low_power", "sw_launch_detected", "insufficient_funds", "victory"]
    packs = sorted({k.split("/")[1] for k in assets if k.startswith("vox/")})
    for pack in packs:
        items = []
        for lid in sample:
            aid = next((a for a in (f"vox/{pack}/{lid}", f"vox/{pack}/{lid}_1") if a in assets), None)
            if aid:
                items.append(tile(aid, f"{pack}: {lid}"))
        if items:
            analyze.contact_sheet(items, str(out / f"voice_{pack}.png"), cols=2, cell_w=560, cell_h=130)
    choice = []
    for pack in packs:
        aid = next((a for a in ("vox/%s/base_under_attack_1" % pack, "vox/%s/base_under_attack" % pack) if a in assets), None)
        if aid:
            choice.append(tile(aid, f"{pack}: base_under_attack"))
    if choice:
        analyze.contact_sheet(choice, str(out / "voice_choice.png"), cols=3, cell_w=430, cell_h=120)
    facs = sorted({k.split("/")[1] for k in assets if k.startswith("resp/")})
    for f in facs:
        items = [tile(f"resp/{f}/vehicle_{t}_1", f"{f}: vehicle {t}") for t in ("select", "move", "attack", "deny", "special") if f"resp/{f}/vehicle_{t}_1" in assets]
        items += [tile(f"resp/{f}/{c}_select_1", f"{f}: {c} select") for c in ("infantry", "heavy", "air", "naval", "support", "structure") if f"resp/{f}/{c}_select_1" in assets]
        if items:
            analyze.contact_sheet(items, str(out / f"resp_{f}.png"), cols=3, cell_w=430, cell_h=110)
