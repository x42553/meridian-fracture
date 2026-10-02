extends RefCounted
## Combat meter: thresholds and hysteresis of audio spec 5.7.


func _meter() -> SndCombatMeter:
	var m: SndCombatMeter = SndCombatMeter.new()
	m.configure((SndTestKit.real()["store"] as SndDataStore).music.get("meter", {}))
	return m


func test_thresholds(t: TestCtx) -> void:
	var m: SndCombatMeter = _meter()
	var now: int = 0
	var raw_at_10: float = 0.0
	var raw_at_20: float = 0.0
	var went: int = -1
	var dt: float = 1.0 / 20.0
	for step: int in 20 * 40:
		m.add(2.5 * dt, 0.0, true)  # 2.5 heat per second at zero distance
		m.update(dt)
		now += 50
		var raw: float = 1.0 - exp(-m.heat / m.h_ref)
		if step == 20 * 10 - 1:
			raw_at_10 = raw
		if step == 20 * 20 - 1:
			raw_at_20 = raw
		if went < 0 and m.wants_combat(now):
			went = now
	t.near(raw_at_10, 0.386, 0.01, "raw intensity at 10 s")
	t.near(raw_at_20, 0.439, 0.01, "raw intensity at 20 s")
	t.check(went >= 12000 and went <= 14500, "combat requested between 12 s and 14 s (%d ms)" % went)


func test_calm_after_quiet(t: TestCtx) -> void:
	var m: SndCombatMeter = _meter()
	var now: int = 0
	for i: int in 200:
		m.add(1.0, 0.0, true)
		m.update(0.05)
		now += 50
		m.wants_combat(now)
	t.check(m.wants_combat(now), "in combat after heavy input")
	# quiet: 30 s of nothing; min combat time satisfied, release + hold 18 s
	var back: int = -1
	for i: int in 20 * 60:
		m.update(0.05)
		now += 50
		if back < 0 and not m.wants_combat(now):
			back = now
	t.check(back > 0, "returns to calm")
	t.check(not m.wants_combat(now), "stays calm")


func test_heavy_input_saturates(t: TestCtx) -> void:
	var m: SndCombatMeter = _meter()
	for i: int in 20:
		m.add(20.0 * 0.05, 0.0, true)
		m.update(0.05)
	var raw: float = 1.0 - exp(-m.heat / m.h_ref)
	t.gt(raw, 0.5, "20 heat/s rises fast (raw %.2f after 1 s)" % raw)
	for i: int in 200:
		m.add(20.0 * 0.05, 0.0, true)
		m.update(0.05)
	t.gt(m.intensity, 0.95, "saturates near 1 (%.3f)" % m.intensity)


func test_distance_and_far_heat(t: TestCtx) -> void:
	var m: SndCombatMeter = _meter()
	m.add(10.0, 0.0, true)
	var near_heat: float = m.heat
	m.reset()
	m.add(10.0, 200.0, true)
	t.near(m.heat, 10.0 * m.min_dist_weight, 0.001, "beyond the radius the weight floors at 0.15")
	t.near(m.far_heat, 10.0 * m.far_weight, 0.001, "own action beyond earshot feeds far_heat")
	t.gt(near_heat, m.heat, "near counts more")
	m.reset()
	m.add(10.0, 200.0, false)
	t.eq(m.far_heat, 0.0, "enemy action does not feed far_heat")


func test_urgent_goes_straight_to_combat(t: TestCtx) -> void:
	var m: SndCombatMeter = _meter()
	t.check(not m.wants_combat(1000), "calm")
	m.add_urgent(20.0)
	t.check(m.wants_combat(1010), "urgent alert requests combat at once")
