extends RefCounted
## FIXTURE: the docs/ARCHITECTURE.md section 11 test convention `func run(t: TestCtx)`, which the runner
## accepts for files that define no test_* method. Driven by tests/unit/test_runner_detects_failure.gd.


func run(t: TestCtx) -> void:
	t.eq(2 * 21, 42)
