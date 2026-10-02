class_name SimZoneAbilities
extends RefCounted
## The zone-spawning ability kinds carried by units (abilities 5.6.7): smoke_launcher (Naga), portable_cover (Vanguard,
## Sapper, Alpine and Combat Pioneers), sensor_puck (Civic Rifle Team), decoy_spawn (Echo Team), and the summon_orbit
## slot of the Lagos repair-drone carrier. State lives in the entity's SimCompAbility slot:
##   SL_STATE  SA_READY / SA_BUILDING / SA_ACTIVE / SA_PACKING / SA_COOLDOWN / SA_RESPAWNING
##   SL_T_END  absolute tick the current state ends (0 while READY / ACTIVE)
##   SL_AUX0   id of the zone the slot created (cover), or the drone entity id (summon_orbit)
## Timers (TK_BUILD / TK_COOLDOWN / TK_RESPAWN) run on the abilities timer wheel and are dispatched here.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")


static func is_zone_kind(kind: int) -> bool:
	return kind == K.AK_SMOKE_LAUNCHER or kind == K.AK_PORTABLE_COVER or kind == K.AK_SENSOR_PUCK or kind == K.AK_DECOY_SPAWN


static func _b(slot: int) -> int:
	return slot * K.SLOT_STRIDE


## A command carries "no point" as (-1, -1) or, from callers that leave the defaults, (0, 0): the map corner is never a target.
static func has_point(x: int, y: int) -> bool:
	return x > 0 or y > 0


## true when the requested point is within launch range of the unit.
static func _in_range(e: SimEntity, x: int, y: int) -> bool:
	var dx: int = x - e.x
	var dy: int = y - e.y
	return dx * dx + dy * dy <= SimZoneConsts.SA_LAUNCH_RANGE_U * SimZoneConsts.SA_LAUNCH_RANGE_U


## CMD_USE_ABILITY entry (SimZoneSystem.use_ability): 0 accepted, else an RJ_* reason.
static func use(world: SimWorld, sys: SimZoneSystem, e: SimEntity, slot: int, mode: int, _target: int, x: int, y: int) -> int:
	var ab: SimCompAbility = e.abil
	if ab == null or slot < 0 or slot >= ab.n_slots:
		return SimAbilityEvents.RJ_NO_SLOT
	var b: int = _b(slot)
	var kind: int = ab.slots[b + K.SL_KIND]
	if not is_zone_kind(kind):
		return SimAbilityEvents.RJ_NO_SLOT
	if (ab.slots[b + K.SL_FLAGS] & K.SF_SUSPENDED) != 0:
		return SimAbilityEvents.RJ_DISABLED
	if kind == K.AK_PORTABLE_COVER:
		return _use_cover(world, sys, e, slot, mode, x, y)
	if mode == 1:
		return SimAbilityEvents.RJ_BAD_STATE
	if ab.slots[b + K.SL_STATE] == SimZoneConsts.SA_COOLDOWN and world.tick < ab.slots[b + K.SL_T_END]:
		return SimAbilityEvents.RJ_COOLDOWN
	var px: int = e.x
	var py: int = e.y
	if has_point(x, y):
		if not _in_range(e, x, y):
			return SimAbilityEvents.RJ_OUT_OF_RANGE
		px = x
		py = y
	var a: SimAbilitySystem = world.abilities
	var zi: int = a.sp(world, e, slot, "zone_idx", -1)
	if zi < 0:
		return SimAbilityEvents.RJ_NO_SLOT
	var cooldown: int = a.sp(world, e, slot, "cooldown_t", 0)
	var until: int = 0
	var radius: int = 0
	match kind:
		K.AK_SMOKE_LAUNCHER:
			var dur: int = a.sp(world, e, slot, "duration_t", 0)
			until = world.tick + dur if dur > 0 else 0
			radius = a.sp(world, e, slot, "radius_u", 0)
		K.AK_SENSOR_PUCK, K.AK_DECOY_SPAWN:
			var max_active: int = a.sp(world, e, slot, "max_active_n", 1)
			if active_from(sys, e.id, zi) >= max_active:
				return SimAbilityEvents.RJ_LIMIT
	var zid: int = sys.create_zone(zi, e.owner, px, py, e.facing, until, -1, radius, 0, 0, 0, -1, e.id, 1, 0, world.tick)
	if zid < 0:
		return SimAbilityEvents.RJ_NO_ROOM
	ab.slots[b + K.SL_AUX0] = zid
	if cooldown > 0:
		ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_COOLDOWN
		ab.slots[b + K.SL_T_END] = world.tick + cooldown
		a.wheel.schedule(world.tick + cooldown, e.id, K.TK_COOLDOWN, slot)
	return 0


## Zones of template zi created by entity `eid` that are still alive.
static func active_from(sys: SimZoneSystem, eid: int, zi: int) -> int:
	var n: int = 0
	for z: SimZone in sys.zones:
		if z.src_eid == eid and z.zone_idx == zi:
			n += 1
	return n


# ---- portable cover ------------------------------------------------------------------------------------------------

static func _use_cover(world: SimWorld, sys: SimZoneSystem, e: SimEntity, slot: int, mode: int, x: int, y: int) -> int:
	var ab: SimCompAbility = e.abil
	var a: SimAbilitySystem = world.abilities
	var b: int = _b(slot)
	var state: int = ab.slots[b + K.SL_STATE]
	if mode == 1:  # cancel a build / pack up a running piece
		if state == SimZoneConsts.SA_BUILDING:
			_set_busy(e, false)
			ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_READY
			ab.slots[b + K.SL_T_END] = 0
			return 0
		if state == SimZoneConsts.SA_ACTIVE:
			return 0 if request_pack(world, e) or _end_piece(world, sys, e, slot) else SimAbilityEvents.RJ_BAD_STATE
		return SimAbilityEvents.RJ_BAD_STATE
	if state == SimZoneConsts.SA_BUILDING or state == SimZoneConsts.SA_PACKING:
		return SimAbilityEvents.RJ_BAD_STATE
	if a.sp(world, e, slot, "stationary_only", 1) != 0 and not SimZoneFx.is_still(e):
		return SimAbilityEvents.RJ_NOT_STATIONARY
	if has_point(x, y):
		return SimAbilityEvents.RJ_BAD_TARGET  # cover is built where the builder stands
	var build_t: int = a.sp(world, e, slot, "build_t", 0)
	ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_BUILDING
	ab.slots[b + K.SL_T_END] = world.tick + build_t
	_set_busy(e, true)
	if build_t <= 0:
		_finish_build(world, sys, e, slot)
	else:
		a.wheel.schedule(world.tick + build_t, e.id, K.TK_BUILD, slot)
	return 0


static func _set_busy(e: SimEntity, on: bool) -> void:
	SimStats.set_flag(e, K.DF_BUSY, on)
	SimStats.set_flag(e, K.DF_IMMOBILE, on)


## The build finished: replaces the previous piece, spawns the cover zone bound to the builder for occupancy.
static func _finish_build(world: SimWorld, sys: SimZoneSystem, e: SimEntity, slot: int) -> void:
	var ab: SimCompAbility = e.abil
	var a: SimAbilitySystem = world.abilities
	var b: int = _b(slot)
	_set_busy(e, false)
	var old: int = ab.slots[b + K.SL_AUX0]
	if old > 0 and ab.slots[b + K.SL_STATE] != SimZoneConsts.SA_READY:
		var oz: SimZone = sys.get_zone(old)
		if oz != null and oz.src_eid == e.id:
			sys.end_zone(old, SimZoneConsts.ZE_CANCELLED)
	var zi: int = a.sp(world, e, slot, "zone_idx", -1)
	var life: int = a.sp(world, e, slot, "lifetime_t", 0)
	var xf: int = SimZoneConsts.ZF_BUILDER_ONLY if a.sp(world, e, slot, "pack_t", 0) > 0 else 0  # a piece the builder must carry away is its own
	var zid: int = sys.create_zone(zi, e.owner, e.x, e.y, e.facing, world.tick + life if life > 0 else 0, -1, 0, 0, 0, 0, -1, e.id, 1, 0, 0, -1,
		xf, a.sp(world, e, slot, "resist_bp", 0))
	if zid < 0:
		ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_READY
		ab.slots[b + K.SL_T_END] = 0
		return
	ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_ACTIVE
	ab.slots[b + K.SL_T_END] = 0
	ab.slots[b + K.SL_AUX0] = zid


static func _end_piece(world: SimWorld, sys: SimZoneSystem, e: SimEntity, slot: int) -> bool:
	var ab: SimCompAbility = e.abil
	var b: int = _b(slot)
	var zid: int = ab.slots[b + K.SL_AUX0]
	if zid > 0 and sys.get_zone(zid) != null:
		sys.end_zone(zid, SimZoneConsts.ZE_CANCELLED)
	ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_READY
	ab.slots[b + K.SL_T_END] = 0
	ab.slots[b + K.SL_AUX0] = 0
	return world != null


## A move order on a builder: a cover being built is dropped; a running piece with pack_t > 0 is packed (the unit is held
## for pack_t ticks, then the zone goes). Returns true while the entity is being held.
static func request_pack(world: SimWorld, e: SimEntity) -> bool:
	var ab: SimCompAbility = e.abil
	if ab == null or world.zones == null:
		return false
	var held: bool = false
	for s: int in ab.n_slots:
		var b: int = _b(s)
		if ab.slots[b + K.SL_KIND] != K.AK_PORTABLE_COVER:
			continue
		var st: int = ab.slots[b + K.SL_STATE]
		if st == SimZoneConsts.SA_BUILDING:
			_set_busy(e, false)
			ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_READY
			ab.slots[b + K.SL_T_END] = 0
		elif st == SimZoneConsts.SA_ACTIVE:
			var pack_t: int = world.abilities.sp(world, e, s, "pack_t", 0)
			if pack_t > 0:
				ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_PACKING
				ab.slots[b + K.SL_T_END] = world.tick + pack_t
				_set_busy(e, true)
				world.abilities.wheel.schedule(world.tick + pack_t, e.id, K.TK_BUILD, s)
				held = true
		elif st == SimZoneConsts.SA_PACKING:
			held = true
	return held


## A zone ended: the creating slot becomes READY again (cover) / stays in its cooldown.
static func on_zone_ended(world: SimWorld, _sys: SimZoneSystem, z: SimZone) -> void:
	if z.src_eid <= 0 or z.zone_idx < 0:
		return
	var e: SimEntity = world.get_entity(z.src_eid)
	if e == null or e.abil == null:
		return
	var ab: SimCompAbility = e.abil
	for s: int in ab.n_slots:
		var b: int = _b(s)
		if ab.slots[b + K.SL_KIND] == K.AK_PORTABLE_COVER and ab.slots[b + K.SL_AUX0] == z.id:
			ab.slots[b + K.SL_AUX0] = 0
			if ab.slots[b + K.SL_STATE] == SimZoneConsts.SA_ACTIVE or ab.slots[b + K.SL_STATE] == SimZoneConsts.SA_PACKING:
				if ab.slots[b + K.SL_STATE] == SimZoneConsts.SA_PACKING:
					_set_busy(e, false)
				ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_READY
				ab.slots[b + K.SL_T_END] = 0


## Timer dispatch (SimAbilitySystem._on_timer): TK_BUILD, TK_COOLDOWN, TK_RESPAWN.
static func on_timer(world: SimWorld, e: SimEntity, kind: int, slot: int) -> void:
	var ab: SimCompAbility = e.abil
	var sys: SimZoneSystem = world.zones
	if ab == null or sys == null or slot < 0 or slot >= ab.n_slots:
		return
	var b: int = _b(slot)
	var st: int = ab.slots[b + K.SL_STATE]
	var due: bool = world.tick >= ab.slots[b + K.SL_T_END]
	match kind:
		K.TK_BUILD:
			if not due:
				return
			if st == SimZoneConsts.SA_BUILDING:
				_finish_build(world, sys, e, slot)
			elif st == SimZoneConsts.SA_PACKING:
				_set_busy(e, false)
				_end_piece(world, sys, e, slot)
		K.TK_COOLDOWN:
			if st == SimZoneConsts.SA_COOLDOWN and due:
				ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_READY
				ab.slots[b + K.SL_T_END] = 0
				world.emit(K.EV_ABILITY_READY, e.x, e.y, e.id, slot)
		K.TK_RESPAWN:
			if st == SimZoneConsts.SA_RESPAWNING and due and ab.slots[b + K.SL_KIND] == K.AK_SUMMON_ORBIT:
				attach_drone(world, e)


# ---- the Lagos repair drone (summon_orbit slot) ---------------------------------------------------------------------

static func drone_slot(e: SimEntity) -> int:
	return e.abil.slot_of_kind(K.AK_SUMMON_ORBIT) if e.abil != null else -1


## Spawns (or respawns) the attached drone of `p` and (re)opens its repair slots.
static func attach_drone(world: SimWorld, p: SimEntity) -> void:
	var u: DefUnit = world.data.units[p.def_idx]
	var didx: int = int(u.params.get("summon_attached_idx", -1))
	if didx < 0 or (p.flags & SimFlags.F_GONE) != 0:
		return
	var ab: SimCompAbility = SimStatus.ensure_abil(world, p)
	var s: int = drone_slot(p)
	if s < 0:
		if ab.n_slots >= K.MAX_SLOTS:
			return
		s = ab.n_slots
		ab.n_slots += 1
		var nb: int = _b(s)
		ab.slots[nb + K.SL_KIND] = K.AK_SUMMON_ORBIT
		ab.slots[nb + K.SL_AB_IDX] = -100
		ab.slots[nb + K.SL_FLAGS] = K.SF_ENABLED | K.SF_AUTOCAST
		ab.slots[nb + K.SL_N] = int(u.params.get("summon_respawn_t", 0))
	var flags: int = SimZoneConsts.SM_NO_SALVAGE | SimZoneConsts.SM_NO_CAPTURE | SimZoneConsts.SM_NO_CMD_FIELD | SimZoneConsts.SM_UNCONTROLLABLE \
		| SimZoneConsts.SM_SHOOTABLE | SimZoneConsts.SM_NO_VISION_GRANT
	var id: int = SimSummons.spawn(world, didx, p.owner, p.x + SimZoneConsts.ORBIT_ATTACHED_U, p.y, p.id, flags, 0, SimZoneConsts.SD_ATTACHED, 0, 0, 0)
	var b: int = _b(s)
	if id <= 0:
		ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_RESPAWNING
		ab.slots[b + K.SL_T_END] = world.tick + maxi(ab.slots[b + K.SL_N], 1)
		world.abilities.wheel.schedule(ab.slots[b + K.SL_T_END], p.id, K.TK_RESPAWN, s)
		return
	world.by_id[id].summon.src_kind = 2
	_drone_driven(world, p)
	ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_ACTIVE
	ab.slots[b + K.SL_T_END] = 0
	ab.slots[b + K.SL_AUX0] = id
	_repair_suspend(world, p, false)


## The carrier's free repair is done by its drone (SimSummons._drone_heal): the order-based auto-cast is switched off.
static func _drone_driven(world: SimWorld, p: SimEntity) -> void:
	var ab: SimCompAbility = p.abil
	for s: int in ab.n_slots:
		var b: int = _b(s)
		if ab.slots[b + K.SL_KIND] == K.AK_REPAIR:
			ab.slots[b + K.SL_FLAGS] &= ~K.SF_AUTOCAST
			ab.slots[b + K.SL_AUX1] = 0
	world.abilities.autocast_note(p.id)


## The drone died (or vanished): the parent's slot starts RESPAWNING and its repair ability is suspended meanwhile.
static func drone_lost(world: SimWorld, drone: SimEntity) -> void:
	var p: SimEntity = world.get_entity(drone.summon.parent_eid)
	if p == null or (p.flags & SimFlags.F_GONE) != 0 or p.abil == null:
		return
	var s: int = drone_slot(p)
	if s < 0:
		return
	var ab: SimCompAbility = p.abil
	var b: int = _b(s)
	if ab.slots[b + K.SL_AUX0] != drone.id or ab.slots[b + K.SL_STATE] != SimZoneConsts.SA_ACTIVE:
		return
	var respawn: int = ab.slots[b + K.SL_N]
	ab.slots[b + K.SL_AUX0] = 0
	_repair_suspend(world, p, true)
	if respawn <= 0:
		ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_RESPAWNING
		ab.slots[b + K.SL_T_END] = SimSummons.NEVER_UNLOCK
		return
	ab.slots[b + K.SL_STATE] = SimZoneConsts.SA_RESPAWNING
	ab.slots[b + K.SL_T_END] = world.tick + respawn
	world.abilities.wheel.schedule(world.tick + respawn, p.id, K.TK_RESPAWN, s)


## Without its drone the carrier's repair slots are suspended (no auto-cast, no commands, a running repair stops).
static func _repair_suspend(world: SimWorld, p: SimEntity, on: bool) -> void:
	var ab: SimCompAbility = p.abil
	for s: int in ab.n_slots:
		var b: int = _b(s)
		if ab.slots[b + K.SL_KIND] != K.AK_REPAIR:
			continue
		if on:
			ab.slots[b + K.SL_FLAGS] |= K.SF_SUSPENDED
			if not p.orders.is_empty() and p.orders[0].type == SimOrder.T_REPAIR:
				world.orders.clear(world, p, SimOrder.END_CANCELLED)
		else:
			ab.slots[b + K.SL_FLAGS] &= ~K.SF_SUSPENDED
