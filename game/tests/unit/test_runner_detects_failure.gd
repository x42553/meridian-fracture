extends RefCounted
## Sample 3/3: proves the runner detects failure. It executes a deliberately failing fixture file
## (tests/fixtures/fixture_failing.gd, never discovered by normal runs) through a real TestSuite
## and asserts that failures are reported, counted, attributed and turned into a non-zero exit code.
## The end-to-end proof (a failing test makes `tools/gd test` exit 1) lives in tools/py/tests/test_gd_cli.py.

const FIXTURE: String = "res://tests/fixtures/fixture_failing.gd"


func _run_fixture() -> TestSuite:
	var suite: TestSuite = TestSuite.new()
	suite.quiet = true
	await suite.run_files(PackedStringArray([FIXTURE]))
	return suite


func test_failures_are_detected_and_counted(t: TestCtx) -> void:
	var suite: TestSuite = await _run_fixture()
	t.eq(suite.results.size(), 5, "fixture defines five tests")
	t.eq(suite.count("pass"), 1)
	t.eq(suite.count("fail"), 2)
	t.eq(suite.count("skip"), 1)
	t.eq(suite.count("error"), 1, "the setup-less test that expects an error but raises none")
	t.eq(suite.exit_code(), 1, "any failure means a non-zero exit code")


func test_failure_details_are_attributed(t: TestCtx) -> void:
	var suite: TestSuite = await _run_fixture()
	var by_name: Dictionary = {}
	for r: Dictionary in suite.results:
		by_name[r["name"]] = r
	var failing: Dictionary = by_name["test_fails_check"]
	t.eq(failing["status"], "fail")
	t.eq((failing["failures"] as Array).size(), 1)
	t.eq(failing["failures"][0]["file"], "res://tests/fixtures/fixture_failing.gd")
	t.gt(int(failing["failures"][0]["line"]), 0)
	t.check(String(failing["failures"][0]["msg"]).contains("deliberate"))
	var mismatch: Dictionary = by_name["test_fails_eq"]
	t.check(String(mismatch["failures"][0]["msg"]).contains("got 2, expected 3"))
	t.eq(by_name["test_passes"]["status"], "pass")
	t.eq(by_name["test_skips"]["status"], "skip")


func test_all_green_suite_exits_zero(t: TestCtx) -> void:
	var suite: TestSuite = TestSuite.new()
	suite.quiet = true
	suite.filters = TestSuite.parse_filters("test_passes")
	await suite.run_files(PackedStringArray([FIXTURE]))
	t.eq(suite.results.size(), 1)
	t.eq(suite.exit_code(), 0)


func test_empty_selection_is_not_success(t: TestCtx) -> void:
	var suite: TestSuite = TestSuite.new()
	suite.quiet = true
	suite.filters = TestSuite.parse_filters("matches_nothing_at_all")
	await suite.run_files(PackedStringArray([FIXTURE]))
	t.eq(suite.results.size(), 0)
	t.eq(suite.exit_code(), 2, "zero tests must not look like a pass")
	t.eq(suite.exit_code(true), 0, "unless the caller allows an empty run")


func test_filter_is_case_insensitive_and_or(t: TestCtx) -> void:
	var suite: TestSuite = TestSuite.new()
	suite.quiet = true
	suite.filters = TestSuite.parse_filters("TEST_PASSES, test_skips")
	await suite.run_files(PackedStringArray([FIXTURE]))
	t.eq(suite.results.size(), 2)


func test_legacy_run_convention_is_supported(t: TestCtx) -> void:
	var suite: TestSuite = TestSuite.new()
	suite.quiet = true
	await suite.run_files(PackedStringArray(["res://tests/fixtures/fixture_legacy_run.gd"]))
	t.eq(suite.results.size(), 1)
	t.eq(suite.results[0]["name"], "run")
	t.eq(suite.results[0]["status"], "pass")


func test_async_tests_are_awaited_and_hung_ones_time_out(t: TestCtx) -> void:
	t.set_timeout(20.0)
	var suite: TestSuite = TestSuite.new()
	suite.quiet = true
	await suite.run_files(PackedStringArray(["res://tests/fixtures/fixture_async.gd"]))
	var by_name: Dictionary = {}
	for r: Dictionary in suite.results:
		by_name[r["name"]] = r
	t.eq(suite.results.size(), 2)
	t.eq(by_name["test_awaits_frames"]["status"], "pass", "awaiting frames in setup/test/teardown works")
	t.eq(by_name["test_never_resumes"]["status"], "error", "a test suspended forever is abandoned, not hung on")
	t.check(String(by_name["test_never_resumes"]["errors"][0]).contains("timed out"))
	t.eq(suite.exit_code(), 1)


func test_uninstantiable_test_class_is_an_error_not_a_crash(t: TestCtx) -> void:
	var suite: TestSuite = TestSuite.new()
	suite.quiet = true
	await suite.run_files(PackedStringArray(["res://tests/fixtures/fixture_needs_args.gd"]))
	t.eq(suite.results.size(), 1)
	t.eq(suite.results[0]["status"], "error")
	t.check(String(suite.results[0]["errors"][0]).contains("_init() must not require arguments"))
