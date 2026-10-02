class_name UiAudioPortRecorder
extends UiAudioPort
## Test adapter: records `[name, args]` for every call. `names()` lists the call names in order.

var calls: Array = []
var captions: bool = false


func ui(id: StringName, gain_db: float = 0.0) -> void:
	calls.append([&"ui", [id, gain_db]])


func announce(line: StringName) -> bool:
	calls.append([&"announce", [line]])
	return true


func music_state(state: StringName) -> void:
	calls.append([&"music_state", [state]])


func unit_selected(def_idx: int, is_structure: bool, count: int) -> void:
	calls.append([&"unit_selected", [def_idx, is_structure, count]])


func unit_ordered(order: int, def_idx: int) -> void:
	calls.append([&"unit_ordered", [order, def_idx]])


func order_denied(def_idx: int, is_structure: bool = false) -> void:
	calls.append([&"order_denied", [def_idx, is_structure]])


func set_time_scale(x: float) -> void:
	calls.append([&"set_time_scale", [x]])


func captions_enabled() -> bool:
	return captions


func names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for c: Array in calls:
		out.append(String(c[0]))
	return out


## Number of recorded calls of `name`.
func count_of(name: StringName) -> int:
	var n: int = 0
	for c: Array in calls:
		if c[0] == name:
			n += 1
	return n


## Args of the last call of `name` (empty when none).
func last_args(name: StringName) -> Array:
	for i: int in range(calls.size() - 1, -1, -1):
		var c: Array = calls[i]
		if c[0] == name:
			return c[1]
	return []


func clear() -> void:
	calls.clear()
