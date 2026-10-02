extends RefCounted
## terrain_movement scenario tests of TM-11 (10.2): S1 open field, S2 forest strip, S3 ford, S5 idle friends,
## S6 blocked lane, S7 building across the route, S8 amphibious, S9 ships, S15-S17 stat mods / immobile, S20 sub layer.

const M := preload("res://tests/support/move_test_kit.gd")
const C := 1024


func _state(e: SimEntity) -> int:
	return SimMovement.state(e)


func test_s1_open_field(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(80))
	var e: SimEntity = M.tank(w, 8, 40)
	var start_x: int = e.x
	var gx: int = start_x + 50 * C
	t.check(SimMovement.go_to(w, e, gx, e.y), "go_to accepted")
	var spd: PackedInt32Array = PackedInt32Array()
	var arrived: int = -1
	for i: int in 700:
		w.step()
		if i < 7:
			spd.append(e.move.spd_q4)
		if _state(e) == SimMoveConfig.MS_ARRIVED:
			arrived = i + 1
			break
	t.eq(spd, PackedInt32Array([272, 544, 816, 1088, 1360, 1632, 1632]), "speed ramp reaches 1632 at tick 6")
	t.note("S1 arrival tick %d" % arrived)
	t.check(arrived >= 495 and arrived <= 515, "arrival tick %d in 500-512 (+-)" % arrived)
	t.check(absi(e.x - gx) <= 256, "final distance %d" % absi(e.x - gx))
	t.eq(SimMovement.result(e), SimMoveConfig.RS_OK, "RS_OK")
	t.check(SimMovement.at_goal(e), "at_goal")
	t.eq(e.flags & SimFlags.F_MOVING, 0, "F_MOVING cleared")
	SimMovement.ack(w, e)
	t.eq(_state(e), SimMoveConfig.MS_IDLE, "ack -> idle")


## Ticks a unit needs to cross x in [x0, x1) cells at steady state: returns [tick_in, tick_out] or [-1, -1].
func _cross_ticks(w: SimWorld, e: SimEntity, x0: int, x1: int, max_ticks: int) -> PackedInt32Array:
	var tin: int = -1
	var tout: int = -1
	for i: int in max_ticks:
		w.step()
		if tin < 0 and e.x >= x0 * C:
			tin = i
		if tout < 0 and e.x >= x1 * C:
			tout = i
			break
	return PackedInt32Array([tin, tout])


func test_s2_forest_strip(t: TestCtx) -> void:
	var rows: PackedStringArray = M.grid(80)
	M.rect(rows, 20, 2, 29, 77, "F")
	var results: Dictionary = {}
	for kind: String in ["foot", "tracked"]:
		var w: SimWorld = M.world(M.map_from(rows))
		var e: SimEntity = M.rifle(w, 10, 40) if kind == "foot" else M.tank(w, 10, 40)
		SimMovement.go_to(w, e, 50 * C, 40 * C + 512)
		var r: PackedInt32Array = _cross_ticks(w, e, 20, 30, 900)
		t.check(r[0] >= 0 and r[1] > r[0], "%s crosses" % kind)
		var per_tick: float = 10.0 * C / float(r[1] - r[0])
		var free_run: float = 87.0 if kind == "foot" else 102.0
		results[kind] = per_tick / free_run
		t.note("S2 %s forest ratio %.3f" % [kind, results[kind]])
	t.check(absf(results["foot"] - 0.70) <= 0.05, "infantry at 70 %% (%.3f)" % results["foot"])
	t.check(absf(results["tracked"] - 0.55) <= 0.05, "tracked at 55 %% (%.3f)" % results["tracked"])
	# a wheeled scout cannot enter forest: no path, no alternative goal within 24 rings of a far goal
	var w2: SimWorld = M.world(M.map_from(rows))
	var sc: SimEntity = M.scout(w2, 10, 40)
	SimMovement.go_to(w2, sc, 70 * C, 40 * C + 512)
	M.run_until(w2, func() -> bool: return SimMovement.state(sc) == SimMoveConfig.MS_NO_PATH, SimMoveConfig.PATH_WAIT_MAX)
	t.eq(SimMovement.state(sc), SimMoveConfig.MS_NO_PATH, "scout: no path within PATH_WAIT_MAX")
	t.eq(SimMovement.result(sc), SimMoveConfig.RS_NO_PATH, "RS_NO_PATH")
	t.check(SimMovement.path_failed(sc), "path_failed")
	t.eq(w2.movement.path.pending(), 0, "request finished")


func test_s3_ford(t: TestCtx) -> void:
	var rows: PackedStringArray = M.grid(80)
	M.rect(rows, 30, 2, 39, 77, "~")
	M.rect(rows, 30, 40, 39, 44, "f")
	var expect: Dictionary = {"foot": 0.70, "tracked": 0.65, "wheeled": 0.50}
	for kind: String in ["foot", "tracked", "wheeled"]:
		var w: SimWorld = M.world(M.map_from(rows))
		var e: SimEntity = M.rifle(w, 20, 20) if kind == "foot" else (M.tank(w, 20, 20) if kind == "tracked" else M.scout(w, 20, 20))
		SimMovement.go_to(w, e, 55 * C, 20 * C + 512)
		var tin: int = -1
		var tout: int = -1
		var outside: int = 0
		for i: int in 1500:
			w.step()
			if e.x >= 30 * C and e.x < 40 * C:
				if e.y < 40 * C or e.y >= 45 * C:
					outside += 1
				if tin < 0:
					tin = i
			if tin >= 0 and tout < 0 and e.x >= 40 * C:
				tout = i
			if SimMovement.state(e) == SimMoveConfig.MS_ARRIVED:
				break
		t.check(tout > tin and tin >= 0, "%s crosses the river" % kind)
		t.eq(outside, 0, "%s crosses only over the ford" % kind)
		var free_run: float = 87.0 if kind == "foot" else 102.0
		var ratio: float = (10.0 * C / float(tout - tin)) / free_run
		t.note("S3 %s ford ratio %.3f" % [kind, ratio])
		t.check(absf(ratio - expect[kind]) <= 0.06, "%s at %.2f (got %.3f)" % [kind, expect[kind], ratio])
		t.check(SimMovement.at_goal(e), "%s arrived" % kind)


func test_s5_idle_friends_in_corridor(t: TestCtx) -> void:
	var rows: PackedStringArray = M.grid(64)
	for y: int in range(2, 62):
		M.rect(rows, 2, y, 61, y, "#")
	M.rect(rows, 2, 20, 61, 25, ".")  # 6-wide corridor
	var w: SimWorld = M.world(M.map_from(rows))
	var idle: Array[SimEntity] = []
	for i: int in 4:
		var it: SimEntity = M.tank(w, 20 + i * 5, 22)
		w.set_pos(it, it.x, it.y + (600 if (i & 1) == 0 else -700), true)  # off the mover's exact line
		idle.append(it)
	var start: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in idle:
		start.append(e.x)
		start.append(e.y)
	var mover: SimEntity = M.tank(w, 4, 22)
	SimMovement.go_to(w, mover, 58 * C, 22 * C + 512)
	var bad: Array[int] = [0]
	var n: int = M.run_until(w, func() -> bool:
		if w.map.nav.w_at(MapTerrain.NP_TRACKED, M.cell_of(w, mover)) == 0:
			bad[0] += 1
		return SimMovement.at_goal(mover), 900)
	t.check(n > 0, "mover reaches the far end")
	w.run(60)
	for i: int in idle.size():
		var d: int = Fp.dist(idle[i].x - start[i * 2], idle[i].y - start[i * 2 + 1])
		t.check(d <= 3 * C, "idle %d displaced %d units" % [i, d])
		t.check(w.map.nav.w_at(MapTerrain.NP_TRACKED, M.cell_of(w, idle[i])) != 0, "idle %d not in a wall cell" % i)
	t.eq(bad[0], 0, "mover never in a wall cell")


func test_s6_blocked_lane(t: TestCtx) -> void:
	var rows: PackedStringArray = M.grid(64)
	for y: int in range(2, 62):
		M.rect(rows, 2, y, 61, y, "#")
	M.rect(rows, 2, 30, 61, 30, ".")  # one lane
	var abil: M.AbilStub = M.AbilStub.new()
	var w: SimWorld = M.world(M.map_from(rows), null, abil)
	var wall: SimEntity = M.rifle(w, 30, 30, 1)
	abil.immobile_ids[wall.id] = true
	var e: SimEntity = M.rifle(w, 12, 30, 0)
	SimMovement.go_to(w, e, 50 * C, 30 * C + 512)
	var contact: int = -1
	var fail: int = -1
	for i: int in 400:
		w.step()
		if contact < 0 and wall.x - e.x <= 1000:
			contact = i
		if SimMovement.state(e) == SimMoveConfig.MS_NO_PATH:
			fail = i
			break
	t.check(contact > 0 and fail > 0, "contact %d fail %d" % [contact, fail])
	t.eq(SimMovement.result(e), SimMoveConfig.RS_STUCK, "RS_STUCK")
	t.note("S6 blocked %d ticks after contact" % (fail - contact))
	t.check(fail - contact >= 70 and fail - contact <= 100, "stuck failure %d ticks after contact (80 +- 10 +stride)" % (fail - contact))
	t.eq(wall.x, 30 * C + 512, "the immobile enemy was never pushed")
	t.check(w.map.nav.w_at(MapTerrain.NP_FOOT, M.cell_of(w, e)) != 0, "mover stays on its lane")


func test_s7_building_across_route(t: TestCtx) -> void:
	var m: MapData = M.open_map(80)
	var d: GameData = M.data()
	var hq: int = d.structure_idx(DefTestKit.S_HQ)
	m.set_footprint(SimEntity.Kind.STRUCTURE, hq, MapFootprint.new(3, 3))
	var w: SimWorld = M.world(m, d)
	var e: SimEntity = M.tank(w, 8, 40)
	SimMovement.go_to(w, e, 60 * C + 512, 40 * C + 512)
	w.run(120)
	t.check(e.x > 15 * C and e.x < 45 * C, "under way")
	var block: SimEntity = w.spawn_structure(hq, 0, 44 * C + 512, 40 * C + 512, 0, SimFlags.F_INITIAL)
	t.not_null(block, "structure placed")
	var in_wall: Array[int] = [0]
	var n: int = M.run_until(w, func() -> bool:
		if w.map.occupant_at(M.cell_of(w, e)) >= 0:
			in_wall[0] += 1
		return SimMovement.at_goal(e), 900)
	t.check(n > 0, "arrives after the detour")
	t.eq(in_wall[0], 0, "never inside a blocked cell")
	t.check(w.map.nav_version > 0, "the structure changed the nav version")
	t.check(absi(e.x - (60 * C + 512)) <= 256 and absi(e.y - (40 * C + 512)) <= 256, "at the goal")


func test_s8_amphibious_lake(t: TestCtx) -> void:
	var rows: PackedStringArray = M.grid(80)
	M.rect(rows, 30, 2, 49, 77, "~")
	var d: GameData = M.data()
	M.reclass(d, DefTestKit.U_TANK2, DefEnums.MoveClass.AMPHIBIOUS, 563, DefEnums.SizeClass.MEDIUM, 0)
	var w: SimWorld = M.world(M.map_from(rows), d)
	var e: SimEntity = M.spawn(w, DefTestKit.U_TANK2, 20, 40)
	SimMovement.go_to(w, e, 65 * C, 40 * C + 512)
	var tin: int = -1
	var tout: int = -1
	var wrong: int = 0
	var layer_bad: int = 0
	for i: int in 900:
		w.step()
		if e.layer != SimEntity.Layer.GROUND:
			layer_bad += 1
		var on: bool = SimMovement.is_on_water(e)
		if e.x >= 32 * C and e.x < 48 * C and not on:
			wrong += 1
		if (e.x < 28 * C or e.x >= 52 * C) and on:
			wrong += 1
		if tin < 0 and e.x >= 32 * C:
			tin = i
		if tin >= 0 and tout < 0 and e.x >= 48 * C:
			tout = i
		if SimMovement.at_goal(e):
			break
	t.check(SimMovement.at_goal(e), "arrived")
	t.eq(M.count_events(w, SimMoveConfig.EV_MEDIUM_CHANGED, 1), 1, "one entered-water event")
	t.eq(M.count_events(w, SimMoveConfig.EV_MEDIUM_CHANGED, 0), 1, "one left-water event")
	t.eq(wrong, 0, "F_ON_WATER only between the events")
	t.eq(layer_bad, 0, "layer stays GROUND")
	var kbp: int = w.map.tt.speed_bp(MapTerrain.MC_AMPHIBIOUS, MapTerrain.T_DEEP)
	var expect: float = 102.0 * kbp / 10000.0
	var got: float = 16.0 * C / float(tout - tin)
	t.note("S8 deep speed %.2f expected %.2f" % [got, expect])
	t.check(absf(got - expect) / expect <= 0.05, "cells/tick on deep water within 5 %%: %.2f vs %.2f" % [got, expect])


func _ship_run(rows: PackedStringArray, radius: int, size_class: int) -> Dictionary:
	var d: GameData = M.data()
	M.reclass(d, DefTestKit.U_TANK2, DefEnums.MoveClass.NAVAL, radius, size_class, SimEntity.Layer.SURFACE)
	var w: SimWorld = M.world(M.map_from(rows), d)
	var e: SimEntity = M.spawn(w, DefTestKit.U_TANK2, 10, 32)
	SimMovement.go_to(w, e, 52 * C + 512, 32 * C + 512)
	var land: int = 0
	for i: int in 1200:
		w.step()
		var k: int = w.map.kind_at(M.cell_of(w, e))
		if k != MapTerrain.TK_DEEP and k != MapTerrain.TK_SHALLOW:
			land += 1
		var st: int = SimMovement.state(e)
		if st == SimMoveConfig.MS_ARRIVED or st == SimMoveConfig.MS_NO_PATH:
			break
	return {"state": SimMovement.state(e), "result": SimMovement.result(e), "land": land, "x": e.x, "layer": e.layer}


func test_s9_ships(t: TestCtx) -> void:
	var small: Dictionary = _ship_run(M.sea_map(2), 614, DefEnums.SizeClass.SHIP_SMALL)
	t.eq(small.state, SimMoveConfig.MS_NO_PATH, "size-2 hull cannot use a 2-wide channel")
	t.eq(small.result, SimMoveConfig.RS_NO_PATH, "RS_NO_PATH")
	var ok3: Dictionary = _ship_run(M.sea_map(3), 614, DefEnums.SizeClass.SHIP_SMALL)
	t.eq(ok3.state, SimMoveConfig.MS_ARRIVED, "size-2 hull passes a 3-wide channel")
	t.eq(ok3.land, 0, "no ship position on land")
	t.eq(ok3.layer, SimEntity.Layer.SURFACE, "naval layer SURFACE")
	var big3: Dictionary = _ship_run(M.sea_map(3), 1434, DefEnums.SizeClass.SHIP_LARGE)
	t.eq(big3.state, SimMoveConfig.MS_NO_PATH, "size-3 hull needs 5-wide deep water")
	var big5: Dictionary = _ship_run(M.sea_map(5), 1434, DefEnums.SizeClass.SHIP_LARGE)
	t.eq(big5.state, SimMoveConfig.MS_ARRIVED, "size-3 hull passes 5 wide")
	t.eq(big5.land, 0, "large hull stays on water")
	var moat: Dictionary = _ship_run(M.sea_map(7), 614, DefEnums.SizeClass.SHIP_SMALL)
	t.eq(moat.state, SimMoveConfig.MS_ARRIVED, "7-wide moat passes")
	# fords: a small hull may sail over shallow, a deep-only hull (radius >= 922) may not
	var ford_small: Dictionary = _ship_run(M.sea_map(7, "f"), 614, DefEnums.SizeClass.SHIP_SMALL)
	t.eq(ford_small.state, SimMoveConfig.MS_ARRIVED, "small hull over a ford")
	var ford_deep: Dictionary = _ship_run(M.sea_map(7, "f"), 1000, DefEnums.SizeClass.SHIP_MEDIUM)
	t.eq(ford_deep.state, SimMoveConfig.MS_NO_PATH, "deep-only hull never routes over a ford")


## Distance travelled between ticks a and b of a straight run.
func _run_distance(d_mult: int, kind: String, a: int, b: int, w_out: Array[SimWorld]) -> int:
	var abil: M.AbilStub = M.AbilStub.new()
	var w: SimWorld = M.world(M.open_map(96), null, abil)
	w_out.append(w)
	var e: SimEntity = M.tank(w, 8, 40) if kind == "tank" else M.rifle(w, 8, 40)
	abil.mult_for_def[e.def_idx] = d_mult
	SimMovement.go_to(w, e, 85 * C, 40 * C + 512)
	var xa: int = 0
	for i: int in b:
		w.step()
		if i + 1 == a:
			xa = e.x
	return e.x - xa


func test_s15_s16_stat_mods(t: TestCtx) -> void:
	var ws: Array[SimWorld] = []
	var base: int = _run_distance(10000, "tank", 20, 100, ws)
	var slow: int = _run_distance(6500, "tank", 20, 100, ws)
	var fast: int = _run_distance(12500, "tank", 20, 100, ws)
	t.note("S15/S16 distances %d %d %d" % [base, slow, fast])
	t.check(absf(float(slow) / base - 0.65) <= 0.02, "S15 slow tracked at 65 %%: %.3f" % (float(slow) / base))
	t.check(absf(float(fast) / base - 1.25) <= 0.01, "S16 Open Corridor 1.25x: %.3f" % (float(fast) / base))
	t.eq(ws[1].movement.path.stat_searches, 1, "no repath from a stat mod")
	t.eq(ws[1].map.nav_version, 0, "nav_version untouched")
	# infantry are not affected by a mod that names the tank only
	var abil: M.AbilStub = M.AbilStub.new()
	var w: SimWorld = M.world(M.open_map(96), null, abil)
	var tk: SimEntity = M.tank(w, 8, 40)
	var rf: SimEntity = M.rifle(w, 8, 44)
	abil.mult_for_def[tk.def_idx] = 6500
	SimMovement.go_to(w, tk, 85 * C, 40 * C + 512)
	SimMovement.go_to(w, rf, 85 * C, 44 * C + 512)
	w.run(50)
	t.eq(rf.move.vcur_q4, 87 * 16, "infantry unaffected")
	t.eq(tk.move.vcur_q4, (102 * 65 + 50) / 100 * 16, "tank slowed to 65 %")
	# removal restores the speed within a few ticks
	abil.mult_for_def.erase(tk.def_idx)
	w.run(10)
	t.eq(tk.move.spd_q4, 1632, "speed restored after the mod ends")


func test_s17_immobile_and_turn_lock(t: TestCtx) -> void:
	var abil: M.AbilStub = M.AbilStub.new()
	var w: SimWorld = M.world(M.open_map(64), null, abil)
	var e: SimEntity = M.tank(w, 20, 30)
	abil.immobile = true
	t.check_false(SimMovement.go_to(w, e, 40 * C, 30 * C), "deployed unit refuses the goal")
	t.eq(SimMovement.result(e), SimMoveConfig.RS_IMMOBILE, "RS_IMMOBILE")
	t.eq(abil.pack_calls, 1, "request_pack asked once")
	w.run(5)
	SimMovement.go_to(w, e, 40 * C, 30 * C)
	t.eq(abil.pack_calls, 1, "rate limited to once per 20 ticks")
	w.run(20)
	SimMovement.go_to(w, e, 40 * C, 30 * C)
	t.eq(abil.pack_calls, 2, "asked again after 20 ticks")
	t.eq(SimMovement.state(e), SimMoveConfig.MS_IDLE, "state untouched")
	abil.immobile = false
	t.check(SimMovement.go_to(w, e, 40 * C, 30 * C), "accepted once unpacked")
	w.run(30)
	t.check(e.x > 20 * C + 512 + C, "moves after unpacking")
	# turn lock: the unit does not rotate
	abil.locked = true
	var f: SimEntity = M.tank(w, 20, 40)
	var face0: int = f.facing
	SimMovement.go_to(w, f, 10 * C, 40 * C)  # behind it
	w.run(30)
	t.eq(f.facing, face0, "a turn-locked unit does not rotate")


func test_s20_submarine_surfacing(t: TestCtx) -> void:
	var rows: PackedStringArray = M.grid(64)
	M.rect(rows, 4, 4, 59, 59, "~")
	var d: GameData = M.data()
	M.reclass(d, DefTestKit.U_TANK2, DefEnums.MoveClass.SUBMERGED, 614, DefEnums.SizeClass.SHIP_SMALL, SimEntity.Layer.UNDERWATER)
	var w: SimWorld = M.world(M.map_from(rows), d)
	var e: SimEntity = M.spawn(w, DefTestKit.U_TANK2, 20, 30)
	t.eq(e.layer, SimEntity.Layer.UNDERWATER, "starts underwater")
	t.eq(e.move.hl, SimMoveConfig.HL_SUB, "hash layer SUB")
	SimMovement.request_layer(w, e, SimEntity.Layer.SURFACE, 40)
	w.run(39)
	t.eq(e.layer, SimEntity.Layer.UNDERWATER, "still submerged at tick 39")
	w.step()
	t.eq(e.layer, SimEntity.Layer.SURFACE, "surfaced at tick 40")
	t.eq(e.move.hl, SimMoveConfig.HL_WATER, "hash layer WATER")
	t.eq(M.count_events(w, SimMoveConfig.EV_LAYER_CHANGED, SimEntity.Layer.SURFACE), 1, "one layer event")
	w.run(20)
	t.eq(M.count_events(w, SimMoveConfig.EV_LAYER_CHANGED), 1, "and only one")
