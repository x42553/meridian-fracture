class_name UiSkinSet
extends RefCounted
## One `UiSkin` per faction + neutral, the team-colour source and the colour-mode switch (ui.md 5.19.3).
## `setup(style)` takes the injected `ViewStyle` duck-typed (`skin(code)`, `chrome()`, `player_color(id, cvd)`,
## `player_color_count(cvd)`); `null` -> built-in fallback skins and the built-in team tables. `setup_from_json`
## reads `style.json` directly (tests, tools) so the UI does not wait for the art module.

enum ColourMode { NORMAL = 0, CVD = 1 }

signal colour_mode_changed(mode: int)

const STYLE_PATH: String = "res://data/recipes/style.json"

static var _shared: UiSkinSet = null


static func release_statics() -> void:
	_shared = null

var _style: Object = null
var _skins: Dictionary = {}
var _mode: int = ColourMode.NORMAL


## Process-wide instance (created with the built-in fallback until `setup` is called on it).
static func shared() -> UiSkinSet:
	if _shared == null:
		_shared = UiSkinSet.new()
	return _shared


## Replaces the process-wide instance (boot, tests).
static func set_shared(s: UiSkinSet) -> void:
	_shared = s


## Injects the style source (a `ViewStyle`) or null for the fallback. Clears the skin cache.
func setup(src: Object) -> void:
	_style = src
	_skins.clear()


## Reads `style.json` (default `STYLE_PATH`) and injects a dictionary-backed source. False (and a log line) on failure.
func setup_from_json(path: String = STYLE_PATH) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		Log.warn("ui", "style.json: %s: cannot open (fallback skins)" % path)
		setup(null)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		Log.warn("ui", "style.json: %s: not a JSON object (fallback skins)" % path)
		setup(null)
		return false
	setup(DictStyle.new(parsed as Dictionary))
	return true


## Skin of a faction code (cached); unknown code -> neutral.
func skin_for(faction_code: String) -> UiSkin:
	if not _skins.has(faction_code):
		_skins[faction_code] = UiSkin.from_style(_style, faction_code) if faction_code != "" else _neutral()
	return _skins[faction_code]


func _neutral() -> UiSkin:
	var s: UiSkin = UiSkin.neutral()
	if _style != null and _style.has_method(&"chrome"):
		var ch: Variant = _style.call(&"chrome")
		if ch is Dictionary and not (ch as Dictionary).is_empty():
			s.chrome = UiSkin.merge_chrome(ch as Dictionary)
	return s


func neutral_skin() -> UiSkin:
	return skin_for("")


func set_colour_mode(mode: int) -> void:
	if mode == _mode:
		return
	_mode = mode
	colour_mode_changed.emit(mode)


func colour_mode() -> int:
	return _mode


## The injected style source; null in fallback mode.
func style() -> Object:
	return _style


## Player colour `id` (0-11) for the active colour mode. ids 8-11 have no CVD variant (default hex).
func team_color(id: int) -> Color:
	return team_color_for(id, _mode == ColourMode.CVD)


func team_color_for(id: int, cvd: bool) -> Color:
	if _style != null and _style.has_method(&"player_color"):
		var v: Variant = _style.call(&"player_color", id, cvd)
		if v is Color:
			return v as Color
	var table: PackedStringArray = UiPalette.TEAM_CVD if cvd and id >= 0 and id < UiPalette.TEAM_CVD.size() else UiPalette.TEAM_DEFAULT
	return Color(table[posmod(id, table.size())])


## 12 in `normal`, 8 in `cvd`.
func team_color_count() -> int:
	var cvd: bool = _mode == ColourMode.CVD
	if _style != null and _style.has_method(&"player_color_count"):
		return int(_style.call(&"player_color_count", cvd))
	return 8 if cvd else 12


## Contrast self-check (5.19.2): every faction accent >= 4.5 : 1 on `BG_PANEL` and `TEXT_ON_ACCENT` >= 4.5 on it.
## Returns the failing faction codes (empty = OK).
func contrast_failures() -> PackedStringArray:
	var bad := PackedStringArray()
	for code in UiSkin.CODES:
		var a: Color = skin_for(code).accent
		if UiA11y.contrast_ratio(a, UiPalette.BG_PANEL) < 4.5 or UiA11y.contrast_ratio(UiPalette.TEXT_ON_ACCENT, a) < 4.5:
			bad.append(code)
	return bad


## Dictionary-backed style source with the `ViewStyle` accessors the UI uses (the art module's class replaces it).
class DictStyle extends RefCounted:
	var data: Dictionary

	func _init(d: Dictionary) -> void:
		data = d

	func ui_token(token_name: String) -> Color:
		return Color(String(((data.get("ui", {}) as Dictionary).get("tokens", {}) as Dictionary).get(token_name, "#ff00ff")))

	func skin(code: String) -> Dictionary:
		return ((data.get("ui", {}) as Dictionary).get("skins", {}) as Dictionary).get(code, {})

	func chrome() -> Dictionary:
		return (data.get("ui", {}) as Dictionary).get("chrome", {})

	func player_color(id: int, cvd: bool) -> Color:
		var pc: Dictionary = data.get("player_colors", {})
		var list: Array = pc.get("cvd" if cvd else "default", [])
		if cvd and (id < 0 or id >= list.size()):
			list = pc.get("default", [])
		if id < 0 or id >= list.size():
			return Color.MAGENTA
		return Color(String((list[id] as Dictionary).get("hex", "#ff00ff")))

	func player_color_count(cvd: bool) -> int:
		return ((data.get("player_colors", {}) as Dictionary).get("cvd" if cvd else "default", []) as Array).size()
