class_name MapTerrain
extends RefCounted
## Terrain tables (terrain_movement 3.2 / 4.2 / 5.1 / 7.1): the 16 terrain types, their TerrainKind, flags,
## and every table DERIVED from the movement speed table (speed, path weight, step costs, land guarantee).
## Immutable after `from_dict`; held by GameData / MapData (`tt`). Speeds are never authored in terrain.json.

# ---- terrain types (byte values stored in MapData.terrain), 16 ----
const T_DEEP: int = 0
const T_SHALLOW: int = 1
const T_FORD: int = 2
const T_BEACH: int = 3
const T_GRASS: int = 4
const T_DIRT: int = 5
const T_SAND: int = 6
const T_ROCK: int = 7
const T_FOREST: int = 8
const T_ROAD: int = 9
const T_PAVEMENT: int = 10
const T_RUBBLE: int = 11
const T_URBAN: int = 12
const T_CLIFF: int = 13
const T_MOUNTAIN: int = 14
const T_MARSH: int = 15
const COUNT: int = 16
# ---- TerrainKind (mirror of DefEnums.TerrainKind; equality asserted at load) ----
const TK_ROAD: int = 0
const TK_OPEN: int = 1
const TK_ROUGH: int = 2
const TK_FOREST: int = 3
const TK_MARSH: int = 4
const TK_SHALLOW: int = 5
const TK_DEEP: int = 6
const TK_CLIFF: int = 7
const TK_COUNT: int = 8
# ---- MoveClass (mirror of DefEnums.MoveClass; equality asserted at load) ----
const MC_FOOT: int = 0
const MC_WHEELED: int = 1
const MC_TRACKED: int = 2
const MC_AMPHIBIOUS: int = 3
const MC_NAVAL: int = 4
const MC_SUBMERGED: int = 5
const MC_AIR_FIXED: int = 6
const MC_AIR_HOVER: int = 7
const MC_STATIC: int = 8
const MC_COUNT: int = 9
# ---- nav profiles (a profile = a class with its own weight vector; air and static have none) ----
const NP_FOOT: int = 0
const NP_WHEELED: int = 1
const NP_TRACKED: int = 2
const NP_AMPH: int = 3
const NP_NAVAL: int = 4
const NP_NAVAL_DEEP: int = 5
const NP_SUB: int = 6
const NP_COUNT: int = 7
const NP_NONE: int = -1
const SZ_1: int = 1
const SZ_2: int = 2
const SZ_3: int = 3
const DEEP_ONLY_RADIUS: int = 922  ## units (0.9 cell): naval hulls with radius >= this are deep-water only (TAXONOMY 6)
const LARGE_HULL_RADIUS: int = 1100  ## units: naval hulls above this need 5-wide channels (SZ_3)
# ---- terrain flag bits (terrain.json "flags") ----
const TF_WATER: int = 1  ## kind SHALLOW or DEEP: is_water(), F_ON_WATER, water_mult_bp applies
const TF_LAND: int = 2
const TF_BUILD: int = 4  ## standard structures may stand here
const TF_BUILD_SHORE: int = 8  ## only shoreline structures (Dock) may stand here (beach)
const TF_CROSSING: int = 16  ## intended ground crossing (ford): part of the land-only guarantee although kind is SHALLOW

const SCHEMA: int = 1  ## legacy integer form, still accepted
const SCHEMA_KEY: String = "meridian.balance.terrain/1"
const TERRAIN_JSON: String = "res://data/balance/terrain.json"
const GLOBAL_JSON: String = "res://data/balance/global.json"
const STEP_MAX_W: int = 40  ## step tables are indexed by weight 0..40
const _FLAG_NAMES: PackedStringArray = ["water", "land", "build", "build_shore", "crossing"]
const _FLAG_BITS: PackedInt32Array = [TF_WATER, TF_LAND, TF_BUILD, TF_BUILD_SHORE, TF_CROSSING]
const _BUILDABLE_NAMES: PackedStringArray = ["none", "std", "shore"]

static var _default: MapTerrain = null

## Type keys ("deep_water", ...), index = terrain type.
var keys: PackedStringArray = PackedStringArray()
var weight_scale: int = 1600
var weight_min: int = 10
var weight_max: int = 40

var _kind: PackedByteArray = PackedByteArray()
var _flags: PackedInt32Array = PackedInt32Array()
var _minimap: PackedInt32Array = PackedInt32Array()
var _speed: PackedInt32Array = PackedInt32Array()  ## [mc * 8 + kind], copy of DefMoveTable.speed_bp
var _weight: PackedByteArray = PackedByteArray()  ## [np * 16 + type]
var _step_o: PackedByteArray = PackedByteArray()
var _step_d: PackedByteArray = PackedByteArray()
var _guar: PackedByteArray = PackedByteArray()


# ---- construction ---------------------------------------------------------------------------------------------

## Parses terrain.json and derives every table from `moves.speed_bp` ([move_class * 8 + terrain_kind], bp, 0 =
## impassable). push_error + null on any schema error (one error per call, the first problem found).
static func from_dict(d: Dictionary, moves: DefMoveTable) -> MapTerrain:
	if moves == null:
		push_error("MapTerrain.from_dict: moves is null")
		return null
	return _build(d, moves.speed_bp)


## Cached singleton built from res://data/balance/terrain.json and the movement table of global.json
## (`movement_classes[*].terrain_speed_pct * 100`, the DefMoveTable source). null (+push_error) on failure.
static func load_default() -> MapTerrain:
	if _default != null:
		return _default
	var td: Variant = _read_json(TERRAIN_JSON)
	var gd: Variant = _read_json(GLOBAL_JSON)
	if not (td is Dictionary) or not (gd is Dictionary):
		push_error("MapTerrain.load_default: cannot read terrain.json / global.json")
		return null
	var rep: DefLoadReport = DefLoadReport.new()
	var moves: DefMoveTable = DefMoveTable.from_global(gd as Dictionary, rep)
	if not rep.is_ok():
		push_error("MapTerrain.load_default: global.json movement table invalid: " + rep.text(5))
		return null
	_default = _build(td as Dictionary, moves.speed_bp)
	return _default


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _is_int(v: Variant) -> bool:
	var t: int = typeof(v)
	if t == TYPE_INT:
		return true
	return t == TYPE_FLOAT and int(v) == v


static func _err(msg: String) -> MapTerrain:
	push_error("MapTerrain: " + msg)
	return null


static func _build(d: Dictionary, speeds: PackedInt32Array) -> MapTerrain:
	if not _mirrors_ok():
		return null
	if speeds.size() != MC_COUNT * TK_COUNT:
		return _err("speed_bp must have %d entries, has %d" % [MC_COUNT * TK_COUNT, speeds.size()])
	for v: int in speeds:
		if v < 0 or v > 100000:
			return _err("speed_bp value out of range: %d" % v)
	var sch: Variant = d.get("schema")
	if not ((_is_int(sch) and int(sch) == SCHEMA) or (sch is String and sch == SCHEMA_KEY)):
		return _err("schema must be '%s'" % SCHEMA_KEY)
	var wd: Variant = d.get("weight")
	if not (wd is Dictionary):
		return _err("missing 'weight' object")
	var t: MapTerrain = MapTerrain.new()
	for f: String in ["scale", "min", "max"]:
		if not _is_int((wd as Dictionary).get(f)):
			return _err("weight.%s must be an integer" % f)
	t.weight_scale = int((wd as Dictionary)["scale"])
	t.weight_min = int((wd as Dictionary)["min"])
	t.weight_max = int((wd as Dictionary)["max"])
	if t.weight_scale < 1 or t.weight_min < 1 or t.weight_min > t.weight_max or t.weight_max > STEP_MAX_W:
		return _err("weight scale/min/max out of range (1 <= min <= max <= %d)" % STEP_MAX_W)
	var types: Variant = d.get("types")
	if not (types is Array) or (types as Array).size() != COUNT:
		return _err("'types' must be an array of exactly %d entries" % COUNT)
	t._kind.resize(COUNT)
	t._flags.resize(COUNT)
	t._minimap.resize(COUNT)
	t.keys.resize(COUNT)
	for i: int in COUNT:
		var msg: String = t._parse_type(i, (types as Array)[i])
		if msg != "":
			return _err("types[%d]: %s" % [i, msg])
	t._speed = speeds.duplicate()
	t._derive()
	return t


## Asserts the mirrored enums against DefEnums (TAXONOMY 11). false + push_error on a mismatch.
static func _mirrors_ok() -> bool:
	var tk: PackedInt32Array = [DefEnums.TerrainKind.ROAD, DefEnums.TerrainKind.OPEN, DefEnums.TerrainKind.ROUGH,
		DefEnums.TerrainKind.FOREST, DefEnums.TerrainKind.MARSH, DefEnums.TerrainKind.SHALLOW,
		DefEnums.TerrainKind.DEEP, DefEnums.TerrainKind.CLIFF, DefEnums.TerrainKind.COUNT]
	var mine_tk: PackedInt32Array = [TK_ROAD, TK_OPEN, TK_ROUGH, TK_FOREST, TK_MARSH, TK_SHALLOW, TK_DEEP, TK_CLIFF, TK_COUNT]
	var mc: PackedInt32Array = [DefEnums.MoveClass.FOOT, DefEnums.MoveClass.WHEELED, DefEnums.MoveClass.TRACKED,
		DefEnums.MoveClass.AMPHIBIOUS, DefEnums.MoveClass.NAVAL, DefEnums.MoveClass.SUBMERGED,
		DefEnums.MoveClass.AIR_FIXED, DefEnums.MoveClass.AIR_HOVER, DefEnums.MoveClass.STATIC, DefEnums.MoveClass.COUNT]
	var mine_mc: PackedInt32Array = [MC_FOOT, MC_WHEELED, MC_TRACKED, MC_AMPHIBIOUS, MC_NAVAL, MC_SUBMERGED,
		MC_AIR_FIXED, MC_AIR_HOVER, MC_STATIC, MC_COUNT]
	if tk != mine_tk or mc != mine_mc:
		push_error("MapTerrain: TK_* / MC_* mirror constants differ from DefEnums.TerrainKind / MoveClass")
		return false
	return true


## Returns "" or the first problem of type entry `i`; fills kind / flags / minimap / key.
func _parse_type(i: int, e: Variant) -> String:
	if not (e is Dictionary):
		return "not an object"
	var o: Dictionary = e
	if not _is_int(o.get("id")) or int(o["id"]) != i:
		return "id must be %d (ids 0..15 in order)" % i
	var key: Variant = o.get("key")
	if not (key is String) or (key as String).is_empty():
		return "missing key"
	if keys.has(key as String):
		return "duplicate key '%s'" % key
	keys[i] = key as String
	var kn: Variant = o.get("kind")
	var kind: int = DefEnums.TERRAIN_NAMES.find(kn as String) if kn is String else -1
	if kind < 0:
		return "unknown kind '%s'" % str(kn)
	_kind[i] = kind
	var fl: int = 0
	var fa: Variant = o.get("flags")
	if not (fa is Array):
		return "flags must be an array"
	for f: Variant in (fa as Array):
		var bi: int = _FLAG_NAMES.find(f as String) if f is String else -1
		if bi < 0:
			return "unknown flag '%s'" % str(f)
		fl |= _FLAG_BITS[bi]
	var bn: Variant = o.get("buildable")
	var bidx: int = _BUILDABLE_NAMES.find(bn as String) if bn is String else -1
	if bidx < 0:
		return "buildable must be one of none/std/shore"
	var want: int = 0
	if bidx == 1:
		want = TF_BUILD
	elif bidx == 2:
		want = TF_BUILD_SHORE
	if (fl & (TF_BUILD | TF_BUILD_SHORE)) != want:
		return "buildable '%s' contradicts the build/build_shore flags" % bn
	var is_water_kind: bool = kind == TK_SHALLOW or kind == TK_DEEP
	if is_water_kind != ((fl & TF_WATER) != 0):
		return "water flag and water kind must agree"
	if ((fl & TF_WATER) != 0) == ((fl & TF_LAND) != 0):
		return "exactly one of water / land is required"
	if (fl & TF_CROSSING) != 0 and (fl & TF_WATER) == 0:
		return "crossing needs water"
	_flags[i] = fl
	var mm: Variant = o.get("minimap")
	if not (mm is String) or not (mm as String).is_valid_hex_number(false) or (mm as String).length() != 6:
		return "minimap must be a 6-digit hex colour"
	_minimap[i] = ((mm as String).hex_to_int() << 8) | 0xFF
	return ""


func _derive() -> void:
	# step tables: entering a cell of weight w (10 = one baseline cell), orthogonal / diagonal
	_step_o.resize(STEP_MAX_W + 1)
	_step_d.resize(STEP_MAX_W + 1)
	for w: int in STEP_MAX_W + 1:
		_step_o[w] = (10 * w + 8) >> 4
		_step_d[w] = (14 * w + 8) >> 4
	# path weights per (nav profile, terrain type)
	_weight.resize(NP_COUNT * COUNT)
	for np: int in NP_COUNT:
		var mc: int = mc_of_profile(np)
		for t: int in COUNT:
			var p: int = _speed[mc * TK_COUNT + _kind[t]] / 100
			var w: int = 0
			if p > 0:
				w = clampi((weight_scale + p / 2) / p, weight_min, weight_max)
			if np == NP_NAVAL_DEEP and _kind[t] == TK_SHALLOW:
				w = 0
			_weight[np * COUNT + t] = w
	# land-only guarantee set
	_guar.resize(COUNT)
	for t: int in COUNT:
		var ok: bool = (_flags[t] & (TF_LAND | TF_CROSSING)) != 0
		for mc: int in [MC_FOOT, MC_WHEELED, MC_TRACKED]:
			if _speed[mc * TK_COUNT + _kind[t]] <= 0:
				ok = false
		_guar[t] = 1 if ok else 0


# ---- static helpers -------------------------------------------------------------------------------------------

## FOOT->NP_FOOT, WHEELED->NP_WHEELED, TRACKED->NP_TRACKED, AMPHIBIOUS->NP_AMPH, NAVAL->NP_NAVAL_DEEP if
## radius_u >= DEEP_ONLY_RADIUS else NP_NAVAL, SUBMERGED->NP_SUB, everything else NP_NONE.
static func profile_of(move_class: int, radius_u: int) -> int:
	match move_class:
		MC_FOOT:
			return NP_FOOT
		MC_WHEELED:
			return NP_WHEELED
		MC_TRACKED:
			return NP_TRACKED
		MC_AMPHIBIOUS:
			return NP_AMPH
		MC_NAVAL:
			return NP_NAVAL_DEEP if radius_u >= DEEP_ONLY_RADIUS else NP_NAVAL
		MC_SUBMERGED:
			return NP_SUB
	return NP_NONE


## FOOT -> SZ_1; NAVAL / SUBMERGED with radius_u > LARGE_HULL_RADIUS -> SZ_3; every other profile -> SZ_2.
static func nav_size(move_class: int, radius_u: int) -> int:
	if move_class == MC_FOOT:
		return SZ_1
	if (move_class == MC_NAVAL or move_class == MC_SUBMERGED) and radius_u > LARGE_HULL_RADIUS:
		return SZ_3
	return SZ_2


## The reference MoveClass of a nav profile (NP_NAVAL_DEEP -> MC_NAVAL); -1 for an invalid profile.
static func mc_of_profile(np: int) -> int:
	match np:
		NP_FOOT:
			return MC_FOOT
		NP_WHEELED:
			return MC_WHEELED
		NP_TRACKED:
			return MC_TRACKED
		NP_AMPH:
			return MC_AMPHIBIOUS
		NP_NAVAL, NP_NAVAL_DEEP:
			return MC_NAVAL
		NP_SUB:
			return MC_SUBMERGED
	return -1


# ---- queries --------------------------------------------------------------------------------------------------

## Terrain type -> TerrainKind.
func kind_of(t: int) -> int:
	return _kind[t]


func flags(t: int) -> int:
	return _flags[t]


## DefMoveTable.speed_bp[mc * 8 + kind_of(t)]; 0 = impassable, 10000 = nominal.
func speed_bp(mc: int, t: int) -> int:
	return _speed[mc * TK_COUNT + _kind[t]]


## Derived path weight 10..40, 0 = blocked (5.1); NP_NAVAL_DEEP additionally blocks TK_SHALLOW.
func weight(np: int, t: int) -> int:
	return _weight[np * COUNT + t]


## (10 * w + 8) >> 4, table lookup, w in 0..40.
func step_o(w: int) -> int:
	return _step_o[w]


## (14 * w + 8) >> 4.
func step_d(w: int) -> int:
	return _step_d[w]


## Land-only guarantee set (5.12): (TF_LAND or TF_CROSSING) and speed_bp > 0 for foot, wheeled AND tracked.
func guarantee(t: int) -> bool:
	return _guar[t] != 0


## 0xRRGGBBAA (view only).
func minimap_rgba(t: int) -> int:
	return _minimap[t]


## The [np * 16 + type] weight table (shared, never mutate): MapNav's fast path.
func weight_table() -> PackedByteArray:
	return _weight


## The step tables (shared, never mutate), indexed by weight 0..40: MapNav / MapPathSearch fast path.
func step_o_table() -> PackedByteArray:
	return _step_o


func step_d_table() -> PackedByteArray:
	return _step_d


## The per-type TerrainKind table (shared, never mutate).
func kind_table() -> PackedByteArray:
	return _kind


## FNV-1a over all converted tables (DR-10 data hash input). Minimap colours are view-only and excluded.
func table_hash() -> int:
	var h: int = Checksum.FNV_OFFSET
	h = Checksum.mix(h, weight_scale)
	h = Checksum.mix(h, weight_min)
	h = Checksum.mix(h, weight_max)
	h = Checksum.fnv_bytes(_kind, h)
	h = Checksum.mix(h, Checksum.digest32(_flags))
	h = Checksum.mix(h, Checksum.digest32(_speed))
	h = Checksum.fnv_bytes(_weight, h)
	h = Checksum.fnv_bytes(_step_o, h)
	h = Checksum.fnv_bytes(_step_d, h)
	h = Checksum.fnv_bytes(_guar, h)
	for k: String in keys:
		h = Checksum.fnv_string(k, h)
	return h
