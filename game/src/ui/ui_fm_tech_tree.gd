class_name UiFmTechTree
extends Control
## Tech tree page of the Field Manual (ui.md 5.17): the structures of a roster as a layered graph. Layout from
## `UiFmModel.tech_tree()`: column `x = depth * 220`, rows in order, nodes 180 x 44, elbow edges from a requirement to the
## structure it unlocks. A click emits `node_selected(kind, index)`; the node of `highlight` is outlined.

signal node_selected(kind: int, def_index: int)

const NODE_W: float = 180.0
const NODE_H: float = 44.0
const COL_W: float = 220.0
const ROW_H: float = 62.0
const PAD: float = 24.0

var _nodes: Array[Dictionary] = []
var _edges: Array = []
var _rects: Dictionary = {}  ## key -> Rect2
var _hover: int = -1
var highlight: int = -1
## True: the columns shrink to the width the page gives the graph (no horizontal scrollbar at 1280 x 720); false: the fixed 220 px columns.
var fit_width: bool = false
var _node_w: float = NODE_W
var _tree: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## `tree` is `UiFmModel.tech_tree()`.
func set_tree(tree: Dictionary) -> void:
	_tree = tree
	_nodes.clear()
	for n: Variant in tree.get("nodes", []) as Array:
		_nodes.append(n as Dictionary)
	_edges = tree.get("edges", []) as Array
	_relayout()


func _relayout() -> void:
	_rects.clear()
	var cols: int = 1
	for n: Dictionary in _nodes:
		cols = maxi(cols, int(n["column"]) + 1)
	var col_w: float = COL_W
	_node_w = NODE_W
	if fit_width and size.x > 0.0:
		col_w = clampf((size.x - 2.0 * PAD) / float(cols), 100.0, COL_W)
		_node_w = clampf(col_w - 34.0, 88.0, NODE_W)
	var max_x: float = 0.0
	var max_y: float = 0.0
	for n2: Dictionary in _nodes:
		var r: Rect2 = Rect2(PAD + float(int(n2["column"])) * col_w, PAD + float(int(n2["row"])) * ROW_H, _node_w, NODE_H)
		_rects[(int(n2["kind"]) << 24) | int(n2["index"])] = r
		max_x = maxf(max_x, r.end.x)
		max_y = maxf(max_y, r.end.y)
	custom_minimum_size = Vector2(0.0 if fit_width else max_x + PAD, max_y + PAD)
	queue_redraw()


func node_count() -> int:
	return _nodes.size()


func rect_of(kind: int, def_index: int) -> Rect2:
	return _rects.get((kind << 24) | def_index, Rect2()) as Rect2


func _gui_input(event: InputEvent) -> void:
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		var h: int = _node_at(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var i: int = _node_at(mb.position)
		if i >= 0:
			node_selected.emit(int(_nodes[i]["kind"]), int(_nodes[i]["index"]))
			accept_event()


func _node_at(p: Vector2) -> int:
	for i: int in _nodes.size():
		if rect_of(int(_nodes[i]["kind"]), int(_nodes[i]["index"])).has_point(p):
			return i
	return -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()
	elif what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()
	elif what == NOTIFICATION_RESIZED and fit_width:
		_relayout()


func _draw() -> void:
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	for e: Variant in _edges:
		var a: Rect2 = _rects.get((e as Array)[0], Rect2()) as Rect2
		var b: Rect2 = _rects.get((e as Array)[1], Rect2()) as Rect2
		if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
			continue
		var p0: Vector2 = Vector2(a.end.x, a.get_center().y)
		var p1: Vector2 = Vector2(b.position.x, b.get_center().y)
		var mid: float = (p0.x + p1.x) * 0.5
		var hot: bool = _hover >= 0 and (rect_of(int(_nodes[_hover]["kind"]), int(_nodes[_hover]["index"])) in [a, b])
		var col: Color = acc if hot else Color(UiPalette.LINE_BRIGHT, 0.7)
		draw_polyline(PackedVector2Array([p0, Vector2(mid, p0.y), Vector2(mid, p1.y), p1]), col, 2.0 if hot else 1.5)
	var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	for i: int in _nodes.size():
		var n: Dictionary = _nodes[i]
		var r: Rect2 = rect_of(int(n["kind"]), int(n["index"]))
		var hot2: bool = i == _hover
		var sel: bool = highlight == ((int(n["kind"]) << 24) | int(n["index"]))
		draw_rect(r, UiPalette.BG_HOVER if hot2 or sel else UiPalette.BG_CONTROL)
		draw_rect(r, acc if hot2 or sel else UiPalette.LINE, false, 2.0 if sel else 1.0)
		draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), acc)
		var fs: int = 16 if _node_w >= 150.0 else 13
		var txt: String = UiDraw.ellipsize(bold, str(n["name"]), fs, _node_w - 22.0)
		draw_string(bold, r.position + Vector2(14.0, 27.0 if fs == 16 else 26.0), txt, HORIZONTAL_ALIGNMENT_LEFT, _node_w - 22.0, fs, UiPalette.TEXT)
