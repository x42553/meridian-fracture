class_name SpatialHash
extends RefCounted
## Uniform bucket grid over entity ids (sim_core 3.2.5 / 5.8). Bucket = 4x4 cells (SHIFT = 12); every id lives in
## exactly one bucket (its centre). Queries are tag-filtered, allocation-free (the caller owns `out`) and return
## ids in ascending order, so results are deterministic regardless of bucket-internal order (swap-remove).
##
## A candidate passes iff `(tag & need) == need and (tag & avoid) == 0`. Circle tests use entity centres:
## `dx*dx + dy*dy <= r*r`. Rect queries are inclusive on all four edges.

const SHIFT: int = 12  # == SimConfig.SPATIAL_SHIFT (core files do not reference each other; a test asserts it)

## Buckets per row / column.
var bw: int = 0
var bh: int = 0

var _max_x: int = 0
var _max_y: int = 0
var _buckets: Array[PackedInt32Array] = []
var _px: PackedInt32Array = PackedInt32Array()
var _py: PackedInt32Array = PackedInt32Array()
var _tag: PackedInt32Array = PackedInt32Array()
## Bucket index per id, -1 when the id is not in the hash.
var _bucket: PackedInt32Array = PackedInt32Array()


func _init(map_w_cells: int, map_h_cells: int) -> void:
	_max_x = (map_w_cells << 10) - 1
	_max_y = (map_h_cells << 10) - 1
	bw = (_max_x >> SHIFT) + 1
	bh = (_max_y >> SHIFT) + 1
	_buckets.resize(bw * bh)
	for i: int in bw * bh:
		_buckets[i] = PackedInt32Array()
	_grow(256)


## Adds `id` (>= 1) at (x, y), clamped into the map. Re-inserting an id first removes the old entry.
func insert(id: int, x: int, y: int, tag: int) -> void:
	if id >= _bucket.size():
		_grow(maxi(id + 1, _bucket.size() * 2))
	elif _bucket[id] >= 0:
		remove(id)
	var cx: int = clampi(x, 0, _max_x)
	var cy: int = clampi(y, 0, _max_y)
	_px[id] = cx
	_py[id] = cy
	_tag[id] = tag
	var b: int = (cy >> SHIFT) * bw + (cx >> SHIFT)
	_bucket[id] = b
	var arr: PackedInt32Array = _buckets[b]
	arr.append(id)


## Removes `id`; a no-op when it is not present.
func remove(id: int) -> void:
	if id < 0 or id >= _bucket.size():
		return
	var b: int = _bucket[id]
	if b < 0:
		return
	_unlink(id, b)
	_bucket[id] = -1


func contains(id: int) -> bool:
	return id >= 0 and id < _bucket.size() and _bucket[id] >= 0


## Updates the coordinates (clamped); re-buckets only when the bucket changes.
func move(id: int, x: int, y: int) -> void:
	if id < 0 or id >= _bucket.size():
		return
	var ob: int = _bucket[id]
	if ob < 0:
		return
	var cx: int = clampi(x, 0, _max_x)
	var cy: int = clampi(y, 0, _max_y)
	_px[id] = cx
	_py[id] = cy
	var nb: int = (cy >> SHIFT) * bw + (cx >> SHIFT)
	if nb != ob:
		_unlink(id, ob)
		var arr: PackedInt32Array = _buckets[nb]
		arr.append(id)
		_bucket[id] = nb


func set_tag(id: int, tag: int) -> void:
	if contains(id):
		_tag[id] = tag


func tag_of(id: int) -> int:
	return _tag[id] if contains(id) else 0


func x_of(id: int) -> int:
	return _px[id] if contains(id) else 0


func y_of(id: int) -> int:
	return _py[id] if contains(id) else 0


## Fills `out` (cleared first) with the ids whose centre lies within r of (x, y), ascending. Returns the count.
func query_circle(x: int, y: int, r: int, out: PackedInt32Array, need: int = 0, avoid: int = 0) -> int:
	out.resize(0)
	if r < 0:
		return 0
	var r2: int = r * r
	var x0: int = x - r
	var y0: int = y - r
	var bx0: int = 0 if x0 < 0 else x0 >> SHIFT  # never shift a negative value
	var by0: int = 0 if y0 < 0 else y0 >> SHIFT
	var bx1: int = (x + r) >> SHIFT
	var by1: int = (y + r) >> SHIFT
	if bx1 >= bw:
		bx1 = bw - 1
	if by1 >= bh:
		by1 = bh - 1
	var px: PackedInt32Array = _px
	var py: PackedInt32Array = _py
	var tags: PackedInt32Array = _tag
	for by: int in range(by0, by1 + 1):
		var row: int = by * bw
		for bx: int in range(bx0, bx1 + 1):
			var ids: PackedInt32Array = _buckets[row + bx]
			for k: int in ids.size():
				var id: int = ids[k]
				var t: int = tags[id]
				if (t & need) != need or (t & avoid) != 0:
					continue
				var dx: int = px[id] - x
				var dy: int = py[id] - y
				if dx * dx + dy * dy <= r2:
					out.append(id)
	out.sort()
	return out.size()


## Fills `out` with the ids whose centre lies in [x0, x1] x [y0, y1] (inclusive), ascending. Returns the count.
func query_rect(x0: int, y0: int, x1: int, y1: int, out: PackedInt32Array, need: int = 0, avoid: int = 0) -> int:
	out.resize(0)
	if x1 < x0 or y1 < y0 or x1 < 0 or y1 < 0:
		return 0
	var bx0: int = 0 if x0 < 0 else x0 >> SHIFT
	var by0: int = 0 if y0 < 0 else y0 >> SHIFT
	var bx1: int = x1 >> SHIFT
	var by1: int = y1 >> SHIFT
	if bx1 >= bw:
		bx1 = bw - 1
	if by1 >= bh:
		by1 = bh - 1
	var px: PackedInt32Array = _px
	var py: PackedInt32Array = _py
	var tags: PackedInt32Array = _tag
	for by: int in range(by0, by1 + 1):
		var row: int = by * bw
		for bx: int in range(bx0, bx1 + 1):
			var ids: PackedInt32Array = _buckets[row + bx]
			for k: int in ids.size():
				var id: int = ids[k]
				var t: int = tags[id]
				if (t & need) != need or (t & avoid) != 0:
					continue
				var ix: int = px[id]
				var iy: int = py[id]
				if ix >= x0 and ix <= x1 and iy >= y0 and iy <= y1:
					out.append(id)
	out.sort()
	return out.size()


## Fills `out` with all ids stored in the bucket containing cell (cx, cy) (clamped), ascending. Returns the count.
func cell_bucket(cx: int, cy: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var bx: int = clampi(cx >> (SHIFT - 10), 0, bw - 1)
	var by: int = clampi(cy >> (SHIFT - 10), 0, bh - 1)
	out.append_array(_buckets[by * bw + bx])
	out.sort()
	return out.size()


func _unlink(id: int, b: int) -> void:
	var arr: PackedInt32Array = _buckets[b]
	var n: int = arr.size()
	for k: int in n:
		if arr[k] == id:
			arr[k] = arr[n - 1]
			arr.resize(n - 1)
			return


func _grow(new_size: int) -> void:
	var old: int = _bucket.size()
	_px.resize(new_size)
	_py.resize(new_size)
	_tag.resize(new_size)
	_bucket.resize(new_size)
	for i: int in range(old, new_size):
		_bucket[i] = -1
