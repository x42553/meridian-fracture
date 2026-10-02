extends RefCounted
## VIEW-S1: ViewDefAdapter through both index-space variants, the real GameData of the test kit, and the test events.


func _units() -> Array:
	var u0: DefUnit = DefUnit.new()
	u0.id = "unit.tst.tank"
	u0.faction = -1
	u0.radius = 1690
	u0.size_class = DefEnums.SizeClass.MEDIUM
	u0.move_class = 2
	u0.pres_recipe = ""
	u0.pres_icon = ""
	u0.pres_scale_bp = 12500
	var slot: DefWeaponSlot = DefWeaponSlot.new()
	slot.arch = DefEnums.WeaponArch.TANK_CANNON
	slot.slot = 0
	u0.weapons.append(slot)
	var u1: DefUnit = DefUnit.new()
	u1.id = "unit.tst.rifleman"
	u1.radius = 410
	u1.size_class = DefEnums.SizeClass.INFANTRY
	return [u0, u1]


func _structures() -> Array:
	var s0: DefStructure = DefStructure.new()
	s0.id = "structure.tst.factory"
	s0.fp_w = 4
	s0.fp_h = 3
	s0.exit_dx = 1
	s0.exit_dy = 3
	s0.power = -30
	s0.radius = 3000
	s0.size_class = DefEnums.SizeClass.S2
	s0.pres_recipe = "structure.shared.factory"
	var s1: DefStructure = DefStructure.new()
	s1.id = "structure.tst.hq"
	s1.fp_w = 3
	s1.fp_h = 3
	s1.flags = DefEnums.SF_NO_BUILD
	s1.starts_deployed = true
	return [s0, s1]


func _variant(dense: bool) -> ViewDefAdapter:
	var a: ViewDefAdapter = ViewDefAdapter.new()
	a.setup_tables(_units(), _structures(), dense)
	return a


func _same(t: TestCtx, a: ViewDef, b: ViewDef, what: String) -> void:
	t.eq(a.id, b.id, what + " id")
	t.eq(a.recipe_id, b.recipe_id, what + " recipe")
	t.eq(a.scale_bp, b.scale_bp, what + " scale")
	t.eq(a.move_class, b.move_class, what + " move class")
	t.eq(a.size_class, b.size_class, what + " size class")
	t.near(a.radius_m, b.radius_m, 0.0001, what + " radius")
	t.eq(a.fp_w, b.fp_w, what + " fp_w")
	t.eq(a.fp_h, b.fp_h, what + " fp_h")
	t.eq(a.needs_power, b.needs_power, what + " needs_power")
	t.eq(a.is_hq, b.is_hq, what + " is_hq")
	t.eq(a.warch, b.warch, what + " warch")
	t.near(a.door_cx, b.door_cx, 0.0001, what + " door_cx")
	t.near(a.door_cz, b.door_cz, 0.0001, what + " door_cz")


func test_both_index_space_variants_agree(t: TestCtx) -> void:
	var per_kind: ViewDefAdapter = _variant(false)
	var dense: ViewDefAdapter = _variant(true)
	for uidx: int in 2:
		_same(t, per_kind.def_for(SimEntity.Kind.UNIT, uidx), dense.def_for(SimEntity.Kind.UNIT, uidx), "unit %d" % uidx)
	for sidx: int in 2:
		_same(t, per_kind.def_for(SimEntity.Kind.STRUCTURE, sidx), dense.def_for(SimEntity.Kind.STRUCTURE, 2 + sidx), "structure %d" % sidx)


func test_values(t: TestCtx) -> void:
	var a: ViewDefAdapter = _variant(false)
	var tank: ViewDef = a.def_for(SimEntity.Kind.UNIT, 0)
	t.eq(tank.recipe_id, &"unit.tst.tank", "recipe defaults to the def id")
	t.eq(tank.icon_id, &"unit.tst.tank", "icon defaults to the def id")
	t.eq(tank.scale_bp, 12500, "scale_bp")
	t.eq(tank.warch[0], DefEnums.WeaponArch.TANK_CANNON, "mount 0 archetype")
	t.eq(tank.warch[1], -1, "mount 1 none")
	t.near(tank.radius_m, 1690.0 * 3.0 / 1024.0, 0.001, "radius metres")
	var fac: ViewDef = a.def_for(SimEntity.Kind.STRUCTURE, 0)
	t.eq(fac.recipe_id, &"structure.shared.factory", "explicit recipe")
	t.near(fac.door_cx, -1.5, 0.0001, "door_cx of the 4x3 factory with door [1, 3]")
	t.near(fac.door_cz, 6.0, 0.0001, "door_cz")
	t.eq(fac.exit_dir, 1024, "exit south")
	t.check(fac.needs_power, "needs power")
	t.check_false(fac.is_hq, "factory is no HQ")
	t.check(a.def_for(SimEntity.Kind.STRUCTURE, 1).is_hq, "HQ flag")
	t.check(a.def_for(SimEntity.Kind.UNIT, 0) == a.def_for(SimEntity.Kind.UNIT, 0), "cached instance")


func test_unknown_def_is_placeholder_with_one_warning(t: TestCtx) -> void:
	var a: ViewDefAdapter = _variant(false)
	t.expect_errors(0)
	var p: ViewDef = a.def_for(SimEntity.Kind.UNIT, 999)
	t.check(p.placeholder, "placeholder")
	t.eq(a.weapon_arch(999), -1, "weapon_arch(999)")
	t.eq(a.weapon_arch(999), -1, "second call still -1 (one warning)")
	t.eq(a.weapon_arch(4), 4, "known archetype index")


func test_real_game_data(t: TestCtx) -> void:
	var data: GameData = SimTestKit.data()
	var a: ViewDefAdapter = ViewDefAdapter.new()
	a.setup(data)
	t.eq(a.space, ViewDefAdapter.Space.PER_KIND, "real data is one table per kind")
	var tank: ViewDef = a.def_for(SimEntity.Kind.UNIT, SimTestKit.unit_def("unit.tst.tank"))
	t.eq(tank.id, "unit.tst.tank", "tank id")
	t.check(not tank.placeholder, "real def resolved")
	var turret: ViewDef = a.def_for(SimEntity.Kind.STRUCTURE, SimTestKit.structure_def("structure.tst.turret"))
	t.check(turret.is_defense, "turret is defence")
	t.eq(turret.warch[0], DefEnums.WeaponArch.TANK_CANNON, "turret archetype")
	var hq: ViewDef = a.def_for(SimEntity.Kind.STRUCTURE, SimTestKit.structure_def("structure.tst.hq"))
	t.check(hq.is_hq, "HQ")
	var col: ViewDef = a.def_for(SimEntity.Kind.UNIT, SimTestKit.unit_def("unit.tst.collector"))
	t.gt(col.cargo_cap, 0, "collector capacity")
	t.eq(a.roster_id(0).begins_with("roster."), true, "roster id")
	t.eq(a.roster_id(-1), "", "unknown roster")


func test_roster_ids_of_the_real_balance(t: TestCtx) -> void:
	var data: GameData = GameData.load_default()
	if data == null:
		t.skip("balance data not loadable")
		return
	var a: ViewDefAdapter = ViewDefAdapter.new()
	a.setup(data)
	t.eq(data.rosters.size(), 32, "32 rosters")
	for i: int in data.rosters.size():
		t.check(a.roster_id(i).begins_with("roster."), "roster %d id" % i)
	var sample_unit: ViewDef = a.def_for(SimEntity.Kind.UNIT, 0)
	t.check(not sample_unit.placeholder, "first real unit resolves")
	t.check(sample_unit.faction_code != "" or sample_unit.id.begins_with("unit.shared"), "faction code")


func test_test_events_cover_the_reaction_table(t: TestCtx) -> void:
	var real: Dictionary = ViewTestEvents.real_constant_codes()
	for nm: String in real.keys():
		var code: int = real[nm]
		t.eq(ViewTestEvents.NAMES.get(code, ""), nm, "name table entry for %s" % nm)
	var unmapped: PackedStringArray = PackedStringArray(["REVEAL_AREA", "PAUSED", "UNPAUSED"])
	for reaction: String in ViewTestEvents.REACTIONS.keys():
		var codes: Array = ViewTestEvents.codes_of(reaction)
		if unmapped.has(reaction):
			t.eq(codes.size(), 0, "%s has no kernel event" % reaction)
			continue
		t.gt(codes.size(), 0, "%s mapped" % reaction)
		var b: PackedInt32Array = ViewTestEvents.for_reaction(reaction, 42)
		t.eq(b.size(), codes.size() * ViewTestEvents.STRIDE, "%s records" % reaction)
		for k: int in codes.size():
			t.eq(b[k * ViewTestEvents.STRIDE], codes[k] as int, "%s code" % reaction)
			t.eq(b[k * ViewTestEvents.STRIDE + 1], 42, "%s tick" % reaction)
	t.eq(ViewTestEvents.REACTIONS.size(), 31, "the 31 names of the reaction table")


func test_test_events_round_trip_a_real_buffer(t: TestCtx) -> void:
	var buf: SimEventBuffer = SimEventBuffer.new()
	var rec: PackedInt32Array = ViewTestEvents.sample(SimEvent.SPAWNED, 7)
	ViewTestEvents.emit_into(buf, rec)
	var taken: PackedInt32Array = buf.take()
	t.eq(taken, rec, "record survives the kernel buffer")
	t.eq(ViewTestEvents.count(ViewTestEvents.batch([rec, rec])), 2, "batch count")
