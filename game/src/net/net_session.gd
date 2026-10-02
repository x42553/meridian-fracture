class_name NetSession
extends RefCounted
## The network facade the app drives (docs/spec/net.md 3.0, 3.1, 5.3-5.5, 5.9, 5.12): one object per hosted game, joined
## game or single-player skirmish. HOST and CLIENT own an ENet (or injected) transport, LOCAL has none; everything else -
## lobby, launch, lockstep, host turn assembly, AI runner, desync detection, command log - is the same code on all roles.
##
## Frame contract: call `poll()` once per rendered frame BEFORE view/ui; it runs, in this order, discovery, transport
## events (<= 256), the launch step (world job slices of 4 ms), host bundle closing, the lockstep runner (0..8 ticks),
## host bundle closing again, timers and `transport.flush()`. Signals are emitted synchronously from inside poll();
## handlers may call any public method, but shutdown() / leave() from a handler is deferred to the end of the poll.

enum Role { NONE = 0, HOST = 1, CLIENT = 2, LOCAL = 3 }
enum Phase {
	IDLE = 0, CONNECTING = 1, LOBBY = 2, COUNTDOWN = 3, LOADING = 4, WAIT_START = 5, PLAYING = 6, PAUSED = 7, ENDED = 8,
	DESYNCED = 9, DISCONNECTED = 10,
}

signal phase_changed(phase: int, previous: int)
## Lobby state changed (re-render from lobby.state).
signal lobby_changed()
## channel 0 all / 1 team; from_pid 255 = system.
signal chat_received(channel: int, from_pid: int, from_name: String, text: String)
## 3, 2, 1, then 0 = aborted.
signal countdown_changed(seconds_left: int)
## RejectReason + info {reason, text, host_*, local_*, session_id, detail, diff_lines}.
signal join_rejected(reason: int, info: Dictionary)
## KickReason (client: removed / host gone).
signal kicked(reason: int, detail: String)
signal load_progress(pids: PackedInt32Array, percents: PackedInt32Array)
## AbortReason; the session is back in the lobby (LOCAL: IDLE).
signal launch_aborted(reason: int, detail: String)
signal match_started()
## Array[Dictionary] {pid, name, reason, wait_ms}; empty = resumed.
signal stall_changed(waiting: Array)
## Host only: offer WAIT / DROP_RESIGN / DROP_AI (host_resolve_stall).
signal stall_prompt(pids: PackedInt32Array)
signal pause_changed(paused: bool, by_pid: int)
signal player_status_changed(pid: int, status: int)
signal speed_changed(speed_pct: int)
signal input_delay_changed(turns: int)
## {reason (MatchEndReason), sim_reason, winner_team, final_tick, final_checksum}.
signal match_ended(result: Dictionary)
## The §7.5 report dictionary.
signal desync_detected(report: Dictionary)
## NetErrorCode + text.
signal net_error(code: int, text: String)
signal map_ping(from_pid: int, cell_x: int, cell_y: int)
## The match recording was written to disk (autosave_1.mfreplay): the path.
signal replay_saved(path: String)

const EVENT_CAP: int = 256
const PARTS_WAIT_US: int = 2_000_000
const JOIN_SNAPSHOT_US: int = 2_000_000
const LOG_RING: int = 400

## Why the last host() / join() / local() returned null.
static var last_create_error: String = ""
static var _process_nonce: int = 0

var role: int = Role.NONE
var phase: int = Phase.IDLE
## Valid in LOBBY..ENDED for HOST / CLIENT (and for LOCAL sessions created with local()); null for local_from_config().
var lobby: NetLobby = null
## Host announces; null for clients and LOCAL (browse with NetSession.create_browser).
var discovery: NetDiscovery = null
var local_peer_id: int = 0
## -1 for spectators / before launch.
var local_pid: int = -1
## Test / tool hook (tick, checksum, chain) on every lockstep checksum snapshot.
var checksum_observer: Callable = Callable()
## Hook (turn, bundle) on every executed bundle (replay recorders).
var turn_observer: Callable = Callable()
## () -> PackedByteArray: replay bytes for a desync package (default: a "command log lite" file).
var replay_bytes_provider: Callable = Callable()

var opts: NetSessionOptions = null
var clock: NetClock = null
var transport: NetTransport = null
var launch: NetLaunch = null
var lockstep: NetLockstep = null
var turn_host: NetTurnHost = null
var ai_runner: NetAiRunner = null
var desync: NetDesync = null

var _adapter: NetSimAdapter = null
var _config: Dictionary = {}
var _config_json: String = ""
var _config_hash: int = 0
var _match_id: String = ""
var _peers: Dictionary = {}
var _gate: NetHostGate = null
var _game: NetHostGame = null
var _backlog: Array[NetTransportEvent] = []
var _cmd_log: SimCommandLog = null
var _tap: NetReplayTap = null
var _in_poll: bool = false
var _deferred_leave: int = 0
var _shut: bool = false
var _status: PackedInt32Array = PackedInt32Array()
var _resigned_noted: Dictionary = {}
var _log_ring: PackedStringArray = PackedStringArray()
var _pause_by: int = 255
var _resume_by: int = 255
var _paused_flag: bool = false
var _client: NetClientGame = null
var _last_ping_us: int = 0
var _ping_seq: int = 0
var _last_lobby_ping_us: int = 0
var _last_checksum_tick: int = -1
var _end_result: Dictionary = {}
var _declared_end: int = -1
var _flow: NetDesyncFlow = null
# client join state
var _join: NetJoinClient = null
var _got_kicked: bool = false
var _return_pending: bool = false  ## client: RETURN_TO_LOBBY arrived before this peer's own match end


# =====================================================================================================================
# construction
# =====================================================================================================================

static func _fail(text: String) -> NetSession:
	last_create_error = text
	return null


static func _check_options(o: NetSessionOptions, need_rosters: bool = true) -> String:
	if o == null:
		return "no options"
	if not o.world_builder.is_valid():
		return "opts.world_builder is missing"
	if need_rosters and o.roster_ids.size() != 32:
		return "opts.roster_ids must list exactly the 32 playable rosters (got %d)" % o.roster_ids.size()
	return ""


static func _random_u32() -> int:
	return Crypto.new().generate_random_bytes(4).decode_u32(0)


func _init_common(o: NetSessionOptions, r: int) -> void:
	opts = o.duplicate_options()
	clock = opts.clock if opts.clock != null else NetClock.real()
	opts.clock = clock
	role = r
	_status.resize(NetProtocol.MAX_PLAYERS)
	_client = NetClientGame.new()
	_client.send_host = _send_host
	_client.emit_stall = _emit_client_stall
	_client.emit_error = _emit_error
	_client.on_final_mismatch = _client_final_mismatch
	_client.log_fn = _log
	if _process_nonce == 0:
		_process_nonce = _random_u32() | 1
	if opts.client_nonce == 0:
		opts.client_nonce = _process_nonce
	if opts.data_handshake.is_valid() and opts.data_hash == 0:
		opts.data_hash = int((opts.data_handshake.call(false) as Dictionary).get("hash", 0))


func _make_transport() -> NetTransport:
	if opts.transport_factory.is_valid():
		return opts.transport_factory.call() as NetTransport
	return NetTransportEnet.new()


func _wire_lobby(st: NetLobbyState, host_role: bool) -> void:
	lobby = NetLobby.new()
	lobby.setup(opts, clock, host_role, st)
	lobby.peers = _peers
	lobby.local_peer_id = local_peer_id
	lobby.send = _lobby_send
	lobby.disconnect_peer = _lobby_disconnect
	lobby.kick_peer = _drop_peer
	lobby.begin_countdown = _lobby_begin_countdown
	lobby.cancel_countdown = _lobby_cancel_countdown
	lobby.changed.connect(_on_lobby_changed)
	lobby.chat_received.connect(_on_lobby_chat)
	lobby.countdown_changed.connect(_on_lobby_countdown)


func _wire_launch() -> void:
	launch = NetLaunch.new()
	launch.opts = opts
	launch.clock = clock
	launch.lobby = lobby
	launch.peers = _peers
	launch.is_host = role == Role.HOST
	launch.is_local = role == Role.LOCAL
	launch.send = _lobby_send
	launch.set_phase = _set_phase
	launch.on_aborted = _on_launch_aborted
	launch.on_progress = _on_launch_progress
	launch.on_timeouts = _apply_timeouts
	launch.on_start = _begin_match
	launch.on_kick = _drop_peer
	launch.log_fn = _log


## Hosts a game: listens (port scan from opts.port), announces on the LAN and creates the lobby. Null on failure
## (see last_create_error).
static func host(o: NetSessionOptions, lobby_name: String = "") -> NetSession:
	var bad: String = _check_options(o)
	if bad != "":
		return _fail(bad)
	var s: NetSession = NetSession.new()
	s._init_common(o, Role.HOST)
	s.transport = s._make_transport()
	if s.transport == null or s.transport.listen(s.opts.port, NetProtocol.ENET_MAX_PEERS) != OK:
		s.transport = null
		return _fail("no free network port (%d-%d)" % [s.opts.port, s.opts.port + NetProtocol.PORT_SCAN_COUNT - 1])
	s.local_peer_id = 1
	s._setup_gate()
	var st: NetLobbyState = NetLobbyState.create_default(s.opts.player_name, _random_u32(), _random_u32(), s.opts)
	st.host_name = NetProtocol.sanitize_name(lobby_name if not lobby_name.is_empty() else s.opts.player_name)
	s._wire_lobby(st, true)
	s._wire_launch()
	s._apply_timeouts(NetProtocol.TIMEOUTS_LOBBY)
	if s.opts.dedicated:
		s.local_pid = -1
	s._set_phase(Phase.LOBBY)
	if s.opts.discovery_enabled:
		s._start_discovery()
	last_create_error = ""
	return s


## Joins a hosted game. `address` may carry its own port ("192.168.1.20:27616"); `port` is used otherwise.
static func join(o: NetSessionOptions, address: String, port: int = NetProtocol.DEFAULT_PORT) -> NetSession:
	var bad: String = _check_options(o)
	if bad != "":
		return _fail(bad)
	var pa: Dictionary = NetProtocol.parse_address(address)
	if not bool(pa["ok"]):
		return _fail("bad address: " + str(pa["error"]))
	var s: NetSession = NetSession.new()
	s._init_common(o, Role.CLIENT)
	s._join = NetJoinClient.new()
	s._join.opts = s.opts
	s._join.host = str(pa["host"])
	s._join.port = int(pa["port"]) if address.strip_edges().contains(":") else port
	s._join.session_id = s.opts.join_session_id
	s._join.send = s._send_host
	s._join.reconnect = s._reconnect
	s._join.on_rejected = s._join_rejected_final
	s._join.on_failed = s._client_fail_connect
	s._join.on_accepted = s._join_accepted
	s.transport = s._make_transport()
	if s.transport == null or s.transport.connect_to(s._join.host, s._join.port, NetProtocol.connect_data()) != OK:
		s.transport = null
		return _fail("could not start connecting")
	s._wire_lobby(NetLobbyState.new(), false)
	s._wire_launch()
	s._join.begin(s.clock.now_us())
	s._set_phase(Phase.CONNECTING)
	last_create_error = ""
	return s


## Single-player skirmish: no transport, everything else is the multiplayer pipeline. `lobby_state` is a NetLobbyState
## (create_skirmish) whose slot 0 is the local player. The start conditions (NetLobby.StartError) are checked first.
static func local(o: NetSessionOptions, lobby_state: NetLobbyState) -> NetSession:
	var bad: String = _check_options(o)
	if bad != "":
		return _fail(bad)
	var s: NetSession = NetSession.new()
	s._init_common(o, Role.LOCAL)
	s.local_peer_id = 1
	s._make_game(true)
	var st: NetLobbyState = lobby_state.duplicate_state()
	if st.session_id == 0:
		st.session_id = _random_u32()
	s._wire_lobby(st, true)
	var err: int = s.lobby.start_error()
	if err != NetLobby.StartError.OK:
		return _fail(NetLobby.start_error_text(err))
	s._wire_launch()
	var msg: String = s.launch.begin_local()
	if msg != "":
		return _fail(msg)
	last_create_error = ""
	return s


## Tests / tools: starts directly from a finished MatchConfig dictionary (schema 7.1). No lobby object.
static func local_from_config(o: NetSessionOptions, match_config: Dictionary) -> NetSession:
	var bad: String = _check_options(o, false)
	if bad != "":
		return _fail(bad)
	var s: NetSession = NetSession.new()
	s._init_common(o, Role.LOCAL)
	s.local_peer_id = 1
	s._make_game(true)
	var cfg: Dictionary = NetMatchConfig.normalize(match_config)
	var err: String = NetMatchConfig.validate(cfg, s.opts)
	if err != "":
		return _fail(err)
	s._wire_launch()
	var msg: String = s.launch.begin_local_config(cfg)
	if msg != "":
		return _fail(msg)
	last_create_error = ""
	return s


## A standalone LAN browser (call start_browse(), poll() it each frame, read entries()).
static func create_browser(o: NetSessionOptions) -> NetDiscovery:
	var d: NetDiscovery = NetDiscovery.new()
	d.setup(o.clock if o.clock != null else NetClock.real(), o.game_version, NetProtocol.PROTO_VERSION, o.sim_version, o.data_hash)
	d.port = o.discovery_port
	d.allow_public = o.allow_public_discovery
	return d


func _start_discovery() -> void:
	discovery = NetDiscovery.new()
	discovery.setup(clock, opts.game_version, NetProtocol.PROTO_VERSION, opts.sim_version, opts.data_hash)
	discovery.port = opts.discovery_port
	discovery.allow_public = opts.allow_public_discovery
	discovery.set_targets_override(opts.discovery_targets)
	discovery.start_announce(lobby.discovery_info, transport.local_port())



# =====================================================================================================================
# logging / phase
# =====================================================================================================================

func _log(level: int, text: String) -> void:
	_log_ring.append("[net] " + text)
	if _log_ring.size() > LOG_RING:
		_log_ring = _log_ring.slice(_log_ring.size() - LOG_RING)
	if opts != null and opts.log_sink.is_valid():
		opts.log_sink.call(level, text)
	elif level >= NetProtocol.LogLevel.ERROR:
		Log.error("net", text)
	elif level == NetProtocol.LogLevel.WARN:
		Log.warn("net", text)
	elif level == NetProtocol.LogLevel.INFO:
		Log.info("net", text)
	else:
		Log.debug("net", text)


const _LEGAL: Dictionary = {
	Phase.IDLE: [Phase.CONNECTING, Phase.LOBBY, Phase.LOADING],
	Phase.CONNECTING: [Phase.LOBBY, Phase.IDLE, Phase.DISCONNECTED],
	Phase.LOBBY: [Phase.COUNTDOWN, Phase.LOADING, Phase.DISCONNECTED, Phase.IDLE],
	Phase.COUNTDOWN: [Phase.LOBBY, Phase.LOADING, Phase.DISCONNECTED, Phase.IDLE],
	Phase.LOADING: [Phase.WAIT_START, Phase.PLAYING, Phase.LOBBY, Phase.DISCONNECTED, Phase.IDLE],
	Phase.WAIT_START: [Phase.PLAYING, Phase.LOBBY, Phase.DISCONNECTED, Phase.IDLE],
	Phase.PLAYING: [Phase.PAUSED, Phase.ENDED, Phase.DESYNCED, Phase.DISCONNECTED, Phase.IDLE],
	Phase.PAUSED: [Phase.PLAYING, Phase.ENDED, Phase.DESYNCED, Phase.DISCONNECTED, Phase.IDLE],
	Phase.ENDED: [Phase.LOBBY, Phase.DESYNCED, Phase.DISCONNECTED, Phase.IDLE],
	Phase.DESYNCED: [Phase.LOBBY, Phase.DISCONNECTED, Phase.IDLE],
	Phase.DISCONNECTED: [Phase.IDLE],
}


func _set_phase(p: int) -> void:
	if p == phase:
		return
	if not (_LEGAL.get(phase, []) as Array).has(p):
		_log(NetProtocol.LogLevel.WARN, "illegal phase transition %d -> %d ignored" % [phase, p])
		net_error.emit(NetProtocol.NetErrorCode.TRANSPORT, "illegal phase transition %d -> %d" % [phase, p])
		return
	var prev: int = phase
	phase = p
	if _gate != null:
		_gate.phase = p
	phase_changed.emit(p, prev)


func _apply_timeouts(t: PackedInt32Array) -> void:
	if transport != null and t.size() == 3:
		transport.set_timeouts(t[0], t[1], t[2])


func _on_lobby_changed() -> void:
	lobby_changed.emit()


func _on_lobby_chat(channel: int, from_slot: int, from_name: String, text: String) -> void:
	if _tap != null and lockstep != null and (phase == Phase.PLAYING or phase == Phase.PAUSED):
		_tap.chat(lockstep.exec_turn(), from_slot if from_slot >= 0 else 255, text)
	chat_received.emit(channel, from_slot, from_name, text)


func _on_lobby_countdown(n: int) -> void:
	countdown_changed.emit(n)


func _lobby_send(peer_id: int, data: PackedByteArray) -> void:
	_send(peer_id, data)


func _lobby_disconnect(peer_id: int, code: int) -> void:
	if transport != null:
		transport.disconnect_peer(peer_id, code, true)


func _lobby_begin_countdown() -> void:
	launch.begin_countdown(opts.countdown_s)


func _lobby_cancel_countdown() -> void:
	launch.cancel_countdown()


func _send(peer_id: int, data: PackedByteArray) -> void:
	if transport == null or data.is_empty():
		return
	var ch: int = NetProtocol.msg_channel(data[0])
	if ch < 0:
		return
	transport.send(peer_id, ch, data)


func _send_host(data: PackedByteArray) -> void:
	_send(1, data)


func _on_launch_progress(pids: PackedInt32Array, pcts: PackedInt32Array) -> void:
	load_progress.emit(pids, pcts)


func _on_launch_aborted(reason: int, pid: int, detail: String) -> void:
	_log(NetProtocol.LogLevel.WARN, "launch aborted: reason=%d pid=%d %s" % [reason, pid, detail])
	_teardown_match()
	if role == Role.LOCAL:
		_set_phase(Phase.IDLE)
	else:
		_set_phase(Phase.LOBBY)
		_apply_timeouts(NetProtocol.TIMEOUTS_LOBBY)
	launch_aborted.emit(reason, detail)


# =====================================================================================================================
# poll
# =====================================================================================================================

## Once per rendered frame, before view/ui. Returns the sim ticks executed (spec 3.0 order).
func poll() -> int:
	if _shut or role == Role.NONE:
		return 0
	assert(not _in_poll, "NetSession.poll() called re-entrantly")
	if _in_poll:
		return 0
	_in_poll = true
	var now: int = clock.now_us()
	if discovery != null:
		discovery.poll()
	if transport != null:
		transport.poll()
		_process_events(now)
	if launch != null and _active():
		launch.step(now, 4000)
	var ticks: int = 0
	if lockstep != null and _active():
		var in_game: bool = phase == Phase.PLAYING or phase == Phase.PAUSED
		if role != Role.CLIENT and in_game:
			_game.close_and_send()
		if in_game:
			# Spec order: close (5), update (6), close (7). Host / LOCAL repeat 7 -> 6 while ticks keep coming (the local
			# fill-up completes the next turn), so an unpaced session is not limited to one turn per poll.
			var left: int = opts.max_ticks_per_poll
			while left > 0:
				var n: int = lockstep.update(left)
				ticks += n
				left -= n
				if n == 0 or role == Role.CLIENT or (phase != Phase.PLAYING and phase != Phase.PAUSED):
					break
				_game.close_and_send()
			if opts.auto_clear_events and ticks > 0 and _adapter != null:
				_adapter.clear_events()
		if role != Role.CLIENT and (phase == Phase.PLAYING or phase == Phase.PAUSED):
			_game.close_and_send()
	if _return_pending and (phase == Phase.ENDED or phase == Phase.DESYNCED) and role == Role.CLIENT:
		_back_to_lobby()
	_timers(now)
	if transport != null:
		transport.flush()
	_in_poll = false
	if _deferred_leave != 0:
		var d: int = _deferred_leave
		_deferred_leave = 0
		if d == 2:
			shutdown()
		else:
			leave()
	return ticks


func _active() -> bool:
	return not _shut and phase != Phase.IDLE


## Fraction of the current tick elapsed, in [0,1) (view-only float).
func tick_alpha() -> float:
	return lockstep.tick_alpha() if lockstep != null and phase == Phase.PLAYING else 0.0


func _process_events(now: int) -> void:
	var xp: NetTransport = transport
	var evs: Array[NetTransportEvent] = _backlog
	_backlog = []
	evs.append_array(transport.take_events())
	var n: int = 0
	for i: int in evs.size():
		if n >= EVENT_CAP:
			_backlog.append_array(evs.slice(i))
			break
		n += 1
		if _shut or transport == null or transport != xp:
			return
		var e: NetTransportEvent = evs[i]
		match e.kind:
			NetTransportEvent.Kind.CONNECTED:
				_on_connected(e, now)
			NetTransportEvent.Kind.DISCONNECTED:
				_on_disconnected(e, now)
			NetTransportEvent.Kind.PACKET:
				if role == Role.HOST:
					_gate.on_packet(e.peer_id, e.channel, e.data, now)
				elif role == Role.CLIENT:
					_client_packet(e, now)


# =====================================================================================================================
# host: connections and dispatch
# =====================================================================================================================

func _on_connected(e: NetTransportEvent, now: int) -> void:
	if role == Role.CLIENT:
		if e.peer_id == 1 and phase == Phase.CONNECTING and _join != null:
			_join.on_connected(now)
		return
	if role == Role.HOST:
		_gate.on_connected(e.peer_id, e.code, e.address, now)


func _on_disconnected(e: NetTransportEvent, now: int) -> void:
	if role == Role.HOST:
		var p: NetPeerInfo = _peers.get(e.peer_id) as NetPeerInfo
		if p != null:
			_peer_gone(p, now)
	elif role == Role.CLIENT and e.peer_id == 1:
		_client_transport_lost(e.code, now)


## The peer's connection ended (transport event, leave, kick). Idempotent.
func _peer_gone(p: NetPeerInfo, _now: int) -> void:
	if not _peers.has(p.peer_id):
		return
	var was_stage: int = p.stage
	_peers.erase(p.peer_id)
	if was_stage == NetPeerInfo.Stage.HANDSHAKE or was_stage == NetPeerInfo.Stage.LEFT:
		return
	if launch != null and (was_stage == NetPeerInfo.Stage.LOADING or was_stage == NetPeerInfo.Stage.LOADED):
		p.stage = NetPeerInfo.Stage.LOADING
		_peers[p.peer_id] = p
		launch.on_peer_lost(p)
		_peers.erase(p.peer_id)
	if turn_host != null and (was_stage == NetPeerInfo.Stage.PLAYING):
		turn_host.peer_disconnected(p.peer_id)
		return
	p.stage = NetPeerInfo.Stage.LEFT
	if lobby != null:
		lobby.on_peer_gone(p.peer_id)


## KICKED + graceful disconnect + bookkeeping (lobby kicks, protocol violations, dropped players).
func _drop_peer(peer_id: int, reason: int, detail: String) -> void:
	var p: NetPeerInfo = _peers.get(peer_id) as NetPeerInfo
	if p == null or transport == null:
		return
	_send(peer_id, NetLobbyCodec.encode_kicked({"reason": reason, "detail": detail}))
	transport.disconnect_peer(peer_id, reason, true)
	if p.stage == NetPeerInfo.Stage.PLAYING and turn_host != null:
		var pid: int = NetMatchConfig.pid_of_peer(_config, peer_id)
		_peers.erase(peer_id)
		p.stage = NetPeerInfo.Stage.LEFT
		if pid >= 0 and turn_host.role_of(pid) == NetProtocol.PlayerRole.PR_HUMAN:
			var mode: int = NetProtocol.StallAction.STALL_DROP_AI if int((_config["net"] as Dictionary)["on_disconnect"]) == NetProtocol.OnDisconnect.AI \
				else NetProtocol.StallAction.STALL_DROP_RESIGN
			turn_host.drop_player(pid, mode, NetProtocol.ResignReason.KICKED)
		return
	_peer_gone(p, clock.now_us())


func _h_join(p: NetPeerInfo, data: PackedByteArray, _now: int) -> float:
	var w: float = lobby.handle_join(p, data)
	if p.stage == NetPeerInfo.Stage.LEFT:
		_peers.erase(p.peer_id)
	return w


func _h_action(p: NetPeerInfo, data: PackedByteArray, _now: int) -> float:
	return lobby.handle_action(p, data)


func _h_chat(p: NetPeerInfo, data: PackedByteArray, _now: int) -> float:
	return lobby.handle_chat(p, data)


func _h_leave(p: NetPeerInfo, data: PackedByteArray, now: int) -> float:
	if NetLobbyCodec.decode_leave(data).is_empty():
		return 3.0
	_host_leave(p, now)
	return 0.0


func _h_load(p: NetPeerInfo, data: PackedByteArray, now: int) -> float:
	return launch.on_client_message(p, data[0], data, now)


func _violate(p: NetPeerInfo, weight: float, why: String) -> void:
	_gate.violate(p, weight, why, clock.now_us())


func _setup_gate() -> void:
	_make_game(role == Role.LOCAL)
	_gate = NetHostGate.new()
	_gate.peers = _peers
	_gate.disconnect_fn = _gate_disconnect
	_gate.kick = _drop_peer
	_gate.log_fn = _log
	_gate.on_oversize_input = _game.handle_oversize_input_hook
	_gate.handlers = {
		NetProtocol.Msg.JOIN_REQUEST: _h_join, NetProtocol.Msg.LOBBY_ACTION: _h_action, NetProtocol.Msg.CHAT: _h_chat,
		NetProtocol.Msg.LEAVE: _h_leave, NetProtocol.Msg.MAP_PING: _game.handle_map_ping,
		NetProtocol.Msg.LOAD_PROGRESS: _h_load, NetProtocol.Msg.LOAD_DONE: _h_load, NetProtocol.Msg.LOAD_FAILED: _h_load,
		NetProtocol.Msg.TURN_INPUT: _game.handle_turn_input, NetProtocol.Msg.PONG: _game.handle_pong,
		NetProtocol.Msg.PAUSE_REQUEST: _game.handle_pause_request, NetProtocol.Msg.CHECKSUM_REPORT: _game.handle_checksum_report,
		NetProtocol.Msg.PARTS_REPORT: _game.handle_parts_report,
	}


func _make_game(is_local: bool) -> void:
	_game = NetHostGame.new()
	_game.opts = opts
	_game.clock = clock
	_game.is_local = is_local
	_game.peers = _peers
	_game.local_peer_id = local_peer_id
	_game.send = _send
	_game.disconnect_fn = _gate_disconnect
	_game.emit_stall = _emit_stall
	_game.emit_prompt = _emit_prompt
	_game.emit_status = _emit_status
	_game.emit_map_ping = _emit_map_ping
	_game.emit_error = _emit_error
	_game.note_resume_by = _note_resume_by
	_game.log_fn = _log
	_game.pid_name = _pid_name


func _emit_client_stall(waiting: Array) -> void:
	stall_changed.emit(waiting)


func _client_final_mismatch(tick: int) -> void:
	_local_desync(tick, NetProtocol.DesyncKind.SIM)


func _emit_stall(waiting: Array) -> void:
	_client.stall_entries = waiting
	stall_changed.emit(waiting.duplicate(true))


func _emit_prompt(pids: PackedInt32Array) -> void:
	stall_prompt.emit(pids)


func _emit_status(pid: int, status: int) -> void:
	_status[pid] = status
	player_status_changed.emit(pid, status)


func _emit_map_ping(from_pid: int, x: int, y: int) -> void:
	map_ping.emit(from_pid, x, y)


func _emit_error(code: int, text: String) -> void:
	net_error.emit(code, text)


func _note_resume_by(pid: int) -> void:
	_resume_by = pid


func _gate_disconnect(peer_id: int, code: int, graceful: bool) -> void:
	if transport != null:
		transport.disconnect_peer(peer_id, code, graceful)


func _host_leave(p: NetPeerInfo, now: int) -> void:
	if transport != null:
		transport.disconnect_peer(p.peer_id, NetProtocol.KickReason.NONE, true)
	if p.stage == NetPeerInfo.Stage.PLAYING and turn_host != null:
		var pid: int = NetMatchConfig.pid_of_peer(_config, p.peer_id)
		_peers.erase(p.peer_id)
		p.stage = NetPeerInfo.Stage.LEFT
		if pid >= 0:
			turn_host.player_left(pid)
		return
	_peer_gone(p, now)


# ---- in-match host handlers ---------------------------------------------------------------------------------------

# =====================================================================================================================
# client: join, dispatch
# =====================================================================================================================

func _client_fail_connect(text: String) -> void:
	net_error.emit(NetProtocol.NetErrorCode.TRANSPORT, text)
	_close_transport()
	_set_phase(Phase.IDLE)


func _client_transport_lost(code: int, _now: int) -> void:
	if phase == Phase.CONNECTING:
		if _join != null and _join.on_transport_lost():
			return
		_client_fail_connect(_join.connect_timeout_text() if _join != null else "connection lost")
		return
	if _got_kicked or phase == Phase.IDLE or phase == Phase.DISCONNECTED:
		return
	var reason: int = code if code >= 0 and code <= NetProtocol.KickReason.VERSION else NetProtocol.KickReason.TIMEOUT
	if code == 0:
		reason = NetProtocol.KickReason.TIMEOUT
	_enter_disconnected(reason, "")


func _enter_disconnected(reason: int, detail: String) -> void:
	_got_kicked = true
	var was_playing: bool = phase == Phase.PLAYING or phase == Phase.PAUSED or phase == Phase.WAIT_START
	_close_transport()
	if was_playing and _end_result.is_empty():
		var res: Dictionary = {
			"reason": NetProtocol.MatchEndReason.ABANDONED, "sim_reason": 0, "winner_team": -1,
			"final_tick": _adapter.current_tick() if _adapter != null else 0, "final_checksum": _adapter.checksum_now() if _adapter != null else 0,
		}
		_end_result = res
		_set_phase(Phase.DISCONNECTED)
		match_ended.emit(res)
	else:
		_set_phase(Phase.DISCONNECTED)
	kicked.emit(reason, detail)


func _close_transport() -> void:
	if transport != null:
		transport.close()


func _client_allows(type: int) -> bool:
	match type:
		NetProtocol.Msg.JOIN_REJECT, NetProtocol.Msg.JOIN_ACCEPT, NetProtocol.Msg.DATA_DIFF:
			return phase == Phase.CONNECTING
		NetProtocol.Msg.LOBBY_SNAPSHOT:
			return phase == Phase.CONNECTING or phase == Phase.LOBBY or phase == Phase.COUNTDOWN or phase == Phase.LOADING or phase == Phase.WAIT_START or phase == Phase.ENDED
		NetProtocol.Msg.CHAT:
			return phase != Phase.CONNECTING and phase != Phase.IDLE and phase != Phase.DISCONNECTED
		NetProtocol.Msg.KICKED:
			return phase != Phase.IDLE and phase != Phase.DISCONNECTED
		NetProtocol.Msg.MAP_PING:
			return phase == Phase.PLAYING or phase == Phase.PAUSED
		NetProtocol.Msg.LAUNCH_COUNTDOWN:
			return phase == Phase.LOBBY or phase == Phase.COUNTDOWN
		NetProtocol.Msg.LAUNCH_CONFIG:
			return phase == Phase.LOBBY or phase == Phase.COUNTDOWN
		NetProtocol.Msg.LAUNCH_ABORT:
			return phase >= Phase.COUNTDOWN and phase <= Phase.WAIT_START
		NetProtocol.Msg.LOAD_STATUS:
			return phase == Phase.LOADING or phase == Phase.WAIT_START
		NetProtocol.Msg.START:
			return phase == Phase.WAIT_START
		NetProtocol.Msg.RETURN_TO_LOBBY:
			# also while the match is still running here: the host decided the end a few turns ago and its player was quicker than this
			# peer's lockstep (queued until this peer's own end, see `_return_pending`)
			return phase == Phase.ENDED or phase == Phase.DESYNCED or phase == Phase.PLAYING or phase == Phase.PAUSED
		NetProtocol.Msg.TURN_BUNDLE:
			return phase == Phase.WAIT_START or phase == Phase.PLAYING or phase == Phase.PAUSED
		NetProtocol.Msg.PING, NetProtocol.Msg.STALL_INFO, NetProtocol.Msg.RESUME:
			return phase == Phase.PLAYING or phase == Phase.PAUSED
		NetProtocol.Msg.DESYNC_NOTICE, NetProtocol.Msg.PARTS_REQUEST:
			return phase == Phase.PLAYING or phase == Phase.PAUSED or phase == Phase.ENDED or phase == Phase.DESYNCED
		NetProtocol.Msg.MATCH_END:
			return phase == Phase.PLAYING or phase == Phase.PAUSED or phase == Phase.ENDED
	return false


func _client_packet(e: NetTransportEvent, now: int) -> void:
	if e.peer_id != 1 or _got_kicked:
		return
	var data: PackedByteArray = e.data
	if data.is_empty():
		return
	var type: int = data[0]
	if not NetProtocol.is_known_msg(type) or NetProtocol.msg_dir(type) == NetProtocol.DIR_C2H:
		_log(NetProtocol.LogLevel.WARN, "host sent an invalid message type %d" % type)
		return
	if data.size() > NetProtocol.msg_max_bytes(type) or e.channel != NetProtocol.msg_channel(type):
		_log(NetProtocol.LogLevel.WARN, "host sent an oversize or misrouted %s" % NetProtocol.msg_name(type))
		net_error.emit(NetProtocol.NetErrorCode.HOST_PROTOCOL, "oversize or misrouted " + NetProtocol.msg_name(type))
		return
	if not _client_allows(type):
		if phase != Phase.IDLE and phase != Phase.DISCONNECTED:
			_log(NetProtocol.LogLevel.DEBUG, "ignored %s in phase %d" % [NetProtocol.msg_name(type), phase])
		return
	match type:
		NetProtocol.Msg.JOIN_REJECT, NetProtocol.Msg.DATA_DIFF, NetProtocol.Msg.JOIN_ACCEPT:
			_join.on_message(type, data, now)
		NetProtocol.Msg.LOBBY_SNAPSHOT:
			_on_snapshot(data)
		NetProtocol.Msg.CHAT:
			lobby.handle_chat_h2c(data)
		NetProtocol.Msg.KICKED:
			_on_kicked(data)
		NetProtocol.Msg.MAP_PING:
			var mp: Dictionary = NetLobbyCodec.decode_map_ping_h2c(data)
			if not mp.is_empty():
				map_ping.emit(int(mp["from_pid"]), int(mp["cell_x"]), int(mp["cell_y"]))
		NetProtocol.Msg.LAUNCH_COUNTDOWN, NetProtocol.Msg.LAUNCH_CONFIG, NetProtocol.Msg.LAUNCH_ABORT, NetProtocol.Msg.LOAD_STATUS, NetProtocol.Msg.START:
			var w: float = launch.on_host_message(type, data, phase)
			if w >= 3.0:
				net_error.emit(NetProtocol.NetErrorCode.HOST_PROTOCOL, "malformed " + NetProtocol.msg_name(type))
		NetProtocol.Msg.RETURN_TO_LOBBY:
			if not NetLobbyCodec.decode_return_to_lobby(data).is_empty():
				if phase == Phase.ENDED or phase == Phase.DESYNCED:
					_back_to_lobby()
				else:
					_return_pending = true
		NetProtocol.Msg.TURN_BUNDLE:
			_client.handle_bundle(data, phase == Phase.WAIT_START)
		NetProtocol.Msg.PING:
			_client.handle_ping(data)
		NetProtocol.Msg.STALL_INFO:
			_client.handle_stall_info(data, now)
		NetProtocol.Msg.RESUME:
			var r: Dictionary = NetCodec.decode_resume(data)
			if not r.is_empty() and lockstep != null:
				_resume_by = int(r["by_pid"])
				lockstep.resume(int(r["resume_turn"]))
		NetProtocol.Msg.DESYNC_NOTICE:
			_client_desync_notice(data, now)
		NetProtocol.Msg.PARTS_REQUEST:
			_client_parts_request(data)
		NetProtocol.Msg.MATCH_END:
			_client.handle_match_end(data)


func _join_accepted(peer_id: int, session_id: int, _slot: int) -> void:
	local_peer_id = peer_id
	lobby.local_peer_id = peer_id
	lobby.set_session_id(session_id)


func _on_snapshot(data: PackedByteArray) -> void:
	if lobby.handle_snapshot(data):
		if phase == Phase.CONNECTING and _join != null and _join.stage == NetJoinClient.Stage.ACCEPTED:
			_join.complete()
			_set_phase(Phase.LOBBY)
			_apply_timeouts(NetProtocol.TIMEOUTS_LOBBY)


func _on_kicked(data: PackedByteArray) -> void:
	var d: Dictionary = NetLobbyCodec.decode_kicked(data)
	if d.is_empty():
		return
	_enter_disconnected(int(d["reason"]), str(d["detail"]))


## Closes the transport and opens a fresh one for a retry of the join (the transport factory must return a new one).
func _reconnect(_with_files: bool) -> bool:
	_close_transport()
	transport = _make_transport()
	if transport == null or _join == null:
		return false
	return transport.connect_to(_join.host, _join.port, NetProtocol.connect_data()) == OK


func _join_rejected_final(reason: int, info: Dictionary) -> void:
	_close_transport()
	_set_phase(Phase.IDLE)
	join_rejected.emit(reason, info)


# ---- client in-match handlers -------------------------------------------------------------------------------------

func _pid_name(pid: int) -> String:
	return _client.pid_name(pid)


# =====================================================================================================================
# match start / teardown
# =====================================================================================================================

## Launch finished on this peer (host after all LOAD_DONE, client on START, LOCAL immediately).
func _begin_match(sim: NetSimAdapter, cfg: Dictionary, json: String, cfg_hash: int, d0: int, speed_pct: int, lpid: int) -> void:
	_adapter = sim
	_config = cfg
	_config_json = json
	_config_hash = cfg_hash
	_match_id = str(cfg["match_id"])
	local_pid = lpid
	_end_result = {}
	_client.reset()
	_client.config = cfg
	_declared_end = -1
	_resigned_noted.clear()
	_paused_flag = false
	_pause_by = 255
	_last_checksum_tick = -1
	for i: int in NetProtocol.MAX_PLAYERS:
		_status[i] = NetProtocol.PlayerNetStatus.ACTIVE
	_cmd_log = SimCommandLog.new() if opts.record_command_log else null
	_abandon_tap()
	var eff: int = speed_pct
	if opts.speed_pct_override == 0:
		eff = 0
	elif opts.speed_pct_override > 0:
		eff = clampi(opts.speed_pct_override, 50, 200)
	lockstep = NetLockstep.new()
	lockstep.setup(sim, clock, lpid, d0, eff)
	lockstep.on_turn_begin = _ls_turn_begin
	lockstep.on_checksum = _ls_checksum
	lockstep.on_ctrl = _ls_ctrl
	lockstep.on_pause = _ls_pause
	lockstep.on_match_over = _ls_match_over
	desync = NetDesync.new()
	desync.setup(sim, role != Role.CLIENT, lpid, _match_id, json)
	desync.dir = opts.desync_dir
	desync.keep = opts.desync_keep
	_client.lockstep = lockstep
	_make_flow()
	if role == Role.CLIENT:
		lockstep.on_send_input = _ls_send_input_client
		lockstep.on_stall_changed = _client.on_lockstep_stall
	else:
		desync.on_detected = _host_desync_detected
		_game.config = cfg
		_game.local_pid = lpid
		_game.lockstep = lockstep
		_game.desync = desync
		_game.adapter = sim
		_game.setup(d0, speed_pct)
		turn_host = _game.turn_host
		ai_runner = _game.ai_runner
		lockstep.on_send_input = _game.send_input_local
		lockstep.on_boundary = _game.boundary
	_start_tap(json)
	lockstep.start()
	if lobby != null and role != Role.CLIENT:
		lobby.set_phase(NetProtocol.LobbyPhase.IN_GAME)
	_apply_timeouts(NetProtocol.TIMEOUTS_GAME)
	_set_phase(Phase.PLAYING)
	if role == Role.CLIENT:
		_client.drain_prestart()
	match_started.emit()


## Client: the host's RETURN_TO_LOBBY (now, or queued until this peer's own lockstep reached the end of the match).
func _back_to_lobby() -> void:
	_return_pending = false
	_teardown_match()
	_set_phase(Phase.LOBBY)
	_apply_timeouts(NetProtocol.TIMEOUTS_LOBBY)


func _teardown_match() -> void:
	_abandon_tap()
	if _game != null:
		_game.release()
		_game.turn_host = null
		_game.ai_runner = null
		_game.lockstep = null
		_game.desync = null
		_game.adapter = null
	lockstep = null
	turn_host = null
	ai_runner = null
	desync = null
	_flow = null
	_adapter = null
	local_pid = -1


# ---- lockstep hooks -----------------------------------------------------------------------------------------------

func _ls_turn_begin(turn: int, b: NetBundle) -> void:
	if _tap != null:
		_tap.turn(turn, b)
	if _cmd_log != null:
		for gi: int in b.pids.size():
			for c: Variant in b.group_cmds[gi] as Array:
				_cmd_log.record(turn * NetProtocol.TURN_TICKS, b.pids[gi], c as PackedInt32Array)
	if turn_observer.is_valid():
		turn_observer.call(turn, b)


func _ls_checksum(tick: int, checksum: int, chain: int) -> void:
	_last_checksum_tick = tick
	if desync != null:
		desync.local_snapshot(tick, checksum, chain)
	if _cmd_log != null and tick % NetProtocol.CHECKSUM_PERIOD_TICKS == 0:
		_cmd_log.checkpoints.append(tick)
		_cmd_log.checkpoints.append(checksum)
	if _tap != null:
		_tap.check(tick, checksum, chain, _adapter)
	if checksum_observer.is_valid():
		checksum_observer.call(tick, checksum, chain)
	_log(NetProtocol.LogLevel.DEBUG, "chk t=%d sum=%08X chain=%08X" % [tick, checksum, chain])
	if role == Role.CLIENT and local_pid >= 0 and phase != Phase.DESYNCED:
		_send_host(NetCodec.encode_checksum_report({"tick": tick, "checksum": checksum, "input_chain": chain}))
	if _adapter != null and _adapter.is_match_over():
		_client.note_local_final(tick, checksum)


func _ls_send_input_client(turn: int, exec_turn: int, cmds: Array) -> void:
	var msg: PackedByteArray = NetCodec.encode_turn_input({"turn": turn, "exec_turn": exec_turn, "cmds": cmds})
	if msg.is_empty():
		_log(NetProtocol.LogLevel.ERROR, "could not encode TURN_INPUT for turn %d" % turn)
		return
	_send_host(msg)


func _ls_ctrl(_turn: int, c: PackedInt32Array) -> void:
	if _tap != null and c[0] == NetProtocol.CtrlKind.PLAYER_STATUS:
		_tap.status(_turn, c)
	match c[0]:
		NetProtocol.CtrlKind.INPUT_DELAY:
			input_delay_changed.emit(c[1])
		NetProtocol.CtrlKind.PLAYER_STATUS:
			if c[1] >= 0 and c[1] < NetProtocol.MAX_PLAYERS:
				_status[c[1]] = c[2]
			player_status_changed.emit(c[1], c[2])
		NetProtocol.CtrlKind.SPEED:
			speed_changed.emit(c[1])
		NetProtocol.CtrlKind.PAUSE:
			_pause_by = c[1]
		NetProtocol.CtrlKind.MATCH_END:
			_declared_end = c[1]
			_finish_declared()


func _ls_pause(paused: bool) -> void:
	_paused_flag = paused
	if paused:
		_set_phase(Phase.PAUSED)
		pause_changed.emit(true, _pause_by)
	else:
		_set_phase(Phase.PLAYING)
		pause_changed.emit(false, _resume_by)


func _ls_match_over() -> void:
	var res: Dictionary = _adapter.match_result()
	var out: Dictionary = {
		"reason": NetProtocol.MatchEndReason.SIM_DECIDED, "sim_reason": int(res.get("reason", 0)),
		"winner_team": int(res.get("winner_team", -1)), "final_tick": _adapter.current_tick(), "final_checksum": _adapter.checksum_now(),
	}
	_finish_match(out)


## CK_MATCH_END executed: the match ends at this boundary on every peer (host-declared end).
func _finish_declared() -> void:
	if _adapter == null or not _end_result.is_empty():
		return
	var res: Dictionary = _adapter.match_result()
	_finish_match({
		"reason": _declared_end, "sim_reason": int(res.get("reason", 0)), "winner_team": int(res.get("winner_team", -1)),
		"final_tick": _adapter.current_tick(), "final_checksum": _adapter.checksum_now(),
	})


## Starts the replay recording of this match (every role).
func _start_tap(json: String) -> void:
	_tap = NetReplayTap.new()
	_tap.failed.connect(net_error.emit)
	_tap.saved.connect(replay_saved.emit)
	_tap.start(opts, _config, json, local_peer_id, local_pid)


## The match stopped before the sim decided it: close the recording with the state reached so far.
func _abandon_tap(reason: int = NetProtocol.MatchEndReason.ABANDONED) -> void:
	if _tap != null and _adapter != null:
		_tap.abandon(_adapter, lockstep, reason)


func _finish_match(out: Dictionary) -> void:
	if not _end_result.is_empty():
		return
	_end_result = out
	if _tap != null:
		_tap.finish(out, lockstep.input_chain() if lockstep != null else 0)
	if role != Role.CLIENT and lobby != null:
		lobby.set_phase(NetProtocol.LobbyPhase.ENDED)
	if ai_runner != null:
		ai_runner.release_all()
	_set_phase(Phase.ENDED)
	if role == Role.HOST:
		var msg: PackedByteArray = NetCodec.encode_match_end({
			"final_tick": int(out["final_tick"]), "final_checksum": int(out["final_checksum"]), "reason": int(out["reason"]),
			"winner_team": int(out["winner_team"]),
		})
		for k: Variant in _peers:
			var p: NetPeerInfo = _peers[k] as NetPeerInfo
			if p.stage == NetPeerInfo.Stage.PLAYING:
				_send(p.peer_id, msg)
	match_ended.emit(out.duplicate())
	if role == Role.CLIENT:
		_client.note_local_final(int(out["final_tick"]), int(out["final_checksum"]))


# ---- host turn assembly hooks ---------------------------------------------------------------------------------------

# =====================================================================================================================
# desync (sequencing lives in NetDesyncFlow)
# =====================================================================================================================

func _make_flow() -> void:
	_flow = NetDesyncFlow.new()
	_flow.desync = desync
	_flow.local_pid = local_pid
	_flow.host_pid = NetMatchConfig.pid_of_peer(_config, 1)
	_flow.match_id = _match_id
	_flow.send_to_players = _send_to_players
	_flow.send_host = _send_host
	_flow.enter_desynced = _enter_desynced
	_flow.emit_report = _emit_desync_report
	_flow.log_fn = _log
	_flow.context = _desync_context
	_flow.replay_bytes = replay_bytes
	_flow.log_lines = log_lines
	if replay_bytes_provider.is_valid():
		_flow.replay_bytes = replay_bytes_provider


func _host_desync_detected(tick: int, kind: int, entries: Array) -> void:
	_flow.host_detected(tick, kind, entries, clock.now_us())


func _send_to_players(data: PackedByteArray) -> void:
	for k: Variant in _peers:
		var p: NetPeerInfo = _peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.PLAYING:
			_send(p.peer_id, data)


func _enter_desynced() -> void:
	_abandon_tap(NetProtocol.MatchEndReason.DESYNC)
	_set_phase(Phase.DESYNCED)


func _emit_desync_report(report: Dictionary) -> void:
	desync_detected.emit(report)


func _desync_context() -> Dictionary:
	return {
		"peer_id": local_peer_id, "role": "host" if role == Role.HOST else ("client" if role == Role.CLIENT else "local"),
		"versions": (_config.get("versions", {}) as Dictionary).duplicate(),
		"delay": lockstep.delay_turns() if lockstep != null else 0, "rtt_ms": _rtt_map(), "violations": _gate_violations(),
		"dup_in": int(lockstep.stats()["dup_in"]) if lockstep != null else 0, "late_in": int(turn_host.stats()["late_in"]) if turn_host != null else 0,
	}


func _client_desync_notice(data: PackedByteArray, now: int) -> void:
	var d: Dictionary = NetCodec.decode_desync_notice(data)
	if d.is_empty() or desync == null or _flow == null:
		return
	_flow.client_notice(int(d["tick"]), int(d["kind"]), d["entries"] as Array, now)


func _client_parts_request(data: PackedByteArray) -> void:
	var d: Dictionary = NetCodec.decode_parts_request(data)
	if d.is_empty() or desync == null or _flow == null:
		return
	var parts: PackedInt32Array = PackedInt32Array()
	for v: int in d["parts"] as PackedInt64Array:
		parts.append(v)
	_flow.client_parts_request(int(d["tick"]), parts)


func _local_desync(tick: int, kind: int) -> void:
	if _flow != null:
		_flow.local(tick, kind)


func _rtt_map() -> Dictionary:
	var m: Dictionary = {}
	for k: Variant in _peers:
		var p: NetPeerInfo = _peers[k] as NetPeerInfo
		m[str(p.slot)] = p.rtt_ms
	return m


# =====================================================================================================================
# timers
# =====================================================================================================================

func _timers(now: int) -> void:
	match role:
		Role.HOST:
			_host_timers(now)
		Role.CLIENT:
			_client_timers(now)
		Role.LOCAL:
			if turn_host != null and lockstep != null and phase != Phase.ENDED:
				turn_host.evaluate(now)
	if _flow != null:
		_flow.step(now, role == Role.HOST)


func _host_timers(now: int) -> void:
	_gate.expire_handshakes(now)
	if lobby != null and (phase == Phase.LOBBY or phase == Phase.COUNTDOWN):
		lobby.tick(now)
		if now - _last_lobby_ping_us >= 1_000_000:
			_last_lobby_ping_us = now
			var rtt: Dictionary = {}
			for k: Variant in _peers:
				var p2: NetPeerInfo = _peers[k] as NetPeerInfo
				if p2.stage == NetPeerInfo.Stage.LOBBY and transport != null:
					rtt[p2.peer_id] = int(transport.peer_stats(p2.peer_id).rtt_ms)
			lobby.update_pings(rtt)
	if turn_host != null and (phase == Phase.PLAYING or phase == Phase.PAUSED):
		turn_host.evaluate(now)
		if now - _last_ping_us >= NetProtocol.PING_INTERVAL_MS * 1000:
			_last_ping_us = now
			_ping_seq += 1
			var ping: PackedByteArray = NetCodec.encode_ping({"seq": _ping_seq, "host_ms": (now / 1000) & 0xFFFFFFFF})
			for k: Variant in _peers:
				var p3: NetPeerInfo = _peers[k] as NetPeerInfo
				if p3.stage == NetPeerInfo.Stage.PLAYING:
					_send(p3.peer_id, ping)


func _client_timers(now: int) -> void:
	if phase == Phase.CONNECTING and _join != null:
		_join.tick(now)
	if phase == Phase.PLAYING or phase == Phase.PAUSED:
		_client.step(now)


# =====================================================================================================================
# public match API
# =====================================================================================================================

## The SimWorld (read-only for everybody but the adapter); valid from PLAYING on.
func world() -> RefCounted:
	return _adapter.world() if _adapter != null else null


func adapter() -> NetSimAdapter:
	return _adapter


## The normalised MatchConfig (deep copy).
func config() -> Dictionary:
	return _config.duplicate(true)


## Every executed command in order (tick = 2 * turn), for replaying a finished match with SimCommandLog.play().
func command_log() -> SimCommandLog:
	return _cmd_log


## UiCommandBus entry point. false = rejected (not playing, no local player, too long or queue full).
func submit_command(ints: PackedInt32Array) -> bool:
	if (phase != Phase.PLAYING and phase != Phase.PAUSED) or lockstep == null or local_pid < 0:
		_log(NetProtocol.LogLevel.WARN, "submit_command rejected: not playing")
		return false
	return lockstep.submit_local(ints)


func surrender() -> bool:
	return submit_command(PackedInt32Array([NetProtocol.T_RESIGN, NetProtocol.ResignReason.SURRENDER]))


## 0 = sent / applied, else NetProtocol.PauseError.
func request_pause(want_paused: bool) -> int:
	if (phase != Phase.PLAYING and phase != Phase.PAUSED) or local_pid < 0:
		return NetProtocol.PauseError.NOT_PLAYING
	if role == Role.CLIENT:
		_send_host(NetCodec.encode_pause_request({"want_paused": want_paused}))
		return NetProtocol.PauseError.OK
	if turn_host == null:
		return NetProtocol.PauseError.NOT_PLAYING
	return turn_host.request_pause(local_pid, want_paused)


func host_set_speed(speed_pct: int) -> bool:
	if (role != Role.HOST and role != Role.LOCAL) or turn_host == null or not NetProtocol.SPEED_PCT.has(speed_pct):
		_log(NetProtocol.LogLevel.WARN, "host_set_speed rejected")
		return false
	turn_host.set_speed(speed_pct)
	return true


## action: NetProtocol.StallAction. Host only.
func host_resolve_stall(pid: int, action: int) -> void:
	if role != Role.HOST or turn_host == null:
		_log(NetProtocol.LogLevel.WARN, "host_resolve_stall rejected")
		return
	if action == NetProtocol.StallAction.STALL_WAIT:
		turn_host.stall_wait(pid)
		return
	turn_host.drop_player(pid, action, NetProtocol.ResignReason.KICKED)


## Host, phase ENDED (or DESYNCED): everybody back to the lobby with their settings, ready reset.
func host_return_to_lobby() -> void:
	if role != Role.HOST or (phase != Phase.ENDED and phase != Phase.DESYNCED):
		_log(NetProtocol.LogLevel.WARN, "host_return_to_lobby rejected")
		return
	_teardown_match()
	var msg: PackedByteArray = NetLobbyCodec.encode_return_to_lobby()
	for k: Variant in _peers:
		var p: NetPeerInfo = _peers[k] as NetPeerInfo
		if p.stage == NetPeerInfo.Stage.PLAYING:
			p.stage = NetPeerInfo.Stage.LOBBY
			_send(p.peer_id, msg)
	lobby.free_disconnected_slots(_peers)
	_set_phase(Phase.LOBBY)
	_apply_timeouts(NetProtocol.TIMEOUTS_LOBBY)
	lobby.reset_after_match()


## Clean leave: a client sends LEAVE and disconnects; the host closes the game for everybody; LOCAL ends. Ends in IDLE.
func leave() -> void:
	if _in_poll:
		_deferred_leave = 1 if _deferred_leave == 0 else _deferred_leave
		return
	if _shut:
		return
	if role == Role.CLIENT and transport != null and not _got_kicked and phase != Phase.CONNECTING:
		_send_host(NetLobbyCodec.encode_leave({"reason": 0}))
		transport.disconnect_peer(1, 0, true)
		transport.flush()
	shutdown()


## Idempotent. Host: KICKED(HOST_LEFT) to every peer with a graceful disconnect, up to 10 x service(0) so the packets
## leave, then the sockets are destroyed; discovery announces CLOSED.
func shutdown() -> void:
	if _in_poll:
		_deferred_leave = 2
		return
	if _shut:
		return
	_shut = true
	if role == Role.HOST and transport != null:
		var kick: PackedByteArray = NetLobbyCodec.encode_kicked({"reason": NetProtocol.KickReason.HOST_LEFT, "detail": ""})
		for k: Variant in _peers.keys():
			var p: NetPeerInfo = _peers[k] as NetPeerInfo
			if p.stage != NetPeerInfo.Stage.LEFT:
				_send(p.peer_id, kick)
				transport.disconnect_peer(p.peer_id, NetProtocol.KickReason.HOST_LEFT, true)
		for _i: int in 10:
			transport.poll()
			transport.flush()
			if clock.is_manual():
				break
			OS.delay_msec(5)
	_abandon_tap()
	if discovery != null:
		discovery.close()
	if ai_runner != null:
		ai_runner.release_all()
	if transport != null:
		transport.flush()
		transport.close()
	_peers.clear()
	if launch != null:
		launch.reset()
	var prev: int = phase
	phase = Phase.IDLE
	if prev != Phase.IDLE:
		phase_changed.emit(Phase.IDLE, prev)
	lockstep = null
	turn_host = null
	desync = null


## Lobby or match chat (channel 1 = team only). Lines come back through chat_received.
func send_chat(text: String, team_only: bool = false) -> void:
	if lobby != null and phase != Phase.IDLE and phase != Phase.CONNECTING and phase != Phase.DISCONNECTED:
		lobby.send_chat(text, team_only)


## Non-sim UI signal relayed to teammates (PLAYING / PAUSED).
func send_map_ping(cell_x: int, cell_y: int) -> void:
	if (phase != Phase.PLAYING and phase != Phase.PAUSED) or local_pid < 0:
		return
	if role == Role.CLIENT:
		_send_host(NetLobbyCodec.encode_map_ping_c2h({"cell_x": cell_x, "cell_y": cell_y}))
	else:
		_game.relay_ping(local_pid, cell_x, cell_y)


# =====================================================================================================================
# introspection
# =====================================================================================================================

## NetProtocol.PlayerNetStatus of `pid`.
func player_status(pid: int) -> int:
	if pid < 0 or pid >= NetProtocol.MAX_PLAYERS:
		return NetProtocol.PlayerNetStatus.ACTIVE
	if _adapter != null and phase != Phase.IDLE and not _adapter.is_player_active(pid) and _status[pid] == NetProtocol.PlayerNetStatus.ACTIVE:
		return NetProtocol.PlayerNetStatus.DEFEATED
	return _status[pid]


func waiting_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if turn_host != null:
		for w: Dictionary in turn_host.waiting():
			out.append({"pid": int(w["pid"]), "name": _pid_name(int(w["pid"])), "reason": int(w["reason"]), "wait_ms": int(w["wait_ms"])})
		return out
	for w2: Variant in _client.stall_entries:
		out.append(w2 as Dictionary)
	return out


func is_paused() -> bool:
	return _paused_flag


## The recording of this match: the temp file while it runs, autosave_1.mfreplay once it ended; "" when nothing is
## written to disk (opts.record_replay off, or no opts.replay_dir).
func replay_path() -> String:
	return _tap.path() if _tap != null else ""


## The recording as bytes (header + records so far; END + trailer once the match ended; the command-log-lite file when
## opts.record_replay is off). Also what a desync package stores.
func replay_bytes() -> PackedByteArray:
	return _tap.bytes(_config_json, _cmd_log) if _tap != null else PackedByteArray()


## "ip:port" strings to tell friends (private IPv4 first).
func advertised_addresses() -> PackedStringArray:
	return NetDiscovery.advertised_addresses(transport.local_port() if transport != null else 0)


## Total protocol violation points scored (all peers).
func violation_total() -> int:
	return _gate_violations()


func _gate_violations() -> int:
	return _gate.violations_total if _gate != null else 0


## Host: the peer record of a transport peer id (tests / diagnostics), null when unknown.
func peer_info(peer_id: int) -> NetPeerInfo:
	return _peers.get(peer_id) as NetPeerInfo


## Host: number of connections currently tracked (handshaking or joined).
func peer_count() -> int:
	return _peers.size()


## Last log lines (ring of 400).
func log_lines() -> PackedStringArray:
	return _log_ring.duplicate()


## Net overlay numbers (spec 4.7), all keys always present.
func stats() -> Dictionary:
	var ls: Dictionary = lockstep.stats() if lockstep != null else {}
	var rtt: Dictionary = {}
	var jit: Dictionary = {}
	for k: Variant in _peers:
		var p: NetPeerInfo = _peers[k] as NetPeerInfo
		if p.slot >= 0:
			rtt[p.slot] = p.rtt_ms
			jit[p.slot] = p.jitter_ms
	var traffic: PackedInt64Array = transport.pop_traffic() if transport != null else PackedInt64Array([0, 0, 0, 0])
	var th: Dictionary = turn_host.stats() if turn_host != null else {}
	return {
		"role": role, "phase": phase, "tick": int(ls.get("tick", 0)), "turn": int(ls.get("exec_turn", 0)),
		"delay_turns": int(ls.get("delay", 0)), "speed_pct": int(ls.get("speed_pct", 0)), "rtt_ms": rtt, "jitter_ms": jit,
		"stall_ms": int(ls.get("stall_ms_total", 0)), "stall_count": int(ls.get("stall_episodes", 0)), "slack_ms": 0,
		"bundles_buffered": int(ls.get("queued", 0)) + int(ls.get("ooo", 0)), "kbps_in": float(traffic[1]) * 8.0 / 1000.0,
		"kbps_out": float(traffic[0]) * 8.0 / 1000.0, "pkts_in": int(traffic[3]), "pkts_out": int(traffic[2]),
		"load_pct": int(ls.get("step_cost_us", 0)) * 100 / NetProtocol.TICK_US, "dropped_cmds": int(th.get("dropped_cmds", 0)),
		"violations": _gate_violations(), "dup_in": int(ls.get("dup_in", 0)), "late_in": int(th.get("late_in", 0)),
		"ooo_in": int(ls.get("ooo_in", 0)), "ai_us": (ai_runner.stats()["think_us"] as Dictionary) if ai_runner != null else {},
		"chain": int(ls.get("chain", 0)), "last_checksum_tick": _last_checksum_tick,
		"transport": "none" if transport == null else str(transport.get_script().get_global_name()),
	}
