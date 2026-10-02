class_name ViewTerrainLayers
extends RefCounted
## Control textures of the terrain shader (render spec 5.5): the two splat maps, terrain flags, moisture, road coverage
## and run-length marking rasters, the water-depth raster (vertex resolution) and the shore-distance field. Everything is
## a pure function of the ViewTerrainSource (+ the baked vertex heights for the depth raster).
##
## Splat table (ctrl_a = grass, dirt, rock, sand; ctrl_b = snow, urban, deposit, rubble):
##   0 deep, 1 shallow: sand 1 | 2 ford: sand .6 dirt .4 | 3 beach: sand 1 | 4 grass: grass 1 (arctic snow 1)
##   5 dirt: dirt 1 (arctic dirt .5 snow .5) | 6 sand: sand 1 (arctic snow .6 sand .4) | 7 rock: rock 1
##   8 forest: grass .7 dirt .3 (arctic snow .6 dirt .4) | 9 road: urban .2 | 10 pavement: urban 1 | 11 rubble: rubble .8 dirt .2
##   12 urban block: urban 1 | 13 cliff: rock 1 (SF_RAMP: rock x0.15, the rest dirt) | 14 mountain: rock 1 (arctic snow cap
##   above 60 % of the local relief) | 15 marsh: grass .5 dirt .5

const T_ROAD: int = 9
const SF_RAMP: int = 16
const BIOME_ARCTIC: int = 2
const FAMILY_URBAN: int = 1
const STREET_MAX_WIDTH: int = 8  ## a street's short run is at most 8 cells
const STREET_MIN_LENGTH: int = 12  ## identical (start, width) over at least this many consecutive cells

## Weights per terrain id: 8 values (grass, dirt, rock, sand, snow, urban, deposit, rubble) in 0..1.
const SPLAT: Array = [
	[0, 0, 0, 1, 0, 0, 0, 0], [0, 0, 0, 1, 0, 0, 0, 0], [0, 0.4, 0, 0.6, 0, 0, 0, 0], [0, 0, 0, 1, 0, 0, 0, 0],
	[1, 0, 0, 0, 0, 0, 0, 0], [0, 1, 0, 0, 0, 0, 0, 0], [0, 0, 0, 1, 0, 0, 0, 0], [0, 0, 1, 0, 0, 0, 0, 0],
	[0.7, 0.3, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0.2, 0, 0], [0, 0, 0, 0, 0, 1, 0, 0], [0, 0.2, 0, 0, 0, 0, 0, 0.8],
	[0, 0, 0, 0, 0, 1, 0, 0], [0, 0, 1, 0, 0, 0, 0, 0], [0, 0, 1, 0, 0, 0, 0, 0], [0.5, 0.5, 0, 0, 0, 0, 0, 0],
]
const SPLAT_ARCTIC: Dictionary = {
	4: [0, 0, 0, 0, 1, 0, 0, 0], 5: [0, 0.5, 0, 0, 0.5, 0, 0, 0], 6: [0, 0, 0, 0.4, 0.6, 0, 0, 0], 8: [0, 0.4, 0, 0, 0.6, 0, 0, 0],
}

var ctrl_a: ImageTexture = null  ## RGBA8 w x h, bilinear
var ctrl_b: ImageTexture = null
var ctrl_flags: ImageTexture = null  ## R8 w x h, NEAREST (MapData.SF_*)
var moisture_tex: ImageTexture = null  ## R8 w x h, bilinear
var road_cov: ImageTexture = null  ## R8 w x h: 255 on ROAD cells, one 3x3 blur, bilinear
var road_info: ImageTexture = null  ## RGBA8 w x h NEAREST: street cells (urban maps only), see street_info()
var water_depth: ImageTexture = null  ## R8 vw x vh: (sea - h + 2) / 8
var shore_dist_tex: ImageTexture = null  ## R8 w x h: 1/3-cell units (shader multiplies by 85 to get cells)

# CPU copies for tests and the deposit repaint
var ctrl_a_bytes: PackedByteArray = PackedByteArray()
var ctrl_b_bytes: PackedByteArray = PackedByteArray()
var road_cov_bytes: PackedByteArray = PackedByteArray()
var road_info_bytes: PackedByteArray = PackedByteArray()
var water_depth_bytes: PackedByteArray = PackedByteArray()
var width: int = 0
var height: int = 0
var build_ms: float = 0.0

var _src: ViewTerrainSource = null
var _threaded: bool = true
# row-task inputs (locals of the source copied once: property reads on another object serialise worker threads)
var _terr: PackedByteArray = PackedByteArray()
var _flg: PackedByteArray = PackedByteArray()
var _cm: PackedFloat32Array = PackedFloat32Array()
var _tab: PackedByteArray = PackedByteArray()  ## 16 terrain ids x 8 weights (0..255)
var _dep_w: PackedFloat32Array = PackedFloat32Array()
var _is_arctic: bool = false
var _relief_lo: float = 0.0
var _relief_span: float = 1.0
var _a_rows: Array = []
var _b_rows: Array = []
var _hv: PackedFloat32Array = PackedFloat32Array()
var _vw: int = 0
var _depth_rows: Array = []
var _sea_v: float = 0.0


static func build(src: ViewTerrainSource, hv: PackedFloat32Array, vw: int, vh: int, threaded: bool = true) -> ViewTerrainLayers:
	var t0: int = Time.get_ticks_usec()
	var l: ViewTerrainLayers = ViewTerrainLayers.new()
	l._src = src
	l._threaded = threaded
	l.width = src.width
	l.height = src.height
	l._build_splat()
	l._build_roads()
	l._build_water_depth(hv, vw, vh)
	l.ctrl_flags = _tex_r8(src.flags, src.width, src.height)
	l.moisture_tex = _tex_r8(src.moisture, src.width, src.height)
	l.shore_dist_tex = _tex_r8(src.shore_dist, src.width, src.height)
	l.build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return l


static func _tex_r8(bytes: PackedByteArray, w: int, h: int) -> ImageTexture:
	var b: PackedByteArray = bytes
	if b.size() != w * h:
		b = PackedByteArray()
		b.resize(w * h)
	return ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_R8, b))


func _build_splat() -> void:
	var w: int = width
	var n: int = w * height
	_terr = _src.terrain
	_flg = _src.flags
	_cm = _src.corner_m
	_is_arctic = _src.biome == BIOME_ARCTIC
	_tab = _splat_table(_is_arctic)
	# local relief for the arctic snow cap: cell height normalised to the map's land range
	var lo: float = 1.0e9
	var hi: float = -1.0e9
	if _is_arctic:
		for i: int in n:
			var hcell: float = _cell_height(i)
			lo = minf(lo, hcell)
			hi = maxf(hi, hcell)
	_relief_lo = lo
	_relief_span = maxf(hi - lo, 0.001)
	_dep_w = _initial_deposit_weights()
	_a_rows.clear()
	_a_rows.resize(height)
	_b_rows.clear()
	_b_rows.resize(height)
	_run_rows(_splat_row, height, "terrain splat")
	ctrl_a_bytes = PackedByteArray()
	ctrl_b_bytes = PackedByteArray()
	for y: int in height:
		ctrl_a_bytes.append_array(_a_rows[y] as PackedByteArray)
		ctrl_b_bytes.append_array(_b_rows[y] as PackedByteArray)
	_a_rows.clear()
	_b_rows.clear()
	ctrl_a = ImageTexture.create_from_image(Image.create_from_data(w, height, false, Image.FORMAT_RGBA8, ctrl_a_bytes))
	ctrl_b = ImageTexture.create_from_image(Image.create_from_data(w, height, false, Image.FORMAT_RGBA8, ctrl_b_bytes))


func _run_rows(fn: Callable, count: int, desc: String) -> void:
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


## 16 x 8 byte weights (grass, dirt, rock, sand, snow, urban, deposit, rubble) per terrain id.
static func _splat_table(arctic: bool) -> PackedByteArray:
	var tab: PackedByteArray = PackedByteArray()
	tab.resize(SPLAT.size() * 8)
	for t: int in SPLAT.size():
		var wts: Array = SPLAT[t]
		if arctic and SPLAT_ARCTIC.has(t):
			wts = SPLAT_ARCTIC[t]
		for k: int in 8:
			tab[t * 8 + k] = int(float(wts[k]) * 255.0 + 0.5)
	return tab


## Threaded task: one row of both control maps.
func _splat_row(y: int) -> void:
	var w: int = width
	var ra: PackedByteArray = PackedByteArray()
	var rb: PackedByteArray = PackedByteArray()
	ra.resize(w * 4)
	rb.resize(w * 4)
	var terr: PackedByteArray = _terr
	var flg: PackedByteArray = _flg
	var tab: PackedByteArray = _tab
	var dep: PackedFloat32Array = _dep_w
	var has_dep: bool = dep.size() > 0
	var nt: int = SPLAT.size()
	for x: int in w:
		var i: int = y * w + x
		var t: int = mini(terr[i], nt - 1)
		var base: int = t * 8
		var g: int = tab[base]
		var d: int = tab[base + 1]
		var r: int = tab[base + 2]
		var s: int = tab[base + 3]
		var sn: int = tab[base + 4]
		if t == 14 and _is_arctic:
			var cap: float = smoothstep(0.55, 0.70, (_cell_height_local(x, y) - _relief_lo) / _relief_span)
			sn = int(cap * 255.0 + 0.5)
			r = 255 - sn
		if r > 0 and (flg[i] & SF_RAMP) != 0:
			d = mini(d + int(float(r) * 0.85), 255)
			r = int(float(r) * 0.15 + 0.5)
		var o: int = x * 4
		ra[o] = g
		ra[o + 1] = d
		ra[o + 2] = r
		ra[o + 3] = s
		rb[o] = sn
		rb[o + 1] = tab[base + 5]
		rb[o + 2] = int(dep[i] * 255.0 + 0.5) if has_dep else 0
		rb[o + 3] = tab[base + 7]
	_a_rows[y] = ra
	_b_rows[y] = rb


func _cell_height_local(x: int, y: int) -> float:
	var st: int = width + 1
	return (_cm[y * st + x] + _cm[y * st + x + 1] + _cm[(y + 1) * st + x] + _cm[(y + 1) * st + x + 1]) * 0.25


func _cell_height(i: int) -> float:
	return _cell_height_local(i % width, i / width)


## Scatter form of _deposit_weight for the initial build: only the deposit cells are visited. Empty when there is none.
func _initial_deposit_weights() -> PackedFloat32Array:
	var cells: PackedInt32Array = PackedInt32Array()
	if _src.deposit_cells(cells) == 0:
		return PackedFloat32Array()
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(width * height)
	for c: int in cells:
		var f: float = _src.deposit_fraction(c)
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var x: int = c % width + dx
				var y: int = c / width + dy
				if x >= 0 and y >= 0 and x < width and y < height:
					var i: int = y * width + x
					out[i] = maxf(out[i], f if (dx == 0 and dy == 0) else f * 0.7)
	return out


## Deposit weight of a cell: its own fraction, or 0.7 x the best neighbour fraction, so a sparse field (the generator
## keeps K of the 49 window cells) reads as one patch of scrap soil rather than isolated speckles.
func _deposit_weight(i: int) -> float:
	var own: float = _src.deposit_fraction(i)
	var cx: int = i % width
	var cy: int = i / width
	var best: float = 0.0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var x: int = cx + dx
			var y: int = cy + dy
			if x >= 0 and y >= 0 and x < width and y < height and (dx != 0 or dy != 0):
				best = maxf(best, _src.deposit_fraction(y * width + x))
	return maxf(own, best * 0.7)


## Re-paints the deposit weight (ctrl_b.b) around the given cells from the live deposit state, so a depleted field fades
## from the ground. Uploads the texture once.
func repaint_deposits(cells: PackedInt32Array, n: int) -> void:
	for k: int in n:
		var c: int = cells[k]
		if c < 0 or c >= width * height:
			continue
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var x: int = c % width + dx
				var y: int = c / width + dy
				if x >= 0 and y >= 0 and x < width and y < height:
					var i: int = y * width + x
					ctrl_b_bytes[i * 4 + 2] = int(_deposit_weight(i) * 255.0 + 0.5)
	if n > 0:
		ctrl_b.update(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, ctrl_b_bytes))


# ---- roads --------------------------------------------------------------------------------------------------

func _build_roads() -> void:
	var w: int = width
	var h: int = height
	var n: int = w * h
	var terr: PackedByteArray = _src.terrain
	var road: PackedByteArray = PackedByteArray()
	road.resize(n)
	var road_cells: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		if terr[i] == T_ROAD:
			road[i] = 255
			road_cells.append(i)
	road_cov_bytes = _blur3_sparse(road_cells, w, h)
	road_info_bytes = PackedByteArray()
	road_info_bytes.resize(n * 4)
	road_info_bytes.fill(0)
	if _src.family == FAMILY_URBAN and not road_cells.is_empty():
		_classify_streets(road)
	road_cov = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_R8, road_cov_bytes))
	road_info = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, road_info_bytes))


## 3x3 box blur of a 255-valued cell set (edges clamp): only the neighbourhood of the given cells is visited.
static func _blur3_sparse(cells: PackedInt32Array, w: int, h: int) -> PackedByteArray:
	var acc: PackedInt32Array = PackedInt32Array()
	acc.resize(w * h)
	for c: int in cells:
		var cx: int = c % w
		var cy: int = c / w
		for dy: int in range(-1, 2):
			var y: int = clampi(cy + dy, 0, h - 1)
			for dx: int in range(-1, 2):
				acc[y * w + clampi(cx + dx, 0, w - 1)] += 255
	# edge clamping counts border cells' replicated neighbours: matches a clamped 3x3 kernel exactly
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	for c: int in cells:
		var cx2: int = c % w
		var cy2: int = c / w
		for dy2: int in range(-1, 2):
			var y2: int = clampi(cy2 + dy2, 0, h - 1)
			for dx2: int in range(-1, 2):
				var i: int = y2 * w + clampi(cx2 + dx2, 0, w - 1)
				out[i] = mini((acc[i] + 4) / 9, 255)
	return out


## Street cells (render 5.5): a ROAD cell is a street cell iff min(rh, rv) <= 8, max >= 2 * min, and the pair
## (start of the short run, its length n) is identical over at least 12 consecutive cells along the street axis.
## road_info = (R 255, G 128 horizontal street / 255 vertical, B k = index inside the short run, A n).
func _classify_streets(road: PackedByteArray) -> void:
	var w: int = width
	var h: int = height
	var n: int = w * h
	var h_len: PackedInt32Array = PackedInt32Array()
	var h_start: PackedInt32Array = PackedInt32Array()
	var v_len: PackedInt32Array = PackedInt32Array()
	var v_start: PackedInt32Array = PackedInt32Array()
	h_len.resize(n)
	h_start.resize(n)
	v_len.resize(n)
	v_start.resize(n)
	for y: int in h:
		var x: int = 0
		while x < w:
			if road[y * w + x] == 0:
				x += 1
				continue
			var x1: int = x
			while x1 < w and road[y * w + x1] != 0:
				x1 += 1
			for k: int in range(x, x1):
				h_len[y * w + k] = x1 - x
				h_start[y * w + k] = x
			x = x1
	for x2: int in w:
		var y2: int = 0
		while y2 < h:
			if road[y2 * w + x2] == 0:
				y2 += 1
				continue
			var y1: int = y2
			while y1 < h and road[y1 * w + x2] != 0:
				y1 += 1
			for k2: int in range(y2, y1):
				v_len[k2 * w + x2] = y1 - y2
				v_start[k2 * w + x2] = y2
			y2 = y1
	# horizontal streets: the short run is vertical (rv < rh), grouped along x by identical (v_start, v_len)
	for y3: int in h:
		var x3: int = 0
		while x3 < w:
			var i: int = y3 * w + x3
			if not _is_street_candidate(road[i], v_len[i], h_len[i]):
				x3 += 1
				continue
			var x4: int = x3 + 1
			while x4 < w:
				var j: int = y3 * w + x4
				if not _is_street_candidate(road[j], v_len[j], h_len[j]) or v_start[j] != v_start[i] or v_len[j] != v_len[i]:
					break
				x4 += 1
			if x4 - x3 >= STREET_MIN_LENGTH:
				for xk: int in range(x3, x4):
					var c: int = y3 * w + xk
					_put_street(c, 128, y3 - v_start[c], v_len[c])
			x3 = x4
	# vertical streets: the short run is horizontal (rh < rv), grouped along y by identical (h_start, h_len)
	for x5: int in w:
		var y5: int = 0
		while y5 < h:
			var i2: int = y5 * w + x5
			if not _is_street_candidate(road[i2], h_len[i2], v_len[i2]):
				y5 += 1
				continue
			var y6: int = y5 + 1
			while y6 < h:
				var j2: int = y6 * w + x5
				if not _is_street_candidate(road[j2], h_len[j2], v_len[j2]) or h_start[j2] != h_start[i2] or h_len[j2] != h_len[i2]:
					break
				y6 += 1
			if y6 - y5 >= STREET_MIN_LENGTH:
				for yk: int in range(y5, y6):
					var c2: int = yk * w + x5
					_put_street(c2, 255, x5 - h_start[c2], h_len[c2])
			y5 = y6


## short_run < long_run, short <= 8 and long >= 2 * short.
static func _is_street_candidate(road_cell: int, short_run: int, long_run: int) -> bool:
	return road_cell != 0 and short_run < long_run and short_run <= STREET_MAX_WIDTH and long_run >= 2 * short_run


func _put_street(cell: int, g: int, k: int, run_n: int) -> void:
	var o: int = cell * 4
	road_info_bytes[o] = 255
	road_info_bytes[o + 1] = g
	road_info_bytes[o + 2] = k
	road_info_bytes[o + 3] = run_n


## (R, G, B, A) of the road_info texel of a cell (tests).
func street_info(cx: int, cy: int) -> Vector4i:
	var o: int = (cy * width + cx) * 4
	return Vector4i(road_info_bytes[o], road_info_bytes[o + 1], road_info_bytes[o + 2], road_info_bytes[o + 3])


# ---- water depth --------------------------------------------------------------------------------------------

func _build_water_depth(hv: PackedFloat32Array, vw: int, vh: int) -> void:
	if not _src.has_water():
		water_depth_bytes = PackedByteArray()
		water_depth_bytes.resize(vw * vh)
	else:
		_hv = hv
		_vw = vw
		_sea_v = _src.sea_level_m
		_depth_rows.clear()
		_depth_rows.resize(vh)
		_run_rows(_depth_row, vh, "terrain depth")
		water_depth_bytes = PackedByteArray()
		for j: int in vh:
			water_depth_bytes.append_array(_depth_rows[j] as PackedByteArray)
		_depth_rows.clear()
		_hv = PackedFloat32Array()
	water_depth = ImageTexture.create_from_image(Image.create_from_data(vw, vh, false, Image.FORMAT_R8, water_depth_bytes))


## Threaded task: one row of the water-depth raster, byte = (sea - h + 2) / 8 * 255.
func _depth_row(j: int) -> void:
	var vw: int = _vw
	var hv: PackedFloat32Array = _hv
	var row: PackedByteArray = PackedByteArray()
	row.resize(vw)
	var k: float = 255.0 / 8.0
	var off: float = (_sea_v + 2.0) * k + 0.5
	var base: int = j * vw
	for i: int in vw:
		row[i] = clampi(int(off - hv[base + i] * k), 0, 255)
	_depth_rows[j] = row
