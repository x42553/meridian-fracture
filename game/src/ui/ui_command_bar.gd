class_name UiCommandBar
extends GridContainer
## Static 4 x 2 order grid (ui.md 5.11.5): attack-move, guard, stop, scatter / deploy, sell, repair, stance. Emits
## `command_pressed(id)`; the presenter enables the buttons from the selection's capabilities (`apply_caps`) and marks
## armed modes. Hotkey labels are the default keymap's (UiKeymap owns the real ones); every button has a tooltip.

signal command_pressed(id: StringName)

const COMMANDS: Array[Dictionary] = [
	{"id": &"attack_move", "glyph": UiGlyphs.Glyph.ATTACK_MOVE, "toggle": true, "key": "A", "title": "Attack-move", "text": "Move and engage everything on the way."},
	{"id": &"guard", "glyph": UiGlyphs.Glyph.GUARD, "toggle": true, "key": "G", "title": "Guard", "text": "Guard a unit or a point; return after a chase."},
	{"id": &"stop", "glyph": UiGlyphs.Glyph.STOP, "toggle": false, "key": "S", "title": "Stop", "text": "Cancel every order."},
	{"id": &"scatter", "glyph": UiGlyphs.Glyph.SCATTER, "toggle": false, "key": "X", "title": "Scatter", "text": "Spread the selected units out."},
	{"id": &"deploy", "glyph": UiGlyphs.Glyph.DEPLOY, "toggle": false, "key": "D", "title": "Deploy", "text": "Deploy or undeploy the selected units."},
	{"id": &"sell", "glyph": UiGlyphs.Glyph.SELL, "toggle": true, "key": "Del", "title": "Sell", "text": "Click a structure to sell it for a refund."},
	{"id": &"repair", "glyph": UiGlyphs.Glyph.REPAIR, "toggle": true, "key": "R", "title": "Repair", "text": "Click a structure to toggle repair."},
	{"id": &"stance", "glyph": UiGlyphs.Glyph.STANCE, "toggle": false, "key": "Z", "title": "Stance", "text": "Cycle aggressive, defensive, hold fire, guard."},
]

var _buttons: Dictionary = {}  ## id -> UiIconButton


func _init() -> void:
	columns = 4
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", UiMetrics.COMMAND_GAP)
	add_theme_constant_override("v_separation", UiMetrics.COMMAND_GAP)
	for c: Dictionary in COMMANDS:
		var b := UiIconButton.new()
		b.glyph = int(c["glyph"])
		b.hotkey = String(c["key"])
		b.custom_minimum_size = Vector2(float(UiMetrics.COMMAND_BTN), float(UiMetrics.COMMAND_BTN))
		b.set_tip({"title": "%s  [%s]" % [c["title"], c["key"]], "text": String(c["text"])})
		var id: StringName = c["id"]
		b.pressed.connect(func() -> void: command_pressed.emit(id))
		add_child(b)
		_buttons[id] = b


func button(id: StringName) -> UiIconButton:
	return _buttons.get(id) as UiIconButton


func set_armed(id: StringName, armed: bool) -> void:
	var b: UiIconButton = button(id)
	if b != null:
		b.active = armed


func set_enabled(id: StringName, enabled: bool) -> void:
	var b: UiIconButton = button(id)
	if b != null:
		b.set_enabled(enabled)


func set_glyph(id: StringName, glyph: int) -> void:
	var b: UiIconButton = button(id)
	if b != null:
		b.glyph = glyph


## Enablement per 5.11.5 from the selection's aggregated capability bits and mode.
func apply_caps(caps_any: int, sel_mode: int, has_sellable: bool) -> void:
	var armed: bool = (caps_any & UiUnitCaps.CAP_ARMED) != 0
	var mobile: bool = (caps_any & UiUnitCaps.CAP_MOBILE) != 0
	var producer: bool = (caps_any & UiUnitCaps.CAP_PRODUCER) != 0
	var foreign: bool = sel_mode == UiSelection.Mode.FOREIGN
	set_enabled(&"attack_move", not foreign and armed and mobile)
	set_enabled(&"guard", not foreign and armed and mobile)
	set_enabled(&"stop", not foreign and (mobile or producer))
	set_enabled(&"scatter", not foreign and mobile)
	set_enabled(&"deploy", not foreign and (caps_any & UiUnitCaps.CAP_DEPLOY) != 0)
	set_enabled(&"sell", not foreign)
	set_enabled(&"repair", not foreign)
	set_enabled(&"stance", not foreign and armed and mobile)
	if sel_mode == UiSelection.Mode.STRUCTURES and not has_sellable:
		set_enabled(&"sell", false)
