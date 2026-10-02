extends RefCounted
## NET-10: message matrix and violation scoring (docs/spec/net.md 4.3, 5.12): oversize, truncated, wrong phase, wrong role
## and unknown messages are dropped and scored while the session survives; 12 points kick; connection limits;
## handshake timeout; connect magic; zip bomb; hostile host messages; bundle corruption.

const P := NetSession.Phase


func _kit() -> NetSessionKit:
	return NetSessionKit.new()


## A raw peer that completed the join handshake (stage LOBBY on the host).
func _joined_raw(kit: NetSessionKit, name: String, address: String = "") -> NetTransportLoopback:
	var ep: NetTransportLoopback = kit.raw_peer(address)
	kit.step(1)
	ep.poll()
	ep.send(1, 0, NetCodec.encode_join_request({"proto_version": 1, "sim_version": 1, "data_hash": NetSessionKit.DATA_HASH,
		"client_nonce": randi(), "game_version": "0.0.1", "name": name}))
	kit.step(2)
	return ep


func _kicked_code(kit: NetSessionKit, ep: NetTransportLoopback) -> Array:
	var out: Array = [-1, -1]
	for e: NetTransportEvent in kit.raw_take(ep):
		if e.kind == NetTransportEvent.Kind.PACKET and e.data[0] == NetProtocol.Msg.KICKED:
			out[0] = int(NetLobbyCodec.decode_kicked(e.data)["reason"])
		elif e.kind == NetTransportEvent.Kind.DISCONNECTED:
			out[1] = e.code
	return out


func test_scoring_per_message_class(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host")
	var friend: NetSession = kit.join("Friend")
	kit.all_in(P.LOBBY, 50)
	var M := NetProtocol.Msg
	# (type, body length, expected points, label); the host is in LOBBY, the raw peer is a seated human
	var cases: Array = [
		[M.LOBBY_ACTION, 81, 3, "oversize LOBBY_ACTION"],
		[M.LOBBY_ACTION, 1, 3, "truncated LOBBY_ACTION"],
		[M.CHAT, 261, 3, "oversize CHAT"],
		[M.CHAT, 1, 3, "truncated CHAT"],
		[M.LEAVE, 5, 3, "oversize LEAVE"],
		[M.LEAVE, 0, 3, "truncated LEAVE"],
		[M.MAP_PING, 3, 1, "MAP_PING outside a match"],
		[M.LOAD_PROGRESS, 1, 1, "LOAD_PROGRESS outside loading"],
		[M.LOAD_DONE, 8, 1, "LOAD_DONE outside loading"],
		[M.LOAD_FAILED, 3, 1, "LOAD_FAILED outside loading"],
		[M.TURN_INPUT, 9, 1, "TURN_INPUT in the lobby"],
		[M.TURN_INPUT, 6200, 3, "oversize TURN_INPUT"],
		[M.PONG, 20, 1, "PONG in the lobby"],
		[M.PAUSE_REQUEST, 1, 1, "PAUSE_REQUEST in the lobby"],
		[M.CHECKSUM_REPORT, 12, 1, "CHECKSUM_REPORT in the lobby"],
		[M.PARTS_REPORT, 5, 1, "PARTS_REPORT in the lobby"],
		[M.JOIN_REQUEST, 26, 1, "second JOIN_REQUEST"],
		[M.JOIN_ACCEPT, 9, 1, "wrong role: JOIN_ACCEPT"],
		[M.LOBBY_SNAPSHOT, 10, 1, "wrong role: LOBBY_SNAPSHOT"],
		[M.KICKED, 3, 1, "wrong role: KICKED"],
		[M.LAUNCH_COUNTDOWN, 1, 1, "wrong role: LAUNCH_COUNTDOWN"],
		[M.START, 7, 1, "wrong role: START"],
		[M.TURN_BUNDLE, 10, 1, "wrong role: TURN_BUNDLE"],
		[M.PING, 8, 1, "wrong role: PING"],
		[M.DESYNC_NOTICE, 7, 1, "wrong role: DESYNC_NOTICE"],
		[M.MATCH_END, 10, 1, "wrong role: MATCH_END"],
		[0x99, 4, 2, "unknown type"],
	]
	var i: int = 0
	for c: Variant in cases:
		var row: Array = c as Array
		# a fresh seated peer per case (each case can kick at 12 points only after several packets)
		var ep: NetTransportLoopback = _joined_raw(kit, "Raw%d" % i, "10.9.%d.%d" % [i / 200, i % 200 + 1])
		var before: int = h.violation_total()
		var body: PackedByteArray = PackedByteArray()
		body.resize(int(row[1]))
		var msg: PackedByteArray = PackedByteArray([int(row[0])])
		msg.append_array(body)
		ep.send(1, NetProtocol.msg_channel(int(row[0])) if NetProtocol.is_known_msg(int(row[0])) else 0, msg)
		kit.step(2)
		t.eq(h.violation_total() - before, int(row[2]), str(row[3]))
		t.eq(h.phase, P.LOBBY, "the session survives: " + str(row[3]))
		ep.disconnect_peer(1, 0, true)
		kit.step(1)
		i += 1
	t.eq(friend.phase, P.LOBBY, "well-behaved peers are unaffected")
	kit.shutdown_all()


func test_twelve_points_kick_with_protocol_violation(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host")
	var ep: NetTransportLoopback = _joined_raw(kit, "Spammer")
	t.eq(h.lobby.state.human_count(), 2)
	for _i: int in 10:
		ep.send(1, 1, PackedByteArray([NetProtocol.Msg.PONG, 0, 0]))
	kit.step(1)
	t.eq(h.lobby.state.human_count(), 2, "10 points: still connected")
	for _i: int in 3:
		ep.send(1, 1, PackedByteArray([NetProtocol.Msg.PONG, 0, 0]))
	kit.step(2)
	var res: Array = _kicked_code(kit, ep)
	t.eq(res[0], NetProtocol.KickReason.PROTOCOL_VIOLATION)
	t.eq(res[1], NetProtocol.KickReason.PROTOCOL_VIOLATION)
	t.eq(h.lobby.state.human_count(), 1, "the slot is free again")
	# the violation score decays: 1 point per 5 s
	var ep2: NetTransportLoopback = _joined_raw(kit, "Slow")
	for _i: int in 7:
		ep2.send(1, 1, PackedByteArray([NetProtocol.Msg.PONG, 0, 0]))
	kit.step(1)
	kit.step(4, 5_000_000)
	for _i: int in 7:
		ep2.send(1, 1, PackedByteArray([NetProtocol.Msg.PONG, 0, 0]))
	kit.step(2)
	t.eq(h.lobby.state.human_count(), 2, "14 points spread over 20 s do not kick (decay 1 per 5 s)")
	kit.shutdown_all()


func test_connection_limits_handshake_timeout_and_magic(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host")
	# 4 connections per IP are fine, the 5th is refused with TOO_MANY_CONNECTIONS
	var same: Array = []
	for _i: int in 5:
		same.append(kit.raw_peer("10.7.7.7"))
	kit.step(2)
	var codes: Array = []
	for ep: Variant in same:
		var code: int = -1
		for e: NetTransportEvent in kit.raw_take(ep as NetTransportLoopback):
			if e.kind == NetTransportEvent.Kind.DISCONNECTED:
				code = e.code
		codes.append(code)
	t.eq(codes, [-1, -1, -1, -1, NetProtocol.RejectReason.TOO_MANY_CONNECTIONS])
	t.eq(h.peer_count(), 4)
	# the 9th unauthenticated peer (different IPs) is refused
	var many: Array = []
	for i: int in 6:
		many.append(kit.raw_peer("10.8.8.%d" % (i + 1)))
	kit.step(2)
	t.eq(h.peer_count(), 8, "8 unauthenticated peers at most")
	var refused: int = 0
	for ep2: Variant in many:
		for e2: NetTransportEvent in kit.raw_take(ep2 as NetTransportLoopback):
			if e2.kind == NetTransportEvent.Kind.DISCONNECTED and e2.code == NetProtocol.RejectReason.TOO_MANY_CONNECTIONS:
				refused += 1
	t.eq(refused, 2)
	# a peer that never sends JOIN_REQUEST is dropped after 5 s
	kit.step(5, 1_000_000)
	t.eq(h.peer_count(), 0, "handshake timeout after 5 s")
	# wrong connect magic: disconnect_now, never a record
	var bad: NetTransportLoopback = kit.raw_peer("10.6.6.6", 0x1234)
	kit.step(2)
	t.eq(h.peer_count(), 0)
	var dropped: bool = false
	for e3: NetTransportEvent in kit.raw_take(bad):
		dropped = dropped or e3.kind == NetTransportEvent.Kind.DISCONNECTED
	t.check(dropped, "wrong connect magic is disconnected at once")
	kit.shutdown_all()


func test_zip_bomb_config_is_refused(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host")
	var c: NetSession = kit.join("Bob")
	kit.all_in(P.LOBBY, 50)
	# the codec refuses a bomb: inflate is bounded by MAX_CONFIG_JSON
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(8 * 1024 * 1024)
	var comp: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var w: NetWriter = NetWriter.new().u8(NetProtocol.Msg.LAUNCH_CONFIG).u32(100).u32(0x12345678)
	w.raw(comp)
	var bomb: PackedByteArray = w.to_bytes()
	t.le(bomb.size(), NetProtocol.MAX_LAUNCH_PACKET)
	t.expect_errors(2)
	t.eq(NetLobbyCodec.inflate_config(bomb), "")
	# a hostile host sending it to a client in the lobby: LOAD_FAILED(CONFIG_INVALID), no crash
	var errors: PackedInt32Array = PackedInt32Array([0])
	kit.log_lines.clear()
	h.transport.send(2, 0, bomb)
	kit.step(4)
	t.eq(c.phase, P.LOBBY, "the client stays in the lobby")
	t.eq(h.phase, P.LOBBY)
	t.check(errors[0] == 0)
	kit.shutdown_all()


func test_hostile_host_messages_are_ignored_by_clients(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host")
	var c: NetSession = kit.join("Bob")
	kit.all_in(P.LOBBY, 50)
	# client-to-host messages arriving at the client, garbage, oversize
	h.transport.send(2, 1, NetCodec.encode_turn_input({"turn": 3, "exec_turn": 1, "cmds": []}))
	h.transport.send(2, 0, PackedByteArray([0x99, 1, 2]))
	h.transport.send(2, 0, PackedByteArray([NetProtocol.Msg.TURN_BUNDLE, 1]))
	h.transport.send(2, 0, PackedByteArray([NetProtocol.Msg.START, 1, 2, 3]))
	h.transport.send(2, 0, PackedByteArray([NetProtocol.Msg.LAUNCH_ABORT, 1, 255, 0]))
	h.transport.send(2, 0, PackedByteArray([NetProtocol.Msg.RETURN_TO_LOBBY]))
	kit.step(4)
	t.eq(c.phase, P.LOBBY)
	t.eq(h.phase, P.LOBBY)
	# a KICKED from the host is honoured
	h.transport.send(2, 0, NetLobbyCodec.encode_kicked({"reason": NetProtocol.KickReason.KICKED_BY_HOST, "detail": "bye"}))
	kit.step(4)
	t.eq(c.phase, P.DISCONNECTED)
	kit.shutdown_all()


func test_corrupted_bundle_is_a_protocol_error_not_a_desync(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var fault: Array = [null]
	var host_opts: Dictionary = {"transport_factory": func() -> NetTransport:
		var ep: NetTransportLoopback = kit.hub.endpoint(500)
		ep.address = "10.0.0.1"
		var f: NetTransportFault = NetTransportFault.wrap(ep, NetFaultProfile.preset("local"), kit.clock(), 7)
		fault[0] = f
		return f}
	var h: NetSession = kit.host("Host", host_opts)
	var c: NetSession = kit.join("Bob")
	kit.all_in(P.LOBBY, 50)
	h.lobby.set_team(1)
	c.lobby.set_team(2)
	c.lobby.set_ready(true)
	kit.step(4)
	var errs: Array = []
	var desyncs: Array = []
	c.net_error.connect(func(code: int, text: String) -> void: errs.append([code, text]))
	c.desync_detected.connect(func(r: Dictionary) -> void: desyncs.append(r))
	h.lobby.host_start()
	t.check(kit.all_in(P.PLAYING, 200))
	kit.step(20)
	(fault[0] as NetTransportFault).corrupt_next(2, NetProtocol.CH_TURN)
	kit.step(40)
	t.check(errs.any(func(e: Array) -> bool: return int(e[0]) == NetProtocol.NetErrorCode.HOST_PROTOCOL), "net_error(HOST_PROTOCOL): %s" % str(errs))
	t.eq(desyncs.size(), 0, "a corrupted bundle is not a desync")
	kit.shutdown_all()
