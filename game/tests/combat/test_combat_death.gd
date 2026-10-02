extends RefCounted
## CB-07: death sequence (U-DEATH-1..4), wreck lifecycle and salvage API, occupants, chain effects and their per-tick
## cap, aircraft crash, S-7 (EMP scenario: vehicles and aircraft disabled, infantry and allies unaffected).

const C: int = SimConfig.CELL


func _world(n: int = 2, teams: PackedInt32Array = PackedInt32Array()) -> SimWorld:
	var w: SimWorld = CombatWK.world(n, 4242, teams)
	CombatWK.set_matrix_all(w, 10000)
	w.combat.salvage_enabled = 1
	return w


func _kill(w: SimWorld, e: SimEntity, killer_pid: int, cause: int = SimCombatConsts.CAUSE_DAMAGE) -> void:
	w.combat.kill(w, e, cause, -1, killer_pid)
	w.step()


func _live_wrecks(w: SimWorld) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for e: SimEntity in w.wrecks:
		if (e.flags & SimFlags.F_GONE) == 0:
			out.append(e)
	return out


func _tank(w: SimWorld, owner: int, cx: int, cy: int, paid: int = 900, flags: int = 0) -> SimEntity:
	return w.spawn_unit(w.data.unit_idx(DefTestKit.U_TANK), owner, cx * C + C / 2, cy * C + C / 2, 0, flags, paid)


# ---------------------------------------------------------------------------------------------- U-DEATH-1
func test_death_1_wreck_matrix(t: TestCtx) -> void:
	# enemy kill of a land combat vehicle that cost 900
	var w: SimWorld = _world()
	var v: SimEntity = _tank(w, 1, 30, 30)
	_kill(w, v, 0)
	var ws: Array[SimEntity] = _live_wrecks(w)
	t.eq(ws.size(), 1, "enemy kill: one wreck")
	if ws.size() == 1:
		var wc: SimCompCombat = ws[0].combat
		t.eq([ws[0].kind, wc.wreck_value, wc.wreck_owner_pid, wc.wreck_flags], [SimEntity.Kind.WRECK, 900, 1, SimCombatConsts.WF_SALVAGEABLE], "value = paid cost, owner, salvageable")
		t.eq(ws[0].hp_max, maxi(SimCombatConsts.WRECK_HP_MIN, SimDamage.mul(v.hp_max, 3000)), "wreck hp = 30 % of the hull, min 150")
		t.eq(wc.wreck_expire, w.tick - 1 + SimCombatConsts.WRECK_TICKS, "expires 1200 ticks after the death")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_WRECK_ADD).size(), 1, "EV_WRECK_ADD")
	var death: PackedInt32Array = CombatWK.evs(w, SimCombatConsts.EV_DEATH)[0]
	t.eq([death[SimEvent.I_A], death[SimEvent.I_C] & 15, (death[SimEvent.I_C] >> 8) & 1], [v.id, SimCombatConsts.DK_VEHICLE, 1], "EV_DEATH: vehicle death with the wreck flag")
	t.eq([w.players[1].st_units_lost, w.players[0].st_units_killed], [1, 1], "kernel statistics credited")
	# no wreck in any of these
	var cases: Array = ["friendly", "scuttle", "summoned", "decoy", "infantry", "salvage off", "unpaid"]
	for c: String in cases:
		var w2: SimWorld = _world(3, PackedInt32Array([1, 2, 1]))
		var fl: int = 0
		if c == "summoned":
			fl = SimFlags.F_SUMMONED
		elif c == "decoy":
			fl = SimFlags.F_DECOY
		var e: SimEntity = _tank(w2, 1, 30, 30, 0 if c == "unpaid" else 900, fl)
		if c == "infantry":
			e = w2.spawn_unit(w2.data.unit_idx(DefTestKit.U_RIFLEMAN), 1, 30 * C, 30 * C, 0, 0, 250)
		if c == "salvage off":
			w2.combat.salvage_enabled = 0
		var killer: int = 0
		var cause: int = SimCombatConsts.CAUSE_DAMAGE
		if c == "friendly":
			killer = 1
		elif c == "scuttle":
			killer = -1
			cause = SimCombatConsts.CAUSE_SCUTTLE
		_kill(w2, e, killer, cause)
		t.eq(_live_wrecks(w2).size(), 0, "no wreck: " + c)
	# a kill by an ally of the victim (same team) is friendly fire too
	var w3: SimWorld = _world(3, PackedInt32Array([1, 1, 2]))
	_kill(w3, _tank(w3, 0, 30, 30), 1)
	t.eq(_live_wrecks(w3).size(), 0, "no wreck: killed by an ally")
	# the salvage trait on any roster switches wrecks on at init_world
	var w4: SimWorld = CombatWK.world(2)
	t.eq(w4.combat.salvage_enabled, 0, "no salvage-capable roster: no wrecks")


# ---------------------------------------------------------------------------------------------- U-DEATH-2
func test_death_2_wreck_lifecycle_and_salvage(t: TestCtx) -> void:
	var w: SimWorld = _world(3, PackedInt32Array([1, 2, 2]))
	var v: SimEntity = _tank(w, 1, 30, 30)
	_kill(w, v, 0)
	var wr: SimEntity = _live_wrecks(w)[0]
	t.eq(w.combat.wreck_ids, PackedInt32Array([wr.id]), "wreck_ids lists it")
	t.check(not w.combat.wreck_can_be_salvaged_by(w, wr, 2), "an allied salvager gets nothing")
	t.eq(w.combat.try_salvage(w, wr.id, 2, 20), -1, "allied salvage refused")
	t.check(w.combat.wreck_can_be_salvaged_by(w, wr, 0), "an enemy may salvage")
	# splash destroys a wreck (all relations)
	var w2: SimWorld = _world()
	_kill(w2, _tank(w2, 1, 30, 30), 0)
	var wr2: SimEntity = _live_wrecks(w2)[0]
	var wh: SimCombatWarhead = CombatKit.wh(2000, SimCombatConsts.DT_HE)
	wh.splash_r = 1024
	wh.splash_inner = 1024
	wh.friendly_fire = 1
	w2.combat.proj.detonate(w2, wh, wr2.x, wr2.y, -1, 2000, 10000, 0, 0, -1, 0, -1, -1, true)
	w2.step()
	t.check(CombatWK.dead(wr2) or w2.get_entity(wr2.id) == null, "splash destroyed the wreck")
	t.eq(CombatWK.evs(w2, SimCombatConsts.EV_WRECK_REMOVE)[0][SimEvent.I_B], 1, "EV_WRECK_REMOVE reason 1 (destroyed)")
	# salvage pays once
	var pay: int = w.combat.try_salvage(w, wr.id, 0, 20)
	t.eq(pay, 180, "half_up(900 * 20 %) = 180")
	t.eq(w.combat.try_salvage(w, wr.id, 0, 20), -1, "each wreck pays once")
	w.step()
	t.check(w.get_entity(wr.id) == null, "the consumed wreck is gone")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_WRECK_REMOVE)[0][SimEvent.I_B], 2, "EV_WRECK_REMOVE reason 2 (salvaged)")
	# expiry after 1200 ticks
	var w3: SimWorld = _world()
	_kill(w3, _tank(w3, 1, 30, 30), 0)
	var wr3: SimEntity = _live_wrecks(w3)[0]
	var due: int = wr3.combat.wreck_expire
	while w3.tick < due:
		w3.step()
	t.check(w3.get_entity(wr3.id) != null, "still there the tick before")
	w3.step()
	t.check(w3.get_entity(wr3.id) == null, "gone when the 1200 ticks are up")
	var rem: PackedInt32Array = CombatWK.evs(w3, SimCombatConsts.EV_WRECK_REMOVE)[0]
	t.eq([rem[SimEvent.I_B], rem[SimEvent.I_TICK]], [0, due], "EV_WRECK_REMOVE reason 0 (expired) at the expiry tick")
	t.eq(w3.combat.wreck_ids.size(), 0, "wreck_ids compacted")


# ---------------------------------------------------------------------------------------------- U-DEATH-3
func _passengers(w: SimWorld, box: SimEntity, n: int, owner: int = 1) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for i: int in n:
		var p: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_RIFLEMAN), owner, box.x, box.y)
		w.set_inside(p, box.id, true)
		out.append(p)
	return out


func test_death_3_occupants(t: TestCtx) -> void:
	# CARGO_DIE: transports die with their cargo, no wreck for the passengers
	var w: SimWorld = _world()
	var apc: SimEntity = _tank(w, 1, 30, 30)
	CombatWK.cd(w, apc).cargo_mode = SimCombatConsts.CARGO_DIE
	var ps: Array[SimEntity] = _passengers(w, apc, 3)
	_kill(w, apc, 0)
	for p: SimEntity in ps:
		t.check(w.get_entity(p.id) == null or CombatWK.dead(p), "passenger died with the transport")
	t.eq(_live_wrecks(w).size(), 1, "only the transport leaves a wreck")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_EJECT).size(), 0, "no ejections")
	var d: PackedInt32Array = CombatWK.evs(w, SimCombatConsts.EV_DEATH)[0]
	t.eq((d[SimEvent.I_C] >> 8) & 32, 32, "EV_DEATH flags: had occupants")
	t.eq(w.players[1].st_units_lost, 4, "all four losses counted")
	# CARGO_EJECT_HURT 3000: reinforced passenger protection
	var w2: SimWorld = _world()
	var beaver: SimEntity = _tank(w2, 1, 30, 30)
	var bd: SimCombatDef = CombatWK.cd(w2, beaver)
	bd.cargo_mode = SimCombatConsts.CARGO_EJECT_HURT
	bd.eject_hurt_bp = 3000
	var hurt: Array[SimEntity] = _passengers(w2, beaver, 2)
	hurt[1].hp = 50
	_kill(w2, beaver, 0)
	t.check((hurt[0].flags & SimFlags.F_INSIDE) == 0 and hurt[0].container_id == -1, "ejected onto the map")
	t.eq(hurt[0].hp, 400 - SimDamage.mul(400, 3000), "each passenger takes 30 % of its max hp")
	t.eq(hurt[1].hp, 1, "non-lethal: at least 1 hp")
	t.check(w2.spatial.contains(hurt[0].id), "back in the spatial hash")
	t.eq(CombatWK.evs(w2, SimCombatConsts.EV_EJECT).size(), 2, "one EV_EJECT per passenger")
	# a garrison (structure): 2500, unharmed variant CARGO_EJECT
	var w3: SimWorld = _world()
	var bld: SimEntity = CombatWK.turret(w3, 1, 40, 40)
	var gd: SimCombatDef = CombatWK.cd(w3, bld)
	gd.cargo_mode = SimCombatConsts.CARGO_EJECT_HURT
	gd.eject_hurt_bp = 2500
	var gar: Array[SimEntity] = _passengers(w3, bld, 2)
	_kill(w3, bld, 0)
	t.eq(gar[0].hp, 400 - SimDamage.mul(400, 2500), "garrison collapse hurts by 25 %")
	t.eq(CombatWK.evs(w3, SimCombatConsts.EV_EJECT)[0][SimEvent.I_C], 0, "reason 0: garrison collapse")
	var w4: SimWorld = _world()
	var box: SimEntity = _tank(w4, 1, 30, 30)
	CombatWK.cd(w4, box).cargo_mode = SimCombatConsts.CARGO_EJECT
	var safe: Array[SimEntity] = _passengers(w4, box, 1)
	_kill(w4, box, 0)
	t.eq(safe[0].hp, safe[0].hp_max, "CARGO_EJECT: unharmed")
	# the derived profiles: transports die with cargo, reinforced ones (passenger_damage_reduction) eject
	t.eq(CombatWK.cd(w4, box).cargo_mode, SimCombatConsts.CARGO_EJECT, "test edit visible")


# ---------------------------------------------------------------------------------------------- chain effects
func test_chain_blast_hurts_neighbours_and_cap(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var gen: SimEntity = w.spawn_structure(w.data.structure_idx(DefTestKit.S_GENERATOR), 1, 40 * C, 40 * C)
	var gd: SimCombatDef = CombatWK.cd(w, gen)
	t.gt(gd.chain_wh, -1, "a generator (power > 0) has a chain blast derived")
	var mine: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_RIFLEMAN), 1, 40 * C + 1200, 40 * C)
	var theirs: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_RIFLEMAN), 0, 40 * C, 40 * C + 1200)
	var far: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_RIFLEMAN), 0, 48 * C, 48 * C)
	_kill(w, gen, 0)
	w.run(6)
	t.lt(mine.hp, mine.hp_max, "friendly fire: the owner's own neighbour is hurt")
	t.lt(theirs.hp, theirs.hp_max, "and the killer's unit too")
	t.eq(far.hp, far.hp_max, "outside the radius: untouched")
	# more than CHAIN_CAP chain deaths in one tick: the rest waits for the next tick, in order
	var w2: SimWorld = _world()
	var gens: Array[SimEntity] = []
	var idx: int = w2.data.structure_idx(DefTestKit.S_GENERATOR)
	for i: int in SimCombatConsts.CHAIN_CAP + 6:
		var g: SimEntity = w2.spawn_structure(idx, 1, (4 + (i % 20) * 4) * C, (4 + (i / 20) * 4) * C)
		t.not_null(g, "generator %d spawned" % i)
		gens.append(g)
	for g: SimEntity in gens:
		w2.combat.kill(w2, g, SimCombatConsts.CAUSE_DAMAGE, -1, 0)
	var before: int = w2.combat.proj.live_count()
	w2.step()
	t.eq(w2.combat.proj.live_count() - before, SimCombatConsts.CHAIN_CAP, "exactly CHAIN_CAP strikes this tick")
	t.eq(w2.combat.chain_q.size(), 6 * SimDeath.CHAIN_REC, "six deferred (hashed queue)")
	w2.step()
	t.eq(w2.combat.chain_q.size(), 0, "the rest released on the next tick")
	# the deferred queue is part of the checksum
	var w3: SimWorld = _world()
	var c1: int = w3.checksum()
	w3.combat.chain_q.append_array(PackedInt32Array([1, 2, 3, 4, 5, 6]))
	t.ne(w3.checksum(), c1, "chain_q changes the checksum")


# ---------------------------------------------------------------------------------------------- U-DEATH-4
func test_death_4_aircraft_crash(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("bomber")
	var ac: SimEntity = CombatAirKit.flying(w, 1, 20, 40)
	var above: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_RIFLEMAN), 1, 0, 0)  # placed below
	CombatWK.set_hp(above, 400)
	# freeze the aircraft in flight with velocity (600, 0) and kill it
	SimMovement.air_hover(w, ac)
	w.set_pos(ac, 20 * C, 40 * C, true)
	ac.vx = 600
	ac.vy = 0
	var x: int = ac.x
	var y: int = ac.y
	var vx: int = 600
	var k: int = w.tick
	var landing_x: int = x
	for _i: int in 29:  # upkeep runs on the 29 ticks after the death tick, then the impact tick
		landing_x += vx
		vx = vx * 15 / 16
	w.set_pos(above, landing_x, y, true)
	var hp0: int = above.hp
	w.combat.kill(w, ac, SimCombatConsts.CAUSE_DAMAGE, -1, 0)
	w.step()
	t.eq(ac.combat.dying_until, k + 30, "crash_ticks 30")
	t.check((ac.combat.cflags & SimCombatConsts.CF_DYING) != 0, "dying")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_CRASH)[0][SimEvent.I_B], 0, "EV_CRASH start")
	t.check(w.get_entity(ac.id) != null, "the wreckage stays while falling")
	w.run(10)
	t.gt(ac.x, x, "falls along its velocity")
	t.check(ac.combat.crash_vx < 600 and ac.combat.crash_vx > 0, "with a decaying velocity (15/16)")
	w.run(30)
	t.eq(w.get_entity(ac.id), null, "removed after the impact")
	t.lt(above.hp, hp0, "the ground impact hurt the unit underneath (friendly fire)")
	var ev: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_CRASH)
	t.eq(ev.size(), 2, "start and ground impact events")
	t.eq(ev[1][SimEvent.I_TICK], k + 30, "impact exactly crash_ticks after the death")
	t.lt(absi(ev[1][SimEvent.I_X] - landing_x), 8, "at the integrated position (15/16 decay, truncating)")
	# a parked aircraft (ground layer) just dies
	var w2: SimWorld = CombatAirKit.world("bomber")
	var af: SimEntity = CombatAirKit.airfield(w2, 1, 30, 30)
	var pk: SimEntity = CombatAirKit.parked(w2, af)
	w2.combat.kill(w2, pk, SimCombatConsts.CAUSE_DAMAGE, -1, 0)
	w2.step()
	t.eq(pk.combat.dying_until, 0, "no crash for a parked aircraft")
	t.eq(af.air.pad_occ[0], -1, "its pad is free again")


# ---------------------------------------------------------------------------------------------- S-7
func test_s7_emp_scenario(t: TestCtx) -> void:
	var w: SimWorld = CombatAirKit.world("bomber", 2, 300, 1, 3)
	w.combat.init_world(w)
	var tanks: Array[SimEntity] = []
	# the fixture world has no vehicle: use the rifleman def for infantry and hand the aircraft def as the "vehicle" class
	for i: int in 8:
		tanks.append(w.spawn_unit(w.data.unit_idx(DefTestKit.U_COLLECTOR), 1, (40 + i % 4) * C, (40 + i / 4) * C))
	var inf: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_RIFLEMAN), 1, 41 * C, 42 * C)
	var ally: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_COLLECTOR), 0, 42 * C, 42 * C)
	var ac: SimEntity = CombatAirKit.flying(w, 1, 41, 43)
	SimMovement.air_fly_to(w, ac, 60 * C, 43 * C)
	var emp: SimCombatWarhead = SimCombatWarhead.new()
	emp.damage = 0
	emp.dtype = SimCombatConsts.DT_EMP
	emp.delivery = SimCombatConsts.DELIV_STRATEGIC
	emp.splash_r = 8 * C
	emp.splash_inner = 8 * C
	emp.splash_edge_bp = 10000
	emp.layer_mask = 15
	emp.friendly_fire = 0
	emp.nonlethal = 1
	emp.emp_unit_ticks = 160
	emp.emp_struct_ticks = 360
	emp.emp_class_mask = SimCombatConsts.EC_VEHICLE | SimCombatConsts.EC_AIRCRAFT | SimCombatConsts.EC_SHIP | SimCombatConsts.EC_STRUCTURE
	var idx: int = w.combat.tables_of(0).add_warhead(emp)
	w.run(5)
	var t0: int = w.tick
	w.combat.proj.spawn_remote(w, 0, -1, SimCombatConsts.PK_STRIKE, idx, 42 * C, 42 * C, 42 * C, 42 * C, 0, 10000, 0)
	w.step()
	for v: SimEntity in tanks:
		t.gt(v.combat.emp_until, t0, "vehicle disabled")
		t.check((v.flags & SimFlags.F_WEAPONS_OFF) != 0, "weapons off flag")
		t.gt(v.hp, 0, "not dead (non-lethal)")
	t.eq(ac.combat.emp_until - t0, 160 + 0, "aircraft: weapons off 160 ticks")
	t.check(w.get_entity(ac.id) != null and ac.combat.dying_until == 0, "an EMP never crashes aircraft")
	t.eq(inf.combat.emp_until, 0, "infantry unaffected")
	t.eq(ally.combat.emp_until, 0, "allies unaffected (friendly_fire 0)")
	var x_before: int = ac.x
	w.run(20)
	t.gt(ac.x, x_before, "the aircraft keeps flying")
	w.run(150)
	t.eq(tanks[0].combat.emp_until, 0, "recovered after 160 ticks")
	t.check((tanks[0].flags & SimFlags.F_WEAPONS_OFF) == 0, "weapons back on")


# ---------------------------------------------------------------------------------------------- determinism
func _death_mix() -> Array:
	var w: SimWorld = _world()
	var gen: SimEntity = w.spawn_structure(w.data.structure_idx(DefTestKit.S_GENERATOR), 1, 40 * C, 40 * C)
	var apc: SimEntity = _tank(w, 1, 30, 30)
	CombatWK.cd(w, apc).cargo_mode = SimCombatConsts.CARGO_EJECT_HURT
	CombatWK.cd(w, apc).eject_hurt_bp = 3000
	_passengers(w, apc, 2)
	var a: SimEntity = _tank(w, 1, 50, 50)
	var near: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_RIFLEMAN), 0, 40 * C + 900, 40 * C)
	w.combat.kill(w, gen, SimCombatConsts.CAUSE_DAMAGE, -1, 0)
	w.combat.kill(w, apc, SimCombatConsts.CAUSE_DAMAGE, -1, 0)
	w.run(30)
	w.combat.kill(w, a, SimCombatConsts.CAUSE_DAMAGE, -1, 0)
	w.run(100)
	return [w.checksum(), w.events.digest(), near.hp, w.checksum_log]


func test_death_sequence_is_deterministic(t: TestCtx) -> void:
	var r1: Array = _death_mix()
	var r2: Array = _death_mix()
	t.eq(r1[0], r2[0], "same final checksum")
	t.eq(r1[1], r2[1], "same event digest")
	t.eq(r1[3], r2[3], "same checkpoint chain")
	t.lt(int(r1[2]), 400, "and the chain blast did something")


# ---------------------------------------------------------------------------------------------- real balance data
## The derived death profiles and sortie numbers on the shipped balance sheets (no fixture).
func test_real_data_profiles(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	if not t.not_null(d, "real data"):
		return
	var pl: Array = []
	for i: int in 2:
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": "roster.napc.usa" if i == 0 else "roster.ae.vanilla",
			"team": i + 1, "color": i, "start": i, "handicap": 100})
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 9, "map": {"id": "real"}, "rules": {"victory": 0, "start_mode": 2, "neutral_structures": 0}, "players": pl})
	var w: SimWorld = SimWorld.create(d, cfg, SimTestKit.make_map(), CombatWK.ISOLATE)
	if not t.not_null(w, "world on real data"):
		return
	var nt: SimCombatTables = w.combat.neutral_tables
	var c_condor: SimCombatDef = nt.def_of(SimEntity.Kind.UNIT, d.unit_idx("unit.napc.condor_stealth_bomber"))
	t.eq([c_condor.air_style, c_condor.death_kind, c_condor.rearm_ticks], [SimCombatConsts.AS_BOMB_RUN, SimCombatConsts.DK_CRASH, 560], "bomber: bomb run, crash, 28 s rearm")
	t.gt(c_condor.crash_wh, -1, "with a crash warhead")
	var c_titan: SimCombatDef = nt.def_of(SimEntity.Kind.UNIT, d.unit_idx("unit.napc.titan_gunship"))
	t.eq([c_titan.air_style, c_titan.air_hover], [SimCombatConsts.AS_HOVER, 1], "gunship: hover style")
	var c_falcon: SimCombatDef = nt.def_of(SimEntity.Kind.UNIT, d.unit_idx("unit.napc.falcon_interceptor"))
	t.eq(c_falcon.air_style, SimCombatConsts.AS_DOGFIGHT, "interceptor: dogfight")
	var c_beaver: SimCombatDef = nt.def_of(SimEntity.Kind.UNIT, d.unit_idx("unit.napc.beaver_amphibious_apc"))
	t.eq([c_beaver.cargo_mode, c_beaver.eject_hurt_bp], [SimCombatConsts.CARGO_EJECT_HURT, 3000], "reinforced passenger protection: eject, hurt 30 %")
	var drone: SimCombatDef = nt.def_of(SimEntity.Kind.UNIT, d.unit_idx("unit.han.silkwing_drone_bomber"))
	t.eq(drone.death_kind, SimCombatConsts.DK_AIR_EXPLODE, "unmanned aircraft explode instead of crashing")
	var kinds: Dictionary = {}
	for c: SimCombatDef in nt.units:
		if c != null and c.wreck_hp_bp > 0:
			kinds[c.death_kind] = true
	t.eq(kinds.keys(), [SimCombatConsts.DK_VEHICLE], "wrecks only for land combat vehicles")
	var big: int = 0
	for s: SimCombatDef in nt.structures:
		if s != null and s.chain_wh >= 0:
			big += 1
	t.gt(big, 0, "some structures (generators, refineries, superweapons) have chain blasts")
	t.eq(w.combat.salvage_enabled, 1, "a roster with the salvage ability is in the match: wrecks are on")
