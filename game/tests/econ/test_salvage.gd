extends RefCounted
## 10.1-I salvage (economy 5.12) on REAL match worlds: the wreck creation matrix (combat's death sequence), the African Empire
## salvage action (160 ticks, 20 % of the paid price, once per wreck), the uninterrupted rule, research / knob durations, the
## claim, frozen expiry and the who-may-salvage checks.

const K := preload("res://tests/support/sim_work_kit.gd")


func _world() -> SimWorld:
	return K.world({"credits": 20000, "rosters": PackedStringArray([K.AE, K.NAPC])})


## Kills an NAPC tank (paid `paid`) by an AE hand and returns the wreck entity (null if none appeared).
func _wreck(w: SimWorld, paid: int = 1100, victim: String = "unit.napc.guardian_tank", killer_pid: int = 0) -> SimEntity:
	var hq: SimEntity = w.structures_of(1)[0]
	var tank: SimEntity = K.unit_near(w, victim, 1, hq.x + 6 * K.CELL, hq.y + 6 * K.CELL, paid)
	w.combat.kill(w, tank, SimCombatConsts.CAUSE_DAMAGE, -1, killer_pid)
	K.run(w, 2)
	for id: int in w.combat.wreck_ids:
		var e: SimEntity = w.get_entity(id)
		if e != null and absi(e.x - tank.x) < 2048 and absi(e.y - tank.y) < 2048:
			return e
	return null


func test_wreck_creation_matrix(t: TestCtx) -> void:
	var w: SimWorld = _world()
	t.not_null(_wreck(w), "enemy-killed tank leaves a wreck")
	var hq1: SimEntity = w.structures_of(1)[0]
	var n0: int = w.combat.wreck_ids.size()
	var inf: SimEntity = K.unit_near(w, "unit.shared.engineer", 1, hq1.x - 6 * K.CELL, hq1.y, 500)
	w.combat.kill(w, inf, SimCombatConsts.CAUSE_DAMAGE, -1, 0)
	var ff: SimEntity = K.unit_near(w, "unit.napc.guardian_tank", 1, hq1.x + 12 * K.CELL, hq1.y + 6 * K.CELL, 1100)
	w.combat.kill(w, ff, SimCombatConsts.CAUSE_DAMAGE, -1, 1)  # killed by its own owner
	var scut: SimEntity = K.unit_near(w, "unit.napc.guardian_tank", 1, hq1.x + 3 * K.CELL, hq1.y + 12 * K.CELL, 1100)
	w.combat.scuttle(w, scut)
	var free: SimEntity = K.unit_near(w, "unit.napc.guardian_tank", 1, hq1.x - 3 * K.CELL, hq1.y + 12 * K.CELL, 0)
	w.combat.kill(w, free, SimCombatConsts.CAUSE_DAMAGE, -1, 0)  # paid_cost 0
	K.run(w, 3)
	t.eq(w.combat.wreck_ids.size(), n0, "infantry, friendly fire, scuttle and free units leave no wreck")
	# no salvage-capable player: no wrecks at all
	var w2: SimWorld = K.world({"rosters": PackedStringArray([K.NAPC, K.NEC])})
	t.check(_wreck(w2) == null, "wrecks exist only when some roster can salvage")


func test_salvage_pays_20_percent_after_160_ticks(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var wr: SimEntity = _wreck(w, 1100)
	var eng: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, wr.x + K.CELL, wr.y, 500)
	var c0: int = w.players[0].credits
	K.cmd(w, 0, SimCmd.salvage(PackedInt32Array([eng.id]), wr.id, 0))
	var n: int = K.run_until(w, func(ww: SimWorld) -> bool: return ww.players[0].econ.stat_salvaged > 0, 400)
	t.check(n >= 160 and n <= 166, "work time 160 ticks once in reach (%d)" % n)
	t.eq(w.players[0].credits - c0, 220, "20 % of the paid 1100")
	t.eq(w.players[0].econ.stat_salvaged, 220, "statistic")
	K.run(w, 3)
	t.check(w.get_entity(wr.id) == null, "the wreck is removed")
	t.eq(K.events(w, SimEconConst.EVT_SALVAGE_PAID).size(), 1, "EVT_SALVAGE_PAID once")
	t.eq(K.events(w, SimEconConst.EVT_SALVAGE_STARTED).size(), 1, "EVT_SALVAGE_STARTED once")
	t.check(eng.orders.is_empty(), "order DONE")
	t.eq(w.economy.q_salvage_share_bp(0), 10000 * 220 / (w.players[0].econ.stat_harvested + 220 + w.players[0].econ.stat_depot), "salvage share of income is tracked")


func test_interrupt_resets_progress(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var wr: SimEntity = _wreck(w, 1100)
	var eng: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, wr.x + K.CELL, wr.y, 500)
	K.cmd(w, 0, SimCmd.salvage(PackedInt32Array([eng.id]), wr.id, 0))
	K.run(w, 100)
	t.eq(wr.econ.unit_repairer_id, eng.id, "claimed while working")
	K.cmd(w, 0, SimCmd.stop(PackedInt32Array([eng.id])))
	K.run(w, 2)
	t.eq(wr.econ.unit_repairer_id, 0, "the claim is freed by the order change")
	t.eq(w.players[0].econ.stat_salvaged, 0, "nothing paid")
	K.cmd(w, 0, SimCmd.salvage(PackedInt32Array([eng.id]), wr.id, 0))
	var n: int = K.run_until(w, func(ww: SimWorld) -> bool: return ww.players[0].econ.stat_salvaged > 0, 400)
	t.check(n >= 160, "the interrupted work started over from 0 (%d)" % n)


func test_durations_winches_and_priority(t: TestCtx) -> void:
	for cfg: Array in [[100, 100], [60, 60]]:
		var w: SimWorld = _world()
		w.economy.set_knob_base(w, 0, SimEconConst.K_SALVAGE_TICKS, cfg[0])
		var wr: SimEntity = _wreck(w, 1100)
		var eng: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, wr.x + K.CELL, wr.y, 500)
		K.cmd(w, 0, SimCmd.salvage(PackedInt32Array([eng.id]), wr.id, 0))
		var n: int = K.run_until(w, func(ww: SimWorld) -> bool: return ww.players[0].econ.stat_salvaged > 0, 300)
		t.check(n >= cfg[1] and n <= cfg[1] + 6, "knob %d -> %d ticks (%d)" % [cfg[0], cfg[1], n])
		t.eq(w.players[0].econ.stat_salvaged, 220, "the payout never changes with research")
	# Recovery Priority is a MIN-mode temporary layer
	var w3: SimWorld = _world()
	w3.economy.set_knob_temp(0, SimEconConst.K_SALVAGE_TICKS, 60, w3.tick + 1000)
	t.eq(w3.economy.knob(0, SimEconConst.K_SALVAGE_TICKS), 60, "MIN(160, 60)")


func test_who_and_what(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var wr: SimEntity = _wreck(w, 1100)
	var ae_eng: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, wr.x + 2 * K.CELL, wr.y, 500)
	var napc_eng: SimEntity = K.unit_near(w, "unit.shared.engineer", 1, wr.x - 2 * K.CELL, wr.y, 500)
	t.eq(SimEconomyWork.salvage_can_target(w, ae_eng, wr), SimEconConst.RSN_OK, "AE Engineer may salvage an enemy wreck")
	t.eq(SimEconomyWork.salvage_can_target(w, napc_eng, wr), SimEconConst.RSN_WRONG_KIND, "a non-AE Engineer cannot")
	var rec: SimEntity = K.unit_near(w, "unit.ae.reclaimer", 0, wr.x, wr.y + 2 * K.CELL, 545)
	t.eq(SimEconomyWork.salvage_can_target(w, rec, wr), SimEconConst.RSN_OK, "Reclaimer may")
	# a wreck of player 1's tank (killed by player 0) is worthless to player 2 when 2 is on player 1's team
	var w2: SimWorld = K.world({"credits": 20000, "rosters": PackedStringArray([K.AE, K.NAPC, K.AE]), "teams": PackedInt32Array([1, 2, 2])})
	var wr2: SimEntity = _wreck(w2, 1100, "unit.napc.guardian_tank", 0)
	t.check(wr2 != null, "wreck of an enemy killed by player 0")
	var e2: SimEntity = K.unit_near(w2, "unit.shared.engineer", 2, wr2.x + K.CELL, wr2.y, 500)
	t.eq(SimEconomyWork.salvage_can_target(w2, e2, wr2), SimEconConst.RSN_FRIENDLY, "an ally of the wreck's owner earns nothing")
	var e0: SimEntity = K.unit_near(w2, "unit.shared.engineer", 0, wr2.x - K.CELL, wr2.y, 500)
	t.eq(SimEconomyWork.salvage_can_target(w2, e0, wr2), SimEconConst.RSN_OK, "the enemy team may")
	# claimed by another salvager: BUSY; expiring: EXPIRING
	var eng_b: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, wr.x - 2 * K.CELL, wr.y + 2 * K.CELL, 500)
	SimEconomyWork.salvage_begin(w, ae_eng, wr, 160)
	t.eq(SimEconomyWork.salvage_can_target(w, eng_b, wr), SimEconConst.RSN_BUSY, "claimed wreck is BUSY")
	SimEconomyWork.release_claim(wr.econ, ae_eng.id)
	wr.combat.wreck_expire = w.tick + 100
	t.eq(SimEconomyWork.salvage_can_target(w, eng_b, wr), SimEconConst.RSN_EXPIRING, "less life than the action time")


func test_expiry_frozen_while_claimed_and_pays_once(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var wr: SimEntity = _wreck(w, 1100)
	var exp0: int = wr.combat.wreck_expire
	var eng: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, wr.x + K.CELL, wr.y, 500)
	wr.combat.wreck_expire = w.tick + 170
	wr.expire_tick = w.tick + 170
	K.cmd(w, 0, SimCmd.salvage(PackedInt32Array([eng.id]), wr.id, 0))
	K.run_until(w, func(ww: SimWorld) -> bool: return ww.players[0].econ.stat_salvaged > 0, 400)
	t.eq(w.players[0].econ.stat_salvaged, 220, "paid although the unclaimed life would have ended")
	# a second salvager on the consumed wreck
	var eng2: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, wr.x - K.CELL, wr.y, 500)
	K.cmd(w, 0, SimCmd.salvage(PackedInt32Array([eng2.id]), wr.id, 0))
	K.run(w, 5)
	t.check(eng2.orders.is_empty(), "the wreck pays once")
	t.check(exp0 > 0, "wreck had an expiry")
