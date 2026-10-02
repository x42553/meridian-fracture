class_name UiPicking
extends RefCounted
## Pure picking maths on `UiPickData` (ui.md 3.3, 3.2.2): ray vs pick sphere and projected-centre box select, without the
## physics engine. The FIXTURE adapter's picker and the reference for `ViewPicker`'s tie rules: smallest ray parameter,
## ties (< 0.01 m) prefer non-wreck over wreck, unit over structure, then the lower id. Reference cost at 439 entities:
## ray ~127 us, box ~92 us (spike).

const TIE_M: float = 0.01


## Entity id under `screen` or -1 (`filter` = UiViewPort.PICK_*). The camera must be inside a scene tree.
static func ray_pick(camera: Camera3D, pd: UiPickData, screen: Vector2, filter: int = 0xFF) -> int:
	return pick_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen), pd, filter)


## The ray test without a camera (origin + unit direction): what the tests drive with synthetic rays.
static func pick_ray(o: Vector3, d: Vector3, pd: UiPickData, filter: int = 0xFF) -> int:
	var best: int = -1
	var best_t: float = INF
	var best_fl: int = 0
	var best_id: int = 0
	for i: int in pd.count:
		var c: Vector3 = pd.center[i]
		var r: float = pd.radius[i]
		var ocx: float = o.x - c.x
		var ocy: float = o.y - c.y
		var ocz: float = o.z - c.z
		var b: float = ocx * d.x + ocy * d.y + ocz * d.z
		var disc: float = b * b - (ocx * ocx + ocy * ocy + ocz * ocz - r * r)
		if disc < 0.0:
			continue
		var t: float = -b - sqrt(disc)
		if t <= 0.0:
			t = -b + sqrt(disc)  # origin inside the sphere
			if t <= 0.0:
				continue
		if best >= 0 and t > best_t + TIE_M:
			continue
		if not pd.allows(i, filter):
			continue
		if best >= 0 and t >= best_t - TIE_M and not _wins_tie(pd.flags[i], pd.ids[i], best_fl, best_id):
			continue  # inside the tie band the tie rules decide
		best = i
		best_t = t
		best_fl = pd.flags[i]
		best_id = pd.ids[i]
	return best_id if best >= 0 else -1


## Tie rule between a candidate and the current best: non-wreck over wreck, unit over structure, lower id.
static func _wins_tie(fl: int, id: int, best_fl: int, best_id: int) -> bool:
	var w: bool = (fl & UiPickData.F_WRECK) != 0
	var bw: bool = (best_fl & UiPickData.F_WRECK) != 0
	if w != bw:
		return not w
	var s: bool = (fl & UiPickData.F_STRUCTURE) != 0
	var bs: bool = (best_fl & UiPickData.F_STRUCTURE) != 0
	if s != bs:
		return not s
	return id < best_id


## Ids whose pick-sphere centre projects into `rect` (viewport px) and lies in front of the camera, ascending.
static func box_select(camera: Camera3D, pd: UiPickData, rect: Rect2, filter: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var r: Rect2 = rect.abs()
	for i: int in pd.count:
		var c: Vector3 = pd.center[i]
		if camera.is_position_behind(c) or not pd.allows(i, filter):
			continue
		if r.has_point(camera.unproject_position(c)):
			out.append(pd.ids[i])
	out.sort()
	return out
