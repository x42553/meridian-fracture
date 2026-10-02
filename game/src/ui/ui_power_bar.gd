class_name UiPowerBar
extends Control
## 32-segment power meter (ui.md 5.10.7). `capacity` = generated power, `usage` = consumed. Usage above capacity turns
## the overflow red, flashes it at 2.2 Hz and pulses LOW POWER (the bible halves production and research rate then).
## scale_max = max(capacity, usage) x 1.1; segment i starts at lo = i x scale_max / 32 and is used while
## lo < usage - 0.001 x scale_max; the capacity marker sits at capacity / scale_max of the bar.

const SEGMENTS: int = 32
const FLASH_HZ: float = 2.2

var capacity: int = 0:
	set(v):
		if v != capacity:
			capacity = v
			_changed()
var usage: int = 0:
	set(v):
		if v != usage:
			usage = v
			_changed()
var _phase: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 42.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(false)


func is_low() -> bool:
	return usage > capacity


## scale of the bar: max(capacity, usage) x 1.1.
static func scale_max_of(cap: int, use: int) -> float:
	return maxf(float(maxi(cap, use)) * 1.1, 1.0)


## Number of lit segments for the given numbers (segments 0..n-1 are "used").
static func used_segments(cap: int, use: int) -> int:
	var sm: float = scale_max_of(cap, use)
	var n: int = 0
	for i: int in SEGMENTS:
		var lo: float = float(i) * sm / float(SEGMENTS)
		if lo < float(use) - 0.001 * sm:
			n += 1
	return n


func _changed() -> void:
	set_process(is_low() and not UiMotion.reduce_flash)
	queue_redraw()


func _get_tooltip(_at: Vector2) -> String:
	return UiTooltipBody.encode({"title": "Power %d / %d" % [usage, capacity], "text": "Consumption above capacity halves production and research speed."})


func _make_custom_tooltip(for_text: String) -> Object:
	return UiTooltipBody.make_from_text(for_text)


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * FLASH_HZ, 1.0)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var low: bool = is_low()
	var cvd: bool = bool(UiThemeService.a11y_options().get("cvd", false))
	var c_ok: Color = UiPalette.semantic_for(&"ok", cvd)
	var c_warn: Color = UiPalette.semantic_for(&"warn", cvd)
	var c_bad: Color = UiPalette.semantic_for(&"danger", cvd)
	UiGlyphs.draw(self, UiGlyphs.Glyph.BOLT, Rect2(0.0, 0.0, 15.0, 15.0), c_warn if low else UiPalette.POWER)
	draw_string(head, Vector2(19.0, 13.0), "POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiPalette.TEXT_DIM)
	draw_string(num, Vector2(0.0, 14.0), "%d / %d" % [usage, capacity], HORIZONTAL_ALIGNMENT_RIGHT, size.x, 14, c_bad if low else UiPalette.TEXT)
	var flash: float = 0.55 + 0.45 * sin(_phase * TAU) if not UiMotion.reduce_flash else 1.0
	if low:
		draw_string(head, Vector2(0.0, 14.0), "LOW POWER", HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(c_warn, flash))
	var top: float = 22.0
	var h: float = size.y - top - 2.0
	var sm: float = scale_max_of(capacity, usage)
	var gap: float = 2.0
	var seg_w: float = (size.x - gap * float(SEGMENTS - 1)) / float(SEGMENTS)
	for i: int in SEGMENTS:
		var lo: float = float(i) * sm / float(SEGMENTS)
		var seg := Rect2(float(i) * (seg_w + gap), top, seg_w, h)
		var within_cap: bool = lo < float(capacity)
		var used: bool = lo < float(usage) - 0.001 * sm
		var c: Color
		if used and within_cap:
			var t: float = lo / maxf(float(capacity), 1.0)
			c = c_ok.lerp(c_warn, smoothstep(0.7, 1.0, t))
		elif used:
			c = c_bad
			c.a = flash
		elif within_cap:
			c = Color(c_ok, 0.16)
		else:
			c = Color(UiPalette.LINE_DIM, 0.8)
		draw_rect(seg, c)
	var cap_x: float = clampf(float(capacity) / sm, 0.0, 1.0) * size.x
	draw_line(Vector2(cap_x, top - 3.0), Vector2(cap_x, top + h + 1.0), Color(UiPalette.TEXT, 0.9), 1.5)
