extends RefCounted
## CB-00: constants and the compiled combat tables derived from Def* (DefPlayerView / DefRoster / DefWeaponSlot).

func test_geometry_and_filters(t: TestCtx) -> void:
	t.eq([SimCombatConsts.wrap_signed(2048), SimCombatConsts.wrap_signed(4095), SimCombatConsts.wrap_signed(-1), SimCombatConsts.wrap_signed(0)], [-2048, -1, -1, 0], "U-GEOM-1")
	var f: int = SimCombatConsts.make_filter(1 << SimCombatConsts.DT_BULLET, SimCombatConsts.DC_DIRECT, SimCombatConsts.DC_SPLASH | SimCombatConsts.DC_INDIRECT)
	t.check(SimCombatConsts.filter_match(f, SimCombatConsts.DT_BULLET, SimCombatConsts.DC_DIRECT), "bullet direct matches")
	t.check(not SimCombatConsts.filter_match(f, SimCombatConsts.DT_BULLET, SimCombatConsts.DC_DIRECT | SimCombatConsts.DC_SPLASH), "forbidden splash bit rejects")
	t.check(not SimCombatConsts.filter_match(f, SimCombatConsts.DT_BULLET, SimCombatConsts.DC_INDIRECT), "required direct bit missing rejects")
	t.check(not SimCombatConsts.filter_match(f, SimCombatConsts.DT_HE, SimCombatConsts.DC_DIRECT), "type not in the filter rejects")
	t.check(SimCombatConsts.filter_match(SimCombatConsts.FILTER_ALL_WEAPON, SimCombatConsts.DT_RAIL, SimCombatConsts.DC_STRATEGIC), "all-weapon matches every weapon type")
	t.check(not SimCombatConsts.filter_match(SimCombatConsts.FILTER_ALL_WEAPON, SimCombatConsts.DT_EMP, SimCombatConsts.DC_DIRECT), "all-weapon excludes EMP")
	t.check(SimCombatConsts.filter_match(SimCombatConsts.FILTER_DIRECT_ONLY, SimCombatConsts.DT_AP, SimCombatConsts.DC_DIRECT), "Dust Screen filter: direct hits")
	t.check(not SimCombatConsts.filter_match(SimCombatConsts.FILTER_DIRECT_ONLY, SimCombatConsts.DT_AP, SimCombatConsts.DC_INDIRECT | SimCombatConsts.DC_SPLASH), "Dust Screen filter: not blasts")
	t.eq(SimCombatConsts.DT_MASK_ALL_WEAPON & (1 << SimCombatConsts.DT_EMP), 0, "mask bit of EMP clear")


func test_damage_type_ids_follow_the_data_vocabulary(t: TestCtx) -> void:
	t.eq(SimCombatConsts.DT_BULLET, DefEnums.DamageType.BULLET, "bullet")
	t.eq(SimCombatConsts.DT_AP, DefEnums.DamageType.AP, "ap")
	t.eq(SimCombatConsts.DT_HE, DefEnums.DamageType.HE, "he")
	t.eq(SimCombatConsts.DT_THERMAL, DefEnums.DamageType.THERMAL, "thermal")
	t.eq(SimCombatConsts.DT_RAIL, DefEnums.DamageType.RAIL, "rail")
	t.eq(SimCombatConsts.DT_KINETIC, DefEnums.DamageType.KINETIC, "kinetic")
	t.eq(SimCombatConsts.DT_EMP, DefEnums.DamageType.EMP, "emp")
	t.eq(SimCombatConsts.KIND_WRECK, SimEntity.Kind.WRECK, "kind numbers mirror the kernel")
	t.eq(SimCombatConsts.LAYER_UNDERWATER, SimEntity.Layer.UNDERWATER, "layer numbers mirror the kernel")


func test_tables_from_small_data(t: TestCtx) -> void:
	var w: SimWorld = CombatKit.world()
	var tank: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var cd: SimCombatDef = CombatKit.cdef(w, tank)
	t.not_null(cd, "tank def compiled")
	t.eq(cd.n_mounts, 1, "one mount")
	t.eq(cd.armor, DefEnums.ArmorClass.MEDIUM_ARMOR, "armor class from the def")
	var tb: SimCombatTables = w.combat.tables_of(1)
	var wh: SimCombatWarhead = tb.warheads[cd.mount_val(0, SimCombatDef.MT_WH)]
	t.eq(wh.damage, 141, "damage of the roster clone slot")
	t.eq(wh.dtype, DefEnums.DamageType.AP, "damage type from the archetype")
	t.eq(wh.splash_r, 512, "splash radius")
	t.eq(wh.splash_inner, 128, "splash inner = outer / 4")
	t.eq(wh.splash_edge_bp, 5000, "edge fraction")
	t.eq(wh.friendly_fire, 1, "splash hurts friendlies by default")
	t.eq(wh.delivery, SimCombatConsts.DELIV_DIRECT, "direct fire")
	t.eq(wh.suppressive, 0, "not suppressive")
	t.eq(wh.nonlethal, 0, "lethal")
	t.eq(cd.mount_val(0, SimCombatDef.MT_KIND), SimCombatConsts.MK_TURRET, "turret mount")
	t.eq(cd.mount_val(0, SimCombatDef.MT_TURN), 51, "turret turn rate from the archetype")
	t.eq(cd.mount_val(0, SimCombatDef.MT_ARC_HALF), Fp.ANGLE_HALF, "360 degree arc")
	t.eq(cd.mount_val(0, SimCombatDef.MT_AIM_TOL), SimCombatConsts.AIM_TOL_DEFAULT, "default aim tolerance")
	var rifle: SimEntity = CombatKit.rifle(w, 1, 32, 30)
	var rd: SimCombatDef = CombatKit.cdef(w, rifle)
	t.eq(rd.armor, DefEnums.ArmorClass.INFANTRY, "infantry armor")
	t.check((rd.cflags & SimCombatConsts.CF_SUPPRESSIBLE) != 0, "infantry is suppressible")
	t.check((cd.cflags & SimCombatConsts.CF_SUPPRESSIBLE) == 0, "tanks are not")
	var tur: SimEntity = CombatKit.turret(w, 1, 40, 40)
	var sd: SimCombatDef = CombatKit.cdef(w, tur)
	t.eq(sd.n_mounts, 1, "turret structure armed")
	t.eq(sd.needs_power, 1, "powered defence")
	t.eq(sd.emp_susceptible, 1, "EMP shuts powered defences")
	var hq: SimEntity = w.get_entity(1)
	t.eq(CombatKit.cdef(w, hq).n_mounts, 0, "HQ unarmed")
	t.eq(w.combat.matrix(DefEnums.DamageType.EMP, DefEnums.ArmorClass.INFANTRY), 0, "matrix copy: EMP vs infantry")
	t.eq(w.combat.matrix(DefEnums.DamageType.BULLET, DefEnums.ArmorClass.MEDIUM_ARMOR), 4000, "matrix copy: bullet vs medium armor")
	t.check(w.combat.tables_of(-1) == w.combat.neutral_tables, "neutral owner uses the neutral table")


func test_warhead_from_packet_and_slot_flags(t: TestCtx) -> void:
	var p: DefImpactPacket = DefImpactPacket.new()
	p.damage = 150
	p.dtype = DefEnums.DamageType.EMP
	p.radius = 8192
	p.edge_bp = 10000
	p.non_lethal = true
	var sw: DefSuperweapon = DefSuperweapon.new()
	sw.params = {"weapon_disable_t": 160, "structure_shutdown_t": 360}
	var w: SimCombatWarhead = SimCombatWarhead.from_packet(p, sw, 1 << DefEnums.DamageType.EMP, "aurora")
	t.eq([w.damage, w.splash_r, w.packet, w.friendly_fire, w.nonlethal], [150, 8192, 0, 0, 1], "Aurora: no packet, enemies only, nonlethal")
	t.eq([w.emp_unit_ticks, w.emp_struct_ticks], [160, 360], "durations from the superweapon params")
	t.eq(w.emp_class_mask & SimCombatConsts.EC_INFANTRY, 0, "infantry unaffected")
	p.dtype = DefEnums.DamageType.KINETIC
	p.non_lethal = false
	var k: SimCombatWarhead = SimCombatWarhead.from_packet(p, null, 1 << DefEnums.DamageType.EMP, "atlas")
	t.eq([k.packet, k.friendly_fire, k.delivery, k.nonlethal], [1, 1, SimCombatConsts.DELIV_STRATEGIC, 0], "kinetic strike is a Trident packet")
	var s: DefWeaponSlot = DefWeaponSlot.new()
	s.flags = DefEnums.WF_SUPPRESSIVE
	s.damage = 5
	var sh: SimCombatWarhead = SimCombatWarhead.from_slot(s, null, 0, "sup")
	t.eq(sh.suppressive, 1, "WF_SUPPRESSIVE -> suppressive warhead")


func test_tables_from_real_balance(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	t.not_null(d, "real balance loads")
	if d == null:
		return
	var gg_idx: int = d.unit_idx("unit.olm.gate_guard")
	var olm: DefRoster = d.base_roster
	for r: DefRoster in d.rosters:
		if r.has_unit(gg_idx):
			olm = r
			break
	var view: DefPlayerView = DefPlayerView.new(d, olm)
	var tb: SimCombatTables = SimCombatTables.build(d, view)
	t.eq(tb.units.size(), d.units.size(), "one slot per unit def")
	var gg: SimCombatDef = tb.def_of(SimEntity.Kind.UNIT, gg_idx)
	if gg == null:
		t.skip("gate guard not in this roster")
	else:
		t.eq(gg.dir_rows.size(), 5, "Gate Guard: one directional row")
		t.eq([gg.dir_rows[1], gg.dir_rows[2], gg.dir_rows[3], gg.dir_rows[4]], [0, 683, 2500, 0], "front arc +-60 deg, 25 %, layer 0")
		t.check(SimCombatConsts.filter_match(gg.dir_rows[0], SimCombatConsts.DT_BULLET, SimCombatConsts.DC_DIRECT), "bullets in front")
		t.check(not SimCombatConsts.filter_match(gg.dir_rows[0], SimCombatConsts.DT_BULLET, SimCombatConsts.DC_DIRECT | SimCombatConsts.DC_SPLASH), "not blasts")
	var neutral: SimCombatTables = SimCombatTables.build(d, null)
	var ural: SimCombatDef = neutral.def_of(SimEntity.Kind.UNIT, d.unit_idx("unit.def.ural_assault_tank"))
	t.eq([ural.aps_count, ural.aps_cooldown, ural.aps_radius], [1, 240, 3072], "Ural point defence block")
	var bear: SimCombatDef = neutral.def_of(SimEntity.Kind.UNIT, d.unit_idx("unit.def.bear_siege_crawler"))
	t.eq(bear.dir_rows.size(), 10, "Bear: front and rear rows")
	t.eq([bear.dir_rows[3], bear.dir_rows[8]], [3000, -2500], "front +30 %, rear -25 % (vulnerability)")
	var armed: int = 0
	for u: SimCombatDef in neutral.units:
		if u != null and u.n_mounts > 0:
			armed += 1
			for m: int in u.n_mounts:
				t.check(u.mount_val(m, SimCombatDef.MT_WH) < neutral.warheads.size(), "warhead index valid")
	t.check(armed > 50, "many units are armed (%d)" % armed)
	var aa: int = 0
	for u2: SimCombatDef in neutral.units:
		if u2 != null and (u2.cflags & SimCombatConsts.CF_HAS_AA) != 0:
			aa += 1
	t.check(aa > 0, "some units carry anti-air")
