class_name NetReplayData
extends RefCounted
## A loaded `*.mfreplay` (docs/spec/net.md 4.8, 5.8). load_file / from_bytes are tolerant of truncation: parsing stops at
## the first incomplete or structurally invalid record, everything before it is kept and `truncated` is set. A file
## without its END record and valid trailer is `finalized == false`. Unknown record types are skipped by length; a
## second END, or records after the END, are ignored.

## Message of the last failed load_file / from_bytes ("" after a success).
static var last_error: String = ""

var config: Dictionary = {}
## The header's "replay" object (os, arch, engine, game_version, started_unix, recorder_peer, recorder_pid, format).
var replay_meta: Dictionary = {}
var format_version: int = 0
## Turn numbers that carry commands, ascending.
var turns: PackedInt32Array = PackedInt32Array()
## Array[PackedByteArray] parallel to `turns`: group_count + groups (the turn number is implicit).
var bodies: Array = []
## Flattened [tick, checksum, chain, ...] triples, ascending by tick.
var checks: PackedInt64Array = PackedInt64Array()
## Array[{tick: int, parts: PackedInt32Array}].
var parts: Array = []
## Array[{turn: int, kind: int, args: PackedInt32Array, text: String}].
var events: Array = []
## {} unless finalized: final_tick, final_checksum, final_chain, reason, winner_team, total_turns.
var end: Dictionary = {}
var finalized: bool = false
var truncated: bool = false
## File size in bytes.
var byte_size: int = 0
var _error: String = ""


## null when the file cannot be read or its header is invalid (NetReplayData.last_error says why).
static func load_file(path: String) -> NetReplayData:
	if not FileAccess.file_exists(path):
		last_error = "file not found: %s" % path
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		last_error = "cannot read %s" % path
		return null
	return from_bytes(bytes)


## Parses a complete or truncated replay. null (last_error set) when the 16-byte header, its JSON or the config is bad.
static func from_bytes(bytes: PackedByteArray) -> NetReplayData:
	var d: NetReplayData = NetReplayData.new()
	d.byte_size = bytes.size()
	var pos: int = d._parse_header(bytes)
	if pos < 0:
		last_error = d._error
		return null
	last_error = ""
	d._parse_records(bytes, pos)
	return d


## Parses only the header (16-byte file header + JSON): config and replay_meta, no records. null on failure.
static func from_header(bytes: PackedByteArray) -> NetReplayData:
	var d: NetReplayData = NetReplayData.new()
	d.byte_size = bytes.size()
	if d._parse_header(bytes) < 0:
		last_error = d._error
		return null
	last_error = ""
	return d


func header_error() -> String:
	return _error


## Number of turns the match executed (END record when finalized, else the last turn with commands + 1).
func total_turns() -> int:
	if finalized:
		return int(end.get("total_turns", 0))
	return turns[turns.size() - 1] + 1 if not turns.is_empty() else 0


## The tick a player runs to: the final tick when finalized, else the last CHECK tick or the end of the last command turn.
func end_tick() -> int:
	if finalized:
		return int(end.get("final_tick", 0))
	var t: int = int(checks[checks.size() - 3]) if checks.size() >= 3 else 0
	if not turns.is_empty():
		t = maxi(t, (turns[turns.size() - 1] + 1) * NetProtocol.TURN_TICKS)
	return t


func check_count() -> int:
	return checks.size() / 3


func command_count() -> int:
	var n: int = 0
	for i: int in bodies.size():
		var r: NetReader = NetReader.new(bodies[i] as PackedByteArray)
		var gc: int = r.u8()
		for _g: int in gc:
			r.u8()
			n += NetCodec.decode_commands(r, NetProtocol.MAX_CMDS_PER_TURN).size()
	return n


## Decoded groups of the i-th TURNS record: Array of [pid: int, cmds: Array[PackedInt32Array]] ascending by pid.
func groups_at(i: int) -> Array:
	var out: Array = []
	if i < 0 or i >= bodies.size():
		return out
	var r: NetReader = NetReader.new(bodies[i] as PackedByteArray)
	var gc: int = r.u8()
	for _g: int in gc:
		var pid: int = r.u8()
		out.append([pid, NetCodec.decode_commands(r, NetProtocol.MAX_CMDS_PER_TURN)])
	return out


## Sub-checksum record for exactly `tick` ({} when none).
func parts_at(tick: int) -> Dictionary:
	for p: Variant in parts:
		if int((p as Dictionary)["tick"]) == tick:
			return p as Dictionary
	return {}


## config.versions (sim, proto, data_hash, data_format, data_ids, game).
func versions() -> Dictionary:
	return config.get("versions", {}) as Dictionary


func match_id() -> String:
	return str(config.get("match_id", ""))


# ---- parsing ---------------------------------------------------------------------------------------------------------

## Returns the offset of the first record, or -1 (and sets _error).
func _parse_header(bytes: PackedByteArray) -> int:
	if bytes.size() < NetReplayRecorder.HEADER_SIZE:
		_error = "file too short for a replay header"
		return -1
	if bytes.slice(0, 4).get_string_from_ascii() != NetReplayRecorder.MAGIC:
		_error = "not a replay file (bad magic)"
		return -1
	var r: NetReader = NetReader.new(bytes, 4, NetReplayRecorder.HEADER_SIZE)
	format_version = r.u16()
	r.u16()
	var json_len: int = r.u32()
	var json_fnv: int = r.u32()
	if format_version != NetReplayRecorder.FORMAT_VERSION:
		_error = "unsupported replay format version %d" % format_version
		return -1
	var start: int = NetReplayRecorder.HEADER_SIZE
	if json_len < 2 or json_len > NetReplayRecorder.MAX_HEADER_JSON or start + json_len > bytes.size():
		_error = "bad replay header length"
		return -1
	if NetProtocol.fnv1a32(bytes, 0x811C9DC5, start, start + json_len) != json_fnv:
		_error = "replay header checksum mismatch"
		return -1
	if not NetProtocol.is_valid_utf8(bytes, start, json_len):
		_error = "replay header is not valid UTF-8"
		return -1
	var j: JSON = JSON.new()
	if j.parse(bytes.slice(start, start + json_len).get_string_from_utf8()) != OK or not (j.data is Dictionary):
		_error = "replay header JSON is malformed"
		return -1
	var top: Dictionary = j.data as Dictionary
	config = NetMatchConfig.normalize(top.get("config", null))
	if config.is_empty():
		_error = "replay header carries an invalid match config"
		return -1
	var meta: Variant = top.get("replay", {})
	replay_meta = {}
	if meta is Dictionary:
		for k: Variant in (meta as Dictionary):
			var v: Variant = (meta as Dictionary)[k]
			if typeof(v) == TYPE_FLOAT and is_equal_approx(float(v), roundf(float(v))):
				v = int(v)
			replay_meta[str(k)] = v
	return start + json_len


func _parse_records(bytes: PackedByteArray, start: int) -> void:
	var pos: int = start
	var size: int = bytes.size()
	var last_turn: int = -1
	var last_check: int = -1
	var saw_end: bool = false
	while pos < size:
		var r: NetReader = NetReader.new(bytes, pos)
		var type: int = r.u8()
		var plen: int = r.varint()
		if not r.ok or plen > NetReplayRecorder.MAX_RECORD or r.pos() + plen > size:
			truncated = true
			return
		var p0: int = r.pos()
		var p1: int = p0 + plen
		pos = p1
		if saw_end:
			continue
		var pr: NetReader = NetReader.new(bytes, p0, p1)
		match type:
			NetProtocol.ReplayRec.TURNS:
				var gap: int = pr.varint()
				var body_start: int = pr.pos()
				if not pr.ok or not _valid_body(bytes, body_start, p1):
					truncated = true
					return
				var turn: int = last_turn + 1 + gap
				if turn > 0x7FFFFFFF:
					truncated = true
					return
				last_turn = turn
				turns.append(turn)
				bodies.append(bytes.slice(body_start, p1))
			NetProtocol.ReplayRec.CHECK:
				var tick: int = pr.u32()
				var cs: int = pr.u32()
				var chain: int = pr.u32()
				if not pr.ok:
					truncated = true
					return
				if tick > last_check:
					last_check = tick
					checks.append(tick)
					checks.append(cs)
					checks.append(chain)
			NetProtocol.ReplayRec.PARTS:
				var ptick: int = pr.u32()
				var n: int = pr.u8()
				var arr: PackedInt32Array = PackedInt32Array()
				for _i: int in n:
					arr.append(pr.u32())
				if not pr.ok:
					truncated = true
					return
				parts.append({"tick": ptick, "parts": arr})
			NetProtocol.ReplayRec.EVENT:
				var ev: Dictionary = _parse_event(pr)
				if not pr.ok:
					truncated = true
					return
				if not ev.is_empty():
					events.append(ev)
			NetProtocol.ReplayRec.END:
				if plen < NetReplayRecorder.END_PAYLOAD:
					truncated = true
					return
				var e: Dictionary = {
					"final_tick": pr.u32(), "final_checksum": pr.u32(), "final_chain": pr.u32(), "reason": pr.u8(),
					"winner_team": pr.i8(), "total_turns": pr.u32(),
				}
				saw_end = true
				if size - pos == 8 and bytes.decode_u32(pos) == NetReplayRecorder.END_RECORD_SIZE \
						and bytes.slice(pos + 4, pos + 8).get_string_from_ascii() == NetReplayRecorder.END_MAGIC:
					finalized = true
					end = e
					pos = size
				else:
					truncated = true
					return
			_:
				pass
	if not saw_end:
		truncated = true


static func _valid_body(bytes: PackedByteArray, from: int, to: int) -> bool:
	var r: NetReader = NetReader.new(bytes, from, to)
	var gc: int = r.u8()
	if not r.ok or gc > NetProtocol.MAX_PLAYERS:
		return false
	var prev: int = -1
	for _g: int in gc:
		var pid: int = r.u8()
		if not r.ok or pid <= prev or pid > 7:
			return false
		prev = pid
		var cmds: Array = NetCodec.decode_commands(r, NetProtocol.MAX_CMDS_PER_TURN)
		if not r.ok or cmds.is_empty():
			return false
	return r.done()


func _parse_event(pr: NetReader) -> Dictionary:
	var turn: int = pr.u32()
	var kind: int = pr.u8()
	if not pr.ok:
		return {}
	match kind:
		NetProtocol.ReplayEvent.PLAYER_STATUS:
			var a: PackedInt32Array = PackedInt32Array([pr.u8(), pr.u8(), pr.u8()])
			return {"turn": turn, "kind": kind, "args": a, "text": ""} if pr.ok else {}
		NetProtocol.ReplayEvent.CHAT:
			var pid: int = pr.u8()
			var tb: PackedByteArray = pr.raw(pr.left())
			if not pr.ok:
				return {}
			return {"turn": turn, "kind": kind, "args": PackedInt32Array([pid]), "text": tb.get_string_from_utf8() if NetProtocol.is_valid_utf8(tb, 0, tb.size()) else ""}
	return {}
