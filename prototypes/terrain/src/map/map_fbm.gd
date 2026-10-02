class_name MapFbm
extends RefCounted
## Lattice-cached fractal value noise over a bounded cell grid (integer only).
## Build cost is one hash per lattice point; sampling is 4 array reads + integer lerps per octave.
## Output is Q16 (0..65535). Coordinates are Q8 cells, clamped to the map.

var _octaves: int = 0
var _spacing_q8: PackedInt32Array = PackedInt32Array()
var _stride: PackedInt32Array = PackedInt32Array()
var _amp: PackedInt32Array = PackedInt32Array()
var _grids: Array[PackedInt32Array] = []
var _norm: int = 1
var _max_x: int = 0
var _max_y: int = 0


## base_spacing_cells is the lattice spacing of octave 0; each further octave halves it (min 1 cell).
func setup(seed_value: int, map_w: int, map_h: int, base_spacing_cells: int, octaves: int) -> MapFbm:
	_octaves = octaves
	_max_x = map_w * 256
	_max_y = map_h * 256
	var amp: int = 32768
	_norm = 0
	for o in octaves:
		var sp: int = maxi(1, base_spacing_cells >> o)
		var gw: int = map_w / sp + 3
		var gh: int = map_h / sp + 3
		var g: PackedInt32Array = PackedInt32Array()
		g.resize(gw * gh)
		var s: int = seed_value + o * 1013
		for j in gh:
			for i in gw:
				g[j * gw + i] = MapNoise.hash2(i, j, s) & 0xFFFF
		_grids.append(g)
		_spacing_q8.append(sp * 256)
		_stride.append(gw)
		_amp.append(amp)
		_norm += amp
		amp = amp >> 1
	return self


## Q16 noise (0..65535) at Q8 cell coordinates.
func sample_q8(x_q8: int, y_q8: int) -> int:
	x_q8 = clampi(x_q8, 0, _max_x)
	y_q8 = clampi(y_q8, 0, _max_y)
	var sum: int = 0
	for o in _octaves:
		var sp: int = _spacing_q8[o]
		var ix: int = x_q8 / sp
		var iy: int = y_q8 / sp
		var fx: int = ((x_q8 - ix * sp) << 16) / sp
		var fy: int = ((y_q8 - iy * sp) << 16) / sp
		fx = (((fx * fx) >> 16) * (196608 - 2 * fx)) >> 16
		fy = (((fy * fy) >> 16) * (196608 - 2 * fy)) >> 16
		var st: int = _stride[o]
		var g: PackedInt32Array = _grids[o]
		var i0: int = iy * st + ix
		var top: int = (g[i0] * (65536 - fx) + g[i0 + 1] * fx) >> 16
		var bot: int = (g[i0 + st] * (65536 - fx) + g[i0 + st + 1] * fx) >> 16
		var v: int = (top * (65536 - fy) + bot * fy) >> 16
		sum += (v * _amp[o]) >> 16
	return mini((sum << 16) / _norm, 65535)
