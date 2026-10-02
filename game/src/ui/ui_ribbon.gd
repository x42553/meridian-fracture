class_name UiRibbon
extends Control
## Top-of-screen alert ribbon (ui.md 5.13.2 anatomy): glyph block, bold title, dim subtitle, countdown or tag, optional
## charge bar, severity colour and a 1 Hz border pulse (static under reduce-motion). DANGER = red hazard block.

signal activated(rule_id: StringName)

enum Severity { INFO = 0, OK = 1, WARN = 2, DANGER = 3 }

var rule_id: StringName = &""
var severity: int = Severity.INFO
var title: String = ""
var subtitle: String = ""
var glyph: int = UiGlyphs.Glyph.WARNING
var countdown_seconds: float = -1.0  ## < 0 hides the numerals
var charge: float = -1.0  ## 0..1 fill of the bottom bar; < 0 hides it
var tag: String = ""
var sim_x: int = -1
var sim_y: int = -1
var created_msec: int = 0
var ttl_msec: int = 0  ## 0 = until removed explicitly
var _phase: float = 0.0
var _accum: float = 0.0


func _init() -> void:
	custom_minimum_size = UiMetrics.RIBBON
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	created_msec = Time.get_ticks_msec()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(rule_id)
		accept_event()


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * UiMotion.PULSE_HZ, 1.0)
	_accum += delta
	if _accum >= 1.0 / 20.0:
		_accum = 0.0
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _color() -> Color:
	var cvd: bool = bool(UiThemeService.a11y_options().get("cvd", false))
	match severity:
		Severity.OK:
			return UiPalette.semantic_for(&"ok", cvd)
		Severity.WARN:
			return UiPalette.semantic_for(&"warn", cvd)
		Severity.DANGER:
			return UiPalette.semantic_for(&"danger", cvd)
	return get_theme_color(&"accent", UiTheme.ACCENT_TYPE)


func _draw() -> void:
	var c: Color = _color()
	var pulse: float = UiMotion.pulse(_phase / UiMotion.PULSE_HZ)
	var danger: bool = severity == Severity.DANGER
	var r := Rect2(Vector2.ZERO, size)
	var sb := UiStyleBox.new()
	sb.cuts = Vector4(14.0, 14.0, 14.0, 14.0)
	sb.fill_top = Color(c.darkened(0.70), 0.94)
	sb.fill_bottom = Color(c.darkened(0.86), 0.96)
	sb.border_color = Color(c, 0.75 + (0.25 * pulse if danger else 0.0))
	sb.glow = Color(c, 0.22 + (0.18 * pulse if danger else 0.0))
	draw_style_box(sb, r)
	var blk := Rect2(1.0, 1.0, 54.0, size.y - 2.0)
	if danger:
		var clip: PackedVector2Array = UiDraw.chamfer_points(blk, Vector4(13.0, 0.0, 0.0, 13.0))
		for k: int in range(-2, 8):
			var x0: float = blk.position.x + float(k) * 16.0
			var stripe := PackedVector2Array([Vector2(x0, blk.end.y), Vector2(x0 + 8.0, blk.end.y), Vector2(x0 + 8.0 + blk.size.y, blk.position.y), Vector2(x0 + blk.size.y, blk.position.y)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(stripe, clip):
				draw_colored_polygon(piece, Color(c, 0.55 + 0.25 * pulse))
		draw_colored_polygon(PackedVector2Array([blk.position + Vector2(10.0, 6.0), Vector2(blk.end.x - 10.0, blk.position.y + 6.0), Vector2(blk.end.x - 10.0, blk.end.y - 6.0), Vector2(blk.position.x + 10.0, blk.end.y - 6.0)]), Color(0.05, 0.02, 0.02, 0.8))
	else:
		draw_colored_polygon(UiDraw.chamfer_points(blk, Vector4(13.0, 0.0, 0.0, 13.0)), Color(c, 0.22))
	UiGlyphs.draw(self, glyph, Rect2(blk.position + Vector2(13.0, 11.0), Vector2(28.0, 26.0)), c.lightened(0.35), 2.0)
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var x: float = blk.end.x + 12.0
	var right_w: float = 160.0 if (countdown_seconds >= 0.0 or tag != "") else 20.0
	draw_string(head, Vector2(x, 21.0), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - right_w - 14.0, 14, c.lightened(0.45))
	draw_string(body, Vector2(x, 39.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - right_w - 14.0, 14, UiPalette.TEXT_DIM)
	if countdown_seconds >= 0.0:
		var t: int = int(ceilf(countdown_seconds))
		draw_string(head, Vector2(size.x - right_w - 14.0, 33.0), "%02d:%02d" % [t / 60, t % 60], HORIZONTAL_ALIGNMENT_RIGHT, right_w, 25, c.lightened(0.4))
	elif tag != "":
		draw_string(head, Vector2(size.x - right_w - 14.0, 31.0), tag, HORIZONTAL_ALIGNMENT_RIGHT, right_w, 14, c.lightened(0.4))
	if charge >= 0.0:
		var bar := Rect2(blk.end.x + 12.0, size.y - 8.0, size.x - blk.end.x - 40.0, 3.0)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(charge, 0.0, 1.0), bar.size.y)), c)
