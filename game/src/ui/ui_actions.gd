class_name UiActions
extends RefCounted
## Action registry (ui.md 4.5.2): every rebindable action with its category, context mask, repeat flag and default
## chords, loaded from `data/ui/keymap_defaults.json` (ui.md 7.8). `UiKeymap` owns the current bindings; this class is
## the immutable description plus the chord parser (US-layout names, stored as PHYSICAL keycodes).

const DEFAULTS_PATH: String = "res://data/ui/keymap_defaults.json"

# = UiKeymap.Context (duplicated so this file has no dependency cycle)
const CTX_GLOBAL: int = 1
const CTX_MENU: int = 2
const CTX_GAME: int = 4
const CTX_OBSERVER: int = 8
const CTX_LOBBY: int = 16
const CTX_TEXT_ENTRY: int = 32
const CTX_ALL: int = 63

const CONTEXT_BITS: Dictionary = {
	"global": CTX_GLOBAL, "menu": CTX_MENU, "game": CTX_GAME, "observer": CTX_OBSERVER, "lobby": CTX_LOBBY,
	"text_entry": CTX_TEXT_ENTRY,
}

## Punctuation the JSON may spell as a symbol (the named forms `Equal`, `Minus` ... go through the engine).
const SYMBOL_KEYS: Dictionary = {
	"=": KEY_EQUAL, "-": KEY_MINUS, ".": KEY_PERIOD, ",": KEY_COMMA, "[": KEY_BRACKETLEFT, "]": KEY_BRACKETRIGHT,
	";": KEY_SEMICOLON, "'": KEY_APOSTROPHE, "/": KEY_SLASH, "\\": KEY_BACKSLASH, "`": KEY_QUOTELEFT,
}


## One action's static description.
class Def extends RefCounted:
	var id: StringName = &""
	var category: StringName = &""
	var contexts: int = 0  ## UiKeymap.Context mask (GLOBAL = active in every context)
	var label_key: StringName = &""
	var repeat: bool = false  ## fires on key echo (camera actions only)
	var allow_mouse: bool = false  ## may be bound to a mouse button (cam_orbit)
	var default: PackedInt32Array = PackedInt32Array()  ## <= 2 packed keys (negative = mouse button)

	## Context mask with GLOBAL expanded to every context (conflict detection).
	func effective_contexts() -> int:
		return UiActions.CTX_ALL if (contexts & UiActions.CTX_GLOBAL) != 0 else contexts


var _defs: Dictionary = {}  ## StringName -> Def
var _order: Array[StringName] = []


## Registry loaded from the shipped JSON (`mac` selects `mac_keys` where a row has them; default = this OS).
static func load_defaults(mac: int = -1, path: String = DEFAULTS_PATH) -> UiActions:
	var reg := UiActions.new()
	var use_mac: bool = OS.get_name() == "macOS" if mac < 0 else mac > 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("actions"):
		push_error("UiActions: cannot read %s" % path)
		return reg
	for row: Variant in (parsed as Dictionary)["actions"]:
		reg._add_row(row as Dictionary, use_mac)
	return reg


func _add_row(row: Dictionary, use_mac: bool) -> void:
	var d := Def.new()
	d.id = StringName(str(row["id"]))
	d.category = StringName(str(row.get("category", "")))
	d.label_key = StringName(str(row.get("label_key", "action.%s" % d.id)))
	d.repeat = bool(row.get("repeat", false))
	d.allow_mouse = bool(row.get("allow_mouse", false))
	for c: Variant in row.get("contexts", []):
		d.contexts |= int(CONTEXT_BITS.get(str(c), 0))
	var keys: Array = row["mac_keys"] if (use_mac and row.has("mac_keys")) else row.get("keys", [])
	for k: Variant in keys:
		var packed: int = parse_chord(str(k))
		if packed != 0 and d.default.size() < 2:
			d.default.append(packed)
	for m: Variant in row.get("mouse", []):
		if d.default.size() < 2:
			d.default.append(-int(m))
	if _defs.has(d.id):
		push_error("UiActions: duplicate action %s" % d.id)
		return
	_defs[d.id] = d
	_order.append(d.id)


## Ids in file order.
func ids() -> Array[StringName]:
	return _order


func has(id: StringName) -> bool:
	return _defs.has(id)


## The Def of `id`, null when unknown.
func get_def(id: StringName) -> Def:
	return _defs.get(id) as Def


func size() -> int:
	return _order.size()


## "group_select_3" with prefix "group_select_" -> 3; -1 when `id` does not start with the prefix or has no number.
static func indexed(id: StringName, prefix: String) -> int:
	var s: String = String(id)
	if not s.begins_with(prefix):
		return -1
	var tail: String = s.substr(prefix.length())
	return int(tail) if tail.is_valid_int() else -1


## "Ctrl+Shift+1" / "Alt+Q" / "Cmd+F" / "Option+Q" / "Equal" -> packed key (physical keycode | KEY_MASK_*), 0 when unparsable.
static func parse_chord(text: String) -> int:
	var mods: int = 0
	var key_part: String = ""
	var parts: PackedStringArray = text.split("+")
	for i: int in parts.size():
		var p: String = parts[i].strip_edges()
		if i < parts.size() - 1:
			match p.to_lower():
				"shift":
					mods |= KEY_MASK_SHIFT
				"ctrl", "control":
					mods |= KEY_MASK_CTRL
				"alt", "option", "opt":
					mods |= KEY_MASK_ALT
				"cmd", "meta", "super", "command", "win":
					mods |= KEY_MASK_META
				_:
					return 0
		else:
			key_part = p
	if key_part.is_empty():
		return 0
	var code: int = int(SYMBOL_KEYS[key_part]) if SYMBOL_KEYS.has(key_part) else OS.find_keycode_from_string(key_part)
	code &= KEY_CODE_MASK
	if code == 0:
		return 0
	return code | mods
