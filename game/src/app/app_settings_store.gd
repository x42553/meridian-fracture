class_name AppSettingsStore
extends RefCounted
## Typed settings model (ui.md 3.1, 4.8, 5.20.1): defaults, clamp/validate per `AppSettingsSchema`, crash-safe load/save
## of `user://settings.cfg`, migration hook, unknown-key preservation and an in-memory mode. Pure: no SceneTree needed.
## Only values that differ from the default are written (plus `meta/version`), in schema order, then the `[controls]`
## key bindings, then unknown sections verbatim.

const FORMAT_VERSION: int = 1
const BAD_SUFFIX: String = ".bad-"

signal changed(id: StringName)

## Human-readable notes of the last load ("settings.cfg corrupt -> moved to settings.cfg.bad-20260929T140311Z").
var load_notes: PackedStringArray = PackedStringArray()
## Error of the last `save_to` (OK = written).
var last_error: int = OK

var _values: Dictionary = {}
var _keys: Dictionary = {}
var _unknown: Dictionary = {}
var _file_version: int = FORMAT_VERSION
var _dirty: bool = false
var _warned: Dictionary = {}


static func with_defaults() -> AppSettingsStore:
	return AppSettingsStore.new()


# ---------------------------------------------------------------- access

## Typed value; the schema default when unset; `null` for an unset preset row and for an unknown id (one warning).
func get_value(id: StringName) -> Variant:
	var row: Dictionary = AppSettingsSchema.entry(id)
	if row.is_empty():
		if not _warned.has(id):
			_warned[id] = true
			Log.warn("app", "settings: unknown id '%s'" % id)
		return null
	if _values.has(String(id)):
		var v: Variant = _values[String(id)]
		return v.duplicate() if v is PackedStringArray else v
	return AppSettingsSchema.default_of(row)


## Coerces and clamps per schema, stores it. False for an unknown id or an unusable value. `null` resets a row.
func set_value(id: StringName, value: Variant) -> bool:
	var row: Dictionary = AppSettingsSchema.entry(id)
	if row.is_empty():
		return false
	if value == null:
		reset(id)
		return true
	var v: Variant = coerce(row, value)
	if v == null:
		return false
	var key: String = String(id)
	if _same(v, row["default"]):
		if not _values.has(key):
			return true
		_values.erase(key)
	else:
		if _values.has(key) and _same(_values[key], v):
			return true
		_values[key] = v
	_dirty = true
	changed.emit(id)
	return true


func reset(id: StringName) -> void:
	if _values.erase(String(id)):
		_dirty = true
		changed.emit(id)


func reset_all() -> void:
	var ids: Array = _values.keys()
	_values.clear()
	_keys.clear()
	if not ids.is_empty():
		_dirty = true
		for id: Variant in ids:
			changed.emit(StringName(id))


## True when the row equals its default (an unset preset row counts as default).
func is_default(id: StringName) -> bool:
	return not _values.has(String(id))


## True when the value was set (differs from the default and will be written).
func is_explicit(id: StringName) -> bool:
	return _values.has(String(id))


func explicit_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for row: Dictionary in AppSettingsSchema.entries():
		if _values.has(String(row["id"])):
			out.append(String(row["id"]))
	return out


func dirty() -> bool:
	return _dirty


func mark_clean() -> void:
	_dirty = false


## `action -> PackedStringArray` of packed key strings (ui.md 4.5.1).
func keys_section() -> Dictionary:
	var out: Dictionary = {}
	for action: Variant in _keys:
		out[action] = (_keys[action] as PackedStringArray).duplicate()
	return out


func set_keys_section(d: Dictionary) -> void:
	var fresh: Dictionary = {}
	for action: Variant in d:
		var arr: Variant = _to_packed(d[action])
		if arr != null:
			fresh[String(action)] = arr
	if fresh != _keys:
		_keys = fresh
		_dirty = true
		changed.emit(&"controls/*")


# ---------------------------------------------------------------- coercion

## Coerced + clamped value for a row, or `null` when `value` is unusable.
static func coerce(row: Dictionary, value: Variant) -> Variant:
	match int(row["type"]):
		AppSettingsSchema.T.BOOL:
			return _to_bool(value)
		AppSettingsSchema.T.INT:
			var n: Variant = _to_int(value)
			if n == null:
				return null
			return _snap_int(row, int(n))
		AppSettingsSchema.T.FLOAT:
			var f: Variant = _to_float(value)
			if f == null:
				return null
			return _snap_float(row, float(f))
		AppSettingsSchema.T.CHOICE:
			return _to_choice(row, value)
		AppSettingsSchema.T.STRING:
			return _coerce_string(row, value)
		AppSettingsSchema.T.VECTOR2I:
			return _to_vec2i(row, value)
		AppSettingsSchema.T.LIST:
			var l: Variant = _to_packed(value)
			if l == null:
				return null
			var lim: int = int(row["max"]) if row["max"] != null else 64
			var arr: PackedStringArray = l as PackedStringArray
			return arr.slice(0, lim) if arr.size() > lim else arr
	return null


static func _to_bool(v: Variant) -> Variant:
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	if v is String or v is StringName:
		var s: String = String(v).to_lower()
		if s == "true" or s == "1" or s == "on":
			return true
		if s == "false" or s == "0" or s == "off":
			return false
	return null


static func _to_int(v: Variant) -> Variant:
	if v is int:
		return v
	if v is float:
		if is_nan(v) or is_inf(v):
			return null
		return roundi(v)
	if v is bool:
		return 1 if v else 0
	if v is String or v is StringName:
		var s: String = String(v).strip_edges()
		if s.is_valid_int():
			return s.to_int()
		if s.is_valid_float():
			return roundi(s.to_float())
	return null


static func _to_float(v: Variant) -> Variant:
	if v is float:
		return null if is_nan(v) or is_inf(v) else v
	if v is int:
		return float(v)
	if v is String or v is StringName:
		var s: String = String(v).strip_edges()
		if s.is_valid_float():
			return s.to_float()
	return null


static func _snap_int(row: Dictionary, n: int) -> int:
	var lo: int = int(row["min"]) if row["min"] != null else -2147483648
	var hi: int = int(row["max"]) if row["max"] != null else 2147483647
	var out: int = clampi(n, lo, hi)
	var step: int = int(row["step"])
	if step > 1 and row["min"] != null:
		out = clampi(lo + roundi(float(out - lo) / float(step)) * step, lo, hi)
	return out


static func _snap_float(row: Dictionary, f: float) -> float:
	var lo: float = float(row["min"]) if row["min"] != null else -1.0e30
	var hi: float = float(row["max"]) if row["max"] != null else 1.0e30
	var out: float = clampf(f, lo, hi)
	var step: float = float(row["step"])
	if step > 0.0 and step != 1.0 and row["min"] != null:
		out = lo + roundf((out - lo) / step) * step
	return clampf(snappedf(out, 0.0001), lo, hi)


static func _to_choice(row: Dictionary, v: Variant) -> Variant:
	for c: Dictionary in row["choices"]:
		var cv: Variant = c["value"]
		if cv is int:
			if v is String or v is StringName:
				if String(v).is_valid_int() and String(v).to_int() == int(cv):
					return cv
			elif v is int or v is bool:
				if int(v) == int(cv):
					return cv
			elif v is float and is_equal_approx(float(v), float(cv)):
				return cv
		elif (v is String or v is StringName) and String(v) == String(cv):
			return cv
	return null


static func _coerce_string(row: Dictionary, v: Variant) -> Variant:
	if not (v is String or v is StringName):
		return null
	var s: String = String(v)
	if String(row["id"]) == "net/player_name":
		return AppProfile.sanitize_name(s)
	s = s.replace("\n", " ").replace("\r", " ")
	var lim: int = int(row["max_len"])
	return s.substr(0, lim) if lim > 0 and s.length() > lim else s


static func _to_vec2i(row: Dictionary, v: Variant) -> Variant:
	var out: Vector2i
	if v is Vector2i:
		out = v
	elif v is Vector2:
		out = Vector2i(roundi((v as Vector2).x), roundi((v as Vector2).y))
	elif v is Array and (v as Array).size() == 2:
		var a: Variant = _to_int((v as Array)[0])
		var b: Variant = _to_int((v as Array)[1])
		if a == null or b == null:
			return null
		out = Vector2i(int(a), int(b))
	else:
		return null
	if row["min"] is Vector2i:
		out = Vector2i(maxi(out.x, (row["min"] as Vector2i).x), maxi(out.y, (row["min"] as Vector2i).y))
	return out


static func _to_packed(v: Variant) -> Variant:
	if v is PackedStringArray:
		return v.duplicate()
	if v is Array:
		var out: PackedStringArray = PackedStringArray()
		for e: Variant in v:
			if not (e is String or e is StringName):
				return null
			out.append(String(e))
		return out
	return null


static func _same(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if typeof(a) != typeof(b):
		return false
	return a == b


# ---------------------------------------------------------------- text and files

## The complete file text for the current values.
func to_text() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("meta", "version", maxi(_file_version, FORMAT_VERSION))
	for row: Dictionary in AppSettingsSchema.entries():
		var id: String = String(row["id"])
		if id != "meta/version" and _values.has(id):
			cfg.set_value(AppSettingsSchema.section_of(id), AppSettingsSchema.key_of(id), _values[id])
	for action: Variant in _keys:
		cfg.set_value(AppSettingsSchema.SECTION_CONTROLS, String(action), _keys[action])
	for sec: Variant in _unknown:
		var kv: Dictionary = _unknown[sec]
		for k: Variant in kv:
			cfg.set_value(String(sec), String(k), kv[k])
	return cfg.encode_to_text()


## Replaces the values from settings text. False on a parse error (the store is left untouched).
func from_text(text: String) -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	if text.strip_edges().is_empty() or cfg.parse(text) != OK:
		return false
	if cfg.get_sections().is_empty() and _has_content(text):
		return false
	_values.clear()
	_keys.clear()
	_unknown.clear()
	_file_version = FORMAT_VERSION
	for sec: String in cfg.get_sections():
		for key: String in cfg.get_section_keys(sec):
			_ingest(sec, key, cfg.get_value(sec, key))
	if _file_version < FORMAT_VERSION:
		_migrate(_file_version)
		_file_version = FORMAT_VERSION
	_dirty = false
	return true


## true when `text` has a line that is neither blank nor a `;` comment (a section-less file with content is garbage).
static func _has_content(text: String) -> bool:
	for line: String in text.split("\n"):
		var l: String = line.strip_edges()
		if not l.is_empty() and not l.begins_with(";") and not l.begins_with("#"):
			return true
	return false


func _ingest(sec: String, key: String, value: Variant) -> void:
	var id: String = "%s/%s" % [sec, key]
	if sec == AppSettingsSchema.SECTION_CONTROLS:
		var arr: Variant = _to_packed(value)
		if arr == null:
			load_notes.append("controls/%s invalid, dropped" % key)
		else:
			_keys[key] = arr
		return
	var row: Dictionary = AppSettingsSchema.entry(StringName(id))
	if row.is_empty():
		if not _unknown.has(sec):
			_unknown[sec] = {}
		(_unknown[sec] as Dictionary)[key] = value
		return
	if id == "meta/version":
		var ver: Variant = _to_int(value)
		_file_version = int(ver) if ver != null else FORMAT_VERSION
		return
	var v: Variant = coerce(row, value)
	if v == null:
		load_notes.append("%s invalid, default used" % id)
		return
	if not _same(v, row["default"]):
		_values[id] = v


## Migration table: empty for format version 1. Called only when the file's version is older than `FORMAT_VERSION`.
func _migrate(_from_version: int) -> void:
	pass


## Loads `path` with the recovery rules of 5.20.1. Returns OK when a file (or its .bak) was loaded,
## `ERR_FILE_NOT_FOUND` when nothing exists (defaults, first run), `ERR_PARSE_ERROR` when the file was corrupt and
## nothing could be recovered.
func load_from(path: String, files: AppFileLayer = null) -> int:
	var fl: AppFileLayer = files if files != null else AppFileLayer.new()
	load_notes = PackedStringArray()
	var bak: String = path + ".bak"
	var result: int = ERR_FILE_NOT_FOUND
	if fl.exists(path):
		if from_text(fl.read_text(path)):
			_dirty = false
			return OK
		var bad: String = "%s%s%s" % [path, BAD_SUFFIX, AppPaths.utc_stamp()]
		var moved: int = fl.rename(path, bad)
		load_notes.append("%s corrupt -> %s as %s" % [path.get_file(), "moved" if moved == OK else "could not be moved",
			bad.get_file()])
		Log.warn("app", load_notes[load_notes.size() - 1])
		result = ERR_PARSE_ERROR
	if fl.exists(bak):
		var bak_text: String = fl.read_text(bak)
		if from_text(bak_text):
			load_notes.append("%s restored from %s" % [path.get_file(), bak.get_file()])
			Log.warn("app", load_notes[load_notes.size() - 1])
			fl.write_text(path, bak_text)
			_dirty = false
			return OK
		load_notes.append("%s unusable" % bak.get_file())
		result = ERR_PARSE_ERROR
	_values.clear()
	_keys.clear()
	_unknown.clear()
	_dirty = false
	return result


## Crash-safe save (5.20.1): (1) write `.tmp` completely; (2) remove an old `.bak`, rename the current file to `.bak`;
## (3) rename `.tmp` into place. A valid file (`path` or `.bak`) is recoverable after every step. Returns the Error;
## on failure the store keeps working in memory (`last_error` is set, one warning).
func save_to(path: String, files: AppFileLayer = null) -> int:
	var fl: AppFileLayer = files if files != null else AppFileLayer.new()
	var tmp: String = path + ".tmp"
	var bak: String = path + ".bak"
	var err: int = fl.write_text(tmp, to_text())
	if err == OK and fl.exists(path):
		if fl.exists(bak):
			err = fl.remove(bak)
		if err == OK:
			err = fl.rename(path, bak)
	if err == OK:
		err = fl.rename(tmp, path)
	last_error = err
	if err != OK:
		Log.warn("app", "settings not saved (%s): %s" % [error_string(err), path])
		return err
	_dirty = false
	return OK
