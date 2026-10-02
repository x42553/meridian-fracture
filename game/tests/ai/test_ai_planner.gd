extends RefCounted
## AiBuildPlanner (ai.md 5.5.2): script pointer semantics (non-parallel steps in order, parallel steps in the background), the
## condition vocabulary, opt-step drops, target table, BUILD_START / BUILD_PLACE flow and the power gate of AiEconomy.


func _match(extra: Dictionary = {}) -> Dictionary:
	var o: Dictionary = {"seed": 1, "waves": false, "rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), "level": AiTypes.Difficulty.HARD}
	o.merge(extra, true)
	return AiEconKit.make(o)


func _step(pl: AiBuildPlanner, id: String) -> AiBuildPlanner.Step:
	for s: AiBuildPlanner.Step in pl.steps:
		if s.id == id:
			return s
	return null


func test_pointer_semantics(t: TestCtx) -> void:
	var m: Dictionary = _match()
	AiEconKit.run(m, 100)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var pl: AiBuildPlanner = eco.planner
	t.eq(_step(pl, "gen1").state, AiBuildPlanner.ST_ACTIVE, "the first spine step runs")
	t.eq(_step(pl, "ref1").state, AiBuildPlanner.ST_WAIT, "later non-parallel steps wait")
	t.eq(_step(pl, "inf1").state, AiBuildPlanner.ST_WAIT, "a parallel step waits for its condition")
	t.check_false(pl.spine_done)
	# the spine finishes in order: generator, refinery, barracks, factory, refinery, radar
	var order: PackedStringArray = PackedStringArray()
	var ticks: int = 0
	while ticks < 6500 and not pl.spine_done:
		AiEconKit.run(m, 50)
		ticks += 50
		for id: String in ["gen1", "ref1", "rax1", "fac1", "ref2", "rad1"]:
			if _step(pl, id).state == AiBuildPlanner.ST_DONE and not order.has(id):
				order.append(id)
	t.eq(order, PackedStringArray(["gen1", "ref1", "rax1", "fac1", "ref2", "rad1"]), "strict order")
	t.check(pl.spine_done, "spine done at tick %d" % (ticks + 100))
	t.le(ticks, 5600, "the spine takes < 280 s (5 structures ~ 3100 ticks of build time + latencies)")
	t.eq(_step(pl, "inf1").state, AiBuildPlanner.ST_DONE, "parallel step completed")


func test_condition_vocabulary(t: TestCtx) -> void:
	var m: Dictionary = _match()
	AiEconKit.run(m, 3000)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var pl: AiBuildPlanner = AiEconKit.eco_of(m, 0).planner
	var cases: Array = [
		[{"t_ge_s": 100}, true], [{"t_ge_s": 500}, false], [{"t_lt_s": 500}, true],
		[{"have": {"struct": "barracks", "n": 1}}, true], [{"have": {"struct": "radar", "n": 1}}, false], [{"have_lt": {"struct": "radar", "n": 1}}, true],
		[{"have": {"role": "INFANTRY_BASIC", "n": 1}}, true], [{"tier_ge": 1}, true], [{"tier_ge": 2}, false],
		[{"credits_ge": 0}, true], [{"credits_lt": 0}, false], [{"all": [{"t_ge_s": 1}, {"tier_ge": 1}]}, true],
		[{"any": [{"tier_ge": 3}, {"t_ge_s": 1}]}, true], [{"not": {"tier_ge": 3}}, true], [{"roster_has_role": "FIGHTER"}, true],
		[{"flag": "PRESERVE_VEHICLES"}, true], [{"flag": "SENSOR_MAST"}, false], [{"phase_ge": 3}, false], [{"enemy_seen": "air"}, false],
		[{"dock_placeable": false}, true], [{"map_trait": {"name": "open", "ge_pct": 100}}, true], [{"map_trait": {"name": "urban", "ge_pct": 10}}, false],
		[{"researched": "research.napc.adaptive_plating"}, false], [null, true], [true, true], [{}, true],
	]
	for c: Variant in cases:
		var pair: Array = c
		t.eq(pl.eval_cond(ctx, pair[0]), bool(pair[1]), "cond %s" % JSON.stringify(pair[0]))
	# an unknown key counts as true and is only warned about once
	var warned: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, _tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			warned.append(msg)
	t.check(pl.eval_cond(ctx, {"no_such_key": 1}))
	t.check(pl.eval_cond(ctx, {"no_such_key": 2}))
	Log.sink = old_sink
	t.eq(warned.size(), 1, "one warning for an unknown key")


func test_optional_steps_are_dropped_reproducibly(t: TestCtx) -> void:
	# Easy keeps only 50 % of the opt steps; the draw is made once per step at init from the seeded rng
	var states: Array = []
	for i: int in 3:
		var m: Dictionary = _match({"level": AiTypes.Difficulty.EASY, "ai_seed": 41})
		AiEconKit.run(m, 30)
		states.append(_step(AiEconKit.eco_of(m, 0).planner, "exp1").state)
	t.eq(states[0], states[1], "same seed, same draw")
	t.eq(states[1], states[2])
	var hard: Dictionary = _match({"level": AiTypes.Difficulty.HARD})
	AiEconKit.run(hard, 30)
	t.eq(_step(AiEconKit.eco_of(hard, 0).planner, "exp1").state, AiBuildPlanner.ST_WAIT, "Hard keeps every optional step (opt_step_keep_pct 100)")


func test_targets_become_wants_when_due(t: TestCtx) -> void:
	var m: Dictionary = _match({"credits": 30000})
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	AiEconKit.run(m, 7400)
	# t_rax2 is due at 300 s x tech_delay: a second Barracks exists or is wanted
	var rax: int = AiEconKit.ctx_of(m, 0).res.structure_of_kind(AiTypes.StructKind.BARRACKS)
	t.ge(eco.struct_own[rax] + eco.struct_q[rax], 2, "the target table added the second Barracks")
	t.eq(eco.planner.stalls, 0, "no step timed out")
	t.gt(eco.planner.placed, 5, "structures were placed through BUILD_PLACE (%d)" % eco.planner.placed)
	t.le(eco.planner.place_fails, 3, "few placements were refused (%d)" % eco.planner.place_fails)


func test_power_gate_inserts_generators(t: TestCtx) -> void:
	var m: Dictionary = _match({"credits": 30000})
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	AiEconKit.run(m, 50)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var gen: int = ctx.res.structure_of_kind(AiTypes.StructKind.GENERATOR)
	var worst: int = 1 << 20
	for k: int in 80:
		AiEconKit.run(m, 100)
		worst = mini(worst, ctx.view.power_supply() - ctx.view.power_demand())
	t.ge(worst, 0, "the power margin never goes negative (min %d)" % worst)
	t.ge(eco.struct_own[gen], 2, "a second Generator came before the load exceeded 150")
