extends SceneTree
## NET-11 / NET-13 process harness (docs/spec/net.md 5.11 and 10.6). One process = one player of a LAN match over real
## ENet on 127.0.0.1; tools/py/net_two_process.py starts a host and its clients and compares their NETTEST lines.
##
##   tools/gd run res://tests/net/net_harness.gd -- role=host --port=27615 --players=2 --ai=1 --sim=real --ticks=3000
##   tools/gd run res://tests/net/net_harness.gd -- role=client --connect=127.0.0.1:27615 --sim=real
##   tools/gd run res://tests/net/net_harness.gd -- role=selftest --sim=real --ticks=2400
##
## Args (leading dashes optional): role=host|client|local|selftest  port=N (0 = default)  connect=host:port  players=N
## (humans incl. the host)  ai=K  sim=fake|real  ticks=N (rounded up to 20) | turns=N  script=file.json (fake sim; default
## res://tests/net/scripts/s0_extended.json)  fault=<preset|profiles.json name>  fixed-delay=D (default 2)  speed=0|50..200
## (0 = unpaced, default)  seed=S  out=file.json  countdown=N (0)  diverge-at=T (this process corrupts its own world at tick T:
## the desync self-test)  expect-desync (a detected desync is the success)  bots=1|0 (SimBot scripted commands for the local
## human on the real sim, default 1)  ai-impl=ai|bot|stub (default ai)  timeout=SECONDS (wall guard, default 240)
## map-size=96  family=0  name=NAME  lobby-timeout=SECONDS (host waits for the clients, default 60)  spawn-clients=N (host only:
## starts N client processes of this same harness itself, waits for them and prints their NETTEST lines too; one gd
## invocation for the whole match, used inside the Linux container)  child-diverge-at=T (that last spawned client corrupts its world).
##
## Output (one line, plus a JSON file with every checksum when out=... is given):
##   NETTEST role=host pid=0 sim=real ticks=3000 chain=0x8FA5BAAE final=0xD8534782 checks=150 digest=0x... desync=0 stalls=0
##   stall_ms=0 delay=2 bytes_out=... bytes_in=... play_ms=... ms_per_tick=... lat_avg_ms=... lat_p95_ms=... status=ok
##   (replay=<dir> adds `NETREPLAY role= path=<autosave_1.mfreplay>` after shutdown)
## `chain`/`final` are the input chain and the world checksum AT the target tick; `digest` folds every (tick, checksum,
## chain) up to it. Exit code: 0 ok, 2 desync (unexpected) / not detected (expect-desync), 3 timeout, 4 setup failure.

const ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla", "roster.han.vanilla", "roster.def.vanilla",
	"roster.ae.vanilla", "roster.olm.vanilla", "roster.pd.vanilla", "roster.sap.vanilla"]
## The host's per-peer rate limiter allows 40 TURN_INPUT/s and 4 CHECKSUM_REPORT/s (anti-flood). An UNPACED harness run needs more, and the
## limiter is not what these runs test (test_net_security covers it), so the host swaps it for one that never refuses input or checksum reports.
class RelaxedLimiter extends NetRateLimiter:
	func allow(cls: int, now_us: int) -> bool:
		if cls == NetRateLimiter.Class.INPUT or cls == NetRateLimiter.Class.CHECK:
			return true
		return super.allow(cls, now_us)


const DONE_TEXT: String = "harness done"
const FIN_TEXT: String = "harness fin"

var _a: Dictionary = {}
var _clock: NetClock = NetClock.real()
var _s: NetSession = null
var _real: bool = false
var _role: String = ""
var _target: int = 3000
var _t_start_ms: int = 0
var _checks: Dictionary = {}  ## tick -> [checksum, chain]
var _bytes_out: int = 0
var _bytes_in: int = 0
var _submit_us: Array = []
var _lat_us: PackedInt64Array = PackedInt64Array()
var _reports: Array = []
var _done_from: Dictionary = {}
var _fin_seen: bool = false
var _cmds_sent: int = 0
var _capture: NetSessionKit.CaptureLog = null
var _bot: SimBot = null
var _script: Array = []
var _script_i: int = 0
var _last_think: int = -1
var _diverged: bool = false
var _errors: PackedStringArray = PackedStringArray()
var _phase_log: PackedStringArray = PackedStringArray()
var _parts: Dictionary = {}
var _ai_factory: AiFactory = null
var _ai_brains: Dictionary = {}
var _children: Array = []  ## [pid, out_path]


func _initialize() -> void:
	_parse_args()
	var code: int = _main()
	quit(code)


# ---- args -----------------------------------------------------------------------------------------------------------

func _parse_args() -> void:
	for raw: String in OS.get_cmdline_user_args():
		var arg: String = raw
		while arg.begins_with("-"):
			arg = arg.substr(1)
		var eq: int = arg.find("=")
		if eq < 0:
			_a[arg] = "1"
		else:
			_a[arg.substr(0, eq)] = arg.substr(eq + 1)


func _s_arg(key: String, def: String = "") -> String:
	return str(_a.get(key, def))


func _i_arg(key: String, def: int = 0) -> int:
	return int(_a.get(key, def))


func _has(key: String) -> bool:
	return _a.has(key)


func _say(text: String) -> void:
	print(text)


func _fail(code: int, text: String) -> int:
	_say("NETTEST_ERROR role=%s code=%d %s" % [_role, code, text])
	if _s != null:
		var shown: int = 0
		var lines: PackedStringArray = _s.log_lines()
		for i: int in range(lines.size() - 1, -1, -1):
			if not lines[i].contains(" chk t="):
				_say("  netlog " + lines[i])
				shown += 1
				if shown >= 14:
					break
		_say("  phases " + ",".join(_phase_log) + " errors: " + "; ".join(_errors))
	_shutdown()
	return code


# ---- entry ----------------------------------------------------------------------------------------------------------

func _main() -> int:
	_role = _s_arg("role", "host")
	_real = _s_arg("sim", "fake") == "real"
	var turns: int = _i_arg("turns", 0)
	_target = _i_arg("ticks", turns * NetProtocol.TURN_TICKS if turns > 0 else 3000)
	_target = (_target + 19) / 20 * 20
	match _role:
		"host":
			return _run_session(true)
		"client":
			return _run_session(false)
		"local":
			return _run_local()
		"selftest":
			return _run_selftest()
	return _fail(4, "unknown role " + _role)


# ---- options / world ---------------------------------------------------------------------------------------------

func _options() -> NetSessionOptions:
	var o: NetSessionOptions
	if _real:
		o = NetSessionOptions.from_game_data(SimMatchKit.data())
		o.world_builder = NetSessionKit.real_job
	else:
		o = NetSessionOptions.new()
		o.sim_version = 1
		o.data_hash = NetSessionKit.DATA_HASH
		o.roster_ids = NetSessionKit.roster_ids()
		o.world_builder = NetSessionKit.fake_job
	o.player_name = _s_arg("name", "Host" if _role == "host" else "Client%d" % (OS.get_process_id() % 1000))
	o.discovery_enabled = false
	o.countdown_s = _i_arg("countdown", 0)
	o.speed_pct_override = _i_arg("speed", 0)
	o.fixed_input_delay_turns = _i_arg("fixed-delay", 2)
	# one tick per poll: the harness sees every tick, so scripted commands and bot decisions are made at exact ticks
	o.max_ticks_per_poll = 1
	o.port = _i_arg("port", NetProtocol.DEFAULT_PORT) if _i_arg("port", 0) > 0 else NetProtocol.DEFAULT_PORT
	o.match_seed_override = _i_arg("seed", 20260930)
	o.unix_time_override = 1_790_000_000
	o.desync_dir = "user://desync_net_harness/%s_%d" % [_role, OS.get_process_id()]
	# replay=<dir>: every process records its replay there (NETREPLAY line with the file); default = no replay files
	o.replay_dir = _s_arg("replay", "")
	o.log_sink = func(level: int, text: String) -> void:
		if level >= NetProtocol.LogLevel.ERROR:
			_errors.append(text)
	o.clock = _clock
	var fault: String = _s_arg("fault", "")
	if fault != "" and fault != "none":
		var prof: NetFaultProfile = _profile(fault)
		if prof == null:
			return null
		var salt: int = _i_arg("seed", 1) * 31 + (0 if _role == "host" else OS.get_process_id())
		o.transport_factory = func() -> NetTransport:
			return NetTransportFault.wrap(NetTransportEnet.new(_clock), prof.duplicate_profile(), _clock, salt)
	if _s_arg("ai-impl", "ai") == "ai" and _real:
		_ai_factory = AiFactory.new()  # a Callable does not keep its object alive: the harness owns it
		# the app glue installs the brain per thinker (AiBrain.install); a bare AiFactory thinker does nothing
		o.ai_factory = func(pid: int, level: int, style: int, rng_seed: int) -> Callable:
			var thinker: Callable = _ai_factory.make(pid, level, style, rng_seed)
			_ai_brains[pid] = AiBrain.install(_ai_factory.thinker(pid).controller)
			return thinker
		o.ai_release = _ai_factory.release
	elif _real and _s_arg("ai-impl", "ai") == "bot":
		o.ai_factory = NetSessionKit.bot_factory({"first_attack_tick": 1200})
	else:
		o.ai_factory = func(pid: int, _level: int, _style: int, _seed: int) -> Callable:
			return func(_world: RefCounted, out: Array) -> void: out.append(PackedInt32Array([9, pid]))
	return o


func _profile(name: String) -> NetFaultProfile:
	var p: NetFaultProfile = NetFaultProfile.preset(name)
	if p != null:
		return p
	var f: FileAccess = FileAccess.open("res://tests/net/profiles.json", FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("profiles", {}) as Dictionary).has(name):
		return null
	var d: Dictionary = ((parsed as Dictionary)["profiles"] as Dictionary)[name] as Dictionary
	d = d.duplicate()
	d["name"] = name
	return NetFaultProfile.from_dict(d)


func _load_script() -> void:
	_script.clear()
	if _real:
		return
	var path: String = _s_arg("script", "res://tests/net/scripts/s0_extended.json")
	if path == "none":
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for c: Variant in (parsed as Dictionary).get("cmds", []) as Array:
			_script.append(c)
		_script.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["turn"]) < int(y["turn"]))


# ---- session run ---------------------------------------------------------------------------------------------------------

func _run_session(is_host: bool) -> int:
	var o: NetSessionOptions = _options()
	if o == null:
		return _fail(4, "unknown fault profile " + _s_arg("fault"))
	var players: int = maxi(2, _i_arg("players", 2))
	var ais: int = _i_arg("ai", 0)
	_load_script()
	if is_host:
		_s = NetSession.host(o, "harness")
		if _s == null:
			return _fail(4, "host failed: " + NetSession.last_create_error)
		var layout: int = 2
		for l: int in NetMatchConfig.LAYOUTS:
			if l >= players + ais:
				layout = l
				break
			layout = l
		_s.lobby.host_set_map(_i_arg("family", 0), _i_arg("map-size", 96), _i_arg("seed", 20260930) & 0xFFFFFFFF, layout)
		_say("NETTEST_LISTEN port=%d" % _s.transport.local_port())
		_spawn_clients(_s.transport.local_port(), _i_arg("spawn-clients", 0))
	else:
		var conn: PackedStringArray = _s_arg("connect", "127.0.0.1:%d" % NetProtocol.DEFAULT_PORT).split(":")
		_s = NetSession.join(o, conn[0], int(conn[1]) if conn.size() > 1 else NetProtocol.DEFAULT_PORT)
		if _s == null:
			return _fail(4, "join failed: " + NetSession.last_create_error)
	_wire_signals()
	_t_start_ms = Time.get_ticks_msec()
	var timeout_ms: int = _i_arg("timeout", 240) * 1000
	# ---- lobby
	var lobby_deadline: int = Time.get_ticks_msec() + _i_arg("lobby-timeout", 60) * 1000
	var lobby_done: bool = false
	var configured: bool = false
	var last_ready_ms: int = 0
	while _s.phase != NetSession.Phase.PLAYING:
		if Time.get_ticks_msec() > lobby_deadline and _s.phase != NetSession.Phase.LOADING:
			return _fail(4, "lobby timeout (phase %d, humans %d, start_error %d)" % [_s.phase, _s.lobby.state.human_count(), _s.lobby.start_error()])
		if _s.phase == NetSession.Phase.DISCONNECTED or _s.phase == NetSession.Phase.IDLE:
			return _fail(4, "lost the session in the lobby: " + "; ".join(_errors))
		_s.poll()
		_relax_limits()
		if _s.phase == NetSession.Phase.LOBBY and not lobby_done:
			if is_host:
				if _s.lobby.state.human_count() >= players and not configured:
					configured = true
					_configure_host_lobby(players, ais)
				if configured and _s.lobby.start_error() == NetLobby.StartError.OK:
					lobby_done = true
					var e: int = _s.lobby.host_start()
					if e != NetLobby.StartError.OK:
						return _fail(4, "host_start error %d" % e)
		if _s.phase == NetSession.Phase.LOBBY and not is_host:
			# the host's lobby edits clear everybody's ready flag: keep asking until the snapshot shows it
			var slot: int = _s.lobby.local_slot()
			var now_l: int = Time.get_ticks_msec()
			if slot >= 0 and now_l - last_ready_ms > 300:
				var me: NetPlayerSlot = _s.lobby.state.slots[slot]
				if me.roster_id != ROSTERS[slot % ROSTERS.size()]:
					_s.lobby.set_roster(ROSTERS[slot % ROSTERS.size()])
				if me.team != (1 if ais > 0 else 1 + slot % 2):
					_s.lobby.set_team(1 if ais > 0 else 1 + slot % 2)
				if not me.ready:
					_s.lobby.set_ready(true)
				last_ready_ms = now_l
		OS.delay_msec(1)
	var lobby_ms: int = Time.get_ticks_msec() - _t_start_ms
	_setup_input()
	var play_start: int = Time.get_ticks_msec()
	# ---- play
	var announced_done: bool = false
	var fin_sent: bool = false
	var fin_at_ms: int = 0
	var reached_ms: int = 0
	while true:
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _t_start_ms > timeout_ms:
			return _fail(3, "timeout at tick %d" % _tick())
		var ph: int = _s.phase
		if ph == NetSession.Phase.DESYNCED:
			break
		if ph == NetSession.Phase.IDLE or ph == NetSession.Phase.DISCONNECTED or ph == NetSession.Phase.ENDED:
			if _tick() >= _target:
				break
			return _fail(3, "session ended early: phase %d tick %d %s" % [ph, _tick(), "; ".join(_errors)])
		var tick: int = _tick()
		if tick >= _target or (_s.adapter() != null and _s.adapter().is_match_over()):
			if reached_ms == 0:
				reached_ms = now_ms
			if not announced_done:
				announced_done = true
				if is_host:
					pass
				else:
					_s.send_chat(DONE_TEXT)
			if is_host:
				var need: int = players - 1
				if _done_from.size() >= need and not fin_sent:
					fin_sent = true
					fin_at_ms = now_ms
					_s.send_chat(FIN_TEXT)
				if fin_sent and now_ms - fin_at_ms > 500:
					break
				if now_ms - reached_ms > 15000:
					break
			elif _fin_seen or now_ms - reached_ms > 20000:
				break
		else:
			_drive_input(tick)
		var n: int = _s.poll()
		_account()
		if is_host and tick % 20 == 0:
			_relax_limits()
		if n == 0:
			OS.delay_msec(1)
	var play_ms: int = Time.get_ticks_msec() - play_start
	# desync path: give the package writer and the report a moment
	if _s.phase == NetSession.Phase.DESYNCED:
		var end_ms: int = Time.get_ticks_msec() + 8000
		while _reports.is_empty() and Time.get_ticks_msec() < end_ms:
			_s.poll()
			OS.delay_msec(2)
		for _i: int in 20:
			_s.poll()
			OS.delay_msec(2)
	return _finish(play_ms, lobby_ms)


func _configure_host_lobby(players: int, ais: int) -> void:
	var lob: NetLobby = _s.lobby
	lob.set_roster(ROSTERS[0])
	lob.set_team(1)
	for i: int in range(1, players):
		var idx: int = i
		lob.host_set_slot_roster(idx, ROSTERS[idx % ROSTERS.size()])
		lob.host_set_slot_team(idx, 1 if ais > 0 else 1 + idx % 2)
	for i: int in ais:
		var slot: int = players + i
		lob.host_set_slot_kind(slot, NetProtocol.SlotKind.AI)
		lob.host_set_slot_roster(slot, ROSTERS[slot % ROSTERS.size()])
		lob.host_set_slot_team(slot, 2)
	if _has("rules-fog"):
		lob.host_set_rules({"fog": _i_arg("rules-fog", 0)})


func _wire_signals() -> void:
	_s.checksum_observer = func(tick: int, cs: int, chain: int) -> void:
		_checks[tick] = [cs & 0xFFFFFFFF, chain & 0xFFFFFFFF]
		if _has("parts") and _s != null and _s.adapter() != null:
			_parts[tick] = Array(_s.adapter().checksum_parts_at(tick))
	_s.turn_observer = _on_turn
	_s.desync_detected.connect(func(report: Dictionary) -> void: _reports.append(report))
	_s.net_error.connect(func(code: int, text: String) -> void: _errors.append("net_error %d %s" % [code, text]))
	_s.kicked.connect(func(reason: int, detail: String) -> void: _errors.append("kicked %d %s" % [reason, detail]))
	_s.phase_changed.connect(func(p: int, prev: int) -> void: _phase_log.append("%d>%d@%d" % [prev, p, Time.get_ticks_msec() - _t_start_ms]))
	if _s.lobby != null:
		_s.lobby.chat_received.connect(func(_ch: int, from_slot: int, _nm: String, text: String) -> void:
			if text.contains(DONE_TEXT):
				_done_from[from_slot] = true
			elif text.contains(FIN_TEXT):
				_fin_seen = true)


func _on_turn(_turn: int, b: NetBundle) -> void:
	var pid: int = _s.local_pid
	for gi: int in b.pids.size():
		if b.pids[gi] != pid:
			continue
		for _c: Variant in b.group_cmds[gi] as Array:
			if not _submit_us.is_empty():
				_lat_us.append(Time.get_ticks_usec() - int(_submit_us.pop_front()))


func _relax_limits() -> void:
	if _role != "host" and not (_s != null and _s.role == NetSession.Role.HOST):
		return
	if _s == null or _s.transport == null or _s_arg("speed", "0") != "0" and not _has("relax-limits"):
		return
	for id: int in _s.transport.peer_ids():
		var p: NetPeerInfo = _s.peer_info(id)
		if p != null and not (p.limiter is RelaxedLimiter):
			p.limiter = RelaxedLimiter.new()


func _tick() -> int:
	var a: NetSimAdapter = _s.adapter() if _s != null else null
	return a.current_tick() if a != null else 0


func _account() -> void:
	if _s != null and _s.transport != null:
		var traffic: PackedInt64Array = _s.transport.pop_traffic()
		_bytes_out += traffic[0]
		_bytes_in += traffic[1]


# ---- scripted input --------------------------------------------------------------------------------------------------

func _setup_input() -> void:
	_script_i = 0
	if _real and _s.local_pid >= 0 and _s_arg("bots", "1") != "0":
		_capture = NetSessionKit.CaptureLog.new()
		_bot = SimBot.new(_s.local_pid, {"first_attack_tick": 1200})
		_bot.cmd_log = _capture


func _submit(ints: PackedInt32Array) -> void:
	if _s.submit_command(ints):
		_cmds_sent += 1
		_submit_us.append(Time.get_ticks_usec())


func _drive_input(tick: int) -> void:
	if _s.local_pid < 0 or _s.phase != NetSession.Phase.PLAYING:
		return
	if _real:
		if _bot != null and tick != _last_think:
			_last_think = tick
			_capture.out = []
			_bot.think(_s.world() as SimWorld)
			for c: Variant in _capture.out:
				_submit(c as PackedInt32Array)
			_capture.out = []
	else:
		var d: int = _s.lockstep.delay_turns()
		var e: int = _s.lockstep.exec_turn()
		while _script_i < _script.size() and int((_script[_script_i] as Dictionary)["turn"]) - d - 1 <= e:
			var c: Dictionary = _script[_script_i] as Dictionary
			_script_i += 1
			if int(c["pid"]) == _s.local_pid:
				var ints: PackedInt32Array = PackedInt32Array()
				for v: Variant in c["ints"] as Array:
					ints.append(int(v))
				_submit(ints)
	var at: int = _i_arg("diverge-at", 0)
	if at > 0 and not _diverged and tick >= at:
		_diverged = true
		_diverge()


func _diverge() -> void:
	var a: NetSimAdapter = _s.adapter()
	if a is NetSimAdapterFake:
		(a as NetSimAdapterFake).inject_divergence(a.current_tick() + 1, 1)
	else:
		var w: SimWorld = a.world() as SimWorld
		w.players[_s.local_pid].credits += 7
	_say("NETTEST_DIVERGE role=%s pid=%d tick=%d" % [_role, _s.local_pid, a.current_tick()])


# ---- finish ------------------------------------------------------------------------------------------------------------

func _digest_upto(limit: int) -> int:
	var keys: Array = _checks.keys()
	keys.sort()
	var h: int = 0x811C9DC5
	for k: Variant in keys:
		if int(k) > limit:
			break
		var e: Array = _checks[k] as Array
		for v: int in [int(k), int(e[0]), int(e[1])]:
			h = ((h ^ (v & 0xFFFFFFFF)) * 0x01000193) & 0xFFFFFFFF
	return h


func _pct(arr: PackedInt64Array, p: float) -> float:
	if arr.is_empty():
		return 0.0
	var c: PackedInt64Array = arr.duplicate()
	c.sort()
	return float(c[clampi(int(ceil(p * c.size())) - 1, 0, c.size() - 1)]) / 1000.0


func _finish(play_ms: int, lobby_ms: int) -> int:
	var desynced: bool = _s.phase == NetSession.Phase.DESYNCED or not _reports.is_empty()
	var st: Dictionary = _s.stats()
	var tick: int = _tick()
	var at_target: Array = _checks.get(_target, []) as Array
	var lat_sum: int = 0
	for v: int in _lat_us:
		lat_sum += v
	var result: Dictionary = {
		"role": _role, "pid": _s.local_pid, "sim": "real" if _real else "fake", "ticks": _target, "tick_end": tick,
		"chain": int(at_target[1]) if at_target.size() == 2 else -1, "final": int(at_target[0]) if at_target.size() == 2 else -1,
		"checks": _checks.keys().filter(func(k: Variant) -> bool: return int(k) <= _target).size(), "digest": _digest_upto(_target),
		"desync": 1 if desynced else 0, "stalls": int(st["stall_count"]), "stall_ms": int(st["stall_ms"]), "delay": int(st["delay_turns"]),
		"bytes_out": _bytes_out, "bytes_in": _bytes_in, "play_ms": play_ms, "lobby_ms": lobby_ms,
		"ms_per_tick": float(play_ms) / maxf(1.0, float(tick)), "cmds": _cmds_sent,
		"lat_avg_ms": (float(lat_sum) / float(_lat_us.size()) / 1000.0) if not _lat_us.is_empty() else 0.0, "lat_p95_ms": _pct(_lat_us, 0.95),
		"phases": ",".join(_phase_log), "errors": "; ".join(_errors), "violations": int(st["violations"]), "dup_in": int(st["dup_in"]),
		"reports": _reports.size(),
	}
	if _real and _s.adapter() != null and _s.adapter().world() is SimWorld:
		var parts: PackedStringArray = PackedStringArray()
		var w: SimWorld = _s.adapter().world() as SimWorld
		for pid: int in w.players.size():
			var rep: Dictionary = SimMatchKit.report(w, pid)
			parts.append("p%d:s%du%dc%d" % [pid, int(rep.get("structures", 0)), int(rep.get("units", 0)), int(rep.get("credits", 0))])
		result["world"] = ",".join(parts)
	var pkg: String = ""
	if not _reports.is_empty():
		var rep: Dictionary = _reports[0] as Dictionary
		result["desync_tick"] = int(rep.get("tick", -1))
		result["desync_kind"] = str(rep.get("kind", ""))
		var files: Dictionary = rep.get("files", {}) as Dictionary
		var dir: String = str(rep.get("dir", ""))
		var present: PackedStringArray = PackedStringArray()
		for k: Variant in files:
			if FileAccess.file_exists(dir.path_join(str(files[k]))):
				present.append(str(k))
		result["package_dir"] = dir
		result["package_files"] = ",".join(present)
		pkg = "%s package_dir=%s" % [",".join(present), dir]
	var status: String = "ok"
	var code: int = 0
	var expect: bool = _has("expect-desync")
	if expect:
		if desynced and not present_ok(result):
			status = "package-missing"
			code = 2
		elif not desynced:
			status = "desync-not-detected"
			code = 2
	elif desynced:
		status = "desync"
		code = 2
	elif tick < _target:
		status = "short"
		code = 3
	result["status"] = status
	var line: String = _format_line(result)
	if pkg != "":
		line += " desync_tick=%d package=%s" % [int(result.get("desync_tick", -1)), pkg]
	_say(line)
	if _has("dump-checks"):
		var ks: Array = _checks.keys()
		ks.sort()
		for k: Variant in ks:
			if int(k) <= _target:
				_say("NETCHK %s t=%d cs=%08X ch=%08X parts=%s" % [_role, int(k), int((_checks[k] as Array)[0]), int((_checks[k] as Array)[1]),
					",".join(PackedStringArray((_parts.get(k, []) as Array).map(func(v: Variant) -> String: return "%08X" % (int(v) & 0xFFFFFFFF))))])
	var child_code: int = _collect_children()
	if child_code != 0:
		code = maxi(code, child_code)
	var out_path: String = _s_arg("out", "")
	if out_path != "":
		var full: Dictionary = result.duplicate()
		var rows: Array = []
		var keys: Array = _checks.keys()
		keys.sort()
		for k: Variant in keys:
			rows.append([int(k), int((_checks[k] as Array)[0]), int((_checks[k] as Array)[1])])
		full["check_rows"] = rows
		if not _parts.is_empty():
			full["parts"] = _parts
			full["part_names"] = Array(_s.adapter().checksum_part_names()) if _s != null and _s.adapter() != null else []
		var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(full))
			f.close()
	_shutdown()
	return code


func _format_line(r: Dictionary) -> String:
	var line: String = "NETTEST role=%s pid=%d sim=%s ticks=%d chain=0x%08X final=0x%08X checks=%d digest=0x%08X desync=%d stalls=%d stall_ms=%d delay=%d bytes_out=%d bytes_in=%d play_ms=%d ms_per_tick=%.3f lat_avg_ms=%.1f lat_p95_ms=%.1f cmds=%d status=%s" % [
		str(r["role"]), int(r["pid"]), str(r["sim"]), int(r["ticks"]), int(r["chain"]) & 0xFFFFFFFF, int(r["final"]) & 0xFFFFFFFF, int(r["checks"]),
		int(r["digest"]) & 0xFFFFFFFF, int(r["desync"]), int(r["stalls"]), int(r["stall_ms"]), int(r["delay"]), int(r["bytes_out"]), int(r["bytes_in"]),
		int(r["play_ms"]), float(r["ms_per_tick"]), float(r["lat_avg_ms"]), float(r["lat_p95_ms"]), int(r["cmds"]), str(r["status"])]
	if r.has("world"):
		line += " world=" + str(r["world"])
	return line


## Starts `n` client processes of this harness (same Godot binary and project). Their NETTEST lines are printed by the host at
## the end (read back from the JSON files they write).
func _spawn_clients(port: int, n: int) -> void:
	for i: int in n:
		var out_path: String = OS.get_user_data_dir().path_join("net_harness_%d_c%d.json" % [OS.get_process_id(), i])
		var args: PackedStringArray = PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--headless", "--script",
			"res://tests/net/net_harness.gd", "--"])
		for k: Variant in _a:
			if ["role", "connect", "out", "name", "port", "spawn-clients", "diverge-at", "child-diverge-at", "players", "ai", "timeout"].has(str(k)):
				continue
			args.append("%s=%s" % [str(k), str(_a[k])])
		args.append_array(["role=client", "connect=127.0.0.1:%d" % port, "out=" + out_path, "players=%d" % _i_arg("players", 2),
			"ai=%d" % _i_arg("ai", 0), "timeout=%d" % _i_arg("timeout", 240), "name=Client%d" % (i + 2)])
		if i == n - 1 and _has("child-diverge-at"):
			args.append("diverge-at=%d" % _i_arg("child-diverge-at", 0))
		var pid: int = OS.create_process(OS.get_executable_path(), args)
		if pid <= 0:
			_say("NETTEST_ERROR role=host code=4 could not start client %d" % i)
			continue
		DirAccess.remove_absolute(out_path)
		_children.append([pid, out_path])


func _collect_children() -> int:
	var worst: int = 0
	var deadline: int = Time.get_ticks_msec() + 60_000
	for c: Variant in _children:
		var pid: int = int((c as Array)[0])
		while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(20)
		if OS.is_process_running(pid):
			OS.kill(pid)
			_say("NETTEST_ERROR role=client code=3 child %d did not finish" % pid)
			worst = maxi(worst, 3)
			continue
		worst = maxi(worst, OS.get_process_exit_code(pid))
		var f: FileAccess = FileAccess.open(str((c as Array)[1]), FileAccess.READ)
		if f == null:
			_say("NETTEST_ERROR role=client code=4 no result file from child %d" % pid)
			worst = maxi(worst, 4)
			continue
		var d: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if d is Dictionary:
			var line: String = _format_line(d as Dictionary)
			if (d as Dictionary).has("package_dir"):
				line += " desync_tick=%d package=%s package_dir=%s" % [int((d as Dictionary).get("desync_tick", -1)), str(d["package_files"]), str(d["package_dir"])]
			_say(line)
	_children.clear()
	return worst


func present_ok(result: Dictionary) -> bool:
	var have: PackedStringArray = str(result.get("package_files", "")).split(",")
	return have.has("json") and have.has("state") and have.has("checks")


func _shutdown() -> void:
	if _s != null:
		_s.shutdown()
		if _has("replay"):
			_say("NETREPLAY role=%s path=%s" % [_role, _s.replay_path()])
		_s = null


# ---- LOCAL and selftest -------------------------------------------------------------------------------------------------

func _local_config(o: NetSessionOptions) -> Dictionary:
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", ROSTERS[0], o)
	st.map_size = _i_arg("map-size", 96)
	st.layout_players = 2 if _i_arg("ai", 1) <= 1 else 4
	st.slots[1].roster_id = ROSTERS[1]
	st.rules["fog"] = 0
	var extra: int = _i_arg("ai", 1) - 1
	for i: int in extra:
		var sl: NetPlayerSlot = st.slots[2 + i]
		sl.kind = NetProtocol.SlotKind.AI
		sl.name = "AI %d" % (3 + i)
		sl.roster_id = ROSTERS[(2 + i) % ROSTERS.size()]
		sl.ready = true
		sl.connected = true
		sl.team = 2
	var ver: Dictionary = {"game": o.game_version, "proto": 1, "sim": o.sim_version, "data_hash": o.data_hash, "data_format": 1,
		"data_ids": int(SimMatchKit.data().table_hashes.get("ids", 0)) if _real else 0}
	var raw: Dictionary = NetMatchConfig.from_lobby(st, _i_arg("seed", 20260930), ver, 1_790_000_000, o.roster_ids)
	return NetMatchConfig.parse(NetMatchConfig.canonical_json(raw))


func _run_local() -> int:
	var o: NetSessionOptions = _options()
	o.fixed_input_delay_turns = 0
	var cfg: Dictionary = _local_config(o)
	_s = NetSession.local_from_config(o, cfg)
	if _s == null:
		return _fail(4, "local failed: " + NetSession.last_create_error)
	_wire_signals()
	_load_script()
	_t_start_ms = Time.get_ticks_msec()
	var play_start: int = _t_start_ms
	while _tick() < _target and _s.phase != NetSession.Phase.ENDED and _s.phase != NetSession.Phase.IDLE:
		if _s.phase == NetSession.Phase.PLAYING and _s.adapter() != null:
			if _bot == null and _capture == null:
				_setup_input()
			_drive_input(_tick())
		_s.poll()
		if Time.get_ticks_msec() - _t_start_ms > _i_arg("timeout", 240) * 1000:
			return _fail(3, "timeout")
	return _finish(Time.get_ticks_msec() - play_start, 0)


func _run_selftest() -> int:
	var o: NetSessionOptions = _options()
	var cfg: Dictionary = _local_config(o)
	var t0: int = Time.get_ticks_msec()
	var r: Dictionary = NetSelfTest.run_double(cfg, o.world_builder, [], _target, o.ai_factory)
	var ok: bool = bool(r["ok"])
	_say("NETTEST role=selftest sim=%s ticks=%d chain=0x%08X final=0x%08X checks=%d desync=%d status=%s compared=%d wall_ms=%d error=%s" % [
		"real" if _real else "fake", int(r["ticks"]), int(r["chain_a"]) & 0xFFFFFFFF, int(r["final_a"]) & 0xFFFFFFFF, int(r["compared"]),
		0 if ok else 1, "ok" if ok else "fail", int(r["compared"]), Time.get_ticks_msec() - t0, str(r["error"])])
	return 0 if ok else 2
