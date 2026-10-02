extends RefCounted
## SimPathService (TM-10): request / deliver, cache and group attach, alternative goal, cancel, budget accounting.

const M := preload("res://tests/support/move_test_kit.gd")
const Pf := preload("res://tests/fixtures/path_fixture.gd")
const C := 1024


func test_direct_los_same_tick(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var e: SimEntity = M.tank(w, 10, 30)
	SimMovement.go_to(w, e, 40 * C + 512, 30 * C + 512)
	t.eq(SimMovement.state(e), SimMoveConfig.MS_WAIT_PATH, "queued")
	t.eq(w.movement.path.pending(), 1, "one request")
	w.step()
	t.eq(e.move.state, SimMoveConfig.MS_MOVING, "delivered in the same tick (LOS shortcut)")
	t.eq(e.move.path, PackedInt32Array([30 * 64 + 40]), "direct path [goal]")
	t.eq(e.move.req_id, 0, "request cleared")
	t.eq(w.movement.path.pending(), 0, "queue empty")
	t.eq(e.move.path_ver, w.map.nav_version, "path version stamped")


func test_cancel_and_replace(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var e: SimEntity = M.tank(w, 10, 30)
	SimMovement.go_to(w, e, 40 * C, 30 * C)
	var first: int = e.move.req_id
	SimMovement.go_to(w, e, 20 * C, 40 * C)
	t.ne(e.move.req_id, first, "a new goal replaces the request")
	t.eq(w.movement.path.pending(), 1, "still one request")
	SimMovement.stop(w, e)
	t.eq(w.movement.path.pending(), 0, "stop cancels")
	t.eq(SimMovement.state(e), SimMoveConfig.MS_IDLE, "idle")
	t.eq(SimMovement.result(e), SimMoveConfig.RS_CANCELLED, "cancelled result")
	w.step()
	t.eq(e.move.path.size(), 0, "nothing delivered after cancel")


func test_group_shares_searches(t: TestCtx) -> void:
	var m: MapData = M.clutter_map(128, 25, 7)
	# pick an open start region and a far goal in the same component
	var prs: PackedInt32Array = Pf.pairs(m, MapTerrain.NP_TRACKED, 2, 1, 70, 5)
	t.check(prs.size() == 2, "pair found")
	var s: int = prs[0]
	var g: int = prs[1]
	var w: SimWorld = M.world(m)
	var units: Array[SimEntity] = []
	for i: int in 24:
		var cx: int = s % 128 + (i % 3) - 1
		var cy: int = s / 128 + (i / 3 % 3) - 1
		if m.nav.clear_at(MapTerrain.NP_TRACKED, cy * 128 + cx) < 2:
			cx = s % 128
			cy = s / 128
		units.append(M.tank(w, cx, cy))
	for e: SimEntity in units:
		SimMovement.go_to(w, e, (g % 128) * C + 512, (g / 128) * C + 512)
	var pend: int = w.movement.path.pending()
	t.eq(pend, units.size(), "all queued")
	var ps: SimPathService = w.movement.path
	w.step()
	t.eq(ps.pending(), units.size() - SimMoveConfig.PATH_MAX_DELIVERIES, "at most PATH_MAX_DELIVERIES per tick")
	w.step()
	t.eq(ps.pending(), 0, "served in two ticks")
	t.check(ps.stat_searches <= 3, "at most 3 searches for the group (%d)" % ps.stat_searches)
	t.check(ps.stat_hits >= units.size() - 3, "cache / attach hits %d" % ps.stat_hits)
	for e: SimEntity in units:
		t.check(e.move.path.size() > 0 and e.move.state == SimMoveConfig.MS_MOVING, "unit %d has a path" % e.id)


func test_partial_alternative_goal(t: TestCtx) -> void:
	# an island: the goal cell lies inside a walled pocket 6 cells from the reachable region
	var rows: PackedStringArray = M.grid(64)
	M.rect(rows, 30, 20, 36, 26, "#")
	M.rect(rows, 32, 22, 34, 24, ".")  # pocket
	var w: SimWorld = M.world(M.map_from(rows))
	var e: SimEntity = M.rifle(w, 10, 23)
	SimMovement.go_to(w, e, 33 * C + 512, 23 * C + 512)
	w.step()
	t.eq(e.move.state, SimMoveConfig.MS_MOVING, "walks toward the nearest reachable cell")
	t.check((e.move.flags & SimMoveConfig.MF_PATH_PARTIAL) != 0, "partial flag")
	var n: int = M.run_until(w, func() -> bool: return SimMovement.state(e) == SimMoveConfig.MS_ARRIVED, 600)
	t.check(n > 0, "arrives at the alternative goal")
	t.eq(SimMovement.result(e), SimMoveConfig.RS_PARTIAL, "RS_PARTIAL")
	t.check(e.y < 20 * C, "stopped outside the walled block (%d, %d)" % [e.x, e.y])


func test_budget_accounting(t: TestCtx) -> void:
	var m: MapData = M.urban_map(128, 16, 3)
	var w: SimWorld = M.world(m)
	var prs: PackedInt32Array = Pf.pairs(m, MapTerrain.NP_FOOT, 1, 12, 60, 11)
	var ents: Array[SimEntity] = []
	for k: int in prs.size() / 2:
		var e: SimEntity = M.rifle(w, prs[k * 2] % 128, prs[k * 2] / 128)
		ents.append(e)
		SimMovement.go_to(w, e, (prs[k * 2 + 1] % 128) * C + 512, (prs[k * 2 + 1] / 128) * C + 512)
	var ps: SimPathService = w.movement.path
	var ticks: int = 0
	var over: int = 0
	var max_pend: int = ps.pending()
	while ps.pending() > 0 and ticks < 200:
		w.step()
		ticks += 1
		if ps.last_units > ps.last_budget:
			over += 1
	t.note("budget test: %d requests drained in %d ticks, %d searches" % [ents.size(), ticks, ps.stat_searches])
	t.eq(over, 0, "units consumed never exceed the tick budget")
	t.eq(ps.pending(), 0, "every request finishes (searches resume across ticks)")
	t.check(max_pend >= 6 and ticks >= 1, "test exercised a queue")
	var got: int = 0
	for e: SimEntity in ents:
		if e.move.state == SimMoveConfig.MS_MOVING:
			got += 1
	t.eq(got, ents.size(), "all units have paths")
	w.step()
	t.eq(ps.last_budget, SimMoveConfig.PATH_BASE, "idle service reports the base budget")


func test_state_ints_and_cache_ring(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var ps: SimPathService = w.movement.path
	var a: PackedInt32Array = PackedInt32Array()
	ps.state_ints(a)
	var e: SimEntity = M.tank(w, 10, 30)
	SimMovement.go_to(w, e, 40 * C + 512, 30 * C + 512)
	var b: PackedInt32Array = PackedInt32Array()
	ps.state_ints(b)
	t.ne(a, b, "queued request changes the hashed state")
	w.step()
	var c: PackedInt32Array = PackedInt32Array()
	ps.state_ints(c)
	t.ne(b, c, "delivered request changes it again (cache entry)")
	ps.invalidate_cache()
	var d: PackedInt32Array = PackedInt32Array()
	ps.state_ints(d)
	t.ne(c, d, "invalidate_cache empties the ring")


func test_priority_order(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var ps: SimPathService = w.movement.path
	var low: Array[SimEntity] = []
	var high: Array[SimEntity] = []
	for i: int in 10:
		var e: SimEntity = M.rifle(w, 10 + i, 20)
		low.append(e)
		SimMovement.go_to(w, e, 50 * C, 20 * C)
		ps.request(e, 20 * 64 + 50, 0, SimPathService.PRIO_REPATH, 0)
	for i: int in 10:
		var e: SimEntity = M.rifle(w, 10 + i, 30)
		high.append(e)
		SimMovement.go_to(w, e, 50 * C, 30 * C)
	w.step()
	var high_done: int = 0
	var low_done: int = 0
	for e: SimEntity in high:
		if e.move.req_id == 0:
			high_done += 1
	for e: SimEntity in low:
		if e.move.req_id == 0:
			low_done += 1
	t.eq(high_done, 10, "PRIO_ORDER requests are served first")
	t.eq(low_done, SimMoveConfig.PATH_MAX_DELIVERIES - 10, "the rest of the deliveries go to PRIO_REPATH in FIFO order")
	# FIFO inside a priority: the earliest low requests got theirs
	t.eq(low[0].move.req_id, 0, "first repath request served")
	t.ne(low[9].move.req_id, 0, "last one waits")
