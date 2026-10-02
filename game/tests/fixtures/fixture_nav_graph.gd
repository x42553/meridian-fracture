extends RefCounted
## Test double of MapNavGraph honouring the MapNav graph seam (map_nav.gd "GRAPH SEAM"): whole-map 4-connected
## components of cells with clearance >= size, relabelled entirely when any block is dirty. Not a real graph.

var clr: PackedByteArray = PackedByteArray()  # alias of nav.clr_array(np); the graph must not keep `nav` (cycle)
var n: int = 0
var w: int = 0
var np: int = 0
var size: int = 1
var cc_of: PackedInt32Array = PackedInt32Array()
var cc_size: PackedInt32Array = PackedInt32Array()
var dirty_units: int = 0
var relabels: int = 0


func _init(p_nav: MapNav, p_np: int, p_size: int) -> void:
	clr = p_nav.clr_array(p_np)
	n = p_nav.n
	w = p_nav.w
	np = p_np
	size = p_size


func build() -> void:
	cc_of.resize(n)
	cc_of.fill(-1)
	cc_size = PackedInt32Array()
	for s: int in n:
		if cc_of[s] != -1 or clr[s] < size:
			continue
		var id: int = cc_size.size()
		var cnt: int = 0
		var st: PackedInt32Array = PackedInt32Array([s])
		cc_of[s] = id
		while not st.is_empty():
			var c: int = st[st.size() - 1]
			st.resize(st.size() - 1)
			cnt += 1
			for d: int in [-1, 1, -w, w]:
				var m: int = c + d
				if m >= 0 and m < n and cc_of[m] == -1 and clr[m] >= size:
					cc_of[m] = id
					st.append(m)
		cc_size.append(cnt)


func mark_rect(_x0: int, _y0: int, _x1: int, _y1: int) -> void:
	dirty_units += 1


func pending() -> int:
	return dirty_units


func relabel_step() -> void:
	dirty_units -= 1
	relabels += 1
	if dirty_units == 0:
		build()


func node_of(i: int) -> int:
	return i if cc_of[i] >= 0 else -1


func region_of(i: int) -> int:
	return cc_of[i]


func region_size_of(i: int) -> int:
	return cc_size[cc_of[i]] if cc_of[i] >= 0 else 0


func estimate_cost(a: int, b: int) -> int:
	return 0 if cc_of[a] >= 0 and cc_of[a] == cc_of[b] else -1


func clone_for(p_nav: MapNav) -> Variant:
	var g: Variant = (load("res://tests/fixtures/fixture_nav_graph.gd") as GDScript).new(p_nav, np, size)
	g.set("cc_of", cc_of.duplicate())
	g.set("cc_size", cc_size.duplicate())
	g.set("dirty_units", dirty_units)
	return g
