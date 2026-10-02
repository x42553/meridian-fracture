extends RefCounted
## VIEW-M3 acceptance: ViewMaterials variants, caching, team colours, quality; ViewModelRig write caching; node backend pooling.

const Entity := preload("res://tests/fixtures/view_fixture_entity.gd")
const FixtureModel := preload("res://tests/fixtures/view_fixture_model.gd")

const V := ViewMaterials.Variant


func _mats() -> ViewMaterials:
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	var m: ViewMaterials = ViewMaterials.new()
	m.setup(null, q)
	return m


func teardown(_t: TestCtx) -> void:
	ViewTeamColors.set_mode(ViewTeamColors.MODE_NORMAL)


func test_one_material_per_style_variant_team(t: TestCtx) -> void:
	var m: ViewMaterials = _mats()
	var a: ShaderMaterial = m.unit_material(&"napc", V.NODE, 0)
	t.check(m.unit_material(&"napc", V.NODE, 0) == a, "same key -> same material")
	t.check(m.unit_material(&"napc", V.NODE, 1) != a, "another player colour -> another material")
	t.check(m.unit_material(&"nec", V.NODE, 0) != a, "another style -> another material")
	t.check(m.unit_material(&"napc", V.BATCH, 0) != a, "another variant -> another material")
	t.check(m.unit_material(&"napc", V.NODE, 0).shader == m.unit_material(&"nec", V.NODE, 3).shader, "one shader per variant")
	t.check(m.unit_material(&"napc", V.GHOST, 5) == m.unit_material(&"napc", V.GHOST, 2), "ghost material has no team")
	t.eq(m.material_count(), 6, "six cached materials")


func test_variant_sources(t: TestCtx) -> void:
	var m: ViewMaterials = _mats()
	t.check(m.shader(V.BATCH).code.begins_with("#define MM 1\n"), "MM variant source starts with #define MM 1")
	t.check(m.shader(V.MATERIAL_UNIFORMS).code.begins_with("#define MATU 1\n"), "MATU variant")
	t.check(m.shader(V.GHOST).code.begins_with("#define GHOST 1\n"), "GHOST variant")
	t.check(not m.shader(V.NODE).code.begins_with("#define"), "NODE variant is the plain source")
	var base: String = m.shader(V.NODE).code
	t.check(m.shader(V.BATCH).code.ends_with(base), "variants share one source")
	t.check(not RegEx.create_from_string("\\bTIME\\b").search(base) is RegExMatch, "unit shader has no TIME token")
	t.check(base.contains("#include \"res://assets/shaders/fog_of_war.gdshaderinc\""), "fog include")


func test_team_colour_is_a_material_uniform(t: TestCtx) -> void:
	var m: ViewMaterials = _mats()
	var mat: ShaderMaterial = m.unit_material(&"napc", V.NODE, 1)
	t.eq(mat.get_shader_parameter(&"team_color"), ViewTeamColors.color(1), "team_color = lobby colour 1")
	t.eq(m.unit_material(&"napc", V.NODE, -1).get_shader_parameter(&"team_color"), ViewTeamColors.NEUTRAL, "owner -1 = neutral")
	ViewTeamColors.set_mode(ViewTeamColors.MODE_DEUTAN)
	m.refresh_team_colors()
	t.eq(mat.get_shader_parameter(&"team_color"), ViewTeamColors.color(1), "refresh rewrites once")
	t.eq(mat.get_shader_parameter(&"team_color"), Color("E69F00"), "deutan id 1 = Okabe-Ito orange")


func test_set_quality_writes_all_cached(t: TestCtx) -> void:
	var m: ViewMaterials = _mats()
	var a: ShaderMaterial = m.unit_material(&"napc", V.NODE, 0)
	var b: ShaderMaterial = m.unit_material(&"def", V.BATCH, 2)
	t.near(a.get_shader_parameter(&"quality") as float, 1.0, 1.0e-6, "HIGH = quality 1")
	var low: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.LOW)
	m.set_quality(low)
	t.near(a.get_shader_parameter(&"quality") as float, 0.0, 1.0e-6, "LOW writes 0 to material a")
	t.near(b.get_shader_parameter(&"quality") as float, 0.0, 1.0e-6, "LOW writes 0 to material b")
	t.near(m.unit_material(&"new", V.NODE, 0).get_shader_parameter(&"quality") as float, 0.0, 1.0e-6, "new materials start at the current quality")


func test_style_parameters(t: TestCtx) -> void:
	var m: ViewMaterials = _mats()
	m.set_style(&"dusty", {"material": {"wear": 0.9, "dirt": 0.2, "panel": 0.1, "wear_color": "#ff0000", "emissive": 4.0}})
	var mat: ShaderMaterial = m.unit_material(&"dusty", V.NODE, 0)
	t.near(mat.get_shader_parameter(&"wear_amount") as float, 0.9, 1.0e-6, "wear")
	t.near(mat.get_shader_parameter(&"dirt_amount") as float, 0.2, 1.0e-6, "dirt")
	t.near(mat.get_shader_parameter(&"panel_amount") as float, 0.1, 1.0e-6, "panel")
	t.eq(mat.get_shader_parameter(&"wear_color"), Color(1, 0, 0), "wear colour")
	t.near(mat.get_shader_parameter(&"emissive_strength") as float, 4.0, 1.0e-6, "emissive")
	var dup: ShaderMaterial = m.new_entity_material(&"dusty", 0)
	t.check(dup != m.unit_material(&"dusty", V.MATERIAL_UNIFORMS, 0), "entity material is a duplicate")
	t.check(dup.shader == m.shader(V.MATERIAL_UNIFORMS), "sharing the MATU shader")


func test_rig_skips_identical_writes(t: TestCtx) -> void:
	var m: ViewMaterials = _mats()
	var rig: ViewModelRig = ViewModelRig.new()
	rig.setup(BoxMesh.new(), m.unit_material(&"napc", V.NODE, 0))
	var base: int = rig.writes
	rig.push_anim(0.0, 0.0, 0.0, 0.0)
	rig.push_aux(0.0, 0.0, 0.0, 0.0)
	rig.push_state(0.0, 0.0, 0, 0.0)
	t.eq(rig.writes, base, "rest values are already cached by setup()")
	rig.push_anim(0.0, 1.0, 2.5, 0.3)
	rig.push_anim(0.0, 1.0, 2.5, 0.3)
	t.eq(rig.writes, base + 1, "an identical push is skipped")
	rig.push_state(0.5, 1.0, ViewConsts.UF_CLOAKED, 0.0, 0.5)
	t.eq(rig.writes, base + 2, "state write")
	var enc: float = ViewModelRig.encode_flags(ViewConsts.UF_CLOAKED | ViewConsts.UF_EMP, 0.5)
	t.eq(int(floor(enc)), 48, "flags survive in the integer part")
	t.near(enc - floor(enc), 0.4995, 1.0e-4, "cloak level in the fraction")
	var mn: PackedFloat32Array = PackedFloat32Array([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9])
	rig.push_mounts(mn)
	var w: int = rig.writes
	rig.push_mounts(mn)
	t.eq(rig.writes, w, "identical mounts skipped")
	t.eq(rig.get_instance_shader_parameter(&"u_mnt2"), Vector4(0.4, 0.5, 0.6, 0.0), "mount 2 values")
	t.eq(rig.get_instance_shader_parameter(&"u_anim"), Vector4(0.0, 1.0, 2.5, 0.3), "anim written as Vector4 (Color values would be sRGB-converted)")
	rig.free()


func _model(key: StringName) -> Object:
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	b.box(Vector3.ZERO, Vector3.ONE)
	var mod: Object = FixtureModel.new()
	mod.mesh = b.build("m")
	mod.info = b.info()
	mod.key = key
	return mod


func test_node_backend_pools_rigs(t: TestCtx) -> void:
	var root: Node3D = Node3D.new()
	var mats: ViewMaterials = _mats()
	var be: ViewNodeBackend = ViewNodeBackend.new()
	be.setup(root, mats, ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH))
	var model: Object = _model(&"tank@napc")
	var a: Object = Entity.new()
	a.style_id = &"napc"
	a.team_index = 2
	be.add(a, model, &"napc", ViewTeamColors.color(2), 2)
	t.not_null(a.rig, "add() sets ve.rig")
	t.eq(root.get_child_count(), 1, "one rig node")
	var rig: ViewModelRig = a.rig as ViewModelRig
	t.check(rig.material_override == mats.unit_material(&"napc", V.NODE, 2), "material of (style, team)")
	a.turret_yaw = 0.5
	a.damage = 0.3
	a.flags = ViewConsts.UF_EMP
	be.push_anim(a)
	be.push_state(a)
	t.eq(rig.get_instance_shader_parameter(&"u_anim"), Vector4(0.0, 0.0, 0.0, 0.5), "u_anim from the entity")
	t.near((rig.get_instance_shader_parameter(&"u_state") as Vector4).x, 0.3, 1.0e-6, "damage in u_state.x")
	be.set_xform(a, Transform3D(Basis.IDENTITY, Vector3(3, 0, 4)))
	t.eq(rig.position, Vector3(3, 0, 4), "set_xform")
	be.set_team(a, ViewTeamColors.color(5), 5)
	t.check(rig.material_override == mats.unit_material(&"napc", V.NODE, 5), "set_team swaps the material")
	be.remove(a)
	t.check(a.rig == null and not rig.visible, "remove() parks and hides the rig")
	var b: Object = Entity.new()
	b.style_id = &"napc"
	be.add(b, model, &"napc", ViewTeamColors.color(0), 0)
	t.check(b.rig == rig, "the parked rig is reused")
	t.eq(be.stats()["reused"], 1, "reuse counted")
	t.eq(root.get_child_count(), 1, "no new node was created")
	t.eq(rig.get_instance_shader_parameter(&"u_anim"), Vector4(0.0, 0.0, 0.0, 0.0), "reuse resets the instance state")
	be.set_shadow(b, false)
	t.eq(rig.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "shadow off")
	root.free()


## Compatibility renderer: the GL uniform buffer holds 4096 instance-uniform items (6 per rig), so entities past ~680 got the engine error
## "Too many instances using shader instance variables" and lost their animation state. The node backend then gives every rig a private
## MATERIAL_UNIFORMS material and writes plain uniforms on it; no rig uses an instance uniform.
func test_compatibility_rigs_use_plain_uniforms_not_instance_uniforms(t: TestCtx) -> void:
	var root: Node3D = Node3D.new()
	var mats: ViewMaterials = _mats()
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.LOW, ViewQuality.Renderer.COMPATIBILITY)
	var be: ViewNodeBackend = ViewNodeBackend.new()
	be.setup(root, mats, q)
	t.check(be.plain, "the Compatibility renderer selects plain uniforms")
	var model: Object = _model(&"tank@napc")
	var a: Object = Entity.new()
	a.style_id = &"napc"
	a.team_index = 1
	be.add(a, model, &"napc", ViewTeamColors.color(1), 1)
	var b: Object = Entity.new()
	b.style_id = &"napc"
	b.team_index = 1
	be.add(b, model, &"napc", ViewTeamColors.color(1), 1)
	var ra: ViewModelRig = a.rig as ViewModelRig
	var rb: ViewModelRig = b.rig as ViewModelRig
	t.check(ra.material_override != rb.material_override, "every rig owns its material (the uniforms are per entity)")
	t.check(ra.plain and rb.plain, "rigs are in plain mode")
	a.turret_yaw = 0.5
	a.damage = 0.3
	be.push_anim(a)
	be.push_state(a)
	var ma: ShaderMaterial = ra.material_override as ShaderMaterial
	t.near((ma.get_shader_parameter(&"u_anim") as Vector4).w, 0.5, 1.0e-5, "turret yaw lands in the rig's own material")
	t.near((ma.get_shader_parameter(&"u_state") as Vector4).x, 0.3, 1.0e-5, "damage lands in the rig's own material")
	var mb: ShaderMaterial = rb.material_override as ShaderMaterial
	t.near((mb.get_shader_parameter(&"u_anim") as Vector4).w, 0.0, 1.0e-5, "the other rig is untouched")
	t.eq(ra.get_instance_shader_parameter(&"u_anim"), null, "and nothing is written as an instance uniform")
	be.set_team(a, ViewTeamColors.color(3), 3)
	var ma2: ShaderMaterial = ra.material_override as ShaderMaterial
	t.check(ma2 != ma, "a team change swaps the private material")
	t.near((ma2.get_shader_parameter(&"u_anim") as Vector4).w, 0.5, 1.0e-5, "and carries the animation state over")
	be.remove(a)
	be.remove(b)
	root.free()
