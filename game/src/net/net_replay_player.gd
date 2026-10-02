class_name NetReplayPlayer
extends RefCounted
## Deterministic playback of a recorded match (docs/spec/net.md 3.7, 5.8): the world is rebuilt from the recorded config
## through the same NetWorldJob path as a live match and re-simulated from tick 0, feeding the recorded commands at the
## recorded turns. The input chain is rebuilt from the turn stream and every recorded CHECK (checksum + chain) is compared
## after the tick it names; the first mismatch emits verify_failed once ("replay-desync") and playback continues.
##
## Seeking forward fast-forwards; seeking backward rebuilds the world and re-simulates from tick 0 (there is no mid-game
## snapshot restore in the sim, spec sim_core 11), time-sliced by poll(budget_us). While the new world is built the old
## one stays readable and frozen (adapter()); world_rebuilt fires when the new one replaces it.

const SPEEDS: PackedFloat32Array = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
## set_speed(MAX): unbounded, time-sliced by the poll budget.
const MAX: float = 0.0
const CHAIN_BASIS: int = 0x811C9DC5
const MAX_CATCHUP_US: int = 250_000
const _MASK: int = 0xFFFFFFFF
const _EMPTY_BODY: PackedByteArray = [0]

## First mismatch of a run (checksum, or input chain when only that differs): tick, expected, actual.
signal verify_failed(tick: int, expected: int, actual: int)
## The recorded end was reached (or the sim ended the match).
signal finished()
## The world was rebuilt (backward seek): adapter() now returns the new one; re-attach views.
signal world_rebuilt()

## Set when setup() fails (version gate, corrupt data, world build error).
var error_text: String = ""
## true: any versions.* difference refuses (tests, verify_file, golden replays).
var strict: bool = false
## Developer override of the whole version gate.
var allow_version_mismatch: bool = false
## Set when playback is allowed despite a data_hash difference ("balance changed since recording").
var warning: String = ""
## The versions of this build for the gate (NetReplay.local_versions(opts)); {} = no gate.
var local_versions: Dictionary = {}
## Clear the world's event buffer after every tick (headless runs without a view). Seeks always do.
var auto_clear_events: bool = false

var _data: NetReplayData = null
var _builder: Callable = Callable()
var _clock: NetClock = null
var _adapter: NetSimAdapter = null
var _job: NetWorldJob = null
var _loading: bool = false
var _build_failed: bool = false
var _pending_seek: int = -1
var _generation: int = 0
var _tick: int = 0
var _chain: int = CHAIN_BASIS
var _ti: int = 0
var _ci: int = 0
var _acc_us: int = 0
var _last_us: int = 0
var _speed: float = 1.0
var _paused: bool = false
var _target: int = -1
var _finished: bool = false
var _end_tick: int = 0
var _verified: int = 0
var _compared: int = 0
var _diverged: int = -1
var _reported: bool = false
var _mismatch: Dictionary = {}
var _tb: PackedByteArray = PackedByteArray([0, 0, 0, 0])


## Validates the replay (version gate) and builds the world through `world_builder(config) -> NetWorldJob`. With
## `sync` = false only the job is created: keep calling poll() until is_loading() is false (progress via
## load_progress_pct()). Returns OK or ERR_INVALID_DATA (version / data) / ERR_CANT_CREATE (the world could not be built);
## error_text says why.
func setup(data: NetReplayData, world_builder: Callable, clock: NetClock, sync: bool = true) -> int:
	error_text = ""
	warning = ""
	if data == null:
		error_text = "no replay data"
		return ERR_INVALID_DATA
	if not world_builder.is_valid():
		error_text = "no world builder"
		return ERR_UNCONFIGURED
	_data = data
	_builder = world_builder
	_clock = clock if clock != null else NetClock.real()
	if not allow_version_mismatch:
		var gate: Dictionary = NetReplay.check_versions(data.versions(), local_versions, strict)
		match int(gate["level"]):
			NetReplay.GATE_REFUSE:
				error_text = str(gate["text"])
				return ERR_INVALID_DATA
			NetReplay.GATE_WARN:
				warning = str(gate["text"])
	_end_tick = data.end_tick()
	_reset_run()
	if not _start_build():
		return ERR_CANT_CREATE
	_pending_seek = -1
	if sync:
		var guard: int = 0
		while _loading and guard < 1_000_000:
			guard += 1
			_advance_build(1_000_000)
		if _build_failed or _adapter == null:
			return ERR_CANT_CREATE
	return OK


# ---- state -----------------------------------------------------------------------------------------------------------

## The current world's adapter (null before the first build finished). Replaced by a backward seek (world_rebuilt).
func adapter() -> NetSimAdapter:
	return _adapter


func replay() -> NetReplayData:
	return _data


func current_tick() -> int:
	return _tick


func end_tick() -> int:
	return _end_tick


## 0..1 of the replay (current tick / end tick).
func progress() -> float:
	return clampf(float(_tick) / float(maxi(_end_tick, 1)), 0.0, 1.0)


## 0..1 through the current tick for render interpolation (paced playback only; 1 while paused, finished, seeking or at MAX speed).
func tick_alpha() -> float:
	if _paused or _finished or _target >= 0 or _loading or _speed <= 0.0:
		return 1.0
	return clampf(float(_acc_us) / float(NetProtocol.TICK_US), 0.0, 1.0)


## true while a seek is running (fast-forward, or rebuilding + re-simulating) or the world is still being built.
func is_seeking() -> bool:
	return _loading or _target >= 0


## 0..1 of the running seek (build counts for the first 10 %); 1 when idle.
func seek_progress() -> float:
	if _loading:
		return 0.1 * float(_job.progress_pct()) / 100.0 if _job != null else 0.0
	if _target < 0:
		return 1.0
	return clampf(float(_tick) / float(maxi(_target, 1)), 0.0, 1.0) * 0.9 + 0.1


func is_loading() -> bool:
	return _loading


func load_progress_pct() -> int:
	return _job.progress_pct() if _loading and _job != null else 100


func is_finished() -> bool:
	return _finished


func is_paused() -> bool:
	return _paused


## 0 = MAX.
func speed() -> float:
	return _speed


## Increments with every world rebuild.
func generation() -> int:
	return _generation


## Last tick whose CHECK record matched while no earlier mismatch had been seen.
func verified_through_tick() -> int:
	return _verified


## Tick of the first mismatch of this player (-1 = none): the replay-desync marker.
func diverged_tick() -> int:
	return _diverged


## {tick, kind ("sim" | "chain" | "both" | "final"), expected, actual, expected_chain, actual_chain, parts: PackedStringArray}
## of the first mismatch ({} = none).
func mismatch() -> Dictionary:
	return _mismatch.duplicate()


## Number of CHECK records compared so far (a re-simulation after a backward seek does not count twice).
func compared_count() -> int:
	return _compared


## Input chain of the turns executed so far.
func input_chain() -> int:
	return _chain


# ---- control ---------------------------------------------------------------------------------------------------------

## Multiplier (0.25 .. 8, clamped); 0 = MAX (as fast as the poll budget allows).
func set_speed(multiplier: float) -> void:
	_speed = 0.0 if multiplier <= 0.0 else clampf(multiplier, SPEEDS[0], SPEEDS[SPEEDS.size() - 1])


func set_paused(p: bool) -> void:
	_paused = p


## Jumps to `target_tick` (clamped to 0 .. end_tick): forward = fast-forward, backward = rebuild the world and re-simulate
## from tick 0 (both time-sliced by poll()).
func seek_tick(target_tick: int) -> void:
	if _data == null:
		return
	var t: int = clampi(target_tick, 0, _end_tick)
	if _loading:
		_pending_seek = t
		return
	if _adapter == null:
		return
	if t > _tick:
		_target = t
		return
	if t == _tick:
		_target = -1
		return
	_reset_run()
	_pending_seek = t
	if not _start_build():
		_pending_seek = -1


## Advances the replay: paced speeds follow the clock (at most 8 x speed ticks per call), MAX and seeks are sliced by
## `budget_us`. Call once per frame.
func poll(budget_us: int = 6000) -> void:
	if _clock == null:
		return
	var now: int = _clock.now_us()
	var elapsed: int = clampi(now - _last_us, 0, MAX_CATCHUP_US)
	_last_us = now
	if _loading:
		_advance_build(budget_us)
		return
	if _adapter == null:
		return
	if _target >= 0:
		_run(budget_us, 1 << 30, _target)
		if _tick >= _target:
			_target = -1
		return
	if _paused or _finished:
		return
	if _speed <= 0.0:
		_run(budget_us, 1 << 30, _end_tick)
		return
	var cap: int = maxi(int(8.0 * _speed), 1)
	_acc_us += int(float(elapsed) * _speed)
	var due: int = mini(_acc_us / NetProtocol.TICK_US, cap)
	if due <= 0:
		return
	var done: int = _run(maxi(budget_us * 3, 12000), due, _end_tick)
	_acc_us -= done * NetProtocol.TICK_US
	_acc_us = mini(_acc_us, 2 * cap * NetProtocol.TICK_US)


# ---- internals -------------------------------------------------------------------------------------------------------

func _reset_run() -> void:
	_tick = 0
	_chain = CHAIN_BASIS
	_ti = 0
	_ci = 0
	_acc_us = 0
	_last_us = _clock.now_us() if _clock != null else 0
	_target = -1
	_finished = false
	_verified = 0


## Creates the world job. false (error_text set) when the builder does not give one.
func _start_build() -> bool:
	_build_failed = false
	var j: Variant = _builder.call(_data.config)
	if j is NetWorldJob:
		_job = j as NetWorldJob
	elif j is NetSimAdapter:
		_job = NetWorldJob.sync(func() -> NetSimAdapter: return j as NetSimAdapter)
	else:
		error_text = "the world builder returned no job"
		_build_failed = true
		return false
	_loading = true
	return true


func _advance_build(budget_us: int) -> void:
	if _job == null:
		_loading = false
		return
	if not _job.step(budget_us):
		return
	var err: String = _job.error()
	var a: NetSimAdapter = _job.take_adapter() if err == "" else null
	_job = null
	_loading = false
	if a == null:
		error_text = err if err != "" else "the world could not be built"
		_build_failed = true
		_pending_seek = -1
		return
	var first: bool = _adapter == null
	_adapter = a
	_generation += 1
	_tick = a.current_tick()
	_last_us = _clock.now_us()
	if not first:
		world_rebuilt.emit()
	if _pending_seek > 0:
		_target = _pending_seek
	_pending_seek = -1


## Runs up to `max_ticks` ticks (at least one) until `stop_tick`, within `budget_us` of real time. Returns the count.
func _run(budget_us: int, max_ticks: int, stop_tick: int) -> int:
	var t0: int = Time.get_ticks_usec()
	var n: int = 0
	var clear: bool = auto_clear_events or _target >= 0
	while n < max_ticks and _tick < stop_tick and not _finished:
		_step_tick(clear)
		n += 1
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
	return n


func _step_tick(clear: bool) -> void:
	if _tick % 2 == 0:
		_begin_turn(_tick / 2)
	_adapter.step()
	_tick += 1
	if clear:
		_adapter.clear_events()
	if _ci < _data.checks.size() / 3:
		_check_here()
	if _adapter.is_match_over() or _tick >= _end_tick:
		_finish_run()


func _begin_turn(turn: int) -> void:
	var body: PackedByteArray = _EMPTY_BODY
	var has: bool = _ti < _data.turns.size() and _data.turns[_ti] == turn
	if has:
		body = _data.bodies[_ti] as PackedByteArray
		_ti += 1
	_tb.encode_u32(0, turn)
	_chain = NetProtocol.fnv1a32(body, NetProtocol.fnv1a32(_tb, _chain))
	if has:
		var r: NetReader = NetReader.new(body)
		var groups: int = r.u8()
		for _g: int in groups:
			var pid: int = r.u8()
			for c: Variant in NetCodec.decode_commands(r, NetProtocol.MAX_CMDS_PER_TURN):
				_adapter.submit_command(pid, c as PackedInt32Array)


func _sum_now() -> int:
	var s: int = _adapter.checksum_at(_tick)
	if s < 0:
		s = _adapter.checksum_now()
	return s & _MASK


func _check_here() -> void:
	var n: int = _data.checks.size() / 3
	while _ci < n and _data.checks[_ci * 3] < _tick:
		_ci += 1
	if _ci >= n or _data.checks[_ci * 3] != _tick:
		return
	var exp_sum: int = _data.checks[_ci * 3 + 1] & _MASK
	var exp_chain: int = _data.checks[_ci * 3 + 2] & _MASK
	var act_sum: int = _sum_now()
	_compared = maxi(_compared, _ci + 1)
	_ci += 1
	if act_sum == exp_sum and _chain == exp_chain:
		if _diverged < 0:
			_verified = _tick
		return
	_flag(_tick, exp_sum, act_sum, exp_chain, _chain)


func _flag(tick: int, exp_sum: int, act_sum: int, exp_chain: int, act_chain: int, final: bool = false) -> void:
	if _diverged >= 0:
		return
	_diverged = tick
	var kind: String = "final" if final else ("both" if act_sum != exp_sum and act_chain != exp_chain else ("sim" if act_sum != exp_sum else "chain"))
	_mismatch = {"tick": tick, "kind": kind, "expected": exp_sum, "actual": act_sum, "expected_chain": exp_chain, "actual_chain": act_chain, "parts": _parts_diff(tick)}
	if not _reported:
		_reported = true
		if kind == "chain":
			verify_failed.emit(tick, exp_chain, act_chain)
		else:
			verify_failed.emit(tick, exp_sum, act_sum)


## Names of the sub-checksums that differ at `tick` (needs a recorded PARTS record for that tick; else the nearest earlier
## one cannot be compared and the list is empty).
func _parts_diff(tick: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var rec: Dictionary = _data.parts_at(tick)
	if rec.is_empty():
		return out
	var mine: PackedInt32Array = _adapter.checksum_parts_at(tick)
	var theirs: PackedInt32Array = rec["parts"] as PackedInt32Array
	var names: PackedStringArray = _adapter.checksum_part_names()
	for i: int in mini(mine.size(), theirs.size()):
		if (mine[i] & _MASK) != (theirs[i] & _MASK):
			out.append(names[i] if i < names.size() else "part%d" % i)
	return out


func _finish_run() -> void:
	if _finished:
		return
	_finished = true
	_target = -1
	if _data.finalized:
		var e: Dictionary = _data.end
		var exp_sum: int = int(e["final_checksum"]) & _MASK
		var exp_chain: int = int(e["final_chain"]) & _MASK
		var act: int = _adapter.checksum_now() & _MASK
		if _tick != int(e["final_tick"]) or act != exp_sum or _chain != exp_chain:
			_flag(_tick, exp_sum, act, exp_chain, _chain, true)
		elif _diverged < 0:
			_verified = _tick
	finished.emit()


# ---- headless verification ---------------------------------------------------------------------------------------------

## Plays the whole file headless and unpaced in strict mode. Result: {ok, ticks, compared, first_mismatch_tick (-1), final_checksum,
## final_chain, parts (differing sub-checksum names), kind, finalized, truncated, error}. `max_ticks` > 0 stops early (ok
## then means: no mismatch so far). `local` = the version gate of this build (see NetReplay.local_versions).
static func verify_file(path: String, world_builder: Callable, max_ticks: int = 0, local: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"ok": false, "ticks": 0, "compared": 0, "first_mismatch_tick": -1, "final_checksum": 0, "final_chain": 0, "parts": PackedStringArray(),
		"kind": "", "finalized": false, "truncated": false, "error": "",
	}
	var data: NetReplayData = NetReplayData.load_file(path)
	if data == null:
		out["error"] = NetReplayData.last_error
		return out
	return verify_data(data, world_builder, max_ticks, local, out)


## verify_file for an already loaded replay.
static func verify_data(data: NetReplayData, world_builder: Callable, max_ticks: int = 0, local: Dictionary = {}, result: Dictionary = {}) -> Dictionary:
	var out: Dictionary = result
	if out.is_empty():
		out = {"ok": false, "ticks": 0, "compared": 0, "first_mismatch_tick": -1, "final_checksum": 0, "final_chain": 0, "parts": PackedStringArray(), "kind": "", "finalized": false, "truncated": false, "error": ""}
	out["finalized"] = data.finalized
	out["truncated"] = data.truncated
	var p: NetReplayPlayer = NetReplayPlayer.new()
	p.strict = true
	p.local_versions = local
	p.auto_clear_events = true
	if p.setup(data, world_builder, NetClock.manual(0)) != OK:
		out["error"] = p.error_text
		return out
	p.set_speed(MAX)
	var guard: int = 0
	var stop: int = max_ticks if max_ticks > 0 else p.end_tick()
	while not p.is_finished() and p.current_tick() < stop and guard < 10_000_000:
		guard += 1
		p.poll(1_000_000)
	out["ticks"] = p.current_tick()
	out["compared"] = p.compared_count()
	out["first_mismatch_tick"] = p.diverged_tick()
	var a: NetSimAdapter = p.adapter()
	if a != null:
		out["final_checksum"] = a.checksum_now() & _MASK
	out["final_chain"] = p.input_chain()
	var mm: Dictionary = p.mismatch()
	if not mm.is_empty():
		out["parts"] = mm["parts"]
		out["kind"] = mm["kind"]
	out["ok"] = p.diverged_tick() < 0 and (p.is_finished() or max_ticks > 0)
	if not bool(out["ok"]) and p.diverged_tick() < 0:
		out["error"] = "the replay stopped before its recorded end"
	return out
