#!/usr/bin/env python3
"""Extracts the UI-relevant slice of the (read-only) bible into data/factions_slice.json.
Run from anywhere: python3 prototypes/ui/tools_py/make_faction_slice.py"""
import json, pathlib
root = pathlib.Path(__file__).resolve().parents[3]
d = json.loads((root / "Input/meridian_agent_reference/meridian_factions.json").read_text())
out = {"factions": [], "units": {}, "structures": {}, "powers": {}, "superweapons": {}}
def unit_meta(uid):
    u = d["units"][uid]
    return {"name": u["name"], "tier": u.get("tier"), "producer": u.get("producer_structure_id"),
            "cost": (u.get("base_stats") or {}).get("cost_credits"), "role": u.get("role_and_abilities", ""),
            "replaces": u.get("replaces_unit_id"), "roster": u.get("introduced_by_roster_id")}
for fid, f in d["factions"].items():
    fe = {"id": fid, "code": f["code"].lower(), "name": f["name"], "motto": f["motto"], "identity": f["identity"],
          "visual": f["visual_direction"], "lore": f["lore"], "rosters": []}
    for rid in [f["vanilla_roster_id"]] + f["subfaction_roster_ids"]:
        r = d["rosters"][rid]; res = r["resolved"]
        fe["rosters"].append({"id": rid, "kind": r["kind"], "name": r["name"].split(" / ")[-1] if r["kind"] == "vanilla" else r["name"],
            "title": r["title"], "identity": r["identity"], "modifiers": r["modifiers_text"] if isinstance(r["modifiers_text"], list) else [],
            "units": res["combat_unit_ids"], "service": res["service_unit_ids"], "structures": res["structure_ids"],
            "powers": res["support_power_ids"], "superweapon": res["superweapon_id"], "research": res["research_ids"],
            "replacements": (r["delta"] or {}).get("replacements", []), "removed": (r["delta"] or {}).get("removed_without_replacement_unit_ids", [])})
        for uid in res["combat_unit_ids"] + res["service_unit_ids"]:
            out["units"][uid] = unit_meta(uid)
        for sid in res["structure_ids"]:
            s = d["structures"][sid]
            out["structures"][sid] = {"name": s["name"], "cost": s.get("cost_credits"), "time": s.get("build_time_seconds"),
                                      "power": s.get("power_supply_delta"), "requires": s.get("requires_all_structure_ids", [])}
        for pid in res["support_power_ids"]:
            p = d["support_powers"][pid]
            out["powers"][pid] = {"name": p["name"], "cost": p.get("cost_credits"), "cooldown": p.get("cooldown_seconds"), "text": p.get("effect_text", "")}
        sw = d["superweapons"][res["superweapon_id"]]
        out["superweapons"][res["superweapon_id"]] = {"name": sw["name"], "recharge": sw["recharge_seconds"], "warning": sw["warning_seconds"], "launcher": sw["launcher_structure_id"]}
    out["factions"].append(fe)
(root / "prototypes/ui/data/factions_slice.json").write_text(json.dumps(out, indent=1))
print("wrote", len(json.dumps(out)), "bytes;", len(out["units"]), "units;", len(out["structures"]), "structures")
