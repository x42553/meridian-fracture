class_name UiCreditTicker
extends Control
## Credit readout (ui.md 5.10.7): a 300 ms ease-out-cubic count between values, a green / red flash on change and the
## income line. Digits are drawn in fixed-width cells (widest digit of the font, commas half width) so the number never
## jitters while it rolls. An event during a roll restarts from the value currently shown.

const ROLL_S: float = 0.3

var target: int = 0
var income_per_min: int = 0:
	set(v):
		if v != income_per_min:
			income_per_min = v
			queue_redraw()
var _from: float = 0.0
var _t: float = ROLL_S
var _shown: int = 0
var _flash: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 56.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(false)


## `roundi(lerp(from, to, ease_out_cubic(t / 0.3)))` (t in seconds, clamped to the roll length).
static func value_at(from_v: int, to_v: int, t: float) -> int:
	var k: float = clampf(t / ROLL_S, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 3.0)
	return roundi(lerpf(float(from_v), float(to_v), e))


func shown() -> int:
	return _shown


func set_credits(v: int, instant: bool = false) -> void:
	if v == target and _t >= ROLL_S:
		return
	if v != target:
		_flash = 1.0 if v > target else -1.0
	_from = float(_shown)
	target = v
	_t = 0.0
	if instant or UiMotion.dur(ROLL_S) <= 0.0:
		_shown = v
		_t = ROLL_S
		_flash = 0.0
		queue_redraw()
		return
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	_shown = value_at(int(_from), target, _t)
	_flash = move_toward(_flash, 0.0, delta * 2.2)
	queue_redraw()
	if _t >= ROLL_S and absf(_flash) < 0.01:
		_shown = target
		set_process(false)


func _get_tooltip(_at: Vector2) -> String:
	return UiTooltipBody.encode({"title": "Credits", "text": "Income %s / min" % ("%+d" % income_per_min)})


func _make_custom_tooltip(for_text: String) -> Object:
	return UiTooltipBody.make_from_text(for_text)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


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
	var text: String = UiBuildItem.group_digits(_shown)
	var cell: float = 0.0
	for d: String in "0123456789":
		cell = maxf(cell, head.get_char_size(d.unicode_at(0), fs).x)
	var comma: float = cell * 0.5
	var total: float = 0.0
	for ch: String in text:
		total += comma if ch == "," else cell
	var x: float = size.x - total
	for ch2: String in text:
		var w: float = comma if ch2 == "," else cell
		draw_string(head, Vector2(x + 1.0, 33.0), ch2, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.0, 0.0, 0.0, 0.5))
		draw_string(head, Vector2(x, 32.0), ch2, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
		x += w
	var inc: String = "%+d / MIN" % income_per_min
	var ic: Color = UiPalette.OK if income_per_min >= 0 else UiPalette.DANGER
	draw_string(num, Vector2(0.0, size.y - 3.0), "INCOME", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_MUTE)
	draw_string(num, Vector2(0.0, size.y - 3.0), inc, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 14, ic)
