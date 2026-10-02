class_name SimDepositTable
extends RefCounted
## Deposit FIELDS of the match (economy 4.6 / 5.9): one entry per map field (`MapData.deposit_fields()`, index =
## deposit idx = position in that list). The credits themselves live in the map (`MapData.deposit`, per cell, hashed
## by the map's deposit_hash); this table holds the per-field bookkeeping (disc geometry, class, harvester counts,
## last harvest / regrowth ticks) and is hashed by the economy (`hash_into`). It never stores the map or the world
## (RefCounted cycles): every call that needs them receives them.
##
## Regrowth: global.json says `deposit.regrow = false` (finite fields), so `regrow` is off by default; when a test
## or a rule switches it on, an idle field regains `regen_amount[i]` credits every `regen_period[i]` ticks after
## `regen_delay[i]` idle ticks (economy 5.9).

const KLASS_START: int = 0
const KLASS_EXPANSION: int = 1
const KLASS_RICH: int = 2
const MAX_HARVESTERS: PackedInt32Array = [4, 5, 6]
const REGEN_AMOUNT: PackedInt32Array = [40, 60, 100]
const REGEN_PERIOD: int = 200
const REGEN_DELAY: int = 1200
const REGEN_STRIDE: int = 20
const CELL: int = SimConfig.CELL

var count: int = 0
var regrow: bool = false  ## configuration (not authoritative state): identical in every peer of a match
var field_id: PackedInt32Array = PackedInt32Array()  ## MapData field id (1-based) of deposit idx i
var x: PackedInt32Array = PackedInt32Array()  ## field centre, sub-cells
var y: PackedInt32Array = PackedInt32Array()
var radius: PackedInt32Array = PackedInt32Array()  ## sub-cells
var klass: PackedInt32Array = PackedInt32Array()
var cap: PackedInt32Array = PackedInt32Array()  ## total credits at match start
var regen_amount: PackedInt32Array = PackedInt32Array()
var regen_period: PackedInt32Array = PackedInt32Array()
var regen_delay: PackedInt32Array = PackedInt32Array()
var last_harvest_tick: PackedInt32Array = PackedInt32Array()
var next_regen_tick: PackedInt32Array = PackedInt32Array()
var harvesters: PackedInt32Array = PackedInt32Array()  ## collectors currently assigned (h_field == idx)
var depleted: PackedByteArray = PackedByteArray()  ## 1 after EVT_DEPOSIT_DEPLETED until regrown to 10 %
var search_tick: int = -1  ## global field-search budget: the tick it was last used and the searches spent in it
var search_used: int = 0


## Builds the table from a finalized map. `_econ` is reserved for data-driven regen (the data schema has none yet).
func setup(map: MapData, _econ: DefEconomy) -> void:
	var fl: Array = map.deposit_fields()
	count = fl.size()
	field_id.resize(count)
	x.resize(count)
	y.resize(count)
	radius.resize(count)
	klass.resize(count)
	cap.resize(count)
	regen_amount.resize(count)
	regen_period.resize(count)
	regen_delay.resize(count)
	last_harvest_tick.resize(count)
	next_regen_tick.resize(count)
	harvesters.resize(count)
	depleted.resize(count)
	for i: int in count:
		var f: Dictionary = fl[i]
		field_id[i] = int(f["id"])
		x[i] = int(f["cx"]) * CELL + CELL / 2
		y[i] = int(f["cy"]) * CELL + CELL / 2
		radius[i] = int(f["radius"]) * CELL
		var k: int = clampi(int(f["klass_economy"]), 0, 2)
		klass[i] = k
		cap[i] = int(f["total"])
		regen_amount[i] = REGEN_AMOUNT[k]
		regen_period[i] = REGEN_PERIOD
		regen_delay[i] = REGEN_DELAY
		last_harvest_tick[i] = -REGEN_DELAY
		harvesters[i] = 0


func max_harvesters(i: int) -> int:
	return MAX_HARVESTERS[klass[i]]


func stock(map: MapData, i: int) -> int:
	return map.field_remaining(field_id[i]) if i >= 0 and i < count else 0


## Deposit idx of a map field id, -1 if none.
func idx_of_field(fid: int) -> int:
	return field_id.find(fid)


## Deposit idx whose field contains the cell (via the map's field layer), else the field with the nearest centre
## within `slack` sub-cells of the point, else -1.
func idx_at(map: MapData, px: int, py: int) -> int:
	var cx: int = clampi(px >> 10, 0, map.w - 1)
	var cy: int = clampi(py >> 10, 0, map.h - 1)
	var fid: int = map.field_of_cell(map.idx(cx, cy))
	if fid > 0:
		return idx_of_field(fid)
	var best: int = -1
	var best_d: int = 1 << 60
	for i: int in count:
		var d: int = Fp.dist(x[i] - px, y[i] - py)
		if d <= radius[i] + CELL and d < best_d:
			best = i
			best_d = d
	return best


## Removes up to `want` credits from the cell of field `i` nearest to `from_cell`; returns what was taken. Records the
## harvest tick; EVT_DEPOSIT_DEPLETED when the field runs dry.
func take(world: SimWorld, i: int, from_cell: int, want: int) -> int:
	var got: int = world.map.harvest_field(field_id[i], from_cell, want)
	if got <= 0:
		return 0
	last_harvest_tick[i] = world.tick
	if depleted[i] == 0 and world.map.field_remaining(field_id[i]) == 0:
		depleted[i] = 1
		world.emit(SimEconConst.EVT_DEPOSIT_DEPLETED, x[i], y[i], i)
	return got


## Stride 20 (called from the economy's stage 3): idle-only regrowth.
func update(world: SimWorld) -> void:
	if not regrow or world.tick % REGEN_STRIDE != 0:
		return
	for i: int in count:
		var st: int = world.map.field_remaining(field_id[i])
		if st >= cap[i]:
			continue
		if world.tick - last_harvest_tick[i] < regen_delay[i] or world.tick < next_regen_tick[i]:
			continue
		world.map.regrow_field(field_id[i], regen_amount[i])
		next_regen_tick[i] = world.tick + regen_period[i]
		if depleted[i] == 1 and world.map.field_remaining(field_id[i]) * 10 >= cap[i]:
			depleted[i] = 0
			world.emit(SimEconConst.EVT_DEPOSIT_REGROWN, x[i], y[i], i)


## Non-empty field nearest to (px, py) by centre distance (explored by `pid`, at least `min_stock` left); -1 if none.
func nearest(world: SimWorld, pid: int, px: int, py: int, min_stock: int) -> int:
	var best: int = -1
	var best_d: int = 1 << 60
	for i: int in count:
		if world.map.field_remaining(field_id[i]) < maxi(min_stock, 1):
			continue
		if pid >= 0 and not world.cell_explored(pid, x[i] >> 10, y[i] >> 10):
			continue
		var d: int = Fp.dist(x[i] - px, y[i] - py)
		if d < best_d:
			best = i
			best_d = d
	return best


func hash_into(buf: PackedInt32Array) -> void:
	if count == 0:
		return  # a map without deposit fields has no bookkeeping to protect
	buf.append(count)
	buf.append(search_tick)
	buf.append(search_used)
	for i: int in count:
		buf.append(harvesters[i])
		buf.append(last_harvest_tick[i])
		buf.append(next_regen_tick[i])
		buf.append(depleted[i])
