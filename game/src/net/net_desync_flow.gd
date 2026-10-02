class_name NetDesyncFlow
extends RefCounted
## The message flow around a detected desync (docs/spec/net.md 5.7): the host broadcasts DESYNC_NOTICE + PARTS_REQUEST,
## clients answer with PARTS_REPORT, everybody writes its package (the host after all reports or 2 s) and raises
## desync_detected. NetDesync does the comparison and the files; this class sequences it. Hooks are Callables so it
## never holds the session.

const PARTS_WAIT_US: int = 2_000_000

## (bytes) -> void; to every player peer (host).
var send_to_players: Callable = Callable()
## (bytes) -> void; to the host (client).
var send_host: Callable = Callable()
## () -> void; phase -> DESYNCED and the lockstep stops.
var enter_desynced: Callable = Callable()
## (report: Dictionary) -> void
var emit_report: Callable = Callable()
## (level: int, text: String) -> void
var log_fn: Callable = Callable()
## () -> Dictionary; the package context (see NetDesync.context).
var context: Callable = Callable()
## () -> PackedByteArray; replay bytes for the package.
var replay_bytes: Callable = Callable()
## () -> PackedStringArray
var log_lines: Callable = Callable()

var desync: NetDesync = null
var local_pid: int = -1
var host_pid: int = -1
var match_id: String = ""

var _expected: PackedInt32Array = PackedInt32Array()
var _deadline_us: int = 0
var _finalized: bool = false
var _report: Dictionary = {}


func reset() -> void:
	_expected = PackedInt32Array()
	_deadline_us = 0
	_finalized = false
	_report = {}


func report() -> Dictionary:
	return _report


func is_finalized() -> bool:
	return _finalized


func _log(level: int, text: String) -> void:
	if log_fn.is_valid():
		log_fn.call(level, text)


func host_detected(at_tick: int, kind: int, entries: Array, now_us: int) -> void:
	_log(NetProtocol.LogLevel.ERROR, "DESYNC match=%s tick=%d kind=%s last_good_tick=%d entries=%d platform=%s/%s engine=%s" % [
		match_id.substr(0, 8), at_tick, NetDesync.kind_name(kind).to_upper(), desync.last_good_tick(), entries.size(), OS.get_name(),
		Engine.get_architecture_name(), Engine.get_version_info().get("string", "")])
	if enter_desynced.is_valid():
		enter_desynced.call()
	var wire: Array = []
	_expected = PackedInt32Array()
	for e: Variant in entries:
		var v: PackedInt64Array = e as PackedInt64Array
		if int(v[0]) >= 0 and int(v[0]) < NetProtocol.MAX_PLAYERS:
			wire.append(v)
			if int(v[0]) != local_pid:
				_expected.append(int(v[0]))
	var notice: PackedByteArray = NetCodec.encode_desync_notice({"tick": at_tick, "kind": kind, "entries": wire.slice(0, 8)})
	var parts: PackedInt64Array = PackedInt64Array()
	for v: int in desync.parts_at(at_tick):
		parts.append(v & 0xFFFFFFFF)
	var req: PackedByteArray = NetCodec.encode_parts_request({"tick": at_tick, "parts": parts})
	if send_to_players.is_valid():
		send_to_players.call(notice)
		send_to_players.call(req)
	_deadline_us = now_us + PARTS_WAIT_US
	if _expected.is_empty():
		finalize()


## Client: DESYNC_NOTICE from the host.
func client_notice(at_tick: int, kind: int, entries: Array, now_us: int) -> void:
	if desync.is_detected():
		return
	desync.on_notice(at_tick, kind, entries)
	_log(NetProtocol.LogLevel.ERROR, "DESYNC match=%s tick=%d kind=%s (host notice)" % [match_id.substr(0, 8), at_tick, NetDesync.kind_name(kind).to_upper()])
	if enter_desynced.is_valid():
		enter_desynced.call()
	_deadline_us = now_us + PARTS_WAIT_US


## Client: PARTS_REQUEST (`parts` = the host's sub-checksums of the tick).
func client_parts_request(at_tick: int, parts: PackedInt32Array) -> void:
	if not desync.is_detected():
		return
	desync.on_parts(host_pid if host_pid >= 0 else 0, at_tick, parts)
	var out: PackedInt64Array = PackedInt64Array()
	for v: int in desync.parts_at(at_tick):
		out.append(v & 0xFFFFFFFF)
	if send_host.is_valid():
		send_host.call(NetCodec.encode_parts_report({"tick": at_tick, "parts": out}))
	finalize()


## A locally detected mismatch (client, end of match).
func local(at_tick: int, kind: int) -> void:
	if desync.is_detected():
		return
	desync.on_notice(at_tick, kind, [])
	if enter_desynced.is_valid():
		enter_desynced.call()
	finalize()


func finalize() -> void:
	if _finalized or desync == null:
		return
	_finalized = true
	desync.context = context.call() as Dictionary if context.is_valid() else {}
	var bytes: PackedByteArray = replay_bytes.call() as PackedByteArray if replay_bytes.is_valid() else PackedByteArray()
	var lines: PackedStringArray = log_lines.call() as PackedStringArray if log_lines.is_valid() else PackedStringArray()
	_report = desync.write_package(bytes, lines)
	if emit_report.is_valid():
		emit_report.call(_report)


## Every poll: finalise after the 2 s wait or as soon as every expected PARTS_REPORT arrived (host).
func step(now_us: int, is_host: bool) -> void:
	if _finalized or desync == null or not desync.is_detected():
		return
	if _deadline_us > 0 and now_us >= _deadline_us:
		finalize()
	elif is_host and desync.missing_parts(_expected).is_empty():
		finalize()
