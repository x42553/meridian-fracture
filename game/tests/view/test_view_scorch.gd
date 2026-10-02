extends RefCounted
## VIEW-04: scorch / tread layer (paint <= 5 us, flush <= 1.2 ms) and blob shadows.

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")


func _layer(res: int = 1024) -> ViewScorchLayer:
	var s: ViewScorchLayer = ViewScorchLayer.new()
	s.setup(Vector2(576.0, 576.0), res)
	return s


func test_paint_marks_and_alpha(t: TestCtx) -> void:
	var s: ViewScorchLayer = _layer()
	var p: Vector2 = Vector2(200.0, 300.0)
	t.eq(s.alpha_at(p), 0.0, "clean layer")
	s.paint(p, 3.0, ViewScorchLayer.Kind.SCORCH)
	t.gt(s.alpha_at(p), 0.5, "scorch is opaque at the centre")
	t.eq(s.alpha_at(p + Vector2(20.0, 0.0)), 0.0, "and clean 20 m away")
	s.paint(Vector2(400.0, 100.0), 4.0, ViewScorchLayer.Kind.CRATER)
	t.gt(s.alpha_at(Vector2(400.0, 100.0)), 0.5, "crater")
	s.paint(Vector2(100.0, 100.0), 2.5, ViewScorchLayer.Kind.RUBBLE_STAIN)
	t.gt(s.alpha_at(Vector2(100.0, 100.0)), 0.2, "rubble stain")
	t.eq(s.painted, 3, "paint counter")
	s.paint(Vector2(-50.0, -50.0), 3.0)
	s.paint(Vector2(600.0, 600.0), 30.0)
	t.eq(s.painted, 5, "marks outside the map are clipped, not errors")


func test_stamp_size_follows_radius(t: TestCtx) -> void:
	var s: ViewScorchLayer = _layer()
	s.paint(Vector2(100.0, 100.0), 1.0)
	var small: float = 0.0
	for dx: int in range(-30, 31, 2):
		small += 1.0 if s.alpha_at(Vector2(100.0 + float(dx) * 0.5, 100.0)) > 0.05 else 0.0
	s.paint(Vector2(300.0, 300.0), 12.0)
	var big: float = 0.0
	for dx: int in range(-30, 31, 2):
		big += 1.0 if s.alpha_at(Vector2(300.0 + float(dx) * 0.5, 300.0)) > 0.05 else 0.0
	t.gt(big, small, "a 12 m mark covers more texels than a 1 m mark")


func test_tread_marks_are_faint_and_accumulate(t: TestCtx) -> void:
	var s: ViewScorchLayer = _layer()
	var a: Vector2 = Vector2(100.0, 100.0)
	var b: Vector2 = Vector2(110.0, 100.0)
	s.paint_tread(a, b, 1.1)
	var mid: Vector2 = Vector2(105.0, 100.0)
	var once: float = s.alpha_at(mid)
	t.gt(once, 0.02, "tread leaves a mark along the segment")
	t.lt(once, 0.4, "but it is faint")
	s.paint_tread(a, b, 1.1)
	t.gt(s.alpha_at(mid), once, "a second pass darkens it")
	t.eq(s.alpha_at(Vector2(105.0, 106.0)), 0.0, "and it stays in its lane")


func test_paint_and_flush_cost(t: TestCtx) -> void:
	var s: ViewScorchLayer = _layer()
	var best: float = 1.0e9
	for pass_i: int in 4:
		var t0: int = Time.get_ticks_usec()
		for i: int in 400:
			s.paint(Vector2(20.0 + float(i % 20) * 25.0, 20.0 + float(i / 20) * 25.0), 3.0)
		best = minf(best, float(Time.get_ticks_usec() - t0) / 400.0)
	t.note("scorch.paint (3 m mark, 1024^2): %.2f us" % best)
	t.le(best, 5.0 * TestCtx.perf_factor(), "paint <= 5 us (x perf_factor)")
	var flush_best: int = 1 << 30
	for i: int in 6:
		s.paint(Vector2(50.0, 50.0), 3.0)
		s.flush()
		flush_best = mini(flush_best, s.last_flush_us)
	t.note("scorch.flush (1024^2 RGBA8): %d us" % flush_best)
	t.le(flush_best, 1200, "flush <= 1.2 ms")
	t.check(not s.flush(), "nothing dirty: no upload")
	t.eq(s.flushes, 6, "flush counter")


func _terrain() -> ViewTerrain:
	var ter: ViewTerrain = ViewTerrain.new()
	ter.build(Fx.source(96), 2, ViewDetailTextures.build(64), false, false)
	return ter


func test_blob_shadows_follow_the_ground(t: TestCtx) -> void:
	var ter: ViewTerrain = _terrain()
	var b: ViewBlobShadows = ViewBlobShadows.new()
	b.setup(64)
	var pos: PackedVector3Array = PackedVector3Array([Vector3(100.0, 0.0, 100.0), Vector3(150.0, 30.0, 60.0)])
	b.update(ter, pos, PackedFloat32Array([1.5, 2.0]), PackedFloat32Array([1.0, 0.25]))
	t.eq(b.shown, 2, "two blobs shown")
	var mm: MultiMesh = b._mmi.multimesh
	t.eq(mm.visible_instance_count, 2, "visible_instance_count")
	var buf: PackedFloat32Array = b._buf
	t.eq(buf.size(), 64 * ViewBlobShadows.FLOATS, "buffer always covers the whole capacity")
	# row-major 3x4: [xx yx zx ox, xy yy zy oy, xz yz zz oz, r g b a]
	var up: Vector3 = Vector3(buf[1], buf[5], buf[9])
	t.near(buf[7], ter.height_at(100.0, 100.0) + ViewBlobShadows.LIFT_M, 1e-3, "quad sits just above the ground")
	t.gt(up.dot(ter.normal_at(100.0, 100.0)), 0.97, "quad normal follows the (cell-cached) terrain normal")
	t.near(up.length(), 1.0, 1e-4, "unit normal")
	t.near(Vector3(buf[0], buf[4], buf[8]).length(), 3.0, 1e-3, "diameter = 2 x radius")
	t.near(buf[ViewBlobShadows.FLOATS + 15], 0.25, 1e-4, "per-blob alpha")
	t.near(buf[15], 1.0, 1e-4, "default alpha 1")
	b.update(ter, PackedVector3Array(), PackedFloat32Array())
	t.eq(mm.visible_instance_count, 0, "empty update hides all")
	b.free()
	ter.free()


func test_blob_shadow_update_cost(t: TestCtx) -> void:
	var ter: ViewTerrain = _terrain()
	var b: ViewBlobShadows = ViewBlobShadows.new()
	b.setup(512)
	var pos: PackedVector3Array = PackedVector3Array()
	var rad: PackedFloat32Array = PackedFloat32Array()
	for i: int in 400:
		pos.append(Vector3(20.0 + float(i % 20) * 12.0, 0.0, 20.0 + float(i / 20) * 12.0))
		rad.append(1.4)
	var best: int = 1 << 30
	for i: int in 8:
		b.update(ter, pos, rad)
		best = mini(best, b.last_update_us)
	t.note("blob shadow update, 400 units: %d us" % best)
	t.lt(best, 1200, "400 units < 1.2 ms (spike 0.8-1.2 ms before the normal cache)")
	b.free()
	ter.free()
