class_name AiEntityTable
extends RefCounted
## Struct-of-arrays rows for own entities and for recently seen enemy units (ai.md 4.2). `count` rows are dense; removal
## is swap-with-last; `row_of` maps eid -> row. Iteration order for tie-breaks is ALWAYS by ascending eid, never by row
## (use `sorted_eids()`).

var count: int = 0
var eid: PackedInt32Array = PackedInt32Array()
var def: PackedInt32Array = PackedInt32Array()
var owner: PackedInt32Array = PackedInt32Array()
var x: PackedInt32Array = PackedInt32Array()
var y: PackedInt32Array = PackedInt32Array()
var hp: PackedInt32Array = PackedInt32Array()
var hp_max: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var order: PackedInt32Array = PackedInt32Array()
var last_dmg: PackedInt32Array = PackedInt32Array()  ## last tick damaged (own rows)
var squad: PackedInt32Array = PackedInt32Array()  ## AiSquad.id or -1 (own rows)
var paid: PackedInt32Array = PackedInt32Array()  ## SimEntity.paid_cost
var role_mask: PackedInt64Array = PackedInt64Array()
var last_seen: PackedInt32Array = PackedInt32Array()  ## enemy rows: tick last seen
var last_moved: PackedInt32Array = PackedInt32Array()  ## enemy rows: tick the position last changed by >= 1 cell
var kind: PackedInt32Array = PackedInt32Array()  ## AiTypes.KIND_*
var refreshed: PackedInt32Array = PackedInt32Array()  ## tick the row was last re-read (ingest cursor)
var row_of: Dictionary = {}  ## eid -> row


## Row of `id` (existing or new). New rows start zeroed with squad -1.
func upsert(id: int) -> int:
	if row_of.has(id):
		return row_of[id]
	var r: int = count
	count += 1
	if eid.size() < count:
		var n: int = maxi(16, eid.size() * 2)
		for a: PackedInt32Array in [eid, def, owner, x, y, hp, hp_max, flags, order, last_dmg, squad, paid, last_seen, last_moved, kind, refreshed]:
			a.resize(n)
		role_mask.resize(n)
	eid[r] = id
	def[r] = -1
	owner[r] = -1
	x[r] = 0
	y[r] = 0
	hp[r] = 0
	hp_max[r] = 0
	flags[r] = 0
	order[r] = 0
	last_dmg[r] = AiTypes.NEVER
	squad[r] = -1
	paid[r] = 0
	role_mask[r] = 0
	last_seen[r] = 0
	last_moved[r] = 0
	kind[r] = 0
	refreshed[r] = AiTypes.NEVER
	row_of[id] = r
	return r


func has(id: int) -> bool:
	return row_of.has(id)


func row(id: int) -> int:
	return row_of.get(id, -1)


## Removes `id` (swap-with-last); false if absent.
func remove(id: int) -> bool:
	if not row_of.has(id):
		return false
	var r: int = row_of[id]
	var last: int = count - 1
	if r != last:
		var moved: int = eid[last]
		for a: PackedInt32Array in [eid, def, owner, x, y, hp, hp_max, flags, order, last_dmg, squad, paid, last_seen, last_moved, kind, refreshed]:
			a[r] = a[last]
		role_mask[r] = role_mask[last]
		row_of[moved] = r
	row_of.erase(id)
	count -= 1
	return true


func clear() -> void:
	count = 0
	row_of.clear()


## Entity ids in ascending order (the deterministic iteration order).
func sorted_eids() -> PackedInt32Array:
	var out: PackedInt32Array = eid.slice(0, count)
	out.sort()
	return out


## Sum of paid x hp / hp_max over the rows selected by `owner_filter` (-1 = all): the army value of the rows.
func value_of(owner_filter: int = -1) -> int:
	var v: int = 0
	for r: int in count:
		if owner_filter >= 0 and owner[r] != owner_filter:
			continue
		v += paid[r] * hp[r] / maxi(hp_max[r], 1)
	return v


func state_hash() -> int:
	return AiRng.mix32(count * 31 + AiRng.hash_ints(sorted_eids()))
