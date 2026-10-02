"""Shared helpers of the recipe tooling (VIEW-T1): gen_recipe_index.py, gen_recipe_stubs.py, validate_recipes.py.

Stdlib only, Python 3.9+, deterministic, never touches anything outside game/data/recipes. Reads the balance data (units_*.json,
global.json, structures.json, neutral_structures.json) to enumerate every def id the view has to draw, and resolves each id
to a view archetype through game/data/recipes/assignments.json (render spec 5.8.7 / 7.4):

    exact `overrides` > `patterns` (fnmatch, top to bottom) > `balance_to_view` (+ `ability_rules`) for units > generated stub warning

`fallbacks` (this tool's own extension, documented in assignments.json `_doc`) name the generic archetype a view archetype
falls back to while its own archetype file does not exist yet, so every id always builds a valid (if generic) model.
"""
from __future__ import annotations

import fnmatch
import glob
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
RECIPES = ROOT / "game/data/recipes"
BALANCE = ROOT / "game/data/balance"
VIEW_SRC = ROOT / "game/src/view"

CELL_M = 3.0
RECIPE_SCHEMA = "meridian.recipe/1"
ARCH_SCHEMA = "meridian.archetype/1"
STYLES_SCHEMA = "meridian.styles/1"
INDEX_SCHEMA = "meridian.recipes.index/1"
ASSIGN_SCHEMA = "meridian.recipes.assignments/1"
FOOTPRINTS_SCHEMA = "meridian.footprints/1"

# Files in game/data/recipes that are not recipes (mirrors ViewRecipeBook.RESERVED).
RESERVED = ("index", "styles", "style", "moods", "fx", "quality", "assignments", "footprints")

# Projectile recipes (the pool's kinds, VIEW-W3); they are not balance defs, so the tooling lists them here.
PROJECTILE_IDS = ("proj.bomb", "proj.missile", "proj.rocket", "proj.torpedo")


def load_json(path: Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def dumps(obj: Any, sort_keys: bool = False) -> str:
    """Canonical text of a data file: UTF-8, LF, 2-space indent, trailing newline."""
    return json.dumps(obj, indent=2, sort_keys=sort_keys, ensure_ascii=False) + "\n"


def write_if_changed(path: Path, text: str) -> bool:
    path = Path(path)
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return True


# ---------------------------------------------------------------------------------------------- defs from the balance data
class Defs:
    """Everything the view has to draw, read from game/data/balance."""

    def __init__(self) -> None:
        self.units: Dict[str, Dict[str, Any]] = {}       # id -> {faction, balance_archetype, abilities}
        self.summons: Dict[str, Dict[str, Any]] = {}     # id -> {faction, movement_class, layer, size_class}
        self.structures: Dict[str, Dict[str, Any]] = {}  # id -> {kind, fw, fh, exit_dx, exit_dy, pads}
        self.neutrals: Dict[str, Dict[str, Any]] = {}    # id -> {fw, fh, kind}
        self.projectiles: List[str] = list(PROJECTILE_IDS)

    def all_ids(self) -> List[str]:
        ids = list(self.units) + list(self.summons) + list(self.structures) + list(self.neutrals) + list(self.projectiles)
        return sorted(ids)


def _structure_kind(sid: str, g: Dict[str, Any]) -> str:
    parts = sid.split(".")
    short = parts[2] if len(parts) > 2 else parts[-1]
    if parts[1] == "shared":
        return "shared"
    if short == "relay":
        return "relay"
    for k in g.get("superweapons", {}):
        if k not in ("common", "design_targets") and short.startswith(k):
            return "superweapon"
    return "advanced"


def collect_defs(balance: Path = BALANCE) -> Defs:
    g = load_json(balance / "global.json")
    d = Defs()
    assign = g.get("unit_assignments", {})
    for f in sorted(glob.glob(str(balance / "units_*.json"))):
        sheet = load_json(Path(f))
        code = sheet.get("faction", Path(f).stem[6:])
        for u in sheet.get("units", []):
            uid = u["id"]
            a = assign.get(uid, {})
            abil = set(a.get("abilities", [])) | set(u.get("abilities", []))
            d.units[uid] = {"faction": code, "balance_archetype": u.get("archetype") or a.get("archetype", ""), "abilities": sorted(abil)}
        for s in sheet.get("summons", []):
            d.summons[s["id"]] = {"faction": code, "movement_class": s.get("movement_class", ""), "layer": s.get("layer", ""),
                                  "size_class": s.get("size_class", "")}
    gs = g.get("structures", {})
    overlay = {e["id"]: e for e in load_json(balance / "structures.json").get("structures", [])}
    for sid, ov in overlay.items():
        kind = _structure_kind(sid, g)
        short = sid.split(".")[2]
        if short in gs:
            block = gs[short]
        elif kind == "advanced":
            block = gs.get("advanced_defense", {})
        elif kind == "superweapon":
            block = gs.get("superweapon", {})
        else:
            block = {}
        fp = block.get("footprint", [1, 1])
        ex = ov.get("exit", {})
        d.structures[sid] = {"kind": kind, "fw": int(fp[0]), "fh": int(fp[1]), "exit_dx": int(ex.get("dx", 0)),
                             "exit_dy": int(ex.get("dy", fp[1])), "pads": int(block.get("pads", 0) or 0)}
    for nid, n in load_json(balance / "neutral_structures.json").get("neutrals", {}).items():
        fp = n.get("footprint", {"w": 1, "h": 1})
        d.neutrals[nid] = {"fw": int(fp.get("w", 1)), "fh": int(fp.get("h", 1)), "kind": n.get("kind", "")}
    return d


def exit_dir(dx: int, dy: int, fw: int, fh: int) -> int:
    """ViewDefAdapter._exit_dir: facing units (1024 = south) of the exit cell relative to the footprint rectangle."""
    if dy >= fh:
        return 1024
    if dy < 0:
        return 3072
    if dx >= fw:
        return 0
    if dx < 0:
        return 2048
    return 1024


def footprint_record(s: Dict[str, Any]) -> Dict[str, Any]:
    """The footprints.json record of a structure (same formulas as ViewDefAdapter._fill_structure)."""
    fw, fh = s["fw"], s["fh"]
    cx = (s["exit_dx"] + 0.5 - fw * 0.5) * CELL_M
    cz = (s["exit_dy"] + 0.5 - fh * 0.5) * CELL_M
    ed = exit_dir(s["exit_dx"], s["exit_dy"], fw, fh)
    return {"fw": fw, "fh": fh, "door_cx": cx, "door_cz": cz, "exit_dir": ed, "dock_cx": cx, "dock_cz": cz, "dock_dir": ed,
            "pads_n": s["pads"]}


def neutral_footprint_record(n: Dict[str, Any]) -> Dict[str, Any]:
    """ViewDefAdapter._fill_neutral: door anchor = one cell south of the footprint."""
    fw, fh = n["fw"], n["fh"]
    return {"fw": fw, "fh": fh, "door_cx": 0.0, "door_cz": fh * CELL_M * 0.5 + CELL_M * 0.5, "exit_dir": 1024, "dock_cx": 0.0,
            "dock_cz": fh * CELL_M * 0.5 + CELL_M * 0.5, "dock_dir": 1024, "pads_n": 0}


def build_footprints(defs: Defs) -> Dict[str, Any]:
    st: Dict[str, Any] = {}
    for sid in sorted(defs.structures):
        st[sid] = footprint_record(defs.structures[sid])
    for nid in sorted(defs.neutrals):
        st[nid] = neutral_footprint_record(defs.neutrals[nid])
    return {"schema": FOOTPRINTS_SCHEMA, "_doc": "GENERATED by tools/py/gen_recipe_index.py from game/data/balance. Metres from the footprint "
            "centre, +Z = south; the builder injects these as expression variables (render spec 5.8.1).", "structures": st}


# ---------------------------------------------------------------------------------------------- assignment resolution
class Resolved:
    """The outcome of resolving one def id."""

    def __init__(self, def_id: str, archetype: str, params: Dict[str, Any], style: str, rule: str, matched: bool) -> None:
        self.def_id = def_id
        self.archetype = archetype     # the view archetype the rules name (may not exist yet)
        self.params = params           # params from the rule
        self.style = style             # "auto" or "owner"
        self.rule = rule               # human-readable rule that matched
        self.matched = matched         # False -> V-RCP-02 warning (no rule; stub fell back to a default)


def resolve(def_id: str, defs: Defs, assign: Dict[str, Any]) -> Resolved:
    ov = assign.get("overrides", {})
    if def_id in ov:
        o = ov[def_id]
        return Resolved(def_id, o["archetype"], dict(o.get("params", {})), o.get("style", "auto"), "override", True)
    for pat in assign.get("patterns", []):
        if fnmatch.fnmatchcase(def_id, pat["match"]):
            return Resolved(def_id, pat["archetype"], dict(pat.get("params", {})), pat.get("style", "auto"), "pattern " + pat["match"], True)
    if def_id in defs.units:
        u = defs.units[def_id]
        va = assign.get("balance_to_view", {}).get(u["balance_archetype"])
        if va is not None:
            for r in assign.get("ability_rules", []):
                if r["when_view"] == va and r["has_ability"] in u["abilities"]:
                    va = r["then"]
                    break
            return Resolved(def_id, va, {}, "auto", "balance archetype " + u["balance_archetype"], True)
    return Resolved(def_id, assign.get("default_archetype", "gen_prop"), {"kind": "capsule"} if def_id.startswith("summon.") else {}, "auto", "no rule", False)


def archetype_files(recipes: Path = RECIPES) -> Dict[str, Path]:
    return {p.stem: p for p in sorted((recipes / "archetypes").glob("*.json"))}


def archetype_defaults(name: str, recipes: Path = RECIPES) -> Optional[Dict[str, Any]]:
    p = recipes / "archetypes" / (name + ".json")
    if not p.exists():
        return None
    return load_json(p).get("defaults", {})


def choose_archetype(res: Resolved, assign: Dict[str, Any], recipes: Path = RECIPES) -> Tuple[str, Dict[str, Any], List[str]]:
    """(archetype file to use, params to write, notes). The rule's archetype wins when its file exists; otherwise the generic
    fallback of assignments.json `fallbacks` is used and the rule's params are kept only where the fallback declares them."""
    notes: List[str] = []
    have = archetype_files(recipes)
    if res.archetype in have:
        dflt = archetype_defaults(res.archetype, recipes) or {}
        params = {k: v for k, v in res.params.items() if k in dflt}
        for k in res.params:
            if k not in dflt:
                notes.append("param '%s' is not declared by archetype '%s' (dropped)" % (k, res.archetype))
        return res.archetype, params, notes
    fb = assign.get("fallbacks", {}).get(res.archetype)
    if fb is None:
        notes.append("archetype '%s' does not exist and has no fallback" % res.archetype)
        return assign.get("default_archetype", "gen_prop"), {}, notes
    dflt = archetype_defaults(fb["archetype"], recipes)
    if dflt is None:
        notes.append("fallback archetype '%s' does not exist" % fb["archetype"])
        return fb["archetype"], dict(fb.get("params", {})), notes
    params = dict(fb.get("params", {}))
    for k, v in res.params.items():
        if k in dflt:
            params[k] = v
    return fb["archetype"], params, notes


def stub_recipe(res: Resolved, arch: str, params: Dict[str, Any]) -> Dict[str, Any]:
    r: Dict[str, Any] = {"schema": RECIPE_SCHEMA, "id": res.def_id, "archetype": arch, "style": "auto" if res.style == "auto" else res.style}
    if params:
        r["params"] = params
    r["meta"] = {"stub": True, "view_archetype": res.archetype, "rule": res.rule}
    return r


def recipe_files(recipes: Path = RECIPES) -> List[Path]:
    return [p for p in sorted(recipes.glob("*.json")) if p.stem not in RESERVED]


def is_stub(path: Path) -> bool:
    try:
        return bool(load_json(path).get("meta", {}).get("stub", False))
    except (OSError, ValueError):
        return False
