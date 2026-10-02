class_name UiDraw
extends RefCounted
## Stateless geometry and drawing helpers shared by styleboxes and widgets (ui.md 2.2). Pure functions.

## Glyph ids shared with `UiGlyphs.Glyph` (UI-01b); the fallback painter below knows these few.
const G_STOP: int = 9
const G_WARNING: int = 17
const G_CHEVRON_UP: int = 18
const G_CHEVRON_DOWN: int = 19
const G_CLOSE: int = 20
const G_CHECK: int = 21
const G_PLUS: int = 25
const G_INFO: int = 9000
const G_MINUS: int = 26

static var _glyph_script: Script = null
static var _glyph_probed: bool = false


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


## Points of an arc (usable for polylines / polygons; `draw_arc` draws only lines).
static func arc_points(center: Vector2, radius: float, a0: float, a1: float, count: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(count + 1)
	for i in count + 1:
		var a: float = lerpf(a0, a1, float(i) / float(count))
		pts[i] = center + Vector2(cos(a), sin(a)) * radius
	return pts


## Snap to the device pixel grid so 1 px lines stay crisp (value in logical px).
static func snap(v: float) -> float:
	return floorf(v) + 0.5


## Truncates `text` with an ellipsis so that it fits `max_w` px in `font` at `size`.
static func ellipsize(font: Font, text: String, size: int, max_w: float) -> String:
	if max_w <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return text
	var lo: int = 0
	var hi: int = text.length()
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		if font.get_string_size(text.substr(0, mid) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.substr(0, lo).strip_edges() + "…"


## `draw_string` with the design system's text shadow (0, 1 black 60 %).
static func shadow_string(ci: CanvasItem, font: Font, pos: Vector2, text: String, align: int, width: float, size: int, col: Color) -> void:
	ci.draw_string(font, pos + Vector2(0.0, 1.0), text, align, width, size, Color(0.0, 0.0, 0.0, 0.6))
	ci.draw_string(font, pos, text, align, width, size, col)


## A global script class by name if the project has it (`UiGlyphs` arrives with UI-01b), else null. Cached probe.
static func optional_script(cls: StringName) -> Script:
	for d: Dictionary in ProjectSettings.get_global_class_list():
		if StringName(d.get("class", "")) == cls:
			return load(String(d.get("path", ""))) as Script
	return null


## Installs a glyph painter (a Script with `static func draw(ci, glyph, rect, col, width)`); null re-runs the `UiGlyphs` lookup.
static func set_glyph_painter(script: Script) -> void:
	_glyph_script = script
	_glyph_probed = script != null


## Draws glyph `glyph` (`UiGlyphs.Glyph` id) into `rect`. Uses the vector glyph library when present, otherwise the
## fallback painter (chevrons, close, check, plus, minus, warning, diamond).
static func glyph(ci: CanvasItem, glyph_id: int, rect: Rect2, col: Color, width: float = 1.8) -> void:
	if not _glyph_probed:
		_glyph_probed = true
		_glyph_script = optional_script(&"UiGlyphs")
	if _glyph_script != null:
		_glyph_script.call(&"draw", ci, glyph_id, rect, col, width)
		return
	basic_glyph(ci, glyph_id, rect, col, width)


## Fallback painter used until the glyph library exists (and in tests).
static func basic_glyph(ci: CanvasItem, glyph_id: int, rect: Rect2, col: Color, width: float = 1.8) -> void:
	var c: Vector2 = rect.get_center()
	var h: float = minf(rect.size.x, rect.size.y) * 0.5
	match glyph_id:
		G_CHEVRON_UP:
			ci.draw_polyline(PackedVector2Array([c + Vector2(-h * 0.7, h * 0.3), c + Vector2(0.0, -h * 0.4), c + Vector2(h * 0.7, h * 0.3)]), col, width, true)
		G_CHEVRON_DOWN:
			ci.draw_polyline(PackedVector2Array([c + Vector2(-h * 0.7, -h * 0.3), c + Vector2(0.0, h * 0.4), c + Vector2(h * 0.7, -h * 0.3)]), col, width, true)
		G_CLOSE:
			ci.draw_line(c + Vector2(-h, -h) * 0.62, c + Vector2(h, h) * 0.62, col, width, true)
			ci.draw_line(c + Vector2(-h, h) * 0.62, c + Vector2(h, -h) * 0.62, col, width, true)
		G_CHECK:
			ci.draw_polyline(PackedVector2Array([c + Vector2(-h * 0.7, 0.0), c + Vector2(-h * 0.2, h * 0.5), c + Vector2(h * 0.7, -h * 0.5)]), col, width + 0.4, true)
		G_PLUS:
			ci.draw_line(c + Vector2(-h * 0.7, 0.0), c + Vector2(h * 0.7, 0.0), col, width, true)
			ci.draw_line(c + Vector2(0.0, -h * 0.7), c + Vector2(0.0, h * 0.7), col, width, true)
		G_MINUS:
			ci.draw_line(c + Vector2(-h * 0.7, 0.0), c + Vector2(h * 0.7, 0.0), col, width, true)
		G_WARNING:
			var tri := PackedVector2Array([c + Vector2(0.0, -h * 0.85), c + Vector2(h * 0.9, h * 0.7), c + Vector2(-h * 0.9, h * 0.7), c + Vector2(0.0, -h * 0.85)])
			ci.draw_polyline(tri, col, width, true)
			ci.draw_line(c + Vector2(0.0, -h * 0.25), c + Vector2(0.0, h * 0.15), col, width, true)
			ci.draw_rect(Rect2(c + Vector2(-width * 0.5, h * 0.35), Vector2(width, width)), col)
		G_INFO:
			ci.draw_arc(c, h * 0.85, 0.0, TAU, 24, col, width, true)
			ci.draw_line(c + Vector2(0.0, -h * 0.05), c + Vector2(0.0, h * 0.45), col, width, true)
			ci.draw_rect(Rect2(c + Vector2(-width * 0.5, -h * 0.5), Vector2(width, width)), col)
		_:
			var d := PackedVector2Array([c + Vector2(0.0, -h * 0.7), c + Vector2(h * 0.7, 0.0), c + Vector2(0.0, h * 0.7), c + Vector2(-h * 0.7, 0.0), c + Vector2(0.0, -h * 0.7)])
			ci.draw_polyline(d, col, width, true)
