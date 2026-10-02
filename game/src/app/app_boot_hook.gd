class_name AppBootHook
extends RefCounted
## Boot-time wiring of the match glue (ui.md 5.2.1 step "services"; `AppBoot` calls `AppBootHook.run(state, store, args)` when this
## class exists): makes sure the `AppNet` autoload is present and reads the debug flags that steer the match glue. Audio (`AppAudio.install`) and the
## cursors / first-run / range-ring entry points are installed here.


## `state`: the `AppState` node, `store`: the settings, `args`: the launch flags. Idempotent.
static func run(state: Node, store: AppSettingsStore, args: AppLaunchArgs) -> void:
	_ensure_net(state)
	AppAudio.install(state, store, args)  # /root/Snd, the settings sink, menu widget sounds, AppAudioFeed; nothing under --no-audio
	AppViewStage.fx_globally_off = args.extras.has("no-fx")
	UiPauseBanner.suppressed = args.extras.has("no-banner")
	AppViewStage.forced_mood = StringName(str(args.extras.get("mood", "")))
	AppAiHook.set_bot_mode(bot_mode(args))
	Log.info("app", "cursors: %s (%d registered)" % ["game cursors" if UiCursors.is_active() else "system cursors", UiCursors.apply_calls])
	if state != null and store != null and state.get("profile") is AppProfile:
		Log.info("app", "match glue ready: bots=%s player=%s" % [bot_mode(args), str(store.get_value(&"net/player_name"))])


## `--bots` -> "" (off), "ai" (bare `--bots`: AI slots use the scripted bot), "human" or "all".
static func bot_mode(args: AppLaunchArgs) -> String:
	if not args.extras.has("bots"):
		return ""
	var v: Variant = args.extras["bots"]
	if v is bool:
		return "ai" if bool(v) else ""
	var t: String = str(v)
	return t if t == "human" or t == "all" else "ai"


## The `AppNet` autoload is registered in project.godot; a process that starts without it (tools, tests) gets a node here.
static func _ensure_net(state: Node) -> void:
	if state == null or not state.is_inside_tree():
		return
	var root: Node = state.get_tree().root
	if root.get_node_or_null("AppNet") == null:
		var n: Node = load("res://src/app/app_net.gd").new() as Node
		root.add_child.call_deferred(n)
