class_name UiSelectionActions
extends RefCounted
## Keyboard and menu selection commands built on the ports (ui.md 3.3, 5.5.4, 5.11.7): same type on screen or map,
## all military, next idle unit, next collector, next producer, headquarters. The single implementation behind the
## keys and the "Select" menu (QA A-06 / A-19). The view is duck-typed (UiViewPort: `entity_screen_rect`,
## `focus_on_sim`, `camera_state`) and `notifier` may implement `notice(key)`; both may be null.

signal nothing_found(key: StringName)  ## "notice.select.none" style key when a cycle finds no unit

var playfield: Rect2 = Rect2(0.0, 0.0, 1920.0, 1080.0)  ## the world area not covered by HUD chrome, viewport px

var _sim: UiSimPort = null
var _view: Object = null
var _sel: UiSelection = null
var _notifier: Object = null
var _caps: UiUnitCaps = null
var _ids: PackedInt32Array = PackedInt32Array()
var _row: UiEntityRow = UiEntityRow.new()
var _cursor_idle: int = 0
var _cursor_collector: int = 0
var _cursor_producer: int = 0


func setup(sim: UiSimPort, view: Object, selection: UiSelection, notifier: Object) -> void:
	_sim = sim
	_view = view
	_sel = selection
	_notifier = notifier
	_caps = UiUnitCaps.shared_for(sim)


## Own alive non-contained entities of that (kind, def) whose projected rect intersects the playfield.
func same_type_on_screen(kind: int, def_idx: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in same_type_on_map(kind, def_idx):
		var r: Variant = _view.call("entity_screen_rect", id) if _view != null else null
		if r is Rect2 and (r as Rect2).intersects(playfield):
			out.append(id)
	return out


## Own alive non-contained entities of that (kind, def), ascending.
func same_type_on_map(kind: int, def_idx: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	_sim.ids_of_def(kind, def_idx, _ids)
	for id: int in _ids:
		if _sim.read(id, _row) and (_row.flags & UiEntityRow.F_LOADED) == 0:
			out.append(id)
	return out


## Every own combat unit (armed, not service, not a structure), optionally only those on screen.
func all_military(on_screen_only: bool) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	_sim.own_ids(UiSimPort.KM_UNIT, _ids)
	for id: int in _ids:
		if not _sim.read(id, _row) or (_row.flags & UiEntityRow.F_LOADED) != 0:
			continue
		var c: int = _caps.caps_of(UiSimPort.KIND_UNIT, _row.def_idx)
		if (c & UiUnitCaps.CAP_ARMED) == 0 or (c & (UiUnitCaps.CAP_SERVICE | UiUnitCaps.CAP_STRUCTURE)) != 0:
			continue
		if on_screen_only:
			var r: Variant = _view.call("entity_screen_rect", id) if _view != null else null
			if not (r is Rect2) or not (r as Rect2).intersects(playfield):
				continue
		out.append(id)
	return out


## Selects the next (direction > 0) or previous idle armed unit in ascending id order, centres the camera; -1 if none.
func next_idle(direction: int) -> int:
	var cand: PackedInt32Array = PackedInt32Array()
	_sim.idle_units(_ids)
	for id: int in _ids:
		if _sim.read(id, _row) and (_caps.caps_of(UiSimPort.KIND_UNIT, _row.def_idx) & UiUnitCaps.CAP_ARMED) != 0:
			cand.append(id)
	var pick: int = _cycle(cand, direction, _cursor_idle)
	_cursor_idle = pick
	return _go(pick, &"notice.select.no_idle")


## Next own collector (ascending id, wraps).
func next_collector() -> int:
	var cand: PackedInt32Array = PackedInt32Array()
	_sim.own_ids(UiSimPort.KM_UNIT, _ids)
	for id: int in _ids:
		if _sim.read(id, _row) and (_caps.caps_of(UiSimPort.KIND_UNIT, _row.def_idx) & UiUnitCaps.CAP_COLLECTOR) != 0:
			cand.append(id)
	var pick: int = _cycle(cand, 1, _cursor_collector)
	_cursor_collector = pick
	return _go(pick, &"notice.select.no_collector")


## Next own producer structure (ascending id, wraps).
func next_producer() -> int:
	var cand: PackedInt32Array = PackedInt32Array()
	_sim.own_ids(UiSimPort.KM_STRUCTURE, _ids)
	for id: int in _ids:
		if _sim.read(id, _row) and (_row.flags & UiEntityRow.F_CONSTRUCTING) == 0 \
				and (_caps.caps_of(UiSimPort.KIND_STRUCTURE, _row.def_idx) & UiUnitCaps.CAP_PRODUCER) != 0:
			cand.append(id)
	var pick: int = _cycle(cand, 1, _cursor_producer)
	_cursor_producer = pick
	return _go(pick, &"notice.select.no_producer")


## The own Headquarters nearest to the camera focus (lowest id on ties); -1 if none.
func hq() -> int:
	var d: GameData = _sim.data()
	var best: int = -1
	var best_d: int = 0
	var fx: int = 0
	var fy: int = 0
	if _view != null and _view.has_method("camera_state"):
		var cs: Variant = _view.call("camera_state")
		if cs is Dictionary:
			fx = roundi(float((cs as Dictionary).get("focus_x", 0.0)) * 1024.0 / 3.0)
			fy = roundi(float((cs as Dictionary).get("focus_z", 0.0)) * 1024.0 / 3.0)
	_sim.own_ids(UiSimPort.KM_STRUCTURE, _ids)
	for id: int in _ids:
		if not _sim.read(id, _row) or (_row.flags & UiEntityRow.F_CONSTRUCTING) != 0:
			continue
		if _row.def_idx < 0 or _row.def_idx >= d.structures.size() or d.structures[_row.def_idx].build_radius <= 0:
			continue
		var dx: int = (_row.x - fx) >> 4
		var dy: int = (_row.y - fy) >> 4
		var dist: int = dx * dx + dy * dy
		if best < 0 or dist < best_d:
			best = id
			best_d = dist
	return _go(best, &"notice.select.no_hq")


## Next id after `last` in ascending `cand` (wraps); direction < 0 walks backwards. -1 when empty.
static func _cycle(cand: PackedInt32Array, direction: int, last: int) -> int:
	if cand.is_empty():
		return -1
	if direction >= 0:
		for id: int in cand:
			if id > last:
				return id
		return cand[0]
	for i: int in range(cand.size() - 1, -1, -1):
		if cand[i] < last or last <= 0:
			return cand[i]
	return cand[cand.size() - 1]


func _go(eid: int, none_key: StringName) -> int:
	if eid < 0:
		nothing_found.emit(none_key)
		if _notifier != null and is_instance_valid(_notifier) and _notifier.has_method("notice"):
			_notifier.call("notice", none_key)
		return -1
	_sel.replace(PackedInt32Array([eid]), _sim)
	if _sim.read(eid, _row) and _view != null and _view.has_method("focus_on_sim"):
		_view.call("focus_on_sim", _row.x, _row.y, false)
	return eid
