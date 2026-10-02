#!/usr/bin/env python3
"""BAL2: stratified AI-vs-AI round robin for the balance pass (stdlib only, resume-safe).

  python3 tools/py/bal2_run.py --out RESULTS.jsonl [--tag base] [--rounds 1] [--jobs 12] [--size 112] [--cap-min 16]
                               [--offsets 4,5,6,7,8,9,10,14] [--level 2] [--only ROSTER_SUBSTR ...] [--like BASE.jsonl] [--arg bal=DIR] [--dry]

Schedule (per round): match (i, (i + d) % 32) for every offset d, rosters in faction order (4 per faction). With the default
offsets every roster meets 16 distinct opponents per round, covering all 7 other factions. Odd rounds swap the start slots. The map
family cycles 0/1/2 with the match index; the map seed is 1000 + 100 * round + match index. Each match is one process of
game/tests/scenarios/bal2_match.gd; the BAL2_JSON line it prints is appended to --out (one JSON object per line, plus keys
"cfg" = --tag, "a", "b", "family", "seed", "lv"). Matches already present in --out (same cfg/a/b/family/seed) are skipped.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIBLE = ROOT / "game" / "data" / "bible" / "meridian_factions.json"


def rosters():
    d = json.loads(BIBLE.read_text())
    out = []
    for f in d["factions"].values():
        out += [f["vanilla_roster_id"]] + f["subfaction_roster_ids"]
    return out


def schedule(rounds, offsets, only=()):
    R = rosters()
    n = len(R)
    jobs = []
    idx = 0
    for r in range(rounds):
        for d in offsets:
            for i in range(n):
                a, b = R[i], R[(i + d) % n]
                if r % 2 == 1:
                    a, b = b, a
                fam = idx % 3
                seed = 1000 + 100 * r + idx
                idx += 1
                if only and not any(s in a or s in b for s in only):
                    continue
                jobs.append({"a": a, "b": b, "family": fam, "seed": seed})
    return jobs


def key(j, cfg):
    return (cfg, j["a"], j["b"], j["family"], j["seed"])


def run_one(j, args):
    if args.project:  # a private snapshot of game/ (own AI data / balance), no shared tools/gd lock, immune to concurrent edits
        cmd = [str(ROOT / "tools" / "godot" / "Godot.app" / "Contents" / "MacOS" / "Godot"), "--headless", "--path", args.project,
               "--script", "res://tests/scenarios/bal2_match.gd", "--"]
    else:
        cmd = [str(ROOT / "tools" / "gd"), "run", "--allow-errors", "--timeout", "900", "res://tests/scenarios/bal2_match.gd", "--"]
    cmd += ["a=" + j["a"], "b=" + j["b"], "family=%d" % j["family"], "seed=%d" % j["seed"], "size=%d" % args.size,
           "cap_min=%d" % args.cap_min, "lv0=%d" % args.level, "lv1=%d" % args.level]
    for extra in args.arg:
        cmd.append(extra)
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=1500)
    for line in p.stdout.splitlines():
        if line.startswith("BAL2_JSON "):
            rec = json.loads(line[len("BAL2_JSON "):])
            rec.update({"cfg": args.tag, "a": j["a"], "b": j["b"], "family": j["family"], "seed": j["seed"], "lv": args.level})
            return rec
    return {"error": "no result", "tail": (p.stdout + p.stderr)[-400:], **j}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", default="base")
    ap.add_argument("--rounds", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=12)
    ap.add_argument("--size", type=int, default=112)
    ap.add_argument("--cap-min", type=int, default=16)
    ap.add_argument("--level", type=int, default=2)
    ap.add_argument("--offsets", default="4,5,6,7,8,9,10,14")
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--arg", action="append", default=[], help="extra key=value passed to the scenario")
    ap.add_argument("--like", help="only run the (a, b, family, seed) matches present in this results file (paired before / after comparison)")
    ap.add_argument("--like-cfg", default="base")
    ap.add_argument("--project", help="run Godot directly on this game directory (a private copy of game/) instead of tools/gd run")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()
    offs = [int(x) for x in args.offsets.split(",")]
    jobs = schedule(args.rounds, offs, args.only)
    if args.like:
        want = set()
        for line in open(args.like):
            if line.startswith("{"):
                r = json.loads(line)
                if r.get("cfg") == args.like_cfg and "a" in r:
                    want.add((r["a"], r["b"], r["family"], r["seed"]))
        jobs = [j for j in jobs if (j["a"], j["b"], j["family"], j["seed"]) in want]
    out = Path(args.out)
    done = set()
    if out.exists():
        for line in out.read_text().splitlines():
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if "a" in r and "error" not in r:
                done.add((r["cfg"], r["a"], r["b"], r["family"], r["seed"]))
    todo = [j for j in jobs if key(j, args.tag) not in done]
    print("matches: %d scheduled, %d done, %d to run" % (len(jobs), len(jobs) - len(todo), len(todo)), flush=True)
    if args.dry:
        return 0
    lock = threading.Lock()
    counter = [0]
    errs = [0]

    def work(j):
        rec = run_one(j, args)
        with lock:
            counter[0] += 1
            if "error" in rec:
                errs[0] += 1
                print("FAIL", j, rec["tail"][-200:].replace("\n", " "), flush=True)
            else:
                with out.open("a") as f:
                    f.write(json.dumps(rec, separators=(",", ":")) + "\n")
            if counter[0] % 10 == 0:
                print("  %d / %d done (%d failed)" % (counter[0], len(todo), errs[0]), flush=True)

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        list(ex.map(work, todo))
    print("finished %d matches, %d failed" % (len(todo), errs[0]))
    return 1 if errs[0] else 0


if __name__ == "__main__":
    sys.exit(main())
