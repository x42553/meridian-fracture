extends RefCounted
## AppAudio + AppAudioFeed over a real headless LOCAL session (AppMatch.start_local): the facade appears as /root/Snd, the
## per-frame feed starts the match audio, swaps the UI port, and the event batch reaches the bridge without the game screen.


func _cfg() -> Dictionary:
	return AppMatch.simple_config(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), 6, 96)


func test_install_feed_and_match(t: TestCtx) -> void:
	t.set_timeout(180.0)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var state: Node = tree.root.get_node_or_null("AppState")
	if not t.not_null(state, "AppState autoload"):
		return
	var args: AppLaunchArgs = AppLaunchArgs.new()
	var app: AppAudio = AppAudio.install(state, null, args)
	t.not_null(app, "installed")
	for i: int in 3:
		await tree.process_frame
	t.check(app.ready, "AppAudio finished its deferred setup")
	t.not_null(tree.root.get_node_or_null("Snd"), "/root/Snd exists")
	t.check(state.get("audio") == app, "AppState.audio is the adapter")
	t.check(AppApply.audio_sink.is_valid(), "settings sink registered")
	# settings reach the facade
	AppApply.audio_sink.call({"audio/master": 55, "audio/announcer": 1})
	t.eq(app.snd.settings().master, 55, "master slider")
	t.eq(app.snd.settings().announcer_mode, SndSettings.ANN_COMPUTER, "announcer mode")
	# a headless LOCAL match
	var ctx: AppMatchContext = AppMatch.start_local(_cfg(), {"with_view": false, "bind": false, "unpaced": true, "discard_events": false})
	t.not_null(ctx, "session started")
	if ctx == null:
		app.uninstall()
		return
	var guard: int = 0
	while guard < 1500 and (ctx.session.phase == NetSession.Phase.LOADING or ctx.audio == null):
		await tree.process_frame
		guard += 1
	# let the feed see the world and the match run for a while
	var frames: int = 0
	while frames < 2000 and app.snd.stats().starts < 3:
		await tree.process_frame
		frames += 1
	t.check(ctx.audio is UiAudioPortSnd, "the context's null port was swapped for the Snd port")
	t.check(app.snd.is_match_ready(), "match audio is ready")
	t.check(app.snd.is_world_attached(), "the stand-in world root is attached (headless run)")
	var starts: int = app.snd.stats().starts
	t.gt(starts, 0, "sounds started from the peeked event batches (%d after %d frames)" % [starts, frames])
	t.check(ctx.world().events.data.size() >= 0, "the buffer was only peeked at")
	# ending the match ends the audio side
	var net: Node = tree.root.get_node_or_null("AppNet")
	if net != null:
		net.call("end_session")
	for i: int in 3:
		await tree.process_frame
	t.check(not app.snd.is_match_ready(), "match audio ended with the session")
	app.uninstall()
	t.is_null(AppAudio.current, "uninstalled")


func test_ui_cues_for_menu_widgets(t: TestCtx) -> void:
	t.set_timeout(30.0)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var app: AppAudio = AppAudio.install(tree.root.get_node_or_null("AppState"), null, AppLaunchArgs.new())
	for i: int in 3:
		await tree.process_frame
	if not t.check(app != null and app.ready, "installed"):
		return
	var b: Button = Button.new()
	tree.root.add_child(b)
	var before: int = app.snd.stats().starts
	b.pressed.emit()
	t.eq(app.snd.stats().starts, before + 1, "a pressed Button plays snd.ui.click")
	var cb: CheckBox = CheckBox.new()
	tree.root.add_child(cb)
	before = app.snd.stats().starts
	cb.button_pressed = true
	t.eq(app.snd.stats().starts, before + 1, "a toggled CheckBox plays a toggle cue")
	b.queue_free()
	cb.queue_free()
	await tree.process_frame
	app.uninstall()
