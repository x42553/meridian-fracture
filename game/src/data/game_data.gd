class_name GameData
extends RefCounted
## Facade + immutable table holder: every converted, int-only definition table of a process (data_balance 3.1).
## A plain RefCounted (never an autoload); SimWorld receives it by reference. Immutable after DefLoader.build().

const FORMAT_VERSION: int = 1  ## part of data_hash
const BIBLE_PATH: String = "res://data/bible/meridian_factions.json"
const BALANCE_DIR: String = "res://data/balance"  ## contains manifest.json
const NEUTRAL_PLAYER_ROSTER: int = -1  ## use base_roster for pid -1 (neutrals)

## Fixed table order of the data hash (compiler tables follow, sorted by key).
const CORE_TABLES: PackedStringArray = [
	"ids", "global", "weapon_archs", "abilities", "units", "structures", "research", "powers", "superweapons",
	"zones", "neutrals", "factions", "selectors", "modifiers", "rosters",
]

static var last_report: DefLoadReport = null  ## diagnostic only, never read by the sim
static var _cache: GameData = null

# ---- tables (dense, index == position; sorted-id order, data_balance 5.3) ----
var units: Array[DefUnit] = []  ## bible units + balance summons/drones, sorted by id
var structures: Array[DefStructure] = []
var weapon_archs: Array[DefWeaponArch] = []  ## index == frozen WeaponArch
var research: Array[DefResearch] = []
var powers: Array[DefPower] = []
var superweapons: Array[DefSuperweapon] = []
var zones: Array[DefZone] = []
var neutrals: Array[DefNeutral] = []
var factions: Array[DefFaction] = []
var rosters: Array[DefRoster] = []  ## sorted by roster id
var modifiers: Array[DefModifier] = []
var selectors: Array[DefSelector] = []  ## bible + balance extras + inline, named ones sorted by id
var abilities: Array[DefAbility] = []  ## ability templates, sorted by id
var stack_groups: PackedStringArray = PackedStringArray()  ## effect stack-group names, sorted
var economy: DefEconomy = DefEconomy.new()
var damage: DefDamageTable = DefDamageTable.new()
var moves: DefMoveTable = DefMoveTable.new()
var bodies: DefBodyTable = DefBodyTable.new()
var tags: DefTags = DefTags.new()
var ids: DefIds = DefIds.new()
var ext: Dictionary = {}  ## domain compiler outputs: domain_id -> RefCounted
var base_roster: DefRoster = DefRoster.new()  ## all defs, no modifiers; pid -1, tests, Field Manual "raw"
var report: DefLoadReport = DefLoadReport.new()  ## warnings / infos of the successful load
var table_hashes: Dictionary = {}  ## String -> int

var _data_hash: int = 0
var _compilers: Array[DefDomainCompiler] = []
var _sources: DefSources = null
var _file_hashes: Dictionary = {}


## Cached per process. Returns null when any ERROR-level problem exists; `last_report` explains.
static func load_default(force_reload: bool = false) -> GameData:
	if _cache != null and not force_reload:
		return _cache
	var d: GameData = load_from_paths(BIBLE_PATH, BALANCE_DIR)
	_cache = d
	return d


## Uncached (tests, fixtures, hot reload). `compilers` empty = DefCompilers.all().
static func load_from_paths(bible_path: String, balance_dir: String, level: int = DefValidator.LEVEL_FULL, compilers: Array[DefDomainCompiler] = []) -> GameData:
	return load_from_sources(DefSources.from_disk(bible_path, balance_dir), level, compilers)


## Uncached, from parsed dictionaries (negative tests mutate a DefSources.deep_copy() first).
static func load_from_sources(src: DefSources, level: int = DefValidator.LEVEL_FULL, compilers: Array[DefDomainCompiler] = []) -> GameData:
	var comps: Array[DefDomainCompiler] = compilers if not compilers.is_empty() else DefCompilers.all()
	return DefLoader.build(src, level, comps)


# ---- hashes (data_balance 5.11) ----
func data_hash() -> int:
	return _data_hash


## Diagnostic per-file hashes keyed by path relative to res://data/ (bible/..., balance/...). Lazy, from the retained
## sources (empty after drop_sources() unless computed before).
func file_hashes() -> Dictionary:
	if _file_hashes.is_empty() and _sources != null:
		_file_hashes["bible/meridian_factions.json"] = DefHash.hash_json(_sources.bible)
		for f: String in _sources.manifest_files:
			if _sources.balance.has(f):
				_file_hashes["balance/" + f] = DefHash.hash_json(_sources.balance[f])
		for mf: String in _sources.mission_files:
			if _sources.missions.has(mf):
				_file_hashes["missions/" + mf] = DefHash.hash_json(_sources.missions[mf])
	return _file_hashes


## {"format", "hash", "tables"[, "files"]} for the lobby handshake.
func handshake(include_files: bool = false) -> Dictionary:
	var h: Dictionary = {"format": FORMAT_VERSION, "hash": _data_hash, "tables": table_hashes.duplicate()}
	if include_files:
		h["files"] = file_hashes().duplicate()
	return h


## Sorted, deterministic human-readable differences between two handshakes ("format: 1 vs 2", "table units differs",
## "file balance/x.json differs", "file balance/x.json missing on remote").
static func diff_handshake(local: Dictionary, remote: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if local.get("format", 0) != remote.get("format", 0):
		out.append("format: %s vs %s" % [str(local.get("format", 0)), str(remote.get("format", 0))])
	var lt: Dictionary = local.get("tables", {})
	var rt: Dictionary = remote.get("tables", {})
	_diff_maps(out, "table", lt, rt)
	if local.has("files") and remote.has("files"):
		_diff_maps(out, "file", local["files"], remote["files"])
	out.sort()
	return out


static func _diff_maps(out: PackedStringArray, label: String, a: Dictionary, b: Dictionary) -> void:
	for k: Variant in a.keys():
		if not b.has(k):
			out.append("%s %s missing on remote" % [label, str(k)])
		elif a[k] != b[k]:
			out.append("%s %s differs" % [label, str(k)])
	for k: Variant in b.keys():
		if not a.has(k):
			out.append("%s %s missing on local" % [label, str(k)])


## Same id lists per kind => indices equal => values may be swapped (hot reload).
func is_hot_swap_compatible(other: GameData) -> bool:
	return table_hashes.get("ids", 0) == other.table_hashes.get("ids", -1)


## Releases the retained parsed sources after caching file_hashes() once.
func drop_sources() -> void:
	file_hashes()
	_sources = null


# ---- lookup (never error; -1 when unknown) ----
func idx(kind: int, id: String) -> int:
	return ids.index_of(kind, id)


func unit_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.UNIT, id)


func structure_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.STRUCTURE, id)


func weapon_arch_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.WEAPON_ARCH, id)


func research_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.RESEARCH, id)


func power_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.POWER, id)


func superweapon_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.SUPERWEAPON, id)


func zone_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.ZONE, id)


func neutral_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.NEUTRAL, id)


func faction_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.FACTION, id)


## Roster index of a full roster id ("roster.napc.canada"), -1 when unknown.
func roster_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.ROSTER, id)


func roster_ids() -> PackedStringArray:
	return ids.ids(DefEnums.Kind.ROSTER)


func roster_faction(roster_index: int) -> int:
	return rosters[roster_index].faction if roster_index >= 0 and roster_index < rosters.size() else -1


func selector_idx(id: String) -> int:
	return ids.index_of(DefEnums.Kind.SELECTOR, id)


func id_of(kind: int, index: int) -> String:
	return ids.id_of(kind, index)


func count(kind: int) -> int:
	return ids.count(kind)


## The def object of (kind, index) or null (also null for ROSTER / ABILITY, which are not DefBase).
func def_of(kind: int, index: int) -> DefBase:
	var arr: Array = _table_of(kind)
	if index < 0 or index >= arr.size():
		return null
	return arr[index] as DefBase


## ("NAPC", "canada"); sub_key "" = vanilla; null when unknown.
func roster_for(faction_code: String, sub_key: String = "") -> DefRoster:
	var i: int = roster_idx("roster.%s.%s" % [faction_code.to_lower(), sub_key if sub_key != "" else "vanilla"])
	return rosters[i] if i >= 0 else null


func vanilla_roster_of(faction: int) -> DefRoster:
	if faction < 0 or faction >= factions.size():
		return null
	var r: int = factions[faction].vanilla_roster
	return rosters[r] if r >= 0 and r < rosters.size() else null


## Packed (kind << 24) | index for messages that may point at any def.
func ref(kind: int, index: int) -> int:
	return (kind << 24) | index


static func ref_kind(r: int) -> int:
	return r >> 24


static func ref_index(r: int) -> int:
	return r & 0xFFFFFF


func _table_of(kind: int) -> Array:
	match kind:
		DefEnums.Kind.UNIT:
			return units
		DefEnums.Kind.STRUCTURE:
			return structures
		DefEnums.Kind.WEAPON_ARCH:
			return weapon_archs
		DefEnums.Kind.RESEARCH:
			return research
		DefEnums.Kind.POWER:
			return powers
		DefEnums.Kind.SUPERWEAPON:
			return superweapons
		DefEnums.Kind.ZONE:
			return zones
		DefEnums.Kind.NEUTRAL:
			return neutrals
		DefEnums.Kind.FACTION:
			return factions
		DefEnums.Kind.ROSTER:
			return rosters
		DefEnums.Kind.MODIFIER:
			return modifiers
		DefEnums.Kind.SELECTOR:
			return selectors
		DefEnums.Kind.ABILITY:
			return abilities
	return []


## The 15 core table hashes + one per compiler key (data_balance 5.11), computed from the current tables.
static func compute_table_hashes(d: GameData) -> Dictionary:
	var t: Dictionary = {}
	t["ids"] = d.ids.hash_all()
	var g: int = DefHash.hash_def(DefHash.OFFSET, d.economy)
	g = DefHash.hash_def(g, d.damage)
	g = DefHash.hash_def(g, d.moves)
	g = DefHash.hash_def(g, d.bodies)
	g = DefHash.mix_int(g, d.tags.hash_all())
	t["global"] = g
	t["weapon_archs"] = _hash_array(d.weapon_archs)
	t["abilities"] = _hash_array(d.abilities)
	t["units"] = _hash_array(d.units)
	t["structures"] = _hash_array(d.structures)
	t["research"] = _hash_array(d.research)
	t["powers"] = _hash_array(d.powers)
	t["superweapons"] = _hash_array(d.superweapons)
	t["zones"] = _hash_array(d.zones)
	t["neutrals"] = _hash_array(d.neutrals)
	t["factions"] = _hash_array(d.factions)
	t["selectors"] = _hash_array(d.selectors)
	t["modifiers"] = _hash_array(d.modifiers)
	var rh: int = DefHash.OFFSET
	for r: DefRoster in d.rosters:
		rh = r.hash_into(rh)
	rh = DefHash.mix_variant(rh, d.stack_groups)
	t["rosters"] = rh
	var extra: Dictionary = {}
	for c: DefDomainCompiler in d._compilers:
		var th: Dictionary = c.table_hashes(d)
		for k: Variant in th.keys():
			extra[str(k)] = th[k]
	var keys: Array = extra.keys()
	keys.sort()
	for k: String in keys:
		t[k] = extra[k]
	return t


## data_hash = FNV over FORMAT_VERSION and (key, table hash) in fixed order: core tables, then compiler keys sorted.
static func compute_data_hash(tables: Dictionary) -> int:
	var h: int = DefHash.mix_int(DefHash.OFFSET, FORMAT_VERSION)
	for k: String in CORE_TABLES:
		h = DefHash.mix_int(DefHash.mix_str(h, k), tables.get(k, 0))
	var extra: Array = []
	for k: Variant in tables.keys():
		if not CORE_TABLES.has(str(k)):
			extra.append(str(k))
	extra.sort()
	for k: String in extra:
		h = DefHash.mix_int(DefHash.mix_str(h, k), tables[k])
	return h


static func _hash_array(arr: Array) -> int:
	var h: int = DefHash.OFFSET
	for d: Variant in arr:
		h = DefHash.hash_def(h, d as Object)
	return h


## Recomputes table_hashes and data_hash from the current tables (end of DefLoader.build, hot reload).
func finalize_hashes() -> void:
	table_hashes = compute_table_hashes(self)
	_data_hash = compute_data_hash(table_hashes)
