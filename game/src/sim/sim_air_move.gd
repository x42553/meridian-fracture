class_name SimAirMove
extends RefCounted
## Flight primitives (terrain_movement 5.6): HOW an aircraft flies; combat decides what it does. Every primitive only
## records the mode on the unit's SimCompMove (air_mode, goal_x/y, orbit_*, land_*, g_t/g_n, air_phase); the flight step
## runs once per tick from SimMovementSystem (stage 6) for aircraft whose air_mode is not AM_PARKED. No terrain rule,
## no path service, no separation grids (parked aircraft cost nothing). The entity layer changes only in takeoff (-> AIR)
## and at touchdown (-> GROUND). Altitude and climb rates are cosmetic except for the layer flip at alt >= FLIP_ALT.
##
## air_phase bits: AP_AT_GOAL latched at arrival / touchdown, AP_FINAL = the landing approach reached the glide slope,
## AP_ROLLED = the fixed-wing take-off roll reached flying speed.

const AP_AT_GOAL: int = 1
const AP_FINAL: int = 2
const AP_ROLLED: int = 4

const EV_AIR_TAKEOFF: int = 102  ## unit id . 0 . 0 (x, y in the header); sim_core 6.4 block 100-129
const EV_AIR_LANDED: int = 103

const FLIP_ALT: int = 512
const ALT_FIXED: int = 6144
const ALT_HOVER: int = 2560
const CLIMB_FIXED: int = 128
const CLIMB_HOVER: int = 96
const DESCEND_HOVER: int = 64
const APPROACH_ALT: int = 1024
const APPROACH_DIST: int = 5120  ## fixed-wing approach point: this far before the touchdown point
const FIXED_MIN_PCT: int = 60  ## movement.json air.fixed_min_speed_pct
const TOUCH_PCT: int = 35  ## speed at touchdown, % of vmax
const ORBIT_R_DEFAULT: int = 4096  ## movement.json air.orbit_r_default
const ARRIVE_ROTOR: int = 256
const TURN_RADIUS_K: int = 652  ## 4096 / (2 pi)
const EDGE_MARGIN: int = 2048
const ORBIT_SLACK: int = 512


# ---- primitives (facade SimMovement.air_*) --------------------------------------------------------------------------

static func is_air(mv: SimCompMove) -> bool:
	return mv != null and (mv.mc == MapTerrain.MC_AIR_FIXED or mv.mc == MapTerrain.MC_AIR_HOVER)


static func at_goal(e: SimEntity) -> bool:
	var mv: SimCompMove = e.move
	return is_air(mv) and (mv.air_phase & AP_AT_GOAL) != 0


static func cruise_alt(mv: SimCompMove) -> int:
	return ALT_FIXED if mv.mc == MapTerrain.MC_AIR_FIXED else ALT_HOVER


## True when the aircraft can start a flight command now (in the air; a parked-in-the-air aircraft is started).
static func _flyable(world: SimWorld, e: SimEntity, mv: SimCompMove) -> bool:
	if not is_air(mv) or e.layer != SimEntity.Layer.AIR or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return false
	if mv.air_mode == SimMoveConfig.AM_PARKED:  # spawned airborne: flying from now on
		mv.alt = cruise_alt(mv)
		mv.alt_goal = mv.alt
		if mv.mc == MapTerrain.MC_AIR_FIXED:
			mv.spd_q4 = world.movement.speed_units(e) * 16 * FIXED_MIN_PCT / 100
		mv.air_mode = SimMoveConfig.AM_HOVER
	return true


static func fly_to(world: SimWorld, e: SimEntity, x: int, y: int) -> void:
	var mv: SimCompMove = e.move
	if not _flyable(world, e, mv):
		return
	mv.goal_kind = SimMoveConfig.GK_POINT
	mv.goal_tick = world.tick
	mv.goal_x = clampi(x, 0, world.map.w * SimMoveConfig.CELL - 1)
	mv.goal_y = clampi(y, 0, world.map.h * SimMoveConfig.CELL - 1)
	mv.air_mode = SimMoveConfig.AM_CRUISE
	mv.air_phase = 0
	mv.alt_goal = cruise_alt(mv)
	mv.result = SimMoveConfig.RS_NONE


static func orbit(world: SimWorld, e: SimEntity, cx: int, cy: int, r: int, dir: int = 1) -> void:
	var mv: SimCompMove = e.move
	if not _flyable(world, e, mv):
		return
	mv.goal_kind = SimMoveConfig.GK_NONE
	mv.orbit_x = cx
	mv.orbit_y = cy
	mv.orbit_r = r if r > 0 else ORBIT_R_DEFAULT
	mv.orbit_dir = -1 if dir < 0 else 1
	mv.air_mode = SimMoveConfig.AM_ORBIT
	mv.air_phase = 0
	mv.alt_goal = cruise_alt(mv)


## Rotor: decelerate to a stop and hold. Fixed-wing cannot hover: it circles the current position.
static func hover(world: SimWorld, e: SimEntity) -> void:
	var mv: SimCompMove = e.move
	if not is_air(mv):
		return
	if mv.mc == MapTerrain.MC_AIR_FIXED:
		orbit(world, e, e.x, e.y, ORBIT_R_DEFAULT, mv.orbit_dir)
		return
	if not _flyable(world, e, mv):
		return
	mv.goal_kind = SimMoveConfig.GK_NONE
	mv.air_mode = SimMoveConfig.AM_HOVER


## Rotor: yaw in place toward `facing_bat` at turn_rate (a moving rotor stops first). Fixed-wing: no-op.
static func face(world: SimWorld, e: SimEntity, facing_bat: int) -> void:
	var mv: SimCompMove = e.move
	if not is_air(mv) or mv.mc != MapTerrain.MC_AIR_HOVER or not _flyable(world, e, mv):
		return
	mv.air_mode = SimMoveConfig.AM_HOVER
	mv.goal_kind = SimMoveConfig.GK_FACE
	mv.goal_x = facing_bat & 4095


## From AM_PARKED on the ground. `ticks` > 0: the layer flips exactly `ticks` flight steps after the call.
static func takeoff(world: SimWorld, e: SimEntity, ticks: int = 0) -> void:
	var mv: SimCompMove = e.move
	if not is_air(mv) or mv.air_mode != SimMoveConfig.AM_PARKED or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return
	if e.layer == SimEntity.Layer.AIR:  # already flying: nothing to lift off
		_flyable(world, e, mv)
		hover(world, e)
		world.emit(EV_AIR_TAKEOFF, e.x, e.y, e.id)
		return
	mv.air_mode = SimMoveConfig.AM_TAKEOFF
	mv.g_t = 0
	mv.g_n = maxi(0, ticks)
	mv.spd_q4 = 0
	mv.alt = 0
	mv.alt_goal = 0
	mv.orbit_x = e.x
	mv.orbit_y = e.y
	mv.orbit_r = ORBIT_R_DEFAULT
	mv.air_phase = 0
	mv.goal_kind = SimMoveConfig.GK_NONE
	mv.state = SimMoveConfig.MS_MOVING


## `heading` -1 = straight in from the current bearing. `ticks` > 0: the final descent lasts exactly that many steps.
static func land_at(world: SimWorld, e: SimEntity, x: int, y: int, heading: int = -1, ticks: int = 0) -> void:
	var mv: SimCompMove = e.move
	if not _flyable(world, e, mv):
		return
	var px: int = clampi(x, 0, world.map.w * SimMoveConfig.CELL - 1)
	var py: int = clampi(y, 0, world.map.h * SimMoveConfig.CELL - 1)
	mv.land_x = px
	mv.land_y = py
	mv.g_t = 0
	mv.g_n = maxi(0, ticks)
	mv.air_phase = 0
	mv.goal_kind = SimMoveConfig.GK_POINT
	mv.goal_tick = world.tick
	mv.air_mode = SimMoveConfig.AM_APPROACH
	if mv.mc == MapTerrain.MC_AIR_FIXED:
		var hd: int = (heading & 4095) if heading >= 0 else Fp.atan2(py - e.y, px - e.x)
		mv.land_heading = hd
		mv.goal_x = clampi(px - Fp.step_x(hd, APPROACH_DIST), 0, world.map.w * SimMoveConfig.CELL - 1)
		mv.goal_y = clampi(py - Fp.step_y(hd, APPROACH_DIST), 0, world.map.h * SimMoveConfig.CELL - 1)
		mv.alt_goal = APPROACH_ALT
	else:
		mv.land_heading = (heading & 4095) if heading >= 0 else -1
		mv.goal_x = px
		mv.goal_y = py
		mv.alt_goal = cruise_alt(mv)


# ---- flight step (stage 6, ascending id) ---------------------------------------------------------------------------------

static func step(world: SimWorld, e: SimEntity, mv: SimCompMove) -> void:
	var vmax: int = world.movement.speed_units(e) * 16
	var fixed: bool = mv.mc == MapTerrain.MC_AIR_FIXED
	var turn_radius: int = 0
	if fixed:
		turn_radius = ((vmax >> 4) * TURN_RADIUS_K) / maxi(1, mv.turn_rate)
	var mode: int = mv.air_mode
	if mode == SimMoveConfig.AM_TAKEOFF:
		_takeoff_step(world, e, mv, vmax, fixed)
		_finish(e, mv)
		return
	if mode == SimMoveConfig.AM_LANDING:
		_landing_step(world, e, mv)
		_finish(e, mv)
		return
	if mode == SimMoveConfig.AM_CRUISE:
		var rd: int = Fp.dist(mv.goal_x - e.x, mv.goal_y - e.y)
		if (fixed and rd <= turn_radius + ORBIT_SLACK) or (not fixed and rd <= ARRIVE_ROTOR):
			mv.air_phase |= AP_AT_GOAL
			mv.result = SimMoveConfig.RS_OK
			if fixed:
				mv.orbit_x = mv.goal_x
				mv.orbit_y = mv.goal_y
				mv.orbit_r = ORBIT_R_DEFAULT
				mv.air_mode = SimMoveConfig.AM_ORBIT
			else:
				mv.air_mode = SimMoveConfig.AM_HOVER
			mv.goal_kind = SimMoveConfig.GK_NONE
			mode = mv.air_mode
	var des: int = e.facing
	var tspd: int = 0
	match mode:
		SimMoveConfig.AM_CRUISE:
			des = Fp.atan2(mv.goal_y - e.y, mv.goal_x - e.x)
			tspd = vmax if fixed else _brake_speed(mv, vmax, Fp.dist(mv.goal_x - e.x, mv.goal_y - e.y), 128)
		SimMoveConfig.AM_ORBIT:
			des = _orbit_heading(e, mv, maxi(mv.orbit_r, turn_radius + ORBIT_SLACK) if fixed else mv.orbit_r)
			tspd = vmax if fixed else vmax / 2
		SimMoveConfig.AM_APPROACH:
			var final: bool = (mv.air_phase & AP_FINAL) != 0
			var tx: int = mv.land_x if final else mv.goal_x
			var ty: int = mv.land_y if final else mv.goal_y
			var rd2: int = Fp.dist(tx - e.x, ty - e.y)
			des = Fp.atan2(ty - e.y, tx - e.x)
			if not fixed:
				tspd = _brake_speed(mv, vmax, rd2, 128)
			elif final:  # glide slope: altitude and speed shrink with the distance to the touchdown point
				var slope: int = mini(256, rd2 * 256 / APPROACH_DIST)
				tspd = vmax * (TOUCH_PCT * 256 + (100 - TOUCH_PCT) * slope) / (100 * 256)
				mv.alt_goal = mini(APPROACH_ALT, APPROACH_ALT * rd2 / APPROACH_DIST)
			else:
				tspd = vmax
		_:  # AM_HOVER
			if mv.goal_kind == SimMoveConfig.GK_FACE:
				var err: int = SimSteering.angle_err(mv.goal_x, e.facing)
				e.facing = (e.facing + clampi(err, -mv.turn_rate, mv.turn_rate)) & 4095
	if fixed and (mode == SimMoveConfig.AM_CRUISE or mode == SimMoveConfig.AM_ORBIT):
		var mx: int = world.map.w * SimMoveConfig.CELL
		var my: int = world.map.h * SimMoveConfig.CELL
		if e.x < EDGE_MARGIN or e.y < EDGE_MARGIN or e.x > mx - EDGE_MARGIN or e.y > my - EDGE_MARGIN:
			des = Fp.atan2(my / 2 - e.y, mx / 2 - e.x)
	if mode != SimMoveConfig.AM_HOVER:
		_steer(e, mv, des, tspd, fixed, mode)
	else:
		mv.spd_q4 = SimSteering.speed_law(mv.spd_q4, 0, mv.accel_q4, mv.decel_q4)
	_integrate(world, e, mv)
	if mode == SimMoveConfig.AM_APPROACH:
		_approach_end(world, e, mv, fixed, turn_radius)
	_finish(e, mv)


## Turns toward `des` (turn_rate) and applies the speed law. Fixed-wing: TM_BANK (full speed while turning; airborne
## cruise and orbit never fall below FIXED_MIN_PCT of vmax). Rotor: speed shrinks with the remaining heading error.
static func _steer(e: SimEntity, mv: SimCompMove, des: int, tspd: int, fixed: bool, mode: int) -> void:
	var err: int = SimSteering.angle_err(des, e.facing)
	var rate: int = mv.turn_rate
	var dturn: int = clampi(err, -rate, rate)
	e.facing = (e.facing + dturn) & 4095
	var t: int = tspd
	if not fixed:
		t = (tspd * SimSteering.heading_factor(SimMoveConfig.TM_INSTANT, absi(err - dturn))) >> 8
	var spd: int = SimSteering.speed_law(mv.spd_q4, t, mv.accel_q4, mv.decel_q4)
	if fixed and (mode == SimMoveConfig.AM_CRUISE or mode == SimMoveConfig.AM_ORBIT) and tspd > 0:
		spd = maxi(spd, tspd * FIXED_MIN_PCT / 100)
	mv.spd_q4 = spd


static func _integrate(world: SimWorld, e: SimEntity, mv: SimCompMove) -> void:
	var spd: int = mv.spd_q4
	if spd != 0:
		world.set_pos(e, e.x + SimSteering.vel_x(spd, e.facing), e.y + SimSteering.vel_y(spd, e.facing))
		mv.vx = e.x - e.prev_x
		mv.vy = e.y - e.prev_y
	else:
		mv.vx = 0
		mv.vy = 0
	mv.alt += clampi(mv.alt_goal - mv.alt, -_descend(mv), _climb(mv))


static func _climb(mv: SimCompMove) -> int:
	return CLIMB_FIXED if mv.mc == MapTerrain.MC_AIR_FIXED else CLIMB_HOVER


static func _descend(mv: SimCompMove) -> int:
	return CLIMB_FIXED if mv.mc == MapTerrain.MC_AIR_FIXED else DESCEND_HOVER


## Fastest speed (Q4) from which the unit can still stop `slack` units short of the goal.
static func _brake_speed(mv: SimCompMove, vmax: int, rd: int, slack: int) -> int:
	return mini(vmax, Fp.isqrt(32 * mv.decel_q4 * maxi(0, rd - slack - (absi(mv.spd_q4) >> 4))))


## Heading that circles (orbit_x, orbit_y) at radius r in direction orbit_dir, steering back onto the circle.
static func _orbit_heading(e: SimEntity, mv: SimCompMove, r: int) -> int:
	var dx: int = e.x - mv.orbit_x
	var dy: int = e.y - mv.orbit_y
	var d: int = Fp.dist(dx, dy)
	var radial: int = Fp.atan2(dy, dx) if d > 0 else e.facing
	var corr: int = clampi(((d - r) * 512) / maxi(1, r), -512, 512)
	# outside the circle (corr > 0) the heading tilts past the tangent toward the centre
	return radial + mv.orbit_dir * (1024 + corr)


## Mirrors state / F_MOVING / F_AIRBORNE (bits 16-19 are the movement domain's).
static func _finish(e: SimEntity, mv: SimCompMove) -> void:
	mv.state = SimMoveConfig.MS_MOVING if mv.spd_q4 != 0 else SimMoveConfig.MS_IDLE
	var bits: int = 0
	if mv.spd_q4 != 0:
		bits |= SimFlags.F_MOVING
	if e.layer == SimEntity.Layer.AIR:
		bits |= SimFlags.F_AIRBORNE
	var f: int = (e.flags & ~SimMoveConfig.F_MIRROR_MASK) | bits
	if f != e.flags:
		e.flags = f


# ---- take-off -----------------------------------------------------------------------------------------------------------------

static func _takeoff_step(world: SimWorld, e: SimEntity, mv: SimCompMove, vmax: int, fixed: bool) -> void:
	var k: int = mv.g_t + 1
	mv.g_t = k
	if fixed:
		var fly: int = vmax * FIXED_MIN_PCT / 100
		mv.spd_q4 = mini(mv.spd_q4 + mv.accel_q4, fly)
		if mv.spd_q4 >= fly:
			mv.air_phase |= AP_ROLLED
		if mv.spd_q4 != 0:
			world.set_pos(e, e.x + SimSteering.vel_x(mv.spd_q4, e.facing), e.y + SimSteering.vel_y(mv.spd_q4, e.facing))
	if mv.g_n > 0:
		mv.alt = FLIP_ALT * mini(k, mv.g_n) / mv.g_n
	elif not fixed or (mv.air_phase & AP_ROLLED) != 0:
		mv.alt += _climb(mv)
	var done: bool = k >= mv.g_n if mv.g_n > 0 else mv.alt >= FLIP_ALT
	if not done:
		return
	mv.alt = maxi(mv.alt, FLIP_ALT)
	mv.alt_goal = cruise_alt(mv)
	world.set_layer(e, SimEntity.Layer.AIR)
	mv.g_t = 0
	mv.g_n = 0
	mv.air_phase = 0
	if fixed:
		mv.air_mode = SimMoveConfig.AM_ORBIT
		mv.goal_kind = SimMoveConfig.GK_NONE
	else:
		mv.air_mode = SimMoveConfig.AM_HOVER
	world.emit(EV_AIR_TAKEOFF, e.x, e.y, e.id)


# ---- landing --------------------------------------------------------------------------------------------------------------------

## End of an approach step: fixed-wing reaches the approach point -> steers at the pad; a rotor above the pad starts
## its descent. With a fixed final-descent length (`g_n` > 0) the rest is the scripted AM_LANDING glide onto the pad;
## fixed-wing without one touches down when it reaches the pad (_check_touchdown).
static func _approach_end(world: SimWorld, e: SimEntity, mv: SimCompMove, fixed: bool, turn_radius: int) -> void:
	var final: bool = (mv.air_phase & AP_FINAL) != 0
	if fixed and not final:
		if Fp.dist(mv.goal_x - e.x, mv.goal_y - e.y) <= turn_radius + ORBIT_SLACK:
			mv.air_phase |= AP_FINAL
			final = true
	elif not fixed and not final and Fp.dist(mv.land_x - e.x, mv.land_y - e.y) <= ARRIVE_ROTOR:
		mv.air_phase |= AP_FINAL
		final = true
		if mv.g_n == 0:
			mv.g_n = maxi(1, (mv.alt + DESCEND_HOVER - 1) / DESCEND_HOVER)
	if not final:
		return
	if mv.g_n == 0:
		if fixed:
			_check_touchdown(world, e, mv)
		return
	mv.air_mode = SimMoveConfig.AM_LANDING
	mv.g_t = 0
	mv.g_x0 = e.x
	mv.g_y0 = e.y
	mv.g_x1 = mv.alt
	mv.goal_kind = SimMoveConfig.GK_NONE


static func _landing_step(world: SimWorld, e: SimEntity, mv: SimCompMove) -> void:
	var k: int = mv.g_t + 1
	mv.g_t = k
	var n: int = maxi(1, mv.g_n)
	var nx: int = mv.land_x if k >= n else Fp.lerp_i(mv.g_x0, mv.land_x, k, n)
	var ny: int = mv.land_y if k >= n else Fp.lerp_i(mv.g_y0, mv.land_y, k, n)
	world.set_pos(e, nx, ny)
	mv.vx = e.x - e.prev_x
	mv.vy = e.y - e.prev_y
	mv.spd_q4 = (absi(mv.vx) + absi(mv.vy)) << 4
	mv.alt = mv.g_x1 - mv.g_x1 * mini(k, n) / n
	if k >= n:
		_touchdown(world, e, mv)


static func _check_touchdown(world: SimWorld, e: SimEntity, mv: SimCompMove) -> void:
	if Fp.dist(mv.land_x - e.x, mv.land_y - e.y) <= maxi(128, absi(mv.spd_q4) >> 4):
		_touchdown(world, e, mv)


static func _touchdown(world: SimWorld, e: SimEntity, mv: SimCompMove) -> void:
	world.set_pos(e, mv.land_x, mv.land_y)
	if mv.land_heading >= 0:
		e.facing = mv.land_heading & 4095
	mv.spd_q4 = 0
	mv.vx = 0
	mv.vy = 0
	mv.alt = 0
	mv.alt_goal = 0
	mv.g_t = 0
	mv.g_n = 0
	mv.goal_kind = SimMoveConfig.GK_NONE
	mv.air_mode = SimMoveConfig.AM_PARKED
	mv.air_phase = AP_AT_GOAL
	mv.result = SimMoveConfig.RS_OK
	world.set_layer(e, SimEntity.Layer.GROUND)
	world.emit(EV_AIR_LANDED, e.x, e.y, e.id)
