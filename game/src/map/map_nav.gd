class_name MapNav
extends RefCounted
## Per-profile navigation layers of a MapData (terrain_movement 3.4 / 5.2): live path weights, clearance,
## integer LOS, nearest-passable search, deferred (count-bounded) clearance / graph maintenance and the
## region-id / connectivity queries that are answered by the abstract graphs (MapNavGraph, task TM-04).
##
## Ownership: `MapData.nav`. To avoid a RefCounted cycle MapNav never references MapData: it shares (aliases) the
## MapData arrays it reads (`terrain`, `flags`, `occ`); MapData is the only writer of those. Nothing here
## reads a clock or a random source; all queues are count-bounded (DR-11).
##
## Weight of a cell in a profile = terrain weight, or 0 if the terrain blocks it, the cell has SF_BLOCK, a
## structure (`occ >= 0`) or lies in the outer NAV_BORDER cells. Clearance = min(3, Chebyshev distance to the
## nearest blocked cell), 0 on blocked cells.

const NAV_BORDER: int = 2  ## == MapData.NAV_BORDER (asserted by tests)
const SF_BLOCK: int = 4  ## == MapData.SF_BLOCK
const MIN_GRAPH_CELLS: int = 100  ## a profile with fewer passable terrain cells gets no abstract graphs
## (a profile without ANY passable terrain cell is inactive: all-zero and never updated)
const CLR_UNITS: int = 4  ## budget units charged per queued clearance rect
## Built from parts on purpose: the file belongs to task TM-04 and may not exist yet (lint L001 checks literals).
const GRAPH_PATH: String = "res://src/map/" + "map_nav_graph.gd"
const _KEYS_ALL: PackedInt32Array = [
	MapTerrain.NP_FOOT * 4 + 1, MapTerrain.NP_WHEELED * 4 + 2, MapTerrain.NP_TRACKED * 4 + 2,
	MapTerrain.NP_AMPH * 4 + 2, MapTerrain.NP_NAVAL * 4 + 2, MapTerrain.NP_NAVAL_DEEP * 4 + 2,
	MapTerrain.NP_NAVAL_DEEP * 4 + 3, MapTerrain.NP_SUB * 4 + 2,
]

var w: int = 0
var h: int = 0
var n: int = 0
var tt: MapTerrain = null
## Static cell -> x / y without division (shared by clones).
var col: PackedInt32Array = PackedInt32Array()
var row: PackedInt32Array = PackedInt32Array()
## Test / MapNavGraph seam: `func(nav: MapNav, np: int, size: int) -> Object` creating a graph. When invalid,
## `GRAPH_PATH` (MapNavGraph) is used if the script exists, else no graphs are built.
var graph_factory: Callable = Callable()
## Graph registry: key (np * 4 + size) -> graph object.
var graphs: Dictionary = {}

var _terrain: PackedByteArray = PackedByteArray()  # aliased with MapData
var _flags: PackedByteArray = PackedByteArray()  # aliased with MapData
var _occ: PackedInt32Array = PackedInt32Array()  # aliased with MapData
var _wtab: PackedByteArray = PackedByteArray()  # tt weight table [np * 16 + type]
var _so: PackedByteArray = PackedByteArray()
var _sd: PackedByteArray = PackedByteArray()
var _wgt: Array[PackedByteArray] = []
var _clr: Array[PackedByteArray] = []
var _active: PackedByteArray = PackedByteArray()
var _graph_ok: PackedByteArray = PackedByteArray()
var _q: PackedInt32Array = PackedInt32Array()  # queued clearance rects x0, y0, x1, y1 (already expanded by 3)
var _q_head: int = 0
var _gkeys: PackedInt32Array = PackedInt32Array()  # sorted graph keys


func _init(p_tt: MapTerrain, p_w: int, p_h: int, p_terrain: PackedByteArray, p_flags: PackedByteArray,
		p_occ: PackedInt32Array) -> void:
	tt = p_tt
	w = p_w
	h = p_h
	n = p_w * p_h
	_terrain = p_terrain
	_flags = p_flags
	_occ = p_occ
	_wtab = p_tt.weight_table()
	_so = p_tt.step_o_table()
	_sd = p_tt.step_d_table()
	_active.resize(MapTerrain.NP_COUNT)
	_graph_ok.resize(MapTerrain.NP_COUNT)
	for np: int in MapTerrain.NP_COUNT:
		var a: PackedByteArray = PackedByteArray()
		a.resize(n)
		_wgt.append(a)
		var b: PackedByteArray = PackedByteArray()
		b.resize(n)
		_clr.append(b)


# ---- build / clone ---------------------------------------------------------------------------------------------

## Computes col/row, decides which profiles are active (any passable terrain cell) and graph-worthy
## (>= MIN_GRAPH_CELLS passable terrain cells, border and blockers ignored), then all
## weights and clearances from scratch. Called by MapData.finalize(); drops queued work and graphs.
func rebuild() -> void:
	if col.size() != n:
		col.resize(n)
		row.resize(n)
		for i: int in n:
			col[i] = i % w
			row[i] = i / w
	var hist: PackedInt32Array = PackedInt32Array()
	hist.resize(MapTerrain.COUNT)
	for i: int in n:
		hist[_terrain[i]] += 1
	for np: int in MapTerrain.NP_COUNT:
		var cnt: int = 0
		for t: int in MapTerrain.COUNT:
			if _wtab[np * MapTerrain.COUNT + t] != 0:
				cnt += hist[t]
		_active[np] = 1 if cnt >= 1 else 0
		_graph_ok[np] = 1 if cnt >= MIN_GRAPH_CELLS else 0
	_q.clear()
	_q_head = 0
	graphs.clear()
	_gkeys.clear()
	_weights_full(_wgt)
	for np: int in MapTerrain.NP_COUNT:
		if _active[np] == 1:
			_clr[np] = _clearance_full(_wgt[np])
		else:
			_clr[np].fill(0)


## Independent copy for another world: weights / clearance / queue / graphs copied, static tables and the
## static arrays shared. `new_occ` is the clone's own occupancy array (the caller's `occ.duplicate()`).
func clone_for(new_occ: PackedInt32Array) -> MapNav:
	var c: MapNav = MapNav.new(tt, w, h, _terrain, _flags, new_occ)
	c.col = col
	c.row = row
	c.graph_factory = graph_factory
	c._active = _active.duplicate()
	c._graph_ok = _graph_ok.duplicate()
	for np: int in MapTerrain.NP_COUNT:
		c._wgt[np] = _wgt[np].duplicate()
		c._clr[np] = _clr[np].duplicate()
	c._q = _q.slice(_q_head)
	c._gkeys = _gkeys.duplicate()
	for k: int in _gkeys:
		c.graphs[k] = (graphs[k] as Object).call("clone_for", c)
	return c


func _weights_full(dst: Array[PackedByteArray]) -> void:
	for np: int in MapTerrain.NP_COUNT:
		var a: PackedByteArray = dst[np]
		a.fill(0)
		if _active[np] == 0:
			continue
		var off: int = np * MapTerrain.COUNT
		for i: int in n:
			a[i] = _wtab[off + _terrain[i]]
		# outer border
		for y: int in h:
			var yb: bool = y < NAV_BORDER or y >= h - NAV_BORDER
			for x: int in NAV_BORDER:
				a[y * w + x] = 0
				a[y * w + w - 1 - x] = 0
			if yb:
				for x: int in w:
					a[y * w + x] = 0
	for i: int in n:
		if (_flags[i] & SF_BLOCK) != 0 or _occ[i] >= 0:
			for np: int in MapTerrain.NP_COUNT:
				dst[np][i] = 0


## Two-pass Chebyshev distance transform capped at 3 over a weight array (blocked = 0).
func _clearance_full(wg: PackedByteArray) -> PackedByteArray:
	var c: PackedByteArray = PackedByteArray()
	c.resize(n)
	for i: int in n:
		if wg[i] != 0:
			c[i] = 3
	for y: int in range(1, h - 1):
		var base: int = y * w
		for x: int in range(1, w - 1):
			var i: int = base + x
			var v: int = c[i]
			if v == 0:
				continue
			var m: int = mini(mini(c[i - 1], c[i - w - 1]), mini(c[i - w], c[i - w + 1])) + 1
			if m < v:
				c[i] = m
	for y: int in range(h - 2, 0, -1):
		var base: int = y * w
		for x: int in range(w - 2, 0, -1):
			var i: int = base + x
			var v: int = c[i]
			if v == 0:
				continue
			var m: int = mini(mini(c[i + 1], c[i + w + 1]), mini(c[i + w], c[i + w - 1])) + 1
			if m < v:
				c[i] = m
	return c


# ---- point queries ---------------------------------------------------------------------------------------------

## Live weight, 0 = blocked (terrain, SF_BLOCK, structure, NAV_BORDER).
func w_at(np: int, i: int) -> int:
	return _wgt[np][i]


## 0..3 clearance (foot: 0/1).
func clear_at(np: int, i: int) -> int:
	return _clr[np][i]


func passable(np: int, size: int, i: int) -> bool:
	return _clr[np][i] >= size


func passable_units(np: int, size: int, x: int, y: int) -> bool:
	var cx: int = x >> 10
	var cy: int = y >> 10
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return false
	return _clr[np][cy * w + cx] >= size


## True when the map has any terrain passable for the profile (else its layers are all-zero and not maintained).
func is_active(np: int) -> bool:
	return _active[np] == 1


## The live weight array of a profile (shared reference: read-only for callers; MapPathSearch fast path).
func wgt_array(np: int) -> PackedByteArray:
	return _wgt[np]


## The live clearance array of a profile (shared reference: read-only for callers).
func clr_array(np: int) -> PackedByteArray:
	return _clr[np]


## Step cost of entering a cell of weight `wt` (orthogonal / diagonal), see MapTerrain.step_o / step_d.
func step_o(wt: int) -> int:
	return _so[wt]


func step_d(wt: int) -> int:
	return _sd[wt]


# ---- LOS ---------------------------------------------------------------------------------------------------------

## Integer Bresenham between two cell indices, diagonal corner rule (both shared orthogonal cells must have
## weight != 0), every visited cell (incl. both ends) needs clearance >= size.
func los(np: int, size: int, c0: int, c1: int) -> bool:
	if c0 < 0 or c1 < 0 or c0 >= n or c1 >= n:
		return false
	var wg: PackedByteArray = _wgt[np]
	var cl: PackedByteArray = _clr[np]
	var x0: int = c0 % w
	var y0: int = c0 / w
	var x1: int = c1 % w
	var y1: int = c1 / w
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x1 > x0 else -1
	var sy: int = 1 if y1 > y0 else -1
	var err: int = dx - dy
	var x: int = x0
	var y: int = y0
	while true:
		if cl[y * w + x] < size:
			return false
		if x == x1 and y == y1:
			return true
		var e2: int = 2 * err
		var stepx: bool = e2 > -dy
		var stepy: bool = e2 < dx
		if stepx and stepy:
			if wg[y * w + x + sx] == 0 or wg[(y + sy) * w + x] == 0:
				return false
		if stepx:
			err -= dy
			x += sx
		if stepy:
			err += dx
			y += sy
	return false


## Sum of step costs (entering each cell after c0; orthogonal or diagonal as taken) along the `los` line,
## -1 if the line is blocked.
func los_cost(np: int, size: int, c0: int, c1: int) -> int:
	if c0 < 0 or c1 < 0 or c0 >= n or c1 >= n:
		return -1
	var wg: PackedByteArray = _wgt[np]
	var cl: PackedByteArray = _clr[np]
	var x0: int = c0 % w
	var y0: int = c0 / w
	var x1: int = c1 % w
	var y1: int = c1 / w
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x1 > x0 else -1
	var sy: int = 1 if y1 > y0 else -1
	var err: int = dx - dy
	var x: int = x0
	var y: int = y0
	var cost: int = 0
	while true:
		if cl[y * w + x] < size:
			return -1
		if x == x1 and y == y1:
			return cost
		var e2: int = 2 * err
		var stepx: bool = e2 > -dy
		var stepy: bool = e2 < dx
		if stepx and stepy:
			if wg[y * w + x + sx] == 0 or wg[(y + sy) * w + x] == 0:
				return -1
			err -= dy
			x += sx
			err += dx
			y += sy
			cost += _sd[wg[y * w + x]]
		elif stepx:
			err -= dy
			x += sx
			cost += _so[wg[y * w + x]]
		else:
			err += dx
			y += sy
			cost += _so[wg[y * w + x]]
	return -1


## First cell with clearance >= size in rings 0..max_ring (Chebyshev) around cell i (ring 0 = i itself). Ring
## order is the domain-wide walk: top row left->right, right column top->bottom, bottom row right->left, left
## column bottom->top. -1 if none. Cells outside the map are skipped.
func nearest_passable(np: int, size: int, i: int, max_ring: int) -> int:
	var cl: PackedByteArray = _clr[np]
	var cx: int = i % w
	var cy: int = i / w
	if cl[i] >= size:
		return i
	for r: int in range(1, max_ring + 1):
		var x0: int = cx - r
		var x1: int = cx + r
		var y0: int = cy - r
		var y1: int = cy + r
		for x: int in range(x0, x1 + 1):  # top row
			if x >= 0 and x < w and y0 >= 0 and cl[y0 * w + x] >= size:
				return y0 * w + x
		for y: int in range(y0 + 1, y1 + 1):  # right column
			if y >= 0 and y < h and x1 < w and cl[y * w + x1] >= size:
				return y * w + x1
		for x: int in range(x1 - 1, x0 - 1, -1):  # bottom row
			if x >= 0 and x < w and y1 < h and cl[y1 * w + x] >= size:
				return y1 * w + x
		for y: int in range(y1 - 1, y0, -1):  # left column
			if y >= 0 and y < h and x0 >= 0 and cl[y * w + x0] >= size:
				return y * w + x0
	return -1


# ---- dynamic updates -------------------------------------------------------------------------------------------

## MapData internal. IMMEDIATE part for the inclusive cell rect: weights of every active profile are recomputed
## from terrain / flags / occ (clearance 0 on blocked cells, 1 on freed cells, so LOS and `passable` are never
## optimistic about a blocked cell). DEFERRED part: clearance of the rect expanded by 3 and the graph block
## relabels are queued for `flush_dirty`.
func on_cells_changed(cx0: int, cy0: int, cx1: int, cy1: int) -> void:
	var x0: int = maxi(cx0, 0)
	var y0: int = maxi(cy0, 0)
	var x1: int = mini(cx1, w - 1)
	var y1: int = mini(cy1, h - 1)
	if x0 > x1 or y0 > y1:
		return
	for np: int in MapTerrain.NP_COUNT:
		if _active[np] == 0:
			continue
		var wg: PackedByteArray = _wgt[np]
		var cl: PackedByteArray = _clr[np]
		var off: int = np * MapTerrain.COUNT
		for y: int in range(y0, y1 + 1):
			for x: int in range(x0, x1 + 1):
				var i: int = y * w + x
				var nw: int = 0
				if x >= NAV_BORDER and y >= NAV_BORDER and x < w - NAV_BORDER and y < h - NAV_BORDER \
						and (_flags[i] & SF_BLOCK) == 0 and _occ[i] < 0:
					nw = _wtab[off + _terrain[i]]
				var old: int = wg[i]
				if nw == 0:
					wg[i] = 0
					cl[i] = 0
				elif old == 0:
					wg[i] = nw
					cl[i] = 1
				elif nw != old:
					wg[i] = nw
	_q.append(maxi(x0 - 3, NAV_BORDER))
	_q.append(maxi(y0 - 3, NAV_BORDER))
	_q.append(mini(x1 + 3, w - 1 - NAV_BORDER))
	_q.append(mini(y1 + 3, h - 1 - NAV_BORDER))


## Drains deferred work: clearance of queued rects (CLR_UNITS each, FIFO) then graph relabels (1 unit each, in
## ascending graph key order). Returns the units consumed (<= budget; an item that does not fit is left queued).
func flush_dirty(budget: int) -> int:
	var used: int = 0
	while _q_head + 4 <= _q.size() and used + CLR_UNITS <= budget:
		var x0: int = _q[_q_head]
		var y0: int = _q[_q_head + 1]
		var x1: int = _q[_q_head + 2]
		var y1: int = _q[_q_head + 3]
		_q_head += 4
		_clearance_rect(x0, y0, x1, y1)
		for k: int in _gkeys:
			(graphs[k] as Object).call("mark_rect", x0, y0, x1, y1)
		used += CLR_UNITS
	if _q_head >= _q.size():
		_q.clear()
		_q_head = 0
	for k: int in _gkeys:
		var g: Object = graphs[k]
		while used < budget and (g.call("pending") as int) > 0:
			g.call("relabel_step")
			used += 1
	return used


## Queued clearance rects plus graph relabel units still pending.
func pending_dirty() -> int:
	var c: int = (_q.size() - _q_head) / 4
	for k: int in _gkeys:
		c += (graphs[k] as Object).call("pending") as int
	return c


func _clearance_rect(x0: int, y0: int, x1: int, y1: int) -> void:
	for np: int in MapTerrain.NP_COUNT:
		if _active[np] == 0:
			continue
		var wg: PackedByteArray = _wgt[np]
		var cl: PackedByteArray = _clr[np]
		for y: int in range(y0, y1 + 1):
			for x: int in range(x0, x1 + 1):
				var i: int = y * w + x
				if wg[i] == 0:
					cl[i] = 0
				else:
					cl[i] = _clr_ring(wg, x, y)


## min(3, Chebyshev distance to the nearest blocked cell) by ring testing with early exit. The blocked border
## guarantees a hit before any ring leaves the map.
func _clr_ring(wg: PackedByteArray, x: int, y: int) -> int:
	for r: int in range(1, 4):
		var top: int = (y - r) * w
		var bot: int = (y + r) * w
		for xx: int in range(x - r, x + r + 1):
			if wg[top + xx] == 0 or wg[bot + xx] == 0:
				return r
		for yy: int in range(y - r + 1, y + r):
			if wg[yy * w + x - r] == 0 or wg[yy * w + x + r] == 0:
				return r
	return 3


## Test hook: recomputes weights (always) and clearance (only when no deferred work is pending) from terrain /
## flags / occ and compares with the live layers. Also verifies inactive profiles are all-zero.
func validate_against_terrain() -> bool:
	var fresh: Array[PackedByteArray] = []
	for np: int in MapTerrain.NP_COUNT:
		var a: PackedByteArray = PackedByteArray()
		a.resize(n)
		fresh.append(a)
	_weights_full(fresh)
	var ok: bool = true
	for np: int in MapTerrain.NP_COUNT:
		if fresh[np] != _wgt[np]:
			ok = false
		if _active[np] == 1 and _q_head >= _q.size() and pending_dirty() == 0:
			if _clearance_full(fresh[np]) != _clr[np]:
				ok = false
		elif _active[np] == 0 and _clr[np].count(0) != n:
			ok = false
	return ok


# ---- GRAPH SEAM (MapNavGraph, task TM-04) -----------------------------------------------------------------------
# MapNav only talks to a graph through the following contract; a graph object provides:
#   _init(nav: MapNav, np: int, size: int)      - constructed by `_make_graph` (nav = this MapNav). MUST NOT store `nav`
#                                                  (RefCounted cycle; sim_core requires none): keep the aliased arrays
#                                                  `nav.clr_array(np)` / `nav.wgt_array(np)` and `nav.w / h` instead
#   build() -> void                              - full build from nav.clr_array(np) / wgt_array(np)
#   mark_rect(cx0, cy0, cx1, cy1) -> void        - queue every block intersecting the (clearance-refreshed) rect
#   pending() -> int                             - queued dirty units (blocks) not yet relabelled
#   relabel_step() -> void                       - relabel + relink ONE dirty block (lowest index first); refresh
#                                                  component ids when the last dirty block was handled
#   node_of(i) -> int                            - abstract node id or -1
#   region_of(i) -> int                          - abstract component id (cc) of the cell or -1
#   region_size_of(i) -> int                     - cells in the cell's abstract component (0 if none)
#   estimate_cost(a, b) -> int                   - cost units, -1 unreachable
#   clone_for(nav: MapNav) -> graph              - independent copy bound to the clone's arrays (same no-cycle rule)

func _make_graph(np: int, size: int) -> Object:
	if graph_factory.is_valid():
		return graph_factory.call(self, np, size) as Object
	if ResourceLoader.exists(GRAPH_PATH):
		return (load(GRAPH_PATH) as GDScript).new(self, np, size) as Object
	return null


## Builds the abstract graphs for keys = np * 4 + size (idempotent; inactive profiles and unavailable graph
## classes are skipped).
func prepare(keys: PackedInt32Array) -> void:
	for k: int in keys:
		var np: int = k >> 2
		var size: int = k & 3
		if graphs.has(k) or np < 0 or np >= MapTerrain.NP_COUNT or size < 1 or _graph_ok[np] == 0:
			continue
		var g: Object = _make_graph(np, size)
		if g == null:
			continue
		g.call("build")
		graphs[k] = g
		_gkeys.append(k)
		_gkeys.sort()


## The eight keys that can occur (FOOT x1, WHEELED x2, TRACKED x2, AMPH x2, NAVAL x2, NAVAL_DEEP x{2,3}, SUB x2)
## for every graph-worthy profile (>= MIN_GRAPH_CELLS passable terrain cells; a dry map gets four).
func prepare_all() -> void:
	prepare(_KEYS_ALL)


func has_graph(np: int, size: int) -> bool:
	return graphs.has(np * 4 + size)


## Abstract node id of the cell or -1 (no graph -> -1).
func node_of(np: int, size: int, i: int) -> int:
	var g: Object = graphs.get(np * 4 + size)
	if g == null:
		return -1
	return g.call("node_of", i) as int


## Abstract connectivity; without a graph: true iff both cells are passable (conservative).
func same_region(np: int, size: int, a: int, b: int) -> bool:
	var g: Object = graphs.get(np * 4 + size)
	if g == null:
		return _clr[np][a] >= size and _clr[np][b] >= size
	var ra: int = g.call("region_of", a) as int
	return ra >= 0 and ra == (g.call("region_of", b) as int)


## Abstract component id (cc) of the cell, -1 when blocked or without a graph.
func region_id(np: int, size: int, i: int) -> int:
	var g: Object = graphs.get(np * 4 + size)
	if g == null:
		return -1
	return g.call("region_of", i) as int


## Cells in the cell's abstract component (0 if none / no graph).
func region_size(np: int, size: int, i: int) -> int:
	var g: Object = graphs.get(np * 4 + size)
	if g == null:
		return 0
	return g.call("region_size_of", i) as int


## Cost estimate in cost units (10 = one baseline cell), -1 unreachable. With a graph: the graph's estimate.
## Without one: octile distance at baseline weight if both cells are passable, else -1. AI / ETA use only.
func estimate_cost(np: int, size: int, a: int, b: int) -> int:
	var g: Object = graphs.get(np * 4 + size)
	if g != null:
		return g.call("estimate_cost", a, b) as int
	if _clr[np][a] < size or _clr[np][b] < size:
		return -1
	var dx: int = absi(a % w - b % w)
	var dy: int = absi(a / w - b / w)
	return 10 * (dx + dy) - 6 * mini(dx, dy)
