class_name UiBottomPanel
extends VBoxContainer
## Bottom-centre stack (ui.md 5.11): the control-group badges above the selection panel. `set_playfield` sizes the
## panel to the free world width (`UiLayout.bottom_panel_width`); the HUD anchors the stack to the bottom centre.

signal group_pressed(index: int, double: bool)
signal tile_pressed(index: int, mods: int)
signal command_pressed(id: StringName)
signal utility_pressed(id: StringName)
signal ability_pressed(slot: int)
signal ability_right_pressed(slot: int)

var observer: bool = false
var _groups: UiGroupBar = null
var _panel: UiSelectionPanel = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	_groups = UiGroupBar.new()
	_groups.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_groups.group_pressed.connect(func(i: int, d: bool) -> void: group_pressed.emit(i, d))
	add_child(_groups)
	_panel = UiSelectionPanel.new()
	_panel.custom_minimum_size = Vector2(880.0, float(UiMetrics.BOTTOM_H))
	_panel.tile_pressed.connect(func(i: int, m: int) -> void: tile_pressed.emit(i, m))
	_panel.command_pressed.connect(func(id: StringName) -> void: command_pressed.emit(id))
	_panel.utility_pressed.connect(func(id: StringName) -> void: utility_pressed.emit(id))
	_panel.ability_pressed.connect(func(s: int) -> void: ability_pressed.emit(s))
	_panel.ability_right_pressed.connect(func(s: int) -> void: ability_right_pressed.emit(s))
	add_child(_panel)


func group_bar() -> UiGroupBar:
	return _groups


## Observer HUD: no control-group badges, no command grid; the panel shows up only while something is selected.
func set_observer(on: bool) -> void:
	observer = on
	_panel.set_observer(on)
	_groups.visible = not on
	if on:
		visible = false


func panel() -> UiSelectionPanel:
	return _panel


func selection_view() -> UiSelectionView:
	return _panel.selection_view()


func commands() -> UiCommandBar:
	return _panel.commands()


func abilities() -> UiAbilityBar:
	return _panel.abilities()


## Sizes the panel for `playfield_w` logical px of free world width.
func set_playfield(playfield_w: float, size_class: int) -> void:
	var w: float = UiLayout.bottom_panel_width(playfield_w, size_class)
	_panel.custom_minimum_size = Vector2(w, float(UiMetrics.BOTTOM_H))
	_groups.visible = not observer
