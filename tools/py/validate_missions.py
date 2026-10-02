#!/usr/bin/env python3
"""Validate scripted missions: game/data/missions/<id>.json (schema meridian.mission/1) against the manifest, the bible and the
balance sheets. Stdlib only, never writes. The GDScript compiler (DefMissionParser, rules V-MIS-*) is the authority at load time;
this tool finds the same problems earlier, without starting Godot, and checks references the engine cannot (announcer lines).

  python3 tools/py/validate_missions.py                 # every mission the manifest lists (+ unlisted files as a warning)
  python3 tools/py/validate_missions.py FILE...         # only these mission files
  python3 tools/py/validate_missions.py --schema        # print the exact JSON schema (field by field)
  python3 tools/py/validate_missions.py --strict        # warnings also fail

Exit: 0 clean, 1 errors, 2 warnings (only with --strict), 3 usage. Output: `file: where: RULE message`.
Rules: V-MIS-01 file / schema / id, V-MIS-02 field type or range, V-MIS-03 unknown reference, V-MIS-04 duplicate id,
V-MIS-05 structure of a condition / action, V-MIS-06 players / map / layout, V-MIS-07 warning (unlisted file, unknown announcer line).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "game" / "data"
BALANCE = DATA / "balance"
MISSIONS = DATA / "missions"
BIBLE = DATA / "bible" / "meridian_factions.json"
ANNOUNCER = DATA / "audio" / "announcer.json"
PARSER_GD = ROOT / "game" / "src" / "data" / "def_mission_parser.gd"

TPS = 20
SCHEMA_ID = "meridian.mission/1"
ID_RE = re.compile(r"^[a-z][a-z0-9_]{0,39}$")

SCHEMA_TEXT = r"""
MERIDIAN MISSION FILE  meridian.mission/1   (game/data/missions/<id>.json; listed in game/data/balance/manifest.json "missions")

Conventions: every number is an integer (JSON ints). Unknown keys are errors (typos). Ids are lowercase [a-z][a-z0-9_]*
(max 40 chars; the file name is <id>.json). Lists marked "sorted" are stored sorted by id at load; the manifest "missions"
list must be sorted ascending and unique. Seconds -> ticks at 20 TPS. Cells are map cells (1 cell = 1024 sub-cell units).
Texts (title, briefing, message text, objective text) never enter the data hash; everything else does.

TOP LEVEL
  schema      "meridian.mission/1"                                  required
  id          mission id; must equal the file name without .json    required
  title       string 1..60                                          required
  group       lowercase word, e.g. "tutorial" | "operation" | "demo" (default "custom")
  order       int 0..9999, menu order inside the group (default 0)
  briefing    [ {heading?: string, text: string, lore?: bible id} ]  lore = a bible id (faction.x, unit.x, structure.x,
              roster.x, research.x, power.x, superweapon.x) shown as a Field Manual link
  map         {family, size, seed, params?}                         required
                family  "open"|"urban"|"coast" (or 0|1|2)
                size    96..256, multiple of 8, >= the minimum of the start layout (2 players 96, 3-4 128, 5-6 160, 7-8 192)
                seed    0..4294967295 (the generator is deterministic per seed)
                params  {water_pct 0..40, density 0..100, resources 0..100, neutrals 0..100, biome 0..2, start_near_water bool}
  sim_seed    0..4294967295 simulation RNG seed (default = map.seed)
  rules       overrides of the match rules: start_credits 0..100000, unit_cap 20..500, superweapons, fog, shared_vision,
              veterancy, neutral_structures, end_when_no_humans (bool or 0/1), vision_stride 1..4, vision_budget 16..512,
              victory 0|1 (default 0 in missions: nobody is eliminated for lacking assets; the script decides),
              allow_debug 0|1. start_mode cannot be set (the mission places the starts itself).
  players     [ player ]  1..8, exactly one with kind "human"         required
  areas       [ area ]    0..64
  messages    [ message ] 0..128
  objectives  [ objective ] 0..64 (declaration order = index shown in the UI)
  timers      [ timer ]   0..16
  triggers    [ trigger ] 0..128 (evaluated in ascending id order)

PLAYER
  slot        pid 0..7 (unique)                                      required
  kind        "human" | "ai"                                         required
  name        label, ascii letters digits space - _ (max 20; default "Commander" / "Hostiles")
  roster      roster id from the bible, e.g. "roster.napc.vanilla"   required
  team        1..4 (players of one team are allies)                  required
  color       0..11 (unique; default = slot)
  start_slot  0..7, the map spawn slot the player's HQ / areas anchor to (unique; default = slot)
  credits     0..100000 (default rules.start_credits)
  handicap    50..200, multiple of 5 (default 100)
  ai          {level 0..15 (default 1), style 0..15 (default 0), active bool (default true), aggression 0..100 (default 50)}
              only for kind "ai". active=false: the AI issues no commands until a change_ai action turns it on. A level or style
              above what the AI module offers is clamped when the match is created (the file may name 0..15).
  start       {mode, units?, structures?}
                mode  "hq" (deployed HQ on the start slot) | "mcv" (MCV instead) | "none" (default "hq")
                units       [ {def: unit id, count 1..32 (default 1), dx, dy: cells from the start cell (default 0, 0)} ]
                structures  [ {def: structure id, dx, dy, id?: placed id} ]   free (no cost), active at tick 0

AREA  (cells; the anchor makes a mission independent of the generated terrain)
  id, shape "circle" | "rect", anchor "abs" (default) | "map" | "start:<slot>"
  circle: x, y, r (0..128; r 0 = the single cell)      rect: x, y, w, h (1..128; x, y = top-left)
  x, y mean: abs = map cell; map = permille of the map width / height (0..1000); start:N = signed cell offset from the
  start cell of player slot N. An entity is "in" an area when the cell it stands on is inside (circle: dx*dx+dy*dy <= r*r).
  Areas are clamped to the map.

MESSAGE   {id, text: string 1..400, speaker?: string, announcer?: announcer line id from data/audio/announcer.json}
OBJECTIVE {id, kind "primary"|"secondary"|"hidden", text: string 1..200, initial "active"|"hidden"|"completed"|"failed"}
          (default initial: "active"; kind hidden requires initial "hidden")
TIMER     {id, seconds 1..36000, repeat bool (default false), autostart bool (default false), label?: string}

TRIGGER   {id, once (default true), enabled (default true), edge (default false), cooldown_s (default 0), when: COND, then: [ACTION]}
  Every 5th tick (tick % 5 == 0) each enabled trigger is evaluated in id order; if `when` is true it runs its actions (1..32), in
  order. once=true: fires one time, then stays disabled. once=false: fires on every evaluation where `when` is true, but no
  more often than cooldown_s; edge=true: only when `when` turned true since the last evaluation. Actions may enable / disable
  triggers (a trigger_enable on a fired once-trigger re-arms it).

OWNER SELECTORS (owner / to / from)  an int slot | "neutral" | "all" | "team:N" | "enemies_of:S" | "allies_of:S" (S = slot)
  Counts and credits sum over the selected players; "defeated" / "no_assets" need ALL of them. Actions that create or
  change things need ONE player (int slot) or, where stated, "neutral".

COND  combinators: {all: [COND...]}  {any: [COND...]}  {not: COND}   (depth <= 8, <= 64 nodes)
  cmp is one of ">=" "<=" "==" ">" "<" "!=" (default ">=")
  {kind:"time", cmp?, seconds | ticks}                   world time compared with the value
  {kind:"timer", timer}                                  the timer has expired (stays true until it is started again)
  {kind:"objective", objective, state}                   state: "hidden"|"active"|"completed"|"failed"
  {kind:"count", owner, of?: "unit"|"structure"|"any", def?, tag?, area?, cmp?, value}
                 number of live entities of the owner; def = unit or structure id (of is inferred from the id prefix);
                 tag = a unit tag (of unit) or structure tag (of structure); area = only entities standing inside
                 (units that are transported are not "in" any area). Default of: "unit".
  {kind:"structure", state, owner?, def?, placed?}       state: "exists" | "powered" (owner + def, or a placed id)
                                                         | "destroyed" | "captured" (placed id only; captured: the
                                                         structure is alive and its owner differs from its first owner)
  {kind:"area_left", owner, area, def?, tag?}            the owner had units in the area earlier and has none now
  {kind:"credits", owner, cmp?, value}
  {kind:"research", owner, research: research id}        researched by the player
  {kind:"power", owner, cmp?, value}                     supply minus demand, e.g. {cmp ">=", value 0}
  {kind:"support_power", owner, slot 0..2, state}        state: "ready" (unlocked, cooldown over) | "used" (used at least once)
  {kind:"superweapon", owner, state}                     state: "fired" (launched at least once) | "ready"
  {kind:"defeated", owner}                               every selected player is eliminated
  {kind:"no_assets", owner}                              every selected player has no structure and no MCV
  {kind:"wave", wave, state}                             state: "spawned" | "cleared" (spawned and all its units dead)
  {kind:"trigger", trigger, cmp?, value}                 how often that trigger has fired (default >= 1)

ACTION  {do: <name>, ...}
  set_objective   {objective, state}
  show_message    {message, announcer?}                  announcer overrides the message's own line
  timer_start     {timer, seconds?}                      (re)starts; seconds overrides the duration
  timer_stop      {timer}
  spawn_units     {owner, def: unit id, count?, area, wave?: wave id, order?: {kind, area?}, facing?}
                  owner: slot | "neutral". Units appear on free cells around the centre of the area. order kinds:
                  "move" | "attack_move" | "guard" (each needs area) | "hold".
  spawn_structure {owner, def: structure id, area | cell: [x, y], id?: placed id, facing?: 0..3}
                  owner: slot | "neutral". Placed free and active; the footprint origin (top-left cell) is the area
                  centre or the cell, moved to the nearest buildable spot (<= 6 cells). `id` names it for conditions.
  give_credits    {owner: slot, amount: -100000..100000}  (negative takes at most what the player has)
  grant_power     {owner: slot, slot 0..2}            clears a lock / the cooldown (prerequisite structures still apply)
  lock_power      {owner: slot, slot 0..2}            the power cannot be used until granted
  reveal_area     {owner: slot | "team:N", area, seconds? (default 10)}   the area becomes explored and visible meanwhile
  change_ai       {owner: slot (an AI player), active?, level?, style?, aggression?}
  transfer        {to: slot | "neutral", placed | (owner, area?, def?, tag?, of?)}  new owner of a placed structure or of
                  every matching live entity
  destroy         {placed | (owner, area?, def?, tag?, of?)}
  order_units     {owner: slot | "team:N", area?, def?, tag?, order: {kind, area?}}   units of the owner (inside `area`)
  eliminate       {owner: slot}                          eliminates the player (its assets die)
  trigger_enable  {trigger}      trigger_disable {trigger}
  win             {owner: slot}                          ends the mission: that player's team wins
  lose            {owner: slot}                          ends the mission: that player is defeated
  camera_hint     {area | cell: [x, y], seconds? (default 5)}   UI-only
  music_state     {state: "auto"|"calm"|"combat"|"tense"|"victory"|"defeat"}   UI-only
  (Not included in v1: hiding an area again, power / knob overrides.)
"""

UNIT_TAGS = {"aircraft", "amphibious", "anti_air", "anti_submarine", "anti_tank", "artillery", "capture", "carrier", "collector",
             "combat", "command", "construction", "detector", "electronic_warfare", "ground", "ground_attack", "infantry",
             "land_vehicle", "light", "repair", "scout", "service", "ship", "siege", "specialist", "submarine", "tank",
             "transport", "unmanned"}
STRUCT_TAGS = {"advanced_defense", "defense", "relay", "structure", "superweapon"}
RULE_RANGES = {"start_credits": (0, 100000), "unit_cap": (20, 500), "superweapons": (0, 1), "fog": (0, 1), "shared_vision": (0, 1),
               "veterancy": (0, 1), "vision_stride": (1, 4), "vision_budget": (16, 512), "neutral_structures": (0, 1), "victory": (0, 1),
               "end_when_no_humans": (0, 1), "allow_debug": (0, 1)}
MIN_SIZE = {2: 96, 4: 128, 6: 160, 8: 192}
FAMILIES = ["open", "urban", "coast"]
CMPS = [">=", "<=", "==", ">", "<", "!="]
OBJ_STATES = ["hidden", "active", "completed", "failed"]
OBJ_KINDS = ["primary", "secondary", "hidden"]
STRUCT_STATES = ["exists", "powered", "destroyed", "captured"]
MUSIC = ["auto", "calm", "combat", "tense", "victory", "defeat"]
ORDER_KINDS = ["move", "attack_move", "guard", "hold"]
LORE_PREFIXES = ("faction.", "unit.", "structure.", "roster.", "research.", "power.", "superweapon.")
LIMITS = {"players": 8, "areas": 64, "messages": 128, "objectives": 64, "timers": 16, "triggers": 128, "actions": 32, "waves": 32, "placed": 64,
          "depth": 8, "nodes": 64}
COND_KEYS = {
    "time": ["kind", "cmp", "seconds", "ticks"], "timer": ["kind", "timer"], "objective": ["kind", "objective", "state"],
    "count": ["kind", "owner", "of", "def", "tag", "area", "cmp", "value"], "structure": ["kind", "state", "owner", "def", "placed"],
    "area_left": ["kind", "owner", "area", "def", "tag"], "credits": ["kind", "owner", "cmp", "value"],
    "research": ["kind", "owner", "research"], "power": ["kind", "owner", "cmp", "value"],
    "support_power": ["kind", "owner", "slot", "state"], "superweapon": ["kind", "owner", "state"], "defeated": ["kind", "owner"],
    "no_assets": ["kind", "owner"], "wave": ["kind", "wave", "state"], "trigger": ["kind", "trigger", "cmp", "value"],
}
TOP_KEYS = ["schema", "id", "title", "group", "order", "briefing", "map", "sim_seed", "rules", "players", "areas", "messages", "objectives",
            "timers", "triggers"]


class Vocab:
    """Ids the missions may reference, from the bible and the balance sheets."""

    def __init__(self, bible_path: Path = BIBLE, balance: Path = BALANCE, announcer: Path = ANNOUNCER) -> None:
        b = json.loads(bible_path.read_text(encoding="utf-8"))
        self.bible = b
        self.rosters = set(b.get("rosters", {}))
        self.units = set(b.get("units", {}))
        self.structures = set(b.get("structures", {}))
        self.research = set(b.get("research", {}))
        self.lore = {p: set(b.get(sec, {})) for p, sec in (("faction.", "factions"), ("unit.", "units"), ("structure.", "structures"),
                                                          ("roster.", "rosters"), ("research.", "research"), ("power.", "support_powers"),
                                                          ("superweapon.", "superweapons"))}
        self.unit_tags = set(UNIT_TAGS)
        self.struct_tags = set(STRUCT_TAGS)
        for f in sorted(balance.glob("units_*.json")):
            try:
                d = json.loads(f.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            for s in d.get("summons", []):
                if isinstance(s, dict) and isinstance(s.get("id"), str):
                    self.units.add(s["id"])
                    self.unit_tags.update(t for t in s.get("unit_tags", []) if isinstance(t, str))
            for u in d.get("units", []):
                if isinstance(u, dict):
                    self.unit_tags.update(t for t in u.get("tags_add", []) if isinstance(t, str))
        try:
            sd = json.loads((balance / "structures.json").read_text(encoding="utf-8"))
            for s in sd.get("structures", []):
                if isinstance(s, dict):
                    self.struct_tags.update(t for t in s.get("tags_add", []) if isinstance(t, str))
        except (OSError, ValueError):
            pass
        self.announcer_lines: set[str] | None = None
        try:
            self.announcer_lines = set(json.loads(announcer.read_text(encoding="utf-8")).get("lines", {}))
        except (OSError, ValueError):
            pass


class Problems:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def err(self, file: str, where: str, rule: str, msg: str) -> None:
        self.errors.append(f"{file}: {where or '-'}: {rule} {msg}")

    def warn(self, file: str, where: str, rule: str, msg: str) -> None:
        self.warnings.append(f"{file}: {where or '-'}: {rule} {msg}")


def is_int(v: object) -> bool:
    return isinstance(v, int) and not isinstance(v, bool) or (isinstance(v, float) and v == int(v))


def to_int(v: object) -> int:
    return int(v)  # type: ignore[call-overload]


class MissionCheck:
    def __init__(self, raw: object, file: str, vocab: Vocab, out: Problems) -> None:
        self.raw, self.file, self.v, self.out = raw, file, vocab, out
        self.slots: dict[int, dict] = {}
        self.areas: set[str] = set()
        self.msgs: set[str] = set()
        self.objs: set[str] = set()
        self.timers: set[str] = set()
        self.trigs: set[str] = set()
        self.waves: set[str] = set()
        self.placed: set[str] = set()
        self.layout = 2

    # ---- helpers
    def e(self, where: str, rule: str, msg: str) -> None:
        self.out.err(self.file, where, rule, msg)

    def keys(self, d: dict, allowed: list[str], where: str) -> None:
        for k in d:
            if k not in allowed:
                self.e(where, "V-MIS-02", f"unknown key '{k}' (allowed: {', '.join(allowed)})")

    def num(self, d: dict, key: str, lo: int, hi: int, dflt: int | None, where: str, required: bool = False) -> int | None:
        if key not in d:
            if required:
                self.e(where, "V-MIS-02", f"missing required field '{key}'")
            return dflt
        v = d[key]
        if not is_int(v):
            self.e(where, "V-MIS-02", f"'{key}' must be an integer")
            return dflt
        n = to_int(v)
        if n < lo or n > hi:
            self.e(where, "V-MIS-02", f"'{key}' = {n} is outside {lo}..{hi}")
            return dflt
        return n

    def string(self, d: dict, key: str, lo: int, hi: int, dflt: str, where: str, required: bool = False) -> str:
        if key not in d:
            if required:
                self.e(where, "V-MIS-02", f"missing required field '{key}'")
            return dflt
        v = d[key]
        if not isinstance(v, str):
            self.e(where, "V-MIS-02", f"'{key}' must be a string")
            return dflt
        if len(v) < lo or len(v) > hi:
            self.e(where, "V-MIS-02", f"'{key}' must have {lo}..{hi} characters")
            return dflt
        return v

    def boolean(self, d: dict, key: str, dflt: bool, where: str) -> bool:
        if key not in d:
            return dflt
        v = d[key]
        if isinstance(v, bool):
            return v
        if is_int(v) and to_int(v) in (0, 1):
            return to_int(v) == 1
        self.e(where, "V-MIS-02", f"'{key}' must be a boolean (or 0 / 1)")
        return dflt

    def ref(self, table: set[str], what: str, d: dict, key: str, where: str, required: bool = True) -> None:
        if key not in d:
            if required:
                self.e(where, "V-MIS-02", f"missing required field '{key}'")
            return
        if str(d[key]) not in table:
            self.e(where, "V-MIS-03", f"unknown {what} '{d[key]}'")

    def obj(self, v: object, where: str) -> dict:
        if isinstance(v, dict):
            return v
        self.e(where, "V-MIS-02", "must be an object")
        return {}

    def lst(self, d: dict, key: str, mx: int) -> list:
        v = d.get(key, [])
        if not isinstance(v, list):
            self.e(key, "V-MIS-02", "must be an array")
            return []
        if len(v) > mx:
            self.e(key, "V-MIS-02", f"has {len(v)} entries, at most {mx}")
            return []
        return v

    def ticks(self, d: dict, where: str, lo: int, hi: int) -> int:
        if "seconds" in d and "ticks" in d:
            self.e(where, "V-MIS-05", "give either 'seconds' or 'ticks', not both")
            return -1
        if "seconds" in d:
            n = self.num(d, "seconds", lo, hi, -1, where)
            return n * TPS if n is not None and n >= 0 else -1
        if "ticks" in d:
            n = self.num(d, "ticks", lo * TPS, hi * TPS, -1, where)
            return -1 if n is None else n
        return -1

    # ---- selectors / filters
    def owner(self, v: object, where: str, single: bool, neutral: bool) -> tuple[str, int] | None:
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            if not is_int(v):
                self.e(where, "V-MIS-02", "player slot must be an integer")
                return None
            if to_int(v) not in self.slots:
                self.e(where, "V-MIS-03", f"unknown player slot {to_int(v)}")
                return None
            return ("pid", to_int(v))
        if not isinstance(v, str):
            self.e(where, "V-MIS-02", "owner must be a slot number or a selector string")
            return None
        if v == "neutral":
            if not neutral:
                self.e(where, "V-MIS-05", "'neutral' is not allowed here")
                return None
            return ("neutral", -1)
        if single:
            self.e(where, "V-MIS-05", "this field needs exactly one player slot" + (' or "neutral"' if neutral else ""))
            return None
        if v == "all":
            return ("all", 0)
        m = re.fullmatch(r"(team|enemies_of|allies_of):(\d+)", v)
        if m:
            n = int(m.group(2))
            if (m.group(1) == "team" and 1 <= n <= 4) or (m.group(1) != "team" and n in self.slots):
                return (m.group(1), n)
        self.e(where, "V-MIS-02", f"bad owner selector '{v}' (slot | neutral | all | team:N | enemies_of:S | allies_of:S)")
        return None

    def owner_key(self, d: dict, where: str, single: bool, neutral: bool = False, key: str = "owner") -> None:
        if key not in d:
            self.e(where, "V-MIS-02", f"missing required field '{key}'")
            return
        self.owner(d[key], f"{where}.{key}", single, neutral)

    def filt(self, d: dict, where: str, units_only: bool = False) -> str:
        of = "unit"
        explicit = False
        if "of" in d:
            of = self.string(d, "of", 3, 9, "unit", where)
            if of not in ("unit", "structure", "any"):
                self.e(where, "V-MIS-02", "of must be unit, structure or any")
                of = "unit"
            explicit = True
        if "def" in d:
            ident = self.string(d, "def", 1, 80, "", where)
            if ident.startswith("unit.") and ident in self.v.units:
                kind = "unit"
            elif ident.startswith("structure.") and ident in self.v.structures:
                kind = "structure"
            else:
                self.e(where, "V-MIS-03", f"unknown unit / structure def '{ident}'")
                kind = of
            if explicit and kind != of:
                self.e(where, "V-MIS-05", f"'of' contradicts the def '{ident}'")
            of = kind
        if "tag" in d:
            tv = d["tag"]
            names = [tv] if isinstance(tv, str) else tv if isinstance(tv, list) else None
            if names is None:
                self.e(where, "V-MIS-02", "tag must be a string or an array of strings")
                names = []
            if of == "any":
                self.e(where, "V-MIS-05", "a tag needs of unit or structure")
            pool = self.v.unit_tags if of == "unit" else self.v.struct_tags
            for n in names:
                if str(n) not in pool:
                    self.e(where, "V-MIS-03", f"unknown {of} tag '{n}'")
        if units_only and of != "unit":
            self.e(where, "V-MIS-05", "this action only addresses units")
        return of

    def area(self, d: dict, where: str, key: str = "area", required: bool = False) -> None:
        self.ref(self.areas, "area", d, key, where, required)

    # ---- build
    def run(self) -> None:
        raw = self.raw
        if not isinstance(raw, dict):
            self.e("", "V-MIS-01", "top level must be a JSON object")
            return
        self.keys(raw, TOP_KEYS, "")
        if raw.get("schema") != SCHEMA_ID:
            self.e("schema", "V-MIS-01", f'must be "{SCHEMA_ID}"')
        mid = self.string(raw, "id", 1, 40, "", "", True)
        if mid and not ID_RE.match(mid):
            self.e("id", "V-MIS-01", f"'{mid}' is not a valid id (lowercase [a-z][a-z0-9_]*, max 40)")
        if mid and self.file != mid + ".json":
            self.e("id", "V-MIS-01", f"id '{mid}' does not match the file name '{self.file}'")
        self.string(raw, "title", 1, 60, "", "", True)
        grp = self.string(raw, "group", 1, 24, "custom", "")
        if not ID_RE.match(grp):
            self.e("group", "V-MIS-02", f"'{grp}' is not a lowercase word")
        self.num(raw, "order", 0, 9999, 0, "")
        self.briefing(raw)
        self.collect(raw)
        self.players(raw)
        self.map(raw)
        self.rules(raw)
        self.area_list(raw)
        self.simple_lists(raw)
        self.triggers(raw)

    def briefing(self, raw: dict) -> None:
        for i, bv in enumerate(self.lst(raw, "briefing", 32)):
            w = f"briefing[{i}]"
            b = self.obj(bv, w)
            self.keys(b, ["heading", "text", "lore"], w)
            self.string(b, "heading", 0, 80, "", w)
            self.string(b, "text", 1, 2000, "", w, True)
            lore = self.string(b, "lore", 0, 80, "", w)
            if lore:
                pre = next((p for p in LORE_PREFIXES if lore.startswith(p)), None)
                if pre is None or lore not in self.v.lore[pre]:
                    self.e(w, "V-MIS-03", f"lore '{lore}' is not a bible id")

    def collect(self, raw: dict) -> None:
        counts: dict[str, int] = {}
        for pv in raw.get("players", []) if isinstance(raw.get("players"), list) else []:
            st = pv.get("start") if isinstance(pv, dict) else None
            for sv in (st.get("structures", []) if isinstance(st, dict) and isinstance(st.get("structures"), list) else []):
                if isinstance(sv, dict) and "id" in sv:
                    counts[str(sv["id"])] = counts.get(str(sv["id"]), 0) + 1
        ids: list[str] = []
        for tv in raw.get("triggers", []) if isinstance(raw.get("triggers"), list) else []:
            if not isinstance(tv, dict):
                continue
            ids.append(str(tv.get("id", "")))
            for av in tv.get("then", []) if isinstance(tv.get("then"), list) else []:
                if not isinstance(av, dict):
                    continue
                if av.get("do") == "spawn_structure" and "id" in av:
                    counts[str(av["id"])] = counts.get(str(av["id"]), 0) + 1
                elif av.get("do") == "spawn_units" and "wave" in av:
                    self.waves.add(str(av["wave"]))
        for k, n in counts.items():
            if n > 1:
                self.e("placed", "V-MIS-04", f"placed id '{k}' is declared {n} times")
            self.placed.add(k)
        for i in sorted(set(ids)):
            if ids.count(i) > 1:
                self.e("triggers", "V-MIS-04", f"duplicate trigger id '{i}'")
        self.trigs = set(ids)
        if len(self.waves) > LIMITS["waves"]:
            self.e("waves", "V-MIS-02", f"more than {LIMITS['waves']} waves")
        if len(self.placed) > LIMITS["placed"]:
            self.e("placed", "V-MIS-02", f"more than {LIMITS['placed']} placed structures")
        for w in sorted(self.waves) + sorted(self.placed):
            if not ID_RE.match(w):
                self.e("ids", "V-MIS-02", f"bad wave / placed id '{w}'")

    def players(self, raw: dict) -> None:
        arr = self.lst(raw, "players", LIMITS["players"])
        if not arr:
            self.e("players", "V-MIS-06", "a mission needs 1..8 players")
        humans = 0
        colors: set[int] = set()
        starts: set[int] = set()
        parsed: list[dict] = []
        for i, pv in enumerate(arr):
            w = f"players[{i}]"
            d = self.obj(pv, w)
            slot = self.num(d, "slot", 0, 7, None, w, True)
            if slot is None:
                continue
            if slot in self.slots:
                self.e(w, "V-MIS-04", f"duplicate slot {slot}")
            self.slots[slot] = d
            parsed.append(d)
            self.keys(d, ["slot", "kind", "name", "roster", "team", "color", "start_slot", "credits", "handicap", "ai", "start"], w)
            kind = self.string(d, "kind", 2, 5, "", w, True)
            if kind not in ("human", "ai"):
                self.e(w, "V-MIS-02", 'kind must be "human" or "ai"')
            humans += 1 if kind == "human" else 0
            nm = self.string(d, "name", 1, 20, "x", w)
            if not re.fullmatch(r"[A-Za-z0-9_-]+( +[A-Za-z0-9_-]+)*", nm):
                self.e(w, "V-MIS-02", f"name '{nm}' may only use letters, digits, space, - and _ (no space at either end)")
            roster = self.string(d, "roster", 1, 40, "", w, True)
            if roster and roster not in self.v.rosters:
                self.e(w, "V-MIS-03", f"unknown roster '{roster}'")
            self.num(d, "team", 1, 4, None, w, True)
            col = self.num(d, "color", 0, 11, slot, w)
            if col in colors:
                self.e(w, "V-MIS-04", f"duplicate color {col}")
            colors.add(col)  # type: ignore[arg-type]
            ss = self.num(d, "start_slot", 0, 7, slot, w)
            if ss in starts:
                self.e(w, "V-MIS-04", f"duplicate start_slot {ss}")
            starts.add(ss)  # type: ignore[arg-type]
            d["_start_slot"] = ss
            self.num(d, "credits", 0, 100000, -1, w)
            hc = self.num(d, "handicap", 50, 200, 100, w)
            if hc is not None and hc % 5:
                self.e(w, "V-MIS-02", "handicap must be a multiple of 5")
            if "ai" in d:
                if kind == "human":
                    self.e(w, "V-MIS-05", "'ai' is only for kind \"ai\"")
                else:
                    a = self.obj(d["ai"], w + ".ai")
                    self.keys(a, ["level", "style", "active", "aggression"], w + ".ai")
                    self.num(a, "level", 0, 15, 1, w + ".ai")
                    self.num(a, "style", 0, 15, 0, w + ".ai")
                    self.boolean(a, "active", True, w + ".ai")
                    self.num(a, "aggression", 0, 100, 50, w + ".ai")
            if "start" in d:
                self.start(self.obj(d["start"], w + ".start"), w + ".start")
        if arr and humans != 1:
            self.e("players", "V-MIS-06", f'exactly one player must have kind "human" (found {humans})')
        need = len(parsed)
        for p in parsed:
            need = max(need, (p.get("_start_slot") or 0) + 1)
        self.layout = next((n for n in (2, 4, 6, 8) if n >= need), 0)
        if self.layout == 0:
            self.e("players", "V-MIS-06", "start slots need a layout of more than 8 players")
            self.layout = 8

    def start(self, d: dict, w: str) -> None:
        self.keys(d, ["mode", "units", "structures"], w)
        if self.string(d, "mode", 2, 4, "hq", w) not in ("hq", "mcv", "none"):
            self.e(w, "V-MIS-02", "mode must be hq, mcv or none")
        for key, pool, kind in (("units", self.v.units, "unit"), ("structures", self.v.structures, "structure")):
            if key in d and not isinstance(d[key], list):
                self.e(w, "V-MIS-02", f"'{key}' must be an array")
                continue
            arr = d.get(key, [])
            if len(arr) > 32:
                self.e(w, "V-MIS-02", f"'{key}' has more than 32 entries")
            for j, ev in enumerate(arr):
                ww = f"{w}.{key}[{j}]"
                e = self.obj(ev, ww)
                self.keys(e, ["def", "count", "dx", "dy", "id"] if kind == "structure" else ["def", "count", "dx", "dy"], ww)
                ident = self.string(e, "def", 1, 80, "", ww, True)
                if ident and ident not in pool:
                    self.e(ww, "V-MIS-03", f"unknown {kind} '{ident}'")
                if kind == "unit":
                    self.num(e, "count", 1, 32, 1, ww)
                self.num(e, "dx", -64, 64, 0, ww)
                self.num(e, "dy", -64, 64, 0, ww)

    def map(self, raw: dict) -> None:
        if "map" not in raw:
            self.e("map", "V-MIS-02", "missing required field 'map'")
        d = self.obj(raw.get("map", {}), "map")
        self.keys(d, ["family", "size", "seed", "params"], "map")
        fam = d.get("family", 0)
        if not (isinstance(fam, str) and fam in FAMILIES) and not (is_int(fam) and 0 <= to_int(fam) <= 2):
            self.e("map", "V-MIS-02", "family must be open, urban, coast (or 0..2)")
        size = self.num(d, "size", 96, 256, 128, "map", True)
        if size is not None and size % 8:
            self.e("map", "V-MIS-06", "size must be a multiple of 8")
        if size is not None and size < MIN_SIZE.get(self.layout, 0):
            self.e("map", "V-MIS-06", f"size {size} is below the minimum {MIN_SIZE[self.layout]} of a {self.layout}-slot layout")
        self.num(d, "seed", 0, 0xFFFFFFFF, 1, "map", True)
        self.num(raw, "sim_seed", 0, 0xFFFFFFFF, 1, "")
        if "params" in d:
            p = self.obj(d["params"], "map.params")
            self.keys(p, ["water_pct", "density", "resources", "neutrals", "biome", "start_near_water"], "map.params")
            for k, (lo, hi) in {"water_pct": (0, 40), "density": (0, 100), "resources": (0, 100), "neutrals": (0, 100), "biome": (0, 2)}.items():
                if k in p:
                    self.num(p, k, lo, hi, 0, "map.params")
            if "start_near_water" in p:
                self.boolean(p, "start_near_water", False, "map.params")

    def rules(self, raw: dict) -> None:
        d = self.obj(raw.get("rules", {}), "rules")
        self.keys(d, list(RULE_RANGES), "rules")
        for k, (lo, hi) in RULE_RANGES.items():
            if k in d and not isinstance(d[k], bool):
                self.num(d, k, lo, hi, lo, "rules")

    def area_list(self, raw: dict) -> None:
        for i, av in enumerate(self.lst(raw, "areas", LIMITS["areas"])):
            w = f"areas[{i}]"
            d = self.obj(av, w)
            aid = self.string(d, "id", 1, 40, "", w, True)
            if not ID_RE.match(aid):
                self.e(w, "V-MIS-01", f"'{aid}' is not a valid id")
            if aid in self.areas:
                self.e(w, "V-MIS-04", f"duplicate area id '{aid}'")
            self.areas.add(aid)
            shape = self.string(d, "shape", 4, 6, "", w, True)
            if shape == "circle":
                self.keys(d, ["id", "shape", "anchor", "x", "y", "r"], w)
                self.num(d, "r", 0, 128, 0, w, True)
            elif shape == "rect":
                self.keys(d, ["id", "shape", "anchor", "x", "y", "w", "h"], w)
                self.num(d, "w", 1, 128, 1, w, True)
                self.num(d, "h", 1, 128, 1, w, True)
            else:
                self.e(w, "V-MIS-02", "shape must be circle or rect")
            anchor = self.string(d, "anchor", 3, 10, "abs", w)
            m = re.fullmatch(r"start:(\d+)", anchor)
            if anchor == "abs":
                self.num(d, "x", 0, 255, 0, w, True)
                self.num(d, "y", 0, 255, 0, w, True)
            elif anchor == "map":
                self.num(d, "x", 0, 1000, 0, w, True)
                self.num(d, "y", 0, 1000, 0, w, True)
            elif m and int(m.group(1)) in self.slots:
                self.num(d, "x", -255, 255, 0, w, True)
                self.num(d, "y", -255, 255, 0, w, True)
            else:
                self.e(w, "V-MIS-03", f"anchor must be abs, map or start:<player slot> (got '{anchor}')")

    def simple_lists(self, raw: dict) -> None:
        for i, mv in enumerate(self.lst(raw, "messages", LIMITS["messages"])):
            w = f"messages[{i}]"
            d = self.obj(mv, w)
            self.keys(d, ["id", "text", "speaker", "announcer"], w)
            mid = self.string(d, "id", 1, 40, "", w, True)
            if not ID_RE.match(mid):
                self.e(w, "V-MIS-01", f"'{mid}' is not a valid id")
            if mid in self.msgs:
                self.e(w, "V-MIS-04", f"duplicate message id '{mid}'")
            self.msgs.add(mid)
            self.string(d, "text", 1, 400, "", w, True)
            self.string(d, "speaker", 0, 40, "", w)
            ann = self.string(d, "announcer", 0, 60, "", w)
            self.announcer_line(ann, w)
        for i, ov in enumerate(self.lst(raw, "objectives", LIMITS["objectives"])):
            w = f"objectives[{i}]"
            d = self.obj(ov, w)
            self.keys(d, ["id", "kind", "text", "initial"], w)
            oid = self.string(d, "id", 1, 40, "", w, True)
            if not ID_RE.match(oid):
                self.e(w, "V-MIS-01", f"'{oid}' is not a valid id")
            if oid in self.objs:
                self.e(w, "V-MIS-04", f"duplicate objective id '{oid}'")
            self.objs.add(oid)
            kind = self.string(d, "kind", 1, 12, "", w, True)
            if kind not in OBJ_KINDS:
                self.e(w, "V-MIS-02", "kind must be primary, secondary or hidden")
            self.string(d, "text", 1, 200, "", w, True)
            ini = self.string(d, "initial", 1, 12, "hidden" if kind == "hidden" else "active", w)
            if ini not in OBJ_STATES:
                self.e(w, "V-MIS-02", "initial must be hidden, active, completed or failed")
            elif kind == "hidden" and ini != "hidden":
                self.e(w, "V-MIS-05", "a hidden objective must start hidden")
        for i, tv in enumerate(self.lst(raw, "timers", LIMITS["timers"])):
            w = f"timers[{i}]"
            d = self.obj(tv, w)
            self.keys(d, ["id", "seconds", "repeat", "autostart", "label"], w)
            tid = self.string(d, "id", 1, 40, "", w, True)
            if not ID_RE.match(tid):
                self.e(w, "V-MIS-01", f"'{tid}' is not a valid id")
            if tid in self.timers:
                self.e(w, "V-MIS-04", f"duplicate timer id '{tid}'")
            self.timers.add(tid)
            self.num(d, "seconds", 1, 36000, 1, w, True)
            self.boolean(d, "repeat", False, w)
            self.boolean(d, "autostart", False, w)
            self.string(d, "label", 0, 40, "", w)

    def announcer_line(self, line: str, where: str) -> None:
        if line and self.v.announcer_lines is not None and line not in self.v.announcer_lines:
            self.out.warn(self.file, where, "V-MIS-07", f"announcer line '{line}' is not in data/audio/announcer.json")

    # ---- triggers
    def triggers(self, raw: dict) -> None:
        arr = self.lst(raw, "triggers", LIMITS["triggers"])
        for tv in arr:
            if not isinstance(tv, dict):
                self.e("triggers", "V-MIS-02", "every trigger must be an object")
                continue
            tid = str(tv.get("id", ""))
            w = f"triggers[{tid}]"
            self.keys(tv, ["id", "once", "enabled", "edge", "cooldown_s", "when", "then"], w)
            if not ID_RE.match(tid):
                self.e(w, "V-MIS-01", f"'{tid}' is not a valid trigger id")
            self.boolean(tv, "once", True, w)
            self.boolean(tv, "enabled", True, w)
            self.boolean(tv, "edge", False, w)
            self.num(tv, "cooldown_s", 0, 36000, 0, w)
            self.nodes = 0
            if isinstance(tv.get("when"), dict):
                self.cond(tv["when"], 0, w + ".when")
            else:
                self.e(w, "V-MIS-02", "'when' (a condition object) is required")
            acts = tv.get("then")
            if not isinstance(acts, list) or not acts:
                self.e(w, "V-MIS-02", "'then' must be a non-empty array of actions")
                continue
            if len(acts) > LIMITS["actions"]:
                self.e(w, "V-MIS-02", f"'then' has more than {LIMITS['actions']} actions")
                continue
            for i, av in enumerate(acts):
                if isinstance(av, dict):
                    self.action(av, f"{w}.then[{i}]")
                else:
                    self.e(w, "V-MIS-02", f"then[{i}] must be an object")

    def cmp(self, d: dict, w: str) -> None:
        if self.string(d, "cmp", 1, 2, ">=", w) not in CMPS:
            self.e(w, "V-MIS-02", f"cmp must be one of {', '.join(CMPS)}")

    def state(self, d: dict, w: str, names: list[str]) -> None:
        s = self.string(d, "state", 1, 12, "", w, True)
        if s and s not in names:
            self.e(w, "V-MIS-02", f"state must be one of {', '.join(names)}")

    def cond(self, d: dict, depth: int, w: str) -> None:
        self.nodes += 1
        if self.nodes > LIMITS["nodes"]:
            self.e(w, "V-MIS-05", f"condition tree has more than {LIMITS['nodes']} nodes")
            return
        if depth > LIMITS["depth"]:
            self.e(w, "V-MIS-05", f"condition tree deeper than {LIMITS['depth']}")
            return
        for comb in ("all", "any", "not"):
            if comb in d:
                if len(d) != 1:
                    self.e(w, "V-MIS-05", f"'{comb}' must be the only key of its object")
                sub = d[comb]
                if comb == "not":
                    if isinstance(sub, dict):
                        self.cond(sub, depth + 1, w + ".not")
                    else:
                        self.e(w, "V-MIS-05", "'not' takes one condition object")
                elif isinstance(sub, list) and sub:
                    for i, s in enumerate(sub):
                        if isinstance(s, dict):
                            self.cond(s, depth + 1, f"{w}.{comb}[{i}]")
                        else:
                            self.e(w, "V-MIS-05", f"'{comb}' entries must be condition objects")
                else:
                    self.e(w, "V-MIS-05", f"'{comb}' takes a non-empty array of conditions")
                return
        kind = self.string(d, "kind", 1, 20, "", w, True)
        if kind not in COND_KEYS:
            self.e(w, "V-MIS-05", f"unknown condition kind '{kind}'")
            return
        self.keys(d, COND_KEYS[kind], w)
        if kind == "time":
            self.cmp(d, w)
            if self.ticks(d, w, 0, 36000) < 0 and "seconds" not in d and "ticks" not in d:
                self.e(w, "V-MIS-05", "time needs 'seconds' or 'ticks'")
        elif kind == "timer":
            self.ref(self.timers, "timer", d, "timer", w)
        elif kind == "objective":
            self.ref(self.objs, "objective", d, "objective", w)
            self.state(d, w, OBJ_STATES)
        elif kind == "count":
            self.owner_key(d, w, False, True)
            self.filt(d, w)
            self.area(d, w)
            self.cmp(d, w)
            self.num(d, "value", 0, 100000, 0, w, True)
        elif kind == "structure":
            self.state(d, w, STRUCT_STATES)
            if "placed" in d:
                self.ref(self.placed, "placed structure", d, "placed", w)
                if "def" in d:
                    self.e(w, "V-MIS-05", "give 'placed' or 'def', not both")
                if "owner" in d:
                    self.owner_key(d, w, True)
            else:
                if d.get("state") in ("destroyed", "captured"):
                    self.e(w, "V-MIS-05", f"state {d.get('state')} needs a 'placed' id")
                self.owner_key(d, w, False)
                if "def" not in d or self.filt({"def": d["def"]}, w) != "structure":
                    self.e(w, "V-MIS-05", "needs a structure 'def' or a 'placed' id")
        elif kind == "area_left":
            self.owner_key(d, w, False)
            self.filt(d, w, True)
            self.area(d, w, required=True)
        elif kind in ("credits", "power"):
            self.owner_key(d, w, False)
            self.cmp(d, w)
            self.num(d, "value", -100000, 1000000, 0, w, True)
        elif kind == "research":
            self.owner_key(d, w, True)
            r = self.string(d, "research", 1, 80, "", w, True)
            if r and r not in self.v.research:
                self.e(w, "V-MIS-03", f"unknown research '{r}'")
        elif kind == "support_power":
            self.owner_key(d, w, True)
            self.num(d, "slot", 0, 2, 0, w, True)
            self.state(d, w, ["ready", "used"])
        elif kind == "superweapon":
            self.owner_key(d, w, True)
            self.state(d, w, ["fired", "ready"])
        elif kind in ("defeated", "no_assets"):
            self.owner_key(d, w, False)
        elif kind == "wave":
            self.ref(self.waves, "wave", d, "wave", w)
            self.state(d, w, ["spawned", "cleared"])
        elif kind == "trigger":
            self.ref(self.trigs, "trigger", d, "trigger", w)
            self.cmp(d, w)
            self.num(d, "value", 0, 100000, 1, w)

    def order(self, d: dict, w: str, required: bool) -> None:
        if "order" not in d:
            if required:
                self.e(w, "V-MIS-02", "missing required field 'order'")
            return
        o = self.obj(d["order"], w + ".order")
        self.keys(o, ["kind", "area"], w + ".order")
        kind = self.string(o, "kind", 1, 12, "", w + ".order", True)
        if kind not in ORDER_KINDS:
            self.e(w, "V-MIS-02", "order kind must be move, attack_move, guard or hold")
        elif kind == "hold":
            if "area" in o:
                self.e(w, "V-MIS-05", "a hold order takes no area")
        else:
            self.area(o, w + ".order", required=True)

    def cell(self, v: object, w: str) -> None:
        if not (isinstance(v, list) and len(v) == 2 and all(is_int(x) for x in v)):
            self.e(w, "V-MIS-02", "cell must be [x, y] (integers)")
        elif any(not 0 <= to_int(x) <= 255 for x in v):
            self.e(w, "V-MIS-02", "cell must be inside 0..255")

    def action(self, d: dict, w: str) -> None:
        names = ["set_objective", "show_message", "timer_start", "timer_stop", "spawn_units", "spawn_structure", "give_credits", "grant_power",
                 "lock_power", "reveal_area", "change_ai", "transfer", "destroy", "order_units", "eliminate", "trigger_enable", "trigger_disable",
                 "win", "lose", "camera_hint", "music_state"]
        name = self.string(d, "do", 1, 20, "", w, True)
        if name not in names:
            self.e(w, "V-MIS-05", f"unknown action '{name}'")
            return
        if name == "set_objective":
            self.keys(d, ["do", "objective", "state"], w)
            self.ref(self.objs, "objective", d, "objective", w)
            self.state(d, w, OBJ_STATES)
        elif name == "show_message":
            self.keys(d, ["do", "message", "announcer"], w)
            self.ref(self.msgs, "message", d, "message", w)
            self.announcer_line(self.string(d, "announcer", 0, 60, "", w), w)
        elif name == "timer_start":
            self.keys(d, ["do", "timer", "seconds"], w)
            self.ref(self.timers, "timer", d, "timer", w)
            self.num(d, "seconds", 1, 36000, 0, w)
        elif name == "timer_stop":
            self.keys(d, ["do", "timer"], w)
            self.ref(self.timers, "timer", d, "timer", w)
        elif name == "spawn_units":
            self.keys(d, ["do", "owner", "def", "count", "area", "wave", "order", "facing"], w)
            self.owner_key(d, w, True, True)
            ident = self.string(d, "def", 1, 80, "", w, True)
            if ident and ident not in self.v.units:
                self.e(w, "V-MIS-03", f"unknown unit '{ident}'")
            self.num(d, "count", 1, 64, 1, w)
            self.area(d, w, required=True)
            self.num(d, "facing", 0, 4095, 0, w)
            self.order(d, w, False)
        elif name == "spawn_structure":
            self.keys(d, ["do", "owner", "def", "area", "cell", "id", "facing"], w)
            self.owner_key(d, w, True, True)
            ident = self.string(d, "def", 1, 80, "", w, True)
            if ident and ident not in self.v.structures:
                self.e(w, "V-MIS-03", f"unknown structure '{ident}'")
            self.num(d, "facing", 0, 3, 0, w)
            if ("area" in d) == ("cell" in d):
                self.e(w, "V-MIS-05", "give exactly one of 'area' or 'cell'")
            if "area" in d:
                self.area(d, w, required=True)
            elif "cell" in d:
                self.cell(d["cell"], w)
        elif name == "give_credits":
            self.keys(d, ["do", "owner", "amount"], w)
            self.owner_key(d, w, True)
            if self.num(d, "amount", -100000, 100000, 0, w, True) == 0 and "amount" in d:
                self.e(w, "V-MIS-02", "amount must not be 0")
        elif name in ("grant_power", "lock_power"):
            self.keys(d, ["do", "owner", "slot"], w)
            self.owner_key(d, w, True)
            self.num(d, "slot", 0, 2, 0, w, True)
        elif name == "reveal_area":
            self.keys(d, ["do", "owner", "area", "seconds"], w)
            if "owner" in d:
                sel = self.owner(d["owner"], w + ".owner", False, False)
                if sel is not None and sel[0] not in ("pid", "team"):
                    self.e(w, "V-MIS-05", "reveal_area needs a slot or team:N")
            else:
                self.e(w, "V-MIS-02", "missing required field 'owner'")
            self.area(d, w, required=True)
            self.num(d, "seconds", 1, 3600, 10, w)
        elif name == "change_ai":
            self.keys(d, ["do", "owner", "active", "level", "style", "aggression"], w)
            self.owner_key(d, w, True)
            if isinstance(d.get("owner"), int) and d["owner"] in self.slots and self.slots[d["owner"]].get("kind") == "human":
                self.e(w, "V-MIS-05", "change_ai needs an AI player")
            self.boolean(d, "active", True, w)
            self.num(d, "level", 0, 15, -1, w)
            self.num(d, "style", 0, 15, -1, w)
            self.num(d, "aggression", 0, 100, -1, w)
            if not any(k in d for k in ("active", "level", "style", "aggression")):
                self.e(w, "V-MIS-05", "change_ai changes nothing")
        elif name in ("transfer", "destroy"):
            self.keys(d, ["do", "placed", "owner", "area", "def", "tag", "of"] + (["to"] if name == "transfer" else []), w)
            if name == "transfer":
                if "to" not in d:
                    self.e(w, "V-MIS-02", "missing required field 'to'")
                else:
                    self.owner(d["to"], w + ".to", True, True)
            if "placed" in d:
                for k in ("owner", "area", "def", "tag", "of"):
                    if k in d:
                        self.e(w, "V-MIS-05", f"'placed' cannot be combined with '{k}'")
                self.ref(self.placed, "placed id", d, "placed", w)
            else:
                self.owner_key(d, w, False, True)
                self.filt(d, w)
                self.area(d, w)
                if not any(k in d for k in ("def", "tag", "of", "area")):
                    self.e(w, "V-MIS-05", "this action needs a 'placed' id or a filter (def / tag / of / area)")
        elif name == "order_units":
            self.keys(d, ["do", "owner", "area", "def", "tag", "order"], w)
            self.owner_key(d, w, False)
            self.filt(d, w, True)
            self.area(d, w)
            self.order(d, w, True)
        elif name in ("eliminate", "win", "lose"):
            self.keys(d, ["do", "owner"], w)
            self.owner_key(d, w, True)
        elif name in ("trigger_enable", "trigger_disable"):
            self.keys(d, ["do", "trigger"], w)
            self.ref(self.trigs, "trigger", d, "trigger", w)
        elif name == "camera_hint":
            self.keys(d, ["do", "area", "cell", "seconds"], w)
            if ("area" in d) == ("cell" in d):
                self.e(w, "V-MIS-05", "give exactly one of 'area' or 'cell'")
            if "area" in d:
                self.area(d, w, required=True)
            elif "cell" in d:
                self.cell(d["cell"], w)
            self.num(d, "seconds", 1, 600, 5, w)
        elif name == "music_state":
            self.keys(d, ["do", "state"], w)
            self.state(d, w, MUSIC)


def check_mission(raw: object, file: str, vocab: Vocab, out: Problems) -> None:
    """Validates one parsed mission document (`file` is its file name, e.g. demo_ambush.json)."""
    MissionCheck(raw, file, vocab, out).run()


def load_json(path: Path, out: Problems, label: str) -> object | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as e:
        out.err(label, "", "V-MIS-01", f"cannot read: {e}")
    except ValueError as e:
        out.err(label, "", "V-MIS-01", f"invalid JSON: {e}")
    return None


def check_all(missions_dir: Path = MISSIONS, balance: Path = BALANCE, vocab: Vocab | None = None, only: list[Path] | None = None) -> Problems:
    out = Problems()
    vocab = vocab or Vocab(balance=balance)
    listed: list[str] = []
    man = load_json(balance / "manifest.json", out, "manifest.json")
    if isinstance(man, dict):
        listed = [str(x) for x in man.get("missions", [])] if isinstance(man.get("missions", []), list) else []
        if listed != sorted(listed):
            out.err("manifest.json", "missions", "V-MIS-01", "must be sorted ascending")
        for dup in sorted({f for f in listed if listed.count(f) > 1}):
            out.err("manifest.json", "missions", "V-MIS-04", f"duplicate entry '{dup}'")
        for f in listed:
            if not re.fullmatch(r"[a-z][a-z0-9_]*\.json", f):
                out.err("manifest.json", "missions", "V-MIS-01", f"'{f}' is not <id>.json")
    files = [p for p in only] if only else [missions_dir / f for f in listed]
    for p in files:
        if not p.is_file():
            out.err(p.name, "", "V-SCH-01", "listed in the manifest but the file does not exist")
            continue
        raw = load_json(p, out, p.name)
        if raw is not None:
            check_mission(raw, p.name, vocab, out)
    if not only and missions_dir.is_dir():
        for p in sorted(missions_dir.glob("*.json")):
            if p.name not in listed:
                out.warn(p.name, "", "V-MIS-07", "exists in game/data/missions but is not listed in the manifest (it will not be loaded)")
    return out


def schema_text() -> str:
    return SCHEMA_TEXT.strip("\n")


def gd_schema_block() -> str:
    """The schema block of the GDScript compiler's header comment (for the consistency test), '' when it cannot be read."""
    try:
        lines = PARSER_GD.read_text(encoding="utf-8").split("\n")
    except OSError:
        return ""
    out: list[str] = []
    on = False
    for ln in lines:
        if ln.startswith("## ==== THE MISSION JSON SCHEMA"):
            on = True
            continue
        if on and ln.startswith("## Rule ids:"):
            break
        if on:
            out.append(ln[3:] if ln.startswith("## ") else ln[2:])
    return "\n".join(out).strip("\n")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("files", nargs="*", help="mission files (default: every file the manifest lists)")
    ap.add_argument("--schema", action="store_true", help="print the exact JSON schema and exit")
    ap.add_argument("--strict", action="store_true", help="warnings also fail (exit 2)")
    args = ap.parse_args(argv)
    if args.schema:
        print(schema_text())
        return 0
    only = [Path(f) for f in args.files] or None
    out = check_all(only=only)
    for line in out.errors:
        print("ERROR " + line)
    for line in out.warnings:
        print("WARN  " + line)
    n = len(only) if only else len(json.loads((BALANCE / "manifest.json").read_text(encoding="utf-8")).get("missions", []))
    print(f"validate_missions: {len(out.errors)} error(s), {len(out.warnings)} warning(s), {n} mission file(s)")
    if out.errors:
        return 1
    return 2 if args.strict and out.warnings else 0


if __name__ == "__main__":
    sys.exit(main())
