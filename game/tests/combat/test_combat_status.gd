extends RefCounted
## CB-02: flush (queue order, nonlethal clamp, overkill, invulnerable, coalesced EV_HIT, alerts, stats), EMP
## (U-EMP-1..5) and suppression (U-SUP-1..4).

const BULLET: int = SimCombatConsts.DT_BULLET
const EMP: int = SimCombatConsts.DT_EMP
const ALL_EMP_CLASSES: int = SimCombatConsts.EC_VEHICLE | SimCombatConsts.EC_AIRCRAFT | SimCombatConsts.EC_SHIP | SimCombatConsts.EC_STRUCTURE


func _aurora() -> SimCombatWarhead:
	var wh: SimCombatWarhead = CombatKit.wh(40, EMP)
	wh.emp_unit_ticks = 160
	wh.emp_struct_ticks = 360
	wh.emp_class_mask = ALL_EMP_CLASSES
	wh.nonlethal = 1
	wh.friendly_fire = 0
	return wh


func _sup_warhead() -> SimCombatWarhead:
	var wh: SimCombatWarhead = CombatKit.wh(1, BULLET)
	wh.suppressive = 1
	return wh


func _world() -> SimWorld:
	var w: SimWorld = CombatKit.world()
	CombatKit.set_matrix(w, BULLET, DefEnums.ArmorClass.MEDIUM_ARMOR, 10000)
	CombatKit.set_matrix(w, EMP, DefEnums.ArmorClass.MEDIUM_ARMOR, 10000)
	CombatKit.set_matrix(w, BULLET, DefEnums.ArmorClass.INFANTRY, 10000)
	return w


# ---------------------------------------------------------------------------------------------------- flush
func test_flush_applies_in_queue_order_and_kills_once(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var a: SimEntity = CombatKit.tank(w, 0, 20, 20)
	v.hp = 25
	CombatKit.hit(w, v, CombatKit.wh(10), {"atk": a.id, "pid": 0})
	CombatKit.hit(w, v, CombatKit.wh(10), {"atk": a.id, "pid": 0})
	CombatKit.hit(w, v, CombatKit.wh(10), {"atk": a.id, "pid": 0})
	CombatKit.hit(w, v, CombatKit.wh(10), {"atk": a.id, "pid": 0})
	t.eq(v.hp, 25, "nothing is written before the flush")
	SimDamage.flush(w)
	t.eq(v.hp, 0, "dead: hp 0 (kernel kill)")
	t.check((v.flags & SimFlags.F_DEAD) != 0 and (v.combat.cflags & SimCombatConsts.CF_DEAD) != 0, "F_DEAD and CF_DEAD")
	t.eq(v.combat.last_attacker_id, a.id, "the killing blow's attacker is remembered")
	t.eq(w.players[0].st_damage_dealt, 25, "overkill is not counted: 10 + 10 + 5 applied")
	t.eq(w.players[1].st_damage_taken, 25, "damage taken")
	t.eq(a.combat.last_dealt_tick, w.tick, "attacker last_dealt_tick")
	t.eq(v.combat.last_hit_tick, w.tick, "victim last_hit_tick")
	t.eq(w.combat.dmg_queue.size(), 0, "queue cleared")
	var hits: Array[PackedInt32Array] = CombatKit.events(w, SimCombatConsts.EV_HIT)
	t.eq(hits.size(), 1, "one coalesced EV_HIT per victim per tick")
	var h: PackedInt32Array = hits[0]
	t.eq([h[SimEvent.I_A], h[SimEvent.I_B], h[SimEvent.I_C], h[SimEvent.I_E], h[SimEvent.I_F]], [v.id, 30, a.id, 0, v.hp_max], "victim, total 10 + 10 + 10, attacker, hp after, hp_max")
	t.eq(h[SimEvent.I_D] & 0xFF, BULLET, "dtype")
	t.eq((h[SimEvent.I_D] >> 8) & 0xFF, SimCombatConsts.DC_DIRECT, "dc")
	t.check(((h[SimEvent.I_D] >> 16) & SimCombatConsts.HITF_KILLED) != 0, "killed flag")
	t.check((v.combat.focus_mask & (1 << (w.team_of(0) & 7))) != 0, "the attacker's team is recorded as focus")


func test_flush_skips_invulnerable_missing_and_indestructible(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var hp0: int = v.hp
	v.combat.cflags |= SimCombatConsts.CF_INVULNERABLE
	CombatKit.hit(w, v, CombatKit.wh(10))
	SimDamage.flush(w)
	t.eq(v.hp, hp0, "CF_INVULNERABLE takes no damage")
	v.combat.cflags &= ~SimCombatConsts.CF_INVULNERABLE
	v.flags |= SimFlags.F_INVULNERABLE
	CombatKit.hit(w, v, CombatKit.wh(10))
	SimDamage.flush(w)
	t.eq(v.hp, hp0, "F_INVULNERABLE takes no damage")
	v.flags &= ~SimFlags.F_INVULNERABLE
	CombatKit.hit(w, v, CombatKit.wh(10))
	v.hp_max = 0
	SimDamage.flush(w)
	t.eq(v.hp, hp0, "hp_max 0 = indestructible")
	v.hp_max = hp0
	CombatKit.hit(w, v, CombatKit.wh(10))
	w.remove_entity(v.id, SimEvent.REM_SCRIPT)
	SimDamage.flush(w)
	t.eq(v.hp, hp0, "a leaving entity is skipped")
	t.eq(CombatKit.events(w, SimCombatConsts.EV_HIT).size(), 0, "and produces no hit event")


func test_nonlethal_clamps_to_one_hp(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.tank(w, 1, 30, 30)
	v.hp = 10
	CombatKit.hit(w, v, _aurora())
	SimDamage.flush(w)
	t.eq(v.hp, 1, "EMP damage 40 leaves 1 hp")
	t.check((v.flags & SimFlags.F_DEAD) == 0, "never lethal")
	var wh: SimCombatWarhead = CombatKit.wh(50)
	wh.nonlethal = 1
	CombatKit.hit(w, v, wh)
	SimDamage.flush(w)
	t.eq(v.hp, 1, "a nonlethal warhead of another type too")


func test_two_victims_two_events_in_first_touch_order(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var b: SimEntity = CombatKit.rifle(w, 1, 34, 30)
	CombatKit.hit(w, b, CombatKit.wh(3))
	CombatKit.hit(w, a, CombatKit.wh(4))
	CombatKit.hit(w, b, CombatKit.wh(5))
	SimDamage.flush(w)
	var hits: Array[PackedInt32Array] = CombatKit.events(w, SimCombatConsts.EV_HIT)
	t.eq(hits.size(), 2, "two victims")
	t.eq([hits[0][SimEvent.I_A], hits[0][SimEvent.I_B], hits[1][SimEvent.I_A], hits[1][SimEvent.I_B]], [b.id, 8, a.id, 4], "first-touch order, summed damage")


func test_attack_alerts_are_throttled(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var far: SimEntity = CombatKit.tank(w, 1, 60, 60)
	var own: SimEntity = CombatKit.tank(w, 0, 20, 20)
	CombatKit.hit(w, v, CombatKit.wh(1))
	CombatKit.hit(w, v, CombatKit.wh(1))
	SimDamage.flush(w)
	var al: Array[PackedInt32Array] = CombatKit.events(w, SimCombatConsts.EV_ATTACK_ALERT)
	t.eq(al.size(), 1, "two hits in one tick alert once")
	t.eq([al[0][SimEvent.I_A], al[0][SimEvent.I_B], al[0][SimEvent.I_C], al[0][SimEvent.I_D]], [1, v.id, 0, 0], "owner pid, victim, attacker pid, class unit")
	w.tick += 100
	CombatKit.hit(w, v, CombatKit.wh(1))
	SimDamage.flush(w)
	t.eq(CombatKit.events(w, SimCombatConsts.EV_ATTACK_ALERT).size(), 1, "within the cooldown and near the last alert: silent")
	CombatKit.hit(w, far, CombatKit.wh(1))
	SimDamage.flush(w)
	t.eq(CombatKit.events(w, SimCombatConsts.EV_ATTACK_ALERT).size(), 2, "30 cells away from the last alert: alerts again")
	w.tick += 200
	CombatKit.hit(w, v, CombatKit.wh(1))
	SimDamage.flush(w)
	t.eq(CombatKit.events(w, SimCombatConsts.EV_ATTACK_ALERT).size(), 3, "after the cooldown: alerts again")
	CombatKit.hit(w, own, CombatKit.wh(1), {"pid": 0})
	SimDamage.flush(w)
	t.eq(CombatKit.events(w, SimCombatConsts.EV_ATTACK_ALERT).size(), 3, "friendly fire never alerts")
	var s: SimEntity = CombatKit.turret(w, 1, 40, 40)
	CombatKit.set_matrix(w, BULLET, DefEnums.ArmorClass.BUILDING_LIGHT, 10000)
	CombatKit.set_matrix(w, BULLET, DefEnums.ArmorClass.BUILDING_HEAVY, 10000)
	w.tick += 200
	CombatKit.hit(w, s, CombatKit.wh(1))
	SimDamage.flush(w)
	var al2: Array[PackedInt32Array] = CombatKit.events(w, SimCombatConsts.EV_ATTACK_ALERT)
	t.eq(al2[al2.size() - 1][SimEvent.I_D], 1, "structure class")


# ------------------------------------------------------------------------------------------------------ EMP
func test_u_emp_1_tank(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var hp0: int = v.hp
	CombatKit.hit(w, v, _aurora())
	SimDamage.flush(w)
	t.eq(v.hp, hp0 - 40, "EMP still deals its normal damage")
	t.eq(v.combat.emp_until, 160, "weapons off for 160 ticks")
	t.check(not w.combat.weapons_online(w, v), "weapons offline")
	t.check(not w.combat.is_functional(w, v), "and the entity counts as non-functional")
	t.check((v.flags & SimFlags.F_EMP_SHUT) != 0 and (v.flags & SimFlags.F_WEAPONS_OFF) != 0, "state mirrors set")
	var ev: Array[PackedInt32Array] = CombatKit.events(w, SimCombatConsts.EV_EMP)
	t.eq([ev[0][SimEvent.I_A], ev[0][SimEvent.I_B], ev[0][SimEvent.I_C], ev[0][SimEvent.I_E]], [v.id, 160, 0, 0], "EV_EMP: duration 160, weapons off, not blocked")
	t.eq(CombatKit.events(w, SimCombatConsts.EV_WEAPON_LOCK).size(), 1, "EV_WEAPON_LOCK offline")
	CombatKit.run_to(w, 159)
	t.check(not w.combat.weapons_online(w, v), "still offline at tick 159")
	CombatKit.run_to(w, 160)
	t.check(w.combat.weapons_online(w, v), "online at tick 160")
	CombatKit.run_to(w, 161)
	t.eq(v.combat.emp_until, 0, "upkeep cleared the timer")
	t.check((v.flags & SimFlags.F_EMP_SHUT) == 0 and (v.flags & SimFlags.F_WEAPONS_OFF) == 0, "mirrors cleared")
	var lk: Array[PackedInt32Array] = CombatKit.events(w, SimCombatConsts.EV_WEAPON_LOCK)
	t.eq([lk.size(), lk[1][SimEvent.I_B], lk[1][SimEvent.I_TICK]], [2, 0, 160], "EV_WEAPON_LOCK online at tick 160")


func test_u_emp_1_hp_floor(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.tank(w, 1, 30, 30)
	v.hp = 20
	CombatKit.hit(w, v, _aurora())
	SimDamage.flush(w)
	t.eq(v.hp, 1, "hp >= 1 after EMP damage")
	t.check((v.flags & SimFlags.F_DEAD) == 0, "alive")


func test_u_emp_2_aircraft_keeps_flying(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.tank(w, 1, 30, 30)
	w.set_layer(v, SimEntity.Layer.AIR)
	v.hp = 30
	CombatKit.hit(w, v, _aurora())
	SimDamage.flush(w)
	t.eq(v.combat.emp_until, 160, "aircraft: weapons off for 160 ticks")
	t.eq(v.layer, SimEntity.Layer.AIR, "still airborne")
	t.check((v.flags & SimFlags.F_DEAD) == 0 and v.hp >= 1, "not dying")
	t.eq(SimDamage.emp_class(v, CombatKit.cdef(w, v)), SimCombatConsts.EC_AIRCRAFT, "class aircraft")


func test_u_emp_3_structure(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var s: SimEntity = CombatKit.turret(w, 1, 40, 40)
	CombatKit.set_matrix(w, EMP, DefEnums.ArmorClass.BUILDING_HEAVY, 10000)
	CombatKit.set_matrix(w, EMP, DefEnums.ArmorClass.BUILDING_LIGHT, 10000)
	s.flags |= SimFlags.F_POWERED
	t.check(w.combat.is_functional(w, s), "a powered turret is functional")
	CombatKit.hit(w, s, _aurora())
	SimDamage.flush(w)
	t.eq(s.combat.emp_until, 360, "structure shutdown 360 ticks")
	t.check(not w.combat.is_functional(w, s), "shut down")
	t.check(not w.combat.weapons_online(w, s), "defences offline")
	var ev: Array[PackedInt32Array] = CombatKit.events(w, SimCombatConsts.EV_EMP)
	t.eq([ev[0][SimEvent.I_B], ev[0][SimEvent.I_C]], [360, 1], "EV_EMP: 360 ticks, shutdown")
	CombatKit.run_to(w, 361)
	s.flags |= SimFlags.F_POWERED  # the power stage owns this flag and may have cleared it while stepping
	t.check(w.combat.is_functional(w, s), "functional again")
	s.flags &= ~SimFlags.F_POWERED
	t.check(not w.combat.is_functional(w, s), "an unpowered defence is non-functional anyway")


func test_u_emp_4_infantry_unaffected(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var r: SimEntity = CombatKit.rifle(w, 1, 30, 30)
	var hp0: int = r.hp
	t.eq(CombatKit.hit(w, r, _aurora()), 0, "0 % matrix: nothing queued")
	SimDamage.flush(w)
	t.eq([r.hp, r.combat.emp_until], [hp0, 0], "no damage, no status")
	CombatKit.set_matrix(w, EMP, DefEnums.ArmorClass.INFANTRY, 10000)
	CombatKit.hit(w, r, _aurora())
	SimDamage.flush(w)
	t.eq(r.combat.emp_until, 0, "even with a matrix, infantry is outside the warhead's class mask")
	t.eq(r.hp, hp0 - 40, "but the damage row still applies")


func test_u_emp_5_recovery_immunity_refresh(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.tank(w, 1, 30, 30)
	SimCombatMods.apply(w, v, 1, SimCombatConsts.STAT_EMP_RECOVER, 2500, 0, 1000)  # Resilient Mesh
	CombatKit.hit(w, v, _aurora())
	SimDamage.flush(w)
	t.eq(v.combat.emp_until, 120, "unmanned: 160 * 0.75 = 120 ticks")
	CombatKit.run_to(w, 50)
	SimCombatMods.apply(w, v, 2, SimCombatConsts.STAT_EMP_RECOVER, 9000, 0, 1000)
	CombatKit.hit(w, v, _aurora())
	SimDamage.flush(w)
	t.eq(v.combat.emp_until, 50 + 80, "recovery is clamped to 50 %: 160 -> 80, re-hits refresh to max(old, new)")
	CombatKit.run_to(w, 200)
	var u: SimEntity = CombatKit.tank(w, 1, 34, 34)
	SimCombatMods.apply(w, u, 3, SimCombatConsts.STAT_FLAG_EMP_IMMUNE, 0, 0, 10)  # Redundant Orders
	var hp0: int = u.hp
	CombatKit.hit(w, u, _aurora())
	SimDamage.flush(w)
	t.eq(u.combat.emp_until, 0, "immune: no status")
	t.eq(u.hp, hp0 - 40, "but the damage is still dealt")
	var ev: Array[PackedInt32Array] = CombatKit.events(w, SimCombatConsts.EV_EMP)
	t.eq([ev[ev.size() - 1][SimEvent.I_A], ev[ev.size() - 1][SimEvent.I_E]], [u.id, 1], "EV_EMP blocked")
	t.check(w.combat.weapons_online(w, u), "stays online")


func test_emp_static_recovery_from_def_param(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.tank(w, 1, 30, 30)
	t.eq(w.combat.emp_recover_bp(w, v), 0, "no research: no reduction")


# ------------------------------------------------------------------------------------------- suppression
func _sup_run(hits: PackedInt32Array, leases: bool = false, immune: bool = false) -> Dictionary:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.rifle(w, 1, 30, 30)
	if leases:
		SimCombatMods.apply(w, v, 1, SimCombatConsts.STAT_SUP_RECOVER, 5000, 0, 5000)
	if immune:
		SimCombatMods.apply(w, v, 2, SimCombatConsts.STAT_FLAG_SUP_IMMUNE, 0, 0, 5000)
	var wh: SimCombatWarhead = _sup_warhead()
	var last: int = hits[hits.size() - 1] + 100
	var hi: int = 0
	for tk: int in last:
		while hi < hits.size() and hits[hi] == w.tick:
			CombatKit.hit(w, v, wh)
			hi += 1
		w.step()
	var begins: PackedInt32Array = PackedInt32Array()
	var ends: PackedInt32Array = PackedInt32Array()
	for e: PackedInt32Array in CombatKit.events(w, SimCombatConsts.EV_SUPPRESS):
		(begins if e[SimEvent.I_B] == 1 else ends).append(e[SimEvent.I_TICK])
	return {"begins": begins, "ends": ends, "w": w, "v": v}


func test_u_sup_1_three_hits_in_window(t: TestCtx) -> void:
	var r: Dictionary = _sup_run(PackedInt32Array([0, 15, 30]))
	t.eq(r["begins"], PackedInt32Array([30]), "begins at 30 (30 - 0 <= 40)")
	t.eq(r["ends"], PackedInt32Array([90]), "ends 60 ticks later")
	var w: SimWorld = r["w"]
	var v: SimEntity = r["v"]
	t.check(not w.combat.is_suppressed(v) and w.combat.suppression_speed_bp(v) == 10000, "over: full speed")
	t.check((v.flags & SimFlags.F_SUPPRESSED) == 0, "mirror cleared")


func test_u_sup_2_too_slow(t: TestCtx) -> void:
	var r: Dictionary = _sup_run(PackedInt32Array([0, 30, 60]))
	t.eq((r["begins"] as PackedInt32Array).size(), 0, "hits at 0, 30, 60 never trigger (60 - 0 > 40)")


func test_u_sup_3_recovery_aura(t: TestCtx) -> void:
	var r: Dictionary = _sup_run(PackedInt32Array([0, 10, 20]), true)
	t.eq([r["begins"], r["ends"]], [PackedInt32Array([20]), PackedInt32Array([60])], "SUP_RECOVER +5000: the 3 s tail lasts 2 s")


func test_u_sup_4_immune(t: TestCtx) -> void:
	var r: Dictionary = _sup_run(PackedInt32Array([0, 10, 20]), false, true)
	t.eq((r["begins"] as PackedInt32Array).size(), 0, "immune infantry is never suppressed")


func test_suppression_effects_and_restart(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatKit.rifle(w, 1, 30, 30)
	var wh: SimCombatWarhead = _sup_warhead()
	for tk: int in 3:
		CombatKit.hit(w, v, wh)
		w.step()
	t.check(w.combat.is_suppressed(v), "suppressed after 3 hits in 3 ticks")
	t.eq(w.combat.suppression_speed_bp(v), 7500, "movement runs at 75 %")
	t.check((v.flags & SimFlags.F_SUPPRESSED) != 0, "mirror set")
	CombatKit.run_to(w, 40)
	CombatKit.hit(w, v, wh)
	w.step()
	t.eq(v.combat.sup_left_q8, 60 * 256 - 256 * 0, "a hit while suppressed restarts the full tail")
	SimDamage.clear_suppression(w, v)
	t.check(not w.combat.is_suppressed(v), "clear_suppression")
	t.eq([v.combat.sup_t0, v.combat.sup_i], [SimCombatConsts.NEVER, 0], "and empties the hit ring")
	var tank: SimEntity = CombatKit.tank(w, 1, 34, 34)
	for tk2: int in 5:
		CombatKit.hit(w, tank, wh)
	SimDamage.flush(w)
	t.check(not w.combat.is_suppressed(tank), "only infantry can be suppressed")
	var plain: SimCombatWarhead = CombatKit.wh(1, BULLET)
	for tk3: int in 5:
		CombatKit.hit(w, v, plain)
	SimDamage.flush(w)
	t.check(not w.combat.is_suppressed(v), "non-suppressive warheads never count")
