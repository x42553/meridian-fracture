class_name AppQuitHook
extends Node
## Test hook (task HARD1, driver `tools/py/quit_stress.py`): quits the process a chosen time after the app reaches a chosen phase, to
## prove that every phase of the app exits cleanly.
##   --quit-at-phase=<phase>   splash (= boot) | main_menu | skirmish_lobby | lan_browser | lan_lobby | loading | loading_map |
##                             loading_world | loading_view | loading_view_<stage: materials|terrain|models|fx|done> | in_match | end_screen | replays | replay_playback | options | credits |
##                             field_manual | any (the first frame). A parent phase matches its sub-phases (`loading` = every loading phase).
##   --quit-after-ms=<n>       real milliseconds after the phase was first seen (default 0)
##   --quit-mode=tree|close|state|raw   `tree` (default): the orderly start (`AppShutdown.begin_quit`, two frames) then `SceneTree.quit`, like the test
##                             boots / QA code | `close`: the window's close request (what the close button / Cmd+Q sends) | `state`:
##                             `AppState.quit_game` (the menu's Quit) | `raw`: a bare `SceneTree.quit()` with no cooperation at all (dev_shot style;
##                             coroutines still suspended at exit make the engine print leak lines, but it must never hang)
## Prints `QUITHOOK phase=<p> after_ms=<n> mode=<m> at_ms=<since process start>` just before it quits. Inert without `--quit-at-phase`
## or `--quit-after-ms`. Presentation / tooling only: never touches the sim.

var phase_wanted: String = "any"
var after_ms: int = 0
var mode: String = "tree"
var fired: bool = false

var _seen_ms: int = -1


## Adds the hook under `host` when the flags ask for it; null otherwise.
static func install(host: Node, args: AppLaunchArgs) -> AppQuitHook:
	if host == null or not (args.extras.has("quit-at-phase") or args.extras.has("quit-after-ms")):
		return null
	var h: AppQuitHook = AppQuitHook.new()
	h.name = "AppQuitHook"
	h.process_mode = Node.PROCESS_MODE_ALWAYS
	h.phase_wanted = str(args.extras.get("quit-at-phase", "any")).to_lower()
	h.after_ms = maxi(0, int(str(args.extras.get("quit-after-ms", "0"))))
	h.mode = str(args.extras.get("quit-mode", "tree")).to_lower()
	host.add_child(h)
	return h


## The current phase name (see the header). Pure read of the app state.
static func phase_of(tree: SceneTree) -> String:
	var state: Node = tree.root.get_node_or_null("AppState")
	if state == null:
		return "splash"
	var flow: AppFlow = state.get("flow") as AppFlow
	if flow == null or flow.mode == AppFlow.Mode.BOOT:
		return "splash"
	var mode_label: String = AppFlow.mode_name(flow.mode).to_lower()
	if flow.mode == AppFlow.Mode.LOADING:
		var ctx: Variant = state.get("match_ctx")
		if ctx != null and (ctx as Object).get("job") is AppMatchJob:
			var job: AppMatchJob = (ctx as Object).get("job") as AppMatchJob
			match job.phase:
				AppMatchJob.Phase.MAP:
					return "loading_map"
				AppMatchJob.Phase.WORLD:
					return "loading_world"
				AppMatchJob.Phase.VIEW:
					return "loading_view" + ("_" + job.view_stage() if job.view_stage() != "" else "")
	return mode_label


## Phases of a match in the order they are passed; a wanted phase of this chain that is already behind us fires at once (a short phase can
## fall between two frames: the world step of a small map), so a run can never wait for a phase that has gone.
const CHAIN: PackedStringArray = ["loading_map", "loading_world", "loading_view", "in_match", "end_screen"]


static func _rank(phase: String) -> int:
	for i: int in CHAIN.size():
		if phase == CHAIN[i] or phase.begins_with(CHAIN[i] + "_"):
			return i
	return -1


static func passed(wanted: String, current: String) -> bool:
	var w: int = _rank(wanted)
	return w >= 0 and _rank(current) > w


static func matches(wanted: String, current: String) -> bool:
	return wanted == "any" or wanted == current or current.begins_with(wanted + "_") or (wanted == "match" and current == "in_match") \
		or (wanted == "boot" and current == "splash")


func _process(_delta: float) -> void:
	if fired:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var now: int = Time.get_ticks_msec()
	if _seen_ms < 0:
		var cur: String = phase_of(tree)
		if not matches(phase_wanted, cur) and not passed(phase_wanted, cur):
			return
		_seen_ms = now
	if now - _seen_ms < after_ms:
		return
	fired = true
	# lint-allow: L006 result line parsed by tools/py/quit_stress.py
	print("QUITHOOK phase=%s after_ms=%d mode=%s at_ms=%d" % [phase_of(tree), after_ms, mode, now])
	match mode:
		"close":
			tree.root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)  # AppState turns it into quit_game(); without it the engine quits itself
			tree.root.close_requested.emit()
		"state":
			var state: Node = tree.root.get_node_or_null("AppState")
			if state != null:
				state.call("quit_game")
			else:
				tree.quit()
		"raw":
			tree.quit()
		_:
			AppShutdown.begin_quit(tree)
			await AppAudio.release_for_quit(tree)  # (3 frames and the audio thread's grace time, like every orderly quit)
			AppShutdown.prepare_quit(tree)
			AppShutdown.release_statics()
			tree.quit()
