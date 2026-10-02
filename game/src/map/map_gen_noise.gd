class_name MapGenNoise
extends RefCounted
## Integer noise of the map generator (terrain_movement 5.12.2): mix32 hash, lattice value noise, fBm, percentile
## helpers. The static functions are the exact reference (test vectors U1). `Field` is the lattice-cached
## implementation used by phase A: it hashes every lattice node once and reads them back, and returns
## BIT-IDENTICAL values (an allowed optimisation, spec 5.12.2). Integer only, no state outside instances.


## 32-bit avalanche hash of (x, y, s); intermediates stay below 2^63 for s < 2^32 and |x|, |y| < 2^20.
static func mix32(x: int, y: int, s: int) -> int:
	var h: int = (x * 374761393 + y * 668265263 + s * 1274126177 + 1013904223) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFFFFFF


static func hash2(x: int, y: int, s: int) -> int:
	return mix32(x, y, s) & 0xFFFF


## Smoothstep weight (Q16) of a lattice fraction; `frac` in [0, 2^shift). Same expression as vnoise().
static func smooth_of(frac: int, shift: int) -> int:
	var f: int = (frac << 16) >> shift
	return (((3 << 16) - 2 * f) * f >> 16) * f >> 16


## Value noise 0..65535, lattice spacing 2^shift, smoothstep in Q16 (reference implementation).
static func vnoise(x: int, y: int, shift: int, s: int) -> int:
	var cs: int = 1 << shift
	var xi: int = x >> shift
	var yi: int = y >> shift
	var sx: int = smooth_of(x & (cs - 1), shift)
	var sy: int = smooth_of(y & (cs - 1), shift)
	var a: int = hash2(xi, yi, s)
	var b: int = hash2(xi + 1, yi, s)
	var c: int = hash2(xi, yi + 1, s)
	var d: int = hash2(xi + 1, yi + 1, s)
	var top: int = a + (((b - a) * sx) >> 16)
	var bot: int = c + (((d - c) * sx) >> 16)
	return top + (((bot - top) * sy) >> 16)


## 4 octaves, weights 8, 4, 2, 1, divided by 15 (non-negative division: truncation is exact).
static func fbm(x: int, y: int, s: int, base_shift: int) -> int:
	return (vnoise(x, y, base_shift, s) * 8 + vnoise(x, y, base_shift - 1, s + 1) * 4
		+ vnoise(x, y, base_shift - 2, s + 2) * 2 + vnoise(x, y, base_shift - 3, s + 3)) / 15


## Smallest t in 0..255 with count(value > t) <= target ("top target cells"); 255 when target is 0.
static func top_threshold(hist: PackedInt32Array, target: int) -> int:
	var above: int = 0
	for t: int in range(255, -1, -1):
		if above + hist[t] > target:
			return t
		above += hist[t]
	return 0


## Smallest bin k with count(value <= k) >= target; the last bin when the total is below target.
static func low_threshold(hist: PackedInt32Array, target: int) -> int:
	var cum: int = 0
	for k: int in hist.size():
		cum += hist[k]
		if cum >= target:
			return k
	return hist.size() - 1


## Lattice-cached vnoise (octaves == 1) or fbm (octaves == 4) over a bounded sample domain.
## `at(x, y)` == MapGenNoise.vnoise(x, y, shift, s) / MapGenNoise.fbm(x, y, s, shift) for every (x, y) inside
## [x0, x1] x [y0, y1] (inclusive, the coordinates passed to the reference functions).
class Field extends RefCounted:
	var _n: int = 0
	var _wsum: int = 1
	var _shift: PackedInt32Array = PackedInt32Array()
	var _mask: PackedInt32Array = PackedInt32Array()
	var _xi0: PackedInt32Array = PackedInt32Array()
	var _yi0: PackedInt32Array = PackedInt32Array()
	var _stride: PackedInt32Array = PackedInt32Array()
	var _wt: PackedInt32Array = PackedInt32Array()
	var _grid: Array[PackedInt32Array] = []
	var _sm: Array[PackedInt32Array] = []

	static func vnoise_field(x0: int, x1: int, y0: int, y1: int, shift: int, s: int) -> Field:
		var f: Field = Field.new()
		f._add(x0, x1, y0, y1, shift, s, 1)
		f._wsum = 1
		return f

	static func fbm_field(x0: int, x1: int, y0: int, y1: int, s: int, base_shift: int) -> Field:
		var f: Field = Field.new()
		for o: int in 4:
			f._add(x0, x1, y0, y1, base_shift - o, s + o, 8 >> o)
		f._wsum = 15
		return f

	func _add(x0: int, x1: int, y0: int, y1: int, shift: int, s: int, wt: int) -> void:
		var xa: int = x0 >> shift
		var ya: int = y0 >> shift
		var gw: int = (x1 >> shift) - xa + 2
		var gh: int = (y1 >> shift) - ya + 2
		var g: PackedInt32Array = PackedInt32Array()
		g.resize(gw * gh)
		for j: int in gh:
			for i: int in gw:
				g[j * gw + i] = MapGenNoise.hash2(xa + i, ya + j, s)
		var sm: PackedInt32Array = PackedInt32Array()
		sm.resize(1 << shift)
		for fr: int in 1 << shift:
			sm[fr] = MapGenNoise.smooth_of(fr, shift)
		_shift.append(shift)
		_mask.append((1 << shift) - 1)
		_xi0.append(xa)
		_yi0.append(ya)
		_stride.append(gw)
		_wt.append(wt)
		_grid.append(g)
		_sm.append(sm)
		_n += 1

	func at(x: int, y: int) -> int:
		var acc: int = 0
		for o: int in _n:
			var sh: int = _shift[o]
			var m: int = _mask[o]
			var sm: PackedInt32Array = _sm[o]
			var sx: int = sm[x & m]
			var sy: int = sm[y & m]
			var st: int = _stride[o]
			var i0: int = ((y >> sh) - _yi0[o]) * st + (x >> sh) - _xi0[o]
			var g: PackedInt32Array = _grid[o]
			var a: int = g[i0]
			var c: int = g[i0 + st]
			var top: int = a + (((g[i0 + 1] - a) * sx) >> 16)
			var bot: int = c + (((g[i0 + st + 1] - c) * sx) >> 16)
			acc += (top + (((bot - top) * sy) >> 16)) * _wt[o]
		return acc / _wsum
