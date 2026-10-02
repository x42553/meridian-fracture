class_name UiGlyphs
extends RefCounted
## Vector glyph library on a unit square (ui.md 3.5, art_direction 5.12.6), drawn with CanvasItem primitives: zero
## external art, crisp at any scale. Ids are the `Glyph` integers of the spec (0-28 spike set, 29-44 art's role
## glyphs, 45-54 UI additions, 55+ extras of the HUD task). UI-01b may replace this file: keep the ids.
## `UiDraw.glyph` finds this class through the global class list.

enum Glyph {
	STRUCTURES = 0, INFANTRY = 1, VEHICLES = 2, AIRCRAFT = 3, NAVAL = 4, DEFENSE = 5, POWERS = 6, ATTACK_MOVE = 7,
	GUARD = 8, STOP = 9, SCATTER = 10, DEPLOY = 11, SELL = 12, REPAIR = 13, WAYPOINT = 14, CREDIT = 15, BOLT = 16,
	WARNING = 17, CHEVRON_UP = 18, CHEVRON_DOWN = 19, CLOSE = 20, CHECK = 21, LOCK = 22, CLOCK = 23, GEAR = 24,
	PLUS = 25, MINUS = 26, RADAR = 27, MISSILE = 28, TANK = 29, ARTILLERY = 30, ANTI_AIR = 31, SCOUT = 32,
	TRANSPORT = 33, ENGINEER = 34, COLLECTOR = 35, MCV = 36, DRONE = 37, SUBMARINE = 38, CARRIER = 39, SIEGE = 40,
	COMMAND = 41, CAMO = 42, EMP_OFF = 43, NO_POWER = 44, FOLLOW = 45, HOLD = 46, PATROL = 47, RETURN = 48,
	UNLOAD = 49, STANCE = 50, RALLY = 51, PING = 52, SPEED = 53, MUTE = 54, ROTATE_L = 55, ROTATE_R = 56, HOME = 57,
	PAUSE = 58, MODE = 59, COVER = 60, SMOKE = 61,
}
const COUNT: int = 62


## Draws glyph `glyph` inside the square fitted to the centre of `rect`. Call only from a CanvasItem's _draw().
static func draw(ci: CanvasItem, glyph: int, rect: Rect2, col: Color, w: float = 1.8) -> void:
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
			for d: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
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
			for i: int in 8:
				var a2: float = float(i) / 8.0 * TAU
				var d2 := Vector2(cos(a2), sin(a2))
				_line(ci, o, s, 0.5 + d2.x * 0.30, 0.5 + d2.y * 0.30, 0.5 + d2.x * 0.44, 0.5 + d2.y * 0.44, col, w + 1.2)
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
		Glyph.TANK:
			_fill(ci, o, s, [0.08, 0.62, 0.92, 0.62, 0.86, 0.84, 0.14, 0.84], col)
			_fill(ci, o, s, [0.26, 0.60, 0.32, 0.36, 0.68, 0.36, 0.74, 0.60], col)
			_line(ci, o, s, 0.60, 0.46, 0.98, 0.42, col, w + 1.4)
		Glyph.ARTILLERY:
			_fill(ci, o, s, [0.08, 0.70, 0.66, 0.70, 0.66, 0.86, 0.08, 0.86], col)
			_line(ci, o, s, 0.34, 0.66, 0.84, 0.18, col, w + 2.0)
			_circle(ci, o, s, 0.30, 0.70, 0.10, dk, -1.0)
		Glyph.ANTI_AIR:
			_line(ci, o, s, 0.20, 0.90, 0.20, 0.50, col, w)
			_line(ci, o, s, 0.20, 0.50, 0.62, 0.10, col, w + 1.6)
			_line(ci, o, s, 0.34, 0.50, 0.76, 0.10, col, w + 1.6)
			_poly(ci, o, s, [0.60, 0.72, 0.80, 0.56, 0.94, 0.72], col, w, false)
		Glyph.SCOUT:
			_circle(ci, o, s, 0.5, 0.5, 0.36, col, w)
			_circle(ci, o, s, 0.5, 0.5, 0.10, col, -1.0)
			_line(ci, o, s, 0.5, 0.04, 0.5, 0.20, col, w)
			_line(ci, o, s, 0.5, 0.80, 0.5, 0.96, col, w)
		Glyph.TRANSPORT:
			_fill(ci, o, s, [0.06, 0.34, 0.66, 0.34, 0.66, 0.78, 0.06, 0.78], col)
			_fill(ci, o, s, [0.70, 0.46, 0.86, 0.46, 0.96, 0.60, 0.96, 0.78, 0.70, 0.78], col)
			_circle(ci, o, s, 0.24, 0.82, 0.08, dk, -1.0)
			_circle(ci, o, s, 0.80, 0.82, 0.08, dk, -1.0)
		Glyph.ENGINEER:
			_circle(ci, o, s, 0.5, 0.5, 0.30, col, w + 1.2)
			for i2: int in 6:
				var a3: float = float(i2) / 6.0 * TAU
				_line(ci, o, s, 0.5 + cos(a3) * 0.30, 0.5 + sin(a3) * 0.30, 0.5 + cos(a3) * 0.44, 0.5 + sin(a3) * 0.44, col, w + 1.6)
			_circle(ci, o, s, 0.5, 0.5, 0.08, col, -1.0)
		Glyph.COLLECTOR:
			_fill(ci, o, s, [0.06, 0.50, 0.70, 0.50, 0.62, 0.84, 0.14, 0.84], col)
			_fill(ci, o, s, [0.70, 0.30, 0.94, 0.86, 0.72, 0.86], col)
			_circle(ci, o, s, 0.28, 0.88, 0.07, dk, -1.0)
			_circle(ci, o, s, 0.60, 0.88, 0.07, dk, -1.0)
		Glyph.MCV:
			_fill(ci, o, s, [0.06, 0.60, 0.94, 0.60, 0.94, 0.84, 0.06, 0.84], col)
			_poly(ci, o, s, [0.22, 0.56, 0.22, 0.28, 0.50, 0.12, 0.78, 0.28, 0.78, 0.56], col, w, false)
			_fill(ci, o, s, [0.42, 0.56, 0.42, 0.36, 0.58, 0.36, 0.58, 0.56], dk)
		Glyph.DRONE:
			_circle(ci, o, s, 0.5, 0.5, 0.12, col, -1.0)
			for dd: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				_line(ci, o, s, 0.5, 0.5, 0.5 + dd.x * 0.32, 0.5 + dd.y * 0.32, col, w)
				_circle(ci, o, s, 0.5 + dd.x * 0.34, 0.5 + dd.y * 0.34, 0.11, col, w * 0.8)
		Glyph.SUBMARINE:
			_fill(ci, o, s, [0.06, 0.60, 0.20, 0.44, 0.82, 0.44, 0.96, 0.60, 0.82, 0.76, 0.20, 0.76], col)
			_line(ci, o, s, 0.46, 0.44, 0.46, 0.24, col, w + 1.0)
			_line(ci, o, s, 0.46, 0.24, 0.62, 0.24, col, w + 1.0)
		Glyph.CARRIER:
			_fill(ci, o, s, [0.04, 0.58, 0.96, 0.58, 0.84, 0.82, 0.16, 0.82], col)
			_line(ci, o, s, 0.12, 0.44, 0.86, 0.44, col, w + 1.0)
			_fill(ci, o, s, [0.62, 0.18, 0.72, 0.36, 0.52, 0.36], col)
		Glyph.SIEGE:
			_fill(ci, o, s, [0.08, 0.78, 0.58, 0.78, 0.58, 0.90, 0.08, 0.90], col)
			_line(ci, o, s, 0.30, 0.74, 0.88, 0.30, col, w + 2.4)
			_circle(ci, o, s, 0.90, 0.24, 0.07, col, -1.0)
		Glyph.COMMAND:
			_fill(ci, o, s, [0.5, 0.04, 0.62, 0.36, 0.96, 0.38, 0.70, 0.58, 0.80, 0.92, 0.5, 0.72, 0.20, 0.92, 0.30, 0.58, 0.04, 0.38, 0.38, 0.36], col)
		Glyph.CAMO:
			_circle(ci, o, s, 0.5, 0.5, 0.40, col, w)
			_fill(ci, o, s, [0.30, 0.40, 0.52, 0.28, 0.70, 0.46, 0.54, 0.72, 0.34, 0.66], dk)
		Glyph.EMP_OFF:
			ci.draw_arc(o + Vector2(0.5, 0.5) * s, 0.36 * s, 0.0, TAU, 22, col, w, true)
			_line(ci, o, s, 0.22, 0.78, 0.78, 0.22, col, w + 0.6)
		Glyph.NO_POWER:
			_fill(ci, o, s, [0.60, 0.04, 0.22, 0.54, 0.46, 0.54, 0.38, 0.96, 0.80, 0.40, 0.54, 0.40, 0.68, 0.04], dk.lightened(0.15))
			_line(ci, o, s, 0.10, 0.90, 0.90, 0.10, UiPalette.DANGER, w + 0.8)
		Glyph.FOLLOW:
			_poly(ci, o, s, [0.10, 0.50, 0.50, 0.50, 0.50, 0.18, 0.92, 0.50, 0.50, 0.82, 0.50, 0.50], col, w, false)
		Glyph.HOLD:
			_fill(ci, o, s, [0.24, 0.16, 0.42, 0.16, 0.42, 0.84, 0.24, 0.84], col)
			_fill(ci, o, s, [0.58, 0.16, 0.76, 0.16, 0.76, 0.84, 0.58, 0.84], col)
		Glyph.PATROL:
			_poly(ci, o, s, [0.10, 0.62, 0.10, 0.30, 0.90, 0.30, 0.90, 0.62], col, w, false)
			_fill(ci, o, s, [0.02, 0.60, 0.18, 0.60, 0.10, 0.74], col)
			_fill(ci, o, s, [0.82, 0.60, 0.98, 0.60, 0.90, 0.74], col)
		Glyph.RETURN:
			_poly(ci, o, s, [0.86, 0.30, 0.86, 0.66, 0.28, 0.66], col, w, false)
			_fill(ci, o, s, [0.10, 0.66, 0.34, 0.46, 0.34, 0.86], col)
		Glyph.UNLOAD:
			_poly(ci, o, s, [0.12, 0.40, 0.12, 0.84, 0.88, 0.84, 0.88, 0.40], col, w, false)
			_line(ci, o, s, 0.5, 0.08, 0.5, 0.56, col, w + 0.6)
			_fill(ci, o, s, [0.34, 0.44, 0.66, 0.44, 0.5, 0.66], col)
		Glyph.STANCE:
			_fill(ci, o, s, [0.5, 0.06, 0.88, 0.22, 0.82, 0.62, 0.5, 0.94, 0.18, 0.62, 0.12, 0.22], col)
			_line(ci, o, s, 0.5, 0.22, 0.5, 0.70, dk, w)
		Glyph.RALLY:
			_line(ci, o, s, 0.26, 0.94, 0.26, 0.10, col, w)
			_fill(ci, o, s, [0.26, 0.12, 0.88, 0.28, 0.26, 0.48], col)
			_circle(ci, o, s, 0.26, 0.94, 0.06, col, -1.0)
		Glyph.PING:
			_circle(ci, o, s, 0.5, 0.5, 0.12, col, -1.0)
			_circle(ci, o, s, 0.5, 0.5, 0.30, col, w)
			_circle(ci, o, s, 0.5, 0.5, 0.46, Color(col, 0.55), w * 0.8)
		Glyph.SPEED:
			_poly(ci, o, s, [0.10, 0.28, 0.42, 0.50, 0.10, 0.72], col, w, false)
			_poly(ci, o, s, [0.48, 0.28, 0.80, 0.50, 0.48, 0.72], col, w, false)
		Glyph.MUTE:
			_fill(ci, o, s, [0.10, 0.38, 0.30, 0.38, 0.52, 0.18, 0.52, 0.82, 0.30, 0.62, 0.10, 0.62], col)
			_line(ci, o, s, 0.64, 0.34, 0.92, 0.66, col, w)
			_line(ci, o, s, 0.92, 0.34, 0.64, 0.66, col, w)
		Glyph.ROTATE_L:
			ci.draw_arc(o + Vector2(0.5, 0.52) * s, 0.32 * s, deg_to_rad(-60.0), deg_to_rad(200.0), 16, col, w + 0.4, true)
			_fill(ci, o, s, [0.10, 0.36, 0.34, 0.30, 0.22, 0.56], col)
		Glyph.ROTATE_R:
			ci.draw_arc(o + Vector2(0.5, 0.52) * s, 0.32 * s, deg_to_rad(-20.0), deg_to_rad(240.0), 16, col, w + 0.4, true)
			_fill(ci, o, s, [0.90, 0.36, 0.66, 0.30, 0.78, 0.56], col)
		Glyph.HOME:
			_poly(ci, o, s, [0.10, 0.50, 0.50, 0.14, 0.90, 0.50], col, w + 0.4, false)
			_poly(ci, o, s, [0.22, 0.46, 0.22, 0.86, 0.78, 0.86, 0.78, 0.46], col, w, false)
		Glyph.PAUSE:
			_fill(ci, o, s, [0.24, 0.16, 0.42, 0.16, 0.42, 0.84, 0.24, 0.84], col)
			_fill(ci, o, s, [0.58, 0.16, 0.76, 0.16, 0.76, 0.84, 0.58, 0.84], col)
		Glyph.MODE:
			_poly(ci, o, s, [0.10, 0.34, 0.80, 0.34], col, w + 0.4, false)
			_fill(ci, o, s, [0.74, 0.18, 0.94, 0.34, 0.74, 0.50], col)
			_poly(ci, o, s, [0.90, 0.68, 0.20, 0.68], col, w + 0.4, false)
			_fill(ci, o, s, [0.26, 0.52, 0.06, 0.68, 0.26, 0.84], col)
		Glyph.COVER:
			_fill(ci, o, s, [0.10, 0.44, 0.50, 0.14, 0.90, 0.44, 0.90, 0.84, 0.10, 0.84], col)
			_fill(ci, o, s, [0.30, 0.84, 0.30, 0.58, 0.70, 0.58, 0.70, 0.84], dk)
		Glyph.SMOKE:
			_circle(ci, o, s, 0.34, 0.60, 0.22, col, -1.0)
			_circle(ci, o, s, 0.62, 0.48, 0.26, col, -1.0)
			_circle(ci, o, s, 0.74, 0.70, 0.18, col, -1.0)
		_:
			_poly(ci, o, s, [0.5, 0.12, 0.88, 0.5, 0.5, 0.88, 0.12, 0.5], col, w, true)


## Role glyph of a unit def (5.10.4): capability first, then layer, then the class glyph.
static func role_glyph_unit(u: DefUnit) -> int:
	if u == null:
		return Glyph.VEHICLES
	var t: int = u.tags
	if (t & DefEnums.UT_COLLECTOR) != 0:
		return Glyph.COLLECTOR
	if u.has_ability(DefEnums.AbilityKind.DEPLOY_STRUCTURE):
		return Glyph.MCV
	if (t & DefEnums.UT_CAPTURE) != 0 or (t & DefEnums.UT_CONSTRUCTION) != 0:
		return Glyph.ENGINEER
	if (t & DefEnums.UT_TRANSPORT) != 0:
		return Glyph.TRANSPORT
	if (t & DefEnums.UT_CARRIER) != 0:
		return Glyph.CARRIER
	if (t & DefEnums.UT_UNMANNED) != 0 and (t & DefEnums.UT_AIRCRAFT) != 0:
		return Glyph.DRONE
	if (t & DefEnums.UT_SUBMARINE) != 0:
		return Glyph.SUBMARINE
	if (t & DefEnums.UT_SHIP) != 0:
		return Glyph.NAVAL
	if (t & DefEnums.UT_AIRCRAFT) != 0:
		return Glyph.AIRCRAFT
	if (t & DefEnums.UT_ANTI_AIR) != 0:
		return Glyph.ANTI_AIR
	if (t & DefEnums.UT_ARTILLERY) != 0:
		return Glyph.ARTILLERY
	if (t & DefEnums.UT_SIEGE) != 0:
		return Glyph.SIEGE
	if (t & DefEnums.UT_SCOUT) != 0:
		return Glyph.SCOUT
	if (t & DefEnums.UT_TANK) != 0:
		return Glyph.TANK
	if (t & DefEnums.UT_INFANTRY) != 0:
		return Glyph.INFANTRY
	return Glyph.VEHICLES


## Glyph of a structure def: defenses, the superweapon launcher and the plain structure glyph.
static func role_glyph_structure(s: DefStructure) -> int:
	if s == null:
		return Glyph.STRUCTURES
	if (s.tags & DefEnums.ST_SUPERWEAPON) != 0:
		return Glyph.MISSILE
	if (s.tags & (DefEnums.ST_DEFENSE | DefEnums.ST_ADVANCED_DEFENSE)) != 0:
		return Glyph.DEFENSE
	if (s.flags & DefEnums.SF_PRODUCTION) != 0:
		return Glyph.GEAR
	if (s.tags & DefEnums.ST_RELAY) != 0:
		return Glyph.RADAR
	return Glyph.STRUCTURES


static func _pts(o: Vector2, s: float, flat: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i: int in range(0, flat.size(), 2):
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
	if w < 0.0:
		ci.draw_circle(o + Vector2(cx, cy) * s, r * s, col)
	else:
		ci.draw_arc(o + Vector2(cx, cy) * s, r * s, 0.0, TAU, 28, col, w, true)
