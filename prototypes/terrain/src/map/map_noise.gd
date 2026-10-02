class_name MapNoise
extends RefCounted
## Integer-only hashing and fixed-point helpers for deterministic map generation
## (Architecture DR-1/DR-4: no floats, identical results on every platform).
## Conventions: Q8 = value * 256 (coordinates in cells); Q16 = value * 65536 (fractions, noise 0..65535).

const Q16: int = 65536


## 32-bit avalanche hash of a lattice point. All intermediates stay below 2^63 (no signed overflow).
static func hash2(ix: int, iy: int, seed_value: int) -> int:
	var h: int = ((ix * 73856093) ^ (iy * 19349663) ^ (seed_value * 83492791)) & 0xFFFFFFFF
	h = (((h >> 16) ^ h) * 0x45D9F3B) & 0xFFFFFFFF
	h = (((h >> 16) ^ h) * 0x45D9F3B) & 0xFFFFFFFF
	return ((h >> 16) ^ h) & 0xFFFFFFFF


## Smoothstep of x between e0 and e1, result in Q16 (0..65536). Arguments share any fixed-point unit.
static func smooth_q16(x: int, e0: int, e1: int) -> int:
	if x <= e0:
		return 0
	if x >= e1:
		return Q16
	var t: int = ((x - e0) << 16) / (e1 - e0)
	var t2: int = (t * t) >> 16
	return (t2 * (196608 - 2 * t)) >> 16


## a + (b - a) * t with t in Q16. Integer division truncates toward zero (DR-5), so it is deterministic.
static func lerp_q16(a: int, b: int, t: int) -> int:
	return a + (((b - a) * t) / Q16)


## Exact floor(sqrt(n)) for 0 <= n < 2^62.
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x: int = n
	var y: int = (x + 1) >> 1
	while y < x:
		x = y
		y = (x + n / x) >> 1
	return x


## Distance from point P to segment AB, all in Q8 cells; result in Q8 cells.
static func dist_point_segment(px: int, py: int, ax: int, ay: int, bx: int, by: int) -> int:
	var abx: int = bx - ax
	var aby: int = by - ay
	var ab2: int = abx * abx + aby * aby
	var t: int = 0
	if ab2 > 0:
		t = clampi(((px - ax) * abx + (py - ay) * aby) * Q16 / ab2, 0, Q16)
	var qx: int = ax + (abx * t) / Q16
	var qy: int = ay + (aby * t) / Q16
	var dx: int = px - qx
	var dy: int = py - qy
	return isqrt(dx * dx + dy * dy)
