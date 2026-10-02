class_name UiSelectRect
extends Control
## Drag-select rectangle overlay (ui.md 2.3). Driven by the input controller; `MOUSE_FILTER_IGNORE` so it never blocks the
## drag that draws it. Colour = the semantic OK colour of the active colour mode (SELF relation colour).

var active: bool = false
var rect: Rect2 = Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Shows / updates the rectangle (any corner order, viewport coordinates).
func show_rect(r: Rect2) -> void:
	active = true
	rect = r.abs()
	queue_redraw()


func hide_rect() -> void:
	if active:
		active = false
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	if not active:
		return
	var color: Color = get_theme_color(&"ok", UiTheme.ACCENT_TYPE)
	draw_rect(rect, Color(color, 0.10))
	draw_rect(rect, Color(color, 0.95), false, 1.5)
	for c: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		draw_rect(Rect2(c - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), color)
