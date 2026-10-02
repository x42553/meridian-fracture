class_name MapGenLayout
extends RefCounted
## Generator phase B (terrain_movement 5.12.5 / 5.12.8): starts, bays, gates and trunk roads, resource fields,
## neutral lots, beaches, scenery boulders, flags and the lists (spawns / fields / neutrals / roads) of a MapData
## that already holds the phase-A layers. Cheap; retried by MapGenerator at level 0, 1, 2 (wider gates, bigger discs).
##
## Every primitive is defined by control points in doubled coordinates, painted once per image with the transformed
## points (MapGenSymmetry), so exact groups are bit mirror images. `keep` marks painted cells (excluded from beaches
## and boulders); `protect` marks bay water (never overwritten by fields or lots). Integer only, reentrant.

const ST_LAYOUT: int = 4
const ST_FIELDS: int = 5
const ST_NEUTRALS: int = 6
const ST_FINALIZE: int = 7
const ST_VALIDATE: int = 8
const ST_DONE: int = 9

const M_CLEAR: int = 0  ## forest / cliff / rock / urban / rubble / marsh -> DIRT, deep + shallow -> FORD
const M_FORCE: int = 1  ## terrain := t
const M_ROAD: int = 2  ## water -> FORD, else terrain := t
const M_PATH: int = 3  ## like M_ROAD with DIRT, but road / pavement / deposit cells stay

const ANG_OFF: PackedInt32Array = [0, 300, -300, 600, -600, 900, -900]
const DIST_SC: PackedInt32Array = [100, 85, 70, 120]
const FIELD_R: int = 7
const NEUTRAL_TRIES: int = 64
const CORR_HW2: int = 5  ## neutral corridor width (cells == doubled half width)
const NEUTRAL_JSON: String = "res://data/balance/neutral_structures.json"
const KINDS: int = 5

static var _dims: Dictionary = {}  ## neutral id -> (w << 8) | h ; immutable cache of neutral_structures.json footprints
static var _berth: Dictionary = {}  ## neutral id -> [x, y, w, h] authored berth rectangle (harbor terminal)

var map: MapData = null
var tt: MapTerrain = null
var tables: MapGenTables = null
var params: MapGenParams = null
var sym: MapGenSymmetry = null
var seed_a: int = 0
var level: int = 0
var template: bool = false
var size: int = 0
var n: int = 0
var ok: bool = true
var failure: String = ""
var gate_w: int = 5
var start_r: int = 13
var keep: PackedByteArray = PackedByteArray()
var protect: PackedByteArray = PackedByteArray()
var order: PackedInt32Array = PackedInt32Array()  ## order[start index] = image index
var pos_of_image: PackedInt32Array = PackedInt32Array()
var p0x: int = 0
var p0y: int = 0
var nn: PackedInt32Array = PackedInt32Array()  ## image indices of the (up to 2) nearest other starts of the canonical start
var nnx: PackedInt32Array = PackedInt32Array()
var nny: PackedInt32Array = PackedInt32Array()
var roads: Array = []
var spawns: PackedInt32Array = PackedInt32Array()
var fields: PackedInt32Array = PackedInt32Array()
var neutrals: PackedInt32Array = PackedInt32Array()

var _progress: Callable = Callable()
var _cells: PackedInt32Array = PackedInt32Array()
var _scx: PackedInt32Array = PackedInt32Array()  # start cells (all images)
var _scy: PackedInt32Array = PackedInt32Array()
var _fcx: PackedInt32Array = PackedInt32Array()  # registered field centres
var _fcy: PackedInt32Array = PackedInt32Array()
var _fkind: PackedInt32Array = PackedInt32Array()
var _pcx: PackedInt32Array = PackedInt32Array()  # bay pocket centres
var _pcy: PackedInt32Array = PackedInt32Array()
var _lcx: PackedInt32Array = PackedInt32Array()  # lot centres
var _lcy: PackedInt32Array = PackedInt32Array()
var _anc_x: PackedInt32Array = PackedInt32Array()  # canonical anchor of the placed field [kind * 2 + sub]
var _anc_y: PackedInt32Array = PackedInt32Array()
var _anc_ok: PackedByteArray = PackedByteArray()
var _ax: int = 0  # scratch: current canonical anchor / lot centre
var _ay: int = 0
var _next_id: int = 1
## Telemetry: rejected lot candidates by reason [edge, terrain, start distance, field distance, lot distance, no deep water].
var lot_reject: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])


## Runs phase B on `p_map` (phase-A layers, not finalized). `ok` false = fail this level (see `failure`).
static func run(p_map: MapData, p_tt: MapTerrain, p_tables: MapGenTables, p_params: MapGenParams, p_seed: int,
		p_level: int, p_template: bool, p_progress: Callable = Callable()) -> MapGenLayout:
	var l: MapGenLayout = MapGenLayout.new()
	l.map = p_map
	l.tt = p_tt
	l.tables = p_tables
	l.params = p_params
	l.seed_a = p_seed
	l.level = p_level
	l.template = p_template
	l._progress = p_progress
	l._run()
	return l


## Footprints of the neutral structures: id -> (w << 8) | h, read from neutral_structures.json (data's file); the
## defaults equal the authored values. Loaded once; call from the main thread before starting workers.
static func neutral_dims() -> Dictionary:
	if not _dims.is_empty():
		return _dims
	var d: Dictionary = {"neutral.civilian_garrison": (3 << 8) | 3, "neutral.substation": (2 << 8) | 2,
		"neutral.salvage_depot": (3 << 8) | 3, "neutral.field_hospital": (2 << 8) | 3,
		"neutral.observation_tower": (1 << 8) | 1, "neutral.harbor_terminal": (3 << 8) | 3}
	var b: Dictionary = {"neutral.harbor_terminal": PackedInt32Array([0, 3, 3, 2])}
	if FileAccess.file_exists(NEUTRAL_JSON):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(NEUTRAL_JSON))
		if j is Dictionary and (j as Dictionary).get("neutrals") is Dictionary:
			var nd: Dictionary = (j as Dictionary)["neutrals"] as Dictionary
			for id: String in MapData.NEUTRAL_IDS_DEFAULT:
				var e: Variant = nd.get(id)
				if e is Dictionary and (e as Dictionary).get("footprint") is Dictionary:
					var fpd: Dictionary = (e as Dictionary)["footprint"] as Dictionary
					var fw: int = MapGenParams._int(fpd.get("w", 0), 0)
					var fh: int = MapGenParams._int(fpd.get("h", 0), 0)
					if fw > 0 and fh > 0 and fw < 16 and fh < 16:
						d[id] = (fw << 8) | fh
				if e is Dictionary and (e as Dictionary).get("berth") is Array and ((e as Dictionary)["berth"] as Array).size() == 4:
					var ba: Array = (e as Dictionary)["berth"] as Array
					b[id] = PackedInt32Array([MapGenParams._int(ba[0], 0), MapGenParams._int(ba[1], 0),
						MapGenParams._int(ba[2], 0), MapGenParams._int(ba[3], 0)])
	_berth = b
	_dims = d
	return _dims


## Authored berth rectangle [x, y, w, h] (footprint-local, orientation 0) of the harbor terminal.
static func harbor_berth() -> PackedInt32Array:
	neutral_dims()
	return _berth["neutral.harbor_terminal"] as PackedInt32Array


# ---- helpers -------------------------------------------------------------------------------------------------------

func _report(stage: int, num: int, den: int) -> void:
	if _progress.is_valid():
		var r: Array = tables.progress["layout"] as Array
		_progress.call(stage, (r[0] as int) + ((r[1] as int) - (r[0] as int)) * num / den)


func _fail(why: String) -> void:
	if ok:
		ok = false
		failure = why


func _is_water(t: int) -> bool:
	return t == MapTerrain.T_DEEP or t == MapTerrain.T_SHALLOW


## Cell x / y of the image-k point (doubled coordinates); may be outside the map.
func _cx(k: int, x2: int, y2: int) -> int:
	return sym.cell_of2(sym.img_x(k, x2, y2))


func _cy(k: int, x2: int, y2: int) -> int:
	return sym.cell_of2(sym.img_y(k, x2, y2))


## Image-frame offset -> canonical offset (inverse of the linear part of image k).
func _inv_x(k: int, dx: int, dy: int) -> int:
	match sym.group:
		MapGenSymmetry.G_D1X:
			return -dx if (k & 1) != 0 else dx
		MapGenSymmetry.G_D2, MapGenSymmetry.G_D4:
			var ux: int = dy if (sym.group == MapGenSymmetry.G_D4 and (k & 4) != 0) else dx
			return -ux if (k & 1) != 0 else ux
	var a: int = k * Fp.TURN / sym.images
	return (dx * Fp.cos(a) + dy * Fp.sin(a) + 32768) >> 16


func _inv_y(k: int, dx: int, dy: int) -> int:
	match sym.group:
		MapGenSymmetry.G_D1X:
			return dy
		MapGenSymmetry.G_D2, MapGenSymmetry.G_D4:
			var uy: int = dx if (sym.group == MapGenSymmetry.G_D4 and (k & 4) != 0) else dy
			return -uy if (k & 2) != 0 else uy
	var a: int = k * Fp.TURN / sym.images
	return (-dx * Fp.sin(a) + dy * Fp.cos(a) + 32768) >> 16


## Paints `cells` (indices) by mode; every cell joins `keep`.
func _apply(cells: PackedInt32Array, mode: int, t: int) -> void:
	var terr: PackedByteArray = map.terrain
	var fl: PackedByteArray = map.flags
	var fo: PackedByteArray = map.field_of
	for i: int in cells:
		if mode == M_ROAD and (fl[i] & MapData.SF_START) != 0:
			continue  # trunk roads end at the start disc: the HQ yard stays buildable
		keep[i] = 1
		var t0: int = terr[i]
		match mode:
			M_FORCE:
				terr[i] = t
				fl[i] = fl[i] & ~MapData.SF_RAMP
			M_CLEAR:
				if t0 == MapTerrain.T_FOREST or t0 == MapTerrain.T_CLIFF or t0 == MapTerrain.T_ROCK \
						or t0 == MapTerrain.T_URBAN or t0 == MapTerrain.T_RUBBLE or t0 == MapTerrain.T_MARSH:
					terr[i] = MapTerrain.T_DIRT
					fl[i] = fl[i] & ~MapData.SF_RAMP
				elif t0 == MapTerrain.T_DEEP or t0 == MapTerrain.T_SHALLOW:
					terr[i] = MapTerrain.T_FORD
			M_ROAD:
				terr[i] = MapTerrain.T_FORD if (t0 == MapTerrain.T_DEEP or t0 == MapTerrain.T_SHALLOW) else t
				fl[i] = fl[i] & ~MapData.SF_RAMP
			_:
				if t0 == MapTerrain.T_DEEP or t0 == MapTerrain.T_SHALLOW:
					terr[i] = MapTerrain.T_FORD
				elif t0 != MapTerrain.T_ROAD and t0 != MapTerrain.T_PAVEMENT and fo[i] == 0:
					terr[i] = t
					fl[i] = fl[i] & ~MapData.SF_RAMP


func _mark(cells: PackedInt32Array, mask: PackedByteArray) -> void:
	for i: int in cells:
		mask[i] = 1


func _disc_all(cx2: int, cy2: int, r: int, mode: int, t: int) -> void:
	for k: int in sym.images:
		_cells.clear()
		sym.paint_disc(k, cx2, cy2, r, _cells)
		_apply(_cells, mode, t)


## Route a -> m -> b (m = midpoint, optionally scaled `via_pct` percent, displaced perpendicular by the meander hash),
## painted per image. Returns m through _ax / _ay.
func _route_mid(ax: int, ay: int, bx: int, by: int, via_pct: int) -> void:
	var mx: int = (ax + bx) / 2
	var my: int = (ay + by) / 2
	if via_pct != 100:
		mx = (ax + bx) * via_pct / 200
		my = (ay + by) * via_pct / 200
	var ex: int = bx - ax
	var ey: int = by - ay
	var ln: int = Fp.isqrt(ex * ex + ey * ey)
	if ln > 0:
		var disp: int = ((MapGenNoise.hash2(ax + 97, ay + 31, seed_a + bx * 3 + by * 5) - 32768) * tables.lay("route_amp2")) >> 15
		mx += -ey * disp / ln
		my += ex * disp / ln
	_ax = mx
	_ay = my


func _route(ax: int, ay: int, bx: int, by: int, via_pct: int, hw2: int, mode: int, t: int) -> void:
	_route_mid(ax, ay, bx, by, via_pct)
	var mx: int = _ax
	var my: int = _ay
	for k: int in sym.images:
		_cells.clear()
		sym.paint_segment(k, ax, ay, mx, my, hw2, _cells)
		sym.paint_segment(k, mx, my, bx, by, hw2, _cells)
		_apply(_cells, mode, t)


func _segment(ax: int, ay: int, bx: int, by: int, hw2: int, mode: int, t: int) -> void:
	for k: int in sym.images:
		_cells.clear()
		sym.paint_segment(k, ax, ay, bx, by, hw2, _cells)
		_apply(_cells, mode, t)


# ---- driver --------------------------------------------------------------------------------------------------------

func _run() -> void:
	size = map.w
	n = map.n
	sym = MapGenSymmetry.new(params.slots, size)
	gate_w = tables.lay("gate_w") + tables.lay("gate_w_step") * level
	start_r = tables.lay("start_r") + tables.lay("start_r_step") * level
	keep.resize(n)
	protect.resize(n)
	_anc_x.resize(KINDS * 2)
	_anc_y.resize(KINDS * 2)
	_anc_ok.resize(KINDS * 2)
	neutral_dims()
	_report(ST_LAYOUT, 0, 4)
	_place_starts()
	if params.family == MapGenParams.FAM_COAST and params.start_near_water and not template:
		_place_bays()
	_report(ST_LAYOUT, 1, 4)
	_place_gates()
	_report(ST_LAYOUT, 2, 4)
	_place_fields()
	_report(ST_FIELDS, 3, 4)
	if not ok:
		return
	if not template:
		_place_neutrals()
	_report(ST_NEUTRALS, 4, 4)
	_beaches()
	if template:
		_rock_clusters()
	else:
		_boulders()
	map.spawns = spawns
	map.fields = fields
	map.neutrals = neutrals
	map.neutral_ids = MapData.NEUTRAL_IDS_DEFAULT.duplicate()
	map.roads = roads
	map.deco_seed = MapGenNoise.mix32(params.seed_value, 0xDEC0, 7)


# ---- 1. starts -----------------------------------------------------------------------------------------------------

func _place_starts() -> void:
	p0x = sym.start_x2()
	p0y = sym.start_y2()
	order = sym.start_order()
	pos_of_image.resize(sym.images)
	for i: int in order.size():
		pos_of_image[order[i]] = i
	var keys: PackedInt64Array = PackedInt64Array()
	for k: int in range(1, sym.images):
		var dx: int = sym.img_x(k, p0x, p0y) - p0x
		var dy: int = sym.img_y(k, p0x, p0y) - p0y
		keys.append(((dx * dx + dy * dy) << 8) | k)
	keys.sort()
	for j: int in mini(2, keys.size()):
		var k: int = (keys[j] & 255) as int
		nn.append(k)
		nnx.append(sym.img_x(k, p0x, p0y))
		nny.append(sym.img_y(k, p0x, p0y))
	for i: int in order.size():
		var k: int = order[i]
		var sx2: int = sym.img_x(k, p0x, p0y)
		var sy2: int = sym.img_y(k, p0x, p0y)
		var cx: int = sym.cell_of2(sx2)
		var cy: int = sym.cell_of2(sy2)
		spawns.append_array(PackedInt32Array([i, cy * size + cx, Fp.atan2(-sy2, -sx2), k, i & 1, 0]))
	for k: int in sym.images:
		_scx.append(_cx(k, p0x, p0y))
		_scy.append(_cy(k, p0x, p0y))
	_disc_all(p0x, p0y, start_r, M_FORCE, MapTerrain.T_GRASS)
	for k: int in sym.images:
		_cells.clear()
		sym.paint_disc(k, p0x, p0y, start_r + 1, _cells)
		for c: int in _cells:
			map.flags[c] = map.flags[c] | MapData.SF_START


# ---- 2. bays ---------------------------------------------------------------------------------------------------------

func _place_bays() -> void:
	var pw: int = tables.bay_pocket_w
	var ph: int = tables.bay_pocket_h
	var off2: int = 2 * (tables.bay_near_edge + pw / 2)
	var deep_hw: int = tables.canal_deep
	var bank_hw: int = tables.canal_deep + 2 * tables.canal_bank
	for k: int in sym.images:
		var sx2: int = sym.img_x(k, p0x, p0y)
		var sy2: int = sym.img_y(k, p0x, p0y)
		var horiz: bool = absi(sx2) >= absi(sy2)
		var dx: int = (1 if sx2 >= 0 else -1) if horiz else 0
		var dy: int = 0 if horiz else (1 if sy2 >= 0 else -1)
		var cx2: int = sx2 + dx * off2
		var cy2: int = sy2 + dy * off2
		var ex: int = dx * size
		var ey: int = dy * size
		var s2x: int = cx2 + dx * (pw - 2)  # the canal starts at the pocket's far edge (one cell of overlap)
		var s2y: int = cy2 + dy * (pw - 2)
		var mx: int = (s2x + ex) / 2 if horiz else cx2
		var my: int = cy2 if horiz else (s2y + ey) / 2
		var lx: int = absi(ex - s2x) / 2 + 2
		var ly: int = absi(ey - s2y) / 2 + 2
		# canal bank (shallow), canal (deep), pocket (deep); rectangles are axis aligned in the image frame
		_cells.clear()
		sym.paint_rect2(0, mx, my, lx if horiz else bank_hw, bank_hw if horiz else ly, _cells)
		_apply(_cells, M_FORCE, MapTerrain.T_SHALLOW)
		_mark(_cells, protect)
		_cells.clear()
		sym.paint_rect2(0, mx, my, lx if horiz else deep_hw, deep_hw if horiz else ly, _cells)
		_apply(_cells, M_FORCE, MapTerrain.T_DEEP)
		_mark(_cells, protect)
		_cells.clear()
		sym.paint_rect2(0, cx2, cy2, pw if horiz else ph, ph if horiz else pw, _cells)
		_apply(_cells, M_FORCE, MapTerrain.T_DEEP)
		_mark(_cells, protect)
		_pcx.append(sym.cell_of2(cx2))
		_pcy.append(sym.cell_of2(cy2))


# ---- 3. gates and trunk roads ----------------------------------------------------------------------------------------

func _place_gates() -> void:
	_route(p0x, p0y, 0, 0, 100, gate_w, M_CLEAR, 0)
	for j: int in nn.size():
		_route(p0x, p0y, nnx[j], nny[j], 120, gate_w, M_CLEAR, 0)
	if params.family == MapGenParams.FAM_URBAN:
		return  # urban streets are terrain: no trunk roads, no polylines
	_road_route(0, 0, 100)
	if not nn.is_empty():
		_road_route(nnx[0], nny[0], 120)


func _road_route(bx: int, by: int, via_pct: int) -> void:
	_route(p0x, p0y, bx, by, via_pct, 3, M_ROAD, MapTerrain.T_ROAD)
	_route_mid(p0x, p0y, bx, by, via_pct)
	var mx: int = _ax
	var my: int = _ay
	for k: int in sym.images:
		var pl: PackedInt32Array = PackedInt32Array()
		for pt: int in 3:
			var x2: int = p0x if pt == 0 else (mx if pt == 1 else bx)
			var y2: int = p0y if pt == 0 else (my if pt == 1 else by)
			pl.append((sym.img_x(k, x2, y2) + size) * 8)
			pl.append((sym.img_y(k, x2, y2) + size) * 8)
		roads.append(pl)


# ---- 4. fields -------------------------------------------------------------------------------------------------------

func _place_fields() -> void:
	# (kind, sub, mandatory): CONTESTED (largest claim) first, START x2, NATURAL, NATURAL_RICH, FURTHER x2
	var plan: Array[PackedInt32Array] = [
		PackedInt32Array([MapData.FK_CONTESTED, 0, 0]), PackedInt32Array([MapData.FK_CONTESTED, 1, 0]),
		PackedInt32Array([MapData.FK_START, 0, 1]), PackedInt32Array([MapData.FK_START, 1, 1]),
		PackedInt32Array([MapData.FK_NATURAL, 0, 1]), PackedInt32Array([MapData.FK_NATURAL_RICH, 0, 0]),
		PackedInt32Array([MapData.FK_FURTHER, 0, 0]), PackedInt32Array([MapData.FK_FURTHER, 1, 0])]
	for pl: PackedInt32Array in plan:
		var placed: bool = false
		for ai: int in ANG_OFF.size():
			for si: int in DIST_SC.size():
				if _try_field(pl[0], pl[1], ai, si):
					placed = true
					break
			if placed:
				break
		if not placed and pl[2] != 0:
			_fail("field kind %d/%d not placeable" % [pl[0], pl[1]])
			return


## Sets the canonical anchor (_ax, _ay) of candidate (ai, si); false when this kind / sub does not exist.
func _anchor(kind: int, sub: int, ai: int, si: int) -> bool:
	var off: int = ANG_OFF[ai]
	var sc: int = DIST_SC[si]
	var ac: int = Fp.atan2(-p0y, -p0x)
	match kind:
		MapData.FK_START:
			var s: int = 1 if sub == 0 else -1
			var a: int = Fp.atan2(p0y, p0x) + s * 1024 + s * off
			var d: int = 22 * sc / 100
			_ax = p0x + Fp.step_x(a, d)
			_ay = p0y + Fp.step_y(a, d)
		MapData.FK_NATURAL, MapData.FK_NATURAL_RICH:
			if sub != 0:
				return false
			var a: int = ac + (450 if kind == MapData.FK_NATURAL else 100) + off
			var d: int = 2 * size * 16 / 100 * sc / 100
			_ax = p0x + Fp.step_x(a, d)
			_ay = p0y + Fp.step_y(a, d)
		MapData.FK_FURTHER:
			if sub == 0:
				var a0: int = ac - 450 + off
				var d0: int = 2 * size * 22 / 100 * sc / 100
				_ax = p0x + Fp.step_x(a0, d0)
				_ay = p0y + Fp.step_y(a0, d0)
			else:
				if nn.is_empty():
					return false
				var a1: int = Fp.atan2(nny[0] - p0y, nnx[0] - p0x) + off
				var d1: int = 2 * size * 20 / 100 * sc / 100
				_ax = p0x + Fp.step_x(a1, d1)
				_ay = p0y + Fp.step_y(a1, d1)
		_:
			if params.slots == 2:
				if off != 0:
					return false
				var yy: int = p0y * 65 / 100 + (1 if sub == 0 else -1) * (size * 35 / 100)
				_ax = 1
				_ay = yy * sc / 100
			else:
				if sub >= nn.size():
					return false
				var mx: int = (p0x + nnx[sub]) * 65 / 200
				var my: int = (p0y + nny[sub]) * 65 / 200
				_ax = Fp.rot_x(mx, my, off) * sc / 100
				_ay = Fp.rot_y(mx, my, off) * sc / 100
	return true


func _try_field(kind: int, sub: int, ai: int, si: int) -> bool:
	if not _anchor(kind, sub, ai, si):
		return false
	var ax: int = _ax
	var ay: int = _ay
	var edge: int = tables.lay("field_edge_margin")
	var sp2: int = tables.lay("field_spacing") * tables.lay("field_spacing")
	var imgs: PackedInt32Array = PackedInt32Array()
	var icx: PackedInt32Array = PackedInt32Array()
	var icy: PackedInt32Array = PackedInt32Array()
	var dup_reg: int = 0
	for k: int in sym.images:
		var cx: int = _cx(k, ax, ay)
		var cy: int = _cy(k, ax, ay)
		var dup: bool = false
		for q: int in _fcx.size():
			if _fkind[q] == kind and absi(_fcx[q] - cx) <= 2 and absi(_fcy[q] - cy) <= 2:
				dup = true
		if dup:
			dup_reg += 1
			continue
		for q: int in imgs.size():
			if absi(icx[q] - cx) <= 2 and absi(icy[q] - cy) <= 2:
				dup = true  # self-symmetric anchor: the image lies on top of an earlier image of this candidate
		if dup and kind != MapData.FK_CONTESTED:
			return false  # only contested fields sit on symmetry axes by design; others must have one image per slot
		if not dup:
			imgs.append(k)
			icx.append(cx)
			icy.append(cy)
	if imgs.is_empty():
		return true  # every image is a duplicate of an earlier field of the kind: nothing to place
	if dup_reg > 0:
		return false  # partly on top of an earlier field of the kind: slots would end up unequal, try the next candidate
	for q: int in imgs.size():
		var cx: int = icx[q]
		var cy: int = icy[q]
		if cx < edge or cy < edge or cx >= size - edge or cy >= size - edge:
			return false
		for r: int in _fcx.size():
			if (_fcx[r] - cx) * (_fcx[r] - cx) + (_fcy[r] - cy) * (_fcy[r] - cy) < sp2:
				return false
		for r: int in _pcx.size():
			if (_pcx[r] - cx) * (_pcx[r] - cx) + (_pcy[r] - cy) * (_pcy[r] - cy) < sp2:
				return false
		for r: int in q:
			if (icx[r] - cx) * (icx[r] - cx) + (icy[r] - cy) * (icy[r] - cy) < sp2:
				return false
		if _is_water(map.terrain[cy * size + cx]):
			return false
		_cells.clear()
		sym.paint_disc(imgs[q], ax, ay, FIELD_R, _cells)
		for c: int in _cells:
			if protect[c] != 0:
				return false
	# commit
	var rich: bool = kind == MapData.FK_NATURAL_RICH or kind == MapData.FK_CONTESTED
	var dep: Dictionary = tables.deposit["rich" if rich else "standard"] as Dictionary
	var cells_k: int = dep["cells"] as int
	var per_cell: int = (dep["per_cell"] as int) * (50 + params.resources) / 100
	for q: int in imgs.size():
		var k: int = imgs[q]
		_cells.clear()
		sym.paint_disc(k, ax, ay, FIELD_R, _cells)
		_apply(_cells, M_FORCE, MapTerrain.T_GRASS)
		_stamp_deposit(k, ax, ay, kind, cells_k, per_cell, dep["klass"] as int)
		_fcx.append(icx[q])
		_fcy.append(icy[q])
		_fkind.append(kind)
		if kind != MapData.FK_START:
			_segment(p0x, p0y, ax, ay, gate_w, M_CLEAR, 0)
			_segment(p0x, p0y, ax, ay, 3, M_PATH, MapTerrain.T_DIRT)
	_anc_x[kind * 2 + sub] = ax
	_anc_y[kind * 2 + sub] = ay
	_anc_ok[kind * 2 + sub] = 1
	return true


## The `cells_k` cells of the 7x7 window around image k's centre with the smallest canonical key get `per_cell`.
func _stamp_deposit(k: int, ax: int, ay: int, kind: int, cells_k: int, per_cell: int, klass: int) -> void:
	var px: int = sym.img_x(k, ax, ay)
	var py: int = sym.img_y(k, ax, ay)
	var ccx: int = sym.cell_of2(px)
	var ccy: int = sym.cell_of2(py)
	var keys: PackedInt64Array = PackedInt64Array()
	for wy: int in range(ccy - 3, ccy + 4):
		for wx: int in range(ccx - 3, ccx + 4):
			var dx: int = sym.to2(wx) - px
			var dy: int = sym.to2(wy) - py
			var ux: int = _inv_x(k, dx, dy)
			var uy: int = _inv_y(k, dx, dy)
			var key: int = (ux * ux + uy * uy) * 64 + (MapGenNoise.hash2(ux, uy, seed_a + 91) & 63)
			keys.append((key << 20) | (wy * size + wx))
	keys.sort()
	var id: int = _next_id
	_next_id += 1
	var total: int = 0
	for q: int in cells_k:
		var c: int = (keys[q] & 0xFFFFF) as int
		map.field_of[c] = id
		map.deposit_max[c] = per_cell
		total += per_cell
		var x: int = c % size
		var y: int = c / size
		for ry: int in range(y - 1, y + 2):
			for rx: int in range(x - 1, x + 2):
				map.flags[ry * size + rx] = map.flags[ry * size + rx] | MapData.SF_NOBUILD
	var cc: int = ccy * size + ccx
	# hint cell: 6 cells from the centre toward the owning (contested: nearest) start
	var own: int = pos_of_image[k]
	var best: int = 0
	var bd: int = 1 << 40
	for q: int in sym.images:
		var d2: int = (_scx[q] - ccx) * (_scx[q] - ccx) + (_scy[q] - ccy) * (_scy[q] - ccy)
		if kind == MapData.FK_CONTESTED:
			if d2 < bd:
				bd = d2
				best = q
	var tk: int = best if kind == MapData.FK_CONTESTED else k
	var dxs: int = _scx[tk] - ccx
	var dys: int = _scy[tk] - ccy
	var ln: int = Fp.isqrt(dxs * dxs + dys * dys)
	var hx: int = ccx
	var hy: int = ccy
	if ln > 0:
		hx += dxs * 6 / ln
		hy += dys * 6 / ln
	fields.append_array(PackedInt32Array([id, cc, 3, cells_k, total, kind, k, hy * size + hx, klass,
		-1 if kind == MapData.FK_CONTESTED else own]))


# ---- 5. neutrals -----------------------------------------------------------------------------------------------------

func _anchor_of(name: String) -> bool:
	_ax = 0
	_ay = 0
	match name:
		"natural":
			return _load_anc(MapData.FK_NATURAL, 0)
		"contested":
			return _load_anc(MapData.FK_CONTESTED, 0) or _load_anc(MapData.FK_CONTESTED, 1)
		"further":
			return _load_anc(MapData.FK_FURTHER, 0) or _load_anc(MapData.FK_FURTHER, 1)
		"center":
			return true
		"start_30":
			_ax = p0x * 30 / 100
			_ay = p0y * 30 / 100
			return true
	return false


func _load_anc(kind: int, sub: int) -> bool:
	if _anc_ok[kind * 2 + sub] == 0:
		return false
	_ax = _anc_x[kind * 2 + sub]
	_ay = _anc_y[kind * 2 + sub]
	return true


func _place_neutrals() -> void:
	var dims: Dictionary = neutral_dims()
	var fam: int = params.family
	# the numerous civilian garrisons go last so that they cannot starve the single-item rows of space
	for pass_i: int in 2:
		for row: int in tables.neutrals.size():
			var nr: Dictionary = tables.neutrals[row] as Dictionary
			var id: String = nr["id"] as String
			if (id == "neutral.civilian_garrison") != (pass_i == 1):
				continue
			var cnt: int = tables.neutral_count(row, fam, size)
			var per_map: bool = tables.neutral_is_per_map(row, fam)
			if not per_map:
				cnt = (cnt * (params.neutrals + 25) + 37) / 75
			if cnt <= 0 or not _anchor_of(nr["anchor"] as String):
				continue
			var ax: int = _ax
			var ay: int = _ay
			var ring: Array = nr["ring"] as Array
			var wh: int = dims[id] as int
			for j: int in cnt:
				if not _place_lot(MapGenTables.neutral_kind_of(id), wh >> 8, wh & 255, ax, ay, ring[0] as int, ring[1] as int, j,
						per_map, nr.get("shore", false) == true, id.ends_with("field_hospital")):
					break  # no room left around this anchor: later items of the row would not fit either


func _lot_ok(x0: int, y0: int, w: int, h: int, shore: bool) -> bool:
	var m: int = tables.lay("neutral_edge_margin")
	if x0 - 1 < m or y0 - 1 < m or x0 + w + 1 > size - m or y0 + h + 1 > size - m:
		lot_reject[0] += 1
		return false
	var terr: PackedByteArray = map.terrain
	for y: int in range(y0 - 1, y0 + h + 1):
		for x: int in range(x0 - 1, x0 + w + 1):
			var i: int = y * size + x
			var t: int = terr[i]
			if t == MapTerrain.T_CLIFF or t == MapTerrain.T_MOUNTAIN or protect[i] != 0 or map.field_of[i] != 0:
				lot_reject[1] += 1
				return false
			if t == MapTerrain.T_DEEP or t == MapTerrain.T_FORD:
				lot_reject[1] += 1
				return false
			if t == MapTerrain.T_SHALLOW:
				var inside: bool = x >= x0 and y >= y0 and x < x0 + w and y < y0 + h
				if inside or not shore:
					lot_reject[1] += 1
					return false
	var ccx: int = x0 + (w - 1) / 2
	var ccy: int = y0 + (h - 1) / 2
	var sd: int = tables.lay("neutral_start_dist")
	for q: int in _scx.size():
		if maxi(absi(_scx[q] - ccx), absi(_scy[q] - ccy)) < sd:
			lot_reject[2] += 1
			return false
	var fd: int = tables.lay("neutral_field_dist")
	for q: int in _fcx.size():
		if maxi(absi(_fcx[q] - ccx), absi(_fcy[q] - ccy)) < fd:
			lot_reject[3] += 1
			return false
	for q: int in _lcx.size():
		if maxi(absi(_lcx[q] - ccx), absi(_lcy[q] - ccy)) < fd:
			lot_reject[4] += 1
			return false
	if shore:
		var deep: bool = false
		for y: int in range(y0 - 5, y0 + h + 5):
			for x: int in range(x0 - 5, x0 + w + 5):
				if x >= 0 and y >= 0 and x < size and y < size and terr[y * size + x] == MapTerrain.T_DEEP:
					deep = true
		if not deep:
			lot_reject[5] += 1
			return false
	return true


## One neutral item j, replicated per image. Each image walks the same candidate sequence (angle = base + j * 700 +
## retry * 341 alternating sign, radius r0..r1; then the ring widened by 8) and takes the first lot that is valid FOR
## THAT IMAGE (exact groups agree by symmetry; the rotation groups may differ by a retry, which keeps their counts
## equal). Last resort: an exhaustive scan of the offsets around the anchor, nearest first (thin shore bands).
## Returns false when NO image found room (the caller then stops the row).
func _place_lot(kind: int, w: int, h: int, ax: int, ay: int, r0: int, r1: int, j: int, per_map: bool, shore: bool,
		toward_centre: bool) -> bool:
	var base: int = Fp.atan2(ay, ax) + (2048 if toward_centre else 0)
	if ax == 0 and ay == 0:
		base = 0
	var urban: bool = params.family == MapGenParams.FAM_URBAN
	var scan: PackedInt64Array = PackedInt64Array()
	var any: bool = false
	for k: int in (1 if per_map else sym.images):
		var placed: bool = false
		for pass_i: int in 2:  # second pass: the ring widened by 8 cells
			var span: int = r1 - r0 + 1 + 8 * pass_i
			for t: int in NEUTRAL_TRIES:
				var sgn: int = 1 if (t & 1) == 1 else -1
				var ang: int = base + j * 700 + sgn * ((t + 1) / 2) * 341
				var rad: int = r0 + (t * 7 + j * 3) % span
				if _try_lot(k, kind, w, h, ax, ay, ax + Fp.step_x(ang, 2 * rad), ay + Fp.step_y(ang, 2 * rad), urban, shore):
					placed = true
					break
			if placed:
				break
		if placed:
			any = true
			continue
		if scan.is_empty():
			var reach: int = r1 + (24 if per_map else 8)
			for oy: int in range(-reach, reach + 1):
				for ox: int in range(-reach, reach + 1):
					var d2: int = ox * ox + oy * oy
					if d2 <= reach * reach:
						scan.append(((d2 * 64 + (MapGenNoise.hash2(ox, oy, seed_a + 177 + j) & 63)) << 16) | ((oy + 64) << 8) | (ox + 64))
			scan.sort()
		for key: int in scan:
			var sx: int = ax + 2 * (((key & 255) as int) - 64)
			var sy: int = ay + 2 * ((((key >> 8) & 255) as int) - 64)
			if _try_lot(k, kind, w, h, ax, ay, sx, sy, urban, shore):
				any = true
				break
		if not any:
			return false  # the first image found nothing anywhere near the anchor: give the item up for every image
	return any


func _try_lot(k: int, kind: int, w: int, h: int, ax: int, ay: int, lx: int, ly: int, urban: bool, shore: bool) -> bool:
	var x0: int = sym.cell_of2(sym.img_x(k, lx, ly) - (w - 1))
	var y0: int = sym.cell_of2(sym.img_y(k, lx, ly) - (h - 1))
	if not _lot_ok(x0, y0, w, h, shore):
		return false
	_commit_lot(k, kind, x0, y0, w, h, lx, ly, ax, ay, urban, shore)
	return true


func _commit_lot(k: int, kind: int, x0: int, y0: int, w: int, h: int, lx: int, ly: int, ax: int, ay: int,
		urban: bool, shore: bool) -> void:
	var t: int = MapTerrain.T_PAVEMENT if urban else MapTerrain.T_GRASS
	for y: int in range(y0 - 2, y0 + h + 2):
		for x: int in range(x0 - 2, x0 + w + 2):
			var i: int = y * size + x
			map.flags[i] = map.flags[i] | MapData.SF_NOBUILD
			if x >= x0 - 1 and y >= y0 - 1 and x < x0 + w + 1 and y < y0 + h + 1:
				keep[i] = 1
				if not (shore and _is_water(map.terrain[i])):
					map.terrain[i] = t
					map.flags[i] = map.flags[i] & ~MapData.SF_RAMP
	_lcx.append(x0 + (w - 1) / 2)
	_lcy.append(y0 + (h - 1) / 2)
	neutrals.append_array(PackedInt32Array([kind, y0 * size + x0, w, h, MapGenNoise.hash2(x0, y0, seed_a + 131) & 3, 0, k, 0]))
	_cells.clear()
	sym.paint_segment(k, ax, ay, lx, ly, CORR_HW2, _cells)
	_apply(_cells, M_CLEAR, 0)


# ---- 6. beaches, boulders, template clusters --------------------------------------------------------------------------

func _beaches() -> void:
	var terr: PackedByteArray = map.terrain
	var rim: int = MapData.RIM_W
	var out: PackedInt32Array = PackedInt32Array()
	for y: int in range(rim, size - rim):
		for x: int in range(rim, size - rim):
			var i: int = y * size + x
			var t: int = terr[i]
			if keep[i] != 0 or (t != MapTerrain.T_GRASS and t != MapTerrain.T_DIRT and t != MapTerrain.T_MARSH):
				continue
			if _is_water(terr[i - 1]) or _is_water(terr[i + 1]) or _is_water(terr[i - size]) or _is_water(terr[i + size]):
				out.append(i)
	for i: int in out:
		terr[i] = MapTerrain.T_BEACH


func _boulders() -> void:
	var cnt: int = 3 if params.family == MapGenParams.FAM_OPEN else (2 if params.family == MapGenParams.FAM_COAST else 0)
	var span: int = size - 28
	var done: int = 0
	for b: int in cnt * 4:
		if done >= cnt:
			break
		var px: int = (((MapGenNoise.hash2(b, 1, seed_a + 201) * span) >> 16) - span / 2) * 2
		var py: int = (((MapGenNoise.hash2(b, 2, seed_a + 201) * span) >> 16) - span / 2) * 2
		var sz: int = 1 + MapGenNoise.hash2(b, 3, seed_a + 201) % 3
		var okb: bool = true
		var placed: PackedInt32Array = PackedInt32Array()
		for k: int in sym.images:
			for e: int in sz:
				var ox: int = 2 if e == 1 else 0
				var oy: int = 2 if e == 2 else 0
				var cx: int = _cx(k, px + ox, py + oy)
				var cy: int = _cy(k, px + ox, py + oy)
				if not _boulder_ok(cx, cy):
					okb = false
				else:
					placed.append(cy * size + cx)
		if okb:
			for c: int in placed:
				map.flags[c] = map.flags[c] | MapData.SF_BLOCK
				keep[c] = 1
			done += 1


func _boulder_ok(cx: int, cy: int) -> bool:
	var m: int = MapData.RIM_W + 8
	if cx < m or cy < m or cx >= size - m or cy >= size - m:
		return false
	for y: int in range(cy - 1, cy + 2):
		for x: int in range(cx - 1, cx + 2):
			var i: int = y * size + x
			if keep[i] != 0 or (map.flags[i] & (MapData.SF_BLOCK | MapData.SF_NOBUILD | MapData.SF_START)) != 0:
				return false
	var t: int = map.terrain[cy * size + cx]
	return t == MapTerrain.T_GRASS or t == MapTerrain.T_DIRT


## Template: one small ROCK cluster per image at 0.35 R, only on cells nothing else painted.
func _rock_clusters() -> void:
	var a: int = Fp.atan2(p0y, p0x) + 700
	var d: int = 2 * (size / 2) * 35 / 100
	var cx2: int = Fp.step_x(a, d)
	var cy2: int = Fp.step_y(a, d)
	var rock: PackedInt32Array = PackedInt32Array()
	for k: int in sym.images:
		_cells.clear()
		sym.paint_disc(k, cx2, cy2, 2, _cells)
		for c: int in _cells:
			if keep[c] == 0:
				rock.append(c)
	for c: int in rock:
		map.terrain[c] = MapTerrain.T_ROCK
