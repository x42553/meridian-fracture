extends RefCounted
## New input labs (ui.md 10.3 `lab_input2`): exact polling (Alt+Q vs rotate), Ctrl+1, the own double-click detector,
## text-entry gating, modal cancel, focus-regain swallow, edge scroll gating, lost-release polling, orbit, armed modes,
## trackpad gestures and the escape-cancel of a gesture.

const R := preload("res://tests/ui/ui_input_rig.gd")
const H := preload("res://tests/ui/ui_harness.gd")


## Real `Input` state (the polled path): press / release an event and flush the buffered input.
func _poll_key(code: int, mods: int, pressed: bool) -> void:
	var e: InputEventKey = UiKeymap.unpack(code | mods)
	e.keycode = code as Key
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _release_all() -> void:
	Input.action_release(&"cam_rotate_left")
	Input.action_release(&"cam_pan_left")
	Input.action_release(&"card_1")
	Input.flush_buffered_events()


func test_alt_q_is_card_1_not_rotate(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	_poll_key(KEY_Q, KEY_MASK_ALT, true)
	r.reset()
	r.ctl.tick(0.016)
	t.check(not r.evlog.has("rotate(-1)"), "polled exact: Alt+Q does not rotate the camera")
	_poll_key(KEY_Q, KEY_MASK_ALT, false)
	r.key(KEY_Q, KEY_MASK_ALT)
	t.eq(r.evlog, PackedStringArray(["action(card_1)"]), "Alt+Q fires card_1 as an action")
	_poll_key(KEY_Q, 0, true)
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog, PackedStringArray(["rotate(-1)"]), "plain Q rotates left while held")
	_poll_key(KEY_Q, 0, false)
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog.size(), 0, "and stops on release")
	_release_all()
	R.Rig.done(r)


func test_ctrl_1_only_assigns(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.key(KEY_1, KEY_MASK_CTRL)
	r.key(KEY_1)
	r.key(KEY_1, KEY_MASK_SHIFT)
	r.key(KEY_1, KEY_MASK_CTRL | KEY_MASK_SHIFT)
	t.eq(r.evlog, PackedStringArray(["action(group_assign_1)", "action(group_select_1)", "action(group_append_1)", "action(group_add_1)"]),
		"each chord fires exactly its own action")
	r.reset()
	r.key(KEY_S, KEY_MASK_SHIFT)
	t.eq(r.evlog.size(), 0, "Shift+S matches nothing")
	r.key(KEY_PAGEUP)
	r.key(KEY_PAGEDOWN)
	r.key(KEY_EQUAL)
	r.key(KEY_MINUS)
	t.eq(r.evlog, PackedStringArray(["tilt(1)", "tilt(-1)", "zoom(1.00@0,0)", "zoom(-1.00@0,0)"]), "tilt and key zoom map to camera signals")
	R.Rig.done(r)


func test_double_click_detector(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	var base: int = 50000
	var p: Vector2 = Vector2(400.0, 300.0)
	var cases: Array = [[349, 7.0, true, "349 ms / 7 px"], [351, 7.0, false, "351 ms"], [349, 9.0, false, "9 px"], [350, 8.0, true, "350 ms / 8 px (inclusive)"]]
	for c: Array in cases:
		base += 10000
		r.ctl.time_override_ms = base
		r.reset()
		r.motion(p)
		r.btn(p, MOUSE_BUTTON_LEFT, true)
		r.btn(p, MOUSE_BUTTON_LEFT, false)
		r.ctl.time_override_ms = base + int(c[0])
		var p2: Vector2 = p + Vector2(float(c[1]), 0.0)
		r.btn(p2, MOUSE_BUTTON_LEFT, true)
		r.btn(p2, MOUSE_BUTTON_LEFT, false)
		t.eq(r.evlog.size(), 2, "%s: two clicks" % c[3])
		t.eq(r.evlog[1].ends_with(",dbl)"), c[2], "second click is a double: %s" % c[3])
		t.check(not r.evlog[0].contains("dbl"), "the first is single")
	# a third click after a double is a fresh single
	base += 10000
	r.reset()
	for dt: int in [0, 100, 200]:
		r.ctl.time_override_ms = base + dt
		r.btn(p, MOUSE_BUTTON_LEFT, true)
		r.btn(p, MOUSE_BUTTON_LEFT, false)
	t.eq([r.evlog[0].contains("dbl"), r.evlog[1].contains("dbl"), r.evlog[2].contains("dbl")], [false, true, false], "single, double, single")
	# same own unit required when a hit probe is installed
	var hits: Array[int] = [7, 7]
	r.ctl.hit_probe = func(_pos: Vector2) -> int: return hits.pop_front() if not hits.is_empty() else -1
	base += 10000
	r.reset()
	for dt: int in [0, 200]:
		r.ctl.time_override_ms = base + dt
		r.btn(p, MOUSE_BUTTON_LEFT, true)
		r.btn(p, MOUSE_BUTTON_LEFT, false)
	t.check(r.evlog[1].contains("dbl"), "both presses on the same own unit -> double")
	var hits2: Array[int] = [7, 8]
	r.ctl.hit_probe = func(_pos: Vector2) -> int: return hits2.pop_front() if not hits2.is_empty() else -1
	base += 10000
	r.reset()
	for dt: int in [0, 200]:
		r.ctl.time_override_ms = base + dt
		r.btn(p, MOUSE_BUTTON_LEFT, true)
		r.btn(p, MOUSE_BUTTON_LEFT, false)
	t.check(not r.evlog[1].contains("dbl"), "different units -> no double")
	var hits3: Array[int] = [-1, -1]
	r.ctl.hit_probe = func(_pos: Vector2) -> int: return hits3.pop_front() if not hits3.is_empty() else -1
	base += 10000
	r.reset()
	for dt: int in [0, 200]:
		r.ctl.time_override_ms = base + dt
		r.btn(p, MOUSE_BUTTON_LEFT, true)
		r.btn(p, MOUSE_BUTTON_LEFT, false)
	t.check(not r.evlog[1].contains("dbl"), "ground (no own unit) never double-clicks")
	R.Rig.done(r)


func test_text_entry_gating(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	var le := LineEdit.new()
	r.sidebar.add_child(le)
	await H.frames(1)
	le.grab_focus()
	t.check(not r.ctl.keys_ok(), "a focused LineEdit disables the keys")
	Input.action_press(&"cam_pan_left")
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog.size(), 0, "polled camera keys are gated too")
	r.key(KEY_A)
	t.check(not r.evlog.has("action(cmd_attack_move)"), "gameplay keys do not fire while typing")
	le.release_focus()
	t.check(r.ctl.keys_ok(), "after release_focus() gameplay keys work in the same frame")
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog, PackedStringArray(["pan(-1.00,0.00)"]), "the held pan key scrolls again")
	Input.action_release(&"cam_pan_left")
	r.reset()
	r.key(KEY_A)
	t.eq(r.evlog, PackedStringArray(["action(cmd_attack_move)"]))
	r.ctl.enabled_keys = false
	r.reset()
	r.key(KEY_A)
	t.eq(r.evlog.size(), 0, "enabled_keys = false silences keys but not the mouse")
	r.click(r.world)
	t.eq(r.evlog.size(), 1)
	R.Rig.done(r)


func test_modal_and_escape_cancel_a_drag(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.motion(r.world)
	r.btn(r.world, MOUSE_BUTTON_LEFT, true)
	r.motion(Vector2(500.0, 420.0), MOUSE_BUTTON_MASK_LEFT)
	t.check(r.rect.active)
	r.ctl.enabled = false  # a modal opened
	t.check(not r.rect.active and not r.ctl.gesture_active(), "opening a modal cancels the drag")
	r.btn(Vector2(500.0, 420.0), MOUSE_BUTTON_LEFT, false)
	t.eq(r.evlog.size(), 0)
	r.click(r.world, MOUSE_BUTTON_RIGHT)
	t.eq(r.evlog.size(), 0, "a disabled controller ignores the mouse")
	r.ctl.enabled = true
	r.reset()
	r.motion(r.world)
	r.btn(r.world, MOUSE_BUTTON_LEFT, true)
	r.motion(Vector2(500.0, 420.0), MOUSE_BUTTON_MASK_LEFT)
	r.key(KEY_ESCAPE)
	t.check(not r.rect.active and not r.ctl.gesture_active(), "Esc cancels a gesture")
	t.check(not r.evlog.has("action(toggle_menu)"), "and does not also open the game menu")
	r.btn(Vector2(500.0, 420.0), MOUSE_BUTTON_LEFT, false)
	t.eq(r.evlog.size(), 0)
	r.key(KEY_ESCAPE)
	t.eq(r.evlog, PackedStringArray(["action(toggle_menu)"]), "with no gesture Esc is the menu action")
	R.Rig.done(r)


func test_focus_regain_swallows_the_click(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.ctl.time_override_ms = 200000
	r.ctl.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	r.ctl.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	r.reset()
	r.ctl.time_override_ms = 200100
	r.btn(r.world, MOUSE_BUTTON_LEFT, true)
	r.btn(r.world, MOUSE_BUTTON_LEFT, false)
	t.eq(r.evlog.size(), 0, "the click that regains focus starts no gesture")
	r.ctl.time_override_ms = 200400
	r.reset()
	r.click(r.world)
	t.eq(r.evlog.size(), 1, "a later click works")
	R.Rig.done(r)


func test_edge_scroll_gating(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make(Vector2i(1920, 1080))
	r.ctl.edge_scroll = true
	r.ctl.time_override_ms = 300000
	r.motion(Vector2(2.0, 300.0))
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog, PackedStringArray(["pan(-1.00,0.00)"]), "the band at x <= 6 scrolls left")
	t.eq(r.ctl.edge_dir, Vector2(-1.0, 0.0), "the cursor shows the matching arrow")
	r.motion(Vector2(1919.0, 1079.0))
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog, PackedStringArray(["pan(1.00,1.00)"]), "corner: diagonal (not normalised, the rig limits)")
	r.motion(Vector2(960.0, 540.0))
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog.size(), 0, "the middle of the screen does not scroll")
	# focus loss: off; regain: 0.5 s grace
	r.motion(Vector2(2.0, 300.0))
	r.ctl.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog.size(), 0, "edge scroll is off while the window is unfocused")
	r.ctl.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	r.ctl.tick(0.016)
	t.eq(r.evlog.size(), 0, "and for 0.5 s after it regains focus")
	r.ctl.time_override_ms += 501
	r.ctl.tick(0.016)
	t.eq(r.evlog, PackedStringArray(["pan(-1.00,0.00)"]), "then it scrolls again")
	# pointer left the window
	r.ctl.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog.size(), 0, "no scroll once the pointer left the window (its last position is stale)")
	r.motion(Vector2(2.0, 300.0))
	# gesture in progress: off
	r.btn(Vector2(2.0, 300.0), MOUSE_BUTTON_LEFT, true)
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog.size(), 0, "no edge scroll while a click / drag is in progress")
	r.btn(Vector2(2.0, 300.0), MOUSE_BUTTON_LEFT, false)
	# toggle action + modal
	r.key(KEY_E, KEY_MASK_CTRL)
	t.check(not r.ctl.edge_scroll, "Ctrl+E toggles the edge scroll for the session")
	r.ctl.edge_scroll = true
	r.ctl.enabled = false
	r.reset()
	r.ctl.tick(0.016)
	t.eq(r.evlog.size(), 0, "no edge scroll under a modal")
	r.ctl.enabled = true
	r.ctl.edge_scroll_speed = 2.0
	r.ctl.tick(0.016)
	t.eq(r.evlog, PackedStringArray(["pan(-2.00,0.00)"]), "the speed setting scales the band")
	R.Rig.done(r)


func test_lost_release_poll(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.motion(r.world)
	r.btn(r.world, MOUSE_BUTTON_LEFT, true)
	r.ctl.tick(0.016)
	t.check(r.ctl.gesture_active(), "synthetic mode never cancels (pushed events do not update Input)")
	r.ctl.synthetic = false
	r.ctl.tick(0.016)
	t.check(not r.ctl.gesture_active(), "a real controller notices the missing button and cancels")
	r.btn(r.world, MOUSE_BUTTON_LEFT, false)
	t.eq(r.evlog.size(), 0)
	R.Rig.done(r)


func test_orbit_and_zoom_settings(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.btn(r.world, MOUSE_BUTTON_MIDDLE, true)
	r.motion(r.world + Vector2(10.0, 0.0), 0, Vector2(10.0, 4.0))
	t.eq(r.evlog, PackedStringArray(["orbit(-2.20,0.88)"]), "MMB drag: yaw = -rel.x x 0.22, tilt = rel.y x 0.22")
	r.btn(r.world, MOUSE_BUTTON_MIDDLE, false)
	r.reset()
	r.motion(r.world + Vector2(10.0, 0.0), 0, Vector2(10.0, 0.0))
	t.eq(r.evlog.size(), 0, "released: no more orbit")
	r.ctl.invert_orbit = true
	r.ctl.orbit_speed = 2.0
	r.btn(r.world, MOUSE_BUTTON_MIDDLE, true)
	r.motion(r.world, 0, Vector2(10.0, 0.0))
	t.eq(r.evlog, PackedStringArray(["orbit(4.40,-0.00)"]), "speed and inversion")
	r.btn(r.world, MOUSE_BUTTON_MIDDLE, false)
	# toggle mode: click once to start, again to stop
	r.ctl.orbit_toggle = true
	r.reset()
	r.btn(r.world, MOUSE_BUTTON_MIDDLE, true)
	r.btn(r.world, MOUSE_BUTTON_MIDDLE, false)
	t.eq(r.ctl.state, UiInputController.State.ORBIT, "toggle mode keeps orbiting after the release")
	r.btn(r.world, MOUSE_BUTTON_MIDDLE, true)
	t.eq(r.ctl.state, UiInputController.State.IDLE, "the second click stops it")
	r.btn(r.world, MOUSE_BUTTON_MIDDLE, false)
	# zoom
	r.ctl.invert_zoom = true
	r.ctl.zoom_speed = 0.5
	r.reset()
	r.motion(r.world)
	r.btn(r.world, MOUSE_BUTTON_WHEEL_UP, true)
	t.eq(r.evlog, PackedStringArray(["zoom(-0.50@300,300)"]), "zoom speed and inversion")
	# trackpad
	r.ctl.invert_zoom = false
	r.ctl.zoom_speed = 1.0
	r.reset()
	var mg := InputEventMagnifyGesture.new()
	mg.position = Vector2(100.0, 100.0)
	mg.factor = 1.25
	r.vp.push_input(mg)
	var pg := InputEventPanGesture.new()
	pg.position = Vector2(100.0, 100.0)
	pg.delta = Vector2(3.0, -2.0)
	r.vp.push_input(pg)
	t.eq(r.evlog, PackedStringArray(["zoom(2.00@100,100)", "zoom(1.00@100,100)"]), "magnify zooms in; a vertical pan gesture zooms like the wheel (horizontal ignored)")
	R.Rig.done(r)


func test_armed_modes(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.ctl.armed = UiModes.Armed.ATTACK_MOVE
	r.reset()
	r.click(r.world)
	t.eq(r.evlog, PackedStringArray(["armed(300,300,m0)"]), "LMB while armed issues instead of selecting")
	r.reset()
	r.click(r.world, MOUSE_BUTTON_LEFT, KEY_MASK_SHIFT)
	t.eq(r.evlog, PackedStringArray(["armed(300,300,m1)"]), "Shift is carried (queue / keep the mode)")
	r.reset()
	r.motion(r.world)
	r.btn(r.world, MOUSE_BUTTON_LEFT, true)
	r.motion(Vector2(500.0, 420.0), MOUSE_BUTTON_MASK_LEFT)
	t.check(not r.rect.active, "no selection rectangle while armed")
	r.btn(Vector2(500.0, 420.0), MOUSE_BUTTON_LEFT, false)
	t.eq(r.evlog, PackedStringArray(["armed(300,300,m0)"]), "the click position is the press position")
	r.reset()
	r.click(r.world, MOUSE_BUTTON_RIGHT)
	t.eq(r.evlog, PackedStringArray(["cancel_armed"]), "RMB while armed cancels the mode and issues no order")
	r.ctl.armed = UiModes.Armed.NONE
	r.km.os_name = "macOS"
	r.reset()
	r.click(r.world, MOUSE_BUTTON_RIGHT, KEY_MASK_ALT)
	t.eq(r.evlog, PackedStringArray(["ctx(300,300,m2)"]), "Option is the force-fire role on macOS")
	R.Rig.done(r)
