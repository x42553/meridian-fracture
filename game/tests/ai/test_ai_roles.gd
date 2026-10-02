extends RefCounted
## AiRoleResolver over all 32 rosters (ai.md 5.5.1 / 10.1 test_ai_roles).

const T2_TANK: PackedStringArray = ["canada", "eurocorps", "russia", "china", "japan", "india", "south_africa"]


func _res(rid: String) -> AiRoleResolver:
	var d: GameData = SimMatchKit.data()
	return AiRoleResolver.resolve(d, d.rosters[d.roster_idx(rid)], AiDataStore.load_default())


func test_essentials_present_in_every_roster(t: TestCtx) -> void:
	var d: GameData = SimMatchKit.data()
	for rid: String in d.roster_ids():
		var r: AiRoleResolver = _res(rid)
		t.eq(r.missing_roles, PackedInt32Array(), "%s: essential roles present" % rid)


func test_tank_tier(t: TestCtx) -> void:
	var d: GameData = SimMatchKit.data()
	for rid: String in d.roster_ids():
		var r: AiRoleResolver = _res(rid)
		var short: String = rid.get_slice(".", 2)
		var want: int = 2 if T2_TANK.has(short) else 1
		t.eq(r.min_tier(AiTypes.R_TANK_MAIN), want, "%s TANK_MAIN tier" % rid)


func test_optional_roles(t: TestCtx) -> void:
	var d: GameData = SimMatchKit.data()
	for rid: String in d.roster_ids():
		var r: AiRoleResolver = _res(rid)
		var short: String = rid.get_slice(".", 2)
		var fam: String = rid.get_slice(".", 1)
		if rid == "roster.pd.japan":
			t.check_false(r.has_role(AiTypes.R_ARTILLERY), "japan has no artillery role")
		else:
			t.check(r.has_role(AiTypes.R_ARTILLERY), "%s has ARTILLERY" % rid)
		var healer: bool = fam == "napc" and short != "mexico"
		t.eq(r.has_role(AiTypes.R_HEALER), healer, "%s HEALER only for NAPC except Mexico" % rid)


func test_replaced_units_never_appear(t: TestCtx) -> void:
	var d: GameData = SimMatchKit.data()
	for rid: String in d.roster_ids():
		var r: AiRoleResolver = _res(rid)
		var ro: DefRoster = d.rosters[d.roster_idx(rid)]
		for role: int in AiTypes.ROLE_COUNT:
			for u: int in r.units_of(role):
				t.check_false(ro.replaced_by.has(u), "%s: replaced def %s in role %s" % [rid, d.units[u].id, AiTypes.ROLE_NAMES[role]])


func test_masks_and_structure_kinds(t: TestCtx) -> void:
	var d: GameData = SimMatchKit.data()
	var r: AiRoleResolver = _res("roster.napc.vanilla")
	var coll: int = d.unit_idx("unit.shared.collector")
	t.check(r.has_bit(coll, AiTypes.R_COLLECTOR), "collector role")
	t.check(r.has_bit(d.unit_idx("unit.shared.engineer"), AiTypes.R_ENGINEER))
	t.check(r.has_bit(d.unit_idx("unit.shared.engineer"), AiTypes.R_SALVAGER), "engineer in the SALVAGER list")
	t.check(r.has_bit(d.unit_idx("unit.shared.mobile_construction_vehicle"), AiTypes.R_MCV))
	var ro: DefRoster = d.rosters[d.roster_idx("roster.napc.vanilla")]
	var kinds: Dictionary = {
		"structure.shared.headquarters": AiTypes.StructKind.HQ, "structure.shared.generator": AiTypes.StructKind.GENERATOR,
		"structure.shared.refinery": AiTypes.StructKind.REFINERY, "structure.shared.barracks": AiTypes.StructKind.BARRACKS,
		"structure.shared.factory": AiTypes.StructKind.FACTORY, "structure.shared.radar": AiTypes.StructKind.RADAR,
		"structure.shared.laboratory": AiTypes.StructKind.LAB, "structure.shared.airfield": AiTypes.StructKind.AIRFIELD,
		"structure.shared.dock": AiTypes.StructKind.DOCK, "structure.shared.watchtower": AiTypes.StructKind.WATCHTOWER,
		"structure.shared.anti_tank_turret": AiTypes.StructKind.AT_TURRET, "structure.shared.aa_battery": AiTypes.StructKind.AA_BATTERY,
		"structure.napc.atlas_kinetic_array": AiTypes.StructKind.SUPERWEAPON,
	}
	for sid: String in kinds:
		t.eq(AiRoleResolver.classify_structure(d, ro, d.structure_idx(sid)), kinds[sid], sid)
	t.eq(r.first(AiTypes.R_COLLECTOR), coll, "first COLLECTOR def")


func test_profiles_of_every_producible_def(t: TestCtx) -> void:
	var d: GameData = SimMatchKit.data()
	var shared: AiSharedData = AiSharedData.new()
	var stub: AiMockWorldView = AiMockWorldView.new(0)
	shared.bind(stub)
	var armed: int = 0
	for ri: int in d.rosters.size():
		var ro: DefRoster = d.rosters[ri]
		for u: int in ro.producible_units:
			var p: AiUnitProfile = shared.unit_profile(ri, u)
			if not t.not_null(p, "%s profile" % d.units[u].id):
				continue
			t.gt(p.hp, 0, "%s hp" % d.units[u].id)
			var ud: DefUnit = ro.unit(u)
			var expects_dps: bool = (ud.tags & DefEnums.UT_COMBAT) != 0 and (ud.flags & DefEnums.UF_UNARMED) == 0 and not ud.weapons.is_empty()
			if expects_dps:
				armed += 1
				t.gt(p.dps_avg_x100() + p.dps_x100_alt[0] + p.dps_x100_alt[1] + p.dps_x100_alt[2], 0, "%s (%s) has damage" % [d.units[u].id, ro.id])
				t.gt(p.hits_mask, 0)
		for s: int in ro.producible_structures:
			t.not_null(shared.struct_profile(ri, s), "%s structure profile" % d.structures[s].id)
	t.gt(armed, 300, "armed producible defs profiled across the 32 rosters")
	# spot values: a rifle squad hurts infantry, cannot hit aircraft with a ground-only weapon set
	var rifle: AiUnitProfile = shared.unit_profile(d.roster_idx("roster.napc.vanilla"), d.unit_idx("unit.napc.rifle_squad"))
	t.gt(rifle.dps_x100[DefEnums.ArmorClass.INFANTRY], 0)
	t.gt(rifle.power, 0)
	t.eq(rifle.category, AiTypes.Cat.INFANTRY)
