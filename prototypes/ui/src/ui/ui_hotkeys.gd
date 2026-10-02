class_name UiHotkeys
extends RefCounted
## Runtime-built InputMap. Every gameplay key is an *action* so it can be rebound and shown in tooltips.
## Letters use `physical_keycode` (position-based: WASD-style grids stay ergonomic on AZERTY/QWERTZ), function
## and digit keys too. Modifiers are expressed on the event, so ctrl+1 and 1 are two different events of the
## same physical key (exact_match = true when polling).
## GOTCHA (verified in UiInputLab N2/O): a focused Button eats arrow keys when focus navigation has a neighbour
## to move to, and SPACE/ENTER 'press' it -> HUD controls must use focus_mode = FOCUS_NONE and Tab must be freed
## from ui_focus_next/prev (done in install()). See UiInputController for the full pattern.

const DEFAULTS: Dictionary = {
	&"cmd_attack_move": [KEY_A],
	&"cmd_guard": [KEY_G],
	&"cmd_stop": [KEY_S],
	&"cmd_scatter": [KEY_X],
	&"cmd_deploy": [KEY_D],
	&"cmd_sell": [KEY_F5],
	&"cmd_repair": [KEY_F6],
	&"cmd_waypoint": [KEY_W],
	&"cam_left": [KEY_LEFT],
	&"cam_right": [KEY_RIGHT],
	&"cam_up": [KEY_UP],
	&"cam_down": [KEY_DOWN],
	&"cam_rotate_left": [KEY_Q],
	&"cam_rotate_right": [KEY_E],
	&"cam_center_base": [KEY_HOME],
	&"cam_jump_alert": [KEY_SPACE],
	&"select_all_type": [KEY_T],
	&"toggle_menu": [KEY_ESCAPE],
	&"chat_open": [KEY_ENTER],
	&"tab_next": [KEY_TAB],
}

static func install() -> void:
	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for k in DEFAULTS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k as Key
			InputMap.action_add_event(action, ev)
	for i in 10:
		var digit: Key = (KEY_0 + i) as Key
		for prefix in ["group_select_", "group_assign_", "group_add_"]:
			var a := StringName("%s%d" % [prefix, i])
			if not InputMap.has_action(a):
				InputMap.add_action(a)
			InputMap.action_erase_events(a)
			var ev2 := InputEventKey.new()
			ev2.physical_keycode = digit
			ev2.ctrl_pressed = prefix == "group_assign_"
			ev2.shift_pressed = prefix == "group_add_"
			InputMap.action_add_event(a, ev2)
	# Tab / arrows / space / enter double as GUI focus navigation: drop the ui_* bindings so a stray
	# focused Control can never swallow them, and so Tab is free for gameplay.
	for ui in [&"ui_focus_next", &"ui_focus_prev"]:
		InputMap.action_erase_events(ui)

## Human-readable key of the first event bound to an action ("A", "F5", "Ctrl+1").
static func label_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k != null:
			return k.as_text_physical_keycode().replace("Escape", "Esc")
	return ""
