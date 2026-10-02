extends RefCounted
## CB-04: projectile pool and kinds, swept test, detonation / splash / falloff / friendly fire, interception hooks,
## pool cap fallback, view snapshot, checksum sensitivity of the pool.


func _duel(dist_cells: int, hp: int = 100000) -> Array:
	var w: SimWorld = CombatWK.world()
	var a: SimEntity = CombatWK.tank(w, 0, 20, 30)
	var b: SimEntity = CombatWK.tank(w, 1, 20 + dist_cells, 30)
	a.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	b.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	CombatWK.set_matrix_all(w, 10000)
	CombatWK.set_hp(b, hp)
	return [w, a, b]


## Manual launch from mount 0 (the shooter has no target of its own: hold fire).
func _launch(w: SimWorld, a: SimEntity, t: SimEntity, base: int = 100, spd: int = 512, gx: int = 0, gy: int = 0, forced: bool = false) -> int:
	var c: SimCombatDef = CombatWK.cd(w, a)
	var ref: int = w.combat.warhead_ref(w, a, c, 0)
	var wh: SimCombatWarhead = SimProjectiles.warhead_of(w, a.owner, ref)
	return w.combat.proj.launch(w, a, c, 0, t, t.x if t != null else gx, t.y if t != null else gy, a.x, a.y, base, 14336, spd, forced, ref, wh, 0)


func _kind(w: SimWorld, a: SimEntity, kind: int, flags: int = 0, extra: Dictionary = {}) -> void:
	var vals: Dictionary = {SimWeaponProfile.PF_KIND: kind, SimWeaponProfile.PF_FLAGS: flags}
	for k: int in extra:
		vals[k] = extra[k]
	CombatWK.prof_set(w, a, 0, vals)


# ---------------------------------------------------------------------------------------------- geometry
func test_geom_3_swept_vector(t: TestCtx) -> void:
	var out: PackedInt32Array = PackedInt32Array([0, 0])
	t.check(SimProjectiles.swept_hit(8192, 0, 10240, 0, 9216, 0, 448, out), "segment 5 hits although both endpoints are 1024 away")
	t.eq([out[0], out[1]], [9216, 0], "closest point")
	t.check(not SimProjectiles.swept_hit(6144, 0, 8192, 0, 9216, 0, 448, out), "segment 4 misses")
	t.check(not SimProjectiles.swept_hit(10240, 0, 12288, 0, 9216, 0, 448, out), "segment 6 (already past) misses")
	t.check(SimProjectiles.swept_hit(5, 5, 5, 5, 5, 5, 0, out), "zero-length segment on the target")


func test_geom_3_bullet_hits_on_tick_5(t: TestCtx) -> void:
	var s: Array = _duel(9)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.slot_set(w, DefTestKit.U_TANK, 0, {"proj_speed": 2048, "splash_radius": 0})
	CombatWK.wh_of(w, a, 0).splash_r = 0
	t.eq(_launch(w, a, b, 100, 2048), 0, "bullet spawned")
	t.eq(w.combat.proj.live_count(), 1, "one live projectile")
	var hp0: int = b.hp
	CombatWK.run(w, 8)
	var imp: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_IMPACT)
	t.eq(imp.size(), 1, "one impact")
	t.eq(imp[0][SimEvent.I_TICK], 5, "hit on tick 5 (segment 8192 -> 10240)")
	t.eq([imp[0][SimEvent.I_X], imp[0][SimEvent.I_Y]], [b.x, b.y], "at the closest point of the segment")
	t.eq(imp[0][SimEvent.I_C] & 15, 1, "hit_kind: unit")
	t.lt(b.hp, hp0, "damage applied")
	t.eq(w.combat.proj.live_count(), 0, "slot freed")
	t.eq(b.combat.inflight_est, 0, "overkill estimate returned")


func test_geom_4_arc_vectors(t: TestCtx) -> void:
	t.eq(SimProjectiles.arc_flight(12288, 512, 10, 80), 24, "ceil_div(12288, 512)")
	t.eq(SimProjectiles.arc_flight(100, 512, 10, 80), 10, "min flight clamp")
	t.eq(SimProjectiles.arc_flight(1000000, 512, 10, 80), 80, "max flight clamp")
	var sc: int = SimProjectiles.scatter_radius(128, 1536, 12288, 14336)
	t.eq(sc, 1334, "scatter radius")
	t.eq(SimProjectiles.disc_radius(sc, 32768), 943, "u = 32768 -> r 943")


func test_arc_flight_impact_and_scatter(t: TestCtx) -> void:
	var s: Array = _duel(12)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	_kind(w, a, SimCombatConsts.PK_ARC, 0, {SimWeaponProfile.PF_LEAD_BP: 0, SimWeaponProfile.PF_SC_MIN: 0, SimWeaponProfile.PF_SC_MAX: 0,
		SimWeaponProfile.PF_MIN_FLIGHT: 10, SimWeaponProfile.PF_MAX_FLIGHT: 80})
	t.eq(_launch(w, a, b, 100, 512), 0, "arc spawned")
	var sp: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_PROJ_SPAWN)
	t.eq(sp[0][SimEvent.I_C] >> 16, 24, "12288 u at 512 u/tick: 24 ticks of flight")
	t.eq([sp[0][SimEvent.I_E], sp[0][SimEvent.I_F]], [b.x, b.y], "end point = aim point (no scatter)")
	CombatWK.run(w, 30)
	var imp: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_IMPACT)
	t.eq(imp[0][SimEvent.I_TICK], 24, "detonates when k == flight")
	t.lt(b.hp, 100000, "direct proximity hit (splash-less arc)")
	# scatter: two draws, deterministic, inside the disc
	var ends: Array = []
	for _r: int in 2:
		var s2: Array = _duel(12)
		var w2: SimWorld = s2[0]
		var a2: SimEntity = s2[1]
		var b2: SimEntity = s2[2]
		_kind(w2, a2, SimCombatConsts.PK_ARC, 0, {SimWeaponProfile.PF_SC_MIN: 128, SimWeaponProfile.PF_SC_MAX: 1536})
		var before: PackedInt32Array = w2.rng.get_state()
		_launch(w2, a2, b2, 100, 512)
		var e2: Array[PackedInt32Array] = CombatWK.evs(w2, SimCombatConsts.EV_PROJ_SPAWN)
		var dx: int = e2[0][SimEvent.I_E] - b2.x
		var dy: int = e2[0][SimEvent.I_F] - b2.y
		t.check(Fp.dist(dx, dy) <= 1536 + 4, "landing point inside the scatter disc (%d)" % Fp.dist(dx, dy))
		t.ne(w2.rng.get_state(), before, "scatter consumed RNG draws")
		ends.append([dx, dy])
	t.eq(ends[0], ends[1], "same seed, same scatter")


# ---------------------------------------------------------------------------------------------- detonation
func _splash_wh(dmg: int, r: int, inner: int, edge: int, ff: int = 1) -> SimCombatWarhead:
	var wh: SimCombatWarhead = CombatKit.wh(dmg, SimCombatConsts.DT_HE)
	wh.splash_r = r
	wh.splash_inner = inner
	wh.splash_edge_bp = edge
	wh.friendly_fire = ff
	wh.delivery = SimCombatConsts.DELIV_INDIRECT
	return wh


func test_pipe_8_falloff(t: TestCtx) -> void:
	t.eq(SimProjectiles.falloff_bp(1280, 512, 2048, 2500), 6250, "worked example")
	t.eq([SimProjectiles.falloff_bp(0, 512, 2048, 2500), SimProjectiles.falloff_bp(512, 512, 2048, 2500), SimProjectiles.falloff_bp(2048, 512, 2048, 2500)],
		[10000, 10000, 2500], "inner, edge")
	var s: Array = _duel(6, 5000)
	var w: SimWorld = s[0]
	var b: SimEntity = s[2]
	var wh: SimCombatWarhead = _splash_wh(110, 2048, 512, 2500)
	var hp0: int = b.hp
	var cx: int = b.x - (1280 + b.radius)
	w.combat.proj.detonate(w, wh, cx, b.y, -1, 110, 10000, 0, 0, -1, 0, -1, -1, true)
	SimDamage.flush(w)
	t.eq(hp0 - b.hp, 69, "U-PIPE-8: 110 damage at d_eff 1280 -> 69")
	var imp: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_IMPACT)
	t.eq([imp[0][SimEvent.I_D], imp[0][SimEvent.I_E], imp[0][SimEvent.I_F] >> 4], [2048, 69, 1], "EV_IMPACT: radius, total damage, victims")


func test_friendly_fire_and_filters(t: TestCtx) -> void:
	var w: SimWorld = CombatWK.world(3)
	CombatWK.set_matrix_all(w, 10000)
	var own: SimEntity = CombatWK.tank(w, 0, 40, 40)
	var foe: SimEntity = CombatWK.tank(w, 1, 40, 41)
	var third: SimEntity = CombatWK.tank(w, 2, 41, 40)
	var wreck: SimEntity = w.spawn_wreck(own, false, 500, 100)
	for e: SimEntity in [own, foe, third]:
		CombatWK.set_hp(e, 10000)
	var cx: int = own.x
	var cy: int = own.y + 512
	var wh: SimCombatWarhead = _splash_wh(200, 3072, 3072, 10000, 1)
	var pj: SimProjectiles = w.combat.proj
	pj.detonate(w, wh, cx, cy, -1, 200, 10000, 0, 0, own.id, 0, -1, -1, true)
	SimDamage.flush(w)
	t.lt(own.hp, 10000, "the owner's own unit takes splash (bible default friendly_fire 1)")
	t.lt(foe.hp, 10000, "enemy")
	t.lt(third.hp, 10000, "third party")
	t.lt(wreck.hp, 500, "wrecks are victims too")
	for e: SimEntity in [own, foe, third]:
		e.hp = 10000
	wh.friendly_fire = 0
	pj.detonate(w, wh, cx, cy, -1, 200, 10000, 0, 0, own.id, 0, -1, -1, true)
	SimDamage.flush(w)
	t.eq(own.hp, 10000, "friendly_fire 0 (Aurora): owner untouched")
	t.lt(foe.hp, 10000, "enemy still hit")
	t.lt(third.hp, 10000, "a third player on another team is an enemy of pid 0: still hit")
	wh.friendly_fire = 1
	own.hp = 10000
	foe.hp = 10000
	pj.detonate(w, wh, cx, cy, -1, 200, 10000, 0, 0, own.id, SimCombatConsts.PI_ENEMY_ONLY, -1, -1, true)
	SimDamage.flush(w)
	t.eq(own.hp, 10000, "PI_ENEMY_ONLY: summoned attackers spare friends")
	t.lt(foe.hp, 10000, "PI_ENEMY_ONLY: enemies hit")
	# layer mask and annulus
	foe.hp = 10000
	own.hp = 10000
	wh.layer_mask = 1 << SimCombatConsts.LAYER_AIR
	pj.detonate(w, wh, cx, cy, -1, 200, 10000, 0, 0, -1, 0, -1, -1, true)
	SimDamage.flush(w)
	t.eq(foe.hp, 10000, "ground victim outside the layer mask")
	wh.layer_mask = 15
	wh.splash_min_r = 2000
	pj.detonate(w, wh, cx, cy, -1, 200, 10000, 0, 0, -1, 0, -1, -1, true)
	SimDamage.flush(w)
	t.eq(own.hp, 10000, "annulus: victims closer than splash_min_r take nothing")
	# a direct hit on a friendly by force fire still lands (non-splash direct hits touch the intended target)
	var one: SimCombatWarhead = CombatKit.wh(50)
	pj.detonate(w, one, own.x, own.y, own.id, 50, 10000, 0, 0, -1, SimCombatConsts.PI_FORCED, 0, -1, true)
	SimDamage.flush(w)
	t.lt(own.hp, 10000, "forced direct hit on a friendly")


# ---------------------------------------------------------------------------------------------- interception
func _aps_target(w: SimWorld, b: SimEntity, count: int, radius: int, cooldown: int) -> void:
	var c: SimCombatDef = CombatWK.cd(w, b)
	c.aps_count = count
	c.aps_radius = radius
	c.aps_cooldown = cooldown
	b.combat.aps_next = PackedInt32Array()
	b.combat.aps_next.resize(count)


func test_int_1_ural_column(t: TestCtx) -> void:
	var s: Array = _duel(8)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	_aps_target(w, b, 1, 3000, 240)
	CombatWK.wh_of(w, a, 0).splash_r = 0
	var missile_flags: int = SimCombatConsts.PF_GUIDED | SimCombatConsts.PF_APS_INTERCEPTABLE | SimCombatConsts.PF_ZONE_INTERCEPTABLE
	var dmg: int = CombatKit.compute(w, b, CombatWK.wh_of(w, a, 0), 100)
	_kind(w, a, SimCombatConsts.PK_MISSILE, missile_flags, {SimWeaponProfile.PF_HIT_R: 96})
	_launch(w, a, b)  # A at tick 0
	t.gt(b.combat.inflight_est, 0, "in-flight estimate registered on the target")
	CombatWK.run(w, 10)
	_launch(w, a, b)  # B at tick 10
	CombatWK.run(w, 10)
	_kind(w, a, SimCombatConsts.PK_ARC, 0, {SimWeaponProfile.PF_MIN_FLIGHT: 4, SimWeaponProfile.PF_SC_MAX: 0, SimWeaponProfile.PF_SC_MIN: 0, SimWeaponProfile.PF_LEAD_BP: 0})
	_launch(w, a, b)  # shell at tick 20 (no APS flag: "cannot intercept shells")
	CombatWK.run(w, 220)
	_kind(w, a, SimCombatConsts.PK_MISSILE, missile_flags, {SimWeaponProfile.PF_HIT_R: 96})
	_launch(w, a, b)  # C at tick 240
	CombatWK.run(w, 40)
	var ic: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_INTERCEPT)
	t.eq(ic.size(), 2, "A and C intercepted, B and the shell are not")
	var ta: int = ic[0][SimEvent.I_TICK]
	t.eq(ic[0][SimEvent.I_D], ta + 240, "interceptor ready again 240 ticks later")
	t.eq(ic[1][SimEvent.I_TICK], ta + 240, "C reaches the radius exactly when the interceptor is ready and is removed")
	t.eq([ic[0][SimEvent.I_C], ic[1][SimEvent.I_C]], [0, 0], "kind 0 = point defence")
	var ends: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_PROJ_END)
	t.eq(ends.size(), 2, "two EV_PROJ_END")
	t.eq(ends[0][SimEvent.I_B], 1, "reason 1 = APS")
	t.eq(100000 - b.hp, 2 * dmg, "missile B and the shell landed")
	t.eq(w.combat.proj.live_count(), 0, "nothing left flying")
	t.eq(b.combat.inflight_est, 0, "estimate balanced")


func test_s4_javelin_volleys_vs_ural(t: TestCtx) -> void:
	var s: Array = _duel(9)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	a.combat.stance = SimCombatConsts.ST_AGGRESSIVE
	_aps_target(w, b, 1, 3000, 240)
	CombatWK.slot_set(w, DefTestKit.U_TANK, 0, {"damage": 100, "reload_mt": 20000, "range": 10240, "proj_speed": 512, "splash_radius": 0})
	CombatWK.wh_of(w, a, 0).splash_r = 0
	_kind(w, a, SimCombatConsts.PK_MISSILE, SimCombatConsts.PF_GUIDED | SimCombatConsts.PF_APS_INTERCEPTABLE, {SimWeaponProfile.PF_HIT_R: 96})
	var dmg: int = CombatKit.compute(w, b, CombatWK.wh_of(w, a, 0), 100)
	w.combat.set_target(w, a, b.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w, 75)  # three volleys at 0 / 20 / 40, all landed or intercepted
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_INTERCEPT).size(), 1, "only the first volley in 240 ticks is intercepted")
	t.eq(100000 - b.hp, 2 * dmg, "the other two land")
	# a unit without APS is never intercepted
	var c: SimEntity = CombatWK.tank(w, 1, 26, 33)
	c.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	c.combat.aps_next = PackedInt32Array()  # the compiled def is shared with B: strip its interceptors
	CombatWK.set_hp(c, 100000)
	w.combat.set_target(w, a, c.id, SimCombatConsts.TS_ORDER)
	CombatWK.run(w, 60)
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_INTERCEPT).size(), 1, "no new interception on a target without point defence")
	t.lt(c.hp, 100000, "damaged")


func _zone_world() -> Array:
	var w: SimWorld = CombatWK.world()
	var fz: CombatWK.FakeZones = CombatWK.FakeZones.new()
	fz.charges = 24
	fz.cx = 50 * 1024
	fz.cy = 30 * 1024
	fz.radius = 3 * 1024
	w.zones = fz
	CombatWK.set_matrix_all(w, 10000)
	return [w, fz]


func test_int_2_trident_ordinary_and_packets(t: TestCtx) -> void:
	var z: Array = _zone_world()
	var w: SimWorld = z[0]
	var fz: CombatWK.FakeZones = z[1]
	var target: SimEntity = CombatWK.tank(w, 1, 50, 30)  # inside the bubble
	target.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	CombatWK.set_hp(target, 1000000)
	var shell: SimCombatWarhead = _splash_wh(100, 1024, 512, 5000)
	var wi: int = w.combat.tables_of(0).add_warhead(shell)
	var pj: SimProjectiles = w.combat.proj
	# 5 shells from outside: all destroyed at the boundary
	for _i: int in 5:
		t.gt(pj.spawn_remote(w, 0, -1, SimCombatConsts.PK_ARC, wi, 30 * 1024, 30 * 1024, 50 * 1024, 30 * 1024, 0, 10000, 0), 0, "spawned")
	CombatWK.run(w, 60)
	t.eq(fz.charges, 19, "5 shells consumed 5 charges")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_PROJ_END).size(), 5, "all five ended")
	for r: PackedInt32Array in CombatWK.evs(w, SimCombatConsts.EV_PROJ_END):
		t.eq(r[SimEvent.I_B], 2, "reason 2 = zone")
	t.eq(target.hp, 1000000, "and never reached the target")
	# a shell launched from inside the bubble bypasses it
	pj.spawn_remote(w, 0, -1, SimCombatConsts.PK_ARC, wi, 50 * 1024, 30 * 1024 - 1500, 50 * 1024, 30 * 1024, 0, 10000, 0)
	CombatWK.run(w, 30)
	t.eq(fz.charges, 19, "launch point inside: bypass")
	t.lt(target.hp, 1000000, "lands")
	# a bullet is never asked
	var calls: int = fz.ordinary_calls
	var a: SimEntity = CombatWK.tank(w, 0, 42, 30)
	a.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	var hp1: int = target.hp
	CombatWK.slot_set(w, DefTestKit.U_TANK, 0, {"damage": 50, "range": 12000, "proj_speed": 819})
	_kind(w, a, SimCombatConsts.PK_BULLET, 0)
	_launch(w, a, target, 50, 819)
	CombatWK.run(w, 20)
	t.eq(fz.ordinary_calls, calls, "bullets never ask the zone system")
	t.lt(target.hp, hp1, "the bullet crossed the bubble and hit")
	# packets: 19 charges -> reduced (11) -> reduced (3) -> full
	var pk: SimCombatWarhead = CombatKit.wh(400, SimCombatConsts.DT_KINETIC)
	pk.packet = 1
	pk.delivery = SimCombatConsts.DELIV_STRATEGIC
	pk.splash_r = 1024
	pk.splash_inner = 1024
	pk.splash_edge_bp = 10000
	var pi: int = w.combat.tables_of(0).add_warhead(pk)
	var full: int = CombatKit.compute(w, target, pk, 400, SimCombatConsts.DC_STRATEGIC, {"pkt": 0})
	var half: int = CombatKit.compute(w, target, pk, 400, SimCombatConsts.DC_STRATEGIC, {"pkt": 5000})
	t.lt(half, full, "reduced packet deals less")
	var seen: Array = []
	for i: int in 3:
		var hp: int = target.hp
		pj.spawn_remote(w, 0, -1, SimCombatConsts.PK_STRIKE, pi, 50 * 1024, 30 * 1024, 50 * 1024, 30 * 1024, 0, 10000, 0)
		w.step()
		seen.append(hp - target.hp)
	t.eq(seen, [half, half, full], "packets 1 and 2 halved, packet 3 full (charges %d)" % fz.charges)
	t.eq(fz.charges, 3, "3 charges left")
	# beams are neither ordinary projectiles nor packets
	var calls2: int = fz.ordinary_calls + fz.packet_calls
	_kind(w, a, SimCombatConsts.PK_BEAM, 0)
	CombatWK.slot_set(w, DefTestKit.U_TANK, 0, {"reload_mt": 5000})
	a.combat.stance = SimCombatConsts.ST_AGGRESSIVE
	w.combat.set_target(w, a, target.id, SimCombatConsts.TS_ORDER)
	var hp2: int = target.hp
	CombatWK.run(w, 30)
	t.lt(target.hp, hp2, "the beam pushes through the zone")
	t.eq(fz.ordinary_calls + fz.packet_calls, calls2, "beams never ask the zone system")


# ---------------------------------------------------------------------------------------------- S-2 / S-6
func _howitzer(lead: int, moving: bool) -> int:
	var s: Array = _duel(12, 100000)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	b.x = a.x + 12288
	w.set_pos(b, a.x + 12288, b.y, true)
	var wh: SimCombatWarhead = CombatWK.wh_of(w, a, 0)
	wh.splash_r = 2048
	wh.splash_inner = 512
	wh.splash_edge_bp = 2500
	wh.delivery = SimCombatConsts.DELIV_INDIRECT
	_kind(w, a, SimCombatConsts.PK_ARC, 0, {SimWeaponProfile.PF_LEAD_BP: lead, SimWeaponProfile.PF_SC_MIN: 0, SimWeaponProfile.PF_SC_MAX: 0,
		SimWeaponProfile.PF_MIN_FLIGHT: 10, SimWeaponProfile.PF_MAX_FLIGHT: 80})
	if moving:
		b.vx = 120
	_launch(w, a, b, 200, 512)
	b.vx = 0
	for _i: int in 40:
		w.step()
		if moving:
			w.set_pos(b, b.x + 120, b.y)
	return 100000 - b.hp


func test_s2_howitzer_stationary_and_moving(t: TestCtx) -> void:
	var full: int = _howitzer(0, false)
	t.gt(full, 0, "stationary target takes the shell")
	t.eq(_howitzer(0, true), 0, "lead 0: a target moving 120 u/tick is 2880 u away when the shell lands: no damage")
	t.gt(_howitzer(10000, true), 0, "lead 10000 hits the mover")
	var s: Array = _duel(12, 100000)
	var w: SimWorld = s[0]
	var wh: SimCombatWarhead = CombatWK.wh_of(w, s[1], 0)
	wh.splash_inner = 512
	wh.splash_r = 2048
	t.eq(SimProjectiles.falloff_bp(0, wh.splash_inner, wh.splash_r, 2500), 10000, "inside splash_inner: full damage")


func test_s6_helios_sweep(t: TestCtx) -> void:
	var w: SimWorld = CombatWK.world()
	CombatWK.set_matrix_all(w, 10000)
	var stay: SimEntity = CombatWK.tank(w, 1, 40, 30)
	var walker: SimEntity = CombatWK.tank(w, 1, 40, 34)
	for e: SimEntity in [stay, walker]:
		e.combat.stance = SimCombatConsts.ST_HOLD_FIRE
		CombatWK.set_hp(e, 1000000)
	var beam: SimCombatWarhead = CombatKit.wh(60, SimCombatConsts.DT_THERMAL)
	var wi: int = w.combat.tables_of(0).add_warhead(beam)
	var ax: int = 32 * 1024
	var ay: int = 30 * 1024
	var ser: int = w.combat.proj.spawn_sweep(w, 0, -1, SimCombatConsts.PK_SWEEP, wi, ax, ay, ax + 16384, ay, 0, 240)
	t.gt(ser, 0, "sweep spawned")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_SWEEP).size(), 1, "EV_SWEEP")
	# the second unit stands off the line first, then walks straight onto it and away again
	walker.y = ay + 4096
	w.set_pos(walker, walker.x, ay + 4096, true)
	var stay_hits: int = 0
	var walk_hits: int = 0
	var s_hp: int = stay.hp
	var w_hp: int = walker.hp
	for i: int in 250:
		w.step()
		if stay.hp < s_hp:
			stay_hits += 1
			s_hp = stay.hp
		if walker.hp < w_hp:
			walk_hits += 1
			w_hp = walker.hp
		# walker keeps 4096 u beside the line, moving with the spot: never inside
		w.set_pos(walker, walker.x, ay + 4096)
	t.check(stay_hits >= 8 and stay_hits <= 12, "a unit standing on the line takes about 9 dots (%d)" % stay_hits)
	t.eq(walk_hits, 0, "a unit off the line takes nothing")
	# a unit crossing the line quickly takes at most 2 dots
	var runner: SimEntity = CombatWK.tank(w, 1, 60, 24)
	runner.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	CombatWK.set_hp(runner, 1000000)
	var ser2: int = w.combat.proj.spawn_sweep(w, 0, -1, SimCombatConsts.PK_SWEEP, wi, 55 * 1024, 30 * 1024, 55 * 1024 + 16384, 30 * 1024, 0, 240)
	t.gt(ser2, 0, "second sweep")
	var r_hp: int = runner.hp
	var r_hits: int = 0
	for i: int in 120:
		w.step()
		if runner.hp < r_hp:
			r_hits += 1
			r_hp = runner.hp
		# the runner crosses the line perpendicular at 400 u/tick, staying under the moving spot in x
		var spot_x: int = 55 * 1024 + 16384 * (i + 1) / 240
		w.set_pos(runner, spot_x, runner.y + 400)
	t.le(r_hits, 2, "walking off the line: at most 2 dots (%d)" % r_hits)
	CombatWK.run(w, 130)
	t.eq(w.combat.proj.live_count(), 0, "sweeps finish (reason 4)")


# ---------------------------------------------------------------------------------------------- pool cap
func _fill(w: SimWorld, upto: int, wi: int) -> void:
	var pj: SimProjectiles = w.combat.proj
	while pj.live_count() < upto:
		if pj.spawn_remote(w, 0, -1, SimCombatConsts.PK_STRIKE, wi, 90 * 1024, 90 * 1024, 90 * 1024, 90 * 1024, 100000, 10000, 0) < 0:
			break


func test_pool_cap_fallback(t: TestCtx) -> void:
	var s: Array = _duel(5)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	var idle: SimCombatWarhead = CombatKit.wh(1)
	var wi: int = w.combat.tables_of(0).add_warhead(idle)
	var pj: SimProjectiles = w.combat.proj
	CombatWK.wh_of(w, a, 0).splash_r = 0
	_kind(w, a, SimCombatConsts.PK_BULLET, 0)
	_fill(w, SimCombatConsts.PROJ_SOFT_CAP - 1, wi)
	t.eq(_launch(w, a, b, 100, 819), 0, "below the soft cap: real projectile")
	t.eq(pj.live_count(), SimCombatConsts.PROJ_SOFT_CAP, "one more live")
	var hp0: int = b.hp
	t.eq(_launch(w, a, b, 100, 819), 1, "at the soft cap: splash-less bullet resolves instantly")
	SimDamage.flush(w)
	t.lt(b.hp, hp0, "instant damage")
	t.eq(pj.live_count(), SimCombatConsts.PROJ_SOFT_CAP, "no slot used")
	# a splash weapon still flies at the soft cap
	CombatWK.wh_of(w, a, 0).splash_r = 512
	t.eq(_launch(w, a, b, 100, 819), 0, "splash shots are not softened")
	# hard cap
	_fill(w, SimCombatConsts.PROJ_POOL - SimCombatConsts.PROJ_STRATEGIC_RESERVE, wi)
	var hp1: int = b.hp
	t.eq(_launch(w, a, b, 100, 819), 1, "hard cap: everything non-strategic resolves instantly")
	SimDamage.flush(w)
	t.lt(b.hp, hp1, "still damages")
	t.eq(pj.live_count(), SimCombatConsts.PROJ_POOL - SimCombatConsts.PROJ_STRATEGIC_RESERVE, "reserve kept")
	_fill(w, SimCombatConsts.PROJ_POOL, wi)
	t.eq(pj.live_count(), SimCombatConsts.PROJ_POOL, "strategic spawns use the reserve")
	t.eq(pj.spawn_remote(w, 0, -1, SimCombatConsts.PK_STRIKE, wi, 0, 0, 0, 0, 5, 10000, 0), -1, "-1 only when the reserve is exhausted too")


# ---------------------------------------------------------------------------------------------- view / hash
func test_snapshot_api(t: TestCtx) -> void:
	var s: Array = _duel(9)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	CombatWK.slot_set(w, DefTestKit.U_TANK, 0, {"proj_speed": 300})
	_launch(w, a, b, 100, 300)
	CombatWK.run(w, 3)
	var out: PackedInt32Array = PackedInt32Array()
	var n: int = w.combat.proj.snapshot(out)
	t.eq([n, out.size()], [1, SimProjectiles.SNAP_STRIDE], "one record")
	var sp: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_PROJ_SPAWN)
	t.eq(out[0], sp[0][SimEvent.I_A], "serial matches EV_PROJ_SPAWN")
	t.eq([out[1], out[8], out[9]], [SimCombatConsts.PK_BULLET, 0, b.id], "kind, owner, target")
	t.check(out[3] > a.x and out[5] < out[3], "x advanced; previous-tick x behind it (interpolation)")
	t.eq(w.combat.proj.slot_of_serial(out[0]), 0, "slot lookup")


func test_pool_checksum_sensitivity(t: TestCtx) -> void:
	var s: Array = _duel(9)
	var w: SimWorld = s[0]
	var a: SimEntity = s[1]
	var b: SimEntity = s[2]
	_launch(w, a, b, 100, 300)
	CombatWK.run(w, 2)
	var pj: SimProjectiles = w.combat.proj
	var slot: int = 0
	t.check(pj.is_live(slot), "a live projectile")
	var base: int = w.checksum()
	for name: String in ["serial", "kind", "pdef", "wh", "wpn", "owner_pid", "owner_id", "owner_team", "x", "y", "px", "py", "sx", "sy", "ex", "ey", "vx", "vy",
			"heading", "speed", "t0", "t_end", "flight", "target", "dmg", "dmg_bp", "dmg_tmp", "flags", "pflags", "est", "aux0", "aux1", "hit_r", "turn"]:
		var arr: PackedInt32Array = pj.get(name)
		arr[slot] += 1
		pj.set(name, arr)
		t.ne(w.checksum(), base, "checksum reacts to projectile field %s" % name)
		arr[slot] -= 1
		pj.set(name, arr)
	t.eq(w.checksum(), base, "restored")
