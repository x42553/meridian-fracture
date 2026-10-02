class_name TestSuite
extends RefCounted
## Test discovery + execution engine behind tests/runner.gd (`tools/gd test`).
##
## Conventions (see docs/spec/qa_tooling.md):
##  * A test file is `res://tests/**/test_*.gd`, a script that extends RefCounted.
##  * Every method named `test_*` is one test. It receives a TestCtx: `func test_x(t: TestCtx) -> void`.
##    (A test method that declares no parameter is allowed too.)
##  * A fresh instance of the script is created for EVERY test, so fields never leak between tests.
##    Optional `func setup(t: TestCtx)` runs before and `func teardown(t: TestCtx)` after each test
##    (parameter optional), even when the test failed.
##  * Legacy convention from docs/ARCHITECTURE.md section 11: a file without any `test_*` method but with
##    `func run(t: TestCtx)` is executed as one test named `run`.
##  * Directories named `fixtures` and `harness` are never scanned for tests.
## Test methods (and setup/teardown) may `await` (e.g. `await get_tree().process_frame` via
## `Engine.get_main_loop() as SceneTree`); the suite waits for them. An async test that never resumes is
## abandoned after `test_timeout_s` (default 30 s, `t.set_timeout(s)` per test) and reported as ERROR.
## A test that hangs synchronously (endless loop) cannot be interrupted: `tools/gd` kills the whole run.
## Failures and engine errors are recorded, never thrown; the run always finishes.
## `run_files()` is a coroutine: `await suite.run_files(files)`.

const TESTS_ROOT: String = "res://tests"
const SKIP_DIRS: Array[String] = ["fixtures", "harness"]
const RESULT_VERSION: int = 1

## Comma separated case-insensitive substrings; a test runs when its id contains any of them.
## The id is `<path relative to res://tests/>::<method>`, e.g. `unit/test_fp.gd::test_isqrt`.
var filters: PackedStringArray = PackedStringArray()
## Print `RUN  <id>` before each test (finds the test that hangs).
var trace: bool = false
## Stop after the first failing/erroring test.
var fail_fast: bool = false
## Wall-clock limit for tests that suspend on `await` (seconds). TestCtx.set_timeout() overrides it per test.
var test_timeout_s: float = 30.0
## True while the suite waits for a test that is suspended on an await (used by runner.gd's watchdog).
var suspended: bool = false
## Suppress per-test console output (used when a suite is driven from inside a test).
var quiet: bool = false
## Print only tests that did not pass (plus the summary); `tools/gd test -q`.
var quiet_pass: bool = false
## One Dictionary per test (see _make_result).
var results: Array[Dictionary] = []
var files_run: int = 0
var duration_usec: int = 0
## Test files that failed to load but were filtered out (reported as a note by print_summary()).
var broken_files: PackedStringArray = PackedStringArray()

var _logger: TestLogger = null
var _stop: bool = false


## Completion rendezvous between a test coroutine and the suite (inner class so no global name is needed).
class Waiter extends RefCounted:
	signal finished
	var completed: bool = false
	var timed_out: bool = false


## Sorted list of `res://` paths of all test files below `root`.
static func discover(root: String = TESTS_ROOT) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_collect(root, out)
	out.sort()
	return out


## Parses `--filter=a,b` style text into the lower-cased filter list.
static func parse_filters(csv: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for part: String in csv.split(",", false):
		var s: String = part.strip_edges().to_lower()
		if not s.is_empty():
			out.append(s)
	return out


## All test ids in `files` (loads each script once; nothing is executed). Used by `--list`.
func list_tests(files: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for path: String in files:
		var gd: GDScript = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as GDScript
		if gd == null or not gd.can_instantiate():
			out.append("%s::<load-error>" % _rel(path))
			continue
		var info: Dictionary = _scan(gd)
		for m: Dictionary in info["methods"]:
			var id: String = "%s::%s" % [_rel(path), m["name"]]
			if _matches(id):
				out.append(id)
	return out


## Runs every test in `files` (res:// paths). Results accumulate in `results`. Coroutine: `await` it.
func run_files(files: PackedStringArray) -> void:
	_logger = TestLogger.new()
	OS.add_logger(_logger)
	var t0: int = Time.get_ticks_usec()
	for path: String in files:
		if _stop:
			break
		await _run_file(path)
	duration_usec = Time.get_ticks_usec() - t0
	OS.remove_logger(_logger)
	_logger = null


## Number of results with the given status: "pass", "fail", "error" or "skip".
func count(status: String) -> int:
	var n: int = 0
	for r: Dictionary in results:
		if r["status"] == status:
			n += 1
	return n


## Total assertions evaluated across all tests.
func total_assertions() -> int:
	var n: int = 0
	for r: Dictionary in results:
		n += r["assertions"] as int
	return n


## 0 = everything passed, 1 = at least one failure/error, 2 = nothing ran (bad filter / no tests).
func exit_code(allow_empty: bool = false) -> int:
	if count("fail") > 0 or count("error") > 0:
		return 1
	if results.is_empty() and not allow_empty:
		return 2
	return 0


## Machine readable report, written to user://last_test_run.json by the runner.
func to_dict() -> Dictionary:
	var tests: Array[Dictionary] = []
	for r: Dictionary in results:
		tests.append(r)
	return {
		"version": RESULT_VERSION,
		"engine": Engine.get_version_info().get("string", ""),
		"filters": Array(filters),
		"duration_ms": snappedf(duration_usec / 1000.0, 0.01),
		"counts": {
			"files": files_run,
			"tests": results.size(),
			"passed": count("pass"),
			"failed": count("fail"),
			"errors": count("error"),
			"skipped": count("skip"),
			"assertions": total_assertions(),
		},
		"tests": tests,
	}


## Prints the closing summary block (and the list of failing ids).
func print_summary() -> void:
	var bad: PackedStringArray = PackedStringArray()
	for r: Dictionary in results:
		if r["status"] == "fail" or r["status"] == "error":
			bad.append("%s %s" % [(r["status"] as String).to_upper(), r["id"]])
	if not bad.is_empty():
		print("")
		print("FAILED TESTS (%d):" % bad.size())
		for line: String in bad:
			print("  " + line)
	if not broken_files.is_empty():
		print("")
		print("note: %d test file(s) did not compile and are not counted (filter active): %s" % [broken_files.size(), ", ".join(broken_files)])
	print("")
	print("== %d files, %d tests in %.2f s: %d passed, %d failed, %d errors, %d skipped (%d checks)" % [
		files_run, results.size(), duration_usec / 1000000.0,
		count("pass"), count("fail"), count("error"), count("skip"), total_assertions()])


static func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with(".") and not SKIP_DIRS.has(entry):
				_collect(dir_path.path_join(entry), out)
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			out.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


func _run_file(path: String) -> void:  # coroutine
	var rel: String = _rel(path)
	var mark: int = _logger.mark()
	var loaded: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	var load_errors: Array[Dictionary] = _logger.entries_since(mark)
	var gd: GDScript = loaded as GDScript
	if gd == null or not gd.can_instantiate():
		# A broken file is always reported when no filter is active or the filter names the file;
		# otherwise it is only remembered so print_summary() can mention it.
		if _matches(rel):
			var msgs: Array[String] = ["test script failed to load/compile"]
			msgs.append_array(_format_entries(load_errors))
			_finish(_make_result("%s::<load>" % rel, rel, "<load>", "error", 0, 0, [], msgs, [], ""))
		else:
			broken_files.append(path)
		return
	files_run += 1
	var info: Dictionary = _scan(gd)
	if info.has("error"):
		var problem: Array[String] = [info["error"]]
		problem.append_array(_format_entries(_logger.entries_since(mark)))
		_finish(_make_result("%s::<new>" % rel, rel, "<new>", "error", 0, 0, [], problem, [], ""))
		return
	for m: Dictionary in info["methods"]:
		if _stop:
			return
		await _run_test(gd, rel, m, info)


## Returns {methods: [{name, takes_ctx}], setup: int, teardown: int}; -1 = absent, 0 = no param, 1 = takes ctx.
func _scan(gd: GDScript) -> Dictionary:
	# gd.new() with missing _init() arguments raises a runtime error that would abort this function, so look first.
	for sm: Dictionary in gd.get_script_method_list():
		if sm["name"] == "_init" and (sm["args"] as Array).size() > (sm["default_args"] as Array).size():
			return {"methods": [], "setup": -1, "teardown": -1, "error": "test classes are created with new(): _init() must not require arguments"}
	var probe: Object = gd.new()
	var methods: Array[Dictionary] = []
	var setup_mode: int = -1
	var teardown_mode: int = -1
	var run_mode: int = -1
	for m: Dictionary in probe.get_method_list():
		var mname: String = m["name"]
		var mode: int = 1 if (m["args"] as Array).size() > 0 else 0
		if mname.begins_with("test_"):
			methods.append({"name": mname, "takes_ctx": mode == 1})
		elif mname == "setup":
			setup_mode = mode
		elif mname == "teardown":
			teardown_mode = mode
		elif mname == "run":
			run_mode = mode
	if methods.is_empty() and run_mode >= 0:
		methods.append({"name": "run", "takes_ctx": run_mode == 1})
	methods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["name"] as String) < (b["name"] as String))
	_release(probe)
	return {"methods": methods, "setup": setup_mode, "teardown": teardown_mode}


func _run_test(gd: GDScript, rel: String, method: Dictionary, info: Dictionary) -> void:  # coroutine
	var mname: String = method["name"]
	var id: String = "%s::%s" % [rel, mname]
	if not _matches(id):
		return
	if trace:
		print("RUN   ", id)
	var setup_mode: int = info["setup"]
	var teardown_mode: int = info["teardown"]
	var takes_ctx: bool = method["takes_ctx"]
	var t: TestCtx = TestCtx.new()
	var inst: Object = gd.new()
	var mark: int = _logger.mark()
	var t0: int = Time.get_ticks_usec()
	var waiter: Waiter = Waiter.new()
	# Fire and forget: runs synchronously up to the first real suspension, so ordinary tests finish
	# before this call returns and cost nothing extra.
	@warning_ignore("missing_await")
	_execute(inst, mname, t, takes_ctx, setup_mode, teardown_mode, waiter)
	if not waiter.completed:
		suspended = true
		@warning_ignore("missing_await")
		_watch(waiter, t, Time.get_ticks_msec())
		await waiter.finished
		suspended = false
	var usec: int = Time.get_ticks_usec() - t0
	if not waiter.timed_out:
		_release(inst)
	var errs: Array[Dictionary] = _logger.entries_since(mark)
	var err_msgs: Array[String] = []
	var status: String = "pass"
	if waiter.timed_out:
		status = "error"
		err_msgs.append("timed out after %.1f s: the test is suspended on an await that never resumed" % _limit(t))
	if errs.size() != t.expected_errors:
		status = "error"
		err_msgs.append_array(_format_entries(errs))
		if errs.size() < t.expected_errors:
			err_msgs.append("expected %d engine error(s) via expect_errors(), got %d" % [t.expected_errors, errs.size()])
	if not t.passed() and status != "error":
		status = "fail"
	if t.skipped and status == "pass":
		status = "skip"
	if status == "pass" and t.assertions == 0:
		t.note("no assertions were made")
	_finish(_make_result(id, rel, mname, status, usec, t.assertions, t.failures, err_msgs, t.notes, t.skip_reason))


## Runs setup, the test and teardown in order (each may await) and then signals completion.
func _execute(inst: Object, mname: String, t: TestCtx, takes_ctx: bool, setup_mode: int, teardown_mode: int, waiter: Waiter) -> void:
	if setup_mode >= 0:
		await _invoke(inst, "setup", t, setup_mode == 1)
	await _invoke(inst, mname, t, takes_ctx)
	if teardown_mode >= 0:
		await _invoke(inst, "teardown", t, teardown_mode == 1)
	waiter.completed = true
	waiter.finished.emit()


## Polls a suspended test so its deadline can honour a set_timeout() made after the test started.
func _watch(waiter: Waiter, t: TestCtx, started_msec: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	while not waiter.completed:
		await tree.create_timer(0.1).timeout
		if waiter.completed:
			return
		if (Time.get_ticks_msec() - started_msec) / 1000.0 > _limit(t):
			waiter.timed_out = true
			waiter.finished.emit()
			return


func _limit(t: TestCtx) -> float:
	return t.timeout_s if t.timeout_s > 0.0 else test_timeout_s


## Frees non-refcounted instances (a test file that extends Node/Object) so nothing leaks at exit.
static func _release(o: Object) -> void:
	if o != null and not (o is RefCounted):
		o.free()


func _invoke(inst: Object, method_name: String, t: TestCtx, takes_ctx: bool) -> void:  # coroutine
	if takes_ctx:
		await inst.call(method_name, t)
	else:
		await inst.call(method_name)


func _make_result(id: String, file: String, mname: String, status: String, usec: int, checks: int,
		failures: Array, errors: Array[String], notes: Array, skip_reason: String) -> Dictionary:
	return {
		"id": id,
		"file": "res://tests/" + file,
		"name": mname,
		"status": status,
		"ms": snappedf(usec / 1000.0, 0.01),
		"assertions": checks,
		"failures": failures.duplicate(),
		"errors": errors.duplicate(),
		"notes": notes.duplicate(),
		"skip_reason": skip_reason,
	}


func _finish(r: Dictionary) -> void:
	results.append(r)
	if r["status"] == "fail" or r["status"] == "error":
		if fail_fast:
			_stop = true
	if quiet or (quiet_pass and r["status"] == "pass"):
		return
	var status: String = r["status"]
	var label: String = status.to_upper()
	print("%-5s %s  (%.2f ms, %d checks)" % [label, r["id"], r["ms"], r["assertions"]])
	for f: Dictionary in r["failures"]:
		print("        %s:%d: %s" % [f["file"], f["line"], f["msg"]])
	for e: String in r["errors"]:
		print("        ! " + e)
	for n: String in r["notes"]:
		print("        note: " + n)
	if status == "skip":
		print("        skipped: " + (r["skip_reason"] as String))


func _format_entries(entries: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in entries:
		out.append("%s:%d: [%s] %s" % [e["file"], e["line"], e["kind"], e["message"]])
	return out


func _matches(id: String) -> bool:
	if filters.is_empty():
		return true
	var lower: String = id.to_lower()
	for f: String in filters:
		if lower.contains(f):
			return true
	return false


static func _rel(path: String) -> String:
	return path.trim_prefix(TESTS_ROOT + "/")
