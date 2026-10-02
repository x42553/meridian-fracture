class_name FxBatch
extends RefCounted
## Ring buffer of MultiMesh instances animated entirely by a shader (fx_*.gdshader; render spec 5.9.1, 4.7).
## One batch = one draw call regardless of how many effects are alive; `capacity` is the HARD cap of the effect class (the
## oldest instance is overwritten and counted in `overwritten`). No per-frame CPU work: an instance becomes degenerate once
## `fx_time - spawn > life`; the batch node is hidden while nothing is alive.

var name: StringName
var index: int = 0
var capacity: int
var multimesh: MultiMesh
var node: MultiMeshInstance3D
## Latest expiry among live instances (fx clock seconds); the batch node is hidden after it passes.
var max_end: float = -1.0
## Instances written since the last reset_stats() and instances that had to overwrite a still-live slot (cap pressure).
var spawned: int = 0
var overwritten: int = 0

var _cursor: int = 0
var _high: int = 0  # slots ever written (visible_instance_count watermark; survives reset_stats and clear)
var _end: PackedFloat32Array = PackedFloat32Array()
var _t0: PackedFloat32Array = PackedFloat32Array()
var _shown: bool = false


func _init(p_name: StringName, mesh: Mesh, material: Material, p_capacity: int, parent: Node3D) -> void:
	name = p_name
	capacity = p_capacity
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	multimesh.custom_aabb = FxAssets.BIG_AABB
	multimesh.visible_instance_count = 0
	_end.resize(capacity)
	_t0.resize(capacity)
	var dead: Color = Color(-1000.0, 1.0, 0.0, 0.0)
	for i: int in capacity:
		multimesh.set_instance_custom_data(i, dead)
	node = MultiMeshInstance3D.new()
	node.name = String(p_name)
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = ViewLayers.MASK_FX
	node.visible = false
	parent.add_child(node)


## Writes one instance and returns its slot. `xf` encodes the effect geometry (see the shader headers).
func emit(xf: Transform3D, t0: float, life: float, seed_v: float, param: float) -> int:
	var i: int = _cursor
	_cursor = (i + 1) % capacity
	if _end[i] > t0:
		overwritten += 1
	var end: float = t0 + life
	_end[i] = end
	_t0[i] = t0
	if end > max_end:
		max_end = end
	spawned += 1
	if i >= _high:
		_high = i + 1
		multimesh.visible_instance_count = _high
	multimesh.set_instance_transform(i, xf)
	multimesh.set_instance_custom_data(i, Color(t0, life, seed_v, param))
	return i


## Cancels one instance early (e.g. a superweapon warning whose launcher was destroyed).
func kill(slot: int) -> void:
	multimesh.set_instance_custom_data(slot, Color(-1000.0, 1.0, 0.0, 0.0))
	_end[slot] = 0.0


## Kills `slot` only if it still holds the instance spawned at `t0` (the ring may have wrapped since).
func kill_if(slot: int, t0: float) -> void:
	if _t0[slot] == t0:
		kill(slot)


func clear() -> void:
	var dead: Color = Color(-1000.0, 1.0, 0.0, 0.0)
	for i: int in _high:
		multimesh.set_instance_custom_data(i, dead)
	_end.fill(0.0)
	max_end = -1.0
	_cursor = 0


## Hides the draw call while nothing is alive (constant draw calls stay ~ number of active kinds).
func sync_visibility(now: float) -> void:
	var show_it: bool = now < max_end
	if show_it != _shown:
		_shown = show_it
		node.visible = show_it


func is_shown() -> bool:
	return _shown


func active_count(now: float) -> int:
	var n: int = 0
	for i: int in _high:
		if _end[i] > now:
			n += 1
	return n


func reset_stats() -> void:
	spawned = 0
	overwritten = 0
