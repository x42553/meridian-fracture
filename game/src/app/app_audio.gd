class_name AppAudio
extends RefCounted
## App-side audio wiring (audio spec 3.11, ui.md 5.2): installs the `Snd` facade (as `/root/Snd` when no autoload of that
## name exists), registers the settings sink, hooks the UI widget sounds, and creates `AppAudioFeed`, the per-frame glue that
## hands the running match (world, event batch, camera pose) to the facade. `--no-audio` installs nothing.
## `AppBootHook.run` calls `AppAudio.install(state, store, args)`; everything else is automatic.

static var current: AppAudio = null

var snd: SndManager = null
var feed: AppAudioFeed = null
var ready: bool = false

var _pending_values: Dictionary = {}
var _hooked: Dictionary = {}  ## instance id -> true (widgets already connected)
var _last_hover_ms: int = 0
var _last_tick_ms: int = 0
var _tree: SceneTree = null


## Idempotent. Returns null under `--no-audio` (nothing is created) or when the audio data cannot be used.
static func install(state: Node, store: AppSettingsStore, args: AppLaunchArgs) -> AppAudio:
	if current != null:
		return current
	if args != null and args.no_audio:
		Log.info("app", "audio disabled (--no-audio)")
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var a: AppAudio = AppAudio.new()
	a._tree = tree
	var existing: Node = tree.root.get_node_or_null("Snd")
	if existing is SndManager:
		a.snd = existing as SndManager
	else:
		a.snd = SndManager.new()
		a.snd.name = "Snd"
		tree.root.add_child.call_deferred(a.snd)
	current = a
	if state != null:
		state.set("audio", a)
	AppApply.audio_sink = Callable(a, "on_settings")
	if store != null:
		a._pending_values = AppApply.audio_values(store)
	a._finish.call_deferred()
	return a


## Deferred half of `install`: the manager is in the tree by now.
func _finish() -> void:
	if snd == null:
		return
	if not snd.is_ready() and not snd.setup():
		Log.warn("app", "audio unavailable: the audio data could not be loaded")
		current = null
		return
	if not _pending_values.is_empty():
		snd.apply_values(_pending_values)
		_pending_values = {}
	feed = AppAudioFeed.new()
	feed.name = "AppAudioFeed"
	feed.setup(self, snd)
	_tree.root.add_child(feed)
	_tree.node_added.connect(_on_node_added)
	_hook_existing(_tree.root)
	ready = true
	snd.set_mode(SndManager.MODE_MENU)
	Log.info("app", "audio ready (driver %s)" % AudioServer.get_driver_name())


## One diagnostics line for the headless proof runs (`APPTEST_AUDIO`): voices started / culled, peak concurrent voices, events heard.
func report(game_seconds: float) -> String:
	if snd == null or not snd.is_ready():
		return "audio=off"
	var st: SndStats = snd.stats()
	var v3: int = 0
	var v2: int = 0
	var snap: Dictionary = snd.debug_snapshot()
	v3 = int(snap.get("voices_3d", 0))
	v2 = int(snap.get("voices_2d", 0))
	return "starts=%d culls=%d voices_now=%d/%d voices_per_s=%.2f events_fed=%d music_state=%d" % [st.starts, st.culls, v3, v2,
		float(st.starts) / maxf(game_seconds, 1.0), feed.events_fed if feed != null else 0, int(snap.get("music_state", 0))]


## `AppApply.audio_sink`: the flat `{"audio/master": 70, ..., "access/announcer_tts": false}` values.
func on_settings(values: Dictionary) -> void:
	if snd != null and snd.is_ready():
		snd.apply_values(values)
	else:
		_pending_values = values


func uninstall() -> void:
	if _tree != null and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
	if feed != null and is_instance_valid(feed):
		feed.queue_free()
	if snd != null and is_instance_valid(snd):
		snd.shutdown()
		snd.name = "SndFreed"  # a queued node still owns its name until the frame ends
		snd.queue_free()
	if AppApply.audio_sink.get_object() == self:
		AppApply.audio_sink = Callable()
	ready = false
	if current == self:
		current = null


## Coroutine for every orderly quit: stops the facade and its players, then gives the engine a few frames so the audio thread lets go
## of the playbacks (otherwise `resources still in use at exit` is printed for the music / loop streams, intermittently).
static func release_for_quit(tree: SceneTree) -> void:
	if current != null:
		current.uninstall()
	if tree == null:
		return
	for i: int in 3:
		await tree.process_frame
	OS.delay_msec(40)


# ---------------------------------------------------------------- UI widget sounds

func _hook_existing(n: Node) -> void:
	_on_node_added(n)
	for c: Node in n.get_children():
		_hook_existing(c)


## Menus and dialogs get click / hover / toggle / tab / slider cues without any widget knowing about audio. In-match HUD
## widgets call `UiAudioPort.ui(...)` themselves, so the generic cue is suppressed while the match screen is up.
func _on_node_added(n: Node) -> void:
	if not (n is Control) or _hooked.has(n.get_instance_id()):
		return
	var c: Control = n as Control
	var id: int = c.get_instance_id()
	if c is BaseButton:
		var b: BaseButton = c as BaseButton
		_hooked[id] = true
		if b.toggle_mode:
			b.toggled.connect(_on_toggled.bind(b))
		else:
			b.pressed.connect(_cue.bind(&"snd.ui.click", b))
		b.mouse_entered.connect(_on_hover.bind(b))
	elif c is Range and not (c is ProgressBar):
		_hooked[id] = true
		(c as Range).value_changed.connect(_on_slider.bind(c))
	elif c is TabBar:
		_hooked[id] = true
		(c as TabBar).tab_changed.connect(func(_i: int) -> void: _cue(&"snd.ui.tab", c))
	elif c.has_signal("pressed"):
		_hooked[id] = true
		c.connect("pressed", _cue.bind(&"snd.ui.click", c))
		if c.has_signal("toggled"):
			c.connect("toggled", _on_toggled.bind(c))
		c.mouse_entered.connect(_on_hover.bind(c))
	elif c.has_signal("tab_selected"):
		_hooked[id] = true
		c.connect("tab_selected", func(_i: int, _id: StringName) -> void: _cue(&"snd.ui.tab", c))
	if _hooked.size() > 4096:
		_prune()


func _prune() -> void:
	for k: Variant in _hooked.keys():
		if not is_instance_id_valid(int(k)):
			_hooked.erase(k)


func _in_match() -> bool:
	var state: Node = _tree.root.get_node_or_null("AppState") if _tree != null else null
	if state == null:
		return false
	var flow: Variant = state.get("flow")
	return flow is AppFlow and (flow as AppFlow).mode == AppFlow.Mode.IN_MATCH


## HUD widgets of the running match play their own cues through `ctx.audio`, so the generic cue is skipped for them only: menus,
## dialogs and overlay screens (Options, Field Manual, the Esc menu) opened during a match still get click / hover / slider sounds.
func _cue(id: StringName, src: Control = null) -> void:
	if snd == null or not snd.is_ready():
		return
	if _in_match() and _under_game_screen(src):
		return
	snd.ui(id)


static func _under_game_screen(c: Node) -> bool:
	var n: Node = c
	while n != null:
		if n is UiScreenGame:
			return true
		n = n.get_parent()
	return c == null


func _on_toggled(on: bool, src: Control = null) -> void:
	_cue(&"snd.ui.toggle_on" if on else &"snd.ui.toggle_off", src)


func _on_hover(c: Control) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_hover_ms < 60:
		return
	if c is BaseButton and (c as BaseButton).disabled:
		return
	_last_hover_ms = now
	_cue(&"snd.ui.hover", c)


func _on_slider(_v: float, src: Control = null) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_tick_ms < 70:
		return
	if _in_audio_page(src):
		return  # the Audio page ticks itself after the new volume is applied (UiOptionsPageAudio.audio_port)
	_last_tick_ms = now
	_cue(&"snd.ui.slider_tick", src)


static func _in_audio_page(c: Node) -> bool:
	var n: Node = c
	while n != null:
		if n is UiOptionsPageAudio:
			return (n as UiOptionsPageAudio).audio_port != null
		n = n.get_parent()
	return false
