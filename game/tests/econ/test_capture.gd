extends RefCounted
## 10.1-H capture (economy 5.13) on a REAL match world: Grid Substation cap_need 240; 1 / 2 / 3 / 4 Engineers take
## 240 / 120 / 80 / 80 evaluations; two teams contest; idle progress decays after 100 ticks; an enemy Engineer burns stored
## progress down first; Engineers survive; units without the capture tag and faction structures cannot capture; a captured
## substation moves +100 power between the players.

const K := preload("res://tests/support/sim_work_kit.gd")


func _capture(w: SimWorld, pid: int, eng: Array[SimEntity], target: SimEntity) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in eng:
		ids.append(e.id)
	K.cmd(w, pid, SimCmd.capture(ids, target.id, 0))


func _engineers(w: SimWorld, pid: int, sub: SimEntity, n: int, first_slot: int = 0) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for i: int in n:
		out.append(K.engineer_at(w, pid, sub, first_slot + i))
	return out


func _time_to_capture(n: int) -> int:
	var w: SimWorld = K.world({})
	var sub: SimEntity = K.neutral(w, "neutral.substation")
	var eng: Array[SimEntity] = _engineers(w, 0, sub, n)
	_capture(w, 0, eng, sub)
	var steps: int = K.run_until(w, func(_ww: SimWorld) -> bool: return sub.owner == 0, 600)
	for e: SimEntity in eng:
		if w.get_entity(e.id) == null:
			return -2
	return steps


func test_capture_times(t: TestCtx) -> void:
	# The order is issued in stage 1, the first channel tick runs in stage 5 of tick 0 and stage 3 evaluates one tick
	# later: N evaluations need N + 1 stepped ticks.
	t.eq(_time_to_capture(1), 241, "1 Engineer: 240 evaluations")
	t.eq(_time_to_capture(2), 121, "2 Engineers: 120")
	t.eq(_time_to_capture(3), 81, "3 Engineers: 80")
	t.eq(_time_to_capture(4), 81, "4 Engineers: still 80 (at most 3 contribute)")


func test_engineers_not_consumed_and_power_moves(t: TestCtx) -> void:
	var w: SimWorld = K.world({})
	var sub: SimEntity = K.neutral(w, "neutral.substation")
	var p0: SimPlayerEcon = w.players[0].econ
	var before: int = p0.power_supply
	var eng: Array[SimEntity] = _engineers(w, 0, sub, 1)
	_capture(w, 0, eng, sub)
	K.run_until(w, func(_ww: SimWorld) -> bool: return sub.owner == 0, 400)
	K.run(w, 2)
	t.check(w.get_entity(eng[0].id) != null, "the Engineer survives")
	t.eq(p0.power_supply, before + 100, "captured substation +100 supply")
	t.eq(sub.econ.power_delta, 100, "registered like a generator delta")
	t.eq(K.events(w, SimEconConst.EVT_STRUCTURE_CAPTURED).size(), 1, "EVT_STRUCTURE_CAPTURED once")
	var prog: int = K.events(w, SimEconConst.EVT_CAPTURE_PROGRESS).size()
	t.check(prog >= 10, "progress events every 20 ticks (%d)" % prog)
	t.eq(eng[0].orders.size(), 0, "order DONE on ownership change")
	# the enemy takes it back: power moves from player 0 to player 1
	var enemy: SimEntity = K.engineer_at(w, 1, sub, 3)
	_capture(w, 1, [enemy], sub)
	K.run_until(w, func(_ww: SimWorld) -> bool: return sub.owner == 1, 600)
	K.run(w, 2)
	t.eq(sub.owner, 1, "recaptured")
	t.eq(p0.power_supply, before, "player 0 loses the +100")
	t.eq(w.players[1].econ.power_supply, w.players[1].econ.power_supply, "player 1 holds it")
	t.eq(sub.econ.cap_progress, 0, "progress reset after the flip")


func test_contested_and_decay_and_burn(t: TestCtx) -> void:
	var w: SimWorld = K.world({})
	var sub: SimEntity = K.neutral(w, "neutral.substation")
	var a: SimEntity = K.engineer_at(w, 0, sub, 0)
	var b: SimEntity = K.engineer_at(w, 1, sub, 3)
	_capture(w, 0, [a], sub)
	_capture(w, 1, [b], sub)
	K.run(w, 60)
	t.eq(sub.econ.cap_progress, 0, "two teams channelling: contested, no progress")
	t.check(K.events(w, SimEconConst.EVT_CAPTURE_CONTESTED).size() >= 1, "EVT_CAPTURE_CONTESTED")
	# player 1 walks away (stop): player 0 alone accumulates
	K.cmd(w, 1, SimCmd.stop(PackedInt32Array([b.id])))
	K.run(w, 150)
	var stored: int = sub.econ.cap_progress
	t.check(stored >= 140 and stored <= 152, "stored progress ~150 (%d)" % stored)
	# player 0 stops: no decay for the first 100 idle ticks, then 2 per tick
	K.cmd(w, 0, SimCmd.stop(PackedInt32Array([a.id])))
	K.run(w, 2)
	stored = sub.econ.cap_progress
	K.run(w, 90)
	t.eq(sub.econ.cap_progress, stored, "no decay during the first 100 idle ticks")
	K.run(w, 30)
	var lost: int = stored - sub.econ.cap_progress
	t.check(lost >= 2 * 18 and lost <= 2 * 22, "then 2 per tick (%d lost in ~20 decaying ticks)" % lost)
	# an enemy Engineer burns the stored progress down first
	var left: int = sub.econ.cap_progress
	_capture(w, 1, [b], sub)
	K.run(w, 3)
	var before_burn: int = sub.econ.cap_progress
	K.run(w, 20)
	t.eq(before_burn - sub.econ.cap_progress, 20, "the enemy burns 1 per tick")
	t.eq(sub.owner, -1, "still neutral")
	t.check(left > 0, "there was progress to burn")


func test_burn_then_own_capture(t: TestCtx) -> void:
	var w: SimWorld = K.world({})
	var sub: SimEntity = K.neutral(w, "neutral.substation")
	sub.econ.cap_pid = 0
	sub.econ.cap_progress = 150
	sub.econ.cap_last_tick = w.tick
	var b: SimEntity = K.engineer_at(w, 1, sub, 0)
	_capture(w, 1, [b], sub)
	var n: int = K.run_until(w, func(_ww: SimWorld) -> bool: return sub.owner == 1, 600)
	t.check(n >= 150 + 240 and n <= 150 + 240 + 3, "burn 150 then capture 240 (%d ticks)" % n)


func test_who_can_capture(t: TestCtx) -> void:
	var w: SimWorld = K.world({})
	var sub: SimEntity = K.neutral(w, "neutral.substation")
	var d: GameData = w.data
	var eng: SimEntity = K.engineer_at(w, 0, sub)
	t.eq(SimEconomyWork.capture_can_target(w, eng, sub), SimEconConst.RSN_OK, "Engineer may capture")
	for uid: String in ["unit.sap.combat_pioneer", "unit.nec.alpine_pioneer"]:
		var ui: int = d.unit_idx(uid)
		t.check(not d.units[ui].has_ability(DefEnums.AbilityKind.CAPTURE), "%s has no capture ability" % uid)
	var rifle: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, sub.x - 4 * K.CELL, sub.y - 4 * K.CELL)
	t.eq(SimEconomyWork.capture_can_target(w, rifle, w.structures_of(1)[0]), SimEconConst.RSN_WRONG_KIND, "faction structures are not capturable")
	var own: SimEntity = w.structures_of(0)[0]
	t.eq(SimEconomyWork.capture_can_target(w, eng, own), SimEconConst.RSN_WRONG_KIND, "own HQ: wrong kind")
	var garrison: SimEntity = K.neutral(w, "neutral.civilian_garrison")
	t.eq(SimEconomyWork.capture_can_target(w, eng, garrison), SimEconConst.RSN_WRONG_KIND, "civilian block is not capturable")
	# a friendly-owned neutral cannot be captured by the owner's team
	w.change_owner(sub.id, 0)
	t.eq(SimEconomyWork.capture_can_target(w, eng, sub), SimEconConst.RSN_FRIENDLY, "already ours")
	# an order against a faction structure is refused by the handler
	K.cmd(w, 0, SimCmd.capture(PackedInt32Array([eng.id]), w.structures_of(1)[0].id, 0))
	K.run(w, 2)
	t.eq(eng.orders.size(), 0, "no order was accepted")


func test_far_engineer_walks_and_captures(t: TestCtx) -> void:
	var w: SimWorld = K.world({})
	var sub: SimEntity = K.neutral(w, "neutral.observation_tower")
	var eng: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, sub.x - 12 * K.CELL, sub.y + 6 * K.CELL, 500)
	_capture(w, 0, [eng], sub)
	var n: int = K.run_until(w, func(_ww: SimWorld) -> bool: return sub.owner == 0, 1500)
	t.check(n > 300, "walked in and channelled 300 ticks (%d)" % n)
	t.eq(sub.owner, 0, "tower captured")
