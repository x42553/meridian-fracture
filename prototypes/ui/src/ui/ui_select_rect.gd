class_name UiSelectRect
extends Control
## Drag-select rectangle overlay. Owned/driven by UiInputController; mouse_filter IGNORE so it never
## blocks the very drag that draws it.

var active: bool = false
var rect: Rect2 = Rect2()
var color: Color = UiPalette.OK

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_rect(r: Rect2) -> void:
	active = true
	rect = r.abs()
	queue_redraw()

func hide_rect() -> void:
	if active:
		active = false
		queue_redraw()

func _draw() -> void:
	if not active:
		return
	draw_rect(rect, Color(color, 0.10))
	draw_rect(rect, Color(color, 0.95), false, 1.5)
	for c in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		draw_rect(Rect2(c - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), color)
