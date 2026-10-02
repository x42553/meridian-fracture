class_name UiFixtureBattlefield
extends Node3D
## Procedural stand-in battlefield of the FIXTURE view adapter (ui.md 2.5 / task UI-04b): a noise-shaded terrain grid,
## dusk lighting and MultiMesh primitives for entities (boxes for hulls / turrets / buildings, capsules for infantry,
## blob shadows). Lifted from the spike's `DemoWorld`; view-only, floats are fine. Not the production view.

enum Shape { INFANTRY = 0, VEHICLE = 1, AIR = 2, STRUCTURE = 3, WRECK = 4, NAVAL = 5 }

const CELL_M: float = 3.0
const GRID_STEP_CELLS: int = 2  ## terrain vertex spacing in cells

var amp: float = 0.0  ## terrain amplitude in metres (0 = flat)
var map_w_m: float = 384.0
var map_h_m: float = 384.0
var camera: Camera3D = null
var render: bool = true

var _noise: FastNoiseLite = FastNoiseLite.new()
var _boxes: MultiMesh = null
var _caps: MultiMesh = null
var _shadows: MultiMesh = null
var _box_buf: PackedFloat32Array = PackedFloat32Array()
var _cap_buf: PackedFloat32Array = PackedFloat32Array()
var _sh_buf: PackedFloat32Array = PackedFloat32Array()
var _nb: int = 0
var _nc: int = 0
var _ns: int = 0


## Builds terrain, light and camera for a `cells_w` x `cells_h` map. `render` false keeps only the height function and camera.
func build(cells_w: int, cells_h: int, p_amp: float, p_render: bool = true) -> void:
	amp = p_amp
	render = p_render
	map_w_m = float(cells_w) * CELL_M
	map_h_m = float(cells_h) * CELL_M
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.018
	_noise.fractal_octaves = 4
	_noise.seed = 11
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.5
	camera.far = 1200.0
	add_child(camera)
	if not render:
		return
	_add_environment()
	_add_terrain()
	_boxes = _make_multimesh(BoxMesh.new()).multimesh
	_caps = _make_multimesh(CapsuleMesh.new()).multimesh
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var sh: MultiMeshInstance3D = _make_multimesh(quad)
	_shadows = sh.multimesh
	var sm: StandardMaterial3D = sh.material_override as StandardMaterial3D
	sm.albedo_texture = _blob_texture()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func height_at(x: float, z: float) -> float:
	if amp <= 0.0:
		return 0.0
	var h: float = _noise.get_noise_2d(x, z) * amp + _noise.get_noise_2d(x * 3.0 + 50.0, z * 3.0) * amp * 0.12
	var edge: float = minf(minf(x, map_w_m - x), minf(z, map_h_m - z))
	return h * smoothstep(0.0, 18.0, edge) + amp * 0.5


# ---- scene ------------------------------------------------------------------------------------------------------------
func _add_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.19, 0.27, 0.42)
	sky_mat.sky_horizon_color = Color(0.72, 0.62, 0.52)
	sky_mat.ground_horizon_color = Color(0.55, 0.5, 0.44)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_white = 6.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 220.0
	sun.rotation_degrees = Vector3(-38.0, 38.0, 0.0)
	add_child(sun)


func _add_terrain() -> void:
	var step: float = CELL_M * float(GRID_STEP_CELLS)
	var nx: int = int(ceil(map_w_m / step))
	var nz: int = int(ceil(map_h_m / step))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize((nx + 1) * (nz + 1))
	norms.resize(verts.size())
	cols.resize(verts.size())
	for iz: int in nz + 1:
		for ix: int in nx + 1:
			var x: float = minf(float(ix) * step, map_w_m)
			var z: float = minf(float(iz) * step, map_h_m)
			var h: float = height_at(x, z)
			var dx: float = height_at(x + 1.0, z) - height_at(x - 1.0, z)
			var dz: float = height_at(x, z + 1.0) - height_at(x, z - 1.0)
			var n: Vector3 = Vector3(-dx, 2.0, -dz).normalized()
			var i: int = iz * (nx + 1) + ix
			verts[i] = Vector3(x, h, z)
			norms[i] = n
			cols[i] = _ground_color(x, z, 1.0 - n.y)
	for iz: int in nz:
		for ix: int in nx:
			var a: int = iz * (nx + 1) + ix
			var b: int = a + 1
			var c: int = a + nx + 1
			var d: int = c + 1
			idx.append_array([a, b, c, b, d, c])  # clockwise seen from above (Godot's front face)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Terrain"
	add_child(mi)


func _ground_color(x: float, z: float, slope: float) -> Color:
	var n: float = _noise.get_noise_2d(x * 2.6 + 200.0, z * 2.6) * 0.5 + 0.5
	var c: Color = Color(0.15, 0.22, 0.10).lerp(Color(0.30, 0.28, 0.15), clampf(n * 1.5 - 0.35, 0.0, 1.0))
	c = c.lerp(Color(0.36, 0.35, 0.33), smoothstep(0.05, 0.3, slope))
	# faint 8-cell tiling so camera motion reads on an otherwise flat field
	var tile: float = 0.5 + 0.5 * sin(x / (CELL_M * 8.0) * PI) * sin(z / (CELL_M * 8.0) * PI)
	return c * (0.93 + 0.07 * tile)


func _make_multimesh(mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mat.metallic = 0.0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mm.custom_aabb = AABB(Vector3(-1.0, -50.0, -1.0), Vector3(map_w_m + 2.0, 200.0, map_h_m + 2.0))
	add_child(mmi)
	return mmi


static func _blob_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 0.55))
	g.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


# ---- per-refresh instance batches -----------------------------------------------------------------------------------
func begin_frame() -> void:
	_nb = 0
	_nc = 0
	_ns = 0


## One oriented box: `centre` world position of the box centre, `size` full extents, `yaw` radians about +Y.
func push_box(centre: Vector3, size: Vector3, yaw: float, color: Color) -> void:
	if not render:
		return
	_push(_box_buf, _nb, Basis(Vector3.UP, yaw).scaled_local(size), centre, color)
	_nb += 1


func push_capsule(base: Vector3, radius: float, height: float, color: Color) -> void:
	if not render:
		return
	# CapsuleMesh default: radius 0.5, height 2.0 (cylinder 1.0 + caps)
	_push(_cap_buf, _nc, Basis.from_scale(Vector3(radius * 2.0, height * 0.5, radius * 2.0)), base + Vector3(0.0, height * 0.5, 0.0), color)
	_nc += 1


func push_shadow(base: Vector3, size: Vector2) -> void:
	if not render:
		return
	_push(_sh_buf, _ns, Basis.from_scale(Vector3(size.x, 1.0, size.y)), base + Vector3(0.0, 0.05, 0.0), Color.WHITE)
	_ns += 1


func end_frame() -> void:
	if not render:
		return
	_upload(_boxes, _box_buf, _nb)
	_upload(_caps, _cap_buf, _nc)
	_upload(_shadows, _sh_buf, _ns)


static func _push(buf: PackedFloat32Array, n: int, b: Basis, o: Vector3, c: Color) -> void:
	var i: int = n * 16
	if buf.size() < i + 16:
		buf.resize(maxi(buf.size() * 2, 16 * 64))
	buf[i] = b.x.x
	buf[i + 1] = b.y.x
	buf[i + 2] = b.z.x
	buf[i + 3] = o.x
	buf[i + 4] = b.x.y
	buf[i + 5] = b.y.y
	buf[i + 6] = b.z.y
	buf[i + 7] = o.y
	buf[i + 8] = b.x.z
	buf[i + 9] = b.y.z
	buf[i + 10] = b.z.z
	buf[i + 11] = o.z
	buf[i + 12] = c.r
	buf[i + 13] = c.g
	buf[i + 14] = c.b
	buf[i + 15] = c.a


func _upload(mm: MultiMesh, buf: PackedFloat32Array, n: int) -> void:
	if n == 0:
		mm.visible_instance_count = 0
		return
	if mm.instance_count < n:
		mm.instance_count = maxi(n + n / 2, 64)
	var b: PackedFloat32Array = buf.duplicate()
	b.resize(mm.instance_count * 16)
	mm.buffer = b
	mm.visible_instance_count = n
