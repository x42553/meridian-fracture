class_name UiMinimap
extends Control
## Minimap widget: terrain texture + fog overlay + unit dots + camera frustum + pings + radar sweep.
## Data in, signals out: the HUD pushes normalised (0..1) coordinates, the widget never reads the sim.
## Input: LMB press/drag moves the camera (drag keeps working outside the rect: Godot grabs the mouse for the
## Control that received the press), RMB issues a move order at that map position.

signal camera_requested(norm: Vector2)
signal order_requested(norm: Vector2)

const PAD := 5.0

var skin: UiSkin
var terrain: Texture2D
var fog: Texture2D
var dots_pos: PackedVector2Array = PackedVector2Array()
var dots_col: PackedColorArray = PackedColorArray()
var dots_size: PackedFloat32Array = PackedFloat32Array()
## Camera footprint polygon in normalised map coordinates (4 points).
var camera_quad: PackedVector2Array = PackedVector2Array()
var sweep_enabled: bool = true
var _pings: Array[Dictionary] = []
var _dragging: bool = false
var _t: float = 0.0
var _accum: float = 0.0
## Last _draw cost in microseconds (perf counter for the benchmark).
var last_draw_us: int = 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_CROSS

## Adds an expanding ring at a normalised map position (attack alerts, orders).
func add_ping(norm: Vector2, col: Color) -> void:
	_pings.append({"pos": norm, "t": 0.0, "col": col})

func set_dots(pos: PackedVector2Array, col: PackedColorArray, sizes: PackedFloat32Array) -> void:
	dots_pos = pos
	dots_col = col
	dots_size = sizes

func map_rect() -> Rect2:
	return Rect2(Vector2(PAD, PAD), size - Vector2(PAD, PAD) * 2.0)

func _process(delta: float) -> void:
	_t += delta
	for i in range(_pings.size() - 1, -1, -1):
		_pings[i]["t"] = float(_pings[i]["t"]) + delta
		if float(_pings[i]["t"]) > 1.6:
			_pings.remove_at(i)
	_accum += delta
	if _accum >= 1.0 / 30.0:
		_accum = 0.0
		queue_redraw()

func _norm_at(local: Vector2) -> Vector2:
	var m: Rect2 = map_rect()
	return ((local - m.position) / m.size).clamp(Vector2.ZERO, Vector2.ONE)

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				camera_requested.emit(_norm_at(mb.position))
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			order_requested.emit(_norm_at(mb.position))
			accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		camera_requested.emit(_norm_at(mm.position))
		accept_event()

func _draw() -> void:
	var t0: int = Time.get_ticks_usec()
	var m: Rect2 = map_rect()
	draw_style_box(get_theme_stylebox(&"panel", &"InsetPanel"), Rect2(Vector2.ZERO, size))
	if terrain != null:
		draw_texture_rect(terrain, m, false)
	if fog != null:
		draw_texture_rect(fog, m, false)
	# grid ticks every 1/8 of the map (cheap orientation aid)
	for i in range(1, 8):
		var f: float = float(i) / 8.0
		draw_line(Vector2(m.position.x + m.size.x * f, m.position.y), Vector2(m.position.x + m.size.x * f, m.end.y), Color(1, 1, 1, 0.035), 1.0)
		draw_line(Vector2(m.position.x, m.position.y + m.size.y * f), Vector2(m.end.x, m.position.y + m.size.y * f), Color(1, 1, 1, 0.035), 1.0)
	for i in dots_pos.size():
		var p: Vector2 = m.position + dots_pos[i] * m.size
		var s: float = dots_size[i]
		draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), dots_col[i])
	if camera_quad.size() == 4:
		var q := PackedVector2Array()
		for v in camera_quad:
			q.append(m.position + v.clamp(Vector2(-0.05, -0.05), Vector2(1.05, 1.05)) * m.size)
		draw_colored_polygon(q, Color(1, 1, 1, 0.06))
		q.append(q[0])
		draw_polyline(q, Color(1, 1, 1, 0.95), 1.5, true)
	for pg in _pings:
		var k: float = float(pg["t"]) / 1.6
		var c: Color = pg["col"]
		var p2: Vector2 = m.position + (pg["pos"] as Vector2) * m.size
		draw_arc(p2, 4.0 + k * 22.0, 0.0, TAU, 28, Color(c, 1.0 - k), 2.0, true)
		draw_circle(p2, 3.0, Color(c, 1.0 - k))
	if sweep_enabled:
		var c0: Vector2 = m.get_center()
		var ang: float = _t * 1.1
		var rad: float = m.size.length() * 0.5
		for j in 6:
			var a: float = ang - float(j) * 0.09
			var acc: Color = Color(skin.accent if skin != null else Color.WHITE, 0.16 * (1.0 - float(j) / 6.0))
			var pa := Vector2(cos(a), sin(a)) * rad
			var pb := Vector2(cos(a - 0.09), sin(a - 0.09)) * rad
			draw_colored_polygon(PackedVector2Array([c0, _clip(c0, pa, m), _clip(c0, pb, m)]), acc)
	draw_string(UiFonts.get_font(UiFonts.Role.HEAD), Vector2(m.position.x + 6.0, m.position.y + 14.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
	last_draw_us = Time.get_ticks_usec() - t0

## Clamp the far end of a ray to the map rect so the sweep wedge never leaves the widget.
func _clip(from: Vector2, dir: Vector2, m: Rect2) -> Vector2:
	var to: Vector2 = from + dir
	var t: float = 1.0
	if to.x > m.end.x:
		t = minf(t, (m.end.x - from.x) / dir.x)
	if to.x < m.position.x:
		t = minf(t, (m.position.x - from.x) / dir.x)
	if to.y > m.end.y:
		t = minf(t, (m.end.y - from.y) / dir.y)
	if to.y < m.position.y:
		t = minf(t, (m.position.y - from.y) / dir.y)
	return from + dir * t
