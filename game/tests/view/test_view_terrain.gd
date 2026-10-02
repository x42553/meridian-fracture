extends RefCounted
## VIEW-02: chunks, seams, height/normal queries, raycast, bake time.

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")


func _build(size: int, height_fn: Callable = Callable(), patch: Callable = Callable(), threaded: bool = true) -> ViewTerrain:
	var ter: ViewTerrain = ViewTerrain.new()
	var detail: ViewDetailTextures = ViewDetailTextures.build(64)
	ter.build(Fx.source(size, height_fn, 0, 0, patch), 2, detail, false, threaded)
	return ter


func _triangles(ter: ViewTerrain) -> int:
	var n: int = 0
	for mi: MeshInstance3D in ter.chunks:
		var arr: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
		n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func test_chunk_counts_and_triangles(t: TestCtx) -> void:
	for spec: Array in [[96, 9], [104, 16], [256, 64]]:
		var ter: ViewTerrain = _build(spec[0] as int)
		t.eq(ter.chunks.size(), spec[1] as int, "%d cells: chunks" % (spec[0] as int))
		var size: int = spec[0] as int
		t.eq(_triangles(ter), size * size * 2 * 2 * 2, "%d cells: triangles = w*h*subdiv^2*2" % size)
		if size == 256:
			t.eq(_triangles(ter), 524288, "256^2: 524 288 triangles")
		ter.free()


func test_partial_chunk_is_smaller(t: TestCtx) -> void:
	var bake: ViewTerrainBake = ViewTerrainBake.bake(Fx.source(104), 2, false)
	t.eq(bake.chunks_x, 4, "4 x 4 chunks")
	t.eq(bake.chunk_size[3], Vector2i(16, 64), "last column chunk is 8 cells wide (16 quads at subdiv 2)")
	t.eq(bake.chunk_size[15], Vector2i(16, 16), "corner chunk 8 x 8 cells")


func test_height_at_matches_vertices_and_is_monotone_between(t: TestCtx) -> void:
	var ter: ViewTerrain = _build(96)
	var ok: bool = true
	for j: int in range(0, ter.vh, 17):
		for i: int in range(0, ter.vw - 1, 13):
			var h: float = ter.height_at(float(i) * ter.step_m, float(j) * ter.step_m)
			if absf(h - ter.hv[j * ter.vw + i]) > 1e-4:
				ok = false
			var mid: float = ter.height_at((float(i) + 0.5) * ter.step_m, float(j) * ter.step_m)
			var a: float = ter.hv[j * ter.vw + i]
			var b: float = ter.hv[j * ter.vw + i + 1]
			if mid < minf(a, b) - 1e-4 or mid > maxf(a, b) + 1e-4:
				ok = false
	t.check(ok, "height_at equals hv on the grid and stays between neighbours in between")
	ter.free()


func test_normals_unit_and_chunk_seams(t: TestCtx) -> void:
	var bake: ViewTerrainBake = ViewTerrainBake.bake(Fx.source(96), 2, true)
	var unit_ok: bool = true
	for arrays: Variant in bake.chunk_arrays:
		for n: Vector3 in ((arrays as Array)[Mesh.ARRAY_NORMAL] as PackedVector3Array):
			if absf(n.length() - 1.0) > 1e-4:
				unit_ok = false
	t.check(unit_ok, "all normals are unit length")
	# chunk (0,0) east edge == chunk (1,0) west edge; chunk (0,0) south edge == chunk (0,1) north edge
	var a: Array = bake.chunk_arrays[0]
	var e: Array = bake.chunk_arrays[1]
	var s: Array = bake.chunk_arrays[3]
	var nv: int = 65
	var worst: float = 0.0
	for k: int in nv:
		var pa: Vector3 = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array)[k * nv + 64]
		var pe: Vector3 = (e[Mesh.ARRAY_VERTEX] as PackedVector3Array)[k * nv]
		var na: Vector3 = (a[Mesh.ARRAY_NORMAL] as PackedVector3Array)[k * nv + 64]
		var ne: Vector3 = (e[Mesh.ARRAY_NORMAL] as PackedVector3Array)[k * nv]
		worst = maxf(worst, maxf(pa.distance_to(pe), na.distance_to(ne)))
		var ps: Vector3 = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array)[64 * nv + k]
		var pn: Vector3 = (s[Mesh.ARRAY_VERTEX] as PackedVector3Array)[k]
		var ns: Vector3 = (a[Mesh.ARRAY_NORMAL] as PackedVector3Array)[64 * nv + k]
		var nn: Vector3 = (s[Mesh.ARRAY_NORMAL] as PackedVector3Array)[k]
		worst = maxf(worst, maxf(ps.distance_to(pn), ns.distance_to(nn)))
	t.le(worst, 1e-5, "neighbouring chunk edges share position and normal")


func test_threaded_equals_single_thread(t: TestCtx) -> void:
	var s: ViewTerrainSource = Fx.source(64)
	var a: ViewTerrainBake = ViewTerrainBake.bake(s, 2, true)
	var b: ViewTerrainBake = ViewTerrainBake.bake(s, 2, false)
	t.eq(a.hv, b.hv, "threaded bake is bit-identical to the single-threaded one")


func test_raycast_down_and_slope_and_miss(t: TestCtx) -> void:
	var ter: ViewTerrain = _build(96)
	var hit: Vector3 = ter.raycast(Vector3(100.0, 500.0, 100.0), Vector3.DOWN)
	t.check(hit != Vector3.INF, "vertical ray hits")
	t.near(hit.x, 100.0, 0.01, "x")
	t.near(hit.y, ter.height_at(100.0, 100.0), 0.02, "y within 2 cm of the surface")
	t.eq(ter.raycast(Vector3(100.0, 50.0, 100.0), Vector3.UP), Vector3.INF, "upward ray misses")
	t.eq(ter.raycast(Vector3(-50.0, 500.0, 100.0), Vector3.DOWN), Vector3.INF, "ray outside the map misses")
	ter.free()
	# exact ramp: y = 0.25 x + 2 (SF_RAMP on every cell disables the relief noise)
	var plane: Callable = func(cx: int, _cy: int) -> int: return int((0.25 * float(cx) * 3.0 + 2.0) * 32.0)
	var patch: Callable = func(m: MapData) -> void: m.flags.fill(MapData.SF_RAMP)
	var ter2: ViewTerrain = _build(96, plane, patch)
	var dir: Vector3 = Vector3(cos(deg_to_rad(30.0)), -sin(deg_to_rad(30.0)), 0.0)
	var o: Vector3 = Vector3(60.0, 60.0, 100.0)
	# 60 - sin30 t = 0.25 (60 + cos30 t) + 2  ->  t = (60 - 15 - 2) / (0.5 + 0.25 cos30)
	var tt: float = 43.0 / (0.5 + 0.25 * cos(deg_to_rad(30.0)))
	var expect: Vector3 = o + dir * tt
	var h2: Vector3 = ter2.raycast(o, dir)
	t.check(h2 != Vector3.INF, "slanted ray hits the ramp")
	t.le(h2.distance_to(expect), 0.05, "within 5 cm of the analytic intersection")
	ter2.free()


func test_water_query_and_size(t: TestCtx) -> void:
	var patch: Callable = func(m: MapData) -> void:
		Fx.paint(m, 20, 20, 30, 30, MapTerrain.T_DEEP)
		m.water_level_u = 100
	var high: Callable = func(_cx: int, _cy: int) -> int: return 300
	var ter: ViewTerrain = _build(64, high, patch)
	t.check(ter.is_water_at(25.0 * 3.0 + 1.5, 25.0 * 3.0 + 1.5), "inside the carved pool")
	t.check(not ter.is_water_at(50.0 * 3.0, 50.0 * 3.0), "dry land")
	t.eq(ter.world_size(), Vector2(192.0, 192.0), "world size")
	t.not_null(ter.skirt, "void skirt exists")
	t.check(ter.normal_at(60.0, 60.0).is_normalized(), "normal_at is a unit vector")
	ter.free()


func test_road_raster_from_a_trunk(t: TestCtx) -> void:
	var patch: Callable = func(m: MapData) -> void: Fx.paint(m, 10, 40, 60, 42, MapTerrain.T_ROAD)
	var ter: ViewTerrain = _build(96, Callable(), patch)
	t.eq(ter.layers.road_cov_bytes[41 * 96 + 30], 255, "road_cov is 255 in the interior")
	t.le(ter.layers.road_cov_bytes[39 * 96 + 30], 128, "road_cov <= 128 one cell outside")
	ter.free()


func test_shader_variants_and_material(t: TestCtx) -> void:
	var ter: ViewTerrain = _build(64)
	t.not_null(ter.material, "shared material")
	t.eq(ter.material.get_shader_parameter("map_size"), Vector2(192.0, 192.0), "map_size uniform")
	for mi: MeshInstance3D in ter.chunks:
		t.check(mi.material_override == ter.material, "one shared material")
		break
	ter.apply_palette({"grass_a": Color(1, 0, 0)}, 0.5)
	t.eq(ter.material.get_shader_parameter("dryness"), 0.5, "dryness applied")
	var src_text: String = FileAccess.get_file_as_string(ViewTerrain.SHADER_PATH)
	t.check(src_text.contains("shader_type spatial;"), "shader_type line present for the TERRAIN_LOW injection")
	t.check(src_text.contains("view_time") and not src_text.contains("TIME *"), "uses view_time, never TIME")
	var low: ViewTerrain = ViewTerrain.new()
	low.build(Fx.source(64), 2, ViewDetailTextures.build(64), true)
	t.check((low.material.shader as Shader).code.contains("#define TERRAIN_LOW"), "TERRAIN_LOW variant injected")
	low.free()
	ter.free()


func test_bake_time_256_threaded(t: TestCtx) -> void:
	var s: ViewTerrainSource = Fx.source(256)
	var best: float = 1.0e9
	for pass_i: int in 3:
		var t0: int = Time.get_ticks_usec()
		var b: ViewTerrainBake = ViewTerrainBake.bake(s, 2, true)
		var lay: ViewTerrainLayers = ViewTerrainLayers.build(s, b.hv, b.vw, b.vh)
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
		t.gt(lay.build_ms, 0.0, "layers timed")
	t.note("256^2 bake + layers, best of 3: %.1f ms" % best)
	t.lt(best, 450.0, "256^2 bake (heights + chunks + layers) <= 450 ms threaded")
