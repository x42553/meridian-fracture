class_name UiActionNames
extends RefCounted
## English names and category titles of the rebindable actions (ui.md 5.6, options Controls page). Numbered families
## ("group_select_3", "card_2", "card_5x_2") share one pattern; everything else has an explicit name. Unknown ids fall back to
## a humanised id, so a new action in `keymap_defaults.json` is usable before it gets a name here.

const CATEGORY_ORDER: PackedStringArray = ["camera", "selection", "orders", "tools", "sidebar", "powers", "interface", "observer"]
const CATEGORY_TITLES: Dictionary = {
	"camera": "Camera", "selection": "Selection and groups", "orders": "Orders", "tools": "Tools", "sidebar": "Build sidebar",
	"powers": "Powers", "interface": "Interface", "observer": "Observer and replay",
}
const NAMES: Dictionary = {
	"cam_pan_left": "Pan left", "cam_pan_right": "Pan right", "cam_pan_up": "Pan up", "cam_pan_down": "Pan down",
	"cam_rotate_left": "Rotate left", "cam_rotate_right": "Rotate right", "cam_tilt_up": "Tilt up", "cam_tilt_down": "Tilt down",
	"cam_zoom_in": "Zoom in", "cam_zoom_out": "Zoom out", "cam_center_base": "Centre on base", "cam_center_selection": "Centre on selection",
	"cam_jump_alert": "Jump to last alert", "cam_reset": "Reset camera", "cam_orbit": "Orbit (hold)", "toggle_edge_scroll": "Toggle edge scrolling",
	"sel_all_military": "Select all combat units", "sel_all_military_screen": "Select all combat units on screen",
	"sel_same_screen": "Select same type on screen", "sel_same_map": "Select same type everywhere", "sel_idle_next": "Next idle unit",
	"sel_idle_prev": "Previous idle unit", "sel_collector_next": "Next collector", "sel_producer_next": "Next producer",
	"sel_hq": "Select headquarters", "sel_subgroup_next": "Cycle sub-group", "sel_group_next": "Next control group",
	"cmd_attack_move": "Attack-move", "cmd_move": "Move", "cmd_guard": "Guard", "cmd_patrol": "Patrol", "cmd_stop": "Stop",
	"cmd_scatter": "Scatter", "cmd_hold": "Hold position", "cmd_follow": "Follow", "cmd_deploy": "Deploy", "cmd_stance_cycle": "Cycle stance",
	"cmd_force_fire_mode": "Force fire", "cmd_return": "Return to base", "cmd_unload": "Unload", "cmd_scuttle": "Scuttle", "cmd_ping": "Ping map",
	"tool_repair": "Repair tool", "tool_sell": "Sell tool", "tool_rally": "Rally point tool", "tool_waypoint": "Waypoint mode",
	"place_rotate": "Rotate placement", "tab_next": "Next build tab", "tab_prev": "Previous build tab", "superweapon": "Superweapon",
	"toggle_menu": "Game menu", "pause_game": "Pause", "chat_all": "Chat to all", "chat_team": "Chat to team", "open_field_manual": "Field Manual",
	"toggle_scoreboard": "Scoreboard", "toggle_objectives": "Mission objectives", "toggle_net_overlay": "Network overlay", "hide_ui": "Hide interface", "screenshot": "Screenshot",
	"toggle_fullscreen": "Toggle fullscreen", "obs_all": "Observe all players", "obs_next_player": "Next player", "obs_toggle_fog": "Toggle fog of war",
	"obs_pause": "Pause replay", "obs_speed_up": "Faster replay", "obs_speed_down": "Slower replay",
	"obs_follow": "Follow the viewed player", "obs_event_next": "Next replay event", "obs_event_prev": "Previous replay event",
	"obs_seek_back": "Back 10 seconds", "obs_seek_fwd": "Forward 10 seconds",
}
const FAMILIES: Array[Array] = [
	["cam_bookmark_set_", "Set camera bookmark %s"], ["cam_bookmark_", "Go to camera bookmark %s"],
	["group_select_", "Select group %s"], ["group_assign_", "Assign group %s"], ["group_add_", "Add selection to group %s"],
	["group_append_", "Add group %s to selection"], ["cmd_ability_", "Ability %s"], ["power_", "Support power %s"],
	["obs_player_", "Observe player %s"],
]


static func title_of(category: String) -> String:
	return str(CATEGORY_TITLES.get(category, UiFmText.humanize(category)))


static func label(id: String) -> String:
	if NAMES.has(id):
		return str(NAMES[id])
	for fam: Array in FAMILIES:
		var prefix: String = fam[0]
		if id.begins_with(prefix) and id.substr(prefix.length()).is_valid_int():
			return str(fam[1]) % id.substr(prefix.length())
	if id.begins_with("card_5x_"):
		return "Build card %s (queue 5)" % id.substr(8)
	if id.begins_with("card_") and id.substr(5).is_valid_int():
		return "Build card %s" % id.substr(5)
	return UiFmText.humanize(id)
