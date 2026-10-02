class_name UiCameraPad
extends Control
## Mouse-only alternative to the camera keys (ui.md 5.11.7, QA A-06): rotate left / right, tilt up / down, zoom in /
## out (hold repeats after 350 ms every 90 ms), centre on base and jump to alert. One custom-drawn row under the
## minimap; emits `pad_pressed(id)`, the screen maps it to the same `UiViewPort` calls as the keys.

signal pad_pressed(id: StringName)

const BUTTONS: Array[Dictionary] = [
	{"id": &"rotate_left", "glyph": UiGlyphs.Glyph.ROTATE_L, "repeat": true, "tip": "Rotate left"},
	{"id": &"rotate_right", "glyph": UiGlyphs.Glyph.ROTATE_R, "repeat": true, "tip": "Rotate right"},
	{"id": &"tilt_up", "glyph": UiGlyphs.Glyph.CHEVRON_UP, "repeat": true, "tip": "Tilt up"},
	{"id": &"tilt_down", "glyph": UiGlyphs.Glyph.CHEVRON_DOWN, "repeat": true, "tip": "Tilt down"},
	{"id": &"zoom_in", "glyph": UiGlyphs.Glyph.PLUS, "repeat": true, "tip": "Zoom in"},
	{"id": &"zoom_out", "glyph": UiGlyphs.Glyph.MINUS, "repeat": true, "tip": "Zoom out"},
	{"id": &"centre_base", "glyph": UiGlyphs.Glyph.HOME, "repeat": false, "tip": "Centre on base"},
	{"id": &"jump_alert", "glyph": UiGlyphs.Glyph.WARNING, "repeat": false, "tip": "Jump to last alert"},
]
const GAP: float = 3.0
const REPEAT_DELAY_S: float = 0.35
const REPEAT_EVERY_S: float = 0.09

var _hover: int = -1
var _down: int = -1
var _held_s: float = 0.0
var _rep_acc: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_force_pass_scroll_events = false
	custom_minimum_size = Vector2(0.0, 28.0)
	set_process(false)


func button_rect(i: int) -> Rect2:
	var n: int = BUTTONS.size()
	var w: float = (size.x - GAP * float(n - 1)) / float(n)
	return Rect2(float(i) * (w + GAP), 0.0, w, size.y)


func _at(p: Vector2) -> int:
	for i: int in BUTTONS.size():
		if button_rect(i).has_point(p):
			return i
	return -1


func _get_tooltip(at_position: Vector2) -> String:
	var i: int = _at(at_position)
	return String(BUTTONS[i]["tip"]) if i >= 0 else ""


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		var h: int = _at(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_down = _at(mb.position)
			if _down >= 0:
				pad_pressed.emit(BUTTONS[_down]["id"])
				_held_s = 0.0
				_rep_acc = 0.0
				set_process(bool(BUTTONS[_down]["repeat"]))
		else:
			_down = -1
			set_process(false)
		queue_redraw()
		accept_event()


func _process(delta: float) -> void:
	if _down < 0:
		set_process(false)
		return
	_held_s += delta
	if _held_s < REPEAT_DELAY_S:
		return
	_rep_acc += delta
	while _rep_acc >= REPEAT_EVERY_S:
		_rep_acc -= REPEAT_EVERY_S
		pad_pressed.emit(BUTTONS[_down]["id"])


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			_hover = -1
			queue_redraw()
		NOTIFICATION_FOCUS_EXIT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_down = -1
			set_process(false)
		NOTIFICATION_THEME_CHANGED, NOTIFICATION_RESIZED:
			queue_redraw()


func _draw() -> void:
	for i: int in BUTTONS.size():
		var r: Rect2 = button_rect(i)
		var st: StringName = &"pressed" if i == _down else (&"hover" if i == _hover else &"normal")
		draw_style_box(get_theme_stylebox(st, &"CommandButton"), r)
		var col: Color = UiPalette.TEXT if i == _hover or i == _down else UiPalette.TEXT_DIM
		UiGlyphs.draw(self, int(BUTTONS[i]["glyph"]), Rect2(r.get_center() - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), col, 1.5)
