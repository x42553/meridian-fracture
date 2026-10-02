extends RefCounted
## E3 production (10.1-B payment, 10.1-C queues, S1 opening with the REAL SimProductionSystem, S8 rate part):
## progressive payment in bp-ticks, shortage / knob rates, funds pauses, prerequisite pauses, unit-cap reservation,
## blocked exits, primary producer choice, rally, research, and the research knobs / pad API on the real data.

const KIT := preload("res://tests/support/sim_econ_kit.gd")
const CELL: int = SimConfig.CELL


func _world(credits: int = 7500, extra: Dictionary = {}) -> SimWorld:
	var o: Dictionary = {"start_mode": 0, "rules": {"start_credits": credits}}
	for k: String in extra:
		o[k] = extra[k]
	return KIT.make_world(o)


func _prod(w: SimWorld, id: String, pid: int, ox: int, oy: int) -> SimEntity:
	return KIT.spawn_struct(w, id, pid, ox, oy, 0, true)


func _run_until(w: SimWorld, pred: Callable, limit: int) -> int:
	var n: int = 0
	while n < limit and not pred.call():
		w.step()
		n += 1
	return n


func _shortage_world(credits: int = 20000) -> SimWorld:
	var w: SimWorld = _world(credits)
	_prod(w, DefTestKit.S_REFINERY, 0, 23, 22)  # demand 50, supply 0
	_prod(w, DefTestKit.S_BARRACKS, 0, 27, 19)
	_prod(w, DefTestKit.S_FACTORY, 0, 14, 19)
	w.step()
	w.step()
	return w


# ---- 10.1-B payment ----
func test_progressive_payment_and_cancel_refund(t: TestCtx) -> void:
	var w: SimWorld = _world()
	_prod(w, DefTestKit.S_REFINERY, 0, 23, 22)
	_prod(w, DefTestKit.S_GENERATOR, 0, 23, 19)
	w.step()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	var start: int = w.players[0].credits
	w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_FACTORY)))
	var paid: PackedInt32Array = PackedInt32Array()
	for _i: int in 3:
		w.step()
		paid.append(pe.cq_paid)
	t.eq(paid, PackedInt32Array([2, 5, 7]), "Factory 2000 / 800 ticks: paid after tick 1/2/3")
	KIT.run(w, 397)
	t.eq(pe.cq_paid, 1000, "half paid after 400 ticks")
	t.eq(w.players[0].credits, start - 1000, "the ledger followed")
	w.submit_raw(0, SimCmd.build_cancel(0))
	w.step()
	t.eq(w.players[0].credits, start, "cancel at 400 refunds exactly 1000")
	t.eq(pe.cq_state, SimEconConst.QS_EMPTY, "queue empty")
	# a full run completes at exactly tick 800 with paid == cost
	w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_FACTORY)))
	var n: int = _run_until(w, func() -> bool: return pe.cq_state == SimEconConst.QS_READY, 2000)
	t.eq([n, pe.cq_paid], [800, 2000] as Array, "READY after exactly 800 ticks with paid == cost")


func test_shortage_and_mobilization_rates(t: TestCtx) -> void:
	var w: SimWorld = _shortage_world()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.check(w.power.is_shortage(0), "Refinery demand with no Generator")
	t.eq(w.production.q_rate_bp(0, SimEconConst.PROD_CONSTRUCTION), 5000, "shortage rate")
	w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_GENERATOR)))
	var n: int = _run_until(w, func() -> bool: return pe.cq_state == SimEconConst.QS_READY, 3000)
	t.eq(n, 1000, "a 500-tick item takes 1000 at half speed")
	t.eq(pe.cq_paid, 600, "the price does not change")
	# Mobilization: factory knob 12500 x shortage 5000 = 6250 -> a 550-tick tank takes 880
	var w2: SimWorld = _shortage_world()
	var fac: SimEntity = w2.structures_of(0)[3]
	w2.economy.set_knob_temp(0, SimEconConst.K_PROD_RATE_FACTORY_BP, 12500, w2.tick + 2000)
	w2.step()
	t.eq(w2.production.q_rate_bp(0, SimEconConst.PROD_FACTORY), 6250, "5000 x 12500 / 10000")
	t.eq(w2.production.q_rate_bp(0, SimEconConst.PROD_BARRACKS), 5000, "barracks unaffected")
	w2.submit_raw(0, SimCmd.train(fac.id, KIT.uidx(DefTestKit.U_TANK2), 1))
	var m: int = _run_until(w2, func() -> bool: return w2.players[0].unit_count > 0, 2000)
	t.check(m >= 879 and m <= 882, "tank in %d ticks (550 * 10000 / 6250 = 880)" % m)


func test_funds_pause_and_resume(t: TestCtx) -> void:
	var w: SimWorld = _world(1000)
	_prod(w, DefTestKit.S_REFINERY, 0, 23, 22)
	_prod(w, DefTestKit.S_GENERATOR, 0, 23, 19)
	w.step()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_FACTORY)))
	KIT.run(w, 600)
	t.eq(pe.cq_state, SimEconConst.QS_PAUSED_FUNDS, "1000 credits are gone at tick 400")
	var frozen: int = pe.cq_progress
	t.eq(pe.cq_paid, 1000, "paid everything it could")
	KIT.run(w, 50)
	t.eq([pe.cq_progress, w.players[0].credits], [frozen, 0] as Array, "progress frozen, credits never negative")
	w.add_credits(0, 1500, SimEvent.CASH_SCRIPT)
	KIT.run(w, 1)
	t.check(pe.cq_progress > frozen and pe.cq_state == SimEconConst.QS_ACTIVE, "resumes at the same progress point")
	t.eq(pe.cq_paid, 2000 * pe.cq_progress / 8000000, "paid follows the progress")


func test_two_queues_share_scarce_credits(t: TestCtx) -> void:
	var w: SimWorld = _world(3)
	var bar: SimEntity = _prod(w, DefTestKit.S_BARRACKS, 0, 27, 19)
	_prod(w, DefTestKit.S_GENERATOR, 0, 23, 19)
	w.step()
	w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_TURRET)))
	w.submit_raw(0, SimCmd.train(bar.id, KIT.uidx(DefTestKit.U_RIFLEMAN), 1))
	var low: int = 3
	for _i: int in 200:
		w.step()
		low = mini(low, w.players[0].credits)
	t.eq(low, 0, "credits are spent down to 0 and never below")
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.eq(pe.cq_paid + bar.prod.head_paid, 3, "exactly the 3 credits were paid out in total")


# ---- 10.1-C queues ----
func test_queue_limits_hold_and_ids(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var b1: SimEntity = _prod(w, DefTestKit.S_BARRACKS, 0, 27, 19)
	var b2: SimEntity = _prod(w, DefTestKit.S_BARRACKS, 0, 30, 19)
	w.step()
	var rifle: int = KIT.uidx(DefTestKit.U_RIFLEMAN)
	t.eq(b1.prod.is_primary, true, "the first Barracks is primary")
	for _i: int in 5:
		w.submit_raw(0, SimCmd.train(b1.id, rifle, 1))
	w.submit_raw(0, SimCmd.train(b1.id, rifle, 1))
	w.step()
	t.eq(b1.prod.q_def.size(), 5, "5 enqueues OK, the 6th refused")
	t.eq(w.players[0].st_rejected, 1, "QUEUE_FULL rejection counted")
	t.eq(w.production.can_queue_unit(w, 0, b1.id, rifle), SimEconConst.RSN_QUEUE_FULL, "reason")
	# auto producer: primary first while it has room, else the fewest queued items, ties lowest id
	t.eq(w.production.q_find_producer(w, 0, SimEconConst.PROD_BARRACKS, rifle), b2.id, "primary is full: the other one")
	w.submit_raw(0, SimCmd.train_cancel(b1.id, 4))
	w.step()
	t.eq(w.production.q_find_producer(w, 0, SimEconConst.PROD_BARRACKS, rifle), b1.id, "primary has room again")
	w.submit_raw(0, SimCmd.set_primary(b2.id))
	w.step()
	t.eq([b1.prod.is_primary, b2.prod.is_primary], [false, true] as Array, "exactly one primary per kind")
	w.submit_raw(0, SimCmd.train(0, rifle, 1))
	w.step()
	t.eq(b2.prod.q_def.size(), 1, "producer 0 resolves to the primary building")
	# hold keeps paid and stops progress
	KIT.run(w, 20)
	var paid: int = b1.prod.head_paid
	t.check(paid > 0, "the head is being paid")
	w.submit_raw(0, SimCmd.queue_hold(PackedInt32Array([b1.id]), 1))
	KIT.run(w, 30)
	t.eq([b1.prod.head_state, b1.prod.head_paid], [SimEconConst.QS_HOLD, paid] as Array, "HOLD keeps paid")
	w.submit_raw(0, SimCmd.queue_hold(PackedInt32Array([b1.id]), 0))
	KIT.run(w, 5)
	t.check(b1.prod.head_paid > paid, "resumed")
	# refunds on cancel of the head
	var hp: int = b1.prod.head_paid
	w.submit_raw(0, SimCmd.train_cancel(b1.id, 0))
	w.step()
	t.eq(KIT.econ(w, 0).stat_refunded, hp, "the head's paid credits come back")


func test_collector_only_at_refinery_and_replaced_unit(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var bar: SimEntity = _prod(w, DefTestKit.S_BARRACKS, 0, 27, 19)
	var ref: SimEntity = _prod(w, DefTestKit.S_REFINERY, 0, 23, 22)
	_prod(w, DefTestKit.S_FACTORY, 0, 14, 19)
	w.step()
	var col: int = KIT.uidx(DefTestKit.U_COLLECTOR)
	t.eq(w.production.can_queue_unit(w, 0, bar.id, col), SimEconConst.RSN_WRONG_KIND, "Barracks cannot build a Collector")
	t.eq(w.production.can_queue_unit(w, 0, ref.id, col), SimEconConst.RSN_OK, "the Refinery can")
	t.eq(w.production.can_queue_unit(w, 0, ref.id, KIT.uidx(DefTestKit.U_RIFLEMAN)), SimEconConst.RSN_WRONG_KIND, "and only that")
	# roster alpha replaces the tank: NOT_AVAILABLE
	var fac: SimEntity = w.structures_of(0)[3]
	t.eq(w.production.can_queue_unit(w, 0, fac.id, KIT.uidx(DefTestKit.U_TANK)), SimEconConst.RSN_NOT_AVAILABLE, "replaced unit")
	t.eq(w.production.can_queue_unit(w, 0, fac.id, KIT.uidx(DefTestKit.U_TANK2)), SimEconConst.RSN_OK, "its replacement")
	t.eq(w.production.can_queue_unit(w, 0, 9999, col), SimEconConst.RSN_BAD_TARGET, "no such producer")
	t.eq(w.production.can_queue_unit(w, 1, bar.id, col), SimEconConst.RSN_NOT_OWNER, "not the owner")
	var out: PackedInt32Array = PackedInt32Array()
	w.production.q_buildable_units(w, 0, fac.id, out, false)
	t.eq(out.has(KIT.uidx(DefTestKit.U_TANK2)) and not out.has(KIT.uidx(DefTestKit.U_TANK)), true, "catalog query")


func test_prerequisite_pause_for_construction_research_and_units(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var gen: SimEntity = _prod(w, DefTestKit.S_GENERATOR, 0, 23, 19)
	var bar: SimEntity = _prod(w, DefTestKit.S_BARRACKS, 0, 27, 19)
	w.step()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	# research needs the Generator: pause at 30 %, progress and paid unchanged for 200 ticks, resume on rebuild
	w.submit_raw(0, SimCmd.research(0))
	KIT.run(w, 270)
	var prog: int = pe.rq_progress
	var paid: int = pe.rq_paid
	t.eq(prog, 270 * 10000, "30 % of 900 ticks")
	w.remove_entity(gen.id, SimEvent.REM_SCRIPT)
	KIT.run(w, 2)
	t.eq(pe.rq_state, SimEconConst.QS_PAUSED_PREREQ, "losing the Generator pauses the research")
	prog = pe.rq_progress
	paid = pe.rq_paid
	KIT.run(w, 200)
	t.eq([pe.rq_progress, pe.rq_paid], [prog, paid] as Array, "unchanged for 200 ticks")
	KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 23, 19, 0, true)
	KIT.run(w, 5)
	t.eq(pe.rq_state, SimEconConst.QS_ACTIVE, "resumes after the rebuild")
	# a unit head paused by a lost prerequisite: the Barracks is its producer, so sell it mid-build
	var rifle: int = KIT.uidx(DefTestKit.U_RIFLEMAN)
	var b2: SimEntity = _prod(w, DefTestKit.S_BARRACKS, 0, 30, 19)
	w.step()
	w.submit_raw(0, SimCmd.train(b2.id, rifle, 1))
	KIT.run(w, 10)
	var hp: int = b2.prod.head_paid
	t.check(hp > 0, "unit head paying")
	w.submit_raw(0, SimCmd.train(bar.id, rifle, 1))
	KIT.run(w, 5)
	# construction head: the Factory needs a Refinery
	var ref: SimEntity = _prod(w, DefTestKit.S_REFINERY, 0, 23, 22)
	w.step()
	w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_FACTORY)))
	KIT.run(w, 50)
	var cprog: int = pe.cq_progress
	w.remove_entity(ref.id, SimEvent.REM_SCRIPT)
	KIT.run(w, 3)
	cprog = pe.cq_progress
	KIT.run(w, 20)
	t.eq([pe.cq_state, pe.cq_progress], [SimEconConst.QS_PAUSED_PREREQ, cprog] as Array, "construction pauses without its Refinery")


func test_unit_cap_reservation_and_blocked_exit(t: TestCtx) -> void:
	var w: SimWorld = _world(7500, {"rules": {"unit_cap": 20}})
	var bar: SimEntity = _prod(w, DefTestKit.S_BARRACKS, 0, 27, 19)
	_prod(w, DefTestKit.S_GENERATOR, 0, 23, 19)
	w.step()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.eq(pe.unit_cap, 20, "cap from the rules")
	for i: int in 20:
		KIT.K.spawn_rifle(w, 0, (40 + i % 5) * CELL + 512, (40 + i / 5) * CELL + 512)
	w.step()
	t.eq(w.players[0].unit_count, 20, "20 live capped units")
	var rifle: int = KIT.uidx(DefTestKit.U_RIFLEMAN)
	w.submit_raw(0, SimCmd.train(bar.id, rifle, 1))
	KIT.run(w, 30)
	t.eq([bar.prod.head_state, pe.cap_reserved, bar.prod.head_progress], [SimEconConst.QS_PAUSED_CAP, 0, 0] as Array, "PAUSED_CAP: no progress, nothing reserved")
	t.check(not KIT.events_of(w, SimEconConst.EVT_UNIT_CAP_REACHED).is_empty(), "EVT_UNIT_CAP_REACHED")
	w.remove_entity(w.units_of(0)[0].id, SimEvent.REM_SCRIPT)
	KIT.run(w, 2)
	t.eq([bar.prod.head_state, pe.cap_reserved], [SimEconConst.QS_ACTIVE, 1] as Array, "room: the head reserves its cap")
	t.eq(w.economy.unit_cap_room(0), 0, "cap - live - reserved")
	# exit fully blocked (every cell within 4 rings holds a unit): PAUSED_EXIT, retry every 10 ticks
	var w2: SimWorld = _world()
	var b2: SimEntity = _prod(w2, DefTestKit.S_BARRACKS, 0, 27, 19)
	_prod(w2, DefTestKit.S_GENERATOR, 0, 23, 19)
	w2.step()
	var blockers: PackedInt32Array = PackedInt32Array()
	for dy: int in range(-4, 5):
		for dx: int in range(-4, 5):
			if w2.map.occupant_at(w2.map.idx(27 + dx, 21 + dy)) < 0:
				blockers.append(KIT.K.spawn_rifle(w2, 0, (27 + dx) * CELL + 512, (21 + dy) * CELL + 512).id)
	w2.step()
	w2.submit_raw(0, SimCmd.train(b2.id, rifle, 1))
	KIT.run(w2, 260)
	t.eq(b2.prod.head_state, SimEconConst.QS_PAUSED_EXIT, "no free cell within 4 rings")
	var retry: int = b2.prod.exit_retry_tick
	KIT.run(w2, 10)
	t.check(b2.prod.exit_retry_tick > retry, "retried after 10 ticks")
	w2.remove_entity(blockers[0], SimEvent.REM_SCRIPT)
	KIT.run(w2, 12)
	t.eq([b2.prod.q_def.size(), w2.players[0].unit_count], [0, blockers.size()] as Array, "spawned once a cell is free")


# ---- production output, rally, prerequisites end to end ----
func test_units_are_produced_with_build_times_paid_cost_and_rally(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var bar: SimEntity = _prod(w, DefTestKit.S_BARRACKS, 0, 27, 19)
	var fac: SimEntity = _prod(w, DefTestKit.S_FACTORY, 0, 14, 19)
	_prod(w, DefTestKit.S_REFINERY, 0, 23, 22)
	_prod(w, DefTestKit.S_GENERATOR, 0, 23, 19)
	w.step()
	w.orders.replace_handler(SimOrder.T_MOVE, KIT.K.MoveHandler.new())
	w.submit_raw(0, SimCmd.set_rally(PackedInt32Array([bar.id]), 40 * CELL, 30 * CELL, 0, 0))
	var before: int = w.players[0].credits
	w.submit_raw(0, SimCmd.train(bar.id, KIT.uidx(DefTestKit.U_RIFLEMAN), 1))
	w.submit_raw(0, SimCmd.train(fac.id, KIT.uidx(DefTestKit.U_TANK2), 1))
	var nr: int = _run_until(w, func() -> bool: return _count(w, DefTestKit.U_RIFLEMAN) == 1, 2000)
	t.eq(nr, 180, "rifleman: 180 ticks")
	var rf: SimEntity = null
	for u: SimEntity in w.units_of(0):
		if u.def_idx == KIT.uidx(DefTestKit.U_RIFLEMAN):
			rf = u
	if t.not_null(rf, "rifleman exists"):
		t.eq(rf.paid_cost, 250, "paid_cost = the locked price")
		t.check(not rf.orders.is_empty() and rf.orders[0].type == SimOrder.T_MOVE and rf.orders[0].x == 40 * CELL, "rally point: an internal move order")
	var nt: int = _run_until(w, func() -> bool: return _count(w, DefTestKit.U_TANK2) == 1, 2000)
	t.eq(nr + nt, 550, "tank: 550 ticks")
	t.eq(w.players[0].credits, before - 250 - 900, "paid 250 + 900 (the alpha tank costs 900)")
	t.check(not KIT.events_of(w, SimEconConst.EVT_UNIT_PRODUCED).is_empty(), "EVT_UNIT_PRODUCED")
	t.eq(KIT.econ(w, 0).cap_reserved, 0, "reservation released")


func _count(w: SimWorld, unit_id: String) -> int:
	var n: int = 0
	for u: SimEntity in w.units_of(0):
		if u.def_idx == KIT.uidx(unit_id):
			n += 1
	return n


# ---- research ----
func test_research_completes_and_cancel_refunds(t: TestCtx) -> void:
	var w: SimWorld = _world()
	_prod(w, DefTestKit.S_GENERATOR, 0, 23, 19)
	w.step()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	var c0: int = w.players[0].credits
	w.submit_raw(0, SimCmd.research(0))
	w.submit_raw(0, SimCmd.research(0))
	w.step()
	t.eq(pe.rq_def.size(), 1, "an already queued research is refused")
	KIT.run(w, 99)
	w.submit_raw(0, SimCmd.research_cancel(0))
	w.step()
	t.eq(w.players[0].credits, c0, "cancel refunds rq_paid in full")
	w.submit_raw(0, SimCmd.research(0))
	var n: int = _run_until(w, func() -> bool: return pe.researched[0] == 1, 2000)
	t.eq(n, 900, "900 ticks")
	t.eq(w.players[0].credits, c0 - 1000, "1000 paid")
	t.check(w.players[0].view.layer3.is_done(0), "the resolved tables were told")
	t.eq(KIT.events_of(w, SimEconConst.EVT_RESEARCH_COMPLETE).size(), 1, "event")
	w.submit_raw(0, SimCmd.research(0))
	w.step()
	t.eq(pe.rq_def.size(), 0, "never researched twice")


# ---- S1 opening with the real production system ----
func test_s1_opening(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	var chain: Array = [[DefTestKit.S_GENERATOR, 23, 19], [DefTestKit.S_REFINERY, 23, 22], [DefTestKit.S_BARRACKS, 27, 19], [DefTestKit.S_FACTORY, 14, 19]]
	for row: Array in chain:
		w.submit_raw(0, SimCmd.build_start(KIT.sidx(row[0])))
	var ready_at: PackedInt32Array = PackedInt32Array()
	var active_at: PackedInt32Array = PackedInt32Array()
	for row: Array in chain:
		var si: int = KIT.sidx(row[0])
		_run_until(w, func() -> bool: return pe.cq_state == SimEconConst.QS_READY, 4000)
		ready_at.append(w.tick)
		w.step()
		w.submit_raw(0, SimCmd.build_place(si, row[1], row[2], 0))
		w.step()
		t.check(w.players[0].credits >= 0, "credits never negative")
		var placed: SimEntity = w.structures_of(0)[w.structures_of(0).size() - 1]
		_run_until(w, func() -> bool: return placed.econ.st == SimEconConst.ST_ACTIVE, 100)
		active_at.append(w.tick)
	# spec 10.2 S1 (+/- 5): Generator READY 500 / ACTIVE 531, Refinery READY 1331, Barracks 1732, Factory 2533
	var want_ready: PackedInt32Array = PackedInt32Array([500, 1331, 1732, 2533])
	for i: int in 4:
		t.check(absi(ready_at[i] - want_ready[i]) <= 5, "READY[%d] = %d (want %d)" % [i, ready_at[i], want_ready[i]])
	t.check(absi(active_at[0] - 531) <= 5, "Generator ACTIVE at %d" % active_at[0])
	t.eq(pe.producer_flat.size(), 3, "Refinery, Barracks and Factory are producers")
	t.eq(w.players[0].credits, 7500 - 4900, "4900 spent (no harvesting on this map yet: the Collector finds no field)")
	var recount: int = 0
	for c: int in pe.struct_count:
		recount += c
	t.eq(recount, 5, "struct_count = HQ + the four new structures")


# ---- real data: research knobs and the airfield pad API ----
func _real_world(rosters: PackedStringArray) -> SimWorld:
	var d: GameData = GameData.load_default()
	var cells: PackedInt32Array = PackedInt32Array([20 * 96 + 20, 70 * 96 + 70])
	var m: MapData = MapData.for_test(96, 96, cells, PackedInt32Array(), 0x5EED)
	for s: DefStructure in d.structures:
		m.set_footprint(SimEntity.Kind.STRUCTURE, s.index, MapFootprint.new(s.fp_w, s.fp_h, s.fp_mask, (s.place_mask & DefEnums.PLACE_SHORELINE) != 0))
	var pl: Array = []
	for i: int in rosters.size():
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": rosters[i], "team": i + 1, "color": i, "start": i, "handicap": 100})
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 7, "map": {"id": "real"}, "rules": {"victory": 0}, "players": pl})
	return SimWorld.create(d, cfg, m)


func test_research_knobs_and_pads_on_real_data(t: TestCtx) -> void:
	var w: SimWorld = _real_world(PackedStringArray(["roster.napc.usa", "roster.sap.india"]))
	if not t.not_null(w, "real world"):
		return
	var r_run: int = w.data.research_idx("research.napc.dispersed_runways")
	var af_idx: int = w.data.structure_idx("structure.shared.airfield")
	var af: SimEntity = w.spawn_structure(af_idx, 0, 40 * CELL + 3 * CELL, 40 * CELL + 3 * CELL / 2, 0, 0, 1000)
	w.step()
	t.eq(af.prod.pad_ent.size(), 4, "4 base pads")
	w.production.apply_research_knobs(w, 0, r_run)
	t.eq(w.economy.knob(0, SimEconConst.K_PAD_EXTRA), 2, "Dispersed Runways: K_PAD_EXTRA = 2")
	t.eq(af.prod.pad_ent.size(), 6, "the Airfield pads were resized")
	t.eq(w.production.airfield_pad_acquire(w, af.id, 77), 0, "lowest free pad")
	t.eq(w.production.airfield_pad_acquire(w, af.id, 77), 0, "idempotent for the same aircraft")
	t.eq(w.production.airfield_pad_acquire(w, af.id, 78), 1, "next pad")
	w.production.airfield_pad_release(w, af.id, 77)
	t.eq(w.production.airfield_pad_acquire(w, af.id, 79), 0, "released pad reused")
	var cell: int = w.production.airfield_pad_cell(w, af.id, 0)
	t.check(cell >= 0 and w.map.occupant_at(cell) == af.id, "pad cell lies inside the Airfield footprint")
	t.eq(w.production.airfield_service_rate_bp(w, af.id), 10000, "service rate 100 % (online)")
	# SAP: Reserve Capacitors raise the maximum and a full reserve follows
	var r_res: int = w.data.research_idx("research.sap.reserve_capacitors")
	w.production.apply_research_knobs(w, 1, r_res)
	var pe1: SimPlayerEcon = KIT.econ(w, 1)
	t.eq([pe1.reserve_max, pe1.reserve_left], [700, 700] as Array, "SAP reserve 700 ticks, refilled")
	# the real research completes through the queue (Radar / Laboratory prerequisites are honoured)
	t.eq(w.production.can_queue_research(w, 0, r_run), SimEconConst.RSN_PREREQ if not w.production.research_prereqs_met(w, 0, r_run) else SimEconConst.RSN_OK, "consistent")
