extends RefCounted
## VIEW-05: camera rules of render 5.4 and the API of 3.3.

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")


func _cam(flat: bool = true) -> ViewCamera:
	var c: ViewCamera = ViewCamera.new()
	c.auto_input = false
	c.edge_scroll_enabled = false
	c.view_size_override = Vector2(1920.0, 1080.0)
	c.map_rect = Rect2(0.0, 0.0, 576.0, 576.0)
	if flat:
		c.height_func = func(_x: float, _z: float) -> float: return 0.0
		c.ground_pick_func = func(o: Vector3, d: Vector3) -> Vector3:
			if d.y >= -0.0001:
				return Vector3.INF
			return o + d * (-o.y / d.y)
	return c


func _free(c: ViewCamera) -> void:
	c.free()


func test_zoom_table(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	c.snap_to(Vector2(288.0, 288.0), 0.0, 0.0)
	t.near(c.current_height(), 34.0, 1e-4, "zoom 0 height")
	t.near(c.current_pitch_deg(), 46.0, 1e-4, "zoom 0 pitch")
	c.snap_to(Vector2(288.0, 288.0), 0.0, 0.5)
	t.near(c.current_height(), 54.625, 1e-3, "zoom 0.5 height")
	t.near(c.current_pitch_deg(), 52.1875, 1e-3, "zoom 0.5 pitch")
	var dist: float = c.camera.position.distance_to(c.current_focus())
	t.near(dist, 69.1, 0.1, "zoom 0.5 distance")
	c.snap_to(Vector2(288.0, 288.0), 0.0, 1.0)
	t.near(c.current_height(), 84.0, 1e-4, "zoom 1 height")
	t.near(c.current_pitch_deg(), 61.0, 1e-4, "zoom 1 pitch")
	t.near(c.camera.near, 50.4, 1e-3, "near plane 0.6 H")
	_free(c)


func test_snap_and_centre_ray(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	c.snap_to(Vector2(200.0, 250.0), 33.0, 0.4)
	c.advance(0.0)
	var centre: Vector2 = c.view_size_override * 0.5
	var g: Vector3 = c.screen_to_ground(centre)
	t.near(g.x, 200.0, 0.05, "centre ray hits the focus x")
	t.near(g.z, 250.0, 0.05, "centre ray hits the focus z")
	_free(c)


func test_clamp_and_edge_scroll(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	c.snap_to(Vector2(-100.0, -100.0), 0.0, 0.0)
	t.near(c.current_focus().x, 14.0, 1e-4, "focus x clamped to 14")
	t.near(c.current_focus().z, 14.0, 1e-4, "focus z clamped to 14")
	_free(c)
	t.eq(ViewCamera.edge_scroll_dir(Vector2(5.0, 540.0), Vector2(1920.0, 1080.0), 10), Vector2(-1.0, 0.0), "left edge")
	t.eq(ViewCamera.edge_scroll_dir(Vector2(1915.0, 1075.0), Vector2(1920.0, 1080.0), 10), Vector2(1.0, 1.0), "bottom right corner")
	t.eq(ViewCamera.edge_scroll_dir(Vector2(-1.0, 5.0), Vector2(1920.0, 1080.0), 10), Vector2(0.0, 0.0), "outside the window")


func test_smoothing_is_frame_rate_independent(t: TestCtx) -> void:
	var a: ViewCamera = _cam()
	var b: ViewCamera = _cam()
	a.snap_to(Vector2(288.0, 288.0), 0.0, 0.3)
	b.snap_to(Vector2(288.0, 288.0), 0.0, 0.3)
	a.pan_world(Vector2(60.0, -40.0))
	b.pan_world(Vector2(60.0, -40.0))
	a.zoom_by(3.0)
	b.zoom_by(3.0)
	a.rotate_yaw(40.0)
	b.rotate_yaw(40.0)
	for i: int in 60:
		a.advance(1.0 / 60.0)
	for i: int in 30:
		b.advance(1.0 / 30.0)
	t.le(a.current_focus().distance_to(b.current_focus()), 0.001, "focus after 1 s: 60 x 1/60 == 30 x 1/30 within 1 mm")
	t.near(a.current_height(), b.current_height(), 0.001, "height")
	t.near(a.current_yaw_deg(), b.current_yaw_deg(), 0.001, "yaw")
	_free(a)
	_free(b)


func test_pan_speed_is_constant_on_screen(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	c.snap_to(Vector2(288.0, 288.0), 0.0, 0.0)
	var d0: float = c.camera.position.distance_to(c.current_focus())
	c.pan_screen(Vector2(0.0, -1.0), 1.0)
	c.advance(20.0)
	t.near(288.0 - c.current_focus().z, 1.1 * d0, 0.05, "1 s of pan = pan_speed x distance metres toward the top of the screen")
	_free(c)


func test_shake(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	c.snap_to(Vector2(288.0, 288.0), 0.0, 0.0)
	c.add_shake(1.0)
	c.advance(0.25)
	t.near(c.trauma(), 0.6, 1e-4, "trauma at 0.25 s")
	c.advance(0.375)
	t.near(c.trauma(), 0.0, 1e-4, "trauma at 0.625 s")
	t.near(c.current_focus().x, 288.0, 1e-4, "focus unaffected by shake")
	t.near(c.current_focus().z, 288.0, 1e-4, "focus z unaffected")
	c.add_shake(5.0)
	t.near(c.trauma(), 1.0, 1e-6, "trauma capped at 1")
	_free(c)


func test_cinematic(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	c.snap_to(Vector2(288.0, 288.0), 0.0, 0.4)
	var events: Array[bool] = []
	c.cinematic_changed.connect(func(active: bool) -> void: events.append(active))
	var keys: Array[Dictionary] = [
		{"t": 4.0, "focus": Vector3(40.0, 0.0, 0.0), "yaw_deg": 0.0, "height": 40.0, "pitch_deg": 50.0},
		{"t": 0.0, "focus": Vector3(0.0, 0.0, 0.0), "yaw_deg": 0.0, "height": 40.0, "pitch_deg": 50.0}]
	c.cinematic_play(keys)
	t.check(c.is_cinematic(), "cinematic running")
	c.advance(2.0)
	t.near(c.current_focus().x, 20.0, 0.01, "focus.x at t = 2")
	c.advance(2.0)
	t.near(c.current_focus().x, 40.0, 0.01, "focus.x at t = 4")
	c.advance(1.0)  # 0.6 s blend back, then done
	t.check(not c.is_cinematic(), "finished after the blend back")
	t.eq(events, [true, false] as Array[bool], "cinematic_changed emitted once each way")
	t.near(c.current_focus().x, 288.0, 0.05, "player pose restored")
	_free(c)


func test_visible_ground_rect_footprint(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	c.snap_to(Vector2(288.0, 288.0), 0.0, 0.0)
	c.advance(0.0)
	var r: Rect2 = c.visible_ground_rect().grow(-ViewCamera.RECT_GROW_M)
	t.note("footprint at H = 34: %.1f x %.1f m (AABB, yaw 0)" % [r.size.x, r.size.y])
	t.near(r.size.y, 51.0, 51.0 * 0.1, "footprint depth ~51 m at H = 34")
	t.gt(r.size.x, 80.0, "top edge is ~90 m wide")
	t.lt(r.size.x, 100.0, "top edge width")
	_free(c)


func test_focus_on_centres_in_the_free_area(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	c.snap_to(Vector2(288.0, 288.0), 20.0, 0.4)
	var size: Vector2 = c.view_size_override
	c.view_margin_px = Vector4(0.0, 0.0, size.x * 0.25, 0.0)  # HUD covers the right quarter
	var p: Vector3 = Vector3(300.0, 0.0, 260.0)
	c.focus_on(p, true)
	var s: Vector2 = c.world_to_screen(p)
	t.near(s.x, size.x * 0.375, size.x * 0.01, "target lands at the centre of the HUD-free area")
	t.near(s.y, size.y * 0.5, size.y * 0.02, "vertical centre")
	c.view_margin_px = Vector4.ZERO
	c.focus_on_sim(51200, 30720, true)
	t.near(c.current_focus().x, 150.0, 0.5, "focus_on_sim x")
	_free(c)


func test_start_anchor_follows_the_margins_until_the_player_moves(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	var size: Vector2 = c.view_size_override
	c.snap_to(Vector2(288.0, 288.0), 0.0, 0.35)
	c.start_anchor = Vector2(288.0, 288.0)
	c.set_view_margins(Vector4(0.0, 0.0, size.x * 0.25, 0.0))
	var s: Vector2 = c.world_to_screen(Vector3(288.0, 0.0, 288.0))
	t.near(s.x, size.x * 0.375, size.x * 0.01, "the start point sits at the centre of the HUD-free area")
	c.set_view_margins(Vector4(0.0, 0.0, size.x * 0.1, 0.0))  # the HUD layout changed: still anchored, not shifted twice
	s = c.world_to_screen(Vector3(288.0, 0.0, 288.0))
	t.near(s.x, size.x * 0.45, size.x * 0.01, "re-anchored to the new free area")
	c.pan_world(Vector2(5.0, 0.0))
	t.check(not is_finite(c.start_anchor.x), "a player pan releases the anchor")
	var f: Vector3 = c.current_focus()
	c.set_view_margins(Vector4(0.0, 0.0, size.x * 0.3, 0.0))
	t.eq(c.current_focus(), f, "margins no longer move a released camera")
	_free(c)


func test_set_pose_and_orbit_limits(t: TestCtx) -> void:
	var c: ViewCamera = _cam()
	c.set_pose(96.0, 96.0, 45.0, 60.0, 0.5)
	t.near(c.current_focus().x, 288.0, 1e-3, "set_pose in cells")
	t.near(c.current_pitch_deg(), 60.0, 1e-3, "absolute pitch")
	t.near(c.current_yaw_deg(), 45.0, 1e-3, "yaw")
	c.set_pose(96.0, 96.0, 0.0, 10.0, 0.5)
	t.near(c.current_pitch_deg(), 22.0, 1e-3, "pitch clamped to 22")
	c.snap_to(Vector2(288.0, 288.0), 0.0, 0.5)
	c.tilt(50.0)
	c.advance(5.0)
	t.near(c.current_pitch_deg(), 52.1875 + 14.0, 0.01, "tilt bias limited to +14")
	c.rotate_yaw(90.0)
	c.reset_orientation()
	c.advance(5.0)
	t.near(c.current_yaw_deg(), 0.0, 0.01, "reset_orientation")
	_free(c)


func test_terrain_follow_and_configure(t: TestCtx) -> void:
	var ter: ViewTerrain = ViewTerrain.new()
	var slope: Callable = func(cx: int, _cy: int) -> int: return cx * 12
	ter.build(Fx.source(96, slope), 2, ViewDetailTextures.build(64), false)
	var c: ViewCamera = _cam(false)
	c.configure(Rect2(Vector2.ZERO, ter.world_size()), ter)
	c.snap_to(Vector2(100.0, 100.0), 0.0, 0.3)
	t.near(c.current_focus().y, ter.height_at(100.0, 100.0), 0.01, "focus follows the terrain height")
	var g: Vector3 = c.screen_to_ground(c.view_size_override * 0.5)
	t.near(g.x, 100.0, 0.1, "picking through the terrain raycast")
	t.near(g.y, ter.height_at(g.x, g.z), 0.05, "hit lies on the surface")
	_free(c)
	ter.free()


func test_input_actions_do_not_override_bindings(t: TestCtx) -> void:
	var probe: StringName = &"cam_reset"
	if InputMap.has_action(probe):
		InputMap.erase_action(probe)
	InputMap.add_action(probe)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = KEY_F12
	InputMap.action_add_event(probe, ev)
	ViewCamera.ensure_input_actions()
	ViewCamera.ensure_input_actions()
	t.eq(InputMap.action_get_events(probe).size(), 1, "user binding kept, nothing appended")
	for a: StringName in [&"cam_pan_left", &"cam_pan_right", &"cam_pan_up", &"cam_pan_down", &"cam_rotate_left", &"cam_rotate_right", &"cam_zoom_in", &"cam_zoom_out", &"cam_orbit"]:
		t.check(InputMap.has_action(a), "%s registered" % a)
	t.eq(InputMap.action_get_events(&"cam_pan_left").size(), 1, "arrows only: WASD off by default")
	InputMap.erase_action(probe)
