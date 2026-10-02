extends RefCounted
## NET-4: NetAiRunner (spec 5.6): cadence, sanitising, seeds, CPU governor.


class Stub extends RefCounted:
	var made: Array = []
	var thought: Array = []  # [pid, world]
	var clock: Array = [0]   # fake microsecond time source
	var cost_us: int = 0
	var released: Array = []

	func factory(pid: int, level: int, style: int, rng_seed: int) -> Callable:
		made.append([pid, level, style, rng_seed])
		return func(world: RefCounted, out: Array) -> void:
			thought.append([pid, world])
			clock[0] += cost_us
			out.append(PackedInt32Array([9, pid]))

	func now() -> int:
		return clock[0]

	func release(pid: int) -> void:
		released.append(pid)


func _runner(stub: Stub, governor: bool = true, periods: Callable = Callable()) -> NetAiRunner:
	var r: NetAiRunner = NetAiRunner.new()
	r.setup(stub.factory, 0xDEADBEEF, periods, stub.release, governor)
	r.time_source = stub.now
	return r


func _think_turns(r: NetAiRunner, sim: NetSimAdapter, from_e: int, to_e: int) -> Dictionary:
	var by_pid: Dictionary = {}
	for e: int in range(from_e, to_e + 1):
		var groups: Array = []
		r.produce(e, e + 2, sim, groups)
		var last: int = -1
		for g: Variant in groups:
			var pid: int = (g as Array)[0]
			assert(pid > last, "ascending")
			last = pid
			if not by_pid.has(pid):
				by_pid[pid] = []
			(by_pid[pid] as Array).append(e)
	return by_pid


func test_seed_and_factory_args(t: TestCtx) -> void:
	var stub: Stub = Stub.new()
	var r: NetAiRunner = _runner(stub)
	t.check(r.add_ai(2, 3, 1))
	t.eq(stub.made.size(), 1)
	t.eq(stub.made[0][0], 2)
	t.eq(stub.made[0][1], 3)
	t.eq(stub.made[0][2], 1)
	t.eq(stub.made[0][3], NetProtocol.mix32(0xDEADBEEF ^ ((3 * 0x9E3779B9) & 0xFFFFFFFF)))
	t.eq(r.seed_of(0), NetProtocol.mix32(0xDEADBEEF ^ 0x9E3779B9))
	t.ne(r.seed_of(0), r.seed_of(1), "per-pid streams")
	t.check(r.has_ai(2) and not r.has_ai(0))
	var bad: NetAiRunner = NetAiRunner.new()
	bad.setup(func(_p: int, _l: int, _s: int, _r: int) -> Variant: return null, 1)
	t.check(not bad.add_ai(0, 0, 0), "factory without a thinker")
	t.check(not NetAiRunner.new().add_ai(0, 0, 0), "no factory")


func test_cadence_default_period_is_phase_staggered(t: TestCtx) -> void:
	var stub: Stub = Stub.new()
	var r: NetAiRunner = _runner(stub)
	r.add_ai(3, 1, 0)
	r.add_ai(1, 1, 0)
	r.add_ai(0, 1, 0)
	t.eq(r.ai_pids(), PackedInt32Array([0, 1, 3]))
	var sim: NetSimAdapterFake = NetSimAdapterFake.new()
	var got: Dictionary = _think_turns(r, sim, 0, 14)
	t.eq(got[0], [0, 5, 10], "(E + pid) % 5 == 0")
	t.eq(got[1], [4, 9, 14])
	t.eq(got[3], [2, 7, 12])
	t.eq(stub.thought[0][1], sim, "the thinker gets sim.world()")


func test_per_level_periods(t: TestCtx) -> void:
	var stub: Stub = Stub.new()
	var periods: Array = [5, 3, 2, 1]
	var r: NetAiRunner = _runner(stub, true, func(level: int) -> int: return periods[level])
	r.add_ai(0, 0, 0)
	r.add_ai(1, 1, 0)
	r.add_ai(2, 2, 0)
	r.add_ai(3, 3, 0)
	t.eq([r.period_of(0), r.period_of(1), r.period_of(2), r.period_of(3)], [5, 3, 2, 1])
	var got: Dictionary = _think_turns(r, NetSimAdapterFake.new(), 0, 11)
	t.eq(got[0], [0, 5, 10])
	t.eq(got[1], [2, 5, 8, 11])
	t.eq(got[2], [0, 2, 4, 6, 8, 10])
	t.eq((got[3] as Array).size(), 12, "period 1 = every boundary")


func test_defeated_ai_stops_thinking(t: TestCtx) -> void:
	var stub: Stub = Stub.new()
	var r: NetAiRunner = _runner(stub)
	r.add_ai(0, 1, 0)
	var sim: NetSimAdapterFake = NetSimAdapterFake.new()
	var out: Array = []
	r.produce(0, 2, sim, out)
	t.eq(out.size(), 1)
	sim.submit_command(0, PackedInt32Array([NetProtocol.T_RESIGN, 0]))
	sim.step()
	out.clear()
	r.produce(5, 7, sim, out)
	t.eq(out.size(), 0)
	t.eq(stub.thought.size(), 1)


func test_sanitising(t: TestCtx) -> void:
	var r: NetAiRunner = NetAiRunner.new()
	var emit: Array = []
	r.setup(func(_p: int, _l: int, _s: int, _r: int) -> Callable:
		return func(_w: RefCounted, sink: Array) -> void:
			sink.append_array(emit), 1)
	r.add_ai(0, 0, 0)
	var big: PackedInt32Array = PackedInt32Array()
	big.resize(1025)
	emit.assign([PackedInt32Array([1, 2]), PackedInt32Array(), PackedInt32Array([256]), PackedInt32Array([-1]), big, "junk", 7,
		PackedInt32Array([255, -5, 262144])])
	var out: Array = []
	r.produce(0, 2, NetSimAdapterFake.new(), out)
	t.eq(out.size(), 1)
	var cmds: Array = (out[0] as Array)[1]
	t.eq(cmds, [PackedInt32Array([1, 2]), PackedInt32Array([255, -5, 262144])])
	t.eq(r.stats()["dropped_cmds"], 6)
	# at most 64 commands per think
	emit.clear()
	for i: int in 100:
		emit.append(PackedInt32Array([3, i]))
	out.clear()
	r.produce(5, 7, NetSimAdapterFake.new(), out)
	t.eq(((out[0] as Array)[1] as Array).size(), 64)
	t.eq(r.stats()["dropped_cmds"], 6 + 36)
	# at most 6144 encoded bytes
	emit.clear()
	for i: int in 30:
		var c: PackedInt32Array = PackedInt32Array()
		c.resize(60)
		c[0] = 4
		for k: int in range(1, 60):
			c[k] = 200_000_000 + k  # 5 bytes each -> ~300 B per command
		emit.append(c)
	out.clear()
	r.produce(10, 12, NetSimAdapterFake.new(), out)
	var kept: int = ((out[0] as Array)[1] as Array).size()
	t.check(kept >= 19 and kept <= 21, "6144 B / ~300 B = %d" % kept)


func test_governor_defers_overdue_thinkers(t: TestCtx) -> void:
	var stub: Stub = Stub.new()
	stub.cost_us = 5000
	var r: NetAiRunner = _runner(stub, true, func(_level: int) -> int: return 1)
	r.add_ai(0, 0, 0)
	r.add_ai(1, 0, 0)
	r.add_ai(2, 0, 0)
	var sim: NetSimAdapterFake = NetSimAdapterFake.new()
	var out: Array = []
	r.produce(0, 2, sim, out)
	t.eq(out.map(func(g: Variant) -> int: return (g as Array)[0]), [0, 1], "budget 8 ms is exceeded after two 5 ms thinks")
	t.check(r.is_overdue(2))
	out.clear()
	r.produce(1, 3, sim, out)
	t.eq(out.map(func(g: Variant) -> int: return (g as Array)[0]), [0, 2], "the overdue thinker ran first (output stays ascending)")
	t.check(r.is_overdue(1))
	t.check(not r.is_overdue(2))
	t.eq(r.stats()["think_us"][2], 5000)
	# governor off (unpaced): everybody on schedule
	var stub2: Stub = Stub.new()
	stub2.cost_us = 5000
	var r2: NetAiRunner = _runner(stub2, false, func(_level: int) -> int: return 1)
	r2.add_ai(0, 0, 0)
	r2.add_ai(1, 0, 0)
	r2.add_ai(2, 0, 0)
	out.clear()
	r2.produce(0, 2, sim, out)
	t.eq(out.size(), 3)
	t.check(not r2.is_overdue(0) and not r2.is_overdue(1) and not r2.is_overdue(2))


func test_slow_thinker_doubles_its_period(t: TestCtx) -> void:
	var stub: Stub = Stub.new()
	stub.cost_us = 13000
	var r: NetAiRunner = _runner(stub, true, func(_level: int) -> int: return 1)
	r.add_ai(0, 0, 0)
	var sim: NetSimAdapterFake = NetSimAdapterFake.new()
	var old: Callable = Log.sink
	var warned: Array = [0]
	Log.sink = func(lv: int, _tag: String, _msg: String) -> void:
		if lv == Log.Level.WARN:
			warned[0] += 1
	var out: Array = []
	r.produce(0, 2, sim, out)
	t.eq(r.period_of(0), 1, "one slow think is tolerated")
	r.produce(1, 3, sim, out)
	t.eq(r.period_of(0), 2, "twice in a row: doubled")
	t.eq(warned[0], 1)
	r.produce(2, 4, sim, out)
	r.produce(4, 6, sim, out)
	t.eq(r.period_of(0), 4, "doubles again after two more slow thinks")
	for e: int in range(60, 200):
		r.produce(e, e + 2, sim, out)
	t.eq(r.period_of(0), 20, "capped at 20 turns")
	Log.sink = old


func test_remove_and_release(t: TestCtx) -> void:
	var stub: Stub = Stub.new()
	var r: NetAiRunner = _runner(stub)
	r.add_ai(1, 1, 0)
	r.add_ai(4, 1, 0)
	r.remove_ai(1)
	r.remove_ai(6)
	t.eq(stub.released, [1])
	t.check(not r.has_ai(1))
	r.release_all()
	t.eq(stub.released, [1, 4])
	t.eq(r.ai_pids().size(), 0)
	# re-adding replaces (and releases) the old thinker
	r.add_ai(2, 1, 0)
	r.add_ai(2, 2, 0)
	t.eq(stub.released, [1, 4, 2])
