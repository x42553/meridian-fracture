class_name AiRouteGraph
extends RefCounted
## Coarse route graph over the map's static passability (ai.md 2.3 / 5.10): 8x8-cell blocks per move class, threat-aware
## A*, choke detection and disjoint routes. A block is passable when at least `min_open_pct` of its sampled cells are
## passable for the class (AiWorldView.passable = MapData.passable, i.e. the nav profile of the class); edges join
## 8-neighbours. The per-class grids are built lazily on the first query of a class (a snapshot of the map at that time) and
## are immutable afterwards, so one instance is shared by all AIs of a match (AiSharedData). Waypoints are block centres in
## sub-cell units, the last one is the exact target. `route()` returns the NUMBER OF WAYPOINTS (out holds 2 ints each), 0 =
## unreachable. Long searches can run as a resumable AiRouteJob.

const NEIGHBORS_DX: PackedInt32Array = [1, 1, 0, -1, -1, -1, 0, 1]
const NEIGHBORS_DY: PackedInt32Array = [0, 1, 1, 1, 0, -1, -1, -1]
const STEP_ORTHO: int = 10
const STEP_DIAG: int = 14
const AVOID_COST: int = 90  ## extra cost of a block inside an active warning zone (about nine plain steps: detour unless the detour is long)

var block_cells: int = 8
var min_open_pct: int = 40
var threat_weight_q8: int = 64
var choke_open_max: int = 3
var bw: int = 0
var bh: int = 0
var map_w: int = 0
var map_h: int = 0
var threat: AiThreatMap = null  ## optional: route cost grows with the threat map
var tick_hint: int = 0  ## world tick used to read the threat map (set by the knowledge base each think)
var avoid_zones: PackedInt32Array = PackedInt32Array()  ## AIT: the warning zones of the AI that is routing (AiDispersal.avoid rows kind, x, y, r, until; a copy set by the knowledge base each think: no reference to the AI)

var _passable_fn: Callable = Callable()
var _open: Dictionary = {}  ## move class -> PackedByteArray (open percent per block, 0 = blocked)
var _comp: Dictionary = {}  ## move class -> PackedInt32Array component ids (0 = blocked)


func _init(store: AiDataStore = null) -> void:
	if store != null:
		block_cells = store.tune("route.block_cells", 8)
		min_open_pct = store.tune("route.min_open_pct", 40)
		threat_weight_q8 = store.tune("route.threat_weight_q8", 64)
		choke_open_max = store.tune("route.choke_open_max", 3)


## Binds the map (first call wins): dimensions and the passability accessor.
func ensure_map(view: AiWorldView) -> void:
	if bw > 0:
		return
	bind_map(view.map_w(), view.map_h(), Callable(view, "passable"))


func bind_map(w: int, h: int, passable_fn: Callable) -> void:
	map_w = w
	map_h = h
	bw = (w + block_cells - 1) / block_cells
	bh = (h + block_cells - 1) / block_cells
	_passable_fn = passable_fn
	_open.clear()
	_comp.clear()


func is_bound() -> bool:
	return bw > 0


## A per-AI handle on the same immutable grids (the cached open/component tables are shared by reference, lazily filled
## by whichever handle asks first) with its OWN threat map and clock, so one route graph can serve every AI of a match.
func fork() -> AiRouteGraph:
	var g: AiRouteGraph = AiRouteGraph.new()
	g.block_cells = block_cells
	g.min_open_pct = min_open_pct
	g.threat_weight_q8 = threat_weight_q8
	g.choke_open_max = choke_open_max
	g.bw = bw
	g.bh = bh
	g.map_w = map_w
	g.map_h = map_h
	g._passable_fn = _passable_fn
	g._open = _open
	g._comp = _comp
	return g


# --------------------------------------------------------------------------------------------- grid building
func _grid(mc: int) -> PackedByteArray:
	if _open.has(mc):
		return _open[mc]
	var g: PackedByteArray = PackedByteArray()
	g.resize(bw * bh)
	for by: int in bh:
		for bx: int in bw:
			var total: int = 0
			var ok: int = 0
			var x0: int = bx * block_cells
			var y0: int = by * block_cells
			for sy: int in range(y0, mini(y0 + block_cells, map_h), 2):
				for sx: int in range(x0, mini(x0 + block_cells, map_w), 2):
					total += 1
					if _passable_fn.call(sx, sy, mc):
						ok += 1
			var pct: int = ok * 100 / maxi(total, 1)
			g[by * bw + bx] = pct if pct >= min_open_pct else 0
	_open[mc] = g
	_label(mc)
	return g


func _label(mc: int) -> void:
	var g: PackedByteArray = _open[mc]
	var comp: PackedInt32Array = PackedInt32Array()
	comp.resize(bw * bh)
	var next_id: int = 0
	var stack: PackedInt32Array = PackedInt32Array()
	for b0: int in bw * bh:
		if g[b0] == 0 or comp[b0] != 0:
			continue
		next_id += 1
		comp[b0] = next_id
		stack.resize(0)
		stack.append(b0)
		while not stack.is_empty():
			var b: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var bx: int = b % bw
			var by: int = b / bw
			for d: int in 8:
				var nx: int = bx + NEIGHBORS_DX[d]
				var ny: int = by + NEIGHBORS_DY[d]
				if nx < 0 or ny < 0 or nx >= bw or ny >= bh:
					continue
				var nb: int = ny * bw + nx
				if g[nb] != 0 and comp[nb] == 0 and _diag_ok(g, bx, by, d):
					comp[nb] = next_id
					stack.append(nb)
	_comp[mc] = comp


## A diagonal step needs both orthogonal neighbours open (no corner cutting through walls).
func _diag_ok(g: PackedByteArray, bx: int, by: int, d: int) -> bool:
	var dx: int = NEIGHBORS_DX[d]
	var dy: int = NEIGHBORS_DY[d]
	if dx == 0 or dy == 0:
		return true
	return g[by * bw + bx + dx] != 0 and g[(by + dy) * bw + bx] != 0


func block_at(x: int, y: int) -> int:
	var bx: int = clampi((x >> Fp.CELL_SHIFT) / block_cells, 0, bw - 1)
	var by: int = clampi((y >> Fp.CELL_SHIFT) / block_cells, 0, bh - 1)
	return by * bw + bx


func block_center_x(b: int) -> int:
	return ((b % bw) * block_cells + block_cells / 2) * Fp.CELL


func block_center_y(b: int) -> int:
	return ((b / bw) * block_cells + block_cells / 2) * Fp.CELL


## Nearest open block to the block of (x, y) within a ring of 3 blocks (the block itself when open), -1 if none.
func snap_open(x: int, y: int, mc: int) -> int:
	var g: PackedByteArray = _grid(mc)
	var b: int = block_at(x, y)
	if g[b] != 0:
		return b
	var bx: int = b % bw
	var by: int = b / bw
	for r: int in range(1, 4):
		var best: int = -1
		var best_d: int = 1 << 30
		for yy: int in range(by - r, by + r + 1):
			for xx: int in range(bx - r, bx + r + 1):
				if xx < 0 or yy < 0 or xx >= bw or yy >= bh or maxi(absi(xx - bx), absi(yy - by)) != r:
					continue
				var nb: int = yy * bw + xx
				if g[nb] != 0:
					var d: int = (xx - bx) * (xx - bx) + (yy - by) * (yy - by)
					if d < best_d:
						best_d = d
						best = nb
		if best >= 0:
			return best
	return -1


# ------------------------------------------------------------------------------------------------ queries
func open_pct(b: int, mc: int) -> int:
	return _grid(mc)[b]


func block_open(x: int, y: int, mc: int) -> bool:
	return _grid(mc)[block_at(x, y)] != 0


## True when both points lie in the same connected component of the class (snapped to the nearest open block).
func connected(fx: int, fy: int, tx: int, ty: int, mc: int) -> bool:
	_grid(mc)
	var a: int = snap_open(fx, fy, mc)
	var b: int = snap_open(tx, ty, mc)
	if a < 0 or b < 0:
		return false
	var comp: PackedInt32Array = _comp[mc]
	return comp[a] == comp[b]


## No LAND route between the two points (the mission needs boats / amphibious units).
func needs_water(fx: int, fy: int, tx: int, ty: int) -> bool:
	return not connected(fx, fy, tx, ty, AiTypes.MoveClass.TRACKED)


## Cost of stepping into block b: base step x openness penalty + threat.
func step_cost(b: int, mc: int, diag: bool, weight_q8: int) -> int:
	var base: int = STEP_DIAG if diag else STEP_ORTHO
	var open: int = _grid(mc)[b]
	var c: int = base * (100 + (100 - open)) / 100
	if threat != null and weight_q8 > 0:
		c += threat.at(block_center_x(b), block_center_y(b), tick_hint) * weight_q8 / 2560
	if not avoid_zones.is_empty() and _in_warning_zone(block_center_x(b), block_center_y(b)):
		c += AVOID_COST
	return c


## True when (x, y) lies inside an active debris or danger zone of `avoid_zones` at `tick_hint`.
func _in_warning_zone(x: int, y: int) -> bool:
	for i: int in avoid_zones.size() / 5:
		var k: int = avoid_zones[5 * i]
		if (k != AiDispersal.AV_DANGER and k != AiDispersal.AV_DEBRIS) or avoid_zones[5 * i + 4] <= tick_hint:
			continue
		var dx: int = avoid_zones[5 * i + 1] - x
		var dy: int = avoid_zones[5 * i + 2] - y
		var r: int = avoid_zones[5 * i + 3]
		if dx * dx + dy * dy <= r * r:
			return true
	return false


func heuristic(b: int, goal: int) -> int:
	var dx: int = absi(b % bw - goal % bw)
	var dy: int = absi(b / bw - goal / bw)
	return STEP_ORTHO * maxi(dx, dy) + (STEP_DIAG - STEP_ORTHO) * mini(dx, dy)


## Creates a resumable search job (blocks in `blocked` are avoided).
func make_job(fx: int, fy: int, tx: int, ty: int, mc: int, weight_q8: int, blocked: Dictionary = {}) -> AiRouteJob:
	return AiRouteJob.new(self, fx, fy, tx, ty, mc, weight_q8, blocked)


## Threat-aware shortest route: waypoints [x0, y0, x1, y1, ...] (block centres, last = exact target); returns the number
## of waypoints, 0 = unreachable. Runs the search to completion.
func route(fx: int, fy: int, tx: int, ty: int, move_class: int, weight_q8: int, out: PackedInt32Array) -> int:
	return _run(make_job(fx, fy, tx, ty, move_class, weight_q8), out)


func _run(job: AiRouteJob, out: PackedInt32Array) -> int:
	var b: AiBudget = AiBudget.new()
	while not job.done:
		b.reset(1 << 20, 1 << 20)
		job.step(b)
	out.resize(0)
	var res: PackedInt32Array = job.result()
	out.append_array(res)
	return out.size() / 2


## A route that shares no block with `avoid` (waypoints of another route, except its start / goal blocks). Tries a
## one-block margin around the avoided blocks first, then the plain blocks. 0 = none.
func disjoint_route(fx: int, fy: int, tx: int, ty: int, move_class: int, avoid: PackedInt32Array, out: PackedInt32Array) -> int:
	var sb: int = block_at(fx, fy)
	var gb: int = block_at(tx, ty)
	var plain: Dictionary = {}
	for i: int in avoid.size() / 2:
		var b: int = block_at(avoid[2 * i], avoid[2 * i + 1])
		if b != sb and b != gb:
			plain[b] = true
	var wide: Dictionary = plain.duplicate()
	for b2: int in plain:
		for d: int in 8:
			var nx: int = b2 % bw + NEIGHBORS_DX[d]
			var ny: int = b2 / bw + NEIGHBORS_DY[d]
			if nx >= 0 and ny >= 0 and nx < bw and ny < bh and ny * bw + nx != sb and ny * bw + nx != gb:
				wide[ny * bw + nx] = true
	var n: int = _run(make_job(fx, fy, tx, ty, move_class, threat_weight_q8, wide), out)
	if n > 0:
		return n
	return _run(make_job(fx, fy, tx, ty, move_class, threat_weight_q8, plain), out)


## Choke waypoints of a route: blocks with <= choke_open_max open 8-neighbours. out = [x, y] pairs; returns the count.
func chokes_on(route_pts: PackedInt32Array, out: PackedInt32Array, move_class: int = AiTypes.MoveClass.TRACKED) -> int:
	out.resize(0)
	var g: PackedByteArray = _grid(move_class)
	for i: int in route_pts.size() / 2:
		var b: int = block_at(route_pts[2 * i], route_pts[2 * i + 1])
		var open: int = 0
		for d: int in 8:
			var nx: int = b % bw + NEIGHBORS_DX[d]
			var ny: int = b / bw + NEIGHBORS_DY[d]
			if nx >= 0 and ny >= 0 and nx < bw and ny < bh and g[ny * bw + nx] != 0:
				open += 1
		if open <= choke_open_max:
			out.append(route_pts[2 * i])
			out.append(route_pts[2 * i + 1])
	return out.size() / 2


## Route length in blocks (Chebyshev-ish, from the waypoint list); used as path_len_c by the resource sites.
func route_cells(route_pts: PackedInt32Array) -> int:
	var total: int = 0
	for i: int in range(1, route_pts.size() / 2):
		var dx: int = absi(route_pts[2 * i] - route_pts[2 * i - 2])
		var dy: int = absi(route_pts[2 * i + 1] - route_pts[2 * i - 1])
		total += (maxi(dx, dy) + mini(dx, dy) / 2) / Fp.CELL
	return total
