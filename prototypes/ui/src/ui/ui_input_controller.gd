class_name UiInputController
extends Node
## World-input state machine for an RTS. The pattern (each rule verified by src/screens/ui_input_lab.gd):
##  * gestures START in _unhandled_input  -> a click on any STOP Control (sidebar, buttons) never starts a drag
##  * once a gesture is active, _input sees every event BEFORE the GUI and consumes it -> the rectangle keeps
##    following the pointer over the sidebar (the GUI swallows motion there) and the HUD never sees the release
##  * _process polls Input for the button state -> a lost release (focus loss, alt-tab, OS dialog) can't stick
##  * keyboard scrolling uses polled actions (never ui_* actions); edge scrolling requires window focus.
## Outputs are signals only; the receiver turns them into SimCommands.

signal select_box(rect: Rect2, additive: bool)
signal select_click(pos: Vector2, additive: bool, double: bool)
signal context_order(pos: Vector2, queued: bool)
signal camera_pan(direction: Vector2, delta: float)
signal camera_rotate(direction: float, delta: float)
signal camera_zoom(step: float)
signal action_triggered(action: StringName)

const DRAG_THRESHOLD := 6.0
const EDGE_MARGIN := 6.0

var select_rect: UiSelectRect
var enabled: bool = true
var edge_scroll: bool = true
## Set by the game while a command mode (sell/repair/attack-move) is armed; LMB then issues instead of selecting.
var armed_command: StringName = &""
var _pressing: bool = false
var _dragging: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _additive: bool = false
var gesture_active: bool:
	get:
		return _pressing

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressing = true
					_dragging = false
					_press_pos = mb.position
					_additive = mb.shift_pressed
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					context_order.emit(mb.position, mb.shift_pressed)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				camera_zoom.emit(-1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				camera_zoom.emit(1.0)
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		for a in [&"cmd_attack_move", &"cmd_guard", &"cmd_stop", &"cmd_scatter", &"cmd_deploy", &"cmd_sell", &"cmd_repair", &"cmd_waypoint", &"cam_center_base", &"cam_jump_alert", &"select_all_type", &"toggle_menu", &"chat_open"]:
			if event.is_action_pressed(a):
				action_triggered.emit(a)
				get_viewport().set_input_as_handled()
				return

## Runs before the GUI: only reacts while a world gesture is in progress.
func _input(event: InputEvent) -> void:
	if not _pressing:
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if not _dragging and mm.position.distance_to(_press_pos) >= DRAG_THRESHOLD:
			_dragging = true
		if _dragging and select_rect != null:
			select_rect.show_rect(Rect2(_press_pos, mm.position - _press_pos))
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		_finish(mb.position, mb.double_click)
		get_viewport().set_input_as_handled()

func _finish(pos: Vector2, double: bool) -> void:
	if _dragging:
		select_box.emit(Rect2(_press_pos, pos - _press_pos).abs(), _additive)
	else:
		select_click.emit(pos, _additive, double)
	_cancel()

func _cancel() -> void:
	_pressing = false
	_dragging = false
	if select_rect != null:
		select_rect.hide_rect()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel()

func _process(delta: float) -> void:
	if not enabled:
		return
	if _pressing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _synthetic:
		_cancel()
	var chatting: bool = get_viewport().gui_get_focus_owner() is LineEdit
	var dir: Vector2 = Vector2.ZERO
	if not chatting:
		dir = Input.get_vector(&"cam_left", &"cam_right", &"cam_up", &"cam_down")
		var rot: float = Input.get_axis(&"cam_rotate_left", &"cam_rotate_right")
		if rot != 0.0:
			camera_rotate.emit(rot, delta)
	if edge_scroll and not _pressing and get_window().has_focus():
		dir += edge_direction(get_viewport().get_mouse_position(), get_viewport().get_visible_rect())
	if dir != Vector2.ZERO:
		camera_pan.emit(dir.limit_length(1.0), delta)

## Screen-edge scroll vector for a pointer position; zero when the pointer is outside the window rect
## (a pointer that left the window keeps its last position, so require it to be inside).
static func edge_direction(p: Vector2, view: Rect2) -> Vector2:
	if not view.has_point(p):
		return Vector2.ZERO
	var d := Vector2.ZERO
	if p.x <= view.position.x + EDGE_MARGIN:
		d.x = -1.0
	elif p.x >= view.end.x - EDGE_MARGIN:
		d.x = 1.0
	if p.y <= view.position.y + EDGE_MARGIN:
		d.y = -1.0
	elif p.y >= view.end.y - EDGE_MARGIN:
		d.y = 1.0
	return d

## Test hook: synthetic (pushed) events do not update Input's polled button state.
var _synthetic: bool = false

func set_synthetic(v: bool) -> void:
	_synthetic = v
