extends RefCounted
## AiStrength: the Lanchester vectors of ai.md 5.3.4 / 10.1.


func _grp(hp: int, dps: int, cls: int = 2, n: int = 1, rng: int = 0, arty: bool = false) -> AiStrengthGroup:
	var g: AiStrengthGroup = AiStrengthGroup.new()
	g.hp = hp * n
	g.hp_by_class[cls] = hp * n
	g.dps_x100_by_class[cls] = dps * 100 * n
	g.avg_range = rng
	g.count = n
	if arty:
		g.arty_dps_x100 = g.total_dps_x100()
		g.arty_hp = g.hp
	return g


func _mix(a: AiStrengthGroup, b: AiStrengthGroup) -> AiStrengthGroup:
	var g: AiStrengthGroup = AiStrengthGroup.new()
	g.hp = a.hp + b.hp
	g.count = a.count + b.count
	for c: int in AiStrengthGroup.NCLASS:
		g.hp_by_class[c] = a.hp_by_class[c] + b.hp_by_class[c]
		g.dps_x100_by_class[c] = a.dps_x100_by_class[c] + b.dps_x100_by_class[c]
	return g


func test_worked_example(t: TestCtx) -> void:
	var d: AiStrengthGroup = _mix(_grp(900, 50, 2, 6), _grp(1000, 60, 2, 2))
	t.eq(d.hp, 7400)
	t.eq(AiStrength.ratio_q8(_grp(800, 45, 2, 10), d), 296, "10 tanks vs 6 tanks + 2 turrets: hold (< 332)")
	t.eq(AiStrength.ratio_q8(_grp(800, 45, 2, 14), d), 581, "14 tanks: launch")
	t.check_false(AiStrength.meets(296, 130))
	t.check(AiStrength.meets(581, 130))


func test_no_defender_damage(t: TestCtx) -> void:
	var idle: AiStrengthGroup = _grp(500, 0, 2, 3)
	t.eq(AiStrength.ratio_q8(_grp(800, 45, 2, 5), idle), 4096, "defender dps 0 => 16 x 256")
	t.eq(AiStrength.ratio_q8(_grp(800, 45, 2, 5), AiStrengthGroup.new()), 4096, "empty defender")
	t.eq(AiStrength.ratio_q8(AiStrengthGroup.new(), idle), 0, "empty attacker")


func test_range_and_home_advantage(t: TestCtx) -> void:
	var a: AiStrengthGroup = _grp(800, 45, 2, 10, 8 * Fp.CELL)
	var d: AiStrengthGroup = _grp(800, 45, 2, 10, 4 * Fp.CELL)
	var flat: int = AiStrength.ratio_q8(_grp(800, 45, 2, 10), _grp(800, 45, 2, 10))
	t.eq(flat, 256, "mirror match = 1.0")
	t.gt(AiStrength.ratio_q8(a, d), flat, "range advantage helps")
	t.lt(AiStrength.ratio_q8(_grp(800, 45, 2, 10), _grp(800, 45, 2, 10), 10), flat, "defender home advantage")


func test_artillery_screen_penalty(t: TestCtx) -> void:
	var plain: AiStrengthGroup = _grp(800, 45, 2, 10)
	var arty: AiStrengthGroup = _grp(800, 45, 2, 10, 0, true)
	t.eq(arty.arty_dps_x100 * 100 / arty.total_dps_x100(), 100)
	var r_plain: int = AiStrength.ratio_q8(plain, _grp(800, 45, 2, 10))
	var r_arty: int = AiStrength.ratio_q8(arty, _grp(800, 45, 2, 10))
	t.le(absi(r_arty - (r_plain * 205 >> 8)), 2, "artillery without a screen: dps x 205/256 (rounding)")


func test_noise_is_stable_within_an_epoch(t: TestCtx) -> void:
	var n1: int = AiStrength.noise_q8(1000, 7, 10)
	t.eq(AiStrength.noise_q8(1100, 7, 10), n1, "same 200-tick epoch and target => same noise")
	var seen: Dictionary = {}
	for tg: int in 40:
		var v: int = AiStrength.noise_q8(1000, tg, 10)
		t.le(absi(v), 25, "within +- est_noise_pct")
		seen[v] = true
	t.gt(seen.size(), 5, "different targets differ")
	t.eq(AiStrength.noise_q8(5, 1, 0), 0, "no noise at 0 %")
