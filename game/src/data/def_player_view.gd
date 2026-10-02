class_name DefPlayerView
extends RefCounted
## Per-player facade over (roster, layer 3) in the accessor shapes the economy / abilities / combat specs requested
## (data_balance 3.13). `SimPlayer.view = DefPlayerView.new(data, roster)`. The flat tables are derived from the
## roster clones and layer 3 and are not hashed; `checksum()` is the layer-3 checksum.
## The flat tables apply layers 1-3 (static roster clone + permanent research from DefLayer3); temporary effects
## (powers, auras, zones) are the abilities domain's `extra_bp` on top.

var data: GameData
var roster: DefRoster
var layer3: DefLayer3
var version: int = -1  ## layer3.version at the last refresh
# economy-shaped flat tables; index = def index; 0 for defs not in the roster
var unit_cost: PackedInt32Array = PackedInt32Array()
var unit_ticks: PackedInt32Array = PackedInt32Array()
var unit_available: PackedInt32Array = PackedInt32Array()
var unit_cap_cost: PackedInt32Array = PackedInt32Array()
var unit_rearm_ticks: PackedInt32Array = PackedInt32Array()
var struct_cost: PackedInt32Array = PackedInt32Array()
var struct_ticks: PackedInt32Array = PackedInt32Array()
var struct_available: PackedInt32Array = PackedInt32Array()
var struct_power: PackedInt32Array = PackedInt32Array()
var unit_repair_cost_bp: PackedInt32Array = PackedInt32Array()
var struct_repair_cost_bp: PackedInt32Array = PackedInt32Array()
var struct_repair_rate_bp: PackedInt32Array = PackedInt32Array()
var research_available: PackedInt32Array = PackedInt32Array()
var power_of_slot: PackedInt32Array = PackedInt32Array()
var super_idx: int = -1

var _stats: Dictionary = {}  ## (kind << 24 | def) -> PackedInt32Array, cleared on refresh


func _init(d: GameData, r: DefRoster) -> void:
	data = d
	roster = r
	layer3 = DefLayer3.new(d, r)
	refresh()


## The single call the sim makes when a research completes.
func apply_research(research_idx: int) -> void:
	layer3.apply_research(research_idx)
	refresh()


## Recomputes the flat tables iff layer3.version != version.
func refresh() -> void:
	if version == layer3.version:
		return
	version = layer3.version
	_stats.clear()
	var nu: int = data.units.size()
	var ns: int = data.structures.size()
	unit_cost = _zeros(nu)
	unit_ticks = _zeros(nu)
	unit_available = _zeros(nu)
	unit_cap_cost = _zeros(nu)
	unit_rearm_ticks = _zeros(nu)
	unit_repair_cost_bp = _zeros(nu)
	struct_cost = _zeros(ns)
	struct_ticks = _zeros(ns)
	struct_available = _zeros(ns)
	struct_power = _zeros(ns)
	struct_repair_cost_bp = _zeros(ns)
	struct_repair_rate_bp = _zeros(ns)
	for i: int in nu:
		var u: DefUnit = roster.unit(i)
		if u == null:
			continue
		unit_cost[i] = layer3.effective_unit_stat(DefEnums.Stat.COST, i) if u.cost > 0 else u.cost
		unit_ticks[i] = layer3.effective_unit_stat(DefEnums.Stat.BUILD_TIME, i)
		unit_available[i] = 1 if (u.flags & DefEnums.UF_PRODUCIBLE) != 0 else 0
		unit_cap_cost[i] = u.pop
		unit_rearm_ticks[i] = layer3.effective_unit_stat(DefEnums.Stat.REARM, i)
		unit_repair_cost_bp[i] = layer3.effective_unit_stat(DefEnums.Stat.REPAIR_COST, i)
	for i: int in ns:
		var s: DefStructure = roster.structure(i)
		if s == null:
			continue
		struct_cost[i] = layer3.effective_struct_stat(DefEnums.Stat.COST, i)
		struct_ticks[i] = layer3.effective_struct_stat(DefEnums.Stat.BUILD_TIME, i)
		struct_available[i] = 1 if (s.flags & DefEnums.SF_NO_BUILD) == 0 else 0
		struct_power[i] = layer3.effective_struct_stat(DefEnums.Stat.POWER, i) if s.power > 0 else s.power
		struct_repair_cost_bp[i] = layer3.effective_struct_stat(DefEnums.Stat.REPAIR_COST, i)
		struct_repair_rate_bp[i] = layer3.effective_struct_stat(DefEnums.Stat.REPAIR_RATE, i)
	research_available = _zeros(data.research.size())
	for r: int in roster.research_list:
		if r >= 0 and r < research_available.size():
			research_available[r] = 1
	power_of_slot = roster.power_list.duplicate()
	super_idx = roster.superweapon


## Static + permanent-research stats of a def, indexed by DefEnums.Stat (0 where not applicable).
func resolved_stats(kind: int, def_idx: int) -> PackedInt32Array:
	var key: int = (kind << 24) | def_idx
	if _stats.has(key):
		return _stats[key]
	var out: PackedInt32Array = _zeros(DefEnums.Stat.COUNT)
	if kind == DefEnums.Kind.UNIT and def_idx >= 0 and def_idx < data.units.size():
		var cu: DefUnit = roster.unit(def_idx) if roster.has_unit(def_idx) else data.units[def_idx]
		for st: int in DefEnums.Stat.COUNT:
			out[st] = layer3.effective_unit_stat(st, def_idx) if DefLayer3.unit_stat_value(st, cu) != 0 else 0
	elif kind == DefEnums.Kind.STRUCTURE and def_idx >= 0 and def_idx < data.structures.size():
		var cs: DefStructure = roster.structure(def_idx) if roster.has_structure(def_idx) else data.structures[def_idx]
		for st2: int in DefEnums.Stat.COUNT:
			out[st2] = layer3.effective_struct_stat(st2, def_idx) if DefLayer3.struct_stat_value(st2, cs) != 0 else 0
	_stats[key] = out
	return out


## Unmodified base values (data.units / data.structures), same indexing as resolved_stats.
func base_stats(kind: int, def_idx: int) -> PackedInt32Array:
	var out: PackedInt32Array = _zeros(DefEnums.Stat.COUNT)
	if kind == DefEnums.Kind.UNIT and def_idx >= 0 and def_idx < data.units.size():
		_fill_unit(out, data.units[def_idx])
	elif kind == DefEnums.Kind.STRUCTURE and def_idx >= 0 and def_idx < data.structures.size():
		_fill_struct(out, data.structures[def_idx])
	return out


## The roster clone's weapon slot (null when absent).
func slot(unit_idx: int, slot_idx: int) -> DefWeaponSlot:
	var u: DefUnit = roster.unit(unit_idx)
	if u == null or slot_idx < 0 or slot_idx >= u.weapons.size():
		return null
	return u.weapons[slot_idx]


## damage / range / reload_mt / proj_speed of a slot after research (+ temporaries `extra_bp`).
func effective_slot_value(unit_idx: int, slot_idx: int, stat: int, extra_bp: int = 0) -> int:
	var s: DefWeaponSlot = slot(unit_idx, slot_idx)
	if s == null:
		return 0
	var base_u: DefUnit = data.units[unit_idx]
	var b: DefWeaponSlot = base_u.weapons[slot_idx] if slot_idx < base_u.weapons.size() else s
	var cur: int = 0
	var base_v: int = 0
	if stat == DefEnums.Stat.DAMAGE:
		cur = s.damage
		base_v = b.damage
	elif stat == DefEnums.Stat.RANGE:
		cur = s.range
		base_v = b.range
	elif stat == DefEnums.Stat.RELOAD:
		cur = s.reload_mt
		base_v = b.reload_mt
	elif stat == DefEnums.Stat.PROJ_SPEED:
		cur = s.proj_speed
		base_v = b.proj_speed
	else:
		return 0
	return DefStatMath.effective(stat, base_v, cur, layer3.unit_stat_bp(stat, unit_idx) + extra_bp, data.economy)


## Sum of unconditional research resistance (bp, uncapped) against a damage type.
func research_resist_bp(kind: int, def_idx: int, damage_type: int) -> int:
	if kind == DefEnums.Kind.UNIT:
		return layer3.unit_resist_bp(damage_type, def_idx)
	if kind == DefEnums.Kind.STRUCTURE:
		return layer3.struct_resist_bp(damage_type, def_idx)
	return 0


func checksum() -> int:
	return layer3.checksum()


static func _zeros(n: int) -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	a.resize(n)
	return a


static func _fill_unit(out: PackedInt32Array, u: DefUnit) -> void:
	for st: int in DefEnums.Stat.COUNT:
		out[st] = DefLayer3.unit_stat_value(st, u)


static func _fill_struct(out: PackedInt32Array, s: DefStructure) -> void:
	for st: int in DefEnums.Stat.COUNT:
		out[st] = DefLayer3.struct_stat_value(st, s)
