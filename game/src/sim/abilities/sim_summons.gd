class_name SimSummons
extends RefCounted
## Temporary units (abilities 5.12): UAV, drones, balloon, cargo aircraft, pontoon, zone bodies, decoys, Tempest drones,
## Dragonfall capsules and engines, the Lagos repair drone. `spawn` creates the entity through world.spawn_unit, attaches
## the SimCompSummon record, mirrors the SM_* flags onto the kernel flags (F_TEMPORARY, F_SUMMONED, F_NO_UNIT_CAP, F_DECOY,
## F_NO_SALVAGE ...), the combat flags (CF_ENEMY_ONLY) and the derived flags (DF_NO_CMD_FIELD, DF_UNCONTROLLABLE), and sets
## the lifetime in SimEntity.expire_tick (the kernel's cleanup kills it with Cause.EXPIRE; F_SUMMONED means no wreck).
## It never draws random numbers: every position is an argument. The per-summon drivers run in SimZoneSystem.update.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const NEVER_UNLOCK: int = 0x3FFFFFFF


## Unit def index of the shootable body of a zone template with hp > 0 (puck, repair station); a static summon def
## (the NAPC pontoon) stands in when the dedicated body def does not exist yet. -1 when no candidate exists.
static func body_def(data: GameData, d: DefZone) -> int:
	var names: PackedStringArray = PackedStringArray()
	match d.zone_kind:
		DefEnums.ZoneKind.PUCK:
			names = PackedStringArray(["summon.shared.sensor_puck", "summon.ae.sensor_puck"])
		DefEnums.ZoneKind.REPAIR:
			names = PackedStringArray(["summon.olm.repair_drone_station"])
	for n: String in names:
		var i: int = data.unit_idx(n)
		if i >= 0:
			return i
	return data.unit_idx("summon.napc.pontoon")


## Kernel SimFlags for SM_* flags and a driver.
static func kernel_flags(flags: int, driver: int) -> int:
	var f: int = SimFlags.F_SUMMONED
	if (flags & SimZoneConsts.SM_TEMPORARY) != 0:
		f |= SimFlags.F_TEMPORARY | SimFlags.F_NO_UNIT_CAP
	if (flags & SimZoneConsts.SM_DECOY) != 0:
		f |= SimFlags.F_DECOY | SimFlags.F_NO_COLLISION
	if (flags & SimZoneConsts.SM_NO_SALVAGE) != 0:
		f |= SimFlags.F_NO_SALVAGE
	if (flags & SimZoneConsts.SM_NO_CAPTURE) != 0:
		f |= SimFlags.F_NO_CAPTURE
	if (flags & SimZoneConsts.SM_NO_REPAIR) != 0:
		f |= SimFlags.F_NO_REPAIR
	if (flags & SimZoneConsts.SM_NO_VISION_GRANT) != 0:
		f |= SimFlags.F_NO_VISION_GRANT
	if (flags & SimZoneConsts.SM_UNCONTROLLABLE) != 0:
		f |= SimFlags.F_NO_SELECT
	if driver == SimZoneConsts.SD_ORBITER or driver == SimZoneConsts.SD_ATTACHED:
		f |= SimFlags.F_SCRIPTED_MOVE
	if driver == SimZoneConsts.SD_ATTACHED:
		f |= SimFlags.F_TETHERED
	return f


## THE spawn primitive. Returns the entity id, or -1 (bad def / owner, entity cap, match over).
## def_idx: unit def (summon.* / unit.*); pid: owner; (x, y): where it appears; parent_eid: summoner or -1 (the child dies
## with the parent for the ATTACHED driver); flags: SM_*; life_ticks: lifetime (0 = the def's lifetime_t, 0 = forever);
## driver: SD_*; (ax, ay, ar): attack area / orbit centre and radius in units.
static func spawn(world: SimWorld, def_idx: int, pid: int, x: int, y: int, parent_eid: int, flags: int, life_ticks: int,
		driver: int, ax: int, ay: int, ar: int) -> int:
	if def_idx < 0 or def_idx >= world.data.units.size():
		return -1
	var e: SimEntity = world.spawn_unit(def_idx, pid, x, y, 0, kernel_flags(flags, driver), 0, maxi(parent_eid, 0), SimEvent.SPAWN_SUMMONED)
	if e == null:
		return -1
	adopt(world, e, parent_eid, flags, life_ticks, driver, ax, ay, ar)
	return e.id


## Attaches the summon record to an entity created elsewhere (structure decoys).
static func adopt(world: SimWorld, e: SimEntity, parent_eid: int, flags: int, life_ticks: int, driver: int, ax: int, ay: int, ar: int) -> void:
	var sm: SimCompSummon = SimCompSummon.new()
	sm.parent_eid = parent_eid
	sm.flags = flags
	sm.driver = driver
	sm.ax = ax
	sm.ay = ay
	sm.ar = ar
	sm.t0 = world.tick
	sm.state = SimZoneConsts.SS_APPROACH
	e.summon = sm
	var life: int = life_ticks
	if life <= 0 and e.kind == SimEntity.Kind.UNIT:
		life = world.data.units[e.def_idx].lifetime_t
	if life > 0:
		e.expire_tick = world.tick + life
		e.flags |= SimFlags.F_EXPIRE_KILLS
	if e.combat != null:
		if (flags & SimZoneConsts.SM_ENEMIES_ONLY) != 0:
			e.combat.cflags |= SimCombatConsts.CF_ENEMY_ONLY
		if (flags & SimZoneConsts.SM_NO_WRECK) != 0:
			e.combat.cflags |= SimCombatConsts.CF_NO_WRECK
		if (flags & SimZoneConsts.SM_DECOY) != 0 and world.combat != null:
			world.combat.lock_weapons(world, e, NEVER_UNLOCK)  # harmless: a decoy never shoots
	if e.stats != null:
		if (flags & SimZoneConsts.SM_NO_CMD_FIELD) != 0:
			SimStats.set_flag(e, K.DF_NO_CMD_FIELD, true)
		if (flags & SimZoneConsts.SM_UNCONTROLLABLE) != 0:
			SimStats.set_flag(e, K.DF_UNCONTROLLABLE, true)
	if world.zones != null:
		SimAbilitySystem._insert(world.zones.sum_ids, e.id)
	world.emit(SimZoneConsts.EV_SUMMONED, e.x, e.y, e.id, parent_eid, flags)


## Tempest drone (driver SWARM): flies to the area (ax, ay, ar), fights for 400 ticks from its first arrival (hard cap 1200
## ticks after spawn). Returns the entity id or -1.
static func spawn_swarm_drone(world: SimWorld, def_idx: int, pid: int, x: int, y: int, ax: int, ay: int, ar: int, group: int, src_idx: int) -> int:
	var flags: int = SimZoneConsts.SM_TEMPORARY | SimZoneConsts.SM_NO_SALVAGE | SimZoneConsts.SM_NO_CAPTURE | SimZoneConsts.SM_NO_REPAIR \
		| SimZoneConsts.SM_NO_CMD_FIELD | SimZoneConsts.SM_ENEMIES_ONLY | SimZoneConsts.SM_PACKET_WEAPONS | SimZoneConsts.SM_UNCONTROLLABLE \
		| SimZoneConsts.SM_NO_WRECK | SimZoneConsts.SM_SHOOTABLE
	var id: int = spawn(world, def_idx, pid, x, y, -1, flags, SimZoneConsts.SWARM_HARD_CAP_TICKS, SimZoneConsts.SD_SWARM, ax, ay, ar)
	if id > 0:
		var sm: SimCompSummon = world.by_id[id].summon
		sm.group_id = group
		sm.src_kind = 1
		sm.src_idx = src_idx
		sm.src_pid = pid
	return id


## Dragonfall capsule (driver CAPSULE): attackable while it unfolds for `unfold_ticks`, then becomes engine def `engine_idx`
## in place (same position, hp fraction kept, a new entity id). Returns the capsule's entity id or -1.
static func spawn_capsule(world: SimWorld, capsule_idx: int, engine_idx: int, pid: int, x: int, y: int, ax: int, ay: int, ar: int,
		unfold_ticks: int, group: int, src_idx: int) -> int:
	var flags: int = SimZoneConsts.SM_TEMPORARY | SimZoneConsts.SM_NO_SALVAGE | SimZoneConsts.SM_NO_CAPTURE | SimZoneConsts.SM_NO_REPAIR \
		| SimZoneConsts.SM_NO_CMD_FIELD | SimZoneConsts.SM_UNCONTROLLABLE | SimZoneConsts.SM_NO_WRECK | SimZoneConsts.SM_SHOOTABLE
	var id: int = spawn(world, capsule_idx, pid, x, y, -1, flags, 0, SimZoneConsts.SD_CAPSULE, ax, ay, ar)
	if id > 0:
		var sm: SimCompSummon = world.by_id[id].summon
		sm.effect_idx = engine_idx
		sm.t1 = world.tick + unfold_ticks
		sm.state = SimZoneConsts.SS_ASSEMBLING
		sm.group_id = group
		sm.src_kind = 1
		sm.src_idx = src_idx
		sm.src_pid = pid
	return id


# ---- hooks ---------------------------------------------------------------------------------------------------------

static func on_dying(world: SimWorld, sys: SimZoneSystem, e: SimEntity, cause: int) -> void:
	var sm: SimCompSummon = e.summon
	if cause == SimWorld.Cause.EXPIRE:
		world.emit(SimZoneConsts.EV_SUMMON_EXPIRED, e.x, e.y, e.id)
	if sm.driver == SimZoneConsts.SD_ATTACHED:
		SimZoneAbilities.drone_lost(world, e)
	if sm.zone_id > 0:
		var z: SimZone = sys.get_zone(sm.zone_id)
		if z != null and z.body_eid == e.id:
			sys.end_zone(z.id, SimZoneConsts.ZE_BODY)


static func on_remove(world: SimWorld, sys: SimZoneSystem, e: SimEntity, _reason: int) -> void:
	var sm: SimCompSummon = e.summon
	if sm.zone_id > 0:
		var z: SimZone = sys.get_zone(sm.zone_id)
		if z != null and z.kind == DefEnums.ZoneKind.DECOY:
			var i: int = z.members.find(e.id)
			if i >= 0:
				z.members.remove_at(i)
				z.n_members = z.members.size()
		elif z != null and z.body_eid == e.id:
			z.body_eid = -1
			sys.end_zone(z.id, SimZoneConsts.ZE_BODY)
	if sm.driver == SimZoneConsts.SD_ATTACHED and (e.flags & SimFlags.F_DEAD) == 0:
		SimZoneAbilities.drone_lost(world, e)


## Lagos-class parents that spawned this tick get their repair drone.
static func process_attach(world: SimWorld, sys: SimZoneSystem) -> void:
	var q: PackedInt32Array = sys.attach_q
	sys.attach_q = PackedInt32Array()
	for id: int in q:
		var p: SimEntity = world.get_entity(id)
		if p != null and (p.flags & SimFlags.F_GONE) == 0:
			SimZoneAbilities.attach_drone(world, p)


# ---- drivers -------------------------------------------------------------------------------------------------------

static func step(world: SimWorld, sys: SimZoneSystem, e: SimEntity) -> void:
	var sm: SimCompSummon = e.summon
	var tick: int = world.tick
	match sm.driver:
		SimZoneConsts.SD_ORBITER:
			_orbit(world, e, sm, sm.ax, sm.ay, sm.ar)
		SimZoneConsts.SD_ATTACHED:
			var p: SimEntity = world.get_entity(sm.parent_eid)
			if p != null:
				_orbit(world, e, sm, p.x, p.y, SimZoneConsts.ORBIT_ATTACHED_U)
				if (tick + e.id) % SimZoneConsts.DRIVER_PERIOD == 0:
					_drone_heal(world, p, sm)
		SimZoneConsts.SD_SWARM:
			if (tick + e.id) % SimZoneConsts.DRIVER_PERIOD == 0:
				_swarm(world, e, sm)
		SimZoneConsts.SD_CAPSULE:
			if tick >= sm.t1:
				_assemble(world, sys, e, sm)
		SimZoneConsts.SD_ENGINE:
			if (tick + e.id) % SimZoneConsts.DRIVER_PERIOD == 0:
				_engine(world, e, sm)


## Scripted circular flight: approach the ring at the def's speed, then follow it (cosmetic; the body is real and shootable).
static func _orbit(world: SimWorld, e: SimEntity, sm: SimCompSummon, cx: int, cy: int, r: int) -> void:
	var speed: int = maxi(world.abilities.speed_units(e), 1)
	var rad: int = maxi(r, 1024)
	if sm.state == SimZoneConsts.SS_APPROACH:
		var dx: int = e.x - cx
		var dy: int = e.y - cy
		var d: int = Fp.isqrt(dx * dx + dy * dy)
		if d <= rad + speed:
			sm.state = SimZoneConsts.SS_ORBIT
			sm.angle = Fp.atan2(dy, dx)
			sm.t0 = world.tick
		else:
			var nx: int = e.x - dx * speed / d
			var ny: int = e.y - dy * speed / d
			e.facing = Fp.atan2(cy - e.y, cx - e.x)
			world.set_pos(e, nx, ny)
			return
	var da: int = maxi(1, speed * SimZoneConsts.ANGLE_PER_UNIT_Q / rad)
	sm.angle = (sm.angle + da) & 4095
	e.facing = (sm.angle + 1024) & 4095
	world.set_pos(e, cx + Fp.mul_q16(rad, Fp.cos(sm.angle)), cy + Fp.mul_q16(rad, Fp.sin(sm.angle)))


## The Lagos repair drone works for its carrier (abilities 5.12): every 10 ticks it heals the nearest damaged friendly
## infantry squad inside the carrier's repair radius (free, one target at a time) at the ability's rate: rate_bps * hp_max / 20
## milli-hp per pulse (1 % / s). The carrier's own repair slot is the parameter source; without the drone it is suspended.
static func _drone_heal(world: SimWorld, p: SimEntity, sm: SimCompSummon) -> void:
	var ab: SimCompAbility = p.abil
	if ab == null:
		return
	var s: int = ab.slot_of_kind(K.AK_REPAIR)
	if s < 0 or (ab.slots[s * K.SLOT_STRIDE + K.SL_FLAGS] & K.SF_SUSPENDED) != 0:
		return
	var a: SimAbilitySystem = world.abilities
	var radius: int = a.sp(world, p, s, "radius_u", 3072)
	var rate: int = a.sp(world, p, s, "rate_bps", 100)
	var mask: int = a.sp(world, p, s, "target_unit_mask", 0)
	var t: SimEntity = world.get_entity(sm.target_eid) if sm.target_eid > 0 else null
	if t != null:
		var tdx: int = t.x - p.x
		var tdy: int = t.y - p.y
		if (t.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or t.hp >= t.hp_max or tdx * tdx + tdy * tdy > radius * radius:
			t = null
	if t == null:
		sm.target_eid = 0
		var ids: PackedInt32Array = PackedInt32Array()
		world.query_circle(p.x, p.y, radius, ids, SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.UNIT))
		var best_d: int = 0
		for id: int in ids:
			var c: SimEntity = world.by_id[id]
			if c == p or c.team != p.team or c.hp_max <= 0 or c.hp >= c.hp_max or (c.flags & (SimFlags.F_NO_REPAIR | SimFlags.F_INSIDE)) != 0:
				continue
			if not SimEconomyWork.unit_mask_fits(mask, world.data.units[c.def_idx].tags):
				continue
			var dx: int = c.x - p.x
			var dy: int = c.y - p.y
			var dd: int = dx * dx + dy * dy
			if t == null or dd < best_d:
				t = c
				best_d = dd
		if t == null:
			return
		sm.target_eid = t.id
	ab.repair_frac += t.hp_max * rate / 20
	var whole: int = ab.repair_frac / 1000
	ab.repair_frac -= whole * 1000
	if whole > 0 and world.combat != null:
		var got: int = world.combat.heal(world, t, whole)
		if got > 0:
			world.emit(K.EV_REPAIR_PULSE, t.x, t.y, t.id, sm.driver, got)


## Tempest drone: fly to the area, attack ground / surface enemies inside it for 400 ticks from the first arrival.
static func _swarm(world: SimWorld, e: SimEntity, sm: SimCompSummon) -> void:
	var tick: int = world.tick
	var dx: int = e.x - sm.ax
	var dy: int = e.y - sm.ay
	var d: int = Fp.isqrt(dx * dx + dy * dy)
	if sm.state == SimZoneConsts.SS_APPROACH:
		if d <= sm.ar + SimZoneConsts.SWARM_MARGIN_U:
			sm.state = SimZoneConsts.SS_ATTACK
			sm.t0 = tick
			e.expire_tick = mini(tick + SimZoneConsts.SWARM_ATTACK_TICKS, e.born + SimZoneConsts.SWARM_HARD_CAP_TICKS)
			e.flags |= SimFlags.F_EXPIRE_KILLS
		elif e.orders.is_empty():
			world.orders.issue_internal(world, e, SimOrder.T_MOVE, 0, sm.ax, sm.ay)
		return
	if not e.orders.is_empty() and e.orders[0].type == SimOrder.T_ATTACK and world.is_alive(e.orders[0].target_id):
		return
	var t: int = nearest_ground_enemy(world, e.owner, sm.ax, sm.ay, sm.ar)
	if t > 0:
		world.orders.issue_internal(world, e, SimOrder.T_ATTACK, t, 0, 0)
	elif e.orders.is_empty() and d > sm.ar:
		world.orders.issue_internal(world, e, SimOrder.T_MOVE, 0, sm.ax, sm.ay)


## Nearest enemy ground / surface unit or structure inside `r` of (cx, cy), squared distance, ties lowest id; 0 = none.
static func nearest_ground_enemy(world: SimWorld, pid: int, cx: int, cy: int, r: int) -> int:
	var avoid: int = world.non_enemy_mask(pid) | SimTag.kind_bit(SimEntity.Kind.WRECK) | SimTag.kind_bit(SimEntity.Kind.ZONE) \
		| SimTag.kind_bit(SimEntity.Kind.NEUTRAL) | SimTag.layer_bit(SimEntity.Layer.AIR) | SimTag.layer_bit(SimEntity.Layer.UNDERWATER)
	var ids: PackedInt32Array = PackedInt32Array()
	world.query_circle(cx, cy, r, ids, SimTag.ALIVE, avoid)
	var best: int = 0
	var best_d: int = 0
	for id: int in ids:
		var t: SimEntity = world.by_id[id]
		if t == null or (t.flags & (SimFlags.F_UNTARGETABLE | SimFlags.F_INSIDE)) != 0:
			continue
		var ddx: int = t.x - cx
		var ddy: int = t.y - cy
		var dd: int = ddx * ddx + ddy * ddy
		if best == 0 or dd < best_d:
			best = id
			best_d = dd
	return best


## Capsule -> engine: same place, hp fraction preserved (half-up, min 1), the engine lives ENGINE_LIFE_TICKS.
static func _assemble(world: SimWorld, sys: SimZoneSystem, e: SimEntity, sm: SimCompSummon) -> void:
	var engine_idx: int = sm.effect_idx
	if engine_idx < 0:
		world.kill(e, SimWorld.Cause.EXPIRE, 0, -1)
		return
	var pid: int = e.owner
	var num: int = e.hp
	var den: int = maxi(e.hp_max, 1)
	var flags: int = SimZoneConsts.SM_TEMPORARY | SimZoneConsts.SM_NO_SALVAGE | SimZoneConsts.SM_NO_CAPTURE | SimZoneConsts.SM_NO_REPAIR \
		| SimZoneConsts.SM_NO_CMD_FIELD | SimZoneConsts.SM_ENEMIES_ONLY | SimZoneConsts.SM_PACKET_WEAPONS | SimZoneConsts.SM_UNCONTROLLABLE \
		| SimZoneConsts.SM_NO_WRECK | SimZoneConsts.SM_SHOOTABLE
	var group: int = sm.group_id
	var src_idx: int = sm.src_idx
	var ax: int = sm.ax
	var ay: int = sm.ay
	var ar: int = sm.ar
	var cap_id: int = e.id
	var x: int = e.x
	var y: int = e.y
	var facing: int = e.facing
	world.remove_entity(e.id, SimEvent.REM_CONSUMED)
	var id: int = spawn(world, engine_idx, pid, x, y, sm.parent_eid, flags, SimZoneConsts.ENGINE_LIFE_TICKS, SimZoneConsts.SD_ENGINE, ax, ay, ar)
	if id <= 0:
		return
	var eng: SimEntity = world.by_id[id]
	eng.facing = facing
	eng.hp = clampi((eng.hp_max * num * 2 + den) / (den * 2), 1, eng.hp_max)
	eng.summon.group_id = group
	eng.summon.src_kind = 1
	eng.summon.src_idx = src_idx
	eng.summon.src_pid = pid
	eng.summon.state = SimZoneConsts.SS_ADVANCE
	world.emit(SimZoneConsts.EV_ENGINE_ASSEMBLED, x, y, id, cap_id)
	if sys == null:
		return


## Dragonfall engine: advance on the nearest enemy structure (from the area centre first, later from itself within 20
## cells), else the nearest enemy of any kind.
static func _engine(world: SimWorld, e: SimEntity, sm: SimCompSummon) -> void:
	if not e.orders.is_empty() and e.orders[0].type == SimOrder.T_ATTACK and world.is_alive(e.orders[0].target_id):
		return
	var t: int = 0
	if sm.state == SimZoneConsts.SS_ADVANCE:
		t = nearest_enemy_structure(world, e.owner, sm.ax, sm.ay, 0x7FFFFFFF)
		sm.state = SimZoneConsts.SS_ATTACK
	else:
		t = nearest_enemy_structure(world, e.owner, e.x, e.y, SimZoneConsts.ENGINE_NEAR_STRUCT_U)
	if t == 0:
		t = world.nearest(e.x, e.y, 0x3FFFF, SimTag.ALIVE, world.non_enemy_mask(e.owner) | SimTag.kind_bit(SimEntity.Kind.WRECK) \
			| SimTag.kind_bit(SimEntity.Kind.ZONE) | SimTag.kind_bit(SimEntity.Kind.NEUTRAL), e.id)
	if t > 0:
		world.orders.issue_internal(world, e, SimOrder.T_ATTACK, t, 0, 0)


static func nearest_enemy_structure(world: SimWorld, pid: int, cx: int, cy: int, max_dist: int) -> int:
	var best: int = 0
	var best_d: int = 0
	var lim: int = max_dist * max_dist if max_dist < 0x10000 else 0x7FFFFFFFFFFF
	for p: SimPlayer in world.players:
		if p.controller == SimPlayer.Controller.NONE or not world.are_enemies(pid, p.pid):
			continue
		for s: SimEntity in world.structures_of(p.pid):
			if (s.flags & (SimFlags.F_GONE | SimFlags.F_UNDER_CONSTRUCTION)) != 0:
				continue
			var dx: int = s.x - cx
			var dy: int = s.y - cy
			var dd: int = dx * dx + dy * dy
			if dd > lim:
				continue
			if best == 0 or dd < best_d or (dd == best_d and s.id < best):
				best = s.id
				best_d = dd
	return best
