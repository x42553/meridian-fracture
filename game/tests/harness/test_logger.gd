class_name TestLogger
extends Logger
## Records engine errors (script runtime errors, push_error, parse errors) raised while tests or
## the script checker run, so they can be attributed to a test or file instead of scrolling by.
## Install with `OS.add_logger(logger)`; warnings are ignored.

## Each entry: {kind: String, file: String, line: int, message: String, function: String}.
## kind is "script" (GDScript runtime/parse error), "shader" or "engine" (push_error and C++ errors).
var entries: Array[Dictionary] = []

var _mutex: Mutex = Mutex.new()


## Number of entries recorded so far; pass to entries_since() to get what happened afterwards.
func mark() -> int:
	_mutex.lock()
	var n: int = entries.size()
	_mutex.unlock()
	return n


## Entries recorded after `mark_value` (a value returned by mark()).
func entries_since(mark_value: int) -> Array[Dictionary]:
	_mutex.lock()
	var out: Array[Dictionary] = []
	for i: int in range(mark_value, entries.size()):
		out.append(entries[i])
	_mutex.unlock()
	return out


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == Logger.ERROR_TYPE_WARNING:
		return
	var kind: String = "engine"
	if error_type == Logger.ERROR_TYPE_SCRIPT:
		kind = "script"
	elif error_type == Logger.ERROR_TYPE_SHADER:
		kind = "shader"
	var where_file: String = file
	var where_line: int = line
	# push_error() and C++ errors report the engine source location; the interesting location is
	# the innermost GDScript frame.
	if not where_file.begins_with("res://") and not script_backtraces.is_empty():
		var bt: ScriptBacktrace = script_backtraces[0]
		if bt != null and bt.get_frame_count() > 0:
			where_file = bt.get_frame_file(0)
			where_line = bt.get_frame_line(0)
	var message: String = code if rationale.is_empty() else code + " (" + rationale + ")"
	_mutex.lock()
	entries.append({"kind": kind, "file": where_file, "line": where_line, "message": message, "function": function})
	_mutex.unlock()
