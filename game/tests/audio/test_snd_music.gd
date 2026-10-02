extends RefCounted
## Music state machine (stubbed interactive playback) and stem curves (audio spec 5.8).


class StubPlayback:
	extends RefCounted
	var clip: int = 0
	var switches: Array[int] = []

	func switch_to_clip(i: int) -> void:
		switches.append(i)
		clip = i

	func get_current_clip_index() -> int:
		return clip


func _director() -> Array:
	var r: Dictionary = SndTestKit.real()
	var lib: SndMusicLibrary = SndMusicLibrary.new()
	lib.setup(r["store"], r["index"])
	var d: SndMusicDirector = SndMusicDirector.new()
	d.setup(lib, r["store"])
	var stub: StubPlayback = StubPlayback.new()
	d.playback_stub = stub
	d._state = SndMusicDirector.State.CALM  # as after enter_match, without touching the audio server
	return [d, stub]


func test_state_machine(t: TestCtx) -> void:
	var pair: Array = _director()
	var d: SndMusicDirector = pair[0]
	var stub: StubPlayback = pair[1]
	t.check(d.request_state(SndMusicDirector.State.COMBAT, false, 20000), "calm -> combat requested")
	t.eq(stub.switches, [1], "clip 1 (with the riser as filler)")
	t.check(d.is_transition_pending(), "pending")
	t.check(not d.request_state(SndMusicDirector.State.CALM, false, 21000), "a reversal while pending is ignored (probe P3)")
	t.check(not d.request_state(SndMusicDirector.State.COMBAT, false, 21000), "the same request while pending is ignored")
	t.eq(stub.switches.size(), 1, "nothing forwarded")
	d.update(0.016, 21000)
	t.check(d.is_transition_pending(), "still pending before the fade elapsed")
	d.update(0.016, 20000 + 10000)
	t.check(not d.is_transition_pending(), "complete when the clip maps to the target and the fade elapsed")
	t.eq(d.current_state(), SndMusicDirector.State.COMBAT, "state is COMBAT")
	t.check(not d.request_state(SndMusicDirector.State.CALM, false, 32000), "min switch interval 8 s: too early")
	t.check(d.request_state(SndMusicDirector.State.CALM, false, 40500), "allowed after the interval")
	t.eq(stub.switches, [1, 0], "back to clip 0")


func test_urgent_uses_the_hot_clip(t: TestCtx) -> void:
	var pair: Array = _director()
	var d: SndMusicDirector = pair[0]
	var stub: StubPlayback = pair[1]
	t.check(d.request_state(SndMusicDirector.State.COMBAT, true, 1000), "urgent request")
	t.eq(stub.switches, [3], "urgent while CALM enters through combat_hot (clip 3)")
	d.update(0.016, 1000 + 10000)
	t.eq(d.current_state(), SndMusicDirector.State.COMBAT, "clip 3 maps to COMBAT")


func test_request_to_current_state_is_not_forwarded(t: TestCtx) -> void:
	var pair: Array = _director()
	var d: SndMusicDirector = pair[0]
	var stub: StubPlayback = pair[1]
	t.check(not d.request_state(SndMusicDirector.State.CALM, false, 50000), "already CALM")
	t.check(not d.request_state(SndMusicDirector.State.NONE, false, 50000), "invalid target")
	t.eq(stub.switches.size(), 0, "no switch")


func test_stem_curves(t: TestCtx) -> void:
	var pair: Array = _director()
	var d: SndMusicDirector = pair[0]
	t.near(d.stem_target_db("combat", "drums", 0.5), -3.01, 0.02, "drums t = 0.5 -> -3.01 dB")
	t.near(d.stem_target_db("combat", "bass", 0.5), 0.0, 0.01, "bass t = 1 -> 0 dB")
	t.near(d.stem_target_db("combat", "pads", 0.5), 0.0, 0.01, "pads full")
	t.near(d.stem_target_db("combat", "lead", 0.5), -80.0, 0.01, "lead t = 0 -> floor")
	t.near(d.stem_target_db("calm", "pads", 0.1), -3.01, 0.02, "calm pads at 0.1 (window 0..0.2)")


func test_stem_volume_updates_only_on_change(t: TestCtx) -> void:
	# a real Synchronized stack: set_sync_stream_volume is called only when the smoothed dB moved by >= 0.05
	var r: Dictionary = SndTestKit.real()
	var lib: SndMusicLibrary = SndMusicLibrary.new()
	lib.setup(r["store"], r["index"])
	var built: SndMusicLibrary.Built = SndMusicLibrary.Built.new()
	var sync: AudioStreamSynchronized = AudioStreamSynchronized.new()
	sync.stream_count = 4
	built.sync = {&"calm": sync, &"combat": sync}
	built.stems = PackedStringArray(["drums", "bass", "pads", "lead"])
	var d: SndMusicDirector = SndMusicDirector.new()
	d.setup(lib, r["store"])
	d._built = built
	d._state = SndMusicDirector.State.COMBAT
	d.set_intensity(0.5)
	for i: int in 400:
		d.update(1.0 / 60.0, i * 16)
	var settled: float = sync.get_sync_stream_volume(1)
	t.near(settled, 0.0, 0.1, "bass settles at 0 dB")
	t.near(sync.get_sync_stream_volume(0), -3.01, 0.15, "drums settle at -3 dB")
	var applied_before: Dictionary = d._stem_applied.duplicate()
	d.update(1.0 / 60.0, 7000)
	t.eq(d._stem_applied, applied_before, "no writes once nothing moved")


## Fixture index: every stem / stinger of the napc set exists as an index entry; the files do not, so silent placeholders stand in.
func _music_index() -> SndAssetIndex:
	var r: Dictionary = SndTestKit.real()
	var ix: SndAssetIndex = SndAssetIndex.new()
	ix.assets = (r["index"] as SndAssetIndex).assets.duplicate()
	var music: Dictionary = (r["store"] as SndDataStore).music
	for tid: Variant in music["tracks"].keys():
		var td: Dictionary = music["tracks"][tid]
		for stem: Variant in td["stems"]:
			var aid: String = "%s/%s" % [td["folder"], stem]
			ix.assets[aid] = {"f": aid + ".ogg", "b": "mus_x", "c": 2, "l": 1}
	for sid: Variant in music["stingers"].keys():
		var aid2: String = str(music["stingers"][sid]["stream"])
		ix.assets[aid2] = {"f": aid2 + ".ogg", "b": "mus_x", "c": 2, "l": 0}
	return ix


func test_interactive_stream_and_real_playback(t: TestCtx) -> void:
	t.set_timeout(30.0)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var r: Dictionary = SndTestKit.real()
	var lib: SndMusicLibrary = SndMusicLibrary.new()
	lib.setup(r["store"], _music_index())
	var built: SndMusicLibrary.Built = lib.build_interactive(&"napc")
	t.not_null(built, "napc interactive stream builds")
	if built == null:
		return
	var inter: AudioStreamInteractive = built.stream
	t.eq(inter.clip_count, 4, "four clips")
	t.eq(inter.get_clip_name(0), &"calm", "clip 0 calm")
	t.eq(inter.get_clip_name(3), &"combat_hot", "clip 3 hot")
	t.check(inter.has_transition(0, 1), "calm -> combat")
	t.check(inter.is_transition_using_filler_clip(0, 1), "with the riser filler")
	t.eq(inter.get_transition_filler_clip(0, 1), 2, "filler is clip 2")
	t.check(inter.has_transition(0, 3), "calm -> combat_hot")
	t.check(inter.has_transition(1, 0), "combat -> calm")
	t.check(inter.has_transition(3, 0), "combat_hot -> calm")
	t.eq(built.stems, PackedStringArray(["drums", "bass", "pads", "lead"]), "stem order")
	t.eq(built.sync[&"calm"].stream_count, 4, "four stems per clip")
	# real player on the Dummy driver: switch clips
	var d: SndMusicDirector = SndMusicDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(d)
	d.setup(lib, r["store"])
	d.enter_match(&"napc")
	t.eq(d.current_state(), SndMusicDirector.State.CALM, "CALM after enter_match")
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	d.set_intensity(0.4)
	for i: int in 30:
		d.update(1.0 / 60.0, 1000 + i * 16)
	var levels: PackedFloat32Array = d.stem_levels_db()
	t.eq(levels.size(), 4, "four stem levels")
	t.gt(levels[2], -70.0, "pads came in")
	var pb: Object = d._playback()
	t.not_null(pb, "engine playback exists")
	if pb != null:
		t.check(pb is AudioStreamPlaybackInteractive, "it is an interactive playback")
		t.check(d.request_state(SndMusicDirector.State.COMBAT, false, 20000), "real switch request")
		t.eq(d.pending_state(), SndMusicDirector.State.COMBAT, "pending")
	d.stop(0)
	d.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func test_menu_theme_and_stinger(t: TestCtx) -> void:
	t.set_timeout(30.0)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var r: Dictionary = SndTestKit.real()
	var lib: SndMusicLibrary = SndMusicLibrary.new()
	lib.setup(r["store"], _music_index())
	var d: SndMusicDirector = SndMusicDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(d)
	d.setup(lib, r["store"])
	d.enter_menu("menu")
	t.eq(d.current_state(), SndMusicDirector.State.MENU, "MENU")
	d.update(0.016, 0)
	d.play_stinger(&"stinger.napc.victory", 100)
	t.eq(d.current_state(), SndMusicDirector.State.STINGER, "STINGER")
	d.stop(0)
	d.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
