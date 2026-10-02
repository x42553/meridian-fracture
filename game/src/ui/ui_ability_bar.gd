class_name UiAbilityBar
extends HBoxContainer
## Utility row + dynamic ability slots under the command grid (ui.md 5.11.5 / 5.11.6): fixed context-dependent buttons
## (Hold H, Patrol P, Follow F, Return V, Unload U) followed by at most four ability slots of the active subgroup
## (mode switch, portable cover, decoy, sensor puck, smoke ...), five buttons in total. Buttons are shown only when they
## apply. `set_buttons` takes [{id, glyph, slot (-1 = utility), enabled, active, hotkey, title, text, autocast}].

signal utility_pressed(id: StringName)
signal ability_pressed(slot: int)
signal ability_right_pressed(slot: int)

const MAX_BUTTONS: int = 5
const ABILITY_KEYS: PackedStringArray = ["I", "O", "K", "L"]

var _pool: Array[UiIconButton] = []
var _shown: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiMetrics.COMMAND_GAP)
	for i: int in MAX_BUTTONS:
		var b := UiIconButton.new()
		b.custom_minimum_size = Vector2(float(UiMetrics.ABILITY_BTN), float(UiMetrics.ABILITY_BTN))
		b.visible = false
		var idx: int = i
		b.pressed.connect(func() -> void: _on_pressed(idx))
		b.right_pressed.connect(func() -> void: _on_right(idx))
		add_child(b)
		_pool.append(b)


## Shows up to five buttons (utility first, then abilities); the rest is hidden.
func set_buttons(list: Array[Dictionary]) -> void:
	_shown = list
	for i: int in MAX_BUTTONS:
		var b: UiIconButton = _pool[i]
		if i >= list.size():
			b.visible = false
			continue
		var d: Dictionary = list[i]
		b.visible = true
		b.glyph = int(d.get("glyph", UiGlyphs.Glyph.MODE))
		b.hotkey = String(d.get("hotkey", ""))
		b.badge = "A" if bool(d.get("autocast", false)) else ""
		b.active = bool(d.get("active", false))
		b.set_enabled(bool(d.get("enabled", true)))
		b.set_tip({"title": String(d.get("title", "")), "text": String(d.get("text", ""))})


func button_count() -> int:
	return _shown.size()


func button_at(i: int) -> UiIconButton:
	return _pool[i] if i >= 0 and i < MAX_BUTTONS else null


func _on_pressed(i: int) -> void:
	if i >= _shown.size():
		return
	var d: Dictionary = _shown[i]
	var slot: int = int(d.get("slot", -1))
	if slot >= 0:
		ability_pressed.emit(slot)
	else:
		utility_pressed.emit(StringName(d.get("id", &"")))


func _on_right(i: int) -> void:
	if i >= _shown.size():
		return
	var slot: int = int(_shown[i].get("slot", -1))
	if slot >= 0:
		ability_right_pressed.emit(slot)
