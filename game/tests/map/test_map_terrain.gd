extends RefCounted
## TM-01 / U2: terrain tables, loader schema errors, enum mirrors, table_hash.

const Fixture := preload("res://tests/fixtures/fixture_move_table.gd")


func _tt() -> MapTerrain:
	return MapTerrain.from_dict(Fixture.terrain_dict(), Fixture.make())


func test_kinds(t: TestCtx) -> void:
	var tt: MapTerrain = _tt()
	if not t.not_null(tt, "loads"):
		return
	var want: Dictionary = {
		MapTerrain.T_DEEP: 6, MapTerrain.T_SHALLOW: 5, MapTerrain.T_FORD: 5, MapTerrain.T_BEACH: 1,
		MapTerrain.T_GRASS: 1, MapTerrain.T_DIRT: 1, MapTerrain.T_SAND: 1, MapTerrain.T_ROCK: 2,
		MapTerrain.T_RUBBLE: 2, MapTerrain.T_FOREST: 3, MapTerrain.T_ROAD: 0, MapTerrain.T_PAVEMENT: 0,
		MapTerrain.T_URBAN: 7, MapTerrain.T_CLIFF: 7, MapTerrain.T_MOUNTAIN: 7, MapTerrain.T_MARSH: 4}
	for k: int in want:
		t.eq(tt.kind_of(k), want[k], "kind_of(%d)" % k)
	t.eq(tt.flags(MapTerrain.T_FORD), MapTerrain.TF_WATER | MapTerrain.TF_CROSSING, "ford flags")
	t.eq(tt.flags(MapTerrain.T_GRASS), MapTerrain.TF_LAND | MapTerrain.TF_BUILD, "grass flags")
	t.eq(tt.flags(MapTerrain.T_BEACH), MapTerrain.TF_LAND | MapTerrain.TF_BUILD_SHORE, "beach flags")
	t.eq(tt.minimap_rgba(MapTerrain.T_DEEP), 0x0D2F6BFF, "minimap")


func test_weights_and_steps(t: TestCtx) -> void:
	var tt: MapTerrain = _tt()
	if not t.not_null(tt, "loads"):
		return
	t.eq(tt.weight(MapTerrain.NP_TRACKED, MapTerrain.T_ROAD), 15, "tracked road")
	t.eq(tt.weight(MapTerrain.NP_WHEELED, MapTerrain.T_ROAD), 12, "wheeled road")
	t.eq(tt.weight(MapTerrain.NP_WHEELED, MapTerrain.T_FOREST), 0, "wheeled forest")
	t.eq(tt.weight(MapTerrain.NP_TRACKED, MapTerrain.T_FOREST), 29, "tracked forest")
	t.eq(tt.weight(MapTerrain.NP_FOOT, MapTerrain.T_FOREST), 23, "foot forest")
	t.eq(tt.weight(MapTerrain.NP_WHEELED, MapTerrain.T_MARSH), 40, "wheeled marsh clamp")
	t.eq(tt.weight(MapTerrain.NP_WHEELED, MapTerrain.T_SHALLOW), 32, "wheeled shallow")
	t.eq(tt.weight(MapTerrain.NP_AMPH, MapTerrain.T_DEEP), 23, "amph deep")
	t.eq(tt.weight(MapTerrain.NP_NAVAL, MapTerrain.T_SHALLOW), 20, "naval shallow")
	t.eq(tt.weight(MapTerrain.NP_NAVAL_DEEP, MapTerrain.T_SHALLOW), 0, "naval deep blocks shallow")
	t.eq(tt.weight(MapTerrain.NP_NAVAL_DEEP, MapTerrain.T_DEEP), 16, "naval deep deep")
	t.eq(tt.weight(MapTerrain.NP_SUB, MapTerrain.T_DEEP), 16, "sub deep")
	t.eq(tt.weight(MapTerrain.NP_FOOT, MapTerrain.T_GRASS), 16, "baseline")
	t.eq(tt.weight(MapTerrain.NP_FOOT, MapTerrain.T_CLIFF), 0, "cliff blocked")
	t.eq(tt.weight(MapTerrain.NP_FOOT, MapTerrain.T_DEEP), 0, "foot deep blocked")
	t.eq(tt.weight(MapTerrain.NP_NAVAL, MapTerrain.T_GRASS), 0, "naval land blocked")
	# the whole 4.2 table
	var tab: Dictionary = {
		MapTerrain.T_ROCK: [20, 29, 20, 21, 0, 0, 0], MapTerrain.T_MARSH: [27, 40, 29, 20, 0, 0, 0],
		MapTerrain.T_FORD: [23, 32, 25, 18, 20, 0, 0], MapTerrain.T_PAVEMENT: [15, 12, 15, 15, 0, 0, 0],
		MapTerrain.T_DEEP: [0, 0, 0, 23, 16, 16, 16], MapTerrain.T_URBAN: [0, 0, 0, 0, 0, 0, 0]}
	for k: int in tab:
		for np: int in MapTerrain.NP_COUNT:
			t.eq(tt.weight(np, k), (tab[k] as Array)[np], "table t=%d np=%d" % [k, np])
	t.eq(tt.step_o(16), 10, "step_o 16")
	t.eq(tt.step_d(16), 14, "step_d 16")
	t.eq(tt.step_o(23), 14, "step_o 23")
	t.eq(tt.step_o(12), 8, "step_o 12")
	t.eq(tt.step_d(12), 11, "step_d 12")
	t.eq(tt.step_o(40), 25, "step_o 40")
	t.eq(tt.step_d(40), 35, "step_d 40")
	t.eq(tt.step_o(0), 0, "step_o 0")
	t.eq(tt.speed_bp(MapTerrain.MC_WHEELED, MapTerrain.T_ROAD), 13000, "speed_bp")
	t.eq(tt.speed_bp(MapTerrain.MC_AIR_FIXED, MapTerrain.T_CLIFF), 10000, "air speed")


func test_profiles_and_sizes(t: TestCtx) -> void:
	t.eq(MapTerrain.nav_size(MapTerrain.MC_FOOT, 410), MapTerrain.SZ_1, "foot")
	t.eq(MapTerrain.nav_size(MapTerrain.MC_WHEELED, 461), MapTerrain.SZ_2, "wheeled")
	t.eq(MapTerrain.nav_size(MapTerrain.MC_TRACKED, 1024), MapTerrain.SZ_2, "tracked")
	t.eq(MapTerrain.nav_size(MapTerrain.MC_NAVAL, 1434), MapTerrain.SZ_3, "large hull")
	t.eq(MapTerrain.nav_size(MapTerrain.MC_NAVAL, 614), MapTerrain.SZ_2, "small hull")
	t.eq(MapTerrain.profile_of(MapTerrain.MC_NAVAL, 614), MapTerrain.NP_NAVAL, "small naval")
	t.eq(MapTerrain.profile_of(MapTerrain.MC_NAVAL, 1024), MapTerrain.NP_NAVAL_DEEP, "big naval")
	t.eq(MapTerrain.profile_of(MapTerrain.MC_AIR_FIXED, 500), MapTerrain.NP_NONE, "air")
	t.eq(MapTerrain.profile_of(MapTerrain.MC_STATIC, 500), MapTerrain.NP_NONE, "static")
	t.eq(MapTerrain.profile_of(MapTerrain.MC_AMPHIBIOUS, 500), MapTerrain.NP_AMPH, "amph")
	t.eq(MapTerrain.profile_of(MapTerrain.MC_SUBMERGED, 500), MapTerrain.NP_SUB, "sub")
	t.eq(MapTerrain.mc_of_profile(MapTerrain.NP_NAVAL_DEEP), MapTerrain.MC_NAVAL, "mc_of_profile")
	t.eq(MapTerrain.DEEP_ONLY_RADIUS, Fp.cells_to_units(900), "DEEP_ONLY_RADIUS == 0.9 cell")


func test_guarantee(t: TestCtx) -> void:
	var tt: MapTerrain = _tt()
	if not t.not_null(tt, "loads"):
		return
	t.check(tt.guarantee(MapTerrain.T_FORD), "ford")
	t.check_false(tt.guarantee(MapTerrain.T_SHALLOW), "shallow")
	t.check_false(tt.guarantee(MapTerrain.T_FOREST), "forest (wheeled blocked)")
	t.check_false(tt.guarantee(MapTerrain.T_CLIFF), "cliff")
	t.check(tt.guarantee(MapTerrain.T_GRASS), "grass")
	t.check(tt.guarantee(MapTerrain.T_MARSH), "marsh")
	# editing the table so that tracked forest = 0 changes only forest-related weights
	var mv: DefMoveTable = Fixture.make()
	mv.speed_bp[MapTerrain.MC_TRACKED * 8 + MapTerrain.TK_FOREST] = 0
	var t2: MapTerrain = MapTerrain.from_dict(Fixture.terrain_dict(), mv)
	t.eq(t2.weight(MapTerrain.NP_TRACKED, MapTerrain.T_FOREST), 0, "tracked forest now blocked")
	t.eq(t2.weight(MapTerrain.NP_FOOT, MapTerrain.T_FOREST), 23, "foot forest unchanged")
	t.eq(t2.weight(MapTerrain.NP_AMPH, MapTerrain.T_FOREST), 32, "amph forest unchanged")
	t.check_false(t2.guarantee(MapTerrain.T_FOREST), "forest still out")
	t.ne(t2.table_hash(), tt.table_hash(), "hash reacts to the table")


func test_table_hash_stable(t: TestCtx) -> void:
	var a: MapTerrain = _tt()
	var b: MapTerrain = _tt()
	t.eq(a.table_hash(), b.table_hash(), "same inputs, same hash")
	t.ge(a.table_hash(), 0, "u32")
	t.le(a.table_hash(), 0xFFFFFFFF, "u32")
	var d: Dictionary = Fixture.terrain_dict()
	((d["types"] as Array)[4] as Dictionary)["minimap"] = "000001"
	var c: MapTerrain = MapTerrain.from_dict(d, Fixture.make())
	t.eq(c.table_hash(), a.table_hash(), "minimap colour is view-only")
	# the default loader (global.json) agrees with the fixture table
	var dflt: MapTerrain = MapTerrain.load_default()
	if t.not_null(dflt, "load_default"):
		t.eq(dflt.table_hash(), a.table_hash(), "global.json speeds == TAXONOMY fixture")
		t.check(MapTerrain.load_default() == dflt, "cached")


func test_enum_mirrors(t: TestCtx) -> void:
	t.eq(MapTerrain.TK_DEEP, DefEnums.TerrainKind.DEEP, "TK_DEEP")
	t.eq(MapTerrain.TK_ROAD, DefEnums.TerrainKind.ROAD, "TK_ROAD")
	t.eq(MapTerrain.TK_CLIFF, DefEnums.TerrainKind.CLIFF, "TK_CLIFF")
	t.eq(MapTerrain.TK_COUNT, DefEnums.TerrainKind.COUNT, "TK_COUNT")
	t.eq(MapTerrain.MC_AMPHIBIOUS, DefEnums.MoveClass.AMPHIBIOUS, "MC_AMPHIBIOUS")
	t.eq(MapTerrain.MC_STATIC, DefEnums.MoveClass.STATIC, "MC_STATIC")
	t.eq(MapTerrain.MC_COUNT, DefEnums.MoveClass.COUNT, "MC_COUNT")
	t.eq(MapTerrain.COUNT, 16, "16 terrain types")


func test_schema_errors(t: TestCtx) -> void:
	t.expect_errors(9)
	var d: Dictionary = Fixture.terrain_dict()
	d["schema"] = 2
	t.is_null(MapTerrain.from_dict(d, Fixture.make()), "bad schema")
	d = Fixture.terrain_dict()
	(d["types"] as Array).pop_back()
	t.is_null(MapTerrain.from_dict(d, Fixture.make()), "15 types")
	d = Fixture.terrain_dict()
	((d["types"] as Array)[3] as Dictionary)["kind"] = "lava"
	t.is_null(MapTerrain.from_dict(d, Fixture.make()), "unknown kind")
	d = Fixture.terrain_dict()
	((d["types"] as Array)[3] as Dictionary)["id"] = 7
	t.is_null(MapTerrain.from_dict(d, Fixture.make()), "id out of order")
	d = Fixture.terrain_dict()
	((d["types"] as Array)[0] as Dictionary)["flags"] = ["land"]
	t.is_null(MapTerrain.from_dict(d, Fixture.make()), "water kind without water flag")
	d = Fixture.terrain_dict()
	((d["types"] as Array)[4] as Dictionary)["flags"] = ["land", "bogus"]
	t.is_null(MapTerrain.from_dict(d, Fixture.make()), "unknown flag")
	d = Fixture.terrain_dict()
	((d["types"] as Array)[4] as Dictionary)["buildable"] = "shore"
	t.is_null(MapTerrain.from_dict(d, Fixture.make()), "buildable contradicts flags")
	d = Fixture.terrain_dict()
	(d["weight"] as Dictionary)["min"] = 50
	t.is_null(MapTerrain.from_dict(d, Fixture.make()), "weight range")
	var mv: DefMoveTable = Fixture.make()
	mv.speed_bp = PackedInt32Array([1, 2, 3])
	t.is_null(MapTerrain.from_dict(Fixture.terrain_dict(), mv), "short speed table")
