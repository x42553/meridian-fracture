class_name AiDataStore
extends RefCounted
## Loads and serves the AI data files in game/data/balance/ai/ (ai.md 2.2 / 7): ai_difficulty.json (4 profiles),
## ai_roles.json, ai_tuning.json, ai_personality.json (32 base vectors) and, when present, the later doctrine files
## (ai_composition, ai_powers, ai_faction_<code>) which are kept raw in `extra`. No directory listing (platform order): the
## file list is explicit. A missing REQUIRED file is an error (`errors`); the AI then runs on defaults (Err.DATA_MISSING).
## Also computes `data_hash` (FNV-1a over the file texts in list order; logged into match results).

const DIR: String = "res://data/balance/ai/"
const REQUIRED: PackedStringArray = ["ai_difficulty.json", "ai_roles.json", "ai_tuning.json", "ai_personality.json"]
const OPTIONAL: PackedStringArray = [
	"ai_composition.json", "ai_powers.json", "ai_faction_napc.json", "ai_faction_nec.json", "ai_faction_olm.json",
	"ai_faction_def.json", "ai_faction_pd.json", "ai_faction_han.json", "ai_faction_ae.json", "ai_faction_sap.json",
]

static var _default: AiDataStore = null

var errors: PackedStringArray = PackedStringArray()
var data_hash: int = 0
var difficulty_rows: Array[AiDifficultyProfile] = []
var roles_cfg: Dictionary = {}
var tuning: Dictionary = {}
var personality: Dictionary = {}  ## {"default": {...}, "rosters": {roster id: row}}
var extra: Dictionary = {}  ## file name -> parsed Dictionary (optional doctrine files)
var _tuning_over: Dictionary = {}


## The shared default store (immutable after load; tests that override create their own with `load_dir`).
static func load_default() -> AiDataStore:
	if _default == null:
		_default = load_dir(DIR)
	return _default


static func load_dir(dir: String = DIR) -> AiDataStore:
	var s: AiDataStore = AiDataStore.new()
	var h: int = 0x811C9DC5
	for f: String in REQUIRED:
		var txt: String = _read(dir + f)
		if txt.is_empty():
			s.errors.append("missing required AI data file %s" % f)
			continue
		h = AiRng.mix32(h ^ AiRng.hash_str(txt))
		var parsed: Variant = JSON.parse_string(txt)
		if not (parsed is Dictionary):
			s.errors.append("%s is not a JSON object" % f)
			continue
		s._ingest(f, parsed as Dictionary)
	for f: String in OPTIONAL:
		var txt2: String = _read(dir + f)
		if txt2.is_empty():
			continue
		h = AiRng.mix32(h ^ AiRng.hash_str(txt2))
		var parsed2: Variant = JSON.parse_string(txt2)
		if parsed2 is Dictionary:
			s.extra[f] = parsed2
		else:
			s.errors.append("%s is not a JSON object" % f)
	s.data_hash = h
	s.errors.append_array(s.validate())
	if not s.errors.is_empty():
		Log.warn("ai", "AI data: %s" % "; ".join(s.errors))
	return s


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _ingest(f: String, d: Dictionary) -> void:
	match f:
		"ai_difficulty.json":
			var rows: Dictionary = d.get("profiles", {})
			for lv: int in AiTypes.LEVEL_IDS.size():
				var key: String = AiTypes.LEVEL_IDS[lv]
				if rows.has(key):
					difficulty_rows.append(AiDifficultyProfile.from_dict(rows[key]))
		"ai_roles.json":
			roles_cfg = d
		"ai_tuning.json":
			tuning = d
		"ai_personality.json":
			personality = d


## Static validation of the loaded data (subset of ai.md 7.7: V6, V8, V10). Returns error strings.
func validate() -> PackedStringArray:
	var e: PackedStringArray = PackedStringArray()
	if difficulty_rows.size() != AiTypes.AI_LEVEL_COUNT:
		e.append("V10: expected %d difficulty rows, found %d" % [AiTypes.AI_LEVEL_COUNT, difficulty_rows.size()])
	for i: int in difficulty_rows.size():
		var p: AiDifficultyProfile = difficulty_rows[i]
		if p.id != i:
			e.append("V10: difficulty row %d has id %d" % [i, p.id])
		if i != AiTypes.Difficulty.BRUTAL and (p.info_omniscient or p.handicap_pct != 100):
			e.append("V10: only Brutal may cheat (row %s)" % p.label)
		if i == AiTypes.Difficulty.BRUTAL and (not p.info_omniscient or p.label_cheats.is_empty()):
			e.append("V10: Brutal must be omniscient and carry its cheat label")
		if p.wu_per_tick <= 0 or p.call_cap_wu < p.wu_per_tick or p.think_period_ticks < 1:
			e.append("V10: bad budget/cadence in row %s" % p.label)
	var rows: Dictionary = personality.get("rosters", {})
	for rid: String in rows:
		var r: Dictionary = rows[rid]
		for fl: Variant in r.get("flags", []):
			if AiTypes.doctrine_bit(str(fl)) < 0:
				e.append("V8: unknown doctrine flag %s in %s" % [str(fl), rid])
		for k: String in ["aggression", "tech", "economy", "harass_pct", "air", "naval", "siege", "infantry"]:
			var v: int = int(r.get(k, 0))
			if v < 0 or v > 100:
				e.append("V6: %s.%s out of range" % [rid, k])
		if int(r.get("defense_pct", 0)) < 0 or int(r.get("defense_pct", 0)) > 40:
			e.append("V6: %s.defense_pct out of range" % rid)
	var ur: Dictionary = roles_cfg.get("unit_roles", {})
	for rn: String in ur:
		if AiTypes.role_bit(rn) < 0:
			e.append("V8: unknown role %s in unit_roles" % rn)
	var rr: Dictionary = roles_cfg.get("roles", {})
	for rn2: String in rr:
		if AiTypes.role_bit(rn2) < 0:
			e.append("V8: unknown role %s in roles" % rn2)
	var uh: Dictionary = roles_cfg.get("unit_handlers", {})
	for uid: String in uh:
		for hn: Variant in uh[uid]:
			if AiTypes.handler_bit(str(hn)) < 0:
				e.append("V8: unknown handler %s for %s" % [str(hn), uid])
	return e


func difficulty(level: int) -> AiDifficultyProfile:
	if level >= 0 and level < difficulty_rows.size():
		return difficulty_rows[level]
	return AiDifficultyProfile.new()  # built-in minimal profile (Err.DATA_MISSING was logged at load)


## Personality row of a roster id ("roster.napc.canada"); the default row merged in for missing keys.
func personality_row(roster_id: String) -> Dictionary:
	var base: Dictionary = (personality.get("default", {}) as Dictionary).duplicate()
	var rows: Dictionary = personality.get("rosters", {})
	if rows.has(roster_id):
		base.merge(rows[roster_id], true)
	return base


func has_personality(roster_id: String) -> bool:
	return (personality.get("rosters", {}) as Dictionary).has(roster_id)


## Tuning value by dotted path ("strength.launch_ratio_x100"), int-coerced; `default` when absent. Overrides win.
func tune(path: String, default_value: int = 0) -> int:
	if _tuning_over.has(path):
		return int(_tuning_over[path])
	var cur: Variant = tuning
	for part: String in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = (cur as Dictionary)[part]
		else:
			return default_value
	if cur is Dictionary:
		return default_value
	return int(cur)


## Copy of this store with tuning overrides applied ("dotted.path" -> value); shares the immutable tables.
func with_overrides(over: Dictionary) -> AiDataStore:
	if over.is_empty():
		return self
	var s: AiDataStore = AiDataStore.new()
	s.errors = errors
	s.data_hash = data_hash
	s.difficulty_rows = difficulty_rows
	s.roles_cfg = roles_cfg
	s.tuning = tuning
	s.personality = personality
	s.extra = extra
	s._tuning_over = over.duplicate()
	return s


## Per-difficulty tuning row ("econ.margin_min" -> {"easy":..}) for a level.
func tune_by_level(path: String, level: int, default_value: int = 0) -> int:
	var cur: Variant = tuning
	for part: String in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = (cur as Dictionary)[part]
		else:
			return default_value
	if cur is Dictionary:
		var k: String = AiTypes.LEVEL_IDS[clampi(level, 0, 3)]
		return int((cur as Dictionary).get(k, default_value))
	return int(cur)
