extends RefCounted
## MIS2 app level: the campaign progress model and its crash-safe persistence (`AppCampaign`, user://campaign.cfg), the mission launch
## glue (`AppMission`: difficulty -> AI levels, LOCAL session, campaign bookkeeping at the end, the result model), the flow edges of the
## new screens, and the headless boot line protocol of `--autostart=mission=<id>`.

const U := preload("res://tests/ui/app_test_util.gd")
const Kit := preload("res://tests/ui/mission_ui_kit.gd")


func _drive(ctx: AppMatchContext, max_frames: int = 40000) -> void:
	var guard: int = 0
	while ctx.session.phase != NetSession.Phase.ENDED and guard < max_frames:
		ctx.frame()
		OS.delay_msec(1)
		guard += 1


## `AppState.data` and `AppState.profile.campaign` swapped for the test (restore with `_restore`).
func _install(extra: Dictionary) -> Array:
	var old_data: Variant = AppState.data
	var old_campaign: AppCampaign = AppState.profile.campaign
	AppState.data = Kit.data(extra)
	AppState.profile.campaign = AppCampaign.new()
	return [old_data, old_campaign]


func _restore(saved: Array) -> void:
	AppState.data = saved[0] as GameData
	AppState.profile.campaign = saved[1] as AppCampaign
	AppState.match_ctx = null


# ---------------------------------------------------------------- progress model

func test_records_wins_best_time_and_difficulty(t: TestCtx) -> void:
	var c: AppCampaign = AppCampaign.new()
	t.check(c.in_memory, "a fresh campaign lives in memory")
	t.check(not c.completed("m1") and c.best_ticks("m1") == 0 and c.best_difficulty("m1") == -1, "unknown mission: nothing recorded")
	t.eq(c.last_difficulty("m1"), 1, "default difficulty Medium")
	c.note_start("m1", 2)
	t.eq(c.plays("m1"), 1)
	t.eq(c.last_difficulty("m1"), 2, "the difficulty of the last start")
	var loss: Dictionary = c.record_result("m1", false, 900, 2)
	t.check(not c.completed("m1") and not bool(loss["first_clear"]), "a loss completes nothing")
	var a: Dictionary = c.record_result("m1", true, 4000, 1)
	t.check(bool(a["first_clear"]) and bool(a["new_best_time"]) and bool(a["new_best_difficulty"]), "first win: everything is new")
	t.check(c.completed("m1"))
	t.eq(c.best_ticks("m1"), 4000)
	t.eq(c.best_difficulty("m1"), 1)
	var b: Dictionary = c.record_result("m1", true, 5000, 3)
	t.check(not bool(b["first_clear"]) and not bool(b["new_best_time"]) and bool(b["new_best_difficulty"]), "slower win on a harder level: only the difficulty improves")
	t.eq(c.best_ticks("m1"), 4000, "the best time stays")
	t.eq(c.best_ticks_difficulty("m1"), 1, "...and remembers the difficulty it was set on")
	t.eq(c.best_difficulty("m1"), 3)
	var d: Dictionary = c.record_result("m1", true, 3000, 0)
	t.check(bool(d["new_best_time"]) and not bool(d["new_best_difficulty"]), "a faster win on Easy: new time, same highest difficulty")
	t.eq(c.best_ticks_difficulty("m1"), 0)
	t.eq(c.wins("m1"), 3)
	t.eq(c.completed_count(PackedStringArray(["m1", "m2"])), 1)


func test_text_round_trip_and_validation(t: TestCtx) -> void:
	var c: AppCampaign = AppCampaign.new()
	c.record_result("alpha", true, 1234, 2)
	c.note_start("beta", 3)
	var text: String = c.to_text()
	var r: AppCampaign = AppCampaign.new()
	t.check(r.from_text(text), "own text parses")
	t.check(r.completed("alpha") and r.best_ticks("alpha") == 1234 and r.best_difficulty("alpha") == 2, "alpha restored")
	t.eq(r.plays("beta"), 1)
	t.eq(r.mission_ids(), PackedStringArray(["alpha", "beta"]))
	var bad: AppCampaign = AppCampaign.new()
	t.check(not bad.from_text(""), "empty text is not a campaign")
	t.check(not bad.from_text("this is [not a config"), "garbage is refused")
	var nasty: String = "[meta]\nversion=1\n[m.good]\ndone=true\nbest_ticks=-5\nbest_diff=99\nwins=\"x\"\n[m.Bad Id!]\ndone=true\n[other]\nk=1\n"
	t.check(bad.from_text(nasty), "values are repaired, not trusted")
	t.check(bad.completed("good") and bad.best_ticks("good") == 0 and bad.best_difficulty("good") == 15, "negative time -> 0, difficulty clamped")
	t.eq(bad.wins("good"), 0, "a wrong-typed value falls back to the default")
	t.check(not bad.has_record("Bad Id!"), "an invalid mission id is dropped")
	t.check(bad.load_notes.size() >= 1, "and the load says so")


func test_disk_round_trip_and_in_memory_never_writes(t: TestCtx) -> void:
	var dir: String = U.sandbox("camp")
	var path: String = dir.path_join("campaign.cfg")
	var c: AppCampaign = AppCampaign.open(path)
	t.check(not c.in_memory, "open() is disk backed")
	t.eq(c.load_file(), ERR_FILE_NOT_FOUND, "first run: no file")
	c.record_result("alpha", true, 777, 1)
	t.check(FileAccess.file_exists(path), "a result is saved at once")
	t.check(not FileAccess.file_exists(path + ".tmp"), "no temp file is left behind")
	var again: AppCampaign = AppCampaign.open(path)
	t.check(again.completed("alpha") and again.best_ticks("alpha") == 777, "a new process reads it back")
	c.record_result("alpha", true, 700, 2)
	t.check(FileAccess.file_exists(path + ".bak"), "the previous version is kept as .bak")
	var mem: AppCampaign = AppCampaign.new()
	mem.path = dir.path_join("never.cfg")
	mem.record_result("x", true, 1, 1)
	t.check(not FileAccess.file_exists(dir.path_join("never.cfg")), "in-memory campaigns never touch the disk")
	U.cleanup(dir)


func test_crash_safe_save_survives_a_cut_at_every_step(t: TestCtx) -> void:
	var dir: String = U.sandbox("camp_crash")
	var path: String = dir.path_join("campaign.cfg")
	var seed_c: AppCampaign = AppCampaign.open(path)
	seed_c.record_result("alpha", true, 500, 1)
	for budget: int in 5:
		for half: bool in [false, true]:
			var layer: U.Crashy = U.Crashy.new(budget, half)
			var c: AppCampaign = AppCampaign.open(path)
			c.files = layer
			c.record_result("alpha", true, 400, 3)  # the save may be cut after `budget` file operations
			var back: AppCampaign = AppCampaign.open(path)
			t.check(back.completed("alpha"), "budget %d half %s: the progress survives a cut" % [budget, str(half)])
			t.check(back.best_ticks("alpha") == 500 or back.best_ticks("alpha") == 400, "budget %d half %s: old or new, never garbage (%d)" % [budget, str(half), back.best_ticks("alpha")])
			t.check(back.best_difficulty("alpha") == 1 or back.best_difficulty("alpha") == 3, "budget %d half %s: difficulty old or new" % [budget, str(half)])
			# reset to the seed state for the next round
			U.write(path, seed_c.to_text())
			for sfx: String in [".bak", ".tmp"]:
				if FileAccess.file_exists(path + sfx):
					DirAccess.remove_absolute(path + sfx)
	U.cleanup(dir)


func test_a_corrupt_file_is_moved_aside_and_the_backup_restores(t: TestCtx) -> void:
	t.expect_errors(2)  # ConfigFile.parse reports each broken file itself
	var dir: String = U.sandbox("camp_bad")
	var path: String = dir.path_join("campaign.cfg")
	var c: AppCampaign = AppCampaign.open(path)
	c.record_result("alpha", true, 500, 1)
	c.record_result("beta", true, 600, 1)  # the second save makes the first one the .bak
	U.write(path, "[[[ truncated")
	var r: AppCampaign = AppCampaign.open(path)
	t.check(r.completed("alpha"), "restored from the backup (the previous save)")
	t.check(r.load_notes.size() >= 2, "the notes say what happened: %s" % str(r.load_notes))
	var moved: bool = false
	for f: String in DirAccess.get_files_at(dir):
		moved = moved or f.contains(".bad-")
	t.check(moved, "the corrupt file was moved aside")
	U.write(path, "[[[ truncated")
	DirAccess.remove_absolute(path + ".bak")
	var empty: AppCampaign = AppCampaign.open(path)
	t.eq(empty.mission_ids().size(), 0, "nothing recoverable: empty progress, no crash")
	U.cleanup(dir)


# ---------------------------------------------------------------- difficulty and launch

func test_difficulty_shifts_the_ai_levels(t: TestCtx) -> void:
	t.expect_errors(1)  # the unknown mission is logged
	t.eq(AppMission.ai_level_for(1, 1), 1, "Medium = as authored")
	t.eq(AppMission.ai_level_for(1, 0), 0, "Easy = one level down")
	t.eq(AppMission.ai_level_for(1, 2), 2)
	t.eq(AppMission.ai_level_for(1, 3), 3)
	t.eq(AppMission.ai_level_for(0, 0), 0, "clamped below")
	t.eq(AppMission.ai_level_for(3, 3), AiFactory.level_count() - 1, "clamped above")
	t.eq(AppMission.clamp_difficulty(9), 3)
	t.eq(AppMission.difficulty_name(2), "Hard")
	var saved: Array = _install(Kit.campaign_set())
	var data: GameData = AppState.data
	var lv: Array = []
	for d: int in 4:
		var cfg: Dictionary = AppMission.build_config(data, "ut_op_a", d)
		lv.append(int(((cfg["players"] as Array)[1] as Dictionary)["ai"]["level"]))
		t.eq(cfg["mission"], "ut_op_a", "the config names the mission")
	t.eq(lv, [1, 2, 3, 3], "the authored level 2 shifts per difficulty")
	t.eq(AppMission.build_config(data, "nope").size(), 0, "an unknown mission has no config")
	_restore(saved)


func test_start_runs_a_mission_to_victory_and_records_it(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var saved: Array = _install({"ut_win": Kit.scripted("ut_win", "win")})
	var camp: AppCampaign = AppState.profile.campaign
	var ctx: AppMatchContext = AppMission.start("ut_win", 2, {"with_view": false, "bind": false, "unpaced": true})
	if not t.not_null(ctx, "the mission starts: %s" % NetSession.last_create_error):
		_restore(saved)
		return
	t.eq(ctx.mission_id(), "ut_win", "the context knows the mission (also read by the loading / game screens)")
	t.eq(ctx.mission_difficulty, 2)
	t.eq(ctx.title, "Scripted ut_win", "the title is the mission's")
	t.eq(ctx.session.role, NetSession.Role.LOCAL, "a mission is a LOCAL session: one code path with skirmish")
	t.eq(camp.plays("ut_win"), 1, "starting counts a play")
	_drive(ctx)
	t.eq(ctx.session.phase, NetSession.Phase.ENDED, "the script ended the match")
	var w: SimWorld = ctx.world()
	t.eq(w.mission.result, SimMissionConst.RES_WIN)
	t.eq(w.mission.result_tick, 100, "won at the scripted tick")
	var out: Dictionary = ctx.mission_outcome
	t.check(bool(out.get("won", false)) and bool(out.get("first_clear", false)), "the campaign outcome: a first clear")
	t.eq(int(out.get("ticks", 0)), 100)
	t.check(camp.completed("ut_win") and camp.best_ticks("ut_win") == 100 and camp.best_difficulty("ut_win") == 2, "recorded in the profile's campaign")
	var model: Dictionary = AppMission.result_model(ctx, ctx.summary())
	t.check(bool(model["won"]), "result model: won")
	t.eq(model["title"], "Scripted ut_win")
	t.eq(model["difficulty_name"], "Hard")
	t.eq(model["clock"], "0:05")
	var words: PackedStringArray = PackedStringArray()
	for o: Variant in model["objectives"] as Array:
		words.append("%s=%d" % [(o as Dictionary)["text"], int((o as Dictionary)["state"])])
	t.eq(words, PackedStringArray(["First thing=2", "Keep the base=2", "Optional thing=3"]),
		"objectives: primaries first; the primary left open when the mission is won counts as complete; the optional one failed")
	t.check((model["stats"] as Dictionary).has("units_killed"), "the debrief carries the local player's stats")
	ctx.dispose()
	_restore(saved)


func test_a_lost_or_surrendered_mission_is_a_defeat(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var saved: Array = _install({"ut_lose": Kit.scripted("ut_lose", "lose")})
	var camp: AppCampaign = AppState.profile.campaign
	var ctx: AppMatchContext = AppMission.start("ut_lose", 1, {"with_view": false, "bind": false, "unpaced": true})
	_drive(ctx)
	t.eq(ctx.world().mission.result, SimMissionConst.RES_LOSE)
	t.check(not bool(ctx.mission_outcome.get("won", true)), "outcome: lost")
	t.check(not camp.completed("ut_lose"), "nothing completed")
	t.eq(camp.plays("ut_lose"), 1)
	var model: Dictionary = AppMission.result_model(ctx, ctx.summary())
	var states: Array = []
	for o: Variant in model["objectives"] as Array:
		states.append(int((o as Dictionary)["state"]))
	t.eq(states, [2, 1, 3], "defeat: the open primary stays open")
	ctx.dispose()
	# a surrender before the script ends is a defeat as well
	var c2: AppMatchContext = AppMission.start("ut_lose", 1, {"with_view": false, "bind": false, "unpaced": true})
	var guard: int = 0
	while c2.tick() < 20 and guard < 20000:
		c2.frame()
		guard += 1
	c2.session.surrender()
	_drive(c2)
	t.eq(c2.session.phase, NetSession.Phase.ENDED, "a surrender ends the mission")
	t.check(not bool(c2.mission_outcome.get("won", true)), "and is no win")
	c2.dispose()
	_restore(saved)


func test_unknown_mission_does_not_start(t: TestCtx) -> void:
	var saved: Array = _install({"ut_win": Kit.scripted("ut_win")})
	t.expect_errors(1)
	t.is_null(AppMission.start("no_such_mission", 1, {"with_view": false, "bind": false}), "unknown id: no context")
	_restore(saved)


# ---------------------------------------------------------------- flow

func test_flow_edges_and_screen_ids_of_the_campaign(t: TestCtx) -> void:
	var M: Dictionary = AppFlow.Mode
	t.check(AppFlow.can_go(M.MAIN_MENU, M.CAMPAIGN), "the main menu opens the campaign")
	t.check(AppFlow.can_go(M.CAMPAIGN, M.MISSION_BRIEFING) and AppFlow.can_go(M.MISSION_BRIEFING, M.LOADING), "campaign -> briefing -> loading")
	t.check(AppFlow.can_go(M.LOADING, M.CAMPAIGN), "a cancelled or failed mission load returns to the campaign")
	t.check(AppFlow.can_go(M.IN_MATCH, M.CAMPAIGN), "leaving a mission returns to the campaign")
	t.check(AppFlow.can_go(M.END_SCREEN, M.MISSION_BRIEFING) and AppFlow.can_go(M.END_SCREEN, M.CAMPAIGN) and AppFlow.can_go(M.END_SCREEN, M.LOADING), "result: next / campaign / retry")
	t.check(not AppFlow.can_go(M.MAIN_MENU, M.MISSION_BRIEFING), "no shortcut past the campaign screen")
	t.eq(AppFlow.screen_id_of(M.CAMPAIGN), &"campaign")
	t.eq(AppFlow.screen_id_of(M.MISSION_BRIEFING), &"mission_briefing")
	t.eq(AppFlow.screen_id_of(M.END_SCREEN), &"end")
	t.eq(AppFlow.screen_id_of(M.END_SCREEN, {"mission": {}}), &"mission_result", "an end with a mission model shows the mission result")
	t.eq(AppFlow.mode_of_screen(&"mission_result"), M.END_SCREEN)
	t.eq(AppFlow.mode_of_screen(&"campaign"), M.CAMPAIGN)
	t.eq(AppFlow.back_of(M.CAMPAIGN), M.MAIN_MENU)
	t.eq(AppFlow.back_of(M.MISSION_BRIEFING), M.CAMPAIGN)
	for id: StringName in [&"campaign", &"mission_briefing", &"mission_result"]:
		t.check(AppScreens.is_valid_id(id), "%s is a registered screen id" % id)
		var made: UiScreen = AppScreens.make(id)
		t.check(made != null and not (made is AppPlaceholderScreen), "%s has a real screen class" % id)
		if made != null:
			made.free()


func test_autostart_argument_and_boot_protocol(t: TestCtx) -> void:
	t.eq(AppMission.id_of_autostart("mission=op_napc"), "op_napc")
	t.eq(AppMission.id_of_autostart("match"), "")
	var a: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--autostart=mission=demo_ambush", "--difficulty=2", "--bots=human"]))
	t.eq(String(a.autostart), "mission=demo_ambush", "the argument keeps its '=' value")
	t.eq(int(a.extras["difficulty"]), 2)
	t.check(a.is_test_mode(), "an autostart is a test mode (never touches the real campaign file)")
