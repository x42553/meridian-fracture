#!/usr/bin/env python3
"""Check the five rules files under game/data/balance/ (spec data_balance 7.9-7.14, BAL-09). Stdlib only, read-only.

  python3 tools/py/check_rules_data.py            # exit 0 = no ERROR (WARN allowed), exit 1 = at least one ERROR

Files: research_effects.json (40), power_actions.json (48), zone_templates.json, faction_traits.json (8 factions, every traits_text covered
exactly once), neutral_structures.json (6 tech structures + 2 deposit kinds). Superweapons are NOT a file (compiled from global.json).

Checks: envelope/schema key, id == bible id set, sorted ids, 3-decimal numeric literals (V-SCH-04; *_pct <= 2, V-SCH-06), unit suffix in params
objects (V-SCH-07), bible-only fields absent (V-CNF-04), effect/selector/condition vocabulary (7.5), ability kinds/templates/params against
ability_kinds.json, zone / damage_ref / structure / unit / modifier references, prose-number cross-check (V-CNF-06: prose numbers appear as leaf
values or in bible_numbers; bible_numbers subset of prose), deposit numbers equal global.json (V-CNF-09).
Summons live in units_<code>.json (other authors): only the id shape is checked; unresolved ids are WARN.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BAL = ROOT / "game" / "data" / "balance"
BIBLE = ROOT / "game" / "data" / "bible" / "meridian_factions.json"

ERR: list[str] = []
WRN: list[str] = []
INFO: list[str] = []


def err(f: str, path: str, msg: str) -> None:
    ERR.append(f"ERROR {f}: {path}: {msg}")


def warn(f: str, path: str, msg: str) -> None:
    WRN.append(f"WARN  {f}: {path}: {msg}")


class Lit(float):
    """Float that remembers its source literal (decimal count check)."""
    lit = ""


def _pf(s: str) -> Lit:
    v = Lit(s)
    v.lit = s
    return v


def load(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8"), parse_float=_pf)
    except (OSError, ValueError) as e:
        return e


WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12}
NUM_RE = re.compile(r"(?<![A-Za-z0-9_.])\d+(?:\.\d+)?(?![A-Za-z0-9_])|\b(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b", re.I)


def prose_numbers(text: str) -> list:
    out = []
    for m in NUM_RE.finditer(text):
        s = m.group(0)
        v = WORDS[s.lower()] if s.lower() in WORDS else float(s)
        if isinstance(v, float) and v.is_integer():
            v = int(v)
        if v not in out:
            out.append(v)
    return out


def num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def norm(v):
    v = float(v)
    return int(v) if v.is_integer() else v


ID_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$")
SUFFIXES = ("_cells_s", "_cells", "_s", "_smt", "_n", "_x100", "_x", "_pct", "_pcts", "_bp", "_deg_s", "_deg", "_credits", "_hp", "_crps")
BIBLE_ONLY = {"cost_credits", "tier", "requires_all_structure_ids", "requires_powered_prerequisites", "research_time_seconds", "cooldown_seconds",
              "faction_id", "inherited_by_all_subfactions", "introduced_by_roster_id", "recharge_s", "prerequisites"}
STATS = {"build_time_seconds", "cost_credits", "health", "movement_speed", "power_output", "projectile_flight_speed", "rearm_time_seconds",
         "reload_interval_seconds", "repair_credit_cost_per_health", "repair_progress_rate", "sight_cells", "weapon_damage", "weapon_range_cells",
         "production_rate", "rearm_rate"}
RESIST_GROUPS = {"bullet", "explosive", "beam", "thermal", "rail", "kinetic", "emp"}
FIRE_MODES = {"direct", "indirect", "melee"}
WEAPON_TAGS = {"thermal_beam", "guided_missile", "direct_fire", "indirect_fire", "anti_air", "anti_ground", "anti_sub"}
CLASSES = {"baseline", "unique", "service", "drone"}
SEL_KEYS = {"kinds", "tags_all", "tags_any", "tags_none", "unit_ids", "structure_ids", "classes", "include_replacements", "has_weapon_tags"}
# condition code -> (required keys, optional keys)
CONDS = {
    "on_water": ((), ()), "in_garrison": ((), ()), "deployed": ((), ()), "camouflaged": ((), ()), "structure_powered": ((), ()), "behind_cover": ((), ()),
    "near_friendly_unit": (("radius_cells", "unit_ids"), ("include_replacements",)),
    "near_friendly_structure": (("radius_cells",), ("structure_ids", "selector", "powered")),
    "target_near_friendly_unit": (("radius_cells", "unit_ids"), ("include_replacements",)),
    "in_relay_field": ((), ("powered",)), "stationary": (("for_s",), ()), "out_of_combat": (("for_s",), ()),
    "recently_disembarked": (("within_s",), ()), "in_zone": (("zone_id",), ()),
}
OPS = {  # op -> (required, optional)
    "stat_mod": (("stat", "delta_pct", "selector"), ("cond", "stack_group", "duration_s", "membership")),
    "resist_mod": (("pct", "selector"), ("groups", "fire_modes", "frontal_arc_deg", "cond", "stack_group", "duration_s")),
    "param_mod": (("scope", "key"), ("ability", "set", "add", "mul_pct", "selector", "filter", "stack_group", "cond")),
    "grant_ability": (("ability", "selector"), ("replace", "cond")),
    "set_flag": (("flag", "selector"), ("cond",)),
    "immunity": (("kind", "selector", "duration_s"), ("cond",)),
    "heal": (("rate_pct_per_s", "selector"), ("cost", "cannot_fire", "ends_on_move", "stack_group", "cond")),
    "camouflage": (("max_s", "selector"), ("breaks_on", "cond")),
    "reveal": (("detect",), ()),
    "disable": (("what", "duration_s", "selector"), ("on_expire", "cond")),
    "mark": (("duration_s", "damage_bonus_pct"), ()),
    "spawn_zone": (("zone", "at"), ("duration_s", "cluster_radius_cells")),
}
ZONE_KINDS = {"buff", "smoke", "intercept", "debris", "decoy", "puck", "shelter", "cover", "repair", "reveal"}
ZONE_FIELDS = {"kind", "shape", "radius_cells", "length_cells", "width_cells", "duration_s", "affects", "follow_source", "hp", "targets", "visible_to_enemy",
               "max_per_owner_n", "effects", "params", "pres", "_designer_params"}
ZONE_ACT = {"op", "zone", "inline", "radius_cells", "length_cells", "width_cells", "duration_s", "shape", "count_n", "cluster_radius_cells", "delay_s",
            "fizzle_if_summon_lost"}
TARGET_KEYS = {"mode", "vision", "radius_cells", "length_cells", "width_cells", "structure_ids", "powered_required"}
NEUTRAL_KINDS = {"civilian_garrison", "power_substation", "observation_post", "salvage_depot", "deposit", "field_hospital", "harbor_terminal"}
NEUTRAL_FIELDS = {"kind", "health", "armor_class", "footprint", "sight_cells", "capturable", "capture_s", "garrison_squads_n", "reward", "pres", "ability",
                  "needs_shore", "berth", "forward_queue", "repair_basis_cost_credits", "_note", "_designer_params"}
REWARD_FIELDS = {"credits", "power_n", "reveal_radius_cells", "income_crps", "credits_per_cell", "cells_n"}
TRAIT_ENC = {"grant", "player", "encoded_in", "text_only"}
SUMMON_RE = re.compile(r"^summon\.[a-z0-9_]+\.[a-z0-9_]+$")


class Ctx:
    def __init__(self) -> None:
        self.bible = load(BIBLE)
        self.g = load(BAL / "global.json")
        self.kinds = load(BAL / "ability_kinds.json")
        for n, v in (("bible", self.bible), ("global.json", self.g), ("ability_kinds.json", self.kinds)):
            if isinstance(v, Exception):
                err(n, "-", f"cannot load: {v}")
                raise SystemExit(_finish())
        self.units = set(self.bible["units"])
        self.structs = set(self.bible["structures"])
        self.tags = {t for u in self.bible["units"].values() for t in u.get("tags", [])} | {t for s in self.bible["structures"].values() for t in s.get("tags", [])}
        self.bsel = set(self.bible["selectors"])
        self.mods = set(self.bible["modifiers"])
        self.named: set[str] = set()
        self.zones: set[str] = set()
        self.summons: set[str] = set()
        for p in sorted(BAL.glob("units_*.json")):
            d = load(p)
            if isinstance(d, dict):
                for s in d.get("summons", []) or []:
                    if isinstance(s, dict) and isinstance(s.get("id"), str):
                        self.summons.add(s["id"])
        self.dmg_keys = set(self.g.get("support_power_damage", {}))


# ---------------------------------------------------------------- generic walkers
def walk_numbers(f: str, v, path: str, key: str = "", in_params: bool = False) -> None:
    """V-SCH-04 / 06 / 07 over every numeric literal."""
    if isinstance(v, dict):
        for k, x in v.items():
            if k.startswith("_"):
                continue
            p = f"{path}.{k}"
            if num(x):
                number(f, p, k, x, in_params)
            else:
                walk_numbers(f, x, p, k, in_params or k == "params")
    elif isinstance(v, list):
        for i, x in enumerate(v):
            if num(x):
                number(f, f"{path}[{i}]", key, x, False)
            else:
                walk_numbers(f, x, f"{path}[{i}]", key, in_params)


def number(f: str, path: str, key: str, x, in_params: bool) -> None:
    lit = getattr(x, "lit", "")
    decs = len(lit.split(".")[1].split("e")[0]) if "." in lit else 0
    if "e" in lit.lower():
        err(f, path, f"exponent literal {lit!r}")
    if decs > 3:
        err(f, path, f"V-SCH-04: {decs} decimals (max 3): {lit}")
    if key.endswith(("_pct", "_pcts")) and decs > 2:
        err(f, path, f"V-SCH-06: percent has {decs} decimals (max 2): {lit}")
    if abs(float(x)) >= 2 ** 40:
        err(f, path, "V-SCH-04: magnitude >= 2^40")
    if in_params and not key.endswith(SUFFIXES):
        err(f, path, f"V-SCH-07: numeric key {key!r} in a params object has no unit suffix")


def leaf_values(v, out: set) -> None:
    if isinstance(v, dict):
        for k, x in v.items():
            if k != "bible_numbers" and not k.startswith("_"):
                leaf_values(x, out)
    elif isinstance(v, list):
        for x in v:
            leaf_values(x, out)
    elif num(v):
        out.add(abs(norm(v)))


def bible_only(f: str, path: str, d: dict) -> None:
    for k in d:
        if k in BIBLE_ONLY or k in ("cooldown_s", "cooldown_seconds"):
            err(f, f"{path}.{k}", "V-CNF-04: bible-only field (cost/cooldown/tier/prerequisites) must not appear here")


def sorted_keys(f: str, path: str, d: dict) -> None:
    ks = [k for k in d if not k.startswith("_")]
    if ks != sorted(ks):
        err(f, path, "V-SCH-09: ids are not sorted ascending")
    for k in ks:
        if not ID_RE.match(k):
            err(f, f"{path}.{k}", "V-SCH-03: id shape")


def prose_check(f: str, path: str, entry: dict, text: str) -> None:
    bn = entry.get("bible_numbers")
    if not isinstance(bn, list) or not all(num(x) for x in bn):
        err(f, f"{path}.bible_numbers", "must be an array of numbers")
        return
    prose = [norm(x) for x in prose_numbers(text)]
    bnn = [norm(x) for x in bn]
    for x in bnn:
        if x not in prose:
            err(f, f"{path}.bible_numbers", f"V-CNF-06: {x} is not a number of the bible prose {prose}")
    leaf: set = set()
    leaf_values(entry, leaf)
    for x in prose:
        if abs(x) not in leaf and x not in bnn:
            err(f, path, f"V-CNF-06: prose number {x} is neither a leaf value nor listed in bible_numbers")
    for x in prose:
        if abs(x) not in leaf:
            INFO.append(f"{f}: {path}: prose number {x} acknowledged only via bible_numbers")


# ---------------------------------------------------------------- vocabulary checks
def check_selector(c: Ctx, f: str, path: str, s, allow_named: bool = True) -> None:
    if isinstance(s, str):
        if s not in c.bsel and s not in c.named:
            err(f, path, f"selector id {s!r} is neither a bible selector nor a selector.balance.* in research_effects.json")
    elif isinstance(s, list):
        if not s:
            err(f, path, "empty selector union")
        for i, x in enumerate(s):
            if not isinstance(x, str):
                err(f, f"{path}[{i}]", "selector union entries must be id strings")
            else:
                check_selector(c, f, f"{path}[{i}]", x)
    elif isinstance(s, dict):
        for k, v in s.items():
            if k not in SEL_KEYS:
                err(f, f"{path}.{k}", "unknown inline-selector key")
        for k in ("kinds",):
            for x in s.get(k, []):
                if x not in ("unit", "structure"):
                    err(f, f"{path}.kinds", f"bad kind {x!r}")
        for k in ("tags_all", "tags_any", "tags_none"):
            for x in s.get(k, []):
                if x not in c.tags:
                    err(f, f"{path}.{k}", f"tag {x!r} exists on no bible unit/structure")
        for x in s.get("unit_ids", []):
            if x not in c.units:
                err(f, f"{path}.unit_ids", f"unknown unit id {x}")
        for x in s.get("structure_ids", []):
            if x not in c.structs:
                err(f, f"{path}.structure_ids", f"unknown structure id {x}")
        for x in s.get("classes", []):
            if x not in CLASSES:
                err(f, f"{path}.classes", f"bad class {x!r}")
        for x in s.get("has_weapon_tags", []):
            if x not in WEAPON_TAGS:
                err(f, f"{path}.has_weapon_tags", f"bad weapon tag {x!r}")
        for k in ("unit_ids", "structure_ids"):
            if k in s and s[k] != sorted(s[k]):
                err(f, f"{path}.{k}", "ids not sorted")
        if not any(k in s for k in ("kinds", "tags_all", "tags_any", "unit_ids", "structure_ids", "has_weapon_tags")):
            err(f, path, "inline selector selects nothing (needs kinds/tags/ids/has_weapon_tags)")
    else:
        err(f, path, "selector must be a string, an array of strings or an object")


def check_cond(c: Ctx, f: str, path: str, conds) -> None:
    if not isinstance(conds, list):
        err(f, path, "cond must be an array")
        return
    for i, cd in enumerate(conds):
        p = f"{path}[{i}]"
        code = cd.get("code") if isinstance(cd, dict) else None
        if code not in CONDS:
            err(f, p, f"unknown condition code {code!r}")
            continue
        if code == "paid_repair":
            err(f, p, "V-EFF-01: paid_repair not allowed in an effect")
        req, opt = CONDS[code]
        for k in req:
            if k not in cd:
                err(f, p, f"condition {code} needs {k}")
        for k in cd:
            if k != "code" and k not in req and k not in opt:
                err(f, p, f"condition {code}: unknown key {k}")
        if code == "near_friendly_structure" and not ("structure_ids" in cd or "selector" in cd):
            err(f, p, "near_friendly_structure needs structure_ids or selector")
        for x in cd.get("unit_ids", []):
            if x not in c.units:
                err(f, p, f"unknown unit id {x}")
        for x in cd.get("structure_ids", []):
            if x not in c.structs:
                err(f, p, f"unknown structure id {x}")
        if "selector" in cd:
            check_selector(c, f, p + ".selector", cd["selector"])


def kind_of_ability_ref(c: Ctx, f: str, path: str, a) -> tuple[str | None, dict]:
    """Validate a grant/trait ability value ({ref,params} | {kind,params} | template id | bare kind); return (kind, params)."""
    tpl = c.kinds["templates"]
    if isinstance(a, str):
        if a in tpl:
            return tpl[a]["kind"], {}
        if a in c.kinds["kinds"]:
            return a, {}
        err(f, path, f"unknown ability {a!r}")
        return None, {}
    if not isinstance(a, dict):
        err(f, path, "ability must be a string or object")
        return None, {}
    params = a.get("params", {})
    if "ref" in a:
        kind = tpl.get(a["ref"], {}).get("kind")
        if kind is None:
            err(f, path + ".ref", f"unknown ability template {a['ref']!r}")
    elif "kind" in a:
        kind = a["kind"]
    else:
        err(f, path, "ability object needs ref or kind")
        return None, {}
    if kind not in c.kinds["kinds"]:
        err(f, path, f"unknown ability kind {kind!r}")
        return None, {}
    spec = c.kinds["kinds"][kind]["params"]
    for k, v in params.items():
        if k not in spec:
            err(f, f"{path}.params.{k}", f"not a parameter of ability kind {kind}")
        else:
            check_ptype(c, f, f"{path}.params.{k}", spec[k], v)
    return kind, params


def check_ptype(c: Ctx, f: str, path: str, ps: dict, v) -> None:
    t = ps.get("type", "")
    if t == "bool":
        ok = isinstance(v, bool)
    elif t.startswith("enum:"):
        ok = v in t[5:].split("|")
    elif t in ("str", "zone_id", "unit_id", "structure_id", "summon_id"):
        ok = isinstance(v, str)
    elif t.startswith("["):
        ok = isinstance(v, list)
        if ok and t == "[str]":
            ok = all(isinstance(x, str) for x in v)
        if ok and t in ("[structure]",):
            ok = all(x in c.structs for x in v)
    elif t in ("unit_ids", "structure_ids"):
        ok = isinstance(v, list) and all(x in (c.units if t == "unit_ids" else c.structs) for x in v)
    else:
        ok = num(v)
        if ok:
            lo, hi = ps.get("min"), ps.get("max")
            if lo is not None and float(v) < lo or hi is not None and float(v) > hi:
                err(f, path, f"value {v} outside the registry range [{lo}, {hi}]")
    if not ok:
        err(f, path, f"value {v!r} does not fit registry type {t}")


def check_effect(c: Ctx, f: str, path: str, e, nested_ok: bool = True) -> None:
    if not isinstance(e, dict) or e.get("op") not in OPS:
        err(f, path, f"unknown effect op {e.get('op') if isinstance(e, dict) else e!r}")
        return
    op = e["op"]
    req, opt = OPS[op]
    for k in req:
        if k not in e:
            err(f, path, f"{op}: required field {k!r} missing")
    for k in e:
        if k != "op" and k not in req and k not in opt:
            err(f, f"{path}.{k}", f"{op}: unknown field")
    if "selector" in e:
        check_selector(c, f, path + ".selector", e["selector"])
    if "cond" in e:
        check_cond(c, f, path + ".cond", e["cond"])
    if op == "stat_mod":
        if e.get("stat") not in STATS:
            err(f, path + ".stat", f"unknown stat {e.get('stat')!r}")
        if not isinstance(e.get("delta_pct"), int):
            err(f, path + ".delta_pct", "delta_pct must be an integer")
        if e.get("membership", "continuous") not in ("continuous", "latched"):
            err(f, path + ".membership", "continuous|latched")
    elif op == "resist_mod":
        for g in e.get("groups", []):
            if g not in RESIST_GROUPS:
                err(f, path + ".groups", f"bad group {g!r}")
        for m in e.get("fire_modes", []):
            if m not in FIRE_MODES:
                err(f, path + ".fire_modes", f"bad fire mode {m!r}")
        if not (0 < e.get("pct", 0) <= 50):
            err(f, path + ".pct", "resist pct must be in (0, 50]")
    elif op == "param_mod":
        how = [k for k in ("set", "add", "mul_pct") if k in e]
        if len(how) != 1:
            err(f, path, "param_mod needs exactly one of set/add/mul_pct")
        scope = e.get("scope")
        if scope not in ("ability", "def", "player"):
            err(f, path + ".scope", "ability|def|player")
        if scope == "player" and "selector" in e:
            err(f, path, "player-scope param_mod takes no selector")
        if scope in ("ability", "def") and "selector" not in e:
            err(f, path, "param_mod needs a selector outside player scope")
        key = e.get("key")
        if scope in ("ability", "player"):
            ab = e.get("ability")
            spec = c.kinds["kinds"].get(ab, {}).get("params") if ab else None
            if spec is None:
                err(f, path + ".ability", f"unknown ability kind {ab!r}")
            elif key not in spec:
                err(f, path + ".key", f"{key!r} is not a parameter of ability kind {ab}")
            else:
                if scope == "player" and "player" not in c.kinds["kinds"][ab]["scopes"]:
                    err(f, path + ".scope", f"ability kind {ab} is not player scope")
                if scope == "ability" and c.kinds["kinds"][ab]["scopes"] == ["player"]:
                    err(f, path + ".scope", f"ability kind {ab} is player-only; use scope player")
                if how:
                    v = e[how[0]]
                    if how[0] == "set":
                        check_ptype(c, f, f"{path}.set", spec[key], v)
                    elif not num(v) or spec[key].get("type") == "bool":
                        err(f, path, f"{how[0]} needs a numeric parameter")
        elif scope == "def":
            dp = c.kinds.get("def_params", {})
            if key not in dp:
                err(f, path + ".key", f"{key!r} is not a def param (def_params: {sorted(dp)})")
        if "mul_pct" in e and not (num(e["mul_pct"]) and e["mul_pct"] > 0):
            err(f, path + ".mul_pct", "must be > 0")
    elif op == "grant_ability":
        kind_of_ability_ref(c, f, path + ".ability", e.get("ability"))
    elif op == "set_flag":
        dp = c.kinds.get("def_params", {})
        if dp.get(e.get("flag"), {}).get("type") != "bool":
            err(f, path + ".flag", f"{e.get('flag')!r} is not a boolean def param")
    elif op == "immunity":
        if e.get("kind") not in ("suppression", "emp"):
            err(f, path + ".kind", "suppression|emp")
    elif op == "heal":
        if e.get("cost", "free") not in ("free", "paid"):
            err(f, path + ".cost", "free|paid")
    elif op == "camouflage":
        for b in e.get("breaks_on", []):
            if b not in ("move", "fire", "detect"):
                err(f, path + ".breaks_on", f"bad value {b!r}")
    elif op == "disable":
        if e.get("what") not in ("weapons", "structure"):
            err(f, path + ".what", "weapons|structure")
    elif op == "spawn_zone":
        chk_zone_ref(c, f, path + ".zone", e.get("zone"))
        if e.get("at") not in ("initial_positions", "target"):
            err(f, path + ".at", "initial_positions|target")


def chk_zone_ref(c: Ctx, f: str, path: str, z) -> None:
    if not isinstance(z, str) or not re.match(r"^zone\.[a-z0-9_.]+$", z):
        err(f, path, f"bad zone id {z!r}")
    elif z not in c.zones:
        err(f, path, f"zone {z!r} does not exist in zone_templates.json")


def check_zone_body(c: Ctx, f: str, path: str, z: dict) -> None:
    for k in z:
        if k not in ZONE_FIELDS:
            err(f, f"{path}.{k}", "unknown zone field")
    if z.get("kind") not in ZONE_KINDS:
        err(f, path + ".kind", f"kind must be one of {sorted(ZONE_KINDS)}")
    shape = z.get("shape", "circle")
    if shape not in ("circle", "line"):
        err(f, path + ".shape", "circle|line")
    if shape == "circle" and "radius_cells" not in z:
        err(f, path, "circle zone needs radius_cells")
    if shape == "line" and not ("length_cells" in z and "width_cells" in z):
        err(f, path, "line zone needs length_cells and width_cells")
    if "duration_s" not in z:
        err(f, path, "duration_s is required")
    if z.get("affects", "friendly") not in ("friendly", "enemy", "all"):
        err(f, path + ".affects", "friendly|enemy|all")
    if z["kind"] in ("decoy", "puck", "cover", "shelter") and z.get("hp", 0) <= 0 and z["kind"] in ("decoy", "puck"):
        err(f, path + ".hp", "decoy/puck zones are destructible: hp > 0")
    for i, e in enumerate(z.get("effects", [])):
        check_effect(c, f, f"{path}.effects[{i}]", e)
    for k, v in z.get("params", {}).items():
        if not isinstance(v, (bool, str, list)) and not num(v):
            err(f, f"{path}.params.{k}", "params values must be bool/number/string/array")
        if k.endswith("_id") and isinstance(v, str) and v not in c.structs and v not in c.units:
            err(f, f"{path}.params.{k}", f"unknown id {v}")


# ---------------------------------------------------------------- file checks
def envelope(f: str, d, name: str, extra_keys: set):
    if isinstance(d, Exception):
        err(f, "-", f"cannot load: {d}")
        return False
    if d.get("schema") != f"meridian.balance.{name}/1":
        err(f, "schema", f"must be 'meridian.balance.{name}/1', got {d.get('schema')!r}")
    for k in d:
        if k not in ("schema",) and k not in extra_keys and not k.startswith("_"):
            err(f, k, "unknown top-level key")
    return True


def check_research(c: Ctx) -> None:
    f = "research_effects.json"
    d = load(BAL / f)
    if not envelope(f, d, "research_effects", {"selectors", "research"}):
        return
    sel = d.get("selectors", {})
    sorted_keys(f, "selectors", sel)
    for k in sel:
        if not k.startswith("selector.balance."):
            err(f, f"selectors.{k}", "named selectors must be selector.balance.<name>")
        if k in c.bsel:
            err(f, f"selectors.{k}", "collides with a bible selector id")
    c.named = set(sel)
    for k, s in sel.items():
        check_selector(c, f, f"selectors.{k}", s)
    walk_numbers(f, d, "$")
    r = d.get("research", {})
    sorted_keys(f, "research", r)
    if len(r) != 40:
        err(f, "research", f"expected 40 research entries, found {len(r)}")
    if set(r) != set(c.bible["research"]):
        err(f, "research", f"ids differ from the bible: missing {sorted(set(c.bible['research']) - set(r))}, extra {sorted(set(r) - set(c.bible['research']))}")
    for rid, e in r.items():
        p = rid
        bible_only(f, p, e)
        for k in e:
            if k not in ("bible_numbers", "effects", "designer_params", "may_be_empty_in"):
                err(f, f"{p}.{k}", "unknown entry key")
        if not e.get("effects"):
            err(f, p, "V-CMP-03: at least one effect required")
        for i, ef in enumerate(e.get("effects", [])):
            check_effect(c, f, f"{p}.effects[{i}]", ef)
        if rid in c.bible["research"]:
            prose_check(f, p, e, c.bible["research"][rid]["effect_text"])
        for dp in e.get("designer_params", []):
            if not isinstance(dp, str):
                err(f, p + ".designer_params", "strings only")


def check_zones(c: Ctx) -> None:
    f = "zone_templates.json"
    d = load(BAL / f)
    if not envelope(f, d, "zone_templates", {"zones"}):
        return
    z = d.get("zones", {})
    sorted_keys(f, "zones", z)
    c.zones = set(z)
    walk_numbers(f, d, "$")
    need = {"zone.smoke_dust_screen", "zone.repair_station", "zone.portable_cover", "zone.infantry_shelter", "zone.sensor_puck", "zone.decoy_light_vehicle",
            "zone.decoy_tank", "zone.decoy_radar", "zone.decoy_transport", "zone.trident_interception", "zone.horizon_debris"}
    for m in sorted(need - set(z)):
        err(f, "zones", f"shared template {m} missing")
    for k, v in z.items():
        check_zone_body(c, f, f"zones.{k}", v)
    # global.json cross checks (V-CNF-09: one number, one home)
    tri = c.g["superweapons"]["trident"]
    tp = z.get("zone.trident_interception", {}).get("params", {})
    for a, b in (("charges_n", "charges"), ("charges_per_ordinary_projectile_n", "charges_per_ordinary_projectile"),
                 ("charges_per_strategic_packet_n", "charges_per_strategic_packet"), ("strategic_reduction_pct", "strategic_reduction_pct")):
        if tp.get(a) != tri[b]:
            err(f, f"zones.zone.trident_interception.params.{a}", f"must equal global.json superweapons.trident.{b} = {tri[b]}")
    zt = z.get("zone.trident_interception", {})
    if zt.get("radius_cells") != tri["zone_radius_cells"] or zt.get("duration_s") != tri["duration_s"]:
        err(f, "zones.zone.trident_interception", "radius/duration must equal global.json superweapons.trident")
    hor = c.g["superweapons"]["horizon"]["debris"]
    zh = z.get("zone.horizon_debris", {})
    eff = zh.get("effects", [{}])[0]
    if zh.get("duration_s") != hor["duration_s"] or eff.get("delta_pct") != -(100 - hor["land_vehicle_speed_pct"]):
        err(f, "zones.zone.horizon_debris", "duration / speed delta must equal global.json superweapons.horizon.debris")
    sm = z.get("zone.smoke_dust_screen", {}).get("effects", [{}])[0]
    if sm.get("pct") != 30 or sm.get("fire_modes") != ["direct"]:
        err(f, "zones.zone.smoke_dust_screen", "shared Dust Screen rule: resist 30 %, fire_modes [direct]")


def check_powers(c: Ctx) -> None:
    f = "power_actions.json"
    d = load(BAL / f)
    if not envelope(f, d, "power_actions", {"powers"}):
        return
    walk_numbers(f, d, "$")
    pw = d.get("powers", {})
    sorted_keys(f, "powers", pw)
    if len(pw) != 48:
        err(f, "powers", f"expected 48 powers, found {len(pw)}")
    if set(pw) != set(c.bible["support_powers"]):
        err(f, "powers", f"ids differ from the bible: missing {sorted(set(c.bible['support_powers']) - set(pw))}, extra {sorted(set(pw) - set(c.bible['support_powers']))}")
    unresolved: set = set()
    for pid, e in pw.items():
        p = pid
        bible_only(f, p, e)
        for k in e:
            if k not in ("bible_numbers", "target", "warning_s", "actions", "designer_params"):
                err(f, f"{p}.{k}", "unknown entry key")
        t = e.get("target", {})
        for k in t:
            if k not in TARGET_KEYS:
                err(f, f"{p}.target.{k}", "unknown target key")
        if t.get("mode") not in ("none", "point", "line", "own_structure"):
            err(f, p + ".target.mode", "none|point|line|own_structure")
        if t.get("vision") not in ("any", "explored", "current"):
            err(f, p + ".target.vision", "any|explored|current")
        if t.get("mode") == "line" and not ("length_cells" in t and "width_cells" in t):
            err(f, p + ".target", "line target needs length_cells and width_cells")
        for x in t.get("structure_ids", []):
            if x not in c.structs:
                err(f, p + ".target.structure_ids", f"unknown structure {x}")
        acts = e.get("actions", [])
        if not acts:
            err(f, p, "at least one action required")
        for i, a in enumerate(acts):
            ap = f"{p}.actions[{i}]"
            op = a.get("op")
            if op == "zone":
                for k in a:
                    if k not in ZONE_ACT:
                        err(f, f"{ap}.{k}", "unknown zone-action field")
                if ("zone" in a) == ("inline" in a):
                    err(f, ap, "zone action needs exactly one of zone / inline")
                if "zone" in a:
                    chk_zone_ref(c, f, ap + ".zone", a["zone"])
                else:
                    check_zone_body(c, f, ap + ".inline", a["inline"])
            elif op == "summon":
                sm = a.get("summon_id", "")
                if not SUMMON_RE.match(sm):
                    err(f, ap + ".summon_id", f"bad summon id shape {sm!r}")
                elif sm not in c.summons:
                    unresolved.add(sm)
                if a.get("at", "target") != "target":
                    err(f, ap + ".at", "target")
            elif op == "strike":
                if "damage_ref" in a:
                    if a["damage_ref"] not in c.dmg_keys:
                        err(f, ap + ".damage_ref", f"not a key of global.json support_power_damage {sorted(c.dmg_keys)}")
                elif not a.get("impacts"):
                    err(f, ap, "strike needs damage_ref or impacts")
                if a.get("pattern", "random_in_radius") not in ("random_in_radius", "fixed"):
                    err(f, ap + ".pattern", "random_in_radius|fixed")
            elif op == "mark":
                for k in ("find_radius_cells", "lookback_s"):
                    if k not in a:
                        err(f, ap, f"mark needs {k}")
                if "then_strike" in a:
                    if a["then_strike"].get("damage_ref") not in c.dmg_keys:
                        err(f, ap + ".then_strike.damage_ref", "not a key of global.json support_power_damage")
                elif "mark_s" not in a:
                    err(f, ap, "mark needs mark_s or then_strike")
                for k in ("find_selector", "bonus_from_selector"):
                    if k in a:
                        check_selector(c, f, f"{ap}.{k}", a[k])
            elif op == "global_effect":
                if "duration_s" not in a or not a.get("effects"):
                    err(f, ap, "global_effect needs duration_s and effects")
                for j, ef in enumerate(a.get("effects", [])):
                    check_effect(c, f, f"{ap}.effects[{j}]", ef)
            else:
                err(f, ap + ".op", f"unknown action op {op!r}")
        if pid in c.bible["support_powers"]:
            prose_check(f, p, e, c.bible["support_powers"][pid]["effect_text"])
            # strike warnings equal the prose warning (bible-fixed number)
            if any(a.get("op") == "strike" or "then_strike" in a for a in acts) and "warning_s" not in e:
                err(f, p, "strike powers carry warning_s")
    # zone template reference sanity: counterbattery-style strikes must agree with global.json warning
    for pid, key in (("power.nec.counterbattery_mission", "counterbattery_mission"), ("power.def.tremor_barrage", "tremor_barrage"),
                     ("power.sap.counterlaunch_plot", "counterlaunch_plot")):
        if pid in pw and pw[pid].get("warning_s") != c.g["support_power_damage"][key]["warning_s"]:
            err(f, pid, f"warning_s must equal global.json support_power_damage.{key}.warning_s")
    for sm in sorted(unresolved):
        warn(f, "summons", f"summon id {sm} is not (yet) defined in any units_<code>.json summons list")


def check_traits(c: Ctx) -> None:
    f = "faction_traits.json"
    d = load(BAL / f)
    if not envelope(f, d, "faction_traits", {"factions"}):
        return
    walk_numbers(f, d, "$")
    fs = d.get("factions", {})
    sorted_keys(f, "factions", fs)
    if len(fs) != 8:
        err(f, "factions", f"expected 8 faction trait sets, found {len(fs)}")
    if set(fs) != set(c.bible["factions"]):
        err(f, "factions", "ids differ from the bible factions")
    for fid, fe in fs.items():
        p = f"factions.{fid}"
        bf = c.bible["factions"].get(fid)
        code = fid.split(".")[1]
        if fe.get("pres", {}).get("palette") != f"palette.{code}":
            err(f, p + ".pres.palette", f"expected palette.{code}")
        for k in fe:
            if k not in ("pres", "traits", "player_params"):
                err(f, f"{p}.{k}", "unknown key")
        tr = fe.get("traits", {})
        sorted_keys(f, p + ".traits", tr)
        covered: list[int] = []
        for tid, t in tr.items():
            tp = f"{p}.traits.{tid}"
            if not tid.startswith(f"trait.{code}."):
                err(f, tp, f"trait id must start with trait.{code}.")
            enc = t.get("encoding")
            if enc not in TRAIT_ENC:
                err(f, tp + ".encoding", f"one of {sorted(TRAIT_ENC)}")
            cov = t.get("covers", [])
            if not isinstance(cov, list) or len(cov) != 1 or not all(isinstance(x, int) for x in cov):
                err(f, tp + ".covers", "exactly one traits_text index expected")
                continue
            covered += cov
            if bf and not 0 <= cov[0] < len(bf["traits_text"]):
                err(f, tp + ".covers", "index outside traits_text")
                continue
            if bf:
                prose_check(f, tp, t, bf["traits_text"][cov[0]])
            if enc == "grant":
                check_selector(c, f, tp + ".selector", t.get("selector"))
                kind, _ = kind_of_ability_ref(c, f, tp + ".ability", t.get("ability"))
                if kind and c.kinds["kinds"][kind]["scopes"] and "unit" not in c.kinds["kinds"][kind]["scopes"] and "structure" not in c.kinds["kinds"][kind]["scopes"]:
                    err(f, tp, "grant of a non-def-scope ability")
            elif enc == "player":
                kind, _ = kind_of_ability_ref(c, f, tp + ".ability", t.get("ability"))
                if kind and "player" not in c.kinds["kinds"][kind]["scopes"]:
                    err(f, tp, f"ability kind {kind} is not player scope")
            elif enc == "encoded_in":
                b = t.get("encoded_in")
                if not isinstance(b, dict) or not b:
                    err(f, tp + ".encoded_in", "required object")
                    continue
                for m in b.get("modifier_ids", []):
                    if m not in c.mods:
                        err(f, tp, f"unknown modifier {m}")
                    elif bf and m not in bf.get("passive_modifier_ids", []):
                        err(f, tp, f"modifier {m} is not a passive modifier of {fid}")
                if bf and "modifier_ids" in b and sorted(b["modifier_ids"]) != b["modifier_ids"]:
                    err(f, tp, "modifier_ids not sorted")
                for x in b.get("unit_ids", []):
                    if x not in c.units:
                        err(f, tp, f"unknown unit {x}")
                if "structure_id" in b and b["structure_id"] not in c.structs:
                    err(f, tp, f"unknown structure {b['structure_id']}")
                if "ability" in b and b["ability"] not in c.kinds["kinds"]:
                    err(f, tp, f"unknown ability kind {b['ability']}")
                if "ability_ref" in b and b["ability_ref"] not in c.kinds["templates"]:
                    err(f, tp, f"unknown template {b['ability_ref']}")
        if bf:
            if sorted(covered) != list(range(len(bf["traits_text"]))):
                err(f, p, f"traits_text indices covered {sorted(covered)}; each of 0..{len(bf['traits_text']) - 1} must be covered exactly once")
            used = {m for t in tr.values() for m in t.get("encoded_in", {}).get("modifier_ids", [])}
            for m in bf.get("passive_modifier_ids", []):
                if m not in used:
                    err(f, p, f"passive modifier {m} is not referenced by any trait")
        if not isinstance(fe.get("player_params", {}), dict):
            err(f, p + ".player_params", "object")
    # PD / SAP / AE / NAPC / HAN / NEC spec-fixed numbers (traits text numbers already covered by prose_check)
    n = fs.get("faction.napc", {}).get("traits", {}).get("trait.napc.factory_apron", {}).get("ability", {}).get("params", {})
    if [n.get("radius_cells"), n.get("rate_pct_per_s"), n.get("cap_pct"), n.get("idle_s")] != [5, 1, 75, 6]:
        err(f, "factions.faction.napc", "factory_apron must be radius 5, 1 %/s, cap 75 %, idle 6 s")


def check_neutrals(c: Ctx) -> None:
    f = "neutral_structures.json"
    d = load(BAL / f)
    if not envelope(f, d, "neutral_structures", {"neutrals"}):
        return
    walk_numbers(f, d, "$")
    ns = d.get("neutrals", {})
    sorted_keys(f, "neutrals", ns)
    kinds = [v.get("kind") for v in ns.values()]
    tech = [k for k in kinds if k != "deposit"]
    if len(tech) != 6 or set(tech) != {"civilian_garrison", "power_substation", "observation_post", "salvage_depot", "field_hospital", "harbor_terminal"}:
        err(f, "neutrals", f"expected the six neutral tech kinds (garrison, substation, observation, salvage depot, field hospital, harbor terminal), found {sorted(tech)}")
    if kinds.count("deposit") != 2:
        err(f, "neutrals", "expected two deposit kinds (standard, rich)")
    armor = {a["id"] for a in c.g["armor_classes"]}
    for k, v in ns.items():
        p = f"neutrals.{k}"
        for fld in v:
            if fld not in NEUTRAL_FIELDS:
                err(f, f"{p}.{fld}", "unknown neutral field")
        if v.get("kind") not in NEUTRAL_KINDS:
            err(f, p + ".kind", f"one of {sorted(NEUTRAL_KINDS)}")
        if v.get("armor_class") not in armor:
            err(f, p + ".armor_class", "not a global.json armor class")
        fp = v.get("footprint", {})
        if not (isinstance(fp.get("w"), int) and isinstance(fp.get("h"), int) and fp["w"] > 0 and fp["h"] > 0):
            err(f, p + ".footprint", "{w,h} positive integers")
        if not isinstance(v.get("health"), int) or v["health"] < 1:
            err(f, p + ".health", "positive integer")
        if v.get("capturable", False) and "capture_s" not in v:
            err(f, p, "capturable neutral needs capture_s")
        if not v.get("capturable", False) and "capture_s" in v:
            err(f, p, "capture_s on a non-capturable neutral")
        for rk in v.get("reward", {}):
            if rk not in REWARD_FIELDS:
                err(f, f"{p}.reward.{rk}", "unknown reward field")
        if v.get("kind") == "civilian_garrison" and v.get("garrison_squads_n") != 4:
            err(f, p + ".garrison_squads_n", "bible: the civilian garrison holds 4 squads")
        if "ability" in v:
            kind_of_ability_ref(c, f, p + ".ability", v["ability"])
        if "forward_queue" in v and v["forward_queue"].get("counts_as_structure_id") not in c.structs:
            err(f, p + ".forward_queue", "counts_as_structure_id must be a bible structure")
    dep = c.g["economy"]["deposit"]
    std, rich = ns.get("neutral.salvage_field", {}).get("reward", {}), ns.get("neutral.salvage_field_rich", {}).get("reward", {})
    if (std.get("credits_per_cell"), std.get("cells_n")) != (dep["credits_per_cell"], dep["standard_field_cells"]):
        err(f, "neutrals.neutral.salvage_field", "V-CNF-09: must mirror global.json economy.deposit (standard)")
    if (rich.get("credits_per_cell"), rich.get("cells_n")) != (dep["rich_credits_per_cell"], dep["rich_field_cells"]):
        err(f, "neutrals.neutral.salvage_field_rich", "V-CNF-09: must mirror global.json economy.deposit (rich)")
    for kid in ("field_hospital",):
        h = next((v for v in ns.values() if v.get("kind") == kid), {})
        if h.get("ability", {}).get("params", {}).get("radius_cells") != 5 or h.get("ability", {}).get("params", {}).get("rate_pct_per_s") != 2:
            err(f, "neutrals", "Field Hospital heal aura must be 5 cells, 2 %/s (economy 5.13)")


def check_manifest() -> None:
    m = load(BAL / "manifest.json")
    if isinstance(m, Exception):
        err("manifest.json", "-", str(m))
        return
    for n in ("research_effects.json", "power_actions.json", "zone_templates.json", "faction_traits.json", "neutral_structures.json"):
        if n not in m.get("files", []):
            err("manifest.json", "files", f"{n} not listed")
    if "superweapons.json" in m.get("files", []) or (BAL / "superweapons.json").exists():
        err("manifest.json", "files", "superweapons are compiled from global.json; there must be no superweapons.json")


def _finish() -> int:
    for line in ERR + WRN:
        print(line)
    print(f"check_rules_data: {len(ERR)} error(s), {len(WRN)} warning(s), {len(INFO)} info (prose numbers acknowledged only via bible_numbers)")
    return 1 if ERR else 0


def main() -> int:
    c = Ctx()
    check_manifest()
    check_research(c)  # first: defines the named selectors used everywhere
    check_zones(c)  # second: defines the zone ids used by powers
    check_powers(c)
    check_traits(c)
    check_neutrals(c)
    return _finish()


if __name__ == "__main__":
    sys.exit(main())
