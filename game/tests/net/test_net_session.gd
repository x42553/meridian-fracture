extends RefCounted
## NET-10: NetSession end to end over the loopback hub in virtual time (phase machine, launch success / abort matrix,
## LOCAL path, pause, speed, drops, deferred shutdown). Fake worlds unless a test says "real".

const P := NetSession.Phase


func _new_kit() -> NetSessionKit:
	return NetSessionKit.new()


## Host + clients in the lobby, everybody ready, launch started; returns the host.
func _launch(kit: NetSessionKit, n_clients: int, host_extra: Dictionary = {}, ai_slots: int = 0) -> NetSession:
	var h: NetSession = kit.lobby_of(n_clients, host_extra)
	for i: int in ai_slots:
		h.lobby.host_set_slot_kind(1 + n_clients + i, NetProtocol.SlotKind.AI)
	for s: NetSession in kit.sessions:
		if s != h:
			s.lobby.set_ready(true)
	kit.step(3)
	for s: NetSession in kit.sessions:
		s.lobby.set_team(1 if s == h else 2)
	kit.step(3)
	return h


func test_join_and_lobby_basics(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var h: NetSession = kit.lobby_of(2)
	t.eq(h.phase, P.LOBBY)
	t.eq(kit.sessions[1].phase, P.LOBBY)
	t.eq(kit.sessions[1].local_peer_id, 2)
	t.eq(kit.sessions[2].local_peer_id, 3)
	t.eq(h.lobby.state.human_count(), 3)
	t.eq(kit.sessions[1].lobby.state.human_count(), 3, "client mirrors the host snapshot")
	t.eq(kit.sessions[1].lobby.local_slot(), 1)
	t.eq(h.lobby.state.slots[2].name, "P3")
	kit.shutdown_all()


func test_full_launch_and_match(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var h: NetSession = _launch(kit, 2)
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	var seen: Array = []
	for s: NetSession in kit.sessions:
		s.phase_changed.connect(func(p: int, _prev: int) -> void: seen.append(p))
	t.check(kit.all_in(P.PLAYING, 200), "everybody playing")
	t.check(seen.has(P.LOADING) and seen.has(P.PLAYING))
	kit.step(120)
	var ticks: Array = []
	for s: NetSession in kit.sessions:
		ticks.append(s.adapter().current_tick())
	t.check(int(ticks[0]) > 100, "ticks advanced: %s" % str(ticks))
	# identical chain and checksum at a common tick
	var chains: Dictionary = {}
	for s: NetSession in kit.sessions:
		var snap: Array = s.desync.snapshot(100)
		t.eq(snap.size(), 2)
		chains[str(snap)] = true
	t.eq(chains.size(), 1, "same checksum and chain on all peers")
	t.eq(h.config()["players"].size(), 3)
	t.eq(kit.sessions[1].local_pid, 1)
	kit.shutdown_all()


# ---- launch abort matrix ----------------------------------------------------------------------------------------

class SlowJob extends NetWorldJob:
	var fail_with: String = ""
	var _calls: int = 0

	func step(_budget_us: int) -> bool:
		_calls += 1
		if fail_with != "":
			_err = fail_with
			return true
		return false

	func progress_pct() -> int:
		return 10


func _lobby_ready(kit: NetSessionKit, n_clients: int, host_extra: Dictionary = {}, client_extra: Dictionary = {}) -> NetSession:
	var h: NetSession = kit.lobby_of(n_clients, host_extra, client_extra)
	for i: int in kit.sessions.size():
		var s: NetSession = kit.sessions[i]
		s.lobby.set_team(1 + i)
		if s != h:
			s.lobby.set_ready(true)
	kit.step(4)
	return h


func _abort_case(t: TestCtx, kit: NetSessionKit, h: NetSession, expect_reason: int) -> Array:
	var got: Array = []
	for s: NetSession in kit.sessions:
		s.launch_aborted.connect(func(reason: int, detail: String) -> void: got.append([reason, detail]))
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	t.check(kit.all_in(P.LOBBY, 400), "everybody is back in the lobby")
	t.check(got.size() >= 1 and int((got[0] as Array)[0]) == expect_reason, "abort reason %d, got %s" % [expect_reason, str(got)])
	t.eq(h.lobby.state.phase, NetProtocol.LobbyPhase.OPEN, "lobby unlocked")
	return got


func test_launch_abort_map_mismatch(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	kit.builders["P2"] = func(_cfg: Dictionary) -> NetWorldJob:
		return NetWorldJob.sync(func() -> NetSimAdapter: return NetSimAdapterFake.new(999))
	var h: NetSession = _lobby_ready(kit, 1)
	var got: Array = _abort_case(t, kit, h, NetProtocol.AbortReason.MAP_MISMATCH)
	t.check(str((got[0] as Array)[1]).contains("different map"))
	t.check(kit.log_errors.size() >= 1, "both hashes are logged at error")
	var c: NetSession = kit.sessions[1]
	t.eq(c.lobby.set_team(4), NetLobby.Result.OK, "unlocked on the client too")
	kit.shutdown_all()


func test_launch_abort_init_mismatch(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	kit.builders["P2"] = func(cfg: Dictionary) -> NetWorldJob:
		var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
		return NetWorldJob.sync(func() -> NetSimAdapter:
			var f: NetSimAdapterFake = NetSimAdapterFake.new(seed_v)
			f._state = 5
			return f)
	var h: NetSession = _lobby_ready(kit, 1)
	_abort_case(t, kit, h, NetProtocol.AbortReason.INIT_MISMATCH)
	kit.shutdown_all()


func test_launch_abort_human_left_and_timeout_and_failures(t: TestCtx) -> void:
	# human leaves while loading
	var kit: NetSessionKit = _new_kit()
	kit.builders["P2"] = func(_cfg: Dictionary) -> NetWorldJob: return SlowJob.new()
	var h: NetSession = _lobby_ready(kit, 2)
	var got: Array = []
	h.launch_aborted.connect(func(reason: int, detail: String) -> void: got.append([reason, detail]))
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	kit.step(4)
	t.eq(h.phase, P.LOADING)
	var slow: NetSession = kit.sessions[1]
	slow.leave()
	kit.step(6)
	t.eq(int((got[0] as Array)[0]), NetProtocol.AbortReason.HUMAN_LEFT)
	t.eq(h.phase, P.LOBBY)
	t.eq(kit.sessions[2].phase, P.LOBBY, "the other client is back in the lobby")
	t.eq(h.lobby.state.human_count(), 2)
	kit.shutdown_all()
	# silent client: LOAD_TIMEOUT after 120 s
	var kit2: NetSessionKit = _new_kit()
	kit2.builders["P2"] = func(_cfg: Dictionary) -> NetWorldJob: return SlowJob.new()
	var h2: NetSession = _lobby_ready(kit2, 1)
	var got2: Array = []
	h2.launch_aborted.connect(func(reason: int, detail: String) -> void: got2.append([reason, detail]))
	t.eq(h2.lobby.host_start(), NetLobby.StartError.OK)
	kit2.step(10)
	t.eq(h2.phase, P.LOADING)
	kit2.step(118, 1_000_000)
	t.eq(got2.size(), 0, "not yet at 118 s")
	kit2.step(5, 1_000_000)
	t.eq(int((got2[0] as Array)[0]), NetProtocol.AbortReason.LOAD_TIMEOUT)
	t.check(kit2.all_in(P.LOBBY, 20))
	kit2.shutdown_all()
	# a client whose world job fails
	var kit3: NetSessionKit = _new_kit()
	kit3.builders["P2"] = func(_cfg: Dictionary) -> NetWorldJob:
		var j: SlowJob = SlowJob.new()
		j.fail_with = "out of memory"
		return j
	var h3: NetSession = _lobby_ready(kit3, 1)
	var g3: Array = _abort_case(t, kit3, h3, NetProtocol.AbortReason.LOAD_FAILED)
	t.check(str((g3[0] as Array)[1]).contains("out of memory"))
	kit3.shutdown_all()
	# the host's own builder fails
	var kit4: NetSessionKit = _new_kit()
	kit4.builders["Host"] = func(_cfg: Dictionary) -> NetWorldJob:
		var j: SlowJob = SlowJob.new()
		j.fail_with = "no map"
		return j
	var h4: NetSession = _lobby_ready(kit4, 1)
	_abort_case(t, kit4, h4, NetProtocol.AbortReason.LOAD_FAILED)
	kit4.shutdown_all()


func test_launch_abort_config_invalid(t: TestCtx) -> void:
	# the client does not know the roster the host chose: it refuses the config
	var kit: NetSessionKit = _new_kit()
	var other: PackedStringArray = PackedStringArray()
	for id: String in NetSessionKit.roster_ids():
		other.append(id.replace("roster.", "other."))
	var h: NetSession = kit.lobby_of(1, {}, {"roster_ids": other})
	# roster ids differ, so pick tokens the client cannot resolve
	h.lobby.set_roster("roster.ae.a")
	kit.sessions[1].lobby.opts.roster_ids = NetSessionKit.roster_ids()
	kit.sessions[1].lobby.set_team(2)
	kit.sessions[1].lobby.set_ready(true)
	h.lobby.set_team(1)
	kit.step(4)
	kit.sessions[1].opts.roster_ids = other
	_abort_case(t, kit, h, NetProtocol.AbortReason.CONFIG_INVALID)
	kit.shutdown_all()


func test_launch_success_eight_players_with_ai(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	kit.ai_factory = func(pid: int, _level: int, _style: int, _seed: int) -> Callable:
		return func(_world: RefCounted, out: Array) -> void: out.append(PackedInt32Array([9, pid]))
	var h: NetSession = kit.host("Host")
	h.lobby.host_set_map(0, 128, 7, 8)
	for i: int in 4:
		kit.join("P%d" % (i + 2))
	kit.all_in(P.LOBBY, 100)
	for i: int in 3:
		h.lobby.host_set_slot_kind(5 + i, NetProtocol.SlotKind.AI)
	for i: int in kit.sessions.size():
		kit.sessions[i].lobby.set_team(1 + (i % 2))
		if i > 0:
			kit.sessions[i].lobby.set_ready(true)
	kit.step(4)
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	var progress: Array = []
	h.load_progress.connect(func(ps: PackedInt32Array, pcts: PackedInt32Array) -> void: progress.append([ps, pcts]))
	t.check(kit.all_in(P.PLAYING, 400), "8 players launched")
	kit.step(1300)
	var tick: int = kit.sessions[0].adapter().current_tick()
	t.check(tick > 1000, "60 s of play (%d ticks)" % tick)
	var common: int = tick
	for s0: NetSession in kit.sessions:
		common = mini(common, s0.adapter().current_tick())
	common = common / 20 * 20 - 20
	var ref: Array = h.desync.snapshot(common)
	t.eq(ref.size(), 2)
	for s: NetSession in kit.sessions:
		t.eq(s.desync.snapshot(common), ref, "identical (checksum, chain) on every peer")
		t.eq(s.phase, P.PLAYING)
	# AI commands travel in the bundles: pid 5 issued [9, 5] commands
	var found: bool = h.command_log().cmds.any(func(c: PackedInt32Array) -> bool: return c.size() == 2 and c[0] == 9 and c[1] == 5)
	t.check(found, "AI 5 commands were executed")
	var pids: Array = []
	for pv: Variant in h.config()["players"] as Array:
		pids.append(int((pv as Dictionary)["pid"]))
	t.eq(pids, [0, 1, 2, 3, 4, 5, 6, 7])
	kit.shutdown_all()


# ---- match control ----------------------------------------------------------------------------------------------

func test_pause_resume_speed_surrender_leave(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var h: NetSession = _launch(kit, 1, {"speed_pct_override": 0})
	h.lobby.host_start()
	t.check(kit.all_in(P.PLAYING, 200))
	var c: NetSession = kit.sessions[1]
	kit.step(30)
	var pauses: Array = []
	h.pause_changed.connect(func(p: bool, by: int) -> void: pauses.append([p, by]))
	c.pause_changed.connect(func(p: bool, by: int) -> void: pauses.append([p, by]))
	t.eq(c.request_pause(true), 0)
	kit.step(20)
	t.eq(h.phase, P.PAUSED)
	t.eq(c.phase, P.PAUSED)
	t.check(h.is_paused() and c.is_paused())
	var tk: int = h.adapter().current_tick()
	t.eq(c.adapter().current_tick(), tk, "same tick on both peers")
	kit.step(20)
	t.eq(h.adapter().current_tick(), tk, "no ticks while paused")
	t.eq(pauses.size(), 2)
	t.eq((pauses[0] as Array)[1], 1, "paused by pid 1")
	t.eq(c.request_pause(true), 0, "second request is answered by the host (ALREADY), the call itself is sent")
	kit.step(3)
	t.eq(h.phase, P.PAUSED)
	# only the pauser or the host resumes
	t.eq(h.request_pause(false), 0)
	kit.step(20)
	t.eq(h.phase, P.PLAYING)
	t.eq(c.phase, P.PLAYING)
	t.gt(h.adapter().current_tick(), tk)
	# speed change is a control record executed by everybody
	var speeds: Array = []
	c.speed_changed.connect(func(p: int) -> void: speeds.append(p))
	t.check(h.host_set_speed(150))
	t.check(not h.host_set_speed(111))
	t.check(not c.host_set_speed(150), "clients cannot change the speed")
	kit.step(20)
	t.eq(speeds, [150])
	# surrender: RESIGNED on every peer
	var stat: Array = []
	h.player_status_changed.connect(func(pid: int, st: int) -> void: stat.append([pid, st]))
	t.check(c.surrender())
	kit.step(30)
	t.eq(h.player_status(1), NetProtocol.PlayerNetStatus.RESIGNED)
	t.eq(c.player_status(1), NetProtocol.PlayerNetStatus.RESIGNED)
	t.check((h.adapter() as NetSimAdapterFake).resigned(1))
	t.check(not c.submit_command(PackedInt32Array()), "empty command refused")
	# a clean leave: host sees LEFT, the leaver goes IDLE
	c.leave()
	t.eq(c.phase, P.IDLE)
	kit.step(30)
	t.eq(h.player_status(1), NetProtocol.PlayerNetStatus.LEFT)
	t.eq(h.phase, P.PLAYING, "the match goes on for the others")
	kit.shutdown_all()


func test_drop_resign_and_ai_takeover(t: TestCtx) -> void:
	for mode: int in [NetProtocol.StallAction.STALL_DROP_RESIGN, NetProtocol.StallAction.STALL_DROP_AI]:
		var kit: NetSessionKit = _new_kit()
		kit.ai_factory = func(pid: int, _level: int, _style: int, _seed: int) -> Callable:
			return func(_world: RefCounted, out: Array) -> void: out.append(PackedInt32Array([9, pid]))
		var h: NetSession = _launch(kit, 2)
		h.lobby.host_start()
		t.check(kit.all_in(P.PLAYING, 200))
		kit.step(60)
		var prompts: Array = []
		h.stall_prompt.connect(func(pids: PackedInt32Array) -> void: prompts.append(pids))
		# client 1 (pid 1) freezes: stop polling it
		var frozen: NetSession = kit.sessions[1]
		kit.sessions.erase(frozen)
		kit.step(200)
		t.check(h.waiting_list().size() >= 1 and int(h.waiting_list()[0]["pid"]) == 1, "host waits for pid 1")
		kit.step(200, 50_000)
		t.check(prompts.size() >= 1, "prompt after 8 s")
		var status: Array = []
		h.player_status_changed.connect(func(pid: int, st: int) -> void: status.append([pid, st]))
		h.host_resolve_stall(1, mode)
		kit.step(80)
		t.eq(h.phase, P.PLAYING)
		var expect: int = NetProtocol.PlayerNetStatus.AI_TAKEOVER if mode == NetProtocol.StallAction.STALL_DROP_AI else NetProtocol.PlayerNetStatus.DROPPED
		t.eq(h.player_status(1), expect)
		t.eq(kit.sessions[1].player_status(1), expect, "all peers agree")
		if mode == NetProtocol.StallAction.STALL_DROP_AI:
			t.check(h.command_log().cmds.any(func(c: PackedInt32Array) -> bool: return c.size() == 2 and c[0] == 9 and c[1] == 1), "AI commands for pid 1")
		else:
			var first_resign: bool = false
			for i: int in h.command_log().cmds.size():
				var c: PackedInt32Array = h.command_log().cmds[i]
				if h.command_log().pids[i] == 1 and c[0] == NetProtocol.T_RESIGN:
					first_resign = true
			t.check(first_resign, "T_RESIGN injected for pid 1")
			t.check(not h.adapter().is_player_active(1))
		frozen.shutdown()
		kit.shutdown_all()


func test_host_quit_and_kicked_states(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var h: NetSession = _launch(kit, 1)
	h.lobby.host_start()
	t.check(kit.all_in(P.PLAYING, 200))
	var c: NetSession = kit.sessions[1]
	var got: Array = []
	var ended: Array = []
	c.kicked.connect(func(reason: int, _d: String) -> void: got.append(reason))
	c.match_ended.connect(func(res: Dictionary) -> void: ended.append(res))
	kit.step(20)
	h.shutdown()
	t.eq(h.phase, P.IDLE)
	h.shutdown()
	kit.step(10)
	t.eq(c.phase, P.DISCONNECTED)
	t.eq(got, [NetProtocol.KickReason.HOST_LEFT])
	t.eq(int((ended[0] as Dictionary)["reason"]), NetProtocol.MatchEndReason.ABANDONED)
	t.eq(NetProtocol.describe_kick(NetProtocol.KickReason.HOST_LEFT, ""), "The host left the game.")
	kit.shutdown_all()


func test_deferred_shutdown_from_a_handler(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var h: NetSession = kit.host("Host")
	var c: NetSession = kit.join("Bob")
	var calls: PackedInt32Array = PackedInt32Array([0])
	var handler: Callable = func(p: int, _prev: int) -> void:
		if p == P.LOBBY:
			calls[0] += 1
			c.leave()
			t.eq(c.phase, P.LOBBY, "leave() inside a handler is deferred")
	c.phase_changed.connect(handler)
	kit.step(10)
	t.eq(calls[0], 1)
	t.eq(c.phase, P.IDLE, "executed at the end of the poll")
	c.phase_changed.disconnect(handler)
	kit.step(3)
	t.eq(h.lobby.state.human_count(), 1)
	kit.shutdown_all()


func test_return_to_lobby_and_second_match(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	kit.builders["Host"] = func(cfg: Dictionary) -> NetWorldJob:
		var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
		return NetWorldJob.sync(func() -> NetSimAdapter: return NetSimAdapterFake.new(seed_v, 200))
	kit.builders["P2"] = kit.builders["Host"]
	var h: NetSession = _launch(kit, 1)
	var ended: Array = []
	for s: NetSession in kit.sessions:
		s.match_ended.connect(func(res: Dictionary) -> void: ended.append(res))
	h.lobby.host_start()
	t.check(kit.all_in(P.PLAYING, 200))
	t.check(kit.all_in(P.ENDED, 600), "the fake sim ends at tick 200")
	t.eq(ended.size(), 2)
	t.eq(int((ended[0] as Dictionary)["reason"]), NetProtocol.MatchEndReason.SIM_DECIDED)
	t.eq(int((ended[0] as Dictionary)["final_tick"]), 200)
	t.eq(int((ended[0] as Dictionary)["final_checksum"]), int((ended[1] as Dictionary)["final_checksum"]))
	t.check(h.world() != null, "the world stays readable after the end")
	h.host_return_to_lobby()
	t.check(kit.all_in(P.LOBBY, 50))
	t.check(not h.lobby.state.slots[1].ready, "ready flags are reset")
	kit.sessions[1].lobby.set_ready(true)
	kit.step(4)
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	t.check(kit.all_in(P.PLAYING, 200), "a second match starts")
	kit.shutdown_all()


func test_return_to_lobby_that_arrives_before_the_clients_own_end(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	kit.builders["Host"] = func(cfg: Dictionary) -> NetWorldJob:
		var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
		return NetWorldJob.sync(func() -> NetSimAdapter: return NetSimAdapterFake.new(seed_v, 200))
	kit.builders["P2"] = kit.builders["Host"]
	var h: NetSession = _launch(kit, 1)
	h.lobby.host_start()
	t.check(kit.all_in(P.PLAYING, 200))
	var c: NetSession = kit.sessions[1]
	# the host's RETURN_TO_LOBBY overtakes the client's own lockstep: it is queued, not dropped, and applied at the client's end
	var ev: NetTransportEvent = NetTransportEvent.new()
	ev.peer_id = 1
	ev.channel = NetProtocol.msg_channel(NetProtocol.Msg.RETURN_TO_LOBBY)
	ev.data = NetLobbyCodec.encode_return_to_lobby()
	c._client_packet(ev, 0)
	t.eq(c.phase, P.PLAYING, "still playing")
	t.check(c._return_pending, "the return is remembered")
	t.check(kit.all_in(P.ENDED, 600) or c.phase == P.LOBBY, "the fake sim ends")
	kit.step(4)
	t.eq(c.phase, P.LOBBY, "the client goes back to the lobby once its own match ended")
	t.check(not c._return_pending)
	kit.shutdown_all()


func test_submit_command_legality_and_stats(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var h: NetSession = kit.lobby_of(1)
	t.check(not h.submit_command(PackedInt32Array([1, 2])), "not playing yet")
	t.eq(h.request_pause(true), NetProtocol.PauseError.NOT_PLAYING)
	t.check(not h.host_set_speed(100))
	var s0: Dictionary = h.stats()
	for key: String in ["role", "phase", "tick", "turn", "delay_turns", "speed_pct", "rtt_ms", "jitter_ms", "stall_ms", "stall_count", "slack_ms",
			"bundles_buffered", "kbps_in", "kbps_out", "pkts_in", "pkts_out", "load_pct", "dropped_cmds", "violations", "dup_in", "late_in", "ooo_in",
			"ai_us", "chain", "last_checksum_tick", "transport"]:
		t.check(s0.has(key), "stats has " + key)
	kit.shutdown_all()


# ---- LOCAL (single-player) path ---------------------------------------------------------------------------------

func _local_config(humans: int = 1) -> Dictionary:
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.ae.a")
	st.map_size = 96
	st.layout_players = 2
	if humans == 0:
		st.slots[0].kind = NetProtocol.SlotKind.AI
		st.slots[0].peer_id = 0
		st.slots[0].name = "AI 1"
		st.slots[0].ready = true
	var raw: Dictionary = NetMatchConfig.from_lobby(st, 777, {"game": "0", "proto": 1, "sim": 1, "data_hash": NetSessionKit.DATA_HASH, "data_format": 0, "data_ids": 0},
		1_790_000_000, NetSessionKit.roster_ids())
	return NetMatchConfig.parse(NetMatchConfig.canonical_json(raw))


func _local_options(kit: NetSessionKit, end_tick: int = -1, extra: Dictionary = {}) -> NetSessionOptions:
	var o: NetSessionOptions = kit.options("Me", extra)
	o.fixed_input_delay_turns = 0
	o.world_builder = func(cfg: Dictionary) -> NetWorldJob:
		var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
		return NetWorldJob.sync(func() -> NetSimAdapter: return NetSimAdapterFake.new(seed_v, end_tick))
	return o


func test_local_unpaced_runs_the_multiplayer_pipeline(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	kit.ai_factory = func(pid: int, _l: int, _s: int, _seed: int) -> Callable:
		return func(_w: RefCounted, out: Array) -> void: out.append(PackedInt32Array([9, pid]))
	var s: NetSession = NetSession.local_from_config(_local_options(kit, 300, {"ai_factory": kit.ai_factory}), _local_config())
	t.not_null(s)
	t.eq(s.role, NetSession.Role.LOCAL)
	t.eq(s.phase, P.LOADING)
	t.is_null(s.transport, "no transport object exists in single player")
	t.is_null(s.discovery)
	var phases: Array = []
	var started: PackedInt32Array = PackedInt32Array([0])
	var ended: Array = []
	s.phase_changed.connect(func(p: int, _prev: int) -> void: phases.append(p))
	s.match_started.connect(func() -> void: started[0] += 1)
	s.match_ended.connect(func(r: Dictionary) -> void: ended.append(r))
	var per_poll: PackedInt32Array = PackedInt32Array()
	for _i: int in 200:
		kit.clock().advance_us(50_000)
		per_poll.append(s.poll())
		if s.phase == P.ENDED:
			break
	t.eq(phases, [P.PLAYING, P.ENDED])
	t.eq(started[0], 1)
	t.eq(int((ended[0] as Dictionary)["final_tick"]), 300)
	t.eq(s.lockstep.delay_turns(), NetProtocol.D_MIN_LOCAL, "local input delay is 1 turn")
	t.eq(s.local_pid, 0)
	t.le(per_poll.size(), 60, "unpaced: many ticks per poll (%d polls)" % per_poll.size())
	t.check(s.command_log().cmds.any(func(c: PackedInt32Array) -> bool: return c.size() == 2 and c[0] == 9 and c[1] == 1), "AI commands were executed")
	# the local player's commands go through the same input path
	var s2: NetSession = NetSession.local_from_config(_local_options(kit, -1), _local_config())
	kit.step(1)
	for _i: int in 5:
		s2.poll()
	t.check(s2.submit_command(PackedInt32Array([5, 6, 7])))
	for _i: int in 6:
		s2.poll()
	t.check(s2.command_log().cmds.any(func(c: PackedInt32Array) -> bool: return c.size() == 3 and c[0] == 5))
	t.check(s2.surrender())
	for _i: int in 6:
		s2.poll()
	t.eq(s2.player_status(0), NetProtocol.PlayerNetStatus.RESIGNED)
	s.shutdown()
	s2.shutdown()


func test_local_paced_follows_the_clock_speed_and_pause(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var s: NetSession = NetSession.local_from_config(_local_options(kit, -1, {"speed_pct_override": -1, "max_ticks_per_poll": 8}), _local_config())
	kit.clock().advance_us(1000)
	s.poll()
	t.eq(s.phase, P.PLAYING)
	var t0: int = s.adapter().current_tick()
	for _i: int in 40:
		kit.clock().advance_us(50_000)
		s.poll()
	var gained: int = s.adapter().current_tick() - t0
	t.check(gained >= 36 and gained <= 40, "100 %%: about one tick per 50 ms (%d)" % gained)
	t.check(s.host_set_speed(200))
	for _i: int in 6:
		kit.clock().advance_us(50_000)
		s.poll()
	var t1: int = s.adapter().current_tick()
	for _i: int in 20:
		kit.clock().advance_us(50_000)
		s.poll()
	var fast: int = s.adapter().current_tick() - t1
	t.check(fast >= 36 and fast <= 42, "200 %%: two ticks per 50 ms (%d)" % fast)
	t.eq(s.request_pause(true), 0, "pause is always allowed in single player")
	for _i: int in 6:
		kit.clock().advance_us(50_000)
		s.poll()
	t.eq(s.phase, P.PAUSED)
	var frozen: int = s.adapter().current_tick()
	for _i: int in 10:
		kit.clock().advance_us(50_000)
		s.poll()
	t.eq(s.adapter().current_tick(), frozen)
	t.eq(s.request_pause(false), 0)
	for _i: int in 6:
		kit.clock().advance_us(50_000)
		s.poll()
	t.eq(s.phase, P.PLAYING)
	t.gt(s.adapter().current_tick(), frozen)
	s.shutdown()


func test_local_from_a_lobby_and_start_errors(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var o: NetSessionOptions = _local_options(kit, 100)
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.ae.a")
	# no AI factory: the shared start validation refuses
	var none: NetSession = NetSession.local(o, st)
	t.is_null(none)
	t.eq(NetSession.last_create_error, NetLobby.start_error_text(NetLobby.StartError.AI_UNAVAILABLE))
	o.ai_factory = func(pid: int, _l: int, _s: int, _seed: int) -> Callable:
		return func(_w: RefCounted, out: Array) -> void: out.append(PackedInt32Array([9, pid]))
	var s: NetSession = NetSession.local(o, st)
	t.not_null(s)
	var pcts: Array = []
	s.load_progress.connect(func(pids: PackedInt32Array, p: PackedInt32Array) -> void: pcts.append([pids, p]))
	t.eq(s.phase, P.LOADING)
	for _i: int in 100:
		kit.clock().advance_us(50_000)
		s.poll()
		if s.phase == P.ENDED:
			break
	t.eq(s.phase, P.ENDED)
	t.check(pcts.size() >= 1 and (pcts.back() as Array)[1][0] == 100, "load_progress reaches 100")
	t.eq(s.lobby.local_slot(), 0)
	# bad options
	var bad: NetSessionOptions = NetSessionOptions.new()
	t.is_null(NetSession.local(bad, st))
	t.check(NetSession.last_create_error.contains("world_builder"))
	bad.world_builder = o.world_builder
	t.is_null(NetSession.host(bad))
	t.check(NetSession.last_create_error.contains("32"), NetSession.last_create_error)
	# a launch abort in single player ends the session (config that fails validation)
	var solo: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.ae.a")
	solo.slots[1].kind = NetProtocol.SlotKind.CLOSED
	t.is_null(NetSession.local(o, solo))
	t.eq(NetSession.last_create_error, NetLobby.start_error_text(NetLobby.StartError.NOT_ENOUGH_PLAYERS))
	s.shutdown()


func test_local_launch_failure_returns_to_idle(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var o: NetSessionOptions = _local_options(kit)
	o.world_builder = func(_cfg: Dictionary) -> NetWorldJob:
		var j: SlowJob = SlowJob.new()
		j.fail_with = "disk full"
		return j
	var s: NetSession = NetSession.local_from_config(o, _local_config())
	var got: Array = []
	s.launch_aborted.connect(func(reason: int, detail: String) -> void: got.append([reason, detail]))
	kit.clock().advance_us(50_000)
	s.poll()
	t.eq(int((got[0] as Array)[0]), NetProtocol.AbortReason.LOAD_FAILED)
	t.check(str((got[0] as Array)[1]).contains("disk full"))
	t.eq(s.phase, P.IDLE)
	s.shutdown()


# ---- real simulation: LOCAL == direct sim -----------------------------------------------------------------------

func _real_options(kit: NetSessionKit) -> NetSessionOptions:
	var data: GameData = SimMatchKit.data()
	var o: NetSessionOptions = NetSessionOptions.from_game_data(data)
	o.clock = kit.clock()
	o.speed_pct_override = 0
	o.max_ticks_per_poll = 64
	o.fixed_input_delay_turns = 0
	o.discovery_enabled = false
	o.replay_dir = ""
	o.world_builder = NetSessionKit.real_job
	o.ai_factory = NetSessionKit.bot_factory({"first_attack_tick": 400, "interval": 1})
	o.log_sink = func(_l: int, _t: String) -> void: pass
	return o


func _real_config(o: NetSessionOptions) -> Dictionary:
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.napc.vanilla", o)
	st.map_size = 96
	st.layout_players = 2
	st.slots[0].kind = NetProtocol.SlotKind.AI
	st.slots[0].peer_id = 0
	st.slots[0].name = "AI 1"
	st.slots[0].ready = true
	st.slots[0].ai_level = 1
	st.slots[1].roster_id = "roster.nec.vanilla"
	st.rules["fog"] = 0
	var ver: Dictionary = {"game": o.game_version, "proto": 1, "sim": o.sim_version, "data_hash": o.data_hash, "data_format": 1,
		"data_ids": int(SimMatchKit.data().table_hashes.get("ids", 0))}
	var raw: Dictionary = NetMatchConfig.from_lobby(st, 20260930, ver, 1_790_000_000, o.roster_ids)
	return NetMatchConfig.parse(NetMatchConfig.canonical_json(raw))


func test_local_matches_the_direct_sim_and_replays(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var o: NetSessionOptions = _real_options(kit)
	var cfg: Dictionary = _real_config(o)
	t.check(not cfg.is_empty(), "real config")
	var s: NetSession = NetSession.local_from_config(o, cfg)
	t.not_null(s)
	if s == null:
		t.note(NetSession.last_create_error)
		return
	var checks: Dictionary = {}
	s.checksum_observer = func(tick: int, cs: int, _chain: int) -> void: checks[tick] = cs
	var guard: int = 0
	while s.phase != P.ENDED and s.adapter() == null or (s.adapter() != null and s.adapter().current_tick() < 1500 and s.phase != P.ENDED):
		kit.clock().advance_us(50_000)
		s.poll()
		guard += 1
		if guard > 4000:
			break
	var ticks: int = s.adapter().current_tick()
	t.ge(ticks, 1500)
	t.check(s.command_log().cmds.size() > 10, "the bots issued commands through the bundles (%d)" % s.command_log().cmds.size())
	# a fresh direct sim driven only by the recorded command log reproduces every checksum
	var job: NetWorldJob = NetSessionKit.real_job(s.config())
	job.step(1_000_000)
	var direct: SimWorld = job.take_adapter().world() as SimWorld
	var res: Dictionary = s.command_log().play(direct, ticks)
	t.check(bool(res["ok"]), "SimCommandLog replay matches every 20-tick checksum: %s" % str(res))
	t.eq(int(res["final"]), s.adapter().checksum_now(), "final checksum equals the direct sim")
	t.check(direct.checksum_at(1000) == int(checks[1000]))
	# the same through NetSelfTest.run_double (AI included)
	var r: Dictionary = NetSelfTest.run_double(cfg, NetSessionKit.real_job, [], 1000, o.ai_factory)
	t.check(bool(r["ok"]), str(r))
	t.gt(int(r["compared"]), 40)
	s.shutdown()


# ---- discovery integration, pre-START buffer, real ENet -----------------------------------------------------------

func test_host_announces_and_a_browser_lists_it(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var port: int = 28700 + OS.get_process_id() % 200
	var extra: Dictionary = {"discovery_enabled": true, "discovery_port": port, "discovery_targets": PackedStringArray(["127.0.0.1"])}
	var o: NetSessionOptions = kit.options("Host", extra)
	var browser: NetDiscovery = NetSession.create_browser(o)
	if browser.start_browse() != OK:
		t.skip("discovery test port %d is busy" % port)
		return
	var h: NetSession = NetSession.host(o, "Fun game")
	kit.add(h)
	t.not_null(h.discovery)
	var seen: Array[NetDiscoveryEntry] = []
	var deadline: int = Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline and seen.is_empty():
		kit.step(1, 1_100_000)
		browser.poll()
		seen = browser.entries()
		OS.delay_msec(5)
	t.eq(seen.size(), 1)
	if seen.size() == 1:
		t.eq(seen[0].host_name, "Fun game")
		t.eq(seen[0].session_id, h.lobby.state.session_id)
		t.eq(seen[0].slots_total, 4)
		t.eq(seen[0].slots_free, 3)
		t.eq(seen[0].humans, 1)
		t.check(seen[0].compatible)
	h.shutdown()
	deadline = Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline and not browser.entries().is_empty():
		browser.poll()
		OS.delay_msec(5)
	t.eq(browser.entries().size(), 0, "shutdown announces CLOSED")
	browser.close()
	kit.shutdown_all()


func test_prestart_bundles_are_buffered_until_start(t: TestCtx) -> void:
	var sim: NetSimAdapterFake = NetSimAdapterFake.new(1)
	var clock: NetClock = NetClock.manual(1_000_000)
	var ls: NetLockstep = NetLockstep.new()
	ls.setup(sim, clock, -1, 2, 100)
	var cg: NetClientGame = NetClientGame.new()
	cg.emit_error = func(_c: int, _t: String) -> void: pass
	cg.log_fn = func(_l: int, _t: String) -> void: pass
	# START not seen yet: bundles 2, 3 arrive first and wait
	for turn: int in [2, 3]:
		cg.handle_bundle(NetBundle.build(turn, PackedInt32Array(), [], []).wire_bytes(), true)
	t.eq(ls.stats()["queued"], 0)
	cg.lockstep = ls
	ls.start()
	cg.drain_prestart()
	t.eq(ls.stats()["next_push"], 4, "buffered bundles were pushed in order after START")
	# a corrupt bundle is reported, never fatal
	var errs: PackedInt32Array = PackedInt32Array([0])
	cg.emit_error = func(_c: int, _t: String) -> void: errs[0] += 1
	var bad: PackedByteArray = NetBundle.build(4, PackedInt32Array(), [], []).wire_bytes()
	bad[bad.size() - 1] ^= 0xFF
	cg.handle_bundle(bad, false)
	t.eq(errs[0], 1)
	# the 64-bundle cap
	var cg2: NetClientGame = NetClientGame.new()
	cg2.log_fn = func(_l: int, _t: String) -> void: pass
	for turn: int in 100:
		cg2.handle_bundle(NetBundle.build(turn, PackedInt32Array(), [], []).wire_bytes(), true)
	cg2.lockstep = ls
	cg2.drain_prestart()


func test_real_enet_session_join_launch_and_play(t: TestCtx) -> void:
	var port: int = 28900 + OS.get_process_id() % 90
	var mk: Callable = func(name: String) -> NetSessionOptions:
		var o: NetSessionOptions = NetSessionOptions.new()
		o.player_name = name
		o.sim_version = 1
		o.data_hash = NetSessionKit.DATA_HASH
		o.roster_ids = NetSessionKit.roster_ids()
		o.discovery_enabled = false
		o.port = port
		o.speed_pct_override = 200
		o.countdown_s = 0
		o.fixed_input_delay_turns = 2
		o.desync_dir = "user://desync_enet_test"
		o.world_builder = NetSessionKit.fake_job
		o.log_sink = func(_l: int, _t: String) -> void: pass
		return o
	var h: NetSession = NetSession.host(mk.call("Host") as NetSessionOptions, "ENet game")
	if h == null:
		t.skip("no free port: " + NetSession.last_create_error)
		return
	var c: NetSession = NetSession.join(mk.call("Bob") as NetSessionOptions, "127.0.0.1", h.transport.local_port())
	t.not_null(c)
	var pump: Callable = func(pred: Callable, ms: int) -> bool:
		var end_ms: int = Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < end_ms:
			h.poll()
			c.poll()
			if pred.call():
				return true
			OS.delay_msec(1)
		return false
	t.check(pump.call(func() -> bool: return c.phase == P.LOBBY, 4000), "joined over real ENet")
	c.lobby.set_team(2)
	c.lobby.set_ready(true)
	h.lobby.set_team(1)
	pump.call(func() -> bool: return h.lobby.state.slots[1].ready, 1000)
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	t.check(pump.call(func() -> bool: return h.phase == P.PLAYING and c.phase == P.PLAYING, 4000), "both playing")
	t.check(pump.call(func() -> bool: return h.adapter().current_tick() >= 100 and c.adapter().current_tick() >= 100, 8000), "100 ticks over ENet at 200 %")
	var common: int = mini(h.adapter().current_tick(), c.adapter().current_tick()) / 20 * 20 - 20
	t.ge(common, 60)
	t.eq(h.desync.snapshot(common), c.desync.snapshot(common), "identical checksum + chain over real ENet")
	c.leave()
	t.eq(c.phase, P.IDLE)
	pump.call(func() -> bool: return h.player_status(1) == NetProtocol.PlayerNetStatus.LEFT, 4000)
	t.eq(h.player_status(1), NetProtocol.PlayerNetStatus.LEFT)
	h.shutdown()
	t.eq(h.phase, P.IDLE)


# ---- poll order, phase legality, transport loss, dedicated host -----------------------------------------------------

## Transport that logs the order of poll / send / flush; the probe adapter logs step().
class ProbeTransport extends NetTransportLoopback:
	var trace: Array = []

	func poll() -> void:
		trace.append("poll")
		super.poll()

	func flush() -> void:
		trace.append("flush")
		super.flush()

	func send(peer_id: int, channel: int, data: PackedByteArray) -> int:
		trace.append("send%02X" % data[0])
		return super.send(peer_id, channel, data)


class ProbeAdapter extends NetSimAdapterFake:
	var trace: Array = []

	func step() -> void:
		trace.append("step")
		super.step()


class ProbeJob extends NetWorldJob:
	var trace: Array = []
	var n: int = 0
	var adapter_out: NetSimAdapter = null

	func step(_budget_us: int) -> bool:
		trace.append("job")
		n += 1
		if n >= 2:
			_adapter = adapter_out
			_done = true
			return true
		return false

	func progress_pct() -> int:
		return 50


func test_poll_runs_in_the_documented_order(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var probe: ProbeTransport = ProbeTransport.new(kit.hub)
	var shared: Array = probe.trace
	var host_opts: Dictionary = {"transport_factory": func() -> NetTransport:
		probe.address = "10.0.0.1"
		return probe}
	var h: NetSession = kit.host("Host", host_opts)
	var c: NetSession = kit.join("Bob")
	kit.all_in(P.LOBBY, 30)
	c.lobby.set_team(2)
	c.lobby.set_ready(true)
	h.lobby.set_team(1)
	kit.step(3)
	# LOADING: transport.poll -> launch step (world job) -> ... -> flush
	kit.builders["Host"] = func(cfg: Dictionary) -> NetWorldJob:
		var pa: ProbeAdapter = ProbeAdapter.new(int((cfg["map"] as Dictionary)["seed"]))
		pa.trace = shared
		var job: ProbeJob = ProbeJob.new()
		job.trace = shared
		job.adapter_out = pa
		return job
	h.lobby.host_start()
	shared.clear()
	kit.hub.clock.advance_us(50_000)
	h.poll()
	t.eq(shared[0], "poll", "transport.poll first")
	t.eq(shared.back(), "flush", "transport.flush last: packets created this frame leave this frame")
	t.check(shared.find("job") > shared.find("poll"), "the world job is sliced after the transport was serviced")
	kit.all_in(P.PLAYING, 100)
	# PLAYING: poll -> (bundle send) -> step ... -> flush
	kit.step(10)
	shared.clear()
	kit.step(1)
	t.eq(shared[0], "poll")
	t.eq(shared.back(), "flush")
	var first_step: int = shared.find("step")
	t.check(first_step > 0, "lockstep update runs after the transport events: %s" % str(shared.slice(0, 12)))
	var last_send: int = shared.rfind("send21")
	t.check(last_send < 0 or last_send < shared.rfind("flush"), "bundles are sent before the flush")
	kit.shutdown_all()


func test_illegal_phase_transition_is_ignored(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var h: NetSession = kit.host("Host")
	var errs: Array = []
	h.net_error.connect(func(code: int, _text: String) -> void: errs.append(code))
	h._set_phase(P.PLAYING)
	t.eq(h.phase, P.LOBBY, "PLAYING -> from LOBBY without a launch is illegal")
	t.eq(errs, [NetProtocol.NetErrorCode.TRANSPORT])
	h._set_phase(P.COUNTDOWN)
	t.eq(h.phase, P.COUNTDOWN)
	kit.shutdown_all()


func test_transport_loss_drops_the_player_after_five_seconds(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	var h: NetSession = _launch(kit, 1)
	h.lobby.host_start()
	t.check(kit.all_in(P.PLAYING, 200))
	kit.step(40)
	var c: NetSession = kit.sessions[1]
	var stat: Array = []
	h.player_status_changed.connect(func(pid: int, st: int) -> void: stat.append([pid, st]))
	c.transport.disconnect_peer(1, 0, false)
	kit.sessions.erase(c)
	kit.step(30)
	t.eq(h.player_status(1), NetProtocol.PlayerNetStatus.DISCONNECTED)
	t.check(h.waiting_list().size() >= 1 and int(h.waiting_list()[0]["reason"]) == NetProtocol.StallReason.DISCONNECTED)
	kit.step(140)
	t.eq(h.player_status(1), NetProtocol.PlayerNetStatus.DROPPED, "auto drop after DISCONNECT_ACT_MS")
	var ticks: int = h.adapter().current_tick()
	kit.step(60)
	t.gt(h.adapter().current_tick(), ticks, "the match goes on")
	c.shutdown()
	kit.shutdown_all()


func test_dedicated_host_ends_the_match_when_no_human_is_left(t: TestCtx) -> void:
	var kit: NetSessionKit = _new_kit()
	kit.ai_factory = func(pid: int, _l: int, _s: int, _seed: int) -> Callable:
		return func(_w: RefCounted, out: Array) -> void: out.append(PackedInt32Array([9, pid]))
	var h: NetSession = kit.host("Srv", {"dedicated": true})
	var c: NetSession = kit.join("Bob")
	kit.all_in(P.LOBBY, 50)
	t.eq(h.lobby.state.slots[0].name, "Bob", "a dedicated host has no player of its own")
	h.lobby.host_set_slot_kind(1, NetProtocol.SlotKind.AI)
	c.lobby.set_team(1)
	c.lobby.set_ready(true)
	kit.step(4)
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	t.check(kit.all_in(P.PLAYING, 200))
	t.eq(h.local_pid, -1)
	t.check(not h.submit_command(PackedInt32Array([1])), "a dedicated host has no input")
	kit.step(60)
	var ended: Array = []
	h.match_ended.connect(func(r: Dictionary) -> void: ended.append(r))
	c.leave()
	kit.step(80)
	t.eq(h.phase, P.ENDED)
	t.eq(int((ended[0] as Dictionary)["reason"]), NetProtocol.MatchEndReason.NO_HUMANS_LEFT)
	kit.shutdown_all()
