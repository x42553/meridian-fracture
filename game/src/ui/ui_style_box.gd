class_name UiStyleBox
extends StyleBox
## Chamfered, vertically graded, glow-bordered panel style drawn with RenderingServer canvas commands (spike 3).
## A GDScript StyleBox overriding `_draw` plugs into a Theme like a built-in stylebox (PanelContainer.panel,
## Button.normal ...). Vector-only: crisp at any UI scale. It costs ~90 us per redraw, so never redraw a styled
## panel every frame (ui.md 5.19.6); instances are shared through `cached()` (one per recipe, state and skin).

var fill_top: Color = UiPalette.BG_RAISED
var fill_bottom: Color = UiPalette.BG_PANEL
var border_color: Color = UiPalette.LINE
var border_width: float = 1.0
## Soft glow drawn as a wide translucent line under the crisp border (alpha 0 = off).
var glow: Color = Color(0.0, 0.0, 0.0, 0.0)
## Corner cuts (top_left, top_right, bottom_right, bottom_left) in px.
var cuts: Vector4 = Vector4.ZERO
## Alpha of a 1 px white highlight just inside the top edge.
var highlight: float = 0.06
## Accent brackets hugging the cut corners (alpha 0 = off). Mask: 1 TL, 2 TR, 4 BR, 8 BL.
var bracket_color: Color = Color(0.0, 0.0, 0.0, 0.0)
var bracket_len: float = 12.0
var bracket_width: float = 2.0
var bracket_mask: int = 5

static var _cache: Dictionary = {}


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var pts: PackedVector2Array = UiDraw.chamfer_points(rect, cuts)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	var h: float = maxf(rect.size.y, 1.0)
	for i in pts.size():
		cols[i] = fill_top.lerp(fill_bottom, clampf((pts[i].y - rect.position.y) / h, 0.0, 1.0))
	if fill_top.a > 0.0 or fill_bottom.a > 0.0:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, cols)
	var inner: Rect2 = rect.grow(-border_width * 0.5)
	var outline: PackedVector2Array = UiDraw.chamfer_points(inner, cuts)
	outline.append(outline[0])
	if glow.a > 0.0:
		RenderingServer.canvas_item_add_polyline(to_canvas_item, outline, PackedColorArray([glow]), border_width + 3.0, true)
	if highlight > 0.0:
		var y: float = rect.position.y + border_width + 0.5
		RenderingServer.canvas_item_add_line(to_canvas_item, Vector2(rect.position.x + cuts.x + 1.0, y), Vector2(rect.end.x - cuts.y - 1.0, y), Color(1.0, 1.0, 1.0, highlight), 1.0)
	if border_width > 0.0 and border_color.a > 0.0:
		RenderingServer.canvas_item_add_polyline(to_canvas_item, outline, PackedColorArray([border_color]), border_width, true)
	if bracket_color.a > 0.0:
		_brackets(to_canvas_item, inner)


func _brackets(item: RID, r: Rect2) -> void:
	var col := PackedColorArray([bracket_color])
	var l: float = bracket_len
	if bracket_mask & 1:
		var c: float = cuts.x
		RenderingServer.canvas_item_add_polyline(item, PackedVector2Array([Vector2(r.position.x, r.position.y + c + l), Vector2(r.position.x, r.position.y + c), Vector2(r.position.x + c, r.position.y), Vector2(r.position.x + c + l, r.position.y)]), col, bracket_width, true)
	if bracket_mask & 2:
		var c: float = cuts.y
		RenderingServer.canvas_item_add_polyline(item, PackedVector2Array([Vector2(r.end.x - c - l, r.position.y), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c), Vector2(r.end.x, r.position.y + c + l)]), col, bracket_width, true)
	if bracket_mask & 4:
		var c: float = cuts.z
		RenderingServer.canvas_item_add_polyline(item, PackedVector2Array([Vector2(r.end.x, r.end.y - c - l), Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.end.x - c - l, r.end.y)]), col, bracket_width, true)
	if bracket_mask & 8:
		var c: float = cuts.w
		RenderingServer.canvas_item_add_polyline(item, PackedVector2Array([Vector2(r.position.x + c + l, r.end.y), Vector2(r.position.x + c, r.end.y), Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.end.y - c - l)]), col, bracket_width, true)


## Copy of this style with a different look (hover / pressed variants derive from one recipe).
func variant(top: Color, bottom: Color, border: Color, glow_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> UiStyleBox:
	var s := duplicate() as UiStyleBox
	s.fill_top = top
	s.fill_bottom = bottom
	s.border_color = border
	s.glow = glow_color
	return s


## Content margins in px (left, top, right, bottom); returns self for chaining.
func set_padding(left: float, top: float, right: float, bottom: float) -> UiStyleBox:
	content_margin_left = left
	content_margin_top = top
	content_margin_right = right
	content_margin_bottom = bottom
	return self


## Shared instance for `key` (recipe|state|skin key), built once by `make`. Widgets and the theme use this so no
## style box is allocated inside `_draw` or per redraw (ui.md 5.19.6 rule 2).
static func cached(key: String, make: Callable) -> UiStyleBox:
	var hit: Variant = _cache.get(key)
	if hit != null and is_instance_valid(hit as Object):
		return hit as UiStyleBox
	var s: UiStyleBox = make.call() as UiStyleBox
	_cache[key] = s
	return s


## Drops every cached instance (skin / accessibility rebuild).
static func clear_cache() -> void:
	_cache.clear()


static func cache_size() -> int:
	return _cache.size()
