extends RefCounted
## E5 harvesting (10.1-G, S3 raid, S7 income band): the Collector state machine on the real movement stage, the
## deposit table, the dock protocol and the determinism of the whole loop. Fixture: a flat 96x96 map, HQ + Generator
## + Refinery (23, 22) with its free Collector, a deposit field about 10 cells east of the Refinery.

const FK := preload("res://tests/support/sim_econ_field_kit.gd")
const K := preload("res://tests/support/sim_econ_kit.gd")
const CELL: int = SimConfig.CELL
const FIELD_A: Dictionary = {"cx": 34, "cy": 26, "r": 3, "per_cell": 600}
const FIELD_B: Dictionary = {"cx": 34, "cy": 40, "r": 3, "per_cell": 600}


func _run_until(w: SimWorld, pred: Callable, limit: int) -> int:
	var n: int = 0
	while n < limit and not pred.call():
		w.step()
		n += 1
	return n


func _harvester(_w: SimWorld) -> SimOrderHarvest:
	return SimOrderHarvest.new(SimOrder.T_HARVEST)


func _refinery(w: SimWorld) -> SimEntity:
	return w.get_entity(w.players[0].econ.refinery_ids[0])


# ---- S7 income band / 10.1-G cycle ----
func test_cycle_time_and_three_minute_income(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A])
	var pe: SimPlayerEcon = w.players[0].econ
	var col: SimEntity = FK.collectors(w)[0]
	t.check((col.econ.flags & SimEconConst.EF_FREE) != 0 and col.paid_cost == 0, "the Refinery's free Collector")
	var deliveries: PackedInt32Array = PackedInt32Array()
	var prev_cargo: int = 0
	var start_stock: int = w.economy.deposits.stock(w.map, 0)
	for _i: int in 3600:
		w.step()
		if prev_cargo > 0 and col.econ.cargo == 0:
			deliveries.append(w.tick)
		prev_cargo = col.econ.cargo
	t.check(pe.stat_harvested >= 1500 and pe.stat_harvested <= 2400, "3 minutes of one Collector: %d credits (framework band 600-800 / min)" % pe.stat_harvested)
	t.check(deliveries.size() >= 3, "at least three deliveries")
	if deliveries.size() >= 3:
		var cycle: int = deliveries[2] - deliveries[1]
		t.check(cycle >= 900 and cycle <= 1000, "steady cycle %d ticks (framework 941 at 10 cells, +/- 2 %% plus the field detour)" % cycle)
	t.eq(w.players[0].credits, 7500 + pe.stat_harvested, "credits = start + harvested")
	t.eq(start_stock - w.economy.deposits.stock(w.map, 0), pe.stat_harvested + col.econ.cargo, "stock -= delivered + cargo")
	t.eq(pe.stat_harvested, w.economy.income_total(0), "income_total")
	t.check(w.economy.q_income_per_minute(0) > 0, "income ring")
	t.eq(w.economy.deposits.harvesters[0], 1 if col.econ.h_field == 0 else 0, "harvester count follows h_field")


func test_income_events_and_q_apis(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A, FIELD_B])
	K.run(w, 1000)
	var gained: Array[PackedInt32Array] = K.events_of(w, SimEconConst.EVT_CREDITS_GAINED)
	t.check(not gained.is_empty(), "EVT_CREDITS_GAINED at the refinery")
	if not gained.is_empty():
		t.eq(gained[0][4], 0, "a = pid")
	var out: PackedInt32Array = PackedInt32Array()
	w.economy.q_collectors(0, out)
	t.eq(out.size(), 1, "q_collectors")
	t.eq(w.economy.q_deposit_nearest(w, 0, 34 * CELL, 26 * CELL, 1), 0, "nearest field")
	t.eq(w.economy.q_deposit_nearest(w, 0, 34 * CELL, 42 * CELL, 1), 1, "the other one")
	t.eq(w.economy.q_deposit_nearest(w, 0, 34 * CELL, 26 * CELL, 999999), -1, "min_stock")
	w.economy.q_refineries(0, out)
	t.eq(out.size(), 1, "q_refineries")


# ---- selection rules ----
func test_choose_field_penalties_bad_and_danger(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A, FIELD_B], {"base": false})
	var h: SimOrderHarvest = _harvester(w)
	var c1: SimEntity = K.K.spawn_collector(w, 0, 34 * CELL, 33 * CELL)
	var c2: SimEntity = K.K.spawn_collector(w, 0, 34 * CELL, 33 * CELL)
	w.step()
	var deps: SimDepositTable = w.economy.deposits
	t.eq(h.choose_field(w, c1, c1.econ), 0, "equidistant: the lowest index wins")
	deps.harvesters[0] = 1
	t.eq(h.choose_field(w, c2, c2.econ), 1, "the field with fewer harvesters wins (penalty 4 cells per harvester)")
	deps.harvesters[0] = 0
	c1.econ.h_last_field = 1
	t.eq(h.choose_field(w, c1, c1.econ), 1, "the last field is preferred by 2 cells")
	# bad field: skipped until h_bad_until passes (600 ticks)
	c1.econ.h_last_field = -1
	c1.econ.h_bad_field = 0
	c1.econ.h_bad_until = w.tick + 600
	t.eq(h.choose_field(w, c1, c1.econ), 1, "h_bad_field is avoided")
	w.tick += 599  # the clock only: the test Collectors must not act meanwhile
	t.eq(h.choose_field(w, c1, c1.econ), 1, "still bad at +599")
	w.tick += 2
	t.eq(h.choose_field(w, c1, c1.econ), 0, "h_bad_field expired after 600 ticks")
	# field danger of the owner (400 ticks)
	w.players[0].econ.field_danger[0] = w.tick + 400
	t.eq(h.choose_field(w, c2, c2.econ), 1, "a dangerous field is avoided by every Collector of the player")
	w.tick += 401
	t.eq(h.choose_field(w, c2, c2.econ), 0, "danger expired")
	# a full field (max harvesters of its class) is not offered
	deps.harvesters[0] = deps.max_harvesters(0)
	t.eq(h.choose_field(w, c2, c2.econ), 1, "full field")


func test_second_collector_takes_the_emptier_field(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A, {"cx": 34, "cy": 26 + 14, "r": 3, "per_cell": 600}])
	K.run(w, 30)
	var extra: SimEntity = K.K.spawn_collector(w, 0, 27 * CELL, 33 * CELL)
	K.run(w, 60)
	var fields: PackedInt32Array = PackedInt32Array()
	for c: SimEntity in FK.collectors(w):
		fields.append(c.econ.h_field)
	t.check(fields.size() == 2 and fields[0] != fields[1] and not fields.has(-1), "two Collectors work two different fields: %s" % str(fields))
	t.eq(extra.econ.h_field >= 0, true, "the new one is assigned")
	t.eq(w.economy.deposits.harvesters[0] + w.economy.deposits.harvesters[1], 2, "counts")


# ---- deposits ----
func test_depletion_and_regrowth(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([{"cx": 34, "cy": 26, "r": 1, "per_cell": 100}], {"base": false})
	var deps: SimDepositTable = w.economy.deposits
	deps.regrow = true
	t.eq(deps.stock(w.map, 0), 500, "5 cells x 100")
	var cell: int = 26 * 96 + 34
	var got: int = 0
	while true:
		var n: int = deps.take(w, 0, cell, 60)
		if n == 0:
			break
		got += n
	t.eq([got, deps.stock(w.map, 0)], [500, 0] as Array, "emptied")
	t.eq(K.events_of(w, SimEconConst.EVT_DEPOSIT_DEPLETED).size(), 1, "EVT_DEPOSIT_DEPLETED once")
	var t_last: int = w.tick
	var n1: int = _run_until(w, func() -> bool: return deps.stock(w.map, 0) > 0, 1500)
	t.check(n1 >= 1200 - 1 and n1 <= 1220, "idle regrowth starts 1200 ticks after the last harvest (%d)" % n1)
	t.eq(deps.stock(w.map, 0), 40, "+40")
	var n2: int = _run_until(w, func() -> bool: return deps.stock(w.map, 0) > 40, 400)
	t.eq([n2, deps.stock(w.map, 0)], [200, 80] as Array, "the next +40 a regen period (200 ticks) later")
	t.eq(K.events_of(w, SimEconConst.EVT_DEPOSIT_REGROWN).size(), 1, "EVT_DEPOSIT_REGROWN at 10 % of the cap")
	t.eq(t_last, t_last, "tick anchor")
	# finite by default
	var w2: SimWorld = FK.make_world([{"cx": 34, "cy": 26, "r": 1, "per_cell": 100}], {"base": false})
	w2.economy.deposits.take(w2, 0, cell, 5000)
	w2.economy.deposits.take(w2, 0, cell, 5000)
	K.run(w2, 1500)
	t.eq(w2.economy.deposits.stock(w2.map, 0), 300, "regrow is off by default (global.json: finite fields)")


# ---- dock protocol ----
func test_dock_fifo_protocol(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A])
	var ref: SimEntity = _refinery(w)
	var c: Array[SimEntity] = []
	for i: int in 3:
		c.append(K.K.spawn_collector(w, 0, (30 + i) * CELL, 20 * CELL))
	w.step()
	var eco: SimEconomySystem = w.economy
	t.eq(eco.dock_request(w, ref.id, c[0].id), SimEconConst.DOCK_GRANTED, "first caller is granted")
	t.eq(eco.dock_request(w, ref.id, c[1].id), SimEconConst.DOCK_WAIT, "second waits")
	t.eq(eco.dock_request(w, ref.id, c[2].id), SimEconConst.DOCK_WAIT, "third waits")
	t.eq(eco.dock_request(w, ref.id, c[2].id), SimEconConst.DOCK_WAIT, "no duplicate in the queue")
	t.eq(eco.dock_queue_len(ref.id), 2, "queue length")
	t.eq(eco.dock_request(w, ref.id, c[0].id), SimEconConst.DOCK_GRANTED, "the occupant stays granted")
	eco.dock_release(w, ref.id, c[0].id)
	t.eq(eco.dock_request(w, ref.id, c[2].id), SimEconConst.DOCK_WAIT, "only the queue head may take the free dock")
	t.eq(eco.dock_request(w, ref.id, c[1].id), SimEconConst.DOCK_GRANTED, "FIFO: c1 is next")
	t.eq(eco.dock_queue_len(ref.id), 1, "c2 remains")
	# unloading: 6 credits / tick, whole load in 100 ticks, credited through the ledger
	c[1].econ.cargo = 600
	var before: int = w.players[0].credits
	var moved: int = 0
	var ticks: int = 0
	while c[1].econ.cargo > 0 and ticks < 200:
		moved += eco.dock_unload_step(w, ref.id, c[1].id)
		ticks += 1
	t.eq([moved, ticks, w.players[0].credits - before], [600, 100, 600] as Array, "600 credits at 6 per tick")
	t.eq(eco.dock_unload_step(w, ref.id, c[2].id), 0, "a non-occupant moves nothing")
	# a shut-down / gone refinery denies
	ref.econ.shutdown_until = w.tick + 50
	t.eq(eco.dock_request(w, ref.id, c[2].id), SimEconConst.DOCK_DENIED, "EMP shutdown denies")
	t.eq(eco.dock_request(w, 9999, c[2].id), SimEconConst.DOCK_DENIED, "no such refinery")


func test_three_collectors_unload_in_arrival_order(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A])
	for c: SimEntity in FK.collectors(w):
		w.remove_entity(c.id, SimEvent.REM_SCRIPT)
	w.step()
	var ref: SimEntity = _refinery(w)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 3:
		var c: SimEntity = K.K.spawn_collector(w, 0, (28 + 2 * i) * CELL + 512, 27 * CELL + 512)
		c.econ.cargo = 600
		ids.append(c.id)
	w.submit_raw(0, SimCmd.return_cargo(ids, ref.id))
	var seen: PackedInt32Array = PackedInt32Array()
	var before: int = w.players[0].credits
	for _i: int in 900:
		w.step()
		var occ: int = ref.econ.dock_occupant
		if occ != 0 and (seen.is_empty() or seen[seen.size() - 1] != occ):
			seen.append(occ)
	t.eq(seen.size(), 3, "each Collector used the dock once")
	t.eq(w.players[0].credits - before, 1800, "1800 credits arrived")
	var arrival_ok: bool = seen.size() == 3
	if arrival_ok:
		# the nearest Collector docks first (they queue in arrival order), all three eventually
		var dists: Array = []
		for id: int in seen:
			dists.append(id)
		t.eq(seen[0], ids[0], "nearest first")


func test_refinery_destroyed_while_unloading_keeps_cargo(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A])
	var col: SimEntity = FK.collectors(w)[0]
	var ref: SimEntity = _refinery(w)
	_run_until(w, func() -> bool: return col.econ.h_state == SimEconConst.H_UNLOAD and col.econ.cargo < 500, 3000)
	t.eq(col.econ.h_state, SimEconConst.H_UNLOAD, "unloading")
	var cargo: int = col.econ.cargo
	t.check(cargo > 0 and cargo < 600, "part of the load is still on board (%d)" % cargo)
	w.kill(ref, SimWorld.Cause.SCRIPT)
	K.run(w, 3)
	t.check(col.econ.h_state != SimEconConst.H_UNLOAD, "the FSM left UNLOAD")
	K.run(w, 200)
	t.check(col.econ.cargo >= cargo, "cargo intact after the refinery died (it may keep loading: %d -> %d)" % [cargo, col.econ.cargo])
	_run_until(w, func() -> bool: return col.econ.cargo >= 600, 600)
	_run_until(w, func() -> bool: return not K.events_of(w, SimEconConst.EVT_NO_REFINERY).is_empty(), 700)
	t.check(not K.events_of(w, SimEconConst.EVT_NO_REFINERY).is_empty(), "EVT_NO_REFINERY hint (about one per 600 ticks)")
	t.eq(col.econ.cargo, 600, "full and waiting for a Refinery")
	t.check((col.flags & SimFlags.F_GONE) == 0, "the Collector survived")
	# a new Refinery is found and the cargo is delivered
	K.spawn_struct(w, DefTestKit.S_REFINERY, 0, 23, 22)
	var before: int = w.players[0].credits
	_run_until(w, func() -> bool: return col.econ.cargo == 0, 1500)
	t.check(w.players[0].credits >= before + cargo, "delivered to the replacement")


# ---- raid ----
func test_flee_marks_the_field_and_preserves_cargo(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A])
	var pe: SimPlayerEcon = w.players[0].econ
	var col: SimEntity = FK.collectors(w)[0]
	_run_until(w, func() -> bool: return col.econ.h_state == SimEconConst.H_HARVEST and col.econ.cargo > 100, 1000)
	var cargo: int = col.econ.cargo
	t.check(cargo > 100, "harvesting")
	var tank: SimEntity = K.K.spawn_tank(w, 1, 38 * CELL, 26 * CELL)
	t.not_null(tank, "raider")
	var t0: int = w.tick
	var n: int = _run_until(w, func() -> bool: return col.econ.h_state != SimEconConst.H_HARVEST, 30)
	t.check(n <= 11, "flees within 10 ticks (%d)" % n)
	t.eq(col.econ.h_state, SimEconConst.H_TO_REFINERY, "loaded: retreats to the safe Refinery")
	t.check(pe.field_danger[0] >= t0 + 400 and pe.field_danger[0] <= t0 + 400 + 12, "field_danger = +400 ticks")
	t.eq(K.events_of(w, SimEconConst.EVT_COLLECTOR_ATTACKED).size(), 1, "EVT_COLLECTOR_ATTACKED")
	t.eq(w.economy.deposits.harvesters[0], 0, "the field was released")
	var h: SimOrderHarvest = _harvester(w)
	var other: SimEntity = K.K.spawn_collector(w, 0, 30 * CELL, 26 * CELL)
	t.eq(h.choose_field(w, other, other.econ), -1, "another Collector of the player avoids the field")
	_run_until(w, func() -> bool: return pe.stat_harvested >= cargo, 600)
	t.check(pe.stat_harvested >= cargo, "the cargo was kept and unloaded at the Refinery")
	w.remove_entity(tank.id, SimEvent.REM_SCRIPT)
	K.run(w, 430)
	t.eq(h.choose_field(w, other, other.econ), 0, "danger expired after 400 ticks")


# ---- orders ----
func test_manual_harvest_and_return_cargo_orders(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A, FIELD_B])
	var col: SimEntity = FK.collectors(w)[0]
	K.run(w, 5)
	t.eq(col.orders[0].type, SimOrder.T_HARVEST, "the idle Collector got an auto-harvest order")
	t.check((col.orders[0].flags & SimOrder.OF_AUTO) != 0, "OF_AUTO")
	# a player command sends it to the farther field (manual)
	w.submit_raw(0, SimCmd.harvest(PackedInt32Array([col.id]), 0, 34 * CELL + 512, 40 * CELL + 512, 0))
	K.run(w, 50)
	t.eq([col.econ.h_mode, col.econ.h_field], [1, 1] as Array, "manual field 1")
	_run_until(w, func() -> bool: return col.econ.cargo > 50, 600)
	t.check(col.econ.cargo > 50 and col.econ.h_state == SimEconConst.H_HARVEST, "harvesting the chosen field")
	# RETURN_CARGO: DONE after the unload, then auto-harvest resumes
	w.submit_raw(0, SimCmd.return_cargo(PackedInt32Array([col.id]), 0))
	K.run(w, 2)
	t.eq(col.orders[0].type, SimOrder.T_RETURN_CARGO, "the order")
	var before: int = w.players[0].econ.stat_harvested
	_run_until(w, func() -> bool: return col.orders.is_empty() or col.orders[0].type != SimOrder.T_RETURN_CARGO, 1500)
	t.check(w.players[0].econ.stat_harvested > before and col.econ.cargo == 0, "unloaded")
	K.run(w, 3)
	t.eq(col.orders[0].type, SimOrder.T_HARVEST, "auto-harvest resumed")
	# a non-collector refuses the order
	var tank: SimEntity = K.K.spawn_tank(w, 0, 40 * CELL, 30 * CELL)
	t.eq(w.orders.issue(w, tank, SimOrder.make(SimOrder.T_HARVEST), SimOrder.QM_REPLACE), SimCommand.Err.NOT_ALLOWED, "tanks do not harvest")


func test_order_end_releases_field_and_dock(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A])
	var col: SimEntity = FK.collectors(w)[0]
	_run_until(w, func() -> bool: return col.econ.h_state == SimEconConst.H_HARVEST, 600)
	t.eq(w.economy.deposits.harvesters[0], 1, "assigned")
	w.submit_raw(0, SimCmd.stop(PackedInt32Array([col.id])))
	K.run(w, 2)
	t.eq(w.economy.deposits.harvesters[0], 0 if col.orders.is_empty() else 1, "STOP released the field (an auto order may start again)")
	# a dying Collector releases its field through on_end(END_DIED)
	var c2: SimEntity = col
	_run_until(w, func() -> bool: return c2.econ.h_field == 0, 600)
	w.kill(c2, SimWorld.Cause.SCRIPT)
	K.run(w, 3)
	t.eq(w.economy.deposits.harvesters[0], 0, "a dead Collector holds no field")


# ---- determinism (DR-13) ----
func test_deposit_state_reaches_the_checksum(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A])
	K.run(w, 300)
	var base: int = w.checksum()
	w.economy.deposits.harvesters[0] += 1
	t.check(w.checksum() != base, "harvester count")
	w.economy.deposits.harvesters[0] -= 1
	w.economy.deposits.last_harvest_tick[0] += 1
	t.check(w.checksum() != base, "last harvest tick")
	w.economy.deposits.last_harvest_tick[0] -= 1
	t.eq(w.checksum(), base, "and back")
	var col: SimEntity = FK.collectors(w)[0]
	col.econ.cargo += 1
	t.check(w.checksum() != base, "collector cargo")


func test_scenario_double_run(t: TestCtx) -> void:
	var build: Callable = func() -> SimWorld: return FK.make_world([FIELD_A, FIELD_B], {"rules": {"start_credits": 9000}})
	var script: Callable = func(w: SimWorld, s: int) -> void:
		match s:
			0:
				w.submit_raw(0, SimCmd.build_start(K.sidx(DefTestKit.S_BARRACKS)))
				w.submit_raw(0, SimCmd.train(_refinery(w).id, K.uidx(DefTestKit.U_COLLECTOR), 2))
			10:
				w.submit_raw(0, SimCmd.research(0))
			420:
				w.submit_raw(0, SimCmd.build_place(K.sidx(DefTestKit.S_BARRACKS), 27, 19, 0))
			700:
				w.submit_raw(0, SimCmd.train(0, K.uidx(DefTestKit.U_RIFLEMAN), 2))
			900:
				var ids: PackedInt32Array = PackedInt32Array()
				for c: SimEntity in FK.collectors(w):
					ids.append(c.id)
				w.submit_raw(0, SimCmd.harvest(ids, 0, 34 * CELL + 512, 40 * CELL + 512, 0))
	var r: Dictionary = K.K.double_run(build, script, 1800)
	t.check(r["ok"], "identical hash chains, event digests, final checksums and dumps")
	t.check((r["chain"] as PackedInt64Array).size() > 10, "chain recorded")


# ---- the full scenario: earn, produce, research ----
func test_full_scenario_income_production_research(t: TestCtx) -> void:
	var w: SimWorld = FK.make_world([FIELD_A], {"rules": {"start_credits": 12000}})
	var pe: SimPlayerEcon = w.players[0].econ
	K.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 27, 19)
	K.spawn_struct(w, DefTestKit.S_FACTORY, 0, 14, 19)
	w.step()
	var bar: SimEntity = null
	var fac: SimEntity = null
	for s: SimEntity in w.structures_of(0):
		if s.def_idx == K.sidx(DefTestKit.S_BARRACKS):
			bar = s
		elif s.def_idx == K.sidx(DefTestKit.S_FACTORY):
			fac = s
	w.submit_raw(0, SimCmd.train(bar.id, K.uidx(DefTestKit.U_RIFLEMAN), 3))
	w.submit_raw(0, SimCmd.train(fac.id, K.uidx(DefTestKit.U_TANK2), 1))
	w.submit_raw(0, SimCmd.research(0))
	var produced: PackedInt32Array = PackedInt32Array()
	var t0: int = w.tick
	for _i: int in 3600:
		w.step()
		for _ev: PackedInt32Array in K.events_of(w, SimEconConst.EVT_UNIT_PRODUCED):
			produced.append(w.tick - t0)
		w.clear_events()
	t.eq(produced.size(), 4, "3 riflemen + 1 tank")
	t.eq(produced.slice(0, 3), PackedInt32Array([180, 360, 540]), "three infantry at 180-tick intervals")
	t.eq(produced[3], 550, "the tank: 550 ticks")
	t.eq(pe.researched[0], 1, "research completed (900 ticks)")
	t.check(pe.stat_harvested >= 1500 and pe.stat_harvested <= 2400, "income in the framework band: %d" % pe.stat_harvested)
	t.eq(w.players[0].credits, 12000 - 3 * 250 - 900 - 1000 + pe.stat_harvested, "ledger: start - units - research + harvested")
	t.eq(pe.cap_reserved, 0, "no dangling cap reservation")


# ---- the real balance data: real Refinery exit, real Collector, real queue ----
func test_real_data_harvest_and_collector_queue(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	if not t.not_null(d, "real data"):
		return
	var pl: Array = []
	for i: int in 2:
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": "roster.napc.usa" if i == 0 else "roster.nec.vanilla", "team": i + 1, "color": i, "start": i, "handicap": 100})
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 9, "map": {"id": "real"}, "rules": {"victory": 0, "fog": false}, "players": pl})
	var w: SimWorld = SimWorld.create(d, cfg, FK.make_map([FIELD_A], d), {"disable": ["SimCombatSystem"]})
	if not t.not_null(w, "world"):
		return
	var ri: int = d.structure_idx("structure.shared.refinery")
	var gi: int = d.structure_idx("structure.shared.generator")
	w.spawn_structure(gi, 0, SimPlacement.footprint_center_x(w, gi, 23, 0), SimPlacement.footprint_center_y(w, gi, 19, 0), 0, 0, 600)
	w.spawn_structure(ri, 0, SimPlacement.footprint_center_x(w, ri, 23, 0), SimPlacement.footprint_center_y(w, ri, 22, 0), 0, 0, 1800)
	w.step()
	var pe: SimPlayerEcon = w.players[0].econ
	var cols: Array[SimEntity] = []
	for u: SimEntity in w.units_of(0):
		if d.units[u.def_idx].has_ability(DefEnums.AbilityKind.HARVEST):
			cols.append(u)
	t.eq(cols.size(), 1, "the real Refinery's free Collector")
	K.run(w, 2400)
	t.check(pe.stat_harvested >= 600 and pe.stat_harvested <= 1800, "the real Collector earns: %d in 2400 ticks" % pe.stat_harvested)
	# buy a second one: 1400 credits, build time from the data, produced at the Refinery exit
	var ref: SimEntity = w.get_entity(pe.refinery_ids[0])
	var cu: int = w.players[0].roster.units_produced_by(ri)[0]
	var ticks: int = w.players[0].view.unit_ticks[cu]
	var cost: int = w.players[0].view.unit_cost[cu]
	t.eq(cost, 1400, "Collector price")
	var before: int = w.players[0].credits
	t.eq(w.production.can_queue_unit(w, 0, ref.id, cu), SimEconConst.RSN_OK, "the real Collector can be queued at the real Refinery")
	w.submit_raw(0, SimCmd.train(ref.id, cu, 1))
	w.step()
	var n: int = 1 + _run_until(w, func() -> bool: return ref.prod.q_def.is_empty(), 2000)
	t.eq(n, ticks, "Collector build time from the data (%d ticks)" % ticks)
	var cnt: int = 0
	for u: SimEntity in w.units_of(0):
		if d.units[u.def_idx].has_ability(DefEnums.AbilityKind.HARVEST):
			cnt += 1
	t.eq(cnt, 2, "a second Collector exists")
	t.check(w.players[0].credits <= before - cost + 600 * 2, "1400 paid")
