class_name SndListener
extends Node3D
## Owns the AudioListener3D and couples it to the RTS camera (audio spec 3.5 / 5.3): the listener sits on the smoothed
## ground focus point, turned by the camera yaw, and the zoom scale pulls the battlefield closer when the camera is high.

var focus: Vector3 = Vector3.ZERO
var zoom_scale: float = 1.0
var yaw: float = 0.0

var _pool: SndVoicePool = null
var _mix: SndMixConfig = null
var _listener: AudioListener3D = null
var _primed: bool = false


## Creates the AudioListener3D under `parent` and makes it current. False (and no listener) when the viewport has no
## current Camera3D: positional audio would be silent (spike rule 2).
func setup(parent: Node3D, pool: SndVoicePool, mix: SndMixConfig) -> bool:
	_pool = pool
	_mix = mix
	if get_parent() == null:
		parent.add_child(self)
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return false
	if _listener == null:
		_listener = AudioListener3D.new()
		_listener.name = "AudioListener"
		add_child(_listener)
	_listener.make_current()
	return true


func has_camera() -> bool:
	return is_inside_tree() and get_viewport().get_camera_3d() != null


## Only the yaw of `basis` is used, extracted as atan2(z.x, z.z); a camera looking straight down keeps the previous yaw.
func set_camera(p_focus: Vector3, cam_basis: Basis, height: float, dt: float) -> void:
	if not _primed:
		focus = p_focus
		_primed = true
	else:
		var a: float = 1.0 - exp(-dt / maxf(_mix.focus_smooth_s, 0.001))
		focus = focus.lerp(p_focus, a)
	var z: Vector3 = cam_basis.z
	if absf(z.x) + absf(z.z) > 0.05:
		yaw = atan2(z.x, z.z)
	zoom_scale = clampf(height / maxf(_mix.ref_height_m, 1.0), _mix.zoom_scale_min, _mix.zoom_scale_max)
	global_position = Vector3(focus.x, _mix.listener_height_m, focus.z)
	rotation = Vector3(0.0, yaw, 0.0)
	if _pool != null:
		_pool.set_listener(focus, 1.0 / zoom_scale)


func hearing_radius_m() -> float:
	return _mix.max_scan_m * zoom_scale


func release() -> void:
	if _listener != null and is_instance_valid(_listener):
		_listener.clear_current()
		_listener.queue_free()
	_listener = null
