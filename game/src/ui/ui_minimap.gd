class_name UiMinimap
extends Control
## Minimap widget (ui.md 5.12): inset panel -> terrain `TextureRect` (+ the view's fog material, or the placeholder fog
## texture) -> 1/8 grid ticks -> ghosts -> class-shaped blips -> camera quad -> strategic-warning circles -> pings ->
## radar sweep -> "N". Data in through `set_feed` / `set_camera_quad` / `add_ping`, signals out. It never reads the
## sim. Redraws at 30 Hz only when the feed changed, a ping is alive or the sweep runs.
## Input: LMB press / drag = `camera_requested` (the press grabs the mouse, so dragging outside the rect keeps
## emitting), double click = `camera_snap`, RMB = `order_requested(norm, mods)`, armed PING = `ping_requested`, the wheel
## is consumed (no camera zoom through the widget).

signal camera_requested(norm: Vector2)
signal camera_snap(norm: Vector2)
signal order_requested(norm: Vector2, mods: int)
signal ping_requested(norm: Vector2)

const PAD: float = 5.0
const PING_LIFE_S: float = 1.0
const PING_KIND_ORDER: int = 0
const PING_KIND_ALERT: int = 1
const PING_KIND_ALLY: int = 2
const PING_KIND_SUPERWEAPON: int = 3
const MOD_SHIFT: int = 1
const MOD_CTRL: int = 2

var sweep_enabled: bool = true
var ping_armed: bool = false  ## LMB while the PING mode is armed -> `ping_requested` instead of the camera
var map_cells: Vector2i = Vector2i(96, 96)  ## for the letterbox and `norm_to_sim`
var last_draw_us: int = 0

var _feed: UiMinimapFeed = null
var _quad: PackedVector2Array = PackedVector2Array()
var _pings: Array[Dictionary] = []  ## {pos, t, life, col, kind}
var _tex: TextureRect = null
var _fog: TextureRect = null
var _top: Control = null
var _dragging: bool = false
var _t: float = 0.0
var _accum: float = 0.0
var _feed_rev: int = -1
var _dirty: bool = true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	mouse_force_pass_scroll_events = false
	custom_minimum_size = Vector2(float(UiMetrics.MINIMAP_MIN), float(UiMetrics.MINIMAP_MIN))
	_tex = TextureRect.new()
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_tex)
	_fog = TextureRect.new()
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.stretch_mode = TextureRect.STRETCH_SCALE
	_fog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_fog)
	_top = _Top.new()
	(_top as _Top).owner_map = self
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)


## The overlay child that draws everything above the textures.
class _Top extends Control:
	var owner_map: UiMinimap = null

	func _draw() -> void:
		if owner_map != null:
			owner_map._draw_overlay(self)


# ---- data in ----------------------------------------------------------------------------------------------------------
func set_feed(f: UiMinimapFeed) -> void:
	_feed = f
	if f != null and f.map_w > 0:
		map_cells = Vector2i(f.map_w, f.map_h)
		_layout()
	_dirty = true


## Terrain texture (one texel per cell) and the view's material (terrain + this viewer's fog in one pass); either may be null.
func set_source(terrain: Texture2D, material_in: Material) -> void:
	_tex.texture = terrain
	_tex.material = material_in
	if terrain != null and _feed == null:
		map_cells = Vector2i(terrain.get_width(), terrain.get_height())
	_layout()
	_dirty = true


## Placeholder fog overlay (alpha texture) used until the view's fog material exists.
func set_fog(tex: Texture2D) -> void:
	_fog.texture = tex
	_dirty = true


## The camera footprint in normalised map coordinates (4 points; fewer hides the quad).
func set_camera_quad(q: PackedVector2Array) -> void:
	_quad = q
	_dirty = true


## Adds an expanding ring; `kind` 0 order (1 s), 1 alert (3 s), 2 ally (3 s), 3 superweapon (until cleared).
func add_ping(norm: Vector2, col: Color, kind: int) -> void:
	var life: float = PING_LIFE_S
	if kind == PING_KIND_ALERT or kind == PING_KIND_ALLY:
		life = 3.0
	elif kind == PING_KIND_SUPERWEAPON:
		life = 12.0
	_pings.append({"pos": norm, "t": 0.0, "life": life, "col": col, "kind": kind})
	_dirty = true


func ping_count() -> int:
	return _pings.size()


func clear_pings() -> void:
	_pings.clear()
	_dirty = true


# ---- geometry ---------------------------------------------------------------------------------------------------------
## The map rect inside the widget: pad 5, non-square maps letterboxed keeping the cell aspect.
func map_rect() -> Rect2:
	var box := Rect2(Vector2(PAD, PAD), size - Vector2(PAD, PAD) * 2.0)
	var aspect: float = float(maxi(map_cells.x, 1)) / float(maxi(map_cells.y, 1))
	var w: float = box.size.x
	var h: float = box.size.x / aspect
	if h > box.size.y:
		h = box.size.y
		w = h * aspect
	return Rect2(box.position + (box.size - Vector2(w, h)) * 0.5, Vector2(w, h))


## Local position -> normalised map coordinate (clamped).
func norm_at(local: Vector2) -> Vector2:
	var m: Rect2 = map_rect()
	return ((local - m.position) / m.size).clamp(Vector2.ZERO, Vector2.ONE)


## `round(norm x cells x 1024)` clamped to the map.
func norm_to_sim(norm: Vector2) -> Vector2i:
	var mx: int = map_cells.x * 1024
	var my: int = map_cells.y * 1024
	return Vector2i(clampi(roundi(norm.x * float(mx)), 0, mx), clampi(roundi(norm.y * float(my)), 0, my))


func _layout() -> void:
	var m: Rect2 = map_rect()
	for c: Control in [_tex, _fog]:
		c.position = m.position
		c.size = m.size
	_top.position = Vector2.ZERO
	_top.size = size


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_layout()
			_dirty = true
		NOTIFICATION_THEME_CHANGED:
			_dirty = true


# ---- frame ------------------------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	for i: int in range(_pings.size() - 1, -1, -1):
		_pings[i]["t"] = float(_pings[i]["t"]) + delta
		if float(_pings[i]["t"]) > float(_pings[i]["life"]):
			_pings.remove_at(i)
			_dirty = true
	_accum += delta
	if _accum < 1.0 / float(UiMetrics.MINIMAP_HZ):
		return
	_accum = 0.0
	var moving: bool = not _pings.is_empty() or (sweep_enabled and not UiMotion.reduce_motion)
	var rev: int = _feed.revision if _feed != null else -1
	if _dirty or moving or rev != _feed_rev:
		_feed_rev = rev
		_dirty = false
		_top.queue_redraw()


func _draw() -> void:
	draw_style_box(get_theme_stylebox(&"panel", &"InsetPanel"), Rect2(Vector2.ZERO, size))
	var m: Rect2 = map_rect()
	if _tex.texture == null:
		draw_rect(m, Color(UiPalette.BG_DEEP, 1.0))


func _draw_overlay(ci: Control) -> void:
	var t0: int = Time.get_ticks_usec()
	var m: Rect2 = map_rect()
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	for i: int in range(1, 8):
		var f: float = float(i) / 8.0
		ci.draw_line(Vector2(m.position.x + m.size.x * f, m.position.y), Vector2(m.position.x + m.size.x * f, m.end.y), Color(1, 1, 1, 0.035), 1.0)
		ci.draw_line(Vector2(m.position.x, m.position.y + m.size.y * f), Vector2(m.end.x, m.position.y + m.size.y * f), Color(1, 1, 1, 0.035), 1.0)
	if _feed != null:
		_draw_feed(ci, m)
	if _quad.size() == 4:
		var q := PackedVector2Array()
		for v: Vector2 in _quad:
			q.append(m.position + v.clamp(Vector2(-0.05, -0.05), Vector2(1.05, 1.05)) * m.size)
		if not Geometry2D.triangulate_polygon(q).is_empty():  # a quad squeezed onto the map border (camera far off the map) is degenerate
			ci.draw_colored_polygon(q, Color(1, 1, 1, 0.06))
		q.append(q[0])
		ci.draw_polyline(q, Color(1, 1, 1, 0.95), 1.5, true)
	if _feed != null:
		for i2: int in _feed.warn_norm.size():
			var wp: Vector2 = m.position + _feed.warn_norm[i2] * m.size
			var wr: float = maxf(_feed.warn_radius_norm[i2] * m.size.x, 5.0)
			ci.draw_arc(wp, wr, 0.0, TAU, 28, Color(UiPalette.DANGER, 0.55 + 0.4 * UiMotion.pulse(_t)), 1.5, true)
	for pg: Dictionary in _pings:
		var life: float = float(pg["life"])
		var k: float = fposmod(float(pg["t"]), PING_LIFE_S) / PING_LIFE_S
		var fade: float = clampf((life - float(pg["t"])) / 0.4, 0.0, 1.0)
		var c: Color = pg["col"]
		var p2: Vector2 = m.position + (pg["pos"] as Vector2) * m.size
		ci.draw_arc(p2, 4.0 + 22.0 * k, 0.0, TAU, 28, Color(c, (1.0 - k) * fade), 2.0, true)
		ci.draw_circle(p2, 3.0, Color(c, fade))
	if sweep_enabled and not UiMotion.reduce_motion:
		var c0: Vector2 = m.get_center()
		var ang: float = _t * 1.1
		var rad: float = m.size.length() * 0.5
		for j: int in 6:
			var a: float = ang - float(j) * 0.09
			var pa := Vector2(cos(a), sin(a)) * rad
			var pb := Vector2(cos(a - 0.09), sin(a - 0.09)) * rad
			ci.draw_colored_polygon(PackedVector2Array([c0, _clip(c0, pa, m), _clip(c0, pb, m)]), Color(acc, 0.16 * (1.0 - float(j) / 6.0)))
	ci.draw_string(UiFonts.get_font(UiFonts.Role.HEAD), Vector2(m.position.x + 6.0, m.position.y + 15.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
	last_draw_us = Time.get_ticks_usec() - t0


func _draw_feed(ci: Control, m: Rect2) -> void:
	for gp: Vector2 in _feed.ghost_norm:
		var g: Vector2 = m.position + gp * m.size
		ci.draw_rect(Rect2(g - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(1, 1, 1, 0.5), false, 1.0)
	var pulse: float = UiMotion.pulse(_t, 1.0)
	for i: int in _feed.dots_norm.size():
		var p: Vector2 = m.position + _feed.dots_norm[i] * m.size
		var s: float = _feed.dots_size[i]
		var col: Color = _feed.dots_color[i]
		var own: bool = _feed.dots_own[i] == 1
		match _feed.dots_class[i]:
			UiMinimapFeed.C_INFANTRY:
				ci.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), col)
			UiMinimapFeed.C_VEHICLE:
				if own:
					ci.draw_rect(Rect2(p - Vector2(s, s) * 0.5 - Vector2.ONE, Vector2(s, s) + Vector2(2, 2)), Color(0, 0, 0, 0.8))
				ci.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), col)
			UiMinimapFeed.C_AIR:
				var h: float = s * 0.8
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -h), p + Vector2(h, 0), p + Vector2(0, h), p + Vector2(-h, 0)]), col)
			UiMinimapFeed.C_NAVAL:
				var h2: float = s * 0.75
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -h2), p + Vector2(h2, h2), p + Vector2(-h2, h2)]), col)
			UiMinimapFeed.C_STRUCTURE:
				var rr := Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s))
				ci.draw_rect(rr, Color(0.02, 0.03, 0.05, 0.85))
				ci.draw_rect(rr, col, false, 1.0)
			UiMinimapFeed.C_NEUTRAL:
				ci.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), UiPalette.TEXT_MUTE, false, 1.0)
			UiMinimapFeed.C_SUPERWEAPON:
				var rad: float = s * (0.5 + 0.12 * pulse)
				var pts := PackedVector2Array()
				for k: int in 10:
					var a: float = -PI * 0.5 + float(k) * PI / 5.0
					var rk: float = rad if k % 2 == 0 else rad * 0.45
					pts.append(p + Vector2(cos(a), sin(a)) * rk)
				ci.draw_colored_polygon(pts, col)


## Clamps the far end of a ray to the map rect so the sweep wedge never leaves the widget.
func _clip(from: Vector2, dir: Vector2, m: Rect2) -> Vector2:
	var to: Vector2 = from + dir
	var t: float = 1.0
	if to.x > m.end.x and dir.x != 0.0:
		t = minf(t, (m.end.x - from.x) / dir.x)
	if to.x < m.position.x and dir.x != 0.0:
		t = minf(t, (m.position.x - from.x) / dir.x)
	if to.y > m.end.y and dir.y != 0.0:
		t = minf(t, (m.end.y - from.y) / dir.y)
	if to.y < m.position.y and dir.y != 0.0:
		t = minf(t, (m.position.y - from.y) / dir.y)
	return from + dir * t


# ---- input ------------------------------------------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var n: Vector2 = norm_at(mb.position)
				if ping_armed:
					ping_requested.emit(n)
				else:
					_dragging = true
					if mb.double_click:
						camera_snap.emit(n)
					else:
						camera_requested.emit(n)
			else:
				_dragging = false
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var mods: int = (MOD_SHIFT if mb.shift_pressed else 0) | (MOD_CTRL if mb.is_command_or_control_pressed() else 0)
			order_requested.emit(norm_at(mb.position), mods)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		camera_requested.emit(norm_at(mm.position))
		accept_event()
