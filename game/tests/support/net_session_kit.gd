class_name NetSessionKit
extends RefCounted
## Test rig for NetSession: loopback hub with a manual clock, N sessions polled in lock step, fake or real worlds, a
## raw endpoint for hostile-peer tests. Everything runs in virtual time (no sockets, no sleeping).

const DATA_HASH: int = 0x1234ABCD

var hub: NetLoopbackHub = NetLoopbackHub.new(NetClock.manual(1_000_000))
var sessions: Array[NetSession] = []
var log_lines: PackedStringArray = PackedStringArray()
var log_errors: PackedStringArray = PackedStringArray()
var desync_dir: String = "user://desync_test_%d" % OS.get_process_id()
var _next_key: int = 1
## Per-session-tag world builders (tag = player name); default builds a NetSimAdapterFake.
var builders: Dictionary = {}
var ai_factory: Callable = Callable()


func clock() -> NetClock:
	return hub.clock


static func roster_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for fac: String in ["ae", "def", "han", "napc", "nec", "olm", "pd", "sap"]:
		for sub: String in ["vanilla", "a", "b", "c"]:
			out.append("roster.%s.%s" % [fac, sub])
	out.sort()
	return out


func _endpoint() -> NetTransport:
	var key: int = _next_key
	_next_key += 1
	var ep: NetTransportLoopback = hub.endpoint(key)
	ep.address = "10.0.0.%d" % key
	return ep


func options(player_name: String, extra: Dictionary = {}) -> NetSessionOptions:
	var o: NetSessionOptions = NetSessionOptions.new()
	o.player_name = player_name
	o.game_version = "0.0.1"
	o.sim_version = 1
	o.data_hash = DATA_HASH
	o.roster_ids = roster_ids()
	o.clock = hub.clock
	o.discovery_enabled = false
	o.transport_factory = _endpoint
	o.fixed_input_delay_turns = 2
	o.speed_pct_override = 0
	o.max_ticks_per_poll = 64
	o.countdown_s = 0
	o.desync_dir = desync_dir
	o.match_seed_override = 0x1234
	o.unix_time_override = 1_790_000_000
	o.ai_factory = ai_factory
	o.log_sink = func(level: int, text: String) -> void:
		log_lines.append(text)
		if level >= NetProtocol.LogLevel.ERROR:
			log_errors.append(text)
	o.world_builder = func(cfg: Dictionary) -> NetWorldJob:
		var b: Callable = builders.get(player_name, Callable()) as Callable
		if b.is_valid():
			return b.call(cfg) as NetWorldJob
		return fake_job(cfg)
	for k: Variant in extra:
		o.set(str(k), extra[k])
	return o


static func fake_job(cfg: Dictionary) -> NetWorldJob:
	var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
	return NetWorldJob.sync(func() -> NetSimAdapter: return NetSimAdapterFake.new(seed_v))


func add(s: NetSession) -> NetSession:
	if s != null:
		sessions.append(s)
	return s


func host(name: String = "Host", extra: Dictionary = {}) -> NetSession:
	return add(NetSession.host(options(name, extra), name + "'s game"))


func join(name: String, extra: Dictionary = {}, port: int = NetProtocol.DEFAULT_PORT) -> NetSession:
	return add(NetSession.join(options(name, extra), "10.0.0.1", port))


## One frame: advance the clock, poll every live session.
func step(n: int = 1, dt_us: int = 50_000) -> int:
	var ticks: int = 0
	for _i: int in n:
		hub.clock.advance_us(dt_us)
		for s: NetSession in sessions:
			ticks += s.poll()
	return ticks


func run_until(pred: Callable, max_steps: int = 400, dt_us: int = 50_000) -> bool:
	for _i: int in max_steps:
		if pred.call():
			return true
		step(1, dt_us)
	return pred.call()


## Steps until every session reaches the phase (false on timeout).
func all_in(phase: int, max_steps: int = 400) -> bool:
	return run_until(func() -> bool:
		for s: NetSession in sessions:
			if s.phase != phase:
				return false
		return true, max_steps)


## Host + `n` joined clients sitting in the lobby, host has 1 extra slot per client.
func lobby_of(n_clients: int, host_extra: Dictionary = {}, client_extra: Dictionary = {}) -> NetSession:
	var h: NetSession = host("Host", host_extra)
	for i: int in n_clients:
		join("P%d" % (i + 2), client_extra)
	all_in(NetSession.Phase.LOBBY, 100)
	return h


func shutdown_all() -> void:
	for s: NetSession in sessions:
		s.shutdown()
	sessions.clear()
	# remove the test desync packages
	var d: DirAccess = DirAccess.open(desync_dir)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(desync_dir)


## A hostile peer: a bare transport endpoint connected to the host (no session). Returns [endpoint, events sink].
func raw_peer(address: String = "", connect_data: int = -1) -> NetTransportLoopback:
	var ep: NetTransportLoopback = hub.endpoint(_next_key)
	ep.address = address if address != "" else "10.0.0.%d" % _next_key
	_next_key += 1
	ep.connect_to("10.0.0.1", NetProtocol.DEFAULT_PORT, NetProtocol.connect_data() if connect_data < 0 else connect_data)
	ep.poll()
	return ep


## Delivers and returns every packet a raw endpoint received since the last call.
func raw_take(ep: NetTransportLoopback) -> Array[NetTransportEvent]:
	ep.poll()
	return ep.take_events()


## The real world builder: MapGenerator + SimMatchSetup.create_world for a net MatchConfig (used by the LOCAL parity tests).
static func real_job(cfg: Dictionary) -> NetWorldJob:
	return NetWorldJob.sync(func() -> NetSimAdapter:
		var data: GameData = SimMatchKit.data()
		var mcfg: Dictionary = cfg["map"] as Dictionary
		var key: Dictionary = {"family": int(mcfg["family"]), "seed": int(mcfg["seed"]), "layout_players": int(mcfg["layout_players"]), "size": int(mcfg["size"]), "params": {}}
		var m: MapData = MapGenerator.generate(key)
		SimMatchSetup.register_map_defs(m, data)
		var w: SimWorld = SimMatchSetup.create_world(data, SimMatchConfig.from_dict(cfg), m, {})
		return NetSimAdapterWorld.new(w))


## Captures SimBot commands instead of applying them (the net AI thinker contract: append to `out`).
class CaptureLog extends SimCommandLog:
	var out: Array = []

	func submit(_world: SimWorld, _pid: int, ints: PackedInt32Array) -> void:
		out.append(ints)


## ai_factory built on the test bot: (pid, level, style, seed) -> Callable(world, out).
static func bot_factory(bot_opts: Dictionary = {}) -> Callable:
	return func(pid: int, _level: int, _style: int, _seed: int) -> Callable:
		var cap: CaptureLog = CaptureLog.new()
		var bot: SimBot = SimBot.new(pid, bot_opts.duplicate())
		bot.cmd_log = cap
		return func(world: RefCounted, out: Array) -> void:
			cap.out = out
			bot.think(world as SimWorld)
