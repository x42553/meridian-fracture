extends RefCounted
## `AppApply` (ui.md 10.2 `test_ui_apply`): audio hand-off, quality config translation, UI scale floor, renderer relaunch.


func _store(pairs: Dictionary) -> AppSettingsStore:
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	for k: Variant in pairs:
		s.set_value(StringName(k), pairs[k])
	return s


func test_audio_values_and_sink_called_once_per_change(t: TestCtx) -> void:
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	var v: Dictionary = AppApply.audio_values(s)
	t.eq(v["audio/master"], 100)
	t.eq(v["audio/music"], 70)
	t.eq(v["audio/sfx"], 90)
	t.eq(v["audio/voice"], 100)
	t.eq(v["audio/ui"], 80)
	t.eq(v["audio/ambience"], 70)
	t.eq(v["audio/announcer"], 0)
	t.eq(v["audio/unit_voices"], 0)
	var calls: Array = []
	AppApply.audio_sink = func(values: Dictionary) -> void: calls.append(values)
	s.set_value(&"audio/music", 30)
	AppApply.on_changed(&"audio/music", s)
	t.eq(calls.size(), 1, "one Snd.apply_settings per change")
	t.eq((calls[0] as Dictionary)["audio/music"], 30)
	AppApply.on_changed(&"video/vsync", s)
	t.eq(calls.size(), 1, "a video change does not touch audio")
	AppApply.audio_sink = Callable()


func test_quality_config_contains_exactly_the_present_keys(t: TestCtx) -> void:
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	var cfg: ConfigFile = AppApply.quality_config(s)
	t.eq(cfg.get_section_keys("video").size() if cfg.has_section("video") else 0, 0, "a default store has no [video] keys (absent = preset)")
	s.set_value(&"video/quality", 1 if AppGraphics.recommend() != 1 else 2)
	s.set_value(&"video/render_scale", 0.85)
	s.set_value(&"video/msaa", 2)
	s.set_value(&"video/vsync", 0)
	s.set_value(&"video/ui_scale", 130)
	cfg = AppApply.quality_config(s)
	var keys: PackedStringArray = cfg.get_section_keys("video")
	keys.sort()
	t.eq(keys, PackedStringArray(["msaa", "quality", "render_scale"]), "window-only keys (vsync, ui_scale) stay out")
	t.near(float(cfg.get_value("video", "render_scale")), 0.85)
	t.eq(cfg.get_value("video", "msaa"), 2)


func test_quality_config_access_names(t: TestCtx) -> void:
	var cfg: ConfigFile = AppApply.quality_config(_store({"access/colour_mode": "cvd", "access/high_contrast_hud": true}))
	t.eq(cfg.get_value("access", "colour_mode"), "deutan", "cvd is written under the view's name")
	t.eq(cfg.get_value("access", "cvd_palette"), true)
	t.eq(cfg.get_value("access", "high_contrast_hud"), true)
	cfg = AppApply.quality_config(AppSettingsStore.with_defaults())
	t.eq(cfg.get_value("access", "colour_mode"), "normal")
	t.eq(cfg.get_value("access", "cvd_palette"), false)
	t.eq(cfg.get_value("access", "reduce_motion"), false)
	# the view understands what we wrote
	var q: ViewQuality = ViewQuality.from_settings(AppApply.quality_config(_store({"access/colour_mode": "cvd"})),
		ViewQuality.load_presets(), ViewQuality.Renderer.FORWARD_PLUS)
	t.eq(q.colour_mode, ViewQuality.colour_mode_from_name("deutan"))


func test_unsupported_scaling_mode_falls_back(t: TestCtx) -> void:
	var s: AppSettingsStore = _store({"video/scaling_mode": "metalfx_spatial"})
	var cfg: ConfigFile = AppApply.quality_config(s)
	if AppSettingsSchema.guard_ok(&"metalfx"):
		t.eq(cfg.get_value("video", "scaling_mode"), "metalfx_spatial", "Metal keeps MetalFX")
	else:
		t.eq(cfg.get_value("video", "scaling_mode"), "bilinear", "the metalfx guard failed -> bilinear")
	# a mode every renderer supports is passed through
	cfg = AppApply.quality_config(_store({"video/scaling_mode": "fsr1"}))
	t.eq(cfg.get_value("video", "scaling_mode"), "fsr1")
	t.check(not AppSettingsSchema.guard_ok(&"renderer_switch") or AppRelaunch.supported(), "renderer_switch follows AppRelaunch.supported")


func test_overrides_win_and_are_not_stored(t: TestCtx) -> void:
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	t.eq(AppApply.value(s, &"video/ui_scale", {"video/ui_scale": 150}), 150)
	t.eq(AppApply.value(s, &"video/ui_scale", {"video/ui_scale": 999}), 200, "an override is clamped like a stored value")
	t.eq(s.get_value(&"video/ui_scale"), 100, "the store is untouched")
	var cfg: ConfigFile = AppApply.quality_config(s, {"access/colour_mode": "cvd"})
	t.eq(cfg.get_value("access", "colour_mode"), "deutan")


func test_ui_scale_floor_and_effective_percent(t: TestCtx) -> void:
	t.near(AppApply.ui_factor(Vector2i(1280, 720), 200), 1.3333, 0.001, "200 % at 1280x720 hits the 540 floor")
	t.eq(AppApply.effective_pct(Vector2i(1280, 720), 200), 178, "reports 178 % effective")
	t.eq(AppApply.effective_pct(Vector2i(1920, 1080), 150), 150)
	t.eq(AppApply.effective_pct(Vector2i(1920, 1080), 100), 100)
	t.near(AppApply.ui_factor(Vector2i(3840, 2160), 125), 2.5, 0.0001)


func test_apply_ui_scale_on_a_window(t: TestCtx) -> void:
	var win: Window = Window.new()
	win.size = Vector2i(1280, 720)
	var s: AppSettingsStore = _store({"video/ui_scale": 200})
	var f: float = AppApply.apply_ui_scale(win, s)
	t.near(f, 1.3333, 0.001)
	t.near(win.content_scale_factor, 1.3333, 0.001)
	t.eq(win.content_scale_mode, Window.CONTENT_SCALE_MODE_DISABLED, "the factor is the only scaling (5.4.1)")
	t.eq(win.min_size, UiMetrics.MIN_WINDOW)
	win.free()
	t.near(AppApply.apply_ui_scale(null, s), 1.0)


func test_apply_ui_switches(t: TestCtx) -> void:
	var s: AppSettingsStore = _store({"access/reduce_motion": true, "access/reduce_flash": true, "access/colour_mode": "cvd",
		"access/high_contrast_hud": true, "ui/tooltip_delay_ms": 800})
	AppApply.apply_ui(s)
	t.check(UiMotion.reduce_motion and UiMotion.reduce_flash)
	t.eq(UiSkinSet.shared().colour_mode(), UiSkinSet.ColourMode.CVD)
	t.eq(UiThemeService.a11y_options(), {"high_contrast": true, "cvd": true})
	t.near(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec")), 0.8, 0.001)
	AppApply.apply_ui(AppSettingsStore.with_defaults())
	t.check(not UiMotion.reduce_motion and not UiMotion.reduce_flash)
	t.eq(UiSkinSet.shared().colour_mode(), UiSkinSet.ColourMode.NORMAL)


func test_relaunch_needed_rules(t: TestCtx) -> void:
	var running: String = RenderingServer.get_current_rendering_method()
	var other: String = "mobile" if running != "mobile" else "gl_compatibility"
	var args: AppLaunchArgs = AppLaunchArgs.new()
	t.check(not AppRelaunch.needed(AppSettingsStore.with_defaults(), args), "auto (project default) never relaunches")
	t.check(not AppRelaunch.needed(_store({"video/renderer": running}), args), "already running that method")
	t.check(AppRelaunch.needed(_store({"video/renderer": other}), args, PackedStringArray()), "a different method needs a restart")
	t.check(not AppRelaunch.needed(_store({"video/renderer": other}), args, PackedStringArray(["--rendering-method", "forward_plus"])),
		"--rendering-method on the command line wins")
	args.renderer_relaunched = true
	t.check(not AppRelaunch.needed(_store({"video/renderer": other}), args), "--renderer-relaunched stops the loop")
	t.check(not AppRelaunch.supported() or DisplayServer.get_name() != "headless", "never supported headless")
	var built: PackedStringArray = AppRelaunch.build_args("mobile", PackedStringArray(["--path", "game"]), PackedStringArray(["--screen=lobby"]))
	t.eq(built, PackedStringArray(["--path", "game", "--rendering-method", "mobile", "--", "--screen=lobby", "--renderer-relaunched"]))
	t.eq(AppRelaunch.relaunch("mobile"), -1, "unsupported (headless) = no process")


func test_info_strings(t: TestCtx) -> void:
	var line: String = AppInfo.smoke_line(0)
	var re: RegEx = RegEx.create_from_string("^MERIDIAN_BOOT engine=\\S+ renderer=\\S+ os=\\S+ debug=[01] version=\\S+ build=\\S+ selftest=(ok|\\d+)$")
	t.check(re.search(line) != null, "smoke line format: " + line)
	t.check(AppInfo.smoke_line(3).ends_with("selftest=3"))
	t.eq(AppInfo.version(), "0.1.0")
	t.eq(AppInfo.selftest_failures(), 0, "Fp.self_test passes")
	t.check(AppInfo.platform_string().length() > 5)
