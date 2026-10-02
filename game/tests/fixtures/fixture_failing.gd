extends RefCounted
## FIXTURE, not a test file (its name does not start with test_, and tests/fixtures is never scanned).
## Contains one test per status. Driven by tests/unit/test_runner_detects_failure.gd and, for the
## end-to-end proof, by `tools/gd test --file res://tests/fixtures/fixture_failing.gd` (exits 1).


func test_passes(t: TestCtx) -> void:
	t.eq(1 + 1, 2)


func test_fails_check(t: TestCtx) -> void:
	t.check(false, "deliberate failure")


func test_fails_eq(t: TestCtx) -> void:
	t.eq(1 + 1, 3)


func test_skips(t: TestCtx) -> void:
	t.skip("fixture skip")


## Declares that one engine error will happen but raises none -> reported as an ERROR.
func test_expects_error_but_none_happens(t: TestCtx) -> void:
	t.expect_errors(1)
