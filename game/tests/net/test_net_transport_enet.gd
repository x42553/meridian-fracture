extends RefCounted
## NET-2: NetTransportEnet over real sockets on 127.0.0.1 (test port range 28100 + pid % 300; never 27614/27615).


func _base_port(offset: int = 0) -> int:
	return 28100 + OS.get_process_id() % 300 + offset


## Polls every transport until `pred` is true or `ms` elapsed (real time). Collects all events per transport.
func _pump(transports: Array, sinks: Array, pred: Callable, ms: int = 3000) -> bool:
	var deadline: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		for i in transports.size():
			var xport: NetTransport = transports[i] as NetTransport
			xport.poll()
			(sinks[i] as Array).append_array(xport.take_events())
			xport.flush()
		if pred.call():
			return true
		OS.delay_msec(1)
	return false


func _count(events: Array, kind: int) -> int:
	var n: int = 0
	for e: NetTransportEvent in events:
		if e.kind == kind:
			n += 1
	return n


func _pair(t: TestCtx, port_off: int, address: String = "127.0.0.1") -> Array:
	var host: NetTransportEnet = NetTransportEnet.new()
	var client: NetTransportEnet = NetTransportEnet.new()
	t.eq(host.listen(_base_port(port_off), 8), OK)
	t.eq(host.local_port(), _base_port(port_off))
	t.eq(client.connect_to(address, host.local_port(), NetProtocol.connect_data()), OK)
	var hs: Array = []
	var cs: Array = []
	var connected: bool = _pump([host, client], [hs, cs], func() -> bool: return _count(hs, 1) >= 1 and _count(cs, 1) >= 1)
	t.check(connected, "connected")
	return [host, client, hs, cs]


func test_connect_data_and_ids(t: TestCtx) -> void:
	var p: Array = _pair(t, 0)
	var host: NetTransportEnet = p[0]
	var client: NetTransportEnet = p[1]
	var hs: Array = p[2]
	var cs: Array = p[3]
	var he: NetTransportEvent = hs[0]
	t.eq(he.kind, NetTransportEvent.Kind.CONNECTED)
	t.eq(he.peer_id, 2, "first remote client is 2")
	t.eq(he.code, NetProtocol.connect_data(), "connect data reaches the host")
	t.eq(he.address, "127.0.0.1")
	t.eq((cs[0] as NetTransportEvent).peer_id, 1, "the server is peer 1")
	t.eq(host.peer_state(2), NetProtocol.PeerState.CONNECTED)
	t.eq(client.peer_state(1), NetProtocol.PeerState.CONNECTED)
	t.eq(host.peer_ids(), PackedInt32Array([2]))
	t.eq(client.peer_address(1), "127.0.0.1")
	# messages both ways on every channel; channel 3 is refused without touching the engine
	t.eq(client.send(1, 3, PackedByteArray([1])), ERR_INVALID_PARAMETER)
	for ch in 3:
		t.eq(client.send(1, ch, PackedByteArray([ch, 7])), OK)
		t.eq(host.send(2, ch, PackedByteArray([ch, 8, 8])), OK)
	_pump([host, client], [hs, cs], func() -> bool: return _count(hs, 3) >= 3 and _count(cs, 3) >= 3)
	t.eq(_count(hs, 3), 3)
	t.eq(_count(cs, 3), 3)
	var st: NetPeerStats = host.peer_stats(2)
	t.check(st.bytes_in >= 6 and st.bytes_out >= 9, "byte counters")
	t.check(st.rtt_ms >= 0.0 and st.packet_loss >= 0.0)
	t.check(host.pop_traffic()[3] > 0, "ENet packet counters")
	host.close()
	client.close()


func test_four_megabyte_message_intact_and_ordered(t: TestCtx) -> void:
	t.set_timeout(30.0)
	var p: Array = _pair(t, 1)
	var host: NetTransportEnet = p[0]
	var client: NetTransportEnet = p[1]
	var hs: Array = p[2]
	var cs: Array = p[3]
	var big: PackedByteArray = PackedByteArray()
	big.resize(4 * 1024 * 1024)
	for i in big.size():
		big[i] = (i * 31 + (i >> 8)) & 0xFF
	t.eq(host.send(2, NetProtocol.CH_BULK, big), OK)
	t.eq(host.send(2, NetProtocol.CH_BULK, PackedByteArray([1, 2, 3])), OK)
	_pump([host, client], [hs, cs], func() -> bool: return _count(cs, 3) >= 2, 20000)
	var got: Array[NetTransportEvent] = []
	for e: NetTransportEvent in cs:
		if e.kind == NetTransportEvent.Kind.PACKET:
			got.append(e)
	t.eq(got.size(), 2)
	if got.size() == 2:
		t.eq(got[0].data.size(), big.size())
		t.check(got[0].data == big, "4 MB payload identical")
		t.eq(got[1].data, PackedByteArray([1, 2, 3]), "small message after the big one")
	host.close()
	client.close()


func test_graceful_disconnect_code_after_kicked_message(t: TestCtx) -> void:
	var p: Array = _pair(t, 2)
	var host: NetTransportEnet = p[0]
	var client: NetTransportEnet = p[1]
	var hs: Array = p[2]
	var cs: Array = p[3]
	cs.clear()
	var kicked: PackedByteArray = NetLobbyCodec.encode_kicked({"reason": NetProtocol.KickReason.KICKED_BY_HOST, "detail": "bye"})
	host.send(2, NetProtocol.CH_CTRL, kicked)
	host.disconnect_peer(2, 4242, true)
	var ok: bool = _pump([host, client], [hs, cs], func() -> bool: return _count(cs, 2) >= 1)
	t.check(ok, "disconnect arrived")
	t.eq(cs.size(), 2)
	if cs.size() == 2:
		t.eq((cs[0] as NetTransportEvent).kind, NetTransportEvent.Kind.PACKET, "KICKED first")
		t.eq(NetLobbyCodec.decode_kicked((cs[0] as NetTransportEvent).data)["reason"], 1)
		t.eq((cs[1] as NetTransportEvent).kind, NetTransportEvent.Kind.DISCONNECTED)
		t.eq((cs[1] as NetTransportEvent).code, 4242, "disconnect code")
	t.eq(client.peer_state(1), NetProtocol.PeerState.GONE)
	# the host learns about the completed disconnect too; stats of the dead peer are never read from the engine
	_pump([host, client], [hs, cs], func() -> bool: return _count(hs, 2) >= 1)
	t.eq(host.peer_state(2), NetProtocol.PeerState.GONE)
	t.eq(host.peer_stats(2).bytes_in, 0)
	t.eq(client.peer_stats(1).rtt_ms, 0.0)
	t.eq(client.send(1, 0, PackedByteArray([1])), ERR_UNAVAILABLE)
	host.close()
	client.close()


func test_client_initiated_hard_disconnect(t: TestCtx) -> void:
	var p: Array = _pair(t, 3)
	var host: NetTransportEnet = p[0]
	var client: NetTransportEnet = p[1]
	var hs: Array = p[2]
	var cs: Array = p[3]
	hs.clear()
	client.disconnect_peer(1, 99, false)
	t.eq(client.peer_state(1), NetProtocol.PeerState.GONE)
	_pump([host, client], [hs, cs], func() -> bool: return _count(hs, 2) >= 1)
	t.eq(_count(hs, 2), 1)
	t.eq((hs[0] as NetTransportEvent).code, 99)
	t.eq(_count(cs, 2), 0, "no local event for a hard disconnect")
	host.close()
	client.close()


func test_close_notifies_remote_quickly(t: TestCtx) -> void:
	var p: Array = _pair(t, 4)
	var host: NetTransportEnet = p[0]
	var client: NetTransportEnet = p[1]
	var hs: Array = p[2]
	var cs: Array = p[3]
	cs.clear()
	host.close()
	_pump([client], [cs], func() -> bool: return _count(cs, 2) >= 1)
	t.eq(_count(cs, 2), 1)
	t.eq(host.local_port(), 0)
	t.eq(host.peer_ids().size(), 0)
	host.close()
	client.close()
	t.check(hs.size() > 0)


func test_port_scan_is_quiet(t: TestCtx) -> void:
	var a: PacketPeerUDP = PacketPeerUDP.new()
	var b: PacketPeerUDP = PacketPeerUDP.new()
	var base: int = _base_port(10)
	t.eq(a.bind(base, "*"), OK)
	t.eq(b.bind(base + 1, "*"), OK)
	var host: NetTransportEnet = NetTransportEnet.new()
	t.eq(host.listen(base, 4), OK)
	t.eq(host.local_port(), base + 2, "scan skipped the two occupied ports")
	var second: NetTransportEnet = NetTransportEnet.new()
	t.eq(second.listen(base, 4), OK)
	t.eq(second.local_port(), base + 3)
	t.eq(second.listen(base, 4), ERR_ALREADY_IN_USE, "one listen per transport")
	host.close()
	second.close()
	a.close()
	b.close()
	# all ten candidates busy => ERR_ALREADY_IN_USE and still no engine error
	var socks: Array[PacketPeerUDP] = []
	for i in NetProtocol.PORT_SCAN_COUNT:
		var s: PacketPeerUDP = PacketPeerUDP.new()
		t.eq(s.bind(base + 20 + i, "*"), OK)
		socks.append(s)
	var none: NetTransportEnet = NetTransportEnet.new()
	t.eq(none.listen(base + 20, 4), ERR_ALREADY_IN_USE)
	for s in socks:
		s.close()


func test_connect_to_closed_port_times_out_in_six_seconds(t: TestCtx) -> void:
	t.set_timeout(20.0)
	var client: NetTransportEnet = NetTransportEnet.new()
	var t0: int = Time.get_ticks_msec()
	t.eq(client.connect_to("127.0.0.1", _base_port(30), NetProtocol.connect_data()), OK, "returns immediately")
	t.eq(client.peer_state(1), NetProtocol.PeerState.CONNECTING)
	var cs: Array = []
	var done: bool = _pump([client], [cs], func() -> bool: return cs.size() >= 1, 9000)
	var elapsed: int = Time.get_ticks_msec() - t0
	t.check(done, "reported")
	t.eq(cs.size(), 1)
	if cs.size() == 1:
		t.eq((cs[0] as NetTransportEvent).kind, NetTransportEvent.Kind.DISCONNECTED)
		t.eq((cs[0] as NetTransportEvent).peer_id, 1)
	t.check(elapsed >= 5990 and elapsed <= 6500, "connect timeout %d ms" % elapsed)
	t.eq(client.peer_state(1), NetProtocol.PeerState.GONE)
	client.close()


func test_dual_stack(t: TestCtx) -> void:
	var host: NetTransportEnet = NetTransportEnet.new()
	t.eq(host.listen(_base_port(40), 8), OK)
	var hs: Array = []
	var c4: NetTransportEnet = NetTransportEnet.new()
	var s4: Array = []
	c4.connect_to("127.0.0.1", host.local_port(), 1)
	t.check(_pump([host, c4], [hs, s4], func() -> bool: return _count(s4, 1) >= 1), "IPv4 connect")
	var c6: NetTransportEnet = NetTransportEnet.new()
	var s6: Array = []
	c6.connect_to("::1", host.local_port(), 2)
	var ok6: bool = _pump([host, c6], [hs, s6], func() -> bool: return _count(s6, 1) >= 1 and _count(hs, 1) >= 2, 2500)
	if ok6:
		t.eq(_count(hs, 1), 2)
	else:
		t.note("IPv6 loopback unavailable on this machine; skipped")
	# a hostname is resolved asynchronously
	var ch: NetTransportEnet = NetTransportEnet.new()
	var sh: Array = []
	ch.connect_to("localhost", host.local_port(), 3)
	t.check(_pump([host, ch], [hs, sh], func() -> bool: return _count(sh, 1) >= 1, 5000), "hostname connect")
	host.close()
	c4.close()
	c6.close()
	ch.close()


func test_timeouts_apply_to_all_peers(t: TestCtx) -> void:
	var host: NetTransportEnet = NetTransportEnet.new()
	host.set_timeouts(NetProtocol.TIMEOUTS_LOBBY[0], NetProtocol.TIMEOUTS_LOBBY[1], NetProtocol.TIMEOUTS_LOBBY[2])
	t.eq(host.listen(_base_port(50), 8), OK)
	var client: NetTransportEnet = NetTransportEnet.new()
	client.connect_to("127.0.0.1", host.local_port(), 1)
	var hs: Array = []
	var cs: Array = []
	_pump([host, client], [hs, cs], func() -> bool: return _count(hs, 1) >= 1 and _count(cs, 1) >= 1)
	host.set_timeouts(NetProtocol.TIMEOUTS_GAME[0], NetProtocol.TIMEOUTS_GAME[1], NetProtocol.TIMEOUTS_GAME[2])
	client.set_timeouts(NetProtocol.TIMEOUTS_LOADING[0], NetProtocol.TIMEOUTS_LOADING[1], NetProtocol.TIMEOUTS_LOADING[2])
	t.eq(host.send(2, 0, PackedByteArray([1])), OK, "connection still healthy")
	host.close()
	client.close()
