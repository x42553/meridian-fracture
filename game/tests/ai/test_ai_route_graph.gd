extends RefCounted
## AiRouteGraph over a scripted map (ai.md 10.1 test_ai_route_graph): corridors, threat shift, disjoint routes, chokes,
## unreachable goals, land-vs-water need, the resumable job.

const C: int = Fp.CELL


## 96x96 map, a 3-block-wide wall (cells 40..63) with one 1-block gap at cell rows 8..15 (corridor A) and one at 72..79 (B).
func _two_corridors(_cx: int, _cy: int, _mc: int) -> bool:
	if _cx >= 40 and _cx < 64:
		return (_cy >= 8 and _cy < 16) or (_cy >= 72 and _cy < 80)
	return true


func _graph(fn: Callable) -> AiRouteGraph:
	var g: AiRouteGraph = AiRouteGraph.new()
	g.bind_map(96, 96, fn)
	return g


func _through(pts: PackedInt32Array, y0: int, y1: int) -> bool:
	for i: int in pts.size() / 2:
		var cx: int = pts[2 * i] / C
		var cy: int = pts[2 * i + 1] / C
		if cx >= 40 and cx < 64 and cy >= y0 and cy < y1:
			return true
	return false


func test_shortest_corridor_and_threat_shift(t: TestCtx) -> void:
	var g: AiRouteGraph = _graph(_two_corridors)
	var out: PackedInt32Array = PackedInt32Array()
	var n: int = g.route(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.TRACKED, 0, out)
	t.gt(n, 3, "a route exists")
	t.check(_through(out, 8, 16), "the near corridor A is used")
	t.eq([out[out.size() - 2], out[out.size() - 1]], [85 * C, 30 * C] as Array, "last waypoint is the exact target")
	var threat: AiThreatMap = AiThreatMap.new()
	threat.setup(96, 96)
	g.threat = threat
	g.tick_hint = 100
	threat.add_sighting(52 * C, 12 * C, 100000)
	threat.commit(100)
	var out2: PackedInt32Array = PackedInt32Array()
	g.route(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.TRACKED, 64, out2)
	t.check(_through(out2, 72, 80), "a threat spike on A shifts the route to B")
	var out3: PackedInt32Array = PackedInt32Array()
	g.route(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.TRACKED, 0, out3)
	t.check(_through(out3, 8, 16), "weight 0 ignores the threat")


func test_disjoint_route_shares_no_block(t: TestCtx) -> void:
	var g: AiRouteGraph = _graph(_two_corridors)
	var a: PackedInt32Array = PackedInt32Array()
	g.route(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.TRACKED, 0, a)
	var b: PackedInt32Array = PackedInt32Array()
	var n: int = g.disjoint_route(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.TRACKED, a, b)
	t.gt(n, 3)
	t.check(_through(b, 72, 80) and not _through(b, 8, 16), "the second route takes the other corridor")
	var shared: int = 0
	var sb: int = g.block_at(10 * C, 30 * C)
	var gb: int = g.block_at(85 * C, 30 * C)
	for i: int in a.size() / 2:
		var ba: int = g.block_at(a[2 * i], a[2 * i + 1])
		if ba == sb or ba == gb:
			continue
		for j: int in b.size() / 2:
			if g.block_at(b[2 * j], b[2 * j + 1]) == ba:
				shared += 1
	t.eq(shared, 0, "no shared node besides start and goal")


func test_chokes_unreachable_and_water(t: TestCtx) -> void:
	var g: AiRouteGraph = _graph(_two_corridors)
	var a: PackedInt32Array = PackedInt32Array()
	g.route(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.TRACKED, 0, a)
	var ch: PackedInt32Array = PackedInt32Array()
	t.gt(g.chokes_on(a, ch), 0, "the corridor blocks are chokes")
	for i: int in ch.size() / 2:
		t.check(ch[2 * i] / C >= 40 and ch[2 * i] / C < 64, "chokes lie in the wall band")
	# island: the east half is cut off completely
	var island: AiRouteGraph = _graph(func(cx: int, _cy: int, _mc: int) -> bool: return cx < 40 or cx >= 64)
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(island.route(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.TRACKED, 0, out), 0, "unreachable => 0")
	t.check(island.needs_water(10 * C, 30 * C, 85 * C, 30 * C), "island fixture needs water")
	t.check_false(g.needs_water(10 * C, 30 * C, 85 * C, 30 * C), "the corridor map does not")
	t.check(g.connected(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.FOOT))


func test_job_is_resumable_and_deterministic(t: TestCtx) -> void:
	var g: AiRouteGraph = _graph(_two_corridors)
	var job: AiRouteJob = g.make_job(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.TRACKED, 0)
	var b: AiBudget = AiBudget.new()
	var steps: int = 0
	while not job.done and steps < 1000:
		b.reset(6, 6)  # three node expansions per step
		job.step(b)
		steps += 1
	t.check(job.done)
	t.gt(steps, 3, "took several small steps")
	var direct: PackedInt32Array = PackedInt32Array()
	g.route(10 * C, 30 * C, 85 * C, 30 * C, AiTypes.MoveClass.TRACKED, 0, direct)
	t.eq(job.result(), direct, "resumable result equals the direct one")
