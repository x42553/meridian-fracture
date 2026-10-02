#!/usr/bin/env python3
"""BAL3: compact per-roster table of the equal-spend fight grid (bal2_fight.gd mode=grid) next to the round-robin win rate (stdlib only).

  python3 tools/py/bal3_grid.py GRID.jsonl [MORE ...] [--rr RESULTS.jsonl [--cfg TAG]] [--compare GRID2.jsonl ...]

Columns: mean (share(self) - share(opponent)) over every fight for each composition (mid / heavy / inf) and over all, then the round-robin win rate.
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bal3_report as rep  # noqa: E402


def load(paths):
    out = []
    for p in paths:
        for f in glob.glob(p):
            for line in open(f):
                line = line.strip()
                if line.startswith("FIGHT_JSON "):
                    line = line[11:]
                if line.startswith("{"):
                    try:
                        out.append(json.loads(line))
                    except ValueError:
                        pass
    return out


def per_roster(fights):
    D = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in fights:
        D[r["a"]][r["comp"]].append(r["diff"])
        D[r["b"]][r["comp"]].append(-r["diff"])
    return D


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("grid", nargs="+")
    ap.add_argument("--compare", nargs="*")
    ap.add_argument("--rr", nargs="*")
    ap.add_argument("--cfg")
    a = ap.parse_args()
    G = per_roster(load(a.grid))
    G2 = per_roster(load(a.compare)) if a.compare else None
    W = rep.agg(rep.load(a.rr, a.cfg)) if a.rr else {}
    comps = sorted({c for v in G.values() for c in v})
    allm = {k: statistics.mean([x for c in v.values() for x in c]) for k, v in G.items()}
    print("%-24s" % "roster" + "".join("%8s" % c for c in comps) + "%8s" % "all" + ("   after:" + "".join("%8s" % c for c in comps) + "%8s" % "all" if G2 else "") + "   RR win%")
    for k in sorted(G, key=lambda k: -allm[k]):
        line = "%-24s" % k.replace("roster.", "") + "".join("%+8.2f" % statistics.mean(G[k][c]) if G[k][c] else "%8s" % "-" for c in comps) + "%+8.2f" % allm[k]
        if G2:
            line += "         " + "".join("%+8.2f" % statistics.mean(G2[k][c]) if G2[k][c] else "%8s" % "-" for c in comps) + "%+8.2f" % statistics.mean([x for c in G2[k].values() for x in c])
        if k in W:
            line += "   %5.1f" % (100 * statistics.mean(W[k]["res"]))
        print(line)
    vals = list(allm.values())
    print("sd of roster means: %.3f" % statistics.pstdev(vals))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
