extends RefCounted
## AB-02: timed effects (abilities 5.4, test_abil_fx): refresh, evict, expire, end_on, camouflage, heal.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const EO := DefEnums.EffectOp


func _world(list: Array[DefEffect]) -> SimWorld:
	var d: GameData = AbilKit.data()
	AbilKit.add_zone_effects(d, list)
	return AbilKit.world({}, d)


func _ap(w: SimWorld, e: SimEntity, fx: DefEffect, src: int, dur: int) -> bool:
	return w.abilities.apply_timed_effect(e.id, AbilKit.fx_index(w, fx), dur, e.owner, src)


func test_refresh_takes_the_later_expiry(t: TestCtx) -> void:
	var f: DefEffect = AbilKit.fx_stat(DefEnums.Stat.SPEED, 1000, 0)
	var w: SimWorld = _world([f])
	var e: SimEntity = AbilKit.rifle(w, 0, 30, 30)
	w.run(10)
	t.check(_ap(w, e, f, 5, 100), "applied")
	var i: int = AbilKit.fx_index(w, f)
	t.eq(e.abil.fx[K.FX_EXPIRE], 110, "expires at tick + duration")
	w.run(20)
	t.check(_ap(w, e, f, 5, 50), "same (fx, src_key): refresh")
	t.eq(e.abil.n_fx, 1, "still one entry")
	t.eq(e.abil.fx[K.FX_EXPIRE], 110, "max(old 110, new 30 + 50 = 80)")
	t.check(_ap(w, e, f, 5, 200), "refresh longer")
	t.eq(e.abil.fx[K.FX_EXPIRE], 230, "230")
	t.eq(e.abil.fx[K.FX_AUX], 30, "aux = the refresh tick (end_on baseline)")
	t.check(SimStatus.has(e, i), "has")


func test_window_semantics(t: TestCtx) -> void:
	var f: DefEffect = AbilKit.fx_stat(DefEnums.Stat.SPEED, 1000, 0)
	var w: SimWorld = _world([f])
	var e: SimEntity = AbilKit.rifle(w, 0, 30, 30)
	w.run(5)
	_ap(w, e, f, 5, 20)  # applied during tick 5, covers the combat steps of ticks 5 .. 24
	AbilKit.run_to(w, 24)
	t.check(SimStatus.has(e, AbilKit.fx_index(w, f)), "still there before the step of tick 25's timer... (tick 24 not run)")
	w.step()  # tick 24 completes: combat of tick 24 saw it
	t.check(SimStatus.has(e, AbilKit.fx_index(w, f)), "present through the combat step of tick 24")
	w.step()  # tick 25: removed at the start of step 7
	t.check_false(SimStatus.has(e, AbilKit.fx_index(w, f)), "removed by the timer of tick 25 = T + D")
	t.eq(AbilKit.events(w, K.EV_FX_REMOVED).size(), 1, "one EV_FX_REMOVED")
	t.eq(AbilKit.events(w, K.EV_FX_REMOVED)[0][SimEvent.I_C], K.RR_EXPIRED, "reason expired")


func test_eviction_of_the_earliest_expiry(t: TestCtx) -> void:
	var list: Array[DefEffect] = []
	for k: int in 12:
		list.append(AbilKit.fx_stat(DefEnums.Stat.SIGHT, 100 + k, 100 + k))
	var w: SimWorld = _world(list)
	var e: SimEntity = AbilKit.rifle(w, 0, 30, 30)
	for k: int in 10:
		t.check(_ap(w, e, list[k], 100 + k, 100 + k * 10), "effect %d stored" % k)
	t.eq(e.abil.n_fx, 10, "table full")
	t.check_false(_ap(w, e, list[10], 200, 50), "an 11th effect that would expire before every stored one is dropped")
	t.eq(e.abil.n_fx, 10, "unchanged")
	t.check(_ap(w, e, list[11], 201, 500), "an 11th with a later expiry evicts")
	t.check_false(SimStatus.has(e, AbilKit.fx_index(w, list[0])), "the earliest expiry (effect 0) was evicted")
	var ev: Array[PackedInt32Array] = AbilKit.events(w, K.EV_FX_REMOVED)
	t.eq(ev.size(), 1, "eviction fires EV_FX_REMOVED")
	t.eq(ev[0][SimEvent.I_C], K.RR_EVICTED, "reason evicted")
	t.eq(e.abil.n_fx, 10, "still ten")


func test_end_on_move_fire_detect(t: TestCtx) -> void:
	var sw: DefEffect = AbilKit.fx_op(EO.CAMOUFLAGE, 0, {"end_on": ["move", "fire", "detected"]})
	var w: SimWorld = _world([sw])
	var a: SimEntity = AbilKit.rifle(w, 0, 30, 30)
	var b: SimEntity = AbilKit.rifle(w, 0, 32, 30)
	var c: SimEntity = AbilKit.rifle(w, 0, 34, 30)
	w.run(3)
	for e: SimEntity in [a, b, c]:
		t.check(_ap(w, e, sw, 9, 300), "Silent Watch applied to a stationary unit")
	var i: int = AbilKit.fx_index(w, sw)
	w.run(2)
	t.check(SimStatus.has(a, i) and SimStatus.has(b, i) and SimStatus.has(c, i), "all three hold it")
	t.eq(a.vis.concealed, 1, "concealed")
	a.combat.ext_moving = 1  # movement wrote it before step 7
	w.step()
	t.check_false(SimStatus.has(a, i), "MOVE ends it")
	t.eq(a.vis.concealed, 0, "and the unit shows again")
	a.combat.ext_moving = 0
	w.run(5)
	t.check_false(SimStatus.has(a, i), "it never returns when the unit stops")
	b.combat.last_fire_tick = w.tick - 1  # combat set it during the last step 8
	w.step()
	t.check_false(SimStatus.has(b, i), "FIRE (last_fire_tick >= applied) ends it")
	SimStatus.remove_on_event(w, c, K.RE_DETECT)
	t.check_false(SimStatus.has(c, i), "DETECTED ends it")


func test_camouflage_grant_rules(t: TestCtx) -> void:
	var sw: DefEffect = AbilKit.fx_op(EO.CAMOUFLAGE, 0, {})
	var w: SimWorld = _world([sw])
	var still: SimEntity = AbilKit.rifle(w, 0, 30, 30)
	var moving: SimEntity = AbilKit.rifle(w, 0, 32, 30)
	var mast: SimEntity = AbilKit.rifle(w, 0, 34, 30)
	w.run(2)
	moving.combat.ext_moving = 1
	SimStats.set_flag(mast, K.DF_EXPOSED, true)
	t.check(_ap(w, still, sw, 1, 100), "stationary: granted")
	t.check_false(_ap(w, moving, sw, 1, 100), "moving at application: refused")
	t.check_false(_ap(w, mast, sw, 1, 100), "DF_EXPOSED (deployed mast): refused")
	t.eq(still.vis.concealed, 1, "the grant conceals at once")
	AbilKit.run_to(w, 105)
	t.eq(still.vis.concealed, 0, "and ends with the effect")
	t.eq(AbilKit.events(w, K.EV_CLOAK_CHANGED).size(), 2, "cloak on / off events")


func test_heal_pulses(t: TestCtx) -> void:
	var f: DefEffect = AbilKit.fx_op(EO.HEAL, 0, {"rate_bps": 100, "cost": "free"})
	var w: SimWorld = _world([f])
	var e: SimEntity = AbilKit.tank(w, 0, 30, 30)
	w.run(1)
	e.hp = 400
	e.hp_max = 1000
	_ap(w, e, f, 3, 200)
	AbilKit.run_to(w, 11)
	t.eq(e.hp, 405, "5 hp after the first pulse (hp_max 1000 x 100 bp / 20 = 5000 milli)")
	AbilKit.run_to(w, 21)
	t.eq(e.hp, 410, "and every 10 ticks")
	e.hp_max = 907
	e.hp = 400
	AbilKit.run_to(w, 31)
	t.eq(e.hp, 404, "907 x 100 / 20 = 4535 milli: 4 hp, 535 carried")
	t.eq(e.abil.heal_frac, 535, "remainder in heal_frac")
	AbilKit.run_to(w, 205)
	t.check_false(w.abilities.heal_ids.has(e.id), "heal list cleaned when the effect ended")
