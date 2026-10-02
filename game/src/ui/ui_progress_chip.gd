class_name UiProgressChip
extends Control
## Small recurring composite (ui.md 2.3): an inset chip with a caption on the left, a value on the right and a thin progress
## fill along the bottom edge ("LOADING 40 %", "READY", "BUILD 2:15"). Tones: &"accent", &"ok", &"warn", &"danger", &"power".
## Redraws only on change; `progress` < 0 hides the bar.

@export var text: String = "":
	set(v):
		text = v
		accessibility_name = v
		queue_redraw()
@export var value_text: String = "":
	set(v):
		value_text = v
		queue_redraw()
## 0..1, or -1 for no bar.
@export_range(-1.0, 1.0) var progress: float = -1.0:
	set(v):
		v = clampf(v, -1.0, 1.0)
		if is_equal_approx(v, progress):
			return
		progress = v
		queue_redraw()
@export var tone: StringName = &"accent":
	set(v):
		tone = v
		queue_redraw()
## Optional `UiGlyphs.Glyph` id before the caption (-1 = none).
@export var glyph: int = -1:
	set(v):
		glyph = v
		queue_redraw()


func _init(caption: String = "", value: String = "", p: float = -1.0, chip_tone: StringName = &"accent") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(120.0, float(UiMetrics.CHIP_H))
	text = caption
	value_text = value
	progress = p
	tone = chip_tone


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()


func _tone_color() -> Color:
	return get_theme_color(tone, UiTheme.ACCENT_TYPE)


func _get_minimum_size() -> Vector2:
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var w: float = 20.0 + (24.0 if glyph >= 0 else 0.0)
	w += num.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_CAPTION).x
	w += num.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_CAPTION).x + (14.0 if value_text != "" else 0.0)
	return Vector2(maxf(w, 120.0), float(UiMetrics.CHIP_H))


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(get_theme_stylebox(&"panel", &"InsetPanel"), r)
	var col: Color = _tone_color()
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var x: float = 10.0
	var base: float = size.y * 0.5 + 5.0 - (1.5 if progress >= 0.0 else 0.0)
	if glyph >= 0:
		UiDraw.glyph(self, glyph, Rect2(Vector2(x, size.y * 0.5 - 9.0), Vector2(18.0, 18.0)), col, 1.6)
		x += 24.0
	draw_string(num, Vector2(x, base), text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_CAPTION, UiPalette.TEXT_DIM)
	if value_text != "":
		draw_string(num, Vector2(0.0, base), value_text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10.0, UiMetrics.FS_CAPTION, col)
	if progress >= 0.0:
		var bar := Rect2(4.0, size.y - 5.0, size.x - 8.0, 3.0)
		draw_rect(bar, Color(0.0, 0.0, 0.0, 0.5))
		if progress > 0.0:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), col)
