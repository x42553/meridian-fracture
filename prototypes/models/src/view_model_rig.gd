class_name ViewModelRig
extends MeshInstance3D
## One unit/structure instance: a MeshInstance3D sharing an ArrayMesh + ShaderMaterial with every other instance of the
## same model. All per-instance variation (team colour, animation, damage, selection, fog) goes through instance
## uniforms, so 400 units cost 400 draw calls but ZERO extra materials/pipelines and no extra nodes.

const P_TEAM: StringName = &"u_team"
const P_ANIM: StringName = &"u_anim"
const P_AUX: StringName = &"u_aux"
const P_STATE: StringName = &"u_state"

var anim_time: float = 0.0
var move: float = 0.0
var roll: float = 0.0
var turret_yaw: float = 0.0
var recoil: float = 0.0
var deploy: float = 0.0
var spin: float = 0.0
var damage: float = 0.0
var selected: float = 0.0
var fog_mode: float = 0.0
var flash: float = 0.0


func setup(m: Mesh, material: Material, team: Color) -> ViewModelRig:
	mesh = m
	material_override = material
	set_instance_shader_parameter(P_TEAM, team)
	push_anim()
	push_aux()
	push_state()
	return self


func push_anim() -> void:
	set_instance_shader_parameter(P_ANIM, Color(anim_time, move, roll, turret_yaw))


func push_aux() -> void:
	set_instance_shader_parameter(P_AUX, Color(recoil, deploy, spin, 0.0))


func push_state() -> void:
	set_instance_shader_parameter(P_STATE, Color(damage, selected, fog_mode, flash))
