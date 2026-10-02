extends RefCounted
## VIEW-F4 / W3 acceptance: the FX event router is table driven over the REAL kernel event codes (every SimEvent code is routed or
## consciously ignored), hit / miss inference, explosion dedupe, fog gating, camera shake amounts, the damage-emitter cap of 24,
## the projectile mirror (pool exactness, cap) and the shipped fx.json vocabulary used by the router.

const Kit := preload("res://tests/view/vw_kit.gd")
const C: int = SimConfig.CELL
const U: int = 1024


## World + view + FxManager (force: no culling / rate limits, so counts are exact) + router with the spawn log on.
class Rig:
	extends RefCounted
	var w: SimWorld
	var vw: ViewWorld
	var fx: FxManager
	var book: FxRecipeBook
	var router: FxEventRouter
	var shakes: Array[float] = []

	func free_all() -> void:
		fx.free()
		Kit.free_view(vw)


class FogStub:
	extends SimFogApi
	var visible_rect: Rect2i = Rect2i(0, 0, 0, 0)  # cells
	var hidden: Dictionary = {}

	func cell_visible(_pid: int, cx: int, cy: int) -> bool:
		return visible_rect.has_point(Vector2i(cx, cy))

	func entity_visible(_pid: int, e: SimEntity) -> bool:
		return not hidden.has(e.id)

	func fog_version(_pid: int) -> int:
		return 1


func _rig(q: FxManager.Quality = FxManager.Quality.HIGH) -> Rig:
	var r: Rig = Rig.new()
	r.w = Kit.sim()
	return _finish(r, q)


func _finish(r: Rig, q: FxManager.Quality = FxManager.Quality.HIGH) -> Rig:
	r.vw = Kit.view(r.w, 0, Vector2(30.0, 30.0), 0.5)
	r.book = FxRecipeBook.new()
	r.book.load_file()
	r.fx = FxManager.new()
	r.fx.viewport_size_override = Vector2(1920.0, 1080.0)
	r.fx.camera_focus_dist = 60.0
	r.fx.setup(r.vw.camera.camera, q, r.book, r.vw.terrain, null)
	r.fx.force = true
	r.fx.camera_shake.connect(func(a: float, _p: Vector3) -> void: r.shakes.append(a))
	r.router = FxEventRouter.new()
	r.router.setup(r.vw, r.fx, null)
	r.router.record = true
	return r


func _rec(type: int, tick: int, x: int, y: int, a: int, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0) -> PackedInt32Array:
	return ViewTestEvents.make(type, tick, x, y, a, b, c, d, e, f)


func _batch(recs: Array) -> PackedInt32Array:
	return ViewTestEvents.batch(recs)


func _ids(r: Rig) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for rec: Variant in r.router.spawn_log:
		out.append(String((rec as Array)[0] as StringName))
	return out


# ---------------------------------------------------------------------------------------------- table coverage
## Every event constant of the kernel domains is either routed to a handler or listed in IGNORED (with the same code never in both).
func test_every_sim_event_code_is_routed_or_ignored(t: TestCtx) -> void:
	var r: Rig = _rig()
	t.eq(r.router.validate_codes(), PackedStringArray(), "every constant named by TABLE / IGNORED exists in the kernel")
	var missing: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for cls: String in FxEventRouter.class_names():
		var consts: Dictionary = r.router._constants_of(cls)
		for name_v: Variant in consts.keys():
			var name_: String = name_v as String
			var val: Variant = consts[name_v]
			if not (val is int):
				continue
			var is_event: bool = name_.begins_with("EV_") or name_.begins_with("EVT_")
			if cls == "SimEvent":
				is_event = (val as int) >= 1 and (val as int) <= 99 and not _core_noise(name_)
			if not is_event:
				continue
			var code: int = val as int
			seen[code] = name_
			var routed: bool = r.router.handler_of(code) != FxEventRouter.H_NONE
			var ign: bool = r.router.is_ignored(code)
			if not routed and not ign:
				missing.append("%s.%s (%d)" % [cls, name_, code])
			if routed and ign:
				missing.append("%s.%s (%d) is both routed and ignored" % [cls, name_, code])
	t.eq(missing, PackedStringArray(), "no event code without a decision")
	t.gt(seen.size(), 100, "the sweep found the kernel events (%d codes)" % seen.size())
	r.free_all()


static func _core_noise(n: String) -> bool:
	for pre: String in ["BLOCK_", "OWNER_", "CASH_", "SPAWN_", "REM_", "I_", "STRIDE", "THROTTLE"]:
		if n.begins_with(pre):
			return true
	return false


## The render reaction table (6.2.2) over ViewTestEvents: every real code behind a reaction is decided, and the sample batches run.
func test_reaction_table_over_view_test_events(t: TestCtx) -> void:
	var r: Rig = _rig()
	var checked: int = 0
	for reaction: String in ViewTestEvents.REACTIONS:
		for code: int in ViewTestEvents.codes_of(reaction):
			var decided: bool = r.router.handler_of(code) != FxEventRouter.H_NONE or r.router.is_ignored(code)
			t.check(decided, "%s -> code %d is routed or ignored" % [reaction, code])
			checked += 1
		var batch: PackedInt32Array = ViewTestEvents.for_reaction(reaction, 10)
		if batch.is_empty():
			continue
		r.router.process_batch(batch)
	t.gt(checked, 30, "the table was walked")
	t.eq(r.router.stats["unknown"], 0, "no unknown code in the sample batches")
	r.free_all()


# ---------------------------------------------------------------------------------------------- weapons: hit / miss
func test_hitscan_hit_and_miss_from_the_fire_result(t: TestCtx) -> void:
	var r: Rig = _rig()
	var a: SimEntity = Kit.rifle(r.w, 0, 30, 30)
	var b: SimEntity = Kit.tank(r.w, 1, 36, 30)
	Kit.frame(r.vw)
	var kind_shift: int = SimCombatConsts.PK_HITSCAN << 8
	var hit: PackedInt32Array = _rec(SimCombatConsts.EV_FIRE, 5, a.x, a.y, a.id, 0, kind_shift | (1 << 12), b.id, b.x, b.y)
	r.router.process_batch(hit)
	t.check(r.router.logged(&"muzzle_small_arms") == 1, "muzzle flash")
	t.check(r.router.logged(&"tr_small") == 1, "instant tracer")
	t.check(r.router.logged(&"hit_armor") == 1, "result 1 = hit on a vehicle -> armour spark")
	t.eq(r.router.logged(&"hit_ground_miss"), 0, "no miss spark on a hit")
	r.router.spawn_log.clear()
	var miss: PackedInt32Array = _rec(SimCombatConsts.EV_FIRE, 6, a.x, a.y, a.id, 0, kind_shift | (2 << 12), b.id, b.x + 900, b.y + 500)
	r.router.process_batch(miss)
	t.check(r.router.logged(&"hit_ground_miss") == 1, "result 2 = miss spark beside the target")
	t.eq(r.router.logged(&"hit_armor"), 0, "no armour spark on a miss")
	r.free_all()


## Fallback inference: result 0 (unknown) + an EV_HIT of the same attacker / victim in the batch = hit, none = miss.
func test_hit_miss_inference_from_ev_hit(t: TestCtx) -> void:
	var r: Rig = _rig()
	var a: SimEntity = Kit.rifle(r.w, 0, 30, 30)
	var b: SimEntity = Kit.rifle(r.w, 1, 34, 30)
	Kit.frame(r.vw)
	var fire: PackedInt32Array = _rec(SimCombatConsts.EV_FIRE, 5, a.x, a.y, a.id, 0, 0, b.id, b.x, b.y)
	var dmg: PackedInt32Array = _rec(SimCombatConsts.EV_HIT, 5, b.x, b.y, b.id, 12, a.id, 0, 30, 100)
	r.router.process_batch(_batch([fire, dmg]))
	t.eq(r.router.logged(&"hit_infantry"), 1, "EV_HIT of (a -> b) in the batch: hit on infantry")
	t.eq(r.router.logged(&"hit_ground_miss"), 0, "not a miss")
	r.router.spawn_log.clear()
	r.router.process_batch(fire)
	t.eq(r.router.logged(&"hit_ground_miss"), 1, "no EV_HIT: miss")
	t.eq(r.router.logged(&"hit_infantry"), 0, "no hit")
	r.free_all()


## Explosion size follows the splash: 1-cell -> small, 1.6 cells -> medium, 3 cells -> large; unknown serial falls back to the radius rules.
func test_impact_effect_by_splash(t: TestCtx) -> void:
	var r: Rig = _rig()
	Kit.frame(r.vw)
	var x: int = 30 * C
	var y: int = 30 * C
	r.router.process_batch(_rec(SimCombatConsts.EV_IMPACT, 3, x, y, 0, -1, 0, 1024, 100, 0))
	r.router.process_batch(_rec(SimCombatConsts.EV_IMPACT, 3, x + 4096, y, 0, -1, 0, 1700, 100, 0))
	r.router.process_batch(_rec(SimCombatConsts.EV_IMPACT, 3, x + 8192, y, 0, -1, 0, 3100, 100, 0))
	var ids: PackedStringArray = _ids(r)
	t.eq(ids, PackedStringArray(["expl_small", "expl_medium", "expl_large"]), "splash 3 m / 5 m / 9 m")
	r.free_all()


# ---------------------------------------------------------------------------------------------- deaths and dedupe
func test_death_effects_by_kind_and_size(t: TestCtx) -> void:
	var r: Rig = _rig()
	var tank: SimEntity = Kit.tank(r.w, 1, 30, 30)
	var rifle: SimEntity = Kit.rifle(r.w, 1, 34, 30)
	Kit.frame(r.vw)
	var vd: ViewDef = r.vw.entity_view(tank.id).vdef
	r.router.process_batch(_rec(SimCombatConsts.EV_DEATH, 8, tank.x, tank.y, tank.id, tank.def_idx, ViewConsts.DK_VEHICLE, 0, 0, 0))
	var expect_id: String = "death_vehicle_light" if vd.size_class <= 1 else ("death_vehicle_medium" if vd.size_class == 2 else "death_vehicle_heavy")
	t.eq(_ids(r), PackedStringArray([expect_id]), "vehicle death by size class")
	r.router.spawn_log.clear()
	r.router.process_batch(_rec(SimCombatConsts.EV_DEATH, 8, rifle.x, rifle.y, rifle.id, rifle.def_idx, ViewConsts.DK_INFANTRY, 0, 0, 0))
	t.eq(_ids(r), PackedStringArray(["death_infantry"]), "infantry death")
	r.router.spawn_log.clear()
	r.router.process_batch(_rec(SimCombatConsts.EV_DEATH, 8, 40 * C, 40 * C, 9999, 0, ViewConsts.DK_STRUCTURE, 0, 0, 0))
	t.eq(_ids(r), PackedStringArray(["building_collapse"]), "structure collapse")
	r.router.spawn_log.clear()
	r.router.process_batch(_rec(SimCombatConsts.EV_DEATH, 8, 41 * C, 41 * C, 9998, 0, ViewConsts.DK_DRONE, 0, 0, 0))
	t.eq(_ids(r), PackedStringArray(["death_drone"]), "drone death")
	r.free_all()


func test_explosion_dedupe_drops_the_second_fireball(t: TestCtx) -> void:
	var r: Rig = _rig()
	var tank: SimEntity = Kit.tank(r.w, 1, 30, 30)
	Kit.frame(r.vw)
	var boom: PackedInt32Array = _rec(SimCombatConsts.EV_IMPACT, 8, tank.x + 300, tank.y, 0, -1, 1, 1700, 400, 0)
	var died: PackedInt32Array = _rec(SimCombatConsts.EV_DEATH, 8, tank.x, tank.y, tank.id, tank.def_idx, ViewConsts.DK_VEHICLE, 0, 0, 0)
	r.router.process_batch(_batch([boom, died]))
	var ids: PackedStringArray = _ids(r)
	t.check(ids.has("expl_medium"), "the detonation drew its explosion: %s" % ids)
	t.check(ids.has("death_secondary"), "the death only adds debris / fire / smoke")
	t.check(not (ids.has("death_vehicle_light") or ids.has("death_vehicle_medium") or ids.has("death_vehicle_heavy")), "no second fireball")
	t.eq(r.router.stats["deduped"], 1, "counted")
	# without a detonation nearby the full death plays
	r.router.spawn_log.clear()
	var far: PackedInt32Array = _rec(SimCombatConsts.EV_IMPACT, 9, tank.x + 20 * U, tank.y, 0, -1, 1, 1700, 400, 0)
	r.router.process_batch(_batch([far, died]))
	ids = _ids(r)
	t.check(not ids.has("death_secondary"), "far detonation: full death effect")
	r.free_all()


# ---------------------------------------------------------------------------------------------- gating
func test_fog_gating(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var fog: FogStub = FogStub.new()
	fog.visible_rect = Rect2i(20, 20, 20, 20)  # cells 20..39
	w.fog = fog
	var mine: SimEntity = Kit.tank(w, 0, 30, 30)
	var foe: SimEntity = Kit.tank(w, 1, 60, 60)
	fog.hidden[foe.id] = true
	var r: Rig = Rig.new()
	r.w = w
	_finish(r)
	Kit.frame(r.vw)
	t.eq(r.vw.entity_view(foe.id).vs, ViewConsts.VS_HIDDEN, "enemy hidden by the fog")
	# an explosion on hidden ground draws nothing
	r.router.process_batch(_rec(SimCombatConsts.EV_IMPACT, 4, 60 * C, 60 * C, 0, -1, 0, 1700, 100, 0))
	t.eq(r.router.spawn_log.size(), 0, "impact in the fog is gated")
	t.eq(r.router.stats["gated"], 1, "counted")
	# the same in vision draws
	r.router.process_batch(_rec(SimCombatConsts.EV_IMPACT, 4, 30 * C, 30 * C, 0, -1, 0, 1700, 100, 0))
	t.eq(r.router.spawn_log.size(), 1, "impact in vision draws")
	# a shot from a hidden unit at a visible one draws (the target end is visible)
	r.router.spawn_log.clear()
	r.router.process_batch(_rec(SimCombatConsts.EV_FIRE, 4, foe.x, foe.y, foe.id, 3, SimCombatConsts.PK_BULLET << 8, mine.id, mine.x, mine.y))
	t.check(r.router.spawn_log.size() >= 1, "a shot INTO vision draws its muzzle")
	# a shot entirely inside the fog does not
	r.router.spawn_log.clear()
	r.router.process_batch(_rec(SimCombatConsts.EV_FIRE, 4, foe.x, foe.y, foe.id, 3, SimCombatConsts.PK_BULLET << 8, -1, foe.x + 500, foe.y))
	t.eq(r.router.spawn_log.size(), 0, "a shot inside the fog is gated")
	# strategic events are global: a warning marker zone for the hidden area is never fog gated (its own visibility mask applies)
	r.vw.set_local_player(-1, true)
	r.router.process_batch(_rec(SimCombatConsts.EV_IMPACT, 5, 60 * C, 60 * C, 0, -1, 0, 1700, 100, 0))
	t.eq(r.router.spawn_log.size(), 1, "observers see everything")
	r.free_all()


# ---------------------------------------------------------------------------------------------- shake
func test_camera_shake_amounts(t: TestCtx) -> void:
	var r: Rig = _rig()
	var at: Vector3 = r.vw.camera.current_focus()
	for id: StringName in [&"expl_small", &"expl_medium", &"expl_large", &"death_vehicle_heavy", &"building_collapse", &"sw_atlas_impact"]:
		r.shakes.clear()
		r.fx.spawn(id, at, Vector3.ZERO, 1.0)
		var peak: float = 0.0
		for s: float in r.shakes:
			peak = maxf(peak, s)
		t.gt(peak, 0.0, "%s shakes the camera" % id)
		t.le(peak, 1.0, "%s: shake amount is at most 1 (%.2f)" % [id, peak])
		r.fx.clear_all()
	r.shakes.clear()
	r.fx.spawn(&"expl_small", at, Vector3.ZERO, 1.0)
	var small: float = r.shakes[0]
	r.shakes.clear()
	r.fx.spawn(&"expl_large", at, Vector3.ZERO, 1.0)
	var large: float = r.shakes[0]
	t.lt(small, large, "bigger blast, bigger shake")
	r.shakes.clear()
	r.fx.spawn(&"expl_large", at + Vector3(300.0, 0.0, 0.0), Vector3.ZERO, 1.0)
	t.eq(r.shakes.size(), 0, "beyond 140 m: no shake")
	r.free_all()


# ---------------------------------------------------------------------------------------------- damage emitters
func test_damage_emitter_cap_and_nearest_first(t: TestCtx) -> void:
	var r: Rig = _rig()
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 40:
		ids.append(Kit.tank(r.w, 0, 10 + (i % 10) * 3, 10 + (i / 10) * 3).id)
	Kit.frame(r.vw)
	for id: int in ids:
		var ve: ViewEntity = r.vw.entity_view(id)
		ve.hp = 20
		ve.max_hp = 100
		r.router.process_batch(_rec(SimCombatConsts.EV_HIT, 3, ve.x_cur, ve.y_cur, id, 10, 0, 0, 20, 100))
	for k: int in 6:
		r.router.frame(0.5)
	t.eq(r.router.ambient.active_count(), 24, "40 damaged entities: exactly 24 emitters")
	# the 24 nearest to the camera win
	var cam: Vector3 = r.vw.camera.camera.transform.origin
	var dist: Array = []
	for id: int in ids:
		var ve2: ViewEntity = r.vw.entity_view(id)
		dist.append([cam.distance_squared_to(Vector3(ve2.wx, ve2.wy, ve2.wz)), id])
	dist.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as float) < (b[0] as float))
	var nearest: Dictionary = {}
	for i: int in 24:
		nearest[(dist[i] as Array)[1]] = true
	var wrong: int = 0
	for aid: Variant in r.router.ambient.active_ids():
		if not nearest.has(aid):
			wrong += 1
	t.eq(wrong, 0, "the active set is the 24 nearest")
	t.gt(r.router.logged(&"damage_fire"), 0, "hp 20 % burns")
	# healing above 75 % removes the emitter
	for id: int in ids:
		r.vw.entity_view(id).hp = 90
	for k: int in 3:
		r.router.frame(0.6)
	t.eq(r.router.ambient.active_count(), 0, "healed entities stop emitting")
	r.free_all()


# ---------------------------------------------------------------------------------------------- projectiles
func _projectiles(r: Rig) -> ViewProjectiles:
	var p: ViewProjectiles = ViewProjectiles.new()
	p.setup(r.vw, r.fx, r.router.catalog)
	r.router.projectiles = p
	return p


func test_projectile_look_per_archetype_and_cap(t: TestCtx) -> void:
	var r: Rig = _rig()
	var p: ViewProjectiles = _projectiles(r)
	t.eq(p.look_of(3), ViewProjectiles.LOOK_TRACER, "tank cannon: tracer")
	t.eq(p.look_of(6), ViewProjectiles.LOOK_MESH, "AT missile: mesh")
	t.eq(p.look_of(9), ViewProjectiles.LOOK_ARC, "artillery: arc ribbon")
	t.eq(p.look_of(13), ViewProjectiles.LOOK_NONE, "thermal beam is a tracker, not a projectile")
	t.eq(p.look_of(19), ViewProjectiles.LOOK_NONE, "EMP field")
	for i: int in 27:
		var row: Dictionary = (r.book.mappings.get("projectiles", {}) as Dictionary).get(FxCatalog.FAMILIES[i], {}) as Dictionary
		t.check(not row.is_empty(), "family %s has a projectile row" % FxCatalog.FAMILIES[i])
	# 100 missiles: the mesh cap holds, the trail effects are unaffected
	var recs: Array = []
	for i: int in 100:
		recs.append(_rec(SimCombatConsts.EV_PROJ_SPAWN, 10, 30 * C, 30 * C, 500 + i, 6, 0 | (SimCombatConsts.PK_MISSILE << 4) | (40 << 16), -1, 40 * C, 34 * C))
	r.router.process_batch(_batch(recs))
	t.le(p.live_meshes(), p.cap, "live meshes <= cap (%d <= %d)" % [p.live_meshes(), p.cap])
	t.gt(p.live_meshes(), 0, "some meshes were created")
	t.eq(r.router.logged(&"muzzle_at_missile"), 0, "the launch event alone draws no muzzle (EV_FIRE does)")
	p.teardown()
	r.free_all()


## Mesh projectiles follow the combat pool exactly (position validated by serial).
func test_projectile_mesh_mirrors_the_pool(t: TestCtx) -> void:
	var r: Rig = _rig()
	var p: ViewProjectiles = _projectiles(r)
	var proj: SimProjectiles = r.w.combat.proj
	var serial: int = proj.spawn_remote(r.w, 0, 0, SimCombatConsts.PK_BOMB, 0, 30 * C, 30 * C, 40 * C, 30 * C, 0, 10000, 0)
	if serial < 0:
		t.skip("no warhead table row for a remote bomb in the test data")
		p.teardown()
		r.free_all()
		return
	var ev: PackedInt32Array = r.w.events.take()
	r.router.process_batch(ev)
	t.eq(p.live_meshes(), 1, "one mesh for the remote bomb")
	var worst: float = 0.0
	var samples: int = 0
	for k: int in 6:
		r.w.step()
		r.router.process_batch(r.w.events.take())
		Kit.frame(r.vw, 1.0)
		var slot: int = proj.slot_of_serial(serial)
		if slot < 0:
			break
		p.frame(1.0 / 60.0)
		var rec: ViewProjectiles.Rec = p.record_of(serial)
		if rec == null or rec.rig == null:
			break
		var rx: float = float(proj.x[slot]) * ViewConsts.M_PER_UNIT
		var rz: float = float(proj.y[slot]) * ViewConsts.M_PER_UNIT
		worst = maxf(worst, maxf(absf(rec.rig.transform.origin.x - rx), absf(rec.rig.transform.origin.z - rz)))
		samples += 1
	t.ge(samples, 4, "the rig was compared with the slot on %d ticks" % samples)
	t.lt(worst, 0.05, "rig position equals the pool slot at alpha 1 (worst %.4f m)" % worst)
	p.teardown()
	r.free_all()


# ---------------------------------------------------------------------------------------------- beams, wrecks, statuses, strategic
func test_beam_tracker_starts_and_stops(t: TestCtx) -> void:
	var r: Rig = _rig()
	var a: SimEntity = Kit.tank(r.w, 0, 30, 30)
	var b: SimEntity = Kit.tank(r.w, 1, 36, 30)
	Kit.frame(r.vw)
	r.router.process_batch(_rec(SimCombatConsts.EV_BEAM_START, 5, a.x, a.y, a.id, 13, 0, b.id, 100))
	t.eq(r.fx.get_stats()["trackers"], 1, "one tracker while the beam is on")
	t.eq(r.router.logged(&"muzzle_beam_thermal"), 1, "source glow")
	for k: int in 10:
		r.fx.advance(0.07)
	t.gt(r.fx.live_instances(), 0, "beam segments are alive")
	r.router.process_batch(_rec(SimCombatConsts.EV_BEAM_END, 40, a.x, a.y, a.id, 0, 0))
	r.fx.advance(0.1)
	t.eq(r.fx.get_stats()["trackers"], 0, "the tracker ends with EV_BEAM_END")
	r.free_all()


func test_wreck_loops_and_statuses(t: TestCtx) -> void:
	var r: Rig = _rig()
	var a: SimEntity = Kit.tank(r.w, 0, 30, 30)
	Kit.frame(r.vw)
	r.router.process_batch(_rec(SimCombatConsts.EV_WRECK_ADD, 5, 32 * C, 32 * C, 700, 0, 5 + 1200, 0, 0, 0))
	t.eq(r.fx.emitter_count(), 2, "burning loop + thin smoke loop")
	r.router.process_batch(_rec(SimCombatConsts.EV_WRECK_REMOVE, 900, 32 * C, 32 * C, 700, 2))
	r.fx.advance(0.05)
	t.eq(r.fx.emitter_count(), 0, "loops stop with the wreck")
	r.router.process_batch(_rec(SimCombatConsts.EV_EMP, 6, a.x, a.y, a.id, 160, 1, 1, 0, 0))
	t.eq(r.fx.get_stats()["trackers"], 1, "EMP status arcs on the victim")
	r.router.process_batch(_rec(SimCombatConsts.EV_EMP, 6, a.x, a.y, a.id, 160, 1, 1, 1, 0))
	t.eq(r.fx.get_stats()["trackers"], 1, "a blocked EMP adds nothing")
	# aircraft: the fall is a trail, the impact comes with EV_CRASH
	r.router.spawn_log.clear()
	r.router.process_batch(_rec(SimCombatConsts.EV_DEATH, 8, 40 * C, 40 * C, 9990, 0, ViewConsts.DK_CRASH, 0, 0, 0))
	t.eq(r.router.spawn_log.size(), 0, "crash death: no fireball yet")
	r.router.process_batch(_rec(SimCombatConsts.EV_CRASH, 38, 40 * C, 40 * C, 9990, 1, 0))
	t.eq(r.router.logged(&"aircraft_impact"), 1, "ground impact of the crash")
	r.free_all()


func test_strategic_events(t: TestCtx) -> void:
	var r: Rig = _rig()
	Kit.frame(r.vw)
	# a strategic impact of an unknown superweapon index falls back to the generic large blast, once per packet
	r.router.process_batch(_rec(SimEconConst.EVT_SW_IMPACT, 30, 30 * C, 30 * C, 77, 30 * C, 30 * C, 6144, 3))
	r.router.process_batch(_rec(SimEconConst.EVT_SW_IMPACT, 30, 30 * C, 30 * C, 77, 30 * C, 30 * C, 6144, 3))
	t.eq(r.router.logged(&"expl_strategic_large"), 1, "duplicate announcements of one packet draw once")
	# Helios sweep: a tracker follows the moving hot spot
	r.router.process_batch(_rec(SimCombatConsts.EV_SWEEP, 31, 20 * C, 30 * C, 5, 0, 240, 3072, 44 * C, 30 * C))
	t.eq(r.fx.get_stats()["trackers"], 1, "sweep tracker")
	# Tempest launch, Dragonfall engine and a buff cast are global feedback
	r.router.process_batch(_rec(SimZoneConsts.EV_SWARM_LAUNCHED, 32, 10 * C, 10 * C, -1, 30 * C, 30 * C))
	r.router.process_batch(_rec(SimZoneConsts.EV_ENGINE_ASSEMBLED, 32, 12 * C, 12 * C, 500, 501))
	t.eq(r.router.logged(&"sw_tempest_launch"), 1, "tempest launch burst")
	t.eq(r.router.logged(&"sw_assemble_burst"), 1, "engine assembly burst")
	r.router.spawn_log.clear()
	r.router.process_batch(_rec(SimEconConst.EVT_POWER_ACTIVATED, 33, 0, 0, 0, 1, 3, 30 * C, 30 * C, 0))
	t.eq(r.router.logged(&"power_cast_ring"), 1, "support power cast ring")
	r.router.process_batch(_rec(SimEconConst.EVT_POWER_ACTIVATED, 33, 0, 0, 0, SimEconConst.SLOT_SW, 3, 30 * C, 30 * C, 0))
	t.eq(r.router.logged(&"power_cast_ring"), 1, "the superweapon slot draws nothing here (its warning did)")
	# Trident intercept flashes
	r.router.spawn_log.clear()
	r.router.process_batch(_rec(SimCombatConsts.EV_INTERCEPT, 34, 30 * C, 30 * C, 9, 0, 1, 20, 0, 1))
	t.eq(r.router.logged(&"sw_intercept_flash"), 1, "zone kill flash")
	r.router.process_batch(_rec(SimCombatConsts.EV_INTERCEPT, 34, 30 * C, 30 * C, 9, 0, 0, 20, 0, 1))
	t.eq(r.router.logged(&"aps_flash"), 1, "APS kill flash")
	r.free_all()


func test_zone_events_with_the_zone_system(t: TestCtx) -> void:
	var r: Rig = _rig()
	if r.w.zones == null:
		t.skip("no zone system in the test world")
		r.free_all()
		return
	Kit.frame(r.vw)
	# an unknown zone id is ignored without error; a warning marker zone draws the marker and cancels with the zone
	r.router.process_batch(_rec(SimZoneConsts.EV_ZONE_SPAWNED, 5, 30 * C, 30 * C, -1, 9999, 1, 0))
	t.eq(r.router.spawn_log.size(), 0, "unknown zone id")
	var zid: int = r.w.zones.spawn_warning(SimZoneConsts.WK_CIRCLE, 0, 30 * C, 30 * C, 0, 6144, 0, 200)
	if zid < 0:
		t.skip("warning zone refused")
		r.free_all()
		return
	r.router.process_batch(r.w.events.take())
	t.eq(r.router.logged(&"sw_warning_marker"), 1, "warning marker for the warning zone")
	t.eq(r.fx.batch(&"marker").active_count(r.fx.now()), 1, "marker ring alive")
	r.w.zones.end_zone(zid, SimZoneConsts.ZE_CANCELLED)
	r.router.process_batch(r.w.events.take())
	t.eq(r.fx.batch(&"marker").active_count(r.fx.now()), 0, "cancelled warning removes the marker at once")
	r.free_all()


# ---------------------------------------------------------------------------------------------- content vocabulary
func test_router_effect_ids_exist_in_fx_json(t: TestCtx) -> void:
	var book: FxRecipeBook = FxRecipeBook.new()
	t.check(book.load_file(), "fx.json compiles: %s" % "; ".join(book.errors()))
	var re: RegEx = RegEx.new()
	re.compile("&\"((?:muzzle|hit|expl|death|sw|zone|power|trail|tr|arc|beam|aps|wreck|damage|status|landing|rotor|cloak|decoy|summon|repair|capture|credit|salvage|build|sell|exit|unload|water|impact|aircraft|collapse|spawn|rearm|emp|vehicle|wake|oil|crash)_[a-z_]*)\"")
	var missing: PackedStringArray = PackedStringArray()
	var found: int = 0
	for path: String in ["res://src/view/fx/fx_event_router.gd", "res://src/view/fx/fx_strategic.gd", "res://src/view/fx/fx_ambient.gd", "res://src/view/view_projectiles.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		for m: RegExMatch in re.search_all(src):
			var id: String = m.get_string(1)
			found += 1
			if not book.has(StringName(id)):
				missing.append("%s: %s" % [path.get_file(), id])
	t.gt(found, 40, "the scan found the ids (%d)" % found)
	t.eq(missing, PackedStringArray(), "every effect id named by the router exists")
	# ids named by the mapping tables
	var maps: Dictionary = book.mappings
	for fam: Variant in (maps.get("projectiles", {}) as Dictionary):
		var row: Dictionary = (maps["projectiles"] as Dictionary)[fam] as Dictionary
		for key: String in ["fx", "trail"]:
			if row.has(key):
				t.check(book.has(StringName(str(row[key]))), "projectiles.%s.%s = %s exists" % [fam, key, row[key]])
	for kind: Variant in (maps.get("zones", {}) as Dictionary):
		var z: Dictionary = (maps["zones"] as Dictionary)[kind] as Dictionary
		t.check(book.has(StringName(str(z.burst))) and book.has(StringName(str(z.tick))), "zone kind %s burst / tick exist" % kind)
	for sw: Variant in (maps.get("superweapons", {}) as Dictionary):
		var row2: Dictionary = (maps["superweapons"] as Dictionary)[sw] as Dictionary
		for key2: Variant in row2:
			if key2 in ["pre", "impact", "core", "wave", "tick", "launch", "capsule", "assemble", "dome", "flash"]:
				t.check(book.has(StringName(str(row2[key2]))), "superweapons.%s.%s = %s exists" % [sw, key2, row2[key2]])


## The catalog resolves every archetype to shipped effects (muzzle, default impact, trail) and all deaths / explosions exist.
func test_catalog_vocabulary_is_shipped(t: TestCtx) -> void:
	var book: FxRecipeBook = FxRecipeBook.new()
	book.load_file()
	var c: FxCatalog = FxCatalog.new(book)
	var quiet_was: bool = Log.quiet
	Log.quiet = true
	for arch: int in 27:
		var mz: StringName = c.muzzle_id(arch)
		t.check(mz != &"" and book.has(mz), "muzzle of archetype %d (%s) exists: %s" % [arch, FxCatalog.FAMILIES[arch], mz])
		for res: int in [1, 2, 3, 4, 5]:
			for splash: int in [0, 700, 1400, 2400, 4000]:
				var imp: StringName = c.impact_id(arch, res, splash, arch == 7 or arch == 18)
				t.check(imp != &"" and book.has(imp), "impact %d/%d/%d -> %s exists" % [arch, res, splash, imp])
	for dk: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		for sc: int in [0, 1, 2, 3, 7, 8, 9]:
			var d: StringName = c.death_id(dk, sc)
			t.check(d != &"" and book.has(d), "death %d/%d -> %s exists" % [dk, sc, d])
	Log.quiet = quiet_was
	t.gt(book.ids().size(), 110, "about 115+ effects shipped (%d)" % book.ids().size())


## Every shipped effect spawns without an engine error and within a sane per-spawn cost.
func test_every_effect_spawns_and_costs(t: TestCtx) -> void:
	var r: Rig = _rig()
	var worst: float = 0.0
	var worst_id: String = ""
	var at: Vector3 = r.vw.camera.current_focus()
	for id: StringName in r.book.ids():
		var d: FxRecipeBook.FxDef = r.book.def(id)
		var t0: int = Time.get_ticks_usec()
		r.fx.spawn(id, at, at + Vector3(8.0, 0.0, -4.0), d.nominal_scale)
		var us: float = float(Time.get_ticks_usec() - t0)
		if us > worst:
			worst = us
			worst_id = String(id)
		r.fx.advance(0.05)
	t.note("slowest composite spawn: %s %.0f us" % [worst_id, worst])
	t.lt(worst, 3000.0, "no composite costs more than 3 ms to spawn (%s %.0f us)" % [worst_id, worst])
	r.free_all()


func test_fx_stage_attaches_and_routes(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var tank: SimEntity = Kit.tank(w, 0, 30, 30)
	var foe: SimEntity = Kit.tank(w, 1, 36, 30)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(30.0, 30.0), 0.5)
	var st: FxStage = FxStage.attach(vw)
	t.check(vw.router.extra_handler.is_valid(), "the router hook is installed")
	t.not_null(st.fx, "manager")
	st.fx.force = true
	var ev: PackedInt32Array = _rec(SimCombatConsts.EV_FIRE, 3, tank.x, tank.y, tank.id, 3, SimCombatConsts.PK_BULLET << 8, foe.id, foe.x, foe.y)
	vw.frame(1.0 / 60.0, 0.5, ev)
	t.gt(st.router.stats["spawns"], 0, "muzzle flash through the ViewWorld hook")
	st.detach()
	t.check(not vw.router.extra_handler.is_valid(), "detach removes the hook")
	Kit.free_view(vw)


func test_attach_chains_an_existing_handler(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var tank: SimEntity = Kit.tank(w, 0, 30, 30)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(30.0, 30.0), 0.5)
	var seen: Array[int] = [0]
	vw.router.extra_handler = func(_ev: PackedInt32Array, _o: int) -> void: seen[0] += 1
	var st: FxStage = FxStage.attach(vw)
	st.fx.force = true
	vw.frame(1.0 / 60.0, 0.5, _rec(SimCombatConsts.EV_FIRE, 3, tank.x, tank.y, tank.id, 3, SimCombatConsts.PK_BULLET << 8, -1, tank.x + 4096, tank.y))
	t.eq(seen[0], 1, "the previous handler still runs")
	t.gt(st.router.stats["spawns"], 0, "and the FX router runs after it")
	st.detach()
	vw.frame(1.0 / 60.0, 0.5, _rec(SimCombatConsts.EV_FIRE, 4, tank.x, tank.y, tank.id, 3, SimCombatConsts.PK_BULLET << 8, -1, tank.x + 4096, tank.y))
	t.eq(seen[0], 2, "detach restores the previous handler")
	Kit.free_view(vw)
