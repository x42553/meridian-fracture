class_name AppNetPortSession
extends UiNetPort
## `UiNetPort` over a `NetSession` (net.md 6.3, ui.md 3.2.3), typed instead of `UiNetPortSession`'s by-name calls: `NetSession.local_pid`
## is a variable and there is no `tick()` / `can_submit()` method, which that adapter expects. The pid is stamped by net.

var _s: NetSession = null
var _ctx: AppMatchContext = null


func _init(session: NetSession = null, ctx: AppMatchContext = null) -> void:
	_s = session
	_ctx = ctx


func submit(cmd: PackedInt32Array) -> bool:
	if _s == null or cmd.is_empty() or cmd.size() > NetProtocol.MAX_CMD_INTS or not can_submit():
		return false
	var ok: bool = _s.submit_command(cmd)
	if ok and _ctx != null:
		_ctx.commands_sent += 1
	return ok


func can_submit() -> bool:
	return _s != null and _s.local_pid >= 0 and (_s.phase == NetSession.Phase.PLAYING or _s.phase == NetSession.Phase.PAUSED)


func local_pid() -> int:
	return _s.local_pid if _s != null else -1


func tick() -> int:
	return _s.adapter().current_tick() if _s != null and _s.adapter() != null else 0


func is_observer() -> bool:
	return _s == null or _s.local_pid < 0


func pending_count() -> int:
	return 0


func request_pause(want_paused: bool) -> int:
	return _s.request_pause(want_paused) if _s != null else NetProtocol.PauseError.NOT_PLAYING


func surrender() -> bool:
	return _s != null and _s.surrender()


func send_chat(text: String, team_only: bool) -> void:
	if _s != null:
		_s.send_chat(text, team_only)


func send_map_ping(cell_x: int, cell_y: int) -> void:
	if _s != null:
		_s.send_map_ping(cell_x, cell_y)
