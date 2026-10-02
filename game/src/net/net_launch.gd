class_name NetLaunch
extends RefCounted
## The launch handshake of docs/spec/net.md 5.4 (config broadcast -> load map -> ack -> start tick 0), host, client and
## LOCAL halves in one class, so single-player uses exactly the multiplayer pipeline (5.9). The session owns it and wires
## the hooks below; nothing here knows the session.
##
## Host: countdown (1 Hz LAUNCH_COUNTDOWN) -> config (from_lobby -> canonical JSON -> parse -> normalize -> validate) ->
## LAUNCH_CONFIG to every human -> own world job (sliced) + LOAD_STATUS at 4 Hz -> every LOAD_DONE compared with the
## host reference (map_hash: MAP_MISMATCH, checksum0: INIT_MISMATCH) -> `on_start` hook (session builds turn host,
## lockstep ...) -> START. Failures abort back to the lobby with LAUNCH_ABORT.
## Client: LAUNCH_CONFIG (bounded inflate, hash, normalize, validate) -> world job -> LOAD_DONE -> START (config hash
## verified). LOCAL: the same, with a self-compare and a local START call.

enum Step { IDLE = 0, COUNTDOWN = 1, LOADING = 2, WAIT_START = 3 }

const STATUS_PERIOD_US: int = 250_000
const PROGRESS_PERIOD_US: int = 250_000

# ---- wiring ------------------------------------------------------------------------------------------------
var opts: NetSessionOptions = null
var clock: NetClock = null
var lobby: NetLobby = null
## host peer records (peer_id -> NetPeerInfo); empty for LOCAL and clients.
var peers: Dictionary = {}
var is_host: bool = false
var is_local: bool = false
## (peer_id: int, data: PackedByteArray) -> void
var send: Callable = Callable()
## (session_phase: int) -> void
var set_phase: Callable = Callable()
## (reason: int, pid: int, detail: String) -> void; the launch was aborted and everybody is back in the lobby.
var on_aborted: Callable = Callable()
## (pids: PackedInt32Array, percents: PackedInt32Array) -> void
var on_progress: Callable = Callable()
## (limit, min_ms, max_ms) -> void ENet timeouts for the new phase (loading vs lobby vs game values).
var on_timeouts: Callable = Callable()
## (adapter: NetSimAdapter, cfg: Dictionary, cfg_json: String, cfg_hash: int, d0: int, speed_pct: int, local_pid: int) -> void
var on_start: Callable = Callable()
## (peer_id: int, reason: int, detail: String) -> void; removes a peer (used for spectators at launch)
var on_kick: Callable = Callable()
## (level: int, text: String) -> void
var log_fn: Callable = Callable()

var _step: int = Step.IDLE
var _cd_left: int = 0
var _cd_next_us: int = 0
var _cfg: Dictionary = {}
var _json: String = ""
var _hash: int = 0
var _d0: int = 2
var _speed: int = 100
var _job: NetWorldJob = null
var _adapter: NetSimAdapter = null
var _own_done: bool = false
var _ref_map: int = 0
var _ref_c0: int = 0
var _local_pid: int = -1
var _last_status_us: int = 0
var _last_progress_us: int = 0
var _last_pct: int = -1
var _started_us: int = 0
var _reports: Dictionary = {}
var _load_error_sent: bool = false


func _log(level: int, text: String) -> void:
	if log_fn.is_valid():
		log_fn.call(level, text)


func active_step() -> int:
	return _step


func is_launching() -> bool:
	return _step != Step.IDLE


## {config, config_json, config_hash, map_hash, checksum0} (the host truth every peer is compared with).
func launch_reference() -> Dictionary:
	return {"config": _cfg.duplicate(true), "config_json": _json, "config_hash": _hash, "map_hash": _ref_map, "checksum0": _ref_c0}


## Hands over the built adapter once the local job finished (null before).
func take_adapter() -> NetSimAdapter:
	var a: NetSimAdapter = _adapter
	_adapter = null
	return a


func d0() -> int:
	return _d0


## Discards any launch in progress silently (shutdown / returning to the lobby).
func reset() -> void:
	_step = Step.IDLE
	_job = null
	_adapter = null
	_cfg = {}
	_json = ""
	_reports.clear()
	_own_done = false
	_load_error_sent = false
	_last_pct = -1


# =====================================================================================================================
# host: countdown
# =====================================================================================================================

func begin_countdown(seconds: int) -> void:
	if seconds <= 0:
		_start_launch()
		return
	_step = Step.COUNTDOWN
	_cd_left = seconds
	_cd_next_us = clock.now_us() + 1_000_000
	_announce_countdown(seconds)


func _announce_countdown(n: int) -> void:
	_broadcast_lobby(NetLobbyCodec.encode_launch_countdown({"seconds_left": n}))
	if lobby != null:
		lobby.note_countdown(n)
	if n > 0 and set_phase.is_valid():
		set_phase.call(NetSession.Phase.COUNTDOWN)


## Aborts a running countdown (unready / leave / host cancel): LAUNCH_COUNTDOWN(0), back to the lobby.
func cancel_countdown() -> void:
	if _step != Step.COUNTDOWN:
		return
	_step = Step.IDLE
	_announce_countdown(0)
	if set_phase.is_valid():
		set_phase.call(NetSession.Phase.LOBBY)


func _broadcast_lobby(data: PackedByteArray) -> void:
	for k: Variant in peers:
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.LOBBY and send.is_valid():
			send.call(p.peer_id, data)


func _broadcast_loading(data: PackedByteArray) -> void:
	for k: Variant in peers:
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if (p.stage == NetPeerInfo.Stage.LOADING or p.stage == NetPeerInfo.Stage.LOADED) and send.is_valid():
			send.call(p.peer_id, data)


# =====================================================================================================================
# host / local: build the config and start loading
# =====================================================================================================================

func _compute_d0() -> int:
	var d: int
	if opts.fixed_input_delay_turns > 0:
		d = opts.fixed_input_delay_turns
	elif is_local:
		d = NetProtocol.D_MIN_LOCAL
	else:
		d = opts.min_input_delay_turns
	return clampi(d, 1, NetProtocol.D_MAX)


func _random_u32() -> int:
	var b: PackedByteArray = Crypto.new().generate_random_bytes(4)
	return b.decode_u32(0)


## Builds the MatchConfig from the lobby state, round-trips it through canonical JSON + normalize + validate exactly as a
## remote peer would and stores it. Returns "" or the error text.
func prepare_config() -> String:
	var st: NetLobbyState = lobby.state
	var seed32: int = opts.match_seed_override & 0xFFFFFFFF if opts.match_seed_override >= 0 else _random_u32()
	var mid: String = Crypto.new().generate_random_bytes(8).hex_encode()
	var hs: Dictionary = {}
	if opts.data_handshake.is_valid():
		hs = opts.data_handshake.call(false) as Dictionary
	var tables: Dictionary = hs.get("tables", {}) as Dictionary
	var versions: Dictionary = {
		"game": opts.game_version, "proto": NetProtocol.PROTO_VERSION, "sim": opts.sim_version, "data_hash": opts.data_hash,
		"data_format": int(hs.get("format", 0)), "data_ids": int(tables.get("ids", 0)), "match_id": mid,
	}
	var now_unix: int = opts.unix_time_override if opts.unix_time_override >= 0 else int(Time.get_unix_time_from_system())
	var raw: Dictionary = NetMatchConfig.from_lobby(st, seed32, versions, now_unix, opts.roster_ids)
	_d0 = _compute_d0()
	(raw["net"] as Dictionary)["input_delay"] = _d0
	var json: String = NetMatchConfig.canonical_json(raw)
	var cfg: Dictionary = NetMatchConfig.parse(json)
	var err: String = NetMatchConfig.validate(cfg, opts)
	if err != "":
		return err
	# the transmitted bytes are the canonical JSON of the NORMALISED config (identical on every peer)
	_json = NetMatchConfig.canonical_json(cfg)
	_cfg = cfg
	_hash = NetMatchConfig.config_hash(_json.to_utf8_buffer())
	_speed = int((cfg["net"] as Dictionary)["speed_pct"])
	_local_pid = NetMatchConfig.pid_of_peer(cfg, lobby.local_peer_id)
	return ""


func _start_launch() -> void:
	_started_us = clock.now_us()
	_step = Step.LOADING
	for k: Variant in peers.keys():
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.is_spectator and on_kick.is_valid():
			on_kick.call(p.peer_id, NetProtocol.KickReason.KICKED_BY_HOST, "spectators cannot join a running match")
	var err: String = prepare_config()
	if err != "":
		abort(NetProtocol.AbortReason.CONFIG_INVALID, 255, err)
		return
	if is_host:
		lobby.set_phase(NetProtocol.LobbyPhase.LOADING)
	var pkt: PackedByteArray = NetLobbyCodec.deflate_config(_json)
	if pkt.is_empty():
		abort(NetProtocol.AbortReason.CONFIG_INVALID, 255, "configuration too large")
		return
	for k: Variant in peers:
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.LOBBY and p.slot >= 0:
			p.stage = NetPeerInfo.Stage.LOADING
			p.loaded = false
			p.load_reported = false
			p.load_pct = 0
			p.last_load_msg_us = _started_us
			if send.is_valid():
				send.call(p.peer_id, pkt)
	if set_phase.is_valid():
		set_phase.call(NetSession.Phase.LOADING)
	if on_timeouts.is_valid():
		on_timeouts.call(NetProtocol.TIMEOUTS_LOADING)
	_begin_job()


func _begin_job() -> void:
	_own_done = false
	_adapter = null
	_last_pct = -1
	var built: Variant = opts.world_builder.call(_cfg.duplicate(true)) if opts.world_builder.is_valid() else null
	if not (built is NetWorldJob):
		_fail_local("world builder returned no job")
		return
	_job = built as NetWorldJob


## LOCAL entry: config, then loading. Returns "" or the error (the session then fails to create).
func begin_local() -> String:
	_started_us = clock.now_us()
	var err: String = prepare_config()
	if err != "":
		return err
	_step = Step.LOADING
	if set_phase.is_valid():
		set_phase.call(NetSession.Phase.LOADING)
	_begin_job()
	return ""


## LOCAL entry from a finished config (already normalised + validated by the caller). Returns "" or an error.
func begin_local_config(cfg: Dictionary) -> String:
	_started_us = clock.now_us()
	_cfg = cfg
	_json = NetMatchConfig.canonical_json(cfg)
	_hash = NetMatchConfig.config_hash(_json.to_utf8_buffer())
	_d0 = _compute_d0()
	_speed = int((cfg["net"] as Dictionary)["speed_pct"])
	_local_pid = NetMatchConfig.pid_of_peer(cfg, 1)
	_step = Step.LOADING
	if set_phase.is_valid():
		set_phase.call(NetSession.Phase.LOADING)
	_begin_job()
	return ""


func _fail_local(detail: String) -> void:
	if is_host or is_local:
		abort(NetProtocol.AbortReason.LOAD_FAILED, _local_pid if _local_pid >= 0 else 255, detail)
	else:
		_load_error_sent = true
		_send_to_host(NetLobbyCodec.encode_load_failed({"reason": NetProtocol.AbortReason.LOAD_FAILED, "detail": detail}))


# =====================================================================================================================
# per-poll step
# =====================================================================================================================

func step(now_us: int, budget_us: int) -> void:
	match _step:
		Step.COUNTDOWN:
			if is_host and now_us >= _cd_next_us:
				_cd_left -= 1
				_cd_next_us += 1_000_000
				if _cd_left <= 0:
					_start_launch()
				else:
					_announce_countdown(_cd_left)
		Step.LOADING:
			_step_loading(now_us, budget_us)


func _step_loading(now_us: int, budget_us: int) -> void:
	if _job != null and not _own_done and not _load_error_sent:
		if _job.step(budget_us):
			if _job.error() != "":
				var why: String = _job.error()
				_job = null
				_fail_local(why)
				return
			_adapter = _job.take_adapter()
			_job = null
			_own_done = true
			_own_loaded(now_us)
			return
		_maybe_progress(now_us, _job.progress_pct())
	if is_host and _step == Step.LOADING:
		_host_status(now_us)
		_host_timeouts(now_us)


func _own_loaded(now_us: int) -> void:
	if _adapter == null:
		_fail_local("world builder produced no world")
		return
	_maybe_progress(now_us, 100, true)
	if is_host or is_local:
		_ref_map = _adapter.map_hash()
		_ref_c0 = _adapter.checksum_now()
		_check_all_done()
	else:
		_send_to_host(NetLobbyCodec.encode_load_done({"map_hash": _adapter.map_hash(), "checksum0": _adapter.checksum_now()}))
		_step = Step.WAIT_START
		if set_phase.is_valid():
			set_phase.call(NetSession.Phase.WAIT_START)


func _maybe_progress(now_us: int, pct: int, force: bool = false) -> void:
	if is_host or is_local:
		if pct != _last_pct and (force or now_us - _last_progress_us >= PROGRESS_PERIOD_US or _last_pct < 0):
			_last_pct = pct
			_last_progress_us = now_us
			if is_local and on_progress.is_valid():
				on_progress.call(PackedInt32Array([maxi(_local_pid, 0)]), PackedInt32Array([pct]))
		return
	# client: LOAD_PROGRESS when the percentage changed, at most 4 Hz
	if pct != _last_pct and (force or now_us - _last_progress_us >= PROGRESS_PERIOD_US or _last_pct < 0):
		_last_pct = pct
		_last_progress_us = now_us
		_send_to_host(NetLobbyCodec.encode_load_progress({"pct": pct}))


func _send_to_host(data: PackedByteArray) -> void:
	if send.is_valid():
		send.call(1, data)


func _human_pids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for pv: Variant in _cfg.get("players", []) as Array:
		var p: Dictionary = pv as Dictionary
		if str(p["kind"]) == "human":
			out.append(int(p["pid"]))
	return out


func _peer_for_pid(pid: int) -> NetPeerInfo:
	for k: Variant in peers:
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.slot == pid and p.stage != NetPeerInfo.Stage.LEFT:
			return p
	return null


func _host_status(now_us: int) -> void:
	if now_us - _last_status_us < STATUS_PERIOD_US:
		return
	_last_status_us = now_us
	var entries: Array = []
	var pids: PackedInt32Array = PackedInt32Array()
	var pcts: PackedInt32Array = PackedInt32Array()
	for pid: int in _human_pids():
		var pct: int = 0
		if pid == lobby.local_slot():
			pct = 100 if _own_done else (_last_pct if _last_pct >= 0 else 0)
		else:
			var p: NetPeerInfo = _peer_for_pid(pid)
			pct = 0 if p == null else (100 if p.loaded else p.load_pct)
		entries.append(PackedInt32Array([pid, pct]))
		pids.append(pid)
		pcts.append(pct)
	if entries.size() <= 8 and not entries.is_empty():
		_broadcast_loading(NetLobbyCodec.encode_load_status({"entries": entries}))
	if on_progress.is_valid():
		on_progress.call(pids, pcts)


func _host_timeouts(now_us: int) -> void:
	for k: Variant in peers.keys():
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.LOADING and not p.loaded and now_us - p.last_load_msg_us > NetProtocol.LOAD_TIMEOUT_MS * 1000:
			abort(NetProtocol.AbortReason.LOAD_TIMEOUT, p.slot if p.slot >= 0 else 255, "no progress from %s for %d s" % [p.name, NetProtocol.LOAD_TIMEOUT_MS / 1000])
			return


# =====================================================================================================================
# messages
# =====================================================================================================================

## Host: LOAD_PROGRESS / LOAD_DONE / LOAD_FAILED of a loading peer. Returns the violation weight (0 = fine).
func on_client_message(peer: NetPeerInfo, type: int, bytes: PackedByteArray, now_us: int) -> float:
	if _step != Step.LOADING:
		return 1.0
	peer.last_load_msg_us = now_us
	match type:
		NetProtocol.Msg.LOAD_PROGRESS:
			var d: Dictionary = NetLobbyCodec.decode_load_progress(bytes)
			if d.is_empty():
				return 3.0
			peer.load_pct = int(d["pct"])
			return 0.0
		NetProtocol.Msg.LOAD_DONE:
			var dd: Dictionary = NetLobbyCodec.decode_load_done(bytes)
			if dd.is_empty():
				return 3.0
			if peer.load_reported:
				return 1.0
			peer.load_reported = true
			peer.map_hash = int(dd["map_hash"])
			peer.checksum0 = int(dd["checksum0"])
			peer.loaded = true
			peer.load_pct = 100
			peer.stage = NetPeerInfo.Stage.LOADED
			_check_all_done()
			return 0.0
		NetProtocol.Msg.LOAD_FAILED:
			var f: Dictionary = NetLobbyCodec.decode_load_failed(bytes)
			if f.is_empty():
				return 3.0
			if peer.load_reported:
				return 1.0
			peer.load_reported = true
			abort(int(f["reason"]) if int(f["reason"]) != NetProtocol.AbortReason.NONE else NetProtocol.AbortReason.LOAD_FAILED,
				peer.slot if peer.slot >= 0 else 255, "%s: %s" % [peer.name, str(f["detail"])])
			return 0.0
	return 1.0


## A loading peer disappeared.
func on_peer_lost(peer: NetPeerInfo) -> void:
	if not is_host or _step != Step.LOADING:
		return
	abort(NetProtocol.AbortReason.HUMAN_LEFT, peer.slot if peer.slot >= 0 else 255, "%s left during loading" % peer.name)


func _check_all_done() -> void:
	if _step != Step.LOADING or not _own_done:
		return
	if is_local:
		_finish()
		return
	# compare every reported LOAD_DONE with the reference
	for k: Variant in peers.keys():
		var p: NetPeerInfo = peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.LOADED and p.loaded:
			if (p.map_hash & 0xFFFFFFFF) != (_ref_map & 0xFFFFFFFF):
				var msg: String = "%s generated a different map (host %08X, %s %08X)" % [p.name, _ref_map & 0xFFFFFFFF, p.name, p.map_hash & 0xFFFFFFFF]
				_log(NetProtocol.LogLevel.ERROR, "launch: " + msg)
				abort(NetProtocol.AbortReason.MAP_MISMATCH, p.slot, msg)
				return
			if (p.checksum0 & 0xFFFFFFFF) != (_ref_c0 & 0xFFFFFFFF):
				var msg2: String = "%s starts from a different state (host %08X, %s %08X)" % [p.name, _ref_c0 & 0xFFFFFFFF, p.name, p.checksum0 & 0xFFFFFFFF]
				_log(NetProtocol.LogLevel.ERROR, "launch: " + msg2)
				abort(NetProtocol.AbortReason.INIT_MISMATCH, p.slot, msg2)
				return
	for k: Variant in peers:
		var p2: NetPeerInfo = peers[k] as NetPeerInfo
		if p2.stage == NetPeerInfo.Stage.LOADING:
			return
	_finish()


func _finish() -> void:
	var adapter: NetSimAdapter = _adapter
	_adapter = null
	_step = Step.IDLE
	if adapter == null:
		return
	if on_start.is_valid():
		on_start.call(adapter, _cfg.duplicate(true), _json, _hash, _d0, _speed, _local_pid)
	if is_host:
		var start: PackedByteArray = NetLobbyCodec.encode_start({"config_hash": _hash, "input_delay": _d0, "speed_pct": _speed})
		for k: Variant in peers:
			var p: NetPeerInfo = peers[k] as NetPeerInfo
			if p.stage == NetPeerInfo.Stage.LOADED:
				p.stage = NetPeerInfo.Stage.PLAYING
				if send.is_valid():
					send.call(p.peer_id, start)


## Host / LOCAL: aborts the launch; everybody goes back to the lobby (LOCAL: the session ends).
func abort(reason: int, pid: int, detail: String) -> void:
	if _step == Step.IDLE:
		return
	_step = Step.IDLE
	_job = null
	_adapter = null
	_own_done = false
	if is_host:
		var data: PackedByteArray = NetLobbyCodec.encode_launch_abort({"reason": reason, "pid": pid, "detail": detail})
		for k: Variant in peers:
			var p: NetPeerInfo = peers[k] as NetPeerInfo
			if p.stage == NetPeerInfo.Stage.LOADING or p.stage == NetPeerInfo.Stage.LOADED:
				p.stage = NetPeerInfo.Stage.LOBBY
				p.loaded = false
				if send.is_valid():
					send.call(p.peer_id, data)
		lobby.set_phase(NetProtocol.LobbyPhase.OPEN)
		if on_timeouts.is_valid():
			on_timeouts.call(NetProtocol.TIMEOUTS_LOBBY)
	if on_aborted.is_valid():
		on_aborted.call(reason, pid, detail)


## Client: every launch related message from the host. `phase` is the session phase.
func on_host_message(type: int, bytes: PackedByteArray, phase: int) -> float:
	match type:
		NetProtocol.Msg.LAUNCH_COUNTDOWN:
			var d: Dictionary = NetLobbyCodec.decode_launch_countdown(bytes)
			if d.is_empty():
				return 3.0
			if phase != NetSession.Phase.LOBBY and phase != NetSession.Phase.COUNTDOWN:
				return 1.0
			var n: int = int(d["seconds_left"])
			lobby.note_countdown(n)
			if set_phase.is_valid():
				set_phase.call(NetSession.Phase.COUNTDOWN if n > 0 else NetSession.Phase.LOBBY)
			return 0.0
		NetProtocol.Msg.LAUNCH_CONFIG:
			if phase != NetSession.Phase.LOBBY and phase != NetSession.Phase.COUNTDOWN:
				return 1.0
			return _client_config(bytes)
		NetProtocol.Msg.LAUNCH_ABORT:
			var a: Dictionary = NetLobbyCodec.decode_launch_abort(bytes)
			if a.is_empty():
				return 3.0
			if phase < NetSession.Phase.COUNTDOWN or phase > NetSession.Phase.WAIT_START:
				return 1.0
			reset()
			if on_timeouts.is_valid():
				on_timeouts.call(NetProtocol.TIMEOUTS_LOBBY)
			lobby.note_countdown(0)
			if on_aborted.is_valid():
				on_aborted.call(int(a["reason"]), int(a["pid"]), str(a["detail"]))
			return 0.0
		NetProtocol.Msg.LOAD_STATUS:
			var s: Dictionary = NetLobbyCodec.decode_load_status(bytes)
			if s.is_empty():
				return 3.0
			var pids: PackedInt32Array = PackedInt32Array()
			var pcts: PackedInt32Array = PackedInt32Array()
			for e: Variant in s["entries"] as Array:
				pids.append((e as PackedInt32Array)[0])
				pcts.append((e as PackedInt32Array)[1])
			if on_progress.is_valid():
				on_progress.call(pids, pcts)
			return 0.0
		NetProtocol.Msg.START:
			return _client_start(bytes, phase)
	return 1.0


func _client_config(bytes: PackedByteArray) -> float:
	var json: String = NetLobbyCodec.inflate_config(bytes)
	var cfg: Dictionary = {}
	var err: String = ""
	if json.is_empty():
		err = "the match settings could not be read"
	else:
		cfg = NetMatchConfig.parse(json)
		err = NetMatchConfig.validate(cfg, opts)
	if err == "":
		_local_pid = NetMatchConfig.pid_of_peer(cfg, lobby.local_peer_id)
		if _local_pid < 0:
			err = "this peer is not part of the match"
	if err != "":
		_log(NetProtocol.LogLevel.WARN, "launch config refused: " + err)
		_send_to_host(NetLobbyCodec.encode_load_failed({"reason": NetProtocol.AbortReason.CONFIG_INVALID, "detail": err}))
		return 0.0
	_cfg = cfg
	_json = json
	_hash = NetMatchConfig.config_hash(json.to_utf8_buffer())
	_d0 = int((cfg["net"] as Dictionary)["input_delay"])
	_speed = int((cfg["net"] as Dictionary)["speed_pct"])
	_step = Step.LOADING
	_started_us = clock.now_us()
	_load_error_sent = false
	if set_phase.is_valid():
		set_phase.call(NetSession.Phase.LOADING)
	if on_timeouts.is_valid():
		on_timeouts.call(NetProtocol.TIMEOUTS_LOADING)
	_begin_job()
	return 0.0


func _client_start(bytes: PackedByteArray, phase: int) -> float:
	var d: Dictionary = NetLobbyCodec.decode_start(bytes)
	if d.is_empty():
		return 3.0
	if phase != NetSession.Phase.WAIT_START or _step != Step.WAIT_START:
		return 1.0
	if (int(d["config_hash"]) & 0xFFFFFFFF) != (_hash & 0xFFFFFFFF):
		var detail: String = "The match settings were corrupted in transit."
		_log(NetProtocol.LogLevel.ERROR, "START config hash %08X differs from local %08X" % [int(d["config_hash"]), _hash & 0xFFFFFFFF])
		reset()
		if on_aborted.is_valid():
			on_aborted.call(NetProtocol.AbortReason.CONFIG_INVALID, 255, detail)
		return 0.0
	var adapter: NetSimAdapter = _adapter
	_adapter = null
	_step = Step.IDLE
	if adapter != null and on_start.is_valid():
		on_start.call(adapter, _cfg.duplicate(true), _json, _hash, int(d["input_delay"]), int(d["speed_pct"]), _local_pid)
	return 0.0
