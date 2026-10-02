class_name AiStrengthGroup
extends RefCounted
## Aggregated hp / dps-by-armor-class summary of a set of units or structures (ai.md 3.5 / 5.3.4); the input of
## AiStrength. All dps values are damage per second x 100 (the ratio is scale free).

const NCLASS: int = DefEnums.ArmorClass.COUNT

var hp: int = 0
var dps_x100_by_class: PackedInt32Array = PackedInt32Array()
var hp_by_class: PackedInt32Array = PackedInt32Array()
var avg_range: int = 0  ## dps-weighted range in units (1024 = 1 cell)
var value: int = 0  ## credits
var arty_dps_x100: int = 0  ## dps contributed by artillery-role members (artillery screen rule)
var arty_hp: int = 0
var count: int = 0
var _range_dps: int = 0  ## sum(range * dps_avg) for the weighting
var _dps_sum: int = 0


func _init() -> void:
	dps_x100_by_class.resize(NCLASS)
	dps_x100_by_class.fill(0)
	hp_by_class.resize(NCLASS)
	hp_by_class.fill(0)


## Adds `n` members of profile `p` with current hp `cur_hp` each (the def's full hp when < 0) and credit value `val`
## each (the def's cost when < 0).
func add(p: AiUnitProfile, n: int = 1, cur_hp: int = -1, val: int = -1) -> void:
	if p == null or n <= 0:
		return
	var h: int = (p.hp if cur_hp < 0 else cur_hp) * n
	hp += h
	hp_by_class[p.armor_class] += h
	value += (p.value if val < 0 else val) * n
	count += n
	var avg: int = p.dps_avg_x100()
	for c: int in NCLASS:
		dps_x100_by_class[c] += p.dps_x100[c] * n
	if avg > 0:
		_range_dps += p.range * avg * n
		_dps_sum += avg * n
		avg_range = _range_dps / maxi(_dps_sum, 1)
	if (p.role_mask & (1 << AiTypes.R_ARTILLERY)) != 0 or (p.tag_mask & DefEnums.UT_ARTILLERY) != 0:
		arty_dps_x100 += avg * n
		arty_hp += h


## `add` scaled by `pct` percent (hp, dps and value): a defensive structure that fights harder than its sheet says (repair, cover).
func add_pct(p: AiUnitProfile, cur_hp: int, val: int, pct: int) -> void:
	if p == null or pct <= 0:
		return
	var h: int = (p.hp if cur_hp < 0 else cur_hp) * pct / 100
	hp += h
	hp_by_class[p.armor_class] += h
	value += (p.value if val < 0 else val) * pct / 100
	count += 1
	var avg: int = p.dps_avg_x100() * pct / 100
	for c: int in NCLASS:
		dps_x100_by_class[c] += p.dps_x100[c] * pct / 100
	if avg > 0:
		_range_dps += p.range * avg
		_dps_sum += avg
		avg_range = _range_dps / maxi(_dps_sum, 1)


## Removes `pct` percent of what `other` contributed (it must have been added into this group before): the artillery siege
## discount of the defensive structures in the wave ratio.
func discount(other: AiStrengthGroup, pct: int) -> void:
	hp = maxi(hp - other.hp * pct / 100, 1)
	value = maxi(value - other.value * pct / 100, 0)
	for c: int in NCLASS:
		dps_x100_by_class[c] = maxi(dps_x100_by_class[c] - other.dps_x100_by_class[c] * pct / 100, 0)
		hp_by_class[c] = maxi(hp_by_class[c] - other.hp_by_class[c] * pct / 100, 0)


func total_dps_x100() -> int:
	var s: int = 0
	for v: int in dps_x100_by_class:
		s += v
	return s


func is_empty() -> bool:
	return count == 0 and hp == 0
