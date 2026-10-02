class_name UiFactionBadge
extends Control
## Faction emblem control (ui.md 2.7 / art_direction 3): draws the op lists of `style.emblems` (poly / circle / line / arc in a
## unit square, y down, colour roles c1 / c2 / dim / bg) in the faction's skin colours, and optionally the subfaction mark as a
## lower-right disc badge. Below 48 px the badge is replaced by 1-3 pips. `muted` greys it (Open / Closed slots). The op lists are
## read once from `res://data/recipes/style.json`; an unknown faction draws a plain chamfered frame.

const STYLE_PATH: String = "res://data/recipes/style.json"

static var _emblems: Dictionary = {}

var faction_code: String = "":
	set(v):
		faction_code = v.to_lower()
		queue_redraw()
## "napc.canada"-style key of the subfaction mark ("" = vanilla, no badge).
var sub_key: String = "":
	set(v):
		sub_key = v.to_lower()
		queue_redraw()
var muted: bool = false:
	set(v):
		muted = v
		queue_redraw()


func _init(code: String = "", size_px: float = 48.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(size_px, size_px)
	faction_code = code


static func _load() -> void:
	if not _emblems.is_empty():
		return
	var f: FileAccess = FileAccess.open(STYLE_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and (parsed as Dictionary).get("emblems") is Dictionary:
			_emblems = (parsed as Dictionary)["emblems"] as Dictionary
	if _emblems.is_empty():
		_emblems = {"factions": {}, "subs": {}, "pips": {}}


## Op list of a faction ("napc") or subfaction ("napc.canada"); empty when unknown.
static func ops_of(code: String, sub: String = "") -> Array:
	_load()
	var table: Variant = (_emblems.get("subs", {}) as Dictionary).get(sub) if sub != "" else (_emblems.get("factions", {}) as Dictionary).get(code)
	return table as Array if table is Array else []


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	if s <= 0.0:
		return
	var skin: UiSkin = UiSkinSet.shared().skin_for(faction_code)
	var c1: Color = skin.accent
	var c2: Color = skin.accent2
	var dim: Color = c1.darkened(0.6)
	var bg: Color = UiPalette.BG_PANEL
	if muted:
		c1 = UiPalette.TEXT_MUTE.darkened(0.2)
		c2 = UiPalette.TEXT_MUTE
		dim = UiPalette.TEXT_MUTE.darkened(0.6)
	var origin: Vector2 = (size - Vector2(s, s)) * 0.5
	var ops: Array = ops_of(faction_code)
	if ops.is_empty():
		draw_polyline(PackedVector2Array([origin + Vector2(0.15, 0.1) * s, origin + Vector2(0.85, 0.1) * s, origin + Vector2(0.85, 0.75) * s,
			origin + Vector2(0.5, 0.95) * s, origin + Vector2(0.15, 0.75) * s, origin + Vector2(0.15, 0.1) * s]), c1, maxf(1.5, s * 0.06), true)
	else:
		draw_ops(self, ops, Rect2(origin, Vector2(s, s)), c1, c2, dim, bg)
	if sub_key != "" and s >= 40.0:
		var sub_ops: Array = ops_of(faction_code, sub_key)
		if not sub_ops.is_empty():
			var d: float = s * 0.44
			var r: Rect2 = Rect2(origin + Vector2(s - d, s - d), Vector2(d, d))
			draw_circle(r.get_center(), d * 0.5, bg)
			draw_arc(r.get_center(), d * 0.5, 0.0, TAU, 24, c2, maxf(1.0, s * 0.03), true)
			draw_ops(self, sub_ops, r.grow(-d * 0.1), c1, c2, dim, bg)


## Draws an op list into `rect` (unit square scaled to it).
static func draw_ops(ci: CanvasItem, ops: Array, rect: Rect2, c1: Color, c2: Color, dim: Color, bg: Color) -> void:
	var s: float = rect.size.x
	var px: float = maxf(1.5, 0.0)
	for raw: Variant in ops:
		var op: Array = raw as Array
		match String(op[0]):
			"poly":
				var pts: PackedVector2Array = _points(op[1] as Array, rect)
				var col: Color = _role(String(op[2]), c1, c2, dim, bg)
				if String(op[3]) == "fill":
					if pts.size() >= 3:
						ci.draw_colored_polygon(pts, col)
				else:
					var closed: PackedVector2Array = pts.duplicate()
					closed.append(pts[0])
					ci.draw_polyline(closed, col, maxf(px, float(op[4]) * s), true)
			"circle":
				var c: Vector2 = rect.position + Vector2(float(op[1]), float(op[2])) * s
				var r: float = float(op[3]) * s
				var col2: Color = _role(String(op[4]), c1, c2, dim, bg)
				if String(op[5]) == "fill":
					ci.draw_circle(c, r, col2)
				else:
					ci.draw_arc(c, r, 0.0, TAU, 28, col2, maxf(px, float(op[6]) * s), true)
			"line":
				ci.draw_polyline(_points(op[1] as Array, rect), _role(String(op[2]), c1, c2, dim, bg), maxf(px, float(op[3]) * s), true)
			"arc":
				var c3: Vector2 = rect.position + Vector2(float(op[1]), float(op[2])) * s
				ci.draw_arc(c3, float(op[3]) * s, deg_to_rad(float(op[4])), deg_to_rad(float(op[5])), 28, _role(String(op[6]), c1, c2, dim, bg),
					maxf(px, float(op[7]) * s), true)


static func _points(flat: Array, rect: Rect2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in flat.size() / 2:
		out.append(rect.position + Vector2(float(flat[i * 2]), float(flat[i * 2 + 1])) * rect.size.x)
	return out


static func _role(role: String, c1: Color, c2: Color, dim: Color, bg: Color) -> Color:
	match role:
		"c1":
			return c1
		"c2":
			return c2
		"dim":
			return dim
	return bg
