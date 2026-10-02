extends RefCounted
## INT3 final wiring: FX stage in the view stage, audio install at boot, cursor states, range-ring setting, Field Manual entry points,
## LAN "back to the lobby" wording on the end screen.

const H := preload("res://tests/ui/ui_harness.gd")


func _gd() -> GameData:
	var app: Node = H.tree().root.get_node_or_null("AppState")
	var d: GameData = app.get("data") as GameData if app != null else null
	if d == null:
		d = GameData.load_default()
		if app != null:
			app.set("data", d)
	return d


func _start_ctx() -> AppMatchContext:
	var cfg: Dictionary = AppMatch.simple_config(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), 6, 96)
	var ctx: AppMatchContext = AppMatch.start_local(cfg, {"with_view": false, "bind": false, "unpaced": true})
	var guard: int = 0
	while ctx.session.phase == NetSession.Phase.LOADING and guard < 4000:
		ctx.session.poll()
		OS.delay_msec(2)
		guard += 1
	return ctx


func test_boot_hook_installs_audio_unless_disabled(t: TestCtx) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var state: Node = tree.root.get_node_or_null("AppState")
	if not t.not_null(state, "AppState autoload"):
		return
	var quiet: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--no-audio"]))
	AppBootHook.run(state, null, quiet)
	t.is_null(AppAudio.current, "--no-audio: nothing is installed")
	t.is_null(tree.root.get_node_or_null("Snd"), "--no-audio: no /root/Snd")
	AppBootHook.run(state, null, AppLaunchArgs.parse(PackedStringArray([])))
	t.not_null(AppAudio.current, "audio is installed by the boot hook")
	for i: int in 4:
		await tree.process_frame
	var app: AppAudio = AppAudio.current
	if app != null:
		t.check(app.ready, "the facade finished its setup")
		t.check(AppApply.audio_sink.is_valid(), "the Options audio sink is registered")
		AppApply.audio_sink.call({"audio/master": 42})
		t.eq(app.snd.settings().master, 42, "the master volume of the settings reaches the facade")
		app.uninstall()
	t.is_null(AppAudio.current, "uninstalled")


func test_view_stage_owns_the_fx_layer(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var ctx: AppMatchContext = _start_ctx()
	var w: SimWorld = ctx.world()
	if not t.not_null(w, "world"):
		ctx.dispose()
		return
	var h: H.Rig = await H.make()
	var stage: AppViewStage = AppViewStage.new()
	h.root.add_child(stage)
	stage.full_look = false
	stage.build_sync(w, 0)
	t.not_null(stage.fx_stage, "the FX stage is attached by the view stage")
	if stage.fx_stage != null:
		t.check(stage.view.router.extra_handler.is_valid(), "the FX router hooks the event router")
		t.check(stage.view.fx.suppressed.has(&"damage_smoke"), "the state views skip the ids the router owns")
		stage.set_paused(true)
		t.check(stage.fx_stage.fx.paused, "pausing the game freezes the FX clock")
		stage.set_paused(false)
	stage.teardown()
	t.is_null(stage.fx_stage, "teardown releases the FX stage")
	stage.queue_free()
	var lean: AppViewStage = AppViewStage.new()
	lean.with_fx = false
	lean.full_look = false
	h.root.add_child(lean)
	lean.build_sync(w, 0)
	t.is_null(lean.fx_stage, "with_fx = false keeps the stage lean (menu showcase)")
	lean.queue_free()
	ctx.dispose()
	H.done(h)
	await H.frames(2)


func test_cursor_states_and_range_rings(t: TestCtx) -> void:
	var d: GameData = _gd()
	var ctx: AppMatchContext = _start_ctx()
	var h: H.Rig = await H.make()
	var game: UiScreenGame = UiScreenGame.new()
	h.root.add_child(game)
	UiLayerRoot.fill(game)
	game.enter({"ctx": ctx})
	await H.frames(3)
	var pos: Vector2 = Vector2(400.0, 400.0)
	game.modes.arm(UiModes.Armed.ATTACK_MOVE)
	t.eq(game.hover_cursor(pos), UiCursors.State.ATTACK_MOVE, "armed attack-move shows the attack-move cursor")
	game.modes.arm(UiModes.Armed.SELL)
	t.eq(game.hover_cursor(pos), UiCursors.State.SELL, "armed sell shows the sell cursor")
	game.modes.disarm()
	# range rings follow ui/range_rings: 0 selection, 1 never, 2 selection + hovered entity
	var own: PackedInt32Array = PackedInt32Array()
	ctx.sim.own_ids(UiSimPort.KM_UNIT, own)
	game.selection.replace(own, ctx.sim)
	game.presenter.set_range_ring_mode(UiHudPresenter.RINGS_NEVER)
	var fixture: UiViewPortFixture = ctx.view as UiViewPortFixture
	if t.not_null(fixture, "headless context uses the fixture view"):
		t.eq(fixture.range_ring_ids.size(), 0, "mode 'never' draws no ring")
		game.presenter.set_range_ring_mode(UiHudPresenter.RINGS_SELECTION)
		t.eq(fixture.range_ring_ids.size(), mini(own.size(), 12), "mode 'selection' rings the selected units")
		var eid: int = 0
		for e: SimEntity in ctx.world().entities:
			if e.owner == 1 and e.kind == SimEntity.Kind.UNIT:
				eid = e.id
				break
		game.presenter.set_range_ring_mode(UiHudPresenter.RINGS_HOVER)
		game.presenter.set_hover_entity(eid)
		t.check(eid == 0 or fixture.range_ring_ids.has(eid) or fixture.range_ring_ids.size() >= 12, "mode 'always' adds the entity under the pointer")
	game.exit()
	t.eq(UiCursors.current_state(), UiCursors.State.DEFAULT, "leaving the match restores the arrow")
	ctx.dispose()
	AppState.match_ctx = null
	game.queue_free()
	H.done(h)
	await H.frames(2)
	t.eq(d.factions.size(), 8)


func test_input_sink_reconfigures_the_controller(t: TestCtx) -> void:
	var ctx: AppMatchContext = _start_ctx()
	var h: H.Rig = await H.make()
	var game: UiScreenGame = UiScreenGame.new()
	h.root.add_child(game)
	UiLayerRoot.fill(game)
	game.enter({"ctx": ctx})
	await H.frames(2)
	t.check(AppApply.input_sink.is_valid(), "the game screen registers the input sink")
	var store: AppSettingsStore = AppSettingsStore.new()
	store.set_value(&"input/double_click_ms", 555)
	AppApply.input_sink.call(&"input/double_click_ms", store)
	t.eq(game.controller.double_click_ms, 555, "an Options change reaches the live controller")
	game.exit()
	t.check(not AppApply.input_sink.is_valid() or AppApply.input_sink.get_object() != game, "the sink is released with the screen")
	ctx.dispose()
	AppState.match_ctx = null
	game.queue_free()
	H.done(h)
	await H.frames(2)


func test_end_screen_buttons(t: TestCtx) -> void:
	var h: H.Rig = await H.make()
	var end: UiScreenEnd = UiScreenEnd.new()
	h.root.add_child(end)
	UiLayerRoot.fill(end)
	end.enter({"summary": {"players": [], "series": {}, "result": "draw", "winner_team": -1, "duration_ticks": 0, "map": "", "seed": 0}})
	await H.frames(2)
	var nav: Array = []
	end.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	t.eq(end._play_again.text, "PLAY AGAIN", "a local match offers PLAY AGAIN")
	end._on_play_again()
	t.eq(nav[0][0], &"lobby", "play again opens the skirmish lobby")
	t.eq(nav[0][1].get("role", ""), "local")
	end._on_main_menu()
	t.eq(nav[1][0], &"main_menu")
	H.done(h)
	await H.frames(2)


func test_selection_plays_the_unit_response(t: TestCtx) -> void:
	var ctx: AppMatchContext = _start_ctx()
	var rec: UiAudioPortRecorder = UiAudioPortRecorder.new()
	ctx.audio = rec
	var h: H.Rig = await H.make()
	var game: UiScreenGame = UiScreenGame.new()
	h.root.add_child(game)
	UiLayerRoot.fill(game)
	game.enter({"ctx": ctx})
	await H.frames(2)
	var own: PackedInt32Array = PackedInt32Array()
	ctx.sim.own_ids(UiSimPort.KM_UNIT | UiSimPort.KM_STRUCTURE, own)
	if t.check(own.size() > 0, "the local player owns entities"):
		game.selection.replace(own, ctx.sim)
		game._say_selected()
		t.eq(rec.count_of(&"unit_selected"), 1, "a selection asks the audio port for the unit response")
		var args: Array = rec.calls[rec.calls.size() - 1][1]
		t.eq(args[2], own.size(), "with the selection size")
		game.selection.clear()
		var before: int = rec.count_of(&"unit_selected")
		game._say_selected()
		t.eq(rec.count_of(&"unit_selected"), before, "an empty selection says nothing")
	game.exit()
	ctx.dispose()
	AppState.match_ctx = null
	game.queue_free()
	H.done(h)
	await H.frames(2)
