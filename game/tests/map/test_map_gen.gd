extends RefCounted
## TM-07 / U1, U15, U18 + phase A: params, tables, integer noise, symmetry primitives, terrain families, determinism,
## timing. (Generator layout / validation belong to TM-08.)

const Fixture := preload("res://tests/fixtures/fixture_move_table.gd")


func _tt() -> MapTerrain:
	return MapTerrain.from_dict(Fixture.terrain_dict(), Fixture.make())


func _cfg(family: int, size: int, slots: int, sd: int, params: Dictionary = {}) -> MapGenParams:
	return MapGenParams.from_config({"family": family, "size": size, "layout_players": slots, "seed": sd, "params": params})


func _phase_a(family: int, size: int, slots: int, sd: int, params: Dictionary = {}) -> MapGenTerrain:
	var p: MapGenParams = _cfg(family, size, slots, sd, params)
	return MapGenTerrain.generate(_tt(), p, MapGenTables.load_default(), sd)


func _digest(g: MapGenTerrain) -> int:
	return Checksum.mix(Checksum.mix(Checksum.digest32_bytes(g.terrain_base), Checksum.digest32_bytes(g.flags_base)),
		Checksum.mix(Checksum.digest32_bytes(g.height), Checksum.digest32_bytes(g.moisture)))


# ---- U1 ---------------------------------------------------------------------------------------------------------

func test_u1_noise_vectors(t: TestCtx) -> void:
	t.eq(MapGenNoise.mix32(0, 0, 0), 3469031917, "mix32 0,0,0")
	t.eq(MapGenNoise.mix32(1, 0, 0), 2814734143, "mix32 1,0,0")
	t.eq(MapGenNoise.mix32(17, 42, 12345), 414332277, "mix32 17,42,12345")
	t.eq(MapGenNoise.mix32(-5, 7, 99), 1917552722, "mix32 -5,7,99")
	t.eq(MapGenNoise.mix32(4100, 4200, 2147483647), 3329929251, "mix32 big seed")
	t.eq(MapGenNoise.vnoise(100, 200, 5, 777), 36241, "vnoise 1")
	t.eq(MapGenNoise.vnoise(-37, 91, 4, 5), 19981, "vnoise negative x")
	t.eq(MapGenNoise.fbm(4106, 4116, 1234, 5), 25507, "fbm 1")
	t.eq(MapGenNoise.fbm(0, 0, 1, 6), 20787, "fbm 2")


func test_u1_cached_field_equals_reference(t: TestCtx) -> void:
	var fb: MapGenNoise.Field = MapGenNoise.Field.fbm_field(-40, 300, -70, 250, 4242, 5)
	var fv: MapGenNoise.Field = MapGenNoise.Field.vnoise_field(-40, 300, -70, 250, 4, 99)
	var bad: int = 0
	for k: int in 3000:
		var x: int = -40 + MapGenNoise.mix32(k, 1, 7) % 341
		var y: int = -70 + MapGenNoise.mix32(k, 2, 7) % 321
		if fb.at(x, y) != MapGenNoise.fbm(x, y, 4242, 5):
			bad += 1
		if fv.at(x, y) != MapGenNoise.vnoise(x, y, 4, 99):
			bad += 1
	t.eq(bad, 0, "cached field == reference (fbm and vnoise, incl. negative coordinates)")
	var edge: MapGenNoise.Field = MapGenNoise.Field.fbm_field(0, 255, 0, 255, 5, 6)
	t.eq(edge.at(255, 255), MapGenNoise.fbm(255, 255, 5, 6), "domain corner")
	t.eq(edge.at(0, 0), MapGenNoise.fbm(0, 0, 5, 6), "domain origin")


func test_thresholds(t: TestCtx) -> void:
	var h: PackedInt32Array = PackedInt32Array()
	h.resize(256)
	for k: int in 256:
		h[k] = 4
	# 1024 values, top 100 => t where count(>t) <= 100: values 231..255 are 25*4 = 100 above 230
	t.eq(MapGenNoise.top_threshold(h, 100), 230, "top_threshold")
	t.eq(MapGenNoise.top_threshold(h, 0), 255, "top 0 => nothing above")
	t.eq(MapGenNoise.low_threshold(h, 100), 24, "low_threshold: 25 bins * 4 = 100 values <= 24")
	t.eq(MapGenNoise.low_threshold(h, 1), 0, "low 1")


# ---- U18 --------------------------------------------------------------------------------------------------------

func test_u18_params(t: TestCtx) -> void:
	t.eq(MapGenParams.validate_basic(0, 96, 2), "", "96/2 ok")
	t.ne(MapGenParams.validate_basic(0, 96, 4), "", "96/4 => size error")
	t.check(MapGenParams.validate_basic(0, 96, 4).contains("size"), "size error text")
	t.eq(MapGenParams.validate_basic(1, 100, 2), "size must be a multiple of 8", "multiple of 8")
	t.check(MapGenParams.validate_basic(3, 128, 2).contains("family"), "family error")
	t.ne(MapGenParams.validate_basic(0, 264, 2), "", "too big")
	t.ne(MapGenParams.validate_basic(0, 128, 5), "", "bad slots")
	var mins: Dictionary = {2: 96, 3: 112, 4: 128, 6: 160, 8: 192}
	for k: int in mins:
		t.eq(MapGenParams.min_size(k), mins[k], "min_size %d" % k)
	t.eq(MapGenParams.recommended_size(2), 128, "rec 2")
	t.eq(MapGenParams.recommended_size(5), 192, "rec 5")
	t.eq(MapGenParams.recommended_size(8), 224, "rec 8")
	t.eq(MapGenParams.slots_for(5), 6, "slots_for 5")
	t.eq(MapGenParams.slots_for(7), 8, "slots_for 7")
	var a: MapGenParams = MapGenParams.from_config({"family": 2, "layout_players": 4, "params": {"water_pct": 30, "bogus": 5},
		"seed": 20240517, "size": 128, "unknown": "x"})
	t.eq(a.family, 2, "family")
	t.eq(a.slots, 4, "slots")
	t.eq(a.size, 128, "size")
	t.eq(a.seed_value, 20240517, "seed")
	t.eq(a.water_pct, 30, "water_pct")
	t.eq(a.density, -1, "density default = family")
	t.eq(a.validate(), "", "valid")
	# unknown keys do not change the canonical ints
	var b: MapGenParams = MapGenParams.from_config({"family": 2, "layout_players": 4, "params": {"water_pct": 30},
		"seed": 20240517, "size": 128})
	t.eq(a.to_ints(), b.to_ints(), "unknown keys ignored")
	var c: MapGenParams = MapGenParams.from_config({"family": 2, "layout_players": 4, "params": {"water_pct": 31},
		"seed": 20240517, "size": 128})
	t.ne(a.to_ints(), c.to_ints(), "known key changes ints")
	var big: MapGenParams = MapGenParams.from_config({"seed": 4294967295.0})
	t.eq(big.seed_value, 4294967295, "float json seed")
	t.eq(big.to_ints()[3], -1, "seed low 32 bits as int32")
	t.ne(MapGenParams.from_config({"params": {"density": 101}}).validate(), "", "density range")
	var tb: MapGenTables = MapGenTables.load_default()
	t.eq(_cfg(2, 128, 2, 1).effective_density(tb), 40, "coast density default")
	t.eq(_cfg(0, 128, 2, 1).effective_density(tb), 50, "open density default")
	t.eq(_cfg(2, 128, 2, 1).effective_water_pct(tb), 22, "coast water default")
	t.eq(_cfg(2, 128, 2, 1, {"water_pct": 5}).effective_water_pct(tb), 5, "explicit water")


# ---- tables -----------------------------------------------------------------------------------------------------

func test_tables(t: TestCtx) -> void:
	var tb: MapGenTables = MapGenTables.load_default()
	if not t.not_null(tb, "map_gen.json loads"):
		return
	t.eq(tb.gen_version, MapGenParams.VERSION, "gen_version")
	t.eq(tb.lay("rim_w"), MapData.RIM_W, "rim")
	t.eq(tb.lay("moat_r_pct"), 26, "moat")
	t.eq(tb.fam_water_pct(2), 22, "coast water")
	t.check(tb.fam_terraces(0) and not tb.fam_terraces(1) and tb.fam_terraces(2), "terraces")
	t.check(tb.fam_moat(2) and not tb.fam_moat(0), "moat flag")
	t.eq(tb.street_w, 4, "street")
	t.eq(tb.avenue_w, 6, "avenue")
	t.eq(tb.biome_base[1], MapTerrain.T_DIRT, "arid base")
	t.eq(tb.biome_sand_pm[1], 180, "arid sand")
	var gar: int = tb.neutral_row_of("neutral.civilian_garrison")
	t.eq(tb.neutral_count(gar, 1, 192), 9, "urban garrisons 6+192/64")
	t.eq(tb.neutral_count(gar, 0, 192), 2, "open garrisons")
	t.check(tb.neutral_is_per_map(tb.neutral_row_of("neutral.salvage_depot"), 0), "depot per map")
	var hb: int = tb.neutral_row_of("neutral.harbor_terminal")
	t.eq(tb.neutral_count(hb, 2, 128), 1, "harbor terminal on coast")
	t.eq(tb.neutral_count(hb, 0, 128), 0, "no harbor on open")
	t.eq(tb.neutral_row_of("nope"), -1, "unknown neutral")
	t.eq(MapGenTables.load_default().table_hash(), tb.table_hash(), "stable hash")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MapGenTables.PATH)) as Dictionary
	var again: MapGenTables = MapGenTables.from_dict(d)
	t.eq(again.table_hash(), tb.table_hash(), "hash of a re-parse")
	(d["layout"] as Dictionary)["moat_r_pct"] = 27
	t.ne(MapGenTables.from_dict(d).table_hash(), tb.table_hash(), "value change changes hash")
	d["gen_version"] = 3
	t.check(MapGenTables.error_of(d).contains("gen_version"), "gen_version mismatch rejected")
	d["gen_version"] = 2
	d.erase("bay")
	t.check(MapGenTables.error_of(d).contains("bay"), "missing section reported")


# ---- U15 --------------------------------------------------------------------------------------------------------

## Cell set -> sorted membership dictionary of cell index (test helper only).
func _set_of(a: PackedInt32Array) -> Dictionary:
	var d: Dictionary = {}
	for c: int in a:
		d[c] = true
	return d


func _brute(sym: MapGenSymmetry, kind: int, k: int, p: PackedInt32Array) -> Dictionary:
	# independent scan over the WHOLE interior with the analytic predicate on the transformed control points
	var out: Dictionary = {}
	var w: int = sym.size
	var px: int = sym.img_x(k, p[0], p[1])
	var py: int = sym.img_y(k, p[0], p[1])
	var qx: int = 0
	var qy: int = 0
	if kind == 1:
		qx = sym.img_x(k, p[2], p[3])
		qy = sym.img_y(k, p[2], p[3])
	for y: int in range(MapData.RIM_W, w - MapData.RIM_W):
		for x: int in range(MapData.RIM_W, w - MapData.RIM_W):
			var cx: int = 2 * x + 1 - w
			var cy: int = 2 * y + 1 - w
			var hit: bool = false
			if kind == 0:
				var dx: int = cx - px
				var dy: int = cy - py
				hit = dx * dx + dy * dy <= 4 * p[2] * p[2]
			elif kind == 1:
				var ex: int = qx - px
				var ey: int = qy - py
				var den: int = ex * ex + ey * ey
				var rx: int = cx - px
				var ry: int = cy - py
				var num: int = rx * ex + ry * ey
				var h2: int = p[4] * p[4]
				if num <= 0:
					hit = rx * rx + ry * ry <= h2
				elif num >= den:
					hit = (cx - qx) * (cx - qx) + (cy - qy) * (cy - qy) <= h2
				else:
					var cr: int = rx * ey - ry * ex
					hit = cr * cr <= h2 * den
			else:
				var hx: int = p[3] if sym.img_swaps(k) else p[2]
				var hy: int = p[2] if sym.img_swaps(k) else p[3]
				hit = absi(cx - px) <= hx and absi(cy - py) <= hy
			if hit:
				out[y * w + x] = true
	return out


func _paint(sym: MapGenSymmetry, kind: int, k: int, p: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if kind == 0:
		sym.paint_disc(k, p[0], p[1], p[2], out)
	elif kind == 1:
		sym.paint_segment(k, p[0], p[1], p[2], p[3], p[4], out)
	else:
		sym.paint_rect2(k, p[0], p[1], p[2], p[3], out)
	return out


func _random_prim(sym: MapGenSymmetry, kind: int, i: int) -> PackedInt32Array:
	var w: int = sym.size
	var span: int = w - 2 * MapData.RIM_W  # doubled offsets stay near the interior
	var p: PackedInt32Array = PackedInt32Array()
	var r: int = MapGenNoise.mix32(i, kind, 5)
	var cx: int = (r % (2 * span)) - span + 1
	var cy: int = ((r >> 12) % (2 * span)) - span + 1
	if (cx & 1) == 0:
		cx += 1
	if (cy & 1) == 0:
		cy += 1
	p.append(cx)
	p.append(cy)
	if kind == 0:
		p.append(2 + (r >> 20) % 12)
	elif kind == 1:
		var bx: int = cx + ((MapGenNoise.mix32(i, kind, 6) % 80) - 40)
		var by: int = cy + ((MapGenNoise.mix32(i, kind, 7) % 80) - 40)
		p.append(bx)
		p.append(by)
		p.append(2 + (r >> 20) % 12)
	else:
		p.append(2 + (r >> 20) % 16)
		p.append(2 + (r >> 24) % 16)
	return p


func test_u15_symmetry_primitives(t: TestCtx) -> void:
	var bad: int = 0
	var checked: int = 0
	for slots: int in [2, 4, 8]:
		var sym: MapGenSymmetry = MapGenSymmetry.new(slots, 128)
		for i: int in 200:
			var kind: int = i % 3
			var prim: PackedInt32Array = _random_prim(sym, kind, i)
			var base: PackedInt32Array = _paint(sym, kind, 0, prim)
			for k: int in range(1, sym.images):
				var got: PackedInt32Array = _paint(sym, kind, k, prim)
				# mirror-image check: every cell of image 0, mapped through the image transform, is in image k
				var have: Dictionary = _set_of(got)
				var mapped: int = 0
				for c: int in base:
					var x2: int = sym.to2(c % 128)
					var y2: int = sym.to2(c / 128)
					var mx: int = sym.cell_of2(sym.img_x(k, x2, y2))
					var my: int = sym.cell_of2(sym.img_y(k, x2, y2))
					if not have.has(my * 128 + mx):
						mapped += 1
				checked += 1
				if mapped != 0 or got.size() != base.size():
					bad += 1
	t.eq(bad, 0, "D1X/D2/D4: image sets are exact mirror images (%d comparisons)" % checked)


func test_u15_rotation_hole_free(t: TestCtx) -> void:
	var bad: int = 0
	for slots: int in [3, 6]:
		var sym: MapGenSymmetry = MapGenSymmetry.new(slots, 128)
		for i: int in 40:
			var kind: int = i % 3
			var prim: PackedInt32Array = _random_prim(sym, kind, i + 1000)
			for k: int in range(0, sym.images):
				var got: Dictionary = _set_of(_paint(sym, kind, k, prim))
				var want: Dictionary = _brute(sym, kind, k, prim)
				if got.size() != want.size():
					bad += 1
					continue
				for c: Variant in want:
					if not got.has(c):
						bad += 1
						break
	t.eq(bad, 0, "DN images cover exactly the analytic shape (no holes)")


func test_symmetry_basics(t: TestCtx) -> void:
	var s2: MapGenSymmetry = MapGenSymmetry.new(2, 128)
	t.eq(s2.img_x(1, 5, 7), -5, "D1X mirror x")
	t.eq(s2.img_y(1, 5, 7), 7, "D1X keeps y")
	t.eq(s2.cell_of2(s2.to2(10)), 10, "cell round trip")
	var order: PackedInt32Array = s2.start_order()
	t.eq(order.size(), 2, "2 starts")
	t.gt(s2.img_x(order[0], s2.start_x2(), s2.start_y2()), 0, "start 0 is east")
	t.lt(s2.img_x(order[1], s2.start_x2(), s2.start_y2()), 0, "start 1 is west")
	for slots: int in [3, 4, 6, 8]:
		var sy: MapGenSymmetry = MapGenSymmetry.new(slots, 192)
		var sorder: PackedInt32Array = sy.start_order()
		var seen: Dictionary = {}
		for k: int in sorder:
			seen[k] = true
		t.eq(seen.size(), slots, "order is a permutation, slots=%d" % slots)
	# fold: mirror images fold to the same point
	var sd: MapGenSymmetry = MapGenSymmetry.new(8, 128)
	var bad: int = 0
	for i: int in 200:
		var x2: int = 2 * (MapGenNoise.mix32(i, 1, 1) % 100) - 99
		var y2: int = 2 * (MapGenNoise.mix32(i, 2, 1) % 100) - 99
		var f0: int = sd.fold(x2, y2)
		for k: int in 8:
			if sd.fold(sd.img_x(k, x2, y2), sd.img_y(k, x2, y2)) != f0:
				bad += 1
	t.eq(bad, 0, "D4 fold is invariant under all 8 images")


# ---- phase A ----------------------------------------------------------------------------------------------------

func _mirror_mismatch(g: MapGenTerrain) -> int:
	var w: int = g.size
	var sym: MapGenSymmetry = g.sym
	var bad: int = 0
	for y: int in w:
		for x: int in w:
			var x2: int = sym.to2(x)
			var y2: int = sym.to2(y)
			var i: int = y * w + x
			for k: int in range(1, sym.images):
				var j: int = sym.cell_of2(sym.img_y(k, x2, y2)) * w + sym.cell_of2(sym.img_x(k, x2, y2))
				if g.terrain_base[i] != g.terrain_base[j] or g.flags_base[i] != g.flags_base[j] or g.height[i] != g.height[j]:
					bad += 1
	return bad


func test_phase_a_exact_symmetry(t: TestCtx) -> void:
	for fam: int in 3:
		for slots: int in [2, 4, 8]:
			var g: MapGenTerrain = _phase_a(fam, 96 if slots < 8 else 192, slots, 777 + fam)
			t.eq(_mirror_mismatch(g), 0, "family %d slots %d: terrain/flags/height are bit-symmetric" % [fam, slots])


func test_phase_a_rotation_near_symmetry(t: TestCtx) -> void:
	for fam: int in 3:
		for slots: int in [3, 6]:
			var g: MapGenTerrain = _phase_a(fam, 112 if slots == 3 else 160, slots, 31 + fam)
			var bad: int = 0
			var total: int = 0
			var w: int = g.size
			for y: int in range(0, w, 3):
				for x: int in range(0, w, 3):
					var x2: int = g.sym.to2(x)
					var y2: int = g.sym.to2(y)
					var k: int = 1
					if (x2 * x2 + y2 * y2) > (w - 12) * (w - 12):
						continue  # corners rotate out of the square map
					var j: int = g.sym.cell_of2(g.sym.img_y(k, x2, y2)) * w + g.sym.cell_of2(g.sym.img_x(k, x2, y2))
					total += 1
					if g.terrain_base[y * w + x] != g.terrain_base[j]:
						bad += 1
			t.le(bad * 100, total * 25, "family %d slots %d: <= 25%% class mismatches (got %d of %d)" % [fam, slots, bad, total])


func _count(g: MapGenTerrain, types: Array) -> int:
	var c: int = 0
	for b: int in g.terrain_base:
		if types.has(b):
			c += 1
	return c


func test_phase_a_open(t: TestCtx) -> void:
	var g: MapGenTerrain = _phase_a(0, 128, 4, 5)
	t.eq(_count(g, [MapTerrain.T_DEEP, MapTerrain.T_SHALLOW, MapTerrain.T_FORD, MapTerrain.T_BEACH, MapTerrain.T_MARSH]), 0, "no water/beach/marsh at water_pct 0")
	t.gt(_count(g, [MapTerrain.T_FOREST]), 500, "forest present")
	t.gt(_count(g, [MapTerrain.T_ROCK]), 100, "rock present")
	t.gt(_count(g, [MapTerrain.T_CLIFF]), 300, "cliffs present (rim + terraces)")
	t.gt(_count(g, [MapTerrain.T_GRASS]), 3000, "grass base")
	t.eq(g.terrain_base[0], MapTerrain.T_MOUNTAIN, "rim corner is mountain")
	t.eq(g.terrain_base[3 * 128 + 64], MapTerrain.T_CLIFF, "rim band cliff")
	var ramps: int = 0
	var inner_cliffs: int = 0
	for y: int in range(6, 122):
		for x: int in range(6, 122):
			if g.terrain_base[y * 128 + x] == MapTerrain.T_CLIFF:
				inner_cliffs += 1
	t.gt(inner_cliffs, 50, "terrace cliffs inside the playable area")
	for f: int in g.flags_base:
		if (f & MapData.SF_RAMP) != 0:
			ramps += 1
	t.gt(ramps, 5, "ramps exist")
	# forest coverage ~ 3 * density permille of the map
	var forest: int = _count(g, [MapTerrain.T_FOREST])
	t.check(forest * 1000 <= 3 * 50 * g.n + g.n, "forest not above 15 %")
	# arid biome
	var a: MapGenTerrain = _phase_a(0, 128, 2, 5, {"biome": 1})
	t.gt(_count(a, [MapTerrain.T_SAND]), 1000, "arid sand")
	t.eq(_count(g, [MapTerrain.T_SAND]), 0, "temperate has no sand")


func test_phase_a_urban(t: TestCtx) -> void:
	var g: MapGenTerrain = _phase_a(1, 128, 4, 9)
	var roads: int = _count(g, [MapTerrain.T_ROAD])
	t.gt(roads, 3000, "streets")
	t.gt(_count(g, [MapTerrain.T_URBAN]), 3000, "blocks")
	t.gt(_count(g, [MapTerrain.T_PAVEMENT]), 100, "plazas / alleys")
	t.gt(_count(g, [MapTerrain.T_GRASS]), 100, "parks")
	t.gt(_count(g, [MapTerrain.T_RUBBLE]), 10, "rubble")
	t.eq(_count(g, [MapTerrain.T_FOREST, MapTerrain.T_DEEP, MapTerrain.T_SHALLOW, MapTerrain.T_ROCK]), 0, "no forest / water / rock")
	t.eq(g.plateau.count(1), 0, "no terraces in urban")
	# 4-wide streets: a horizontal run of ROAD of length >= 4 exists
	var run: int = 0
	var best: int = 0
	for x: int in range(6, 122):
		if g.terrain_base[64 * 128 + x] == MapTerrain.T_ROAD or g.terrain_base[64 * 128 + x] == MapTerrain.T_RUBBLE:
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	t.gt(best, 3, "a street at least 4 cells wide crosses row 64")
	t.eq(g.make_map().biome, 3, "urban forces biome 3")


func test_phase_a_coast(t: TestCtx) -> void:
	var g: MapGenTerrain = _phase_a(2, 128, 4, 13)
	var deep: int = _count(g, [MapTerrain.T_DEEP])
	t.gt(deep, 128 * 128 * 10 / 100, "sea + moat")
	t.gt(_count(g, [MapTerrain.T_SHALLOW]), 200, "shallows")
	t.gt(_count(g, [MapTerrain.T_MARSH]), 50, "marsh fringe")
	# rim is DEEP for coast
	t.eq(g.terrain_base[0], MapTerrain.T_DEEP, "coast rim corner deep")
	t.eq(g.terrain_base[5 * 128 + 5], MapTerrain.T_DEEP, "coast rim band deep")
	t.gt(_count(g, [MapTerrain.T_GRASS, MapTerrain.T_DIRT]), 2000, "land")
	# marsh only within 3 cells (Chebyshev) of water
	var w: int = 128
	var bad: int = 0
	for y: int in range(4, w - 4):
		for x: int in range(4, w - 4):
			if g.terrain_base[y * w + x] != MapTerrain.T_MARSH:
				continue
			var near: bool = false
			for dy: int in range(-3, 4):
				for dx: int in range(-3, 4):
					var b: int = g.terrain_base[(y + dy) * w + x + dx]
					if b == MapTerrain.T_DEEP or b == MapTerrain.T_SHALLOW:
						near = true
			if not near:
				bad += 1
	t.eq(bad, 0, "every marsh cell has water within 3 cells")
	# playable-interior water share is at least the 22 % percentile (moat adds a little)
	var wet: int = 0
	for y: int in range(6, 122):
		for x: int in range(6, 122):
			var b: int = g.terrain_base[y * w + x]
			if b == MapTerrain.T_DEEP or b == MapTerrain.T_SHALLOW:
				wet += 1
	t.check(wet * 100 >= 20 * 116 * 116 and wet * 100 <= 45 * 116 * 116, "interior water share 20..45 %% (got %d of %d)" % [wet, 116 * 116])
	t.gt(_count(g, [MapTerrain.T_DEEP]) - 128 * 128 + 116 * 116, 0, "deep water beyond the rim")
	t.gt(_count(g, [MapTerrain.T_SHALLOW]), _count(g, [MapTerrain.T_DEEP]) / 10, "shallow shore ring exists")
	var wpc: MapGenTerrain = _phase_a(2, 128, 2, 13, {"water_pct": 40})
	t.gt(_count(wpc, [MapTerrain.T_DEEP, MapTerrain.T_SHALLOW]), _count(g, [MapTerrain.T_DEEP, MapTerrain.T_SHALLOW]), "more water_pct => more water")


func test_phase_a_map_and_finalize(t: TestCtx) -> void:
	var g: MapGenTerrain = _phase_a(2, 96, 2, 3)
	var m: MapData = g.make_map()
	t.eq(m.family, 2, "family")
	t.eq(m.gen_version, MapGenParams.VERSION, "gen_version")
	t.eq(m.gen_params, _cfg(2, 96, 2, 3).to_ints(), "gen_params")
	t.eq(m.terrain, g.terrain_base, "terrain copied")
	t.check((m.flags[0] & MapData.SF_NOBUILD) != 0, "rim nobuild")
	m.finalize()
	t.check(m.is_finalized(), "finalizes")
	t.gt(m.water_size.size(), 0, "water components derived")


func test_phase_a_determinism(t: TestCtx) -> void:
	for fam: int in 3:
		var a: MapGenTerrain = _phase_a(fam, 128, 6 if fam == 1 else 4, 424242)
		var b: MapGenTerrain = _phase_a(fam, 128, 6 if fam == 1 else 4, 424242)
		t.eq(_digest(a), _digest(b), "double run identical, family %d" % fam)
		var c: MapGenTerrain = _phase_a(fam, 128, 6 if fam == 1 else 4, 424243)
		t.ne(_digest(a), _digest(c), "seed changes the map, family %d" % fam)
	# thread safety / purity: interleaved generation of two configs does not disturb either
	var x1: int = _digest(_phase_a(2, 96, 2, 8))
	var _y: int = _digest(_phase_a(0, 96, 3, 9))
	t.eq(_digest(_phase_a(2, 96, 2, 8)), x1, "no hidden state between runs")


func test_phase_a_progress(t: TestCtx) -> void:
	var plog: Array = []
	var cb: Callable = func(stage: int, pct: int) -> void: plog.append([stage, pct])
	var p: MapGenParams = _cfg(0, 96, 2, 1)
	MapGenTerrain.generate(_tt(), p, MapGenTables.load_default(), 1, cb)
	t.gt(plog.size(), 5, "progress reported")
	var last: int = -1
	var mono: bool = true
	for e: Array in plog:
		var pct: int = e[1] as int
		if pct < last:
			mono = false
		last = pct
	t.check(mono, "pct monotonic")
	t.le(last, 64, "phase A stays within 0..64")


func test_phase_a_timing(t: TestCtx) -> void:
	var worst: int = 0
	var lines: PackedStringArray = PackedStringArray()
	for spec: Array in [[0, 2], [0, 4], [0, 8], [0, 6], [1, 2], [2, 2], [2, 3], [2, 8]]:
		var p: MapGenParams = _cfg(spec[0] as int, 192, spec[1] as int, 12345)
		var tb: MapGenTables = MapGenTables.load_default()
		var tt: MapTerrain = _tt()
		var t0: int = Time.get_ticks_usec()
		MapGenTerrain.generate(tt, p, tb, 12345)
		var ms: int = (Time.get_ticks_usec() - t0) / 1000
		worst = maxi(worst, ms)
		lines.append("fam%d/s%d=%dms" % [spec[0], spec[1], ms])
	t.note("phase A at 192x192: " + ", ".join(lines))
	t.lt(worst, 1500, "phase A worst case at 192^2 (target 500 ms unloaded; loose bound for loaded CI)")
