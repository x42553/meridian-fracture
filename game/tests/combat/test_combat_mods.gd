extends RefCounted
## CB-01: lease slots (SimCombatMods): dedupe, eviction, expiry, filters, marks, flags, aggregates, aura refresh.

const ALL: int = SimCombatConsts.FILTER_ALL_WEAPON


func _setup() -> Array:
	var w: SimWorld = CombatKit.world()
	return [w, CombatKit.tank(w, 1, 30, 30)]


func _live(e: SimEntity, tick: int) -> int:
	var n: int = 0
	for i: int in SimCombatConsts.MAX_MODS:
		var b: int = i * SimCombatConsts.MODS_STRIDE
		if e.combat.mods[b + SimCombatConsts.MOD_STAT] != SimCombatConsts.STAT_NONE and e.combat.mods[b + SimCombatConsts.MOD_EXPIRE] > tick:
			n += 1
	return n


func test_apply_sum_and_expiry(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	t.eq(e.combat.mods.size(), 0, "no lease storage before the first lease")
	SimCombatMods.apply(w, e, 7, SimCombatConsts.STAT_DMG_OUT, 1000, 0, 10)
	t.eq(e.combat.mods.size(), SimCombatConsts.MAX_MODS * SimCombatConsts.MODS_STRIDE, "storage allocated lazily")
	t.eq(SimCombatMods.sum_bp(e.combat, SimCombatConsts.STAT_DMG_OUT, w.tick), 1000, "live lease counts")
	t.eq(SimCombatMods.sum_bp(e.combat, SimCombatConsts.STAT_RELOAD, w.tick), 0, "other stat untouched")
	t.eq(SimCombatMods.sum_bp(e.combat, SimCombatConsts.STAT_DMG_OUT, w.tick + 9), 1000, "still live one tick before expiry")
	t.eq(SimCombatMods.sum_bp(e.combat, SimCombatConsts.STAT_DMG_OUT, w.tick + 10), 0, "expired at tick + ticks")
	t.check(w.combat.status_ids.has(e.id), "entity registered for upkeep")
	CombatKit.run_to(w, 11)
	t.eq(SimCombatMods.sum_bp(e.combat, SimCombatConsts.STAT_DMG_OUT, w.tick), 0, "expired by the world clock")
	t.eq(e.combat.mods[SimCombatConsts.MOD_STAT], SimCombatConsts.STAT_NONE, "upkeep emptied the slot canonically")
	t.eq([e.combat.mods[0], e.combat.mods[2], e.combat.mods[3], e.combat.mods[4]], [0, 0, 0, 0], "canonical empty slot")
	t.check(not w.combat.status_ids.has(e.id), "entity left the upkeep list")
	SimCombatMods.apply(w, e, 7, SimCombatConsts.STAT_DMG_OUT, 500, 0, 0)
	t.eq(_live(e, w.tick), 0, "a lease of zero ticks is ignored")


func test_same_key_never_stacks(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	var D: int = SimCombatConsts.STAT_DMG_OUT
	SimCombatMods.apply(w, e, 1, D, 1000, 0, 10)
	SimCombatMods.apply(w, e, 1, D, 1500, 0, 6)
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick), 1500, "same (key, stat): the larger |bp| wins, no stacking")
	t.eq(_live(e, w.tick), 1, "one slot")
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick + 9), 1500, "the later expiry is kept")
	SimCombatMods.apply(w, e, 1, D, -1200, 0, 4)
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick), 1500, "a smaller |bp| of the opposite sign does not replace it")
	SimCombatMods.apply(w, e, 1, D, -2000, 0, 4)
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick), -2000, "a larger |bp| replaces it, sign included")
	SimCombatMods.apply(w, e, 1, D, 2000, 0, 4)
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick), -2000, "ties keep the existing value")
	SimCombatMods.apply(w, e, 1, SimCombatConsts.STAT_RELOAD, -1000, 0, 10)
	t.eq(_live(e, w.tick), 2, "the same key on another stat is its own lease")
	SimCombatMods.apply(w, e, 2, D, 1000, 0, 10)
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick), -1000, "different keys add (-2000 + 1000)")


func test_noop_fast_path(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	SimCombatMods.apply(w, e, 1, SimCombatConsts.STAT_RANGE, 1000, 0, 6)
	SimCombatMods.refresh(e.combat, w.tick)
	t.eq(e.combat.mods_dirty, 0, "clean after refresh")
	SimCombatMods.apply(w, e, 1, SimCombatConsts.STAT_RANGE, 1000, 0, 6)
	t.eq(e.combat.mods_dirty, 0, "re-applying identical values changes nothing")
	SimCombatMods.apply(w, e, 1, SimCombatConsts.STAT_RANGE, 1000, 0, 8)
	t.eq(e.combat.mods_dirty, 1, "a later expiry marks the cache dirty")


func test_eviction(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	var D: int = SimCombatConsts.STAT_DMG_OUT
	for k: int in SimCombatConsts.MAX_MODS:
		SimCombatMods.apply(w, e, 100 + k, D, 100, 0, 20 + k * 5)  # expiries 20, 25, ..., 65
	t.eq(_live(e, w.tick), SimCombatConsts.MAX_MODS, "table full")
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick), 1000, "ten leases add")
	SimCombatMods.apply(w, e, 900, D, 777, 0, 10)
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick), 1000, "a lease that expires before every slot is dropped")
	SimCombatMods.apply(w, e, 901, D, 777, 0, 30)
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick), 1000 - 100 + 777, "otherwise the earliest expiry (key 100, tick 20) is evicted")
	t.eq(e.combat.mods[SimCombatConsts.MOD_KEY], 901, "into the evicted slot (lowest index among equals)")
	SimCombatMods.apply(w, e, 902, D, 50, 0, 1000)
	t.eq(SimCombatMods.sum_bp(e.combat, D, w.tick), 1000 - 100 + 777 - 100 + 50, "next eviction: the earliest is now key 101 (tick 25)")
	CombatKit.run_to(w, 30)
	t.eq(_live(e, w.tick), 8, "two leases expired by tick 30 (key 901 at 30, key 102 at 30)")
	SimCombatMods.apply(w, e, 903, D, 10, 0, 5)
	t.eq(_live(e, w.tick), 9, "an expired slot is reused before anything live is evicted")


func test_clear_and_filters(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	var T: int = SimCombatConsts.STAT_TAKEN
	SimCombatMods.apply(w, e, 5, T, 1000, SimCombatConsts.make_filter(1 << SimCombatConsts.DT_HE), 50)
	SimCombatMods.apply(w, e, 5, SimCombatConsts.STAT_DMG_OUT, 300, 0, 50)
	SimCombatMods.apply(w, e, 6, T, 2000, SimCombatConsts.FILTER_DIRECT_ONLY, 50)
	var c: SimCompCombat = e.combat
	t.eq(SimCombatMods.sum_bp(c, T, w.tick), 3000, "unfiltered read adds everything")
	t.eq(SimCombatMods.sum_bp(c, T, w.tick, SimCombatConsts.DT_HE, SimCombatConsts.DC_DIRECT), 3000, "HE direct: both rows match")
	t.eq(SimCombatMods.sum_bp(c, T, w.tick, SimCombatConsts.DT_HE, SimCombatConsts.DC_INDIRECT | SimCombatConsts.DC_SPLASH), 1000, "HE splash: only the type row")
	t.eq(SimCombatMods.sum_bp(c, T, w.tick, SimCombatConsts.DT_BULLET, SimCombatConsts.DC_DIRECT), 2000, "bullet direct: only the direct-only row")
	t.eq(SimCombatMods.sum_bp(c, T, w.tick, SimCombatConsts.DT_BULLET, SimCombatConsts.DC_INDIRECT), 0, "bullet indirect: none")
	SimCombatMods.clear_key(e, 5)
	t.eq(SimCombatMods.sum_bp(c, T, w.tick), 2000, "clear_key removes every stat of the key")
	t.eq(SimCombatMods.sum_bp(c, SimCombatConsts.STAT_DMG_OUT, w.tick), 0, "including the other stat")
	SimCombatMods.clear_all(c)
	t.eq(_live(e, w.tick), 0, "clear_all")


func test_flags_and_marks(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	t.check(not SimCombatMods.has_flag(e.combat, SimCombatConsts.STAT_FLAG_EMP_IMMUNE, w.tick), "no flag")
	SimCombatMods.apply(w, e, 1, SimCombatConsts.STAT_FLAG_EMP_IMMUNE, 0, 0, 10)
	t.check(SimCombatMods.has_flag(e.combat, SimCombatConsts.STAT_FLAG_EMP_IMMUNE, w.tick), "boolean lease")
	t.check(not SimCombatMods.has_flag(e.combat, SimCombatConsts.STAT_FLAG_EMP_IMMUNE, w.tick + 10), "expires")
	t.check(not SimCombatMods.has_flag(e.combat, SimCombatConsts.STAT_FLAG_SUP_IMMUNE, w.tick), "other flag unaffected")
	SimCombatMods.apply(w, e, 2, SimCombatConsts.STAT_MARK, 1500, SimCombatMods.mark_filter(1, true), 240)
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, 1, true), 1500, "marking team, ground weapon")
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, 1, false), 0, "ground-only mark ignores air / ship shooters")
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, 2, true), 0, "other team gets nothing")
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, -1, true), 0, "no team gets nothing")
	SimCombatMods.apply(w, e, 3, SimCombatConsts.STAT_MARK, 500, SimCombatMods.mark_filter(1, false), 240)
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, 1, false), 500, "unrestricted mark applies to any shooter")
	t.eq(SimCombatMods.mark_bp(e.combat, w.tick, 1, true), 2000, "both marks for a ground shooter")


func test_aggregates_and_aura_refresh(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	SimCombatMods.apply(w, e, 1, SimCombatConsts.STAT_DMG_OUT, 1000, 0, 30)
	SimCombatMods.apply(w, e, 2, SimCombatConsts.STAT_DMG_OUT, 2000, 0, 10)
	SimCombatMods.apply(w, e, 3, SimCombatConsts.STAT_RELOAD, -1500, 0, 30)
	SimCombatMods.apply(w, e, 4, SimCombatConsts.STAT_RANGE, 1000, 0, 30)
	t.check(SimCombatMods.refresh(e.combat, w.tick), "live leases remain")
	t.eq([e.combat.agg_dmg_bp, e.combat.agg_reload_bp, e.combat.agg_range_bp], [3000, -1500, 1000], "aggregates")
	t.eq(e.combat.mods_next_expiry, 10, "earliest expiry")
	CombatKit.run_to(w, 11)
	t.eq([e.combat.agg_dmg_bp, e.combat.mods_next_expiry], [1000, 30], "aggregates follow the expiry (upkeep P1)")
	# an aura owner re-applies every 4 ticks with ticks = 4 + 2: never a gap
	var f: SimEntity = CombatKit.tank(w, 1, 34, 34)
	var gaps: int = 0
	for i: int in 40:
		if i % 4 == 0:
			SimCombatMods.apply(w, f, 9, SimCombatConsts.STAT_DMG_OUT, 1000, 0, 6)
		if SimCombatMods.sum_bp(f.combat, SimCombatConsts.STAT_DMG_OUT, w.tick) != 1000:
			gaps += 1
		w.step()
	t.eq(gaps, 0, "N+2 re-application keeps the aura continuous")
	CombatKit.run_to(w, w.tick + 6)
	t.eq(SimCombatMods.sum_bp(f.combat, SimCombatConsts.STAT_DMG_OUT, w.tick), 0, "and lapses once the owner stops")


func test_dead_entities_take_no_leases(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	w.combat.kill(w, e, SimCombatConsts.CAUSE_DAMAGE, -1, -1)
	SimCombatMods.apply(w, e, 1, SimCombatConsts.STAT_DMG_OUT, 1000, 0, 10)
	t.eq(e.combat.mods.size(), 0, "no lease on a dead entity")
