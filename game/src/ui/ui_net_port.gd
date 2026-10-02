class_name UiNetPort
extends RefCounted
## Command submission seam (ui.md 3.2.3). `cmd` is the int array built by `UiCmdCodec` / `SimCmd`
## ([op, fields..., ids...], no pid: net stamps it from the connection). Adapters: `UiNetPortSession` (NetSession),
## `UiNetPortRecorder` (tests), `UiNetPortNull` (observers, replays, showcase).


func _ni(fn: String) -> void:
	push_error("NOT IMPLEMENTED: UiNetPort.%s" % fn)


## False = refused (not playing / larger than 1024 ints / queue full / observer). Never blocks.
func submit(_cmd: PackedInt32Array) -> bool:
	_ni("submit")
	return false


func can_submit() -> bool:
	_ni("can_submit")
	return false


func local_pid() -> int:
	return -1


func tick() -> int:
	return 0


func is_observer() -> bool:
	return false


## Commands queued locally and not yet sent (<= 256).
func pending_count() -> int:
	return 0


## NetProtocol.PauseError (0 = sent).
func request_pause(_want_paused: bool) -> int:
	return 0


## NetSession.surrender().
func surrender() -> bool:
	return false


func send_chat(_text: String, _team_only: bool) -> void:
	pass


func send_map_ping(_cell_x: int, _cell_y: int) -> void:
	pass
