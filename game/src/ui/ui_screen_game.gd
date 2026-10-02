class_name UiScreenGame
extends UiScreen
## The in-game screen (ui.md 3.5 / 5.3 step 8 / 5.5): assembles the ports of an `AppMatchContext` into the playable UI. The 3D
## world is the scene backdrop (`AppViewStage`, built by the loading job); this screen owns the HUD, the selection model,
## control groups, armed modes, the input controller, the command bus and the presenter, and runs the per-frame order of
## ui.md 3.0: events out of the sim -> view -> presenter cadences -> input tick. Every action reaches the sim as a command
## through `UiCommandBus` -> `UiNetPort`; this class never writes sim state.
## Params: `{ctx: AppMatchContext}` (default `AppState.match_ctx`).

const PICK_BOX_UNITS: int = UiViewPort.PICK_UNITS | UiViewPort.PICK_OWN | UiViewPort.PICK_AIR
const BANNER_S: float = 2.5
const CAMERA_ROT_DEG_S: float = 90.0
const PAD_ROTATE_DEG: float = 8.0  ## one press / repeat of the camera pad's rotate buttons
const PAD_TILT_DEG: float = 2.0
const SCREENSHOT_DIR: String = "user://screenshots"
const SCUTTLE_TITLE: String = "SCUTTLE"

var ctx: AppMatchContext = null
var hud: UiHud = null
var presenter: UiHudPresenter = null
var selection: UiSelection = UiSelection.new()
var groups: UiControlGroups = UiControlGroups.new()
var bookmarks: UiBookmarks = UiBookmarks.new()
var modes: UiModes = UiModes.new()
var actions: UiSelectionActions = UiSelectionActions.new()
var feedback: UiFeedback = UiFeedback.new()
var bus: UiCommandBus = UiCommandBus.new()
var placement: UiPlacement = UiPlacement.new()
var targeting: UiTargeting = UiTargeting.new()
var controller: UiInputController = null

var _sim: UiSimPort = null
var _view: UiViewPort = null
var _stage: AppViewStage = null
var _session: NetSession = null
var overlays: UiMatchOverlays = null
## Scripted mission (MIS2): objectives, timers, captions; null in a skirmish.
var mission_hud: UiMissionHud = null
## Observer HUD (replays, all-AI sessions, defeated or surrendered players; task REP2): the controller owns perspective, follow camera
## and the replay transport.
var observer_ctl: UiObserverController = null
var _observer: bool = false
var _replay: AppReplaySession = null
var _last_tick: int = 0
var _frame: int = 0
var _banner: Label = null
var _band: ColorRect = null
var _ending: bool = false
var _defeat_shown: bool = false
var _menu: UiDlgGameMenu = null
var _paused_by_menu: bool = false
var _row: UiEntityRow = UiEntityRow.new()
var _box_ids: PackedInt32Array = PackedInt32Array()
var _preview_left: String = ""
## In-match chat (LAN matches only); null before `enter`.
var chat: UiMatchChat = null
## Tests: `func() -> Image` replaces the viewport texture the screenshot key reads (a headless run has no rendered frame).
var screenshot_source: Callable = Callable()
## The file the last screenshot key press wrote ("" = none yet or it failed).
var last_screenshot: String = ""
## The open scuttle confirmation (tests answer it); null when none.
var scuttle_dialog: UiDlgConfirm = null
## The latest ping the local player placed (sim position), (-1, -1) = none.
var last_ping: Vector2i = Vector2i(-1, -1)

var _group_cursor: int = -1
var _group_double_tap_centres: bool = true  ## input/group_double_tap_center
var _esc_clears_selection: bool = false  ## input/esc_clears_selection
var _pause_on_focus_loss: bool = true  ## input/pause_on_focus_loss
var _paused_by_focus: bool = false
var _automated: bool = false  ## started by `--autostart` (test boots, stress scripts): their windows lose focus all the time, so no focus pause


func _init() -> void:
	super._init()
	screen_id = &"game"
	handles_escape = false


func enter(params: Dictionary) -> void:
	var c: Variant = params.get("ctx", null)
	if not (c is AppMatchContext):
		var state: Node = get_tree().root.get_node_or_null("AppState")
		c = state.get("match_ctx") if state != null else null
	ctx = c as AppMatchContext
	if ctx == null or ctx.sim == null:
		Log.warn("ui", "UiScreenGame.enter: no running match")
		var msg: Label = UiScreenKit.label("No match is running.", &"SubLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
		add_child(msg)
		msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		return
	_automated = AppLaunchArgs.parse(OS.get_cmdline_user_args()).autostart != &""
	_sim = ctx.sim
	_view = ctx.view
	_stage = ctx.stage
	_session = ctx.session
	_replay = ctx.replay
	_observer = ctx.is_observer or ctx.is_replay
	UiThemeService.rebuild(ctx.skin)
	_install_keymap()
	_build_hud()
	_build_logic()
	_build_mission()
	_build_input()
	_build_banner()
	_build_overlays()
	_build_chat()
	_wire_dialogs()
	_wire_settings()
	_last_tick = _sim.tick()
	_preview_left = ctx.preview
	if _replay != null:
		_replay.finished.connect(_on_replay_finished)
		if _replay.player.warning != "":
			var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
			if scenes != null:
				scenes.call("toast", _replay.player.warning, 1)
	set_process(true)
	Log.info("ui", "game screen entered: pid %d, %d players" % [ctx.local_pid, _sim.player_count()])


func exit() -> void:
	set_process(false)
	if controller != null:
		controller.enabled = false
	UiCursors.set_scroll(Vector2i.ZERO)
	UiCursors.set_state(UiCursors.State.DEFAULT)
	_unwire_settings()
	_unwire_chat()
	if _session != null and _session.is_paused() and _paused_by_menu:
		_session.request_pause(false)
	if _replay != null and _paused_by_menu:
		_replay.set_paused(false)
	if overlays != null:
		overlays.release()
	UiKeymap.instance().uninstall(UiKeymap.Context.GAME)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_release_refs()
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes != null:
		scenes.call("clear_backdrop")
	if ctx != null:
		ctx.stage = null
		if ctx.driver != null and is_instance_valid(ctx.driver):
			ctx.driver.queue_free()
			ctx.driver = null


# ---------------------------------------------------------------- construction

## The presenter connects lambdas that capture itself to the models; dropping every connection frees the whole UI graph (and lets a
## new presenter be wired to the same models).
func _disconnect_models() -> void:
	feedback.setup(null, null, null, null)
	bus.setup(null, null, null, null, null)
	for obj: Object in [selection, groups, bookmarks, modes, placement, targeting, feedback, bus, actions]:
		for sig: Dictionary in obj.get_signal_list():
			for conn: Dictionary in obj.get_signal_connection_list(String(sig["name"])):
				(conn["signal"] as Signal).disconnect(conn["callable"] as Callable)


## Breaks the reference cycles of the wiring (presenter -> bus -> feedback -> presenter) so the whole UI graph is freed with the screen.
func _release_refs() -> void:
	_disconnect_models()
	observer_ctl = null
	_sim = null
	_view = null
	_stage = null
	_session = null


## Live settings: the input sink (Options -> Controls / input rows) reconfigures the controller, `ui/range_rings` reaches the presenter.
func _wire_settings() -> void:
	AppApply.input_sink = Callable(self, "_on_input_setting")
	var st: Node = get_tree().root.get_node_or_null("AppSettings")
	if st == null or not (st.get("store") is AppSettingsStore):
		return
	presenter.set_range_ring_mode(int((st.get("store") as AppSettingsStore).get_value(&"ui/range_rings")))
	_apply_hud_settings(st.get("store") as AppSettingsStore)
	_apply_input_settings(st.get("store") as AppSettingsStore)
	if st.has_signal("changed") and not st.is_connected("changed", _on_setting_changed):
		st.connect("changed", _on_setting_changed)


func _on_input_setting(_id: StringName, store: AppSettingsStore) -> void:
	if controller != null and store != null:
		controller.configure(store)
	_apply_input_settings(store)


func _on_setting_changed(id: StringName) -> void:
	if presenter == null or not (id in [&"ui/range_rings", &"ui/camera_pad", &"ui/minimap_sweep"] or String(id).begins_with("input/")):
		return
	var st: Node = get_tree().root.get_node_or_null("AppSettings")
	if st != null and st.get("store") is AppSettingsStore:
		var store: AppSettingsStore = st.get("store") as AppSettingsStore
		presenter.set_range_ring_mode(int(store.get_value(&"ui/range_rings")))
		_apply_hud_settings(store)
		_apply_input_settings(store)


## The order-related Options > Controls rows: sticky modes, speed matching, reversing, double-tap centring and Esc clearing the selection.
func _apply_input_settings(store: AppSettingsStore) -> void:
	if store == null:
		return
	modes.sticky = bool(store.get_value(&"input/sticky_modes"))
	bus.move_speed_match = bool(store.get_value(&"input/move_speed_match"))
	bus.move_reverse = bool(store.get_value(&"input/move_reverse"))
	_group_double_tap_centres = bool(store.get_value(&"input/group_double_tap_center"))
	_esc_clears_selection = bool(store.get_value(&"input/esc_clears_selection"))
	_pause_on_focus_loss = bool(store.get_value(&"input/pause_on_focus_loss"))


## `ui/camera_pad` (the on-screen camera buttons under the minimap) and `ui/minimap_sweep` (the radar sweep line).
func _apply_hud_settings(store: AppSettingsStore) -> void:
	if hud == null or store == null:
		return
	hud.sidebar().camera_pad().visible = bool(store.get_value(&"ui/camera_pad"))
	hud.minimap().sweep_enabled = bool(store.get_value(&"ui/minimap_sweep"))


func _unwire_settings() -> void:
	if AppApply.input_sink.is_valid() and AppApply.input_sink.get_object() == self:
		AppApply.input_sink = Callable()
	var st: Node = get_tree().root.get_node_or_null("AppSettings") if is_inside_tree() else null
	if st != null and st.has_signal("changed") and st.is_connected("changed", _on_setting_changed):
		st.disconnect("changed", _on_setting_changed)


func _install_keymap() -> void:
	var km: UiKeymap = UiKeymap.instance()
	if km.action_ids().is_empty():
		km.load_defaults()
	km.install(UiKeymap.Context.OBSERVER if _observer else UiKeymap.Context.GAME)


func _build_hud() -> void:
	hud = UiHud.new()
	add_child(hud)
	UiLayerRoot.fill(hud)
	hud.setup(ctx.skin, ctx.data, ctx.roster, UiHud.MODE_OBSERVER if _observer else UiHud.MODE_PLAYER)


func _build_logic() -> void:
	modes.audio = ctx.audio
	actions.setup(_sim, _view, selection, null)
	bus.setup(ctx.net, _sim, _view, ctx.audio, feedback)
	placement.setup(_sim, _view, bus, ctx.audio, ctx.roster)
	targeting.setup(_sim, bus, hud.overlay(), ctx.audio, ctx.roster)
	presenter = UiHudPresenter.new()
	presenter.set_modes(modes)
	presenter.auto_place = not AppAiHook.human_is_bot()  # a bot-driven human places its own structures
	presenter.observer = _observer
	presenter.setup_ports(_sim, _view, ctx.audio, ctx.roster, hud, selection, groups, bus, placement, targeting, null)
	feedback.setup(presenter, presenter, ctx.audio, null)
	presenter.menu_requested.connect(open_menu)
	hud.pad_pressed.connect(_on_pad)
	presenter.camera_center_requested.connect(func(x: int, y: int, instant: bool) -> void:
		_free_camera()
		_view.focus_on_sim(x, y, instant))
	selection.changed.connect(func(_m: int) -> void: _view.set_selection(selection.sorted_ids()))
	modes.changed.connect(func(a: int, _prev: int) -> void:
		if controller != null:
			controller.armed = a
		hud.minimap().ping_armed = a == UiModes.Armed.PING)
	hud.minimap().ping_requested.connect(_on_minimap_ping)
	feedback.marker_requested.connect(func(kind: int, x: int, y: int, target: int) -> void: presenter.add_marker(kind, x, y, target))
	presenter.refresh_all()
	if _observer:
		_build_observer(-1 if _replay != null or ctx.local_pid < 0 else ctx.local_pid)


## The mission layer of the HUD (objectives panel, timers, captions) when the match runs a scripted mission (live or replayed).
func _build_mission() -> void:
	mission_hud = null
	if ctx == null or _sim == null or hud == null:
		return
	var mid: String = _sim.mission_id()
	var def: DefMission = AppMission.def_of(ctx.data, mid) if mid != "" else null
	if def == null:
		return
	mission_hud = UiMissionHud.new()
	mission_hud.setup(hud, _sim, ctx.audio, def, _observer)
	mission_hud.camera_hint.connect(func(x: int, y: int, _ticks: int) -> void:
		if _stage == null:
			return  # no view stage (headless run): there is no camera to move
		_free_camera()
		_view.focus_on_sim(x, y, false)
		hud.overlay().add_order_marker(UiOrderIntent.MK_MOVE, x, y))


## The observer controller over the freshly built HUD; a defeated or surrendered player starts on their own perspective.
func _build_observer(default_pid: int) -> void:
	observer_ctl = UiObserverController.new()
	observer_ctl.setup(hud, _sim, _view, _stage, presenter, selection, _replay, default_pid)


## A player who surrendered or was eliminated keeps watching the match (ui.md 5.16.3): the HUD is rebuilt in observer mode on that
## player's own perspective; the match goes on for the others.
func _become_observer(default_pid: int) -> void:
	if _observer or ctx == null or hud == null:
		return
	_observer = true
	_disconnect_models()
	hud.queue_free()
	hud = null
	_install_keymap()
	_build_hud()
	_build_logic()
	_build_mission()
	_on_setting_changed(&"ui/camera_pad")  # the rebuilt HUD takes the pad / sweep settings again
	if observer_ctl != null and default_pid >= 0:
		observer_ctl.set_perspective(default_pid)
	controller.select_rect = hud.select_rect()
	selection.clear()


func _build_input() -> void:
	controller = UiInputController.new()
	controller.name = "InputController"
	add_child(controller)
	controller.select_rect = hud.select_rect()
	controller.hit_probe = func(pos: Vector2) -> int: return _view.pick(pos, UiViewPort.PICK_UNITS | UiViewPort.PICK_OWN)
	var st: Node = get_tree().root.get_node_or_null("AppSettings")
	if st != null and st.get("store") is AppSettingsStore:
		controller.configure(st.get("store") as AppSettingsStore)
	controller.select_box.connect(_on_select_box)
	controller.select_click.connect(_on_select_click)
	controller.context_click.connect(_on_context_click)
	controller.armed_click.connect(_on_armed_click)
	controller.cancel_armed.connect(_on_cancel_armed)
	controller.hover_changed.connect(_on_hover)
	controller.camera_pan.connect(func(dir: Vector2, dt: float) -> void:
		_free_camera()
		_view.pan_screen(dir, dt))
	controller.camera_rotate.connect(func(dir: float, dt: float) -> void: _view.rotate_yaw(dir * CAMERA_ROT_DEG_S * dt))
	controller.camera_tilt.connect(func(deg: float) -> void: _view.tilt(deg))
	controller.camera_orbit.connect(func(yaw: float, tilt_deg: float) -> void:
		_view.rotate_yaw(yaw)
		_view.tilt(tilt_deg))
	controller.camera_zoom.connect(func(steps: float, cursor: Vector2) -> void: _view.zoom_by(steps, cursor))
	controller.action.connect(_on_action)


func _build_banner() -> void:
	_band = ColorRect.new()
	_band.color = Color(0.02, 0.03, 0.05, 0.62)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.visible = false
	add_child(_band)
	_band.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_band.anchor_right = 1.0
	_band.offset_top = -96.0
	_band.offset_bottom = 96.0
	_band.offset_right = -float(UiMetrics.SIDEBAR_W)
	_banner = UiScreenKit.wordmark("", 84, 800, 14, UiPalette.TEXT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_band.add_child(_banner)
	UiLayerRoot.fill(_banner)
	if _session != null:
		_session.match_ended.connect(_on_match_ended)
		_session.player_status_changed.connect(_on_player_status)


## The pause banner, stall overlay and prompt, desync dialog and F3 network overlay (ui.md 5.16.2).
func _build_overlays() -> void:
	if _session == null:
		return
	var names: Dictionary = {}
	for pv: Variant in ctx.config.get("players", []) as Array:
		names[int((pv as Dictionary).get("pid", -1))] = str((pv as Dictionary).get("name", ""))
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	overlays = UiMatchOverlays.new()
	add_child(overlays)
	overlays.setup(_session, names, scenes)
	overlays.leave_requested.connect(leave_match)
	var st: Node = get_tree().root.get_node_or_null("AppSettings")
	if st != null and bool(st.call("get_bool", &"net/show_net_overlay")):
		overlays.net_overlay.set_shown(true)


func _wire_dialogs() -> void:
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes == null:
		return
	var stack: UiDialogStack = scenes.get("dialogs") as UiDialogStack
	if stack != null:
		stack.top_changed.connect(func(_d: UiDialog) -> void: controller.enabled = not stack.has_modal_over_input())


## `--preview=` tags that only need the overlays (no held tick): they fire a moment after the screen appears.
func _overlay_preview_only() -> bool:
	for tag: String in _preview_left.split(",", false):
		if not (tag in ["menu", "stall", "desync", "net", "chat"]):
			return false
	return true


## `--preview=<tags>` (screenshots): `select` = all own military units, `structs` = own structures, `place` = start placing the first
## ready structure, `units` = the units tab, `menu` = the Esc menu, `stall` = stall overlay and prompt, `desync` = the desync dialog, `net` = the F3 overlay,
## `chat` = sample chat lines with the input open.
func _debug_preview(spec: String) -> void:
	for tag: String in spec.split(",", false):
		match tag:
			"select":
				selection.replace(actions.all_military(false), _sim)
			"structs":
				var ids: PackedInt32Array = PackedInt32Array()
				_sim.own_ids(UiSimPort.KM_STRUCTURE, ids)
				selection.replace(ids, _sim)
			"units":
				hud.sidebar().select_tab(UiBuildModel.Tab.INFANTRY, true)
			"vehicles":
				hud.sidebar().select_tab(UiBuildModel.Tab.VEHICLES, true)
			"army":
				_focus_selection()
			"menu":
				open_menu()
			"stall":
				if overlays != null:
					overlays.stall.set_waiting([{"pid": 1, "name": "Bot 1", "reason": NetProtocol.StallReason.DISCONNECTED, "wait_ms": 6500},
						{"pid": 2, "name": "Bot 2", "reason": NetProtocol.StallReason.SLOW_CPU, "wait_ms": 2100}])
					overlays.prompt.set_pids(PackedInt32Array([1, 2]), {1: "Bot 1", 2: "Bot 2"})
			"desync":
				if overlays != null:
					overlays.session.desync_detected.emit({"tick": _sim.tick(), "kind": "SIM", "message": "The sub-checksums that differ: units, economy."})
			"net":
				if overlays != null:
					overlays.net_overlay.set_shown(true)
			"chat":
				chat.add_line(0, 1, "Mara", "Ready when you are.")
				chat.add_line(1, 2, "Jules", "Hold the north ramp, I bring the tanks.")
				chat.add_line(0, 255, "", "Jules lost the connection and the game waits for 10 s.")
				chat.open(true)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if ctx == null or _sim == null:
		return
	_frame += 1
	var records: PackedInt32Array = _sim.take_events()
	var alpha: float = _replay.tick_alpha() if _replay != null else (_session.tick_alpha() if _session != null else 1.0)
	if _stage != null and is_instance_valid(_stage):
		_stage.set_paused((_session != null and _session.is_paused()) or (_replay != null and _replay.is_paused()))
		_stage.frame(delta, alpha, records)
	if _view is UiViewPortWorld:
		(_view as UiViewPortWorld).poll_camera()
	var now: int = _sim.tick()
	presenter.on_events(records)
	if mission_hud != null:
		mission_hud.on_events(records)
	presenter.on_ticks(maxi(now - _last_tick, 0))
	if now != _last_tick and now % 10 == 0:
		selection.prune(_sim)
		_check_local_defeat()
	_last_tick = now
	presenter.on_frame(delta)
	if mission_hud != null:
		mission_hud.on_frame(delta)
	if observer_ctl != null:
		observer_ctl.update(delta)
	controller.tick(delta)
	if _preview_left != "" and (_session == null or _session.is_paused() or _sim.tick() > 6000 or (_frame > 40 and _overlay_preview_only())):
		var spec: String = _preview_left
		_preview_left = ""
		_debug_preview(spec)


# ---------------------------------------------------------------- selection and orders

func _on_select_box(rect: Rect2, mode: int) -> void:
	if targeting.active or placement.active:
		_drag_during_targeting(rect)
		return
	_box_ids.clear()
	if _observer:
		_view.pick_box(rect, UiViewPort.PICK_UNITS | UiViewPort.PICK_AIR | UiViewPort.PICK_OWN | UiViewPort.PICK_ENEMY, _box_ids)
	else:
		_view.pick_box(rect, PICK_BOX_UNITS, _box_ids)
	if _box_ids.is_empty():
		_view.pick_box(rect, UiViewPort.PICK_STRUCTURES | UiViewPort.PICK_OWN | (UiViewPort.PICK_ENEMY if _observer else 0), _box_ids)
	if mode == 1:
		selection.add(_box_ids, _sim)
	else:
		selection.replace(_box_ids, _sim)
	_say_selected()


## A drag while a power is being aimed or a structure placed never selects: a line power takes the press point as its start and the
## release point as its direction; anything else acts on the release point.
func _drag_during_targeting(rect: Rect2) -> void:
	if targeting.active and targeting.is_line():
		var a: Vector2i = presenter.ground_sim_at(rect.position)
		var b: Vector2i = presenter.ground_sim_at(rect.end)
		if a.x >= 0 and b.x >= 0:
			targeting.press(a.x, a.y)
			targeting.update(b.x, b.y)
			targeting.release(b.x, b.y)
		return
	presenter.world_press(rect.end, MOUSE_BUTTON_LEFT)


func _on_select_click(pos: Vector2, mode: int, dbl: bool) -> void:
	if presenter.world_press(pos, MOUSE_BUTTON_LEFT):
		return
	var eid: int = _view.pick(pos, UiViewPort.PICK_ANY)
	if eid < 0 or not _sim.read(eid, _row):
		if mode == 0:
			selection.clear()
		return
	var own: bool = _row.owner == _sim.viewer_pid()
	if dbl and own and _row.kind == UiEntityRow.K_UNIT:
		_sync_playfield()
		selection.replace(actions.same_type_on_screen(UiSimPort.KIND_UNIT, _row.def_idx), _sim)
	elif mode == 1 and own:
		selection.toggle(eid, _sim)
	else:
		selection.replace(PackedInt32Array([eid]), _sim)
	_say_selected()


## The selection response of the active unit / structure ("Yes sir", the structure hum): own selections only.
func _say_selected() -> void:
	if ctx == null or ctx.audio == null or selection.is_empty() or selection.mode == UiSelection.Mode.FOREIGN:
		return
	ctx.audio.unit_selected(selection.active_def, selection.mode == UiSelection.Mode.STRUCTURES, selection.size())


func _resolve_and_dispatch(pos: Vector2, mods: int, armed: int) -> int:
	var tgt: UiTarget = UiContextResolver.make_target(_sim, _view, pos, _sim.viewer_pid())
	var info: UiSelectionInfo = UiSelectionInfo.build(selection, _sim)
	var m: int = modes.effective_mods((UiContextResolver.MOD_QUEUE if (mods & UiKeymap.MOD_SHIFT) != 0 else 0)
		| (UiContextResolver.MOD_FORCE if (mods & UiKeymap.MOD_CTRL) != 0 else 0))
	return bus.dispatch(UiContextResolver.resolve(info, tgt, m, armed))


func _on_context_click(pos: Vector2, mods: int) -> void:
	if _observer:
		return  # an observer gives no orders
	if presenter.world_press(pos, MOUSE_BUTTON_RIGHT):
		return
	_resolve_and_dispatch(pos, mods, UiModes.Armed.NONE)


func _on_armed_click(pos: Vector2, mods: int) -> void:
	if presenter.world_press(pos, MOUSE_BUTTON_LEFT):
		return
	if modes.armed == UiModes.Armed.PING:
		var g: Vector2i = presenter.ground_sim_at(pos)
		if g.x >= 0:
			do_ping(g.x, g.y)
			modes.consume((mods & UiKeymap.MOD_SHIFT) != 0)
		return
	var armed: int = modes.armed
	if _resolve_and_dispatch(pos, mods, armed) > 0:
		modes.consume((mods & UiKeymap.MOD_SHIFT) != 0)


func _on_cancel_armed() -> void:
	if not presenter.cancel_modes():
		modes.disarm()


func _on_hover(pos: Vector2, over_ui: bool) -> void:
	if over_ui:
		_view.set_hover(-1)
		presenter.set_hover_entity(0)
		UiCursors.set_state(UiCursors.State.DEFAULT)
		return
	presenter.world_motion(pos)
	var over: int = _view.pick(pos, UiViewPort.PICK_ANY)
	_view.set_hover(over)
	presenter.set_hover_entity(over)
	UiCursors.set_state(hover_cursor(pos))


## The cursor (`UiCursors.State`) for the pointer over the world: the armed mode, the placement / power targeting state, else the
## intent the right click would issue for the current selection (move, attack, repair, capture, select, inspect ...).
func hover_cursor(pos: Vector2) -> int:
	if placement.active:
		return UiCursors.State.PLACE_OK if placement.valid or placement.cell.x < 0 else UiCursors.State.PLACE_BAD
	if targeting.active:
		return UiCursors.State.SUPERWEAPON if targeting.kind == UiTargeting.Kind.SUPERWEAPON else UiCursors.State.POWER
	match modes.armed:
		UiModes.Armed.ATTACK_MOVE:
			return UiCursors.State.ATTACK_MOVE
		UiModes.Armed.GUARD:
			return UiCursors.State.GUARD
		UiModes.Armed.SELL:
			return UiCursors.State.SELL
		UiModes.Armed.REPAIR:
			return UiCursors.State.REPAIR
		UiModes.Armed.RALLY:
			return UiCursors.State.RALLY
		UiModes.Armed.FORCE_FIRE:
			return UiCursors.State.FORCE_FIRE
		UiModes.Armed.POWER:
			return UiCursors.State.POWER
		UiModes.Armed.SUPERWEAPON:
			return UiCursors.State.SUPERWEAPON
		UiModes.Armed.MOVE, UiModes.Armed.PATROL, UiModes.Armed.FOLLOW:
			return UiCursors.State.MOVE
		UiModes.Armed.ABILITY:
			return UiCursors.State.ATTACK
		UiModes.Armed.PING:
			return UiCursors.State.DEFAULT
	var tgt: UiTarget = UiContextResolver.make_target(_sim, _view, pos, _sim.viewer_pid())
	var info: UiSelectionInfo = UiSelectionInfo.build(selection, _sim)
	return UiContextResolver.cursor_for(UiContextResolver.resolve(info, tgt, modes.effective_mods(0), UiModes.Armed.NONE))


# ---------------------------------------------------------------- keymap actions

func _on_action(id: StringName) -> void:
	if _observer:
		if observer_ctl != null and observer_ctl.handle_action(id):
			return
		if id == &"obs_pause" and _session != null:
			_session.request_pause(not _session.is_paused())
			return
	var n: int = UiActions.indexed(id, "group_select_")
	if n >= 0:
		var ids: PackedInt32Array = groups.recall(n, _sim)
		if not ids.is_empty():
			selection.replace(ids, _sim)
		if groups.register_press(n, Time.get_ticks_msec()) and _group_double_tap_centres:
			var c: Vector2i = groups.centroid_sim(n, _sim)
			if c.x >= 0:
				_view.focus_on_sim(c.x, c.y)
		return
	n = UiActions.indexed(id, "group_assign_")
	if n >= 0:
		groups.assign(n, selection.sorted_ids())
		return
	n = UiActions.indexed(id, "group_add_")
	if n >= 0:
		groups.add_to(n, selection.sorted_ids())
		return
	n = UiActions.indexed(id, "group_append_")
	if n >= 0:
		selection.add(groups.recall(n, _sim), _sim)
		return
	n = UiActions.indexed(id, "cam_bookmark_set_")
	if n >= 1:
		bookmarks.set_slot(n - 1, _view.camera_state())
		return
	n = UiActions.indexed(id, "cam_bookmark_")
	if n >= 1:
		_view.set_camera_state(bookmarks.get_slot(n - 1))
		return
	n = UiActions.indexed(id, "power_")
	if n >= 1:
		presenter.press_power_slot(n - 1)
		return
	n = UiActions.indexed(id, "cmd_ability_")
	if n >= 1:
		presenter.press_ability_hotkey(n - 1)
		return
	n = UiActions.indexed(id, "card_5x_")
	if n >= 1:
		presenter.press_card_slot(n - 1, true)
		return
	n = UiActions.indexed(id, "card_")
	if n >= 1:
		presenter.press_card_slot(n - 1, false)
		return
	match id:
		&"cmd_attack_move":
			hud.command_pressed.emit(&"attack_move")
		&"cmd_guard":
			hud.command_pressed.emit(&"guard")
		&"cmd_patrol":
			hud.command_pressed.emit(&"patrol")
		&"cmd_follow":
			hud.command_pressed.emit(&"follow")
		&"cmd_stop":
			hud.command_pressed.emit(&"stop")
		&"cmd_scatter":
			hud.command_pressed.emit(&"scatter")
		&"cmd_hold":
			hud.command_pressed.emit(&"hold")
		&"cmd_deploy":
			hud.command_pressed.emit(&"deploy")
		&"cmd_stance_cycle":
			hud.command_pressed.emit(&"stance")
		&"cmd_return":
			hud.command_pressed.emit(&"return")
		&"cmd_unload":
			hud.command_pressed.emit(&"unload")
		&"tool_repair":
			hud.tool_pressed.emit(&"repair")
		&"tool_sell":
			hud.tool_pressed.emit(&"sell")
		&"tool_rally":
			hud.tool_pressed.emit(&"rally")
		&"tool_waypoint":
			hud.tool_pressed.emit(&"waypoint")
		&"place_rotate":
			placement.rotate(1)
		&"sel_all_military":
			selection.replace(actions.all_military(false), _sim)
		&"sel_all_military_screen":
			_sync_playfield()
			selection.replace(actions.all_military(true), _sim)
		&"sel_idle_next":
			_select_one(actions.next_idle(1))
		&"sel_idle_prev":
			_select_one(actions.next_idle(-1))
		&"sel_collector_next":
			_select_one(actions.next_collector())
		&"sel_producer_next":
			_select_one(actions.next_producer())
		&"sel_hq", &"cam_center_base":
			_select_one(actions.hq(), id == &"cam_center_base")
		&"cam_center_selection":
			_focus_selection()
		&"cam_reset":
			_view.reset_camera_orientation()
		&"pause_game":
			if _session != null:
				_session.request_pause(not _session.is_paused())
		&"toggle_net_overlay":
			if overlays != null:
				overlays.toggle_net_overlay()
		&"toggle_menu":
			escape_chain()
		&"open_field_manual":
			open_field_manual()
		&"toggle_objectives":
			if mission_hud != null:
				mission_hud.toggle_objectives()
		&"superweapon":
			presenter.press_superweapon()
		&"cam_jump_alert":
			presenter.jump_to_alert()
		&"cmd_move":
			hud.command_pressed.emit(&"move")
		&"cmd_force_fire_mode":
			hud.command_pressed.emit(&"force_fire")
		&"cmd_ping":
			arm_ping()
		&"cmd_scuttle":
			ask_scuttle()
		&"sel_same_screen":
			select_same_type(true)
		&"sel_same_map":
			select_same_type(false)
		&"sel_group_next":
			select_next_group()
		&"sel_subgroup_next":
			selection.cycle_subgroup(1)
		&"tab_next":
			hud.sidebar().cycle_tab(1)
		&"tab_prev":
			hud.sidebar().cycle_tab(-1)
		&"hide_ui":
			hud.set_chrome_visible(not hud.chrome_visible())
		&"chat_all":
			open_chat(false)
		&"chat_team":
			open_chat(true)
		&"screenshot":
			take_screenshot()
		&"toggle_fullscreen":
			toggle_fullscreen()


## Manual camera input ends the follow camera of the observer HUD (the free camera).
func _free_camera() -> void:
	if observer_ctl != null and observer_ctl.follow:
		observer_ctl.set_follow(false)


func _select_one(eid: int, focus_only: bool = false) -> void:
	if eid <= 0 or not _sim.read(eid, _row):
		return
	if not focus_only:
		selection.replace(PackedInt32Array([eid]), _sim)
	_view.focus_on_sim(_row.x, _row.y)


func _focus_selection() -> void:
	var ids: PackedInt32Array = selection.sorted_ids()
	if ids.is_empty():
		return
	var sx: int = 0
	var sy: int = 0
	var n: int = 0
	for id: int in ids:
		if _sim.read(id, _row):
			sx += _row.x
			sy += _row.y
			n += 1
	if n > 0:
		_view.focus_on_sim(sx / n, sy / n)


# ---------------------------------------------------------------- hotkey actions (HOT1)

## The playfield the "on screen" selections measure against (the world area not covered by the sidebar).
func _sync_playfield() -> void:
	if hud != null and hud.size.x > 0.0:
		actions.playfield = hud.playfield_rect()


## T / Ctrl+T: every own unit (or structure) of the active subgroup type on the screen / on the map.
func select_same_type(on_screen: bool) -> bool:
	if selection.mode != UiSelection.Mode.UNITS and selection.mode != UiSelection.Mode.STRUCTURES:
		presenter.notice("Select one of your own units or structures first.")
		return false
	var kind: int = UiSimPort.KIND_STRUCTURE if selection.mode == UiSelection.Mode.STRUCTURES else UiSimPort.KIND_UNIT
	var ids: PackedInt32Array
	if on_screen:
		_sync_playfield()
		ids = actions.same_type_on_screen(kind, selection.active_def)
	else:
		ids = actions.same_type_on_map(kind, selection.active_def)
	if ids.is_empty():
		return false
	selection.replace(ids, _sim)
	_say_selected()
	return true


## Ctrl+G: selects the next assigned control group (wraps); false when none is assigned.
func select_next_group() -> bool:
	var from: int = _group_cursor
	for _k: int in UiControlGroups.COUNT:
		var i: int = groups.next_nonempty(from)
		if i < 0:
			break
		from = i
		var ids: PackedInt32Array = groups.recall(i, _sim)
		if ids.is_empty():
			continue
		_group_cursor = i
		selection.replace(ids, _sim)
		_say_selected()
		return true
	presenter.notice("No control group is assigned (Ctrl+1 to Ctrl+0).")
	return false


## Ctrl+Delete: scuttles the selected units after a confirmation (they leave no wreck).
func ask_scuttle() -> bool:
	if _observer:
		return false
	var ids: PackedInt32Array = selection.sorted_ids() if selection.mode == UiSelection.Mode.UNITS else PackedInt32Array()
	if ids.is_empty():
		presenter.notice("Select units to scuttle (structures are sold with Delete).")
		return false
	var n: int = ids.size()
	scuttle_dialog = UiDlgConfirm.ask(SCUTTLE_TITLE, "Scuttle %d unit%s? They leave no wreck." % [n, "" if n == 1 else "s"],
		func(yes: bool) -> void:
			scuttle_dialog = null
			if yes and _sim != null:
				bus.simple(UiOrderIntent.Kind.SCUTTLE, ids),
		"Scuttle", "Cancel", true)
	return true


## J: the next click on the world or the minimap pings it (toggles when pressed again).
func arm_ping() -> void:
	if modes.armed == UiModes.Armed.PING:
		modes.disarm()
	else:
		modes.arm(UiModes.Armed.PING)


## Places a ping: a marker for the local player at once, relayed to the teammates of a LAN match (`NetProtocol.Msg.MAP_PING`).
func do_ping(sim_x: int, sim_y: int) -> void:
	last_ping = Vector2i(sim_x, sim_y)
	bus.ping(sim_x, sim_y)
	presenter.show_ping(sim_x, sim_y, false)


func _on_minimap_ping(norm: Vector2) -> void:
	var s: Vector2i = hud.minimap().norm_to_sim(norm)
	do_ping(s.x, s.y)
	modes.disarm()


## A teammate's ping (the host relays MAP_PING to the sender's team only).
func _on_map_ping(from_pid: int, cell_x: int, cell_y: int) -> void:
	if presenter == null or (ctx != null and from_pid == ctx.local_pid):
		return
	presenter.show_ping(cell_x * 1024 + 512, cell_y * 1024 + 512, true)
	if ctx != null and ctx.audio != null:
		ctx.audio.ui(UiAudioPort.MINIMAP_PING)


## The camera pad under the minimap: the same view calls as the camera keys.
func _on_pad(id: StringName) -> void:
	_free_camera()
	match id:
		&"rotate_left":
			_view.rotate_yaw(-PAD_ROTATE_DEG)
		&"rotate_right":
			_view.rotate_yaw(PAD_ROTATE_DEG)
		&"tilt_up":
			_view.tilt(PAD_TILT_DEG)
		&"tilt_down":
			_view.tilt(-PAD_TILT_DEG)
		&"zoom_in":
			_view.zoom_by(1.0, hud.playfield_rect().get_center())
		&"zoom_out":
			_view.zoom_by(-1.0, hud.playfield_rect().get_center())
		&"centre_base":
			_select_one(actions.hq(), true)
		&"jump_alert":
			presenter.jump_to_alert()


# ---------------------------------------------------------------- chat, screenshot, fullscreen

func _build_chat() -> void:
	chat = UiMatchChat.new()
	chat.name = "MatchChat"
	add_child(chat)
	chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat.offset_left = 14.0
	chat.offset_bottom = -float(UiMetrics.LOG_BOTTOM + UiMetrics.LOG_MAX * 20 + 12)
	var st: Node = get_tree().root.get_node_or_null("AppSettings") if is_inside_tree() else null
	if st != null:
		chat.apply_settings(int(st.call("get_int", &"ui/chat_fade_s")), int(st.call("get_int", &"ui/chat_opacity")))
	chat.submitted.connect(func(text: String, team_only: bool) -> void:
		if ctx != null and ctx.net != null:
			ctx.net.send_chat(text, team_only))
	if _session != null:
		_session.chat_received.connect(_on_chat_received)
		_session.map_ping.connect(_on_map_ping)


func _unwire_chat() -> void:
	if _session == null:
		return
	if _session.chat_received.is_connected(_on_chat_received):
		_session.chat_received.disconnect(_on_chat_received)
	if _session.map_ping.is_connected(_on_map_ping):
		_session.map_ping.disconnect(_on_map_ping)


func _on_chat_received(channel: int, from_pid: int, from_name: String, text: String) -> void:
	if chat != null:
		chat.add_line(channel, from_pid, from_name, text)


## Enter / Shift+Enter: opens the chat input in a LAN match. A single-player match, a replay and the observer of one have nobody
## to talk to, so the key says so instead of opening a box that goes nowhere.
func open_chat(team_only: bool) -> bool:
	if chat == null:
		return false
	if _replay != null or _session == null or _session.role == NetSession.Role.LOCAL:
		presenter.notice("Chat is only available in LAN matches.")
		return false
	chat.open(team_only)
	return true


## Print: the current frame (the viewport texture) as a PNG under `user://screenshots/`. Returns the file ("" = failed).
func take_screenshot() -> String:
	var img: Image = null
	if screenshot_source.is_valid():
		img = screenshot_source.call() as Image
	elif is_inside_tree() and get_viewport() != null and DisplayServer.get_name() != "headless":
		var tex: ViewportTexture = get_viewport().get_texture()
		img = tex.get_image() if tex != null else null
	last_screenshot = ""
	if img == null or img.is_empty():
		presenter.notice("Screenshot is not available here.", UiPalette.WARN)
		return ""
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = "%s/meridian_%s_%d.png" % [SCREENSHOT_DIR, stamp, Time.get_ticks_msec() % 100000]
	if img.save_png(path) != OK:
		presenter.notice("Could not write the screenshot.", UiPalette.WARN)
		return ""
	last_screenshot = path
	presenter.notice("Screenshot saved: %s" % ProjectSettings.globalize_path(path), UiPalette.OK)
	return path


## Alt+Enter: windowed <-> fullscreen (the setting is saved, so Options shows the same state).
func toggle_fullscreen() -> void:
	var st: Node = get_tree().root.get_node_or_null("AppSettings") if is_inside_tree() else null
	if st == null:
		return
	var full: bool
	if DisplayServer.get_name() == "headless":
		full = int(st.call("get_int", &"video/window_mode")) != 0
	else:
		var m: int = DisplayServer.window_get_mode()
		full = m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	st.call("set_value", &"video/window_mode", 0 if full else 1)
	if st.get("store") is AppSettingsStore:
		AppApply.apply_video(st.get("store") as AppSettingsStore)  # the stored mode may already equal the target while the window is not there


# ---------------------------------------------------------------- escape chain and menu

## `input/pause_on_focus_loss`: a single-player match pauses while the window is in the background and resumes when it is back
## (a pause the player set themselves stays).
func _notification(what: int) -> void:
	if _session == null or _replay != null or _automated or not _pause_on_focus_loss or _session.role != NetSession.Role.LOCAL:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _session.is_paused() and not _ending:
		_paused_by_focus = _session.request_pause(true) == NetProtocol.PauseError.OK
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _paused_by_focus:
		_paused_by_focus = false
		if _session.is_paused() and not _paused_by_menu:
			_session.request_pause(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and is_visible_in_tree() and not _ending:
		escape_chain()
		get_viewport().set_input_as_handled()


## 5.5.7: cancel placement / targeting / armed mode, else clear the selection (setting), else toggle the game menu.
func escape_chain() -> void:
	if _menu != null:
		return
	if chat != null and chat.is_open():
		chat.close()
		return
	if presenter.cancel_modes():
		return
	if modes.armed != UiModes.Armed.NONE or modes.waypoint_latch:
		modes.disarm()
		modes.clear_latch()
		return
	if _esc_clears_selection and not selection.is_empty():
		selection.clear()
		return
	open_menu()


func open_menu() -> void:
	if _menu != null or _ending:
		return
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes == null or (_session == null and _replay == null):
		return
	if _replay != null:
		_open_replay_menu(scenes)
		return
	var local_match: bool = _session.role == NetSession.Role.LOCAL
	var pause_pref: bool = true
	var st: Node = get_tree().root.get_node_or_null("AppSettings")
	if st != null:
		pause_pref = bool(st.call("get_bool", &"input/pause_on_menu"))
	_paused_by_menu = local_match and pause_pref and not _session.is_paused() and _session.request_pause(true) == NetProtocol.PauseError.OK
	if overlays != null:
		overlays.banner_suppressed = true
	_menu = UiDlgGameMenu.new(local_match and pause_pref, ctx.local_pid >= 0 and _session.player_status(ctx.local_pid) == NetProtocol.PlayerNetStatus.ACTIVE)
	_menu.closed.connect(_on_menu_closed)
	scenes.call("modal", _menu)


## The Esc menu of a replay: Resume, Options, Field Manual, Leave replay (no surrender); the playback pauses while it is open.
func _open_replay_menu(scenes: Node) -> void:
	var pause_pref: bool = true
	var st: Node = get_tree().root.get_node_or_null("AppSettings")
	if st != null:
		pause_pref = bool(st.call("get_bool", &"input/pause_on_menu"))
	_paused_by_menu = pause_pref and not _replay.is_paused()
	if _paused_by_menu:
		_replay.set_paused(true)
	_menu = UiDlgGameMenu.new(pause_pref, false, true)
	_menu.closed.connect(_on_menu_closed)
	scenes.call("modal", _menu)


func _on_menu_closed(result: int) -> void:
	_menu = null
	if _replay != null:
		if _paused_by_menu and result != UiDlgGameMenu.RESULT_LEAVE:
			_replay.set_paused(false)
		_paused_by_menu = false
		match result:
			UiDlgGameMenu.RESULT_LEAVE:
				leave_match()
			UiDlgGameMenu.RESULT_OPTIONS:
				navigate.emit(&"options", {})
			UiDlgGameMenu.RESULT_MANUAL:
				open_field_manual()
		return
	if overlays != null:
		overlays.banner_suppressed = false
		if _session != null and _session.is_paused() and not _paused_by_menu:
			overlays.banner.visible = true
	var to_overlay: bool = result == UiDlgGameMenu.RESULT_OPTIONS or result == UiDlgGameMenu.RESULT_MANUAL
	if _paused_by_menu and _session != null and result != UiDlgGameMenu.RESULT_LEAVE and not to_overlay:
		_session.request_pause(false)
	if to_overlay and _paused_by_menu:
		_resume_when_back()  # a LOCAL match stays paused while Options / the Field Manual are open
	else:
		_paused_by_menu = false
	match result:
		UiDlgGameMenu.RESULT_SURRENDER:
			bus_surrender()
		UiDlgGameMenu.RESULT_LEAVE:
			leave_match()
		UiDlgGameMenu.RESULT_OPTIONS:
			navigate.emit(&"options", {})
		UiDlgGameMenu.RESULT_MANUAL:
			open_field_manual()


## The Field Manual overlay on the local roster (F1, the Esc menu entry). No-op while the menu dialog is up or an overlay is open.
func open_field_manual() -> void:
	var p: Dictionary = {}
	if ctx != null and ctx.roster != null:
		p["roster_id"] = ctx.roster.id
	navigate.emit(&"field_manual", p)


## Resumes the pause the menu holds once the flow is back in the match (the pushed screen was popped).
func _resume_when_back() -> void:
	var state: Node = get_tree().root.get_node_or_null("AppState")
	if state == null:
		_paused_by_menu = false
		return
	var holder: Array[Callable] = [Callable()]
	holder[0] = func(mode: int, _previous: int) -> void:
		if mode != AppFlow.Mode.IN_MATCH:
			return  # the push of Options itself also announces a mode change
		state.disconnect("mode_changed", holder[0])
		if _paused_by_menu:
			_paused_by_menu = false
			if _session != null:
				_session.request_pause(false)
	state.connect("mode_changed", holder[0])


func bus_surrender() -> void:
	ctx.net.surrender()


## Abandons the match (LOCAL: back to the main menu; LAN: the host resigns the player).
func leave_match() -> void:
	if _replay != null:
		navigate.emit(&"replays", {})  # the replay browser disposes the playback
		return
	if _session != null:
		_session.leave()
		var saved: String = _session.replay_path()
		if saved != "" and not saved.ends_with(NetReplay.TMP_SUFFIX):
			var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
			if scenes != null:
				scenes.call("toast", "Match recorded. Find it under Replays (last match).", 0)
	navigate.emit(&"campaign" if ctx != null and ctx.mission_id() != "" else &"main_menu", {})


# ---------------------------------------------------------------- end of match

## The recorded end of a replay was reached: a short banner (the replay bar offers REPLAY to start over).
func _on_replay_finished() -> void:
	if _ending or _banner == null:
		return
	var tw: Tween = _show_banner("REPLAY ENDED", UiPalette.TEXT, 1.6)
	tw.tween_property(_band, "modulate:a", 0.0, 0.5)

## The local player left the running game (surrender, elimination, drop): a banner, the match goes on for the others.
func _on_player_status(pid: int, status: int) -> void:
	if ctx == null or pid != ctx.local_pid or _ending:
		return
	match status:
		NetProtocol.PlayerNetStatus.RESIGNED:
			_show_banner("YOU HAVE SURRENDERED", UiPalette.semantic(&"warn"), 3.0)
			_become_observer(pid)
		NetProtocol.PlayerNetStatus.DEFEATED:
			_show_banner("YOU HAVE BEEN DEFEATED", UiPalette.semantic(&"danger"), 3.0)
			_become_observer(pid)


## Elimination by lost assets is not announced by net (only resignations are): read the status now and then.
func _check_local_defeat() -> void:
	if _defeat_shown or _ending or _session == null or ctx.local_pid < 0:
		return
	if _session.player_status(ctx.local_pid) == NetProtocol.PlayerNetStatus.DEFEATED:
		_defeat_shown = true
		_on_player_status(ctx.local_pid, NetProtocol.PlayerNetStatus.DEFEATED)


func _show_banner(text: String, col: Color, hold_s: float) -> Tween:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.add_theme_color_override("font_shadow_color", Color(col, 0.4))
	_band.visible = true
	_band.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(_band, "modulate:a", 1.0, 0.4)
	tw.tween_interval(hold_s)
	return tw


## The banner text and colour of a finished match for the local player.
static func end_banner(outcome: int, reason: int) -> Array:
	match outcome:
		UiMatchStats.OUTCOME_VICTORY:
			return ["VICTORY", UiPalette.semantic(&"ok")]
		UiMatchStats.OUTCOME_DEFEAT:
			return ["DEFEAT", UiPalette.semantic(&"danger")]
		UiMatchStats.OUTCOME_DRAW:
			return ["DRAW", UiPalette.TEXT]
	if reason == NetProtocol.MatchEndReason.DESYNC:
		return ["DESYNC", UiPalette.semantic(&"danger")]
	return ["MATCH ENDED", UiPalette.TEXT]


func _on_match_ended(result: Dictionary) -> void:
	if _ending:
		return
	_ending = true
	var summary: Dictionary = ctx.summary(result)
	var look: Array = end_banner(int(summary["outcome"]), int(result.get("reason", 0)))
	var params: Dictionary = {"summary": summary}
	if ctx.mission_id() != "":
		var model: Dictionary = AppMission.result_model(ctx, summary)
		params["mission"] = model
		look = ["MISSION COMPLETE" if bool(model["won"]) else "MISSION FAILED", look[1]]
	var tw: Tween = _show_banner(str(look[0]), look[1] as Color, BANNER_S)
	for tag: String in ctx.preview.split(",", false):
		if tag.begins_with("tab_"):
			params["tab"] = tag.substr(4)  # `--preview=tab_graphs` opens the end screen on that tab (screenshots)
	tw.tween_callback(func() -> void: navigate.emit(&"end", params))
