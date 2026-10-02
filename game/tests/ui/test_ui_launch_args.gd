extends RefCounted
## `AppLaunchArgs.parse` (ui.md 10.2 `test_ui_launch_args`, 5.2.3).


func test_documented_line(t: TestCtx) -> void:
	var a: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--screen=lobby", "--fixture=hud_mid_match", "--ui-scale=1.5",
		"--smoke", "--qa=D01", "--selfcheck"]))
	t.eq(a.screen, &"lobby")
	t.eq(a.fixture, "hud_mid_match")
	t.near(a.ui_scale, 1.5)
	t.check(a.smoke, "bare --smoke is true")
	t.eq(a.qa_job, "D01")
	t.check(a.selfcheck)
	t.check(a.extras.is_empty(), "known keys are not extras")


func test_unknown_pairs_land_in_extras(t: TestCtx) -> void:
	var a: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--preview=tip,drag", "--popup=1", "--verbose", "--page=graphics", "loose"]))
	t.eq(a.extras["preview"], "tip,drag")
	t.eq(a.extras["popup"], "1")
	t.eq(a.extras["page"], "graphics")
	t.eq(a.extras["verbose"], true, "a bare unknown flag is true")
	t.eq(a.positional, PackedStringArray(["loose"]))
	t.check(not a.smoke and not a.selfcheck and a.screen == &"")


func test_autostart_and_numbers(t: TestCtx) -> void:
	var a: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--autostart=match", "--config=cfg/match.json", "--ticks=6000",
		"--quit-on-end", "--speed=0", "--no-audio", "--no-prewarm", "--fresh-settings", "--faction=han", "--palette=cvd",
		"--with-ui", "--timeout-s=30", "--renderer-relaunched"]))
	t.eq(a.autostart, &"match")
	t.eq(a.config_path, "cfg/match.json")
	t.eq(a.ticks, 6000)
	t.check(a.quit_on_end and a.no_audio and a.no_prewarm and a.fresh_settings and a.with_ui and a.renderer_relaunched)
	t.eq(a.speed_pct, 0, "--speed=0 = unpaced")
	t.eq(a.faction, "han")
	t.eq(a.palette, "cvd")
	t.eq(a.timeout_s, 30)
	t.check(a.is_test_mode())
	t.eq(AppLaunchArgs.parse(PackedStringArray()).speed_pct, 100, "default speed 100 %")


func test_explicit_false_and_modes(t: TestCtx) -> void:
	var a: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--smoke=0", "--no-audio=false"]))
	t.check(not a.smoke and not a.no_audio)
	t.check(not a.is_test_mode(), "a plain launch is not a test mode")
	var shot: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--shot=/tmp/x.png", "--frames=30"]))
	t.check(shot.shot and not shot.manages_window(), "screenshot runs keep the window as the tool sized it")
	t.check(shot.is_test_mode(), "and never write the session sentinel")
	t.check(AppLaunchArgs.parse(PackedStringArray()).manages_window())
