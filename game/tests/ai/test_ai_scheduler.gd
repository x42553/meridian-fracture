extends RefCounted
## AiScheduler: periods per difficulty, due arithmetic, count-based slicing, starvation guard (ai.md 5.2 / 10.1).


## Synthetic module: burns everything its slot budget allows (a greedy worst case).
class Greedy extends RefCounted:
	var calls: int = 0
	var spent: int = 0

	func step(_ctx: Object, b: AiBudget) -> void:
		calls += 1
		var before: int = b.used
		while b.spend(1):
			pass
		spent += b.used - before


func _diff(level: int) -> AiDifficultyProfile:
	return AiDataStore.load_default().difficulty(level)


func test_periods_per_difficulty(t: TestCtx) -> void:
	var expect: Dictionary = {0: [30, 15, 0], 1: [20, 10, 10], 2: [10, 5, 4], 3: [6, 5, 2]}
	for lv: int in expect:
		var d: AiDifficultyProfile = _diff(lv)
		var e: Array = expect[lv]
		t.eq(AiScheduler.slot_period(AiScheduler.Slot.ECONOMY, d), e[0], "economy period level %d" % lv)
		t.eq(AiScheduler.slot_period(AiScheduler.Slot.PRODUCTION, d), maxi(5, e[0] / 2), "production period level %d" % lv)
		t.eq(AiScheduler.slot_period(AiScheduler.Slot.MICRO, d), e[2], "micro period level %d" % lv)
		t.eq(AiScheduler.slot_period(AiScheduler.Slot.ATTACK, d), e[0] * 4)
		t.eq(AiScheduler.slot_period(AiScheduler.Slot.INGEST, d), 1)


func test_due_arithmetic(t: TestCtx) -> void:
	# period 10, phase 4: multiples at 4, 14, 24 ...
	t.check(AiScheduler.is_due(10, 4, 0, 4), "4 in (0, 4]")
	t.check_false(AiScheduler.is_due(10, 4, 4, 13), "nothing in (4, 13]")
	t.check(AiScheduler.is_due(10, 4, 4, 14))
	t.check(AiScheduler.is_due(10, 4, 0, 50), "a long gap is due (ONCE)")
	t.check_false(AiScheduler.is_due(0, 0, 0, 100), "period 0 = disabled")
	t.check(AiScheduler.is_due(1, 0, 5, 6))


func test_runs_once_per_think_with_scaled_quota(t: TestCtx) -> void:
	var s: AiScheduler = AiScheduler.new(_diff(AiTypes.Difficulty.HARD))
	var m: Greedy = Greedy.new()
	s.register(AiScheduler.Slot.INGEST, m)
	s.start_at(0)
	var b: AiBudget = AiBudget.new()
	b.reset(100000, 100000)
	s.run(1, 1, null, b)
	t.eq(m.calls, 1)
	t.eq(s.last_wu[AiScheduler.Slot.INGEST], 120, "quota x 1 at dt 1")
	b.reset(100000, 100000)
	s.run(51, 50, null, b)
	t.eq(m.calls, 2, "one run per think whatever dt")
	t.eq(s.last_wu[AiScheduler.Slot.INGEST], 480, "quota x min(4, ceil(50/1))")


func test_starvation_guard(t: TestCtx) -> void:
	var s: AiScheduler = AiScheduler.new(_diff(AiTypes.Difficulty.HARD))
	var m: Greedy = Greedy.new()
	s.register(AiScheduler.Slot.TECH, m)
	s.start_at(0)
	var b: AiBudget = AiBudget.new()
	var tick: int = 0
	var ran_after_skips: bool = false
	for _i: int in 12:
		tick += 40
		b.reset(0, 100)  # no budget at all
		s.run(tick, 40, null, b)
		if m.calls > 0:
			ran_after_skips = true
			break
	t.check(ran_after_skips, "a slot skipped SKIP_RESERVE times runs on its reserved quota")
	t.eq(s.skips[AiScheduler.Slot.TECH], 0)


func test_average_budget_holds_at_every_dt(t: TestCtx) -> void:
	for lv: int in 4:
		var d: AiDifficultyProfile = _diff(lv)
		for dt: int in [1, 2, 4, 10, 50]:
			var s: AiScheduler = AiScheduler.new(d)
			var mods: Array = []
			for slot: int in AiScheduler.SLOT_COUNT:
				var g: Greedy = Greedy.new()
				mods.append(g)
				s.register(slot, g)
			s.start_at(0)
			var b: AiBudget = AiBudget.new()
			var total: int = 0
			var worst: int = 0
			var tick: int = 0
			while tick < 10000:
				tick += dt
				b.reset(mini(d.wu_per_tick * dt, d.call_cap_wu), d.call_cap_wu)
				s.run(tick, dt, null, b)
				total += b.used
				worst = maxi(worst, b.used)
			t.le(total, d.wu_per_tick * tick + d.call_cap_wu, "level %d dt %d: mean wu/tick within the profile" % [lv, dt])
			t.le(worst, d.call_cap_wu + 400, "level %d dt %d: a think stays near the call cap (overshoot becomes debt)" % [lv, dt])
