extends RefCounted
## SimRng vectors of sim_core 10.1 (cross-checked against a Python implementation).


func _first4(seed_value: int) -> PackedInt32Array:
	var r: SimRng = SimRng.new(seed_value)
	var out: PackedInt32Array = PackedInt32Array()
	for _i: int in 4:
		out.append(r.next_u32())
	return out


func test_seed_vectors(t: TestCtx) -> void:
	# PackedInt32Array wraps values >= 2^31, so compare with the masked expected values.
	var cases: Array = [
		[0, [2407135599, 70998536, 3162094942, 2962270859]],
		[1, [3898016280, 503430273, 2109199260, 1781707058]],
		[12345, [1165108165, 1674106077, 2795167292, 40330380]],
		[4294967296, [3443646874, 3280564437, 988752536, 1060094022]],
		[1234567890123456789, [1222558724, 1588512357, 1375524028, 485886740]],
	]
	for c: Array in cases:
		var r: SimRng = SimRng.new(c[0] as int)
		var want: Array = c[1]
		for i: int in 4:
			t.eq(r.next_u32(), want[i] as int, "seed %d draw %d" % [c[0] as int, i])


func test_seed_42_sequence(t: TestCtx) -> void:
	var r: SimRng = SimRng.new(42)
	var a: Array[int] = []
	for _i: int in 8:
		a.append(r.next_int(100))
	t.eq(a, [82, 87, 94, 90, 96, 0, 16, 46] as Array[int], "next_int(100)")
	var b: Array[int] = []
	for _i: int in 8:
		b.append(r.range_i(-5, 5))
	t.eq(b, [0, -4, -2, -3, 1, -3, -3, 0] as Array[int], "range_i(-5,5)")


func test_next_int_bounds(t: TestCtx) -> void:
	var r: SimRng = SimRng.new(7)
	for n: int in [1, 2, 3, 100, 1 << 30]:
		for _i: int in 200:
			var v: int = r.next_int(n)
			if v < 0 or v >= n:
				t.fail("next_int(%d) = %d out of range" % [n, v])
				return
	t.check(true)


func test_uniformity(t: TestCtx) -> void:
	var r: SimRng = SimRng.new(99)
	var buckets: PackedInt32Array = PackedInt32Array()
	buckets.resize(10)
	for _i: int in 1000000:
		buckets[r.next_int(10)] += 1
	var worst: int = 0
	for b: int in buckets:
		worst = maxi(worst, absi(b - 100000))
	t.lt(worst, 2000, "each bucket within 2%% of 100000 (worst deviation %d)" % worst)


func test_state_roundtrip(t: TestCtx) -> void:
	var r: SimRng = SimRng.new(5)
	for _i: int in 10:
		r.next_u32()
	var st: PackedInt32Array = r.get_state()
	var next_a: int = r.next_u32()
	var r2: SimRng = SimRng.new(1234)
	r2.set_state(st)
	t.eq(r2.next_u32(), next_a, "set_state resumes the same sequence")
	var buf: PackedInt32Array = PackedInt32Array()
	r2.hash_into(buf)
	t.eq(buf.size(), 4, "hash_into appends 4 lanes")


func test_reseed_negative(t: TestCtx) -> void:
	var a: PackedInt32Array = _first4(-1)
	var b: PackedInt32Array = _first4(1)
	t.ne(a, b, "seed -1 differs from seed 1")
	var r: SimRng = SimRng.new(-1)
	t.check((r.s0 | r.s1 | r.s2 | r.s3) != 0, "state not all-zero")
	r.reseed(-1)
	t.eq(r.next_u32(), a[0] & 0xFFFFFFFF, "reseed is deterministic")


func test_shuffle_vector(t: TestCtx) -> void:
	var r: SimRng = SimRng.new(3)
	var a: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	r.shuffle(a)
	t.eq(a, [1, 3, 4, 7, 5, 2, 8, 6] as Array, "shuffle of 1..8 with seed 3")


func test_mul32(t: TestCtx) -> void:
	t.eq(SimRng.mul32(0xFFFFFFFF, 0xFFFFFFFF), 1, "(2^32-1)^2 mod 2^32 = 1")
	t.eq(SimRng.mul32(0x12345678, 0x9E3779B1), (0x12345678 * 0x9E3779B1) & 0xFFFFFFFF, "matches int64 product")


func test_chance(t: TestCtx) -> void:
	var r: SimRng = SimRng.new(11)
	var hits: int = 0
	for _i: int in 10000:
		if r.chance_pct(30):
			hits += 1
	t.check(hits > 2700 and hits < 3300, "chance_pct(30) ~ 30%% (%d)" % hits)
	t.check(not SimRng.new(1).chance_bp(0), "chance_bp(0) never")
