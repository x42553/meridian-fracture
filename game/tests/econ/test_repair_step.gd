extends RefCounted
## 10.1-F repair (economy 5.10 / 5.11) on REAL match worlds: the Engineer baseline (1 % of max health per second costing
## 0.5 % of the paid price per second), the African Empire and Standardized Parts cost factors, Cambodia's structure rate,
## Tunnel Workshops on defenses only, the credit pause, source stacking, the claim, the categories and their legal targets.

const K := preload("res://tests/support/sim_work_kit.gd")


func _tank(w: SimWorld, id: String, pid: int, paid: int, hp: int = 1) -> SimEntity:
	var hq: SimEntity = w.structures_of(pid)[0]
	var u: SimEntity = K.unit_near(w, id, pid, hq.x + 5 * K.CELL, hq.y + 5 * K.CELL, paid)
	u.hp = hp
	return u


## Steps the primitive by hand (one call per tick) until full health; returns [ticks, credits spent].
func _repair_fully(w: SimWorld, rep: SimEntity, target: SimEntity, rc: int, max_ticks: int = 10000) -> PackedInt32Array:
	var c0: int = w.players[target.owner].credits if rep == null else w.players[rep.owner].credits
	var n: int = 0
	while target.hp < target.hp_max and n < max_ticks:
		SimEconomyWork.repair_step(w, rep, target, rc, SimEconConst.RS_UNIT)
		n += 1
	var c1: int = w.players[target.owner].credits if rep == null else w.players[rep.owner].credits
	return PackedInt32Array([n, c0 - c1])


func test_engineer_baseline(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 20000})
	var tank: SimEntity = _tank(w, "unit.napc.guardian_tank", 0, 1100)
	var eng: SimEntity = K.engineer_at(w, 0, tank)
	var mh: int = tank.hp_max
	var r: PackedInt32Array = _repair_fully(w, eng, tank, SimEconConst.RC_ENGINEER)
	var gain: int = mh - 1
	t.eq(r[0], (gain * SimEconomyWork.HP_UNIT + mh * 100 - 1) / (mh * 100), "1 %% of max hp per second: full repair in %d ticks" % r[0])
	t.eq(r[1], 1100 * 5000 * gain / (10000 * mh), "credits: 0.5 %% of the paid price per 1 %% hp, remainders carried exactly")
	t.ge(r[0], 1990, "about 100 s at 20 ticks per second")
	t.le(r[0], 2000, "about 100 s")
	t.eq(tank.hp, mh, "full health")


func test_ae_and_standardized_parts_cost(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 20000, "rosters": PackedStringArray([K.AE, K.NAPC])})
	var tank: SimEntity = _tank(w, "unit.ae.buffalo_tank", 0, 1100)
	var eng: SimEntity = K.engineer_at(w, 0, tank)
	var mh: int = tank.hp_max
	var r: PackedInt32Array = _repair_fully(w, eng, tank, SimEconConst.RC_ENGINEER)
	t.eq(r[1], 1100 * 3750 * (mh - 1) / (10000 * mh), "African Empire land vehicles: 75 %% of the cost (%d)" % r[1])
	var d: SimWorld = K.world({"credits": 20000, "rosters": PackedStringArray(["roster.def.vanilla", K.NAPC])})
	var t2: SimEntity = _tank(d, "unit.def.hammer_tank", 0, 1100)
	var e2: SimEntity = K.engineer_at(d, 0, t2)
	d.economy.set_knob_base(d, 0, SimEconConst.K_REPAIR_COST_ENG_VEH_BP, 8500)
	var r2: PackedInt32Array = _repair_fully(d, e2, t2, SimEconConst.RC_ENGINEER)
	t.eq(r2[1], 1100 * 4250 * (t2.hp_max - 1) / (10000 * t2.hp_max), "Standardized Parts: 85 %% of 50 %% = 42.5 %% (%d)" % r2[1])


func test_credit_pause_keeps_accumulators(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 20000})
	var tank: SimEntity = _tank(w, "unit.napc.guardian_tank", 0, 1100)
	var eng: SimEntity = K.engineer_at(w, 0, tank)
	for _i: int in 200:
		SimEconomyWork.repair_step(w, eng, tank, SimEconConst.RC_ENGINEER, SimEconConst.RS_UNIT)
	var hp: int = tank.hp
	var ec: SimCompEcon = tank.econ
	var acc_hp: int = ec.repair_acc_hp
	var acc_cost: int = ec.repair_acc_cost
	w.players[0].credits = 0
	var paused: int = 0
	for _i: int in 100:
		if SimEconomyWork.repair_step(w, eng, tank, SimEconConst.RC_ENGINEER, SimEconConst.RS_UNIT) < 0:
			paused += 1
	# a step that owes no whole credit still heals (cost accumulates below 1 credit); once one is due it pauses
	t.check(paused > 0, "the step pauses when a whole credit is due and the payer has none (%d)" % paused)
	w.players[0].credits = 5
	var before_credits: int = w.players[0].credits
	var got: int = 0
	for _i: int in 60:
		got += maxi(SimEconomyWork.repair_step(w, eng, tank, SimEconConst.RC_ENGINEER, SimEconConst.RS_UNIT), 0)
	t.check(got > 0, "resumes once credits exist")
	t.check(w.players[0].credits < before_credits, "and pays")
	t.check(tank.hp > hp, "hp grew again")
	t.check(acc_hp >= 0 and acc_cost >= 0, "accumulators are non-negative")


func test_stacking_and_claim(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 20000})
	var hq: SimEntity = w.structures_of(0)[0]
	hq.hp = 100
	var e: SimEntity = K.engineer_at(w, 0, hq)
	var one: int = 0
	var both: int = 0
	var a: SimWorld = w
	for _i: int in 100:
		one += maxi(SimEconomyWork.repair_step(a, e, hq, SimEconConst.RC_ENGINEER, SimEconConst.RS_UNIT), 0)
	hq.hp = 100
	hq.econ.repair_acc_hp = 0
	hq.econ.repair_acc_cost = 0
	for _i: int in 100:
		both += maxi(SimEconomyWork.repair_step(a, e, hq, SimEconConst.RC_ENGINEER, SimEconConst.RS_UNIT), 0)
		both += maxi(SimEconomyWork.repair_step(a, null, hq, SimEconConst.RC_WRENCH, SimEconConst.RS_WRENCH), 0)
	t.check(both >= one * 2 - 1 and both <= one * 2 + 1, "wrench + Engineer stack (%d vs %d)" % [both, one])
	# two Engineers on one vehicle: the second waits on the claim, the total rate is the single rate
	var w2: SimWorld = K.world({"credits": 20000})
	var tank: SimEntity = _tank(w2, "unit.napc.guardian_tank", 0, 1100, 100)
	var e1: SimEntity = K.engineer_at(w2, 0, tank, 0)
	var e2: SimEntity = K.engineer_at(w2, 0, tank, 1)
	K.cmd(w2, 0, SimCmd.repair(PackedInt32Array([e1.id, e2.id]), tank.id, 0))
	K.run(w2, 400)
	var gained: int = tank.hp - 100
	var single: int = tank.hp_max * 100 * 400 / SimEconomyWork.HP_UNIT
	t.check(gained >= single - 8 and gained <= single + 8, "two Engineers heal like one (%d vs %d)" % [gained, single])
	t.eq(tank.econ.unit_repairer_id, e1.id, "the lowest id got the claim")
	K.run(w2, 100)
	t.check(e2.orders.is_empty(), "the second Engineer gave up with BUSY after 100 ticks")
	t.check(K.events(w2, SimEconConst.EVT_ORDER_FAILED).size() >= 1, "EVT_ORDER_FAILED (economy) emitted")


func test_repair_order_full_cycle(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 20000})
	var tank: SimEntity = _tank(w, "unit.napc.guardian_tank", 0, 1100, 700)
	var eng: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, tank.x - 8 * K.CELL, tank.y, 500)
	var c0: int = w.players[0].credits
	K.cmd(w, 0, SimCmd.repair(PackedInt32Array([eng.id]), tank.id, 0))
	var n: int = K.run_until(w, func(_ww: SimWorld) -> bool: return tank.hp >= tank.hp_max, 1500)
	t.check(n > 0, "repaired to full (%d ticks)" % n)
	K.run(w, 3)
	t.check(eng.orders.is_empty(), "order DONE at full health")
	t.eq(tank.econ.unit_repairer_id, 0, "claim released")
	var spent: int = c0 - w.players[0].credits
	var gain: int = tank.hp_max - 700
	t.check(absi(spent - 1100 * 5000 * gain / (10000 * tank.hp_max)) <= 1, "credits spent (%d) match the rule" % spent)
	t.eq(w.players[0].econ.stat_spent_repair, spent, "statistic")


func test_structure_rates(t: TestCtx) -> void:
	# Cambodia (repair_progress_rate 12500): 1.25 % of max hp per second, cost per hp unchanged
	var w: SimWorld = K.world({"credits": 50000, "rosters": PackedStringArray(["roster.han.cambodia", K.NAPC])})
	var hq: SimEntity = w.structures_of(0)[0]
	hq.hp = 100
	var e: SimEntity = K.engineer_at(w, 0, hq)
	var got: int = 0
	for _i: int in 200:
		got += maxi(SimEconomyWork.repair_step(w, e, hq, SimEconConst.RC_ENGINEER, SimEconConst.RS_UNIT), 0)
	var expect: int = hq.hp_max * 125 * 200 / SimEconomyWork.HP_UNIT
	t.check(absi(got - expect) <= 1, "Cambodia structure repair 1.25 %%/s (%d vs %d)" % [got, expect])
	# the base roster: 1 %/s
	var w2: SimWorld = K.world({"credits": 50000})
	var hq2: SimEntity = w2.structures_of(0)[0]
	hq2.hp = 100
	var e2: SimEntity = K.engineer_at(w2, 0, hq2)
	var got2: int = 0
	for _i: int in 200:
		got2 += maxi(SimEconomyWork.repair_step(w2, e2, hq2, SimEconConst.RC_ENGINEER, SimEconConst.RS_UNIT), 0)
	t.check(absi(got2 - hq2.hp_max * 100 * 200 / SimEconomyWork.HP_UNIT) <= 1, "base 1 %%/s (%d)" % got2)
	# HQ repair basis is the MCV price when the HQ was free
	t.eq(SimEconomyWork.repair_basis_cost(w2, hq2), 3000, "free HQ: basis = one MCV (3000)")


func test_tunnel_workshops_defense_only(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 50000, "rosters": PackedStringArray([K.NEC, K.NAPC])})
	var def_idx: int = -1
	for s: DefStructure in w.data.structures:
		if (s.tags & DefEnums.ST_DEFENSE) != 0 and w.players[0].roster.has_structure(s.index) and s.fp_w * s.fp_h <= 4:
			def_idx = s.index
			break
	t.check(def_idx >= 0, "a defense structure exists in the roster")
	var hq: SimEntity = w.structures_of(0)[0]
	var site: PackedInt32Array = PackedInt32Array([0, 0])
	t.check(SimPlacement.find_site(w, 0, def_idx, hq.x >> SimConfig.CELL_SHIFT, (hq.y >> SimConfig.CELL_SHIFT) + 4, 10, site), "site for the defense")
	var d: SimEntity = w.economy.life.place(w, 0, def_idx, site[0], site[1], 0, 1530)
	K.run(w, 40)
	d.hp = 1
	hq.hp = 1
	var e: SimEntity = K.engineer_at(w, 0, hq)
	w.economy.set_knob_base(w, 0, SimEconConst.K_REPAIR_RATE_DEF_BP, 12500)
	var gd: int = 0
	var gh: int = 0
	for _i: int in 200:
		gd += maxi(SimEconomyWork.repair_step(w, e, d, SimEconConst.RC_ENGINEER, SimEconConst.RS_UNIT), 0)
		gh += maxi(SimEconomyWork.repair_step(w, e, hq, SimEconConst.RC_ENGINEER, SimEconConst.RS_UNIT), 0)
	t.check(absi(gd - d.hp_max * 125 * 200 / SimEconomyWork.HP_UNIT) <= 1, "defense repaired at 1.25 %%/s (%d)" % gd)
	t.check(absi(gh - hq.hp_max * 100 * 200 / SimEconomyWork.HP_UNIT) <= 1, "other structures keep 1 %%/s (%d)" % gh)


func test_categories_and_targets(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 50000, "rosters": PackedStringArray(["roster.han.vanilla", K.NAPC])})
	var hq: SimEntity = w.structures_of(0)[0]
	var tank: SimEntity = _tank(w, "unit.han.ox_tank", 0, 850, 100)
	var lotus: SimEntity = K.unit_near(w, "unit.han.lotus_drone_tender", 0, hq.x + 8 * K.CELL, hq.y, 585)
	var a: DefAbility = SimEconomyWork.repair_ability(w, lotus)
	t.eq(SimEconomyWork.repair_category(a), SimEconConst.RC_TENDER, "Lotus is a TENDER")
	t.eq(SimEconomyWork.repair_can_target(w, lotus, lotus), SimEconConst.RSN_BAD_TARGET, "never itself")
	t.eq(SimEconomyWork.repair_can_target(w, lotus, tank), SimEconConst.RSN_WRONG_KIND, "manned tanks are not legal (unmanned land units only)")
	var mek: SimEntity = K.unit_near(w, "unit.han.mekong_field_engineer", 0, hq.x + 9 * K.CELL, hq.y, 520)
	t.eq(SimEconomyWork.repair_category(SimEconomyWork.repair_ability(w, mek)), SimEconConst.RC_FIELD_ENGINEER, "Mekong Field Engineer")
	t.eq(SimEconomyWork.repair_can_target(w, mek, hq), SimEconConst.RSN_OK, "structures are legal")
	t.eq(SimEconomyWork.repair_can_target(w, mek, tank), SimEconConst.RSN_WRONG_KIND, "vehicles are not")
	var eng: SimEntity = K.engineer_at(w, 0, hq)
	t.eq(SimEconomyWork.repair_can_target(w, eng, tank), SimEconConst.RSN_OK, "Engineer repairs land vehicles")
	t.eq(SimEconomyWork.repair_can_target(w, eng, w.structures_of(1)[0]), SimEconConst.RSN_BAD_TARGET, "not enemy structures")
	tank.flags |= SimFlags.F_NO_REPAIR
	t.eq(SimEconomyWork.repair_can_target(w, eng, tank), SimEconConst.RSN_DECOY, "EF_NO_REPAIR")
	tank.flags &= ~SimFlags.F_NO_REPAIR
	var infantry: SimEntity = K.unit_near(w, "unit.shared.engineer", 0, hq.x + 3 * K.CELL, hq.y + 6 * K.CELL, 500)
	t.eq(SimEconomyWork.repair_can_target(w, eng, infantry), SimEconConst.RSN_WRONG_KIND, "not infantry")
	# Pioneers (NEC / SAP): defenses only
	var w3: SimWorld = K.world({"rosters": PackedStringArray(["roster.sap.vanilla", K.NAPC])})
	var pio: SimEntity = K.unit_near(w3, "unit.sap.combat_pioneer", 0, w3.structures_of(0)[0].x + 6 * K.CELL, w3.structures_of(0)[0].y, 550)
	t.eq(SimEconomyWork.repair_category(SimEconomyWork.repair_ability(w3, pio)), SimEconConst.RC_PIONEER, "Combat Pioneer")
	t.eq(SimEconomyWork.repair_can_target(w3, pio, w3.structures_of(0)[0]), SimEconConst.RSN_WRONG_KIND, "the HQ is not a defense")
	# Technician: land vehicles or ships
	var w4: SimWorld = K.world({"rosters": PackedStringArray(["roster.pd.vanilla", K.NAPC])})
	var tech: SimEntity = K.unit_near(w4, "unit.pd.reef_technician", 0, w4.structures_of(0)[0].x + 6 * K.CELL, w4.structures_of(0)[0].y, 475)
	t.eq(SimEconomyWork.repair_category(SimEconomyWork.repair_ability(w4, tech)), SimEconConst.RC_TECHNICIAN, "Reef Technician")
	var pt: SimEntity = K.unit_near(w4, "unit.pd.tide_tank", 0, w4.structures_of(0)[0].x + 8 * K.CELL, w4.structures_of(0)[0].y, 900)
	t.eq(SimEconomyWork.repair_can_target(w4, tech, pt), SimEconConst.RSN_OK, "Technician repairs a land vehicle")
	t.eq(SimEconomyWork.repair_can_target(w4, tech, w4.structures_of(0)[0]), SimEconConst.RSN_WRONG_KIND, "but no structure")


func _place(w: SimWorld, pid: int, s_idx: int, paid: int) -> SimEntity:
	var hq: SimEntity = w.structures_of(pid)[0]
	var site: PackedInt32Array = PackedInt32Array([0, 0])
	if not SimPlacement.find_site(w, pid, s_idx, hq.x >> SimConfig.CELL_SHIFT, (hq.y >> SimConfig.CELL_SHIFT) + 4, 10, site):
		return null
	var e: SimEntity = w.economy.life.place(w, pid, s_idx, site[0], site[1], 0, paid)
	K.run(w, SimEconConst.BUILDUP_TICKS + 2)
	return e


func test_wrench_loop(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 50000})
	var gen_idx: int = -1
	for s: DefStructure in w.data.structures:
		if s.power > 0 and w.players[0].roster.has_structure(s.index):
			gen_idx = s.index
			break
	var gen: SimEntity = _place(w, 0, gen_idx, 600)
	t.check(gen != null, "generator placed")
	gen.hp = gen.hp_max - 40
	K.cmd(w, 0, SimCmd.set_struct_repair(PackedInt32Array([gen.id]), 1))
	var c0: int = w.players[0].credits
	var n: int = K.run_until(w, func(_ww: SimWorld) -> bool: return gen.hp >= gen.hp_max, 3000)
	t.check(n > 0, "wrench repaired the generator (%d ticks)" % n)
	K.run(w, 2)
	t.check(not gen.econ.repair_on, "auto-off at full health")
	t.check((gen.flags & SimFlags.F_REPAIR_ON) == 0, "flag cleared")
	t.check(w.players[0].credits < c0, "the wrench costs credits")
	t.check(SimEconomyWork.repair_sources(gen.econ, w.tick) == 0, "no source once it stopped")
	# wrench + Engineer at the same time repair twice as fast; the Engineer takes the claim
	gen.hp = 100
	K.cmd(w, 0, SimCmd.set_struct_repair(PackedInt32Array([gen.id]), 1))
	var eng: SimEntity = K.engineer_at(w, 0, gen)
	K.cmd(w, 0, SimCmd.repair(PackedInt32Array([eng.id]), gen.id, 0))
	K.run(w, 100)
	var gained: int = gen.hp - 100
	var single: int = gen.hp_max * 100 * 100 / SimEconomyWork.HP_UNIT
	t.check(gained >= single * 2 - 6 and gained <= single * 2 + 2, "two sources stack (%d vs 2 x %d)" % [gained, single])
	t.eq(SimEconomyWork.repair_sources(gen.econ, w.tick), SimEconConst.RS_UNIT | SimEconConst.RS_WRENCH, "both source bits reported")


func test_airfield_pad_repair(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 50000})
	var af_idx: int = -1
	var ac_idx: int = -1
	for s: DefStructure in w.data.structures:
		if s.queue_kind == DefEnums.QueueKind.AIRCRAFT and w.players[0].roster.has_structure(s.index):
			af_idx = s.index
			break
	for u: int in w.players[0].roster.producible_units:
		if w.data.units[u].home_layer == SimEntity.Layer.AIR and w.data.units[u].producer == af_idx and (w.data.units[u].tags & DefEnums.UT_AIRCRAFT) != 0:
			ac_idx = u
			break
	t.check(af_idx >= 0 and ac_idx >= 0, "the roster has an airfield and an aircraft")
	var af: SimEntity = _place(w, 0, af_idx, 1500)
	t.check(af != null and af.prod != null and af.prod.pad_ent.size() > 0, "airfield with pads")
	var id: int = w.production.spawn_from_producer(w, af, ac_idx, 1000)
	t.check(id != 0, "aircraft on a pad")
	var ac: SimEntity = w.get_entity(id)
	K.run(w, 5)
	ac.hp = ac.hp_max / 2
	var hp0: int = ac.hp
	var c0: int = w.players[0].credits
	K.run(w, 200)
	var gained: int = ac.hp - hp0
	var expect: int = ac.hp_max * 300 * 200 / SimEconomyWork.HP_UNIT
	t.check(gained > 0 and absi(gained - expect) <= 2 or ac.hp >= ac.hp_max, "pads repair 3 %%/s (%d vs %d)" % [gained, expect])
	t.check(w.players[0].credits < c0, "the owner pays")
	t.check(SimEconomyWork.repair_sources(ac.econ, w.tick) == SimEconConst.RS_PAD, "source PAD")


func test_technician_and_tender_knobs(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 50000, "rosters": PackedStringArray(["roster.pd.vanilla", K.NAPC])})
	var hq: SimEntity = w.structures_of(0)[0]
	var tech: SimEntity = K.unit_near(w, "unit.pd.reef_technician", 0, hq.x + 6 * K.CELL, hq.y, 475)
	var tank: SimEntity = K.unit_near(w, "unit.pd.tide_tank", 0, hq.x + 8 * K.CELL, hq.y, 900)
	tank.hp = 10
	var base: int = 0
	for _i: int in 200:
		base += maxi(SimEconomyWork.repair_step(w, tech, tank, SimEconConst.RC_TECHNICIAN, SimEconConst.RS_UNIT), 0)
	t.check(absi(base - tank.hp_max * 100 * 200 / SimEconomyWork.HP_UNIT) <= 1, "Technician baseline 1 %%/s (%d)" % base)
	w.economy.set_knob_base(w, 0, SimEconConst.K_REPAIR_RATE_TECH_BP, 12500)
	tank.hp = 10
	tank.econ.repair_acc_hp = 0
	tank.econ.repair_acc_cost = 0
	var fast: int = 0
	for _i: int in 200:
		fast += maxi(SimEconomyWork.repair_step(w, tech, tank, SimEconConst.RC_TECHNICIAN, SimEconConst.RS_UNIT), 0)
	t.check(absi(fast - tank.hp_max * 125 * 200 / SimEconomyWork.HP_UNIT) <= 1, "Expeditionary Maintenance: 1.25 %%/s (%d)" % fast)
