class_name SimDisc
extends RefCounted
## Integer disc tables for radii 0..32 (abilities 5.9.3): cell (dx, dy) is inside a disc of radius R iff
## dx*dx + dy*dy <= R*R; the row half-width is hw[R][dy] = isqrt(R*R - dy*dy), built once with Fp.isqrt (exact).
## Instance state of the owning system (DR-9: no static mutable state).

const MAX_R: int = 32
const ROW: int = 2 * MAX_R + 1  ## table stride: dy in -32..32

## hw[r * ROW + dy + MAX_R]; -1 where |dy| > r.
var hw: PackedInt32Array = PackedInt32Array()
## Number of cells of the disc of radius r.
var cells: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	hw.resize((MAX_R + 1) * ROW)
	hw.fill(-1)
	cells.resize(MAX_R + 1)
	for r: int in MAX_R + 1:
		var n: int = 0
		for dy: int in range(-r, r + 1):
			var half: int = Fp.isqrt(r * r - dy * dy)
			hw[r * ROW + dy + MAX_R] = half
			n += 2 * half + 1
		cells[r] = n


## Half width of row dy of the disc of radius r (-1 outside).
func half_width(r: int, dy: int) -> int:
	if r < 0 or r > MAX_R or dy < -MAX_R or dy > MAX_R:
		return -1
	return hw[r * ROW + dy + MAX_R]


## Number of cells of the disc of radius r.
func cell_count(r: int) -> int:
	return cells[clampi(r, 0, MAX_R)]


## Sight/detection radius in cells for a radius in units: (u + 512) >> 10, clamped to 1..32.
static func radius_cells(radius_u: int) -> int:
	return clampi((radius_u + 512) >> 10, 1, MAX_R)
