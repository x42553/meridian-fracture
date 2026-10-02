class_name SimEventBuffer
extends RefCounted
## Append-only buffer of fixed-stride int32 event records (sim_core 3.7 / 5.7), `world.events`. Output-only
## (DR-12): the sim never reads it, toggling `enabled` never changes the checksum chain, and the emission
## sequence is deterministic (`digest()` is tested across runs and platforms).
##
## Draining: the app calls `take()` once per rendered frame and hands the array, read-only, to view / audio / UI.

## Accumulated records, SimEvent.STRIDE ints each: [type, tick, x, y, a, b, c, d, e, f].
var data: PackedInt32Array = PackedInt32Array()
## false makes every emit a no-op (soak tests).
var enabled: bool = true
## Records dropped by the soft cap since construction.
var dropped: int = 0
## Stamped into every record. SimWorld sets it to its current tick at the start of each step (and after the tick
## counter advances); tests may set it directly.
var tick: int = 0

## Last emission tick per (type, pid slot) for emit_throttled; SimConfig.NEVER = never.
var _last: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_last.resize(SimEvent.THROTTLE_TYPES * (SimConfig.MAX_PLAYERS + 1))
	_last.fill(SimConfig.NEVER)


## Appends [type, tick, x, y, a..f]; dropped (and counted) when the buffer would exceed the soft cap.
func emit(type: int, x: int = 0, y: int = 0, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0) -> void:
	if not enabled:
		return
	var n: int = data.size()
	if n + SimConfig.EVENT_STRIDE > SimConfig.EVENT_SOFT_CAP_INTS:
		dropped += 1
		return
	data.resize(n + SimConfig.EVENT_STRIDE)
	data[n] = type
	data[n + 1] = tick
	data[n + 2] = x
	data[n + 3] = y
	data[n + 4] = a
	data[n + 5] = b
	data[n + 6] = c
	data[n + 7] = d
	data[n + 8] = e
	data[n + 9] = f


## Like emit, but at most once per `gap` ticks per (type, pid); type < SimEvent.THROTTLE_TYPES, pid -1..7.
func emit_throttled(type: int, pid: int, gap: int, x: int = 0, y: int = 0, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0) -> void:
	if not enabled:
		return
	var idx: int = type * (SimConfig.MAX_PLAYERS + 1) + SimConfig.slot_of(pid)
	if tick - _last[idx] < gap:
		return
	_last[idx] = tick
	emit(type, x, y, a, b, c, d, e, f)


## O(1): hands the accumulated records to the caller and restarts empty.
func take() -> PackedInt32Array:
	var out: PackedInt32Array = data
	data = PackedInt32Array()
	return out


## Number of records.
func count() -> int:
	return data.size() / SimConfig.EVENT_STRIDE


## Discards the accumulated records (the throttle state and `dropped` are kept).
func clear() -> void:
	data = PackedInt32Array()


## Checksum.digest32 of the whole buffer (event-determinism tests); an empty buffer gives EMPTY_DIGEST.
func digest() -> int:
	return Checksum.digest32(data)
