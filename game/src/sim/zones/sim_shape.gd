class_name SimShape
extends RefCounted
## Circle and capsule containment (abilities 5.11.2 / 3.6). Integer math only: the capsule test uses the cross product
## divided by the segment length (Fp.isqrt), exact to 1 unit. Coordinates are sub-cell units (max 262143), so every
## product stays far below 2^62.

const SHAPE_DISC: int = 0
const SHAPE_CAPSULE: int = 1


static func circle_contains(cx: int, cy: int, r: int, x: int, y: int) -> bool:
	var dx: int = x - cx
	var dy: int = y - cy
	return dx * dx + dy * dy <= r * r


## Distance (floor, in units) from (x, y) to the segment (x0, y0)-(x1, y1).
static func segment_distance(x0: int, y0: int, x1: int, y1: int, x: int, y: int) -> int:
	var sx: int = x1 - x0
	var sy: int = y1 - y0
	var px: int = x - x0
	var py: int = y - y0
	var len2: int = sx * sx + sy * sy
	if len2 == 0:
		return Fp.isqrt(px * px + py * py)
	var dot: int = px * sx + py * sy
	if dot <= 0:
		return Fp.isqrt(px * px + py * py)
	if dot >= len2:
		var qx: int = x - x1
		var qy: int = y - y1
		return Fp.isqrt(qx * qx + qy * qy)
	var cross: int = absi(px * sy - py * sx)
	return cross / Fp.isqrt(len2)


static func capsule_contains(x0: int, y0: int, x1: int, y1: int, half_w: int, x: int, y: int) -> bool:
	return segment_distance(x0, y0, x1, y1, x, y) <= half_w


## true when the segment from the previous point (px, py) to (x, y) enters the circle from outside: false when the
## start point is already inside, true for any contact (a grazing chord counts) otherwise.
static func segment_enters_circle(cx: int, cy: int, r: int, px: int, py: int, x: int, y: int) -> bool:
	if circle_contains(cx, cy, r, px, py):
		return false
	return segment_distance(px, py, x, y, cx, cy) <= r


## Entity ids (ascending, alive) whose centre lies inside the shape: SHAPE_DISC (centre x, y, `radius`) or
## SHAPE_CAPSULE (segment (x, y)-(x2, y2), half-width `radius`).
static func query_shape(world: SimWorld, shape: int, x: int, y: int, x2: int, y2: int, radius: int, out: PackedInt32Array) -> void:
	if shape == SHAPE_DISC:
		world.query_circle(x, y, radius, out)
		return
	var mx: int = (x + x2) / 2
	var my: int = (y + y2) / 2
	var hx: int = x2 - x
	var hy: int = y2 - y
	var half_len: int = Fp.isqrt(hx * hx + hy * hy) / 2 + 1
	var cand: PackedInt32Array = PackedInt32Array()
	world.query_circle(mx, my, half_len + radius, cand)
	out.resize(0)
	for id: int in cand:
		var e: SimEntity = world.by_id[id]
		if e != null and capsule_contains(x, y, x2, y2, radius, e.x, e.y):
			out.append(id)
