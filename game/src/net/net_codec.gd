class_name NetCodec
extends RefCounted
## Static encode/decode of the handshake, turn, control, checksum, pause/stall, desync and catch-up messages
## (docs/spec/net.md 3.9, 4.4). For every message X: `encode_x(fields: Dictionary) -> PackedByteArray`
## (EMPTY on over-limit/invalid input) and `decode_x(bytes) -> Dictionary` (EMPTY on any failure, including
## leftover bytes, wrong type byte or an over-size message). Decoders are total: they never raise an engine
## error. Any accepted buffer re-encodes to identical bytes (canonical form).
##
## Lobby / launch / chat messages live in NetLobbyCodec.

# ---- helpers ------------------------------------------------------------------------------------------

## Message type byte of `bytes`, -1 when empty.
static func peek_type(bytes: PackedByteArray) -> int:
	return -1 if bytes.is_empty() else bytes[0]


## Reader positioned after the type byte, or null when the type differs or the message is over its size limit.
static func open(bytes: PackedByteArray, type: int) -> NetReader:
	if bytes.is_empty() or bytes[0] != type or bytes.size() > NetProtocol.msg_max_bytes(type):
		return null
	return NetReader.new(bytes, 1)


static func _w(type: int) -> NetWriter:
	return NetWriter.new().u8(type)


static func _finish(w: NetWriter, type: int) -> PackedByteArray:
	if w.size() > NetProtocol.msg_max_bytes(type):
		return PackedByteArray()
	return w.to_bytes()


static func _i(d: Dictionary, key: String, def: int = 0) -> int:
	var v: Variant = d.get(key, def)
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_BOOL or typeof(v) == TYPE_FLOAT else def


static func _s(d: Dictionary, key: String) -> String:
	var v: Variant = d.get(key, "")
	return str(v) if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME else ""


static func _in(v: int, lo: int, hi: int) -> bool:
	return v >= lo and v <= hi


# ---- commands (shared by input, bundle and replay records) -------------------------------------------------

## Writes `varint count` + commands (`varint n` + n x zvarint each). Returns false (writer content then
## undefined) for > MAX_CMDS_PER_TURN commands, a command of 0 or > MAX_CMD_INTS ints, or ints[0] outside 0..255.
static func encode_commands(cmds: Array, w: NetWriter) -> bool:
	if cmds.size() > NetProtocol.MAX_CMDS_PER_TURN:
		return false
	w.varint(cmds.size())
	for c: Variant in cmds:
		if typeof(c) != TYPE_PACKED_INT32_ARRAY:
			return false
		var ints: PackedInt32Array = c
		var n: int = ints.size()
		if n < 1 or n > NetProtocol.MAX_CMD_INTS or ints[0] < 0 or ints[0] > 255:
			return false
		w.varint(n)
		for v in ints:
			w.zvarint(v)
	return true


## Reads what encode_commands wrote. `max_cmds` caps the count (0 allowed = heartbeat). On any violation
## r.ok becomes false and [] is returned. Result: Array[PackedInt32Array].
static func decode_commands(r: NetReader, max_cmds: int) -> Array:
	var out: Array = []
	var count: int = r.varint()
	if not r.ok or count > max_cmds or count > NetProtocol.MAX_CMDS_PER_TURN:
		r.ok = false
		return []
	for _i0 in count:
		var n: int = r.varint()
		if not r.ok or n < 1 or n > NetProtocol.MAX_CMD_INTS or n > r.left():
			r.ok = false
			return []
		var ints: PackedInt32Array = PackedInt32Array()
		ints.resize(n)
		for k in n:
			ints[k] = r.zvarint()
		if not r.ok or ints[0] < 0 or ints[0] > 255:
			r.ok = false
			return []
		out.append(ints)
	return out


# ---- JOIN_REQUEST / JOIN_REJECT / JOIN_ACCEPT / DATA_DIFF ---------------------------------------------------

## fields: proto_version (default PROTO_VERSION), spectator:bool, sim_version, data_hash, client_nonce,
## game_version (<=24 B), name (<=48 B); optional pw_proof:PackedByteArray(32) [flag bit1], tables:{String->int}
## + data_format [bit2] (<=32 tables), files:{String->int} [bit3] (<=160 files).
static func encode_join_request(f: Dictionary) -> PackedByteArray:
	var has_pw: bool = f.has("pw_proof")
	var has_tables: bool = f.has("tables")
	var has_files: bool = f.has("files")
	var flags: int = (1 if bool(f.get("spectator", false)) else 0) | (2 if has_pw else 0) | (4 if has_tables else 0) | (8 if has_files else 0)
	var w: NetWriter = _w(NetProtocol.Msg.JOIN_REQUEST)
	w.u16(_i(f, "proto_version", NetProtocol.PROTO_VERSION)).u8(flags)
	w.u32(_i(f, "sim_version")).u32(_i(f, "data_hash")).u32(_i(f, "client_nonce"))
	w.str_(_s(f, "game_version"), 24).str_(_s(f, "name"), 48)
	if has_pw:
		var pw: PackedByteArray = f["pw_proof"] as PackedByteArray
		if pw.size() != 32:
			return PackedByteArray()
		w.raw(pw)
	if has_tables:
		var t: Dictionary = f["tables"] as Dictionary
		if t.size() > 32:
			return PackedByteArray()
		w.u8(_i(f, "data_format")).u8(t.size())
		for k: Variant in t:
			w.str_(str(k), 32).u32(int(t[k]))
	if has_files:
		var fl: Dictionary = f["files"] as Dictionary
		if fl.size() > 160:
			return PackedByteArray()
		w.u16(fl.size())
		for k: Variant in fl:
			w.str_(str(k), 64).u32(int(fl[k]))
	return _finish(w, NetProtocol.Msg.JOIN_REQUEST)


static func _read_hash_table(r: NetReader, count: int, name_max: int) -> Dictionary:
	var d: Dictionary = {}
	for _k in count:
		var key: String = r.str_(name_max)
		var h: int = r.u32()
		if not r.ok or d.has(key):
			r.ok = false
			return {}
		d[key] = h
	return d


static func decode_join_request(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.JOIN_REQUEST)
	if r == null:
		return {}
	var out: Dictionary = {}
	out["proto_version"] = r.u16()
	var flags: int = r.u8()
	if flags & 0xF0:
		return {}
	out["flags"] = flags
	out["spectator"] = (flags & 1) != 0
	out["sim_version"] = r.u32()
	out["data_hash"] = r.u32()
	out["client_nonce"] = r.u32()
	out["game_version"] = r.str_(24)
	out["name"] = r.str_(48)
	if flags & 2:
		out["pw_proof"] = r.raw(32)
	if flags & 4:
		out["data_format"] = r.u8()
		var n: int = r.u8()
		if n > 32:
			return {}
		out["tables"] = _read_hash_table(r, n, 32)
	if flags & 8:
		var nf: int = r.u16()
		if nf > 160:
			return {}
		out["files"] = _read_hash_table(r, nf, 64)
	return out if r.done() else {}


## Frozen prefix: {proto_version} from any JOIN_REQUEST of any version (>= 3 bytes, type 0x01), else {}.
static func peek_join_request(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 3 or bytes[0] != NetProtocol.Msg.JOIN_REQUEST:
		return {}
	return {"proto_version": bytes[1] | (bytes[2] << 8)}


## fields: host_proto_version, reason (RejectReason), host_sim_version, host_data_hash, host_session_id,
## host_game_version (<=24 B), detail (<=96 B).
static func encode_join_reject(f: Dictionary) -> PackedByteArray:
	var w: NetWriter = _w(NetProtocol.Msg.JOIN_REJECT)
	w.u16(_i(f, "host_proto_version", NetProtocol.PROTO_VERSION)).u8(_i(f, "reason"))
	w.u32(_i(f, "host_sim_version")).u32(_i(f, "host_data_hash")).u32(_i(f, "host_session_id"))
	w.str_(_s(f, "host_game_version"), 24).str_(_s(f, "detail"), 96)
	return _finish(w, NetProtocol.Msg.JOIN_REJECT)


static func decode_join_reject(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.JOIN_REJECT)
	if r == null:
		return {}
	var out: Dictionary = {}
	out["host_proto_version"] = r.u16()
	out["reason"] = r.u8()
	out["host_sim_version"] = r.u32()
	out["host_data_hash"] = r.u32()
	out["host_session_id"] = r.u32()
	out["host_game_version"] = r.str_(24)
	out["detail"] = r.str_(96)
	if not r.done() or not _in(int(out["reason"]), 0, NetProtocol.RejectReason.TOO_MANY_CONNECTIONS):
		return {}
	return out


## Frozen prefix of JOIN_REJECT: {host_proto_version, reason} (>= 4 bytes, type 0x02), else {}.
static func peek_join_reject(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4 or bytes[0] != NetProtocol.Msg.JOIN_REJECT:
		return {}
	return {"host_proto_version": bytes[1] | (bytes[2] << 8), "reason": bytes[3]}


## fields: peer_id (>= 2), session_id, slot (0..7, 255 spectator), phase (LobbyPhase).
static func encode_join_accept(f: Dictionary) -> PackedByteArray:
	if _i(f, "peer_id") < 2:
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.JOIN_ACCEPT)
	w.u16(_i(f, "peer_id")).u32(_i(f, "session_id")).u8(_i(f, "slot")).u8(_i(f, "phase"))
	return _finish(w, NetProtocol.Msg.JOIN_ACCEPT)


static func decode_join_accept(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.JOIN_ACCEPT)
	if r == null:
		return {}
	var out: Dictionary = {"peer_id": r.u16(), "session_id": r.u32(), "slot": r.u8(), "phase": r.u8()}
	if not r.done() or int(out["peer_id"]) < 2 or not (int(out["slot"]) <= 7 or int(out["slot"]) == 255) or int(out["phase"]) > NetProtocol.LobbyPhase.ENDED:
		return {}
	return out


## fields: wants_files:bool, lines:PackedStringArray (<=32, each <=96 B).
static func encode_data_diff(f: Dictionary) -> PackedByteArray:
	var lines: PackedStringArray = f.get("lines", PackedStringArray()) as PackedStringArray
	if lines.size() > 32:
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.DATA_DIFF)
	w.u8(1 if bool(f.get("wants_files", false)) else 0).u8(lines.size())
	for l in lines:
		w.str_(l, 96)
	return _finish(w, NetProtocol.Msg.DATA_DIFF)


static func decode_data_diff(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.DATA_DIFF)
	if r == null:
		return {}
	var flags: int = r.u8()
	var n: int = r.u8()
	if flags > 1 or n > 32:
		return {}
	var lines: PackedStringArray = PackedStringArray()
	for _k in n:
		lines.append(r.str_(96))
	if not r.done():
		return {}
	return {"wants_files": flags == 1, "lines": lines}


# ---- TURN_INPUT ---------------------------------------------------------------------------------------------

## fields: turn, exec_turn, cmds:Array[PackedInt32Array] (0 = heartbeat).
static func encode_turn_input(f: Dictionary) -> PackedByteArray:
	var w: NetWriter = _w(NetProtocol.Msg.TURN_INPUT)
	w.u32(_i(f, "turn")).u32(_i(f, "exec_turn"))
	if not encode_commands(f.get("cmds", []) as Array, w):
		return PackedByteArray()
	return _finish(w, NetProtocol.Msg.TURN_INPUT)


static func decode_turn_input(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.TURN_INPUT)
	if r == null:
		return {}
	var turn: int = r.u32()
	var exec_turn: int = r.u32()
	var cmds: Array = decode_commands(r, NetProtocol.MAX_CMDS_PER_TURN)
	if not r.done():
		return {}
	return {"turn": turn, "exec_turn": exec_turn, "cmds": cmds}


## The two leading u32s of a (possibly malformed) TURN_INPUT: {turn, exec_turn}, or {} when < 9 bytes / wrong
## type. Lets the host substitute an empty input for a decodable turn number (spec 5.5.5 TOO_BIG).
static func peek_turn_input_header(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 9 or bytes[0] != NetProtocol.Msg.TURN_INPUT:
		return {}
	return {"turn": bytes.decode_u32(1), "exec_turn": bytes.decode_u32(5)}


# ---- TURN_BUNDLE ----------------------------------------------------------------------------------------------

static func _write_groups(w: NetWriter, pids: PackedInt32Array, group_cmds: Array) -> bool:
	if pids.size() != group_cmds.size() or pids.size() > NetProtocol.MAX_PLAYERS:
		return false
	w.u8(pids.size())
	var prev: int = -1
	for i in pids.size():
		var pid: int = pids[i]
		var cmds: Array = group_cmds[i] as Array
		if pid <= prev or pid > 7 or cmds.is_empty():
			return false
		prev = pid
		w.u8(pid)
		if not encode_commands(cmds, w):
			return false
	return true


## Canonical chain/replay bytes: u32 turn | u8 group_count | groups. Empty when the content is invalid.
static func encode_turn_core(turn: int, pids: PackedInt32Array, group_cmds: Array) -> PackedByteArray:
	var w: NetWriter = NetWriter.new()
	w.u32(turn)
	if not _write_groups(w, pids, group_cmds):
		return PackedByteArray()
	return w.to_bytes()


static func _valid_ctrl(c: PackedInt32Array) -> bool:
	if c.is_empty():
		return false
	match c[0]:
		NetProtocol.CtrlKind.INPUT_DELAY:
			return c.size() == 2 and _in(c[1], 1, NetProtocol.D_MAX)
		NetProtocol.CtrlKind.PLAYER_STATUS:
			return c.size() == 4 and _in(c[1], 0, 7) and _in(c[2], 0, 7) and _in(c[3], 0, 255)
		NetProtocol.CtrlKind.SPEED:
			return c.size() == 2 and _in(c[1], 50, 200)
		NetProtocol.CtrlKind.MATCH_END:
			return c.size() == 2 and _in(c[1], 0, NetProtocol.MatchEndReason.DESYNC)
		NetProtocol.CtrlKind.PAUSE:
			return c.size() == 2 and (_in(c[1], 0, 7) or c[1] == 255)
	return false


static func _write_ctrl(w: NetWriter, c: PackedInt32Array) -> void:
	w.u8(c[0])
	if c[0] == NetProtocol.CtrlKind.SPEED:
		w.u16(c[1])
	else:
		for i in range(1, c.size()):
			w.u8(c[i])


static func _read_ctrl(r: NetReader) -> PackedInt32Array:
	var kind: int = r.u8()
	var c: PackedInt32Array = PackedInt32Array([kind])
	match kind:
		NetProtocol.CtrlKind.INPUT_DELAY, NetProtocol.CtrlKind.MATCH_END, NetProtocol.CtrlKind.PAUSE:
			c.append(r.u8())
		NetProtocol.CtrlKind.PLAYER_STATUS:
			c.append(r.u8())
			c.append(r.u8())
			c.append(r.u8())
		NetProtocol.CtrlKind.SPEED:
			c.append(r.u16())
		_:
			r.ok = false
	if r.ok and not _valid_ctrl(c):
		r.ok = false
	return c


## The full TURN_BUNDLE message including the trailing FNV-1a. Empty when the bundle violates a limit.
static func encode_bundle(b: NetBundle) -> PackedByteArray:
	var w: NetWriter = _w(NetProtocol.Msg.TURN_BUNDLE)
	w.u32(b.turn)
	var has_ctrl: bool = not b.ctrl.is_empty()
	if b.ctrl.size() > 8:
		return PackedByteArray()
	w.u8(1 if has_ctrl else 0)
	if not _write_groups(w, b.pids, b.group_cmds):
		return PackedByteArray()
	if has_ctrl:
		w.u8(b.ctrl.size())
		for c: Variant in b.ctrl:
			if typeof(c) != TYPE_PACKED_INT32_ARRAY or not _valid_ctrl(c as PackedInt32Array):
				return PackedByteArray()
			_write_ctrl(w, c as PackedInt32Array)
	var body: PackedByteArray = w.to_bytes()
	w.u32(NetProtocol.fnv1a32(body, 0x811C9DC5, 1))
	return _finish(w, NetProtocol.Msg.TURN_BUNDLE)


## Strict decode (null on any failure): hash, contiguous ascending pids, limits, flags, ctrl ranges, no trailing bytes.
static func decode_bundle(bytes: PackedByteArray) -> NetBundle:
	if bytes.size() < 11 or bytes.size() > NetProtocol.MAX_BUNDLE_BYTES or bytes[0] != NetProtocol.Msg.TURN_BUNDLE:
		return null
	var body_end: int = bytes.size() - 4
	if NetProtocol.fnv1a32(bytes, 0x811C9DC5, 1, body_end) != bytes.decode_u32(body_end):
		return null
	var r: NetReader = NetReader.new(bytes, 1, body_end)
	var turn: int = r.u32()
	var flags: int = r.u8()
	if flags & 0xFE:
		return null
	var groups: int = r.u8()
	if groups > NetProtocol.MAX_PLAYERS:
		return null
	var pids: PackedInt32Array = PackedInt32Array()
	var group_cmds: Array = []
	var prev: int = -1
	for _g in groups:
		var pid: int = r.u8()
		if not r.ok or pid <= prev or pid > 7:
			return null
		prev = pid
		var cmds: Array = decode_commands(r, NetProtocol.MAX_CMDS_PER_TURN)
		if not r.ok or cmds.is_empty():
			return null
		pids.append(pid)
		group_cmds.append(cmds)
	var core_end: int = r.pos()
	var ctrl: Array = []
	if flags & 1:
		var cc: int = r.u8()
		if not _in(cc, 1, 8):
			return null
		for _c in cc:
			ctrl.append(_read_ctrl(r))
			if not r.ok:
				return null
	if not r.done():
		return null
	var out: NetBundle = NetBundle.new()
	out.turn = turn
	out.flags = flags
	out.pids = pids
	out.group_cmds = group_cmds
	out.ctrl = ctrl
	out._prime(bytes.slice(1, 5) + bytes.slice(6, core_end), bytes)
	return out


# ---- PING / PONG / STALL_INFO / PAUSE / RESUME -----------------------------------------------------------

## fields: seq, host_ms (low 32 bits of the host clock in ms).
static func encode_ping(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.PING).u32(_i(f, "seq")).u32(_i(f, "host_ms")), NetProtocol.Msg.PING)


static func decode_ping(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.PING)
	if r == null:
		return {}
	var out: Dictionary = {"seq": r.u32(), "host_ms": r.u32()}
	return out if r.done() else {}


## fields: seq, echo_ms, exec_turn, slack_min_ms (i16), stall_ms (u16), episodes, load_pct, hitch:bool.
static func encode_pong(f: Dictionary) -> PackedByteArray:
	var w: NetWriter = _w(NetProtocol.Msg.PONG)
	w.u32(_i(f, "seq")).u32(_i(f, "echo_ms")).u32(_i(f, "exec_turn"))
	w.i16(clampi(_i(f, "slack_min_ms"), -32768, 32767)).u16(clampi(_i(f, "stall_ms"), 0, 65535))
	w.u8(clampi(_i(f, "episodes"), 0, 255)).u8(clampi(_i(f, "load_pct"), 0, 255)).u8(1 if bool(f.get("hitch", false)) else 0)
	return _finish(w, NetProtocol.Msg.PONG)


static func decode_pong(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.PONG)
	if r == null:
		return {}
	var out: Dictionary = {}
	out["seq"] = r.u32()
	out["echo_ms"] = r.u32()
	out["exec_turn"] = r.u32()
	out["slack_min_ms"] = r.i16()
	out["stall_ms"] = r.u16()
	out["episodes"] = r.u8()
	out["load_pct"] = r.u8()
	var fl: int = r.u8()
	out["hitch"] = (fl & 1) != 0
	if not r.done() or fl > 1:
		return {}
	return out


## fields: turn, entries:Array[PackedInt32Array [pid, reason, wait_ms]] (<=8; an empty list clears the overlay).
static func encode_stall_info(f: Dictionary) -> PackedByteArray:
	var entries: Array = f.get("entries", []) as Array
	if entries.size() > 8:
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.STALL_INFO)
	w.u32(_i(f, "turn")).u8(entries.size())
	for e: Variant in entries:
		var v: PackedInt32Array = e as PackedInt32Array
		if v.size() != 3:
			return PackedByteArray()
		w.u8(v[0]).u8(v[1]).u16(clampi(v[2], 0, 65535))
	return _finish(w, NetProtocol.Msg.STALL_INFO)


static func decode_stall_info(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.STALL_INFO)
	if r == null:
		return {}
	var turn: int = r.u32()
	var n: int = r.u8()
	if n > 8:
		return {}
	var entries: Array = []
	for _k in n:
		var pid: int = r.u8()
		var reason: int = r.u8()
		var wait: int = r.u16()
		if pid > 7 or reason > NetProtocol.StallReason.LOADING:
			return {}
		entries.append(PackedInt32Array([pid, reason, wait]))
	return {"turn": turn, "entries": entries} if r.done() else {}


## fields: want_paused:bool.
static func encode_pause_request(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.PAUSE_REQUEST).u8(1 if bool(f.get("want_paused", false)) else 0), NetProtocol.Msg.PAUSE_REQUEST)


static func decode_pause_request(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.PAUSE_REQUEST)
	if r == null:
		return {}
	var v: int = r.u8()
	return {"want_paused": v == 1} if r.done() and v <= 1 else {}


## fields: resume_turn, by_pid.
static func encode_resume(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.RESUME).u32(_i(f, "resume_turn")).u8(_i(f, "by_pid")), NetProtocol.Msg.RESUME)


static func decode_resume(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.RESUME)
	if r == null:
		return {}
	var out: Dictionary = {"resume_turn": r.u32(), "by_pid": r.u8()}
	return out if r.done() else {}


# ---- checksums / desync / match end ------------------------------------------------------------------------

## fields: tick, checksum, input_chain.
static func encode_checksum_report(f: Dictionary) -> PackedByteArray:
	var w: NetWriter = _w(NetProtocol.Msg.CHECKSUM_REPORT)
	return _finish(w.u32(_i(f, "tick")).u32(_i(f, "checksum")).u32(_i(f, "input_chain")), NetProtocol.Msg.CHECKSUM_REPORT)


static func decode_checksum_report(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.CHECKSUM_REPORT)
	if r == null:
		return {}
	var out: Dictionary = {"tick": r.u32(), "checksum": r.u32(), "input_chain": r.u32()}
	return out if r.done() else {}


## fields: tick, kind (DesyncKind), entries:Array[PackedInt64Array [pid, checksum, chain]] (<=8).
static func encode_desync_notice(f: Dictionary) -> PackedByteArray:
	var entries: Array = f.get("entries", []) as Array
	if entries.size() > 8:
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.DESYNC_NOTICE)
	w.u32(_i(f, "tick")).u8(_i(f, "kind")).u8(entries.size())
	for e: Variant in entries:
		var v: PackedInt64Array = e as PackedInt64Array
		if v.size() != 3:
			return PackedByteArray()
		w.u8(v[0]).u32(v[1]).u32(v[2])
	return _finish(w, NetProtocol.Msg.DESYNC_NOTICE)


static func decode_desync_notice(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.DESYNC_NOTICE)
	if r == null:
		return {}
	var tick: int = r.u32()
	var kind: int = r.u8()
	var n: int = r.u8()
	if kind > NetProtocol.DesyncKind.BOTH or n > 8:
		return {}
	var entries: Array = []
	for _k in n:
		var pid: int = r.u8()
		var cs: int = r.u32()
		var ch: int = r.u32()
		if pid > 7:
			return {}
		entries.append(PackedInt64Array([pid, cs, ch]))
	return {"tick": tick, "kind": kind, "entries": entries} if r.done() else {}


static func _encode_parts(type: int, f: Dictionary) -> PackedByteArray:
	var parts: PackedInt64Array = f.get("parts", PackedInt64Array()) as PackedInt64Array
	if parts.size() > 16:
		return PackedByteArray()
	var w: NetWriter = _w(type)
	w.u32(_i(f, "tick")).u8(parts.size())
	for p in parts:
		w.u32(p)
	return _finish(w, type)


static func _decode_parts(bytes: PackedByteArray, type: int) -> Dictionary:
	var r: NetReader = open(bytes, type)
	if r == null:
		return {}
	var tick: int = r.u32()
	var n: int = r.u8()
	if n > 16:
		return {}
	var parts: PackedInt64Array = PackedInt64Array()
	for _k in n:
		parts.append(r.u32())
	return {"tick": tick, "parts": parts} if r.done() else {}


## fields: tick, parts:PackedInt64Array (<=16 u32 values).
static func encode_parts_request(f: Dictionary) -> PackedByteArray:
	return _encode_parts(NetProtocol.Msg.PARTS_REQUEST, f)


static func decode_parts_request(bytes: PackedByteArray) -> Dictionary:
	return _decode_parts(bytes, NetProtocol.Msg.PARTS_REQUEST)


static func encode_parts_report(f: Dictionary) -> PackedByteArray:
	return _encode_parts(NetProtocol.Msg.PARTS_REPORT, f)


static func decode_parts_report(bytes: PackedByteArray) -> Dictionary:
	return _decode_parts(bytes, NetProtocol.Msg.PARTS_REPORT)


## fields: final_tick, final_checksum, reason (MatchEndReason), winner_team (i8, -1 none).
static func encode_match_end(f: Dictionary) -> PackedByteArray:
	var w: NetWriter = _w(NetProtocol.Msg.MATCH_END)
	w.u32(_i(f, "final_tick")).u32(_i(f, "final_checksum")).u8(_i(f, "reason")).i8(_i(f, "winner_team", -1))
	return _finish(w, NetProtocol.Msg.MATCH_END)


static func decode_match_end(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.MATCH_END)
	if r == null:
		return {}
	var out: Dictionary = {"final_tick": r.u32(), "final_checksum": r.u32(), "reason": r.u8(), "winner_team": r.i8()}
	if not r.done() or int(out["reason"]) > NetProtocol.MatchEndReason.DESYNC:
		return {}
	return out


# ---- catch-up (spectators; optional feature, wire layout only) ----------------------------------------------

## fields: from_turn.
static func encode_catchup_request(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.CATCHUP_REQUEST).u32(_i(f, "from_turn")), NetProtocol.Msg.CATCHUP_REQUEST)


static func decode_catchup_request(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.CATCHUP_REQUEST)
	if r == null:
		return {}
	var out: Dictionary = {"from_turn": r.u32()}
	return out if r.done() else {}


## fields: next_live_turn.
static func encode_catchup_done(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.CATCHUP_DONE).u32(_i(f, "next_live_turn")), NetProtocol.Msg.CATCHUP_DONE)


static func decode_catchup_done(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.CATCHUP_DONE)
	if r == null:
		return {}
	var out: Dictionary = {"next_live_turn": r.u32()}
	return out if r.done() else {}


## fields: first_turn, turn_count (u16), raw:PackedByteArray (concatenated replay TURNS records; deflated here).
static func encode_catchup_chunk(f: Dictionary) -> PackedByteArray:
	var raw: PackedByteArray = f.get("raw", PackedByteArray()) as PackedByteArray
	if raw.is_empty() or raw.size() > NetProtocol.MAX_CATCHUP_RAW:
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.CATCHUP_CHUNK)
	w.u32(_i(f, "first_turn")).u16(_i(f, "turn_count")).u32(raw.size())
	w.raw(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	return _finish(w, NetProtocol.Msg.CATCHUP_CHUNK)


## Returns {first_turn, turn_count, raw} (inflated, size verified) or {}.
static func decode_catchup_chunk(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = open(bytes, NetProtocol.Msg.CATCHUP_CHUNK)
	if r == null:
		return {}
	var first_turn: int = r.u32()
	var count: int = r.u16()
	var raw_len: int = r.u32()
	if not r.ok or raw_len < 1 or raw_len > NetProtocol.MAX_CATCHUP_RAW or r.left() < 1:
		return {}
	var packed: PackedByteArray = r.raw(r.left())
	if not NetProtocol.looks_like_zlib(packed):
		return {}
	var raw: PackedByteArray = packed.decompress_dynamic(NetProtocol.MAX_CATCHUP_RAW, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_len:
		return {}
	return {"first_turn": first_turn, "turn_count": count, "raw": raw}
