class_name SimEffectTable
extends RefCounted
## Flat, derived index of every compiled DefEffect of the data set (abilities 5.4: `fx_idx`). GameData has no global
## effect table (effects live inside research, power actions and zones), so the abilities domain flattens them once
## per world in a fixed order: research[0..], then powers[0..] (actions in order), then zones[0..]. The index is a pure
## function of the loaded data (covered by data_hash), so it is identical on every client and is never hashed.

var effects: Array[DefEffect] = []
## research_first[r] .. research_first[r + 1] - 1 = fx indices of research r (size = research count + 1).
var research_first: PackedInt32Array = PackedInt32Array()
var power_first: PackedInt32Array = PackedInt32Array()
var zone_first: PackedInt32Array = PackedInt32Array()


func _init(data: GameData) -> void:
	for r: DefResearch in data.research:
		research_first.append(effects.size())
		effects.append_array(r.effects)
	research_first.append(effects.size())
	for p: DefPower in data.powers:
		power_first.append(effects.size())
		for a: DefPowerAction in p.actions:
			effects.append_array(a.effects)
	power_first.append(effects.size())
	for z: DefZone in data.zones:
		zone_first.append(effects.size())
		effects.append_array(z.effects)
	zone_first.append(effects.size())


func size() -> int:
	return effects.size()


func get_effect(fx_idx: int) -> DefEffect:
	return effects[fx_idx] if fx_idx >= 0 and fx_idx < effects.size() else null


## fx index of a DefEffect instance, -1 when it is not part of the data set.
func index_of(fx: DefEffect) -> int:
	return effects.find(fx)


## fx_idx of the k-th effect of power p (flattened over its actions), -1 out of range.
func power_effect(p: int, k: int) -> int:
	if p < 0 or p + 1 >= power_first.size() or power_first[p] + k >= power_first[p + 1]:
		return -1
	return power_first[p] + k


func zone_effect(z: int, k: int) -> int:
	if z < 0 or z + 1 >= zone_first.size() or zone_first[z] + k >= zone_first[z + 1]:
		return -1
	return zone_first[z] + k


func research_effect(r: int, k: int) -> int:
	if r < 0 or r + 1 >= research_first.size() or research_first[r] + k >= research_first[r + 1]:
		return -1
	return research_first[r] + k
