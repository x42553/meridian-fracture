class_name SndStats
extends RefCounted
## Counters of the voice pool and the bridge (played / culled / stolen / dropped per reason) and the numbers behind the
## `snd/*` Performance monitors.

var counters: Dictionary = {}
var starts: int = 0
var culls: int = 0


func add(name: StringName, n: int = 1) -> void:
	counters[name] = int(counters.get(name, 0)) + n
	if String(name).begins_with("cull_") or name == &"dropped":
		culls += n


func get_count(name: StringName) -> int:
	return int(counters.get(name, 0))


func started() -> void:
	starts += 1
	add(&"started")


func reset() -> void:
	counters.clear()
	starts = 0
	culls = 0
