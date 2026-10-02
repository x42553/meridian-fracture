class_name AiGhostTable
extends RefCounted
## Persistent remembered enemy / neutral STRUCTURES (ai.md 4.2 / 5.3.2), <= 768 rows: eid, def, owner, x, y, last_seen,
## hp_pct, flags, conf, kind (StructKind), value. `conf` = 100 when seen this tick, -1 per 20 ticks down to a floor of 30.
## Ghosts are deleted when their cell is visible and the entity is absent, or when destruction is confirmed. Seed rows: a
## PRESUMED HQ per enemy start position (conf 30, negative synthetic eid = -(owner + 1)) that a real sighting replaces.

const MAX_ROWS: int = 768

var count: int = 0
var eid: PackedInt32Array = PackedInt32Array()
var def: PackedInt32Array = PackedInt32Array()
var owner: PackedInt32Array = PackedInt32Array()
var x: PackedInt32Array = PackedInt32Array()
var y: PackedInt32Array = PackedInt32Array()
var last_seen: PackedInt32Array = PackedInt32Array()
var hp_pct: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var conf: PackedInt32Array = PackedInt32Array()
var kind: PackedInt32Array = PackedInt32Array()
var value: PackedInt32Array = PackedInt32Array()
var row_of: Dictionary = {}

var conf_floor: int = 30
var decay_ticks: int = 20


func _cols() -> Array:
	return [eid, def, owner, x, y, last_seen, hp_pct, flags, conf, kind, value]


## Inserts or refreshes a ghost; returns the row (-1 when the table is full and `id` is new).
func upsert(id: int, p_def: int, p_owner: int, px: int, py: int, tick: int, pct: int, p_flags: int, p_kind: int, p_value: int) -> int:
	var r: int
	if row_of.has(id):
		r = row_of[id]
	else:
		if count >= MAX_ROWS:
			return -1
		r = count
		count += 1
		if eid.size() < count:
			var n: int = maxi(32, eid.size() * 2)
			for a: PackedInt32Array in _cols():
				a.resize(n)
		row_of[id] = r
	eid[r] = id
	def[r] = p_def
	owner[r] = p_owner
	x[r] = px
	y[r] = py
	last_seen[r] = tick
	hp_pct[r] = pct
	flags[r] = p_flags
	conf[r] = 100
	kind[r] = p_kind
	value[r] = p_value
	return r


## Presumed HQ ghost of an enemy start (conf 30). A later real upsert of the true HQ removes it via replace_presumed().
func seed_presumed_hq(p_owner: int, p_def: int, px: int, py: int, tick: int, p_value: int) -> int:
	var r: int = upsert(-(p_owner + 1), p_def, p_owner, px, py, tick, 100, 0, AiTypes.StructKind.HQ, p_value)
	if r >= 0:
		conf[r] = conf_floor
	return r


## Drops the presumed HQ of `p_owner` (called when the real HQ is sighted).
func replace_presumed(p_owner: int) -> void:
	remove(-(p_owner + 1))


func has(id: int) -> bool:
	return row_of.has(id)


func row(id: int) -> int:
	return row_of.get(id, -1)


func remove(id: int) -> bool:
	if not row_of.has(id):
		return false
	var r: int = row_of[id]
	var last: int = count - 1
	if r != last:
		var moved: int = eid[last]
		for a: PackedInt32Array in _cols():
			a[r] = a[last]
		row_of[moved] = r
	row_of.erase(id)
	count -= 1
	return true


## conf decays 1 per `decay_ticks` since the last sighting, floor `conf_floor`.
func decay(tick: int) -> void:
	for r: int in count:
		if eid[r] < 0:
			continue  # presumed rows stay at their seed confidence
		conf[r] = clampi(100 - (tick - last_seen[r]) / decay_ticks, conf_floor, 100)


## Rows within r (sub-cell units) of (px, py) whose kind bit (1 << kind) is in kind_mask (-1 = any), ascending eid.
func near(px: int, py: int, r: int, kind_mask: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var r2: int = r * r
	for i: int in count:
		if kind_mask >= 0 and (kind_mask & (1 << kind[i])) == 0:
			continue
		var dx: int = x[i] - px
		var dy: int = y[i] - py
		if dx * dx + dy * dy <= r2:
			out.append(i)
	_sort_rows_by_eid(out)
	return out.size()


func _sort_rows_by_eid(rows: PackedInt32Array) -> void:
	# insertion sort on (eid, row): tables are small, rows come mostly ordered
	for i: int in range(1, rows.size()):
		var v: int = rows[i]
		var j: int = i - 1
		while j >= 0 and eid[rows[j]] > eid[v]:
			rows[j + 1] = rows[j]
			j -= 1
		rows[j + 1] = v


func sorted_eids() -> PackedInt32Array:
	var out: PackedInt32Array = eid.slice(0, count)
	out.sort()
	return out


func value_of_owner(p_owner: int) -> int:
	var v: int = 0
	for r: int in count:
		if owner[r] == p_owner:
			v += value[r]
	return v


func state_hash() -> int:
	return AiRng.mix32(count * 17 + AiRng.hash_ints(sorted_eids()))
