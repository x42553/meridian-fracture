extends RefCounted
## DATA-11: DefTestKit (hand-made GameData, stub balance generator) and the members sim_core 7.2 reads.

const GOLDEN: String = "res://tests/golden/data_hash.json"


func test_small_data_shape(t: TestCtx) -> void:
	var d: GameData = DefTestKit.small_data()
	t.eq(d.units.size(), 6, "6 units")
	t.eq(d.structures.size(), 6, "6 structures")
	t.eq(d.rosters.size(), 2, "2 rosters")
	t.eq(d.roster_idx(DefTestKit.R_ALPHA), 0, "alpha sorts first")
	t.eq(d.roster_idx(DefTestKit.R_VANILLA), 1, "vanilla")
	t.eq(d.roster_idx("roster.nope"), -1, "unknown roster")
	t.check(d.data_hash() > 0, "hashed")
	t.check(DefValidator.check_frozen(d), "frozen")
	var alpha: DefRoster = d.roster_for("TST", "alpha")
	var van: DefRoster = d.roster_for("TST")
	t.not_null(alpha, "roster_for alpha")
	t.check(alpha.has_unit(d.unit_idx(DefTestKit.U_TANK2)) and not alpha.has_unit(d.unit_idx(DefTestKit.U_TANK)), "alpha replaces the tank")
	t.check(van.has_unit(d.unit_idx(DefTestKit.U_TANK)) and not van.has_unit(d.unit_idx(DefTestKit.U_TANK2)), "vanilla keeps the tank")
	t.eq(van.hq_idx, d.structure_idx(DefTestKit.S_HQ), "hq_idx")
	t.eq(van.mcv_idx, d.unit_idx(DefTestKit.U_MCV), "mcv_idx")
	var hq: DefStructure = van.structure(van.hq_idx)
	t.check((hq.flags & DefEnums.SF_NO_BUILD) != 0 and hq.deploy_unit == van.mcv_idx, "HQ is the MCV's deploy target")
	var mcv: DefUnit = van.unit(van.mcv_idx)
	t.check(mcv.has_ability(DefEnums.AbilityKind.DEPLOY_STRUCTURE), "MCV carries DEPLOY_STRUCTURE (is_rebuilder)")
	t.eq(mcv.pop, 0, "MCV is cap-exempt")
	var tank: DefUnit = van.unit(d.unit_idx(DefTestKit.U_TANK))
	t.eq(tank.weapons[0].damage, 141, "tank weapon")
	t.eq(tank.weapons[0].reload_ticks, 24, "reload ticks")
	t.eq(tank.max_range, 7168, "derived max_range")
	t.check(tank.weapons[0] != d.units[tank.index].weapons[0], "roster clone is not aliased")
	t.check(d.zones[0].radius > 0 and d.neutrals[0].radius > 0 and d.neutrals[0].health > 0, "zone + neutral fields the kernel reads")
	t.eq(d.damage.pct(DefEnums.DamageType.EMP, DefEnums.ArmorClass.INFANTRY), 0, "kit damage table")
	t.eq(d.moves.speed_bp_at(DefEnums.MoveClass.FOOT, DefEnums.TerrainKind.DEEP), 0, "kit move table")


func test_kernel_members_of_sim_core_7_2(t: TestCtx) -> void:
	var d: GameData = DefTestKit.small_data()
	# GameData: units/structures/zones/neutrals/rosters arrays, roster_idx(id), data_hash()
	t.check(d.units is Array and d.structures is Array and d.zones is Array and d.neutrals is Array and d.rosters is Array, "arrays")
	t.eq(d.roster_idx(DefTestKit.R_VANILLA), 1, "roster_idx(id)")
	t.check(d.data_hash() is int, "data_hash()")
	# DefUnit: health radius home_layer pop flags ability_mask; DefStructure: health radius; DefZone: hp radius; DefNeutral: health radius
	var u: DefUnit = d.units[d.unit_idx(DefTestKit.U_TANK)]
	t.check(u.health > 0 and u.radius > 0 and u.pop == 1, "unit fields")
	t.eq(u.home_layer, DefEnums.Layer.GROUND, "home_layer")
	t.check(u.flags is int and u.ability_mask is int, "flags / ability_mask")
	t.check(d.structures[0].health > 0 and d.structures[0].radius > 0, "structure fields")
	t.check(d.zones[0].hp is int and d.zones[0].radius > 0, "zone fields")
	# DefPlayerView.new(data, roster) / resolved_stats(kind, def)[HEALTH] / checksum()
	var v: DefPlayerView = DefPlayerView.new(d, d.rosters[d.roster_idx(DefTestKit.R_VANILLA)])
	var st: PackedInt32Array = v.resolved_stats(DefEnums.Kind.UNIT, u.index)
	t.eq(st.size(), DefEnums.Stat.COUNT, "stat vector size")
	t.eq(st[DefEnums.Stat.HEALTH], 907, "HEALTH")
	t.eq(st[DefEnums.Stat.COST], 850, "COST")
	t.eq(st[DefEnums.Stat.SPEED], 102, "SPEED")
	t.eq(v.resolved_stats(DefEnums.Kind.STRUCTURE, d.structure_idx(DefTestKit.S_GENERATOR))[DefEnums.Stat.POWER], 150, "structure POWER")
	t.eq(v.base_stats(DefEnums.Kind.UNIT, u.index)[DefEnums.Stat.HEALTH], 907, "base_stats")
	t.eq(v.checksum(), v.layer3.checksum(), "checksum == layer3.checksum()")
	t.eq(v.unit_cost[u.index], 850, "unit_cost table")
	t.eq(v.unit_cost[d.unit_idx(DefTestKit.U_TANK2)], 0, "0 for units not in the roster")
	t.eq(v.struct_power[d.structure_idx(DefTestKit.S_GENERATOR)], 150, "struct_power")
	t.eq(v.struct_available[d.structure_idx(DefTestKit.S_HQ)], 0, "HQ is not buildable")
	t.eq(v.unit_cap_cost[d.unit_idx(DefTestKit.U_MCV)], 0, "unit_cap_cost of MCV")
	t.eq(v.research_available[0], 1, "research in roster")
	t.eq(v.power_of_slot, PackedInt32Array([0]), "power slot")
	var c0: int = v.checksum()
	v.apply_research(0)
	t.eq(v.version, 1, "version follows layer3")
	t.ne(v.checksum(), c0, "checksum changes with research")
	t.check(v.layer3.is_done(0), "recorded")
	t.eq(v.effective_slot_value(u.index, 0, DefEnums.Stat.DAMAGE), 141, "effective slot value")
	t.eq(v.slot(u.index, 0).damage, 141, "slot()")
	t.is_null(v.slot(u.index, 5), "no such slot")


func test_pinned_golden(t: TestCtx) -> void:
	var p: JSON = JSON.new()
	t.eq(p.parse(FileAccess.get_file_as_string(GOLDEN)), OK, "golden parses")
	var g: Dictionary = p.data
	var now: Dictionary = DefTestKit.golden_dict()
	t.eq(int(g["format"]), now["format"], "format")
	t.eq(int(g["hash"]), now["hash"], "small_data data_hash matches tests/golden/data_hash.json (regenerate: tools/gd run res://tests/fixtures/data/gen_data_golden.gd)")
	for k: Variant in (now["tables"] as Dictionary).keys():
		t.eq(int((g["tables"] as Dictionary).get(k, -1)), (now["tables"] as Dictionary)[k], "table " + str(k))
	t.eq((g["tables"] as Dictionary).size(), (now["tables"] as Dictionary).size(), "same table set")


func test_stub_sheets_cover_every_bible_unit(t: TestCtx) -> void:
	var bible: Dictionary = DefTestKit.read_json(DefTestKit.BIBLE_PATH)
	var g: Dictionary = DefTestKit.read_json(DefTestKit.BALANCE_DIR + "/global.json")
	var kinds: Dictionary = DefTestKit.read_json(DefTestKit.BALANCE_DIR + "/ability_kinds.json")
	var sheets: Dictionary = DefTestKit.stub_balance(bible, g, kinds)
	t.eq(sheets.size(), 8, "8 faction sheets")
	var seen: Dictionary = {}
	var archs: Dictionary = g["weapon_archetypes"]
	var all_weapon_ids: Dictionary = {}
	for f: String in sheets.keys():
		var sh: Dictionary = sheets[f]
		t.eq(sh["schema"], "meridian.balance.units/1", f + " schema")
		var prev: String = ""
		for u: Dictionary in sh["units"]:
			var id: String = u["id"]
			t.check(id > prev, "%s sorted at %s" % [f, id])
			prev = id
			t.check(not seen.has(id), "%s appears once" % id)
			seen[id] = true
			t.eq("faction." + id.get_slice(".", 1), sh["faction"], id + " in its faction's sheet")
			for k: String in ["archetype", "build_time_s", "health", "speed_cells_s", "vision_cells", "radius_cells", "cost_credits"]:
				t.check(u.has(k), "%s has %s" % [id, k])
			for w: String in u["weapons"]:
				all_weapon_ids[w] = f
		var wprev: String = ""
		for w: Dictionary in sh["weapons"]:
			t.check(archs.has(w["archetype"]), "%s: known archetype %s" % [w["id"], w["archetype"]])
			t.check(str(w["id"]) > wprev, "weapons sorted")
			wprev = w["id"]
			t.check(all_weapon_ids.has(w["id"]) or str(w["id"]).ends_with("_drone_gun"), "%s is referenced" % w["id"])
	var want: int = 0
	for id: String in bible["units"]:
		if bible["units"][id]["faction_id"] != null:
			want += 1
	t.eq(want, 152, "152 faction units in the bible")
	t.eq(seen.size(), 152, "every faction unit has exactly one stub entry")
	# determinism: same inputs, same sheets
	t.eq(JSON.stringify(sheets, "", true), JSON.stringify(DefTestKit.stub_balance(bible, g, kinds), "", true), "generator is deterministic")
	# carriers get a drone summon and wings
	var carriers: int = 0
	for f: String in sheets.keys():
		carriers += (sheets[f]["summons"] as Array).size()
	t.eq(carriers, 3, "3 carrier drones")


func test_stub_sources_are_a_complete_manifest(t: TestCtx) -> void:
	var s: DefSources = DefTestKit.stub_sources()
	t.eq(s.manifest_files.size(), 19, "19 manifest files (17 core + 2 map)")
	for f: String in DefValidator.CORE_FILES:
		t.check(s.balance.has(f), "has " + f)
	var real: DefSources = DefTestKit.stub_sources(true)
	t.eq(real.manifest_files, s.manifest_files, "same manifest with real sheets preferred")
	var d: GameData = GameData.load_from_sources(s)
	t.check(d != null, "stub sources load: " + GameData.last_report.text(5))
