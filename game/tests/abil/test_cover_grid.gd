extends RefCounted
## AB-01: counted coverage grid (abilities 10.1 test_cover_grid).

const W: int = 40
const H: int = 30


func _lcg(s: int) -> int:
	return (s * 1103515245 + 12345) & 0x7FFFFFFF


func test_move_disc_equals_unstamp_stamp(t: TestCtx) -> void:
	var disc: SimDisc = SimDisc.new()
	var a: SimCoverGrid = SimCoverGrid.new(W, H, disc)
	var b: SimCoverGrid = SimCoverGrid.new(W, H, disc)
	var sink: SimCoverGrid.Sink = SimCoverGrid.Sink.new()
	var s: int = 12345
	var cx: int = 10
	var cy: int = 10
	var r: int = 6
	a.stamp_disc(cx, cy, r, 1, sink)
	b.stamp_disc(cx, cy, r, 1)
	var covered: PackedByteArray = PackedByteArray()  # shadow of "count > 0" built from the sink only
	covered.resize(W * H)
	for i: int in sink.cells.size():
		covered[sink.cells[i] >> 1] = sink.cells[i] & 1
	var mismatches: int = 0
	for step: int in 1000:
		s = _lcg(s)
		var nx: int = cx
		var ny: int = cy
		var kind: int = (s >> 8) % 5
		if kind == 0:  # a jump anywhere, edges included
			s = _lcg(s)
			nx = (s >> 8) % (W + 6) - 3
			s = _lcg(s)
			ny = (s >> 8) % (H + 6) - 3
		else:
			s = _lcg(s)
			nx = cx + (s >> 8) % 3 - 1
			s = _lcg(s)
			ny = cy + (s >> 8) % 3 - 1
		nx = clampi(nx, 0, W - 1)
		ny = clampi(ny, 0, H - 1)
		sink.clear()
		a.move_disc(cx, cy, nx, ny, r, sink)
		b.stamp_disc(cx, cy, r, -1)
		b.stamp_disc(nx, ny, r, 1)
		for i: int in sink.cells.size():
			covered[sink.cells[i] >> 1] = sink.cells[i] & 1
		cx = nx
		cy = ny
		if a.counts != b.counts or a.digest != b.digest:
			mismatches += 1
	t.eq(mismatches, 0, "1000 random moves: identical counts and digest")
	var shadow_bad: int = 0
	for cell: int in W * H:
		if (covered[cell] != 0) != (a.counts[cell] > 0):
			shadow_bad += 1
	t.eq(shadow_bad, 0, "the transition sink reproduces 'count > 0' exactly")
	a.stamp_disc(cx, cy, r, -1)
	t.eq(a.digest, 0, "digest returns to 0 after unstamping")
	var total: int = 0
	for v: int in a.counts:
		total += v
	t.eq(total, 0, "all counts back to 0")


func test_overlap_counts(t: TestCtx) -> void:
	var disc: SimDisc = SimDisc.new()
	var g: SimCoverGrid = SimCoverGrid.new(W, H, disc)
	var sink: SimCoverGrid.Sink = SimCoverGrid.Sink.new()
	g.stamp_disc(10, 10, 3, 1, sink)
	t.eq(sink.cells.size(), 29, "29 cells become covered")
	sink.clear()
	g.stamp_disc(11, 10, 3, 1, sink)
	t.eq(g.count_xy(10, 10), 2, "overlap counts 2")
	t.eq(sink.cells.size(), 7, "only the 7 new cells (one column) report a transition")
	sink.clear()
	g.stamp_disc(10, 10, 3, -1, sink)
	t.eq(g.count_xy(10, 10), 1, "one source left")
	t.eq(g.count_xy(7, 10), 0, "cell only the first covered is free")
	g.stamp_disc(11, 10, 3, -1)
	t.eq(g.digest, 0, "empty again")


func test_edges_and_capsule(t: TestCtx) -> void:
	var disc: SimDisc = SimDisc.new()
	var g: SimCoverGrid = SimCoverGrid.new(W, H, disc)
	g.stamp_disc(0, 0, 4, 1)
	t.eq(g.count_xy(4, 0), 1, "clipped disc at the corner covers (4, 0)")
	t.eq(g.count_xy(3, 3), 0, "3,3 is outside R=4 (18 > 16)")
	g.stamp_disc(0, 0, 4, -1)
	t.eq(g.digest, 0, "corner disc unstamps cleanly")
	# capsule: segment 12 cells long (x 10.5 .. 22.5), half width 2 cells
	var x0: int = 10 * 1024 + 512
	var x1: int = 22 * 1024 + 512
	var y: int = 10 * 1024 + 512
	g.stamp_capsule(x0, y, x1, y, 2048, 1)
	t.eq(g.count_xy(16, 10), 1, "centre line")
	t.eq(g.count_xy(16, 12), 1, "2 cells beside the axis is inside (centre distance 2048)")
	t.eq(g.count_xy(16, 13), 0, "3 cells beside is outside")
	t.eq(g.count_xy(24, 10), 1, "the end cap reaches 2 cells beyond")
	t.eq(g.count_xy(25, 10), 0, "and no further")
	g.stamp_capsule(x0, y, x1, y, 2048, -1)
	t.eq(g.digest, 0, "capsule unstamps cleanly")


func test_writes_are_bounded(t: TestCtx) -> void:
	var disc: SimDisc = SimDisc.new()
	var g: SimCoverGrid = SimCoverGrid.new(64, 64, disc)
	g.stamp_disc(20, 20, 8, 1)
	var before: int = g.stat_cells_written
	g.move_disc(20, 20, 21, 20, 8, null)
	t.eq(g.stat_cells_written - before, 2 * 17, "an x step of R=8 writes 2 cells per row = 34")
	before = g.stat_cells_written
	g.move_disc(21, 20, 21, 21, 8, null)
	t.le(g.stat_cells_written - before, 40, "a y step writes about 2 rows")
