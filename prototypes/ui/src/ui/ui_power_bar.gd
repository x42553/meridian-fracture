class_name UiPowerBar
extends Control
## Segmented power meter. `capacity` = generated power, `usage` = consumed. Usage above capacity turns the
## overflow red and flashes LOW POWER (the bible halves production and research rate in that state).

const SEGMENTS := 32

var capacity: int = 0:
	set(v):
		capacity = v
		set_process(usage > capacity)
		queue_redraw()
var usage: int = 0:
	set(v):
		usage = v
		set_process(usage > capacity)
		queue_redraw()
var _flash: float = 0.0

func _init() -> void:
	custom_minimum_size = Vector2(0.0, 42.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "Power: consumption above capacity halves production and research speed."

func _process(delta: float) -> void:
	_flash = fposmod(_flash + delta * 2.2, 1.0)
	queue_redraw()

func _ready() -> void:
	set_process(usage > capacity)

func _draw() -> void:
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var low: bool = usage > capacity
	var head_col: Color = UiPalette.TEXT_DIM
	UiGlyphs.draw(self, UiGlyphs.Glyph.BOLT, Rect2(0.0, 1.0, 14.0, 14.0), UiPalette.WARN if low else UiPalette.POWER)
	draw_string(head, Vector2(19.0, 13.0), "POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, head_col)
	var txt_col: Color = UiPalette.DANGER if low else UiPalette.TEXT
	draw_string(num, Vector2(0.0, 14.0), "%d / %d" % [usage, capacity], HORIZONTAL_ALIGNMENT_RIGHT, size.x, 14, txt_col)
	if low:
		var a: float = 0.55 + 0.45 * sin(_flash * TAU)
		draw_string(head, Vector2(0.0, 14.0), "LOW POWER", HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(UiPalette.WARN, a))
	var top: float = 22.0
	var h: float = size.y - top - 2.0
	var scale_max: float = maxf(float(maxi(capacity, usage)) * 1.1, 1.0)
	var gap: float = 2.0
	var seg_w: float = (size.x - gap * float(SEGMENTS - 1)) / float(SEGMENTS)
	for i in SEGMENTS:
		var lo: float = float(i) / float(SEGMENTS) * scale_max
		var hi: float = float(i + 1) / float(SEGMENTS) * scale_max
		var seg := Rect2(float(i) * (seg_w + gap), top, seg_w, h)
		var within_cap: bool = lo < float(capacity)
		var used: bool = lo < float(usage) - 0.001 * scale_max
		var c: Color
		if used and within_cap:
			var t: float = lo / maxf(float(capacity), 1.0)
			c = UiPalette.OK.lerp(UiPalette.WARN, smoothstep(0.7, 1.0, t))
		elif used:
			c = UiPalette.DANGER
			c.a = 0.55 + 0.45 * sin(_flash * TAU)
		elif within_cap:
			c = Color(UiPalette.OK, 0.16)
		else:
			c = Color(UiPalette.LINE_DIM, 0.8)
		draw_rect(seg, c)
	var cap_x: float = clampf(float(capacity) / scale_max, 0.0, 1.0) * size.x
	draw_line(Vector2(cap_x, top - 3.0), Vector2(cap_x, top + h + 1.0), Color(UiPalette.TEXT, 0.9), 1.5)
