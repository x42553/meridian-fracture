extends RefCounted
## AIT (AI quality pass): the economy / expansion fixes (early MCV, MCV line exempt from the bank hold, expansion Refinery placement),
## the attack finishing rules (progress-aware attrition, static defense weight), the avoid-zone wiring (route graph, staging,
## placer, siege) and the staging cell. Real matches through AiSoakKit / AiXKit, a few pure unit tests.

const C: int = Fp.CELL


func _open_map_graph(w: int, h: int) -> AiRouteGraph:
	var g: AiRouteGraph = AiRouteGraph.new()
	g.bind_map(w, h, func(_x: int, _y: int, _mc: int) -> bool: return true)
	return g


# ------------------------------------------------------------------------------------------------ strength
func test_add_pct_scales_hp_dps_and_value(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40)
	var c: AiContext = AiXKit.ctx(m, 0)
	var tank: int = c.res.first(AiTypes.R_TANK_MAIN)
	var p: AiUnitProfile = c.unit_profile(tank)
	var one: AiStrengthGroup = AiStrengthGroup.new()
	one.add(p, 1, p.hp, p.value)
	var dbl: AiStrengthGroup = AiStrengthGroup.new()
	dbl.add_pct(p, p.hp, p.value, 200)
	t.eq(dbl.hp, one.hp * 2, "hp doubles")
	t.eq(dbl.value, one.value * 2, "value doubles")
	t.eq(dbl.total_dps_x100(), one.total_dps_x100() * 2, "dps doubles")
	var same: AiStrengthGroup = AiStrengthGroup.new()
	same.add_pct(p, p.hp, p.value, 100)
	t.eq(same.hp, one.hp, "100 percent is the plain add")
	t.eq(same.total_dps_x100(), one.total_dps_x100())
	AiSoakKit.dispose(m)


func test_static_defense_weight_raises_the_defender_group(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40, {"tuning": {"strength.static_mult_pct": 200}})
	var m2: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40)
	var v: PackedInt32Array = PackedInt32Array()
	for mm: Dictionary in [m, m2]:
		var c: AiContext = AiXKit.ctx(mm, 0)
		var h: PackedInt32Array = AiXKit.home(mm, 1)
		var tower: int = c.shared.resolver(c.view.roster_of(1)).structure_of_kind(AiTypes.StructKind.AT_TURRET)
		c.kb.ghosts.upsert(9001, tower, 1, h[0], h[1], c.tick, 100, 0, AiTypes.StructKind.AT_TURRET, 600)
		v.append(AiForce.enemy_group(c, h[0], h[1], 16 * C, 100).hp)
	t.gt(v[0], 0, "the tower ghost counts")
	t.eq(v[0], v[1] * 2, "static_mult_pct 200 doubles the tower in the defender group (%d vs %d)" % [v[0], v[1]])
	AiSoakKit.dispose(m)
	AiSoakKit.dispose(m2)


# ------------------------------------------------------------------------------------------------ attrition
func _wave(m: Dictionary, n: int) -> AiOpAttack:
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		ids.append(AiXKit.spawn(m, "unit.napc.guardian_tank", 0, h[0] + (4 + i) * C, h[1] + 3 * C, 800))
	AiXKit.settle(m)
	var e: PackedInt32Array = AiXKit.home(m, 1)
	var op: AiOpAttack = AiOpAttack.new()
	op.setup_wave(AiTypes.SquadKind.MAIN, ids, {"x": e[0], "y": e[1], "eid": -1, "value": 3000}, 400)
	t_assert(b.add_op(c, op), "wave starts")
	return op


func t_assert(cond: bool, _msg: String) -> void:
	assert(cond)


func test_attrition_presses_on_while_the_defenses_fall(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40, {"seed": 4})
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	var op: AiOpAttack = _wave(m, 8)
	op.measure(c, AiBudget.new())
	# the wave lost 40 % of its value within the window while the enemy structures in reach fell from 6000 to 2000
	op.initial_value = 1000
	op.value_now = 600
	op._samples = PackedInt32Array([c.tick - 100, 1000])
	op._gv = PackedInt32Array([6000])
	op.cx = AiXKit.home(m, 0)[0]
	op.cy = AiXKit.home(m, 0)[1]
	# no ghost value near the wave now: the peak (6000) minus the present (0) is the progress
	var held: bool = not op._attrition(c, b)
	t.check(held, "a wave that destroys 6000 of defenses for 400 of losses presses on")
	t.eq(b.stat("attr_progress"), 1)
	# the same losses without any progress: back
	var op2: AiOpAttack = _wave(m, 8)
	op2.measure(c, AiBudget.new())
	op2.initial_value = 1000
	op2.value_now = 600
	op2._samples = PackedInt32Array([c.tick - 100, 1000])
	op2._gv = PackedInt32Array([0])
	op2.r_now_q8 = 256
	t.check(op2._attrition(c, b), "the same losses without progress turn the wave back")
	t.eq(op2.state, AiTypes.OpState.RETREATING)
	AiSoakKit.dispose(m)


func test_attrition_threshold_rises_with_a_big_surplus(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40, {"seed": 4})
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	var op: AiOpAttack = _wave(m, 8)
	op.measure(c, AiBudget.new())
	op.initial_value = 1000
	op.value_now = 650  # 35 % lost: over the plain 25 %, under the 45 % of a wave that outweighs everything it knows
	op._samples = PackedInt32Array([c.tick - 100, 1000])
	op._gv = PackedInt32Array([0])
	op.set_state(c, AiTypes.OpState.ENGAGING)
	op.r_now_q8 = 4 * 256
	op._last_ratio_tick = c.tick
	t.check(not op._attrition(c, b), "a 4x wave keeps going at 35 % losses")
	var op2: AiOpAttack = _wave(m, 8)
	op2.measure(c, AiBudget.new())
	op2.initial_value = 1000
	op2.value_now = 650
	op2._samples = PackedInt32Array([c.tick - 100, 1000])
	op2._gv = PackedInt32Array([0])
	op2.set_state(c, AiTypes.OpState.ENGAGING)
	op2.r_now_q8 = 2 * 256
	op2._last_ratio_tick = c.tick
	t.check(op2._attrition(c, b), "a 2x wave turns back at 35 % losses")
	AiSoakKit.dispose(m)


# ------------------------------------------------------------------------------------------------ avoid zones
func test_route_detours_around_a_warning_zone(t: TestCtx) -> void:
	var g: AiRouteGraph = _open_map_graph(64, 64)
	var d: AiDispersal = AiDispersal.new()
	d.add_avoid(AiDispersal.AV_DANGER, 32 * C, 32 * C, 7 * C, 5000)
	g.tick_hint = 100
	var straight: PackedInt32Array = PackedInt32Array()
	var n0: int = g.route(4 * C, 32 * C, 60 * C, 32 * C, AiTypes.MoveClass.TRACKED, 0, straight)
	t.gt(n0, 0)
	var through0: bool = false
	for i: int in n0:
		if d.avoided(straight[2 * i], straight[2 * i + 1], AiDispersal.AV_DANGER, 100):
			through0 = true
	t.check(through0, "without the zone wired the straight route crosses it")
	g.avoid_zones = d.avoid
	var detour: PackedInt32Array = PackedInt32Array()
	var n1: int = g.route(4 * C, 32 * C, 60 * C, 32 * C, AiTypes.MoveClass.TRACKED, 0, detour)
	t.gt(n1, 0)
	var through1: bool = false
	for i: int in n1:
		if d.avoided(detour[2 * i], detour[2 * i + 1], AiDispersal.AV_DANGER, 100):
			through1 = true
	t.check(not through1, "with the zone wired the route goes around it")
	# an expired zone costs nothing
	g.tick_hint = 6000
	var after: PackedInt32Array = PackedInt32Array()
	g.route(4 * C, 32 * C, 60 * C, 32 * C, AiTypes.MoveClass.TRACKED, 0, after)
	t.eq(after, straight, "an expired zone no longer bends the route")


func test_staging_cell_is_not_inside_a_warning_zone(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40, {"seed": 4})
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	var prod: AiProduction = b.eco().production
	var sx: int = prod.stage_x >> Fp.CELL_SHIFT
	var sy: int = prod.stage_y >> Fp.CELL_SHIFT
	t.check(prod._stage_ok(c, sx, sy), "the current staging cell is acceptable")
	b.powers.dispersal.add_avoid(AiDispersal.AV_DEBRIS, sx * C + C / 2, sy * C + C / 2, 3 * C, c.tick + 1000)
	t.check(not prod._stage_ok(c, sx, sy), "a debris zone over the cell makes it unacceptable")
	b.powers.dispersal.add_avoid(AiDispersal.AV_NO_FIRE_ARTY, (sx + 20) * C, sy * C, 3 * C, c.tick + 1000)
	t.check(prod._stage_ok(c, sx + 20, sy) or not c.view.passable(sx + 20, sy, AiTypes.MoveClass.TRACKED), "a no-fire zone does not matter for the staging cell")
	AiSoakKit.dispose(m)


func test_placer_keeps_out_of_a_no_build_zone(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 600, {"seed": 4, "credits": 12000})
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	var eco: AiEconomy = b.eco()
	var def: int = c.res.structure_of_kind(AiTypes.StructKind.GENERATOR)
	var job: AiJob = eco.placer.request(def, AiPlacer.Site.BACK)
	var bg: AiBudget = AiBudget.new()
	bg.reset(1 << 20, 1 << 20)
	while not job.done:
		job.step(bg)
	var first: PackedInt32Array = job.result()
	t.eq(first.size(), 3, "a generator site exists")
	if first.size() != 3:
		return
	b.powers.dispersal.add_avoid(AiDispersal.AV_NO_BUILD, first[0] * C + C / 2, first[1] * C + C / 2, 2 * C, c.tick + 2000)
	var job2: AiJob = eco.placer.request(def, AiPlacer.Site.BACK)
	while not job2.done:
		job2.step(bg)
	var second: PackedInt32Array = job2.result()
	t.eq(second.size(), 3, "another site exists")
	if second.size() == 3:
		t.check(maxi(absi(second[0] - first[0]), absi(second[1] - first[1])) >= 2, "the new site is outside the no-build zone (%s vs %s)" % [str(first), str(second)])
	AiSoakKit.dispose(m)


func test_field_site_beyond_the_build_radius_is_refused_fast(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 600, {"seed": 4, "credits": 12000})
	var c: AiContext = AiXKit.ctx(m, 0)
	var eco: AiEconomy = AiXKit.brain(m, 0).eco()
	var def: int = c.res.structure_of_kind(AiTypes.StructKind.REFINERY)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var far: PackedInt32Array = AiXKit.toward(h, AiXKit.home(m, 1), 40)
	var job: AiJob = eco.placer.request(def, AiPlacer.Site.FIELD, far[0], far[1])
	var bg: AiBudget = AiBudget.new()
	bg.reset(1 << 20, 1 << 20)
	while not job.done:
		job.step(bg)
	t.eq(job.result().size(), 0, "no refinery site 40 cells from the only HQ")
	AiSoakKit.dispose(m)


# ------------------------------------------------------------------------------------------------ economy
func test_expansion_starts_before_the_radar_and_places_its_refinery(t: TestCtx) -> void:
	# the first MCV is due once two Refineries, a Factory and two Collectors stand (about 4 minutes), not after the Radar / opener
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NEC, AiXKit.R_NAPC]), [2, 0], 9000, {"seed": 6, "credits": 7500, "pers_over": {0: {"expand": 0}}})
	var b: AiBrain = AiXKit.brain(m, 0)
	var ex: AiExpansion = b.eco().expansion
	t.check(ex.started > 0, "an expansion started within 7.5 minutes at Hard (started %d)" % ex.started)
	t.eq(AiXKit.ctx(m, 0).tune("exp.early", 1), 1)
	AiSoakKit.play(m, 6000)
	var rdef: int = AiXKit.ctx(m, 0).res.structure_of_kind(AiTypes.StructKind.REFINERY)
	var refs: int = 0
	for e: SimEntity in AiXKit.world(m).structures_of(0):
		if e.def_idx == rdef and (e.flags & SimFlags.F_GONE) == 0:
			refs += 1
	t.check(ex.done == 0 or refs >= 3, "the new HQ got a Refinery (expansions done %d, refineries %d)" % [ex.done, refs])
	t.eq((m["errors"] as PackedStringArray).size(), 0)
	AiSoakKit.dispose(m)


func test_collector_target_boost_applies_above_easy_only(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 3000, {"seed": 4, "tuning": {"econ.collector_k_boost_x10": 10}})
	var hard: AiEconomy = AiXKit.brain(m, 0).eco()
	var easy: AiEconomy = AiXKit.brain(m, 1).eco()
	t.ge(hard.collector_target, 2, "Hard targets at least 2 collectors (%d)" % hard.collector_target)
	# k = 2.0 + 1.0 per refinery at Hard, 1.0 at Easy (no boost)
	t.eq(hard.collector_target, mini((hard.refineries_active * 30 + 9) / 10, maxi(hard.collector_target, 1)) if hard.refineries_active > 0 else hard.collector_target)
	t.le(easy.collector_target, maxi(easy.refineries_active, 1), "Easy keeps one collector per refinery")
	AiSoakKit.dispose(m)


# ------------------------------------------------------------------------------------------------ strategy
func test_enemy_peak_decays_and_adds_remote_defenders(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40, {"seed": 4})
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	var e: PackedInt32Array = AiXKit.home(m, 1)
	var plain: AiStrengthGroup = b.attack.defenders(c, e[0], e[1], c.kb.primary)
	b.strategy.enemy_peak = 6000
	var with_peak: AiStrengthGroup = b.attack.defenders(c, e[0], e[1], c.kb.primary)
	t.gt(with_peak.value, plain.value, "a remembered army that is not at the target joins its defenders (%d vs %d)" % [with_peak.value, plain.value])
	b.strategy._track_enemy_peak(c)
	t.lt(b.strategy.enemy_peak, 6000, "the peak decays")
	t.gt(b.strategy.enemy_peak, 5800, "slowly: about 1.5 percent per evaluation")
	b.strategy.enemy_peak = 0
	b.strategy._track_enemy_peak(c)
	t.ge(b.strategy.enemy_peak, 0)
	AiSoakKit.dispose(m)


func test_target_weights_when_ahead(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40, {"seed": 4})
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	var pl: AiAttackPlanner = b.attack
	t.eq(pl._weight_of(c, AiTypes.StructKind.HQ, 2, 2, false, false), AiAttackPlanner.W_HQ)
	t.eq(pl._weight_of(c, AiTypes.StructKind.HQ, 2, 2, false, true), AiAttackPlanner.W_HQ * 2, "ahead: the HQ is worth twice")
	t.gt(pl._weight_of(c, AiTypes.StructKind.FACTORY, 2, 2, false, true), pl._weight_of(c, AiTypes.StructKind.FACTORY, 2, 2, false, false), "ahead: production first")
	t.eq(pl._weight_of(c, AiTypes.StructKind.BARRACKS, 2, 2, false, true), pl._weight_of(c, AiTypes.StructKind.BARRACKS, 2, 2, false, false), "barracks unchanged")
	AiSoakKit.dispose(m)


func test_superweapon_is_built_earlier_when_ahead(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40, {"seed": 4})
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	b.strategy.ratio_q8 = 256
	var normal: int = b.powers.sw.min_start_tick(c)
	b.strategy.ratio_q8 = 3 * 256
	var ahead: int = b.powers.sw.min_start_tick(c)
	t.lt(ahead, normal, "ahead: the launcher is due earlier (%d vs %d)" % [ahead, normal])
	t.gt(ahead * 100, normal * 50, "but not absurdly early")
	AiSoakKit.dispose(m)


func test_expansion_mcv_gets_a_free_factory_line(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 3600, {"seed": 4, "credits": 12000})
	var b: AiBrain = AiXKit.brain(m, 0)
	var eco: AiEconomy = b.eco()
	t.check(not eco.mcv_wanted_unqueued(), "no expansion in training: nothing is held back")
	eco.expansion.state = AiExpansion.State.TRAINING
	eco.expansion._t_start = AiXKit.ctx(m, 0).tick
	var def: int = AiXKit.ctx(m, 0).res.first(AiTypes.R_MCV)
	if eco.unit_queued[def] == 0 and eco.role_have(AiTypes.R_MCV) == 0:
		t.check(eco.mcv_wanted_unqueued(), "an MCV is wanted and not queued")
		var row: int = eco.mcv_slot_row()
		t.ge(row, 0, "a factory line is reserved for it")
		if row >= 0:
			for i: int in eco.prod_eid.size():
				if eco.prod_kind[i] == eco.prod_kind[row]:
					t.le(eco.prod_qlen[row], eco.prod_qlen[i], "the reserved line has the shortest queue")
	eco.expansion.state = AiExpansion.State.IDLE
	AiSoakKit.dispose(m)


func test_defense_scale_by_level_and_override(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40, {"seed": 4})
	t.eq(AiXKit.brain(m, 0).eco()._defense_scale(AiXKit.ctx(m, 0)), 40, "Hard spends 40 percent of the defense share")
	t.eq(AiXKit.brain(m, 1).eco()._defense_scale(AiXKit.ctx(m, 1)), 100, "Easy keeps its defenses")
	var m2: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 40, {"seed": 4, "tuning": {"econ.defense_scale_pct": 0}})
	t.eq(AiXKit.brain(m2, 0).eco()._defense_scale(AiXKit.ctx(m2, 0)), 0, "the override applies to every level")
	AiSoakKit.dispose(m)
	AiSoakKit.dispose(m2)


func test_economy_waits_for_the_army_when_it_is_small(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 7200, {"seed": 4})
	var c: AiContext = AiXKit.ctx(m, 0)
	var eco: AiEconomy = AiXKit.brain(m, 0).eco()
	eco.refresh(c, AiBudget.new())
	AiXKit.brain(m, 0).strategy.enemy_peak = 0
	var need: int = AiAttackPlanner.assumed_army(c) * 60 / 100
	t.gt(need, 0)
	eco.army_value = need / 2
	eco.army_units = 5
	t.check_false(eco.econ_safe(c), "half the army the enemy is believed to field is not safe")
	eco.army_value = need + 100
	t.check(eco.econ_safe(c), "enough army: the economy may grow")
	AiSoakKit.dispose(m)


func test_personality_eco_dial_adds_collectors(t: TestCtx) -> void:
	var a: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 3000, {"seed": 4})
	var b: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 3000, {"seed": 4, "pers_over": {0: {"eco_x10": 10}}})
	var ea: AiEconomy = AiXKit.brain(a, 0).eco()
	var eb: AiEconomy = AiXKit.brain(b, 0).eco()
	t.eq(AiXKit.ctx(b, 0).pers.eco_x10, 10)
	t.ge(eb.collector_target, ea.collector_target, "a greedier roster targets at least as many collectors")
	AiSoakKit.dispose(a)
	AiSoakKit.dispose(b)


func test_target_search_works_with_an_empty_budget(t: TestCtx) -> void:
	# a 100-unit army leaves the slot budget empty before the target search: the first cluster must still be scored
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 600, {"seed": 4, "fog": false})
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	AiXKit.settle(m, 60)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 6:
		ids.append(AiXKit.spawn(m, "unit.napc.guardian_tank", 0, h[0] + (4 + i) * C, h[1] + 3 * C, 800))
	AiXKit.settle(m)
	var fg: AiStrengthGroup = AiForce.own_group(c, ids)
	var empty: AiBudget = AiBudget.new()
	empty.left = 0
	var tgt: Dictionary = b.attack.pick_target(c, empty, h[0], h[1], fg, -1, -1, 0, 0)
	t.check(not tgt.is_empty(), "a target is found although the budget is empty")
	AiSoakKit.dispose(m)


func test_enemy_units_in_the_ring_join_the_defenders(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 600, {"seed": 4, "fog": false})
	var c: AiContext = AiXKit.ctx(m, 0)
	var e: PackedInt32Array = AiXKit.home(m, 1)
	var tank: int = AiXKit.ctx(m, 1).res.first(AiTypes.R_TANK_MAIN)
	var p: AiUnitProfile = c.shared.unit_profile(c.view.roster_of(1), tank)
	t.check(p != null)
	var near_def: String = (m["world"] as SimWorld).data.units[tank].id
	for i: int in 3:
		AiXKit.spawn(m, near_def, 1, e[0] + (22 + i) * C, e[1], 800)  # 22 cells from the target: outside the 16 cell defense radius
	AiXKit.settle(m, 60)
	var g0: AiStrengthGroup = AiStrengthGroup.new()
	AiForce.add_ring(c, g0, e[0], e[1], 16 * C, 45 * C, 200, 60)
	t.gt(g0.value, 0, "units 22 cells away count as reinforcements")
	var g1: AiStrengthGroup = AiStrengthGroup.new()
	AiForce.add_ring(c, g1, e[0], e[1], 30 * C, 45 * C, 200, 60)
	t.eq(g1.value, 0, "units inside the inner radius are not counted twice")
	AiSoakKit.dispose(m)
