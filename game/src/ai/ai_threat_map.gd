class_name AiThreatMap
extends RefCounted
## 8-cell-block threat / influence grid with lazy decay (ai.md 4.2 / 5.3.3). A SWEEP accumulates the armed enemies seen
## (`add_sighting`) into a frame; `commit(tick)` stores per block max(decayed stored, frame) and stamps the tick. Read value
## v(t) = threat x max(0, decay - (t - stamp)) / decay (integer, linear decay over 600 ticks).

var block_shift: int = 13  ## 8 cells x 1024 = 8192 = 1 << 13
var decay_ticks: int = 600
var bw: int = 0
var bh: int = 0
var threat: PackedInt32Array = PackedInt32Array()
var stamp: PackedInt32Array = PackedInt32Array()
var _frame: PackedInt32Array = PackedInt32Array()
var _touched: PackedInt32Array = PackedInt32Array()


func setup(map_w_cells: int, map_h_cells: int, p_block_shift: int = 13, p_decay: int = 600) -> void:
	block_shift = p_block_shift
	decay_ticks = maxi(1, p_decay)
	var cells_per_block: int = (1 << block_shift) / Fp.CELL
	bw = (map_w_cells + cells_per_block - 1) / cells_per_block
	bh = (map_h_cells + cells_per_block - 1) / cells_per_block
	threat.resize(bw * bh)
	threat.fill(0)
	stamp.resize(bw * bh)
	stamp.fill(-1000000)
	_frame.resize(bw * bh)
	_frame.fill(0)
	_touched.resize(0)


func block_of(x: int, y: int) -> int:
	var bx: int = clampi(x >> block_shift, 0, bw - 1)
	var by: int = clampi(y >> block_shift, 0, bh - 1)
	return by * bw + bx


## Accumulates `power` at (x, y) into the current sweep frame.
func add_sighting(x: int, y: int, power: int) -> void:
	if bw == 0 or power <= 0:
		return
	var b: int = block_of(x, y)
	if _frame[b] == 0:
		_touched.append(b)
	_frame[b] += power


## Ends a sweep at `tick`: stored = max(decayed stored, frame) for every block the frame touched.
func commit(tick: int) -> void:
	for b: int in _touched:
		var decayed: int = value_of_block(b, tick)
		threat[b] = maxi(decayed, _frame[b])
		stamp[b] = tick
		_frame[b] = 0
	_touched.resize(0)


func value_of_block(b: int, tick: int) -> int:
	var age: int = tick - stamp[b]
	if age >= decay_ticks:
		return 0
	return threat[b] * (decay_ticks - maxi(age, 0)) / decay_ticks


## Threat at a point.
func at(x: int, y: int, tick: int) -> int:
	if bw == 0:
		return 0
	return value_of_block(block_of(x, y), tick)


## Sum over the blocks overlapped by the circle (<= 9 blocks for r <= 12 cells).
func circle(x: int, y: int, r: int, tick: int) -> int:
	if bw == 0:
		return 0
	var bx0: int = clampi((x - r) >> block_shift, 0, bw - 1)
	var bx1: int = clampi((x + r) >> block_shift, 0, bw - 1)
	var by0: int = clampi((y - r) >> block_shift, 0, bh - 1)
	var by1: int = clampi((y + r) >> block_shift, 0, bh - 1)
	var s: int = 0
	for by: int in range(by0, by1 + 1):
		for bx: int in range(bx0, bx1 + 1):
			s += value_of_block(by * bw + bx, tick)
	return s


## Writes a block value directly (defensive structures known from ghosts keep the map warm).
func write(x: int, y: int, power: int, tick: int) -> void:
	if bw == 0:
		return
	var b: int = block_of(x, y)
	threat[b] = maxi(value_of_block(b, tick), power)
	stamp[b] = tick


func state_hash() -> int:
	var n: int = 0
	for b: int in threat.size():
		if threat[b] != 0:
			n += 1
	return AiRng.mix32(n * 13 + bw * bh)
