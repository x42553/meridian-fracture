class_name AiRouteJob
extends AiJob
## Resumable threat-aware A* over an AiRouteGraph (ai.md 2.3): a node expansion costs 2 wu. result() = waypoints
## [x0, y0, ...] (empty = unreachable). Stepping with a budget of any size makes progress; done is set on completion.

var graph: AiRouteGraph = null
var mc: int = 0
var weight_q8: int = 0
var fx: int = 0
var fy: int = 0
var tx: int = 0
var ty: int = 0
var expanded: int = 0

var _blocked: Dictionary = {}
var _start: int = -1
var _goal: int = -1
var _g: PackedInt32Array = PackedInt32Array()
var _from: PackedInt32Array = PackedInt32Array()
var _closed: PackedByteArray = PackedByteArray()
var _heap: PackedInt64Array = PackedInt64Array()
var _result: PackedInt32Array = PackedInt32Array()
var _started: bool = false


func _init(p_graph: AiRouteGraph, p_fx: int, p_fy: int, p_tx: int, p_ty: int, p_mc: int, p_weight: int, blocked: Dictionary) -> void:
	graph = p_graph
	fx = p_fx
	fy = p_fy
	tx = p_tx
	ty = p_ty
	mc = p_mc
	weight_q8 = p_weight
	_blocked = blocked


func _begin() -> void:
	_started = true
	_start = graph.snap_open(fx, fy, mc)
	_goal = graph.snap_open(tx, ty, mc)
	if _start < 0 or _goal < 0:
		done = true
		return
	var comp: PackedInt32Array = graph._comp[mc]
	if comp[_start] != comp[_goal]:
		done = true  # different components: unreachable without a search
		return
	var n: int = graph.bw * graph.bh
	_g.resize(n)
	_g.fill(1 << 30)
	_from.resize(n)
	_from.fill(-1)
	_closed.resize(n)
	_g[_start] = 0
	_push(graph.heuristic(_start, _goal), _start)


func step(budget: AiBudget) -> void:
	if done:
		return
	if not _started:
		_begin()
		if done:
			return
	var g: PackedByteArray = graph._grid(mc)
	while not _heap.is_empty():
		if not budget.spend(2):
			return
		var top: int = _pop()
		var b: int = top & 0xFFFF
		if _closed[b] != 0:
			continue
		_closed[b] = 1
		expanded += 1
		if b == _goal:
			_build_result()
			done = true
			return
		var bx: int = b % graph.bw
		var by: int = b / graph.bw
		for d: int in 8:
			var nx: int = bx + AiRouteGraph.NEIGHBORS_DX[d]
			var ny: int = by + AiRouteGraph.NEIGHBORS_DY[d]
			if nx < 0 or ny < 0 or nx >= graph.bw or ny >= graph.bh:
				continue
			var nb: int = ny * graph.bw + nx
			if g[nb] == 0 or _closed[nb] != 0 or (not _blocked.is_empty() and _blocked.has(nb)):
				continue
			var diag: bool = _is_diag(d)
			if diag and not graph._diag_ok(g, bx, by, d):
				continue
			var ng: int = _g[b] + graph.step_cost(nb, mc, diag, weight_q8)
			if ng < _g[nb]:
				_g[nb] = ng
				_from[nb] = b
				_push(ng + graph.heuristic(nb, _goal), nb)
	done = true  # open list exhausted: unreachable


static func _is_diag(d: int) -> bool:
	return (d & 1) == 1


func _build_result() -> void:
	var chain: PackedInt32Array = PackedInt32Array()
	var b: int = _goal
	while b >= 0 and b != _start:
		chain.append(b)
		b = _from[b]
	_result.resize(0)
	for i: int in range(chain.size() - 1, -1, -1):
		_result.append(graph.block_center_x(chain[i]))
		_result.append(graph.block_center_y(chain[i]))
	if _result.is_empty():
		_result.append(tx)
		_result.append(ty)
	else:
		_result[_result.size() - 2] = tx
		_result[_result.size() - 1] = ty


func result() -> Variant:
	return _result


# ----------------------------------------------------------------------------- binary min-heap of f<<16 | node
func _push(f: int, node: int) -> void:
	_heap.append((f << 16) | node)
	var i: int = _heap.size() - 1
	while i > 0:
		var p: int = (i - 1) / 2
		if _heap[p] <= _heap[i]:
			break
		var t: int = _heap[p]
		_heap[p] = _heap[i]
		_heap[i] = t
		i = p


func _pop() -> int:
	var top: int = _heap[0]
	var last: int = _heap[_heap.size() - 1]
	_heap.resize(_heap.size() - 1)
	if not _heap.is_empty():
		_heap[0] = last
		var i: int = 0
		var n: int = _heap.size()
		while true:
			var l: int = 2 * i + 1
			var r: int = l + 1
			var m: int = i
			if l < n and _heap[l] < _heap[m]:
				m = l
			if r < n and _heap[r] < _heap[m]:
				m = r
			if m == i:
				break
			var t: int = _heap[m]
			_heap[m] = _heap[i]
			_heap[i] = t
			i = m
	return top
