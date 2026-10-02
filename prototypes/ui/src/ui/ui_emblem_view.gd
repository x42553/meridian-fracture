class_name UiEmblemView
extends Control
## Control wrapper that draws a UiEmblem (sidebar header, menus, skirmish slot rows).

var code: String = "napc":
	set(v):
		code = v
		queue_redraw()
var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()
var line_width: float = 2.0

func _init(sz: float = 36.0) -> void:
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	UiEmblem.draw(self, code, Rect2(Vector2.ZERO, size).grow(-2.0), color, line_width)
