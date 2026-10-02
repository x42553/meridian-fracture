class_name NetHostGame
extends RefCounted
## Host / LOCAL side of a running match (docs/spec/net.md 5.5.4-5.5.10, 5.6): builds the NetTurnHost and NetAiRunner from
## the MatchConfig, handles the in-match messages of the players (TURN_INPUT, PONG, PAUSE_REQUEST, CHECKSUM_REPORT,
## PARTS_REPORT, MAP_PING), closes and relays turn bundles and reacts to the turn host's hooks (stall info / prompts,
## status changes, resume, AI takeover). The session wires the Callables and the shared references; nothing here holds
## the session.

var opts: NetSessionOptions = null
var clock: NetClock = null
var is_local: bool = false
var peers: Dictionary = {}
var config: Dictionary = {}
var local_peer_id: int = 1
var local_pid: int = -1
var lockstep: NetLockstep = null
var desync: NetDesync = null
var adapter: NetSimAdapter = null
var turn_host: NetTurnHost = null
var ai_runner: NetAiRunner = null

## (peer_id: int, data: PackedByteArray) -> void
var send: Callable = Callable()
## (peer_id: int, code: int, graceful: bool) -> void
var disconnect_fn: Callable = Callable()
## (waiting: Array) -> void; [{pid, name, reason, wait_ms}], empty = resumed
var emit_stall: Callable = Callable()
var emit_prompt: Callable = Callable()
## (pid: int, status: int) -> void; host-local status detection (DISCONNECTED / STALLED)
var emit_status: Callable = Callable()
var emit_map_ping: Callable = Callable()
## (code: int, text: String) -> void
var emit_error: Callable = Callable()
## (by_pid: int) -> void
var note_resume_by: Callable = Callable()
## (level: int, text: String) -> void
var log_fn: Callable = Callable()
## (pid: int) -> String
var pid_name: Callable = Callable()

var _resigned_noted: Dictionary = {}


func _log(level: int, text: String) -> void:
	if log_fn.is_valid():
		log_fn.call(level, text)


func _send(peer_id: int, data: PackedByteArray) -> void:
	if send.is_valid():
		send.call(peer_id, data)


func _players_send(data: PackedByteArray) -> void:
	for k: Variant in peers:
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.PLAYING:
			_send(p.peer_id, data)


## Builds the turn host (roles from the config) and the AI runner (one thinker per AI player).
func setup(d0: int, speed_pct: int) -> void:
	var net: Dictionary = config["net"] as Dictionary
	turn_host = NetTurnHost.new()
	turn_host.setup(clock, {
		"initial_delay": d0, "min_delay": 1 if is_local else maxi(opts.min_input_delay_turns, 1), "max_delay": NetProtocol.D_MAX,
		"fixed_delay": d0 if is_local else opts.fixed_input_delay_turns, "speed_pct": speed_pct,
		"pause_policy": NetProtocol.PausePolicy.ANY_PLAYER if is_local else int(net["pause_policy"]),
		"auto_drop_ms": int(net["auto_drop_ms"]), "on_disconnect": int(net["on_disconnect"]),
	})
	turn_host.on_stall_info = on_stall_info
	turn_host.on_stall_prompt = on_stall_prompt
	turn_host.on_status = on_status
	turn_host.on_resume = on_resume
	turn_host.on_takeover = on_takeover
	ai_runner = NetAiRunner.new()
	ai_runner.setup(opts.ai_factory, int(config["seed"]), opts.ai_think_period, opts.ai_release, opts.speed_pct_override != 0)
	for pv: Variant in config["players"] as Array:
		var pl: Dictionary = pv as Dictionary
		var pid: int = int(pl["pid"])
		if str(pl["kind"]) == "human":
			turn_host.set_player(pid, NetProtocol.PlayerRole.PR_HUMAN, int(pl["peer"]))
		else:
			turn_host.set_player(pid, NetProtocol.PlayerRole.PR_AI, 0)
			var ai: Dictionary = pl["ai"] as Dictionary
			if not ai_runner.add_ai(pid, int(ai["level"]), int(ai["style"])):
				_log(NetProtocol.LogLevel.WARN, "no AI thinker for pid %d (factory missing or refused)" % pid)


# ---- lockstep hooks (host) ------------------------------------------------------------------------------------

## The host's own fill-up input goes straight into the turn host, like a remote TURN_INPUT would.
func send_input_local(turn: int, exec_turn: int, cmds: Array) -> void:
	if turn_host == null or local_pid < 0:
		return
	turn_host.on_input(local_pid, turn, exec_turn, cmds)
	note_resign(local_pid, cmds)


## After the local fill-up: AI production for the bundle of `target` and the injection frontier.
func boundary(turn: int, target: int) -> void:
	if turn_host == null:
		return
	var groups: Array = []
	if ai_runner != null and adapter != null:
		ai_runner.produce(turn, target, adapter, groups)
	for g: Variant in groups:
		turn_host.add_ai_commands(target, int((g as Array)[0]), (g as Array)[1] as Array)
	turn_host.note_injection_through(target)


## Closes every ready turn, relays it to the players and feeds the local lockstep.
func close_and_send() -> void:
	if turn_host == null or lockstep == null or lockstep.is_over():
		return
	for b: NetBundle in turn_host.close_ready():
		if not b.is_encodable():
			_log(NetProtocol.LogLevel.ERROR, "bundle %d is not encodable" % b.turn)
			if emit_error.is_valid():
				emit_error.call(NetProtocol.NetErrorCode.HOST_PROTOCOL, "bundle %d is not encodable" % b.turn)
			continue
		for k: Variant in peers:
			var p: NetPeerInfo = peers[k] as NetPeerInfo
			if p.stage != NetPeerInfo.Stage.PLAYING:
				continue
			var pb: NetBundle = turn_host._bundle_for_peer(b, p.peer_id)
			_send(p.peer_id, pb.wire_bytes())
		lockstep.push_bundle(b)


# ---- message handlers (host); every one returns the violation weight ------------------------------------------

func _pid_of(p: NetPeerInfo) -> int:
	return NetMatchConfig.pid_of_peer(config, p.peer_id)


func handle_map_ping(p: NetPeerInfo, data: PackedByteArray, _now: int) -> float:
	var d: Dictionary = NetLobbyCodec.decode_map_ping_c2h(data)
	if d.is_empty():
		return 3.0
	var pid: int = _pid_of(p)
	if pid < 0:
		return 1.0
	relay_ping(pid, int(d["cell_x"]), int(d["cell_y"]))
	return 0.0


func relay_ping(from_pid: int, x: int, y: int) -> void:
	var team: int = NetMatchConfig.team_of(config, from_pid)
	var out: PackedByteArray = NetLobbyCodec.encode_map_ping_h2c({"from_pid": from_pid, "cell_x": x, "cell_y": y})
	for pv: Variant in config.get("players", []) as Array:
		var pl: Dictionary = pv as Dictionary
		if int(pl["pid"]) == from_pid or int(pl["team"]) != team or str(pl["kind"]) != "human":
			continue
		if int(pl["peer"]) == local_peer_id:
			if emit_map_ping.is_valid():
				emit_map_ping.call(from_pid, x, y)
		else:
			_send(int(pl["peer"]), out)


func handle_turn_input(p: NetPeerInfo, data: PackedByteArray, _now: int) -> float:
	var pid: int = _pid_of(p)
	var d: Dictionary = NetCodec.decode_turn_input(data)
	if d.is_empty():
		var hdr: Dictionary = NetCodec.peek_turn_input_header(data)
		if not hdr.is_empty() and turn_host != null and pid >= 0:
			turn_host.on_bad_input(pid, int(hdr["turn"]))
		return 3.0
	if turn_host == null or pid < 0:
		return 1.0
	p.exec_turn = int(d["exec_turn"])
	var res: int = turn_host.on_input(pid, int(d["turn"]), int(d["exec_turn"]), d["cmds"] as Array)
	if res == NetTurnHost.InputResult.WRONG_PLAYER:
		return 0.0
	note_resign(pid, d["cmds"] as Array)
	match res:
		NetTurnHost.InputResult.DUPLICATE:
			return 1.0
		NetTurnHost.InputResult.TOO_FAR, NetTurnHost.InputResult.TOO_BIG:
			return 3.0
	return 0.0


## Gate hook: an oversize TURN_INPUT whose header is readable still counts as an EMPTY input (I1: no gap).
func handle_oversize_input_hook(p: NetPeerInfo, _type: int, data: PackedByteArray) -> void:
	var hdr: Dictionary = NetCodec.peek_turn_input_header(data)
	if not hdr.is_empty() and turn_host != null:
		turn_host.on_bad_input(_pid_of(p), int(hdr["turn"]))


## The host sees a player's own T_RESIGN: RESIGNED status (ctrl record) once.
func note_resign(pid: int, cmds: Array) -> void:
	if turn_host == null or _resigned_noted.has(pid):
		return
	for c: Variant in cmds:
		var a: PackedInt32Array = c as PackedInt32Array
		if a.size() >= 1 and a[0] == NetProtocol.T_RESIGN:
			_resigned_noted[pid] = true
			var reason: int = clampi(a[1] if a.size() > 1 else 0, 0, 3)
			turn_host.queue_ctrl(PackedInt32Array([NetProtocol.CtrlKind.PLAYER_STATUS, pid, NetProtocol.PlayerNetStatus.RESIGNED, reason]))
			return


func handle_pong(p: NetPeerInfo, data: PackedByteArray, now: int) -> float:
	var d: Dictionary = NetCodec.decode_pong(data)
	if d.is_empty():
		return 3.0
	var now_ms: int = (now / 1000) & 0xFFFFFFFF
	var rtt: int = (now_ms - int(d["echo_ms"])) & 0xFFFFFFFF
	if rtt > 600000:
		return 0.0
	p.jitter_ms = (p.jitter_ms * 3 + absi(rtt - p.rtt_ms)) / 4
	p.rtt_ms = rtt
	p.exec_turn = int(d["exec_turn"])
	p.stats.add_rtt_sample(float(rtt))
	if turn_host != null:
		turn_host.on_pong(p.peer_id, {
			"rtt_ms": rtt, "slack_min_ms": int(d["slack_min_ms"]), "stall_ms": int(d["stall_ms"]), "episodes": int(d["episodes"]),
			"hitch": bool(d["hitch"]), "exec_turn": int(d["exec_turn"]), "load_pct": int(d["load_pct"]),
		})
	return 0.0


func handle_pause_request(p: NetPeerInfo, data: PackedByteArray, _now: int) -> float:
	var d: Dictionary = NetCodec.decode_pause_request(data)
	if d.is_empty():
		return 3.0
	var pid: int = _pid_of(p)
	if turn_host != null and pid >= 0:
		turn_host.request_pause(pid, bool(d["want_paused"]))
	return 0.0


func handle_checksum_report(p: NetPeerInfo, data: PackedByteArray, _now: int) -> float:
	var d: Dictionary = NetCodec.decode_checksum_report(data)
	if d.is_empty():
		return 3.0
	var pid: int = _pid_of(p)
	if desync != null and pid >= 0:
		desync.on_report(pid, int(d["tick"]), int(d["checksum"]), int(d["input_chain"]))
	return 0.0


func handle_parts_report(p: NetPeerInfo, data: PackedByteArray, _now: int) -> float:
	var d: Dictionary = NetCodec.decode_parts_report(data)
	if d.is_empty():
		return 3.0
	var pid: int = _pid_of(p)
	if desync != null and pid >= 0:
		var parts: PackedInt32Array = PackedInt32Array()
		for v: int in d["parts"] as PackedInt64Array:
			parts.append(v)
		desync.on_parts(pid, int(d["tick"]), parts)
	return 0.0


# ---- turn host hooks ------------------------------------------------------------------------------------------

func entries_to_waiting(entries: Array) -> Array:
	var out: Array = []
	for e: Variant in entries:
		var v: PackedInt32Array = e as PackedInt32Array
		out.append({"pid": v[0], "name": str(pid_name.call(v[0])) if pid_name.is_valid() else "", "reason": v[1], "wait_ms": v[2]})
	return out


func on_stall_info(turn: int, entries: Array) -> void:
	_players_send(NetCodec.encode_stall_info({"turn": turn, "entries": entries.slice(0, 8)}))
	if emit_stall.is_valid():
		emit_stall.call(entries_to_waiting(entries))


func on_stall_prompt(pids: PackedInt32Array) -> void:
	if emit_prompt.is_valid():
		emit_prompt.call(pids)


func on_status(pid: int, status: int, aux: int) -> void:
	if pid >= 0 and pid < NetProtocol.MAX_PLAYERS and (status == NetProtocol.PlayerNetStatus.DISCONNECTED or status == NetProtocol.PlayerNetStatus.STALLED):
		if emit_status.is_valid():
			emit_status.call(pid, status)
	if status == NetProtocol.PlayerNetStatus.DROPPED or status == NetProtocol.PlayerNetStatus.AI_TAKEOVER:
		_kick_replaced_peer(pid)
		_check_no_humans()
	elif status == NetProtocol.PlayerNetStatus.LEFT:
		_check_no_humans()
	_log(NetProtocol.LogLevel.INFO, "player %d status %d aux %d" % [pid, status, aux])


func _kick_replaced_peer(pid: int) -> void:
	for pv: Variant in config.get("players", []) as Array:
		var pl: Dictionary = pv as Dictionary
		if int(pl["pid"]) == pid and str(pl["kind"]) == "human" and int(pl["peer"]) != local_peer_id:
			var peer_id: int = int(pl["peer"])
			if peers.has(peer_id):
				_send(peer_id, NetLobbyCodec.encode_kicked({"reason": NetProtocol.KickReason.DROPPED_UNRESPONSIVE, "detail": ""}))
				if disconnect_fn.is_valid():
					disconnect_fn.call(peer_id, NetProtocol.KickReason.DROPPED_UNRESPONSIVE, true)
				(peers[peer_id] as NetPeerInfo).stage = NetPeerInfo.Stage.LEFT
				peers.erase(peer_id)


## A dedicated host with no human left in the barrier ends the match (CK_MATCH_END NO_HUMANS_LEFT).
func _check_no_humans() -> void:
	if turn_host == null or not opts.dedicated:
		return
	for pid: int in NetProtocol.MAX_PLAYERS:
		if turn_host.role_of(pid) == NetProtocol.PlayerRole.PR_HUMAN:
			return
	turn_host.queue_ctrl(PackedInt32Array([NetProtocol.CtrlKind.MATCH_END, NetProtocol.MatchEndReason.NO_HUMANS_LEFT]))


func on_resume(resume_turn: int, by_pid: int) -> void:
	if note_resume_by.is_valid():
		note_resume_by.call(by_pid)
	_players_send(NetCodec.encode_resume({"resume_turn": resume_turn, "by_pid": by_pid}))
	if lockstep != null:
		lockstep.resume(resume_turn)


func on_takeover(pid: int) -> void:
	if ai_runner == null:
		return
	if not ai_runner.add_ai(pid, NetProtocol.TAKEOVER_AI_LEVEL, 0):
		_log(NetProtocol.LogLevel.WARN, "AI takeover of pid %d failed: no AI factory" % pid)


## Releases the AI thinkers (match end / teardown).
func release() -> void:
	if ai_runner != null:
		ai_runner.release_all()
