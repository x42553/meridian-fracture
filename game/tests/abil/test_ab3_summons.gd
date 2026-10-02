extends RefCounted
## AB-08 summons on the REAL balance data: the SimSummons primitive and its flags, Tempest drones and Dragonfall engines
## (S16), the UAV orbit, and the summon_orbit / zone-spawning unit abilities: Lagos drone (S20), portable cover, smoke
## launcher, sensor puck, decoy.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")

const CELL: int = 1024


func _c(cell: int) -> int:
	return cell * CELL + CELL / 2


func _use(w: SimWorld, e: SimEntity, slot: int, mode: int = 0, x: int = -1, y: int = -1) -> int:
	var c: SimCommand = SimCommand.from_ints(e.owner, SimCmd.use_ability(PackedInt32Array([e.id]), slot, mode, 0, x, y))
	c.actors = [e]
	var err: int = SimAbilityCmds.execute(w, c)
	return 0 if err == SimCommand.Err.OK else c.detail


func _sw(w: SimWorld, id: String) -> int:
	for i: int in w.data.superweapons.size():
		if w.data.superweapons[i].id == id:
			return i
	return -1


# ---- the primitive -------------------------------------------------------------------------------------------------

func test_spawn_flags_and_lifetime(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var uav: int = w.data.unit_idx("summon.napc.uav")
	var cap0: int = w.players[0].unit_count
	var flags: int = SimZoneConsts.SM_DEFAULT_POWER | SimZoneConsts.SM_SHOOTABLE | SimZoneConsts.SM_UNCONTROLLABLE | SimZoneConsts.SM_NO_CMD_FIELD | SimZoneConsts.SM_ENEMIES_ONLY
	var id: int = SimSummons.spawn(w, uav, 0, _c(20), _c(20), -1, flags, 100, SimZoneConsts.SD_STATIC, 0, 0, 0)
	t.check(id > 0, "spawned")
	var e: SimEntity = w.get_entity(id)
	t.check((e.flags & SimFlags.F_TEMPORARY) != 0 and (e.flags & SimFlags.F_SUMMONED) != 0, "temporary + summoned")
	t.check((e.flags & SimFlags.F_NO_UNIT_CAP) != 0, "no unit cap")
	t.check((e.flags & SimFlags.F_NO_SALVAGE) != 0 and (e.flags & SimFlags.F_NO_CAPTURE) != 0 and (e.flags & SimFlags.F_NO_REPAIR) != 0, "no salvage / capture / repair")
	t.check((e.combat.cflags & C.CF_SUMMONED) != 0 and (e.combat.cflags & C.CF_ENEMY_ONLY) != 0, "combat flags CF_SUMMONED / CF_ENEMY_ONLY")
	t.check((e.stats.flags & K.DF_NO_CMD_FIELD) != 0 and (e.stats.flags & K.DF_UNCONTROLLABLE) != 0, "DF_NO_CMD_FIELD / DF_UNCONTROLLABLE")
	t.eq(e.expire_tick, w.tick + 100, "lifetime in expire_tick")
	t.eq(w.players[0].unit_count, cap0, "the unit cap is untouched")
	t.check(not e._asset, "not an asset (victory weight 0)")
	t.eq(A.count_events(w, SimZoneConsts.EV_SUMMONED), 1, "EV_SUMMONED")
	# uncontrollable: player orders bounce, the domain's own orders pass
	t.eq(w.orders.issue(w, e, SimOrder.make(SimOrder.T_MOVE, 0, _c(30), _c(30)), SimOrder.QM_REPLACE), SimCommand.Err.DISABLED, "a player order is refused")
	# expiry: dies with Cause.EXPIRE and no wreck
	A.run(w, 101)
	t.check(w.get_entity(id) == null or (w.get_entity(id).flags & SimFlags.F_GONE) != 0, "gone after its lifetime")
	t.eq(A.count_events(w, SimZoneConsts.EV_SUMMON_EXPIRED), 1, "EV_SUMMON_EXPIRED")
	var wrecks: int = 0
	for x: SimEntity in w.entities:
		if x.kind == SimEntity.Kind.WRECK:
			wrecks += 1
	t.eq(wrecks, 0, "no wreck")


func test_uav_orbits_its_target_and_reveals(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "fog": true, "movement": false})
	A.spawn(w, "unit.napc.rifle_squad", 0, 6, 6)
	var uav: int = w.data.unit_idx("summon.napc.uav")
	var id: int = SimPowerFx.spawn_summon(w, uav, 0, _c(40), _c(40), 240, 0)
	var e: SimEntity = w.get_entity(id)
	t.eq(e.summon.driver, SimZoneConsts.SD_ORBITER, "aircraft use the orbiter driver")
	t.eq(e.summon.ar, 7168, "orbit radius from its summon_orbit ability (7 cells)")
	t.check(e.layer == SimEntity.Layer.AIR, "flies")
	A.run(w, 60)
	var dx: int = e.x - _c(40)
	var dy: int = e.y - _c(40)
	var d: int = Fp.isqrt(dx * dx + dy * dy)
	t.check(absi(d - 7168) < 800, "circling at the ring (%d)" % d)
	t.eq(e.summon.state, SimZoneConsts.SS_ORBIT, "in orbit")
	t.check(SimVision.is_visible(w, 0, e.x / CELL, e.y / CELL), "its own cell is visible to the owner")
	A.run(w, 60)
	t.check(SimVision.is_explored(w, 0, 40, 40), "the UAV's 7 cell sight swept the target cell")
	t.check(SimVision.is_explored(w, 0, 44, 40) and SimVision.is_explored(w, 0, 36, 40), "and both sides of it")
	A.run(w, 130)
	t.check(w.get_entity(id) == null or (w.get_entity(id).flags & SimFlags.F_GONE) != 0, "expired at 240 ticks")
	t.eq(w.zones.debug_validate(w), PackedStringArray(), "zones validate")


# ---- S16 Tempest ---------------------------------------------------------------------------------------------------

func test_s16_tempest_swarm(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.pd.vanilla", "roster.nec.vanilla"]})
	var sw: int = _sw(w, "superweapon.pd.tempest_swarm_hub")
	t.check(sw >= 0, "Tempest exists")
	var foe: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 50, 30)
	A.hold_fire(w)
	var cap0: int = w.players[0].unit_count
	var r: int = SimPowerFx.apply_superweapon(w, sw, 0, _c(50), _c(30), 0, _c(20), _c(30), 0)
	w.call("_flush_spawns")
	t.eq(r, SimZoneConsts.PW_OK, "activation accepted")
	var drones: Array[SimEntity] = []
	for e: SimEntity in w.units_of(0):
		if e.summon != null and e.summon.driver == SimZoneConsts.SD_SWARM:
			drones.append(e)
	t.eq(drones.size(), 24, "24 drones")
	var angles: Dictionary = {}
	for e2: SimEntity in drones:
		var dx: int = e2.x - _c(20)
		var dy: int = e2.y - _c(30)
		t.check(absi(Fp.isqrt(dx * dx + dy * dy) - 1536) < 16, "on the 1.5 cell ring")
		angles[Fp.atan2(dy, dx) / 8] = true
		t.check((e2.flags & SimFlags.F_TEMPORARY) != 0 and (e2.combat.cflags & C.CF_ENEMY_ONLY) != 0, "temporary, enemies only")
		t.check((e2.stats.flags & K.DF_NO_CMD_FIELD) != 0, "no command field")
	t.gt(angles.size(), 20, "spread around the ring (angle step 170)")
	t.eq(w.players[0].unit_count, cap0, "no unit cap use")
	t.eq(A.count_events(w, SimZoneConsts.EV_SWARM_LAUNCHED), 1, "EV_SWARM_LAUNCHED once")
	# fly in: every drone starts its 400 tick window on its own first arrival
	var born: int = w.tick
	A.run(w, 160)
	var attacking: int = 0
	for e3: SimEntity in drones:
		if (e3.flags & SimFlags.F_GONE) != 0:
			continue
		if e3.summon.state == SimZoneConsts.SS_ATTACK:
			attacking += 1
			t.eq(e3.expire_tick, mini(e3.summon.t0 + 400, born + 1200), "expires 400 ticks after its arrival (cap 1200)")
			t.check(e3.summon.t0 > born, "arrival after the flight")
	t.gt(attacking, 20, "the swarm has arrived (%d)" % attacking)
	# the window closes: all gone by spawn + 1200 at the latest
	A.run(w, 1100)
	var alive: int = 0
	for e4: SimEntity in drones:
		if (e4.flags & SimFlags.F_GONE) == 0:
			alive += 1
	t.eq(alive, 0, "every drone is gone")
	t.lt(foe.hp, foe.hp_max, "the swarm hurt the target it was sent to")
	t.check((foe.flags & SimFlags.F_GONE) != 0 or foe.hp < foe.hp_max, "target damaged or destroyed")


# ---- S16 Dragonfall ------------------------------------------------------------------------------------------------

func test_s16_dragonfall_capsules_become_engines(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.han.vanilla", "roster.nec.vanilla"]})
	var sw: int = _sw(w, "superweapon.han.dragonfall_field_foundry")
	var foe: SimEntity = A.structure(w, "structure.nec.relay", 1, 44, 30)
	var cap0: int = w.players[0].unit_count
	t.eq(SimPowerFx.apply_superweapon(w, sw, 0, _c(30), _c(30), 0, _c(10), _c(10), 500), SimZoneConsts.PW_OK, "accepted")
	w.call("_flush_spawns")
	var caps: Array[SimEntity] = []
	for e: SimEntity in w.units_of(0):
		if e.summon != null and e.summon.driver == SimZoneConsts.SD_CAPSULE:
			caps.append(e)
	t.eq(caps.size(), 3, "three capsules")
	var seen_ang: Dictionary = {}
	for c: SimEntity in caps:
		var dx: int = c.x - _c(30)
		var dy: int = c.y - _c(30)
		t.check(absi(Fp.isqrt(dx * dx + dy * dy) - 2560) < 16, "on the 2.5 cell ring")
		seen_ang[(Fp.atan2(dy, dx) - 500) & 4095] = true
	t.eq(seen_ang.size(), 3, "three distinct angles: base + k * 1365")
	caps[0].hp = caps[0].hp_max / 2  # hit while assembling: the fraction survives
	var frac_hp: int = caps[0].hp
	var frac_max: int = caps[0].hp_max
	A.run(w, 99)
	for c2: SimEntity in caps:
		t.check((c2.flags & SimFlags.F_GONE) == 0, "still a capsule at +99")
	A.run(w, 3)
	var engines: Array[SimEntity] = []
	for e2: SimEntity in w.units_of(0):
		if e2.summon != null and e2.summon.driver == SimZoneConsts.SD_ENGINE and (e2.flags & SimFlags.F_GONE) == 0:
			engines.append(e2)
	t.eq(engines.size(), 3, "three engines at +100")
	var half_engine: SimEntity = null
	for eg: SimEntity in engines:
		if eg.hp < eg.hp_max:
			half_engine = eg
	t.check(half_engine != null, "the damaged capsule gave a damaged engine")
	if half_engine != null:
		var want: int = (half_engine.hp_max * frac_hp * 2 + frac_max) / (frac_max * 2)
		t.eq(half_engine.hp, want, "hp fraction preserved (half-up)")
	for eg2: SimEntity in engines:
		t.eq(eg2.expire_tick, 100 + 1200, "engines live 1200 ticks from the assembly at tick 100")
		t.check((eg2.combat.cflags & C.CF_ENEMY_ONLY) != 0, "enemies only")
		t.check((eg2.stats.flags & K.DF_UNCONTROLLABLE) != 0, "uncontrollable")
	t.eq(w.players[0].unit_count, cap0, "no unit cap use")
	t.eq(A.count_events(w, SimZoneConsts.EV_ENGINE_ASSEMBLED), 3, "EV_ENGINE_ASSEMBLED x3")
	A.run(w, 1250)
	for eg3: SimEntity in engines:
		t.check((eg3.flags & SimFlags.F_GONE) != 0, "engine expired")
	t.check((foe.flags & SimFlags.F_GONE) != 0 or foe.hp < foe.hp_max, "the engines marched on the nearest enemy structure and hurt it")


# ---- S20 Lagos drone -----------------------------------------------------------------------------------------------

func test_s20_lagos_drone_respawn(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.ae.kongo", "roster.nec.vanilla"], "movement": false})
	var lagos: SimEntity = A.spawn(w, "unit.ae.lagos_drone_guard", 0, 30, 30)
	var inf: SimEntity = A.spawn(w, "unit.ae.civic_rifle_team", 0, 31, 31)
	A.hold_fire(w)
	A.run(w, 2)
	var s: int = lagos.abil.slot_of_kind(K.AK_SUMMON_ORBIT)
	t.check(s >= 0, "the carrier has a summon_orbit slot")
	var b: int = s * K.SLOT_STRIDE
	t.eq(lagos.abil.slots[b + K.SL_STATE], SimZoneConsts.SA_ACTIVE, "drone active")
	var drone: SimEntity = w.get_entity(lagos.abil.slots[b + K.SL_AUX0])
	t.check(drone != null and drone.summon.driver == SimZoneConsts.SD_ATTACHED, "an attached repair drone")
	t.eq(drone.parent, lagos.id, "parent set")
	t.check((drone.flags & SimFlags.F_TETHERED) != 0, "tethered to the parent")
	A.run(w, 20)
	var dx: int = drone.x - lagos.x
	var dy: int = drone.y - lagos.y
	t.check(absi(Fp.isqrt(dx * dx + dy * dy) - 1536) < 400, "orbits at 1.5 cells")
	# repair works while the drone lives: 1 % / s free
	inf.hp = inf.hp_max / 2
	var hp0: int = inf.hp
	A.run_to(w, 100)
	t.gt(inf.hp, hp0, "the damaged squad is healed while the drone lives")
	# drone shot down at tick 300
	A.run_to(w, 300)
	var died_at: int = w.tick
	w.kill(drone, SimWorld.Cause.SCRIPT)
	A.run(w, 2)
	t.eq(lagos.abil.slots[b + K.SL_STATE], SimZoneConsts.SA_RESPAWNING, "slot RESPAWNING")
	t.eq(lagos.abil.slots[b + K.SL_T_END], died_at + 1800, "for 1800 ticks (90 s)")
	t.check((lagos.abil.slots[lagos.abil.slot_of_kind(K.AK_REPAIR) * K.SLOT_STRIDE + K.SL_FLAGS] & K.SF_SUSPENDED) != 0, "repair suspended without the drone")
	var hp1: int = inf.hp
	A.run(w, 200)
	t.eq(inf.hp, hp1, "no healing while the drone is down")
	A.run_to(w, died_at + 1800 + 2)
	t.eq(lagos.abil.slots[b + K.SL_STATE], SimZoneConsts.SA_ACTIVE, "respawned")
	var d2: SimEntity = w.get_entity(lagos.abil.slots[b + K.SL_AUX0])
	t.check(d2 != null and d2.id != drone.id, "a new drone")
	inf.hp = inf.hp_max / 2
	var hp2: int = inf.hp
	A.run(w, 200)
	t.gt(inf.hp, hp2, "healing resumes")
	# parent death removes the drone
	w.kill(lagos, SimWorld.Cause.SCRIPT)
	A.run(w, 3)
	t.check(w.get_entity(d2.id) == null or (d2.flags & SimFlags.F_GONE) != 0, "the drone dies with its parent")


# ---- unit abilities ------------------------------------------------------------------------------------------------

func test_smoke_launcher_naga(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.sap.vanilla", "roster.nec.vanilla"], "movement": false})
	var naga: SimEntity = A.spawn(w, "unit.sap.naga_amphibious_carrier", 0, 30, 30)
	var s: int = naga.abil.slot_of_kind(K.AK_SMOKE_LAUNCHER)
	t.check(s >= 0, "smoke slot")
	t.eq(_use(w, naga, s), 0, "launch accepted")
	t.eq(w.zones.zone_count(), 1, "a smoke zone")
	var z: SimZone = w.zones.active_zones()[0]
	t.eq(z.radius, 4096, "radius 4 cells")
	t.eq(z.t_end - z.t_start, 120, "120 ticks")
	t.eq(z.src_eid, naga.id, "created by the Naga")
	t.eq(_use(w, naga, s), SimAbilityEvents.RJ_COOLDOWN, "cooldown 800")
	A.run(w, 799)
	t.eq(_use(w, naga, s), SimAbilityEvents.RJ_COOLDOWN, "still cooling at 799")
	A.run(w, 2)
	t.eq(A.count_events(w, K.EV_ABILITY_READY), 1, "EV_ABILITY_READY")
	t.eq(_use(w, naga, s, 0, _c(60), _c(60)), SimAbilityEvents.RJ_OUT_OF_RANGE, "too far")
	t.eq(_use(w, naga, s, 0, _c(35), _c(30)), 0, "ready again, aimed launch")
	t.eq(w.zones.active_zones()[0].x, _c(35), "at the aimed point")


func test_cover_builder_vanguard(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.mexico", "roster.nec.vanilla"], "movement": false})
	var v: SimEntity = A.spawn(w, "unit.napc.vanguard_rifle_squad", 0, 30, 30)
	A.hold_fire(w)
	A.run(w, 3)
	var s: int = v.abil.slot_of_kind(K.AK_PORTABLE_COVER)
	t.eq(_use(w, v, s), 0, "build starts")
	t.eq(v.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], SimZoneConsts.SA_BUILDING, "BUILDING")
	t.check(w.abilities.is_immobile(v), "held while building")
	t.eq(_use(w, v, s), SimAbilityEvents.RJ_BAD_STATE, "cannot start a second build")
	A.run(w, 79)
	t.eq(w.zones.zone_count(), 0, "no zone before build_t = 80")
	A.run(w, 2)
	t.eq(w.zones.zone_count(), 1, "the cover stands at tick 80")
	var z: SimZone = w.zones.active_zones()[0]
	t.eq(z.t_end - z.t_start, 900, "900 ticks")
	t.check(z.has_flag(SimZoneConsts.ZF_BUILDER_ONLY), "Vanguard cover belongs to its builder (pack_t > 0)")
	t.check(not w.abilities.is_immobile(v), "free again")
	A.run(w, 8)
	t.eq(z.members, PackedInt32Array([v.id]), "the builder occupies it")
	t.eq(SimCombatMods.sum_bp(v.combat, C.STAT_TAKEN, w.tick, C.DT_BULLET, C.DC_DIRECT), 2000, "Vanguard cover: 20 % bullet")
	# a second rifle squad standing there does not get it
	var other: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 30, 31)
	A.hold_fire(w)
	A.run(w, 8)
	t.eq(SimCombatMods.sum_bp(other.combat, C.STAT_TAKEN, w.tick, C.DT_BULLET, C.DC_DIRECT), 0, "only the builder occupies")
	# a new cover ends the previous piece
	var first_id: int = z.id
	t.eq(_use(w, v, s), 0, "build again")
	A.run(w, 82)
	t.check(w.zones.get_zone(first_id) == null, "one piece per builder")
	t.eq(w.zones.zone_count(), 1, "exactly one cover")
	# pack: a move order holds the unit for pack_t = 40, then the cover is gone
	w.abilities.request_pack(v)
	t.check(w.abilities.is_immobile(v), "packing holds the unit")
	t.eq(v.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], SimZoneConsts.SA_PACKING, "PACKING")
	A.run(w, 41)
	t.eq(w.zones.zone_count(), 0, "cover removed after the pack time")
	t.check(not w.abilities.is_immobile(v), "free")
	t.eq(v.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], SimZoneConsts.SA_READY, "READY again")


func test_alpine_shelter_uses_the_builders_magnitude(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.nec.alpine_brotherhood", "roster.napc.usa"], "movement": false})
	var alp: SimEntity = A.spawn(w, "unit.nec.alpine_pioneer", 0, 30, 30)
	A.hold_fire(w)
	A.run(w, 3)
	var s: int = alp.abil.slot_of_kind(K.AK_PORTABLE_COVER)
	t.eq(_use(w, alp, s), 0, "build")
	A.run(w, 90)
	var z: SimZone = w.zones.active_zones()[0]
	A.run(w, 8)
	t.eq(z.members, PackedInt32Array([alp.id]), "occupied")
	t.eq(SimCombatMods.sum_bp(alp.combat, C.STAT_TAKEN, w.tick, C.DT_BULLET, C.DC_DIRECT), 2500, "Alpine shelter: 25 % (the unit's own resist_bp)")
	A.place(w, alp, 30, 50)
	A.run(w, 12)
	t.eq(SimCombatMods.sum_bp(alp.combat, C.STAT_TAKEN, w.tick, C.DT_BULLET, C.DC_DIRECT), 0, "released when leaving")


func test_cover_moving_builder_is_refused(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.nec.vanilla", "roster.napc.usa"], "movement": false})
	var sap: SimEntity = A.spawn(w, "unit.nec.sapper", 0, 30, 30)
	var s: int = sap.abil.slot_of_kind(K.AK_PORTABLE_COVER)
	sap.flags |= SimFlags.F_MOVING
	t.eq(_use(w, sap, s), SimAbilityEvents.RJ_NOT_STATIONARY, "stationary_only")
	sap.flags &= ~SimFlags.F_MOVING
	A.run(w, 3)
	t.eq(_use(w, sap, s), 0, "standing: accepted")
	t.eq(sap.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], SimZoneConsts.SA_BUILDING, "building")
	w.abilities.request_pack(sap)  # a move order while building drops the piece
	t.eq(sap.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], SimZoneConsts.SA_READY, "back to READY")
	t.check(not w.abilities.is_immobile(sap), "free to move")
	A.run(w, 90)
	t.eq(w.zones.zone_count(), 0, "no cover appears from a dropped build")
	t.eq(_use(w, sap, s), 0, "and it can be started again")
	A.run(w, 82)
	t.eq(w.zones.zone_count(), 1, "the Sapper's cover stands")
	w.abilities.request_pack(sap)
	t.check(not w.abilities.is_immobile(sap), "pack_t = 0: a move order leaves the piece standing and is not held")
	t.eq(w.zones.zone_count(), 1, "still standing")


func test_cover_expires_and_can_be_rebuilt(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.nec.vanilla", "roster.napc.usa"], "movement": false})
	var sap: SimEntity = A.spawn(w, "unit.nec.sapper", 0, 30, 30)
	var s: int = sap.abil.slot_of_kind(K.AK_PORTABLE_COVER)
	A.run(w, 3)
	t.eq(_use(w, sap, s, 0, 0, 0), 0, "a caller that leaves the point at (0, 0) means no point")
	A.run(w, 85)
	t.eq(w.zones.zone_count(), 1, "cover stands")
	t.eq(sap.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], SimZoneConsts.SA_ACTIVE, "ACTIVE")
	A.run(w, 900)
	t.eq(w.zones.zone_count(), 0, "it lasted 900 ticks")
	t.eq(sap.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], SimZoneConsts.SA_READY, "the slot is READY again")
	t.eq(_use(w, sap, s), 0, "and can build once more")


func test_sensor_puck_civic(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.ae.kongo", "roster.nec.vanilla"], "movement": false})
	var u: SimEntity = A.spawn(w, "unit.ae.civic_rifle_team", 0, 30, 30)
	var s: int = u.abil.slot_of_kind(K.AK_SENSOR_PUCK)
	t.eq(_use(w, u, s, 0, _c(34), _c(30)), 0, "puck placed")
	var z: SimZone = w.zones.active_zones()[0]
	t.eq(z.kind, DefEnums.ZoneKind.PUCK, "PUCK zone")
	t.eq(z.x, _c(34), "where aimed")
	t.check(z.body_eid > 0, "destructible body")
	t.eq(_use(w, u, s), SimAbilityEvents.RJ_COOLDOWN, "cooldown 600")
	A.run(w, 401)
	t.eq(w.zones.zone_count(), 0, "lasts 400 ticks")
	t.eq(_use(w, u, s), SimAbilityEvents.RJ_COOLDOWN, "still cooling at 401")
	A.run(w, 200)
	t.eq(_use(w, u, s), 0, "ready after 600")


func test_decoy_echo_team(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.def.vanilla", "roster.nec.vanilla"], "movement": false})
	var u: SimEntity = A.spawn(w, "unit.def.echo_team", 0, 30, 30)
	var s: int = u.abil.slot_of_kind(K.AK_DECOY_SPAWN)
	t.check(s >= 0, "decoy slot")
	t.eq(_use(w, u, s, 0, _c(33), _c(30)), 0, "decoy placed")
	var z: SimZone = w.zones.active_zones()[0]
	t.eq(z.members.size(), 1, "one decoy")
	var d: SimEntity = w.get_entity(z.members[0])
	t.check((d.flags & SimFlags.F_DECOY) != 0, "flagged decoy")
	t.check(d.combat.mods.size() >= 0, "combat component")
	t.eq(_use(w, u, s), SimAbilityEvents.RJ_COOLDOWN, "cooldown 800 / one active")
	A.run(w, 601)
	t.eq(w.zones.zone_count(), 0, "the decoy lasts 600 ticks")
	t.check(w.get_entity(d.id) == null or (w.get_entity(d.id).flags & SimFlags.F_GONE) != 0, "and dies with the zone")
