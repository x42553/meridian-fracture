extends RefCounted
## `AppLogger` and `AppLogSink` (ui.md 10.2 `test_ui_logger`, 5.20.2): thread safety, rate limits, storm, no re-entry.

var _clock: int = 0


func _now() -> int:
	return _clock


func _logger() -> AppLogger:
	var l: AppLogger = AppLogger.new()
	l.clock = _now
	_clock = 1000
	Log.ring = PackedStringArray()
	return l


func _err(l: AppLogger, code: String, line: int = 10, type: int = 0, bt: Array[ScriptBacktrace] = []) -> void:
	l._log_error("fn", "src/x.gd", line, code, "", false, type, bt)


func test_error_and_warning_types_reach_the_ring(t: TestCtx) -> void:
	var l: AppLogger = _logger()
	_err(l, "first", 10, Logger.ERROR_TYPE_ERROR)
	_err(l, "second", 11, Logger.ERROR_TYPE_WARNING)
	_err(l, "third", 12, Logger.ERROR_TYPE_SCRIPT)
	t.eq(Log.ring.size(), 3)
	t.check(Log.ring[0].begins_with("ERROR") and Log.ring[0].contains("first"))
	t.check(Log.ring[1].begins_with("WARN") and Log.ring[1].contains("second"))
	t.eq(l.errors_total, 2)
	t.eq(l.warnings_total, 1)
	var recent: Array[Dictionary] = l.recent_errors()
	t.eq(recent.size(), 3)
	t.eq(int(recent[1]["type"]), Logger.ERROR_TYPE_WARNING)
	t.eq(l.tail(2).size(), 2)


func test_identical_errors_are_rate_limited(t: TestCtx) -> void:
	var l: AppLogger = _logger()
	for i: int in 250:
		_err(l, "same")
	t.eq(Log.ring.size(), 3, "250 identical errors log 1, 100 and 200")
	t.check(Log.ring[1].contains("(x100)") and Log.ring[2].contains("(x200)"), "with counts")
	_err(l, "same", 99)
	t.eq(Log.ring.size(), 4, "another location is its own entry")


func test_storm_flag_and_toast(t: TestCtx) -> void:
	var l: AppLogger = _logger()
	var toasts: Array = []
	l.toast_callback = func(text: String, severity: int) -> void: toasts.append([text, severity])
	for i: int in 49:
		_clock += 50
		_err(l, "e%d" % i, i)
	t.check(not l.storm(), "49 errors do not make a storm")
	_clock += 50
	_err(l, "e50", 50)
	t.check(l.storm(), "50 errors within 5 s do")
	await Engine.get_main_loop().process_frame
	t.eq(toasts.size(), 1, "exactly one toast")
	_clock += 6000
	l.clear_storm()
	t.check(not l.storm())
	var l2: AppLogger = _logger()
	for i: int in 60:
		_clock += 200
		_err(l2, "slow%d" % i, i)
	t.check(not l2.storm(), "60 errors spread over 12 s are not a storm")


func test_empty_backtrace_is_tolerated(t: TestCtx) -> void:
	var l: AppLogger = _logger()
	l._log_error("fn", "src/y.gd", 3, "no backtrace", "rationale text", false, Logger.ERROR_TYPE_SCRIPT, [] as Array[ScriptBacktrace])
	t.eq(Log.ring.size(), 1)
	t.check(Log.ring[0].contains("src/y.gd:3"), "location falls back to file:line")
	t.check(Log.ring[0].contains("rationale text"), "the rationale is the message when present")


func test_log_error_never_prints(t: TestCtx) -> void:
	var l: AppLogger = _logger()
	var printed: Array = []
	var old: Callable = Log.sink
	Log.sink = func(_lv: int, _tag: String, msg: String) -> void: printed.append(msg)
	_err(l, "quiet")
	l._log_message("some stderr text", true)
	Log.sink = old
	t.eq(printed.size(), 0, "nothing went through Log (no re-entry)")
	l._log_message("[E] 12 [net] echo of our own line", true)
	l._log_message("plain stdout", false)
	var echoes: int = 0
	for line: String in Log.ring:
		echoes += 1 if line.contains("echo of our own line") or line.contains("plain stdout") else 0
	t.eq(echoes, 0, "own-prefix and stdout lines are ignored")
	t.check(Log.ring.size() == 2 and Log.ring[1].contains("some stderr text"))


func test_100_errors_from_a_worker_thread(t: TestCtx) -> void:
	var l: AppLogger = _logger()
	var worker: Callable = func() -> void:
		for i: int in 100:
			l._log_error("wf", "src/worker.gd", i, "worker-%d" % i, "", false, Logger.ERROR_TYPE_ERROR, [] as Array[ScriptBacktrace])
	var th: Thread = Thread.new()
	th.start(worker)
	th.wait_to_finish()
	var got: int = 0
	for line: String in Log.ring:
		got += 1 if line.contains("worker-") else 0
	t.eq(got, 100, "all 100 worker-thread errors reached Log.ring")
	t.eq(l.errors_total, 100)
	t.check(Log.ring.size() <= Log.RING_SIZE)
	await Engine.get_main_loop().process_frame


## Two threads log at once.
func test_two_threads_do_not_lose_entries(t: TestCtx) -> void:
	var l: AppLogger = _logger()
	var mk: Callable = func(tag: String) -> Callable:
		return func() -> void:
			for i: int in 60:
				l._log_error("f", "src/%s.gd" % tag, i, "%s-%d" % [tag, i], "", false, Logger.ERROR_TYPE_ERROR, [] as Array[ScriptBacktrace])
	var a: Thread = Thread.new()
	var b: Thread = Thread.new()
	a.start(mk.call("ta") as Callable)
	b.start(mk.call("tb") as Callable)
	a.wait_to_finish()
	b.wait_to_finish()
	t.eq(l.errors_total, 120)
	t.eq(Log.ring.size(), 120, "no lost updates of the shared ring")
	await Engine.get_main_loop().process_frame


## A real engine error reaches an installed logger with the script frame as its location.
func test_real_push_error_is_captured(t: TestCtx) -> void:
	t.expect_errors(1)
	var l: AppLogger = _logger()
	l.install()
	push_error("boom-from-test")
	l.uninstall()
	var found: String = ""
	for line: String in Log.ring:
		if line.contains("boom-from-test"):
			found = line
	t.check(not found.is_empty(), "push_error captured")
	t.check(found.contains("test_ui_logger"), "the location is the script frame: " + found)
	await Engine.get_main_loop().process_frame


func test_sink_format_and_rate_limit(t: TestCtx) -> void:
	var s: AppLogSink = AppLogSink.new()
	var lines: PackedStringArray = PackedStringArray()
	s.out = func(line: String) -> void: lines.append(line)
	s.clock = _now
	_clock = 1234
	s.emit(Log.Level.ERROR, "net", "text")
	t.eq(lines[0], "[E] 1234 [net] text")
	s.emit(Log.Level.WARN, "net", "w")
	s.emit(Log.Level.INFO, "sim", "i")
	s.emit(Log.Level.DEBUG, "sim", "d")
	t.eq(lines[1], "[W] 1234 [net] w")
	t.eq(lines[2], "[I] 1234 [sim] i")
	t.eq(lines[3], "[D] 1234 [sim] d")
	lines.clear()
	_clock = 5000
	for i: int in 25:
		s.emit(Log.Level.INFO, "spam", "line %d" % i)
	t.eq(lines.size(), 20, "20 lines per second per tag")
	s.emit(Log.Level.INFO, "other", "x")
	t.eq(lines.size(), 21, "other tags are independent")
	_clock = 6100
	s.emit(Log.Level.INFO, "spam", "after")
	t.check(lines[lines.size() - 1].ends_with("after (+5 suppressed)"), "the next window's line carries the count: " + lines[lines.size() - 1])
	s.emit(Log.Level.INFO, "spam", "again")
	t.check(not lines[lines.size() - 1].contains("suppressed"), "the counter is reported once")
	t.eq(s.lines_suppressed, 5)


func test_sink_installs_into_log(t: TestCtx) -> void:
	var old: Callable = Log.sink
	var s: AppLogSink = AppLogSink.new()
	var lines: PackedStringArray = PackedStringArray()
	s.out = func(line: String) -> void: lines.append(line)
	s.install()
	Log.info("app", "through the facade")
	s.uninstall()
	t.eq(lines.size(), 1)
	t.check(lines[0].contains("[I]") and lines[0].contains("[app] through the facade"))
	t.check(not Log.sink.is_valid(), "uninstall clears the sink")
	Log.sink = old
