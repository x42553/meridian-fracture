class_name UiKeymap
extends RefCounted
## Rebindable keymap (ui.md 4.5, 5.6): the action registry (`UiActions`) plus the current bindings as PACKED PHYSICAL keys
## (`physical_keycode | KEY_MASK_*`, negative = mouse button), the per-context InputMap installation, exact-match event
## tests, conflict detection, persistence through `AppSettingsStore` (`[keys]`) and the per-OS gesture modifier mapping.

enum Context { GLOBAL = 1, MENU = 2, GAME = 4, OBSERVER = 8, LOBBY = 16, TEXT_ENTRY = 32 }
enum Conflict { REFUSE = 0, SWAP = 1, REPLACE = 2 }  ## `bind(on_conflict)`

const MOD_SHIFT: int = 1
const MOD_CTRL: int = 2  ## the force-fire role: Ctrl on Windows / Linux, Option on macOS (5.5.6)
const MOD_ALT: int = 4
const MOD_META: int = 8

const MOD_KEYS: PackedInt32Array = [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]
## Combos the OS owns (packed with the given modifiers; the Cmd ones only exist on macOS but are refused everywhere).
const RESERVED: PackedInt32Array = [
	KEY_F4 | KEY_MASK_ALT, KEY_Q | KEY_MASK_META, KEY_H | KEY_MASK_META, KEY_M | KEY_MASK_META, KEY_TAB | KEY_MASK_META,
	KEY_TAB | KEY_MASK_ALT, KEY_DELETE | KEY_MASK_CTRL | KEY_MASK_ALT,
]
const FOCUS_ACTIONS: PackedStringArray = ["ui_focus_next", "ui_focus_prev"]

signal bindings_changed()

static var _instance: UiKeymap = null

## Overridable OS name for `mods_of` (tests); "" = `OS.get_name()`.
var os_name: String = ""
var last_error: String = ""  ## reason of the last refused `bind`

var _reg: UiActions = null
var _binds: Dictionary = {}  ## StringName -> PackedInt32Array (<= 2 packed keys)
var _installed: Dictionary = {}  ## StringName -> true: actions this keymap put into the InputMap
var _created: Dictionary = {}  ## StringName -> true: of those, the ones it created (erased on uninstall)
var _saved: Dictionary = {}  ## StringName -> Array[InputEvent]: events of actions that already existed (the view camera's), restored on uninstall
var _install_ctx: int = 0
var _focus_saved: Dictionary = {}  ## action -> Array[InputEvent] (ui_focus_next / prev before Tab was freed)
var _tab_freed: bool = false


static func instance() -> UiKeymap:
	if _instance == null:
		_instance = UiKeymap.new()
		_instance.load_defaults()
	return _instance


## Test hook: drops the shared instance.
static func reset_instance() -> void:
	if _instance != null:
		_instance.uninstall(0)
	_instance = null


## (Re)loads the registry and default bindings from `data/ui/keymap_defaults.json` (`mac` -1 = this OS, 0 no, 1 yes).
func load_defaults(mac: int = -1) -> void:
	_reg = UiActions.load_defaults(mac)
	_binds.clear()
	for id: StringName in _reg.ids():
		_binds[id] = _reg.get_def(id).default.duplicate()
	_reinstall()
	bindings_changed.emit()


func registry() -> UiActions:
	return _reg


## Action ids in registry order.
func action_ids() -> Array[StringName]:
	return _reg.ids()


func def_of(action: StringName) -> UiActions.Def:
	return _reg.get_def(action)


# ---- queries --------------------------------------------------------------------------------------------------------
## <= 2 packed keys; empty = unbound (or unknown action).
func bindings(action: StringName) -> PackedInt32Array:
	var b: Variant = _binds.get(action)
	return (b as PackedInt32Array).duplicate() if b != null else PackedInt32Array()


## Platform label of the first binding ("Alt+Q" / "Option+Q" / "F5"), "" when unbound.
func label(action: StringName) -> String:
	var b: PackedInt32Array = bindings(action)
	return key_label(b[0]) if not b.is_empty() else ""


## Label of a packed key with the layout-aware letter (position stays the physical one, 4.5.1).
static func key_label(packed: int) -> String:
	if packed < 0:
		return "Mouse %d" % -packed
	var phys: int = packed & KEY_CODE_MASK
	var mods: int = packed & ~KEY_CODE_MASK
	var code: int = phys
	if DisplayServer.get_name() != "headless":
		var c: int = DisplayServer.keyboard_get_keycode_from_physical(phys as Key)
		if c != 0:
			code = c & KEY_CODE_MASK
	return OS.get_keycode_string((code | mods) as Key)


## Actions bound to `packed` whose contexts overlap `contexts` (GLOBAL overlaps everything), except `ignore`.
func conflicts(packed: int, contexts: int, ignore: StringName = &"") -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var mask: int = UiActions.CTX_ALL if (contexts & Context.GLOBAL) != 0 else contexts
	for id: StringName in _reg.ids():
		if id == ignore:
			continue
		var d: UiActions.Def = _reg.get_def(id)
		if (d.effective_contexts() & mask) != 0 and (_binds[id] as PackedInt32Array).has(packed):
			out.append(String(id))
	return out


## Human-readable reason a chord cannot be bound to `action` ("" = allowed): modifier-only, Esc, OS-reserved, mouse.
func refused_reason(action: StringName, packed: int) -> String:
	var d: UiActions.Def = _reg.get_def(action)
	if d == null:
		return "unknown action"
	if packed < 0:
		return "" if d.allow_mouse else "mouse buttons are not allowed for this action"
	var code: int = packed & KEY_CODE_MASK
	if code == 0 or MOD_KEYS.has(code):
		return "a modifier alone cannot be bound"
	if code == KEY_ESCAPE and action != &"toggle_menu":
		return "Esc is reserved for the menu"
	if RESERVED.has(packed):
		return "reserved by the operating system"
	return ""


# ---- editing --------------------------------------------------------------------------------------------------------
## Binds `packed` in `slot` (0 or 1) of `action`. `on_conflict`: Conflict.REFUSE returns false and leaves everything,
## SWAP gives the other action this slot's previous key, REPLACE unbinds the other. False also when refused (`last_error`).
func bind(action: StringName, slot: int, packed: int, on_conflict: int) -> bool:
	last_error = refused_reason(action, packed)
	if not last_error.is_empty():
		return false
	var d: UiActions.Def = _reg.get_def(action)
	var mine: PackedInt32Array = _binds[action]
	slot = clampi(slot, 0, mini(mine.size(), 1))
	var previous: int = mine[slot] if slot < mine.size() else 0
	var others: PackedStringArray = conflicts(packed, d.contexts, action)
	if not others.is_empty() and on_conflict == Conflict.REFUSE:
		last_error = "already used by %s" % others[0]
		return false
	for o: String in others:
		var ob: PackedInt32Array = _binds[StringName(o)]
		var at: int = ob.find(packed)
		if at < 0:
			continue
		if on_conflict == Conflict.SWAP and previous != 0 and not ob.has(previous):
			ob[at] = previous
		else:
			ob.remove_at(at)
		_binds[StringName(o)] = ob
	if mine.has(packed):  # rebinding the same chord into the other slot: keep it once
		mine.remove_at(mine.find(packed))
		slot = clampi(slot, 0, mine.size())
	if slot < mine.size():
		mine[slot] = packed
	else:
		mine.append(packed)
	_binds[action] = mine
	_changed()
	return true


func unbind(action: StringName, slot: int) -> void:
	if not _binds.has(action):
		return
	var b: PackedInt32Array = _binds[action]
	if slot < 0 or slot >= b.size():
		return
	b.remove_at(slot)
	_binds[action] = b
	_changed()


func reset(action: StringName) -> void:
	var d: UiActions.Def = _reg.get_def(action)
	if d == null:
		return
	_binds[action] = d.default.duplicate()
	_changed()


func reset_all() -> void:
	for id: StringName in _reg.ids():
		_binds[id] = _reg.get_def(id).default.duplicate()
	_changed()


## True when the action's bindings differ from its default.
func is_modified(action: StringName) -> bool:
	var d: UiActions.Def = _reg.get_def(action)
	return d != null and _binds[action] != d.default


func _changed() -> void:
	_reinstall()
	bindings_changed.emit()


# ---- InputMap installation -----------------------------------------------------------------------------------------
## (Re)builds the InputMap for GLOBAL | `context`: one action per binding set (deadzone 0.2), stale events erased.
## Entering GAME / OBSERVER also frees Tab (erases the events of ui_focus_next / ui_focus_prev, spike case R).
func install(context: int) -> void:
	_erase_installed()
	_install_ctx = context
	var mask: int = Context.GLOBAL | context
	for id: StringName in _reg.ids():
		var d: UiActions.Def = _reg.get_def(id)
		if (d.contexts & mask) == 0:
			continue
		var b: PackedInt32Array = _binds[id]
		if b.is_empty():
			continue
		if not InputMap.has_action(id):
			InputMap.add_action(id, 0.2)
			_created[id] = true
		else:
			_saved[id] = InputMap.action_get_events(id)
		InputMap.action_erase_events(id)
		for packed: int in b:
			InputMap.action_add_event(id, event_for(packed))
		_installed[id] = true
	if (context & (Context.GAME | Context.OBSERVER)) != 0:
		_free_tab()
	else:
		_restore_tab()


## Erases every action this keymap installed and restores ui_focus_next / prev (menus and lobby LineEdits need Tab).
func uninstall(_context: int) -> void:
	_erase_installed()
	_install_ctx = 0
	_restore_tab()


## Actions currently in the InputMap on this keymap's behalf.
func installed_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _reg.ids():
		if _installed.has(id):
			out.append(id)
	return out


func _reinstall() -> void:
	if _install_ctx != 0:
		install(_install_ctx)


func _erase_installed() -> void:
	for id: StringName in _installed:
		if _created.has(id):
			if InputMap.has_action(id):
				InputMap.erase_action(id)
		elif InputMap.has_action(id):
			InputMap.action_erase_events(id)
			for ev: Variant in _saved.get(id, []) as Array:
				InputMap.action_add_event(id, ev as InputEvent)
	_installed.clear()
	_created.clear()
	_saved.clear()


func _free_tab() -> void:
	if _tab_freed:
		return
	for a: String in FOCUS_ACTIONS:
		if InputMap.has_action(a):
			_focus_saved[a] = InputMap.action_get_events(a)
			InputMap.action_erase_events(a)
	_tab_freed = true


func _restore_tab() -> void:
	if not _tab_freed:
		return
	for a: String in _focus_saved:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
			for e: InputEvent in _focus_saved[a]:
				InputMap.action_add_event(a, e)
	_focus_saved.clear()
	_tab_freed = false


## The InputMap event for a packed key.
static func event_for(packed: int) -> InputEvent:
	if packed < 0:
		var mb := InputEventMouseButton.new()
		mb.button_index = (-packed) as MouseButton
		return mb
	var k: InputEventKey = unpack(packed)
	return k


# ---- events ---------------------------------------------------------------------------------------------------------
## Exact-match test (`is_action_pressed(a, echo, exact_match = true)`): plain Ctrl+1 never matches the action bound to 1.
## Echo repeats only match when `allow_echo`.
func matches(event: InputEvent, action: StringName, allow_echo: bool = false) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action, allow_echo, true)


## MOD_* bits with the per-OS gesture mapping (5.5.6): Shift = queue, MOD_CTRL = force-fire role (Ctrl; Option on macOS).
func mods_of(ev: InputEventWithModifiers) -> int:
	var mac: bool = (os_name if not os_name.is_empty() else OS.get_name()) == "macOS"
	var m: int = 0
	if ev.shift_pressed:
		m |= MOD_SHIFT
	if mac:
		if ev.alt_pressed:
			m |= MOD_CTRL
	else:
		if ev.ctrl_pressed:
			m |= MOD_CTRL
		if ev.alt_pressed:
			m |= MOD_ALT
	if ev.meta_pressed:
		m |= MOD_META
	return m


## `physical_keycode | modifier mask` of a key event (falls back to `keycode` for hand-made events).
static func pack(ev: InputEventKey) -> int:
	var p: int = ev.get_physical_keycode_with_modifiers()
	if (p & KEY_CODE_MASK) == 0:
		p = ev.get_keycode_with_modifiers()
	return p


## Inverse of `pack` (physical keycode + modifier flags; mouse packs are not keys).
static func unpack(packed: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = (packed & KEY_CODE_MASK) as Key
	ev.shift_pressed = (packed & KEY_MASK_SHIFT) != 0
	ev.ctrl_pressed = (packed & KEY_MASK_CTRL) != 0
	ev.alt_pressed = (packed & KEY_MASK_ALT) != 0
	ev.meta_pressed = (packed & KEY_MASK_META) != 0
	return ev


# ---- persistence ----------------------------------------------------------------------------------------------------
## Stores every modified action as `k:<packed>` / `m:<button>` tokens (an empty array = explicitly unbound); unmodified
## actions are omitted (a missing action means default); entries of actions this build does not know are kept.
func save_to(store: AppSettingsStore) -> void:
	var out: Dictionary = {}
	for a: Variant in store.keys_section():
		if not _reg.has(StringName(str(a))):
			out[a] = store.keys_section()[a]
	for id: StringName in _reg.ids():
		if not is_modified(id):
			continue
		var tokens: PackedStringArray = PackedStringArray()
		for packed: int in _binds[id]:
			tokens.append("m:%d" % -packed if packed < 0 else "k:%d" % packed)
		out[String(id)] = tokens
	store.set_keys_section(out)


## Replaces the bindings with the defaults plus the stored overrides; unknown tokens are dropped, a row whose tokens are
## all unusable keeps the default, a valid empty array unbinds.
func load_from(store: AppSettingsStore) -> void:
	for id: StringName in _reg.ids():
		_binds[id] = _reg.get_def(id).default.duplicate()
	var section: Dictionary = store.keys_section()
	for a: Variant in section:
		var id := StringName(str(a))
		var d: UiActions.Def = _reg.get_def(id)
		if d == null:
			continue
		var tokens: PackedStringArray = section[a]
		var got: PackedInt32Array = PackedInt32Array()
		for tok: String in tokens:
			var packed: int = _parse_token(tok, d)
			if packed != 0 and not got.has(packed) and got.size() < 2:
				got.append(packed)
		if got.is_empty() and not tokens.is_empty():
			continue
		_binds[id] = got
	_changed()


static func _parse_token(tok: String, d: UiActions.Def) -> int:
	if tok.length() < 3 or tok[1] != ":" or not tok.substr(2).is_valid_int():
		return 0
	var n: int = tok.substr(2).to_int()
	if tok[0] == "k" and n > 0 and (n & KEY_CODE_MASK) != 0:
		return n
	if tok[0] == "m" and n > 0 and d.allow_mouse:
		return -n
	return 0


## One line per action: "id  contexts  labels" (QA `UiBindings.dump`).
func dump() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for id: StringName in _reg.ids():
		var d: UiActions.Def = _reg.get_def(id)
		var labels: PackedStringArray = PackedStringArray()
		for packed: int in _binds[id]:
			labels.append(key_label(packed))
		lines.append("%s ctx=%d [%s]" % [id, d.contexts, ", ".join(labels)])
	return "\n".join(lines)
