class_name NetJoinClient
extends RefCounted
## Client half of the join handshake (docs/spec/net.md 5.3.1): JOIN_REQUEST -> JOIN_ACCEPT | JOIN_REJECT -> lobby
## snapshot, including the two "reconnect once" retries: with per-file hashes after a DATA_MISMATCH whose DATA_DIFF asks
## for them, and with the password proof after BAD_PASSWORD. The session owns the transport; this class only decides
## what to send and when the join failed, through the hooks below.

enum Stage { CONNECTING = 0, REQUESTED = 1, ACCEPTED = 2 }

const SNAPSHOT_WAIT_US: int = 2_000_000
const DIFF_WAIT_US: int = 2_000_000

## (bytes: PackedByteArray) -> void; sends on the control channel to the host.
var send: Callable = Callable()
## (with_files: bool) -> bool; closes the transport, opens a fresh one and connects again.
var reconnect: Callable = Callable()
## (reason: int, info: Dictionary) -> void; final rejection (the session closes the transport and goes IDLE).
var on_rejected: Callable = Callable()
## (text: String) -> void; connect / reply / snapshot timeout or a transport failure.
var on_failed: Callable = Callable()
## (peer_id: int, session_id: int, slot: int) -> void
var on_accepted: Callable = Callable()

var opts: NetSessionOptions = null
var host: String = ""
var port: int = 0
var session_id: int = 0
var stage: int = Stage.CONNECTING

var _with_files: bool = false
var _retried_files: bool = false
var _retried_password: bool = false
var _deadline_us: int = 0
var _snapshot_deadline_us: int = 0
var _reject: Dictionary = {}
var _awaiting_diff: bool = false
var _diff_lines: PackedStringArray = PackedStringArray()
var _diff_deadline_us: int = 0


func begin(now_us: int) -> void:
	stage = Stage.CONNECTING
	_deadline_us = now_us + (NetProtocol.CONNECT_TIMEOUT_MS + NetProtocol.JOIN_REPLY_TIMEOUT_MS + 1000) * 1000


func connect_timeout_text() -> String:
	return "Could not reach %s:%d within 6 seconds. Check the address, that the host has opened a game, and that UDP %d is allowed through the host's firewall." % [host, port, port]


## The transport reported CONNECTED: send the JOIN_REQUEST.
func on_connected(now_us: int) -> void:
	var req: PackedByteArray = NetLobby.build_join_request(opts, session_id, _with_files, opts.client_nonce)
	stage = Stage.REQUESTED
	_deadline_us = now_us + NetProtocol.JOIN_REPLY_TIMEOUT_MS * 1000
	if req.is_empty():
		_fail("the join request could not be built")
		return
	if send.is_valid():
		send.call(req)


func _fail(text: String) -> void:
	if on_failed.is_valid():
		on_failed.call(text)


## true while a rejection is being resolved (waiting for DATA_DIFF, or already reported).
func is_resolving() -> bool:
	return _awaiting_diff or not _reject.is_empty()


## The transport died during the handshake. Returns true when it was consumed here.
func on_transport_lost() -> bool:
	if _awaiting_diff:
		_finish_reject()
		return true
	return not _reject.is_empty()


## Snapshot applied: the join is complete.
func complete() -> void:
	_reject = {}


func on_message(type: int, data: PackedByteArray, now_us: int) -> void:
	match type:
		NetProtocol.Msg.JOIN_REJECT:
			_on_reject(data, now_us)
		NetProtocol.Msg.DATA_DIFF:
			_on_diff(data)
		NetProtocol.Msg.JOIN_ACCEPT:
			var d: Dictionary = NetCodec.decode_join_accept(data)
			if d.is_empty() or stage != Stage.REQUESTED:
				return
			stage = Stage.ACCEPTED
			_snapshot_deadline_us = now_us + SNAPSHOT_WAIT_US
			if on_accepted.is_valid():
				on_accepted.call(int(d["peer_id"]), int(d["session_id"]), int(d["slot"]))


func tick(now_us: int) -> void:
	if _awaiting_diff and now_us >= _diff_deadline_us:
		_finish_reject()
	elif stage == Stage.ACCEPTED and now_us >= _snapshot_deadline_us:
		_fail("The host did not send the lobby state.")
	elif stage == Stage.REQUESTED and now_us >= _deadline_us and not _awaiting_diff:
		_fail("The host did not answer the join request.")
	elif stage == Stage.CONNECTING and now_us >= _deadline_us:
		_fail(connect_timeout_text())


func _info(d: Dictionary) -> Dictionary:
	return {
		"reason": int(d["reason"]), "session_id": int(d["host_session_id"]), "detail": str(d["detail"]),
		"host_version": str(d["host_game_version"]), "host_game_version": str(d["host_game_version"]),
		"host_proto": int(d["host_proto_version"]), "host_proto_version": int(d["host_proto_version"]),
		"host_sim": int(d["host_sim_version"]), "host_sim_version": int(d["host_sim_version"]),
		"host_data_hash": int(d["host_data_hash"]),
		"my_version": opts.game_version, "local_game_version": opts.game_version, "my_proto": NetProtocol.PROTO_VERSION,
		"local_proto_version": NetProtocol.PROTO_VERSION, "my_sim": opts.sim_version, "local_sim_version": opts.sim_version,
		"my_data_hash": opts.data_hash, "local_data_hash": opts.data_hash, "diff_lines": PackedStringArray(),
	}


func _on_reject(data: PackedByteArray, now_us: int) -> void:
	var d: Dictionary = NetCodec.decode_join_reject(data)
	if d.is_empty():
		var pre: Dictionary = NetCodec.peek_join_reject(data)
		d = {"host_proto_version": int(pre.get("host_proto_version", 0)), "reason": int(pre.get("reason", NetProtocol.RejectReason.BAD_REQUEST)),
			"host_sim_version": 0, "host_data_hash": 0, "host_session_id": 0, "host_game_version": "", "detail": ""}
	_reject = _info(d)
	var reason: int = int(d["reason"])
	if reason == NetProtocol.RejectReason.DATA_MISMATCH and opts.data_handshake.is_valid():
		_awaiting_diff = true
		_diff_deadline_us = now_us + DIFF_WAIT_US
		return
	if reason == NetProtocol.RejectReason.BAD_PASSWORD and not opts.password.is_empty() and not _retried_password:
		_retried_password = true
		session_id = int(d["host_session_id"])
		_retry(false)
		return
	_finish_reject()


func _on_diff(data: PackedByteArray) -> void:
	var d: Dictionary = NetCodec.decode_data_diff(data)
	if d.is_empty() or not _awaiting_diff:
		return
	for l: String in d["lines"] as PackedStringArray:
		if not _diff_lines.has(l) and _diff_lines.size() < 32:
			_diff_lines.append(l)
	_awaiting_diff = false
	if bool(d["wants_files"]) and not _retried_files and opts.data_handshake.is_valid():
		_retried_files = true
		_retry(true)
		return
	_finish_reject()


func _retry(with_files: bool) -> void:
	_with_files = with_files
	stage = Stage.CONNECTING
	_awaiting_diff = false
	_reject = {}
	_deadline_us = 0
	if not reconnect.is_valid() or not bool(reconnect.call(with_files)):
		_fail("could not reconnect")
		return
	begin(_deadline_now())


func _deadline_now() -> int:
	return opts.clock.now_us() if opts.clock != null else 0


func _finish_reject() -> void:
	if _reject.is_empty():
		return
	var info: Dictionary = _reject
	_reject = {}
	_awaiting_diff = false
	info["diff_lines"] = _diff_lines.duplicate()
	info["text"] = NetProtocol.describe_reject(int(info["reason"]), info)
	if on_rejected.is_valid():
		on_rejected.call(int(info["reason"]), info)
