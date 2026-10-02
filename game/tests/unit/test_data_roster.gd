extends RefCounted
## DATA-06: roster resolution (data_balance 5.7 / 10.1 "roster resolution"): availability, replacements, lists, overrides,
## trait grants, producible orderings, self-check V-ROS-01 (clean x32) and the V-ROS-0x negative cases.

const K := DefEnums.Kind

static var _real: GameData = null


static func real() -> GameData:
	if _real == null:
		_real = DefTestKit.stub_game_data(true)
	return _real


func _counts(r: DefRoster) -> Array:
	var combat: int = 0
	var service: int = 0
	var structs: int = 0
	for u: DefUnit in r.units:
		if u == null:
			continue
		if u.unit_class == DefEnums.UnitClass.SERVICE:
			service += 1
		elif u.unit_class == DefEnums.UnitClass.BASELINE or u.unit_class == DefEnums.UnitClass.UNIQUE:
			combat += 1
	for s: DefStructure in r.structures:
		if s != null:
			structs += 1
	return [combat, service, structs]


func test_sizes_of_all_32_rosters(t: TestCtx) -> void:
	var d: GameData = real()
	if not t.not_null(d, "load: " + GameData.last_report.text(6)):
		return
	t.eq(d.rosters.size(), 32, "32 rosters")
	var vanilla: int = 0
	var subs: int = 0
	for r: DefRoster in d.rosters:
		var braw: Dictionary = d._sources.bible["rosters"][r.id]
		var res: Dictionary = braw["resolved"]
		var c: Array = _counts(r)
		t.eq(c, [res["combat_unit_ids"].size(), res["service_unit_ids"].size(), res["structure_ids"].size()], "%s sizes equal the bible's resolved block" % r.id)
		var nec: bool = r.id.begins_with("roster.nec.")
		if r.is_vanilla:
			vanilla += 1
			t.eq(c, [13, 4, 15 if nec else 14], "%s: 13 + 4 + %d" % [r.id, 15 if nec else 14])
			t.eq(r.research_list.size(), 2, "vanilla: 2 research")
			t.eq(r.replaced_by.size(), 0, "vanilla: no replacements")
			t.eq(r.parent, -1, "vanilla has no parent")
		else:
			subs += 1
			t.eq(c, [12, 4, 15 if nec else 14], "%s: 12 + 4 + %d" % [r.id, 15 if nec else 14])
			t.eq(r.research_list.size(), 3, "subfaction: 3 research")
			t.eq(r.replaced_by.size(), 2, "2 replacements")
			t.check(r.parent >= 0 and d.rosters[r.parent].is_vanilla and d.rosters[r.parent].faction == r.faction, "parent is the faction's vanilla")
		t.eq(r.power_list.size(), 3, "3 powers")
		t.check(r.superweapon >= 0 and r.superweapon_def != null, "superweapon")
		t.check(r.hq_idx >= 0 and r.mcv_idx >= 0, "start structures")
	t.eq([vanilla, subs], [8, 24], "8 vanilla + 24 subfactions")


func test_v_ros_01_is_clean_for_all_rosters(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	t.eq(d.report.count_rule("V-ROS-01"), 0, "no V-ROS-01 in the load report")
	for r: DefRoster in d.rosters:
		t.eq(DefRosterBuilder.golden_mismatches(d, r).size(), 0, "%s clean" % r.id)


func test_canada(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var r: DefRoster = d.roster_for("napc", "canada")
	t.check(r.has_unit(d.unit_idx("unit.napc.beaver_amphibious_apc")) and r.has_unit(d.unit_idx("unit.napc.narwhal_amphibious_tank")), "has Beaver and Narwhal")
	for id: String in ["unit.napc.pathfinder_apc", "unit.napc.guardian_tank", "unit.napc.titan_gunship"]:
		t.check(not r.has_unit(d.unit_idx(id)), "lacks %s (replaced / removed)" % id)
		t.check(r.unit(d.unit_idx(id)) == null, "unit() of an absent def is null")
	t.eq(r.power_list, PackedInt32Array([d.power_idx("power.napc.uav_sweep"), d.power_idx("power.napc.field_repair_drop"), d.power_idx("power.napc.floating_workshop")]), "power_list")
	t.eq(r.research_list, PackedInt32Array([d.research_idx("research.napc.adaptive_plating"), d.research_idx("research.napc.joint_tactical_links"), d.research_idx("research.napc.sealed_compartments")]), "research_list")
	t.eq(r.replaced_by, {d.unit_idx("unit.napc.pathfinder_apc"): d.unit_idx("unit.napc.beaver_amphibious_apc"), d.unit_idx("unit.napc.guardian_tank"): d.unit_idx("unit.napc.narwhal_amphibious_tank")}, "replaced_by")
	t.eq(r.research_slot(d.research_idx("research.napc.sealed_compartments")), 2, "research slot")
	t.eq(r.power_slot(d.power_idx("power.napc.floating_workshop")), 2, "power slot")
	t.eq(r.research_slot(d.research_idx("research.ae.circular_armor")), -1, "foreign research")
	t.eq(r.superweapon, d.superweapon_idx("superweapon.napc.atlas_kinetic_array"), "Atlas")
	t.eq(r.modifier_list.size(), 6, "2 parent + 4 own modifiers, parents first")
	t.check(not d.modifiers[r.modifier_list[0]].owner_is_roster and d.modifiers[r.modifier_list[5]].owner_is_roster, "parents first")
	t.eq(r.hq_idx, d.structure_idx("structure.shared.headquarters"), "hq")
	t.eq(r.mcv_idx, d.unit_idx("unit.shared.mobile_construction_vehicle"), "mcv")
	# spawnables: the summons of the roster's powers (UAV, cargo aircraft, pontoon) are clones inside the roster
	var want: PackedInt32Array = PackedInt32Array([d.unit_idx("summon.napc.cargo_aircraft"), d.unit_idx("summon.napc.pontoon"), d.unit_idx("summon.napc.uav")])
	want.sort()
	t.eq(r.spawnables, want, "spawnables")
	for i: int in want:
		t.check(r.has_unit(i) and r.unit(i).unit_class == DefEnums.UnitClass.SUMMON, "summon clone in the roster")
	t.check(not d.roster_for("napc", "mexico").has_unit(d.unit_idx("summon.napc.pontoon")), "Mexico has no floating workshop")
	# the base defs are never touched
	t.check(r.unit(d.unit_idx("unit.napc.narwhal_amphibious_tank")) != d.units[d.unit_idx("unit.napc.narwhal_amphibious_tank")], "clones, not the base def")


func test_replacements_and_removals_everywhere(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	for r: DefRoster in d.rosters:
		var delta: Dictionary = d._sources.bible["rosters"][r.id]["delta"]
		for rp: Dictionary in delta["replacements"]:
			var a: int = d.unit_idx(rp["replaced_unit_id"])
			var b: int = d.unit_idx(rp["replacement_unit_id"])
			t.check(not r.has_unit(a) and r.has_unit(b), "%s: %s -> %s" % [r.id, rp["replaced_unit_id"], rp["replacement_unit_id"]])
			t.eq(r.replaced_by.get(a, -1), b, "replaced_by")
			t.check((d.units[b].tags & d.units[a].tags) == d.units[a].tags, "role tags carried over (V-ROS-06)")
			t.eq(d.units[b].introduced_by, r.index, "introduced_by")
		for id: String in delta["removed_without_replacement_unit_ids"]:
			t.check(not r.has_unit(d.unit_idx(id)), "%s: %s removed" % [r.id, id])
		t.check(r.is_vanilla or not r.power_list.has(d.factions[r.faction].vanilla_power), "%s loses the vanilla-only power" % r.id)
		t.check(not r.is_vanilla or r.power_list.has(d.factions[r.faction].vanilla_power), "vanilla keeps it")


func test_unit_overrides_of_pd_collectors(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var col: int = d.unit_idx("unit.shared.collector")
	for sub: String in ["", "australia", "indonesia", "japan"]:
		var c: DefUnit = d.roster_for("pd", sub).unit(col)
		t.eq(c.move_class, DefEnums.MoveClass.AMPHIBIOUS, "PD %s collector is amphibious" % sub)
		t.eq(c.deep_speed_bp, 7000, "70 % of land speed on deep water")
		t.check((c.tags & DefEnums.UT_AMPHIBIOUS) != 0, "tag amphibious added")
		t.eq(c.layer_mask, DefEnums.L_GROUND | DefEnums.L_WATER, "layer mask follows the class")
		t.eq(c.speed_water, DefMoveTable.effective_speed(d.moves, c.speed, c.move_class, DefEnums.TerrainKind.DEEP, 7000, c.water_mult_bp), "speed_water recomputed")
	var other: DefUnit = d.roster_for("napc").unit(col)
	t.eq(other.move_class, d.units[col].move_class, "other factions keep the wheeled class")
	t.check((other.tags & DefEnums.UT_AMPHIBIOUS) == 0, "and the tags")
	t.check((d.units[col].tags & DefEnums.UT_AMPHIBIOUS) == 0, "the base def is untouched")


func test_trait_grants_are_applied_to_clones(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var fac: int = d.structure_idx("structure.shared.factory")
	for sub: String in ["", "canada", "mexico", "usa"]:
		var f: DefStructure = d.roster_for("napc", sub).structure(fac)
		t.eq(f.ability_of(DefEnums.AbilityKind.AURA_REGEN).params["radius_u"], 5120, "NAPC %s factory apron" % sub)
	t.check(d.roster_for("nec").structure(fac).ability_of(DefEnums.AbilityKind.AURA_REGEN) == null, "other factions have no apron")
	t.check(d.structures[fac].ability_of(DefEnums.AbilityKind.AURA_REGEN) == null, "the base def has none")
	var eng: int = d.unit_idx("unit.shared.engineer")
	t.check(d.roster_for("ae").unit(eng).ability_of(DefEnums.AbilityKind.SALVAGE) != null, "AE engineers salvage")
	t.check(d.roster_for("def").unit(eng).ability_of(DefEnums.AbilityKind.SALVAGE) == null, "DEF engineers do not")
	t.eq(d.roster_for("ae").unit(eng).ability_mask & (1 << DefEnums.AbilityKind.SALVAGE), 1 << DefEnums.AbilityKind.SALVAGE, "ability_mask updated")
	t.check(d.roster_for("ae").unit(d.unit_idx("unit.ae.reclaimer")).ability_of(DefEnums.AbilityKind.SALVAGE) != null, "Reclaimer carries salvage natively (the grant is skipped there)")
	t.check(d.roster_for("sap").player_params.has("defense_power_reserve.reserve_t"), "SAP player params")
	t.check(d.roster_for("napc").player_params.is_empty(), "NAPC has none")


func test_orderings_and_queries(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	for r: DefRoster in d.rosters:
		var prev: int = -1
		var pu: DefUnit = null
		for i: int in r.producible_units:
			var u: DefUnit = r.units[i]
			t.check(u.unit_class <= DefEnums.UnitClass.UNIQUE, "no summons / drones in producible_units")
			if pu != null:
				t.check(pu.tier < u.tier or (pu.tier == u.tier and (pu.cost < u.cost or (pu.cost == u.cost and prev < i))), "%s ordered by (tier, cost, index)" % r.id)
			pu = u
			prev = i
		t.check(not r.producible_structures.has(r.hq_idx), "HQ is not producible")
		t.eq(r.producible_structures.size(), int(_counts(r)[2]) - 1, "every structure but the HQ")
		var prod: DefRoster = r
		for si: int in prod.producible_structures:
			var us: PackedInt32Array = prod.units_produced_by(si)
			for k: int in range(1, us.size()):
				t.check(prod.producible_units.find(us[k - 1]) < prod.producible_units.find(us[k]), "units_produced_by keeps the producible order")
	t.check(DefRoster.prereqs_met(0b0110, 0b1111) and not DefRoster.prereqs_met(0b0110, 0b0100), "prereqs_met")
	var canada: DefRoster = d.roster_for("napc", "canada")
	var sel: int = d.selector_idx("selector.land_combat_vehicles")
	var us2: PackedInt32Array = canada.selector_units(sel)
	t.check(us2.has(d.unit_idx("unit.napc.narwhal_amphibious_tank")) and not us2.has(d.unit_idx("unit.napc.guardian_tank")), "selector_units works on the roster's own clones")
	t.eq(canada.selector_units(sel), us2, "cached")
	var mask: PackedByteArray = canada.selector_mask_units(sel)
	t.eq(mask.size(), d.units.size(), "mask size")
	var count: int = 0
	for b: int in mask:
		count += b
	t.eq(count, us2.size(), "mask agrees with the list")
	t.eq(canada.selector_structures(d.selector_idx("selector.defensive_structures")).size(), 4, "4 defenses in Canada (3 shared + its advanced one)")
	t.eq(canada.selector_units(-1).size(), 0, "bad selector index")


func test_base_roster(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var b: DefRoster = d.base_roster
	t.eq(b.id, "roster.base", "id")
	var missing: int = 0
	for u: DefUnit in b.units:
		if u == null:
			missing += 1
	t.eq(missing, 0, "contains every unit def")
	for s: DefStructure in b.structures:
		if s == null:
			missing += 1
	t.eq(missing, 0, "and every structure")
	t.eq(b.replaced_by.size(), 0, "no replacements")
	t.eq(b.modifier_list.size(), 0, "no modifiers")
	t.eq(b.unit(d.unit_idx("unit.napc.guardian_tank")).cost, d.units[d.unit_idx("unit.napc.guardian_tank")].cost, "base values")
	t.check(b.has_unit(d.unit_idx("unit.napc.pathfinder_apc")) and b.has_unit(d.unit_idx("unit.napc.beaver_amphibious_apc")), "both the replaced and the replacement")


func test_hash_determinism(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var d2: GameData = GameData.load_from_sources(DefTestKit.stub_sources(true))
	t.eq(d2.data_hash(), d.data_hash(), "two loads: same data_hash")
	t.eq(d2.table_hashes["rosters"], d.table_hashes["rosters"], "same roster table hash")
	t.check(DefValidator.check_frozen(d), "frozen: nothing mutated a def after the build")
	var h1: int = d.rosters[0].hash_into(DefHash.OFFSET)
	var h2: int = d.rosters[1].hash_into(DefHash.OFFSET)
	t.ne(h1, h2, "different rosters hash differently")
	t.eq(d2.rosters[0].hash_into(DefHash.OFFSET), h1, "per-roster hash reproducible")


func test_roster_negative_cases(t: TestCtx) -> void:
	# V-ROS-03: a subfaction with a missing replacement
	var s: DefSources = DefTestKit.stub_sources(true)
	var canada: Dictionary = (s.bible["rosters"] as Dictionary)["roster.napc.canada"]
	(canada["delta"]["replacements"] as Array).pop_back()
	t.check(GameData.load_from_sources(s) == null, "1 replacement instead of 2 refuses to load")
	t.check(GameData.last_report.has_rule("V-ROS-03"), "V-ROS-03")
	# V-ROS-04: the vanilla-only power must be the unavailable one
	var s2: DefSources = DefTestKit.stub_sources(true)
	(((s2.bible["rosters"] as Dictionary)["roster.napc.canada"] as Dictionary)["delta"] as Dictionary)["unavailable_support_power_ids"] = []
	t.check(GameData.load_from_sources(s2) == null, "vanilla-only power still available")
	t.check(GameData.last_report.has_rule("V-ROS-04"), "V-ROS-04")
	# V-ROS-02: replacement of a unit that is not a baseline unit of the faction
	var s3: DefSources = DefTestKit.stub_sources(true)
	var rep0: Dictionary = (((s3.bible["rosters"] as Dictionary)["roster.napc.canada"] as Dictionary)["delta"]["replacements"] as Array)[0]
	rep0["replaced_unit_id"] = "unit.nec.leopard_tank"
	t.check(GameData.load_from_sources(s3) == null, "foreign replaced unit")
	t.check(GameData.last_report.has_rule("V-ROS-02"), "V-ROS-02")
	# V-ROS-01: the bible's derived block disagrees with the resolution
	var s4: DefSources = DefTestKit.stub_sources(true)
	var res: Dictionary = (((s4.bible["rosters"] as Dictionary)["roster.napc.mexico"] as Dictionary)["resolved"]) as Dictionary
	(res["combat_unit_ids"] as Array).pop_back()
	t.check(GameData.load_from_sources(s4) == null, "stale derived block")
	t.check(GameData.last_report.has_rule("V-ROS-01"), "V-ROS-01 names the roster")
	# V-ROS-01 on a golden application: a wrong eligible list
	var s5: DefSources = DefTestKit.stub_sources(true)
	var apps: Array = (((s5.bible["rosters"] as Dictionary)["roster.napc.usa"] as Dictionary)["resolved"]["modifier_applications"]) as Array
	((apps[0] as Dictionary)["eligible_unit_ids"] as Array).clear()
	t.check(GameData.load_from_sources(s5) == null, "wrong golden application")
	t.check(GameData.last_report.text().contains("eligible_unit_ids"), "reports which application")
