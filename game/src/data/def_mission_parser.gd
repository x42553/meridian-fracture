class_name DefMissionParser
extends RefCounted
## Compiles one mission JSON (schema meridian.mission/1) into a DefMission and validates it (rule ids V-MIS-*). Instance-based:
## DefMissionParser.parse(raw, file, data, rep). Conditions / actions are compiled by DefMissionScript.
##
## ==== THE MISSION JSON SCHEMA (identical to `python3 tools/py/validate_missions.py --schema`) ====
##
## MERIDIAN MISSION FILE  meridian.mission/1   (game/data/missions/<id>.json; listed in game/data/balance/manifest.json "missions")
##
## Conventions: every number is an integer (JSON ints). Unknown keys are errors (typos). Ids are lowercase [a-z][a-z0-9_]*
## (max 40 chars; the file name is <id>.json). Lists marked "sorted" are stored sorted by id at load; the manifest "missions"
## list must be sorted ascending and unique. Seconds -> ticks at 20 TPS. Cells are map cells (1 cell = 1024 sub-cell units).
## Texts (title, briefing, message text, objective text) never enter the data hash; everything else does.
##
## TOP LEVEL
##   schema      "meridian.mission/1"                                  required
##   id          mission id; must equal the file name without .json    required
##   title       string 1..60                                          required
##   group       lowercase word, e.g. "tutorial" | "operation" | "demo" (default "custom")
##   order       int 0..9999, menu order inside the group (default 0)
##   briefing    [ {heading?: string, text: string, lore?: bible id} ]  lore = a bible id (faction.x, unit.x, structure.x,
##               roster.x, research.x, power.x, superweapon.x) shown as a Field Manual link
##   map         {family, size, seed, params?}                         required
##                 family  "open"|"urban"|"coast" (or 0|1|2)
##                 size    96..256, multiple of 8, >= the minimum of the start layout (2 players 96, 3-4 128, 5-6 160, 7-8 192)
##                 seed    0..4294967295 (the generator is deterministic per seed)
##                 params  {water_pct 0..40, density 0..100, resources 0..100, neutrals 0..100, biome 0..2, start_near_water bool}
##   sim_seed    0..4294967295 simulation RNG seed (default = map.seed)
##   rules       overrides of the match rules: start_credits 0..100000, unit_cap 20..500, superweapons, fog, shared_vision,
##               veterancy, neutral_structures, end_when_no_humans (bool or 0/1), vision_stride 1..4, vision_budget 16..512,
##               victory 0|1 (default 0 in missions: nobody is eliminated for lacking assets; the script decides),
##               allow_debug 0|1. start_mode cannot be set (the mission places the starts itself).
##   players     [ player ]  1..8, exactly one with kind "human"         required
##   areas       [ area ]    0..64
##   messages    [ message ] 0..128
##   objectives  [ objective ] 0..64 (declaration order = index shown in the UI)
##   timers      [ timer ]   0..16
##   triggers    [ trigger ] 0..128 (evaluated in ascending id order)
##
## PLAYER
##   slot        pid 0..7 (unique)                                      required
##   kind        "human" | "ai"                                         required
##   name        label, ascii letters digits space - _ (max 20; default "Commander" / "Hostiles")
##   roster      roster id from the bible, e.g. "roster.napc.vanilla"   required
##   team        1..4 (players of one team are allies)                  required
##   color       0..11 (unique; default = slot)
##   start_slot  0..7, the map spawn slot the player's HQ / areas anchor to (unique; default = slot)
##   credits     0..100000 (default rules.start_credits)
##   handicap    50..200, multiple of 5 (default 100)
##   ai          {level 0..15 (default 1), style 0..15 (default 0), active bool (default true), aggression 0..100 (default 50)}
##               only for kind "ai". active=false: the AI issues no commands until a change_ai action turns it on. A level or style
##               above what the AI module offers is clamped when the match is created (the file may name 0..15).
##   start       {mode, units?, structures?}
##                 mode  "hq" (deployed HQ on the start slot) | "mcv" (MCV instead) | "none" (default "hq")
##                 units       [ {def: unit id, count 1..32 (default 1), dx, dy: cells from the start cell (default 0, 0)} ]
##                 structures  [ {def: structure id, dx, dy, id?: placed id} ]   free (no cost), active at tick 0
##
## AREA  (cells; the anchor makes a mission independent of the generated terrain)
##   id, shape "circle" | "rect", anchor "abs" (default) | "map" | "start:<slot>"
##   circle: x, y, r (0..128; r 0 = the single cell)      rect: x, y, w, h (1..128; x, y = top-left)
##   x, y mean: abs = map cell; map = permille of the map width / height (0..1000); start:N = signed cell offset from the
##   start cell of player slot N. An entity is "in" an area when the cell it stands on is inside (circle: dx*dx+dy*dy <= r*r).
##   Areas are clamped to the map.
##
## MESSAGE   {id, text: string 1..400, speaker?: string, announcer?: announcer line id from data/audio/announcer.json}
## OBJECTIVE {id, kind "primary"|"secondary"|"hidden", text: string 1..200, initial "active"|"hidden"|"completed"|"failed"}
##           (default initial: "active"; kind hidden requires initial "hidden")
## TIMER     {id, seconds 1..36000, repeat bool (default false), autostart bool (default false), label?: string}
##
## TRIGGER   {id, once (default true), enabled (default true), edge (default false), cooldown_s (default 0), when: COND, then: [ACTION]}
##   Every 5th tick (tick % 5 == 0) each enabled trigger is evaluated in id order; if `when` is true it runs its actions (1..32), in
##   order. once=true: fires one time, then stays disabled. once=false: fires on every evaluation where `when` is true, but no
##   more often than cooldown_s; edge=true: only when `when` turned true since the last evaluation. Actions may enable / disable
##   triggers (a trigger_enable on a fired once-trigger re-arms it).
##
## OWNER SELECTORS (owner / to / from)  an int slot | "neutral" | "all" | "team:N" | "enemies_of:S" | "allies_of:S" (S = slot)
##   Counts and credits sum over the selected players; "defeated" / "no_assets" need ALL of them. Actions that create or
##   change things need ONE player (int slot) or, where stated, "neutral".
##
## COND  combinators: {all: [COND...]}  {any: [COND...]}  {not: COND}   (depth <= 8, <= 64 nodes)
##   cmp is one of ">=" "<=" "==" ">" "<" "!=" (default ">=")
##   {kind:"time", cmp?, seconds | ticks}                   world time compared with the value
##   {kind:"timer", timer}                                  the timer has expired (stays true until it is started again)
##   {kind:"objective", objective, state}                   state: "hidden"|"active"|"completed"|"failed"
##   {kind:"count", owner, of?: "unit"|"structure"|"any", def?, tag?, area?, cmp?, value}
##                  number of live entities of the owner; def = unit or structure id (of is inferred from the id prefix);
##                  tag = a unit tag (of unit) or structure tag (of structure); area = only entities standing inside
##                  (units that are transported are not "in" any area). Default of: "unit".
##   {kind:"structure", state, owner?, def?, placed?}       state: "exists" | "powered" (owner + def, or a placed id)
##                                                          | "destroyed" | "captured" (placed id only; captured: the
##                                                          structure is alive and its owner differs from its first owner)
##   {kind:"area_left", owner, area, def?, tag?}            the owner had units in the area earlier and has none now
##   {kind:"credits", owner, cmp?, value}
##   {kind:"research", owner, research: research id}        researched by the player
##   {kind:"power", owner, cmp?, value}                     supply minus demand, e.g. {cmp ">=", value 0}
##   {kind:"support_power", owner, slot 0..2, state}        state: "ready" (unlocked, cooldown over) | "used" (used at least once)
##   {kind:"superweapon", owner, state}                     state: "fired" (launched at least once) | "ready"
##   {kind:"defeated", owner}                               every selected player is eliminated
##   {kind:"no_assets", owner}                              every selected player has no structure and no MCV
##   {kind:"wave", wave, state}                             state: "spawned" | "cleared" (spawned and all its units dead)
##   {kind:"trigger", trigger, cmp?, value}                 how often that trigger has fired (default >= 1)
##
## ACTION  {do: <name>, ...}
##   set_objective   {objective, state}
##   show_message    {message, announcer?}                  announcer overrides the message's own line
##   timer_start     {timer, seconds?}                      (re)starts; seconds overrides the duration
##   timer_stop      {timer}
##   spawn_units     {owner, def: unit id, count?, area, wave?: wave id, order?: {kind, area?}, facing?}
##                   owner: slot | "neutral". Units appear on free cells around the centre of the area. order kinds:
##                   "move" | "attack_move" | "guard" (each needs area) | "hold".
##   spawn_structure {owner, def: structure id, area | cell: [x, y], id?: placed id, facing?: 0..3}
##                   owner: slot | "neutral". Placed free and active; the footprint origin (top-left cell) is the area
##                   centre or the cell, moved to the nearest buildable spot (<= 6 cells). `id` names it for conditions.
##   give_credits    {owner: slot, amount: -100000..100000}  (negative takes at most what the player has)
##   grant_power     {owner: slot, slot 0..2}            clears a lock / the cooldown (prerequisite structures still apply)
##   lock_power      {owner: slot, slot 0..2}            the power cannot be used until granted
##   reveal_area     {owner: slot | "team:N", area, seconds? (default 10)}   the area becomes explored and visible meanwhile
##   change_ai       {owner: slot (an AI player), active?, level?, style?, aggression?}
##   transfer        {to: slot | "neutral", placed | (owner, area?, def?, tag?, of?)}  new owner of a placed structure or of
##                   every matching live entity
##   destroy         {placed | (owner, area?, def?, tag?, of?)}
##   order_units     {owner: slot | "team:N", area?, def?, tag?, order: {kind, area?}}   units of the owner (inside `area`)
##   eliminate       {owner: slot}                          eliminates the player (its assets die)
##   trigger_enable  {trigger}      trigger_disable {trigger}
##   win             {owner: slot}                          ends the mission: that player's team wins
##   lose            {owner: slot}                          ends the mission: that player is defeated
##   camera_hint     {area | cell: [x, y], seconds? (default 5)}   UI-only
##   music_state     {state: "auto"|"calm"|"combat"|"tense"|"victory"|"defeat"}   UI-only
##   (Not included in v1: hiding an area again, power / knob overrides.)
##
## Rule ids: V-MIS-01 file / schema / id, V-MIS-02 field type or range, V-MIS-03 unknown reference, V-MIS-04 duplicate id,
## V-MIS-05 structure of a condition / action, V-MIS-06 players / map / layout.

const MAX_PLAYERS: int = 8
const MAX_AREAS: int = 64
const MAX_MESSAGES: int = 128
const MAX_OBJECTIVES: int = 64
const MAX_TIMERS: int = 16
const MAX_TRIGGERS: int = 128
const MAX_ACTIONS: int = 32
const MAX_WAVES: int = 32
const MAX_PLACED: int = 64
const LAYOUTS: PackedInt32Array = [2, 4, 6, 8]
## MapGenParams.min_size(layout) copied (data may not name map classes); tests assert equality.
const MIN_SIZE: Dictionary = {2: 96, 4: 128, 6: 160, 8: 192}
## SimMatchRules fields a mission may override: name -> [min, max]; copied (data may not name sim classes); tests assert equality.
const RULE_RANGES: Dictionary = {
	"start_credits": [0, 100000], "unit_cap": [20, 500], "superweapons": [0, 1], "fog": [0, 1], "shared_vision": [0, 1],
	"veterancy": [0, 1], "vision_stride": [1, 4], "vision_budget": [16, 512], "neutral_structures": [0, 1], "victory": [0, 1],
	"end_when_no_humans": [0, 1], "allow_debug": [0, 1],
}
const TOP_KEYS: PackedStringArray = ["schema", "id", "title", "group", "order", "briefing", "map", "sim_seed", "rules", "players", "areas",
	"messages", "objectives", "timers", "triggers"]
const FAMILY_NAMES: PackedStringArray = ["open", "urban", "coast"]
const SCHEMA: String = "meridian.mission/1"

var rep: DefLoadReport = null
var data: GameData = null
var file: String = ""
var m: DefMission = null
var area_ix: Dictionary = {}
var msg_ix: Dictionary = {}
var obj_ix: Dictionary = {}
var timer_ix: Dictionary = {}
var trig_ix: Dictionary = {}
var wave_ix: Dictionary = {}
var placed_ix: Dictionary = {}
var slots: Dictionary = {}  ## pid -> DefMissionPlayer
var team_of_slot: Dictionary = {}


## null (errors in `rep`) when the mission is invalid.
static func parse(raw: Dictionary, file_name: String, game_data: GameData, report: DefLoadReport) -> DefMission:
	var p: DefMissionParser = DefMissionParser.new()
	p.rep = report
	p.data = game_data
	p.file = file_name
	var before: int = report.errors.size()
	var out: DefMission = p._build(raw)
	return out if report.errors.size() == before else null


# ---------------------------------------------------------------------------------------------------- helpers
func fail(rule: String, where: String, msg: String) -> void:
	rep.error(rule, "%s %s" % [file, where] if where != "" else file, msg)


func check_keys(d: Dictionary, allowed: PackedStringArray, where: String) -> void:
	for k: Variant in d.keys():
		if not allowed.has(str(k)):
			fail("V-MIS-02", where, "unknown key '%s' (allowed: %s)" % [str(k), ", ".join(allowed)])


static func id_ok(s: String) -> bool:
	if s.length() < 1 or s.length() > 40:
		return false
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		var ok: bool = (c >= 97 and c <= 122) or (i > 0 and ((c >= 48 and c <= 57) or c == 95))
		if not ok:
			return false
	return true


## Player names must survive NetProtocol.sanitize_name unchanged (the net config refuses a name it would rewrite).
static func name_ok(s: String) -> bool:
	if s.is_empty() or s.begins_with(" ") or s.ends_with(" "):
		return false
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 32 or c == 45 or c == 95):
			return false
	return true


## Integer field with range; `required` reports a missing key, otherwise `dflt` is returned.
func int_of(d: Dictionary, key: String, lo: int, hi: int, dflt: int, where: String, required: bool = false) -> int:
	if not d.has(key):
		if required:
			fail("V-MIS-02", where, "missing required field '%s'" % key)
		return dflt
	var v: Variant = d[key]
	if not DefNumParse.is_integral(v):
		fail("V-MIS-02", where, "'%s' must be an integer" % key)
		return dflt
	var n: int = DefNumParse.whole(v, where + "." + key, rep)
	if n < lo or n > hi:
		fail("V-MIS-02", where, "'%s' = %d is outside %d..%d" % [key, n, lo, hi])
		return dflt
	return n


func str_of(d: Dictionary, key: String, min_len: int, max_len: int, dflt: String, where: String, required: bool = false) -> String:
	if not d.has(key):
		if required:
			fail("V-MIS-02", where, "missing required field '%s'" % key)
		return dflt
	var v: Variant = d[key]
	if not (v is String):
		fail("V-MIS-02", where, "'%s' must be a string" % key)
		return dflt
	var s: String = v
	if s.length() < min_len or s.length() > max_len:
		fail("V-MIS-02", where, "'%s' must have %d..%d characters" % [key, min_len, max_len])
		return dflt
	return s


func bool_of(d: Dictionary, key: String, dflt: bool, where: String) -> bool:
	if not d.has(key):
		return dflt
	var v: Variant = d[key]
	if v is bool:
		return v
	if DefNumParse.is_integral(v):
		var n: int = DefNumParse.whole(v, where, rep)
		if n == 0 or n == 1:
			return n == 1
	fail("V-MIS-02", where, "'%s' must be a boolean (or 0 / 1)" % key)
	return dflt


## Seconds or ticks of an object ("seconds" xor "ticks"); -1 when neither is present.
func ticks_of(d: Dictionary, where: String, lo: int, hi: int) -> int:
	var has_s: bool = d.has("seconds")
	var has_t: bool = d.has("ticks")
	if has_s and has_t:
		fail("V-MIS-05", where, "give either 'seconds' or 'ticks', not both")
		return -1
	if has_s:
		var s: int = int_of(d, "seconds", lo, hi, -1, where)
		return s * SimConfig.TPS if s >= 0 else -1
	if has_t:
		return int_of(d, "ticks", lo * SimConfig.TPS, hi * SimConfig.TPS, -1, where)
	return -1


## Index lookup in an id -> index dictionary; reports V-MIS-03 and returns -1.
func ref_of(table: Dictionary, what: String, key: String, d: Dictionary, where: String, required: bool = true) -> int:
	if not d.has(key):
		if required:
			fail("V-MIS-02", where, "missing required field '%s'" % key)
		return -1
	var id: String = str(d[key])
	if not table.has(id):
		fail("V-MIS-03", where, "unknown %s '%s'" % [what, id])
		return -1
	return int(table[id])


## Player selector -> PackedInt32Array [mode, val] (DefMissionCond.OWN_*), empty after an error.
## `single`: only one player ("neutral" allowed when `allow_neutral`).
func owner_sel(v: Variant, where: String, single: bool, allow_neutral: bool) -> PackedInt32Array:
	var bad: PackedInt32Array = PackedInt32Array()
	if DefNumParse.is_number(v):
		if not DefNumParse.is_integral(v):
			fail("V-MIS-02", where, "player slot must be an integer")
			return bad
		var pid: int = DefNumParse.whole(v, where, rep)
		if not slots.has(pid):
			fail("V-MIS-03", where, "unknown player slot %d" % pid)
			return bad
		return PackedInt32Array([DefMissionCond.OWN_PID, pid])
	if not (v is String):
		fail("V-MIS-02", where, "owner must be a slot number or a selector string")
		return bad
	var s: String = v
	if s == "neutral":
		if not allow_neutral:
			fail("V-MIS-05", where, "'neutral' is not allowed here")
			return bad
		return PackedInt32Array([DefMissionCond.OWN_NEUTRAL, -1])
	if single:
		fail("V-MIS-05", where, "this field needs exactly one player slot%s" % (" or \"neutral\"" if allow_neutral else ""))
		return bad
	if s == "all":
		return PackedInt32Array([DefMissionCond.OWN_ALL, 0])
	var parts: PackedStringArray = s.split(":")
	if parts.size() == 2 and parts[1].is_valid_int():
		var n: int = parts[1].to_int()
		match parts[0]:
			"team":
				if n >= 1 and n <= 4:
					return PackedInt32Array([DefMissionCond.OWN_TEAM, n])
			"enemies_of":
				if slots.has(n):
					return PackedInt32Array([DefMissionCond.OWN_ENEMIES_OF, n])
			"allies_of":
				if slots.has(n):
					return PackedInt32Array([DefMissionCond.OWN_ALLIES_OF, n])
	fail("V-MIS-02", where, "bad owner selector '%s' (slot | neutral | all | team:N | enemies_of:S | allies_of:S)" % s)
	return bad


# ---------------------------------------------------------------------------------------------------- build
func _build(raw: Dictionary) -> DefMission:
	m = DefMission.new()
	m.kind = DefEnums.Kind.COUNT  # not a table kind
	check_keys(raw, TOP_KEYS, "")
	if str(raw.get("schema", "")) != SCHEMA:
		fail("V-MIS-01", "schema", "must be \"%s\"" % SCHEMA)
	m.id = str_of(raw, "id", 1, 40, "", "", true)
	if m.id != "" and not id_ok(m.id):
		fail("V-MIS-01", "id", "'%s' is not a valid id (lowercase [a-z][a-z0-9_]*, max 40)" % m.id)
	if m.id != "" and file != m.id + ".json":
		fail("V-MIS-01", "id", "id '%s' does not match the file name '%s'" % [m.id, file])
	m.ui_title = str_of(raw, "title", 1, 60, "", "", true)
	m.group = str_of(raw, "group", 1, 24, "custom", "")
	if not id_ok(m.group):
		fail("V-MIS-02", "group", "'%s' is not a lowercase word" % m.group)
	m.order = int_of(raw, "order", 0, 9999, 0, "")
	_briefing(raw)
	_collect_ids(raw)
	_players(raw)
	_map(raw)
	_rules(raw)
	_areas(raw)
	_messages(raw)
	_objectives(raw)
	_timers(raw)
	var script: DefMissionScript = DefMissionScript.new(self)
	script.parse_triggers(raw.get("triggers", []))
	m.waves = _sorted_keys(wave_ix)
	m.placed = _sorted_keys(placed_ix)
	_announcers()
	return m


## Distinct announcer line ids (sorted) -> indices carried by MISSION_MESSAGE events.
func _announcers() -> void:
	var set: Dictionary = {}
	for mm: DefMissionMessage in m.messages:
		if mm.announcer != "":
			set[mm.announcer] = true
	for t: DefMissionTrigger in m.triggers:
		for a: DefMissionAction in t.then:
			if a.op == DefMissionAction.Op.SHOW_MESSAGE and a.announcer != "":
				set[a.announcer] = true
	m.announcers = _sorted_keys(set)
	for mm: DefMissionMessage in m.messages:
		mm.announcer_idx = m.announcers.find(mm.announcer) if mm.announcer != "" else -1
	for t: DefMissionTrigger in m.triggers:
		for a: DefMissionAction in t.then:
			if a.op == DefMissionAction.Op.SHOW_MESSAGE:
				a.value = m.announcers.find(a.announcer) if a.announcer != "" else -1


func _sorted_keys(dct: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in dct.keys():
		out.append(str(k))
	out.sort()
	return out


func _list(raw: Dictionary, key: String, max_n: int) -> Array:
	var v: Variant = raw.get(key, [])
	if not (v is Array):
		fail("V-MIS-02", key, "must be an array")
		return []
	var a: Array = v
	if a.size() > max_n:
		fail("V-MIS-02", key, "has %d entries, at most %d" % [a.size(), max_n])
		return []
	return a


func entry(v: Variant, where: String) -> Dictionary:
	if v is Dictionary:
		return v
	fail("V-MIS-02", where, "must be an object")
	return {}


func _briefing(raw: Dictionary) -> void:
	var lore_prefixes: PackedStringArray = ["faction.", "unit.", "structure.", "roster.", "research.", "power.", "superweapon."]
	var arr: Array = _list(raw, "briefing", 32)
	for i: int in arr.size():
		var w: String = "briefing[%d]" % i
		var d: Dictionary = entry(arr[i], w)
		check_keys(d, ["heading", "text", "lore"], w)
		var lore: String = str_of(d, "lore", 0, 80, "", w)
		if lore != "":
			var ok: bool = false
			for pre: String in lore_prefixes:
				ok = ok or lore.begins_with(pre)
			if not ok:
				fail("V-MIS-03", w, "lore '%s' is not a bible id" % lore)
		m.ui_briefing.append({"heading": str_of(d, "heading", 0, 80, "", w), "text": str_of(d, "text", 1, 2000, "", w, true), "lore": lore})


## Pass 1: ids that conditions / actions reference before they are parsed (waves, placed structures, triggers, players).
func _collect_ids(raw: Dictionary) -> void:
	var counts: Dictionary = {}
	var plist: Variant = raw.get("players", [])
	var plist_a: Array = plist if plist is Array else []
	for pv: Variant in plist_a:
		if not (pv is Dictionary):
			continue
		var st: Variant = (pv as Dictionary).get("start", {})
		if not (st is Dictionary):
			continue
		var sl: Variant = (st as Dictionary).get("structures", [])
		var sl_a: Array = sl if sl is Array else []
		for sv: Variant in sl_a:
			if sv is Dictionary and (sv as Dictionary).has("id"):
				_count_id(counts, "placed:" + str((sv as Dictionary)["id"]))
	var trig_ids: PackedStringArray = PackedStringArray()
	var trigs: Variant = raw.get("triggers", [])
	if trigs is Array:
		for tv: Variant in trigs as Array:
			if not (tv is Dictionary):
				continue
			var td: Dictionary = tv
			trig_ids.append(str(td.get("id", "")))
			var acts: Variant = td.get("then", [])
			if not (acts is Array):
				continue
			for av: Variant in acts as Array:
				if not (av is Dictionary):
					continue
				var ad: Dictionary = av
				if str(ad.get("do", "")) == "spawn_structure" and ad.has("id"):
					_count_id(counts, "placed:" + str(ad["id"]))
				elif str(ad.get("do", "")) == "spawn_units" and ad.has("wave"):
					wave_ix[str(ad["wave"])] = 0
	for k: Variant in counts.keys():
		if int(counts[k]) > 1:
			fail("V-MIS-04", "placed", "placed id '%s' is declared %d times" % [str(k).substr(7), int(counts[k])])
		placed_ix[str(k).substr(7)] = 0
	trig_ids.sort()
	for i: int in trig_ids.size():
		if i > 0 and trig_ids[i] == trig_ids[i - 1]:
			fail("V-MIS-04", "triggers", "duplicate trigger id '%s'" % trig_ids[i])
		trig_ix[trig_ids[i]] = i
	var keys: PackedStringArray = _sorted_keys(wave_ix)
	if keys.size() > MAX_WAVES:
		fail("V-MIS-02", "waves", "more than %d waves" % MAX_WAVES)
	for i: int in keys.size():
		wave_ix[keys[i]] = i
		if not id_ok(keys[i]):
			fail("V-MIS-02", "wave", "bad wave id '%s'" % keys[i])
	var pk: PackedStringArray = _sorted_keys(placed_ix)
	if pk.size() > MAX_PLACED:
		fail("V-MIS-02", "placed", "more than %d placed structures" % MAX_PLACED)
	for i: int in pk.size():
		placed_ix[pk[i]] = i
		if not id_ok(pk[i]):
			fail("V-MIS-02", "placed", "bad placed id '%s'" % pk[i])


func _count_id(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1


func _players(raw: Dictionary) -> void:
	var arr: Array = _list(raw, "players", MAX_PLAYERS)
	if arr.is_empty():
		fail("V-MIS-06", "players", "a mission needs 1..8 players")
	var humans: int = 0
	var colors: Dictionary = {}
	var starts: Dictionary = {}
	var parsed: Array[DefMissionPlayer] = []
	# slots first: selectors in the player list itself do not exist, but areas / scripts need the table
	for i: int in arr.size():
		var d: Dictionary = entry(arr[i], "players[%d]" % i)
		var slot: int = int_of(d, "slot", 0, 7, -1, "players[%d]" % i, true)
		if slot >= 0:
			if slots.has(slot):
				fail("V-MIS-04", "players[%d]" % i, "duplicate slot %d" % slot)
			var pl: DefMissionPlayer = DefMissionPlayer.new()
			pl.slot = slot
			slots[slot] = pl
			parsed.append(pl)
			_player_fields(pl, d, i)
			if pl.human:
				humans += 1
			if colors.has(pl.color):
				fail("V-MIS-04", "players[%d]" % i, "duplicate color %d" % pl.color)
			colors[pl.color] = true
			if starts.has(pl.start_slot):
				fail("V-MIS-04", "players[%d]" % i, "duplicate start_slot %d" % pl.start_slot)
			starts[pl.start_slot] = true
			team_of_slot[slot] = pl.team
	if not arr.is_empty() and humans != 1:
		fail("V-MIS-06", "players", "exactly one player must have kind \"human\" (found %d)" % humans)
	parsed.sort_custom(func(a: DefMissionPlayer, b: DefMissionPlayer) -> bool: return a.slot < b.slot)
	m.players = parsed
	var need: int = parsed.size()
	for p: DefMissionPlayer in parsed:
		need = maxi(need, p.start_slot + 1)
	m.layout_players = 0
	for l: int in LAYOUTS:
		if l >= need:
			m.layout_players = l
			break
	if m.layout_players == 0:
		fail("V-MIS-06", "players", "start slots need a layout of more than 8 players")
		m.layout_players = 8


func _player_fields(pl: DefMissionPlayer, d: Dictionary, i: int) -> void:
	var w: String = "players[%d]" % i
	check_keys(d, ["slot", "kind", "name", "roster", "team", "color", "start_slot", "credits", "handicap", "ai", "start"], w)
	var kind: String = str_of(d, "kind", 2, 5, "", w, true)
	if kind != "human" and kind != "ai":
		fail("V-MIS-02", w, "kind must be \"human\" or \"ai\"")
	pl.human = kind == "human"
	pl.ui_name = str_of(d, "name", 1, 20, "Commander" if pl.human else "Hostiles", w)
	if not name_ok(pl.ui_name):
		fail("V-MIS-02", w, "name '%s' may only use letters, digits, space, - and _ (no space at either end)" % pl.ui_name)
	pl.roster = str_of(d, "roster", 1, 40, "", w, true)
	pl.roster_idx = data.roster_idx(pl.roster) if pl.roster != "" else -1
	if pl.roster != "" and pl.roster_idx < 0:
		fail("V-MIS-03", w, "unknown roster '%s'" % pl.roster)
	pl.team = int_of(d, "team", 1, 4, 1, w, true)
	pl.color = int_of(d, "color", 0, 11, pl.slot, w)
	pl.start_slot = int_of(d, "start_slot", 0, 7, pl.slot, w)
	pl.credits = int_of(d, "credits", 0, 100000, -1, w)
	pl.handicap = int_of(d, "handicap", 50, 200, 100, w)
	if pl.handicap % 5 != 0:
		fail("V-MIS-02", w, "handicap must be a multiple of 5")
	if d.has("ai"):
		if pl.human:
			fail("V-MIS-05", w, "'ai' is only for kind \"ai\"")
		else:
			var ad: Dictionary = entry(d["ai"], w + ".ai")
			check_keys(ad, ["level", "style", "active", "aggression"], w + ".ai")
			pl.ai_level = int_of(ad, "level", 0, 15, 1, w + ".ai")
			pl.ai_style = int_of(ad, "style", 0, 15, 0, w + ".ai")
			pl.ai_active = bool_of(ad, "active", true, w + ".ai")
			pl.ai_aggr = int_of(ad, "aggression", 0, 100, 50, w + ".ai")
	if d.has("start"):
		_start(pl, entry(d["start"], w + ".start"), w + ".start")


func _start(pl: DefMissionPlayer, d: Dictionary, w: String) -> void:
	check_keys(d, ["mode", "units", "structures"], w)
	var mode: String = str_of(d, "mode", 2, 4, "hq", w)
	var modes: PackedStringArray = ["hq", "mcv", "none"]
	if not modes.has(mode):
		fail("V-MIS-02", w, "mode must be hq, mcv or none")
	pl.start_mode = maxi(modes.find(mode), 0)
	for kind_i: int in 2:
		var key: String = "units" if kind_i == 0 else "structures"
		var arr: Array = d.get(key, []) if d.get(key, []) is Array else []
		if d.has(key) and not (d[key] is Array):
			fail("V-MIS-02", w, "'%s' must be an array" % key)
		if arr.size() > 32:
			fail("V-MIS-02", w, "'%s' has more than 32 entries" % key)
		for j: int in arr.size():
			var ww: String = "%s.%s[%d]" % [w, key, j]
			var e: Dictionary = entry(arr[j], ww)
			check_keys(e, ["def", "count", "dx", "dy", "id"] if kind_i == 1 else ["def", "count", "dx", "dy"], ww)
			var def_id: String = str_of(e, "def", 1, 80, "", ww, true)
			var di: int = -1
			if def_id != "":
				di = data.unit_idx(def_id) if kind_i == 0 else data.structure_idx(def_id)
				if di < 0:
					fail("V-MIS-03", ww, "unknown %s '%s'" % ["unit" if kind_i == 0 else "structure", def_id])
			pl.start_kinds.append(kind_i)
			pl.start_def_idx.append(di)
			pl.start_count.append(int_of(e, "count", 1, 32, 1, ww) if kind_i == 0 else 1)
			pl.start_dx.append(int_of(e, "dx", -64, 64, 0, ww))
			pl.start_dy.append(int_of(e, "dy", -64, 64, 0, ww))
			pl.start_placed.append(int(placed_ix.get(str(e["id"]), -1)) if e.has("id") else -1)


func _map(raw: Dictionary) -> void:
	var d: Dictionary = entry(raw.get("map", null), "map")
	if not raw.has("map"):
		fail("V-MIS-02", "map", "missing required field 'map'")
	check_keys(d, ["family", "size", "seed", "params"], "map")
	var fam: Variant = d.get("family", 0)
	if fam is String and FAMILY_NAMES.has(fam):
		m.map_family = FAMILY_NAMES.find(fam)
	elif DefNumParse.is_integral(fam) and DefNumParse.whole(fam, "map.family", rep) >= 0 and DefNumParse.whole(fam, "map.family", rep) <= 2:
		m.map_family = DefNumParse.whole(fam, "map.family", rep)
	else:
		fail("V-MIS-02", "map", "family must be open, urban, coast (or 0..2)")
	m.map_size = int_of(d, "size", 96, 256, 128, "map", true)
	if m.map_size % 8 != 0:
		fail("V-MIS-06", "map", "size must be a multiple of 8")
	if MIN_SIZE.has(m.layout_players) and m.map_size < int(MIN_SIZE[m.layout_players]):
		fail("V-MIS-06", "map", "size %d is below the minimum %d of a %d-slot layout" % [m.map_size, int(MIN_SIZE[m.layout_players]), m.layout_players])
	m.map_seed = int_of(d, "seed", 0, 0xFFFFFFFF, 1, "map", true)
	m.sim_seed = int_of(raw, "sim_seed", 0, 0xFFFFFFFF, m.map_seed, "")
	if d.has("params"):
		var pd: Dictionary = entry(d["params"], "map.params")
		check_keys(pd, ["water_pct", "density", "resources", "neutrals", "biome", "start_near_water"], "map.params")
		var ranges: Dictionary = {"water_pct": [0, 40], "density": [0, 100], "resources": [0, 100], "neutrals": [0, 100], "biome": [0, 2]}
		for k: String in ranges.keys():
			if pd.has(k):
				m.map_params[k] = int_of(pd, k, int((ranges[k] as Array)[0]), int((ranges[k] as Array)[1]), 0, "map.params")
		if pd.has("start_near_water"):
			m.map_params["start_near_water"] = 1 if bool_of(pd, "start_near_water", false, "map.params") else 0


func _rules(raw: Dictionary) -> void:
	var d: Dictionary = entry(raw.get("rules", {}), "rules")
	var allowed: PackedStringArray = PackedStringArray(RULE_RANGES.keys())
	check_keys(d, allowed, "rules")
	m.rules["victory"] = 0
	for k: String in RULE_RANGES.keys():
		if not d.has(k):
			continue
		var rng: Array = RULE_RANGES[k]
		if d[k] is bool:
			m.rules[k] = 1 if d[k] else 0
		else:
			m.rules[k] = int_of(d, k, int(rng[0]), int(rng[1]), int(rng[0]), "rules")


func _areas(raw: Dictionary) -> void:
	var arr: Array = _list(raw, "areas", MAX_AREAS)
	for i: int in arr.size():
		var w: String = "areas[%d]" % i
		var d: Dictionary = entry(arr[i], w)
		var a: DefMissionArea = DefMissionArea.new()
		a.id = str_of(d, "id", 1, 40, "", w, true)
		if not id_ok(a.id):
			fail("V-MIS-01", w, "'%s' is not a valid id" % a.id)
		if area_ix.has(a.id):
			fail("V-MIS-04", w, "duplicate area id '%s'" % a.id)
		area_ix[a.id] = i
		var shape: String = str_of(d, "shape", 4, 6, "", w, true)
		if shape == "circle":
			a.shape = DefMissionArea.Shape.CIRCLE
			check_keys(d, ["id", "shape", "anchor", "x", "y", "r"], w)
			a.r = int_of(d, "r", 0, 128, 0, w, true)
		elif shape == "rect":
			a.shape = DefMissionArea.Shape.RECT
			check_keys(d, ["id", "shape", "anchor", "x", "y", "w", "h"], w)
			a.w = int_of(d, "w", 1, 128, 1, w, true)
			a.h = int_of(d, "h", 1, 128, 1, w, true)
		else:
			fail("V-MIS-02", w, "shape must be circle or rect")
		var anchor: String = str_of(d, "anchor", 3, 10, "abs", w)
		if anchor == "abs":
			a.anchor = DefMissionArea.Anchor.ABS
			a.x = int_of(d, "x", 0, 255, 0, w, true)
			a.y = int_of(d, "y", 0, 255, 0, w, true)
		elif anchor == "map":
			a.anchor = DefMissionArea.Anchor.MAP
			a.x = int_of(d, "x", 0, 1000, 0, w, true)
			a.y = int_of(d, "y", 0, 1000, 0, w, true)
		elif anchor.begins_with("start:") and anchor.substr(6).is_valid_int() and slots.has(anchor.substr(6).to_int()):
			a.anchor = DefMissionArea.Anchor.START
			a.anchor_pid = anchor.substr(6).to_int()
			a.x = int_of(d, "x", -255, 255, 0, w, true)
			a.y = int_of(d, "y", -255, 255, 0, w, true)
		else:
			fail("V-MIS-03", w, "anchor must be abs, map or start:<player slot> (got '%s')" % anchor)
		m.areas.append(a)


func _messages(raw: Dictionary) -> void:
	var arr: Array = _list(raw, "messages", MAX_MESSAGES)
	for i: int in arr.size():
		var w: String = "messages[%d]" % i
		var d: Dictionary = entry(arr[i], w)
		check_keys(d, ["id", "text", "speaker", "announcer"], w)
		var mm: DefMissionMessage = DefMissionMessage.new()
		mm.id = str_of(d, "id", 1, 40, "", w, true)
		if not id_ok(mm.id):
			fail("V-MIS-01", w, "'%s' is not a valid id" % mm.id)
		if msg_ix.has(mm.id):
			fail("V-MIS-04", w, "duplicate message id '%s'" % mm.id)
		msg_ix[mm.id] = i
		mm.ui_text = str_of(d, "text", 1, 400, "", w, true)
		mm.ui_speaker = str_of(d, "speaker", 0, 40, "", w)
		mm.announcer = str_of(d, "announcer", 0, 60, "", w)
		m.messages.append(mm)


func _objectives(raw: Dictionary) -> void:
	var arr: Array = _list(raw, "objectives", MAX_OBJECTIVES)
	for i: int in arr.size():
		var w: String = "objectives[%d]" % i
		var d: Dictionary = entry(arr[i], w)
		check_keys(d, ["id", "kind", "text", "initial"], w)
		var o: DefMissionObjective = DefMissionObjective.new()
		o.id = str_of(d, "id", 1, 40, "", w, true)
		if not id_ok(o.id):
			fail("V-MIS-01", w, "'%s' is not a valid id" % o.id)
		if obj_ix.has(o.id):
			fail("V-MIS-04", w, "duplicate objective id '%s'" % o.id)
		obj_ix[o.id] = i
		var kind: String = str_of(d, "kind", 1, 12, "", w, true)
		o.kind = DefMissionObjective.KIND_NAMES.find(kind)
		if o.kind < 0:
			fail("V-MIS-02", w, "kind must be primary, secondary or hidden")
			o.kind = 0
		o.ui_text = str_of(d, "text", 1, 200, "", w, true)
		var st: String = str_of(d, "initial", 1, 12, "hidden" if o.kind == DefMissionObjective.Kind.HIDDEN else "active", w)
		o.initial = DefMissionObjective.STATE_NAMES.find(st)
		if o.initial < 0:
			fail("V-MIS-02", w, "initial must be hidden, active, completed or failed")
			o.initial = 1
		if o.kind == DefMissionObjective.Kind.HIDDEN and o.initial != 0:
			fail("V-MIS-05", w, "a hidden objective must start hidden")
		m.objectives.append(o)


func _timers(raw: Dictionary) -> void:
	var arr: Array = _list(raw, "timers", MAX_TIMERS)
	for i: int in arr.size():
		var w: String = "timers[%d]" % i
		var d: Dictionary = entry(arr[i], w)
		check_keys(d, ["id", "seconds", "repeat", "autostart", "label"], w)
		var t: DefMissionTimer = DefMissionTimer.new()
		t.id = str_of(d, "id", 1, 40, "", w, true)
		if not id_ok(t.id):
			fail("V-MIS-01", w, "'%s' is not a valid id" % t.id)
		if timer_ix.has(t.id):
			fail("V-MIS-04", w, "duplicate timer id '%s'" % t.id)
		timer_ix[t.id] = i
		t.ticks = int_of(d, "seconds", 1, 36000, 1, w, true) * SimConfig.TPS
		t.repeat = bool_of(d, "repeat", false, w)
		t.autostart = bool_of(d, "autostart", false, w)
		t.ui_label = str_of(d, "label", 0, 40, "", w)
		m.timers.append(t)
