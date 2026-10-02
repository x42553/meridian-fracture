class_name UiLobbyLan
extends RefCounted
## The logic of the lobby screen in the LAN roles HOST and CLIENT (ui.md 5.14), free of nodes so it can be tested against loopback
## sessions. It owns nothing: the `NetSession` holds the authoritative `NetLobby`; the screen's widgets edit a `UiLobbyState` mirror.
##   * `pull()` mirrors the replicated state into the mirror (`UiLobbyNet.pull`) whenever the lobby changed,
##   * `push()` turns the widget edit that just happened into `NetLobby` calls (`UiLobbyNet.diff` / `execute`),
##   * a client keeps its optimistic edit for `REVERT_S` and then pulls again, so a refused edit snaps back and a granted one shows
##     the host's normalisation,
##   * `start()` / `cancel_start()` / `toggle_ready()` / `kick()` / `take()` / `spectate()` / `play()` are the buttons of the bottom bar
##     and the rows.
## `refreshed` fires after every pull; `notice(text)` carries a refusal or a status line for the screen's message line.

signal refreshed()
signal notice(text: String)

## How long a client waits for the host's snapshot before it shows the authoritative state again.
const REVERT_S: float = 0.6

var session: NetSession = null
var lobby: NetLobby = null
var ui: UiLobbyState = null
var role: int = UiLobbyNet.Role.CLIENT

var _revert_in: float = -1.0


## `p_session` must be a HOST or CLIENT session in the lobby phases; `p_ui` is the mirror the widgets edit.
func setup(p_session: NetSession, p_ui: UiLobbyState) -> void:
	session = p_session
	lobby = p_session.lobby
	ui = p_ui
	role = role_of(p_session)
	session.lobby_changed.connect(_on_lobby_changed)
	pull()


func release() -> void:
	if session != null and session.lobby_changed.is_connected(_on_lobby_changed):
		session.lobby_changed.disconnect(_on_lobby_changed)
	session = null
	lobby = null


static func role_of(s: NetSession) -> int:
	return UiLobbyNet.Role.HOST if s != null and s.role == NetSession.Role.HOST else UiLobbyNet.Role.CLIENT


func local_slot() -> int:
	return lobby.local_slot() if lobby != null else -1


func is_spectator() -> bool:
	return lobby != null and lobby.is_spectator()


func state() -> NetLobbyState:
	return lobby.state


## Whether the launch countdown is running (the lobby is locked, the host may cancel, a client cancels by un-readying).
func counting_down() -> bool:
	return lobby != null and lobby.state.phase == NetProtocol.LobbyPhase.COUNTDOWN


## Whether the settings can still be edited (OPEN phase).
func open_for_edits() -> bool:
	return lobby != null and lobby.state.phase == NetProtocol.LobbyPhase.OPEN


func pull() -> void:
	if lobby == null:
		return
	_revert_in = -1.0
	UiLobbyNet.pull(lobby.state, ui)
	refreshed.emit()


func _on_lobby_changed() -> void:
	pull()


## Per frame: a client whose edit got no snapshot back re-shows the authoritative state.
func tick(delta: float) -> void:
	if _revert_in >= 0.0:
		_revert_in -= delta
		if _revert_in < 0.0:
			pull()


## The slots whose kind change in the UI mirror would remove a remote human player (the screen asks first).
func removals() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if role != UiLobbyNet.Role.HOST or lobby == null:
		return out
	for op: Dictionary in UiLobbyNet.diff(lobby.state, ui, role, local_slot()):
		if str(op["call"]) == "host_set_slot_kind":
			var slot: int = int((op["args"] as Array)[0])
			var n: NetPlayerSlot = lobby.state.slots[slot]
			if n.kind == NetProtocol.SlotKind.HUMAN and n.peer_id != 1:
				out.append(slot)
	return out


## Sends the widget edit that just happened. Returns `{ops: int, result: int}` (`NetLobby.Result`); a refusal also raises `notice`.
func push() -> Dictionary:
	if lobby == null:
		return {"ops": 0, "result": NetLobby.Result.DENIED}
	var ops: Array[Dictionary] = UiLobbyNet.diff(lobby.state, ui, role, local_slot())
	if ops.is_empty():
		return {"ops": 0, "result": NetLobby.Result.OK}
	var r: int = UiLobbyNet.execute(lobby, ops)
	if r != NetLobby.Result.OK:
		notice.emit(UiLobbyNet.result_text(r))
	if role == UiLobbyNet.Role.HOST:
		pull()
	else:
		_revert_in = REVERT_S
	return {"ops": ops.size(), "result": r}


## The ready flag of this peer's seat (the host is always ready).
func is_ready() -> bool:
	var i: int = local_slot()
	if i < 0 or lobby == null:
		return false
	return lobby.state.slots[i].ready or role == UiLobbyNet.Role.HOST


func toggle_ready() -> int:
	if lobby == null or local_slot() < 0:
		return NetLobby.Result.DENIED
	var r: int = lobby.set_ready(not is_ready())
	if r != NetLobby.Result.OK:
		notice.emit(UiLobbyNet.result_text(r))
	return r


## Host: checks the start conditions and begins the countdown. Returns `NetLobby.StartError` (the same codes as `UiLobbyState.Err`).
func start() -> int:
	if lobby == null or role != UiLobbyNet.Role.HOST:
		return NetLobby.StartError.ALREADY_LAUNCHING
	return lobby.host_start()


func start_error() -> int:
	return lobby.start_error() if lobby != null else NetLobby.StartError.NO_PLAYERS


func cancel_start() -> void:
	if lobby == null:
		return
	if role == UiLobbyNet.Role.HOST:
		lobby.host_cancel_start()
	else:
		lobby.set_ready(false)


## Host: removes the human in `slot` from the game (`ban` keeps it out for the rest of the session).
func kick(slot: int, ban: bool) -> int:
	if lobby == null or slot < 0 or slot >= lobby.state.slots.size():
		return NetLobby.Result.INVALID
	var n: NetPlayerSlot = lobby.state.slots[slot]
	if n.kind != NetProtocol.SlotKind.HUMAN or n.peer_id == 1:
		return NetLobby.Result.INVALID
	return lobby.host_kick(n.peer_id, ban)


## Client: moves to the open `slot` (a spectator becomes a player there).
func take(slot: int) -> int:
	if lobby == null:
		return NetLobby.Result.DENIED
	var r: int = lobby.move_to_slot(slot)
	if r != NetLobby.Result.OK:
		notice.emit(UiLobbyNet.result_text(r))
	if role == UiLobbyNet.Role.CLIENT:
		_revert_in = REVERT_S
	return r


func spectate() -> int:
	if lobby == null:
		return NetLobby.Result.DENIED
	var r: int = lobby.become_spectator()
	if r != NetLobby.Result.OK:
		notice.emit(UiLobbyNet.result_text(r))
	return r


func play() -> int:
	if lobby == null:
		return NetLobby.Result.DENIED
	var r: int = lobby.become_player()
	if r != NetLobby.Result.OK:
		notice.emit(UiLobbyNet.result_text(r))
	return r


## The host-measured ping of this peer's seat in ms (0 = unknown; the host itself has none).
func my_ping_ms() -> int:
	var i: int = local_slot()
	return lobby.state.slots[i].ping_ms if lobby != null and i >= 0 else 0


func send_chat(text: String, team_only: bool) -> void:
	if session != null:
		session.send_chat(text, team_only)


## The colour of the slot named `sender` (chat names), white for a system line or an unknown name.
func color_of_name(sender: String) -> Color:
	if lobby != null:
		for n: NetPlayerSlot in lobby.state.slots:
			if n.is_active() and n.name == sender:
				return UiPalette.team(n.color)
	return Color.WHITE
