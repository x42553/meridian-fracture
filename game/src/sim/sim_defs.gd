class_name SimDefs
extends RefCounted
## THE adapter between the kernel and the data domain (sim_core 3.3.5 / 7.2): every def field the kernel reads is
## read here and nowhere else, so a data-side rename costs one file. Built once from `world.data` (a GameData);
## all reads are pure and allocation-free after construction.
##
## Members read (data_balance 3-4): GameData.units / structures / zones / neutrals (arrays indexed by the per-kind
## dense def index); DefUnit.health, radius, home_layer, pop, flags, ability_mask; DefStructure.health, radius;
## DefZone.hp, radius; DefNeutral.health, radius; DefPlayerView.resolved_stats(kind, def_idx)[STAT_HEALTH].
## Footprints are NOT a data matter for the kernel: they belong to the map (`map.footprint_of(kind, def_idx)`).

## SimEntity.Kind -> DefEnums.Kind (UNIT 0, STRUCTURE 1, WRECK -> UNIT, ZONE 7, NEUTRAL 8).
const DEF_KIND: PackedInt32Array = [0, 1, 0, 7, 8]
## DefEnums.Stat.HEALTH: index into DefPlayerView.resolved_stats().
const STAT_HEALTH: int = DefEnums.Stat.HEALTH
## DefUnit.flags bits (DefEnums.UnitFlag).
const UF_NO_REPAIR: int = DefEnums.UF_NO_REPAIR
const UF_NO_CAPTURE: int = DefEnums.UF_NO_CAPTURE
const UF_NO_SALVAGE: int = DefEnums.UF_NO_SALVAGE
const UF_NON_BLOCKING: int = DefEnums.UF_NON_BLOCKING
## AbilityKind.DEPLOY_STRUCTURE: a unit whose ability_mask has this bit is an MCV-class rebuilder.
const ABILITY_DEPLOY_STRUCTURE: int = DefEnums.AbilityKind.DEPLOY_STRUCTURE

var data: GameData = null

# Per-kind def arrays of `data` (same arrays, not copies).
var _units: Array[DefUnit] = []
var _structures: Array[DefStructure] = []
var _zones: Array[DefZone] = []
var _neutrals: Array[DefNeutral] = []
## 1 for each unit def that carries DEPLOY_STRUCTURE, built once.
var _rebuilder: PackedByteArray = PackedByteArray()


func _init(game_data: GameData) -> void:
	data = game_data
	_units = game_data.units
	_structures = game_data.structures
	_zones = game_data.zones
	_neutrals = game_data.neutrals
	_rebuilder.resize(_units.size())
	for i: int in _units.size():
		var d: DefUnit = _units[i]
		_rebuilder[i] = 1 if ((d.ability_mask >> ABILITY_DEPLOY_STRUCTURE) & 1) != 0 else 0


## true when (kind, def_idx) names an existing def.
func has_def(kind: int, def_idx: int) -> bool:
	if kind < 0 or kind > 4 or def_idx < 0:
		return false
	match kind:
		SimEntity.Kind.STRUCTURE:
			return def_idx < _structures.size()
		SimEntity.Kind.ZONE:
			return def_idx < _zones.size()
		SimEntity.Kind.NEUTRAL:
			return def_idx < _neutrals.size()
	return def_idx < _units.size()


## The owner's current max hit points (static layers + permanent research). `view` null (neutral owner): the
## def's base value.
func hp_max(view: DefPlayerView, kind: int, def_idx: int) -> int:
	if view != null and (kind == SimEntity.Kind.UNIT or kind == SimEntity.Kind.WRECK or kind == SimEntity.Kind.STRUCTURE):
		var st: PackedInt32Array = view.resolved_stats(DEF_KIND[kind], def_idx)
		return st[STAT_HEALTH]
	match kind:
		SimEntity.Kind.STRUCTURE:
			return _structures[def_idx].health
		SimEntity.Kind.ZONE:
			return _zones[def_idx].hp
		SimEntity.Kind.NEUTRAL:
			return _neutrals[def_idx].health
	return _units[def_idx].health


## Collision / selection radius in sub-cell units.
func radius(kind: int, def_idx: int) -> int:
	match kind:
		SimEntity.Kind.STRUCTURE:
			return _structures[def_idx].radius
		SimEntity.Kind.ZONE:
			return _zones[def_idx].radius
		SimEntity.Kind.NEUTRAL:
			return _neutrals[def_idx].radius
	return _units[def_idx].radius


## SimEntity.Layer at spawn (non-units: GROUND).
func home_layer(kind: int, def_idx: int) -> int:
	if kind == SimEntity.Kind.UNIT:
		return _units[def_idx].home_layer
	return SimEntity.Layer.GROUND


## Unit-cap weight: DefUnit.pop for UNIT (0 = exempt), 0 otherwise.
func cap_weight(kind: int, def_idx: int) -> int:
	if kind == SimEntity.Kind.UNIT:
		return _units[def_idx].pop
	return 0


## Initial SimFlags: UF_* of a unit / wreck def mapped to F_*; zones are untargetable and unselectable.
func flags_init(kind: int, def_idx: int) -> int:
	if kind == SimEntity.Kind.ZONE:
		return SimFlags.F_UNTARGETABLE | SimFlags.F_NO_SELECT
	if kind != SimEntity.Kind.UNIT and kind != SimEntity.Kind.WRECK:
		return 0
	var uf: int = _units[def_idx].flags
	var f: int = 0
	if (uf & UF_NON_BLOCKING) != 0:
		f |= SimFlags.F_NO_COLLISION
	if (uf & UF_NO_REPAIR) != 0:
		f |= SimFlags.F_NO_REPAIR
	if (uf & UF_NO_CAPTURE) != 0:
		f |= SimFlags.F_NO_CAPTURE
	if (uf & UF_NO_SALVAGE) != 0:
		f |= SimFlags.F_NO_SALVAGE
	return f


## MCV-class unit (carries DEPLOY_STRUCTURE): keeps its owner alive.
func is_rebuilder(kind: int, def_idx: int) -> bool:
	return kind == SimEntity.Kind.UNIT and def_idx >= 0 and def_idx < _rebuilder.size() and _rebuilder[def_idx] == 1
