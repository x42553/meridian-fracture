class_name UiDraw
extends RefCounted
## Stateless geometry helpers shared by styleboxes and widgets. Pure functions, no engine state.

## Outline of `r` with chamfered (cut) corners, clockwise from the top-left corner.
## `cuts` = Vector4(top_left, top_right, bottom_right, bottom_left) in px, 0 = square corner.
static func chamfer_points(r: Rect2, cuts: Vector4) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x0: float = r.position.x
	var y0: float = r.position.y
	var x1: float = r.end.x
	var y1: float = r.end.y
	if cuts.x > 0.0:
		pts.append(Vector2(x0, y0 + cuts.x))
		pts.append(Vector2(x0 + cuts.x, y0))
	else:
		pts.append(Vector2(x0, y0))
	if cuts.y > 0.0:
		pts.append(Vector2(x1 - cuts.y, y0))
		pts.append(Vector2(x1, y0 + cuts.y))
	else:
		pts.append(Vector2(x1, y0))
	if cuts.z > 0.0:
		pts.append(Vector2(x1, y1 - cuts.z))
		pts.append(Vector2(x1 - cuts.z, y1))
	else:
		pts.append(Vector2(x1, y1))
	if cuts.w > 0.0:
		pts.append(Vector2(x0 + cuts.w, y1))
		pts.append(Vector2(x0, y1 - cuts.w))
	else:
		pts.append(Vector2(x0, y1))
	return pts

## Point where a ray from the centre of `r`, at clockwise angle `ang` (radians, 0 = up), leaves `r`.
static func rect_boundary(r: Rect2, ang: float) -> Vector2:
	var c: Vector2 = r.get_center()
	var d := Vector2(sin(ang), -cos(ang))
	var sx: float = INF if absf(d.x) < 0.00001 else r.size.x * 0.5 / absf(d.x)
	var sy: float = INF if absf(d.y) < 0.00001 else r.size.y * 0.5 / absf(d.y)
	return c + d * minf(sx, sy)

## Polygon of the part of `r` swept by a clockwise radial wipe between fractions t0..t1 (0 = 12 o'clock).
## This is the classic RTS "clock wipe" over a rectangular build icon. Star-shaped around the centre,
## so it can be drawn with draw_colored_polygon without pre-triangulation.
static func rect_sector(r: Rect2, t0: float, t1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if t1 <= t0:
		return pts
	var hw: float = r.size.x * 0.5
	var hh: float = r.size.y * 0.5
	var a_tr: float = atan2(hw, hh)
	var a0: float = t0 * TAU
	var a1: float = t1 * TAU
	pts.append(r.get_center())
	pts.append(rect_boundary(r, a0))
	if a_tr > a0 and a_tr < a1:
		pts.append(Vector2(r.end.x, r.position.y))
	if PI - a_tr > a0 and PI - a_tr < a1:
		pts.append(r.end)
	if PI + a_tr > a0 and PI + a_tr < a1:
		pts.append(Vector2(r.position.x, r.end.y))
	if TAU - a_tr > a0 and TAU - a_tr < a1:
		pts.append(r.position)
	pts.append(rect_boundary(r, a1))
	return pts

## Points of an arc, usable for polylines/polygons (draw_arc draws only lines).
static func arc_points(center: Vector2, radius: float, a0: float, a1: float, count: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(count + 1)
	for i in count + 1:
		var a: float = lerpf(a0, a1, float(i) / float(count))
		pts[i] = center + Vector2(cos(a), sin(a)) * radius
	return pts

## Snap to the device pixel grid so 1 px lines stay crisp (call with the value in *logical* px).
static func snap(v: float) -> float:
	return floorf(v) + 0.5
