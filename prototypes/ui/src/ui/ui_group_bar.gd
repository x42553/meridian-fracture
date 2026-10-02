class_name UiGroupBar
extends Control
## Control-group badges 1..0 above the selection panel: number, unit count, dominant type glyph.
## Click selects the group, double-click selects and centres the camera (same as the hotkeys).

signal group_selected(index: int)
signal group_focused(index: int)

const BADGE := Vector2(60.0, 30.0)
const GAP := 4.0

var skin: UiSkin
## Per group: {count: int, glyph: UiGlyphs.Glyph}; missing/count 0 = empty slot (drawn dim).
var groups: Array[Dictionary] = []
var active: int = -1
var _hover: int = -1

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(BADGE.x * 10.0 + GAP * 9.0, BADGE.y)

func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		var h: int = _at(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var i: int = _at(mb.position)
		if i >= 0 and i < groups.size() and int(groups[i].get("count", 0)) > 0:
			active = i
			if mb.double_click:
				group_focused.emit(i)
			else:
				group_selected.emit(i)
			queue_redraw()
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()

func _at(p: Vector2) -> int:
	for i in 10:
		if Rect2(float(i) * (BADGE.x + GAP), 0.0, BADGE.x, BADGE.y).has_point(p):
			return i
	return -1

func _draw() -> void:
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	for i in 10:
		var g: Dictionary = groups[i] if i < groups.size() else {}
		var count: int = int(g.get("count", 0))
		var r := Rect2(float(i) * (BADGE.x + GAP), 0.0, BADGE.x, BADGE.y)
		var st: StringName = &"normal"
		if i == active:
			st = &"pressed"
		elif i == _hover and count > 0:
			st = &"hover"
		elif count == 0:
			st = &"disabled"
		draw_style_box(get_theme_stylebox(st, &"Button"), r)
		var nc: Color = skin.accent if i == active else (UiPalette.TEXT if count > 0 else UiPalette.TEXT_MUTE)
		draw_string(head, Vector2(r.position.x + 8.0, r.position.y + 21.0), str((i + 1) % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, nc)
		if count > 0:
			UiGlyphs.draw(self, g.get("glyph", UiGlyphs.Glyph.VEHICLES), Rect2(r.position + Vector2(25.0, 7.0), Vector2(16.0, 16.0)), skin.accent2 if i != active else skin.accent, 1.4)
			draw_string(num, Vector2(r.position.x + 40.0, r.position.y + 20.0), str(count), HORIZONTAL_ALIGNMENT_CENTER, 18.0, 13, UiPalette.TEXT_DIM)
