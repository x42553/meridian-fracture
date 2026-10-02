extends RefCounted
## VQ2A regression for the "unexplained SIGABRT on a far-camera shot (zoom 1.0)" of VQ1: the far end of the camera range must stay inside
## every limit the renderer is fed with. A sweep over zoom 0..1, the whole pitch-bias range and eight yaws checks the camera pose
## (finite transform, near < far, near plane >= 2 m), the ground footprint used for culling (finite, bounded), and the shadow fit
## (cascade distance within [MIN_SHADOW_M, MAX_SHADOW_M], ascending splits). The GPU side is exercised by tools/py/far_zoom_probe.py
## (live matches and the terrain lab on Forward+ / Mobile / Compatibility, 3 map families, 192 / 256 maps) and tests/visual/far_zoom_lab.tscn.

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")
const ZOOMS: Array[float] = [0.0, 0.2, 0.35, 0.6, 0.85, 1.0]
const BIASES: Array[float] = [-60.0, -30.0, -10.0, 0.0, 15.0, 40.0, 60.0]


func _cam(size: int) -> ViewCamera:
	var cam: ViewCamera = ViewCamera.new()
	cam.auto_input = false
	cam.edge_scroll_enabled = false
	cam.view_size_override = Vector2(1920.0, 1080.0)
	var ter: ViewTerrain = ViewTerrain.new()
	ter.build(Fx.source(size, func(_x: int, _y: int) -> int: return 0), 2, ViewDetailTextures.build(64), false, false)
	cam.add_child(ter)
	cam.camera = Camera3D.new()
	cam.add_child(cam.camera)
	cam.configure(Rect2(Vector2.ZERO, ter.world_size()), ter)
	return cam


func test_far_camera_poses_stay_finite_and_inside_the_clip_planes(t: TestCtx) -> void:
	var cam: ViewCamera = _cam(96)
	var bad: PackedStringArray = PackedStringArray()
	var n: int = 0
	for z: float in ZOOMS:
		for b: float in BIASES:
			for yi: int in 8:
				cam.snap_to(Vector2(144.0, 144.0), float(yi) * 45.0, z, b)
				cam.advance(0.0)
				var xf: Transform3D = cam.camera.transform
				var tag: String = "zoom %.2f bias %.0f yaw %d" % [z, b, yi * 45]
				n += 1
				if not (xf.origin.is_finite() and xf.basis.x.is_finite() and xf.basis.y.is_finite() and xf.basis.z.is_finite()):
					bad.append(tag + " transform")
					continue
				if not (cam.camera.near >= 2.0 and cam.camera.near < cam.camera.far and cam.camera.far <= 2000.0):
					bad.append("%s clip planes %.1f .. %.1f" % [tag, cam.camera.near, cam.camera.far])
				var r: Rect2 = cam.visible_ground_rect()
				if not (r.position.is_finite() and r.size.is_finite()) or r.size.x > 3000.0 or r.size.y > 3000.0:
					bad.append("%s ground rect %s" % [tag, r])
				var h: float = cam.current_height()
				if not (h >= cam.height_min - 0.01 and h <= cam.height_max + 0.01):
					bad.append("%s height %.1f" % [tag, h])
	t.eq(n, ZOOMS.size() * BIASES.size() * 8, "poses checked")
	t.eq(bad.size(), 0, "bad poses: %s" % " | ".join(bad))
	cam.free()


func test_shadow_fit_is_bounded_over_the_whole_camera_range(t: TestCtx) -> void:
	var a: ViewAtmosphere = ViewAtmosphere.new()
	a.setup()
	var cam: ViewCamera = ViewCamera.new()
	var worst: float = 0.0
	var lo: float = INF
	for z: float in ZOOMS:
		for b: float in BIASES:
			var h: float = cam._height_of(z)
			var pitch: float = clampf(cam._base_pitch_deg(z) + b, ViewCamera.PITCH_MIN_DEG, ViewCamera.PITCH_MAX_DEG)
			var near: float = a.fit_shadows(h, pitch, cam.fov_deg)
			var d: float = a.sun.directional_shadow_max_distance
			worst = maxf(worst, d)
			lo = minf(lo, d)
			t.check(is_finite(near) and near >= 2.0 and near < ViewCamera.FAR_M, "near plane %.1f at zoom %.2f bias %.0f" % [near, z, b])
			t.check(is_finite(d) and d >= ViewAtmosphere.MIN_SHADOW_M and d <= ViewAtmosphere.MAX_SHADOW_M, "shadow distance %.1f at zoom %.2f bias %.0f" % [d, z, b])
			t.check(a.sun.directional_shadow_split_1 < a.sun.directional_shadow_split_2 and a.sun.directional_shadow_split_2 < a.sun.directional_shadow_split_3, "splits ascend")
	t.le(worst, ViewAtmosphere.MAX_SHADOW_M, "largest cascade distance %.1f" % worst)
	t.ge(lo, ViewAtmosphere.MIN_SHADOW_M, "smallest cascade distance %.1f" % lo)
	# the default framing is unchanged by the cap (art direction numbers of test_view_atmosphere)
	var near0: float = a.fit_shadows(84.0, cam._base_pitch_deg(1.0), cam.fov_deg)
	t.near(a.sun.directional_shadow_max_distance, 141.0, 1.0, "H 84 default pitch keeps its 141 m")
	t.near(near0, 50.4, 0.01, "near plane at H 84")
	cam.free()
	a.free()


func test_far_zoom_is_the_far_end_of_the_height_curve(t: TestCtx) -> void:
	var cam: ViewCamera = ViewCamera.new()
	t.near(cam._height_of(1.0), cam.height_max, 0.001, "zoom 1.0 = height_max")
	t.near(cam._height_of(0.0), cam.height_min, 0.001, "zoom 0.0 = height_min")
	t.ge(ViewCamera.FAR_M, cam.height_max / sin(deg_to_rad(ViewCamera.PITCH_MIN_DEG)), "far plane covers the ground below the lowest pitch")
	cam.free()
