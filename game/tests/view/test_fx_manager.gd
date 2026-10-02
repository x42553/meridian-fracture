extends RefCounted
## VIEW-F1 acceptance: buckets, admission (cull with the focus-distance fix), rings, cancel, tracker, quality, pause, caps.

const Kit := preload("res://tests/view/fx_kit.gd")


func _kit(q: FxManager.Quality = FxManager.Quality.HIGH, focus: float = 60.0) -> Kit:
	return Kit.make(q, focus) as Kit


func test_tiny_bucket_burst_and_refill(t: TestCtx) -> void:
	var k: Kit = _kit()
	var p: Vector3 = k.on_axis(60.0)
	var ok: int = 0
	for i: int in 100:
		if k.fx.spawn(&"hit_infantry", p, Vector3.ZERO, 1.0) > 0:
			ok += 1
	t.eq(ok, 60, "100 immediate TINY spawns = 60 accepted (burst)")
	t.gt(k.fx.get_stats()["rate_dropped"] as int, 39, "the rest are rate dropped")
	k.fx.advance(0.1)
	ok = 0
	for i: int in 100:
		if k.fx.spawn(&"hit_infantry", p, Vector3.ZERO, 1.0) > 0:
			ok += 1
	t.eq(ok, 50, "after advance(0.1) 50 more (500 per s)")
	k.free_all()


func test_distance_rule_uses_camera_focus_distance(t: TestCtx) -> void:
	var k: Kit = _kit(FxManager.Quality.HIGH, 96.0)
	t.gt(k.fx.spawn(&"hit_infantry", k.on_axis(150.0)), 0, "TINY at 150 m accepted (limit 70 + 96 = 166)")
	t.eq(k.fx.spawn(&"hit_infantry", k.on_axis(200.0)), -1, "TINY at 200 m rejected")
	t.gt(k.fx.spawn(&"expl_small", k.on_axis(290.0)), 0, "MEDIUM at 290 m accepted (limit 200 + 96 = 296)")
	t.eq(k.fx.spawn(&"expl_small", k.on_axis(310.0)), -1, "MEDIUM at 310 m rejected")
	t.gt(k.fx.get_stats()["culled"] as int, 1, "culls counted")
	k.free_all()


func test_behind_camera_and_frustum(t: TestCtx) -> void:
	var k: Kit = _kit()
	var behind: Vector3 = k.cam.transform.origin + k.cam.transform.basis.z * 30.0
	t.eq(k.fx.spawn(&"hit_infantry", behind), -1, "behind the camera rejected")
	t.gt(k.fx.spawn(&"expl_large", k.cam.transform.origin + k.cam.transform.basis.z * 3.0), 0, "behind but closer than the radius accepted")
	var right: Vector3 = k.cam.transform.basis.x
	t.eq(k.fx.spawn(&"hit_infantry", k.on_axis(60.0) + right * 400.0), -1, "far outside the frustum rejected")
	t.gt(k.fx.spawn(&"hit_infantry", k.on_axis(60.0) + right * 10.0), 0, "inside the frustum accepted")
	k.free_all()


func test_force_bypasses_budgets(t: TestCtx) -> void:
	var k: Kit = _kit()
	var far: Vector3 = k.on_axis(900.0)
	t.eq(k.fx.spawn(&"hit_infantry", far), -1, "far effect culled")
	k.fx.force = true
	for i: int in 200:
		t.check(k.fx.spawn(&"hit_infantry", far) > 0 or i > 0, "force spawns")
	t.gt(k.fx.get_stats()["spawned"] as int, 199, "200 forced spawns despite bucket and distance")
	k.free_all()


func test_unknown_effect_returns_minus_one(t: TestCtx) -> void:
	var k: Kit = _kit()
	t.eq(k.fx.spawn(&"no_such_effect", k.on_axis(40.0)), -1, "unknown id")
	t.eq(k.fx.get_stats()["unknown"] as int, 1, "counted")
	k.free_all()


func test_ring_overwrite_counter(t: TestCtx) -> void:
	var k: Kit = _kit()
	var b: FxBatch = k.fx.batch(&"flash")
	t.eq(b.capacity, 256, "flash cap 256")
	for i: int in b.capacity + 5:
		k.fx.sprites(&"flash", Vector3.ZERO, 1.0, 1.0)
	t.eq(b.overwritten, 5, "capacity + 5 emits overwrite 5 live instances")
	t.eq(b.active_count(k.fx.now()), 256, "never more than the cap alive")
	k.free_all()


func test_caps_match_spec_inventory(t: TestCtx) -> void:
	var k: Kit = _kit()
	t.eq(k.fx.batch_names().size(), 34, "34 batches incl. wake")
	var total: int = 0
	for n: StringName in k.fx.batch_names():
		var b: FxBatch = k.fx.batch(n)
		total += b.capacity
		t.eq(b.capacity, int((FxManager.BATCHES[n] as Array)[1]), "%s cap" % n)
	t.gt(total, 5000, "about 5.7k instance slots")
	t.lt(total, 6500, "about 5.7k instance slots")
	k.free_all()


func test_cancel_empties_super_effect(t: TestCtx) -> void:
	var k: Kit = _kit()
	var h: int = k.fx.spawn(&"sw_warning_marker", k.on_axis(60.0), Vector3(8.0, 0.0, 0.0), 12.0)
	t.gt(h, 0, "super effect spawns")
	t.eq(k.fx.batch(&"marker").active_count(k.fx.now()), 1, "marker alive")
	t.eq(k.fx.batch(&"beacon").active_count(k.fx.now()), 1, "beacon alive")
	k.fx.cancel(h)
	t.eq(k.fx.batch(&"marker").active_count(k.fx.now()), 0, "marker cancelled")
	t.eq(k.fx.batch(&"beacon").active_count(k.fx.now()), 0, "beacon cancelled")
	# a scheduled sub-effect of a cancelled composite never fires
	var h2: int = k.fx.spawn(&"sw_orbital_strike", k.on_axis(60.0), Vector3.ZERO, 1.0)
	t.gt(k.fx.pending_scheduled(), 0, "rods 2 and 3 are scheduled")
	k.fx.cancel(h2)
	t.eq(k.fx.pending_scheduled(), 0, "cancel drops the group's scheduled work")
	k.free_all()


func test_cancel_does_not_kill_a_reused_slot(t: TestCtx) -> void:
	var k: Kit = _kit()
	var h: int = k.fx.spawn(&"sw_warning_marker", k.on_axis(60.0), Vector3(8.0, 0.0, 0.0), 12.0)
	var b: FxBatch = k.fx.batch(&"marker")
	k.fx.advance(0.5)
	for i: int in b.capacity:
		k.fx.ring(&"marker", Vector3.ZERO, 3.0, 5.0)  # wraps the ring: slot 0 now holds a newer instance
	var alive: int = b.active_count(k.fx.now())
	k.fx.cancel(h)
	t.eq(b.active_count(k.fx.now()), alive, "cancel leaves the overwriting instances alone")
	k.free_all()


func test_schedule_fires_at_time(t: TestCtx) -> void:
	var k: Kit = _kit()
	k.fx.schedule(0.5, &"hit_infantry", k.on_axis(60.0), Vector3.ZERO, 1.0)
	t.eq(k.fx.pending_scheduled(), 1, "queued")
	k.fx.advance(0.3)
	t.eq(k.fx.pending_scheduled(), 1, "not yet at 0.3 s")
	k.fx.advance(0.25)
	t.eq(k.fx.pending_scheduled(), 0, "fired once now >= 0.5")
	t.gt(k.fx.live_instances(), 0, "the sub-effect produced instances")
	k.free_all()


func test_scheduled_effect_is_re_culled(t: TestCtx) -> void:
	var k: Kit = _kit()
	k.fx.schedule(0.1, &"hit_infantry", k.on_axis(900.0), Vector3.ZERO, 1.0)
	k.fx.advance(0.2)
	t.eq(k.fx.live_instances(), 0, "a delayed sub-effect far away is culled when it fires")
	k.free_all()


func test_tracker_calls_callables_each_interval(t: TestCtx) -> void:
	var k: Kit = _kit()
	var from_n: Array[int] = [0]
	var to_n: Array[int] = [0]
	var a: Vector3 = k.on_axis(50.0)
	var h: int = k.fx.start_tracker(&"beam_tick",
		func() -> Vector3:
			from_n[0] += 1
			return a,
		func() -> Vector3:
			to_n[0] += 1
			return a + Vector3(10.0, 0.0, 0.0),
		0.1, 1.0)
	t.gt(h, 0, "tracker admitted")
	var calls_at_start: int = from_n[0]
	for i: int in 10:
		k.fx.advance(0.1)
	var emitted: int = from_n[0] - calls_at_start
	t.check(emitted >= 9 and emitted <= 11, "callables evaluated once per 0.1 s interval (%d)" % emitted)
	t.eq(from_n[0], to_n[0], "both endpoints re-evaluated together")
	k.fx.advance(0.05)
	t.eq(k.fx.emitter_count(), 0, "tracker ended after its duration")
	k.free_all()


func test_tracker_cap_and_bucket_bypass(t: TestCtx) -> void:
	var k: Kit = _kit()
	var a: Vector3 = k.on_axis(50.0)
	var n: int = 0
	for i: int in 30:
		if k.fx.start_tracker(&"beam_tick", func() -> Vector3: return a, func() -> Vector3: return a + Vector3(5, 0, 0), 0.07, 5.0) > 0:
			n += 1
	t.eq(n, 24, "at most 24 live trackers (BEAM burst 24 admits exactly that many)")
	var before: float = k.fx.bucket_tokens(FxManager.Cls.BEAM)
	for i: int in 10:
		k.fx.advance(0.07)
	t.check(k.fx.bucket_tokens(FxManager.Cls.BEAM) >= before, "tracker segments do not draw from the BEAM bucket")
	t.gt(k.fx.live_instances(), 0, "segments were drawn")
	k.free_all()


func test_quality_low_thins_and_drops_lights(t: TestCtx) -> void:
	var k: Kit = _kit(FxManager.Quality.LOW)
	t.near(k.fx.lod(), 0.45, 1.0e-6, "LOW fx_lod 0.45")
	k.fx.light_flash(Vector3.ZERO, Color.WHITE, 3.0, 10.0, 1.0)
	t.eq(k.fx.live_lights(), 0, "no lights on LOW")
	k.fx.set_quality(FxManager.Quality.HIGH)
	k.fx.light_flash(Vector3.ZERO, Color.WHITE, 3.0, 10.0, 1.0)
	t.eq(k.fx.live_lights(), 1, "lights on HIGH")
	t.near(k.fx.lod(), 1.0, 1.0e-6, "HIGH fx_lod 1")
	for i: int in 10:
		k.fx.light_flash(Vector3.ZERO, Color.WHITE, 3.0, 10.0, 1.0)
	t.eq(k.fx.live_lights(), 6, "at most 6 lights")
	k.free_all()


func test_distort_off_drops_refraction_layers(t: TestCtx) -> void:
	var k: Kit = _kit(FxManager.Quality.MEDIUM)
	k.fx.force = true
	k.fx.spawn(&"expl_medium", k.on_axis(60.0))
	t.eq(k.fx.batch(&"ring_distort").active_count(k.fx.now()), 0, "no refraction ring on MEDIUM")
	t.gt(k.fx.batch(&"ring_add").active_count(k.fx.now()), 0, "additive ring stays")
	k.fx.set_distort(true)
	k.fx.spawn(&"expl_medium", k.on_axis(60.0))
	t.eq(k.fx.batch(&"ring_distort").active_count(k.fx.now()), 1, "fx_distort override re-enables it")
	k.free_all()


func test_pause_freezes_the_clock(t: TestCtx) -> void:
	var k: Kit = _kit()
	k.fx.advance(1.0)
	t.near(k.fx.now(), 1.0, 1.0e-6, "clock advanced")
	k.fx.paused = true
	k.fx.advance(5.0)
	t.near(k.fx.now(), 1.0, 1.0e-6, "paused: clock frozen")
	k.fx.paused = false
	k.fx.time_scale = 0.5
	k.fx.advance(1.0)
	t.near(k.fx.now(), 1.5, 1.0e-6, "time_scale 0.5")
	k.free_all()


func test_every_effect_spawns_something(t: TestCtx) -> void:
	var k: Kit = _kit()
	k.fx.force = true
	var p: Vector3 = k.on_axis(60.0)
	for id: StringName in k.book.ids():
		k.fx.clear_all()
		var d: FxRecipeBook.FxDef = k.book.def(id)
		var h: int = 0
		var n: int = 0
		# some layers are chance-gated (`when: rand() < 0.7`; oil_fire_tick both: 15 % of single spawns are legitimately empty), so retry
		for attempt: int in 12:
			h = k.fx.spawn(id, p, p + Vector3(8.0, 0.0, -4.0), d.nominal_scale)
			n = k.fx.live_instances() + k.fx.live_lights() + k.fx.emitter_count() + k.fx.pending_scheduled()
			if h > 0 and n > 0:
				break
		t.check(h > 0 and n > 0, "%s spawns (%d live)" % [id, n])
	k.free_all()


func test_shake_falls_off_with_distance(t: TestCtx) -> void:
	var k: Kit = _kit()
	var got: Array[float] = []
	k.fx.camera_shake.connect(func(amount: float, _pos: Vector3) -> void: got.append(amount))
	k.fx.shake(1.0, k.cam.transform.origin)
	k.fx.shake(1.0, k.cam.transform.origin + Vector3(70.0, 0.0, 0.0))
	k.fx.shake(1.0, k.cam.transform.origin + Vector3(200.0, 0.0, 0.0))
	t.eq(got.size(), 2, "beyond 140 m no shake")
	t.near(got[0], 1.0, 1.0e-4, "full strength at the camera")
	t.near(got[1], 0.5, 1.0e-4, "half at 70 m")
	k.free_all()


func test_stamper_caps_at_eight_per_frame(t: TestCtx) -> void:
	var k: Kit = _kit()
	k.fx.force = true
	var n: Node3D = Node3D.new()
	n.position = k.on_axis(50.0)
	var h: int = k.fx.start_stamper(&"vehicle_dust", n, 1.0, 10.0)
	t.gt(h, 0, "stamper handle")
	k.fx.reset_stats()
	n.position += Vector3(0.0, 0.0, 100.0)
	k.fx.advance(0.016)
	t.eq(k.fx.get_stats()["spawned"] as int, 8, "100 m in one frame stamps at most 8")
	k.fx.stop_emitter(h)
	k.fx.advance(0.016)
	t.eq(k.fx.emitter_count(), 0, "stopped emitter removed")
	n.free()
	k.free_all()


func test_hidden_batches_drop_layers(t: TestCtx) -> void:
	var k: Kit = _kit()
	k.fx.force = true
	k.fx.hidden_batches[&"fire"] = true
	k.fx.spawn(&"expl_small", k.on_axis(60.0))
	t.eq(k.fx.batch(&"fire").active_count(k.fx.now()), 0, "hidden batch receives nothing")
	t.gt(k.fx.batch(&"smoke").active_count(k.fx.now()), 0, "other layers still spawn")
	k.free_all()


func test_batch_hides_when_idle(t: TestCtx) -> void:
	var k: Kit = _kit()
	k.fx.sprites(&"flash", Vector3.ZERO, 1.0, 0.2)
	k.fx.advance(0.01)
	t.check(k.fx.batch(&"flash").node.visible, "shown while alive")
	k.fx.advance(0.5)
	t.check(not k.fx.batch(&"flash").node.visible, "hidden once nothing is alive")
	k.free_all()
