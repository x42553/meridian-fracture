extends RefCounted
## Sample 1/3: the smallest useful test file. Copy this shape.
## Rules: extend RefCounted, name the file test_*.gd, every `func test_*(t: TestCtx)` is one test,
## a fresh instance is created per test (fields do not leak), setup()/teardown() are optional.

var _values: Array[int] = []


func setup(_t: TestCtx) -> void:
	_values = [3, 1, 2]


func test_integer_math_is_exact(t: TestCtx) -> void:
	t.eq(7 / 2, 3, "integer division truncates toward zero")
	t.eq(-7 / 2, -3, "and so does the negative case (C semantics, DR-5)")
	t.eq(-7 % 3, -1, "% keeps the dividend's sign")
	t.eq(1 << 10, 1024, "Fp.CELL is 1 << 10")


func test_fresh_instance_per_test(t: TestCtx) -> void:
	t.eq(_values.size(), 3, "setup() ran for this test")
	_values.append(99)
	t.eq(_values.size(), 4)


func test_no_state_leak_between_tests(t: TestCtx) -> void:
	# Would be 4 if the instance from test_fresh_instance_per_test were reused.
	t.eq(_values.size(), 3)
	_values.sort()
	var expected: Array[int] = [1, 2, 3]
	t.eq(_values, expected)


func test_near_and_ordering(t: TestCtx) -> void:
	t.near(0.1 + 0.2, 0.3, 0.000001)
	t.lt(1, 2)
	t.ge(2, 2)
	t.ne("a", "b")
