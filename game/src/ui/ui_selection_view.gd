class_name UiSelectionView
extends Control
## Left part of the bottom-centre panel (ui.md 5.11.4): the primary's portrait (152 x 76), name, role, HP bar with
## ticks at 33 / 66 %, status chips and info lines, and for several entities a tile grid (TILE 46) with HP bar, vet
## chevrons, squad pips and a "+N" overflow tile. Data only: the presenter fills `set_selection` from port reads.
## Entry: {id, name, role, hp (permille), hp_now, hp_max, vet, squad, squad_max, glyph, icon, tip}.

signal tile_pressed(index: int, mods: int)

const MOD_SHIFT: int = 1
const MOD_CTRL: int = 2
const PORTRAIT_W: float = 152.0
const PORTRAIT_H: float = 76.0
const HEADER_H: float = 24.0

var mode: int = UiSelection.Mode.NONE
var total: int = 0  ## selected count (may exceed the entries)
var primary_index: int = 0
var entries: Array[Dictionary] = []
var chips: PackedStringArray = PackedStringArray()  ## status chips of the single entity ("POWERED", "EMP", ...)
var info_lines: Array[Dictionary] = []  ## [{text, color}] body of a single entity (cargo, queue, sell value, ...)
var owner_text: String = ""  ## FOREIGN: the owner's player name
var owner_color: Color = Color.WHITE
var show_vet: bool = true
var _hover: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(440.0, 130.0)


## Replaces the shown selection. `entries` are the first entries (at most `capacity()`), `p_total` the selected count.
func set_selection(list: Array[Dictionary], p_total: int, p_primary: int, p_mode: int) -> void:
	entries = list
	total = p_total
	primary_index = clampi(p_primary, 0, maxi(list.size() - 1, 0))
	mode = p_mode
	queue_redraw()


func set_details(p_chips: PackedStringArray, p_lines: Array[Dictionary]) -> void:
	chips = p_chips
	info_lines = p_lines
	queue_redraw()


func _cols() -> int:
	return maxi(int((size.x - PORTRAIT_W - 12.0 + float(UiMetrics.TILE_GAP)) / float(UiMetrics.TILE + UiMetrics.TILE_GAP)), 1)


func _rows() -> int:
	return maxi(int((size.y - HEADER_H + float(UiMetrics.TILE_GAP)) / float(UiMetrics.TILE + UiMetrics.TILE_GAP)), 1)


## Number of tiles that fit (the presenter reads at most this many entries).
func capacity() -> int:
	return _cols() * _rows()


func _tile_rect(i: int) -> Rect2:
	var cols: int = _cols()
	var step: float = float(UiMetrics.TILE + UiMetrics.TILE_GAP)
	return Rect2(PORTRAIT_W + 12.0 + float(i % cols) * step, HEADER_H + float(i / cols) * step, float(UiMetrics.TILE), float(UiMetrics.TILE))


func _multi() -> bool:
	return total > 1 and (mode == UiSelection.Mode.UNITS or mode == UiSelection.Mode.STRUCTURES)


func _index_at(p: Vector2) -> int:
	if not _multi():
		return -1
	var shown: int = mini(entries.size(), capacity())
	for i: int in shown:
		if _tile_rect(i).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		var h: int = _index_at(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var i: int = _index_at(mb.position)
		if i >= 0:
			tile_pressed.emit(i, (MOD_SHIFT if mb.shift_pressed else 0) | (MOD_CTRL if mb.is_command_or_control_pressed() else 0))
		accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var i: int = _index_at(at_position)
	if i < 0 or i >= entries.size():
		return ""
	var e: Dictionary = entries[i]
	return UiTooltipBody.encode({"title": String(e.get("name", "")), "text": "%d / %d HP" % [int(e.get("hp_now", 0)), int(e.get("hp_max", 0))], "hint": String(e.get("tip", ""))})


func _make_custom_tooltip(for_text: String) -> Object:
	return UiTooltipBody.make_from_text(for_text)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			_hover = -1
			queue_redraw()
		NOTIFICATION_THEME_CHANGED, NOTIFICATION_RESIZED:
			queue_redraw()


# ---- drawing ----------------------------------------------------------------------------------------------------------
func _draw() -> void:
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	if entries.is_empty() or mode == UiSelection.Mode.NONE:
		draw_string(head, Vector2(0.0, 20.0), "NO SELECTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiPalette.TEXT_MUTE)
		draw_string(UiFonts.get_font(UiFonts.Role.BODY), Vector2(0.0, 42.0), "Drag a box or click a unit to select. Double-click selects all of the same type on screen.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 8.0, 14, UiPalette.TEXT_MUTE)
		return
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
	var p: Dictionary = entries[primary_index]
	var pr := Rect2(0.0, 0.0, PORTRAIT_W, PORTRAIT_H)
	_plate(pr, true)
	_icon(p, pr, 44.0, true)
	draw_string(bold, Vector2(0.0, pr.end.y + 21.0), String(p.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, PORTRAIT_W, 18, UiPalette.TEXT)
	draw_string(body, Vector2(0.0, pr.end.y + 37.0), String(p.get("role", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, PORTRAIT_W, 14, UiPalette.TEXT_DIM)
	var hp: float = float(p.get("hp", 1000)) / 1000.0
	var bar := Rect2(0.0, size.y - 16.0, PORTRAIT_W, 15.0)
	_hp_bar(bar, hp, true)
	draw_string(num, Vector2(0.0, size.y - 4.0), "%d / %d" % [int(p.get("hp_now", 0)), int(p.get("hp_max", 0))], HORIZONTAL_ALIGNMENT_CENTER, PORTRAIT_W, 13, Color.WHITE)
	if show_vet and int(p.get("vet", 0)) > 0:
		for v: int in int(p["vet"]):
			var y: float = pr.position.y + 8.0 + float(v) * 6.0
			draw_polyline(PackedVector2Array([Vector2(6.0, y), Vector2(11.0, y + 3.5), Vector2(16.0, y)]), UiPalette.CREDITS, 1.8, true)
	if _multi():
		_draw_grid(acc, head, num)
	else:
		_draw_single(acc, bold, body)


func _draw_single(acc: Color, bold: Font, body: Font) -> void:
	var x: float = PORTRAIT_W + 16.0
	var y: float = 18.0
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	if mode == UiSelection.Mode.FOREIGN:
		draw_rect(Rect2(x, y - 12.0, 14.0, 14.0), owner_color)
		draw_string(bold, Vector2(x + 20.0, y), owner_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 24.0, 16, UiPalette.TEXT)
		y += 24.0
		_chip(Vector2(x, y - 14.0), "INSPECTING", UiPalette.TEXT_DIM)
		return
	draw_string(head, Vector2(x, y), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_DIM)
	var cx: float = x
	y += 10.0
	for c: String in chips:
		var w: float = _chip(Vector2(cx, y), c, _chip_color(c))
		cx += w + 6.0
	y += 34.0 if not chips.is_empty() else 12.0
	for ln: Dictionary in info_lines:
		draw_string(body, Vector2(x, y), String(ln.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8.0, 15, ln.get("color", UiPalette.TEXT_DIM))
		y += 20.0
	# squad pips
	var e: Dictionary = entries[primary_index]
	var sm: int = int(e.get("squad_max", 1))
	if sm > 1:
		var sq: int = int(e.get("squad", sm))
		draw_string(UiFonts.get_font(UiFonts.Role.NUM), Vector2(x, size.y - 4.0), "SQUAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_MUTE)
		for i: int in mini(sm, 8):
			var r := Rect2(x + 58.0 + float(i) * 12.0, size.y - 15.0, 9.0, 11.0)
			draw_rect(r, acc if i < sq else Color(UiPalette.LINE, 0.6))


func _chip_color(c: String) -> Color:
	match c:
		"OFFLINE", "EMP", "SUPPRESSED":
			return UiPalette.WARN
		"POWERED", "DEPLOYED":
			return UiPalette.OK
	return UiPalette.TEXT_DIM


## Small caps chip; returns its width.
func _chip(p: Vector2, text: String, col: Color) -> float:
	var f: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
	var r := Rect2(p, Vector2(w, 22.0))
	draw_rect(r, Color(col.darkened(0.6), 0.85))
	draw_rect(r, Color(col, 0.75), false, 1.0)
	draw_string(f, p + Vector2(7.0, 15.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.lightened(0.25))
	return w


func _draw_grid(acc: Color, head: Font, num: Font) -> void:
	var x0: float = PORTRAIT_W + 12.0
	draw_string(head, Vector2(x0, 14.0), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_DIM)
	draw_string(num, Vector2(x0, 14.0), "%d %s" % [total, "UNITS" if mode == UiSelection.Mode.UNITS else "STRUCTURES"], HORIZONTAL_ALIGNMENT_RIGHT, size.x - x0, 14, acc)
	var cap: int = capacity()
	var shown: int = mini(entries.size(), cap)
	var overflow: int = total - shown
	if overflow > 0:
		shown -= 1
		overflow += 1
	for i: int in shown:
		_tile(i)
	if overflow > 0 and shown < cap:
		var r: Rect2 = _tile_rect(shown)
		_plate(r, false)
		draw_string(head, Vector2(r.position.x, r.position.y + 29.0), "+%d" % overflow, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, UiPalette.TEXT_DIM)


func _tile(i: int) -> void:
	var e: Dictionary = entries[i]
	var r: Rect2 = _tile_rect(i)
	_plate(r, i == primary_index)
	_icon(e, r.grow(-1.0), 20.0)
	var hp: float = float(e.get("hp", 1000)) / 1000.0
	_hp_bar(Rect2(r.position.x + 2.0, r.end.y - 6.0, r.size.x - 4.0, 4.0), hp, false)
	if show_vet:
		for v: int in int(e.get("vet", 0)):
			var y: float = r.position.y + 4.0 + float(v) * 5.0
			draw_polyline(PackedVector2Array([Vector2(r.position.x + 4.0, y), Vector2(r.position.x + 8.0, y + 3.0), Vector2(r.position.x + 12.0, y)]), UiPalette.CREDITS, 1.5, true)
	var squad: int = int(e.get("squad", 1))
	if squad > 1:
		for s: int in mini(squad, 5):
			draw_rect(Rect2(r.end.x - 5.0 - float(s) * 4.0, r.position.y + 3.0, 3.0, 3.0), UiPalette.TEXT_DIM)
	if i == _hover:
		draw_rect(r, Color(1, 1, 1, 0.08))


func _plate(r: Rect2, emphasise: bool) -> void:
	var tint: Color = get_theme_color(&"tint", UiTheme.ACCENT_TYPE)
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	var top: Color = UiPalette.BG_RAISED.lerp(tint, 0.4)
	var bot: Color = UiPalette.BG_DEEP
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	draw_rect(r, acc if emphasise else UiPalette.LINE_DIM, false, 1.0)


func _icon(e: Dictionary, r: Rect2, glyph_size: float, large: bool = false) -> void:
	var tex: Texture2D = e.get("icon") as Texture2D
	if large and e.get("portrait") is Texture2D:
		tex = e["portrait"] as Texture2D
	if tex != null:
		draw_texture_rect(tex, _fit(tex, r), false)
	else:
		var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		UiGlyphs.draw(self, int(e.get("glyph", UiGlyphs.Glyph.VEHICLES)), Rect2(r.get_center() - Vector2(glyph_size, glyph_size) * 0.5, Vector2(glyph_size, glyph_size)), acc.darkened(0.1), 1.8)


func _hp_bar(bar: Rect2, hp: float, ticks: bool) -> void:
	draw_rect(bar, Color(0, 0, 0, 0.7))
	var inner := Rect2(bar.position + Vector2.ONE, Vector2((bar.size.x - 2.0) * clampf(hp, 0.0, 1.0), bar.size.y - 2.0))
	draw_rect(inner, hp_color(hp).darkened(0.2 if ticks else 0.0))
	if ticks:
		for t: float in [0.33, 0.66]:
			var tx: float = bar.position.x + 1.0 + (bar.size.x - 2.0) * t
			draw_line(Vector2(tx, bar.position.y + 1.0), Vector2(tx, bar.end.y - 1.0), Color(0, 0, 0, 0.55), 1.0)


static func _fit(tex: Texture2D, r: Rect2) -> Rect2:
	var a: float = float(tex.get_width()) / float(maxi(tex.get_height(), 1))
	var w: float = minf(r.size.x, r.size.y * a)
	var h: float = w / a
	return Rect2(r.position + (r.size - Vector2(w, h)) * 0.5, Vector2(w, h))


## HP ramp: OK >= 66 %, WARN 33-66 %, DANGER below (style.ui.hp_ramp).
static func hp_color(hp: float) -> Color:
	if hp >= 0.66:
		return UiPalette.OK
	if hp >= 0.33:
		return UiPalette.WARN
	return UiPalette.DANGER
