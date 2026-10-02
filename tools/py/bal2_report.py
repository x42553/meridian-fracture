#!/usr/bin/env python3
"""BAL2 report: aggregates bal2_run.py results (JSON lines) per roster / faction / unit (stdlib only).

  python3 tools/py/bal2_report.py RESULTS.jsonl [MORE.jsonl ...] [--cfg base] [--compare OTHER.jsonl] [--units] [--matrix] [--csv OUT.csv]

Per roster: games, wins / losses / draws (a draw = no winner at the cap: score gap < 25 %), win rate = (W + D/2) / N with a 95 % interval
(normal approximation), how the wins were decided (E = elimination, A = adjudicated by score), median first-timings in m:ss (tank, aa,
siege, t3, all by unit birth), income at minutes 5 / 10 / 15 (credits per minute), value lost / value built of combat units, exchange
ratio (value of the opponent's units + structures lost / own value lost: a measure free of the adjudication score), salvage share
of income, superweapon launches per game. Flags: OUT when the win rate is outside 35-65 % with >= 12 games; DOM for the units that are
the most cost-efficient by a wide margin (--units).
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from collections import defaultdict

TPS = 20


def load(paths, cfg=None):
    recs = []
    for p in paths:
        with open(p) as f:
            for line in f:
                line = line.strip()
                if not line.startswith("{"):
                    continue
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if "players" not in r:
                    continue
                if cfg and r.get("cfg") != cfg:
                    continue
                recs.append(r)
    return recs


def mmss(t):
    s = int(t) // TPS
    return "%d:%02d" % (s // 60, s % 60)


def med(v):
    return statistics.median(v) if v else None


def fmt_t(v):
    return mmss(v) if v is not None else "  -  "


def per_roster(recs):
    R = defaultdict(lambda: {"n": 0, "w": 0, "l": 0, "d": 0, "we": 0, "wa": 0, "le": 0, "la": 0, "first": defaultdict(list), "inc": defaultdict(list),
                             "built": 0, "lost": 0, "harv": 0, "salv": 0, "sw": 0, "sw_games": 0, "struct_lost": 0, "opp": defaultdict(lambda: [0, 0, 0]),
                             "army15": [], "score": [], "opp_lost": 0, "own_lost": 0})
    for r in recs:
        w = r["winner"]
        for pid, p in enumerate(r["players"]):
            ro = p["roster"]
            d = R[ro]
            d["n"] += 1
            opp = r["players"][1 - pid]["roster"]
            ofac = opp.split(".")[1]
            if w == pid:
                d["w"] += 1
                d["opp"][ofac][0] += 1
                if r["how"] == "elimination":
                    d["we"] += 1
                else:
                    d["wa"] += 1
            elif w >= 0:
                d["l"] += 1
                d["opp"][ofac][1] += 1
                if r["how"] == "elimination":
                    d["le"] += 1
                else:
                    d["la"] += 1
            else:
                d["d"] += 1
                d["opp"][ofac][2] += 1
            x = p.get("x", {})
            for k, v in x.get("first_born", {}).items():
                d["first"][k].append(v)
            for k in ("tank", "aa", "siege", "t3"):
                pass
            ipm = p.get("income_per_min", [])
            for m in (5, 10, 15):
                if len(ipm) > m:
                    d["inc"][m].append(ipm[m])
            d["built"] += sum(x.get("built_v", {}).values())
            d["lost"] += sum(x.get("lost_v", {}).values())
            d["struct_lost"] += x.get("struct_lost_v", 0)
            d["own_lost"] += sum(x.get("lost_v", {}).values()) + x.get("struct_lost_v", 0)
            ox = r["players"][1 - pid].get("x", {})
            d["opp_lost"] += sum(ox.get("lost_v", {}).values()) + ox.get("struct_lost_v", 0)
            d["harv"] += x.get("harvested", 0)
            d["salv"] += x.get("salvaged", 0)
            d["sw"] += x.get("sw_launches", 0)
            d["sw_games"] += 1
            if p.get("army_curve"):
                ac = p["army_curve"]
                d["army15"].append(ac[min(len(ac) - 1, 9 * 12 * 1)] if ac else 0)
            d["score"].append(p.get("score", 0))
    return R


def rate(d):
    n = d["n"]
    if n == 0:
        return 0.5, 0.0
    p = (d["w"] + 0.5 * d["d"]) / n
    ci = 1.96 * math.sqrt(max(p * (1 - p), 0.02) / n)
    return p, ci


def print_rosters(R, title="", flag=True):
    print("== per-roster results %s" % title)
    print("%-28s %3s %3s %3s %3s  %6s %6s  %-4s | %5s %5s %5s %5s | %5s %5s %5s | lost/built exch salv%% sw" % (
        "roster", "N", "W", "L", "D", "win%", "+-", "E/A", "tank", "aa", "siege", "t3", "inc5", "inc10", "inc15"))
    rows = []
    for ro in sorted(R):
        d = R[ro]
        p, ci = rate(d)
        f = d["first"]
        inc = d["inc"]
        income = d["harv"] + d["salv"]
        line = "%-28s %3d %3d %3d %3d  %5.1f%% %5.1f  %2d/%-2d | %5s %5s %5s %5s | %5s %5s %5s | %5.2f %4.2f %5.1f%% %.2f%s" % (
            ro.replace("roster.", ""), d["n"], d["w"], d["l"], d["d"], 100 * p, 100 * ci, d["we"], d["wa"],
            fmt_t(med(f["tank"])), fmt_t(med(f["aa"])), fmt_t(med(f["siege"])), fmt_t(med(f["t3"])),
            "%5d" % med(inc[5]) if inc[5] else "  -  ", "%5d" % med(inc[10]) if inc[10] else "  -  ", "%5d" % med(inc[15]) if inc[15] else "  -  ",
            d["lost"] / max(d["built"], 1), d["opp_lost"] / max(d["own_lost"], 1), 100 * d["salv"] / max(income, 1), d["sw"] / max(d["sw_games"], 1),
            "  OUT" if flag and d["n"] >= 12 and (p < 0.35 or p > 0.65) else "")
        rows.append((p, line))
    for _, line in sorted(rows, key=lambda t: -t[0]):
        print(line)


def print_factions(R):
    F = defaultdict(lambda: {"n": 0, "w": 0, "d": 0})
    for ro, d in R.items():
        f = ro.split(".")[1]
        F[f]["n"] += d["n"]
        F[f]["w"] += d["w"]
        F[f]["d"] += d["d"]
    print("== per-faction")
    for f in sorted(F):
        d = F[f]
        print("  %-5s N=%3d win %5.1f%%" % (f, d["n"], 100 * (d["w"] + 0.5 * d["d"]) / max(d["n"], 1)))


def print_matrix(R):
    facs = sorted({ro.split(".")[1] for ro in R})
    M = defaultdict(lambda: [0, 0, 0])
    for ro, d in R.items():
        f = ro.split(".")[1]
        for of, (w, l, dr) in d["opp"].items():
            M[(f, of)][0] += w
            M[(f, of)][1] += l
            M[(f, of)][2] += dr
    print("== faction x faction win% (row vs column, draws half; n in brackets)")
    print("       " + " ".join("%9s" % f for f in facs))
    for f in facs:
        cells = []
        for of in facs:
            w, l, dr = M[(f, of)]
            n = w + l + dr
            cells.append("%4.0f(%3d)" % (100 * (w + 0.5 * dr) / n, n) if n else "    -    ")
        print("%-6s " % f + " ".join(cells))


def print_units(recs, top=14):
    """Cost efficiency: for every combat unit, value lost / value built (lower = survives more) pooled over all games, plus the
    share of the value that was built at all (usage). The 'kill' side is not attributed per unit in the sim, so this is a survival
    proxy; use balance_calc.py duel/rps for the exchange side."""
    B = defaultdict(int)
    L = defaultdict(int)
    NB = defaultdict(int)
    NL = defaultdict(int)
    games = defaultdict(set)
    for gi, r in enumerate(recs):
        for p in r["players"]:
            x = p.get("x", {})
            for k, v in x.get("built_v", {}).items():
                B[k] += v
                NB[k] += x["built_n"].get(k, 0)
                games[k].add(gi)
            for k, v in x.get("lost_v", {}).items():
                L[k] += v
                NL[k] += x["lost_n"].get(k, 0)
    rows = []
    for k in B:
        if NB[k] >= 20 and not k.startswith("unit.shared.collector"):
            rows.append((L[k] / max(B[k], 1), k, NB[k], NL[k], B[k], len(games[k])))
    rows.sort()
    print("== unit survival (lost/built value, pooled; NB=count built)  best %d and worst %d" % (top, top))
    for r in rows[:top]:
        print("  %5.2f %-40s NB=%4d NL=%4d builtV=%6d games=%d" % (r[0], r[1].replace("unit.", ""), r[2], r[3], r[4], r[5]))
    print("  ...")
    for r in rows[-top:]:
        print("  %5.2f %-40s NB=%4d NL=%4d builtV=%6d games=%d" % (r[0], r[1].replace("unit.", ""), r[2], r[3], r[4], r[5]))
    # usage: which unit types are built most (value share) per roster
    tot = sum(B.values())
    use = sorted(((v / tot, k) for k, v in B.items()), reverse=True)[:10]
    print("  most-built value share: " + ", ".join("%s %.1f%%" % (k.replace("unit.", ""), 100 * s) for s, k in use))


def summary(recs):
    n = len(recs)
    el = sum(1 for r in recs if r["how"] == "elimination")
    ad = sum(1 for r in recs if r["how"] != "elimination" and r["winner"] >= 0)
    dr = sum(1 for r in recs if r["winner"] < 0)
    errs = sum(r.get("error_count", 0) for r in recs)
    ticks = statistics.mean(r["ticks"] for r in recs) if recs else 0
    print("== %d matches: %d elimination, %d adjudicated, %d draws; engine errors %d; mean length %s" % (n, el, ad, dr, errs, mmss(ticks)))
    side0 = sum(1 for r in recs if r["winner"] == 0)
    side1 = sum(1 for r in recs if r["winner"] == 1)
    print("   slot bias: slot0 wins %d, slot1 wins %d" % (side0, side1))
    fam = defaultdict(lambda: [0, 0])
    for r in recs:
        fam[r["family"]][0] += 1
        fam[r["family"]][1] += 1 if r["winner"] >= 0 else 0
    print("   decisive by map family: " + ", ".join("f%d %d/%d" % (k, v[1], v[0]) for k, v in sorted(fam.items())))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--cfg")
    ap.add_argument("--compare", nargs="*", default=[])
    ap.add_argument("--units", action="store_true")
    ap.add_argument("--matrix", action="store_true")
    ap.add_argument("--csv")
    a = ap.parse_args()
    recs = load(a.files, a.cfg)
    if not recs:
        print("no records")
        return 2
    summary(recs)
    R = per_roster(recs)
    print_rosters(R)
    print_factions(R)
    if a.matrix:
        print_matrix(R)
    if a.units:
        print_units(recs)
    if a.compare:
        recs2 = load(a.compare)
        R2 = per_roster(recs2)
        print("\n== before -> after win%% (before N=%d matches, after N=%d)" % (len(recs), len(recs2)))
        for ro in sorted(R):
            p1, c1 = rate(R[ro])
            if ro in R2:
                p2, c2 = rate(R2[ro])
                print("  %-28s %5.1f%% (%d) -> %5.1f%% (%d)  %+5.1f" % (ro.replace("roster.", ""), 100 * p1, R[ro]["n"], 100 * p2, R2[ro]["n"], 100 * (p2 - p1)))
    if a.csv:
        with open(a.csv, "w") as f:
            f.write("roster,n,w,l,d,winrate\n")
            for ro in sorted(R):
                d = R[ro]
                f.write("%s,%d,%d,%d,%d,%.4f\n" % (ro, d["n"], d["w"], d["l"], d["d"], rate(d)[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
