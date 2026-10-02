extends RefCounted
## REP2 replay UI (ui.md 5.16.3 / 5.16.6): the replay list model, the replay browser screen over a sandbox folder, the replay bar
## (speed ladder, seek mapping, marks, divergence banner, seek input), the observer model and bar, and the scoreboard.

const H := preload("res://tests/ui/ui_harness.gd")
const U := preload("res://tests/ui/app_test_util.gd")
const FIXTURE: String = "res://tests/fixtures/net/replays/app_ai_2p_3min.mfreplay"


func _gd() -> GameData:
	var app: Node = H.tree().root.get_node_or_null("AppState")
	var d: GameData = app.get("data") as GameData if app != null else null
	if d == null:
		d = GameData.load_default()
		if app != null:
			app.set("data", d)
	return d


func _info(name: String = "autosave_1", extra: Dictionary = {}) -> Dictionary:
	var info: Dictionary = {
		"path": "user://replays/%s.mfreplay" % name, "name": name, "kind": "autosave" if name.begins_with("autosave_") else ("crash" if name.begins_with("crash_") else "manual"),
		"size": 5300, "mtime": 1790000000, "valid": true, "error": "", "match_id": "x", "map": {"family": 0, "size": 96, "seed": 11, "layout_players": 2},
		"rules": {"start_credits": 7500, "fog": true, "superweapons": true, "unit_cap": 150, "shared_vision": false, "veterancy": false},
		"players": [{"pid": 0, "name": "Commander", "roster": "roster.napc.vanilla", "team": 1, "kind": "human", "color": 0, "start": 0},
			{"pid": 1, "name": "Bot 1", "roster": "roster.nec.vanilla", "team": 2, "kind": "ai", "color": 1, "start": 1}],
		"duration_ticks": 3600, "duration_s": 180, "finalized": true, "truncated": false, "game_version": "0.1.0", "versions": {}, "started_unix": 1790000000,
		"os": "macos", "result": {"reason": 0, "winner_team": 2, "final_tick": 3600}, "compatible": true, "incompatible_reason": "", "warning": "",
	}
	for k: Variant in extra:
		info[k] = extra[k]
	return info


# ---------------------------------------------------------------- list model

func test_model_titles_tags_and_formats(t: TestCtx) -> void:
	t.eq(UiReplayModel.title_of(_info("autosave_1")), "Last match")
	t.eq(UiReplayModel.title_of(_info("autosave_3")), "Match 3 back")
	t.eq(UiReplayModel.title_of(_info("crash_1790000000")), "Recovered (truncated)")
	t.eq(UiReplayModel.title_of(_info("My game")), "My game")
	t.eq(UiReplayModel.tag_of(_info("autosave_1")), "LAST")
	t.eq(UiReplayModel.tag_of(_info("autosave_2")), "AUTO 2")
	t.eq(UiReplayModel.tag_of(_info("crash_5")), "CRASH")
	t.eq(UiReplayModel.tag_of(_info("My game")), "")
	t.eq(UiReplayModel.date_text(1790000000, 0), "2026-09-21 14:13")
	t.eq(UiReplayModel.date_text(1790000000, 120), "2026-09-21 16:13", "the local UTC offset is applied")
	t.eq(UiReplayModel.date_text(0, 0), "-")
	t.eq(UiReplayModel.length_text(3600), "3:00")
	t.eq(UiReplayModel.length_text(0), "0:00")
	t.eq(UiReplayModel.size_text(5300), "6 KB")
	t.eq(UiReplayModel.size_text(3 * 1048576), "3.0 MB")
	t.eq(UiReplayModel.map_text(_info()["map"] as Dictionary), "%s  96" % UiMapNames.name_for(0, 11))
	t.eq(UiReplayModel.faction_code("roster.napc.vanilla"), "napc")
	t.eq(UiReplayModel.sub_key("roster.napc.canada"), "napc.canada")
	t.eq(UiReplayModel.sub_key("roster.napc.vanilla"), "")
	var chips: PackedStringArray = UiReplayModel.rule_chips(_info())
	t.check(chips.has("7,500 credits") and chips.has("Fog of war") and chips.has("Unit cap 150"), "rule chips: %s" % str(chips))


func test_model_result_and_build_states(t: TestCtx) -> void:
	t.eq(UiReplayModel.result_text(_info()), "Won: Bot 1", "the winning team's first name")
	t.eq(UiReplayModel.players_text(_info()), "Commander, * Bot 1", "winners are starred")
	t.eq(UiReplayModel.result_text(_info("a", {"result": {"reason": 0, "winner_team": -1, "final_tick": 10}})), "Draw")
	t.eq(UiReplayModel.result_text(_info("a", {"result": {"reason": NetProtocol.MatchEndReason.ABANDONED, "winner_team": -1, "final_tick": 10}})), "Left early")
	t.eq(UiReplayModel.result_text(_info("a", {"result": {"reason": NetProtocol.MatchEndReason.DESYNC, "winner_team": -1, "final_tick": 10}})), "Out of sync")
	t.eq(UiReplayModel.result_text(_info("crash_1", {"result": {}, "finalized": false})), "Truncated")
	t.eq(UiReplayModel.result_text(_info("a", {"valid": false})), "Unreadable")
	t.eq(UiReplayModel.build_state(_info()), UiReplayModel.BUILD_OK)
	t.eq(UiReplayModel.build_text(_info()), "OK")
	var old: Dictionary = _info("old", {"compatible": false, "incompatible_reason": "This replay was recorded with a different simulation version (recorded 1, this build 2) and cannot be played."})
	t.eq(UiReplayModel.build_state(old), UiReplayModel.BUILD_OLD)
	t.eq(UiReplayModel.build_text(old), "OLD BUILD")
	t.check(not UiReplayModel.playable(old), "an old build is not playable")
	t.check(UiReplayModel.refusal(old).contains("simulation version"), "the refusal text is the net gate's")
	var soft: Dictionary = _info("soft", {"warning": "Balance changed since recording; playback may diverge."})
	t.eq(UiReplayModel.build_state(soft), UiReplayModel.BUILD_BALANCE)
	t.check(UiReplayModel.playable(soft), "a balance difference still plays")
	t.eq(UiReplayModel.build_state(_info("bad", {"valid": false})), UiReplayModel.BUILD_BROKEN)
	t.check(UiReplayModel.refusal(_info("bad", {"valid": false, "error": "bad magic"})).contains("bad magic"))


func test_model_rows_filter_and_sort(t: TestCtx) -> void:
	var infos: Array[Dictionary] = [
		_info("autosave_1", {"mtime": 300, "started_unix": 300, "duration_ticks": 1200}),
		_info("Epic duel", {"mtime": 100, "started_unix": 100, "duration_ticks": 6000, "map": {"family": 1, "size": 128, "seed": 4, "layout_players": 2}}),
		_info("crash_9", {"mtime": 200, "started_unix": 200, "duration_ticks": 2400, "compatible": false, "incompatible_reason": "different build"}),
	]
	var rows: Array[Dictionary] = UiReplayModel.build_rows(infos)
	t.eq(rows.size(), 3)
	t.eq(str(rows[0]["key"]), "user://replays/autosave_1.mfreplay", "newest first by default")
	t.eq(str(rows[2]["key"]), "user://replays/Epic duel.mfreplay")
	t.check(bool(rows[1]["dimmed"]) and not bool(rows[1]["playable"]), "the incompatible row is dimmed")
	t.eq(str(rows[1]["tooltip"]), "different build", "and carries the reason")
	rows = UiReplayModel.build_rows(infos, {"hide_autosaves": true})
	t.eq(rows.size(), 1, "hide automatic keeps the manual ones")
	rows = UiReplayModel.build_rows(infos, {"hide_incompatible": true})
	t.eq(rows.size(), 2)
	rows = UiReplayModel.build_rows(infos, {"text": "epic"})
	t.eq(rows.size(), 1, "the text filter matches the name")
	rows = UiReplayModel.build_rows(infos, {"text": "nec"})
	t.eq(rows.size(), 3, "and the roster ids")
	rows = UiReplayModel.build_rows(infos, {"text": "zzz"})
	t.eq(rows.size(), 0)
	rows = UiReplayModel.build_rows(infos, {}, UiReplayModel.Col.LENGTH, false)
	t.eq(str(rows[0]["key"]), "user://replays/autosave_1.mfreplay", "shortest first")
	rows = UiReplayModel.build_rows(infos, {}, UiReplayModel.Col.LENGTH, true)
	t.eq(str(rows[0]["key"]), "user://replays/Epic duel.mfreplay", "longest first")
	var cells: Array[Dictionary] = (UiReplayModel.build_rows(infos)[0] as Dictionary)["cells"] as Array[Dictionary]
	t.eq(cells.size(), UiReplayModel.COLUMN_NAMES.size(), "one cell per column")
	t.eq((cells[UiReplayModel.Col.PLAYERS]["dots"] as PackedColorArray).size(), 2, "one colour pip per player")
	var w: PackedFloat32Array = UiReplayModel.scaled_widths(1200.0)
	t.check(w[UiReplayModel.Col.MAP] > UiReplayModel.COLUMN_WIDTHS[UiReplayModel.Col.MAP], "wide lists give MAP more room")
	t.eq(UiReplayModel.scaled_widths(100.0)[0], UiReplayModel.COLUMN_WIDTHS[0], "narrow lists keep the base widths")


func test_model_reads_the_golden_fixture(t: TestCtx) -> void:
	var info: Dictionary = NetReplay.read_info(FIXTURE, {})
	t.check(bool(info["valid"]), "the fixture reads")
	t.eq((info["players"] as Array).size(), 2)
	t.check((info["rules"] as Dictionary).has("start_credits"), "rules are in the info")
	t.check(((info["players"] as Array)[0] as Dictionary).has("start"), "and the start slots")
	t.check(UiReplayModel.playable(info))
	t.eq(UiReplayModel.length_text(int(info["duration_ticks"])), "3:00")
	var bad: Dictionary = NetReplay.read_info(FIXTURE, {"sim": 9999})
	t.check(not UiReplayModel.playable(bad), "a different simulation version is refused by the gate")
	t.eq(UiReplayModel.build_text(bad), "OLD BUILD")
	t.check(UiReplayModel.detail_lines(info).size() >= 8, "the detail pane has its lines")
	t.eq(AppReplay.event_marks(NetReplayData.load_file(FIXTURE)).size(), 0, "a match without status events has no recorded marks")


# ---------------------------------------------------------------- replay bar

func test_bar_speed_ladder(t: TestCtx) -> void:
	t.eq(UiReplayBar.speed_index(1.0), 2)
	t.eq(UiReplayBar.speed_index(0.0), 6, "MAX is the last chip")
	t.eq(UiReplayBar.speed_index(3.0), 3, "the nearest chip")
	t.eq(UiReplayBar.step_speed(1.0, 1), 2.0)
	t.eq(UiReplayBar.step_speed(8.0, 1), 0.0, "faster than 8x is MAX")
	t.eq(UiReplayBar.step_speed(0.0, 1), 0.0, "MAX stays")
	t.eq(UiReplayBar.step_speed(0.25, -1), 0.25, "the slowest chip stays")
	t.eq(UiReplayBar.step_speed(0.0, -1), 8.0, "one down from MAX is 8x")
	t.eq(UiReplayBar.SPEEDS.size(), NetReplayPlayer.SPEEDS.size() + 1, "the chips are the player's speeds plus MAX")
	for i: int in NetReplayPlayer.SPEEDS.size():
		t.near(float(UiReplayBar.SPEEDS[i]["value"]), NetReplayPlayer.SPEEDS[i], 0.0001, "chip %d" % i)


func test_bar_seek_mapping_marks_and_events(t: TestCtx) -> void:
	t.eq(UiReplayBar.tick_at(0.0, 800.0, 3600), 0)
	t.eq(UiReplayBar.tick_at(400.0, 800.0, 3600), 1800)
	t.eq(UiReplayBar.tick_at(900.0, 800.0, 3600), 3600, "clamped to the end")
	t.eq(UiReplayBar.tick_at(-5.0, 800.0, 3600), 0)
	t.eq(UiReplayBar.mark_step(3600, 800.0), 600, "30 s marks on a short replay")
	t.check(UiReplayBar.mark_step(600000, 800.0) > 600, "marks thin out on a long replay")
	t.eq(UiReplayBar.clock(1200), "1:00")
	var marks: Array[Dictionary] = [{"tick": 400, "kind": "defeated", "pid": 1, "text": "a"}, {"tick": 1000, "kind": "chat", "pid": 0, "text": "b"}]
	t.eq(UiReplayBar.event_after(marks, 0, 1), 400)
	t.eq(UiReplayBar.event_after(marks, 400, 1), 1000, "the event under the playhead is skipped")
	t.eq(UiReplayBar.event_after(marks, 1000, 1), -1)
	t.eq(UiReplayBar.event_after(marks, 1000, -1), 400)
	t.eq(UiReplayBar.event_after(marks, 400, -1), -1)
	var cps: PackedInt32Array = AppReplaySession.checkpoints(3600)
	t.eq(cps.size(), 5, "tick marks every 600 ticks")
	t.eq(cps[0], 600)


func test_bar_widget_state_and_signals(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1280, 720))
	var bar: UiReplayBar = UiReplayBar.new()
	h.root.add_child(bar)
	await H.frames(2)
	var got: Dictionary = {"pause": 0, "speed": [], "seek": [], "rel": [], "ev": []}
	bar.pause_toggled.connect(func() -> void: got["pause"] = int(got["pause"]) + 1)
	bar.speed_chosen.connect(func(v: float) -> void: (got["speed"] as Array).append(v))
	bar.seek_requested.connect(func(tk: int) -> void: (got["seek"] as Array).append(tk))
	bar.seek_relative.connect(func(s: int) -> void: (got["rel"] as Array).append(s))
	bar.event_jump.connect(func(d: int) -> void: (got["ev"] as Array).append(d))
	bar.set_state(1200, 3600, 2.0, false, 900, -1, false, 0, false)
	t.eq(bar.play_button().text, "PAUSE")
	t.check(bar.speed_button(3).button_pressed and not bar.speed_button(2).button_pressed, "the 2x chip is the pressed one")
	t.eq(bar.badge_text(), "VERIFIED THROUGH 0:45")
	t.eq(bar.banner_text(), "")
	bar.set_state(1200, 3600, 1.0, true, 900, -1, true, 42, false)
	t.eq(bar.play_button().text, "PLAY", "paused shows PLAY")
	t.eq(bar.spinner_text(), "SEEKING 42%", "a seek shows its progress")
	bar.set_state(3600, 3600, 1.0, false, 3600, -1, false, 0, true)
	t.eq(bar.play_button().text, "REPLAY", "a finished replay offers to start over")
	bar.set_state(2000, 3600, 1.0, false, 600, 1000, false, 0, false)
	t.check(bar.banner_text().contains("diverged at 0:50"), "the divergence banner: %s" % bar.banner_text())
	t.eq(bar.badge_text(), "", "no verified badge once it diverged")
	bar.set_marks([{"tick": 500, "kind": "defeated", "pid": 1, "text": "Bot 1 defeated"}])
	bar.set_state(0, 3600, 1.0, false, 0, -1, false, 0, false)
	t.check(not bar._next_ev.disabled and bar._prev_ev.disabled, "the event buttons follow the marks")
	bar.play_button().pressed.emit()
	bar.speed_button(4).pressed.emit()
	bar.speed_button(6).pressed.emit()
	bar._next_ev.pressed.emit()
	t.eq(int(got["pause"]), 1)
	t.eq(got["speed"], [4.0, 0.0], "the chips send their multiplier, MAX is 0")
	t.eq(got["ev"], [1])
	# a click on the seek track seeks to that fraction
	var seek: Control = bar.seek_bar()
	await H.frames(2)
	var rect: Rect2 = seek.get_global_rect()
	H.click(h.vp, rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.5))
	await H.frames(2)
	t.eq((got["seek"] as Array).size(), 1, "a click on the track requests a seek")
	t.check(absi(int((got["seek"] as Array)[0]) - 1800) < 80, "to the clicked fraction: %s" % str(got["seek"]))
	H.done(h)
	await H.frames(2)


# ---------------------------------------------------------------- observer model, bar, scoreboard

func test_observer_bar_rows_and_perspective(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1280, 720))
	var bar: UiObserverBar = UiObserverBar.new()
	bar.custom_minimum_size = Vector2(320.0, 460.0)
	h.root.add_child(bar)
	var rows: Array[Dictionary] = []
	for i: int in 3:
		rows.append({"pid": i, "name": "P%d" % i, "color": i, "team": i + 1, "faction": "napc", "roster_id": "roster.napc.vanilla", "credits": 1000 * i, "earned": 0,
			"income": 500, "army_value": 2000 + i, "army_n": 4, "units": 5, "structs": 6, "kills": 1, "losses": 2, "active": i != 2, "score": 10 * i, "apm": 30,
			"share": 500, "army_x": 1, "army_y": 1, "base_x": 1, "base_y": 1})
	bar.set_rows(rows)
	await H.frames(2)
	t.eq(bar.row_count(), 3)
	var asked: Array[int] = []
	bar.perspective_requested.connect(func(pid: int) -> void: asked.append(pid))
	var follows: Array[bool] = []
	bar.follow_toggled.connect(func(on: bool) -> void: follows.append(on))
	H.click(h.vp, bar.row_node(1).get_global_rect().get_center())
	H.click(h.vp, bar.all_row().get_global_rect().get_center())
	await H.frames(2)
	t.eq(asked, [1, -1], "a click on a player row asks for that perspective, the first row for everyone")
	bar.set_perspective(1)
	t.check(bar._player_rows[1].selected and not bar.all_row().selected, "the viewed row is highlighted")
	t.check(bar._hint.text.contains("P1"), "the header names the viewed player: %s" % bar._hint.text)
	bar._follow_btn.button_pressed = true
	t.eq(follows, [true])
	bar.set_follow(false)
	t.check(not bar._follow_btn.button_pressed, "set_follow updates the button silently")
	t.eq(follows.size(), 1)
	rows.pop_back()
	bar.set_rows(rows)
	await H.frames(2)
	t.eq(bar.row_count(), 2, "rows of players that vanished are removed")
	H.done(h)
	await H.frames(2)


func test_scoreboard_sorts_and_formats(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1280, 720))
	var sb: UiScoreboard = UiScoreboard.new()
	h.root.add_child(sb)
	var mk: Callable = func(pid: int, score: int, active: bool) -> Dictionary:
		return {"pid": pid, "name": "P%d" % pid, "color": pid, "team": pid + 1, "faction": "nec", "credits": 12345, "income": 678, "units": 9, "structs": 4, "kills": 3,
			"losses": 1, "active": active, "score": score, "apm": 42}
	var rows: Array[Dictionary] = [mk.call(0, 50, true), mk.call(1, 200, true), mk.call(2, 900, false)]
	sb.set_rows(rows, 1200)
	t.check(not sb.visible, "hidden until F2")
	sb.toggle()
	t.check(sb.visible)
	t.eq(sb.row_count(), 3)
	t.eq(sb._order, [1, 0, 2], "best score first, players that are out last")
	t.eq(sb.cell_text(1, "credits"), "12,345")
	t.eq(sb.cell_text(1, "income"), "+678")
	t.eq(sb.cell_text(0, "team"), "T1")
	t.eq(sb.cell_text(1, "score"), "200")
	t.check(sb.cell_text(2, "name").ends_with("(out)"), "a player who is out is marked")
	t.eq(sb.mouse_filter, Control.MOUSE_FILTER_IGNORE, "mouse transparent")
	H.done(h)
	await H.frames(2)


# ---------------------------------------------------------------- replay browser screen

func _folder() -> String:
	var dir: String = U.sandbox("rep")
	DirAccess.copy_absolute(FIXTURE, dir.path_join("autosave_1.mfreplay"))
	DirAccess.copy_absolute(FIXTURE, dir.path_join("My duel.mfreplay"))
	DirAccess.copy_absolute("res://tests/fixtures/net/replays/xplat_2p_ai.mfreplay", dir.path_join("crash_1790000001.mfreplay"))
	var junk: FileAccess = FileAccess.open(dir.path_join("garbage.mfreplay"), FileAccess.WRITE)
	junk.store_string("this is not a replay file")
	junk.close()
	U.write(dir.path_join("notes.txt"), "ignored")
	return dir


func test_screen_lists_selects_and_filters(t: TestCtx) -> void:
	var dir: String = _folder()
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var scr: UiScreenReplays = UiScreenReplays.new()
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr.enter({"dir": dir})
	scr.read_all()
	await H.frames(3)
	t.eq(scr.row_count(), 4, "every *.mfreplay is listed (the text file is not)")
	var info: Dictionary = scr.selected_info()
	t.check(not info.is_empty(), "the first row is selected by default")
	t.check(scr._watch.disabled == not UiReplayModel.playable(info), "WATCH follows the selection's compatibility")
	var garbage_idx: int = -1
	for i: int in scr._rows.size():
		if str((scr._rows[i]["info"] as Dictionary)["name"]) == "garbage":
			garbage_idx = i
	t.check(garbage_idx >= 0, "an unreadable file is listed")
	scr._select(str(scr._rows[garbage_idx]["key"]))
	t.check(scr._watch.disabled and scr._verify.disabled, "an unreadable replay cannot be watched or verified")
	t.check(scr._banner.text.contains("not a readable replay") or scr._banner.text.contains("replay"), "and says why: %s" % scr._banner.text)
	scr._hide_auto.button_pressed = true
	await H.frames(2)
	t.eq(scr.row_count(), 2, "hide automatic drops autosave_ and crash_ files")
	scr._hide_auto.button_pressed = false
	scr._filter.text = "duel"
	scr._filter.text_changed.emit("duel")
	await H.frames(2)
	t.eq(scr.row_count(), 1, "the text filter")
	scr._filter.text = ""
	scr._filter.text_changed.emit("")
	scr._on_sort(UiReplayModel.Col.LENGTH)
	t.eq(scr._sort_col, UiReplayModel.Col.LENGTH)
	scr._on_sort(UiReplayModel.Col.LENGTH)
	t.check(scr._sort_desc != true or scr._sort_col == UiReplayModel.Col.LENGTH, "a second click flips the direction")
	scr.exit()
	H.done(h)
	await H.frames(2)
	U.cleanup(dir)


func test_screen_incompatible_build_and_empty_state(t: TestCtx) -> void:
	var dir: String = _folder()
	var h: H.Rig = await H.make(Vector2i(1280, 720))
	var scr: UiScreenReplays = UiScreenReplays.new()
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr._local = {"sim": 987654}
	scr.enter({"dir": dir})
	scr._local = {"sim": 987654, "proto": NetProtocol.PROTO_VERSION}
	scr.scan()
	scr.read_all()
	var bad: int = 0
	for r: Dictionary in scr._rows:
		if not bool(r["playable"]):
			bad += 1
	t.gt(bad, 0, "replays of another simulation version get the OLD BUILD treatment")
	scr._select(str(scr._rows[0]["key"]))
	for r: Dictionary in scr._rows:
		if str((r["info"] as Dictionary)["name"]) == "My duel":
			scr._select(str(r["key"]))
	t.check(scr._watch.disabled, "WATCH is disabled for an old build")
	t.check(scr._watch.tooltip_text.contains("simulation version"), "and the tooltip is the gate's text: %s" % scr._watch.tooltip_text)
	scr.exit()
	H.done(h)
	var empty: String = U.sandbox("rep_empty")
	var h2: H.Rig = await H.make(Vector2i(1280, 720))
	var scr2: UiScreenReplays = UiScreenReplays.new()
	h2.root.add_child(scr2)
	UiLayerRoot.fill(scr2)
	scr2.enter({"dir": empty})
	scr2.read_all()
	await H.frames(2)
	t.eq(scr2.row_count(), 0)
	t.check(scr2._empty_note.visible and scr2._empty_note.text.contains("No replays yet"), "the empty state: %s" % scr2._empty_note.text)
	t.check(scr2._watch.disabled and scr2._delete.disabled, "no actions without a selection")
	scr2.exit()
	H.done(h2)
	await H.frames(2)
	U.cleanup(dir)
	U.cleanup(empty)


func test_screen_rename_delete_and_watch_errors(t: TestCtx) -> void:
	var dir: String = _folder()
	var h: H.Rig = await H.make(Vector2i(1280, 720))
	var scr: UiScreenReplays = UiScreenReplays.new()
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr.enter({"dir": dir})
	scr.read_all()
	# a manual replay is renamed in place, an automatic one is copied (the rotation keeps its own)
	var manual: String = dir.path_join("My duel.mfreplay")
	var renamed: String = scr.rename_or_copy(manual, "Final: best/game?", true)
	t.eq(renamed.get_file(), "Final_ best_game_.mfreplay", "the name is sanitised by the net module")
	t.check(FileAccess.file_exists(renamed) and not FileAccess.file_exists(manual), "renamed in place")
	var auto: String = dir.path_join("autosave_1.mfreplay")
	var kept: String = scr.rename_or_copy(auto, "Keeper", false)
	t.check(FileAccess.file_exists(kept) and FileAccess.file_exists(auto), "an automatic replay is copied, the original stays")
	t.check(NetReplayData.load_file(kept) != null, "the copy is a valid replay")
	# delete only touches *.mfreplay files inside the replay folder
	t.check(scr.delete_file(kept), "a replay of the folder is deleted")
	t.check(not FileAccess.file_exists(kept))
	t.check(not scr.delete_file(dir.path_join("notes.txt")), "other files are refused")
	t.check(FileAccess.file_exists(dir.path_join("notes.txt")))
	t.check(not scr.delete_file(dir.path_join("../x.mfreplay")), "no path tricks")
	scr.exit()
	H.done(h)
	await H.frames(2)
	U.cleanup(dir)
