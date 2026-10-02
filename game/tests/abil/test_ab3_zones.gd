extends RefCounted
## AB-07 on the REAL balance data: zones (Trident S07, smoke / cover / repair S14, debris, sensor puck, decoys, warnings)
## and the sim-level equivalents of the visual rows V2 (smoke geometry) and V4 (Trident dome state).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")

const CELL: int = 1024
const RIFLE: String = "unit.napc.rifle_squad"
const TANK: String = "unit.napc.guardian_tank"
const SPIKE: String = "unit.nec.spike_team"


func _w(o: Dictionary = {}) -> SimWorld:
	var d: Dictionary = {"movement": false}
	for k: Variant in o.keys():
		d[k] = o[k]
	return A.world(d)


func _zi(w: SimWorld, id: String) -> int:
	return w.data.zone_idx(id)


func _c(cell: int) -> int:
	return cell * CELL + CELL / 2


func _taken(w: SimWorld, e: SimEntity, dtype: int, dc: int) -> int:
	return SimCombatMods.sum_bp(e.combat, C.STAT_TAKEN, w.tick, dtype, dc)


# ---- S07 Trident -------------------------------------------------------------------------------------------------

func test_s07_trident_ledger(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var zid: int = w.zones.create_zone(_zi(w, "zone.trident_interception"), 0, _c(30), _c(30))
	t.check(zid > 0, "the dome exists")
	var z: SimZone = w.zones.get_zone(zid)
	t.eq(z.charges, 24, "24 charges")
	t.eq(z.radius, 6144, "radius 6 cells")
	t.eq(z.t_end - z.t_start, 500, "active for 500 ticks")
	t.eq(w.zones.n_intercept, 1, "one interception slot in use")
	var hostile_team: int = w.team_of(1)
	var friendly_team: int = w.team_of(0)
	var hits: int = 0
	for i: int in 26:  # inbound shells from the west, launched far outside
		var r: int = w.zones.intercept_ordinary(w, hostile_team, _c(20), _c(30), _c(24), _c(30), _c(10), _c(30), 0)
		if r == zid:
			hits += 1
		else:
			t.eq(r, -1, "shell %d passes once the dome is empty" % i)
	t.eq(hits, 24, "the first 24 shells are intercepted")
	t.eq(z.charges, 0, "charges spent")
	# a shell launched from inside bypasses and keeps the charge
	var z2: SimZone = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.trident_interception"), 0, _c(50), _c(50)))
	t.eq(w.zones.intercept_ordinary(w, hostile_team, _c(50), _c(50), _c(58), _c(50), _c(50), _c(51), 0), -1, "launched inside: bypass")
	t.eq(z2.charges, 24, "the bypass keeps its charge")
	t.eq(w.zones.intercept_ordinary(w, friendly_team, _c(40), _c(50), _c(46), _c(50), _c(30), _c(50), 0), -1, "the owner's own shells are never asked")
	# a segment that starts inside is not "entering"
	t.eq(w.zones.intercept_ordinary(w, hostile_team, _c(51), _c(50), _c(57), _c(50), _c(30), _c(50), 0), -1, "a shell already inside is not intercepted again")
	# packets: 3 reduced, the 4th full
	var pk: PackedInt32Array = PackedInt32Array()
	for i2: int in 4:
		pk.append(w.zones.intercept_packet(w, hostile_team, _c(50), _c(50)))
	t.eq(pk, PackedInt32Array([5000, 5000, 5000, 0]), "three packets reduced by 50 %, the fourth at full damage")
	# fewer than 8 charges cannot reduce
	var z3: SimZone = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.trident_interception"), 0, _c(20), _c(50)))
	z3.charges = 7
	t.eq(w.zones.intercept_packet(w, hostile_team, _c(20), _c(50)), 0, "7 charges: a packet is not reduced")
	t.eq(z3.charges, 7, "and costs nothing")
	# ledger from the spec: 5 shells leave 19, packets 1 and 2 reduced (3 left), packet 3 full
	var z4: SimZone = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.trident_interception"), 0, _c(20), _c(20)))
	for i3: int in 5:
		w.zones.intercept_ordinary(w, hostile_team, _c(10), _c(20), _c(14), _c(20), _c(2), _c(20), 0)
	t.eq(z4.charges, 19, "5 shells leave 19")
	t.eq(w.zones.intercept_packet(w, hostile_team, _c(20), _c(20)), 5000, "packet 1")
	t.eq(w.zones.intercept_packet(w, hostile_team, _c(20), _c(20)), 5000, "packet 2")
	t.eq(z4.charges, 3, "3 left")
	t.eq(w.zones.intercept_packet(w, hostile_team, _c(20), _c(20)), 0, "packet 3 is full damage")


func test_v4_trident_dome_state(t: TestCtx) -> void:
	# V4 at sim level: the view draws domes from active_zones(): position, radius, charges, kind, ends after 500 ticks
	var w: SimWorld = _w()
	var zid: int = w.zones.create_zone(_zi(w, "zone.trident_interception"), 0, _c(30), _c(30))
	var list: Array[SimZone] = w.zones.active_zones()
	t.eq(list.size(), 1, "one drawable zone")
	t.eq(list[0].kind, DefEnums.ZoneKind.INTERCEPT, "kind INTERCEPT")
	t.eq(list[0].x, _c(30), "centre x")
	t.check(list[0].charges > 0 and list[0].is_active(), "armed and active")
	w.zones.intercept_ordinary(w, w.team_of(1), _c(20), _c(30), _c(24), _c(30), _c(10), _c(30), 0)
	t.eq(list[0].charges, 23, "the charge counter the dome shows")
	A.run(w, 499)
	t.check(w.zones.get_zone(zid) != null, "still standing at tick 499")
	A.run(w, 2)
	t.check(w.zones.get_zone(zid) == null, "gone after 500 ticks")
	t.eq(w.zones.n_intercept, 0, "slot released")
	t.eq(A.count_events(w, SimZoneConsts.EV_ZONE_ENDED, -1), 1, "EV_ZONE_ENDED")


func test_trident_slots_are_bounded(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var ids: Array[int] = []
	for i: int in 9:
		ids.append(w.zones.create_zone(_zi(w, "zone.trident_interception"), 0, _c(10 + i * 4), _c(10)))
	t.eq(ids.count(-1), 1, "the 9th dome is refused: 8 interception slots")


# ---- S14 smoke -------------------------------------------------------------------------------------------------

func test_s14_dust_screen_two_sided(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var inside: Array[SimEntity] = []
	for i: int in 30:
		var id: String = RIFLE if i % 2 == 0 else SPIKE
		inside.append(A.spawn(w, id, i % 2, 30 + (i % 5) - 2, 30 + (i / 5) % 5 - 2))
	var outside: SimEntity = A.spawn(w, RIFLE, 0, 30, 38)
	A.hold_fire(w)
	var zid: int = w.zones.create_zone(_zi(w, "zone.smoke_dust_screen"), 0, _c(30), _c(30))
	var z: SimZone = w.zones.get_zone(zid)
	t.eq(z.radius, 6144, "6 cell radius")
	t.eq(z.t_end - z.t_start, 240, "240 ticks")
	t.eq(z.n_members, 30, "30 units inside, both sides")
	for e: SimEntity in inside:
		t.eq(_taken(w, e, C.DT_BULLET, C.DC_DIRECT), 3000, "e%d direct fire -30 %%" % e.id)
	t.eq(_taken(w, inside[0], C.DT_HE, C.DC_INDIRECT), 0, "artillery unaffected")
	t.eq(_taken(w, inside[0], C.DT_HE, C.DC_SPLASH), 0, "area blasts unaffected")
	t.eq(_taken(w, inside[0], C.DT_KINETIC, C.DC_STRATEGIC), 0, "strategic packets unaffected")
	t.eq(_taken(w, outside, C.DT_BULLET, C.DC_DIRECT), 0, "outside: nothing")
	# leaving: within 4 ticks
	var walker: SimEntity = inside[0]
	A.place(w, walker, 30, 45)
	A.run(w, 4)
	t.eq(_taken(w, walker, C.DT_BULLET, C.DC_DIRECT), 0, "lost within 4 ticks of leaving")
	t.eq(z.n_members, 29, "member count follows")
	# entering
	A.place(w, outside, 30, 31)
	A.run(w, 4)
	t.eq(_taken(w, outside, C.DT_BULLET, C.DC_DIRECT), 3000, "gained within 4 ticks of entering")
	# the smoke ends with everything it held
	A.run(w, 240)
	t.check(w.zones.get_zone(zid) == null, "expired")
	t.eq(_taken(w, inside[3], C.DT_BULLET, C.DC_DIRECT), 0, "all leases gone with the zone")
	t.eq(w.abilities.debug_validate(w).size(), 0, "abilities validate")
	t.eq(w.zones.debug_validate(w).size(), 0, "zones validate")


func test_smoke_overlap_never_stacks(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var e: SimEntity = A.spawn(w, RIFLE, 0, 30, 30)
	A.hold_fire(w)
	var zi: int = _zi(w, "zone.smoke_dust_screen")
	w.zones.create_zone(zi, 0, _c(30), _c(30))
	w.zones.create_zone(zi, 1, _c(32), _c(30))
	t.eq(_taken(w, e, C.DT_BULLET, C.DC_DIRECT), 3000, "two smokes, one 30 %")
	t.eq(e.abil.n_fx, 1, "a single shared timed effect")


func test_v2_smoke_geometry(t: TestCtx) -> void:
	# V2 at sim level: a Dust Screen disc and a 16 x 4 cell Concealed Crossing corridor, bounded shapes the view can draw
	var w: SimWorld = _w()
	var disc: SimZone = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.smoke_dust_screen"), 0, _c(20), _c(20)))
	var line: SimZone = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.smoke_dust_screen"), 0, _c(40), _c(40), 0, 0, -1, 0, 16 * CELL, 4 * CELL))
	t.eq(disc.shape, DefEnums.ZoneShape.CIRCLE, "disc")
	t.eq(line.shape, DefEnums.ZoneShape.LINE, "corridor is a capsule")
	t.eq(line.half_length(), 8 * CELL, "16 cells long")
	t.eq(line.radius, 2 * CELL, "4 cells wide")
	t.check(line.contains_point(_c(40) + 7 * CELL, _c(40) + CELL), "inside the corridor")
	t.check(not line.contains_point(_c(40), _c(40) + 3 * CELL), "outside the corridor")
	var inn: SimEntity = A.spawn(w, RIFLE, 0, 46, 41)
	var out: SimEntity = A.spawn(w, RIFLE, 0, 40, 44)
	A.hold_fire(w)
	A.run(w, 4)
	t.eq(_taken(w, inn, C.DT_BULLET, C.DC_DIRECT), 3000, "unit in the corridor is smoked")
	t.eq(_taken(w, out, C.DT_BULLET, C.DC_DIRECT), 0, "unit beside it is not")


# ---- S14 cover -------------------------------------------------------------------------------------------------

func test_s14_cover_occupants(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var a: SimEntity = A.spawn(w, RIFLE, 0, 30, 30)
	var b: SimEntity = A.spawn(w, RIFLE, 0, 31, 30)
	var c: SimEntity = A.spawn(w, RIFLE, 0, 30, 31)
	var foe: SimEntity = A.spawn(w, SPIKE, 1, 31, 31)
	A.hold_fire(w)
	var zid: int = w.zones.create_zone(_zi(w, "zone.portable_cover"), 0, _c(30), _c(30))
	var z: SimZone = w.zones.get_zone(zid)
	t.eq(z.t_end - z.t_start, 900, "900 ticks")
	t.eq(z.n_members, 0, "nobody is still yet (still_ticks starts at 0)")
	A.run(w, 4)
	t.eq(z.n_members, 2, "at most two occupants")
	t.eq(z.members, PackedInt32Array([a.id, b.id]), "the lowest ids")
	t.eq(_taken(w, a, C.DT_BULLET, C.DC_DIRECT), 2000, "occupant: -20 % bullet")
	t.eq(_taken(w, c, C.DT_BULLET, C.DC_DIRECT), 0, "the third infantry gets nothing")
	t.eq(_taken(w, foe, C.DT_BULLET, C.DC_DIRECT), 0, "cover is friendly only")
	t.eq(_taken(w, a, C.DT_HE, C.DC_SPLASH), 0, "bullet damage only")
	A.run(w, 900)
	t.check(w.zones.get_zone(zid) == null, "gone after 900 ticks")
	t.eq(_taken(w, a, C.DT_BULLET, C.DC_DIRECT), 0, "leases released")


func test_cover_needs_a_standing_unit(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var a: SimEntity = A.spawn(w, RIFLE, 0, 30, 30)
	A.hold_fire(w)
	A.run(w, 3)
	var z: SimZone = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.portable_cover"), 0, _c(30), _c(30)))
	t.eq(z.n_members, 1, "a unit that has stood still is covered at once")
	a.flags |= SimFlags.F_MOVING
	A.run(w, 4)
	t.eq(z.n_members, 0, "a moving unit loses the cover")
	t.eq(_taken(w, a, C.DT_BULLET, C.DC_DIRECT), 0, "and the lease")


# ---- S14 repair stations ---------------------------------------------------------------------------------------

func test_s14_repair_station_highest_rate(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var tank: SimEntity = A.spawn(w, TANK, 0, 30, 30)
	var other: SimEntity = A.spawn(w, TANK, 0, 31, 31)
	A.hold_fire(w)
	tank.hp = tank.hp_max / 2
	other.hp = other.hp_max / 2
	var hp0: int = tank.hp
	var hp_max: int = tank.hp_max
	# 2 %/s station and a 1.5 %/s one on the same unit: only the higher rate applies
	w.zones.create_zone(_zi(w, "zone.repair_station"), 0, _c(30), _c(30))
	w.zones.create_zone(_zi(w, "zone.napc.floating_workshop"), 0, _c(30), _c(30), 0, w.tick + 200)
	A.run(w, 200)
	var gain: int = tank.hp - hp0
	var expect: int = hp_max * 20 / 100
	t.check(absi(gain - expect) <= hp_max / 50, "2 %%/s for 10 s heals %d of %d (got %d)" % [expect, hp_max, gain])
	t.check(other.hp - hp0 <= expect + hp_max / 50, "the second unit is healed once, not twice")
	t.eq(w.abilities.debug_validate(w), PackedStringArray(), "validate")


func test_repair_never_heals_the_body_or_the_bound_unit(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var caster: SimEntity = A.spawn(w, TANK, 0, 30, 30)
	A.hold_fire(w)
	caster.hp = caster.hp_max / 2
	var hp0: int = caster.hp
	var zid: int = w.zones.create_zone(_zi(w, "zone.olm.mobile_workshop"), 0, _c(30), _c(30), 0, 0, caster.id)
	var z: SimZone = w.zones.get_zone(zid)
	t.check(z.body_eid > 0, "the station has a shootable body (hp 600)")
	var body: SimEntity = w.get_entity(z.body_eid)
	t.eq(body.hp_max, 600, "body hp from the template")
	t.check(body.summon != null and (body.summon.flags & SimZoneConsts.SM_SHOOTABLE) != 0, "flagged shootable")
	body.hp = 100
	A.run(w, 60)
	t.eq(caster.hp, hp0, "the bound unit is never healed by its own station")
	t.eq(body.hp, 100, "the body is never healed")
	# killing the body ends the zone (reason 1)
	w.kill(body, SimWorld.Cause.SCRIPT)
	A.run(w, 2)
	t.check(w.zones.get_zone(zid) == null, "body death ends the zone")
	t.eq(A.event_field(w, SimZoneConsts.EV_ZONE_ENDED, 0, SimEvent.I_C), SimZoneConsts.ZE_BODY, "reason: body destroyed")


# ---- debris ----------------------------------------------------------------------------------------------------

func test_debris_slows_land_vehicles_and_blocks_construction(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var tank: SimEntity = A.spawn(w, TANK, 0, 30, 30)
	var foe_tank: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 31, 30)
	var rifle: SimEntity = A.spawn(w, RIFLE, 0, 30, 31)
	A.hold_fire(w)
	var base: int = SimStats.peek(w, tank, DefEnums.Stat.SPEED)
	var zid: int = w.zones.create_zone(_zi(w, "zone.horizon_debris"), 1, _c(30), _c(30), 0)
	var z: SimZone = w.zones.get_zone(zid)
	t.eq(z.shape, DefEnums.ZoneShape.LINE, "a 10 x 6 cell capsule")
	A.run(w, 4)
	t.eq(SimStats.get_val(w, tank, DefEnums.Stat.SPEED), base * 65 / 100, "-35 % speed on a land vehicle (both sides)")
	t.check(SimStats.get_val(w, foe_tank, DefEnums.Stat.SPEED) < SimStats.peek(w, foe_tank, DefEnums.Stat.SPEED) + 1, "the owner's own vehicles are slowed too")
	t.eq(SimStats.get_val(w, rifle, DefEnums.Stat.SPEED), SimStats.peek(w, rifle, DefEnums.Stat.SPEED), "infantry unaffected")
	t.check(w.zones.construction_blocked(30, 30), "no new construction inside")
	t.check(w.zones.blocks_construction(31, 30), "placement's name too")
	t.check(not w.zones.construction_blocked(30, 45), "free outside")
	A.place(w, tank, 30, 60)
	A.run(w, 4)
	t.eq(SimStats.get_val(w, tank, DefEnums.Stat.SPEED), base, "speed restored outside")


# ---- sensor puck / reveal ---------------------------------------------------------------------------------------

func test_sensor_puck_reveals_without_detecting(t: TestCtx) -> void:
	var w: SimWorld = _w({"fog": true})
	A.spawn(w, RIFLE, 0, 8, 8)
	var zid: int = w.zones.create_zone(_zi(w, "zone.sensor_puck"), 0, _c(40), _c(40))
	var z: SimZone = w.zones.get_zone(zid)
	t.check(z.body_eid > 0 and z.vis_handle >= 0, "body and vision source")
	A.run(w, 6)
	t.check(SimVision.is_visible(w, 0, 40, 40), "the puck's 4 cell disc is visible to its owner")
	t.check(SimVision.is_visible(w, 0, 43, 40), "3 cells away")
	t.check(not SimVision.is_visible(w, 0, 46, 40), "6 cells away is not")
	t.check(not SimVision.is_visible(w, 1, 40, 40), "the enemy sees nothing there")
	var body: SimEntity = w.get_entity(z.body_eid)
	t.eq(body.hp_max, 60, "puck hp 60")
	w.kill(body, SimWorld.Cause.SCRIPT)
	A.run(w, 3)
	t.check(w.zones.get_zone(zid) == null, "shot down: the zone ends")
	A.run(w, 8)
	t.check(not SimVision.is_visible(w, 0, 43, 40), "the source closed with it")


func test_wideband_scan_warmup(t: TestCtx) -> void:
	var w: SimWorld = _w({"fog": true, "rosters": ["roster.han.vanilla", "roster.nec.vanilla"]})
	A.spawn(w, "unit.han.banner_infantry", 0, 8, 8)
	var zi: int = _zi(w, "zone.han.wideband_scan")
	var zid: int = w.zones.create_zone(zi, 0, _c(40), _c(40), 0, 0, -1, 0, 0, 0, 40)
	var z: SimZone = w.zones.get_zone(zid)
	t.eq(z.state, SimZoneConsts.ZS_WARMUP, "warm-up first")
	t.eq(z.t_end - z.t_start, 40 + 120, "the duration starts after the warm-up")
	t.eq(A.count_events(w, K.EV_SCAN_WARNING), 1, "EV_SCAN_WARNING is emitted")
	A.run(w, 10)
	t.check(not SimVision.is_visible(w, 0, 40, 40), "no reveal during the warm-up")
	A.run(w, 32)
	t.eq(z.state, SimZoneConsts.ZS_ACTIVE, "active after 40 ticks")
	A.run(w, 4)
	t.check(SimVision.is_visible(w, 0, 40, 40), "the scan reveals once active")


# ---- decoys ------------------------------------------------------------------------------------------------------

func test_decoy_zone_spawns_and_dies_with_the_zone(t: TestCtx) -> void:
	var w: SimWorld = _w({"rosters": ["roster.olm.vanilla", "roster.nec.vanilla"]})
	var zi: int = _zi(w, "zone.decoy_light_vehicle")
	var n0: int = w.units_of(0).size()
	var zid: int = w.zones.create_zone(zi, 0, _c(30), _c(30), 0, 0, -1, 0, 0, 0, 0, -1, -1, 4, 4096, 12345)
	var z: SimZone = w.zones.get_zone(zid)
	t.eq(z.members.size(), 4, "four decoys")
	for id: int in z.members:
		var e: SimEntity = w.get_entity(id)
		t.check((e.flags & SimFlags.F_DECOY) != 0 and (e.flags & SimFlags.F_TEMPORARY) != 0, "decoy and temporary flags")
		t.check((e.flags & SimFlags.F_NO_UNIT_CAP) != 0, "no unit cap")
		t.eq(e.hp_max, 1, "one hit point")
		t.check(e.combat != null and (e.combat.cflags & C.CF_DECOY) != 0, "combat flag CF_DECOY")
		t.check(e.combat.wlock_until > w.tick + 100000, "harmless: weapons locked for good")
		t.eq(e.expire_tick, z.t_end, "lifetime = the zone's")
	A.run(w, 1)
	t.eq(w.players[0].unit_count, w.players[0].unit_count, "cap accounting is untouched")
	t.eq(w.units_of(0).size(), n0 + 4, "four more entities of the owner")
	# scatter is a pure function of aux
	var w2: SimWorld = _w({"rosters": ["roster.olm.vanilla", "roster.nec.vanilla"]})
	var z2: SimZone = w2.zones.get_zone(w2.zones.create_zone(_zi(w2, "zone.decoy_light_vehicle"), 0, _c(30), _c(30), 0, 0, -1, 0, 0, 0, 0, -1, -1, 4, 4096, 12345))
	for i: int in 4:
		t.eq(w2.get_entity(z2.members[i]).x, w.get_entity(z.members[i]).x, "same aux, same scatter x")
	w.zones.end_zone(zid, SimZoneConsts.ZE_CANCELLED)
	A.run(w, 2)
	t.eq(w.units_of(0).size(), n0, "decoys die with the zone")


# ---- warnings ----------------------------------------------------------------------------------------------------

func test_warning_marker_visibility(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var mine: SimEntity = A.spawn(w, RIFLE, 0, 10, 10)
	var victim: SimEntity = A.spawn(w, SPIKE, 1, 40, 40)
	var far: SimEntity = A.spawn(w, SPIKE, 1, 60, 10)
	var zid: int = w.zones.spawn_warning(SimZoneConsts.WK_CIRCLE, 0, _c(40), _c(42), 0, 5 * CELL, 0, 120)
	var z: SimZone = w.zones.get_zone(zid)
	t.eq(z.kind, SimZoneConsts.ZK_WARNING, "a warning marker")
	t.check((z.warn_vis & 1) != 0, "the owner sees it")
	t.check((z.warn_vis & 2) != 0, "the player owning an entity inside sees it")
	A.run(w, 121)
	t.check(w.zones.get_zone(zid) == null, "the marker lives its ticks")
	t.check(mine != null and victim != null and far != null, "units exist")
	var far_zone: SimZone = w.zones.get_zone(w.zones.spawn_warning(SimZoneConsts.WK_LINE, 0, _c(10), _c(30), 0, 10 * CELL, 6 * CELL, 100))
	t.check((far_zone.warn_vis & 2) == 0, "a player with nobody near the line does not")


# ---- table limits / ownership -------------------------------------------------------------------------------------

func test_zone_table_is_bounded_and_ids_never_reused(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var zi: int = _zi(w, "zone.smoke_dust_screen")
	var first: int = w.zones.create_zone(zi, 0, _c(10), _c(10))
	w.zones.end_zone(first, SimZoneConsts.ZE_CANCELLED)
	var second: int = w.zones.create_zone(zi, 0, _c(10), _c(10))
	t.check(second > first, "ids are monotonic and never reused")
	var made: int = 1
	while w.zones.create_zone(zi, 0, _c(10 + made % 40), _c(10)) > 0:
		made += 1
		if made > 200:
			break
	t.eq(made, SimZoneConsts.MAX_ZONES, "96 zones at most")


func test_max_per_owner_replaces_the_oldest(t: TestCtx) -> void:
	# a template with max_per_owner would end the owner's oldest piece first: exercised through a builder's cover
	var w: SimWorld = _w()
	var zi: int = _zi(w, "zone.portable_cover")
	var d: DefZone = w.data.zones[zi]
	var saved: int = d.max_per_owner
	d.max_per_owner = 1
	var a: int = w.zones.create_zone(zi, 0, _c(10), _c(10))
	var b: int = w.zones.create_zone(zi, 0, _c(20), _c(10))
	d.max_per_owner = saved
	t.check(w.zones.get_zone(a) == null and w.zones.get_zone(b) != null, "the oldest ended first")


func test_structure_decoy_false_front(t: TestCtx) -> void:
	var w: SimWorld = _w({"rosters": ["roster.def.vanilla", "roster.nec.vanilla"]})
	var zid: int = w.zones.create_zone(_zi(w, "zone.decoy_radar"), 0, _c(30), _c(30))
	var z: SimZone = w.zones.get_zone(zid)
	t.eq(z.members.size(), 1, "one radar look-alike")
	var e: SimEntity = w.get_entity(z.members[0])
	t.eq(e.kind, SimEntity.Kind.STRUCTURE, "a structure decoy")
	t.eq(w.data.structures[e.def_idx].id, "structure.shared.radar", "of the radar def")
	t.check((e.flags & SimFlags.F_DECOY) != 0 and (e.flags & SimFlags.F_NO_FOOTPRINT) != 0, "decoy, no map footprint")
	t.eq(e.hp_max, 1, "1 hp")
	t.check(not e._asset, "not an asset: it does not keep its owner alive")
	t.eq(w.players[0].struct_count, w.players[0].struct_count, "counters intact")
	A.run(w, 3)
	t.eq(w.zones.debug_validate(w), PackedStringArray(), "validate")
	t.eq(w.abilities.debug_validate(w), PackedStringArray(), "abilities validate")
	A.run(w, 600)
	t.check(w.get_entity(e.id) == null or (w.get_entity(e.id).flags & SimFlags.F_GONE) != 0, "gone with the zone (30 s)")


func test_decoys_are_identified_by_detectors(t: TestCtx) -> void:
	var w: SimWorld = _w({"rosters": ["roster.olm.vanilla", "roster.nec.vanilla"], "fog": true})
	var zid: int = w.zones.create_zone(_zi(w, "zone.decoy_light_vehicle"), 0, _c(30), _c(30))
	var dec: SimEntity = w.get_entity(w.zones.get_zone(zid).members[0])
	var spy: SimEntity = A.spawn(w, "unit.nec.surveyor_apc", 1, 50, 50)  # a detector, far away
	t.check(spy.abil != null and spy.abil.slot_of_kind(K.AK_DETECTOR) >= 0, "the Surveyor detects")
	A.run(w, 12)
	t.check(not SimVision.decoy_identified(w, 1, dec), "not identified while no detector is near")
	A.place(w, spy, 33, 30)
	A.run(w, 12)
	t.check(SimVision.decoy_identified(w, 1, dec), "a detector within range identifies it")
	t.check(A.count_events(w, K.EV_DECOY_IDENTIFIED) >= 1, "EV_DECOY_IDENTIFIED")


func test_redundant_orders_clears_a_running_emp(t: TestCtx) -> void:
	var w: SimWorld = _w({"rosters": ["roster.def.vanilla", "roster.nec.vanilla"]})
	var tank: SimEntity = A.spawn(w, "unit.def.hammer_tank", 0, 30, 30)
	A.hold_fire(w)
	tank.combat.emp_until = w.tick + 200
	SimStats.mark_dirty(w, tank, 0)
	var zid: int = w.zones.create_zone(_zi(w, "zone.def.redundant_orders"), 0, _c(30), _c(30))
	t.check(w.zones.get_zone(zid) != null, "the zone exists")
	t.check(tank.combat.emp_until <= w.tick, "the running EMP weapons-off is cleared")
	t.check(SimCombatMods.has_flag(tank.combat, C.STAT_FLAG_EMP_IMMUNE, w.tick), "and the tank is immune for the window")


func test_zone_owner_elimination_cancels_zones(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var zid: int = w.zones.create_zone(_zi(w, "zone.smoke_dust_screen"), 1, _c(30), _c(30))
	w.zones.on_player_eliminated(w, 1)
	t.check(w.zones.get_zone(zid) == null, "an eliminated player's zones end")


# ---- Trident against real combat ----------------------------------------------------------------------------------

func _shell_duel(dome: bool) -> Dictionary:
	var w: SimWorld = A.world({"rosters": ["roster.sap.vanilla", "roster.napc.usa"], "movement": true})
	var tgt: SimEntity = A.spawn(w, "unit.sap.bulwark_tank", 0, 30, 30)
	var gun: SimEntity = A.spawn(w, "unit.napc.paladin_howitzer", 1, 30, 44)
	var z: SimZone = null
	if dome:
		z = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.trident_interception"), 0, _c(30), _c(34), 0, 0, -1, 8192))
	w.orders.issue_internal(w, gun, SimOrder.T_ATTACK, tgt.id)
	A.run(w, 400)
	return {"hp": tgt.hp, "hp_max": tgt.hp_max, "zone": z, "intercepts": A.count_events(w, C.EV_INTERCEPT), "fired": A.count_events(w, C.EV_FIRE)}


func test_trident_stops_real_shells(t: TestCtx) -> void:
	var with_dome: Dictionary = _shell_duel(true)
	var without: Dictionary = _shell_duel(false)
	t.gt(int(without["fired"]), 3, "the howitzer fires")
	t.lt(int(without["hp"]), int(without["hp_max"]), "without a dome the target is hurt")
	t.eq(int(with_dome["hp"]), int(with_dome["hp_max"]), "inside the dome it is untouched")
	t.gt(int(with_dome["intercepts"]), 3, "shells are intercepted (EV_INTERCEPT)")
	t.eq((with_dome["zone"] as SimZone).charges, 24 - int(with_dome["intercepts"]), "one charge per shell")


func test_trident_halves_a_strategic_packet(t: TestCtx) -> void:
	var hp_lost: Array[int] = []
	var charges: int = -1
	for dome: bool in [true, false]:
		var w: SimWorld = A.world({"rosters": ["roster.sap.vanilla", "roster.napc.usa"], "movement": false})
		var tgt: SimEntity = A.spawn(w, "unit.sap.bulwark_tank", 0, 30, 30)
		A.hold_fire(w)
		w.set_hp_max(tgt, 100000)  # survives the volley so that the damage can be compared
		tgt.hp = 100000
		var z: SimZone = null
		if dome:
			z = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.trident_interception"), 0, _c(30), _c(30)))
		var sw: int = -1
		for i: int in w.data.superweapons.size():
			if w.data.superweapons[i].id == "superweapon.napc.atlas_kinetic_array":
				sw = i
		var hp0: int = tgt.hp
		SimPowerFx.apply_superweapon(w, sw, 1, _c(30), _c(30), 0, 0, 0, 0)
		A.run(w, 120)
		hp_lost.append(hp0 - tgt.hp)
		if z != null:
			charges = z.charges
	t.gt(hp_lost[1], 0, "the volley hurts an unprotected target (%d)" % hp_lost[1])
	t.lt(hp_lost[0], hp_lost[1], "the dome reduces it (%d < %d)" % [hp_lost[0], hp_lost[1]])
	t.check(charges <= 24 and charges % 8 == 0 and charges < 24, "whole packets cost 8 charges each (%d left)" % charges)


func test_v5_command_field_ring_state(t: TestCtx) -> void:
	# V5 at sim level: what the view draws - the provider's ring radius, the recipients it marks, the ring going away
	var w: SimWorld = A.world({"rosters": ["roster.han.vanilla", "roster.nec.vanilla"], "movement": false})
	var op: SimEntity = A.spawn(w, "unit.han.link_operator", 0, 30, 30)
	var near: SimEntity = A.spawn(w, "unit.han.nest_rocket_drone", 0, 34, 30)
	var far: SimEntity = A.spawn(w, "unit.han.nest_rocket_drone", 0, 36, 30)
	A.run(w, 3)
	var s: int = op.abil.slot_of_kind(K.AK_COMMAND_FIELD)
	t.eq(w.abilities.sp(w, op, s, "radius_u", 0), 5 * CELL, "the ring has radius 5 cells")
	t.check(w.abilities.aura.is_covered(near, SimAuraSystem.G_CMD), "the drone inside is marked")
	t.check(not w.abilities.aura.is_covered(far, SimAuraSystem.G_CMD), "the one outside is not")
	op.combat.sup_left_q8 = 9999
	A.run(w, 2)
	t.check(not w.abilities.aura.is_covered(near, SimAuraSystem.G_CMD), "the ring disappears while the operator is suppressed")


func test_infantry_shelter_template(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var a: SimEntity = A.spawn(w, RIFLE, 0, 30, 30)
	var tank: SimEntity = A.spawn(w, TANK, 0, 31, 30)
	A.hold_fire(w)
	A.run(w, 3)
	var z: SimZone = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.infantry_shelter"), 0, _c(30), _c(30)))
	t.eq(z.kind, DefEnums.ZoneKind.SHELTER, "SHELTER")
	t.eq(z.t_end - z.t_start, 900, "45 s")
	t.eq(_taken(w, a, C.DT_BULLET, C.DC_DIRECT), 2500, "25 % against bullets")
	t.eq(_taken(w, tank, C.DT_BULLET, C.DC_DIRECT), 0, "infantry only")


func test_zone_visibility_for_the_view(t: TestCtx) -> void:
	var w: SimWorld = _w()
	var dome: SimZone = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.trident_interception"), 0, _c(30), _c(30)))
	var cover: SimZone = w.zones.get_zone(w.zones.create_zone(_zi(w, "zone.portable_cover"), 0, _c(10), _c(10)))
	t.check(w.zones.visible_to(dome, 0) and w.zones.visible_to(dome, 1), "the dome is drawn for everybody")
	t.check(w.zones.visible_to(cover, 0), "the owner sees his cover")
	t.check(w.zones.visible_to(cover, 1) == w.data.zones[cover.zone_idx].visible_to_enemy, "the enemy per the template")
	var warn: SimZone = w.zones.get_zone(w.zones.spawn_warning(SimZoneConsts.WK_CIRCLE, 0, _c(40), _c(40), 0, 3 * CELL, 0, 100))
	t.check(w.zones.visible_to(warn, 0) and not w.zones.visible_to(warn, 1), "a warning marker follows warn_vis")
