class_name AiTelemetry
extends RefCounted
## Telemetry emit helper (ai.md 2.1 / 6.3). Codes are AiTypes.Tele; the sink is `func(pid, code, a, b, tick)` (harness or
## log consumer, may be invalid). "First" events fire once per player (`first_tick`), the rest every call.

var pid: int = 0
var sink: Callable = Callable()
var first_tick: Dictionary = {}  ## code -> tick of the first emission
var counts: Dictionary = {}  ## code -> number of emissions


func _init(p_pid: int = 0, p_sink: Callable = Callable()) -> void:
	pid = p_pid
	sink = p_sink


func emit(code: int, a: int, b: int, tick: int) -> void:
	if not first_tick.has(code):
		first_tick[code] = tick
	counts[code] = int(counts.get(code, 0)) + 1
	if sink.is_valid():
		sink.call(pid, code, a, b, tick)


## Emits only the first time `code` occurs.
func emit_first(code: int, a: int, b: int, tick: int) -> void:
	if not first_tick.has(code):
		emit(code, a, b, tick)


func count_of(code: int) -> int:
	return int(counts.get(code, 0))


## Callable-friendly entry with the AiCommandBuilder telemetry signature (pid, code, a, b, tick).
func emit_cb(_pid: int, code: int, a: int, b: int, tick: int) -> void:
	emit(code, a, b, tick)
