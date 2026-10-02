class_name MapGenSymmetry
extends RefCounted
## Symmetry groups of the map generator (terrain_movement 5.12.3): doubled coordinates, image points, the fold into
## the noise domain, exact integer painting primitives (disc / segment / rectangle) and the canonical start anchors.
##
## Doubled coordinates: x2 = 2x + 1 - w, y2 = 2y + 1 - h (odd; the map centre is (0, 0)); the cell of a doubled point
## p is (p + w - 1) >> 1. Exact groups: D1X (2 slots), D2 (4), D4 (8). Rotation groups DN (3, 6 slots) are symmetric
## to about one cell. Integer only.

const G_D1X: int = 0
const G_D2: int = 1
const G_D4: int = 2
const G_DN: int = 3
const FOLD_V_OFF: int = 1024  ## packed fold: ((fv + FOLD_V_OFF) << 16) | fu

var slots: int = 2
var size: int = 128
var group: int = G_D1X
var images: int = 2  ## number of images == slots
var half: int = 64  ## R = size / 2
## bounds of the fold domain (fu, fv) so noise lattices / memo tables can be sized once
var fu_min: int = 0
var fu_max: int = 0
var fv_min: int = 0
var fv_max: int = 0
var _rot_c: PackedInt32Array = PackedInt32Array()  ## DN: Q16 cos / sin of image k's rotation
var _rot_s: PackedInt32Array = PackedInt32Array()


static func group_of(p_slots: int) -> int:
	match p_slots:
		2:
			return G_D1X
		4:
			return G_D2
		8:
			return G_D4
	return G_DN


func _init(p_slots: int = 2, p_size: int = 128) -> void:
	slots = p_slots
	size = p_size
	half = p_size / 2
	group = group_of(p_slots)
	images = p_slots
	match group:
		G_D1X:
			fu_min = 0
			fu_max = half - 1
			fv_min = -half
			fv_max = half - 1
		G_D2, G_D4:
			fu_min = 0
			fu_max = half - 1
			fv_min = 0
			fv_max = half - 1
		_:
			var rmax: int = Fp.isqrt(2 * (size - 1) * (size - 1))
			fu_min = 0
			fu_max = (rmax >> 1) + 2
			fv_min = 0
			fv_max = (rmax >> 1) + 2
			for k: int in images:
				var a: int = k * Fp.TURN / images
				_rot_c.append(Fp.cos(a))
				_rot_s.append(Fp.sin(a))


## True for D1X / D2 / D4 (bit-exact images), false for the rotation groups.
func is_exact() -> bool:
	return group != G_DN


func cell_of2(p2: int) -> int:
	return (p2 + size - 1) >> 1


## Doubled coordinate of the cell centre.
func to2(c: int) -> int:
	return 2 * c + 1 - size


## Image k of the doubled point (x2, y2): x component / y component.
func img_x(k: int, x2: int, y2: int) -> int:
	match group:
		G_D1X:
			return -x2 if (k & 1) != 0 else x2
		G_D2, G_D4:
			var ax: int = -x2 if (k & 1) != 0 else x2
			var ay: int = -y2 if (k & 2) != 0 else y2
			return ay if group == G_D4 and (k & 4) != 0 else ax
	return (x2 * _rot_c[k] - y2 * _rot_s[k] + 32768) >> 16


func img_y(k: int, x2: int, y2: int) -> int:
	match group:
		G_D1X:
			return y2
		G_D2, G_D4:
			var ax: int = -x2 if (k & 1) != 0 else x2
			var ay: int = -y2 if (k & 2) != 0 else y2
			return ax if group == G_D4 and (k & 4) != 0 else ay
	return (x2 * _rot_s[k] + y2 * _rot_c[k] + 32768) >> 16


## True if image k swaps the axes (D4 swap bit): half extents of axis-aligned rectangles swap.
func img_swaps(k: int) -> bool:
	return group == G_D4 and (k & 4) != 0


## Fold of a doubled point into the noise domain (packed, see fold_u / fold_v). Every terrain-affecting per-cell
## random value must use (fu, fv), never raw (x, y).
func fold(x2: int, y2: int) -> int:
	var fu: int = 0
	var fv: int = 0
	match group:
		G_D1X:
			fu = (absi(x2) - 1) >> 1
			fv = y2 >> 1
		G_D2:
			fu = (absi(x2) - 1) >> 1
			fv = (absi(y2) - 1) >> 1
		G_D4:
			var a: int = (absi(x2) - 1) >> 1
			var b: int = (absi(y2) - 1) >> 1
			fu = maxi(a, b)
			fv = mini(a, b)
		_:
			var ang: int = Fp.atan2(y2, x2)
			var t: int = (ang * slots) & 4095
			if t > 2047:
				t = 4095 - t
			var a2: int = t / slots
			var r: int = Fp.isqrt(x2 * x2 + y2 * y2)
			fu = (r * Fp.cos(a2)) >> 17
			fv = (r * Fp.sin(a2)) >> 17
	return ((fv + FOLD_V_OFF) << 16) | fu


static func fold_u(packed: int) -> int:
	return packed & 0xFFFF


static func fold_v(packed: int) -> int:
	return (packed >> 16) - FOLD_V_OFF


# ---- painting primitives (exact integer predicates, clipped to the playable interior) -------------------------------
# Each appends the covered cell indices (ascending scan order, each once) of image k of the primitive with canonical
# control points in doubled coordinates. The control points are transformed per image; the predicate is then
# evaluated exactly, so exact-group images are bit-mirror images and rotation images are hole-free.

func _clip_lo(v2: int, r2: int) -> int:
	return clampi(((v2 - r2 + size - 1) >> 1) - 1, MapData.RIM_W, size - MapData.RIM_W)


func _clip_hi(v2: int, r2: int) -> int:
	return clampi(((v2 + r2 + size - 1) >> 1) + 1, MapData.RIM_W - 1, size - MapData.RIM_W - 1)


## Disc of radius r (cells) around the doubled point (cx2, cy2): dx^2 + dy^2 <= (2r)^2 in doubled offsets.
func paint_disc(k: int, cx2: int, cy2: int, r: int, out: PackedInt32Array) -> void:
	var px: int = img_x(k, cx2, cy2)
	var py: int = img_y(k, cx2, cy2)
	var lim: int = 4 * r * r
	for y: int in range(_clip_lo(py, 2 * r), _clip_hi(py, 2 * r) + 1):
		var dy: int = to2(y) - py
		for x: int in range(_clip_lo(px, 2 * r), _clip_hi(px, 2 * r) + 1):
			var dx: int = to2(x) - px
			if dx * dx + dy * dy <= lim:
				out.append(y * size + x)


## Segment a -> b of half width hw2 (doubled units): distance test without division (cross^2 <= hw2^2 * den).
func paint_segment(k: int, ax2: int, ay2: int, bx2: int, by2: int, hw2: int, out: PackedInt32Array) -> void:
	var ax: int = img_x(k, ax2, ay2)
	var ay: int = img_y(k, ax2, ay2)
	var bx: int = img_x(k, bx2, by2)
	var by: int = img_y(k, bx2, by2)
	var ex: int = bx - ax
	var ey: int = by - ay
	var den: int = ex * ex + ey * ey
	var h2: int = hw2 * hw2
	var x_lo: int = _clip_lo(mini(ax, bx), hw2)
	var x_hi: int = _clip_hi(maxi(ax, bx), hw2)
	for y: int in range(_clip_lo(mini(ay, by), hw2), _clip_hi(maxi(ay, by), hw2) + 1):
		var py: int = to2(y)
		for x: int in range(x_lo, x_hi + 1):
			var qx: int = to2(x) - ax
			var qy: int = py - ay
			var num: int = qx * ex + qy * ey
			var hit: bool = false
			if num <= 0:
				hit = qx * qx + qy * qy <= h2
			elif num >= den:
				var rx: int = to2(x) - bx
				var ry: int = py - by
				hit = rx * rx + ry * ry <= h2
			else:
				var cr: int = qx * ey - qy * ex
				hit = cr * cr <= h2 * den
			if hit:
				out.append(y * size + x)


## Axis-aligned rectangle |dx| <= hx2 and |dy| <= hy2 (doubled) around (cx2, cy2); half extents swap for D4 images
## with the swap bit; rotation groups keep the axes (only the centre is rotated).
func paint_rect2(k: int, cx2: int, cy2: int, hx2: int, hy2: int, out: PackedInt32Array) -> void:
	var px: int = img_x(k, cx2, cy2)
	var py: int = img_y(k, cx2, cy2)
	var hx: int = hy2 if img_swaps(k) else hx2
	var hy: int = hx2 if img_swaps(k) else hy2
	for y: int in range(_clip_lo(py, hy), _clip_hi(py, hy) + 1):
		if absi(to2(y) - py) > hy:
			continue
		for x: int in range(_clip_lo(px, hx), _clip_hi(px, hx) + 1):
			if absi(to2(x) - px) <= hx:
				out.append(y * size + x)


# ---- start anchors and order ------------------------------------------------------------------------------------

## Canonical start point p0 (doubled, relative to the centre): x component.
func start_x2() -> int:
	var r: int = half
	match group:
		G_D1X:
			return -(r * 62 / 100) * 2 - 1
		G_D2:
			return -(r * 55 / 100) * 2 - 1
		G_D4:
			return (r * 68 / 100) * 2 + 1
	var a: int = 2048 / slots
	return (2 * (r * 64 / 100) * Fp.cos(a)) >> 16


func start_y2() -> int:
	var r: int = half
	match group:
		G_D1X:
			return (size * 6 / 100) * 2 + 1
		G_D2:
			return -(r * 55 / 100) * 2 - 1
		G_D4:
			return (r * 24 / 100) * 2 + 1
	var a: int = 2048 / slots
	return (2 * (r * 64 / 100) * Fp.sin(a)) >> 16


## Image indices in the published start order: sorted by Fp.atan2(y2, x2) of the image point around the centre
## (ties: lowest image index), so adjacent start indices are adjacent positions. order[i] = image index of start i.
func start_order() -> PackedInt32Array:
	var px: int = start_x2()
	var py: int = start_y2()
	var keys: PackedInt64Array = PackedInt64Array()
	for k: int in images:
		var ang: int = Fp.atan2(img_y(k, px, py), img_x(k, px, py))
		keys.append((ang << 8) | k)
	keys.sort()
	var order: PackedInt32Array = PackedInt32Array()
	for key: int in keys:
		order.append(key & 255)
	return order
