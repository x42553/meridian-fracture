class_name FxBatch
extends RefCounted
## Ring buffer of MultiMesh instances animated entirely by a shader (see fx_*.gdshader).
## One batch = one draw call regardless of how many effects are alive; capacity is the hard cap for the
## effect class (oldest instance is overwritten). No per-frame CPU work: an instance simply becomes
## degenerate once (fx_time - spawn) exceeds its lifetime.

var name: StringName
var index: int = 0
var capacity: int
var multimesh: MultiMesh
var node: MultiMeshInstance3D
## Latest expiry among live instances (fx clock seconds); the batch node is hidden after it passes.
var max_end: float = -1.0
var spawned: int = 0
## Spawns that had to overwrite a still-live instance (cap pressure indicator).
var overwritten: int = 0

var _cursor: int = 0
var _end: PackedFloat32Array
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
	_end = PackedFloat32Array()
	_end.resize(capacity)
	for i in capacity:
		multimesh.set_instance_custom_data(i, Color(-1000.0, 1.0, 0.0, 0.0))
	node = MultiMeshInstance3D.new()
	node.name = String(p_name)
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	parent.add_child(node)


## Writes one instance. Returns its slot. `xf` encodes the effect geometry (see the shader headers).
func emit(xf: Transform3D, t0: float, life: float, seed_v: float, param: float) -> int:
	var i: int = _cursor
	_cursor = (i + 1) % capacity
	if _end[i] > t0:
		overwritten += 1
	var end: float = t0 + life
	_end[i] = end
	if end > max_end:
		max_end = end
	spawned += 1
	if spawned <= capacity:
		multimesh.visible_instance_count = spawned
	multimesh.set_instance_transform(i, xf)
	multimesh.set_instance_custom_data(i, Color(t0, life, seed_v, param))
	return i


## Cancels one instance early (e.g. a superweapon warning whose launcher was destroyed).
func kill(slot: int) -> void:
	multimesh.set_instance_custom_data(slot, Color(-1000.0, 1.0, 0.0, 0.0))
	_end[slot] = 0.0


func clear() -> void:
	for i in capacity:
		multimesh.set_instance_custom_data(i, Color(-1000.0, 1.0, 0.0, 0.0))
	_end.fill(0.0)
	max_end = -1.0


## Hides the draw call while nothing is alive (constant draw calls stay ~ number of active kinds).
func sync_visibility(now: float) -> void:
	var show: bool = now < max_end
	if show != _shown:
		_shown = show
		node.visible = show


func active_count(now: float) -> int:
	var n: int = 0
	for i in capacity:
		if _end[i] > now:
			n += 1
	return n
