extends RefCounted
## SimMovement facade primitives and the movement determinism double run.

const K := preload("res://tests/support/sim_test_kit.gd")
const M := preload("res://tests/support/move_test_kit.gd")
const C := 1024


func test_glide(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var g: SimEntity = M.tank(w, 20, 30)
	var idle: SimEntity = M.tank(w, 22, 30)
	var ix: int = idle.x
	SimMovement.glide(w, g, 22 * C + 512, 30 * C + 512, 12)
	t.eq(SimMovement.state(g), SimMoveConfig.MS_GLIDE, "gliding")
	var start: int = w.tick
	var n: int = M.run_until(w, func() -> bool: return SimMovement.state(g) == SimMoveConfig.MS_ARRIVED, 30)
	t.eq(n, 12, "exactly 12 ticks")
	t.eq(w.tick - start, 12, "tick count")
	t.eq(g.x, 22 * C + 512, "exact end x")
	t.eq(g.y, 30 * C + 512, "exact end y")
	t.eq(SimMovement.result(g), SimMoveConfig.RS_OK, "RS_OK")
	# the idle unit in the glide path was not pushed by the gliding one
	t.eq(idle.x, ix, "a gliding unit does not push")
	# a glide is not pushed either
	var g2: SimEntity = M.tank(w, 30, 40)
	var mover: SimEntity = M.tank(w, 26, 40)
	SimMovement.glide(w, g2, 32 * C + 512, 40 * C + 512, 20)
	SimMovement.go_to(w, mover, 34 * C + 512, 40 * C + 512)
	var line: int = 0
	for i: int in 20:
		w.step()
		var expect_x: int = Fp.lerp_i(30 * C + 512, 32 * C + 512, i + 1, 20)
		if g2.x != expect_x:
			line += 1
	t.eq(line, 0, "glide follows the exact interpolation regardless of neighbours")
	t.eq(w.map.nav_version, 0, "nothing changed on the map")


func test_stop_and_turn(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var e: SimEntity = M.tank(w, 10, 30)
	SimMovement.go_to(w, e, 50 * C + 512, 30 * C + 512)
	w.run(30)
	t.check(SimMovement.is_moving(e), "moving")
	SimMovement.stop(w, e)
	t.eq(SimMovement.state(e), SimMoveConfig.MS_IDLE, "stop -> idle")
	t.check(e.move.spd_q4 > 0, "soft stop keeps the speed for a moment")
	w.run(6)
	t.eq(e.move.spd_q4, 0, "decelerated to a halt")
	t.check_false(SimMovement.is_moving(e), "no longer moving")
	# hard stop
	SimMovement.go_to(w, e, 50 * C + 512, 30 * C + 512)
	w.run(20)
	SimMovement.stop(w, e, true)
	t.eq(e.move.spd_q4, 0, "hard stop: speed 0 now")
	# turn in place
	SimMovement.turn_to(w, e, 2048)
	t.eq(SimMovement.state(e), SimMoveConfig.MS_FACING, "facing")
	var n: int = M.run_until(w, func() -> bool: return SimMovement.state(e) == SimMoveConfig.MS_IDLE, 80)
	t.check(n > 0, "turn completes")
	t.check(absi(SimSteering.angle_err(2048, e.facing)) < 64, "faces the target angle (%d)" % e.facing)
	t.check(n >= 1 and n <= 40, "took %d ticks at 85 apt/tick" % n)
	t.eq(SimMovement.result(e), SimMoveConfig.RS_OK, "RS_OK")


func test_pause_resume_and_near(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var e: SimEntity = M.tank(w, 10, 30)
	SimMovement.go_near(w, e, 50 * C + 512, 30 * C + 512, 4 * C)
	w.run(40)
	SimMovement.pause(w, e)
	t.eq(SimMovement.state(e), SimMoveConfig.MS_PAUSED, "paused")
	w.run(10)
	t.eq(e.move.spd_q4, 0, "decelerates to 0")
	var px: int = e.x
	w.run(10)
	t.eq(e.x, px, "holds while paused")
	SimMovement.resume(w, e)
	t.eq(SimMovement.state(e), SimMoveConfig.MS_MOVING, "resumed with the old goal and path")
	var n: int = M.run_until(w, func() -> bool: return SimMovement.at_goal(e), 600)
	t.check(n > 0, "arrives")
	var d: int = Fp.dist(50 * C + 512 - e.x, 30 * C + 512 - e.y)
	t.check(d <= 4 * C, "within the requested range (%d)" % d)
	t.check(d > 3 * C, "but not much closer (%d)" % d)


func test_approach_and_follow(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var e: SimEntity = M.tank(w, 10, 30)
	var target: SimEntity = M.rifle(w, 40, 30, 1)
	t.check(SimMovement.approach_entity(w, e, target.id, 3 * C), "approach accepted")
	var n: int = M.run_until(w, func() -> bool: return SimMovement.at_goal(e), 600)
	t.check(n > 0, "arrived")
	var d: int = Fp.dist(target.x - e.x, target.y - e.y) - target.radius
	t.check(d <= 3 * C, "within range of the target (%d)" % d)
	t.check_false(SimMovement.approach_entity(w, e, 99999, C), "unknown target refused")
	t.eq(SimMovement.result(e), SimMoveConfig.RS_BAD_TARGET, "RS_BAD_TARGET")
	# follow: the target walks away, the follower keeps up and never arrives
	var f: SimEntity = M.tank(w, 10, 40)
	var lead: SimEntity = M.rifle(w, 14, 40)
	SimMovement.follow(w, f, lead.id, C, 4 * C)
	SimMovement.go_to(w, lead, 50 * C + 512, 40 * C + 512)
	w.run(300)
	t.check(SimMovement.state(f) != SimMoveConfig.MS_ARRIVED, "follow never arrives")
	t.check(Fp.dist(lead.x - f.x, lead.y - f.y) <= 9 * C, "follower keeps up (%d)" % Fp.dist(lead.x - f.x, lead.y - f.y))
	# a dead target ends the follow with RS_BAD_TARGET
	w.kill(lead, SimWorld.Cause.SCRIPT)
	w.run(3)
	t.eq(SimMovement.result(f), SimMoveConfig.RS_BAD_TARGET, "target lost")


func test_sidestep_and_refusals(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var ally: SimEntity = M.rifle(w, 30, 30)
	var y0: int = ally.y
	SimMovement.sidestep(w, ally, 0, 0)
	t.eq(SimMovement.state(ally), SimMoveConfig.MS_SIDESTEP, "sidestepping")
	var n: int = M.run_until(w, func() -> bool: return SimMovement.state(ally) == SimMoveConfig.MS_IDLE, 100)
	t.check(n > 0, "returns to idle")
	t.check(absi(ally.y - y0) >= 2 * C, "moved 2-3 cells sideways (%d)" % (ally.y - y0))
	t.check(absi(ally.x - (30 * C + 512)) <= 600, "perpendicular to the requester's heading")
	var ally2: SimEntity = M.rifle(w, 40, 30)
	SimMovement.sidestep(w, ally2, 0, 0)
	var gy: int = ally2.move.goal_y
	SimMovement.sidestep(w, ally2, 1024, 0)  # within 20 ticks: refused
	t.eq(ally2.move.goal_y, gy, "one sidestep per 20 ticks")
	# structures and other non-movers have no move slot
	var hq: SimEntity = w.spawn_structure(w.data.structure_idx(DefTestKit.S_HQ), 0, 5 * C, 5 * C)
	t.check_false(SimMovement.go_to(w, hq, 10 * C, 10 * C), "no move slot: refused")
	t.check_false(SimMovement.is_moving(hq), "is_moving on a structure")
	# eta
	var e: SimEntity = M.tank(w, 10, 50)
	var eta: int = SimMovement.eta_ticks(w, e, 50 * C, 50 * C)
	t.check(eta > 350 and eta < 450, "eta %d ticks for 40 cells at 102 u/tick" % eta)


func _det_world() -> SimWorld:
	var m: MapData = M.clutter_map(96, 12, 3)
	var w: SimWorld = M.world(m, null, null, 4)
	var rng: SimRng = SimRng.new(99)
	var ids: PackedStringArray = [DefTestKit.U_RIFLEMAN, DefTestKit.U_TANK, DefTestKit.U_COLLECTOR, DefTestKit.U_MCV]
	var spawned: int = 0
	var guard: int = 0
	while spawned < 40 and guard < 4000:
		guard += 1
		var cx: int = 8 + rng.next_int(80)
		var cy: int = 8 + rng.next_int(80)
		var c: int = cy * 96 + cx
		if m.nav.clear_at(MapTerrain.NP_TRACKED, c) < 2:
			continue
		M.spawn(w, ids[spawned % 4], cx, cy, spawned % 4)
		spawned += 1
	return w


func _det_script(w: SimWorld, s: int) -> void:
	if s % 25 != 0:
		return
	var rng: SimRng = SimRng.new(1000 + s)
	for e: SimEntity in w.units:
		if e.move == null or rng.next_int(3) == 0:
			continue
		var cx: int = 6 + rng.next_int(84)
		var cy: int = 6 + rng.next_int(84)
		match rng.next_int(5):
			0:
				SimMovement.go_near(w, e, cx * C + 512, cy * C + 512, 3 * C)
			1:
				SimMovement.stop(w, e)
			2:
				SimMovement.turn_to(w, e, rng.next_int(4096))
			_:
				SimMovement.go_to(w, e, cx * C + 512, cy * C + 512)


func test_determinism_double_run(t: TestCtx) -> void:
	var r: Dictionary = K.double_run(_det_world, _det_script, 300)
	t.check(bool(r["ok"]), "two identical runs: chains, events, checksum and state dump agree")
	var w: SimWorld = _det_world()
	K.run_script(w, 300, _det_script)
	var moved: int = 0
	for e: SimEntity in w.units:
		if e.move != null and (e.x != e.prev_x or e.move.stuck_cnt > 0 or e.move.goal_kind != 0):
			moved += 1
	t.check(moved > 5, "the scenario exercises movement (%d active)" % moved)
	var buf: PackedInt32Array = PackedInt32Array()
	w.movement.hash_state(w, buf)
	t.check(buf.size() > 10, "movement hash part carries the path service state")


func test_lifecycle_hooks(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var a: SimEntity = M.tank(w, 10, 30)
	var b: SimEntity = M.tank(w, 10, 34)
	SimMovement.go_to(w, a, 50 * C, 30 * C)
	SimMovement.go_to(w, b, 50 * C, 34 * C)
	w.run(10)
	t.eq(w.movement.dump_state(w)["movers"], 2, "two movers registered")
	w.remove_entity(a.id, SimEvent.REM_SCRIPT)
	w.run(2)
	t.eq(w.movement.dump_state(w)["movers"], 1, "removed unit leaves the mover list")
	t.check(SimMovement.is_moving(b), "the other keeps moving")
	# a request pending for a unit that is removed is dropped
	var c: SimEntity = M.tank(w, 10, 40)
	SimMovement.go_to(w, c, 50 * C, 40 * C)
	t.eq(w.movement.path.pending(), 1, "queued")
	w.remove_entity(c.id, SimEvent.REM_SCRIPT)
	w.step()
	t.eq(w.movement.path.pending(), 0, "request dropped with the unit")
	# ownership change clears the goal
	w.change_owner(b.id, 1)
	t.eq(SimMovement.state(b), SimMoveConfig.MS_IDLE, "goal cleared on owner change")


func test_dirty_graph_defers_long_requests(t: TestCtx) -> void:
	var m: MapData = M.clutter_map(128, 20, 13)
	var d: GameData = M.data()
	m.set_footprint(SimEntity.Kind.STRUCTURE, d.structure_idx(DefTestKit.S_HQ), MapFootprint.new(3, 3))
	var w: SimWorld = M.world(m, d)
	var prs: PackedInt32Array = load("res://tests/fixtures/path_fixture.gd").pairs(m, MapTerrain.NP_FOOT, 1, 1, 80, 3)
	var e: SimEntity = M.rifle(w, prs[0] % 128, prs[0] / 128)
	# structure on an open patch near the start marks the graph dirty
	var sx: int = prs[0] % 128
	var sy: int = prs[0] / 128
	var placed: SimEntity = w.spawn_structure(d.structure_idx(DefTestKit.S_HQ), 1, (sx + 5) * C + 512, (sy + 5) * C + 512)
	t.check(placed != null and w.map.nav.pending_dirty() > 0, "graph dirty after the placement")
	SimMovement.go_to(w, e, (prs[1] % 128) * C + 512, (prs[1] / 128) * C + 512)
	var n: int = M.run_until(w, func() -> bool: return e.move.state == SimMoveConfig.MS_MOVING or e.move.state == SimMoveConfig.MS_NO_PATH, 12)
	t.check(n > 0 and n <= 6, "served within the wait bound (%d ticks)" % n)
	t.eq(SimMovement.state(e), SimMoveConfig.MS_MOVING, "and it found a path")


func test_find_free_cell_and_eject(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var origin: int = 30 * 64 + 30
	var seen: Dictionary = {}
	for i: int in 9:
		var c: int = SimMovement.find_free_cell_near(w, origin, SimEntity.Layer.GROUND, 4)
		t.check(c >= 0 and not seen.has(c), "free cell %d distinct" % i)
		seen[c] = true
		M.rifle(w, c % 64, c / 64)
	t.check(seen.has(origin), "the first answer is the cell itself (ring 0)")
	t.eq(SimMovement.find_free_cell_near(w, origin, SimEntity.Layer.GROUND, 0), -1, "ring 0 is taken now")
	# cells 4 rings around are all taken: -1
	for y: int in range(26, 35):
		for x: int in range(26, 35):
			if SimMovement.find_free_cell_near(w, y * 64 + x, SimEntity.Layer.GROUND, 0) >= 0:
				M.rifle(w, x, y)
	t.eq(SimMovement.find_free_cell_near(w, origin, SimEntity.Layer.GROUND, 4), -1, "no free cell within 4 rings")
	# a rect over units ejects those of the given team (pid 0 = team 1), others stay
	var w2: SimWorld = M.world(M.open_map(64))
	var mine: SimEntity = M.rifle(w2, 20, 20, 0)
	var mine2: SimEntity = M.tank(w2, 21, 21, 0)
	var foe: SimEntity = M.rifle(w2, 20, 21, 1)
	var fx: int = foe.x
	var fy: int = foe.y
	SimMovement.eject_units_from_rect(w2, 19, 19, 22, 22, w2.team_of(0))
	t.eq(foe.x, fx, "other team stays (x)")
	t.eq(foe.y, fy, "other team stays (y)")
	for e: SimEntity in [mine, mine2]:
		var inside: bool = e.x >= 19 * C and e.x < 23 * C and e.y >= 19 * C and e.y < 23 * C
		t.check_false(inside, "unit %d is outside the rectangle" % e.id)
	t.check(Fp.dist(mine.x - mine2.x, mine.y - mine2.y) >= C / 2, "ejected to distinct cells")
	t.eq(mine.move.spd_q4, 0, "speed 0")


func test_reverse_precise_and_speed_cap(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var e: SimEntity = M.tank(w, 30, 30)
	SimMovement.go_to(w, e, 27 * C + 512, 30 * C + 512, SimMoveConfig.OPT_REVERSE_OK)
	var neg: bool = false
	for i: int in 120:
		w.step()
		if e.move.spd_q4 < 0:
			neg = true
		if SimMovement.at_goal(e):
			break
	t.check(neg, "reverse used for a short move behind")
	t.eq(e.facing, 0, "facing unchanged while reversing")
	t.check(SimMovement.at_goal(e) and absi(e.x - (27 * C + 512)) <= 256, "arrived")
	# without the option the tank turns around instead
	var f: SimEntity = M.tank(w, 30, 40)
	SimMovement.go_to(w, f, 27 * C + 512, 40 * C + 512)
	w.run(15)
	t.check(f.move.spd_q4 >= 0 and f.facing != 0, "turns instead of reversing")
	# precise arrival snaps onto the goal
	var g: SimEntity = M.rifle(w, 30, 50)
	SimMovement.go_to(w, g, 36 * C + 300, 50 * C + 700, SimMoveConfig.OPT_PRECISE)
	M.run_until(w, func() -> bool: return SimMovement.at_goal(g), 300)
	t.eq(g.x, 36 * C + 300, "precise x")
	t.eq(g.y, 50 * C + 700, "precise y")
	# formation speed cap
	var h: SimEntity = M.tank(w, 30, 20)
	h.move.speed_cap_q4 = 800
	SimMovement.go_to(w, h, 60 * C + 512, 20 * C + 512)
	w.run(30)
	t.eq(h.move.spd_q4, 800, "speed cap limits the top speed")


func test_crowd_settles_at_one_point(t: TestCtx) -> void:
	# 30 mixed units ordered to the exact same point (no formation): all arrive, the pile settles, nobody coincides
	var w: SimWorld = M.world(M.open_map(96))
	var ents: Array[SimEntity] = []
	var ids: PackedStringArray = [DefTestKit.U_RIFLEMAN, DefTestKit.U_COLLECTOR, DefTestKit.U_TANK, DefTestKit.U_MCV]
	for i: int in 30:
		ents.append(M.spawn(w, ids[i % 4], 10 + (i % 6) * 2, 40 + (i / 6) * 2))
	for e: SimEntity in ents:
		SimMovement.go_to(w, e, 60 * C, 48 * C)
	var n: int = M.run_until(w, func() -> bool:
		for e: SimEntity in ents:
			if e.move.state != SimMoveConfig.MS_ARRIVED:
				return false
		return true, 1600)
	t.check(n > 0, "everyone arrived (%d ticks)" % n)
	w.run(300)
	var minr: float = 9.0
	var far: int = 0
	for i: int in ents.size():
		if Fp.dist(60 * C - ents[i].x, 48 * C - ents[i].y) > 14 * C:
			far += 1
		for j: int in range(i + 1, ents.size()):
			var d: float = Vector2(ents[i].x - ents[j].x, ents[i].y - ents[j].y).length()
			minr = minf(minr, d / float(ents[i].radius + ents[j].radius))
	t.eq(far, 0, "nobody was flung away from the destination")
	t.check(minr >= 0.7, "no pair on top of each other (min distance ratio %.2f)" % minr)
	var before: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in ents:
		before.append(e.x)
		before.append(e.y)
	w.run(200)
	var drift: int = 0
	for i: int in ents.size():
		drift += absi(ents[i].x - before[i * 2]) + absi(ents[i].y - before[i * 2 + 1])
	t.check(drift <= 2500, "the pile has settled (drift %d)" % drift)
