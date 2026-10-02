extends RefCounted
## terrain_movement TM-15 (10.2 S12 S13 S14): scripted glides, exit cell search, eject with the MS_EVICT fallback.

const M := preload("res://tests/support/move_test_kit.gd")
const C := 1024


func test_s12_glide_exact_ticks(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var col: SimEntity = M.scout(w, 20, 30)
	var x0: int = col.x
	var y0: int = col.y
	SimMovement.glide(w, col, x0 + 3 * C, y0 + C, 12)  # dock in
	for i: int in 11:
		w.step()
	t.eq(SimMovement.state(col), SimMoveConfig.MS_GLIDE, "still gliding after 11 ticks")
	w.step()
	t.eq(SimMovement.state(col), SimMoveConfig.MS_ARRIVED, "12 ticks exactly")
	t.eq([col.x, col.y], [x0 + 3 * C, y0 + C], "endpoint exact")
	SimMovement.glide(w, col, x0, y0, 8)  # dock out
	w.run(7)
	t.eq(SimMovement.state(col), SimMoveConfig.MS_GLIDE, "8 ticks: 7 in")
	w.step()
	t.eq([SimMovement.state(col), col.x, col.y], [SimMoveConfig.MS_ARRIVED, x0, y0], "arrived after 8")


func test_ring_order(t: TestCtx) -> void:
	# ring 1 in the domain-wide walk: top row left -> right, right column, bottom row right -> left, left column
	var seen: Array[Vector2i] = []
	var k: int = 0
	while true:
		var p: int = SimExitMove.ring_cell(1, k)
		if p < 0:
			break
		seen.append(Vector2i((p & 0xFFFF) - 32768, (p >> 16) - 32768))
		k += 1
	var want: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
	t.eq(seen, want, "ring 1 order")
	for r: int in range(1, 6):
		var n: int = 0
		while SimExitMove.ring_cell(r, n) >= 0:
			n += 1
		t.eq(n, 8 * r, "ring %d has %d cells" % [r, 8 * r])


func test_s13_exit_search_and_rally(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var origin: int = 30 * 64 + 30
	var tanks: Array[SimEntity] = []
	var seen: Dictionary = {}
	for i: int in 10:
		var c: int = SimMovement.find_free_cell_near(w, origin, SimEntity.Layer.GROUND, 4)
		t.check(c >= 0 and not seen.has(c), "exit %d: distinct free cell" % i)
		seen[c] = true
		var e: SimEntity = M.tank(w, c % 64, c / 64)
		tanks.append(e)
		w.orders.issue(w, e, SimOrder.make(SimOrder.T_MOVE, 0, 45 * C + 512, (30 + i - 5) * C + 512), SimOrder.QM_REPLACE)
	t.check(seen.has(origin), "the first answer is the exit cell itself")
	var minr: int = 1 << 30
	for i: int in 10:
		for j: int in range(i + 1, 10):
			minr = mini(minr, Fp.dist(tanks[i].x - tanks[j].x, tanks[i].y - tanks[j].y))
	t.check(minr >= 1000, "no two units share a cell (min distance %d)" % minr)
	var start_x: Array[int] = []
	var start_y: Array[int] = []
	for e: SimEntity in tanks:
		start_x.append(e.x)
		start_y.append(e.y)
	var cleared: Array[int] = []
	cleared.resize(10)
	cleared.fill(-1)
	for tick: int in 40:
		w.step()
		for i: int in 10:
			if cleared[i] < 0 and Fp.dist(tanks[i].x - start_x[i], tanks[i].y - start_y[i]) >= C:
				cleared[i] = tick
	var late: int = 0
	for i: int in 10:
		if cleared[i] < 0:
			late += 1
	t.eq(late, 0, "every tank cleared the door within 40 ticks")
	# every cell within 4 rings taken: -1
	var w2: SimWorld = M.world(M.open_map(64))
	for y: int in range(26, 35):
		for x: int in range(26, 35):
			M.rifle(w2, x, y)
	t.eq(SimMovement.find_free_cell_near(w2, origin, SimEntity.Layer.GROUND, 4), -1, "no free cell within 4 rings")
	t.check(SimMovement.find_free_cell_near(w2, origin, SimEntity.Layer.GROUND, 6) >= 0, "a wider search finds one")
	# F_NO_COLLISION entities do not block a cell; other layers do not either
	var w3: SimWorld = M.world(M.open_map(64))
	var ghost: SimEntity = M.rifle(w3, 30, 30)
	ghost.flags |= SimFlags.F_NO_COLLISION
	t.eq(SimMovement.find_free_cell_near(w3, origin, SimEntity.Layer.GROUND, 2), origin, "a non-colliding unit leaves the cell free")
	t.eq(SimMovement.find_free_cell_near(w3, origin, SimEntity.Layer.AIR, 2), origin, "air: the cell itself")


func test_s14_eject(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var mine: Array[SimEntity] = []
	for i: int in 4:
		mine.append(M.rifle(w, 20 + i, 20 + (i & 1)))
	var foe: SimEntity = M.rifle(w, 21, 21, 1)
	var fx: int = foe.x
	var fy: int = foe.y
	w.step()
	SimMovement.eject_units_from_rect(w, 19, 19, 23, 22, w.team_of(0))
	t.eq([foe.x, foe.y], [fx, fy], "the enemy stays")
	var cells: Dictionary = {}
	for e: SimEntity in mine:
		var cx: int = e.x >> 10
		var cy: int = e.y >> 10
		t.check(cx < 19 or cx > 23 or cy < 19 or cy > 22, "unit %d is outside the rectangle (%d,%d)" % [e.id, cx, cy])
		cells[Vector2i(cx, cy)] = true
		t.eq([e.move.spd_q4, e.move.state], [0, SimMoveConfig.MS_IDLE], "stopped")
	t.eq(cells.size(), 4, "each to its own cell")
	# same call twice: identical result (ascending id, pure)
	var w2: SimWorld = M.world(M.open_map(64))
	var mine2: Array[SimEntity] = []
	for i: int in 4:
		mine2.append(M.rifle(w2, 20 + i, 20 + (i & 1)))
	M.rifle(w2, 21, 21, 1)
	w2.step()
	SimMovement.eject_units_from_rect(w2, 19, 19, 23, 22, w2.team_of(0))
	for i: int in 4:
		t.eq([mine2[i].x, mine2[i].y], [mine[i].x, mine[i].y], "deterministic placement of unit %d" % i)


func test_s14_boxed_in_unit_drives_out(t: TestCtx) -> void:
	var rows: PackedStringArray = M.grid(64)
	M.rect(rows, 2, 2, 61, 61, "#")
	M.rect(rows, 30, 30, 34, 34, ".")  # a 5x5 room: no size-2 cell outside the 3x3 rectangle
	var w: SimWorld = M.world(M.map_from(rows))
	var v: SimEntity = M.rifle(w, 32, 32)
	w.step()
	SimMovement.eject_units_from_rect(w, 31, 31, 33, 33, w.team_of(0))
	t.eq(SimMovement.state(v), SimMoveConfig.MS_EVICT, "no free cell: MS_EVICT")
	var n: int = M.run_until(w, func() -> bool: return SimMovement.state(v) != SimMoveConfig.MS_EVICT, 40)
	t.check(n > 0 and n <= 40, "leaves within 40 ticks (%d)" % n)
	var cx: int = v.x >> 10
	var cy: int = v.y >> 10
	t.check(cx < 31 or cx > 33 or cy < 31 or cy > 33, "outside the rectangle (%d,%d)" % [cx, cy])
	t.eq(SimMovement.result(v), SimMoveConfig.RS_OK, "RS_OK")
	# a unit with nowhere to go at all keeps its place
	var rows2: PackedStringArray = M.grid(64)
	M.rect(rows2, 2, 2, 61, 61, "#")
	M.rect(rows2, 31, 31, 33, 33, ".")
	var w2: SimWorld = M.world(M.map_from(rows2))
	var u: SimEntity = M.rifle(w2, 32, 32)
	w2.step()
	var ux: int = u.x
	SimMovement.eject_units_from_rect(w2, 31, 31, 33, 33, w2.team_of(0))
	t.eq([u.x, SimMovement.state(u)], [ux, SimMoveConfig.MS_IDLE], "sealed room: the unit stays")
