extends RefCounted
## The spike's input lab, cases A-S, as asserted facts (ui.md 10.3 `lab_input`): events pushed through the real GUI
## pipeline of a SubViewport reach the right handler. Every `LAB |` note reads like the spike's log.

const R := preload("res://tests/ui/ui_input_rig.gd")
const H := preload("res://tests/ui/ui_harness.gd")


func _note(t: TestCtx, title: String, r: R.Rig) -> void:
	t.note("LAB | %s | %s" % [title, ", ".join(r.evlog) if r.evlog.size() > 0 else "(nothing received)"])


func test_a_hud_root_mouse_filter(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	for mf: Array in [["STOP", Control.MOUSE_FILTER_STOP, 0], ["PASS", Control.MOUSE_FILTER_PASS, 1], ["IGNORE", Control.MOUSE_FILTER_IGNORE, 1]]:
		r.hud.mouse_filter = mf[1] as Control.MouseFilter
		r.reset()
		r.click(r.world)
		_note(t, "A. HUD root %s, LMB over the world" % mf[0], r)
		t.eq(r.evlog.size(), mf[2], "root %s: world clicks reaching the controller" % mf[0])
	r.hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	R.Rig.done(r)


func test_b_to_e_sidebar_clicks(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.click(r.on_sidebar)
	_note(t, "B. LMB on the STOP sidebar", r)
	t.eq(r.evlog.size(), 0, "a STOP panel swallows the click")
	t.check(r.gui_log.has("sidebar.LMB down"), "the sidebar's own gui_input got it")
	r.reset()
	r.click(r.on_label)
	_note(t, "C. LMB on a Label (IGNORE) inside the sidebar", r)
	t.eq(r.evlog.size(), 0)
	t.check(r.gui_log.has("sidebar.LMB down"), "the Label falls through to the panel, never to the world")
	r.reset()
	r.click(r.on_button)
	_note(t, "D. LMB on a Button", r)
	t.eq(r.evlog.size(), 0)
	t.eq(r.pressed_count, 1, "the Button fires once, on release")
	r.sidebar.mouse_filter = Control.MOUSE_FILTER_PASS
	r.reset()
	r.click(r.on_sidebar)
	_note(t, "E. sidebar switched to PASS", r)
	t.eq(r.evlog.size(), 1, "a PASS panel LEAKS clicks to the world")
	r.sidebar.mouse_filter = Control.MOUSE_FILTER_STOP
	R.Rig.done(r)


func test_f_naive_drag_pipeline(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.ctl.enabled = false  # naive handling: only _unhandled_input sees anything
	r.reset()
	r.motion(r.world)
	r.btn(r.world, MOUSE_BUTTON_LEFT, true)
	r.motion(Vector2(400.0, 350.0), MOUSE_BUTTON_MASK_LEFT)
	var before: int = r.probe.motion_unhandled
	r.motion(r.on_sidebar, MOUSE_BUTTON_MASK_LEFT)
	r.btn(r.on_sidebar, MOUSE_BUTTON_LEFT, false)
	t.note("LAB | F. naive handling: motion events reaching _unhandled_input while over the sidebar: %d of 1; release delivered: %s" % [
		r.probe.motion_unhandled - before, r.probe.seen_unhandled.has("LMB up")])
	t.gt(before, 0, "motion over the world reaches _unhandled_input")
	t.check(r.probe.seen_unhandled.has("LMB up"), "a release over the sidebar still reaches a gesture started in the world")
	# the controller does not depend on the answer: it consumes motion in _input, before the GUI (case H)
	R.Rig.done(r)


func test_g_button_grab(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.motion(r.on_button)
	r.btn(r.on_button, MOUSE_BUTTON_LEFT, true)
	r.motion(r.world, MOUSE_BUTTON_MASK_LEFT)
	r.btn(r.world, MOUSE_BUTTON_LEFT, false)
	_note(t, "G. press on Button, release in the world", r)
	t.check(r.gui_log.has("button.LMB up"), "the Button still gets the up event (implicit grab)")
	t.eq(r.evlog.size(), 0, "the world sees nothing")
	R.Rig.done(r)


func test_h_i_drag_select_and_click(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.motion(Vector2(200.0, 200.0))
	r.btn(Vector2(200.0, 200.0), MOUSE_BUTTON_LEFT, true)
	r.motion(Vector2(400.0, 350.0), MOUSE_BUTTON_MASK_LEFT)
	t.check(r.rect.active and r.rect.rect == Rect2(200.0, 200.0, 200.0, 150.0), "the rectangle follows the pointer")
	r.motion(r.on_sidebar, MOUSE_BUTTON_MASK_LEFT)
	t.check(r.rect.active and r.rect.rect.end == r.on_sidebar, "and keeps following over the sidebar (_input consumes the motion)")
	r.btn(r.on_sidebar, MOUSE_BUTTON_LEFT, false)
	_note(t, "H. drag-select: press world, drag onto the sidebar, release there", r)
	t.eq(r.evlog, PackedStringArray(["box(200,200,%d,200,m0)" % (r.on_sidebar.x - 200.0)]), "exactly one select_box")
	t.check(not r.rect.active, "the rectangle hides")
	t.check(not r.gui_log.has("sidebar.LMB up"), "the sidebar never saw the release")
	t.eq(r.ctl.state, UiInputController.State.IDLE)
	r.reset()
	r.click(r.world)
	_note(t, "I. plain click in the world", r)
	t.eq(r.evlog, PackedStringArray(["click(300,300,m0)"]))
	r.reset()
	r.motion(Vector2(200.0, 200.0))
	r.btn(Vector2(200.0, 200.0), MOUSE_BUTTON_LEFT, true, KEY_MASK_SHIFT)
	r.motion(Vector2(230.0, 240.0), MOUSE_BUTTON_MASK_LEFT)
	r.btn(Vector2(230.0, 240.0), MOUSE_BUTTON_LEFT, false, KEY_MASK_SHIFT)
	t.eq(r.evlog, PackedStringArray(["box(200,200,30,40,m1)"]), "Shift + drag adds")
	r.reset()
	r.click(r.world, MOUSE_BUTTON_LEFT, KEY_MASK_SHIFT)
	t.eq(r.evlog, PackedStringArray(["click(300,300,m1)"]), "Shift + click toggles")
	R.Rig.done(r)


func test_j_k_right_click(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.click(r.world, MOUSE_BUTTON_RIGHT)
	_note(t, "J. RMB in the world", r)
	t.eq(r.evlog, PackedStringArray(["ctx(300,300,m0)"]), "issues on press, once")
	r.reset()
	r.click(r.on_sidebar, MOUSE_BUTTON_RIGHT)
	_note(t, "K. RMB over the sidebar", r)
	t.eq(r.evlog.size(), 0, "a world order is never issued from the sidebar")
	r.reset()
	r.click(r.world, MOUSE_BUTTON_RIGHT, KEY_MASK_SHIFT)
	t.eq(r.evlog, PackedStringArray(["ctx(300,300,m1)"]), "Shift is the queue modifier")
	R.Rig.done(r)


func test_l_m_wheel(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.motion(r.on_sidebar)
	r.btn(r.on_sidebar, MOUSE_BUTTON_WHEEL_UP, true)
	_note(t, "L. wheel over the sidebar with the default mouse_force_pass_scroll_events", r)
	t.eq(r.evlog.size(), 1, "default: the wheel zooms the camera THROUGH the panel (the bug)")
	r.sidebar.mouse_force_pass_scroll_events = false
	r.reset()
	r.motion(r.on_sidebar)
	r.btn(r.on_sidebar, MOUSE_BUTTON_WHEEL_UP, true)
	_note(t, "L2. same with mouse_force_pass_scroll_events = false", r)
	t.eq(r.evlog.size(), 0, "HUD panels set it to false: no zoom over the sidebar")
	r.reset()
	r.motion(r.world)
	r.btn(r.world, MOUSE_BUTTON_WHEEL_UP, true)
	r.btn(r.world, MOUSE_BUTTON_WHEEL_DOWN, true)
	_note(t, "M. wheel over the world", r)
	t.eq(r.evlog, PackedStringArray(["zoom(1.00@300,300)", "zoom(-1.00@300,300)"]), "wheel up zooms in")
	R.Rig.done(r)


func test_n_o_p_focus_traps(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	# a focusable Button with a focus neighbour eats arrows and Space (the reason every HUD control is FOCUS_NONE)
	r.button.focus_mode = Control.FOCUS_ALL
	r.button2.focus_mode = Control.FOCUS_ALL
	r.button.grab_focus()
	r.reset()
	r.key(KEY_DOWN)
	_note(t, "N2. focused Button, neighbour below: Down", r)
	t.check(not r.probe.seen_unhandled.has("key Down down"), "the focus neighbour consumes the arrow")
	r.button.grab_focus()
	r.reset()
	r.key(KEY_SPACE)
	t.eq(r.pressed_count, 1, "O. Space presses the focused Build button (a stray 'Build' while playing)")
	r.button.release_focus()
	r.button.focus_mode = Control.FOCUS_NONE
	r.button2.focus_mode = Control.FOCUS_NONE
	r.reset()
	r.key(KEY_RIGHT)
	r.key(KEY_SPACE)
	_note(t, "P. FOCUS_NONE buttons: Right + Space", r)
	t.check(r.probe.seen_unhandled.has("key Right down") and r.probe.seen_unhandled.has("key Space down"), "both reach _unhandled_input")
	t.eq(r.pressed_count, 0, "and no button is pressed")
	t.eq(r.evlog, PackedStringArray(["action(cam_jump_alert)"]), "Space = jump to alert (Right is a polled camera key, not a signal)")
	R.Rig.done(r)


func test_q_r_keys_and_tab(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.key(KEY_A)
	t.eq(r.evlog, PackedStringArray(["action(cmd_attack_move)"]), "Q. A -> cmd_attack_move")
	r.reset()
	r.key(KEY_TAB)
	_note(t, "R. Tab with ui_focus_next erased by install(GAME)", r)
	t.eq(r.evlog, PackedStringArray(["action(tab_next)"]), "Tab reaches the controller (the GUI no longer takes it)")
	r.reset()
	r.key(KEY_TAB, KEY_MASK_SHIFT)
	t.eq(r.evlog, PackedStringArray(["action(tab_prev)"]))
	R.Rig.done(r)


func test_s_focus_loss_cancels_the_drag(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.reset()
	r.motion(r.world)
	r.btn(r.world, MOUSE_BUTTON_LEFT, true)
	r.motion(Vector2(500.0, 420.0), MOUSE_BUTTON_MASK_LEFT)
	t.check(r.ctl.gesture_active() and r.rect.active, "mid-drag")
	r.ctl.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	t.check(not r.ctl.gesture_active() and not r.rect.active, "S. window focus lost: the gesture and the rectangle are gone")
	r.btn(Vector2(500.0, 420.0), MOUSE_BUTTON_LEFT, false)
	t.eq(r.evlog.size(), 0, "nothing is emitted afterwards")
	R.Rig.done(r)


func test_action_matching_facts(t: TestCtx) -> void:
	var e1 := InputEventKey.new()
	e1.physical_keycode = KEY_1
	e1.keycode = KEY_1
	e1.pressed = true
	var e2: InputEventKey = e1.duplicate()
	e2.ctrl_pressed = true
	var r: R.Rig = await R.Rig.make()
	t.check(e1.is_action(&"group_select_1", true) and not e1.is_action(&"group_assign_1", true), "plain 1")
	t.check(e2.is_action(&"group_select_1"), "loose matching: Ctrl+1 ALSO matches the action bound to 1 (the bug)")
	t.check(not e2.is_action(&"group_select_1", true) and e2.is_action(&"group_assign_1", true), "exact_match fixes it")
	var lay := InputEventKey.new()
	lay.keycode = KEY_S
	lay.pressed = true
	t.check(not lay.is_action(&"cmd_stop"), "an event without physical_keycode does not match a physically bound action")
	R.Rig.done(r)


func test_hover_probe(t: TestCtx) -> void:
	var r: R.Rig = await R.Rig.make()
	r.motion(r.on_sidebar)
	t.not_null(r.hovered(), "hover: non-null over the sidebar")
	r.motion(r.world)
	t.is_null(r.hovered(), "hover: null over the world when the root is IGNORE")
	var seen: Array = []
	r.ctl.hover_changed.connect(func(p: Vector2, over: bool) -> void: seen.append([p, over]))
	r.ctl.time_override_ms = 10000
	r.motion(r.on_sidebar)
	r.ctl.tick(0.016)
	t.eq(seen.size(), 1, "hover_changed fires from tick")
	t.eq(seen[0][1], true, "over_ui over the sidebar")
	r.motion(r.world)
	r.ctl.tick(0.016)
	t.eq(seen.size(), 1, "rate limited to 30 Hz (same millisecond)")
	r.ctl.time_override_ms = 10040
	r.ctl.tick(0.016)
	t.eq(seen.size(), 2)
	t.eq(seen[1][1], false, "over_ui false over the world")
	R.Rig.done(r)
