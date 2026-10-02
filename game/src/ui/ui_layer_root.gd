class_name UiLayerRoot
extends Control
## Full-rect Control directly under a CanvasLayer; carries the `theme` (ui.md 2.3, pitfalls P1 / P2).
## `Window.theme` is NOT inherited by Controls below a CanvasLayer, so the theme is assigned here and inherited by
## everything below. Anchors are set with `set_anchors_and_offsets_preset` (set_anchors_preset alone left the size at 0
## under a CanvasLayer). `MOUSE_FILTER_IGNORE`: the root never eats world clicks. Registers with `UiThemeService`.


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _enter_tree() -> void:
	UiThemeService.instance().register_root(self)


func _exit_tree() -> void:
	UiThemeService.instance().unregister_root(self)


## Makes `c` fill its parent (the correct call for code-built full-rect Controls, P2).
static func fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
