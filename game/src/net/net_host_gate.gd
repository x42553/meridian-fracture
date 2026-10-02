class_name NetHostGate
extends RefCounted
## The host's front door (docs/spec/net.md 4.3 matrix, 5.3.1, 5.12): connection admission (connect magic, 4 per IP, 8
## unauthenticated), per-packet validation BEFORE any handler runs (known type, direction, size, channel, phase / stage
## permission, token bucket) and the decaying violation score that kicks at 12. Handlers are registered by the
## session as `type -> Callable(peer: NetPeerInfo, data: PackedByteArray, now_us: int) -> float` (the violation weight
## to add, 0 = fine). The gate never touches lobby, launch or lockstep itself.

## Session phase (NetSession.Phase), mirrored by the session on every change.
var phase: int = 0
var peers: Dictionary = {}
var handlers: Dictionary = {}
## (peer_id: int, code: int, graceful: bool) -> void
var disconnect_fn: Callable = Callable()
## (peer_id: int, reason: int, detail: String) -> void; KICKED + graceful disconnect + bookkeeping.
var kick: Callable = Callable()
## (level: int, text: String) -> void
var log_fn: Callable = Callable()
## (peer: NetPeerInfo, type: int, data: PackedByteArray) -> void; an oversize TURN_INPUT with a readable header.
var on_oversize_input: Callable = Callable()
var violations_total: int = 0


func _log(level: int, text: String) -> void:
	if log_fn.is_valid():
		log_fn.call(level, text)


## CONNECTED on the listening side. Creates the peer record or refuses the connection.
func on_connected(peer_id: int, connect_data: int, address: String, now_us: int) -> void:
	if not NetProtocol.has_connect_magic(connect_data):
		_log(NetProtocol.LogLevel.DEBUG, "peer %d: wrong connect magic, disconnected" % peer_id)
		disconnect_fn.call(peer_id, 0, false)
		return
	var same_ip: int = 0
	var unauth: int = 0
	for k: Variant in peers:
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.address == address:
			same_ip += 1
		if p.stage == NetPeerInfo.Stage.HANDSHAKE:
			unauth += 1
	if same_ip >= NetProtocol.MAX_CONN_PER_IP or unauth >= NetProtocol.MAX_UNAUTH_PEERS:
		_log(NetProtocol.LogLevel.DEBUG, "peer %d (%s): too many connections, refused" % [peer_id, address])
		disconnect_fn.call(peer_id, NetProtocol.RejectReason.TOO_MANY_CONNECTIONS, false)
		return
	var info: NetPeerInfo = NetPeerInfo.new()
	info.peer_id = peer_id
	info.address = address
	info.stage = NetPeerInfo.Stage.HANDSHAKE
	info.connected_at_ms = now_us / 1000
	info.handshake_since_us = now_us
	peers[peer_id] = info


## Drops peers that never sent a JOIN_REQUEST within HANDSHAKE_TIMEOUT_MS.
func expire_handshakes(now_us: int) -> void:
	for k: Variant in peers.keys():
		var p: NetPeerInfo = peers.get(k) as NetPeerInfo
		if p != null and p.stage == NetPeerInfo.Stage.HANDSHAKE and now_us - p.handshake_since_us > NetProtocol.HANDSHAKE_TIMEOUT_MS * 1000:
			peers.erase(k)
			disconnect_fn.call(p.peer_id, NetProtocol.KickReason.TIMEOUT, false)


func violate(p: NetPeerInfo, weight: float, why: String, now_us: int) -> void:
	if weight <= 0.0:
		return
	var score: float = p.limiter.add_violation(weight, now_us)
	p.violations = score
	p.last_violation_ms = now_us / 1000
	violations_total += int(ceil(weight))
	p.violation_total += int(ceil(weight))
	_log(NetProtocol.LogLevel.DEBUG, "peer %d violation +%.0f (%s), score %.1f" % [p.peer_id, weight, why, score])
	if score >= float(NetProtocol.VIOLATION_KICK_SCORE):
		_log(NetProtocol.LogLevel.WARN, "peer %d kicked: protocol violations (%s)" % [p.peer_id, why])
		kick.call(p.peer_id, NetProtocol.KickReason.PROTOCOL_VIOLATION, "")


## Phase / stage permission of a message received from `p` (spec 4.3 "Allowed when").
func allows(p: NetPeerInfo, type: int) -> bool:
	var playing: bool = phase == NetSession.Phase.PLAYING or phase == NetSession.Phase.PAUSED
	match type:
		NetProtocol.Msg.JOIN_REQUEST:
			return p.stage == NetPeerInfo.Stage.HANDSHAKE
		NetProtocol.Msg.LOBBY_ACTION:
			return p.stage == NetPeerInfo.Stage.LOBBY and (phase == NetSession.Phase.LOBBY or phase == NetSession.Phase.COUNTDOWN)
		NetProtocol.Msg.CHAT:
			return p.stage != NetPeerInfo.Stage.HANDSHAKE and p.stage != NetPeerInfo.Stage.LEFT
		NetProtocol.Msg.LEAVE:
			return p.stage != NetPeerInfo.Stage.LEFT
		NetProtocol.Msg.MAP_PING:
			return playing and p.stage == NetPeerInfo.Stage.PLAYING
		NetProtocol.Msg.LOAD_PROGRESS, NetProtocol.Msg.LOAD_DONE, NetProtocol.Msg.LOAD_FAILED:
			return phase == NetSession.Phase.LOADING and (p.stage == NetPeerInfo.Stage.LOADING \
				or (p.stage == NetPeerInfo.Stage.LOADED and type != NetProtocol.Msg.LOAD_PROGRESS))
		NetProtocol.Msg.TURN_INPUT, NetProtocol.Msg.PONG, NetProtocol.Msg.PAUSE_REQUEST:
			return playing and p.stage == NetPeerInfo.Stage.PLAYING
		NetProtocol.Msg.CHECKSUM_REPORT:
			return (playing or phase == NetSession.Phase.ENDED or phase == NetSession.Phase.DESYNCED) and p.stage == NetPeerInfo.Stage.PLAYING
		NetProtocol.Msg.PARTS_REPORT:
			return phase == NetSession.Phase.DESYNCED and p.stage == NetPeerInfo.Stage.PLAYING
	return false


## One received packet. Validation order: known type, direction, size, channel, permission, rate; then the handler.
func on_packet(peer_id: int, channel: int, data: PackedByteArray, now_us: int) -> void:
	var p: NetPeerInfo = peers.get(peer_id) as NetPeerInfo
	if p == null or p.stage == NetPeerInfo.Stage.LEFT:
		return
	if data.is_empty():
		violate(p, 3.0, "empty packet", now_us)
		return
	var type: int = data[0]
	if not NetProtocol.is_known_msg(type):
		violate(p, 2.0, "unknown type", now_us)
		return
	if NetProtocol.msg_dir(type) == NetProtocol.DIR_H2C:
		violate(p, 1.0, "wrong direction " + NetProtocol.msg_name(type), now_us)
		return
	if data.size() > NetProtocol.msg_max_bytes(type):
		if type == NetProtocol.Msg.TURN_INPUT and allows(p, type) and on_oversize_input.is_valid():
			on_oversize_input.call(p, type, data)
		violate(p, 3.0, "oversize " + NetProtocol.msg_name(type), now_us)
		return
	if channel != NetProtocol.msg_channel(type):
		violate(p, 1.0, "wrong channel", now_us)
		return
	if not allows(p, type):
		violate(p, 1.0, "wrong phase " + NetProtocol.msg_name(type), now_us)
		return
	var rc: int = NetProtocol.msg_rate_class(type)
	if rc >= 0 and not p.limiter.allow(rc, now_us):
		violate(p, 1.0, "rate " + NetProtocol.msg_name(type), now_us)
		return
	var h: Callable = handlers.get(type, Callable()) as Callable
	if not h.is_valid():
		return
	var w: float = float(h.call(p, data, now_us))
	if w > 0.0 and peers.has(p.peer_id):
		violate(p, w, NetProtocol.msg_name(type), now_us)
