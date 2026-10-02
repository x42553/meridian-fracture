class_name Fp
extends RefCounted
## Fixed-point / integer math, all static (sim_core 3.2.2 / 5.1). Every sim number is an int; this is the only
## place that knows rounding rules, exact integer sqrt, Q16 trig and the load-time float -> int converters.
##
## TRAP: inside this file an UNQUALIFIED `sin(x)`, `cos(x)` or `atan2(y, x)` resolves to the FLOAT builtin, not to
## the static method of the same name. Internal code therefore reads `FpTables` directly or writes `Fp.sin(...)`;
## `self_test()` guards this.

const CELL: int = 1024
const CELL_SHIFT: int = 10
## Angle units per full turn (0 = +x / east, increasing toward +y / south).
const TURN: int = 4096
const ANGLE_MASK: int = 4095
const ANGLE_HALF: int = 2048
const ANGLE_QUARTER: int = 1024
const Q16: int = 65536
## 2^62 - 1: the largest argument of isqrt(); (r + 1)^2 for the result never overflows.
const ISQRT_MAX: int = 4611686018427387903

## Rounding modes of mul_div. HALF_UP rounds ties toward +infinity, HALF_AWAY ties away from zero.
enum Round { TRUNC = 0, FLOOR = 1, CEIL = 2, HALF_UP = 3, HALF_AWAY = 4 }

## Checksum.digest32 of FpTables.SIN_Q16 / ATAN_Q8 (checked by self_test and tools/py/gen_fp_tables.py).
const TABLE_DIGEST_SIN: int = 2046802713
const TABLE_DIGEST_ATAN: int = 1306073121


# ---- cells --------------------------------------------------------------------------------------------------

## Cell index of a coordinate (floor for negatives; hot loops inline `v >> 10`).
static func cell_of(v: int) -> int:
	return v >> 10


## Centre coordinate of cell c.
static func cell_center(c: int) -> int:
	return (c << 10) + 512


# ---- division, roots ----------------------------------------------------------------------------------------

## floor(a / b), b != 0.
static func floor_div(a: int, b: int) -> int:
	var q: int = a / b
	if q * b != a and (a ^ b) < 0:
		q -= 1
	return q


## a - floor_div(a, b) * b: takes the sign of b, 0 <= r < b for b > 0. b != 0.
static func floor_mod(a: int, b: int) -> int:
	var m: int = a % b
	if m != 0 and (m ^ b) < 0:
		m += b
	return m


## ceil(a / b), b != 0.
static func ceil_div(a: int, b: int) -> int:
	var q: int = a / b
	if q * b != a and (a ^ b) >= 0:
		q += 1
	return q


## EXACT floor(sqrt(n)), n clamped to [0, ISQRT_MAX]. The float seed is corrected by two integer loops, so the
## result is independent of any float behaviour.
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	if n > ISQRT_MAX:
		n = ISQRT_MAX
	var r: int = int(sqrt(float(n)))  # lint-allow: L003 float seed only; the two integer loops below make the result exact
	while r * r > n:
		r -= 1
	while (r + 1) * (r + 1) <= n:
		r += 1
	return r


## dx*dx + dy*dy (|dx|, |dy| < 2^30).
static func dist2(dx: int, dy: int) -> int:
	return dx * dx + dy * dy


## Floor Euclidean distance. Prefer `dist2(...) <= r * r` for comparisons.
static func dist(dx: int, dy: int) -> int:
	return isqrt(dx * dx + dy * dy)


# ---- rounding multiply-divide, percentages ------------------------------------------------------------------

## a * b / c with the given rounding (c != 0, |a * b| < 2^62).
static func mul_div(a: int, b: int, c: int, mode: int = Round.HALF_UP) -> int:
	var n: int = a * b
	var d: int = c
	if d < 0:
		n = -n
		d = -d
	var q: int = n / d
	var r: int = n - q * d  # sign of n, |r| < d
	if r == 0 or mode == Round.TRUNC:
		return q
	if mode == Round.FLOOR:
		return q - 1 if r < 0 else q
	if mode == Round.CEIL:
		return q + 1 if r > 0 else q
	if mode == Round.HALF_UP:
		if r < 0:
			q -= 1
			r += d
		return q + 1 if 2 * r >= d else q
	# HALF_AWAY
	if r > 0:
		return q + 1 if 2 * r >= d else q
	return q - 1 if -2 * r >= d else q


## v * p / 100, half up.
static func pct(v: int, p: int) -> int:
	if v >= 0 and p >= 0:
		return (v * p + 50) / 100
	return mul_div(v, p, 100, Round.HALF_UP)


## base * (100 + delta_pct) / 100, half up.
static func apply_pct(base: int, delta_pct: int) -> int:
	return mul_div(base, 100 + delta_pct, 100, Round.HALF_UP)


## The bible's layered-modifier formula final = base * PROD(1 + layer_sum) with ONE sequential half-up rounding per
## layer. `layers_bp` are the per-layer delta sums in basis points; optional floors / caps as percent of base
## (0 = unused). Overflow-free for base <= 10^6 and <= 4 layers of |sum| <= 200 %.
static func apply_layers(base: int, layers_bp: PackedInt32Array, min_pct_of_base: int = 0, max_pct_of_base: int = 0) -> int:
	var acc: int = base * 10000
	for i: int in layers_bp.size():
		acc = mul_div(acc, 10000 + layers_bp[i], 10000, Round.HALF_UP)
	var res: int = floor_div(acc + 5000, 10000)
	if min_pct_of_base > 0:
		res = maxi(res, mul_div(base, min_pct_of_base, 100, Round.CEIL))
	if max_pct_of_base > 0:
		res = mini(res, mul_div(base, max_pct_of_base, 100, Round.FLOOR))
	return res


@warning_ignore("shadowed_global_identifier")
static func clamp(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v


## a + (b - a) * num / den, half up.
static func lerp_i(a: int, b: int, num: int, den: int) -> int:
	return a + mul_div(b - a, num, den, Round.HALF_UP)


## Moves v toward target by at most step (step >= 0).
static func approach(v: int, target: int, step: int) -> int:
	if v < target:
		return mini(v + step, target)
	return maxi(v - step, target)


## (a * q + 32768) >> 16: a times a Q16 factor, rounded half up (arithmetic shift).
static func mul_q16(a: int, q: int) -> int:
	return (a * q + 32768) >> 16


# ---- trigonometry (Q16 table, integer atan2) ------------------------------------------------------------------

## Q16 sine of a binary angle (any int, masked to 0..4095).
@warning_ignore("shadowed_global_identifier")
static func sin(a: int) -> int:
	return FpTables.SIN_Q16[a & 4095]


## Q16 cosine of a binary angle.
@warning_ignore("shadowed_global_identifier")
static func cos(a: int) -> int:
	return FpTables.SIN_Q16[(a + 1024) & 4095]


## Ratio angle for 0 <= mn <= mx, mx > 0: 0..512 (45 degrees = 512 units), linear interpolation in ATAN_Q8.
static func _atan_ratio(mn: int, mx: int) -> int:
	var t: int = (mn << 16) / mx
	if t >= 65536:
		return 512
	var i: int = t >> 6
	var f: int = t & 63
	var a0: int = FpTables.ATAN_Q8[i]
	return (a0 + (((FpTables.ATAN_Q8[i + 1] - a0) * f) >> 6) + 128) >> 8


## Binary angle 0..4095 of the vector (dx, dy); atan2(0, 0) = 0.
@warning_ignore("shadowed_global_identifier")
static func atan2(dy: int, dx: int) -> int:
	if dx == 0 and dy == 0:
		return 0
	var ax: int = absi(dx)
	var ay: int = absi(dy)
	var a: int = _atan_ratio(ay, ax) if ay <= ax else 1024 - _atan_ratio(ax, ay)
	if dx >= 0:
		return a if dy >= 0 else (4096 - a) & 4095
	return (2048 - a) if dy >= 0 else (2048 + a)


static func angle_between(x0: int, y0: int, x1: int, y1: int) -> int:
	return Fp.atan2(y1 - y0, x1 - x0)


## a & 4095.
static func angle_norm(a: int) -> int:
	return a & 4095


## Shortest signed difference to_a - from_a in [-2048, 2047].
static func angle_diff(from_a: int, to_a: int) -> int:
	return ((to_a - from_a + 2048) & 4095) - 2048


## Rotates cur toward target by at most max_step (max_step >= 0); returns 0..4095.
static func turn_toward(cur: int, target: int, max_step: int) -> int:
	var d: int = angle_diff(cur, target)
	if d >= -max_step and d <= max_step:
		return target & 4095
	return (cur + max_step if d > 0 else cur - max_step) & 4095


## x component of the offset (ox, oy) rotated by angle a, rounded half up.
static func rot_x(ox: int, oy: int, a: int) -> int:
	return (ox * Fp.cos(a) - oy * Fp.sin(a) + 32768) >> 16


## y component of the offset (ox, oy) rotated by angle a, rounded half up.
static func rot_y(ox: int, oy: int, a: int) -> int:
	return (ox * Fp.sin(a) + oy * Fp.cos(a) + 32768) >> 16


## Displacement x of a step of length d along angle.
static func step_x(angle: int, d: int) -> int:
	return mul_q16(d, Fp.cos(angle))


## Displacement y of a step of length d along angle.
static func step_y(angle: int, d: int) -> int:
	return mul_q16(d, Fp.sin(angle))


# ---- load-time converters (DR-10: the ONLY place a float touches a sim number) ---------------------------------

## The single float -> int rounding step: roundi(f * 1000).
static func milli(f: float) -> int:  # lint-allow: L003 load-time float entry point (DR-10)
	return roundi(f * 1000.0)  # lint-allow: L003 one IEEE multiplication + round, identical on every platform


## Milli-cells -> sub-cell units, half up.
static func cells_to_units(milli_cells: int) -> int:
	return floor_div(milli_cells * 1024 + 500, 1000)


## Milli-seconds -> ticks (TPS = 20), rounded up.
static func seconds_to_ticks(milli_seconds: int) -> int:
	return ceil_div(milli_seconds * 20, 1000)


## Milli-cells per second -> units per tick, half up.
static func cps_to_units_per_tick(milli_cps: int) -> int:
	return floor_div(milli_cps * 1024 + 10000, 20000)


# ---- self test --------------------------------------------------------------------------------------------------

## Guards the engine facts this class relies on (sim_core 8.4). Returns the failure messages; [] = OK.
## Call at boot and in tests.
static func self_test() -> PackedStringArray:
	var bad: PackedStringArray = PackedStringArray()
	var m7: int = -7
	var p7: int = 7
	var two: int = 2
	var three: int = 3
	var neg_two: int = -2
	if m7 / two != -3 or p7 / neg_two != -3:
		bad.append("integer division must truncate toward zero")
	if m7 % three != -1 or p7 % -three != 1:
		bad.append("% must keep the dividend's sign")
	if floor_div(m7, two) != -4 or floor_mod(m7, three) != 2 or ceil_div(m7, two) != -3:
		bad.append("floor_div / floor_mod / ceil_div")
	var neg: int = -1025
	var sh: int = 10
	if (neg >> sh) != -2:
		bad.append(">> on negative ints must be arithmetic")
	if (1 << (sh + 42)) != 4503599627370496:
		bad.append("<< on int64")
	if Fp.sin(1) != 101 or Fp.cos(0) != 65536 or Fp.sin(1024) != 65536 or Fp.sin(-1) != -101:
		bad.append("Fp.sin/Fp.cos must read the table (unqualified sin/cos are the float builtins)")
	if Fp.atan2(1, 1) != 512 or Fp.atan2(-1, -1) != 2560:
		bad.append("Fp.atan2 octant reduction")
	if isqrt(ISQRT_MAX) != 2147483647 or isqrt(-5) != 0 or isqrt(99) != 9 or isqrt(100) != 10:
		bad.append("isqrt must be exact")
	if mul_div(-7, 1, 2, Round.HALF_UP) != -3 or mul_div(-7, 1, 2, Round.HALF_AWAY) != -4:
		bad.append("mul_div rounding modes")
	if Checksum.digest32(FpTables.SIN_Q16) != TABLE_DIGEST_SIN:
		bad.append("SIN_Q16 digest mismatch")
	if Checksum.digest32(FpTables.ATAN_Q8) != TABLE_DIGEST_ATAN:
		bad.append("ATAN_Q8 digest mismatch")
	var a: PackedInt32Array = PackedInt32Array([1])
	var alias: PackedInt32Array = a
	alias.append(2)
	if a.size() != 2:
		bad.append("PackedInt32Array must be a reference type")
	var w: PackedInt32Array = PackedInt32Array()
	w.append(0x80000000)
	if w[0] != -2147483648:
		bad.append("PackedInt32Array.append must wrap modulo 2^32")
	if Checksum.digest32(PackedInt32Array()) != Checksum.EMPTY_DIGEST:
		bad.append("empty digest")
	return bad
