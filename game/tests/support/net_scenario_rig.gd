class_name NetScenarioRig
extends RefCounted
## NET-11 scenario rig (docs/spec/net.md 10.4): a host plus N clients as real NetSessions on one loopback hub, every
## endpoint wrapped in a NetTransportFault, all in virtual time. The master clock is the "real world"; every session has
## its own manual clock that advances by dt scaled with the session's drift (ppm), so S6 can skew the peers.
## Measures what the scenarios assert: ticks, input delay, stalls, command latency (submit -> executed), wire bytes,
## checksum-chain agreement. The default world is NetSimAdapterFake; `real` builds a SimWorld through SimMatchSetup.

const DATA_HASH: int = 0x1234ABCD
const MARK: int = 20  ## command type of the measured random commands: [MARK, pid, seq, random]

class RigPeer extends RefCounted:
	var name: String = ""
	var session: NetSession = null
	var clock: NetClock = null
	var fault: NetTransportFault = null
	var drift_ppm: int = 0
	var frozen_until_us: int = 0  ## master clock time until which the process is suspended (0 = running)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var next_cmd_us: int = 0
	var seq: int = 0
	var submit_us: Dictionary = {}  ## seq -> master time of submit
	var lat_us: PackedInt64Array = PackedInt64Array()
	var checks: Dictionary = {}  ## tick -> [checksum, chain]
	var bytes_out: int = 0
	var bytes_in: int = 0
	var delay_changes: Array = []  ## [master_us, turns]
	var pauses: Array = []  ## [paused, by_pid]
	var errors: Array = []  ## [code, text]
	var desyncs: Array = []
	var status_changes: Array = []  ## [pid, status]
	var stall_signals: int = 0
	var cmd_rate_ms: int = 250
	var active: bool = true  ## submits random commands while playing

var master: NetClock = NetClock.manual(1_000_000)
var hub: NetLoopbackHub = NetLoopbackHub.new(master)
var nodes: Array[RigPeer] = []
var dt_us: int = 16_667
var profile: NetFaultProfile = NetFaultProfile.preset("lan")
var seed_base: int = 7
var real: bool = false
var fixed_delay: int = 0
var speed_pct: int = 100
var ai_factory: Callable = Callable()
var desync_dir: String = "user://desync_scn_%d" % OS.get_process_id()
var max_ticks_per_poll: int = NetProtocol.MAX_TICKS_PER_POLL
var extra_opts: Dictionary = {}
var builders: Dictionary = {}  ## node name -> Callable(cfg) -> NetWorldJob
var match_start_us: int = 0
## Scenario scratch: host tick when a stalled player was dropped.
var tick_at_drop: int = 0
var _next_key: int = 1


func _init(profile_: NetFaultProfile = null) -> void:
	if profile_ != null:
		profile = profile_


static func roster_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for fac: String in ["ae", "def", "han", "napc", "nec", "olm", "pd", "sap"]:
		for sub: String in ["vanilla", "a", "b", "c"]:
			out.append("roster.%s.%s" % [fac, sub])
	out.sort()
	return out


func _options(nd: RigPeer) -> NetSessionOptions:
	var o: NetSessionOptions = NetSessionOptions.new()
	o.player_name = nd.name
	o.game_version = "0.0.1"
	o.sim_version = 1
	o.data_hash = DATA_HASH
	o.roster_ids = roster_ids()
	o.clock = nd.clock
	o.discovery_enabled = false
	o.countdown_s = 0
	o.desync_dir = desync_dir
	o.match_seed_override = 0x1234
	o.unix_time_override = 1_790_000_000
	o.speed_pct_override = speed_pct
	o.fixed_input_delay_turns = fixed_delay
	o.max_ticks_per_poll = max_ticks_per_poll
	o.ai_factory = ai_factory
	o.transport_factory = func() -> NetTransport:
		var key: int = _next_key
		_next_key += 1
		var ep: NetTransportLoopback = hub.endpoint(key)
		ep.address = "10.0.0.%d" % key
		nd.fault = NetTransportFault.wrap(ep, profile.duplicate_profile(), master, seed_base * 1000 + key)
		return nd.fault
	o.log_sink = func(_level: int, _text: String) -> void: pass
	o.world_builder = func(cfg: Dictionary) -> NetWorldJob:
		var b: Callable = builders.get(nd.name, Callable()) as Callable
		if b.is_valid():
			return b.call(cfg) as NetWorldJob
		return real_job(cfg) if real else fake_job(cfg)
	for k: Variant in extra_opts:
		o.set(str(k), extra_opts[k])
	return o


static func fake_job(cfg: Dictionary) -> NetWorldJob:
	var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
	return NetWorldJob.sync(func() -> NetSimAdapter: return NetSimAdapterFake.new(seed_v))


static func real_job(cfg: Dictionary) -> NetWorldJob:
	return NetSessionKit.real_job(cfg)


func _new_node(name: String, drift_ppm: int) -> RigPeer:
	var nd: RigPeer = RigPeer.new()
	nd.name = name
	nd.clock = NetClock.manual(master.now_us())
	nd.drift_ppm = drift_ppm
	nd.rng.seed = seed_base * 7919 + nodes.size() * 104729 + 1
	nodes.append(nd)
	return nd


func _hook(nd: RigPeer) -> void:
	var s: NetSession = nd.session
	s.checksum_observer = func(tick: int, cs: int, ch: int) -> void: nd.checks[tick] = [cs, ch]
	s.turn_observer = func(_turn: int, b: NetBundle) -> void:
		var pid: int = s.local_pid
		for gi: int in b.pids.size():
			if b.pids[gi] != pid:
				continue
			for c: Variant in b.group_cmds[gi] as Array:
				var ints: PackedInt32Array = c as PackedInt32Array
				if ints.size() >= 3 and ints[0] == MARK and nd.submit_us.has(ints[2]):
					nd.lat_us.append(master.now_us() - int(nd.submit_us[ints[2]]))
					nd.submit_us.erase(ints[2])
	s.input_delay_changed.connect(func(turns: int) -> void: nd.delay_changes.append([master.now_us(), turns]))
	s.pause_changed.connect(func(p: bool, by: int) -> void: nd.pauses.append([p, by]))
	s.net_error.connect(func(code: int, text: String) -> void: nd.errors.append([code, text]))
	s.desync_detected.connect(func(report: Dictionary) -> void: nd.desyncs.append(report))
	s.player_status_changed.connect(func(pid: int, st: int) -> void: nd.status_changes.append([pid, st]))


## Creates the host ("Host") and `n_clients` clients ("P2".."Pn"), waits for the lobby, readies everybody and starts
## the launch. Returns true when every session is PLAYING. drift_ppm: per node (host first), missing = 0.
func launch(n_clients: int, drifts: Array = [], ai_slots: int = 0, layout: int = 0) -> bool:
	var h: RigPeer = _new_node("Host", int(drifts[0]) if drifts.size() > 0 else 0)
	h.session = NetSession.host(_options(h), "scenario")
	if h.session == null:
		return false
	if layout > 0:
		h.session.lobby.host_set_map(0, 128, 7, layout)
	_hook(h)
	for i: int in n_clients:
		var c: RigPeer = _new_node("P%d" % (i + 2), int(drifts[i + 1]) if drifts.size() > i + 1 else 0)
		c.session = NetSession.join(_options(c), "10.0.0.1", NetProtocol.DEFAULT_PORT)
		if c.session == null:
			return false
		_hook(c)
	if not run_until(func() -> bool: return _all_in(NetSession.Phase.LOBBY), 800):
		return false
	var hs: NetSession = h.session
	for i: int in ai_slots:
		hs.lobby.host_set_slot_kind(1 + n_clients + i, NetProtocol.SlotKind.AI)
	for nd: RigPeer in nodes:
		nd.session.lobby.set_team(1 + nodes.find(nd) % 4)
	frames(20)
	for nd: RigPeer in nodes:
		if nd != h:
			nd.session.lobby.set_ready(true)
	frames(20)
	if hs.lobby.host_start() != NetLobby.StartError.OK:
		return false
	if not run_until(func() -> bool: return _all_in(NetSession.Phase.PLAYING), 6000):
		return false
	match_start_us = master.now_us()
	for nd: RigPeer in nodes:
		nd.next_cmd_us = master.now_us() + 100_000
		nd.bytes_out = 0
		nd.bytes_in = 0
	return true


func _all_in(phase: int) -> bool:
	for nd: RigPeer in nodes:
		if nd.session.phase != phase:
			return false
	return true


## One frame: advance the master clock and every session clock, feed random commands, poll everyone that is running.
func frame() -> void:
	master.advance_us(dt_us)
	for nd: RigPeer in nodes:
		nd.clock.advance_us(dt_us + dt_us * nd.drift_ppm / 1_000_000)
	var now: int = master.now_us()
	for nd: RigPeer in nodes:
		var s: NetSession = nd.session
		if s == null or s.phase == NetSession.Phase.IDLE:
			continue
		if nd.frozen_until_us > now:
			continue
		if nd.active and s.phase == NetSession.Phase.PLAYING and s.local_pid >= 0 and now >= nd.next_cmd_us:
			nd.next_cmd_us = now + nd.cmd_rate_ms * 1000 + nd.rng.randi_range(0, 100_000)
			nd.seq += 1
			if s.submit_command(PackedInt32Array([MARK, s.local_pid, nd.seq, nd.rng.randi_range(0, 9999)])):
				nd.submit_us[nd.seq] = now
		s.poll()
		if s.transport != null:
			var traffic: PackedInt64Array = s.transport.pop_traffic()
			nd.bytes_out += traffic[0]
			nd.bytes_in += traffic[1]


func frames(n: int) -> void:
	for _i: int in n:
		frame()


func run_until(pred: Callable, max_frames: int) -> bool:
	for _i: int in max_frames:
		if pred.call():
			return true
		frame()
	return pred.call()


## Runs `seconds` of virtual time.
func run_seconds(seconds: float) -> void:
	frames(int(seconds * 1_000_000.0 / float(dt_us)))


## Seconds of virtual time since the match started.
func match_seconds() -> float:
	return float(master.now_us() - match_start_us) / 1_000_000.0


func freeze(idx: int, ms: int) -> void:
	nodes[idx].frozen_until_us = master.now_us() + ms * 1000


func host() -> NetSession:
	return nodes[0].session


func sess(idx: int) -> NetSession:
	return nodes[idx].session


func ticks() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for nd: RigPeer in nodes:
		var a: NetSimAdapter = nd.session.adapter()
		out.append(a.current_tick() if a != null else -1)
	return out


## Number of checksum ticks on which two live nodes disagree (checksum or input chain), plus DESYNCED sessions.
func mismatches() -> int:
	var bad: int = 0
	for nd: RigPeer in nodes:
		if nd.session.phase == NetSession.Phase.DESYNCED:
			bad += 1
	var ref: RigPeer = nodes[0]
	for k: Variant in ref.checks:
		for nd: RigPeer in nodes:
			if nd != ref and nd.checks.has(k) and nd.checks[k] != ref.checks[k]:
				bad += 1
	return bad


func checks_compared() -> int:
	var n: int = 0
	for k: Variant in nodes[0].checks:
		if nodes[1].checks.has(k):
			n += 1
	return n


static func percentile(arr: PackedInt64Array, p: float) -> int:
	if arr.is_empty():
		return 0
	var c: PackedInt64Array = arr.duplicate()
	c.sort()
	return c[clampi(int(ceil(p * c.size())) - 1, 0, c.size() - 1)]


## Latency (ms) over the clients' commands: {avg, p95, max, n}.
func latency_ms(include_host: bool = true) -> Dictionary:
	var all: PackedInt64Array = PackedInt64Array()
	for nd: RigPeer in nodes:
		if nd == nodes[0] and not include_host:
			continue
		all.append_array(nd.lat_us)
	var sum: int = 0
	for v: int in all:
		sum += v
	return {"avg": float(sum) / maxf(1.0, float(all.size())) / 1000.0, "p95": float(percentile(all, 0.95)) / 1000.0,
		"max": float(percentile(all, 1.0)) / 1000.0, "n": all.size()}


## Sum over the clients of the stall totals (ms) and episode count, as seen by their lockstep.
func client_stalls() -> Dictionary:
	var ms: int = 0
	var n: int = 0
	for i: int in range(1, nodes.size()):
		var st: Dictionary = nodes[i].session.stats()
		ms += int(st["stall_ms"])
		n += int(st["stall_count"])
	return {"ms": ms, "count": n}


## Average wire rate (bytes/s, out) of the host and the mean over the clients, over `seconds` of play.
func wire_bytes_per_s(seconds: float) -> Dictionary:
	var client_sum: float = 0.0
	for i: int in range(1, nodes.size()):
		client_sum += float(nodes[i].bytes_out)
	var n_cl: int = maxi(1, nodes.size() - 1)
	return {"host_out": float(nodes[0].bytes_out) / seconds, "client_out": client_sum / float(n_cl) / seconds,
		"total": (float(nodes[0].bytes_out) + client_sum) / seconds}


func shutdown() -> void:
	for nd: RigPeer in nodes:
		if nd.session != null:
			nd.session.shutdown()
	var d: DirAccess = DirAccess.open(desync_dir)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(desync_dir)
	nodes.clear()
