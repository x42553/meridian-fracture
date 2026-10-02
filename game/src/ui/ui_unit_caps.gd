class_name UiUnitCaps
extends RefCounted
## Per-def capability bits (ui.md 4.3), computed once per def from `DefUnit` / `DefStructure` and cached; the cache
## is rebuilt when the roster changes. Pure logic: `of_unit` / `of_structure` are static and testable on any def.

const CAP_ARMED: int = 1 << 0
const CAP_HIT_GROUND: int = 1 << 1
const CAP_HIT_AIR: int = 1 << 2
const CAP_HIT_WATER: int = 1 << 3
const CAP_HIT_SUB: int = 1 << 4
const CAP_MOBILE: int = 1 << 5
const CAP_AIR: int = 1 << 6
const CAP_NAVAL: int = 1 << 7
const CAP_INFANTRY: int = 1 << 8
const CAP_VEHICLE: int = 1 << 9
const CAP_ARTILLERY: int = 1 << 10
const CAP_COLLECTOR: int = 1 << 11
const CAP_CAPTURE: int = 1 << 12
const CAP_REPAIR_VEHICLE: int = 1 << 13
const CAP_REPAIR_STRUCT: int = 1 << 14
const CAP_SALVAGE: int = 1 << 15
const CAP_TRANSPORT: int = 1 << 16
const CAP_PASSENGER: int = 1 << 17
const CAP_DEPLOY: int = 1 << 18
const CAP_MCV: int = 1 << 19
const CAP_MODE_SWITCH: int = 1 << 20
const CAP_GARRISON: int = 1 << 21
const CAP_DETECTOR: int = 1 << 22
const CAP_CARRIER_DRONE: int = 1 << 23
const CAP_SERVICE: int = 1 << 24
const CAP_STRUCTURE: int = 1 << 25
const CAP_PRODUCER: int = 1 << 26
const CAP_SELLABLE: int = 1 << 27
const CAP_HAS_ABILITY_BUTTONS: int = 1 << 28
const CAP_BITS: int = 29

const NAMES: PackedStringArray = [
	"armed", "hit_ground", "hit_air", "hit_water", "hit_sub", "mobile", "air", "naval", "infantry", "vehicle",
	"artillery", "collector", "capture", "repair_vehicle", "repair_struct", "salvage", "transport", "passenger",
	"deploy", "mcv", "mode_switch", "garrison", "detector", "carrier_drone", "service", "structure", "producer",
	"sellable", "ability_buttons",
]

static var _shared: UiUnitCaps = null

var _data: GameData = null
var _roster: DefRoster = null
var _unit_cache: Dictionary = {}  ## def_idx -> caps
var _struct_cache: Dictionary = {}


## The process-wide instance for the port's data and viewer roster; rebuilt when either changes.
static func shared_for(port: UiSimPort) -> UiUnitCaps:
	var d: GameData = port.data()
	var r: DefRoster = port.roster_of(port.viewer_pid()) if port.viewer_pid() >= 0 else null
	if _shared == null or not _shared.matches(d, r):
		_shared = UiUnitCaps.new()
		_shared.setup(d, r)
	return _shared


func matches(d: GameData, r: DefRoster) -> bool:
	return _data == d and _roster == r


## Binds the def source: `roster` resolves the viewer's modified defs (null = raw GameData tables). Clears the cache.
func setup(data: GameData, roster: DefRoster = null) -> void:
	_data = data
	_roster = roster
	_unit_cache.clear()
	_struct_cache.clear()


## Capability bits of a def; `kind` = UiSimPort.KIND_UNIT / KIND_STRUCTURE. 0 when the def is unknown.
func caps_of(kind: int, def_idx: int) -> int:
	if _data == null or def_idx < 0:
		return 0
	if kind == UiSimPort.KIND_STRUCTURE:
		if not _struct_cache.has(def_idx):
			var s: DefStructure = _struct_def(def_idx)
			_struct_cache[def_idx] = of_structure(s) if s != null else 0
		return int(_struct_cache[def_idx])
	if not _unit_cache.has(def_idx):
		var u: DefUnit = _unit_def(def_idx)
		_unit_cache[def_idx] = of_unit(u) if u != null else 0
	return int(_unit_cache[def_idx])


## DefEnums.MoveClass of a unit def, -1 for structures / unknown.
func move_class_of(kind: int, def_idx: int) -> int:
	if kind == UiSimPort.KIND_STRUCTURE:
		return -1
	var u: DefUnit = _unit_def(def_idx)
	return u.move_class if u != null else -1


func _unit_def(def_idx: int) -> DefUnit:
	if _roster != null and def_idx >= 0 and def_idx < _roster.units.size() and _roster.units[def_idx] != null:
		return _roster.units[def_idx]
	if _data != null and def_idx >= 0 and def_idx < _data.units.size():
		return _data.units[def_idx]
	return null


func _struct_def(def_idx: int) -> DefStructure:
	if _roster != null and def_idx >= 0 and def_idx < _roster.structures.size() and _roster.structures[def_idx] != null:
		return _roster.structures[def_idx]
	if _data != null and def_idx >= 0 and def_idx < _data.structures.size():
		return _data.structures[def_idx]
	return null


## True if `caps` can hit a target on `layer` (SimEntity.Layer: 0 ground, 1 air, 2 surface water, 3 underwater).
static func hits(caps: int, layer: int) -> bool:
	match layer:
		0:
			return (caps & CAP_HIT_GROUND) != 0
		1:
			return (caps & CAP_HIT_AIR) != 0
		2:
			return (caps & CAP_HIT_WATER) != 0
		3:
			return (caps & CAP_HIT_SUB) != 0
	return false


## Names of the set bits (logs, test messages).
static func describe(caps: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in CAP_BITS:
		if (caps & (1 << i)) != 0:
			parts.append(NAMES[i])
	return ",".join(parts)


static func of_unit(u: DefUnit) -> int:
	var c: int = 0
	if not u.weapons.is_empty() and (u.flags & DefEnums.UF_UNARMED) == 0:
		c |= CAP_ARMED
		if (u.attack_layer_mask & DefEnums.L_GROUND) != 0:
			c |= CAP_HIT_GROUND
		if (u.attack_layer_mask & DefEnums.L_AIR) != 0:
			c |= CAP_HIT_AIR
		if (u.attack_layer_mask & DefEnums.L_WATER) != 0:
			c |= CAP_HIT_WATER
		if (u.attack_layer_mask & DefEnums.L_UNDER) != 0:
			c |= CAP_HIT_SUB
	if u.speed > 0:
		c |= CAP_MOBILE
	match u.move_class:
		DefEnums.MoveClass.AIR_FIXED, DefEnums.MoveClass.AIR_HOVER:
			c |= CAP_AIR
		DefEnums.MoveClass.NAVAL, DefEnums.MoveClass.SUBMERGED:
			c |= CAP_NAVAL
	var infantry: bool = (u.tags & DefEnums.UT_INFANTRY) != 0
	var vehicle: bool = (u.tags & DefEnums.UT_LAND_VEHICLE) != 0
	if infantry:
		c |= CAP_INFANTRY | CAP_GARRISON
	if vehicle:
		c |= CAP_VEHICLE
	if (u.tags & DefEnums.UT_ARTILLERY) != 0:
		c |= CAP_ARTILLERY
	if (u.tags & DefEnums.UT_COLLECTOR) != 0:
		c |= CAP_COLLECTOR
	if (u.tags & DefEnums.UT_CONSTRUCTION) != 0:
		c |= CAP_MCV
	if (u.tags & DefEnums.UT_DETECTOR) != 0:
		c |= CAP_DETECTOR
	if u.unit_class == DefEnums.UnitClass.SERVICE:
		c |= CAP_SERVICE
	if u.unit_class == DefEnums.UnitClass.DRONE and (u.tags & DefEnums.UT_UNMANNED) != 0:
		c |= CAP_CARRIER_DRONE
	for a: DefAbility in u.abilities:
		c |= _ability_caps(a)
	if (c & CAP_TRANSPORT) == 0 and (infantry or vehicle) and (c & (CAP_COLLECTOR | CAP_MCV)) == 0:
		c |= CAP_PASSENGER
	return c


static func of_structure(s: DefStructure) -> int:
	var c: int = CAP_STRUCTURE
	if not s.weapons.is_empty():
		c |= CAP_ARMED | CAP_HIT_GROUND
		if (s.weapon_tags & DefEnums.WT_ANTI_AIR) != 0:
			c |= CAP_HIT_AIR
	if s.queue_kind != 0:
		c |= CAP_PRODUCER
	if (s.flags & DefEnums.SF_SELLABLE) != 0:
		c |= CAP_SELLABLE
	if s.detect_radius > 0:
		c |= CAP_DETECTOR
	return c


static func _ability_caps(a: DefAbility) -> int:
	var c: int = 0
	match a.kind:
		DefEnums.AbilityKind.HARVEST:
			c |= CAP_COLLECTOR
		DefEnums.AbilityKind.CAPTURE:
			c |= CAP_CAPTURE
		DefEnums.AbilityKind.SALVAGE:
			c |= CAP_SALVAGE
		DefEnums.AbilityKind.REPAIR:
			var um: int = int(a.params.get("target_unit_mask", 0))
			var sm: int = int(a.params.get("target_structure_mask", 0))
			if (um & DefEnums.UT_LAND_VEHICLE) != 0:
				c |= CAP_REPAIR_VEHICLE
			if sm != 0:
				c |= CAP_REPAIR_STRUCT
		DefEnums.AbilityKind.TRANSPORT:
			c |= CAP_TRANSPORT | CAP_HAS_ABILITY_BUTTONS
		DefEnums.AbilityKind.DEPLOY, DefEnums.AbilityKind.SENSOR_MAST:
			c |= CAP_DEPLOY
		DefEnums.AbilityKind.DEPLOY_STRUCTURE:
			c |= CAP_DEPLOY | CAP_MCV
		DefEnums.AbilityKind.MODE_SWITCH:
			c |= CAP_MODE_SWITCH | CAP_HAS_ABILITY_BUTTONS
		DefEnums.AbilityKind.DETECTOR:
			c |= CAP_DETECTOR
		DefEnums.AbilityKind.DECOY_SPAWN, DefEnums.AbilityKind.SENSOR_PUCK, DefEnums.AbilityKind.SMOKE_LAUNCHER, \
		DefEnums.AbilityKind.PORTABLE_COVER, DefEnums.AbilityKind.CARRIER, DefEnums.AbilityKind.SUBMERGE:
			c |= CAP_HAS_ABILITY_BUTTONS
	return c
