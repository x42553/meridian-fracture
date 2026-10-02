class_name AppCampaign
extends RefCounted
## Campaign progress (MIS2): per mission completed flag, best winning time, highest difficulty beaten, attempts, and the difficulty
## last chosen. Persisted in `user://campaign.cfg` (ConfigFile text) with the crash-safe write sequence of the settings
## (`.tmp` written completely, old file kept as `.bak`, `.tmp` renamed into place; load falls back to `.bak` and moves a corrupt
## file aside). Owned by `AppProfile.campaign`. Pure data: no SceneTree. A campaign opened with `in_memory` (tests, `--fresh-settings`,
## every `--autostart` run) never touches the disk.
##
## Difficulty values are AI levels 0..3 (Easy, Medium, Hard, Brutal; `AppMission.DIFFICULTY_NAMES`); -1 = none.

const FORMAT_VERSION: int = 1
const BAD_SUFFIX: String = ".bad-"
const SECTION_PREFIX: String = "m."
const MAX_TICKS: int = 20 * 3600 * 24  ## a stored best time above this is corrupt

## Human-readable notes of the last load.
var load_notes: PackedStringArray = PackedStringArray()
## Error of the last `save` (OK = written).
var last_error: int = OK
var path: String = AppPaths.CAMPAIGN
var files: AppFileLayer = AppFileLayer.new()
## true = never reads or writes the disk.
var in_memory: bool = true
## Debug (`--campaign-unlock`): every mission is selectable.
var unlock_all: bool = false

var _rec: Dictionary = {}  ## mission id -> {done, best_ticks, best_ticks_diff, best_diff, plays, wins, last_diff}
var _dirty: bool = false


## A campaign backed by `file` (loaded now; defaults when the file is missing or unreadable).
static func open(file: String = AppPaths.CAMPAIGN, layer: AppFileLayer = null) -> AppCampaign:
	var c: AppCampaign = AppCampaign.new()
	c.in_memory = false
	c.path = file
	if layer != null:
		c.files = layer
	c.load_file()
	return c


static func blank_record() -> Dictionary:
	return {"done": false, "best_ticks": 0, "best_ticks_diff": -1, "best_diff": -1, "plays": 0, "wins": 0, "last_diff": -1}


# ---------------------------------------------------------------- queries

func has_record(mission_id: String) -> bool:
	return _rec.has(mission_id)


func completed(mission_id: String) -> bool:
	return bool(_field(mission_id, "done"))


## Fastest winning time in ticks, 0 = never won.
func best_ticks(mission_id: String) -> int:
	return int(_field(mission_id, "best_ticks"))


## Difficulty of the fastest win (-1 = never won).
func best_ticks_difficulty(mission_id: String) -> int:
	return int(_field(mission_id, "best_ticks_diff"))


## Highest difficulty the mission was won on (-1 = never won).
func best_difficulty(mission_id: String) -> int:
	return int(_field(mission_id, "best_diff"))


func plays(mission_id: String) -> int:
	return int(_field(mission_id, "plays"))


func wins(mission_id: String) -> int:
	return int(_field(mission_id, "wins"))


## The difficulty chosen last time (`fallback` when none).
func last_difficulty(mission_id: String, fallback: int = 1) -> int:
	var d: int = int(_field(mission_id, "last_diff"))
	return d if d >= 0 else fallback


func completed_count(ids: PackedStringArray) -> int:
	var n: int = 0
	for id: String in ids:
		if completed(id):
			n += 1
	return n


func mission_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(_rec.keys())
	out.sort()
	return out


func dirty() -> bool:
	return _dirty


func _field(mission_id: String, key: String) -> Variant:
	var r: Variant = _rec.get(mission_id)
	if r == null:
		return blank_record()[key]
	return (r as Dictionary)[key]


# ---------------------------------------------------------------- updates

## A mission was started (counts as a play; remembers the difficulty). Does not save: `record_result` / `save` do.
func note_start(mission_id: String, difficulty: int) -> void:
	var r: Dictionary = _ensure(mission_id)
	r["plays"] = int(r["plays"]) + 1
	r["last_diff"] = clampi(difficulty, 0, 15)
	_dirty = true


## The mission ended. A loss only counts the attempt's result nowhere (plays was counted at the start); a win updates completion,
## the best time and the best difficulty. Saves at once (crash-safe). Returns
## `{first_clear, new_best_time, new_best_difficulty, prev_best_ticks, prev_best_diff}` for the result screen.
func record_result(mission_id: String, won: bool, ticks: int, difficulty: int) -> Dictionary:
	var r: Dictionary = _ensure(mission_id)
	var out: Dictionary = {"first_clear": false, "new_best_time": false, "new_best_difficulty": false,
		"prev_best_ticks": int(r["best_ticks"]), "prev_best_diff": int(r["best_diff"])}
	r["last_diff"] = clampi(difficulty, 0, 15)
	if won:
		out["first_clear"] = not bool(r["done"])
		r["done"] = true
		r["wins"] = int(r["wins"]) + 1
		if difficulty > int(r["best_diff"]):
			r["best_diff"] = difficulty
			out["new_best_difficulty"] = true
		if ticks > 0 and (int(r["best_ticks"]) <= 0 or ticks < int(r["best_ticks"])):
			r["best_ticks"] = ticks
			r["best_ticks_diff"] = difficulty
			out["new_best_time"] = true
	_dirty = true
	save()
	return out


func remember_difficulty(mission_id: String, difficulty: int) -> void:
	var r: Dictionary = _ensure(mission_id)
	if int(r["last_diff"]) != difficulty:
		r["last_diff"] = clampi(difficulty, 0, 15)
		_dirty = true


func clear() -> void:
	_rec.clear()
	_dirty = true


func _ensure(mission_id: String) -> Dictionary:
	if not _rec.has(mission_id):
		_rec[mission_id] = blank_record()
	return _rec[mission_id] as Dictionary


# ---------------------------------------------------------------- text and files

static func valid_id(s: String) -> bool:
	if s.is_empty() or s.length() > 40:
		return false
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true


func to_text() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("meta", "version", FORMAT_VERSION)
	for id: String in mission_ids():
		var r: Dictionary = _rec[id] as Dictionary
		for k: String in ["done", "best_ticks", "best_ticks_diff", "best_diff", "plays", "wins", "last_diff"]:
			cfg.set_value(SECTION_PREFIX + id, k, r[k])
	return cfg.encode_to_text()


## Replaces the records from `text`. False on a parse error (the campaign is left untouched).
func from_text(text: String) -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	if text.strip_edges().is_empty() or cfg.parse(text) != OK or cfg.get_sections().is_empty():
		return false
	var fresh: Dictionary = {}
	for sec: String in cfg.get_sections():
		if not sec.begins_with(SECTION_PREFIX):
			continue
		var id: String = sec.substr(SECTION_PREFIX.length())
		if not valid_id(id):
			load_notes.append("section %s dropped (bad mission id)" % sec)
			continue
		var r: Dictionary = blank_record()
		for k: String in r.keys():
			if not cfg.has_section_key(sec, k):
				continue
			var v: Variant = cfg.get_value(sec, k)
			if k == "done":
				r[k] = bool(v) if v is bool or v is int else false
			elif v is int:
				var floor_v: int = 0 if (k == "best_ticks" or k == "plays" or k == "wins") else -1
				r[k] = clampi(int(v), floor_v, MAX_TICKS if k == "best_ticks" else 1000000)
			else:
				load_notes.append("%s/%s invalid, default used" % [id, k])
		r["best_diff"] = clampi(int(r["best_diff"]), -1, 15)
		r["best_ticks_diff"] = clampi(int(r["best_ticks_diff"]), -1, 15)
		r["last_diff"] = clampi(int(r["last_diff"]), -1, 15)
		r["done"] = bool(r["done"]) or int(r["best_diff"]) >= 0
		fresh[id] = r
	_rec = fresh
	_dirty = false
	return true


## Loads `path` with the settings recovery rules: the file, else its `.bak`; a corrupt file is moved aside. Returns OK, ERR_FILE_NOT_FOUND
## (first run) or ERR_PARSE_ERROR (nothing recoverable; empty progress).
func load_file() -> int:
	load_notes = PackedStringArray()
	if in_memory:
		return ERR_FILE_NOT_FOUND
	var bak: String = path + ".bak"
	var result: int = ERR_FILE_NOT_FOUND
	if files.exists(path):
		if from_text(files.read_text(path)):
			return OK
		var bad: String = "%s%s%s" % [path, BAD_SUFFIX, AppPaths.utc_stamp()]
		var moved: int = files.rename(path, bad)
		load_notes.append("%s corrupt -> %s as %s" % [path.get_file(), "moved" if moved == OK else "could not be moved", bad.get_file()])
		Log.warn("app", load_notes[load_notes.size() - 1])
		result = ERR_PARSE_ERROR
	if files.exists(bak):
		var bak_text: String = files.read_text(bak)
		if from_text(bak_text):
			load_notes.append("%s restored from %s" % [path.get_file(), bak.get_file()])
			Log.warn("app", load_notes[load_notes.size() - 1])
			files.write_text(path, bak_text)
			return OK
		load_notes.append("%s unusable" % bak.get_file())
		result = ERR_PARSE_ERROR
	_rec.clear()
	_dirty = false
	return result


## Crash-safe save: (1) write `.tmp` completely; (2) remove an old `.bak`, rename the current file to `.bak`; (3) rename `.tmp` into place.
## A valid file (`path` or `.bak`) exists after every step. Returns the Error; on failure the progress stays in memory.
func save() -> int:
	if in_memory:
		return OK
	var tmp: String = path + ".tmp"
	var bak: String = path + ".bak"
	var err: int = files.write_text(tmp, to_text())
	if err == OK and files.exists(path):
		if files.exists(bak):
			err = files.remove(bak)
		if err == OK:
			err = files.rename(path, bak)
	if err == OK:
		err = files.rename(tmp, path)
	last_error = err
	if err != OK:
		Log.warn("app", "campaign progress not saved (%s): %s" % [error_string(err), path])
		return err
	_dirty = false
	return OK
