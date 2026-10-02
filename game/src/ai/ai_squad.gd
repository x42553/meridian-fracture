class_name AiSquad
extends RefCounted
## One tactical group (ai.md 4.3): plain data plus a few helpers. `units` is ascending by eid. `prio` decides who may take
## units from whom in AiSquadManager.claim (a claimer steals only from squads with a LOWER prio; the reserve has 0).
## Centroid, radius, value, hp fraction and the slowest speed are refreshed by AiSquadManager.refresh.

const PRIO_BY_KIND: PackedInt32Array = [0, 40, 40, 80, 50, 30, 45, 45, 60, 45, 35, 35, 35, 55, 35]  ## by AiTypes.SquadKind

var id: int = 0
var kind: int = AiTypes.SquadKind.RESERVE
var op_id: int = -1
var prio: int = 0
var units: PackedInt32Array = PackedInt32Array()
var cx: int = 0
var cy: int = 0
var radius: int = 0
var value: int = 0
var hp_frac_q8: int = 256
var speed_min: int = 0
var stage_x: int = 0
var stage_y: int = 0
var last_cmd_tick: int = AiTypes.NEVER
var role_counts: PackedInt32Array = PackedInt32Array()


func _init(p_id: int = 0, p_kind: int = AiTypes.SquadKind.RESERVE, p_op: int = -1) -> void:
	id = p_id
	kind = p_kind
	op_id = p_op
	prio = PRIO_BY_KIND[p_kind] if p_kind >= 0 and p_kind < PRIO_BY_KIND.size() else 40
	role_counts.resize(AiTypes.ROLE_COUNT)


func size() -> int:
	return units.size()


func has(eid: int) -> bool:
	var i: int = units.bsearch(eid)
	return i < units.size() and units[i] == eid


func add(eid: int) -> void:
	var i: int = units.bsearch(eid)
	if i < units.size() and units[i] == eid:
		return
	units.insert(i, eid)


func remove(eid: int) -> void:
	var i: int = units.bsearch(eid)
	if i < units.size() and units[i] == eid:
		units.remove_at(i)


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([id, kind, op_id, units.size(), cx, cy]))
