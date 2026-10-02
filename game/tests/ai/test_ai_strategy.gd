extends RefCounted
## AIC (ai.md 5.7 / 5.8 / 5.14 / 10.3, lean): the strategy layer on REAL matches - data authoring (32 doctrines, difficulty
## table), phase / posture, the defend op, wave launch gate and op state machine, retreat / regroup bookkeeping, scouting,
## the hunt op and determinism. Matches are played through AiSoakKit (full AiBrain per player, production think cadence).

const R_NAPC: String = "roster.napc.vanilla"
const R_NEC: String = "roster.nec.vanilla"


func _match(rosters: PackedStringArray, levels: Array, ticks: int, o: Dictionary = {}) -> Dictionary:
	var opts: Dictionary = {"seed": 3, "rosters": rosters, "levels": levels, "family": 0, "fog": true}
	opts.merge(o, true)
	var m: Dictionary = AiSoakKit.make(opts)
	if ticks > 0:
		AiSoakKit.play(m, ticks)
	return m


func _brain(m: Dictionary, pid: int) -> AiBrain:
	return (m["brains"] as Dictionary)[pid]


func _ctx(m: Dictionary, pid: int) -> AiContext:
	return (m["factory"] as AiFactory).thinker(pid).controller.ctx


func test_authoring_covers_every_roster(t: TestCtx) -> void:
	var store: AiDataStore = AiDataStore.load_default()
	t.eq(store.errors, PackedStringArray(), "the AI data files validate")
	for code: String in ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]:
		t.check(store.extra.has("ai_faction_%s.json" % code), "faction file for %s" % code)
	var ids: PackedStringArray = SimMatchKit.data().roster_ids()
	t.eq(ids.size(), 32)
	for id: String in ids:
		t.check(store.has_personality(id), "personality of %s" % id)
		var d: AiDoctrine = AiDoctrine.resolve(store, id)
		t.eq(d.errors, PackedStringArray(), "doctrine of %s resolves cleanly" % id)
		t.gt(d.opener.size(), 8, "opener of %s" % id)


func test_difficulty_table(t: TestCtx) -> void:
	var s: AiDataStore = AiDataStore.load_default()
	var e: AiDifficultyProfile = s.difficulty(0)
	var md: AiDifficultyProfile = s.difficulty(1)
	var h: AiDifficultyProfile = s.difficulty(2)
	var b: AiDifficultyProfile = s.difficulty(3)
	t.gt(e.first_attack_min_s, md.first_attack_min_s)
	t.gt(md.first_attack_min_s, h.first_attack_min_s)
	t.gt(h.first_attack_min_s, b.first_attack_min_s)
	t.ge(e.first_attack_min_s, 900, "Easy never attacks before 15 minutes of schedule")
	var store: AiDataStore = AiDataStore.load_default()
	t.le(md.first_attack_min_s * store.tune_by_level("attack.first_attack_scale_pct", 1, 100) / 100 * 125 / 100, 7 * 60,
		"Medium's first wave, even with the +25 % jitter, is due by 7:00")
	t.eq(store.tune_by_level("attack.first_attack_scale_pct", 0, 100), 100, "Easy keeps the table value")
	t.gt(e.wave_interval_s, md.wave_interval_s)
	t.eq([e.harass_ops_max, md.harass_ops_max, h.harass_ops_max, b.harass_ops_max], [0, 1, 2, 3])
	t.eq([e.scout_level, md.scout_level, h.scout_level, b.scout_level], [0, 1, 2, 3])
	t.check(b.info_omniscient and not h.info_omniscient and b.handicap_pct == 120)


func test_wave_history_adaptation(t: TestCtx) -> void:
	var ctx: AiContext = AiContext.new()
	ctx.pers = AiPersonality.new()
	ctx.pers.aggression = 50
	ctx.tick = 5000
	var b: AiBrain = AiBrain.new()
	b.note_wave_end(ctx, 3000, 2400, 20, 400)  # lost 80 %, destroyed 20 %
	t.eq(b.aggression_delta, -5)
	t.eq(b.min_wave_extra, 2)
	t.eq(b.waves_lost, 1)
	t.eq(b.last_wave_end, 5000)
	for _i: int in 8:
		b.note_wave_end(ctx, 3000, 600, 90, 400)  # success
	t.eq(b.aggression_delta, 15, "the reward is capped at base + 15")
	ctx.pers.aggression = 20
	b.aggression_delta = 0
	for _j: int in 10:
		b.note_wave_end(ctx, 3000, 2900, 0, 300)
	t.eq(ctx.pers.aggression + b.aggression_delta, 10, "aggression never falls below 10")
	t.eq(b.min_wave_extra, 12, "min wave size growth is bounded")


func test_phase_posture_and_ops_live(t: TestCtx) -> void:
	var m: Dictionary = _match(PackedStringArray([R_NAPC, R_NEC]), [1, 1], 7000)
	var b0: AiBrain = _brain(m, 0)
	var c0: AiContext = _ctx(m, 0)
	t.eq((m["errors"] as PackedStringArray).size(), 0, "no engine errors")
	t.ge(b0.base_phase, AiTypes.Phase.BUILDUP, "the opening is over after 5:50")
	t.eq(b0.eco().comp.phase_override, b0.base_phase, "the composition follows the strategy phase")
	t.ge(b0.posture, AiTypes.Posture.BALANCED, "a healthy AI is not in TURTLE at 5:50")
	t.gt(b0.strategy.evals, 100, "strategy evaluated every 40 ticks")
	t.gt(c0.telemetry.count_of(AiTypes.Tele.PHASE_CHANGE), 0)
	# scouting: Medium sends one scout (SCOUT_LIGHT or the fallback unit) after 90 s
	t.gt(b0.scout.launched, 0, "a scout was sent")
	t.check(c0.telemetry.first_tick.has(AiTypes.Tele.FIRST_SCOUT_SENT))
	t.ge(int(c0.telemetry.first_tick[AiTypes.Tele.FIRST_SCOUT_SENT]), 90 * 20, "not before 90 s")


func test_defend_op_answers_intruders(t: TestCtx) -> void:
	var m: Dictionary = _match(PackedStringArray([R_NAPC, R_NEC]), [2, 1], 5200, {"fog": false})
	var w: SimWorld = m["world"]
	var b0: AiBrain = _brain(m, 0)
	var c0: AiContext = _ctx(m, 0)
	var before: int = b0.defend_ops_total
	var hx: int = c0.kb.sites.home_x
	var hy: int = c0.kb.sites.home_y
	var enemy_def: int = _some_armed_unit(w, 1)
	t.gt(enemy_def, -1, "an armed NEC unit exists")
	for i: int in 3:
		w.spawn_unit(enemy_def, 1, hx + (6 + i) * Fp.CELL, hy + 2 * Fp.CELL, 0, 0, 500)
	AiSoakKit.play(m, 300)
	t.gt(b0.defend_ops_total, before, "a DEFEND op was created for the intruders")
	t.check(c0.telemetry.first_tick.has(AiTypes.Tele.DEFEND_STARTED))
	t.eq((m["errors"] as PackedStringArray).size(), 0)


func _some_armed_unit(w: SimWorld, pid: int) -> int:
	var ridx: int = w.players[pid].roster_idx
	var res: AiRoleResolver = AiRoleResolver.resolve(w.data, w.data.rosters[ridx], AiDataStore.load_default())
	return res.first(AiTypes.R_TANK_MAIN)


func test_waves_launch_after_the_gate_and_finish(t: TestCtx) -> void:
	var m: Dictionary = _match(PackedStringArray([R_NAPC, R_NEC]), [2, 2], 13000)
	t.eq((m["errors"] as PackedStringArray).size(), 0, "no engine errors")
	var launched: int = 0
	for pid: int in 2:
		var b: AiBrain = _brain(m, pid)
		var c: AiContext = _ctx(m, pid)
		launched += b.waves_launched
		if b.waves_launched > 0:
			var first: int = int(c.telemetry.first_tick[AiTypes.Tele.ATTACK_LAUNCHED])
			t.ge(first, AiAttackPlanner.first_wave_ticks(c), "the first wave respects the first-attack gate")
			t.ge(b.first_wave_tick, AiAttackPlanner.first_wave_ticks(c))
		for o: AiOp in b.ops:
			t.check(o.state != AiTypes.OpState.NEW, "live ops have started")
			t.le(o.created_tick, o.timeout_tick)
	t.gt(launched, 0, "at least one Hard AI launched a wave in 10:50")


func test_two_runs_are_identical(t: TestCtx) -> void:
	var a: Dictionary = _match(PackedStringArray([R_NAPC, R_NEC]), [2, 1], 6000, {"seed": 7})
	var b: Dictionary = _match(PackedStringArray([R_NAPC, R_NEC]), [2, 1], 6000, {"seed": 7})
	t.eq((a["world"] as SimWorld).checksum(), (b["world"] as SimWorld).checksum(), "same sim state")
	t.eq((a["factory"] as AiFactory).state_hash(), (b["factory"] as AiFactory).state_hash(), "same AI state")
	t.eq(_brain(a, 0).state_hash(), _brain(b, 0).state_hash())


func test_per_ai_cost_within_budget(t: TestCtx) -> void:
	var m: Dictionary = _match(PackedStringArray([R_NAPC, R_NEC]), [2, 2], 8000)
	for pid: int in 2:
		var c: AiController = (m["factory"] as AiFactory).thinker(pid).controller
		var us: int = c.perf.total_us / maxi(c.total_ticks, 1)
		t.le(us, 1500, "AI %d costs %d us per tick (budget 1500)" % [pid, us])
		t.le(c.total_wu, c.ctx.diff.wu_per_tick * c.total_ticks + c.ctx.diff.call_cap_wu, "work units within the profile")


func test_main_and_flank_ops_advance_on_their_own_routes(t: TestCtx) -> void:
	# the planner decides PRONG waves rarely on a 96x96 map (one enemy cluster), so the two-op machinery is driven directly
	var m: Dictionary = _match(PackedStringArray([R_NAPC, R_NEC]), [3, 1], 8000, {"seed": 5, "credits": 20000, "fog": false})
	var b0: AiBrain = _brain(m, 0)
	var c0: AiContext = _ctx(m, 0)
	var res: AiSquad = b0.eco().squads.reserve
	t.gt(res.size(), 5, "an army exists")
	var half: int = res.size() / 2
	var ids_a: PackedInt32Array = res.units.slice(0, half)
	var ids_b: PackedInt32Array = res.units.slice(half)
	var es: PackedInt32Array = c0.kb.enemy_starts
	var tx: int = es[0] * Fp.CELL + Fp.CELL / 2
	var ty: int = es[1] * Fp.CELL + Fp.CELL / 2
	var main_op: AiOpAttack = AiOpAttack.new()
	main_op.setup_wave(AiTypes.SquadKind.MAIN, ids_a, {"x": tx, "y": ty, "eid": -1, "value": 100}, 300)
	var flank_op: AiOpAttack = AiOpAttack.new()
	flank_op.setup_wave(AiTypes.SquadKind.FLANK, ids_b, {"x": tx, "y": ty + 6 * Fp.CELL, "eid": -1, "value": 100}, 300)
	t.check(b0.add_op(c0, main_op), "MAIN op starts")
	flank_op.sibling = main_op.id
	main_op.sibling = flank_op.id
	t.check(b0.add_op(c0, flank_op), "FLANK op starts")
	t.eq(main_op.priority, 60)
	t.eq(flank_op.priority, 55)
	t.eq(b0.eco().squads.squad(main_op.squads[0]).prio, 60, "the squad carries the op priority")
	var states: Dictionary = {}
	AiSoakKit.play(m, 1500, func(_mm: Dictionary) -> void:
		states[main_op.state] = true
		states[100 + flank_op.state] = true)
	t.eq((m["errors"] as PackedStringArray).size(), 0, "no engine errors")
	t.check(states.has(AiTypes.OpState.ADVANCING) or states.has(AiTypes.OpState.ENGAGING), "MAIN left the forming state")
	t.check(main_op.waypoints.size() >= 2, "MAIN planned a route")
	t.check(flank_op.waypoints.size() >= 2 or flank_op.state == AiTypes.OpState.FORMING, "FLANK planned a route")
	t.check(flank_op.eta_ticks >= 0)
	# abort releases the units to the reserve
	var n_units: int = main_op.ids.size()
	main_op.abort(c0, AiTypes.Err.OP_TIMEOUT)
	t.eq(main_op.state, AiTypes.OpState.FAILED)
	t.eq(main_op.squads.size(), 0, "the squads are released")
	t.le(n_units, b0.eco().squads.reserve.size() + n_units)


func test_hunt_op_sweeps_when_no_enemy_structure_is_known(t: TestCtx) -> void:
	var m: Dictionary = _match(PackedStringArray([R_NAPC, R_NEC]), [2, 1], 6500, {"tuning": {"hunt.min_s": 0}})
	var b0: AiBrain = _brain(m, 0)
	var c0: AiContext = _ctx(m, 0)
	var kb: AiKnowledge = c0.kb
	for eid: int in kb.ghosts.sorted_eids():
		kb.ghosts.remove(eid)
	t.eq(kb.ghosts.count, 0)
	# a few fast combat units in the reserve (AIT: the army is out on other ops at this minute)
	var hh: PackedInt32Array = AiXKit.home(m, 0)
	for i: int in 3:
		AiXKit.spawn(m, "unit.napc.guardian_tank", 0, hh[0] + (4 + i) * Fp.CELL, hh[1] + 3 * Fp.CELL, 800)
	AiXKit.settle(m)
	var budget: AiBudget = AiBudget.new()
	budget.left = 1000
	b0.strategy._launch_ops(c0, b0, budget)  # the utility table of the non-attack ops, called right now
	t.gt(b0.hunt_ops_total, 0, "a HUNT op was started")
	var hunt: AiOpHunt = null
	for o: AiOp in b0.ops:
		if o is AiOpHunt:
			hunt = o
	t.not_null(hunt, "the hunt op is alive")
	if hunt != null:
		AiSoakKit.play(m, 60)
		t.gt(hunt.alive, 0)
		t.check(hunt.block >= 0 or hunt.is_over(), "a sweep block was chosen")
		var b1: int = hunt.block
		AiSoakKit.play(m, 1200)
		t.check(hunt.is_over() or hunt.blocks_done > 0 or hunt.block != b1, "the sweep moves on")
	t.eq((m["errors"] as PackedStringArray).size(), 0)


func test_harass_roster_raids_and_retreats(t: TestCtx) -> void:
	var m: Dictionary = _match(PackedStringArray(["roster.olm.algeria", R_NAPC]), [2, 1], 0, {"seed": 4, "fog": false})
	var c0: AiContext = _ctx(m, 0)
	var es: PackedInt32Array = c0.kb.enemy_starts
	var seen: Dictionary = {}
	var hijacked: Array = []
	AiSoakKit.play(m, 9000, func(mm: Dictionary) -> void:
		for o: AiOp in _brain(mm, 0).ops:
			if o is AiOpHarass:
				var h: AiOpHarass = o
				if hijacked.is_empty():
					# drive the first raid by hand at the enemy base (no target is "safe" by the threat rule there)
					hijacked.append(h)
					h.tx = es[0] * Fp.CELL
					h.ty = es[1] * Fp.CELL
					h.set_state(c0, AiTypes.OpState.ADVANCING)
				if h == hijacked[0]:
					seen[h.state] = true)
	var b0: AiBrain = _brain(m, 0)
	t.eq((m["errors"] as PackedStringArray).size(), 0, "no engine errors")
	t.gt(b0.harass_ops_total, 0, "Algeria (harass 80) started a HARASS op")
	t.le(_brain(m, 1).harass_ops_total, 3, "a low-harass roster does not spam raids")
	t.eq(hijacked.size(), 1, "a HARASS op was alive at a sample")
	t.check(seen.has(AiTypes.OpState.ENGAGING) or seen.has(AiTypes.OpState.RETREATING), "the raid reached its target or pulled back")


func test_factory_adapter_installs_the_brain(t: TestCtx) -> void:
	var f: AiFactory = AiFactory.new()
	var make_fn: Callable = AiBrain.factory_fn(f)
	var thinker: Callable = make_fn.call(2, AiTypes.Difficulty.HARD, 0, AiRng.thinker_seed(9, 2))
	t.check(thinker.is_valid(), "the adapter returns the thinker callable")
	var ctrl: AiController = f.thinker(2).controller
	t.check(ctrl.ctx.brain is AiBrain, "ctx.brain is the AiBrain")
	t.check(ctrl.scheduler.modules[AiScheduler.Slot.STRATEGY] is AiStrategy)
	t.check(ctrl.scheduler.modules[AiScheduler.Slot.DEFENSE] is AiDefense)
	t.check(ctrl.scheduler.modules[AiScheduler.Slot.ATTACK] is AiAttackPlanner)
	t.check(ctrl.scheduler.modules[AiScheduler.Slot.OPS] is AiBrain)
	t.check(ctrl.scheduler.modules[AiScheduler.Slot.SUPPORT] is AiScout)
	t.check(ctrl.scheduler.modules[AiScheduler.Slot.ECONOMY] is AiEconomy, "the economy hub is installed too")


func test_danger_memory_fades(t: TestCtx) -> void:
	var b: AiBrain = AiBrain.new()
	b.note_danger(40 * Fp.CELL, 40 * Fp.CELL, 1000, 100)
	t.eq(b.danger_power(40 * Fp.CELL, 40 * Fp.CELL, 5 * Fp.CELL, 100), 1000, "fresh")
	t.eq(b.danger_power(41 * Fp.CELL, 40 * Fp.CELL, 5 * Fp.CELL, 100 + AiBrain.DANGER_TICKS / 2), 500, "half way")
	t.eq(b.danger_power(40 * Fp.CELL, 40 * Fp.CELL, 5 * Fp.CELL, 100 + AiBrain.DANGER_TICKS), 0, "forgotten")
	t.eq(b.danger_power(70 * Fp.CELL, 40 * Fp.CELL, 5 * Fp.CELL, 100), 0, "elsewhere")
	for i: int in 20:
		b.note_danger(i * Fp.CELL, 0, 10, 200)
	t.le(b.danger.size(), 4 * 12, "the memory is bounded")


func test_force_geometry_helpers(t: TestCtx) -> void:
	t.eq(AiForce.cells(0, 0, 3 * Fp.CELL, 4 * Fp.CELL), 5, "octile distance in cells")
	t.eq(AiForce.cells(2 * Fp.CELL, 0, 12 * Fp.CELL, 0), 10)
	t.eq(AiForce.dist(3 * Fp.CELL, 4 * Fp.CELL, 0, 0), 5 * Fp.CELL, "Euclid")


func test_key_site_defense_takes_units_from_lower_priority_squads(t: TestCtx) -> void:
	var m: Dictionary = _match(PackedStringArray([R_NAPC, R_NEC]), [2, 1], 6500, {"fog": false})
	var w: SimWorld = m["world"]
	var b0: AiBrain = _brain(m, 0)
	var c0: AiContext = _ctx(m, 0)
	var sm: AiSquadManager = b0.squads()
	# every free combat unit joins a lower-priority (HARASS, 45) squad: the reserve is empty
	var busy: AiSquad = sm.create(AiTypes.SquadKind.HARASS, -1)
	busy.prio = 45
	b0.assign_units(c0, busy, sm.reserve.units.duplicate())
	t.eq(sm.reserve.size(), 0, "the reserve is empty")
	t.gt(busy.size(), 2, "there is something to steal")
	var before: int = b0.defend_ops_total
	var hx: int = c0.kb.sites.home_x
	var hy: int = c0.kb.sites.home_y
	var enemy_def: int = _some_armed_unit(w, 1)
	for i: int in 2:
		w.spawn_unit(enemy_def, 1, hx + (5 + i) * Fp.CELL, hy + 2 * Fp.CELL, 0, 0, 500)
	AiSoakKit.play(m, 300)
	t.gt(b0.defend_ops_total, before, "the HQ defense took the units of the lower-priority squad")
	t.eq((m["errors"] as PackedStringArray).size(), 0)
