class_name UiLogFeed
extends Control
## Fading message feed at the bottom left (ui.md 5.13.3): the newest `max_lines` lines, each visible for `LIFE_S` and
## fading over the last second. Drawn in one canvas item (no Label nodes). Mouse-transparent.

const LIFE_S: float = 8.0
const FADE_S: float = 1.0
const LINE_H: float = 20.0

var max_lines: int = UiMetrics.LOG_MAX
var _lines: Array[Dictionary] = []  ## {text, color, born}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(420.0, LINE_H * float(UiMetrics.LOG_MAX))
	set_process(false)


## Appends a line (`col` = severity colour; default dim).
func add(text: String, col: Color = UiPalette.TEXT) -> void:
	_lines.append({"text": text, "color": col, "born": Time.get_ticks_msec()})
	while _lines.size() > max_lines:
		_lines.remove_at(0)
	set_process(true)
	queue_redraw()


func line_count() -> int:
	return _lines.size()


func line_text(i: int) -> String:
	return String(_lines[i]["text"])


func clear() -> void:
	_lines.clear()
	queue_redraw()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	while not _lines.is_empty() and float(now - int(_lines[0]["born"])) / 1000.0 > LIFE_S:
		_lines.remove_at(0)
	queue_redraw()
	if _lines.is_empty():
		set_process(false)


func _draw() -> void:
	var font: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var now: int = Time.get_ticks_msec()
	var n: int = _lines.size()
	var fs: int = 16
	for i: int in n:
		var e: Dictionary = _lines[i]
		var age: float = float(now - int(e["born"])) / 1000.0
		var a: float = clampf((LIFE_S - age) / FADE_S, 0.0, 1.0)
		var y: float = size.y - float(n - i - 1) * LINE_H - 4.0
		var text: String = String(e["text"])
		var col: Color = e["color"]
		# a backing plate (the feed sits over bright terrain), a severity tick on its left edge and an outlined, brightened text
		var tw: float = minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x, size.x - 14.0)
		var plate: Rect2 = Rect2(-4.0, y - 15.0, tw + 16.0, LINE_H - 1.0)
		draw_rect(plate, Color(0.02, 0.03, 0.05, 0.62 * a))
		draw_rect(Rect2(plate.position, Vector2(3.0, plate.size.y)), Color(col, 0.95 * a))
		for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
			draw_string(font, Vector2(6.0, y) + o, text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8.0, fs, Color(0, 0, 0, 0.9 * a))
		draw_string(font, Vector2(6.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8.0, fs, Color(col.lightened(0.25), a))
