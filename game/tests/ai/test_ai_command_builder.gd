extends RefCounted
## AiCommandBuilder: dedup, chunking, APM bucket with reserve, class order, flush cap, no-effect blacklist, wire types.


func _cb(level: int = AiTypes.Difficulty.HARD) -> AiCommandBuilder:
	var b: AiCommandBuilder = AiCommandBuilder.new(0, AiDataStore.load_default().difficulty(level))
	b.begin_think(10, 1000)
	return b


func _ids(n: int, first: int = 1) -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		a.append(first + i)
	return a


func test_one_order_per_unit_last_wins(t: TestCtx) -> void:
	var b: AiCommandBuilder = _cb()
	t.check(b.move(PackedInt32Array([1, 2, 3]), 5000, 5000))
	t.check(b.attack_move(PackedInt32Array([2, 3, 4]), 9000, 9000))
	var out: Array = []
	t.eq(b.flush(out), 2)
	var first: PackedInt32Array = out[0]
	var second: PackedInt32Array = out[1]
	t.eq(first[0], SimCmd.MOVE)
	t.eq(first.slice(first.size() - 1), PackedInt32Array([1]), "units 2 and 3 were taken over by the later intent")
	t.eq(second[0], SimCmd.ATTACK_MOVE)
	t.eq(second.slice(second.size() - 3), PackedInt32Array([2, 3, 4]))


func test_chunking_100_units(t: TestCtx) -> void:
	var b: AiCommandBuilder = _cb(AiTypes.Difficulty.BRUTAL)
	t.check(b.attack_move(_ids(100), 4096, 4096))
	var out: Array = []
	t.eq(b.flush(out), 3, "100 units => 48 / 48 / 4")
	var sizes: Array = []
	for c: PackedInt32Array in out:
		t.check(c.size() >= 1 and c.size() <= 1024)
		t.check(c[0] >= 0 and c[0] <= 255)
		sizes.append(c.size() - 5)  # [type, x, y, mode, flags] precede the ids
	t.eq(sizes, [48, 48, 4] as Array)


func test_apm_bucket_and_reserve(t: TestCtx) -> void:
	var b: AiCommandBuilder = _cb()
	t.eq(b.tokens(), 16 * 256, "starts full: cmd_burst x 256")
	var queued: int = 0
	for i: int in 100:
		if b.move(PackedInt32Array([1000 + i]), 1024 * (i + 1), 2048):
			queued += 1
	t.le(queued, 16, "at most the burst")
	t.gt(queued, 5)
	t.check(b.use_power(3, 5000, 5000), "class 0 still emits: 30 % of the capacity is reserved for classes 0-1")
	t.check(b.build_start(7), "class 1 too")
	var out: Array = []
	t.check(b.flush(out) <= 64)
	# refill: 180 x 256 x 10 / 1200 = 384 tokens
	var before: int = b.tokens()
	b.begin_think(10, 1010)
	t.eq(b.tokens(), mini(16 * 256, before + 384), "refill Hard dt 10")


func test_flush_cap_and_class_order(t: TestCtx) -> void:
	var b: AiCommandBuilder = _cb(AiTypes.Difficulty.BRUTAL)
	b.begin_think(600, 2000)  # a long think refills the bucket
	for i: int in 12:
		b.build_start(100 + i)
	for i: int in 12:
		b.attack_move(PackedInt32Array([50 + i]), 1024 * (i + 1), 1024)
	b.use_power(1, 2048, 2048)
	var out: Array = []
	var n: int = b.flush(out)
	t.le(n, AiTypes.AI_MAX_CMDS_PER_THINK)
	t.eq((out[0] as PackedInt32Array)[0], SimCmd.USE_POWER, "class 0 first")


func test_duplicates_and_blacklist(t: TestCtx) -> void:
	var b: AiCommandBuilder = _cb()
	t.check(b.build_start(5))
	t.check_false(b.build_start(5), "duplicate in the same think")
	b.note_no_effect(AiTypes.Intent.BUILD_START, 5, 1000)
	b.begin_think(10, 1010)
	t.check_false(b.build_start(5), "first strike backs off")
	b.begin_think(10, 1100)
	t.check(b.build_start(5), "back-off over")
	b.note_no_effect(AiTypes.Intent.BUILD_START, 5, 1100)
	t.check(b.is_blocked(AiTypes.Intent.BUILD_START, 5, 1100 + 1199))
	t.check_false(b.is_blocked(AiTypes.Intent.BUILD_START, 5, 1100 + 1200), "blacklisted for 1200 ticks")
	b.note_effect(AiTypes.Intent.BUILD_START, 5)


func test_wire_types_match_the_sim(t: TestCtx) -> void:
	var b: AiCommandBuilder = _cb(AiTypes.Difficulty.BRUTAL)
	b.begin_think(600, 3000)
	var u: PackedInt32Array = PackedInt32Array([11, 12])
	b.attack(u, 77)
	b.attack_move(PackedInt32Array([13]), 2048, 2048)
	b.guard(PackedInt32Array([14]), 0, 4096, 4096)
	b.hold(PackedInt32Array([15]))
	b.force_fire(PackedInt32Array([16]), 3000, 3000)
	b.set_stance(PackedInt32Array([17]), 2)
	b.return_to_base(PackedInt32Array([18]))
	b.build_start(3)
	b.build_place(3, 10, 12)
	b.train(99, 4, 2)
	b.research(6)
	b.launch_superweapon(1000, 2000, 5000)
	var out: Array = []
	b.flush(out)
	var types: Array = []
	for c: PackedInt32Array in out:
		types.append(c[0])
	t.check(types.has(40) and types.has(41) and types.has(42) and types.has(43) and types.has(44) and types.has(45) and types.has(47), "combat block 40..47")
	t.check(types.has(SimCmd.BUILD_START) and types.has(SimCmd.BUILD_PLACE) and types.has(SimCmd.TRAIN) and types.has(SimCmd.RESEARCH))
	for c2: PackedInt32Array in out:
		if c2[0] == SimCmd.LAUNCH_SUPERWEAPON:
			t.eq(c2, PackedInt32Array([SimCmd.LAUNCH_SUPERWEAPON, 1000, 2000, 5000 & 4095]), "angle wrapped into 0..4095")
	var st: Dictionary = b.stats()
	t.eq(int(st.get(AiTypes.Intent.ATTACK, 0)), 1)
	t.gt(int(st["emitted"]), 5)
