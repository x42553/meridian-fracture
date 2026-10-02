extends RefCounted
## AB-08 power glue on the REAL balance data (S15, S08): latched buff zones, delivery powers, global-effect windows,
## marks, strikes and the superweapon entry points; plus a generated test that applies every one of the 48 powers and the
## 8 superweapons and asserts that something in the sim changed.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")

const CELL: int = 1024


func _c(cell: int) -> int:
	return cell * CELL + CELL / 2


func _pw(w: SimWorld, id: String) -> int:
	return w.data.power_idx(id)


func _sw(w: SimWorld, id: String) -> int:
	for i: int in w.data.superweapons.size():
		if w.data.superweapons[i].id == id:
			return i
	return -1


func _lease(w: SimWorld, e: SimEntity, stat: int) -> int:
	return SimCombatMods.sum_bp(e.combat, stat, w.tick)


# ---- S15 latched snapshots -----------------------------------------------------------------------------------------

func test_s15_combined_arms_window_is_a_snapshot(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var a: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 30, 30)
	var b: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 32, 30)
	var far: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 30, 40)
	var foe: SimEntity = A.spawn(w, "unit.nec.spike_team", 1, 31, 31)
	A.hold_fire(w)
	var pw: int = _pw(w, "power.napc.combined_arms_window")
	t.eq(SimPowerFx.apply(w, pw, 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	t.eq(_lease(w, a, C.STAT_DMG_OUT), 1000, "infantry +10 % damage")
	t.eq(_lease(w, b, C.STAT_DMG_OUT), 1000, "land combat vehicle +10 %")
	t.eq(_lease(w, far, C.STAT_DMG_OUT), 0, "outside the 6 cell disc: nothing")
	t.eq(_lease(w, foe, C.STAT_DMG_OUT), 0, "the enemy is not a friendly")
	t.eq(A.count_events(w, K.EV_BUFF_APPLIED), 1, "EV_BUFF_APPLIED")
	t.eq(A.event_field(w, K.EV_BUFF_APPLIED, 0, SimEvent.I_C), 2, "two units buffed")
	# leaving keeps the effect, entering later does not get it
	A.place(w, a, 30, 50)
	A.run(w, 12)
	t.eq(_lease(w, a, C.STAT_DMG_OUT), 1000, "a unit that left the area keeps it")
	A.place(w, far, 30, 31)
	A.run(w, 12)
	t.eq(_lease(w, far, C.STAT_DMG_OUT), 0, "a unit that entered later does not get it")
	A.run(w, 310)
	t.eq(_lease(w, a, C.STAT_DMG_OUT), 0, "the buff ends after 15 s")
	t.eq(w.abilities.debug_validate(w), PackedStringArray(), "validate")


func test_s15_coordinated_advance_clears_suppression(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.mexico", "roster.nec.vanilla"], "movement": false})
	var a: SimEntity = A.spawn(w, "unit.napc.vanguard_rifle_squad", 0, 30, 30)
	var b: SimEntity = A.spawn(w, "unit.napc.vanguard_rifle_squad", 0, 31, 30)
	A.hold_fire(w)
	a.combat.sup_left_q8 = 20000
	b.combat.sup_left_q8 = 20000
	var base_speed: int = SimStats.peek(w, a, DefEnums.Stat.SPEED)
	var pw: int = _pw(w, "power.napc.coordinated_advance")
	t.eq(SimPowerFx.apply(w, pw, 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	t.check(not w.combat.is_suppressed(a) and not w.combat.is_suppressed(b), "existing suppression is cleared")
	t.check(SimCombatMods.has_flag(a.combat, C.STAT_FLAG_SUP_IMMUNE, w.tick), "and the units are immune for the window")
	t.eq(SimStats.get_val(w, a, DefEnums.Stat.SPEED), base_speed * 125 / 100, "+25 % speed")
	A.run(w, 241)
	t.check(not SimCombatMods.has_flag(a.combat, C.STAT_FLAG_SUP_IMMUNE, w.tick), "immunity ends with the window")
	t.eq(SimStats.get_val(w, a, DefEnums.Stat.SPEED), base_speed, "speed back to normal")


func test_open_corridor_and_steel_advance_speed(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.olm.vanilla", "roster.def.vanilla"], "movement": false})
	var tank: SimEntity = A.spawn(w, "unit.olm.sirocco_tank", 0, 30, 30)
	var base: int = SimStats.peek(w, tank, DefEnums.Stat.SPEED)
	t.eq(SimPowerFx.apply(w, _pw(w, "power.olm.open_corridor"), 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "Open Corridor")
	t.eq(SimStats.get_val(w, tank, DefEnums.Stat.SPEED), base * 125 / 100, "+25 % for the snapshot")
	var dtank: SimEntity = A.spawn(w, "unit.def.hammer_tank", 1, 50, 50)
	var dbase: int = SimStats.peek(w, dtank, DefEnums.Stat.SPEED)
	t.eq(SimPowerFx.apply(w, _pw(w, "power.def.steel_advance"), 1, _c(50), _c(50), 0, 0), SimZoneConsts.PW_OK, "Steel Advance")
	t.check(absi(SimStats.get_val(w, dtank, DefEnums.Stat.SPEED) - dbase * 80 / 100) <= 1, "-20 % speed")
	t.eq(_lease(w, dtank, C.STAT_TAKEN), 2000, "and 20 % damage reduction")


func test_armored_overwatch_needs_a_standing_tank(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.nec.vanilla", "roster.napc.usa"], "movement": false})
	var a: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 30, 30)
	var b: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 31, 30)
	A.hold_fire(w)
	b.flags |= SimFlags.F_MOVING
	t.eq(SimPowerFx.apply(w, _pw(w, "power.nec.armored_overwatch"), 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	t.eq(_lease(w, a, C.STAT_RANGE), 1000, "standing tank +10 % range")
	t.eq(_lease(w, b, C.STAT_RANGE), 0, "a moving tank does not get it")
	a.combat.ext_moving = 1  # the watch pass ends it on movement
	A.run(w, 3)
	t.eq(_lease(w, a, C.STAT_RANGE), 0, "movement ends the effect")


func test_silent_watch_camouflages_standing_units(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.nec.vanilla", "roster.napc.usa"], "movement": false})
	var a: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 30, 30)
	var m: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 31, 30)
	A.hold_fire(w)
	m.combat.ext_moving = 1
	t.eq(SimPowerFx.apply(w, _pw(w, "power.nec.silent_watch"), 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	A.run(w, 2)
	t.check(a.vis.concealed != 0, "a standing unit is camouflaged")
	t.check(m.vis.concealed == 0, "a moving one is not")
	a.combat.last_fire_tick = w.tick  # firing breaks it for good
	A.run(w, 3)
	t.check(a.vis.concealed == 0, "firing breaks it")
	A.run(w, 40)
	t.check(a.vis.concealed == 0, "and it does not come back")


func test_capacitor_discharge_buff_then_cannot_fire(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.olm.vanilla", "roster.napc.usa"], "movement": false})
	var beam: SimEntity = A.spawn(w, "unit.olm.sunlance_beam_tank", 0, 30, 30)
	var plain: SimEntity = A.spawn(w, "unit.olm.sirocco_tank", 0, 31, 30)
	A.hold_fire(w)
	t.eq(SimPowerFx.apply(w, _pw(w, "power.olm.capacitor_discharge"), 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	t.eq(_lease(w, beam, C.STAT_DMG_OUT), 2000, "thermal beam weapon +20 % damage")
	t.eq(_lease(w, plain, C.STAT_DMG_OUT), 0, "other weapons untouched")
	t.check(beam.combat.wlock_until <= w.tick, "still able to fire during the window")
	A.run_to(w, 199)
	t.check(beam.combat.wlock_until <= w.tick, "still firing at 199")
	A.run_to(w, 201)
	t.check(beam.combat.wlock_until > w.tick, "then locked")
	t.eq(beam.combat.wlock_until, 200 + 80, "for 4 s (80 ticks) from the end of the window")


func test_wideband_scan_power_opens_with_its_warning(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.han.vanilla", "roster.nec.vanilla"], "movement": false, "fog": true})
	var pw: int = _pw(w, "power.han.wideband_scan")
	t.check(SimPowerFx.self_warned(w, pw), "Wideband Scan carries its own warm-up (economy must activate it at once)")
	t.check(not SimPowerFx.self_warned(w, _pw(w, "power.pd.long_watch")), "Long Watch does not")
	t.eq(SimPowerFx.apply(w, pw, 0, _c(40), _c(40), 0, 0), SimZoneConsts.PW_OK, "accepted")
	var z: SimZone = w.zones.active_zones()[0]
	t.eq(z.state, SimZoneConsts.ZS_WARMUP, "warm-up")
	t.eq(z.t_warn_end - z.t_start, 40, "for the 2 s warning")
	t.eq(z.t_end - z.t_warn_end, 120, "then 6 s of detection")
	t.eq(A.event_field(w, K.EV_SCAN_WARNING, 0, SimEvent.I_D), 0, "EV_SCAN_WARNING names the owner")


func test_mobile_reserve_timed_param_mod(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.sap.vanilla", "roster.nec.vanilla"], "movement": false})
	var apc: SimEntity = A.spawn(w, "unit.sap.jackal_apc", 0, 30, 30)
	t.eq(w.abilities.ability_param(w, apc, K.AK_TRANSPORT, "unload_moving_speed_bp", 10000), 10000, "no reserve: the default")
	t.eq(SimPowerFx.apply(w, _pw(w, "power.sap.mobile_reserve"), 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "Mobile Reserve")
	t.eq(w.abilities.ability_param(w, apc, K.AK_TRANSPORT, "unload_moving_speed_bp", 10000), 5000, "unloading while moving at 50 % speed")
	A.run(w, 301)
	t.eq(w.abilities.ability_param(w, apc, K.AK_TRANSPORT, "unload_moving_speed_bp", 10000), 10000, "and back to normal after 15 s")


func test_broken_contact_spawns_smoke_discs(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.han.vanilla", "roster.nec.vanilla"], "movement": false})
	for i: int in 10:
		A.spawn(w, "unit.han.banner_infantry", 0, 28 + i % 5, 28 + i / 5 * 2)
	t.eq(SimPowerFx.apply(w, _pw(w, "power.han.broken_contact"), 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	var smokes: int = 0
	for z: SimZone in w.zones.active_zones():
		if z.kind == DefEnums.ZoneKind.SMOKE:
			smokes += 1
			t.eq(z.t_end - z.t_start, 120, "6 s of smoke")
	t.eq(smokes, 8, "up to 8 smoke discs at the units' positions")


# ---- delivery powers -----------------------------------------------------------------------------------------------

func test_field_repair_drop_delivery_and_fizzle(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var tank: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 30, 30)
	A.hold_fire(w)
	tank.hp = tank.hp_max / 2
	var pw: int = _pw(w, "power.napc.field_repair_drop")
	t.eq(SimPowerFx.apply(w, pw, 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	w.call("_flush_spawns")
	var plane: SimEntity = null
	for e: SimEntity in w.units_of(0):
		if e.summon != null and e.summon.driver == SimZoneConsts.SD_ORBITER:
			plane = e
	t.check(plane != null, "a shootable cargo aircraft is summoned")
	t.eq(w.zones.zone_count(), 0, "the repair zone waits for the delivery (delay 100)")
	t.eq(w.zones.pend.size(), SimZoneSystem.PEND_STRIDE, "one deferred action")
	A.run(w, 101)
	t.eq(w.zones.zone_count(), 1, "the drop happened")
	var hp0: int = tank.hp
	A.run(w, 100)
	t.gt(tank.hp, hp0, "the station heals")
	t.check(plane.hp == plane.hp_max or (plane.flags & SimFlags.F_GONE) != 0, "the aircraft is never healed")
	# a second drop whose aircraft is shot down before the delivery: no zone
	A.run(w, 120)
	t.eq(w.zones.zone_count(), 0, "first zone over")
	t.eq(SimPowerFx.apply(w, pw, 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "second drop")
	w.call("_flush_spawns")
	for e2: SimEntity in w.units_of(0):
		if e2.summon != null and e2.summon.driver == SimZoneConsts.SD_ORBITER and (e2.flags & SimFlags.F_GONE) == 0:
			w.kill(e2, SimWorld.Cause.SCRIPT)
	A.run(w, 110)
	t.eq(w.zones.zone_count(), 0, "body dead = no zone (fizzle)")


func test_floating_workshop_follows_its_pontoon(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var pw: int = _pw(w, "power.napc.floating_workshop")
	t.eq(SimPowerFx.apply(w, pw, 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	w.call("_flush_spawns")
	t.eq(w.zones.zone_count(), 1, "the workshop opens with the pontoon")
	var z: SimZone = w.zones.active_zones()[0]
	t.check(z.bind_eid > 0, "bound to the pontoon")
	var pont: SimEntity = w.get_entity(z.bind_eid)
	t.check(pont != null and pont.summon.driver == SimZoneConsts.SD_STATIC, "a static pontoon")
	w.kill(pont, SimWorld.Cause.SCRIPT)
	A.run(w, 3)
	t.eq(w.zones.zone_count(), 0, "the workshop ends with the pontoon")


func test_field_refurbishment_locks_weapons_and_ends_on_move(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.ae.kongo", "roster.nec.vanilla"], "movement": false})
	var tank: SimEntity = A.spawn(w, "unit.ae.buffalo_tank", 0, 30, 30)
	var mover: SimEntity = A.spawn(w, "unit.ae.buffalo_tank", 0, 31, 31)
	A.hold_fire(w)
	tank.hp = tank.hp_max / 2
	mover.hp = mover.hp_max / 2
	var hp0: int = tank.hp
	var pw: int = _pw(w, "power.ae.field_refurbishment")
	t.eq(SimPowerFx.apply(w, pw, 0, _c(30), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	A.run(w, 41)
	t.check(tank.combat.wlock_until > w.tick, "weapons are locked while repairing")
	t.gt(tank.hp, hp0, "healing")
	var per_s: int = (tank.hp - hp0) * 20 / 41
	t.check(absi(per_s - tank.hp_max * 3 / 100) <= tank.hp_max / 100 + 1, "about 3 %% per second (%d hp/s of %d)" % [per_s, tank.hp_max])
	mover.combat.ext_moving = 1
	A.run(w, 3)
	mover.combat.ext_moving = 0
	var mh: int = mover.hp
	A.run(w, 60)
	t.eq(mover.hp, mh, "a unit that moved is excluded for the rest of the zone")
	A.run(w, 200)
	t.check(tank.combat.wlock_until <= w.tick + 2, "weapons free again after the zone")


# ---- global-effect windows -----------------------------------------------------------------------------------------

func test_treaty_coordination_and_central_priority_windows(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.nec.vanilla", "roster.han.vanilla"], "movement": false})
	var pw: int = _pw(w, "power.nec.treaty_coordination")
	t.eq(SimPowerFx.apply(w, pw, 0, 0, 0, 0, 0), SimZoneConsts.PW_OK, "Treaty Coordination")
	var aura: SimAuraSystem = w.abilities.aura
	var i: int = 0 * SimAuraSystem.G_COUNT + SimAuraSystem.G_RELAY
	t.eq(aura.win_bp[i], 1500, "the Relay field damage bonus reads 15 %")
	t.eq(aura.win_until[i], w.tick + 400, "for 400 ticks")
	t.eq(w.players[0].fx.n_active, 1, "recorded in the player's window list")
	var pw2: int = _pw(w, "power.han.central_priority")
	t.eq(SimPowerFx.apply(w, pw2, 1, 0, 0, 0, 0), SimZoneConsts.PW_OK, "Central Priority")
	var j: int = 1 * SimAuraSystem.G_COUNT + SimAuraSystem.G_CMD
	t.eq(aura.win_bp[j], 2000, "command field damage bonus 20 %")
	var pw3: int = _pw(w, "power.han.reserve_bandwidth")
	t.eq(SimPowerFx.apply(w, pw3, 1, 0, 0, 0, 0), SimZoneConsts.PW_OK, "Reserve Bandwidth")
	t.eq(aura.win_rad[j], 3 * CELL, "+3 cells of radius")
	t.eq(aura.win_bp[j], 2000, "without losing the damage bonus")
	A.run(w, 401)
	t.eq(w.players[1].fx.n_active, 0, "windows pruned")


func test_recovery_priority_and_mobilization_windows(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.ae.vanilla", "roster.def.vanilla"], "movement": false})
	var rec: SimEntity = A.spawn(w, "unit.ae.reclaimer", 0, 30, 30)
	var base: int = SimStats.peek(w, rec, DefEnums.Stat.SPEED)
	var pw: int = _pw(w, "power.ae.recovery_priority")
	t.eq(SimPowerFx.apply(w, pw, 0, 0, 0, 0, 0), SimZoneConsts.PW_OK, "Recovery Priority")
	t.eq(SimStats.get_val(w, rec, DefEnums.Stat.SPEED), base * 125 / 100, "Reclaimers +25 % speed")
	t.eq(w.economy.knob(0, SimEconConst.K_SALVAGE_TICKS), 60, "salvage action time 3 s")
	var late: SimEntity = A.spawn(w, "unit.shared.engineer", 0, 32, 30)
	A.run(w, 2)
	t.check(SimStatus.has_from(late, w.abilities.fx_table.power_effect(pw, 0), K.fxk(K.SRC_POWER, pw)), "a unit spawned during the window gets it too")
	A.run(w, 400)
	t.eq(w.economy.knob(0, SimEconConst.K_SALVAGE_TICKS), 160, "back to 8 s")
	t.eq(SimStats.get_val(w, rec, DefEnums.Stat.SPEED), base, "speed restored")
	var pm: int = _pw(w, "power.def.mobilization_order")
	t.eq(SimPowerFx.apply(w, pm, 1, 0, 0, 0, 0), SimZoneConsts.PW_OK, "Mobilization Order")
	t.eq(w.economy.knob(1, SimEconConst.K_PROD_RATE_BARRACKS_BP), 12500, "barracks 125 %")
	t.eq(w.economy.knob(1, SimEconConst.K_PROD_RATE_FACTORY_BP), 12500, "factory 125 %")


func test_joint_landing_window_hooks_the_unload(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.pd.indonesia", "roster.nec.vanilla"], "movement": false})
	var pax: SimEntity = A.spawn(w, "unit.pd.island_raider", 0, 30, 30)
	A.hold_fire(w)
	var pw: int = _pw(w, "power.pd.joint_landing")
	t.eq(SimPowerFx.apply(w, pw, 0, 0, 0, 0, 0), SimZoneConsts.PW_OK, "accepted")
	t.eq(_lease(w, pax, C.STAT_TAKEN), 0, "nothing until a unit disembarks")
	w.abilities.on_disembark(w, pax)
	t.eq(_lease(w, pax, C.STAT_TAKEN), 2000, "-20 % damage taken after the unload")
	var fx_idx: int = w.abilities.fx_table.power_effect(pw, 0)
	var exp0: int = pax.abil.fx[0 * K.FX_STRIDE + K.FX_EXPIRE]
	A.run(w, 30)
	w.abilities.on_disembark(w, pax)
	var ex: int = 0
	for i: int in K.MAX_FX:
		if pax.abil.fx[i * K.FX_STRIDE] == fx_idx:
			ex = pax.abil.fx[i * K.FX_STRIDE + K.FX_EXPIRE]
	t.eq(ex, exp0, "a second unload inside the window changes nothing")
	A.run(w, 100)
	t.eq(_lease(w, pax, C.STAT_TAKEN), 0, "the effect lasts 120 ticks")


func test_rapid_turnaround_targets_a_powered_airfield(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var af: SimEntity = A.structure(w, "structure.shared.airfield", 0, 30, 30)
	var pw: int = _pw(w, "power.napc.rapid_turnaround")
	af.flags &= ~SimFlags.F_POWERED
	t.eq(SimPowerFx.validate_target(w, pw, 0, af.id), SimZoneConsts.PW_ERR_TARGET, "an unpowered airfield is refused")
	af.flags |= SimFlags.F_POWERED
	t.eq(SimPowerFx.validate_target(w, pw, 0, af.id), SimZoneConsts.PW_OK, "powered: fine")
	t.eq(SimPowerFx.apply(w, pw, 0, 0, 0, 0, af.id), SimZoneConsts.PW_OK, "accepted")
	t.eq(_lease(w, af, C.STAT_REARM_RATE), 5000, "+50 % rearm rate on the chosen airfield")
	t.eq(SimPowerFx.apply(w, pw, 0, 0, 0, 0, 9999), SimZoneConsts.PW_ERR_TARGET, "a missing target is refused")


# ---- marks / strikes ---------------------------------------------------------------------------------------------------

func test_counterbattery_solution_marks_recent_artillery(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.ae.kongo", "roster.nec.vanilla"], "movement": false})
	var gun: SimEntity = A.spawn(w, "unit.nec.archer_spg", 1, 30, 30)
	var idle: SimEntity = A.spawn(w, "unit.nec.archer_spg", 1, 32, 30)
	var tank: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 31, 30)
	A.run(w, 200)
	gun.combat.last_fire_tick = w.tick - 40
	tank.combat.last_fire_tick = w.tick - 40
	var pw: int = _pw(w, "power.ae.counterbattery_solution")
	t.eq(SimPowerFx.apply(w, pw, 0, _c(31), _c(30), 0, 0), SimZoneConsts.PW_OK, "accepted")
	var team0: int = w.team_of(0)
	t.eq(SimCombatMods.mark_bp(gun.combat, w.tick, team0, true), 1500, "the shooting gun is marked +15 % for ground weapons")
	t.eq(SimCombatMods.mark_bp(gun.combat, w.tick, team0, false), 0, "not for air weapons")
	t.eq(SimCombatMods.mark_bp(idle.combat, w.tick, team0, true), 0, "a gun that did not fire is not")
	t.eq(SimCombatMods.mark_bp(tank.combat, w.tick, team0, true), 0, "a tank is not artillery")
	t.eq(SimCombatMods.mark_bp(gun.combat, w.tick, w.team_of(1), true), 0, "only the caster's team profits")
	A.run(w, 241)
	t.eq(SimCombatMods.mark_bp(gun.combat, w.tick, team0, true), 0, "the mark ends after 240 ticks")


func test_strike_powers_spawn_shells(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.def.vanilla", "roster.nec.vanilla"], "movement": false})
	var pw: int = _pw(w, "power.def.tremor_barrage")
	var live0: int = w.combat.proj.live_count()
	t.eq(SimPowerFx.apply(w, pw, 0, _c(40), _c(40), 0, 777), SimZoneConsts.PW_OK, "Tremor Barrage")
	t.eq(w.combat.proj.live_count() - live0, 24, "6 shells x 4 waves")
	t.eq(SimPowerFx.apply(w, _pw(w, "power.nec.counterbattery_mission"), 1, _c(40), _c(40), 0, 5), SimZoneConsts.PW_OK, "Counterbattery Mission")
	t.eq(w.combat.proj.live_count() - live0, 30, "plus 6 shells")


# ---- superweapons -----------------------------------------------------------------------------------------------------

func test_s08_aurora_emp_integration(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.nec.vanilla", "roster.def.vanilla"], "movement": false})
	var immune: SimEntity = A.spawn(w, "unit.def.hammer_tank", 1, 40, 40)
	var plain: SimEntity = A.spawn(w, "unit.def.hammer_tank", 1, 41, 41)
	# Redundant Orders on the first tank: an EMP-immune lease
	t.eq(SimPowerFx.apply(w, _pw(w, "power.def.redundant_orders"), 1, _c(40), _c(40), 0, 0), SimZoneConsts.PW_OK, "Redundant Orders")
	var members: int = w.zones.active_zones()[0].n_members
	t.eq(members, 2, "both tanks in the area are immune")
	SimCombatMods.clear_all(plain.combat)  # the second tank plays the unprotected one
	var sw: int = _sw(w, "superweapon.nec.aurora_microwave_array")
	var live0: int = w.combat.proj.live_count()
	t.eq(SimPowerFx.apply_superweapon(w, sw, 0, _c(40), _c(40), 0, _c(10), _c(10), 0), SimZoneConsts.PW_OK, "Aurora accepted")
	t.eq(w.combat.proj.live_count(), live0 + 1, "one strike is in flight")
	t.check(SimCombatMods.has_flag(immune.combat, C.STAT_FLAG_EMP_IMMUNE, w.tick), "the immune vehicle holds STAT_FLAG_EMP_IMMUNE")
	var wh: SimCombatWarhead = w.combat.tables_of(0).warheads.back()
	t.eq(wh.dtype, C.DT_EMP, "the warhead is an EMP")
	t.eq(wh.emp_unit_ticks, 160, "weapons off for 160 ticks")
	t.eq(wh.emp_struct_ticks, 360, "structures shut for 360 ticks")
	A.run(w, 20)
	t.check(plain.combat.emp_until > w.tick, "the unprotected tank was hit by the EMP")
	t.eq(immune.combat.emp_until, 0, "the immune one shrugged it off")


func test_trident_superweapon_dome(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.sap.vanilla", "roster.nec.vanilla"], "movement": false})
	var sw: int = _sw(w, "superweapon.sap.trident_interception_array")
	t.eq(SimPowerFx.apply_superweapon(w, sw, 0, _c(30), _c(30), 0, 0, 0, 0), SimZoneConsts.PW_OK, "accepted")
	var z: SimZone = w.zones.active_zones()[0]
	t.eq(z.kind, DefEnums.ZoneKind.INTERCEPT, "an interception dome")
	t.eq(z.charges, 24, "24 charges")
	t.eq(z.t_end - z.t_start, 500, "500 ticks")
	t.eq(z.radius, 6144, "6 cells")


func test_horizon_places_debris_at_each_impact(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.ae.kongo", "roster.nec.vanilla"], "movement": false})
	var sw: int = _sw(w, "superweapon.ae.horizon_mass_driver")
	var live0: int = w.combat.proj.live_count()
	t.eq(SimPowerFx.apply_superweapon(w, sw, 0, _c(40), _c(40), 0, 0, 0, 0), SimZoneConsts.PW_OK, "accepted")
	t.eq(w.combat.proj.live_count() - live0, 3, "three impacts")
	var debris: Array[SimZone] = []
	for z: SimZone in w.zones.active_zones():
		if z.kind == DefEnums.ZoneKind.DEBRIS:
			debris.append(z)
	t.eq(debris.size(), 1, "the first debris disc exists at impact tick 0")
	t.eq(w.zones.pend.size() / SimZoneSystem.PEND_STRIDE, 2, "two more are queued")
	A.run(w, 100)
	var n: int = 0
	for z2: SimZone in w.zones.active_zones():
		if z2.kind == DefEnums.ZoneKind.DEBRIS:
			n += 1
	t.eq(n, 2, "the second at tick 90")
	A.run(w, 100)
	n = 0
	for z3: SimZone in w.zones.active_zones():
		if z3.kind == DefEnums.ZoneKind.DEBRIS:
			n += 1
	t.eq(n, 3, "and the third at tick 180 (-5, 0, +5 cells on the line)")
	t.check(w.zones.construction_blocked(40, 40), "new construction is blocked at the centre")


# ---- generated: every power, every superweapon -------------------------------------------------------------------------

func _footprint(w: SimWorld) -> int:
	var fp: int = w.zones.zone_count() * 1000003 + w.entities.size() * 7919 + w.combat.proj.live_count() * 104729
	fp += w.zones.pend.size() * 31
	for p: SimPlayer in w.players:
		if p.fx != null:
			fp += p.fx.n_active * 15485863
		fp += p.econ.knob_until[SimEconConst.K_SALVAGE_TICKS] + p.econ.knob_until[SimEconConst.K_PROD_RATE_BARRACKS_BP] + p.econ.knob_until[SimEconConst.K_PROD_RATE_FACTORY_BP]
	for e: SimEntity in w.entities:
		if e.abil != null:
			fp += e.abil.n_fx * 2038073
		if e.combat != null and not e.combat.mods.is_empty():
			for i: int in SimCombatConsts.MAX_MODS:
				if e.combat.mods[i * SimCombatConsts.MODS_STRIDE + SimCombatConsts.MOD_STAT] != SimCombatConsts.STAT_NONE:
					fp += 611953
	for i2: int in w.abilities.aura.win_until.size():
		fp += w.abilities.aura.win_until[i2]
	return fp


func test_every_power_takes_effect(t: TestCtx) -> void:
	var d: GameData = A.data()
	var rosters: Dictionary = {}
	for r: DefRoster in d.rosters:
		if r.is_vanilla:
			rosters[d.factions[r.faction].id] = r.id
	var skipped: PackedStringArray = PackedStringArray()
	for pi: int in d.powers.size():
		var p: DefPower = d.powers[pi]
		var own: String = "roster.%s.vanilla" % d.factions[p.faction].id.split(".")[-1] if p.faction >= 0 else "roster.napc.vanilla"
		var w: SimWorld = A.world({"rosters": [own if d.roster_idx(own) >= 0 else "roster.napc.vanilla", "roster.nec.vanilla" if not own.contains("nec") else "roster.napc.vanilla"], "movement": false})
		# a populated battlefield around the target: own units of every archetype, enemy units, an airfield
		var ids: Array[String] = ["unit.shared.engineer", "unit.shared.collector"]
		for u: DefUnit in d.units:
			if w.players[0].roster.has_unit(u.index) and not u.id.begins_with("summon.") and not u.id.begins_with("unit.drone") and ids.size() < 24 and u.cost > 0:
				ids.append(u.id)
		var n: int = 0
		for id: String in ids:
			if d.unit_idx(id) >= 0 and w.players[0].roster.has_unit(d.unit_idx(id)):
				A.spawn(w, id, 0, 28 + n % 6, 28 + n / 6)
				n += 1
		var foe: SimEntity = A.spawn(w, "unit.nec.archer_spg" if w.players[1].roster.has_unit(d.unit_idx("unit.nec.archer_spg")) else "unit.napc.paladin_howitzer", 1, 30, 30)
		foe.combat.last_fire_tick = w.tick
		var af: int = d.structure_idx("structure.shared.airfield")
		var target: int = 0
		if p.params.has("target_structure_idx"):
			var s: SimEntity = A.structure(w, d.structures[(p.params["target_structure_idx"] as PackedInt32Array)[0]].id, 0, 45, 45)
			s.flags |= SimFlags.F_POWERED
			target = s.id
		if af < 0:
			t.fail("no airfield def")
		A.run(w, 2)
		var before: int = _footprint(w)
		var r: int = SimPowerFx.apply(w, pi, 0, _c(30), _c(30), 0, target if target > 0 else 4242)
		w.call("_flush_spawns")
		if r == SimZoneConsts.PW_ERR_NO_SUMMON:
			skipped.append(p.id)
			continue
		t.eq(r, SimZoneConsts.PW_OK, "%s accepted" % p.id)
		A.run(w, 3)
		t.check(_footprint(w) != before, "%s changed the sim (zones, entities, leases, windows or projectiles)" % p.id)
		t.eq(w.zones.debug_validate(w), PackedStringArray(), "%s: zones validate" % p.id)
		t.eq(w.abilities.debug_validate(w), PackedStringArray(), "%s: abilities validate" % p.id)
		_check_catalog_row(t, w, d, p, pi)
	t.eq(skipped.size(), 0, "every power is playable (the two recon powers whose summon def is not authored yet use the UAV as a stand-in)")


## The catalog row of a zone-based power in sim state: the zone's area and duration equal the data (action override or
## template), and every effect of the zone is held by the own units of the area that its selector names.
func _check_catalog_row(t: TestCtx, w: SimWorld, d: GameData, p: DefPower, pi: int) -> void:
	var tbl: SimEffectTable = w.abilities.fx_table
	for z: SimZone in w.zones.active_zones():
		if z.power_idx != pi or z.zone_idx < 0:
			continue
		var zd: DefZone = d.zones[z.zone_idx]
		var act: DefPowerAction = null
		for a: DefPowerAction in p.actions:
			if a.op == DefEnums.PowerOp.ZONE and a.zone == z.zone_idx:
				act = a
		if act == null:
			continue
		var want_r: int = act.radius if act.radius > 0 else zd.radius
		var want_d: int = act.duration_t if act.duration_t > 0 else zd.duration_t
		if z.shape == DefEnums.ZoneShape.CIRCLE and zd.shape == DefEnums.ZoneShape.CIRCLE:
			t.eq(z.radius, want_r, "%s: zone area radius" % p.id)
		t.eq(z.t_end - z.t_start - (z.t_warn_end - z.t_start), want_d, "%s: zone duration" % p.id)
		var key: int = SimZoneFx.src_key_of(z)
		for k: int in zd.effects.size():
			var fx: DefEffect = zd.effects[k]
			if fx.op == DefEnums.EffectOp.REVEAL or fx.op == DefEnums.EffectOp.SPAWN_ZONE or not fx.cond_codes.is_empty():
				continue
			var fx_idx: int = tbl.zone_effect(z.zone_idx, k)
			var matching: int = 0
			var holding: int = 0
			for e: SimEntity in w.entities:
				if (e.flags & SimFlags.F_GONE) != 0 or e.owner != 0 or e.summon != null or not z.contains_point(e.x, e.y):
					continue
				if (e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE) or not w.zones.selector_ok(w, e, fx.selector):
					continue
				matching += 1
				if SimStatus.has_from(e, fx_idx, key):
					holding += 1
			if matching > 0:
				t.gt(holding, 0, "%s: effect %d (op %d) is held by the units it names (%d of %d)" % [p.id, k, fx.op, holding, matching])


func test_every_superweapon_activates(t: TestCtx) -> void:
	var d: GameData = A.data()
	for si: int in d.superweapons.size():
		var sw: DefSuperweapon = d.superweapons[si]
		var fac: String = d.factions[sw.faction].id.split(".")[-1] if sw.faction >= 0 else "napc"
		var w: SimWorld = A.world({"rosters": ["roster.%s.vanilla" % fac, "roster.nec.vanilla" if fac != "nec" else "roster.napc.vanilla"], "movement": false})
		A.spawn(w, "unit.shared.engineer", 1, 30, 30)
		var before: int = _footprint(w)
		var r: int = SimPowerFx.apply_superweapon(w, si, 0, _c(30), _c(30), 512, _c(10), _c(10), 99)
		w.call("_flush_spawns")
		t.eq(r, SimZoneConsts.PW_OK, "%s accepted" % sw.id)
		t.check(_footprint(w) != before, "%s changed the sim" % sw.id)
		A.run(w, 5)
		t.eq(w.zones.debug_validate(w), PackedStringArray(), "%s: zones validate" % sw.id)
