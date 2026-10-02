#!/usr/bin/env python3
"""Aggregates AI soak results into a text report (+ optional JSON metrics) and checks the AIC acceptance thresholds.

Input: one or more files produced by `tools/gd run res://tests/scenarios/ai_soak.gd -- ... [out=<file>]` (or a saved
stdout log). Every result is one line `AISOAK_JSON {...}` (or a bare JSON object per line). Stdlib only.

  python3 tools/py/ai_soak_report.py round.log [ladder.log ...] [--json metrics.json] [--quiet]

Sections: verdict, per-match table, outcome / win-rate by level and roster, timing distributions (first_* ticks as m:ss,
median / min / max per difficulty level), income at 5 / 10 / 15 minutes, idle ratios, stalls and errors, AI CPU
(microseconds per game tick; budget 1500), determinism pairs (tags det1 / det2).

Exit codes: 0 all thresholds met, 1 a threshold breached (see the verdict lines), 2 no input.
Thresholds (AIC acceptance): errors == 0; AI cost <= 1500 us/tick on average; Medium first tank <= 4:00 and first attack
<= 7:00 (reported as WARN when missed, they depend on the economy modules); ladder: higher level wins >= 80 %;
determinism pairs identical.
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import defaultdict

TPS = 20
LEVELS = ["Easy", "Medium", "Hard", "Brutal"]
FIRST_KEYS = ["scout", "barracks", "factory", "radar", "tank", "opener_done", "attack", "contact", "defend", "lab", "aa", "expansion"]
AI_US_BUDGET = 1500
MEDIUM_TANK_TICKS = 4 * 60 * TPS
MEDIUM_ATTACK_TICKS = 7 * 60 * TPS


def load(paths):
    recs = []
    for p in paths:
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("AISOAK_JSON "):
                    line = line[len("AISOAK_JSON "):]
                if not line.startswith("{"):
                    continue
                try:
                    recs.append(json.loads(line))
                except ValueError:
                    continue
    return recs


def mmss(ticks):
    s = ticks // TPS
    return "%d:%02d" % (s // 60, s % 60)


def dist(values):
    if not values:
        return "-"
    return "n=%d med %s min %s max %s" % (len(values), mmss(int(statistics.median(values))), mmss(min(values)), mmss(max(values)))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--json", help="write the aggregated metrics as JSON")
    ap.add_argument("--quiet", action="store_true", help="only the verdict")
    args = ap.parse_args(argv)
    recs = load(args.inputs)
    if not recs:
        print("no AISOAK_JSON records found")
        return 2

    out = []
    verdict = []
    fail = False

    def say(s=""):
        out.append(s)

    # ---- per match
    say("== matches (%d) ==" % len(recs))
    total_err = 0
    outcomes = defaultdict(int)
    for r in recs:
        pl = r["players"]
        lv = "/".join(LEVELS[p["level"]][0] for p in pl)
        total_err += r.get("error_count", 0)
        outcomes[r["how"] + ("+adj" if r.get("adjudicated") else "")] += 1
        say("%-10s %-24s vs %-24s L%s fam=%d %-11s win=%2d at %s  errors=%d  %.2f ms/tick" % (
            r.get("tag", ""), pl[0]["roster"], pl[1]["roster"] if len(pl) > 1 else "-", lv, r.get("family", 0), r["how"],
            r["winner"], mmss(r["ticks"]), r.get("error_count", 0), r.get("ms_per_tick", 0.0)))
    say()
    say("outcomes: " + ", ".join("%s=%d" % kv for kv in sorted(outcomes.items())))

    # ---- win rate by level pair (ladders) and by roster
    pair = defaultdict(lambda: [0, 0, 0])  # (hi, lo) -> [hi wins, n, adjudicated hi wins]
    roster_w = defaultdict(lambda: [0, 0])
    for r in recs:
        pl = r["players"]
        if len(pl) == 2 and pl[0]["level"] != pl[1]["level"]:
            hi = 0 if pl[0]["level"] > pl[1]["level"] else 1
            key = (pl[hi]["level"], pl[1 - hi]["level"])
            pair[key][1] += 1
            if r["winner"] == hi:
                pair[key][0] += 1
                if r.get("adjudicated"):
                    pair[key][2] += 1
        for p in pl:
            roster_w[p["roster"]][1] += 1
            if r["winner"] == p["pid"]:
                roster_w[p["roster"]][0] += 1
    if pair:
        say()
        say("== difficulty ladder ==")
        for (hi, lo), (w, n, adj) in sorted(pair.items()):
            pct = 100.0 * w / n
            say("%s beats %s: %d of %d (%.0f %%, %d by adjudication)" % (LEVELS[hi], LEVELS[lo], w, n, pct, adj))
            if pct < 80.0 and n >= 5:
                verdict.append("FAIL ladder %s vs %s: %.0f %% < 80 %%" % (LEVELS[hi], LEVELS[lo], pct))
                fail = True
            else:
                verdict.append("PASS ladder %s vs %s: %d/%d" % (LEVELS[hi], LEVELS[lo], w, n))
    say()
    say("== win rate per roster (wins / games) ==")
    for name, (w, n) in sorted(roster_w.items()):
        say("%-30s %2d / %2d" % (name, w, n))

    # ---- timings per level
    first = defaultdict(lambda: defaultdict(list))
    income = defaultdict(lambda: defaultdict(list))
    idle_p = defaultdict(list)
    idle_c = defaultdict(list)
    us_avg = []
    us_worst = []
    stalls = defaultdict(int)
    wall = []
    ticks_total = 0
    waves = defaultdict(list)
    for r in recs:
        wall.append(r.get("ms_per_tick", 0.0))
        ticks_total += r["ticks"]
        for p in r["players"]:
            lv = p["level"]
            for k, v in p.get("first", {}).items():
                first[lv][k].append(v)
            ipm = p.get("income_per_min", [])
            for minute in (5, 10, 15):
                if len(ipm) >= minute:
                    income[lv][minute].append(sum(ipm[minute - 1:minute]))
            idle_p[lv].append(p.get("idle_production", 0.0))
            idle_c[lv].append(p.get("idle_construction", 0.0))
            us_avg.append(p.get("ai_us_avg", 0))
            us_worst.append(p.get("ai_us_worst_think", 0))
            for code, n in p.get("stalls", {}).items():
                stalls[code] += n
            waves[lv].append(p.get("brain", {}).get("waves", 0))
    say()
    say("== timings (game time) ==")
    for lv in sorted(first):
        say("%s:" % LEVELS[lv])
        for k in FIRST_KEYS:
            if k in first[lv]:
                say("  first %-12s %s" % (k, dist(first[lv][k])))
        n_players = sum(1 for r in recs for p in r["players"] if p["level"] == lv)
        say("  waves per player: mean %.1f (players %d)" % (statistics.mean(waves[lv]) if waves[lv] else 0.0, n_players))
    say()
    say("== income (credits harvested in the minute) ==")
    for lv in sorted(income):
        for minute in (5, 10, 15):
            v = income[lv].get(minute, [])
            if v:
                say("%s minute %2d: median %d (n=%d)" % (LEVELS[lv], minute, statistics.median(v), len(v)))
    say()
    say("== idle ratios (60-900 s; producers with an empty queue at >= 500 credits / construction idle with wants) ==")
    for lv in sorted(idle_p):
        say("%s: production mean %.2f, construction mean %.2f" % (LEVELS[lv], statistics.mean(idle_p[lv]), statistics.mean(idle_c[lv])))
    say()
    say("== stalls / errors ==")
    gaps = [r.get("stalemate_gap", 0) for r in recs]
    stale = sum(1 for g in gaps if g >= 3600)
    say("stalemates (no unit / structure loss for >= 3600 ticks while both alive): %d of %d matches (longest gap %s)" % (stale, len(recs), mmss(max(gaps)) if gaps else "-"))
    say("watchdog stall reports by code: %s" % (dict(stalls) if stalls else "none"))
    say("script / engine errors: %d" % total_err)
    if total_err:
        for r in recs:
            for e in r.get("errors", [])[:3]:
                say("  [%s] %s" % (r.get("tag", ""), e))
        verdict.append("FAIL %d error(s)" % total_err)
        fail = True
    else:
        verdict.append("PASS 0 errors in %d matches" % len(recs))

    # ---- AIX1: how decisive the matches were and how much the micro / support ops were used
    say()
    say("== decisiveness and AIX1 operations ==")
    elim = sum(1 for r in recs if r.get("how") == "elimination")
    say("ended by elimination: %d of %d matches" % (elim, len(recs)))
    totals = defaultdict(int)
    for r in recs:
        for p in r.get("players", []):
            for k, v in (p.get("brain", {}).get("stats", {}) or {}).items():
                totals[k] += int(v)
    if totals:
        say("op / micro counters (sum over %d players): %s" % (sum(len(r.get("players", [])) for r in recs),
            ", ".join("%s=%d" % kv for kv in sorted(totals.items()))))
    if recs:
        verdict.append("INFO elimination %d of %d matches" % (elim, len(recs)))
    # AIT acceptance: Medium vs Medium ends by elimination in >= 30 % of the matches, Hard beats Easy by elimination in >= 80 %
    mm = [r for r in recs if len(r.get("players", [])) == 2 and all(int(p.get("level", -1)) == 1 for p in r["players"])]
    if len(mm) >= 8:
        e = sum(1 for r in mm if r.get("how") == "elimination")
        verdict.append("%s Medium vs Medium by elimination: %d of %d (%.0f %%, target >= 30 %%)" % ("PASS" if e * 100 >= 30 * len(mm) else "WARN", e, len(mm), 100.0 * e / len(mm)))
    he = [r for r in recs if len(r.get("players", [])) == 2 and sorted(int(p.get("level", -1)) for p in r["players"]) == [0, 2]]
    if len(he) >= 8:
        won = 0
        elim_won = 0
        for r in he:
            hi = [i for i, p in enumerate(r["players"]) if int(p.get("level", -1)) == 2][0]
            if int(r.get("winner", -1)) == hi:
                won += 1
                if r.get("how") == "elimination":
                    elim_won += 1
        verdict.append("%s Hard beats Easy: %d of %d, by elimination %d (%.0f %%, target >= 80 %%)" % (
            "PASS" if won == len(he) and elim_won * 100 >= 80 * len(he) else "WARN", won, len(he), elim_won, 100.0 * elim_won / len(he)))

    # ---- cost
    say()
    say("== AI cost ==")
    if us_avg:
        mean_us = statistics.mean(us_avg)
        say("per-AI microseconds per game tick: mean %.0f, max %d (budget %d); worst single think %d us; sim+AI %.2f ms/tick (mean)" % (
            mean_us, max(us_avg), AI_US_BUDGET, max(us_worst), statistics.mean(wall)))
        if max(us_avg) > AI_US_BUDGET:
            verdict.append("FAIL AI cost %d us/tick > %d" % (max(us_avg), AI_US_BUDGET))
            fail = True
        else:
            verdict.append("PASS AI cost max %d us/tick <= %d" % (max(us_avg), AI_US_BUDGET))

    # ---- pacing (Medium)
    med = first.get(1, {})
    if med:
        for key, limit, label in (("tank", MEDIUM_TANK_TICKS, "first tank"), ("attack", MEDIUM_ATTACK_TICKS, "first attack wave")):
            vals = med.get(key, [])
            if vals:
                late = sum(1 for v in vals if v > limit)
                verdict.append("%s Medium %s: median %s, %d of %d later than %s" % (
                    "PASS" if late == 0 else "WARN", label, mmss(int(statistics.median(vals))), late, len(vals), mmss(limit)))

    # ---- determinism pairs
    tags = {r.get("tag"): r for r in recs}
    if "det1" in tags and "det2" in tags:
        a, b = tags["det1"], tags["det2"]
        same = a["checksum"] == b["checksum"] and a["ai_hash"] == b["ai_hash"] and a["ticks"] == b["ticks"]
        verdict.append("%s determinism double run (checksum %s, ai hash %s)" % ("PASS" if same else "FAIL", a["checksum"], a["ai_hash"]))
        fail = fail or not same

    print("== VERDICT ==")
    for v in verdict:
        print(v)
    if not args.quiet:
        print()
        print("\n".join(out))
    if args.json:
        metrics = {
            "matches": len(recs), "errors": total_err, "outcomes": dict(outcomes),
            "first": {LEVELS[lv]: {k: v for k, v in d.items()} for lv, d in first.items()},
            "ladder": {"%s>%s" % (LEVELS[h], LEVELS[l]): {"wins": w, "n": n, "adjudicated": a} for (h, l), (w, n, a) in pair.items()},
            "ai_us_avg_max": max(us_avg) if us_avg else 0, "ai_us_avg_mean": statistics.mean(us_avg) if us_avg else 0,
            "ai_us_worst_think": max(us_worst) if us_worst else 0, "verdict": verdict,
        }
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(metrics, f, indent=1)
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
