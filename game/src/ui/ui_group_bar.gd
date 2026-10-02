class_name UiGroupBar
extends Control
## Control-group badges 1..0 above the selection panel (ui.md 5.11.3): digit, alive count and the dominant type glyph;
## empty groups are dimmed. Click = recall, double click = recall + centre (same as the hotkeys).

signal group_pressed(index: int, double: bool)

const BADGE := Vector2(60.0, 30.0)
const GAP: float = 4.0

## Per group index 0..9 (key 1..0): {count: int, glyph: int}; missing / count 0 = empty.
var groups: Array[Dictionary] = []
var active: int = -1
var _hover: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(BADGE.x * 10.0 + GAP * 9.0, BADGE.y)


func set_groups(g: Array[Dictionary], p_active: int = -1) -> void:
	groups = g
	active = p_active
	queue_redraw()


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
			group_pressed.emit(i, mb.double_click)
		accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var i: int = _at(at_position)
	if i < 0:
		return ""
	var n: int = int(groups[i].get("count", 0)) if i < groups.size() else 0
	var key: String = str((i + 1) % 10)
	return UiTooltipBody.encode({"title": "Group %s" % key, "text": ("%d units. Ctrl+%s reassigns." % [n, key]) if n > 0 else "Empty. Ctrl+%s assigns the selection." % key})


func _make_custom_tooltip(for_text: String) -> Object:
	return UiTooltipBody.make_from_text(for_text)


func _at(p: Vector2) -> int:
	for i: int in 10:
		if Rect2(float(i) * (BADGE.x + GAP), 0.0, BADGE.x, BADGE.y).has_point(p):
			return i
	return -1


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			_hover = -1
			queue_redraw()
		NOTIFICATION_THEME_CHANGED:
			queue_redraw()


func _draw() -> void:
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	var acc2: Color = get_theme_color(&"accent2", UiTheme.ACCENT_TYPE)
	for i: int in 10:
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
		var nc: Color = acc if i == active else (UiPalette.TEXT if count > 0 else UiPalette.TEXT_MUTE)
		draw_string(head, Vector2(r.position.x + 8.0, r.position.y + 21.0), str((i + 1) % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, nc)
		if count > 0:
			UiGlyphs.draw(self, int(g.get("glyph", UiGlyphs.Glyph.VEHICLES)), Rect2(r.position + Vector2(25.0, 7.0), Vector2(16.0, 16.0)), acc2 if i != active else acc, 1.4)
			draw_string(num, Vector2(r.position.x + 40.0, r.position.y + 20.0), str(count), HORIZONTAL_ALIGNMENT_CENTER, 18.0, 14, UiPalette.TEXT_DIM)
