class_name MapNavGraph
extends RefCounted
## Abstract block-component graph of one prepared (nav profile, size) pair (terrain_movement 5.2.1 / 4.7).
##
## Blocks are 8x8 cells; a NODE is a 4-connected component of cells with clearance >= size inside one block
## (node id = block * 8 + local slot, at most 8 kept per block). Edges join nodes of adjacent blocks (border cell
## pairs, and the two diagonals of a block corner when all four corner cells are passable); adjacency lists are
## kept SORTED by neighbour id so the structure never depends on the update history. `cc` = connected component
## per node (ids in ascending order of the first node). Dirty blocks (mark_rect) are relabelled one per
## `relabel_step` (the MapNav graph seam, map_nav.gd "GRAPH SEAM"). The graph never stores the MapNav (no cycle):
## it aliases `nav.clr_array(np)` / `nav.wgt_array(np)` (PackedArrays are shared by reference).
##
## `AbsSearch` (inner class) is the resumable Dial-bucket A* over the nodes, used by `estimate_cost` here and by
## MapPathSearch for the abstract phase. All integers, count-bounded, no clock (DR-1..11).

const BLOCK: int = 8
const MAX_DEG: int = 12
const ABS_BUCKETS: int = 1024  ## power of two

var np: int = 0
var size: int = 1
var w: int = 0
var h: int = 0
var nbx: int = 0
var nby: int = 0
var nodes: int = 0  ## nbx * nby * 8 (slot count)

var node_of_cell: PackedInt32Array = PackedInt32Array()  ## node id or -1 (impassable for this size)
var node_rep: PackedInt32Array = PackedInt32Array()  ## representative cell (-1 = empty slot)
var node_rx: PackedInt32Array = PackedInt32Array()  ## x / y of the representative (-1 = empty)
var node_ry: PackedInt32Array = PackedInt32Array()
var node_cnt: PackedInt32Array = PackedInt32Array()  ## cells of the node (0 = empty slot)
var node_sumw: PackedInt32Array = PackedInt32Array()  ## sum of path weights over the node's cells
var adj: PackedInt32Array = PackedInt32Array()  ## nodes * MAX_DEG neighbour ids (sorted ascending per node)
var adj_cost: PackedInt32Array = PackedInt32Array()  ## edge cost parallel to `adj`
var deg: PackedByteArray = PackedByteArray()
var cc: PackedInt32Array = PackedInt32Array()  ## component id per node, -1 for empty slots
var cc_cells: PackedInt32Array = PackedInt32Array()  ## cells per component id
var dirty: PackedByteArray = PackedByteArray()  ## per block

var _clr: PackedByteArray = PackedByteArray()  # alias of the nav layer (shared reference)
var _wgt: PackedByteArray = PackedByteArray()
var _dirty_cnt: int = 0
var _dirty_lo: int = 0
var _lab: PackedInt32Array = PackedInt32Array()  # 10x10 padded label scratch
var _stk: PackedInt32Array = PackedInt32Array()
var _csz: PackedInt32Array = PackedInt32Array()  # per-component scratch of _label_block (<= 32 components)
var _csw: PackedInt32Array = PackedInt32Array()
var _cbi: PackedInt32Array = PackedInt32Array()
var _slot: PackedInt32Array = PackedInt32Array()
var _est: AbsSearch = null


func _init(nav: MapNav, p_np: int, p_size: int) -> void:
	np = p_np
	size = p_size
	w = nav.w
	h = nav.h
	nbx = (w + BLOCK - 1) / BLOCK
	nby = (h + BLOCK - 1) / BLOCK
	nodes = nbx * nby * 8
	_clr = nav.clr_array(p_np)
	_wgt = nav.wgt_array(p_np)


# ---- build ---------------------------------------------------------------------------------------------------------

func _scratch() -> void:
	_lab.resize(100)
	_stk.resize(100)
	_csz.resize(64)
	_csw.resize(64)
	_cbi.resize(64)
	_slot.resize(64)


func _alloc() -> void:
	node_of_cell.resize(w * h)
	node_of_cell.fill(-1)
	node_rep.resize(nodes)
	node_rx.resize(nodes)
	node_ry.resize(nodes)
	node_cnt.resize(nodes)
	node_sumw.resize(nodes)
	adj.resize(nodes * MAX_DEG)
	adj_cost.resize(nodes * MAX_DEG)
	deg.resize(nodes)
	cc.resize(nodes)
	dirty.resize(nbx * nby)
	_scratch()
	adj.fill(0)
	adj_cost.fill(0)
	deg.fill(0)
	dirty.fill(0)
	_dirty_cnt = 0
	_dirty_lo = nbx * nby


## Full build from the aliased clearance / weight arrays.
func build() -> void:
	_alloc()
	var nb: int = nbx * nby
	for b: int in nb:
		_label_block(b)
	for b: int in nb:
		var bx: int = b % nbx
		var by: int = b / nbx
		if bx + 1 < nbx:
			_link_ortho(b, true)
		if by + 1 < nby:
			_link_ortho(b, false)
		if bx + 1 < nbx and by + 1 < nby:
			_link_corner(b)
	_refresh_cc()


## Independent copy bound to another MapNav (the clone's own arrays).
func clone_for(nav: MapNav) -> MapNavGraph:
	var g: MapNavGraph = MapNavGraph.new(nav, np, size)
	g.node_of_cell = node_of_cell.duplicate()
	g.node_rep = node_rep.duplicate()
	g.node_rx = node_rx.duplicate()
	g.node_ry = node_ry.duplicate()
	g.node_cnt = node_cnt.duplicate()
	g.node_sumw = node_sumw.duplicate()
	g.adj = adj.duplicate()
	g.adj_cost = adj_cost.duplicate()
	g.deg = deg.duplicate()
	g.cc = cc.duplicate()
	g.cc_cells = cc_cells.duplicate()
	g.dirty = dirty.duplicate()
	g._dirty_cnt = _dirty_cnt
	g._dirty_lo = _dirty_lo
	g._scratch()
	return g


## Test hook: structure equal to another graph (nodes, edges, component ids).
func equals(o: MapNavGraph) -> bool:
	return node_of_cell == o.node_of_cell and node_rep == o.node_rep and node_cnt == o.node_cnt \
			and node_sumw == o.node_sumw and adj == o.adj and adj_cost == o.adj_cost and deg == o.deg \
			and cc == o.cc and cc_cells == o.cc_cells


func _label_block(b: int) -> void:
	var bx: int = b % nbx
	var by: int = b / nbx
	var x0: int = bx * BLOCK
	var y0: int = by * BLOCK
	var bw: int = mini(BLOCK, w - x0)
	var bh: int = mini(BLOCK, h - y0)
	var base: int = b * 8
	var clr: PackedByteArray = _clr
	var nof: PackedInt32Array = node_of_cell
	for k: int in 8:
		var nd: int = base + k
		node_cnt[nd] = 0
		node_sumw[nd] = 0
		node_rep[nd] = -1
		node_rx[nd] = -1
		node_ry[nd] = -1
	# fast path: a full block whose every cell has clearance >= size, proven by a handful of clr == 3 probes
	if bw == BLOCK and bh == BLOCK:
		var c0: int = y0 * w + x0
		var full: bool
		if size == 1:
			full = clr[c0 + 2 * w + 2] == 3 and clr[c0 + 2 * w + 5] == 3 and clr[c0 + 5 * w + 2] == 3 \
					and clr[c0 + 5 * w + 5] == 3
		elif size == 2:
			full = clr[c0 + w + 1] == 3 and clr[c0 + w + 6] == 3 and clr[c0 + 6 * w + 1] == 3 \
					and clr[c0 + 6 * w + 6] == 3
		else:
			full = clr[c0] == 3 and clr[c0 + 5] == 3 and clr[c0 + 7] == 3 \
					and clr[c0 + 5 * w] == 3 and clr[c0 + 5 * w + 5] == 3 and clr[c0 + 5 * w + 7] == 3 \
					and clr[c0 + 7 * w] == 3 and clr[c0 + 7 * w + 5] == 3 and clr[c0 + 7 * w + 7] == 3
		if full:
			var sw: int = 0
			var wg: PackedByteArray = _wgt
			for ly: int in BLOCK:
				var ci: int = c0 + ly * w
				for lx: int in BLOCK:
					nof[ci + lx] = base
					sw += wg[ci + lx]
			node_cnt[base] = 64
			node_sumw[base] = sw
			node_rep[base] = (y0 + 3) * w + x0 + 3
			node_rx[base] = x0 + 3
			node_ry[base] = y0 + 3
			return
	# general path: 4-connected components in a 10x10 padded scratch (-2 impassable, -1 unlabelled, >= 0 component);
	# per-component cell count, weight sum and representative are accumulated during the flood
	var lab: PackedInt32Array = _lab
	var stk: PackedInt32Array = _stk
	var csz: PackedInt32Array = _csz
	var csw: PackedInt32Array = _csw
	var cbi: PackedInt32Array = _cbi
	var wg2: PackedByteArray = _wgt
	lab.fill(-2)
	for ly: int in bh:
		var ci: int = (y0 + ly) * w + x0
		var lo: int = (ly + 1) * 10 + 1
		for lx: int in bw:
			if clr[ci + lx] >= size:
				lab[lo + lx] = -1
	var ncomp: int = 0
	var cx: int = x0 + 3
	var cy: int = y0 + 3
	for ly: int in bh:
		for lx: int in bw:
			var li: int = (ly + 1) * 10 + lx + 1
			if lab[li] != -1:
				continue
			stk[0] = li
			var sp: int = 1
			lab[li] = ncomp
			var cnt: int = 0
			var sw: int = 0
			var bd: int = 99
			var bi: int = 0
			while sp > 0:
				sp -= 1
				var cl: int = stk[sp]
				cnt += 1
				var fx: int = cl % 10 - 1
				var fy: int = cl / 10 - 1
				var gi: int = (y0 + fy) * w + x0 + fx
				sw += wg2[gi]
				var dd: int = maxi(absi(x0 + fx - cx), absi(y0 + fy - cy))
				if dd < bd or (dd == bd and gi < bi):
					bd = dd
					bi = gi
				var m: int = cl + 1
				if lab[m] == -1:
					lab[m] = ncomp
					stk[sp] = m
					sp += 1
				m = cl - 1
				if lab[m] == -1:
					lab[m] = ncomp
					stk[sp] = m
					sp += 1
				m = cl + 10
				if lab[m] == -1:
					lab[m] = ncomp
					stk[sp] = m
					sp += 1
				m = cl - 10
				if lab[m] == -1:
					lab[m] = ncomp
					stk[sp] = m
					sp += 1
			csz[ncomp] = cnt
			csw[ncomp] = sw
			cbi[ncomp] = bi
			ncomp += 1
	# slot per component: at most 8, the 8 largest (ties: lowest first cell), renumbered in first-cell order
	var slot_of: PackedInt32Array = _slot
	if ncomp <= 8:
		for c: int in ncomp:
			slot_of[c] = c
	else:
		for c: int in ncomp:
			slot_of[c] = -1
		var keep: int = 0
		while keep < 8:
			var best: int = -1
			for c: int in ncomp:
				if slot_of[c] == -1 and (best < 0 or csz[c] > csz[best]):
					best = c
			slot_of[best] = -3
			keep += 1
		var rank: int = 0
		for c: int in ncomp:
			if slot_of[c] == -3:
				slot_of[c] = rank
				rank += 1
	for c: int in ncomp:
		var sl: int = slot_of[c]
		if sl >= 0:
			var nd: int = base + sl
			node_cnt[nd] = csz[c]
			node_sumw[nd] = csw[c]
			node_rep[nd] = cbi[c]
			node_rx[nd] = cbi[c] % w
			node_ry[nd] = cbi[c] / w
	for ly: int in bh:
		var ci: int = (y0 + ly) * w + x0
		var lo: int = (ly + 1) * 10 + 1
		for lx: int in bw:
			var lc: int = lab[lo + lx]
			nof[ci + lx] = -1 if lc < 0 else (base + slot_of[lc] if slot_of[lc] >= 0 else -1)


# ---- edges ---------------------------------------------------------------------------------------------------------

func _edge_cost(a: int, b: int) -> int:
	var dx: int = absi(node_rx[a] - node_rx[b])
	var dy: int = absi(node_ry[a] - node_ry[b])
	var oct: int = 10 * (dx + dy) - 6 * mini(dx, dy)
	var wa: int = node_sumw[a] / node_cnt[a]
	var wb: int = node_sumw[b] / node_cnt[b]
	return maxi(1, oct * (wa + wb) / 32)


## Undirected edge a-b (no-op if present or if either list is full).
func _add_edge(a: int, b: int) -> void:
	var oa: int = a * MAX_DEG
	var da: int = deg[a]
	var p: int = 0
	while p < da and adj[oa + p] < b:
		p += 1
	if p < da and adj[oa + p] == b:
		return
	var db: int = deg[b]
	if da >= MAX_DEG or db >= MAX_DEG:
		return
	var c: int = _edge_cost(a, b)
	var k: int = da
	while k > p:
		adj[oa + k] = adj[oa + k - 1]
		adj_cost[oa + k] = adj_cost[oa + k - 1]
		k -= 1
	adj[oa + p] = b
	adj_cost[oa + p] = c
	deg[a] = da + 1
	var ob: int = b * MAX_DEG
	var q: int = 0
	while q < db and adj[ob + q] < a:
		q += 1
	k = db
	while k > q:
		adj[ob + k] = adj[ob + k - 1]
		adj_cost[ob + k] = adj_cost[ob + k - 1]
		k -= 1
	adj[ob + q] = a
	adj_cost[ob + q] = c
	deg[b] = db + 1


func _remove_dir(a: int, b: int) -> void:
	var oa: int = a * MAX_DEG
	var da: int = deg[a]
	for p: int in da:
		if adj[oa + p] == b:
			for k: int in range(p, da - 1):
				adj[oa + k] = adj[oa + k + 1]
				adj_cost[oa + k] = adj_cost[oa + k + 1]
			adj[oa + da - 1] = 0
			adj_cost[oa + da - 1] = 0
			deg[a] = da - 1
			return


## Removes every edge between the nodes of block `ba` and block `bb`.
func _unlink_blocks(ba: int, bb: int) -> void:
	for k: int in 8:
		var a: int = ba * 8 + k
		var p: int = deg[a] - 1
		while p >= 0:
			var m: int = adj[a * MAX_DEG + p]
			if (m >> 3) == bb:
				_remove_dir(a, m)
				_remove_dir(m, a)
			p -= 1


## Border pairs between block a and its right (horiz) / lower neighbour b.
func _link_ortho(ba: int, horiz: bool) -> void:
	var bx: int = ba % nbx
	var by: int = ba / nbx
	var x0: int = bx * BLOCK
	var y0: int = by * BLOCK
	var nof: PackedInt32Array = node_of_cell
	var last_a: int = -1
	var last_b: int = -1
	if horiz:
		var rows: int = mini(BLOCK, h - y0)
		for k: int in rows:
			var ci: int = (y0 + k) * w + x0 + BLOCK - 1
			var na: int = nof[ci]
			var nb: int = nof[ci + 1]
			if na >= 0 and nb >= 0 and (na != last_a or nb != last_b):
				_add_edge(na, nb)
				last_a = na
				last_b = nb
	else:
		var cols: int = mini(BLOCK, w - x0)
		var ci0: int = (y0 + BLOCK - 1) * w + x0
		for k: int in cols:
			var na: int = nof[ci0 + k]
			var nb: int = nof[ci0 + w + k]
			if na >= 0 and nb >= 0 and (na != last_a or nb != last_b):
				_add_edge(na, nb)
				last_a = na
				last_b = nb


## Corner shared by block `tl` and its right / lower / lower-right neighbours: the two diagonal links when all
## four corner cells are passable.
func _link_corner(tl: int) -> void:
	var bx: int = tl % nbx
	var by: int = tl / nbx
	var c: int = (by * BLOCK + BLOCK - 1) * w + bx * BLOCK + BLOCK - 1
	var nt: int = node_of_cell[c]
	var nr: int = node_of_cell[c + 1]
	var nl: int = node_of_cell[c + w]
	var nd: int = node_of_cell[c + w + 1]
	if nt >= 0 and nr >= 0 and nl >= 0 and nd >= 0:
		_add_edge(nt, nd)
		_add_edge(nr, nl)


# ---- components ----------------------------------------------------------------------------------------------------

func _refresh_cc() -> void:
	cc.fill(-1)
	cc_cells = PackedInt32Array()
	var stack: PackedInt32Array = PackedInt32Array()
	stack.resize(nodes + 1)
	var ncc: int = 0
	for s: int in nodes:
		if cc[s] != -1 or node_cnt[s] == 0:
			continue
		var cells: int = 0
		var sp: int = 1
		stack[0] = s
		cc[s] = ncc
		while sp > 0:
			sp -= 1
			var a: int = stack[sp]
			cells += node_cnt[a]
			var o: int = a * MAX_DEG
			for k: int in deg[a]:
				var m: int = adj[o + k]
				if cc[m] == -1:
					cc[m] = ncc
					stack[sp] = m
					sp += 1
		cc_cells.append(cells)
		ncc += 1


# ---- MapNav graph seam ---------------------------------------------------------------------------------------------

## Queues every block intersecting the (clearance-refreshed) cell rect.
func mark_rect(cx0: int, cy0: int, cx1: int, cy1: int) -> void:
	var x0: int = maxi(cx0, 0)
	var y0: int = maxi(cy0, 0)
	var x1: int = mini(cx1, w - 1)
	var y1: int = mini(cy1, h - 1)
	if x0 > x1 or y0 > y1:
		return
	for by: int in range(y0 / BLOCK, y1 / BLOCK + 1):
		for bx: int in range(x0 / BLOCK, x1 / BLOCK + 1):
			var b: int = by * nbx + bx
			if dirty[b] == 0:
				dirty[b] = 1
				_dirty_cnt += 1
				if b < _dirty_lo:
					_dirty_lo = b


func pending() -> int:
	return _dirty_cnt


## Relabels and relinks ONE dirty block (lowest index first); refreshes component ids after the last one.
func relabel_step() -> void:
	if _dirty_cnt == 0:
		return
	var nb: int = nbx * nby
	var b: int = _dirty_lo
	while b < nb and dirty[b] == 0:
		b += 1
	dirty[b] = 0
	_dirty_cnt -= 1
	_dirty_lo = b + 1 if _dirty_cnt > 0 else nb
	_relabel(b)
	if _dirty_cnt == 0:
		_refresh_cc()


func _relabel(b: int) -> void:
	var bx: int = b % nbx
	var by: int = b / nbx
	for k: int in 8:
		var a: int = b * 8 + k
		while deg[a] > 0:
			var m: int = adj[a * MAX_DEG]
			_remove_dir(m, a)
			_remove_dir(a, m)
	_label_block(b)
	if bx > 0:
		_link_ortho(b - 1, true)
	if bx + 1 < nbx:
		_link_ortho(b, true)
	if by > 0:
		_link_ortho(b - nbx, false)
	if by + 1 < nby:
		_link_ortho(b, false)
	# the four block corners touching b (top-left block of each corner); the pair not involving b is refreshed too
	for oy: int in [-1, 0]:
		for ox: int in [-1, 0]:
			var cx: int = bx + ox
			var cy: int = by + oy
			if cx < 0 or cy < 0 or cx + 1 >= nbx or cy + 1 >= nby:
				continue
			var tl: int = cy * nbx + cx
			_unlink_blocks(tl, tl + nbx + 1)
			_unlink_blocks(tl + 1, tl + nbx)
			_link_corner(tl)


func node_of(i: int) -> int:
	return node_of_cell[i]


func region_of(i: int) -> int:
	var nd: int = node_of_cell[i]
	return cc[nd] if nd >= 0 else -1


func region_size_of(i: int) -> int:
	var nd: int = node_of_cell[i]
	if nd < 0 or cc[nd] < 0 or cc[nd] >= cc_cells.size():
		return 0
	return cc_cells[cc[nd]]


## Average path weight of a node (sumw / cnt), 16 for an empty slot.
func avg_w(nd: int) -> int:
	return node_sumw[nd] / node_cnt[nd] if node_cnt[nd] > 0 else 16


## Cost units (10 = one baseline cell), -1 unreachable: octile(a, rep_S) * w_S / 16 + abstract A* cost +
## octile(rep_G, b) * w_G / 16. AI / ETA use only (private scratch, not resumable).
func estimate_cost(a: int, b: int) -> int:
	if a < 0 or b < 0 or a >= w * h or b >= w * h:
		return -1
	var s: int = node_of_cell[a]
	var g: int = node_of_cell[b]
	if s < 0 or g < 0:
		return -1
	if cc[s] != cc[g]:
		return -1
	var ax: int = a % w
	var ay: int = a / w
	var bx: int = b % w
	var by: int = b / w
	if s == g:
		var ddx: int = absi(ax - bx)
		var ddy: int = absi(ay - by)
		return (10 * (ddx + ddy) - 6 * mini(ddx, ddy)) * avg_w(s) / 16
	if _est == null:
		_est = AbsSearch.new(nodes)
	_est.begin(self, s, g)
	while _est.state == AbsSearch.RUNNING:
		_est.step(1 << 30)
	if _est.state != AbsSearch.FOUND:
		return -1
	var d1x: int = absi(ax - node_rx[s])
	var d1y: int = absi(ay - node_ry[s])
	var d2x: int = absi(bx - node_rx[g])
	var d2y: int = absi(by - node_ry[g])
	return (10 * (d1x + d1y) - 6 * mini(d1x, d1y)) * avg_w(s) / 16 + _est.cost \
			+ (10 * (d2x + d2y) - 6 * mini(d2x, d2y)) * avg_w(g) / 16


## Resumable Dial-bucket A* over the abstract nodes (1024 circular buckets, LIFO per bucket, key clamped to the
## current key, neighbour order = adjacency order). 2 budget units per expansion. Holds references to the graph
## ARRAYS only (never to the graph), so a graph may own one without a reference cycle.
class AbsSearch extends RefCounted:
	const RUNNING: int = 0
	const FOUND: int = 1
	const FAILED: int = 2
	const IDLE: int = 3

	var state: int = IDLE
	var cost: int = 0  ## g of the goal when FOUND
	var pops: int = 0

	var _g: PackedInt32Array = PackedInt32Array()
	var _vis: PackedInt32Array = PackedInt32Array()
	var _closed: PackedInt32Array = PackedInt32Array()
	var _par: PackedInt32Array = PackedInt32Array()
	var _head: PackedInt32Array = PackedInt32Array()
	var _en: PackedInt32Array = PackedInt32Array()
	var _enext: PackedInt32Array = PackedInt32Array()
	var _eg: PackedInt32Array = PackedInt32Array()
	var _serial: int = 0
	var _cur: int = 0
	var _rem: int = 0
	var _ne: int = 0
	var _goal: int = -1
	var _gx: int = 0
	var _gy: int = 0
	var _adj: PackedInt32Array = PackedInt32Array()
	var _adjc: PackedInt32Array = PackedInt32Array()
	var _deg: PackedByteArray = PackedByteArray()
	var _rx: PackedInt32Array = PackedInt32Array()
	var _ry: PackedInt32Array = PackedInt32Array()
	var _start: int = -1


	func _init(p_nodes: int) -> void:
		_g.resize(p_nodes)
		_vis.resize(p_nodes)
		_closed.resize(p_nodes)
		_par.resize(p_nodes)
		_head.resize(ABS_BUCKETS)
		_en.resize(p_nodes * MAX_DEG + 16)
		_enext.resize(p_nodes * MAX_DEG + 16)
		_eg.resize(p_nodes * MAX_DEG + 16)


	func begin(gr: MapNavGraph, s: int, goal: int) -> void:
		_adj = gr.adj
		_adjc = gr.adj_cost
		_deg = gr.deg
		_rx = gr.node_rx
		_ry = gr.node_ry
		_serial += 1
		_head.fill(-1)
		_ne = 0
		_rem = 0
		pops = 0
		cost = 0
		_goal = goal
		_start = s
		_gx = _rx[goal]
		_gy = _ry[goal]
		_g[s] = 0
		_vis[s] = _serial
		_par[s] = -1
		var dx: int = absi(_rx[s] - _gx)
		var dy: int = absi(_ry[s] - _gy)
		var f: int = 10 * (dx + dy) - 6 * mini(dx, dy)
		_cur = f
		_en[0] = s
		_eg[0] = 0
		_enext[0] = -1
		_head[f & (ABS_BUCKETS - 1)] = 0
		_ne = 1
		_rem = 1
		state = RUNNING


	## Runs while the next expansion fits in `max_units` (2 units each); returns the units consumed.
	func step(max_units: int) -> int:
		if state != RUNNING:
			return 0
		var units: int = 0
		var head: PackedInt32Array = _head
		var en: PackedInt32Array = _en
		var enext: PackedInt32Array = _enext
		var eg: PackedInt32Array = _eg
		var g: PackedInt32Array = _g
		var vis: PackedInt32Array = _vis
		var closed: PackedInt32Array = _closed
		var par: PackedInt32Array = _par
		var adj: PackedInt32Array = _adj
		var adjc: PackedInt32Array = _adjc
		var dg: PackedByteArray = _deg
		var rx: PackedInt32Array = _rx
		var ry: PackedInt32Array = _ry
		var serial: int = _serial
		var cur: int = _cur
		var rem: int = _rem
		var ne: int = _ne
		var gx: int = _gx
		var gy: int = _gy
		var mask: int = ABS_BUCKETS - 1
		var pool: int = en.size()
		while units + 2 <= max_units:
			if rem <= 0:
				state = FAILED
				break
			var e: int = head[cur & mask]
			if e < 0:
				cur += 1
				continue
			head[cur & mask] = enext[e]
			rem -= 1
			var n: int = en[e]
			if closed[n] == serial or eg[e] != g[n]:
				continue
			closed[n] = serial
			units += 2
			pops += 1
			if n == _goal:
				state = FOUND
				cost = g[n]
				break
			var gn: int = g[n]
			var o: int = n * MAX_DEG
			for k: int in dg[n]:
				var m: int = adj[o + k]
				if closed[m] == serial:
					continue
				var ng: int = gn + adjc[o + k]
				if vis[m] == serial and g[m] <= ng:
					continue
				if ne >= pool:
					continue
				vis[m] = serial
				g[m] = ng
				par[m] = n
				var ddx: int = absi(rx[m] - gx)
				var ddy: int = absi(ry[m] - gy)
				var f: int = ng + 10 * (ddx + ddy) - 6 * mini(ddx, ddy)
				if f < cur:
					f = cur
				elif f - cur >= ABS_BUCKETS:
					f = cur + ABS_BUCKETS - 1
				en[ne] = m
				eg[ne] = ng
				enext[ne] = head[f & mask]
				head[f & mask] = ne
				ne += 1
				rem += 1
		_cur = cur
		_rem = rem
		_ne = ne
		return units


	## Node route start..goal (inclusive) of a FOUND search.
	func route(out: PackedInt32Array) -> void:
		out.clear()
		var n: int = _goal
		while n >= 0:
			out.append(n)
			n = _par[n]
		out.reverse()
