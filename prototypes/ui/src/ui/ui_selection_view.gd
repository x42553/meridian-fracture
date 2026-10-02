class_name UiSelectionView
extends Control
## Left part of the bottom-centre panel: large portrait + name + health of the primary selection, and a
## tile grid of every selected entity (portrait, health bar, veterancy chevrons, squad pips, +N overflow).
## Entry dictionary: {name, role, hp: float 0..1, hp_max: int, vet: int 0..3, squad: int, icon: Texture2D}.

signal tile_clicked(index: int, shift: bool, ctrl: bool)

const TILE := 46.0
const GAP := 4.0
const PORTRAIT_W := 152.0
const GRID_TOP := 24.0

var skin: UiSkin
var entries: Array[Dictionary] = []
var primary: int = 0
var _hover: int = -1

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(560.0, 130.0)

func set_entries(list: Array[Dictionary], primary_index: int = 0) -> void:
	entries = list
	primary = clampi(primary_index, 0, maxi(list.size() - 1, 0))
	queue_redraw()

func _cols() -> int:
	return maxi(int((size.x - PORTRAIT_W - 12.0 + GAP) / (TILE + GAP)), 1)

func _rows() -> int:
	return maxi(int((size.y - GRID_TOP + GAP) / (TILE + GAP)), 1)

func _tile_rect(i: int) -> Rect2:
	var cols: int = _cols()
	return Rect2(PORTRAIT_W + 12.0 + float(i % cols) * (TILE + GAP), GRID_TOP + float(i / cols) * (TILE + GAP), TILE, TILE)

func _index_at(p: Vector2) -> int:
	var cap: int = _cols() * _rows()
	for i in mini(entries.size(), cap):
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
			tile_clicked.emit(i, mb.shift_pressed, mb.is_command_or_control_pressed())
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()

func _draw() -> void:
	if entries.is_empty():
		draw_string(UiFonts.get_font(UiFonts.Role.HEAD), Vector2(0.0, 40.0), "NO SELECTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_MUTE)
		return
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
	var p: Dictionary = entries[primary]
	var pr := Rect2(0.0, 0.0, PORTRAIT_W, 76.0)
	_tile_backdrop(pr, true)
	if p.get("icon") != null:
		draw_texture_rect(p["icon"], _fit(p["icon"], pr), false)
	draw_string(bold, Vector2(0.0, pr.end.y + 20.0), String(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, PORTRAIT_W, 18, UiPalette.TEXT)
	draw_string(body, Vector2(0.0, pr.end.y + 36.0), String(p.get("role", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, PORTRAIT_W, 12, UiPalette.TEXT_DIM)
	var hp: float = float(p["hp"])
	var bar := Rect2(0.0, size.y - 15.0, PORTRAIT_W, 14.0)
	draw_rect(bar, Color(0, 0, 0, 0.7))
	draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2((bar.size.x - 2.0) * hp, bar.size.y - 2.0)), _hp_color(hp).darkened(0.25))
	draw_string(num, Vector2(0.0, size.y - 4.0), "%d / %d" % [int(hp * float(p.get("hp_max", 100))), int(p.get("hp_max", 100))], HORIZONTAL_ALIGNMENT_CENTER, PORTRAIT_W, 12, Color.WHITE)
	draw_string(head, Vector2(PORTRAIT_W + 12.0, 14.0), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiPalette.TEXT_DIM)
	draw_string(num, Vector2(PORTRAIT_W + 12.0, 14.0), "%d UNITS" % entries.size(), HORIZONTAL_ALIGNMENT_RIGHT, size.x - PORTRAIT_W - 12.0, 12, skin.accent)
	var cap: int = _cols() * _rows()
	var shown: int = mini(entries.size(), cap)
	var overflow: int = entries.size() - shown
	if overflow > 0:
		shown -= 1
	for i in shown:
		_tile(i)
	if overflow > 0:
		var r: Rect2 = _tile_rect(shown)
		_tile_backdrop(r, false)
		draw_string(head, Vector2(r.position.x, r.position.y + 29.0), "+%d" % (overflow + 1), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, UiPalette.TEXT_DIM)

func _tile(i: int) -> void:
	var e: Dictionary = entries[i]
	var r: Rect2 = _tile_rect(i)
	_tile_backdrop(r, i == primary)
	if e.get("icon") != null:
		draw_texture_rect(e["icon"], _fit(e["icon"], r.grow(-1.0)), false)
	var hp: float = float(e["hp"])
	var b := Rect2(r.position.x + 2.0, r.end.y - 6.0, r.size.x - 4.0, 4.0)
	draw_rect(b, Color(0, 0, 0, 0.75))
	draw_rect(Rect2(b.position + Vector2(0.5, 0.5), Vector2((b.size.x - 1.0) * hp, b.size.y - 1.0)), _hp_color(hp))
	for v in int(e.get("vet", 0)):
		var y: float = r.position.y + 4.0 + float(v) * 5.0
		draw_polyline(PackedVector2Array([Vector2(r.position.x + 4.0, y), Vector2(r.position.x + 8.0, y + 3.0), Vector2(r.position.x + 12.0, y)]), UiPalette.CREDITS, 1.5, true)
	var squad: int = int(e.get("squad", 1))
	if squad > 1:
		for s in squad:
			draw_rect(Rect2(r.end.x - 5.0 - float(s) * 4.0, r.position.y + 3.0, 3.0, 3.0), UiPalette.TEXT_DIM)
	if i == _hover:
		draw_rect(r, Color(1, 1, 1, 0.08))

func _tile_backdrop(r: Rect2, emphasise: bool) -> void:
	var top: Color = Color("#141e2a").lerp(skin.tint, 0.4)
	var bot: Color = Color("#070b10")
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	draw_rect(r, skin.accent if emphasise else UiPalette.LINE_DIM, false, 1.0)

## Aspect-preserving "contain" rect for a texture inside `r`.
static func _fit(tex: Texture2D, r: Rect2) -> Rect2:
	var a: float = float(tex.get_width()) / float(tex.get_height())
	var w: float = minf(r.size.x, r.size.y * a)
	var h: float = w / a
	return Rect2(r.position + (r.size - Vector2(w, h)) * 0.5, Vector2(w, h))

static func _hp_color(hp: float) -> Color:
	if hp > 0.6:
		return UiPalette.OK
	if hp > 0.3:
		return UiPalette.WARN
	return UiPalette.DANGER
