extends RefCounted
## The runtime against the tiny REAL OGG fixtures of tests/fixtures/audio (made by tools/py/audio/make_fixtures.py):
## index resolution, loop duplicates, stem stacks with bpm metadata, a spoken line, engine playback on the Dummy driver.


func _index() -> SndAssetIndex:
	var ix: SndAssetIndex = SndAssetIndex.new()
	ix.setup(SndTestKit.FIXTURE_INDEX)
	return ix


func test_index_resolution_and_groups(t: TestCtx) -> void:
	var ix: SndAssetIndex = _index()
	t.gt(ix.assets.size(), 10, "fixture index loaded")
	t.eq(ix.group_size("sfx/weapon/small_arms"), 3, "group size")
	t.eq(ix.group_members("sfx/weapon/small_arms"), PackedStringArray(["sfx/weapon/small_arms_1", "sfx/weapon/small_arms_2", "sfx/weapon/small_arms_3"]), "members")
	t.eq(ix.bank_of("ui/click"), &"core", "bank")
	t.check(ix.resolve_path("ui/click", true).ends_with("ui/click.mono.ogg"), "mono path")
	t.check(ix.resolve_path("ui/confirm", false).ends_with("ui/confirm.ogg"), "stereo path")
	t.eq(ix.resolve_path("no/such", true), "", "unknown id")


func test_streams_load_and_loops_are_duplicates(t: TestCtx) -> void:
	var ix: SndAssetIndex = _index()
	var s: AudioStream = ix.get_stream("sfx/weapon/small_arms_1", true)
	t.check(s is AudioStreamOggVorbis, "a real OGG stream")
	t.gt(s.get_length(), 0.1, "it has a length (%.3f s)" % s.get_length())
	t.check(not (s as AudioStreamOggVorbis).loop, "one-shots do not loop")
	var l: AudioStream = ix.get_stream("sfx/loop/engine_tracked", true)
	t.check((l as AudioStreamOggVorbis).loop, "loop assets come back looping")
	var raw: AudioStreamOggVorbis = load(ix.resolve_path("sfx/loop/engine_tracked", true)) as AudioStreamOggVorbis
	t.check(not raw.loop, "the cached resource itself is never mutated (a duplicate carries the loop flag)")
	t.check(ix.get_stream("sfx/loop/engine_tracked", true) == l, "cached")
	t.eq(ix.missing_files, 0, "no placeholder was needed")


func test_stem_stack_with_bpm(t: TestCtx) -> void:
	var ix: SndAssetIndex = _index()
	var sync: AudioStreamSynchronized = AudioStreamSynchronized.new()
	sync.stream_count = 4
	var stems: PackedStringArray = ["drums", "bass", "pads", "lead"]
	for i: int in 4:
		var s: AudioStreamOggVorbis = SndAssetIndex.apply_loop(ix.get_stream("mus/fixture/combat/" + stems[i], false), true) as AudioStreamOggVorbis
		s.bpm = 120.0
		s.beat_count = 8
		s.bar_beats = 4
		sync.set_sync_stream(i, s)
	t.eq(sync.stream_count, 4, "four stems")
	sync.set_sync_stream_volume(2, -6.0)
	t.near(sync.get_sync_stream_volume(2), -6.0, 0.001, "stem volume set")
	t.near(sync.get_sync_stream(0).get_length(), 4.0, 0.05, "2 bars at 120 BPM = 4 s")


func test_engine_playback_of_fixture_voices(t: TestCtx) -> void:
	t.set_timeout(30.0)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var r: Dictionary = SndTestKit.real()
	var ix: SndAssetIndex = _index()
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var map: SndEventMap = SndEventMap.new()
	map.build(r["store"], ix)  # most events are absent from the fixture index: errors expected, defs for the fixture ones exist
	var pool: SndVoicePool = SndVoicePool.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(pool)
	var container: Node3D = Node3D.new()
	root.add_child(container)
	pool.setup(map, (r["store"] as SndDataStore).mix, 11, Callable(clock, "now"))
	pool.attach_3d(container, 8)
	pool.set_listener(Vector3.ZERO, 1.0)
	var h: int = pool.play(&"snd.weapon.small_arms", Vector3(20, 1.5, 0))
	var h2: int = pool.play(&"snd.ui.click")
	t.check(h != 0 and h2 != 0, "3D and 2D voices started with real streams")
	var loop: int = pool.play(&"snd.loop.engine.tracked", Vector3(30, 1.5, 0))
	t.check(loop != 0, "loop voice")
	for i: int in 20:
		pool.update(1.0 / 60.0)
		await (Engine.get_main_loop() as SceneTree).process_frame
	t.check(pool.is_active(loop), "the loop keeps playing")
	pool.stop_all(0)
	pool.detach_3d()
	pool.queue_free()
	container.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func test_announcer_with_a_real_line(t: TestCtx) -> void:
	var r: Dictionary = SndTestKit.real()
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var a: SndAnnouncer = SndAnnouncer.new()
	a.setup(r["store"], _index(), Callable(clock, "now"), 3)
	a.set_pack(&"computer")
	t.check(a.say(&"base_under_attack"), "the fixture line plays")
	t.check(a.is_speaking(), "speaking")
	var len_ms: int = int((a._index.get_stream("vox/computer/base_under_attack", false) as AudioStream).get_length() * 1000.0)
	clock.advance(len_ms + 5)
	a.update(0.0, clock.ms)
	t.check(not a.is_speaking(), "ends after the stream length (%d ms)" % len_ms)
