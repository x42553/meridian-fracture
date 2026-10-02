class_name ViewNodeBackend
extends ViewUnitBackend
## One ViewModelRig (MeshInstance3D + instance uniforms) per entity; Forward+ default (Mobile and Compatibility use the batch
## backend). Rigs are pooled per model key (max POOL_MAX each) so death / production churn reuses nodes and their
## instance-uniform slots: remove() hides and parks, add() pops. Team colour rides in the (style, team) material.

const POOL_MAX: int = 64

var plain: bool = false  ## Compatibility renderer: per-entity plain-uniform materials instead of instance uniforms (see ViewModelRig.plain)
var _free: Dictionary = {}  # model key -> Array[ViewModelRig] (parked, hidden)
var _live: int = 0
var _created: int = 0
var _reused: int = 0


func setup(parent_node: Node3D, materials: ViewMaterials, q: ViewQuality) -> void:
	super.setup(parent_node, materials, q)
	plain = q != null and q.renderer == ViewQuality.Renderer.COMPATIBILITY


func _material_for(style_id: StringName, team_index: int) -> ShaderMaterial:
	if plain:
		return mats.new_entity_material(style_id, team_index)
	return mats.unit_material(style_id, ViewMaterials.Variant.NODE, team_index)


func add(ve: Object, model: Object, style_id: StringName, _team: Color, team_index: int) -> void:
	var key: StringName = model.key
	var mesh: Mesh = model.mesh
	var mat: ShaderMaterial = _material_for(style_id, team_index)
	var pool: Array = _free.get(key, []) as Array
	var rig: ViewModelRig = null
	if not pool.is_empty():
		rig = pool.pop_back() as ViewModelRig
		rig.plain = plain
		rig.material_override = mat
		rig.reset_state()
		rig.visible = true
		_reused += 1
	else:
		rig = ViewModelRig.new()
		rig.plain = plain
		rig.setup(mesh, mat)
		rig.set_meta(&"model_key", key)
		parent.add_child(rig)
		_created += 1
	rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	ve.rig = rig
	ve.slot = _live
	_live += 1


func remove(ve: Object) -> void:
	var rig: ViewModelRig = ve.rig as ViewModelRig
	if rig == null:
		return
	rig.visible = false
	var key: StringName = rig.get_meta(&"model_key", &"") as StringName
	var pool: Array = _free.get(key, []) as Array
	if pool.size() < POOL_MAX:
		pool.append(rig)
		_free[key] = pool
	else:
		rig.queue_free()
	ve.rig = null
	ve.slot = -1
	_live = maxi(_live - 1, 0)


func set_visible(ve: Object, vis: bool) -> void:
	var rig: ViewModelRig = ve.rig as ViewModelRig
	if rig != null:
		rig.visible = vis


func set_xform(ve: Object, xf: Transform3D) -> void:
	var rig: ViewModelRig = ve.rig as ViewModelRig
	if rig != null:
		rig.transform = xf


func push_anim(ve: Object) -> void:
	var rig: ViewModelRig = ve.rig as ViewModelRig
	if rig == null:
		return
	var sink: float = 0.0
	var s: Variant = ve.get(&"sink_m")
	if s is float:
		sink = s as float
	rig.push_anim(sink, ve.move01, ve.roll_m, ve.turret_yaw)


func push_aux(ve: Object) -> void:
	var rig: ViewModelRig = ve.rig as ViewModelRig
	if rig != null:
		rig.push_aux(ve.recoil, ve.deploy, ve.spin_angle, ve.elevation)


func push_state(ve: Object) -> void:
	var rig: ViewModelRig = ve.rig as ViewModelRig
	if rig != null:
		rig.push_state(ve.damage, ve.selected, ve.flags, ve.flash, ve.cloak)


func push_mounts(ve: Object) -> void:
	var rig: ViewModelRig = ve.rig as ViewModelRig
	if rig != null:
		rig.push_mounts(ve.mnt)


func set_team(ve: Object, _team: Color, team_index: int) -> void:
	var rig: ViewModelRig = ve.rig as ViewModelRig
	if rig != null:
		if plain:
			rig.replace_plain_material(mats.new_entity_material(ve.style_id, team_index))
		else:
			rig.material_override = mats.unit_material(ve.style_id, ViewMaterials.Variant.NODE, team_index)


func set_shadow(ve: Object, on: bool) -> void:
	var rig: ViewModelRig = ve.rig as ViewModelRig
	if rig != null:
		rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func stats() -> Dictionary:
	var parked: int = 0
	for k: Variant in _free:
		parked += (_free[k] as Array).size()
	return {"backend": "nodes", "live": _live, "parked": parked, "created": _created, "reused": _reused}
