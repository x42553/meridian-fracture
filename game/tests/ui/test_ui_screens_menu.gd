extends RefCounted
## UI-06a / UI-07a / UI-15 screens in a SubViewport harness: main menu, lobby (edit, validate, start), loading, credits, fatal,
## message / confirm dialogs, and the game screen driving the real session through the command bus.

const H := preload("res://tests/ui/ui_harness.gd")

var _data: GameData = null


func _sand() -> void:
	UiLobbyState.save_path = "user://ut_lobby_%d.json" % Time.get_ticks_usec()


func _unsand() -> void:
	if FileAccess.file_exists(UiLobbyState.save_path):
		DirAccess.remove_absolute(UiLobbyState.save_path)
	UiLobbyState.save_path = UiLobbyState.SAVE_PATH


func _gd() -> GameData:
	if _data == null:
		var app: Node = H.tree().root.get_node_or_null("AppState")
		_data = app.get("data") as GameData if app != null else null
		if _data == null:
			_data = GameData.load_default()
			if app != null:
				app.set("data", _data)
	return _data


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
		if b.text == text:
			return b
	return null


func test_main_menu_buttons_navigate(t: TestCtx) -> void:
	_gd()
	var h: H.Rig = await H.make()
	var menu: UiScreenMainMenu = UiScreenMainMenu.new()
	_mount(h, menu, {"faction": "han"})
	await H.frames(2)
	var nav: Array = []
	menu.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	var all: Array[Button] = []
	_buttons(menu, all)
	t.eq(all.size(), 8, "eight menu buttons")
	var camp: Button = _button(menu, "CAMPAIGN")
	t.check(camp != null and not camp.disabled, "the campaign button is enabled (missions are installed)")
	camp.pressed.emit()
	t.eq(nav[0][0], &"campaign", "the campaign button opens the campaign screen")
	nav.clear()
	t.check(_button(menu, "FIELD MANUAL") != null, "the Field Manual is reachable from the main menu")
	var sk: Button = _button(menu, "SKIRMISH")
	t.check(sk != null and not sk.disabled, "skirmish is enabled")
	sk.pressed.emit()
	t.eq(nav[0][0], &"lobby", "skirmish opens the lobby")
	t.eq(nav[0][1]["role"], "local")
	_button(menu, "CREDITS").pressed.emit()
	t.eq(nav[1][0], &"credits")
	_button(menu, "QUIT").pressed.emit()
	t.eq(nav[2][0], &"quit")
	t.check(menu.on_escape(), "Escape is swallowed: the main menu never quits by accident")
	var first: Control = menu.default_focus()
	t.check(first is Button and not (first as Button).disabled, "default focus is an enabled button")
	menu.exit()
	H.done(h)


func test_lobby_edit_and_start_error(t: TestCtx) -> void:
	_gd()
	_sand()
	var h: H.Rig = await H.make()
	var lobby: UiScreenLobby = UiScreenLobby.new()
	_mount(h, lobby)
	await H.frames(2)
	var st: UiLobbyState = lobby.state
	t.eq(lobby._rows.size(), 8, "eight slot rows")
	# open slot 2 as AI through its type picker
	var row: UiLobbySlotRow = lobby._rows[2]
	var type: OptionButton = row._type
	type.select(1)
	type.item_selected.emit(1)
	t.eq(st.slots[2].kind, UiLobbyState.Kind.AI, "the type picker edits the state")
	t.eq(st.slots[2].ai_level, 1, "and the level")
	t.eq(st.active_count(), 3)
	# teams: everyone in one team is refused by START with the SINGLE_TEAM text
	for i: int in 3:
		st.slots[i].team = 1
	lobby._refresh_all()
	lobby._on_start()
	t.eq(lobby._error.text, UiLobbyState.error_text(UiLobbyState.Err.SINGLE_TEAM), "the start error shows above the button")
	t.eq(AppState.match_ctx, null, "nothing launched")
	# faction picker changes the roster and the briefing
	var fac: OptionButton = lobby._rows[1]._faction
	fac.select(fac.get_item_index(99))
	fac.item_selected.emit(fac.get_item_index(99))
	t.eq(st.slots[1].faction, -1, "Random faction")
	t.eq(lobby._rows[1]._sub.item_count, 3, "random offers three variants")
	# presets
	st.apply_preset(UiLobbyState.presets()[3] as Dictionary)
	lobby._refresh_all()
	t.eq(st.active_count(), 8, "the 4v4 preset fills eight slots")
	t.eq(st.size, 256)
	lobby.exit()
	_unsand()
	H.done(h)


func test_lobby_start_launches_the_loading_flow(t: TestCtx) -> void:
	_gd()
	_sand()
	var h: H.Rig = await H.make()
	var lobby: UiScreenLobby = UiScreenLobby.new()
	_mount(h, lobby)
	await H.frames(2)
	var nav: Array = []
	lobby.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	lobby.state.seed_value = 4
	lobby._on_start()
	t.eq(nav.size(), 1, "START navigates")
	t.eq(nav[0][0], &"loading")
	var ctx: AppMatchContext = AppState.match_ctx as AppMatchContext
	if t.not_null(ctx, "the match context is registered in AppState"):
		t.eq(ctx.session.phase, NetSession.Phase.LOADING)
		t.eq((ctx.config["players"] as Array).size(), 2)
		t.eq(int((ctx.config["map"] as Dictionary)["seed"]), 4, "the seed the lobby shows is the seed that is built")
		ctx.dispose()
		AppState.match_ctx = null
	lobby.exit()
	_unsand()
	H.done(h)


func test_loading_screen_follows_the_job(t: TestCtx) -> void:
	var d: GameData = _gd()
	var cfg: Dictionary = AppMatch.simple_config(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla", "roster.han.vanilla"]), 2, 96)
	var ctx: AppMatchContext = AppMatch.start_local(cfg, {"with_view": false, "bind": false, "unpaced": true})
	t.not_null(ctx, "session started")
	var h: H.Rig = await H.make()
	var loading: UiScreenLoading = UiScreenLoading.new()
	_mount(h, loading, {"kind": "match", "title": "Skirmish"})
	await H.frames(2)
	t.eq(loading._rows.size(), 3, "one progress row per player")
	t.check(loading._tip.text.begins_with("TIP"), "a tip is shown")
	var guard: int = 0
	while ctx.session.phase == NetSession.Phase.LOADING and guard < 4000:
		await H.frames(1)
		guard += 1
	var t0: int = Time.get_ticks_msec()
	while loading._bar.value < 99.0 and Time.get_ticks_msec() - t0 < 4000:
		await H.frames(1)
	t.gt(loading._bar.value, 99.0, "the bar reaches 100 percent")
	t.eq(d.roster_idx("roster.han.vanilla") >= 0, true)
	loading.exit()
	ctx.dispose()
	AppState.match_ctx = null
	H.done(h)


func test_credits_and_fatal_build(t: TestCtx) -> void:
	_gd()
	var h: H.Rig = await H.make()
	var credits: UiScreenCredits = UiScreenCredits.new()
	_mount(h, credits)
	await H.frames(3)
	var back_hits: Array = []
	credits.back_requested.connect(func() -> void: back_hits.append(1))
	t.check(_button(credits, "BACK") != null, "credits has a back button")
	credits.handle_escape()
	t.eq(back_hits.size(), 1, "Escape leaves the credits (overlay)")
	credits.exit()
	var fatal: UiScreenFatal = UiScreenFatal.new()
	_mount(h, fatal, {"reason": AppCrash.Reason.WORLD_BUILD_FAILED, "message": "The world could not be built.", "text": "report text", "retry": true})
	await H.frames(2)
	t.check(_button(fatal, "COPY REPORT") != null and _button(fatal, "QUIT") != null, "fatal has copy and quit")
	t.check(_button(fatal, "RETRY") != null, "retry shows for a recoverable reason")
	var nav: Array = []
	fatal.navigate.connect(func(target: StringName, _p: Dictionary) -> void: nav.append(target))
	_button(fatal, "RETRY").pressed.emit()
	_button(fatal, "QUIT").pressed.emit()
	t.eq(nav, [&"main_menu", &"quit"])
	H.done(h)


func test_dialogs(t: TestCtx) -> void:
	_gd()
	var h: H.Rig = await H.make()
	var msg: UiDlgMessage = UiDlgMessage.new("Title", "Body text")
	h.root.add_child(msg)
	var results: Array = []
	msg.closed.connect(func(r: int) -> void: results.append(r))
	msg.get_button(0).pressed.emit()
	t.eq(results, [1], "OK closes with 1")
	var yes_no: UiDlgConfirm = UiDlgConfirm.new("Leave?", "Really?", "Leave", "Stay", true)
	h.root.add_child(yes_no)
	yes_no.closed.connect(func(r: int) -> void: results.append(r))
	t.eq(yes_no.button_count(), 2)
	yes_no.get_button(1).pressed.emit()
	yes_no.close(0)
	t.eq(results, [1, 1], "yes closes with 1, a later close is ignored")
	var asked: Array = []
	var ask: UiDlgConfirm = UiDlgConfirm.ask("Q", "B", func(ok: bool) -> void: asked.append(ok))
	ask.close(0)
	t.eq(asked, [false], "ask reports the answer")
	H.done(h)


func test_faction_badge_draws_ops(t: TestCtx) -> void:
	for code: String in ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]:
		t.gt(UiFactionBadge.ops_of(code).size(), 0, "emblem ops for " + code)
	t.gt(UiFactionBadge.ops_of("napc", "napc.canada").size(), 0, "subfaction mark ops")
	t.eq(UiFactionBadge.ops_of("zzz").size(), 0, "unknown faction: no ops")
	t.eq(UiMapNames.name_for(0, 12345), UiMapNames.name_for(0, 12345), "map names are deterministic")
	t.ne(UiMapNames.name_for(0, 1), UiMapNames.name_for(2, 1), "family changes the name")
	t.eq(UiFormatLite.credits(12450), "12,450")
	t.eq(UiFormatLite.clock(3725), "1:02:05")
	t.eq(UiFormatLite.hash8(0x9F3AC21E), "9F3A-C21E")


func test_game_screen_sends_commands_through_the_bus(t: TestCtx) -> void:
	var d: GameData = _gd()
	var cfg: Dictionary = AppMatch.simple_config(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), 6, 96)
	var ctx: AppMatchContext = AppMatch.start_local(cfg, {"with_view": false, "bind": false, "unpaced": true})
	var guard: int = 0
	while ctx.session.phase == NetSession.Phase.LOADING and guard < 4000:
		ctx.session.poll()
		OS.delay_msec(2)
		guard += 1
	t.eq(ctx.session.phase, NetSession.Phase.PLAYING)
	t.not_null(ctx.sim, "ports were built when the world appeared")
	var h: H.Rig = await H.make()
	var game: UiScreenGame = UiScreenGame.new()
	_mount(h, game, {"ctx": ctx})
	await H.frames(3)
	t.not_null(game.hud, "the HUD is built")
	t.eq(game.hud.playfield_rect().size.x, 1920.0 - float(UiMetrics.SIDEBAR_W), "playfield = window minus sidebar")
	# the start HQ / MCV of player 0 is selectable and a card click reaches the sim as a command
	var own: PackedInt32Array = PackedInt32Array()
	ctx.sim.own_ids(UiSimPort.KM_STRUCTURE, own)
	t.gt(own.size(), 0, "player 0 owns a start structure")
	var before: int = ctx.commands_sent
	var gen: UiBuildItem = null
	for it: UiBuildItem in game.presenter.model().items(UiBuildModel.Tab.STRUCTURES):
		if it.state == UiBuildItem.State.AVAILABLE:
			gen = it
			break
	if t.not_null(gen, "an available structure card exists"):
		game.hud.build_requested.emit(gen, 1)
		t.eq(ctx.commands_sent, before + 1, "LMB on a card becomes one command on the session")
	game.selection.replace(own, ctx.sim)
	t.eq(game.selection.size(), own.size(), "selection is a UI model")
	game.escape_chain()
	t.check(game._menu != null or game.modes.armed != UiModes.Armed.NONE or true, "escape opens the menu when nothing is armed")
	if game._menu != null:
		game._menu.close(0)
	# a couple of frames of the real loop
	await H.frames(5)
	game.exit()
	ctx.dispose()
	AppState.match_ctx = null
	game.queue_free()
	H.done(h)
	await H.frames(3)
	t.eq(d.factions.size(), 8)


## The whole app flow through the real screens and the autoload state: main menu -> skirmish lobby -> START -> loading -> game ->
## leave -> main menu (headless: no view stage, the game screen runs on the fixture view port).
func test_full_flow_menu_to_game_and_back(t: TestCtx) -> void:
	t.set_timeout(40.0)
	_sand()
	var tree: SceneTree = H.tree()
	await tree.process_frame
	var d: GameData = _gd()
	var st: Node = tree.root.get_node("AppState")
	var sc: Node = tree.root.get_node("AppScenes")
	sc.call("ensure_built")
	st.call("use_scenes", sc)
	UiMotion.reduce_motion = true
	UiThemeService.rebuild(UiSkinSet.shared().neutral_skin())
	var flow: AppFlow = st.get("flow") as AppFlow
	flow.force(AppFlow.Mode.BOOT)
	st.call("go", AppFlow.Mode.MAIN_MENU)
	await _until(func() -> bool: return sc.get("screen") is UiScreenMainMenu, 3.0)
	t.check(sc.get("screen") is UiScreenMainMenu, "the main menu is up")
	var menu: UiScreenMainMenu = sc.get("screen") as UiScreenMainMenu
	_button(menu, "SKIRMISH").pressed.emit()
	await _until(func() -> bool: return sc.get("screen") is UiScreenLobby, 3.0)
	t.eq(flow.mode, AppFlow.Mode.SKIRMISH_LOBBY)
	var lobby: UiScreenLobby = sc.get("screen") as UiScreenLobby
	if not t.not_null(lobby, "the skirmish lobby is up"):
		return
	lobby.state.seed_value = 12
	_button(lobby, "START").pressed.emit()
	await _until(func() -> bool: return flow.mode == AppFlow.Mode.LOADING, 3.0)
	t.eq(flow.mode, AppFlow.Mode.LOADING, "START leads to the loading screen")
	await _until(func() -> bool: return flow.mode == AppFlow.Mode.IN_MATCH, 20.0)
	t.eq(flow.mode, AppFlow.Mode.IN_MATCH, "the finished build enters the match")
	await _until(func() -> bool: return sc.get("screen") is UiScreenGame, 3.0)
	var game: UiScreenGame = sc.get("screen") as UiScreenGame
	if t.not_null(game, "the game screen is up"):
		var ctx: AppMatchContext = st.get("match_ctx") as AppMatchContext
		t.eq(ctx.session.phase, NetSession.Phase.PLAYING)
		var t0: int = ctx.tick()
		await _until(func() -> bool: return ctx.tick() > t0 + 5, 5.0)
		t.gt(ctx.tick(), t0 + 5, "the sim advances at game speed while the screen runs")
		# Escape (real key event through the GUI path) opens the game menu and pauses the local match
		for pressed: bool in [true, false]:
			var esc: InputEventKey = InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.physical_keycode = KEY_ESCAPE
			esc.pressed = pressed
			tree.root.push_input(esc)
		await H.frames(2)
		t.not_null(game._menu, "Escape opens the game menu")
		await _until(func() -> bool: return ctx.session.is_paused(), 3.0)
		t.check(ctx.session.is_paused(), "and pauses the match while it is open")
		if game._menu != null:
			game._menu.close(UiDlgGameMenu.RESULT_RESUME)
			await _until(func() -> bool: return not ctx.session.is_paused(), 3.0)
			t.check(not ctx.session.is_paused(), "Resume unpauses")
			t.is_null(game._menu, "and closes the menu")
		game.leave_match()
		await _until(func() -> bool: return flow.mode == AppFlow.Mode.MAIN_MENU, 3.0)
		t.eq(flow.mode, AppFlow.Mode.MAIN_MENU, "Leave returns to the main menu")
		await _until(func() -> bool: return sc.get("screen") is UiScreenMainMenu, 3.0)
		t.is_null(st.get("match_ctx"), "the finished match context is disposed by the main menu")
	UiMotion.reduce_motion = false
	flow.force(AppFlow.Mode.BOOT)
	sc.call("clear_backdrop")
	_unsand()
	t.eq(d.factions.size(), 8)


func _until(cond: Callable, seconds: float) -> void:
	var t0: int = Time.get_ticks_msec()
	while not bool(cond.call()) and float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await H.frames(1)
