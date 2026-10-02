class_name AppFlow
extends RefCounted
## Pure screen-flow graph (ui.md 3.1, 5.1): modes, allowed edges (`can_go`, the table of 5.1.2), the overlay push/pop stack
## and per-mode params. No SceneTree; unit-tested. An illegal transition is refused and logged.

enum Mode { BOOT = 0, MAIN_MENU = 1, SKIRMISH_LOBBY = 2, LAN_BROWSER = 3, LAN_LOBBY = 4, LOADING = 5, IN_MATCH = 6,
		END_SCREEN = 7, REPLAYS = 8, REPLAY_PLAYBACK = 9, OPTIONS = 10, CREDITS = 11, FIELD_MANUAL = 12, FATAL = 13, QUIT = 14,
		CAMPAIGN = 15, MISSION_BRIEFING = 16 }

## Modes entered with `push` (return with `pop`).
const OVERLAYS: Array[int] = [Mode.OPTIONS, Mode.CREDITS, Mode.FIELD_MANUAL]

const _NAMES: PackedStringArray = ["BOOT", "MAIN_MENU", "SKIRMISH_LOBBY", "LAN_BROWSER", "LAN_LOBBY", "LOADING", "IN_MATCH",
	"END_SCREEN", "REPLAYS", "REPLAY_PLAYBACK", "OPTIONS", "CREDITS", "FIELD_MANUAL", "FATAL", "QUIT", "CAMPAIGN", "MISSION_BRIEFING"]

static var _edges: Dictionary = {}

var mode: int = Mode.BOOT
var params: Dictionary = {}
## Entries `{mode, params}` of the modes below the current overlay.
var _stack: Array[Dictionary] = []


static func mode_name(m: int) -> String:
	return _NAMES[m] if m >= 0 and m < _NAMES.size() else "?"


static func _table() -> Dictionary:
	if _edges.is_empty():
		var m: Dictionary = {}
		m[Mode.BOOT] = [Mode.MAIN_MENU, Mode.FATAL, Mode.LOADING]
		m[Mode.MAIN_MENU] = [Mode.SKIRMISH_LOBBY, Mode.LAN_BROWSER, Mode.REPLAYS, Mode.OPTIONS, Mode.CREDITS, Mode.FIELD_MANUAL, Mode.QUIT, Mode.CAMPAIGN]
		m[Mode.SKIRMISH_LOBBY] = [Mode.MAIN_MENU, Mode.LOADING, Mode.FIELD_MANUAL, Mode.OPTIONS]
		m[Mode.LAN_BROWSER] = [Mode.LAN_LOBBY, Mode.MAIN_MENU]
		m[Mode.LAN_LOBBY] = [Mode.LAN_BROWSER, Mode.LOADING, Mode.FIELD_MANUAL, Mode.OPTIONS]
		m[Mode.LOADING] = [Mode.IN_MATCH, Mode.SKIRMISH_LOBBY, Mode.LAN_LOBBY, Mode.MAIN_MENU, Mode.REPLAY_PLAYBACK, Mode.REPLAYS, Mode.CAMPAIGN]
		m[Mode.IN_MATCH] = [Mode.END_SCREEN, Mode.MAIN_MENU, Mode.OPTIONS, Mode.FIELD_MANUAL, Mode.CAMPAIGN]
		m[Mode.END_SCREEN] = [Mode.MAIN_MENU, Mode.SKIRMISH_LOBBY, Mode.LAN_LOBBY, Mode.LOADING, Mode.REPLAY_PLAYBACK, Mode.CAMPAIGN, Mode.MISSION_BRIEFING]
		m[Mode.CAMPAIGN] = [Mode.MAIN_MENU, Mode.MISSION_BRIEFING, Mode.LOADING, Mode.OPTIONS, Mode.FIELD_MANUAL]
		m[Mode.MISSION_BRIEFING] = [Mode.CAMPAIGN, Mode.LOADING, Mode.MAIN_MENU, Mode.OPTIONS, Mode.FIELD_MANUAL]
		m[Mode.REPLAYS] = [Mode.LOADING, Mode.REPLAY_PLAYBACK, Mode.MAIN_MENU]
		m[Mode.REPLAY_PLAYBACK] = [Mode.REPLAYS, Mode.MAIN_MENU, Mode.OPTIONS, Mode.FIELD_MANUAL, Mode.CAMPAIGN]
		m[Mode.OPTIONS] = []
		m[Mode.CREDITS] = []
		m[Mode.FIELD_MANUAL] = []
		m[Mode.FATAL] = [Mode.MAIN_MENU, Mode.QUIT]
		m[Mode.QUIT] = []
		_edges = m
	return _edges


## The edge table of 5.1.2. Every mode except FATAL and QUIT may go to FATAL (`AppCrash.show`).
static func can_go(from: int, to: int) -> bool:
	if to == Mode.FATAL:
		return from != Mode.FATAL and from != Mode.QUIT
	var list: Variant = _table().get(from)
	return list != null and (list as Array).has(to)


## Screen id of a mode (`AppScreens`); QUIT has none. `p`: the mode's params; a mission end (`p.mission` = the result model of
## `AppMission.result_model`) shows `mission_result` instead of `end`.
static func screen_id_of(m: int, p: Dictionary = {}) -> StringName:
	match m:
		Mode.BOOT:
			return &"splash"
		Mode.MAIN_MENU:
			return &"main_menu"
		Mode.SKIRMISH_LOBBY, Mode.LAN_LOBBY:
			return &"lobby"
		Mode.LAN_BROWSER:
			return &"lan_browser"
		Mode.LOADING:
			return &"loading"
		Mode.IN_MATCH, Mode.REPLAY_PLAYBACK:
			return &"game"
		Mode.END_SCREEN:
			return &"mission_result" if p.has("mission") else &"end"
		Mode.REPLAYS:
			return &"replays"
		Mode.OPTIONS:
			return &"options"
		Mode.CREDITS:
			return &"credits"
		Mode.FIELD_MANUAL:
			return &"field_manual"
		Mode.FATAL:
			return &"fatal"
		Mode.CAMPAIGN:
			return &"campaign"
		Mode.MISSION_BRIEFING:
			return &"mission_briefing"
	return &""


## Mode a screen id navigates to (`navigate(target, params)`); `-1` for an unknown id. `lobby` uses `params.lan`, `game`
## uses `params.replay`.
static func mode_of_screen(id: StringName, p: Dictionary = {}) -> int:
	match id:
		&"splash":
			return Mode.BOOT
		&"main_menu":
			return Mode.MAIN_MENU
		&"lobby":
			return Mode.LAN_LOBBY if bool(p.get("lan", false)) else Mode.SKIRMISH_LOBBY
		&"lan_browser":
			return Mode.LAN_BROWSER
		&"loading":
			return Mode.LOADING
		&"game":
			return Mode.REPLAY_PLAYBACK if bool(p.get("replay", false)) else Mode.IN_MATCH
		&"end", &"mission_result":
			return Mode.END_SCREEN
		&"campaign":
			return Mode.CAMPAIGN
		&"mission_briefing":
			return Mode.MISSION_BRIEFING
		&"replays":
			return Mode.REPLAYS
		&"options":
			return Mode.OPTIONS
		&"credits":
			return Mode.CREDITS
		&"field_manual":
			return Mode.FIELD_MANUAL
		&"fatal":
			return Mode.FATAL
	return -1


## The mode Back/Esc returns to from a mode (-1 = none: menus, match, fatal). Overlays return with `pop`.
static func back_of(m: int) -> int:
	match m:
		Mode.SKIRMISH_LOBBY, Mode.LAN_BROWSER, Mode.REPLAYS, Mode.END_SCREEN, Mode.LOADING, Mode.CAMPAIGN:
			return Mode.MAIN_MENU
		Mode.MISSION_BRIEFING:
			return Mode.CAMPAIGN
		Mode.LAN_LOBBY:
			return Mode.LAN_BROWSER
		Mode.REPLAY_PLAYBACK:
			return Mode.REPLAYS
	return -1


static func is_overlay(m: int) -> bool:
	return OVERLAYS.has(m)


## Goes to `to` when the edge is legal (clears the overlay stack; an overlay mode is pushed instead). False + a warning otherwise.
func go(to: int, p: Dictionary = {}) -> bool:
	if not can_go(mode, to):
		Log.warn("app", "flow: illegal transition %s -> %s" % [mode_name(mode), mode_name(to)])
		return false
	if is_overlay(to):
		return push(to, p)
	_stack.clear()
	mode = to
	params = p
	return true


## Overlay (options / field manual / credits over a menu, lobby or match); the mode below stays alive.
func push(to: int, p: Dictionary = {}) -> bool:
	if not is_overlay(to) or not can_go(_base_mode(), to) or (not _stack.is_empty() and is_overlay(mode) and mode == to):
		Log.warn("app", "flow: illegal push %s -> %s" % [mode_name(mode), mode_name(to)])
		return false
	_stack.append({"mode": mode, "params": params})
	mode = to
	params = p
	return true


## Returns the mode returned to, or -1 when nothing is stacked.
func pop() -> int:
	if _stack.is_empty():
		return -1
	var top: Dictionary = _stack.pop_back()
	mode = int(top["mode"])
	params = top["params"] as Dictionary
	return mode


func stack_depth() -> int:
	return _stack.size()


## Debug/test: sets the mode without checking the edge (`--screen=<id>`).
func force(m: int, p: Dictionary = {}) -> void:
	_stack.clear()
	mode = m
	params = p


func _base_mode() -> int:
	return int((_stack[0] as Dictionary)["mode"]) if not _stack.is_empty() else mode
