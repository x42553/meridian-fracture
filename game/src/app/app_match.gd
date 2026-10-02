class_name AppMatch
extends RefCounted
## Match glue (ui.md 3.1 / 5.3): default rules, the world builder for sessions, config helpers, the context factory and
## `start_local`, the one call the lobby (and the headless test boot) makes to launch a match.

const MAX_PLAYERS: int = 8
const AI_LEVEL_NAMES: PackedStringArray = ["Easy", "Medium", "Hard", "Brutal"]


## net.md 7.2 defaults.
static func default_rules() -> Dictionary:
	return {"start_credits": SimConfig.DEFAULT_START_CREDITS, "unit_cap": 150, "superweapons": true, "fog": true,
		"shared_vision": false, "veterancy": false, "victory": 1}


## The world builder of a session: a time-sliced `AppMatchJob`. With a view the stage is parented under the scene backdrop.
static func begin_build(config: Dictionary, with_view: bool = true) -> AppMatchJob:
	var data: GameData = _app_data()
	var parent: Node = null
	if with_view:
		var scenes: Node = _autoload("AppScenes")
		if scenes != null:
			scenes.call("clear_backdrop")
			parent = scenes.call("backdrop_host") as Node
	return AppMatchJob.new(config, with_view, data, parent)


## "" = valid (the callable net expects as `opts.map_validator`).
static func validate_map(family: int, size: int, layout_players: int) -> String:
	return MapGenerator.validate_params(family, size, layout_players)


## net's `ai_factory` for callers without a context (tests): a one-off hook, kept alive by the caller through `hook`.
static func make_ai_thinker(hook: AppAiHook, pid: int, level: int, style: int, rng_seed: int) -> Callable:
	return hook.make(pid, level, style, rng_seed)


## Minimal 2-player config on an open map, both sides as given rosters (tests, `--autostart`). `humans` 0..2 leading human slots.
static func simple_config(rosters: PackedStringArray, map_seed: int, size: int = 96, family: int = 0, humans: int = 1) -> Dictionary:
	var players: Array = []
	for i: int in rosters.size():
		var p: Dictionary = {"pid": i, "kind": "human" if i < humans else "ai", "name": "Commander" if i < humans else "Bot %d" % i,
			"roster": rosters[i], "team": i + 1, "color": i, "start": i, "handicap": 100}
		if i >= humans:
			p["ai"] = {"level": 1, "style": 0, "flags": 0}
		players.append(p)
	var slots: int = AppNetSetup.net_layout(rosters.size())
	size = maxi(size, MapGenParams.min_size(slots))
	return {"seed": 20260930 + map_seed, "map": {"family": family, "size": size, "seed": map_seed, "layout_players": slots, "params": {}},
		"rules": default_rules(), "players": players}


## Starts a LOCAL `NetSession` for `config` (UI shape: seed, map, rules, players; `AppNetSetup.complete_config` makes it a net.md 7.1
## MatchConfig), registers the context in `AppState.match_ctx`, hands it to the `AppNet` autoload for polling, and returns it (null
## when the session cannot be created: see `NetSession.last_create_error`, logged). One code path with LAN: the session, the lockstep
## turns, the AI runner and the command log are net's.
## `opts`: with_view (default true unless headless), unpaced, ticks (stop polling at this tick), speed_pct (game speed 50..200),
## discard_events, bind (wire AppState transitions), title, pause_at, player_name.
static func start_local(config: Dictionary, opts: Dictionary = {}) -> AppMatchContext:
	var headless: bool = DisplayServer.get_name() == "headless"
	var with_view: bool = bool(opts.get("with_view", not headless))
	var data: GameData = _app_data()
	if data == null:
		data = GameData.load_default()
	if data == null:
		Log.error("app", "start_local: the game data could not be loaded")
		return null
	var discard: bool = bool(opts.get("discard_events", not with_view))
	if discard and AppAudio.current != null:
		discard = false  # a headless run with audio installed: the audio feed hears the events (and empties the buffer itself)
	var ctx: AppMatchContext = AppMatchContext.new()
	ctx.ai = AppAiHook.new()
	var wctx: WeakRef = weakref(ctx)  # weak: the context owns the session, whose options hold the callables below
	var net_opts: NetSessionOptions = AppNetSetup.make_options(data, {"player_name": opts.get("player_name", _player_name()),
		"with_view": with_view, "unpaced": bool(opts.get("unpaced", false)), "discard_events": discard,
		"events": not discard, "ai": ctx.ai,
		"job_sink": func(job: AppMatchJob) -> void:
			var c: AppMatchContext = wctx.get_ref() as AppMatchContext
			if c != null:
				c.job = job})
	var raw: Dictionary = config.duplicate(true)
	var speed: int = int(opts.get("speed_pct", 0))
	if speed > 0:
		var netblock: Dictionary = (raw.get("net", {}) as Dictionary).duplicate()
		netblock["speed_pct"] = speed
		raw["net"] = netblock
	var full: Dictionary = NetMatchConfig.normalize(AppNetSetup.complete_config(raw, net_opts))
	var session: NetSession = NetSession.local_from_config(net_opts, full)
	if session == null:
		Log.error("app", "start_local: " + NetSession.last_create_error)
		return null
	ctx.session = session
	ctx.config = full  # the session's own config (net.md 7.1) once it exists; the loading screen needs it earlier
	ctx.local_pid = NetMatchConfig.pid_of_peer(ctx.config, 1)
	ctx.title = str(opts.get("title", "Skirmish"))
	ctx.data = data
	ctx.tick_limit = int(opts.get("ticks", 0))
	ctx.pause_at_tick = int(opts.get("pause_at", 0))
	# the ports appear the moment the world is ready, before any listener of match_started runs
	session.match_started.connect(func() -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c != null:
			c.build_ports(c.job.take_stage() if c.job != null else null))
	session.match_ended.connect(func(result: Dictionary) -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c != null:
			c.last_end = result)
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
		if bool(opts.get("bind", true)):
			state.call("bind_session", session, true)
	return ctx


## The `UiScreenEnd` model (ui.md 4.9.2, `UiMatchStats.build`): outcome, winner, duration, per-player stats and score, series. Also
## carries `result` ("victory" | "defeat" | "draw" | "observed" | "left") and `tick` as plain aliases.
static func result_summary(ctx: AppMatchContext, end: Dictionary = {}) -> Dictionary:
	return ctx.summary(end)


static func _player_name() -> String:
	var settings: Node = _autoload("AppSettings")
	return str(settings.call("get_str", &"net/player_name")) if settings != null else "Commander"


static func _autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree != null else null


static func _app_data() -> GameData:
	var state: Node = _autoload("AppState")
	if state != null and state.get("data") is GameData:
		return state.get("data") as GameData
	return null
