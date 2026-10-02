class_name SimTimerWheel
extends RefCounted
## Deterministic 1024-slot timer wheel with ABSOLUTE due ticks (abilities 3.6 / 5.1). A slot holds every timer whose
## due tick is congruent modulo 1024; entries keep insertion order and are fired only when due <= the popped tick, so
## timers further than 1024 ticks away simply wait a lap. Raw buckets are derived state (never hashed).

const SIZE: int = 1024
const STRIDE: int = 4  ## [due, eid, kind, gen]

var _b: Array[PackedInt32Array] = []
var _last: int = -1  ## last popped tick
var _count: int = 0


func _init() -> void:
	_b.resize(SIZE)
	for i: int in SIZE:
		_b[i] = PackedInt32Array()


## A timer scheduled for a tick that was already popped fires at the next pop (never lost).
func schedule(due_tick: int, eid: int, kind: int, gen: int) -> void:
	if due_tick <= _last:
		due_tick = _last + 1
	var arr: PackedInt32Array = _b[due_tick & (SIZE - 1)]
	arr.append(due_tick)
	arr.append(eid)
	arr.append(kind)
	arr.append(gen)
	_count += 1


## Clears `out` and fills it with the (eid, kind, gen) triples due at `tick`, in insertion order.
func pop_due(tick: int, out: PackedInt32Array) -> void:
	out.resize(0)
	_last = maxi(_last, tick)
	var arr: PackedInt32Array = _b[tick & (SIZE - 1)]
	var n: int = arr.size()
	if n == 0:
		return
	var w: int = 0
	var i: int = 0
	while i < n:
		if arr[i] <= tick:
			out.append(arr[i + 1])
			out.append(arr[i + 2])
			out.append(arr[i + 3])
			_count -= 1
		else:
			if w != i:
				arr[w] = arr[i]
				arr[w + 1] = arr[i + 1]
				arr[w + 2] = arr[i + 2]
				arr[w + 3] = arr[i + 3]
			w += STRIDE
		i += STRIDE
	arr.resize(w)


## Timers still pending.
func size() -> int:
	return _count
