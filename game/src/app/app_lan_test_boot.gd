class_name AppLanTestBoot
extends RefCounted
## Headless LAN test boot (task APP2; `AppTestBoot.run` dispatches here for `--autostart=lan-host` and `--autostart=lan-join=<address>`).
## Two of these processes play a whole LAN game through the REAL app path on 127.0.0.1 (ENet): `AppLan.host_lan` / `AppLan.join_lan`
## (the same calls the LAN screens make), lobby edits through `UiLobbyNet` (`diff` / `execute`, the calls the lobby widgets make),
## `NetLobby.host_start` with its countdown, `NetLaunch` (config, loading, LOAD_DONE compare, START), the lockstep match, the AI slot
## on the host, and a scripted test bot for each human. The driver `tools/py/app_two_process.py` starts both and compares the lines.
##
##   tools/gd run res://src/app/boot.tscn -- --autostart=lan-host --port=27700 --ticks=3000 --out=host.txt
##   tools/gd run res://src/app/boot.tscn -- --autostart=lan-join=127.0.0.1 --port=27700 --ticks=3000 --out=client.txt
##
## Flags: `--port=N` (game port), `--ticks=N` (default 3000, checksum lines every 200), `--net-speed=<pct>` (game speed, default 200: the
## per-peer input rate limit makes an unpaced LAN run impossible), `--expect-humans=N` (default 2), `--ai=N` (AI slots, default 1),
## `--ai-level=L` (default 0), `--map-seed=S --map-size=N --family=F`, `--match-seed=S` (the lobby then plays the same match run after run), `--governor=1` (keep the AI's CPU governor, off by default in the test so that runs are reproducible across machines), `--fixed-delay=N` (input delay in turns, default 2: otherwise the host derives it from the measured latency and the checksums differ between machines), `--rosters=a,b,c`, `--lobby-timeout-s=S` (default 120),
## `--timeout-s=S` (whole run, default 600), `--discovery=0|1` and `--discovery-port=N`, `--bots=human|all|ai` (default `human`),
## `--out=<file>` (every line is also appended to the file), `--spawn-client` (host only: the host starts the client process itself,
## needed inside the Linux container where `tools/gd` runs one command at a time).
## Lines (all carry `role=`): `APP_READY`, `APPLAN_LISTEN port=`, `APPLAN_LOBBY ...`, `APPTEST role= tick= chain= checksum= cmds=` every 200
## ticks up to `--ticks`, `APPTEST_END role= reason=ticks tick=`, `APPLAN_SUMMARY ...`. Exit codes: 0 ok, 3 timeout, 4 setup or lobby
## failure, 5 desync, 6 disconnected or kicked.

const DEFAULT_ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla", "roster.han.vanilla", "roster.def.vanilla"]
const DONE_TEXT: String = "app lan done"
const FIN_TEXT: String = "app lan fin"
const LOBBY_TEXT: String = "app lan lobby"
const REPORT_EVERY: int = 200

static var _file: FileAccess = null
static var _role: String = ""


## Coroutine (AppBoot awaits it). Never returns normally: it quits the tree with the exit code.
static func run(host: Node, args: AppLaunchArgs) -> void:
	var mode: String = String(args.autostart)
	var tree: SceneTree = host.get_tree()
	_role = "host" if mode == "lan-host" else "client"
	var out_path: String = str(args.extras.get("out", ""))
	if not out_path.is_empty():
		_file = FileAccess.open(out_path, FileAccess.WRITE)
	var state: Node = tree.root.get_node_or_null("AppState")
	var data: GameData = state.get("data") as GameData if state != null else null
	if data == null:
		_out("APPTEST_END reason=data tick=0")
		tree.quit(4)
		return
	_out("APP_READY mode=%s data_hash=%08X" % [mode, data.data_hash()])
	AppAiHook.set_bot_mode(str(args.extras.get("bots", "human")) if args.extras.get("bots", "human") is String else "human")
	var code: int
	if _role == "host":
		code = await _run_host(tree, data, args)
	else:
		code = await _run_client(tree, mode.substr("lan-join=".length()), data, args)
	if _file != null:
		_file.flush()
		_file.close()
		_file = null
	await tree.process_frame
	tree.quit(code)


# ---------------------------------------------------------------- host

static func _run_host(tree: SceneTree, data: GameData, args: AppLaunchArgs) -> int:
	var port: int = _int(args, "port", NetProtocol.DEFAULT_PORT)
	var target: int = args.ticks if args.ticks > 0 else 3000
	var expect_humans: int = _int(args, "expect-humans", 2)
	var p: Dictionary = {"port": port, "lobby_name": "Test game", "advertise": _int(args, "discovery", 0) != 0, "player_name": "Host",
		"countdown_s": 1, "with_view": false, "match_seed": _int(args, "match-seed", -1), "fixed_delay": _int(args, "fixed-delay", 2), "discovery_port": _int(args, "discovery-port", NetProtocol.DISCOVERY_PORT),
		"discovery_targets": PackedStringArray(["127.0.0.1"])}
	var ctx: AppMatchContext = AppLan.host_lan(p)
	if ctx == null:
		_out("APPTEST_END reason=setup tick=0 detail=%s" % NetSession.last_create_error)
		return 4
	var s: NetSession = ctx.session
	var rec: Recorder = Recorder.new(s, target)
	_out("APPLAN_LISTEN port=%d" % s.transport.local_port())
	if _int(args, "governor", 0) == 0:
		# The AI's CPU governor raises the think period of a slow machine (wall clock): right for play, but it makes the match differ from
		# machine to machine. The proof compares runs across machines, so the test switches it off (`--governor=1` keeps it).
		s.match_started.connect(func() -> void:
			if s.ai_runner != null:
				s.ai_runner.set_governor(false))
	_show_lobby(tree, args)
	var child: int = -1
	var child_file: String = ""
	if args.extras.has("spawn-client"):
		child_file = OS.get_user_data_dir().path_join("app_lan_client_%d.txt" % OS.get_process_id())
		child = _spawn_client(s.transport.local_port(), child_file, args)  # the port the host really got (it scans upward when busy)
		if child <= 0:
			_out("APPTEST_END reason=setup tick=0 detail=could not start the client process")
			return 4
	var t0: int = Time.get_ticks_msec()
	var lobby_deadline: int = t0 + _int(args, "lobby-timeout-s", 120) * 1000
	var overall: int = t0 + args.timeout_s * 1000
	var ui: UiLobbyState = UiLobbyState.create(data)
	var configured: bool = false
	var started: bool = false
	var next_try: int = 0
	var code: int = 0
	while true:
		await tree.process_frame
		var now: int = Time.get_ticks_msec()
		if now > overall or (not started and now > lobby_deadline):
			_out("APPTEST_END reason=timeout tick=%d phase=%d" % [rec.tick, s.phase])
			code = 3
			break
		if rec.failed():
			code = rec.fail_code
			_out("APPTEST_END reason=%s tick=%d" % [rec.fail_reason, rec.tick])
			break
		if s.phase == NetSession.Phase.LOBBY:
			if not configured and s.lobby.state.human_count() >= expect_humans:
				configured = _configure(s, ui, data, args)
			elif configured and not started and now >= next_try:
				next_try = now + 400
				if s.lobby.state.phase == NetProtocol.LobbyPhase.OPEN:
					var err: int = s.lobby.start_error()
					if err == NetLobby.StartError.OK:
						var r: int = s.lobby.host_start()
						started = r == NetLobby.StartError.OK
						_out("APPLAN_LOBBY start=%s countdown=%d" % [started, s.opts.countdown_s])
					elif err == NetLobby.StartError.HUMAN_NOT_READY or err == NetLobby.StartError.HUMAN_DISCONNECTED:
						pass
					else:
						_out("APPLAN_LOBBY start_error=%d %s" % [err, NetLobby.start_error_text(err)])
		if s.phase == NetSession.Phase.PLAYING and not started:
			started = true
		if rec.reached():
			if not rec.done_sent:
				rec.done_sent = true
				_out("APPTEST_REACHED tick=%d" % rec.target)
			if rec.peer_done or now > rec.reached_at + 30_000:
				s.send_chat(FIN_TEXT)
				await _flush_frames(tree, 20)
				break
	if code == 0 and args.extras.has("lobby-again"):
		code = await _back_to_lobby(tree, rec, s)
	_finish(ctx, rec, s, args.with_ui)
	if child > 0:
		code = maxi(code, _collect_child(child, child_file))
	return code


## Puts the lobby in the state of the test through `UiLobbyNet`: the same `pull` / `diff` / `execute` path the lobby widgets use. Returns
## true once no difference is left (a map change makes the lobby clear the ready flags and one edit kind returns alone, so it takes
## several rounds).
static func _configure(s: NetSession, ui: UiLobbyState, data: GameData, args: AppLaunchArgs) -> bool:
	for round_i: int in 10:
		UiLobbyNet.pull(s.lobby.state, ui)
		_setup(ui, data, args)
		var ops: Array[Dictionary] = UiLobbyNet.diff(s.lobby.state, ui, UiLobbyNet.Role.HOST, s.lobby.local_slot())
		if ops.is_empty():
			_out("APPLAN_LOBBY configured rounds=%d humans=%d ai=%d layout=%d" % [round_i, s.lobby.state.human_count(), s.lobby.state.ai_count(), s.lobby.state.layout_players])
			return true
		var r: int = UiLobbyNet.execute(s.lobby, ops)
		if r != NetLobby.Result.OK:
			_out("APPLAN_LOBBY edit_refused=%d %s" % [r, str(ops[0]["call"])])
	return false


## The wanted lobby, applied on top of the authoritative state.
static func _setup(ui: UiLobbyState, data: GameData, args: AppLaunchArgs) -> void:
	var rosters: PackedStringArray = DEFAULT_ROSTERS.duplicate()
	if args.extras.has("rosters"):
		rosters = str(args.extras["rosters"]).split(",", false)
	ui.family = _int(args, "family", 0)
	ui.size = _int(args, "map-size", 128)
	ui.seed_value = _int(args, "map-seed", 7)
	ui.speed_pct = _int(args, "net-speed", 200)
	ui.fog = false
	ui.set_layout_players(4)
	_apply_pick(ui.slots[0], data, rosters[0], 1)
	var ai_left: int = _int(args, "ai", 1)
	for i: int in range(1, 4):
		var sl: UiLobbyState.Slot = ui.slots[i]
		if sl.kind == UiLobbyState.Kind.HUMAN:
			continue
		if ai_left > 0:
			ai_left -= 1
			sl.kind = UiLobbyState.Kind.AI
			sl.ai_level = _int(args, "ai-level", 0)
			_apply_pick(sl, data, rosters[mini(i + 1, rosters.size() - 1)], 2)


static func _apply_pick(slot: UiLobbyState.Slot, data: GameData, roster_id: String, team: int) -> void:
	var pick: Vector2i = UiLobbyNet.roster_pick(data, roster_id)
	slot.faction = pick.x
	slot.sub = pick.y
	slot.team = team


# ---------------------------------------------------------------- client

static func _run_client(tree: SceneTree, address: String, data: GameData, args: AppLaunchArgs) -> int:
	var port: int = _int(args, "port", NetProtocol.DEFAULT_PORT)
	var target: int = args.ticks if args.ticks > 0 else 3000
	var ctx: AppMatchContext = AppLan.join_lan(address, port, "", {"player_name": "Client", "with_view": false})
	if ctx == null:
		_out("APPTEST_END reason=setup tick=0 detail=%s" % NetSession.last_create_error)
		return 4
	var s: NetSession = ctx.session
	var rec: Recorder = Recorder.new(s, target)
	var rejected: PackedStringArray = PackedStringArray()
	s.join_rejected.connect(func(reason: int, info: Dictionary) -> void: rejected.append("%d %s" % [reason, str(info.get("text", ""))]))
	s.net_error.connect(func(err_code: int, text: String) -> void:
		if s.phase == NetSession.Phase.IDLE or s.phase == NetSession.Phase.CONNECTING:
			rejected.append("net_error %d %s" % [err_code, text]))
	var rosters: PackedStringArray = DEFAULT_ROSTERS.duplicate()
	if args.extras.has("rosters"):
		rosters = str(args.extras["rosters"]).split(",", false)
	var ui: UiLobbyState = UiLobbyState.create(data)
	var t0: int = Time.get_ticks_msec()
	var lobby_deadline: int = t0 + _int(args, "lobby-timeout-s", 120) * 1000
	var overall: int = t0 + args.timeout_s * 1000
	var next_edit: int = 0
	var reported_lobby: bool = false
	var code: int = 0
	while true:
		await tree.process_frame
		var now: int = Time.get_ticks_msec()
		if not rejected.is_empty():
			_out("APPTEST_END reason=rejected tick=0 detail=%s" % rejected[0])
			code = 4
			break
		if now > overall or (s.phase < NetSession.Phase.LOADING and now > lobby_deadline):
			_out("APPTEST_END reason=timeout tick=%d phase=%d" % [rec.tick, s.phase])
			code = 3
			break
		if rec.failed():
			code = rec.fail_code
			_out("APPTEST_END reason=%s tick=%d" % [rec.fail_reason, rec.tick])
			break
		if s.phase == NetSession.Phase.LOBBY and now >= next_edit and s.lobby.local_slot() >= 0:
			next_edit = now + 500
			if not reported_lobby:
				reported_lobby = true
				_out("APPLAN_LOBBY joined slot=%d peer=%d" % [s.lobby.local_slot(), s.local_peer_id])
				_show_lobby(tree, args)
			UiLobbyNet.pull(s.lobby.state, ui)
			var mine: UiLobbyState.Slot = ui.slots[s.lobby.local_slot()]
			_apply_pick(mine, data, rosters[1 % rosters.size()], 1)
			var ops: Array[Dictionary] = UiLobbyNet.diff(s.lobby.state, ui, UiLobbyNet.Role.CLIENT, s.lobby.local_slot())
			if not ops.is_empty():
				UiLobbyNet.execute(s.lobby, ops)
			elif s.lobby.state.phase == NetProtocol.LobbyPhase.OPEN and not s.lobby.state.slots[s.lobby.local_slot()].ready:
				s.lobby.set_ready(true)
		if rec.reached():
			if not rec.done_sent:
				rec.done_sent = true
				s.send_chat(DONE_TEXT)
				_out("APPTEST_REACHED tick=%d" % rec.target)
			if rec.peer_done or now > rec.reached_at + 30_000:
				await _flush_frames(tree, 10)
				break
	if code == 0 and args.extras.has("lobby-again"):
		code = await _back_to_lobby(tree, rec, s)
	_finish(ctx, rec, s, args.with_ui)
	return code


# ---------------------------------------------------------------- back to the lobby

## `--lobby-again`: after the target tick every human surrenders, the match ends (the AI team wins), and both processes return to
## the lobby the way the end screen's BACK TO THE LOBBY button does: `AppLan.return_to_lobby` (the host sends everybody back, a client
## is back once the host did). Prints `APPLAN_BACK_IN_LOBBY` per process; the host waits until the client reported it as well.
static func _back_to_lobby(tree: SceneTree, rec: Recorder, s: NetSession) -> int:
	var deadline: int = Time.get_ticks_msec() + 40_000
	var surrendered: bool = s.surrender()
	_out("APPLAN_SURRENDER ok=%s phase=%d" % [surrendered, s.phase])
	# a client may jump ENDED -> LOBBY inside one poll when the host's RETURN_TO_LOBBY reached it before its own end of the match
	while s.phase != NetSession.Phase.ENDED and s.phase != NetSession.Phase.LOBBY and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	if s.phase != NetSession.Phase.ENDED and s.phase != NetSession.Phase.LOBBY:
		_out("APPTEST_END reason=no_end tick=%d phase=%d" % [rec.tick, s.phase])
		return 3
	var back: bool = false
	while not back and Time.get_ticks_msec() < deadline:
		back = AppLan.return_to_lobby()
		await tree.process_frame
	if not back:
		_out("APPTEST_END reason=no_lobby tick=%d phase=%d" % [rec.tick, s.phase])
		return 3
	_out("APPLAN_BACK_IN_LOBBY phase=%d humans=%d ready=%d" % [s.phase, s.lobby.state.human_count(), int(s.lobby.state.slots[s.lobby.local_slot()].ready) if s.lobby.local_slot() >= 0 else -1])
	if s.role == NetSession.Role.HOST:
		while not rec.peer_lobby and Time.get_ticks_msec() < deadline:
			await tree.process_frame
	else:
		s.send_chat(LOBBY_TEXT)
		await _flush_frames(tree, 20)
	return 0


# ---------------------------------------------------------------- shared

## `--with-ui`: the LAN lobby screen is on display (headless, dummy renderer), so the flow binding of `AppLan` (lobby -> loading ->
## in-match screens) and the widgets run against the real session while the test drives the lobby through `UiLobbyNet`.
static func _show_lobby(tree: SceneTree, args: AppLaunchArgs) -> void:
	if not args.with_ui:
		return
	var state: Node = tree.root.get_node_or_null("AppState")
	if state != null:
		state.call("go_screen", &"lobby", {"lan": true})
		_out("APPLAN_UI screen=lobby")


## Records the lockstep checksum snapshots (identical on every peer by construction of the tick), the chat handshake and failures.
class Recorder extends RefCounted:
	var session: NetSession = null
	var target: int = 0
	var tick: int = 0
	var rows: Dictionary = {}  ## tick -> [checksum, chain]
	var printed: int = 0
	var peer_done: bool = false
	var peer_lobby: bool = false
	var done_sent: bool = false
	var reached_at: int = 0
	var fail_code: int = 0
	var fail_reason: String = ""
	var desyncs: int = 0
	var stalls: int = 0

	func _init(s: NetSession, p_target: int) -> void:
		session = s
		target = p_target
		s.checksum_observer = _on_checksum
		s.chat_received.connect(_on_chat)
		s.desync_detected.connect(func(_report: Dictionary) -> void:
			desyncs += 1
			fail_code = 5
			fail_reason = "desync")
		s.kicked.connect(func(reason: int, detail: String) -> void:
			if fail_code == 0 and not reached():
				fail_code = 6
				fail_reason = "kicked reason=%d %s" % [reason, detail])
		s.stall_changed.connect(func(waiting: Array) -> void:
			if not waiting.is_empty():
				stalls += 1)
		s.launch_aborted.connect(func(reason: int, detail: String) -> void:
			fail_code = 4
			fail_reason = "launch_aborted reason=%d %s" % [reason, detail])

	func _on_checksum(t: int, checksum: int, chain: int) -> void:
		tick = t
		rows[t] = [checksum & 0xFFFFFFFF, chain & 0xFFFFFFFF]
		while printed + AppLanTestBoot.REPORT_EVERY <= mini(t, target):
			printed += AppLanTestBoot.REPORT_EVERY
			var r: Array = rows.get(printed, [0, 0]) as Array
			var n_cmds: int = session.command_log().cmds.size() if session.command_log() != null else 0
			AppLanTestBoot._out("APPTEST tick=%d chain=%08X checksum=%08X cmds=%d" % [printed, int(r[1]), int(r[0]), n_cmds])
		if t >= target and reached_at == 0:
			reached_at = Time.get_ticks_msec()

	func _on_chat(_channel: int, _from: int, _name: String, text: String) -> void:
		if text == AppLanTestBoot.DONE_TEXT or text == AppLanTestBoot.FIN_TEXT:
			peer_done = true
		elif text == AppLanTestBoot.LOBBY_TEXT:
			peer_lobby = true

	func reached() -> bool:
		return reached_at != 0 and printed >= target

	func failed() -> bool:
		return fail_code != 0


## `keep_ui`: the screens are still on display, so the context stays alive (they read its ports every frame); the sockets close.
static func _finish(ctx: AppMatchContext, rec: Recorder, s: NetSession, keep_ui: bool) -> void:
	var w: SimWorld = ctx.world()
	var st: Dictionary = s.stats()
	var by_pid: Dictionary = {}
	if s.command_log() != null:
		for pid: int in s.command_log().pids:
			by_pid[pid] = int(by_pid.get(pid, 0)) + 1
	var pid_text: PackedStringArray = PackedStringArray()
	for pid_key: Variant in by_pid:
		pid_text.append("%d:%d" % [int(pid_key), int(by_pid[pid_key])])
	pid_text.sort()
	_out("APPTEST_END reason=%s tick=%d" % ["ticks" if rec.reached() else "aborted", mini(rec.tick, rec.target)])
	_out("APPLAN_SUMMARY pid=%d tick=%d cmds=%d ui_cmds=%d stalls=%d stall_ms=%d desyncs=%d delay=%d players=%d final=%08X cmds_by_pid=%s" % [
		s.local_pid, w.tick if w != null else 0, s.command_log().cmds.size() if s.command_log() != null else 0, ctx.commands_sent,
		int(st.get("stall_count", 0)), int(st.get("stall_ms", 0)), rec.desyncs, int(st.get("delay_turns", 0)),
		(s.config().get("players", []) as Array).size(), (w.checksum() & 0xFFFFFFFF) if w != null else 0, ",".join(pid_text)])
	if keep_ui:
		s.shutdown()
	else:
		ctx.dispose()


static func _flush_frames(tree: SceneTree, n: int) -> void:
	for _i: int in n:
		await tree.process_frame


static func _spawn_client(port: int, out_file: String, args: AppLaunchArgs) -> int:
	var head: PackedStringArray = PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--headless", "res://src/app/boot.tscn", "--"])
	if OS.has_feature("template"):
		head = PackedStringArray(["--headless", "--"])  # the EXPORTED app finds its .pck itself (QA2: tools/py/app_two_process.py --binary)
	var argv: PackedStringArray = head + PackedStringArray([
		"--autostart=lan-join=127.0.0.1", "--port=%d" % port, "--out=" + out_file, "--ticks=%d" % (args.ticks if args.ticks > 0 else 3000),
		"--fresh-settings", "--no-audio", "--timeout-s=%d" % args.timeout_s])
	if args.with_ui:
		argv.append("--with-ui")
	for k: Variant in args.extras:
		if ["rosters", "map-seed", "match-seed", "fixed-delay", "governor", "bots", "net-speed", "lobby-timeout-s", "ai", "ai-level", "map-size", "family", "expect-humans", "lobby-again"].has(str(k)):
			argv.append("--%s=%s" % [str(k), str(args.extras[k])])
	DirAccess.remove_absolute(out_file)
	return OS.create_process(OS.get_executable_path(), argv)


## Waits for the child, then re-prints its lines (they carry `role=client`).
static func _collect_child(pid: int, out_file: String) -> int:
	var deadline: int = Time.get_ticks_msec() + 60_000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(20)
	if OS.is_process_running(pid):
		OS.kill(pid)
		_out("APPTEST_END role=client reason=child_timeout tick=0")
		return 3
	var rc: int = OS.get_process_exit_code(pid)
	if FileAccess.file_exists(out_file):
		for line: String in FileAccess.get_file_as_string(out_file).split("\n", false):
			# lint-allow: L006 greppable test-boot protocol lines, parsed by tools/py/app_two_process.py
			print("CLIENT| " + line)
	return rc


static func _int(args: AppLaunchArgs, key: String, fallback: int) -> int:
	return str(args.extras[key]).to_int() if args.extras.has(key) else fallback


static func _out(line: String) -> void:
	var tagged: String = line
	var sp: int = line.find(" ")
	if not line.contains(" role="):
		tagged = (line.substr(0, sp) + " role=" + _role + line.substr(sp)) if sp > 0 else line + " role=" + _role
	# lint-allow: L006 greppable test-boot protocol lines, parsed by tools/py/app_two_process.py
	print(tagged)
	if _file != null:
		_file.store_line(tagged)
		_file.flush()
