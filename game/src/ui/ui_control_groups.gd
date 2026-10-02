class_name UiControlGroups
extends RefCounted
## Control groups 0-9 (ui.md 5.11.3): ids only, ascending. Membership is checked against the sim on recall - dead or
## foreign-owned members are dropped permanently, contained (F_LOADED) ones stay in the group but are not recalled.
## Assign / add semantics follow the keys: Ctrl+n assign, Ctrl+Shift+n `add_to`, Shift+n = `recall` merged by the caller.

const COUNT: int = 10

signal changed(index: int)

var double_tap_ms: int = 350  ## input group double-tap window (`register_press`)

var _groups: Array[PackedInt32Array] = []
var _last_press_index: int = -1
var _last_press_ms: int = -1000000
var _row: UiEntityRow = UiEntityRow.new()


func _init() -> void:
	for i: int in COUNT:
		_groups.append(PackedInt32Array())


## Ctrl+n: the group becomes exactly `ids` (ascending, unique). Empty ids clear it.
func assign(index: int, ids: PackedInt32Array) -> void:
	if not _ok(index):
		return
	var g: PackedInt32Array = ids.duplicate()
	g.sort()
	_groups[index] = _unique(g)
	changed.emit(index)


## Ctrl+Shift+n: adds `ids` to the group.
func add_to(index: int, ids: PackedInt32Array) -> void:
	if not _ok(index) or ids.is_empty():
		return
	var g: PackedInt32Array = _groups[index].duplicate()
	g.append_array(ids)
	g.sort()
	_groups[index] = _unique(g)
	changed.emit(index)


## Raw members (may contain dead ids until the next recall).
func members(index: int) -> PackedInt32Array:
	return _groups[index].duplicate() if _ok(index) else PackedInt32Array()


## Alive, viewer-owned, uncontained members, ascending. Dead / foreign-owned ids are removed from the group for good;
## a group that ends up empty stays empty (the caller plays the soft "empty" tick).
func recall(index: int, port: UiSimPort) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if not _ok(index):
		return out
	var keep: PackedInt32Array = PackedInt32Array()
	var viewer: int = port.viewer_pid()
	for id: int in _groups[index]:
		if not port.read(id, _row) or _row.hp <= 0 or (viewer >= 0 and port.rel(viewer, _row.owner) != UiSimPort.Rel.SELF):
			continue
		keep.append(id)
		if (_row.flags & UiEntityRow.F_LOADED) == 0:
			out.append(id)
	if keep.size() != _groups[index].size():
		_groups[index] = keep
		changed.emit(index)
	return out


## Alive recallable members (does not prune).
func count(index: int, port: UiSimPort) -> int:
	if not _ok(index):
		return 0
	var n: int = 0
	var viewer: int = port.viewer_pid()
	for id: int in _groups[index]:
		if port.read(id, _row) and _row.hp > 0 and (_row.flags & UiEntityRow.F_LOADED) == 0 \
				and (viewer < 0 or port.rel(viewer, _row.owner) == UiSimPort.Rel.SELF):
			n += 1
	return n


func is_empty(index: int) -> bool:
	return not _ok(index) or _groups[index].is_empty()


## Integer centroid (x, y sum / n, truncating) of the alive recallable members; (-1, -1) when none.
func centroid_sim(index: int, port: UiSimPort) -> Vector2i:
	if not _ok(index):
		return Vector2i(-1, -1)
	var sx: int = 0
	var sy: int = 0
	var n: int = 0
	var viewer: int = port.viewer_pid()
	for id: int in _groups[index]:
		if port.read(id, _row) and _row.hp > 0 and (_row.flags & UiEntityRow.F_LOADED) == 0 \
				and (viewer < 0 or port.rel(viewer, _row.owner) == UiSimPort.Rel.SELF):
			sx += _row.x
			sy += _row.y
			n += 1
	return Vector2i(sx / n, sy / n) if n > 0 else Vector2i(-1, -1)


## Index of the next non-empty group after `from` (cycling, Ctrl+G); -1 when every group is empty.
func next_nonempty(from: int) -> int:
	for step: int in range(1, COUNT + 1):
		var i: int = (from + step) % COUNT
		if not _groups[i].is_empty():
			return i
	return -1


## Records a press of group `index` at `now_ms`; true when it is the second press of the same group within
## `double_tap_ms` (the caller then centres the camera). A completed double tap resets the detector.
func register_press(index: int, now_ms: int) -> bool:
	var dbl: bool = index == _last_press_index and now_ms - _last_press_ms <= double_tap_ms and now_ms >= _last_press_ms
	if dbl:
		_last_press_index = -1
		_last_press_ms = -1000000
	else:
		_last_press_index = index
		_last_press_ms = now_ms
	return dbl


## Forgets every group (new match).
func clear_all() -> void:
	for i: int in COUNT:
		if not _groups[i].is_empty():
			_groups[i] = PackedInt32Array()
			changed.emit(i)
	_last_press_index = -1


func _ok(index: int) -> bool:
	return index >= 0 and index < COUNT


static func _unique(sorted_ids: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in sorted_ids:
		if id > 0 and (out.is_empty() or out[out.size() - 1] != id):
			out.append(id)
	return out
