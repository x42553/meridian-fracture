class_name SndScheduler
extends RefCounted
## Tiny time-ordered queue for delayed sounds (shell whistle, propagation delay, staggered impacts). Capacity 64.

const CAPACITY: int = 64

var _due: PackedInt32Array = PackedInt32Array()
var _def: Array[SndEventDef] = []
var _pos: PackedVector3Array = PackedVector3Array()
var _flavour: Array[StringName] = []
var _gain: PackedFloat32Array = PackedFloat32Array()
var _tag: PackedInt32Array = PackedInt32Array()


func size() -> int:
	return _due.size()


## False when the queue is full.
func push(due_ms: int, def: SndEventDef, world_pos: Vector3, flavour: StringName, gain_db: float, tag: int) -> bool:
	if _due.size() >= CAPACITY:
		return false
	var at: int = _due.size()
	while at > 0 and _due[at - 1] > due_ms:
		at -= 1
	_due.insert(at, due_ms)
	_def.insert(at, def)
	_pos.insert(at, world_pos)
	_flavour.insert(at, flavour)
	_gain.insert(at, gain_db)
	_tag.insert(at, tag)
	return true


## Removes every item due at `now_ms` and returns its parallel data through `out_items` ({def, pos, flavour, gain, tag}).
func pop_due(now_ms: int, out_items: Array[Dictionary]) -> int:
	var n: int = 0
	while not _due.is_empty() and _due[0] <= now_ms:
		out_items.append({"def": _def[0], "pos": _pos[0], "flavour": _flavour[0], "gain": _gain[0], "tag": _tag[0]})
		_due.remove_at(0)
		_def.remove_at(0)
		_pos.remove_at(0)
		_flavour.remove_at(0)
		_gain.remove_at(0)
		_tag.remove_at(0)
		n += 1
	return n


func cancel_tag(tag: int) -> void:
	var i: int = _tag.size() - 1
	while i >= 0:
		if _tag[i] == tag:
			_due.remove_at(i)
			_def.remove_at(i)
			_pos.remove_at(i)
			_flavour.remove_at(i)
			_gain.remove_at(i)
			_tag.remove_at(i)
		i -= 1


func clear() -> void:
	_due.clear()
	_def.clear()
	_pos.clear()
	_flavour.clear()
	_gain.clear()
	_tag.clear()
