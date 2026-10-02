extends RefCounted
## Boot timeline (ui.md 5.2.1), scene layers / transitions / toasts (`AppScenes`) and the screen registry.

const U := preload("res://tests/ui/app_test_util.gd")


func test_boot_scene_and_smoke_contract(t: TestCtx) -> void:
	t.check(ResourceLoader.exists("res://src/app/boot.tscn"))
	t.eq(String(ProjectSettings.get_setting("application/run/main_scene")), "res://src/app/boot.tscn")
	var autoloads: PackedStringArray = PackedStringArray()
	for p: Dictionary in ProjectSettings.get_property_list():
		if String(p["name"]).begins_with("autoload/"):
			autoloads.append(String(p["name"]).substr(9))
	for a: String in ["DevShot", "AppSettings", "AppState", "AppScenes"]:
		t.check(autoloads.has(a), "autoload %s registered" % a)
	t.eq(ProjectSettings.get_setting("display/window/stretch/mode"), "disabled", "the UI factor is the only scaling")
	t.check(bool(ProjectSettings.get_setting("display/window/dpi/allow_hidpi")))
	t.check(String(ProjectSettings.get_setting("debug/settings/crash_handler/message")).contains("crashed"))


## The whole timeline over the real autoloads: fresh in-memory settings, no session sentinel, straight to a screen.
func test_boot_timeline_within_budgets(t: TestCtx) -> void:
	t.set_timeout(60.0)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var host: Node = Node.new()
	tree.root.add_child(host)
	var b: AppBoot = AppBoot.new()
	var args: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--fresh-settings", "--no-prewarm", "--no-audio", "--screen=main_menu"]))
	await b.execute(host, args)
	var scenes0: Node = tree.root.get_node("AppScenes")
	while bool(scenes0.call("is_busy")):
		await tree.process_frame
	t.check(b.finished and not b.fatal, "boot finished")
	var names: PackedStringArray = PackedStringArray()
	for s: Dictionary in b.timeline():
		names.append(String(s["step"]))
	t.eq(names, PackedStringArray(["args", "logging", "settings", "ui", "data", "services", "prewarm"]), "steps in the order of 5.2.1")
	t.check(b.splash_ms >= 0 and b.splash_ms < 600, "the splash is up early (%d ms after boot start)" % b.splash_ms)
	# generous factor: shared CI machines are slow; the real budgets are checked on the reference Mac by hand
	var over: PackedStringArray = b.over_budget(8.0)
	t.eq(over.size(), 0, "no step took 8x its budget: %s" % [over])
	for s: Dictionary in b.timeline():
		t.note("%s %d ms (budget %d)" % [s["step"], s["ms"], s["budget_ms"]])
	var state: Node = tree.root.get_node("AppState")
	var scenes: Node = tree.root.get_node("AppScenes")
	t.eq((state.get("flow") as AppFlow).mode, AppFlow.Mode.MAIN_MENU, "--screen=main_menu forces that mode")
	t.eq(String((scenes.get("screen") as UiScreen).screen_id), "main_menu")
	t.check(state.get("data") != null, "GameData loaded")
	t.eq(int(UiThemeService.instance().root_count()) > 0, true, "layer roots are themed")
	var settings: Node = tree.root.get_node("AppSettings")
	t.check(bool(settings.get("in_memory")), "--fresh-settings uses an in-memory store")
	t.check(b.unclean.is_empty(), "test modes do not touch the session sentinel")
	AppBoot.shutdown_logging()
	settings.call("configure", AppPaths.SETTINGS, true)
	tree.root.remove_child(host)
	host.free()


func test_screen_registry(t: TestCtx) -> void:
	for id: StringName in AppScreens.IDS:
		var s: UiScreen = AppScreens.make(id)
		t.not_null(s, "screen %s" % id)
		if s != null:
			t.eq(s.screen_id, id)
			s.free()
	t.eq(AppScreens.class_of(&"main_menu"), &"UiScreenMainMenu")
	t.eq(AppScreens.class_of(&"lan_browser"), &"UiScreenLanBrowser")
	var splash: UiScreen = AppScreens.make(&"splash")
	t.check(splash is AppSplash, "splash placeholder")
	splash.free()
	var replays: UiScreen = AppScreens.make(&"replays")
	t.check(replays is UiScreenReplays, "the replay browser is the real screen class (REP2)")
	replays.free()
	t.eq(AppScreens.class_of(&"replays"), &"UiScreenReplays")
	AppScreens.register(&"credits", func() -> UiScreen: return AppPlaceholderScreen.new())
	t.check(AppScreens.is_valid_id(&"credits"))
	var marker: UiScreen = UiScreen.new()
	AppScreens.register(&"credits", func() -> UiScreen: return marker)
	t.check(AppScreens.make(&"credits") == marker, "an override wins over everything")
	AppScreens.clear_overrides()
	marker.free()


## Layers exist with the right canvas indices; goto/push/pop/toast/modal behave.
func test_scenes_layers_transitions_toasts(t: TestCtx) -> void:
	t.set_timeout(30.0)
	t.expect_errors(1)  # the unknown screen id below is logged as an error
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var sc: Node = (load("res://src/app/app_scenes.gd") as GDScript).new() as Node
	tree.root.add_child(sc)
	await tree.process_frame
	UiThemeService.rebuild(UiSkinSet.shared().neutral_skin())
	var idx: Array[int] = []
	for layer: int in 5:
		var root: Control = sc.call("layer_root", layer) as Control
		t.check(root is UiLayerRoot and root.theme != null, "layer %d root is themed (P1)" % layer)
		idx.append((root.get_parent() as CanvasLayer).layer)
	t.eq(idx, [0, 10, 40, 90, 100] as Array[int], "CanvasLayer indices")
	t.check(sc.call("backdrop_host") is Node3D)
	var ids: Array[StringName] = []
	sc.connect("screen_changed", func(id: StringName) -> void: ids.append(id))
	# animated transition (fade 0.18 + 0.22 s)
	UiMotion.reduce_motion = false
	sc.call("goto", &"main_menu", {}, false)
	t.eq(ids, [&"main_menu"] as Array[StringName], "no fade = immediate")
	sc.call("goto", &"options", {}, true)
	t.check(bool(sc.call("is_busy")), "a fading transition is in flight")
	sc.call("goto", &"credits", {}, true)
	sc.call("goto", &"replays", {}, true)
	await sc.transition_finished
	t.eq(ids, [&"main_menu", &"options", &"replays"] as Array[StringName], "requests queued during a transition coalesce: the last wins")
	t.near(float(sc.call("fade_alpha")), 0.0, 0.01, "the curtain is open again")
	t.eq(String((sc.get("screen") as UiScreen).screen_id), "replays")
	var old: UiScreen = sc.get("screen") as UiScreen
	UiMotion.reduce_motion = true
	sc.call("goto", &"main_menu", {}, true)
	t.check(not is_instance_valid(old) or old.is_queued_for_deletion(), "the previous screen was exited and freed")
	# overlays
	sc.call("push", &"options")
	t.eq(int(sc.call("pushed_count")), 1)
	var top: UiScreen = sc.call("top_screen") as UiScreen
	t.eq(String(top.screen_id), "options")
	sc.call("pop")
	t.eq(int(sc.call("pushed_count")), 0)
	# unknown ids are refused, the current screen stays
	sc.call("goto", &"not_a_screen", {}, false)
	t.eq(String((sc.get("screen") as UiScreen).screen_id), "main_menu")
	# toasts
	var toast: UiToast = sc.call("toast", "hello", 0) as UiToast
	t.not_null(toast)
	t.eq(int(sc.call("toast_count")), 1)
	var acted: Array = []
	var t2: UiToast = sc.call("toast", "unclean", 1, [{"label_key": &"ui.ok", "call": func() -> void: acted.append(1)}] as Array[Dictionary]) as UiToast
	t.near(t2.hold_s, 10.0, 0.001, "a toast with actions stays 10 s")
	for i: int in 8:
		sc.call("toast", "many %d" % i, 0)
	t.eq(int(sc.call("toast_count")), 5, "at most 5 toasts stack")
	# modal
	var dlg: UiDialog = UiDialog.new()
	sc.call("modal", dlg)
	var dialogs: UiDialogStack = sc.get("dialogs") as UiDialogStack
	t.check(dialogs.is_open(), "the dialog stack shows it")
	dialogs.close_top(0)
	await tree.process_frame
	t.check(not dialogs.is_open())
	UiMotion.reduce_motion = false
	tree.root.remove_child(sc)
	sc.free()
	AppScreens.clear_overrides()
