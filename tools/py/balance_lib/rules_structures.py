"""structures.json overlay rules (V-CMP-02, V-CNF-04/09, V-ABL-*) and the bible-structure -> global.json row mapping."""
from __future__ import annotations

from .abilities import Entity, resolve
from .context import Ctx, LoadedFile, dicts, num
from .jsonio import line_of
from .rules_files import add
from .rules_units import _Rep, check_ability_slots, registry


def global_row(ctx: Ctx, sid: str) -> tuple[str, dict] | None:
    """(global.json structures key, merged numbers) for a bible structure id, or None when it has no mapped key (V-CMP-02/04)."""
    s = ctx.g.get("structures", {})
    tags = ctx.b_structs.get(sid, {}).get("tags", [])
    key = ""
    if sid == "structure.nec.relay":
        key = "relay"
    elif "advanced_defense" in tags:
        key = "advanced_defense"
    elif "superweapon" in tags:
        key = "superweapon"
    elif sid.startswith("structure.shared."):
        key = sid.rsplit(".", 1)[1]
    row = s.get(key)
    if not isinstance(row, dict):
        return None
    row = dict(row)
    if key == "advanced_defense":
        code = sid.split(".")[1]
        for name, dfn in ctx.g.get("defenses", {}).get("advanced", {}).items():
            if isinstance(dfn, dict) and dfn.get("faction") == code:
                row["health"] = dfn.get("health", row.get("health"))
                break
    return key, row


def check_structures_file(ctx: Ctx, lf: LoadedFile) -> None:
    d = lf.data
    assert isinstance(d, dict)
    reg = registry(ctx)
    entries = dicts(d.get("structures"))
    seen: set[str] = set()
    for e in entries:
        sid = e.get("id")
        if not isinstance(sid, str):
            continue
        R = _Rep(ctx, lf, e, sid)
        if sid in seen:
            R("V-CMP-02", "id", f"structure {sid} appears more than once", "exactly once", "duplicate")
        seen.add(sid)
        if sid not in ctx.b_structs:
            R("V-CMP-02", "id", f"{sid} is not a bible structure id", "a structure id of meridian_factions.json", sid)
            continue
        b = ctx.b_structs[sid]
        gr = global_row(ctx, sid)
        for k, gk in (("health", "health"), ("armor_class", "armor_class"), ("footprint", "footprint"), ("radius_cells", "radius_cells"),
                      ("vision_cells", "vision_cells"), ("build_time_s", "build_time_s")):
            if k in e and gr:
                gv = gr[1].get(gk)
                same = (e[k] == gv) or (isinstance(e[k], (int, float)) and num(gv) is not None and float(e[k]) == float(gv))
                if same:
                    R("V-CNF-09", k, f"{k} repeats the global.json value (structures.json is an overlay and never repeats numbers)", gv, e[k], sev="I")
                else:
                    R("V-CNF-09", k, f"{k} differs from global.json structures.{gr[0]}; the overlay must not set numbers", f"global.json {gv}", e[k], sev="E")
        if "footprint_mask" in e and gr and isinstance(e["footprint_mask"], list):
            fp = gr[1].get("footprint", [0, 0])
            rows = e["footprint_mask"]
            if len(rows) != fp[1] or any(isinstance(r, str) and len(r) != fp[0] for r in rows):
                R("V-SCH-10", "footprint_mask", f"footprint_mask must have {fp[1]} rows of {fp[0]} characters (footprint {fp[0]}x{fp[1]} from global.json)",
                  f"{fp[1]} rows x {fp[0]} chars", f"{len(rows)} rows, widths {[len(r) for r in rows if isinstance(r, str)]}")
        for i, t in enumerate(e.get("tags_add") or []):
            if isinstance(t, str) and (t in ctx.locked_tags() or t in b.get("tags", [])):
                R("V-CNF-03", f"tags_add[{i}]", f"tag {t!r} is a locked/bible tag", "a free tag", t)
        if reg:
            ent = Entity("structure", list(e.get("abilities") or []), e.get("ability_params") if isinstance(e.get("ability_params"), dict) else {}, set(b.get("tags", [])), "", "")
            res = resolve(reg, ent, R, ctx)
            check_ability_slots(R, res, [])
    for sid in sorted(set(ctx.b_structs) - seen):
        add(ctx, "V-CMP-02", lf, f"bible structure {sid} ({ctx.b_structs[sid].get('name', '?')}) has no entry in structures.json (an entry with only 'id' is fine)",
            d, "structures", entity=sid, field="structures", expected="exactly one entry", found="<absent>")
    if isinstance(d.get("structures"), list) and len(entries) != len(d["structures"]):
        add(ctx, "V-SCH-10", lf, "every element of 'structures' must be an object", d, "structures", field="structures", expected="objects", found="non-object element")
