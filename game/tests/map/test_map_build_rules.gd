extends RefCounted
## TM-06 / U10: terrain build rules (check_land, check_berth, scan) and their MapData facts.

const Fx := preload("res://tests/fixtures/map_fixture.gd")


func _sea_map() -> MapData:
	# 32x32 grass, deep sea in x 16..29 (14 cols) y 3..28, a shallow shelf column at x=15, a 60-cell deep pond
	var m: MapData = MapData.create(Fx.tt(), 32)
	m.terrain.fill(MapTerrain.T_GRASS)
	m.flags.fill(0)
	Fx.rect(m, 16, 3, 29, 28, MapTerrain.T_DEEP)
	Fx.rect(m, 15, 3, 15, 28, MapTerrain.T_SHALLOW)
	Fx.rect(m, 3, 3, 12, 8, MapTerrain.T_DEEP)  # 10 x 6 = 60 cells pond
	Fx.rect(m, 3, 9, 12, 9, MapTerrain.T_BEACH)
	m.finalize()
	return m


func _cells(m: MapData, x0: int, y0: int, x1: int, y1: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			out.append(m.idx(x, y))
	return out


func test_check_land_order(t: TestCtx) -> void:
	var m: MapData = MapData.create(Fx.tt(), 32)
	Fx.rect(m, 6, 6, 25, 25, MapTerrain.T_GRASS)
	m.flags[m.idx(12, 12)] = MapData.SF_NOBUILD
	Fx.rect(m, 20, 20, 20, 20, MapTerrain.T_BEACH)
	m.finalize()
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([0])), MapBuildRules.PR_OUT_OF_BOUNDS, "cell 0, margin 1")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(31, 5)])), MapBuildRules.PR_OUT_OF_BOUNDS, "right edge")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(3, 10)])), MapBuildRules.PR_TERRAIN, "rim cell: cliff")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(1, 10)]), false, 1), MapBuildRules.PR_TERRAIN, "x=1 is inside margin 1")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(1, 10)]), false, 2), MapBuildRules.PR_OUT_OF_BOUNDS, "margin 2")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(12, 12)])), MapBuildRules.PR_NOBUILD, "deposit ring")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(10, 10)])), MapBuildRules.PR_OK, "plain grass")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(20, 20)])), MapBuildRules.PR_TERRAIN, "beach without shore_ok")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(20, 20)]), true), MapBuildRules.PR_OK, "beach with shore_ok")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(12, 12), m.idx(3, 10)])), MapBuildRules.PR_TERRAIN, "terrain rule precedes nobuild")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(12, 12), m.idx(0, 0)])), MapBuildRules.PR_OUT_OF_BOUNDS, "bounds rule first")
	m.occupy_cells(4, PackedInt32Array([m.idx(10, 10), m.idx(11, 10)]))
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(11, 10), m.idx(11, 11)])), MapBuildRules.PR_OCCUPIED, "occupied")
	t.eq(MapBuildRules.check_land(m, PackedInt32Array([m.idx(12, 12), m.idx(11, 10)])), MapBuildRules.PR_NOBUILD, "nobuild precedes occupied")
	# the same facts through MapData predicates
	t.check(m.is_buildable(9, 9), "buildable grass")
	t.check_false(m.is_buildable(12, 12), "nobuild")
	t.check_false(m.is_buildable(20, 20), "beach is not standard")
	t.check(m.is_shore_buildable(20, 20), "beach is shore-buildable")
	t.check_false(m.is_shore_buildable(12, 12), "nobuild also blocks shore")
	t.check_false(m.is_buildable(3, 10), "rim")
	t.check_false(m.is_buildable(-1, 3), "outside")
	# footprint form
	var fp: MapFootprint = MapFootprint.new(2, 2)
	t.eq(MapBuildRules.check(m, fp, 0, 14, 14), MapBuildRules.PR_OK, "check(fp)")
	t.eq(MapBuildRules.check(m, fp, 0, 30, 30), MapBuildRules.PR_OUT_OF_BOUNDS, "check(fp) outside")
	t.eq(MapBuildRules.check(m, fp, 0, 10, 9), MapBuildRules.PR_OCCUPIED, "check(fp) overlaps the structure")


func test_check_berth(t: TestCtx) -> void:
	var m: MapData = _sea_map()
	t.eq(MapBuildRules.check_berth(m, _cells(m, 6, 15, 8, 16)), MapBuildRules.PR_NEEDS_WATER, "berth on dry land")
	t.eq(MapBuildRules.check_berth(m, _cells(m, 5, 4, 7, 5)), MapBuildRules.PR_WATER_EXIT, "3x2 berth in a 60-cell pond")
	t.eq(MapBuildRules.check_berth(m, _cells(m, 15, 10, 16, 11)), MapBuildRules.PR_NEEDS_WATER, "berth partly in SHALLOW")
	t.eq(MapBuildRules.check_berth(m, _cells(m, 20, 10, 22, 11)), MapBuildRules.PR_OK, "berth in the sea")
	# the FIRST berth cell touches the coast (SZ_2 clearance 1, no naval region): a real dock berth always looks like this
	var coast_first: PackedInt32Array = PackedInt32Array([m.idx(29, 10), m.idx(28, 10), m.idx(29, 11), m.idx(28, 11)])
	t.eq(m.nav.region_size(MapTerrain.NP_NAVAL, MapTerrain.SZ_2, coast_first[0]), 0, "precondition: the shore cell has no SZ_2 region")
	t.eq(MapBuildRules.check_berth(m, coast_first), MapBuildRules.PR_OK, "a berth whose first cell touches the coast is fine (INT1 fix: best cell decides)")
	t.eq(MapBuildRules.check_berth(m, PackedInt32Array([m.idx(5, 5), m.idx(20, 10)])), MapBuildRules.PR_WATER_EXIT, "two different bodies")
	t.eq(MapBuildRules.check_berth(m, PackedInt32Array()), MapBuildRules.PR_NEEDS_WATER, "empty berth")
	t.eq(MapBuildRules.check_berth(m, _cells(m, 5, 4, 7, 5), 10), MapBuildRules.PR_WATER_EXIT, "small min_body does not lift the naval rule")
	t.eq(m.water_body_size(20, 10), 14 * 26 + 26, "sea + shelf are one body (shallow shelf counts)")
	t.eq(m.water_body_size(5, 5), 60, "pond")
	t.eq(m.water_body_size(20, 30), 0, "land")
	t.check(m.has_adjacent_water(14, 10), "shore land cell")
	t.check_false(m.has_adjacent_water(10, 20), "inland")
	t.check(m.is_water(15, 10), "shallow is water")
	t.check(m.is_land(14, 10), "land")


func _ring_ref(m: MapData, fp: MapFootprint, orient: int, ccx: int, ccy: int, radius: int, max_out: int) -> PackedInt32Array:
	var res: PackedInt32Array = PackedInt32Array()
	var cells: PackedInt32Array = PackedInt32Array()
	for r: int in range(0, radius + 1):
		var ring: PackedInt32Array = PackedInt32Array()
		for y: int in range(ccy - r, ccy + r + 1):
			for x: int in range(ccx - r, ccx + r + 1):
				if maxi(absi(x - ccx), absi(y - ccy)) == r:
					ring.append(y * 1000 + x)  # row-major key
		ring.sort()
		for key: int in ring:
			var x: int = key % 1000
			var y: int = key / 1000
			if fp.cells_at(orient, x, y, cells, m.w, m.h) >= 0 and MapBuildRules.check_land(m, cells) == MapBuildRules.PR_OK:
				res.append(y * m.w + x)
				if res.size() >= max_out:
					return res
	return res


func test_scan_nearest_ring_first(t: TestCtx) -> void:
	var m: MapData = Fx.open(32)
	m.occupy_cells(9, PackedInt32Array([m.idx(16, 16)]))
	var fp: MapFootprint = MapFootprint.new(2, 2)
	var out: PackedInt32Array = PackedInt32Array()
	var got: int = MapBuildRules.scan(m, 2, 2, PackedByteArray(), 0, 16, 16, 3, out, 100)
	var want: PackedInt32Array = _ring_ref(m, fp, 0, 16, 16, 3, 100)
	t.eq(got, want.size(), "count")
	t.eq(out, want, "ring order, then row-major, only valid sites")
	t.eq(out[0], m.idx(17, 15), "first valid site: ring 1, first row-major spot clear of the structure")
	t.check(not out.has(m.idx(15, 15)) and not out.has(m.idx(16, 16)), "overlapping sites excluded")
	t.eq(MapBuildRules.scan(m, 2, 2, PackedByteArray(), 0, 16, 16, 3, out, 5), 5, "max_out bounds the result")
	t.eq(out, _ring_ref(m, fp, 0, 16, 16, 3, 5), "first five")
	# rotated 3x1 footprint near the edge: sites that leave the map are skipped
	var m2: MapData = Fx.open(16)
	var out2: PackedInt32Array = PackedInt32Array()
	var n2: int = MapBuildRules.scan(m2, 3, 1, PackedByteArray(), 1, 2, 2, 2, out2, 100)
	t.eq(out2, _ring_ref(m2, MapFootprint.new(3, 1, PackedByteArray(), true), 1, 2, 2, 2, 100), "rotated near the edge")
	t.ge(n2, 1, "some site exists")
	t.eq(MapBuildRules.scan(m2, 2, 2, PackedByteArray(), 0, 8, 8, 0, out2, 10), 1, "radius 0 checks the centre only")
