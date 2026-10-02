extends RefCounted
## FIXTURE: async tests. `await` inside tests, setup and teardown is supported; a test that never resumes
## is abandoned after its timeout and reported as ERROR. Driven by tests/unit/test_runner_detects_failure.gd.

signal never_emitted

var _log: Array[String] = []


func setup(_t: TestCtx) -> void:
	await _next_frame()
	_log.append("setup")


func teardown(_t: TestCtx) -> void:
	await _next_frame()


func test_awaits_frames(t: TestCtx) -> void:
	var before: int = Engine.get_process_frames()
	await _next_frame()
	await _next_frame()
	t.gt(Engine.get_process_frames(), before, "frames advanced while awaiting")
	t.eq(_log, ["setup"] as Array[String])


func test_never_resumes(t: TestCtx) -> void:
	t.set_timeout(0.5)
	await _never()
	t.fail("unreachable")


func _next_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _never() -> void:
	await never_emitted
