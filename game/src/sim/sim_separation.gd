class_name SimSeparation
extends RefCounted
## Canonical per-layer bucket grids and the separation displacement (terrain_movement 5.4.4). The grids are rebuilt
## from entity state every tick (inserting in ascending id), so nothing here is hashed. Bucket = 2 cells.
## Entries are indexed by the position in the movement system's per-tick mover list.

const SHIFT: int = SimMoveConfig.SEP_BUCKET_SHIFT

var bw: int = 0
var bh: int = 0
var cells: int = 0
var head: PackedInt32Array = PackedInt32Array()  ## [layer * cells + bucket] -> entry index or -1
var hot: PackedInt32Array = PackedInt32Array()  ## tick stamp: a goal-holding mover is within one bucket
var nxt: PackedInt32Array = PackedInt32Array()
# per entry
var ex: PackedInt32Array = PackedInt32Array()
var ey: PackedInt32Array = PackedInt32Array()
var er: PackedInt32Array = PackedInt32Array()
var em: PackedInt32Array = PackedInt32Array()  ## mass
var eid: PackedInt32Array = PackedInt32Array()
var eown: PackedInt32Array = PackedInt32Array()  ## owner slot 0..8
var ehl: PackedInt32Array = PackedInt32Array()  ## hash layer, -1 = not in the grid
var ebk: PackedInt32Array = PackedInt32Array()  ## bucket the entry was inserted into (tick-start position)
var eact: PackedByteArray = PackedByteArray()  ## 1 = active goal (written by phase A)
var eimm: PackedByteArray = PackedByteArray()  ## 1 = immobile (written by phase A)
var enemy: PackedByteArray = PackedByteArray()  ## [slot_i * 9 + slot_j]


func _init(map_w: int, map_h: int) -> void:
	bw = ((map_w << 10) + (1 << SHIFT) - 1) >> SHIFT
	bh = ((map_h << 10) + (1 << SHIFT) - 1) >> SHIFT
	cells = bw * bh
	head.resize(SimMoveConfig.HL_COUNT * cells)
	head.fill(-1)
	hot.resize(SimMoveConfig.HL_COUNT * cells)
	hot.fill(-1)
	enemy.resize(81)


func ensure(n: int) -> void:
	if ex.size() >= n:
		return
	var cap: int = maxi(n, ex.size() * 2)
	for arr: PackedInt32Array in [nxt, ex, ey, er, em, eid, eown, ehl, ebk]:
		arr.resize(cap)
	eact.resize(cap)
	eimm.resize(cap)


## Refreshes the relation table (cheap: 81 lookups).
func refresh_relations(world: SimWorld) -> void:
	for a: int in 9:
		for b: int in 9:
			enemy[a * 9 + b] = 1 if (a < 8 and b < 8 and world.are_enemies(a, b)) else 0


## Rebuilds the grids from `ents` (ascending id). F_NO_COLLISION / gliding entries stay out of the grid.
func rebuild(world: SimWorld, ents: Array[SimEntity], n: int) -> void:
	head.fill(-1)
	ensure(n)
	var tick: int = world.tick
	var lx: PackedInt32Array = ex
	var ly: PackedInt32Array = ey
	var lr: PackedInt32Array = er
	var lm: PackedInt32Array = em
	var lid: PackedInt32Array = eid
	var lown: PackedInt32Array = eown
	var lhl: PackedInt32Array = ehl
	var lbk: PackedInt32Array = ebk
	var lact: PackedByteArray = eact
	var limm: PackedByteArray = eimm
	var lhead: PackedInt32Array = head
	var lnxt: PackedInt32Array = nxt
	var lhot: PackedInt32Array = hot
	var w: int = bw
	var cc: int = cells
	for i: int in n:
		var e: SimEntity = ents[i]
		var mv: SimCompMove = e.move
		var x: int = e.x
		var y: int = e.y
		lx[i] = x
		ly[i] = y
		lr[i] = mv.radius
		lm[i] = mv.mass
		lid[i] = e.id
		lown[i] = e.owner if e.owner >= 0 else 8
		lact[i] = 0
		limm[i] = 0
		var st: int = mv.state
		if st == SimMoveConfig.MS_GLIDE or (e.flags & SimFlags.F_NO_COLLISION) != 0:
			lhl[i] = -1
			continue
		var l: int = mv.hl
		lhl[i] = l
		var b: int = (y >> SHIFT) * w + (x >> SHIFT)
		var o: int = l * cc + b
		lbk[i] = b
		lnxt[i] = lhead[o]
		lhead[o] = i
		if mv.spd_q4 != 0 and mv.goal_kind != SimMoveConfig.GK_NONE and st != SimMoveConfig.MS_ARRIVED and st != SimMoveConfig.MS_PAUSED:
			var bx: int = b % w
			var by: int = b / w
			for yy: int in range(maxi(by - 1, 0), mini(by + 2, bh)):
				var row: int = l * cc + yy * w
				for xx: int in range(maxi(bx - 1, 0), mini(bx + 2, w)):
					lhot[row + xx] = tick


## Moves every entry to where its own intent (phase A) takes it this tick, so the push resolves the penetration
## AFTER the drive: an enemy or immobile neighbour is then a real wall. Still a pure function of all intents.
func predict(sx: PackedInt32Array, sy: PackedInt32Array, n: int) -> void:
	for i: int in n:
		ex[i] += sx[i]
		ey[i] += sy[i]


## Displacement (px, py) of every entry into `out[2 * i]`, `out[2 * i + 1]` from the snapshot (tick-start positions
## plus phase-A intents); (0, 0) for entries that do not take part this tick (idle stride, immobile, not in the grid).
func compute_all(n: int, tick: int, out: PackedInt32Array) -> void:
	var lx: PackedInt32Array = ex
	var ly: PackedInt32Array = ey
	var lr: PackedInt32Array = er
	var lm: PackedInt32Array = em
	var lid: PackedInt32Array = eid
	var lown: PackedInt32Array = eown
	var lhl: PackedInt32Array = ehl
	var lbk: PackedInt32Array = ebk
	var lact: PackedByteArray = eact
	var limm: PackedByteArray = eimm
	var lhead: PackedInt32Array = head
	var lnxt: PackedInt32Array = nxt
	var lenemy: PackedByteArray = enemy
	var lhot: PackedInt32Array = hot
	var w: int = bw
	var hh: int = bh
	var cap: int = SimMoveConfig.SEP_MAX_NEIGHBOURS
	for i: int in n:
		out[2 * i] = 0
		out[2 * i + 1] = 0
		var l: int = lhl[i]
		if l < 0 or limm[i] == 1:
			continue
		var b: int = lbk[i]
		var active: bool = lact[i] == 1
		if not active and (tick + lid[i]) % SimMoveConfig.IDLE_SEP_STRIDE != 0 and lhot[l * cells + b] != tick:
			continue
		var xi: int = lx[i]
		var yi: int = ly[i]
		var ri: int = lr[i]
		var wi: int = lm[i] * (4 if active else 1)
		var si: int = lown[i] * 9
		var bx: int = b % w
		var by: int = b / w
		var px: int = 0
		var py: int = 0
		var seen: int = 0
		var over: int = 0
		var base: int = l * cells
		for yy: int in range(maxi(by - 1, 0), mini(by + 2, hh)):
			for xx: int in range(maxi(bx - 1, 0), mini(bx + 2, w)):
				var j: int = lhead[base + yy * w + xx]
				while j >= 0 and seen < cap:
					if j != i:
						seen += 1
						var rs: int = ((ri + lr[j]) * 7) >> 3
						var dx: int = xi - lx[j]
						var dy: int = yi - ly[j]
						if dx < rs and dx > -rs and dy < rs and dy > -rs and dx * dx + dy * dy < rs * rs:
							var share: int
							if lenemy[si + lown[j]] == 1:
								share = 256 if active else 0
							else:
								var wj: int = 65536 if limm[j] == 1 else lm[j] * (4 if lact[j] == 1 else 1)
								share = (wj * 256) / (wi + wj)
							if share > 0:
								var adx: int = absi(dx)
								var ady: int = absi(dy)
								var d: int = maxi(adx, ady) + ((mini(adx, ady) * 3) >> 3)
								if d == 0:
									var x2: int = lid[i] ^ lid[j]
									dx = 2 * (x2 & 1) - 1
									dy = 2 * ((x2 >> 1) & 1) - 1
									if lid[i] > lid[j]:  # opposite directions for the two units of a coincident pair
										dx = -dx
										dy = -dy
									d = 1
								var push: int = ((rs - d) * share) >> 8
								px += dx * push / d
								py += dy * push / d
								over += 1
					j = lnxt[j]
		if over > 1:  # several simultaneous overlaps: damp the sum (Jacobi over-relaxation blows crowds apart)
			px = px * 2 / (over + 1)
			py = py * 2 / (over + 1)
		var lim: int = maxi(24, ri / 3)
		out[2 * i] = clampi(px, -lim, lim)
		out[2 * i + 1] = clampi(py, -lim, lim)
