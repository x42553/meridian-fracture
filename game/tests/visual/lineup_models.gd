extends Node3D
## VIEW-M3 visual acceptance: the spike's sample models (tank in 4 faction styles, APC, howitzer, squads, gunship, boat,
## factory) rendered through the real API: ViewMeshBuilder -> ViewMaterials -> ViewNodeBackend / ViewModelRig.
## `tools/gd shot res://tests/visual/lineup_units.tscn out.png --size 1920x1080` (units), lineup_big.tscn (factory + boat),
## lineup_factions.tscn (four tank styles), lineup_rts.tscn (400 units at the RTS camera).

const Models := preload("res://tests/visual/lineup_sample_models.gd")
const Entity := preload("res://tests/fixtures/view_fixture_entity.gd")
const FixtureModel := preload("res://tests/fixtures/view_fixture_model.gd")

@export var layout: int = 0  ## 0 units, 1 big, 2 factions, 3 rts, 4 squads at hp 100 / 74 / 49 / 24 %, 5 = 400 mixed units, 6 = 5000 tanks (stats), 7 = state flags + GHOST / MATU variants, 8 = MM (MultiMesh) variant
@export var pose: String = "action"
@export var team_id: int = 1
@export var shadows: bool = true
@export var teams: int = 2  ## player colours used by the mix scenes
@export var squad_cam_dist: int = 12

var _mats: ViewMaterials = ViewMaterials.new()
var _backend: ViewNodeBackend = ViewNodeBackend.new()
var _models: Dictionary = {}
var _ents: Array = []
var _cam: Camera3D = null
var _ground_mat: ShaderMaterial = null
var _frame: int = 0


func _ready() -> void:
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	q.apply_to_viewport(get_viewport())
	_mats.setup(null, q)
	_backend.setup(self, _mats, q)
	_environment()
	_ground()
	match layout:
		0:
			_scene_units()
			_aim(Vector3(1.0, 1.2, -1.0), 30.0, 26.0, 0.0, 32.0)
		1:
			_scene_big()
			_aim(Vector3(2.0, 2.0, 0.0), 34.0, 26.0, -18.0, 36.0)
		2:
			for i in 4:
				var f: StringName = [&"napc", &"nec", &"def", &"han"][i]
				_place(&"tank", f, Vector3(-7.5 + 5.0 * float(i), 0.0, 0.0), 156.0)
			_aim(Vector3(0.0, 0.9, 0.0), 19.0, 24.0, 0.0, 34.0)
		4:
			for i in 4:
				var sq: Object = _place(&"infantry", &"napc", Vector3(-7.5 + 5.0 * float(i), 0.0, 0.0), 160.0, -1, "action")
				sq.damage = [0.0, 0.26, 0.51, 0.76][i]
				_push(sq)
			_aim(Vector3(0.0, 0.5, 0.0), float(squad_cam_dist), 28.0, 0.0, 34.0)
		8:
			_scene_mm()
			_aim(Vector3(0.0, 0.8, 0.5), 26.0, 32.0, 0.0, 34.0)
		7:
			_scene_flags()
			_aim(Vector3(0.0, 0.8, 0.5), 36.0, 32.0, 0.0, 34.0)
		5:
			_scene_mix(400)
			_aim(Vector3(0.0, 0.0, 0.0), 78.0, 55.0, 0.0, 40.0)
		6:
			_scene_mix(5000, true)
			_aim(Vector3(0.0, 0.0, 0.0), 150.0, 55.0, 0.0, 40.0)
		3:
			_scene_rts()
			var d: float = 45.0 / sin(deg_to_rad(55.0))
			_aim(Vector3(-4.0, 0.0, 2.0), d, 55.0, 0.0, 40.0)


func _mesh(id: StringName, faction: StringName) -> Object:
	var key: String = "%s:%s" % [id, faction]
	if not _models.has(key):
		var style: Dictionary = Models.tank_style(faction) if id == &"tank" else Models.palette(faction)
		var b: ViewMeshBuilder = Models.make_builder(id, style)
		b.compat_layout = ViewQuality.detect_renderer() == ViewQuality.Renderer.COMPATIBILITY
		var m: Object = FixtureModel.new()
		m.mesh = b.build(String(id))
		m.info = b.info()
		m.key = StringName(key)
		_models[key] = m
	return _models[key] as Object


func _place(id: StringName, faction: StringName, pos: Vector3, yaw_deg: float, team: int = -1, ent_pose: String = "") -> Object:
	var e: Object = Entity.new()
	e.style_id = faction
	e.team_index = team_id if team < 0 else team
	var model: Object = _mesh(id, faction)
	_backend.add(e, model, faction, ViewTeamColors.color(e.team_index), e.team_index)
	var hover: float = float(Models.info(id)["hover"])
	e.rig.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos + Vector3(0.0, hover, 0.0))
	var p: String = pose if ent_pose.is_empty() else ent_pose
	if p == "action":
		match id:
			&"tank":
				e.turret_yaw = deg_to_rad(-22.0)
				e.recoil = 0.55
			&"apc":
				e.turret_yaw = deg_to_rad(35.0)
			&"howitzer":
				e.deploy = 1.0
				e.elevation = 1.0
				e.turret_yaw = deg_to_rad(18.0)
				e.recoil = 0.3
			&"infantry":
				e.move01 = 1.0
				e.roll_m = 0.37 + pos.x * 0.05
			&"gunship":
				e.spin_angle = 1.7
				e.turret_yaw = deg_to_rad(25.0)
			&"boat":
				e.spin_angle = 1.1
				e.turret_yaw = deg_to_rad(-30.0)
			&"factory":
				e.deploy = 1.0
	elif id == &"gunship":
		e.spin_angle = 1.7
	_push(e)
	_ents.append(e)
	return e


func _push(e: Object) -> void:
	_backend.push_anim(e)
	_backend.push_aux(e)
	_backend.push_state(e)


func _scene_units() -> void:
	var yaw: float = 158.0
	_place(&"tank", &"napc", Vector3(-9.0, 0.0, 3.0), yaw)
	var t2: Object = _place(&"tank", &"napc", Vector3(-2.5, 0.0, 3.0), yaw + 12.0)
	t2.damage = 0.75
	_push(t2)
	var a: Object = _place(&"apc", &"napc", Vector3(4.0, 0.0, 3.0), yaw)
	a.selected = 1.0
	_push(a)
	_place(&"howitzer", &"napc", Vector3(11.5, 0.0, 3.0), yaw - 10.0)
	_place(&"infantry", &"napc", Vector3(-6.0, 0.0, -5.5), yaw)
	_place(&"gunship", &"napc", Vector3(2.0, 0.0, -6.0), yaw - 25.0)
	var sq: Object = _place(&"infantry", &"napc", Vector3(9.0, 0.0, -5.0), yaw + 20.0, -1, "rest")
	sq.damage = 0.4  # hp 60 %: the last soldier falls
	_push(sq)


## State flags of unit.gdshader (cloak, EMP, wreck, ghost, submerged, decoy, unpowered, selected) plus the GHOST and MATU variants.
func _scene_flags() -> void:
	var flags: Array = [[0, 0.0], [ViewConsts.UF_CLOAKED, 0.5], [ViewConsts.UF_CLOAKED, 1.0], [ViewConsts.UF_EMP, 0.0],
		[ViewConsts.UF_WRECK, 0.0], [ViewConsts.UF_GHOST, 0.0], [ViewConsts.UF_SUBMERGED, 0.0], [ViewConsts.UF_DECOY_ID, 0.0]]
	for i in flags.size():
		var e: Object = _place(&"tank", &"napc", Vector3(-15.75 + 4.5 * float(i), 0.0, 4.0), 160.0, -1, "rest")
		e.flags = (flags[i] as Array)[0] as int
		e.cloak = (flags[i] as Array)[1] as float
		if i == 4:
			e.damage = 1.0
		_push(e)
	var f: Object = _place(&"factory", &"napc", Vector3(-9.0, 0.0, -6.0), 180.0, -1, "rest")
	f.flags = ViewConsts.UF_UNPOWERED
	_push(f)
	var a: Object = _place(&"apc", &"napc", Vector3(-1.0, 0.0, -5.0), 160.0, -1, "rest")
	a.selected = 1.0
	a.flash = 0.6
	_push(a)
	# GHOST variant (placement ghost) and MATU variant (plain uniforms on a per-entity material)
	var model: Object = _mesh(&"tank", &"napc")
	var g: MeshInstance3D = MeshInstance3D.new()
	g.mesh = model.mesh
	var gm: ShaderMaterial = _mats.unit_material(&"napc", ViewMaterials.Variant.GHOST)
	gm.set_shader_parameter(&"ghost_tint", Color(0.3, 1.0, 0.4))
	g.material_override = gm
	g.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(160.0)), Vector3(6.0, 0.0, -5.0))
	add_child(g)
	var g2: MeshInstance3D = MeshInstance3D.new()
	g2.mesh = model.mesh
	var gm2: ShaderMaterial = _mats.unit_material(&"def", ViewMaterials.Variant.GHOST)
	gm2.set_shader_parameter(&"ghost_tint", Color(1.0, 0.25, 0.2))
	g2.material_override = gm2
	g2.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(160.0)), Vector3(11.0, 0.0, -5.0))
	add_child(g2)
	var mu: MeshInstance3D = MeshInstance3D.new()
	mu.mesh = model.mesh
	var mm: ShaderMaterial = _mats.new_entity_material(&"napc", 1)
	mm.set_shader_parameter(&"u_anim", Vector4(0.0, 0.0, 0.0, deg_to_rad(-40.0)))
	mm.set_shader_parameter(&"u_state", Vector4(0.5, 0.0, 0.0, 0.0))
	mu.material_override = mm
	mu.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(160.0)), Vector3(16.0, 0.0, -5.0))
	add_child(mu)


## The MM variant (batch backend look): MultiMesh with colour + custom data (roll, turret yaw, recoil, damage) per instance.
func _scene_mm() -> void:
	for kind in 2:
		var id: StringName = [&"tank", &"infantry"][kind]
		var model: Object = _mesh(id, &"napc")
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = model.mesh
		mm.instance_count = 4
		for i in 4:
			var xf: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(160.0)), Vector3(-8.0 + 5.0 * float(i), 0.0, 3.0 - 8.0 * float(kind)))
			mm.set_instance_transform(i, xf)
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, Color(0.37 * float(i), deg_to_rad(-20.0 * float(i)), 0.5 * float(i % 2), 0.25 * float(i)))
		var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mats.unit_material(&"napc", ViewMaterials.Variant.BATCH, 1)
		add_child(mi)


func _scene_big() -> void:
	_place(&"factory", &"napc", Vector3(0.0, 0.0, -4.0), 180.0)
	_place(&"tank", &"napc", Vector3(-9.0, 0.0, 6.0), -30.0)
	_place(&"infantry", &"napc", Vector3(-4.0, 0.0, 6.5), -30.0)
	var w: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(16.0, 14.0)
	w.mesh = pm
	var wm: ShaderMaterial = ShaderMaterial.new()
	wm.shader = _ground_mat.shader
	wm.set_shader_parameter(&"water_mix", 1.0)
	w.material_override = wm
	w.position = Vector3(15.0, 0.02, 2.0)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)
	_place(&"boat", &"napc", Vector3(14.0, 0.0, 3.0), -50.0)


func _scene_rts() -> void:
	var yaw: float = -30.0
	for r in 2:
		for c in 3:
			_place(&"tank", &"napc", Vector3(-14.0 + 3.7 * float(c), 0.0, -2.0 + 3.6 * float(r)), yaw + float(c) * 4.0, -1, "rest")
	for c in 3:
		_place(&"apc", &"napc", Vector3(-14.0 + 3.7 * float(c), 0.0, 6.6), yaw, -1, "rest")
	_place(&"howitzer", &"napc", Vector3(-20.5, 0.0, -1.0), yaw, -1, "rest")
	for i in 5:
		_place(&"infantry", &"napc", Vector3(-2.5 + 1.6 * float(i % 3), 0.0, -3.0 + 3.0 * float(i / 3)), yaw + 15.0 * float(i), -1, "rest")
	_place(&"gunship", &"napc", Vector3(-12.0, 0.0, -9.0), yaw, -1, "rest")
	_place(&"factory", &"napc", Vector3(-26.0, 0.0, -14.0), 180.0, -1, "rest")
	var enemy: Array[StringName] = [&"def", &"nec", &"han"]
	for r in 3:
		for c in 3:
			_place(&"tank", enemy[r], Vector3(9.0 + 3.7 * float(c), 0.0, -5.0 + 4.0 * float(r)), 150.0 + float(c) * 5.0, 0, "rest")


## The spike's 400-unit mix (130 tank, 60 APC, 50 howitzer, 100 squads, 30 gunships, 20 boats, 10 factories) on a jittered grid;
## `tanks_only` fills `n` with tanks (instance-uniform capacity test).
func _scene_mix(n: int, tanks_only: bool = false) -> void:
	var kinds: Array[StringName] = []
	if tanks_only:
		for i in n:
			kinds.append(&"tank")
	else:
		var mix: Array = [[&"tank", 130], [&"apc", 60], [&"howitzer", 50], [&"infantry", 100], [&"gunship", 30], [&"boat", 20], [&"factory", 10]]
		for e: Array in mix:
			for i in e[1] as int:
				kinds.append(e[0] as StringName)
	var side: int = int(ceil(sqrt(float(n))))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var gx: int = i % side
		var gz: int = i / side
		var step: float = 8.0 if not tanks_only else 4.5
		var pos: Vector3 = Vector3((float(gx) - float(side) * 0.5) * step, 0.0, (float(gz) - float(side) * 0.5) * step)
		_place(kinds[(i * 37) % kinds.size()], &"napc", pos, rng.randf() * 360.0, i % teams, "rest")


func _process(_dt: float) -> void:
	_frame += 1
	if _frame == 20 and layout >= 5:
		var info: String = "STATS layout=%d entities=%d draws=%d objects=%d prims=%d rig_writes=%d" % [layout, _ents.size(),
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)), 0]
		print(info)


func _aim(target: Vector3, dist: float, pitch_deg: float, yaw_deg: float, fov: float) -> void:
	var p: float = deg_to_rad(pitch_deg)
	var y: float = deg_to_rad(yaw_deg)
	var dir: Vector3 = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam = Camera3D.new()
	_cam.fov = fov
	_cam.near = 0.5
	_cam.far = 500.0
	add_child(_cam)
	_cam.position = target + dir * dist
	_cam.look_at(target, Vector3.UP)
	_cam.current = true


func _environment() -> void:
	var e: Environment = Environment.new()
	var sm: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.44, 0.70)
	sm.sky_horizon_color = Color(0.80, 0.82, 0.84)
	sm.ground_horizon_color = Color(0.66, 0.63, 0.58)
	sm.ground_bottom_color = Color(0.30, 0.28, 0.25)
	var sky: Sky = Sky.new()
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 1.0
	e.ssao_intensity = 2.0
	e.ssao_power = 1.6
	e.ssao_light_affect = 0.25
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.05
	e.adjustment_contrast = 1.12
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = e
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.9
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.light_angular_distance = 0.6
	add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30.0, 140.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.55, 0.70, 1.0)
	add_child(fill)


func _ground() -> void:
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://tests/visual/lineup_ground.gdshader") as Shader
	var g: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(400.0, 400.0)
	g.mesh = pm
	g.material_override = _ground_mat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
