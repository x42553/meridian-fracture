#!/usr/bin/env python3
"""AIT report: aggregate metrics of a bal2_run / bal2_match results file (stdlib only).

  python3 tools/py/ait_report.py RESULTS.jsonl [--cfg TAG] [--rosters]

Prints: matches, how they ended (elimination share, median elimination minute), share and median minute of the first attack wave,
mean army value at minutes 6 / 10 / 14, mean income per minute at minutes 5 / 10 / 15, harvested, units vs construction spending,
collectors at the end. With --rosters: per-roster win rate (adjudicated winner = score gap >= 25 %) next to those figures.
"""
import argparse
import json
import statistics
from collections import defaultdict


def load(path, cfg):
    out = []
    for line in open(path):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if "players" in r and (cfg is None or r.get("cfg") == cfg):
            out.append(r)
    return out


def med(xs):
    return statistics.median(xs) if xs else float("nan")


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def at(curve, minute):
    i = minute * 12
    return curve[i] if len(curve) > i else (curve[-1] if curve else 0)


def pm(lst, m):
    return lst[m] if len(lst) > m else float("nan")


def summarize(recs):
    n = len(recs)
    elim = [r for r in recs if r["how"] == "elimination"]
    ps = [p for r in recs for p in r["players"]]
    fa = [p["first"]["attack"] / 1200.0 for p in ps if "attack" in p["first"]]
    print("matches %d | errors %d | elimination %d (%.1f%%) | median elim minute %.1f | mean length %.1f min" % (
        n, sum(r["error_count"] for r in recs), len(elim), 100.0 * len(elim) / max(n, 1), med([r["ticks"] / 1200.0 for r in elim]),
        mean([r["ticks"] / 1200.0 for r in recs])))
    print("first attack: %d/%d players, median minute %.1f" % (len(fa), len(ps), med(fa)))
    print("army value @6/10/14: %d / %d / %d" % tuple(int(mean([at(p["army_curve"], m) for p in ps])) for m in (6, 10, 14)))
    print("income/min @5/10/15: %d / %d / %d" % tuple(int(mean([pm(p["income_per_min"], m) for p in ps if len(p["income_per_min"]) > m] or [0])) for m in (5, 10, 15)))
    xs = [p["x"] for p in ps if "x" in p]
    print("harvested %d | spent units %d construction %d | collectors end %.1f | structures end %.1f | combat units end %.1f" % (
        mean([p["harvested"] for p in ps]), mean([x["spent_units"] for x in xs]), mean([x["spent_construction"] for x in xs]),
        mean([p["collectors"] for p in ps]), mean([p["structures"] for p in ps]), mean([p["combat_units"] for p in ps])))
    ai = [p["ai_us_avg"] for p in ps]
    print("AI us/tick: mean %d max %d" % (mean(ai), max(ai) if ai else 0))


def rosters(recs):
    st = defaultdict(lambda: [0, 0, 0, 0, 0.0, 0.0, 0.0])  # n, wins, losses, draws, army10, harvested, elim wins
    for r in recs:
        for i, p in enumerate(r["players"]):
            s = st[p["roster"]]
            s[0] += 1
            if r["winner"] == i:
                s[1] += 1
                if r["how"] == "elimination":
                    s[6] += 1
            elif r["winner"] < 0:
                s[3] += 1
            else:
                s[2] += 1
            s[4] += at(p["army_curve"], 10)
            s[5] += p["harvested"]
    print("%-28s %4s %4s %4s %4s %7s %5s %7s %8s" % ("roster", "N", "W", "L", "D", "win%", "Ewin", "army10", "harvest"))
    out = []
    for k, s in sorted(st.items(), key=lambda kv: -((kv[1][1] + kv[1][3] / 2) / kv[1][0])):
        wr = 100.0 * (s[1] + s[3] / 2) / s[0]
        out.append(wr)
        print("%-28s %4d %4d %4d %4d %6.1f%% %5d %7d %8d%s" % (k.replace("roster.", ""), s[0], s[1], s[2], s[3], wr, s[6], s[4] / s[0], s[5] / s[0], "  OUT" if wr < 35 or wr > 65 else ""))
    print("rosters outside 35-65%%: %d of %d; sd %.1f" % (sum(1 for w in out if w < 35 or w > 65), len(out), statistics.pstdev(out) if out else 0))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--cfg")
    ap.add_argument("--rosters", action="store_true")
    a = ap.parse_args()
    recs = load(a.path, a.cfg)
    summarize(recs)
    if a.rosters:
        rosters(recs)
