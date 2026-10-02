extends RefCounted
## VIEW-01: ViewInstanceBuffer stride, capacity and overflow behaviour.


func test_push_commit_and_overflow(t: TestCtx) -> void:
	var root: Node3D = Node3D.new()
	var buf: ViewInstanceBuffer = ViewInstanceBuffer.new()
	buf.setup(root, QuadMesh.new(), null, 3)
	t.eq(ViewInstanceBuffer.STRIDE, 20, "stride 20 floats")
	t.check(buf.multimesh.use_colors and buf.multimesh.use_custom_data, "colour and custom data both enabled (Compatibility pitfall)")
	t.eq(buf.multimesh.instance_count, 3, "capacity")
	buf.begin()
	buf.push(Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)), Color(0.1, 0.2, 0.3, 0.4), Color(0.5, 0.6, 0.7, 0.8))
	buf.push(Transform3D.IDENTITY, Color.WHITE, Color.BLACK)
	buf.push(Transform3D.IDENTITY, Color.WHITE, Color.BLACK)
	buf.push(Transform3D.IDENTITY, Color.WHITE, Color.BLACK)
	buf.push(Transform3D.IDENTITY, Color.WHITE, Color.BLACK)
	t.eq(buf.count, 3, "drops silently at capacity")
	t.eq(buf.overflow, 2, "overflow counted")
	buf.commit()
	t.eq(buf.multimesh.visible_instance_count, 3, "visible count")
	t.eq(buf.multimesh.buffer.size(), 60, "buffer always holds capacity * stride floats")
	var b: PackedFloat32Array = buf.multimesh.buffer
	t.near(b[3], 1.0, 1.0e-6, "origin x")
	t.near(b[7], 2.0, 1.0e-6, "origin y")
	t.near(b[11], 3.0, 1.0e-6, "origin z")
	t.near(b[12], 0.1, 1.0e-6, "colour r")
	t.near(b[15], 0.4, 1.0e-6, "colour a")
	t.near(b[16], 0.5, 1.0e-6, "custom x")
	t.near(b[19], 0.8, 1.0e-6, "custom w")
	buf.begin()
	buf.commit()
	t.eq(buf.multimesh.visible_instance_count, 0, "begin/commit with nothing hides everything")
	t.eq(buf.multimesh.buffer.size(), 60, "buffer size unchanged when fewer instances are visible")
	root.free()


func test_bounds(t: TestCtx) -> void:
	var root: Node3D = Node3D.new()
	var buf: ViewInstanceBuffer = ViewInstanceBuffer.new()
	buf.setup(root, QuadMesh.new(), null, 4)
	buf.set_bounds(Rect2(0.0, 0.0, 576.0, 576.0))
	var bb: AABB = buf.multimesh.custom_aabb
	t.near(bb.position.x, -100.0, 1.0e-4, "map + 100 m margin (min)")
	t.near(bb.end.x, 676.0, 1.0e-4, "map + 100 m margin (max)")
	root.free()
