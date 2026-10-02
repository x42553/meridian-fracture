extends Node
## Autoload `AppNet` (ui.md 3.1, no class_name so that the autoload name stays free): owns the frame drive of the running match
## session. Registered BEFORE `AppState` (project.godot) with process priority -100, so `NetSession.poll()` runs once per rendered
## frame ahead of every view and UI node (ui.md 3.0). Skirmish (`Role.LOCAL`) and, later, LAN host / client sessions all go through
## `attach(ctx)`: the context carries the session and the per-frame extras (debug bot, statistics, test limits); this node only
## drives it and lets go of it.

signal attached(ctx: RefCounted)
signal detached()

## The `AppMatchContext` being driven, null between matches.
var ctx: RefCounted = null


func _init() -> void:
	name = "AppNet"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100


func _process(_delta: float) -> void:
	var c: AppMatchContext = ctx as AppMatchContext
	if c == null:
		return
	if c.disposed:
		detach(c)
		return
	c.frame()


## Starts driving `c` (replaces a previous context, which keeps existing but is no longer polled).
func attach(c: RefCounted) -> void:
	ctx = c
	attached.emit(c)


## Stops driving `c` (a no-op when another context has replaced it).
func detach(c: RefCounted = null) -> void:
	if c != null and c != ctx:
		return
	ctx = null
	detached.emit()


## The session of the driven context (null when idle).
func session() -> NetSession:
	var c: AppMatchContext = ctx as AppMatchContext
	return c.session if c != null else null


## Ends the running match session: disposes the context (shutdown, view stage) and clears `AppState.match_ctx`. Idempotent.
func end_session() -> void:
	var c: AppMatchContext = ctx as AppMatchContext
	ctx = null
	if c != null:
		c.dispose()
	var state: Node = _autoload("AppState")
	if state != null and state.get("match_ctx") == c:
		state.set("match_ctx", null)
	detached.emit()


## The session options of the app with the persisted settings applied (`net/player_name`); `extra` as `AppNetSetup.make_options`.
func make_options(extra: Dictionary = {}) -> NetSessionOptions:
	var state: Node = _autoload("AppState")
	var data: GameData = state.get("data") as GameData if state != null else null
	if data == null:
		data = GameData.load_default()
	var p: Dictionary = extra.duplicate()
	var settings: Node = _autoload("AppSettings")
	if settings != null and not p.has("player_name"):
		p["player_name"] = str(settings.call("get_str", &"net/player_name"))
	return AppNetSetup.make_options(data, p)


## A sibling autoload by name (`/root` relative through the main loop, so it also works before this node is fully in the tree).
static func _autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree != null else null
