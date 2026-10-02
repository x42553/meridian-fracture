extends RefCounted
## NET-7: NetDiscovery (golden datagram, validation, expiry, candidates, breaker, real UDP unicast on a test port).

const GOLDEN: PackedByteArray = [
	0x4D, 0x46, 0x44, 0x53, 0x01, 0x01, 0x01, 0x00, 0xEF, 0xBE, 0xAD, 0xDE, 0xDF, 0x6B, 0x44, 0x33, 0x22, 0x11, 0x07, 0x00,
	0x00, 0x00, 0x00, 0x02, 0x04, 0x02, 0x00, 0x10, 0x00, 0x00, 0x0C, 0x53, 0x69, 0x6D, 0x6F, 0x6E, 0x27, 0x73, 0x20, 0x67,
	0x61, 0x6D, 0x65, 0x05, 0x30, 0x2E, 0x33, 0x2E, 0x31]


func _fields() -> Dictionary:
	return {"kind": 1, "proto_version": 1, "session_id": 0xDEADBEEF, "game_port": 27615, "data_hash": 0x11223344, "sim_version": 7,
		"flags": 0, "humans": 2, "slots_total": 4, "slots_free": 2, "map_family": 0, "map_size": 128, "ai_count": 0,
		"host_name": "Simon's game", "game_version": "0.3.1"}


func _disc(clock: NetClock, sim: int = 7, data: int = 0x11223344) -> NetDiscovery:
	var d: NetDiscovery = NetDiscovery.new()
	d.setup(clock, "0.3.1", NetProtocol.PROTO_VERSION, sim, data)
	d.port = 0
	return d


## A browser that is "browsing" without a socket (datagrams are fed by hand).
func _browser(clock: NetClock, sim: int = 7, data: int = 0x11223344) -> NetDiscovery:
	var d: NetDiscovery = _disc(clock, sim, data)
	d._browsing = true
	return d


func test_golden_datagram(t: TestCtx) -> void:
	var enc: PackedByteArray = NetDiscovery.encode_datagram(_fields())
	t.eq(enc.size(), 49)
	t.eq(enc, GOLDEN, "golden bytes")
	var d: Dictionary = NetDiscovery.decode_datagram(GOLDEN)
	t.eq(int(d["session_id"]), 0xDEADBEEF)
	t.eq(int(d["game_port"]), 27615)
	t.eq(int(d["data_hash"]), 0x11223344)
	t.eq(int(d["sim_version"]), 7)
	t.eq(int(d["humans"]), 2)
	t.eq(int(d["slots_total"]), 4)
	t.eq(int(d["slots_free"]), 2)
	t.eq(int(d["map_size"]), 128)
	t.eq(str(d["host_name"]), "Simon's game")
	t.eq(str(d["game_version"]), "0.3.1")
	t.eq(NetDiscovery.encode_datagram(d), GOLDEN, "canonical re-encode")
	# flags
	var f: Dictionary = _fields()
	f["has_password"] = true
	f["full"] = true
	f["dedicated"] = true
	var e2: Dictionary = NetDiscovery.decode_datagram(NetDiscovery.encode_datagram(f))
	t.eq(int(e2["flags"]), 1 | 4 | 16)
	t.check(bool(e2["has_password"]) and bool(e2["full"]) and bool(e2["dedicated"]) and not bool(e2["in_progress"]))


func test_invalid_datagrams_are_ignored(t: TestCtx) -> void:
	var clock: NetClock = NetClock.manual(1_000_000)
	var b: NetDiscovery = _browser(clock)
	var changes: PackedInt32Array = PackedInt32Array([0])
	b.entries_changed.connect(func() -> void: changes[0] += 1)
	var bad: Array = []
	bad.append(PackedByteArray())
	bad.append(GOLDEN.slice(0, 29))
	var big: PackedByteArray = GOLDEN.duplicate()
	big.resize(129)
	bad.append(big)
	var magic: PackedByteArray = GOLDEN.duplicate()
	magic[0] = 0x00
	bad.append(magic)
	var layout: PackedByteArray = GOLDEN.duplicate()
	layout[4] = 2
	bad.append(layout)
	var kind: PackedByteArray = GOLDEN.duplicate()
	kind[5] = 3
	bad.append(kind)
	var utf: PackedByteArray = GOLDEN.duplicate()
	utf[31] = 0xFF
	bad.append(utf)
	var strlen: PackedByteArray = GOLDEN.duplicate()
	strlen[30] = 0x30
	bad.append(strlen)
	var tail: PackedByteArray = GOLDEN.duplicate()
	tail.append(0)
	bad.append(tail)
	for i: int in bad.size():
		clock.advance_us(300_000)  # stay under the per-source rate limit
		b.handle_datagram("192.168.1.5", bad[i] as PackedByteArray)
	t.eq(b.entries().size(), 0, "nothing accepted")
	t.eq(changes[0], 0)
	# public source is refused unless allowed
	b.handle_datagram("8.8.8.8", GOLDEN)
	t.eq(b.entries().size(), 0, "public source ip")
	b.allow_public = true
	clock.advance_us(300_000)
	b.handle_datagram("8.8.8.8", GOLDEN)
	t.eq(b.entries().size(), 1)


func test_entries_expiry_closed_and_rate_limit(t: TestCtx) -> void:
	var clock: NetClock = NetClock.manual(5_000_000)
	var b: NetDiscovery = _browser(clock)
	var changes: PackedInt32Array = PackedInt32Array([0])
	b.entries_changed.connect(func() -> void: changes[0] += 1)
	b.handle_datagram("192.168.1.5", GOLDEN)
	t.eq(b.entries().size(), 1)
	t.eq(changes[0], 1)
	var e: NetDiscoveryEntry = b.entries()[0]
	t.eq(e.address, "192.168.1.5", "address from the source ip")
	t.eq(e.port, 27615)
	t.eq(e.join_address(), "192.168.1.5:27615")
	t.check(e.compatible)
	t.eq(e.humans, 2)
	# refresh keeps one entry and does not signal without a visible change
	clock.advance_us(1_000_000)
	b.handle_datagram("192.168.1.5", GOLDEN)
	t.eq(b.entries().size(), 1)
	t.eq(changes[0], 1)
	# expiry: 4 s without an announce
	clock.advance_us(3_900_000)
	t.eq(b.entries().size(), 1, "still alive at 3.9 s")
	clock.advance_us(200_000)
	t.eq(b.entries().size(), 0, "expired after 4 s")
	t.eq(changes[0], 2)
	# CLOSED removes at once
	b.handle_datagram("192.168.1.5", GOLDEN)
	var closed: Dictionary = _fields()
	closed["kind"] = 2
	clock.advance_us(300_000)
	b.handle_datagram("192.168.1.5", NetDiscovery.encode_datagram(closed))
	t.eq(b.entries().size(), 0)
	# per-source rate: only 5 datagrams per second are looked at
	var b2: NetDiscovery = _browser(clock)
	for i: int in 8:
		var f: Dictionary = _fields()
		f["session_id"] = 100 + i
		b2.handle_datagram("10.0.0.9", NetDiscovery.encode_datagram(f))
	t.eq(b2.entries().size(), 5, "5 datagrams/s per source")
	# same session id from two sources = two entries; sorted by (host_name, address)
	var b3: NetDiscovery = _browser(clock)
	b3.handle_datagram("192.168.1.9", GOLDEN)
	b3.handle_datagram("192.168.1.2", GOLDEN)
	var es: Array[NetDiscoveryEntry] = b3.entries()
	t.eq(es.size(), 2)
	t.eq(es[0].address, "192.168.1.2")


func test_capacity_and_compatibility(t: TestCtx) -> void:
	var clock: NetClock = NetClock.manual(1_000_000)
	var b: NetDiscovery = _browser(clock, 7, 0x11223344)
	for i: int in 70:
		var f: Dictionary = _fields()
		f["session_id"] = i + 1
		clock.advance_us(250_000)
		b.handle_datagram("192.168.1.%d" % (i % 200 + 1), NetDiscovery.encode_datagram(f))
		clock.advance_us(10_000)
		# keep the earlier ones alive (expiry is 4 s)
	t.le(b.entries().size(), 64, "table capped at 64")
	# incompatible games are listed, with the failing layer
	var b2: NetDiscovery = _browser(NetClock.manual(1_000_000), 8, 0x11223344)
	b2.handle_datagram("192.168.1.5", GOLDEN)
	t.eq(b2.entries().size(), 1)
	t.check(not b2.entries()[0].compatible)
	t.eq(b2.entries()[0].mismatch, "simulation")
	var b3: NetDiscovery = _browser(NetClock.manual(1_000_000), 7, 0x99999999)
	b3.handle_datagram("192.168.1.5", GOLDEN)
	t.eq(b3.entries()[0].mismatch, "game data")


func test_broadcast_candidates(t: TestCtx) -> void:
	t.eq(NetDiscovery.broadcast_candidates(PackedStringArray(["172.16.223.202"])), PackedStringArray(["255.255.255.255", "172.16.223.255", "172.16.255.255"]))
	t.eq(NetDiscovery.broadcast_candidates(PackedStringArray(["192.168.1.20"])), PackedStringArray(["255.255.255.255", "192.168.1.255", "192.168.255.255"]))
	t.eq(NetDiscovery.broadcast_candidates(PackedStringArray(["10.4.7.9"])), PackedStringArray(["255.255.255.255", "10.4.7.255", "10.4.255.255", "10.255.255.255"]))
	t.eq(NetDiscovery.broadcast_candidates(PackedStringArray(["127.0.0.1", "169.254.3.4"])), PackedStringArray(["255.255.255.255", "169.254.3.255", "169.254.255.255"]), "link-local kept when it is the only address")
	t.eq(NetDiscovery.broadcast_candidates(PackedStringArray(["169.254.3.4", "192.168.1.20"])), PackedStringArray(["255.255.255.255", "192.168.1.255", "192.168.255.255"]), "link-local dropped when another address exists")
	t.eq(NetDiscovery.broadcast_candidates(PackedStringArray(["192.168.1.20", "192.168.1.21"])), PackedStringArray(["255.255.255.255", "192.168.1.255", "192.168.255.255"]), "deduplicated")
	t.eq(NetDiscovery.broadcast_candidates(PackedStringArray(["bogus", "1.2.3", "300.1.1.1"])), PackedStringArray(["255.255.255.255"]))
	var many: PackedStringArray = PackedStringArray()
	for i: int in 20:
		many.append("172.%d.1.1" % (16 + i))
	t.eq(NetDiscovery.broadcast_candidates(many).size(), 12, "capped at 12")


func test_circuit_breaker_and_announce_ok(t: TestCtx) -> void:
	var clock: NetClock = NetClock.manual(1_000_000)
	var d: NetDiscovery = _disc(clock)
	var sent: Dictionary = {}
	d.send_override = func(target: String, data: PackedByteArray) -> int:
		sent[target] = int(sent.get(target, 0)) + 1
		t.check(data.size() <= 128)
		return ERR_UNAVAILABLE if target == "9.9.9.9" else OK
	d.set_targets_override(PackedStringArray(["127.0.0.1", "9.9.9.9"]))
	d.start_announce(func() -> Dictionary: return _fields(), 27615)
	for i: int in 10:
		d.poll()
		clock.advance_us(1_100_000)
	t.eq(int(sent["127.0.0.1"]), 10)
	t.eq(int(sent["9.9.9.9"]), 5, "the failing target stops after 5 consecutive failures")
	t.check(d.target_disabled("9.9.9.9"))
	t.check(d.announce_ok, "one target works")
	# 30 s later the breaker closes again
	clock.advance_us(30_000_000)
	d.poll()
	t.eq(int(sent["9.9.9.9"]), 6)
	# every target failing for > 10 s clears announce_ok
	var d2: NetDiscovery = _disc(clock)
	d2.send_override = func(_target: String, _data: PackedByteArray) -> int: return ERR_CANT_CONNECT
	d2.set_targets_override(PackedStringArray(["255.255.255.255"]))
	d2.start_announce(func() -> Dictionary: return _fields(), 27615)
	for i: int in 9:
		d2.poll()
		clock.advance_us(1_100_000)
	t.check(d2.announce_ok, "not yet")
	for i: int in 3:
		d2.poll()
		clock.advance_us(1_100_000)
	t.check(not d2.announce_ok, "announce_ok false after 10 s without a success")
	# stop_announce sends a CLOSED datagram
	var kinds: Array = []
	d.send_override = func(_target: String, data: PackedByteArray) -> int:
		kinds.append(data[5])
		return OK
	d.stop_announce(true)
	t.check(kinds.has(2), "CLOSED sent")


func _free_port() -> int:
	return 28400 + OS.get_process_id() % 500


func test_real_udp_unicast_loopback(t: TestCtx) -> void:
	var clock: NetClock = NetClock.real()
	var host: NetDiscovery = NetDiscovery.new()
	host.setup(clock, "0.3.1", NetProtocol.PROTO_VERSION, 7, 0x11223344)
	var browser: NetDiscovery = NetDiscovery.new()
	browser.setup(clock, "0.3.1", NetProtocol.PROTO_VERSION, 7, 0x11223344)
	var port: int = _free_port()
	var bound: int = ERR_UNAVAILABLE
	for k: int in 5:
		browser.port = port + k
		bound = browser.start_browse()
		if bound == OK:
			host.port = port + k
			break
	t.eq(bound, OK, "test discovery port bound")
	if bound != OK:
		return
	# a second browser on the same port reports port_in_use
	var second: NetDiscovery = NetDiscovery.new()
	second.setup(clock, "0.3.1", NetProtocol.PROTO_VERSION, 7, 0x11223344)
	second.port = browser.port
	t.eq(second.start_browse(), ERR_UNAVAILABLE)
	t.eq(second.browse_error, "port_in_use")
	host.set_targets_override(PackedStringArray(["127.0.0.1"]))
	host.start_announce(func() -> Dictionary: return _fields(), 27615)
	var deadline: int = Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline and browser.entries().is_empty():
		host.poll()
		browser.poll()
		OS.delay_msec(5)
	var es: Array[NetDiscoveryEntry] = browser.entries()
	t.eq(es.size(), 1, "announce received over real UDP")
	if es.size() == 1:
		t.eq(es[0].address, "127.0.0.1")
		t.eq(es[0].host_name, "Simon's game")
		t.eq(es[0].port, 27615)
		t.eq(es[0].session_id, 0xDEADBEEF)
		t.check(es[0].compatible)
	# CLOSED drops the entry at once
	host.stop_announce(true)
	deadline = Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline and not browser.entries().is_empty():
		browser.poll()
		OS.delay_msec(5)
	t.eq(browser.entries().size(), 0, "CLOSED removes the entry")
	browser.close()
	host.close()
