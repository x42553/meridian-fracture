class_name SimAirSortie
extends RefCounted
## Aircraft sortie machine (combat 5.12, task CB-08): missions, pads, rearm, patrol, forced return and the five attack
## styles. Stateless statics; all state is in SimCompAir / SimCompCombat (hashed). Runs in P2 of SimCombatSystem.update
## for every aircraft (ascending id, `air_ids`). Flight itself is the movement facade (SimMovement.air_*); the layer flips
## are movement's (air_takeoff / air_land_at).
##
## Pads: when the airfield carries economy's `prod.pad_ent` table (the real game) the pads are allocated through
## `world.production.airfield_pad_acquire / release / pad_cell / service_rate_bp`; without it (tests, standalone use)
## combat's own `air.pad_occ` and `is_functional` are used. Data note: DefAir does not exist, so the sortie numbers are
## DERIVED per unit def by `derive` (style from the weapons, fuel from the SORTIE ability, rearm from DefUnit.rearm_t).

const SEARCH_TICKS: int = 10  ## MI_ATTACK: wait this long for a next target after a kill
const RETRY_TICKS: int = 10  ## RETURN with no free pad: retry period
const REPOS_TICKS: int = 10  ## throttle of re-positioning orders
const LAND_DIST: int = 6144  ## RETURN -> LANDING when this close to the pad
const RUN_START: int = 16384  ## TRANSIT -> ATTACK at this distance from the target
const FALL_TICKS: int = SimWeaponProfile.FALL_TICKS
const DEFAULT_REARM: int = 240
const DEFAULT_FUEL: int = 3600
const HOVER_ARRIVE: int = 1536
const EGRESS_MAX: int = 200
const RUN_MAX: int = 600


# ---------------------------------------------------------------------------------------------------- derived data
## Fills the aircraft fields of `c` from the unit def (weapons, move class, SORTIE ability, rearm time).
static func derive(u: DefUnit, c: SimCombatDef) -> void:
	c.air_hover = 1 if u.move_class == DefEnums.MoveClass.AIR_HOVER else 0
	c.rearm_ticks = u.rearm_t if u.rearm_t > 0 else DEFAULT_REARM
	c.takeoff_ticks = 30 if c.air_hover == 1 else 20
	var sortie: DefAbility = u.ability_of(DefEnums.AbilityKind.SORTIE)
	var endurance: int = int(sortie.params.get("endurance_t", 0)) if sortie != null else 0
	c.fuel_max = endurance if endurance > 0 else DEFAULT_FUEL
	c.am_mode = 1
	var has_bomb: bool = false
	var has_missile: bool = false
	var any_air: bool = false
	var any_ground: bool = false
	for s: DefWeaponSlot in u.weapons:
		if s.proj_kind == DefEnums.ProjKind.BOMB:
			has_bomb = true
		elif s.proj_kind == DefEnums.ProjKind.MISSILE:
			has_missile = true
		if (s.target_mask & DefEnums.L_AIR) != 0:
			any_air = true
		if (s.target_mask & (DefEnums.L_GROUND | DefEnums.L_WATER)) != 0:
			any_ground = true
	if u.weapons.is_empty():
		c.air_style = SimCombatConsts.AS_NONE
	elif has_bomb:
		c.air_style = SimCombatConsts.AS_BOMB_RUN
	elif any_air and not any_ground:
		c.air_style = SimCombatConsts.AS_DOGFIGHT
	elif c.air_hover == 1:
		c.air_style = SimCombatConsts.AS_HOVER
	elif has_missile:
		c.air_style = SimCombatConsts.AS_MISSILE_RUN
	else:
		c.air_style = SimCombatConsts.AS_STRAFE


# ---------------------------------------------------------------------------------------------------- entry points
## Called by SimCombatSystem.on_spawn: full tank; parked when it spawned on the ground, else in free flight (AIR_NO_BASE
## without a mission: the sortie machine leaves the controls to the orders / movement until a mission arrives).
static func init_aircraft(world: SimWorld, e: SimEntity, cd: SimCombatDef) -> void:
	var a: SimCompAir = e.air
	a.fuel = cd.fuel_max
	a.state = SimCombatConsts.AIR_PARKED if e.layer == SimCombatConsts.LAYER_GROUND else SimCombatConsts.AIR_NO_BASE
	a.state_t0 = world.tick


## A non-combat order (move, patrol, land ...) takes the controls: the mission is dropped, a flying aircraft goes to free
## flight (AIR_NO_BASE, no mission). Called from SimCombatSystem.order_gate.
static func release_mission(world: SimWorld, e: SimEntity) -> void:
	var a: SimCompAir = e.air
	if a == null or a.is_airfield == 1:
		return
	if a.mission == SimCombatConsts.MI_NONE and a.resume_mission == SimCombatConsts.MI_NONE:
		return
	a.mission = SimCombatConsts.MI_NONE
	a.resume_mission = SimCombatConsts.MI_NONE
	a.m_target = -1
	a.search_until = 0
	SimTargeting.clear_target(e)
	var st: int = a.state
	if st == SimCombatConsts.AIR_TRANSIT or st == SimCombatConsts.AIR_ATTACK or st == SimCombatConsts.AIR_PATROL or st == SimCombatConsts.AIR_RETURN:
		if a.pad >= 0:
			var af: SimEntity = world.get_entity(a.home_id) if a.home_id > 0 else null
			if af != null:
				_pad_release(world, af, e)
			a.pad = -1
		_set_state(world, e, a, SimCombatConsts.AIR_NO_BASE)


## Production: puts a freshly spawned aircraft on a free pad of `airfield_id` (AIR_PARKED, layer GROUND). -1 = drone.
static func on_aircraft_spawned(world: SimWorld, e: SimEntity, airfield_id: int) -> void:
	var a: SimCompAir = e.air
	if a == null or a.is_airfield == 1 or airfield_id < 0:
		return
	var af: SimEntity = world.get_entity(airfield_id)
	if af == null or af.air == null or af.air.is_airfield == 0 or (af.flags & SimFlags.F_GONE) != 0:
		return
	var pad: int = _pad_reserve(world, af, e)
	if pad < 0:
		return
	a.home_id = af.id
	a.home_kind = SimCombatConsts.HOME_AIRFIELD
	a.pad = pad
	var pos: PackedInt32Array = _pad_pos(world, af, pad)
	world.set_pos(e, pos[0], pos[1], true)
	world.set_layer(e, SimCombatConsts.LAYER_GROUND)
	if e.move != null:
		e.move.air_mode = SimMoveConfig.AM_PARKED
		e.move.alt = 0
		e.move.spd_q4 = 0
	var cd: SimCombatDef = world.combat.def_for(world, e)
	if cd != null:
		a.fuel = cd.fuel_max
	a.mission = SimCombatConsts.MI_NONE
	_set_state(world, e, a, SimCombatConsts.AIR_PARKED)


## After Dispersed Runways or any pad-count change: resizes combat's own pad table to the def's count.
static func on_pads_changed(world: SimWorld, airfield: SimEntity) -> void:
	var a: SimCompAir = airfield.air
	if a == null or a.is_airfield == 0:
		return
	var cd: SimCombatDef = world.combat.def_for(world, airfield)
	var n: int = cd.pad_count if cd != null else a.pad_occ.size()
	var old: int = a.pad_occ.size()
	if n == old:
		return
	a.pad_occ.resize(n)
	for i: int in range(old, n):
		a.pad_occ[i] = -1


## Order handlers: gives `e` a mission. False when a mission that needs fuel / ammo cannot start.
static func assign_mission(world: SimWorld, e: SimEntity, mission: int, target_id: int, x: int, y: int, r: int) -> bool:
	var a: SimCompAir = e.air
	var cc: SimCompCombat = e.combat
	if a == null or a.is_airfield == 1 or cc == null or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return false
	var cd: SimCombatDef = world.combat.def_for(world, e)
	if cd == null:
		return false
	var offensive: bool = mission == SimCombatConsts.MI_ATTACK or mission == SimCombatConsts.MI_ATTACK_MOVE or mission == SimCombatConsts.MI_PATROL
	if mission != SimCombatConsts.MI_RETURN and (a.fuel <= 0 or (offensive and not usable_ammo(cc, cd))):
		return false
	var st: int = a.state
	if e.layer == SimCombatConsts.LAYER_GROUND and st != SimCombatConsts.AIR_PARKED and st != SimCombatConsts.AIR_REARM \
			and st != SimCombatConsts.AIR_TAKEOFF and st != SimCombatConsts.AIR_LANDING:
		st = SimCombatConsts.AIR_PARKED  # landed by a T_LAND order: it is on the ground
		_set_state(world, e, a, st)
	var same_patrol: bool = mission == SimCombatConsts.MI_PATROL and a.mission == SimCombatConsts.MI_PATROL and st == SimCombatConsts.AIR_PATROL
	a.mission = mission
	a.m_target = target_id if target_id > 0 else -1
	a.m_x = x
	a.m_y = y
	a.m_r = r
	a.resume_mission = SimCombatConsts.MI_NONE
	a.search_until = 0
	a.sub = 0
	if same_patrol:
		return true
	if mission != SimCombatConsts.MI_RETURN or st == SimCombatConsts.AIR_PARKED or st == SimCombatConsts.AIR_REARM:
		SimTargeting.clear_target(e)
	if st == SimCombatConsts.AIR_PARKED:
		if mission != SimCombatConsts.MI_RETURN:
			_set_state(world, e, a, SimCombatConsts.AIR_TAKEOFF)
	elif st == SimCombatConsts.AIR_REARM:
		pass  # launches by itself when the rearm is complete (auto resume)
	elif st == SimCombatConsts.AIR_TAKEOFF or st == SimCombatConsts.AIR_LANDING:
		pass  # finishes the manoeuvre first; TRANSIT / REARM pick the mission up
	elif mission == SimCombatConsts.MI_RETURN:
		if st != SimCombatConsts.AIR_RETURN:
			_set_state(world, e, a, SimCombatConsts.AIR_RETURN)
	else:
		if st == SimCombatConsts.AIR_RETURN and a.pad >= 0:
			var af: SimEntity = world.get_entity(a.home_id) if a.home_id > 0 else null
			if af != null:
				_pad_release(world, af, e)  # a new mission cancels the pad reserved for the landing
			a.pad = -1
		_set_state(world, e, a, SimCombatConsts.AIR_TRANSIT)
	return true


static func pads_free(world: SimWorld, airfield: SimEntity) -> int:
	var n: int = 0
	for i: int in _pad_count(world, airfield):
		if _pad_free(world, airfield, i):
			n += 1
	return n


static func pad_of(e: SimEntity) -> int:
	return e.air.pad if e.air != null else -1


static func sortie_state(e: SimEntity) -> int:
	return e.air.state if e.air != null else SimCombatConsts.AIR_PARKED


## An aircraft that dies or is removed frees its pad; drones will free their bay (CB-09).
static func release_links(world: SimWorld, _cs: SimCombatSystem, e: SimEntity) -> void:
	var a: SimCompAir = e.air
	if a == null or a.is_airfield == 1 or a.pad < 0:
		return
	var af: SimEntity = world.get_entity(a.home_id) if a.home_id > 0 else null
	if af != null:
		_pad_release(world, af, e)
	a.pad = -1


# ---------------------------------------------------------------------------------------------------- P2
static func update_all(world: SimWorld, cs: SimCombatSystem) -> void:
	for id: int in cs.air_ids:
		var e: SimEntity = world.get_entity(id)
		if e != null and e.air != null:
			update(world, cs, e)


static func update(world: SimWorld, cs: SimCombatSystem, e: SimEntity) -> void:
	if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return
	var a: SimCompAir = e.air
	var cc: SimCompCombat = e.combat
	if a == null or cc == null or a.is_airfield == 1 or (cc.cflags & SimCombatConsts.CF_DEAD) != 0:
		return
	var cd: SimCombatDef = cs.def_for(world, e)
	if cd == null:
		return
	match a.state:
		SimCombatConsts.AIR_TAKEOFF:
			_takeoff(world, e, a, cd)
		SimCombatConsts.AIR_TRANSIT:
			_burn(a)
			_transit(world, cs, e, a, cc, cd)
		SimCombatConsts.AIR_ATTACK:
			_burn(a)
			_attack_state(world, cs, e, a, cc, cd)
		SimCombatConsts.AIR_PATROL:
			_burn(a)
			_patrol(world, cs, e, a, cc, cd)
		SimCombatConsts.AIR_RETURN:
			_burn(a)
			_return(world, cs, e, a, cc, cd)
		SimCombatConsts.AIR_LANDING:
			_burn(a)
			_landing(world, e, a, cd)
		SimCombatConsts.AIR_REARM:
			_rearm(world, cs, e, a, cc, cd)
		SimCombatConsts.AIR_NO_BASE:
			_no_base(world, e, a, cd)


static func _burn(a: SimCompAir) -> void:
	if a.fuel > 0:
		a.fuel -= 1


static func _set_state(world: SimWorld, e: SimEntity, a: SimCompAir, st: int, sub: int = 0) -> void:
	a.state = st
	a.sub = sub
	a.state_t0 = world.tick
	a.sub_t0 = world.tick
	a.next_logic = 0
	world.emit(SimCombatConsts.EV_AIR_STATE, e.x, e.y, e.id, st, a.pad, a.home_id, sub)


# ---------------------------------------------------------------------------------------------------- ammo
## Any offensive mount that can still fire (infinite ammo counts).
static func usable_ammo(cc: SimCompCombat, cd: SimCombatDef) -> bool:
	if cd.n_mounts == 0:
		return false
	for m: int in cd.n_mounts:
		var ammo: int = cc.mnt[m * SimCombatConsts.MS + SimCombatConsts.M_AMMO]
		if ammo != 0:
			return true
	return false


static func ammo_now(cc: SimCompCombat, cd: SimCombatDef) -> int:
	var n: int = 0
	for m: int in cd.n_mounts:
		if cd.slots[cd.slot_of_mount(m)].ammo_volleys > 0:
			n += maxi(cc.mnt[m * SimCombatConsts.MS + SimCombatConsts.M_AMMO], 0)
	return n


static func ammo_total(cd: SimCombatDef) -> int:
	var n: int = 0
	for m: int in cd.n_mounts:
		n += maxi(cd.slots[cd.slot_of_mount(m)].ammo_volleys, 0)
	return n


static func _shots(cc: SimCompCombat, cd: SimCombatDef) -> int:
	var n: int = 0
	for m: int in cd.n_mounts:
		n += cc.mnt[m * SimCombatConsts.MS + SimCombatConsts.M_SHOTS]
	return n


# ---------------------------------------------------------------------------------------------------- take-off / transit
static func _takeoff(world: SimWorld, e: SimEntity, a: SimCompAir, cd: SimCombatDef) -> void:
	if a.sub == 0:
		if a.pad >= 0:
			var af: SimEntity = world.get_entity(a.home_id) if a.home_id > 0 else null
			if af != null:
				_pad_release(world, af, e)
			a.pad = -1
		SimMovement.air_takeoff(world, e, cd.takeoff_ticks)
		a.sub = 1
		return
	if e.layer == SimCombatConsts.LAYER_AIR:
		_set_state(world, e, a, SimCombatConsts.AIR_TRANSIT)
	elif world.tick - a.state_t0 > cd.takeoff_ticks * 20 + 60:
		world.set_layer(e, SimCombatConsts.LAYER_AIR)  # movement never lifted it: do not hang forever


static func _transit(world: SimWorld, cs: SimCombatSystem, e: SimEntity, a: SimCompAir, cc: SimCompCombat, cd: SimCombatDef) -> void:
	if e.layer != SimCombatConsts.LAYER_AIR:
		return
	if _must_return(world, e, a, cc, cd):
		return
	var tick: int = world.tick
	match a.mission:
		SimCombatConsts.MI_ATTACK:
			var dx: int = a.m_x
			var dy: int = a.m_y
			if a.m_target > 0:
				var t: SimEntity = world.get_entity(a.m_target)
				if t == null or (t.flags & SimFlags.F_GONE) != 0:
					_target_lost(world, cs, e, a, cc, cd)
					return
				dx = t.x
				dy = t.y
			if a.sub == 0 or tick >= a.next_logic:
				a.sub = 1
				a.next_logic = tick + REPOS_TICKS
				SimMovement.air_fly_to(world, e, dx, dy)
			if Fp.dist(dx - e.x, dy - e.y) <= RUN_START:
				_set_state(world, e, a, SimCombatConsts.AIR_ATTACK, SimCombatConsts.AP_APPROACH)
		SimCombatConsts.MI_ATTACK_MOVE, SimCombatConsts.MI_PATROL, SimCombatConsts.MI_MOVE:
			if a.sub == 0:
				a.sub = 1
				SimMovement.air_fly_to(world, e, a.m_x, a.m_y)
			elif SimMovement.air_at_goal(e):
				if a.mission == SimCombatConsts.MI_MOVE:
					return  # holds its pattern at the point
				_set_state(world, e, a, SimCombatConsts.AIR_PATROL)
		SimCombatConsts.MI_RETURN:
			_set_state(world, e, a, SimCombatConsts.AIR_RETURN)
		_:
			_set_state(world, e, a, SimCombatConsts.AIR_RETURN)  # no mission: go home


## Forced return: empty tank, no usable ammo on an offensive mission, or the fuel reserve plus the flight home.
static func _must_return(world: SimWorld, e: SimEntity, a: SimCompAir, cc: SimCompCombat, cd: SimCombatDef) -> bool:
	var offensive: bool = a.mission == SimCombatConsts.MI_ATTACK or a.mission == SimCombatConsts.MI_ATTACK_MOVE or a.mission == SimCombatConsts.MI_PATROL
	var reason: int = 0
	if a.fuel <= 0:
		reason = 1
	elif offensive and not usable_ammo(cc, cd):
		reason = 2
	elif world.tick >= a.next_logic and (world.tick + e.id) % 4 == 0:
		var pad: PackedInt32Array = _home_point(world, e, a)
		if pad.size() == 2:
			var spd: int = maxi(1, world.movement.speed_units(e))
			if a.fuel <= cd.fuel_reserve + Fp.dist(pad[0] - e.x, pad[1] - e.y) / spd:
				reason = 3
	if reason == 0:
		return false
	a.forced_return = reason
	_begin_return(world, e, a, cc)
	return true


## Remembers what to resume after the rearm, drops the target and heads home.
static func _begin_return(world: SimWorld, e: SimEntity, a: SimCompAir, cc: SimCompCombat) -> void:
	var m: int = a.mission
	if m == SimCombatConsts.MI_PATROL or m == SimCombatConsts.MI_ATTACK_MOVE or (m == SimCombatConsts.MI_ATTACK and a.m_target > 0 and world.is_alive(a.m_target)):
		a.resume_mission = m
		a.resume_target = a.m_target
		a.resume_x = a.m_x
		a.resume_y = a.m_y
	a.mission = SimCombatConsts.MI_RETURN
	SimTargeting.clear_target(e)
	cc.scan_next = world.tick
	_set_state(world, e, a, SimCombatConsts.AIR_RETURN)


## Target gone (dead / not engageable): next target near, else back to the patrol, else home.
static func _target_lost(world: SimWorld, _cs: SimCombatSystem, e: SimEntity, a: SimCompAir, cc: SimCompCombat, _cd: SimCombatDef) -> void:
	var tick: int = world.tick
	if cc.target_id >= 0 and cc.target_src == SimCombatConsts.TS_AUTO and a.mission != SimCombatConsts.MI_RETURN:
		var nt: SimEntity = world.get_entity(cc.target_id)
		if nt != null and (nt.flags & SimFlags.F_GONE) == 0:
			a.m_target = nt.id  # the scans found one: adopt it
			a.search_until = 0
			a.sub = SimCombatConsts.AP_APPROACH
			if a.state != SimCombatConsts.AIR_ATTACK:
				_set_state(world, e, a, SimCombatConsts.AIR_ATTACK, SimCombatConsts.AP_APPROACH)
			return
	if a.mission == SimCombatConsts.MI_PATROL or a.mission == SimCombatConsts.MI_ATTACK_MOVE:
		SimTargeting.clear_target(e, true)
		a.m_target = -1
		_set_state(world, e, a, SimCombatConsts.AIR_PATROL)
		return
	if a.search_until == 0:
		a.search_until = tick + SEARCH_TICKS
		SimTargeting.clear_target(e)
		cc.scan_next = tick
		SimMovement.air_hover(world, e)
		return
	if tick >= a.search_until:
		a.search_until = 0
		a.mission = SimCombatConsts.MI_RETURN
		a.m_target = -1
		SimTargeting.clear_target(e)
		_set_state(world, e, a, SimCombatConsts.AIR_RETURN)


# ---------------------------------------------------------------------------------------------------- patrol
static func _patrol(world: SimWorld, _cs: SimCombatSystem, e: SimEntity, a: SimCompAir, cc: SimCompCombat, cd: SimCombatDef) -> void:
	if _must_return(world, e, a, cc, cd):
		return
	var tick: int = world.tick
	if a.sub == 0:
		a.sub = 1
		SimMovement.air_orbit(world, e, a.m_x, a.m_y, a.m_r if a.m_r > 0 else cd.orbit_r)
	# an auto target found by the scans (stance permitting): engage, then resume the orbit
	if cc.target_id >= 0 and (cc.target_src == SimCombatConsts.TS_AUTO or cc.target_src == SimCombatConsts.TS_RETAL or cc.target_src == SimCombatConsts.TS_GUARD):
		var t: SimEntity = world.get_entity(cc.target_id)
		if t != null and (t.flags & SimFlags.F_GONE) == 0 and Fp.dist(t.x - a.m_x, t.y - a.m_y) <= cd.patrol_r + t.radius:
			a.m_target = t.id
			_set_state(world, e, a, SimCombatConsts.AIR_ATTACK, SimCombatConsts.AP_APPROACH)
			return
	if tick >= a.next_logic and a.sub == 1 and not SimMovement.air_at_goal(e) and e.move != null and e.move.air_mode != SimMoveConfig.AM_ORBIT:
		a.next_logic = tick + 20
		SimMovement.air_orbit(world, e, a.m_x, a.m_y, a.m_r if a.m_r > 0 else cd.orbit_r)


# ---------------------------------------------------------------------------------------------------- attack styles
static func _attack_state(world: SimWorld, cs: SimCombatSystem, e: SimEntity, a: SimCompAir, cc: SimCompCombat, cd: SimCombatDef) -> void:
	if a.sub != SimCombatConsts.AP_RELEASE and _must_return(world, e, a, cc, cd):
		return
	var t: SimEntity = null
	var point: bool = a.m_target <= 0
	if not point:
		t = world.get_entity(a.m_target)
		if t == null or (t.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
			_target_lost(world, cs, e, a, cc, cd)
			return
	var tx: int = t.x if t != null else a.m_x
	var ty: int = t.y if t != null else a.m_y
	var style: int = cd.air_style
	var releasing: bool = style == SimCombatConsts.AS_BOMB_RUN and a.sub == SimCombatConsts.AP_RELEASE
	if not releasing and style != SimCombatConsts.AS_BOMB_RUN:
		if t != null:
			if cc.target_id != t.id and not SimTargeting.set_target(world, e, t.id, SimCombatConsts.TS_ORDER):
				a.mission = SimCombatConsts.MI_RETURN  # cannot be engaged by any of our weapons
				SimTargeting.clear_target(e)
				_set_state(world, e, a, SimCombatConsts.AIR_RETURN)
				return
		elif cc.ground_on == 0:
			SimTargeting.set_ground_target(e, tx, ty)
	match style:
		SimCombatConsts.AS_HOVER:
			_hover(world, cs, e, a, cc, cd, t, tx, ty)
		SimCombatConsts.AS_BOMB_RUN:
			_bomb_run(world, e, a, cc, cd, t, tx, ty)
		SimCombatConsts.AS_DOGFIGHT:
			_dogfight(world, e, a, t, tx, ty)
		_:
			_run(world, e, a, cc, cd, t, tx, ty)


static func _hover(world: SimWorld, cs: SimCombatSystem, e: SimEntity, a: SimCompAir, _cc: SimCompCombat, cd: SimCombatDef, t: SimEntity, tx: int, ty: int) -> void:
	var tick: int = world.tick
	var range_u: int = cs.range_max_eff(world, e, -1)
	var hd: int = SimDamage.mul(range_u, cd.hover_bp)
	var dx: int = e.x - tx
	var dy: int = e.y - ty
	var d: int = Fp.dist(dx, dy)
	var hx: int = tx
	var hy: int = ty
	if d > 0:
		hx = tx + dx * hd / d
		hy = ty + dy * hd / d
	else:
		hx = tx + Fp.step_x(e.facing, hd)
		hy = ty + Fp.step_y(e.facing, hd)
	var to_h: int = Fp.dist(hx - e.x, hy - e.y)
	var d_eff: int = maxi(d - (t.radius if t != null else 0), 0)
	if a.sub != SimCombatConsts.AP_HOVER:
		if a.sub == SimCombatConsts.AP_APPROACH or tick >= a.next_logic:
			a.next_logic = tick + REPOS_TICKS
			SimMovement.air_fly_to(world, e, hx, hy)
			a.sub = SimCombatConsts.AP_PURSUE
		if to_h <= HOVER_ARRIVE:
			a.sub = SimCombatConsts.AP_HOVER
			SimMovement.air_hover(world, e)
			SimMovement.air_face(world, e, Fp.atan2(ty - e.y, tx - e.x))
	elif d_eff > range_u and tick >= a.next_logic:  # the target drifted out of range: re-position
		a.next_logic = tick + REPOS_TICKS
		a.sub = SimCombatConsts.AP_PURSUE
		SimMovement.air_fly_to(world, e, hx, hy)
	elif tick >= a.next_logic:
		a.next_logic = tick + REPOS_TICKS
		SimMovement.air_face(world, e, Fp.atan2(ty - e.y, tx - e.x))


## Bomb run (5.12): direction fixed at the start, release when the lead point Q = P + V * fall is within S / 2 + V / 2 of
## the target along the run; the release is done by P4 firing at the aircraft's own position.
static func _bomb_run(world: SimWorld, e: SimEntity, a: SimCompAir, cc: SimCompCombat, cd: SimCombatDef, t: SimEntity, tx: int, ty: int) -> void:
	var tick: int = world.tick
	var bm: int = _bomb_mount(cd)
	var burst: int = cd.pf(bm, SimWeaponProfile.PF_BURST) if bm >= 0 else 1
	var interval: int = cd.pf(bm, SimWeaponProfile.PF_BURST_INT) if bm >= 0 else 1
	match a.sub:
		SimCombatConsts.AP_APPROACH:
			var dx: int = tx - e.x
			var dy: int = ty - e.y
			var d: int = Fp.dist(dx, dy)
			if d < 64:
				dx = Fp.step_x(e.facing, 1 << 16)
				dy = Fp.step_y(e.facing, 1 << 16)
				d = Fp.dist(dx, dy)
			a.run_ux = dx * Fp.Q16 / d
			a.run_uy = dy * Fp.Q16 / d
			a.wx = tx + ((a.run_ux * cd.egress) >> 16)
			a.wy = ty + ((a.run_uy * cd.egress) >> 16)
			SimMovement.air_fly_to(world, e, a.wx, a.wy)
			a.sub = SimCombatConsts.AP_RUN
			a.sub_t0 = tick
		SimCombatConsts.AP_RUN:
			var v: int = Fp.dist(e.vx, e.vy)
			if v > 0:
				var qx: int = e.x + e.vx * FALL_TICKS
				var qy: int = e.y + e.vy * FALL_TICKS
				var along: int = ((tx - qx) * a.run_ux + (ty - qy) * a.run_uy) >> 16
				var s: int = (burst - 1) * v * interval
				if along <= s / 2 + v / 2:
					if along >= -(s + v) and usable_ammo(cc, cd):
						a.sub = SimCombatConsts.AP_RELEASE
						a.pass_count = _shots(cc, cd)
						a.release_left = burst
						a.sub_t0 = tick
						cc.ground_on = 1
						cc.ground_x = e.x
						cc.ground_y = e.y
						cc.target_id = -1
						cc.target_src = SimCombatConsts.TS_FORCE
					else:
						a.sub = SimCombatConsts.AP_EGRESS  # overshot: try another pass
						a.sub_t0 = tick
			if tick - a.sub_t0 > RUN_MAX:
				a.sub = SimCombatConsts.AP_EGRESS
				a.sub_t0 = tick
		SimCombatConsts.AP_RELEASE:
			cc.ground_on = 1
			cc.ground_x = e.x
			cc.ground_y = e.y
			cc.target_src = SimCombatConsts.TS_FORCE
			var done: bool = _shots(cc, cd) - a.pass_count >= a.release_left or tick - a.sub_t0 > burst * interval + 12
			if done:
				cc.ground_on = 0
				cc.target_src = SimCombatConsts.TS_NONE
				a.sub = SimCombatConsts.AP_EGRESS
				a.sub_t0 = tick
		_:  # AP_EGRESS: fly on to the waypoint, then again or home
			if Fp.dist(a.wx - e.x, a.wy - e.y) <= 3072 or tick - a.sub_t0 > EGRESS_MAX:
				if usable_ammo(cc, cd) and (t != null or a.m_target <= 0):
					a.sub = SimCombatConsts.AP_APPROACH
				else:
					a.mission = SimCombatConsts.MI_RETURN if a.mission == SimCombatConsts.MI_ATTACK else a.mission
					if a.mission == SimCombatConsts.MI_RETURN:
						_begin_return(world, e, a, cc)
					else:
						_target_lost(world, world.combat, e, a, cc, cd)


static func _bomb_mount(cd: SimCombatDef) -> int:
	for m: int in cd.n_mounts:
		if cd.pf(m, SimWeaponProfile.PF_KIND) == SimCombatConsts.PK_BOMB:
			return m
	return -1


## Missile run and strafe: fly at the target, P4 fires in the cone, then break away (egress), come back while ammo lasts.
static func _run(world: SimWorld, e: SimEntity, a: SimCompAir, cc: SimCompCombat, cd: SimCombatDef, t: SimEntity, tx: int, ty: int) -> void:
	var tick: int = world.tick
	var d: int = Fp.dist(tx - e.x, ty - e.y)
	if a.sub != SimCombatConsts.AP_EGRESS:
		if a.sub == SimCombatConsts.AP_APPROACH or tick >= a.next_logic:
			a.sub = SimCombatConsts.AP_RUN
			a.next_logic = tick + REPOS_TICKS
			SimMovement.air_fly_to(world, e, tx, ty)
		var fired: bool = cc.last_fire_tick >= a.sub_t0 and tick - cc.last_fire_tick >= 4
		var strafe: bool = cd.air_style == SimCombatConsts.AS_STRAFE
		var brk: bool = fired or tick - a.sub_t0 > RUN_MAX
		if strafe:
			brk = d < cd.strafe_min_sep or tick - a.sub_t0 > cd.strafe_max + 60
		if brk:
			a.sub = SimCombatConsts.AP_EGRESS
			a.sub_t0 = tick
			a.wx = tx + Fp.step_x(e.facing, cd.egress)
			a.wy = ty + Fp.step_y(e.facing, cd.egress)
			SimMovement.air_fly_to(world, e, a.wx, a.wy)
		return
	if Fp.dist(a.wx - e.x, a.wy - e.y) <= 3072 or tick - a.sub_t0 > EGRESS_MAX:
		if usable_ammo(cc, cd) and (t != null or a.m_target <= 0):
			a.sub = SimCombatConsts.AP_APPROACH
			a.sub_t0 = tick
		elif a.mission == SimCombatConsts.MI_ATTACK:
			_begin_return(world, e, a, cc)
		else:
			_begin_return(world, e, a, cc)


## Fighters: chase the lead point of the target, fire in the cone, break away deterministically when too close.
static func _dogfight(world: SimWorld, e: SimEntity, a: SimCompAir, t: SimEntity, tx: int, ty: int) -> void:
	var tick: int = world.tick
	if a.sub == SimCombatConsts.AP_EGRESS:
		if tick - a.sub_t0 >= 20:
			a.sub = SimCombatConsts.AP_PURSUE
			a.next_logic = 0
		return
	if tick >= a.next_logic:
		a.next_logic = tick + 4
		var lx: int = tx + (t.vx * 8 if t != null else 0)
		var ly: int = ty + (t.vy * 8 if t != null else 0)
		SimMovement.air_fly_to(world, e, lx, ly)
	if Fp.dist(tx - e.x, ty - e.y) < 2048:
		var sgn: int = 1 if ((e.id ^ (tick / 40)) & 1) == 0 else -1
		var ang: int = (e.facing + sgn * 512) & Fp.ANGLE_MASK
		a.wx = e.x + Fp.step_x(ang, 6144)
		a.wy = e.y + Fp.step_y(ang, 6144)
		a.sub = SimCombatConsts.AP_EGRESS
		a.sub_t0 = tick
		SimMovement.air_fly_to(world, e, a.wx, a.wy)


# ---------------------------------------------------------------------------------------------------- return / land / rearm
static func _return(world: SimWorld, _cs: SimCombatSystem, e: SimEntity, a: SimCompAir, _cc: SimCompCombat, cd: SimCombatDef) -> void:
	var tick: int = world.tick
	if e.layer != SimCombatConsts.LAYER_AIR:
		# it was ordered home while still on the ground (or spawned parked): nothing to fly
		_set_state(world, e, a, SimCombatConsts.AIR_PARKED)
		return
	if a.sub == 2:  # waiting for a free pad
		if tick >= a.next_logic:
			a.sub = 0
		return
	if a.sub == 0:
		var af: SimEntity = _pick_pad(world, e, a)
		if af == null:
			var near: SimEntity = _nearest_airfield(world, e, false)
			if near == null:
				_set_state(world, e, a, SimCombatConsts.AIR_NO_BASE)
				SimMovement.air_orbit(world, e, e.x, e.y, cd.orbit_r)
				return
			a.sub = 2  # every pad taken: circle the airfield and retry
			a.next_logic = tick + RETRY_TICKS
			SimMovement.air_orbit(world, e, near.x, near.y, cd.orbit_r)
			return
		var pos: PackedInt32Array = _pad_pos(world, af, a.pad)
		SimMovement.air_land_at(world, e, pos[0], pos[1], -1, cd.landing_ticks)
		a.sub = 1
		return
	var home: SimEntity = world.get_entity(a.home_id) if a.home_id > 0 else null
	if home == null or (home.flags & SimFlags.F_GONE) != 0:
		a.pad = -1
		a.home_id = -1
		a.sub = 0
		return
	var p: PackedInt32Array = _pad_pos(world, home, a.pad)
	if Fp.dist(p[0] - e.x, p[1] - e.y) <= LAND_DIST:
		_set_state(world, e, a, SimCombatConsts.AIR_LANDING)


static func _landing(world: SimWorld, e: SimEntity, a: SimCompAir, cd: SimCombatDef) -> void:
	var mv: SimCompMove = e.move
	if e.layer == SimCombatConsts.LAYER_GROUND and (mv == null or mv.air_mode == SimMoveConfig.AM_PARKED):
		a.fuel = cd.fuel_max
		a.rearm_prog = 0
		var cc: SimCompCombat = e.combat
		if a.resume_mission == SimCombatConsts.MI_NONE and a.mission == SimCombatConsts.MI_RETURN:
			a.mission = SimCombatConsts.MI_NONE
		SimTargeting.clear_target(e)
		if ammo_now(cc, cd) >= ammo_total(cd):
			_set_state(world, e, a, SimCombatConsts.AIR_PARKED)
			_maybe_resume(world, e, a, cd)
		else:
			_set_state(world, e, a, SimCombatConsts.AIR_REARM)
			world.emit(SimCombatConsts.EV_REARM, e.x, e.y, e.id, 0, ammo_now(cc, cd), a.home_id)
		return
	var home: SimEntity = world.get_entity(a.home_id) if a.home_id > 0 else null
	if home == null or (home.flags & SimFlags.F_GONE) != 0:
		a.pad = -1
		a.home_id = -1
		_set_state(world, e, a, SimCombatConsts.AIR_RETURN)


static func _rearm(world: SimWorld, cs: SimCombatSystem, e: SimEntity, a: SimCompAir, cc: SimCompCombat, cd: SimCombatDef) -> void:
	var af: SimEntity = world.get_entity(a.home_id) if a.home_id > 0 else null
	if af == null or (af.flags & SimFlags.F_GONE) != 0:
		a.home_id = -1
		a.pad = -1
		_set_state(world, e, a, SimCombatConsts.AIR_PARKED)  # homeless
		return
	var rate: int = _rate_bp(world, cs, af)
	if rate <= 0:
		return  # unpowered / EMP-shut pad: no progress
	var total: int = ammo_total(cd)
	if total <= 0:
		_finish_rearm(world, e, a, cc, cd)
		return
	var unit: int = cd.rearm_ticks * 10000 / total
	a.rearm_prog += rate
	while a.rearm_prog >= unit:
		var m: int = _rearm_mount(cc, cd)
		if m < 0:
			break
		a.rearm_prog -= unit
		cc.mnt[m * SimCombatConsts.MS + SimCombatConsts.M_AMMO] += 1
		world.emit(SimCombatConsts.EV_REARM, e.x, e.y, e.id, 1, ammo_now(cc, cd), af.id)
	if ammo_now(cc, cd) >= total:
		_finish_rearm(world, e, a, cc, cd)


## First mount (slot order) with finite ammo below its maximum, -1 when all are full.
static func _rearm_mount(cc: SimCompCombat, cd: SimCombatDef) -> int:
	for m: int in cd.n_mounts:
		var mx: int = cd.slots[cd.slot_of_mount(m)].ammo_volleys
		if mx > 0 and cc.mnt[m * SimCombatConsts.MS + SimCombatConsts.M_AMMO] < mx:
			return m
	return -1


static func _finish_rearm(world: SimWorld, e: SimEntity, a: SimCompAir, cc: SimCompCombat, cd: SimCombatDef) -> void:
	a.rearm_prog = 0
	world.emit(SimCombatConsts.EV_REARM, e.x, e.y, e.id, 2, ammo_now(cc, cd), a.home_id)
	_set_state(world, e, a, SimCombatConsts.AIR_PARKED)
	_maybe_resume(world, e, a, cd)


## auto_resume: a stored mission (patrol, attack whose target lives) or a mission given during the rearm restarts.
static func _maybe_resume(world: SimWorld, e: SimEntity, a: SimCompAir, cd: SimCombatDef) -> void:
	if a.resume_mission != SimCombatConsts.MI_NONE:
		var m: int = a.resume_mission
		var tg: int = a.resume_target
		if m == SimCombatConsts.MI_ATTACK and tg > 0 and not world.is_alive(tg):
			a.resume_mission = SimCombatConsts.MI_NONE
			return
		a.mission = m
		a.m_target = tg
		a.m_x = a.resume_x
		a.m_y = a.resume_y
		a.resume_mission = SimCombatConsts.MI_NONE
		if a.fuel > 0 and usable_ammo(e.combat, cd):
			_set_state(world, e, a, SimCombatConsts.AIR_TAKEOFF)
	elif a.mission != SimCombatConsts.MI_NONE and a.mission != SimCombatConsts.MI_RETURN:
		if a.fuel > 0 and usable_ammo(e.combat, cd):
			_set_state(world, e, a, SimCombatConsts.AIR_TAKEOFF)  # a mission arrived while rearming


static func _no_base(world: SimWorld, e: SimEntity, a: SimCompAir, cd: SimCombatDef) -> void:
	if a.mission == SimCombatConsts.MI_NONE:
		return  # free flight: orders / movement are in control
	if world.tick >= a.next_logic:
		a.next_logic = world.tick + RETRY_TICKS
		if _nearest_airfield(world, e, false) != null:
			_set_state(world, e, a, SimCombatConsts.AIR_RETURN)
		elif e.layer == SimCombatConsts.LAYER_AIR and e.move != null and e.move.air_mode != SimMoveConfig.AM_ORBIT and e.move.air_mode != SimMoveConfig.AM_HOVER:
			SimMovement.air_orbit(world, e, e.x, e.y, cd.orbit_r)


# ---------------------------------------------------------------------------------------------------- airfields and pads
static func _is_airfield(af: SimEntity) -> bool:
	return af.air != null and af.air.is_airfield == 1 and (af.flags & SimFlags.F_GONE) == 0


## The airfield to land at: the home one if alive, else the nearest own one (tie: squared distance, id). With
## `need_free` only airfields that have a free pad qualify.
static func _nearest_airfield(world: SimWorld, e: SimEntity, need_free: bool) -> SimEntity:
	var a: SimCompAir = e.air
	if a.home_id > 0:
		var h: SimEntity = world.get_entity(a.home_id)
		if h != null and _is_airfield(h) and h.owner == e.owner and (not need_free or pads_free(world, h) > 0 or _pad_held(world, h, e) >= 0):
			return h
	var best: SimEntity = null
	var best_d: int = 0
	for s: SimEntity in world.structures_of(e.owner):
		if not _is_airfield(s):
			continue
		if need_free and pads_free(world, s) <= 0 and _pad_held(world, s, e) < 0:
			continue
		var dx: int = s.x - e.x
		var dy: int = s.y - e.y
		var d2: int = dx * dx + dy * dy
		if best == null or d2 < best_d:
			best = s
			best_d = d2
	return best


## Picks the airfield, reserves a pad (sets home_id / pad); null when none has a free pad.
static func _pick_pad(world: SimWorld, e: SimEntity, a: SimCompAir) -> SimEntity:
	var af: SimEntity = _nearest_airfield(world, e, true)
	if af == null:
		return null
	var pad: int = _pad_reserve(world, af, e)
	if pad < 0:
		return null
	a.home_id = af.id
	a.home_kind = SimCombatConsts.HOME_AIRFIELD
	a.pad = pad
	return af


static func _home_point(world: SimWorld, e: SimEntity, a: SimCompAir) -> PackedInt32Array:
	var af: SimEntity = null
	if a.home_id > 0:
		af = world.get_entity(a.home_id)
		if af != null and not _is_airfield(af):
			af = null
	if af == null:
		af = _nearest_airfield(world, e, false)
	if af == null:
		return PackedInt32Array()
	return PackedInt32Array([af.x, af.y])


static func _uses_prod(af: SimEntity) -> bool:
	return af.prod != null and af.prod.pad_ent.size() > 0


static func _pad_count(_world: SimWorld, af: SimEntity) -> int:
	return af.prod.pad_ent.size() if _uses_prod(af) else af.air.pad_occ.size()


static func _pad_free(_world: SimWorld, af: SimEntity, i: int) -> bool:
	return af.prod.pad_ent[i] == 0 if _uses_prod(af) else af.air.pad_occ[i] < 0


## Pad index already held by `e` (-1 none).
static func _pad_held(_world: SimWorld, af: SimEntity, e: SimEntity) -> int:
	if _uses_prod(af):
		return af.prod.pad_ent.find(e.id)
	return af.air.pad_occ.find(e.id)


static func _pad_reserve(world: SimWorld, af: SimEntity, e: SimEntity) -> int:
	if _uses_prod(af):
		return world.production.airfield_pad_acquire(world, af.id, e.id)
	var held: int = af.air.pad_occ.find(e.id)
	if held >= 0:
		return held
	for i: int in af.air.pad_occ.size():
		if af.air.pad_occ[i] < 0:
			af.air.pad_occ[i] = e.id
			return i
	return -1


static func _pad_release(world: SimWorld, af: SimEntity, e: SimEntity) -> void:
	if _uses_prod(af):
		world.production.airfield_pad_release(world, af.id, e.id)
	if af.air != null:
		var i: int = af.air.pad_occ.find(e.id)
		if i >= 0:
			af.air.pad_occ[i] = -1


## Touchdown point of pad `pad`: economy's pad cell, else a row along the airfield's centre.
static func _pad_pos(world: SimWorld, af: SimEntity, pad: int) -> PackedInt32Array:
	if _uses_prod(af):
		var cell: int = world.production.airfield_pad_cell(world, af.id, pad)
		if cell >= 0:
			return PackedInt32Array([world.map.center_x(cell), world.map.center_y(cell)])
	var n: int = maxi(_pad_count(world, af), 1)
	return PackedInt32Array([af.x + (2 * maxi(pad, 0) - (n - 1)) * 512, af.y])


## Rearm progress per tick in bp (10000 = base): 0 when the airfield is unpowered / EMP-shut.
static func _rate_bp(world: SimWorld, cs: SimCombatSystem, af: SimEntity) -> int:
	if _uses_prod(af):
		return world.production.airfield_service_rate_bp(world, af.id)
	if not cs.is_functional(world, af) or af.combat == null:
		return 0
	return maxi(0, 10000 + SimCombatMods.sum_bp(af.combat, SimCombatConsts.STAT_REARM_RATE, world.tick))
