class_name SimCoverGrid
extends RefCounted
## Counted coverage grid (abilities 3.6 / 5.9.4): every stamp adds +1 to the cells of a disc (or capsule), every
## unstamp -1, so overlapping sources never lose cells. Cells that change between 0 and positive are reported to an
## optional Sink (cell * 2 + 1 for 0 -> positive, cell * 2 for positive -> 0, in the order they happened) and folded
## into `digest`, the XOR of zob(cell) over all covered cells (abilities 8.3). `move_disc` touches only the cells that
## enter / leave (row spans), so a one-cell step of an R = 8 disc costs about 34 writes.

const _M32: int = 0xFFFFFFFF

## Transition sink: `cells` gets cell * 2 + positive for every 0 <-> positive change.
class Sink:
	extends RefCounted
	var cells: PackedInt32Array = PackedInt32Array()

	func clear() -> void:
		cells.resize(0)

var w: int = 0
var h: int = 0
var counts: PackedInt32Array = PackedInt32Array()
var digest: int = 0  ## XOR of zob(cell) over cells with count > 0, in [0, 2^32)
var disc: SimDisc = null
## Counters for the budget tests (never wall time).
var stat_cells_written: int = 0
var stat_transitions: int = 0


func _init(width: int, height: int, disc_tables: SimDisc) -> void:
	w = width
	h = height
	disc = disc_tables
	counts.resize(width * height)


static func zob(cell: int) -> int:
	return mix32(cell * 0x9E3779B1 + 0x7F4A7C15)


## abilities 8.3: all arithmetic masked to 32 bits inside 64-bit ints.
static func mix32(v: int) -> int:
	v &= _M32
	v ^= v >> 16
	v = (v * 0x7FEB352D) & _M32
	v ^= v >> 15
	v = (v * 0x846CA68B) & _M32
	v ^= v >> 16
	return v


func count_at(cell: int) -> int:
	return counts[cell]


func count_xy(cx: int, cy: int) -> int:
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return 0
	return counts[cy * w + cx]


## Zeroes the grid (digest 0). Transitions are not reported.
func clear() -> void:
	counts.fill(0)
	digest = 0


## +1 (sgn > 0) or -1 (sgn < 0) on every cell of the disc of radius r cells around (cx, cy).
func stamp_disc(cx: int, cy: int, r: int, sgn: int, sink: Sink = null) -> void:
	var y0: int = maxi(cy - r, 0)
	var y1: int = mini(cy + r, h - 1)
	var hwt: PackedInt32Array = disc.hw
	var base: int = r * SimDisc.ROW + SimDisc.MAX_R - cy
	for y: int in range(y0, y1 + 1):
		var half: int = hwt[base + y]
		_span(y * w, maxi(cx - half, 0), mini(cx + half, w - 1), sgn, sink)


## Moves a disc of radius r from (ocx, ocy) to (ncx, ncy): only the symmetric difference is written.
func move_disc(ocx: int, ocy: int, ncx: int, ncy: int, r: int, sink: Sink = null) -> void:
	if ocx == ncx and ocy == ncy:
		return
	var ya: int = ocy - r
	var yb: int = ocy + r
	var yc: int = ncy - r
	var yd: int = ncy + r
	var hwt: PackedInt32Array = disc.hw
	var rb: int = r * SimDisc.ROW + SimDisc.MAX_R
	var top: int = maxi(mini(ya, yc), 0)
	var bot: int = mini(maxi(yb, yd), h - 1)
	var ww: int = w - 1
	for y: int in range(top, bot + 1):
		var a0: int = 1
		var a1: int = 0
		var b0: int = 1
		var b1: int = 0
		if y >= ya and y <= yb:
			var ha: int = hwt[rb + y - ocy]
			a0 = ocx - ha
			a1 = ocx + ha
		if y >= yc and y <= yd:
			var hb: int = hwt[rb + y - ncy]
			b0 = ncx - hb
			b1 = ncx + hb
		var base: int = y * w
		if a1 < a0:
			_span(base, maxi(b0, 0), mini(b1, ww), 1, sink)
		elif b1 < b0:
			_span(base, maxi(a0, 0), mini(a1, ww), -1, sink)
		elif b1 < a0 or b0 > a1:
			_span(base, maxi(a0, 0), mini(a1, ww), -1, sink)
			_span(base, maxi(b0, 0), mini(b1, ww), 1, sink)
		else:
			if a0 < b0:
				_span(base, maxi(a0, 0), mini(b0 - 1, ww), -1, sink)
			elif b0 < a0:
				_span(base, maxi(b0, 0), mini(a0 - 1, ww), 1, sink)
			if a1 > b1:
				_span(base, maxi(b1 + 1, 0), mini(a1, ww), -1, sink)
			elif b1 > a1:
				_span(base, maxi(a1 + 1, 0), mini(b1, ww), 1, sink)


## Capsule: the cells whose centre lies within half_w_u (units) of the segment (x0, y0)-(x1, y1) (units).
func stamp_capsule(x0: int, y0: int, x1: int, y1: int, half_w_u: int, sgn: int, sink: Sink = null) -> void:
	var c0: int = maxi(mini(x0, x1) - half_w_u, 0) >> 10
	var c1: int = mini((maxi(x0, x1) + half_w_u) >> 10, w - 1)
	var r0: int = maxi(mini(y0, y1) - half_w_u, 0) >> 10
	var r1: int = mini((maxi(y0, y1) + half_w_u) >> 10, h - 1)
	for cy: int in range(r0, r1 + 1):
		var py: int = cy * 1024 + 512
		for cx: int in range(c0, c1 + 1):
			if SimShape.capsule_contains(x0, y0, x1, y1, half_w_u, cx * 1024 + 512, py):
				_span(cy * w, cx, cx, sgn, sink)


## Row span [x0, x1] (already clamped) of row base `base`.
func _span(base: int, x0: int, x1: int, sgn: int, sink: Sink) -> void:
	if x1 < x0:
		return
	stat_cells_written += x1 - x0 + 1
	var c: PackedInt32Array = counts
	if sgn > 0:
		for i: int in range(base + x0, base + x1 + 1):
			var v: int = c[i]
			c[i] = v + 1
			if v == 0:
				digest ^= zob(i)
				stat_transitions += 1
				if sink != null:
					sink.cells.append(i * 2 + 1)
	else:
		for i: int in range(base + x0, base + x1 + 1):
			var v2: int = c[i]
			c[i] = v2 - 1
			if v2 == 1:
				digest ^= zob(i)
				stat_transitions += 1
				if sink != null:
					sink.cells.append(i * 2)
