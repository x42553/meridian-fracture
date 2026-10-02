class_name SimWorkDriver
extends RefCounted
## A tiny deterministic "engineer brain" for scenarios (EC3A): every DECIDE ticks each idle Engineer-class unit of the given
## players salvages the nearest enemy wreck it may, else captures the nearest neutral structure of the players' team, else
## repairs the nearest damaged friendly vehicle. Commands only (SimCmd through world.submit_raw), like the bots.

const DECIDE: int = 20

var pids: PackedInt32Array = PackedInt32Array()
var salvaged_orders: int = 0
var capture_orders: int = 0
var repair_orders: int = 0


func _init(p_pids: PackedInt32Array) -> void:
	pids = p_pids


func think(w: SimWorld) -> void:
	if w.tick % DECIDE != 0:
		return
	for pid: int in pids:
		for u: SimEntity in w.units_of(pid):
			if (u.flags & SimFlags.F_GONE) != 0 or not u.orders.is_empty():
				continue
			var ud: DefUnit = SimEconomyWork.udef(w, u)
			if not (ud.has_ability(DefEnums.AbilityKind.CAPTURE) or ud.has_ability(DefEnums.AbilityKind.SALVAGE) or ud.has_ability(DefEnums.AbilityKind.REPAIR)):
				continue
			_decide(w, pid, u)


func _decide(w: SimWorld, pid: int, u: SimEntity) -> void:
	var best: int = 0
	var best_d: int = 0
	var ids: PackedInt32Array = PackedInt32Array([u.id])
	if SimEconomyWork.salvage_ability(w, u) != null:
		for id: int in w.combat.wreck_ids:
			var wr: SimEntity = w.get_entity(id)
			if wr == null or SimEconomyWork.salvage_can_target(w, u, wr) != SimEconConst.RSN_OK:
				continue
			var d: int = _d2(u, wr)
			if best == 0 or d < best_d:
				best = id
				best_d = d
		if best != 0:
			w.submit_raw(pid, SimCmd.salvage(ids, best, 0))
			salvaged_orders += 1
			return
	if SimEconomyWork.can_capture(w, u):
		for n: SimEntity in w.neutrals:
			if SimEconomyWork.capture_can_target(w, u, n) != SimEconConst.RSN_OK or n.owner >= 0 and w.team_of(n.owner) == w.team_of(pid):
				continue
			var d2: int = _d2(u, n)
			if best == 0 or d2 < best_d:
				best = n.id
				best_d = d2
		if best != 0:
			w.submit_raw(pid, SimCmd.capture(ids, best, 0))
			capture_orders += 1
			return
	if SimEconomyWork.repair_ability(w, u) != null:
		for t: SimEntity in w.units_of(pid):
			if t.hp >= t.hp_max or SimEconomyWork.repair_can_target(w, u, t) != SimEconConst.RSN_OK:
				continue
			var d3: int = _d2(u, t)
			if best == 0 or d3 < best_d:
				best = t.id
				best_d = d3
		if best != 0:
			w.submit_raw(pid, SimCmd.repair(ids, best, 0))
			repair_orders += 1


static func _d2(a: SimEntity, b: SimEntity) -> int:
	var dx: int = (a.x - b.x) >> 4
	var dy: int = (a.y - b.y) >> 4
	return dx * dx + dy * dy


## Spawns `n` Engineers next to the player's HQ (paid 500 each, ignoring the unit cap like a debug spawn).
static func spawn_engineers(w: SimWorld, pid: int, n: int) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	var hq: SimEntity = w.structures_of(pid)[0]
	var idx: int = w.data.unit_idx("unit.shared.engineer")
	for i: int in n:
		var cell: int = SimMovement.find_free_cell_near(w, w.map.idx((hq.x >> SimConfig.CELL_SHIFT) + 4 + i, (hq.y >> SimConfig.CELL_SHIFT) + 6), SimEntity.Layer.GROUND, 8)
		if cell < 0:
			continue
		var u: SimEntity = w.spawn_unit(idx, pid, w.map.center_x(cell), w.map.center_y(cell), 0, 0, 500)
		if u != null:
			out.append(u)
	return out
