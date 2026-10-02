extends RefCounted
## MIS2 menus: the campaign model (menu order, locked / unlocked / completed, best time, the unlock rule, next mission, map layout), the
## campaign screen and its map, the mission briefing (blocks, objectives preview, difficulty, START) and the mission result screen.

const H := preload("res://tests/ui/ui_harness.gd")
const Kit := preload("res://tests/ui/mission_ui_kit.gd")

var _saved_data: GameData = null
var _saved_campaign: AppCampaign = null


func _install(extra: Dictionary = {}) -> AppCampaign:
	_saved_data = AppState.data
	_saved_campaign = AppState.profile.campaign
	AppState.data = Kit.data(extra if not extra.is_empty() else Kit.campaign_set())
	AppState.profile.campaign = AppCampaign.new()
	UiSkinSet.shared().setup_from_json()
	return AppState.profile.campaign


func _restore() -> void:
	if AppState.match_ctx is AppMatchContext:
		(AppState.match_ctx as AppMatchContext).dispose()
	AppState.match_ctx = null
	AppState.data = _saved_data
	AppState.profile.campaign = _saved_campaign
	AppMission.release_statics()


func _mount(h: H.Rig, screen: UiScreen, params: Dictionary = {}) -> void:
	h.root.add_child(screen)
	UiLayerRoot.fill(screen)
	screen.enter(params)


func _buttons(n: Node, out: Array[Button]) -> void:
	for c: Node in n.get_children():
		if c is Button:
			out.append(c as Button)
		_buttons(c, out)


func _button(n: Node, text: String) -> Button:
	var all: Array[Button] = []
	_buttons(n, all)
	for b: Button in all:
		if b.text == text or b.text.begins_with(text):
			return b
	return null


# ---------------------------------------------------------------- model

func test_menu_order_states_and_the_unlock_rule(t: TestCtx) -> void:
	var camp: AppCampaign = _install()
	var m: UiCampaignModel = UiCampaignModel.build(AppState.data, camp)
	t.eq(m.ids(), PackedStringArray(["ut_tut", "ut_op_a", "ut_op_b", "ut_demo"]), "menu order: tutorial, operations by order, then the other groups")
	t.eq(m.entry("ut_tut").state, UiCampaignModel.State.UNLOCKED, "the tutorial is open")
	t.eq(m.entry("ut_op_a").state, UiCampaignModel.State.LOCKED, "operations wait for the tutorial")
	t.eq(m.entry("ut_op_b").state, UiCampaignModel.State.LOCKED)
	t.eq(m.entry("ut_demo").state, UiCampaignModel.State.UNLOCKED, "other groups are always open")
	t.eq(m.recommended(), "ut_tut", "the tutorial is what to play first")
	t.eq(m.lock_reason("ut_op_a"), "Complete Field Training first.")
	t.eq(m.lock_reason("ut_tut"), "")
	camp.record_result("ut_tut", true, 4000, 1)
	m.refresh()
	t.eq(m.entry("ut_tut").state, UiCampaignModel.State.COMPLETED)
	t.eq(m.entry("ut_tut").best_ticks, 4000)
	t.eq(m.entry("ut_tut").best_difficulty, 1)
	t.eq(m.entry("ut_op_a").state, UiCampaignModel.State.UNLOCKED, "the tutorial opens the operations")
	t.eq(m.entry("ut_op_b").state, UiCampaignModel.State.UNLOCKED)
	t.eq(m.recommended(), "ut_op_a", "then the first open operation")
	t.eq(m.next_after("ut_tut"), "ut_op_a", "next mission after the tutorial")
	t.eq(m.next_after("ut_op_a"), "ut_op_b")
	t.eq(m.next_after("ut_op_b"), "", "the demo is never offered as the next mission")
	t.eq(m.completed_count(), 1)
	var fresh: AppCampaign = AppCampaign.new()
	fresh.record_result("ut_op_b", true, 100, 0)  # an operation won without the tutorial: nothing stays locked behind it
	t.eq(UiCampaignModel.build(AppState.data, fresh).entry("ut_op_a").state, UiCampaignModel.State.UNLOCKED, "a player who skipped the training is not locked out")
	var all: AppCampaign = AppCampaign.new()
	all.unlock_all = true
	t.eq(UiCampaignModel.build(AppState.data, all).entry("ut_op_b").state, UiCampaignModel.State.UNLOCKED, "unlock_all (debug) opens everything")
	_restore()


func test_entries_carry_faction_teaser_objectives_and_map_positions(t: TestCtx) -> void:
	_install()
	var m: UiCampaignModel = UiCampaignModel.build(AppState.data, AppState.profile.campaign)
	t.eq(m.entry("ut_op_a").faction_code, "nec", "the faction of the human slot")
	t.eq(m.entry("ut_op_b").faction_code, "olm")
	t.eq(m.entry("ut_tut").faction_code, "napc")
	t.eq(m.entry("ut_op_a").teaser, "Hostiles gather at the ridge.", "the first sentence of the briefing")
	t.eq(m.entry("ut_op_a").objectives_primary, 1, "the hidden objective is not counted")
	t.eq(m.entry("ut_op_a").objectives_secondary, 1)
	t.eq(m.entry("ut_op_a").title, "Operation Alpha")
	t.eq(m.entry("ut_tut").pos, Vector2(0.5, UiCampaignModel.HUB_Y), "the tutorial is the hub")
	t.check(m.entry("ut_op_a").pos != m.entry("ut_op_b").pos, "operations sit on the ring")
	t.check(m.entry("ut_demo").pos.y > 0.9, "other groups line up along the lower edge")
	for e: UiCampaignModel.Entry in m.entries:
		t.check(e.pos.x >= 0.0 and e.pos.x <= 1.0 and e.pos.y >= 0.0 and e.pos.y <= 1.0, "%s is inside the map" % e.id)
	var long_def: DefMission = DefMission.new()
	long_def.ui_briefing = [{"text": "A very long sentence without any stop that keeps going " + "and going ".repeat(30), "heading": ""}]
	t.check(UiCampaignModel.teaser_of(long_def).length() <= UiCampaignModel.TEASER_CHARS, "a long first sentence is cut")
	t.check(UiCampaignModel.teaser_of(long_def).ends_with("..."))
	t.eq(UiCampaignModel.teaser_of(DefMission.new()), "", "no briefing, no teaser")
	_restore()


func test_shipped_campaign_lists_the_tutorial_first(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	if not t.not_null(d, "data loads"):
		return
	var m: UiCampaignModel = UiCampaignModel.build(d, AppCampaign.new())
	t.gt(m.count(), 0, "the shipped missions are listed")
	if m.count() > 0 and d.ext.has("missions"):
		var first: UiCampaignModel.Entry = m.entries[0]
		var has_tut: bool = false
		for e: UiCampaignModel.Entry in m.entries:
			has_tut = has_tut or e.group == "tutorial"
		if has_tut:
			t.eq(first.group, "tutorial", "the tutorial comes first")
		for e: UiCampaignModel.Entry in m.entries:
			t.check(e.title != "" and e.faction_code != "", "%s has a title and a faction" % e.id)


# ---------------------------------------------------------------- campaign screen

func test_campaign_screen_selects_and_opens_the_briefing(t: TestCtx) -> void:
	var camp: AppCampaign = _install()
	var h: H.Rig = await H.make()
	var screen: UiScreenCampaign = UiScreenCampaign.new()
	_mount(h, screen)
	await H.frames(3)
	t.eq(screen.map.card_count(), 4, "one card per mission")
	t.eq(screen.selected_id, "ut_tut", "the recommended mission is selected first")
	t.eq(screen.default_focus(), screen.map.card_for("ut_tut"), "and takes the keyboard focus")
	var nav: Array = []
	var backs: Array = []
	screen.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	screen.back_requested.connect(func() -> void: backs.append(1))
	t.check(not _button(screen, "BRIEFING").disabled, "the open mission can be briefed")
	_button(screen, "BRIEFING").pressed.emit()
	t.eq(nav[0][0], &"mission_briefing")
	t.eq(nav[0][1]["mission"], "ut_tut")
	nav.clear()
	screen.map.select("ut_op_a")
	await H.frames(1)
	t.eq(screen.selected_id, "ut_op_a", "selecting a card updates the detail panel")
	t.check(_button(screen, "BRIEFING").disabled, "a locked mission cannot be briefed")
	screen.map.mission_activated.emit("ut_op_a")
	t.eq(nav.size(), 0, "activating a locked mission does nothing")
	camp.record_result("ut_tut", true, 4000, 1)
	screen.model.refresh()
	screen.map.refresh()
	screen._update_detail()
	t.check(not _button(screen, "BRIEFING").disabled, "completing the tutorial unlocks it")
	screen.map.mission_activated.emit("ut_op_a")
	t.eq(nav[0][1]["mission"], "ut_op_a", "a double click / Enter opens the briefing")
	t.check(screen.handle_escape(), "Escape is handled")
	t.eq(backs.size(), 1, "and goes back to the main menu")
	screen.exit()
	h.vp.queue_free()
	await H.frames(2)
	_restore()


func test_campaign_screen_disposes_a_finished_match_and_reports_a_start_error(t: TestCtx) -> void:
	_install()
	var ctx: AppMatchContext = AppMatchContext.new()
	AppState.match_ctx = ctx
	var h: H.Rig = await H.make()
	var screen: UiScreenCampaign = UiScreenCampaign.new()
	_mount(h, screen, {"select": "ut_demo"})
	await H.frames(2)
	t.check(ctx.disposed and AppState.match_ctx == null, "coming back from a mission frees its context")
	t.eq(screen.selected_id, "ut_demo", "the screen can preselect a mission")
	screen.exit()
	h.vp.queue_free()
	await H.frames(2)
	_restore()


# ---------------------------------------------------------------- briefing

func test_briefing_shows_blocks_objectives_and_the_difficulty_selector(t: TestCtx) -> void:
	var camp: AppCampaign = _install()
	camp.note_start("ut_op_a", 3)
	var h: H.Rig = await H.make()
	var screen: UiScreenMissionBriefing = UiScreenMissionBriefing.new()
	_mount(h, screen, {"mission": "ut_op_a"})
	await H.frames(3)
	t.eq(screen.def.ui_title, "Operation Alpha")
	t.eq(screen.difficulty, 3, "the difficulty used last time is preselected")
	t.not_null(_button(screen, "FIELD MANUAL  //  NEC"), "a block with a lore id offers a Field Manual link")
	var labels: PackedStringArray = PackedStringArray()
	_collect_labels(screen, labels)
	t.check(labels.has("Destroy the camp") and labels.has("Lose nobody"), "primary and optional objectives are previewed")
	t.check(not labels.has("Revealed later"), "an objective that starts hidden stays hidden")
	t.check(labels.has("1 further objective is revealed during the mission."), "and the preview says there is one more")
	t.check(labels.has("Hostiles gather at the ridge. Hold the line, then strike back. More text follows here."), "the briefing text is there")
	t.check(labels.has("SITUATION"), "with its heading")
	t.eq(screen._diff_buttons.size(), 4)
	t.check(screen._diff_buttons[3].button_pressed and not screen._diff_buttons[1].button_pressed, "Brutal is selected")
	screen._diff_buttons[0].pressed.emit()
	t.eq(screen.difficulty, 0, "choosing Easy")
	t.eq(camp.last_difficulty("ut_op_a"), 0, "is remembered for the next visit")
	t.eq(screen._diff_blurb.text, AppMission.DIFFICULTY_BLURBS[0])
	t.check(screen.default_focus() == screen._start, "START has the focus")
	var nav: Array = []
	screen.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	t.check(screen.handle_escape(), "Escape is handled")
	t.eq(nav[0], [&"campaign", {"select": "ut_op_a"}], "Escape returns to the campaign with this mission selected")
	nav.clear()
	_button(screen, "FIELD MANUAL").pressed.emit()
	t.eq(nav[0][0], &"field_manual")
	t.eq(nav[0][1]["roster_id"], "roster.nec.vanilla", "the Field Manual opens on the mission's roster")
	t.eq(nav[0][1]["focus_id"], "faction.nec")
	screen.exit()
	h.vp.queue_free()
	await H.frames(2)
	_restore()


func _collect_labels(n: Node, out: PackedStringArray) -> void:
	for c: Node in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_collect_labels(c, out)


func test_briefing_start_launches_the_mission_with_the_chosen_difficulty(t: TestCtx) -> void:
	t.set_timeout(60.0)
	_install()
	var h: H.Rig = await H.make()
	var screen: UiScreenMissionBriefing = UiScreenMissionBriefing.new()
	_mount(h, screen, {"mission": "ut_op_a", "difficulty": 2})
	await H.frames(2)
	var nav: Array = []
	screen.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	_button(screen, "START MISSION").pressed.emit()
	t.eq(nav.size(), 1, "START navigates once")
	t.eq(nav[0][0], &"loading")
	t.eq(nav[0][1]["mission"], "ut_op_a")
	t.eq(nav[0][1]["title"], "Operation Alpha")
	var ctx: AppMatchContext = AppState.match_ctx as AppMatchContext
	if t.not_null(ctx, "the match context exists (the loading screen reads it)"):
		t.eq(ctx.mission_id(), "ut_op_a")
		t.eq(ctx.mission_difficulty, 2)
		var ai_level: int = -1
		for pv: Variant in ctx.config["players"] as Array:
			if (pv as Dictionary).has("ai"):
				ai_level = int(((pv as Dictionary)["ai"] as Dictionary)["level"])
		t.eq(ai_level, 3, "authored level 2 + Hard (+1)")
	screen.exit()
	h.vp.queue_free()
	await H.frames(2)
	_restore()


func test_briefing_of_an_unknown_mission_offers_the_way_back(t: TestCtx) -> void:
	_install()
	var h: H.Rig = await H.make()
	var screen: UiScreenMissionBriefing = UiScreenMissionBriefing.new()
	_mount(h, screen, {"mission": "gone"})
	await H.frames(2)
	t.not_null(_button(screen, "CAMPAIGN"), "no crash, a way back")
	screen.exit()
	h.vp.queue_free()
	await H.frames(2)
	_restore()


# ---------------------------------------------------------------- result screen

func _model(won: bool, extra: Dictionary = {}) -> Dictionary:
	var m: Dictionary = {"id": "ut_op_a", "title": "Operation Alpha", "won": won, "ticks": 4000, "clock": "3:20", "difficulty": 1, "difficulty_name": "Medium",
		"outcome": {"won": won, "first_clear": won, "new_best_time": won, "new_best_difficulty": won, "ticks": 4000},
		"objectives": [{"text": "Destroy the camp", "kind": 0, "state": 2 if won else 1, "word": "COMPLETE" if won else "NOT COMPLETED"},
			{"text": "Lose nobody", "kind": 1, "state": 3, "word": "FAILED"}],
		"stats": {"units_killed": 12, "units_lost": 3, "structures_destroyed": 2, "structures_lost": 0, "harvested": 5000, "spent": 4200},
		"next_id": "ut_op_b" if won else "", "faction_code": "nec", "summary": {}, "best_ticks": 4000}
	for k: Variant in extra:
		m[k] = extra[k]
	return m


func test_result_helpers(t: TestCtx) -> void:
	t.eq(UiScreenMissionResult.headline(true), "MISSION COMPLETE")
	t.eq(UiScreenMissionResult.headline(false), "MISSION FAILED")
	t.eq(UiScreenMissionResult.badges({"won": true, "first_clear": true, "new_best_time": true}), PackedStringArray(["FIRST CLEAR"]), "a first clear is not also a 'new best'")
	t.eq(UiScreenMissionResult.badges({"won": true, "new_best_time": true, "new_best_difficulty": true}), PackedStringArray(["NEW BEST TIME", "NEW HIGHEST DIFFICULTY"]))
	t.eq(UiScreenMissionResult.badges({"won": false, "new_best_time": true}), PackedStringArray(), "a defeat earns nothing")
	var rows: Array[Array] = UiScreenMissionResult.debrief_rows({"units_killed": 1200, "units_lost": 3})
	t.eq(rows[0], ["ENEMY UNITS DESTROYED", "1,200"])
	t.eq(UiScreenMissionResult.debrief_rows({}).size(), 0)


func test_result_screen_victory_and_defeat(t: TestCtx) -> void:
	_install()
	var h: H.Rig = await H.make()
	var win: UiScreenMissionResult = UiScreenMissionResult.new()
	_mount(h, win, {"mission": _model(true), "summary": {}})
	await H.frames(3)
	var labels: PackedStringArray = PackedStringArray()
	_collect_labels(win, labels)
	t.check(labels.has("Destroy the camp") and labels.has("Lose nobody") and labels.has("COMPLETE") and labels.has("FAILED"), "the objective list with final states")
	t.check(labels.has("3:20") and labels.has("Medium") and labels.has("FIRST CLEAR"), "time, difficulty and the first-clear chip")
	t.check(labels.has("ENEMY UNITS DESTROYED") and labels.has("12"), "debrief figures")
	var nav: Array = []
	win.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	t.not_null(_button(win, "NEXT MISSION"), "a win with an open next mission offers it")
	t.eq(win.default_focus(), _button(win, "NEXT MISSION"))
	t.check(_button(win, "WATCH REPLAY").disabled, "no recording, no replay button")
	_button(win, "NEXT MISSION").pressed.emit()
	t.eq(nav[0], [&"mission_briefing", {"mission": "ut_op_b"}], "NEXT MISSION goes to its briefing")
	_button(win, "CAMPAIGN").pressed.emit()
	t.eq(nav[1][0], &"campaign")
	t.eq(nav[1][1]["select"], "ut_op_b", "back in the campaign the next mission is selected")
	win.exit()
	h.vp.queue_free()
	await H.frames(2)
	var h2: H.Rig = await H.make()
	var lose: UiScreenMissionResult = UiScreenMissionResult.new()
	_mount(h2, lose, {"mission": _model(false), "summary": {}})
	await H.frames(3)
	t.is_null(_button(lose, "NEXT MISSION"), "a defeat has no next mission")
	t.eq(lose.default_focus(), _button(lose, "RETRY"), "RETRY takes the focus after a defeat")
	var labels2: PackedStringArray = PackedStringArray()
	_collect_labels(lose, labels2)
	t.check(labels2.has("NOT COMPLETED"), "the open objective is shown as not completed")
	t.check(not labels2.has("FIRST CLEAR"), "no chips after a defeat")
	var nav2: Array = []
	lose.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav2.append([target, p]))
	_button(lose, "CAMPAIGN").pressed.emit()
	t.eq(nav2[0][1]["select"], "ut_op_a", "after a defeat the campaign selects the same mission")
	lose.exit()
	h2.vp.queue_free()
	await H.frames(2)
	_restore()


func test_result_retry_starts_the_mission_again(t: TestCtx) -> void:
	t.set_timeout(60.0)
	_install()
	var h: H.Rig = await H.make()
	var screen: UiScreenMissionResult = UiScreenMissionResult.new()
	_mount(h, screen, {"mission": _model(false, {"difficulty": 3}), "summary": {}})
	await H.frames(2)
	var nav: Array = []
	screen.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	_button(screen, "RETRY").pressed.emit()
	t.eq(nav[0][0], &"loading")
	t.eq(nav[0][1]["mission"], "ut_op_a")
	var ctx: AppMatchContext = AppState.match_ctx as AppMatchContext
	if t.not_null(ctx, "a new context"):
		t.eq(ctx.mission_difficulty, 3, "retry keeps the difficulty")
	screen.exit()
	h.vp.queue_free()
	await H.frames(2)
	_restore()
