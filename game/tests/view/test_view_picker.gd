extends RefCounted
## VIEW-W4: ray -> entity id through the sim's spatial hash and structure grid (no physics), filters, box selection, timings.

const Kit := preload("res://tests/view/vw_kit.gd")
const C: int = SimConfig.CELL


func _world() -> Array:
	var w: SimWorld = Kit.sim()
	var tank: SimEntity = Kit.tank(w, 0, 48, 48)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(48.5, 48.5), 0.0)
	Kit.step_frame(vw, 1, 1.0)
	return [w, vw, tank]


func _screen(vw: ViewWorld, ve: ViewEntity, lift: float = 0.5) -> Vector2:
	return vw.camera.world_to_screen(Vector3(ve.wx, ve.wy + lift, ve.wz))


func test_tank_under_the_cursor(t: TestCtx) -> void:
	var r: Array = _world()
	var vw: ViewWorld = r[1] as ViewWorld
	var tank: SimEntity = r[2] as SimEntity
	var ve: ViewEntity = vw.entity_view(tank.id)
	t.eq(vw.pick(_screen(vw, ve), ViewPicker.PICK_ANY), tank.id, "the click on the tank picks it")
	t.eq(vw.pick(Vector2(20.0, 20.0), ViewPicker.PICK_ANY), -1, "an empty corner picks nothing")
	Kit.free_view(vw)


func test_factory_roof_and_hidden_ground_behind_it(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var tank: SimEntity = Kit.tank(w, 0, 48, 48)
	var fac: SimEntity = w.spawn_structure(w.data.structure_idx(DefTestKit.S_FACTORY), 0, 48 * C + C / 2, 44 * C + C, 0, 0, 0, 0, SimEvent.SPAWN_INITIAL)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(48.5, 46.5), 0.0)
	Kit.step_frame(vw, 1, 1.0)
	var fv: ViewEntity = vw.entity_view(fac.id)
	t.eq(vw.pick(vw.camera.world_to_screen(Vector3(fv.wx, fv.height_m, fv.wz)), ViewPicker.PICK_ANY), fac.id, "click on the roof picks the factory")
	# ground point directly behind (north of) the factory, hidden from the camera by the building
	var behind: Vector3 = Vector3(fv.wx, 0.0, fv.wz - fv.pick_half.z + 0.3)
	var sp: Vector2 = vw.camera.world_to_screen(Vector3(behind.x, 0.0, behind.z))
	t.eq(vw.pick(sp, ViewPicker.PICK_ANY), fac.id, "a click on the ground the building hides picks the building (nearest ray hit)")
	t.eq(vw.pick(vw.camera.world_to_screen(Vector3(vw.entity_view(tank.id).wx, 0.6, vw.entity_view(tank.id).wz)), ViewPicker.PICK_ANY), tank.id, "the tank is still pickable")
	Kit.free_view(vw)


func test_aircraft_above_a_ground_unit(t: TestCtx) -> void:
	var r: Array = _world()
	var vw: ViewWorld = r[1] as ViewWorld
	var w: SimWorld = r[0] as SimWorld
	var ground: SimEntity = r[2] as SimEntity
	var heli: SimEntity = Kit.tank(w, 0, 48, 48)
	Kit.step_frame(vw, 1, 1.0)
	var hv: ViewEntity = vw.entity_view(heli.id)
	# turn the record into an aircraft hovering 7 m above the ground unit (test seam: the small data set has no air unit)
	hv.motion = ViewConsts.MOTION_AIR_FIXED
	hv.wy = 7.0
	vw.air_list().append(hv)
	var gv: ViewEntity = vw.entity_view(ground.id)
	var air_sp: Vector2 = vw.camera.world_to_screen(hv.pick_centre())
	t.eq(vw.pick(air_sp, ViewPicker.PICK_ANY), heli.id, "the gunship wins at its own screen position")
	var pos_ground: Vector2 = _screen(vw, gv)
	t.gt(pos_ground.distance_to(air_sp), 40.0, "the two are well separated on screen")
	t.eq(vw.pick(pos_ground, ViewPicker.PICK_ANY), ground.id, "a click on the ground unit below the gunship picks the ground unit")
	t.check(vw.pick(air_sp, ViewPicker.PICK_ANY & ~ViewPicker.PICK_AIR) != heli.id, "without PICK_AIR aircraft are never returned")
	Kit.free_view(vw)


func test_wreck_tie_prefers_the_unit_and_hidden_enemies_are_skipped(t: TestCtx) -> void:
	var r: Array = _world()
	var vw: ViewWorld = r[1] as ViewWorld
	var w: SimWorld = r[0] as SimWorld
	var unit: SimEntity = r[2] as SimEntity
	var dead: SimEntity = Kit.tank(w, 1, 48, 48)
	var wreck: SimEntity = w.spawn_wreck(dead, true, 50, 1200)
	wreck.combat.wreck_expire = w.tick + 1200  # what combat's death sequence does
	wreck.combat.wreck_flags = SimCombatConsts.WF_SALVAGEABLE
	Kit.step_frame(vw, 1, 1.0)
	var uv: ViewEntity = vw.entity_view(unit.id)
	t.eq(vw.pick(_screen(vw, uv), ViewPicker.PICK_ANY), unit.id, "wreck vs unit tie: the unit")
	t.eq(vw.pick(_screen(vw, uv), ViewPicker.PICK_WRECKS), wreck.id, "a wreck-only filter returns the wreck")
	var enemy: SimEntity = Kit.tank(w, 1, 52, 48)
	Kit.step_frame(vw, 1, 1.0)
	var ev: ViewEntity = vw.entity_view(enemy.id)
	t.eq(vw.pick(_screen(vw, ev), ViewPicker.PICK_ENEMY), enemy.id, "enemy filter finds the enemy")
	t.eq(vw.pick(_screen(vw, ev), ViewPicker.PICK_OWN), -1, "own filter skips it")
	ev.vs = ViewConsts.VS_HIDDEN
	t.eq(vw.pick(_screen(vw, ev), ViewPicker.PICK_ANY), -1, "a fog-hidden enemy is never returned")
	Kit.free_view(vw)


func test_pick_box_returns_own_units_inside_ascending(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 5:
		ids.append(Kit.tank(w, 0, 44 + i * 2, 48).id)
	var foe: SimEntity = Kit.tank(w, 1, 46, 50)
	var far: SimEntity = Kit.tank(w, 0, 80, 20)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(48.5, 48.5), 0.2)
	Kit.step_frame(vw, 1, 1.0)
	var lo: Vector2 = vw.camera.world_to_screen(Vector3(43.0 * 3.0, 0.0, 47.0 * 3.0))
	var hi: Vector2 = vw.camera.world_to_screen(Vector3(54.0 * 3.0, 0.0, 51.0 * 3.0))
	var rect: Rect2 = Rect2(lo, hi - lo).abs()
	var out: PackedInt32Array = PackedInt32Array()
	var n: int = vw.pick_box(rect, ViewPicker.PICK_UNITS | ViewPicker.PICK_OWN, out)
	t.eq(n, 5, "exactly the own units inside")
	var sorted: PackedInt32Array = ids.duplicate()
	sorted.sort()
	t.eq(out, sorted, "ascending ids")
	t.check(not out.has(foe.id) and not out.has(far.id), "enemy and far units excluded")
	Kit.free_view(vw)


func test_pick_timings(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	for i: int in 200:
		Kit.tank(w, i % 2, 6 + (i % 40) * 2, 6 + (i / 40) * 3)
		Kit.rifle(w, i % 2, 7 + (i % 40) * 2, 30 + (i / 40) * 3)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(48.0, 30.0), 1.0)
	Kit.step_frame(vw, 1, 1.0)
	var out: PackedInt32Array = PackedInt32Array()
	var t0: int = Time.get_ticks_usec()
	for i: int in 20:
		vw.pick_box(Rect2(0.0, 0.0, 1920.0, 1080.0), ViewPicker.PICK_ANY, out)
	var box_ms: float = float(Time.get_ticks_usec() - t0) / 20000.0
	var t1: int = Time.get_ticks_usec()
	for i: int in 200:
		vw.pick(Vector2(700.0 + float(i % 20) * 30.0, 500.0 + float(i / 20) * 20.0), ViewPicker.PICK_ANY)
	var pick_us: float = float(Time.get_ticks_usec() - t1) / 200.0
	t.note("pick_box(%d entities): %.3f ms; pick: %.0f us" % [vw.entity_count(), box_ms, pick_us])
	t.lt(box_ms, 2.5, "pick_box over ~400 entities stays near the 2 ms budget")
	t.lt(pick_us, 400.0, "pick stays in the hundreds of microseconds")
	Kit.free_view(vw)
