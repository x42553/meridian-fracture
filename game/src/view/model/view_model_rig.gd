class_name ViewModelRig
extends MeshInstance3D
## One node-backend instance: a MeshInstance3D sharing an ArrayMesh + a (style, team) ShaderMaterial with every other instance
## of the same model. All per-instance variation (animation, damage, selection, flags) goes through instance uniforms
## (Forward+ / Mobile); team colour lives in the material. The rig only forwards values: each push is skipped when the packed
## vec4 equals the last write (spec 3.5), so an idle unit costs nothing.
## Values are written as Vector4, NEVER Color: the engine sRGB-converts Color values written to a vec4 uniform (verified on 4.7.2:
## Color(0.5) reaches the shader as 0.214), which would distort damage, yaw, roll and every other animation channel.

const P_ANIM: StringName = &"u_anim"
const P_AUX: StringName = &"u_aux"
const P_STATE: StringName = &"u_state"
const P_MNT1: StringName = &"u_mnt1"
const P_MNT2: StringName = &"u_mnt2"
const P_MNT3: StringName = &"u_mnt3"
const CLOAK_SCALE: float = 0.999  ## cloak level rides in the fraction of the flags float (unit.gdshader decodes it)

var _last_anim: Vector4 = Vector4(NAN, 0.0, 0.0, 0.0)
var _last_aux: Vector4 = Vector4(NAN, 0.0, 0.0, 0.0)
var _last_state: Vector4 = Vector4(NAN, 0.0, 0.0, 0.0)
var _last_mnt: PackedFloat32Array = PackedFloat32Array()
var writes: int = 0  ## instance-uniform writes since creation (tests, stats)
## Compatibility renderer: instance uniforms are capped by the GL uniform buffer (4096 items, 6 per rig: ~680 rigs, then the engine prints
## "Too many instances using shader instance variables"), so the rig owns a private MATERIAL_UNIFORMS material and writes plain uniforms on it.
var plain: bool = false


## `m` is the model mesh, `mat` the (style, team) ShaderMaterial from ViewMaterials.
func setup(m: Mesh, mat: Material) -> ViewModelRig:
	mesh = m
	material_override = mat
	reset_state()
	return self


## Forces every uniform back to rest (pooled reuse) and clears the write cache.
func reset_state() -> void:
	_last_anim = Vector4(NAN, 0.0, 0.0, 0.0)
	_last_aux = Vector4(NAN, 0.0, 0.0, 0.0)
	_last_state = Vector4(NAN, 0.0, 0.0, 0.0)
	_last_mnt = PackedFloat32Array()
	push_anim(0.0, 0.0, 0.0, 0.0)
	push_aux(0.0, 0.0, 0.0, 0.0)
	push_state(0.0, 0.0, 0, 0.0, 0.0)


## One uniform write: an instance uniform (Forward+ / Mobile) or a plain uniform of the rig's own material (Compatibility).
func _write(param: StringName, v: Vector4) -> void:
	if plain:
		var sm: ShaderMaterial = material_override as ShaderMaterial
		if sm != null:
			sm.set_shader_parameter(param, v)
	else:
		set_instance_shader_parameter(param, v)


## Swaps the private material of a plain rig (team change) keeping the current uniform values.
func replace_plain_material(m: ShaderMaterial) -> void:
	var old: ShaderMaterial = material_override as ShaderMaterial
	if old != null:
		for n: StringName in [P_ANIM, P_AUX, P_STATE, P_MNT1, P_MNT2, P_MNT3]:
			var v: Variant = old.get_shader_parameter(n)
			if v != null:
				m.set_shader_parameter(n, v)
	material_override = m


## u_anim: (sink depth m [structures], move 0..1, roll metres, turret yaw rad relative to the hull).
func push_anim(sink_m: float, move: float, roll_m: float, turret_yaw: float) -> void:
	var c: Vector4 = Vector4(sink_m, move, roll_m, turret_yaw)
	if c == _last_anim:
		return
	_last_anim = c
	_write(P_ANIM, c)
	writes += 1


## u_aux: (recoil 0..1, deploy / door / activity 0..1, spin angle rad, barrel elevation 0..1).
func push_aux(recoil: float, deploy: float, spin_angle: float, elevation: float) -> void:
	var c: Vector4 = Vector4(recoil, deploy, spin_angle, elevation)
	if c == _last_aux:
		return
	_last_aux = c
	_write(P_AUX, c)
	writes += 1


## u_state: (damage 0..1, selected 0..1, ViewConsts.UF_* flags + cloak level, hit flash 0..1).
func push_state(damage: float, selected: float, flags: int, flash: float, cloak: float = 0.0) -> void:
	var c: Vector4 = Vector4(damage, selected, encode_flags(flags, cloak), flash)
	if c == _last_state:
		return
	_last_state = c
	_write(P_STATE, c)
	writes += 1


## u_mnt1..3 from 9 floats (yaw, elevation, recoil) x mounts 1..3.
func push_mounts(m: PackedFloat32Array) -> void:
	if m == _last_mnt:
		return
	_last_mnt = m.duplicate()
	var names: Array[StringName] = [P_MNT1, P_MNT2, P_MNT3]
	for i in 3:
		var o: int = i * 3
		if o + 2 < m.size():
			_write(names[i], Vector4(m[o], m[o + 1], m[o + 2], 0.0))
			writes += 1


## flags (int bits) and cloak level 0..1 packed into one float: exact integer part, cloak in the fraction.
static func encode_flags(flags: int, cloak: float) -> float:
	return float(flags) + clampf(cloak, 0.0, 1.0) * CLOAK_SCALE
