extends RefCounted
## The fixture adapter's picker (`UiPicking` on `UiPickData`, ui.md 10.2 `test_ui_picking`): the reference for ViewPicker's
## rules. Synthetic rays for the tie rules, the camera for projection / box / alignment, and the timing report.

const TANK: String = "unit.napc.guardian_tank"
const RIFLE: String = "unit.napc.rifle_squad"
const BARRACKS: String = "structure.shared.barracks"
const V = preload("res://src/ui/ui_view_port.gd")


func _pd() -> UiPickData:
	return UiPickData.new()


## A pick sphere at (x, 1, z) radius r.
func _add(pd: UiPickData, id: int, x: float, z: float, r: float, fl: int) -> void:
	pd.add(id, Vector3(x, 0.0, z), Vector3(x, 1.0, z), r, 2.0, fl)


func test_nearest_hit_wins(t: TestCtx) -> void:
	var pd: UiPickData = _pd()
	_add(pd, 2, 0.0, -3.0, 3.0, UiPickData.F_STRUCTURE | UiPickData.F_OWN)  # the building
	_add(pd, 1, 0.0, 0.0, 1.0, UiPickData.F_OWN)  # a unit standing 1 m in front of it
	var o: Vector3 = Vector3(0.0, 1.0, 10.0)
	var d: Vector3 = Vector3(0.0, 0.0, -1.0)
	t.eq(UiPicking.pick_ray(o, d, pd), 1, "the unit in front of the building wins")
	# behind a wall: the wall is nearer than the unit behind it
	var pd2: UiPickData = _pd()
	_add(pd2, 7, 0.0, -5.0, 1.0, UiPickData.F_OWN)
	_add(pd2, 8, 0.0, 5.0, 2.0, UiPickData.F_STRUCTURE | 0)
	t.eq(UiPicking.pick_ray(o, d, pd2), 8, "a unit behind a wall is not picked")
	t.eq(UiPicking.pick_ray(o, Vector3(1.0, 0.0, 0.0).normalized(), pd2), -1, "a miss returns -1")
	t.eq(UiPicking.pick_ray(o, d, _pd()), -1, "empty data")


func test_tie_rules(t: TestCtx) -> void:
	var o: Vector3 = Vector3(0.0, 1.0, 10.0)
	var d: Vector3 = Vector3(0.0, 0.0, -1.0)
	var pd: UiPickData = _pd()
	_add(pd, 5, 0.0, 0.0, 1.0, UiPickData.F_WRECK)
	_add(pd, 6, 0.0, 0.0, 1.0, 0)
	t.eq(UiPicking.pick_ray(o, d, pd), 6, "non-wreck over wreck")
	var pd2: UiPickData = _pd()
	_add(pd2, 3, 0.0, 0.0, 1.0, UiPickData.F_STRUCTURE)
	_add(pd2, 9, 0.0, 0.0, 1.0, 0)
	t.eq(UiPicking.pick_ray(o, d, pd2), 9, "unit over structure even with the higher id")
	var pd3: UiPickData = _pd()
	_add(pd3, 12, 0.0, 0.0, 1.0, 0)
	_add(pd3, 4, 0.0, 0.0, 1.0, 0)
	_add(pd3, 8, 0.0, 0.0, 1.0, 0)
	t.eq(UiPicking.pick_ray(o, d, pd3), 4, "then the lowest id")
	var pd4: UiPickData = _pd()  # 5 mm apart is inside the 0.01 m tie band: the rules decide, not the depth
	_add(pd4, 20, 0.0, 0.005, 1.0, UiPickData.F_WRECK)
	_add(pd4, 21, 0.0, 0.0, 1.0, 0)
	t.eq(UiPicking.pick_ray(o, d, pd4), 21)
	var pd5: UiPickData = _pd()  # 5 cm apart: the nearer wreck wins
	_add(pd5, 20, 0.0, 0.05, 1.0, UiPickData.F_WRECK)
	_add(pd5, 21, 0.0, 0.0, 1.0, 0)
	t.eq(UiPicking.pick_ray(o, d, pd5), 20, "outside the band the nearest wins")


func test_filters_fog_and_ghosts(t: TestCtx) -> void:
	var o: Vector3 = Vector3(0.0, 1.0, 10.0)
	var d: Vector3 = Vector3(0.0, 0.0, -1.0)
	var pd: UiPickData = _pd()
	_add(pd, 1, 0.0, 2.0, 1.0, UiPickData.F_STRUCTURE | UiPickData.F_GHOST)  # remembered structure in front
	_add(pd, 2, 0.0, -2.0, 1.0, UiPickData.F_OWN)
	t.eq(UiPicking.pick_ray(o, d, pd, V.PICK_ANY), 1, "PICK_ANY includes ghosts")
	t.eq(UiPicking.pick_ray(o, d, pd, V.PICK_ANY & ~V.PICK_GHOSTS), 2, "a ghost is returned only when asked for")
	t.eq(UiPicking.pick_ray(o, d, pd, V.PICK_UNITS), 2, "kind filter")
	t.eq(UiPicking.pick_ray(o, d, pd, V.PICK_STRUCTURES | V.PICK_GHOSTS), 1)
	t.eq(UiPicking.pick_ray(o, d, pd, V.PICK_UNITS | V.PICK_ENEMY), -1, "relation filter: id 2 is own")
	var air: UiPickData = _pd()
	_add(air, 3, 0.0, 0.0, 1.0, UiPickData.F_AIR | UiPickData.F_OWN)
	t.eq(UiPicking.pick_ray(o, d, air, V.PICK_UNITS | V.PICK_OWN), -1, "aircraft need PICK_AIR (ViewPicker's rule)")
	t.eq(UiPicking.pick_ray(o, d, air, V.PICK_UNITS | V.PICK_OWN | V.PICK_AIR), 3)
	t.eq(air.slot_of(3), 0)
	t.eq(air.slot_of(99), -1, "an entity absent from the data (fogged) has no slot")


func _rig(size: Vector2i = Vector2i(1920, 1080)) -> Array:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	(Engine.get_main_loop() as SceneTree).root.add_child(vp)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var f: UiSimPortFixture = UiSimPortFixture.blank()
	f.add_player(0, "Me", 1, "roster.napc.canada", 1000)
	f.add_player(1, "Foe", 2, "roster.napc.canada")
	f.set_viewer(0)
	var view := UiViewPortFixture.new(f, 0.0, false)
	view.attach(vp)
	return [vp, f, view]


func test_projection_alignment(t: TestCtx) -> void:
	var rig: Array = await _rig()
	var vp: SubViewport = rig[0]
	var f: UiSimPortFixture = rig[1]
	var view: UiViewPortFixture = rig[2]
	var c: Vector3 = view.focus
	var mid: Vector2i = view.world_to_sim(c)
	f.spawn(TANK, 0, mid.x, mid.y, 11)
	f.spawn(TANK, 1, mid.x + 6144, mid.y, 12)
	f.spawn(BARRACKS, 0, mid.x - 9216, mid.y + 3072, 13)
	view.refresh()
	for id: int in [11, 12, 13]:
		var r: Rect2 = view.entity_screen_rect(id)
		t.gt(r.size.x, 4.0, "entity %d projects to a visible rect" % id)
		t.eq(view.pick(r.get_center(), V.PICK_ANY), id, "picking the centre of the projected rect returns entity %d" % id)
		t.eq(view.pick(r.get_center() + Vector2(0.0, -r.size.y * 3.0), V.PICK_ANY), -1, "well above it is empty ground")
	t.eq(view.pick(Vector2(960.0, 540.0), V.PICK_UNITS | V.PICK_ENEMY), -1, "filters apply through the adapter")
	# the screen centre hits the ground at the focus point
	var g: Vector3 = view.pick_ground(Vector2(960.0, 540.0))
	t.check(g.distance_to(c) < 0.05, "the centre ray hits the focus (got %s)" % g)
	t.eq(view.world_to_sim(view.sim_to_world(12345, 6789)), Vector2i(12345, 6789), "the float -> int step round-trips a sim point")
	t.eq(view.pick_ground(Vector2(960.0, -5000.0)), Vector3.INF, "a ray above the horizon misses")
	vp.queue_free()


func test_fog_hidden_never_picked(t: TestCtx) -> void:
	var rig: Array = await _rig()
	var vp: SubViewport = rig[0]
	var f: UiSimPortFixture = rig[1]
	var view: UiViewPortFixture = rig[2]
	var mid: Vector2i = view.world_to_sim(view.focus)
	f.spawn(TANK, 1, mid.x, mid.y, 21)
	f.hide_entity(21)
	f.spawn(TANK, 0, mid.x + 10240, mid.y, 22)
	var loaded: UiEntityRow = f.spawn(TANK, 0, mid.x - 10240, mid.y, 23)
	loaded.flags |= UiEntityRow.F_LOADED
	var ghost: UiEntityRow = f.spawn(BARRACKS, 1, mid.x, mid.y + 12288, 24)
	f.hide_entity(24)
	ghost.flags |= UiEntityRow.F_GHOST
	view.refresh()
	t.eq(view.pick(Vector2(960.0, 540.0), V.PICK_ANY), -1, "the fogged enemy at the screen centre cannot be picked")
	t.eq(view.pd().slot_of(21), -1)
	t.eq(view.pd().slot_of(23), -1, "a contained unit is not rendered")
	var out: PackedInt32Array = PackedInt32Array()
	view.pick_box(Rect2(0.0, 0.0, 1920.0, 1080.0), V.PICK_ANY, out)
	t.check(not out.has(21) and not out.has(23), "box select never returns them either")
	var rg: Rect2 = view.entity_screen_rect(24)
	t.eq(view.pick(rg.get_center(), V.PICK_ANY), 24, "a remembered structure is pickable with PICK_ANY (hover / inspect)")
	t.eq(view.pick(rg.get_center(), V.PICK_ANY & ~V.PICK_GHOSTS), -1, "and not without PICK_GHOSTS")
	vp.queue_free()


func test_box_select(t: TestCtx) -> void:
	var rig: Array = await _rig()
	var vp: SubViewport = rig[0]
	var f: UiSimPortFixture = rig[1]
	var view: UiViewPortFixture = rig[2]
	var mid: Vector2i = view.world_to_sim(view.focus)
	for i: int in 3:
		f.spawn(TANK, 0, mid.x + i * 2048, mid.y, 31 + i)
	f.spawn(BARRACKS, 0, mid.x + 2048, mid.y + 2048, 40)
	f.spawn(TANK, 1, mid.x + 1024, mid.y, 41)
	view.refresh()
	var box: Rect2 = Rect2(0.0, 0.0, 1920.0, 1080.0)
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(view.pick_box(box, V.PICK_UNITS | V.PICK_OWN, out), 3, "3 own units")
	t.eq(out, PackedInt32Array([31, 32, 33]), "ascending ids")
	t.eq(view.pick_box(box, V.PICK_STRUCTURES | V.PICK_OWN, out), 1)
	t.eq(out, PackedInt32Array([40]), "the structure alone")
	t.eq(view.pick_box(box, V.PICK_UNITS | V.PICK_ENEMY, out), 1)
	t.eq(view.pick_box(Rect2(1900.0, 1060.0, 10.0, 10.0), V.PICK_ANY, out), 0, "an empty corner")
	t.eq(view.pick_box(Rect2(box.end, -box.size), V.PICK_UNITS | V.PICK_OWN, out), 3, "any corner order")
	# behind the camera: excluded
	var pd: UiPickData = _pd()
	var cam: Camera3D = view.camera()
	var behind: Vector3 = cam.global_position - cam.global_transform.basis.z * -20.0
	pd.add(1, behind, behind, 1.0, 2.0, UiPickData.F_OWN)
	t.eq(UiPicking.box_select(cam, pd, box, V.PICK_ANY).size(), 0, "a point behind the camera never projects into the box")
	vp.queue_free()


func test_timing_report(t: TestCtx) -> void:
	var rig: Array = await _rig()
	var vp: SubViewport = rig[0]
	var view: UiViewPortFixture = rig[2]
	var pd: UiPickData = _pd()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 439:
		var p: Vector3 = view.focus + Vector3(rng.randf_range(-50.0, 50.0), 0.0, rng.randf_range(-40.0, 40.0))
		pd.add(i + 1, p, p + Vector3(0.0, 0.9, 0.0), 1.1, 1.8, UiPickData.F_OWN if i % 3 == 0 else 0)
	var cam: Camera3D = view.camera()
	var n: int = 200
	var t0: int = Time.get_ticks_usec()
	var hits: int = 0
	for i: int in n:
		if UiPicking.ray_pick(cam, pd, Vector2(200.0 + float(i) * 7.0, 300.0 + float(i % 20) * 30.0), V.PICK_ANY) >= 0:
			hits += 1
	var ray_us: float = float(Time.get_ticks_usec() - t0) / float(n)
	var box: Rect2 = Rect2(400.0, 250.0, 900.0, 500.0)
	t0 = Time.get_ticks_usec()
	var sel: int = 0
	for i: int in n:
		sel = UiPicking.box_select(cam, pd, box, V.PICK_UNITS | V.PICK_OWN | V.PICK_AIR).size()
	var box_us: float = float(Time.get_ticks_usec() - t0) / float(n)
	t.note("UiPicking at 439 entities: ray_pick %.0f us (%d/%d hits), box_select %.0f us (%d selected); spike reference 127 / 92 us" % [ray_us, hits, n, box_us, sel])
	t.lt(ray_us, 1000.0, "ray pick stays well below a millisecond")
	t.lt(box_us, 1500.0, "box select at 439 entities is below the 1.2 ms of ViewPicker.pick_box (x1.25 slack)")
	vp.queue_free()
