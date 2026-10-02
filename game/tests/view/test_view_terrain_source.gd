extends RefCounted
## VIEW-02: ViewTerrainSource (MapData adapter) and ViewTerrainLayers (splat table, road raster, deposit drain).

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")


func test_corner_heights_and_dry_sea_level(t: TestCtx) -> void:
	var m: MapData = Fx.map(64)
	var s: ViewTerrainSource = ViewTerrainSource.from_map(m)
	t.eq(s.width, 64, "width")
	t.eq(s.corner_m.size(), 65 * 65, "corner count")
	var ok: bool = true
	for i: int in s.corner_m.size():
		if absf(s.corner_m[i] - float(m.heights[i]) / 32.0) > 1e-6:
			ok = false
	t.check(ok, "corner heights equal MapData.heights / 32 on a dry map")
	t.eq(s.sea_level_m, -1000.0, "no water: sea level -1000")
	t.check(not s.has_water(), "has_water false")
	t.eq(s.start_cells.size(), 0, "no spawns in the fixture")


func test_sea_level_from_water_cells_and_generator_level(t: TestCtx) -> void:
	var patch: Callable = func(m: MapData) -> void: Fx.paint(m, 20, 20, 30, 30, MapTerrain.T_SHALLOW)
	var flat: Callable = func(_cx: int, _cy: int) -> int: return 100
	var s: ViewTerrainSource = Fx.source(64, flat, 0, 0, patch)
	t.near(s.sea_level_m, (100.0 + 0.5) / 32.0, 1e-6, "(max water corner + 0.5 unit) / 32")
	var m2: MapData = Fx.map(64, flat, 0, 0, patch)
	m2.water_level_u = 130
	t.near(ViewTerrainSource.from_map(m2).sea_level_m, 130.0 / 32.0, 1e-6, "generator water_level_u wins")


func test_carve_lowers_water_cells_above_the_plane(t: TestCtx) -> void:
	var patch: Callable = func(m: MapData) -> void:
		Fx.paint(m, 10, 10, 20, 20, MapTerrain.T_DEEP)
		m.water_level_u = 100
	var high: Callable = func(_cx: int, _cy: int) -> int: return 300
	var s: ViewTerrainSource = Fx.source(64, high, 0, 0, patch)
	t.near(s.corner_at(15, 15), 100.0 / 32.0 - ViewTerrainSource.DEPTH_DEEP_M, 1e-5, "interior corner of a deep pool sits 3 m below the plane")
	t.check(s.corner_at(10, 10) <= 100.0 / 32.0 + ViewTerrainSource.BANK_ABOVE_M + 1e-5, "shore corner just above the plane")
	t.near(s.corner_at(50, 50), 300.0 / 32.0, 1e-6, "far land untouched")
	var low: Callable = func(_cx: int, _cy: int) -> int: return 20
	var s2: ViewTerrainSource = Fx.source(64, low, 0, 0, patch)
	t.near(s2.corner_at(12, 12), 20.0 / 32.0, 1e-6, "water already below the plane is not raised")


func test_splat_table(t: TestCtx) -> void:
	var flat: Callable = func(_cx: int, _cy: int) -> int: return 96
	var patch: Callable = func(m: MapData) -> void:
		Fx.paint(m, 20, 20, 21, 20, MapTerrain.T_GRASS)
		Fx.paint(m, 24, 20, 24, 20, MapTerrain.T_CLIFF)
		m.flags[20 * m.w + 24] = MapData.SF_RAMP
		Fx.paint(m, 26, 20, 26, 20, MapTerrain.T_CLIFF)
		Fx.paint(m, 28, 20, 28, 20, MapTerrain.T_PAVEMENT)
		Fx.paint(m, 30, 20, 30, 20, MapTerrain.T_RUBBLE)
	var src_t: ViewTerrainSource = Fx.source(64, flat, 0, 0, patch)
	var lt: ViewTerrainLayers = ViewTerrainLayers.build(src_t, PackedFloat32Array([0.0]), 1, 1)
	var c: int = 20 * 64 + 20
	t.eq(lt.ctrl_a_bytes[c * 4], 255, "temperate grass: grass 1.0")
	t.eq(lt.ctrl_b_bytes[c * 4], 0, "temperate grass: no snow")
	var ramp: int = 20 * 64 + 24
	t.eq(lt.ctrl_a_bytes[ramp * 4 + 2], int(0.15 * 255.0 + 0.5), "RAMP cell: rock weight x 0.15")
	t.gt(lt.ctrl_a_bytes[ramp * 4 + 1], 200, "RAMP cell reads as a dirt path")
	var cliff: int = 20 * 64 + 26
	t.eq(lt.ctrl_a_bytes[cliff * 4 + 2], 255, "plain cliff: rock 1.0")
	t.eq(lt.ctrl_b_bytes[(20 * 64 + 28) * 4 + 1], 255, "pavement: urban 1.0")
	t.eq(lt.ctrl_b_bytes[(20 * 64 + 30) * 4 + 3], int(0.8 * 255.0 + 0.5), "rubble: 0.8")
	var arctic: ViewTerrainSource = Fx.source(64, flat, 0, 2, patch)
	var la: ViewTerrainLayers = ViewTerrainLayers.build(arctic, PackedFloat32Array([0.0]), 1, 1)
	t.eq(la.ctrl_a_bytes[c * 4], 0, "arctic grass: no grass")
	t.eq(la.ctrl_b_bytes[c * 4], 255, "arctic grass: snow 1.0")


func test_deposit_weight_and_drain(t: TestCtx) -> void:
	var patch: Callable = func(pm: MapData) -> void:
		pm.deposit_max[30 * pm.w + 30] = 500
		pm.deposit_max[30 * pm.w + 31] = 500
	var m: MapData = Fx.map(64, Callable(), 0, 0, patch)
	var s: ViewTerrainSource = ViewTerrainSource.from_map(m)
	var cells: PackedInt32Array = PackedInt32Array()
	t.eq(s.deposit_cells(cells), 2, "two deposit cells")
	t.near(s.deposit_fraction(30 * 64 + 30), 1.0, 1e-6, "full")
	var lt: ViewTerrainLayers = ViewTerrainLayers.build(s, PackedFloat32Array([0.0]), 1, 1)
	t.eq(lt.ctrl_b_bytes[(30 * 64 + 30) * 4 + 2], 255, "deposit weight 1 on a full cell")
	t.gt(lt.ctrl_b_bytes[(30 * 64 + 32) * 4 + 2], 100, "neighbour of a deposit cell carries dilated weight")
	m.harvest_cell(30 * 64 + 30, 500)
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(s.drain_deposit_changes(out), 1, "harvested cell drained once")
	t.eq(out[0], 30 * 64 + 30, "cell index")
	t.eq(s.drain_deposit_changes(out), 0, "then empty")
	t.near(s.deposit_fraction(30 * 64 + 30), 0.0, 1e-6, "depleted")
	lt.repaint_deposits(PackedInt32Array([30 * 64 + 30]), 1)
	t.eq(lt.ctrl_b_bytes[(30 * 64 + 30) * 4 + 2], int(0.7 * 255.0 + 0.5), "depleted cell fades to the neighbour's dilation")


## Road run-length markings (urban only).
func _urban_layers(patch: Callable) -> ViewTerrainLayers:
	var flat: Callable = func(_cx: int, _cy: int) -> int: return 96
	var s: ViewTerrainSource = Fx.source(96, flat, 1, 3, patch)
	return ViewTerrainLayers.build(s, PackedFloat32Array([0.0]), 1, 1)


func test_avenue_rows(t: TestCtx) -> void:
	var lt: ViewTerrainLayers = _urban_layers(func(m: MapData) -> void: Fx.paint(m, 10, 30, 85, 35, MapTerrain.T_ROAD))
	for k: int in 6:
		var v: Vector4i = lt.street_info(40, 30 + k)
		t.eq(v.x, 255, "row %d is a street cell" % k)
		t.eq(v.y, 128, "row %d: street runs horizontally" % k)
		t.eq(v.z, k, "row %d: k" % k)
		t.eq(v.w, 6, "row %d: n" % k)


func test_lattice_streets_and_junctions(t: TestCtx) -> void:
	var lt: ViewTerrainLayers = _urban_layers(func(m: MapData) -> void:
		Fx.paint(m, 10, 50, 85, 53, MapTerrain.T_ROAD)  # horizontal street, 4 wide
		Fx.paint(m, 20, 10, 23, 85, MapTerrain.T_ROAD)  # vertical street A
		Fx.paint(m, 36, 10, 39, 85, MapTerrain.T_ROAD))  # vertical street B
	for x: int in range(24, 36):  # 12 cells between the two junctions
		t.eq(lt.street_info(x, 51).x, 255, "segment cell x=%d classified" % x)
	t.eq(lt.street_info(21, 51).x, 0, "junction cell is not a street cell")
	t.eq(lt.street_info(21, 30).y, 255, "vertical street: G = 255")
	t.eq(lt.street_info(21, 30).z, 1, "vertical street: k = x - start")
	t.eq(lt.street_info(21, 30).w, 4, "vertical street: n = 4")


func test_trunks_have_no_street_cells(t: TestCtx) -> void:
	for slope: Vector2i in [Vector2i(1, 1), Vector2i(1, 4), Vector2i(1, 9)]:
		var lt: ViewTerrainLayers = _urban_layers(func(m: MapData) -> void:
			for x: int in range(10, 85):
				var y0: int = 8 + x * slope.x / slope.y
				for r: int in 3:
					if y0 + r < 90:
						m.terrain[(y0 + r) * m.w + x] = MapTerrain.T_ROAD)
		var found: int = 0
		for i: int in 96 * 96:
			if lt.road_info_bytes[i * 4] != 0:
				found += 1
		t.eq(found, 0, "3-wide trunk of slope %d/%d has no street cells" % [slope.x, slope.y])


func test_road_coverage_profile(t: TestCtx) -> void:
	var lt: ViewTerrainLayers = _urban_layers(func(m: MapData) -> void: Fx.paint(m, 10, 40, 85, 42, MapTerrain.T_ROAD))
	t.eq(lt.road_cov_bytes[41 * 96 + 40], 255, "interior of a 3-wide trunk")
	t.le(lt.road_cov_bytes[39 * 96 + 40], 128, "one cell outside")
	t.gt(lt.road_cov_bytes[40 * 96 + 40], 128, "edge cell of the trunk is above the threshold")
