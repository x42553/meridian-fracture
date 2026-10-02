extends SceneTree
## Event map + voice pool invariants. Run: Godot --headless --path prototypes/audio --script res://tests/t_events.gd

var fails: int = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL  ", msg)


func _initialize() -> void:
	_run()


## Nodes added to `root` inside _initialize() are NOT in the tree yet (play()/global_position fail): wait one frame.
func _run() -> void:
	await process_frame
	SndBus.setup()
	var map: SndEventMap = SndEventMap.new()
	var t0: int = Time.get_ticks_usec()
	var ok: bool = map.load_file("res://data/audio_events.json")
	print("MAP      loaded %d events in %.1f ms, errors=%d %s" % [map.event_ids().size(), float(Time.get_ticks_usec() - t0) / 1000.0, map.errors.size(), str(map.errors.slice(0, 3))])
	check(ok, "event map must load without errors")
	check(map.get_def(&"voice.base_under_attack", &"napc") != map.get_def(&"voice.base_under_attack"), "per-faction override resolves to a different def")
	check(map.get_def(&"voice.unit_lost", &"napc") == map.get_def(&"voice.unit_lost"), "missing override falls back to default")
	check(map.resolve(&"weapon_fire", {"snd": "cannon_heavy"}) == &"weapon.cannon_heavy.fire", "sim_map pattern")
	check(map.resolve(&"weapon_fire", {"snd": "nonexistent"}) == &"weapon.rifle.fire", "sim_map fallback")
	# validation catches typos
	var bad: SndEventMap = SndEventMap.new()
	var f: FileAccess = FileAccess.open("user://bad_events.json", FileAccess.WRITE)
	f.store_string('{"version":1,"events":{"x.y":{"prioritee":5,"variants":[{"stream":"res://nope.ogg"}]}}}')
	f.close()
	check(not bad.load_file("user://bad_events.json") and bad.errors.size() >= 2, "validation reports unknown key + missing stream: %s" % str(bad.errors))

	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var pool: SndVoicePool = SndVoicePool.new()
	root.add_child(pool)
	pool.setup(map, 48, 16, 11)
	pool.listener_pos = Vector3.ZERO

	# --- distance cull + audibility cull
	check(pool.play(&"weapon.rifle.fire", Vector3(500, 0, 0)) == SndVoicePool.INVALID and pool.stats["cull_distance"] == 1, "beyond max_distance is culled")
	var h: int = pool.play(&"weapon.rifle.fire", Vector3(10, 0, 0))
	check(h > 0, "near rifle plays")
	check(pool.play(&"weapon.rifle.fire", Vector3(10, 0, 0)) == SndVoicePool.INVALID and pool.stats["cull_interval"] == 1, "min_interval_ms rate limit")

	# --- attenuation formula sanity (engine-verified curve is in t_capture)
	var d: SndEventDef = map.get_def(&"weapon.cannon_heavy.fire")
	check(is_equal_approx(SndVoicePool.model_db(d, d.unit_size), 0.0), "0 dB at unit_size")
	check(absf(SndVoicePool.model_db(d, d.unit_size * 4.0) + 12.04) < 0.05 and absf(SndVoicePool.attenuation_db(d, d.max_distance * 0.5) - (SndVoicePool.model_db(d, d.max_distance * 0.5) - 6.02)) < 0.05, "-12 dB at 4x unit_size; -6 dB window at half max_distance")

	# --- stealing: fill with cheap loops, then a high-priority explosion must steal; a low-priority newcomer must not
	var pool2: SndVoicePool = SndVoicePool.new()
	root.add_child(pool2)
	pool2.setup(map, 8, 4, 12)
	for i in 20:
		pool2.play(&"unit.engine.tracked", Vector3(5 + i, 0, 3))  # 12 max_instances, priority 15
	var before: int = pool2.stats["stolen"]
	var boom: int = pool2.play(&"impact.explosion_large", Vector3(20, 0, 0))
	check(boom > 0, "high priority event admitted when pool is full")
	check(pool2.stats["stolen"] > before, "a low priority voice was stolen")
	check(pool2.active_voices() <= 12, "active voices bounded by pool size (%d)" % pool2.active_voices())
	var dropped_before: int = pool2.stats["dropped"] + pool2.stats["cull_limit"]
	var lo: int = pool2.play(&"unit.foot.step", Vector3(30, 0, 0))
	check(lo == SndVoicePool.INVALID and pool2.stats["dropped"] + pool2.stats["cull_limit"] > dropped_before, "low priority newcomer does not steal a louder/more important voice")

	# --- randomized stress: invariants must hold after every call
	var ids: Array[StringName] = map.event_ids()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var calls: int = 20000
	var t1: int = Time.get_ticks_usec()
	var viol: int = 0
	for i in calls:
		var id: StringName = ids[rng.randi() % ids.size()]
		pool.play(id, Vector3(rng.randf_range(-300, 300), 0, rng.randf_range(-300, 300)))
		if pool.active_voices() > 64:
			viol += 1
	var dt: float = float(Time.get_ticks_usec() - t1) / 1000.0
	for id in ids:
		var e: SndEventDef = map.get_def(id)
		if e.active_count > e.max_instances:
			viol += 1
	check(viol == 0, "pool invariants violated %d times" % viol)
	print("STRESS   %d play() calls in %.1f ms (%.2f us/call incl. player setup) stats=%s active=%d" % [calls, dt, dt * 1000.0 / calls, JSON.stringify(pool.stats), pool.active_voices()])
	print("T_EVENTS %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
