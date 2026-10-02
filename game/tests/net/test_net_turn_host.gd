extends RefCounted
## NET-4: NetTurnHost (spec 5.5.4-5.5.10, test plan 10.3 "test_net_turn_host.gd").

const P_NONE: int = 0
const P_HUMAN: int = 1
const P_AI: int = 2


## roles[i]: P_NONE / P_HUMAN (transport peer id i + 1; pid 0 is the host's own player) / P_AI. Returns [host, clock].
func _host(roles: Array, cfg: Dictionary = {}) -> Array:
	var clock: NetClock = NetClock.manual(10_000_000)
	var h: NetTurnHost = NetTurnHost.new()
	var c: Dictionary = {"initial_delay": 2, "fixed_delay": 2}
	c.merge(cfg, true)
	h.setup(clock, c)
	for i: int in roles.size():
		match int(roles[i]):
			P_HUMAN:
				h.set_player(i, NetProtocol.PlayerRole.PR_HUMAN, i + 1)
			P_AI:
				h.set_player(i, NetProtocol.PlayerRole.PR_AI, 0)
	return [h, clock]


static func _c(a: Array) -> PackedInt32Array:
	return PackedInt32Array(a)


func test_input_result_table(t: TestCtx) -> void:
	var h: NetTurnHost = _host([P_HUMAN, P_HUMAN, P_NONE])[0]
	t.eq(h.next_close_turn(), 2)
	t.eq(h.recv_through(0), 1, "pre-roll: received through D0-1")
	t.eq(h.recv_through(2), -1)
	t.eq(h.on_input(0, 2, 0, []), NetTurnHost.InputResult.OK)
	t.eq(h.recv_through(0), 2)
	t.eq(h.on_input(0, 2, 0, []), NetTurnHost.InputResult.DUPLICATE)
	t.eq(h.on_input(0, 1, 0, []), NetTurnHost.InputResult.DUPLICATE, "pre-roll turns are duplicates")
	t.eq(h.on_input(0, 4, 0, [_c([1])]), NetTurnHost.InputResult.BUFFERED)
	t.eq(h.recv_through(0), 2, "barrier still needs contiguity")
	t.eq(h.on_input(0, 4, 0, []), NetTurnHost.InputResult.DUPLICATE, "a second copy of a buffered turn")
	t.eq(h.on_input(0, 3, 0, []), NetTurnHost.InputResult.OK)
	t.eq(h.recv_through(0), 4, "buffered successors drained")
	# TOO_FAR beyond next_close + INPUT_LOOKAHEAD (= D_MAX + 2)
	var nc: int = h.next_close_turn()
	t.eq(h.on_input(1, nc + NetProtocol.D_MAX + 3, 0, []), NetTurnHost.InputResult.TOO_FAR)
	t.eq(h.on_input(1, nc + NetProtocol.D_MAX + 2, 0, []), NetTurnHost.InputResult.BUFFERED)
	# not a human / unseated
	t.eq(h.on_input(2, 2, 0, []), NetTurnHost.InputResult.WRONG_PLAYER)
	t.eq(h.on_input(7, 2, 0, []), NetTurnHost.InputResult.WRONG_PLAYER)
	t.eq(h.on_input(-1, 2, 0, []), NetTurnHost.InputResult.WRONG_PLAYER)
	# LATE (white box: a turn already closed that the player never delivered)
	h._recv_through[1] = 1
	h._next_close = 6
	t.eq(h.on_input(1, 3, 0, []), NetTurnHost.InputResult.LATE)
	h._next_close = 2


func test_too_big_substitutes_an_empty_input(t: TestCtx) -> void:
	var h: NetTurnHost = _host([P_HUMAN, P_HUMAN])[0]
	var many: Array = []
	for i: int in 65:
		many.append(_c([1, i]))
	t.eq(h.on_input(1, 2, 0, many), NetTurnHost.InputResult.TOO_BIG)
	t.eq(h.recv_through(1), 2, "the turn counts as empty: I1 is kept")
	t.eq(h.on_input(1, 3, 0, [PackedInt32Array()]), NetTurnHost.InputResult.TOO_BIG, "empty command")
	t.eq(h.on_input(1, 4, 0, [_c([256])]), NetTurnHost.InputResult.TOO_BIG, "type outside 0..255")
	var huge: PackedInt32Array = PackedInt32Array()
	huge.resize(1025)
	t.eq(h.on_input(1, 5, 0, [huge]), NetTurnHost.InputResult.TOO_BIG)
	t.eq(h.recv_through(1), 5)
	t.eq(h.on_input(1, 6, 0, ["not a command"]), NetTurnHost.InputResult.TOO_BIG)
	# body undecodable but the header was: on_bad_input
	t.eq(h.on_bad_input(1, 7), NetTurnHost.InputResult.TOO_BIG)
	t.eq(h.recv_through(1), 7)
	t.eq(h.on_bad_input(1, 7), NetTurnHost.InputResult.TOO_BIG, "repeat is harmless")
	t.eq(h.on_bad_input(3, 7), NetTurnHost.InputResult.WRONG_PLAYER)
	t.eq(h.stats()["too_big_in"], 7)


func test_barrier_blocks_on_slowest_and_orders_groups(t: TestCtx) -> void:
	var r: Array = _host([P_HUMAN, P_HUMAN, P_HUMAN])
	var h: NetTurnHost = r[0]
	h.note_injection_through(20)
	for n: int in range(2, 5):
		h.on_input(0, n, 0, [_c([10, n])])
		h.on_input(2, n, 0, [_c([30, n]), _c([31, n])])
	h.on_input(1, 2, 0, [_c([20, 2])])
	h.on_input(1, 3, 0, [])
	var out: Array[NetBundle] = h.close_ready()
	t.eq(out.size(), 2, "pid 1 blocks turn 4")
	t.eq(out[0].turn, 2)
	t.eq(out[0].pids, PackedInt32Array([0, 1, 2]), "groups ascending by pid")
	t.eq(out[0].group_cmds[2], [_c([30, 2]), _c([31, 2])], "submission order inside a group")
	t.eq(out[1].pids, PackedInt32Array([0, 2]), "pids without commands are omitted")
	t.eq(h.next_close_turn(), 4)
	var w: Array[Dictionary] = h.waiting()
	t.eq(w.size(), 1)
	t.eq(w[0]["pid"], 1)
	t.eq(w[0]["reason"], NetProtocol.StallReason.NETWORK)
	t.eq(h.close_ready().size(), 0)
	h.on_input(1, 4, 0, [])
	t.eq(h.close_ready().size(), 1)
	t.eq(h.waiting().size(), 3, "now everybody waits for turn 5")
	# the host's own fill-up frontier (local human) is part of the barrier
	h.on_input(0, 5, 0, [])
	h.on_input(1, 5, 0, [])
	h.on_input(2, 5, 0, [])
	h._inject_through = 4
	t.eq(h.close_ready().size(), 0, "host frontier not there yet")
	h.note_injection_through(5)
	t.eq(h.close_ready().size(), 1)


func test_at_most_16_bundles_per_call(t: TestCtx) -> void:
	var h: NetTurnHost = _host([P_AI])[0]
	h.note_injection_through(100)
	t.eq(h.close_ready().size(), 16)
	t.eq(h.next_close_turn(), 18)
	t.eq(h.close_ready().size(), 16)
	# dedicated host without AI or human: no frontier, still bounded
	var d: NetTurnHost = _host([])[0]
	t.eq(d.close_ready().size(), 16)


func test_ai_commands_merge_and_ctrl_attach_once(t: TestCtx) -> void:
	var h: NetTurnHost = _host([P_HUMAN, P_AI, P_AI])[0]
	h.note_injection_through(10)
	h.on_input(0, 2, 0, [_c([1])])
	h.add_ai_commands(2, 2, [_c([50, 2])])
	h.add_ai_commands(2, 1, [_c([40, 1]), _c([41, 1])])
	h.add_ai_commands(2, 0, [_c([99])])
	t.eq(h.stats()["dropped_cmds"], 1, "commands for a non-AI pid are refused")
	h.set_speed(150)
	h.set_speed(123)
	h.queue_ctrl(_c([NetProtocol.CtrlKind.MATCH_END, 1]))
	var out: Array[NetBundle] = h.close_ready()
	t.eq(out.size() >= 1, true)
	t.eq(out[0].pids, PackedInt32Array([0, 1, 2]))
	t.eq(out[0].group_cmds[1], [_c([40, 1]), _c([41, 1])])
	t.eq(out[0].group_cmds[2], [_c([50, 2])])
	t.eq(out[0].ctrl.size(), 2, "invalid speed was ignored")
	t.eq(out[0].ctrl[0], _c([NetProtocol.CtrlKind.SPEED, 150]))
	h.on_input(0, 3, 0, [])
	h.add_ai_commands(1, 1, [_c([1])])
	var more: Array[NetBundle] = h.close_ready()
	t.check(more.size() >= 1 and more[0].ctrl.is_empty(), "ctrl records are attached once")
	# the codec accepts what the host builds
	for b: NetBundle in out:
		t.check(NetCodec.decode_bundle(b.wire_bytes()) != null)
	# more than 64 commands in one group: overflow dropped and counted
	var big: Array = []
	for i: int in 70:
		big.append(_c([2, i]))
	h.add_ai_commands(4, 1, big)
	h.on_input(0, 4, 0, [])
	var o2: Array[NetBundle] = h.close_ready()
	t.eq(o2[0].group_cmds[o2[0].pids.find(1)].size(), 64)
	t.eq(h.stats()["dropped_cmds"], 8, "1 non-AI pid + 1 late turn + 6 overflow")
	# at most 8 ctrl records per bundle, the rest in the next
	for i: int in 10:
		h.queue_ctrl(_c([NetProtocol.CtrlKind.MATCH_END, 0]))
	h.on_input(0, 5, 0, [])
	h.on_input(0, 6, 0, [])
	var o3: Array[NetBundle] = h.close_ready()
	t.eq(o3[0].ctrl.size(), 8)
	t.eq(o3[1].ctrl.size(), 2)
	for b: NetBundle in o3:
		t.check(b.is_encodable())


func test_drop_resign_puts_t_resign_first(t: TestCtx) -> void:
	var h: NetTurnHost = _host([P_HUMAN, P_HUMAN])[0]
	var status: Array = []
	h.on_status = func(pid: int, st: int, aux: int) -> void:
		status.append([pid, st, aux])
	h.note_injection_through(30)
	h.on_input(0, 2, 0, [_c([1])])
	h.on_input(1, 2, 0, [_c([7, 7])])
	h.on_input(1, 3, 0, [_c([8])])
	h.drop_player(1, NetProtocol.StallAction.STALL_DROP_RESIGN, NetProtocol.ResignReason.KICKED)
	t.eq(status, [[1, NetProtocol.PlayerNetStatus.DROPPED, NetProtocol.ResignReason.KICKED]])
	t.eq(h.role_of(1), NetProtocol.PlayerRole.PR_DROPPED)
	h.on_input(0, 3, 0, [])
	var out: Array[NetBundle] = h.close_ready()
	t.eq(out.size(), 2, "the dropped human left the barrier")
	t.eq(out[0].pids, PackedInt32Array([0, 1]))
	t.eq(out[0].group_cmds[1], [_c([NetProtocol.T_RESIGN, 2])], "T_RESIGN first; buffered inputs are discarded")
	t.eq(out[0].ctrl, [_c([NetProtocol.CtrlKind.PLAYER_STATUS, 1, NetProtocol.PlayerNetStatus.DROPPED, 2])],
		"the status record travels in the same bundle")
	t.eq(out[1].pids.size(), 0, "resign is injected once")
	t.eq(h.on_input(1, 4, 0, []), NetTurnHost.InputResult.WRONG_PLAYER, "in-flight packet after the drop")
	# clean leave with the resign policy
	var h2: NetTurnHost = _host([P_HUMAN, P_HUMAN, P_HUMAN])[0]
	h2.player_left(2)
	h2.note_injection_through(9)
	h2.on_input(0, 2, 0, [])
	h2.on_input(1, 2, 0, [])
	var o2: Array[NetBundle] = h2.close_ready()
	t.eq(o2[0].group_cmds[o2[0].pids.find(2)], [_c([NetProtocol.T_RESIGN, NetProtocol.ResignReason.DISCONNECT])])
	t.eq(o2[0].ctrl[0][2], NetProtocol.PlayerNetStatus.LEFT)


func test_drop_ai_takeover_discards_inputs(t: TestCtx) -> void:
	var h: NetTurnHost = _host([P_HUMAN, P_HUMAN])[0]
	var took: Array = []
	h.on_takeover = func(pid: int) -> void:
		took.append(pid)
	h.note_injection_through(30)
	h.on_input(1, 2, 0, [_c([7])])
	h.on_input(1, 4, 0, [_c([8])])
	h.drop_player(1, NetProtocol.StallAction.STALL_DROP_AI, NetProtocol.ResignReason.TIMEOUT)
	t.eq(took, [1])
	t.eq(h.role_of(1), NetProtocol.PlayerRole.PR_AI)
	for n: int in range(2, 6):
		h.on_input(0, n, 0, [])
	var out: Array[NetBundle] = h.close_ready()
	t.eq(out.size(), 4)
	t.eq(out[0].pids.size(), 0, "no commands for pid 1: buffered inputs were discarded")
	t.eq(out[0].ctrl, [_c([NetProtocol.CtrlKind.PLAYER_STATUS, 1, NetProtocol.PlayerNetStatus.AI_TAKEOVER, NetProtocol.TAKEOVER_AI_LEVEL])])
	h.add_ai_commands(6, 1, [_c([9, 1])])
	h.on_input(0, 6, 0, [])
	var o2: Array[NetBundle] = h.close_ready()
	t.eq(o2[0].pids, PackedInt32Array([1]), "from the next boundary the AI commands appear in pid 1's group")
	t.eq(o2[0].group_cmds[0], [_c([9, 1])])


func test_waiting_reasons(t: TestCtx) -> void:
	var r: Array = _host([P_HUMAN, P_HUMAN, P_HUMAN], {"fixed_delay": 0})
	var h: NetTurnHost = r[0]
	h.note_injection_through(99)
	for n: int in range(2, 12):
		for p: int in 3:
			h.on_input(p, n, 0, [])
	h.on_input(0, 12, 0, [])
	h.on_input(1, 12, 0, [])
	t.eq(h.close_ready().size(), 10)
	var w: Array[Dictionary] = h.waiting()
	t.eq(w.size(), 1)
	t.eq(w[0]["pid"], 2)
	t.eq(w[0]["reason"], NetProtocol.StallReason.NETWORK)
	h.on_pong(3, {"rtt_ms": 20, "slack_min_ms": 100, "stall_ms": 0, "episodes": 0, "hitch": false, "exec_turn": 5, "load_pct": 0})
	t.eq(h.waiting()[0]["reason"], NetProtocol.StallReason.SLOW_CPU, "alive, but 3+ turns behind N - D")
	h.on_pong(3, {"rtt_ms": 20, "slack_min_ms": 100, "stall_ms": 0, "episodes": 0, "hitch": false, "exec_turn": 9, "load_pct": 0})
	t.eq(h.waiting()[0]["reason"], NetProtocol.StallReason.NETWORK)
	h.peer_disconnected(3)
	t.eq(h.waiting()[0]["reason"], NetProtocol.StallReason.DISCONNECTED)
	(r[1] as NetClock).advance_us(1_500_000)
	t.eq(h.waiting()[0]["wait_ms"], 1500)


func test_stall_info_prompt_and_auto_drop(t: TestCtx) -> void:
	var r: Array = _host([P_HUMAN, P_HUMAN], {"auto_drop_ms": 60000, "on_disconnect": NetProtocol.OnDisconnect.RESIGN})
	var h: NetTurnHost = r[0]
	var clock: NetClock = r[1]
	var infos: Array = []
	var prompts: Array = []
	h.on_stall_info = func(turn: int, entries: Array) -> void:
		infos.append([clock.now_us(), turn, entries.size()])
	h.on_stall_prompt = func(pids: PackedInt32Array) -> void:
		prompts.append([clock.now_us(), pids])
	h.note_injection_through(9999)
	var t0: int = clock.now_us()
	var closed_after: Array = []
	for _i: int in 700:  # 70 s in 100 ms steps
		while h.recv_through(0) < h.next_close_turn() + 8:
			h.on_input(0, h.recv_through(0) + 1, 0, [])
		clock.advance_us(100_000)
		h.evaluate(clock.now_us())
		while h.recv_through(0) < h.next_close_turn() + 8:
			h.on_input(0, h.recv_through(0) + 1, 0, [])
		var out: Array[NetBundle] = h.close_ready()
		if not out.is_empty() and closed_after.is_empty():
			closed_after.append((clock.now_us() - t0) / 1000)
	t.check(not infos.is_empty())
	t.check((infos[0][0] - t0) / 1000 >= 400 and (infos[0][0] - t0) / 1000 <= 500, "first STALL_INFO at ~400 ms")
	t.eq(infos[0][2], 1)
	t.check((infos[1][0] - infos[0][0]) / 1000 >= 250 and (infos[1][0] - infos[0][0]) / 1000 <= 300, "repeated every 250 ms")
	t.eq(prompts.size(), 1)
	t.check((prompts[0][0] - t0) / 1000 >= 8000 and (prompts[0][0] - t0) / 1000 <= 8100, "prompt at 8 s")
	t.eq(prompts[0][1], PackedInt32Array([1]))
	t.eq(h.role_of(1), NetProtocol.PlayerRole.PR_DROPPED, "auto-drop at 60 s with the resign policy")
	t.eq(closed_after.size(), 1)
	t.check(closed_after[0] >= 60000 and closed_after[0] <= 60200, "barrier released at ~60 s (%d)" % closed_after[0])
	t.check(infos.back()[2] == 0, "a clear message (n = 0) once the block ends: %s" % str(infos.slice(infos.size() - 3)) + str(h.stats()) + str(h._block_since_us))


func test_wait_suppresses_the_prompt_for_30s(t: TestCtx) -> void:
	var r: Array = _host([P_HUMAN, P_HUMAN], {"auto_drop_ms": 0})
	var h: NetTurnHost = r[0]
	var clock: NetClock = r[1]
	var prompts: Array = []
	h.on_stall_prompt = func(_pids: PackedInt32Array) -> void:
		prompts.append(clock.now_us() / 1000)
	h.note_injection_through(9999)
	h.on_input(0, 2, 0, [])
	h.close_ready()
	var t0: int = clock.now_us() / 1000
	for _i: int in 1000:
		clock.advance_us(100_000)
		h.evaluate(clock.now_us())
		h.close_ready()
		if prompts.size() == 1 and int(h._prompt_hold_until_us.get(1, 0)) == 0:
			h.stall_wait(1)
	t.check(prompts.size() >= 2)
	t.check(prompts[1] - prompts[0] >= 30000 and prompts[1] - prompts[0] <= 30300, "second prompt 30 s after WAIT")
	t.eq(h.role_of(1), NetProtocol.PlayerRole.PR_HUMAN, "auto_drop_ms 0 = manual only")
	t.check(prompts[0] - t0 >= 8000)


func test_disconnected_human_is_dropped_after_5s(t: TestCtx) -> void:
	var r: Array = _host([P_HUMAN, P_HUMAN], {"auto_drop_ms": 60000, "on_disconnect": NetProtocol.OnDisconnect.AI})
	var h: NetTurnHost = r[0]
	var clock: NetClock = r[1]
	var prompts: Array = []
	var took: Array = []
	h.on_stall_prompt = func(pids: PackedInt32Array) -> void:
		prompts.append(pids)
	h.on_takeover = func(pid: int) -> void:
		took.append(pid)
	h.note_injection_through(9999)
	h.on_input(0, 2, 0, [])
	h.close_ready()
	h.peer_disconnected(2)
	clock.advance_us(100_000)
	h.evaluate(clock.now_us())
	t.eq(prompts.size(), 1, "prompt at once for a DISCONNECTED human")
	for _i: int in 45:
		clock.advance_us(100_000)
		h.evaluate(clock.now_us())
	t.eq(took, [], "not yet: 4.6 s")
	for _i: int in 8:
		clock.advance_us(100_000)
		h.evaluate(clock.now_us())
	t.eq(took, [1], "the policy AI took over after DISCONNECT_ACT_MS")
	t.eq(h.role_of(1), NetProtocol.PlayerRole.PR_AI)
	t.eq(h.pid_of_peer(2), -1)


func test_pause_budget_and_permissions(t: TestCtx) -> void:
	var r: Array = _host([P_HUMAN, P_HUMAN, P_HUMAN])
	var h: NetTurnHost = r[0]
	var resumes: Array = []
	h.on_resume = func(turn: int, by: int) -> void:
		resumes.append([turn, by])
	h.note_injection_through(9999)
	var next_turn: Array = [2]

	var cycle: Callable = func(pid: int) -> int:
		var e: int = h.request_pause(pid, true)
		if e != NetProtocol.PauseError.OK:
			return e
		for p: int in 3:
			h.on_input(p, next_turn[0], 0, [])
		h.close_ready()
		next_turn[0] += 1
		# the pause bundle closed: nothing further until resumed
		for p: int in 3:
			h.on_input(p, next_turn[0], 0, [])
		if not h.close_ready().is_empty():
			return -1
		if h.request_pause(1 if pid != 1 else 2, false) != NetProtocol.PauseError.NOT_ALLOWED and pid != 0:
			return -2
		t.eq(h.request_pause(pid, false), NetProtocol.PauseError.OK)
		return e

	for i: int in 3:
		t.eq(cycle.call(1), NetProtocol.PauseError.OK, "pause %d of player 1" % (i + 1))
		h.close_ready()
		next_turn[0] += 1
	t.eq(h.pauses_used(1), 3)
	t.eq(h.request_pause(1, true), NetProtocol.PauseError.BUDGET_EXHAUSTED, "4th request")
	t.eq(h.request_pause(2, true), NetProtocol.PauseError.OK, "other players have their own budget")
	t.eq(h.request_pause(0, true), NetProtocol.PauseError.ALREADY, "second request while one is pending")
	t.eq(h.request_pause(0, false), NetProtocol.PauseError.OK, "the host may cancel; the pause never happens")
	t.eq(h.is_pause_active(), false)
	for _i: int in 5:
		t.eq(h.request_pause(0, true), NetProtocol.PauseError.OK, "the host is unlimited")
		h.request_pause(0, false)
	t.eq(resumes.size(), 3)
	t.eq(h.request_pause(5, true), NetProtocol.PauseError.NOT_ALLOWED, "no such human")


func test_pause_policies_and_resume_turn(t: TestCtx) -> void:
	var r: Array = _host([P_HUMAN, P_HUMAN], {"pause_policy": NetProtocol.PausePolicy.HOST_ONLY})
	var h: NetTurnHost = r[0]
	t.eq(h.request_pause(1, true), NetProtocol.PauseError.NOT_ALLOWED)
	var resumes: Array = []
	h.on_resume = func(turn: int, by: int) -> void:
		resumes.append([turn, by])
	h.note_injection_through(99)
	h.on_input(0, 2, 0, [])
	h.on_input(1, 2, 0, [])
	t.eq(h.request_pause(0, true), NetProtocol.PauseError.OK)
	var out: Array[NetBundle] = h.close_ready()
	t.eq(out.size(), 1)
	t.eq(out[0].ctrl, [_c([NetProtocol.CtrlKind.PAUSE, 0])])
	h.on_input(0, 3, 0, [])
	h.on_input(1, 3, 0, [])
	t.eq(h.close_ready().size(), 0, "paused: turn 3 stays open")
	t.eq(h.request_pause(0, true), NetProtocol.PauseError.ALREADY)
	t.eq(h.request_pause(1, false), NetProtocol.PauseError.NOT_ALLOWED, "not the pauser, not the host")
	t.eq(h.resume_pause(0), NetProtocol.PauseError.OK)
	t.eq(resumes, [[3, 0]])
	t.eq(h.resume_pause(0), NetProtocol.PauseError.NOT_ALLOWED, "nothing pending, nothing active")
	t.eq(h.close_ready().size(), 1, "the next bundle closes immediately after RESUME")
	var d: NetTurnHost = _host([P_HUMAN], {"pause_policy": NetProtocol.PausePolicy.DISABLED})[0]
	t.eq(d.request_pause(0, true), NetProtocol.PauseError.NOT_ALLOWED)
	# a non-host pauser may resume its own pause
	var a: NetTurnHost = _host([P_HUMAN, P_HUMAN])[0]
	a.note_injection_through(99)
	t.eq(a.request_pause(1, true), NetProtocol.PauseError.OK)
	t.eq(a.request_pause(1, false), NetProtocol.PauseError.OK)


func test_pause_expires_after_120s(t: TestCtx) -> void:
	var r: Array = _host([P_HUMAN, P_HUMAN])
	var h: NetTurnHost = r[0]
	var clock: NetClock = r[1]
	var resumes: Array = []
	h.on_resume = func(turn: int, by: int) -> void:
		resumes.append([turn, by, clock.now_us()])
	h.note_injection_through(99)
	h.on_input(0, 2, 0, [])
	h.on_input(1, 2, 0, [])
	h.request_pause(0, true)
	h.close_ready()
	var t0: int = clock.now_us()
	for _i: int in 1300:
		clock.advance_us(100_000)
		h.evaluate(clock.now_us())
	t.eq(resumes.size(), 1)
	t.check((resumes[0][2] - t0) / 1000 >= 120000 and (resumes[0][2] - t0) / 1000 <= 120200)
	t.eq(resumes[0][0], 3)


func test_delay_policy_drives_input_delay_ctrl(t: TestCtx) -> void:
	var r: Array = _host([P_HUMAN, P_HUMAN], {"fixed_delay": 0, "initial_delay": 2})
	var h: NetTurnHost = r[0]
	var clock: NetClock = r[1]
	var changed: Array = []
	h.on_delay_changed = func(d: int) -> void:
		changed.append(d)
	h.note_injection_through(9999)
	for _i: int in 30:
		clock.advance_us(100_000)
		h.on_pong(2, {"rtt_ms": 250, "slack_min_ms": 50, "stall_ms": 0, "episodes": 0, "hitch": false, "exec_turn": 0, "load_pct": 0})
		h.evaluate(clock.now_us())
	t.eq(h.delay_turns(), 3, "ceil((250 + 0 + 34) / 100)")
	t.eq(changed.size() >= 1, true)
	h.on_input(0, 2, 0, [])
	h.on_input(1, 2, 0, [])
	var out: Array[NetBundle] = h.close_ready()
	var found: bool = false
	for c: Variant in out[0].ctrl:
		if (c as PackedInt32Array)[0] == NetProtocol.CtrlKind.INPUT_DELAY:
			found = true
	t.check(found, "CK_INPUT_DELAY is queued into the next bundle")
	# fixed delay bypasses the policy
	var f: NetTurnHost = _host([P_HUMAN, P_HUMAN], {"fixed_delay": 2})[0]
	for _i: int in 30:
		f.on_pong(2, {"rtt_ms": 900, "slack_min_ms": -50, "stall_ms": 500, "episodes": 3, "hitch": false, "exec_turn": 0, "load_pct": 0})
		f.evaluate(_i * 600_000)
	t.eq(f.delay_turns(), 2)


func test_bundle_for_peer_is_identity_by_default(t: TestCtx) -> void:
	var h: NetTurnHost = _host([P_HUMAN])[0]
	var b: NetBundle = NetBundle.build(3, PackedInt32Array(), [], [])
	t.check(h._bundle_for_peer(b, 2) == b)
