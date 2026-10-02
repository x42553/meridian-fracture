#!/usr/bin/env python3
"""App-level replay proof (task REP2, docs/spec/ui.md 5.16.3, net.md 5.8).

Records a headless match through the real app path (`--autostart=match`, recording into a scratch replay folder), then plays the
recording back through the real app path (`--autostart=replay=<file>`: AppReplay -> AppMatchContext -> AppReplaySession ->
NetReplayPlayer) and compares what both processes print: the `APPTEST_CK tick= chain= checksum=` line at every 200th tick and the
`APPTEST_PLAYER` lines of the end-of-match model must be identical, the playback must report `APPTEST_REPLAY ok=1` (every recorded
CHECK matched), and a second playback with `--seek-demo` (forward, backward and end-of-file seeks first) must end identically.

    python3 tools/py/app_replay_proof.py                       one scenario (3 players, 4000 ticks), host OS
    python3 tools/py/app_replay_proof.py --ticks 6000 --players 4 --seed 7
    python3 tools/py/app_replay_proof.py --linux               the same inside the Debian container

Exit code 0 = every check passed; the last line is `APP_REPLAY_PROOF RESULT=OK|FAIL ...`.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List

ROOT = Path(__file__).resolve().parents[2]
GD = ROOT / "tools" / "gd"
SCENE = "res://src/app/boot.tscn"
EXIT_NOISE = re.compile(r"still in use at exit|leaked at exit|RID allocations")


def run(cmd: List[str], timeout: int) -> List[str]:
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
    return p.stdout.splitlines()


def pick(lines: List[str], prefix: str) -> List[str]:
    return [ln.strip() for ln in lines if ln.startswith(prefix)]


def errors(lines: List[str]) -> List[str]:
    return [ln for ln in lines if (ln.startswith("ERROR") or "SCRIPT ERROR" in ln) and not EXIT_NOISE.search(ln)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ticks", type=int, default=4000)
    ap.add_argument("--players", type=int, default=3)
    ap.add_argument("--humans", type=int, default=1)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--size", type=int, default=96)
    ap.add_argument("--linux", action="store_true", help="run inside the Debian container (tools/gd linux run)")
    ap.add_argument("--arch", default="amd64", choices=["amd64", "arm64"], help="with --linux: the container architecture")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args()

    # the container mounts only game/ (a mirror) and its cache dir (.cache/linux-<arch>/cache = /work/.cache): the scratch folder lives in the cache dir
    # (QA2 fix: it used to be docs/shots, which the container does not see, so the recording never reached the host)
    cache = ROOT / ".cache" / f"linux-{a.arch}" / "cache"
    cache.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="replay_proof_", dir=str(cache) if a.linux else None))
    prefix = [str(GD), "linux", "--arch", a.arch, "run"] if a.linux else [str(GD), "run"]
    shown = scratch if not a.linux else Path("/work/.cache") / scratch.name
    try:
        rec_cmd = prefix + [SCENE, "--", "--autostart=match", f"--players={a.players}", f"--humans={a.humans}", "--bots=human",
                            f"--ticks={a.ticks}", "--speed=0", "--fresh-settings", "--no-audio", f"--map-size={a.size}", f"--map-seed={a.seed}",
                            "--record-replays", f"--replay-dir={shown}", "--ck-lines"]
        rec = run(rec_cmd, a.timeout)
        rec_ck, rec_pl = pick(rec, "APPTEST_CK"), pick(rec, "APPTEST_PLAYER")
        replay_file = scratch / "autosave_1.mfreplay"
        checks: List[tuple] = []
        checks.append(("recording written", replay_file.exists(), str(replay_file)))
        checks.append(("recording has checksum lines", len(rec_ck) >= a.ticks // 200 - 1, f"{len(rec_ck)} lines"))
        checks.append(("recording run has no errors", not errors(rec), "; ".join(errors(rec)[:3])))
        play_cmd = prefix + [SCENE, "--", f"--autostart=replay={shown}/autosave_1.mfreplay", "--fresh-settings", "--no-audio", "--ck-lines"]
        play = run(play_cmd, a.timeout)
        play_ck, play_pl = pick(play, "APPTEST_CK"), pick(play, "APPTEST_PLAYER")
        res = pick(play, "APPTEST_REPLAY ok=")
        checks.append(("playback ok (every CHECK matched)", bool(res) and "ok=1" in res[0], res[0] if res else "no APPTEST_REPLAY line"))
        checks.append(("checksum lines identical", rec_ck == play_ck and len(rec_ck) > 0, f"{len(rec_ck)} vs {len(play_ck)}"))
        checks.append(("player stat lines identical", rec_pl == play_pl and len(rec_pl) > 0, f"{len(rec_pl)} vs {len(play_pl)}"))
        checks.append(("playback run has no errors", not errors(play), "; ".join(errors(play)[:3])))
        seek = run(play_cmd + ["--seek-demo"], a.timeout)
        seeks = pick(seek, "APPTEST_SEEK")
        sres = pick(seek, "APPTEST_REPLAY ok=")
        landed = all(re.search(r"target=(\d+) now=(\d+)", s) and re.search(r"target=(\d+) now=(\d+)", s).group(1) == re.search(r"target=(\d+) now=(\d+)", s).group(2)
                     for s in seeks)
        checks.append(("seek demo: every seek lands on its tick", len(seeks) >= 5 and landed, f"{len(seeks)} seeks"))
        checks.append(("seek demo: still verified", bool(sres) and "ok=1" in sres[0], sres[0] if sres else ""))
        checks.append(("seek demo: same end state", bool(sres) and bool(res) and sres[0].split("chain=")[1] == res[0].split("chain=")[1],
                       "chain/checksum after seeking vs straight through"))
        ok = True
        for name, passed, detail in checks:
            print(f"  [{'ok' if passed else 'FAIL'}] {name}  {detail}")
            ok = ok and passed
        print(f"APP_REPLAY_PROOF RESULT={'OK' if ok else 'FAIL'} ticks={a.ticks} players={a.players} lines={len(rec_ck)}")
        return 0 if ok else 1
    finally:
        if not a.keep:
            shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
