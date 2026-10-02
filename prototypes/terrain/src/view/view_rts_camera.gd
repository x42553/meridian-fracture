class_name ViewRtsCamera
extends Node3D
## RTS camera rig: pan (keys / edge scroll / drag), zoom-to-cursor, yaw orbit, height-dependent pitch, exponential
## smoothing (frame-rate independent), map clamp, terrain-height follow, focus-on-point and ground picking.
## The rig owns a Camera3D child. It never touches the sim: it only reads the terrain through two callables.

signal view_changed(height: float, pitch_deg: float)

@export var height_min: float = 34.0            ## camera altitude above the focus at closest zoom (m)
@export var height_max: float = 84.0            ## ... at farthest zoom
@export var pitch_near_deg: float = 46.0        ## pitch below horizon at closest zoom
@export var pitch_far_deg: float = 61.0         ## ... at farthest zoom (more top-down)
@export var fov_deg: float = 38.0
@export var pan_speed: float = 1.1              ## m/s per metre of camera distance (constant screen speed)
@export var edge_scroll_enabled: bool = true
@export var edge_margin_px: int = 10
@export var pan_smooth: float = 11.0
@export var zoom_smooth: float = 9.0
@export var rot_smooth: float = 12.0
@export var map_rect: Rect2 = Rect2(0.0, 0.0, 576.0, 576.0)
@export var clamp_margin_m: float = 14.0
@export var zoom_step: float = 0.08
@export var key_rotate_deg_per_s: float = 100.0
@export var orbit_deg_per_px: float = 0.22

var camera: Camera3D
## (x: float, z: float) -> float ground height. Optional; without it the focus stays at y = 0.
var height_func: Callable
## (origin: Vector3, dir: Vector3) -> Vector3 ground hit (Vector3.INF on miss), e.g. ViewTerrain.raycast.
var ground_pick_func: Callable

var _focus: Vector2 = Vector2(288.0, 288.0)
var _focus_t: Vector2 = Vector2(288.0, 288.0)
var _focus_y: float = 0.0
var _yaw: float = 0.0
var _yaw_t: float = 0.0
var _zoom: float = 0.4
var _zoom_t: float = 0.4
var _pitch_bias: float = 0.0
var _pitch_bias_t: float = 0.0
var _orbiting: bool = false
var _last_height: float = -1.0
var _external_pan: Vector2 = Vector2.ZERO


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = fov_deg
	camera.far = 4000.0
	add_child(camera)
	camera.make_current()
	_apply(0.0)


## Instantly places the rig. zoom01: 0 = closest, 1 = farthest. yaw in degrees (0 looks toward -Z / north).
func snap_to(focus_xz: Vector2, yaw_deg: float, zoom01: float, pitch_bias_deg: float = 0.0) -> void:
	_focus_t = _clamp_focus(focus_xz)
	_focus = _focus_t
	_yaw_t = deg_to_rad(yaw_deg)
	_yaw = _yaw_t
	_zoom_t = clampf(zoom01, 0.0, 1.0)
	_zoom = _zoom_t
	_pitch_bias_t = pitch_bias_deg
	_pitch_bias = pitch_bias_deg
	_focus_y = _ground(_focus.x, _focus.y)
	_apply(0.0)


## Smoothly (or instantly) centres the view on a world point, e.g. the selection or a "base under attack" alert.
func focus_on(p: Vector3, instant: bool = false) -> void:
	_focus_t = _clamp_focus(Vector2(p.x, p.z))
	if instant:
		_focus = _focus_t
		_focus_y = _ground(_focus.x, _focus.y)
		_apply(0.0)


## World-space pan of the target focus (metres, already in world axes).
func pan_world(delta_xz: Vector2) -> void:
	_focus_t = _clamp_focus(_focus_t + delta_xz)


## Pan in camera-relative axes; dir.y = -1 moves toward the top of the screen.
func pan_screen(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		return
	var dist: float = _current_height() / sin(_current_pitch())
	var fwd: Vector2 = Vector2(-sin(_yaw), -cos(_yaw))
	var right: Vector2 = Vector2(cos(_yaw), -sin(_yaw))
	pan_world((right * dir.x - fwd * dir.y) * pan_speed * dist * delta)


func rotate_yaw(deg: float) -> void:
	_yaw_t += deg_to_rad(deg)


func tilt(deg: float) -> void:
	_pitch_bias_t = clampf(_pitch_bias_t + deg, -14.0, 14.0)


## Wheel zoom (steps > 0 zooms in). With a cursor position the focus drifts toward the ground point under it.
func zoom_by(steps: float, cursor: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if cursor.x >= 0.0 and ground_pick_func.is_valid():
		var hit: Vector3 = screen_to_ground(cursor)
		if hit != Vector3.INF:
			var k: float = clampf(steps * zoom_step * 1.5, -0.4, 0.4)
			_focus_t = _clamp_focus(_focus_t + (Vector2(hit.x, hit.z) - _focus_t) * k)
	_zoom_t = clampf(_zoom_t - steps * zoom_step, 0.0, 1.0)


## Screen position -> ground point (Vector3.INF on miss). Uses the ground_pick_func heightfield raycast.
func screen_to_ground(screen_pos: Vector2) -> Vector3:
	if not ground_pick_func.is_valid():
		return Vector3.INF
	var o: Vector3 = camera.project_ray_origin(screen_pos)
	var d: Vector3 = camera.project_ray_normal(screen_pos)
	return ground_pick_func.call(o, d)


func current_focus() -> Vector3:
	return Vector3(_focus.x, _focus_y, _focus.y)


func current_height() -> float:
	return _current_height()


func current_pitch_deg() -> float:
	return rad_to_deg(_current_pitch())


## Screen-space edge-scroll direction for a mouse position (pure function, unit-testable).
static func edge_scroll_dir(mouse: Vector2, view_size: Vector2, margin: int) -> Vector2:
	var d: Vector2 = Vector2.ZERO
	if mouse.x < 0.0 or mouse.y < 0.0 or mouse.x > view_size.x or mouse.y > view_size.y:
		return d
	if mouse.x <= margin:
		d.x = -1.0
	elif mouse.x >= view_size.x - margin:
		d.x = 1.0
	if mouse.y <= margin:
		d.y = -1.0
	elif mouse.y >= view_size.y - margin:
		d.y = 1.0
	return d


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.0, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(-1.0, mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed
	elif event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event
		rotate_yaw(-mm.relative.x * orbit_deg_per_px)
		tilt(mm.relative.y * orbit_deg_per_px)


func _process(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if edge_scroll_enabled and dir == Vector2.ZERO and DisplayServer.window_is_focused():
		dir = edge_scroll_dir(get_viewport().get_mouse_position(), get_viewport().get_visible_rect().size, edge_margin_px)
	pan_screen(dir.normalized() if dir != Vector2.ZERO else dir, delta)
	if Input.is_key_pressed(KEY_Q):
		rotate_yaw(key_rotate_deg_per_s * delta)
	if Input.is_key_pressed(KEY_E):
		rotate_yaw(-key_rotate_deg_per_s * delta)
	_apply(delta)


func _apply(delta: float) -> void:
	var kp: float = 1.0 if delta <= 0.0 else 1.0 - exp(-pan_smooth * delta)
	var kz: float = 1.0 if delta <= 0.0 else 1.0 - exp(-zoom_smooth * delta)
	var kr: float = 1.0 if delta <= 0.0 else 1.0 - exp(-rot_smooth * delta)
	_focus = _focus.lerp(_focus_t, kp)
	_zoom = lerpf(_zoom, _zoom_t, kz)
	_yaw = lerp_angle(_yaw, _yaw_t, kr)
	_pitch_bias = lerpf(_pitch_bias, _pitch_bias_t, kr)
	_focus_y = lerpf(_focus_y, _ground(_focus.x, _focus.y), kp * 0.7 if delta > 0.0 else 1.0)
	var height: float = _current_height()
	var pitch: float = _current_pitch()
	var dist: float = height / sin(pitch)
	var focus: Vector3 = Vector3(_focus.x, _focus_y, _focus.y)
	var offset: Vector3 = Vector3(0.0, sin(pitch), cos(pitch)) * dist
	offset = offset.rotated(Vector3.UP, _yaw)
	if camera != null:
		camera.near = maxf(2.0, height * 0.72)
		camera.fov = fov_deg
		camera.look_at_from_position(focus + offset, focus, Vector3.UP)
	if absf(height - _last_height) > 0.25:
		_last_height = height
		view_changed.emit(height, rad_to_deg(pitch))


func _current_height() -> float:
	var s: float = _zoom * _zoom * 0.35 + _zoom * 0.65     # gentle ease: finer control when close
	return lerpf(height_min, height_max, s)


func _current_pitch() -> float:
	var s: float = _zoom * _zoom * 0.35 + _zoom * 0.65
	return deg_to_rad(clampf(lerpf(pitch_near_deg, pitch_far_deg, s) + _pitch_bias, 22.0, 82.0))


func _ground(x: float, z: float) -> float:
	if height_func.is_valid():
		return height_func.call(x, z)
	return 0.0


func _clamp_focus(p: Vector2) -> Vector2:
	var r: Rect2 = map_rect.grow(-clamp_margin_m)
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
