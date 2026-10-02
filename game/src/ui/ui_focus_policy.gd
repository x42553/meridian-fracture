class_name UiFocusPolicy
extends RefCounted
## Keyboard-focus policy (ui.md 5.19.4, spike 10). Menus: every interactive control takes focus (Tab / arrows /
## Enter / Esc, styled focus ring). HUD: every control is `FOCUS_NONE`, otherwise arrow keys and Space are consumed
## by a focused Button before the game's key handling sees them (spike cases N-R).


## Focus mode of the Controls that count as interactive in menus.
static func is_interactive(c: Control) -> bool:
	return c is BaseButton or c is LineEdit or c is TextEdit or c is Slider or c is SpinBox or c is ItemList or c is Tree or c is TabBar or c is UiListRow or c is UiTabBar


## Menu screen: interactive controls FOCUS_ALL, everything else untouched. Recursive.
static func apply_menu(root: Node) -> void:
	for n in root.find_children("*", "Control", true, false):
		var c: Control = n as Control
		if is_interactive(c) and c.focus_mode == Control.FOCUS_NONE:
			c.focus_mode = Control.FOCUS_ALL


## HUD: FOCUS_NONE on `root` and every Control below (also LineEdit unless `keep_text_inputs`, e.g. the chat box).
static func apply_hud(root: Node, keep_text_inputs: bool = true) -> void:
	var rc: Control = root as Control
	if rc != null:
		rc.focus_mode = Control.FOCUS_NONE
	for n in root.find_children("*", "Control", true, false):
		var c: Control = n as Control
		if keep_text_inputs and (c is LineEdit or c is TextEdit):
			continue
		c.focus_mode = Control.FOCUS_NONE


## True while a text input owns keyboard focus (gate camera keys on this, ui.md 5.5.8).
static func text_entry_active(vp: Viewport) -> bool:
	var f: Control = vp.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
