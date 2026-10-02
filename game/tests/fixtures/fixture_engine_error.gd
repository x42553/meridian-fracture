extends RefCounted
## FIXTURE (never discovered). Raises a real engine error: calling a method on null aborts the test
## function with "SCRIPT ERROR: Invalid call", which the runner must attribute to the test and report
## as ERROR instead of silently passing. It prints a scary engine error on purpose, so it is only run
## by tools/py/tests/test_gd_cli.py via `tools/gd test --file res://tests/fixtures/fixture_engine_error.gd`.


func test_runtime_error_is_reported(t: TestCtx) -> void:
	var nothing: Variant = null
	t.check(true, "this assertion runs before the error")
	nothing.no_such_method()
	t.check(true, "never reached: the function was aborted")


func test_push_error_is_reported(_t: TestCtx) -> void:
	push_error("deliberate push_error from a test")


func test_declared_errors_are_accepted(t: TestCtx) -> void:
	t.expect_errors(1)
	push_error("declared push_error: allowed by expect_errors(1)")
