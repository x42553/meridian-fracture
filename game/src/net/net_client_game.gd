class_name NetClientGame
extends RefCounted
## Client side of a running match (docs/spec/net.md 5.5.7, 5.5.11): TURN_BUNDLE intake (with the pre-START buffer), PING ->
## PONG with the lockstep's report, the "Waiting for ..." overlay from STALL_INFO (or from the host's silence), and the
## end-of-match cross check (MATCH_END final tick / checksum against the local ones). Hooks are Callables; nothing here
## holds the session.

const PRESTART_MAX: int = 64
const HOST_SILENCE_US: int = 1_500_000

var lockstep: NetLockstep = null
var config: Dictionary = {}
## (bytes) -> void; to the host
var send_host: Callable = Callable()
## (waiting: Array) -> void; [{pid, name, reason, wait_ms}], empty = resumed
var emit_stall: Callable = Callable()
## (code: int, text: String) -> void
var emit_error: Callable = Callable()
## (tick: int) -> void; the host's final state differs from ours
var on_final_mismatch: Callable = Callable()
## (level: int, text: String) -> void
var log_fn: Callable = Callable()

var stall_entries: Array = []
var _prestart: Array[NetBundle] = []
var _host_wait: bool = false
var _last_info_us: int = 0
var _stalled: bool = false
var _pending_final: Dictionary = {}
var _final_local: Dictionary = {}


func reset() -> void:
	_prestart = []
	stall_entries = []
	_host_wait = false
	_stalled = false
	_pending_final = {}
	_final_local = {}
	lockstep = null


func _log(level: int, text: String) -> void:
	if log_fn.is_valid():
		log_fn.call(level, text)


func pid_name(pid: int) -> String:
	for pv: Variant in config.get("players", []) as Array:
		if int((pv as Dictionary)["pid"]) == pid:
			return str((pv as Dictionary)["name"])
	return "Player %d" % (pid + 1)


## TURN_BUNDLE. `buffer_only` (phase WAIT_START): keep it for after START.
func handle_bundle(data: PackedByteArray, buffer_only: bool) -> void:
	var b: NetBundle = NetCodec.decode_bundle(data)
	if b == null:
		_log(NetProtocol.LogLevel.ERROR, "corrupt TURN_BUNDLE from the host")
		if emit_error.is_valid():
			emit_error.call(NetProtocol.NetErrorCode.HOST_PROTOCOL, "corrupt bundle from the host")
		return
	if buffer_only or lockstep == null:
		if _prestart.size() < PRESTART_MAX:
			_prestart.append(b)
		return
	if lockstep.push_bundle(b) == NetProtocol.BundleResult.TOO_FAR:
		_log(NetProtocol.LogLevel.WARN, "bundle %d too far ahead" % b.turn)


## Feeds the bundles that arrived before START into the lockstep.
func drain_prestart() -> void:
	var pre: Array[NetBundle] = _prestart
	_prestart = []
	for b: NetBundle in pre:
		lockstep.push_bundle(b)


func handle_ping(data: PackedByteArray) -> void:
	var d: Dictionary = NetCodec.decode_ping(data)
	if d.is_empty() or lockstep == null:
		return
	var rep: Dictionary = lockstep.take_report()
	send_host.call(NetCodec.encode_pong({
		"seq": int(d["seq"]), "echo_ms": int(d["host_ms"]), "exec_turn": int(rep["exec_turn"]), "slack_min_ms": int(rep["slack_min_ms"]),
		"stall_ms": int(rep["stall_ms"]), "episodes": int(rep["episodes"]), "load_pct": int(rep["load_pct"]), "hitch": bool(rep["hitch"]),
	}))


func handle_stall_info(data: PackedByteArray, now_us: int) -> void:
	var d: Dictionary = NetCodec.decode_stall_info(data)
	if d.is_empty():
		return
	_last_info_us = now_us
	_host_wait = false
	stall_entries = []
	for e: Variant in d["entries"] as Array:
		var v: PackedInt32Array = e as PackedInt32Array
		stall_entries.append({"pid": v[0], "name": pid_name(v[0]), "reason": v[1], "wait_ms": v[2]})
	emit_stall.call(stall_entries.duplicate(true))


## NetLockstep.on_stall_changed
func on_lockstep_stall(stalled: bool, _ms: int) -> void:
	_stalled = stalled
	if not stalled and (not stall_entries.is_empty() or _host_wait):
		stall_entries = []
		_host_wait = false
		emit_stall.call([])


## No STALL_INFO for 1.5 s while stalled: the host itself is the slow party ("Waiting for the host...").
func step(now_us: int) -> void:
	if _stalled and not _host_wait and stall_entries.is_empty() and now_us - _last_info_us > HOST_SILENCE_US:
		_host_wait = true
		emit_stall.call([{"pid": -1, "name": "host", "reason": NetProtocol.StallReason.NETWORK, "wait_ms": int(HOST_SILENCE_US / 1000)}])


func handle_match_end(data: PackedByteArray) -> void:
	var d: Dictionary = NetCodec.decode_match_end(data)
	if d.is_empty():
		return
	_pending_final = d
	compare_final()


## The local match ended at (tick, checksum).
func note_local_final(tick: int, checksum: int) -> void:
	if _final_local.is_empty() or int(_final_local["tick"]) != tick:
		_final_local = {"tick": tick, "checksum": checksum}
	compare_final()


func compare_final() -> void:
	if _pending_final.is_empty() or _final_local.is_empty():
		return
	var remote: Dictionary = _pending_final
	_pending_final = {}
	if int(remote["final_tick"]) != int(_final_local["tick"]) or (int(remote["final_checksum"]) & 0xFFFFFFFF) != (int(_final_local["checksum"]) & 0xFFFFFFFF):
		_log(NetProtocol.LogLevel.ERROR, "DESYNC at match end: host tick %d sum %08X, local tick %d sum %08X" % [
			int(remote["final_tick"]), int(remote["final_checksum"]), int(_final_local["tick"]), int(_final_local["checksum"])])
		if on_final_mismatch.is_valid():
			on_final_mismatch.call(int(remote["final_tick"]))
