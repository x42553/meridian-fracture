class_name UiObjectiveMark
extends Control
## The state mark of a mission objective (MIS2): an open ring (active; accent for primary, dim for optional), a green disc with a check
## (completed) or a red disc with a cross (failed). Drawn, 20 px, mouse-transparent.

var state: int = UiMissionModel.S_ACTIVE:
	set(v):
		state = v
		queue_redraw()
var primary: bool = true:
	set(v):
		primary = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(20.0, 20.0)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c: Vector2 = Vector2(10.0, 11.0)
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	match state:
		UiMissionModel.S_COMPLETED:
			draw_circle(c, 9.0, UiPalette.semantic(&"ok"))
			UiDraw.glyph(self, UiGlyphs.Glyph.CHECK, Rect2(c - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), UiPalette.TEXT_ON_ACCENT, 2.0)
		UiMissionModel.S_FAILED:
			draw_circle(c, 9.0, UiPalette.semantic(&"danger"))
			UiDraw.glyph(self, UiGlyphs.Glyph.CLOSE, Rect2(c - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), UiPalette.TEXT_ON_ACCENT, 2.0)
		_:
			var ring: Color = acc if primary else UiPalette.TEXT_DIM
			draw_arc(c, 8.0, 0.0, TAU, 24, ring, 2.0, true)
			draw_circle(c, 3.0, Color(ring, 0.55))
