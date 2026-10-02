class_name ViewDefAdapter
extends RefCounted
## Resolves (SimEntity.Kind, def index) to a ViewDef built from GameData. The ONLY view file that reads Def* fields.
## Two index-space variants are supported (render risk R25): PER_KIND (the real data module: units, structures, zones,
## neutrals are separate dense tables and WRECK entities index the unit table) and DENSE (one space: units first, then
## structures, zones, neutrals). Tests feed both through `setup_tables`.

enum Space { PER_KIND = 0, DENSE = 1 }

const MAX_WARN: int = 8

var space: int = Space.PER_KIND
var _data: GameData = null
var _units: Array = []
var _structures: Array = []
var _zones: Array = []
var _neutrals: Array = []
var _factions: Array = []
var _rosters: Array = []
var _powers: Array = []
var _superweapons: Array = []
var _arch_count: int = 27
var _cache: Dictionary = {}
var _warned: Dictionary = {}


## Detects the index-space variant once and reads the table references; builds nothing eagerly.
func setup(data: GameData) -> void:
	_data = data
	_units = data.units
	_structures = data.structures
	_zones = data.zones
	_neutrals = data.neutrals
	_factions = data.factions
	_rosters = data.rosters
	_powers = data.powers
	_superweapons = data.superweapons
	_arch_count = data.weapon_archs.size() if not data.weapon_archs.is_empty() else 27
	# a structure table whose first def carries an index past the unit table is one dense space
	space = Space.PER_KIND
	if not data.structures.is_empty() and not data.units.is_empty() and (data.structures[0] as DefBase).index >= data.units.size():
		space = Space.DENSE
	ViewSimReader.default_collector_capacity = data.economy.collector_capacity_cr
	_cache.clear()
	_warned.clear()


## Fixture entry point (tests): explicit tables and variant. In DENSE the structure indices are offset by units.size().
func setup_tables(units: Array, structures: Array, dense: bool, zones: Array = [], neutrals: Array = [], factions: Array = []) -> void:
	_data = null
	_units = units
	_structures = structures
	_zones = zones
	_neutrals = neutrals
	_factions = factions
	_rosters = []
	_powers = []
	_superweapons = []
	space = Space.DENSE if dense else Space.PER_KIND
	_cache.clear()
	_warned.clear()


## Cached ViewDef; an unknown def yields a placeholder record and one Log.warn.
func def_for(kind: int, def_idx: int) -> ViewDef:
	var key: int = (kind << 24) | (def_idx & 0xFFFFFF)
	var hit: Variant = _cache.get(key)
	if hit != null:
		return hit as ViewDef
	var vd: ViewDef = _build(kind, def_idx)
	_cache[key] = vd
	return vd


## DefWeaponArch index 0..26 of a weapon def index (the `weapon def idx` of combat events); -1 (one Log.warn) when unknown.
## `weapon_def_idx` is the archetype index itself: combat derives its weapon tables from DefWeaponArch (binding decision 1).
func weapon_arch(weapon_def_idx: int) -> int:
	if weapon_def_idx >= 0 and weapon_def_idx < _arch_count:
		return weapon_def_idx
	_warn_once("warch:%d" % weapon_def_idx, "unknown weapon def index %d" % weapon_def_idx)
	return -1


## "roster.napc.canada" for a roster index; "" when unknown.
func roster_id(roster_idx: int) -> String:
	if roster_idx < 0 or roster_idx >= _rosters.size():
		return ""
	return (_rosters[roster_idx] as DefRoster).id


## Every (kind, def index) a player of roster `roster_idx` can ever show: producible units, summons / drones, the start MCV, producible structures
## and the start HQ, as a flat PackedInt32Array [kind, idx, kind, idx, ...] (model prewarm of the loading screen).
func roster_showable(roster_idx: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if roster_idx < 0 or roster_idx >= _rosters.size():
		return out
	var r: DefRoster = _rosters[roster_idx] as DefRoster
	for ui: int in r.producible_units:
		out.append(SimEntity.Kind.UNIT)
		out.append(ui)
	for ui2: int in r.spawnables:
		out.append(SimEntity.Kind.UNIT)
		out.append(ui2)
	if r.mcv_idx >= 0:
		out.append(SimEntity.Kind.UNIT)
		out.append(r.mcv_idx)
	for si: int in r.producible_structures:
		out.append(SimEntity.Kind.STRUCTURE)
		out.append(si)
	if r.hq_idx >= 0:
		out.append(SimEntity.Kind.STRUCTURE)
		out.append(r.hq_idx)
	return out


## Last id segment of a power id (fx.json key), e.g. &"atlas_kinetic_array" for superweapons.
func power_key(power_idx: int) -> StringName:
	if power_idx < 0 or power_idx >= _powers.size():
		return &""
	return StringName(_last_segment((_powers[power_idx] as DefBase).id))


func superweapon_key(sw_idx: int) -> StringName:
	if sw_idx < 0 or sw_idx >= _superweapons.size():
		return &""
	return StringName(_last_segment((_superweapons[sw_idx] as DefBase).id))


# ---- build ---------------------------------------------------------------------------------------------------

func _resolve(kind: int, def_idx: int) -> DefBase:
	var idx: int = def_idx
	var table: Array = []
	match kind:
		SimEntity.Kind.STRUCTURE:
			table = _structures
			if space == Space.DENSE:
				idx -= _units.size()
		SimEntity.Kind.ZONE:
			table = _zones
			if space == Space.DENSE:
				idx -= _units.size() + _structures.size()
		SimEntity.Kind.NEUTRAL:
			table = _neutrals
			if space == Space.DENSE:
				idx -= _units.size() + _structures.size() + _zones.size()
		_:
			table = _units
	if idx < 0 or idx >= table.size():
		return null
	return table[idx] as DefBase


func _build(kind: int, def_idx: int) -> ViewDef:
	var d: DefBase = _resolve(kind, def_idx)
	var vd: ViewDef = ViewDef.new()
	vd.kind = kind
	vd.def_idx = def_idx
	if d == null:
		_warn_once("def:%d:%d" % [kind, def_idx], "unknown def (kind %d, idx %d): placeholder" % [kind, def_idx])
		vd.placeholder = true
		vd.id = "unknown.%d.%d" % [kind, def_idx]
		vd.recipe_id = &"placeholder"
		vd.icon_id = &"placeholder"
		vd.radius_m = 1.35
		return vd
	vd.id = d.id
	if d is DefUnit:
		_fill_unit(vd, d as DefUnit)
	elif d is DefStructure:
		_fill_structure(vd, d as DefStructure)
	elif d is DefZone:
		_fill_zone(vd, d as DefZone)
	elif d is DefNeutral:
		_fill_neutral(vd, d as DefNeutral)
	return vd


func _fill_unit(vd: ViewDef, u: DefUnit) -> void:
	vd.faction_code = _faction_code(u.faction)
	vd.recipe_id = StringName(u.pres_recipe if u.pres_recipe != "" else u.id)
	vd.icon_id = StringName(u.pres_icon if u.pres_icon != "" else u.id)
	vd.scale_bp = u.pres_scale_bp
	vd.unit_class = u.unit_class
	vd.move_class = u.move_class
	vd.size_class = u.size_class
	vd.layer = u.home_layer
	vd.radius_m = float(u.radius) * ViewConsts.M_PER_UNIT
	var harvest: DefAbility = u.ability_of(DefEnums.AbilityKind.HARVEST)
	if harvest != null:
		vd.cargo_cap = int(harvest.params.get("capacity_cr", _data.economy.collector_capacity_cr if _data != null else 0))
	_fill_warch(vd, u.weapons)
	vd.is_defense = false


func _fill_structure(vd: ViewDef, s: DefStructure) -> void:
	vd.faction_code = _faction_code(s.faction)
	vd.recipe_id = StringName(s.pres_recipe if s.pres_recipe != "" else s.id)
	vd.icon_id = StringName(s.pres_icon if s.pres_icon != "" else s.id)
	vd.size_class = s.size_class
	vd.radius_m = float(s.radius) * ViewConsts.M_PER_UNIT
	vd.fp_w = s.fp_w
	vd.fp_h = s.fp_h
	vd.rotatable = (s.place_mask & DefEnums.PLACE_SHORELINE) != 0  # only the Dock is rotatable
	vd.needs_power = s.power < 0
	vd.is_hq = (s.flags & DefEnums.SF_NO_BUILD) != 0 and (s.starts_deployed or s.deploy_unit >= 0)
	vd.is_defense = not s.weapons.is_empty()
	_fill_warch(vd, s.weapons)
	var fw: float = float(s.fp_w)
	var fh: float = float(s.fp_h)
	vd.door_cx = (float(s.exit_dx) + 0.5 - fw * 0.5) * ViewConsts.CELL_M
	vd.door_cz = (float(s.exit_dy) + 0.5 - fh * 0.5) * ViewConsts.CELL_M
	vd.exit_dir = _exit_dir(s.exit_dx, s.exit_dy, s.fp_w, s.fp_h)
	vd.dock_cx = vd.door_cx
	vd.dock_cz = vd.door_cz
	vd.dock_dir = vd.exit_dir
	if s.pads > 0:
		vd.pads.resize(s.pads * 2)
		for i: int in s.pads:
			vd.pads[i * 2] = ((float(i) + 0.5) / float(s.pads) - 0.5) * (fw * ViewConsts.CELL_M - 1.0)
			vd.pads[i * 2 + 1] = 0.0


func _fill_zone(vd: ViewDef, z: DefZone) -> void:
	vd.recipe_id = StringName(z.pres_recipe if z.pres_recipe != "" else z.id)
	vd.icon_id = vd.recipe_id
	vd.zone_kind = z.zone_kind
	vd.zone_shape = z.shape
	vd.zone_radius_m = float(z.radius) * ViewConsts.M_PER_UNIT
	vd.zone_length_m = float(z.length) * ViewConsts.M_PER_UNIT
	vd.zone_width_m = float(z.width) * ViewConsts.M_PER_UNIT
	vd.visible_to_enemy = z.visible_to_enemy
	vd.radius_m = vd.zone_radius_m


func _fill_neutral(vd: ViewDef, n: DefNeutral) -> void:
	vd.recipe_id = StringName(n.pres_recipe if n.pres_recipe != "" else n.id)
	vd.icon_id = vd.recipe_id
	vd.fp_w = n.fp_w
	vd.fp_h = n.fp_h
	vd.radius_m = float(n.radius) * ViewConsts.M_PER_UNIT
	vd.door_cz = float(n.fp_h) * ViewConsts.CELL_M * 0.5 + ViewConsts.CELL_M * 0.5


func _fill_warch(vd: ViewDef, weapons: Array) -> void:
	var seen: int = 0
	for ws: Variant in weapons:
		var slot: DefWeaponSlot = ws as DefWeaponSlot
		if slot == null:
			continue
		if slot.slot >= 0 and slot.slot < 4:
			vd.warch[slot.slot] = slot.arch
			seen += 1
		elif seen < 4:
			vd.warch[seen] = slot.arch
			seen += 1


func _faction_code(f: int) -> String:
	if f < 0 or f >= _factions.size():
		return ""
	return (_factions[f] as DefFaction).code.to_lower()


## Direction (facing units, 1024 = south) of the exit cell relative to the footprint rectangle.
static func _exit_dir(dx: int, dy: int, fw: int, fh: int) -> int:
	if dy >= fh:
		return 1024
	if dy < 0:
		return 3072
	if dx >= fw:
		return 0
	if dx < 0:
		return 2048
	return 1024


static func _last_segment(id: String) -> String:
	var p: int = id.rfind(".")
	return id.substr(p + 1) if p >= 0 else id


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key) or _warned.size() >= MAX_WARN:
		return
	_warned[key] = true
	Log.warn("view.defs", msg)
