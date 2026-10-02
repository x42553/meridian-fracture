class_name NetAiRunner
extends RefCounted
## Host-side AI hookup (docs/spec/net.md 5.6). net never depends on ai/: the AI arrives through an injected
## factory `(pid, level, style, rng_seed) -> Callable thinker`, `thinker.call(world: RefCounted, out: Array)` appends
## PackedInt32Array commands to `out`. The runner only decides WHEN each AI thinks and sanitises what it returns; the
## commands then travel to every peer through the bundle of the target turn, so playback never needs the AI.
##
## Cadence: an AI thinks at boundary E when (E + pid) % period(pid) == 0 (period = think_period(level), default 5).
## CPU governor (paced sessions): the total think time per boundary is capped at AI_BOUNDARY_BUDGET_US; the due
## thinkers that did not fit become overdue and run first (pid order) at the next boundary. A thinker that needs more
## than SLOW_THINK_US twice in a row has its period doubled (max MAX_PERIOD). Unpaced runs disable the governor.

const SLOW_THINK_US: int = 12000
const MAX_PERIOD: int = 20
const MAX_CMD_BYTES: int = 6144

## Turns between thinks when no think_period callable is supplied.
var think_period_turns: int = NetProtocol.AI_THINK_PERIOD_TURNS
## Test hook: () -> int microseconds (default Time.get_ticks_usec).
var time_source: Callable = Callable()

class _Ai extends RefCounted:
	var thinker: Callable = Callable()
	var level: int = 0
	var style: int = 0
	var period: int = 5
	var overdue: bool = false
	var slow_streak: int = 0
	var last_us: int = 0


var _factory: Callable = Callable()
var _base_seed: int = 0
var _period_of: Callable = Callable()
var _release: Callable = Callable()
var _governor: bool = true
var _ais: Dictionary = {}
var _dropped_cmds: int = 0
var _think_us: Dictionary = {}


## think_period: (level: int) -> int turns (optional); release: (pid: int) -> void (optional).
func setup(ai_factory: Callable, base_seed: int, think_period: Callable = Callable(), release: Callable = Callable(), governor: bool = true) -> void:
	_factory = ai_factory
	_base_seed = base_seed & 0xFFFFFFFF
	_period_of = think_period
	_release = release
	_governor = governor


func set_governor(enabled: bool) -> void:
	_governor = enabled


## Private RNG seed of the thinker of `pid`: mix32(base_seed ^ ((pid + 1) * 0x9E3779B9)) (never the sim RNG).
func seed_of(pid: int) -> int:
	return NetProtocol.mix32(_base_seed ^ (((pid + 1) * 0x9E3779B9) & 0xFFFFFFFF))


## Creates the thinker via ai_factory(pid, level, style, seed). Returns false when the factory gave no valid Callable.
func add_ai(pid: int, level: int, style: int) -> bool:
	if pid < 0 or pid >= NetProtocol.MAX_PLAYERS or not _factory.is_valid():
		return false
	if _ais.has(pid):
		remove_ai(pid)
	var th: Variant = _factory.call(pid, level, style, seed_of(pid))
	if not (th is Callable) or not (th as Callable).is_valid():
		return false
	var a: _Ai = _Ai.new()
	a.thinker = th as Callable
	a.level = level
	a.style = style
	a.period = maxi(1, int(_period_of.call(level))) if _period_of.is_valid() else maxi(1, think_period_turns)
	_ais[pid] = a
	return true


func remove_ai(pid: int) -> void:
	if not _ais.has(pid):
		return
	_ais.erase(pid)
	_think_us.erase(pid)
	if _release.is_valid():
		_release.call(pid)


## Releases every thinker (match end).
func release_all() -> void:
	for pid: int in ai_pids():
		remove_ai(pid)


func has_ai(pid: int) -> bool:
	return _ais.has(pid)


func ai_pids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array(_ais.keys())
	out.sort()
	return out


func period_of(pid: int) -> int:
	return (_ais[pid] as _Ai).period if _ais.has(pid) else 0


func is_overdue(pid: int) -> bool:
	return _ais.has(pid) and (_ais[pid] as _Ai).overdue


func _now_us() -> int:
	return int(time_source.call()) if time_source.is_valid() else Time.get_ticks_usec()


## Appends [pid: int, cmds: Array[PackedInt32Array]] in ascending pid order for every AI that thinks at boundary
## `exec_turn` (the target turn is the caller's E + D).
func produce(exec_turn: int, _target_turn: int, sim: NetSimAdapter, out_groups: Array) -> void:
	var order: PackedInt32Array = PackedInt32Array()
	var pids: PackedInt32Array = ai_pids()
	for pid: int in pids:
		if (_ais[pid] as _Ai).overdue:
			order.append(pid)
	for pid: int in pids:
		var a: _Ai = _ais[pid] as _Ai
		if not a.overdue and (exec_turn + pid) % a.period == 0:
			order.append(pid)
	var results: Dictionary = {}
	var spent_us: int = 0
	var out_of_budget: bool = false
	for pid: int in order:
		var a: _Ai = _ais[pid] as _Ai
		if out_of_budget:
			a.overdue = true
			continue
		a.overdue = false
		if not sim.is_player_active(pid):
			continue
		var cmds: Array = []
		var t0: int = _now_us()
		a.thinker.call(sim.world(), cmds)
		var dt: int = maxi(_now_us() - t0, 0)
		a.last_us = dt
		_think_us[pid] = dt
		spent_us += dt
		results[pid] = _sanitise(cmds)
		if _governor:
			_track_slow(pid, a, dt)
			if spent_us >= NetProtocol.AI_BOUNDARY_BUDGET_US:
				out_of_budget = true
	var got: PackedInt32Array = PackedInt32Array(results.keys())
	got.sort()
	for pid: int in got:
		out_groups.append([pid, results[pid]])


func _track_slow(pid: int, a: _Ai, dt: int) -> void:
	if dt > SLOW_THINK_US:
		a.slow_streak += 1
		if a.slow_streak >= 2 and a.period < MAX_PERIOD:
			a.period = mini(a.period * 2, MAX_PERIOD)
			a.slow_streak = 0
			Log.warn("net.ai", "AI pid %d needs %d us per think; period raised to %d turns" % [pid, dt, a.period])
	else:
		a.slow_streak = 0


## Keeps well-formed commands only (size 1..1024, type 0..255), at most AI_MAX_CMDS_PER_THINK and MAX_CMD_BYTES encoded.
func _sanitise(cmds: Array) -> Array:
	var out: Array = []
	var bytes: int = 10
	for c: Variant in cmds:
		if not (c is PackedInt32Array):
			_dropped_cmds += 1
			continue
		var a: PackedInt32Array = c as PackedInt32Array
		if a.is_empty() or a.size() > NetProtocol.MAX_CMD_INTS or a[0] < 0 or a[0] > 255:
			_dropped_cmds += 1
			continue
		var sz: int = NetLockstep._cmd_bytes(a)
		if out.size() >= NetProtocol.AI_MAX_CMDS_PER_THINK or bytes + sz > MAX_CMD_BYTES:
			_dropped_cmds += 1
			continue
		bytes += sz
		out.append(a)
	return out


func stats() -> Dictionary:
	return {"think_us": _think_us.duplicate(), "dropped_cmds": _dropped_cmds}
