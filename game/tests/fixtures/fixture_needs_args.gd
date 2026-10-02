extends RefCounted
## FIXTURE: a test class whose _init() requires an argument cannot be created by the runner (it uses new());
## it must be reported as ERROR instead of aborting the run. Driven by tests/unit/test_runner_detects_failure.gd.


func _init(_required: int) -> void:
	pass


func test_never_runs(t: TestCtx) -> void:
	t.fail("unreachable")
