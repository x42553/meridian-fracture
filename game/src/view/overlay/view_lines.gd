class_name ViewLines
extends Node3D
## Rally lines, waypoint / order paths and a transient preview (render spec 5.10). Order lines come from the queued orders
## (`SimEntity.orders`) of the SELECTED OWN units only (enemy orders are never read); rally lines from
## `ViewSimReader.rally_of(structure)`. Everything is one ribbon mesh (line.gdshader: constant pixel width, marching dashes,
## ground following, 3 m samples lifted 0.15 m), rebuilt only when the sources or the orders change and at most 10 Hz.
## Presentation only: it reads the sim and never writes it.

const MAX_UNITS: int = 32
const MAX_WAYPOINTS: int = 8
const MAX_RALLY: int = 16
const STEP_M: float = 3.0
const STEP_FAR_M: float = 6.0
const LONG_LEG_M: float = 60.0
const MIN_INTERVAL_S: float = 0.1
const END_RING_M: float = 0.9
const WP_RING_M: float = 0.6
const LIFT_M: float = 0.15

const COL_MOVE: Color = Color(0.30, 1.0, 0.40, 0.95)
const COL_ATTACK: Color = Color(1.0, 0.30, 0.25, 0.95)
const COL_ATTACK_MOVE: Color = Color(1.0, 0.60, 0.15, 0.95)
const COL_GUARD: Color = Color(0.30, 0.60, 1.0, 0.95)
const COL_SUPPORT: Color = Color(1.0, 0.90, 0.30, 0.95)  ## capture / repair / salvage
const COL_ECON: Color = Color(0.95, 0.75, 0.20, 0.95)  ## harvest / return cash
const COL_TRANSPORT: Color = Color(1.0, 1.0, 1.0, 0.9)  ## load / unload / garrison
const COL_RALLY: Color = Color(0.30, 1.0, 0.40, 0.9)
const COL_RALLY_HARVEST: Color = Color(1.0, 0.90, 0.30, 0.9)

var count_lines: int = 0  ## lines drawn at the last rebuild (tests)
var rebuilds: int = 0

var _v: ViewWorld = null
var _ribbon: ViewRibbon = null
var _rally_ids: PackedInt32Array = PackedInt32Array()
var _order_ids: PackedInt32Array = PackedInt32Array()
var _preview_pts: PackedVector3Array = PackedVector3Array()
var _preview_col: Color = COL_MOVE
var _sig: int = 0
var _cool: float = 0.0
var _dirty: bool = true
var _ground: Callable = Callable()
var _tmp: PackedInt32Array = PackedInt32Array([0, 0, 0])


func setup(v: ViewWorld) -> void:
	_v = v
	_ground = Callable(v, "ground_at")
	_ribbon = ViewRibbon.new()
	_ribbon.setup(self, 4.0, ViewLayers.PRIO_LINES)
	_ribbon.material.set_shader_parameter(&"outline_px", 1.5)
	_ribbon.material.set_shader_parameter(&"intensity", 1.1)
	if v.terrain != null:
		_ribbon.set_bounds(Rect2(Vector2.ZERO, v.terrain.world_size()))


## Producers whose rally point is drawn (the selected structures); own structures only, at most 16.
func set_rally_sources(structure_ids: PackedInt32Array) -> void:
	_rally_ids = structure_ids.duplicate()
	_dirty = true


## Selected units whose queued orders are drawn (at most 32 units x 8 waypoints).
func set_order_sources(unit_ids: PackedInt32Array) -> void:
	_order_ids = unit_ids.duplicate()
	_dirty = true


## Transient path / drag preview (world points, ground already applied or not: the ribbon lifts them); empty clears it.
func set_preview(points: PackedVector3Array, color: Color) -> void:
	_preview_pts = points.duplicate()
	_preview_col = color
	_dirty = true


func clear() -> void:
	_rally_ids = PackedInt32Array()
	_order_ids = PackedInt32Array()
	_preview_pts = PackedVector3Array()
	_dirty = true


func _process(delta: float) -> void:
	update(delta)


func update(dt: float) -> void:
	if _v == null or _ribbon == null or _v.sim == null:
		return
	_cool -= dt
	if _cool > 0.0:
		return
	var sig: int = _signature()
	if sig == _sig and not _dirty:
		return
	_cool = MIN_INTERVAL_S
	_sig = sig
	_dirty = false
	_rebuild()


## Cheap hash of the sources, their orders (type, target, point) and the quantised unit positions.
func _signature() -> int:
	var h: int = 17
	var w: SimWorld = _v.sim
	var n: int = 0
	for id: int in _order_ids:
		if n >= MAX_UNITS:
			break
		var e: SimEntity = w.get_entity(id)
		if e == null:
			continue
		n += 1
		h = h * 31 + id
		var ve: ViewEntity = _v.entity_view(id)
		if ve != null:
			h = h * 31 + int(ve.wx * 4.0) * 7919 + int(ve.wz * 4.0)
		var k: int = 0
		for o: SimOrder in e.orders:
			if k >= MAX_WAYPOINTS:
				break
			k += 1
			h = h * 31 + o.type * 1009 + o.target_id * 17 + o.x * 3 + o.y
	for rid: int in _rally_ids:
		var re: SimEntity = w.get_entity(rid)
		if re == null:
			continue
		h = h * 31 + rid
		if ViewSimReader.rally_of(re, _tmp):
			h = h * 31 + _tmp[0] * 5 + _tmp[1] * 3 + _tmp[2]
	h = h * 31 + _preview_pts.size()
	if not _preview_pts.is_empty():
		h = h * 31 + int(_preview_pts[_preview_pts.size() - 1].x * 4.0) + int(_preview_pts[_preview_pts.size() - 1].z * 4.0) * 131
	return h


func _rebuild() -> void:
	rebuilds += 1
	_ribbon.begin()
	count_lines = 0
	var w: SimWorld = _v.sim
	var units_drawn: int = 0
	for id: int in _order_ids:
		if units_drawn >= MAX_UNITS:
			break
		var e: SimEntity = w.get_entity(id)
		var ve: ViewEntity = _v.entity_view(id)
		if e == null or ve == null or e.owner != _v.local_pid or e.orders.is_empty():
			continue
		units_drawn += 1
		_unit_path(e, ve)
	var rallies: int = 0
	for rid: int in _rally_ids:
		if rallies >= MAX_RALLY:
			break
		var re: SimEntity = w.get_entity(rid)
		var rv: ViewEntity = _v.entity_view(rid)
		if re == null or rv == null or re.owner != _v.local_pid:
			continue
		if ViewSimReader.rally_of(re, _tmp):
			rallies += 1
			_rally_line(rv, _tmp[0], _tmp[1], _tmp[2])
	if _preview_pts.size() >= 2:
		var lifted: PackedVector3Array = PackedVector3Array()
		for p: Vector3 in _preview_pts:
			lifted.append(Vector3(p.x, maxf(p.y, _v.ground_at(p.x, p.z)) + LIFT_M, p.z))
		_ribbon.add_polyline(lifted, _preview_col, ViewRibbon.STYLE_MARCH)
		count_lines += 1
	_ribbon.commit()


func _unit_path(e: SimEntity, ve: ViewEntity) -> void:
	var cur: Vector2 = Vector2(ve.wx, ve.wz)
	var k: int = 0
	for o: SimOrder in e.orders:
		if k >= MAX_WAYPOINTS:
			break
		var dest: Vector2 = Vector2.INF
		var col: Color = COL_MOVE
		match o.type:
			SimOrder.T_MOVE, SimOrder.T_PATROL, SimOrder.T_LAND, SimOrder.T_DEPLOY_MCV, SimOrder.T_UNLOAD:
				col = COL_MOVE if o.type != SimOrder.T_UNLOAD else COL_TRANSPORT
				dest = _order_point(o)
			SimOrder.T_FOLLOW:
				dest = _target_point(o.target_id)
			SimOrder.T_ATTACK, SimOrder.T_FORCE_FIRE:
				col = COL_ATTACK
				dest = _target_point(o.target_id) if o.target_id > 0 else _order_point(o)
			SimOrder.T_ATTACK_MOVE:
				col = COL_ATTACK_MOVE
				dest = _order_point(o)
			SimOrder.T_GUARD:
				col = COL_GUARD
				dest = _target_point(o.target_id) if o.target_id > 0 else _order_point(o)
			SimOrder.T_CAPTURE, SimOrder.T_REPAIR, SimOrder.T_SALVAGE:
				col = COL_SUPPORT
				dest = _target_point(o.target_id)
			SimOrder.T_HARVEST:
				col = COL_ECON
				dest = _order_point(o)
			SimOrder.T_RETURN_CARGO, SimOrder.T_RETURN_BASE:
				col = COL_ECON
				dest = _target_point(o.target_id)
			SimOrder.T_LOAD, SimOrder.T_GARRISON:
				col = COL_TRANSPORT
				dest = _target_point(o.target_id)
			_:
				continue
		if dest == Vector2.INF:
			continue
		k += 1
		_leg(cur, dest, col)
		cur = dest


## Ground path from `a` to `b` plus a small ring at the waypoint.
func _leg(a: Vector2, b: Vector2, col: Color) -> void:
	if a.distance_to(b) < 0.3:
		return
	var pts: PackedVector3Array = PackedVector3Array()
	var step: float = STEP_FAR_M if a.distance_to(b) > LONG_LEG_M else STEP_M
	ViewRibbon.sample_segment(pts, a, b, step, _ground, LIFT_M, true)
	_ribbon.add_polyline(pts, col, ViewRibbon.STYLE_MARCH)
	count_lines += 1
	var rc: PackedVector3Array = ViewRibbon.circle_points(b.x, b.y, WP_RING_M, 14, _ground, LIFT_M)
	_ribbon.add_polyline(rc, col, ViewRibbon.STYLE_SOLID, 0.85, true)


func _rally_line(rv: ViewEntity, rx: int, ry: int, target: int) -> void:
	var a: Vector2 = Vector2(rv.wx, rv.wz)
	var b: Vector2 = ViewConsts.sim_to_world_xz(rx, ry)
	var col: Color = COL_RALLY
	if target > 0:
		var tp: Vector2 = _target_point(target)
		if tp != Vector2.INF:
			b = tp
			col = COL_RALLY_HARVEST
	if a.distance_to(b) < 0.3:
		return
	var pts: PackedVector3Array = PackedVector3Array()
	ViewRibbon.sample_segment(pts, a, b, STEP_M if a.distance_to(b) < LONG_LEG_M else STEP_FAR_M, _ground, LIFT_M, true)
	_ribbon.add_polyline(pts, col, ViewRibbon.STYLE_MARCH)
	var ping: PackedVector3Array = ViewRibbon.circle_points(b.x, b.y, END_RING_M, 20, _ground, LIFT_M)
	_ribbon.add_polyline(ping, col, ViewRibbon.STYLE_SOLID, 1.0, true)
	count_lines += 1


static func _order_point(o: SimOrder) -> Vector2:
	return ViewConsts.sim_to_world_xz(o.x, o.y)


## World XZ of a target entity that is visible to the player; INF otherwise (a hidden target never leaks its position).
func _target_point(id: int) -> Vector2:
	if id <= 0:
		return Vector2.INF
	var tv: ViewEntity = _v.entity_view(id)
	if tv == null or tv.vs == ViewConsts.VS_HIDDEN or tv.sim_gone:
		return Vector2.INF
	return Vector2(tv.wx, tv.wz)


## Test hook: the committed ribbon (vertex / triangle counts).
func ribbon() -> ViewRibbon:
	return _ribbon
