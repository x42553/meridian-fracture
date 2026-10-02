extends RefCounted
## NET-2: NetClock, NetTransportLoopback / NetLoopbackHub semantics, NetPeerStats, NetRateLimiter.


func _connected_pair(hub: NetLoopbackHub) -> Array[NetTransportLoopback]:
	var host: NetTransportLoopback = hub.endpoint(1)
	var client: NetTransportLoopback = hub.endpoint(2)
	host.listen(27615, 8)
	client.connect_to("127.0.0.1", host.local_port(), 0xABCD1234)
	host.poll()
	client.poll()
	host.take_events()
	client.take_events()
	var out: Array[NetTransportLoopback] = [host, client]
	return out


func _packets(xport: NetTransport) -> Array[NetTransportEvent]:
	xport.poll()
	return xport.take_events()


func test_clock(t: TestCtx) -> void:
	var m: NetClock = NetClock.manual(1000)
	t.eq(m.now_us(), 1000)
	m.advance_us(250)
	t.eq(m.now_us(), 1250)
	t.eq(m.now_ms(), 1)
	m.set_us(5_000_000)
	t.eq(m.now_ms(), 5000)
	t.check(m.is_manual())
	var r: NetClock = NetClock.real()
	var a: int = r.now_us()
	var b: int = r.now_us()
	t.check(b >= a and not r.is_manual(), "real clock is monotonic")


func test_connect_events_and_ids(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	var host: NetTransportLoopback = hub.endpoint(1)
	var c1: NetTransportLoopback = hub.endpoint(2)
	var c2: NetTransportLoopback = hub.endpoint(3)
	t.eq(host.listen(27615, 8), OK)
	t.eq(host.local_port(), 27615)
	c1.address = "10.0.0.2"
	t.eq(c1.connect_to("h", 27615, 0x4D460001), OK)
	t.eq(c2.connect_to("h", 27615, 77), OK)
	t.eq(c1.peer_state(1), NetProtocol.PeerState.CONNECTING, "connecting until the CONNECTED event was polled")
	var he: Array[NetTransportEvent] = _packets(host)
	t.eq(he.size(), 2)
	t.eq(he[0].kind, NetTransportEvent.Kind.CONNECTED)
	t.eq(he[0].peer_id, 2)
	t.eq(he[0].code, 0x4D460001)
	t.eq(he[0].address, "10.0.0.2")
	t.eq(he[1].peer_id, 3)
	t.eq(he[1].code, 77)
	var ce: Array[NetTransportEvent] = _packets(c1)
	t.eq(ce.size(), 1)
	t.eq(ce[0].peer_id, 1, "server is peer 1")
	t.eq(c1.peer_state(1), NetProtocol.PeerState.CONNECTED)
	t.eq(host.peer_ids(), PackedInt32Array([2, 3]))
	t.eq(host.peer_address(2), "10.0.0.2")
	t.eq(host.peer_state(9), NetProtocol.PeerState.GONE)
	t.eq(c1.connect_to("h", 27615, 0), ERR_ALREADY_IN_USE)


func test_ordering_per_channel_and_isolation(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	var p: Array[NetTransportLoopback] = _connected_pair(hub)
	for i in 50:
		t.eq(p[0].send(2, i % 3, PackedByteArray([i])), OK)
	var got: Array[NetTransportEvent] = _packets(p[1])
	t.eq(got.size(), 50)
	var last: Array[int] = [-1, -1, -1]
	for e in got:
		var v: int = e.data[0]
		t.check(v > last[e.channel], "channel %d in order" % e.channel)
		last[e.channel] = v
		t.eq(v % 3, e.channel, "payload stays on its channel")
	t.eq(_packets(p[1]).size(), 0, "take_events drains")
	# both directions
	p[1].send(1, NetProtocol.CH_CTRL, PackedByteArray([9, 9]))
	var back: Array[NetTransportEvent] = _packets(p[0])
	t.eq(back.size(), 1)
	t.eq(back[0].peer_id, 2)
	t.eq(back[0].data, PackedByteArray([9, 9]))


func test_send_validation(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	var p: Array[NetTransportLoopback] = _connected_pair(hub)
	t.eq(p[0].send(2, 3, PackedByteArray([1])), ERR_INVALID_PARAMETER, "channel 3 is never sent")
	t.eq(p[0].send(2, -1, PackedByteArray([1])), ERR_INVALID_PARAMETER)
	t.eq(p[0].send(2, 0, PackedByteArray()), ERR_INVALID_PARAMETER, "empty message")
	t.eq(p[0].send(99, 0, PackedByteArray([1])), ERR_UNAVAILABLE, "unknown peer")
	t.eq(_packets(p[1]).size(), 0)


func test_graceful_disconnect_delivers_queued_packets_first(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	var p: Array[NetTransportLoopback] = _connected_pair(hub)
	p[0].send(2, 0, PackedByteArray([1, 2, 3]))
	p[0].send(2, 0, PackedByteArray([4]))
	p[0].disconnect_peer(2, 4242, true)
	var got: Array[NetTransportEvent] = _packets(p[1])
	t.eq(got.size(), 3)
	t.eq(got[0].kind, NetTransportEvent.Kind.PACKET)
	t.eq(got[1].kind, NetTransportEvent.Kind.PACKET)
	t.eq(got[2].kind, NetTransportEvent.Kind.DISCONNECTED)
	t.eq(got[2].code, 4242)
	t.eq(got[2].peer_id, 1)
	t.eq(p[1].peer_state(1), NetProtocol.PeerState.GONE)
	var mine: Array[NetTransportEvent] = _packets(p[0])
	t.eq(mine.size(), 1, "graceful: the local side also reports the disconnect")
	t.eq(mine[0].kind, NetTransportEvent.Kind.DISCONNECTED)
	t.eq(p[0].peer_state(2), NetProtocol.PeerState.GONE)


func test_hard_disconnect_drops_queued_packets_and_is_silent_locally(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	var p: Array[NetTransportLoopback] = _connected_pair(hub)
	p[0].send(2, 0, PackedByteArray([1]))
	p[0].disconnect_peer(2, 7, false)
	var got: Array[NetTransportEvent] = _packets(p[1])
	t.eq(got.size(), 1)
	t.eq(got[0].kind, NetTransportEvent.Kind.DISCONNECTED)
	t.eq(got[0].code, 7)
	t.eq(_packets(p[0]).size(), 0, "no local event for a hard disconnect")
	t.eq(p[0].send(2, 0, PackedByteArray([1])), ERR_UNAVAILABLE)


func test_close_disconnects_remotes(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	var p: Array[NetTransportLoopback] = _connected_pair(hub)
	p[0].close()
	var got: Array[NetTransportEvent] = _packets(p[1])
	t.eq(got.size(), 1)
	t.eq(got[0].kind, NetTransportEvent.Kind.DISCONNECTED)
	t.eq(got[0].code, 0)
	t.eq(p[0].local_port(), 0)
	# the port is free again
	var other: NetTransportLoopback = hub.endpoint(9)
	t.eq(other.listen(27615, 4), OK)
	t.eq(other.local_port(), 27615)


func test_port_scan_and_capacity(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	hub.reserve_port(27615)
	hub.reserve_port(27616)
	var host: NetTransportLoopback = hub.endpoint(1)
	t.eq(host.listen(27615, 1), OK)
	t.eq(host.local_port(), 27617, "first two ports occupied")
	var full: NetLoopbackHub = NetLoopbackHub.new()
	for p in range(28000, 28010):
		full.reserve_port(p)
	t.eq(full.endpoint(1).listen(28000, 4), ERR_ALREADY_IN_USE)
	# max_peers = 1: the second client is refused after the connect timeout
	var c1: NetTransportLoopback = hub.endpoint(2)
	var c2: NetTransportLoopback = hub.endpoint(3)
	c1.connect_to("h", 27617, 0)
	c2.connect_to("h", 27617, 0)
	t.eq(_packets(c1).size(), 1)
	t.eq(_packets(c2).size(), 0, "no answer yet")
	hub.clock.advance_us(NetProtocol.CONNECT_TIMEOUT_MS * 1000 - 1)
	t.eq(_packets(c2).size(), 0)
	hub.clock.advance_us(1)
	var ev: Array[NetTransportEvent] = _packets(c2)
	t.eq(ev.size(), 1)
	t.eq(ev[0].kind, NetTransportEvent.Kind.DISCONNECTED)
	t.eq(c2.peer_state(1), NetProtocol.PeerState.GONE)


func test_connect_to_missing_port_times_out(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	var c: NetTransportLoopback = hub.endpoint(2)
	c.connect_to("127.0.0.1", 27615, 0)
	t.eq(_packets(c).size(), 0)
	hub.clock.advance_us(5_999_000)
	t.eq(_packets(c).size(), 0)
	hub.clock.advance_us(1_000)
	var ev: Array[NetTransportEvent] = _packets(c)
	t.eq(ev.size(), 1)
	t.eq(ev[0].kind, NetTransportEvent.Kind.DISCONNECTED)
	t.eq(ev[0].peer_id, 1)


func test_connect_endpoints_and_deliver_all(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	var a: NetTransportLoopback = hub.endpoint(1)
	var b: NetTransportLoopback = hub.endpoint(2)
	t.eq(hub.connect_endpoints(b, a, 5), 2)
	hub.deliver_all()
	t.eq(a.take_events()[0].code, 5)
	t.eq(b.take_events().size(), 1)
	b.send(1, 1, PackedByteArray([1, 2]))
	t.eq(a.take_events().size(), 0, "not delivered before deliver_all/poll")
	hub.deliver_all()
	var ev: Array[NetTransportEvent] = a.take_events()
	t.eq(ev.size(), 1)
	t.eq(ev[0].channel, 1)


func test_stats_and_traffic(t: TestCtx) -> void:
	var hub: NetLoopbackHub = NetLoopbackHub.new()
	var p: Array[NetTransportLoopback] = _connected_pair(hub)
	hub.clock.advance_us(5_000_000)
	p[0].send(2, 0, PackedByteArray([1, 2, 3]))
	p[0].send(2, 0, PackedByteArray([1, 2]))
	_packets(p[1])
	t.eq(p[0].peer_stats(2).bytes_out, 5)
	var s: NetPeerStats = p[1].peer_stats(1)
	t.eq(s.bytes_in, 5)
	t.eq(s.last_seen_ms, 5000)
	t.eq(p[0].pop_traffic(), PackedInt64Array([5, 0, 2, 0]))
	t.eq(p[0].pop_traffic(), PackedInt64Array([0, 0, 0, 0]), "counters reset on read")
	t.eq(p[1].pop_traffic(), PackedInt64Array([0, 5, 0, 2]))
	p[0].disconnect_peer(2, 0, false)
	t.eq(p[0].peer_stats(2).bytes_out, 0, "stats of a dead peer are zero")


func test_base_class_is_abstract(t: TestCtx) -> void:
	t.expect_errors(5)
	var base: NetTransport = NetTransport.new()
	t.eq(base.listen(1, 1), ERR_UNAVAILABLE)
	t.eq(base.connect_to("x", 1, 0), ERR_UNAVAILABLE)
	t.eq(base.send(1, 0, PackedByteArray([1])), ERR_UNAVAILABLE)
	base.poll()
	base.disconnect_peer(1, 0, true)
	t.eq(base.take_events().size(), 0)
	t.eq(base.local_port(), 0)


func test_peer_stats_rtt_smoothing(t: TestCtx) -> void:
	var s: NetPeerStats = NetPeerStats.new()
	s.add_rtt_sample(40.0)
	t.near(s.rtt_ms, 40.0, 0.001)
	s.add_rtt_sample(80.0)
	t.near(s.rtt_ms, 45.0, 0.001)
	t.near(s.last_rtt_ms, 80.0, 0.001)
	t.gt(s.rtt_var_ms, 0.0)
	var d: NetPeerStats = s.duplicate_stats()
	s.reset()
	t.near(d.rtt_ms, 45.0, 0.001)
	t.near(s.rtt_ms, 0.0, 0.001)


# ---- rate limiter ------------------------------------------------------------------------------------------------

func test_rate_limiter_bursts_and_refill(t: TestCtx) -> void:
	var rl: NetRateLimiter = NetRateLimiter.new()
	var now: int = 1_000_000
	# INPUT: burst 64, 40/s
	var ok: int = 0
	for _i in 100:
		if rl.allow(NetRateLimiter.Class.INPUT, now):
			ok += 1
	t.eq(ok, 64, "burst")
	now += 250_000  # +0.25 s = 10 tokens
	ok = 0
	for _i in 100:
		if rl.allow(NetRateLimiter.Class.INPUT, now):
			ok += 1
	t.eq(ok, 10, "refill 40/s")
	# CHAT: 5 per 5 s (burst 5, 1/s)
	var chat_ok: int = 0
	for i in 8:
		if rl.allow(NetRateLimiter.Class.CHAT, now + i * 100_000):
			chat_ok += 1
	t.eq(chat_ok, 5, "6th chat message within 5 s dropped")
	t.check(rl.allow(NetRateLimiter.Class.CHAT, now + 2_000_000), "one token per second later")
	t.check(rl.allow(NetRateLimiter.Class.CHAT, now + 2_000_000), "2.0 tokens had accumulated")
	t.check_false(rl.allow(NetRateLimiter.Class.CHAT, now + 2_000_000))
	# independent buckets
	t.check(rl.allow(NetRateLimiter.Class.PAUSE, now))
	t.check(rl.allow(NetRateLimiter.Class.PAUSE, now))
	t.check_false(rl.allow(NetRateLimiter.Class.PAUSE, now), "PAUSE burst 2")
	t.check(rl.allow(NetRateLimiter.Class.PAUSE, now + 1_000_000), "PAUSE 1/s")
	# an unknown class falls back to MISC (burst 10)
	var misc: int = 0
	for _i in 20:
		if rl.allow(99, now):
			misc += 1
	t.eq(misc, 10)
	# a bucket never exceeds its burst however long it idles
	var idle: int = 0
	for _i in 200:
		if rl.allow(NetRateLimiter.Class.CHECK, now + 3_600_000_000):
			idle += 1
	t.eq(idle, 8)


func test_rate_limiter_table(t: TestCtx) -> void:
	var expect: Array = [[40, 64], [8, 16], [4, 8], [10, 20], [1, 5], [1, 2], [5, 10]]
	for c in expect.size():
		var rl: NetRateLimiter = NetRateLimiter.new()
		var n: int = 0
		while rl.allow(c, 0):
			n += 1
			if n > 1000:
				break
		t.eq(n, (expect[c] as Array)[1], "burst of class %d" % c)


func test_violation_score_decays_and_kicks(t: TestCtx) -> void:
	var rl: NetRateLimiter = NetRateLimiter.new()
	t.near(rl.score(0), 0.0, 0.0001)
	t.near(rl.add_violation(3.0, 0), 3.0, 0.0001)
	t.near(rl.add_violation(3.0, 0), 6.0, 0.0001)
	t.near(rl.score(5_000_000), 5.0, 0.0001)
	t.near(rl.score(10_000_000), 4.0, 0.0001)
	t.near(rl.add_violation(3.0, 10_000_000), 7.0, 0.0001)
	t.near(rl.score(2_000_000_000), 0.0, 0.0001, "decays to zero, never negative")
	var kick: float = 0.0
	for _i in 4:
		kick = rl.add_violation(3.0, 3_000_000_000)
	t.check(kick >= float(NetProtocol.VIOLATION_KICK_SCORE), "four malformed packets reach the kick score")


func test_fault_profile_presets(t: TestCtx) -> void:
	for n in NetFaultProfile.PRESET_NAMES:
		var p: NetFaultProfile = NetFaultProfile.preset(n)
		t.not_null(p, n)
		t.eq(p.name, n)
	t.check(NetFaultProfile.preset("nope") == null)
	var bw: NetFaultProfile = NetFaultProfile.preset("bad_wifi")
	t.near(bw.latency_ms, 30.0, 0.001)
	t.near(bw.jitter_ms, 25.0, 0.001)
	t.near(bw.loss_pct, 3.0, 0.001)
	t.near(bw.effective_rto_ms(), 2.0 * 30.0 + 4.0 * 25.0 + 33.0, 0.001)
	var rc: NetFaultProfile = NetFaultProfile.preset("raw_chaos")
	t.check(not rc.ordered and rc.dup_pct == 3.0 and rc.reorder_pct == 10.0)
	var custom: NetFaultProfile = NetFaultProfile.from_dict({"preset": "lan", "name": "mine", "loss_pct": 2.5, "freeze_ms": 100, "ordered": false})
	t.eq(custom.name, "mine")
	t.near(custom.loss_pct, 2.5, 0.001)
	t.near(custom.latency_ms, 0.5, 0.001)
	t.eq(custom.freeze_ms, 100)
	t.check(not custom.ordered)
	t.check(NetFaultProfile.from_dict({"preset": "bogus"}) == null)
	t.eq(custom.duplicate_profile().to_dict(), custom.to_dict())
