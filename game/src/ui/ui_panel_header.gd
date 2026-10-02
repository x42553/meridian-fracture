class_name UiPanelHeader
extends Control
## Small recurring composite: accent tick + CAPS title (Orbitron 14, skin accent), optional glyph, right-aligned dim text and a
## fading hairline (ui.md 2.3). Redraws only when a property changes.

@export var title: String = "":
	set(v):
		title = v
		accessibility_name = v
		queue_redraw()
## Right-aligned secondary text (counts, status), Rajdhani 14 dim.
@export var right_text: String = "":
	set(v):
		right_text = v
		queue_redraw()
## `UiGlyphs.Glyph` id drawn before the title (-1 = none).
@export var glyph: int = -1:
	set(v):
		glyph = v
		queue_redraw()


func _init(title_text: String = "", right: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0.0, float(UiMetrics.HEADER_H))
	title = title_text
	right_text = right


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
	var base: float = size.y - 9.0
	# chamfered accent tick
	draw_colored_polygon(PackedVector2Array([Vector2(0.0, base - 13.0), Vector2(6.0, base - 13.0), Vector2(6.0, base + 1.0), Vector2(0.0, base + 1.0)]), acc)
	var x: float = 14.0
	if glyph >= 0:
		UiDraw.glyph(self, glyph, Rect2(Vector2(x, base - 14.0), Vector2(18.0, 18.0)), acc, 1.6)
		x += 26.0
	var txt: String = title.to_upper()
	draw_string(head, Vector2(x, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_HEAD, acc)
	var title_end: float = x + head.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_HEAD).x
	if right_text != "":
		var rw: float = body.get_string_size(right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_SMALL).x
		if title_end + rw + 24.0 <= size.x:
			draw_string(body, Vector2(size.x - rw, base), right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_SMALL, UiPalette.TEXT_DIM)
	var y: float = size.y - 1.0
	var steps: int = 24
	var w: float = size.x
	for i in steps:
		var a: float = 1.0 - float(i) / float(steps)
		draw_rect(Rect2(w * float(i) / float(steps), y, w / float(steps) + 1.0, 1.0), Color(acc, 0.55 * a * a + 0.05))
