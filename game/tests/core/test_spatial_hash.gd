extends RefCounted
## SpatialHash: brute-force equivalence, edge cases and bucket bookkeeping (sim_core 10.1).

const W: int = 96
const N: int = 1200


class Ref:
	extends RefCounted
	var xs: PackedInt32Array = PackedInt32Array()
	var ys: PackedInt32Array = PackedInt32Array()
	var tags: PackedInt32Array = PackedInt32Array()
	var alive: PackedByteArray = PackedByteArray()


func _populate(rng: SimRng, h: SpatialHash, ref: Ref) -> void:
	ref.xs.resize(N + 1)
	ref.ys.resize(N + 1)
	ref.tags.resize(N + 1)
	ref.alive.resize(N + 1)
	for id: int in range(1, N + 1):
		var x: int
		var y: int
		if id <= 800:  # dense cluster inside 30x30 cells
			x = 30 * 1024 + rng.next_int(30 * 1024)
			y = 30 * 1024 + rng.next_int(30 * 1024)
		else:
			x = rng.next_int(W * 1024)
			y = rng.next_int(W * 1024)
		var tag: int = rng.next_u32() & 0x3FFFF
		h.insert(id, x, y, tag)
		ref.xs[id] = x
		ref.ys[id] = y
		ref.tags[id] = tag
		ref.alive[id] = 1


func test_brute_force_equivalence(t: TestCtx) -> void:
	var rng: SimRng = SimRng.new(2024)
	var h: SpatialHash = SpatialHash.new(W, W)
	var ref: Ref = Ref.new()
	_populate(rng, h, ref)
	# move a third of them (some across buckets) and remove some, mirrored in the reference
	for id: int in range(1, N + 1, 3):
		var nx: int = rng.next_int(W * 1024)
		var ny: int = rng.next_int(W * 1024)
		h.move(id, nx, ny)
		ref.xs[id] = nx
		ref.ys[id] = ny
	for id: int in range(2, N + 1, 17):
		h.remove(id)
		ref.alive[id] = 0
	var out: PackedInt32Array = PackedInt32Array()
	var mismatches: int = 0
	var hits: int = 0
	for _q: int in 300:
		var x: int = rng.next_int(W * 1024 + 4096) - 2048
		var y: int = rng.next_int(W * 1024 + 4096) - 2048
		var r: int = rng.next_int(9 * 1024)
		var need: int = rng.next_u32() & rng.next_u32() & 0x3FFFF
		var avoid: int = rng.next_u32() & rng.next_u32() & rng.next_u32() & 0x3FFFF
		h.query_circle(x, y, r, out, need, avoid)
		var want: PackedInt32Array = PackedInt32Array()
		for id: int in range(1, N + 1):
			if ref.alive[id] == 0:
				continue
			var tg: int = ref.tags[id]
			if (tg & need) != need or (tg & avoid) != 0:
				continue
			var dx: int = ref.xs[id] - x
			var dy: int = ref.ys[id] - y
			if dx * dx + dy * dy <= r * r:
				want.append(id)
		hits += want.size()
		if want != out:
			mismatches += 1
	t.eq(mismatches, 0, "circle queries vs brute force")
	t.gt(hits, 0, "circle queries hit something")
	mismatches = 0
	for _q: int in 300:
		var x0: int = rng.next_int(W * 1024 + 4096) - 2048
		var y0: int = rng.next_int(W * 1024 + 4096) - 2048
		var x1: int = x0 + rng.next_int(12 * 1024)
		var y1: int = y0 + rng.next_int(12 * 1024)
		var need: int = rng.next_u32() & rng.next_u32() & 0x3FFFF
		var avoid: int = rng.next_u32() & rng.next_u32() & rng.next_u32() & 0x3FFFF
		h.query_rect(x0, y0, x1, y1, out, need, avoid)
		var want: PackedInt32Array = PackedInt32Array()
		for id: int in range(1, N + 1):
			if ref.alive[id] == 0:
				continue
			var tg: int = ref.tags[id]
			if (tg & need) != need or (tg & avoid) != 0:
				continue
			if ref.xs[id] >= x0 and ref.xs[id] <= x1 and ref.ys[id] >= y0 and ref.ys[id] <= y1:
				want.append(id)
		if want != out:
			mismatches += 1
	t.eq(mismatches, 0, "rect queries vs brute force")


func test_results_ascending(t: TestCtx) -> void:
	var h: SpatialHash = SpatialHash.new(W, W)
	for id: int in [9, 3, 7, 1, 5]:
		h.insert(id, 500 + id, 500, 1)
	var out: PackedInt32Array = PackedInt32Array()
	h.query_circle(500, 500, 100, out)
	t.eq(out, PackedInt32Array([1, 3, 5, 7, 9]), "ascending")


func test_edges_and_clamp(t: TestCtx) -> void:
	var h: SpatialHash = SpatialHash.new(W, W)
	var max_x: int = W * 1024 - 1
	h.insert(1, 0, 0, 1)
	h.insert(2, max_x, max_x, 1)
	h.insert(3, -5000, 999999999, 1)  # out of map: clamped
	t.eq(h.x_of(3), 0, "x clamped")
	t.eq(h.y_of(3), max_x, "y clamped")
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(h.query_circle(0, 0, 0, out), 1, "r = 0 finds exact centre")
	t.eq(h.query_circle(max_x, max_x, 10, out), 1, "far corner finds only 2")
	t.eq(h.query_circle(0, max_x, 10, out), 1, "clamped insert sits at (0, max)")
	t.eq(h.query_rect(-100, -100, 0, 0, out), 1, "rect edge inclusive, off-map origin")
	t.eq(h.query_circle(-100000, -100000, 50, out), 0, "far outside")
	t.eq(h.query_circle(0, 0, -1, out), 0, "negative radius")


func test_remove_move_grow(t: TestCtx) -> void:
	var h: SpatialHash = SpatialHash.new(W, W)
	h.insert(5, 100, 100, 3)
	h.remove(5)
	h.remove(5)
	t.check_false(h.contains(5), "removed")
	h.remove(99999)
	h.move(5, 1, 1)
	t.check_false(h.contains(5), "move of absent id is a no-op")
	h.insert(6, 100, 100, 3)
	h.move(6, 50 * 1024, 60 * 1024)  # across buckets
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(h.query_circle(100, 100, 500, out), 0, "left old bucket")
	t.eq(h.query_circle(50 * 1024, 60 * 1024, 10, out), 1, "arrived in new bucket")
	h.insert(100000, 7, 7, 1)  # beyond capacity: grows
	t.check(h.contains(100000), "grown")
	t.eq(h.tag_of(100000), 1, "tag survives growth")
	h.set_tag(100000, 9)
	t.eq(h.tag_of(100000), 9, "set_tag")
	h.insert(100000, 9000, 9000, 2)  # re-insert moves rather than duplicates
	t.eq(h.query_circle(7, 7, 100, out), 0, "old spot empty after re-insert")
	t.eq(h.query_circle(9000, 9000, 1, out), 1, "single entry")


func test_cell_bucket(t: TestCtx) -> void:
	var h: SpatialHash = SpatialHash.new(W, W)
	h.insert(4, 5 * 1024, 5 * 1024, 1)  # bucket (1,1) = cells 4..7
	h.insert(2, 6 * 1024, 4 * 1024, 1)
	h.insert(9, 20 * 1024, 20 * 1024, 1)
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(h.cell_bucket(7, 7, out), 2, "two in the bucket")
	t.eq(out, PackedInt32Array([2, 4]), "ascending")
	t.eq(h.cell_bucket(3, 3, out), 0, "neighbour bucket empty")


func test_shift_matches_config(t: TestCtx) -> void:
	t.eq(SpatialHash.SHIFT, SimConfig.SPATIAL_SHIFT, "SHIFT == SimConfig.SPATIAL_SHIFT")
