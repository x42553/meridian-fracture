extends RefCounted
## REP2 app level: `AppReplay.start` -> `AppMatchContext` over a `NetReplayPlayer` (the golden app-recorded replay), seeks forward and
## backward with the ports re-bound, the version gate, the observer HUD of `UiScreenGame` for replays / all-AI sessions / defeated
## players, the end-screen buttons, saving a recording, the desync dialog button and the replay menu.

const H := preload("res://tests/ui/ui_harness.gd")
const U := preload("res://tests/ui/app_test_util.gd")
const FIXTURE: String = "res://tests/fixtures/net/replays/app_ai_2p_3min.mfreplay"


func _start(opts: Dictionary = {}) -> AppMatchContext:
	var o: Dictionary = {"with_view": false, "bind": false, "local_versions": {}}
	for k: Variant in opts:
		o[k] = opts[k]
	var ctx: AppMatchContext = AppReplay.start(FIXTURE, o)
	if ctx == null:
		return null
	_drive(ctx, func() -> bool: return ctx.replay.is_ready or ctx.replay.is_failed)
	return ctx


## Runs `ctx.frame()` until `until` is true (a real-time guard: world builds use a worker thread).
func _drive(ctx: AppMatchContext, until: Callable, max_ms: int = 60000) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not until.call() and Time.get_ticks_msec() - t0 < max_ms:
		ctx.frame()
		OS.delay_msec(1)
	return until.call()


func _seek(ctx: AppMatchContext, tick: int) -> void:
	ctx.replay.set_speed(NetReplayPlayer.MAX)
	ctx.replay.seek(tick)
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())


func _dispose(ctx: AppMatchContext) -> void:
	ctx.dispose()
	AppState.match_ctx = null


# ---------------------------------------------------------------- the replay context

func test_replay_context_is_an_observer_and_verifies(t: TestCtx) -> void:
	t.set_timeout(180.0)
	var ctx: AppMatchContext = _start()
	if not t.not_null(ctx, "the replay starts: %s" % AppReplay.last_error):
		return
	t.check(ctx.replay.is_ready, "the world is built")
	t.check(ctx.is_replay and ctx.is_observer and ctx.local_pid == -1, "a replay context is an observer context")
	t.is_null(ctx.session, "it owns no network session")
	t.check(ctx.net is UiNetPortNull and not ctx.net.can_submit(), "commands are refused")
	t.eq(ctx.sim.viewer_pid(), -1, "everything is visible (fog off)")
	t.eq(ctx.sim.local_pid(), -1)
	t.eq(ctx.skin.code, "neutral", "replays wear the neutral skin")
	t.eq(ctx.tick(), 0)
	t.check(AppState.match_ctx == ctx, "registered as the match context")
	t.check(AppNet.ctx == ctx, "AppNet drives it")
	_seek(ctx, 1200)
	t.eq(ctx.tick(), 1200, "a forward seek lands exactly")
	t.eq(ctx.replay.verified_through(), 1200, "every CHECK up to there matched")
	t.eq(ctx.replay.diverged_tick(), -1)
	t.eq(ctx.sim.tick(), 1200, "the sim port reads the replayed world")
	_seek(ctx, ctx.replay.end_tick())
	t.check(ctx.replay.is_finished(), "the recorded end is reached")
	t.eq(ctx.replay.diverged_tick(), -1, "no divergence over the whole recording")
	var data: NetReplayData = ctx.replay.data
	t.eq(ctx.world().checksum() & 0xFFFFFFFF, int(data.end["final_checksum"]) & 0xFFFFFFFF, "the final checksum is the recorded one")
	t.eq(ctx.replay.player.input_chain() & 0xFFFFFFFF, int(data.end["final_chain"]) & 0xFFFFFFFF, "and so is the input chain")
	t.eq(int(ctx.last_end["final_tick"]), ctx.tick(), "last_end carries the recorded end")
	var sum: Dictionary = ctx.summary()
	t.eq((sum["players"] as Array).size(), 2, "the end-screen model builds for a replay")
	_dispose(ctx)


func test_backward_seek_rebinds_the_world_and_stays_deterministic(t: TestCtx) -> void:
	t.set_timeout(180.0)
	var ctx: AppMatchContext = _start()
	if not t.not_null(ctx):
		return
	_seek(ctx, 1000)
	var cs: int = ctx.world().checksum()
	var w1: SimWorld = ctx.world()
	var gen1: int = ctx.replay.player.generation()
	_seek(ctx, 400)
	t.eq(ctx.tick(), 400, "a backward seek lands exactly")
	t.gt(ctx.replay.player.generation(), gen1, "it rebuilt the world")
	t.check(ctx.world() != w1, "a new world object")
	t.check((ctx.sim as UiSimPortWorld).sim_world() == ctx.world(), "the sim port was re-bound to it")
	_seek(ctx, 1000)
	t.eq(ctx.world().checksum(), cs, "the same tick of the re-simulation has the same checksum")
	t.eq(ctx.replay.diverged_tick(), -1)
	ctx.replay.seek_by_seconds(-10)
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	t.eq(ctx.tick(), 800, "-10 s is 200 ticks back")
	_dispose(ctx)


func test_stage_rebind_follows_a_rebuilt_world(t: TestCtx) -> void:
	t.set_timeout(180.0)
	var ctx: AppMatchContext = _start()
	if not t.not_null(ctx):
		return
	_seek(ctx, 600)
	var h: H.Rig = await H.make()
	var stage: AppViewStage = AppViewStage.new()
	stage.full_look = false
	stage.with_fx = false
	h.root.add_child(stage)
	stage.build_sync(ctx.world(), -1)
	var count: Callable = func(w: SimWorld) -> int:
		var n: int = 0
		for e: SimEntity in w.by_id:
			if e != null and (e.flags & SimFlags.F_GONE) == 0:
				n += 1
		return n
	t.eq(stage.view.entity_count(), int(count.call(ctx.world())), "the stage mirrors the world")
	_seek(ctx, 200)
	stage.rebind_world(ctx.world())
	t.eq(stage.view.entity_count(), int(count.call(ctx.world())), "after a rebuild the stage mirrors the NEW world")
	t.check(stage.view.sim == ctx.world(), "the view reads the new world")
	stage.set_perspective(0)
	t.eq(stage.perspective(), 0)
	t.eq(stage.view.local_pid, 0, "the view follows the perspective")
	stage.set_perspective(-1)
	t.check(stage.view.observer, "-1 is the observer again")
	stage.teardown()
	stage.queue_free()
	_dispose(ctx)
	H.done(h)
	await H.frames(2)


func test_the_golden_replay_passes_the_gate_of_this_build(t: TestCtx) -> void:
	var info: Dictionary = NetReplay.read_info(FIXTURE, AppReplay.local_versions())
	t.check(bool(info["compatible"]), "the app-recorded golden replay is playable by this build: %s" % str(info["incompatible_reason"]))
	t.check(UiReplayModel.playable(info))
	t.note("data hash warning: '%s'" % str(info["warning"]))


func test_the_version_gate_refuses_other_builds(t: TestCtx) -> void:
	var ctx: AppMatchContext = AppReplay.start(FIXTURE, {"with_view": false, "bind": false, "local_versions": {"sim": 987654}})
	t.is_null(ctx, "a replay of another simulation version is not started")
	t.check(AppReplay.last_error.contains("simulation version"), "and says why: %s" % AppReplay.last_error)
	var missing: AppMatchContext = AppReplay.start("res://tests/fixtures/net/replays/".path_join("none") + ".mfreplay", {"with_view": false, "bind": false})
	t.is_null(missing)
	t.check(AppReplay.last_error != "", "a missing file reports an error")
	var soft: Dictionary = NetReplay.local_versions(AppNetSetup.make_options(GameData.load_default(), {}))
	t.check(soft.has("sim") and soft.has("data_hash"), "this build's versions")


func test_event_marks_come_from_the_recorded_events(t: TestCtx) -> void:
	var d: NetReplayData = NetReplayData.new()
	d.config = {"players": [{"pid": 0, "name": "Ann"}, {"pid": 1, "name": "Bob"}]}
	d.events = [
		{"turn": 100, "kind": NetProtocol.ReplayEvent.PLAYER_STATUS, "args": PackedInt32Array([1, NetProtocol.PlayerNetStatus.RESIGNED, 0]), "text": ""},
		{"turn": 50, "kind": NetProtocol.ReplayEvent.CHAT, "args": PackedInt32Array([0]), "text": "gg"},
		{"turn": 300, "kind": NetProtocol.ReplayEvent.PLAYER_STATUS, "args": PackedInt32Array([0, NetProtocol.PlayerNetStatus.DEFEATED, 0]), "text": ""},
		{"turn": 400, "kind": NetProtocol.ReplayEvent.PLAYER_STATUS, "args": PackedInt32Array([0, NetProtocol.PlayerNetStatus.ACTIVE, 0]), "text": ""},
	]
	var marks: Array[Dictionary] = AppReplay.event_marks(d)
	t.eq(marks.size(), 3, "an ACTIVE status is no event")
	t.eq(int(marks[0]["tick"]), 100, "turn 50 = tick 100, ascending")
	t.eq(str(marks[0]["kind"]), "chat")
	t.eq(str(marks[1]["kind"]), "resigned")
	t.eq(str(marks[1]["text"]), "Bob resigned")
	t.eq(int(marks[1]["tick"]), 200)
	t.eq(str(marks[2]["kind"]), "defeated")
	t.eq(int(marks[2]["pid"]), 0)


# ---------------------------------------------------------------- observer model over a real world

func test_observer_model_reads_a_real_world(t: TestCtx) -> void:
	t.set_timeout(180.0)
	var ctx: AppMatchContext = _start()
	if not t.not_null(ctx):
		return
	var ov: Dictionary = {}
	ctx.sim.player_overview(0, ov)
	t.eq(int(ov["present"]), 1)
	t.check(ov.has("credits") and ov.has("army_value") and ov.has("base_x"), "the overview carries the observer keys")
	ctx.sim.player_overview(5, ov)
	t.check(ov.is_empty(), "a pid beyond the players has no overview")
	var model: UiObserverModel = UiObserverModel.new()
	_seek(ctx, 1600)
	model.update(ctx.sim, true)
	t.eq(model.rows.size(), 2, "one row per player")
	t.eq(int(model.rows[0]["pid"]), 0)
	t.check(str(model.rows[0]["faction"]) != "", "the faction code comes from the roster")
	_seek(ctx, 2600)
	model.update(ctx.sim, true)
	var r0: Dictionary = model.row_of(0)
	t.gt(int(r0["army_value"]) + int(r0["structs"]), 0, "player 0 has an army or structures at 2:10")
	t.ge(int(r0["income"]), 0, "income is a rolling per-minute figure")
	t.ge(int(model.row_of(1)["share"]), 0)
	var tgt: Vector2i = model.follow_target(0)
	t.check(tgt.x >= 0, "the follow camera has a target")
	t.eq(model.follow_target(7), Vector2i(-1, -1), "none for a pid that is not playing")
	t.eq(model.next_pid(0, 1), 1)
	t.eq(model.next_pid(1, 1), 0, "Tab wraps")
	t.eq(model.next_pid(-1, 1), 0, "from all players Tab starts at the first")
	_seek(ctx, 400)
	t.check(model.update(ctx.sim), "a rewind resamples at once")
	t.eq(model.rows.size(), 2)
	_dispose(ctx)


# ---------------------------------------------------------------- the observer HUD in the game screen

func _game(ctx: AppMatchContext, h: H.Rig) -> UiScreenGame:
	var game: UiScreenGame = UiScreenGame.new()
	h.root.add_child(game)
	UiLayerRoot.fill(game)
	game.enter({"ctx": ctx})
	return game


func _leave(game: UiScreenGame, ctx: AppMatchContext, h: H.Rig) -> void:
	game.exit()
	_dispose(ctx)
	game.queue_free()
	H.done(h)


func test_replay_runs_in_the_observer_hud(t: TestCtx) -> void:
	t.set_timeout(180.0)
	var ctx: AppMatchContext = _start()
	if not t.not_null(ctx):
		return
	var h: H.Rig = await H.make()
	var game: UiScreenGame = _game(ctx, h)
	await H.frames(3)
	t.eq(game.hud.mode, UiHud.MODE_OBSERVER, "the HUD is in observer mode")
	t.check(game.presenter.observer, "the presenter knows")
	t.not_null(game.observer_ctl, "the observer controller exists")
	t.not_null(game.hud.observer_bar(), "with its bar")
	t.not_null(game.hud.scoreboard(), "and the scoreboard")
	t.not_null(game.hud.replay_bar(), "a replay adds the replay bar")
	t.check(game.hud.sidebar().observer_content() == game.hud.observer_bar(), "the bar replaces the build area of the sidebar")
	t.eq(game.hud.observer_bar().row_count(), 2, "one row per player")
	t.is_null(game.overlays, "no net overlays in a replay")
	t.eq(game.observer_ctl.perspective, -1, "all players first")
	t.eq(ctx.sim.viewer_pid(), -1)
	# perspective: keys 1..8, 0, Tab, F
	var oc: UiObserverController = game.observer_ctl
	game._on_action(&"obs_player_2")
	t.eq(oc.perspective, 1)
	t.eq(ctx.sim.viewer_pid(), 1, "the sim port reads that player's vision")
	game._on_action(&"obs_all")
	t.eq(oc.perspective, -1)
	game._on_action(&"obs_player_1")
	game._on_action(&"obs_next_player")
	t.eq(oc.perspective, 1, "Tab goes to the next player")
	game._on_action(&"obs_toggle_fog")
	t.eq(oc.perspective, -1, "F switches the fog off")
	game._on_action(&"obs_toggle_fog")
	t.eq(oc.perspective, 1, "and back to the last player")
	game._on_action(&"obs_player_7")
	t.eq(oc.perspective, 1, "a key of a player that is not in the match does nothing")
	# follow camera: the camera key toggles, manual panning ends it
	game._on_action(&"obs_follow")
	t.check(oc.follow and game.hud.observer_bar()._follow_btn.button_pressed, "C starts the follow camera")
	game._free_camera()
	t.check(not oc.follow, "manual camera input frees the camera")
	game._on_action(&"toggle_scoreboard")
	t.check(game.hud.scoreboard().visible, "F2 opens the scoreboard")
	game._on_action(&"toggle_scoreboard")
	t.check(not game.hud.scoreboard().visible)
	# an observer gives no orders
	var before: int = ctx.commands_sent
	game._on_context_click(Vector2(300.0, 300.0), 0)
	t.eq(ctx.commands_sent, before, "right clicks are ignored")
	# the transport drives the replay
	var rb: UiReplayBar = game.hud.replay_bar()
	rb.speed_chosen.emit(4.0)
	t.eq(ctx.replay.speed(), 4.0, "the chips set the speed")
	game._on_action(&"obs_speed_up")
	t.eq(ctx.replay.speed(), 8.0, "] is one chip up")
	game._on_action(&"obs_speed_down")
	game._on_action(&"obs_speed_down")
	t.eq(ctx.replay.speed(), 2.0)
	rb.pause_toggled.emit()
	t.check(ctx.replay.is_paused(), "pause from the bar")
	game._on_action(&"obs_pause")
	t.check(not ctx.replay.is_paused(), "Space resumes")
	rb.seek_requested.emit(800)
	ctx.replay.set_speed(NetReplayPlayer.MAX)
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	ctx.replay.set_paused(true)  # hold the playhead: at MAX it would run on during the frames below
	await H.frames(2)
	t.eq(ctx.tick(), 800, "a seek from the bar lands on its tick")
	t.eq(rb.tick, 800, "and the bar shows it")
	t.eq(rb.end_tick, ctx.replay.end_tick())
	game._on_action(&"obs_seek_back")
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	t.eq(ctx.tick(), 600, ", is 10 s back")
	# events: a jump goes a few seconds before the next mark
	oc._discovered[1] = 1500
	rb.event_jump.emit(1)
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	t.eq(ctx.tick(), 1500 - UiObserverController.JUMP_LEAD_TICKS, "an event jump lands slightly before the event")
	rb.event_jump.emit(1)
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	t.eq(ctx.tick(), 1500, "the next jump lands on it")
	# the replay menu
	game.open_menu()
	t.not_null(game._menu, "Esc opens the replay menu")
	var texts: PackedStringArray = PackedStringArray()
	for b: Node in game._menu.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	t.check(texts.has("Leave replay") and not texts.has("Surrender"), "with Leave replay and no Surrender: %s" % str(texts))
	t.check(ctx.replay.is_paused(), "the replay pauses while the menu is open")
	var nav: Array = []
	game.navigate.connect(func(target: StringName, _p: Dictionary) -> void: nav.append(target))
	game._menu.close(UiDlgGameMenu.RESULT_LEAVE)
	await H.frames(2)
	t.eq(nav, [&"replays"], "Leave replay goes back to the browser")
	_leave(game, ctx, h)
	await H.frames(2)


func test_all_ai_session_shows_the_observer_hud(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var cfg: Dictionary = AppMatch.simple_config(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), 6, 96, 0, 0)
	var ctx: AppMatchContext = AppMatch.start_local(cfg, {"with_view": false, "bind": false, "unpaced": true})
	var guard: int = 0
	while ctx.session.phase == NetSession.Phase.LOADING and guard < 4000:
		ctx.session.poll()
		OS.delay_msec(2)
		guard += 1
	t.eq(ctx.local_pid, -1, "no human slot")
	var h: H.Rig = await H.make()
	var game: UiScreenGame = _game(ctx, h)
	await H.frames(3)
	t.eq(game.hud.mode, UiHud.MODE_OBSERVER, "an all-AI session no longer shows the player HUD")
	t.is_null(game.hud.replay_bar(), "no replay transport in a live session")
	t.eq(ctx.sim.viewer_pid(), -1, "watching everyone")
	t.check(ctx.net is UiNetPortNull, "no commands")
	t.eq(game.hud.observer_bar().row_count(), 2)
	game._on_action(&"obs_player_2")
	t.eq(ctx.sim.viewer_pid(), 1)
	game._on_action(&"obs_pause")  # net refuses a pause without a pid: nothing happens, nothing breaks
	t.check(not ctx.session.is_paused(), "a session without a human cannot be paused by its observer")
	_leave(game, ctx, h)
	await H.frames(2)


func test_a_defeated_player_keeps_watching_in_the_observer_hud(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var cfg: Dictionary = AppMatch.simple_config(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), 6, 96)
	var ctx: AppMatchContext = AppMatch.start_local(cfg, {"with_view": false, "bind": false, "unpaced": true})
	var guard: int = 0
	while ctx.session.phase == NetSession.Phase.LOADING and guard < 4000:
		ctx.session.poll()
		OS.delay_msec(2)
		guard += 1
	var h: H.Rig = await H.make()
	var game: UiScreenGame = _game(ctx, h)
	await H.frames(3)
	t.eq(game.hud.mode, UiHud.MODE_PLAYER, "a playing human has the player HUD")
	t.is_null(game.observer_ctl)
	game._on_player_status(0, NetProtocol.PlayerNetStatus.RESIGNED)
	await H.frames(3)
	t.eq(game.hud.mode, UiHud.MODE_OBSERVER, "a surrendered player gets the observer HUD")
	t.check(game.presenter.observer)
	t.not_null(game.observer_ctl)
	t.eq(game.observer_ctl.perspective, 0, "on their own perspective")
	t.eq(ctx.sim.viewer_pid(), 0)
	game._on_action(&"obs_all")
	t.eq(ctx.sim.viewer_pid(), -1, "and can watch everyone")
	t.check(game.hud.observer_bar().row_count() >= 2)
	t.check(UiKeymap.instance().installed_ids().has(&"obs_all"), "the observer keymap is installed")
	_leave(game, ctx, h)
	await H.frames(2)


# ---------------------------------------------------------------- end screen, saving, dialogs

func test_end_screen_replay_buttons(t: TestCtx) -> void:
	var h: H.Rig = await H.make()
	var end: UiScreenEnd = UiScreenEnd.new()
	h.root.add_child(end)
	UiLayerRoot.fill(end)
	end.enter({"summary": {"players": [], "series": {}, "result": "draw", "winner_team": -1, "duration_ticks": 0, "map": "", "seed": 0, "replay_path": "", "can_save_replay": false}})
	await H.frames(2)
	t.check(end._save_replay.disabled and end._watch_replay.disabled, "an unrecorded match offers neither")
	end.exit()
	end.queue_free()
	var end2: UiScreenEnd = UiScreenEnd.new()
	h.root.add_child(end2)
	UiLayerRoot.fill(end2)
	end2.enter({"summary": {"players": [], "series": {}, "result": "draw", "winner_team": -1, "duration_ticks": 0, "map": "", "seed": 0, "replay_path": FIXTURE, "can_save_replay": true}})
	await H.frames(2)
	t.check(not end2._save_replay.disabled and not end2._watch_replay.disabled, "a recorded match offers Save replay and Watch replay")
	t.eq(end2._save_replay.text, "SAVE REPLAY")
	t.eq(end2._watch_replay.text, "WATCH REPLAY")
	end2.exit()
	H.done(h)
	await H.frames(2)


func test_watching_from_the_end_screen_starts_the_replay_and_keeps_it(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var h: H.Rig = await H.make()
	var end: UiScreenEnd = UiScreenEnd.new()
	h.root.add_child(end)
	UiLayerRoot.fill(end)
	var old: AppMatchContext = AppMatch.start_local(AppMatch.simple_config(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), 6, 96), {"with_view": false, "bind": false, "unpaced": true})
	end.enter({"summary": {"players": [], "series": {}, "result": "draw", "winner_team": -1, "duration_ticks": 0, "map": "", "seed": 0, "replay_path": FIXTURE, "can_save_replay": true}})
	await H.frames(2)
	var nav: Array = []
	end.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	# the gate of the test process: the fixture was recorded by an older data hash only if the project's data changed; refuse politely then
	end._on_watch_replay()
	if nav.is_empty():
		t.note("the golden replay is not playable with this build's versions (a dialog was shown): %s" % AppReplay.last_error)
		end.exit()
		H.done(h)
		return
	t.eq(nav[0][0], &"loading", "Watch replay goes through the loading screen")
	t.eq((nav[0][1] as Dictionary).get("kind", ""), "replay")
	var rctx: AppMatchContext = AppState.match_ctx
	t.check(rctx != null and rctx.is_replay, "the replay context is the match context now")
	t.check(old.disposed, "the finished match was let go")
	end.exit()  # leaving the end screen must not dispose the replay that was just started
	t.check(not rctx.disposed, "the end screen only disposes its own context")
	_dispose(rctx)
	H.done(h)
	await H.frames(2)


func test_saving_the_recording_of_a_session(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var ctx: AppMatchContext = AppMatch.start_local(AppMatch.simple_config(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), 6, 96, 0, 0),
		{"with_view": false, "bind": false, "unpaced": true, "ticks": 400})
	var guard: int = 0
	while not ctx.limit_reached and guard < 40000:
		ctx.frame()
		OS.delay_msec(1)
		guard += 1
	t.check(AppReplay.can_save(ctx.session), "a running match can be saved (the memory mirror)")
	var dir: String = U.sandbox("save")
	var path: String = AppReplay.save_session(ctx.session, "My: best/match", dir)
	t.check(path != "" and FileAccess.file_exists(path), "saved: %s %s" % [path, AppReplay.last_error])
	t.eq(path.get_file(), "My_ best_match.mfreplay", "under the sanitised name")
	var data: NetReplayData = NetReplayData.load_file(path)
	t.not_null(data, "the file is a valid replay")
	var again: String = AppReplay.save_session(ctx.session, "My: best/match", dir)
	t.eq(again.get_file(), "My_ best_match_2.mfreplay", "a second save does not overwrite")
	var info: Dictionary = NetReplay.read_info(path, {})
	t.check(bool(info["valid"]) and (info["players"] as Array).size() == 2, "the browser can list it")
	t.check(AppReplay.default_name(ctx.config, 1790000000).contains("2026-09-21"), "the default name carries the date")
	var sum: Dictionary = ctx.summary({"reason": 0, "winner_team": -1, "final_tick": 400, "final_checksum": 0})
	t.check(bool(sum["can_save_replay"]), "the end-screen model says the recording can be saved")
	U.cleanup(dir)
	_dispose(ctx)


func test_desync_dialog_offers_save_replay(t: TestCtx) -> void:
	var d: UiDlgDesync = UiDlgDesync.new({"tick": 400, "kind": "SIM"})
	var texts: PackedStringArray = PackedStringArray()
	for b: Node in d.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	t.check(texts.has("Save replay"), "the desync dialog has Save replay: %s" % str(texts))
	d.save_replay()  # no session: nothing happens, nothing breaks
	t.is_null(d.session)
	d.free()


func test_replay_menu_has_no_surrender(t: TestCtx) -> void:
	var m: UiDlgGameMenu = UiDlgGameMenu.new(true, false, true)
	var texts: PackedStringArray = PackedStringArray()
	for b: Node in m.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	t.check(texts.has("Resume") and texts.has("Leave replay") and not texts.has("Surrender") and not texts.has("Leave match"), "items: %s" % str(texts))
	t.eq(m.get_title(), "REPLAY MENU")
	t.check(m.footer().begins_with("The replay is paused"))
	m.free()


func test_keymap_has_the_observer_actions(t: TestCtx) -> void:
	var km: UiKeymap = UiKeymap.instance()
	if km.action_ids().is_empty():
		km.load_defaults()
	for id: String in ["obs_follow", "obs_event_next", "obs_event_prev", "obs_seek_back", "obs_seek_fwd", "toggle_scoreboard", "obs_pause", "obs_speed_up"]:
		t.check(km.action_ids().has(StringName(id)), "action %s exists" % id)
		t.check(UiActionNames.label(id) != "", "and has a label: %s" % id)


func test_replay_browser_watch_starts_the_playback(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var dir: String = U.sandbox("watch")
	DirAccess.copy_absolute(FIXTURE, dir.path_join("Duel.mfreplay"))
	DirAccess.copy_absolute(FIXTURE, dir.path_join("Other.mfreplay"))
	var h: H.Rig = await H.make()
	var scr: UiScreenReplays = UiScreenReplays.new()
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr.enter({"dir": dir, "select": dir.path_join("Other.mfreplay")})
	scr.read_all()
	await H.frames(2)
	t.eq(str(scr.selected_info().get("name", "")), "Other", "the select parameter picks that replay (the recovered replay of the crash toast)")
	var nav: Array = []
	scr.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	scr._on_watch()
	t.eq(nav.size(), 1, "Watch navigates")
	t.eq(nav[0][0], &"loading", "to the loading screen")
	t.eq((nav[0][1] as Dictionary).get("kind", ""), "replay")
	var ctx: AppMatchContext = AppState.match_ctx
	if t.check(ctx != null and ctx.is_replay, "the playback context is registered"):
		_drive(ctx, func() -> bool: return ctx.replay.is_ready)
		t.check(ctx.replay.is_ready, "and builds")
		t.eq(ctx.replay.path, dir.path_join("Other.mfreplay"), "from the selected file")
		t.eq(ctx.title, "Replay")
		_dispose(ctx)
	scr.exit()
	H.done(h)
	await H.frames(2)
	U.cleanup(dir)
