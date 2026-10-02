class_name ViewCamera
extends Node3D
## RTS camera rig (render spec 3.3 / 5.4): pan with constant screen speed, zoom-to-cursor, yaw orbit, height-dependent
## pitch, frame-rate independent smoothing, map clamp, terrain-height follow, shake, cinematic keys, ground picking.
## The rig owns a Camera3D child and keeps its own transform at identity (the child carries the pose). Nothing here
## touches the sim: the terrain is read through two Callables (`height_func`, `ground_pick_func`).
## ViewWorld.frame calls `advance(dt)` once per rendered frame; with `auto_input` the InputMap actions of
## `ensure_input_actions()` are read in there, otherwise callers drive pan_screen / zoom_by / rotate_yaw themselves.

signal view_changed(height: float, pitch_deg: float, yaw_deg: float)  ## |dheight| > 0.25 m or yaw / pitch moved > 0.1 deg
signal cinematic_changed(active: bool)  ## UI hides the HUD / shows the letterbox

const PITCH_MIN_DEG: float = 22.0
const PITCH_MAX_DEG: float = 82.0
const TILT_BIAS_MAX_DEG: float = 14.0
const FAR_M: float = 1500.0
const START_ZOOM: float = 0.30  ## match-start zoom (VQ2A: 0.35 -> 0.30, a tank hull of 4.2 m spans ~110 px at 1080p, the 95 px of the models spike)
const NEAR_FACTOR: float = 0.6
const SHAKE_DECAY_PER_S: float = 1.6
const SHAKE_OFFSET_M: float = 0.4
const SHAKE_ROLL_DEG: float = 0.5
const CINEMATIC_BLEND_S: float = 0.6
const RECT_GROW_M: float = 10.0
const FALLBACK_REACH_M: float = 900.0

const ACT_PAN_LEFT: StringName = &"cam_pan_left"
const ACT_PAN_RIGHT: StringName = &"cam_pan_right"
const ACT_PAN_UP: StringName = &"cam_pan_up"
const ACT_PAN_DOWN: StringName = &"cam_pan_down"
const ACT_ROTATE_LEFT: StringName = &"cam_rotate_left"
const ACT_ROTATE_RIGHT: StringName = &"cam_rotate_right"
const ACT_ZOOM_IN: StringName = &"cam_zoom_in"
const ACT_ZOOM_OUT: StringName = &"cam_zoom_out"
const ACT_ORBIT: StringName = &"cam_orbit"
const ACT_RESET: StringName = &"cam_reset"

## Setting `camera/wasd_pan`: WASD also pans (off by default because A / S / G / D are command hotkeys).
static var wasd_pan: bool = false

@export var height_min: float = 34.0  ## m above the focus at the closest zoom ("wide view" setting: max 110)
@export var height_max: float = 84.0
@export var pitch_near_deg: float = 46.0
@export var pitch_far_deg: float = 61.0
@export var fov_deg: float = 38.0  ## vertical (KEEP_HEIGHT)
@export var pan_speed: float = 1.1  ## m/s per metre of camera distance (constant screen speed)
@export var edge_scroll_enabled: bool = true  ## must be false in automation
@export var edge_margin_px: int = 10
@export var pan_smooth: float = 11.0
@export var zoom_smooth: float = 9.0
@export var rot_smooth: float = 12.0
@export var zoom_step: float = 0.08
@export var key_rotate_deg_per_s: float = 100.0
@export var orbit_deg_per_px: float = 0.22
@export var clamp_margin_m: float = 14.0
@export var auto_input: bool = true

var camera: Camera3D = null
var height_func: Callable = Callable()  ## (x: float, z: float) -> float
var ground_pick_func: Callable = Callable()  ## (origin: Vector3, dir: Vector3) -> Vector3, Vector3.INF on a miss
var view_margin_px: Vector4 = Vector4.ZERO  ## (left, top, right, bottom) HUD-occluded pixels
## Match-start anchor (xz metres): while it is finite the rig re-centres it in the HUD-free area whenever the margins change; any later pan / focus / drag clears it.
var start_anchor: Vector2 = Vector2(INF, INF)
var map_rect: Rect2 = Rect2(0.0, 0.0, 576.0, 576.0)
var cinematic_skippable: bool = true
var view_size_override: Vector2 = Vector2.ZERO  ## viewport size in pixels when > 0 (tests, replays, headless); else the real viewport

var _terrain: ViewTerrain = null
var _focus: Vector2 = Vector2(288.0, 288.0)
var _focus_t: Vector2 = Vector2(288.0, 288.0)
var _focus_y: float = 0.0
var _yaw: float = 0.0
var _yaw_t: float = 0.0
var _zoom: float = 0.4
var _zoom_t: float = 0.4
var _bias: float = 0.0
var _bias_t: float = 0.0
var _orbiting: bool = false
var _last_emit_height: float = -1000.0
var _last_emit_pitch: float = -1000.0
var _last_emit_yaw: float = -1000.0
var _trauma: float = 0.0
var _shake_t: float = 0.0
# cinematic
var _cine_keys: Array[Dictionary] = []
var _cine_loop: bool = false
var _cine_t: float = 0.0
var _cine_active: bool = false
var _cine_blend: float = -1.0  # >= 0 while blending back to the player pose
var _cine_from: Dictionary = {}
var _saved: Dictionary = {}
var _pose: Dictionary = {}  # focus Vector3, yaw rad, height, pitch rad, fov deg of the applied pose


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = FAR_M
	add_child(camera)
	_apply_pose()


func _ready() -> void:
	if auto_input:
		ensure_input_actions()
	camera.make_current()
	_apply_pose()


# ---- input actions ------------------------------------------------------------------------------------------

## Registers the cam_* actions when absent; an action that already exists (user bindings) is never touched.
static func ensure_input_actions() -> void:
	_add_action(ACT_PAN_LEFT, [_key(KEY_LEFT)] + ([_key(KEY_A)] if wasd_pan else []))
	_add_action(ACT_PAN_RIGHT, [_key(KEY_RIGHT)] + ([_key(KEY_D)] if wasd_pan else []))
	_add_action(ACT_PAN_UP, [_key(KEY_UP)] + ([_key(KEY_W)] if wasd_pan else []))
	_add_action(ACT_PAN_DOWN, [_key(KEY_DOWN)] + ([_key(KEY_S)] if wasd_pan else []))
	_add_action(ACT_ROTATE_LEFT, [_key(KEY_Q)])
	_add_action(ACT_ROTATE_RIGHT, [_key(KEY_E)])
	_add_action(ACT_ZOOM_IN, [_wheel(MOUSE_BUTTON_WHEEL_UP), _key(KEY_KP_ADD), _key(KEY_PAGEUP)])
	_add_action(ACT_ZOOM_OUT, [_wheel(MOUSE_BUTTON_WHEEL_DOWN), _key(KEY_KP_SUBTRACT), _key(KEY_PAGEDOWN)])
	_add_action(ACT_ORBIT, [_wheel(MOUSE_BUTTON_MIDDLE)])
	_add_action(ACT_RESET, [_key(KEY_HOME)])


static func _add_action(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for ev: Variant in events:
		InputMap.action_add_event(action, ev as InputEvent)


static func _key(code: Key) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	return e


static func _wheel(button: MouseButton) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = button
	return e


# ---- setup and placement ------------------------------------------------------------------------------------

## Map clamp rectangle (metres) and the terrain used for height follow and ground picking.
func configure(map_rect_m: Rect2, terrain_ref: ViewTerrain) -> void:
	map_rect = map_rect_m
	_terrain = terrain_ref
	if terrain_ref != null:
		height_func = terrain_ref.height_at
		ground_pick_func = terrain_ref.raycast


## Instantly places the rig. zoom01: 0 = closest, 1 = farthest; yaw 0 looks toward -Z (north).
func snap_to(focus_xz: Vector2, yaw_deg: float, zoom01: float, pitch_bias_deg: float = 0.0) -> void:
	_focus_t = _clamp_focus(focus_xz)
	_focus = _focus_t
	_yaw_t = deg_to_rad(yaw_deg)
	_yaw = _yaw_t
	_zoom_t = clampf(zoom01, 0.0, 1.0)
	_zoom = _zoom_t
	_bias_t = pitch_bias_deg
	_bias = pitch_bias_deg
	_focus_y = _ground(_focus.x, _focus.y)
	_apply_pose()


## QA absolute pose in map CELLS; `pitch_deg` becomes the tilt bias for this zoom (final pitch clamped to 22..82). Instant.
func set_pose(cell_x: float, cell_y: float, yaw_deg: float, pitch_deg: float, zoom01: float) -> void:
	var z: float = clampf(zoom01, 0.0, 1.0)
	var target: float = clampf(pitch_deg, PITCH_MIN_DEG, PITCH_MAX_DEG)
	snap_to(Vector2(cell_x, cell_y) * ViewConsts.CELL_M, yaw_deg, z, target - _base_pitch_deg(z))


## Smoothly (or instantly) centres a world point in the HUD-free area of the screen.
func focus_on(p: Vector3, instant: bool = false) -> void:
	start_anchor = Vector2(INF, INF)
	_focus_on_free_area(p, instant)


## Sets the HUD-occluded margins (pixels); a pending match-start anchor is re-centred in the new free area.
func set_view_margins(m: Vector4) -> void:
	view_margin_px = m
	if is_finite(start_anchor.x):
		_focus_on_free_area(Vector3(start_anchor.x, 0.0, start_anchor.y), true)


func _focus_on_free_area(p: Vector3, instant: bool) -> void:
	var t: Vector2 = Vector2(p.x, p.z)
	var vp_w: float = _viewport_size().x
	if view_margin_px.z != view_margin_px.x and vp_w > 0.0:
		var right: Vector2 = Vector2(cos(_yaw_t), -sin(_yaw_t))
		var dist: float = _height_of(_zoom_t) / sin(_pitch_of(_zoom_t, _bias_t))
		t += right * ((view_margin_px.z - view_margin_px.x) * 0.5 / vp_w * _ground_width(dist))
	_focus_t = _clamp_focus(t)
	if instant:
		_focus = _focus_t
		_focus_y = _ground(_focus.x, _focus.y)
		_apply_pose()


func focus_on_sim(x: int, y: int, instant: bool = false) -> void:
	var wx: float = float(x) * ViewConsts.M_PER_UNIT
	var wz: float = float(y) * ViewConsts.M_PER_UNIT
	focus_on(Vector3(wx, _ground(wx, wz), wz), instant)


func pan_world(delta_xz: Vector2) -> void:
	start_anchor = Vector2(INF, INF)
	_focus_t = _clamp_focus(_focus_t + delta_xz)


## Pan in camera-relative axes; dir.y = -1 moves toward the top of the screen.
func pan_screen(dir: Vector2, dt: float) -> void:
	if dir == Vector2.ZERO:
		return
	var dist: float = current_height() / sin(deg_to_rad(current_pitch_deg()))
	var fwd: Vector2 = Vector2(-sin(_yaw), -cos(_yaw))
	var right: Vector2 = Vector2(cos(_yaw), -sin(_yaw))
	pan_world((right * dir.x - fwd * dir.y) * pan_speed * dist * dt)


func rotate_yaw(deg: float) -> void:
	_yaw_t += deg_to_rad(deg)


func tilt(deg: float) -> void:
	_bias_t = clampf(_bias_t + deg, -TILT_BIAS_MAX_DEG, TILT_BIAS_MAX_DEG)


## Wheel zoom (steps > 0 zooms in). With a cursor position the focus drifts toward the ground point under it.
func zoom_by(steps: float, cursor: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if cursor.x >= 0.0 and ground_pick_func.is_valid():
		var hit: Vector3 = screen_to_ground(cursor)
		if hit != Vector3.INF:
			var k: float = clampf(steps * zoom_step * 1.5, -0.4, 0.4)
			_focus_t = _clamp_focus(_focus_t + (Vector2(hit.x, hit.z) - _focus_t) * k)
	_zoom_t = clampf(_zoom_t - steps * zoom_step, 0.0, 1.0)


func reset_orientation() -> void:
	_yaw_t = 0.0
	_bias_t = 0.0


# ---- per frame ----------------------------------------------------------------------------------------------

## Called by ViewWorld.frame: input (auto_input), smoothing, shake, cinematic.
func advance(dt: float) -> void:
	if _cine_active:
		_advance_cinematic(dt)
	else:
		if auto_input:
			_read_input(dt)
		_smooth(dt)
	_shake_t += dt
	_trauma = maxf(_trauma - SHAKE_DECAY_PER_S * dt, 0.0)
	_apply_pose()


func _read_input(dt: float) -> void:
	if not InputMap.has_action(ACT_PAN_LEFT):
		return
	var dir: Vector2 = Vector2(
		Input.get_action_strength(ACT_PAN_RIGHT) - Input.get_action_strength(ACT_PAN_LEFT),
		Input.get_action_strength(ACT_PAN_DOWN) - Input.get_action_strength(ACT_PAN_UP))
	if edge_scroll_enabled and dir == Vector2.ZERO and is_inside_tree() and DisplayServer.window_is_focused():
		var vp: Viewport = get_viewport()
		dir = edge_scroll_dir(vp.get_mouse_position(), vp.get_visible_rect().size, edge_margin_px)
	if dir != Vector2.ZERO:
		pan_screen(dir.normalized(), dt)
	rotate_yaw((Input.get_action_strength(ACT_ROTATE_LEFT) - Input.get_action_strength(ACT_ROTATE_RIGHT)) * key_rotate_deg_per_s * dt)


func _smooth(dt: float) -> void:
	var kp: float = 1.0 if dt <= 0.0 else 1.0 - exp(-pan_smooth * dt)
	var kz: float = 1.0 if dt <= 0.0 else 1.0 - exp(-zoom_smooth * dt)
	var kr: float = 1.0 if dt <= 0.0 else 1.0 - exp(-rot_smooth * dt)
	_focus = _focus.lerp(_focus_t, kp)
	_zoom = lerpf(_zoom, _zoom_t, kz)
	_yaw = lerp_angle(_yaw, _yaw_t, kr)
	_bias = lerpf(_bias, _bias_t, kr)
	_focus_y = lerpf(_focus_y, _ground(_focus.x, _focus.y), 1.0 if dt <= 0.0 else 1.0 - exp(-pan_smooth * 0.7 * dt))


func _unhandled_input(event: InputEvent) -> void:
	if not auto_input:
		return
	if _cine_active:
		if cinematic_skippable and ((event is InputEventKey and (event as InputEventKey).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)):
			cinematic_stop()
		return
	if event.is_action_pressed(ACT_ZOOM_IN):
		zoom_by(1.0, get_viewport().get_mouse_position())
	elif event.is_action_pressed(ACT_ZOOM_OUT):
		zoom_by(-1.0, get_viewport().get_mouse_position())
	elif event.is_action_pressed(ACT_RESET):
		reset_orientation()
	if event.is_action(ACT_ORBIT):
		_orbiting = event.is_pressed()
	if event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		rotate_yaw(-mm.relative.x * orbit_deg_per_px)
		tilt(mm.relative.y * orbit_deg_per_px)


## Screen-space edge-scroll direction for a mouse position (pure, unit-testable): (-1..1, -1..1); outside the view = 0.
static func edge_scroll_dir(mouse: Vector2, view_size: Vector2, margin: int) -> Vector2:
	var d: Vector2 = Vector2.ZERO
	if mouse.x < 0.0 or mouse.y < 0.0 or mouse.x > view_size.x or mouse.y > view_size.y:
		return d
	if mouse.x <= float(margin):
		d.x = -1.0
	elif mouse.x >= view_size.x - float(margin):
		d.x = 1.0
	if mouse.y <= float(margin):
		d.y = -1.0
	elif mouse.y >= view_size.y - float(margin):
		d.y = 1.0
	return d


# ---- shake ---------------------------------------------------------------------------------------------------

## trauma = min(1, trauma + amount); the caller has already attenuated by distance.
func add_shake(amount: float) -> void:
	_trauma = minf(_trauma + maxf(amount, 0.0), 1.0)


func trauma() -> float:
	return _trauma


# ---- cinematic -----------------------------------------------------------------------------------------------

## keys: {t, focus: Vector3, yaw_deg, height, pitch_deg, fov_deg?}. Sorted by t; input is ignored while it runs.
func cinematic_play(keys: Array[Dictionary], loop: bool = false) -> void:
	if keys.size() < 2:
		return
	_cine_keys = keys.duplicate()
	_cine_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["t"] as float) < (b["t"] as float))
	_cine_loop = loop
	_cine_t = _cine_keys[0]["t"] as float
	_cine_blend = -1.0
	_saved = {"focus": _focus, "focus_t": _focus_t, "yaw": _yaw, "yaw_t": _yaw_t, "zoom": _zoom, "zoom_t": _zoom_t, "bias": _bias, "bias_t": _bias_t}
	var was: bool = _cine_active
	_cine_active = true
	if not was:
		cinematic_changed.emit(true)


func cinematic_stop() -> void:
	if not _cine_active:
		return
	_restore_saved()
	_finish_cinematic()


func is_cinematic() -> bool:
	return _cine_active


func _restore_saved() -> void:
	_focus = _saved.get("focus", _focus)
	_focus_t = _saved.get("focus_t", _focus_t)
	_yaw = _saved.get("yaw", _yaw)
	_yaw_t = _saved.get("yaw_t", _yaw_t)
	_zoom = _saved.get("zoom", _zoom)
	_zoom_t = _saved.get("zoom_t", _zoom_t)
	_bias = _saved.get("bias", _bias)
	_bias_t = _saved.get("bias_t", _bias_t)
	_focus_y = _ground(_focus.x, _focus.y)


func _finish_cinematic() -> void:
	_cine_active = false
	_cine_blend = -1.0
	_cine_keys.clear()
	cinematic_changed.emit(false)


func _advance_cinematic(dt: float) -> void:
	if _cine_blend >= 0.0:
		_cine_blend += dt
		var u: float = clampf(_cine_blend / CINEMATIC_BLEND_S, 0.0, 1.0)
		var to: Dictionary = _player_pose_dict()
		_pose = _lerp_pose(_cine_from, to, _smootherstep(u))
		_focus = Vector2((_pose["focus"] as Vector3).x, (_pose["focus"] as Vector3).z)
		_focus_y = (_pose["focus"] as Vector3).y
		if u >= 1.0:
			_restore_saved()
			_finish_cinematic()
		return
	var t_first: float = _cine_keys[0]["t"] as float
	var t_last: float = _cine_keys[_cine_keys.size() - 1]["t"] as float
	_cine_t += dt
	if _cine_t >= t_last:
		if _cine_loop:
			_cine_t = t_first + fposmod(_cine_t - t_first, t_last - t_first)
		else:
			_cine_t = t_last
	_pose = _cinematic_pose(_cine_t)
	var f: Vector3 = _pose["focus"] as Vector3
	_focus = Vector2(f.x, f.z)
	_focus_y = f.y
	if not _cine_loop and _cine_t >= t_last:
		_cine_from = _pose.duplicate()
		_cine_blend = 0.0


func _cinematic_pose(t: float) -> Dictionary:
	var n: int = _cine_keys.size()
	var i: int = 0
	while i < n - 2 and t >= (_cine_keys[i + 1]["t"] as float):
		i += 1
	var k1: Dictionary = _cine_keys[i]
	var k2: Dictionary = _cine_keys[i + 1]
	var span: float = maxf((k2["t"] as float) - (k1["t"] as float), 0.0001)
	var u: float = clampf((t - (k1["t"] as float)) / span, 0.0, 1.0)
	var k0: Dictionary = _cine_keys[maxi(i - 1, 0)]
	var k3: Dictionary = _cine_keys[mini(i + 2, n - 1)]
	var f1: Vector3 = k1["focus"] as Vector3
	var f2: Vector3 = k2["focus"] as Vector3
	var focus: Vector3 = _catmull(k0["focus"] as Vector3, f1, f2, k3["focus"] as Vector3, u)
	if height_func.is_valid():
		focus.y = _ground(focus.x, focus.z)
	var e: float = _smootherstep(u)
	return {
		"focus": focus,
		"yaw": deg_to_rad(lerpf(k1["yaw_deg"] as float, k2["yaw_deg"] as float, e)),
		"height": lerpf(k1["height"] as float, k2["height"] as float, e),
		"pitch": deg_to_rad(lerpf(k1["pitch_deg"] as float, k2["pitch_deg"] as float, e)),
		"fov": lerpf(k1.get("fov_deg", fov_deg) as float, k2.get("fov_deg", fov_deg) as float, e),
	}


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


static func _smootherstep(u: float) -> float:
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


func _lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"focus": (a["focus"] as Vector3).lerp(b["focus"] as Vector3, t),
		"yaw": lerp_angle(a["yaw"] as float, b["yaw"] as float, t),
		"height": lerpf(a["height"] as float, b["height"] as float, t),
		"pitch": lerpf(a["pitch"] as float, b["pitch"] as float, t),
		"fov": lerpf(a["fov"] as float, b["fov"] as float, t),
	}


func _player_pose_dict() -> Dictionary:
	var z: float = _saved.get("zoom_t", _zoom_t) as float
	var fxz: Vector2 = _saved.get("focus_t", _focus_t) as Vector2
	return {
		"focus": Vector3(fxz.x, _ground(fxz.x, fxz.y), fxz.y),
		"yaw": _saved.get("yaw_t", _yaw_t) as float,
		"height": _height_of(z),
		"pitch": _pitch_of(z, _saved.get("bias_t", _bias_t) as float),
		"fov": fov_deg,
	}


# ---- pose ----------------------------------------------------------------------------------------------------

static func ease_zoom(z: float) -> float:
	return 0.35 * z * z + 0.65 * z


func _height_of(z: float) -> float:
	return lerpf(height_min, height_max, ease_zoom(z))


func _base_pitch_deg(z: float) -> float:
	return lerpf(pitch_near_deg, pitch_far_deg, ease_zoom(z))


func _pitch_of(z: float, bias: float) -> float:
	return deg_to_rad(clampf(_base_pitch_deg(z) + bias, PITCH_MIN_DEG, PITCH_MAX_DEG))


func current_height() -> float:
	return float(_pose["height"]) if _cine_active and not _pose.is_empty() else _height_of(_zoom)


func current_pitch_deg() -> float:
	return rad_to_deg(_pose["pitch"] as float) if _cine_active and not _pose.is_empty() else rad_to_deg(_pitch_of(_zoom, _bias))


func current_yaw_deg() -> float:
	return rad_to_deg(_pose["yaw"] as float) if _cine_active and not _pose.is_empty() else rad_to_deg(_yaw)


func current_focus() -> Vector3:
	return Vector3(_focus.x, _focus_y, _focus.y)


func current_zoom() -> float:
	return _zoom


## Writes the camera transform from the smoothed state (or the cinematic pose) and applies shake to the child only.
func _apply_pose() -> void:
	var focus: Vector3 = current_focus()
	var yaw: float = _yaw
	var height: float = _height_of(_zoom)
	var pitch: float = _pitch_of(_zoom, _bias)
	var fov: float = fov_deg
	if _cine_active and not _pose.is_empty():
		yaw = _pose["yaw"] as float
		height = _pose["height"] as float
		pitch = _pose["pitch"] as float
		fov = _pose["fov"] as float
	var dist: float = height / sin(pitch)
	var offset: Vector3 = (Vector3(0.0, sin(pitch), cos(pitch)) * dist).rotated(Vector3.UP, yaw)
	var eye: Vector3 = focus + offset
	var base: Transform3D = Transform3D(Basis.looking_at(focus - eye, Vector3.UP), eye)
	if _trauma > 0.0:
		var a: float = _trauma * _trauma
		var sx: float = sin(_shake_t * 35.0)
		var sy: float = sin(_shake_t * 53.0 + 1.7)
		var sr: float = sin(_shake_t * 71.0 + 4.1)
		var mag: float = SHAKE_OFFSET_M * height / 34.0 * a
		base = base * Transform3D(Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(SHAKE_ROLL_DEG) * a * sr), Vector3(sx * mag, sy * mag, 0.0))
	camera.transform = base
	camera.fov = fov
	camera.near = maxf(2.0, NEAR_FACTOR * height)
	camera.far = FAR_M
	var yaw_deg: float = rad_to_deg(yaw)
	var pitch_deg: float = rad_to_deg(pitch)
	if absf(height - _last_emit_height) > 0.25 or absf(pitch_deg - _last_emit_pitch) > 0.1 or absf(rad_to_deg(angle_difference(deg_to_rad(_last_emit_yaw), deg_to_rad(yaw_deg)))) > 0.1:
		_last_emit_height = height
		_last_emit_pitch = pitch_deg
		_last_emit_yaw = yaw_deg
		view_changed.emit(height, pitch_deg, yaw_deg)


# ---- queries -------------------------------------------------------------------------------------------------

## Ray (origin, unit direction) through a screen position, computed from the rig itself (no Camera3D internals, so it also
## works before the node entered the tree). Vertical fov, KEEP_HEIGHT.
func screen_ray(p: Vector2) -> Array[Vector3]:
	var size: Vector2 = _viewport_size()
	var xf: Transform3D = camera.global_transform if camera.is_inside_tree() else camera.transform
	var tv: float = tan(deg_to_rad(camera.fov) * 0.5)
	var ndc: Vector2 = Vector2(p.x / size.x * 2.0 - 1.0, 1.0 - p.y / size.y * 2.0)
	var d: Vector3 = xf.basis * Vector3(ndc.x * tv * size.x / size.y, ndc.y * tv, -1.0).normalized()
	return [xf.origin, d.normalized()]


## World point -> screen pixels (Vector2(-1e9, -1e9) when behind the camera).
func world_to_screen(w: Vector3) -> Vector2:
	var size: Vector2 = _viewport_size()
	var xf: Transform3D = camera.global_transform if camera.is_inside_tree() else camera.transform
	var l: Vector3 = xf.affine_inverse() * w
	if l.z >= -0.0001:
		return Vector2(-1.0e9, -1.0e9)
	var tv: float = tan(deg_to_rad(camera.fov) * 0.5)
	var ndc: Vector2 = Vector2(l.x / (-l.z * tv * size.x / size.y), l.y / (-l.z * tv))
	return Vector2((ndc.x + 1.0) * 0.5 * size.x, (1.0 - ndc.y) * 0.5 * size.y)


## Screen position -> ground point through the heightfield raycast (Vector3.INF on a miss).
func screen_to_ground(p: Vector2) -> Vector3:
	var r: Array[Vector3] = screen_ray(p)
	if not ground_pick_func.is_valid():
		return _plane_hit(r[0], r[1])
	return ground_pick_func.call(r[0], r[1]) as Vector3


func _plane_hit(o: Vector3, d: Vector3) -> Vector3:
	if d.y >= -0.0001:
		return Vector3.INF
	return o + d * ((_plane_y() - o.y) / d.y)


func _plane_y() -> float:
	return _terrain.src.sea_level_m if _terrain != null and _terrain.src != null and _terrain.src.has_water() else 0.0


## AABB (metres, xz) of the frustum's ground footprint: four corner rays vs the heightfield, grown by 10 m.
func visible_ground_rect() -> Rect2:
	var size: Vector2 = _viewport_size()
	var corners: Array[Vector2] = [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for c: Vector2 in corners:
		var hit: Vector3 = screen_to_ground(c)
		if hit == Vector3.INF:
			var rr: Array[Vector3] = screen_ray(c)
			var o: Vector3 = rr[0]
			var d: Vector3 = rr[1]
			hit = Vector3(o.x + d.x * FALLBACK_REACH_M, 0.0, o.z + d.z * FALLBACK_REACH_M) if Vector2(d.x, d.z).length() > 0.01 else o
		lo = Vector2(minf(lo.x, hit.x), minf(lo.y, hit.z))
		hi = Vector2(maxf(hi.x, hit.x), maxf(hi.y, hit.z))
	return Rect2(lo, hi - lo).grow(RECT_GROW_M)


## Audio listener: yaw-only orientation, positioned at the focus point (not at the camera 40-90 m up in the air).
func listener_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _yaw if not _cine_active else (_pose.get("yaw", _yaw) as float)), current_focus())


# ---- helpers -------------------------------------------------------------------------------------------------

func _viewport_size() -> Vector2:
	if view_size_override.x > 0.0 and view_size_override.y > 0.0:
		return view_size_override
	if is_inside_tree():
		var s: Vector2 = get_viewport().get_visible_rect().size
		if s.x > 0.0 and s.y > 0.0:
			return s
	return Vector2(1920.0, 1080.0)


## Screen pixels per metre of a surface facing the camera at the focus point for a zoom01 (viewport height `vp_h_px`, default fov / heights).
func px_per_m(zoom01: float, vp_h_px: float = 1080.0) -> float:
	var dist: float = _height_of(zoom01) / sin(_pitch_of(zoom01, 0.0))
	return vp_h_px / (2.0 * dist * tan(deg_to_rad(fov_deg) * 0.5))


## Horizontal ground extent (m) seen across the screen at `dist` m from the camera.
func _ground_width(dist: float) -> float:
	var s: Vector2 = _viewport_size()
	return 2.0 * dist * tan(deg_to_rad(fov_deg) * 0.5) * s.x / s.y


func _ground(x: float, z: float) -> float:
	if height_func.is_valid():
		return height_func.call(x, z) as float
	return 0.0


func _clamp_focus(p: Vector2) -> Vector2:
	var r: Rect2 = map_rect.grow(-clamp_margin_m)
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
