class_name UiFixtureOverlay
extends Control
## 2D stand-ins for the interaction visuals the REAL view owns in 3D (ui.md 3.2.2): selection brackets, health bars, hover
## ring, range rings, rally / order lines and the placement ghost. Drawn over the fixture battlefield from the state the
## UI pushes through `UiViewPortFixture` (`set_selection`, `set_hover`, ...). `MOUSE_FILTER_IGNORE`; redrawn by the adapter.

const RING_STEPS: int = 48
const M_PER_UNIT: float = 3.0 / 1024.0

var view: UiViewPortFixture = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if view == null:
		return
	var cam: Camera3D = view.camera()
	if cam == null or not cam.is_inside_tree():
		return
	var ok: Color = UiPalette.semantic(&"ok")
	_draw_ghost(cam)
	for id: int in view.range_ring_ids:
		_ring(cam, id, float(view.sim().range_max(id)) * M_PER_UNIT, Color(UiPalette.WARN, 0.75))
	_draw_lines(cam)
	if view.hover_id >= 0 and not view.selection_ids.has(view.hover_id):
		_ring(cam, view.hover_id, view.radius_of(view.hover_id) * 0.9, Color(1.0, 1.0, 1.0, 0.8))
	for id: int in view.selection_ids:
		var r: Rect2 = view.entity_screen_rect(id)
		if r.size == Vector2.ZERO:
			continue
		_ring(cam, id, view.radius_of(id) * 0.8, Color(ok, 0.55))
		_brackets(r.grow(3.0), ok)
	if view.bar_mode != 0:
		_draw_bars(view.bar_mode)


func _brackets(r: Rect2, col: Color) -> void:
	var l: float = clampf(minf(r.size.x, r.size.y) * 0.32, 5.0, 12.0)
	var segs: PackedVector2Array = PackedVector2Array()
	var sx: Vector2 = Vector2(l, 0.0)
	var sy: Vector2 = Vector2(0.0, l)
	var p: Vector2 = r.position
	var e: Vector2 = r.end
	segs.append_array([p, p + sx, p, p + sy, Vector2(e.x, p.y), Vector2(e.x, p.y) - sx, Vector2(e.x, p.y), Vector2(e.x, p.y) + sy])
	segs.append_array([e, e - sx, e, e - sy, Vector2(p.x, e.y), Vector2(p.x, e.y) + sx, Vector2(p.x, e.y), Vector2(p.x, e.y) - sy])
	draw_multiline(segs, Color(0.0, 0.0, 0.0, 0.55), 3.5)
	draw_multiline(segs, col, 1.8)


func _draw_bars(mode: int) -> void:
	var ids: PackedInt32Array = view.pd().ids
	for i: int in view.pd().count:
		var frac: float = view.hp_frac_of_slot(i)
		var sel: bool = view.selection_ids.has(ids[i])
		var shown: bool = mode == 3 or (mode == 1 and sel) or (mode == 2 and (sel or frac < 0.999))
		if not shown or (view.pd().flags[i] & UiPickData.F_GHOST) != 0:
			continue
		var r: Rect2 = view.entity_screen_rect(ids[i])
		if r.size == Vector2.ZERO:
			continue
		var w: float = clampf(r.size.x * 0.8, 22.0, 64.0)
		var bar: Rect2 = Rect2(Vector2(r.get_center().x - w * 0.5, r.position.y - 9.0), Vector2(w, 4.0))
		var col: Color = UiPalette.semantic(&"ok") if frac > 0.6 else (UiPalette.semantic(&"warn") if frac > 0.3 else UiPalette.semantic(&"danger"))
		draw_rect(bar.grow(1.0), Color(0.0, 0.0, 0.0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(frac, 0.0, 1.0), bar.size.y)), col)


## A ground circle of `radius_m` around entity `id`.
func _ring(cam: Camera3D, id: int, radius_m: float, col: Color) -> void:
	var c: Vector3 = view.entity_world_pos(id)
	if radius_m <= 0.05 or cam.is_position_behind(c):
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in RING_STEPS + 1:
		var a: float = TAU * float(i) / float(RING_STEPS)
		var w: Vector3 = Vector3(c.x + cos(a) * radius_m, view.ground_height(c.x + cos(a) * radius_m, c.z + sin(a) * radius_m) + 0.05, c.z + sin(a) * radius_m)
		if cam.is_position_behind(w):
			return
		pts.append(cam.unproject_position(w))
	draw_polyline(pts, Color(0.0, 0.0, 0.0, col.a * 0.5), 3.0)
	draw_polyline(pts, col, 1.4)


func _draw_lines(cam: Camera3D) -> void:
	var accent: Color = Color(UiPalette.semantic(&"ok"), 0.9)
	var q: PackedInt32Array = PackedInt32Array()
	for id: int in view.order_ids:
		var n: int = view.sim().order_queue(id, q)
		var prev: Vector3 = view.entity_world_pos(id)
		for i: int in n:
			var wp: Vector3 = view.sim_to_world(q[i * UiSimPort.OQ_STRIDE + 1], q[i * UiSimPort.OQ_STRIDE + 2])
			_line(cam, prev, wp, accent)
			prev = wp
	var row := UiEntityRow.new()
	for id: int in view.rally_ids:
		if view.sim().read(id, row) and row.rally_x >= 0:
			_line(cam, view.entity_world_pos(id), view.sim_to_world(row.rally_x, row.rally_y), Color(UiPalette.CREDITS, 0.9))


func _line(cam: Camera3D, a: Vector3, b: Vector3, col: Color) -> void:
	if cam.is_position_behind(a) or cam.is_position_behind(b):
		return
	var pa: Vector2 = cam.unproject_position(a)
	var pb: Vector2 = cam.unproject_position(b)
	draw_line(pa, pb, Color(0.0, 0.0, 0.0, 0.5), 3.0)
	draw_line(pa, pb, col, 1.5)
	draw_circle(pb, 3.5, col)


func _draw_ghost(cam: Camera3D) -> void:
	var g: Dictionary = view.ghost
	if g.is_empty() or not (g.get("result") is SimPlacementResult):
		return
	var res: SimPlacementResult = g["result"]
	var m: float = 3.0
	for i: int in res.cells.size():
		var cx: int = res.ox + i % maxi(res.w, 1)
		var cy: int = res.oy + i / maxi(res.w, 1)
		var x0: float = float(cx) * m
		var z0: float = float(cy) * m
		var quad: PackedVector2Array = PackedVector2Array()
		var behind: bool = false
		for c: Vector2 in [Vector2(x0, z0), Vector2(x0 + m, z0), Vector2(x0 + m, z0 + m), Vector2(x0, z0 + m)]:
			var w: Vector3 = Vector3(c.x, view.ground_height(c.x, c.y) + 0.08, c.y)
			behind = behind or cam.is_position_behind(w)
			quad.append(cam.unproject_position(w))
		if behind:
			continue
		var col: Color = UiPalette.semantic(&"ok") if res.cells[i] == 0 else UiPalette.semantic(&"danger")
		draw_colored_polygon(quad, Color(col, 0.38))
		quad.append(quad[0])
		draw_polyline(quad, Color(col, 0.9), 1.2)
