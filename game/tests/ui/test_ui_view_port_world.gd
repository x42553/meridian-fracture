extends RefCounted
## UI-04b/UI-15 seam: `UiViewPortWorld` over a real `ViewWorld` + `SimWorld` (camera driving, picking, selection push).

const Kit := preload("res://tests/view/vw_kit.gd")
const V = preload("res://src/ui/ui_view_port.gd")


func _rig() -> Array:
	var w: SimWorld = Kit.sim()
	var tank: SimEntity = Kit.tank(w, 0, 48, 48)
	var enemy: SimEntity = Kit.tank(w, 1, 52, 48)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(50.0, 48.5), 0.0)
	Kit.step_frame(vw, 1, 1.0)
	return [w, vw, UiViewPortWorld.new(vw), tank, enemy]


func test_picking_goes_through_the_view_picker(t: TestCtx) -> void:
	var r: Array = _rig()
	var vw: ViewWorld = r[1] as ViewWorld
	var port: UiViewPortWorld = r[2] as UiViewPortWorld
	var tank: SimEntity = r[3] as SimEntity
	var ve: ViewEntity = vw.entity_view(tank.id)
	var sp: Vector2 = vw.camera.world_to_screen(Vector3(ve.wx, ve.wy + 0.5, ve.wz))
	t.eq(port.pick(sp, V.PICK_ANY), tank.id, "click on the tank picks it")
	t.eq(port.pick(Vector2(10.0, 10.0), V.PICK_ANY), -1, "an empty corner picks nothing")
	t.eq(port.pick(sp, V.PICK_UNITS | V.PICK_ENEMY), -1, "the own tank is filtered out by an enemy-only filter")
	var out := PackedInt32Array()
	var n: int = port.pick_box(Rect2(0.0, 0.0, 1920.0, 1080.0), V.PICK_ANY, out)
	t.eq(n, out.size(), "pick_box returns the count")
	t.eq(n, 2, "both tanks are inside the full-screen box")
	t.check(out[0] < out[1], "ids ascending")
	var g: Vector3 = port.pick_ground(sp)
	t.check(g != Vector3.INF, "the ground under the cursor is found")
	var sim: Vector2i = port.world_to_sim(port.sim_to_world(48 * SimConfig.CELL, 48 * SimConfig.CELL))
	t.eq(sim, Vector2i(48 * SimConfig.CELL, 48 * SimConfig.CELL), "sim -> world -> sim round trip")
	t.check(port.entity_screen_rect(tank.id).has_point(sp), "the projected pick volume contains the click")
	Kit.free_view(vw)


func test_camera_is_ui_driven(t: TestCtx) -> void:
	var r: Array = _rig()
	var vw: ViewWorld = r[1] as ViewWorld
	var port: UiViewPortWorld = r[2] as UiViewPortWorld
	t.check(not vw.camera.auto_input, "the adapter turns the rig's own input off")
	t.check(not vw.camera.edge_scroll_enabled, "and its edge scroll")
	var st: Dictionary = port.camera_state()
	port.pan_screen(Vector2(1.0, 0.0), 0.5)
	vw.camera.advance(1.0)
	t.gt(vw.camera.current_focus().x, float(st["focus_x"]), "pan right moves the focus east")
	var saved: Dictionary = port.camera_state()
	port.set_camera_state(st, true)
	t.near(port.camera_state()["focus_x"] as float, st["focus_x"] as float, 0.01, "bookmark restore is exact")
	port.set_camera_state(saved, true)
	t.near(port.camera_state()["focus_x"] as float, saved["focus_x"] as float, 0.01, "and restores the panned pose")
	var q: PackedVector2Array = port.frustum_ground_quad()
	t.eq(q.size(), 4, "the frustum polygon has 4 corners")
	t.gt(port.px_per_metre(), 5.0, "camera scale is sane")
	var pts := PackedVector2Array()
	port.project_points(PackedInt32Array([48 * SimConfig.CELL, 48 * SimConfig.CELL]), pts)
	t.eq(pts.size(), 1, "project_points fills one point per pair")
	Kit.free_view(vw)


func test_selection_push(t: TestCtx) -> void:
	var r: Array = _rig()
	var vw: ViewWorld = r[1] as ViewWorld
	var port: UiViewPortWorld = r[2] as UiViewPortWorld
	var tank: SimEntity = r[3] as SimEntity
	port.set_selection(PackedInt32Array([tank.id]))
	t.eq(vw.selection.selection(), PackedInt32Array([tank.id]), "selection reaches the view rings")
	port.set_hover(tank.id)
	port.set_health_bar_mode(3)
	t.eq(vw.health_bars.mode, 3, "health bar mode reaches the view")
	var ve: ViewEntity = vw.entity_view(tank.id)
	var sp: Vector2 = vw.camera.world_to_screen(ve.pick_centre())
	t.eq(port.pick(sp, V.PICK_ANY), tank.id, "production picking agrees")
	Kit.free_view(vw)
