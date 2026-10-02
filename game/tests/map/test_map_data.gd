extends RefCounted
## TM-02: MapData core (U9 map part, U12 deposits, U13 serialisation, U17 predicates, kernel contract 7.2b).

const Fx := preload("res://tests/fixtures/map_fixture.gd")


## 32x32 grass map with one 24-cell (4 x 6) field of 600-credit cells at x 10..13, y 10..15; second field of
## 16 rich cells; a lake; view layers filled so the serialisation has something to say.
func _deposit_map(finalize: bool = true) -> MapData:
	var m: MapData = MapData.create(Fx.tt(), 32)
	m.terrain.fill(MapTerrain.T_GRASS)
	m.flags.fill(0)
	Fx.rect(m, 22, 4, 28, 9, MapTerrain.T_DEEP)
	Fx.rect(m, 21, 4, 21, 9, MapTerrain.T_SHALLOW)
	for y: int in range(10, 16):
		for x: int in range(10, 14):
			m.field_of[y * 32 + x] = 1
			m.deposit_max[y * 32 + x] = 600
	for y: int in range(20, 24):
		for x: int in range(20, 24):
			m.field_of[y * 32 + x] = 2
			m.deposit_max[y * 32 + x] = 1200
	m.fields = PackedInt32Array([
		1, 12 * 32 + 11, 3, 24, 14400, MapData.FK_START, 0, 12 * 32 + 11, 0, 0,
		2, 21 * 32 + 21, 3, 16, 19200, MapData.FK_NATURAL_RICH, 1, 21 * 32 + 21, 1, -1])
	m.spawns = PackedInt32Array([0, 5 * 32 + 5, 0, 0, 0, 0, 1, 26 * 32 + 26, 2048, 1, 1, 0])
	m.neutrals = PackedInt32Array([1, 8 * 32 + 20, 2, 2, 0, 0, 0, 0])
	m.neutral_ids = PackedStringArray(["neutral.civilian_garrison", "neutral.substation"])
	m.seed_value = 123456789012
	m.family = 2
	m.biome = 1
	m.slots = 2
	m.players = 2
	m.gen_version = 3
	m.gen_params = PackedInt32Array([1, 2, 3])
	for i: int in m.heights.size():
		m.heights[i] = (i * 7) % 200
	for i: int in m.n:
		m.moisture[i] = (i * 3) % 251
		m.deco[i] = i % 5
		m.height[i] = (i * 5) % 256
	m.roads = [PackedInt32Array([1, 2, 3, 4]), PackedInt32Array([5, 6])]
	m.water_level_u = 17
	m.deco_seed = 99
	if finalize:
		m.finalize()
	return m


func test_create_rim_and_finalize_layers(t: TestCtx) -> void:
	var m: MapData = MapData.create(Fx.tt(), 24)
	t.eq(m.terrain_at(m.idx(0, 5)), MapTerrain.T_MOUNTAIN, "outer rim: mountain")
	t.eq(m.terrain_at(m.idx(1, 5)), MapTerrain.T_MOUNTAIN, "outer rim: mountain")
	t.eq(m.terrain_at(m.idx(2, 5)), MapTerrain.T_CLIFF, "inner rim: cliff")
	t.eq(m.terrain_at(m.idx(5, 12)), MapTerrain.T_CLIFF, "rim width 6")
	t.eq(m.terrain_at(m.idx(6, 12)), MapTerrain.T_GRASS, "interior")
	t.check((m.flags[m.idx(3, 3)] & MapData.SF_NOBUILD) != 0, "rim is no-build")
	t.eq(m.heights.size(), 25 * 25, "height lattice")
	m.terrain[m.idx(12, 12)] = MapTerrain.T_DEEP
	m.terrain[m.idx(13, 12)] = MapTerrain.T_FORD
	m.finalize()
	t.eq(m.kind_at(m.idx(12, 12)), MapTerrain.TK_DEEP, "kind layer")
	t.eq(m.kind_at(m.idx(13, 12)), MapTerrain.TK_SHALLOW, "ford kind")
	t.eq(m.kind_at_units(12 * 1024 + 5, 12 * 1024 + 900), MapTerrain.TK_DEEP, "kind_at_units")
	t.eq(m.kind_at_units(-50, -50), m.kind_at(0), "kind_at_units clamps into the map")
	t.eq(m.idx_of_units(-50, 99999999), m.idx(0, 23), "idx_of_units clamps")
	t.eq(m.speed_bp_at(MapTerrain.MC_FOOT, m.idx(8, 8)), 10000, "speed_bp_at grass")
	t.eq(m.speed_bp_at(MapTerrain.MC_FOOT, m.idx(12, 12)), 0, "speed_bp_at deep")
	t.check((m.flags[m.idx(11, 12)] & MapData.SF_SHORE) != 0, "SF_SHORE next to water")
	t.check((m.flags[m.idx(13, 13)] & MapData.SF_SHORE) != 0, "land cell below the ford is shore")
	t.check((m.flags[m.idx(12, 12)] & MapData.SF_SHORE) == 0, "water is never shore")
	t.eq(m.buildable[m.idx(8, 8)], 1, "buildable grass")
	t.eq(m.buildable[m.idx(3, 3)], 0, "rim not buildable")
	t.eq(m.buildable[m.idx(6, 6)], 1, "just inside the rim")
	t.eq(m.water_body_size(12, 12), 2, "deep + ford are one 4-connected body")
	t.eq(m.shore_dist[m.idx(12, 12)], 3, "shore_dist: one step from land")
	t.eq(m.shore_dist[m.idx(8, 8)], 0, "0 on land")
	t.eq(m.shore_dist.size(), m.n, "shore_dist sized")
	t.expect_errors(1)
	m.finalize()  # second call is an error
	t.check(m.is_finalized(), "still finalized")


func test_shore_distance_chamfer(t: TestCtx) -> void:
	var m: MapData = MapData.create(Fx.tt(), 32)
	m.terrain.fill(MapTerrain.T_GRASS)
	m.flags.fill(0)
	Fx.rect(m, 10, 10, 20, 20, MapTerrain.T_DEEP)
	m.finalize()
	t.eq(m.shore_dist[m.idx(10, 15)], 3, "edge water cell: 1 step from land")
	t.eq(m.shore_dist[m.idx(12, 15)], 9, "3 cells in")
	t.eq(m.shore_dist[m.idx(15, 15)], 18, "6 cells in")
	t.eq(m.shore_dist[m.idx(10, 10)], 3, "corner cell: land is orthogonally adjacent")
	t.eq(m.shore_dist[m.idx(12, 12)], 9, "diagonal: 3 cells to the nearest land orthogonally")
	var d: MapData = MapData.create(Fx.tt(), 24)
	d.finalize()
	t.check(d.shore_dist.count(0) == d.n, "dry map: all zero")


func test_predicates_u17(t: TestCtx) -> void:
	var m: MapData = _deposit_map()
	t.check(m.is_water(21, 5), "ford/shallow is water")
	t.check(m.is_water(25, 5), "deep is water")
	t.check_false(m.is_water(20, 5), "land")
	t.check(m.is_land(6, 6), "land")
	t.check_false(m.is_land(25, 5), "deep is not land")
	t.check_false(m.is_water(-1, 0), "outside")
	t.eq(m.water_body_size(25, 5), 7 * 6 + 6, "all water of the lake")
	t.eq(m.water_body_size(21, 4), 7 * 6 + 6, "shelf is in the same body")
	t.eq(m.water_body_size(10, 10), 0, "land")
	t.check(m.has_adjacent_water(20, 5), "shore")
	t.check_false(m.has_adjacent_water(10, 20), "inland")
	t.check(m.is_clear(10, 20, MapData.LAYER_GROUND), "clear ground")
	t.check(m.is_clear(10, 20, MapData.LAYER_AIR), "clear air")
	t.check_false(m.is_clear(0, 0, MapData.LAYER_AIR), "air outside the interior")
	t.check(m.is_clear(25, 5, MapData.LAYER_SURFACE), "surface on water")
	t.check(m.is_clear(25, 5, MapData.LAYER_UNDERWATER), "underwater in deep")
	t.check_false(m.is_clear(21, 5, MapData.LAYER_UNDERWATER), "no submarine in the shallows")
	t.check_false(m.is_clear(10, 20, MapData.LAYER_SURFACE), "no ship on land")
	m.occupy_cells(2, PackedInt32Array([m.idx(9, 20)]))
	t.check_false(m.is_clear(9, 20, MapData.LAYER_GROUND), "structure blocks ground")
	t.check(m.is_clear(9, 20, MapData.LAYER_AIR), "air ignores structures")
	for mc: int in [MapTerrain.MC_FOOT, MapTerrain.MC_WHEELED, MapTerrain.MC_TRACKED, MapTerrain.MC_AMPHIBIOUS]:
		t.check_false(m.passable(9, 20, mc), "structure cell not passable for mc %d" % mc)
	t.check(m.passable(9, 20, MapTerrain.MC_AIR_HOVER), "air passes")
	t.check(m.is_passable_ground(9, 20), "is_passable_ground ignores structures")
	t.check_false(m.is_passable_ground(25, 5), "deep water is not ground")
	# regions come from the abstract graph (TM-04): -1 on blocked (NAV_BORDER) cells and for air
	t.eq(m.region(1, 1, MapTerrain.MC_FOOT), -1, "nav border has no region")
	t.check(m.region(3, 3, MapTerrain.MC_FOOT) >= 0, "open land has a region")
	t.eq(m.region(10, 20, MapTerrain.MC_AIR_FIXED), -1, "air has no region")
	t.eq(m.get_family(), 2, "get_family")


func test_deposits_u12(t: TestCtx) -> void:
	var m: MapData = _deposit_map()
	var c0: int = m.idx(10, 10)
	t.eq(m.deposit_at(c0), 600, "initial")
	t.eq(m.field_of_cell(c0), 1, "field id")
	t.eq(m.field_of_cell(m.idx(0, 0)), 0, "no field")
	t.eq(m.field_remaining(1), 14400, "field total")
	t.eq(m.field_remaining(2), 19200, "rich field")
	t.eq(m.field_remaining(0), 0, "field 0")
	t.eq(m.field_remaining(9), 0, "unknown field")
	t.eq(m.recompute_dynamic_hash(), m.checksum_dynamic(), "initial recompute")
	t.eq(m.harvest_cell(c0, 700), 600, "harvest more than there is")
	t.eq(m.harvest_cell(c0, 700), 0, "empty")
	t.eq(m.field_remaining(1), 13800, "field_left")
	t.eq(m.recompute_dynamic_hash(), m.checksum_dynamic(), "hash incremental == recomputed")
	# nearest cell of the field, ties -> lowest index
	var from: int = m.idx(12, 8)
	t.eq(m.harvest_field(1, from, 600), 600, "one 600 load empties one cell")
	t.eq(m.deposit_at(m.idx(10, 10)), 0, "(10,10) was already empty")
	t.eq(m.deposit_at(m.idx(11, 10)), 0, "next nearest lowest index (Chebyshev 2, ties by index)")
	t.eq(m.field_remaining(1), 13200, "13200 left")
	# a cell is not split across calls: want 1000 on a 600 cell takes 600
	t.eq(m.harvest_field(1, from, 1000), 600, "at most the cell's content")
	# drain the rest with 21 calls (24 cells: 3 already empty)
	var taken: int = 0
	var calls: int = 0
	while true:
		var k: int = m.harvest_field(1, m.idx(12, 12), 600)
		if k == 0:
			break
		taken += k
		calls += 1
	t.eq(calls, 21, "24 cells in total, 3 emptied before")
	t.eq(taken, 12600, "the rest")
	t.eq(m.field_remaining(1), 0, "field empty")
	t.eq(m.harvest_field(1, 0, 600), 0, "empty field yields 0")
	t.eq(m.recompute_dynamic_hash(), m.checksum_dynamic(), "hash after draining")
	# dirty list: each changed cell exactly once, then cleared
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(m.drain_deposit_dirty(out), 24, "24 distinct cells changed")
	t.eq(out.size(), 24, "list")
	var seen: Dictionary = {}
	for c: int in out:
		seen[c] = true
	t.eq(seen.size(), 24, "each once")
	t.eq(m.drain_deposit_dirty(out), 0, "cleared")
	# regrow: lowest index cells first, capped by deposit_max
	t.eq(m.regrow_field(1, 700), 700, "regrow")
	t.eq(m.deposit_at(m.idx(10, 10)), 600, "lowest index cell full")
	t.eq(m.deposit_at(m.idx(11, 10)), 100, "next gets the rest")
	t.eq(m.field_remaining(1), 700, "field_left follows")
	t.eq(m.regrow_field(1, 1000000), 14400 - 700, "capped by deposit_max")
	t.eq(m.regrow_field(1, 5), 0, "full")
	t.eq(m.recompute_dynamic_hash(), m.checksum_dynamic(), "hash after regrow")
	# nearest_deposit ring search
	var m2: MapData = _deposit_map()
	t.eq(m2.nearest_deposit(m2.idx(12, 12), 0), m2.idx(12, 12), "ring 0 = the cell itself")
	t.eq(m2.nearest_deposit(m2.idx(8, 8), 1), -1, "nothing within 1")
	t.eq(m2.nearest_deposit(m2.idx(8, 8), 2), m2.idx(10, 10), "ring 2, row-major")
	t.eq(m2.nearest_deposit(m2.idx(14, 12), 1), m2.idx(13, 11), "ring 1 row-major: (13,11) before (13,12)")
	# deposit_fields
	var fl: Array = m2.deposit_fields()
	t.eq(fl.size(), 2, "two fields")
	var f0: Dictionary = fl[0]
	t.eq(f0["id"], 1, "id")
	t.eq(f0["cells"], 24, "cells")
	t.eq(f0["total"], 14400, "total == sum of deposit_max")
	t.eq(f0["klass_economy"], 0, "start field")
	t.eq(f0["cx"], 11, "cx")
	t.eq(f0["cy"], 12, "cy")
	t.eq((fl[1] as Dictionary)["klass_economy"], 2, "rich field")
	t.eq((fl[1] as Dictionary)["total"], 19200, "rich total")
	t.eq(m2.neutral_spawns(), [{"type": "neutral.substation", "cx": 20, "cy": 8}], "neutral_spawns")
	t.eq(m2.objects.size(), 1, "objects")


func test_serialisation_u13(t: TestCtx) -> void:
	var m: MapData = _deposit_map()
	var b: PackedByteArray = m.to_bytes()
	var m2: MapData = MapData.from_bytes(Fx.tt(), b)
	if not t.not_null(m2, "round trip"):
		return
	t.eq(m2.map_hash(), m.map_hash(), "map_hash")
	t.eq(m2.content_hash(), m.map_hash(), "content_hash == map_hash")
	t.eq(m.content_hash(), m.map_hash(), "content_hash of the original")
	t.eq(m2.visual_hash(), m.visual_hash(), "visual_hash survives")
	t.eq(m2.to_bytes(), b, "byte-stable")
	t.eq(m2.w, 32, "w")
	t.eq(m2.seed_value, 123456789012, "64-bit seed")
	t.eq(m2.gen_params, m.gen_params, "gen_params")
	t.eq(m2.spawns, m.spawns, "spawns")
	t.eq(m2.start_cells, PackedInt32Array([5, 5, 26, 26]), "start_cells derived")
	t.eq(m2.neutral_ids, m.neutral_ids, "neutral_ids")
	t.eq(m2.roads.size(), 2, "roads")
	t.eq(m2.heights, m.heights, "heights")
	t.eq(m2.water_size, m.water_size, "derived layers rebuilt")
	t.eq(m2.checksum_dynamic(), m.checksum_dynamic(), "dynamic state initial")
	# any static change changes the hash
	var m3: MapData = _deposit_map(false)
	m3.terrain[m3.idx(8, 8)] = MapTerrain.T_DIRT
	m3.finalize()
	t.ne(m3.map_hash(), m.map_hash(), "terrain change")
	var m4: MapData = _deposit_map(false)
	m4.deposit_max[m4.idx(10, 10)] = 601
	m4.finalize()
	t.ne(m4.map_hash(), m.map_hash(), "deposit change")
	var m5: MapData = _deposit_map(false)
	m5.heights[5] = 1
	m5.finalize()
	t.eq(m5.map_hash(), m.map_hash(), "view layers are not in map_hash")
	t.ne(m5.visual_hash(), m.visual_hash(), "but in visual_hash")
	# corrupt / truncated / wrong version
	t.expect_errors(4)
	var bad: PackedByteArray = b.duplicate()
	bad[bad.size() / 2] ^= 0x55
	t.is_null(MapData.from_bytes(Fx.tt(), bad), "corrupt byte")
	t.is_null(MapData.from_bytes(Fx.tt(), b.slice(0, 40)), "truncated")
	var ver: PackedByteArray = b.duplicate()
	ver[4] = 9
	t.is_null(MapData.from_bytes(Fx.tt(), ver), "version mismatch")
	t.is_null(MapData.from_bytes(Fx.tt(), PackedByteArray([1, 2, 3])), "garbage")
	# pinned hash survives the round trip
	var f: MapData = MapData.make_flat(16, 16, PackedInt32Array([8, 8]), 0xABCD1234)
	var f2: MapData = MapData.from_bytes(Fx.tt(), f.to_bytes())
	t.eq(f2.map_hash(), 0xABCD1234, "pinned hash preserved")


func test_clone_independence(t: TestCtx) -> void:
	var m: MapData = _deposit_map()
	m.occupy_cells(5, PackedInt32Array([m.idx(20, 12), m.idx(21, 12)]))
	var ck: int = m.checksum_dynamic()
	var a: MapData = m.clone_for_world()
	var b: MapData = m.clone_fresh()
	t.eq(a.checksum_dynamic(), ck, "clone starts equal")
	t.eq(a.map_hash(), m.map_hash(), "same map hash")
	t.check(a.terrain == m.terrain and a.flags == m.flags, "static arrays equal")
	a.occupy_cells(6, PackedInt32Array([a.idx(8, 20)]))
	a.harvest_field(1, 0, 600)
	a.nav.flush_dirty(1000)
	t.eq(b.checksum_dynamic(), ck, "the other clone is untouched")
	t.eq(m.checksum_dynamic(), ck, "the template is untouched")
	t.eq(b.structure_at(b.idx(8, 20)), -1, "no structure in b")
	t.eq(m.structure_at(m.idx(8, 20)), -1, "no structure in the template")
	t.eq(b.deposit_at(b.idx(10, 10)), 600, "deposit in b")
	t.eq(b.nav.w_at(MapTerrain.NP_FOOT, b.idx(8, 20)), 16, "nav of b untouched")
	t.eq(a.nav.w_at(MapTerrain.NP_FOOT, a.idx(8, 20)), 0, "nav of a changed")
	t.eq(a.field_remaining(1), 13800, "a's field")
	t.eq(b.field_remaining(1), 14400, "b's field")
	t.eq(a.recompute_dynamic_hash(), a.checksum_dynamic(), "a consistent")
	t.check(a.nav.validate_against_terrain(), "a nav valid")
	t.check(b.nav.validate_against_terrain(), "b nav valid")
	b.vacate(5)
	t.eq(m.structure_at(m.idx(20, 12)), 5, "vacating in b keeps the template's structure")
	t.eq(m.recompute_dynamic_hash(), m.checksum_dynamic(), "template consistent")
	# no reference cycle: the whole graph of objects dies with its last reference
	var wr: WeakRef = weakref(a)
	var nr: WeakRef = weakref(a.nav)
	a = null
	t.is_null(wr.get_ref(), "MapData freed")
	t.is_null(nr.get_ref(), "MapNav freed (no cycle)")


func test_make_flat_and_for_test(t: TestCtx) -> void:
	var f: MapData = MapData.make_flat(96, 96, PackedInt32Array([10, 48, 48, 10, 85, 48, 48, 85]), 0x5678EF01)
	t.eq(f.w, 96, "w")
	t.eq(f.n, 96 * 96, "n")
	t.eq(f.map_hash(), 0x5678EF01, "pinned map_hash")
	t.eq(f.spawns.size(), 4 * MapData.SPAWN_STRIDE, "4 spawn records")
	t.eq(f.spawns[1], 48 * 96 + 10, "spawn cell index")
	t.eq(f.spawns[0], 0, "start index")
	t.eq(f.spawns[MapData.SPAWN_STRIDE], 1, "start index 1")
	t.eq(f.spawns[2], 0, "facing east toward the centre from the west")
	t.eq(f.spawns[MapData.SPAWN_STRIDE + 2], 1024, "from the north: facing south (y grows downward)")
	t.eq(f.spawns[MapData.SPAWN_STRIDE * 2 + 2], 2048, "from the east: facing west")
	t.eq(f.spawns[MapData.SPAWN_STRIDE * 3 + 2], 3072, "from the south: facing north")
	t.eq(f.start_cells, PackedInt32Array([10, 48, 48, 10, 85, 48, 48, 85]), "start_cells")
	t.eq(f.slots, 4, "slots")
	t.eq(f.terrain_at(f.idx(5, 5)), MapTerrain.T_GRASS, "grass everywhere")
	t.eq(f.terrain_at(f.idx(0, 0)), MapTerrain.T_GRASS, "no rim")
	t.eq(f.nav.w_at(MapTerrain.NP_FOOT, f.idx(1, 1)), 0, "but the nav border")
	t.eq(f.nav.w_at(MapTerrain.NP_FOOT, f.idx(2, 2)), 16, "interior")
	t.check(f.is_finalized(), "finalized")
	t.eq(f.content_hash() == f.map_hash(), false, "pinned hash is not the content hash")
	var recs: PackedInt32Array = PackedInt32Array([1, 20 * 96 + 30, 2, 2, 0, 0, 0, 0, 3, 40 * 96 + 41, 3, 3, 1, 0, 0, 0])
	var g: MapData = MapData.for_test(96, 96, PackedInt32Array([1000, 2000]), recs, 0x5678EF01)
	t.eq(g.neutrals, recs, "neutral records")
	t.eq(g.spawns[1], 1000, "spawn cell index kept")
	t.eq(g.objects.size(), 2, "objects derived")
	t.eq((g.objects[0] as Dictionary)["def_id"], "neutral.substation", "kind 1")
	t.eq((g.objects[1] as Dictionary)["cx"], 41, "cx")
	t.eq(g.neutral_def_for_kind(1), -1, "unmapped kind")
	g.set_neutral_def(1, 4)
	t.eq(g.neutral_def_for_kind(1), 4, "mapped")
	t.eq(g.neutral_def_for_kind(0), -1, "gap is -1")
	t.eq(g.neutral_def_for_kind(99), -1, "out of range")
	t.check(g.footprint_of(1, 4) == null, "no footprint yet")
	var fp: MapFootprint = MapFootprint.new(3, 3)
	g.set_footprint(1, 4, fp)
	t.check(g.footprint_of(1, 4) == fp, "footprint registered")
	t.check(g.footprint_of(1, 5) == null, "other def")
	var c: MapData = g.clone_fresh()
	t.check(c.footprint_of(1, 4) == fp, "clone shares the tables")
	t.eq(c.neutral_def_for_kind(1), 4, "clone neutral defs")
	t.expect_errors(1)
	t.is_null(MapData.for_test(96, 96, PackedInt32Array([1]), PackedInt32Array([1, 2, 3]), 1), "partial neutral record")


func test_occupy_with_footprint(t: TestCtx) -> void:
	var m: MapData = Fx.open(32)
	var dock: MapFootprint = MapFootprint.new(3, 2, PackedByteArray(), true)
	var bb: int = m.occupy(11, dock, 10, 10, 1)
	t.eq(bb, (10 << 24) | (10 << 16) | (11 << 8) | 12, "rotated 3x2 covers 2 wide x 3 tall")
	t.eq(m.structure_at(m.idx(11, 12)), 11, "cell")
	t.eq(m.structure_at(m.idx(12, 10)), -1, "outside")
	t.eq(m.vacate(11), bb, "vacate")
	var fixed: MapFootprint = MapFootprint.new(3, 2, PackedByteArray(), false)
	t.eq(m.occupy(12, fixed, 10, 10, 1), (10 << 24) | (10 << 16) | (12 << 8) | 11, "non-rotatable ignores orient")
	t.expect_errors(2)
	t.eq(m.occupy(13, fixed, 31, 31, 0), -1, "outside the map")
	t.eq(m.occupy(14, null, 5, 5, 0), -1, "null footprint")


func test_fair_slot_order(t: TestCtx) -> void:
	var m: MapData = MapData.create(Fx.tt(), 32)
	m.spawns = PackedInt32Array([
		0, 16 * 32 + 28, 0, 0, 0, 0,
		1, 4 * 32 + 16, 0, 0, 1, 0,
		2, 16 * 32 + 4, 0, 0, 0, 0,
		3, 28 * 32 + 16, 0, 0, 1, 0])
	m.finalize()
	t.eq(m.fair_slot_order(1), PackedInt32Array([0]), "one player")
	t.eq(m.fair_slot_order(2), PackedInt32Array([0, 2]), "opposite corner")
	t.eq(m.fair_slot_order(3), PackedInt32Array([0, 2, 1]), "tie -> lowest index")
	t.eq(m.fair_slot_order(4), PackedInt32Array([0, 2, 1, 3]), "all")
	t.eq(m.fair_slot_order(9), PackedInt32Array([0, 2, 1, 3]), "capped by the slot count")
