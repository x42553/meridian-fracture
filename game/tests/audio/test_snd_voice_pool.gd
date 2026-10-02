extends RefCounted
## Voice pool: attenuation model, limits, reserve, stealing, handles, intervals, loop ramps, audio space, fuzz.


func _pool(clock: SndTestKit.FakeClock, voices: int = 48) -> SndVoicePool:
	return SndTestKit.virtual_pool(clock, voices)


func test_attenuation(t: TestCtx) -> void:
	var def: SndEventDef = SndEventDef.new()
	def.unit_size_m = 22.0
	def.max_distance_m = 170.0
	def.attenuation = SndEventDef.Atten.INVERSE
	t.near(SndVoicePool.model_db(def, 22.0), 0.0, 0.05, "model_db(22)")
	t.near(SndVoicePool.model_db(def, 88.0), -12.04, 0.05, "model_db(88)")
	t.near(SndVoicePool.model_db(def, 5.0), 3.0, 0.001, "clamped at +3 dB")
	t.near(SndVoicePool.attenuation_db(def, 85.0), -17.76, 0.05, "attenuation_db(85)")
	def.attenuation = SndEventDef.Atten.INVERSE_SQUARE
	t.near(SndVoicePool.model_db(def, 44.0), -12.04, 0.05, "inverse square doubles the slope")
	def.attenuation = SndEventDef.Atten.NONE
	t.near(SndVoicePool.model_db(def, 1000.0), 0.0, 0.001, "no attenuation")


func test_audio_space(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var pool: SndVoicePool = _pool(clock)
	pool.set_listener(Vector3.ZERO, 1.0 / 2.0)
	var p: Vector3 = pool.to_audio_space(Vector3(60, 1.5, 0))
	t.near(p.x, 30.0, 0.001, "zoom scale 2.0 halves the distance")
	t.near(p.y, 1.5, 0.001, "height preserved")
	pool.set_listener(Vector3.ZERO, 1.0 / 0.7)
	t.near(pool.to_audio_space(Vector3(70, 1.5, 0)).x, 100.0, 0.01, "scale 0.7 pushes it out")
	pool.set_listener(Vector3(10, 0, 10), 1.0)
	t.near(pool.to_audio_space(Vector3(20, 1.5, 30)).z, 30.0, 0.001, "scale 1 is the identity")


func test_intervals(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var pool: SndVoicePool = _pool(clock)
	pool.set_listener(Vector3.ZERO, 1.0)
	var pos: Vector3 = Vector3(20, 1.5, 0)
	var h1: int = pool.play(&"snd.weapon.small_arms", pos)
	clock.advance(20)
	var h2: int = pool.play(&"snd.weapon.small_arms", pos)
	t.check(h1 != 0, "first plays")
	t.eq(h2, 0, "20 ms later is throttled (min 35 ms)")
	t.eq(pool.stats.get_count(&"cull_interval"), 1, "counter")
	clock.advance(40)
	t.check(pool.play(&"snd.weapon.small_arms", pos) != 0, "60 ms after the first plays")


func test_handles(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var pool: SndVoicePool = _pool(clock, 48)
	pool.set_listener(Vector3.ZERO, 1.0)
	var pos: Vector3 = Vector3(15, 1.5, 0)
	var h: int = pool.play(&"snd.explosion.medium", pos)
	t.check(h != 0, "started")
	t.check(pool.is_active(h), "active")
	pool.stop(h, 0)
	t.check(not pool.is_active(h), "stopped")
	clock.advance(500)
	var h2: int = pool.play(&"snd.explosion.medium", pos)
	t.check(h2 != h, "a reused slot gets a new generation")
	t.check(not pool.is_active(h), "the old handle stays dead")
	t.eq(h & 127, h2 & 127, "same slot index")


func test_reserve_keeps_slots_for_big_sounds(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var pool: SndVoicePool = _pool(clock, 48)
	pool.set_listener(Vector3.ZERO, 1.0)
	var map: SndEventMap = SndTestKit.real()["map"]
	# a group-free priority-28 fixture event with a huge instance limit
	var filler: SndEventDef = map.get_def(&"snd.impact.bullet.dirt")
	var saved_max: int = filler.max_instances
	var saved_group: StringName = filler.group
	var saved_int: int = filler.min_interval_ms
	filler.max_instances = 1000
	filler.group = &""
	filler.min_interval_ms = 0
	filler.priority = 28
	for i: int in 42:
		var pos: Vector3 = Vector3(5.0 + float(i) * 0.1, 1.5, 0)
		t.check(pool.play_def(filler, pos, &"", 0.0) != 0, "filler %d" % i)
	t.eq(pool.active_3d(), 42, "42 busy, 6 free")
	var before: int = pool.active_3d()
	var h: int = pool.play_def(filler, Vector3(400, 1.5, 0), &"", 0.0)
	t.eq(h, 0, "a far priority-28 start is not admitted by a free slot (reserve) and cannot steal")
	t.eq(pool.active_3d(), before, "count unchanged")
	var huge: SndEventDef = map.get_def(&"snd.explosion.huge")
	var saved_huge: int = huge.min_interval_ms
	huge.min_interval_ms = 0
	t.check(pool.play_def(huge, Vector3(40, 1.5, 0), &"", 0.0) != 0, "explosion.huge takes a free reserve slot")
	huge.min_interval_ms = saved_huge
	filler.max_instances = saved_max
	filler.group = saved_group
	filler.min_interval_ms = saved_int
	filler.active_count = 0


func test_steal_by_priority(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var pool: SndVoicePool = _pool(clock, 3)
	pool.set_listener(Vector3.ZERO, 1.0)
	var mixc: SndMixConfig = (SndTestKit.real()["store"] as SndDataStore).mix
	var saved_reserve: int = mixc.reserve_high_slots
	mixc.reserve_high_slots = 0
	var map: SndEventMap = SndTestKit.real()["map"]
	var low: SndEventDef = map.get_def(&"snd.impact.bullet.dirt")
	var saved: Array = [low.max_instances, low.group, low.min_interval_ms]
	low.max_instances = 100
	low.group = &""
	low.min_interval_ms = 0
	for i: int in 3:
		pool.play_def(low, Vector3(30 + i, 1.5, 0), &"", 0.0)
	t.eq(pool.active_3d(), 3, "pool full")
	var big: SndEventDef = map.get_def(&"snd.explosion.large")
	big.min_interval_ms = 0
	t.check(pool.play_def(big, Vector3(40, 1.5, 0), &"", 0.0) != 0, "a big boom steals from a low band voice")
	t.eq(pool.active_3d(), 3, "still 3 voices")
	t.check(pool.stats.get_count(&"stolen") >= 1, "stolen counted")
	mixc.reserve_high_slots = saved_reserve
	low.max_instances = saved[0]
	low.group = saved[1]
	low.min_interval_ms = saved[2]
	low.active_count = 0
	big.active_count = 0


func test_loop_ramp(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var pool: SndVoicePool = _pool(clock)
	pool.set_listener(Vector3.ZERO, 1.0)
	var def: SndEventDef = (SndTestKit.real()["map"] as SndEventMap).get_def(&"snd.loop.engine.tracked")
	var h: int = pool.play_def(def, Vector3(10, 1.5, 0), &"", 0.0)
	t.check(h != 0, "loop started")
	var slot: SndVoicePool.Slot = pool._slots[h & 127]
	t.near(slot.ramp_from_db, SndConfig.LOOP_START_DB, 0.001, "starts at -60 dB")
	var steps: int = 0
	while slot.ramp_dur_ms > 0.0 and steps < 100:
		pool.update(1.0 / 60.0)
		steps += 1
	t.near(slot.vol_db, def.volume_db, 0.05, "reaches the event volume")
	t.le(absf(float(steps) - float(def.fade_in_ms) / 1000.0 * 60.0), 3.0, "fade-in takes fade_in_ms +- a few frames (%d frames)" % steps)
	pool.stop(h)
	for i: int in 60:
		pool.update(1.0 / 60.0)
	t.check(not pool.is_active(h), "stopped after the fade-out")


func test_fuzz(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var pool: SndVoicePool = _pool(clock, 48)
	pool.set_listener(Vector3.ZERO, 1.0)
	var map: SndEventMap = SndTestKit.real()["map"]
	var ids: Array[StringName] = []
	for id: StringName in map.event_ids():
		var d: SndEventDef = map.get_def(id)
		if not d.loop:
			ids.append(id)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var start_us: int = Time.get_ticks_usec()
	var bad: int = 0
	for i: int in 20000:
		var id: StringName = ids[rng.randi() % ids.size()]
		var pos: Vector3 = Vector3(rng.randf_range(-300, 300), 1.5, rng.randf_range(-300, 300))
		pool.play(id, pos, &"", 0.0)
		clock.advance(rng.randi_range(0, 15))
		if i % 8 == 0:
			pool.update(0.016)
		var d2: SndEventDef = map.get_def(id)
		if d2.active_count > d2.max_instances or pool.group_count(d2.group) > map.group_limit(d2.group) or pool.active_3d() > 48:
			bad += 1
	t.eq(bad, 0, "limits held at every step")
	var ms: float = float(Time.get_ticks_usec() - start_us) / 1000.0
	t.lt(ms, 3000.0, "20000 plays in %.0f ms" % ms)
	t.note("fuzz %.0f ms, starts %d, counters %s" % [ms, pool.stats.starts, str(pool.stats.counters)])


func test_real_players_start(t: TestCtx) -> void:
	t.set_timeout(20.0)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var r: Dictionary = SndTestKit.real()
	SndTestKit.reset_defs(r["map"])
	var pool: SndVoicePool = SndVoicePool.new()
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(pool)
	var container: Node3D = Node3D.new()
	root.add_child(container)
	pool.setup(r["map"], (r["store"] as SndDataStore).mix, 3, Callable(clock, "now"))
	pool.attach_3d(container, 8)
	pool.set_listener(Vector3.ZERO, 1.0)
	var h: int = pool.play(&"snd.weapon.small_arms", Vector3(20, 1.5, 0), &"napc")
	var h2: int = pool.play(&"snd.ui.click")
	t.check(h != 0 and h2 != 0, "3D and 2D voices started")
	t.eq(pool.active_3d(), 1, "one positional voice")
	t.eq(pool.active_2d(), 1, "one flat voice")
	pool.detach_3d()
	pool.queue_free()
	container.queue_free()
