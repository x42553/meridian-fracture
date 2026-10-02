class_name UiRibbon
extends Control
## Top-of-screen alert ribbon: superweapon countdowns (enemy = red hazard block, own = green "ready"),
## construction/attack notices. Angled ends, severity colour, optional charge bar and countdown numerals.

signal activated

enum Severity { INFO, OK, WARN, DANGER }

var skin: UiSkin
var severity: Severity = Severity.INFO
var title: String = ""
var subtitle: String = ""
var glyph: UiGlyphs.Glyph = UiGlyphs.Glyph.WARNING
## Seconds left; < 0 hides the numerals.
var countdown: float = -1.0
## 0..1 fill of the bottom charge bar; < 0 hides it.
var charge: float = -1.0
var tag: String = ""
var _pulse: float = 0.0
var _accum: float = 0.0

func _init() -> void:
	custom_minimum_size = Vector2(480.0, 48.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		activated.emit()
		accept_event()

func _process(delta: float) -> void:
	_pulse = fposmod(_pulse + delta * 2.4, 1.0)
	if countdown >= 0.0:
		countdown = maxf(countdown - delta, 0.0)
	_accum += delta
	if _accum > 1.0 / 20.0:
		_accum = 0.0
		queue_redraw()

func _color() -> Color:
	match severity:
		Severity.OK:
			return UiPalette.OK
		Severity.WARN:
			return UiPalette.WARN
		Severity.DANGER:
			return UiPalette.DANGER
	return skin.accent

func _draw() -> void:
	var c: Color = _color()
	var pulse: float = 0.5 + 0.5 * sin(_pulse * TAU)
	var r := Rect2(Vector2.ZERO, size)
	var sb := UiStyleBox.new()
	sb.cuts = Vector4(14.0, 14.0, 14.0, 14.0)
	sb.fill_top = c.darkened(0.70)
	sb.fill_top.a = 0.94
	sb.fill_bottom = c.darkened(0.86)
	sb.fill_bottom.a = 0.96
	sb.border_color = Color(c, 0.75 + (0.25 * pulse if severity == Severity.DANGER else 0.0))
	sb.glow = Color(c, 0.22 + (0.18 * pulse if severity == Severity.DANGER else 0.0))
	draw_style_box(sb, r)
	var blk := Rect2(1.0, 1.0, 54.0, size.y - 2.0)
	if severity == Severity.DANGER:
		var clip: PackedVector2Array = UiDraw.chamfer_points(blk, Vector4(13.0, 0.0, 0.0, 13.0))
		for k in range(-2, 8):
			var x0: float = blk.position.x + float(k) * 16.0
			var stripe := PackedVector2Array([Vector2(x0, blk.end.y), Vector2(x0 + 8.0, blk.end.y), Vector2(x0 + 8.0 + blk.size.y, blk.position.y), Vector2(x0 + blk.size.y, blk.position.y)])
			for piece in Geometry2D.intersect_polygons(stripe, clip):
				draw_colored_polygon(piece, Color(c, 0.55 + 0.25 * pulse))
		draw_colored_polygon(PackedVector2Array([blk.position + Vector2(10.0, 6.0), Vector2(blk.end.x - 10.0, blk.position.y + 6.0), Vector2(blk.end.x - 10.0, blk.end.y - 6.0), Vector2(blk.position.x + 10.0, blk.end.y - 6.0)]), Color(0.05, 0.02, 0.02, 0.8))
	else:
		draw_colored_polygon(UiDraw.chamfer_points(blk, Vector4(13.0, 0.0, 0.0, 13.0)), Color(c, 0.22))
	UiGlyphs.draw(self, glyph, Rect2(blk.position + Vector2(13.0, 11.0), Vector2(28.0, 26.0)), c.lightened(0.35), 2.0)
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var x: float = blk.end.x + 12.0
	draw_string(head, Vector2(x, 20.0), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 190.0, 13, c.lightened(0.45))
	draw_string(body, Vector2(x, 38.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 190.0, 14, UiPalette.TEXT_DIM)
	if countdown >= 0.0:
		var t: int = int(ceilf(countdown))
		draw_string(head, Vector2(size.x - 172.0, 32.0), "%02d:%02d" % [t / 60, t % 60], HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 25, c.lightened(0.4))
	elif tag != "":
		draw_string(head, Vector2(size.x - 172.0, 30.0), tag, HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 14, c.lightened(0.4))
	if charge >= 0.0:
		var bar := Rect2(blk.end.x + 12.0, size.y - 8.0, size.x - blk.end.x - 40.0, 3.0)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * charge, bar.size.y)), c)
