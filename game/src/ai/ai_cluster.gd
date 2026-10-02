class_name AiCluster
extends RefCounted
## Grid-hash clustering and oriented-shape candidate scoring over the knowledge base (ai.md 2.2 / 3.5): the basis of the
## power, superweapon and harass target search. Items are the remembered enemy structures (ghost value) and the seen enemy
## units (paid x hp / hp_max) of the players in `enemy_mask` (bit p = pid p). Everything is integer; angles are binary angles
## (0..4095, Fp), offsets are sub-cell units.
##
## Shapes are Arrays of part dictionaries, offsets/radii in sub-cells, `w` = Q8 weight (256 = 1.0), all optional but `t`:
##   {"t": "c", "dx", "dy", "r", "w"}            circle at (dx, dy) rotated by the shape angle
##   {"t": "a", "dx", "dy", "r0", "r1", "w"}     annulus (ring) r0 <= d <= r1
##   {"t": "r", "dx", "dy", "len", "hw", "w"}    rectangle: half-length `len` along the axis, half-width `hw`
## Modes: MODE_ALL 0 (units and structures), MODE_STRUCT 1, MODE_UNITS 2.

const MODE_ALL: int = 0
const MODE_STRUCT: int = 1
const MODE_UNITS: int = 2
const BLOCK_CELLS: int = 3

var grid_w: int = 0  ## value_grid dimensions in blocks (set by value_grid)
var grid_h: int = 0

# item arrays of the last collection
var ix: PackedInt32Array = PackedInt32Array()
var iy: PackedInt32Array = PackedInt32Array()
var iv: PackedInt32Array = PackedInt32Array()
var ik: PackedInt32Array = PackedInt32Array()  ## 0 structure, 1 unit
var n_items: int = 0


## Collects the items of the players in enemy_mask filtered by mode. Charges 1 wu per 4 items when a budget is given.
func collect(ctx: AiContext, enemy_mask: int, mode: int = MODE_ALL, budget: AiBudget = null) -> int:
	ix.resize(0)
	iy.resize(0)
	iv.resize(0)
	ik.resize(0)
	var kb: AiKnowledge = ctx.kb
	if mode != MODE_UNITS:
		var g: AiGhostTable = kb.ghosts
		for r: int in g.count:
			var o: int = g.owner[r]
			if o < 0 or (enemy_mask & (1 << o)) == 0:
				continue
			ix.append(g.x[r])
			iy.append(g.y[r])
			iv.append(g.value[r] * g.hp_pct[r] / 100 if g.hp_pct[r] > 0 else g.value[r])
			ik.append(0)
	if mode != MODE_STRUCT:
		var t: AiEntityTable = kb.enemy_units
		for r2: int in t.count:
			var o2: int = t.owner[r2]
			if o2 < 0 or (enemy_mask & (1 << o2)) == 0 or (t.flags[r2] & AiTypes.EF_DECOY) != 0:
				continue
			ix.append(t.x[r2])
			iy.append(t.y[r2])
			iv.append(t.paid[r2] * t.hp[r2] / maxi(t.hp_max[r2], 1))
			ik.append(1)
	n_items = ix.size()
	if budget != null:
		budget.spend(1 + n_items / 4)
	return n_items


## 3-cell block value grid of the enemy items; out has grid_w x grid_h entries (row major).
func value_grid(ctx: AiContext, enemy_mask: int, out: PackedInt32Array) -> void:
	collect(ctx, enemy_mask, MODE_ALL)
	var bs: int = BLOCK_CELLS * Fp.CELL
	grid_w = (ctx.view.map_w() * Fp.CELL + bs - 1) / bs
	grid_h = (ctx.view.map_h() * Fp.CELL + bs - 1) / bs
	out.resize(grid_w * grid_h)
	out.fill(0)
	for i: int in n_items:
		var bx: int = clampi(ix[i] / bs, 0, grid_w - 1)
		var by: int = clampi(iy[i] / bs, 0, grid_h - 1)
		out[by * grid_w + bx] += iv[i]


## Best k non-overlapping circles of radius r (sub-cells): out = [x, y, score] * k. Candidates are the item positions,
## each refined once to the value-weighted centroid of the items it covers. Ties: higher score, then lower y, then lower x.
## Returns the number of circles found.
func best_circle(ctx: AiContext, r: int, mode: int, k: int, out: PackedInt32Array, budget: AiBudget = null, enemy_mask: int = 0xFF) -> int:
	out.resize(0)
	collect(ctx, enemy_mask, mode, budget)
	if n_items == 0 or k <= 0:
		return 0
	var r2: int = r * r
	# spatial hash of the items with buckets of size r
	var bs: int = maxi(r, Fp.CELL)
	var buckets: Dictionary = {}
	for i: int in n_items:
		var key: int = (iy[i] / bs) * 4096 + ix[i] / bs
		var bucket: PackedInt32Array = buckets.get(key, PackedInt32Array())
		bucket.append(i)
		buckets[key] = bucket
	var taken: PackedInt32Array = PackedInt32Array()  # centres already chosen, x,y pairs
	var found: int = 0
	for _round: int in k:
		var best_score: int = 0
		var best_x: int = 0
		var best_y: int = 0
		for c: int in n_items:
			var cx: int = ix[c]
			var cy: int = iy[c]
			if _near_any(taken, cx, cy, r2):
				continue
			if budget != null and not budget.spend(2):
				break
			var s: int = _circle_sum(buckets, bs, cx, cy, r2)
			# one refinement step towards the weighted centroid
			var mx: int = 0
			var my: int = 0
			var mw: int = 0
			for j: int in _circle_items(buckets, bs, cx, cy, r2):
				mx += ix[j] * maxi(iv[j], 1)
				my += iy[j] * maxi(iv[j], 1)
				mw += maxi(iv[j], 1)
			if mw > 0:
				var rx: int = mx / mw
				var ry: int = my / mw
				var s2: int = _circle_sum(buckets, bs, rx, ry, r2)
				if s2 > s:
					s = s2
					cx = rx
					cy = ry
			if s > best_score or (s == best_score and s > 0 and (cy < best_y or (cy == best_y and cx < best_x))):
				best_score = s
				best_x = cx
				best_y = cy
		if best_score <= 0:
			break
		out.append(best_x)
		out.append(best_y)
		out.append(best_score)
		taken.append(best_x)
		taken.append(best_y)
		found += 1
	return found


func _near_any(centres: PackedInt32Array, x: int, y: int, r2: int) -> bool:
	for i: int in centres.size() / 2:
		var dx: int = centres[2 * i] - x
		var dy: int = centres[2 * i + 1] - y
		if dx * dx + dy * dy < r2:
			return true
	return false


func _circle_items(buckets: Dictionary, bs: int, cx: int, cy: int, r2: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var bx0: int = maxi(cx - bs, 0) / bs
	var bx1: int = (cx + bs) / bs
	var by0: int = maxi(cy - bs, 0) / bs
	var by1: int = (cy + bs) / bs
	for by: int in range(by0, by1 + 1):
		for bx: int in range(bx0, bx1 + 1):
			var key: int = by * 4096 + bx
			if not buckets.has(key):
				continue
			for i: int in (buckets[key] as PackedInt32Array):
				var dx: int = ix[i] - cx
				var dy: int = iy[i] - cy
				if dx * dx + dy * dy <= r2:
					out.append(i)
	return out


func _circle_sum(buckets: Dictionary, bs: int, cx: int, cy: int, r2: int) -> int:
	var s: int = 0
	for i: int in _circle_items(buckets, bs, cx, cy, r2):
		s += iv[i]
	return s


## Weighted score of `shape` placed at (x, y) with `angle`; items are collected for the mode (call collect() yourself first
## and pass mode = -1 to reuse the last collection, e.g. inside a candidate loop).
func score_shape(ctx: AiContext, shape: Array, x: int, y: int, angle: int, mode: int = MODE_ALL, enemy_mask: int = 0xFF) -> int:
	if mode >= 0:
		collect(ctx, enemy_mask, mode)
	var total: int = 0
	for part: Variant in shape:
		var p: Dictionary = part
		var w: int = int(p.get("w", 256))
		var dx: int = int(p.get("dx", 0))
		var dy: int = int(p.get("dy", 0))
		var px: int = x + Fp.rot_x(dx, dy, angle)
		var py: int = y + Fp.rot_y(dx, dy, angle)
		var s: int = 0
		match str(p.get("t", "c")):
			"c":
				var r: int = int(p.get("r", 0))
				var r2: int = r * r
				for i: int in n_items:
					var ddx: int = ix[i] - px
					var ddy: int = iy[i] - py
					if ddx * ddx + ddy * ddy <= r2:
						s += iv[i]
			"a":
				var lo: int = int(p.get("r0", 0))
				var hi: int = int(p.get("r1", 0))
				for i2: int in n_items:
					var ax: int = ix[i2] - px
					var ay: int = iy[i2] - py
					var d2: int = ax * ax + ay * ay
					if d2 >= lo * lo and d2 <= hi * hi:
						s += iv[i2]
			"r":
				var half_len: int = int(p.get("len", 0))
				var half_w: int = int(p.get("hw", 0))
				for i3: int in n_items:
					# item in the rectangle's local frame (axis = angle)
					var lx: int = ix[i3] - px
					var ly: int = iy[i3] - py
					var inv: int = (Fp.TURN - angle) & Fp.ANGLE_MASK
					var u: int = Fp.rot_x(lx, ly, inv)
					var v: int = Fp.rot_y(lx, ly, inv)
					if absi(u) <= half_len and absi(v) <= half_w:
						s += iv[i3]
		total += s * w / 256
	return total
