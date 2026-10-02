class_name ViewTerrainBake
extends RefCounted
## Threaded height / normal / cavity / chunk baking (render spec 5.5). Pure functions of a ViewTerrainSource: rows and
## chunks are independent, so they run on WorkerThreadPool group tasks; only mesh creation stays on the main thread.
##
## Height bake: Catmull-Rom on the 4x4 lattice corners CLAMPED to the middle pair (no cliff ringing) plus view-only relief
## noise, masked to 0 on roads / pavement (x0.08), water, beach, ramps and the outer rim, and faded out around start cells.
## Implemented separably (horizontal pass per corner row, vertical pass per vertex row), identical to the 2-D form.

const CHUNK_CELLS: int = 32
const RELIEF_AMP_M: float = 0.45
const RELIEF_FREQ: float = 0.09
const T_DEEP: int = 0
const T_SHALLOW: int = 1
const T_FORD: int = 2
const T_BEACH: int = 3
const T_ROAD: int = 9
const T_PAVEMENT: int = 10
const SF_RAMP: int = 16

var src: ViewTerrainSource = null
var subdiv: int = 2
var step_m: float = 1.5
var vw: int = 0
var vh: int = 0
var chunks_x: int = 0
var chunks_z: int = 0
var hv: PackedFloat32Array = PackedFloat32Array()  ## vw * vh vertex heights (m)
var chunk_arrays: Array = []  ## per chunk: surface arrays (position, normal, COLOR.r = cavity, index)
var chunk_size: Array[Vector2i] = []  ## quads (x, z) of each chunk
var stats: Dictionary = {}

var _threaded: bool = true
var _noise: FastNoiseLite = null
var _amp_cell: PackedByteArray = PackedByteArray()  ## relief amplitude per cell, 0..255
var _relief: PackedByteArray = PackedByteArray()  ## vw * vh relief noise, 0..255 = -1..1
var _hrows: Array = []  ## horizontally interpolated corner rows (PackedFloat32Array each)
var _index_cache: Dictionary = {}  ## (nx << 16 | nz) -> PackedInt32Array
var _start_xy: PackedVector2Array = PackedVector2Array()


static func chunk_counts(cells_w: int, cells_h: int) -> Vector2i:
	return Vector2i((cells_w + CHUNK_CELLS - 1) / CHUNK_CELLS, (cells_h + CHUNK_CELLS - 1) / CHUNK_CELLS)


## Runs the whole bake. `sub` = vertices per cell edge.
static func bake(source: ViewTerrainSource, sub: int, threaded: bool = true) -> ViewTerrainBake:
	var b: ViewTerrainBake = ViewTerrainBake.new()
	b.src = source
	b.subdiv = sub
	b._threaded = threaded
	b._run()
	return b


func _run() -> void:
	var t0: int = Time.get_ticks_usec()
	step_m = ViewConsts.CELL_M / float(subdiv)
	vw = src.width * subdiv + 1
	vh = src.height * subdiv + 1
	var cc: Vector2i = chunk_counts(src.width, src.height)
	chunks_x = cc.x
	chunks_z = cc.y
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = RELIEF_FREQ * step_m  # sampled per vertex index below, so scale to the vertex pitch
	_noise.fractal_octaves = 3
	_noise.seed = src.seed_value
	_build_amp_mask()
	# the relief field is generated natively in ONE call (FastNoiseLite.get_noise_2d from worker threads serialises on a lock
	# and did not scale); 8 bit quantisation of a 0.45 m amplitude is 3.5 mm
	var img: Image = _noise.get_image(vw, vh, false, false, false)
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	_relief = img.get_data()
	_start_xy.clear()
	for sc: int in src.start_cells:
		_start_xy.append(Vector2(float(sc % src.width) + 0.5, float(sc / src.width) + 0.5))
	# pass 1: horizontal interpolation of every corner row; pass 2: vertical interpolation + relief per vertex row
	_hrows.clear()
	_hrows.resize(src.height + 1)
	_tasks(_bake_corner_row, src.height + 1, "terrain corner rows")
	var t_corner: int = Time.get_ticks_usec()
	var rows: Array = []
	rows.resize(vh)
	_rows_out = rows
	_tasks(_bake_vertex_row, vh, "terrain heights")
	var t_vertex: int = Time.get_ticks_usec()
	hv = PackedFloat32Array()
	for j: int in vh:
		hv.append_array(rows[j] as PackedFloat32Array)
	_hrows.clear()
	_rows_out = []
	var t1: int = Time.get_ticks_usec()
	chunk_arrays.clear()
	chunk_arrays.resize(chunks_x * chunks_z)
	chunk_size.clear()
	chunk_size.resize(chunks_x * chunks_z)
	_prepare_indices()
	_tasks(_bake_chunk, chunks_x * chunks_z, "terrain chunks")
	var t2: int = Time.get_ticks_usec()
	stats = {"corner_ms": float(t_corner - t0) / 1000.0, "vertex_ms": float(t_vertex - t_corner) / 1000.0, "height_ms": float(t1 - t0) / 1000.0, "chunk_ms": float(t2 - t1) / 1000.0, "total_ms": float(t2 - t0) / 1000.0}


var _rows_out: Array = []


func _tasks(fn: Callable, count: int, desc: String) -> void:
	if _threaded and count > 1:
		# item 0 runs alone first: Godot 4.7.2 publishes the cached operator evaluator of a GDScript function unsynchronised on its first
		# execution, so a burst of threads starting the same function can crash (see ViewModelBuilder.WARM_MAX)
		fn.call(0)
		var rest: Callable = func(k: int) -> void: fn.call(k + 1)
		var gid: int = WorkerThreadPool.add_group_task(rest, count - 1, -1, true, desc)
		WorkerThreadPool.wait_for_group_task_completion(gid)
	else:
		for k: int in count:
			fn.call(k)


## Relief amplitude per cell: 1 in the open, 0.08 on road / pavement, 0 on water, beach, ford, ramps and the outer rim.
func _build_amp_mask() -> void:
	var w: int = src.width
	var h: int = src.height
	var terr: PackedByteArray = src.terrain
	var flg: PackedByteArray = src.flags
	_amp_cell.resize(w * h)
	_amp_cell.fill(255)
	for i: int in w * h:
		var t: int = terr[i]
		if t == T_ROAD or t == T_PAVEMENT:
			_amp_cell[i] = 20
		elif t <= T_BEACH or (flg[i] & SF_RAMP) != 0:  # deep, shallow, ford, beach: shorelines stay exact
			_amp_cell[i] = 0
	for x: int in w:  # the outermost ring keeps the exact rim height
		_amp_cell[x] = 0
		_amp_cell[(h - 1) * w + x] = 0
	for y: int in h:
		_amp_cell[y * w] = 0
		_amp_cell[y * w + w - 1] = 0


## Threaded task: horizontal Catmull-Rom of one lattice-corner row, evaluated at every vertex column.
func _bake_corner_row(cy: int) -> void:
	var cw: int = src.width + 1
	var base: int = cy * cw
	var cm: PackedFloat32Array = src.corner_m
	var row: PackedFloat32Array = PackedFloat32Array()
	row.resize(vw)
	for i: int in vw:
		var cx: int = i / subdiv
		var tx: float = float(i - cx * subdiv) / float(subdiv)
		if tx == 0.0:
			row[i] = cm[base + cx]
		else:
			# Catmull-Rom clamped to the middle pair, inlined: user function calls serialise worker threads in debug builds
			var p0: float = cm[base + maxi(cx - 1, 0)]
			var p1: float = cm[base + cx]
			var p2: float = cm[base + mini(cx + 1, cw - 1)]
			var p3: float = cm[base + mini(cx + 2, cw - 1)]
			var t2: float = tx * tx
			var v: float = 0.5 * (2.0 * p1 + (p2 - p0) * tx + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t2 * tx)
			row[i] = clampf(v, minf(p1, p2), maxf(p1, p2))
	_hrows[cy] = row


## Threaded task: one vertex row = vertical interpolation of the corner rows + masked relief noise.
func _bake_vertex_row(j: int) -> void:
	var cy: int = mini(j / subdiv, src.height)
	var ty: float = float(j - (j / subdiv) * subdiv) / float(subdiv)
	var ch: int = src.height + 1
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(vw)
	var r1: PackedFloat32Array = _hrows[cy]
	var vw_v: int = vw
	var z_m: float = float(j) * step_m
	var z_cell: float = z_m / ViewConsts.CELL_M
	# start cells whose fade disc reaches this row
	var near_starts: PackedVector2Array = PackedVector2Array()
	for sxy: Vector2 in _start_xy:
		if absf(sxy.y - z_cell) < 16.0:
			near_starts.append(sxy)
	# vertex row -> touched cell rows (on a cell edge both neighbours)
	var on_edge_y: bool = j % subdiv == 0
	var cyr_hi: int = mini(j / subdiv, src.height - 1)
	var cyr_lo: int = maxi(j / subdiv - 1, 0) if on_edge_y else cyr_hi
	if ty == 0.0:
		out = r1.duplicate()
	else:
		var r0: PackedFloat32Array = _hrows[maxi(cy - 1, 0)]
		var r2: PackedFloat32Array = _hrows[mini(cy + 1, ch - 1)]
		var r3: PackedFloat32Array = _hrows[mini(cy + 2, ch - 1)]
		var ty2: float = ty * ty
		var ty3: float = ty2 * ty
		for i: int in vw_v:
			var q0: float = r0[i]
			var q1: float = r1[i]
			var q2: float = r2[i]
			var q3: float = r3[i]
			var v: float = 0.5 * (2.0 * q1 + (q2 - q0) * ty + (2.0 * q0 - 5.0 * q1 + 4.0 * q2 - q3) * ty2 + (3.0 * q1 - q0 - 3.0 * q2 + q3) * ty3)
			out[i] = clampf(v, minf(q1, q2), maxf(q1, q2))
	var sw: int = src.width  # locals only in the loop: property reads on another object serialise worker threads
	var amp_cell: PackedByteArray = _amp_cell
	var relief: PackedByteArray = _relief
	var sub: int = subdiv
	var vw_l: int = vw
	var row_lo: int = cyr_lo * sw
	var row_hi: int = cyr_hi * sw
	for i: int in vw_l:
		var on_edge_x: bool = i % sub == 0
		var cxr_hi: int = mini(i / sub, sw - 1)
		var cxr_lo: int = maxi(i / sub - 1, 0) if on_edge_x else cxr_hi
		var amp: int = mini(mini(amp_cell[row_lo + cxr_lo], amp_cell[row_lo + cxr_hi]), mini(amp_cell[row_hi + cxr_lo], amp_cell[row_hi + cxr_hi]))
		if amp == 0:
			continue
		var a: float = RELIEF_AMP_M * float(amp) / 255.0
		if not near_starts.is_empty():
			var x_cell: float = float(i) * step_m / ViewConsts.CELL_M
			for sxy: Vector2 in near_starts:
				var d: float = Vector2(x_cell, z_cell).distance_to(sxy)
				if d < 16.0:
					a *= smoothstep(9.0, 16.0, d)
		out[i] += (float(relief[j * vw_l + i]) * (2.0 / 255.0) - 1.0) * a
	_rows_out[j] = out


func _prepare_indices() -> void:
	_index_cache.clear()
	var sizes: Dictionary = {}
	for cz: int in chunks_z:
		for cx: int in chunks_x:
			var nx: int = mini(CHUNK_CELLS, src.width - cx * CHUNK_CELLS) * subdiv
			var nz: int = mini(CHUNK_CELLS, src.height - cz * CHUNK_CELLS) * subdiv
			chunk_size[cz * chunks_x + cx] = Vector2i(nx, nz)
			sizes[(nx << 16) | nz] = Vector2i(nx, nz)
	for key: int in sizes.keys():
		var s: Vector2i = sizes[key]
		_index_cache[key] = _make_indices(s.x, s.y)


## Checkerboard diagonals ((i + j) & 1) so triangles do not all lean one way.
static func _make_indices(nx: int, nz: int) -> PackedInt32Array:
	var nv: int = nx + 1
	var idx: PackedInt32Array = PackedInt32Array()
	idx.resize(nx * nz * 6)
	var p: int = 0
	for j: int in nz:
		for i: int in nx:
			var a: int = j * nv + i
			var b: int = a + 1
			var c: int = a + nv
			var d: int = c + 1
			if ((i + j) & 1) == 0:
				idx[p] = a
				idx[p + 1] = b
				idx[p + 2] = c
				idx[p + 3] = b
				idx[p + 4] = d
				idx[p + 5] = c
			else:
				idx[p] = a
				idx[p + 1] = b
				idx[p + 2] = d
				idx[p + 3] = a
				idx[p + 4] = d
				idx[p + 5] = c
			p += 6
	return idx


## Threaded task: surface arrays of one chunk. Normals are central differences of the GLOBAL grid, so neighbouring
## chunks agree on their shared edge (no seams).
func _bake_chunk(index: int) -> void:
	var cx: int = index % chunks_x
	var cz: int = index / chunks_x
	var sz: Vector2i = chunk_size[index]
	var nvx: int = sz.x + 1
	var nvz: int = sz.y + 1
	var i0: int = cx * CHUNK_CELLS * subdiv
	var j0: int = cz * CHUNK_CELLS * subdiv
	var pos: PackedVector3Array = PackedVector3Array()
	var nrm: PackedVector3Array = PackedVector3Array()
	var col: PackedColorArray = PackedColorArray()
	pos.resize(nvx * nvz)
	nrm.resize(nvx * nvz)
	col.resize(nvx * nvz)
	var two_step: float = 2.0 * step_m
	var k: int = 0
	for j: int in nvz:
		var gj: int = j0 + j
		var jm: int = maxi(gj - 1, 0) * vw
		var jp: int = mini(gj + 1, vh - 1) * vw
		var jm4: int = maxi(gj - 4, 0) * vw
		var jp4: int = mini(gj + 4, vh - 1) * vw
		var jr: int = gj * vw
		for i: int in nvx:
			var gi: int = i0 + i
			var hh: float = hv[jr + gi]
			pos[k] = Vector3(float(gi) * step_m, hh, float(gj) * step_m)
			var hl: float = hv[jr + maxi(gi - 1, 0)]
			var hr: float = hv[jr + mini(gi + 1, vw - 1)]
			nrm[k] = Vector3(hl - hr, two_step, hv[jm + gi] - hv[jp + gi]).normalized()
			var lap: float = (hv[jr + maxi(gi - 4, 0)] + hv[jr + mini(gi + 4, vw - 1)] + hv[jm4 + gi] + hv[jp4 + gi]) * 0.25 - hh
			col[k] = Color(clampf(0.5 - lap * 0.05, 0.0, 1.0), 0.0, 0.0, 1.0)
			k += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = _index_cache[(sz.x << 16) | sz.y]
	chunk_arrays[index] = arrays
