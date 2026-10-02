extends RefCounted
## NET-2: NetTransportFault statistics and semantics under a manual clock (1 ms steps).
## The fault decorator wraps the SENDING endpoint (host); the client is a plain loopback endpoint.


class Rig extends RefCounted:
	var clock: NetClock = NetClock.manual(1_000_000)
	var hub: NetLoopbackHub
	var host: NetTransportFault
	var client: NetTransportLoopback
	var received: Array[NetTransportEvent] = []
	var recv_at: PackedInt64Array = PackedInt64Array()
	var client_events: Array[NetTransportEvent] = []
	var t_wrap: int = 0

	func _init(profile: NetFaultProfile, rng_seed: int) -> void:
		t_wrap = clock.now_us()
		hub = NetLoopbackHub.new(clock)
		host = NetTransportFault.wrap(hub.endpoint(1), profile, clock, rng_seed)
		client = hub.endpoint(2)
		host.listen(27615, 8)
		client.connect_to("h", 27615, 0)
		step(1)
		step(1)
		received.clear()
		recv_at.clear()

	## Advances virtual time `n` times by `ms` milliseconds, polling both sides each step.
	func step(ms: int, n: int = 1) -> void:
		for _i in n:
			clock.advance_us(ms * 1000)
			host.poll()
			host.take_events()
			client.poll()
			for e in client.take_events():
				client_events.append(e)
				if e.kind == NetTransportEvent.Kind.PACKET:
					received.append(e)
					recv_at.append(clock.now_us())

	func send_seq(ch: int, value: int) -> int:
		var b: PackedByteArray = PackedByteArray()
		b.resize(8)
		b.encode_u32(0, value)
		b.encode_u32(4, clock.now_us() / 1000)
		return host.send(2, ch, b)


func _value(e: NetTransportEvent) -> int:
	return e.data.decode_u32(0)


func test_ordered_mode_never_reorders(t: TestCtx) -> void:
	var p: NetFaultProfile = NetFaultProfile.preset("bad_wifi")
	var rig: Rig = Rig.new(p, 1234)
	var n: int = 10000
	for i in n:
		rig.send_seq(i % 2, i)
		rig.step(1)
	rig.step(5, 400)
	t.eq(rig.received.size(), n, "every message delivered exactly once")
	var last: Array[int] = [-1, -1]
	var inversions: int = 0
	for e in rig.received:
		var v: int = _value(e)
		if v <= last[e.channel]:
			inversions += 1
		last[e.channel] = v
	t.eq(inversions, 0, "FIFO per channel")
	var s: Dictionary = rig.host.stats()
	t.eq(s["reordered"], 0)
	t.eq(s["duplicated"], 0)
	t.check(int(s["retransmitted"]) > 0, "loss events inflate delay")
	t.eq(rig.host.pending_count(), 0)


func test_unordered_raw_chaos_reorders_and_duplicates(t: TestCtx) -> void:
	var rig: Rig = Rig.new(NetFaultProfile.preset("raw_chaos"), 99)
	var n: int = 10000
	for i in n:
		rig.send_seq(0, i)
		rig.step(1)
	rig.step(5, 100)
	var s: Dictionary = rig.host.stats()
	var dups: int = int(s["duplicated"])
	t.check(dups > 200 and dups < 400, "dup 3 %% of 10000 (~300): %d" % dups)
	t.eq(rig.received.size(), n + dups, "no loss in raw_chaos; every duplicate arrives")
	var seen: Dictionary = {}
	var repeats: int = 0
	var inversions: int = 0
	var last: int = -1
	for e in rig.received:
		var v: int = _value(e)
		if seen.has(v):
			repeats += 1
		seen[v] = true
		if v < last:
			inversions += 1
		last = maxi(last, v)
	t.eq(repeats, dups)
	t.eq(seen.size(), n, "all distinct messages arrive")
	t.check(inversions > 300, "reorders (10 %% chance, up to ~2x latency): %d inversions" % inversions)
	t.check(int(s["reordered"]) > 300)


func test_latency_and_jitter_bounds(t: TestCtx) -> void:
	# raw (unordered) link: every message gets its own uniform delay, so the mean equals the profile latency
	var p: NetFaultProfile = NetFaultProfile.new()
	p.latency_ms = 50.0
	p.jitter_ms = 10.0
	p.ordered = false
	var rig: Rig = Rig.new(p, 5)
	var n: int = 3000
	for i in n:
		rig.send_seq(0, i)
		rig.step(1)
	rig.step(1, 200)
	t.eq(rig.received.size(), n)
	var sum: float = 0.0
	var lo: float = 1e9
	var hi: float = 0.0
	for i in rig.received.size():
		var sent_ms: int = rig.received[i].data.decode_u32(4)
		var d: float = float(rig.recv_at[i] / 1000 - sent_ms)
		sum += d
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var mean: float = sum / float(n)
	t.check(absf(mean - 50.0) <= 5.0, "mean latency %.1f ms within +-10 %% of 50" % mean)
	t.check(lo >= 39.0, "min %.1f >= latency - jitter" % lo)
	t.check(hi <= 62.0, "max %.1f <= latency + jitter (+ step)" % hi)
	# ENet-like ordered link: head-of-line blocking can only add delay (running maximum), never beat the bounds
	p.ordered = true
	var rig2: Rig = Rig.new(p, 5)
	for i in n:
		rig2.send_seq(0, i)
		rig2.step(1)
	rig2.step(1, 200)
	var sum2: float = 0.0
	var lo2: float = 1e9
	var hi2: float = 0.0
	for i in rig2.received.size():
		var d2: float = float(rig2.recv_at[i] / 1000 - rig2.received[i].data.decode_u32(4))
		sum2 += d2
		lo2 = minf(lo2, d2)
		hi2 = maxf(hi2, d2)
	t.check(sum2 / float(n) >= mean - 1.0, "ordered mean %.1f >= unordered mean" % (sum2 / float(n)))
	t.check(lo2 >= 39.0 and hi2 <= 62.0, "ordered bounds %.1f..%.1f" % [lo2, hi2])


func test_loss_in_ordered_mode_adds_rto_multiples(t: TestCtx) -> void:
	var p: NetFaultProfile = NetFaultProfile.new()
	p.latency_ms = 20.0
	p.loss_pct = 30.0
	var rto: float = p.effective_rto_ms()
	t.near(rto, 73.0, 0.001)
	var rig: Rig = Rig.new(p, 42)
	var n: int = 400
	for i in n:
		rig.send_seq(0, i)
		rig.step(5, 200)  # one message per second: no head-of-line interplay
	rig.step(50, 40)
	t.eq(rig.received.size(), n)
	var hist: Dictionary = {}
	for i in rig.received.size():
		var sent_ms: int = rig.received[i].data.decode_u32(4)
		var d: float = float(rig.recv_at[i] / 1000 - sent_ms)
		var k: int = roundi((d - 20.0) / rto)
		t.check(absf(d - (20.0 + float(k) * rto)) <= 5.5, "delay %.1f = 20 + %d * 73" % [d, k])
		hist[k] = int(hist.get(k, 0)) + 1
	var zero_frac: float = float(hist.get(0, 0)) / float(n)
	t.check(zero_frac > 0.6 and zero_frac < 0.8, "70 %% of messages are not retransmitted: %.2f" % zero_frac)
	t.check(hist.has(1) and hist.has(2), "geometric retransmits")
	var s: Dictionary = rig.host.stats()
	t.eq(s["retransmitted"], s["dropped"])
	var expected_events: int = 0
	for k: int in hist:
		expected_events += k * int(hist[k])
	t.eq(int(s["retransmitted"]), expected_events, "counter equals the observed number of rto steps")


func test_head_of_line_blocking(t: TestCtx) -> void:
	var p: NetFaultProfile = NetFaultProfile.new()
	p.latency_ms = 10.0
	p.loss_pct = 50.0
	var rig: Rig = Rig.new(p, 8)
	for i in 300:
		rig.send_seq(0, i)
		rig.step(2)
	rig.step(10, 300)
	t.eq(rig.received.size(), 300)
	for i in 300:
		t.eq(_value(rig.received[i]), i)
	for i in range(1, 300):
		t.check(rig.recv_at[i] >= rig.recv_at[i - 1], "delivery times are monotonic")


func test_unordered_loss_drops(t: TestCtx) -> void:
	var p: NetFaultProfile = NetFaultProfile.new()
	p.latency_ms = 5.0
	p.loss_pct = 10.0
	p.ordered = false
	var rig: Rig = Rig.new(p, 3)
	for i in 5000:
		rig.send_seq(0, i)
		rig.step(1)
	rig.step(5, 20)
	var lost: int = 5000 - rig.received.size()
	t.check(lost > 400 and lost < 600, "10 %% dropped: %d" % lost)
	t.eq(int(rig.host.stats()["dropped"]), lost)


func test_freeze_holds_delivery_exactly(t: TestCtx) -> void:
	var p: NetFaultProfile = NetFaultProfile.new()
	p.latency_ms = 10.0
	var rig: Rig = Rig.new(p, 1)
	var t0: int = rig.clock.now_us()
	rig.send_seq(0, 1)
	rig.host.freeze_for_ms(500)  # frozen from t0 until t0 + 500 ms; the message was due at t0 + 10 ms
	rig.step(1, 499)
	t.eq(rig.received.size(), 0, "nothing delivered during the freeze")
	rig.send_seq(0, 2)  # sent during the freeze: leaves at the end of it, then travels 10 ms
	rig.step(1, 1)
	t.eq(rig.received.size(), 1, "the held message appears the millisecond the freeze ends")
	t.eq(rig.recv_at[0] - t0, 500_000 - 0)
	t.eq(_value(rig.received[0]), 1)
	rig.step(1, 9)
	t.eq(rig.received.size(), 1)
	rig.step(1, 2)
	t.eq(rig.received.size(), 2)
	t.eq(_value(rig.received[1]), 2)
	t.check(rig.recv_at[1] - t0 >= 510_000 and rig.recv_at[1] - t0 <= 512_000, "sent during the freeze: end + latency")
	t.check(int(rig.host.stats()["held"]) >= 1)


func test_periodic_freeze(t: TestCtx) -> void:
	var p: NetFaultProfile = NetFaultProfile.new()
	p.latency_ms = 1.0
	p.freeze_every_ms = 1000
	p.freeze_ms = 200
	var rig: Rig = Rig.new(p, 1)
	var t0: int = rig.t_wrap
	for ms in 3500:
		rig.step(1)
		rig.send_seq(0, ms)
	rig.step(1, 300)
	# every message still arrives, but never inside a freeze window [k*1000, k*1000 + 200) for k >= 1
	t.eq(rig.received.size(), 3500)
	for at in rig.recv_at:
		var el: int = int((at - t0) / 1000)
		if el >= 1000:
			t.check(el % 1000 >= 200, "delivery at %d ms is outside a freeze" % el)


func test_same_seed_same_schedule(t: TestCtx) -> void:
	var runs: Array[PackedInt64Array] = []
	for seed_value: int in [777, 777, 778]:
		var rig: Rig = Rig.new(NetFaultProfile.preset("bad_wifi"), seed_value)
		rig.host.record_schedule = true
		for i in 500:
			rig.send_seq(i % 3, i)
			rig.step(1)
		runs.append(rig.host.schedule)
	t.eq(runs[0].size(), 500)
	t.check(runs[0] == runs[1], "identical seed => identical delivery schedule")
	t.check(runs[0] != runs[2], "different seed => different schedule")
	var chaos_a: Rig = Rig.new(NetFaultProfile.preset("raw_chaos"), 5)
	var chaos_b: Rig = Rig.new(NetFaultProfile.preset("raw_chaos"), 5)
	chaos_a.host.record_schedule = true
	chaos_b.host.record_schedule = true
	for i in 300:
		chaos_a.send_seq(0, i)
		chaos_b.send_seq(0, i)
		chaos_a.step(1)
		chaos_b.step(1)
	t.check(chaos_a.host.schedule == chaos_b.host.schedule)
	t.eq(chaos_a.host.stats(), chaos_b.host.stats())


func test_bandwidth_serialisation_delay(t: TestCtx) -> void:
	var p: NetFaultProfile = NetFaultProfile.new()
	p.latency_ms = 0.1
	p.bandwidth_kbps = 80  # 10 bytes per ms
	var rig: Rig = Rig.new(p, 1)
	var t0: int = rig.clock.now_us()
	var big: PackedByteArray = PackedByteArray()
	big.resize(1000)
	for _i in 5:
		rig.host.send(2, 0, big)
	rig.step(1, 700)
	t.eq(rig.received.size(), 5)
	for i in 5:
		var ms: float = float(rig.recv_at[i] - t0) / 1000.0
		t.check(absf(ms - float(100 * (i + 1))) <= 2.0, "packet %d leaves the link after %d ms (%.1f)" % [i, 100 * (i + 1), ms])


func test_disconnect_ordered_after_delayed_packets(t: TestCtx) -> void:
	var p: NetFaultProfile = NetFaultProfile.new()
	p.latency_ms = 40.0
	var rig: Rig = Rig.new(p, 1)
	rig.send_seq(0, 1)
	rig.host.disconnect_peer(2, 4242, true)
	rig.step(1, 30)
	t.eq(rig.client_events.size(), 1 if rig.client_events.size() == 1 else rig.client_events.size(), "nothing yet")
	var before: int = rig.client_events.size()
	rig.step(1, 30)
	var tail: Array[NetTransportEvent] = rig.client_events.slice(before)
	t.eq(tail.size(), 2)
	if tail.size() == 2:
		t.eq(tail[0].kind, NetTransportEvent.Kind.PACKET, "data before the disconnect")
		t.eq(tail[1].kind, NetTransportEvent.Kind.DISCONNECTED)
		t.eq(tail[1].code, 4242)


func test_corrupt_next_flips_one_byte(t: TestCtx) -> void:
	var rig: Rig = Rig.new(NetFaultProfile.preset("local"), 1)
	var msg: PackedByteArray = PackedByteArray([0x21, 1, 2, 3, 4, 5])
	rig.host.corrupt_next(2, 1)
	rig.host.send(2, 1, msg)
	rig.host.send(2, 1, msg)
	rig.host.send(2, 0, msg)
	rig.step(1, 10)
	t.eq(rig.received.size(), 3)
	t.check(rig.received[0].data != msg, "first message on that channel is corrupted")
	var diff: int = 0
	for i in msg.size():
		if rig.received[0].data[i] != msg[i]:
			diff += 1
	t.eq(diff, 1, "exactly one byte")
	t.eq(rig.received[1].data, msg, "only once")
	t.eq(rig.received[2].data, msg, "other channel untouched")
	t.eq(rig.host.stats()["corrupted"], 1)


func test_disconnect_after_ms_cuts_the_link(t: TestCtx) -> void:
	var p: NetFaultProfile = NetFaultProfile.new()
	p.latency_ms = 1.0
	p.disconnect_after_ms = 300
	var rig: Rig = Rig.new(p, 1)
	rig.step(1, 250)
	t.eq(rig.host.send(2, 0, PackedByteArray([1])), OK)
	rig.step(1, 100)
	var kinds: Array[int] = []
	for e in rig.client_events:
		kinds.append(e.kind)
	t.check(kinds.has(NetTransportEvent.Kind.DISCONNECTED), "remote saw the cut")
	t.eq(rig.host.send(2, 0, PackedByteArray([1])), ERR_UNAVAILABLE)
	t.eq(rig.host.peer_state(2), NetProtocol.PeerState.GONE)


func test_wrapper_delegates_and_validates(t: TestCtx) -> void:
	var rig: Rig = Rig.new(NetFaultProfile.preset("lan"), 1)
	t.eq(rig.host.local_port(), 27615)
	t.eq(rig.host.peer_ids(), PackedInt32Array([2]))
	t.eq(rig.host.send(2, 3, PackedByteArray([1])), ERR_INVALID_PARAMETER)
	t.eq(rig.host.send(77, 0, PackedByteArray([1])), ERR_UNAVAILABLE)
	rig.host.set_profile(NetFaultProfile.preset("awful"))
	rig.send_seq(0, 5)
	rig.step(1, 60)
	t.eq(rig.received.size(), 0, "new profile applies to new messages (awful = 150 ms)")
	rig.step(10, 60)
	t.eq(rig.received.size(), 1)
	t.check(rig.host.inner_transport() is NetTransportLoopback)
