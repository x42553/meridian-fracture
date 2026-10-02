class_name ViewUnitBackend
extends RefCounted
## Abstract unit backend (render spec 3.4): ViewNodeBackend (one MeshInstance3D per entity, Forward+) and ViewBatchBackend
## (MultiMesh, Mobile / Compatibility) implement it. `ve` is a ViewEntity; the parameter is typed Object here so the backends
## do not depend on the entity class, and they only touch this duck-typed contract:
##   read : style_id, team_index, roll_m, move01, turret_yaw, elevation, recoil, deploy, spin_angle, damage, selected, flash,
##          flags, cloak, mnt (PackedFloat32Array, 9 floats); optional sink_m (float, structure sink depth in metres)
##   write: rig (the backend handle), slot (int)
## `model` is a ViewModel ({key: StringName, mesh: Mesh, info: ViewModelInfo}).

var mats: ViewMaterials = null
var quality: ViewQuality = null
var parent: Node3D = null


func setup(parent_node: Node3D, materials: ViewMaterials, q: ViewQuality) -> void:
	parent = parent_node
	mats = materials
	quality = q


func add(_ve: Object, _model: Object, _style_id: StringName, _team: Color, _team_index: int) -> void:
	push_error("ViewUnitBackend.add is abstract")


func remove(_ve: Object) -> void:
	push_error("ViewUnitBackend.remove is abstract")


func set_visible(_ve: Object, _vis: bool) -> void:
	push_error("ViewUnitBackend.set_visible is abstract")


func set_xform(_ve: Object, _xf: Transform3D) -> void:
	push_error("ViewUnitBackend.set_xform is abstract")


## u_anim: (sink_depth_m, move, roll, turret_yaw)
func push_anim(_ve: Object) -> void:
	push_error("ViewUnitBackend.push_anim is abstract")


## u_aux: (recoil, deploy_or_activity, spin_angle, elevation)
func push_aux(_ve: Object) -> void:
	push_error("ViewUnitBackend.push_aux is abstract")


## u_state: (damage, selected, flags, flash)
func push_state(_ve: Object) -> void:
	push_error("ViewUnitBackend.push_state is abstract")


## u_mnt1..3 (only entities with extra mounts)
func push_mounts(_ve: Object) -> void:
	push_error("ViewUnitBackend.push_mounts is abstract")


func set_team(_ve: Object, _team: Color, _team_index: int) -> void:
	push_error("ViewUnitBackend.set_team is abstract")


func set_shadow(_ve: Object, _on: bool) -> void:
	push_error("ViewUnitBackend.set_shadow is abstract")


## Batch backends write their MultiMesh buffers here; the node backend has nothing to do.
func flush() -> void:
	pass


func stats() -> Dictionary:
	return {}
