class_name ViewTerrain
extends Node3D
## Chunked heightmap terrain renderer (render spec 3.4 / 5.5). The sim owns integer terrain ids and corner heights; this
## node bakes them (ViewTerrainBake, threaded), builds the control textures (ViewTerrainLayers) and drives ONE shared
## splat ShaderMaterial. It answers ground queries for the camera, picking and placement without a physics engine.
## Presentation only: it reads a ViewTerrainSource and never mutates sim state.

const CHUNK_CELLS: int = ViewTerrainBake.CHUNK_CELLS
const SHADER_PATH: String = "res://assets/shaders/terrain.gdshader"
const SKIRT_EXTENT_M: float = 400.0

var src: ViewTerrainSource = null
var material: ShaderMaterial = null
var water_depth_tex: ImageTexture = null
var layers: ViewTerrainLayers = null
var subdiv: int = 2
var step_m: float = 1.5
var vw: int = 0
var vh: int = 0
var hv: PackedFloat32Array = PackedFloat32Array()  ## vw * vh vertex heights (m)
var chunks: Array[MeshInstance3D] = []
var chunks_x: int = 0
var chunks_z: int = 0
var stats: Dictionary = {}
var skirt: MeshInstance3D = null

var _size_m: Vector2 = Vector2.ZERO
var _sea: float = ViewTerrainSource.NO_WATER


## Bakes and builds everything. `low_shader` compiles the TERRAIN_LOW variant (no triplanar, no caustics).
func build(source: ViewTerrainSource, sub: int, detail: ViewDetailTextures, low_shader: bool, threaded: bool = true) -> void:
	ViewGlobals.ensure()
	src = source
	subdiv = sub
	step_m = ViewConsts.CELL_M / float(sub)
	_size_m = source.size_m()
	_sea = source.sea_level_m
	var bake: ViewTerrainBake = ViewTerrainBake.bake(source, sub, threaded)
	vw = bake.vw
	vh = bake.vh
	hv = bake.hv
	chunks_x = bake.chunks_x
	chunks_z = bake.chunks_z
	var t0: int = Time.get_ticks_usec()
	for mi: MeshInstance3D in chunks:
		mi.queue_free()
	chunks.clear()
	for idx: int in bake.chunk_arrays.size():
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bake.chunk_arrays[idx])
		var mi2: MeshInstance3D = MeshInstance3D.new()
		mi2.name = "Chunk_%d" % idx
		mi2.mesh = mesh
		mi2.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi2.layers = ViewLayers.MASK_WORLD
		add_child(mi2)
		chunks.append(mi2)
	var t1: int = Time.get_ticks_usec()
	layers = ViewTerrainLayers.build(source, hv, vw, vh)
	water_depth_tex = layers.water_depth
	_create_material(detail, low_shader)
	_build_skirt()
	var t2: int = Time.get_ticks_usec()
	stats = bake.stats.duplicate()
	stats["mesh_ms"] = float(t1 - t0) / 1000.0
	stats["layers_ms"] = layers.build_ms
	stats["material_ms"] = float(t2 - t1) / 1000.0 - layers.build_ms
	stats["chunks"] = chunks.size()
	stats["triangles"] = source.width * source.height * sub * sub * 2
	stats["vertices"] = vw * vh


func _create_material(detail: ViewDetailTextures, low: bool) -> void:
	var base: Shader = load(SHADER_PATH) as Shader
	var shader: Shader = base
	if low:
		shader = Shader.new()
		shader.code = base.code.replace("shader_type spatial;", "shader_type spatial;\n#define TERRAIN_LOW")
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("ctrl_a", layers.ctrl_a)
	m.set_shader_parameter("ctrl_b", layers.ctrl_b)
	m.set_shader_parameter("ctrl_flags", layers.ctrl_flags)
	m.set_shader_parameter("moisture", layers.moisture_tex)
	m.set_shader_parameter("road_cov", layers.road_cov)
	m.set_shader_parameter("road_info", layers.road_info)
	m.set_shader_parameter("water_depth", layers.water_depth)
	m.set_shader_parameter("shore_dist", layers.shore_dist_tex)
	m.set_shader_parameter("detail", detail.detail)
	m.set_shader_parameter("detail_nrm", detail.normals)
	m.set_shader_parameter("map_size", _size_m)
	m.set_shader_parameter("depth_scale", Vector2(1.0 / (step_m * float(vw)), 1.0 / (step_m * float(vh))))
	m.set_shader_parameter("depth_offset", Vector2(0.5 / float(vw), 0.5 / float(vh)))  # texel centres = vertices
	m.set_shader_parameter("stamps", ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)))
	material = m
	for mi: MeshInstance3D in chunks:
		mi.material_override = m


## Four flat quads around the map at the outer rim height, unshaded near-black, so the sky never shows below the horizon.
func _build_skirt() -> void:
	if skirt != null:
		skirt.queue_free()
	var edge: float = 0.0
	var cnt: int = 0
	for i: int in vw:
		edge += hv[i] + hv[(vh - 1) * vw + i]
		cnt += 2
	for j: int in vh:
		edge += hv[j * vw] + hv[j * vw + vw - 1]
		cnt += 2
	var y: float = edge / float(cnt)
	var w: float = _size_m.x
	var h: float = _size_m.y
	var e: float = SKIRT_EXTENT_M
	var verts: PackedVector3Array = PackedVector3Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var rects: Array[Rect2] = [Rect2(-e, -e, w + 2.0 * e, e), Rect2(-e, h, w + 2.0 * e, e), Rect2(-e, 0.0, e, h), Rect2(w, 0.0, e, h)]
	for r: Rect2 in rects:
		var b: int = verts.size()
		verts.append(Vector3(r.position.x, y, r.position.y))
		verts.append(Vector3(r.end.x, y, r.position.y))
		verts.append(Vector3(r.end.x, y, r.end.y))
		verts.append(Vector3(r.position.x, y, r.end.y))
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.015, 0.02, 0.025)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	skirt = MeshInstance3D.new()
	skirt.name = "VoidSkirt"
	skirt.mesh = mesh
	skirt.material_override = mat
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skirt.layers = ViewLayers.MASK_WORLD
	add_child(skirt)


## Applies a mood palette (Dictionary of uniform name -> Color) plus dryness. Cloud shadows come from the `atm_cloud`
## global written by ViewAtmosphere. ViewMoodDef (VIEW-03) exposes `palette` and `dryness`; `apply_mood` accepts any object
## that has them (duck-typed so this file does not depend on VIEW-03).
func apply_palette(palette: Dictionary, dryness: float) -> void:
	if material == null:
		return
	for key: Variant in palette.keys():
		material.set_shader_parameter(StringName(str(key)), palette[key])
	material.set_shader_parameter("dryness", dryness)


func apply_mood(m: Object) -> void:
	var pal: Variant = m.get(&"palette")
	var dry: Variant = m.get(&"dryness")
	apply_palette(pal as Dictionary if pal is Dictionary else {}, float(dry) if dry != null else 0.0)


func set_scorch_texture(t: Texture2D) -> void:
	if material != null:
		material.set_shader_parameter("stamps", t)


func set_shadow_casting(on: bool) -> void:
	var mode: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi: MeshInstance3D in chunks:
		mi.cast_shadow = mode


func world_size() -> Vector2:
	return _size_m


func triangle_count() -> int:
	return src.width * src.height * subdiv * subdiv * 2


## Repaints the deposit weight of changed cells (from ViewTerrainSource.drain_deposit_changes).
func apply_deposit_changes(cells: PackedInt32Array, n: int) -> void:
	if layers != null:
		layers.repaint_deposits(cells, n)
		material.set_shader_parameter("ctrl_b", layers.ctrl_b)


## Bilinear ground height in metres, clamped to the map.
func height_at(x: float, z: float) -> float:
	var fx: float = clampf(x / step_m, 0.0, float(vw) - 1.001)
	var fz: float = clampf(z / step_m, 0.0, float(vh) - 1.001)
	var ix: int = int(fx)
	var iz: int = int(fz)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var i00: int = iz * vw + ix
	var top: float = lerpf(hv[i00], hv[i00 + 1], tx)
	var bot: float = lerpf(hv[i00 + vw], hv[i00 + vw + 1], tx)
	return lerpf(top, bot, tz)


func normal_at(x: float, z: float) -> Vector3:
	var e: float = step_m
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


func is_water_at(x: float, z: float) -> bool:
	return height_at(x, z) < _sea


## Ray vs heightfield without physics: adaptive march + 8 bisection steps. Vector3.INF on a miss.
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 3000.0) -> Vector3:
	var t: float = 0.0
	var prev_t: float = 0.0
	while t < max_dist:
		var p: Vector3 = origin + dir * t
		if p.x >= 0.0 and p.z >= 0.0 and p.x <= _size_m.x and p.z <= _size_m.y:
			var h: float = height_at(p.x, p.z)
			if p.y <= h:
				var lo: float = prev_t
				var hi: float = t
				for it: int in 8:
					var mid: float = (lo + hi) * 0.5
					var q: Vector3 = origin + dir * mid
					if q.y <= height_at(q.x, q.z):
						hi = mid
					else:
						lo = mid
				return origin + dir * hi
			prev_t = t
			t += clampf((p.y - h) * 0.45, step_m * 0.5, 30.0)
		else:
			prev_t = t
			t += 6.0
	return Vector3.INF
