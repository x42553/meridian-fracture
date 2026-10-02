class_name NetSimAdapterFake
extends NetSimAdapter
## Deterministic stand-in for the simulation (docs/spec/net.md 3.3 and 10.2): a 32-bit hash machine that
## folds every submitted command and the tick number into two words. Ships in src/net because the scenario
## harness and CI use it; shipping game code never constructs it.
##
## Algorithm: mix(h, v) = ((h ^ (v & 0xFFFFFFFF)) * 0x01000193) & 0xFFFFFFFF. step(): for each pending
## (pid, ints) in call order state = mix(state, 0x1000 + pid) then state = mix(state, v) for each int; clear
## pending; state = (state * 1103515245 + 12345 + tick) & 0xFFFFFFFF; state_b = mix(state_b, tick);
## tick += 1; every 20 ticks a snapshot total = mix(state, state_b) with parts [state, state_b] is stored.

const PART_NAMES: PackedStringArray = ["cmds", "clock"]
const RETAIN: int = 64

## Fake-only knob for tests: the tick at which is_match_over() turns true (-1 = never).
var end_tick: int = -1

var _seed: int = 0
var _state: int = 12345
var _state_b: int = 0x2545F491
var _tick: int = 0
var _pending_pid: PackedInt32Array = PackedInt32Array()
var _pending_ints: Array[PackedInt32Array] = []
var _snap_ticks: PackedInt32Array = PackedInt32Array()
var _snap_total: Dictionary = {}
var _snap_parts: Dictionary = {}
var _resigned: Dictionary = {}
var _diverge: Dictionary = {}  # at_tick -> part (consumed once)
## Number of submitted commands that were empty (ignored).
var malformed_count: int = 0


func _init(map_seed: int = 0, end_tick_: int = -1) -> void:
	_seed = map_seed
	end_tick = end_tick_


static func mix(h: int, v: int) -> int:
	return ((h ^ (v & 0xFFFFFFFF)) * 0x01000193) & 0xFFFFFFFF


## Test hook: flips bit 0 of `part` (0 = cmds word, 1 = clock word) once, when the tick counter reaches
## `at_tick` (before that tick's snapshot is taken).
func inject_divergence(at_tick: int, part: int) -> void:
	_diverge[at_tick] = part


## Test hook: true after a command of type 250 was executed for `pid`.
func resigned(pid: int) -> bool:
	return _resigned.has(pid)


func world() -> RefCounted:
	return self


func current_tick() -> int:
	return _tick


func submit_command(pid: int, ints: PackedInt32Array) -> void:
	if ints.is_empty():
		malformed_count += 1
		return
	_pending_pid.append(pid)
	_pending_ints.append(ints)


func step() -> void:
	for i: int in _pending_pid.size():
		var pid: int = _pending_pid[i]
		var ints: PackedInt32Array = _pending_ints[i]
		_state = mix(_state, 0x1000 + pid)
		for v: int in ints:
			_state = mix(_state, v)
		if ints[0] == NetProtocol.T_RESIGN:
			_resigned[pid] = true
	_pending_pid = PackedInt32Array()
	_pending_ints = []
	_state = (_state * 1103515245 + 12345 + _tick) & 0xFFFFFFFF
	_state_b = mix(_state_b, _tick)
	_tick += 1
	if _diverge.has(_tick):
		if int(_diverge[_tick]) == 0:
			_state ^= 1
		else:
			_state_b ^= 1
		_diverge.erase(_tick)
	if _tick % NetProtocol.CHECKSUM_PERIOD_TICKS == 0:
		_snap_ticks.append(_tick)
		_snap_total[_tick] = mix(_state, _state_b)
		_snap_parts[_tick] = PackedInt32Array([_state, _state_b])
		while _snap_ticks.size() > RETAIN:
			var old: int = _snap_ticks[0]
			_snap_ticks.remove_at(0)
			_snap_total.erase(old)
			_snap_parts.erase(old)


func checksum_at(tick: int) -> int:
	return int(_snap_total.get(tick, -1))


func checksum_parts_at(tick: int) -> PackedInt32Array:
	if not _snap_parts.has(tick):
		return PackedInt32Array()
	return _snap_parts[tick] as PackedInt32Array


func checksum_part_names() -> PackedStringArray:
	return PART_NAMES


func checksum_now() -> int:
	return mix(_state, _state_b)


func map_hash() -> int:
	return NetProtocol.fnv1a32(("fake-map:" + str(_seed)).to_utf8_buffer())


func is_match_over() -> bool:
	return end_tick >= 0 and _tick >= end_tick


func match_result() -> Dictionary:
	return {"winner_team": -1, "reason": 0}


func is_player_active(pid: int) -> bool:
	return not _resigned.has(pid)


func dump_state() -> String:
	return "state=%08X\nstate_b=%08X\ntick=%d\n" % [_state, _state_b, _tick]


func clear_events() -> void:
	pass
