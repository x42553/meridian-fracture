class_name UiScreen
extends Control
## Base class of every screen (ui.md 3.5). Lifecycle: `enter(params)` after the screen is in the tree, `exit()` before it
## is freed (release ports, tweens, sockets). Full-rect, `MOUSE_FILTER_IGNORE` by default (HUD screens must let world clicks
## through, spike A); menu screens that need a click-blocking backdrop add their own STOP child.
## Escape chain (5.5.7, last link): `handle_escape()` = `on_escape()` (closes a popup) else `can_leave()` -> `back_requested`.
## Open dialogs consume Escape first (`UiDialogStack`).

## The screen asks its host to go back (Esc on the root of a menu).
signal back_requested()
## The screen asks its host to open another screen.
signal navigate(target: StringName, params: Dictionary)

var screen_id: StringName = &""
## `UiKeymap.Context` installed while the screen is active (0 = none yet; the keymap belongs to UI-09a).
var keymap_context: int = 0
## Escape presses call `handle_escape()` from `_unhandled_key_input` (off for the game screen, whose controller owns Esc).
var handles_escape: bool = true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Virtual: called once the screen is in the tree. `params` are documented per screen (ui.md 3.5).
func enter(_params: Dictionary) -> void:
	pass


## Virtual: release everything the screen started.
func exit() -> void:
	pass


## Virtual (menus): the control that receives focus first.
func default_focus() -> Control:
	return null


## Virtual: true when Escape was handled (closed a popup, collapsed a panel); false -> `back_requested`.
func on_escape() -> bool:
	return false


## Virtual: false when the screen shows its own confirm dialog before leaving.
func can_leave() -> bool:
	return true


## Menu focus setup: interactive controls take focus (`UiFocusPolicy.apply_menu`) and `default_focus()` grabs it.
func setup_menu_focus() -> void:
	UiFocusPolicy.apply_menu(self)
	var c: Control = default_focus()
	if c != null and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()


## The escape chain of one screen; returns true when the press was consumed.
func handle_escape() -> bool:
	if on_escape():
		return true
	if can_leave():
		back_requested.emit()
		return true
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if handles_escape and is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		if handle_escape():
			get_viewport().set_input_as_handled()
