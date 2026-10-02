extends RefCounted
## CB-08: aircraft sortie machine on the REAL movement / orders / combat systems: U-AIR-1..4, S-3 (bomber vs AA), the
## hover style, patrol and return-to-base orders.

const C: int = SimConfig.CELL
const S := preload("res://src/sim/combat/sim_combat_consts.gd")


func _quiet(e: SimEntity, hp: int = 100000) -> SimEntity:
	e.combat.stance = S.ST_HOLD_FIRE
	CombatWK.set_hp(e, hp)
	return e


func _rifle(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return CombatWK.rifle(w, owner, cx, cy)


func _has_in_order(seq: PackedInt32Array, want: Array) -> bool:
	var at: int = 0
	for s: int in seq:
		if at < want.size() and s == int(want[at]):
			at += 1
	return at == want.size()


func _run_until(w: SimWorld, pred: Callable, max_ticks: int) -> int:
	for i: int in max_ticks:
		w.step()
		if pred.call():
			return i + 1
	return -1


# ---------------------------------------------------------------------------------------------- U-AIR-1
func test_air_1_full_sortie_and_rearm(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("bomber", 2, 460, 1)
	var af: SimEntity = CombatAirKit.airfield(w, 0, 20, 40)
	var ac: SimEntity = CombatAirKit.parked(w, af)
	t.eq([ac.air.state, ac.layer, ac.air.pad, ac.air.home_id], [S.AIR_PARKED, S.LAYER_GROUND, 0, af.id], "parked on pad 0, ground layer")
	t.eq(af.air.pad_occ, PackedInt32Array([ac.id, -1]), "the pad is taken")
	var foe: SimEntity = _quiet(_rifle(w, 1, 55, 40), 300)
	var hp0: int = foe.hp
	w.submit_raw(0, SimCmd.attack([ac.id], foe.id))
	w.run(3)
	t.eq(ac.air.state, S.AIR_TAKEOFF, "an attack order scrambles the parked aircraft")
	t.eq(af.air.pad_occ[0], -1, "the pad is released at take-off")
	var done: int = _run_until(w, func() -> bool: return ac.air.state == S.AIR_PARKED and ac.orders.is_empty() and w.tick > 20, 3000)
	t.gt(done, 0, "the sortie ended parked (%d ticks)" % done)
	var seq: PackedInt32Array = CombatAirKit.states(w, ac)
	t.check(_has_in_order(seq, [S.AIR_PARKED, S.AIR_TAKEOFF, S.AIR_TRANSIT, S.AIR_ATTACK, S.AIR_RETURN, S.AIR_LANDING, S.AIR_REARM, S.AIR_PARKED]),
		"PARKED -> TAKEOFF -> TRANSIT -> ATTACK -> RETURN -> LANDING -> REARM -> PARKED (%s)" % str(seq))
	t.lt(foe.hp, hp0, "the stick landed on the target")
	var r0: int = CombatAirKit.tick_of(w, ac, S.AIR_REARM)
	var p1: int = CombatAirKit.tick_of(w, ac, S.AIR_PARKED, r0)
	t.eq(p1 - r0, 240, "rearm from empty takes exactly rearm_ticks")
	t.eq([ac.combat.mnt[S.M_AMMO], ac.air.fuel, ac.layer], [1, CombatWK.cd(w, ac).fuel_max, S.LAYER_GROUND], "ammo and fuel restored, on the ground")
	t.eq([ac.air.pad, af.air.pad_occ[ac.air.pad]], [0, ac.id], "back on a pad of its airfield")
	t.eq(ac.orders.size(), 0, "the order ended when the aircraft landed with nothing to resume")


func test_air_1_unpowered_or_emp_airfield_does_not_rearm(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("bomber", 2, 460, 1)
	var af: SimEntity = CombatAirKit.airfield(w, 0, 20, 40)
	var ac: SimEntity = CombatAirKit.parked(w, af)
	ac.combat.mnt[S.M_AMMO] = 0
	ac.air.state = S.AIR_REARM
	af.combat.emp_until = w.tick + 400
	af.flags |= SimFlags.F_EMP_SHUT
	w.combat.note_status(af.id)
	w.run(100)
	t.eq([ac.combat.mnt[S.M_AMMO], ac.air.rearm_prog], [0, 0], "EMP-shut airfield: no progress")
	t.eq(ac.air.state, S.AIR_REARM, "still waiting")
	w.run(320)  # EMP over at +400
	t.eq(ac.combat.mnt[S.M_AMMO], 0, "still nothing before the shutdown ends")
	w.run(300)
	t.eq(ac.combat.mnt[S.M_AMMO], 1, "then the rearm runs")
	t.eq(ac.air.state, S.AIR_PARKED, "and completes")


# ---------------------------------------------------------------------------------------------- U-AIR-2
func test_air_2_rapid_turnaround_ammo_ticks(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("bomber", 2, 460, 6)
	var af: SimEntity = CombatAirKit.airfield(w, 0, 20, 40)
	var ac: SimEntity = CombatAirKit.parked(w, af)
	SimCombatMods.apply(w, af, 5, S.STAT_REARM_RATE, 5000, 0, 100000)
	ac.combat.mnt[S.M_AMMO] = 0
	ac.air.state = S.AIR_REARM
	var t0: int = w.tick
	w.run(200)
	var ticks: PackedInt32Array = PackedInt32Array()
	for r: PackedInt32Array in CombatWK.evs(w, S.EV_REARM):
		if r[SimEvent.I_B] == 1:
			ticks.append(r[SimEvent.I_TICK] - t0 + 1)
	t.eq(ticks, PackedInt32Array([27, 54, 80, 107, 134, 160]), "ammo units restored at 27, 54, 80, 107, 134, 160")
	t.eq(ac.air.state, S.AIR_PARKED, "done at the sixth unit")
	# base rate: one unit per 40 ticks
	var w2: SimWorld = CombatAirKit.world("bomber", 2, 460, 6)
	var af2: SimEntity = CombatAirKit.airfield(w2, 0, 20, 40)
	var ac2: SimEntity = CombatAirKit.parked(w2, af2)
	ac2.combat.mnt[S.M_AMMO] = 0
	ac2.air.state = S.AIR_REARM
	var b0: int = w2.tick
	w2.run(260)
	var base: PackedInt32Array = PackedInt32Array()
	for r2: PackedInt32Array in CombatWK.evs(w2, S.EV_REARM):
		if r2[SimEvent.I_B] == 1:
			base.append(r2[SimEvent.I_TICK] - b0 + 1)
	t.eq(base, PackedInt32Array([40, 80, 120, 160, 200, 240]), "rearm 240, 6 units: one per 40 ticks")


# ---------------------------------------------------------------------------------------------- U-AIR-3
func test_air_3_bomb_run_release_point(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("bomber", 2, 614, 1)
	var ac: SimEntity = CombatAirKit.flying(w, 0, 8, 48)
	CombatWK.prof_set(w, ac, 0, {SimWeaponProfile.PF_BURST: 6, SimWeaponProfile.PF_BURST_INT: 3})
	var foe: SimEntity = _quiet(_rifle(w, 1, 66, 48))
	w.submit_raw(0, SimCmd.attack([ac.id], foe.id))
	w.run(400)
	var bombs: Array[PackedInt32Array] = []
	for r: PackedInt32Array in CombatWK.evs(w, S.EV_PROJ_SPAWN):
		if (r[SimEvent.I_C] >> 4) & 15 == S.PK_BOMB:
			bombs.append(r)
	t.eq(bombs.size(), 6, "one stick of six bombs")
	if bombs.size() != 6:
		return
	var v: int = (bombs[1][SimEvent.I_E] - bombs[0][SimEvent.I_E]) / 3
	t.check(v > 590 and v < 640, "flying at about 614 u/tick (%d)" % v)
	var s: int = 5 * v * 3
	var first_along: int = foe.x - bombs[0][SimEvent.I_E]
	t.le(first_along, s / 2 + v / 2, "released when along <= S/2 + V/2 (%d <= %d)" % [first_along, s / 2 + v / 2])
	t.gt(first_along, s / 2 - v / 2, "and not a tick earlier (%d > %d)" % [first_along, s / 2 - v / 2])
	var cx: int = 0
	for b: PackedInt32Array in bombs:
		cx += b[SimEvent.I_E]
	cx /= 6
	t.le(absi(cx - foe.x), 307, "the stick is centred on the target within V/2 (%d)" % absi(cx - foe.x))
	t.lt(foe.hp, foe.hp_max, "bombs hit")


# ---------------------------------------------------------------------------------------------- U-AIR-4
func test_air_4_fuel_forced_return_and_no_base(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("bomber", 2, 460, 1)
	var af: SimEntity = CombatAirKit.airfield(w, 0, 20, 40)
	var ac: SimEntity = CombatAirKit.parked(w, af)
	var cd: SimCombatDef = CombatWK.cd(w, ac)
	w.submit_raw(0, SimCmd.guard([ac.id], 0, 34 * C, 40 * C))
	w.run(3)
	ac.air.fuel = 330
	var n: int = _run_until(w, func() -> bool: return ac.air.state == S.AIR_RETURN, 600)
	t.gt(n, 0, "the fuel reserve forces a return (%d ticks)" % n)
	t.eq(ac.air.forced_return, 3, "reason: reserve plus the flight home")
	t.gt(ac.air.fuel, 0, "with fuel left")
	t.le(ac.air.fuel, cd.fuel_reserve + 30 * 1024 / 460 + 12, "at about the reserve")
	var fuel_low: int = ac.air.fuel
	var landed: int = _run_until(w, func() -> bool: return CombatAirKit.tick_of(w, ac, S.AIR_TAKEOFF, maxi(CombatAirKit.tick_of(w, ac, S.AIR_LANDING), 0) + 1) >= 0 and CombatAirKit.tick_of(w, ac, S.AIR_LANDING) >= 0, 1200)
	t.gt(landed, 0, "it lands")
	t.gt(ac.air.fuel, fuel_low + 1000, "and refuels on touchdown (patrol then resumes by itself)")
	t.check(ac.air.resume_mission == S.MI_NONE and ac.air.mission == S.MI_PATROL, "auto resume: the patrol goes on after the rearm")
	# no airfield at all: it orbits, no fuel penalty, no crash
	var w2: SimWorld = CombatAirKit.world("bomber", 2, 460, 1)
	var lone: SimEntity = CombatAirKit.flying(w2, 0, 30, 40)
	w2.submit_raw(0, SimCmd.guard([lone.id], 0, 34 * C, 40 * C))
	w2.run(3)
	lone.air.fuel = 50
	w2.run(200)
	t.eq(lone.air.state, S.AIR_NO_BASE, "no airfield: AIR_NO_BASE")
	var f0: int = lone.air.fuel
	w2.run(100)
	t.eq(lone.air.fuel, f0, "no fuel is burnt while it has no base")
	t.check(w2.get_entity(lone.id) != null and lone.layer == S.LAYER_AIR, "still alive and airborne")
	CombatAirKit.airfield(w2, 0, 20, 40)
	var back: int = _run_until(w2, func() -> bool: return CombatAirKit.tick_of(w2, lone, S.AIR_TAKEOFF, maxi(CombatAirKit.tick_of(w2, lone, S.AIR_LANDING), 0) + 1) >= 0 and CombatAirKit.tick_of(w2, lone, S.AIR_LANDING) >= 0, 1500)
	t.gt(back, 0, "a new airfield brings it home")
	t.gt(lone.air.fuel, 1000, "and refuels")


# ---------------------------------------------------------------------------------------------- S-3
func _aa_run(n_aa: int) -> Array:
	var w: SimWorld = CombatAirKit.world("bomber", 2, 614, 1)
	CombatWK.add_weapon(w, DefTestKit.U_COLLECTOR, DefEnums.WeaponArch.AA_MISSILE, 45, 20000, 12 * C, 0)
	var ac: SimEntity = CombatAirKit.flying(w, 0, 8, 48)
	CombatWK.set_hp(ac, 500)
	CombatWK.prof_set(w, ac, 0, {SimWeaponProfile.PF_BURST: 6, SimWeaponProfile.PF_BURST_INT: 3})
	var foe: SimEntity = _quiet(_rifle(w, 1, 66, 48))
	for i: int in n_aa:
		var aa: SimEntity = CombatWK.unit(w, DefTestKit.U_COLLECTOR, 1, 56 + i % 4, 44 + (i / 4) * 8)
		CombatWK.prof_set(w, aa, 0, {SimWeaponProfile.PF_KIND: S.PK_HITSCAN, SimWeaponProfile.PF_ACC: 10000,
			SimWeaponProfile.PF_BURST: 2, SimWeaponProfile.PF_BURST_INT: 1})
	CombatWK.set_matrix_all(w, 10000)
	w.submit_raw(0, SimCmd.attack([ac.id], foe.id))
	var released: bool = false
	for _i: int in 95:
		w.step()
		if not released:
			for r: PackedInt32Array in CombatWK.evs(w, S.EV_FIRE):
				if r[SimEvent.I_A] == ac.id:
					released = true
	var alive: bool = w.get_entity(ac.id) != null and (ac.flags & SimFlags.F_GONE) == 0
	return [ac.hp if alive else 0, released, w.checksum(), foe.hp]


func test_s3_bomber_versus_aa(t: TestCtx) -> void:
	var hp: Array[int] = []
	var released: Array[bool] = []
	for n: int in [1, 2, 4, 8]:
		var r1: Array = _aa_run(n)
		var r2: Array = _aa_run(n)
		t.eq(r1[2], r2[2], "identical across double runs (%d AA)" % n)
		hp.append(int(r1[0]))
		released.append(bool(r1[1]))
	t.check(hp[0] >= hp[1] and hp[1] >= hp[2] and hp[2] >= hp[3], "damage taken is monotonic in the AA count %s" % str(hp))
	t.gt(hp[0], 0, "one battery does not stop the bomber")
	t.check(released[0], "with one AA the bomber reaches its release point")
	t.eq(hp[3], 0, "eight AA kill it")
	t.check(not released[3], "before it can release")


# ---------------------------------------------------------------------------------------------- styles and orders
func test_hover_style_gunship_attacks(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("gunship", 2, 240, 0)
	var gs: SimEntity = CombatAirKit.flying(w, 0, 20, 40)
	t.eq(CombatWK.cd(w, gs).air_style, S.AS_HOVER, "rotor craft derive the hover style")
	var foe: SimEntity = _quiet(_rifle(w, 1, 40, 40), 300)
	w.submit_raw(0, SimCmd.attack([gs.id], foe.id))
	var n: int = _run_until(w, func() -> bool: return not w.is_alive(foe.id), 1500)
	t.gt(n, 0, "the gunship destroyed its target (%d ticks)" % n)
	t.check(Fp.dist(gs.x - foe.x, gs.y - foe.y) <= 5 * C, "from its hover point inside gun range")
	t.eq(gs.air.sub == S.AP_HOVER or gs.air.state != S.AIR_ATTACK, true, "it hovered (or already left)")


func test_patrol_engages_and_return_to_base(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("gunship", 2, 240, 0)
	var af: SimEntity = CombatAirKit.airfield(w, 0, 20, 40)
	var gs: SimEntity = CombatAirKit.parked(w, af)
	w.submit_raw(0, SimCmd.guard([gs.id], 0, 30 * C, 40 * C))
	w.run(60)
	t.check(gs.air.state == S.AIR_TRANSIT or gs.air.state == S.AIR_PATROL, "guard on an aircraft is an air patrol")
	w.run(300)
	t.eq(gs.air.state, S.AIR_PATROL, "orbiting the patrol point")
	var foe: SimEntity = _quiet(_rifle(w, 1, 31, 43), 200)
	var n: int = _run_until(w, func() -> bool: return not w.is_alive(foe.id), 900)
	t.gt(n, 0, "the patrol engaged an intruder on its own")
	w.run(80)
	t.eq(gs.air.state, S.AIR_PATROL, "and resumed the orbit")
	w.submit_raw(0, SimCmd.return_to_base([gs.id]))
	var landed: int = _run_until(w, func() -> bool: return gs.orders.is_empty() and (gs.air.state == S.AIR_PARKED or gs.air.state == S.AIR_REARM), 1500)
	t.gt(landed, 0, "return to base lands it and the order ends")
	t.eq(gs.layer, S.LAYER_GROUND, "on the ground")


func test_move_order_takes_the_controls_from_the_sortie(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("bomber", 2, 460, 1)
	var ac: SimEntity = CombatAirKit.flying(w, 0, 20, 40)
	w.run(5)
	t.eq([ac.air.state, ac.air.mission], [S.AIR_NO_BASE, S.MI_NONE], "an aircraft without a mission is in free flight")
	w.submit_raw(0, SimCmd.move([ac.id], 50 * C, 40 * C))
	var x0: int = ac.x
	w.run(120)
	t.gt(ac.x, x0 + 10 * C, "a plain move order flies it (the sortie machine stays out of the way)")


# ---------------------------------------------------------------------------------------------- determinism
func _sortie_run() -> Array:
	var w: SimWorld = CombatAirKit.world("bomber", 2, 460, 1)
	var af: SimEntity = CombatAirKit.airfield(w, 0, 20, 40)
	var ac: SimEntity = CombatAirKit.parked(w, af)
	var foe: SimEntity = _quiet(_rifle(w, 1, 55, 40), 300)
	w.submit_raw(0, SimCmd.attack([ac.id], foe.id))
	w.run(700)
	return [w.checksum(), w.events.digest(), w.checksum_log, CombatAirKit.states(w, ac)]


func test_sortie_is_deterministic(t: TestCtx) -> void:
	var r1: Array = _sortie_run()
	var r2: Array = _sortie_run()
	t.eq(r1[0], r2[0], "same final checksum")
	t.eq(r1[1], r2[1], "same event digest")
	t.eq(r1[2], r2[2], "same checkpoint chain")
	t.eq(r1[3], r2[3], "same state sequence")
	# the air component is checksummed: a changed field changes the hash
	var w: SimWorld = CombatAirKit.world("bomber", 2, 460, 1)
	var af: SimEntity = CombatAirKit.airfield(w, 0, 20, 40)
	var ac: SimEntity = CombatAirKit.parked(w, af)
	w.run(1)
	var base: int = w.checksum()
	ac.air.sub_t0 += 1
	t.ne(w.checksum(), base, "SimCompAir.sub_t0 is part of the checksum")
	var base2: int = w.checksum()
	ac.air.search_until += 1
	t.ne(w.checksum(), base2, "SimCompAir.search_until is part of the checksum")


func test_strafe_missile_and_dogfight_styles_engage(t: TestCtx) -> void:
	for style: int in [S.AS_STRAFE, S.AS_MISSILE_RUN, S.AS_DOGFIGHT]:
		var w: SimWorld = CombatAirKit.world("gunship", 2, 300, 0)
		var af: SimEntity = CombatAirKit.airfield(w, 0, 10, 40)
		var gs: SimEntity = CombatAirKit.flying(w, 0, 16, 40)
		CombatWK.cd(w, gs).air_style = style
		var foe: SimEntity = _quiet(_rifle(w, 1, 36, 40), 200)
		w.submit_raw(0, SimCmd.attack([gs.id], foe.id))
		var n: int = _run_until(w, func() -> bool: return not w.is_alive(foe.id), 1500)
		t.gt(n, 0, "style %d: the target was destroyed (%d ticks)" % [style, n])
		var landed: int = _run_until(w, func() -> bool: return gs.orders.is_empty() and gs.layer == S.LAYER_GROUND, 1500)
		t.gt(landed, 0, "style %d: and the aircraft went home and landed" % style)
		t.check(af.air.pad_occ.has(gs.id), "on a pad of its airfield")
