class_name AppBoot
extends RefCounted
## Boot state machine (ui.md 5.2.1). `AppBoot.run(host)` is called by `boot.gd`; the timeline is:
##   args -> logging (paths, sink, logger, Fp.self_test) -> settings (+ crash sentinel, apply, renderer relaunch) ->
##   ui (fonts, style, theme, layers, SPLASH shown) -> data (`GameData.load_default`) -> services (keymap, cursors, audio,
##   text; soft-linked, skipped while the class does not exist) -> prewarm -> splash minimum -> first screen.
## Every step is timed (`timeline()`, `over_budget()`), so a test can hold the boot to the budgets of 5.2.1. Services and
## classes of later tasks are probed by name (`UiDraw.optional_script`) and called if present, so they plug in without
## edits here. Autoloads are looked up by node path (created from their scripts when the project does not register them).

const SPLASH_MIN_S: float = 1.2
## `{step: budget in ms}` of 5.2.1 (targets on the reference Mac).
const BUDGET_MS: Dictionary = {"args": 1, "logging": 5, "settings": 20, "ui": 35, "data": 270, "services": 70, "prewarm": 2900}

static var last: AppBoot = null
static var sink: AppLogSink = null
static var logger: AppLogger = null

var args: AppLaunchArgs = AppLaunchArgs.new()
var host: Node = null
var selftest_failed: int = 0
var start_ms: int = 0
## Milliseconds after `start_ms` at which the splash was on screen (-1 = not yet).
var splash_ms: int = -1
var unclean: Dictionary = {}
var finished: bool = false
## Set when `GameData.load_default` failed (the FATAL screen was requested).
var fatal: bool = false

var _steps: Array[Dictionary] = []
var _mark_ms: int = 0
var _pending_toasts: Array[Dictionary] = []
var _settings: Node = null
var _scenes: Node = null
var _state: Node = null


## Entry point of the main scene: builds the boot object and runs the timeline.
static func run(host_node: Node) -> void:
	var b: AppBoot = AppBoot.new()
	last = b
	await b.execute(host_node, AppLaunchArgs.parse(OS.get_cmdline_user_args()))


## Milliseconds spent per step (in order): `[{step, ms, budget_ms, at_ms}]`.
func timeline() -> Array[Dictionary]:
	return _steps.duplicate()


## Names of the steps that exceeded `factor` x their budget.
func over_budget(factor: float = 1.0) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for s: Dictionary in _steps:
		var budget: float = float(s["budget_ms"])
		if budget > 0.0 and float(s["ms"]) > budget * factor:
			out.append(String(s["step"]))
	return out


func _mark(step: String) -> void:
	var now: int = Time.get_ticks_msec()
	_steps.append({"step": step, "ms": now - _mark_ms, "budget_ms": int(BUDGET_MS.get(step, 0)), "at_ms": now - start_ms})
	_mark_ms = now


## The whole timeline as a coroutine.
func execute(host_node: Node, launch: AppLaunchArgs) -> void:
	host = host_node
	args = launch
	start_ms = Time.get_ticks_msec()
	_mark_ms = start_ms
	_mark("args")
	_step_logging()
	AppQuitHook.install(host, args)  # `--quit-at-phase` / `--quit-after-ms` (tools/py/quit_stress.py)
	_step_settings()
	if _relaunch_if_needed():
		return
	_step_ui()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	splash_ms = Time.get_ticks_msec() - start_ms
	if not _step_data():
		return
	_step_services()
	await _step_prewarm()
	await _hold_splash()
	await _enter_first_screen()
	finished = true
	Log.info("app", "boot complete in %d ms (splash at %d ms)" % [Time.get_ticks_msec() - start_ms, splash_ms])


# ---------------------------------------------------------------- steps

func _step_logging() -> void:
	AppPaths.ensure_user_dirs()
	if sink == null:
		sink = AppLogSink.new()
		logger = AppLogger.new()
	sink.install()
	logger.install()
	selftest_failed = AppInfo.selftest_failures()
	if selftest_failed > 0:
		Log.error("app", "Fp.self_test: %d check(s) failed" % selftest_failed)
	_mark("logging")


func _step_settings() -> void:
	_settings = _autoload("AppSettings", "res://src/app/app_settings.gd")
	if args.fresh_settings:
		_settings.call("configure", AppPaths.SETTINGS, true)
	var ov: Dictionary = {}
	if args.ui_scale > 0.0:
		ov["video/ui_scale"] = roundi(args.ui_scale * 100.0)
	if not args.palette.is_empty():
		ov["access/colour_mode"] = "cvd" if args.palette == "cvd" else "normal"
	var q_extra: String = str(args.extras.get("quality", ""))
	if q_extra != "":
		ov["video/quality"] = ["low", "medium", "high", "ultra"].find(q_extra) if ["low", "medium", "high", "ultra"].has(q_extra) else q_extra.to_int()
	if args.extras.has("vsync"):
		ov["video/vsync"] = int(str(args.extras["vsync"]))
	if args.extras.has("window"):
		var wh: PackedStringArray = str(args.extras["window"]).split("x")
		if wh.size() == 2:
			ov["video/resolution"] = Vector2i(wh[0].to_int(), wh[1].to_int())
	if args.extras.has("render-scale"):
		ov["video/render_scale"] = float(str(args.extras["render-scale"]))
	_settings.call("set_overrides", ov)
	var store: AppSettingsStore = _settings.get("store") as AppSettingsStore
	for note: String in store.load_notes:
		_pending_toasts.append({"text": "Settings were reset (%s)." % note, "severity": UiToast.Severity.WARN})
	_state = _autoload("AppState", "res://src/app/app_state.gd")
	_open_campaign()
	host.get_tree().auto_accept_quit = false  # a window close / Cmd+Q goes through AppState.quit_game (AppShutdown), never straight to SceneTree.quit
	var reporter: AppCrashReporter = _state.get("crash_reporter") as AppCrashReporter
	reporter.info_provider = _match_info
	AppCrash.reporter = reporter
	if not args.is_test_mode():
		unclean = reporter.start_session()
		if not unclean.is_empty():
			_pending_toasts.append({"text": "The game did not close properly last time.", "severity": UiToast.Severity.WARN,
				"actions": reporter.toast_actions(unclean)})
	AppCrash.settings_digest = "quality=%s renderer=%s ui_scale=%s window_mode=%s" % [store.get_value(&"video/quality"),
		store.get_value(&"video/renderer"), store.get_value(&"video/ui_scale"), store.get_value(&"video/window_mode")]
	_settings.call("apply_all", args.manages_window() and DisplayServer.get_name() != "headless")
	_mark("settings")


## The campaign progress of the profile: `user://campaign.cfg` in normal play, in memory under `--fresh-settings` and every test /
## autostart / screenshot mode (they never touch the real file). `--campaign-progress=id[:seconds[:difficulty]],...` marks missions
## as won (screenshots, tests), `--campaign-unlock` opens every mission.
func _open_campaign() -> void:
	var prof: Variant = _state.get("profile")
	if not (prof is AppProfile):
		return
	var camp: AppCampaign = AppCampaign.new() if (args.fresh_settings or args.is_test_mode()) else AppCampaign.open()
	for note: String in camp.load_notes:
		_pending_toasts.append({"text": "Campaign progress was reset (%s)." % note, "severity": UiToast.Severity.WARN})
	for item: String in str(args.extras.get("campaign-progress", "")).split(",", false):
		var f: PackedStringArray = item.split(":")
		camp.record_result(f[0], true, (f[1].to_int() if f.size() > 1 else 600) * SimConfig.TPS, f[2].to_int() if f.size() > 2 else 1)
	camp.unlock_all = args.extras.has("campaign-unlock")
	(prof as AppProfile).campaign = camp


func _match_info() -> Dictionary:
	var ctx: Variant = _state.get("match_ctx") if _state != null else null
	if ctx is Object and (ctx as Object).has_method("crash_info"):
		return (ctx as Object).call("crash_info") as Dictionary
	return {}


func _relaunch_if_needed() -> bool:
	if args.is_test_mode() or not AppRelaunch.supported():
		return false
	var store: AppSettingsStore = _settings.get("store") as AppSettingsStore
	if not AppRelaunch.needed(store, args):
		return false
	var pid: int = AppRelaunch.relaunch(AppRelaunch.requested_method(store))
	if pid < 0:
		return false
	Log.info("app", "relaunching with renderer '%s'" % AppRelaunch.requested_method(store))
	(_state.get("crash_reporter") as AppCrashReporter).end_session()
	host.get_tree().quit()
	return true


func _step_ui() -> void:
	for role: int in [UiFonts.Role.BODY, UiFonts.Role.BODY_BOLD, UiFonts.Role.HEAD, UiFonts.Role.NUM]:
		UiFonts.get_font(role)
	_call_static_optional(&"UiText", &"load_all", [])
	var skins: UiSkinSet = UiSkinSet.shared()
	var style: Variant = _call_static_optional(&"ViewStyle", &"load_file", [])
	if style is Object:
		skins.setup(style as Object)
	else:
		skins.setup_from_json()
	var skin: UiSkin = skins.skin_for(args.faction) if not args.faction.is_empty() else skins.neutral_skin()
	AppApply.apply_ui(_settings.get("store") as AppSettingsStore, _settings.get("overrides") as Dictionary)
	UiThemeService.rebuild(skin)
	_scenes = _autoload("AppScenes", "res://src/app/app_scenes.gd")
	_scenes.call("ensure_built")
	_state.call("use_scenes", _scenes)
	UiLayout.watch(host.get_window(), func() -> float: return float(_settings.call("get_int", &"video/ui_scale")) / 100.0)
	_scenes.call("set_fps_visible", bool(_settings.call("get_bool", &"ui/show_fps")))
	_scenes.call("goto", &"splash", {}, false)
	var splash: Variant = _scenes.get("screen")
	if splash is Object and (splash as Object).has_method("set_status"):
		(splash as Object).call("set_status", "Starting")
	if logger != null:
		logger.toast_callback = func(text: String, severity: int) -> void: _scenes.call("toast", text, severity)
	_mark("ui")


func _set_splash(text: String, progress: float) -> void:
	var splash: Variant = _scenes.get("screen") if _scenes != null else null
	if splash is Object:
		if (splash as Object).has_method("set_status"):
			(splash as Object).call("set_status", text)
		if (splash as Object).has_method("set_progress"):
			(splash as Object).call("set_progress", progress)


func _step_data() -> bool:
	_set_splash("Loading game data", 0.2)
	var data: GameData = GameData.load_default()
	_state.set("data", data)
	_mark("data")
	if data == null:
		fatal = true
		AppCrash.show(AppCrash.Reason.DATA_LOAD_FAILED, AppCrash.data_failure_detail())
		return false
	_set_splash("Preparing", 0.55)
	return true


func _step_services() -> void:
	var store: AppSettingsStore = _settings.get("store") as AppSettingsStore
	var recovered: Variant = _call_static_optional(&"NetReplay", &"recover_orphans", [])
	if recovered is PackedStringArray and not (recovered as PackedStringArray).is_empty():
		_offer_recovered_replay((recovered as PackedStringArray)[0])
	UiKeymap.instance().load_from(store)  # an instance method: the soft static call never worked
	_call_static_optional(&"UiCursors", &"register_all", [])
	# later modules (audio setup, AppNet wiring) plug in through an optional `AppBootHook.run(state, store, args)`
	_call_static_optional(&"AppBootHook", &"run", [_state, store, args])
	_mark("services")


## The unclean-exit toast gets "Watch recovered replay" when the replay recovery turned the dead run's recording into a playable file.
func _offer_recovered_replay(path: String) -> void:
	for t: Dictionary in _pending_toasts:
		var actions: Variant = t.get("actions", null)
		if actions is Array:
			(actions as Array).append({"label_key": &"ui.crash.watch_replay", "label": "Watch recovered replay",
				"call": func() -> void: _state.call("go", AppFlow.Mode.REPLAYS, {"select": path})})
			return


func _step_prewarm() -> void:
	if not args.no_prewarm and DisplayServer.get_name() != "headless":
		_set_splash("Warming up graphics", 0.7)
		await _call_static_optional(&"UiIconBaker", &"prewarm", [])
	_set_splash("Ready", 1.0)
	_mark("prewarm")


## The splash stays at least `SPLASH_MIN_S` unless a direct screen / autostart / test mode was requested.
func _hold_splash() -> void:
	if args.is_test_mode() or not args.screen.is_empty():
		return
	var left: float = SPLASH_MIN_S - float(Time.get_ticks_msec() - start_ms - maxi(splash_ms, 0)) / 1000.0
	if left > 0.0:
		# a Timer node (not a SceneTreeTimer): freed with the host, so quitting mid-splash releases the suspended coroutine
		var timer: Timer = Timer.new()
		timer.one_shot = true
		timer.wait_time = left
		host.add_child(timer)
		timer.start()
		await timer.timeout
		timer.queue_free()


func _enter_first_screen() -> void:
	if not args.autostart.is_empty():
		var script: Script = UiDraw.optional_script(&"AppTestBoot")
		if script != null:
			await script.call("run", host, args)
			return
		Log.warn("app", "--autostart=%s ignored: AppTestBoot is not available" % args.autostart)
	var params: Dictionary = args.extras.duplicate()
	if params.has("no_help"):
		params["no_help"] = true  # `--no_help`: skip the first-run LAN explainer (screenshots, tools/py/quit_stress.py); the screens read a bool
	if not args.fixture.is_empty():
		params["fixture"] = args.fixture
	var store: AppSettingsStore = _settings.get("store") as AppSettingsStore
	if not args.screen.is_empty():
		if args.screen == &"lobby" and args.extras.has("lan-host"):  # `--screen=lobby --lan-host[=port]`: the LAN host lobby (quit stress, screenshots)
			var port: int = int(str(args.extras["lan-host"])) if str(args.extras["lan-host"]).is_valid_int() else NetProtocol.DEFAULT_PORT
			var host_ctx: AppMatchContext = AppLan.host_lan({"port": port, "advertise": false})
			if host_ctx != null:
				params["lan"] = true
				params["session"] = host_ctx.session
				if args.extras.has("lan-address"):
					params["address_override"] = str(args.extras["lan-address"])  # screenshots: never show the real private address
		_state.call("go_screen", args.screen, params)
	else:
		if bool(store.get_value(&"meta/first_run")):
			params["first_run"] = true
		_state.call("go", AppFlow.Mode.MAIN_MENU, params)
	_flush_toasts()


func _flush_toasts() -> void:
	for t: Dictionary in _pending_toasts:
		var actions: Array[Dictionary] = []
		for a: Variant in t.get("actions", []) as Array:
			actions.append(a as Dictionary)
		_scenes.call("toast", str(t["text"]), int(t["severity"]), actions)
	_pending_toasts.clear()


# ---------------------------------------------------------------- helpers

## The autoload node `name`, or a fresh node from `script_path` added under the root when the project does not register it.
func _autoload(node_name: String, script_path: String) -> Node:
	var root: Window = host.get_tree().root
	var n: Node = root.get_node_or_null(node_name)
	if n == null:
		n = (load(script_path) as GDScript).new() as Node
		n.name = node_name
		root.add_child(n)
	return n


## Calls `cls.method(args)` when the project has that class and static method; null otherwise (a later task plugs in).
func _call_static_optional(cls: StringName, method: StringName, call_args: Array) -> Variant:
	var script: Script = UiDraw.optional_script(cls)
	if script == null:
		return null
	for m: Dictionary in script.get_script_method_list():
		if StringName(m["name"]) == method:
			return script.callv(method, call_args)
	return null


## Restores the engine logging hooks (tests).
static func shutdown_logging() -> void:
	if sink != null:
		sink.uninstall()
	if logger != null:
		logger.uninstall()
