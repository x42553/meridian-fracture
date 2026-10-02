#!/usr/bin/env python3
"""BAL2: aggregates the equal-spend fight grid (bal2_fight.gd mode=grid, JSON lines) per roster (stdlib only).

  python3 tools/py/bal2_fightrep.py FIGHTS.jsonl [MORE ...] [--comp mid] [--compare OTHER.jsonl] [--pair A B]

Per roster and composition: mean of (share(self) - share(opponent)) over every fight, its standard error, the win rate of the fights
(diff > +0.05 win, < -0.05 loss) and the mean army size bought. |mean| below 0.05 is even; the spread of the 32 rosters shows which
ones are outliers (more than 2 standard deviations from the mean of all rosters).
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from collections import defaultdict


def load(paths):
    out = []
    for p in paths:
        with open(p) as f:
            for line in f:
                line = line.strip()
                if line.startswith("FIGHT_JSON "):
                    line = line[11:]
                if line.startswith("{"):
                    try:
                        out.append(json.loads(line))
                    except ValueError:
                        pass
    return out


def per_roster(recs, comp):
    d = defaultdict(list)
    n_units = defaultdict(list)
    vs = defaultdict(lambda: defaultdict(list))
    for r in recs:
        if r["comp"] != comp:
            continue
        d[r["a"]].append(r["diff"])
        d[r["b"]].append(-r["diff"])
        n_units[r["a"]].append(r["n_a"])
        n_units[r["b"]].append(r["n_b"])
        vs[r["a"]][r["b"]].append(r["diff"])
        vs[r["b"]][r["a"]].append(-r["diff"])
    return d, n_units, vs


def stats(v):
    m = statistics.mean(v)
    se = statistics.pstdev(v) / math.sqrt(len(v)) if len(v) > 1 else 0.0
    w = sum(1 for x in v if x > 0.05) / len(v)
    l = sum(1 for x in v if x < -0.05) / len(v)
    return m, se, w, l


def report(recs, comp, other=None):
    d, nu, vs = per_roster(recs, comp)
    if not d:
        print("no fights for comp", comp)
        return {}
    rows = {ro: stats(v) for ro, v in d.items()}
    means = [r[0] for r in rows.values()]
    mu = statistics.mean(means)
    sd = statistics.pstdev(means)
    d2 = per_roster(other, comp)[0] if other else None
    print("== comp %s: %d fights, %d rosters; roster means: avg %+.3f sd %.3f" % (comp, sum(len(v) for v in d.values()) // 2, len(d), mu, sd))
    print("%-26s %6s %5s %5s %5s %5s%s" % ("roster", "mean", "se", "win", "loss", "units", "   after" if d2 else ""))
    for ro, (m, se, w, l) in sorted(rows.items(), key=lambda t: -t[1][0]):
        flag = "  <-- OUT" if abs(m - mu) > 2 * sd else ""
        extra = ""
        if d2 and ro in d2:
            extra = "   %+.3f" % stats(d2[ro])[0]
        print("%-26s %+6.3f %5.3f %4.0f%% %4.0f%% %5.1f%s%s" % (ro.replace("roster.", ""), m, se, 100 * w, 100 * l, statistics.mean(nu[ro]), extra, flag))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--comp", default=None)
    ap.add_argument("--compare", nargs="*", default=[])
    ap.add_argument("--pair", nargs=2)
    a = ap.parse_args()
    recs = load(a.files)
    other = load(a.compare) if a.compare else None
    comps = [a.comp] if a.comp else sorted({r["comp"] for r in recs})
    for c in comps:
        report(recs, c, other)
    if a.pair:
        for c in comps:
            v = [r["diff"] if r["a"] == a.pair[0] else -r["diff"] for r in recs if r["comp"] == c and {r["a"], r["b"]} == set(a.pair)]
            if v:
                print("pair %s vs %s %s: n=%d mean %+.3f" % (a.pair[0], a.pair[1], c, len(v), statistics.mean(v)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
