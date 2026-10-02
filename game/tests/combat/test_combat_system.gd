extends RefCounted
## CB-01: components, lifecycle hooks (spawn / remove / owner change), id lists, read API, health writers,
## checksum sensitivity (D-4) and a double-run determinism test.


# ---------------------------------------------------------------------------------------------- lifecycle
func test_spawn_allocates_components(t: TestCtx) -> void:
	var w: SimWorld = CombatKit.world()
	var tank: SimEntity = CombatKit.tank(w, 1, 30, 30)
	t.not_null(tank.combat, "every unit gets SimCompCombat")
	var c: SimCompCombat = tank.combat
	t.eq(c.n_mounts, 1, "one mount")
	t.eq(c.mnt.size(), SimCombatConsts.MS, "mount state block")
	t.eq(c.mnt[SimCombatConsts.M_AMMO], -1, "infinite ammo (ammo_volleys 0)")
	t.eq(c.mnt[SimCombatConsts.M_TARGET], -1, "no mount target")
	t.eq(c.mnt[SimCombatConsts.M_CD], 0, "no cooldown: full and ready")
	t.eq([c.target_id, c.stance, c.target_src], [-1, SimCombatConsts.ST_AGGRESSIVE, SimCombatConsts.TS_NONE], "no target, default stance")
	t.eq([c.last_fire_tick, c.last_hit_tick, c.last_dealt_tick], [SimCombatConsts.NEVER, SimCombatConsts.NEVER, SimCombatConsts.NEVER], "timestamps start long ago")
	t.eq([c.want_deploy, c.want_mode, c.want_surface, c.last_attacker_id], [-1, -1, -1, -1], "requests empty")
	t.eq([c.sup_t0, c.sup_t1, c.sup_t2], [SimCombatConsts.NEVER, SimCombatConsts.NEVER, SimCombatConsts.NEVER], "suppression ring starts empty")
	t.check(tank.air == null and tank.carrier == null, "no air / carrier component on a tank")
	t.check(w.combat.armed_ids.has(tank.id), "armed_ids")
	var hq: SimEntity = w.get_entity(1)
	t.not_null(hq.combat, "structures too")
	t.eq(hq.combat.n_mounts, 0, "HQ unarmed")
	t.check(not w.combat.armed_ids.has(hq.id), "unarmed entities are not scanned")
	var tur: SimEntity = CombatKit.turret(w, 1, 40, 40)
	t.check(w.combat.armed_ids.has(tur.id) and tur.combat.n_mounts == 1, "turret armed")
	var flagged: SimEntity = w.spawn_unit(SimTestKit.unit_def(DefTestKit.U_RIFLEMAN), 1, 33 * SimConfig.CELL, 33 * SimConfig.CELL, 0,
		SimFlags.F_SUMMONED | SimFlags.F_DECOY | SimFlags.F_INVULNERABLE)
	t.eq(flagged.combat.cflags & (SimCombatConsts.CF_SUMMONED | SimCombatConsts.CF_DECOY | SimCombatConsts.CF_INVULNERABLE | SimCombatConsts.CF_SUPPRESSIBLE),
		SimCombatConsts.CF_SUMMONED | SimCombatConsts.CF_DECOY | SimCombatConsts.CF_INVULNERABLE | SimCombatConsts.CF_SUPPRESSIBLE, "cflags from kernel flags and the def")
	t.eq(w.combat.verify_indexes(w), PackedStringArray(), "derived id lists match entity state")
	t.check(_ascending(w.combat.armed_ids), "ascending ids")


func _ascending(a: PackedInt32Array) -> bool:
	for i: int in range(1, a.size()):
		if a[i] <= a[i - 1]:
			return false
	return true


func test_air_carrier_and_wreck_components(t: TestCtx) -> void:
	var w: SimWorld = CombatKit.world()
	var tank: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var cd: SimCombatDef = CombatKit.cdef(w, tank)
	# hand-made shapes: an airfield, an aircraft and a carrier def
	cd.is_aircraft = 1
	var air: SimEntity = CombatKit.tank(w, 1, 32, 30)
	t.not_null(air.air, "aircraft-tagged def gets SimCompAir")
	t.eq(air.air.state, SimCombatConsts.AIR_PARKED, "parked")
	t.eq([air.air.home_id, air.air.pad, air.air.orphan_deadline], [-1, -1, -1], "no home, no pad")
	t.check(w.combat.air_ids.has(air.id) and w.combat.armed_ids.has(air.id), "listed as air and armed")
	cd.is_aircraft = 0
	cd.carrier_bays = 3
	var car: SimEntity = CombatKit.tank(w, 1, 34, 30)
	t.eq([car.carrier.bay_id.size(), car.carrier.bay_id[0], car.carrier.wing_req], [3, -1, -1], "carrier bays")
	t.check(w.combat.carrier_ids.has(car.id), "listed as carrier")
	cd.carrier_bays = 0
	var first: SimEntity = CombatKit.turret(w, 1, 40, 40)
	t.check(first.air == null, "a turret is no airfield")
	CombatKit.cdef(w, first).pad_count = 4
	var af2: SimEntity = CombatKit.turret(w, 1, 44, 40)
	t.eq([af2.air.is_airfield, af2.air.pad_occ.size(), af2.air.pad_occ[3]], [1, 4, -1], "airfield pads")
	t.check(not w.combat.air_ids.has(af2.id) and w.combat.armed_ids.has(af2.id), "airfields are armed but not in air_ids")
	# a wreck
	var wreck: SimEntity = w.spawn_wreck(tank, true, 50, 100)
	t.not_null(wreck.combat, "wrecks carry a combat component")
	t.check(w.combat.wreck_ids.has(wreck.id) and wreck.combat.n_mounts == 0, "listed as wreck, unarmed")
	t.eq(wreck.combat.wreck_owner_pid, -1, "wreck fields start empty")
	t.eq(w.combat.verify_indexes(w), PackedStringArray(), "consistent")


func test_remove_unlinks_everything(t: TestCtx) -> void:
	var w: SimWorld = CombatKit.world()
	var a: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var b: SimEntity = CombatKit.tank(w, 1, 34, 30)
	SimCombatMods.apply(w, a, 1, SimCombatConsts.STAT_DMG_OUT, 500, 0, 500)
	t.check(w.combat.status_ids.has(a.id), "leased entity is in status_ids")
	w.remove_entity(a.id, SimEvent.REM_SCRIPT)
	w.step()
	t.check(not w.combat.armed_ids.has(a.id) and not w.combat.status_ids.has(a.id), "removal drops the ids")
	t.check(w.combat.armed_ids.has(b.id), "others stay")
	# an aircraft frees its pad
	var af: SimEntity = CombatKit.turret(w, 1, 40, 40)
	var cd: SimCombatDef = CombatKit.cdef(w, af)
	cd.pad_count = 2
	var af2: SimEntity = CombatKit.turret(w, 1, 44, 40)
	var plane: SimEntity = CombatKit.tank(w, 1, 36, 36)
	plane.air = SimCompAir.new()
	plane.air.home_id = af2.id
	plane.air.pad = 1
	af2.air.pad_occ[1] = plane.id
	w.remove_entity(plane.id, SimEvent.REM_SCRIPT)
	w.step()
	t.eq(af2.air.pad_occ[1], -1, "the pad is free again")
	t.eq(w.combat.verify_indexes(w).size(), 0, "indexes consistent after the removals")


func test_owner_change_resets_combat_state(t: TestCtx) -> void:
	var w: SimWorld = CombatKit.world()
	var e: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var c: SimCompCombat = e.combat
	c.target_id = 99
	c.target_src = SimCombatConsts.TS_ORDER
	c.stance = SimCombatConsts.ST_HOLD_FIRE
	c.ground_on = 1
	c.anchor_on = 1
	c.hold_pos = 1
	c.focus_mask = 3
	SimCombatMods.apply(w, e, 1, SimCombatConsts.STAT_TAKEN, 1000, SimCombatConsts.FILTER_ALL_WEAPON, 500)
	t.check(w.change_owner(e.id, 0, SimEvent.OWNER_CAPTURE), "captured")
	t.eq([c.target_id, c.target_src, c.ground_on, c.anchor_on, c.hold_pos, c.focus_mask], [-1, 0, 0, 0, 0, 0], "target, ground point, anchor, hold and focus cleared")
	t.eq(c.stance, SimCombatConsts.ST_AGGRESSIVE, "stance reset")
	t.eq(SimCombatMods.sum_bp(c, SimCombatConsts.STAT_TAKEN, w.tick), 0, "leases dropped")
	t.eq(c.scan_next, w.tick, "asks for an immediate rescan")
	t.check(CombatKit.cdef(w, e) != null and w.combat.def_for(w, e).armor == DefEnums.ArmorClass.MEDIUM_ARMOR, "def resolved for the new owner")


# ---------------------------------------------------------------------------------------------- health
func test_heal_rescale_and_debug(t: TestCtx) -> void:
	var w: SimWorld = CombatKit.world()
	var e: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var mx: int = e.hp_max
	e.hp = mx - 30
	t.eq(w.combat.heal(w, e, 20), 20, "heals the requested amount")
	t.eq(w.combat.heal(w, e, 50), 10, "never above hp_max")
	t.eq([e.hp, w.combat.heal(w, e, 5), w.combat.heal(w, e, -5), w.combat.heal(w, e, 0)], [mx, 0, 0, 0], "full: nothing, non-positive: nothing")
	e.hp = 400
	w.combat.rescale_hp(w, e, mx * 2)
	t.eq([e.hp_max, e.hp], [mx * 2, 800], "rescale keeps the fraction")
	w.combat.kill(w, e, SimCombatConsts.CAUSE_DAMAGE, -1, -1)
	t.eq(w.combat.heal(w, e, 100), 0, "the dead are not healed")
	w.combat.kill(w, e, SimCombatConsts.CAUSE_DAMAGE, -1, -1)  # idempotent
	t.check((e.flags & SimFlags.F_DEAD) != 0 and e.hp == 0, "killed once")
	var v: SimEntity = CombatKit.tank(w, 1, 34, 30)
	t.eq(w.combat.on_debug(w, 0, 5, v.id, 0, 7, 0, 0), SimCommand.Err.OK, "debug mode 5 sets hp")
	t.eq(v.hp, 7, "to the requested value")
	t.eq(w.combat.on_debug(w, 0, 4, v.id, 0, 7, 0, 0), -1, "other modes are not ours")
	var s: SimEntity = CombatKit.tank(w, 1, 36, 30)
	w.combat.scuttle(w, s)
	t.check((s.combat.cflags & SimCombatConsts.CF_SCUTTLED) != 0 and (s.flags & SimFlags.F_DEAD) != 0, "scuttle")


# ---------------------------------------------------------------------------------------------- read API
func test_read_api(t: TestCtx) -> void:
	var w: SimWorld = CombatKit.world()
	var tank: SimEntity = CombatKit.tank(w, 1, 30, 30)
	var rifle: SimEntity = CombatKit.rifle(w, 0, 40, 30)
	t.check(w.combat.is_alive(tank) and w.combat.is_functional(w, tank) and w.combat.weapons_online(w, tank), "healthy tank")
	t.eq(w.combat.range_max_eff(w, tank), 7168, "base range")
	SimCombatMods.apply(w, tank, 1, SimCombatConsts.STAT_RANGE, 1000, 0, 100)
	t.eq(w.combat.range_max_eff(w, tank), 7885, "range lease +10 % (half-up)")
	t.eq(w.combat.range_max_eff(w, tank, 3), 0, "a missing mount has no range")
	t.eq(w.combat.range_min_of(w, tank), 0, "no minimum range")
	t.eq(w.combat.ammo_of(tank, 0), -1, "infinite ammo")
	t.eq(w.combat.ammo_of(tank, 5), -1, "unknown mount")
	t.eq(w.combat.dp100(w, tank, rifle), 587, "141 dmg / 24 ticks x 100 (AP vs infantry 100 %)")
	t.eq(w.combat.dp100(w, rifle, tank), 52, "rifle: 26 dmg / 20 ticks x 100 at 40 % (bullet vs medium armor)")
	t.eq(w.combat.ticks_since_combat(w, tank), w.tick - SimCombatConsts.NEVER, "never fought")
	tank.combat.last_hit_tick = 5
	tank.combat.last_fire_tick = 12
	w.tick = 20
	t.eq(w.combat.ticks_since_combat(w, tank), 8, "since the most recent of fire / hit / dealt")
	tank.combat.wlock_until = 30
	t.check(w.combat.is_functional(w, tank) and not w.combat.weapons_online(w, tank), "weapon lock: functional but not online")
	w.tick = 30
	t.check(w.combat.weapons_online(w, tank), "lock over")
	tank.combat.sup_left_q8 = 100
	t.check(w.combat.is_suppressed(tank) and w.combat.suppression_speed_bp(tank) == 7500, "suppressed")
	w.combat.kill(w, tank, SimCombatConsts.CAUSE_DAMAGE, -1, -1)
	t.check(not w.combat.is_alive(tank) and not w.combat.is_functional(w, tank), "dead")
	t.check(w.combat.debug_string(w, rifle).begins_with("combat:"), "debug string")
	var tur: SimEntity = CombatKit.turret(w, 1, 40, 44)
	t.eq(w.combat.range_max_eff(w, tur), 8 * SimConfig.CELL, "structure range")


# ---------------------------------------------------------------------------------------- checksum (D-4)
## Perturbs every script variable of `c` (ints; packed arrays: append, or bump element 0) and returns the problems:
## a non-exempt field that does not change the digest, or an exempt one that does.
func _coverage(c: SimComponent, exempt: PackedStringArray) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var buf: PackedInt32Array = PackedInt32Array()
	c.hash_into(buf)
	var base: int = Checksum.digest32(buf)
	for p: Dictionary in c.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = p["name"]
		var v: Variant = c.get(n)
		if typeof(v) == TYPE_INT:
			c.set(n, (v as int) + 1)
		elif typeof(v) == TYPE_PACKED_INT32_ARRAY:
			var a: PackedInt32Array = (v as PackedInt32Array).duplicate()
			if a.is_empty():
				a.append(7)
			else:
				a[a.size() - 1] += 1
			c.set(n, a)
		else:
			continue
		buf = PackedInt32Array()
		c.hash_into(buf)
		var changed: bool = Checksum.digest32(buf) != base
		c.set(n, v)
		if changed and exempt.has(n):
			problems.append("%s is exempt but hashed" % n)
		elif not changed and not exempt.has(n):
			problems.append("%s is not hashed" % n)
	return problems


func test_d4_checksum_sensitivity_populated_components(t: TestCtx) -> void:
	var w: SimWorld = CombatKit.world()
	var e: SimEntity = CombatKit.tank(w, 1, 30, 30)
	SimCombatMods.apply(w, e, 1, SimCombatConsts.STAT_TAKEN, 500, SimCombatConsts.FILTER_ALL_WEAPON, 100)
	e.combat.aps_next = PackedInt32Array([3, 4])
	t.eq(_coverage(e.combat, SimCompCombat.HASH_EXEMPT), PackedStringArray(), "SimCompCombat: every field but the derived ones is hashed (mnt, mods, aps_next included)")
	var air: SimCompAir = SimCompAir.new()
	air.pad_occ = PackedInt32Array([-1, 5])
	t.eq(_coverage(air, SimCompAir.HASH_EXEMPT), PackedStringArray(), "SimCompAir")
	var car: SimCompCarrier = SimCompCarrier.new()
	car.bay_id = PackedInt32Array([1, 2])
	car.bay_state = PackedInt32Array([1, 0])
	car.bay_timer = PackedInt32Array([4, 5])
	t.eq(_coverage(car, SimCompCarrier.HASH_EXEMPT), PackedStringArray(), "SimCompCarrier")
	for cls: GDScript in [SimCompCombat, SimCompAir, SimCompCarrier]:
		t.eq(SimTestKit.check_hash_coverage(cls, cls.get("HASH_EXEMPT")), PackedStringArray(), "kit coverage check on a fresh instance")
	t.eq(_coverage(SimCompCombat.new(), SimCompCombat.HASH_EXEMPT), PackedStringArray(), "and on a fresh combat component")


func test_derived_fields_do_not_change_the_world_hash(t: TestCtx) -> void:
	var w: SimWorld = CombatKit.world()
	var e: SimEntity = CombatKit.tank(w, 1, 30, 30)
	w.step()  # lists the new entity (only listed entities enter the checksum)
	var h0: int = w.checksum()
	e.combat.agg_dmg_bp = 999
	e.combat.mods_dirty = 1
	e.combat.taken_stamp = 5
	e.combat.hit_dmg = 7
	w.combat.alert_tick[1] = 33
	w.combat.counters[0] = 9
	t.eq(w.checksum(), h0, "derived / scratch fields are outside the checksum")
	e.combat.stance = SimCombatConsts.ST_DEFENSIVE
	t.check(w.checksum() != h0, "authoritative fields are inside it")
	e.combat.stance = SimCombatConsts.ST_AGGRESSIVE
	t.eq(w.checksum(), h0, "and restoring them restores it")
	w.combat.scan_cursor = 3
	t.check(w.checksum() != h0, "the scan cursor is hashed")
	w.combat.scan_cursor = 0
	CombatKit.hit(w, e, CombatKit.wh(1))
	t.check(w.checksum() != h0, "a pending damage instance is hashed (the queue must be empty between ticks)")
	SimDamage.flush(w)


# ---------------------------------------------------------------------------------------------- determinism
func _build() -> SimWorld:
	var w: SimWorld = CombatKit.world({"players": 3, "seed": 99})
	for i: int in 4:
		CombatKit.tank(w, 1, 30 + i * 2, 30)
		CombatKit.rifle(w, 2, 30 + i * 2, 40)
	CombatKit.turret(w, 1, 50, 50)
	CombatKit.set_matrix(w, SimCombatConsts.DT_AP, DefEnums.ArmorClass.MEDIUM_ARMOR, 9000)
	return w


func _script(w: SimWorld, s: int) -> void:
	var units: Array[SimEntity] = w.units
	if units.is_empty():
		return
	var wh: SimCombatWarhead = CombatKit.wh(9, SimCombatConsts.DT_BULLET)
	wh.suppressive = 1
	var emp: SimCombatWarhead = CombatKit.wh(3, SimCombatConsts.DT_EMP)
	emp.emp_unit_ticks = 30
	emp.emp_class_mask = SimCombatConsts.EC_VEHICLE
	var v: SimEntity = units[s % units.size()]
	if (v.flags & SimFlags.F_GONE) != 0:
		return
	if s % 3 != 2:
		CombatKit.hit(w, v, wh, {"pid": 0})
	if s % 7 == 0:
		CombatKit.hit(w, v, emp, {"pid": 0})
	if s % 5 == 0:
		SimCombatMods.apply(w, v, s % 4, SimCombatConsts.STAT_TAKEN, 300 * (s % 5), SimCombatConsts.FILTER_ALL_WEAPON, 12)
	if s % 11 == 0:
		SimCombatMods.apply(w, v, 20, SimCombatConsts.STAT_SUP_RECOVER, 2500, 0, 20)


func test_double_run_is_identical(t: TestCtx) -> void:
	var r: Dictionary = SimTestKit.double_run(_build, _script, 300)
	t.check(r["ok"], "two worlds, same script: identical chains, events, final checksum and dump")
	t.check((r["chain"] as PackedInt64Array).size() >= 30, "checkpoints were recorded")
	var w: SimWorld = _build()
	SimTestKit.run_script(w, 300, _script)
	t.eq(w.combat.verify_indexes(w), PackedStringArray(), "indexes still consistent after 300 ticks")
	t.eq(w.combat.dmg_queue.size(), 0, "queue empty between ticks")
	t.check(CombatKit.events(w, SimCombatConsts.EV_HIT).size() > 20, "hits happened (%d)" % CombatKit.events(w, SimCombatConsts.EV_HIT).size())
	t.check(CombatKit.events(w, SimCombatConsts.EV_SUPPRESS).size() > 0, "and suppression")
	t.check(CombatKit.events(w, SimCombatConsts.EV_EMP).size() > 0, "and EMP")
