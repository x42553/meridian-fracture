extends RefCounted
## CB-05: filters, scoring, scan scheduling / budget, stances and leash, target validation (hidden, leash), retaliation and
## assist, overkill guard, independent mounts.


func _world(n: int = 2) -> SimWorld:
	var w: SimWorld = CombatWK.world(n)
	CombatWK.set_matrix_all(w, 10000)
	return w


func _quiet(e: SimEntity, hp: int = 100000) -> SimEntity:
	e.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	CombatWK.set_hp(e, hp)
	return e


func _place(w: SimWorld, e: SimEntity, cx: int, cy: int) -> void:
	w.set_pos(e, cx * SimConfig.CELL + 512, cy * SimConfig.CELL + 512, true)


func _scan(w: SimWorld, e: SimEntity) -> void:
	SimTargeting.scan(w, w.combat, e)


# ---------------------------------------------------------------------------------------------- scoring
func test_tgt_1_scoring_prio_matrix_ties(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var foe_tank: SimEntity = _quiet(CombatWK.tank(w, 1, 35, 30))
	var foe_inf: SimEntity = _quiet(CombatWK.rifle(w, 1, 30, 35))
	CombatWK.cd(w, foe_tank).prio = 8
	CombatWK.cd(w, foe_inf).prio = 6
	CombatWK.set_matrix_all(w, 10000)
	w.combat.matrix_bp[SimCombatConsts.DT_AP * w.combat.n_armor + CombatWK.cd(w, foe_tank).armor] = 20000  # AT weapon: 200 % vs the tank
	_scan(w, a)
	t.eq(a.combat.target_id, foe_tank.id, "tank (prio 8, matrix 200 %) beats infantry (prio 6)")
	t.eq(a.combat.target_src, SimCombatConsts.TS_AUTO, "auto source")
	t.check((foe_tank.combat.focus_mask & (1 << (w.team_of(0) & 7))) != 0, "acquiring stamps the target's focus mask")
	# equal score: lowest id
	var w2: SimWorld = _world()
	var a2: SimEntity = CombatWK.tank(w2, 0, 30, 30)
	var e1: SimEntity = _quiet(CombatWK.tank(w2, 1, 35, 30))
	var e2: SimEntity = _quiet(CombatWK.tank(w2, 1, 30, 35))
	t.lt(e1.id, e2.id, "setup ids")
	_scan(w2, a2)
	t.eq(a2.combat.target_id, e1.id, "tie -> lowest entity id")
	# wounded target scores higher
	e2.hp = e2.hp_max / 4
	e1.combat.focus_mask = 0
	a2.combat.target_id = -1
	a2.combat.target_src = SimCombatConsts.TS_NONE
	_scan(w2, a2)
	t.eq(a2.combat.target_id, e2.id, "wounded_max bonus prefers the weakened tank")
	# weapons never auto-acquire targets they barely hurt
	var w3: SimWorld = _world()
	var a3: SimEntity = CombatWK.tank(w3, 0, 30, 30)
	var bunk: SimEntity = _quiet(CombatWK.tank(w3, 1, 34, 30))
	w3.combat.matrix_bp[SimCombatConsts.DT_AP * w3.combat.n_armor + CombatWK.cd(w3, bunk).armor] = 1000  # 10 % < auto_min 15 %
	_scan(w3, a3)
	t.eq(a3.combat.target_id, -1, "matrix below auto_min_eff: not acquired")
	t.check(w3.combat.set_target(w3, a3, bunk.id, SimCombatConsts.TS_ORDER), "but an explicit order is accepted")


func test_tgt_2_stickiness_and_overkill(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var t1: SimEntity = _quiet(CombatWK.tank(w, 1, 34, 30))
	var t2: SimEntity = _quiet(CombatWK.tank(w, 1, 30, 34))
	w.combat.set_target(w, a, t2.id, SimCombatConsts.TS_AUTO)
	_scan(w, a)
	t.eq(a.combat.target_id, t2.id, "equal candidates: the current target sticks (stick bonus beats the id tie-break)")
	# overkill: 10 hp left with 15 in flight
	t2.hp = 10
	t2.combat.inflight_est = 15
	_scan(w, a)
	t.eq(a.combat.target_id, t1.id, "target already covered by shots in flight: switch to the next")
	# scan reschedule
	t.eq(a.combat.scan_next, w.tick + SimCombatConsts.RESCORE_INTERVAL, "a unit with an auto target rescans every RESCORE_INTERVAL")


func test_tgt_2_hold_fire_orders(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var foe: SimEntity = _quiet(CombatWK.tank(w, 1, 34, 30))
	CombatWK.make_hitscan(w, a, 5, 10, 7168)
	a.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	CombatWK.run(w, 40)
	t.eq(a.combat.target_id, -1, "hold fire never auto-acquires")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_FIRE).size(), 0, "and never fires")
	t.check(w.combat.set_target(w, a, foe.id, SimCombatConsts.TS_ORDER), "order accepted")
	CombatWK.run(w, 12)
	t.gt(CombatWK.evs(w, SimCombatConsts.EV_FIRE).size(), 0, "fires on ORD_ATTACK under hold fire")


# ---------------------------------------------------------------------------------------------- filters
func test_tgt_3_filters(t: TestCtx) -> void:
	var w: SimWorld = _world(3)
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var cdA: SimCombatDef = CombatWK.cd(w, a)
	var g: SimEntity = CombatWK.tank(w, 1, 34, 30)  # ground (also: a parked aircraft is LAYER_GROUND)
	var sky: SimEntity = CombatWK.tank(w, 1, 34, 31)
	w.set_layer(sky, SimCombatConsts.LAYER_AIR)
	var sub: SimEntity = CombatWK.tank(w, 1, 34, 32)
	w.set_layer(sub, SimCombatConsts.LAYER_UNDERWATER)
	var boat: SimEntity = CombatWK.tank(w, 1, 34, 33)
	w.set_layer(boat, SimCombatConsts.LAYER_SURFACE)
	t.check(SimTargeting.can_engage(w, a, cdA, 0, g, false), "ground gun vs ground")
	t.check(not SimTargeting.can_engage(w, a, cdA, 0, sky, false), "ground gun vs air: not engaged")
	t.check(not SimTargeting.can_engage(w, a, cdA, 0, sub, false), "ground gun vs submerged: not engaged")
	t.check(SimTargeting.can_engage(w, a, cdA, 0, boat, false), "ground/water gun vs surface")
	# AA mount
	CombatWK.prof_set(w, a, 0, {SimWeaponProfile.PF_TF: SimCombatConsts.TF_AIR})
	t.check(SimTargeting.can_engage(w, a, cdA, 0, sky, false), "AA vs air")
	t.check(not SimTargeting.can_engage(w, a, cdA, 0, g, false), "AA vs a parked aircraft (LAYER_GROUND): not engaged")
	# ASW mount
	CombatWK.prof_set(w, a, 0, {SimWeaponProfile.PF_TF: SimCombatConsts.TF_UNDERWATER})
	t.check(SimTargeting.can_engage(w, a, cdA, 0, sub, false), "ASW vs submerged")
	w.set_layer(sub, SimCombatConsts.LAYER_SURFACE)
	t.check(not SimTargeting.can_engage(w, a, cdA, 0, sub, false), "ASW vs a surfaced boat: not engaged")
	w.set_layer(sub, SimCombatConsts.LAYER_UNDERWATER)
	# strategic blast still hurts the submerged (layer mask contains LAYER_UNDERWATER)
	var strat: SimCombatWarhead = CombatKit.wh(300, SimCombatConsts.DT_KINETIC)
	strat.layer_mask = 15
	strat.splash_r = 2048
	strat.splash_inner = 2048
	strat.splash_edge_bp = 10000
	strat.delivery = SimCombatConsts.DELIV_STRATEGIC
	CombatWK.set_hp(sub, 5000)
	w.combat.proj.detonate(w, strat, sub.x, sub.y, -1, 300, 10000, 0, 0, -1, 0, -1, -1, true)
	SimDamage.flush(w)
	t.lt(sub.hp, 5000, "strategic warhead damages a submerged unit")
	var ground_only: SimCombatWarhead = CombatKit.wh(300, SimCombatConsts.DT_KINETIC)
	ground_only.layer_mask = 1 << SimCombatConsts.LAYER_GROUND
	ground_only.splash_r = 2048
	ground_only.splash_inner = 2048
	ground_only.splash_edge_bp = 10000
	CombatWK.set_hp(sub, 5000)
	w.combat.proj.detonate(w, ground_only, sub.x, sub.y, -1, 300, 10000, 0, 0, -1, 0, -1, -1, true)
	SimDamage.flush(w)
	t.eq(sub.hp, 5000, "an ordinary ground warhead does not")
	# wrecks: force only
	CombatWK.prof_set(w, a, 0, {SimWeaponProfile.PF_TF: SimCombatConsts.TF_GROUND | SimCombatConsts.TF_STRUCTURE})
	var wreck: SimEntity = w.spawn_wreck(g, false, 100, 100)
	t.check(not SimTargeting.can_engage(w, a, cdA, 0, wreck, false), "wrecks are never auto targets")
	t.check(SimTargeting.can_engage(w, a, cdA, 0, wreck, true), "but force fire may shoot them")
	# relation: neutral / third parties only by force
	var third: SimEntity = CombatWK.tank(w, 2, 36, 30)
	t.check(SimTargeting.can_engage(w, a, cdA, 0, third, false), "enemy player")
	var w2: SimWorld = CombatWK.world(3, 4242, PackedInt32Array([1, 1, 2]))
	var mate: SimEntity = CombatWK.tank(w2, 1, 34, 30)
	var s2: SimEntity = CombatWK.tank(w2, 0, 30, 30)
	t.check(not SimTargeting.can_engage(w2, s2, CombatWK.cd(w2, s2), 0, mate, false), "allies are not auto targets")
	t.check(SimTargeting.can_engage(w2, s2, CombatWK.cd(w2, s2), 0, mate, true), "force fire may hit allies")
	s2.combat.cflags |= SimCombatConsts.CF_ENEMY_ONLY
	t.check(not SimTargeting.can_engage(w2, s2, CombatWK.cd(w2, s2), 0, mate, true), "summoned attackers select enemies only, even under force")
	t.check(not w2.combat.set_target(w2, s2, mate.id, SimCombatConsts.TS_ORDER), "CMD_ATTACK on a non-enemy is refused")
	# untargetable / cargo / decoys
	g.combat.cflags |= SimCombatConsts.CF_UNTARGETABLE
	t.check(not SimTargeting.can_engage(w, a, cdA, 0, g, true), "untargetable (cargo, docked): never, even forced")
	g.combat.cflags &= ~SimCombatConsts.CF_UNTARGETABLE
	g.container_id = 999
	t.check(not SimTargeting.can_engage(w, a, cdA, 0, g, true), "inside a container: never")
	g.container_id = -1
	var fog: CombatWK.DecoyFog = CombatWK.DecoyFog.new()
	w.fog = fog
	g.combat.cflags |= SimCombatConsts.CF_DECOY
	t.check(SimTargeting.can_engage(w, a, cdA, 0, g, false), "an unidentified decoy looks like a target")
	fog.identified.append(g.id)
	t.check(not SimTargeting.can_engage(w, a, cdA, 0, g, false), "an identified decoy is not auto-acquired")


# ---------------------------------------------------------------------------------------------- retaliation / assist
func test_tgt_4_retaliation_and_assist(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var x: SimEntity = _quiet(CombatWK.tank(w, 1, 44, 30))  # too far to be scanned: only retaliation can pick it
	CombatWK.set_hp(v, 100000)
	var ids: Array = []
	for i: int in 3:
		ids.append(CombatWK.tank(w, 0, 30 + i, 26).id)
	var far: SimEntity = CombatWK.tank(w, 0, 30, 45)  # > 8 cells
	var holder: SimEntity = CombatWK.tank(w, 0, 33, 27)
	holder.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	var busy: SimEntity = CombatWK.tank(w, 0, 34, 28)
	busy.combat.target_id = 12345  # already engaged
	var wh: SimCombatWarhead = CombatKit.wh(10, SimCombatConsts.DT_BULLET)
	SimDamage.deal(w, v, wh, 10, SimCombatConsts.DC_DIRECT, 0, x.id, 1, true, 10000, 0, 10000, 0, 0, v.x, v.y)
	SimDamage.flush(w)
	t.eq([v.combat.target_id, v.combat.target_src], [x.id, SimCombatConsts.TS_RETAL], "the attacked idle unit targets its attacker")
	for id: int in ids:
		var e: SimEntity = w.get_entity(id)
		t.eq([e.combat.target_id, e.combat.target_src], [x.id, SimCombatConsts.TS_RETAL], "idle ally %d assists" % id)
	t.eq(far.combat.target_id, -1, "outside the assist radius: no")
	t.eq(holder.combat.target_id, -1, "hold fire: no")
	t.eq(busy.combat.target_id, 12345, "busy: no")
	# second event within the cooldown: a new idle ally does not join
	var late: SimEntity = CombatWK.tank(w, 0, 29, 27)
	CombatWK.run(w, 5)
	SimDamage.deal(w, v, wh, 10, SimCombatConsts.DC_DIRECT, 0, x.id, 1, true, 10000, 0, 10000, 0, 0, v.x, v.y)
	SimDamage.flush(w)
	t.eq(late.combat.target_id, -1, "no re-assist within ASSIST_COOLDOWN")
	CombatWK.run(w, SimCombatConsts.ASSIST_COOLDOWN)
	SimDamage.deal(w, v, wh, 10, SimCombatConsts.DC_DIRECT, 0, x.id, 1, true, 10000, 0, 10000, 0, 0, v.x, v.y)
	SimDamage.flush(w)
	t.eq(late.combat.target_id, x.id, "after the cooldown it does")


func test_retaliation_rules(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var v: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var x: SimEntity = _quiet(CombatWK.tank(w, 1, 44, 30))
	var wh: SimCombatWarhead = CombatKit.wh(10, SimCombatConsts.DT_BULLET)
	# an ordered target is never replaced
	var keep: SimEntity = _quiet(CombatWK.tank(w, 1, 44, 33))
	w.combat.set_target(w, v, keep.id, SimCombatConsts.TS_ORDER)
	SimTargeting.on_damaged(w, v, x.id)
	t.eq(v.combat.target_id, keep.id, "TS_ORDER is never replaced by retaliation")
	# hold fire units do not retaliate
	SimTargeting.clear_target(v)
	v.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	SimTargeting.on_damaged(w, v, x.id)
	t.eq(v.combat.target_id, -1, "hold fire: no retaliation")
	v.combat.stance = SimCombatConsts.ST_AGGRESSIVE
	# an auto target that scores nearly as well stays; a much worse one is replaced
	var near: SimEntity = _quiet(CombatWK.tank(w, 1, 36, 30))
	w.combat.set_target(w, v, near.id, SimCombatConsts.TS_AUTO)
	SimTargeting.on_damaged(w, v, x.id)
	t.eq(v.combat.target_id, near.id, "current auto target scores at least as well: keep")
	var junk: SimEntity = _quiet(CombatWK.rifle(w, 1, 36, 31))
	CombatWK.cd(w, junk).prio = 1
	SimTargeting.clear_target(v)
	w.combat.set_target(w, v, junk.id, SimCombatConsts.TS_AUTO)
	SimTargeting.on_damaged(w, v, x.id)
	t.eq([v.combat.target_id, v.combat.target_src], [x.id, SimCombatConsts.TS_RETAL], "much worse auto target: switch to the attacker")
	# hidden attackers are not retaliated against
	var fog: CombatWK.HideFog = CombatWK.HideFog.new()
	fog.hidden.append(x.id)
	w.fog = fog
	SimTargeting.clear_target(v)
	SimTargeting.on_damaged(w, v, x.id)
	t.eq(v.combat.target_id, -1, "an attacker the victim cannot see is ignored")
	t.check(wh != null, "warhead helper")


# ---------------------------------------------------------------------------------------------- scan scheduling
func test_scan_schedule_and_intervals(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var tur: SimEntity = CombatWK.turret(w, 0, 40, 40)
	t.eq(tk.combat.scan_next, w.tick + tk.id % SimCombatConsts.SCAN_INTERVAL_UNIT, "units stagger by id over 6 ticks")
	t.eq(tur.combat.scan_next, w.tick + tur.id % SimCombatConsts.SCAN_INTERVAL_STRUCT, "structures over 8")
	tk.combat.scan_next = 0
	tur.combat.scan_next = 0
	_scan(w, tk)
	_scan(w, tur)
	t.eq(tk.combat.scan_next, w.tick + SimCombatConsts.SCAN_INTERVAL_UNIT, "unit interval 6")
	t.eq(tur.combat.scan_next, w.tick + SimCombatConsts.SCAN_INTERVAL_STRUCT, "structure interval 8")


func test_scan_rotation_reaches_everyone(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var n: int = 200
	var all: Array[SimEntity] = []
	for i: int in n:
		all.append(CombatWK.rifle(w, i % 2, 2 + (i % 40) * 2, 2 + (i / 40) * 2))
	var cs: SimCombatSystem = w.combat
	for e: SimEntity in all:
		e.combat.scan_next = w.tick  # everybody due
	var budget: int = SimCombatConsts.SCAN_BUDGET_BASE + 4 * (cs.armed_ids.size() / 64)
	var rounds: int = Fp.ceil_div(cs.armed_ids.size(), budget)
	var before: int = cs.counters[SimCombatSystem.CNT_SCANS]
	SimTargeting.run_scans(w, cs)
	t.eq(cs.counters[SimCombatSystem.CNT_SCANS] - before, budget, "one pass spends exactly the budget")
	for _r: int in rounds - 1:
		SimTargeting.run_scans(w, cs)
	var starved: int = 0
	for e: SimEntity in all:
		if e.combat.scan_next <= w.tick:
			starved += 1
	t.eq(starved, 0, "every due entity is scanned within ceil(n / budget) = %d passes" % rounds)
	t.eq(cs.counters[SimCombatSystem.CNT_SCANS] - before, cs.armed_ids.size(), "each entity scanned exactly once in the rotation")
	# next tick nobody is due yet (intervals >= 4)
	var c2: int = cs.counters[SimCombatSystem.CNT_SCANS]
	SimTargeting.run_scans(w, cs)
	t.eq(cs.counters[SimCombatSystem.CNT_SCANS], c2, "scanned entities are not due again")


func test_urgent_scan_budget(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var b: SimEntity = _quiet(CombatWK.tank(w, 1, 34, 30))
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_AUTO)
	var c: SimEntity = _quiet(CombatWK.tank(w, 1, 30, 34))
	w.kill(b, SimWorld.Cause.SCRIPT)
	w.step()
	t.eq(a.combat.target_id, c.id, "target lost: an urgent rescan picks the next one in the same tick")


# ---------------------------------------------------------------------------------------------- stances / validation
func test_stances_acquisition_range(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var foe: SimEntity = _quiet(CombatWK.tank(w, 1, 30, 30))
	var range_u: int = w.combat.range_max_eff(w, a)
	# d_eff = range + 1000: only aggressive (range + 2048) reaches
	w.set_pos(foe, a.x + range_u + 1000 + foe.radius, a.y, true)
	a.combat.stance = SimCombatConsts.ST_DEFENSIVE
	_scan(w, a)
	t.eq(a.combat.target_id, -1, "defensive: only targets within range")
	a.combat.stance = SimCombatConsts.ST_AGGRESSIVE
	_scan(w, a)
	t.eq(a.combat.target_id, foe.id, "aggressive: range + 2048")
	SimTargeting.clear_target(a)
	a.combat.hold_pos = 1
	_scan(w, a)
	t.eq(a.combat.target_id, -1, "hold position: range only")
	a.combat.hold_pos = 0
	w.set_pos(foe, a.x + range_u + 3000 + foe.radius, a.y, true)
	a.combat.stance = SimCombatConsts.ST_AGGRESSIVE
	_scan(w, a)
	t.eq(a.combat.target_id, -1, "aggressive: nothing beyond range + 2048")
	a.combat.stance = SimCombatConsts.ST_GUARD
	_scan(w, a)
	t.eq(a.combat.target_id, foe.id, "guard: R_acq >= GUARD_RADIUS")
	# structures never look beyond their range
	var tw: SimEntity = CombatWK.turret(w, 0, 60, 60)
	var tr_range: int = w.combat.range_max_eff(w, tw)
	var foe2: SimEntity = _quiet(CombatWK.tank(w, 1, 60, 60))
	w.set_pos(foe2, tw.x + tr_range + 1000 + foe2.radius, tw.y, true)
	tw.flags |= SimFlags.F_POWERED
	_scan(w, tw)
	t.eq(tw.combat.target_id, -1, "structure: no acquisition beyond range")
	w.set_pos(foe2, tw.x + tr_range - 500, tw.y, true)
	_scan(w, tw)
	t.eq(tw.combat.target_id, foe2.id, "structure: acquires inside range")


func test_validation_hidden_and_leash(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var foe: SimEntity = _quiet(CombatWK.tank(w, 1, 34, 30))
	a.combat.scan_next = 100000
	var fog: CombatWK.HideFog = CombatWK.HideFog.new()
	w.fog = fog
	w.combat.set_target(w, a, foe.id, SimCombatConsts.TS_AUTO)
	fog.hidden.append(foe.id)
	CombatWK.run(w, SimCombatConsts.HIDE_GIVEUP_AUTO)
	t.eq(a.combat.target_id, foe.id, "hidden target kept inside the give-up window")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_FIRE).size(), 0, "and not shot at while hidden")
	CombatWK.run(w, 3)
	t.eq(a.combat.target_id, -1, "auto target given up after HIDE_GIVEUP_AUTO ticks")
	# ordered targets are remembered longer
	w.combat.set_target(w, a, foe.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w, SimCombatConsts.HIDE_GIVEUP_ORDER - 2)
	t.eq(a.combat.target_id, foe.id, "orders wait")
	CombatWK.run(w, 6)
	t.eq(a.combat.target_id, -1, "then give up (HIDE_GIVEUP_ORDER)")
	fog.hidden.clear()
	# leash
	w.combat.set_target(w, a, foe.id, SimCombatConsts.TS_AUTO)
	a.combat.anchor_on = 1
	a.combat.anchor_x = a.x - 20000
	a.combat.anchor_y = a.y
	CombatWK.run(w, 1)
	t.eq(a.combat.target_id, -1, "auto target outside leash + range of the anchor is dropped")
	w.combat.set_target(w, a, foe.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w, 1)
	t.eq(a.combat.target_id, foe.id, "orders ignore the leash")
	# dead target is dropped and hold_pos leash is 0
	SimTargeting.clear_target(a)
	a.combat.anchor_x = a.x - 4000
	a.combat.hold_pos = 1
	w.combat.set_target(w, a, foe.id, SimCombatConsts.TS_AUTO)
	CombatWK.run(w, 1)
	t.eq(a.combat.target_id, -1, "hold position: leash 0, only targets inside weapon range of the anchor")


func test_set_ground_and_clear(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	a.combat.mnt[SimCombatConsts.M_BURST] = 2
	a.combat.mnt[SimCombatConsts.M_NEXT] = 9
	w.combat.set_ground_target(a, 40000, 31000)
	t.eq([a.combat.ground_on, a.combat.ground_x, a.combat.ground_y, a.combat.target_src], [1, 40000, 31000, SimCombatConsts.TS_FORCE], "ground point")
	w.combat.clear_target(a, true)
	t.eq(a.combat.ground_on, 0, "keep_auto still clears forced / ordered targets")
	a.combat.target_id = 5
	a.combat.target_src = SimCombatConsts.TS_AUTO
	a.combat.ground_on = 0
	w.combat.clear_target(a, true)
	t.eq(a.combat.target_id, 5, "keep_auto keeps auto targets")
	w.combat.clear_target(a)
	t.eq([a.combat.target_id, a.combat.ground_on, a.combat.mnt[SimCombatConsts.M_BURST]], [-1, 0, 0], "clear drops target and salvo remainder")
	t.check(a.combat.mnt[SimCombatConsts.M_CD] >= 9, "the abandoned salvo still owes its cooldown")


# ---------------------------------------------------------------------------------------------- independent mounts
func test_independent_aa_mount(t: TestCtx) -> void:
	var w: SimWorld = _world()
	CombatWK.add_weapon(w, DefTestKit.U_TANK, DefEnums.WeaponArch.AA_MISSILE, 40, 20000, 7168, 1)
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	t.eq(a.combat.n_mounts, 2, "two mounts")
	var c: SimCombatDef = CombatWK.cd(w, a)
	t.eq([c.mount_val(0, SimCombatDef.MT_INDEP), c.mount_val(1, SimCombatDef.MT_INDEP)], [0, 1], "the AA mount is independent")
	var g: SimEntity = _quiet(CombatWK.tank(w, 1, 34, 30))
	var sky: SimEntity = _quiet(CombatWK.tank(w, 1, 34, 33))
	w.set_layer(sky, SimCombatConsts.LAYER_AIR)
	CombatWK.set_matrix_all(w, 10000)
	_scan(w, a)
	t.eq(a.combat.target_id, g.id, "primary mount takes the ground target")
	t.eq(a.combat.mnt[1 * SimCombatConsts.MS + SimCombatConsts.M_TARGET], sky.id, "the AA mount holds its own air target")
	CombatWK.run(w, 60)
	var mounts_fired: Dictionary = {}
	for r: PackedInt32Array in CombatWK.evs(w, SimCombatConsts.EV_FIRE):
		if r[SimEvent.I_A] == a.id:
			mounts_fired[r[SimEvent.I_C] & 15] = r[SimEvent.I_D]
	t.eq(mounts_fired.get(0, -2), g.id, "cannon fires at the ground unit")
	t.eq(mounts_fired.get(1, -2), sky.id, "AA fires at the aircraft at the same time")
	t.lt(sky.hp, 100000, "the aircraft was hit")


func test_player_elimination_clears_targets(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var b: SimEntity = _quiet(CombatWK.tank(w, 1, 34, 30))
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	w.combat.on_player_eliminated(w, 1)
	t.eq([a.combat.target_id, a.combat.target_src], [-1, SimCombatConsts.TS_NONE], "targets of the eliminated player are dropped")
	t.eq(a.combat.scan_next, w.tick, "and a rescan is requested")
