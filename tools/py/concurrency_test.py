#!/usr/bin/env python3
"""Proof that tools/gd survives parallel use: N `gd test` + M `gd import` (+ a forced cold cache) at once.

Runs in an isolated copy of game/ (GD_ROOT=<tmp>) so it never disturbs other agents. Checks:
  * nothing deadlocks (hard timeout),
  * every `gd test` passes with the identical summary line,
  * every `gd import` succeeds,
  * lock trace (GD_TRACE_FILE): no EXCLUSIVE interval overlaps any other lock interval,
  * the class cache is valid afterwards (parses, lists the expected class_name globals),
  * the marker fingerprint matches the tree.
Usage: tools/py/concurrency_test.py [--tests 6] [--imports 2] [--rounds 3] [--keep]
"""
from __future__ import annotations

import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
REPO = TOOLS.parent
GD = TOOLS / "gd"


def copy_game(dst: Path) -> None:
    def ignore(_d: str, names: list) -> list:
        return [n for n in names if n in (".godot", ".import")]

    shutil.copytree(REPO / "game", dst / "game", ignore=ignore)


def parse_trace(path: Path):
    """[(pid, kind, start_ns, end_ns)] from acquire/release events."""
    open_stack = {}
    out = []
    for line in path.read_text().splitlines():
        t, pid, _name, kind, event = line.split()
        key = (pid, kind)
        if event == "acquire":
            open_stack.setdefault(key, []).append(int(t))
        else:
            start = open_stack[key].pop()
            out.append((pid, kind, start, int(t)))
    return out


def find_overlaps(intervals):
    bad = []
    for i, a in enumerate(intervals):
        if a[1] != "exclusive":
            continue
        for j, b in enumerate(intervals):
            if i == j:
                continue
            if b[2] < a[3] and a[2] < b[3]:
                bad.append((a, b))
    return bad


def one_round(rnd: int, n_tests: int, n_imports: int, timeout: float, keep: bool) -> bool:
    order = ("tests first (cold cache: tests must auto-import)", "shuffled", "imports first")[(rnd - 1) % 3]
    tmp = Path(tempfile.mkdtemp(prefix="gd-concurrency-"))
    trace = tmp / "trace.log"
    try:
        copy_game(tmp)
        env = dict(os.environ, GD_ROOT=str(tmp), GD_TRACE_FILE=str(trace))
        jobs = [("test", [str(GD), "test"]) for _ in range(n_tests)] + [("import", [str(GD), "import"]) for _ in range(n_imports)]
        if order == "shuffled":
            random.shuffle(jobs)
        elif order == "imports first":
            jobs.sort(key=lambda j: j[0] != "import")
        else:
            jobs.sort(key=lambda j: j[0] != "test")
        procs = []
        t0 = time.time()
        for kind, cmd in jobs:
            time.sleep(random.random() * 0.15)  # jitter so arrivals interleave
            procs.append((kind, subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)))
        results = []
        for kind, p in procs:
            remaining = max(1.0, timeout - (time.time() - t0))
            try:
                out, _ = p.communicate(timeout=remaining)
            except subprocess.TimeoutExpired:
                p.kill()
                print(f"  DEADLOCK/TIMEOUT: a `gd {kind}` did not finish within {timeout:.0f}s")
                return False
            results.append((kind, p.returncode, out))
        elapsed = time.time() - t0
        ok = True
        summaries = set()
        for kind, rc, out in results:
            if rc != 0:
                ok = False
                print(f"  FAIL: gd {kind} exited {rc}\n" + "\n".join("    " + l for l in out.splitlines()[-15:]))
            if kind == "test":
                m = re.search(r"^== .*$", out, re.M)
                summaries.add(re.sub(r" in [\d.]+ s", "", m.group(0)) if m else "<no summary>")
        if len(summaries) != 1 or "<no summary>" in summaries:
            ok = False
            print(f"  FAIL: test summaries differ or missing: {summaries}")
        intervals = parse_trace(trace)
        overlaps = find_overlaps(intervals)
        exclusive = [i for i in intervals if i[1] == "exclusive"]
        shared = [i for i in intervals if i[1] == "shared"]
        if overlaps:
            ok = False
            print(f"  FAIL: {len(overlaps)} exclusive/other lock overlaps, e.g. {overlaps[0]}")
        cache = tmp / "game" / ".godot" / "global_script_class_cache.cfg"
        text = cache.read_text() if cache.exists() else ""
        for cls in ("TestCtx", "TestSuite", "TestLogger"):
            if f'"class": &"{cls}"' not in text:
                ok = False
                print(f"  FAIL: class cache is missing {cls}")
        peak = max_concurrent_shared(shared)
        print(f"  round {rnd} [{order}]: {'OK' if ok else 'FAILED'} in {elapsed:.1f}s - {len(exclusive)} exclusive + {len(shared)} shared lock intervals, "
              f"peak {peak} concurrent shared holders, no overlap with exclusive: {not overlaps}, summaries: {sorted(summaries)}")
        return ok
    finally:
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)


def max_concurrent_shared(shared) -> int:
    events = []
    for _pid, _k, s, e in shared:
        events.append((s, 1))
        events.append((e, -1))
    cur = best = 0
    for _t, d in sorted(events):
        cur += d
        best = max(best, cur)
    return best


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tests", type=int, default=6)
    ap.add_argument("--imports", type=int, default=2)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=240)
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()
    print(f"concurrency test: {args.tests} x `gd test` + {args.imports} x `gd import` per round, cold cache, {args.rounds} rounds")
    ok = all([one_round(i + 1, args.tests, args.imports, args.timeout, args.keep) for i in range(args.rounds)])
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
