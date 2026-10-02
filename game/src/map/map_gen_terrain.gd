class_name MapGenTerrain
extends RefCounted
## Generator phase A (terrain_movement 5.12.4): height and noise fields on the folded domain, percentile thresholds,
## family classification (open / urban / coast), terraces with cliffs and ramps, moat and marsh (coast) and the rim.
## Expensive, run once per attempt; the result (`terrain_base`, `flags_base`, `height`, `moisture`, `plateau`) is a pure
## function of (MapTerrain, MapGenTables, MapGenParams, seed_a) and is copied into a fresh MapData by `make_map()`
## for every phase-B retry. Integer only, reentrant (no static state), safe on a worker thread.
##
## Speed: every noise field is evaluated once per DISTINCT folded point (memo over the fold domain: half / quarter /
## eighth of the cells for the D groups, ~1/6 or 1/12 for rotations) through lattice-cached `MapGenNoise.Field`s.

const ST_HEIGHT: int = 0
const ST_CLASSIFY: int = 1
const ST_WATER: int = 2
const ST_CLIFFS: int = 3

# noise domain offsets (keep operands non-negative)
## The water percentile / depth test runs on the height BEFORE the 0..255 clamp of the coast falloff (deviation, see
## the report): clamping would pile ~30 % of a coast map into bin 0, making `H <= t_water - 10` (deep) unreachable and
## the whole sea shallow. Histogram bin = value + WATER_BIAS.
const WATER_BIAS: int = 128
const _H_OFF: int = 4096
const _F2_U: int = 5095
const _F2_V: int = 4873
const _F3_U: int = 4429
const _F3_V: int = 4651
const _F6_U: int = 5596
const _F6_V: int = 5796

var params: MapGenParams = null
var tt: MapTerrain = null
var tables: MapGenTables = null
var sym: MapGenSymmetry = null
var seed_a: int = 0
var size: int = 0
var n: int = 0
# ---- results ----
var terrain_base: PackedByteArray = PackedByteArray()  ## terrain types after phase A (rim included)
var flags_base: PackedByteArray = PackedByteArray()  ## MapData.SF_RAMP on ramp cells, SF_NOBUILD on the rim
var height: PackedByteArray = PackedByteArray()  ## H 0..255 (source of MapData.height)
var moisture: PackedByteArray = PackedByteArray()  ## F2 (view layer)
var plateau: PackedByteArray = PackedByteArray()  ## 1 where F3 >= t_plateau (interior, non-water); terraced families
# ---- thresholds (telemetry / tests; -1 = not used) ----
var t_water: int = -1000  ## on the UNCLAMPED height scale (coast falloff can go below 0), see WATER_BIAS
var t_forest: int = -1
var t_rock: int = -1
var t_plateau: int = -1
var t_sand: int = -1

var _progress: Callable = Callable()
var _f_h: MapGenNoise.Field = null
var _f_2: MapGenNoise.Field = null
var _f_3: MapGenNoise.Field = null
var _f_4: MapGenNoise.Field = null
var _f_5: MapGenNoise.Field = null
var _f_6: MapGenNoise.Field = null


## Runs phase A. `p_seed_a` is the attempt seed (seed for attempt 0, mix32(seed, attempt, 0x51ED) later).
## progress.call(stage, pct) is invoked between stages (pct within the tables' 0..64 phase-A range, monotonic).
static func generate(p_tt: MapTerrain, p_params: MapGenParams, p_tables: MapGenTables, p_seed_a: int,
		p_progress: Callable = Callable()) -> MapGenTerrain:
	var g: MapGenTerrain = MapGenTerrain.new()
	g.tt = p_tt
	g.params = p_params
	g.tables = p_tables
	g.seed_a = p_seed_a
	g._progress = p_progress
	g._run()
	return g


## A fresh, un-finalized MapData holding the phase-A layers and the generator identity fields (seed_value, family,
## biome (urban forces 3), slots, players = slots, gen_version, gen_params). Phase B paints onto it.
func make_map() -> MapData:
	var m: MapData = MapData.create(tt, size, MapTerrain.T_GRASS)
	m.terrain = terrain_base.duplicate()
	m.flags = flags_base.duplicate()
	m.height = height.duplicate()
	m.moisture = moisture.duplicate()
	m.seed_value = params.seed_value
	m.family = params.family
	m.biome = 3 if params.family == MapGenParams.FAM_URBAN else params.biome
	m.slots = params.slots
	m.players = params.slots
	m.gen_version = MapGenParams.VERSION
	m.gen_params = params.to_ints()
	return m


func _report(stage: int, pct: int) -> void:
	if _progress.is_valid():
		_progress.call(stage, pct)


func _pct(key: String, num: int, den: int) -> int:
	var r: Array = tables.progress[key] as Array
	return (r[0] as int) + ((r[1] as int) - (r[0] as int)) * num / den


## All noise fields of one folded point packed in an int: H0 | F2 << 8 | F3 << 16 | F4 << 24 | F5 << 32 | F6 << 40
## (each `>> 8`, 0..255). Fields a family does not use are skipped (0).
func _eval(fu: int, fv: int) -> int:
	var v: int = _f_h.at(fu + _H_OFF, fv + _H_OFF) >> 8
	if _f_2 != null:
		v |= (_f_2.at(fu + _F2_U, fv + _F2_V) >> 8) << 8
	if _f_3 != null:
		v |= (_f_3.at(fu + _F3_U, fv + _F3_V) >> 8) << 16
	if _f_4 != null:
		v |= (_f_4.at(fu + _H_OFF, fv + _H_OFF) >> 8) << 24
	if _f_5 != null:
		v |= (_f_5.at(fu + _H_OFF, fv + _H_OFF) >> 8) << 32
	if _f_6 != null:
		v |= (_f_6.at(fu + _F6_U, fv + _F6_V) >> 8) << 40
	return v


func _run() -> void:
	size = params.size
	n = size * size
	sym = MapGenSymmetry.new(params.slots, size)
	var fam: int = params.family
	var urban: bool = fam == MapGenParams.FAM_URBAN
	var coast: bool = fam == MapGenParams.FAM_COAST
	var dens: int = params.effective_density(tables)
	var wpct: int = params.effective_water_pct(tables)
	var s: int = seed_a
	var rim_w: int = MapData.RIM_W

	# ---- 1. height and noise fields (memo over the fold domain) ----
	var u0: int = sym.fu_min
	var u1: int = sym.fu_max
	var v0: int = sym.fv_min
	var v1: int = sym.fv_max
	var dw: int = u1 - u0 + 1
	var base_shift: int = 5 if size < 200 else 6
	_f_h = MapGenNoise.Field.fbm_field(u0 + _H_OFF, u1 + _H_OFF, v0 + _H_OFF, v1 + _H_OFF, s, base_shift)
	_f_2 = MapGenNoise.Field.fbm_field(u0 + _F2_U, u1 + _F2_U, v0 + _F2_V, v1 + _F2_V, s + 11, 4)
	if not urban:
		_f_3 = MapGenNoise.Field.fbm_field(u0 + _F3_U, u1 + _F3_U, v0 + _F3_V, v1 + _F3_V, s + 23, 4)
		_f_4 = MapGenNoise.Field.vnoise_field(u0 + _H_OFF, u1 + _H_OFF, v0 + _H_OFF, v1 + _H_OFF, 3, s + 37)
	if coast:
		_f_5 = MapGenNoise.Field.vnoise_field(u0 + _H_OFF, u1 + _H_OFF, v0 + _H_OFF, v1 + _H_OFF, 4, s + 51)
		_f_6 = MapGenNoise.Field.vnoise_field(u0 + _F6_U, u1 + _F6_U, v0 + _F6_V, v1 + _F6_V, 3, s + 63)
	var memo: PackedInt64Array = PackedInt64Array()
	memo.resize(dw * (v1 - v0 + 1))
	memo.fill(-1)
	var cellkey: PackedInt32Array = PackedInt32Array()
	cellkey.resize(n)
	height.resize(n)
	moisture.resize(n)
	var hist_h: PackedInt32Array = PackedInt32Array()
	hist_h.resize(256 + WATER_BIAS)
	var hsig: PackedInt32Array = PackedInt32Array()  ## unclamped height (coast) for the water test
	hsig.resize(n)
	var hist2: PackedInt32Array = PackedInt32Array()
	hist2.resize(256)
	var hist3: PackedInt32Array = PackedInt32Array()
	hist3.resize(256)
	var hist4: PackedInt32Array = PackedInt32Array()
	hist4.resize(256)
	var exact: bool = sym.is_exact()
	var playable: int = 0
	for y: int in size:
		var y2: int = 2 * y + 1 - size
		for x: int in size:
			var x2: int = 2 * x + 1 - size
			var p: int = sym.fold(x2, y2)
			var key: int = ((p >> 16) - MapGenSymmetry.FOLD_V_OFF - v0) * dw + (p & 0xFFFF) - u0
			var mv: int = memo[key]
			if mv < 0:
				mv = _eval(p & 0xFFFF, (p >> 16) - MapGenSymmetry.FOLD_V_OFF)
				memo[key] = mv
			var i: int = y * size + x
			cellkey[i] = key
			var hv: int = mv & 255
			var hu: int = hv
			if urban:
				hv = 110 + ((hv - 128) >> 3)
				hu = hv
			elif coast:
				var dist: int = maxi(absi(x2), absi(y2)) if exact else Fp.isqrt(x2 * x2 + y2 * y2)
				hu = hv - 3 * clampi(dist * 100 / size - 60, 0, 40)
				hv = clampi(hu, 0, 255)
			height[i] = hv
			hsig[i] = hu
			var f2: int = (mv >> 8) & 255
			moisture[i] = f2
			hist2[f2] += 1
			if not urban:
				if x >= rim_w and y >= rim_w and x < size - rim_w and y < size - rim_w:
					hist_h[hu + WATER_BIAS] += 1
					playable += 1
				hist3[(mv >> 16) & 255] += 1
				hist4[(mv >> 24) & 255] += 1
		if (y & 7) == 7:
			_report(ST_HEIGHT, _pct("height", y + 1, size))
	_report(ST_HEIGHT, _pct("height", 1, 1))

	# ---- 2. thresholds by percentile ----
	var base: int = tables.biome_base[params.biome]
	var sand_pm: int = tables.biome_sand_pm[params.biome]
	if not urban:
		t_forest = MapGenNoise.top_threshold(hist2, 3 * dens * n / 1000)
		t_rock = MapGenNoise.top_threshold(hist3, dens * n / 1000)
		t_plateau = MapGenNoise.top_threshold(hist3, (250 + 4 * dens) * n / 1000)
		t_water = MapGenNoise.low_threshold(hist_h, wpct * playable / 100) - WATER_BIAS if wpct > 0 else -1000
		t_sand = MapGenNoise.top_threshold(hist4, sand_pm * n / 1000)

	# ---- 3. classification ----
	terrain_base.resize(n)
	flags_base.resize(n)
	if urban:
		_classify_urban(cellkey, u0, dw, s)
	else:
		_classify_open(cellkey, memo, hsig, u0, v0, dw, s, base, sand_pm)
	_report(ST_CLASSIFY, _pct("classify", 1, 2))

	# ---- 4. terraces, cliffs, ramps ----
	plateau.resize(n)
	if tables.fam_terraces(fam):
		for y: int in range(rim_w, size - rim_w):
			for x: int in range(rim_w, size - rim_w):
				var i: int = y * size + x
				var t: int = terrain_base[i]
				if t == MapTerrain.T_DEEP or t == MapTerrain.T_SHALLOW:
					continue
				var mv: int = memo[cellkey[i]]
				if ((mv >> 16) & 255) < t_plateau:
					continue
				plateau[i] = 1
				var terr: int = height[i] >> 5
				if (height[i - 1] >> 5) > terr or (height[i + 1] >> 5) > terr \
						or (height[i - size] >> 5) > terr or (height[i + size] >> 5) > terr:
					if ((mv >> 24) & 255) > 168:
						terrain_base[i] = MapTerrain.T_ROCK
						flags_base[i] = MapData.SF_RAMP
					else:
						terrain_base[i] = MapTerrain.T_CLIFF
	_report(ST_CLIFFS, _pct("classify", 2, 2))

	# ---- 5. moat and marsh (coast) ----
	if coast and tables.fam_moat(fam):
		_carve_moat(memo, cellkey)
	if coast and tables.fam_marsh(fam):
		_marsh(memo, cellkey)

	# ---- 6. rim ----
	for y: int in size:
		for x: int in size:
			var d: int = mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			if d < rim_w:
				var i: int = y * size + x
				flags_base[i] = MapData.SF_NOBUILD
				if coast:
					terrain_base[i] = MapTerrain.T_DEEP
				else:
					terrain_base[i] = MapTerrain.T_MOUNTAIN if d < 2 else MapTerrain.T_CLIFF
	_report(ST_WATER, _pct("classify", 2, 2))


func _classify_open(cellkey: PackedInt32Array, memo: PackedInt64Array, hsig: PackedInt32Array, u0: int, v0: int, dw: int, s: int,
		base: int, sand_pm: int) -> void:
	var tw: int = t_water
	var tf: int = t_forest
	var trk: int = t_rock
	var ts: int = t_sand
	var s5: int = s + 5
	for i: int in n:
		var key: int = cellkey[i]
		var mv: int = memo[key]
		var h: int = hsig[i]
		var f2: int = (mv >> 8) & 255
		var f3: int = (mv >> 16) & 255
		var t: int = base
		if h <= tw:
			t = MapTerrain.T_DEEP if h <= tw - 10 else MapTerrain.T_SHALLOW
		elif f2 > tf:
			t = MapTerrain.T_FOREST
		elif f3 > trk and f3 <= trk + 40:
			t = MapTerrain.T_ROCK
		elif f2 > tf - 30 and (MapGenNoise.hash2(key % dw + u0, key / dw + v0, s5) & 7) == 0:
			t = MapTerrain.T_DIRT
		elif sand_pm > 0 and ((mv >> 24) & 255) > ts:
			t = MapTerrain.T_SAND
		terrain_base[i] = t


func _classify_urban(cellkey: PackedInt32Array, u0: int, dw: int, s: int) -> void:
	var v0: int = sym.fv_min
	var pitch: int = tables.pitch_base + size / 96
	var pitch3: int = 3 * pitch
	var sw: int = tables.street_w
	var aw: int = tables.avenue_w
	var mid: int = sw + (pitch - sw) / 2
	for i: int in n:
		var key: int = cellkey[i]
		var lu: int = key % dw + u0 + 4096
		var lv: int = key / dw + v0 + 4096
		var mu: int = lu % pitch
		var mvv: int = lv % pitch
		var t: int
		if mu < sw or mvv < sw or lu % pitch3 < aw or lv % pitch3 < aw:
			t = MapTerrain.T_RUBBLE if (MapGenNoise.hash2(lu, lv, s + 13) & 63) == 0 else MapTerrain.T_ROAD
		else:
			var hb: int = MapGenNoise.hash2(lu / pitch, lv / pitch, s + 17)
			var k: int = hb & 7
			if k == 0:
				t = MapTerrain.T_PAVEMENT
			elif k == 1:
				t = MapTerrain.T_GRASS
			else:
				t = MapTerrain.T_URBAN
				if ((hb >> 3) & 3) == 0:
					if ((hb >> 5) & 1) == 0:
						if mu == mid:
							t = MapTerrain.T_PAVEMENT
					elif mvv == mid:
						t = MapTerrain.T_PAVEMENT
		terrain_base[i] = t


## Moat ring around the centre: deep core, shallow banks; a pure function of folded values and the radius.
func _carve_moat(memo: PackedInt64Array, cellkey: PackedInt32Array) -> void:
	var rc: int = (size / 2) * tables.lay("moat_r_pct") / 100
	var deep2: int = tables.lay("moat_deep_half2")
	var bank2: int = tables.lay("moat_bank_half2")
	var lo: int = maxi(0, 2 * (rc - 6) - bank2 - 2)
	var hi: int = 2 * (rc + 6) + bank2 + 2
	var lo2: int = lo * lo
	var hi2: int = hi * hi
	for y: int in size:
		var y2: int = 2 * y + 1 - size
		for x: int in size:
			var x2: int = 2 * x + 1 - size
			var q: int = x2 * x2 + y2 * y2
			if q < lo2 or q > hi2:
				continue
			var i: int = y * size + x
			var f5: int = (memo[cellkey[i]] >> 32) & 255
			var dd: int = absi(Fp.isqrt(q) - 2 * (rc + (((f5 - 128) * 6) >> 7)))
			if dd <= deep2:
				terrain_base[i] = MapTerrain.T_DEEP
			elif dd <= bank2:
				terrain_base[i] = MapTerrain.T_SHALLOW


## Land (GRASS / DIRT) within Chebyshev distance `marsh_reach` of water whose F6 exceeds the threshold becomes MARSH.
func _marsh(memo: PackedInt64Array, cellkey: PackedInt32Array) -> void:
	var water: PackedByteArray = PackedByteArray()
	water.resize(n)
	for i: int in n:
		var t: int = terrain_base[i]
		if t == MapTerrain.T_DEEP or t == MapTerrain.T_SHALLOW or t == MapTerrain.T_FORD:
			water[i] = 1
	var near: PackedByteArray = _dilate(_dilate(water, tables.lay("marsh_reach"), true), tables.lay("marsh_reach"), false)
	var f6_min: int = tables.lay("marsh_f6_min")
	for i: int in n:
		if near[i] == 0:
			continue
		var t: int = terrain_base[i]
		if (t == MapTerrain.T_GRASS or t == MapTerrain.T_DIRT) and ((memo[cellkey[i]] >> 40) & 255) > f6_min:
			terrain_base[i] = MapTerrain.T_MARSH


## One axis of a Chebyshev-r dilation of a 0/1 mask (rows when `horizontal`, else columns), via prefix counts.
func _dilate(mask: PackedByteArray, r: int, horizontal: bool) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(n)
	var pre: PackedInt32Array = PackedInt32Array()
	pre.resize(size + 1)
	var step: int = 1 if horizontal else size
	var lstep: int = size if horizontal else 1
	for line: int in size:
		var o: int = line * lstep
		pre[0] = 0
		for k: int in size:
			pre[k + 1] = pre[k] + mask[o + k * step]
		for k: int in size:
			if pre[mini(size - 1, k + r) + 1] - pre[maxi(0, k - r)] > 0:
				out[o + k * step] = 1
	return out
