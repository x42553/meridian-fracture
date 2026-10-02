class_name AppReplay
extends RefCounted
## Replay glue of the app (task REP2, ui.md 5.16.3 / 5.16.6, net.md 5.8): starts a playback as an observer match context
## (`start`), the version gate of this build (`local_versions`), the recorded event marks, and the saving of the match just
## played (`save_session`, end screen / desync dialog). Presentation and app code only: playback re-simulates in a world of its
## own and never feeds back into any running session.

## Message of the last failed `start` / `save_session`.
static var last_error: String = ""
static var _local_cache: Dictionary = {}


## The versions of this build as the replay gate compares them (sim, proto, data_hash, data_ids, data_format). Cached.
static func local_versions() -> Dictionary:
	if _local_cache.is_empty():
		var data: GameData = _app_data()
		if data == null:
			data = GameData.load_default()
		if data == null:
			return {}
		_local_cache = NetReplay.local_versions(AppNetSetup.make_options(data, {}))
	return _local_cache.duplicate()


static func release_statics() -> void:
	_local_cache = {}
	last_error = ""


## Starts the playback of a replay (`source` = a path or a loaded `NetReplayData`) as an observer match context: the context is
## registered in `AppState.match_ctx`, handed to `AppNet` for the frame drive, and (opts.bind, default true) the flow moves from
## LOADING to REPLAY_PLAYBACK by itself when the world is ready. null (and `last_error`) when the file cannot be played.
## opts: with_view (default: not headless), bind, title, allow_mismatch, strict, events, local_versions.
static func start(source: Variant, opts: Dictionary = {}) -> AppMatchContext:
	last_error = ""
	var data: NetReplayData = source as NetReplayData if source is NetReplayData else NetReplayData.load_file(str(source))
	if data == null:
		last_error = NetReplayData.last_error
		Log.warn("app", "replay: " + last_error)
		return null
	var headless: bool = DisplayServer.get_name() == "headless"
	var with_view: bool = bool(opts.get("with_view", not headless))
	var app_data: GameData = _app_data()
	if app_data == null:
		app_data = GameData.load_default()
	if app_data == null:
		last_error = "the game data could not be loaded"
		return null
	var ctx: AppMatchContext = AppMatchContext.new()
	ctx.is_replay = true
	ctx.config = data.config
	ctx.local_pid = -1
	ctx.data = app_data
	ctx.title = str(opts.get("title", "Replay"))
	ctx.last_end = _end_of(data)
	var rs: AppReplaySession = AppReplaySession.new()
	var wctx: WeakRef = weakref(ctx)
	var run_opts: Dictionary = {"with_view": with_view, "events": bool(opts.get("events", with_view)),
		"allow_mismatch": bool(opts.get("allow_mismatch", false)), "strict": bool(opts.get("strict", false)),
		"job_sink": func(job: AppMatchJob) -> void:
			var c: AppMatchContext = wctx.get_ref() as AppMatchContext
			if c != null:
				c.job = job}
	if opts.has("local_versions"):
		run_opts["local_versions"] = opts["local_versions"]
	var path: String = str(source) if not (source is NetReplayData) else ""
	if rs.begin(data, path, run_opts) != OK:
		last_error = rs.error_text
		Log.warn("app", "replay: " + last_error)
		return null
	ctx.replay = rs
	rs.ready.connect(func() -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c == null or c.disposed:
			return
		c.build_ports(c.replay.take_stage())  # not `rs`: a lambda that captured the session would keep it alive through its own signal
		if bool(opts.get("bind", true)):
			var st: Node = _autoload("AppState")
			if st != null and int(st.get("flow").get("mode")) == AppFlow.Mode.LOADING:
				st.call("go", AppFlow.Mode.REPLAY_PLAYBACK, {"ctx": c, "replay": true}))
	rs.failed.connect(func(text: String) -> void:
		last_error = text
		var st: Node = _autoload("AppState")
		if bool(opts.get("bind", true)) and st != null and int(st.get("flow").get("mode")) == AppFlow.Mode.LOADING:
			st.call("go", AppFlow.Mode.REPLAYS, {"message": "This replay could not be played: " + text}))
	var net_node: Node = _autoload("AppNet")
	if net_node != null:
		net_node.call("attach", ctx)
	else:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null:
			ctx.driver = AppSessionDriver.new(ctx)
			tree.root.add_child(ctx.driver)
	var state: Node = _autoload("AppState")
	if state != null:
		var old: Variant = state.get("match_ctx")
		if old is AppMatchContext and old != ctx:
			(old as AppMatchContext).dispose()
		state.set("match_ctx", ctx)
	return ctx


## `ctx.last_end` of a replay: the recorded result in the `match_ended` shape.
static func _end_of(data: NetReplayData) -> Dictionary:
	if not data.finalized:
		return {"reason": NetProtocol.MatchEndReason.ABANDONED, "winner_team": -1, "final_tick": data.end_tick(), "final_checksum": 0}
	var e: Dictionary = data.end
	return {"reason": int(e.get("reason", 0)), "winner_team": int(e.get("winner_team", -1)), "final_tick": int(e.get("final_tick", 0)),
		"final_checksum": int(e.get("final_checksum", 0))}


## The recorded events as jump marks: `[{tick, kind: "defeated"|"resigned"|"left"|"chat", pid, text}]` ascending by tick.
static func event_marks(data: NetReplayData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names: Dictionary = {}
	for pv: Variant in data.config.get("players", []) as Array:
		names[int((pv as Dictionary).get("pid", -1))] = str((pv as Dictionary).get("name", ""))
	for ev: Variant in data.events:
		var e: Dictionary = ev as Dictionary
		var tick: int = int(e["turn"]) * NetProtocol.TURN_TICKS
		var args: PackedInt32Array = e["args"] as PackedInt32Array
		match int(e["kind"]):
			NetProtocol.ReplayEvent.PLAYER_STATUS:
				var pid: int = args[0] if args.size() > 0 else -1
				var status: int = args[1] if args.size() > 1 else 0
				var kind: String = ""
				match status:
					NetProtocol.PlayerNetStatus.RESIGNED:
						kind = "resigned"
					NetProtocol.PlayerNetStatus.DEFEATED:
						kind = "defeated"
					NetProtocol.PlayerNetStatus.LEFT, NetProtocol.PlayerNetStatus.DISCONNECTED, NetProtocol.PlayerNetStatus.DROPPED:
						kind = "left"
				if kind != "":
					out.append({"tick": tick, "kind": kind, "pid": pid, "text": "%s %s" % [str(names.get(pid, "Player %d" % (pid + 1))), kind]})
			NetProtocol.ReplayEvent.CHAT:
				var cp: int = args[0] if args.size() > 0 else -1
				out.append({"tick": tick, "kind": "chat", "pid": cp, "text": "%s: %s" % [str(names.get(cp, "?")), str(e["text"])]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tick"]) < int(b["tick"]))
	return out


# ---- saving the match just played --------------------------------------------------------------------------------------

## Whether the finished (or running) session has a recording that can be saved.
static func can_save(session: NetSession) -> bool:
	return session != null and (session.replay_path() != "" or not session.replay_bytes().is_empty())


## Saves the recording of `session` under a display name next to the autosaves: a copy of the autosave file when it exists
## (the recording is final once the match ended), else the memory mirror written to the replay folder. Returns the new path or "".
static func save_session(session: NetSession, display_name: String, dir: String = "") -> String:
	last_error = ""
	if session == null:
		last_error = "no match"
		return ""
	var src: String = session.replay_path()
	if src != "" and FileAccess.file_exists(src) and not src.ends_with(NetReplay.TMP_SUFFIX):
		var copy: String = NetReplay.save_copy(src, display_name)
		if copy == "":
			last_error = "the replay file could not be copied"
		return copy
	var bytes: PackedByteArray = session.replay_bytes()
	if bytes.is_empty():
		last_error = "this match has no recording"
		return ""
	return save_bytes(bytes, display_name, dir)


## Writes replay bytes as `<replay dir>/<sanitised name>.mfreplay` (a numbered suffix on a collision).
static func save_bytes(bytes: PackedByteArray, display_name: String, dir: String = "") -> String:
	var d: String = NetReplay.replay_dir(dir if dir != "" else NetReplay.default_dir())
	var base: String = NetReplay.sanitize_name(display_name)
	var dst: String = "%s/%s.%s" % [d, base, NetReplay.EXT]
	var n: int = 1
	while FileAccess.file_exists(dst):
		n += 1
		dst = "%s/%s_%d.%s" % [d, base, n, NetReplay.EXT]
	var f: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		last_error = "cannot write " + dst
		return ""
	f.store_buffer(bytes)
	f.close()
	return dst


## A default file name for a match: "Map name 2026-10-01 14-03".
static func default_name(config: Dictionary, unix: int = -1) -> String:
	var m: Dictionary = config.get("map", {}) as Dictionary
	var t: int = unix if unix >= 0 else int(Time.get_unix_time_from_system())
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(t)
	var map_name: String = UiMapNames.name_for(int(m.get("family", 0)), int(m.get("seed", 0)))
	return "%s %04d-%02d-%02d %02d-%02d" % [map_name, int(dt["year"]), int(dt["month"]), int(dt["day"]), int(dt["hour"]), int(dt["minute"])]


static func _autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree != null else null


static func _app_data() -> GameData:
	var state: Node = _autoload("AppState")
	if state != null and state.get("data") is GameData:
		return state.get("data") as GameData
	return null
