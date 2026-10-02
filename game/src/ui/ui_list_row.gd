class_name UiListRow
extends Control
## One row of a data list (LAN games, replays, Field Manual lists; ui.md 2.3). Custom-drawn: ONE canvas item per row instead
## of one node per cell, so a 200-row list stays cheap (5.19.6 rule 3). Fixed column widths, per-cell colour and alignment,
## hover / selected / dimmed / header states. `selected` fires on click, `activated` on double click or Enter.
## Cells: `[{text: String, color: Color (optional), align: int (optional HorizontalAlignment), mono: bool (NUM font),
## dots: PackedColorArray (optional: small colour squares drawn before the text, e.g. the player colours of a replay),
## tag: String + tag_color (optional: a small caption in front of the text, e.g. "LAST" on the last automatic replay)}]`.

signal selected()
signal activated()

## Header rows draw Orbitron captions and a skin-accent baseline and ignore clicks.
var is_header: bool = false:
	set(v):
		is_header = v
		queue_redraw()
var is_selected: bool = false:
	set(v):
		if v == is_selected:
			return
		is_selected = v
		queue_redraw()
## Dimmed rows (full games, incompatible builds).
var dimmed: bool = false:
	set(v):
		dimmed = v
		queue_redraw()
## Zebra striping seed (odd rows are drawn a touch lighter).
var odd: bool = false

var _cells: Array[Dictionary] = []
var _widths: PackedFloat32Array = PackedFloat32Array()
var _hover: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(0.0, float(UiMetrics.LIST_ROW_H))
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## Menu use: rows take focus (Enter activates).
func set_focusable(on: bool) -> void:
	focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


func set_cells(cells: Array[Dictionary], widths: PackedFloat32Array) -> void:
	_cells = cells
	_widths = widths
	if not cells.is_empty():
		accessibility_name = ", ".join(PackedStringArray(cells.map(func(c: Dictionary) -> String: return String(c.get("text", "")))))
	queue_redraw()


func cell_count() -> int:
	return _cells.size()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()
		NOTIFICATION_THEME_CHANGED, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT, NOTIFICATION_RESIZED:
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if is_header:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.double_click:
			activated.emit()
		else:
			selected.emit()
		accept_event()
	elif event.is_action_pressed(&"ui_accept") and has_focus():
		activated.emit()
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	if is_header:
		draw_rect(r, Color(0.0, 0.0, 0.0, 0.35))
		draw_rect(Rect2(0.0, size.y - 1.0, size.x, 1.0), acc)
	elif is_selected:
		draw_style_box(get_theme_stylebox(&"hover", &"PopupMenu"), r)
		draw_rect(Rect2(0.0, 0.0, 3.0, size.y), acc)
	elif _hover:
		draw_rect(r, Color(acc, 0.10))
		draw_rect(Rect2(0.0, size.y - 1.0, size.x, 1.0), Color(acc, 0.35))
	else:
		draw_rect(r, Color(1.0, 1.0, 1.0, 0.045 if odd else 0.02))
		draw_rect(Rect2(0.0, size.y - 1.0, size.x, 1.0), Color(1.0, 1.0, 1.0, 0.04))
	var body: Font = UiFonts.get_font(UiFonts.Role.HEAD if is_header else UiFonts.Role.BODY_BOLD)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var fs: int = UiMetrics.FS_HEAD if is_header else UiMetrics.FS_LIST
	var x: float = 14.0
	var base: float = size.y * 0.5 + (5.0 if is_header else 5.5)
	for i in mini(_cells.size(), _widths.size()):
		var w: float = _widths[i]
		var c: Dictionary = _cells[i]
		var col: Color = c.get("color", acc if is_header else UiPalette.TEXT) as Color
		if dimmed and not is_header:
			col = col.darkened(0.4)
		var f: Font = num if bool(c.get("mono", false)) and not is_header else body
		var lead: float = 0.0
		var tag: String = str(c.get("tag", ""))
		if tag != "" and not is_header:
			var tf: Font = UiFonts.get_font(UiFonts.Role.HEAD)
			var tcol: Color = c.get("tag_color", acc) as Color
			if dimmed:
				tcol = tcol.darkened(0.4)
			draw_string(tf, Vector2(x, base - 1.0), tag, HORIZONTAL_ALIGNMENT_LEFT, w - 12.0, 11, tcol)
			lead += tf.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8.0
		var dots: PackedColorArray = c.get("dots", PackedColorArray()) as PackedColorArray
		if not dots.is_empty() and not is_header:
			var dsz: float = 9.0
			var dy: float = size.y * 0.5 - dsz * 0.5
			for di: int in dots.size():
				var dc: Color = dots[di].darkened(0.4) if dimmed else dots[di]
				draw_rect(Rect2(x + lead, dy, dsz, dsz), dc)
				draw_rect(Rect2(x + lead, dy, dsz, dsz), Color(0.0, 0.0, 0.0, 0.45), false, 1.0)
				lead += dsz + 3.0
			lead += 4.0
		var txt: String = UiDraw.ellipsize(f, String(c.get("text", "")), fs, w - 12.0 - lead)
		draw_string(f, Vector2(x + lead, base), txt, int(c.get("align", HORIZONTAL_ALIGNMENT_LEFT)), w - 12.0 - lead, fs, col)
		x += w
	if has_focus():
		draw_style_box(get_theme_stylebox(&"focus", &"Button"), r)
