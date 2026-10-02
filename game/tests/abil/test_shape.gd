extends RefCounted
## AB-01: circle / capsule containment (abilities 10.1 test_shape).


func test_circle(t: TestCtx) -> void:
	t.check(SimShape.circle_contains(1000, 1000, 500, 1300, 1400), "3-4-5: exactly on the rim")
	t.check_false(SimShape.circle_contains(1000, 1000, 500, 1301, 1400), "one unit further is outside")


func test_capsule_horizontal_12_cells_half_width_2(t: TestCtx) -> void:
	var x0: int = 5000
	var x1: int = x0 + 12 * 1024
	var y: int = 8000
	var hw: int = 2 * 1024
	t.check(SimShape.capsule_contains(x0, y, x1, y, hw, x0 + 6000, y + hw), "on the side edge")
	t.check_false(SimShape.capsule_contains(x0, y, x1, y, hw, x0 + 6000, y + hw + 1), "1 unit beyond the side edge")
	t.check(SimShape.capsule_contains(x0, y, x1, y, hw, x1 + hw, y), "the end cap reaches half-width past the end")
	t.check_false(SimShape.capsule_contains(x0, y, x1, y, hw, x1 + hw + 1, y), "and not one unit more")
	t.check(SimShape.capsule_contains(x0, y, x1, y, hw, x0 - 1000, y + 1000), "round cap corner inside (dist 1414)")
	t.check_false(SimShape.capsule_contains(x0, y, x1, y, hw, x0 - 1600, y + 1600), "round cap corner outside (dist 2263)")


func test_capsule_diagonal(t: TestCtx) -> void:
	# 45 degrees: segment (0,0)-(8192, 8192); the point (4096 + d, 4096 - d) is d * sqrt(2) from the axis
	var hw: int = 2048
	t.check(SimShape.capsule_contains(0, 0, 8192, 8192, hw, 4096 + 1448, 4096 - 1448), "1448 * 1.4142 = 2047.7 inside")
	t.check_false(SimShape.capsule_contains(0, 0, 8192, 8192, hw, 4096 + 1451, 4096 - 1451), "1451 * 1.4142 = 2052 outside")
	t.check(SimShape.capsule_contains(0, 0, 0, 0, 500, 300, 400), "degenerate capsule = circle (rim)")


func test_segment_enters_circle(t: TestCtx) -> void:
	# circle at (0,0) r 1000; a shell flying along y = 1000 grazes it
	t.check(SimShape.segment_enters_circle(0, 0, 1000, -3000, 1000, 3000, 1000), "a grazing chord touches the rim")
	t.check_false(SimShape.segment_enters_circle(0, 0, 1000, -3000, 1001, 3000, 1001), "one unit higher misses")
	t.check_false(SimShape.segment_enters_circle(0, 0, 1000, 100, 100, 5000, 0), "a chord that starts inside never 'enters'")
	t.check(SimShape.segment_enters_circle(0, 0, 1000, -5000, 0, 0, 0), "a chord that ends inside enters")
	t.check_false(SimShape.segment_enters_circle(0, 0, 1000, -5000, 0, -2000, 0), "a segment that stops short does not")
