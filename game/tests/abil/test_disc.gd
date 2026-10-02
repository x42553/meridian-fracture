extends RefCounted
## AB-01: integer disc tables (abilities 5.9.3 / 10.1 test_disc).


func test_cell_counts(t: TestCtx) -> void:
	var d: SimDisc = SimDisc.new()
	var expect: Dictionary = {0: 1, 1: 5, 2: 13, 3: 29, 4: 49, 5: 81, 6: 113, 7: 149, 8: 197, 10: 317, 12: 441}
	for r: int in expect:
		t.eq(d.cell_count(r), expect[r], "R=%d" % r)
	t.eq(d.half_width(8, 0), 8, "middle row of R=8")
	t.eq(d.half_width(8, 8), 0, "pole of R=8")
	t.eq(d.half_width(8, 9), -1, "outside")
	t.eq(d.half_width(5, 3), 4, "isqrt(25 - 9)")


func test_every_cell_matches_the_definition(t: TestCtx) -> void:
	var d: SimDisc = SimDisc.new()
	var bad: int = 0
	for r: int in range(0, 33):
		for dy: int in range(-32, 33):
			var hw: int = d.half_width(r, dy)
			for dx: int in range(-33, 34):
				var inside: bool = dx * dx + dy * dy <= r * r
				var claimed: bool = hw >= 0 and absi(dx) <= hw
				if inside != claimed:
					bad += 1
	t.eq(bad, 0, "hw table equals dx*dx + dy*dy <= R*R for R 0..32")


func test_radius_cells(t: TestCtx) -> void:
	t.eq(SimDisc.radius_cells(6144), 6, "6 cells")
	t.eq(SimDisc.radius_cells(7373), 7, "abilities 5.2.2 example: (7373 + 512) >> 10")
	t.eq(SimDisc.radius_cells(0), 1, "clamped up to 1")
	t.eq(SimDisc.radius_cells(100000), 32, "clamped down to 32")
