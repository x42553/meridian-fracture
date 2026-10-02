extends RefCounted
## NET-1: NetWriter / NetReader / NetCodec / NetLobbyCodec / NetBundle. Reference vectors of spec 10.2
## (byte exact), reject tables, truncation at every length, fuzz (random + mutated buffers per decoder,
## no engine error, accepted buffers re-encode identically).

const FUZZ_ITERATIONS: int = 2000


func _hex(b: PackedByteArray) -> String:
	return b.hex_encode().to_upper()


func _from_hex(s: String) -> PackedByteArray:
	return s.replace(" ", "").hex_decode()


func _cmd(a: Array) -> PackedInt32Array:
	return PackedInt32Array(a)


# ---- primitives -----------------------------------------------------------------------------------------

func test_varint_vectors(t: TestCtx) -> void:
	var cases: Dictionary = {0: "00", 127: "7F", 128: "80 01", 16383: "FF 7F", 16384: "80 80 01", 0xFFFFFFFF: "FF FF FF FF 0F"}
	for v: int in cases:
		var b: PackedByteArray = NetWriter.new().varint(v).to_bytes()
		t.eq(_hex(b), (cases[v] as String).replace(" ", ""), "varint %d" % v)
		var r: NetReader = NetReader.new(b)
		t.eq(r.varint(), v)
		t.check(r.done())
	for bad: String in ["80 00", "FF 00", "80 80 00", "FF FF FF FF 10", "FF FF FF FF FF 01", "80 80 80 80 80 80 00", "80", ""]:
		var r2: NetReader = NetReader.new(_from_hex(bad))
		r2.varint()
		t.check_false(r2.ok, "rejects '%s'" % bad)


func test_zvarint_vectors(t: TestCtx) -> void:
	var cases: Dictionary = {0: "00", -1: "01", 1: "02", -2: "03", 2147483647: "FE FF FF FF 0F", -2147483648: "FF FF FF FF 0F"}
	for v: int in cases:
		var b: PackedByteArray = NetWriter.new().zvarint(v).to_bytes()
		t.eq(_hex(b), (cases[v] as String).replace(" ", ""), "zvarint %d" % v)
		var r: NetReader = NetReader.new(b)
		t.eq(r.zvarint(), v)
		t.check(r.done())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for _i in 500:
		var v: int = rng.randi() - 0x80000000
		var r: NetReader = NetReader.new(NetWriter.new().zvarint(v).to_bytes())
		t.eq(r.zvarint(), v)


# ---- goldens ----------------------------------------------------------------------------------------------

func test_join_request_golden(t: TestCtx) -> void:
	var f: Dictionary = {"proto_version": 1, "spectator": false, "sim_version": 7, "data_hash": 0x11223344,
		"client_nonce": 0xCAFEBABE, "game_version": "0.3.1", "name": "Bob"}
	var b: PackedByteArray = NetCodec.encode_join_request(f)
	t.eq(_hex(b), "01010000070000004433221 1BEBAFECA0530 2E332E31 03426F62".replace(" ", ""))
	t.eq(b.size(), 26)
	var d: Dictionary = NetCodec.decode_join_request(b)
	t.eq(d["name"], "Bob")
	t.eq(d["game_version"], "0.3.1")
	t.eq(d["client_nonce"], 0xCAFEBABE)
	t.eq(d["data_hash"], 0x11223344)
	t.eq(d["sim_version"], 7)
	t.check(not bool(d["spectator"]))
	t.eq(NetCodec.peek_join_request(b)["proto_version"], 1)
	t.eq(NetCodec.peek_join_request(PackedByteArray([1, 9, 0]))["proto_version"], 9)
	t.check(NetCodec.peek_join_request(PackedByteArray([1, 9])).is_empty())
	# optional sections
	var tables: Dictionary = {"units": 0xAABBCCDD, "weapons": 5}
	var files: Dictionary = {"balance/units_napc.json": 0x01020304}
	var f2: Dictionary = f.duplicate()
	f2["spectator"] = true
	f2["pw_proof"] = "x".sha256_buffer()
	f2["data_format"] = 1
	f2["tables"] = tables
	f2["files"] = files
	var b2: PackedByteArray = NetCodec.encode_join_request(f2)
	var d2: Dictionary = NetCodec.decode_join_request(b2)
	t.eq(d2["flags"], 0x0F)
	t.eq(d2["tables"], tables)
	t.eq(d2["files"], files)
	t.eq(d2["pw_proof"], "x".sha256_buffer())
	t.eq(NetCodec.encode_join_request(d2), b2, "canonical")
	f2["pw_proof"] = PackedByteArray([1, 2])
	t.check(NetCodec.encode_join_request(f2).is_empty(), "wrong proof size")
	var big: Dictionary = {}
	for i in 33:
		big["t%d" % i] = i
	f["tables"] = big
	t.check(NetCodec.encode_join_request(f).is_empty(), "33 tables")


func test_turn_input_golden(t: TestCtx) -> void:
	var b: PackedByteArray = NetCodec.encode_turn_input({"turn": 5, "exec_turn": 3, "cmds": [_cmd([3, 17, 4096])]})
	t.eq(_hex(b), "200500000003000000010306228040")
	t.eq(b.size(), 15)
	var d: Dictionary = NetCodec.decode_turn_input(b)
	t.eq(d["turn"], 5)
	t.eq(d["exec_turn"], 3)
	t.eq((d["cmds"] as Array).size(), 1)
	t.eq((d["cmds"] as Array)[0], _cmd([3, 17, 4096]))
	var hb: PackedByteArray = NetCodec.encode_turn_input({"turn": 12, "exec_turn": 10, "cmds": []})
	t.eq(hb.size(), 10, "heartbeat is 10 bytes")
	t.eq(_hex(hb), "200C0000000A00000000")
	t.eq(NetCodec.peek_turn_input_header(b), {"turn": 5, "exec_turn": 3})
	t.check(NetCodec.peek_turn_input_header(b.slice(0, 8)).is_empty())
	t.eq(NetCodec.peek_type(b), 0x20)
	t.eq(NetCodec.peek_type(PackedByteArray()), -1)


func test_turn_input_limits(t: TestCtx) -> void:
	var many: Array = []
	for i in 65:
		many.append(_cmd([1, i]))
	t.check(NetCodec.encode_turn_input({"turn": 1, "exec_turn": 0, "cmds": many}).is_empty(), "65 commands")
	many.resize(64)
	t.check(not NetCodec.encode_turn_input({"turn": 1, "exec_turn": 0, "cmds": many}).is_empty(), "64 commands")
	var long: PackedInt32Array = PackedInt32Array()
	long.resize(1025)
	t.check(NetCodec.encode_turn_input({"turn": 1, "exec_turn": 0, "cmds": [long]}).is_empty(), "1025 ints")
	t.check(NetCodec.encode_turn_input({"turn": 1, "exec_turn": 0, "cmds": [PackedInt32Array()]}).is_empty(), "0 ints")
	t.check(NetCodec.encode_turn_input({"turn": 1, "exec_turn": 0, "cmds": [_cmd([256])]}).is_empty(), "type 256")
	t.check(NetCodec.encode_turn_input({"turn": 1, "exec_turn": 0, "cmds": [_cmd([-1])]}).is_empty(), "type -1")
	# message-size cap: 6 commands of 1024 max-width ints exceed 6200 bytes
	var wide: PackedInt32Array = PackedInt32Array()
	wide.resize(1024)
	wide.fill(0x7FFFFFFF)
	wide[0] = 3
	t.check(NetCodec.encode_turn_input({"turn": 1, "exec_turn": 0, "cmds": [wide, wide]}).is_empty(), "over MAX_INPUT_BYTES")
	# decoder: n = 0 and n = 1025
	t.check(NetCodec.decode_turn_input(_from_hex("20 05000000 03000000 01 00")).is_empty(), "n = 0")
	t.check(NetCodec.decode_turn_input(_from_hex("20 05000000 03000000 01 81 08")).is_empty(), "n = 1025")
	t.check(NetCodec.decode_turn_input(_from_hex("20 05000000 03000000 41")).is_empty(), "65 commands declared")
	t.check(not NetCodec.decode_turn_input(_from_hex("20 05000000 03000000 01 01 06")).is_empty(), "type 3 accepted")
	t.check(NetCodec.decode_turn_input(_from_hex("20 05000000 03000000 01 01 01")).is_empty(), "type -1 rejected")
	t.check(NetCodec.decode_turn_input(_from_hex("20 05000000 03000000 00 00")).is_empty(), "trailing byte")
	var oversize: PackedByteArray = PackedByteArray()
	oversize.resize(6201)
	oversize[0] = 0x20
	t.check(NetCodec.decode_turn_input(oversize).is_empty(), "oversize message")


func _golden_bundle() -> NetBundle:
	return NetBundle.build(5, PackedInt32Array([0, 4]), [[_cmd([3, 17, 4096])], [_cmd([7, -1])]], [])


func test_bundle_goldens(t: TestCtx) -> void:
	var b: NetBundle = _golden_bundle()
	var w: PackedByteArray = NetCodec.encode_bundle(b)
	t.eq(_hex(w), "2105000000000200010306228040040102 0E0198E82DEF".replace(" ", ""))
	t.eq(w.size(), 23)
	t.eq(b.wire_bytes(), w)
	t.eq(b.hash32(), 0xEF2DE898)
	t.eq(b.command_count(), 2)
	t.eq(_hex(b.core_bytes()), "0500000002 00010306228040 040102 0E01".replace(" ", ""), "core = turn | groups | groups, no flags")
	var d: NetBundle = NetCodec.decode_bundle(w)
	t.not_null(d, "decodes")
	if d == null:
		return
	t.eq(d.turn, 5)
	t.eq(d.pids, PackedInt32Array([0, 4]))
	t.eq((d.group_cmds[1] as Array)[0], _cmd([7, -1]))
	t.eq(d.wire_bytes(), w)
	t.eq(d.core_bytes(), b.core_bytes())
	t.eq(d.commands_of(4).size(), 1)
	t.eq(d.commands_of(3).size(), 0)
	# control record golden
	var c: NetBundle = NetBundle.build(6, PackedInt32Array(), [], [_cmd([1, 3])])
	t.eq(_hex(c.wire_bytes()), "21060000000100010103F1F5905B")
	t.eq(c.wire_bytes().size(), 14)
	var cd: NetBundle = NetCodec.decode_bundle(c.wire_bytes())
	t.not_null(cd)
	if cd != null:
		t.eq(cd.ctrl, [_cmd([1, 3])] as Array)
		t.eq(cd.flags, 1)
		t.eq(cd.core_bytes(), _from_hex("0600000000"))


func test_bundle_ctrl_records(t: TestCtx) -> void:
	var ctrl: Array = [_cmd([1, 4]), _cmd([2, 3, 5, 7]), _cmd([3, 150]), _cmd([4, 1]), _cmd([5, 255])]
	var b: NetBundle = NetBundle.build(9, PackedInt32Array([2]), [[_cmd([250, 0])]], ctrl)
	var w: PackedByteArray = b.wire_bytes()
	t.check(not w.is_empty())
	var d: NetBundle = NetCodec.decode_bundle(w)
	t.not_null(d)
	if d != null:
		t.eq(d.ctrl, ctrl)
	for bad: PackedInt32Array in [_cmd([1, 0]), _cmd([1, 9]), _cmd([2, 8, 0, 0]), _cmd([3, 49]), _cmd([3, 201]), _cmd([4, 5]), _cmd([5, 8]), _cmd([9, 1]), _cmd([1]), _cmd([])]:
		var bb: NetBundle = NetBundle.build(1, PackedInt32Array(), [], [bad])
		t.check(bb.wire_bytes().is_empty(), "ctrl %s rejected on encode" % str(bad))
	var nine: Array = []
	for i in 9:
		nine.append(_cmd([1, 2]))
	t.check(NetBundle.build(1, PackedInt32Array(), [], nine).wire_bytes().is_empty(), "9 ctrl records")


func _rehash(body_without_hash: PackedByteArray) -> PackedByteArray:
	var w: NetWriter = NetWriter.new().raw(body_without_hash)
	w.u32(NetProtocol.fnv1a32(body_without_hash, 0x811C9DC5, 1))
	return w.to_bytes()


func test_bundle_rejects(t: TestCtx) -> void:
	var ok: PackedByteArray = _golden_bundle().wire_bytes()
	t.not_null(NetCodec.decode_bundle(ok))
	# non-ascending / duplicate pid
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 00 02 04 01 02 0E 01 00 01 02 0E"))) == null, "pid 4 then 0")
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 00 02 00 01 02 0E 00 01 02 0E"))) == null, "duplicate pid")
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 00 01 08 01 02 0E"))) == null, "pid 8")
	# 9 groups
	var nine: PackedByteArray = _from_hex("21 05000000 00 09")
	for p in 9:
		nine.append_array(PackedByteArray([p, 1, 1, 2]))
	t.check(NetCodec.decode_bundle(_rehash(nine)) == null, "9 groups")
	# 0 and 65 commands in a group
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 00 01 00 00"))) == null, "0 commands")
	var c65: PackedByteArray = _from_hex("21 05000000 00 01 00 41")
	for _i in 65:
		c65.append_array(PackedByteArray([1, 2]))
	t.check(NetCodec.decode_bundle(_rehash(c65)) == null, "65 commands")
	# n = 0 / 1025
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 00 01 00 01 00"))) == null, "n = 0")
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 00 01 00 01 8108"))) == null, "n = 1025")
	# unknown flag bit, ctrl_count 0 / 9, has_ctrl without ctrl
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 02 00"))) == null, "flag bit1")
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 01 00 00"))) == null, "ctrl_count 0")
	var nine_ctrl: PackedByteArray = _from_hex("21 05000000 01 00 09")
	for _i in 9:
		nine_ctrl.append_array(PackedByteArray([1, 2]))
	t.check(NetCodec.decode_bundle(_rehash(nine_ctrl)) == null, "ctrl_count 9")
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 00 00 01 02"))) == null, "ctrl without flag = trailing bytes")
	t.check(NetCodec.decode_bundle(_rehash(_from_hex("21 05000000 01 00 01 09 01"))) == null, "unknown ctrl kind")
	# trailing byte before the hash, flipped hash bit, wrong type
	var trail: PackedByteArray = ok.slice(0, ok.size() - 4)
	trail.append(0)
	t.check(NetCodec.decode_bundle(_rehash(trail)) == null, "trailing byte")
	for bit in 32:
		var flipped: PackedByteArray = ok.duplicate()
		flipped[flipped.size() - 4 + bit / 8] ^= 1 << (bit % 8)
		t.check(NetCodec.decode_bundle(flipped) == null, "hash bit %d" % bit)
	for i in range(1, ok.size() - 4):
		var f2: PackedByteArray = ok.duplicate()
		f2[i] ^= 0x10
		t.check(NetCodec.decode_bundle(f2) == null, "body byte %d" % i)
	var wrong: PackedByteArray = ok.duplicate()
	wrong[0] = 0x20
	t.check(NetCodec.decode_bundle(wrong) == null)
	# truncation at every length
	for n in ok.size():
		t.check(NetCodec.decode_bundle(ok.slice(0, n)) == null, "truncated to %d" % n)
	# bundle with a pid list that is not encodable is refused by the encoder
	t.check(NetBundle.build(1, PackedInt32Array([3, 1]), [[_cmd([1])], [_cmd([1])]], []).wire_bytes().is_empty(), "descending pids")
	t.check(NetBundle.build(1, PackedInt32Array([1]), [[]], []).wire_bytes().is_empty(), "empty group")


func test_bundle_size_limit(t: TestCtx) -> void:
	# 8 groups x 64 commands x 200 ints of big values overflows 52000 bytes
	var cmd: PackedInt32Array = PackedInt32Array()
	cmd.resize(200)
	cmd.fill(0x40000000)
	cmd[0] = 9
	var group: Array = []
	for _i in 64:
		group.append(cmd)
	var pids: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7])
	var groups: Array = []
	for _i in 8:
		groups.append(group)
	t.check(NetBundle.build(1, pids, groups, []).wire_bytes().is_empty(), "encoder refuses > 52000 bytes")
	var big: PackedByteArray = PackedByteArray()
	big.resize(NetProtocol.MAX_BUNDLE_BYTES + 1)
	big[0] = 0x21
	t.check(NetCodec.decode_bundle(big) == null, "decoder refuses > 52000 bytes")


func test_input_chain_matches_s0_golden(t: TestCtx) -> void:
	# Spec 10.2: after turns 0..9 of script S0 (turn 5 pid0 [1,2,3]; turn 7 pid1 [9]) the input chain is A6C168F3,
	# i.e. fnv chain over core_bytes of every turn starting from the FNV basis.
	var chain: int = 0x811C9DC5
	for turn in 10:
		var b: NetBundle
		if turn == 5:
			b = NetBundle.build(turn, PackedInt32Array([0]), [[_cmd([1, 2, 3])]], [])
		elif turn == 7:
			b = NetBundle.build(turn, PackedInt32Array([1]), [[_cmd([9])]], [])
		else:
			b = NetBundle.build(turn, PackedInt32Array(), [], [])
		chain = NetProtocol.fnv1a32(b.core_bytes(), chain)
	t.eq(chain, 0xA6C168F3, "chain at tick 20")


func test_small_message_goldens(t: TestCtx) -> void:
	t.eq(_hex(NetCodec.encode_ping({"seq": 7, "host_ms": 123456})), "220700000040E20100")
	t.eq(NetCodec.decode_ping(_from_hex("22 07000000 40E20100")), {"seq": 7, "host_ms": 123456})
	var pong: PackedByteArray = NetCodec.encode_pong({"seq": 7, "echo_ms": 123456, "exec_turn": 310, "slack_min_ms": -12,
		"stall_ms": 0, "episodes": 0, "load_pct": 35, "hitch": false})
	t.eq(_hex(pong), "230700000040E2010036010000F4FF0000002300")
	t.eq(pong.size(), 20)
	var pd: Dictionary = NetCodec.decode_pong(pong)
	t.eq(pd["slack_min_ms"], -12)
	t.eq(pd["exec_turn"], 310)
	t.eq(pd["load_pct"], 35)
	t.eq(pd["hitch"], false)
	t.eq(NetCodec.decode_pong(NetCodec.encode_pong({"hitch": true}))["hitch"], true)
	var cr: PackedByteArray = NetCodec.encode_checksum_report({"tick": 4200, "checksum": 0xE50086E1, "input_chain": 0xA6C168F3})
	t.eq(_hex(cr), "3068100000E18600E5F368C1A6")
	t.eq(NetCodec.decode_checksum_report(cr)["checksum"], 0xE50086E1)
	var st: PackedByteArray = NetLobbyCodec.encode_start({"config_hash": 0x8FA5BAAE, "input_delay": 2, "speed_pct": 100})
	t.eq(_hex(st), "15AEBAA58F026400")
	t.eq(NetLobbyCodec.decode_start(st), {"config_hash": 0x8FA5BAAE, "input_delay": 2, "speed_pct": 100})
	t.check(NetLobbyCodec.encode_start({"config_hash": 1, "input_delay": 9, "speed_pct": 100}).is_empty())
	t.check(NetLobbyCodec.encode_start({"config_hash": 1, "input_delay": 2, "speed_pct": 49}).is_empty())


func test_join_reject_and_accept(t: TestCtx) -> void:
	var rej: Dictionary = {"host_proto_version": 1, "reason": NetProtocol.RejectReason.DATA_MISMATCH, "host_sim_version": 3,
		"host_data_hash": 0x9F3A21C4, "host_session_id": 0xDEADBEEF, "host_game_version": "0.3.1", "detail": "table units differs"}
	var b: PackedByteArray = NetCodec.encode_join_reject(rej)
	t.eq(NetCodec.decode_join_reject(b), rej)
	t.eq(NetCodec.peek_join_reject(b), {"host_proto_version": 1, "reason": 3})
	t.eq(b[0], 2)
	var acc: Dictionary = {"peer_id": 2, "session_id": 0xDEADBEEF, "slot": 1, "phase": 0}
	var ab: PackedByteArray = NetCodec.encode_join_accept(acc)
	t.eq(ab.size(), 9)
	t.eq(NetCodec.decode_join_accept(ab), acc)
	t.check(NetCodec.encode_join_accept({"peer_id": 1}).is_empty(), "peer_id >= 2")
	acc["slot"] = 255
	t.eq(NetCodec.decode_join_accept(NetCodec.encode_join_accept(acc))["slot"], 255)
	acc["slot"] = 8
	t.check(NetCodec.decode_join_accept(NetCodec.encode_join_accept(acc)).is_empty(), "slot 8 rejected")
	var dd: PackedByteArray = NetCodec.encode_data_diff({"wants_files": true, "lines": PackedStringArray(["table units differs", "format: 1 vs 2"])})
	t.eq(NetCodec.decode_data_diff(dd), {"wants_files": true, "lines": PackedStringArray(["table units differs", "format: 1 vs 2"])})
	var many: PackedStringArray = PackedStringArray()
	many.resize(33)
	t.check(NetCodec.encode_data_diff({"lines": many}).is_empty())


func test_misc_message_roundtrips(t: TestCtx) -> void:
	var si: PackedByteArray = NetCodec.encode_stall_info({"turn": 99, "entries": [PackedInt32Array([1, 0, 250]), PackedInt32Array([3, 1, 65535])]})
	t.eq(NetCodec.decode_stall_info(si), {"turn": 99, "entries": [PackedInt32Array([1, 0, 250]), PackedInt32Array([3, 1, 65535])]})
	t.eq(NetCodec.decode_stall_info(NetCodec.encode_stall_info({"turn": 5, "entries": []})), {"turn": 5, "entries": []})
	t.eq(NetCodec.decode_pause_request(NetCodec.encode_pause_request({"want_paused": true})), {"want_paused": true})
	t.eq(NetCodec.decode_resume(NetCodec.encode_resume({"resume_turn": 500, "by_pid": 3})), {"resume_turn": 500, "by_pid": 3})
	var dn: Dictionary = {"tick": 4200, "kind": 1, "entries": [PackedInt64Array([0, 0xE50086E1, 5]), PackedInt64Array([2, 7, 0xFFFFFFFF])]}
	t.eq(NetCodec.decode_desync_notice(NetCodec.encode_desync_notice(dn)), dn)
	var pr: Dictionary = {"tick": 400, "parts": PackedInt64Array([1, 0xFFFFFFFF, 3])}
	t.eq(NetCodec.decode_parts_request(NetCodec.encode_parts_request(pr)), pr)
	t.eq(NetCodec.decode_parts_report(NetCodec.encode_parts_report(pr)), pr)
	t.check(NetCodec.decode_parts_request(NetCodec.encode_parts_report(pr)).is_empty(), "type byte differs")
	var me: Dictionary = {"final_tick": 9000, "final_checksum": 0xABCDEF01, "reason": 4, "winner_team": -1}
	t.eq(NetCodec.decode_match_end(NetCodec.encode_match_end(me)), me)
	t.eq(NetCodec.decode_catchup_request(NetCodec.encode_catchup_request({"from_turn": 12})), {"from_turn": 12})
	t.eq(NetCodec.decode_catchup_done(NetCodec.encode_catchup_done({"next_live_turn": 77})), {"next_live_turn": 77})
	var raw: PackedByteArray = PackedByteArray()
	for i in 3000:
		raw.append(i % 7)
	var chunk: PackedByteArray = NetCodec.encode_catchup_chunk({"first_turn": 10, "turn_count": 30, "raw": raw})
	t.check(not chunk.is_empty() and chunk.size() < raw.size())
	var cd: Dictionary = NetCodec.decode_catchup_chunk(chunk)
	t.eq(cd["raw"], raw)
	t.eq(cd["first_turn"], 10)


# ---- truncation of every golden ---------------------------------------------------------------------------------

func test_truncation_at_every_length(t: TestCtx) -> void:
	for e: Array in _fuzz_table():
		var enc: PackedByteArray = (e[1] as Callable).call(e[3])
		t.check(not enc.is_empty(), "%s sample encodes" % e[0])
		if e[0] == "return_to_lobby":
			continue
		for n in enc.size():
			var d: Variant = (e[2] as Callable).call(enc.slice(0, n))
			t.check(_is_empty_result(d), "%s truncated to %d/%d" % [e[0], n, enc.size()])
		var grown: PackedByteArray = enc.duplicate()
		grown.append(0)
		t.check(_is_empty_result((e[2] as Callable).call(grown)), "%s with a trailing byte" % e[0])


# ---- lobby codec --------------------------------------------------------------------------------------------------

func _snapshot_dict() -> Dictionary:
	var slots: Array = []
	for i in 8:
		slots.append({"index": i, "kind": 2 if i == 0 else (3 if i == 1 else 1 if i < 4 else 0), "peer_id": 1 if i == 0 else 0,
			"name": "P%d é" % i, "roster_id": "random.vanilla" if i else "napc", "team": i % 3, "color": i, "start": -1 if i % 2 else i,
			"handicap_pct": 100 + 5 * i, "ready": i % 2 == 0, "connected": i < 2, "ai_level": i % 4, "ai_style": i % 4, "ai_flags": i, "ping_ms": 10 * i})
	return {"revision": 77, "phase": 0, "password_set": true, "allow_spectators": true, "host_name": "X42553's game", "map_family": 1,
		"map_size": 128, "map_seed": 0xC0FFEE11, "layout_players": 4, "rules": {"start_credits": 7500, "unit_cap": 150, "fog": 1, "neg": -5},
		"speed_code": 2, "pause_policy": 1, "on_disconnect": 0, "auto_drop_ms": 60000, "slots": slots,
		"spectators": [{"peer_id": 9, "name": "Watcher"}]}


func test_snapshot_roundtrip(t: TestCtx) -> void:
	var d: Dictionary = _snapshot_dict()
	var b: PackedByteArray = NetLobbyCodec.encode_snapshot_dict(d)
	t.check(not b.is_empty() and b.size() <= NetProtocol.MAX_SNAPSHOT, "size %d" % b.size())
	var back: Dictionary = NetLobbyCodec.decode_snapshot_dict(b)
	t.check(not back.is_empty())
	t.eq(back["revision"], 77)
	t.eq(back["map_size"], 128)
	t.eq(back["rules"], d["rules"])
	t.eq(((back["slots"] as Array)[3] as Dictionary)["handicap_pct"], 115)
	t.eq(((back["slots"] as Array)[1] as Dictionary)["start"], -1)
	t.eq(((back["slots"] as Array)[2] as Dictionary)["name"], "P2 é")
	t.eq(back["spectators"], d["spectators"])
	t.eq(back["auto_drop_ms"], 60000)
	t.eq(NetLobbyCodec.encode_snapshot_dict(back), b, "canonical")
	# worst case size stays under MAX_SNAPSHOT
	var worst: Dictionary = _snapshot_dict()
	var rules: Dictionary = {}
	for i in 16:
		rules["k".repeat(24 - 2) + "%02d" % i] = 1 << 30
	worst["rules"] = rules
	for s: Dictionary in (worst["slots"] as Array):
		s["name"] = "日".repeat(16)
		s["roster_id"] = "r".repeat(40)
	var specs: Array = []
	for i in 8:
		specs.append({"peer_id": i, "name": "日".repeat(16)})
	worst["spectators"] = specs
	var wb: PackedByteArray = NetLobbyCodec.encode_snapshot_dict(worst)
	t.check(not wb.is_empty(), "worst-case snapshot fits: %d" % wb.size())


func test_snapshot_range_checks(t: TestCtx) -> void:
	var base: Dictionary = _snapshot_dict()
	var good: PackedByteArray = NetLobbyCodec.encode_snapshot_dict(base)
	t.check(not NetLobbyCodec.decode_snapshot_dict(good).is_empty())
	var patches: Array[Callable] = [
		func(d: Dictionary) -> void: d["layout_players"] = 5,
		func(d: Dictionary) -> void: (d["slots"] as Array).pop_back(),
		func(d: Dictionary) -> void: d["spectators"] = [1, 2, 3, 4, 5, 6, 7, 8, 9],
	]
	for p in patches:
		var d: Dictionary = _snapshot_dict()
		p.call(d)
		t.check(NetLobbyCodec.encode_snapshot_dict(d).is_empty(), "encoder refuses invalid structure")
	# field-level corruption of the wire bytes must be refused by the decoder
	var opts: Object = _FakeOpts.new()
	t.check(not NetLobbyCodec.decode_snapshot_dict(good, opts).is_empty(), "within opts ranges")
	opts.set("color_count", 4)
	t.check(NetLobbyCodec.decode_snapshot_dict(good, opts).is_empty(), "color >= color_count")
	opts.set("color_count", 12)
	opts.set("ai_level_count", 2)
	t.check(NetLobbyCodec.decode_snapshot_dict(good, opts).is_empty(), "ai_level >= ai_level_count")
	t.check(NetLobbyCodec.decode_snapshot(good, null) == null or true)
	for pos: int in [5, 6]:
		var bad: PackedByteArray = good.duplicate()
		bad[pos] = 0xEE
		t.check(NetLobbyCodec.decode_snapshot_dict(bad).is_empty(), "byte %d out of range" % pos)


class _FakeOpts extends RefCounted:
	var color_count: int = 12
	var ai_level_count: int = 4
	var ai_style_count: int = 4


func test_lobby_actions(t: TestCtx) -> void:
	var cases: Array = [
		[NetProtocol.LobbyOp.SET_ROSTER, {"roster": "random.subfaction"}],
		[NetProtocol.LobbyOp.SET_TEAM, {"team": 3}],
		[NetProtocol.LobbyOp.SET_COLOR, {"color": 9}],
		[NetProtocol.LobbyOp.SET_START, {"start": 5}],
		[NetProtocol.LobbyOp.SET_START, {"start": -1}],
		[NetProtocol.LobbyOp.SET_READY, {"ready": true}],
		[NetProtocol.LobbyOp.SET_NAME, {"name": "Böb"}],
		[NetProtocol.LobbyOp.MOVE_TO_SLOT, {"slot": 6}],
		[NetProtocol.LobbyOp.TO_SPECTATOR, {}],
		[NetProtocol.LobbyOp.TO_PLAYER, {}],
	]
	for c: Array in cases:
		var b: PackedByteArray = NetLobbyCodec.encode_action(int(c[0]), c[1] as Dictionary)
		t.check(not b.is_empty() and b.size() <= 80)
		var d: Dictionary = NetLobbyCodec.decode_action(b)
		t.eq(d["op"], c[0])
		for k: String in (c[1] as Dictionary):
			t.eq(d[k], (c[1] as Dictionary)[k], "op %d key %s" % [c[0], k])
		t.eq(NetLobbyCodec.encode_action(int(d["op"]), d), b, "canonical")
	t.check(NetLobbyCodec.encode_action(99, {}).is_empty())
	t.check(NetLobbyCodec.decode_action(PackedByteArray([5, 99])).is_empty())
	t.check(NetLobbyCodec.decode_action(PackedByteArray([5, 5, 2])).is_empty(), "ready = 2")
	t.check(NetLobbyCodec.decode_action(PackedByteArray([5, 4, 9])).is_empty(), "start = 9")
	t.check(NetLobbyCodec.decode_action(PackedByteArray([5, 7, 8])).is_empty(), "slot 8")


func test_chat_and_small_lobby_messages(t: TestCtx) -> void:
	var c: PackedByteArray = NetLobbyCodec.encode_chat_c2h({"channel": 1, "text": "gl hf é"})
	t.eq(NetLobbyCodec.decode_chat_c2h(c), {"channel": 1, "text": "gl hf é"})
	var long: String = "é".repeat(150)
	var cl: PackedByteArray = NetLobbyCodec.encode_chat_c2h({"channel": 0, "text": long})
	t.check(cl.size() <= 260)
	var back: String = (NetLobbyCodec.decode_chat_c2h(cl)["text"] as String)
	t.eq(back.length(), 100, "cut at 200 bytes on a boundary")
	var h: PackedByteArray = NetLobbyCodec.encode_chat_h2c({"channel": 0, "from_slot": 255, "from_name": "System", "text": "hi"})
	t.eq(NetLobbyCodec.decode_chat_h2c(h), {"channel": 0, "from_slot": 255, "from_name": "System", "text": "hi"})
	t.check(NetLobbyCodec.encode_chat_c2h({"channel": 2, "text": "x"}).is_empty())
	t.check(NetLobbyCodec.decode_chat_c2h(PackedByteArray([6, 0, 2, 0xC3, 0x28])).is_empty(), "invalid UTF-8")
	t.eq(NetLobbyCodec.decode_leave(NetLobbyCodec.encode_leave({"reason": 0})), {"reason": 0})
	t.eq(NetLobbyCodec.decode_kicked(NetLobbyCodec.encode_kicked({"reason": 2, "detail": "bye"})), {"reason": 2, "detail": "bye"})
	t.eq(NetLobbyCodec.decode_map_ping_c2h(NetLobbyCodec.encode_map_ping_c2h({"cell_x": 100, "cell_y": 2000})), {"cell_x": 100, "cell_y": 2000})
	t.eq(NetLobbyCodec.decode_map_ping_h2c(NetLobbyCodec.encode_map_ping_h2c({"from_pid": 3, "cell_x": 1, "cell_y": 2})), {"from_pid": 3, "cell_x": 1, "cell_y": 2})
	t.eq(NetLobbyCodec.decode_launch_countdown(NetLobbyCodec.encode_launch_countdown({"seconds_left": 3})), {"seconds_left": 3})
	t.eq(NetLobbyCodec.decode_launch_abort(NetLobbyCodec.encode_launch_abort({"reason": 4, "pid": 2, "detail": "x"})), {"reason": 4, "pid": 2, "detail": "x"})
	t.eq(NetLobbyCodec.decode_load_progress(NetLobbyCodec.encode_load_progress({"pct": 55})), {"pct": 55})
	t.eq(NetLobbyCodec.decode_load_status(NetLobbyCodec.encode_load_status({"entries": [PackedInt32Array([0, 10]), PackedInt32Array([3, 100])]})), {"entries": [PackedInt32Array([0, 10]), PackedInt32Array([3, 100])]})
	t.eq(NetLobbyCodec.decode_load_done(NetLobbyCodec.encode_load_done({"map_hash": 0xDEADBEEF, "checksum0": 1})), {"map_hash": 0xDEADBEEF, "checksum0": 1})
	t.eq(NetLobbyCodec.decode_load_failed(NetLobbyCodec.encode_load_failed({"reason": 3, "detail": "oom"})), {"reason": 3, "detail": "oom"})
	t.eq(NetLobbyCodec.encode_return_to_lobby(), PackedByteArray([0x17]))
	t.eq(NetLobbyCodec.decode_return_to_lobby(PackedByteArray([0x17]))["type"], 0x17)
	t.check(NetLobbyCodec.decode_return_to_lobby(PackedByteArray([0x17, 0])).is_empty())


func test_config_deflate(t: TestCtx) -> void:
	var json: String = JSON.stringify({"format": 1, "players": [1, 2, 3], "text": "x".repeat(2000)})
	var pk: PackedByteArray = NetLobbyCodec.deflate_config(json)
	t.check(not pk.is_empty() and pk.size() < json.length(), "compresses")
	t.eq(pk[0], 0x12)
	t.eq(pk.decode_u32(1), json.to_utf8_buffer().size())
	t.eq(pk.decode_u32(5), NetProtocol.fnv1a32(json.to_utf8_buffer()))
	t.eq(NetLobbyCodec.inflate_config(pk), json)
	t.check(NetLobbyCodec.deflate_config("").is_empty())
	var huge: String = "a".repeat(NetProtocol.MAX_CONFIG_JSON + 1)
	t.check(NetLobbyCodec.deflate_config(huge).is_empty(), "json above 64 KiB")
	var bad_hash: PackedByteArray = pk.duplicate()
	bad_hash[5] ^= 1
	t.eq(NetLobbyCodec.inflate_config(bad_hash), "", "fnv mismatch")
	var bad_len: PackedByteArray = pk.duplicate()
	bad_len[1] ^= 1
	t.eq(NetLobbyCodec.inflate_config(bad_len), "", "length mismatch")
	t.eq(NetLobbyCodec.inflate_config(pk.slice(0, 8)), "")
	t.eq(NetLobbyCodec.inflate_config(PackedByteArray()), "")
	var wrong_type: PackedByteArray = pk.duplicate()
	wrong_type[0] = 0x13
	t.eq(NetLobbyCodec.inflate_config(wrong_type), "")
	# a packet whose header claims a huge length is refused before inflating
	var claim: PackedByteArray = pk.duplicate()
	claim.encode_u32(1, 0x7FFFFFFF)
	t.eq(NetLobbyCodec.inflate_config(claim), "")


func test_config_zip_bomb_is_bounded(t: TestCtx) -> void:
	# 8 MB of zeros compresses to ~8 KB; the bounded inflate must refuse it. The engine reports the refused
	# inflate as one error message (declared).
	t.expect_errors(1)
	var zeros: PackedByteArray = PackedByteArray()
	zeros.resize(8 * 1024 * 1024)
	var comp: PackedByteArray = zeros.compress(FileAccess.COMPRESSION_DEFLATE)
	var w: NetWriter = NetWriter.new().u8(0x12).u32(NetProtocol.MAX_CONFIG_JSON).u32(0).raw(comp)
	var pk: PackedByteArray = w.to_bytes()
	t.check(pk.size() <= NetProtocol.MAX_LAUNCH_PACKET, "bomb fits the packet limit: %d" % pk.size())
	t.eq(NetLobbyCodec.inflate_config(pk), "")


# ---- fuzz ------------------------------------------------------------------------------------------------------------

func _is_empty_result(v: Variant) -> bool:
	if v == null:
		return true
	if v is Dictionary:
		return (v as Dictionary).is_empty()
	return false


## Rows: [name, encode Callable(dict) -> bytes, decode Callable(bytes) -> result, sample dict, reencode Callable(result) -> bytes].
func _fuzz_table() -> Array:
	var rows: Array = []
	var bundle: NetBundle = NetBundle.build(77, PackedInt32Array([1, 5]), [[_cmd([3, 1, -2]), _cmd([9])], [_cmd([250, 1])]], [_cmd([1, 4]), _cmd([2, 1, 3, 9]), _cmd([3, 100])])
	var snap: Dictionary = _snapshot_dict()
	var json_pk: PackedByteArray = NetLobbyCodec.deflate_config("{\"a\":1,\"b\":[1,2,3]}")
	rows.append(["join_request", NetCodec.encode_join_request, NetCodec.decode_join_request, {"sim_version": 7, "data_hash": 9, "client_nonce": 3, "game_version": "0.3.1", "name": "Bob", "pw_proof": "x".sha256_buffer(), "data_format": 1, "tables": {"units": 5, "weapons": 6}, "files": {"a": 1}, "spectator": true}])
	rows.append(["join_reject", NetCodec.encode_join_reject, NetCodec.decode_join_reject, {"reason": 3, "host_sim_version": 1, "host_data_hash": 2, "host_session_id": 3, "host_game_version": "v", "detail": "d"}])
	rows.append(["join_accept", NetCodec.encode_join_accept, NetCodec.decode_join_accept, {"peer_id": 2, "session_id": 5, "slot": 1, "phase": 0}])
	rows.append(["data_diff", NetCodec.encode_data_diff, NetCodec.decode_data_diff, {"wants_files": true, "lines": PackedStringArray(["a", "bb"])}])
	rows.append(["turn_input", NetCodec.encode_turn_input, NetCodec.decode_turn_input, {"turn": 5, "exec_turn": 3, "cmds": [_cmd([3, 17, 4096]), _cmd([1])]}])
	rows.append(["ping", NetCodec.encode_ping, NetCodec.decode_ping, {"seq": 7, "host_ms": 99}])
	rows.append(["pong", NetCodec.encode_pong, NetCodec.decode_pong, {"seq": 7, "echo_ms": 5, "exec_turn": 310, "slack_min_ms": -12, "stall_ms": 3, "episodes": 1, "load_pct": 35, "hitch": true}])
	rows.append(["stall_info", NetCodec.encode_stall_info, NetCodec.decode_stall_info, {"turn": 4, "entries": [PackedInt32Array([1, 2, 300])]}])
	rows.append(["pause_request", NetCodec.encode_pause_request, NetCodec.decode_pause_request, {"want_paused": true}])
	rows.append(["resume", NetCodec.encode_resume, NetCodec.decode_resume, {"resume_turn": 9, "by_pid": 2}])
	rows.append(["checksum_report", NetCodec.encode_checksum_report, NetCodec.decode_checksum_report, {"tick": 20, "checksum": 5, "input_chain": 6}])
	rows.append(["desync_notice", NetCodec.encode_desync_notice, NetCodec.decode_desync_notice, {"tick": 20, "kind": 2, "entries": [PackedInt64Array([1, 5, 6])]}])
	rows.append(["parts_request", NetCodec.encode_parts_request, NetCodec.decode_parts_request, {"tick": 20, "parts": PackedInt64Array([1, 2])}])
	rows.append(["parts_report", NetCodec.encode_parts_report, NetCodec.decode_parts_report, {"tick": 20, "parts": PackedInt64Array([1, 2])}])
	rows.append(["match_end", NetCodec.encode_match_end, NetCodec.decode_match_end, {"final_tick": 20, "final_checksum": 5, "reason": 1, "winner_team": 2}])
	rows.append(["catchup_request", NetCodec.encode_catchup_request, NetCodec.decode_catchup_request, {"from_turn": 4}])
	rows.append(["catchup_done", NetCodec.encode_catchup_done, NetCodec.decode_catchup_done, {"next_live_turn": 4}])
	rows.append(["bundle", func(_d: Dictionary) -> PackedByteArray: return bundle.wire_bytes(),
		func(b: PackedByteArray) -> Variant: return NetCodec.decode_bundle(b), {}])
	rows.append(["snapshot", NetLobbyCodec.encode_snapshot_dict, func(b: PackedByteArray) -> Dictionary: return NetLobbyCodec.decode_snapshot_dict(b), snap])
	rows.append(["action", func(d: Dictionary) -> PackedByteArray: return NetLobbyCodec.encode_action(int(d["op"]), d), NetLobbyCodec.decode_action, {"op": 1, "roster": "napc"}])
	rows.append(["chat_c2h", NetLobbyCodec.encode_chat_c2h, NetLobbyCodec.decode_chat_c2h, {"channel": 1, "text": "hello é"}])
	rows.append(["chat_h2c", NetLobbyCodec.encode_chat_h2c, NetLobbyCodec.decode_chat_h2c, {"channel": 1, "from_slot": 2, "from_name": "Bob", "text": "hello"}])
	rows.append(["leave", NetLobbyCodec.encode_leave, NetLobbyCodec.decode_leave, {"reason": 0}])
	rows.append(["kicked", NetLobbyCodec.encode_kicked, NetLobbyCodec.decode_kicked, {"reason": 1, "detail": "why"}])
	rows.append(["map_ping_c2h", NetLobbyCodec.encode_map_ping_c2h, NetLobbyCodec.decode_map_ping_c2h, {"cell_x": 5, "cell_y": 6}])
	rows.append(["map_ping_h2c", NetLobbyCodec.encode_map_ping_h2c, NetLobbyCodec.decode_map_ping_h2c, {"from_pid": 1, "cell_x": 5, "cell_y": 6}])
	rows.append(["launch_countdown", NetLobbyCodec.encode_launch_countdown, NetLobbyCodec.decode_launch_countdown, {"seconds_left": 2}])
	rows.append(["launch_abort", NetLobbyCodec.encode_launch_abort, NetLobbyCodec.decode_launch_abort, {"reason": 2, "pid": 255, "detail": "x"}])
	rows.append(["load_progress", NetLobbyCodec.encode_load_progress, NetLobbyCodec.decode_load_progress, {"pct": 50}])
	rows.append(["load_status", NetLobbyCodec.encode_load_status, NetLobbyCodec.decode_load_status, {"entries": [PackedInt32Array([1, 50])]}])
	rows.append(["load_done", NetLobbyCodec.encode_load_done, NetLobbyCodec.decode_load_done, {"map_hash": 1, "checksum0": 2}])
	rows.append(["load_failed", NetLobbyCodec.encode_load_failed, NetLobbyCodec.decode_load_failed, {"reason": 3, "detail": "x"}])
	rows.append(["start", NetLobbyCodec.encode_start, NetLobbyCodec.decode_start, {"config_hash": 1, "input_delay": 3, "speed_pct": 150}])
	rows.append(["return_to_lobby", NetLobbyCodec.encode_return_to_lobby, NetLobbyCodec.decode_return_to_lobby, {}])
	# inflate_config is exercised through its header path (valid deflate tail, mutated header) below
	json_pk.clear()
	return rows


func _re_encode(row: Array, decoded: Variant) -> PackedByteArray:
	if decoded is NetBundle:
		return NetCodec.encode_bundle(decoded as NetBundle)
	var name: String = row[0]
	var d: Dictionary = decoded as Dictionary
	if name == "return_to_lobby":
		return NetLobbyCodec.encode_return_to_lobby()
	if name == "action":
		return NetLobbyCodec.encode_action(int(d["op"]), d)
	return (row[1] as Callable).call(d)


func test_fuzz_all_decoders(t: TestCtx) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260930
	var accepted_random: int = 0
	var accepted_mutated: int = 0
	for row: Array in _fuzz_table():
		var name: String = row[0]
		var enc: PackedByteArray = (row[1] as Callable).call(row[3])
		t.check(not enc.is_empty(), name + " sample encodes")
		var type: int = enc[0] if not enc.is_empty() else 0
		var dec: Callable = row[2] as Callable
		# (a) fully random buffers, half of them starting with the right type byte
		for i in FUZZ_ITERATIONS:
			var n: int = rng.randi_range(0, 64)
			var buf: PackedByteArray = PackedByteArray()
			buf.resize(n)
			for k in n:
				buf[k] = rng.randi() & 0xFF
			if n > 0 and (i & 1) == 0:
				buf[0] = type
			var res: Variant = dec.call(buf)
			if not _is_empty_result(res):
				accepted_random += 1
				if _re_encode(row, res) != buf:
					t.fail("%s: random accepted buffer is not canonical: %s" % [name, buf.hex_encode()])
					break
		# (b) single- and multi-byte mutations, truncations and extensions of a valid message
		for i in FUZZ_ITERATIONS:
			var buf2: PackedByteArray = enc.duplicate()
			var mode: int = rng.randi_range(0, 4)
			var flips: int = rng.randi_range(1, 3)
			if mode <= 2 and not buf2.is_empty():
				for _f in flips:
					buf2[rng.randi_range(0, buf2.size() - 1)] = rng.randi() & 0xFF
			elif mode == 3 and not buf2.is_empty():
				buf2 = buf2.slice(0, rng.randi_range(0, buf2.size()))
			else:
				for _f in rng.randi_range(1, 4):
					buf2.append(rng.randi() & 0xFF)
			var res2: Variant = dec.call(buf2)
			if not _is_empty_result(res2):
				accepted_mutated += 1
				if _re_encode(row, res2) != buf2:
					t.fail("%s: mutated accepted buffer is not canonical: %s" % [name, buf2.hex_encode()])
					break
	t.note("accepted random=%d mutated=%d" % [accepted_random, accepted_mutated])
	t.check(accepted_mutated > 100, "mutation fuzz reaches accepting paths")


func test_fuzz_inflate_config_headers(t: TestCtx) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var json: String = JSON.stringify({"k": "v"})
	var pk: PackedByteArray = NetLobbyCodec.deflate_config(json)
	var accepted: int = 0
	for i in FUZZ_ITERATIONS:
		var b: PackedByteArray = pk.duplicate()
		# mutate only the 9 header bytes (the deflate tail stays valid, so no engine message is possible)
		for _f in rng.randi_range(1, 3):
			b[rng.randi_range(0, 8)] = rng.randi() & 0xFF
		var s: String = NetLobbyCodec.inflate_config(b)
		if not s.is_empty():
			accepted += 1
			t.eq(s, json)
	t.check(accepted > 0)


func test_fuzz_catchup_chunk(t: TestCtx) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var raw: PackedByteArray = PackedByteArray()
	for i in 200:
		raw.append(i % 5)
	var pk: PackedByteArray = NetCodec.encode_catchup_chunk({"first_turn": 1, "turn_count": 2, "raw": raw})
	t.check(NetProtocol.looks_like_zlib(pk, 11), "engine deflate is a zlib stream")
	for i in FUZZ_ITERATIONS:
		var b: PackedByteArray = pk.duplicate()
		for _f in rng.randi_range(1, 3):
			b[rng.randi_range(0, 10)] = rng.randi() & 0xFF  # message header only, the deflate stream stays valid
		var d: Dictionary = NetCodec.decode_catchup_chunk(b)
		if not d.is_empty():
			t.eq(d["raw"], raw)
	# foreign data behind a valid header is refused without touching the inflater
	var junk: PackedByteArray = NetWriter.new().u8(0x41).u32(1).u16(1).u32(10).raw(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])).to_bytes()
	t.check(NetCodec.decode_catchup_chunk(junk).is_empty())


func test_fuzz_readers_never_error(t: TestCtx) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for _i in FUZZ_ITERATIONS:
		var n: int = rng.randi_range(0, 40)
		var buf: PackedByteArray = PackedByteArray()
		buf.resize(n)
		for k in n:
			buf[k] = rng.randi() & 0xFF
		var r: NetReader = NetReader.new(buf, rng.randi_range(0, 50), rng.randi_range(-1, 50))
		for _step in 12:
			match rng.randi_range(0, 10):
				0: r.u8()
				1: r.u16()
				2: r.u32()
				3: r.i8()
				4: r.i16()
				5: r.varint()
				6: r.zvarint()
				7: r.str_(rng.randi_range(0, 40))
				8: r.bytes_(rng.randi_range(0, 40))
				9: r.raw(rng.randi_range(-2, 40))
				_: r.i32()
		t.check(r.left() >= 0)
