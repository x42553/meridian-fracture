class_name DefTestKit
extends RefCounted
## Test kit of the data domain (data_balance 11, DATA-11). Not shipped: lives under tests/.
##  * small_data()        a hand-made GameData (2 rosters, 6 units, 6 structures, 1 research, 1 power, 1 zone, 1 neutral) with
##                        NO file access, so headless sim tests can run before the real balance sheets land. Fully
##                        self-contained (its hash is pinned by tests/golden/data_hash.json).
##  * stub_balance()      generated stub `units_<code>.json` sheets for every bible unit of the 8 factions (numbers from the
##                        role archetypes of global.json), in the schema of data_balance 7.7.
##  * stub_sources() / stub_game_data()   bible + real global.json/ability_kinds.json/structures.json/units_shared.json
##                        from disk + stub sheets (+ empty schema shells for research/powers/zones/traits/neutrals when a
##                        file does not exist yet) => a complete DefSources for GameData.load_from_sources.

const BIBLE_PATH: String = "res://data/bible/meridian_factions.json"
const BALANCE_DIR: String = "res://data/balance"
const FACTION_CODES: PackedStringArray = ["ae", "def", "han", "napc", "nec", "olm", "pd", "sap"]
const _EMPTY_SHELLS: Dictionary = {
	"research_effects.json": ["meridian.balance.research_effects/1", "research"],
	"power_actions.json": ["meridian.balance.power_actions/1", "powers"],
	"zone_templates.json": ["meridian.balance.zone_templates/1", "zones"],
	"faction_traits.json": ["meridian.balance.faction_traits/1", "traits"],
	"neutral_structures.json": ["meridian.balance.neutral_structures/1", "neutrals"],
}

# ids of small_data()
const U_COLLECTOR: String = "unit.tst.collector"
const U_ENGINEER: String = "unit.tst.engineer"
const U_MCV: String = "unit.tst.mcv"
const U_RIFLEMAN: String = "unit.tst.rifleman"
const U_TANK: String = "unit.tst.tank"
const U_TANK2: String = "unit.tst.tank2"  ## replaces U_TANK in roster.tst.alpha
const S_BARRACKS: String = "structure.tst.barracks"
const S_FACTORY: String = "structure.tst.factory"
const S_GENERATOR: String = "structure.tst.generator"
const S_HQ: String = "structure.tst.hq"
const S_REFINERY: String = "structure.tst.refinery"
const S_TURRET: String = "structure.tst.turret"
const R_ALPHA: String = "roster.tst.alpha"
const R_VANILLA: String = "roster.tst.vanilla"

static var _json_cache: Dictionary = {}


# ------------------------------------------------------------------------------------------------ files
## Parsed JSON object of a res:// path (cached per process); {} when missing.
static func read_json(path: String) -> Dictionary:
	if _json_cache.has(path):
		return (_json_cache[path] as Dictionary).duplicate(true)
	var d: Dictionary = {}
	if FileAccess.file_exists(path):
		var p: JSON = JSON.new()
		if p.parse(FileAccess.get_file_as_string(path)) == OK and p.data is Dictionary:
			d = p.data
	_json_cache[path] = d
	return d.duplicate(true)


# ------------------------------------------------------------------------------------------- stub sheets
## {"units_<code>.json": sheet} for the 8 faction codes: every bible unit of a faction has exactly one entry, sorted by
## id, numbers from its `unit_assignments` role archetype in `g` (global.json); weapons are instances of the archetype's
## weapon list; abilities are the assignment's framework names (dropped when a required id-typed param cannot be stubbed).
static func stub_balance(bible: Dictionary, g: Dictionary, kinds: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var assign: Dictionary = g.get("unit_assignments", {})
	var archs: Dictionary = g.get("archetypes", {})
	var units: Dictionary = bible.get("units", {})
	var by_code: Dictionary = {}
	var ids: Array = units.keys()
	ids.sort()
	for id: String in ids:
		var e: Dictionary = units[id]
		var fid: Variant = e.get("faction_id")
		if fid == null:
			continue
		var code: String = str(fid).trim_prefix("faction.")
		if not by_code.has(code):
			by_code[code] = []
		(by_code[code] as Array).append(id)
	for code: String in FACTION_CODES:
		var sheet_units: Array = []
		var sheet_weapons: Array = []
		var sheet_summons: Array = []
		for id: String in by_code.get(code, []):
			var a: Dictionary = assign.get(id, {})
			var an: String = str(a.get("archetype", "mbt_t1"))
			var ar: Dictionary = archs.get(an, {})
			var short: String = id.get_slice(".", 2)
			var u: Dictionary = {"id": id, "archetype": an}
			for k: String in ["cost_credits", "build_time_s", "health", "speed_cells_s", "vision_cells", "radius_cells", "rearm_s_full"]:
				if ar.has(k):
					u[k] = ar[k]
			var wids: Array = []
			var wl: Array = ar.get("weapons", [])
			for wi: int in wl.size():
				var w: Dictionary = (wl[wi] as Dictionary).duplicate(true)
				w["id"] = "weapon.%s.%s_%d" % [code, short, wi]
				wids.append(w["id"])
				sheet_weapons.append(w)
			u["weapons"] = wids
			var ab: Array = []
			var params: Dictionary = {}
			for name: Variant in a.get("abilities", []):
				var need: Dictionary = _stub_ability_params(str(name), kinds)
				if need.get("ok", false):
					ab.append(str(name))
					if not (need["params"] as Dictionary).is_empty():
						params[str(name)] = need["params"]
			if an == "ship_carrier":
				var drone_id: String = "summon.%s.%s_drone" % [code, short]
				sheet_summons.append(_stub_drone(drone_id, g, code, short, sheet_weapons))
				params["ability.carrier.default"] = {"wings": [{"id": "wing_a", "drone_id": drone_id, "wing_size_n": 6}]}
			u["abilities"] = ab
			if not params.is_empty():
				u["ability_params"] = params
			sheet_units.append(u)
		out["units_%s.json" % code] = {
			"schema": "meridian.balance.units/1", "faction": "faction." + code,
			"units": sheet_units, "weapons": _sorted_by_id(sheet_weapons), "summons": sheet_summons,
		}
	return out


## Whether `name` (framework alias or template id) can be stubbed and the params to add so every required one exists.
static func _stub_ability_params(name: String, kinds: Dictionary) -> Dictionary:
	var aliases: Dictionary = kinds.get("aliases", {})
	var templates: Dictionary = kinds.get("templates", {})
	var tid: String = name if name.begins_with("ability.") else str(aliases.get(name, ""))
	if tid == "" or not templates.has(tid):
		return {"ok": aliases.has(name) and aliases[name] == null, "params": {}}
	var t: Dictionary = templates[tid]
	var spec: Dictionary = ((kinds.get("kinds", {}) as Dictionary).get(str(t.get("kind", "")), {}) as Dictionary).get("params", {})
	var have: Dictionary = t.get("params", {})
	var add: Dictionary = {}
	for k: Variant in spec.keys():
		var ps: Dictionary = spec[k]
		if not bool(ps.get("req", false)) or have.has(k) or ps.has("def"):
			continue
		var ty: String = str(ps.get("type", ""))
		match ty:
			"s":
				add[k] = 3
			"cells":
				add[k] = 5
			"pct":
				add[k] = 10
			"n":
				add[k] = 1
			"bool":
				add[k] = false
			"str":
				add[k] = "stub"
			_:
				return {"ok": false, "params": {}}
	return {"ok": true, "params": add}


static func _stub_drone(drone_id: String, g: Dictionary, code: String, short: String, weapons: Array) -> Dictionary:
	var c: Dictionary = g.get("carriers", {})
	var wid: String = "weapon.%s.%s_drone_gun" % [code, short]
	var w: Dictionary = (c.get("drone_weapon", {}) as Dictionary).duplicate(true)
	w["id"] = wid
	weapons.append(w)
	return {
		"id": drone_id, "class": "drone", "unit_tags": ["aircraft", "combat", "unmanned"], "size_class": "air_medium",
		"armor_class": str(c.get("drone_armor_class", "air_light")), "movement_class": "air_hover", "layer": "air",
		"health": c.get("drone_health", 150), "speed_cells_s": c.get("drone_speed_cells_s", 6.0), "vision_cells": 7.0,
		"radius_cells": 0.4, "cost_credits": c.get("drone_replace_cost_credits", 120),
		"build_time_s": c.get("drone_replace_s", 14), "pop_n": 0, "weapons": [wid],
	}


static func _sorted_by_id(arr: Array) -> Array:
	var out: Array = arr.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


## A complete DefSources: bible + every manifest file; unit sheets of the 8 factions are STUBS (deterministic, from the
## role archetypes), everything else is read from disk, or an empty schema shell when the file does not exist yet.
## `real_sheets` = true prefers a real units_<code>.json when it exists on disk.
static func stub_sources(real_sheets: bool = false) -> DefSources:
	var bible: Dictionary = read_json(BIBLE_PATH)
	var g: Dictionary = read_json(BALANCE_DIR.path_join("global.json"))
	var kinds: Dictionary = read_json(BALANCE_DIR.path_join("ability_kinds.json"))
	var stubs: Dictionary = stub_balance(bible, g, kinds)
	var man: Dictionary = read_json(BALANCE_DIR.path_join("manifest.json"))
	var files: Array = man.get("files", DefValidator.CORE_FILES)
	var bal: Dictionary = {}
	for f: Variant in files:
		var name: String = str(f)
		var disk: Dictionary = read_json(BALANCE_DIR.path_join(name))
		if stubs.has(name) and not (real_sheets and not disk.is_empty()):
			bal[name] = stubs[name]
		elif not disk.is_empty():
			bal[name] = disk
		elif name == "structures.json":
			var ov: Array = []
			var sids: Array = (bible.get("structures", {}) as Dictionary).keys()
			sids.sort()
			for sid: Variant in sids:
				ov.append({"id": sid})
			bal[name] = {"schema": "meridian.balance.structures/1", "structures": ov}
		elif _EMPTY_SHELLS.has(name):
			var sh: Array = _EMPTY_SHELLS[name]
			bal[name] = {"schema": sh[0], sh[1]: {}}
	return DefSources.from_dicts(bible, bal)


## GameData loaded from stub_sources() (null when the loader reports errors; see GameData.last_report).
static func stub_game_data(real_sheets: bool = false) -> GameData:
	return GameData.load_from_sources(stub_sources(real_sheets))


# --------------------------------------------------------------------------------------------- goldens
## {format, hash, tables} of small_data(): the content of tests/golden/data_hash.json (ints only, so JSON-safe).
static func golden_dict() -> Dictionary:
	var d: GameData = small_data()
	return {"format": GameData.FORMAT_VERSION, "hash": d.data_hash(), "tables": d.table_hashes}


# ------------------------------------------------------------------------------------------ small_data
## Hand-made GameData without file access (see the class comment). `pop` of service units is 0.
static func small_data() -> GameData:
	var d: GameData = GameData.new()
	var rep: DefLoadReport = d.report
	d.damage = _small_damage()
	d.moves = _small_moves()
	d.bodies = _small_bodies()
	d.weapon_archs = _small_archs()
	var ids: DefIds = d.ids
	var warch: PackedStringArray = PackedStringArray()
	for n: String in DefEnums.WEAPON_ARCH_NAMES:
		warch.append("warch." + n)
	ids.assign_frozen(DefEnums.Kind.WEAPON_ARCH, warch, rep)
	ids.assign(DefEnums.Kind.UNIT, PackedStringArray([U_COLLECTOR, U_ENGINEER, U_MCV, U_RIFLEMAN, U_TANK, U_TANK2]), rep)
	ids.assign(DefEnums.Kind.STRUCTURE, PackedStringArray([S_BARRACKS, S_FACTORY, S_GENERATOR, S_HQ, S_REFINERY, S_TURRET]), rep)
	ids.assign(DefEnums.Kind.RESEARCH, PackedStringArray(["research.tst.armor"]), rep)
	ids.assign(DefEnums.Kind.POWER, PackedStringArray(["power.tst.strike"]), rep)
	ids.assign(DefEnums.Kind.ZONE, PackedStringArray(["zone.tst.smoke"]), rep)
	ids.assign(DefEnums.Kind.NEUTRAL, PackedStringArray(["neutral.tst.depot"]), rep)
	ids.assign(DefEnums.Kind.FACTION, PackedStringArray(["faction.tst"]), rep)
	ids.assign(DefEnums.Kind.ROSTER, PackedStringArray([R_ALPHA, R_VANILLA]), rep)
	_small_structures(d)
	_small_units(d)
	_small_rules(d)
	_small_rosters(d)
	d.finalize_hashes()
	return d


## A player view on a roster of small_data() (or any GameData).
static func player_view(data: GameData, roster_id: String) -> DefPlayerView:
	return DefPlayerView.new(data, data.rosters[data.roster_idx(roster_id)])


static func _small_damage() -> DefDamageTable:
	var t: DefDamageTable = DefDamageTable.new()
	var nd: int = DefEnums.DamageType.COUNT
	var na: int = DefEnums.ArmorClass.COUNT
	t.damage_ids = DefEnums.DAMAGE_NAMES.duplicate()
	t.armor_ids = DefEnums.ARMOR_NAMES.duplicate()
	t.group_mask = DefEnums.DAMAGE_GROUP_MASK.duplicate()
	t.nonlethal_mask = 1 << DefEnums.DamageType.EMP
	t.matrix_pct.resize(nd * na)
	t.matrix_bp.resize(nd * na)
	for dt: int in nd:
		for ar: int in na:
			var v: int = 100
			if dt == DefEnums.DamageType.EMP and ar == DefEnums.ArmorClass.INFANTRY:
				v = 0
			elif (dt == DefEnums.DamageType.RAIL or dt == DefEnums.DamageType.KINETIC) and (ar == DefEnums.ArmorClass.AIR_LIGHT or ar == DefEnums.ArmorClass.AIR_HEAVY):
				v = 0
			elif dt == DefEnums.DamageType.AP and ar == DefEnums.ArmorClass.HEAVY_ARMOR:
				v = 90
			elif dt == DefEnums.DamageType.BULLET and ar >= DefEnums.ArmorClass.MEDIUM_ARMOR:
				v = 40
			t.matrix_pct[dt * na + ar] = v
			t.matrix_bp[dt * na + ar] = v * 100
	return t


static func _small_moves() -> DefMoveTable:
	var t: DefMoveTable = DefMoveTable.new()
	var nm: int = DefEnums.MoveClass.COUNT
	t.speed_bp.resize(nm * DefMoveTable.TERRAIN_COUNT)
	t.layer.resize(nm)
	t.layer_mask.resize(nm)
	for c: int in nm:
		var layer: int = DefEnums.Layer.GROUND
		var row: Array = [10000, 10000, 7500, 5000, 8000, 9000, 0, 0]  # road open rough forest marsh shallow deep cliff
		if c == DefEnums.MoveClass.NAVAL:
			layer = DefEnums.Layer.SURFACE_WATER
			row = [0, 0, 0, 0, 0, 10000, 10000, 0]
		elif c == DefEnums.MoveClass.SUBMERGED:
			layer = DefEnums.Layer.UNDERWATER
			row = [0, 0, 0, 0, 0, 0, 10000, 0]
		elif c == DefEnums.MoveClass.AIR_FIXED or c == DefEnums.MoveClass.AIR_HOVER:
			layer = DefEnums.Layer.AIR
			row = [10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000]
		elif c == DefEnums.MoveClass.STATIC:
			row = [0, 0, 0, 0, 0, 0, 0, 0]
		elif c == DefEnums.MoveClass.AMPHIBIOUS:
			row[DefEnums.TerrainKind.DEEP] = 7000
		t.layer[c] = layer
		t.layer_mask[c] = 1 << layer
		if c == DefEnums.MoveClass.AMPHIBIOUS:
			t.layer_mask[c] = DefEnums.L_GROUND | DefEnums.L_WATER
		elif c == DefEnums.MoveClass.SUBMERGED:
			t.layer_mask[c] = DefEnums.L_UNDER | DefEnums.L_WATER
		for k: int in DefMoveTable.TERRAIN_COUNT:
			t.speed_bp[c * DefMoveTable.TERRAIN_COUNT + k] = row[k]
	return t


static func _small_bodies() -> DefBodyTable:
	var t: DefBodyTable = DefBodyTable.new()
	var n: int = DefEnums.SizeClass.COUNT
	t.radius_u.resize(n)
	t.turn_apt.resize(n)
	t.mass.resize(n)
	t.fp_w.resize(n)
	t.fp_h.resize(n)
	t.is_structure.resize(n)
	for i: int in n:
		t.radius_u[i] = 410 + 50 * i
		t.turn_apt[i] = 130 - 6 * i
		t.mass[i] = 1 + i
		if i >= DefEnums.SizeClass.S1:
			t.is_structure[i] = 1
			t.fp_w[i] = i - DefEnums.SizeClass.S1 + 1
			t.fp_h[i] = i - DefEnums.SizeClass.S1 + 1
	return t


static func _small_archs() -> Array[DefWeaponArch]:
	var out: Array[DefWeaponArch] = []
	for i: int in DefEnums.WeaponArch.COUNT:
		var w: DefWeaponArch = DefWeaponArch.new()
		w.id = "warch." + DefEnums.WEAPON_ARCH_NAMES[i]
		w.index = i
		w.target_mask = DefEnums.L_GROUND | DefEnums.L_WATER
		w.range_lo = 5 * Fp.CELL
		w.range_hi = 8 * Fp.CELL
		w.reload_lo_mt = 20000
		w.reload_hi_mt = 40000
		if i == DefEnums.WeaponArch.TANK_CANNON:
			w.dtype = DefEnums.DamageType.AP
			w.proj_kind = DefEnums.ProjKind.SHELL
			w.proj_speed = 819
			w.homing = true
			w.splash_radius = 512
			w.splash_edge_bp = 5000
			w.turret_turn = 51
		elif i == DefEnums.WeaponArch.AA_MISSILE:
			w.dtype = DefEnums.DamageType.AP
			w.proj_kind = DefEnums.ProjKind.MISSILE
			w.proj_speed = 1024
			w.target_mask = DefEnums.L_AIR
			w.interceptable = DefEnums.Interceptable.APS_TRIDENT
		elif i == DefEnums.WeaponArch.BEAM_THERMAL:
			w.dtype = DefEnums.DamageType.THERMAL
			w.proj_kind = DefEnums.ProjKind.BEAM
		w.tags = DefWeaponArch.derived_tags(w)
		out.append(w)
	return out


static func _slot(d: GameData, arch: int, damage: int, reload_mt: int, range_u: int, mount: int) -> DefWeaponSlot:
	var a: DefWeaponArch = d.weapon_archs[arch]
	var s: DefWeaponSlot = DefWeaponSlot.new()
	s.arch = arch
	s.damage = damage
	s.dtype = a.dtype
	s.fire_mode = a.fire_mode
	s.proj_kind = a.proj_kind
	s.interceptable = a.interceptable
	s.homing = a.homing
	s.reload_mt = reload_mt
	s.reload_ticks = DefConvert.ceil_div(reload_mt, 1000)
	s.range = range_u
	s.proj_speed = a.proj_speed
	s.splash_radius = a.splash_radius
	s.splash_edge_bp = a.splash_edge_bp
	s.target_mask = a.target_mask
	s.turret_turn = a.turret_turn
	s.mount = mount
	if a.homing:
		s.flags |= DefEnums.WF_HOMING
	return s


static func _ability(kind: int, slot: int, params: Dictionary) -> DefAbility:
	var a: DefAbility = DefAbility.new()
	a.kind = kind
	a.slot = slot
	a.params = params
	return a


static func _small_structures(d: GameData) -> void:
	var rows: Array = [
		# id, cost, ticks, power, health, armor, size(S1..), radius, sight, tags, requires
		[S_BARRACKS, 500, 400, -30, 1500, 8, 11, 1024, 6144, [], [S_GENERATOR]],
		[S_FACTORY, 2000, 800, -60, 2500, 8, 12, 1536, 7168, [], [S_REFINERY]],
		[S_GENERATOR, 600, 500, 150, 1200, 8, 11, 1024, 6144, [], []],
		[S_HQ, 0, 0, 0, 6000, 10, 12, 1536, 11264, [], []],
		[S_REFINERY, 1800, 800, -50, 2000, 8, 12, 1536, 7168, [], [S_GENERATOR]],
		[S_TURRET, 800, 300, -20, 1000, 9, 10, 512, 8192, ["defense"], [S_GENERATOR]],
	]
	for i: int in rows.size():
		var r: Array = rows[i]
		var s: DefStructure = DefStructure.new()
		s.id = r[0]
		s.index = d.ids.index_of(DefEnums.Kind.STRUCTURE, s.id)
		s.cost = r[1]
		s.build_ticks = r[2]
		s.power = r[3]
		s.health = r[4]
		s.armor_class = r[5]
		s.size_class = r[6]
		s.radius = r[7]
		s.sight = r[8]
		s.fp_w = d.bodies.fp_w[s.size_class]
		s.fp_h = d.bodies.fp_h[s.size_class]
		s.tags = DefEnums.ST_STRUCTURE
		if (r[9] as Array).has("defense"):
			s.tags |= DefEnums.ST_DEFENSE
			s.flags |= DefEnums.SF_POWERED_DEFENSE
		for rq: String in r[10]:
			s.requires.append(d.ids.index_of(DefEnums.Kind.STRUCTURE, rq))
		s.requires.sort()
		for q: int in s.requires:
			s.requires_mask |= 1 << q
		s.ability_slot_of_kind = _no_abilities()
		s.repair_cost_bp = d.economy.repair_cost_bp
		s.sell_bp = d.economy.sell_refund_bp
		s.flags |= DefEnums.SF_SELLABLE | DefEnums.SF_REPAIRABLE
		s.pres_recipe = s.id
		s.pres_icon = s.id
		d.structures.append(s)
	var hq: DefStructure = d.structures[d.structure_idx(S_HQ)]
	hq.flags = DefEnums.SF_NO_BUILD | DefEnums.SF_CAPTURE_IMMUNE
	hq.build_radius = d.economy.build_radius_u
	hq.starts_deployed = true
	hq.deploy_t = 60
	var tur: DefStructure = d.structures[d.structure_idx(S_TURRET)]
	tur.weapons.append(_slot(d, DefEnums.WeaponArch.TANK_CANNON, 110, 30000, 8 * Fp.CELL, 1))
	tur.weapon_tags = d.weapon_archs[DefEnums.WeaponArch.TANK_CANNON].tags
	for s: DefStructure in d.structures:
		match s.id:
			S_BARRACKS:
				s.queue_kind = DefEnums.QueueKind.INFANTRY
				s.flags |= DefEnums.SF_PRODUCTION
			S_FACTORY:
				s.queue_kind = DefEnums.QueueKind.VEHICLE
				s.flags |= DefEnums.SF_PRODUCTION
			S_REFINERY:
				s.queue_kind = DefEnums.QueueKind.COLLECTOR
				s.flags |= DefEnums.SF_PRODUCTION


static func _no_abilities() -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	a.resize(DefEnums.AbilityKind.COUNT)
	a.fill(-1)
	return a


static func _small_units(d: GameData) -> void:
	var t: DefTags = d.tags
	var inf: int = t.unit_mask(PackedStringArray(["combat", "ground", "infantry"]))
	var veh: int = t.unit_mask(PackedStringArray(["combat", "ground", "land_vehicle", "tank"]))
	var svc: int = t.unit_mask(PackedStringArray(["service", "ground"]))
	var rows: Array = [
		# id, tags, class, tier, producer, cost, ticks, hp, armor, move, size, speed, sight, radius, turn, pop
		[U_COLLECTOR, svc | DefEnums.UT_LAND_VEHICLE | DefEnums.UT_COLLECTOR, 0, 1, S_REFINERY, 1400, 610, 900, 1, 1, 1, 102, 8192, 614, 136, 0],
		[U_ENGINEER, svc | DefEnums.UT_INFANTRY | DefEnums.UT_REPAIR, 0, 1, S_BARRACKS, 500, 360, 260, 0, 0, 0, 77, 7168, 410, 130, 1],
		[U_MCV, svc | DefEnums.UT_LAND_VEHICLE | DefEnums.UT_CONSTRUCTION, 0, 1, S_FACTORY, 3000, 1340, 2000, 2, 2, 2, 61, 8192, 819, 85, 0],
		[U_RIFLEMAN, inf, 1, 1, S_BARRACKS, 250, 180, 400, 0, 0, 0, 77, 7168, 410, 130, 1],
		[U_TANK, veh, 1, 1, S_FACTORY, 850, 550, 907, 2, 2, 2, 102, 9216, 563, 85, 1],
		[U_TANK2, veh, 2, 1, S_FACTORY, 900, 550, 1000, 2, 2, 2, 102, 9216, 563, 85, 1],
	]
	for r: Array in rows:
		var u: DefUnit = DefUnit.new()
		u.id = r[0]
		u.index = d.ids.index_of(DefEnums.Kind.UNIT, u.id)
		u.tags = r[1]
		u.unit_class = r[2]
		u.tier = r[3]
		u.producer = d.structure_idx(r[4])
		u.requires = PackedInt32Array([u.producer])
		u.requires_mask = 1 << u.producer
		u.cost = r[5]
		u.build_ticks = r[6]
		u.health = r[7]
		u.armor_class = r[8]
		u.move_class = r[9]
		u.size_class = r[10]
		u.speed = r[11]
		u.sight = r[12]
		u.radius = r[13]
		u.turn_rate = r[14]
		u.pop = r[15]
		u.layer_mask = DefEnums.L_GROUND
		u.home_layer = DefEnums.Layer.GROUND
		u.accel_t = 6
		u.repair_cost_bp = d.economy.repair_cost_bp
		u.ability_slot_of_kind = _no_abilities()
		u.flags = DefEnums.UF_PRODUCIBLE
		u.pres_recipe = u.id
		u.pres_icon = u.id
		d.units.append(u)
	var col: DefUnit = d.units[d.unit_idx(U_COLLECTOR)]
	_add_ability(col, _ability(DefEnums.AbilityKind.HARVEST, 0, {"capacity_cr": 600}))
	var mcv: DefUnit = d.units[d.unit_idx(U_MCV)]
	_add_ability(mcv, _ability(DefEnums.AbilityKind.DEPLOY_STRUCTURE, 0, {"deploy_t": 60, "structure_idx": d.structure_idx(S_HQ)}))
	d.structures[d.structure_idx(S_HQ)].deploy_unit = mcv.index
	var rifle: DefUnit = d.units[d.unit_idx(U_RIFLEMAN)]
	rifle.weapons.append(_slot(d, DefEnums.WeaponArch.SMALL_ARMS, 26, 20000, 5632, 0))
	for tk: String in [U_TANK, U_TANK2]:
		var tank: DefUnit = d.units[d.unit_idx(tk)]
		tank.weapons.append(_slot(d, DefEnums.WeaponArch.TANK_CANNON, 141 if tk == U_TANK else 150, 24000, 7168, 1))
	d.units[d.unit_idx(U_TANK2)].replaces = d.unit_idx(U_TANK)
	d.units[d.unit_idx(U_TANK)].replaced_by = PackedInt32Array([d.unit_idx(U_TANK2)])
	for u: DefUnit in d.units:
		for w: DefWeaponSlot in u.weapons:
			u.max_range = maxi(u.max_range, w.range)
			u.attack_layer_mask |= w.target_mask
			u.weapon_tags |= d.weapon_archs[w.arch].tags
		if u.weapons.is_empty():
			u.flags |= DefEnums.UF_UNARMED


static func _add_ability(u: DefUnit, a: DefAbility) -> void:
	u.abilities.append(a)
	u.ability_slot_of_kind[a.kind] = a.slot
	u.ability_mask |= 1 << a.kind


static func _small_rules(d: GameData) -> void:
	var f: DefFaction = DefFaction.new()
	f.id = "faction.tst"
	f.index = 0
	f.code = "TST"
	f.vanilla_roster = d.roster_idx(R_VANILLA)
	f.sub_rosters = PackedInt32Array([d.roster_idx(R_ALPHA)])
	d.factions.append(f)
	var r: DefResearch = DefResearch.new()
	r.id = "research.tst.armor"
	r.index = 0
	r.faction = 0
	r.tier = 2
	r.cost = 1000
	r.time_t = 900
	r.requires_mask = 1 << d.structure_idx(S_GENERATOR)
	d.research.append(r)
	var p: DefPower = DefPower.new()
	p.id = "power.tst.strike"
	p.index = 0
	p.faction = 0
	p.cost = 500
	p.cooldown_t = 1800
	d.powers.append(p)
	var z: DefZone = DefZone.new()
	z.id = "zone.tst.smoke"
	z.index = 0
	z.zone_kind = DefEnums.ZoneKind.SMOKE
	z.radius = 6144
	z.duration_t = 240
	z.hp = 0
	d.zones.append(z)
	var n: DefNeutral = DefNeutral.new()
	n.id = "neutral.tst.depot"
	n.index = 0
	n.neutral_kind = DefEnums.NeutralKind.CIVILIAN_GARRISON
	n.health = 1200
	n.armor_class = 8
	n.fp_w = 2
	n.fp_h = 2
	n.radius = 1024
	n.sight = 6144
	d.neutrals.append(n)


static func _small_rosters(d: GameData) -> void:
	var hq: int = d.structure_idx(S_HQ)
	for rid: String in [R_ALPHA, R_VANILLA]:
		var r: DefRoster = _build_roster(d, rid, hq)
		d.rosters.append(r)
	d.rosters[d.roster_idx(R_ALPHA)].parent = d.roster_idx(R_VANILLA)
	d.rosters[d.roster_idx(R_ALPHA)].replaced_by = {d.unit_idx(U_TANK): d.unit_idx(U_TANK2)}
	d.base_roster = _build_roster(d, "roster.base", hq)
	d.base_roster.index = -1
	d.base_roster.is_vanilla = true


static func _build_roster(d: GameData, rid: String, hq: int) -> DefRoster:
	var r: DefRoster = DefRoster.new()
	r.id = rid
	r.index = d.roster_idx(rid)
	r.faction = 0
	r.is_vanilla = rid == R_VANILLA
	r.units.resize(d.units.size())
	r.structures.resize(d.structures.size())
	var hidden: String = U_TANK2 if rid != R_ALPHA else U_TANK
	if rid == "roster.base":
		hidden = ""
	for u: DefUnit in d.units:
		if u.id == hidden:
			continue
		r.units[u.index] = u.copy_resolved()
		if (u.flags & DefEnums.UF_PRODUCIBLE) != 0:
			r.producible_units.append(u.index)
	for s: DefStructure in d.structures:
		r.structures[s.index] = s.copy_resolved()
		if s.index != hq:
			r.producible_structures.append(s.index)
	r.research_list = PackedInt32Array([0])
	r.power_list = PackedInt32Array([0])
	r.hq_idx = hq
	r.mcv_idx = d.unit_idx(U_MCV)
	return r
