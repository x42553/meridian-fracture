class_name ViewTerrain
extends Node3D
## Chunked heightmap terrain renderer. Source of truth is MapTerrainData (integer corner heights, 1 cell = 3 m);
## the view bakes a float vertex grid (Catmull-Rom clamped at cliffs + view-only detail noise), smooth normals and a
## cavity term into ArrayMesh chunks, and drives one splat shader from per-cell control textures.
## Everything expensive runs on WorkerThreadPool; only mesh/texture creation touches the main thread.

const CHUNK_CELLS: int = 24

var data: MapTerrainData
var subdiv: int = 2
var step_m: float = 1.5
var vw: int = 0
var vh: int = 0
var hv: PackedFloat32Array = PackedFloat32Array()   ## metres, vw*vh full-resolution height grid
var material: ShaderMaterial
var chunks: Array[MeshInstance3D] = []
var stats: Dictionary = {}
var detail_amp_m: float = 0.45
var water_depth_tex: ImageTexture

var _chunks_x: int = 0
var _chunks_z: int = 0
var _rows: Array[PackedFloat32Array] = []
var _drows: Array[PackedByteArray] = []
var _chunk_arrays: Array = []
var _indices: PackedInt32Array = PackedInt32Array()
var _noise: FastNoiseLite
var _ctrl_a: ImageTexture
var _ctrl_b: ImageTexture
var _roads: ImageTexture
var _threaded: bool = true


## Builds meshes and data textures. threaded=false is only for timing comparison.
func build(map: MapTerrainData, sub: int = 2, threaded: bool = true) -> void:
	data = map
	subdiv = sub
	_threaded = threaded
	step_m = MapTerrainData.CELL_M / float(subdiv)
	vw = map.width * subdiv + 1
	vh = map.height * subdiv + 1
	_chunks_x = map.width / CHUNK_CELLS
	_chunks_z = map.height / CHUNK_CELLS
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.09
	_noise.fractal_octaves = 3
	_noise.seed = map.seed_value

	var t0: int = Time.get_ticks_usec()
	_rows.resize(vh)
	_drows.resize(vh)
	_run_tasks(_bake_height_row, vh, "terrain heights")
	hv = PackedFloat32Array()
	var depth_bytes: PackedByteArray = PackedByteArray()
	for j in vh:
		hv.append_array(_rows[j])
		depth_bytes.append_array(_drows[j])
	_rows.clear()
	_drows.clear()
	var t1: int = Time.get_ticks_usec()
	water_depth_tex = ImageTexture.create_from_image(Image.create_from_data(vw, vh, false, Image.FORMAT_R8, depth_bytes))

	_build_indices()
	_chunk_arrays.clear()
	_chunk_arrays.resize(_chunks_x * _chunks_z)
	_run_tasks(_bake_chunk, _chunks_x * _chunks_z, "terrain chunks")
	var t2: int = Time.get_ticks_usec()

	for mi in chunks:
		mi.queue_free()
	chunks.clear()
	for idx in _chunks_x * _chunks_z:
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _chunk_arrays[idx])
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Chunk_%d" % idx
		mi.mesh = mesh
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
		chunks.append(mi)
	_chunk_arrays.clear()
	var t3: int = Time.get_ticks_usec()

	_build_control_textures()
	_roads = _build_roads_texture()
	var t4: int = Time.get_ticks_usec()
	stats = {
		"height_ms": (t1 - t0) / 1000.0, "chunk_ms": (t2 - t1) / 1000.0,
		"mesh_ms": (t3 - t2) / 1000.0, "tex_ms": (t4 - t3) / 1000.0,
		"chunks": chunks.size(), "vertices": vw * vh, "triangles": map.width * map.height * subdiv * subdiv * 2,
	}


func _run_tasks(fn: Callable, count: int, desc: String) -> void:
	if _threaded:
		var gid: int = WorkerThreadPool.add_group_task(fn, count, -1, true, desc)
		WorkerThreadPool.wait_for_group_task_completion(gid)
	else:
		for k in count:
			fn.call(k)


static func _cr(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	# Catmull-Rom clamped to the middle pair: smooth, but no overshoot ringing at cliff steps.
	var t2: float = t * t
	var v: float = 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t2 * t)
	return clampf(v, minf(p1, p2), maxf(p1, p2))


## Threaded task: bakes one vertex row (heights in metres + encoded water depth).
func _bake_height_row(j: int) -> void:
	var cw: int = data.width + 1
	var ch: int = data.height + 1
	var fy: float = float(j) / float(subdiv)
	var cy: int = mini(int(fy), data.height)
	var ty: float = fy - float(cy)
	var r0: int = clampi(cy - 1, 0, ch - 1) * cw
	var r1: int = cy * cw
	var r2: int = mini(cy + 1, ch - 1) * cw
	var r3: int = mini(cy + 2, ch - 1) * cw
	var row: PackedFloat32Array = PackedFloat32Array()
	row.resize(vw)
	var drow: PackedByteArray = PackedByteArray()
	drow.resize(vw)
	var hs: PackedInt32Array = data.heights
	var flg: PackedByteArray = data.flags
	var inv_m: float = 1.0 / float(MapTerrainData.HEIGHT_UNITS_PER_M)
	var wl: float = float(data.water_level_u) * inv_m
	var z_m: float = float(j) * step_m
	var cell_z: int = mini(int(z_m / MapTerrainData.CELL_M), data.height - 1)
	for i in vw:
		var fx: float = float(i) / float(subdiv)
		var cx: int = mini(int(fx), data.width)
		var tx: float = fx - float(cx)
		var v: float
		if tx == 0.0 and ty == 0.0:
			v = float(hs[r1 + cx])
		else:
			var c0: int = clampi(cx - 1, 0, cw - 1)
			var c2: int = mini(cx + 1, cw - 1)
			var c3: int = mini(cx + 2, cw - 1)
			var a: float = _cr(float(hs[r0 + c0]), float(hs[r0 + cx]), float(hs[r0 + c2]), float(hs[r0 + c3]), tx)
			var b: float = _cr(float(hs[r1 + c0]), float(hs[r1 + cx]), float(hs[r1 + c2]), float(hs[r1 + c3]), tx)
			var c: float = _cr(float(hs[r2 + c0]), float(hs[r2 + cx]), float(hs[r2 + c2]), float(hs[r2 + c3]), tx)
			var e: float = _cr(float(hs[r3 + c0]), float(hs[r3 + cx]), float(hs[r3 + c2]), float(hs[r3 + c3]), tx)
			v = _cr(a, b, c, e, ty)
		var x_m: float = float(i) * step_m
		# View-only micro relief, masked to ~0 on roads and start plateaus (gameplay heights stay exact there).
		var amp: float = detail_amp_m
		var cell_x: int = mini(int(x_m / MapTerrainData.CELL_M), data.width - 1)
		if (flg[cell_z * data.width + cell_x] & MapTerrainData.F_ROAD) != 0:
			amp *= 0.08
		for sc in data.start_cells:
			var ddx: float = x_m / MapTerrainData.CELL_M - float(sc.x)
			var ddz: float = z_m / MapTerrainData.CELL_M - float(sc.y)
			var dd: float = sqrt(ddx * ddx + ddz * ddz)
			amp *= smoothstep(9.0, 16.0, dd) if dd < 16.0 else 1.0
		var hm: float = v * inv_m + _noise.get_noise_2d(x_m, z_m) * amp
		row[i] = hm
		drow[i] = clampi(int((wl - hm + 2.0) / 8.0 * 255.0 + 0.5), 0, 255)
	_rows[j] = row
	_drows[j] = drow


func _build_indices() -> void:
	var n: int = CHUNK_CELLS * subdiv
	var nv: int = n + 1
	_indices.resize(n * n * 6)
	var p: int = 0
	for j in n:
		for i in n:
			var a: int = j * nv + i
			var b: int = a + 1
			var c: int = a + nv
			var d: int = c + 1
			if ((i + j) & 1) == 0:
				_indices[p] = a
				_indices[p + 1] = b
				_indices[p + 2] = c
				_indices[p + 3] = b
				_indices[p + 4] = d
				_indices[p + 5] = c
			else:
				_indices[p] = a
				_indices[p + 1] = b
				_indices[p + 2] = d
				_indices[p + 3] = a
				_indices[p + 4] = d
				_indices[p + 5] = c
			p += 6


## Threaded task: builds the surface arrays of one chunk (positions, smooth normals, cavity in COLOR.r).
func _bake_chunk(index: int) -> void:
	var n: int = CHUNK_CELLS * subdiv
	var nv: int = n + 1
	var i0: int = (index % _chunks_x) * n
	var j0: int = (index / _chunks_x) * n
	var pos: PackedVector3Array = PackedVector3Array()
	var nrm: PackedVector3Array = PackedVector3Array()
	var col: PackedColorArray = PackedColorArray()
	pos.resize(nv * nv)
	nrm.resize(nv * nv)
	col.resize(nv * nv)
	var two_step: float = 2.0 * step_m
	var k: int = 0
	for j in nv:
		var gj: int = j0 + j
		var jm: int = maxi(gj - 1, 0) * vw
		var jp: int = mini(gj + 1, vh - 1) * vw
		var jm4: int = maxi(gj - 4, 0) * vw
		var jp4: int = mini(gj + 4, vh - 1) * vw
		var jr: int = gj * vw
		for i in nv:
			var gi: int = i0 + i
			var hh: float = hv[jr + gi]
			pos[k] = Vector3(float(gi) * step_m, hh, float(gj) * step_m)
			var hl: float = hv[jr + maxi(gi - 1, 0)]
			var hr: float = hv[jr + mini(gi + 1, vw - 1)]
			nrm[k] = Vector3(hl - hr, two_step, hv[jm + gi] - hv[jp + gi]).normalized()
			var lap: float = (hv[jr + maxi(gi - 4, 0)] + hv[jr + mini(gi + 4, vw - 1)] + hv[jm4 + gi] + hv[jp4 + gi]) * 0.25 - hh
			col[k] = Color(clampf(0.5 - lap * 0.05, 0.0, 1.0), 0.0, 0.0, 1.0)
			k += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = _indices
	_chunk_arrays[index] = arrays


## Per-cell control weights: ctrl_a = grass, dirt, rock, sand; ctrl_b = snow, salvage, (unused), moisture.
## Bilinear filtering turns the 3 m cell steps into soft ramps that the shader distorts with noise.
func _build_control_textures() -> void:
	var n: int = data.width * data.height
	var ca: PackedByteArray = PackedByteArray()
	var cb: PackedByteArray = PackedByteArray()
	ca.resize(n * 4)
	cb.resize(n * 4)
	ca.fill(0)
	cb.fill(0)
	for c in n:
		match data.types[c]:
			MapTerrainData.T_GRASS: ca[c * 4] = 255
			MapTerrainData.T_DIRT, MapTerrainData.T_ASPHALT: ca[c * 4 + 1] = 255
			MapTerrainData.T_ROCK: ca[c * 4 + 2] = 255
			MapTerrainData.T_SAND: ca[c * 4 + 3] = 255
			MapTerrainData.T_SNOW: cb[c * 4] = 255
			MapTerrainData.T_SALVAGE: cb[c * 4 + 1] = 255
		cb[c * 4 + 3] = data.moisture[c]
	_ctrl_a = ImageTexture.create_from_image(Image.create_from_data(data.width, data.height, false, Image.FORMAT_RGBA8, ca))
	_ctrl_b = ImageTexture.create_from_image(Image.create_from_data(data.width, data.height, false, Image.FORMAT_RGBA8, cb))


## Road raster at 4 texels per cell: R = 255 - dist_to_centreline/6 m, G = signed lateral, BA = sin/cos of the
## along-road phase (12 m period), so dashes stay crisp under bilinear filtering.
func _build_roads_texture() -> ImageTexture:
	var res: int = 4
	var tw: int = data.width * res
	var th: int = data.height * res
	var texel: float = MapTerrainData.CELL_M / float(res)
	var px: PackedByteArray = PackedByteArray()
	px.resize(tw * th * 4)
	px.fill(0)
	var best: PackedFloat32Array = PackedFloat32Array()
	best.resize(tw * th)
	best.fill(99.0)
	var unit: float = MapTerrainData.CELL_M / 16.0
	for pl in data.roads:
		var acc: float = 0.0
		for k in range(0, pl.size() - 2, 2):
			var a: Vector2 = Vector2(pl[k], pl[k + 1]) * unit
			var b: Vector2 = Vector2(pl[k + 2], pl[k + 3]) * unit
			var ab: Vector2 = b - a
			var len: float = ab.length()
			var dir: Vector2 = ab / len
			var l2: float = ab.length_squared()
			var i0: int = maxi(0, int((minf(a.x, b.x) - 7.0) / texel))
			var i1: int = mini(tw - 1, int((maxf(a.x, b.x) + 7.0) / texel))
			var j0: int = maxi(0, int((minf(a.y, b.y) - 7.0) / texel))
			var j1: int = mini(th - 1, int((maxf(a.y, b.y) + 7.0) / texel))
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p: Vector2 = Vector2((float(i) + 0.5) * texel, (float(j) + 0.5) * texel)
					var ap: Vector2 = p - a
					var t: float = clampf(ap.dot(ab) / l2, 0.0, 1.0)
					var dist: float = p.distance_to(a + ab * t)
					var idx: int = j * tw + i
					if dist < 6.0 and dist < best[idx]:
						best[idx] = dist
						var lat: float = dir.x * ap.y - dir.y * ap.x
						var ph: float = (acc + t * len) * TAU / 12.0
						px[idx * 4] = int((1.0 - dist / 6.0) * 255.0 + 0.5)
						px[idx * 4 + 1] = clampi(int(128.0 + lat / 6.0 * 127.0), 0, 255)
						px[idx * 4 + 2] = int(128.0 + sin(ph) * 127.0)
						px[idx * 4 + 3] = int(128.0 + cos(ph) * 127.0)
			acc += len
	return ImageTexture.create_from_image(Image.create_from_data(tw, th, false, Image.FORMAT_RGBA8, px))


## Creates the shared terrain material. low=true compiles the cheap variant (no triplanar, no caustics).
func create_material(tex: ViewDetailTextures, low: bool = false) -> ShaderMaterial:
	var base: Shader = load("res://shaders/terrain.gdshader")
	var shader: Shader = base
	if low:
		shader = Shader.new()
		shader.code = base.code.replace("shader_type spatial;", "shader_type spatial;\n#define TERRAIN_LOW")
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = shader
	var size: Vector2 = data.size_m()
	m.set_shader_parameter("ctrl_a", _ctrl_a)
	m.set_shader_parameter("ctrl_b", _ctrl_b)
	m.set_shader_parameter("roads", _roads)
	m.set_shader_parameter("water_depth", water_depth_tex)
	m.set_shader_parameter("detail", tex.detail)
	m.set_shader_parameter("detail_nrm", tex.normals)
	m.set_shader_parameter("map_size", size)
	m.set_shader_parameter("depth_scale", Vector2(1.0 / (step_m * vw), 1.0 / (step_m * vh)))
	m.set_shader_parameter("depth_offset", Vector2(0.5 / vw, 0.5 / vh))
	m.set_shader_parameter("stamps", ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)))
	material = m
	for mi in chunks:
		mi.material_override = m
	return m


func apply_mood(mood: ViewMoodDef) -> void:
	for key in mood.palette:
		material.set_shader_parameter(key, mood.palette[key])
	material.set_shader_parameter("dryness", mood.dryness)
	material.set_shader_parameter("cloud_strength", mood.cloud_strength)


func set_scorch_texture(tex: Texture2D) -> void:
	material.set_shader_parameter("stamps", tex)


func set_shadow_casting(enabled: bool) -> void:
	var mode: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in chunks:
		mi.cast_shadow = mode as GeometryInstance3D.ShadowCastingSetting


func set_material_override_all(m: Material) -> void:
	for mi in chunks:
		mi.material_override = m


## Bilinear ground height in metres (view-only).
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


## Ray vs heightfield without physics: adaptive marching + bisection. Returns Vector3.INF on a miss.
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 3000.0) -> Vector3:
	var size: Vector2 = data.size_m()
	var t: float = 0.0
	var prev_t: float = 0.0
	while t < max_dist:
		var p: Vector3 = origin + dir * t
		if p.x >= 0.0 and p.z >= 0.0 and p.x <= size.x and p.z <= size.y:
			var h: float = height_at(p.x, p.z)
			if p.y <= h:
				var lo: float = prev_t
				var hi: float = t
				for it in 8:
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
