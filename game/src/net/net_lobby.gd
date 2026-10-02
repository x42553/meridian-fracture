class_name NetLobby
extends RefCounted
## Lobby protocol, host and client halves (docs/spec/net.md 3.5, 4.4, 5.3). The host half is authoritative: it decides
## joins (proto -> sim -> data -> ban -> phase -> password -> capacity), validates and normalises every edit
## (permissions, colour / start swaps, unique names, layout shrink, ready clearing), coalesces LOBBY_SNAPSHOTs and
## checks the start conditions. The client half sends LOBBY_ACTIONs and mirrors snapshots (last writer wins by
## revision). Components never hold the session: everything outward goes through the Callables below, which the session
## wires (and clears on shutdown).
##
## For a non-host peer the int returned by the edit methods only reports LOCAL pre-validation and sending (OK = sent);
## the authoritative outcome is the next snapshot, so UI code renders from `state`.

enum Result { OK = 0, DENIED = 1, INVALID = 2, LOCKED = 3, CONFLICT = 4, FULL = 5 }
enum StartError {
	OK = 0, NO_PLAYERS = 1, NOT_ENOUGH_PLAYERS = 2, HUMAN_NOT_READY = 3, HUMAN_DISCONNECTED = 4, BAD_ROSTER = 5,
	COLOR_CONFLICT = 6, START_CONFLICT = 7, TOO_MANY_PLAYERS = 8, MAP_INVALID = 9, SINGLE_TEAM = 10,
	ALREADY_LAUNCHING = 11, AI_UNAVAILABLE = 12,
}

signal changed()
signal chat_received(channel: int, from_slot: int, from_name: String, text: String)
signal countdown_changed(seconds_left: int)

const BAN_MAX: int = 256

## The replicated lobby model. Read-only for the UI (mutations only through the methods below).
var state: NetLobbyState = NetLobbyState.new()

# ---- wiring (set by the session) ---------------------------------------------------------------------------
## (peer_id: int, data: PackedByteArray) -> void; sends on the control channel.
var send: Callable = Callable()
## (peer_id: int, code: int) -> void; graceful disconnect after the queued packets (join rejects).
var disconnect_peer: Callable = Callable()
## (peer_id: int, reason: int, detail: String) -> void; KICKED + graceful disconnect + peer bookkeeping.
var kick_peer: Callable = Callable()
## () -> void; the countdown of a successful host_start() begins (NetLaunch).
var begin_countdown: Callable = Callable()
## () -> void; an unready / leave / cancel aborts the countdown (LAUNCH_COUNTDOWN(0), phase back to LOBBY).
var cancel_countdown: Callable = Callable()

var opts: NetSessionOptions = null
var clock: NetClock = null
## peer_id -> NetPeerInfo (host; owned by the session).
var peers: Dictionary = {}
var local_peer_id: int = 1
## In-memory ban list of the session: [{ip, nonce}].
var bans: Array = []

var _is_host: bool = false
var _dirty: bool = false
var _last_snapshot_us: int = -1_000_000_000
var _session_id: int = 0


## host: `st` is the initial lobby (NetLobbyState.create_default / create_skirmish); client: an empty placeholder state.
func setup(options: NetSessionOptions, clk: NetClock, host_role: bool, st: NetLobbyState) -> void:
	opts = options
	clock = clk
	_is_host = host_role
	state = st
	_session_id = st.session_id
	if host_role and state.revision < 1:
		state.revision = 1
	_last_snapshot_us = clk.now_us() - 1_000_000_000


func is_host() -> bool:
	return _is_host


func local_slot() -> int:
	return state.slot_of_peer(local_peer_id) if local_peer_id > 0 else -1


func is_spectator() -> bool:
	for sp: Variant in state.spectators:
		if int((sp as Dictionary).get("peer_id", 0)) == local_peer_id:
			return true
	return false


func set_session_id(sid: int) -> void:
	_session_id = sid
	state.session_id = sid


# =====================================================================================================================
# host: snapshot production
# =====================================================================================================================

func _touch() -> void:
	state.revision += 1
	_dirty = true
	changed.emit()


## Sends the snapshot to every peer in the lobby now (join / kick / phase change).
func flush_snapshot() -> void:
	if not _is_host:
		return
	_dirty = false
	_last_snapshot_us = clock.now_us()
	var data: PackedByteArray = NetLobbyCodec.encode_snapshot(state)
	if data.is_empty():
		return
	for k: Variant in peers:
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.LOBBY:
			_send(p.peer_id, data)


## Coalesced snapshot broadcast (>= 100 ms apart) and the once-per-second ping refresh.
func tick(now_us: int) -> void:
	if not _is_host:
		return
	if _dirty and now_us - _last_snapshot_us >= NetProtocol.LOBBY_SNAPSHOT_MIN_MS * 1000:
		flush_snapshot()


## Updates the displayed ping of every seated human from {peer_id: rtt_ms}; the revision only moves when a value
## changed by >= 10 ms.
func update_pings(rtt_by_peer: Dictionary) -> void:
	if not _is_host:
		return
	var moved: bool = false
	for s: NetPlayerSlot in state.slots:
		if s.kind == NetProtocol.SlotKind.HUMAN and rtt_by_peer.has(s.peer_id):
			var v: int = int(rtt_by_peer[s.peer_id])
			if absi(v - s.ping_ms) >= 10:
				s.ping_ms = v
				moved = true
	if moved:
		state.revision += 1
		_dirty = true
		changed.emit()


func _send(peer_id: int, data: PackedByteArray) -> void:
	if send.is_valid() and not data.is_empty():
		send.call(peer_id, data)


func _broadcast(data: PackedByteArray, except_peer: int = 0) -> void:
	for k: Variant in peers:
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.LOBBY and p.peer_id != except_peer:
			_send(p.peer_id, data)


## The LAN discovery datagram fields of this lobby (NetDiscovery.encode_datagram keys).
func discovery_info() -> Dictionary:
	var total: int = 0
	var free: int = 0
	for s: NetPlayerSlot in state.slots:
		if s.kind != NetProtocol.SlotKind.CLOSED:
			total += 1
		if s.kind == NetProtocol.SlotKind.OPEN:
			free += 1
	return {
		"session_id": state.session_id, "humans": state.human_count(), "slots_total": total, "slots_free": free,
		"map_family": state.map_family, "map_size": state.map_size, "ai_count": state.ai_count(),
		"host_name": state.host_name, "has_password": not opts.password.is_empty(),
		"in_progress": state.phase != NetProtocol.LobbyPhase.OPEN, "full": free == 0,
		"spectators_allowed": state.allow_spectators, "dedicated": opts.dedicated,
	}


# =====================================================================================================================
# host: joins
# =====================================================================================================================

## Builds the JOIN_REQUEST a client sends (frozen prefix first). `with_files`: include the per-file hashes (retry).
static func build_join_request(o: NetSessionOptions, session_id: int, with_files: bool, nonce: int) -> PackedByteArray:
	var f: Dictionary = {
		"proto_version": NetProtocol.PROTO_VERSION, "spectator": o.join_as_spectator, "sim_version": o.sim_version,
		"data_hash": o.data_hash, "client_nonce": nonce, "game_version": o.game_version, "name": NetProtocol.sanitize_name(o.player_name),
	}
	if not o.password.is_empty() and session_id != 0:
		f["pw_proof"] = password_proof(session_id, o.password)
	if o.data_handshake.is_valid():
		var hs: Dictionary = o.data_handshake.call(with_files) as Dictionary
		f["data_format"] = int(hs.get("format", 0))
		f["tables"] = (hs.get("tables", {}) as Dictionary).duplicate()
		if with_files and hs.has("files"):
			f["files"] = (hs["files"] as Dictionary).duplicate()
	return NetCodec.encode_join_request(f)


static func password_proof(session_id: int, password: String) -> PackedByteArray:
	return ("%d:%s" % [session_id & 0xFFFFFFFF, password]).sha256_buffer()


func _reject(peer: NetPeerInfo, reason: int, detail: String) -> void:
	_send(peer.peer_id, NetCodec.encode_join_reject({
		"host_proto_version": NetProtocol.PROTO_VERSION, "reason": reason, "host_sim_version": opts.sim_version,
		"host_data_hash": opts.data_hash, "host_session_id": state.session_id, "host_game_version": opts.game_version,
		"detail": detail,
	}))


func _refuse(peer: NetPeerInfo, reason: int, detail: String = "") -> void:
	_reject(peer, reason, detail)
	peer.stage = NetPeerInfo.Stage.LEFT
	if disconnect_peer.is_valid():
		disconnect_peer.call(peer.peer_id, reason)


func _is_banned(peer: NetPeerInfo, nonce: int) -> bool:
	for b: Variant in bans:
		var d: Dictionary = b as Dictionary
		if str(d["ip"]) == peer.address or int(d["nonce"]) == nonce:
			return true
	return false


## JOIN_REQUEST of a peer in HANDSHAKE. Returns the violation weight to score (0 = none). The caller has verified type,
## size, direction and rate; everything else (frozen-prefix handling, checks in spec order, reply, disconnect) is here.
func handle_join(peer: NetPeerInfo, bytes: PackedByteArray) -> float:
	var pre: Dictionary = NetCodec.peek_join_request(bytes)
	if pre.is_empty():
		_refuse(peer, NetProtocol.RejectReason.BAD_REQUEST, "malformed")
		return 3.0
	if int(pre["proto_version"]) != NetProtocol.PROTO_VERSION:
		_refuse(peer, NetProtocol.RejectReason.PROTO_MISMATCH, "protocol %d, host %d" % [int(pre["proto_version"]), NetProtocol.PROTO_VERSION])
		return 0.0
	var req: Dictionary = NetCodec.decode_join_request(bytes)
	if req.is_empty():
		_refuse(peer, NetProtocol.RejectReason.BAD_REQUEST, "malformed")
		return 3.0
	if int(req["sim_version"]) != (opts.sim_version & 0xFFFFFFFF):
		_refuse(peer, NetProtocol.RejectReason.SIM_MISMATCH, "simulation %d, host %d" % [int(req["sim_version"]), opts.sim_version])
		return 0.0
	if int(req["data_hash"]) != (opts.data_hash & 0xFFFFFFFF):
		_reject_data(peer, req)
		return 0.0
	var nonce: int = int(req["client_nonce"])
	if _is_banned(peer, nonce):
		_refuse(peer, NetProtocol.RejectReason.BANNED)
		return 0.0
	var spectator: bool = bool(req["spectator"])
	if state.phase == NetProtocol.LobbyPhase.IN_GAME:
		_refuse(peer, NetProtocol.RejectReason.IN_PROGRESS)
		return 0.0
	if state.phase != NetProtocol.LobbyPhase.OPEN:
		_refuse(peer, NetProtocol.RejectReason.HOST_BUSY)
		return 0.0
	if not opts.password.is_empty():
		var ok: bool = req.has("pw_proof") and (req["pw_proof"] as PackedByteArray) == password_proof(state.session_id, opts.password)
		if not ok:
			_refuse(peer, NetProtocol.RejectReason.BAD_PASSWORD)
			return 0.0
	if spectator:
		if not state.allow_spectators:
			_refuse(peer, NetProtocol.RejectReason.SPECTATORS_CLOSED)
			return 0.0
		if state.spectators.size() >= NetProtocol.MAX_SPECTATORS:
			_refuse(peer, NetProtocol.RejectReason.LOBBY_FULL)
			return 0.0
	elif state.first_open_slot() < 0:
		_refuse(peer, NetProtocol.RejectReason.LOBBY_FULL)
		return 0.0
	# accepted
	peer.nonce = nonce
	peer.join_game_version = str(req["game_version"])
	peer.stage = NetPeerInfo.Stage.LOBBY
	peer.is_spectator = spectator
	var name: String = _unique_name(NetProtocol.sanitize_name(str(req["name"])), -1)
	peer.name = name
	if spectator:
		state.spectators.append({"peer_id": peer.peer_id, "name": name})
		peer.slot = -1
	else:
		var idx: int = state.first_open_slot()
		_seat(idx, peer.peer_id, name)
		peer.slot = idx
	state.revision += 1
	_send(peer.peer_id, NetCodec.encode_join_accept({
		"peer_id": peer.peer_id, "session_id": state.session_id, "slot": peer.slot if peer.slot >= 0 else 255, "phase": state.phase,
	}))
	_send(peer.peer_id, NetLobbyCodec.encode_snapshot(state))
	# the newcomer already has the fresh snapshot: the others get it right away too
	var snap: PackedByteArray = NetLobbyCodec.encode_snapshot(state)
	_broadcast(snap, peer.peer_id)
	_dirty = false
	_last_snapshot_us = clock.now_us()
	changed.emit()
	if opts.game_version != peer.join_game_version and not opts.game_version.is_empty():
		system_chat("%s uses game version %s (host %s)" % [name, peer.join_game_version, opts.game_version])
	return 0.0


func _reject_data(peer: NetPeerInfo, req: Dictionary) -> void:
	_reject(peer, NetProtocol.RejectReason.DATA_MISMATCH, "data %08X, host %08X" % [int(req["data_hash"]), opts.data_hash & 0xFFFFFFFF])
	if req.has("tables") and opts.data_handshake.is_valid() and opts.data_diff.is_valid():
		var has_files: bool = req.has("files")
		var host_hs: Dictionary = opts.data_handshake.call(has_files) as Dictionary
		var remote: Dictionary = {"format": int(req.get("data_format", 0)), "tables": req["tables"]}
		if has_files:
			remote["files"] = req["files"]
		var lines: PackedStringArray = opts.data_diff.call(host_hs, remote) as PackedStringArray
		if lines.size() > 32:
			lines = lines.slice(0, 32)
		var can_files: bool = not has_files and host_hs.get("files", null) == null and _host_has_files()
		_send(peer.peer_id, NetCodec.encode_data_diff({"wants_files": can_files, "lines": lines}))
	peer.stage = NetPeerInfo.Stage.LEFT
	if disconnect_peer.is_valid():
		disconnect_peer.call(peer.peer_id, NetProtocol.RejectReason.DATA_MISMATCH)


func _host_has_files() -> bool:
	if not opts.data_handshake.is_valid():
		return false
	var hs: Dictionary = opts.data_handshake.call(true) as Dictionary
	return hs.has("files") and not (hs["files"] as Dictionary).is_empty()


func _lowest_unused_color(exclude_slot: int) -> int:
	var used: Dictionary = {}
	for s: NetPlayerSlot in state.slots:
		if s.is_active() and s.index != exclude_slot:
			used[s.color] = true
	for c: int in opts.color_count:
		if not used.has(c):
			return c
	return 0


func _unique_name(base: String, exclude_slot: int) -> String:
	var taken: Dictionary = {}
	for s: NetPlayerSlot in state.slots:
		if s.is_active() and s.index != exclude_slot and not s.name.is_empty():
			taken[s.name] = true
	for sp: Variant in state.spectators:
		taken[str((sp as Dictionary).get("name", ""))] = true
	if not taken.has(base):
		return base
	var n: int = 2
	while true:
		var suffix: String = " (%d)" % n
		var cand: String = NetProtocol.truncate_utf8(base, NetProtocol.NAME_MAX_BYTES - suffix.length()) + suffix
		if cand.length() > NetProtocol.NAME_MAX_CHARS:
			cand = base.substr(0, NetProtocol.NAME_MAX_CHARS - suffix.length()) + suffix
		if not taken.has(cand):
			return cand
		n += 1
	return base


func _seat(idx: int, peer_id: int, name: String) -> void:
	var s: NetPlayerSlot = state.slots[idx]
	s.kind = NetProtocol.SlotKind.HUMAN
	s.peer_id = peer_id
	s.name = name
	s.roster_id = "random"
	s.team = 0
	s.color = _lowest_unused_color(idx)
	s.start = -1
	s.handicap_pct = 100
	s.ready = false
	s.connected = true
	s.ai_level = 1
	s.ai_style = 0
	s.ai_flags = 0
	s.ping_ms = 0


func _vacate(idx: int, kind: int) -> void:
	var s: NetPlayerSlot = state.slots[idx]
	s.kind = kind
	s.peer_id = 0
	s.name = ""
	s.roster_id = "random"
	s.team = 0
	s.start = -1
	s.handicap_pct = 100
	s.ready = false
	s.connected = false
	s.ai_level = 1
	s.ai_style = 0
	s.ai_flags = 0
	s.ping_ms = 0
	if kind == NetProtocol.SlotKind.CLOSED or kind == NetProtocol.SlotKind.OPEN:
		s.color = idx


## The transport connection of `peer_id` ended (or it was kicked): free its slot / spectator entry. Returns true when a
## COUNTDOWN was running and has been cancelled.
func on_peer_gone(peer_id: int) -> bool:
	if not _is_host or peer_id == 1:
		return false
	var cancelled: bool = false
	var idx: int = state.slot_of_peer(peer_id)
	if idx >= 0:
		if state.phase == NetProtocol.LobbyPhase.COUNTDOWN:
			cancelled = true
		if state.phase == NetProtocol.LobbyPhase.IN_GAME or state.phase == NetProtocol.LobbyPhase.LOADING or state.phase == NetProtocol.LobbyPhase.ENDED:
			state.slots[idx].connected = false
		else:
			_vacate(idx, NetProtocol.SlotKind.OPEN)
	else:
		for i: int in range(state.spectators.size() - 1, -1, -1):
			if int((state.spectators[i] as Dictionary).get("peer_id", 0)) == peer_id:
				state.spectators.remove_at(i)
	if cancelled:
		_abort_countdown_state()
	_touch()
	flush_snapshot()
	return cancelled


func _abort_countdown_state() -> void:
	state.phase = NetProtocol.LobbyPhase.OPEN
	if cancel_countdown.is_valid():
		cancel_countdown.call()


# =====================================================================================================================
# host: LOBBY_ACTION
# =====================================================================================================================

## LOBBY_ACTION of a seated peer. Returns the violation weight (0 = fine or a benign race).
func handle_action(peer: NetPeerInfo, bytes: PackedByteArray) -> float:
	var act: Dictionary = NetLobbyCodec.decode_action(bytes)
	if act.is_empty():
		return 3.0
	var res: int = _apply(peer.peer_id, int(act["op"]), act)
	peer.name = _name_of_peer(peer.peer_id, peer.name)
	peer.slot = state.slot_of_peer(peer.peer_id)
	if res == Result.DENIED or res == Result.INVALID or res == Result.CONFLICT:
		return 1.0
	return 0.0


func _name_of_peer(peer_id: int, fallback: String) -> String:
	var idx: int = state.slot_of_peer(peer_id)
	if idx >= 0:
		return state.slots[idx].name
	return fallback


func _apply(peer_id: int, op: int, a: Dictionary) -> int:
	var idx: int = state.slot_of_peer(peer_id)
	var locked: bool = state.phase != NetProtocol.LobbyPhase.OPEN
	if op == NetProtocol.LobbyOp.SET_READY and not bool(a.get("ready", false)) and idx >= 0 and state.phase == NetProtocol.LobbyPhase.COUNTDOWN:
		# the only edit allowed while counting down: it aborts the launch
		if peer_id != 1:
			state.slots[idx].ready = false
		_abort_countdown_state()
		_touch()
		flush_snapshot()
		return Result.OK
	if locked:
		return Result.LOCKED
	match op:
		NetProtocol.LobbyOp.TO_SPECTATOR:
			return _to_spectator(peer_id, idx)
		NetProtocol.LobbyOp.TO_PLAYER:
			return _to_player(peer_id, idx)
		NetProtocol.LobbyOp.MOVE_TO_SLOT:
			return _move(peer_id, idx, int(a.get("slot", -1)))
	if idx < 0:
		return Result.DENIED
	var s: NetPlayerSlot = state.slots[idx]
	match op:
		NetProtocol.LobbyOp.SET_ROSTER:
			var r: String = str(a.get("roster", ""))
			if not NetMatchConfig.is_roster_ok(r, opts.roster_ids):
				return Result.INVALID
			s.roster_id = r
		NetProtocol.LobbyOp.SET_TEAM:
			var t: int = int(a.get("team", -1))
			if t < 0 or t > 4:
				return Result.INVALID
			s.team = t
		NetProtocol.LobbyOp.SET_COLOR:
			return _set_color(idx, int(a.get("color", -1)))
		NetProtocol.LobbyOp.SET_START:
			return _set_start(idx, int(a.get("start", -2)))
		NetProtocol.LobbyOp.SET_READY:
			if peer_id != 1:
				s.ready = bool(a.get("ready", false))
			else:
				return Result.OK
		NetProtocol.LobbyOp.SET_NAME:
			s.name = _unique_name(NetProtocol.sanitize_name(str(a.get("name", ""))), idx)
		_:
			return Result.INVALID
	_touch()
	return Result.OK


func _set_color(idx: int, color: int) -> int:
	if color < 0 or color >= opts.color_count:
		return Result.INVALID
	var s: NetPlayerSlot = state.slots[idx]
	for o: NetPlayerSlot in state.slots:
		if o.index != idx and o.is_active() and o.color == color:
			o.color = s.color
			break
	s.color = color
	_touch()
	return Result.OK


func _set_start(idx: int, start: int) -> int:
	if start < -1 or start >= state.layout_players:
		return Result.INVALID
	var s: NetPlayerSlot = state.slots[idx]
	if start >= 0:
		for o: NetPlayerSlot in state.slots:
			if o.index != idx and o.is_active() and o.start == start:
				o.start = s.start
				break
	s.start = start
	_touch()
	return Result.OK


func _to_spectator(peer_id: int, idx: int) -> int:
	if peer_id == 1 or not state.allow_spectators:
		return Result.DENIED
	if idx < 0:
		return Result.OK  # already a spectator
	if state.spectators.size() >= NetProtocol.MAX_SPECTATORS:
		return Result.FULL
	var nm: String = state.slots[idx].name
	_vacate(idx, NetProtocol.SlotKind.OPEN)
	state.spectators.append({"peer_id": peer_id, "name": nm})
	_touch()
	return Result.OK


func _to_player(peer_id: int, idx: int) -> int:
	if idx >= 0:
		return Result.OK
	var free: int = state.first_open_slot()
	if free < 0:
		return Result.FULL
	var nm: String = ""
	for i: int in state.spectators.size():
		if int((state.spectators[i] as Dictionary).get("peer_id", 0)) == peer_id:
			nm = str((state.spectators[i] as Dictionary).get("name", ""))
			state.spectators.remove_at(i)
			break
	if nm.is_empty():
		return Result.DENIED
	_seat(free, peer_id, _unique_name(nm, -1))
	_touch()
	return Result.OK


func _move(peer_id: int, idx: int, target: int) -> int:
	if target < 0 or target >= NetProtocol.MAX_PLAYERS:
		return Result.INVALID
	if idx == target:
		return Result.OK
	if state.slots[target].kind != NetProtocol.SlotKind.OPEN:
		return Result.CONFLICT
	if idx < 0:
		var r: int = _to_player_at(peer_id, target)
		return r
	var src: NetPlayerSlot = state.slots[idx]
	var dst: NetPlayerSlot = state.slots[target]
	dst.kind = src.kind
	dst.peer_id = src.peer_id
	dst.name = src.name
	dst.roster_id = src.roster_id
	dst.team = src.team
	dst.color = src.color
	dst.start = src.start
	dst.handicap_pct = src.handicap_pct
	dst.ready = src.ready
	dst.connected = src.connected
	dst.ping_ms = src.ping_ms
	_vacate(idx, NetProtocol.SlotKind.OPEN)
	_touch()
	return Result.OK


func _to_player_at(peer_id: int, target: int) -> int:
	var nm: String = ""
	for i: int in state.spectators.size():
		if int((state.spectators[i] as Dictionary).get("peer_id", 0)) == peer_id:
			nm = str((state.spectators[i] as Dictionary).get("name", ""))
			state.spectators.remove_at(i)
			break
	if nm.is_empty():
		return Result.DENIED
	_seat(target, peer_id, _unique_name(nm, -1))
	_touch()
	return Result.OK


# =====================================================================================================================
# any seated peer: own-slot edits
# =====================================================================================================================

func _edit(op: int, args: Dictionary) -> int:
	if _is_host:
		return _apply(local_peer_id, op, args)
	if local_peer_id <= 0:
		return Result.DENIED
	if state.phase != NetProtocol.LobbyPhase.OPEN and not (op == NetProtocol.LobbyOp.SET_READY and not bool(args.get("ready", false)) and state.phase == NetProtocol.LobbyPhase.COUNTDOWN):
		return Result.LOCKED
	var data: PackedByteArray = NetLobbyCodec.encode_action(op, args)
	if data.is_empty():
		return Result.INVALID
	_send(1, data)
	return Result.OK


func set_roster(roster_id: String) -> int:
	if not NetMatchConfig.is_roster_ok(roster_id, opts.roster_ids):
		return Result.INVALID
	return _edit(NetProtocol.LobbyOp.SET_ROSTER, {"roster": roster_id})


func set_team(team: int) -> int:
	if team < 0 or team > 4:
		return Result.INVALID
	return _edit(NetProtocol.LobbyOp.SET_TEAM, {"team": team})


func set_color(color: int) -> int:
	if color < 0 or color >= opts.color_count:
		return Result.INVALID
	return _edit(NetProtocol.LobbyOp.SET_COLOR, {"color": color})


func set_start(start: int) -> int:
	if start < -1 or start >= state.layout_players:
		return Result.INVALID
	return _edit(NetProtocol.LobbyOp.SET_START, {"start": start})


func set_ready(ready: bool) -> int:
	return _edit(NetProtocol.LobbyOp.SET_READY, {"ready": ready})


func set_name(name: String) -> int:
	return _edit(NetProtocol.LobbyOp.SET_NAME, {"name": NetProtocol.sanitize_name(name)})


func move_to_slot(slot: int) -> int:
	if slot < 0 or slot >= NetProtocol.MAX_PLAYERS:
		return Result.INVALID
	return _edit(NetProtocol.LobbyOp.MOVE_TO_SLOT, {"slot": slot})


func become_spectator() -> int:
	return _edit(NetProtocol.LobbyOp.TO_SPECTATOR, {})


func become_player() -> int:
	return _edit(NetProtocol.LobbyOp.TO_PLAYER, {})


# =====================================================================================================================
# host only
# =====================================================================================================================

func _host_edit_ok() -> int:
	if not _is_host:
		return Result.DENIED
	if state.phase != NetProtocol.LobbyPhase.OPEN:
		return Result.LOCKED
	return Result.OK


## Any host change to a human slot / map / rules / net options clears the ready flag of every remote human.
func _clear_ready() -> void:
	for s: NetPlayerSlot in state.slots:
		if s.kind == NetProtocol.SlotKind.HUMAN and s.peer_id != 1:
			s.ready = false


func host_set_slot_kind(slot: int, kind: int) -> int:
	var g: int = _host_edit_ok()
	if g != Result.OK:
		return g
	if slot < 0 or slot >= NetProtocol.MAX_PLAYERS:
		return Result.INVALID
	if kind != NetProtocol.SlotKind.CLOSED and kind != NetProtocol.SlotKind.OPEN and kind != NetProtocol.SlotKind.AI:
		return Result.INVALID
	var s: NetPlayerSlot = state.slots[slot]
	if s.kind == NetProtocol.SlotKind.HUMAN and s.peer_id == 1:
		return Result.DENIED
	if kind != NetProtocol.SlotKind.CLOSED and slot >= state.layout_players:
		return Result.INVALID
	if s.kind == kind:
		return Result.OK
	if s.kind == NetProtocol.SlotKind.HUMAN:
		var pid: int = s.peer_id
		_vacate(slot, kind)
		if kick_peer.is_valid():
			kick_peer.call(pid, NetProtocol.KickReason.KICKED_BY_HOST, "slot closed")
	else:
		_vacate(slot, kind)
	if kind == NetProtocol.SlotKind.AI:
		s.name = "AI %d" % (slot + 1)
		s.ready = true
		s.connected = true
		s.ai_level = clampi(1, 0, opts.ai_level_count - 1)
		s.handicap_pct = _ai_handicap(s.ai_level)
		s.color = _lowest_unused_color(slot)
	_clear_ready()
	_touch()
	flush_snapshot()
	return Result.OK


func _ai_handicap(level: int) -> int:
	if opts.ai_default_handicap.is_valid():
		return clampi(int(opts.ai_default_handicap.call(level)), 50, 200)
	return 100


func host_set_ai(slot: int, level: int, style: int) -> int:
	var g: int = _host_edit_ok()
	if g != Result.OK:
		return g
	if slot < 0 or slot >= NetProtocol.MAX_PLAYERS or state.slots[slot].kind != NetProtocol.SlotKind.AI:
		return Result.INVALID
	if level < 0 or level >= opts.ai_level_count or style < 0 or style >= opts.ai_style_count:
		return Result.INVALID
	var s: NetPlayerSlot = state.slots[slot]
	s.ai_level = level
	s.ai_style = style
	s.ai_flags = 0
	if opts.ai_default_handicap.is_valid():
		s.handicap_pct = _ai_handicap(level)
	_touch()
	return Result.OK


func _slot_edit(slot: int) -> int:
	var g: int = _host_edit_ok()
	if g != Result.OK:
		return g
	if slot < 0 or slot >= NetProtocol.MAX_PLAYERS or not state.slots[slot].is_active():
		return Result.INVALID
	return Result.OK


func _after_slot_edit(slot: int) -> void:
	if state.slots[slot].kind == NetProtocol.SlotKind.HUMAN and state.slots[slot].peer_id != 1:
		_clear_ready()
	_touch()
	if state.slots[slot].kind == NetProtocol.SlotKind.HUMAN:
		flush_snapshot()


func host_set_slot_roster(slot: int, roster_id: String) -> int:
	var g: int = _slot_edit(slot)
	if g != Result.OK:
		return g
	if not NetMatchConfig.is_roster_ok(roster_id, opts.roster_ids):
		return Result.INVALID
	state.slots[slot].roster_id = roster_id
	_after_slot_edit(slot)
	return Result.OK


func host_set_slot_team(slot: int, team: int) -> int:
	var g: int = _slot_edit(slot)
	if g != Result.OK:
		return g
	if team < 0 or team > 4:
		return Result.INVALID
	state.slots[slot].team = team
	_after_slot_edit(slot)
	return Result.OK


func host_set_slot_color(slot: int, color: int) -> int:
	var g: int = _slot_edit(slot)
	if g != Result.OK:
		return g
	var r: int = _set_color(slot, color)
	if r == Result.OK:
		_after_slot_edit(slot)
	return r


func host_set_slot_start(slot: int, start: int) -> int:
	var g: int = _slot_edit(slot)
	if g != Result.OK:
		return g
	var r: int = _set_start(slot, start)
	if r == Result.OK:
		_after_slot_edit(slot)
	return r


func host_set_slot_handicap(slot: int, handicap_pct: int) -> int:
	var g: int = _slot_edit(slot)
	if g != Result.OK:
		return g
	if handicap_pct < 50 or handicap_pct > 200 or handicap_pct % 5 != 0:
		return Result.INVALID
	state.slots[slot].handicap_pct = handicap_pct
	_after_slot_edit(slot)
	return Result.OK


## Slots >= layout_players are forced CLOSED (a human there moves to the first OPEN slot, else becomes a spectator, else is
## kicked); when the layout grows the new slots open.
func host_set_map(family: int, size: int, map_seed: int, layout_players: int) -> int:
	var g: int = _host_edit_ok()
	if g != Result.OK:
		return g
	if family < 0 or family > 2 or size < 96 or size > 256 or size % 8 != 0 or not NetMatchConfig.LAYOUTS.has(layout_players):
		return Result.INVALID
	if map_seed < 0 or map_seed > 0xFFFFFFFF:
		return Result.INVALID
	var old_layout: int = state.layout_players
	state.map_family = family
	state.map_size = size
	state.map_seed = map_seed
	state.layout_players = layout_players
	if layout_players < old_layout:
		var displaced: Array = []
		for i: int in range(layout_players, NetProtocol.MAX_PLAYERS):
			var s: NetPlayerSlot = state.slots[i]
			if s.kind == NetProtocol.SlotKind.HUMAN:
				displaced.append([s.peer_id, s.name, s.roster_id, s.team, s.ready])
			if s.kind != NetProtocol.SlotKind.CLOSED:
				_vacate(i, NetProtocol.SlotKind.CLOSED)
		for d: Variant in displaced:
			var arr: Array = d as Array
			var free: int = state.first_open_slot()
			if free >= 0:
				_seat(free, int(arr[0]), str(arr[1]))
				state.slots[free].roster_id = str(arr[2])
				state.slots[free].team = int(arr[3])
			elif state.allow_spectators and state.spectators.size() < NetProtocol.MAX_SPECTATORS:
				state.spectators.append({"peer_id": int(arr[0]), "name": str(arr[1])})
			elif kick_peer.is_valid():
				kick_peer.call(int(arr[0]), NetProtocol.KickReason.KICKED_BY_HOST, "no free slot")
	else:
		for i: int in range(old_layout, layout_players):
			if state.slots[i].kind == NetProtocol.SlotKind.CLOSED:
				_vacate(i, NetProtocol.SlotKind.OPEN)
	for s: NetPlayerSlot in state.slots:
		if s.start >= layout_players:
			s.start = -1
	_clear_ready()
	_touch()
	flush_snapshot()
	return Result.OK


func host_set_rules(rules: Dictionary) -> int:
	var g: int = _host_edit_ok()
	if g != Result.OK:
		return g
	var schema: Dictionary = {}
	for e: Variant in NetMatchConfig.rules_schema():
		schema[(e as Dictionary)["key"]] = e
	var merged: Dictionary = state.rules.duplicate()
	for k: Variant in rules:
		if not schema.has(k):
			return Result.INVALID
		var sd: Dictionary = schema[k] as Dictionary
		var raw: Variant = rules[k]
		var v: int
		if typeof(raw) == TYPE_BOOL:
			v = 1 if bool(raw) else 0
		elif typeof(raw) == TYPE_INT:
			v = int(raw)
		else:
			return Result.INVALID
		if v < int(sd["min"]) or v > int(sd["max"]):
			return Result.INVALID
		merged[k] = v
	state.rules = merged
	_clear_ready()
	_touch()
	flush_snapshot()
	return Result.OK


## keys: speed_pct (one of NetProtocol.SPEED_PCT), pause_policy 0..2, on_disconnect 0..1, auto_drop_ms 0..600000,
## allow_spectators (bool; switching it off removes the current spectators).
func host_set_net_options(o: Dictionary) -> int:
	var g: int = _host_edit_ok()
	if g != Result.OK:
		return g
	var speed_code: int = state.speed_code
	var pause_policy: int = state.pause_policy
	var on_disc: int = state.on_disconnect
	var auto_drop: int = state.auto_drop_ms
	var spect: bool = state.allow_spectators
	for k: Variant in o:
		var v: Variant = o[k]
		match str(k):
			"speed_pct":
				var idx: int = NetProtocol.SPEED_PCT.find(int(v)) if typeof(v) == TYPE_INT else -1
				if idx < 0:
					return Result.INVALID
				speed_code = idx
			"pause_policy":
				if typeof(v) != TYPE_INT or int(v) < 0 or int(v) > 2:
					return Result.INVALID
				pause_policy = int(v)
			"on_disconnect":
				if typeof(v) != TYPE_INT or int(v) < 0 or int(v) > 1:
					return Result.INVALID
				on_disc = int(v)
			"auto_drop_ms":
				if typeof(v) != TYPE_INT or int(v) < 0 or int(v) > 600000:
					return Result.INVALID
				auto_drop = int(v)
			"allow_spectators":
				if typeof(v) != TYPE_BOOL:
					return Result.INVALID
				spect = bool(v)
			_:
				return Result.INVALID
	state.speed_code = speed_code
	state.pause_policy = pause_policy
	state.on_disconnect = on_disc
	state.auto_drop_ms = auto_drop
	if state.allow_spectators and not spect:
		var gone: Array = state.spectators.duplicate()
		state.spectators = []
		state.allow_spectators = false
		for sp: Variant in gone:
			if kick_peer.is_valid():
				kick_peer.call(int((sp as Dictionary)["peer_id"]), NetProtocol.KickReason.KICKED_BY_HOST, "spectators closed")
	state.allow_spectators = spect
	_clear_ready()
	_touch()
	flush_snapshot()
	return Result.OK


func host_kick(peer_id: int, ban_for_session: bool) -> int:
	if not _is_host:
		return Result.DENIED
	if peer_id == 1 or not peers.has(peer_id):
		return Result.INVALID
	var p: NetPeerInfo = peers[peer_id] as NetPeerInfo
	if ban_for_session:
		if bans.size() >= BAN_MAX:
			bans.pop_front()
		bans.append({"ip": p.address, "nonce": p.nonce})
	if kick_peer.is_valid():
		kick_peer.call(peer_id, NetProtocol.KickReason.BANNED if ban_for_session else NetProtocol.KickReason.KICKED_BY_HOST, "")
	return Result.OK


# ---- start ---------------------------------------------------------------------------------------------------

static func team_final(s: NetPlayerSlot) -> int:
	return s.team if s.team > 0 else 8 + s.index


## The first failing start condition (spec 5.3.7), or StartError.OK.
func start_error() -> int:
	var active: PackedInt32Array = state.active_slot_indices()
	if active.is_empty():
		return StartError.NO_PLAYERS
	if active.size() < 2 and not opts.allow_solo:
		return StartError.NOT_ENOUGH_PLAYERS
	for i: int in active:
		var s: NetPlayerSlot = state.slots[i]
		if s.kind == NetProtocol.SlotKind.HUMAN:
			if not s.connected:
				return StartError.HUMAN_DISCONNECTED
			if not s.ready and s.peer_id != 1:
				return StartError.HUMAN_NOT_READY
	for i: int in active:
		if not NetMatchConfig.is_roster_ok(state.slots[i].roster_id, opts.roster_ids):
			return StartError.BAD_ROSTER
	var colors: Dictionary = {}
	for i: int in active:
		var c: int = state.slots[i].color
		if colors.has(c) or c < 0 or c >= opts.color_count:
			return StartError.COLOR_CONFLICT
		colors[c] = true
	var starts: Dictionary = {}
	for i: int in active:
		var st: int = state.slots[i].start
		if st < 0:
			continue
		if st >= state.layout_players or starts.has(st):
			return StartError.START_CONFLICT
		starts[st] = true
	if active.size() > state.layout_players:
		return StartError.TOO_MANY_PLAYERS
	if opts.map_validator.is_valid():
		if str(opts.map_validator.call(state.map_family, state.map_size, state.layout_players)) != "":
			return StartError.MAP_INVALID
	if not opts.allow_solo:
		var teams: Dictionary = {}
		for i: int in active:
			teams[team_final(state.slots[i])] = true
		if teams.size() < 2:
			return StartError.SINGLE_TEAM
	if state.phase != NetProtocol.LobbyPhase.OPEN:
		return StartError.ALREADY_LAUNCHING
	for i: int in active:
		if state.slots[i].kind == NetProtocol.SlotKind.AI and not opts.ai_factory.is_valid():
			return StartError.AI_UNAVAILABLE
	return StartError.OK


## Validates and begins the COUNTDOWN. Returns a StartError.
func host_start() -> int:
	if not _is_host:
		return StartError.ALREADY_LAUNCHING
	var e: int = start_error()
	if e != StartError.OK:
		return e
	state.phase = NetProtocol.LobbyPhase.COUNTDOWN
	_touch()
	flush_snapshot()
	if begin_countdown.is_valid():
		begin_countdown.call()
	return StartError.OK


func host_cancel_start() -> void:
	if _is_host and state.phase == NetProtocol.LobbyPhase.COUNTDOWN:
		_abort_countdown_state()
		_touch()
		flush_snapshot()


static func start_error_text(code: int) -> String:
	match code:
		StartError.OK:
			return ""
		StartError.NO_PLAYERS:
			return "There are no players in the game."
		StartError.NOT_ENOUGH_PLAYERS:
			return "At least two players (humans or AI) are needed."
		StartError.HUMAN_NOT_READY:
			return "Not every player is ready."
		StartError.HUMAN_DISCONNECTED:
			return "A player is disconnected."
		StartError.BAD_ROSTER:
			return "A player has no valid faction selected."
		StartError.COLOR_CONFLICT:
			return "Two players share a colour."
		StartError.START_CONFLICT:
			return "Two players share a start position."
		StartError.TOO_MANY_PLAYERS:
			return "There are more players than start positions on this map."
		StartError.MAP_INVALID:
			return "This map setup is not valid."
		StartError.SINGLE_TEAM:
			return "All players are on the same team."
		StartError.ALREADY_LAUNCHING:
			return "The game is already starting."
		StartError.AI_UNAVAILABLE:
			return "AI players are not available in this build."
	return "The game cannot start."


## The host returned to the lobby after a match (or an aborted launch): phase OPEN, ready flags reset, everybody
## still connected keeps the slot.
func reset_after_match() -> void:
	state.phase = NetProtocol.LobbyPhase.OPEN
	for s: NetPlayerSlot in state.slots:
		if s.kind == NetProtocol.SlotKind.HUMAN:
			s.ready = s.peer_id == 1
		elif s.kind == NetProtocol.SlotKind.AI:
			s.ready = true
	_touch()
	flush_snapshot()


## After a match: seats of humans that are no longer connected become OPEN. `peers` = the live peer records.
func free_disconnected_slots(live_peers: Dictionary) -> void:
	for s: NetPlayerSlot in state.slots:
		if s.kind == NetProtocol.SlotKind.HUMAN and s.peer_id != 1 and not live_peers.has(s.peer_id):
			_vacate(s.index, NetProtocol.SlotKind.OPEN)


## Sets the lobby phase and pushes a snapshot (launch progress).
func set_phase(phase: int) -> void:
	if state.phase == phase:
		return
	state.phase = phase
	_touch()
	if _is_host:
		flush_snapshot()


# =====================================================================================================================
# chat
# =====================================================================================================================

func send_chat(text: String, team_only: bool) -> void:
	var clean: String = NetProtocol.sanitize_text(text, NetProtocol.CHAT_MAX_BYTES)
	if clean.is_empty():
		return
	var ch: int = 1 if team_only else 0
	if _is_host:
		_host_chat(local_slot(), local_peer_id, ch, clean)
	elif local_peer_id > 0:
		_send(1, NetLobbyCodec.encode_chat_c2h({"channel": ch, "text": clean}))


## System line (from_slot 255) to everybody, including the host's own UI.
func system_chat(text: String) -> void:
	var clean: String = NetProtocol.sanitize_text(text, NetProtocol.CHAT_MAX_BYTES)
	if clean.is_empty():
		return
	var data: PackedByteArray = NetLobbyCodec.encode_chat_h2c({"channel": 0, "from_slot": 255, "from_name": "", "text": clean})
	_broadcast(data)
	chat_received.emit(0, 255, "", clean)


func _team_of_peer(peer_id: int) -> int:
	var idx: int = state.slot_of_peer(peer_id)
	return team_final(state.slots[idx]) if idx >= 0 else -1


## CHAT from a peer (host half): relays it. Returns the violation weight.
func handle_chat(peer: NetPeerInfo, bytes: PackedByteArray) -> float:
	var c: Dictionary = NetLobbyCodec.decode_chat_c2h(bytes)
	if c.is_empty():
		return 3.0
	var clean: String = NetProtocol.sanitize_text(str(c["text"]), NetProtocol.CHAT_MAX_BYTES)
	if clean.is_empty():
		return 0.0
	_host_chat(state.slot_of_peer(peer.peer_id), peer.peer_id, int(c["channel"]), clean)
	return 0.0


func _host_chat(from_slot: int, from_peer: int, channel: int, clean: String) -> void:
	var nm: String = state.slots[from_slot].name if from_slot >= 0 else _spectator_name(from_peer)
	var data: PackedByteArray = NetLobbyCodec.encode_chat_h2c({"channel": channel, "from_slot": from_slot if from_slot >= 0 else 255, "from_name": nm, "text": clean})
	var my_team: int = _team_of_peer(from_peer)
	for k: Variant in peers:
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.LEFT or p.stage == NetPeerInfo.Stage.HANDSHAKE:
			continue
		if channel == 1:
			var t: int = _team_of_peer(p.peer_id)
			if p.peer_id != from_peer and (t < 0 or my_team < 0 or t != my_team):
				continue
		_send(p.peer_id, data)
	var mine_ok: bool = channel == 0 or from_peer == local_peer_id or (my_team >= 0 and _team_of_peer(local_peer_id) == my_team)
	if mine_ok and local_peer_id > 0:
		chat_received.emit(channel, from_slot if from_slot >= 0 else 255, nm, clean)


func _spectator_name(peer_id: int) -> String:
	for sp: Variant in state.spectators:
		if int((sp as Dictionary).get("peer_id", 0)) == peer_id:
			return str((sp as Dictionary).get("name", ""))
	return ""


# =====================================================================================================================
# client half
# =====================================================================================================================

## LOBBY_SNAPSHOT: applied when newer than the current revision. Returns true when applied.
func handle_snapshot(bytes: PackedByteArray) -> bool:
	var d: NetLobbyState = NetLobbyCodec.decode_snapshot(bytes, opts) as NetLobbyState
	if d == null:
		return false
	if state.revision > 0 and d.revision <= state.revision:
		return false
	d.session_id = _session_id
	state = d
	changed.emit()
	return true


## Host-relayed CHAT (client half).
func handle_chat_h2c(bytes: PackedByteArray) -> bool:
	var c: Dictionary = NetLobbyCodec.decode_chat_h2c(bytes)
	if c.is_empty():
		return false
	chat_received.emit(int(c["channel"]), int(c["from_slot"]), str(c["from_name"]), str(c["text"]))
	return true


## Client: the countdown display changed (LAUNCH_COUNTDOWN). 0 = aborted.
func note_countdown(seconds_left: int) -> void:
	if not _is_host:
		state.phase = NetProtocol.LobbyPhase.COUNTDOWN if seconds_left > 0 else NetProtocol.LobbyPhase.OPEN
	countdown_changed.emit(seconds_left)
