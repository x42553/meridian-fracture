extends RefCounted
## E4 structure lifecycle (economy 5.3): BUILDUP -> ACTIVE registration, sell (unregisters at once, refunds 50 % of
## the paid cost at the end), HQ undeploy / MCV deploy, the free Collector, captured structures moving power.

const KIT := preload("res://tests/support/sim_econ_kit.gd")


func _hq(w: SimWorld, pid: int, ox: int = 10, oy: int = 10) -> SimEntity:
	return KIT.spawn_struct(w, DefTestKit.S_HQ, pid, ox, oy)


func test_buildup_then_active(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	_hq(w, 0)
	var gen: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600, false)
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.eq(gen.econ.st, SimEconConst.ST_BUILDUP, "spawned inert")
	t.check((gen.flags & SimFlags.F_UNDER_CONSTRUCTION) != 0, "flag while under construction")
	t.eq(pe.struct_count[gen.def_idx], 0, "not counted while BUILDUP")
	KIT.run(w, 1)
	t.eq(pe.power_supply, 0, "no power while BUILDUP")
	KIT.run(w, SimEconConst.BUILDUP_TICKS)
	t.eq(gen.econ.st, SimEconConst.ST_ACTIVE, "active after 30 ticks")
	t.eq(pe.struct_count[gen.def_idx], 1, "counted")
	t.eq(pe.power_supply, 150, "supply after the stage-3 balance")
	t.check((gen.flags & SimFlags.F_UNDER_CONSTRUCTION) == 0, "flag cleared")
	t.eq(pe.active_hq_count, 1, "the start HQ is registered")


func test_sell_refund_and_unregister(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	_hq(w, 0)
	var gen: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600)
	KIT.run(w, 2)
	var before: int = w.players[0].credits
	t.eq(KIT.econ(w, 0).power_supply, 150, "supply")
	w.submit_raw(0, SimCmd.sell(PackedInt32Array([gen.id])))
	w.step()
	t.eq(gen.econ.st, SimEconConst.ST_SELLING, "selling")
	t.eq(KIT.econ(w, 0).struct_count[gen.def_idx], 0, "unregistered at once (prerequisites drop now)")
	t.eq(KIT.econ(w, 0).power_supply, 0, "power dropped on the same stage-3 pass")
	KIT.run(w, SimEconConst.SELL_TICKS)
	t.eq(w.players[0].credits, before + 300, "50 % of paid_cost 600, flat")
	t.is_null(w.get_entity(gen.id), "removed")
	t.eq(KIT.econ(w, 0).stat_sold, 300, "statistic")
	
	var hq_id: int = w.structures_of(0)[0].id
	w.submit_raw(0, SimCmd.sell(PackedInt32Array([hq_id])))
	w.step()
	t.eq(w.players[0].st_rejected, 1, "HQ sale rejected (not sellable)")


func test_sell_hq_refunds_nothing_and_buildup_locked(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	_hq(w, 0)
	var gen: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600, false)
	var r: int = w.economy.life.begin_sell(w, gen)
	t.eq(r, SimEconConst.RSN_LOCKED, "cannot sell in BUILDUP")
	var hq_owner_neutral: SimEntity = KIT.spawn_struct(w, DefTestKit.S_BARRACKS, -1, 40, 40)
	t.eq(w.economy.life.begin_sell(w, hq_owner_neutral), SimEconConst.RSN_NOT_OWNER, "neutral-owned structures cannot be sold")


func test_killed_while_selling_pays_nothing(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	_hq(w, 0)
	var gen: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600)
	KIT.run(w, 2)
	var before: int = w.players[0].credits
	w.submit_raw(0, SimCmd.sell(PackedInt32Array([gen.id])))
	KIT.run(w, 5)
	w.kill(gen, SimWorld.Cause.DAMAGE, 0, 1)
	KIT.run(w, SimEconConst.SELL_TICKS)
	t.eq(w.players[0].credits, before, "no refund when killed during the sale")


func test_death_unregisters_and_updates_power(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	_hq(w, 0)
	var gen: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600)
	var bar: SimEntity = KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 18, 10, 500)
	KIT.run(w, 2)
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.eq([pe.power_supply, pe.power_demand], [150, 30] as Array, "balance")
	t.eq(pe.producer_flat, PackedInt32Array([bar.id]), "producer list")
	t.check(bar.prod != null and bar.prod.is_primary, "first producer of its kind is primary")
	w.kill(gen, SimWorld.Cause.DAMAGE, 0, 1)
	KIT.run(w, 3)
	t.eq(pe.power_supply, 0, "generator loss")
	t.eq(pe.struct_count[gen.def_idx], 0, "counter")
	t.check(pe.power_state == SimEconConst.PW_SHORTAGE, "demand 30 > supply 0")


func test_free_collector_with_refinery(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	_hq(w, 0)
	KIT.spawn_struct(w, DefTestKit.S_REFINERY, 0, 14, 10, 1800)
	KIT.run(w, 2)
	var n: int = 0
	for u: SimEntity in w.units_of(0):
		if u.def_idx == KIT.uidx(DefTestKit.U_COLLECTOR):
			n += 1
			t.eq(u.paid_cost, 0, "free")
			t.check((u.econ.flags & SimEconConst.EF_FREE) != 0, "EF_FREE")
	t.eq(n, 1, "one free Collector")
	t.eq(KIT.econ(w, 0).refinery_ids.size(), 1, "refinery list")


func test_undeploy_hq_restores_mcv_value(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	var mcv: SimEntity = w.spawn_unit(KIT.uidx(DefTestKit.U_MCV), 0, 20 * 1024 + 512, 20 * 1024 + 512, 0, 0, 3000)
	w.step()
	var hq_id: int = w.economy.life.deploy_mcv(w, mcv)
	t.check(hq_id > 0, "deployed")
	w.step()
	var hq: SimEntity = w.get_entity(hq_id)
	t.eq(hq.econ.st, SimEconConst.ST_BUILDUP, "BUILDUP first")
	t.eq(hq.econ.mcv_paid_cost, 3000, "remembers the MCV cost")
	t.eq(hq.paid_cost, 0, "the HQ itself is free")
	KIT.run(w, 70)
	t.eq(hq.econ.st, SimEconConst.ST_ACTIVE, "active")
	t.eq(KIT.econ(w, 0).active_hq_count, 1, "counter")
	w.submit_raw(0, SimCmd.undeploy_hq(PackedInt32Array([hq_id])))
	w.step()
	t.eq(hq.econ.st, SimEconConst.ST_UNDEPLOYING, "undeploying")
	t.eq(KIT.econ(w, 0).active_hq_count, 0, "no construction anchor")
	KIT.run(w, SimEconConst.UNDEPLOY_TICKS + 2)
	t.is_null(w.get_entity(hq_id), "HQ gone")
	var found: SimEntity = null
	for u: SimEntity in w.units_of(0):
		if u.def_idx == KIT.uidx(DefTestKit.U_MCV):
			found = u
	if t.not_null(found, "an MCV again"):
		t.eq(found.paid_cost, 3000, "value restored: no income loop")


func test_deploy_blocked_reports_reason(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 1, 20, 20)  # an enemy structure on the site
	var mcv: SimEntity = w.spawn_unit(KIT.uidx(DefTestKit.U_MCV), 0, 21 * 1024 + 512, 21 * 1024 + 512, 0, 0, 3000)
	w.step()
	t.eq(w.economy.life.deploy_mcv(w, mcv), 0, "refused")
	var ev: Array[PackedInt32Array] = KIT.events_of(w, SimEconConst.EVT_ORDER_FAILED)
	t.eq(ev.size(), 1, "EVT_ORDER_FAILED")
	t.eq(ev[0][7], SimEconConst.RSN_STRUCTURE_BLOCK, "reason")
	t.check(w.is_alive(mcv.id), "the MCV stays")


func test_capture_moves_power(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	_hq(w, 0)
	_hq(w, 1, 60, 60)
	var gen: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600)
	KIT.run(w, 2)
	t.eq(KIT.econ(w, 0).power_supply, 150, "before")
	t.check(w.change_owner(gen.id, 1, SimEvent.OWNER_CAPTURE), "captured")
	KIT.run(w, 2)
	t.eq([KIT.econ(w, 0).power_supply, KIT.econ(w, 1).power_supply], [0, 150] as Array, "power moved with the structure")
	t.eq(KIT.econ(w, 1).struct_count[gen.def_idx], 1, "counter moved")
	t.eq(KIT.econ(w, 0).struct_count[gen.def_idx], 0, "old counter")


func test_neutral_power_and_income_after_capture(t: TestCtx) -> void:
	var d: GameData = DefTestKit.small_data()
	for rw: Dictionary in [{"power_n": 100}, {"income_mcpt": 250}]:
		var n: DefNeutral = DefNeutral.new()
		n.index = d.neutrals.size()
		n.id = "neutral.test%d" % n.index
		n.health = 1200
		n.radius = 1024
		n.capturable = true
		n.reward = rw
		d.neutrals.append(n)
	var w: SimWorld = KIT.make_world({"data": d})
	var sub: SimEntity = w.spawn_entity(SimEntity.Kind.NEUTRAL, d.neutrals.size() - 2, -1, 40 * 1024, 40 * 1024, 0, SimFlags.F_INITIAL)
	var depot: SimEntity = w.spawn_entity(SimEntity.Kind.NEUTRAL, d.neutrals.size() - 1, -1, 44 * 1024, 40 * 1024, 0, SimFlags.F_INITIAL)
	KIT.run(w, 3)
	t.eq([KIT.econ(w, 0).power_supply, KIT.econ(w, 1).power_supply], [0, 0] as Array, "neutral-owned: nobody gets the power")
	t.check(w.change_owner(sub.id, 0, SimEvent.OWNER_CAPTURE), "substation captured by P0")
	t.check(w.change_owner(depot.id, 1, SimEvent.OWNER_CAPTURE), "depot captured by P1")
	var before: int = w.players[1].credits
	KIT.run(w, 3)
	t.eq(KIT.econ(w, 0).power_supply, 100, "+100 power registered like a Generator delta")
	KIT.run(w, 200)
	t.eq(w.players[1].credits - before, 50, "+50 credits every 200 ticks")
	t.eq(KIT.econ(w, 1).stat_depot, 50, "depot statistic")
	w.change_owner(sub.id, 1, SimEvent.OWNER_CAPTURE)
	KIT.run(w, 2)
	t.eq([KIT.econ(w, 0).power_supply, KIT.econ(w, 1).power_supply], [0, 100] as Array, "the power moves on recapture")
