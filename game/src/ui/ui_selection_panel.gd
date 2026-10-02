class_name UiSelectionPanel
extends PanelContainer
## Bottom-centre panel (ui.md 5.11.4): the selection view (portrait, tiles) on the left, the 4 x 2 command grid with
## the utility / ability row on the right. Pure composition; every signal is forwarded to the HUD.

signal tile_pressed(index: int, mods: int)
signal command_pressed(id: StringName)
signal utility_pressed(id: StringName)
signal ability_pressed(slot: int)
signal ability_right_pressed(slot: int)

var _view: UiSelectionView = null
var _commands: UiCommandBar = null
var _abilities: UiAbilityBar = null
var _sep: VSeparator = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	add_child(hb)
	_view = UiSelectionView.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.tile_pressed.connect(func(i: int, m: int) -> void: tile_pressed.emit(i, m))
	hb.add_child(_view)
	_sep = VSeparator.new()
	hb.add_child(_sep)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiMetrics.COMMAND_GAP)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(col)
	_commands = UiCommandBar.new()
	_commands.command_pressed.connect(func(id: StringName) -> void: command_pressed.emit(id))
	col.add_child(_commands)
	_abilities = UiAbilityBar.new()
	_abilities.utility_pressed.connect(func(id: StringName) -> void: utility_pressed.emit(id))
	_abilities.ability_pressed.connect(func(s: int) -> void: ability_pressed.emit(s))
	_abilities.ability_right_pressed.connect(func(s: int) -> void: ability_right_pressed.emit(s))
	col.add_child(_abilities)


func selection_view() -> UiSelectionView:
	return _view


## Observer HUD: the panel only informs (no command grid, no abilities).
func set_observer(on: bool) -> void:
	_sep.visible = not on
	_commands.get_parent().visible = not on


func commands() -> UiCommandBar:
	return _commands


func abilities() -> UiAbilityBar:
	return _abilities
