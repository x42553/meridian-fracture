class_name NetReplayRecorder
extends RefCounted
## Writes a `*.mfreplay` (docs/spec/net.md 4.8, 5.8): header (MatchConfig JSON + replay meta) followed by TURNS / CHECK /
## PARTS / EVENT / END records. Every record is mirrored in memory (to_bytes() is valid at any moment, also for a desync
## package) and, in file mode, appended to the file; the file is flushed after every CHECK so a crash loses at most about
## one second of data. Recording never blocks or raises: a failed write disables the file (the memory mirror keeps
## working) and calls `on_error` once.

const FORMAT_VERSION: int = 1
const HEADER_SIZE: int = 16
const MAX_HEADER_JSON: int = 1 << 20
const MAX_RECORD: int = 1 << 20
const END_PAYLOAD: int = 18
## u8 type + varint len (1 byte for 18) + 18 payload bytes.
const END_RECORD_SIZE: int = 20
const MAGIC: String = "MFRP"
const END_MAGIC: String = "MFRE"

## (text: String) -> void, called once when a file write fails.
var on_error: Callable = Callable()

var _buf: PackedByteArray = PackedByteArray()
var _file: FileAccess = null
var _path: String = ""
var _started: bool = false
var _finished: bool = false
var _write_failed: bool = false
var _last_turn: int = -1
var _last_check_tick: int = -1
var _last_parts_tick: int = -1
var _turn_records: int = 0
var _commands: int = 0


## The replay-header "replay" object for this machine: format, recorder_peer, recorder_pid, started_unix, os, arch, engine,
## game_version.
static func make_meta(recorder_peer: int, recorder_pid: int, started_unix: int, game_version: String) -> Dictionary:
	var v: Dictionary = Engine.get_version_info()
	return {
		"format": FORMAT_VERSION, "recorder_peer": recorder_peer, "recorder_pid": recorder_pid, "started_unix": started_unix,
		"os": OS.get_name(), "arch": Engine.get_architecture_name(),
		"engine": "%d.%d.%d-%s" % [int(v.get("major", 0)), int(v.get("minor", 0)), int(v.get("patch", 0)), str(v.get("status", ""))],
		"game_version": game_version,
	}


## Header bytes: 16-byte FileHeader + HeaderJson. `config_json` (the exact launch JSON) is embedded verbatim when
## non-empty, otherwise the canonical JSON of `config` is used.
static func build_header(config: Dictionary, config_json: String, meta: Dictionary) -> PackedByteArray:
	var cj: String = config_json if config_json != "" else NetMatchConfig.canonical_json(config)
	var json: PackedByteArray = ('{"config":%s,"replay":%s}' % [cj, JSON.stringify(meta, "", true)]).to_utf8_buffer()
	var w: NetWriter = NetWriter.new()
	w.raw(MAGIC.to_utf8_buffer()).u16(FORMAT_VERSION).u16(0).u32(json.size()).u32(NetProtocol.fnv1a32(json)).raw(json)
	return w.to_bytes()


## Starts a file recording (truncates `path`). Returns the Error; on failure nothing is recorded to disk but the
## recorder still works in memory.
func open_file(path: String, config: Dictionary, meta: Dictionary, config_json: String = "") -> int:
	_begin(config, meta, config_json)
	_path = path
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		var err: int = FileAccess.get_open_error()
		_fail("cannot create %s (error %d)" % [path, err])
		return err
	_file.store_buffer(_buf)
	return OK


## Memory-only recording (tests, desync packages, sessions without a replay directory).
func open_memory(config: Dictionary, meta: Dictionary, config_json: String = "") -> void:
	_begin(config, meta, config_json)


func _begin(config: Dictionary, meta: Dictionary, config_json: String) -> void:
	_buf = build_header(config, config_json, meta)
	_started = true
	_finished = false
	_write_failed = false
	_last_turn = -1
	_last_check_tick = -1
	_last_parts_tick = -1
	_turn_records = 0
	_commands = 0


func is_recording() -> bool:
	return _started and not _finished


func is_finished() -> bool:
	return _finished


## true when the file target failed (the memory mirror is still intact).
func write_failed() -> bool:
	return _write_failed


func path() -> String:
	return _path


func turn_records() -> int:
	return _turn_records


func command_count() -> int:
	return _commands


## Last turn number seen in a TURNS record (-1 = none).
func last_turn() -> int:
	return _last_turn


## Writes a TURNS record only when the bundle has commands; empty turns are accounted for by the next record's gap.
## Turns must arrive in ascending order (anything <= the last recorded turn is ignored).
func record_turn(bundle: NetBundle) -> void:
	if not is_recording() or bundle == null or bundle.pids.is_empty() or int(bundle.turn) <= _last_turn:
		return
	var core: PackedByteArray = bundle.core_bytes()
	if core.size() < 5:
		return
	var w: NetWriter = NetWriter.new()
	w.varint(int(bundle.turn) - _last_turn - 1)
	w.raw(core.slice(4))
	_last_turn = int(bundle.turn)
	_turn_records += 1
	_commands += bundle.command_count()
	_record(NetProtocol.ReplayRec.TURNS, w.to_bytes())


## CHECK every 20 ticks. Ticks that are not a multiple of 20 (the final one) and repeated ticks are ignored: the END
## record carries the final values.
func record_check(tick: int, checksum: int, chain: int) -> void:
	if not is_recording() or tick <= _last_check_tick or tick % NetProtocol.CHECKSUM_PERIOD_TICKS != 0:
		return
	_last_check_tick = tick
	var w: NetWriter = NetWriter.new()
	w.u32(tick).u32(checksum).u32(chain)
	_record(NetProtocol.ReplayRec.CHECK, w.to_bytes())
	flush()


## Sub-checksums (every 200 ticks). Empty arrays and repeats are ignored.
func record_parts(tick: int, parts: PackedInt32Array) -> void:
	if not is_recording() or parts.is_empty() or parts.size() > 255 or tick <= _last_parts_tick:
		return
	_last_parts_tick = tick
	var w: NetWriter = NetWriter.new()
	w.u32(tick).u8(parts.size())
	for p: int in parts:
		w.u32(p)
	_record(NetProtocol.ReplayRec.PARTS, w.to_bytes())


## PLAYER_STATUS (args = pid, status, aux) or CHAT (args = pid, text).
func record_event(turn: int, kind: int, args: PackedInt32Array, text: String = "") -> void:
	if not is_recording():
		return
	var w: NetWriter = NetWriter.new()
	w.u32(turn).u8(kind)
	match kind:
		NetProtocol.ReplayEvent.PLAYER_STATUS:
			if args.size() < 3:
				return
			w.u8(args[0]).u8(args[1]).u8(args[2])
		NetProtocol.ReplayEvent.CHAT:
			if args.is_empty():
				return
			var t: String = text
			while t.length() > 0 and t.to_utf8_buffer().size() > 200:
				t = t.left(t.length() - 1)
			w.u8(args[0]).raw(t.to_utf8_buffer())
		_:
			return
	_record(NetProtocol.ReplayRec.EVENT, w.to_bytes())


## FileAccess.flush() (also called after each CHECK).
func flush() -> void:
	if _file != null:
		_file.flush()


## END record + trailer; closes the file. `result`: final_tick, final_checksum, final_chain, reason, winner_team,
## total_turns (optional, default last_turn + 1).
func finish(result: Dictionary) -> void:
	if not is_recording():
		return
	var w: NetWriter = NetWriter.new()
	w.u32(int(result.get("final_tick", 0))).u32(int(result.get("final_checksum", 0))).u32(int(result.get("final_chain", 0)))
	w.u8(int(result.get("reason", 0))).i8(int(result.get("winner_team", -1)))
	w.u32(int(result.get("total_turns", _last_turn + 1)))
	_record(NetProtocol.ReplayRec.END, w.to_bytes())
	var tail: NetWriter = NetWriter.new()
	tail.u32(END_RECORD_SIZE).raw(END_MAGIC.to_utf8_buffer())
	_append(tail.to_bytes())
	_finished = true
	_close_file()


## Stops recording without END (the file stays truncated-but-playable); closes the file.
func abort() -> void:
	_finished = true
	_close_file()


## Everything recorded so far (memory mirror; header included; END + trailer once finished).
func to_bytes() -> PackedByteArray:
	return _buf.duplicate()


func byte_size() -> int:
	return _buf.size()


func _record(type: int, payload: PackedByteArray) -> void:
	var w: NetWriter = NetWriter.new()
	w.u8(type).varint(payload.size()).raw(payload)
	_append(w.to_bytes())


func _append(b: PackedByteArray) -> void:
	_buf.append_array(b)
	if _file != null and not _write_failed:
		_file.store_buffer(b)
		var err: int = _file.get_error()
		if err != OK:
			_fail("write error %d on %s" % [err, _path])


func _fail(text: String) -> void:
	if _write_failed:
		return
	_write_failed = true
	_close_file()
	if on_error.is_valid():
		on_error.call(text)


func _close_file() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null
