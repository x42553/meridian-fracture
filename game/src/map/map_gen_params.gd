class_name MapGenParams
extends RefCounted
## Generator parameters (terrain_movement 3.7 / 5.12.1): read from the lobby's `config.map` dictionary, defaults,
## validation and the canonical integer serialisation (params hash / replay header). Integer only.

const VERSION: int = 2  ## generator algorithm version: bump on ANY output-affecting change (must equal map_gen.json gen_version)
const FAM_OPEN: int = 0
const FAM_URBAN: int = 1
const FAM_COAST: int = 2  ## == net.md 7.1 `map.family`
const SIZE_MIN: int = 96
const SIZE_MAX: int = 256
const SEED_MAX: int = 0xFFFFFFFF

var size: int = 128
var family: int = 0
var seed_value: int = 1  ## net `map.seed` (0..2^32-1)
var slots: int = 2  ## net `map.layout_players`: 2, 3, 4, 6, 8
var water_pct: int = -1  ## 0..40, -1 = family default (open 0, urban 0, coast 22)
## 0..100 clutter. DEVIATION: default -1 = family default (open 50, urban 50, coast 40 per map_gen.json), because the spec
## lists "50 (coast 40)" but a plain default of 50 could not express the coast default.
var density: int = -1
var resources: int = 50  ## 0..100; credit scale = (50 + resources) %
var neutrals: int = 50  ## 0..100
var biome: int = 0  ## 0 temperate, 1 arid, 2 arctic (the urban family forces MapData.biome = 3)
var start_near_water: bool = false  ## coast only


## Reads family, size, seed, layout_players and params{water_pct, density, resources, neutrals, biome,
## start_near_water}. Unknown keys are ignored; missing keys keep the defaults; numbers may arrive as int or float
## (JSON). Size defaults to recommended_size(slots) when absent.
static func from_config(map_cfg: Dictionary) -> MapGenParams:
	var p: MapGenParams = MapGenParams.new()
	p.family = _int(map_cfg.get("family", 0), 0)
	p.seed_value = _int(map_cfg.get("seed", 1), 1)
	p.slots = _int(map_cfg.get("layout_players", 2), 2)
	p.size = _int(map_cfg.get("size", recommended_size(p.slots)), recommended_size(p.slots))
	var pr_v: Variant = map_cfg.get("params", {})
	if pr_v is Dictionary:
		var pr: Dictionary = pr_v as Dictionary
		p.water_pct = _int(pr.get("water_pct", -1), -1)
		p.density = _int(pr.get("density", -1), -1)
		p.resources = _int(pr.get("resources", 50), 50)
		p.neutrals = _int(pr.get("neutrals", 50), 50)
		p.biome = _int(pr.get("biome", 0), 0)
		var snw: Variant = pr.get("start_near_water", false)
		p.start_near_water = (snw as bool) if snw is bool else _int(snw, 0) != 0
	return p


static func _int(v: Variant, dflt: int) -> int:
	var t: int = typeof(v)
	if t == TYPE_INT:
		return v as int
	if t == TYPE_FLOAT:
		return roundi(v as float)  # lint-allow: L003 load-time JSON number entry point (DR-10), value is an integer in the file
	return dflt


static func min_size(p_slots: int) -> int:
	match p_slots:
		2:
			return 96
		3:
			return 112
		4:
			return 128
		6:
			return 160
		8:
			return 192
	return 0


static func recommended_size(players: int) -> int:
	if players <= 2:
		return 128
	if players == 3:
		return 144
	if players == 4:
		return 160
	if players <= 6:
		return 192
	return 224


## Smallest of {2,3,4,6,8} >= players.
static func slots_for(players: int) -> int:
	if players <= 2:
		return 2
	if players == 3:
		return 3
	if players == 4:
		return 4
	if players <= 6:
		return 6
	return 8


## Lobby-level check of the three values net.md XR-12 knows: "" = ok. (MapGenerator.validate_params delegates here.)
static func validate_basic(p_family: int, p_size: int, p_slots: int) -> String:
	if p_family < 0 or p_family > 2:
		return "family must be 0 (open), 1 (urban) or 2 (coast)"
	if p_slots != 2 and p_slots != 3 and p_slots != 4 and p_slots != 6 and p_slots != 8:
		return "layout_players must be one of 2, 3, 4, 6, 8"
	if p_size % 8 != 0:
		return "size must be a multiple of 8"
	if p_size > SIZE_MAX:
		return "size must be at most %d" % SIZE_MAX
	var lo: int = maxi(SIZE_MIN, min_size(p_slots))
	if p_size < lo:
		return "size must be at least %d for %d slots" % [lo, p_slots]
	return ""


## "" if OK (size multiple of 8 in [max(96, min_size(slots)), 256], family 0..2, slots in {2,3,4,6,8}, ranges).
func validate() -> String:
	var e: String = validate_basic(family, size, slots)
	if e != "":
		return e
	if seed_value < 0 or seed_value > SEED_MAX:
		return "seed must be in 0..4294967295"
	if water_pct < -1 or water_pct > 40:
		return "water_pct must be -1 or 0..40"
	if density < -1 or density > 100:
		return "density must be -1 or 0..100"
	if resources < 0 or resources > 100:
		return "resources must be 0..100"
	if neutrals < 0 or neutrals > 100:
		return "neutrals must be 0..100"
	if biome < 0 or biome > 2:
		return "biome must be 0..2"
	return ""


## Family-resolved values (tables carry the family defaults).
func effective_water_pct(tables: MapGenTables) -> int:
	return water_pct if water_pct >= 0 else tables.fam_water_pct(family)


func effective_density(tables: MapGenTables) -> int:
	return density if density >= 0 else tables.fam_density(family)


## Canonical serialisation: [VERSION, size, family, seed_value, slots, water_pct, density, resources, neutrals, biome,
## start_near_water]. Stored in MapData.gen_params; only known keys enter it.
func to_ints() -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	a.append(VERSION)
	a.append(size)
	a.append(family)
	a.append(((seed_value + 0x80000000) & 0xFFFFFFFF) - 0x80000000)  # low 32 bits as a signed int32
	a.append(slots)
	a.append(water_pct)
	a.append(density)
	a.append(resources)
	a.append(neutrals)
	a.append(biome)
	a.append(1 if start_near_water else 0)
	return a
