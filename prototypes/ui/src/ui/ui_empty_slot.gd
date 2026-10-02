class_name UiEmptySlot
extends Control
## Ghost cell that keeps the build grid looking like a grid when a tab has few items (C&C sidebar look).

func _init() -> void:
	custom_minimum_size = UiBuildCard.CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(get_theme_stylebox(&"disabled", &"Button"), r)
	draw_rect(r.grow(-8.0), Color(1, 1, 1, 0.015))
	var c: Vector2 = r.get_center()
	draw_line(c - Vector2(6.0, 0.0), c + Vector2(6.0, 0.0), Color(1, 1, 1, 0.08), 1.0)
	draw_line(c - Vector2(0.0, 6.0), c + Vector2(0.0, 6.0), Color(1, 1, 1, 0.08), 1.0)
