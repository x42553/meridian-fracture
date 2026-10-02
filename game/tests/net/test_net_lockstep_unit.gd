extends RefCounted
## NET-3: NetLockstep against NetSimAdapterFake (fill-up table, barrier, caps, S0 goldens, pause, speed, match end),
## plus the fake adapter itself.

const GOLD: Array = [
	[20, 0xE7DDB1C4, 0xA6C168F3, 0xE50086E1, 0xC8E2374D],
	[40, 0x9C652497, 0xA46D1BD5, 0x1985D524, 0x047C9649],
	[60, 0x8F911C91, 0x338B671A, 0xAC325A1E, 0x49FC95D5],
	[80, 0x45C83A4B, 0x3DD9FC11, 0xE5D90FE8, 0x99B23881],
	[100, 0xF3AE0C0D, 0x8FA5BAAE, 0xD8534782, 0x16D3F85D],
]


func _solo(d: int = 2, speed: int = 100, fake: NetSimAdapterFake = null) -> Array:
	var clock: NetClock = NetClock.manual(5_000_000)
	var sim: NetSimAdapterFake = fake if fake != null else NetSimAdapterFake.new(7)
	var ls: NetLockstep = NetLockstep.new()
	ls.setup(sim, clock, 0, d, speed)
	ls.start()
	return [ls, clock, sim]


static func _bundle(turn: int, ctrl: Array = [], pids: PackedInt32Array = PackedInt32Array(), groups: Array = []) -> NetBundle:
	return NetBundle.build(turn, pids, groups, ctrl)


func test_fake_adapter_basics(t: TestCtx) -> void:
	var f: NetSimAdapterFake = NetSimAdapterFake.new(42)
	t.eq(f.current_tick(), 0)
	t.eq(f.map_hash(), NetProtocol.fnv1a32("fake-map:42".to_utf8_buffer()))
	t.eq(f.dump_state(), "state=00003039\nstate_b=2545F491\ntick=0\n")
	f.submit_command(1, PackedInt32Array([5, 6]))
	f.step()
	t.eq(f.current_tick(), 1)
	t.eq(f.checksum_at(20), -1, "no snapshot yet")
	for _i: int in 19:
		f.step()
	t.ne(f.checksum_at(20), -1)
	t.eq(f.checksum_parts_at(20).size(), 2)
	t.eq(f.checksum_part_names(), PackedStringArray(["cmds", "clock"]))
	t.eq(f.checksum_at(20), NetSimAdapterFake.mix(f.checksum_parts_at(20)[0], f.checksum_parts_at(20)[1]))
	t.check(f.is_player_active(1) and not f.resigned(1))
	f.submit_command(1, PackedInt32Array([NetProtocol.T_RESIGN, 0]))
	f.step()
	t.check(f.resigned(1) and not f.is_player_active(1))
	for _i: int in 20 * 70:
		f.step()
	t.eq(f.checksum_at(20), -1, "old snapshots are dropped after 64")
	t.ne(f.checksum_at(f.current_tick() - f.current_tick() % 20), -1)
	# divergence hook flips exactly one bit once
	var a: NetSimAdapterFake = NetSimAdapterFake.new()
	var b: NetSimAdapterFake = NetSimAdapterFake.new()
	b.inject_divergence(40, 1)
	for _i: int in 60:
		a.step()
		b.step()
	t.eq(a.checksum_at(20), b.checksum_at(20))
	t.ne(a.checksum_at(40), b.checksum_at(40))
	t.eq(a.checksum_parts_at(40)[0] ^ b.checksum_parts_at(40)[0], 0, "cmds part untouched")
	t.eq(a.checksum_parts_at(40)[1] ^ b.checksum_parts_at(40)[1], 1, "clock part bit 0")


func test_fill_up_table(t: TestCtx) -> void:
	var r: Array = _solo()
	var ls: NetLockstep = r[0]
	var clock: NetClock = r[1]
	var sent: Array = []
	ls.on_send_input = func(turn: int, exec_turn: int, cmds: Array) -> void:
		sent.append([turn, exec_turn, cmds.size()])
	for n: int in range(2, 24):
		var ctrl: Array = []
		if n == 12:
			ctrl.append(PackedInt32Array([NetProtocol.CtrlKind.INPUT_DELAY, 3]))
		if n == 14:
			ctrl.append(PackedInt32Array([NetProtocol.CtrlKind.INPUT_DELAY, 2]))
		t.eq(ls.push_bundle(_bundle(n, ctrl)), NetProtocol.BundleResult.OK)
	# a command is always waiting, so the last packet of every boundary carries it
	for e: int in range(0, 16):
		ls.submit_local(PackedInt32Array([1, e]))
		while ls.exec_turn() <= e or ls.current_tick() % 2 == 1 and ls.exec_turn() == e:
			clock.advance_us(NetProtocol.TICK_US)
			ls.update()
		if ls.exec_turn() > e + 1:
			break
	var by_exec: Dictionary = {}
	for s: Variant in sent:
		var a: Array = s as Array
		if not by_exec.has(a[1]):
			by_exec[a[1]] = []
		(by_exec[a[1]] as Array).append([a[0], a[2]])
	t.eq((by_exec[0] as Array)[0][0], 2, "E=0 sends turn D0")
	t.eq(by_exec[10], [[12, 1]])
	t.eq(by_exec[11], [[13, 1]])
	t.eq(by_exec[12], [[14, 0], [15, 1]], "delay increase inserts an empty gap turn")
	t.eq(by_exec[13], [[16, 1]])
	t.check(not by_exec.has(14), "delay decrease skips one boundary")
	t.eq(by_exec[15], [[17, 2]], "the command pending since E=14 goes out at E=15")
	# one packet per turn on average, no gap: turns are strictly +1
	var last: int = 1
	for s: Variant in sent:
		t.eq((s as Array)[0], last + 1)
		last = (s as Array)[0]


func test_barrier_stall_and_resume(t: TestCtx) -> void:
	var r: Array = _solo()
	var ls: NetLockstep = r[0]
	var clock: NetClock = r[1]
	var stall_log: Array = []
	ls.on_stall_changed = func(stalled: bool, ms: int) -> void:
		stall_log.append([stalled, ms])
	ls.push_bundle(_bundle(2))
	var total: int = 0
	for _i: int in 20:
		clock.advance_us(NetProtocol.TICK_US)
		total += ls.update()
	t.eq(total, 6, "bundles 0..2 only: stops at tick 6")
	t.eq(ls.current_tick(), 6)
	t.check(ls.is_stalled())
	t.check(stall_log.is_empty() or stall_log[0][0] == true)
	t.check(not stall_log.is_empty(), "stall UI fired after 400 ms")
	t.check(stall_log[0][1] >= NetProtocol.STALL_UI_MS)
	t.eq(ls.push_bundle(_bundle(3)), NetProtocol.BundleResult.OK)
	for n: int in range(4, 14):
		ls.push_bundle(_bundle(n))
	clock.advance_us(NetProtocol.TICK_US)
	t.gt(ls.update(), 0, "resumes when bundle 3 arrives")
	t.check(not ls.is_stalled(), "later bundles are there too")
	t.eq(stall_log.back()[0], false)
	var rep: Dictionary = ls.take_report()
	t.eq(rep["episodes"], 1)
	t.eq(rep["hitch"], false)
	t.check(rep["stall_ms"] >= 600 and rep["stall_ms"] <= 800, "about 700 ms: %d" % rep["stall_ms"])


func test_push_bundle_results(t: TestCtx) -> void:
	var r: Array = _solo()
	var ls: NetLockstep = r[0]
	t.eq(ls.push_bundle(_bundle(1)), NetProtocol.BundleResult.DUPLICATE, "pre-roll turns are already implicit")
	t.eq(ls.push_bundle(_bundle(2)), NetProtocol.BundleResult.OK)
	t.eq(ls.push_bundle(_bundle(2)), NetProtocol.BundleResult.DUPLICATE)
	t.eq(ls.push_bundle(_bundle(5)), NetProtocol.BundleResult.OK, "out of order is buffered")
	t.eq(ls.push_bundle(_bundle(5)), NetProtocol.BundleResult.DUPLICATE)
	t.eq(ls.stats()["ooo"], 1)
	t.eq(ls.push_bundle(_bundle(3)), NetProtocol.BundleResult.OK)
	t.eq(ls.push_bundle(_bundle(4)), NetProtocol.BundleResult.OK)
	t.eq(ls.stats()["ooo"], 0, "drained")
	t.eq(ls.stats()["next_push"], 6)
	t.eq(ls.push_bundle(_bundle(6 + NetProtocol.REORDER_WINDOW)), NetProtocol.BundleResult.OK)
	t.eq(ls.push_bundle(_bundle(7 + NetProtocol.REORDER_WINDOW)), NetProtocol.BundleResult.TOO_FAR)
	t.eq(ls.push_bundle(null), NetProtocol.BundleResult.MALFORMED)


func test_tick_caps(t: TestCtx) -> void:
	var r: Array = _solo(2, 200)
	var ls: NetLockstep = r[0]
	var clock: NetClock = r[1]
	for n: int in range(2, 60):
		ls.push_bundle(_bundle(n))
	clock.advance_us(5_000_000)
	t.eq(ls.update(), NetProtocol.MAX_TICKS_PER_POLL, "8 ticks per poll at most (250 ms elapsed cap x 200 %)")
	t.eq(ls.update(), 2, "the remainder of the accumulator, nothing more")
	t.eq(ls.update(), 0)
	# 100 %: a 5 s jump yields 5 ticks (elapsed cap 250 ms), never a fast-forward
	var r2: Array = _solo()
	var l2: NetLockstep = r2[0]
	for n: int in range(2, 60):
		l2.push_bundle(_bundle(n))
	(r2[1] as NetClock).advance_us(5_000_000)
	t.eq(l2.update(), 5)
	# accumulator cap after a stall: only 4 ticks are banked
	var r3: Array = _solo()
	var l3: NetLockstep = r3[0]
	var c3: NetClock = r3[1]
	for _i: int in 40:
		c3.advance_us(NetProtocol.TICK_US)
		l3.update()
	t.eq(l3.current_tick(), 4, "turns 0 and 1 are implicit; stalls at tick 4 waiting for bundle 2")
	for n: int in range(2, 60):
		l3.push_bundle(_bundle(n))
	t.eq(l3.update(), 4, "the banked debt is capped at 4 ticks")
	t.eq(l3.update(), 0)


func test_unpaced_ignores_clock_not_barrier(t: TestCtx) -> void:
	var r: Array = _solo(2, 0)
	var ls: NetLockstep = r[0]
	for n: int in range(2, 40):
		ls.push_bundle(_bundle(n))
	t.eq(ls.update(64), 64, "no clock advance needed")
	t.eq(ls.update(0), 0, "max_ticks 0 runs nothing")
	var r2: Array = _solo(2, 0)
	var l2: NetLockstep = r2[0]
	l2.push_bundle(_bundle(2))
	t.eq(l2.update(64), 6, "barrier still enforced")
	t.check(l2.is_stalled())


func test_s0_goldens(t: TestCtx) -> void:
	var kit: NetLockstepKit = NetLockstepKit.new(NetLockstepKit.fakes(2), 2)
	kit.cmd_script = NetLockstepKit.script_s0()
	kit.run_to(100)
	for p: NetLockstepKit.Peer in kit.peers:
		t.eq(p.lockstep.current_tick(), 100)
		for g: Variant in GOLD:
			var row: Array = g as Array
			var tick: int = row[0]
			t.eq(p.checks[tick][0], row[1], "checksum @%d pid %d" % [tick, p.pid])
			t.eq(p.checks[tick][1], row[2], "chain @%d pid %d" % [tick, p.pid])
			var parts: PackedInt32Array = p.adapter.checksum_parts_at(tick)
			t.eq(parts[0] & 0xFFFFFFFF, row[3], "cmds part @%d" % tick)
			t.eq(parts[1] & 0xFFFFFFFF, row[4], "clock part @%d" % tick)


func test_pause_and_resume(t: TestCtx) -> void:
	var r: Array = _solo()
	var ls: NetLockstep = r[0]
	var clock: NetClock = r[1]
	var pauses: Array = []
	var sent: Array = []
	ls.on_pause = func(p: bool) -> void:
		pauses.append(p)
	ls.on_send_input = func(turn: int, _e: int, _c: Array) -> void:
		sent.append(turn)
	for n: int in range(2, 40):
		ls.push_bundle(_bundle(n, [PackedInt32Array([NetProtocol.CtrlKind.PAUSE, 0])] if n == 9 else []))
	for _i: int in 60:
		clock.advance_us(NetProtocol.TICK_US)
		ls.update()
	t.check(ls.is_paused(), "paused at boundary 10")
	t.eq(ls.current_tick(), 20)
	t.eq(pauses, [true])
	var n_sent: int = sent.size()
	clock.advance_us(NetProtocol.TICK_US * 4)
	t.eq(ls.update(), 0)
	t.eq(sent.size(), n_sent, "no TURN_INPUT while paused")
	ls.resume(9)
	t.check(ls.is_paused(), "a stale RESUME does not unpause")
	ls.resume(10)
	t.check(not ls.is_paused())
	t.eq(pauses, [true, false])
	clock.advance_us(NetProtocol.TICK_US * 2)
	t.gt(ls.update(), 0)
	# quick toggle: the RESUME overtakes the pause bundle
	var r2: Array = _solo()
	var l2: NetLockstep = r2[0]
	var c2: NetClock = r2[1]
	var p2: Array = []
	l2.on_pause = func(p: bool) -> void:
		p2.append(p)
	for n: int in range(2, 40):
		l2.push_bundle(_bundle(n, [PackedInt32Array([NetProtocol.CtrlKind.PAUSE, 0])] if n == 9 else []))
	l2.resume(10)
	for _i: int in 60:
		c2.advance_us(NetProtocol.TICK_US)
		l2.update()
	t.check(not l2.is_paused() and p2.is_empty(), "already resumed: never pauses")
	t.gt(l2.current_tick(), 30)


func test_speed_ctrl_halves_wall_time(t: TestCtx) -> void:
	var kit1: NetLockstepKit = NetLockstepKit.new(NetLockstepKit.fakes(1), 2)
	var kit2: NetLockstepKit = NetLockstepKit.new(NetLockstepKit.fakes(1), 2)
	kit2.host.set_speed(200)
	var f1: int = kit1.run_to(200)
	var f2: int = kit2.run_to(200)
	t.eq(f1, 200)
	t.check(f2 >= 100 and f2 <= 104, "200 %% speed: about half the frames (%d)" % f2)
	t.eq(kit2.peers[0].lockstep.get_speed_pct(), 200)


func test_match_over_stops_with_final_checksum(t: TestCtx) -> void:
	var fake: NetSimAdapterFake = NetSimAdapterFake.new(1, 45)
	var r: Array = _solo(2, 100, fake)
	var ls: NetLockstep = r[0]
	var clock: NetClock = r[1]
	var got: Array = []
	var over: Array = [0]
	ls.on_checksum = func(tick: int, cs: int, chain: int) -> void:
		got.append([tick, cs, chain])
	ls.on_match_over = func() -> void:
		over[0] += 1
	for n: int in range(2, 60):
		ls.push_bundle(_bundle(n))
	for _i: int in 200:
		clock.advance_us(NetProtocol.TICK_US)
		ls.update()
	t.eq(fake.current_tick(), 45)
	t.check(ls.is_over())
	t.eq(over[0], 1)
	t.eq(got.size(), 3, "ticks 20, 40 and the final 45")
	t.eq(got[2][0], 45)
	t.eq(got[2][1], fake.checksum_now())
	t.eq(got[2][2], ls.input_chain())
	t.eq(ls.update(), 0)
	t.eq(ls.push_bundle(_bundle(30)), NetProtocol.BundleResult.WRONG_STATE)


func test_submit_local_limits(t: TestCtx) -> void:
	var r: Array = _solo()
	var ls: NetLockstep = r[0]
	t.check(not ls.submit_local(PackedInt32Array()))
	t.check(not ls.submit_local(PackedInt32Array([256])))
	t.check(not ls.submit_local(PackedInt32Array([-1])))
	var big: PackedInt32Array = PackedInt32Array()
	big.resize(1025)
	t.check(not ls.submit_local(big))
	for i: int in NetProtocol.LOCAL_QUEUE_MAX:
		t.check(ls.submit_local(PackedInt32Array([1, i])))
	t.check(not ls.submit_local(PackedInt32Array([1])), "257th is refused")
	# a boundary sends at most 64 commands; the rest stay pending in FIFO order
	var sent: Array = []
	ls.on_send_input = func(turn: int, _e: int, cmds: Array) -> void:
		sent.append([turn, cmds])
	for n: int in range(2, 12):
		ls.push_bundle(_bundle(n))
	var clock: NetClock = r[1]
	for _i: int in 2:
		clock.advance_us(NetProtocol.TICK_US)
		ls.update()
	t.eq(sent.size(), 1)
	t.eq((sent[0][1] as Array).size(), 64)
	t.eq(((sent[0][1] as Array)[63] as PackedInt32Array)[1], 63)
	t.eq(ls.pending_count(), 192)
	# a dedicated host (no local pid) sends nothing but still gets boundaries
	var clock2: NetClock = NetClock.manual()
	var l2: NetLockstep = NetLockstep.new()
	l2.setup(NetSimAdapterFake.new(), clock2, -1, 2, 100)
	l2.start()
	var bnd: Array = []
	l2.on_boundary = func(e: int, target: int) -> void:
		bnd.append([e, target])
	for n: int in range(2, 12):
		l2.push_bundle(_bundle(n))
	t.check(not l2.submit_local(PackedInt32Array([1])))
	for _i: int in 6:
		clock2.advance_us(NetProtocol.TICK_US)
		l2.update()
	t.eq(bnd, [[0, 2], [1, 3], [2, 4]])


func test_report_slack_and_load(t: TestCtx) -> void:
	var kit: NetLockstepKit = NetLockstepKit.new(NetLockstepKit.fakes(2), 2)
	kit.run_to(60)
	var rep: Dictionary = kit.peers[1].lockstep.take_report()
	t.gt(rep["slack_min_ms"], 100, "zero-latency relay: bundles arrive far ahead of their due time")
	t.eq(rep["stall_ms"], 0)
	t.eq(rep["exec_turn"], 30)
	t.eq(kit.peers[1].lockstep.take_report()["slack_min_ms"], 32767, "window restarts")


func test_two_peers_stay_identical_with_random_script(t: TestCtx) -> void:
	var kit: NetLockstepKit = NetLockstepKit.new(NetLockstepKit.fakes(3), 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	for i: int in 60:
		kit.cmd_script.append({"turn": 4 + i * 2, "pid": rng.randi() % 3, "ints": PackedInt32Array([rng.randi() % 200, rng.randi() % 100 - 50])})
	kit.run_to(400)
	var first: NetLockstepKit.Peer = kit.peers[0]
	for p: NetLockstepKit.Peer in kit.peers:
		t.eq(p.lockstep.current_tick(), 400)
		t.eq(p.lockstep.input_chain(), first.lockstep.input_chain())
		t.eq(p.adapter.checksum_now(), first.adapter.checksum_now())
		t.eq(p.checks.size(), 20)


func test_world_job_sync(t: TestCtx) -> void:
	var ok: NetWorldJob = NetWorldJob.sync(func() -> NetSimAdapter: return NetSimAdapterFake.new(9))
	t.eq(ok.progress_pct(), 0)
	t.check(ok.step(4000))
	t.eq(ok.progress_pct(), 100)
	t.eq(ok.error(), "")
	var a: NetSimAdapter = ok.take_adapter()
	t.check(a is NetSimAdapterFake)
	t.check(ok.step(4000), "finished jobs stay finished")
	var bad: NetWorldJob = NetWorldJob.sync(func() -> Variant: return null)
	t.check(bad.step(4000))
	t.ne(bad.error(), "")
	t.is_null(bad.take_adapter())
	var none: NetWorldJob = NetWorldJob.sync(Callable())
	t.check(none.step(1))
	t.ne(none.error(), "")
