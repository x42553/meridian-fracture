class_name MapGenTables
extends RefCounted
## Parsed `data/balance/map_gen.json` (terrain_movement 7.4): generator constants, family parameters, deposit classes,
## field / neutral catalogue rules, biome table, progress ranges. Immutable after load; `table_hash()` (over the
## converted ints and strings) enters the data hash (DR-10). Any change to a value changes generator output and
## requires a gen_version bump (the loader rejects gen_version != MapGenParams.VERSION).

const PATH: String = "res://data/balance/map_gen.json"
const SCHEMA: int = 1  ## legacy integer form, still accepted
const SCHEMA_KEY: String = "meridian.balance.map_gen/1"
const FAMILY_KEYS: PackedStringArray = ["open", "urban", "coast"]
const _LAYOUT_KEYS: PackedStringArray = [
	"rim_w", "start_r", "start_r_step", "gate_w", "gate_w_step", "route_amp2", "moat_r_pct", "moat_deep_half2",
	"moat_bank_half2", "marsh_reach", "marsh_f6_min", "exit_ring_r", "min_buildable_start", "start_buildable_r",
	"max_attempts", "field_clear_r", "field_edge_margin", "field_spacing", "neutral_edge_margin",
	"neutral_start_dist", "neutral_field_dist"]
const _TERRAIN_KEYS: Dictionary = {"grass": MapTerrain.T_GRASS, "dirt": MapTerrain.T_DIRT, "sand": MapTerrain.T_SAND}
const _NEUTRAL_ORDER: PackedStringArray = [
	"neutral.civilian_garrison", "neutral.substation", "neutral.salvage_depot", "neutral.field_hospital",
	"neutral.observation_tower", "neutral.harbor_terminal"]

static var _default: MapGenTables = null

var gen_version: int = 0
var layout: Dictionary = {}  ## key -> int, keys of _LAYOUT_KEYS
var bay_pocket_w: int = 9
var bay_pocket_h: int = 7
var bay_near_edge: int = 6
var canal_deep: int = 7
var canal_bank: int = 2
## by family index (0 open, 1 urban, 2 coast)
var _fam_water: PackedInt32Array = PackedInt32Array()
var _fam_density: PackedInt32Array = PackedInt32Array()
var _fam_terraces: PackedInt32Array = PackedInt32Array()
var _fam_route: PackedInt32Array = PackedInt32Array()
var _fam_moat: PackedInt32Array = PackedInt32Array()
var _fam_marsh: PackedInt32Array = PackedInt32Array()
var street_w: int = 4
var avenue_w: int = 6
var pitch_base: int = 16
var deposit: Dictionary = {}  ## "standard" / "rich" -> {cells, per_cell, klass} (ints); "budget_min" -> int
var fields: Array = []  ## raw parsed rows of the "fields" list (read-only: strings and numbers as parsed)
var neutrals: Array = []  ## rows {id: String, count: {open,urban,coast: String}, anchor: String, ring: [lo, hi], shore: bool}
var biome_base: PackedInt32Array = PackedInt32Array()  ## terrain type of the base ground by biome 0..2
var biome_sand_pm: PackedInt32Array = PackedInt32Array()
var progress: Dictionary = {}  ## stage name -> [lo, hi]
var _hash: int = 0
var _hcount: int = 0


## Cached singleton from res://data/balance/map_gen.json; null (+push_error) on failure.
static func load_default() -> MapGenTables:
	if _default != null:
		return _default
	if not FileAccess.file_exists(PATH):
		push_error("MapGenTables.load_default: missing " + PATH)
		return null
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (d is Dictionary):
		push_error("MapGenTables.load_default: " + PATH + " is not a JSON object")
		return null
	_default = from_dict(d as Dictionary)
	return _default


## Parses and validates; push_error + null on the first schema problem (see `error_of`).
static func from_dict(d: Dictionary) -> MapGenTables:
	var t: MapGenTables = MapGenTables.new()
	var e: String = t._parse(d)
	if e != "":
		push_error("MapGenTables: " + e)
		return null
	return t


## Schema check without push_error: "" = valid.
static func error_of(d: Dictionary) -> String:
	return MapGenTables.new()._parse(d)


func fam_water_pct(fam: int) -> int:
	return _fam_water[fam]


func fam_density(fam: int) -> int:
	return _fam_density[fam]


func fam_terraces(fam: int) -> bool:
	return _fam_terraces[fam] != 0


func fam_min_route_pct(fam: int) -> int:
	return _fam_route[fam]


func fam_moat(fam: int) -> bool:
	return _fam_moat[fam] != 0


func fam_marsh(fam: int) -> bool:
	return _fam_marsh[fam] != 0


## Integer layout constant by key (see map_gen.json "layout"); 0 for an unknown key.
func lay(key: String) -> int:
	return layout.get(key, 0) as int


## Value of a neutral count expression over `size` ("2", "6+size/64", "0"); "map1" evaluates to 1 (one per map, see
## `count_is_per_map`). Left-to-right over + and /, integer division.
static func eval_count(expr: String, size: int) -> int:
	if expr == "map1":
		return 1
	var total: int = 0
	for term: String in expr.split("+"):
		var v: int = 0
		var parts: PackedStringArray = term.split("/")
		v = size if parts[0].strip_edges() == "size" else parts[0].strip_edges().to_int()
		for k: int in range(1, parts.size()):
			var dv: int = parts[k].strip_edges().to_int()
			v = v / dv if dv != 0 else 0
		total += v
	return total


## Row of `neutrals` for a catalogue id ("neutral.substation"), -1 if unknown. Rows are in FILE order, which is NOT
## the MapData.neutral_ids order (kind index = _NEUTRAL_ORDER.find(id)).
func neutral_row_of(id: String) -> int:
	for i: int in neutrals.size():
		if (neutrals[i] as Dictionary)["id"] == id:
			return i
	return -1


## Kind index (MapData.neutral_ids / terrain_movement 4.3 order) of a catalogue id, -1 if unknown.
static func neutral_kind_of(id: String) -> int:
	return _NEUTRAL_ORDER.find(id)


## Count of neutral row `row` (index in `neutrals`, same order as MapData.neutral_ids) for a family and size.
func neutral_count(row: int, fam: int, size: int) -> int:
	var c: Dictionary = (neutrals[row] as Dictionary)["count"] as Dictionary
	return eval_count(c[FAMILY_KEYS[fam]] as String, size)


func neutral_is_per_map(row: int, fam: int) -> bool:
	var c: Dictionary = (neutrals[row] as Dictionary)["count"] as Dictionary
	return (c[FAMILY_KEYS[fam]] as String) == "map1"


## u32 over every converted int / string of the file in a fixed order.
func table_hash() -> int:
	return Checksum.finalize(_hash)


# ---- parsing --------------------------------------------------------------------------------------------------

func _h(v: int) -> void:
	_hash = Checksum.mix(_hash if _hcount > 0 else Checksum.FNV_OFFSET, v)
	_hcount += 1


func _hs(s: String) -> void:
	_h(Checksum.fnv_string(s))


static func _is_int(v: Variant) -> bool:
	var ty: int = typeof(v)
	if ty == TYPE_INT:
		return true
	return ty == TYPE_FLOAT and roundi(v as float) == v  # lint-allow: L003 load-time JSON number check (DR-10)


static func _to_i(v: Variant) -> int:
	return v as int if typeof(v) == TYPE_INT else roundi(v as float)  # lint-allow: L003 load-time JSON number entry point (DR-10)


## Reads an int field of `d` (records it in the hash); returns false when missing or not an integer.
func _gi(d: Dictionary, key: String, out: PackedInt32Array) -> bool:
	if not d.has(key) or not _is_int(d[key]):
		return false
	var v: int = _to_i(d[key])
	_hs(key)
	_h(v)
	out.append(v)
	return true


func _parse(d: Dictionary) -> String:
	var tmp: PackedInt32Array = PackedInt32Array()
	var sch: Variant = d.get("schema")
	if not ((_is_int(sch) and _to_i(sch) == SCHEMA) or (sch is String and sch == SCHEMA_KEY)):
		return "schema must be '%s'" % SCHEMA_KEY
	if not _gi(d, "gen_version", tmp):
		return "gen_version missing"
	gen_version = tmp[0]
	if gen_version != MapGenParams.VERSION:
		return "gen_version %d != MapGenParams.VERSION %d" % [gen_version, MapGenParams.VERSION]
	# layout
	if not (d.get("layout") is Dictionary):
		return "layout missing"
	var lay_d: Dictionary = d["layout"] as Dictionary
	for k: String in _LAYOUT_KEYS:
		tmp.clear()
		if not _gi(lay_d, k, tmp):
			return "layout.%s missing or not an integer" % k
		layout[k] = tmp[0]
	if lay("rim_w") != MapData.RIM_W:
		return "layout.rim_w must equal MapData.RIM_W (%d)" % MapData.RIM_W
	# bay
	if not (d.get("bay") is Dictionary):
		return "bay missing"
	var bay: Dictionary = d["bay"] as Dictionary
	var pc: Variant = bay.get("pocket_cells")
	if not (pc is Array) or (pc as Array).size() != 2 or not _is_int((pc as Array)[0]) or not _is_int((pc as Array)[1]):
		return "bay.pocket_cells must be [w, h]"
	bay_pocket_w = _to_i((pc as Array)[0])
	bay_pocket_h = _to_i((pc as Array)[1])
	_h(bay_pocket_w)
	_h(bay_pocket_h)
	for k: String in ["near_edge_cells", "canal_deep", "canal_bank"]:
		tmp.clear()
		if not _gi(bay, k, tmp):
			return "bay.%s missing or not an integer" % k
	bay_near_edge = _to_i(bay["near_edge_cells"])
	canal_deep = _to_i(bay["canal_deep"])
	canal_bank = _to_i(bay["canal_bank"])
	# families
	if not (d.get("families") is Dictionary):
		return "families missing"
	var fams: Dictionary = d["families"] as Dictionary
	for fk: String in FAMILY_KEYS:
		if not (fams.get(fk) is Dictionary):
			return "families.%s missing" % fk
		var f: Dictionary = fams[fk] as Dictionary
		_hs(fk)
		tmp.clear()
		for k: String in ["water_pct", "density", "min_route_pct"]:
			if not _gi(f, k, tmp):
				return "families.%s.%s missing or not an integer" % [fk, k]
		_fam_water.append(tmp[0])
		_fam_density.append(tmp[1])
		_fam_route.append(tmp[2])
		_fam_terraces.append(1 if f.get("terraces", false) == true else 0)
		_fam_moat.append(1 if f.get("moat", false) == true else 0)
		_fam_marsh.append(1 if f.get("marsh", false) == true else 0)
		_h(_fam_terraces[_fam_terraces.size() - 1])
		_h(_fam_moat[_fam_moat.size() - 1])
		_h(_fam_marsh[_fam_marsh.size() - 1])
		if tmp[0] < 0 or tmp[0] > 40 or tmp[1] < 0 or tmp[1] > 100:
			return "families.%s water_pct/density out of range" % fk
	var urb: Dictionary = fams["urban"] as Dictionary
	for k: String in ["street_w", "avenue_w", "pitch_base"]:
		tmp.clear()
		if not _gi(urb, k, tmp):
			return "families.urban.%s missing or not an integer" % k
	street_w = _to_i(urb["street_w"])
	avenue_w = _to_i(urb["avenue_w"])
	pitch_base = _to_i(urb["pitch_base"])
	if street_w < 1 or avenue_w < street_w or pitch_base < avenue_w + 4:
		return "families.urban street_w/avenue_w/pitch_base inconsistent"
	# deposit
	if not (d.get("deposit") is Dictionary):
		return "deposit missing"
	var dep: Dictionary = d["deposit"] as Dictionary
	for cls: String in ["standard", "rich"]:
		if not (dep.get(cls) is Dictionary):
			return "deposit.%s missing" % cls
		var row: Dictionary = {}
		var cd: Dictionary = dep[cls] as Dictionary
		_hs(cls)
		for k: String in ["cells", "per_cell", "klass"]:
			tmp.clear()
			if not _gi(cd, k, tmp):
				return "deposit.%s.%s missing or not an integer" % [cls, k]
			row[k] = tmp[0]
		deposit[cls] = row
	tmp.clear()
	if not _gi(dep, "budget_min", tmp):
		return "deposit.budget_min missing"
	deposit["budget_min"] = tmp[0]
	# fields (kept as parsed, hashed by canonical text)
	if not (d.get("fields") is Array) or (d["fields"] as Array).size() != 5:
		return "fields must list 5 rows"
	fields = (d["fields"] as Array).duplicate(true)
	for row_v: Variant in fields:
		if not (row_v is Dictionary):
			return "fields rows must be objects"
		_hs(JSON.stringify(row_v, "", true))
	# neutrals: every catalogue id exactly once (rows keep the file order; see neutral_row_of)
	if not (d.get("neutrals") is Array) or (d["neutrals"] as Array).size() != _NEUTRAL_ORDER.size():
		return "neutrals must list %d rows" % _NEUTRAL_ORDER.size()
	neutrals = (d["neutrals"] as Array).duplicate(true)
	var seen: Dictionary = {}
	for i: int in neutrals.size():
		var nr: Variant = neutrals[i]
		if not (nr is Dictionary) or not _NEUTRAL_ORDER.has(str((nr as Dictionary).get("id", ""))) \
				or seen.has((nr as Dictionary)["id"]):
			return "neutrals[%d].id must be a distinct catalogue id" % i
		seen[(nr as Dictionary)["id"]] = true
		if not ((nr as Dictionary).get("count") is Dictionary):
			return "neutrals[%d].count missing" % i
		for fk: String in FAMILY_KEYS:
			if not (((nr as Dictionary)["count"] as Dictionary).get(fk) is String):
				return "neutrals[%d].count.%s must be a string" % [i, fk]
		_hs(JSON.stringify(nr, "", true))
	# biomes
	if not (d.get("biomes") is Array) or (d["biomes"] as Array).size() != 3:
		return "biomes must list 3 rows"
	for b_v: Variant in d["biomes"] as Array:
		if not (b_v is Dictionary) or not _TERRAIN_KEYS.has((b_v as Dictionary).get("base")):
			return "biomes[].base must be grass, dirt or sand"
		var b: Dictionary = b_v as Dictionary
		tmp.clear()
		if not _gi(b, "sand_permille", tmp):
			return "biomes[].sand_permille missing"
		_hs(b["base"] as String)
		biome_base.append(_TERRAIN_KEYS[b["base"]] as int)
		biome_sand_pm.append(tmp[0])
	# progress
	if not (d.get("progress") is Dictionary):
		return "progress missing"
	for k: String in ["height", "classify", "layout", "finalize", "validate"]:
		var pr: Variant = (d["progress"] as Dictionary).get(k)
		if not (pr is Array) or (pr as Array).size() != 2 or not _is_int((pr as Array)[0]) or not _is_int((pr as Array)[1]):
			return "progress.%s must be [lo, hi]" % k
		progress[k] = [_to_i((pr as Array)[0]), _to_i((pr as Array)[1])]
		_hs(k)
		_h(_to_i((pr as Array)[0]))
		_h(_to_i((pr as Array)[1]))
	return ""
