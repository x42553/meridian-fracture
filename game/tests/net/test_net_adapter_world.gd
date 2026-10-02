extends RefCounted
## NET-3 / NET-13 slice: the REAL adapter. A host and two loopback clients (real NetTransportLoopback, real codec,
## NetTurnHost, NetLockstep, PING/PONG feeding the adaptive delay policy) each advance their own real SimWorld
## (SimMatchSetup.create_world through SimMatchKit) driven by scripted SimBots that act only by submitting commands
## through the lockstep. All three worlds must stay bit-identical.


class RecLog extends SimCommandLog:
	var out: Array[PackedInt32Array] = []

	func submit(_world: SimWorld, _pid: int, ints: PackedInt32Array) -> void:
		out.append(ints.duplicate())


class RPeer extends RefCounted:
	var pid: int = 0
	var world: SimWorld = null
	var adapter: NetSimAdapterWorld = null
	var lockstep: NetLockstep = null
	var bot: SimBot = null
	var rec: RecLog = RecLog.new()
	var transport: NetTransportLoopback = null
	var checks: Dictionary = {}
	var final_check: Array = []
	var last_think: int = -1
	var sent_cmds: int = 0
	var errors: PackedStringArray = PackedStringArray()


class Rig extends RefCounted:
	var clock: NetClock = NetClock.manual(50_000_000)
	var hub: NetLoopbackHub = null
	var host_t: NetTransportLoopback = null
	var host: NetTurnHost = NetTurnHost.new()
	var peers: Array[RPeer] = []
	var bundles: int = 0
	var commands: int = 0
	var ping_seq: int = 0
	var last_ping_us: int = 0
	var stop_tick: int = 600
	var ctrl_seen: Array = []

	func _init(rosters: PackedStringArray, fixed_delay: int, opts: Dictionary, bot_opts: Dictionary = {}) -> void:
		hub = NetLoopbackHub.new(clock)
		host_t = hub.endpoint(0)
		host_t.listen(NetProtocol.DEFAULT_PORT, 8)
		host.setup(clock, {"initial_delay": 2, "fixed_delay": fixed_delay})
		var cfg_opts: Dictionary = {"rosters": rosters, "bots": false, "seed": 5, "size": 96, "rules": {"fog": true}}
		cfg_opts.merge(opts, true)
		for i: int in rosters.size():
			var p: RPeer = RPeer.new()
			p.pid = i
			p.world = SimMatchKit.make_match(cfg_opts)["world"] as SimWorld
			p.adapter = NetSimAdapterWorld.new(p.world)
			p.bot = SimBot.new(i, bot_opts)
			p.bot.cmd_log = p.rec
			var ls: NetLockstep = NetLockstep.new()
			ls.setup(p.adapter, clock, i, 2, 100)
			p.lockstep = ls
			ls.on_checksum = func(tick: int, cs: int, chain: int) -> void:
				p.checks[tick] = [cs, chain, p.adapter.checksum_parts_at(tick)]
				if p.adapter.is_match_over():
					p.final_check = [tick, cs, chain]
			ls.on_ctrl = func(turn: int, c: PackedInt32Array) -> void:
				ctrl_seen.append([p.pid, turn, c])
			if i == 0:
				ls.on_send_input = func(turn: int, exec_turn: int, cmds: Array) -> void:
					host.on_input(0, turn, exec_turn, cmds)
				ls.on_boundary = func(_t: int, target: int) -> void:
					host.note_injection_through(target)
				host.set_player(0, NetProtocol.PlayerRole.PR_HUMAN, 1)
			else:
				p.transport = hub.endpoint(i)
				p.transport.connect_to("host", NetProtocol.DEFAULT_PORT, NetProtocol.connect_data())
				ls.on_send_input = func(turn: int, exec_turn: int, cmds: Array) -> void:
					p.transport.send(1, NetProtocol.CH_TURN, NetCodec.encode_turn_input({"turn": turn, "exec_turn": exec_turn, "cmds": cmds}))
			peers.append(p)
		host_t.poll()
		host_t.take_events()
		for p: RPeer in peers:
			if p.transport != null:
				p.transport.poll()
				p.transport.take_events()
				host.set_player(p.pid, NetProtocol.PlayerRole.PR_HUMAN, p.pid + 1)
		for p: RPeer in peers:
			p.lockstep.start()
		last_ping_us = clock.now_us()

	func _send_bundles() -> void:
		for b: NetBundle in host.close_ready():
			bundles += 1
			commands += b.command_count()
			for p: RPeer in peers:
				if p.transport == null:
					p.lockstep.push_bundle(b)
				else:
					var pb: NetBundle = host._bundle_for_peer(b, p.pid + 1)
					host_t.send(p.pid + 1, NetProtocol.CH_TURN, pb.wire_bytes())

	func _dispatch_host() -> void:
		host_t.poll()
		for e: NetTransportEvent in host_t.take_events():
			if e.kind != NetTransportEvent.Kind.PACKET:
				continue
			match NetCodec.peek_type(e.data):
				NetProtocol.Msg.TURN_INPUT:
					var d: Dictionary = NetCodec.decode_turn_input(e.data)
					var pid: int = host.pid_of_peer(e.peer_id)
					if not d.is_empty() and pid >= 0:
						host.on_input(pid, int(d["turn"]), int(d["exec_turn"]), d["cmds"] as Array)
				NetProtocol.Msg.PONG:
					var d: Dictionary = NetCodec.decode_pong(e.data)
					if not d.is_empty():
						d["rtt_ms"] = (clock.now_ms() - int(d["echo_ms"])) & 0xFFFFFFFF
						host.on_pong(e.peer_id, d)

	func _dispatch_client(p: RPeer) -> void:
		p.transport.poll()
		for e: NetTransportEvent in p.transport.take_events():
			if e.kind != NetTransportEvent.Kind.PACKET:
				continue
			match NetCodec.peek_type(e.data):
				NetProtocol.Msg.TURN_BUNDLE:
					var b: NetBundle = NetCodec.decode_bundle(e.data)
					if b == null:
						p.errors.append("undecodable bundle")
					else:
						p.lockstep.push_bundle(b)
				NetProtocol.Msg.PING:
					var d: Dictionary = NetCodec.decode_ping(e.data)
					var rep: Dictionary = p.lockstep.take_report()
					rep["seq"] = int(d["seq"])
					rep["echo_ms"] = int(d["host_ms"])
					p.transport.send(1, NetProtocol.CH_CTRL, NetCodec.encode_pong(rep))

	## One rendered frame of 50 ms (spec 3.0 order): transports, bundles out, sim ticks, bundles out, timers, flush.
	func frame() -> void:
		clock.advance_us(NetProtocol.TICK_US)
		_dispatch_host()
		for p: RPeer in peers:
			if p.transport != null:
				_dispatch_client(p)
		_send_bundles()
		for p: RPeer in peers:
			if p.lockstep.current_tick() >= stop_tick or p.lockstep.is_over():
				continue
			if p.world.tick != p.last_think:
				p.last_think = p.world.tick
				p.bot.think(p.world)
				for ints: PackedInt32Array in p.rec.out:
					if p.lockstep.submit_local(ints):
						p.sent_cmds += 1
				p.rec.out.clear()
			p.lockstep.update()
		_send_bundles()
		host.evaluate(clock.now_us())
		if clock.now_us() - last_ping_us >= NetProtocol.PING_INTERVAL_MS * 1000:
			last_ping_us = clock.now_us()
			ping_seq += 1
			host_t.send(2, NetProtocol.CH_CTRL, NetCodec.encode_ping({"seq": ping_seq, "host_ms": clock.now_ms() & 0xFFFFFFFF}))
			if peers.size() > 2:
				host_t.send(3, NetProtocol.CH_CTRL, NetCodec.encode_ping({"seq": ping_seq, "host_ms": clock.now_ms() & 0xFFFFFFFF}))
		host_t.flush()

	func done() -> bool:
		for p: RPeer in peers:
			if p.lockstep.current_tick() < stop_tick and not p.lockstep.is_over():
				return false
		return true

	func run(max_frames: int) -> int:
		var f: int = 0
		while f < max_frames and not done():
			frame()
			f += 1
		return f


static func _rosters3() -> PackedStringArray:
	var seen: Dictionary = {}
	var out: PackedStringArray = PackedStringArray()
	for r: DefRoster in SimMatchKit.data().rosters:
		var parts: PackedStringArray = r.id.split(".")
		if parts.size() >= 3 and parts[2] == "vanilla" and not seen.has(parts[1]) and out.size() < 3:
			seen[parts[1]] = true
			out.append(r.id)
	return out


func test_adapter_forwards_to_the_world(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"bots": false, "seed": 3})
	var w: SimWorld = m["world"]
	var a: NetSimAdapterWorld = NetSimAdapterWorld.new(w)
	t.check(a.world() == w)
	t.eq(a.current_tick(), 0)
	t.eq(a.map_hash(), w.map_hash())
	t.eq(a.checksum_now(), w.checksum())
	t.eq(a.checksum_part_names(), SimWorld.CHECKSUM_PART_NAMES)
	t.eq(a.checksum_part_names().size(), 16)
	t.eq(a.checksum_at(20), -1)
	a.submit_command(0, PackedInt32Array())
	a.submit_command(0, PackedInt32Array([201, 1, 2, 3]))  # unknown op: ignored by the sim, counted there
	t.eq(a.malformed_count, 1)
	for _i: int in 40:
		a.step()
	t.eq(a.current_tick(), 40)
	t.eq(a.checksum_at(20), w.checksum_at(20))
	t.ne(a.checksum_at(20), -1)
	t.eq(a.checksum_parts_at(40).size(), 16)
	t.eq(a.checksum_parts_at(40), w.checksum_parts_at(40))
	t.check(a.dump_state().length() > 100)
	t.check(a.is_player_active(0) and a.is_player_active(1))
	t.check(not a.is_player_active(5))
	t.check(not a.is_match_over())
	t.eq(a.match_result()["winner_team"], -1)
	a.submit_command(1, PackedInt32Array([NetProtocol.T_RESIGN, NetProtocol.ResignReason.SURRENDER]))
	a.step()
	t.check(not a.is_player_active(1), "T_RESIGN eliminates the player")
	a.step()
	t.check(a.is_match_over(), "two players, one resigned: the match is decided")
	t.eq(a.match_result()["winner_team"], 1)
	a.clear_events()


func test_host_and_two_clients_advance_a_real_match_600_ticks(t: TestCtx) -> void:
	t.set_timeout(240.0)
	var rig: Rig = Rig.new(_rosters3(), 0, {})
	var frames: int = rig.run(3000)
	var p0: RPeer = rig.peers[0]
	for p: RPeer in rig.peers:
		t.eq(p.lockstep.current_tick(), 600, "pid %d reached tick 600" % p.pid)
		t.eq(p.world.tick, 600)
		t.check(p.errors.is_empty())
	t.check(frames < 700, "paced at 20 ticks/s with 2 frames of relay latency: %d frames" % frames)
	# identical hash chain at every checkpoint, identical parts, identical input chain
	t.eq(p0.checks.size(), 30)
	for p: RPeer in rig.peers:
		for tick: Variant in p0.checks:
			t.eq((p.checks[tick] as Array)[0], (p0.checks[tick] as Array)[0], "checksum @%d pid %d" % [int(tick), p.pid])
			t.eq((p.checks[tick] as Array)[1], (p0.checks[tick] as Array)[1], "input chain @%d pid %d" % [int(tick), p.pid])
			t.eq(((p.checks[tick] as Array)[2] as PackedInt32Array).size(), 16)
			t.eq((p.checks[tick] as Array)[2], (p0.checks[tick] as Array)[2])
		t.eq(p.adapter.checksum_now(), p0.adapter.checksum_now())
		t.eq(p.adapter.map_hash(), p0.adapter.map_hash())
		t.eq(p.lockstep.input_chain(), p0.lockstep.input_chain())
		t.eq(p.adapter.dump_state(), p0.adapter.dump_state())
	# the checksums moved (the match did something) and the bots' commands went through the bundles
	var distinct: Dictionary = {}
	for tick: Variant in p0.checks:
		distinct[(p0.checks[tick] as Array)[0]] = true
	t.eq(distinct.size(), 30, "state changes every second")
	t.gt(rig.commands, 5, "commands travelled through bundles: %d" % rig.commands)
	t.gt(p0.sent_cmds, 1)
	for p: RPeer in rig.peers:
		t.gt(p.world.structures_of(p.pid).size(), 1, "pid %d built something" % p.pid)
		t.eq(p.world.structures_of(p.pid).size(), p0.world.structures_of(p.pid).size())
		t.eq(SimMatchKit.report(p.world, p.pid), SimMatchKit.report(p0.world, p.pid))
	# the adaptive policy ran on loopback PONGs and kept the LAN default
	t.eq(rig.host.delay_turns(), 2)
	t.gt(rig.host._policy.peer_rtt_ms(2) + 1, 0)
	for ctrl: Variant in rig.ctrl_seen:
		t.ne(((ctrl as Array)[2] as PackedInt32Array)[0], NetProtocol.CtrlKind.INPUT_DELAY, "no delay change on a LAN")


func test_resign_and_drop_end_a_real_match_on_every_peer(t: TestCtx) -> void:
	t.set_timeout(240.0)
	var rig: Rig = Rig.new(_rosters3(), 2, {})
	rig.stop_tick = 800
	var stage: int = 0
	var guard: int = 0
	while not rig.done() and guard < 2000:
		guard += 1
		rig.frame()
		var tick: int = rig.peers[0].lockstep.current_tick()
		if stage == 0 and tick >= 100:
			stage = 1
			rig.peers[2].lockstep.submit_local(PackedInt32Array([NetProtocol.T_RESIGN, NetProtocol.ResignReason.SURRENDER]))
		elif stage == 1 and tick >= 200:
			stage = 2
			rig.host.drop_player(1, NetProtocol.StallAction.STALL_DROP_RESIGN, NetProtocol.ResignReason.KICKED)
	var end_tick: int = -1
	for p: RPeer in rig.peers:
		t.check(p.lockstep.is_over(), "pid %d saw the match end" % p.pid)
		t.check(not p.final_check.is_empty())
		if end_tick < 0:
			end_tick = p.final_check[0]
		t.eq(p.final_check, rig.peers[0].final_check, "same end tick, same final checksum, same input chain")
		t.check(not p.adapter.is_player_active(1) and not p.adapter.is_player_active(2))
		t.check(p.adapter.is_player_active(0))
		t.eq(p.adapter.match_result()["winner_team"], 1)
	t.gt(end_tick, 200)
	t.lt(end_tick, 260, "decided a few ticks after the injected T_RESIGN")
	# the injected resign is first in pid 1's group and its status record travelled in the same bundle
	var status_seen: bool = false
	for c: Variant in rig.ctrl_seen:
		var rec: PackedInt32Array = (c as Array)[2] as PackedInt32Array
		if rec[0] == NetProtocol.CtrlKind.PLAYER_STATUS and rec[1] == 1 and rec[2] == NetProtocol.PlayerNetStatus.DROPPED:
			status_seen = true
	t.check(status_seen)


func test_longer_match_with_units_stays_identical(t: TestCtx) -> void:
	t.set_timeout(300.0)
	var rig: Rig = Rig.new(_rosters3(), 0, {"credits": 30000}, {"first_attack_tick": 1500, "wave_size": 4})
	rig.stop_tick = 2400
	rig.run(6000)
	var p0: RPeer = rig.peers[0]
	t.eq(p0.checks.size(), 120)
	for p: RPeer in rig.peers:
		t.eq(p.lockstep.current_tick(), 2400)
		for tick: Variant in p0.checks:
			t.eq((p.checks[tick] as Array)[0], (p0.checks[tick] as Array)[0], "checksum @%d pid %d" % [int(tick), p.pid])
		t.eq(p.adapter.dump_state(), p0.adapter.dump_state())
		t.gt(p.world.units_of(p.pid).size(), 0, "pid %d has units" % p.pid)
	t.gt(rig.commands, 25, "commands: %d" % rig.commands)
	t.eq(rig.host.delay_turns(), 2)
