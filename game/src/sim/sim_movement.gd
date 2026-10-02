class_name SimMovement
extends RefCounted
## The static facade every other domain calls (terrain_movement 3.10.2). Goals are recorded on the unit's SimCompMove
## and executed by SimMovementSystem.update in stage 6 (goals set in stage 5 start in the same tick). A refused
## goal returns false and sets `result` (RS_IMMOBILE / RS_NO_MOVE / RS_BAD_TARGET); the state is left untouched.
## The air_* primitives delegate to SimAirMove, find_free_cell_near / eject_units_from_rect to SimExitMove (task MV2).


# ---- primitives named by combat.md 3.8 / economy.md 13-15 ----------------------------------------------------------

static func move_to(world: SimWorld, e: SimEntity, x: int, y: int, flags: int = 0) -> void:
	go_to(world, e, x, y, flags)


static func move_to_range(world: SimWorld, e: SimEntity, tx: int, ty: int, range_units: int) -> void:
	go_near(world, e, tx, ty, range_units)


## soft = decelerate; hard = speed 0 now. Clears the goal, cancels the path request, wakes the unit for separation.
static func stop(world: SimWorld, e: SimEntity, hard: bool = false) -> void:
	var mv: SimCompMove = e.move
	if mv == null:
		return
	if mv.mc >= MapTerrain.MC_AIR_FIXED:
		if mv.air_mode == SimMoveConfig.AM_CRUISE or mv.air_mode == SimMoveConfig.AM_APPROACH:
			SimAirMove.hover(world, e)
		return
	var ms: SimMovementSystem = world.movement
	if ms.path != null:
		ms.path.cancel(e.id)
	mv.req_id = 0
	mv.route_x = -1
	var st: int = mv.state
	if st != SimMoveConfig.MS_IDLE and st != SimMoveConfig.MS_ARRIVED and st != SimMoveConfig.MS_NO_PATH:
		mv.result = SimMoveConfig.RS_CANCELLED
	mv.state = SimMoveConfig.MS_IDLE
	mv.goal_kind = SimMoveConfig.GK_NONE
	mv.goal_target = -1
	mv.path = PackedInt32Array()
	mv.wp = 0
	mv.wait = 0
	mv.stuck_cnt = 0
	mv.nudge_t = 0
	mv.g_n = 0
	mv.g_t = 0
	mv.flags &= ~(SimMoveConfig.MF_REVERSING | SimMoveConfig.MF_PATH_PARTIAL)
	if hard:
		mv.spd_q4 = 0


## Turn in place (INSTANT / PIVOT) or slowly (ARC); done (state MS_IDLE, RS_OK) when |err| < 64.
static func turn_to(world: SimWorld, e: SimEntity, facing_bat: int) -> void:
	var mv: SimCompMove = e.move
	if mv == null or mv.mc >= MapTerrain.MC_AIR_FIXED:
		return
	var ms: SimMovementSystem = world.movement
	ms.path.cancel(e.id)
	mv.req_id = 0
	mv.goal_kind = SimMoveConfig.GK_FACE
	mv.goal_x = facing_bat & 4095
	mv.goal_target = -1
	mv.path = PackedInt32Array()
	mv.wp = 0
	mv.g_n = 0
	mv.state = SimMoveConfig.MS_FACING
	mv.result = SimMoveConfig.RS_NONE


static func is_moving(e: SimEntity) -> bool:
	var mv: SimCompMove = e.move
	if mv == null:
		return false
	return mv.spd_q4 != 0 or mv.state == SimMoveConfig.MS_MOVING or mv.state == SimMoveConfig.MS_WAIT_PATH


static func request_move(world: SimWorld, e: SimEntity, x: int, y: int, flags: int = 0) -> bool:
	return go_to(world, e, x, y, flags)


static func at_goal(e: SimEntity) -> bool:
	return e.move != null and e.move.state == SimMoveConfig.MS_ARRIVED


static func path_failed(e: SimEntity) -> bool:
	return e.move != null and e.move.state == SimMoveConfig.MS_NO_PATH


# ---- goals -----------------------------------------------------------------------------------------------------------

static func go_to(world: SimWorld, e: SimEntity, x: int, y: int, opts: int = 0) -> bool:
	return _set_goal(world, e, SimMoveConfig.GK_POINT, x, y, 0, -1, opts)


## Formation leg: the unit ends at (x, y) (its slot) but its path is searched to the group target (route_x, route_y), so
## a whole group shares one cached path. The last leg cuts straight to the slot as soon as it is in line of sight.
static func go_to_slot(world: SimWorld, e: SimEntity, x: int, y: int, route_x: int, route_y: int, opts: int = 0) -> bool:
	return _set_goal(world, e, SimMoveConfig.GK_POINT, x, y, 0, -1, opts, route_x, route_y)


static func go_near(world: SimWorld, e: SimEntity, x: int, y: int, range_units: int, opts: int = 0) -> bool:
	return _set_goal(world, e, SimMoveConfig.GK_NEAR, x, y, maxi(0, range_units), -1, opts)


## Path to the target's nearest passable cell; stops as soon as dist(centre, target) - target.radius <= range.
## Re-plans when the target moves more than 3 cells.
static func approach_entity(world: SimWorld, e: SimEntity, target_id: int, range_units: int, opts: int = 0) -> bool:
	var t: SimEntity = world.get_entity(target_id)
	if t == null or t.id == e.id or (t.flags & SimFlags.F_GONE) != 0:
		if e.move != null:
			e.move.result = SimMoveConfig.RS_BAD_TARGET
		return false
	return _set_goal(world, e, SimMoveConfig.GK_APPROACH, t.x, t.y, maxi(0, range_units), t.id, opts)


## Keeps within `max_d` of the target (min_d is not used by this implementation); never arrives.
static func follow(world: SimWorld, e: SimEntity, target_id: int, _min_d: int, max_d: int, opts: int = 0) -> bool:
	var t: SimEntity = world.get_entity(target_id)
	if t == null or t.id == e.id or (t.flags & SimFlags.F_GONE) != 0:
		if e.move != null:
			e.move.result = SimMoveConfig.RS_BAD_TARGET
		return false
	return _set_goal(world, e, SimMoveConfig.GK_FOLLOW, t.x, t.y, maxi(0, max_d), t.id, opts)


static func pause(_world: SimWorld, e: SimEntity) -> void:
	var mv: SimCompMove = e.move
	if mv == null:
		return
	if mv.state == SimMoveConfig.MS_MOVING or mv.state == SimMoveConfig.MS_BLOCKED or mv.state == SimMoveConfig.MS_WAIT_PATH:
		mv.state = SimMoveConfig.MS_PAUSED


static func resume(_world: SimWorld, e: SimEntity) -> void:
	var mv: SimCompMove = e.move
	if mv == null or mv.state != SimMoveConfig.MS_PAUSED:
		return
	if mv.goal_kind == SimMoveConfig.GK_NONE:
		mv.state = SimMoveConfig.MS_IDLE
	elif mv.req_id != 0:
		mv.state = SimMoveConfig.MS_WAIT_PATH
	else:
		mv.state = SimMoveConfig.MS_MOVING


## Scripted straight-line move over EXACTLY `ticks` ticks (>= 1): no path, no terrain rule, immune to and not part of
## separation. Ends in MS_ARRIVED at (x, y).
static func glide(world: SimWorld, e: SimEntity, x: int, y: int, ticks: int, face_angle: int = -1) -> void:
	var mv: SimCompMove = e.move
	if mv == null:
		return
	world.movement.path.cancel(e.id)
	mv.req_id = 0
	mv.goal_kind = SimMoveConfig.GK_GLIDE
	mv.goal_target = -1
	mv.path = PackedInt32Array()
	mv.wp = 0
	mv.g_x0 = e.x
	mv.g_y0 = e.y
	mv.g_x1 = clampi(x, 0, world.map.w * SimMoveConfig.CELL - 1)
	mv.g_y1 = clampi(y, 0, world.map.h * SimMoveConfig.CELL - 1)
	mv.g_t = 0
	mv.g_n = maxi(1, ticks)
	mv.spd_q4 = 0
	mv.result = SimMoveConfig.RS_NONE
	mv.state = SimMoveConfig.MS_GLIDE
	if face_angle >= 0:
		e.facing = face_angle & 4095
	elif mv.g_x1 != e.x or mv.g_y1 != e.y:
		e.facing = Fp.atan2(mv.g_y1 - e.y, mv.g_x1 - e.x)


## Short deterministic goal 2-3 cells perpendicular to `dir_angle` (the requester's heading), on the side whose cell is
## passable (tie: right). At most one sidestep per unit per 20 ticks and SIDESTEP_PER_TICK per tick.
static func sidestep(world: SimWorld, e: SimEntity, dir_angle: int, dist: int) -> void:
	var mv: SimCompMove = e.move
	if mv == null or mv.mc >= MapTerrain.MC_AIR_FIXED:
		return
	var ms: SimMovementSystem = world.movement
	if world.tick - mv.side_t < SimMoveConfig.SIDESTEP_MIN_INTERVAL:
		return
	if ms.side_tick != world.tick:
		ms.side_tick = world.tick
		ms.side_cnt = 0
	if ms.side_cnt >= SimMoveConfig.SIDESTEP_PER_TICK:
		return
	var d: int = dist if dist >= SimMoveConfig.CELL else 2 * SimMoveConfig.CELL + SimMoveConfig.CELL / 2
	var nav: MapNav = world.map.nav
	var tx: int = 0
	var ty: int = 0
	var ok: bool = false
	for side: int in [1024, -1024]:
		var a: int = dir_angle + side
		tx = clampi(e.x + Fp.step_x(a, d), 2048, world.map.w * SimMoveConfig.CELL - 2049)
		ty = clampi(e.y + Fp.step_y(a, d), 2048, world.map.h * SimMoveConfig.CELL - 2049)
		if nav.passable(mv.np, mv.nav_size, (ty >> 10) * world.map.w + (tx >> 10)):
			ok = true
			break
	if not ok:
		return
	ms.side_cnt += 1
	mv.side_t = world.tick
	ms.path.cancel(e.id)
	mv.req_id = 0
	mv.goal_kind = SimMoveConfig.GK_SIDESTEP
	mv.goal_x = tx
	mv.goal_y = ty
	mv.goal_range = 0
	mv.goal_target = -1
	mv.goal_opts = 0
	mv.path = PackedInt32Array()
	mv.wp = 0
	mv.stuck_cnt = 0
	mv.state = SimMoveConfig.MS_SIDESTEP


## Submarines: SURFACE <-> UNDERWATER after `ticks` ticks (world.set_layer + EV_LAYER_CHANGED).
static func request_layer(_world: SimWorld, e: SimEntity, layer: int, ticks: int) -> void:
	var mv: SimCompMove = e.move
	if mv == null:
		return
	mv.lr_layer = layer
	mv.lr_t = maxi(1, ticks)


# ---- status ----------------------------------------------------------------------------------------------------------

static func state(e: SimEntity) -> int:
	return e.move.state if e.move != null else SimMoveConfig.MS_IDLE


static func result(e: SimEntity) -> int:
	return e.move.result if e.move != null else SimMoveConfig.RS_NONE


## Acknowledges a terminal state: MS_ARRIVED / MS_NO_PATH -> MS_IDLE (goal cleared, result kept).
static func ack(_world: SimWorld, e: SimEntity) -> void:
	var mv: SimCompMove = e.move
	if mv == null:
		return
	if mv.state == SimMoveConfig.MS_ARRIVED or mv.state == SimMoveConfig.MS_NO_PATH:
		mv.state = SimMoveConfig.MS_IDLE
		mv.goal_kind = SimMoveConfig.GK_NONE
		mv.goal_target = -1
		mv.path = PackedInt32Array()
		mv.wp = 0


static func dist_to_goal(e: SimEntity) -> int:
	var mv: SimCompMove = e.move
	if mv == null:
		return 0
	return Fp.dist(mv.goal_x - e.x, mv.goal_y - e.y)


static func is_on_water(e: SimEntity) -> bool:
	return (e.flags & SimFlags.F_ON_WATER) != 0


static func speed_q4(e: SimEntity) -> int:
	return e.move.spd_q4 if e.move != null else 0


## out[0], out[1] = displacement applied in the last tick (units per tick).
static func velocity(e: SimEntity, out: PackedInt32Array) -> void:
	if out.size() < 2:
		out.resize(2)
	out[0] = e.vx
	out[1] = e.vy


## Estimated travel time in ticks (terrain % and water ignored, stat modifiers included); -1 unreachable.
static func eta_ticks(world: SimWorld, e: SimEntity, x: int, y: int) -> int:
	var mv: SimCompMove = e.move
	if mv == null:
		return -1
	var map: MapData = world.map
	var a: int = clampi(e.y >> 10, 0, map.h - 1) * map.w + clampi(e.x >> 10, 0, map.w - 1)
	var b: int = clampi(y >> 10, 0, map.h - 1) * map.w + clampi(x >> 10, 0, map.w - 1)
	var cost: int = map.nav.estimate_cost(mv.np, mv.nav_size, a, b)
	if cost < 0:
		return -1
	return cost * 1024 / (10 * maxi(1, world.movement.speed_units(e)))


# ---- internals -------------------------------------------------------------------------------------------------------

static func _set_goal(world: SimWorld, e: SimEntity, kind: int, x: int, y: int, range_u: int, target: int, opts: int, route_x: int = -1, route_y: int = -1) -> bool:
	var mv: SimCompMove = e.move
	var ms: SimMovementSystem = world.movement
	if mv == null or not ms.ready or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return false
	if mv.mc >= MapTerrain.MC_AIR_FIXED:
		mv.result = SimMoveConfig.RS_NO_MOVE
		return false
	if ms.is_immobile(world, e):
		mv.result = SimMoveConfig.RS_IMMOBILE
		ms.request_pack(world, e)
		return false
	ms.path.cancel(e.id)
	mv.g_n = 0
	mv.g_t = 0
	mv.goal_kind = kind
	mv.goal_x = clampi(x, 2048, world.map.w * SimMoveConfig.CELL - 2049)
	mv.goal_y = clampi(y, 2048, world.map.h * SimMoveConfig.CELL - 2049)
	mv.goal_range = range_u
	mv.goal_target = target
	mv.goal_opts = opts
	mv.route_x = -1 if route_x < 0 else clampi(route_x, 2048, world.map.w * SimMoveConfig.CELL - 2049)
	mv.route_y = -1 if route_x < 0 else clampi(route_y, 2048, world.map.h * SimMoveConfig.CELL - 2049)
	mv.goal_tick = world.tick
	mv.result = SimMoveConfig.RS_NONE
	var f: int = mv.flags & SimMoveConfig.MF_ON_WATER
	if (opts & SimMoveConfig.OPT_PRECISE) != 0:
		f |= SimMoveConfig.MF_PRECISE
	if (opts & SimMoveConfig.OPT_SPEED_MATCH) != 0:
		f |= SimMoveConfig.MF_SPEED_MATCH
	if (opts & SimMoveConfig.OPT_ATTACK_MOVE) != 0:
		f |= SimMoveConfig.MF_ATTACK_MOVE
	mv.flags = f
	mv.path = PackedInt32Array()
	mv.wp = 0
	mv.path_ver = -1
	mv.wait = 0
	mv.stuck_cnt = 0
	mv.stuck_x = e.x
	mv.stuck_y = e.y
	mv.blocked_t = 0
	mv.blocked_by = -1
	mv.nudge_t = 0
	mv.state = SimMoveConfig.MS_WAIT_PATH
	var prio: int = SimPathService.PRIO_ECON if (opts & SimMoveConfig.OPT_PRIO_ECON) != 0 else SimPathService.PRIO_ORDER
	ms.request_path(world, e, mv, prio, 0, PackedInt32Array())
	return true


# ---- exits, spawn placement, eject (SimExitMove) ---------------------------------------------------------------------

## First qualifying cell of rings 0..max_radius around `cell` for the layer's default profile; -1 if none.
static func find_free_cell_near(world: SimWorld, cell: int, layer: int, max_radius: int) -> int:
	return SimExitMove.find_free_cell_near(world, cell, layer, max_radius)


## Units of `team` inside the inclusive cell rect are moved out (ascending id) to the nearest free cell outside it;
## a unit without one starts MS_EVICT and drives out.
static func eject_units_from_rect(world: SimWorld, x0: int, y0: int, x1: int, y1: int, team: int) -> void:
	SimExitMove.eject_units_from_rect(world, x0, y0, x1, y1, team)


# ---- air primitives (SimAirMove): recorded now, flown by stage 6 of the next tick --------------------------------------

static func air_fly_to(world: SimWorld, e: SimEntity, x: int, y: int) -> void:
	SimAirMove.fly_to(world, e, x, y)


static func air_orbit(world: SimWorld, e: SimEntity, cx: int, cy: int, r: int, dir: int = 1) -> void:
	SimAirMove.orbit(world, e, cx, cy, r, dir)


static func air_hover(world: SimWorld, e: SimEntity) -> void:
	SimAirMove.hover(world, e)


static func air_face(world: SimWorld, e: SimEntity, facing_bat: int) -> void:
	SimAirMove.face(world, e, facing_bat)


static func air_takeoff(world: SimWorld, e: SimEntity, ticks: int = 0) -> void:
	SimAirMove.takeoff(world, e, ticks)


static func air_land_at(world: SimWorld, e: SimEntity, x: int, y: int, heading: int = -1, ticks: int = 0) -> void:
	SimAirMove.land_at(world, e, x, y, heading, ticks)


static func air_at_goal(e: SimEntity) -> bool:
	return SimAirMove.at_goal(e)


static func altitude(e: SimEntity) -> int:
	return e.move.alt if e.move != null else 0
