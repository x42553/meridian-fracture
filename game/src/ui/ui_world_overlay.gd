class_name UiWorldOverlay
extends Control
## Small 2D screen-space layer above the 3D view (ui.md 3.4): order-issue markers, the support-power / superweapon
## targeting preview (circle, capsule or line projected onto the ground as polylines, red hatch when own units are
## inside) and off-screen alert arrows. Everything else in the world (rings, health bars, lines, placement ghost) is the
## view's. Redraws every frame only while something is alive; mouse-transparent. Projection goes through `project`, a
## Callable (sim_x: int, sim_y: int) -> Vector2 returning (INF, INF) for points behind the camera; `setup` binds it to
## a view port (`camera()` + `sim_to_world`).

const SHAPE_CIRCLE: int = 0
const SHAPE_CAPSULE: int = 1
const SHAPE_LINE: int = 2
const MARKER_LIFE_S: float = 0.6
const EDGE_LIFE_S: float = 4.0
const EDGE_MARGIN: float = 44.0

## Kind -> colour of `UiOrderIntent.MK_*`.
const _MARKER_COLORS: Array[Color] = [
	Color("#5ce383"), Color("#ff5555"), Color("#ffb52a"), Color("#49d0ff"), Color("#ffd35c"), Color("#5ce383"), Color("#ffd35c"), Color("#ff5555"),
]

var project: Callable = Callable()
var strategic_markers: bool = false

var _view: Object = null
var _markers: Array[Dictionary] = []  ## {kind, x, y, t}
var _edges: Array[Dictionary] = []  ## {x, y, kind, t}
var _prev: Dictionary = {}  ## the targeting preview, empty = none
var _pts: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)


func setup(view: Object, _port: UiSimPort) -> void:
	_view = view
	if view != null and view.has_method("camera") and view.has_method("sim_to_world"):
		project = Callable(self, "_project_via_view")


func _project_via_view(x: int, y: int) -> Vector2:
	var cam: Camera3D = _view.call("camera") as Camera3D
	if cam == null:
		return Vector2(INF, INF)
	var w: Vector3 = _view.call("sim_to_world", x, y)
	if cam.is_position_behind(w):
		return Vector2(INF, INF)
	return cam.unproject_position(w)


## 0.6 s feedback flash at a ground point (5.8.7); `kind` = `UiOrderIntent.MK_*`.
func add_order_marker(kind: int, sim_x: int, sim_y: int) -> void:
	if kind < 0:
		return
	_markers.append({"kind": kind, "x": sim_x, "y": sim_y, "t": 0.0})
	_wake()


## Circle / capsule / line projected onto the ground. `radius_units` and `length_units` in sim units, `angle` binary 0-4095.
func set_targeting_preview(shape: int, sim_x: int, sim_y: int, radius_units: int, angle: int, length_units: int, valid: bool, friendly_fire: bool) -> void:
	_prev = {"shape": shape, "x": sim_x, "y": sim_y, "r": radius_units, "a": angle, "len": length_units, "valid": valid, "ff": friendly_fire}
	_wake()


func clear_targeting_preview() -> void:
	if not _prev.is_empty():
		_prev = {}
		queue_redraw()


func has_preview() -> bool:
	return not _prev.is_empty()


## Arrow + glyph on the screen edge pointing at an off-screen alert for 4 s (A-07: alerts never rely on sound alone).
func add_edge_alert(sim_x: int, sim_y: int, kind: int) -> void:
	_edges.append({"x": sim_x, "y": sim_y, "kind": kind, "t": 0.0})
	_wake()


func set_strategic_markers(on: bool) -> void:
	strategic_markers = on


func marker_count() -> int:
	return _markers.size()


func _wake() -> void:
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	for i: int in range(_markers.size() - 1, -1, -1):
		_markers[i]["t"] = float(_markers[i]["t"]) + delta
		if float(_markers[i]["t"]) > MARKER_LIFE_S:
			_markers.remove_at(i)
	for j: int in range(_edges.size() - 1, -1, -1):
		_edges[j]["t"] = float(_edges[j]["t"]) + delta
		if float(_edges[j]["t"]) > EDGE_LIFE_S:
			_edges.remove_at(j)
	queue_redraw()
	if _markers.is_empty() and _edges.is_empty() and _prev.is_empty():
		set_process(false)


func _pt(x: int, y: int) -> Vector2:
	if not project.is_valid():
		return Vector2(INF, INF)
	return project.call(x, y)


func _draw() -> void:
	if not project.is_valid():
		return
	var bounds := Rect2(Vector2.ZERO, size)
	for m: Dictionary in _markers:
		var p: Vector2 = _pt(int(m["x"]), int(m["y"]))
		if not p.is_finite():
			continue
		var k: float = float(m["t"]) / MARKER_LIFE_S
		var col: Color = _MARKER_COLORS[clampi(int(m["kind"]), 0, _MARKER_COLORS.size() - 1)]
		var rad: float = lerpf(20.0, 7.0, k)
		draw_arc(p, rad, 0.0, TAU, 24, Color(col, 1.0 - k), 2.0, true)
		for q: int in 4:
			var a: float = float(q) * PI * 0.5 + PI * 0.25
			var d := Vector2(cos(a), sin(a))
			draw_line(p + d * (rad + 2.0), p + d * (rad + 8.0), Color(col, 1.0 - k), 2.0, true)
	if not _prev.is_empty():
		_draw_preview()
	for e: Dictionary in _edges:
		var p2: Vector2 = _pt(int(e["x"]), int(e["y"]))
		if p2.is_finite() and bounds.has_point(p2):
			continue
		var c: Vector2 = bounds.get_center()
		var dir: Vector2 = (p2 - c) if p2.is_finite() else Vector2(0, -1)
		if dir.length() < 1.0:
			continue
		dir = dir.normalized()
		var inner: Rect2 = bounds.grow(-EDGE_MARGIN)
		var edge: Vector2 = UiDraw.rect_boundary(inner, atan2(dir.x, -dir.y))
		var fade: float = clampf((EDGE_LIFE_S - float(e["t"])) / 0.6, 0.0, 1.0) * (0.65 + 0.35 * UiMotion.pulse(float(e["t"]), 2.0))
		var col2: Color = UiPalette.DANGER if int(e["kind"]) >= 3 else UiPalette.WARN
		var n := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([edge + dir * 16.0, edge - dir * 6.0 + n * 12.0, edge - dir * 6.0 - n * 12.0]), Color(col2, fade))
		UiGlyphs.draw(self, UiGlyphs.Glyph.WARNING, Rect2(edge - dir * 26.0 - Vector2(9.0, 9.0), Vector2(18.0, 18.0)), Color(col2.lightened(0.3), fade), 1.6)


func _draw_preview() -> void:
	var valid: bool = bool(_prev["valid"])
	var col: Color = UiPalette.OK if valid else UiPalette.DANGER
	if bool(_prev["ff"]):
		col = UiPalette.WARN
	var cx: int = int(_prev["x"])
	var cy: int = int(_prev["y"])
	var poly: PackedVector2Array = preview_ground_points(int(_prev["shape"]), cx, cy, int(_prev["r"]), int(_prev["a"]), int(_prev["len"]))
	_pts.resize(0)
	for gp: Vector2 in poly:
		var sp: Vector2 = _pt(int(gp.x), int(gp.y))
		if not sp.is_finite():
			return
		_pts.append(sp)
	if _pts.size() < 3:
		return
	draw_colored_polygon(_pts, Color(col, 0.14))
	var loop: PackedVector2Array = _pts.duplicate()
	loop.append(_pts[0])
	draw_polyline(loop, Color(col, 0.95), 2.0, true)
	if bool(_prev["ff"]):
		var r2: Rect2 = Rect2(_pts[0], Vector2.ZERO)
		for p: Vector2 in _pts:
			r2 = r2.expand(p)
		var hatch := Color(UiPalette.DANGER, 0.45)
		var step: float = 12.0
		var x: float = r2.position.x - r2.size.y
		while x < r2.end.x:
			var a: Vector2 = Vector2(x, r2.end.y)
			var b: Vector2 = Vector2(x + r2.size.y, r2.position.y)
			for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), _pts):
				if piece.size() >= 2:
					draw_polyline(piece, hatch, 1.5)
			x += step
	var c: Vector2 = _pt(cx, cy)
	if c.is_finite():
		draw_circle(c, 3.0, Color(col, 0.95))


## Ground outline in sim units of a preview shape (pure; the overlay projects each point).
static func preview_ground_points(shape: int, x: int, y: int, radius_units: int, angle: int, length_units: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r: float = float(maxi(radius_units, 256))
	if shape == SHAPE_CIRCLE:
		for i: int in 40:
			var a: float = float(i) / 40.0 * TAU
			out.append(Vector2(float(x) + cos(a) * r, float(y) + sin(a) * r))
		return out
	var ang: float = float(angle) * TAU / 4096.0
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var c := Vector2(float(x), float(y))
	var half_len: float = float(maxi(length_units, 1024)) * 0.5
	var half_w: float = r
	if shape == SHAPE_LINE:
		out.append(c - d * half_len - n * half_w)
		out.append(c + d * half_len - n * half_w)
		out.append(c + d * half_len + n * half_w)
		out.append(c - d * half_len + n * half_w)
		return out
	# capsule: the corridor with rounded ends
	for i2: int in 9:
		var a2: float = ang - PI * 0.5 + float(i2) / 8.0 * PI
		out.append(c + d * half_len + Vector2(cos(a2), sin(a2)) * half_w)
	for i3: int in 9:
		var a3: float = ang + PI * 0.5 + float(i3) / 8.0 * PI
		out.append(c - d * half_len + Vector2(cos(a3), sin(a3)) * half_w)
	return out
