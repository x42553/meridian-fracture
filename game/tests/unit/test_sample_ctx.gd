extends RefCounted
## Sample 2/3: the assertion API itself. A TestCtx is driven directly, so failures can be provoked
## and inspected without failing this test (the real assertions here are on the inner context).


func test_passing_assertions_leave_no_failures(t: TestCtx) -> void:
	var inner: TestCtx = TestCtx.new()
	t.check(inner.check(true), "check(true) returns true")
	t.check(inner.eq(5, 5))
	t.check(inner.ne(5, 6))
	t.check(inner.near(1.0, 1.00001, 0.001))
	t.check(inner.not_null(inner))
	t.check(inner.is_null(null))
	t.check(inner.check_false(false))
	t.eq(inner.failures.size(), 0)
	t.eq(inner.assertions, 7)


func test_failing_assertions_are_recorded_with_location(t: TestCtx) -> void:
	var inner: TestCtx = TestCtx.new()
	t.check_false(inner.check(false, "boom"), "check(false) returns false")
	t.check_false(inner.eq(1, 2))
	t.check_false(inner.near(1.0, 2.0, 0.1))
	inner.fail("explicit")
	t.eq(inner.failures.size(), 4, "each failed assertion is recorded once")
	t.check(String(inner.failures[0]["msg"]).contains("boom"), "message is kept")
	t.eq(inner.failures[0]["file"], "res://tests/unit/test_sample_ctx.gd", "location is the caller, not test_ctx.gd")
	t.gt(int(inner.failures[0]["line"]), 0, "line number recorded")
	t.check(not inner.passed())


func test_eq_is_type_strict(t: TestCtx) -> void:
	var inner: TestCtx = TestCtx.new()
	# int 1 vs float 1.0 must NOT compare equal: that is how accidental float math is caught.
	t.check_false(inner.eq(1, 1.0))
	t.check(String(inner.failures[0]["msg"]).contains("type int vs float"))
	# String and StringName are interchangeable.
	t.check(inner.eq("abc", &"abc"))


func test_skip_and_notes(t: TestCtx) -> void:
	var inner: TestCtx = TestCtx.new()
	inner.skip("needs a GPU")
	inner.note("hello")
	t.check(inner.skipped)
	t.eq(inner.skip_reason, "needs a GPU")
	var expected: Array[String] = ["hello"]
	t.eq(inner.notes, expected)
