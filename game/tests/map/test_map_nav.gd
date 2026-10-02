extends RefCounted
## TM-03: MapNav weights, clearance (U3), LOS (U4), nearest_passable, deferred update (U9), graph seam.

const Fx := preload("res://tests/fixtures/map_fixture.gd")
const NavGraph := preload("res://tests/fixtures/fixture_nav_graph.gd")
const FOOT: int = MapTerrain.NP_FOOT
const WHEELED: int = MapTerrain.NP_WHEELED


func _corridor_map() -> MapData:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 16:
		var ch: String = "#"
		var line: String = ""
		var open: bool = y == 3 or y == 6 or y == 7 or y == 10 or y == 11 or y == 12
		for x: int in 16:
			line += "." if (open and x >= 2 and x <= 13) else ch
		rows.append(line)
	return Fx.ascii(rows)


func test_clearance_corridors(t: TestCtx) -> void:
	var m: MapData = _corridor_map()
	for y: int in [3, 6, 7, 10, 11, 12]:
		t.check(m.nav.passable(FOOT, 1, m.idx(7, y)), "foot passes corridor row %d" % y)
	t.check_false(m.nav.passable(WHEELED, 2, m.idx(7, 3)), "wheeled: 1-wide")
	t.check_false(m.nav.passable(WHEELED, 2, m.idx(7, 6)), "wheeled: 2-wide (row 6)")
	t.check_false(m.nav.passable(WHEELED, 2, m.idx(7, 7)), "wheeled: 2-wide (row 7)")
	t.check(m.nav.passable(WHEELED, 2, m.idx(7, 11)), "wheeled: centre line of the 3-wide")
	t.eq(m.nav.clear_at(WHEELED, m.idx(7, 11)), 2, "clr = 2 on the 3-wide centre")
	t.eq(m.nav.clear_at(WHEELED, m.idx(7, 10)), 1, "clr = 1 on the 3-wide edge")
	t.eq(m.nav.clear_at(FOOT, m.idx(7, 11)), 2, "clearance is profile-independent on grass")
	t.eq(m.nav.clear_at(FOOT, m.idx(7, 4)), 0, "wall")
	t.check(m.nav.validate_against_terrain(), "layers equal a from-scratch recompute")


func test_clearance_room_and_border(t: TestCtx) -> void:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 12:
		var line: String = ""
		for x: int in 12:
			line += "." if (x >= 3 and x <= 7 and y >= 3 and y <= 7) else "#"
		rows.append(line)
	var m: MapData = Fx.ascii(rows)
	t.eq(m.nav.clear_at(FOOT, m.idx(5, 5)), 3, "5x5 room centre")
	t.eq(m.nav.clear_at(FOOT, m.idx(4, 4)), 2, "ring 1")
	t.eq(m.nav.clear_at(FOOT, m.idx(3, 3)), 1, "corner")
	# NAV_BORDER on a make_flat map
	var f: MapData = MapData.make_flat(16, 16, PackedInt32Array([8, 8]), 1)
	for np: int in MapTerrain.NP_COUNT:
		for k: int in 16:
			t.eq(f.nav.w_at(np, f.idx(0, k)), 0, "border x=0 np %d" % np)
			t.eq(f.nav.w_at(np, f.idx(1, k)), 0, "border x=1")
			t.eq(f.nav.w_at(np, f.idx(k, 14)), 0, "border y=14")
			t.eq(f.nav.w_at(np, f.idx(k, 15)), 0, "border y=15")
	t.check(f.nav.passable(FOOT, 1, f.idx(2, 2)), "first interior cell passable")
	t.eq(f.nav.clear_at(FOOT, f.idx(2, 2)), 1, "next to the border: clr 1")
	t.eq(f.nav.clear_at(FOOT, f.idx(8, 8)), 3, "open centre")
	t.eq(f.nav.w_at(FOOT, f.idx(8, 8)), 16, "grass weight")
	t.eq(f.nav.w_at(MapTerrain.NP_NAVAL, f.idx(8, 8)), 0, "naval blocked on land")
	t.check_false(f.nav.is_active(MapTerrain.NP_NAVAL), "dry map: naval profile inactive")
	t.check(f.nav.is_active(WHEELED), "wheeled active")
	t.check(f.nav.validate_against_terrain(), "validate")


func test_weights_from_terrain(t: TestCtx) -> void:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 24:
		var line: String = ""
		for x: int in 24:
			var ch: String = "."
			if x == 5 and y == 8:
				ch = "F"
			elif x == 6 and y == 8:
				ch = "r"
			elif x == 7 and y == 8:
				ch = "X"
			elif x == 8 and y == 8:
				ch = "m"
			elif x == 9 and y == 8:
				ch = "f"
			elif x >= 12 and y >= 3 and y <= 20:
				ch = "~"
			line += ch
		rows.append(line)
	var m: MapData = Fx.ascii(rows)
	t.eq(m.nav.w_at(FOOT, m.idx(5, 8)), 23, "foot forest")
	t.eq(m.nav.w_at(WHEELED, m.idx(5, 8)), 0, "wheeled forest blocked")
	t.eq(m.nav.w_at(WHEELED, m.idx(6, 8)), 12, "wheeled road")
	t.eq(m.nav.w_at(FOOT, m.idx(7, 8)), 0, "SF_BLOCK blocks foot")
	t.eq(m.nav.w_at(MapTerrain.NP_AMPH, m.idx(7, 8)), 0, "SF_BLOCK blocks amph")
	t.eq(m.nav.w_at(WHEELED, m.idx(8, 8)), 40, "wheeled marsh clamp")
	t.eq(m.nav.w_at(WHEELED, m.idx(9, 8)), 32, "ford")
	t.eq(m.nav.w_at(MapTerrain.NP_NAVAL, m.idx(9, 8)), 20, "naval over ford")
	t.eq(m.nav.w_at(MapTerrain.NP_NAVAL_DEEP, m.idx(9, 8)), 0, "deep naval not over ford")
	t.eq(m.nav.w_at(MapTerrain.NP_NAVAL_DEEP, m.idx(12, 8)), 16, "deep water")
	t.eq(m.nav.w_at(FOOT, m.idx(12, 8)), 0, "foot cannot enter deep water")
	t.eq(m.nav.w_at(MapTerrain.NP_AMPH, m.idx(12, 8)), 23, "amph deep")
	t.eq(m.nav.w_at(MapTerrain.NP_SUB, m.idx(12, 8)), 16, "sub deep")
	t.eq(m.nav.w_at(MapTerrain.NP_SUB, m.idx(6, 6)), 0, "sub on land")
	t.check(m.passable(6, 8, MapTerrain.MC_WHEELED), "passable wheeled road")
	t.check_false(m.passable(7, 8, MapTerrain.MC_FOOT), "blocker")
	t.check(m.passable(7, 8, MapTerrain.MC_AIR_FIXED), "air passes blockers")
	t.check_false(m.passable(1, 8, MapTerrain.MC_AIR_FIXED), "air inside the interior only")
	t.check_false(m.passable(6, 8, MapTerrain.MC_STATIC), "static never")
	t.check(m.passable(12, 8, MapTerrain.MC_NAVAL), "small-hull naval on deep")
	t.check(m.passable(9, 8, MapTerrain.MC_NAVAL), "small-hull naval on ford")
	t.check(m.nav.validate_against_terrain(), "validate")


func test_los(t: TestCtx) -> void:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 16:
		var line: String = ""
		for x: int in 16:
			line += "#" if ((x == 8 and y == 7) or (x == 7 and y == 8)) else "."
		rows.append(line)
	var m: MapData = Fx.ascii(rows)
	var nav: MapNav = m.nav
	t.check_false(nav.los(FOOT, 1, m.idx(7, 7), m.idx(8, 8)), "diagonal squeeze between touching blockers: corner rule")
	t.check_false(nav.los(FOOT, 1, m.idx(8, 8), m.idx(7, 7)), "same, reversed")
	t.check(nav.los(FOOT, 1, m.idx(3, 3), m.idx(3, 12)), "straight through the open room")
	t.check(nav.los(FOOT, 1, m.idx(3, 3), m.idx(3, 3)), "self")
	t.check_false(nav.los(FOOT, 1, m.idx(6, 8), m.idx(9, 8)), "blocked by a cell on the line")
	t.eq(nav.los_cost(FOOT, 1, m.idx(3, 3), m.idx(13, 3)), 100, "10 orthogonal steps of weight 16")
	t.eq(nav.los_cost(FOOT, 1, m.idx(3, 3), m.idx(3, 3)), 0, "zero length")
	t.eq(nav.los_cost(FOOT, 1, m.idx(3, 10), m.idx(8, 12)), 3 * 10 + 2 * 14, "mixed steps: 3 orthogonal + 2 diagonal")
	t.eq(nav.los_cost(FOOT, 1, m.idx(6, 8), m.idx(9, 8)), -1, "blocked")
	t.eq(nav.los_cost(FOOT, 1, m.idx(3, 3), m.idx(8, 8)), -1, "line through blocked corner cells")
	t.check(nav.los(WHEELED, 2, m.idx(3, 3), m.idx(3, 12)), "size 2 fits the open room")
	# size 2 cannot pass next to the blocker column
	t.check_false(nav.los(WHEELED, 2, m.idx(6, 10), m.idx(9, 6)), "size 2 blocked near the blockers")
	t.check_false(nav.los(FOOT, 1, -1, 5), "invalid cell")


func test_nearest_passable(t: TestCtx) -> void:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 16:
		var line: String = ""
		for x: int in 16:
			var open: bool = (x == 9 and y == 6) or (x == 7 and y == 6) or (x == 7 and y == 10) or (x == 12 and y == 8)
			line += "." if open else "#"
		rows.append(line)
	var m: MapData = Fx.ascii(rows)
	var c: int = m.idx(8, 8)
	t.eq(m.nav.nearest_passable(FOOT, 1, c, 0), -1, "ring 0 only: blocked")
	t.eq(m.nav.nearest_passable(FOOT, 1, c, 1), -1, "nothing in ring 1")
	t.eq(m.nav.nearest_passable(FOOT, 1, c, 2), m.idx(7, 6), "top row left to right: (7,6) before (9,6)")
	t.eq(m.nav.nearest_passable(FOOT, 1, c, 3), m.idx(7, 6), "still ring 2")
	t.eq(m.nav.nearest_passable(FOOT, 1, m.idx(12, 8), 3), m.idx(12, 8), "passable cell returns itself")
	t.eq(m.nav.nearest_passable(FOOT, 1, m.idx(4, 12), 1), -1, "max_ring bounds the search")
	t.eq(m.nav.nearest_passable(FOOT, 1, m.idx(2, 14), 3), -1, "none within 3")
	t.eq(m.nav.nearest_passable(FOOT, 1, m.idx(4, 12), 4), m.idx(7, 10), "found at ring 3 via the walk order")


func test_occupy_vacate_weights_and_hashes(t: TestCtx) -> void:
	var m: MapData = Fx.open(32)
	var nav: MapNav = m.nav
	var w0: Array[PackedByteArray] = []
	var c0: Array[PackedByteArray] = []
	for np: int in MapTerrain.NP_COUNT:
		w0.append(nav.wgt_array(np).duplicate())
		c0.append(nav.clr_array(np).duplicate())
	var cells: PackedInt32Array = PackedInt32Array()
	for y: int in range(10, 14):
		for x: int in range(10, 14):
			cells.append(m.idx(x, y))
	var h0: int = m.checksum_dynamic()
	var bbox: int = m.occupy_cells(7, cells)
	t.eq(bbox, (10 << 24) | (10 << 16) | (13 << 8) | 13, "packed bbox")
	t.eq(m.nav_version, 1, "nav_version")
	t.ne(m.checksum_dynamic(), h0, "checksum reacts")
	for np: int in MapTerrain.NP_COUNT:
		for c: int in cells:
			t.eq(nav.w_at(np, c), 0, "occupied cell weight 0 (np %d)" % np)
	t.eq(nav.pending_dirty(), 1, "one queued clearance rect")
	t.eq(nav.flush_dirty(3), 0, "3 units cannot pay for a 4-unit rect")
	t.eq(nav.pending_dirty(), 1, "still queued")
	t.check(nav.validate_against_terrain(), "weights exact before the flush")
	t.eq(nav.flush_dirty(4), 4, "one rect = 4 units")
	nav.flush_dirty(100000)  # the real MapNavGraphs (TM-04) queue block relabels behind the clearance rect
	t.eq(nav.pending_dirty(), 0, "drained")
	t.eq(nav.clear_at(FOOT, m.idx(9, 9)), 1, "ring around the structure has clr 1")
	t.eq(nav.clear_at(FOOT, m.idx(8, 8)), 2, "two cells away: clr 2")
	t.eq(nav.clear_at(FOOT, m.idx(7, 7)), 3, "three cells away: clr 3")
	t.check(nav.validate_against_terrain(), "layers equal from-scratch after the flush")
	t.eq(m.recompute_dynamic_hash(), m.checksum_dynamic(), "recompute == incremental")
	t.eq(m.structure_at(m.idx(11, 11)), 7, "structure_at")
	t.eq(m.occupant_at(m.idx(9, 9)), -1, "occupant_at free")
	t.eq(m.occupant_at(-5), -1, "occupant_at outside")
	t.check_false(m.is_clear(11, 11, MapData.LAYER_GROUND), "not clear under a structure")
	t.check_false(m.passable(11, 11, MapTerrain.MC_TRACKED), "not passable under a structure")
	var v: int = m.vacate(7)
	t.eq(v, bbox, "vacate returns the same bbox")
	t.eq(m.nav_version, 2, "nav_version")
	t.eq(nav.w_at(FOOT, m.idx(11, 11)), 16, "weight restored at once")
	t.eq(nav.clear_at(FOOT, m.idx(11, 11)), 1, "freed cells start with clr 1")
	nav.flush_dirty(1000)
	for np: int in MapTerrain.NP_COUNT:
		t.check(nav.wgt_array(np) == w0[np], "weights byte-identical after vacate (np %d)" % np)
		t.check(nav.clr_array(np) == c0[np], "clearance byte-identical after vacate (np %d)" % np)
	t.eq(m.occ_hash, 0, "occ_hash back to 0")
	t.eq(m.recompute_dynamic_hash(), m.checksum_dynamic(), "recompute after vacate")
	t.eq(m.vacate(7), -1, "second vacate is a no-op")


func test_occupy_order_independent(t: TestCtx) -> void:
	var a: MapData = Fx.open(32)
	var b: MapData = Fx.open(32)
	var s1: PackedInt32Array = PackedInt32Array([a.idx(6, 6), a.idx(7, 6), a.idx(6, 7)])
	var s2: PackedInt32Array = PackedInt32Array([a.idx(20, 20), a.idx(21, 20)])
	a.occupy_cells(3, s1)
	a.occupy_cells(9, s2)
	b.occupy_cells(9, s2)
	b.occupy_cells(3, s1)
	t.eq(a.checksum_dynamic(), b.checksum_dynamic(), "checksum_dynamic order-independent")
	var ba: PackedInt32Array = PackedInt32Array()
	var bb: PackedInt32Array = PackedInt32Array()
	a.hash_state(ba)
	b.hash_state(bb)
	t.eq(ba, bb, "hash_state order-independent")
	t.eq(ba.size(), 5, "5 ints")
	t.eq(ba[0], 32, "w")
	t.eq(a.recompute_dynamic_hash(), a.checksum_dynamic(), "recompute a")
	a.nav.flush_dirty(1000)
	b.nav.flush_dirty(1000)
	for np: int in MapTerrain.NP_COUNT:
		t.check(a.nav.clr_array(np) == b.nav.clr_array(np), "same clearance np %d" % np)
	t.expect_errors(3)
	t.eq(a.occupy_cells(3, s2), -1, "duplicate sid rejected")
	t.eq(a.occupy_cells(4, s1), -1, "occupied cells rejected")
	t.eq(a.occupy_cells(5, PackedInt32Array([-1])), -1, "cell outside rejected")


func test_graph_seam(t: TestCtx) -> void:
	# two rooms joined by a 1-cell doorway at (8,8); the wall is column 8
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 16:
		var line: String = ""
		for x: int in 16:
			line += "#" if (x == 8 and y != 8) else "."
		rows.append(line)
	var m: MapData = Fx.ascii(rows)
	var nav: MapNav = MapNav.new(m.tt, m.w, m.h, m.terrain, m.flags, m.occ)
	nav.graph_factory = func(nv: MapNav, np: int, sz: int) -> Object: return NavGraph.new(nv, np, sz)
	nav.rebuild()
	t.check_false(nav.has_graph(FOOT, 1), "no graph before prepare")
	t.eq(nav.region_id(FOOT, 1, m.idx(4, 4)), -1, "no graph: region -1")
	t.check(nav.same_region(FOOT, 1, m.idx(4, 4), m.idx(12, 12)), "no graph: passable cells are conservatively connected")
	nav.prepare_all()
	t.check(nav.has_graph(FOOT, 1), "foot x1")
	t.check(nav.has_graph(WHEELED, 2), "wheeled x2")
	t.check(nav.has_graph(MapTerrain.NP_AMPH, 2), "amph x2")
	t.check_false(nav.has_graph(MapTerrain.NP_NAVAL, 2), "no naval graph on a dry map")
	t.check_false(nav.has_graph(WHEELED, 1), "only the prepared sizes")
	t.eq(nav.graphs.size(), 4, "a dry map gets four graphs")
	nav.prepare_all()
	t.eq(nav.graphs.size(), 4, "prepare is idempotent")
	var a: int = m.idx(4, 4)
	var b: int = m.idx(12, 12)
	t.check(nav.same_region(FOOT, 1, a, b), "joined through the doorway")
	t.ge(nav.region_id(FOOT, 1, a), 0, "region id")
	t.eq(nav.region_id(FOOT, 1, a), nav.region_id(FOOT, 1, b), "same id")
	t.eq(nav.region_size(FOOT, 1, a), nav.region_size(FOOT, 1, b), "same size")
	t.eq(nav.node_of(FOOT, 1, m.idx(8, 4)), -1, "wall has no node")
	t.eq(nav.region_id(FOOT, 1, m.idx(8, 4)), -1, "wall has no region")
	t.check_false(nav.same_region(FOOT, 1, a, m.idx(8, 4)), "wall not connected")
	# close the doorway with a structure
	m.occ[m.idx(8, 8)] = 5
	nav.on_cells_changed(8, 8, 8, 8)
	t.eq(nav.pending_dirty(), 1, "one clearance rect queued, no graph work yet")
	t.eq(nav.flush_dirty(4), 4, "clearance rect")
	t.eq(nav.pending_dirty(), 4, "one relabel unit per graph")
	t.eq(nav.flush_dirty(2), 2, "budget bounds the relabels")
	t.eq(nav.pending_dirty(), 2, "two left")
	t.eq(nav.flush_dirty(100), 2, "rest")
	t.eq(nav.pending_dirty(), 0, "drained")
	t.check_false(nav.same_region(FOOT, 1, a, b), "doorway closed: two regions")
	t.ne(nav.region_id(FOOT, 1, a), nav.region_id(FOOT, 1, b), "different ids")
	t.check(nav.region_size(FOOT, 1, a) > 0, "region size")
	t.eq(nav.estimate_cost(FOOT, 1, a, b), -1, "graph estimate is delegated (unreachable)")
	t.eq(nav.estimate_cost(FOOT, 1, a, m.idx(6, 12)), 0, "graph estimate is delegated (same region)")
	# independent clone
	var c: MapNav = nav.clone_for(m.occ.duplicate())
	t.eq(c.graphs.size(), 4, "graphs cloned")
	c._occ[m.idx(8, 8)] = -1
	c.on_cells_changed(8, 8, 8, 8)
	c.flush_dirty(100)
	t.check(c.same_region(FOOT, 1, a, b), "clone reopened")
	t.check_false(nav.same_region(FOOT, 1, a, b), "original unaffected")
	t.eq(nav.w_at(FOOT, m.idx(8, 8)), 0, "original weights unaffected")
	t.eq(c.w_at(FOOT, m.idx(8, 8)), 16, "clone weights")
	# without graphs estimate_cost falls back to the octile at baseline weight
	var plain: MapData = Fx.open(16)
	plain.nav.graphs.clear()  # finalize() builds the real graphs (TM-04); the fallback is the graph-less path
	t.eq(plain.nav.estimate_cost(FOOT, 1, plain.idx(2, 2), plain.idx(12, 9)), 10 * 17 - 6 * 7, "octile fallback")
