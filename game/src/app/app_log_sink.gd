class_name AppLogSink
extends RefCounted
## The `Log.sink` formatter (ui.md 5.20.2, QA-XR-23): `[E|W|I|D] <ms since start> [tag] message`, at most 20 lines per
## second per tag (the 21st and later are suppressed and the next line of that tag carries `(+N suppressed)`), then it
## prints. The one place in `src/app` that calls `print`. Thread-safe (the net module may log from its own thread).

const MAX_PER_SECOND: int = 20
const LETTERS: PackedStringArray = ["D", "I", "W", "E"]

## `func() -> int` milliseconds since start (injectable for tests).
var clock: Callable = Callable()
## `func(line: String)` where finished lines go (default: print); tests capture here.
var out: Callable = Callable()
## Every line accepted for output since `install` (bounded, for crash reports of a sink-less run).
var lines_emitted: int = 0
var lines_suppressed: int = 0

var _mutex: Mutex = Mutex.new()
var _tags: Dictionary = {}


func install() -> void:
	Log.sink = Callable(self, "emit")


func uninstall() -> void:
	if Log.sink.get_object() == self:
		Log.sink = Callable()


func now_ms() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()


func emit(level: int, tag: String, msg: String) -> void:
	var t: int = now_ms()
	_mutex.lock()
	var st: Dictionary = _tags.get(tag, {"start": t, "count": 0, "dropped": 0}) as Dictionary
	if t - int(st["start"]) >= 1000 or t < int(st["start"]):
		st["start"] = t
		st["count"] = 0
	var suffix: String = ""
	var accepted: bool = int(st["count"]) < MAX_PER_SECOND
	if accepted:
		st["count"] = int(st["count"]) + 1
		if int(st["dropped"]) > 0:
			suffix = " (+%d suppressed)" % int(st["dropped"])
			st["dropped"] = 0
		lines_emitted += 1
	else:
		st["dropped"] = int(st["dropped"]) + 1
		lines_suppressed += 1
	_tags[tag] = st
	_mutex.unlock()
	if not accepted:
		return
	var line: String = "[%s] %d [%s] %s%s" % [LETTERS[clampi(level, 0, 3)], t, tag, msg, suffix]
	if out.is_valid():
		out.call(line)
	else:
		# lint-allow: L006 app log sink, the one console writer of src/app
		print(line)
