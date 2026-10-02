class_name NetLockstepKit
extends RefCounted
## In-process lockstep rig for net tests: one NetTurnHost and N human peers (pid i, transport peer id i + 1; pid 0 is the
## host's own local player) each with its own NetLockstep + adapter, zero-latency relay, manual clock. Bundles travel
## through the real codec (encode_bundle / decode_bundle). Optional scripted commands (spec 7.6) are submitted when a
## peer has just finished the tick before the boundary that will send them.

class Peer extends RefCounted:
	var pid: int = 0
	var lockstep: NetLockstep = null
	var adapter: NetSimAdapter = null
	## [turn, exec_turn, cmd_count] of every TURN_INPUT the peer produced.
	var sent: Array = []
	## tick -> [checksum, chain]
	var checks: Dictionary = {}
	var final_check: Array = []
	var ctrls: Array = []
	var pauses: Array = []
	var stalls: Array = []
	var over: bool = false
	var ticks: int = 0

var clock: NetClock = NetClock.manual(1_000_000)
var host: NetTurnHost = NetTurnHost.new()
var peers: Array[Peer] = []
var delay: int = 2
var cmd_script: Array = []
var bundles: Array[NetBundle] = []
var _script_done: Dictionary = {}
## Extra commands sink: Callable(peer: Peer, tick: int) -> void called after each frame (tests inject inputs).
var on_frame: Callable = Callable()


func _init(adapters: Array, delay_: int = 2, speed_pct: int = 100, host_cfg: Dictionary = {}) -> void:
	delay = delay_
	var cfg: Dictionary = {"initial_delay": delay_, "fixed_delay": delay_, "speed_pct": speed_pct}
	cfg.merge(host_cfg, true)
	host.setup(clock, cfg)
	for i: int in adapters.size():
		var p: Peer = Peer.new()
		p.pid = i
		p.adapter = adapters[i] as NetSimAdapter
		var ls: NetLockstep = NetLockstep.new()
		ls.setup(p.adapter, clock, i, delay_, speed_pct)
		ls.on_send_input = func(turn: int, exec_turn: int, cmds: Array) -> void:
			p.sent.append([turn, exec_turn, cmds.size()])
			host.on_input(p.pid, turn, exec_turn, cmds)
		ls.on_checksum = func(tick: int, cs: int, chain: int) -> void:
			p.checks[tick] = [cs, chain]
			if p.adapter.is_match_over():
				p.final_check = [tick, cs, chain]
		ls.on_ctrl = func(turn: int, c: PackedInt32Array) -> void:
			p.ctrls.append([turn, c])
		ls.on_pause = func(paused: bool) -> void:
			p.pauses.append(paused)
		ls.on_stall_changed = func(stalled: bool, ms: int) -> void:
			p.stalls.append([stalled, ms])
		ls.on_match_over = func() -> void:
			p.over = true
		if i == 0:
			ls.on_boundary = func(_turn: int, target: int) -> void:
				host.note_injection_through(target)
		p.lockstep = ls
		peers.append(p)
		host.set_player(i, NetProtocol.PlayerRole.PR_HUMAN, i + 1)
	for p: Peer in peers:
		p.lockstep.start()


## Relay closed bundles to every peer through the codec.
func pump() -> void:
	for b: NetBundle in host.close_ready():
		bundles.append(b)
		var got: NetBundle = NetCodec.decode_bundle(b.wire_bytes())
		for p: Peer in peers:
			p.lockstep.push_bundle(got)


## Advances the clock by dt_us and runs one poll of every peer (session poll order: relay, update, relay).
func frame(dt_us: int = NetProtocol.TICK_US) -> int:
	clock.advance_us(dt_us)
	pump()
	var n: int = 0
	for p: Peer in peers:
		var t: int = p.lockstep.update()
		p.ticks += t
		n = maxi(n, t)
		_run_script(p)
		if on_frame.is_valid():
			on_frame.call(p, p.lockstep.current_tick())
	pump()
	return n


## Frames of dt_us until every peer reached `tick` (or max_frames elapsed). Returns the frames used.
func run_to(tick: int, dt_us: int = NetProtocol.TICK_US, max_frames: int = 100000) -> int:
	var f: int = 0
	while f < max_frames:
		var all: bool = true
		for p: Peer in peers:
			if p.lockstep.current_tick() < tick and not p.lockstep.is_over():
				all = false
		if all:
			break
		frame(dt_us)
		f += 1
	return f


func _run_script(p: Peer) -> void:
	for i: int in cmd_script.size():
		var e: Dictionary = cmd_script[i] as Dictionary
		if int(e["pid"]) != p.pid or _script_done.has(i):
			continue
		var when: int = 2 * (int(e["turn"]) - delay - 1) + 1
		if p.lockstep.current_tick() >= when:
			_script_done[i] = true
			p.lockstep.submit_local(e["ints"] as PackedInt32Array)


## The spec 7.6 script S0 (execution turns).
static func script_s0() -> Array:
	return [
		{"turn": 5, "pid": 0, "ints": PackedInt32Array([1, 2, 3])},
		{"turn": 7, "pid": 1, "ints": PackedInt32Array([9])},
		{"turn": 12, "pid": 0, "ints": PackedInt32Array([4, -5, 262144])},
		{"turn": 12, "pid": 1, "ints": PackedInt32Array([7, 7])},
		{"turn": 12, "pid": 1, "ints": PackedInt32Array([8])},
	]


static func fakes(n: int, map_seed: int = 0) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(NetSimAdapterFake.new(map_seed))
	return out
