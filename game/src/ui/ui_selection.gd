class_name UiSelection
extends RefCounted
## The selection model (ui.md 5.11): ids only, in selection order, in ONE mode (UNITS, STRUCTURES or a single
## FOREIGN entity). Survives entity death by pruning on every tick batch and by the REMOVED / DEATH hooks, and
## follows a deploying MCV to its Headquarters (successor rule, exact pairing, no distance heuristic).

enum Mode { NONE = 0, UNITS = 1, STRUCTURES = 2, FOREIGN = 3 }
const MAX_SELECT: int = 500  ## = maximum unit cap
const REM_DEPLOYED: int = 3  ## REMOVED reason

signal changed(mode: int)

var ids: PackedInt32Array = PackedInt32Array()  ## selection order (first = oldest)
var primary: int = -1  ## first id of the active subgroup, -1 if empty
var mode: int = Mode.NONE
var active_def: int = -1  ## active subgroup: per-kind def index; default = highest (tier, cost), ties lowest def index

var _kind: Dictionary = {}  ## id -> UiEntityRow.K_*
var _def: Dictionary = {}  ## id -> def_idx
var _rank: Dictionary = {}  ## def_idx -> tier * 2^20 + cost (units) / cost (structures), for the subgroup default
var _sorted: PackedInt32Array = PackedInt32Array()
var _sorted_ok: bool = false
var _row: UiEntityRow = UiEntityRow.new()


func size() -> int:
	return ids.size()


func has(eid: int) -> bool:
	return _kind.has(eid)


func is_empty() -> bool:
	return ids.is_empty()


func clear() -> void:
	if ids.is_empty():
		return
	_reset()
	changed.emit(mode)


## Ascending copy, cached until the next change: what commands carry (byte-identical arrays for identical actions).
func sorted_ids() -> PackedInt32Array:
	if not _sorted_ok:
		_sorted = ids.duplicate()
		_sorted.sort()
		_sorted_ok = true
	return _sorted


## Replaces the selection with the best mode found in `new_ids` (units win over structures; foreign = the first
## non-own entity only), capped at MAX_SELECT.
func replace(new_ids: PackedInt32Array, port: UiSimPort) -> void:
	var cls: Dictionary = _classify(new_ids, port)
	_apply(cls, false, port)


## Adds `new_ids` to the selection when they are of the current mode, otherwise replaces it (ui.md 5.11.1).
func add(new_ids: PackedInt32Array, port: UiSimPort) -> void:
	var cls: Dictionary = _classify(new_ids, port)
	var best: int = int(cls["mode"])
	if best == Mode.NONE:
		return
	_apply(cls, best == mode and mode != Mode.FOREIGN, port)


## Shift-click: removes eid if selected, else adds it (replaces when it is of another mode).
func toggle(eid: int, port: UiSimPort) -> void:
	if has(eid):
		remove(eid)
		return
	add(PackedInt32Array([eid]), port)


## Removes one id (no-op when absent).
func remove(eid: int) -> void:
	var i: int = ids.find(eid)
	if i < 0:
		return
	ids.remove_at(i)
	_kind.erase(eid)
	_def.erase(eid)
	_after_change()


## Drops dead, foreign-owned and contained ids and re-picks the primary; true when anything changed.
func prune(port: UiSimPort) -> bool:
	var settled: bool = settle()
	var viewer: int = port.viewer_pid()
	var keep: PackedInt32Array = PackedInt32Array()
	var def_changed: bool = false
	for id: int in ids:
		if not port.read(id, _row):
			continue
		if mode != Mode.FOREIGN and (_row.owner != viewer or (_row.flags & (UiEntityRow.F_LOADED | UiEntityRow.F_GHOST)) != 0):
			continue
		keep.append(id)
		if int(_def.get(id, -2)) != _row.def_idx:
			_def[id] = _row.def_idx
			def_changed = true
	if keep.size() == ids.size():
		if def_changed:
			_after_change()
		return def_changed or settled
	var dropped: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		if not keep.has(id):
			dropped.append(id)
	for id: int in dropped:
		_kind.erase(id)
		_def.erase(id)
	ids = keep
	_after_change()
	return true


## REMOVED / EV_DEATH hook (5.11.2). `reason` = REM_* (3 DEPLOYED, 4 CONSUMED, ...); `successor_eid` is the
## SPAWNED entity of reason DEPLOYED paired with this removal (`successors_of`), else -1. A deployed MCV becomes its
## Headquarters (and back) in place; any other removal just drops the id.
func on_removed(eid: int, reason: int, successor_eid: int) -> void:
	var i: int = ids.find(eid)
	if i < 0:
		return
	if reason == REM_DEPLOYED and successor_eid > 0 and not _kind.has(successor_eid):
		var was_struct: bool = int(_kind.get(eid, UiEntityRow.K_UNIT)) == UiEntityRow.K_STRUCTURE
		ids[i] = successor_eid
		_kind.erase(eid)
		_def.erase(eid)
		_kind[successor_eid] = UiEntityRow.K_UNIT if was_struct else UiEntityRow.K_STRUCTURE
		_def[successor_eid] = -1
		_fix_mode_after_swap()
		_after_change()
		return
	remove(eid)


## Pairs REMOVED(DEPLOYED) with SPAWNED(DEPLOYED) records of one drained batch into `out` (removed id -> successor id).
## Same owner only; paired by `parent_of.call(spawned_id) == removed_id` first, then by emission order per owner.
static func successors_of(records: PackedInt32Array, out: Dictionary, parent_of: Callable = Callable()) -> void:
	var removed: Dictionary = {}  ## owner -> Array[int] of removed ids in order
	var spawned: Dictionary = {}
	for i: int in UiEv.count(records):
		var t: int = UiEv.field(records, i, UiEv.I_TYPE)
		if t == UiEv.REMOVED and UiEv.field(records, i, UiEv.I_E) == UiEv.REM_DEPLOYED:
			var o: int = UiEv.field(records, i, UiEv.I_D)
			if not removed.has(o):
				removed[o] = []
			(removed[o] as Array).append(UiEv.field(records, i, UiEv.I_A))
		elif t == UiEv.SPAWNED and UiEv.field(records, i, UiEv.I_F) == UiEv.SPAWN_DEPLOYED:
			var o2: int = UiEv.field(records, i, UiEv.I_D)
			if not spawned.has(o2):
				spawned[o2] = []
			(spawned[o2] as Array).append(UiEv.field(records, i, UiEv.I_A))
	for o: Variant in removed:
		var rem: Array = (removed[o] as Array).duplicate()
		var spw: Array = (spawned.get(o, []) as Array).duplicate()
		if parent_of.is_valid():
			for s: Variant in spw.duplicate():
				var p: int = int(parent_of.call(int(s)))
				if p > 0 and rem.has(p):
					out[p] = int(s)
					rem.erase(p)
					spw.erase(s)
		while not rem.is_empty() and not spw.is_empty():
			out[int(rem.pop_front())] = int(spw.pop_front())


## Ctrl+Tab: moves the active subgroup to the next (direction > 0) / previous one, ordered by rank (highest first).
func cycle_subgroup(direction: int = 1) -> void:
	var defs: Array[int] = _distinct_defs()
	if defs.size() < 2:
		return
	var i: int = defs.find(active_def)
	i = posmod(i + (1 if direction >= 0 else -1), defs.size())
	active_def = defs[i]
	_pick_primary()
	changed.emit(mode)


## Number of selected ids whose def is `def_idx`.
func count_of_def(def_idx: int) -> int:
	var n: int = 0
	for id: int in ids:
		if int(_def.get(id, -2)) == def_idx:
			n += 1
	return n


## Def index of a selected id (-1 unknown).
func def_of(eid: int) -> int:
	return int(_def.get(eid, -1))


# ---- internals ------------------------------------------------------------------------------------------------
func _reset() -> void:
	ids = PackedInt32Array()
	_kind.clear()
	_def.clear()
	primary = -1
	active_def = -1
	mode = Mode.NONE
	_sorted_ok = false


## {"mode": best Mode, "ids": ordered candidate ids of that mode, "kinds": id -> K, "defs": id -> def}.
func _classify(new_ids: PackedInt32Array, port: UiSimPort) -> Dictionary:
	var viewer: int = port.viewer_pid()
	var units: PackedInt32Array = PackedInt32Array()
	var structs: PackedInt32Array = PackedInt32Array()
	var foreign: int = -1
	var kinds: Dictionary = {}
	var defs: Dictionary = {}
	for id: int in new_ids:
		if kinds.has(id) or not port.read(id, _row):
			continue
		if (_row.flags & UiEntityRow.F_LOADED) != 0:
			continue
		kinds[id] = _row.kind if _row.kind != UiEntityRow.K_NEUTRAL_STRUCTURE else UiEntityRow.K_STRUCTURE
		defs[id] = _row.def_idx
		if viewer >= 0 and _row.owner == viewer and (_row.flags & UiEntityRow.F_GHOST) == 0:
			if _row.kind == UiEntityRow.K_UNIT:
				units.append(id)
			elif _row.kind == UiEntityRow.K_STRUCTURE:
				structs.append(id)
		elif foreign < 0:
			foreign = id
	var best: int = Mode.NONE
	var picked: PackedInt32Array = PackedInt32Array()
	if not units.is_empty():
		best = Mode.UNITS
		picked = units
	elif not structs.is_empty():
		best = Mode.STRUCTURES
		picked = structs
	elif foreign >= 0:
		best = Mode.FOREIGN
		picked = PackedInt32Array([foreign])
	return {"mode": best, "ids": picked, "kinds": kinds, "defs": defs}


func _apply(cls: Dictionary, append: bool, port: UiSimPort) -> void:
	var best: int = int(cls["mode"])
	var picked: PackedInt32Array = cls["ids"]
	var kinds: Dictionary = cls["kinds"]
	var defs: Dictionary = cls["defs"]
	if best == Mode.NONE:
		if not append and not ids.is_empty():
			_reset()
			changed.emit(mode)
		return
	if not append:
		_reset()
	var before: int = ids.size()
	for id: int in picked:
		if ids.size() >= MAX_SELECT:
			break
		if _kind.has(id):
			continue
		ids.append(id)
		_kind[id] = kinds[id]
		_def[id] = defs[id]
	mode = best
	_note_ranks(port)
	if append and ids.size() == before:
		return
	_after_change()


func _note_ranks(port: UiSimPort) -> void:
	var d: GameData = port.data()
	if d == null:
		return
	for id: int in ids:
		var di: int = int(_def[id])
		if _rank.has(di) and int(_kind[id]) == UiEntityRow.K_UNIT:
			continue
		if int(_kind[id]) == UiEntityRow.K_UNIT:
			if di >= 0 and di < d.units.size():
				_rank[di] = d.units[di].tier * 1048576 + d.units[di].cost
		elif di >= 0 and di < d.structures.size():
			_rank[-di - 2] = d.structures[di].cost


func _rank_of(di: int, is_struct: bool) -> int:
	return int(_rank.get(-di - 2 if is_struct else di, 0))


func _distinct_defs() -> Array[int]:
	var defs: Array[int] = []
	for id: int in ids:
		var di: int = int(_def[id])
		if not defs.has(di):
			defs.append(di)
	var is_struct: bool = mode == Mode.STRUCTURES
	defs.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = _rank_of(a, is_struct)
		var rb: int = _rank_of(b, is_struct)
		return a < b if ra == rb else ra > rb)
	return defs


func _after_change() -> void:
	_sorted_ok = false
	if ids.is_empty():
		_reset()
		changed.emit(mode)
		return
	var still: bool = false
	for id: int in ids:
		if int(_def[id]) == active_def:
			still = true
			break
	if not still:
		active_def = _distinct_defs()[0]
	_pick_primary()
	changed.emit(mode)


func _pick_primary() -> void:
	primary = -1
	for id: int in ids:
		if int(_def[id]) == active_def:
			primary = id
			return
	primary = ids[0] if not ids.is_empty() else -1


## After an in-place MCV <-> HQ swap: when every id is of one kind the mode follows it. A mixed result waits for
## `settle` (several MCVs of one batch swap one after the other, so the intermediate state is legitimately mixed).
func _fix_mode_after_swap() -> void:
	var has_units: bool = false
	var has_structs: bool = false
	for id: int in ids:
		if int(_kind[id]) == UiEntityRow.K_UNIT:
			has_units = true
		else:
			has_structs = true
	if has_units != has_structs:
		mode = Mode.UNITS if has_units else Mode.STRUCTURES
	active_def = -2


## Resolves a mixed selection (after MCV <-> HQ swaps): units win over structures, the losers are dropped.
## `prune` calls it; a presenter may call it at the end of an event batch. True when anything changed.
func settle() -> bool:
	var has_units: bool = false
	for id: int in ids:
		if int(_kind[id]) == UiEntityRow.K_UNIT:
			has_units = true
			break
	var want: int = UiEntityRow.K_UNIT if has_units else UiEntityRow.K_STRUCTURE
	var keep: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		if int(_kind[id]) == want:
			keep.append(id)
	if keep.size() == ids.size():
		return false
	for id: int in ids:
		if not keep.has(id):
			_kind.erase(id)
			_def.erase(id)
	ids = keep
	mode = Mode.UNITS if has_units else Mode.STRUCTURES
	_after_change()
	return true
