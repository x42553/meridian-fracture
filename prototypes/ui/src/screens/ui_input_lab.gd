class_name UiInputLab
extends SubViewport
## Scripted experiment (run with --headless): pushes synthetic events through the real GUI pipeline
## (Viewport.push_input) inside a 1280x720 SubViewport (the headless root window is only 64x64) and prints which handler saw them. Every "LAB |" line is an observed fact used in REPORT.md.

var _log: PackedStringArray = PackedStringArray()
var _probing: bool = false
var _hud_root: Control
var _sidebar: PanelContainer
var _button: Button
var _button2: Button
var _label: Label
var _scroll: ScrollContainer
var _ctrl: UiInputController
var _rect: UiSelectRect

func _ready() -> void:
	size = Vector2i(1280, 720)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	UiHotkeys.install()
	_hud_root = Control.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.gui_input.connect(func(e: InputEvent) -> void: _rec_gui("hud_root", e))
	add_child(_hud_root)
	_sidebar = PanelContainer.new()
	_sidebar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_sidebar.offset_left = -300.0
	_sidebar.gui_input.connect(func(e: InputEvent) -> void: _rec_gui("sidebar", e))
	_hud_root.add_child(_sidebar)
	var v := VBoxContainer.new()
	_sidebar.add_child(v)
	_button = Button.new()
	_button.text = "Build"
	_button.pressed.connect(func() -> void: _log.append("button.pressed"))
	_button.gui_input.connect(func(e: InputEvent) -> void: _rec_gui("button", e))
	v.add_child(_button)
	_button2 = Button.new()
	_button2.text = "Sell"
	_button2.focus_mode = Control.FOCUS_ALL
	v.add_child(_button2)
	_label = Label.new()
	_label.text = "Credits 5000"
	v.add_child(_label)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0.0, 200.0)
	var tall := Control.new()
	tall.custom_minimum_size = Vector2(100.0, 900.0)
	_scroll.add_child(tall)
	v.add_child(_scroll)
	_rect = UiSelectRect.new()
	add_child(_rect)
	_ctrl = UiInputController.new()
	_ctrl.select_rect = _rect
	_ctrl.edge_scroll = false
	_ctrl.set_synthetic(true)
	_ctrl.select_box.connect(func(r: Rect2, a: bool) -> void: _log.append("ctrl.select_box(%s,%s)" % [r, a]))
	_ctrl.select_click.connect(func(p: Vector2, a: bool, d: bool) -> void: _log.append("ctrl.select_click(%s)" % p))
	_ctrl.context_order.connect(func(p: Vector2, q: bool) -> void: _log.append("ctrl.context_order(%s)" % p))
	_ctrl.camera_zoom.connect(func(s: float) -> void: _log.append("ctrl.zoom(%s)" % s))
	_ctrl.action_triggered.connect(func(a: StringName) -> void: _log.append("ctrl.action(%s)" % a))
	add_child(_ctrl)
	_run.call_deferred()

# --- recorders ---------------------------------------------------------------------------------------------

func _desc(e: InputEvent) -> String:
	var mb := e as InputEventMouseButton
	if mb != null:
		return "%s %s" % [["?", "LMB", "RMB", "MMB", "wheelUp", "wheelDown"][clampi(mb.button_index, 0, 5)], "down" if mb.pressed else "up"]
	if e is InputEventMouseMotion:
		return "motion"
	var k := e as InputEventKey
	if k != null:
		return "key %s %s" % [OS.get_keycode_string(k.keycode), "down" if k.pressed else "up"]
	return e.get_class()

func _rec_gui(who: String, e: InputEvent) -> void:
	if _probing and not (e is InputEventMouseMotion):
		_log.append("%s.gui_input(%s)" % [who, _desc(e)])

func _input(e: InputEvent) -> void:
	if _probing and not (e is InputEventMouseMotion):
		_log.append("_input(%s)" % _desc(e))

func _unhandled_input(e: InputEvent) -> void:
	if _probing:
		_log.append("_unhandled_input(%s)" % _desc(e))

func _unhandled_key_input(e: InputEvent) -> void:
	if _probing:
		_log.append("_unhandled_key_input(%s)" % _desc(e))

# --- event helpers -------------------------------------------------------------------------------------------

func _motion(p: Vector2, mask: int = 0) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.button_mask = mask
	get_viewport().push_input(m)

func _btn(p: Vector2, index: MouseButton, pressed: bool, shift: bool = false) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = index
	b.pressed = pressed
	b.position = p
	b.global_position = p
	b.shift_pressed = shift
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	get_viewport().push_input(b)

func _key(code: Key, pressed: bool = true, ctrl: bool = false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = pressed
	k.ctrl_pressed = ctrl
	get_viewport().push_input(k)

func _click(p: Vector2, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_motion(p)
	_btn(p, index, true)
	_btn(p, index, false)

func _case(title: String) -> void:
	_log.clear()
	_probing = true
	await get_tree().process_frame

func _end(title: String) -> void:
	_probing = false
	print("LAB | ", title, " | ", ", ".join(_log) if _log.size() > 0 else "(nothing received)")

# --- the experiments -----------------------------------------------------------------------------------------

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var world := Vector2(300.0, 300.0)
	var on_sidebar := Vector2(get_visible_rect().size.x - 150.0, 400.0)
	var on_button: Vector2 = _button.global_position + Vector2(20.0, 10.0)
	var on_label: Vector2 = _label.global_position + Vector2(10.0, 5.0)
	print("LAB | env | viewport=%s sidebar=%s button=%s" % [get_visible_rect().size, _sidebar.get_global_rect(), _button.get_global_rect()])
	for mf in [["STOP (Control default)", Control.MOUSE_FILTER_STOP], ["PASS", Control.MOUSE_FILTER_PASS], ["IGNORE", Control.MOUSE_FILTER_IGNORE]]:
		_hud_root.mouse_filter = mf[1]
		await _case("A")
		_click(world)
		_end("A. full-rect HUD root mouse_filter=%s, LMB click over the 3D world" % mf[0])
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await _case("B")
	_click(on_sidebar)
	_end("B. LMB on sidebar PanelContainer (default STOP), root IGNORE")
	await _case("C")
	_click(on_label)
	_end("C. LMB on a Label (default IGNORE) inside the STOP sidebar")
	await _case("D")
	_click(on_button)
	_end("D. LMB on Button")
	_sidebar.mouse_filter = Control.MOUSE_FILTER_PASS
	await _case("E")
	_click(on_sidebar)
	_end("E. LMB on sidebar switched to PASS")
	_sidebar.mouse_filter = Control.MOUSE_FILTER_STOP
	_ctrl.enabled = false
	await _case("F")
	_motion(world)
	_btn(world, MOUSE_BUTTON_LEFT, true)
	_motion(on_sidebar, MOUSE_BUTTON_MASK_LEFT)
	_btn(on_sidebar, MOUSE_BUTTON_LEFT, false)
	_end("F. NAIVE handling (controller disabled): press in world, move onto sidebar, release over sidebar")
	_ctrl.enabled = false
	await _case("G")
	_motion(on_button)
	_btn(on_button, MOUSE_BUTTON_LEFT, true)
	_motion(world, MOUSE_BUTTON_MASK_LEFT)
	_btn(world, MOUSE_BUTTON_LEFT, false)
	_end("G. press on Button, release in the world (button still gets its up event: implicit mouse grab)")
	_ctrl.enabled = true
	await _case("H")
	_motion(Vector2(200.0, 200.0))
	_btn(Vector2(200.0, 200.0), MOUSE_BUTTON_LEFT, true)
	_motion(Vector2(400.0, 350.0), MOUSE_BUTTON_MASK_LEFT)
	_motion(on_sidebar, MOUSE_BUTTON_MASK_LEFT)
	print("LAB |   (mid-drag) select rect active=%s rect=%s" % [_rect.active, _rect.rect])
	_btn(on_sidebar, MOUSE_BUTTON_LEFT, false)
	_end("H. UiInputController drag-select: press world, drag onto sidebar, release over sidebar")
	await _case("I")
	_click(world)
	_end("I. UiInputController plain click in world")
	await _case("J")
	_click(world, MOUSE_BUTTON_RIGHT)
	_end("J. RMB in world -> context order")
	await _case("K")
	_click(on_sidebar, MOUSE_BUTTON_RIGHT)
	_end("K. RMB over sidebar -> must NOT issue a world order")
	await _case("L")
	_motion(on_sidebar)
	_btn(on_sidebar, MOUSE_BUTTON_WHEEL_UP, true)
	_end("L. wheel over sidebar ScrollContainer (camera zoom must not fire)")
	_sidebar.mouse_force_pass_scroll_events = false
	await _case("L2")
	_motion(on_sidebar)
	_btn(on_sidebar, MOUSE_BUTTON_WHEEL_UP, true)
	_end("L2. wheel over sidebar with mouse_force_pass_scroll_events=false on the sidebar")
	_sidebar.mouse_force_pass_scroll_events = true
	await _case("M")
	_motion(world)
	_btn(world, MOUSE_BUTTON_WHEEL_UP, true)
	_end("M. wheel over world")
	# --- keyboard focus ---
	_button.focus_mode = Control.FOCUS_ALL
	_button.grab_focus()
	await _case("N")
	_key(KEY_RIGHT)
	_end("N. Button focus_mode=ALL and focused: KEY_RIGHT (camera key)")
	await _case("N2")
	_key(KEY_DOWN)
	_end("N2. focused Button with a focusable neighbour below: KEY_DOWN (arrow used by camera / UI focus nav)")
	_button.grab_focus()
	await _case("O")
	_key(KEY_SPACE)
	_key(KEY_SPACE, false)
	_end("O. same focused Button: KEY_SPACE down+up (would 'press' Build!)")
	_button.release_focus()
	_button.focus_mode = Control.FOCUS_NONE
	await _case("P")
	_key(KEY_RIGHT)
	_key(KEY_SPACE)
	_key(KEY_SPACE, false)
	_end("P. Button focus_mode=NONE: KEY_RIGHT + KEY_SPACE")
	await _case("Q")
	_key(KEY_A)
	_end("Q. KEY_A -> action cmd_attack_move")
	await _case("R")
	_key(KEY_TAB)
	_end("R. KEY_TAB after erasing ui_focus_next/prev in UiHotkeys.install()")
	await _case("S")
	_motion(world)
	_btn(world, MOUSE_BUTTON_LEFT, true)
	_motion(Vector2(500.0, 420.0), MOUSE_BUTTON_MASK_LEFT)
	var before: bool = _ctrl.gesture_active
	_ctrl.notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	print("LAB | S. window focus lost mid-drag: gesture_active before=%s after=%s rect_visible_after=%s" % [before, _ctrl.gesture_active, _rect.active])
	_probing = false
	# --- action matching with modifiers ---
	var e1 := InputEventKey.new()
	e1.physical_keycode = KEY_1
	e1.keycode = KEY_1
	e1.pressed = true
	var e2: InputEventKey = e1.duplicate()
	e2.ctrl_pressed = true
	print("LAB | action match | plain '1': select=%s assign=%s | ctrl+'1': select(loose)=%s select(exact)=%s assign=%s" % [e1.is_action(&"group_select_1"), e1.is_action(&"group_assign_1"), e2.is_action(&"group_select_1"), e2.is_action(&"group_select_1", true), e2.is_action(&"group_assign_1")])
	var lay := InputEventKey.new()
	lay.keycode = KEY_A
	lay.pressed = true
	print("LAB | action match | event with keycode only (no physical_keycode) vs physical-bound action cmd_attack_move: ", lay.is_action(&"cmd_attack_move"))
	_motion(on_sidebar)
	print("LAB | hover | after motion over sidebar: ", get_viewport().gui_get_hovered_control().get_class() if get_viewport().gui_get_hovered_control() != null else "null")
	_motion(world)
	print("LAB | hover | after motion over world (root IGNORE): ", get_viewport().gui_get_hovered_control().get_class() if get_viewport().gui_get_hovered_control() != null else "null")
	print("LAB | edge scroll | pointer (2,300) in 1920x1080: ", UiInputController.edge_direction(Vector2(2.0, 300.0), Rect2(0, 0, 1920, 1080)), " | pointer outside window (-40,300): ", UiInputController.edge_direction(Vector2(-40.0, 300.0), Rect2(0, 0, 1920, 1080)), " | corner: ", UiInputController.edge_direction(Vector2(1919.0, 1079.0), Rect2(0, 0, 1920, 1080)))
	get_tree().quit()
