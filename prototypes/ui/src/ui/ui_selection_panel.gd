class_name UiSelectionPanel
extends PanelContainer
## Bottom-centre panel: selection view (portrait + tiles) on the left, command bar on the right.

signal tile_clicked(index: int, shift: bool, ctrl: bool)
signal command(id: StringName)

var view: UiSelectionView
var commands: UiCommandBar

func setup(skin: UiSkin) -> UiSelectionPanel:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	add_child(hb)
	view = UiSelectionView.new()
	view.skin = skin
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.tile_clicked.connect(func(i: int, s: bool, c: bool) -> void: tile_clicked.emit(i, s, c))
	hb.add_child(view)
	var sep := VSeparator.new()
	hb.add_child(sep)
	commands = UiCommandBar.new().setup(skin)
	commands.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	commands.command.connect(func(id: StringName) -> void: command.emit(id))
	hb.add_child(commands)
	return self
