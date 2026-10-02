extends RefCounted
## terrain_movement TM-16 (reduced): determinism double-run of the order layer end to end. Group MOVE / PATROL /
## SCATTER / STOP / FOLLOW commands, aircraft take-off / cruise / orbit / landing, eject with eviction, scripted
## glides. Also the scenario builder of tests/scenarios/xplat_move_orders.gd (cross-platform hash chain).

const M := preload("res://tests/support/move_test_kit.gd")
const K := preload("res://tests/support/sim_test_kit.gd")
const C: int = 1024
const STEPS: int = 450


static func build() -> SimWorld:
	var d: GameData = M.data()
	var f: int = M.reclass(d, DefTestKit.U_TANK2, MapTerrain.MC_AIR_FIXED, 500, DefEnums.SizeClass.AIR_MEDIUM, DefEnums.Layer.AIR, 300)
	d.units[f].turn_rate = 100
	var h: int = M.reclass(d, DefTestKit.U_ENGINEER, MapTerrain.MC_AIR_HOVER, 500, DefEnums.SizeClass.AIR_LARGE, DefEnums.Layer.AIR, 200)
	d.units[h].turn_rate = 120
	var w: SimWorld = M.world(M.clutter_map(96, 8, 5), d)
	var kinds: PackedStringArray = [DefTestKit.U_RIFLEMAN, DefTestKit.U_TANK, DefTestKit.U_MCV, DefTestKit.U_RIFLEMAN]
	for i: int in 24:
		M.spawn(w, kinds[i % 4], 10 + (i % 6), 10 + (i / 6), 0)
	for i: int in 8:
		M.spawn(w, kinds[i % 4], 70 + (i % 4), 70 + (i / 4), 1)
	for i: int in 3:
		var a: SimEntity = M.spawn(w, DefTestKit.U_TANK2, 40 + i, 10, 0)
		w.set_layer(a, SimEntity.Layer.GROUND)  # parked on the apron
		var b: SimEntity = M.spawn(w, DefTestKit.U_ENGINEER, 40 + i, 14, 0)
		w.set_layer(b, SimEntity.Layer.GROUND)
	return w


static func on_step(w: SimWorld, s: int) -> void:
	var mine: PackedInt32Array = PackedInt32Array()
	var ground: PackedInt32Array = PackedInt32Array()
	var air: Array[SimEntity] = []
	for e: SimEntity in w.units_of(0):
		if e.move == null:
			continue
		mine.append(e.id)
		if e.move.mc >= MapTerrain.MC_AIR_FIXED:
			air.append(e)
		else:
			ground.append(e.id)
	match s:
		2:
			w.submit_raw(0, SimCmd.move(ground, 48 * C, 40 * C))
			for a: SimEntity in air:
				SimMovement.air_takeoff(w, a, 20 if (a.id & 1) == 0 else 0)
		6:
			w.submit_raw(0, SimCmd.patrol(PackedInt32Array([ground[0], ground[3]]), 30 * C, 12 * C))
			w.submit_raw(0, SimCmd.patrol(PackedInt32Array([ground[0], ground[3]]), 30 * C, 24 * C, SimOrder.QM_APPEND))
			w.submit_raw(1, SimCmd.move(PackedInt32Array([w.units_of(1)[0].id, w.units_of(1)[1].id]), 20 * C, 20 * C, 0, 2))
		60:
			w.submit_raw(0, SimCmd.scatter(PackedInt32Array([ground[4], ground[5], ground[6]])))
			w.submit_raw(0, SimCmd.follow(PackedInt32Array([ground[8], ground[9]]), ground[7]))
			for a: SimEntity in air:
				SimMovement.air_fly_to(w, a, (20 + (a.id & 7) * 6) * C, 60 * C)
		100:
			w.submit_raw(0, SimCmd.move(PackedInt32Array([ground[10], ground[11], ground[12], ground[13]]), 60 * C, 30 * C, 0, 1))
			w.submit_raw(0, SimCmd.stop(PackedInt32Array([ground[4]])))
			for a: SimEntity in air:
				if (a.id & 1) == 0:
					SimMovement.air_orbit(w, a, 50 * C, 50 * C, 5000, 1)
		150:
			SimMovement.eject_units_from_rect(w, 9, 9, 13, 11, w.team_of(0))
			for a: SimEntity in air:
				if (a.id & 1) == 1:
					SimMovement.air_land_at(w, a, (30 + (a.id & 3)) * C, 42 * C, -1, 25)
		200:
			w.submit_raw(0, SimCmd.move(PackedInt32Array([ground[14], ground[15], ground[16]]), 25 * C, 65 * C, SimOrder.QM_APPEND))
			var g: SimEntity = w.get_entity(ground[17])
			if g != null:
				SimMovement.glide(w, g, g.x + 3 * C, g.y, 12)
		260:
			w.submit_raw(0, SimCmd.move(ground, 15 * C, 15 * C))
			for a: SimEntity in air:
				SimMovement.air_hover(w, a)


func test_double_run(t: TestCtx) -> void:
	var r: Dictionary = K.double_run(build, on_step, STEPS)
	t.check(r["ok"], "two runs: identical hash chain, events, final checksum and dump")
	t.check((r["chain"] as PackedInt64Array).size() >= 40, "checkpoints recorded")
	var w: SimWorld = build.call()
	K.run_script(w, STEPS, on_step)
	var landed: int = M.count_events(w, SimAirMove.EV_AIR_LANDED)
	var lifted: int = M.count_events(w, SimAirMove.EV_AIR_TAKEOFF)
	t.note("takeoffs %d landings %d events %d" % [lifted, landed, w.events.count()])
	t.eq(lifted, 6, "every parked fixed-wing / rotor took off once")
	t.check(landed >= 1, "at least one landing")


func test_snapshot_replay_equal(t: TestCtx) -> void:
	# a different construction order of the same match (spawn order is fixed by ids) still gives one chain
	var a: SimWorld = build.call()
	var b: SimWorld = build.call()
	K.run_script(a, 200, on_step)
	K.run_script(b, 100, on_step)
	for s: int in range(100, 200):
		on_step(b, s)
		b.step()
	t.eq(a.checksum(), b.checksum(), "stepping in two chunks changes nothing")
