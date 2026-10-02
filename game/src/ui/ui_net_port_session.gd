class_name UiNetPortSession
extends UiNetPort
## Forwards to a `NetSession` (net.md 6.3). The session is held as an Object and called by name: the net module
## does not exist yet and this adapter must compile without it. The pid is stamped by net from the connection.

var _session: Object = null


func _init(session: Object = null) -> void:
	_session = session


func bind(session: Object) -> void:
	_session = session


func _ok() -> bool:
	return _session != null and is_instance_valid(_session)


func submit(cmd: PackedInt32Array) -> bool:
	if not _ok() or cmd.is_empty() or cmd.size() > 1024:
		return false
	return bool(_session.call("submit_command", cmd))


func can_submit() -> bool:
	return _ok() and bool(_session.call("can_submit"))


func local_pid() -> int:
	return int(_session.call("local_pid")) if _ok() else -1


func tick() -> int:
	return int(_session.call("tick")) if _ok() else 0


func is_observer() -> bool:
	return not _ok() or bool(_session.call("is_observer"))


func pending_count() -> int:
	return int(_session.call("pending_count")) if _ok() else 0


func request_pause(want_paused: bool) -> int:
	return int(_session.call("request_pause", want_paused)) if _ok() else 1


func surrender() -> bool:
	return bool(_session.call("surrender")) if _ok() else false


func send_chat(text: String, team_only: bool) -> void:
	if _ok():
		_session.call("send_chat", text, team_only)


func send_map_ping(cell_x: int, cell_y: int) -> void:
	if _ok():
		_session.call("send_map_ping", cell_x, cell_y)
