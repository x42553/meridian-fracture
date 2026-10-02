extends RefCounted
## CB-03: mount aim / slew, firing gates, salvo / reload / ammo, hitscan, beams, muzzle geometry, S-1 mirror duel
## and a determinism double run.


func _pair(dist_cells: int = 4) -> Array:
	var w: SimWorld = CombatWK.world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var b: SimEntity = CombatWK.tank(w, 1, 30 + dist_cells, 30)
	b.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	return [w, a, b]


func _fire_ticks(w: SimWorld, shooter: SimEntity) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for r: PackedInt32Array in CombatWK.evs(w, SimCombatConsts.EV_FIRE):
		if r[SimEvent.I_A] == shooter.id:
			out.append(r[SimEvent.I_TICK])
	return out


# ---------------------------------------------------------------------------------------------- geometry
func test_geom_1_wrap_signed(t: TestCtx) -> void:
	t.eq([SimCombatConsts.wrap_signed(2048), SimCombatConsts.wrap_signed(4095), SimCombatConsts.wrap_signed(-1), SimCombatConsts.wrap_signed(0)],
		[-2048, -1, -1, 0], "U-GEOM-1")


func test_geom_2_slew_vector(t: TestCtx) -> void:
	var cur: int = 0
	var aimed_at: int = -1
	var reached_at: int = -1
	for k: int in range(1, 140):
		cur = SimWeapons.aim_step(cur, 1024, 8)
		if aimed_at < 0 and absi(SimCombatConsts.wrap_signed(1024 - cur)) <= 24:
			aimed_at = k
		if reached_at < 0 and cur == 1024:
			reached_at = k
	t.eq(aimed_at, 125, "aimed from tick 125")
	t.eq(reached_at, 128, "cur == goal at tick 128, not 127")
	t.eq(SimWeapons.slew_ticks(1024, 8), 128, "slew time 90 degrees at 8 bat/tick")
	t.eq(SimWeapons.aim_step(10, 4090, 8), 2, "shortest way around the circle")


func test_geom_2_slew_in_world(t: TestCtx) -> void:
	var w: SimWorld = CombatWK.world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var b: SimEntity = CombatWK.tank(w, 1, 30, 34)  # due +y = bearing 1024
	b.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	CombatWK.mt_set(w, a, 0, {SimCombatDef.MT_TURN: 8, SimCombatDef.MT_ARC_HALF: 2048})
	t.check(w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER), "order accepted")
	var first_aimed: int = -1
	for n: int in range(1, 131):
		w.step()
		var ang: int = a.combat.mnt[SimCombatConsts.M_ANGLE]
		if n in [1, 60, 124, 125, 127, 128, 130]:
			t.eq(ang, mini(8 * n, 1024), "angle after step %d" % n)
		if first_aimed < 0 and a.combat.mnt[SimCombatConsts.M_AIM_SINCE] >= 0:
			first_aimed = n
	t.eq(first_aimed, 125, "aimed continuously from step 125")
	var fires: PackedInt32Array = _fire_ticks(w, a)
	t.check(not fires.is_empty() and fires[0] == 124, "first shot on the aimed step (tick 124), got %s" % str(fires))


func test_arc_limits(t: TestCtx) -> void:
	# narrow +-30 degree fixed arc: a target 90 degrees off is never in arc, so it never fires
	var s: Array = _pair()
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.mt_set(w, a, 0, {SimCombatDef.MT_ARC_HALF: 341, SimCombatDef.MT_TURN: 20})
	a.facing = 1024  # b is due east = 90 degrees off the hull
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w, 60)
	t.eq(_fire_ticks(w, a).size(), 0, "outside the firing arc: no shot")
	t.check(absi(SimCombatConsts.wrap_signed(a.combat.mnt[SimCombatConsts.M_ANGLE] - 3755)) <= 20 or a.combat.mnt[SimCombatConsts.M_ANGLE] == 341 or a.combat.mnt[SimCombatConsts.M_ANGLE] == 3755,
		"turret pinned at the arc edge (angle %d)" % a.combat.mnt[SimCombatConsts.M_ANGLE])
	a.facing = 0  # now dead ahead
	CombatWK.run(w, 60)
	t.gt(_fire_ticks(w, a).size(), 0, "in arc again: fires")


func test_muzzle_geometry(t: TestCtx) -> void:
	var w: SimWorld = CombatWK.world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var c: SimCombatDef = CombatWK.cd(w, a)
	CombatWK.mt_set(w, a, 0, {SimCombatDef.MT_OFF_FWD: 512, SimCombatDef.MT_OFF_SIDE: 256})
	a.facing = 1024
	t.eq([SimWeapons.muzzle_x(a, c, 0, 0) - a.x, SimWeapons.muzzle_y(a, c, 0, 0) - a.y], [-256, 512], "hull facing 1024: forward is +y, right is -x")
	a.facing = 0
	t.eq([SimWeapons.muzzle_x(a, c, 0, 1024) - a.x, SimWeapons.muzzle_y(a, c, 0, 1024) - a.y], [-256, 512], "turret angle adds to the hull facing")
	CombatWK.mt_set(w, a, 0, {SimCombatDef.MT_KIND: SimCombatConsts.MK_HULL})
	t.eq([SimWeapons.muzzle_x(a, c, 0, 1024) - a.x, SimWeapons.muzzle_y(a, c, 0, 1024) - a.y], [512, 256], "hull mounts ignore the turret angle")


# ---------------------------------------------------------------------------------------------- reload / hitscan
func test_rel_1_reload_vectors(t: TestCtx) -> void:
	t.eq([SimWeapons.reload_eff(92, 80, 0), SimWeapons.reload_eff(92, 80, -1000), SimWeapons.reload_eff(18, 20, -4000), SimWeapons.reload_eff(18, 20, -7000)],
		[92, 83, 11, 10], "U-REL-1")


func test_hit_chance_vector(t: TestCtx) -> void:
	t.eq(SimWeapons.hit_chance_bp(8000, 3000, 1500, 1000, 3840, 5632, 30, 256, false, false), 5643, "worked example of 5.4.1: 56.4 %")
	t.eq(SimWeapons.hit_chance_bp(8000, 3000, 1500, 1000, 3840, 5632, 30, 256, false, true), 10000, "structures are always hit")
	t.eq(SimWeapons.hit_chance_bp(1000, 9000, 9000, 9000, 5000, 5000, 99, 0, true, false), SimCombatConsts.ACC_MIN_BP, "floor 10 %")
	t.eq(SimWeapons.hit_chance_bp(8000, 3000, 1500, 1000, 0, 5000, 0, 0, true, false), 7000, "shooter penalty while moving")


func test_hitscan_shot_and_events(t: TestCtx) -> void:
	var s: Array = _pair()
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.set_matrix_all(w, 10000)
	CombatWK.make_hitscan(w, a, 40, 20, 7168)
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	var hp0: int = b.hp
	w.step()
	var expect: int = CombatKit.compute(w, b, CombatWK.wh_of(w, a, 0), 40)
	t.eq(hp0 - b.hp, expect, "one hitscan shot hits for the pipeline damage")
	var f: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_FIRE)
	t.eq(f.size(), 1, "one EV_FIRE")
	var c: int = f[0][SimEvent.I_C]
	t.eq([c & 15, (c >> 8) & 15, (c >> 12) & 15], [0, SimCombatConsts.PK_HITSCAN, 1], "mount 0, hitscan, result 1 (hit)")
	t.eq([f[0][SimEvent.I_D], f[0][SimEvent.I_E], f[0][SimEvent.I_F]], [b.id, b.x, b.y], "target id and impact point")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_IMPACT).size(), 0, "splash-less hitscan hits emit no EV_IMPACT")
	t.eq(a.combat.last_fire_tick, 0, "last_fire_tick")
	t.check((a.flags & SimFlags.F_FIRING) != 0, "F_FIRING set on the shot tick")
	w.step()
	t.check((a.flags & SimFlags.F_FIRING) == 0, "F_FIRING cleared next tick")


func test_hitscan_miss_draws_and_displaces(t: TestCtx) -> void:
	var s: Array = _pair()
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.make_hitscan(w, a, 40, 20, 7168)
	CombatWK.prof_set(w, a, 0, {SimWeaponProfile.PF_ACC: 1000, SimWeaponProfile.PF_ACC_FALL: 0, SimWeaponProfile.PF_ACC_MOVE: 0, SimWeaponProfile.PF_ACC_SHOOTER: 0})
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	var hits: int = 0
	var misses: int = 0
	for _i: int in 200:
		w.step()
	for r: PackedInt32Array in CombatWK.evs(w, SimCombatConsts.EV_FIRE):
		var res: int = (r[SimEvent.I_C] >> 12) & 15
		if res == 1:
			hits += 1
		else:
			misses += 1
			var dx: int = r[SimEvent.I_E] - b.x
			var dy: int = r[SimEvent.I_F] - b.y
			t.check(Fp.dist(dx, dy) >= 200, "a miss lands away from the target")
	t.check(misses > hits, "10 %% + size bonus: mostly misses (%d/%d)" % [hits, misses])
	t.gt(hits, 0, "some hits")


# ---------------------------------------------------------------------------------------------- salvo / ammo / gates
func test_salvo_reload_ammo(t: TestCtx) -> void:
	var s: Array = _pair()
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.make_hitscan(w, a, 5, 30, 7168)
	CombatWK.prof_set(w, a, 0, {SimWeaponProfile.PF_BURST: 3, SimWeaponProfile.PF_BURST_INT: 3})
	a.combat.mnt[SimCombatConsts.M_AMMO] = 2
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w, 120)
	t.eq(Array(_fire_ticks(w, a)), [0, 3, 6, 30, 33, 36], "two salvos of 3, reload counted from the salvo start, then out of ammo")
	t.eq(w.combat.ammo_of(a, 0), 0, "ammo used per salvo")


func test_salvo_aborts_when_gates_fail(t: TestCtx) -> void:
	var s: Array = _pair()
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.make_hitscan(w, a, 5, 30, 7168)
	CombatWK.prof_set(w, a, 0, {SimWeaponProfile.PF_BURST: 4, SimWeaponProfile.PF_BURST_INT: 3})
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	w.step()  # shot 0
	a.combat.wlock_until = 1000  # weapons lock mid-salvo
	CombatWK.run(w, 3 + 2 * 3 + 4)
	t.eq(a.combat.mnt[SimCombatConsts.M_BURST], 0, "salvo aborted after 2 * interval + 2 failed ticks")
	t.gt(a.combat.mnt[SimCombatConsts.M_CD], w.tick, "abort starts a half reload")
	t.eq(_fire_ticks(w, a).size(), 1, "only shot 0 fired")


func test_gates_offline_range_min_stance_settle(t: TestCtx) -> void:
	var s: Array = _pair(4)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.make_hitscan(w, a, 5, 10, 7168)
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	a.combat.wlock_until = 20
	CombatWK.run(w, 20)
	t.eq(_fire_ticks(w, a).size(), 0, "weapon lock: offline")
	CombatWK.run(w, 5)
	t.gt(_fire_ticks(w, a).size(), 0, "fires once online")
	# stance: auto target + hold fire = silent, order = fires
	var s2: Array = _pair(4)
	var w2: SimWorld = s2[0]
	var a2: SimEntity = s2[1]
	var b2: SimEntity = s2[2]
	CombatWK.make_hitscan(w2, a2, 5, 10, 7168)
	a2.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	w2.combat.set_target(w2, a2, b2.id, SimCombatConsts.TS_RETAL)
	CombatWK.run(w2, 30)
	t.eq(_fire_ticks(w2, a2).size(), 0, "TS_RETAL under hold fire: no shot")
	w2.combat.set_target(w2, a2, b2.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w2, 30)
	t.gt(_fire_ticks(w2, a2).size(), 0, "TS_ORDER fires under hold fire")
	# min range
	var s3: Array = _pair(3)
	var w3: SimWorld = s3[0]
	var a3: SimEntity = s3[1]
	var b3: SimEntity = s3[2]
	CombatWK.make_hitscan(w3, a3, 5, 10, 7168)
	CombatWK.slot_set(w3, DefTestKit.U_TANK, 0, {"min_range": 6000})
	w3.combat.set_target(w3, a3, b3.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w3, 30)
	t.eq(_fire_ticks(w3, a3).size(), 0, "inside the minimum range")
	# out of range
	var s4: Array = _pair(12)
	var w4: SimWorld = s4[0]
	var a4: SimEntity = s4[1]
	var b4: SimEntity = s4[2]
	CombatWK.make_hitscan(w4, a4, 5, 10, 7168)
	w4.combat.set_target(w4, a4, b4.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w4, 30)
	t.eq(_fire_ticks(w4, a4).size(), 0, "out of range")
	# stationary fire needs settle ticks and no movement
	var s5: Array = _pair(4)
	var w5: SimWorld = s5[0]
	var a5: SimEntity = s5[1]
	var b5: SimEntity = s5[2]
	CombatWK.make_hitscan(w5, a5, 5, 10, 7168)
	CombatWK.prof_set(w5, a5, 0, {SimWeaponProfile.PF_SETTLE: 6})
	w5.combat.set_target(w5, a5, b5.id, SimCombatConsts.TS_ORDER)
	a5.combat.ext_moving = 1
	CombatWK.run(w5, 10)
	t.eq(_fire_ticks(w5, a5).size(), 0, "moving: a stationary-fire weapon holds")
	a5.combat.ext_moving = 0
	CombatWK.run(w5, 10)
	var ft: PackedInt32Array = _fire_ticks(w5, a5)
	t.check(not ft.is_empty() and ft[0] == 15, "fires when still_ticks reached the settle time (tick 15), got %s" % str(ft))


func test_state_requests(t: TestCtx) -> void:
	var s: Array = _pair(4)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.make_hitscan(w, a, 5, 10, 7168)
	CombatWK.mt_set(w, a, 0, {SimCombatDef.MT_REQ_DEPLOYED: 1})
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	w.step()
	t.eq(a.combat.want_deploy, 1, "deploy-only weapon with a target in reach asks for deployment")
	t.eq(_fire_ticks(w, a).size(), 0, "and does not fire undeployed")
	a.combat.ext_deployed = 1
	CombatWK.run(w, 3)
	t.gt(_fire_ticks(w, a).size(), 0, "deployed: fires")
	t.eq(a.combat.want_deploy, -1, "request cleared")
	# surface request
	var s2: Array = _pair(4)
	var w2: SimWorld = s2[0]
	var a2: SimEntity = s2[1]
	var b2: SimEntity = s2[2]
	CombatWK.make_hitscan(w2, a2, 5, 10, 7168)
	CombatWK.slot_set(w2, DefTestKit.U_TANK, 0, {"requires_surface_t": 160})
	w2.combat.set_target(w2, a2, b2.id, SimCombatConsts.TS_ORDER)
	w2.step()
	t.eq(a2.combat.want_surface, 1, "surface-only weapon asks to surface")
	# mode: a mount of another mode can engage -> want_mode
	var s3: Array = _pair(4)
	var w3: SimWorld = s3[0]
	var a3: SimEntity = s3[1]
	var b3: SimEntity = s3[2]
	CombatWK.mt_set(w3, a3, 0, {SimCombatDef.MT_MODE_MASK: 2})  # only active in mode 1
	w3.combat.set_target(w3, a3, b3.id, SimCombatConsts.TS_ORDER)
	w3.step()
	t.eq(a3.combat.want_mode, 1, "no active-mode weapon reaches: request the mode that has one")


# ---------------------------------------------------------------------------------------------- beams
func _beam_setup() -> Array:
	var s: Array = _pair()
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.set_matrix_all(w, 10000)
	CombatWK.set_hp(b, 100000)
	CombatWK.slot_set(w, DefTestKit.U_TANK, 0, {"damage": 50, "reload_mt": 5000, "range": 7168, "ramp_t": 100, "ramp_max_bp": 15000, "splash_radius": 0})
	CombatWK.prof_set(w, a, 0, {SimWeaponProfile.PF_KIND: SimCombatConsts.PK_BEAM, SimWeaponProfile.PF_BURST: 1})
	CombatWK.wh_of(w, a, 0).splash_r = 0
	return s


func test_beam_ramp_vectors(t: TestCtx) -> void:
	t.eq([SimWeapons.beam_ramp_bp(0, 100, 15000), SimWeapons.beam_ramp_bp(50, 100, 15000), SimWeapons.beam_ramp_bp(100, 100, 15000), SimWeapons.beam_ramp_bp(500, 100, 15000)],
		[10000, 12500, 15000, 15000], "linear ramp then plateau")
	t.eq(SimWeapons.beam_ramp_bp(30, 0, 15000), 10000, "no ramp data: flat")


func test_beam_ramps_and_overheats(t: TestCtx) -> void:
	var s: Array = _beam_setup()
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.prof_set(w, a, 0, {SimWeaponProfile.PF_BEAM_MAX: 120})
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	var dots: Array = []
	var prev: int = b.hp
	for _i: int in 130:
		w.step()
		if b.hp != prev:
			dots.append([w.tick - 1, prev - b.hp])
			prev = b.hp
	t.eq(dots[0], [5, SimDamage.mul(50, 10250)], "first dot after beam_dot ticks at ramp 102.5 %")
	var at50: Array = []
	var at100: Array = []
	for d: Array in dots:
		if d[0] == 50:
			at50 = d
		if d[0] == 100:
			at100 = d
	t.eq(at50, [50, SimDamage.mul(50, 12500)], "half ramp")
	t.eq(at100, [100, 75], "full ramp: 150 %")
	var st: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_BEAM_START)
	var en: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_BEAM_END)
	t.eq(st[0][SimEvent.I_TICK], 0, "beam starts on the first aimed tick")
	t.eq([en[0][SimEvent.I_TICK], en[0][SimEvent.I_B]], [120, SimWeapons.BR_OVERHEAT], "overheat after beam_max ticks; reload doubles as cooling")
	t.eq(st[1][SimEvent.I_TICK], 125, "restarts after the cooling interval (reload 5) with a fresh ramp")
	# beams are hitscan-like: no projectile involved
	t.eq(w.combat.proj.live_count(), 0, "beams are not projectiles")


func test_beam_ends_on_target_change_and_loss(t: TestCtx) -> void:
	var s: Array = _beam_setup()
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	var c: SimEntity = CombatWK.tank(w, 1, 30, 27)
	c.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	CombatWK.set_hp(c, 100000)
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w, 12)
	w.combat.set_target(w, a, c.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w, 3)
	var en: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_BEAM_END)
	t.check(not en.is_empty() and en[0][SimEvent.I_B] == SimWeapons.BR_ORDER, "changing targets ends the beam (reason 4)")
	# target dies: reason 3 or 0, never keeps running
	var s2: Array = _beam_setup()
	var w2: SimWorld = s2[0]
	var a2: SimEntity = s2[1]
	var b2: SimEntity = s2[2]
	w2.combat.set_target(w2, a2, b2.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w2, 8)
	w2.kill(b2, SimWorld.Cause.SCRIPT)
	CombatWK.run(w2, 4)
	t.check(a2.combat.mnt[SimCombatConsts.M_BEAM] < 0, "beam off after the target died")
	t.gt(CombatWK.evs(w2, SimCombatConsts.EV_BEAM_END).size(), 0, "EV_BEAM_END emitted")


# ---------------------------------------------------------------------------------------------- S-1
func test_s1_guardian_mirror(t: TestCtx) -> void:
	var w: SimWorld = CombatWK.world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var b: SimEntity = CombatWK.tank(w, 1, 34, 30)
	b.facing = 2048
	CombatWK.set_matrix_all(w, 10000)
	CombatWK.slot_set(w, DefTestKit.U_TANK, 0, {"damage": 60, "reload_mt": 30000, "range": 7168})
	var d0: int = CombatKit.compute(w, b, CombatWK.wh_of(w, a, 0), 60)
	t.gt(d0, 0, "hit damage")
	CombatWK.set_hp(a, 15 * d0)
	CombatWK.set_hp(b, 15 * d0)
	t.check(w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER) and w.combat.set_target(w, b, a.id, SimCombatConsts.TS_ORDER), "orders")
	var dead_a: int = -1
	var dead_b: int = -1
	for n: int in range(1, 520):
		w.step()
		if dead_a < 0 and CombatWK.dead(a):
			dead_a = n
		if dead_b < 0 and CombatWK.dead(b):
			dead_b = n
		if dead_a >= 0 and dead_b >= 0:
			break
	t.check(dead_a > 0 and dead_a == dead_b, "identical stats and start ticks: both die in the same tick (%d / %d)" % [dead_a, dead_b])
	t.check(dead_a >= 14 * 30 + 1 and dead_a <= 14 * 30 + 1 + 8, "15th shot at t0 + 14 * 30, death a few ticks of flight later (%d)" % dead_a)
	t.eq([_fire_ticks(w, a).size(), _fire_ticks(w, b).size()], [15, 15], "exactly 15 shots each")


# ---------------------------------------------------------------------------------------------- idle turret
func test_idle_turret_returns_at_half_rate(t: TestCtx) -> void:
	var w: SimWorld = CombatWK.world()
	var a: SimEntity = CombatWK.tank(w, 0, 30, 30)
	CombatWK.mt_set(w, a, 0, {SimCombatDef.MT_TURN: 8})
	a.combat.mnt[SimCombatConsts.M_ANGLE] = 400
	CombatWK.run(w, SimCombatConsts.TURRET_IDLE_RETURN - 1)
	t.eq(a.combat.mnt[SimCombatConsts.M_ANGLE], 400, "holds its heading for TURRET_IDLE_RETURN ticks")
	CombatWK.run(w, 10)
	var ang: int = a.combat.mnt[SimCombatConsts.M_ANGLE]
	t.lt(ang, 400, "then swings back")
	t.eq((400 - ang) % 4, 0, "at half the traverse rate (4 bat/tick)")
	CombatWK.run(w, 120)
	t.eq(a.combat.mnt[SimCombatConsts.M_ANGLE], 0, "centred")


# ---------------------------------------------------------------------------------------------- determinism
func _brawl_world() -> SimWorld:
	var w: SimWorld = CombatWK.world()
	for i: int in 4:
		CombatWK.tank(w, 0, 26 + i, 30)
		CombatWK.rifle(w, 0, 26 + i, 32)
		CombatWK.tank(w, 1, 31 + i, 30)
		CombatWK.rifle(w, 1, 31 + i, 32)
	return w


func test_determinism_double_run(t: TestCtx) -> void:
	var res: Dictionary = SimTestKit.double_run(_brawl_world, Callable(), 260)
	t.check(bool(res["ok"]), "two identical worlds hash identically at every checkpoint")
	var w: SimWorld = _brawl_world()
	SimTestKit.run_script(w, 260)
	t.gt(CombatWK.evs(w, SimCombatConsts.EV_FIRE).size(), 20, "the brawl actually fires")
	t.gt(w.players[0].st_damage_dealt + w.players[1].st_damage_dealt, 0, "and deals damage")
