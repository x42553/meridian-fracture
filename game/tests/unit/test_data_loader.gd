extends RefCounted
## DATA-03: loader core + GameData facade: P0-P3, bible ingestion, merge policy, manifest errors, handshake, plug-in
## compilers, global.json consumption (P2). Uses DefTestKit stub sources (no dependence on the real unit sheets).

const K := DefEnums.Kind


class DummyCompiler:
	extends DefDomainCompiler
	var fail: bool = false

	func domain_id() -> String:
		return "dummy"

	func file_names() -> PackedStringArray:
		return PackedStringArray(["dummy.json"])

	func collect_ids(_src: DefSources, ids: DefIds, rep: DefLoadReport) -> void:
		ids.extend(DefEnums.Kind.ZONE, PackedStringArray(["zone.dummy.one"]), rep)

	func compile(_src: DefSources, data: GameData, rep: DefLoadReport) -> void:
		if fail:
			rep.error("V-DUM-01", "dummy.json", "boom")
		else:
			data.ext["dummy"] = RefCounted.new()

	func table_hashes(_data: GameData) -> Dictionary:
		return {"dummy": 1234}


func _data() -> GameData:
	return DefTestKit.stub_game_data()


func _bible_src() -> DefSources:
	var s: DefSources = DefTestKit.stub_sources()
	s.bible_path = DefTestKit.BIBLE_PATH
	s.raw_texts[DefTestKit.BIBLE_PATH] = FileAccess.get_file_as_string(DefTestKit.BIBLE_PATH)
	return s


func test_counts(t: TestCtx) -> void:
	var d: GameData = _data()
	t.not_null(d, "stub sources load: " + GameData.last_report.text(10))
	if d == null:
		return
	var bible_units: int = 0
	for u: DefUnit in d.units:
		if u.id.begins_with("unit."):
			bible_units += 1
	t.eq(bible_units, 156, "156 bible units")
	t.eq(d.structures.size(), 29, "29 structures")
	t.eq(d.research.size(), 40, "40 research")
	t.eq(d.powers.size(), 48, "48 powers")
	t.eq(d.superweapons.size(), 8, "8 superweapons")
	t.eq(d.modifiers.size(), 98, "98 modifiers")
	t.eq(d.selectors.size() >= 27, true, ">= 27 selectors (27 bible + balance extras)")
	t.eq(d.rosters.size(), 32, "32 rosters")
	t.eq(d.factions.size(), 8, "8 factions")
	t.eq(d.weapon_archs.size(), 27, "27 weapon archetypes")
	t.eq(d.roster_ids().size(), 32, "roster_ids")
	var classes: Array = [0, 0, 0]
	for u: DefUnit in d.units:
		if u.id.begins_with("unit."):
			classes[u.unit_class] += 1
	t.eq(classes, [4, 104, 48], "4 service / 104 baseline / 48 unique")


func test_indices_of_5_3(t: TestCtx) -> void:
	var d: GameData = _data()
	if d == null:
		t.fail("no data")
		return
	t.eq(d.structure_idx("structure.ae.forge_cannon"), 0, "first structure")
	t.eq(d.structure_idx("structure.shared.radar"), 26, "radar")
	t.eq(d.structure_idx("structure.shared.factory"), 22, "factory")
	t.eq(d.structure_idx("structure.shared.laboratory"), 25, "laboratory")
	t.eq(d.structure_idx("structure.shared.watchtower"), 28, "last structure")
	t.eq(d.faction_idx("faction.ae"), 0, "faction ae")
	t.eq(d.faction_idx("faction.napc"), 3, "faction napc")
	t.eq(d.faction_idx("faction.sap"), 7, "faction sap")
	t.eq(d.superweapon_idx("superweapon.ae.horizon_mass_driver"), 0, "first superweapon")
	t.eq(d.superweapon_idx("superweapon.sap.trident_interception_array"), 7, "last superweapon")
	t.eq(d.roster_idx("roster.ae.kongo"), 0, "roster 0")
	t.eq(d.roster_idx("roster.napc.canada"), 12, "roster 12")
	t.eq(d.roster_idx("roster.sap.vanilla"), 31, "roster 31")
	t.eq(d.roster_idx("roster.nope.x"), -1, "unknown roster")
	t.eq(d.weapon_arch_idx("warch.tank_cannon"), 3, "tank_cannon frozen")
	t.eq(d.weapon_arch_idx("warch.drone_missile"), 26, "drone_missile frozen")
	var bastion: DefUnit = d.units[d.unit_idx("unit.napc.bastion_heavy_tank")]
	t.eq(bastion.requires_mask, (1 << 22) | (1 << 26) | (1 << 25), "T3 factory unit requires factory|radar|laboratory")
	t.eq(bastion.producer, 22, "producer factory")
	t.eq(bastion.tier, 3, "tier 3")
	t.eq(d.id_of(K.STRUCTURE, 26), "structure.shared.radar", "id_of")
	t.eq(d.id_of(K.STRUCTURE, 99), "", "id_of out of range")
	t.eq(d.count(K.STRUCTURE), 29, "count")
	var ids: PackedStringArray = d.ids.ids(K.UNIT)
	var sorted_ids: PackedStringArray = ids.duplicate()
	sorted_ids.sort()
	t.eq(ids, sorted_ids, "unit ids sorted")
	t.check(ids[0].begins_with("summon.") or ids[0].begins_with("unit."), "summons sort before units")


func test_lookups_and_refs(t: TestCtx) -> void:
	var d: GameData = _data()
	if d == null:
		t.fail("no data")
		return
	var canada: DefRoster = d.roster_for("NAPC", "canada")
	t.not_null(canada, "roster_for canada")
	t.eq(canada.id, "roster.napc.canada", "id")
	t.check(not canada.is_vanilla, "subfaction")
	t.eq(canada.parent, d.roster_idx("roster.napc.vanilla"), "parent")
	t.eq(d.roster_for("NAPC").id, "roster.napc.vanilla", "vanilla by default")
	t.is_null(d.roster_for("XXX"), "unknown faction")
	t.eq(d.vanilla_roster_of(d.faction_idx("faction.pd")).id, "roster.pd.vanilla", "vanilla_roster_of")
	t.eq(d.roster_faction(canada.index), d.faction_idx("faction.napc"), "roster_faction")
	var r: int = d.ref(K.UNIT, 77)
	t.eq(GameData.ref_kind(r), K.UNIT, "ref kind")
	t.eq(GameData.ref_index(r), 77, "ref index")
	t.eq(d.def_of(K.UNIT, 3).id, d.units[3].id, "def_of unit")
	t.is_null(d.def_of(K.UNIT, -1), "def_of out of range")
	t.is_null(d.def_of(K.ROSTER, 0), "rosters are not DefBase")
	t.eq(d.roster_idx(canada.id), canada.index, "roster_idx")
	t.eq(canada.units.size(), d.units.size(), "roster tables sized to the global counts")
	t.eq(canada.structures.size(), 29, "roster structure table")
	var hq: int = d.structure_idx("structure.shared.headquarters")
	t.eq(canada.hq_idx, hq, "hq_idx")
	t.eq(canada.mcv_idx, d.unit_idx("unit.shared.mobile_construction_vehicle"), "mcv_idx")
	t.eq(d.base_roster.hq_idx, hq, "base roster hq")


func test_bible_ingestion(t: TestCtx) -> void:
	var d: GameData = _data()
	if d == null:
		t.fail("no data")
		return
	var g: DefUnit = d.units[d.unit_idx("unit.napc.guardian_tank")]
	t.eq(g.faction, d.faction_idx("faction.napc"), "guardian faction")
	t.eq(g.introduced_by, d.roster_idx("roster.napc.vanilla"), "introduced_by")
	t.eq(g.unit_class, DefEnums.UnitClass.BASELINE, "class")
	t.eq(g.tags, DefEnums.UT_COMBAT | DefEnums.UT_GROUND | DefEnums.UT_LAND_VEHICLE | DefEnums.UT_TANK, "tags")
	t.eq(g.ui_name, "Guardian Tank", "label")
	t.check((g.flags & DefEnums.UF_PRODUCIBLE) != 0, "producible")
	var col: DefUnit = d.units[d.unit_idx("unit.shared.collector")]
	t.eq(col.cost, 1400, "collector cost is bible-fixed")
	t.eq(col.unit_class, DefEnums.UnitClass.SERVICE, "service class")
	t.eq(col.faction, -1, "shared faction")
	var pf: DefUnit = d.units[d.unit_idx("unit.napc.pathfinder_apc")]
	var beaver: int = d.unit_idx("unit.napc.beaver_amphibious_apc")
	t.eq(d.units[beaver].replaces, pf.index, "beaver replaces pathfinder")
	t.eq(pf.replaced_by, PackedInt32Array([beaver]), "replaced_by derived")
	var hq: DefStructure = d.structures[d.structure_idx("structure.shared.headquarters")]
	t.check((hq.flags & DefEnums.SF_NO_BUILD) != 0, "HQ is SF_NO_BUILD")
	t.eq(hq.deploy_unit, d.unit_idx("unit.shared.mobile_construction_vehicle"), "HQ deploys from the MCV")
	t.check(hq.starts_deployed, "starts deployed")
	t.eq(hq.build_radius, 8192, "8 cell build radius")
	t.eq(hq.build_ticks, 0, "no build time")
	var dock: DefStructure = d.structures[d.structure_idx("structure.shared.dock")]
	t.eq(dock.place_mask, DefEnums.PLACE_SHORELINE, "dock placement")
	t.eq(dock.cost, 1800, "dock cost")
	t.eq(dock.build_ticks, 800, "dock 40 s")
	t.eq(dock.power, -35, "dock power")
	t.eq(dock.queue_kind, DefEnums.QueueKind.NAVAL, "dock queue")
	var atlas: DefStructure = d.structures[d.structure_idx("structure.napc.atlas_kinetic_array")]
	t.eq(atlas.max_per_player, 1, "one strategic")
	t.check((atlas.place_mask & DefEnums.PLACE_MAX_ONE_STRATEGIC) != 0, "strategic placement")
	t.check((atlas.flags & DefEnums.SF_STRATEGIC) != 0, "strategic flag")
	t.eq(atlas.superweapon, d.superweapon_idx("superweapon.napc.atlas_kinetic_array"), "launcher links the superweapon")
	var relay: DefStructure = d.structures[d.structure_idx("structure.nec.relay")]
	t.eq(relay.place_mask, DefEnums.PLACE_NO_RADIUS_EXTENSION, "relay placement")
	t.check((relay.flags & DefEnums.SF_RELAY) != 0, "relay flag")
	var rs: DefResearch = d.research[d.research_idx("research.napc.adaptive_plating")]
	t.eq(rs.cost, 1000, "research cost")
	t.eq(rs.time_t, 900, "45 s research")
	t.eq(rs.tier, 2, "tier")
	t.eq(rs.requires_mask, 1 << d.structure_idx("structure.shared.radar"), "requires radar")
	t.check(rs.inherited, "inherited by subfactions")
	var uav: DefPower = d.powers[d.power_idx("power.napc.uav_sweep")]
	t.eq(uav.cooldown_t, 1800, "90 s cooldown")
	t.eq(uav.cost, 500, "cost")
	t.check(uav.requires_powered, "requires powered prerequisites")
	var sw: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.napc.atlas_kinetic_array")]
	t.eq(sw.recharge_t, 9600, "480 s recharge")
	t.eq(sw.warning_t, 200, "10 s warning")
	t.eq(sw.max_charges, 1, "charges")
	var f: DefFaction = d.factions[d.faction_idx("faction.napc")]
	t.eq(f.code, "NAPC", "code")
	t.eq(f.baseline_units.size(), 13, "13 baseline units")
	t.eq(f.sub_rosters.size(), 3, "3 subfactions")
	t.eq(f.vanilla_roster, d.roster_idx("roster.napc.vanilla"), "vanilla roster")
	t.eq(f.superweapon, d.superweapon_idx("superweapon.napc.atlas_kinetic_array"), "faction superweapon")
	t.eq(f.passive_modifiers.size(), 2, "2 passive modifiers")
	var m: DefModifier = d.modifiers[d.ids.index_of(K.MODIFIER, "modifier.napc.canada.03")]
	t.check(m.owner_is_roster, "roster-owned")
	t.eq(m.owner, d.roster_idx("roster.napc.canada"), "owner")
	t.eq(m.layer, 2, "subfaction layer")
	t.eq(m.stat, DefEnums.Stat.SPEED, "stat")
	t.eq(m.delta_bp, 2000, "+20 %")
	t.eq(m.cond, DefEnums.Cond.ON_WATER, "on-water condition")
	t.eq(m.selector, d.selector_idx("selector.amphibious_vehicles_on_water"), "selector")
	var m1: DefModifier = d.modifiers[d.ids.index_of(K.MODIFIER, "modifier.napc.01")]
	t.eq(m1.layer, 1, "parent layer")
	t.eq(m1.cond, 0, "no condition")


func test_deterministic_and_frozen(t: TestCtx) -> void:
	var a: GameData = _data()
	var b: GameData = _data()
	if a == null or b == null:
		t.fail("no data")
		return
	t.eq(a.data_hash(), b.data_hash(), "two loads, same data_hash")
	t.eq(a.table_hashes, b.table_hashes, "same table hashes")
	t.check(a.data_hash() >= 0 and a.data_hash() < (1 << 32), "hash is a 32-bit value")
	t.eq(a.table_hashes.size(), 17, "15 core tables + the map table + the missions table")
	t.check(DefValidator.check_frozen(a), "check_frozen")
	a.units[0].health += 1
	t.check(not DefValidator.check_frozen(a), "check_frozen detects a mutation")


func test_merge_policy(t: TestCtx) -> void:
	var rep: DefLoadReport = DefLoadReport.new()
	t.eq(DefLoader.merge_field(true, 850, false, 0, "u", "cost", true, rep), 850, "bible only")
	t.eq(DefLoader.merge_field(true, 850, true, 850, "u", "cost", true, rep), 850, "equal repeat")
	t.eq(rep.count_rule("V-CNF-02"), 1, "redundant -> info")
	t.check(rep.is_ok(), "still ok")
	t.eq(DefLoader.merge_field(false, 0, true, 700, "u", "cost", true, rep), 700, "balance fills null")
	DefLoader.merge_field(true, 850, true, 900, "u", "cost", true, rep)
	t.eq(rep.count_rule("V-CNF-01"), 1, "conflict -> V-CNF-01")
	DefLoader.merge_field(false, 0, false, 0, "u", "cost", true, rep)
	t.eq(rep.count_rule("V-CMP-04"), 1, "null + absent + required -> V-CMP-04")
	t.eq(DefLoader.merge_field(false, 0, false, 0, "u", "cost", false, rep), 0, "exempt -> 0")
	t.eq(rep.count_rule("V-CMP-04"), 1, "exempt adds nothing")


func test_manifest_and_read_errors(t: TestCtx) -> void:
	var dir: String = "user://data_loader_test"
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir + "/manifest.json", '{"schema": "meridian.balance.manifest/1", "format": 1, "files": ["a.json", "missing.json"]}')
	_write(dir + "/a.json", '{\n  "schema": "x",\n  "broken": [1, 2,\n}')
	var src: DefSources = DefSources.from_disk(DefTestKit.BIBLE_PATH, dir)
	t.eq(src.manifest_files, PackedStringArray(["a.json", "missing.json"]), "manifest read")
	t.eq(src.read_errors.size(), 2, "two read errors: " + str(src.read_errors))
	var joined: String = " | ".join(src.read_errors)
	t.check(joined.contains("V-SCH-01 a.json:"), "parse error carries file:line - " + joined)
	t.check(joined.contains("missing.json") and joined.contains("does not exist"), "missing file reported")
	var d: GameData = GameData.load_from_sources(src)
	t.check(d == null, "load fails")
	t.check(GameData.last_report.has_rule("V-SCH-01"), "V-SCH-01 in the report")
	t.check(GameData.last_report.text().contains("expected file 'global.json' is not listed"), "expected files enforced")
	# a directory without a manifest, and an unsorted / wrong-format manifest
	var s2: DefSources = DefTestKit.stub_sources()
	s2.manifest_files = PackedStringArray(["units_ae.json", "global.json"])
	s2.manifest_format = 2
	t.check(GameData.load_from_sources(s2) == null, "bad manifest fails")
	var txt: String = GameData.last_report.text()
	t.check(txt.contains("format must be 1") and txt.contains("sorted ascending"), "format + order errors: " + txt)
	var s3: DefSources = DefTestKit.stub_sources()
	s3.balance.erase("units_pd.json")
	t.check(GameData.load_from_sources(s3) == null, "missing sheet reported, not crashed")


func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_reference_errors_carry_file_line(t: TestCtx) -> void:
	var src: DefSources = _bible_src()
	(src.bible["units"] as Dictionary)["unit.napc.guardian_tank"]["producer_structure_id"] = "structure.shared.nope"
	t.check(GameData.load_from_sources(src) == null, "unknown reference aborts")
	var txt: String = GameData.last_report.text()
	t.check(txt.contains("V-REF-01"), "V-REF-01: " + txt)
	t.check(txt.contains("meridian_factions.json:"), "message carries file:line: " + txt)
	var src2: DefSources = _bible_src()
	(src2.bible["structures"] as Dictionary)["structure.shared.dock"]["conditions"] = ["Some new condition."]
	t.check(GameData.load_from_sources(src2) == null, "unknown condition aborts")
	t.check(GameData.last_report.has_rule("V-MOD-04"), "V-MOD-04")
	var src3: DefSources = _bible_src()
	(src3.bible["units"] as Dictionary)["unit.napc.guardian_tank"]["tags"] = ["combat", "not_a_tag"]
	t.check(GameData.load_from_sources(src3) == null, "unknown bible tag aborts")
	var src4: DefSources = _bible_src()
	(src4.bible["units"] as Dictionary)["unit.napc.guardian_tank"]["base_stats"]["health"] = 900.5
	t.check(GameData.load_from_sources(src4) == null, "non-integral health aborts")
	t.check(GameData.last_report.has_rule("V-SCH-05"), "V-SCH-05")


func test_handshake(t: TestCtx) -> void:
	var a: GameData = _data()
	var b: GameData = _data()
	var s: DefSources = DefTestKit.stub_sources()
	((s.balance["global.json"] as Dictionary)["production"] as Dictionary)["queue_length"] = 6
	var c: GameData = GameData.load_from_sources(s)
	if a == null or b == null or c == null:
		t.fail("loads failed: " + GameData.last_report.text(5))
		return
	var ha: Dictionary = a.handshake()
	t.eq(ha["format"], GameData.FORMAT_VERSION, "format")
	t.eq(ha["hash"], a.data_hash(), "hash")
	t.check(not ha.has("files"), "no files by default")
	t.eq(GameData.diff_handshake(ha, b.handshake()), PackedStringArray(), "equal data: no diff")
	t.ne(a.data_hash(), c.data_hash(), "economy change changes data_hash")
	var diff: PackedStringArray = GameData.diff_handshake(a.handshake(true), c.handshake(true))
	t.eq(diff, PackedStringArray(["file balance/global.json differs", "table global differs"]), "diff lines sorted")
	var remote: Dictionary = c.handshake(true)
	(remote["files"] as Dictionary).erase("balance/units_ae.json")
	(remote["tables"] as Dictionary).erase("zones")
	remote["format"] = 2
	var d2: PackedStringArray = GameData.diff_handshake(a.handshake(true), remote)
	t.check(d2.has("format: 1 vs 2"), "format line")
	t.check(d2.has("file balance/units_ae.json missing on remote"), "missing file line")
	t.check(d2.has("table zones missing on remote"), "missing table line")
	t.check(a.is_hot_swap_compatible(c), "same ids => hot swap compatible")
	var fh: Dictionary = a.file_hashes()
	t.check(fh.has("bible/meridian_factions.json") and fh.has("balance/global.json"), "file hashes keyed by path")
	a.drop_sources()
	t.eq(a.file_hashes(), fh, "file hashes survive drop_sources")


func test_plugin_compiler(t: TestCtx) -> void:
	var comp: DummyCompiler = DummyCompiler.new()
	var comps: Array[DefDomainCompiler] = [comp]
	var s: DefSources = DefTestKit.stub_sources()
	s.balance["dummy.json"] = {"schema": "meridian.balance.dummy/1"}
	s.manifest_files = PackedStringArray(s.balance.keys())
	s.manifest_files.sort()
	var with: GameData = GameData.load_from_sources(s, DefValidator.LEVEL_FULL, comps)
	t.not_null(with, "load with compiler: " + GameData.last_report.text(5))
	if with == null:
		return
	t.check(with.ids.index_of(K.ZONE, "zone.dummy.one") >= 0, "compiler ids are in DefIds")
	t.check(with.ext.has("dummy"), "compile ran")
	t.eq(with.table_hashes["dummy"], 1234, "compiler table hash present")
	t.check(with.file_hashes().has("balance/dummy.json"), "file_hashes lists the compiler's file")
	var without: GameData = GameData.load_from_sources(DefTestKit.stub_sources())
	t.ne(with.data_hash(), without.data_hash(), "removing the compiler changes the hash")
	comp.fail = true
	t.check(GameData.load_from_sources(s, DefValidator.LEVEL_FULL, comps) == null, "compile error aborts")
	t.check(GameData.last_report.has_rule("V-DUM-01"), "with the compiler's rule id")
	var s2: DefSources = DefTestKit.stub_sources()
	t.check(GameData.load_from_sources(s2, DefValidator.LEVEL_FULL, comps) == null, "compiler file must be in the manifest")
	t.check(GameData.last_report.text().contains("owned by a registered compiler"), "reported")


func test_vocabulary_of_global_json(t: TestCtx) -> void:
	var d: GameData = _data()
	if d == null:
		t.fail("no data")
		return
	var AC := DefEnums.ArmorClass
	var DT := DefEnums.DamageType
	t.eq(d.damage.matrix_pct[DT.AP * 11 + AC.HEAVY_ARMOR], 90, "AP vs heavy armor")
	t.eq(d.damage.matrix_pct[DT.EMP * 11 + AC.INFANTRY], 0, "EMP vs infantry")
	t.eq(d.damage.matrix_bp[DT.AP * 11 + AC.HEAVY_ARMOR], 9000, "matrix_bp")
	t.eq(d.damage.group_mask, PackedInt32Array([1, 2, 2, 12, 16, 32, 64]), "group masks")
	t.eq(d.damage.nonlethal_mask, 1 << 6, "EMP non-lethal")
	t.eq(d.damage.resist_cap_bp, 5000, "cap")
	t.eq(d.moves.speed_bp[DefEnums.MoveClass.AMPHIBIOUS * 8 + DefEnums.TerrainKind.DEEP], 7000, "amphibious deep")
	t.eq(d.bodies.radius_u[DefEnums.SizeClass.MEDIUM], 563, "medium radius")
	t.eq(d.bodies.turn_apt[DefEnums.SizeClass.MEDIUM], 85, "medium turn")
	t.check(d.bodies.is_structure[DefEnums.SizeClass.S1] == 1 and d.bodies.fp_w[DefEnums.SizeClass.S1] == 1, "s1 is a 1x1 structure class")
	var w: DefWeaponArch = d.weapon_archs[3]
	t.eq(w.id, "warch.tank_cannon", "id")
	t.eq(w.dtype, 1, "dtype")
	t.eq(w.fire_mode, 0, "fire_mode")
	t.eq(w.proj_kind, 1, "proj_kind")
	t.eq(w.proj_speed, 819, "proj_speed")
	t.check(w.homing, "homing")
	t.eq(w.target_mask, 5, "target_mask")
	t.eq(w.splash_radius, 512, "splash_radius")
	t.eq(w.splash_edge_bp, 5000, "splash_edge_bp")
	t.eq(w.range_lo, 6656, "range_lo")
	t.eq(w.range_hi, 9216, "range_hi")
	t.eq(w.reload_lo_mt, 20000, "reload_lo_mt")
	t.eq(w.reload_hi_mt, 32000, "reload_hi_mt")
	t.eq(w.turret_turn, 51, "turret_turn")
	t.eq(w.interceptable, 0, "interceptable")
	t.eq(w.tags, DefEnums.WT_DIRECT_FIRE | DefEnums.WT_ANTI_GROUND, "tank_cannon tags")
	t.check((d.weapon_archs[13].tags & DefEnums.WT_THERMAL_BEAM) != 0, "beam_thermal is thermal_beam")
	t.check((d.weapon_archs[7].tags & DefEnums.WT_ANTI_AIR) != 0 and (d.weapon_archs[7].tags & DefEnums.WT_GUIDED_MISSILE) != 0, "aa_missile tags")
	t.eq(d.economy.start_cr, 7500, "start credits")
	t.eq(d.economy.floor_cost_bp, 6000, "cost floor")
	t.eq(d.economy.floor_reload_bp, 5000, "reload floor")
	t.eq(d.economy.resist_cap_bp, 5000, "economy cap")
	t.eq(d.economy.power_shortage_rate_bp, 5000, "power shortage")
	t.eq(d.economy.research_tier2_t, 900, "tier 2 research")
	t.eq(d.economy.research_tier3_t, 1500, "tier 3 research")
	t.eq(d.economy.build_radius_u, 8192, "build radius")
	t.eq(d.economy.harvest_mcpt, 1000, "harvest rate")
	t.eq(d.economy.unload_mcpt, 6000, "unload rate")
	t.eq(d.economy.collector_capacity_cr, 600, "collector capacity")
	t.eq(d.economy.repair_cost_bp, 5000, "repair cost")
	t.eq(d.economy.detector_default_radius_u, 5120, "detector radius")
	t.eq(d.economy.sell_refund_bp, 5000, "sell refund")


func test_frozen_vocabulary_is_verified(t: TestCtx) -> void:
	var s: DefSources = DefTestKit.stub_sources()
	var g: Dictionary = s.balance["global.json"]
	var dts: Array = g["damage_types"]
	var tmp: int = int(dts[1]["index"])
	dts[1]["index"] = dts[2]["index"]
	dts[2]["index"] = tmp
	t.check(GameData.load_from_sources(s) == null, "swapped damage type indices refuse to load")
	t.check(GameData.last_report.has_rule("V-CNF-05"), "V-CNF-05")
	var s2: DefSources = DefTestKit.stub_sources()
	((s2.balance["global.json"] as Dictionary)["production"] as Dictionary)["cost_floor_pct"] = 50
	t.check(GameData.load_from_sources(s2) == null, "global.json vs bible floor mismatch")
	t.check(GameData.last_report.text().contains("floor_cost"), "names the field")
	var s3: DefSources = DefTestKit.stub_sources()
	((s3.balance["global.json"] as Dictionary)["conventions"] as Dictionary)["tps"] = 30
	t.check(GameData.load_from_sources(s3) == null, "conventions.tps must equal SimConfig.TPS")
	var s4: DefSources = DefTestKit.stub_sources()
	((s4.balance["global.json"] as Dictionary)["weapon_archetypes"] as Dictionary)["tank_cannon"]["index"] = 4
	t.check(GameData.load_from_sources(s4) == null, "archetype index is frozen")


func test_sources_deep_copy(t: TestCtx) -> void:
	var s: DefSources = DefTestKit.stub_sources()
	var c: DefSources = s.deep_copy()
	(c.balance["global.json"] as Dictionary)["version"] = 2
	t.eq(int((s.balance["global.json"] as Dictionary)["version"]), 1, "deep_copy does not alias")
	t.check(GameData.load_from_sources(c) == null, "version gate")
	t.check(GameData.last_report.has_rule("V-SCH-01"), "V-SCH-01 on global.json version")
