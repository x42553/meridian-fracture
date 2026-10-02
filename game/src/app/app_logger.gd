class_name AppLogger
extends Logger
## `Logger` subclass (ui.md 5.20.2): mirrors engine errors and warnings into `Log.ring`, rate-limits identical entries,
## detects error storms and hands UI callbacks to the main thread. `_log_error` / `_log_message` may run on ANY thread, so
## every entry point takes the mutex; nothing here prints (re-entry). Release builds have no script backtraces; an empty
## array is tolerated.

## `{type, where, text, count}`; emitted deferred on the main thread for entries that were recorded (not rate-limited).
signal error_logged(entry: Dictionary)

const STORM_COUNT: int = 50
const STORM_WINDOW_MS: int = 5000
const REPEAT_EVERY: int = 100
const SCRIPT_TOAST_GAP_MS: int = 30000
const MAX_RECENT: int = 64
## Prefixes of the lines `AppLogSink` prints; `_log_message` ignores them (no echo of our own output).
const APP_PREFIXES: PackedStringArray = ["[E] ", "[W] ", "[I] ", "[D] "]

## `func() -> int` milliseconds (injectable clock for tests).
var clock: Callable = Callable()
## `func(text: String, severity: int)` called on the main thread for the storm toast and script-error toasts.
var toast_callback: Callable = Callable()

var errors_total: int = 0
## Engine "caller thread can't call" errors seen (any thread); see `_note_thread_guard`.
var thread_guard_hits: int = 0
var warnings_total: int = 0

var _mutex: Mutex = Mutex.new()
var _counts: Dictionary = {}
var _recent: Array[Dictionary] = []
var _stamps: PackedInt64Array = PackedInt64Array()
var _storm: bool = false
var _storm_toasted: bool = false
var _last_script_toast: Dictionary = {}
var _installed: bool = false


func install() -> void:
	if not _installed:
		_installed = true
		OS.add_logger(self)


func uninstall() -> void:
	if _installed:
		_installed = false
		OS.remove_logger(self)


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var where: String = "%s:%d @ %s" % [file, line, function]
	if not script_backtraces.is_empty() and script_backtraces[0] != null and not script_backtraces[0].is_empty():
		where = _top_frame(script_backtraces[0])
	var text: String = rationale if not rationale.is_empty() else code
	if text.contains("caller thread can't call"):
		_note_thread_guard(where)
	var key: String = "%d|%s|%d|%s" % [error_type, file, line, code]
	var now: int = _now()
	var record: bool = false
	var count: int = 0
	var toast_text: String = ""
	_mutex.lock()
	if error_type == Logger.ERROR_TYPE_WARNING:
		warnings_total += 1
	else:
		errors_total += 1
		_stamps.append(now)
		while _stamps.size() > 0 and now - _stamps[0] > STORM_WINDOW_MS:
			_stamps.remove_at(0)
		if _stamps.size() >= STORM_COUNT:
			_storm = true
			if not _storm_toasted:
				_storm_toasted = true
				toast_text = "Many errors are occurring. The log has details."
	count = int(_counts.get(key, 0)) + 1
	_counts[key] = count
	record = count == 1 or count % REPEAT_EVERY == 0
	var entry: Dictionary = {}
	if record:
		var label: String = "ERROR" if error_type != Logger.ERROR_TYPE_WARNING else "WARN"
		var line_text: String = "%s [engine] %s (%s)%s" % [label, text, where, "" if count == 1 else " (x%d)" % count]
		_ring_push(line_text)
		entry = {"type": error_type, "where": where, "text": text, "count": count}
		_recent.append(entry)
		if _recent.size() > MAX_RECENT:
			_recent.remove_at(0)
		if error_type == Logger.ERROR_TYPE_SCRIPT and toast_text.is_empty():
			var last: int = int(_last_script_toast.get(where, -SCRIPT_TOAST_GAP_MS))
			if OS.is_debug_build() or now - last >= SCRIPT_TOAST_GAP_MS:
				_last_script_toast[where] = now
				toast_text = "Script error: %s" % text
	_mutex.unlock()
	if not entry.is_empty():
		error_logged.emit.call_deferred(entry)
	if not toast_text.is_empty() and toast_callback.is_valid():
		toast_callback.call_deferred(toast_text, 2)


## Engine thread-guard errors ("The caller thread can't call ...") name no thread: this records which one it was (`user://thread_guard.log`, one line per
## hit: caller thread id, main thread id, worker-pool thread flag, innermost script frame) so a stress run can tell a worker from a stray main-thread flag.
func _note_thread_guard(where: String) -> void:
	thread_guard_hits += 1
	var f: FileAccess = FileAccess.open("user://thread_guard.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://thread_guard.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s | caller=%d main=%d is_main=%s | %s" % [Time.get_datetime_string_from_system(), OS.get_thread_caller_id(), OS.get_main_thread_id(),
		str(OS.get_thread_caller_id() == OS.get_main_thread_id()), where])
	f.close()


## "fn (res://file.gd:12)" of the innermost frame (the formatted backtrace starts with a header line, then `[0] ...`).
static func _top_frame(bt: ScriptBacktrace) -> String:
	for line: String in bt.format().split("\n"):
		var l: String = line.strip_edges()
		if l.begins_with("[0]"):
			return l.substr(3).strip_edges()
	return bt.format().strip_edges().split("\n")[0].strip_edges()


func _log_message(message: String, error: bool) -> void:
	if not error:
		return
	for p: String in APP_PREFIXES:
		if message.begins_with(p):
			return
	_mutex.lock()
	_ring_push("ERROR [stderr] " + message.strip_edges())
	_mutex.unlock()


## Appends to `Log.ring` (bounded). Caller holds the mutex.
func _ring_push(line: String) -> void:
	Log.ring_push(line)


## The newest `n` lines of `Log.ring`.
func tail(n: int = 60) -> PackedStringArray:
	return Log.ring_tail(n)


func recent_errors() -> Array[Dictionary]:
	_mutex.lock()
	var out: Array[Dictionary] = _recent.duplicate()
	_mutex.unlock()
	return out


## At least 50 errors within the last 5 seconds (it stays set until `clear_storm`).
func storm() -> bool:
	return _storm


func clear_storm() -> void:
	_mutex.lock()
	_storm = false
	_storm_toasted = false
	_stamps.clear()
	_mutex.unlock()
