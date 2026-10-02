extends RefCounted
## TM-08 (MG2): generator layout, view layers, validation, repair loop, template, MapGenJob. The statistical matrix
## (families x slot counts) runs MERIDIAN_MAPGEN_SEEDS seeds per cell (default 2; the spec's nightly run uses 200).

const MIN_SIZE: Dictionary = {2: 96, 3: 112, 4: 128, 6: 160, 8: 192}
const SLOT_LIST: Array[int] = [2, 3, 4, 6, 8]
const NP_CHECK: Array[int] = [MapTerrain.NP_FOOT, MapTerrain.NP_WHEELED, MapTerrain.NP_TRACKED, MapTerrain.NP_AMPH]


func _seeds() -> int:
	var v: String = OS.get_environment("MERIDIAN_MAPGEN_SEEDS")
	return v.to_int() if v != "" else 2


static func _cfg(fam: int, slots: int, size: int, sd: int, snw: bool = false, params: Dictionary = {}) -> Dictionary:
	var pr: Dictionary = params.duplicate()
	if snw:
		pr["start_near_water"] = true
	return {"family": fam, "layout_players": slots, "size": size, "seed": sd, "params": pr}


static func _seed_of(k: int) -> int:
	return 1000 + 7919 * k


static func _regions_equal(map: MapData, np: int, sz: int, cells: PackedInt32Array) -> bool:
	var r0: int = map.nav.region_id(np, sz, cells[0])
	if r0 < 0:
		return false
	for c: int in cells:
		if map.nav.region_id(np, sz, c) != r0:
			return false
	return true


func _check_map(t: TestCtx, map: MapData, fam: int, slots: int, tag: String, snw: bool, agg: PackedInt32Array) -> void:
	var w: int = map.w
	var res: Dictionary = MapGenValidate.analyze(map, true)
	t.eq((res["fails"] as PackedStringArray).size(), 0, tag + " validates: " + str(res["fails"]))
	var met: Dictionary = res["metrics"] as Dictionary
	for e: int in met["exits_per_start"] as PackedInt32Array:
		t.ge(e, 1, tag + " every start has an exit")
	t.eq(met["water_required"], false, tag + " water never required")
	t.le(met["fairness_spread_permille"] as int, MapGenValidate.SPREAD_MAX, tag + " fairness spread")
	for c: int in met["credits_reachable_per_start"] as PackedInt32Array:
		t.ge(c, 75000, tag + " reachable credits per slot")
	if snw:
		for d: int in met["dock_sites"] as PackedInt32Array:
			t.ge(d, 1, tag + " dock site per start")
	# all starts connected by land for every non-naval ground class (independent of the generator: the nav graphs)
	var starts: PackedInt32Array = PackedInt32Array()
	for k: int in map.spawns.size() / MapData.SPAWN_STRIDE:
		starts.append(map.spawns[k * MapData.SPAWN_STRIDE + 1])
	t.eq(starts.size(), slots, tag + " spawn count")
	for np: int in NP_CHECK:
		t.check(_regions_equal(map, np, MapTerrain.SZ_1 if np == MapTerrain.NP_FOOT else MapTerrain.SZ_2, starts),
			tag + " starts connected for np %d" % np)
	# no unreachable deposits / lots (wheeled, size 2)
	var r0: int = map.nav.region_id(MapTerrain.NP_WHEELED, MapTerrain.SZ_2, starts[0])
	var bad: int = 0
	var deposits: int = 0
	var sum_max: int = 0
	for i: int in map.n:
		sum_max += map.deposit_max[i]
		if map.field_of[i] != 0:
			deposits += 1
			if map.nav.region_id(MapTerrain.NP_WHEELED, MapTerrain.SZ_2, i) != r0:
				bad += 1
	t.eq(bad, 0, tag + " unreachable deposit cells")
	t.gt(deposits, 0, tag + " has deposits")
	var sum_fields: int = 0
	var per_owner: Dictionary = {}
	for f: int in map.fields.size() / MapData.FIELD_STRIDE:
		var b: int = f * MapData.FIELD_STRIDE
		sum_fields += map.fields[b + 4]
		if map.fields[b + 9] >= 0:
			per_owner[map.fields[b + 9]] = (per_owner.get(map.fields[b + 9], 0) as int) + map.fields[b + 4]
	t.eq(sum_fields, sum_max, tag + " sum deposit_max == sum fields.total")
	t.check(per_owner.size() == slots, tag + " every slot owns fields")
	var owner_vals: Array = per_owner.values()
	for v: Variant in owner_vals:
		t.eq(v, owner_vals[0], tag + " owned totals equal across slots")
	var lot_bad: int = 0
	for k: int in map.neutrals.size() / MapData.NEUTRAL_STRIDE:
		var cell: int = map.neutrals[k * MapData.NEUTRAL_STRIDE + 1]
		if map.nav.region_id(MapTerrain.NP_WHEELED, MapTerrain.SZ_2, cell) != r0 \
				and map.nav.region_id(MapTerrain.NP_FOOT, MapTerrain.SZ_1, cell) != map.nav.region_id(MapTerrain.NP_FOOT, MapTerrain.SZ_1, starts[0]):
			lot_bad += 1
	t.eq(lot_bad, 0, tag + " unreachable neutral lots")
	# land-only guarantee: dry families never contain water-ish cells
	if fam != MapGenParams.FAM_COAST:
		var wet: int = 0
		for i: int in map.n:
			var ty: int = map.terrain[i]
			if ty == MapTerrain.T_DEEP or ty == MapTerrain.T_SHALLOW or ty == MapTerrain.T_BEACH or ty == MapTerrain.T_FORD \
					or ty == MapTerrain.T_MARSH:
				wet += 1
		t.eq(wet, 0, tag + " dry family has no water/beach/ford/marsh cells")
	# neutrals: counts within +-25 % (min +-1) of the guidance
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	for k: int in map.neutrals.size() / MapData.NEUTRAL_STRIDE:
		counts[map.neutrals[k * MapData.NEUTRAL_STRIDE]] += 1
	var garr: int = (6 + w / 64) * slots if fam == MapGenParams.FAM_URBAN else 2 * slots
	var want: PackedInt32Array = PackedInt32Array([garr, slots, 1, slots, slots, slots if fam == MapGenParams.FAM_COAST else 0])
	for kind: int in 6:
		if want[kind] == 0:
			t.eq(counts[kind], 0, tag + " neutral kind %d absent" % kind)
			continue
		if kind != 5:  # a harbor terminal needs shore room: tiny islands may go without (aggregate bar below)
			t.ge(counts[kind], 1, tag + " neutral kind %d present (%d of %d)" % [kind, counts[kind], want[kind]])
		if kind == 2:
			t.eq(counts[kind], 1, tag + " one salvage depot per map")
		if not (kind == 0 and fam == MapGenParams.FAM_URBAN):  # urban garrison blocks only fit in parks / plazas
			agg[kind * 2] += counts[kind]
			agg[kind * 2 + 1] += want[kind]
	# view layers
	t.eq(map.heights.size(), (w + 1) * (w + 1), tag + " heights size")
	t.eq(map.heights[0], MapGenView.RAMP_LOW, tag + " corner ramps to -2 m")
	t.eq(map.roads.size(), 0 if fam == MapGenParams.FAM_URBAN else 2 * slots, tag + " road polylines")
	t.eq(map.water_level_u > 0, fam == MapGenParams.FAM_COAST, tag + " sea plane")
	t.eq(map.biome, 3 if fam == MapGenParams.FAM_URBAN else 0, tag + " biome")


func test_matrix_guarantees(t: TestCtx) -> void:
	var seeds: int = _seeds()
	var total: int = 0
	var first_ok: int = 0
	var ms_worst: int = 0
	var cells_run: int = 0
	var agg: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	for fam: int in 3:
		for snw_i: int in (2 if fam == MapGenParams.FAM_COAST else 1):
			for slots: int in SLOT_LIST:
				var size: int = MIN_SIZE[slots] as int
				var cell_fail: int = 0
				for k: int in seeds:
					var t0: int = Time.get_ticks_usec()
					var r: Dictionary = MapGenerator.generate_report(_cfg(fam, slots, size, _seed_of(k), snw_i == 1))
					ms_worst = maxi(ms_worst, (Time.get_ticks_usec() - t0) / 1000)
					var map: MapData = r["map"] as MapData
					var tag: String = "fam%d%s/s%d/seed%d" % [fam, "+bay" if snw_i == 1 else "", slots, k]
					total += 1
					if (r["attempts"] as int) == 1 and (r["layout_level"] as int) == 0 and not (r["template"] as bool):
						first_ok += 1
					else:
						cell_fail += 1
					t.check(not (r["template"] as bool), tag + " never falls back to the template")
					_check_map(t, map, fam, slots, tag, snw_i == 1, agg)
				t.le(cell_fail * 100, maxi(1, seeds) * 25 + 99, "cell fam%d/s%d first-attempt failures %d/%d" % [fam, slots, cell_fail, seeds])
				cells_run += 1
	t.note("matrix: %d cells, %d maps, first-attempt/level-0 success %d/%d, slowest map %d ms" % [cells_run, total, first_ok, total, ms_worst])
	t.ge(first_ok * 100, total * 90, "first-attempt success >= 90 % (spec nightly bar 99 %)")
	for kind: int in 6:
		t.check(agg[kind * 2] * 4 >= agg[kind * 2 + 1] * 3, "neutral kind %d placed %d of %d (>= 75 %%)" % [kind, agg[kind * 2], agg[kind * 2 + 1]])


func test_seed_and_param_variation(t: TestCtx) -> void:
	var a: MapData = MapGenerator.generate(_cfg(0, 4, 128, 5))
	var b: MapData = MapGenerator.generate(_cfg(0, 4, 128, 6))
	t.ne(a.map_hash(), b.map_hash(), "seed changes the map")
	var lo: MapData = MapGenerator.generate(_cfg(0, 4, 128, 5, false, {"resources": 0}))
	var hi: MapData = MapGenerator.generate(_cfg(0, 4, 128, 5, false, {"resources": 100}))
	t.eq(lo.fields[4], 16 * 600, "resources 0 => 50 % credits (rich contested field)")
	t.eq(hi.fields[4], 16 * 1800, "resources 100 => 150 % credits")
	t.eq(MapGenValidate.validate(lo).size(), 0, "resources 0 valid")
	t.eq(MapGenValidate.validate(hi).size(), 0, "resources 100 valid")
	var few: MapData = MapGenerator.generate(_cfg(0, 4, 128, 5, false, {"neutrals": 0}))
	var many: MapData = MapGenerator.generate(_cfg(0, 4, 128, 5, false, {"neutrals": 100}))
	t.lt(few.neutrals.size(), many.neutrals.size(), "neutrals scale")
	t.eq(MapGenValidate.validate(few).size() + MapGenValidate.validate(many).size(), 0, "neutral extremes valid")
	var arid: MapData = MapGenerator.generate(_cfg(0, 2, 96, 5, false, {"biome": 1}))
	t.eq(arid.biome, 1, "arid biome")
	t.eq(MapGenValidate.validate(arid).size(), 0, "arid valid")
	# clamping of a bad lobby config never returns null
	var odd: MapData = MapGenerator.generate({"family": 9, "layout_players": 5, "size": 100, "seed": 3})
	t.not_null(odd, "sanitised config still generates")
	t.eq(odd.slots, 6, "5 players => 6 slots")
	t.eq(odd.w % 8, 0, "size rounded to a multiple of 8")
	t.eq(MapGenerator.validate_params(0, 96, 2), "", "validate_params ok")
	t.ne(MapGenerator.validate_params(0, 96, 4), "", "validate_params size error")


func test_symmetry_of_layouts(t: TestCtx) -> void:
	for fam: int in 3:
		for slots: int in SLOT_LIST:
			var size: int = MIN_SIZE[slots] as int
			var map: MapData = MapGenerator.generate(_cfg(fam, slots, size, 77))
			var sym: MapGenSymmetry = MapGenSymmetry.new(slots, size)
			var skip: PackedByteArray = PackedByteArray()
			skip.resize(map.n)
			for k: int in map.neutrals.size() / MapData.NEUTRAL_STRIDE:
				var c: int = map.neutrals[k * MapData.NEUTRAL_STRIDE + 1]
				for y: int in range(c / size - 4, c / size + 8):
					for x: int in range(c % size - 4, c % size + 8):
						skip[y * size + x] = 1
			var seen: int = 0
			var diff: int = 0
			for y: int in range(MapData.RIM_W, size - MapData.RIM_W, 2):
				for x: int in range(MapData.RIM_W, size - MapData.RIM_W, 2):
					if skip[y * size + x] != 0:
						continue
					for k: int in range(1, slots):
						var ix: int = sym.cell_of2(sym.img_x(k, sym.to2(x), sym.to2(y)))
						var iy: int = sym.cell_of2(sym.img_y(k, sym.to2(x), sym.to2(y)))
						if ix < 0 or iy < 0 or ix >= size or iy >= size or skip[iy * size + ix] != 0:
							continue
						seen += 1
						var same: bool = map.terrain[y * size + x] == map.terrain[iy * size + ix] if sym.is_exact() \
							else map.kind[y * size + x] == map.kind[iy * size + ix]
						if not same:
							diff += 1
			var pm: int = diff * 1000 / maxi(1, seen)
			if sym.is_exact():
				t.le(pm, 10, "fam%d slots %d: exact group mismatch %d permille (<= 1 %%)" % [fam, slots, pm])
			else:
				t.le(pm, 250, "fam%d slots %d: rotation group mismatch %d permille (<= 25 %%)" % [fam, slots, pm])


func test_determinism_and_job_equality(t: TestCtx) -> void:
	var cfg: Dictionary = _cfg(2, 3, 112, 4242, false, {"density": 60})
	var a: MapData = MapGenerator.generate(cfg)
	var b: MapData = MapGenerator.generate(cfg)
	t.eq(a.map_hash(), b.map_hash(), "double run: map_hash")
	t.eq(a.content_hash(), a.map_hash(), "content_hash == map_hash")
	t.eq(a.visual_hash(), b.visual_hash(), "double run: visual_hash")
	t.eq(a.to_bytes(), b.to_bytes(), "double run: byte identical")
	# threaded job
	var job: MapGenJob = MapGenJob.begin(cfg)
	var last: int = -1
	var mono: bool = true
	var guard: int = 0
	while not job.step(1000):
		var p: int = job.progress_pct()
		if p < last:
			mono = false
		last = p
		guard += 1
		if guard > 20000:
			break
		OS.delay_msec(2)
	t.check(mono, "job progress monotonic (threaded)")
	t.eq(job.progress_pct(), 100, "job progress ends at 100")
	t.not_null(job.result(), "threaded job result")
	t.eq(job.result().to_bytes(), a.to_bytes(), "threaded job == direct call")
	t.eq(job.result().visual_hash(), a.visual_hash(), "threaded job view layers == direct")
	# unthreaded, sliced into tiny budgets (stage granularity)
	var job2: MapGenJob = MapGenJob.begin(cfg, null, false)
	var steps: int = 0
	var last2: int = -1
	var mono2: bool = true
	while not job2.step(1):
		steps += 1
		var p2: int = job2.progress_pct()
		if p2 < last2:
			mono2 = false
		last2 = p2
	t.check(mono2, "job progress monotonic (unthreaded)")
	t.gt(steps, 0, "unthreaded job yields between stages")
	t.eq(job2.result().to_bytes(), a.to_bytes(), "unthreaded sliced job == direct call")
	# cancel
	var job3: MapGenJob = MapGenJob.begin(cfg)
	job3.cancel()
	t.check(job3.step(0), "cancelled job reports finished")
	t.is_null(job3.result(), "cancelled job has no result")
	# serialisation round trip of a generated map
	var back: MapData = MapData.from_bytes(a.tt, a.to_bytes())
	t.not_null(back, "from_bytes")
	if back != null:
		t.eq(back.map_hash(), a.map_hash(), "round trip map_hash")
		t.eq(back.visual_hash(), a.visual_hash(), "round trip view layers")


func test_sim_state_determinism(t: TestCtx) -> void:
	# two clones of one generated map mutate identically (occupy in different orders) and hash the same
	var m: MapData = MapGenerator.generate(_cfg(0, 4, 128, 9))
	var c1: MapData = m.clone_fresh()
	var c2: MapData = m.clone_fresh()
	var fp: MapFootprint = MapFootprint.new(3, 3)
	var s0: int = m.spawns[1]
	var s1: int = m.spawns[MapData.SPAWN_STRIDE + 1]
	c1.occupy(1, fp, s0 % m.w + 3, s0 / m.w + 3, 0)
	c1.occupy(2, fp, s1 % m.w + 3, s1 / m.w + 3, 0)
	c2.occupy(2, fp, s1 % m.w + 3, s1 / m.w + 3, 0)
	c2.occupy(1, fp, s0 % m.w + 3, s0 / m.w + 3, 0)
	t.eq(c1.checksum_dynamic(), c2.checksum_dynamic(), "occupy order independent on a generated map")
	t.eq(m.checksum_dynamic(), m.recompute_dynamic_hash(), "template dynamic hash consistent")
	t.check(m.nav.validate_against_terrain(), "nav layers match the terrain")


func test_progress_callable(t: TestCtx) -> void:
	var plog: Array = []
	var cb: Callable = func(stage: int, pct: int) -> void: plog.append([stage, pct])
	var m: MapData = MapGenerator.generate(_cfg(1, 4, 128, 3), null, cb)
	t.not_null(m, "map")
	var last: int = -1
	var mono: bool = true
	var stages: Dictionary = {}
	for e: Array in plog:
		if (e[1] as int) < last:
			mono = false
		last = e[1] as int
		stages[e[0]] = true
		t.check((e[1] as int) >= 0 and (e[1] as int) <= 100, "pct in range")
	t.check(mono, "pct monotonic")
	t.eq(last, 100, "ends at 100")
	for st: int in [MapGenerator.ST_HEIGHT, MapGenerator.ST_LAYOUT, MapGenerator.ST_FINALIZE, MapGenerator.ST_DONE]:
		t.check(stages.has(st), "stage %d reported" % st)


func test_repair_loop_and_template(t: TestCtx) -> void:
	# a seed known to fail level 0 (coast, 3 slots, 192): the repair loop widens the gates, deterministically
	var cfg: Dictionary = _cfg(2, 3, 192, 40595)
	var r1: Dictionary = MapGenerator.generate_report(cfg)
	var r2: Dictionary = MapGenerator.generate_report(cfg)
	t.gt((r1["failures"] as Array).size(), 0, "level 0 fails for this seed")
	t.eq(r1["failures"], r2["failures"], "failure log deterministic")
	t.eq(r1["layout_level"], r2["layout_level"], "level deterministic")
	t.eq((r1["map"] as MapData).map_hash(), (r2["map"] as MapData).map_hash(), "repaired map deterministic")
	t.eq(MapGenValidate.validate(r1["map"] as MapData).size(), 0, "repaired map valid")
	t.eq(r1["template"], false, "no template needed")
	# impossible route requirement => every level of every attempt fails => the safe template, still valid
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(MapGenTables.PATH))
	((d as Dictionary)["families"] as Dictionary)["open"]["min_route_pct"] = 100
	var hard: MapGenTables = MapGenTables.from_dict(d as Dictionary)
	var rt: Dictionary = MapGenerator.generate_report(_cfg(0, 4, 128, 11), hard)
	t.eq(rt["template"], true, "falls back to the template")
	t.eq((rt["failures"] as Array).size(), 6, "2 attempts x 3 levels logged")
	var tm: MapData = rt["map"] as MapData
	t.eq(MapGenValidate.validate(tm).size(), 0, "template validates")
	t.eq(tm.neutrals.size(), 0, "template has no neutrals")


func test_template_validates_everywhere(t: TestCtx) -> void:
	for fam: int in 3:
		for slots: int in SLOT_LIST:
			for size: int in [MIN_SIZE[slots] as int] + ([256] if slots == 8 and fam == 2 else []):
				var p: MapGenParams = MapGenParams.from_config(_cfg(fam, slots, size, 5 + slots, fam == 2))
				var m: MapData = MapGenTemplate.make(p)
				var fails: PackedStringArray = MapGenValidate.validate(m)
				t.eq(fails.size(), 0, "template fam%d s%d size %d: %s" % [fam, slots, size, str(fails)])
				var m2: MapData = MapGenTemplate.make(p)
				t.eq(m.map_hash(), m2.map_hash(), "template deterministic")


func test_validators_detect_faults(t: TestCtx) -> void:
	var cfg: Dictionary = _cfg(0, 4, 128, 21)
	var w: int = 128
	# V1: wall start 1 in with cliffs
	var m: MapData = MapGenerator.generate(cfg)
	var s1: int = m.spawns[MapData.SPAWN_STRIDE + 1]
	for y: int in range(s1 / w - 9, s1 / w + 10):
		for x: int in range(s1 % w - 9, s1 % w + 10):
			var d2: int = (x - s1 % w) * (x - s1 % w) + (y - s1 / w) * (y - s1 / w)
			if d2 >= 49 and d2 <= 81:
				m.terrain[y * w + x] = MapTerrain.T_CLIFF
	t.check(MapGenValidate.validate(m).has("V1 starts_disconnected"), "V1 detects a walled-in start")
	# V3: field centre encased
	m = MapGenerator.generate(cfg)
	var fc: int = m.fields[1]
	for y: int in range(fc / w - 6, fc / w + 7):
		for x: int in range(fc % w - 6, fc % w + 7):
			var d2: int = (x - fc % w) * (x - fc % w) + (y - fc / w) * (y - fc / w)
			if d2 >= 25 and d2 <= 36 and m.field_of[y * w + x] == 0:
				m.terrain[y * w + x] = MapTerrain.T_CLIFF
	t.check(MapGenValidate.validate(m).has("V3 field_unreachable"), "V3 detects an isolated field")
	# V4: no buildable ground around start 0
	m = MapGenerator.generate(cfg)
	var s0: int = m.spawns[1]
	for y: int in range(s0 / w - 14, s0 / w + 15):
		for x: int in range(s0 % w - 14, s0 % w + 15):
			if m.terrain[y * w + x] == MapTerrain.T_GRASS:
				m.terrain[y * w + x] = MapTerrain.T_SAND if (x + y) % 2 == 0 else MapTerrain.T_ROAD
	var f4: PackedStringArray = MapGenValidate.validate(m)
	t.check(f4.has("V4 start_area_small") or f4.has("V9 structural"), "V4/V9 detect a hostile start ground")
	# V9: deposit total tampered
	m = MapGenerator.generate(cfg)
	m.deposit_max[m.fields[1]] += 1
	t.check(MapGenValidate.validate(m).has("V9 structural"), "V9 detects a deposit / field total mismatch")
	# V10: budget scaled by the recorded resources parameter
	m = MapGenerator.generate(cfg)
	m.gen_params[7] = 500
	t.check(MapGenValidate.validate(m).has("V10 economy_budget"), "V10 detects a credit deficit")
	# V11: a coast map without bays asked for docks
	m = MapGenerator.generate(_cfg(2, 2, 96, 21))
	m.gen_params[10] = 1
	t.check(MapGenValidate.validate(m).has("V11 no_dock"), "V11 detects missing docks")
	# V12: a neutral lot moved next to a start
	m = MapGenerator.generate(cfg)
	m.neutrals[1] = m.spawns[1] + 3
	t.check(MapGenValidate.validate(m).has("V12 neutral_separation"), "V12 detects a lot beside a start")


func test_layout_details(t: TestCtx) -> void:
	# start order, HQ space, deposits, boulders and shore flags
	var m: MapData = MapGenerator.generate(_cfg(2, 4, 160, 31, true))
	var w: int = m.w
	t.eq(m.spawns.size() / MapData.SPAWN_STRIDE, 4, "4 spawns")
	for k: int in 4:
		t.eq(m.spawns[k * MapData.SPAWN_STRIDE], k, "spawn index")
		t.eq(m.spawns[k * MapData.SPAWN_STRIDE + 4], k & 1, "team hint")
		var hq: PackedInt32Array = PackedInt32Array()
		var c: int = m.spawns[k * MapData.SPAWN_STRIDE + 1]
		for y: int in range(c / w - 1, c / w + 2):
			for x: int in range(c % w - 1, c % w + 2):
				hq.append(y * w + x)
		t.eq(MapBuildRules.check_land(m, hq), MapBuildRules.PR_OK, "HQ fits at start %d" % k)
		t.check((m.flags[c] & MapData.SF_START) != 0, "SF_START at start")
	# every deposit cell and its ring is SF_NOBUILD; ids are dense 1..n
	var ids: Dictionary = {}
	for i: int in m.n:
		if m.field_of[i] != 0:
			ids[m.field_of[i]] = true
			t.check((m.flags[i] & MapData.SF_NOBUILD) != 0, "deposit cell nobuild")
	var nf: int = m.fields.size() / MapData.FIELD_STRIDE
	t.eq(ids.size(), nf, "one id per field")
	for f: int in nf:
		t.eq(m.fields[f * MapData.FIELD_STRIDE], f + 1, "dense 1-based field ids")
		t.eq(m.fields[f * MapData.FIELD_STRIDE + 2], 3, "radius 3")
	# 4 slots: 2 start + 1 natural + 1 rich + 2 further per slot + 4 contested
	var per_kind: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
	for f: int in nf:
		per_kind[m.fields[f * MapData.FIELD_STRIDE + 5]] += 1
	t.eq(per_kind, PackedInt32Array([8, 4, 4, 8, 4]), "field kinds for 4 slots")
	# coast + bay: every start has deep water within reach and the harbor terminals sit on the shore
	var harbor: int = 0
	for k: int in m.neutrals.size() / MapData.NEUTRAL_STRIDE:
		if m.neutrals[k * MapData.NEUTRAL_STRIDE] == 5:
			harbor += 1
	t.eq(harbor, 4, "one harbor terminal per slot")
	t.check(not m.objects.is_empty(), "objects derived from neutrals")
	t.eq(m.neutral_ids.size(), 6, "neutral id table")
	# scenery boulders exist on open ground and block every profile
	var open: MapData = MapGenerator.generate(_cfg(0, 4, 128, 31))
	var blocks: int = 0
	for i: int in open.n:
		if (open.flags[i] & MapData.SF_BLOCK) != 0:
			blocks += 1
			t.check(open.nav.clear_at(MapTerrain.NP_FOOT, i) == 0 or not open.nav.passable(MapTerrain.NP_FOOT, 1, i), "boulder blocks")
	t.gt(blocks, 0, "boulders placed")


func test_generation_time(t: TestCtx) -> void:
	var worst: int = 0
	var lines: PackedStringArray = PackedStringArray()
	for spec: Array in [[0, 8, false], [1, 8, false], [2, 8, false], [2, 8, true], [0, 6, false], [2, 3, false]]:
		var t0: int = Time.get_ticks_usec()
		var m: MapData = MapGenerator.generate(_cfg(spec[0] as int, spec[1] as int, 192, 12345, spec[2] as bool))
		var ms: int = (Time.get_ticks_usec() - t0) / 1000
		worst = maxi(worst, ms)
		lines.append("fam%d/s%d%s=%dms" % [spec[0], spec[1], "+bay" if spec[2] else "", ms])
		t.not_null(m, "generated")
	t.note("generation at 192x192 incl. nav: " + ", ".join(lines))
	t.lt(worst, 1500.0 * TestCtx.perf_factor(), "192^2 generation incl. nav under 1.5 s (x perf_factor on a slow / loaded machine)")
	var t1: int = Time.get_ticks_usec()
	MapGenerator.generate(_cfg(2, 8, 256, 777))
	t.note("256x256 coast 8 slots: %d ms" % ((Time.get_ticks_usec() - t1) / 1000))


## D4: recorded map_hash values (macOS; reproduced on linux-amd64 / linux-arm64 by the xplat scenario). A change means
## the generator output changed: bump MapGenParams.VERSION + map_gen.json gen_version and re-record.
func test_goldens(t: TestCtx) -> void:
	var golden: Array = [
		[0, 2, 96, 1, false, 3203326388], [0, 4, 128, 7, false, 1349390315], [0, 8, 192, 12345, false, 1218799133],
		[1, 3, 112, 1, false, 3918671308], [1, 6, 160, 7, false, 2357097114], [2, 4, 128, 12345, false, 1197958286],
		[2, 8, 192, 7, true, 2482609851], [2, 6, 160, 1, true, 2765474648], [2, 3, 128, 7, false, 1768727216]]
	for g: Array in golden:
		var m: MapData = MapGenerator.generate(_cfg(g[0] as int, g[1] as int, g[2] as int, g[3] as int, g[4] as bool))
		t.eq(m.map_hash(), g[5] as int, "map_hash fam%d s%d size %d seed %d" % [g[0], g[1], g[2], g[3]])
