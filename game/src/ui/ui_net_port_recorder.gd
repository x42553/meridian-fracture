class_name UiNetPortRecorder
extends UiNetPort
## Test adapter: appends every submitted array to `sent` (compare `UiCmdCodec.describe(cmd)` strings and raw ints).
## `accept` = false makes it refuse like a stalled or observer session; `tick_value` / `pid` are settable.

var sent: Array[PackedInt32Array] = []
var chats: Array[String] = []
var pings: Array[Vector2i] = []
var accept: bool = true
var tick_value: int = 0
var pid: int = 0
var observer: bool = false
var max_ints: int = 1024


func submit(cmd: PackedInt32Array) -> bool:
	if not accept or observer or cmd.size() > max_ints or cmd.is_empty():
		return false
	sent.append(cmd.duplicate())
	return true


func can_submit() -> bool:
	return accept and not observer


func local_pid() -> int:
	return -1 if observer else pid


func tick() -> int:
	return tick_value


func is_observer() -> bool:
	return observer


func pending_count() -> int:
	return sent.size()


func send_chat(text: String, team_only: bool) -> void:
	chats.append(("[team] " if team_only else "") + text)


func send_map_ping(cell_x: int, cell_y: int) -> void:
	pings.append(Vector2i(cell_x, cell_y))


## describe() text of every sent command (needs SimCmd).
func described() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for c: PackedInt32Array in sent:
		out.append(UiCmdCodec.describe(c))
	return out


func clear() -> void:
	sent.clear()
	chats.clear()
	pings.clear()
