class_name UiGlyphs
extends RefCounted
## Vector icon set drawn with CanvasItem primitives (zero external art, crisp at any scale).
## Every glyph lives in a unit square centred in `rect`. Call only from a CanvasItem's _draw().

enum Glyph {
	STRUCTURES, INFANTRY, VEHICLES, AIRCRAFT, NAVAL, DEFENSE, POWERS,
	ATTACK_MOVE, GUARD, STOP, SCATTER, DEPLOY, SELL, REPAIR, WAYPOINT,
	CREDIT, BOLT, WARNING, CHEVRON_UP, CHEVRON_DOWN, CLOSE, CHECK, LOCK, CLOCK, GEAR, PLUS, MINUS, RADAR, MISSILE,
}

static func draw(ci: CanvasItem, glyph: Glyph, rect: Rect2, col: Color, w: float = 1.8) -> void:
	var s: float = minf(rect.size.x, rect.size.y)
	var o: Vector2 = rect.get_center() - Vector2(s, s) * 0.5
	var dk: Color = col.darkened(0.55)
	match glyph:
		Glyph.STRUCTURES:
			_fill(ci, o, s, [0.06, 0.92, 0.06, 0.50, 0.30, 0.34, 0.30, 0.50, 0.56, 0.34, 0.56, 0.50, 0.82, 0.16, 0.94, 0.16, 0.94, 0.92], col)
			_fill(ci, o, s, [0.20, 0.92, 0.20, 0.66, 0.42, 0.66, 0.42, 0.92], dk)
		Glyph.INFANTRY:
			_circle(ci, o, s, 0.46, 0.20, 0.13, col, -1.0)
			_fill(ci, o, s, [0.22, 0.94, 0.24, 0.50, 0.36, 0.36, 0.56, 0.36, 0.68, 0.50, 0.72, 0.94, 0.56, 0.94, 0.48, 0.70, 0.40, 0.94], col)
			_line(ci, o, s, 0.62, 0.52, 0.94, 0.30, col, w + 0.6)
		Glyph.VEHICLES:
			_fill(ci, o, s, [0.06, 0.66, 0.10, 0.90, 0.90, 0.90, 0.94, 0.66], col)
			_fill(ci, o, s, [0.16, 0.62, 0.22, 0.44, 0.74, 0.44, 0.84, 0.62], col)
			_fill(ci, o, s, [0.32, 0.44, 0.38, 0.26, 0.62, 0.26, 0.68, 0.44], col)
			_line(ci, o, s, 0.62, 0.34, 0.98, 0.34, col, w + 1.2)
			_line(ci, o, s, 0.16, 0.78, 0.86, 0.78, dk, 1.2)
		Glyph.AIRCRAFT:
			_fill(ci, o, s, [0.50, 0.04, 0.58, 0.30, 0.96, 0.62, 0.96, 0.74, 0.58, 0.62, 0.56, 0.84, 0.70, 0.92, 0.70, 0.98, 0.30, 0.98, 0.30, 0.92, 0.44, 0.84, 0.42, 0.62, 0.04, 0.74, 0.04, 0.62, 0.42, 0.30], col)
		Glyph.NAVAL:
			_fill(ci, o, s, [0.04, 0.58, 0.96, 0.58, 0.82, 0.82, 0.18, 0.82], col)
			_fill(ci, o, s, [0.28, 0.58, 0.34, 0.38, 0.66, 0.38, 0.72, 0.58], col)
			_line(ci, o, s, 0.50, 0.38, 0.50, 0.10, col, w)
			_line(ci, o, s, 0.66, 0.46, 0.94, 0.42, col, w + 0.8)
			_poly(ci, o, s, [0.04, 0.92, 0.20, 0.87, 0.36, 0.92, 0.52, 0.87, 0.68, 0.92, 0.84, 0.87, 0.96, 0.92], dk, w, false)
		Glyph.DEFENSE:
			_fill(ci, o, s, [0.50, 0.04, 0.92, 0.18, 0.92, 0.52, 0.50, 0.96, 0.08, 0.52, 0.08, 0.18], col)
			_fill(ci, o, s, [0.50, 0.20, 0.76, 0.28, 0.76, 0.50, 0.50, 0.78, 0.24, 0.50, 0.24, 0.28], dk)
		Glyph.POWERS:
			_fill(ci, o, s, [0.50, 0.02, 0.60, 0.36, 0.98, 0.36, 0.67, 0.58, 0.79, 0.96, 0.50, 0.72, 0.21, 0.96, 0.33, 0.58, 0.02, 0.36, 0.40, 0.36], col)
		Glyph.ATTACK_MOVE:
			_circle(ci, o, s, 0.5, 0.5, 0.30, col, w)
			_circle(ci, o, s, 0.5, 0.5, 0.05, col, -1.0)
			_line(ci, o, s, 0.5, 0.06, 0.5, 0.32, col, w)
			_line(ci, o, s, 0.5, 0.68, 0.5, 0.94, col, w)
			_line(ci, o, s, 0.06, 0.5, 0.32, 0.5, col, w)
			_line(ci, o, s, 0.68, 0.5, 0.94, 0.5, col, w)
		Glyph.GUARD:
			_poly(ci, o, s, [0.50, 0.06, 0.90, 0.20, 0.90, 0.52, 0.50, 0.94, 0.10, 0.52, 0.10, 0.20], col, w, true)
			_poly(ci, o, s, [0.30, 0.48, 0.45, 0.62, 0.70, 0.34], col, w, false)
		Glyph.STOP:
			_poly(ci, o, s, [0.32, 0.08, 0.68, 0.08, 0.92, 0.32, 0.92, 0.68, 0.68, 0.92, 0.32, 0.92, 0.08, 0.68, 0.08, 0.32], col, w, true)
			_fill(ci, o, s, [0.34, 0.34, 0.66, 0.34, 0.66, 0.66, 0.34, 0.66], col)
		Glyph.SCATTER:
			for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var a: Vector2 = Vector2(0.5, 0.5) + d * 0.12
				var b: Vector2 = Vector2(0.5, 0.5) + d * 0.40
				_line(ci, o, s, a.x, a.y, b.x, b.y, col, w)
				_fill(ci, o, s, [b.x + d.x * 0.08, b.y + d.y * 0.08, b.x - d.x * 0.20, b.y + d.y * 0.02, b.x + d.x * 0.02, b.y - d.y * 0.20], col)
		Glyph.DEPLOY:
			_poly(ci, o, s, [0.08, 0.34, 0.08, 0.08, 0.34, 0.08], col, w, false)
			_poly(ci, o, s, [0.66, 0.08, 0.92, 0.08, 0.92, 0.34], col, w, false)
			_poly(ci, o, s, [0.92, 0.66, 0.92, 0.92, 0.66, 0.92], col, w, false)
			_poly(ci, o, s, [0.34, 0.92, 0.08, 0.92, 0.08, 0.66], col, w, false)
			_fill(ci, o, s, [0.5, 0.28, 0.72, 0.5, 0.5, 0.72, 0.28, 0.5], col)
		Glyph.SELL:
			_circle(ci, o, s, 0.5, 0.5, 0.42, col, w)
			ci.draw_string(UiFonts.get_font(UiFonts.Role.HEAD), o + Vector2(0.0, s * 0.72), "$", HORIZONTAL_ALIGNMENT_CENTER, s, int(s * 0.62), col)
		Glyph.REPAIR:
			_line(ci, o, s, 0.14, 0.88, 0.56, 0.46, col, w + 2.2)
			ci.draw_arc(o + Vector2(0.68, 0.32) * s, 0.22 * s, deg_to_rad(140.0), deg_to_rad(420.0), 20, col, w + 1.4, true)
		Glyph.WAYPOINT:
			_line(ci, o, s, 0.24, 0.94, 0.24, 0.06, col, w)
			_fill(ci, o, s, [0.24, 0.08, 0.90, 0.26, 0.24, 0.48], col)
		Glyph.CREDIT:
			_fill(ci, o, s, [0.5, 0.06, 0.92, 0.5, 0.5, 0.94, 0.08, 0.5], col)
			_fill(ci, o, s, [0.5, 0.26, 0.72, 0.5, 0.5, 0.74, 0.28, 0.5], dk)
		Glyph.BOLT:
			_fill(ci, o, s, [0.60, 0.02, 0.18, 0.56, 0.46, 0.56, 0.36, 0.98, 0.82, 0.38, 0.54, 0.38, 0.70, 0.02], col)
		Glyph.WARNING:
			_fill(ci, o, s, [0.5, 0.06, 0.96, 0.90, 0.04, 0.90], col)
			_line(ci, o, s, 0.5, 0.36, 0.5, 0.62, dk, w + 0.6)
			_circle(ci, o, s, 0.5, 0.76, 0.04, dk, -1.0)
		Glyph.CHEVRON_UP:
			_poly(ci, o, s, [0.16, 0.66, 0.5, 0.32, 0.84, 0.66], col, w + 0.4, false)
		Glyph.CHEVRON_DOWN:
			_poly(ci, o, s, [0.16, 0.34, 0.5, 0.68, 0.84, 0.34], col, w + 0.4, false)
		Glyph.CLOSE:
			_line(ci, o, s, 0.2, 0.2, 0.8, 0.8, col, w + 0.4)
			_line(ci, o, s, 0.8, 0.2, 0.2, 0.8, col, w + 0.4)
		Glyph.CHECK:
			_poly(ci, o, s, [0.14, 0.52, 0.40, 0.76, 0.86, 0.24], col, w + 0.6, false)
		Glyph.LOCK:
			_fill(ci, o, s, [0.18, 0.46, 0.82, 0.46, 0.82, 0.92, 0.18, 0.92], col)
			ci.draw_arc(o + Vector2(0.5, 0.42) * s, 0.20 * s, PI, TAU, 14, col, w + 0.6, true)
		Glyph.CLOCK:
			_circle(ci, o, s, 0.5, 0.5, 0.42, col, w)
			_poly(ci, o, s, [0.5, 0.22, 0.5, 0.5, 0.70, 0.62], col, w, false)
		Glyph.GEAR:
			_circle(ci, o, s, 0.5, 0.5, 0.26, col, w + 0.6)
			for i in 8:
				var a: float = float(i) / 8.0 * TAU
				var d := Vector2(cos(a), sin(a))
				_line(ci, o, s, 0.5 + d.x * 0.30, 0.5 + d.y * 0.30, 0.5 + d.x * 0.44, 0.5 + d.y * 0.44, col, w + 1.2)
		Glyph.PLUS:
			_line(ci, o, s, 0.5, 0.15, 0.5, 0.85, col, w + 0.6)
			_line(ci, o, s, 0.15, 0.5, 0.85, 0.5, col, w + 0.6)
		Glyph.MINUS:
			_line(ci, o, s, 0.15, 0.5, 0.85, 0.5, col, w + 0.6)
		Glyph.RADAR:
			_circle(ci, o, s, 0.5, 0.5, 0.42, col, w)
			_circle(ci, o, s, 0.5, 0.5, 0.20, col, w)
			_line(ci, o, s, 0.5, 0.5, 0.82, 0.24, col, w)
			_circle(ci, o, s, 0.66, 0.66, 0.05, col, -1.0)
		Glyph.MISSILE:
			_fill(ci, o, s, [0.5, 0.02, 0.62, 0.16, 0.62, 0.66, 0.38, 0.66, 0.38, 0.16], col)
			_fill(ci, o, s, [0.38, 0.52, 0.16, 0.80, 0.38, 0.72], col)
			_fill(ci, o, s, [0.62, 0.52, 0.84, 0.80, 0.62, 0.72], col)
			_fill(ci, o, s, [0.42, 0.70, 0.58, 0.70, 0.5, 0.98], UiPalette.WARN)

static func _pts(o: Vector2, s: float, flat: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		p.append(o + Vector2(float(flat[i]), float(flat[i + 1])) * s)
	return p

static func _fill(ci: CanvasItem, o: Vector2, s: float, flat: Array, col: Color) -> void:
	ci.draw_colored_polygon(_pts(o, s, flat), col)

static func _poly(ci: CanvasItem, o: Vector2, s: float, flat: Array, col: Color, w: float, closed: bool) -> void:
	var p: PackedVector2Array = _pts(o, s, flat)
	if closed:
		p.append(p[0])
	ci.draw_polyline(p, col, w, true)

static func _line(ci: CanvasItem, o: Vector2, s: float, x0: float, y0: float, x1: float, y1: float, col: Color, w: float) -> void:
	ci.draw_line(o + Vector2(x0, y0) * s, o + Vector2(x1, y1) * s, col, w, true)

static func _circle(ci: CanvasItem, o: Vector2, s: float, cx: float, cy: float, r: float, col: Color, w: float) -> void:
	ci.draw_circle(o + Vector2(cx, cy) * s, r * s, col, w < 0.0, w if w >= 0.0 else -1.0, true)
