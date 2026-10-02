#!/usr/bin/env python3
"""BAL2: the balance-pass change list as data, plus the tool that applies it (stdlib only, deterministic).

  python3 tools/py/bal2_changes.py --src PRISTINE_DIR --dst OUTDIR [--rounds 1,2,3]     # variant for experiments (OUTDIR is recreated)
  python3 tools/py/bal2_changes.py --src PRISTINE_DIR --inplace-into game/data/balance [--rounds 1,2,3]   # final numbers
  python3 tools/py/bal2_changes.py --list                                                # print the change list with reasons

An entry is (id glob, power-index change in percent, reason). The power index (PI) of a unit is HP x damage-per-second; a change of
p % is split evenly between HP and damage of every weapon (each by sqrt(1 + p/100)). When a unit's weapons hit for less than 60 per
hit (a 3 % change would be quantised away) the whole change goes to health. Entries of all selected rounds are accumulated per unit
and applied ONCE to the pristine sheet numbers (so rounds can be re-tuned without rounding drift). Faction-wide entries (`unit.sap.*`)
touch only units that have a weapon (the framework's power_offset_pct applies to combat units). Costs, build times, speeds and ranges
are never touched by this table (the bible shows them to players; FRAMEWORK 5.15). Bands: after applying, validate_balance is run on the result and a unit it flags
(V-RNG-02 fair-cost / health band, V-RNG-06 stale derived helper) has its change scaled down by 25 % per iteration until it is clean.
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
import balance_calc as bc  # noqa: E402  (effective_dps for the derived helpers)

# (round, id glob, PI %, reason).  Round 1 = first pass from the baseline round robin + equal-spend fight grid + unit duels.
CHANGES: list[tuple[int, str, float, str]] = [
    # --- round 1 (run r1 on the shipped AI) ---------------------------------------------------------------------------------------
    # evidence: base round robin (710 games), equal-spend grid (bal2_fight mode=grid), 1v1 duels per cost (mode=units), value exchange
    (1, "unit.sap.river_marine", -5.0, "Thailand 72 % (River Marine is 31 % of its built value, duel +0.22 vs rifle line)"),
    (1, "unit.sap.naga_amphibious_carrier", -3.0, "Thailand 72 %"),
    (1, "unit.sap.arjun_assault_tank", -5.0, "India 63 %, duel +0.36 vs tank at equal cost, grid +0.39"),
    (1, "unit.sap.gaj_siege_platform", -3.0, "India 63 %"),
    (1, "unit.def.*", -2.0, "DEF faction offset: 57.5 % round robin, +0.20 equal-spend grid"),
    (1, "unit.def.ural_assault_tank", -5.0, "Russia 63 %, duel +0.51 vs tank (best T2 tank by far), grid +0.43"),
    (1, "unit.def.bear_siege_crawler", -3.0, "Russia: never lost in 24 games"),
    (1, "unit.def.saker_missile_truck", -5.0, "Kazakhstan 67 %"),
    (1, "unit.def.steppe_recon_carrier", -3.0, "Kazakhstan 67 %"),
    (1, "unit.han.canopy_ranger", -5.0, "Vietnam 61 %, duel +0.43 vs tank (infantry line with the cheap-light-vehicle and +10 % speed packages)"),
    (1, "unit.han.reed_rocket_skimmer", -3.0, "Vietnam 61 %"),
    (1, "unit.olm.gate_guard", -5.0, "El Andalus 65 %, value exchange 1.58 (lost/built 0.27 for 896 built)"),
    (1, "unit.olm.strait_frigate", -3.0, "El Andalus 65 %"),
    (1, "unit.olm.dune_rover", -5.0, "Algeria 66 %"),
    (1, "unit.olm.scorpion_rocket_buggy", -3.0, "Algeria 66 %"),
    (1, "unit.ae.rhino_rail_tank", -4.0, "South Africa 60 %, value exchange 1.36"),
    (1, "unit.ae.protea_gun_carrier", -4.0, "South Africa 60 %"),
    (1, "unit.ae.civic_rifle_team", -5.0, "Nigeria 68 %"),
    (1, "unit.ae.lagos_drone_guard", -3.0, "Nigeria 68 %"),
    (1, "unit.napc.*", 2.0, "NAPC faction offset: napc.vanilla 41-44 %, canada 41 % in the shipped and the doctrine-free runs"),
    (1, "unit.pd.*", 2.0, "PD faction offset: 44 % round robin, exchange 0.77-0.85"),
    (1, "unit.pd.shinano_adaptive_tank", 4.0, "Japan 43 %, exchange 0.77"),
    (1, "unit.pd.shogun_drone_carrier", 3.0, "Japan 43 %"),
    (1, "unit.pd.outrider_howitzer", 4.0, "Australia 39.5 %, grid -0.16"),
    (1, "unit.pd.wedge_recon_fighter", 3.0, "Australia 39.5 %"),
    (1, "unit.nec.*", 2.0, "NEC faction offset: 37 % round robin, grid -0.09 / -0.31"),
    (1, "unit.nec.fen_recon_carrier", 3.0, "Nordics 36 %"),
    (1, "unit.nec.fjord_missile_carrier", 4.0, "Nordics 36 %, fair-cost deviation -6.7 % (clamped to the band)"),
    # round 1 also contained: unit.sap.* -2 (SAP faction), unit.napc.raptor/condor/vanguard/aguila +5 (USA, Mexico).  REVERTED in round 2:
    # the doctrine ablation (ai_faction_napc.json roster patches emptied) took Mexico 19 -> 50 % and USA 31 -> 48 % with unchanged unit
    # numbers, so those two are AI-doctrine outliers and not number outliers; the doctrine-free baseline has SAP at 50 % (thailand 62,
    # india 51, vanilla 50, pakistan 36), so only its two unique-unit packages stay nerfed.
    # --- round 2 (runs clean1 = doctrine-free AI and r2 = shipped AI) -------------------------------------------------------------
    (2, "unit.sap.river_marine", -4.0, "Thailand 70 % shipped (pooled base+r1), 62 % doctrine-free, exchange 1.08-1.14"),
    (2, "unit.sap.arjun_assault_tank", -4.0, "India 64 % pooled shipped"),
    (2, "unit.sap.gaj_siege_platform", -3.0, "India 64 % pooled shipped"),
    (2, "unit.def.saker_missile_truck", -4.0, "Kazakhstan 64 % shipped, 74 % doctrine-free (best roster of 32), exchange 1.24"),
    (2, "unit.def.steppe_recon_carrier", -3.0, "Kazakhstan 64 % shipped, 74 % doctrine-free"),
    (2, "unit.olm.*", -2.0, "OLM faction offset: 64 % shipped / 58 % doctrine-free over four rosters (algeria 72 / 60, el_andalus 62 / 64)"),
    (2, "unit.olm.gate_guard", -4.0, "El Andalus 62 % shipped, 64 % doctrine-free, exchange 1.38-1.63"),
    (2, "unit.olm.dawn_laser_aa", -2.0, "Saudi Arabia 60 % shipped"),
    (2, "unit.olm.ifrit_prism_tank", -3.0, "Saudi Arabia 60 % shipped"),
    (2, "unit.han.canopy_ranger", -3.0, "Vietnam 67 % shipped, 58 % doctrine-free"),
    (2, "unit.ae.civic_rifle_team", -4.0, "Nigeria 67 % shipped, 64 % doctrine-free (clamped to the band)"),
    (2, "unit.ae.rhino_rail_tank", -3.0, "South Africa 57 % shipped, 60 % doctrine-free, exchange 1.54"),
    (2, "unit.ae.protea_gun_carrier", -3.0, "South Africa 57 % shipped, 60 % doctrine-free"),
    (2, "unit.pd.*", 2.0, "PD faction offset, second step: 43.6 % shipped, 41.5 % doctrine-free (exchange 0.73-0.96)"),
    (2, "unit.pd.outrider_howitzer", 3.0, "Australia 36 % shipped, 37.5 % doctrine-free, exchange 0.73"),
    (2, "unit.pd.wedge_recon_fighter", 3.0, "Australia 36 % shipped, 37.5 % doctrine-free"),
    (2, "unit.nec.*", 2.0, "NEC faction offset, second step: 36.8 % shipped, 44.7 % doctrine-free"),
    (2, "unit.nec.fen_recon_carrier", 3.0, "Nordics 35 % shipped, 38.6 % doctrine-free"),
    # --- round 3 (runs clean2 = doctrine-free AI and r3 = shipped AI) -------------------------------------------------------------
    (3, "unit.def.*", -2.0, "DEF faction offset, second step: 59 % doctrine-free / 56 % shipped; Kazakhstan 72 % and Russia 61 % in the doctrine-free run"),
    (3, "unit.def.saker_missile_truck", -4.0, "Kazakhstan still 72 % doctrine-free after round 2 (best roster of 32)"),
    (3, "unit.def.steppe_recon_carrier", -3.0, "Kazakhstan still 72 % doctrine-free after round 2"),
    (3, "unit.olm.*", -2.0, "OLM faction offset, second step: 59 % doctrine-free / 64 % shipped after round 2"),
    (3, "unit.olm.gate_guard", -3.0, "El Andalus 68 % doctrine-free, exchange 1.38"),
    (3, "unit.olm.strait_frigate", -3.0, "El Andalus 68 % doctrine-free"),
    (3, "unit.olm.dune_rover", -3.0, "Algeria 62 % doctrine-free after round 2"),
    (3, "unit.olm.scorpion_rocket_buggy", -3.0, "Algeria 62 % doctrine-free after round 2"),
    (3, "unit.ae.rhino_rail_tank", -3.0, "South Africa exchange 1.47 doctrine-free"),
    (3, "unit.ae.protea_gun_carrier", -3.0, "South Africa exchange 1.47 doctrine-free"),
    (3, "unit.nec.*", 2.0, "NEC faction offset, third step: 44.7 % doctrine-free, nec.vanilla 38 % in both settings"),
    (3, "unit.napc.*", 2.0, "NAPC faction offset, second step: napc.vanilla 40 % and canada 42 % doctrine-free"),
    (3, "unit.pd.*", 2.0, "PD faction offset, third step: 43 % doctrine-free and shipped, exchange 0.83-0.90"),
    (3, "unit.sap.shaheen_missile_battery", 3.0, "Pakistan 38.6 % doctrine-free (shipped 48 %)"),
    (3, "unit.sap.watchpost_recon_team", 3.0, "Pakistan 38.6 % doctrine-free"),
]


def _helper(u: dict, arch: dict, weapons: dict) -> None:
    """Recompute the derived helper (dps_vs_primary, or sortie_avg_dps_vs_primary for aircraft) the way validate_balance (V-RNG-06) does."""
    key = "sortie_avg_dps_vs_primary" if arch.get("family") == "aircraft" else "dps_vs_primary"
    if key not in u or "drone_weapon" in arch or not u.get("weapons"):
        return
    full = []
    for wid in u["weapons"]:
        w = weapons.get(wid)
        if w is None or w.get("archetype") not in bc.WA or not w.get("reload_s"):
            return
        full.append({**w, "hits_per_volley": w.get("hits_per_volley", 1)})
    rearm_full = u.get("rearm_s_full")
    mult = (rearm_full / arch["rearm_s_full"]) if (rearm_full is not None and arch.get("rearm_s_full")) else 1.0
    try:
        u[key] = round(bc.effective_dps(arch, full, mult), 1)
    except Exception:  # noqa: BLE001
        return


def _apply_once(src: Path, dst: Path, entries, caps: dict[str, float], write: bool) -> list[dict]:
    records: list[dict] = []
    for f in sorted(glob.glob(str(src / "units_*.json"))):
        d = json.load(open(f))
        weapons = {w["id"]: w for w in d.get("weapons", [])}
        dirty = False
        done_weapons: set[str] = set()
        for u in d["units"]:
            factor = 1.0
            why: list[str] = []
            for g, p, r in entries:
                if not fnmatch.fnmatch(u["id"], g):
                    continue
                if g.endswith("*") and not u.get("weapons"):
                    continue
                factor *= 1.0 + p / 100.0
                why.append("%+.1f%% %s" % (p, r))
            if not why or abs(factor - 1.0) < 1e-9:
                continue
            cap = caps.get(u["id"], 1.0)
            if cap < 1.0:
                factor = 1.0 + (factor - 1.0) * cap
                why.append("scaled x%.2f to stay inside the fair-cost band" % cap)
            ws = [weapons[w] for w in u.get("weapons", []) if w in weapons]
            small = bool(ws) and min(w["damage"] for w in ws) < 60
            hp_f = factor if (small or not ws) else math.sqrt(factor)
            dmg_f = 1.0 if (small or not ws) else math.sqrt(factor)
            old_hp = u["health"]
            u["health"] = int(round(old_hp * hp_f))
            rec = {"id": u["id"], "pi_pct": round((factor - 1) * 100, 2), "health": [old_hp, u["health"]], "damage": {}, "why": why}
            if dmg_f != 1.0:
                for w in ws:
                    if w["id"] in done_weapons:
                        continue
                    done_weapons.add(w["id"])
                    old = w["damage"]
                    w["damage"] = int(round(old * dmg_f))
                    rec["damage"][w["id"]] = [old, w["damage"]]
            arch = bc.ARCH.get(u.get("archetype", ""))
            if arch is not None:
                _helper(u, arch, weapons)
            records.append(rec)
            dirty = True
        if dirty and write:
            with open(dst / Path(f).name, "w") as fh:
                json.dump(d, fh, indent=2, ensure_ascii=False)
                fh.write("\n")
    return records


def _band_violations(balance: Path, ids: set[str]) -> set[str]:
    """Units of `ids` that validate_balance flags for the fair-cost / health band (V-RNG-02 on cost_credits or health) or a stale helper (V-RNG-06)."""
    import validate_balance as vb  # noqa: WPS433

    _, rep = vb.run(balance, ROOT / "game" / "data" / "bible" / "meridian_factions.json")
    bad = set()
    for f in rep.findings:
        if f.rule in ("V-RNG-02", "V-RNG-06") and f.entity in ids and f.severity != "I" and (
                f.field in ("cost_credits", "health", "dps_vs_primary", "sortie_avg_dps_vs_primary") and "damage per hit" not in f.message):
            bad.add(f.entity)
    return bad


def apply_to_dir(src: Path, dst: Path, rounds: set[int], quiet: bool = False, fresh: bool = True) -> list[dict]:
    """Copy src to dst (unless fresh=False) and apply the accumulated entries; shrinks a unit's change until validate_balance accepts it."""
    if fresh and src.resolve() != dst.resolve():
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    entries = [(g, p, r) for (rd, g, p, r) in CHANGES if rd in rounds]
    caps: dict[str, float] = {}
    for it in range(12):
        records = _apply_once(src, dst, entries, caps, True)
        bad = _band_violations(dst, {r["id"] for r in records})
        if not bad:
            break
        for uid in bad:
            caps[uid] = caps.get(uid, 1.0) * 0.75
    if not quiet:
        for r in records:
            print("%-40s PI %+5.1f%%  hp %5d -> %5d  dmg %s   (%s)" % (
                r["id"], r["pi_pct"], r["health"][0], r["health"][1],
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
    ap.add_argument("--json", help="write the change records to this file")
    a = ap.parse_args()
    rounds = {int(x) for x in a.rounds.split(",") if x}
    if a.list:
        for rd, g, p, r in CHANGES:
            print("r%d  %-34s %+5.1f%%  %s" % (rd, g, p, r))
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
