extends Node
## Autoload `AppState` (no class_name, ui.md 2.1 / 3.1): the current `AppFlow` mode and overlay stack, the loaded `GameData`,
## the `AppProfile`, the match context and the clean quit. It maps flow modes to screens through `AppScenes` (looked up by
## node path, so the script also loads where the autoloads are not registered yet) and turns screen `navigate` / `back`
## requests into flow transitions. It knows screen ids, never widget classes.

signal mode_changed(mode: int, previous: int)

var flow: AppFlow = AppFlow.new()
## Loaded once at boot; null only in FATAL.
var data: GameData = null
var profile: AppProfile = AppProfile.new()
## `AppMatchContext` (UI-05); null outside LOADING / IN_MATCH / END_SCREEN / REPLAY_PLAYBACK.
var match_ctx: RefCounted = null
## `AppAudio` (UI-05); a no-op until then.
var audio: RefCounted = null
var crash_reporter: AppCrashReporter = AppCrashReporter.new()
## Injectable for tests; defaults to the `/root/AppScenes` autoload.
var scenes: Node = null

var _quit_started: bool = false
var _session: Object = null
var _bound: Array[Array] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _scenes() -> Node:
	if scenes == null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		scenes = tree.root.get_node_or_null("AppScenes") if tree != null else null
		if scenes != null:
			_connect_scenes()
	return scenes


func _connect_scenes() -> void:
	if not scenes.is_connected("navigate_requested", _on_navigate):
		scenes.connect("navigate_requested", _on_navigate)
		scenes.connect("back_requested", _on_back)


## Attaches this state to a scenes node (boot and tests).
func use_scenes(s: Node) -> void:
	scenes = s
	_connect_scenes()


## `AppFlow.go` + `AppScenes.goto(screen id, params)`; overlay modes are pushed. Illegal edges are refused (logged).
func go(mode: int, params: Dictionary = {}) -> void:
	if mode == AppFlow.Mode.QUIT:
		quit_game()
		return
	var previous: int = flow.mode
	if not flow.go(mode, params):
		return
	_show(previous, mode, params)


func push_mode(mode: int, params: Dictionary = {}) -> void:
	var previous: int = flow.mode
	if not flow.push(mode, params):
		return
	_show(previous, mode, params)


func pop_mode() -> void:
	var previous: int = flow.mode
	if flow.pop() < 0:
		return
	var sc: Node = _scenes()
	if sc != null:
		sc.call("pop")
	_set_phase(flow.mode)
	mode_changed.emit(flow.mode, previous)


## Debug/screenshots (`--screen=<id>`): shows a screen directly and sets the mode without checking the edge.
func go_screen(id: StringName, params: Dictionary = {}) -> void:
	var mode: int = AppFlow.mode_of_screen(id, params)
	if mode < 0:
		Log.warn("app", "go_screen: unknown screen '%s'" % id)
		return
	var previous: int = flow.mode
	flow.force(mode, params)
	var sc: Node = _scenes()
	if sc != null:
		sc.call("goto", id, params, true)
	_set_phase(mode)
	mode_changed.emit(mode, previous)


func _show(previous: int, mode: int, params: Dictionary) -> void:
	var sc: Node = _scenes()
	var id: StringName = AppFlow.screen_id_of(mode, params)
	if sc != null and id != &"":
		if AppFlow.is_overlay(mode):
			sc.call("push", id, params)
		else:
			sc.call("goto", id, params, true)
	_set_phase(mode)
	mode_changed.emit(mode, previous)


func _set_phase(mode: int) -> void:
	match mode:
		AppFlow.Mode.BOOT:
			crash_reporter.phase = "boot"
		AppFlow.Mode.SKIRMISH_LOBBY, AppFlow.Mode.LAN_LOBBY, AppFlow.Mode.LAN_BROWSER:
			crash_reporter.phase = "lobby"
		AppFlow.Mode.LOADING:
			crash_reporter.phase = "loading"
		AppFlow.Mode.IN_MATCH, AppFlow.Mode.REPLAY_PLAYBACK:
			crash_reporter.phase = "match"
		AppFlow.Mode.END_SCREEN:
			crash_reporter.phase = "end"
		AppFlow.Mode.FATAL:
			crash_reporter.phase = "fatal"
		AppFlow.Mode.OPTIONS, AppFlow.Mode.CREDITS, AppFlow.Mode.FIELD_MANUAL:
			pass
		_:
			crash_reporter.phase = "menu"


func _on_navigate(target: StringName, params: Dictionary) -> void:
	if target == &"quit":
		quit_game()
		return
	var mode: int = AppFlow.mode_of_screen(target, params)
	if mode < 0:
		Log.warn("app", "navigate: unknown target '%s'" % target)
		return
	if AppFlow.is_overlay(mode):
		push_mode(mode, params)
	else:
		go(mode, params)


func _on_back() -> void:
	if flow.stack_depth() > 0:
		pop_mode()
		return
	var back: int = AppFlow.back_of(flow.mode)
	if back >= 0:
		go(back)


## Wires the session phase signals to navigation (signals that a session lacks are skipped): `match_started` moves LOADING to
## IN_MATCH (with the match context), `launch_aborted` returns to the lobby with the reason, a lost connection leaves the match with
## a message. `match_ended` shows the end screen unless `end_via_screen`: the game screen then shows its result banner first and
## navigates itself. Rebinding replaces the previous session's connections.
func bind_session(session: Object, end_via_screen: bool = false) -> void:
	unbind_session()
	_session = session
	if session == null:
		return
	if session.has_signal("match_started"):
		_bind(session, "match_started", func() -> void:
			if flow.mode == AppFlow.Mode.LOADING:
				go(AppFlow.Mode.IN_MATCH, {"ctx": match_ctx} if match_ctx != null else {}))
	if session.has_signal("launch_aborted"):
		_bind(session, "launch_aborted", func(_reason: Variant = null, detail: Variant = "") -> void:
			if flow.mode != AppFlow.Mode.LOADING:
				return
			if match_ctx is AppMatchContext and (match_ctx as AppMatchContext).mission_id() != "":
				go(AppFlow.Mode.CAMPAIGN, {"error": str(detail)})  # a mission that cannot start goes back to the campaign
			else:
				go(AppFlow.Mode.SKIRMISH_LOBBY, {"role": "local", "error": str(detail)}))
	if session.has_signal("match_ended") and not end_via_screen:
		_bind(session, "match_ended", func(_result: Variant = null) -> void:
			if flow.mode == AppFlow.Mode.IN_MATCH:
				go(AppFlow.Mode.END_SCREEN))
	if session.has_signal("kicked"):
		_bind(session, "kicked", func(_reason: Variant = null, detail: Variant = "") -> void:
			if flow.mode == AppFlow.Mode.IN_MATCH or flow.mode == AppFlow.Mode.LOADING:
				go(AppFlow.Mode.MAIN_MENU, {"message": str(detail)}))


func unbind_session() -> void:
	for c: Array in _bound:
		var obj: Object = c[0] as Object
		if is_instance_valid(obj) and obj.is_connected(c[1] as String, c[2] as Callable):
			obj.disconnect(c[1] as String, c[2] as Callable)
	_bound.clear()
	_session = null


func _bind(obj: Object, sig: String, fn: Callable) -> void:
	obj.connect(sig, fn)
	_bound.append([obj, sig, fn])


## Clean quit: flush the settings, delete the `.session` sentinel, leave the tree.
func quit_game() -> void:
	if _quit_started:
		return
	_quit_started = true
	var tree: SceneTree = get_tree()
	AppShutdown.begin_quit(tree)
	var st: Node = tree.root.get_node_or_null("AppSettings") if tree != null else null
	if st != null:
		st.call("flush")
	if profile.campaign.dirty():
		profile.campaign.save()  # attempts / the last difficulty; results are saved the moment they are recorded
	crash_reporter.end_session()
	if tree != null:
		await AppAudio.release_for_quit(tree)
		AppShutdown.prepare_quit(tree)  # screens exit, the match context / sessions / background work are disposed (the frame's remaining nodes see no screen)
		AppShutdown.release_statics()
		tree.quit()


func _exit_tree() -> void:
	# any orderly leave of the tree (quit, window close) ends the session; a crash or kill -9 leaves the sentinel behind
	crash_reporter.end_session()
	AppShutdown.prepare_quit(get_tree())
	AppShutdown.release_statics()  # the RenderingServer still exists here: caches that own GPU resources go now, not at engine exit


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_CRASH:
			crash_reporter.on_crash()
		NOTIFICATION_WM_CLOSE_REQUEST:
			crash_reporter.end_session()
			if is_inside_tree() and not get_tree().auto_accept_quit:
				quit_game()  # the orderly path (coroutines stop, audio released) instead of the engine's immediate quit
