class_name UiCreditTicker
extends Control
## Credit readout with a count-up/down ticker, a green/red flash on change and an income-rate line.
## Digits are drawn one by one in fixed-width cells so the number never jitters while it counts.

var target: int = 0
var income_per_min: int = 0
var shown: float = 0.0
var _flash: float = 0.0

func _init() -> void:
	custom_minimum_size = Vector2(0.0, 56.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_credits(v: int, instant: bool = false) -> void:
	if v != target:
		_flash = 1.0 if v > target else -1.0
	target = v
	if instant:
		shown = float(v)
	set_process(true)

func _process(delta: float) -> void:
	var diff: float = float(target) - shown
	if absf(diff) > 0.5:
		var step: float = maxf(absf(diff) * 7.0, 90.0) * delta
		shown = float(target) if step >= absf(diff) else shown + signf(diff) * step
	else:
		shown = float(target)
	_flash = move_toward(_flash, 0.0, delta * 2.2)
	queue_redraw()
	if is_equal_approx(shown, float(target)) and absf(_flash) < 0.01:
		set_process(false)

func _draw() -> void:
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var col: Color = UiPalette.CREDITS
	if _flash > 0.0:
		col = col.lerp(UiPalette.OK.lightened(0.3), _flash)
	elif _flash < 0.0:
		col = col.lerp(UiPalette.DANGER, -_flash)
	UiGlyphs.draw(self, UiGlyphs.Glyph.CREDIT, Rect2(0.0, 4.0, 30.0, 30.0), UiPalette.CREDITS)
	var fs: int = 30
	var text: String = _group(int(roundf(shown)))
	var cell: float = 0.0
	for d in "0123456789":
		cell = maxf(cell, head.get_char_size(d.unicode_at(0), fs).x)
	var comma: float = cell * 0.5
	var total: float = 0.0
	for ch in text:
		total += comma if ch == "," else cell
	var x: float = size.x - total
	for ch in text:
		var w: float = comma if ch == "," else cell
		draw_string(head, Vector2(x + 1.0, 33.0), ch, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.0, 0.0, 0.0, 0.5))
		draw_string(head, Vector2(x, 32.0), ch, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
		x += w
	var inc: String = "%+d / MIN" % income_per_min
	var ic: Color = UiPalette.OK if income_per_min >= 0 else UiPalette.DANGER
	draw_string(num, Vector2(0.0, size.y - 3.0), "INCOME", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiPalette.TEXT_MUTE)
	draw_string(num, Vector2(0.0, size.y - 3.0), inc, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 13, ic)

static func _group(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
