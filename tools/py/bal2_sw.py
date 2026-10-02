#!/usr/bin/env python3
"""BAL2: long-cap superweapon / support-power usage subset (stdlib only).

  python3 tools/py/bal2_sw.py --out SW.jsonl [--tag base] [--cap-min 30] [--jobs 10] [--arg bal=DIR]

The 16-minute cap of the round robin ends before the first superweapon shot (FRAMEWORK targets: first shot 1020-1240 s typical), so this
subset plays 16 vanilla-vs-vanilla matches (each faction twice, as slot 0, against factions 3 and 5 places later) with a longer cap and
reports, per faction, the superweapon launches / starts and the power casts of its AI (keys of "x" in the bal2_match record).
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
F = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]


def jobs():
    out = []
    for i in range(8):
        for k in (3, 5):
            j = (i + k) % 8
            out.append({"a": "roster.%s.vanilla" % F[i], "b": "roster.%s.vanilla" % F[j], "family": (i + k) % 3, "seed": 7000 + i * 10 + k})
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", default="base")
    ap.add_argument("--cap-min", type=int, default=30)
    ap.add_argument("--jobs", type=int, default=10)
    ap.add_argument("--arg", action="append", default=[])
    a = ap.parse_args()
    lock = threading.Lock()

    def run(j):
        cmd = [str(ROOT / "tools" / "gd"), "run", "--allow-errors", "--timeout", "1800", "res://tests/scenarios/bal2_match.gd", "--",
               "a=" + j["a"], "b=" + j["b"], "family=%d" % j["family"], "seed=%d" % j["seed"], "size=112", "cap_min=%d" % a.cap_min] + a.arg
        p = subprocess.run(cmd, capture_output=True, text=True)
        for line in p.stdout.splitlines():
            if line.startswith("BAL2_JSON "):
                rec = json.loads(line[10:])
                rec.update({"cfg": a.tag, "a": j["a"], "b": j["b"]})
                with lock:
                    with open(a.out, "a") as f:
                        f.write(json.dumps(rec, separators=(",", ":")) + "\n")
                return
        print("FAIL", j, p.stdout[-200:], flush=True)

    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        list(ex.map(run, jobs()))
    rows = {}
    for line in open(a.out):
        r = json.loads(line)
        if r.get("cfg") != a.tag:
            continue
        for p in r["players"]:
            x = p["x"]
            d = rows.setdefault(p["roster"], [0, 0, 0, 0, []])
            d[0] += 1
            d[1] += x["sw_started"] > 0
            d[2] += x["sw_launches"]
            d[3] += x["power_casts"]
            fs = p["first"].get("sw_launch") or p["first"].get("superweapon")
            if fs:
                d[4].append(fs / 20)
    print("%-22s games started launches casts  first launch s" % "roster")
    for k in sorted(rows):
        d = rows[k]
        print("%-22s %5d %7d %8d %5d  %s" % (k, d[0], d[1], d[2], d[3], ",".join("%d" % v for v in d[4])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
