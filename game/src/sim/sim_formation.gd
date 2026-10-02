class_name SimFormation
extends RefCounted
## Same-tick group moves (terrain_movement 5.5): group detection from the fresh T_MOVE orders and the arrival slots.
## sim_core has no group command: MOVE(ids, x, y) becomes one T_MOVE per actor in the same tick, and the first unit of
## the group that begins computes every member's slot as a pure function of the current positions.

const MAX_GROUP: int = 200
const EXTRA_SPACING: int = 461  ## movement_defaults.formation_spacing_cells_extra 0.45 cell
const MIN_SPACING: int = 1024
const MAX_SPACING: int = 3072
const MAX_COLS: int = 12
const NEAR_TARGET: int = 2048  ## group centroid closer than this to the target: use the lowest id's facing
const SNAP_RINGS: int = 8
const F_SPEED_MATCH: int = 1  ## assign() flag: cap every member at the slowest member's top speed
const KEY_BIAS: int = 1 << 18  ## |u|, |v| stay below 256 cells = 2^18 units; keys are (u, v, id) packed 19 + 19 + 24 bits

## movement.json formation.speed_match (the file does not exist yet): speed matching is off unless the order asks for it.
const SPEED_MATCH_DEFAULT: bool = false


static func is_ground(mv: SimCompMove) -> bool:
	return mv != null and mv.mc >= MapTerrain.MC_FOOT and mv.mc <= MapTerrain.MC_AMPHIBIOUS


## Fills `out` with the ids (ascending, <= MAX_GROUP) of the owner's units whose head order is a T_MOVE with the same
## x, y, without OF_NO_FORMATION, not begun yet (PH_NEW) or begun in this very tick, ground class with a move
## component; `e` (whose order `o` is beginning) is among them. Returns out.size(); 1 = no group.
static func group_of(world: SimWorld, e: SimEntity, o: SimOrder, out: PackedInt32Array) -> int:
	out.resize(0)
	if (o.flags & SimOrder.OF_NO_FORMATION) != 0 or not is_ground(e.move):
		out.append(e.id)
		return 1
	var tick: int = world.tick
	var has_e: bool = false
	for u: SimEntity in world.units_of(e.owner):
		if u.orders.is_empty() or (u.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
			continue
		var h: SimOrder = u.orders[0]
		if h.type != SimOrder.T_MOVE or h.x != o.x or h.y != o.y or (h.flags & SimOrder.OF_NO_FORMATION) != 0 or not is_ground(u.move):
			continue
		if u.id != e.id and h.phase != SimOrder.PH_NEW and h.t0 != tick:
			continue
		if out.size() >= MAX_GROUP:
			break
		out.append(u.id)
		if u.id == e.id:
			has_e = true
	if not has_e:
		out.resize(0)
		out.append(e.id)
	return out.size()


## Slot of ids[i] into out_x[i] / out_y[i] (arrays are resized); every member's SimCompMove receives
## fslot_x / fslot_y / fslot_tick = world.tick. flags: F_SPEED_MATCH.
static func assign(world: SimWorld, ids: PackedInt32Array, tx: int, ty: int, flags: int, out_x: PackedInt32Array, out_y: PackedInt32Array) -> void:
	var n: int = ids.size()
	out_x.resize(n)
	out_y.resize(n)
	if n == 0:
		return
	var ents: Array[SimEntity] = []
	var sx: int = 0
	var sy: int = 0
	var rmax: int = 0
	for id: int in ids:
		var u: SimEntity = world.by_id[id]
		ents.append(u)
		sx += u.x
		sy += u.y
		rmax = maxi(rmax, u.radius)
	var cx: int = sx / n
	var cy: int = sy / n
	var tick: int = world.tick
	if n == 1:
		out_x[0] = tx
		out_y[0] = ty
		_store(ents[0], tx, ty, tick)
		return
	var theta: int
	if Fp.dist(tx - cx, ty - cy) < NEAR_TARGET:
		theta = ents[0].facing
	else:
		theta = Fp.atan2(ty - cy, tx - cx)
	var fx: int = Fp.cos(theta)
	var fy: int = Fp.sin(theta)
	var rx: int = -fy
	var ry: int = fx
	var spacing: int = clampi(2 * rmax + EXTRA_SPACING, MIN_SPACING, MAX_SPACING)
	var cols: int = clampi(Fp.isqrt(3 * n / 2), 1, MAX_COLS)
	var lim: int = KEY_BIAS - 1
	# front-to-back order: key = (-u, v, id)
	var keys: PackedInt64Array = PackedInt64Array()
	var vs: PackedInt32Array = PackedInt32Array()
	keys.resize(n)
	vs.resize(n)
	var idx_of: Dictionary = {}  # id -> position in ids (keyed lookup only, never iterated)
	for i: int in n:
		var u2: SimEntity = ents[i]
		idx_of[u2.id] = i
		var uu: int = clampi(((u2.x - cx) * fx + (u2.y - cy) * fy) >> 16, -lim, lim)
		var vv: int = clampi(((u2.x - cx) * rx + (u2.y - cy) * ry) >> 16, -lim, lim)
		vs[i] = vv
		keys[i] = ((KEY_BIAS - uu) << 43) | ((vv + KEY_BIAS) << 24) | u2.id
	keys.sort()
	var order: PackedInt32Array = PackedInt32Array()  # positions in ids, front to back
	order.resize(n)
	for k: int in n:
		order[k] = idx_of[keys[k] & 0xFFFFFF]
	var rows: int = (n + cols - 1) / cols
	var nav: MapNav = world.map.nav
	var w: int = world.map.w
	for row: int in rows:
		var first: int = row * cols
		var cnt: int = mini(cols, n - first)
		var rk: PackedInt64Array = PackedInt64Array()
		rk.resize(cnt)
		for j: int in cnt:
			var pos: int = order[first + j]
			rk[j] = ((vs[pos] + KEY_BIAS) << 24) | ents[pos].id
		rk.sort()
		for j: int in cnt:
			var pos2: int = idx_of[rk[j] & 0xFFFFFF]
			var lat: int = ((2 * j - (cnt - 1)) * spacing) / 2
			var back: int = -row * spacing
			var px: int = tx + ((fx * back) >> 16) + ((rx * lat) >> 16)
			var py: int = ty + ((fy * back) >> 16) + ((ry * lat) >> 16)
			px = clampi(px, 2048, world.map.w * 1024 - 2049)
			py = clampi(py, 2048, world.map.h * 1024 - 2049)
			var mv: SimCompMove = ents[pos2].move
			var cell: int = (py >> 10) * w + (px >> 10)
			if not nav.passable(mv.np, mv.nav_size, cell):
				var alt: int = nav.nearest_passable(mv.np, mv.nav_size, cell, SNAP_RINGS)
				if alt < 0:
					px = tx
					py = ty
				else:
					px = (alt % w) * 1024 + 512
					py = (alt / w) * 1024 + 512
			out_x[pos2] = px
			out_y[pos2] = py
	var cap: int = 0
	if (flags & F_SPEED_MATCH) != 0:
		cap = 1 << 30
		for u3: SimEntity in ents:
			cap = mini(cap, u3.move.speed_base * 16)
	for i2: int in n:
		_store(ents[i2], out_x[i2], out_y[i2], tick)
		if cap > 0:
			ents[i2].move.speed_cap_q4 = cap


static func _store(u: SimEntity, x: int, y: int, tick: int) -> void:
	var mv: SimCompMove = u.move
	mv.fslot_x = x
	mv.fslot_y = y
	mv.fslot_tick = tick
