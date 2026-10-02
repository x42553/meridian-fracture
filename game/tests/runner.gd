extends SceneTree
## Test runner entry point. `tools/gd test [filter]` runs:
##   godot --headless --path game --script res://tests/runner.gd -- [args]
##
## User args (everything after `--`):
##   --filter=<a,b>       case-insensitive substrings of `<file>::<method>` ids (OR)
##   --file=<res://x.gd>  run exactly this file (repeatable), bypassing discovery; the file name need
##                        not start with test_ (used for fixtures)
##   --dir=<res://dir>    discover `test_*.gd` below this directory instead of res://tests
##   --results=<path>     additionally write the JSON report to this filesystem path
##   --list               print the ids of the selected tests and exit 0 without running them
##   --trace              print `RUN <id>` before every test (finds a hanging test)
##   --fail-fast          stop after the first failing test
##   --quiet              do not print passing tests (failures, errors, skips and the summary still appear)
##   --test-timeout=<s>   limit for tests that await (default 30 s); a hung synchronous test needs tools/gd's kill
##   --allow-empty        exit 0 even when no test matched
## Exit code: 0 all passed, 1 failures/errors, 2 nothing ran or the runner itself broke.
## The JSON report always goes to user://last_test_run.json (written atomically; concurrent runs
## overwrite each other, so parallel callers should pass --results).

const LAST_RUN_PATH: String = "user://last_test_run.json"

var _finished: bool = false
var _suite: TestSuite = null


func _initialize() -> void:
	# GDScript aborts a function at its first runtime error. If that happens inside _initialize the
	# scene tree would idle forever, so make the first frame after it a hard stop.
	process_frame.connect(_on_first_frame, CONNECT_ONE_SHOT)
	var code: int = await _run(OS.get_cmdline_user_args())
	_finished = true
	quit(code)


func _on_first_frame() -> void:
	# a suite that is legitimately waiting for an async test is not an abort
	if _finished or (_suite != null and _suite.suspended):
		return
	printerr("RUNNER ABORTED: the test runner hit an internal error before finishing (see SCRIPT ERROR above)")
	quit(2)


func _run(args: PackedStringArray) -> int:  # coroutine
	var suite: TestSuite = TestSuite.new()
	_suite = suite
	var files: PackedStringArray = PackedStringArray()
	var explicit_files: PackedStringArray = PackedStringArray()
	var tests_root: String = TestSuite.TESTS_ROOT
	var results_path: String = ""
	var list_only: bool = false
	var allow_empty: bool = false
	for arg: String in args:
		if arg.begins_with("--filter="):
			suite.filters = TestSuite.parse_filters(arg.substr("--filter=".length()))
		elif arg.begins_with("--file="):
			explicit_files.append(arg.substr("--file=".length()))
		elif arg.begins_with("--dir="):
			tests_root = arg.substr("--dir=".length())
		elif arg.begins_with("--results="):
			results_path = arg.substr("--results=".length())
		elif arg == "--list":
			list_only = true
		elif arg == "--trace":
			suite.trace = true
		elif arg == "--fail-fast":
			suite.fail_fast = true
		elif arg == "--quiet":
			suite.quiet_pass = true
		elif arg.begins_with("--test-timeout="):
			suite.test_timeout_s = arg.substr("--test-timeout=".length()).to_float()
		elif arg == "--allow-empty":
			allow_empty = true
		else:
			printerr("runner: unknown argument '%s'" % arg)
			return 2
	files = explicit_files if not explicit_files.is_empty() else TestSuite.discover(tests_root)
	if list_only:
		for id: String in suite.list_tests(files):
			print(id)
		return 0
	await suite.run_files(files)
	suite.print_summary()
	var report: Dictionary = suite.to_dict()
	_write_json(LAST_RUN_PATH, report)
	if not results_path.is_empty():
		_write_json(results_path, report)
	var code: int = suite.exit_code(allow_empty)
	if code == 2:
		printerr("runner: no tests matched (files scanned: %d, filters: %s)" % [files.size(), ",".join(suite.filters)])
	return code


## Writes to a temp file and then renames it into place, so readers never see a half-written report. Godot's
## rename is remove-then-rename (not POSIX rename(2)), so when several runs replace the shared user:// report
## at once the loser's rename can fail; it then cleans up its temp file and moves on (last writer wins).
func _write_json(path: String, data: Dictionary) -> void:
	var tmp: String = "%s.%d.tmp" % [path, OS.get_process_id()]
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		printerr("runner: cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	var err: Error = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(tmp)
