class_name ViewPicker
extends RefCounted
## Screen position / rectangle -> entity id without a physics engine (render spec 5.11): the ray hits the heightfield, the sim's
## spatial hash and structure occupancy grid supply candidates around the hit, aircraft are always candidates, and every candidate
## is tested against its oriented pick box. Presentation only.

const PICK_UNITS: int = 1
const PICK_STRUCTURES: int = 2
const PICK_WRECKS: int = 4
const PICK_OWN: int = 8
const PICK_ENEMY: int = 16
const PICK_NEUTRAL: int = 32
const PICK_AIR: int = 64
const PICK_GHOSTS: int = 128  ## remembered structures: needs ViewGhosts (VIEW-W2), ignored for now
const PICK_ANY: int = 0xFF

const QUERY_RADIUS_UNITS: int = 4608  ## 4.5 cells
const AIR_MIN_HALF_M: float = 1.2
const AIR_SCREEN_PX: float = 22.0
const TIE_M: float = 0.01
const DDA_MAX_CELLS: int = 12

var _v: ViewWorld = null
var _cand: PackedInt32Array = PackedInt32Array()


func setup(v: ViewWorld) -> void:
	_v = v
	_cand.resize(256)


## Entity id under the cursor or -1. Ties: non-wreck over wreck, unit over structure, lower id.
func pick(screen_pos: Vector2, filter: int) -> int:
	var cam: ViewCamera = _v.camera
	if cam == null or _v.sim == null:
		return -1
	var ray: Array[Vector3] = cam.screen_ray(screen_pos)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var g: Vector3 = _v.terrain.raycast(o, d) if _v.terrain != null else _plane(o, d)
	var seen: Dictionary = {}
	var best: ViewEntity = null
	var best_t: float = INF
	if g != Vector3.INF:
		var su: Vector2i = ViewConsts.world_to_sim_xz(Vector2(g.x, g.z))
		var n: int = _v.sim.query_circle(su.x, su.y, QUERY_RADIUS_UNITS, _cand, SimTag.ALIVE, 0)
		for i: int in n:
			var t: float = _test(_cand[i], o, d, filter, seen)
			if t >= 0.0 and _better(_cand[i], t, best, best_t):
				best = _v.entity_view(_cand[i])
				best_t = t
		# structures: walk the occupancy grid from the ground hit back toward the camera's ground foot
		var foot: Vector2 = Vector2(o.x, o.z)
		var dir: Vector2 = foot - Vector2(g.x, g.z)
		var dist: float = dir.length()
		var steps: int = mini(DDA_MAX_CELLS, int(ceil(minf(dist, 30.0) / ViewConsts.CELL_M)) + 1)
		if dist > 0.001:
			dir /= dist
		var last_cell: int = -1
		for s: int in steps:
			var p: Vector2 = Vector2(g.x, g.z) + dir * (float(s) * ViewConsts.CELL_M * 0.9)
			var cx: int = int(floor(p.x / ViewConsts.CELL_M))
			var cy: int = int(floor(p.y / ViewConsts.CELL_M))
			var key: int = cy * 4096 + cx
			if key == last_cell:
				continue
			last_cell = key
			var sid: int = _v.sim.struct_at(cx, cy)
			if sid > 0:
				var t2: float = _test(sid, o, d, filter, seen)
				if t2 >= 0.0 and _better(sid, t2, best, best_t):
					best = _v.entity_view(sid)
					best_t = t2
	if (filter & PICK_AIR) != 0:
		for ve: ViewEntity in _v.air_list():
			var t3: float = _test_air(ve, o, d, filter, screen_pos, seen)
			if t3 >= 0.0 and _better(ve.id, t3, best, best_t):
				best = ve
				best_t = t3
	return best.id if best != null else -1


func _plane(o: Vector3, d: Vector3) -> Vector3:
	if d.y >= -0.0001:
		return Vector3.INF
	return o + d * (-o.y / d.y)


func _better(id: int, t: float, best: ViewEntity, best_t: float) -> bool:
	if best == null:
		return true
	if t < best_t - TIE_M:
		return true
	if t > best_t + TIE_M:
		return false
	var c: ViewEntity = _v.entity_view(id)
	var cw: bool = c.kind == SimEntity.Kind.WRECK
	var bw: bool = best.kind == SimEntity.Kind.WRECK
	if cw != bw:
		return not cw
	var cs: bool = c.kind == SimEntity.Kind.STRUCTURE or c.kind == SimEntity.Kind.NEUTRAL
	var bs: bool = best.kind == SimEntity.Kind.STRUCTURE or best.kind == SimEntity.Kind.NEUTRAL
	if cs != bs:
		return not cs
	return id < best.id


## Ray parameter of the hit or -1 (filtered, hidden, duplicate or missed).
func _test(id: int, o: Vector3, d: Vector3, filter: int, seen: Dictionary) -> float:
	if seen.has(id):
		return -1.0
	var ve: ViewEntity = _v.entity_view(id)
	if ve == null:
		return -1.0
	if ve.motion >= ViewConsts.MOTION_AIR_FIXED and ve.motion <= ViewConsts.MOTION_AIR_HOVER:
		return -1.0  # aircraft only through the air path
	seen[id] = true
	if not _allowed(ve, filter):
		return -1.0
	return ray_vs_obb(o, d, ve.pick_centre(), ve.pick_half, ve.yaw)


func _test_air(ve: ViewEntity, o: Vector3, d: Vector3, filter: int, screen: Vector2, seen: Dictionary) -> float:
	if seen.has(ve.id) or not _allowed(ve, filter):
		return -1.0
	seen[ve.id] = true
	var half: Vector3 = Vector3(maxf(ve.pick_half.x, AIR_MIN_HALF_M), maxf(ve.pick_half.y, AIR_MIN_HALF_M), maxf(ve.pick_half.z, AIR_MIN_HALF_M))
	var t: float = ray_vs_obb(o, d, ve.pick_centre(), half, ve.yaw)
	if t >= 0.0:
		return t
	var sp: Vector2 = _v.camera.world_to_screen(ve.pick_centre())
	if sp.distance_to(screen) < AIR_SCREEN_PX:
		return (ve.pick_centre() - o).length()
	return -1.0


func _allowed(ve: ViewEntity, filter: int) -> bool:
	if ve.vs == ViewConsts.VS_HIDDEN or ve.vs == ViewConsts.VS_DYING or ve.dead or ve.sim_gone:
		return false
	if (ve.sim_flags & SimFlags.F_INSIDE) != 0:
		return false
	var km: int = filter & (PICK_UNITS | PICK_STRUCTURES | PICK_WRECKS)
	if km != 0:
		var bit: int = PICK_UNITS
		if ve.kind == SimEntity.Kind.STRUCTURE or ve.kind == SimEntity.Kind.NEUTRAL:
			bit = PICK_STRUCTURES
		elif ve.kind == SimEntity.Kind.WRECK:
			bit = PICK_WRECKS
		if (km & bit) == 0:
			return false
	var rm: int = filter & (PICK_OWN | PICK_ENEMY | PICK_NEUTRAL)
	if rm != 0:
		var rbit: int = PICK_NEUTRAL
		if ve.owner >= 0:
			rbit = PICK_OWN if (ve.owner == _v.local_pid or _v.sim.are_allied(_v.local_pid, ve.owner)) else PICK_ENEMY
		if (rm & rbit) == 0:
			return false
	var is_air: bool = ve.motion >= ViewConsts.MOTION_AIR_FIXED and ve.motion <= ViewConsts.MOTION_AIR_HOVER
	if is_air and (filter & PICK_AIR) == 0:
		return false
	return true


## Slab test in entity space (box centred at `centre`, half extents `half`, yawed about Y). Returns t >= 0 or -1.
static func ray_vs_obb(o: Vector3, d: Vector3, centre: Vector3, half: Vector3, yaw: float) -> float:
	var inv: Basis = Basis(Vector3.UP, -yaw)
	var lo: Vector3 = inv * (o - centre)
	var ld: Vector3 = inv * d
	var tmin: float = 0.0
	var tmax: float = INF
	for axis: int in 3:
		var oa: float = lo[axis]
		var da: float = ld[axis]
		var h: float = half[axis]
		if absf(da) < 1.0e-8:
			if oa < -h or oa > h:
				return -1.0
		else:
			var t1: float = (-h - oa) / da
			var t2: float = (h - oa) / da
			if t1 > t2:
				var tmp: float = t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


## Fills `out` (cleared) with the ids whose pick centre projects into `rect`, ascending; returns the count.
func pick_box(rect: Rect2, filter: int, out: PackedInt32Array) -> int:
	out.clear()
	var cam: ViewCamera = _v.camera
	if cam == null:
		return 0
	var r: Rect2 = rect.abs()
	for ve: ViewEntity in _v.entities():
		if not _allowed(ve, filter):
			continue
		var structural: bool = ve.kind == SimEntity.Kind.STRUCTURE or ve.kind == SimEntity.Kind.NEUTRAL
		var p: Vector3 = ve.pick_centre() if structural else Vector3(ve.wx, ve.wy + ve.height_m * 0.5, ve.wz)
		var sp: Vector2 = cam.world_to_screen(p)
		if r.has_point(sp):
			out.append(ve.id)
	out.sort()
	return out.size()
