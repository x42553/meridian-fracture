extends RefCounted
## VIEW-W1 scenarios on a real SimWorld (real movement / orders / combat): the entity mirror incl. interpolation and the
## catch-up case, reconcile repair, visibility gating, squads, deaths, and the script-cost bench (400 entities).

const Kit := preload("res://tests/view/vw_kit.gd")
const C: int = SimConfig.CELL


## Fog stand-in: entities of `hidden` ids are invisible to everybody, `version` bumps when the set changes.
class FogStub:
	extends SimFogApi
	var hidden: Dictionary = {}
	var version: int = 1

	func entity_visible(_pid: int, e: SimEntity) -> bool:
		return not hidden.has(e.id)

	func fog_version(_pid: int) -> int:
		return version


func _army(w: SimWorld, n_tanks: int, n_rifles: int, x0: int, y0: int, owner: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in n_tanks:
		ids.append(Kit.tank(w, owner, x0 + (i % 10) * 3, y0 + (i / 10) * 3).id)
	for i: int in n_rifles:
		ids.append(Kit.rifle(w, owner, x0 + (i % 10) * 3 + 1, y0 + 20 + (i / 10) * 3).id)
	return ids


func test_mirror_follows_the_sim(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var a: PackedInt32Array = _army(w, 30, 20, 10, 10, 0)
	var b: PackedInt32Array = _army(w, 30, 20, 50, 10, 1)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(30.0, 30.0), 0.9)
	w.submit_raw(0, SimCmd.move(a, 40 * C, 30 * C))
	w.submit_raw(1, SimCmd.move(b, 20 * C, 30 * C))
	var worst: float = 0.0
	var checked: int = 0
	for f: int in 200:
		w.step()
		var alpha: float = 0.5
		vw.frame(1.0 / 60.0, alpha, w.events.take())
		if f % 20 == 19:
			for e: SimEntity in w.entities:
				var ve: ViewEntity = vw.entity_view(e.id)
				if ve == null:
					t.check(false, "entity %d has a record" % e.id)
					return
				if ve.kind == SimEntity.Kind.UNIT and ve.vs != ViewConsts.VS_HIDDEN and ve.in_view:
					checked += 1
					# after the first update the world position equals lerp(prev, cur, alpha)
					var ex: float = (float(ve.x_prev) + float(ve.x_cur - ve.x_prev) * alpha) * ViewConsts.M_PER_UNIT
					worst = maxf(worst, absf(ex - ve.wx))
	t.gt(checked, 20, "in-view entities were compared")
	t.check(worst < 1.0e-4, "interpolated positions equal lerp(prev, cur, alpha) (worst %.6f)" % worst)
	var moved: int = 0
	for id: int in a:
		var e2: SimEntity = w.get_entity(id)
		if e2 != null and e2.x > 12 * C:
			moved += 1
	t.gt(moved, 10, "the armies actually moved")
	t.eq(vw.entity_count(), w.entities.size(), "one record per live entity")
	Kit.free_view(vw)


func test_removed_entities_disappear_and_reconcile_repairs(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	var e1: SimEntity = Kit.tank(w, 0, 20, 20)
	var e2: SimEntity = Kit.tank(w, 0, 24, 20)
	# a frame whose batch is dropped: the SPAWNED events never reach the router
	w.step()
	w.events.take()
	vw.frame(1.0 / 60.0, 0.5, PackedInt32Array())
	t.check(not vw.has_entity(e1.id) and not vw.has_entity(e2.id), "missed SPAWNED: no record yet")
	vw.reconcile()
	t.check(vw.has_entity(e1.id) and vw.has_entity(e2.id), "reconcile repairs the missed spawns")
	# silent removal (SCRIPT) is followed by the 8-tick window, then the record is gone
	w.remove_entity(e1.id, SimEvent.REM_SCRIPT)
	Kit.step_frame(vw, 1)
	t.check(vw.entity_view(e1.id) != null and vw.entity_view(e1.id).dying_kind == ViewConsts.DK_SILENT, "silent removal starts a window")
	Kit.step_frame(vw, 9)
	t.check(not vw.has_entity(e1.id), "record disposed after the window")
	# a removal whose event was dropped is found by reconcile
	w.remove_entity(e2.id, SimEvent.REM_SCRIPT)
	w.step()
	w.events.take()
	vw.reconcile()
	t.check(vw.entity_view(e2.id) == null or vw.entity_view(e2.id).sim_gone, "reconcile marks a vanished entity gone")
	Kit.free_view(vw)


func test_catch_up_never_moves_backwards(t: TestCtx) -> void:
	for exact: bool in [false, true]:
		var w: SimWorld = Kit.sim()
		var ids: PackedInt32Array = _army(w, 6, 0, 10, 40, 0)
		var vw: ViewWorld = Kit.view(w)
		w.submit_raw(0, SimCmd.move(ids, 80 * C, 42 * C))
		for i: int in 20:
			Kit.step_frame(vw, 1, 0.3)
		var probe: ViewEntity = vw.entity_view(ids[0])
		var last_x: float = probe.wx
		var backwards: int = 0
		# one frame that ran three ticks, then ten normal frames
		if exact:
			for k: int in 3:
				vw.capture_prev(w)
				w.step()
		else:
			w.run(3)
		vw.frame(1.0 / 60.0, 0.05, w.events.take())
		if exact:
			t.eq(probe.x_prev, w.get_entity(ids[0]).prev_x, "exact mode: prev is the state before the last step")
		else:
			t.gt(probe.x_cur - probe.x_prev, 0, "frame-granular mode: a multi-tick span")
		if probe.wx < last_x - 1.0e-4:
			backwards += 1
		last_x = probe.wx
		for f: int in 10:
			var a2: float = float(f % 3) / 3.0
			if f % 3 == 0:
				w.step()
			vw.frame(1.0 / 60.0, a2, w.events.take())
			if probe.wx < last_x - 1.0e-4:
				backwards += 1
			last_x = probe.wx
		t.eq(backwards, 0, "no backwards step after a catch-up frame (exact=%s)" % exact)
		Kit.free_view(vw)


func test_visibility_gating(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var fog: FogStub = FogStub.new()
	w.fog = fog
	var mine: SimEntity = Kit.tank(w, 0, 30, 30)
	var enemy: SimEntity = Kit.tank(w, 1, 34, 30)
	var vw: ViewWorld = Kit.view(w, 0)
	Kit.frame(vw)
	t.eq(vw.entity_view(enemy.id).vs, ViewConsts.VS_VISIBLE, "visible enemy")
	fog.hidden[enemy.id] = true
	fog.version += 1
	Kit.frame(vw)
	t.eq(vw.entity_view(enemy.id).vs, ViewConsts.VS_HIDDEN, "enemy leaves vision: hidden the frame the fog changes")
	t.check(not (vw.entity_view(enemy.id).rig.visible), "the rig is hidden")
	t.eq(vw.entity_view(mine.id).vs, ViewConsts.VS_VISIBLE, "own units stay visible")
	fog.hidden.erase(enemy.id)
	fog.version += 1
	Kit.frame(vw)
	t.eq(vw.entity_view(enemy.id).vs, ViewConsts.VS_VISIBLE, "reveal is instantaneous")
	# a unit inside a container is hidden regardless of fog
	enemy.flags |= SimFlags.F_INSIDE
	vw.entity_view(enemy.id).sim_flags = enemy.flags
	vw.entity_view(enemy.id).vis_ver = -5
	Kit.frame(vw)
	t.eq(vw.entity_view(enemy.id).vs, ViewConsts.VS_HIDDEN, "F_INSIDE hides")
	# observer sees everything
	vw.set_local_player(-1, true)
	fog.hidden[mine.id] = true
	Kit.frame(vw)
	t.eq(vw.entity_view(mine.id).vs, ViewConsts.VS_VISIBLE, "observer")
	Kit.free_view(vw)


func test_squad_damage_channel_and_members(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var r: SimEntity = Kit.rifle(w, 0, 30, 30)
	var vw: ViewWorld = Kit.view(w)
	var ve: ViewEntity = vw.entity_view(r.id)
	t.eq(ve.members, 4, "the proof squad has 4 members")
	for pair: Array in [[0.74, 0.26], [0.49, 0.51], [0.24, 0.76], [1.0, 0.0]]:
		r.hp = int(float(r.hp_max) * (pair[0] as float))
		Kit.step_frame(vw, 1)
		var got: float = ve.damage
		# u_state.x = 1 - hp fraction: the shader hides member i while (1 - x) <= i / count
		t.near(got, pair[1] as float, 0.01, "hp %.2f -> damage %.2f" % [pair[0] as float, pair[1] as float])
	Kit.free_view(vw)


func test_combat_deaths_leave_wreck_and_window(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var killer: SimEntity = Kit.tank(w, 0, 30, 30)
	var victim: SimEntity = Kit.tank(w, 1, 33, 30)
	victim.paid_cost = 850
	var vw: ViewWorld = Kit.view(w)
	Kit.frame(vw)
	w.kill(victim, SimWorld.Cause.DAMAGE, killer.id, 0)
	var wk: SimEntity = w.spawn_wreck(victim, true, 50, 1200)
	t.not_null(wk, "wreck spawned")
	w.step()
	var batch: PackedInt32Array = w.events.take()
	vw.frame(1.0 / 60.0, 0.5, batch)
	var ve: ViewEntity = vw.entity_view(victim.id)
	t.check(ve != null and ve.dead, "DIED starts the dying window (record kept)")
	var wrecks: int = 0
	var wv: ViewEntity = vw.entity_view(wk.id) if wk != null else null
	if wv != null and (wv.flags & ViewConsts.UF_WRECK) != 0:
		wrecks += 1
	t.gt(wrecks, 0, "a wreck record with UF_WRECK exists")
	for i: int in 6:
		Kit.step_frame(vw, 1)
	t.check(not vw.has_entity(victim.id), "the dying record is disposed after its window")
	Kit.free_view(vw)


func test_script_cost_400_entities(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var a: PackedInt32Array = _army(w, 100, 100, 6, 6, 0)
	var b: PackedInt32Array = _army(w, 100, 100, 6, 40, 1)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(30.0, 30.0), 0.9)
	w.submit_raw(0, SimCmd.move(a, 70 * C, 35 * C))
	w.submit_raw(1, SimCmd.move(b, 70 * C, 55 * C))
	for i: int in 30:
		Kit.step_frame(vw, 1 if i % 3 == 0 else 0)
	var total: float = 0.0
	var worst: float = 0.0
	var n: int = 120
	var samples: PackedFloat32Array = PackedFloat32Array()
	for f: int in n:
		if f % 3 == 0:
			w.step()
		var ev: PackedInt32Array = w.events.take()
		vw.frame(1.0 / 60.0, float(f % 3) / 3.0, ev)
		var ms: float = (vw.stats()["ms"] as Dictionary)["total"] as float
		total += ms
		worst = maxf(worst, ms)
		samples.append(ms)
	var avg: float = total / float(n)
	samples.sort()
	var median: float = samples[n / 2]
	t.note("script cost, %d entities (%d visible): avg %.3f ms, median %.3f ms, worst %.3f ms" % [vw.entity_count(), vw.stats()["visible"] as int, avg, median, worst])
	t.lt(median, 3.0 * TestCtx.perf_factor(), "median script cost per frame stays small (target 2 ms on the reference machine; the median keeps a loaded CI box from flaking)")
	Kit.free_view(vw)


func test_build_async_builds_terrain_camera_and_mirrors(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	Kit.tank(w, 0, 30, 30)
	Kit.rifle(w, 1, 60, 60)
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.LOW)
	var vw: ViewWorld = ViewWorld.create(q)
	var stages: Array[String] = []
	vw.build_progress.connect(func(_f: float, s: String) -> void: stages.append(s))
	var opts: ViewBuildOptions = ViewBuildOptions.new()
	opts.screenshot_mode = true
	opts.prewarm_scope = 1
	(Engine.get_main_loop() as SceneTree).root.add_child(vw)
	await vw.build_async(w, 0, opts)
	t.check(vw.terrain != null and vw.camera != null, "terrain and camera were created")
	t.eq(stages[stages.size() - 1], "done", "progress ends with done")
	t.eq(vw.entity_count(), w.by_id.size() - w.by_id.count(null), "every existing entity is mirrored after the build")
	t.eq(vw.models.pending(), 0, "the prewarm builds finished")
	t.check(vw.camera.height_func.is_valid(), "the camera follows the terrain")
	vw.teardown()
	vw.queue_free()
