class_name UiEmblem
extends RefCounted
## Procedural faction emblems (placeholder heraldry) drawn with primitives in a unit square.

static func draw(ci: CanvasItem, code: String, rect: Rect2, col: Color, w: float = 2.0) -> void:
	var s: float = minf(rect.size.x, rect.size.y)
	var o: Vector2 = rect.get_center() - Vector2(s, s) * 0.5
	var c: Vector2 = o + Vector2(s, s) * 0.5
	var dim: Color = Color(col, 0.35)
	match code:
		"napc":
			_poly(ci, o, s, [0.5, 0.04, 0.92, 0.2, 0.86, 0.66, 0.5, 0.96, 0.14, 0.66, 0.08, 0.2], col, w)
			_star(ci, c, s * 0.26, s * 0.11, 5, col)
		"nec":
			for i in 12:
				var a: float = float(i) / 12.0 * TAU
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * s * 0.40, s * 0.045, col)
			ci.draw_arc(c, s * 0.27, 0.0, TAU, 32, dim, w, true)
			_fillp(ci, o, s, [0.5, 0.28, 0.66, 0.5, 0.5, 0.72, 0.34, 0.5], col)
		"olm":
			ci.draw_arc(c, s * 0.36, deg_to_rad(50.0), deg_to_rad(310.0), 32, col, w * 2.2, true)
			ci.draw_circle(c + Vector2(s * 0.16, 0.0), s * 0.13, col)
			for i in 8:
				var a2: float = float(i) / 8.0 * TAU
				ci.draw_line(c + Vector2(cos(a2), sin(a2)) * s * 0.44, c + Vector2(cos(a2), sin(a2)) * s * 0.5, dim, w, true)
		"def":
			_poly(ci, o, s, [0.5, 0.04, 0.94, 0.28, 0.94, 0.72, 0.5, 0.96, 0.06, 0.72, 0.06, 0.28], col, w)
			_poly(ci, o, s, [0.24, 0.62, 0.5, 0.36, 0.76, 0.62], col, w * 1.4, false)
			_poly(ci, o, s, [0.24, 0.78, 0.5, 0.52, 0.76, 0.78], dim, w * 1.4, false)
		"pd":
			ci.draw_arc(c, s * 0.42, 0.0, TAU, 40, col, w, true)
			for k in 3:
				var y: float = 0.38 + float(k) * 0.12
				_poly(ci, o, s, [0.2, y, 0.35, y - 0.06, 0.5, y, 0.65, y + 0.06, 0.8, y], col, w, false)
		"han":
			_fillp(ci, o, s, [0.5, 0.04, 0.96, 0.5, 0.5, 0.96, 0.04, 0.5], dim)
			_poly(ci, o, s, [0.5, 0.04, 0.96, 0.5, 0.5, 0.96, 0.04, 0.5], col, w)
			_poly(ci, o, s, [0.5, 0.24, 0.76, 0.5, 0.5, 0.76, 0.24, 0.5], col, w)
			ci.draw_circle(c, s * 0.07, col)
		"ae":
			ci.draw_circle(c, s * 0.16, col)
			for i in 10:
				var a3: float = float(i) / 10.0 * TAU
				var d := Vector2(cos(a3), sin(a3))
				var n := Vector2(-d.y, d.x)
				ci.draw_colored_polygon(PackedVector2Array([c + d * s * 0.26 + n * s * 0.05, c + d * s * 0.48, c + d * s * 0.26 - n * s * 0.05]), col)
		"sap":
			ci.draw_arc(c, s * 0.43, 0.0, TAU, 40, dim, w, true)
			for i in 3:
				var a4: float = deg_to_rad(-90.0 + (float(i) - 1.0) * 46.0)
				var d2 := Vector2(cos(a4), sin(a4))
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, s * 0.30), c + d2 * s * 0.42 + Vector2(-s * 0.10, 0.0), c + d2 * s * 0.42 + Vector2(s * 0.10, 0.0)]), col)
		_:
			ci.draw_circle(c, s * 0.4, col)

static func _pts(o: Vector2, s: float, flat: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		p.append(o + Vector2(float(flat[i]), float(flat[i + 1])) * s)
	return p

static func _poly(ci: CanvasItem, o: Vector2, s: float, flat: Array, col: Color, w: float, closed: bool = true) -> void:
	var p: PackedVector2Array = _pts(o, s, flat)
	if closed:
		p.append(p[0])
	ci.draw_polyline(p, col, w, true)

static func _fillp(ci: CanvasItem, o: Vector2, s: float, flat: Array, col: Color) -> void:
	ci.draw_colored_polygon(_pts(o, s, flat), col)

static func _star(ci: CanvasItem, c: Vector2, r_out: float, r_in: float, n: int, col: Color) -> void:
	var p := PackedVector2Array()
	for i in n * 2:
		var a: float = -PI * 0.5 + float(i) / float(n * 2) * TAU
		var r: float = r_out if i % 2 == 0 else r_in
		p.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(p, col)
