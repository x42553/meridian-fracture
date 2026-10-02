#!/usr/bin/env python3
"""build_all.py - CLI driver of the audio generation pipeline (audio spec 7.8).

  build_all.py sfx [--only a,b*] [--jobs N] [--force]     regenerate the SFX library (weapons ... ambience)
  build_all.py check [--verify] [--sheets] [--budget]      QA thresholds + budget + gates (+ deterministic re-render)
  build_all.py music [--only napc,mus/stinger] [--force]   AUD-T4: 17 tracks x 4 stems + 25 stingers
  build_all.py voice [--engine kokoro] | responses | barks   AUD-T5: 513 announcer lines, 648 unit response bleeps, 624 optional TTS barks
  build_all.py events                                       hook of AUD-T6
  build_all.py all                                         sfx + every hook that is available

--only takes recipe names, asset ids / prefixes (`sfx/weapon`), or globs (`sfx/impact/bullet_*`).  The build is
incremental: an asset is re-rendered only when its recipe_hash changed or its file is missing.
Run with the venv from bootstrap.py (the script re-executes itself under it when the current interpreter lacks numpy).
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import bootstrap  # noqa: E402

bootstrap.ensure_toolchain_or_reexec(str(Path(__file__).resolve()))

import catalog  # noqa: E402
import manifest  # noqa: E402
import render  # noqa: E402
import sfx  # noqa: E402


def matches(patterns: list[str], spec: catalog.AssetSpec, asset_id: str) -> bool:
    if not patterns:
        return True
    for p in patterns:
        if p == spec.recipe or p == spec.id or p == asset_id:
            return True
        if any(c in p for c in "*?["):
            if fnmatch.fnmatch(asset_id, p):
                return True
        elif asset_id.startswith(p.rstrip("/") + "/") or asset_id.startswith(p):
            return True
    return False


def plan(only: list[str], force: bool, prev_assets: dict, out_root: Path):
    """Return (jobs, carried, all_expected_ids) - jobs = assets to (re)render."""
    fns = sfx.load_all()
    jobs, carried, expected = [], {}, set()
    for spec in catalog.all_specs():
        if spec.recipe not in fns:
            raise SystemExit(f"{spec.id}: unknown recipe {spec.recipe!r}")
        rh = render.recipe_hash(spec, fns[spec.recipe])
        for v, aid in catalog.asset_ids(spec):
            expected.add(aid)
            old = prev_assets.get(aid)
            files = catalog.files_of(spec, aid)
            intact = (old is not None and old.get("recipe_hash") == rh
                      and all((out_root / f).exists() for f in files.values())
                      and (out_root / old["file"]).stat().st_size == old["bytes"])
            selected = matches(only, spec, aid)
            if intact and not (force and selected):
                carried[aid] = old
            elif selected:
                jobs.append((spec.id, v, aid, str(out_root), rh))
            elif old is not None and intact:
                carried[aid] = old
            elif old is not None:
                carried[aid] = old          # not selected and stale: keep the old entry (a full build fixes it)
    return jobs, carried, expected


def run_jobs(jobs: list[tuple], n_jobs: int) -> dict[str, dict]:
    results: dict[str, dict] = {}
    errors = 0
    prio = {"amb": 0, "sfx/sw": 1, "sfx/exp": 2, "sfx/col": 2, "sfx/pow": 3}
    jobs = sorted(jobs, key=lambda j: min([v for k, v in prio.items() if j[2].startswith(k)] or [9]))
    t0 = time.time()

    def take(aid: str, res) -> None:
        nonlocal errors
        if isinstance(res, str):
            errors += 1
            print(f"FAILED {aid}\n{res}", file=sys.stderr)
        else:
            results[aid] = res

    if n_jobs <= 1 or len(jobs) <= 2:
        for j in jobs:
            take(*render.worker(j))
    else:
        import multiprocessing as mp
        from concurrent.futures import ProcessPoolExecutor
        with ProcessPoolExecutor(max_workers=n_jobs, mp_context=mp.get_context("spawn")) as ex:
            for i, (aid, res) in enumerate(ex.map(render.worker, jobs, chunksize=2), 1):
                take(aid, res)
                if i % 50 == 0:
                    print(f"  ... {i}/{len(jobs)} ({time.time() - t0:.0f}s)", flush=True)
    if errors:
        print(f"{errors} asset(s) failed", file=sys.stderr)
    results["__errors__"] = {"n": errors}
    return results


def cmd_sfx(a: argparse.Namespace) -> int:
    t0 = time.time()
    root = Path(a.out) if a.out else manifest.AUDIO_ROOT
    prev = manifest.load(root)
    only = [p for p in a.only.split(",") if p]
    jobs, carried, expected = plan(only, a.force, prev["assets"], root)
    print(f"sfx: {len(expected)} assets in catalog, {len(jobs)} to render, {len(carried)} up to date")
    res = run_jobs(jobs, a.jobs) if jobs else {"__errors__": {"n": 0}}
    errors = res.pop("__errors__")["n"]
    assets = {**{k: v for k, v in prev["assets"].items() if not k.startswith(manifest.SFX_PREFIXES)}, **carried, **res}
    if not only:                                       # full build: drop assets that left the catalog
        stale = [k for k in assets if k.startswith(manifest.SFX_PREFIXES) and k not in expected]
        for k in stale:
            e = assets.pop(k)
            for f in (e["file"], e.get("mono_file")):
                if f:
                    for suffix in ("", ".import"):
                        (root / (f + suffix)).unlink(missing_ok=True)
        if stale:
            print(f"removed {len(stale)} stale assets")
    rerendered = set(res)
    manifest.write_all(assets, prev, root=root, rerendered=rerendered)
    tot = sum(e["bytes"] + e.get("mono_bytes", 0) for k, e in assets.items() if k.startswith(manifest.SFX_PREFIXES))
    print(f"sfx done in {time.time() - t0:.1f}s: {len(res)} rendered, {tot / 1e6:.2f} MB of SFX in {root}")
    return 1 if errors else 0


def _drop_stale(assets: dict, owned, expected: set[str], root: Path) -> int:
    """Remove owned assets (`owned(id)`) that left the catalog (full builds only); returns how many."""
    stale = [k for k in assets if owned(k) and k not in expected]
    for k in stale:
        e = assets.pop(k)
        for f in (e["file"], e.get("mono_file")):
            if f:
                for suffix in ("", ".import"):
                    (root / (f + suffix)).unlink(missing_ok=True)
    return len(stale)


def cmd_music(a: argparse.Namespace) -> int:
    """AUD-T4: 17 tracks x 4 stems + 25 stingers (music/mixdown.py); incremental by recipe hash."""
    from music import mixdown
    t0 = time.time()
    root = Path(a.out) if a.out else manifest.AUDIO_ROOT
    prev = manifest.load(root)
    only = [p for p in a.only.split(",") if p]
    jobs, carried, expected = mixdown.plan(prev["assets"], only, a.force, root)
    print(f"music: {len(expected)} assets in catalog, {len(jobs)} job(s) to render, {len(carried)} up to date")
    res, errors = mixdown.run_jobs(jobs, a.jobs) if jobs else ({}, 0)
    assets = {**{k: v for k, v in prev["assets"].items() if not k.startswith(mixdown.MUSIC_PREFIX)}, **carried, **res}
    if not only:
        n = _drop_stale(assets, lambda k: k.startswith(mixdown.MUSIC_PREFIX), expected, root)
        if n:
            print(f"removed {n} stale music assets")
    manifest.write_all(assets, prev, root=root)
    tot = sum(e["bytes"] for k, e in assets.items() if k.startswith(mixdown.MUSIC_PREFIX))
    print(f"music done in {time.time() - t0:.1f}s: {len(res)} rendered, {tot / 1e6:.2f} MB of music in {root}")
    return 1 if errors else 0


def _cmd_voice_family(a: argparse.Namespace, kind: str) -> int:
    """AUD-T5: `voice` = announcer lines (vox/), `responses` = unit acknowledgement bleeps (resp/), `barks` = optional TTS barks (resp/<f>/voice/)."""
    from voice import build as vb
    t0 = time.time()
    root = Path(a.out) if a.out else manifest.AUDIO_ROOT
    prev = manifest.load(root)
    only = [p for p in a.only.split(",") if p]
    jobs, carried, expected = vb.plan(kind, prev["assets"], only, a.force, root, a.engine)
    print(f"{kind}: {len(expected)} assets in catalog, {len(jobs)} to render, {len(carried)} up to date")
    res, errors = vb.run_jobs(jobs, a.jobs) if jobs else ({}, 0)
    assets = {**{k: v for k, v in prev["assets"].items() if not vb.owns(kind, k)}, **carried, **res}
    if not only:
        n = _drop_stale(assets, lambda k: vb.owns(kind, k), expected, root)
        if n:
            print(f"removed {n} stale {kind} assets")
    manifest.write_all(assets, prev, root=root)
    tot = sum(e["bytes"] for k, e in assets.items() if vb.owns(kind, k))
    print(f"{kind} done in {time.time() - t0:.1f}s: {len(res)} rendered, {tot / 1e6:.2f} MB in {root}")
    return 1 if errors else 0


def cmd_check(a: argparse.Namespace) -> int:
    from qa import qa_assets
    return qa_assets.run(verify=a.verify, sheets=a.sheets, budget=a.budget, jobs=a.jobs, only=[p for p in a.only.split(",") if p])


def cmd_hook(name: str) -> int:
    print(f"{name}: not available in this checkout (owned by a later audio task; see audio spec 11)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("commands", nargs="+", choices=["sfx", "music", "voice", "responses", "barks", "events", "check", "all"])
    ap.add_argument("--only", default="", help="comma list: recipe names, asset ids/prefixes, globs")
    ap.add_argument("--jobs", type=int, default=max(1, min(8, (os.cpu_count() or 2) - 1)))
    ap.add_argument("--force", action="store_true", help="re-render the selected assets even when up to date")
    ap.add_argument("--out", default="", help="output root instead of game/assets/audio (scratch builds)")
    ap.add_argument("--verify", action="store_true", help="check: re-render to a temp dir and compare hashes")
    ap.add_argument("--sheets", action="store_true", help="check: write spectrogram contact sheets to .cache/audio/sheets")
    ap.add_argument("--budget", action="store_true", help="check: print the size budget table")
    ap.add_argument("--engine", default="kokoro", choices=["kokoro", "piper"], help="voice engine (piper = fast iteration with CC0 voices, not for shipping)")
    a = ap.parse_args()
    cmds = list(dict.fromkeys(a.commands))
    if "all" in cmds:
        cmds = ["sfx", "music", "voice", "responses", "barks", "events", "check"]
    rc = 0
    for c in cmds:
        if c == "sfx":
            rc |= cmd_sfx(a)
        elif c == "music":
            rc |= cmd_music(a)
        elif c in ("voice", "responses", "barks"):
            rc |= _cmd_voice_family(a, c)
        elif c == "check":
            rc |= cmd_check(a)
        else:
            rc |= cmd_hook(c)
    return rc


if __name__ == "__main__":
    sys.exit(main())
