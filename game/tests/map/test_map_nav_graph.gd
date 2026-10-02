extends RefCounted
## TM-04: MapNavGraph structure, incremental relabel == fresh build (U14), regions, estimate_cost, clone.

const Fx := preload("res://tests/fixtures/map_fixture.gd")
const Pf := preload("res://tests/fixtures/path_fixture.gd")
const FOOT: int = MapTerrain.NP_FOOT
const WHEELED: int = MapTerrain.NP_WHEELED


func _graph(m: MapData, np: int, size: int) -> MapNavGraph:
	return m.nav.graphs[np * 4 + size] as MapNavGraph


func _fresh(m: MapData, np: int, size: int) -> MapNavGraph:
	var g: MapNavGraph = MapNavGraph.new(m.nav, np, size)
	g.build()
	return g


func _nodes_used(g: MapNavGraph) -> int:
	var c: int = 0
	for k: int in g.nodes:
		if g.node_cnt[k] > 0:
			c += 1
	return c


## Structural invariants: symmetric sorted adjacency with equal costs, adjacent nodes share cc, one node per
## passable cell, node cell counts add up.
func _check_invariants(t: TestCtx, m: MapData, g: MapNavGraph, tag: String) -> void:
	var clr: PackedByteArray = m.nav.clr_array(g.np)
	var ok_sym: bool = true
	var ok_cc: bool = true
	for a: int in g.nodes:
		var o: int = a * MapNavGraph.MAX_DEG
		if g.node_cnt[a] == 0 and g.deg[a] != 0:
			ok_sym = false
		for k: int in g.deg[a]:
			var b: int = g.adj[o + k]
			if k > 0 and g.adj[o + k - 1] >= b:
				ok_sym = false
			var found: bool = false
			for q: int in g.deg[b]:
				if g.adj[b * MapNavGraph.MAX_DEG + q] == a:
					found = g.adj_cost[b * MapNavGraph.MAX_DEG + q] == g.adj_cost[o + k]
			if not found or (b >> 3) == (a >> 3):
				ok_sym = false
			if g.cc[a] != g.cc[b]:
				ok_cc = false
	t.check(ok_sym, tag + ": adjacency symmetric, sorted, equal costs, no intra-block edge")
	t.check(ok_cc, tag + ": adjacent nodes share a component")
	var cells: int = 0
	var bad: int = 0
	for i: int in m.n:
		var passable: bool = clr[i] >= g.size
		if passable != (g.node_of_cell[i] >= 0):
			bad += 1
		if passable:
			cells += 1
	t.eq(bad, 0, tag + ": node_of_cell >= 0 exactly on passable cells")
	var sum: int = 0
	for k: int in g.nodes:
		sum += g.node_cnt[k]
	t.eq(sum, cells, tag + ": node cell counts add up")


## Independent per-block reference labelling (naive BFS) against the graph's nodes.
func _check_labelling(t: TestCtx, m: MapData, g: MapNavGraph, tag: String) -> void:
	var clr: PackedByteArray = m.nav.clr_array(g.np)
	var wg: PackedByteArray = m.nav.wgt_array(g.np)
	var bad: int = 0
	for b: int in g.nbx * g.nby:
		var x0: int = (b % g.nbx) * 8
		var y0: int = (b / g.nbx) * 8
		var comp: Dictionary = {}  # cell -> component index (first-cell order)
		var ncomp: int = 0
		var sums: PackedInt32Array = PackedInt32Array()
		var cnts: PackedInt32Array = PackedInt32Array()
		var reps: PackedInt32Array = PackedInt32Array()
		var repd: PackedInt32Array = PackedInt32Array()
		for y: int in range(y0, mini(y0 + 8, g.h)):
			for x: int in range(x0, mini(x0 + 8, g.w)):
				var i: int = y * g.w + x
				if clr[i] < g.size or comp.has(i):
					continue
				var st: Array[int] = [i]
				comp[i] = ncomp
				sums.append(0)
				cnts.append(0)
				reps.append(-1)
				repd.append(99)
				while not st.is_empty():
					var c: int = st.pop_back()
					sums[ncomp] += wg[c]
					cnts[ncomp] += 1
					for d: int in [1, -1, g.w, -g.w]:
						var q: int = c + d
						var qx: int = q % g.w
						var qy: int = q / g.w
						if qx >= x0 and qx < x0 + 8 and qy >= y0 and qy < y0 + 8 and clr[q] >= g.size and not comp.has(q):
							comp[q] = ncomp
							st.append(q)
				ncomp += 1
		if ncomp > 8:
			continue  # > 8 components: documented degradation, not compared
		for y: int in range(y0, mini(y0 + 8, g.h)):
			for x: int in range(x0, mini(x0 + 8, g.w)):
				var i: int = y * g.w + x
				if not comp.has(i):
					continue
				var k: int = comp[i]
				var dd: int = maxi(absi(x - (x0 + 3)), absi(y - (y0 + 3)))
				if dd < repd[k]:
					repd[k] = dd
					reps[k] = i
		for k: int in ncomp:
			var nd: int = b * 8 + k
			if g.node_cnt[nd] != cnts[k] or g.node_sumw[nd] != sums[k] or g.node_rep[nd] != reps[k]:
				bad += 1
		for i: int in comp:
			if g.node_of_cell[i] != b * 8 + (comp[i] as int):
				bad += 1
	t.eq(bad, 0, tag + ": labelling equals the reference flood (count, weight sum, representative)")


func test_structure_and_labelling(t: TestCtx) -> void:
	var m: MapData = Pf.clutter(96, 25, 3)
	for key: int in m.nav.graphs.keys():
		var g: MapNavGraph = m.nav.graphs[key] as MapNavGraph
		var tag: String = "clutter np%d s%d" % [g.np, g.size]
		_check_invariants(t, m, g, tag)
		_check_labelling(t, m, g, tag)
	var u: MapData = Pf.urban(96, 16, 4)
	var gu: MapNavGraph = _graph(u, WHEELED, 2)
	_check_invariants(t, u, gu, "urban")
	_check_labelling(t, u, gu, "urban")
	# odd map size: partial blocks
	var s: MapData = Pf.clutter(84, 20, 4)
	_check_invariants(t, s, _graph(s, FOOT, 1), "84x84")
	_check_labelling(t, s, _graph(s, FOOT, 1), "84x84")


func test_open_map_edges_and_diagonals(t: TestCtx) -> void:
	var m: MapData = Fx.open(32)
	var g: MapNavGraph = _graph(m, FOOT, 1)
	# block (1,1) = 5 has 8 neighbours in a 4x4 block map: all four orthogonal + all four diagonal
	t.eq(g.deg[5 * 8], 8, "interior block: 8 edges (orthogonal + diagonal)")
	var has_diag: bool = false
	for k: int in g.deg[5 * 8]:
		if g.adj[5 * 8 * MapNavGraph.MAX_DEG + k] == 10 * 8:
			has_diag = true
	t.check(has_diag, "diagonal edge to block (2,2)")
	t.eq(g.node_of(m.idx(10, 10)), 5 * 8, "node id = block * 8 + slot")
	t.eq(g.node_rep[5 * 8], m.idx(11, 11), "representative = block centre cell (bx*8+3, by*8+3)")
	t.eq(g.node_cnt[5 * 8], 64, "full block")
	t.eq(g.node_sumw[5 * 8], 64 * 16, "weight sum")
	# edge cost = octile10(rep, rep) * (16 + 16) / 32
	var ok: bool = true
	for k: int in g.deg[5 * 8]:
		var nb: int = g.adj[5 * 8 * MapNavGraph.MAX_DEG + k]
		var dx: int = absi(g.node_rx[5 * 8] - g.node_rx[nb])
		var dy: int = absi(g.node_ry[5 * 8] - g.node_ry[nb])
		if g.adj_cost[5 * 8 * MapNavGraph.MAX_DEG + k] != 10 * (dx + dy) - 6 * mini(dx, dy):
			ok = false
	t.check(ok, "edge cost = octile at baseline weight")
	t.eq(g.cc_cells.size(), 1, "one component")


func test_node_counts_256(t: TestCtx) -> void:
	for pct: int in [12, 35]:
		var m: MapData = Pf.clutter(256, pct, 100 + pct)
		var g: MapNavGraph = _graph(m, WHEELED, 2)
		var n: int = _nodes_used(g)
		t.note("256^2 clutter %d%%: %d wheeled nodes" % [pct, n])
		t.check(n >= 900 and n <= 1400, "node count %d in the 1024-block ballpark (%d%%)" % [n, pct])
		t.check(n <= 1024 * 8, "bounded by 8 per block")


func test_regions_and_estimate(t: TestCtx) -> void:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 32:
		var line: String = ""
		for x: int in 32:
			line += "#" if x == 16 else "."
		rows.append(line)
	var m: MapData = Fx.ascii(rows)
	var a: int = m.idx(6, 10)
	var b: int = m.idx(25, 20)
	var c: int = m.idx(6, 25)
	t.check_false(m.nav.same_region(FOOT, 1, a, b), "wall splits the map")
	t.check(m.nav.same_region(FOOT, 1, a, c), "same side")
	t.eq(m.nav.estimate_cost(FOOT, 1, a, b), -1, "unreachable")
	t.eq(m.nav.estimate_cost(FOOT, 1, a, m.idx(16, 10)), -1, "blocked cell")
	var same: int = m.nav.estimate_cost(FOOT, 1, a, c)
	var oct: int = 10 * 15
	t.check(same >= oct and same <= oct + 100, "same-side estimate %d ~ octile %d (+ rep detour)" % [same, oct])
	t.check(m.nav.region_size(FOOT, 1, a) > 0, "region size")
	t.ne(m.nav.region_size(FOOT, 1, a), 0, "region size")
	# open 256 map: estimate ~ octile
	var o: MapData = Fx.open(256)
	var p: int = o.idx(10, 10)
	var q: int = o.idx(240, 200)
	var est: int = o.nav.estimate_cost(FOOT, 1, p, q)
	var oc: int = 10 * (230 + 190) - 6 * 190
	t.check(est >= oc * 95 / 100 and est <= oc * 108 / 100, "open map estimate %d ~ octile %d" % [est, oc])
	t.check(o.nav.estimate_cost(WHEELED, 2, p, q) > 0, "wheeled estimate")


func test_dirty_flush_equals_fresh_u14(t: TestCtx) -> void:
	var m: MapData = Pf.clutter(96, 20, 9)
	var rng: Pf.Lcg = Pf.Lcg.new(77)
	var sid: int = 1
	var live: PackedInt32Array = PackedInt32Array()
	for round_i: int in 4:
		for _k: int in 5:
			var wd: int = 2 + rng.next(4)
			var ht: int = 2 + rng.next(4)
			var x0: int = 3 + rng.next(m.w - 8 - wd)
			var y0: int = 3 + rng.next(m.h - 8 - ht)
			var cells: PackedInt32Array = PackedInt32Array()
			var free: bool = true
			for y: int in range(y0, y0 + ht):
				for x: int in range(x0, x0 + wd):
					cells.append(y * m.w + x)
					if m.occ[y * m.w + x] >= 0:
						free = false
			if free:
				m.occupy_cells(sid, cells)
				live.append(sid)
				sid += 1
		if round_i >= 2 and not live.is_empty():
			m.vacate(live[rng.next(live.size())])
			m.vacate(live[live.size() - 1])
		# drain with small budgets like the tick loop does
		var guard: int = 0
		while m.nav.pending_dirty() > 0 and guard < 100000:
			m.nav.flush_dirty(12)
			guard += 1
		t.eq(m.nav.pending_dirty(), 0, "drained (round %d)" % round_i)
		t.check(m.nav.validate_against_terrain(), "layers valid (round %d)" % round_i)
		for key: int in m.nav.graphs.keys():
			var g: MapNavGraph = m.nav.graphs[key] as MapNavGraph
			var f: MapNavGraph = _fresh(m, g.np, g.size)
			t.check(g.equals(f), "round %d np%d s%d: relabelled graph equals a fresh build" % [round_i, g.np, g.size])
	_check_invariants(t, m, _graph(m, WHEELED, 2), "after updates")


func test_dirty_state_and_pending(t: TestCtx) -> void:
	var m: MapData = Fx.open(48)
	var g: MapNavGraph = _graph(m, FOOT, 1)
	t.eq(g.pending(), 0, "clean")
	m.occupy_cells(1, PackedInt32Array([m.idx(20, 20), m.idx(21, 20), m.idx(20, 21), m.idx(21, 21)]))
	t.eq(g.pending(), 0, "graph work is only queued by the clearance flush")
	m.nav.flush_dirty(4)
	t.check(g.pending() >= 1, "blocks queued")
	var before: int = g.pending()
	g.relabel_step()
	t.eq(g.pending(), before - 1, "one block per relabel step")
	m.nav.flush_dirty(1000)
	t.eq(g.pending(), 0, "drained")
	t.check(g.equals(_fresh(m, FOOT, 1)), "equals fresh")


func test_clone_independent(t: TestCtx) -> void:
	var m: MapData = Fx.open(64)
	var c: MapData = m.clone_for_world()
	var g: MapNavGraph = _graph(m, WHEELED, 2)
	var gc: MapNavGraph = _graph(c, WHEELED, 2)
	t.check(g.equals(gc), "clone has an equal graph")
	t.check(g != gc and g.adj != PackedInt32Array() and gc.node_of_cell != PackedInt32Array(), "distinct objects")
	c.occupy_cells(3, PackedInt32Array([c.idx(30, 30), c.idx(31, 30), c.idx(30, 31), c.idx(31, 31)]))
	c.nav.flush_dirty(1000)
	t.check(g.equals(_fresh(m, WHEELED, 2)), "original graph untouched")
	t.check(gc.equals(_fresh(c, WHEELED, 2)), "clone graph updated")
	t.check_false(g.equals(gc), "diverged")
