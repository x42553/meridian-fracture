extends RefCounted
## NET-1: NetProtocol helpers (hashes, RNG vectors, text sanitising, UTF-8 validation, addresses, tables).


func _hex(b: PackedByteArray) -> String:
	return b.hex_encode().to_upper()


func test_fnv_vectors(t: TestCtx) -> void:
	t.eq(NetProtocol.fnv1a32(PackedByteArray()), 0x811C9DC5)
	t.eq(NetProtocol.fnv1a32("a".to_utf8_buffer()), 0xE40C292C)
	t.eq(NetProtocol.fnv1a32("foobar".to_utf8_buffer()), 0xBF9CF968)
	var h1: int = NetProtocol.fnv1a32("foo".to_utf8_buffer())
	t.eq(NetProtocol.fnv1a32("bar".to_utf8_buffer(), h1), 0xBF9CF968, "chaining equals concatenation")
	t.eq(NetProtocol.fnv1a32("xfoobary".to_utf8_buffer(), 0x811C9DC5, 1, 7), 0xBF9CF968, "from/to window")


func test_rng_vectors(t: TestCtx) -> void:
	t.eq(NetProtocol.mix32(0), 0)
	t.eq(NetProtocol.mix32(1), 0x514E28B7)
	t.eq(NetProtocol.mix32(0xDEADBEEF), 0x0DE5C6A9)
	var want: Array[int] = [0x96A0F96B, 0x12BC8390, 0x971E9964, 0x79ADC7E7]
	for i in 4:
		t.eq(NetProtocol.lobby_rand(1, i), want[i], "lobby_rand(1,%d)" % i)
	# Fisher-Yates with seed 12345 (spec 5.3.5)
	var a: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	var c: int = 0
	for i in range(7, 0, -1):
		var j: int = NetProtocol.lobby_rand(12345, c) % (i + 1)
		c += 1
		var tmp: int = a[i]
		a[i] = a[j]
		a[j] = tmp
	t.eq(a, [7, 3, 2, 0, 1, 6, 5, 4] as Array[int], "shuffle vector")


func test_constants_match_sim_config(t: TestCtx) -> void:
	t.eq(NetProtocol.TURN_TICKS, SimConfig.TURN_TICKS)
	t.eq(NetProtocol.CHECKSUM_PERIOD_TICKS, SimConfig.CHECKSUM_PERIOD)
	t.eq(NetProtocol.TICK_US, 1_000_000 / SimConfig.TPS)
	t.eq(NetProtocol.TURN_MS, NetProtocol.TURN_TICKS * NetProtocol.TICK_US / 1000)
	t.eq(NetProtocol.INPUT_LOOKAHEAD, NetProtocol.D_MAX + 2)
	t.eq(NetProtocol.SPEED_PCT[2], 100)


func test_msg_table(t: TestCtx) -> void:
	for k: String in NetProtocol.Msg.keys():
		var type: int = NetProtocol.Msg[k]
		t.check(NetProtocol.is_known_msg(type), "table has " + k)
		t.eq(NetProtocol.msg_name(type), k)
	t.eq(NetProtocol.MSG_TABLE.size(), NetProtocol.Msg.size(), "no stray rows")
	t.eq(NetProtocol.msg_max_bytes(NetProtocol.Msg.TURN_INPUT), NetProtocol.MAX_INPUT_BYTES)
	t.eq(NetProtocol.msg_max_bytes(NetProtocol.Msg.TURN_BUNDLE), NetProtocol.MAX_BUNDLE_BYTES)
	t.eq(NetProtocol.msg_max_bytes(NetProtocol.Msg.LAUNCH_CONFIG), NetProtocol.MAX_LAUNCH_PACKET)
	t.eq(NetProtocol.msg_max_bytes(NetProtocol.Msg.LOBBY_SNAPSHOT), NetProtocol.MAX_SNAPSHOT)
	t.eq(NetProtocol.msg_channel(NetProtocol.Msg.TURN_BUNDLE), NetProtocol.CH_TURN)
	t.eq(NetProtocol.msg_channel(NetProtocol.Msg.CATCHUP_CHUNK), NetProtocol.CH_BULK)
	t.eq(NetProtocol.msg_max_bytes(0x99), -1)
	t.check(NetProtocol.has_connect_magic(NetProtocol.connect_data()))
	t.eq(NetProtocol.connect_data(), 0x4D460001)
	t.check(not NetProtocol.has_connect_magic(0x1234ABCD))


func test_sanitize_name(t: TestCtx) -> void:
	t.eq(NetProtocol.sanitize_name("  Bob  "), "Bob")
	var s: String = NetProtocol.sanitize_name("[b]X[/b]")
	t.check(not s.contains("[") and not s.contains("]"), "no brackets: " + s)
	t.eq(NetProtocol.sanitize_name("a\u0001b\tc\n"), "abc", "control chars removed")
	t.eq(NetProtocol.sanitize_name("x".repeat(30)).length(), 24)
	t.eq(NetProtocol.sanitize_name(""), "Player")
	t.eq(NetProtocol.sanitize_name("   "), "Player")
	t.eq(NetProtocol.sanitize_name("[]"), "Player")
	var wide: String = NetProtocol.sanitize_name("日".repeat(30))
	t.check(wide.to_utf8_buffer().size() <= 48, "fits the 48 byte wire field")
	t.eq(NetProtocol.sanitize_name("a" + String.chr(0x202E) + "b"), "ab", "bidi override removed")


func test_sanitize_text(t: TestCtx) -> void:
	t.eq(NetProtocol.sanitize_text("  hello \t\n  world  ", 200), "hello world")
	t.eq(NetProtocol.sanitize_text("a\u0001b\u0007c", 200), "abc")
	var s: String = NetProtocol.sanitize_text("é".repeat(150), 200)
	var b: PackedByteArray = s.to_utf8_buffer()
	t.check(b.size() <= 200, "cut to <= 200 bytes")
	t.check(NetProtocol.is_valid_utf8(b, 0, b.size()), "no split sequence")
	t.eq(s.length(), 100)
	t.eq(NetProtocol.sanitize_text(String.chr(0x1F600).repeat(60), 200).length(), 50)


func test_utf8_table(t: TestCtx) -> void:
	var ok_cases: Array[PackedByteArray] = [
		"Bob".to_utf8_buffer(), "Zoë 日本".to_utf8_buffer(), PackedByteArray([0xF0, 0x9F, 0x98, 0x80]), PackedByteArray(),
	]
	for b in ok_cases:
		t.check(NetProtocol.is_valid_utf8(b, 0, b.size()), "valid " + _hex(b))
	var bad_cases: Array[PackedByteArray] = [
		PackedByteArray([0xFF, 0xFE, 0x41]), PackedByteArray([0x41, 0xC3]), PackedByteArray([0x41, 0x00, 0x42]),
		PackedByteArray([0xC0, 0x80]), PackedByteArray([0xED, 0xA0, 0x80]), PackedByteArray([0xF4, 0x90, 0x80, 0x80]),
		PackedByteArray([0xE0, 0x80, 0x80]), PackedByteArray([0xF0, 0x80, 0x80, 0x80]), PackedByteArray([0x80]),
		PackedByteArray([0xC3, 0x28]), PackedByteArray([0xE2, 0x82]), PackedByteArray([0xF5, 0x80, 0x80, 0x80]),
	]
	for b in bad_cases:
		t.check_false(NetProtocol.is_valid_utf8(b, 0, b.size()), "invalid " + _hex(b))
	t.check_false(NetProtocol.is_valid_utf8(PackedByteArray([0x41]), 0, 2), "range past the end")
	t.check_false(NetProtocol.is_valid_utf8(PackedByteArray([0x41]), -1, 1), "negative start")
	t.check(NetProtocol.is_valid_utf8(PackedByteArray([0x41, 0x00, 0x42]), 0, 1), "window before the NUL is fine")
	# exhaustive 2-byte sweep agrees with the engine decoder for accepted sequences
	for b0 in range(0x80, 0x100):
		for b1 in range(0x00, 0x100):
			var pair: PackedByteArray = PackedByteArray([b0, b1])
			if NetProtocol.is_valid_utf8(pair, 0, 2):
				t.check(pair.get_string_from_utf8().to_utf8_buffer() == pair, "roundtrip %s" % _hex(pair))


func test_private_ipv4(t: TestCtx) -> void:
	for ip: String in ["10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.20", "169.254.1.1", "127.0.0.1", "100.64.0.1", "100.127.255.255"]:
		t.check(NetProtocol.is_private_ipv4(ip), ip)
	for ip: String in ["172.32.0.1", "172.15.0.1", "8.8.8.8", "100.128.0.1", "192.169.0.1", "1.2.3", "a.b.c.d", "", "256.1.1.1", "10.0.0.0.1"]:
		t.check_false(NetProtocol.is_private_ipv4(ip), ip)


func test_parse_address(t: TestCtx) -> void:
	var r: Dictionary = NetProtocol.parse_address("192.168.1.20")
	t.check(bool(r["ok"]))
	t.eq(r["host"], "192.168.1.20")
	t.eq(r["port"], 27615)
	r = NetProtocol.parse_address(" 10.0.0.5:28000 ")
	t.check(bool(r["ok"]))
	t.eq(r["host"], "10.0.0.5")
	t.eq(r["port"], 28000)
	r = NetProtocol.parse_address("[fe80::1]:27620")
	t.check(bool(r["ok"]))
	t.eq(r["host"], "fe80::1")
	t.eq(r["port"], 27620)
	r = NetProtocol.parse_address("fe80::1")
	t.check(bool(r["ok"]), "bare IPv6")
	t.eq(r["port"], 27615)
	r = NetProtocol.parse_address("host.local")
	t.check(bool(r["ok"]))
	t.eq(r["host"], "host.local")
	r = NetProtocol.parse_address("host.local:1234")
	t.eq(r["port"], 1234)
	r = NetProtocol.parse_address("[::1]")
	t.check(bool(r["ok"]))
	t.eq(r["host"], "::1")
	for bad: String in ["1.2.3.4:0", "1.2.3.4:70000", "fe80::1%en0", "", "  ", "a".repeat(300), "1.2.3.4:", "1.2.3.4:abc", "999.1.1.1", "[fe80::1", "[fe80::1]x", "bad host", "1.2.3.4:-5", "1.2.3.4:+5", "[1.2.3.4]:5", ".x", ":27615"]:
		var rr: Dictionary = NetProtocol.parse_address(bad)
		t.check_false(bool(rr["ok"]), "rejects '%s'" % bad.left(20))
		t.check(not str(rr["error"]).is_empty(), "has an error text")
	t.check(bool(NetProtocol.parse_address("1.2.3.4:65535")["ok"]))
	t.check(bool(NetProtocol.parse_address("1.2.3.4:1")["ok"]))


func test_describe_texts(t: TestCtx) -> void:
	var text: String = NetProtocol.describe_reject(NetProtocol.RejectReason.DATA_MISMATCH, {
		"host_game_version": "0.3.1", "host_data_hash": 0x9F3A21C4, "local_game_version": "0.3.0", "local_data_hash": 0x12AB77E0})
	t.check(text.contains("9F3A21C4") and text.contains("12AB77E0"), text)
	t.check(text.contains("game data"))
	t.eq(NetProtocol.describe_reject(NetProtocol.RejectReason.DATA_MISMATCH, {"host_data_hash": 0x1A}).contains("0000001A"), true, "8 hex digits, upper case")
	t.check(NetProtocol.describe_reject(NetProtocol.RejectReason.PROTO_MISMATCH, {}).contains("protocol"))
	t.check(NetProtocol.describe_reject(NetProtocol.RejectReason.SIM_MISMATCH, {}).contains("simulation"))
	t.eq(NetProtocol.describe_reject(NetProtocol.RejectReason.LOBBY_FULL, {}), "The game is full.")
	t.eq(NetProtocol.describe_reject(NetProtocol.RejectReason.BAD_PASSWORD, {}), "Wrong password.")
	t.eq(NetProtocol.describe_reject(NetProtocol.RejectReason.NONE, {}), "")
	for rr in range(1, 12):
		t.check(not NetProtocol.describe_reject(rr, {}).is_empty(), "text for reject %d" % rr)
	for kr in range(0, 10):
		t.check(not NetProtocol.describe_kick(kr, "").is_empty(), "text for kick %d" % kr)
	t.eq(NetProtocol.describe_kick(NetProtocol.KickReason.HOST_LEFT, ""), "The host left the game.")
	t.check(NetProtocol.describe_kick(NetProtocol.KickReason.PROTOCOL_VIOLATION, "bad").ends_with("(bad)"))


func test_writer_reader_primitives(t: TestCtx) -> void:
	var w: NetWriter = NetWriter.new()
	w.u8(0x1FF).u16(0x1ABCD).u32(0x1_89ABCDEF).i8(-2).i16(-300).i32(-70000)
	w.str_("héllo", 24).bytes_(PackedByteArray([1, 2, 3])).raw(PackedByteArray([9, 9]))
	var r: NetReader = NetReader.new(w.to_bytes())
	t.eq(r.u8(), 0xFF)
	t.eq(r.u16(), 0xABCD)
	t.eq(r.u32(), 0x89ABCDEF)
	t.eq(r.i8(), -2)
	t.eq(r.i16(), -300)
	t.eq(r.i32(), -70000)
	t.eq(r.str_(24), "héllo")
	t.eq(r.bytes_(8), PackedByteArray([1, 2, 3]))
	t.eq(r.raw(2), PackedByteArray([9, 9]))
	t.check(r.done())
	# overrun is sticky, returns zeros, moves to the end
	var r2: NetReader = NetReader.new(PackedByteArray([1, 2, 3]))
	t.eq(r2.u32(), 0)
	t.check_false(r2.ok)
	t.eq(r2.left(), 0)
	t.eq(r2.u8(), 0)
	t.eq(r2.str_(5), "")
	t.eq(r2.varint(), 0)
	t.check_false(r2.done())


func test_writer_string_truncation(t: TestCtx) -> void:
	var w: NetWriter = NetWriter.new()
	w.str_("日本語", 7)  # 3 x 3 bytes; 7 -> cut at 6
	var b: PackedByteArray = w.to_bytes()
	t.eq(b[0], 6)
	t.eq(b.size(), 7)
	var r: NetReader = NetReader.new(b)
	t.eq(r.str_(7), "日本")
	t.check(r.done())
	# reader rejects too-long and invalid UTF-8 without engine messages
	var r2: NetReader = NetReader.new(PackedByteArray([4, 0x41, 0xC3, 0x28, 0x42]))
	t.eq(r2.str_(10), "")
	t.check_false(r2.ok)
	var r3: NetReader = NetReader.new(PackedByteArray([3, 0x41, 0x42, 0x43]))
	t.eq(r3.str_(2), "")
	t.check_false(r3.ok)
	var r4: NetReader = NetReader.new(PackedByteArray([3, 0x41, 0x00, 0x43]))
	t.eq(r4.str_(5), "", "embedded NUL rejected")
	t.check_false(r4.ok)
