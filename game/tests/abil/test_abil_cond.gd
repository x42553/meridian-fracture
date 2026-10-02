extends RefCounted
## AB-02: bound conditional effects (abilities 5.3, test_abil_cond).

const C := preload("res://src/sim/combat/sim_combat_consts.gd")
const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const CD := DefEnums.Cond


func _cond_fx(stat: int, delta: int, code: int, params: Dictionary) -> DefEffect:
	var f: DefEffect = AbilKit.fx_stat(stat, delta)
	f.cond_codes = PackedInt32Array([code])
	f.cond_params = [params]
	return f


func _setup(f: DefEffect) -> Array:
	var d: GameData = AbilKit.data()
	AbilKit.add_research_effects(d, [f])
	var w: SimWorld = AbilKit.world({}, d)
	AbilKit.bind_cond(w, 0, DefTestKit.U_TANK, f)
	var e: SimEntity = AbilKit.tank(w, 0, 30, 30)
	return [w, e]


func test_stationary_threshold(t: TestCtx) -> void:
	var f: DefEffect = _cond_fx(DefEnums.Stat.RELOAD, -1000, CD.STATIONARY, {"for_t": 80})
	var s: Array = _setup(f)
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	t.eq(e.abil.watch & K.WF_STILL, K.WF_STILL, "bound STATIONARY puts the unit on the watch list")
	t.check(w.abilities.watch_list.has(e.id), "watch list")
	e.combat.still_ticks = 0
	w.run(4)
	e.combat.still_ticks = 79
	w.run(1)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_RELOAD, w.tick), 0, "79 quiet ticks: not yet")
	e.combat.still_ticks = 80
	w.run(2)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_RELOAD, w.tick), -1000, "80: reload lease held (lag at most one tick)")
	e.combat.still_ticks = 0
	w.run(2)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_RELOAD, w.tick), 0, "moving again releases it")


func test_out_of_combat(t: TestCtx) -> void:
	var f: DefEffect = _cond_fx(DefEnums.Stat.DAMAGE, 500, CD.OUT_OF_COMBAT, {"for_t": 120})
	var s: Array = _setup(f)
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	w.run(2)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 500, "true at binding (quiet since forever)")
	e.combat.last_hit_tick = w.tick
	w.run(2)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 0, "a hit resets the clock")
	AbilKit.run_to(w, e.combat.last_hit_tick + 118)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 0, "still 118 ticks after")
	AbilKit.run_to(w, e.combat.last_hit_tick + 123)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 500, "120 ticks quiet: back (within a tick of lag)")


func test_pushed_codes_disembarked_and_zone(t: TestCtx) -> void:
	var f: DefEffect = _cond_fx(DefEnums.Stat.DAMAGE, 2000, CD.RECENTLY_DISEMBARKED, {"within_t": 120})
	f.stat = DefEnums.Stat.DAMAGE
	var s: Array = _setup(f)
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	w.run(3)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 0, "false until SimTransport says so")
	SimCond.set_code(w, e, CD.RECENTLY_DISEMBARKED, true)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 2000, "the pushed bit holds the lease at once")
	t.eq(e.abil.cond_bits, 1, "bit 0 of cond_bits")
	SimCond.set_code(w, e, CD.RECENTLY_DISEMBARKED, false)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 0, "and the clear releases it")


func test_two_conditions_and(t: TestCtx) -> void:
	var f: DefEffect = _cond_fx(DefEnums.Stat.DAMAGE, 700, CD.DEPLOYED, {})
	f.cond_codes = PackedInt32Array([CD.DEPLOYED, CD.IN_ZONE])
	f.cond_params = [{}, {}]
	var s: Array = _setup(f)
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	SimCond.set_code(w, e, CD.DEPLOYED, true)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 0, "one of two codes: false")
	SimCond.set_code(w, e, CD.IN_ZONE, true)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 700, "both: true")
	SimCond.set_code(w, e, CD.DEPLOYED, false)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_DMG_OUT, w.tick), 0, "either off: false")


func test_effect_without_condition_is_always_on(t: TestCtx) -> void:
	var f: DefEffect = AbilKit.fx_op(DefEnums.EffectOp.RESIST_MOD, 1500)
	f.fire_mode_mask = 1  # Layered Fieldworks style: filtered, unconditional
	var s: Array = _setup(f)
	var w: SimWorld = s[0]
	var e: SimEntity = s[1]
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_TAKEN, w.tick, C.DT_BULLET, C.DC_DIRECT), 1500, "held from spawn")
	w.abilities.on_owner_changed(w, e, 0)
	t.eq(SimCombatMods.sum_bp(e.combat, C.STAT_TAKEN, w.tick, C.DT_BULLET, C.DC_DIRECT), 1500, "rebinding keeps it")
