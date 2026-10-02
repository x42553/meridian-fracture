extends RefCounted
## terrain_movement TM-13 (10.2 S10): flight primitives of SimAirMove through the SimMovement.air_* facade, and the
## air orders (T_LAND, plus T_MOVE / STOP on an aircraft).

const M := preload("res://tests/support/move_test_kit.gd")
const C := 1024
const VMAX: int = 460  ## units per tick (9 cells/s at 20 ticks/s)


## World with one fixed-wing type (the tank def) and one rotor type (the MCV def). Aircraft spawn in the air (home layer).
func _world(size: int = 160) -> SimWorld:
	var d: GameData = M.data()
	var f: int = M.reclass(d, DefTestKit.U_TANK, MapTerrain.MC_AIR_FIXED, 500, DefEnums.SizeClass.AIR_MEDIUM, DefEnums.Layer.AIR, VMAX)
	d.units[f].turn_rate = 102
	d.units[f].accel_t = 12
	var h: int = M.reclass(d, DefTestKit.U_MCV, MapTerrain.MC_AIR_HOVER, 600, DefEnums.SizeClass.AIR_LARGE, DefEnums.Layer.AIR, 240)
	d.units[h].turn_rate = 120
	d.units[h].accel_t = 10
	return M.world(M.open_map(size), d)


func _fighter(w: SimWorld, cx: int, cy: int, grounded: bool = false) -> SimEntity:
	var e: SimEntity = M.tank(w, cx, cy)
	if grounded:
		w.set_layer(e, SimEntity.Layer.GROUND)
	return e


func _rotor(w: SimWorld, cx: int, cy: int, grounded: bool = false) -> SimEntity:
	var e: SimEntity = M.spawn(w, DefTestKit.U_MCV, cx, cy)
	if grounded:
		w.set_layer(e, SimEntity.Layer.GROUND)
	return e


func test_s10_fixed_wing_cruise_and_pattern(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var f: SimEntity = _fighter(w, 10, 80)
	t.eq(f.layer, SimEntity.Layer.AIR, "spawns airborne (home layer)")
	SimMovement.air_fly_to(w, f, 110 * C, 80 * C)
	var minspd: int = 1 << 30
	var latched: int = -1
	for i: int in 400:
		w.step()
		minspd = mini(minspd, f.move.spd_q4)
		if latched < 0 and SimMovement.air_at_goal(f):
			latched = i
	t.check(minspd >= VMAX * 16 * 60 / 100, "never below 60 %% speed (min %d)" % minspd)
	t.check(latched > 0 and latched < 260, "arrival latched (tick %d)" % latched)
	# holding pattern of radius 4096 around the point
	var lo: int = 1 << 30
	var hi: int = 0
	for i: int in 200:
		w.step()
		var d: int = Fp.dist(f.x - 110 * C, f.y - 80 * C)
		lo = mini(lo, d)
		hi = maxi(hi, d)
	t.check(SimMovement.air_at_goal(f), "at_goal stays latched")
	t.check(lo >= 4096 - 512 and hi <= 4096 + 512, "pattern radius 4096 +- 512 (%d..%d)" % [lo, hi])
	t.check((f.flags & SimFlags.F_AIRBORNE) != 0 and (f.flags & SimFlags.F_MOVING) != 0, "F_AIRBORNE / F_MOVING mirrors")
	t.eq(SimMovement.altitude(f), SimAirMove.ALT_FIXED, "cruise altitude reached")


func test_s10_orbit_and_hover_of_fixed_wing(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var f: SimEntity = _fighter(w, 60, 80)
	SimMovement.air_orbit(w, f, 60 * C, 90 * C, 5000, -1)
	w.run(200)
	var lo: int = 1 << 30
	var hi: int = 0
	for i: int in 200:
		w.step()
		var d: int = Fp.dist(f.x - 60 * C, f.y - 90 * C)
		lo = mini(lo, d)
		hi = maxi(hi, d)
	t.check(lo >= 5000 - 600 and hi <= 5000 + 600, "orbit radius 5000 (%d..%d)" % [lo, hi])
	SimMovement.air_hover(w, f)
	t.eq(f.move.air_mode, SimMoveConfig.AM_ORBIT, "a fixed-wing cannot hover: it circles")
	t.eq(f.move.orbit_r, SimAirMove.ORBIT_R_DEFAULT, "default radius")


func test_s10_takeoff_exact_tick(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var f: SimEntity = _fighter(w, 30, 80, true)
	t.eq(f.move.air_mode, SimMoveConfig.AM_PARKED, "parked")
	var x0: int = f.x
	w.run(30)
	t.eq(f.x, x0, "a parked aircraft does not move")
	t.eq(w.movement._air.size(), 0, "and costs nothing (not in the flight list)")
	SimMovement.air_takeoff(w, f, 20)
	for i: int in 19:
		w.step()
	t.eq(f.layer, SimEntity.Layer.GROUND, "still on the ground after 19 steps")
	w.step()
	t.eq(f.layer, SimEntity.Layer.AIR, "layer flips at exactly tick 20")
	t.eq(M.count_events(w, SimAirMove.EV_AIR_TAKEOFF), 1, "one takeoff event")
	t.check((f.flags & SimFlags.F_AIRBORNE) != 0, "F_AIRBORNE")
	w.run(80)
	t.eq(f.move.air_mode, SimMoveConfig.AM_ORBIT, "holds a pattern at the take-off point")
	t.check(f.move.spd_q4 >= VMAX * 16 * 60 / 100, "flying speed kept")
	t.eq(M.count_events(w, SimAirMove.EV_AIR_TAKEOFF), 1, "still one event")
	# default take-off (no fixed duration) and a rotor
	var g: SimEntity = _fighter(w, 40, 100, true)
	SimMovement.air_takeoff(w, g)
	var n: int = M.run_until(w, func() -> bool: return g.layer == SimEntity.Layer.AIR, 80)
	t.check(n > 4 and n < 40, "roll then climb: airborne after %d ticks" % n)
	var r: SimEntity = _rotor(w, 50, 100, true)
	SimMovement.air_takeoff(w, r)
	n = M.run_until(w, func() -> bool: return r.layer == SimEntity.Layer.AIR, 40)
	t.check(n >= 5 and n <= 7, "rotor climbs vertically 96 per tick: %d ticks" % n)
	t.eq(r.move.air_mode, SimMoveConfig.AM_HOVER, "and hovers")


func test_s10_landing_exact_tick(t: TestCtx) -> void:
	for kind: String in ["fixed", "rotor"]:
		var w: SimWorld = _world()
		var f: SimEntity = _fighter(w, 20, 80) if kind == "fixed" else _rotor(w, 20, 80)
		var px: int = 60 * C + 300
		var py: int = 84 * C
		SimMovement.air_land_at(w, f, px, py, -1, 30)
		var start: int = -1
		for i: int in 600:
			w.step()
			if start < 0 and f.move.air_mode == SimMoveConfig.AM_LANDING:
				start = i
				break
		t.check(start > 0, "%s: the final descent starts (step %d)" % [kind, start])
		for i: int in 29:
			w.step()
		t.eq(f.layer, SimEntity.Layer.AIR, "%s: still airborne 29 steps into the descent" % kind)
		t.check(not SimMovement.air_at_goal(f), "%s: not at goal yet" % kind)
		w.step()
		t.eq(f.layer, SimEntity.Layer.GROUND, "%s: touches down exactly 30 ticks after the descent started" % kind)
		t.eq([f.x, f.y], [px, py], "%s: snapped to the pad" % kind)
		t.check(SimMovement.air_at_goal(f), "%s: at_goal" % kind)
		t.eq(f.move.air_mode, SimMoveConfig.AM_PARKED, "%s: parked" % kind)
		t.eq(M.count_events(w, SimAirMove.EV_AIR_LANDED), 1, "%s: one landed event" % kind)
		t.eq(f.flags & SimFlags.F_AIRBORNE, 0, "%s: F_AIRBORNE cleared" % kind)
		t.eq(f.move.spd_q4, 0, "%s: speed 0" % kind)


func test_s10_landing_without_fixed_duration(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var f: SimEntity = _fighter(w, 20, 80)
	var px: int = 70 * C
	var py: int = 80 * C
	SimMovement.air_land_at(w, f, px, py, 0, 0)
	var n: int = M.run_until(w, func() -> bool: return f.move.air_mode == SimMoveConfig.AM_PARKED, 900)
	t.check(n > 0, "a straight-in landing finishes by itself (%d ticks)" % n)
	t.eq([f.x, f.y], [px, py], "at the pad")
	t.eq(f.facing, 0, "facing = the approach heading")
	t.eq(f.layer, SimEntity.Layer.GROUND, "on the ground")


func test_s10_rotor_hover_and_face(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var r: SimEntity = _rotor(w, 20, 80)
	SimMovement.air_fly_to(w, r, 60 * C, 80 * C)
	w.run(60)
	t.check(r.move.spd_q4 > 0 and not SimMovement.air_at_goal(r), "flying")
	var spd: int = r.move.spd_q4
	var x0: int = r.x
	SimMovement.air_hover(w, r)
	var n: int = M.run_until(w, func() -> bool: return r.move.spd_q4 == 0, 40)
	t.check(n > 0, "stops (%d ticks)" % n)
	var brake: int = r.x - x0
	var bound: int = (spd >> 4) * (n + 1) / 2 + 60
	t.check(brake >= 0 and brake <= bound, "within braking distance (%d <= %d)" % [brake, bound])
	var hx: int = r.x
	w.run(20)
	t.eq(r.x, hx, "position held")
	# yaw in place at turn_rate
	var f0: int = r.facing
	SimMovement.air_face(w, r, 2000)
	w.step()
	t.eq(absi(SimSteering.angle_err(r.facing, f0)), 120, "yaws at turn_rate per tick")
	var steps: int = M.run_until(w, func() -> bool: return absi(SimSteering.angle_err(2000, r.facing)) < 64, 60)
	t.check(steps > 0, "reaches the heading")
	t.eq(r.x, hx, "without moving")
	# arrival latches at_goal and hovers
	var r2: SimEntity = _rotor(w, 20, 100)
	SimMovement.air_fly_to(w, r2, 40 * C, 100 * C)
	M.run_until(w, func() -> bool: return SimMovement.air_at_goal(r2), 400)
	t.check(SimMovement.air_at_goal(r2), "rotor arrival latched")
	w.run(30)
	t.eq(r2.move.air_mode, SimMoveConfig.AM_HOVER, "hovering at the goal")
	t.eq(r2.move.spd_q4, 0, "at rest")
	t.check(Fp.dist(r2.x - 40 * C, r2.y - 100 * C) <= 400, "over the goal")


func test_air_orders(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var f: SimEntity = _fighter(w, 20, 80)
	# MOVE on an airborne aircraft: fly there, DONE when latched
	w.submit_raw(0, SimCmd.move(PackedInt32Array([f.id]), 60 * C, 80 * C))
	var n: int = M.run_until(w, func() -> bool: return f.orders.is_empty(), 300)
	t.check(n > 0 and SimMovement.air_at_goal(f), "T_MOVE on an aircraft ends at the latch (%d)" % n)
	# STOP on a cruising fixed-wing: it circles
	w.submit_raw(0, SimCmd.move(PackedInt32Array([f.id]), 20 * C, 120 * C))
	w.run(5)
	w.submit_raw(0, SimCmd.stop(PackedInt32Array([f.id])))
	w.run(3)
	t.eq(f.move.air_mode, SimMoveConfig.AM_ORBIT, "STOP: a fixed-wing holds a pattern")
	# T_LAND
	w.orders.issue(w, f, SimOrder.make(SimOrder.T_LAND, 0, 50 * C, 100 * C, -1), SimOrder.QM_REPLACE)
	n = M.run_until(w, func() -> bool: return f.orders.is_empty(), 900)
	t.check(n > 0 and f.layer == SimEntity.Layer.GROUND and f.move.air_mode == SimMoveConfig.AM_PARKED, "T_LAND lands the aircraft (%d)" % n)
	t.eq([f.x, f.y], [50 * C, 100 * C], "on the pad")
	# a grounded aircraft cannot be told to land or fly
	w.orders.issue(w, f, SimOrder.make(SimOrder.T_LAND, 0, 60 * C, 100 * C, -1), SimOrder.QM_REPLACE)
	w.run(3)
	t.check(f.orders.is_empty(), "T_LAND on a parked aircraft fails")
	t.eq(M.count_events(w, SimEvent.ORDER_FAILED), 1, "ORDER_FAILED once")
	# ground units refuse air orders
	var tank: SimEntity = M.spawn(w, DefTestKit.U_RIFLEMAN, 20, 20)
	t.eq(w.orders.issue(w, tank, SimOrder.make(SimOrder.T_LAND, 0, 60 * C, 100 * C, -1), SimOrder.QM_REPLACE), SimCommand.Err.NOT_ALLOWED, "T_LAND refused for ground units")


func test_air_edge_and_dead(t: TestCtx) -> void:
	var w: SimWorld = _world(96)
	var f: SimEntity = _fighter(w, 90, 48)
	SimMovement.air_fly_to(w, f, 95 * C + 900, 48 * C)  # a goal in the edge zone
	w.run(400)
	t.check(f.x >= 0 and f.x <= 96 * C - 1 and f.y >= 0 and f.y <= 96 * C - 1, "stays on the map")
	w.kill(f, SimWorld.Cause.SCRIPT, 0, 0)
	w.run(2)  # the mover loop skips dead aircraft: no error, no motion after death
	t.check((f.flags & SimFlags.F_GONE) != 0 or f.hp == 0, "dead")
