class_name MapPathSearch
extends RefCounted
## Resumable, count-budgeted path search on the MapNav layers (terrain_movement 3.5 / 5.3): LOS shortcut ->
## fine Dial-bucket A* (short queries, capped) -> abstract A* over the MapNavGraph + corridor-restricted fine A*
## (long queries) -> cost-checked string-pulling smoothing. One instance per SimPathService; the scratch arrays
## (sized w*h) are allocated once and never cleared: a monotonic `serial` invalidates them (DR-9).
##
## Determinism: integer costs only; neighbour order E, W, S, N, SE, SW, NE, NW is the tie-break; LIFO buckets;
## the work is metered in UNITS (1 per fine expansion, 2 per abstract expansion, ceil(cells/8) per LOS) and the
## result never depends on the budget a step() call was given (DR-11). No clock, no RNG.
##
## Passability is tested with the live clearance (`clr >= size`), costs with the live weights, so the search is
## exact even while the abstract graph is dirty (the graph is only used to restrict / guide long searches).

const ST_IDLE: int = 0
const ST_RUNNING: int = 1
const ST_DONE: int = 2
const ST_PARTIAL: int = 3
const ST_NO_PATH: int = 4

const PH_IDLE: int = 0
const PH_LOS: int = 1
const PH_FINE: int = 2
const PH_ABS: int = 3
const PH_CORR: int = 4
const PH_SMOOTH: int = 5

const HIER_MIN_OCTILE: int = 240  ## below: unrestricted fine search first (24 baseline cells)
const FINE_CAP: int = 2400  ## expansions of the short fine search before the corridor is used
const MAX_EXPANSIONS: int = 12000
const MAX_WAYPOINTS: int = 160
const MAX_AVOID: int = 16
const NB: int = 128  ## fine buckets (power of two)
const _SPANS: PackedInt32Array = [24, 16, 12, 8, 6, 4, 3, 2]

const _FR_RUN: int = 0
const _FR_FOUND: int = 1
const _FR_CAP: int = 2
const _FR_EXHAUSTED: int = 3
const _FR_OVERFLOW: int = 4

var status: int = ST_IDLE
var path: PackedInt32Array = PackedInt32Array()  ## waypoint cells, start EXCLUDED, last = goal (best node when PARTIAL)
var path_cost: int = 0  ## unsmoothed fine cost of the accepted route (cost units)
var expanded: int = 0  ## fine + abstract (x2) expansions used
var force_mode: int = 0  ## test hook: 0 auto, 1 fine A* only, 2 corridor only
var corridor_dilate: int = 0  ## 1 = also stamp the 1-hop neighbours of the abstract route (quality mode)
var serial: int = 0
var cur: int = 0  ## current bucket key of the fine search
var remaining: int = 0  ## live entries in the fine buckets
var ne: int = 0  ## entries used in the fine pool

var nav: MapNav = null

var _w: int = 0
var _n: int = 0
var _col: PackedInt32Array = PackedInt32Array()
var _row: PackedInt32Array = PackedInt32Array()
var _so: PackedByteArray = PackedByteArray()
var _sd: PackedByteArray = PackedByteArray()
var _offs: PackedInt32Array = PackedInt32Array()
var _odx: PackedInt32Array = PackedInt32Array()
var _ody: PackedInt32Array = PackedInt32Array()
var _dxs: PackedInt32Array = PackedInt32Array([1, -1, 0, 0, 1, -1, 1, -1])
var _dys: PackedInt32Array = PackedInt32Array([0, 0, 1, -1, 1, 1, -1, -1])
# fine scratch
var _g: PackedInt32Array = PackedInt32Array()
var _vis: PackedInt32Array = PackedInt32Array()
var _closed: PackedInt32Array = PackedInt32Array()
var _parent: PackedInt32Array = PackedInt32Array()
var _head: PackedInt32Array = PackedInt32Array()
var _e_node: PackedInt32Array = PackedInt32Array()
var _e_next: PackedInt32Array = PackedInt32Array()
var _e_g: PackedInt32Array = PackedInt32Array()
# abstract scratch
var _abs: MapNavGraph.AbsSearch = null
var _corr_stamp: PackedInt32Array = PackedInt32Array()
var _corr_serial: int = 0
var _route: PackedInt32Array = PackedInt32Array()
# current search
var _phase: int = PH_IDLE
var _np: int = 0
var _size: int = 1
var _start: int = 0
var _goal: int = 0
var _goal_r: int = 0
var _gx: int = 0
var _gy: int = 0
var _avoid: PackedInt32Array = PackedInt32Array()
var _wgt: PackedByteArray = PackedByteArray()
var _clr: PackedByteArray = PackedByteArray()
var _graph: MapNavGraph = null
var _nof: PackedInt32Array = PackedInt32Array()
var _fine_kind: int = 0  ## 0 short (capped), 1 unrestricted, 2 corridor
var _fine_exp: int = 0
var _fine_res: int = 0
var _found: int = -1
var _best_h: int = 0
var _best_g: int = 0
var _best_n: int = 0
var _partial: bool = false
var _blocked: bool = false
# smoothing
var _raw: PackedInt32Array = PackedInt32Array()
var _rawg: PackedInt32Array = PackedInt32Array()
var _sm_i: int = 0
var _sm_k: int = 0
var _sm_last: int = -1
var _sm_out: PackedInt32Array = PackedInt32Array()


func _init(p_nav: MapNav) -> void:
	nav = p_nav
	_w = p_nav.w
	_n = p_nav.n
	_col = p_nav.col
	_row = p_nav.row
	_so = p_nav.tt.step_o_table()
	_sd = p_nav.tt.step_d_table()
	var w: int = _w
	_offs = PackedInt32Array([1, -1, w, -w, w + 1, w - 1, -w + 1, -w - 1])
	_odx = PackedInt32Array([0, 0, 0, 0, 1, -1, 1, -1])
	_ody = PackedInt32Array([0, 0, 0, 0, w, w, -w, -w])
	_g.resize(_n)
	_vis.resize(_n)
	_closed.resize(_n)
	_parent.resize(_n)
	_head.resize(NB)
	_head.fill(-1)
	_e_node.resize(4 * _n)
	_e_next.resize(4 * _n)
	_e_g.resize(4 * _n)
	var nodes: int = ((_w + 7) / 8) * ((p_nav.h + 7) / 8) * 8
	_corr_stamp.resize(nodes)
	_abs = MapNavGraph.AbsSearch.new(nodes)


# ---- public API ----------------------------------------------------------------------------------------------------

## goal_r: stop when the Chebyshev distance to the goal is <= goal_r (0 = exact). avoid: <= 16 cells treated as
## blocked for this search only. Different abstract components (graph present, graph not dirty) => ST_NO_PATH
## at once with expanded == 0. A start on the outermost map ring or an out-of-range cell => ST_NO_PATH.
func begin(np: int, size: int, start: int, goal: int, goal_r: int, avoid: PackedInt32Array) -> void:
	path = PackedInt32Array()
	path_cost = 0
	expanded = 0
	_phase = PH_IDLE
	_partial = false
	_blocked = false
	_np = np
	_size = size
	_start = start
	_goal = goal
	_goal_r = goal_r
	_avoid = avoid.slice(0, MAX_AVOID) if avoid.size() > MAX_AVOID else avoid
	if start < 0 or goal < 0 or start >= _n or goal >= _n or np < 0 or np >= MapTerrain.NP_COUNT:
		status = ST_NO_PATH
		return
	_gx = _col[goal]
	_gy = _row[goal]
	var sx: int = _col[start]
	var sy: int = _row[start]
	if sx < 1 or sy < 1 or sx >= _w - 1 or sy >= nav.h - 1:
		status = ST_NO_PATH
		return
	_wgt = nav.wgt_array(np)
	_clr = nav.clr_array(np)
	_graph = nav.graphs.get(np * 4 + size) as MapNavGraph
	_nof = _graph.node_of_cell if _graph != null else PackedInt32Array()
	if _reached(start):
		status = ST_DONE
		return
	if _graph != null and _graph.pending() == 0:
		var s: int = _nof[start]
		var g: int = _nof[goal]
		if s >= 0 and g >= 0 and _graph.cc[s] != _graph.cc[g]:
			status = ST_NO_PATH
			return
	status = ST_RUNNING
	if force_mode == 0:
		_phase = PH_LOS
	else:
		_after_los()


## Runs until done or `budget` units are consumed; returns the units consumed (>= 1 while RUNNING; never more
## than `budget` except for the single indivisible operation of a call that would otherwise make no progress).
func step(budget: int) -> int:
	if status != ST_RUNNING:
		return 0
	var units: int = 0
	_blocked = false
	while status == ST_RUNNING and units < budget and not _blocked:
		var first: bool = units == 0
		var left: int = budget - units
		if _phase == PH_FINE or _phase == PH_CORR:
			units += _ph_fine(left)
		elif _phase == PH_LOS:
			units += _ph_los(first, left)
		elif _phase == PH_ABS:
			units += _ph_abs(first, left)
		elif _phase == PH_SMOOTH:
			units += _ph_smooth(first, left)
		else:
			status = ST_NO_PATH
	return units


func cancel() -> void:
	status = ST_IDLE
	_phase = PH_IDLE


## The resumable state (enters SimPathService.hash_state): serial, status, expanded, cur, remaining, ne, phase.
func state_ints(buf: PackedInt32Array) -> void:
	buf.append(serial)
	buf.append(status)
	buf.append(expanded)
	buf.append(cur)
	buf.append(remaining)
	buf.append(ne)
	buf.append(_phase)


# ---- helpers -------------------------------------------------------------------------------------------------------

func _reached(c: int) -> bool:
	if _goal_r == 0:
		return c == _goal
	return maxi(absi(_col[c] - _gx), absi(_row[c] - _gy)) <= _goal_r


func _octile(a: int, b: int) -> int:
	var dx: int = absi(_col[a] - _col[b])
	var dy: int = absi(_row[a] - _row[b])
	return 10 * (dx + dy) - 6 * mini(dx, dy)


## True when an avoid cell lies in the bounding box of the segment a-b grown by one cell (the LOS shortcut and the
## smoothing ignore `avoid`, so they are not used across such a segment).
func _avoid_near(a: int, b: int) -> bool:
	if _avoid.is_empty():
		return false
	var x0: int = mini(_col[a], _col[b]) - 1
	var x1: int = maxi(_col[a], _col[b]) + 1
	var y0: int = mini(_row[a], _row[b]) - 1
	var y1: int = maxi(_row[a], _row[b]) + 1
	for c: int in _avoid:
		if _col[c] >= x0 and _col[c] <= x1 and _row[c] >= y0 and _row[c] <= y1:
			return true
	return false


func _fail_or_partial(node: int) -> void:
	if node == _start:
		status = ST_NO_PATH
		return
	_finish_fine(node, true)


# ---- phase LOS -----------------------------------------------------------------------------------------------------

func _ph_los(first: bool, left: int) -> int:
	var cheb: int = maxi(absi(_col[_start] - _gx), absi(_row[_start] - _gy))
	var cost: int = 1 + (cheb + 7) / 8
	if not first and cost > left:
		_blocked = true
		return 0
	var lc: int = nav.los_cost(_np, _size, _start, _goal)
	var oct: int = _octile(_start, _goal)
	if lc >= 0 and lc <= oct + oct / 4 and not _avoid_near(_start, _goal):
		path = PackedInt32Array([_goal])
		path_cost = lc
		status = ST_DONE
	else:
		_after_los()
	return cost


func _after_los() -> void:
	if _graph == null or force_mode == 1:
		_fine_begin(1)
	elif force_mode == 2:
		_abs_begin()
	elif _octile(_start, _goal) < HIER_MIN_OCTILE:
		_fine_begin(0)
	else:
		_abs_begin()


# ---- fine search ---------------------------------------------------------------------------------------------------

func _fine_begin(kind: int) -> void:
	serial += 1
	_head.fill(-1)
	ne = 0
	remaining = 0
	_fine_kind = kind
	_fine_exp = 0
	_phase = PH_CORR if kind == 2 else PH_FINE
	for a: int in _avoid:
		_closed[a] = serial
	var s: int = _start
	_closed[s] = 0
	_g[s] = 0
	_vis[s] = serial
	_parent[s] = -1
	var h0: int = _octile(s, _goal)
	_best_h = h0
	_best_g = 0
	_best_n = s
	cur = h0
	_e_node[0] = s
	_e_g[0] = 0
	_e_next[0] = -1
	_head[h0 & (NB - 1)] = 0
	ne = 1
	remaining = 1


func _ph_fine(left: int) -> int:
	var units: int = _fine_run(left)
	expanded += units
	match _fine_res:
		_FR_FOUND:
			_finish_fine(_found, false)
		_FR_CAP:
			if _fine_kind == 0:
				_abs_begin()
			else:
				_fail_or_partial(_best_n)
		_FR_EXHAUSTED:
			if _fine_kind == 2:
				_fine_begin(1)
			else:
				_fail_or_partial(_best_n)
		_FR_OVERFLOW:
			_fail_or_partial(_best_n)
	return units


## Inner loop of the fine A* (see the spec listing). Locals cache every array; state is written back on exit.
func _fine_run(max_units: int) -> int:
	var wgt: PackedByteArray = _wgt
	var clr: PackedByteArray = _clr
	var parent: PackedInt32Array = _parent
	var g: PackedInt32Array = _g
	var vis: PackedInt32Array = _vis
	var closed: PackedInt32Array = _closed
	var head: PackedInt32Array = _head
	var e_node: PackedInt32Array = _e_node
	var e_next: PackedInt32Array = _e_next
	var e_g: PackedInt32Array = _e_g
	var so: PackedByteArray = _so
	var sd: PackedByteArray = _sd
	var offs: PackedInt32Array = _offs
	var odx: PackedInt32Array = _odx
	var ody: PackedInt32Array = _ody
	var dxs: PackedInt32Array = _dxs
	var dys: PackedInt32Array = _dys
	var col: PackedInt32Array = _col
	var row: PackedInt32Array = _row
	var nof: PackedInt32Array = _nof
	var stamp: PackedInt32Array = _corr_stamp
	var cs: int = _corr_serial
	var corr: bool = _fine_kind == 2
	var size: int = _size
	var ser: int = serial
	var goal: int = _goal
	var gx: int = _gx
	var gy: int = _gy
	var gr: int = _goal_r
	var cap: int = FINE_CAP if _fine_kind == 0 else MAX_EXPANSIONS
	var pool: int = e_node.size()
	var cu: int = cur
	var rem: int = remaining
	var nel: int = ne
	var ex: int = _fine_exp
	var best_h: int = _best_h
	var best_g: int = _best_g
	var best_n: int = _best_n
	var res: int = _FR_RUN
	var units: int = 0
	while units < max_units:
		if ex >= cap:
			res = _FR_CAP
			break
		if rem <= 0:
			res = _FR_EXHAUSTED
			break
		var e: int = head[cu & 127]
		if e < 0:
			cu += 1
			continue
		head[cu & 127] = e_next[e]
		rem -= 1
		var n: int = e_node[e]
		if closed[n] == ser or e_g[e] != g[n]:
			continue
		closed[n] = ser
		units += 1
		ex += 1
		if n == goal or (gr > 0 and maxi(absi(col[n] - gx), absi(row[n] - gy)) <= gr):
			res = _FR_FOUND
			_found = n
			break
		if nel + 8 > pool:
			res = _FR_OVERFLOW
			break
		var gn: int = g[n]
		var nx: int = col[n]
		var ny: int = row[n]
		for k: int in 8:
			var m: int = n + offs[k]
			if clr[m] < size or closed[m] == ser:
				continue
			if corr:
				var nn: int = nof[m]
				if nn < 0 or stamp[nn] != cs:
					continue
			var wc: int = wgt[m]
			var stc: int
			if k < 4:
				stc = so[wc]
			else:
				if wgt[n + odx[k]] == 0 or wgt[n + ody[k]] == 0:
					continue
				stc = sd[wc]
			var ng: int = gn + stc
			if vis[m] == ser and g[m] <= ng:
				continue
			vis[m] = ser
			g[m] = ng
			parent[m] = n
			var ddx: int = nx + dxs[k] - gx
			if ddx < 0:
				ddx = -ddx
			var ddy: int = ny + dys[k] - gy
			if ddy < 0:
				ddy = -ddy
			var hh: int = 10 * (ddx + ddy) - 6 * (ddx if ddx < ddy else ddy)
			var f: int = ng + hh
			if f < cu:
				f = cu
			e_node[nel] = m
			e_g[nel] = ng
			e_next[nel] = head[f & 127]
			head[f & 127] = nel
			nel += 1
			rem += 1
			if hh < best_h or (hh == best_h and (ng < best_g or (ng == best_g and m < best_n))):
				best_h = hh
				best_g = ng
				best_n = m
	cur = cu
	remaining = rem
	ne = nel
	_fine_exp = ex
	_best_h = best_h
	_best_g = best_g
	_best_n = best_n
	_fine_res = res
	return units


## Reconstructs the raw cell route (start included) ending at `node` and starts the smoothing phase.
func _finish_fine(node: int, partial: bool) -> void:
	path_cost = _g[node]
	_partial = partial
	_raw = PackedInt32Array()
	_rawg = PackedInt32Array()
	var c: int = node
	while c != _start:
		_raw.append(c)
		c = _parent[c]
	_raw.append(_start)
	_raw.reverse()
	_rawg.resize(_raw.size())
	for i: int in _raw.size():
		_rawg[i] = _g[_raw[i]]
	_sm_i = 0
	_sm_k = 0
	_sm_last = -1
	_sm_out = PackedInt32Array()
	_phase = PH_SMOOTH


# ---- abstract + corridor -------------------------------------------------------------------------------------------

func _abs_begin() -> void:
	var gr: MapNavGraph = _graph
	if gr == null:
		_fine_begin(1)
		return
	var s: int = _nof[_start]
	if s < 0:
		var sc: int = nav.nearest_passable(_np, _size, _start, 3)
		s = _nof[sc] if sc >= 0 else -1
	var g: int = _nof[_goal]
	if g < 0:
		var gc: int = nav.nearest_passable(_np, _size, _goal, 6)
		g = _nof[gc] if gc >= 0 else -1
	if s < 0 or g < 0:
		_fine_begin(1)
		return
	_abs.begin(gr, s, g)
	_phase = PH_ABS


func _ph_abs(first: bool, left: int) -> int:
	var lim: int = left
	if first and lim < 2:
		lim = 2
	var used: int = _abs.step(lim)
	expanded += used
	if _abs.state == MapNavGraph.AbsSearch.FOUND:
		_abs.route(_route)
		_corr_begin()
	elif _abs.state == MapNavGraph.AbsSearch.FAILED:
		_fine_begin(1)
	elif used == 0:
		_blocked = true
	return used


func _corr_begin() -> void:
	_corr_serial += 1
	var gr: MapNavGraph = _graph
	for nd: int in _route:
		_corr_stamp[nd] = _corr_serial
		if corridor_dilate != 0:
			var o: int = nd * MapNavGraph.MAX_DEG
			for k: int in gr.deg[nd]:
				_corr_stamp[gr.adj[o + k]] = _corr_serial
	_fine_begin(2)


# ---- smoothing -----------------------------------------------------------------------------------------------------

func _ph_smooth(first: bool, left: int) -> int:
	var units: int = 0
	var rn: int = _raw.size()
	while true:
		if _sm_i >= rn - 1:
			_finish_smooth(false)
			return units
		if _sm_out.size() >= MAX_WAYPOINTS:
			_finish_smooth(true)
			return units
		var acc: int = -1
		while _sm_k < 8:
			var jj: int = mini(_sm_i + _SPANS[_sm_k], rn - 1)
			if jj <= _sm_i + 1 or jj == _sm_last:
				_sm_k += 1
				continue
			var a: int = _raw[_sm_i]
			var b: int = _raw[jj]
			var cheb: int = maxi(absi(_col[a] - _col[b]), absi(_row[a] - _row[b]))
			var cost: int = (cheb + 8) / 8
			if not (first and units == 0) and units + cost > left:
				_blocked = true
				return units
			units += cost
			_sm_last = jj
			_sm_k += 1
			var lc: int = nav.los_cost(_np, _size, a, b)
			if lc >= 0 and lc <= _rawg[jj] - _rawg[_sm_i] and not _avoid_near(a, b):
				acc = jj
				break
		if acc < 0:
			acc = _sm_i + 1
		_sm_out.append(_raw[acc])
		_sm_i = acc
		_sm_k = 0
		_sm_last = -1
		if units >= left:
			return units
	return units


func _finish_smooth(truncated: bool) -> void:
	path = _sm_out
	_sm_out = PackedInt32Array()
	status = ST_PARTIAL if (_partial or truncated) else ST_DONE
	_phase = PH_IDLE
