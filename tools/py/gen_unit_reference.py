#!/usr/bin/env python3
"""Generate the human-readable unit / structure / tech reference from the data files.

Sources (single truth, never hand-edited):  game/data/bible/meridian_factions.json (names, tiers, prerequisites,
roles, roster deltas, research, powers, superweapons) + game/data/balance/{global,units_*}.json (designed numbers).

Output:  docs/units/README.md   overview, how to read, all-unit summary table, shared structures, service units
         docs/units/<code>.md   one file per faction: traits, roster table, every unit (stats, weapons, abilities),
                                defenses, superweapon, research, support powers, subfaction deltas.

Numbers are BASE values in designer units (cells, seconds, credits, hit points) BEFORE the faction/subfaction passive
modifiers and research are applied; the roster resolver (src/data/def_resolver.gd) applies those layers at match start.
Stdlib only; deterministic. Run:  python3 tools/py/gen_unit_reference.py
"""
from __future__ import annotations

import glob
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIB = json.loads((ROOT / "game/data/bible/meridian_factions.json").read_text())
GLB = json.loads((ROOT / "game/data/balance/global.json").read_text())
OUT = ROOT / "docs/units"

SHEETS: dict[str, dict] = {}
for f in sorted(glob.glob(str(ROOT / "game/data/balance/units_*.json"))):
    d = json.loads(Path(f).read_text())
    SHEETS[d["faction"] if "faction" in d else Path(f).stem[6:]] = d
UNITS: dict[str, dict] = {}
WEAPONS: dict[str, dict] = {}
SUMMONS: dict[str, dict] = {}
for code, d in SHEETS.items():
    for u in d.get("units", []):
        UNITS[u["id"]] = u
    for w in d.get("weapons", []):
        WEAPONS[w["id"]] = w
    for s in d.get("summons", []):
        SUMMONS[s["id"]] = s

ARCH = GLB["archetypes"]
FACTION_ORDER = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]


def short(sid: str) -> str:
    return sid.split(".", 2)[-1]


def num(x, nd=1):
    if x is None:
        return "—"
    if isinstance(x, float) and x == int(x):
        x = int(x)
    if isinstance(x, float):
        return f"{x:.{nd}f}".rstrip("0").rstrip(".")
    return f"{x:,}" if isinstance(x, int) and abs(x) >= 10000 else str(x)


def unit_facts(uid: str) -> dict:
    """Merge bible record + sheet + archetype defaults into one flat dict of BASE facts."""
    b = BIB["units"][uid]
    s = UNITS.get(uid, {})
    a = ARCH.get(s.get("archetype", ""), {})
    bs = b.get("base_stats") or {}

    def pick(key, akey=None):
        if key in s and s[key] is not None:
            return s[key]
        return a.get(akey or key)

    f = {
        "id": uid, "name": b["name"], "class": b["roster_class"], "tier": s.get("tier", b["tier"]),
        "producer": short(b["producer_structure_id"]),
        "prereq": [short(x) for x in b["requires_all_structure_ids"]],
        "tags": b["tags"], "role": b["role_and_abilities"],
        "replaces": b.get("replaces_unit_id"), "introduced_by": b.get("introduced_by_roster_id"),
        "archetype": s.get("archetype", "—"),
        "cost": bs.get("cost_credits") if bs.get("cost_credits") is not None else pick("cost_credits"),
        "build": pick("build_time_s"), "hp": pick("health"),
        "armor": pick("armor_class"), "move": pick("movement_class"), "layer": pick("layer"),
        "size": pick("size_class"), "speed": pick("speed_cells_s"), "vision": pick("vision_cells"),
        "radius": pick("radius_cells"), "pop": s.get("pop_n"),
        "abilities": s.get("abilities", []), "ability_params": s.get("ability_params", {}),
        "notes": s.get("notes"), "rearm": s.get("rearm_s_full"),
        "weapons": [WEAPONS[w] for w in s.get("weapons", []) if w in WEAPONS],
    }
    return f


def weapon_line(w: dict) -> tuple[str, float]:
    hits = w.get("hits_per_volley", 1)
    dps = w["damage"] * hits / w["reload_s"] if w["reload_s"] else 0.0
    extra = []
    if w.get("min_range_cells"):
        extra.append(f"min {num(w['min_range_cells'])}")
    if w.get("splash_cells"):
        extra.append(f"splash {num(w['splash_cells'])}")
    if w.get("ammo_volleys"):
        extra.append(f"{w['ammo_volleys']} volleys/sortie")
    if w.get("deploy_s"):
        extra.append(f"deploy {num(w['deploy_s'])} s")
    if w.get("suppressive"):
        extra.append("suppressive")
    if w.get("ramp_seconds"):
        extra.append(f"ramps +{w.get('ramp_max_pct', 0)}% over {num(w['ramp_seconds'])} s")
    if w.get("modes"):
        extra.append("modes: " + ", ".join(str(m) if not isinstance(m, dict) else str(m.get("id", m)) for m in w["modes"]))
    x = f", {'; '.join(extra)}" if extra else ""
    return (f"`{short(w['id'])}` ({w['archetype']}): {w['damage']}×{hits} per {num(w['reload_s'])} s = "
            f"**{dps:.0f} dps**, range {num(w['range_cells'])} cells{x}"), dps


def dps_range(f: dict) -> tuple[str, str]:
    if not f["weapons"]:
        return "—", "—"
    best = max(f["weapons"], key=lambda w: w["damage"] * w.get("hits_per_volley", 1) / max(w["reload_s"], 0.01))
    hits = best.get("hits_per_volley", 1)
    return f"{best['damage'] * hits / best['reload_s']:.0f}", num(max(w["range_cells"] for w in f["weapons"]))


def unit_block(f: dict) -> list[str]:
    L = [f"#### {f['name']} (`{f['id']}`)", ""]
    kind = "unique subfaction unit" if f["class"] == "unique_subfaction" else ("service unit" if f["class"] == "service" else "baseline")
    rep = f" — replaces **{BIB['units'][f['replaces']]['name']}** in {BIB['rosters'][f['introduced_by']]['name']}" if f["replaces"] else ""
    L.append(f"*{kind}{rep}* · **T{f['tier']}** · built at **{f['producer']}** · requires {', '.join(f['prereq']) or '—'} · tags: {', '.join(f['tags'])}")
    L.append("")
    L.append("| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |")
    L.append("|---:|---:|---:|---|---|---:|---:|---:|---|")
    L.append(f"| {num(f['cost'])} | {num(f['build'])} s | {num(f['hp'])} | {f['armor']} | {f['move']} | {num(f['speed'])} c/s | {num(f['vision'])} | {num(f['radius'])} | {f['layer']} |")
    L.append("")
    L.append(f"**Role (bible):** {f['role']}")
    if f["weapons"]:
        L.append("")
        L.append("**Weapons:**")
        for w in f["weapons"]:
            L.append(f"- {weapon_line(w)[0]}")
    elif f["class"] != "service":
        L.append("")
        L.append("**Weapons:** none (support / unarmed).")
    if f["abilities"]:
        L.append("")
        L.append("**Abilities:** " + ", ".join(f"`{a}`" for a in f["abilities"]))
        for a, p in f["ability_params"].items():
            L.append(f"  - `{a}`: {json.dumps(p, separators=(', ', ': '))}")
    if f["rearm"]:
        L.append(f"\n**Rearm (full):** {num(f['rearm'])} s")
    if f["notes"]:
        L.append(f"\n*Design note:* {f['notes']}")
    L.append("")
    return L


def summary_table(ids: list[str]) -> list[str]:
    L = ["| Unit | T | Producer | Cost | Build | HP | Armor | Speed | Vision | DPS | Range |", "|---|:-:|---|---:|---:|---:|---|---:|---:|---:|---:|"]
    for uid in ids:
        f = unit_facts(uid)
        d, r = dps_range(f)
        mark = " ★" if f["class"] == "unique_subfaction" else ""
        L.append(f"| {f['name']}{mark} | {f['tier']} | {f['producer']} | {num(f['cost'])} | {num(f['build'])} s | {num(f['hp'])} | {f['armor']} | {num(f['speed'])} | {num(f['vision'])} | {d} | {r} |")
    return L


def structure_rows() -> list[str]:
    S = GLB["structures"]
    L = ["| Structure | Cost | Build | Power | Health | Armor | Footprint | Prerequisites |", "|---|---:|---:|---:|---:|---|---|---|"]
    for sid, b in BIB["structures"].items():
        if not sid.startswith("structure.shared."):
            continue
        key = short(sid)
        g = S.get(key, {})
        pd = b.get("power_supply_delta")
        L.append(f"| {b['name']} | {num(b.get('cost_credits'))} | {num(b.get('build_time_seconds'))} s | {('+' if (pd or 0) > 0 else '')}{num(pd)} | {num(g.get('health'))} | {g.get('armor_class', '—')} | {'×'.join(map(str, g.get('footprint', []))) or '—'} | {', '.join(short(x) for x in b['requires_all_structure_ids']) or '—'} |")
    return L


def faction_doc(code: str) -> str:
    fk = f"faction.{code}"
    F = BIB["factions"][fk]
    L = [f"# {F['name']} ({F['code']})", "", f"*{F['motto']}*", "",
         f"> Generated from the bible + balance sheets by `tools/py/gen_unit_reference.py`. **Base values before roster modifiers** (cells, seconds, credits, hit points). DPS = damage × hits per volley ÷ reload.", "",
         f"**Doctrine:** {F['identity']}  ", f"**Visual direction:** {F['visual_direction']}", "", "## Faction traits (passive modifiers, applied by the resolver)", ""]
    L += [f"- {t}" for t in F["traits_text"]]
    L += ["", "## Rosters", ""]
    for rid in [F["vanilla_roster_id"]] + F["subfaction_roster_ids"]:
        R = BIB["rosters"][rid]
        L.append(f"### {R['name']}" + (f" — {R['title']}" if R.get("title") else ""))
        L.append("")
        L.append(f"*{R['identity']}*")
        L.append("")
        if R["kind"] == "subfaction":
            for m in R.get("modifiers_text", []):
                L.append(f"- modifier: {m}")
            d = R["delta"]
            for rp in d.get("replacements", []):
                L.append(f"- replaces **{BIB['units'][rp['replaced_unit_id']]['name']}** with **{BIB['units'][rp['replacement_unit_id']]['name']}**")
            for u in d.get("removed_without_replacement_unit_ids", []):
                L.append(f"- removes **{BIB['units'][u]['name']}** (no replacement)")
            for p in d.get("unavailable_support_power_ids", []):
                L.append(f"- loses vanilla-only power **{BIB['support_powers'][p]['name']}**")
            rs = BIB["research"][R["exclusive_research_id"]]
            pw = BIB["support_powers"][R["exclusive_support_power_id"]]
            L.append(f"- exclusive research: **{rs['name']}** (T{rs['tier']}, {rs['cost_credits']} cr) — {rs['effect_text']}")
            L.append(f"- exclusive power: **{pw['name']}** (T{pw['tier']}, {pw['cost_credits']} cr, {pw['cooldown_seconds']} s cooldown) — {pw['effect_text']}")
            L.append(f"- opening: {R['opening']}")
        else:
            L.append(f"- opening: {F['opening']}")
        L.append("")
    base = [u for u in F["baseline_combat_unit_ids"]]
    uniq = [uid for uid, u in BIB["units"].items() if u["faction_id"] == fk and u["roster_class"] == "unique_subfaction"]
    L += ["## All units at a glance (★ = unique subfaction unit)", ""] + summary_table(base + uniq) + [""]
    L += ["## Baseline combat units", ""]
    for uid in base:
        L += unit_block(unit_facts(uid))
    L += ["## Unique subfaction units", ""]
    for uid in uniq:
        L += unit_block(unit_facts(uid))
    # defenses and superweapon
    L += ["## Faction structures", ""]
    for sid, b in BIB["structures"].items():
        if not sid.startswith(f"structure.{code}."):
            continue
        key = short(sid)
        extra = ""
        if "superweapon" in b["tags"]:
            c = GLB["superweapons"]["common"]
            extra = f" health {num(c['health'])}, power {num(b['power_supply_delta'])}"
        else:
            adv = GLB["defenses"]["advanced"].get(key.replace("_missile_tower", "_missile_tower"))
            if adv is None:
                for k, v in GLB["defenses"]["advanced"].items():
                    if v.get("faction") == code:
                        adv = v
            if adv:
                w = adv["weapon"]
                extra = f" health {num(adv['health'])}; {w['damage']}×{w.get('hits_per_volley', 1)} per {num(w['reload_s'])} s, range {num(w['range_cells'])}"
        L.append(f"- **{b['name']}** — {num(b['cost_credits'])} cr, {num(b['build_time_seconds'])} s, power {num(b['power_supply_delta'])};{extra}. {b['description']}")
    sw = BIB["superweapons"][F["superweapon_id"]]
    L += ["", "## Superweapon", "", f"**{sw['name']}** — recharge {sw['recharge_seconds']} s, warning {sw['warning_seconds']} s.", "", sw["effect_text"], "", f"*Counterplay:* {sw['counterplay']}", ""]
    L += ["## Research", ""]
    for rid, r in BIB["research"].items():
        if r["faction_id"] == fk:
            L.append(f"- **{r['name']}** (T{r['tier']}, {r['cost_credits']} cr, {r['research_time_seconds']} s{'' if r['inherited_by_all_subfactions'] else ', subfaction-exclusive'}): {r['effect_text']}")
    L += ["", "## Support powers", ""]
    for pid, p in BIB["support_powers"].items():
        if p["faction_id"] == fk:
            L.append(f"- **{p['name']}** (T{p['tier']}, {p['cost_credits']} cr, cooldown {p['cooldown_seconds']} s{'' if p['inherited_by_all_subfactions'] else ', not inherited'}): {p['effect_text']}")
    L.append("")
    return "\n".join(L)


def readme() -> str:
    L = ["# Unit, structure and tech reference", "",
         "> **Generated** by `python3 tools/py/gen_unit_reference.py` from the bible (`game/data/bible/meridian_factions.json`) and the balance sheets (`game/data/balance/`). Do not edit by hand — change the data and regenerate.", "",
         "## How to read", "",
         "- All numbers are **base values before roster modifiers**. At match start the resolver applies (1) faction passive modifiers, (2) subfaction modifiers, (3) research / temporary effects, with the bible's layering rule and floors/caps (cost and build time never below 60 % of base, reload never below 50 %, combined damage resistance never above 50 %).",
         "- Units of measure: distances in **cells** (1 cell = 3 m in the 3D view), time in **seconds** at normal game speed, speed in **cells/second**, cost in **credits**, health in **hit points**.",
         "- **DPS** = damage × hits per volley ÷ reload interval of the unit's best weapon; the damage-type × armor-class matrix (`docs/balance/TAXONOMY.md`) scales it against real targets. **Range** = longest weapon range.",
         "- ★ marks unique subfaction units (they replace a vanilla unit in that roster only). Numbers the bible specifies (structure costs, service-unit costs, research/power costs, tiers, prerequisites) are never overridden; everything else is designed in `docs/balance/FRAMEWORK.md` and tuned later by AI-vs-AI simulation.",
         "- Design status: the numbers were tuned by AI self-play (rounds BAL2 and BAL3: unit sheets inside the fair-cost band, and in a 1,140-match Hard round robin no roster outside 35-65 % wins) and have **not been playtested by humans**.", "",
         "## Factions", ""]
    for code in FACTION_ORDER:
        F = BIB["factions"][f"faction.{code}"]
        L.append(f"- [{F['name']} ({F['code']})]({code}.md) — {F['identity']}")
    L += ["", "## Shared structures (all factions)", ""] + structure_rows() + [""]
    L += ["## Shared service units", ""]
    L += ["| Unit | Cost | Build | HP | Speed | Notes |", "|---|---:|---:|---:|---:|---|"]
    for uid, b in BIB["units"].items():
        if b["roster_class"] != "service":
            continue
        f = unit_facts(uid)
        L.append(f"| {f['name']} | {num(f['cost'])} | {num(f['build'])} s | {num(f['hp'])} | {num(f['speed'])} | {f['role']} |")
    L += ["", "## All combat units (base values)", ""]
    for code in FACTION_ORDER:
        F = BIB["factions"][f"faction.{code}"]
        ids = list(F["baseline_combat_unit_ids"]) + [u for u, x in BIB["units"].items() if x["faction_id"] == f"faction.{code}" and x["roster_class"] == "unique_subfaction"]
        L += [f"### {F['name']}", ""] + summary_table(ids) + [""]
    e = GLB["economy"]
    L += ["## Economy constants (from `global.json`)", "", "```json", json.dumps({k: e[k] for k in list(e)[:16]}, indent=1)[:1800], "```", ""]
    return "\n".join(L)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "README.md").write_text(readme(), encoding="utf-8")
    for code in FACTION_ORDER:
        (OUT / f"{code}.md").write_text(faction_doc(code), encoding="utf-8")
    n = sum(1 for _ in OUT.glob("*.md"))
    print(f"wrote {n} files in {OUT} ({sum(p.stat().st_size for p in OUT.glob('*.md')) // 1024} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
