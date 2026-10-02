class_name DemoWorld
extends Node3D
## Procedural 3D backdrop: a heightmap battlefield with a base, armies, water and props (HUD mock-ups,
## minimap source) or a cinematic "hero" desert scene (main-menu background). View-only; floats are fine here.

const HALF := 96.0
enum Mode { BATTLEFIELD, HERO }

var mode: Mode = Mode.BATTLEFIELD
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
## Every visible thing: {kind, team, pos: Vector3, hp: float, selected: bool, radius: float, struct: bool, node: Node3D, vel: Vector3}
var entities: Array[Dictionary] = []
var focus: Vector3 = Vector3(8.0, 0.0, -2.0)
var yaw_deg: float = 32.0
var pitch_deg: float = -50.0
var distance: float = 62.0
var fov_deg: float = 42.0
var _noise := FastNoiseLite.new()
var _lcg: int = 1234567
var _rich: bool = true

func build(m: Mode, own: Color, enemy: Color) -> void:
	setup_noise(m)
	_rich = RenderingServer.get_current_rendering_method() == "forward_plus"
	_add_environment()
	_add_terrain()
	if m == Mode.BATTLEFIELD:
		_add_water()
		_scatter_props()
		_populate_battlefield(own, enemy)
	else:
		_populate_hero(own)
	camera = Camera3D.new()
	camera.fov = fov_deg
	camera.near = 0.5
	camera.far = 900.0
	if mode == Mode.HERO:
		camera.h_offset = -3.4
		camera.v_offset = -0.6
	add_child(camera)
	apply_camera()

func setup_noise(m: Mode) -> void:
	mode = m
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.028
	_noise.fractal_octaves = 4
	_noise.seed = 11 if m == Mode.BATTLEFIELD else 5

## Terrain preview image without building any 3D nodes (skirmish setup / lobby map cards).
static func preview_image(m: Mode, px: int) -> Image:
	var w := DemoWorld.new()
	w.setup_noise(m)
	var img: Image = w.minimap_image(px)
	w.free()
	return img

func apply_camera() -> void:
	var el: float = deg_to_rad(-pitch_deg)
	var yaw: float = deg_to_rad(yaw_deg)
	var off := Vector3(sin(yaw) * cos(el), sin(el), cos(yaw) * cos(el)) * distance
	camera.look_at_from_position(focus + off, focus, Vector3.UP)

func _rand() -> float:
	_lcg = (_lcg * 1103515245 + 12345) & 0x7fffffff
	return float(_lcg) / float(0x7fffffff)

# --- terrain -------------------------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	if mode == Mode.HERO:
		return _noise.get_noise_2d(x * 1.2, z * 1.2) * 9.0 + _noise.get_noise_2d(x * 4.0 + 30.0, z * 4.0) * 1.0 - 1.0
	var h: float = _noise.get_noise_2d(x, z) * 6.0 + 3.0 + _noise.get_noise_2d(x * 3.0 + 50.0, z * 3.0) * 0.8
	var d: float = Vector2(x + 6.0, z + 4.0).length()
	h = lerpf(0.35, h, smoothstep(24.0, 46.0, d))
	var dl: float = Vector2(x - 66.0, z - 60.0).length()
	h -= (1.0 - smoothstep(6.0, 36.0, dl)) * 10.0
	return h

func _terrain_color(x: float, z: float, h: float, slope: float) -> Color:
	var n: float = _noise.get_noise_2d(x * 3.3 + 200.0, z * 3.3) * 0.5 + 0.5
	if mode == Mode.HERO:
		var c: Color = Color(0.55, 0.42, 0.28).lerp(Color(0.68, 0.53, 0.36), n)
		return c.lerp(Color(0.32, 0.27, 0.22), smoothstep(0.25, 0.7, slope))
	var c2: Color = Color(0.17, 0.27, 0.10).lerp(Color(0.36, 0.33, 0.16), clampf(n * 1.5 - 0.4, 0.0, 1.0))
	c2 = c2.lerp(Color(0.60, 0.54, 0.38), 1.0 - smoothstep(-1.2, 0.5, h))
	c2 = c2.lerp(Color(0.34, 0.33, 0.31), smoothstep(0.3, 0.75, slope))
	var d: float = Vector2(x + 6.0, z + 4.0).length()
	return c2.lerp(Color(0.27, 0.28, 0.27), (1.0 - smoothstep(12.0, 26.0, d)) * 0.75)

func _add_terrain() -> void:
	var res: int = 120
	var step: float = 2.0 * HALF / float(res)
	var hs := PackedFloat32Array()
	hs.resize((res + 1) * (res + 1))
	for iz in res + 1:
		for ix in res + 1:
			hs[iz * (res + 1) + ix] = height_at(-HALF + ix * step, -HALF + iz * step)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for iz in res + 1:
		for ix in res + 1:
			var x: float = -HALF + ix * step
			var z: float = -HALF + iz * step
			var h: float = hs[iz * (res + 1) + ix]
			var hl: float = hs[iz * (res + 1) + maxi(ix - 1, 0)]
			var hr: float = hs[iz * (res + 1) + mini(ix + 1, res)]
			var hu: float = hs[maxi(iz - 1, 0) * (res + 1) + ix]
			var hd: float = hs[mini(iz + 1, res) * (res + 1) + ix]
			var n := Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
			verts.append(Vector3(x, h, z))
			norms.append(n)
			cols.append(_terrain_color(x, z, h, 1.0 - n.y))
			uvs.append(Vector2(x, z) / 6.0)
	for iz in res:
		for ix in res:
			var a: int = iz * (res + 1) + ix
			idx.append_array([a, a + 1, a + res + 1, a + 1, a + res + 2, a + res + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _detail_texture()
	mat.roughness = 0.96
	mat.metallic_specular = 0.15
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "Terrain"
	add_child(mi)

func _detail_texture() -> ImageTexture:
	var n: int = 128
	var nz := FastNoiseLite.new()
	nz.frequency = 0.09
	nz.fractal_octaves = 3
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var v: float = 0.78 + nz.get_noise_2d(x, y) * 0.22 + nz.get_noise_2d(x * 4.0, y * 4.0) * 0.06
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _add_water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0 * HALF, 2.0 * HALF)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.26, 0.32, 0.82)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06
	m.metallic = 0.35
	mi.material_override = m
	mi.position = Vector3(0.0, -0.9, 0.0)
	mi.name = "Water"
	add_child(mi)

func _scatter_props() -> void:
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 1.4
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.38, 0.37, 0.35)
	rock_mat.roughness = 0.95
	var tree_mesh := CylinderMesh.new()
	tree_mesh.top_radius = 0.0
	tree_mesh.bottom_radius = 0.9
	tree_mesh.height = 3.6
	tree_mesh.radial_segments = 7
	tree_mesh.rings = 1
	var tree_mat := StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.08, 0.17, 0.08)
	tree_mat.roughness = 0.9
	for spec in [[rock_mesh, rock_mat, 70, 0.0], [tree_mesh, tree_mat, 140, 2.7]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[0]
		var count: int = spec[2]
		var lift: float = spec[3]
		mm.instance_count = count
		for i in count:
			var x: float = (_rand() * 2.0 - 1.0) * (HALF - 4.0)
			var z: float = (_rand() * 2.0 - 1.0) * (HALF - 4.0)
			var d: float = Vector2(x + 6.0, z + 4.0).length()
			if d < 34.0 or height_at(x, z) < -0.5:
				x += 80.0 * (1.0 if x < 0.0 else -1.0)
				x = clampf(x, -HALF + 4.0, HALF - 4.0)
			var h: float = height_at(x, z)
			var s: float = 0.5 + _rand() * 1.2
			var b := Basis.from_euler(Vector3(0.0, _rand() * TAU, 0.0)).scaled(Vector3(s, s * (1.0 if lift == 0.0 else 1.4), s))
			mm.set_instance_transform(i, Transform3D(b, Vector3(x, h + lift * s * 0.5 * (1.4 if lift > 0.0 else 0.2), z)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = spec[1]
		add_child(mmi)

# --- lighting ------------------------------------------------------------------------------------------------------

func _add_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	var hero: bool = mode == Mode.HERO
	sky_mat.sky_top_color = Color(0.10, 0.17, 0.32) if hero else Color(0.24, 0.42, 0.68)
	sky_mat.sky_horizon_color = Color(0.95, 0.55, 0.32) if hero else Color(0.72, 0.78, 0.84)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.2, 0.17, 0.15) if hero else Color(0.35, 0.38, 0.36)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.50, 0.50, 0.50) if not hero else Color(0.40, 0.33, 0.30)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.75 if not hero else 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05 if not hero else 0.12
	env.fog_enabled = true
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_density = 0.0016 if not hero else 0.0038
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06
	if _rich:
		env.ssao_enabled = true
		env.ssao_radius = 1.6
		env.ssao_intensity = 1.4
		if hero:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.012
			env.volumetric_fog_albedo = Color(1.0, 0.7, 0.45)
			env.volumetric_fog_length = 90.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0) if not hero else Vector3(-9.0, -62.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86) if not hero else Color(1.0, 0.62, 0.34)
	sun.light_energy = 1.9 if not hero else 2.4
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 130.0
	sun.shadow_bias = 0.04
	add_child(sun)
	if hero:
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-18.0, 150.0, 0.0)
		rim.light_color = Color(0.45, 0.62, 1.0)
		rim.light_energy = 1.4
		rim.shadow_enabled = false
		add_child(rim)

# --- population ------------------------------------------------------------------------------------------------------

func add_entity(kind: String, team: int, pos: Vector2, color: Color, yaw: float = 0.0, hp: float = 1.0, is_struct: bool = false, radius: float = 1.6) -> Dictionary:
	var node: Node3D = DemoModels.build(kind, color)
	var p := Vector3(pos.x, maxf(height_at(pos.x, pos.y), -0.2 if kind in ["boat", "frigate", "arsenal", "barge"] else -9.0), pos.y)
	if kind in ["boat", "frigate", "arsenal", "barge"]:
		p.y = -0.85
	if kind in ["jet", "gunship", "bomber"]:
		p.y += 6.0
	node.position = p
	node.rotation.y = yaw
	add_child(node)
	var e: Dictionary = {"kind": kind, "team": team, "pos": p, "hp": hp, "selected": false, "radius": radius, "struct": is_struct, "node": node, "vel": Vector3.ZERO}
	entities.append(e)
	return e

func _populate_battlefield(own: Color, enemy: Color) -> void:
	var b := Vector2(-6.0, -4.0)
	add_entity("headquarters", 0, b, own, 0.0, 1.0, true, 5.5)
	add_entity("generator", 0, b + Vector2(-16.0, -6.0), own, 0.0, 1.0, true, 3.6)
	add_entity("generator", 0, b + Vector2(-16.0, 5.0), own, 0.0, 0.7, true, 3.6)
	add_entity("refinery", 0, b + Vector2(-2.0, 15.0), own, PI * 0.5, 1.0, true, 4.6)
	add_entity("barracks", 0, b + Vector2(15.0, 12.0), own, PI * 0.5, 1.0, true, 4.6)
	add_entity("factory", 0, b + Vector2(18.0, -8.0), own, PI * 0.5, 1.0, true, 6.0)
	add_entity("radar", 0, b + Vector2(-2.0, -17.0), own, 0.0, 1.0, true, 3.6)
	add_entity("tower", 0, b + Vector2(28.0, 3.0), own, 0.0, 0.85, true, 2.0)
	add_entity("turret", 0, b + Vector2(30.0, -14.0), own, PI * 0.5, 1.0, true, 2.2)
	add_entity("aa_battery", 0, b + Vector2(26.0, 16.0), own, PI * 0.5, 1.0, true, 2.2)
	var kinds: Array[String] = ["tank_medium", "tank_medium", "tank_heavy", "tank_medium", "apc", "tank_medium", "artillery", "aa", "tank_medium", "tank_light", "recon", "tank_medium"]
	for i in kinds.size():
		var col: int = i % 4
		var row: int = i / 4
		var p := Vector2(30.0 + col * 5.2, -2.0 + row * 6.0 + (col % 2) * 1.2)
		var e: Dictionary = add_entity(kinds[i], 0, p, own, -PI * 0.5 + 0.06 * float(col), 1.0 - 0.09 * float(i % 5), false, 2.0)
		e["selected"] = i < 8
	add_entity("collector", 0, b + Vector2(8.0, 24.0), own, 0.6, 0.9, false, 2.4)
	add_entity("collector", 0, b + Vector2(-9.0, 24.0), own, -0.4, 1.0, false, 2.4)
	for i in 3:
		add_entity("infantry", 0, Vector2(20.0 + float(i) * 3.4, 11.0 + float(i) * 1.6), own, PI * 0.6, 0.6 + 0.2 * float(i), false, 1.4)
	add_entity("gunship", 0, Vector2(38.0, -18.0), own, -PI * 0.5, 1.0, false, 3.0)
	# enemy skirmish line
	var ek: Array[String] = ["tank_medium", "tank_heavy", "tank_medium", "artillery", "tank_light", "apc", "tank_medium"]
	for i in ek.size():
		add_entity(ek[i], 1, Vector2(66.0 + float(i % 3) * 5.5, -24.0 + float(i / 3) * 6.5), enemy, PI * 0.5, 0.35 + 0.1 * float(i % 4), false, 2.0)
	add_entity("turret", 1, Vector2(76.0, -6.0), enemy, PI * 0.5, 0.6, true, 2.2)
	add_entity("barracks", 1, Vector2(84.0, -26.0), enemy, PI, 1.0, true, 4.6)
	add_entity("boat", 2, Vector2(60.0, 52.0), Color("#33a0ec"), 0.7, 1.0, false, 3.0)
	add_entity("frigate", 2, Vector2(70.0, 66.0), Color("#33a0ec"), 0.3, 0.8, false, 4.5)
	focus = Vector3(28.0, 0.0, -2.0)

func _populate_hero(col: Color) -> void:
	yaw_deg = 24.0
	pitch_deg = -9.0
	distance = 21.0
	fov_deg = 36.0
	focus = Vector3(0.0, 2.2, 0.0)
	var hero: Dictionary = add_entity("tank_heavy", 0, Vector2(0.0, 0.0), col, -0.55, 1.0, false, 3.0)
	(hero["node"] as Node3D).scale = Vector3.ONE * 2.0
	for i in 5:
		add_entity("tank_medium", 0, Vector2(-24.0 - float(i) * 9.0, -22.0 - float(i) * 7.5), col, -0.4, 1.0, false, 2.0)
	add_entity("factory", 0, Vector2(-38.0, -34.0), col, 0.4, 1.0, true, 6.0)
	add_entity("radar", 0, Vector2(-14.0, -46.0), col, 0.0, 1.0, true, 3.0)
	add_entity("superweapon", 0, Vector2(-62.0, -50.0), col, 0.0, 1.0, true, 5.0)
	add_entity("gunship", 0, Vector2(-8.0, -20.0), col, 0.5, 1.0, false, 3.0)
	add_entity("jet", 0, Vector2(-30.0, -12.0), col, 0.3, 1.0, false, 3.0)
	var dust := CPUParticles3D.new()
	dust.amount = 240
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(40.0, 5.0, 40.0)
	dust.direction = Vector3(1.0, 0.15, 0.4)
	dust.spread = 25.0
	dust.initial_velocity_min = 1.2
	dust.initial_velocity_max = 3.4
	dust.gravity = Vector3.ZERO
	dust.scale_amount_min = 0.05
	dust.scale_amount_max = 0.16
	var qm := SphereMesh.new()
	qm.radius = 0.5
	qm.height = 1.0
	qm.radial_segments = 6
	qm.rings = 3
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.72, 0.42, 0.55)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust.mesh = qm
	dust.material_override = dm
	dust.position = Vector3(0.0, 4.0, 0.0)
	add_child(dust)

# --- queries for 2D overlays ---------------------------------------------------------------------------------------------

## Ground (y = 0) hit of a screen position, or null when the ray misses (sky).
func ground_point(screen: Vector2) -> Variant:
	var o: Vector3 = camera.project_ray_origin(screen)
	var d: Vector3 = camera.project_ray_normal(screen)
	return Plane(Vector3.UP, 0.0).intersects_ray(o, d)

## World-xz polygon of the camera's ground footprint (screen corners projected to y = 0).
func frustum_polygon(view_size: Vector2) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for c in [Vector2(0.0, 0.0), Vector2(view_size.x, 0.0), view_size, Vector2(0.0, view_size.y)]:
		var hit: Variant = ground_point(c)
		if hit == null:
			hit = ground_point(Vector2(c.x, view_size.y * 0.3))
		var v: Vector3 = hit if hit != null else focus
		poly.append(Vector2(v.x, v.z))
	return poly

## Top-down colour image of the terrain for the minimap (lit from the north-west so hills read).
func minimap_image(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var step: float = 2.0 * HALF / float(size)
	for py in size:
		for px in size:
			var x: float = -HALF + (px + 0.5) * step
			var z: float = -HALF + (py + 0.5) * step
			var h: float = height_at(x, z)
			if h < -0.9:
				var depth: float = clampf((-0.9 - h) / 6.0, 0.0, 1.0)
				img.set_pixel(px, py, Color(0.10, 0.36, 0.50).lerp(Color(0.04, 0.16, 0.28), depth))
				continue
			var dx: float = height_at(x + 1.5, z) - height_at(x - 1.5, z)
			var dz: float = height_at(x, z + 1.5) - height_at(x, z - 1.5)
			var c: Color = _terrain_color(x, z, h, absf(dx) + absf(dz))
			var lit: float = clampf(0.85 + (-dx - dz) * 0.09, 0.55, 1.25)
			img.set_pixel(px, py, Color(minf(c.r * lit * 1.55, 1.0), minf(c.g * lit * 1.55, 1.0), minf(c.b * lit * 1.5, 1.0), 1.0))
	return img

func world_to_norm(p: Vector3) -> Vector2:
	return Vector2((p.x + HALF) / (2.0 * HALF), (p.z + HALF) / (2.0 * HALF))

func norm_to_world(n: Vector2) -> Vector2:
	return Vector2(n.x * 2.0 * HALF - HALF, n.y * 2.0 * HALF - HALF)
