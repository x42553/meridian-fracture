class_name UiSelectionInfo
extends RefCounted
## Aggregated capabilities of a selection (ui.md 4.3): the input of `UiContextResolver`. Built when the selection
## changes (or per click), never per frame. `ids` is ascending and parallel to `caps` / `defs`.

var mode: int = UiSelection.Mode.NONE
var count: int = 0
var caps_any: int = 0  ## OR of UiUnitCaps over the selection
var caps_all: int = 0  ## AND of UiUnitCaps
var ids_by_cap: Dictionary = {}  ## cap bit -> PackedInt32Array of ids having it; filled lazily by ids_with
var primary_def: int = -1
var has_foreign: bool = false
var ids: PackedInt32Array = PackedInt32Array()  ## ascending
var caps: PackedInt32Array = PackedInt32Array()  ## caps of ids[i]
var defs: PackedInt32Array = PackedInt32Array()  ## per-kind def index of ids[i]
var move_mask: int = 0  ## OR of 1 << DefEnums.MoveClass over the mobile units (0 when unknown)
var move_classes: PackedInt32Array = PackedInt32Array()  ## move class of ids[i], -1 unknown


## Builds the info for `sel` from the port's reads and the caps cache (null = UiUnitCaps.shared_for(port)).
static func build(sel: UiSelection, port: UiSimPort, cache: UiUnitCaps = null) -> UiSelectionInfo:
	var c: UiUnitCaps = cache if cache != null else UiUnitCaps.shared_for(port)
	var sorted: PackedInt32Array = sel.sorted_ids()
	var row := UiEntityRow.new()
	var cap_arr: PackedInt32Array = PackedInt32Array()
	var def_arr: PackedInt32Array = PackedInt32Array()
	var mc_arr: PackedInt32Array = PackedInt32Array()
	var kept: PackedInt32Array = PackedInt32Array()
	for id: int in sorted:
		if not port.read(id, row):
			continue
		var k: int = UiSimPort.KIND_STRUCTURE if row.is_structure() else UiSimPort.KIND_UNIT
		kept.append(id)
		cap_arr.append(c.caps_of(k, row.def_idx))
		def_arr.append(row.def_idx)
		mc_arr.append(c.move_class_of(k, row.def_idx))
	var info: UiSelectionInfo = from_entries(sel.mode, kept, cap_arr, def_arr, mc_arr)
	info.primary_def = sel.active_def
	info.has_foreign = sel.mode == UiSelection.Mode.FOREIGN
	return info


## Pure builder: parallel arrays (ids need not be sorted; they are sorted here). `move_classes` optional.
static func from_entries(p_mode: int, p_ids: PackedInt32Array, p_caps: PackedInt32Array, p_defs: PackedInt32Array = PackedInt32Array(), p_move_classes: PackedInt32Array = PackedInt32Array()) -> UiSelectionInfo:
	var info := UiSelectionInfo.new()
	info.mode = p_mode
	var n: int = p_ids.size()
	var order: Array[int] = []
	for i: int in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return p_ids[a] < p_ids[b])
	info.ids.resize(n)
	info.caps.resize(n)
	info.defs.resize(n)
	info.move_classes.resize(n)
	var all: int = -1
	var any: int = 0
	for j: int in n:
		var i: int = order[j]
		var cp: int = p_caps[i]
		info.ids[j] = p_ids[i]
		info.caps[j] = cp
		info.defs[j] = p_defs[i] if i < p_defs.size() else -1
		var mc: int = p_move_classes[i] if i < p_move_classes.size() else -1
		info.move_classes[j] = mc
		if mc >= 0 and (cp & UiUnitCaps.CAP_MOBILE) != 0:
			info.move_mask |= 1 << mc
		any |= cp
		all &= cp
	info.count = n
	info.caps_any = any
	info.caps_all = all if n > 0 else 0
	if n > 0:
		info.primary_def = info.defs[0]
	return info


## Ids whose caps contain every bit of `cap_mask` (or any bit when require_all is false), ascending.
func ids_with(cap_mask: int, require_all: bool = true) -> PackedInt32Array:
	var single: bool = cap_mask != 0 and (cap_mask & (cap_mask - 1)) == 0
	if single and ids_by_cap.has(cap_mask):
		return ids_by_cap[cap_mask]
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in ids.size():
		var hit: int = caps[i] & cap_mask
		if (hit == cap_mask) if require_all else (hit != 0):
			out.append(ids[i])
	if single:
		ids_by_cap[cap_mask] = out
	return out


## Ids having none of the bits of `cap_mask`, ascending.
func ids_without(cap_mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in ids.size():
		if (caps[i] & cap_mask) == 0:
			out.append(ids[i])
	return out


func has_id(eid: int) -> bool:
	return index_of(eid) >= 0


## Position of `eid` in `ids` (binary search; ids are ascending), -1 when not selected.
func index_of(eid: int) -> int:
	var i: int = ids.bsearch(eid)
	return i if i < ids.size() and ids[i] == eid else -1


## Caps of one selected id (0 when not selected).
func caps_of(eid: int) -> int:
	var i: int = index_of(eid)
	return caps[i] if i >= 0 else 0


func def_of(eid: int) -> int:
	var i: int = index_of(eid)
	return defs[i] if i >= 0 else -1


func is_empty() -> bool:
	return count == 0
