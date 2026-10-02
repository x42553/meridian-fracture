extends RefCounted
## TM-06 / U11: footprint cells, rotation, oriented size.

const MASK_3X3: PackedByteArray = [0, 0, 1, 0, 1, 1, 1, 1, 1]  # rows "..X" ".XX" "XXX"


func _rel(w: int, cells: PackedInt32Array, x0: int, y0: int) -> Array:
	# cells as [dx, dy] pairs relative to (x0, y0), sorted
	var out: Array = []
	for c: int in cells:
		out.append([c % w - x0, c / w - y0])
	return out


func test_cells_all_orientations(t: TestCtx) -> void:
	var out: PackedInt32Array = PackedInt32Array()
	var W: int = 20  # map width
	# authored solid cells (dx,dy): (2,0) (1,1) (2,1) (0,2) (1,2) (2,2)
	t.eq(MapFootprint.cells(3, 3, MASK_3X3, 0, 5, 5, out, W, W), 6, "count o0")
	t.eq(_rel(W, out, 5, 5), [[2, 0], [1, 1], [2, 1], [0, 2], [1, 2], [2, 2]], "o0")
	# orient 1: (dx,dy) -> (2-dy, dx)
	t.eq(MapFootprint.cells(3, 3, MASK_3X3, 1, 5, 5, out, W, W), 6, "count o1")
	var o1: Array = []
	for p: Array in [[2, 0], [1, 1], [2, 1], [0, 2], [1, 2], [2, 2]]:
		o1.append([2 - (p[1] as int), p[0]])
	o1.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	t.eq(_rel(W, out, 5, 5), o1, "o1 == rotate_offset of every solid cell")
	for o: int in 4:
		t.eq(MapFootprint.cells(3, 3, MASK_3X3, o, 5, 5, out, W, W), 6, "count o%d" % o)
		var want: Array = []
		var r: PackedInt32Array = PackedInt32Array([0, 0])
		for p: Array in [[2, 0], [1, 1], [2, 1], [0, 2], [1, 2], [2, 2]]:
			MapFootprint.rotate_offset(3, 3, o, p[0], p[1], r)
			want.append([r[0], r[1]])
		want.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
		t.eq(_rel(W, out, 5, 5), want, "orient %d equals rotate_offset applied to the mask" % o)
	# orient 2 explicitly: 180 degrees
	MapFootprint.cells(3, 3, MASK_3X3, 2, 5, 5, out, W, W)
	t.eq(_rel(W, out, 5, 5), [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [0, 2]], "o2 explicit")
	# full rectangle, 4x3
	t.eq(MapFootprint.cells(4, 3, PackedByteArray(), 0, 1, 1, out, W, W), 12, "rect 4x3")
	t.eq(MapFootprint.cells(4, 3, PackedByteArray(), 1, 1, 1, out, W, W), 12, "rect rotated")
	t.eq(out[0], 1 * W + 1, "first cell = top-left")
	t.eq(out[11], 4 * W + 3, "last cell of the 3-wide x 4-tall box")
	t.eq(MapFootprint.cells(2, 2, PackedByteArray(), 4, 0, 0, out, W, W), 4, "orient is taken mod 4")


func test_rotate_offset_and_sizes(t: TestCtx) -> void:
	var o: PackedInt32Array = PackedInt32Array([0, 0])
	for dx: int in 3:
		for dy: int in 3:
			MapFootprint.rotate_offset(3, 3, 1, dx, dy, o)
			t.eq(Vector2i(o[0], o[1]), Vector2i(2 - dy, dx), "o1 (%d,%d)" % [dx, dy])
			MapFootprint.rotate_offset(3, 3, 2, dx, dy, o)
			t.eq(Vector2i(o[0], o[1]), Vector2i(2 - dx, 2 - dy), "o2")
			MapFootprint.rotate_offset(3, 3, 3, dx, dy, o)
			t.eq(Vector2i(o[0], o[1]), Vector2i(dy, 2 - dx), "o3")
			MapFootprint.rotate_offset(3, 3, 0, dx, dy, o)
			t.eq(Vector2i(o[0], o[1]), Vector2i(dx, dy), "o0")
	MapFootprint.rotate_offset(4, 3, 1, 3, 2, o)
	t.eq(Vector2i(o[0], o[1]), Vector2i(0, 3), "non-square o1: (h-1-dy, dx)")
	t.eq(MapFootprint.oriented_size(4, 3, 1), (3 << 8) | 4, "oriented_size(4,3,1)")
	t.eq(MapFootprint.oriented_size(4, 3, 0), (4 << 8) | 3, "oriented_size(4,3,0)")
	t.eq(MapFootprint.oriented_size(4, 3, 2), (4 << 8) | 3, "oriented_size(4,3,2)")
	t.eq(MapFootprint.oriented_size(4, 3, 3), (3 << 8) | 4, "oriented_size(4,3,3)")


func test_outside_map(t: TestCtx) -> void:
	var out: PackedInt32Array = PackedInt32Array([99])
	t.eq(MapFootprint.cells(3, 3, PackedByteArray(), 0, 8, 8, out, 10, 10), -1, "sticks out at the bottom right")
	t.check(out.is_empty(), "out cleared on failure")
	t.eq(MapFootprint.cells(3, 3, PackedByteArray(), 0, 7, 7, out, 10, 10), 9, "fits exactly")
	t.eq(MapFootprint.cells(3, 2, PackedByteArray(), 1, 8, 8, out, 10, 10), -1, "rotated 2x3 at (8,8): row 10 is outside")
	t.eq(MapFootprint.cells(3, 2, PackedByteArray(), 0, 8, 8, out, 10, 10), -1, "3 wide at x=8")
	t.eq(MapFootprint.cells(3, 2, PackedByteArray(), 1, 8, 7, out, 10, 10), 6, "rotated 2 wide x 3 tall fits at (8,7)")
	t.eq(MapFootprint.cells(2, 2, PackedByteArray(), 0, -1, 0, out, 10, 10), -1, "negative origin")


func test_instance_form(t: TestCtx) -> void:
	var fp: MapFootprint = MapFootprint.new(3, 2, PackedByteArray(), true)
	t.eq(fp.size_oriented(1), (2 << 8) | 3, "rotatable footprint swaps")
	var fixed: MapFootprint = MapFootprint.new(3, 2, PackedByteArray(), false)
	t.eq(fixed.size_oriented(1), (3 << 8) | 2, "non-rotatable ignores orient")
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(fixed.cells_at(1, 4, 4, out, 16, 16), 6, "non-rotatable cells")
	t.eq(out[1], 4 * 16 + 5, "still 3 wide")
	t.eq(fp.cells_at(1, 4, 4, out, 16, 16), 6, "rotatable cells")
	t.eq(out[1], 4 * 16 + 5, "2 wide: second cell is on the next row")
	t.eq(out[2], 5 * 16 + 4, "third cell is one row down")
