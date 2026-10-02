extends RefCounted
## `AppFlow` transition table (ui.md 5.1.2, 10.2 `test_ui_flow`) and the `AppState` navigation over `AppScenes`.

const U := preload("res://tests/ui/app_test_util.gd")
const M = AppFlow.Mode


func test_edges_of_the_table(t: TestCtx) -> void:
	var legal: Array = [[M.BOOT, M.MAIN_MENU], [M.BOOT, M.FATAL], [M.BOOT, M.LOADING], [M.MAIN_MENU, M.SKIRMISH_LOBBY],
		[M.MAIN_MENU, M.LAN_BROWSER], [M.MAIN_MENU, M.REPLAYS], [M.MAIN_MENU, M.OPTIONS], [M.MAIN_MENU, M.CREDITS],
		[M.MAIN_MENU, M.FIELD_MANUAL], [M.MAIN_MENU, M.QUIT], [M.SKIRMISH_LOBBY, M.MAIN_MENU], [M.SKIRMISH_LOBBY, M.LOADING],
		[M.SKIRMISH_LOBBY, M.OPTIONS], [M.LAN_BROWSER, M.LAN_LOBBY], [M.LAN_BROWSER, M.MAIN_MENU], [M.LAN_LOBBY, M.LAN_BROWSER],
		[M.LAN_LOBBY, M.LOADING], [M.LOADING, M.IN_MATCH], [M.LOADING, M.SKIRMISH_LOBBY], [M.LOADING, M.LAN_LOBBY],
		[M.LOADING, M.MAIN_MENU], [M.IN_MATCH, M.END_SCREEN], [M.IN_MATCH, M.MAIN_MENU], [M.IN_MATCH, M.OPTIONS],
		[M.IN_MATCH, M.FIELD_MANUAL], [M.IN_MATCH, M.FATAL], [M.END_SCREEN, M.MAIN_MENU], [M.END_SCREEN, M.SKIRMISH_LOBBY],
		[M.END_SCREEN, M.LAN_LOBBY], [M.END_SCREEN, M.REPLAY_PLAYBACK], [M.REPLAYS, M.REPLAY_PLAYBACK],
		[M.REPLAY_PLAYBACK, M.REPLAYS], [M.REPLAY_PLAYBACK, M.MAIN_MENU], [M.OPTIONS, M.FATAL], [M.FATAL, M.QUIT]]
	for e: Array in legal:
		t.check(AppFlow.can_go(e[0], e[1]), "%s -> %s legal" % [AppFlow.mode_name(e[0]), AppFlow.mode_name(e[1])])
	var illegal: Array = [[M.MAIN_MENU, M.IN_MATCH], [M.MAIN_MENU, M.LOADING], [M.BOOT, M.IN_MATCH], [M.SKIRMISH_LOBBY, M.IN_MATCH],
		[M.LAN_BROWSER, M.LOADING], [M.IN_MATCH, M.LOADING], [M.END_SCREEN, M.IN_MATCH], [M.QUIT, M.MAIN_MENU],
		[M.FATAL, M.FATAL], [M.LOADING, M.END_SCREEN], [M.OPTIONS, M.MAIN_MENU], [M.REPLAYS, M.IN_MATCH]]
	for e: Array in illegal:
		t.check(not AppFlow.can_go(e[0], e[1]), "%s -> %s illegal" % [AppFlow.mode_name(e[0]), AppFlow.mode_name(e[1])])


func test_go_refuses_illegal_and_keeps_state(t: TestCtx) -> void:
	var f: AppFlow = AppFlow.new()
	t.eq(f.mode, M.BOOT)
	t.check(f.go(M.MAIN_MENU, {"first_run": true}))
	t.eq(f.params["first_run"], true)
	t.check(not f.go(M.IN_MATCH), "MAIN_MENU -> IN_MATCH is illegal")
	t.eq(f.mode, M.MAIN_MENU, "an illegal go changes nothing")
	t.check(f.go(M.SKIRMISH_LOBBY))
	t.check(f.go(M.LOADING))
	t.check(f.go(M.SKIRMISH_LOBBY), "LOADING -> SKIRMISH_LOBBY is legal (launch aborted)")


func test_push_pop_stack(t: TestCtx) -> void:
	var f: AppFlow = AppFlow.new()
	f.go(M.MAIN_MENU)
	t.check(f.push(M.OPTIONS))
	t.eq(f.mode, M.OPTIONS)
	t.eq(f.stack_depth(), 1)
	t.check(f.push(M.FIELD_MANUAL), "a second overlay may be stacked")
	t.eq(f.stack_depth(), 2)
	t.eq(f.pop(), M.OPTIONS, "pop returns the mode returned to")
	t.eq(f.pop(), M.MAIN_MENU)
	t.eq(f.pop(), -1, "nothing left to pop")
	t.check(not f.push(M.LOADING), "only overlay modes can be pushed")
	t.check(not f.push(M.QUIT))
	# go while a stack exists clears it
	f.push(M.CREDITS)
	t.check(f.go(M.SKIRMISH_LOBBY) == false, "CREDITS is an overlay: its own edges are empty")
	f.pop()
	f.push(M.OPTIONS)
	t.check(f.go(M.FATAL), "FATAL is reachable from anywhere")
	t.eq(f.stack_depth(), 0, "go clears the overlay stack")
	f.force(M.IN_MATCH)
	t.check(f.push(M.OPTIONS) and f.push(M.FIELD_MANUAL), "match overlays (Esc menu)")
	t.check(f.go(M.OPTIONS) == false, "go to an overlay from an overlay is a push")
	t.eq(f.mode, M.FIELD_MANUAL)


func test_screen_ids(t: TestCtx) -> void:
	t.eq(AppFlow.screen_id_of(M.BOOT), &"splash")
	t.eq(AppFlow.screen_id_of(M.SKIRMISH_LOBBY), &"lobby")
	t.eq(AppFlow.screen_id_of(M.LAN_LOBBY), &"lobby")
	t.eq(AppFlow.screen_id_of(M.REPLAY_PLAYBACK), &"game")
	t.eq(AppFlow.screen_id_of(M.QUIT), &"")
	for m: int in M.values():
		if m != M.QUIT:
			var id: StringName = AppFlow.screen_id_of(m)
			t.check(AppScreens.is_valid_id(id), "%s has a registered screen id" % AppFlow.mode_name(m))
	t.eq(AppFlow.mode_of_screen(&"lobby", {"lan": true}), M.LAN_LOBBY)
	t.eq(AppFlow.mode_of_screen(&"lobby"), M.SKIRMISH_LOBBY)
	t.eq(AppFlow.mode_of_screen(&"game", {"replay": true}), M.REPLAY_PLAYBACK)
	t.eq(AppFlow.mode_of_screen(&"nope"), -1)
	t.eq(AppFlow.back_of(M.LAN_LOBBY), M.LAN_BROWSER)
	t.eq(AppFlow.back_of(M.MAIN_MENU), -1)


## AppState over a private AppScenes: modes map to screens, overlays push and pop, navigate/back requests become transitions.
func test_app_state_drives_scenes(t: TestCtx) -> void:
	t.set_timeout(20.0)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var dir: String = U.sandbox("state")
	var sc: Node = (load("res://src/app/app_scenes.gd") as GDScript).new() as Node
	tree.root.add_child(sc)
	var st: Node = (load("res://src/app/app_state.gd") as GDScript).new() as Node
	(st.get("crash_reporter") as AppCrashReporter).session_path = dir.path_join(".session")
	tree.root.add_child(st)
	st.call("use_scenes", sc)
	await tree.process_frame
	UiThemeService.rebuild(UiSkinSet.shared().neutral_skin())
	UiMotion.reduce_motion = true
	var flow: AppFlow = st.get("flow") as AppFlow
	st.call("go", M.MAIN_MENU)
	await tree.process_frame
	t.eq(String((sc.get("screen") as UiScreen).screen_id), "main_menu", "MAIN_MENU shows the main_menu screen")
	st.call("go", M.IN_MATCH)
	t.eq(flow.mode, M.MAIN_MENU, "an illegal transition is refused")
	# a placeholder button navigates: SKIRMISH LOBBY
	(sc.get("screen") as UiScreen).navigate.emit(&"lobby", {})
	await tree.process_frame
	t.eq(flow.mode, M.SKIRMISH_LOBBY)
	t.eq(String((sc.get("screen") as UiScreen).screen_id), "lobby")
	# overlay push / pop
	st.call("push_mode", M.OPTIONS)
	t.eq(int(sc.call("pushed_count")), 1)
	t.eq(String((sc.call("top_screen") as UiScreen).screen_id), "options")
	t.check(not (sc.get("screen") as UiScreen).handles_escape, "the lower screen stops handling Escape")
	sc.emit_signal("back_requested")
	t.eq(int(sc.call("pushed_count")), 0, "back pops the overlay")
	t.eq(flow.mode, M.SKIRMISH_LOBBY)
	t.check((sc.get("screen") as UiScreen).handles_escape, "and re-enables it")
	# back from a lobby goes to the menu
	sc.emit_signal("back_requested")
	await tree.process_frame
	t.eq(flow.mode, M.MAIN_MENU)
	# fatal screen carries the model
	var model: Dictionary = AppCrash.build(AppCrash.Reason.WORLD_BUILD_FAILED, "boom detail")
	st.call("go", M.FATAL, model)
	await tree.process_frame
	t.eq(String((sc.get("screen") as UiScreen).screen_id), "fatal")
	t.check(bool(model["retry"]), "world-build failure offers Retry")
	t.check(String(model["text"]).contains("boom detail") and String(model["text"]).contains("WORLD_BUILD_FAILED"))
	# bind_session: a fake session with the phase signals
	var fake: FakeSession = FakeSession.new()
	st.call("go", M.MAIN_MENU)
	st.call("go", M.SKIRMISH_LOBBY)
	st.call("go", M.LOADING)
	st.call("bind_session", fake)
	fake.match_started.emit()
	t.eq(flow.mode, M.IN_MATCH, "match_started moves LOADING to IN_MATCH")
	fake.match_ended.emit(1)
	t.eq(flow.mode, M.END_SCREEN)
	UiMotion.reduce_motion = false
	tree.root.remove_child(st)
	tree.root.remove_child(sc)
	st.free()
	sc.free()
	U.cleanup(dir)


class FakeSession extends RefCounted:
	signal match_started()
	signal launch_aborted(reason: int, detail: String)
	signal match_ended(result: int)
