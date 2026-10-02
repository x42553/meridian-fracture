#!/usr/bin/env python3
"""BAL3 report: per-roster win rate (W + D/2) / N, score share and exchange ratio, with 95 % intervals; optional before / after table (stdlib only).

  python3 tools/py/bal3_report.py FILE.jsonl [MORE.jsonl ...] [--cfg TAG] [--compare OTHER.jsonl [--compare-cfg TAG]] [--flag 35,65] [--sort win|name]

A game result: win = elimination of the opponent or an adjudicated score gap >= 25 % (the match harness' `winner`), draw otherwise.
score share = own score / (own + opponent score) (0.5 when both 0; an eliminated side scores 0): a continuous measure that is far less noisy
than the thresholded outcome, shown next to it. exch = value of the opponent's units + structures lost / own value lost (bal2 metric).
With --compare the second file is the 'after' run; rosters are matched by name and the columns show n, win % and score share for both.
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
from collections import defaultdict


def load(paths, cfg=None):
    out = []
    for p in paths:
        for line in open(p):
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if "players" in r and "error" not in r and (cfg is None or r.get("cfg") == cfg):
                out.append(r)
    return out


def games(recs):
    """Yield (roster, opponent, result 1 / 0.5 / 0, score share, how, exch, famly) per player per match."""
    for r in recs:
        ps = r["players"]
        if len(ps) != 2:
            continue
        for i in (0, 1):
            me, op = ps[i], ps[1 - i]
            w = r.get("winner", -1)
            res = 1.0 if w == i else (0.0 if w == 1 - i else 0.5)
            s0, s1 = me.get("score", 0), op.get("score", 0)
            share = 0.5 if (s0 + s1) <= 0 else s0 / (s0 + s1)
            x, ox = me.get("x", {}), op.get("x", {})
            lost = sum((x.get("lost_v") or {}).values())
            olost = sum((ox.get("lost_v") or {}).values()) + (ox.get("struct_lost_v") or 0)
            yield me["roster"], op["roster"], res, share, r.get("how", ""), (lost, olost), r.get("family")


def agg(recs):
    R = defaultdict(lambda: {"res": [], "share": [], "elim_w": 0, "elim_l": 0, "lost": 0, "olost": 0, "opp": defaultdict(list)})
    for me, op, res, share, how, (lost, olost), fam in games(recs):
        a = R[me]
        a["res"].append(res)
        a["share"].append(share)
        a["lost"] += lost
        a["olost"] += olost
        a["opp"][op].append(res)
        if how == "elimination":
            if res == 1.0:
                a["elim_w"] += 1
            elif res == 0.0:
                a["elim_l"] += 1
    return R


def ci(v):
    n = len(v)
    if n < 2:
        return 0.0
    return 1.96 * statistics.pstdev(v) / math.sqrt(n)


def fmt(a):
    n = len(a["res"])
    return n, 100 * statistics.mean(a["res"]), 100 * ci(a["res"]), 100 * statistics.mean(a["share"]), 100 * ci(a["share"])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--cfg")
    ap.add_argument("--compare", nargs="*")
    ap.add_argument("--compare-cfg")
    ap.add_argument("--flag", default="35,65")
    ap.add_argument("--sort", default="win")
    a = ap.parse_args()
    lo, hi = [float(x) for x in a.flag.split(",")]
    base = agg(load(a.files, a.cfg))
    after = agg(load(a.compare, a.compare_cfg)) if a.compare else None
    names = sorted(base, key=(lambda k: -statistics.mean(base[k]["res"])) if a.sort == "win" else (lambda k: k))
    tot = sum(len(v["res"]) for v in base.values()) // 2
    print("== %d matches (%d games), %d rosters" % (tot, tot * 2, len(base)))
    head = "%-24s %4s %6s %5s %6s %5s  E+/E-  exch" % ("roster", "n", "win%", "+-", "share", "+-")
    if after:
        head += "  ||  %4s %6s %5s %6s %5s  d_win d_share" % ("n", "win%", "+-", "share", "+-")
    print(head)
    out_b = out_a = 0
    for k in names:
        b = base[k]
        n, w, cw, s, cs = fmt(b)
        flag = " OUT" if (w < lo or w > hi) and n >= 12 else ""
        out_b += 1 if flag else 0
        ex = b["olost"] / b["lost"] if b["lost"] else 0.0
        line = "%-24s %4d %6.1f %5.1f %6.1f %5.1f  %2d/%-2d %5.2f%s" % (k.replace("roster.", ""), n, w, cw, s, cs, b["elim_w"], b["elim_l"], ex, flag)
        if after and k in after:
            n2, w2, cw2, s2, cs2 = fmt(after[k])
            fl2 = " OUT" if (w2 < lo or w2 > hi) and n2 >= 12 else ""
            out_a += 1 if fl2 else 0
            line += "  ||  %4d %6.1f %5.1f %6.1f %5.1f  %+5.1f %+5.1f%s" % (n2, w2, cw2, s2, cs2, w2 - w, s2 - s, fl2)
        print(line)
    sd = statistics.pstdev([100 * statistics.mean(v["res"]) for v in base.values()])
    print("spread sd (win%%): %.1f   outside %g-%g %%: %d" % (sd, lo, hi, out_b))
    if after:
        sd2 = statistics.pstdev([100 * statistics.mean(v["res"]) for v in after.values()])
        sh1 = statistics.pstdev([100 * statistics.mean(v["share"]) for v in base.values()])
        sh2 = statistics.pstdev([100 * statistics.mean(v["share"]) for v in after.values()])
        print("after: spread sd (win%%): %.1f   outside: %d   | score-share sd %.1f -> %.1f" % (sd2, out_a, sh1, sh2))
    ks = defaultdict(list)
    for k, v in base.items():
        ks[k.split(".")[1]].append(statistics.mean(v["res"]) * 100)
    print("faction means: " + "  ".join("%s %.1f" % (f, statistics.mean(x)) for f, x in sorted(ks.items())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
