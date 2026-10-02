class_name ViewScaffolds
extends Node3D
## Scaffold cages of structures under construction or being sold (render spec 5.2 BUILDUP / SELLING, art_direction 5.9.6). One shared
## unit BoxMesh per cage, scaled to footprint x (height * ease(build)) and drawn by scaffold.gdshader (the lattice is procedural in
## metres). A pool of MAX_CAGES nodes, each with its own material duplicate for the team colour. Presentation only.

const MAX_CAGES: int = 24
const SHADER_PATH: String = "res://assets/shaders/scaffold.gdshader"
const INSET_M: float = 0.2  ## cage sits this far inside the footprint edge (on the plinth)
const TOP_MARGIN_M: float = 0.45

var count: int = 0  ## cages shown last update

var _v: ViewWorld = null
var _tracked: Array[ViewStructure] = []
var _pool: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _team: PackedInt32Array = PackedInt32Array()
var _mesh: BoxMesh = null
var _shader: Shader = null


func setup(v: ViewWorld) -> void:
	_v = v
	_mesh = BoxMesh.new()
	_mesh.size = Vector3.ONE
	_shader = load(SHADER_PATH) as Shader


func track(st: ViewStructure) -> void:
	if not _tracked.has(st):
		_tracked.append(st)


func untrack(st: ViewStructure) -> void:
	_tracked.erase(st)


func tracked_count() -> int:
	return _tracked.size()


func update(_dt: float) -> void:
	if _v == null:
		return
	var used: int = 0
	var i: int = 0
	while i < _tracked.size():
		var st: ViewStructure = _tracked[i]
		if st.phase == ViewConsts.PH_ACTIVE or st.active_idx < 0:
			_tracked.remove_at(i)
			continue
		i += 1
		if st.vs == ViewConsts.VS_HIDDEN or used >= MAX_CAGES or st.dead:
			continue
		_show(used, st)
		used += 1
	for j: int in range(used, _pool.size()):
		_pool[j].visible = false
	count = used


func _show(slot: int, st: ViewStructure) -> void:
	while _pool.size() <= slot:
		_add_node()
	var mi: MeshInstance3D = _pool[slot]
	if _team[slot] != st.team_index:
		_team[slot] = st.team_index
		_mats[slot].set_shader_parameter(&"team_color", ViewTeamColors.color(st.team_index))
	_mats[slot].set_shader_parameter(&"seed", float(st.id % 7))
	var ext: Vector2 = st.extent_m() - Vector2(INSET_M * 2.0, INSET_M * 2.0)
	var e: float = st.build * st.build * (3.0 - 2.0 * st.build)
	var ch: float = maxf(st.top_m() * e + TOP_MARGIN_M * minf(st.build * 4.0, 1.0), 0.35)
	var y0: float = _ground_min(st) - 0.05
	var height: float = ch + maxf(st.base_y() - y0, 0.0)
	var b: Basis = Basis.IDENTITY.scaled_local(Vector3(maxf(ext.x, 0.5), height, maxf(ext.y, 0.5)))
	mi.transform = Transform3D(b, Vector3(st.wx, y0 + height * 0.5, st.wz))
	mi.visible = true
	# the weld line glows while the cage is still growing or shrinking
	_mats[slot].set_shader_parameter(&"weld_glow", 1.0 if (st.build > 0.02 and st.build < 0.995) else 0.35)


func _ground_min(st: ViewStructure) -> float:
	var ext: Vector2 = st.extent_m() * 0.5
	var g: float = _v.ground_at(st.wx, st.wz)
	g = minf(g, _v.ground_at(st.wx - ext.x, st.wz - ext.y))
	g = minf(g, _v.ground_at(st.wx + ext.x, st.wz - ext.y))
	g = minf(g, _v.ground_at(st.wx - ext.x, st.wz + ext.y))
	g = minf(g, _v.ground_at(st.wx + ext.x, st.wz + ext.y))
	return g


func _add_node() -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _mesh
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = _shader
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.layers = ViewLayers.MASK_UNITS
	mi.visible = false
	mi.extra_cull_margin = 4.0
	add_child(mi)
	_pool.append(mi)
	_mats.append(m)
	_team.append(-99)
