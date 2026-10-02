extends RefCounted
## HARD1: the quit hook (`--quit-at-phase`, `--quit-after-ms`, `--quit-mode`; driver tools/py/quit_stress.py) and the orderly-quit state of AppShutdown.


func test_flags_are_parsed_into_extras(t: TestCtx) -> void:
	var a: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--quit-at-phase=loading_view", "--quit-after-ms=300", "--quit-mode=close"]))
	t.eq(str(a.extras["quit-at-phase"]), "loading_view")
	t.eq(str(a.extras["quit-after-ms"]), "300")
	t.eq(str(a.extras["quit-mode"]), "close")
	t.is_null(AppQuitHook.install(null, a), "nothing is installed without a host")
	var host: Node = Node.new()
	t.is_null(AppQuitHook.install(host, AppLaunchArgs.parse(PackedStringArray(["--autostart=match"]))), "and nothing without the flags")
	host.free()


func test_phase_matching(t: TestCtx) -> void:
	t.check(AppQuitHook.matches("any", "anything"))
	t.check(AppQuitHook.matches("loading", "loading_view_models"), "a parent phase matches its sub-phases")
	t.check(AppQuitHook.matches("loading_view", "loading_view_terrain"))
	t.check_false(AppQuitHook.matches("loading_view", "loading_map"))
	t.check_false(AppQuitHook.matches("loading_view_models", "loading_view_terrain"))
	t.check(AppQuitHook.matches("match", "in_match"))
	t.check(AppQuitHook.matches("boot", "splash"))
	t.check_false(AppQuitHook.matches("options", "credits"))


func test_a_passed_phase_of_the_match_chain_fires_at_once(t: TestCtx) -> void:
	t.check(AppQuitHook.passed("loading_world", "loading_view_terrain"), "the world step fell between two frames")
	t.check(AppQuitHook.passed("loading_map", "in_match"))
	t.check_false(AppQuitHook.passed("loading_view", "loading_view_models"), "still inside the wanted phase")
	t.check_false(AppQuitHook.passed("in_match", "loading_map"))
	t.check_false(AppQuitHook.passed("options", "in_match"), "a phase outside the chain is never 'passed'")


func test_phase_of_follows_the_flow(t: TestCtx) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var state: Node = tree.root.get_node_or_null("AppState")
	if state == null:
		t.skip("no AppState autoload")
		return
	var flow: AppFlow = state.get("flow") as AppFlow
	var saved_mode: int = flow.mode
	var saved_params: Dictionary = flow.params
	flow.force(AppFlow.Mode.OPTIONS)
	t.eq(AppQuitHook.phase_of(tree), "options")
	flow.force(AppFlow.Mode.LAN_LOBBY)
	t.eq(AppQuitHook.phase_of(tree), "lan_lobby")
	flow.force(AppFlow.Mode.BOOT)
	t.eq(AppQuitHook.phase_of(tree), "splash")
	flow.force(saved_mode, saved_params)


func test_begin_quit_flags_the_process_and_is_idempotent(t: TestCtx) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var before: bool = AppShutdown.quitting
	AppShutdown.begin_quit(tree)
	AppShutdown.begin_quit(tree)
	t.check(AppShutdown.quitting)
	AppShutdown.quitting = before  # static: other tests (the autostart loops) must not see an orderly quit
