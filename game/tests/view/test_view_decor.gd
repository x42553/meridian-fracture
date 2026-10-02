extends RefCounted
## VIEW-04: decor placement rules against MapData fixtures, urban blocks, deposit clusters, grouping, determinism.

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")
const SIZE: int = 96
const K := ViewDecor.Kind


## One fixture with every decor-relevant terrain: forest, rock, cliff, mountain, SF_BLOCK, shallow shore, deposits, urban blocks,
## plus road / pavement / beach / ford / sand / dirt / deep cells that must stay empty.
func _patch(m: MapData) -> void:
	for i: int in m.n:
		m.deco[i] = (i * 37 + 11) & 255
	Fx.paint(m, 20, 20, 39, 39, MapTerrain.T_FOREST)
	Fx.paint(m, 50, 20, 60, 30, MapTerrain.T_ROCK)
	Fx.paint(m, 50, 32, 60, 40, MapTerrain.T_CLIFF)
	Fx.paint(m, 70, 20, 80, 30, MapTerrain.T_MOUNTAIN)
	for x: int in range(10, 30, 2):
		m.flags[45 * SIZE + x] |= MapData.SF_BLOCK
	Fx.paint(m, 20, 60, 30, 70, MapTerrain.T_SHALLOW)
	Fx.paint(m, 20, 71, 30, 75, MapTerrain.T_DEEP)
	Fx.paint(m, 15, 60, 19, 70, MapTerrain.T_BEACH)
	Fx.paint(m, 60, 60, 66, 66, MapTerrain.T_GRASS)
	for y: int in range(60, 67):
		for x: int in range(60, 67):
			m.deposit_max[y * SIZE + x] = 800
	Fx.paint(m, 10, 80, 25, 88, MapTerrain.T_URBAN)
	Fx.paint(m, 40, 80, 50, 82, MapTerrain.T_ROAD)
	Fx.paint(m, 40, 84, 50, 86, MapTerrain.T_PAVEMENT)
	Fx.paint(m, 70, 40, 80, 45, MapTerrain.T_SAND)
	Fx.paint(m, 70, 50, 80, 55, MapTerrain.T_DIRT)
	Fx.paint(m, 70, 60, 80, 62, MapTerrain.T_FORD)
	m.water_level_u = 60


func _build(biome: int = 0, groups: int = 4, density: float = 1.0) -> Array:
	var src: ViewTerrainSource = Fx.source(SIZE, Callable(), 0, biome, _patch)
	var ter: ViewTerrain = ViewTerrain.new()
	ter.build(src, 2, ViewDetailTextures.build(64), false, false)
	var qs: Dictionary = ViewQuality.load_presets()
	var q: ViewQuality = ViewQuality.create(qs, ViewQuality.Preset.HIGH, ViewQuality.Renderer.FORWARD_PLUS)
	q.set_override("decor_density", density)
	q.values["decor_groups"] = groups
	var d: ViewDecor = ViewDecor.new()
	d.build(ter, src, q)
	return [d, ter, src]


func _free(a: Array) -> void:
	for n: Variant in a:
		if n is Node:
			(n as Node).free()


func _cells_of(d: ViewDecor, kinds: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k: int in kinds:
		out.append_array(d.source_cells(k))
	return out


func test_placement_rules(t: TestCtx) -> void:
	var a: Array = _build()
	var d: ViewDecor = a[0] as ViewDecor
	var src: ViewTerrainSource = a[2] as ViewTerrainSource
	var allowed: Dictionary = {
		K.BROADLEAF: [MapTerrain.T_FOREST], K.CONIFER: [MapTerrain.T_FOREST], K.PALM: [MapTerrain.T_FOREST],
		K.ROCK: [MapTerrain.T_ROCK, MapTerrain.T_CLIFF, MapTerrain.T_MOUNTAIN],
		K.REED: [MapTerrain.T_SHALLOW],
		K.OFFICE: [MapTerrain.T_URBAN], K.APARTMENT: [MapTerrain.T_URBAN], K.WAREHOUSE: [MapTerrain.T_URBAN],
	}
	var seen_kinds: int = 0
	for kind: int in ViewDecor.KIND_COUNT:
		var cells: PackedInt32Array = d.source_cells(kind)
		t.eq(cells.size(), d.counts[kind], "row count of kind %d" % kind)
		if cells.is_empty():
			continue
		seen_kinds += 1
		for row: int in cells.size():
			var c: int = cells[row]
			var terr: int = src.terrain[c]
			var ok: bool = false
			if kind == K.CRYSTAL or kind == K.SCRAP:
				ok = src.deposit_fraction(c) > 0.0
			elif kind == K.ROCK and (src.flags[c] & MapData.SF_BLOCK) != 0:
				ok = true
			elif allowed.has(kind):
				ok = (allowed[kind] as Array).has(terr)
			if not ok:
				t.fail("kind %d placed on cell %d (terrain %d, flags %d)" % [kind, c, terr, src.flags[c]])
				break
			if kind < K.OFFICE:
				var p: Vector3 = d.row_position(kind, row)
				if int(p.x / 3.0) != c % SIZE or int(p.z / 3.0) != c / SIZE:
					t.fail("kind %d row %d leaves its cell %d" % [kind, row, c])
					break
	t.ge(seen_kinds, 6, "fixture exercises trees, rocks, reeds, crystals, scrap and buildings")
	t.gt(d.counts[K.BROADLEAF], 0, "trees on FOREST")
	t.gt(d.counts[K.ROCK], 0, "rocks on ROCK / CLIFF / MOUNTAIN / SF_BLOCK")
	t.gt(d.counts[K.REED], 0, "reeds on shore shallow cells")
	t.gt(d.counts[K.CRYSTAL] + d.counts[K.SCRAP], 0, "deposit clusters")
	t.gt(d.counts[K.OFFICE] + d.counts[K.APARTMENT] + d.counts[K.WAREHOUSE], 0, "urban buildings")
	_free(a)


func test_nothing_on_open_ground_roads_water(t: TestCtx) -> void:
	var a: Array = _build()
	var d: ViewDecor = a[0] as ViewDecor
	var src: ViewTerrainSource = a[2] as ViewTerrainSource
	var banned: Array[int] = [MapTerrain.T_GRASS, MapTerrain.T_DIRT, MapTerrain.T_SAND, MapTerrain.T_ROAD, MapTerrain.T_PAVEMENT, MapTerrain.T_FORD, MapTerrain.T_BEACH, MapTerrain.T_DEEP]
	var bad: int = 0
	for kind: int in ViewDecor.KIND_COUNT:
		if kind == K.CRYSTAL or kind == K.SCRAP:
			continue
		for c: int in d.source_cells(kind):
			if banned.has(src.terrain[c]) and (src.flags[c] & MapData.SF_BLOCK) == 0:
				bad += 1
	t.eq(bad, 0, "no decor on grass, dirt, sand, road, pavement, ford, beach or deep cells")
	var reeds_far: int = 0
	for c: int in d.source_cells(K.REED):
		if src.shore_dist[c] > ViewDecor.REED_SHORE_MAX:
			reeds_far += 1
	t.eq(reeds_far, 0, "reeds only within one cell of land")
	_free(a)


func test_reeds_only_in_temperate_and_tropical(t: TestCtx) -> void:
	var arid: Array = _build(1)
	t.eq((arid[0] as ViewDecor).counts[K.REED], 0, "arid biome: no reeds")
	_free(arid)
	var arctic: Array = _build(2)
	var d: ViewDecor = arctic[0] as ViewDecor
	t.eq(d.counts[K.REED], 0, "arctic biome: no reeds")
	t.eq(d.counts[K.BROADLEAF], 0, "arctic biome: conifers only")
	t.gt(d.counts[K.CONIFER], 0, "arctic biome: conifers")
	_free(arctic)


func test_forest_density_one_to_four_trees_per_cell(t: TestCtx) -> void:
	var a: Array = _build()
	var d: ViewDecor = a[0] as ViewDecor
	var per_cell: Dictionary = {}
	for kind: int in [K.BROADLEAF, K.CONIFER]:
		for c: int in d.source_cells(kind):
			per_cell[c] = int(per_cell.get(c, 0)) + 1
	var worst: int = 0
	for c: Variant in per_cell.keys():
		worst = maxi(worst, per_cell[c] as int)
	t.le(worst, 4, "at most 4 trees per forest cell")
	t.gt(per_cell.size(), 200, "most of the 400 forest cells carry trees")
	_free(a)


func test_urban_blocks_are_merged_rectangles(t: TestCtx) -> void:
	var a: Array = _build()
	var d: ViewDecor = a[0] as ViewDecor
	var src: ViewTerrainSource = a[2] as ViewTerrainSource
	var n: int = d.counts[K.OFFICE] + d.counts[K.APARTMENT] + d.counts[K.WAREHOUSE]
	t.eq(n, 18, "16 x 9 urban cells = 6 x 3 blocks of at most 3 x 3 (greedy row-major merge; the last column is 1 cell wide)")
	var covered: int = 0
	var tall: float = 0.0
	for kind: int in [K.OFFICE, K.APARTMENT, K.WAREHOUSE]:
		for row: int in d.counts[kind]:
			var o: int = row * ViewDecor.FLOATS_PER_INSTANCE
			var b: PackedFloat32Array = d._inst[kind]
			var sx: float = absf(b[o]) + absf(b[o + 8])
			var sz: float = absf(b[o + 2]) + absf(b[o + 10])
			var w_cells: int = roundi((sx + 0.5) / 3.0)
			var h_cells: int = roundi((sz + 0.5) / 3.0)
			t.check(w_cells >= 1 and w_cells <= 3 and h_cells >= 1 and h_cells <= 3, "block %d x %d cells" % [w_cells, h_cells])
			covered += w_cells * h_cells
			var top_left: int = d.source_cells(kind)[row]
			var expect_h: float = 6.0 + float(src.deco[top_left] & 7) * 0.7
			tall = maxf(tall, b[o + 5])
			t.ge(b[o + 5], expect_h + 0.35 - 1e-3, "building height covers 6 + (deco & 7) * 0.7")
	t.eq(covered, 16 * 9, "every URBAN cell belongs to exactly one building")
	t.le(tall, 10.9 + 0.35 + 2.0, "tallest building stays in the 6 .. 10.9 m rule (plus foundation and slope)")
	_free(a)


func test_deposit_clusters_shrink_and_hide(t: TestCtx) -> void:
	var qs: Dictionary = ViewQuality.load_presets()
	var patch: Callable = func(md: MapData) -> void:
		md.deposit_max[50 * SIZE + 50] = 1000
		md.deposit_max[50 * SIZE + 51] = 1000
	var map: MapData = Fx.map(SIZE, Callable(), 0, 0, patch)
	var src: ViewTerrainSource = ViewTerrainSource.from_map(map)
	var ter: ViewTerrain = ViewTerrain.new()
	ter.build(src, 2, ViewDetailTextures.build(64), false, false)
	var d: ViewDecor = ViewDecor.new()
	d.build(ter, src, ViewQuality.create(qs, ViewQuality.Preset.HIGH))
	var cell: int = 50 * SIZE + 50
	var kind: int = K.CRYSTAL if d.source_cells(K.CRYSTAL).has(cell) else K.SCRAP
	var row: int = d.source_cells(kind).find(cell)
	t.ge(row, 0, "deposit cell has a cluster")
	t.eq(d.row_scale_multiplier(kind, row), 1.0, "full deposit: full scale")
	var cells: PackedInt32Array = PackedInt32Array()
	map.harvest_cell(cell, 500)
	src.drain_deposit_changes(cells)
	d.apply_deposit_changes(src, cells, 1)
	t.near(d.row_scale_multiplier(kind, row), 0.35 + 0.65 * 0.5, 1e-4, "half deposit: 0.35 + 0.65 * 0.5")
	map.harvest_cell(cell, 500)
	var n: int = src.drain_deposit_changes(cells)
	d.apply_deposit_changes(src, cells, n)
	t.lt(d.row_scale_multiplier(kind, row), 0.001, "empty deposit: hidden")
	var mmi: MultiMeshInstance3D = null
	for c: Node in d.get_children():
		var m: MultiMeshInstance3D = c as MultiMeshInstance3D
		if m != null and m.multimesh.mesh == d._meshes[kind]:
			mmi = m
	t.not_null(mmi, "cluster MultiMesh exists")
	var other: int = 50 * SIZE + 51
	var okind: int = K.CRYSTAL if d.source_cells(K.CRYSTAL).has(other) else K.SCRAP
	t.eq(d.row_scale_multiplier(okind, d.source_cells(okind).find(other)), 1.0, "the second deposit is untouched")
	d.free()
	ter.free()


func test_grouping_counts_and_regroup(t: TestCtx) -> void:
	var a: Array = _build(0, 4)
	var d: ViewDecor = a[0] as ViewDecor
	var n4: int = d.multimesh_count
	t.eq(d.get_child_count(), n4, "one MultiMeshInstance3D per group and kind")
	var total: int = d.total_instances()
	d.regroup(6)
	var n6: int = d.multimesh_count
	t.gt(n6, n4, "more groups per side -> more MultiMeshes")
	t.le(n4, 16 * ViewDecor.KIND_COUNT, "at most groups^2 x kinds")
	t.eq(d.total_instances(), total, "regroup keeps every instance")
	var inst: int = 0
	for c: Node in d.get_children():
		if c is MultiMeshInstance3D and not (c as Node).is_queued_for_deletion():
			inst += (c as MultiMeshInstance3D).multimesh.instance_count
	t.eq(inst, total, "MultiMesh instance counts add up")
	t.note("fixture: groups 4 -> %d MultiMeshes, 6 -> %d; %d instances" % [n4, n6, total])
	_free(a)


func test_generated_map_group_counts_and_build_time(t: TestCtx) -> void:
	var map: MapData = MapGenerator.generate({"family": 0, "size": 192, "seed": 1337, "layout_players": 2, "params": {"biome": 0}})
	var src: ViewTerrainSource = ViewTerrainSource.from_map(map)
	var ter: ViewTerrain = ViewTerrain.new()
	ter.build(src, 2, ViewDetailTextures.build(64), false, true)
	var qs: Dictionary = ViewQuality.load_presets()
	var d: ViewDecor = ViewDecor.new()
	var q: ViewQuality = ViewQuality.create(qs, ViewQuality.Preset.HIGH)
	q.values["decor_groups"] = 4
	d.build(ter, src, q)
	var n4: int = d.multimesh_count
	d.regroup(6)
	var n6: int = d.multimesh_count
	t.note("192^2 open map: %d instances, groups 4 -> %d, 6 -> %d MultiMeshes, build %.0f ms" % [d.total_instances(), n4, n6, d.build_ms])
	t.check(n4 >= 40 and n4 <= 80, "groups 4: 40..80 MultiMeshes (spike 56)")
	t.check(n6 >= 60 and n6 <= 130, "groups 6: 60..130 MultiMeshes (spike 94)")
	t.lt(d.build_ms, 600.0, "decor place + MultiMesh build well under a second")
	var t0: int = Time.get_ticks_usec()
	d.regroup(5)
	t.note("regroup %.1f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	d.free()
	ter.free()


func test_deterministic_scatter(t: TestCtx) -> void:
	var a: Array = _build()
	var b: Array = _build()
	var da: ViewDecor = a[0] as ViewDecor
	var db: ViewDecor = b[0] as ViewDecor
	t.eq(da.counts, db.counts, "same map -> same counts")
	var same: bool = true
	for kind: int in ViewDecor.KIND_COUNT:
		same = same and da._inst[kind] == db._inst[kind]
	t.check(same, "identical instance data")
	_free(a)
	_free(b)


func test_density_thins_trees(t: TestCtx) -> void:
	var full: Array = _build(0, 4, 1.0)
	var half: Array = _build(0, 4, 0.5)
	var nf: int = (full[0] as ViewDecor).counts[K.BROADLEAF]
	var nh: int = (half[0] as ViewDecor).counts[K.BROADLEAF]
	t.lt(nh, nf, "decor_density 0.5 places fewer trees")
	t.gt(nh, nf / 4, "but not none")
	_free(full)
	_free(half)


func test_mood_kit_switch_and_meshes(t: TestCtx) -> void:
	var a: Array = _build()
	var d: ViewDecor = a[0] as ViewDecor
	var moods: Dictionary = ViewMoodDef.load_all()
	d.apply_mood(moods["tropical_day"] as ViewMoodDef)
	t.eq(d.kit, "palm", "tropical kit")
	t.gt(d.counts[K.PALM], 0, "palms placed")
	d.apply_mood(moods["arctic_day"] as ViewMoodDef)
	t.eq(d.counts[K.PALM] + d.counts[K.BROADLEAF], 0, "arctic kit: conifers only")
	t.eq(d.material.get_shader_parameter("foliage_a"), (moods["arctic_day"] as ViewMoodDef).foliage_a, "foliage colours from the mood")
	for k: int in ViewDecor.KIND_COUNT:
		t.gt(d.mesh_tris[k], 20, "mesh %d has triangles" % k)
	t.lt(d.mesh_tris[K.BROADLEAF], 600, "broadleaf stays low-poly")
	_free(a)
