class_name UiCommandBar
extends GridContainer
## 4x2 grid of order buttons (attack-move, guard, stop, scatter, deploy, sell, repair, waypoint).
## Emits `command(id)`; toggle-style commands (sell/repair/attack-move) stay armed until used or cancelled,
## which matches the C&C cursor-mode model. Hotkeys are shown from the InputMap, never hard-coded here.

signal command(id: StringName)

const COMMANDS: Array[Dictionary] = [
	{"id": &"attack_move", "glyph": UiGlyphs.Glyph.ATTACK_MOVE, "toggle": true, "action": &"cmd_attack_move"},
	{"id": &"guard", "glyph": UiGlyphs.Glyph.GUARD, "toggle": false, "action": &"cmd_guard"},
	{"id": &"stop", "glyph": UiGlyphs.Glyph.STOP, "toggle": false, "action": &"cmd_stop"},
	{"id": &"scatter", "glyph": UiGlyphs.Glyph.SCATTER, "toggle": false, "action": &"cmd_scatter"},
	{"id": &"deploy", "glyph": UiGlyphs.Glyph.DEPLOY, "toggle": false, "action": &"cmd_deploy"},
	{"id": &"sell", "glyph": UiGlyphs.Glyph.SELL, "toggle": true, "action": &"cmd_sell"},
	{"id": &"repair", "glyph": UiGlyphs.Glyph.REPAIR, "toggle": true, "action": &"cmd_repair"},
	{"id": &"waypoint", "glyph": UiGlyphs.Glyph.WAYPOINT, "toggle": true, "action": &"cmd_waypoint"},
]

var _buttons: Dictionary = {}

func _init() -> void:
	columns = 4
	add_theme_constant_override("h_separation", 5)
	add_theme_constant_override("v_separation", 5)

func setup(skin: UiSkin) -> UiCommandBar:
	for c in COMMANDS:
		var b := UiIconButton.new()
		b.glyph = c["glyph"]
		b.toggle_mode = c["toggle"]
		b.accent = skin.accent
		b.hotkey = UiHotkeys.label_for(c["action"])
		b.tooltip_text = "%s  [%s]" % [String(c["id"]).replace("_", " ").capitalize(), b.hotkey]
		b.custom_minimum_size = Vector2(48.0, 48.0)
		var id: StringName = c["id"]
		b.pressed.connect(func() -> void: command.emit(id))
		add_child(b)
		_buttons[id] = b
	return self

func button(id: StringName) -> UiIconButton:
	return _buttons.get(id)

func set_armed(id: StringName, armed: bool) -> void:
	var b: UiIconButton = button(id)
	if b != null:
		b.active = armed

func set_enabled(id: StringName, enabled: bool) -> void:
	var b: UiIconButton = button(id)
	if b != null:
		b.set_enabled(enabled)
