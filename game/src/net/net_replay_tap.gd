class_name NetReplayTap
extends RefCounted
## Glue between a NetSession and the NetReplayRecorder (docs/spec/net.md 5.8): started at match start on every role, fed
## from the lockstep hooks (turn begin, checksum, ctrl) and the chat, finished at match end / leave. Owns the recording
## temp file and the autosave rotation. Never raises: errors go through the `failed` signal, the memory mirror stays usable.

const PARTS_EVERY_TICKS: int = 200
## A match that ended before this tick without a single command does not replace the last autosave.
const MIN_KEEP_TICKS: int = 200

## NetErrorCode.REPLAY_WRITE + text, once per recording (the file write failed; the memory mirror keeps working).
signal failed(code: int, text: String)
## The autosave was written: its path.
signal saved(path: String)

var recorder: NetReplayRecorder = null
var _opts: NetSessionOptions = null
var _tmp: String = ""
var _saved: String = ""
var _error_sent: bool = false


## Starts a recording for the match `config` (`config_json` = the exact launch JSON). Memory-only when opts.replay_dir is "".
func start(opts: NetSessionOptions, config: Dictionary, config_json: String, peer_id: int, pid: int) -> void:
	_opts = opts
	_saved = ""
	_tmp = ""
	_error_sent = false
	recorder = null
	if not opts.record_replay:
		return
	var unix: int = opts.unix_time_override if opts.unix_time_override >= 0 else int(Time.get_unix_time_from_system())
	var meta: Dictionary = NetReplayRecorder.make_meta(peer_id, pid, unix, opts.game_version)
	recorder = NetReplayRecorder.new()
	recorder.on_error = _recorder_error
	if opts.replay_dir != "":
		_tmp = NetReplay.begin_recording_path(opts.replay_dir)
		if recorder.open_file(_tmp, config, meta, config_json) != OK:
			NetReplay.release_recording_path(_tmp)
			_tmp = ""
	else:
		recorder.open_memory(config, meta, config_json)


func is_active() -> bool:
	return recorder != null and recorder.is_recording()


func turn(turn_no: int, b: NetBundle) -> void:
	if recorder != null:
		recorder.record_turn(b)


func check(tick: int, checksum: int, chain: int, adapter: NetSimAdapter) -> void:
	if recorder == null or tick % NetProtocol.CHECKSUM_PERIOD_TICKS != 0:
		return
	recorder.record_check(tick, checksum, chain)
	if tick % PARTS_EVERY_TICKS == 0 and adapter != null:
		recorder.record_parts(tick, adapter.checksum_parts_at(tick))


## CtrlKind.PLAYER_STATUS record [kind, pid, status, aux] executed at `turn_no`.
func status(turn_no: int, c: PackedInt32Array) -> void:
	if recorder != null and c.size() >= 4:
		recorder.record_event(turn_no, NetProtocol.ReplayEvent.PLAYER_STATUS, PackedInt32Array([c[1], c[2], c[3]]))


func chat(turn_no: int, pid: int, text: String) -> void:
	if recorder != null and _opts != null and _opts.record_chat:
		recorder.record_event(turn_no, NetProtocol.ReplayEvent.CHAT, PackedInt32Array([clampi(pid, 0, 255)]), text)


## END + trailer, then the autosave rotation. `result`: reason, winner_team, final_tick, final_checksum; `chain` = the input
## chain at the final tick. Returns the autosave path ("" when nothing was written to disk).
func finish(result: Dictionary, chain: int) -> String:
	if recorder == null or not recorder.is_recording():
		return _saved
	var ft: int = int(result.get("final_tick", 0))
	recorder.finish({
		"final_tick": ft, "final_checksum": int(result.get("final_checksum", 0)), "final_chain": chain,
		"reason": int(result.get("reason", 0)), "winner_team": int(result.get("winner_team", -1)), "total_turns": (ft + 1) / NetProtocol.TURN_TICKS,
	})
	if _tmp == "":
		return ""
	if recorder.write_failed():
		NetReplay.discard_recording(_tmp)
		_tmp = ""
		return ""
	if recorder.turn_records() == 0 and ft < MIN_KEEP_TICKS:
		NetReplay.discard_recording(_tmp)
		_tmp = ""
		return ""
	_saved = NetReplay.finalize_autosave(_tmp, _opts.replay_autosave_count, _opts.replay_max_bytes)
	_tmp = ""
	if _saved != "":
		saved.emit(_saved)
	return _saved


## The match stopped before the sim decided it (leave, shutdown, desync): END with the state reached so far.
func abandon(adapter: NetSimAdapter, lockstep: NetLockstep, reason: int) -> void:
	if is_active():
		finish({"reason": reason, "winner_team": -1, "final_tick": adapter.current_tick(), "final_checksum": adapter.checksum_now()}, lockstep.input_chain() if lockstep != null else 0)


## The file being written (while recording), else the autosave ("" = memory only).
func path() -> String:
	return _tmp if _tmp != "" else _saved


func saved_path() -> String:
	return _saved


## The replay as bytes (memory mirror: valid mid-match, then without END; with END once finished). Without a recorder: the command-log-lite file for `lite_log` (empty when null).
func bytes(lite_json: String = "", lite_log: SimCommandLog = null) -> PackedByteArray:
	return recorder.to_bytes() if recorder != null else command_log_lite(lite_json, lite_log)


## Used when there is no recording: the old "MFCLOG1" command-log-lite file (config JSON + SimCommandLog ints).
static func command_log_lite(config_json: String, log: SimCommandLog) -> PackedByteArray:
	if log == null:
		return PackedByteArray()
	var w: NetWriter = NetWriter.new()
	w.raw("MFCLOG1\n".to_utf8_buffer())
	w.bytes_(config_json.to_utf8_buffer())
	var ints: PackedInt32Array = log.to_ints()
	w.u32(ints.size())
	for v: int in ints:
		w.u32(v)
	return w.to_bytes()


func _recorder_error(text: String) -> void:
	if _tmp != "":
		NetReplay.discard_recording(_tmp)
	_tmp = ""
	if not _error_sent:
		_error_sent = true
		failed.emit(NetProtocol.NetErrorCode.REPLAY_WRITE, text)
