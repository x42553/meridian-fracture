class_name UiEntitySnapshot
extends RefCounted
## Structure-of-arrays snapshot of everything the viewer may draw on the minimap (ui.md 4.4.2); one bulk
## `UiSimPort.snapshot` call per 10 Hz. `flags` = UiEntityRow.F_* | (kind << 16).

var count: int = 0
var ids: PackedInt32Array = PackedInt32Array()
var xs: PackedInt32Array = PackedInt32Array()  ## sim units
var ys: PackedInt32Array = PackedInt32Array()
var defs: PackedInt32Array = PackedInt32Array()
var owners: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var hp_pct: PackedByteArray = PackedByteArray()  ## 0..100


## count = 0; the arrays keep their capacity.
func clear() -> void:
	count = 0


## Appends one entity (grows the arrays when full).
func push(eid: int, x: int, y: int, def_idx: int, owner: int, fl: int, pct: int) -> void:
	if count >= ids.size():
		var n: int = maxi(count * 2, 64)
		ids.resize(n)
		xs.resize(n)
		ys.resize(n)
		defs.resize(n)
		owners.resize(n)
		flags.resize(n)
		hp_pct.resize(n)
	ids[count] = eid
	xs[count] = x
	ys[count] = y
	defs[count] = def_idx
	owners[count] = owner
	flags[count] = fl
	hp_pct[count] = clampi(pct, 0, 100)
	count += 1


## Index of `eid` in the snapshot, -1 when absent (linear).
func index_of(eid: int) -> int:
	for i: int in count:
		if ids[i] == eid:
			return i
	return -1


## UiEntityRow.K_* of entry i.
func kind_of(i: int) -> int:
	return (flags[i] >> 16) & 0xFF
