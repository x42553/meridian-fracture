"""Rules on global.json and the bible: frozen vocabulary and bible constants (V-CNF-05), matrices (V-RNG-04/05), tier/prerequisite sanity (V-TIER-*)."""
from __future__ import annotations

from . import vocab
from .context import Ctx
from .rules_files import add
from .rules_structures import global_row

G = "global.json"
B = "bible"
NON_WATER = ["road", "open", "rough", "forest", "marsh", "cliff"]


def check_global(ctx: Ctx) -> None:
    if ctx.g_error:
        add(ctx, "V-SCH-01", G, ctx.g_error, expected="valid JSON object", found="unreadable")
        return
    g = ctx.g

    def X(rule: str, msg: str, exp: object = "", found: object = "", ent: str = "", fld: str = "") -> None:
        add(ctx, rule, G, msg, entity=ent, field=fld, expected=exp, found=found)
    if g.get("version") != 1:
        X("V-SCH-01", "global.json must carry version == 1", 1, g.get("version"), fld="version")
    conv = g.get("conventions", {})
    if conv.get("tps") != 20 or conv.get("cell_units") != 1024:
        X("V-CNF-05", "conventions must be tps 20 / cell_units 1024", "20 / 1024", f"{conv.get('tps')} / {conv.get('cell_units')}", fld="conventions")
    # ---- frozen vocabulary
    dts = g.get("damage_types", [])
    if [d.get("id") for d in dts] != vocab.DAMAGE_TYPES or [d.get("index") for d in dts] != list(range(7)):
        X("V-CNF-05", "damage_types differ from the frozen TAXONOMY list", vocab.DAMAGE_TYPES, [d.get("id") for d in dts], fld="damage_types")
    for d in dts:
        if d.get("id") in vocab.DAMAGE_GROUPS and (sorted(d.get("groups", [])) != sorted(vocab.DAMAGE_GROUPS[d["id"]]) or bool(d.get("nonlethal")) != (d["id"] in vocab.NONLETHAL)):
            X("V-CNF-05", "damage type resist groups / nonlethal flag differ from TAXONOMY", f"{vocab.DAMAGE_GROUPS[d['id']]} nonlethal={d['id'] in vocab.NONLETHAL}",
              f"{d.get('groups')} nonlethal={d.get('nonlethal')}", d["id"], "groups")
    if g.get("resist_groups") != vocab.RESIST_GROUPS:
        X("V-CNF-05", "resist_groups differ from the frozen list", vocab.RESIST_GROUPS, g.get("resist_groups"), fld="resist_groups")
    acs = g.get("armor_classes", [])
    if [a.get("id") for a in acs] != vocab.ARMOR_CLASSES or [a.get("index") for a in acs] != list(range(11)):
        X("V-CNF-05", "armor_classes differ from the frozen TAXONOMY list", vocab.ARMOR_CLASSES, [a.get("id") for a in acs], fld="armor_classes")
    if g.get("layers") != vocab.LAYERS:
        X("V-CNF-05", "layers differ from the frozen list", vocab.LAYERS, g.get("layers"), fld="layers")
    if g.get("fire_modes") != vocab.FIRE_MODES:
        X("V-CNF-05", "fire_modes differ from the frozen list", vocab.FIRE_MODES, g.get("fire_modes"), fld="fire_modes")
    if sorted(g.get("size_classes", {})) != sorted(vocab.SIZE_CLASSES):
        X("V-CNF-05", "size_classes differ from the frozen list", sorted(vocab.SIZE_CLASSES), sorted(g.get("size_classes", {})), fld="size_classes")
    if g.get("terrain_kinds") != vocab.TERRAIN_KINDS:
        X("V-CNF-05", "terrain_kinds differ from the frozen list", vocab.TERRAIN_KINDS, g.get("terrain_kinds"), fld="terrain_kinds")
    mcs = g.get("movement_classes", {})
    if list(mcs) != vocab.MOVE_CLASSES and sorted(mcs) != sorted(vocab.MOVE_CLASSES):
        X("V-CNF-05", "movement_classes differ from the frozen list", vocab.MOVE_CLASSES, list(mcs), fld="movement_classes")
    for i, n in enumerate(vocab.MOVE_CLASSES):
        if n in mcs and mcs[n].get("index") != i:
            X("V-CNF-05", f"movement class {n} has the wrong frozen index", i, mcs[n].get("index"), n, "index")
    was = g.get("weapon_archetypes", {})
    if sorted(was) != sorted(vocab.WEAPON_ARCHETYPES):
        X("V-CNF-05", "weapon_archetypes differ from the frozen 27", sorted(set(vocab.WEAPON_ARCHETYPES) ^ set(was)), "", fld="weapon_archetypes")
    for i, n in enumerate(vocab.WEAPON_ARCHETYPES):
        if n in was and was[n].get("index") != i:
            X("V-CNF-05", f"weapon archetype {n} has the wrong frozen index", i, was[n].get("index"), n, "index")
    cap = g.get("resistance_rules", {}).get("cap_pct")
    bcap = ctx.conv.get("maximum_combined_damage_resistance_fraction")
    if isinstance(bcap, (int, float)) and cap != round(bcap * 100):
        X("V-CNF-05", "resistance cap differs from the bible", round(bcap * 100), cap, fld="resistance_rules.cap_pct")
    # ---- V-RNG-04 damage matrix
    dm = g.get("damage_matrix", {})
    for dt in vocab.DAMAGE_TYPES:
        row = dm.get(dt)
        if not isinstance(row, dict):
            X("V-RNG-04", f"damage matrix row {dt!r} is missing", "row", "<absent>", dt)
            continue
        for ac in vocab.ARMOR_CLASSES:
            v = row.get(ac)
            if not isinstance(v, int) or isinstance(v, bool) or not 0 <= v <= 300:
                X("V-RNG-04", f"damage matrix cell {dt} x {ac} must be an integer percent 0-300", "0..300", v, dt, ac)
    # ---- V-RNG-05 movement table
    for mn in vocab.MOVE_CLASSES:
        m = mcs.get(mn)
        if not isinstance(m, dict):
            X("V-RNG-05", f"movement class {mn!r} is missing", "class", "<absent>", mn)
            continue
        t = m.get("terrain_speed_pct", {})
        for tk in vocab.TERRAIN_KINDS:
            v = t.get(tk)
            if not isinstance(v, (int, float)) or not 0 <= v <= 200:
                X("V-RNG-05", f"terrain speed {mn} x {tk} must be 0-200 %", "0..200", v, mn, tk)
        vals = [t.get(k, 0) for k in vocab.TERRAIN_KINDS]
        if m.get("layer") not in vocab.LAYERS:
            X("V-RNG-05", f"movement class {mn} has an invalid layer", vocab.LAYERS, m.get("layer"), mn, "layer")
        if mn == "static" and any(vals):
            X("V-RNG-05", "static must be 0 on every terrain", 0, vals, mn)
        if mn.startswith("air_") and not all(v > 0 for v in vals):
            X("V-RNG-05", "air classes must be > 0 on every terrain", "> 0", vals, mn)
        if mn == "naval" and any(t.get(k, 0) for k in NON_WATER):
            X("V-RNG-05", "naval must be 0 on every non-water terrain", 0, {k: t.get(k) for k in NON_WATER}, mn)
        if mn in ("foot", "wheeled", "tracked") and (t.get("deep") or t.get("cliff")):
            X("V-RNG-05", f"{mn} must be 0 on deep water and cliff", 0, {"deep": t.get("deep"), "cliff": t.get("cliff")}, mn)
        if mn == "amphibious" and not t.get("deep"):
            X("V-RNG-05", "amphibious must be > 0 on deep water", "> 0", t.get("deep"), mn, "deep")
    # ---- structures / service units vs bible (V-CNF-05b, V-CMP-02/04)
    for sid, b in sorted(ctx.b_structs.items()):
        gr = global_row(ctx, sid)
        if gr is None:
            X("V-CMP-02", f"bible structure {sid} has no mapped key in global.json structures / defenses", "a structures key", "<none>", sid, "structures")
            continue
        key, row = gr
        for gk in ("health", "armor_class", "footprint", "vision_cells"):
            if row.get(gk) is None:
                X("V-CMP-04", f"global.json structures.{key} lacks {gk} (needed by {sid})", gk, "<absent>", sid, gk)
        if b.get("cost_credits") is not None and row.get("cost_credits") != b["cost_credits"]:
            X("V-CNF-05", f"structure cost differs from the bible ({sid} via structures.{key})", b["cost_credits"], row.get("cost_credits"), sid, "cost_credits")
        if b.get("power_supply_delta") is not None and row.get("power_delta") != b["power_supply_delta"]:
            X("V-CNF-05", f"structure power differs from the bible ({sid} via structures.{key})", b["power_supply_delta"], row.get("power_delta"), sid, "power_delta")
        bt = b.get("build_time_seconds")
        if bt is not None and row.get("build_time_s") != bt:
            X("V-CNF-05", f"structure build time differs from the bible ({sid} via structures.{key})", bt, row.get("build_time_s"), sid, "build_time_s")
        if bt is None and row.get("build_time_s") is None and b.get("cost_credits", 0) != 0:
            X("V-CMP-04", f"{sid}: bible build time is null and global.json structures.{key} has none", "build_time_s", "<absent>", sid, "build_time_s")
    sv = {"engineer": "unit.shared.engineer", "collector": "unit.shared.collector", "mcv": "unit.shared.mobile_construction_vehicle",
          "landing_transport": "unit.shared.landing_transport"}
    for k, uid in sv.items():
        bc = ctx.b_units.get(uid, {}).get("base_stats", {}).get("cost_credits")
        if bc is not None and g.get("service_units", {}).get(k, {}).get("cost_credits") != bc:
            X("V-CNF-05", f"service unit {k} cost differs from the bible", bc, g.get("service_units", {}).get(k, {}).get("cost_credits"), uid, "cost_credits")
    cc = g.get("economy", {}).get("collector", {}).get("capacity_credits")
    sc = g.get("service_units", {}).get("collector", {}).get("capacity_credits")
    if cc is not None and sc is not None and cc != sc:
        X("V-CNF-09", "collector capacity differs between global.json economy.collector and service_units.collector", f"economy.collector {cc}", f"service_units.collector {sc}",
          "collector", "capacity_credits")


def check_bible(ctx: Ctx) -> None:
    """V-TIER-01/02/03 on the bible prerequisite data (file 'bible')."""
    if ctx.bible_error:
        add(ctx, "V-SCH-01", B, ctx.bible_error, expected="valid JSON", found="unreadable")
        return
    treq = {int(k): v for k, v in ctx.conv.get("tier_requirements", {}).items()}

    def X(rule: str, msg: str, exp: object, found: object, ent: str, fld: str) -> None:
        add(ctx, rule, B, msg, entity=ent, field=fld, expected=exp, found=found)
    for uid, u in sorted(ctx.b_units.items()):
        want = [u.get("producer_structure_id")] + treq.get(u.get("tier"), [])
        if u.get("requires_all_structure_ids") != want:
            X("V-TIER-01", "unit prerequisites differ from [producer] + tier_requirements[tier]", want, u.get("requires_all_structure_ids"), uid, "requires_all_structure_ids")
    for sect, label in (("research", "research"), ("support_powers", "power")):
        for rid, r in sorted(ctx.bible.get(sect, {}).items()):
            if r.get("requires_all_structure_ids") != treq.get(r.get("tier"), []) and set(r.get("requires_all_structure_ids", [])) != set(treq.get(r.get("tier"), [])):
                X("V-TIER-01", f"{label} prerequisites differ from tier_requirements[tier]", treq.get(r.get("tier"), []), r.get("requires_all_structure_ids"), rid,
                  "requires_all_structure_ids")
    graph = {sid: [x for x in s.get("requires_all_structure_ids", [])] for sid, s in ctx.b_structs.items()}
    hq = graph.get("structure.shared.headquarters")
    if hq:
        X("V-TIER-02", "the Headquarters must have no prerequisites", [], hq, "structure.shared.headquarters", "requires_all_structure_ids")
    state: dict[str, int] = {}

    def dfs(n: str, stack: list[str]) -> None:
        state[n] = 1
        for m in graph.get(n, []):
            if state.get(m) == 1:
                X("V-TIER-02", "structure prerequisite cycle: " + " -> ".join(stack + [n, m]), "acyclic", "cycle", n, "requires_all_structure_ids")
            elif state.get(m) is None and m in graph:
                dfs(m, stack + [n])
        state[n] = 2
    for n in sorted(graph):
        if state.get(n) is None:
            dfs(n, [])

    def closure(seed: list[str]) -> set[str]:
        out: set[str] = set()
        todo = list(seed)
        while todo:
            s = todo.pop()
            if s in out:
                continue
            out.add(s)
            todo.extend(graph.get(s, []))
        return out
    dock = "structure.shared.dock"
    for uid, u in sorted(ctx.b_units.items()):
        tags = u.get("tags", [])
        if "ship" in tags or uid == "unit.shared.landing_transport":
            continue
        if dock in closure(list(u.get("requires_all_structure_ids", [])) + [u.get("producer_structure_id", "")]):
            X("V-TIER-03", "a non-naval unit needs the Dock (land-only playability)", "no dock in the prerequisite closure", dock, uid, "requires_all_structure_ids")
    for sid, s in sorted(ctx.b_structs.items()):
        if sid != dock and dock in closure(s.get("requires_all_structure_ids", [])):
            X("V-TIER-03", "a structure needs the Dock (land-only playability)", "no dock in the prerequisite closure", dock, sid, "requires_all_structure_ids")
    for sect in ("research", "support_powers"):
        for rid, r in sorted(ctx.bible.get(sect, {}).items()):
            if dock in closure(r.get("requires_all_structure_ids", [])):
                X("V-TIER-03", "a research/power needs the Dock (land-only playability)", "no dock in the prerequisite closure", dock, rid, "requires_all_structure_ids")
