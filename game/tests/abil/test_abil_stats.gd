extends RefCounted
## AB-02: effective stats through DefLayer3 + temporary extra_bp (abilities 5.2.2, test_abil_stats).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const ST := DefEnums.Stat


func _world(effects: Array[DefEffect], conds: Array[DefEffect] = []) -> SimWorld:
	var d: GameData = AbilKit.data()
	AbilKit.set_sight(d, DefTestKit.U_ENGINEER, 6144)
	AbilKit.add_zone_effects(d, effects)
	AbilKit.add_research_effects(d, conds)
	return AbilKit.world({}, d)


func _apply(w: SimWorld, e: SimEntity, fx: DefEffect, src_key: int, dur: int = 200) -> bool:
	return w.abilities.apply_timed_effect(e.id, AbilKit.fx_index(w, fx), dur, e.owner, src_key)


func test_gate_guard_sight(t: TestCtx) -> void:
	var f: DefEffect = AbilKit.fx_stat(ST.SIGHT, 2000, 0)
	var w: SimWorld = _world([f])
	var e: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 30, 30)
	t.eq(SimStats.get_val(w, e, ST.SIGHT), 6144, "base sight 6 cells")
	t.check(_apply(w, e, f, 5), "Straits Crossfire applied")
	t.eq(SimStats.get_val(w, e, ST.SIGHT), DefStatMath.apply_bp(6144, 2000), "6144 +20 %")
	t.eq(SimStats.get_val(w, e, ST.SIGHT), 7373, "= 7373 units")
	t.eq(SimDisc.radius_cells(7373), 7, "stamped radius (7373 + 512) >> 10 = 7")
	w.run(4)
	t.eq(e.vis.r_cells, 7, "the vision system restamped the bigger disc")
	AbilKit.run_to(w, 205)
	t.eq(SimStats.get_val(w, e, ST.SIGHT), 6144, "expired at tick 200")
	t.eq(e.vis.r_cells, 6, "and the disc shrank again")


func test_distinct_groups_add_same_group_counts_once(t: TestCtx) -> void:
	var corridor: DefEffect = AbilKit.fx_stat(ST.SPEED, 2500, 1)
	var debris: DefEffect = AbilKit.fx_stat(ST.SPEED, -3500, 2)
	var jam: DefEffect = AbilKit.fx_stat(ST.SIGHT, -2500, 3)
	var g4a: DefEffect = AbilKit.fx_stat(ST.SIGHT, 1000, 4)
	var g4b: DefEffect = AbilKit.fx_stat(ST.SIGHT, 1500, 4)
	var w: SimWorld = _world([corridor, debris, jam, g4a, g4b])
	var e: SimEntity = AbilKit.spawn(w, DefTestKit.U_RIFLEMAN, 0, 30, 30)
	var base: int = SimStats.get_val(w, e, ST.SPEED)
	_apply(w, e, corridor, 1)
	_apply(w, e, debris, 2)
	SimStats.get_val(w, e, ST.SPEED)
	t.eq(e.stats.extra[K.K_SPEED], -1000, "Open Corridor +2500 and Debris -3500 in different groups: -1000")
	t.eq(SimStats.get_val(w, e, ST.SPEED), DefStatMath.apply_bp(base, -1000), "speed x0.90")
	_apply(w, e, jam, 11)
	_apply(w, e, jam, 12)  # a second Aster: same group, counts once
	SimStats.get_val(w, e, ST.SIGHT)
	t.eq(e.stats.extra[K.K_SIGHT], -2500, "two jammers of one group count once")
	_apply(w, e, g4a, 21)
	_apply(w, e, g4b, 22)
	SimStats.get_val(w, e, ST.SIGHT)
	t.eq(e.stats.extra[K.K_SIGHT], -2500 + 1500, "+1000 and +1500 in one group contribute +1500 (largest |delta|)")


func test_bound_condition_adds_to_timed(t: TestCtx) -> void:
	var corridor: DefEffect = AbilKit.fx_stat(ST.SPEED, 2500, 1)
	var caches: DefEffect = AbilKit.fx_stat(ST.SPEED, 1000)
	caches.cond_codes = PackedInt32Array([DefEnums.Cond.OUT_OF_COMBAT])
	caches.cond_params = [{"for_t": 120}]
	var w: SimWorld = _world([corridor], [caches])
	AbilKit.bind_cond(w, 0, DefTestKit.U_RIFLEMAN, caches)
	var e: SimEntity = AbilKit.spawn(w, DefTestKit.U_RIFLEMAN, 0, 30, 30)
	t.eq(e.stats.cond_fx.size(), 1, "one bound effect")
	var base: int = SimStats.get_val(w, e, ST.SPEED)
	t.eq(base, DefStatMath.apply_bp(77, 1000), "true at binding: out of combat since forever, so +10 % speed")
	t.eq(e.abil.cond_bits, 1, "bound bit set")
	_apply(w, e, corridor, 1)
	SimStats.get_val(w, e, ST.SPEED)
	t.eq(e.stats.extra[K.K_SPEED], 3500, "Fuel Caches +1000 and Open Corridor +2500 = +3500")


func test_peek_never_writes(t: TestCtx) -> void:
	var f: DefEffect = AbilKit.fx_stat(ST.SPEED, 1000, 0)
	var w: SimWorld = _world([f])
	var e: SimEntity = AbilKit.spawn(w, DefTestKit.U_RIFLEMAN, 0, 30, 30)
	SimStats.get_val(w, e, ST.SPEED)
	_apply(w, e, f, 3)
	var before: PackedInt32Array = PackedInt32Array()
	e.stats.hash_into(before)
	var v: int = SimStats.peek(w, e, ST.SPEED)
	var after: PackedInt32Array = PackedInt32Array()
	e.stats.hash_into(after)
	t.eq(before, after, "peek leaves the component untouched")
	t.eq(v, SimStats.get_val(w, e, ST.SPEED), "and equals what get_val computes")


func test_movement_adapters(t: TestCtx) -> void:
	var f: DefEffect = AbilKit.fx_stat(ST.SPEED, -3500, 0)
	var w: SimWorld = _world([f])
	var e: SimEntity = AbilKit.spawn(w, DefTestKit.U_RIFLEMAN, 0, 30, 30)
	var base: int = w.abilities.speed_units(e)
	t.eq(base, 77, "speed_units = the def's speed")
	_apply(w, e, f, 3)
	t.eq(w.abilities.speed_units(e), DefStatMath.apply_bp(77, -3500), "slowed")
	t.check_false(w.abilities.is_immobile(e), "not immobile")
	SimStats.set_flag(e, K.DF_IMMOBILE, true)
	t.check(w.abilities.is_immobile(e), "DF_IMMOBILE")
	t.check_false(w.abilities.is_turn_locked(e), "not turn locked")
	SimStats.set_flag(e, K.DF_TURN_LOCKED, true)
	t.check(w.abilities.is_turn_locked(e), "DF_TURN_LOCKED")
	w.abilities.request_pack(e)
