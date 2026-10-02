extends RefCounted
## MIS2 in the match: the mission presentation model (`UiMissionModel`), the objectives panel, caption feed, timer chips and the HUD layer
## (`UiMissionHud`) driven by the scripted events of a REAL mission world (a real sim stepped tick by tick, its real event records through
## `UiSimPortWorld`), the game screen with a mission (hotkey, camera hint, end of mission -> result screen) and a recorded mission replayed.

const H := preload("res://tests/ui/ui_harness.gd")
const U := preload("res://tests/ui/app_test_util.gd")
const Kit := preload("res://tests/ui/mission_ui_kit.gd")
const MK := preload("res://tests/support/mission_kit.gd")

var _saved_data: GameData = null


func _install(extra: Dictionary) -> GameData:
	_saved_data = AppState.data
	AppState.data = Kit.data(extra)
	UiSkinSet.shared().setup_from_json()
	return AppState.data


func _restore() -> void:
	if AppState.match_ctx is AppMatchContext:
		(AppState.match_ctx as AppMatchContext).dispose()
	AppState.match_ctx = null
	AppState.data = _saved_data


## A HUD over the real world of mission `id` plus the mission layer; `r` = {world, sim, audio, hud, mh, def}.
func _rig(h: H.Rig, d: GameData, id: String) -> Dictionary:
	var w: SimWorld = MK.world(d, id, {"events": true})
	var sim: UiSimPortWorld = UiSimPortWorld.new(w, 0)
	var audio: UiAudioPortRecorder = UiAudioPortRecorder.new()
	var hud: UiHud = UiHud.new()
	h.root.add_child(hud)
	UiLayerRoot.fill(hud)
	hud.setup(UiSkinSet.shared().skin_for("napc"), d, sim.roster_of(0), UiHud.MODE_PLAYER)
	var def: DefMission = AppMission.def_of(d, id)
	var mh: UiMissionHud = UiMissionHud.new()
	mh.setup(hud, sim, audio, def, false)
	return {"world": w, "sim": sim, "audio": audio, "hud": hud, "mh": mh, "def": def, "hints": []}


## The screen's loop in miniature: `ticks` sim ticks, then the frame's events and a frame of the layer.
func _pump(r: Dictionary, ticks: int) -> void:
	var w: SimWorld = r["world"] as SimWorld
	var sim: UiSimPortWorld = r["sim"] as UiSimPortWorld
	var mh: UiMissionHud = r["mh"] as UiMissionHud
	for _i: int in ticks:
		if w.match_state != SimWorld.MATCH_RUNNING:
			break
		w.step()
	mh.on_events(sim.take_events())
	mh.on_frame(0.2)


# ---------------------------------------------------------------- model

func test_constants_and_decoding(t: TestCtx) -> void:
	t.eq([UiMissionModel.S_HIDDEN, UiMissionModel.S_ACTIVE, UiMissionModel.S_COMPLETED, UiMissionModel.S_FAILED],
		[SimMissionConst.OBJ_HIDDEN, SimMissionConst.OBJ_ACTIVE, SimMissionConst.OBJ_COMPLETED, SimMissionConst.OBJ_FAILED], "objective states")
	t.eq([UiMissionModel.T_STOPPED, UiMissionModel.T_RUNNING, UiMissionModel.T_EXPIRED], [SimMissionConst.TM_STOPPED, SimMissionConst.TM_RUNNING, SimMissionConst.TM_EXPIRED])
	t.eq([UiMissionModel.R_NONE, UiMissionModel.R_WIN, UiMissionModel.R_LOSE], [SimMissionConst.RES_NONE, SimMissionConst.RES_WIN, SimMissionConst.RES_LOSE])
	t.eq([UiMissionModel.KIND_PRIMARY, UiMissionModel.KIND_SECONDARY, UiMissionModel.KIND_HIDDEN],
		[DefMissionObjective.Kind.PRIMARY, DefMissionObjective.Kind.SECONDARY, DefMissionObjective.Kind.HIDDEN])
	var recs: PackedInt32Array = PackedInt32Array()
	recs.append_array(PackedInt32Array([UiEv.MISSION_OBJECTIVE, 40, 0, 0, 2, UiMissionModel.S_COMPLETED, 0, UiMissionModel.S_ACTIVE, 0, 0]))
	recs.append_array(PackedInt32Array([UiEv.CASH, 41, 0, 0, 1, 5, 0, 0, 0, 0]))
	recs.append_array(PackedInt32Array([UiEv.MISSION_MESSAGE, 42, 0, 0, 1, 0, 0, 0, 0, 0]))
	recs.append_array(PackedInt32Array([UiEv.MISSION_CAMERA, 43, 5120, 7168, 3, 80, 0, 0, 0, 0]))
	recs.append_array(PackedInt32Array([UiEv.MISSION_MUSIC, 44, 0, 0, 2, 0, 0, 0, 0, 0]))
	var ev: Array[Dictionary] = UiMissionModel.decode(recs)
	t.eq(ev.size(), 4, "only mission records are decoded")
	t.eq(ev[0], {"type": &"objective", "tick": 40, "idx": 2, "state": 2, "kind": 0, "prev": 1})
	t.eq(ev[1]["type"], &"message")
	t.eq(ev[2], {"type": &"camera", "tick": 43, "x": 5120, "y": 7168, "area": 3, "ticks": 80})
	t.eq(ev[3], {"type": &"music", "tick": 44, "state": 2})


func test_model_rows_flash_and_timers(t: TestCtx) -> void:
	var d: GameData = Kit.data({"ut_hud": Kit.scripted("ut_hud")})
	var def: DefMission = AppMission.def_of(d, "ut_hud")
	var m: UiMissionModel = UiMissionModel.new()
	m.setup(def)
	# snapshot: result 0, tick 0, 3 objectives (active, hidden, active), 2 timers (running 400 ticks, running)
	var snap: PackedInt32Array = PackedInt32Array([0, 0, 3, 1, 0, 1, 2, 1, 400, 400, 1, 400, 400])
	var ch: PackedInt32Array = m.sync(snap, 0, 1000)
	t.eq(ch.size(), 0, "the first sync flashes nothing")
	var rows: Array[Dictionary] = m.rows()
	t.eq(rows.size(), 2, "the hidden objective is not listed")
	t.eq([rows[0]["text"], rows[1]["text"]], ["First thing", "Keep the base"], "primaries in declaration order")
	t.eq(m.progress(true), Vector2i(0, 2))
	var snap2: PackedInt32Array = PackedInt32Array([0, 30, 3, 1, 1, 1, 2, 1, 400, 400, 1, 400, 400])
	t.eq(m.sync(snap2, 30, 2000), PackedInt32Array([1]), "objective 2 turned active")
	rows = m.rows()
	t.eq([rows[0]["text"], rows[1]["text"], rows[2]["text"]], ["First thing", "Keep the base", "Optional thing"], "the optional one follows the primaries")
	var snap3: PackedInt32Array = PackedInt32Array([0, 60, 3, 2, 1, 1, 2, 1, 400, 400, 1, 400, 400])
	t.eq(m.sync(snap3, 60, 3000), PackedInt32Array([0]))
	t.eq(m.progress(true), Vector2i(1, 2))
	t.eq(m.progress(false), Vector2i(0, 1))
	t.eq(m.changed_msec[0], 3000, "the change time drives the flash")
	t.eq(m.sync(snap3, 61, 3100).size(), 0, "no change, no flash")
	var tm: Array[Dictionary] = m.visible_timers()
	t.eq(tm.size(), 1, "only the labelled timer is shown")
	t.eq(tm[0]["label"], "Reinforcements")
	t.eq(tm[0]["left_ticks"], 400 - 61)
	t.eq(UiMissionModel.clock_of(400), "0:20")
	t.eq(UiMissionModel.clock_of(21), "0:02", "rounded up to whole seconds")
	t.eq(UiMissionModel.clock_of(0), "0:00")
	t.eq(UiMissionModel.state_word(1, true), "NOT COMPLETED")
	t.eq(UiMissionModel.state_word(2), "COMPLETE")
	t.check(UiMissionModel.message_seconds("x") >= 5.0 and UiMissionModel.message_seconds("y".repeat(900)) <= 16.0, "reading time is clamped")
	var msg: Dictionary = m.message_of(0, 0)
	t.eq(msg["text"], "Commander, the raid begins soon.")
	t.eq(msg["speaker"], "Command")
	t.eq(msg["announcer"], "base_under_attack")
	t.eq(m.message_of(1, -1)["announcer"], "", "no announcer line")
	t.eq(m.message_of(9, 0).size(), 0, "a bad index is nothing")


# ---------------------------------------------------------------- widgets

func test_objectives_panel_flash_collapse_and_peek(t: TestCtx) -> void:
	var d: GameData = Kit.data({"ut_hud": Kit.scripted("ut_hud")})
	var m: UiMissionModel = UiMissionModel.new()
	m.setup(AppMission.def_of(d, "ut_hud"))
	var h: H.Rig = await H.make(Vector2i(800, 600))
	var panel: UiObjectivesPanel = UiObjectivesPanel.new()
	h.root.add_child(panel)
	panel.setup(m)
	m.sync(PackedInt32Array([0, 0, 3, 1, 0, 1, 2, 1, 400, 400, 1, 400, 400]), 0, Time.get_ticks_msec())
	panel.refresh()
	await H.frames(2)
	t.eq(panel.row_count(), 2)
	t.eq(panel.row_text(0), "First thing")
	t.eq(panel.header_text(), "OBJECTIVES  0 / 2")
	t.check(not panel.is_flashing(0), "nothing flashes at the start")
	var ch: PackedInt32Array = m.sync(PackedInt32Array([0, 20, 3, 2, 1, 1, 2, 1, 400, 400, 1, 400, 400]), 20, Time.get_ticks_msec())
	panel.refresh(ch)
	await H.frames(1)
	t.eq(panel.row_count(), 3, "the revealed objective appears")
	t.eq(panel.row_state(0), UiMissionModel.S_COMPLETED)
	t.eq(panel.header_text(), "OBJECTIVES  1 / 2")
	t.check(panel.is_flashing(0), "the objective that changed flashes")
	t.check(not panel.is_flashing(1) or panel.row_index(1) != 0, "...the others do not")
	# collapse / expand
	var got: Array = []
	panel.collapsed_changed.connect(func(c: bool) -> void: got.append(c))
	panel.toggle()
	t.check(panel.collapsed and not panel.peeking(), "collapsed: only the header")
	t.eq(got, [true])
	var ch2: PackedInt32Array = m.sync(PackedInt32Array([0, 40, 3, 2, 3, 1, 2, 1, 400, 400, 1, 400, 400]), 40, Time.get_ticks_msec())
	panel.refresh(ch2)
	t.check(panel.peeking(), "a change while collapsed shows the list for a while")
	panel.toggle()
	t.check(not panel.collapsed, "toggle expands again")
	t.eq(got, [true, false])
	t.eq(panel.row_state(2), UiMissionModel.S_FAILED)
	h.vp.queue_free()
	await H.frames(2)


func test_message_feed_stacks_and_expires(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(900, 500))
	var feed: UiMissionMessage = UiMissionMessage.new()
	h.root.add_child(feed)
	feed.post("First", "Command")
	feed.post("Second text that is a little longer than the first one", "")
	await H.frames(2)
	t.eq(feed.plate_count(), 2)
	t.eq(feed.plate_text(0), "First")
	t.eq(feed.plate_speaker(0), "Command")
	feed.post("Third")
	feed.post("Fourth")
	t.eq(feed.plate_count(), UiMissionMessage.MAX_PLATES, "at most three plates")
	t.eq(feed.plate_text(0), "Second text that is a little longer than the first one", "the oldest is pushed out")
	t.eq(feed.posted, 4)
	feed.post("Short lived", "", 0.1)
	await H.frames(1)
	OS.delay_msec(150)
	await H.frames(3)
	t.check(feed.plate_count() <= UiMissionMessage.MAX_PLATES, "plates expire on their own")
	feed.clear()
	t.eq(feed.plate_count(), 0)
	h.vp.queue_free()
	await H.frames(2)


func test_timer_chips_colour_and_update(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(600, 300))
	var tm: UiMissionTimers = UiMissionTimers.new()
	h.root.add_child(tm)
	tm.update([{"idx": 0, "label": "Raid", "left_ticks": 1200, "len_ticks": 1200}])
	await H.frames(1)
	t.eq(tm.chip_count(), 1)
	t.eq(tm.chip_text(0), "1:00")
	t.eq(tm.chip_label(0), "RAID")
	tm.update([{"idx": 0, "label": "Raid", "left_ticks": 150, "len_ticks": 1200}])
	t.eq(tm.chip_text(0), "0:08", "the text updates in place (rounded up)")
	tm.update([])
	await H.frames(1)
	t.eq(tm.chip_count(), 0, "an expired timer's chip goes")
	h.vp.queue_free()
	await H.frames(2)


# ---------------------------------------------------------------- the HUD layer on a real mission

func test_mission_hud_follows_a_real_mission_match(t: TestCtx) -> void:
	var d: GameData = _install({"ut_hud": Kit.scripted("ut_hud", "win")})
	var h: H.Rig = await H.make()
	var r: Dictionary = _rig(h, d, "ut_hud")
	var mh: UiMissionHud = r["mh"] as UiMissionHud
	var audio: UiAudioPortRecorder = r["audio"] as UiAudioPortRecorder
	var hud: UiHud = r["hud"] as UiHud
	var hints: Array = r["hints"]
	mh.camera_hint.connect(func(x: int, y: int, ticks: int) -> void: hints.append([x, y, ticks]))
	await H.frames(2)
	# tick 5: the opening message, the camera hint, the music, the timer
	_pump(r, 5)
	t.eq(mh.messages.plate_count(), 1, "the intro message is on screen")
	t.eq(mh.messages.plate_text(0), "Commander, the raid begins soon.")
	t.eq(mh.messages.plate_speaker(0), "Command")
	t.eq(audio.count_of(&"announce"), 1, "its announcer line went through the audio port")
	t.eq(audio.calls[audio.names().find("announce")][1], [&"base_under_attack"])
	t.eq(mh.announcer_played, 1)
	t.eq(audio.count_of(&"music_state"), 1, "the mission's music state too")
	t.eq(audio.calls[audio.names().find("music_state")][1], [&"combat"])
	t.eq(hints.size(), 1, "one camera hint reaches the screen")
	var far_a: int = mh.model.def.area_idx("a_far")
	var cell: int = (r["world"] as SimWorld).mission.area_center_cell(r["world"] as SimWorld, far_a)
	var mw: int = (r["world"] as SimWorld).map.w
	t.eq(hints[0][0], (cell % mw) * 1024 + 512, "it points at the centre of the area (x)")
	t.eq(hints[0][1], (cell / mw) * 1024 + 512, "...(y)")
	t.eq(mh.timers.chip_count(), 1, "the labelled timer is shown, the unlabelled one is not")
	t.eq(mh.timers.chip_label(0), "REINFORCEMENTS")
	t.check(mh.timers.chip_text(0) in ["0:20", "0:19"], "counting down: %s" % mh.timers.chip_text(0))
	t.eq(mh.objectives.row_count(), 2, "two objectives at the start (the optional one is hidden)")
	t.eq(hud.ribbons().count(), 0, "no ribbon announces the initial objectives")
	# tick 35: the optional objective is revealed and a second message
	_pump(r, 30)
	t.eq(mh.objectives.row_count(), 3, "the revealed objective is listed")
	t.eq(mh.messages.plate_count(), 2)
	t.check(hud.ribbons().has_ribbon(&"mission_obj_1"), "a ribbon says NEW OPTIONAL OBJECTIVE")
	t.eq(hud.ribbons().get_ribbon(&"mission_obj_1").title, "NEW OPTIONAL OBJECTIVE")
	t.check(audio.count_of(&"ui") >= 1, "with a cue")
	# tick 65: objective 1 completed
	_pump(r, 30)
	t.eq(mh.objectives.row_state(0), UiMissionModel.S_COMPLETED, "the objective is checked off")
	t.check(mh.objectives.is_flashing(0), "and flashes")
	t.check(hud.ribbons().has_ribbon(&"mission_obj_0"))
	t.eq(hud.ribbons().get_ribbon(&"mission_obj_0").title, "OBJECTIVE COMPLETE")
	# tick 85: the optional one failed
	_pump(r, 20)
	t.eq(mh.objectives.row_state(2), UiMissionModel.S_FAILED)
	t.eq(hud.ribbons().get_ribbon(&"mission_obj_1").title, "OBJECTIVE FAILED")
	# tick 105: the mission is won
	_pump(r, 20)
	t.eq(mh.model.result, UiMissionModel.R_WIN, "the layer sees the result")
	t.eq((r["world"] as SimWorld).match_state, SimWorld.MATCH_ENDED)
	# stale records are not announced (a replay seek / a long pause replays a backlog)
	var plates: int = mh.messages.plate_count()
	var old: PackedInt32Array = PackedInt32Array([UiEv.MISSION_MESSAGE, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	mh.on_events(old)
	t.eq(mh.messages.plate_count(), plates, "a message older than five seconds is ignored")
	h.vp.queue_free()
	await H.frames(2)
	_restore()


func test_hotkey_toggle_and_collapsed_peek_on_a_real_match(t: TestCtx) -> void:
	var d: GameData = _install({"ut_hud": Kit.scripted("ut_hud", "win")})
	var h: H.Rig = await H.make()
	var r: Dictionary = _rig(h, d, "ut_hud")
	var mh: UiMissionHud = r["mh"] as UiMissionHud
	await H.frames(1)
	_pump(r, 5)
	mh.toggle_objectives()
	t.check(mh.objectives.collapsed, "the hotkey collapses the panel")
	_pump(r, 30)  # the optional objective appears while collapsed
	t.check(mh.objectives.peeking(), "a new objective peeks the list open")
	mh.toggle_objectives()
	t.check(not mh.objectives.collapsed)
	t.eq(UiKeymap.instance().label(&"toggle_objectives") != "", true, "the action is bound by default")
	t.eq(mh.objectives.hotkey_text, UiKeymap.instance().label(&"toggle_objectives"), "and its key is shown in the header")
	h.vp.queue_free()
	await H.frames(2)
	_restore()


func test_observer_mode_has_no_camera_hints(t: TestCtx) -> void:
	var d: GameData = _install({"ut_hud": Kit.scripted("ut_hud", "win")})
	var h: H.Rig = await H.make()
	var w: SimWorld = MK.world(d, "ut_hud", {"events": true})
	var sim: UiSimPortWorld = UiSimPortWorld.new(w, 0)
	var hud: UiHud = UiHud.new()
	h.root.add_child(hud)
	UiLayerRoot.fill(hud)
	hud.setup(UiSkinSet.shared().skin_for("napc"), d, sim.roster_of(0), UiHud.MODE_OBSERVER)
	var mh: UiMissionHud = UiMissionHud.new()
	mh.setup(hud, sim, UiAudioPortRecorder.new(), AppMission.def_of(d, "ut_hud"), true)
	var hints: Array = []
	mh.camera_hint.connect(func(_x: int, _y: int, _t: int) -> void: hints.append(1))
	for _i: int in 6:
		w.step()
	mh.on_events(sim.take_events())
	mh.on_frame(0.2)
	t.eq(hints.size(), 0, "an observer's camera is their own")
	t.eq(mh.messages.plate_count(), 1, "but the captions still show")
	t.eq(mh.objectives.row_count(), 2, "and so do the objectives")
	h.vp.queue_free()
	await H.frames(2)
	_restore()


# ---------------------------------------------------------------- the game screen

func _drive_until(cond: Callable, max_ms: int = 30000) -> void:
	var t0: int = Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < max_ms:
		await H.frames(1)


func test_game_screen_with_a_mission_shows_the_layer_and_ends_with_the_result(t: TestCtx) -> void:
	t.set_timeout(90.0)
	_install({"ut_hud": Kit.scripted("ut_hud", "win")})
	UiMotion.reduce_motion = true
	var ctx: AppMatchContext = AppMission.start("ut_hud", 1, {"with_view": false, "bind": false, "discard_events": false})
	if not t.not_null(ctx, "the mission starts"):
		_restore()
		return
	var guard: int = 0
	while ctx.sim == null and guard < 4000:
		ctx.frame()
		OS.delay_msec(2)
		guard += 1
	var h: H.Rig = await H.make()
	var game: UiScreenGame = UiScreenGame.new()
	h.root.add_child(game)
	UiLayerRoot.fill(game)
	game.enter({"ctx": ctx})
	var nav: Array = []
	game.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	await H.frames(2)
	t.not_null(game.mission_hud, "the game screen builds the mission layer")
	t.eq(ctx.sim.mission_id(), "ut_hud", "the sim port knows the mission")
	await _drive_until(func() -> bool: return ctx.tick() >= 40)
	t.eq(game.mission_hud.objectives.row_count(), 3, "live objectives on the real screen")
	game._on_action(&"toggle_objectives")
	t.check(game.mission_hud.objectives.collapsed, "the action collapses the panel")
	game._on_action(&"toggle_objectives")
	t.check(not game.mission_hud.objectives.collapsed)
	game._become_observer(0)  # a defeated / surrendered player keeps watching: the HUD is rebuilt, and so is the mission layer
	await H.frames(2)
	if t.not_null(game.mission_hud, "the mission layer survives the rebuild into the observer HUD"):
		t.check(game.mission_hud.observer and game.mission_hud.is_inside_tree(), "in observer mode")
		t.eq(game.mission_hud.objectives.row_count(), 3, "with the same objectives")
	game.leave_match()
	t.eq(nav[0][0], &"campaign", "leaving a mission goes back to the campaign")
	nav.clear()
	game.exit()
	game.queue_free()
	h.vp.queue_free()
	await H.frames(2)
	ctx.dispose()
	# a mission that runs to its end: the banner, then the result screen with the model
	var ctx2: AppMatchContext = AppMission.start("ut_hud", 2, {"with_view": false, "bind": false, "discard_events": false, "unpaced": true})
	var g2: int = 0
	while ctx2.sim == null and g2 < 4000:
		ctx2.frame()
		OS.delay_msec(2)
		g2 += 1
	var h2: H.Rig = await H.make()
	var game2: UiScreenGame = UiScreenGame.new()
	h2.root.add_child(game2)
	UiLayerRoot.fill(game2)
	game2.enter({"ctx": ctx2})
	var nav2: Array = []
	game2.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav2.append([target, p]))
	await _drive_until(func() -> bool: return not nav2.is_empty(), 20000)
	if t.eq(nav2.size(), 1, "the end of the mission navigates once"):
		t.eq(nav2[0][0], &"end")
		var model: Dictionary = (nav2[0][1] as Dictionary).get("mission", {}) as Dictionary
		t.check(not model.is_empty(), "with the mission result model")
		t.check(bool(model.get("won", false)), "won")
		t.eq(model.get("difficulty_name"), "Hard")
		t.eq(AppFlow.screen_id_of(AppFlow.Mode.END_SCREEN, nav2[0][1] as Dictionary), &"mission_result", "which the flow shows as the mission result screen")
	game2.exit()
	game2.queue_free()
	h2.vp.queue_free()
	await H.frames(2)
	ctx2.dispose()
	UiMotion.reduce_motion = false
	_restore()


# ---------------------------------------------------------------- replay

func test_a_recorded_mission_replays_with_its_objectives(t: TestCtx) -> void:
	t.set_timeout(180.0)
	_install({"ut_hud": Kit.scripted("ut_hud", "win")})
	var ctx: AppMatchContext = AppMission.start("ut_hud", 1, {"with_view": false, "bind": false, "unpaced": true})
	var guard: int = 0
	while ctx.session.phase != NetSession.Phase.ENDED and guard < 40000:
		ctx.frame()
		OS.delay_msec(1)
		guard += 1
	t.eq(ctx.session.phase, NetSession.Phase.ENDED)
	var dir: String = U.sandbox("mis_replay")
	var path: String = AppReplay.save_session(ctx.session, "mission run", dir)
	if not t.check(path != "" and FileAccess.file_exists(path), "the recording is saved: %s" % AppReplay.last_error):
		ctx.dispose()
		U.cleanup(dir)
		_restore()
		return
	var data: NetReplayData = NetReplayData.load_file(path)
	t.eq(str(data.config.get("mission", "")), "ut_hud", "the replay records the mission id")
	ctx.dispose()
	AppState.match_ctx = null
	var rctx: AppMatchContext = AppReplay.start(path, {"with_view": false, "bind": false, "local_versions": {}})
	if not t.not_null(rctx, "the replay starts: %s" % AppReplay.last_error):
		U.cleanup(dir)
		_restore()
		return
	var t0: int = Time.get_ticks_msec()
	while not (rctx.replay.is_ready or rctx.replay.is_failed) and Time.get_ticks_msec() - t0 < 60000:
		rctx.frame()
		OS.delay_msec(1)
	t.check(rctx.replay.is_ready, "the replay is ready")
	t.eq(rctx.mission_id(), "ut_hud", "the replay context knows the mission")
	t.eq(rctx.sim.mission_id(), "ut_hud", "and so does its sim port")
	var h: H.Rig = await H.make()
	var game: UiScreenGame = UiScreenGame.new()
	h.root.add_child(game)
	UiLayerRoot.fill(game)
	game.enter({"ctx": rctx})
	await H.frames(2)
	if t.not_null(game.mission_hud, "the replay's observer HUD has the mission layer"):
		t.check(game.mission_hud.observer, "in observer mode")
		rctx.replay.set_speed(NetReplayPlayer.MAX)
		rctx.replay.set_paused(true)  # pause first: at MAX speed playback would overshoot the target before the pause below lands
		rctx.replay.seek(70)
		var s0: int = Time.get_ticks_msec()
		while rctx.replay.is_seeking() and Time.get_ticks_msec() - s0 < 60000:
			rctx.frame()
			await H.frames(1)
		rctx.replay.set_paused(true)
		await H.frames(8)
		game.mission_hud.sync_now()
		t.eq(rctx.tick(), 70, "seeked to tick 70")
		t.eq(game.mission_hud.objectives.row_count(), 3, "the objective list of that moment")
		t.eq(game.mission_hud.objectives.row_state(0), UiMissionModel.S_COMPLETED, "objective 1 was completed at tick 60")
		t.eq(game.mission_hud.objectives.row_state(2), UiMissionModel.S_ACTIVE, "the optional one is still open")
	game.exit()
	game.queue_free()
	h.vp.queue_free()
	await H.frames(2)
	rctx.dispose()
	AppState.match_ctx = null
	U.cleanup(dir)
	_restore()
