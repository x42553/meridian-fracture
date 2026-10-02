#!/usr/bin/env python3
"""BAL3: the rebalance-in-the-new-AI-meta change list as data, plus the tool that applies it on top of the post-BAL2 sheets (stdlib only).

  python3 tools/py/bal3_changes.py --src PRE_BAL3_DIR --dst OUTDIR [--rounds 1,2,3]          # variant for experiments (OUTDIR is recreated)
  python3 tools/py/bal3_changes.py --src PRE_BAL3_DIR --inplace-into game/data/balance        # final numbers
  python3 tools/py/bal3_changes.py --list

Entry = (round, id glob, kind, percent, reason). kind: pi (health x damage split evenly, like BAL2), hp, dmg (all weapons of the unit), cost, build
(build_time_s). Entries of the selected rounds accumulate per unit and apply ONCE to the PRE-BAL3 sheet numbers (the sheets of the tree before BAL3;
keep a copy), so rounds can be re-tuned without rounding drift. Faction-wide globs (ending in `*`) touch only units with a weapon for pi/hp/dmg, and
every unit for cost/build. After applying, validate_balance runs on the result and a unit flagged for the fair-cost / health band or a stale helper
has its change scaled down by 25 % per iteration (as BAL2). Costs round to 5 (< 1000) or 25 credits.
"""
from __future__ import annotations

import argparse
import fnmatch
import glob
import json
import math
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "py"))
import bal2_changes as b2  # noqa: E402
import balance_calc as bc  # noqa: E402

CHANGES: list[tuple[int, str, str, float, str]] = [
    # --- round 1 (baseline: 768-match Hard RR + 372 extension matches on suspects, n=96 each; equal-spend grid) -------------------------
    (1, "unit.napc.rifle_squad", "pi", -4.0, "NAPC faction now strong: canada 69 %, napc.vanilla 58 %, exchange 1.4-1.6 (BAL2 had added +4 in the old meta)"),
    (1, "unit.napc.guardian_tank", "pi", -4.0, "NAPC vanilla / canada line: grid +0.10, RR 58 / 69 %"),
    (1, "unit.napc.javelin_team", "pi", -4.0, "NAPC vanilla / canada line"),
    (1, "unit.napc.narwhal_amphibious_tank", "pi", -3.0, "Canada 69 % (95 % interval 63-76), exchange 1.64: amphibious +10 % health on all terrain"),
    (1, "unit.napc.beaver_amphibious_apc", "pi", -3.0, "Canada 69 %"),
    (1, "unit.ae.union_guard", "pi", 5.0, "AE vanilla 35 %, kongo 31 %, exchange 0.91 / 0.81 (no faction offset so far)"),
    (1, "unit.ae.buffalo_tank", "pi", 5.0, "AE vanilla 35 %, kongo 31 %"),
    (1, "unit.ae.pike_team", "pi", 5.0, "AE vanilla 35 %, kongo 31 %"),
    (1, "unit.ae.forge_howitzer", "pi", 5.0, "AE vanilla 35 %, kongo 31 %"),
    (1, "unit.ae.weaver_aa", "pi", 5.0, "AE vanilla 35 %, kongo 31 %"),
    (1, "unit.pd.ranger_marine", "pi", 4.0, "PD: australia 35 %, japan 38 %, exchange 0.89"),
    (1, "unit.pd.tide_tank", "pi", 4.0, "PD: australia 35 % (land vehicle health -10 % modifier), japan 38 %"),
    (1, "unit.pd.harpoon_team", "pi", 4.0, "PD: australia 35 %, japan 38 %"),
    (1, "unit.pd.storm_aa", "pi", 4.0, "PD: australia 35 %, japan 38 %"),
    (1, "unit.pd.outrider_howitzer", "pi", 3.0, "Australia 35 %, 24 of 27 losses by elimination"),
    (1, "unit.pd.wedge_recon_fighter", "pi", 3.0, "Australia 35 %"),
    (1, "unit.nec.jager_squad", "pi", 3.0, "NEC: eurocorps 26 %, alpine 32 %, exchange 0.87 / 0.98"),
    (1, "unit.nec.spike_team", "pi", 3.0, "NEC: eurocorps 26 %, alpine 32 %"),
    (1, "unit.nec.leopard_tank", "pi", 3.0, "NEC: alpine 32 %, nordics 41 %"),
    (1, "unit.nec.archer_spg", "pi", 3.0, "NEC: alpine 32 %, nordics 41 %"),
    (1, "unit.nec.marte_heavy_mbt", "build", -8.0, "Eurocorps 26 %: all land combat vehicle build time +10 % (modifier) and Marte already at the fair-cost floor; first tank 7:20 vs 5:00 field"),
    (1, "unit.nec.charlemagne_siege_tank", "build", -8.0, "Eurocorps 26 %: build time +10 % modifier, fair-cost floor reached"),
    # --- round 2 (r1 measured on the same 1140 matches: canada 69 -> 55, outside 35-65 % 6 -> 1; remaining low rosters: ae.vanilla 40, kongo 37) -----
    (2, "unit.ae.union_guard", "pi", 2.0, "AE vanilla 39.6 %, kongo 37 % after round 1"),
    (2, "unit.ae.buffalo_tank", "pi", 2.0, "AE vanilla 39.6 %, kongo 37 % after round 1"),
    (2, "unit.ae.pike_team", "pi", 2.0, "AE vanilla 39.6 %, kongo 37 % after round 1"),
    (2, "unit.ae.forge_howitzer", "pi", 2.0, "AE vanilla 39.6 %, kongo 37 % after round 1"),
    (2, "unit.ae.weaver_aa", "pi", 2.0, "AE vanilla 39.6 %, kongo 37 % after round 1"),
    # --- round 3 (r2 on the 5 rosters: kongo 52, ae.vanilla 44, japan 47 (AI eco dials); australia 38, sap.vanilla 37 still low) -------------------
    (3, "unit.pd.ranger_marine", "pi", 2.0, "Australia 38 % after round 2 (eco dials), grid mid / heavy negative"),
    (3, "unit.pd.tide_tank", "pi", 2.0, "Australia 38 % after round 2"),
    (3, "unit.pd.harpoon_team", "pi", 2.0, "Australia 38 % after round 2"),
    (3, "unit.pd.outrider_howitzer", "pi", 2.0, "Australia 38 % after round 2"),
    (3, "unit.pd.wedge_recon_fighter", "pi", 2.0, "Australia 38 % after round 2"),
    (3, "unit.sap.arjun_assault_tank", "pi", -3.0, "India 64 % at n=96 (65.6 % after the other round-3 changes), exchange 2.1, 26 eliminations won vs 3 lost; grid +0.37"),
    (3, "unit.sap.gaj_siege_platform", "pi", -3.0, "India 64-66 %, exchange 2.1"),
]

# AI personality dials changed by BAL3 (game/data/balance/ai/ai_personality.json, row -> {key: new value}); old values in the reasons. Applied with
# `python3 tools/py/bal3_changes.py --apply-ai game/data/balance/ai/ai_personality.json`. Each was measured on the paired 1140-match round robin (n = 96 per roster).
AI_DIALS: dict[str, tuple[dict, str]] = {
    "roster.nec.eurocorps": ({"retreat_hp_pct": 50, "return_hp_pct": 75, "defense_pct": 15, "siege": 50},
                             "was 35 / 85 / 25 / 60; 25.5 % -> 52-54 %: the 25 % defence share and the siege weight starved its field army (7 combat units alive at the end vs 21)"),
    "roster.pd.australia": ({"eco_x10": 8, "expand": "E"}, "was none / D; 8 collectors vs 10, income at min 10 about 8 % below the field; 35 % -> 39 %"),
    "roster.pd.japan": ({"eco_x10": 6, "expand": "E"}, "was none / D; 8.6 collectors; 38 % -> 50 %"),
    "roster.ae.kongo": ({"eco_x10": 5}, "was none; 8.9 collectors, 4.4 lost; 31 % -> 47-52 % together with the AE +7 % unit offset"),
    "roster.sap.vanilla": ({"eco_x10": 5, "aggression": 45, "defense_pct": 20, "expand": "E"}, "was none / 35 / 30 / D; 39 % -> 59 %"),
}


def apply_ai(path: Path) -> None:
    d = json.loads(path.read_text())
    for rid, (row, _why) in AI_DIALS.items():
        d["rosters"][rid].update(row)
    text = json.dumps(d, indent=1, ensure_ascii=False)
    path.write_text(text + ("\n" if path.read_text().endswith("\n") else ""))


def _rc(v: float) -> int:
    return int(round(v / (5 if v < 1000 else 25)) * (5 if v < 1000 else 25))


def _apply_once(src: Path, dst: Path, entries, caps: dict[str, float], write: bool) -> list[dict]:
    records: list[dict] = []
    for f in sorted(glob.glob(str(src / "units_*.json"))):
        d = json.load(open(f))
        weapons = {w["id"]: w for w in d.get("weapons", [])}
        dirty = False
        done_weapons: set[str] = set()
        for u in d["units"]:
            fac = {"pi": 1.0, "hp": 1.0, "dmg": 1.0, "cost": 1.0, "build": 1.0}
            why: list[str] = []
            for g, kind, p, r in entries:
                if not fnmatch.fnmatch(u["id"], g):
                    continue
                if g.endswith("*") and kind in ("pi", "hp", "dmg") and not u.get("weapons"):
                    continue
                fac[kind] *= 1.0 + p / 100.0
                why.append("%s %+.1f%% %s" % (kind, p, r))
            if not why:
                continue
            cap = caps.get(u["id"], 1.0)
            if cap < 1.0:
                fac = {k: 1.0 + (v - 1.0) * cap for k, v in fac.items()}
                why.append("scaled x%.2f to stay inside the fair-cost band" % cap)
            ws = [weapons[w] for w in u.get("weapons", []) if w in weapons]
            small = bool(ws) and min(w["damage"] for w in ws) < 60
            pi = fac["pi"]
            hp_f = fac["hp"] * (pi if (small or not ws) else math.sqrt(pi))
            dmg_f = fac["dmg"] * (1.0 if (small or not ws) else math.sqrt(pi))
            rec = {"id": u["id"], "health": [u["health"], u["health"]], "damage": {}, "cost": [u["cost_credits"], u["cost_credits"]],
                   "build": [u.get("build_time_s"), u.get("build_time_s")], "why": why}
            u["health"] = int(round(u["health"] * hp_f))
            rec["health"][1] = u["health"]
            if dmg_f != 1.0:
                for w in ws:
                    if w["id"] in done_weapons:
                        continue
                    done_weapons.add(w["id"])
                    old = w["damage"]
                    w["damage"] = int(round(old * dmg_f))
                    rec["damage"][w["id"]] = [old, w["damage"]]
            if fac["cost"] != 1.0:
                u["cost_credits"] = _rc(u["cost_credits"] * fac["cost"])
                rec["cost"][1] = u["cost_credits"]
            if fac["build"] != 1.0 and "build_time_s" in u:
                u["build_time_s"] = round(u["build_time_s"] * fac["build"], 1)
                rec["build"][1] = u["build_time_s"]
            arch = bc.ARCH.get(u.get("archetype", ""))
            if arch is not None:
                b2._helper(u, arch, weapons)
            records.append(rec)
            dirty = True
        if dirty and write:
            with open(dst / Path(f).name, "w") as fh:
                json.dump(d, fh, indent=2, ensure_ascii=False)
                fh.write("\n")
    return records


def apply_to_dir(src: Path, dst: Path, rounds: set[int], quiet: bool = False, fresh: bool = True) -> list[dict]:
    if fresh and src.resolve() != dst.resolve():
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    entries = [(g, k, p, r) for (rd, g, k, p, r) in CHANGES if rd in rounds]
    caps: dict[str, float] = {}
    records: list[dict] = []
    it = 0
    for it in range(12):
        records = _apply_once(src, dst, entries, caps, True)
        bad = b2._band_violations(dst, {r["id"] for r in records})
        if not bad:
            break
        for uid in bad:
            caps[uid] = caps.get(uid, 1.0) * 0.75
    if not quiet:
        for r in records:
            print("%-40s hp %5d -> %5d  cost %5d -> %5d  bt %s -> %s  dmg %s   (%s)" % (
                r["id"], r["health"][0], r["health"][1], r["cost"][0], r["cost"][1], r["build"][0], r["build"][1],
                ", ".join("%s %d->%d" % (k.split(".", 2)[-1], v[0], v[1]) for k, v in r["damage"].items()) or "-", "; ".join(r["why"])))
        print("%d units changed in %s (%d band iterations, %d units scaled down)" % (len(records), dst, it + 1, len(caps)))
    return records


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src")
    ap.add_argument("--dst")
    ap.add_argument("--inplace-into")
    ap.add_argument("--rounds", default="1,2,3")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--apply-ai", help="apply AI_DIALS to this ai_personality.json")
    ap.add_argument("--json")
    a = ap.parse_args()
    rounds = {int(x) for x in a.rounds.split(",") if x}
    if a.apply_ai:
        apply_ai(Path(a.apply_ai))
        return 0
    if a.list:
        for rd, g, k, p, r in CHANGES:
            print("r%d  %-34s %-5s %+5.1f%%  %s" % (rd, g, k, p, r))
        for rid, (row, why) in AI_DIALS.items():
            print("ai  %-34s %s  (%s)" % (rid, row, why))
        return 0
    if not a.src or not (a.dst or a.inplace_into):
        ap.error("--src and --dst/--inplace-into")
    dst = Path(a.dst or a.inplace_into)
    recs = apply_to_dir(Path(a.src), dst, rounds, fresh=not a.inplace_into)
    if a.json:
        Path(a.json).write_text(json.dumps(recs, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
