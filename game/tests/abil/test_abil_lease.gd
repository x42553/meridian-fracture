extends RefCounted
## AB-02: the lease bridge (abilities 5.2.4 / 10.1 test_abil_lease): DefEffect ops -> SimCombatMods.

const C := preload("res://src/sim/combat/sim_combat_consts.gd")
const EO := DefEnums.EffectOp


func _world(list: Array[DefEffect]) -> SimWorld:
	var d: GameData = AbilKit.data()
	AbilKit.add_zone_effects(d, list)
	return AbilKit.world({}, d)


func _fx(op: int, delta: int, params: Dictionary = {}) -> DefEffect:
	return AbilKit.fx_op(op, delta, params)


func test_hold_release_and_reissue(t: TestCtx) -> void:
	var f: DefEffect = AbilKit.fx_stat(DefEnums.Stat.DAMAGE, 1000)
	var w: SimWorld = _world([f])
	var e: SimEntity = AbilKit.tank(w, 0, 30, 30)
	var key: int = SimLeaseBridge.fxk(SimAbilityConsts.SRC_GROUP, 4)
	SimLeaseBridge.hold(w, e, key, f, 0, SimAbilityConsts.LEASE_HOLD)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 1000, "aura hold +10 %")
	SimLeaseBridge.release(w, e, key)
	SimLeaseBridge.hold(w, e, key, f, 1500, SimAbilityConsts.LEASE_HOLD)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 1500, "window opens: clear_key then apply 1500")
	SimLeaseBridge.release(w, e, key)
	SimLeaseBridge.hold(w, e, key, f, 0, SimAbilityConsts.LEASE_HOLD)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 1000, "window closes: back to the base magnitude")
	SimLeaseBridge.release(w, e, key)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 0, "released")


func test_stat_mapping(t: TestCtx) -> void:
	var dmg: DefEffect = AbilKit.fx_stat(DefEnums.Stat.DAMAGE, 500)
	var rng: DefEffect = AbilKit.fx_stat(DefEnums.Stat.RANGE, 2500)
	var rel: DefEffect = AbilKit.fx_stat(DefEnums.Stat.RELOAD, -1000)
	var spd: DefEffect = AbilKit.fx_stat(DefEnums.Stat.SPEED, 1000)
	var w: SimWorld = _world([dmg, rng, rel, spd])
	var e: SimEntity = AbilKit.tank(w, 0, 30, 30)
	for f: DefEffect in [dmg, rng, rel, spd]:
		SimLeaseBridge.hold(w, e, 9, f, 0, 100)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 500, "DAMAGE -> DMG_OUT")
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_RANGE, w.tick), 2500, "RANGE -> RANGE")
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_RELOAD, w.tick), -1000, "RELOAD -> RELOAD (negative = faster)")
	t.eq(SimLeaseBridge.local_stat_of(spd), SimAbilityConsts.K_SPEED, "SPEED stays local")
	t.eq(SimLeaseBridge.stat_of(spd), -1, "and is not a lease")


func test_resist_filters(t: TestCtx) -> void:
	var smoke: DefEffect = _fx(EO.RESIST_MOD, 3000)
	smoke.fire_mode_mask = 1
	var cover: DefEffect = _fx(EO.RESIST_MOD, 2000)
	cover.group_mask = DefEnums.RG_BULLET
	var w: SimWorld = _world([smoke, cover])
	var e: SimEntity = AbilKit.tank(w, 0, 30, 30)
	SimLeaseBridge.hold(w, e, 1, smoke, 0, 100)
	SimLeaseBridge.hold(w, e, 2, cover, 0, 100)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_TAKEN, w.tick, C.DT_BULLET, C.DC_DIRECT), 5000, "a direct bullet gets both")
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_TAKEN, w.tick, C.DT_HE, C.DC_DIRECT), 3000, "HE gets only the smoke")
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_TAKEN, w.tick, C.DT_BULLET, C.DC_INDIRECT | C.DC_SPLASH), 2000, "indirect fire ignores the direct-only smoke")
	t.eq(SimLeaseBridge.filter_of(w, smoke), C.FILTER_DIRECT_ONLY, "smoke = FILTER_DIRECT_ONLY exactly")
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_TAKEN, w.tick, C.DT_EMP, C.DC_DIRECT), 0, "EMP is never reduced")


func test_immunity_mark_and_lock(t: TestCtx) -> void:
	var sup: DefEffect = _fx(EO.IMMUNITY, 0, {"kind": "suppression"})
	var emp: DefEffect = _fx(EO.IMMUNITY, 0, {"kind": "emp"})
	var mark: DefEffect = _fx(EO.MARK, 0, {"damage_bonus_bp": 1500})
	var dis: DefEffect = _fx(EO.DISABLE, 0, {"what": "weapons"})
	var w: SimWorld = _world([sup, emp, mark, dis])
	var e: SimEntity = AbilKit.tank(w, 0, 30, 30)
	e.combat.sup_left_q8 = 500
	e.flags |= SimFlags.F_SUPPRESSED
	t.check(w.abilities.apply_timed_effect(e.id, AbilKit.fx_index(w, sup), 120, 0, 7), "Coordinated Advance")
	t.check(SimCombatMods.has_flag(e.combat, C.STAT_FLAG_SUP_IMMUNE, w.tick), "suppression immunity held")
	t.check_false(w.combat.is_suppressed(e), "and the running suppression is removed")
	t.check_false(SimCombatMods.has_flag(e.combat, C.STAT_FLAG_EMP_IMMUNE, w.tick), "emp flag not set by the suppression effect")
	w.abilities.apply_timed_effect(e.id, AbilKit.fx_index(w, emp), 120, 0, 8)
	t.check(SimCombatMods.has_flag(e.combat, C.STAT_FLAG_EMP_IMMUNE, w.tick), "Redundant Orders: emp immunity")
	w.abilities.apply_timed_effect(e.id, AbilKit.fx_index(w, mark), 100, 0, 9)
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, w.team_of(0), true), 1500, "Counterbattery mark for the marking team")
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, w.team_of(1), true), 0, "not for the other team")
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, w.team_of(0), false), 0, "ground weapons only")
	w.step()
	w.abilities.apply_timed_effect(e.id, AbilKit.fx_index(w, dis), 80, 0, 10)
	t.eq(e.combat.wlock_until, w.tick + 80, "Capacitor phase 2: weapons locked until tick + 80")
	w.abilities.clear_timed_effects(e.id, 9)
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, w.team_of(0), true), 0, "clear_timed_effects releases the mark lease")
