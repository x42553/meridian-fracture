extends RefCounted
## E2 / E4 scenario (S1 opening, S2 brownout, S5 sell): an HQ-only player builds Generator -> Refinery -> Barracks
## -> Factory through real BUILD_START / BUILD_PLACE commands with progressive payment, a power shortage halves
## the construction speed, a sale refunds 50 %. The construction queue is the test double SimEconProdDouble until
## the production task lands.

const KIT := preload("res://tests/support/sim_econ_kit.gd")
const DOUBLE := preload("res://tests/support/sim_econ_prod_double.gd")


func _world() -> SimWorld:
	return KIT.make_world({"start_mode": 0, "opts": {"systems": [DOUBLE.new()]}})


## Queues `id`, steps until READY (returns the steps taken), places it at (ox, oy) and steps until ACTIVE.
func _build(w: SimWorld, t: TestCtx, id: String, ox: int, oy: int) -> Dictionary:
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	var si: int = KIT.sidx(id)
	w.submit_raw(0, SimCmd.build_start(si))
	var n: int = 0
	while pe.cq_state != SimEconConst.QS_READY and n < 3000:
		w.step()
		n += 1
		t.check(w.players[0].credits >= 0, "credits never negative")
	var paid: int = pe.cq_paid
	w.submit_raw(0, SimCmd.build_place(si, ox, oy))
	w.step()
	var ent: SimEntity = null
	for e: SimEntity in w.structures_of(0):
		if e.def_idx == si and e.econ.st == SimEconConst.ST_BUILDUP:
			ent = e
	if not t.not_null(ent, "%s placed" % id):
		return {}
	t.eq(ent.paid_cost, paid, "paid_cost = the progressive payments")
	var m: int = 0
	while ent.econ.st != SimEconConst.ST_ACTIVE and m < 100:
		w.step()
		m += 1
	return {"ready": n, "paid": paid, "ent": ent, "buildup": m}


func test_opening_progressive_payment(t: TestCtx) -> void:
	var w: SimWorld = _world()
	t.eq(w.players[0].credits, 7500, "the preset")
	t.eq(w.structures_of(0).size(), 1, "HQ only")
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_GENERATOR)))
	KIT.run(w, 100)
	t.eq(pe.cq_paid, 120, "600 credits over 500 ticks: 120 after 100 ticks")
	t.eq(w.players[0].credits, 7500 - 120, "the ledger followed")
	KIT.run(w, 400)
	t.eq(pe.cq_state, SimEconConst.QS_READY, "READY after exactly 500 ticks")
	t.eq([pe.cq_paid, w.players[0].credits], [600, 6900] as Array, "fully paid")
	t.eq(pe.stat_spent_construction, 600, "statistic")
	# the queue is blocked until placed; a wrong spot is rejected and leaves the queue untouched
	w.submit_raw(0, SimCmd.build_place(KIT.sidx(DefTestKit.S_GENERATOR), 60, 60))
	w.step()
	t.eq(pe.cq_state, SimEconConst.QS_READY, "still READY after a rejected placement")
	t.eq(w.players[0].st_rejected, 1, "rejected")
	w.submit_raw(0, SimCmd.build_place(KIT.sidx(DefTestKit.S_GENERATOR), 23, 19))
	w.step()
	var gen: SimEntity = w.structures_of(0)[1]
	t.eq(gen.econ.st, SimEconConst.ST_BUILDUP, "placed inert")
	t.eq(pe.cq_state, SimEconConst.QS_EMPTY, "queue popped")
	KIT.run(w, 31)
	t.eq(gen.econ.st, SimEconConst.ST_ACTIVE, "active 30 ticks later")
	t.eq(pe.power_supply, 150, "the grid")
	# prerequisite: Barracks needs an ACTIVE Generator, Factory needs a Refinery
	w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_FACTORY)))
	w.step()
	t.eq(pe.cq_state, SimEconConst.QS_EMPTY, "Factory refused: no Refinery")
	t.eq(w.players[0].st_rejected, 2, "PREREQ")


func test_full_chain_brownout_and_sell(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	var gen: Dictionary = _build(w, t, DefTestKit.S_GENERATOR, 23, 19)
	t.eq(gen["ready"], 500, "Generator: 25 s")
	var ref: Dictionary = _build(w, t, DefTestKit.S_REFINERY, 23, 22)
	t.eq([ref["ready"], ref["paid"]], [800, 1800] as Array, "Refinery: 40 s, 1800")
	var bar: Dictionary = _build(w, t, DefTestKit.S_BARRACKS, 27, 19)
	t.eq([bar["ready"], bar["paid"]], [400, 500] as Array, "Barracks: 20 s, 500")
	var fac: Dictionary = _build(w, t, DefTestKit.S_FACTORY, 14, 19)
	t.eq([fac["ready"], fac["paid"]], [800, 2000] as Array, "Factory: 40 s, 2000")
	t.eq([w.power.supply(0), w.power.demand(0)], [150, 140] as Array, "150 vs 50 + 30 + 60: normal")
	t.check_false(w.power.is_shortage(0), "no shortage yet")
	t.eq(w.players[0].credits, 7500 - 600 - 1800 - 500 - 2000, "the ledger adds up (no income: no Collector orders here)")
	t.eq(pe.struct_count[KIT.sidx(DefTestKit.S_BARRACKS)], 1, "counters")
	t.eq(pe.producer_flat.size(), 3, "Barracks, Factory and Refinery are producers")
	var collectors: int = 0
	for u: SimEntity in w.units_of(0):
		if u.def_idx == KIT.uidx(DefTestKit.U_COLLECTOR):
			collectors += 1
	t.eq(collectors, 1, "the Refinery's free Collector")
	# brownout: a Turret (-20) tips 160 > 150; the next Barracks (400 ticks) takes 800
	_build(w, t, DefTestKit.S_TURRET, 19, 25)
	t.check(w.power.is_shortage(0), "160 > 150: shortage")
	t.eq(w.power.production_rate_bp(0), 5000, "rate")
	var slow: Dictionary = _build(w, t, DefTestKit.S_BARRACKS, 16, 23)
	t.eq(slow["ready"], 800, "half speed: 400 ticks take 800")
	t.eq(slow["paid"], 500, "the price does not change")
	# sell the first Barracks: 50 % of the paid price, no handicap, the power drops at once
	var before: int = w.players[0].credits
	var b1: SimEntity = bar["ent"]
	w.submit_raw(0, SimCmd.sell(PackedInt32Array([b1.id])))
	w.step()
	t.eq(pe.struct_count[b1.def_idx], 1, "unregistered when the sale starts (one Barracks left)")
	KIT.run(w, SimEconConst.SELL_TICKS)
	t.eq(w.players[0].credits, before + 250, "refund 50 % of 500")
	t.is_null(w.get_entity(b1.id), "sold structure removed")
	t.eq(pe.stat_sold, 250, "sell statistic")


func test_scenario_determinism(t: TestCtx) -> void:
	var script: Callable = func(w: SimWorld, s: int) -> void:
		match s:
			0:
				w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_GENERATOR)))
			500:
				w.submit_raw(0, SimCmd.build_place(KIT.sidx(DefTestKit.S_GENERATOR), 23, 19))
			540:
				w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_BARRACKS)))
			940:
				w.submit_raw(0, SimCmd.build_place(KIT.sidx(DefTestKit.S_BARRACKS), 27, 19))
			1000:
				w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_TURRET)))
				w.submit_raw(1, SimCmd.build_start(KIT.sidx(DefTestKit.S_GENERATOR)))
			1400:
				w.submit_raw(0, SimCmd.sell(PackedInt32Array([w.structures_of(0)[1].id])))
	var r: Dictionary = KIT.K.double_run(func() -> SimWorld: return _world(), script, 1500)
	t.check(r["ok"], "two runs give identical hash chains, event digests, final checksums and dumps")
	t.check((r["chain"] as PackedInt64Array).size() > 10, "the chain was recorded")
