extends RefCounted
## AiRng: net vectors of ai.md 5.14.3 / 10.1.


func test_mix32_vectors(t: TestCtx) -> void:
	t.eq(AiRng.mix32(1), 0x514E28B7, "mix32(1)")
	t.eq(AiRng.mix32(0xDEADBEEF), 0x0DE5C6A9, "mix32(0xDEADBEEF)")


func test_stream_from_mixed_seed(t: TestCtx) -> void:
	var r: AiRng = AiRng.new()
	r.seed_from(0x514E28B7)
	var got: Array = []
	for _i: int in 6:
		got.append(r.next_u32())
	t.eq(got, [524866043, 2877414208, 2380002740, 2664205378, 3890067424, 1964142960] as Array, "six next_u32")
	var r2: AiRng = AiRng.new()
	r2.seed_from(0x514E28B7)
	var got2: Array = []
	for _i: int in 6:
		got2.append(r2.range_i(-15, 25))
	t.eq(got2, [18, -1, -2, 25, -4, 20] as Array, "six range_i(-15, 25)")


func test_zero_seed_and_thinker_seed(t: TestCtx) -> void:
	var r: AiRng = AiRng.new()
	r.seed_from(0)
	t.eq(r.state(), 0x9E3779B9, "zero seed falls back")
	t.eq(r.next_u32(), 1359758873)
	t.eq(r.next_u32(), 3761132862)
	t.eq(AiRng.thinker_seed(12345, 1), 0x8739D20C, "thinker_seed(12345, 1)")
	var r3: AiRng = AiRng.new()
	r3.seed_from(AiRng.thinker_seed(12345, 1))
	t.eq([r3.next_u32(), r3.next_u32(), r3.next_u32()], [309959344, 81710791, 2110671044] as Array)


func test_hash_str_and_helpers(t: TestCtx) -> void:
	t.eq(AiRng.hash_str(""), 0x811C9DC5)
	t.eq(AiRng.hash_str("a"), 0xE40C292C)
	var r: AiRng = AiRng.new()
	r.seed_from(7)
	t.eq(r.pick_weighted(PackedInt32Array([0, 0, 0])), 0, "sum 0 => index 0, no draw")
	var s0: int = r.state()
	r.pick_weighted(PackedInt32Array())
	t.eq(r.state(), s0, "empty weights do not draw")
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0])
	for _i: int in 3000:
		counts[r.pick_weighted(PackedInt32Array([50, 0, 50]))] += 1
	t.eq(counts[1], 0, "zero weight never picked")
	t.gt(counts[0], 1200, "weighted pick roughly even")
	t.gt(counts[2], 1200)
	t.check(not r.chance(0) and r.chance(100), "chance bounds")
