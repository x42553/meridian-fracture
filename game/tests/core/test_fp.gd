extends RefCounted
## Fp: sim_core 10.1 cases. The three oracle digests are pinned to tools/py/gen_fp_tables.py --verify, which derives
## them independently in Python (Fraction / math.isqrt / a re-implementation of the trig algorithm).

const ORACLE_MULDIV: int = 1324223992
const ORACLE_ISQRT: int = 2674672166
const ORACLE_TRIG: int = 1666396940


func _push64(buf: PackedInt32Array, v: int) -> void:
	buf.append(v & 0xFFFFFFFF)
	buf.append((v >> 32) & 0xFFFFFFFF)


func test_self_test_and_constants(t: TestCtx) -> void:
	t.eq(Fp.self_test(), PackedStringArray(), "self_test() == []")
	t.eq(Fp.TURN, 4096, "TURN")
	t.eq(Fp.CELL, SimConfig.CELL, "SimConfig.CELL == Fp.CELL")
	t.eq(Fp.CELL_SHIFT, SimConfig.CELL_SHIFT, "CELL_SHIFT")
	t.eq(1 << Fp.CELL_SHIFT, Fp.CELL, "CELL == 1 << CELL_SHIFT")


func test_table_digests(t: TestCtx) -> void:
	t.eq(Checksum.digest32(FpTables.SIN_Q16), 2046802713, "sin table digest")
	t.eq(Checksum.digest32(FpTables.ATAN_Q8), 1306073121, "atan table digest")
	t.eq(Fp.TABLE_DIGEST_SIN, 2046802713, "TABLE_DIGEST_SIN")
	t.eq(Fp.TABLE_DIGEST_ATAN, 1306073121, "TABLE_DIGEST_ATAN")
	t.eq(FpTables.SIN_Q16.size(), 4096, "sin size")
	t.eq(FpTables.ATAN_Q8.size(), 1025, "atan size")
	t.eq(FpTables.ATAN_Q8[1], 163, "ATAN_Q8[1]")
	t.eq(FpTables.ATAN_Q8[256], 40884, "ATAN_Q8[256]")
	t.eq(FpTables.ATAN_Q8[512], 77376, "ATAN_Q8[512]")
	t.eq(FpTables.ATAN_Q8[1023], 130990, "ATAN_Q8[1023]")
	t.eq(FpTables.ATAN_Q8[1024], 131072, "ATAN_Q8[1024]")


func test_sin_cos(t: TestCtx) -> void:
	var samples: Array = [[0, 0], [1, 101], [256, 25080], [512, 46341], [1024, 65536], [2048, 0], [3072, -65536], [-1, -101]]
	for s: Array in samples:
		t.eq(Fp.sin(s[0] as int), s[1] as int, "sin(%d)" % (s[0] as int))
	t.eq(Fp.cos(0), 65536, "cos(0)")
	t.eq(Fp.cos(2048), -65536, "cos(2048)")
	t.eq(Fp.sin(4096 + 5), Fp.sin(5), "sin wraps")
	var sym: int = 0
	var norm_worst: int = 0
	for a: int in 4096:
		var sa: int = FpTables.SIN_Q16[a]
		if sa != FpTables.SIN_Q16[(2048 - a) & 4095] and a != 0:
			sym += 1
		if sa != -FpTables.SIN_Q16[(a + 2048) & 4095]:
			sym += 1
		var n: int = Fp.sin(a) * Fp.sin(a) + Fp.cos(a) * Fp.cos(a)
		norm_worst = maxi(norm_worst, absi(n - 65536 * 65536))
	t.eq(sym, 0, "symmetry violations")
	t.lt(norm_worst, 2 * 65536, "sin^2 + cos^2 within 2*65536 of 65536^2")


func test_atan2(t: TestCtx) -> void:
	var samples: Array = [[0, 1, 0], [1, 0, 1024], [0, -1, 2048], [-1, 0, 3072], [1, 1, 512], [-1, 1, 3584], [1, -1, 1536], [-1, -1, 2560], [1000, 1, 1023], [0, 0, 0]]
	for s: Array in samples:
		t.eq(Fp.atan2(s[0] as int, s[1] as int), s[2] as int, "atan2(%d,%d)" % [s[0] as int, s[1] as int])
	var rng: SimRng = SimRng.new(77)
	var worst: float = 0.0
	for _i: int in 20000:
		var dx: int = rng.range_i(-262143, 262143)
		var dy: int = rng.range_i(-262143, 262143)
		if dx == 0 and dy == 0:
			continue
		var exact: float = fposmod(atan2(float(dy), float(dx)) * 4096.0 / TAU, 4096.0)
		var d: float = absf(float(Fp.atan2(dy, dx)) - exact)
		worst = maxf(worst, minf(d, 4096.0 - d))
	t.check(worst <= 1.0, "atan2 within 1 unit of float atan2 (worst %f)" % worst)


func test_isqrt(t: TestCtx) -> void:
	for k: int in [0, 1, 2, 3, 46340, 46341, 65535, 65536, 1000003, 2147483646, 2147483647]:
		var sq: int = k * k
		if k > 0:
			t.eq(Fp.isqrt(sq - 1), k - 1, "isqrt(%d^2-1)" % k)
		t.eq(Fp.isqrt(sq), k, "isqrt(%d^2)" % k)
		t.eq(Fp.isqrt(sq + 1), k if k > 0 else 1, "isqrt(%d^2+1)" % k)
	t.eq(Fp.isqrt(Fp.ISQRT_MAX), 2147483647, "isqrt(2^62-1)")
	t.eq(Fp.isqrt(Fp.ISQRT_MAX + 5), 2147483647, "clamped above")
	t.eq(Fp.isqrt(-5), 0, "isqrt(-5)")
	t.eq(Fp.dist(3000, 4000), 5000, "dist 3-4-5")
	t.eq(Fp.dist(1, 1), 1, "dist(1,1)")
	t.eq(Fp.dist(-5, 12), 13, "dist(-5,12)")
	t.eq(Fp.dist2(-5, 12), 169, "dist2")


func test_isqrt_oracle_digest(t: TestCtx) -> void:
	var rng: SimRng = SimRng.new(2002)
	var out: PackedInt32Array = PackedInt32Array()
	var wrong: int = 0
	for _i: int in 100000:
		var hi: int = rng.next_u32()
		var lo: int = rng.next_u32()
		var sh: int = rng.next_u32() % 63
		var v: int = (((hi & 0x3FFFFFFF) << 32) | lo) >> sh
		var r: int = Fp.isqrt(v)
		if r * r > v or (r + 1) * (r + 1) <= v:
			wrong += 1
		out.append(r & 0xFFFFFFFF)
	t.eq(wrong, 0, "isqrt is the exact floor sqrt")
	t.eq(Checksum.digest32(out), ORACLE_ISQRT, "isqrt oracle digest")


func test_mul_div_table(t: TestCtx) -> void:
	# a*b/c -> trunc, floor, ceil, half_up, half_away
	var rows: Array = [
		[7, 2, [3, 3, 4, 4, 4]], [-7, 2, [-3, -4, -3, -3, -4]], [5, 2, [2, 2, 3, 3, 3]], [-5, 2, [-2, -3, -2, -2, -3]],
		[10, 3, [3, 3, 4, 3, 3]], [-10, 3, [-3, -4, -3, -3, -3]], [11, 3, [3, 3, 4, 4, 4]], [-11, 3, [-3, -4, -3, -4, -4]],
	]
	for row: Array in rows:
		var want: Array = row[2]
		for mode: int in 5:
			t.eq(Fp.mul_div(row[0] as int, 1, row[1] as int, mode), want[mode] as int, "%d/%d mode %d" % [row[0] as int, row[1] as int, mode])
	t.eq(Fp.mul_div(7, 1, -2, Fp.Round.FLOOR), -4, "negative divisor normalised")
	t.eq(Fp.mul_div(6, 7, 3), 14, "exact")


func test_mul_div_oracle_digest(t: TestCtx) -> void:
	var rng: SimRng = SimRng.new(1001)
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in 60000:
		var d0: int = rng.next_u32()
		var d1: int = rng.next_u32()
		var d2: int = rng.next_u32()
		var a: int
		var b: int
		var c: int
		if i % 2 == 0:
			a = d0 % 2001 - 1000
			b = d1 % 2001 - 1000
			c = d2 % 101 - 50
			if c == 0:
				c = 7
		else:
			a = (d0 >> 1) - 1073741824
			b = (d1 >> 1) - 1073741824
			c = (d2 & 0xFFFFF) - 524288
			if c == 0:
				c = 1
		for mode: int in 5:
			_push64(out, Fp.mul_div(a, b, c, mode))
	t.eq(Checksum.digest32(out), ORACLE_MULDIV, "mul_div oracle digest")


func test_division_helpers(t: TestCtx) -> void:
	t.eq(Fp.floor_div(-7, 2), -4, "floor_div(-7,2)")
	t.eq(Fp.floor_mod(-7, 3), 2, "floor_mod(-7,3)")
	t.eq(Fp.ceil_div(-7, 2), -3, "ceil_div(-7,2)")
	t.eq(Fp.floor_div(7, -2), -4, "floor_div(7,-2)")
	t.eq(Fp.ceil_div(7, 2), 4, "ceil_div(7,2)")
	t.eq(Fp.floor_mod(7, -3), -2, "floor_mod(7,-3)")
	t.eq(Fp.floor_div(-8, 2), -4, "exact")
	t.eq(Fp.pct(7, 50), 4, "pct(7,50)")
	t.eq(Fp.pct(-7, 50), -3, "pct(-7,50)")
	t.eq(Fp.apply_pct(1000, -10), 900, "apply_pct")
	t.eq(Fp.cell_of(-1025), -2, "cell_of negative floors")
	t.eq(Fp.cell_center(3), 3584, "cell_center")


func test_apply_layers(t: TestCtx) -> void:
	t.eq(Fp.apply_layers(1000, PackedInt32Array([1000, -1000])), 990, "+10%, -10%")
	t.eq(Fp.apply_layers(1000, PackedInt32Array([1000, 500])), 1155, "+10%, +5%")
	t.eq(Fp.apply_layers(1500, PackedInt32Array([-2000, -2500, -1500])), 765, "three cuts")
	t.eq(Fp.apply_layers(1500, PackedInt32Array([-2000, -2500, -1500]), 60), 900, "60% floor")
	t.eq(Fp.apply_layers(1000, PackedInt32Array([15000]), 0, 200), 2000, "200%% cap")


func test_misc_int_helpers(t: TestCtx) -> void:
	t.eq(Fp.clamp(5, 0, 3), 3, "clamp hi")
	t.eq(Fp.clamp(-5, 0, 3), 0, "clamp lo")
	t.eq(Fp.lerp_i(0, 100, 1, 3), 33, "lerp_i")
	t.eq(Fp.approach(0, 10, 3), 3, "approach up")
	t.eq(Fp.approach(9, 10, 3), 10, "approach clamps")
	t.eq(Fp.approach(0, -10, 3), -3, "approach down")
	t.eq(Fp.mul_q16(-3, 32768), -1, "mul_q16(-3, .5)")
	t.eq(Fp.mul_q16(3, 32768), 2, "mul_q16(3, .5)")
	t.eq(Fp.mul_q16(1000, 46341), 707, "mul_q16(1000, .7071)")


func test_angles(t: TestCtx) -> void:
	t.eq(Fp.angle_diff(10, 4090), -16, "angle_diff(10,4090)")
	t.eq(Fp.angle_diff(4090, 10), 16, "angle_diff(4090,10)")
	t.eq(Fp.angle_diff(0, 2048), -2048, "angle_diff(0,2048)")
	t.eq(Fp.angle_diff(2048, 0), -2048, "angle_diff(2048,0)")
	t.eq(Fp.turn_toward(0, 100, 30), 30, "turn_toward up")
	t.eq(Fp.turn_toward(0, 4000, 30), 4066, "turn_toward wraps")
	t.eq(Fp.turn_toward(4090, 20, 30), 20, "turn_toward arrives")
	t.eq(Fp.turn_toward(10, 15, 30), 15, "turn_toward small")
	t.eq(Fp.angle_norm(-1), 4095, "angle_norm")
	t.eq(Fp.rot_x(1000, 0, 1024), 0, "rot_x quarter turn")
	t.eq(Fp.rot_y(1000, 0, 1024), 1000, "rot_y quarter turn")
	t.eq(Fp.rot_x(0, 1000, 1024), -1000, "rot_x of +y by quarter turn")
	t.eq(Fp.angle_between(0, 0, 0, 5), 1024, "angle_between south")


func test_trig_oracle_digest(t: TestCtx) -> void:
	var rng: SimRng = SimRng.new(3003)
	var out: PackedInt32Array = PackedInt32Array()
	for _i: int in 50000:
		var dx: int = (rng.next_u32() & 0x7FFFF) - 262144
		var dy: int = (rng.next_u32() & 0x7FFFF) - 262144
		var a: int = rng.next_u32() & 4095
		out.append(Fp.atan2(dy, dx))
		out.append(Fp.rot_x(dx, dy, a))
		out.append(Fp.rot_y(dx, dy, a))
	t.eq(Checksum.digest32(out), ORACLE_TRIG, "atan2/rot_x/rot_y oracle digest")


func test_worked_movement_example(t: TestCtx) -> void:
	var x: int = 21504
	var y: int = 22528
	var tx: int = 30720
	var ty: int = 30720
	t.eq(Fp.dist(tx - x, ty - y), 12330, "distance")
	var ang: int = Fp.atan2(ty - y, tx - x)
	t.eq(ang, 474, "facing")
	t.eq(Fp.sin(474), 43562, "sin(474)")
	t.eq(Fp.cos(474), 48962, "cos(474)")
	t.eq(Fp.step_x(474, 300), 224, "step_x")
	t.eq(Fp.step_y(474, 300), 199, "step_y")
	var steps: int = 0
	while Fp.dist2(tx - x, ty - y) > 300 * 300 and steps < 100:
		x += Fp.step_x(ang, 300)
		y += Fp.step_y(ang, 300)
		steps += 1
	t.eq(steps + 1, 42, "arrives on the 42nd step")


func test_converters(t: TestCtx) -> void:
	t.eq(Fp.milli(0.1), 100, "milli(0.1)")
	t.eq(Fp.milli(2.675), 2675, "milli(2.675)")
	t.eq(Fp.cells_to_units(2500), 2560, "cells_to_units")
	t.eq(Fp.seconds_to_ticks(1500), 30, "seconds_to_ticks")
	t.eq(Fp.seconds_to_ticks(1501), 31, "seconds_to_ticks rounds up")
	t.eq(Fp.cps_to_units_per_tick(3000), 154, "cps_to_units_per_tick")
