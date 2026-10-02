extends RefCounted
## TM-05: MapPathSearch (U5 fine A*, U6 corridor search, LOS shortcut, smoothing, partial / avoid / goal radius,
## resumability, determinism).

const Fx := preload("res://tests/fixtures/map_fixture.gd")
const Pf := preload("res://tests/fixtures/path_fixture.gd")
const FOOT: int = MapTerrain.NP_FOOT
const WHEELED: int = MapTerrain.NP_WHEELED
const NONE: PackedInt32Array = []


func _run(s: MapPathSearch, budget: int) -> int:
	var total: int = 0
	var guard: int = 0
	while s.status == MapPathSearch.ST_RUNNING and guard < 1000000:
		var u: int = s.step(budget)
		total += u
		guard += 1
	return total


func _search(m: MapData, np: int, size: int, a: int, b: int, mode: int = 0, budget: int = 1 << 30,
		goal_r: int = 0, avoid: PackedInt32Array = NONE) -> MapPathSearch:
	var s: MapPathSearch = MapPathSearch.new(m.nav)
	s.force_mode = mode
	s.begin(np, size, a, b, goal_r, avoid)
	_run(s, budget)
	return s


## Every consecutive waypoint pair (start included) has line of sight; returns the summed line cost or -1.
func _valid_cost(m: MapData, np: int, size: int, start: int, p: PackedInt32Array) -> int:
	var cur: int = start
	var sum: int = 0
	for c: int in p:
		var lc: int = m.nav.los_cost(np, size, cur, c)
		if lc < 0:
			return -1
		sum += lc
		cur = c
	return sum


func test_fine_astar_u5(t: TestCtx) -> void:
	var m: MapData = Fx.open(16)
	var a: int = m.idx(2, 2)
	var b: int = m.idx(13, 9)
	var s: MapPathSearch = _search(m, FOOT, 1, a, b, 1)
	t.eq(s.status, MapPathSearch.ST_DONE, "fine: done")
	t.eq(s.path_cost, 138, "7 diagonal + 4 orthogonal steps")
	t.eq(s.path, PackedInt32Array([b]), "smoothed to [goal]")
	var auto: MapPathSearch = _search(m, FOOT, 1, a, b)
	t.eq(auto.path, PackedInt32Array([b]), "auto: same [goal] via the LOS shortcut")
	t.eq(auto.expanded, 0, "LOS shortcut expands nothing")
	t.eq(auto.path_cost, 138, "LOS cost")
	# forest column x = 8 (weight 23 for foot): 10 * 10 + 14
	var patch: Dictionary = {}
	for y: int in 16:
		patch[y * 16 + 8] = MapTerrain.T_FOREST
	var f: MapData = Fx.open(16, patch)
	var fs: MapPathSearch = _search(f, FOOT, 1, f.idx(2, 7), f.idx(13, 7), 1)
	t.eq(fs.path_cost, 114, "cost across the forest column")
	t.eq(fs.status, MapPathSearch.ST_DONE, "done")
	t.eq(fs.path.size() > 0 and fs.path[fs.path.size() - 1] == f.idx(13, 7), true, "ends at the goal")
	# start == goal: nothing to do
	var z: MapPathSearch = _search(m, FOOT, 1, a, a)
	t.eq(z.status, MapPathSearch.ST_DONE, "start == goal")
	t.eq(z.path.size(), 0, "empty path")


func test_mirrored_maps_equal_cost(t: TestCtx) -> void:
	var a: MapData = Pf.clutter(64, 22, 21)
	var b: MapData = Pf.mirrored(a)
	var prs: PackedInt32Array = Pf.pairs(a, FOOT, 1, 12, 25, 3)
	for k: int in prs.size() / 2:
		var s0: int = prs[k * 2]
		var g0: int = prs[k * 2 + 1]
		var s1: int = (s0 / 64) * 64 + 63 - s0 % 64
		var g1: int = (g0 / 64) * 64 + 63 - g0 % 64
		var pa: MapPathSearch = _search(a, FOOT, 1, s0, g0, 1)
		var pb: MapPathSearch = _search(b, FOOT, 1, s1, g1, 1)
		t.eq(pa.status, pb.status, "pair %d: same status" % k)
		if pa.status == MapPathSearch.ST_DONE:
			t.eq(pa.path_cost, pb.path_cost, "pair %d: mirrored cost" % k)


func test_resumable_budget_independent(t: TestCtx) -> void:
	var m: MapData = Pf.clutter(128, 25, 5)
	var prs: PackedInt32Array = Pf.pairs(m, WHEELED, 2, 6, 70, 9)
	for k: int in prs.size() / 2:
		var a: int = prs[k * 2]
		var b: int = prs[k * 2 + 1]
		var ref: MapPathSearch = _search(m, WHEELED, 2, a, b)
		for mode: int in [0, 1, 2]:
			var r: MapPathSearch = _search(m, WHEELED, 2, a, b, mode)
			for budget: int in [1, 7, 50, 1600]:
				var s: MapPathSearch = MapPathSearch.new(m.nav)
				s.force_mode = mode
				s.begin(WHEELED, 2, a, b, 0, NONE)
				var over: int = 0
				while s.status == MapPathSearch.ST_RUNNING:
					var u: int = s.step(budget)
					if u > budget:
						over += 1
					if u < 1 and s.status == MapPathSearch.ST_RUNNING:
						t.fail("step consumed no units and did not finish")
						break
				if budget >= 50:
					t.eq(over, 0, "pair %d mode %d budget %d: units in 1..budget" % [k, mode, budget])
				t.eq(s.status, r.status, "pair %d mode %d budget %d: status" % [k, mode, budget])
				t.eq(s.path, r.path, "pair %d mode %d budget %d: path" % [k, mode, budget])
				t.eq(s.path_cost, r.path_cost, "pair %d mode %d budget %d: cost" % [k, mode, budget])
				t.eq(s.expanded, r.expanded, "pair %d mode %d budget %d: expanded" % [k, mode, budget])
		t.eq(ref.status, MapPathSearch.ST_DONE, "pair %d reachable" % k)


func test_corridor_u6(t: TestCtx) -> void:
	var maps: Array[MapData] = [Pf.clutter(128, 12, 41), Pf.clutter(128, 25, 42), Pf.clutter(128, 35, 43),
			Pf.urban(128, 16, 4), Pf.urban(128, 20, 3)]
	var pairs_n: int = 0
	var ratio_sum: int = 0
	var worst_ratio: int = 0
	var worst_exp: int = 0
	var bad_valid: int = 0
	var bad_cost: int = 0
	for m: MapData in maps:
		var prs: PackedInt32Array = Pf.pairs(m, WHEELED, 2, 30, 60, 5)
		for k: int in prs.size() / 2:
			var a: int = prs[k * 2]
			var b: int = prs[k * 2 + 1]
			var fine: MapPathSearch = _search(m, WHEELED, 2, a, b, 1)
			var corr: MapPathSearch = _search(m, WHEELED, 2, a, b, 2)
			if fine.status != MapPathSearch.ST_DONE:
				continue
			pairs_n += 1
			if corr.status != MapPathSearch.ST_DONE or corr.path.is_empty() or corr.path[corr.path.size() - 1] != b:
				bad_valid += 1
				continue
			var vc: int = _valid_cost(m, WHEELED, 2, a, corr.path)
			if vc < 0 or vc > corr.path_cost:
				bad_valid += 1
			var ratio: int = corr.path_cost * 1000 / fine.path_cost
			ratio_sum += ratio
			worst_ratio = maxi(worst_ratio, ratio)
			worst_exp = maxi(worst_exp, corr.expanded)
			if corr.path_cost * 2 > fine.path_cost * 3:
				bad_cost += 1
	t.check(pairs_n >= 100, "enough reachable pairs (%d)" % pairs_n)
	t.eq(bad_valid, 0, "every corridor result is valid (LOS between consecutive waypoints, smoothed cost <= raw)")
	t.eq(bad_cost, 0, "corridor cost <= 1.5 x optimum for every pair (spec fixtures: 1.25)")
	t.check(ratio_sum <= 1060 * pairs_n, "mean corridor cost ratio %d/1000 <= 1.06" % (ratio_sum / maxi(pairs_n, 1)))
	t.check(worst_exp <= 2500, "expanded (incl. abstract pops x2) <= 2500 (worst %d)" % worst_exp)
	t.note("corridor: %d pairs, mean ratio %d/1000, max %d/1000, worst expanded %d" % [
			pairs_n, ratio_sum / maxi(pairs_n, 1), worst_ratio, worst_exp])


func test_auto_long_search_uses_abstract_phase(t: TestCtx) -> void:
	var m: MapData = Pf.urban(128, 16, 4)
	var prs: PackedInt32Array = Pf.pairs(m, WHEELED, 2, 8, 80, 12)
	var used: int = 0
	for k: int in prs.size() / 2:
		var a: int = prs[k * 2]
		var b: int = prs[k * 2 + 1]
		var s: MapPathSearch = _search(m, WHEELED, 2, a, b)
		t.eq(s.status, MapPathSearch.ST_DONE, "pair %d done" % k)
		t.check(s.path.size() > 0 and s.path[s.path.size() - 1] == b, "pair %d ends at the goal" % k)
		t.check(_valid_cost(m, WHEELED, 2, a, s.path) >= 0, "pair %d valid path" % k)
		t.check(s.path.size() <= MapPathSearch.MAX_WAYPOINTS, "waypoint cap")
		if s.expanded > 0:
			used += 1
	t.check(used >= 1, "some queries needed real search work")


func test_no_path_across_components(t: TestCtx) -> void:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 32:
		var line: String = ""
		for x: int in 32:
			line += "#" if x == 16 else "."
		rows.append(line)
	var m: MapData = Fx.ascii(rows)
	var s: MapPathSearch = MapPathSearch.new(m.nav)
	s.begin(FOOT, 1, m.idx(6, 10), m.idx(25, 20), 0, NONE)
	t.eq(s.status, MapPathSearch.ST_NO_PATH, "different components: immediate NO_PATH")
	t.eq(s.expanded, 0, "expanded == 0")
	t.eq(s.step(100), 0, "step on a finished search consumes nothing")
	# out-of-range and border starts
	s.begin(FOOT, 1, -1, m.idx(25, 20), 0, NONE)
	t.eq(s.status, MapPathSearch.ST_NO_PATH, "bad start")
	s.begin(FOOT, 1, 0, m.idx(25, 20), 0, NONE)
	t.eq(s.status, MapPathSearch.ST_NO_PATH, "start on the map ring")


func test_partial_and_avoid(t: TestCtx) -> void:
	# one-cell-high corridor y = 8 sealed by an avoid cell: same abstract component, search exhausts -> PARTIAL
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 16:
		var line: String = ""
		for x: int in 16:
			line += "." if (y == 8 and x >= 2 and x <= 13) else "#"
		rows.append(line)
	var m: MapData = Fx.ascii(rows)
	var goal: int = m.idx(12, 8)
	var s: MapPathSearch = _search(m, FOOT, 1, m.idx(3, 8), goal, 0, 1 << 30, 0, PackedInt32Array([m.idx(8, 8)]))
	t.eq(s.status, MapPathSearch.ST_PARTIAL, "sealed by avoid: partial")
	t.eq(s.path[s.path.size() - 1], m.idx(7, 8), "ends at the reachable cell nearest the goal")
	var free: MapPathSearch = _search(m, FOOT, 1, m.idx(3, 8), goal)
	t.eq(free.status, MapPathSearch.ST_DONE, "without avoid: done")
	# avoid on the straight line of an open room: LOS shortcut and smoothing must not cut through it
	var o: MapData = Fx.open(24)
	var blocked: int = o.idx(11, 12)
	var d: MapPathSearch = _search(o, FOOT, 1, o.idx(4, 12), o.idx(18, 12), 0, 1 << 30, 0, PackedInt32Array([blocked]))
	t.eq(d.status, MapPathSearch.ST_DONE, "detour found")
	t.check(d.path.size() > 1, "not a direct shot")
	var o2: MapData = Fx.open(24)
	o2.occupy_cells(1, PackedInt32Array([blocked]))
	var seg_ok: bool = true
	var prev: int = o.idx(4, 12)
	for c: int in d.path:
		var cheb: int = maxi(absi(c % 24 - prev % 24), absi(c / 24 - prev / 24))
		if c == blocked or (cheb > 1 and o2.nav.los_cost(FOOT, 1, prev, c) < 0):
			seg_ok = false
		prev = c
	t.check(seg_ok, "no waypoint or straight segment passes through the avoid cell")


func test_goal_radius(t: TestCtx) -> void:
	var m: MapData = Fx.open(40)
	var goal: int = m.idx(30, 30)
	var s: MapPathSearch = _search(m, FOOT, 1, m.idx(5, 5), goal, 1, 1 << 30, 3)
	t.eq(s.status, MapPathSearch.ST_DONE, "done")
	var last: int = s.path[s.path.size() - 1]
	t.eq(maxi(absi(last % 40 - 30), absi(last / 40 - 30)), 3, "stops at Chebyshev distance 3")
	var near: MapPathSearch = _search(m, FOOT, 1, m.idx(28, 28), goal, 0, 1 << 30, 3)
	t.eq(near.status, MapPathSearch.ST_DONE, "already within the radius")
	t.eq(near.path.size(), 0, "empty path")


func test_stale_graph_still_finds_paths(t: TestCtx) -> void:
	var m: MapData = Fx.open(64)
	var wall: PackedInt32Array = PackedInt32Array()
	for y: int in range(2, 50):
		wall.append(y * 64 + 30)
	m.occupy_cells(1, wall)
	t.check(m.nav.pending_dirty() > 0, "graph is dirty (clearance / relabel queued)")
	var a: int = m.idx(6, 20)
	var b: int = m.idx(56, 20)
	var s: MapPathSearch = _search(m, FOOT, 1, a, b)
	t.eq(s.status, MapPathSearch.ST_DONE, "found around the wall while the graph is stale")
	t.check(_valid_cost(m, FOOT, 1, a, s.path) >= 0, "valid path around the wall")
	m.nav.flush_dirty(100000)
	var s2: MapPathSearch = _search(m, FOOT, 1, a, b)
	t.eq(s2.status, MapPathSearch.ST_DONE, "found after the flush")
	t.check(_valid_cost(m, FOOT, 1, a, s2.path) >= 0, "valid path after the flush")
	# fully sealed: different abstract components now
	var wall2: PackedInt32Array = PackedInt32Array()
	for y: int in range(50, 62):
		wall2.append(y * 64 + 30)
	m.occupy_cells(2, wall2)
	m.nav.flush_dirty(100000)
	var s3: MapPathSearch = MapPathSearch.new(m.nav)
	s3.begin(FOOT, 1, a, b, 0, NONE)
	t.eq(s3.status, MapPathSearch.ST_NO_PATH, "sealed wall: unreachable")


func test_state_ints_and_cancel(t: TestCtx) -> void:
	var m: MapData = Pf.clutter(96, 25, 8)
	var prs: PackedInt32Array = Pf.pairs(m, FOOT, 1, 1, 60, 3)
	var s1: MapPathSearch = MapPathSearch.new(m.nav)
	var s2: MapPathSearch = MapPathSearch.new(m.nav)
	s1.begin(FOOT, 1, prs[0], prs[1], 0, NONE)
	s2.begin(FOOT, 1, prs[0], prs[1], 0, NONE)
	var b1: PackedInt32Array = PackedInt32Array()
	var b2: PackedInt32Array = PackedInt32Array()
	while s1.status == MapPathSearch.ST_RUNNING:
		s1.step(37)
		s2.step(37)
		b1.clear()
		b2.clear()
		s1.state_ints(b1)
		s2.state_ints(b2)
		if b1 != b2:
			t.fail("state diverged")
			return
	t.eq(b1.size(), 7, "state_ints appends serial, status, expanded, cur, remaining, ne, phase")
	t.eq(s1.path, s2.path, "identical results")
	s1.begin(FOOT, 1, prs[0], prs[1], 0, NONE)
	s1.step(3)
	s1.cancel()
	t.eq(s1.status, MapPathSearch.ST_IDLE, "cancelled")
	t.eq(s1.step(100), 0, "nothing runs after cancel")
	s1.begin(FOOT, 1, prs[0], prs[1], 0, NONE)
	_run(s1, 1 << 30)
	t.eq(s1.path, s2.path, "the scratch is reusable at once after a cancel")


func test_partial_by_cap_and_waypoint_cap(t: TestCtx) -> void:
	# a long serpentine corridor (> 160 waypoints after smoothing is impossible to guarantee), so only check that
	# every result respects MAX_WAYPOINTS and the path ends on a passable cell
	var m: MapData = Pf.urban(128, 16, 4)
	var prs: PackedInt32Array = Pf.pairs(m, FOOT, 1, 10, 100, 4)
	for k: int in prs.size() / 2:
		var s: MapPathSearch = _search(m, FOOT, 1, prs[k * 2], prs[k * 2 + 1])
		t.check(s.path.size() <= MapPathSearch.MAX_WAYPOINTS, "waypoint cap (pair %d)" % k)
		t.check(s.status == MapPathSearch.ST_DONE or s.status == MapPathSearch.ST_PARTIAL, "pair %d resolved" % k)
