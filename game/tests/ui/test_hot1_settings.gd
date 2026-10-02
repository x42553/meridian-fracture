extends RefCounted
## HOT1: Options rows that nothing applied now reach the live game screen (sticky modes, speed match / reverse, group double-tap centring,
## Esc clears the selection, pause on focus loss, the camera pad and the minimap sweep).

const H := preload("res://tests/ui/ui_harness.gd")
const K := preload("res://tests/ui/test_hot1_keys.gd")


func _rig(k: Object) -> Object:
	var r: Object = k._make_rig(K.MATCH_ROSTERS)
	await k._enter(r)
	k._populate(r, true)
	return r


func test_input_settings_reach_the_screen(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var k: Object = K.new()
	var r: Object = await _rig(k)
	var g: UiScreenGame = r.game
	var store: AppSettingsStore = AppSettingsStore.with_defaults()
	t.check(not g.modes.sticky and not g.bus.move_reverse and not g.bus.move_speed_match, "(setup) the defaults are off")
	for id: StringName in [&"input/sticky_modes", &"input/move_speed_match", &"input/move_reverse", &"input/esc_clears_selection"]:
		store.set_value(id, true)
	store.set_value(&"input/group_double_tap_center", false)
	AppApply.input_sink.call(&"input/sticky_modes", store)
	t.check(g.modes.sticky, "input/sticky_modes keeps modes armed")
	t.check(g.bus.move_speed_match and g.bus.move_reverse, "speed match and reverse reach the command bus")
	# move orders carry the flag bits
	r.select(r.units_a)
	var before: int = r.spy.sent.size()
	g.bus.dispatch(UiContextResolver.resolve(UiSelectionInfo.build(g.selection, r.sim), UiTarget.ground(30 * 1024, 30 * 1024), 0, UiModes.Armed.NONE))
	t.gt(r.spy.sent.size(), before, "(setup) a move order was sent")
	if r.spy.sent.size() > before:
		var cmd: PackedInt32Array = r.spy.sent[r.spy.sent.size() - 1]
		t.check(cmd[0] == SimCmd.MOVE, "it is a MOVE")
		var fi: int = 1 + SimCmd.layout_of(SimCmd.MOVE).find(SimCmd.FT_FLAGS)
		t.check((cmd[fi] & UiCmdCodec.MF_SPEED_MATCH) != 0 and (cmd[fi] & UiCmdCodec.MF_REVERSE) != 0, "with the speed-match and reverse flags")
	# Esc clears the selection instead of opening the menu
	r.select(r.units_a)
	g.escape_chain()
	t.check(g.selection.is_empty() and g._menu == null, "Esc clears the selection first")
	g.escape_chain()
	await H.frames(1)
	t.not_null(g._menu, "and the next Esc opens the menu")
	# the group double tap no longer centres the camera
	r.reset()
	g.groups.assign(1, r.units_a)
	r.away()
	var focus: Vector3 = r.view.focus
	g._on_action(&"group_select_1")
	g._on_action(&"group_select_1")
	t.check(r.view.focus.is_equal_approx(focus), "a double tap on a group does not move the camera when the setting is off")
	store.set_value(&"input/group_double_tap_center", true)
	AppApply.input_sink.call(&"input/group_double_tap_center", store)
	g.groups.double_tap_ms = 10000
	g._on_action(&"group_select_1")
	g._on_action(&"group_select_1")
	t.check(not r.view.focus.is_equal_approx(focus), "and does when it is on")
	await k._leave(r)


func test_pause_on_focus_loss_pauses_a_local_match(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var k: Object = K.new()
	var r: Object = await _rig(k)
	var g: UiScreenGame = r.game
	g._pause_on_focus_loss = true
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	r.until(func() -> bool: return r.ctx.session.is_paused())
	t.check(r.ctx.session.is_paused(), "losing the focus pauses a single-player match")
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	r.until(func() -> bool: return not r.ctx.session.is_paused())
	t.check(not r.ctx.session.is_paused(), "and getting it back resumes")
	g._pause_on_focus_loss = false
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	r.step_ticks(2)
	t.check(not r.ctx.session.is_paused(), "the setting switches it off")
	await k._leave(r)


func test_camera_pad_and_minimap_sweep_follow_the_settings(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var k: Object = K.new()
	var r: Object = await _rig(k)
	var g: UiScreenGame = r.game
	var store: AppSettingsStore = AppSettingsStore.with_defaults()
	store.set_value(&"ui/camera_pad", false)
	store.set_value(&"ui/minimap_sweep", false)
	g._apply_hud_settings(store)
	t.check(not g.hud.sidebar().camera_pad().visible, "ui/camera_pad hides the pad")
	t.check(not g.hud.minimap().sweep_enabled, "ui/minimap_sweep stops the radar sweep")
	store.set_value(&"ui/camera_pad", true)
	store.set_value(&"ui/minimap_sweep", true)
	g._apply_hud_settings(store)
	t.check(g.hud.sidebar().camera_pad().visible and g.hud.minimap().sweep_enabled, "and both come back")
	await k._leave(r)
