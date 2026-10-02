"""qa_assets.py - objective asset QA (audio spec 10.2): thresholds per class, budget, distinctiveness gate,
reproducibility gate.  Run through `build_all.py check [--verify] [--sheets] [--budget]`.

Everything is measured on the *decoded* shipped OGGs.  Assets of families without thresholds yet (music, voice,
responses: AUD-T4/T5) are counted in the budget but not classified."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import analyze  # noqa: E402
import catalog  # noqa: E402
import manifest as mf  # noqa: E402
import oggtools  # noqa: E402
from catalog import qa_thresholds as T  # noqa: E402

MAX_FILES, MAX_BYTES, MAX_BANK_BYTES = 2500, 110_000_000, 45_000_000
DISTINCT_DROP = 0.20


def _spec_for(specs: dict[str, catalog.AssetSpec], aid: str):
    if aid in specs:
        return specs[aid]
    base = aid.rsplit("_", 1)[0]
    return specs.get(base)


def check_asset(job: tuple) -> tuple[str, dict, list[str], list[str]]:
    """Worker: returns (asset_id, metrics, failures, warnings)."""
    aid, entry, spec_fields, root = job
    root = Path(root)
    fails: list[str] = []
    warns: list[str] = []
    spec = catalog.AssetSpec(**spec_fields)
    cls = T.classify(spec, aid)
    lim = T.LIMITS[cls]
    p = root / entry["file"]
    if not p.exists():
        return aid, {}, [f"file missing: {entry['file']}"], warns
    import hashlib
    if hashlib.sha256(p.read_bytes()).hexdigest() != entry["sha256"]:
        fails.append("sha256 differs from manifest")
    x = oggtools.decode(p)
    m = analyze.metrics(x, spec.loop)
    m["class"] = cls
    ch = 2 if spec.channels in ("stereo", "both") else 1
    if m["channels"] != ch:
        fails.append(f"channels {m['channels']} != {ch}")
    if entry.get("len_delta", 0) != 0:
        fails.append(f"OGG length delta {entry['len_delta']} samples")
    if "mono_file" in entry:
        xm = oggtools.decode(root / entry["mono_file"])
        if xm.ndim != 1:
            fails.append("mono twin is not mono")
        if len(xm) != len(x):
            fails.append("mono twin length differs")
        tpm = analyze.true_peak_db(xm)
        if tpm > lim.tp_max:
            fails.append(f"mono twin true peak {tpm:.2f} > {lim.tp_max}")
    if m["nan"]:
        fails.append("NaN samples")
    if abs(m["dc"]) >= T.DC_MAX:
        fails.append(f"DC {m['dc']}")
    if m["clipped_samples"]:
        fails.append(f"{m['clipped_samples']} clipped samples")
    if not spec.loop:
        if m["x0"] > T.X0_MAX:
            fails.append(f"first sample {m['x0']} > {T.X0_MAX}")
        if lim.ends_faded and m["x_end"] > T.XEND_MAX:
            fails.append(f"last sample {m['x_end']} > {T.XEND_MAX}")
    d = m["duration_s"]
    if not (lim.min_s <= d <= lim.max_s):
        fails.append(f"length {d}s outside {lim.min_s}-{lim.max_s}s")
    if m["true_peak_db"] > lim.tp_max:
        fails.append(f"true peak {m['true_peak_db']} > {lim.tp_max}")
    if lim.lufs_window and not (lim.lufs_window[0] <= m["lufs_i"] <= lim.lufs_window[1]):
        fails.append(f"LUFS {m['lufs_i']} outside {lim.lufs_window}")
    if lim.lufs_tol is not None and spec.lufs is not None and abs(m["lufs_i"] - spec.lufs) > lim.lufs_tol:
        fails.append(f"LUFS {m['lufs_i']} not within {lim.lufs_tol} LU of target {spec.lufs}")
    if lim.attack_ms_max is not None and m["attack_ms"] > lim.attack_ms_max:
        fails.append(f"attack {m['attack_ms']} ms > {lim.attack_ms_max}")
    if lim.centroid_min is not None and m["centroid_hz"] < lim.centroid_min:
        fails.append(f"centroid {m['centroid_hz']} Hz < {lim.centroid_min}")
    if lim.band_200_2k_min is not None and m["band_200_2k_pct"] < lim.band_200_2k_min:
        fails.append(f"200 Hz-2 kHz share {m['band_200_2k_pct']}% < {lim.band_200_2k_min}")
    if lim.lf_corr_min is not None and m["channels"] == 2 and m["lf_corr"] < lim.lf_corr_min:
        fails.append(f"LF L/R correlation {m['lf_corr']} < {lim.lf_corr_min}")
    if lim.seam_max is not None:
        if m.get("seam_score", 0) > lim.seam_max:
            fails.append(f"decoded seam {m['seam_score']} > {lim.seam_max}")
        if (entry.get("seam_src") or 0) > lim.seam_max:
            fails.append(f"source seam {entry['seam_src']} > {lim.seam_max}")
    if entry.get("snr_db", 99) < lim.snr_min:
        fails.append(f"codec SNR {entry['snr_db']} dB < {lim.snr_min}")
    return aid, m, fails, warns


def _distinctiveness(metrics: dict[str, dict], specs: dict) -> dict:
    """Per weapon family: closest pair of the 8 factions in normalised feature space."""
    fam: dict[str, dict[str, list]] = {}
    for aid, m in metrics.items():
        p = aid.split("/")
        if p[:2] != ["sfx", "weapon_fx"]:
            continue
        arch = p[3].rsplit("_", 1)[0]
        fam.setdefault(arch, {}).setdefault(p[2], []).append(analyze.feature_vector(m))
    out = {}
    for arch, byf in sorted(fam.items()):
        facs = sorted(byf)
        if len(facs) < 2:
            continue
        v = np.stack([np.mean(byf[f], axis=0) for f in facs])
        sd = np.maximum(v.std(axis=0), 0.03)
        z = v / sd
        best = (1e9, ("", ""))
        for i in range(len(facs)):
            for j in range(i + 1, len(facs)):
                dist = float(np.linalg.norm(z[i] - z[j]))
                if dist < best[0]:
                    best = (dist, (facs[i], facs[j]))
        out[arch] = {"min": round(best[0], 3), "pair": list(best[1])}
    return out


def run(verify: bool = False, sheets: bool = False, budget: bool = False, jobs: int = 4, only: list[str] | None = None) -> int:
    t0 = time.time()
    root = mf.AUDIO_ROOT
    man = mf.load(root)
    assets = man["assets"]
    if not assets:
        print("no audio_manifest.json - run build_all.py sfx first")
        return 1
    specs = {s.id: s for s in catalog.all_specs()}
    fails_total = 0
    # -- catalog coverage -------------------------------------------------------------------------
    expected = {aid for s in specs.values() for _, aid in catalog.asset_ids(s)}
    have = {a for a in assets if a.startswith(mf.SFX_PREFIXES)}
    for a in sorted(expected - have):
        print(f"FAIL  {a}: in catalog but missing from manifest")
        fails_total += 1
    for a in sorted(have - expected):
        print(f"FAIL  {a}: in manifest but not in catalog (stale)")
        fails_total += 1
    # -- per-asset checks ---------------------------------------------------------------------------
    todo = []
    for aid in sorted(have & expected):
        spec = _spec_for(specs, aid)
        if only and not any(aid.startswith(o) or aid == o or spec.recipe == o for o in only):
            continue
        todo.append((aid, assets[aid], {k: getattr(spec, k) for k in spec.__dataclass_fields__}, str(root)))
    results = []
    if jobs <= 1:
        results = [check_asset(j) for j in todo]
    else:
        import multiprocessing as mp
        from concurrent.futures import ProcessPoolExecutor
        with ProcessPoolExecutor(max_workers=jobs, mp_context=mp.get_context("spawn")) as ex:
            results = list(ex.map(check_asset, todo, chunksize=4))
    metrics: dict[str, dict] = {}
    by_class: dict[str, list[int]] = {}
    for aid, m, fails, warns in results:
        metrics[aid] = m
        c = m.get("class", "?")
        by_class.setdefault(c, [0, 0])
        by_class[c][0] += 1
        for f in fails:
            print(f"FAIL  {aid}: {f}")
            fails_total += 1
        by_class[c][1] += 1 if fails else 0
        for w in warns:
            print(f"warn  {aid}: {w}")
    print("class summary (assets / failing): " + ", ".join(f"{c} {a}/{f}" for c, (a, f) in sorted(by_class.items())))
    # -- distinctiveness gate -----------------------------------------------------------------------
    dist = _distinctiveness(metrics, specs)
    if dist:
        base = man.get("qa", {}).get("distinct", {})
        new_base = dict(base)
        for arch, d in dist.items():
            b = base.get(arch)
            if b and d["min"] < b["min"] * (1.0 - DISTINCT_DROP):
                print(f"FAIL  weapon flavours {arch}: closest pair {d['pair']} distance {d['min']} < 80% of baseline {b['min']}")
                fails_total += 1
            elif not b or d["min"] > b["min"]:
                new_base[arch] = d
        print("flavour distinctiveness (closest pair per family): " + ", ".join(f"{a} {d['min']}" for a, d in dist.items()))
        if new_base != base and fails_total == 0 and not only:
            man.setdefault("qa", {})["distinct"] = new_base
            mf.write_if_changed(root / "audio_manifest.json", mf.dumps(man))
            print("distinctiveness baseline recorded in the manifest")
    # -- budget ---------------------------------------------------------------------------------------
    files = bytes_ = 0
    bank_bytes: dict[str, int] = {}
    cat_bytes: dict[str, list[int]] = {}
    for aid, e in assets.items():
        n, b = mf.file_count_bytes(e)
        files, bytes_ = files + n, bytes_ + b
        bank_bytes[e["bank"]] = bank_bytes.get(e["bank"], 0) + b
        c = cat_bytes.setdefault(e["category"], [0, 0])
        c[0], c[1] = c[0] + n, c[1] + b
    for b, v in bank_bytes.items():
        if v > MAX_BANK_BYTES:
            print(f"FAIL  bank {b}: {v / 1e6:.1f} MB > {MAX_BANK_BYTES / 1e6:.0f} MB")
            fails_total += 1
    if files > MAX_FILES or bytes_ > MAX_BYTES:
        print(f"FAIL  budget: {files} files / {bytes_ / 1e6:.1f} MB exceeds {MAX_FILES} / {MAX_BYTES / 1e6:.0f} MB")
        fails_total += 1
    print(f"budget: {files} files, {bytes_ / 1e6:.2f} MB of {MAX_BYTES / 1e6:.0f} MB (caps: {MAX_FILES} files, {MAX_BANK_BYTES / 1e6:.0f} MB per bank)")
    if budget:
        for c, (n, b) in sorted(cat_bytes.items()):
            print(f"  {c:12s} {n:5d} files {b / 1e6:7.2f} MB")
        for bk, b in sorted(bank_bytes.items()):
            print(f"  bank {bk:12s} {b / 1e6:7.2f} MB")
    # -- music (AUD-T4) and voice (AUD-T5) -----------------------------------------------------------------
    fails_total += _media_checks(man, root, only or [], sheets, jobs, verify)
    # -- sheets ---------------------------------------------------------------------------------------------
    if sheets:
        from qa import sheets as sh
        ids = [a for a in sorted(have & expected) if not only or any(a.startswith(o) or a == o for o in only)]
        out = mf.ROOT / ".cache" / "audio" / "sheets"
        paths = sh.build(root, man, ids, out)
        print(f"{len(paths)} contact sheets in {out}")
    # -- reproducibility ----------------------------------------------------------------------------------------
    if verify:
        fails_total += verify_render(man, specs, jobs, only)
    print(f"check {'FAILED' if fails_total else 'ok'}: {fails_total} failure(s) in {time.time() - t0:.1f}s")
    return 1 if fails_total else 0


MUSIC_KEYS = ("mus", "music", "napc.", "nec.", "olm.", "def.", "pd.", "han.", "ae.", "sap.", "menu")
VOICE_KEYS = ("vox", "voice")
RESP_KEYS = ("resp", "responses")


def _wants(only: list[str], keys: tuple[str, ...]) -> bool:
    return not only or any(o.startswith(keys) for o in only)


def _media_checks(man: dict, root: Path, only: list[str], sheets: bool, jobs: int, verify: bool) -> int:
    """Music (stems, stingers) and voice (announcer lines, unit responses) QA; they classify by their own rules (spec 10.2)."""
    assets = man["assets"]
    fails = 0
    qa_up: dict = {}
    if any(a.startswith("mus/") for a in assets) and _wants(only, MUSIC_KEYS):
        from music import verify as mverify
        n, up = mverify.run(root, man, only=[o for o in only if o.startswith(MUSIC_KEYS)] or None, sheets=sheets)
        fails += n
        qa_up.update(up)
    if any(a.startswith(("vox/", "resp/")) for a in assets) and (_wants(only, VOICE_KEYS) or _wants(only, RESP_KEYS)):
        from voice import verify as vverify
        n, up = vverify.run(root, man, only=[o for o in only if o.startswith(VOICE_KEYS + RESP_KEYS)] or None, sheets=sheets)
        fails += n
        qa_up.update(up)
    if qa_up and fails == 0 and not only:
        man.setdefault("qa", {}).update(qa_up)
        mf.write_if_changed(root / "audio_manifest.json", mf.dumps(man))
        print("music / voice distinctiveness baselines recorded in the manifest")
    if verify and (assets.keys() & {a for a in assets if a.startswith(("mus/", "vox/", "resp/"))}):
        fails += verify_render_media(man, jobs, only)
    return fails


def verify_render_media(man: dict, jobs: int, only: list[str]) -> int:
    """Re-render music / voice into a scratch dir and compare with the manifest (hashes on identical toolchains, metrics otherwise)."""
    import shutil
    tmp = mf.ROOT / ".cache" / "audio" / "verify_media"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    res: dict[str, dict] = {}
    if _wants(only, MUSIC_KEYS):
        from music import mixdown
        js, _, _ = mixdown.plan({}, [o for o in only if o.startswith(MUSIC_KEYS)], True, tmp)
        r, _ = mixdown.run_jobs(js, jobs)
        res.update(r)
    from voice import build as vb
    for kind, keys in (("voice", VOICE_KEYS), ("responses", RESP_KEYS), ("barks", RESP_KEYS)):
        if _wants(only, keys):
            js, _, _ = vb.plan(kind, {}, [o for o in only if o.startswith(keys)], True, tmp)
            r, _ = vb.run_jobs(js, jobs)
            res.update(r)
    same_env = man.get("generator") == mf.generator_info()
    bad = 0
    for aid, e in sorted(res.items()):
        old = man["assets"].get(aid)
        if old is None:
            continue
        if same_env:
            if old.get("sha256") != e.get("sha256") or old.get("pcm_sha256") != e.get("pcm_sha256"):
                print(f"FAIL  verify {aid}: sha256 differs")
                bad += 1
        elif not (abs(old["lufs_i"] - e["lufs_i"]) <= 0.3 and abs(old["true_peak_db"] - e["true_peak_db"]) <= 0.3
                  and old["duration_samples"] == e["duration_samples"]):
            print(f"FAIL  verify {aid}: metrics differ across toolchains")
            bad += 1
    print(f"verify (media): {len(res)} assets re-rendered, {'byte/hash comparison' if same_env else 'metric comparison'}, {bad} mismatch(es)")
    shutil.rmtree(tmp, ignore_errors=True)
    return bad


def verify_render(man: dict, specs: dict, jobs: int, only: list[str] | None) -> int:
    """Re-render into a scratch dir and compare with the committed manifest (hashes on identical toolchains)."""
    import shutil
    import build_all
    import sfx
    tmp = mf.ROOT / ".cache" / "audio" / "verify"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    fns = sfx.load_all()
    import render
    js = []
    for spec in specs.values():
        rh = render.recipe_hash(spec, fns[spec.recipe])
        for v, aid in catalog.asset_ids(spec):
            if only and not build_all.matches(only, spec, aid):
                continue
            js.append((spec.id, v, aid, str(tmp), rh))
    res = build_all.run_jobs(js, jobs)
    res.pop("__errors__", None)
    same_env = man.get("generator") == mf.generator_info()
    bad = 0
    for aid, e in sorted(res.items()):
        old = man["assets"].get(aid)
        if old is None:
            continue
        if same_env:
            for k in ("sha256", "pcm_sha256", "mono_sha256"):
                if old.get(k) != e.get(k):
                    print(f"FAIL  verify {aid}: {k} differs")
                    bad += 1
                    break
        else:
            ok = (abs(old["lufs_i"] - e["lufs_i"]) <= 0.3 and abs(old["true_peak_db"] - e["true_peak_db"]) <= 0.3
                  and old["duration_samples"] == e["duration_samples"])
            if not ok:
                print(f"FAIL  verify {aid}: metrics differ across toolchains")
                bad += 1
    print(f"verify: {len(res)} assets re-rendered, {'byte/hash comparison' if same_env else 'metric comparison (toolchain differs)'}, {bad} mismatch(es)")
    shutil.rmtree(tmp, ignore_errors=True)
    return bad
