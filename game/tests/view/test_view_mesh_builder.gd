extends RefCounted
## VIEW-M1 acceptance: ViewMeshBuilder counts, winding, mirror, scale, part encoding, sockets, determinism.

const Mat := ViewMeshBuilder.Mat
const Pt := ViewMeshBuilder.Part


func _b() -> ViewMeshBuilder:
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	b.seed_rng(7)
	return b


## Fraction of LOD0 triangles whose right-hand normal points into the solid (clockwise front faces).
func _inward_fraction(d: Dictionary, centre: Vector3) -> float:
	var arrays: Array = d["arrays"] as Array
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var good: int = 0
	var n: int = idx.size() / 3
	for t in n:
		var a: Vector3 = pos[idx[t * 3]]
		var bb: Vector3 = pos[idx[t * 3 + 1]]
		var c: Vector3 = pos[idx[t * 3 + 2]]
		var nrm: Vector3 = (bb - a).cross(c - a)
		if nrm.dot((a + bb + c) / 3.0 - centre) < 0.0:
			good += 1
	return float(good) / float(maxi(n, 1))


## Fraction of LOD0 triangles whose right-hand normal opposes the stored (outward) vertex normal: valid for non-convex solids.
func _normal_fraction(d: Dictionary) -> float:
	var arrays: Array = d["arrays"] as Array
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var good: int = 0
	var n: int = idx.size() / 3
	for t in n:
		var a: int = idx[t * 3]
		var geo: Vector3 = (pos[idx[t * 3 + 1]] - pos[a]).cross(pos[idx[t * 3 + 2]] - pos[a])
		if geo.dot(nrm[a]) < 0.0:
			good += 1
	return float(good) / float(maxi(n, 1))


func test_box_counts(t: TestCtx) -> void:
	var b: ViewMeshBuilder = _b()
	b.box(Vector3.ZERO, Vector3.ONE, 0.0)
	t.eq(b.vertex_count(), 24, "plain box vertices")
	t.eq(b.triangle_count(), 12, "plain box triangles")
	var b2: ViewMeshBuilder = _b()
	b2.box(Vector3.ZERO, Vector3.ONE, 0.05)
	t.eq(b2.vertex_count(), 120, "bevelled box vertices")
	t.eq(b2.tier_triangle_counts(), Vector3i(44, 12, 12), "bevelled box tris (LOD0, LOD1, LOD2)")
	var mesh: ArrayMesh = b2.build("box")
	t.eq(mesh.get_surface_count(), 1, "one surface")
	t.not_null(mesh, "mesh built")


func test_winding_is_clockwise_front(t: TestCtx) -> void:
	var b: ViewMeshBuilder = _b()
	b.box(Vector3.ZERO, Vector3(1.0, 2.0, 3.0), 0.05)
	t.eq(_inward_fraction(b.build_arrays(), Vector3.ZERO), 1.0, "bevelled box")
	var p: ViewMeshBuilder = _b()
	p.prism(ViewMeshBuilder.ngon(Vector3(0.0, -0.5, 0.0), 1.0, 0.8, 8, 22.5), ViewMeshBuilder.ngon(Vector3(0.0, 0.5, 0.0), 0.7, 0.6, 8, 22.5), 0.03)
	t.eq(_inward_fraction(p.build_arrays(), Vector3.ZERO), 1.0, "octagonal prism")
	var l: ViewMeshBuilder = _b()
	l.cylinder(Vector3(0.0, -1.0, 0.0), Vector3(0.0, 1.0, 0.0), 0.5, 12, 0.05)
	t.eq(_inward_fraction(l.build_arrays(), Vector3.ZERO), 1.0, "lathe cylinder")
	var e: ViewMeshBuilder = _b()
	e.extrude(PackedVector2Array([Vector2(-1, 0), Vector2(-1, 1), Vector2(1, 0.4), Vector2(1, 0)]), -0.5, 0.5, 0.02)
	t.eq(_inward_fraction(e.build_arrays(), Vector3(0.0, 0.4, 0.0)), 1.0, "extruded profile")
	var pk: ViewMeshBuilder = _b()
	var pockets: Array[Rect2] = [Rect2(0.2, 0.2, 0.5, 0.5)]
	pk.pocket_box(Vector3.ZERO, Vector3(2.0, 0.4, 2.0), pockets, 0.1)
	t.eq(_normal_fraction(pk.build_arrays()), 1.0, "pocket box")
	var tb: ViewMeshBuilder = _b()
	var circles: Array[Vector3] = [Vector3(1.0, 0.4, 0.4), Vector3(-1.0, 0.4, 0.4)]
	tb.set_part(Pt.TRACK)
	tb.track_belt(0.0, 0.4, circles, 0.06)
	t.eq(_normal_fraction(tb.build_arrays()), 1.0, "track belt")


func test_mirror_x(t: TestCtx) -> void:
	var b: ViewMeshBuilder = _b()
	var m: PackedInt32Array = b.mark()
	b.set_part(Pt.TURRET, Vector3(0.5, 1.0, 0.0))
	b.box(Vector3(1.0, 0.5, 0.0), Vector3(0.4, 0.4, 0.4), 0.0)
	var n0: int = b.vertex_count()
	b.mirror_x(m)
	t.eq(b.vertex_count(), n0 * 2, "vertices double")
	var d: Dictionary = b.build_arrays()
	var arrays: Array = d["arrays"] as Array
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	t.near(pos[n0].x, -pos[0].x, 1.0e-6, "x negated")
	t.near(pos[n0].y, pos[0].y, 1.0e-6, "y kept")
	var raw: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM1] as PackedByteArray
	t.near(raw.decode_half(0), 0.5, 0.004, "pivot x of the original")
	t.near(raw.decode_half(n0 * 8), -0.5, 0.004, "pivot x mirrored")
	t.eq(_normal_fraction(d), 1.0, "mirrored winding valid (against the mirrored normals)")


func test_model_scale(t: TestCtx) -> void:
	var a: ViewMeshBuilder = _b()
	a.box(Vector3(1.0, 1.0, 1.0), Vector3(2.0, 2.0, 2.0), 0.0)
	a.build_arrays()
	var s: ViewMeshBuilder = _b()
	s.model_scale = 1.25
	s.box(Vector3(1.0, 1.0, 1.0), Vector3(2.0, 2.0, 2.0), 0.0)
	s.build_arrays()
	t.near(s.info().rest_aabb.size.x, a.info().rest_aabb.size.x * 1.25, 1.0e-5, "AABB scaled by 1.25")
	t.near(s.info().height, a.info().height * 1.25, 1.0e-5, "height scaled")
	t.near(s.info().radius, a.info().radius * 1.25, 1.0e-5, "radius scaled")


func test_half_pivot_error(t: TestCtx) -> void:
	var worst: float = 0.0
	for v: float in [0.013, 1.234, -3.777, 7.9, -7.99, 9.4, 12.3, -15.5]:
		var b: ViewMeshBuilder = _b()
		b.set_part(Pt.TURRET, Vector3(v, v * 0.5, -v))
		b.box(Vector3.ZERO, Vector3.ONE, 0.0)
		var raw: PackedByteArray = (b.build_arrays()["arrays"] as Array)[Mesh.ARRAY_CUSTOM1] as PackedByteArray
		var lim: float = 0.004 if absf(v) < 8.0 else 0.008
		var err: float = absf(raw.decode_half(0) - v)
		worst = maxf(worst, err)
		t.le(err, lim, "half pivot error at %.3f" % v)
	t.lt(worst, 0.008, "worst pivot error < 8 mm")


func test_float_fallback_for_large_pivot(t: TestCtx) -> void:
	var b: ViewMeshBuilder = _b()
	b.set_part(Pt.SLIDE_Y, Vector3(20.0, 0.0, 0.0), 0.0, 3.0)
	b.box(Vector3.ZERO, Vector3.ONE, 0.0)
	var arr: Array = b.build_arrays()["arrays"] as Array
	t.check(arr[Mesh.ARRAY_CUSTOM1] is PackedFloat32Array, "pivot beyond 15.9 m switches CUSTOM1 to float")
	var mesh: ArrayMesh = b.build("big")
	t.eq(mesh.get_surface_count(), 1, "float custom1 mesh builds")


func test_custom_aabb_covers_sweep(t: TestCtx) -> void:
	var b: ViewMeshBuilder = _b()
	b.box(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 3.0), 0.0)
	b.set_part(Pt.TURRET, Vector3(0.0, 1.0, 0.0))
	b.box(Vector3(0.0, 1.3, -1.5), Vector3(0.2, 0.2, 2.0), 0.0)
	var mesh: ArrayMesh = b.build("t")
	var rest: AABB = mesh.get_meta("rest_aabb") as AABB
	t.check(mesh.custom_aabb.encloses(rest), "custom_aabb encloses the rest AABB")
	# the barrel tip swings to +-x at 2.5 m from the pivot
	t.check(mesh.custom_aabb.has_point(Vector3(2.4, 1.0, 0.0)), "custom_aabb covers a turret swing")


func test_gait_members_and_wheel(t: TestCtx) -> void:
	var b: ViewMeshBuilder = _b()
	b.member(2, 4)
	b.set_part(Pt.LEG_A, Vector3(0.0, 0.45, 0.0), 0.31)
	b.box(Vector3(0.0, 0.2, 0.0), Vector3(0.1, 0.4, 0.1), 0.0)
	b.member(0, 0)
	b.clear_part()
	b.wheel(Vector3(1.0, 0.4, 0.0), 0.4, 0.3, Color.BLACK, Color.GRAY, 1, 10)
	var arrays: Array = b.build_arrays()["arrays"] as Array
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
	var c0: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0] as PackedByteArray
	var c1: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM1] as PackedByteArray
	t.eq(uv2[0], Vector2(2.0, 4.0), "gait UV2 = (member index, count)")
	t.eq(int(c0[1]), Pt.LEG_A, "leg kind in CUSTOM0.y")
	t.eq(int(c0[3]), 0, "CUSTOM0.w unused (Compatibility drops it)")
	t.eq(b.info().members, 4, "members recorded")
	var found: bool = false
	for i in b.vertex_count():
		if int(c0[i * 4 + 1]) == Pt.WHEEL:
			t.near(c1.decode_half(i * 8 + 6), 0.4, 0.001, "wheel extra = radius")
			found = true
			break
	t.check(found, "wheel part present")
	t.check(b.info().has_part(Pt.WHEEL) and b.info().has_part(Pt.LEG_A) and not b.info().has_part(Pt.TURRET), "parts mask")


func test_determinism(t: TestCtx) -> void:
	var h: Array[int] = []
	for i in 2:
		var b: ViewMeshBuilder = ViewMeshBuilder.new()
		b.seed_rng(99)
		b.default_bevel = 0.04
		b.brush(Color(0.3, 0.4, 0.2))
		b.box(Vector3.ZERO, Vector3(2.0, 1.0, 3.0))
		var tri: Array[Vector3] = [Vector3(0, 0, 0)]
		b.greebles(Vector3(0.0, 0.5, 0.0), Vector3.UP, Vector3(0.8, 0.0, 0.0), Vector3(0.0, 0.0, 1.2), 6, 0.1, 0.2, 0.03, 0.08)
		b.build_arrays()
		h.append(b.info().content_hash)
		t.eq(tri.size(), 1, "sanity")
	t.eq(h[0], h[1], "identical seeds give identical content hash")
	var c: ViewMeshBuilder = ViewMeshBuilder.new()
	c.seed_rng(100)
	c.default_bevel = 0.04
	c.box(Vector3.ZERO, Vector3(2.0, 1.0, 3.0))
	c.greebles(Vector3(0.0, 0.5, 0.0), Vector3.UP, Vector3(0.8, 0.0, 0.0), Vector3(0.0, 0.0, 1.2), 6, 0.1, 0.2, 0.03, 0.08)
	c.build_arrays()
	t.ne(c.info().content_hash, h[0], "a different seed changes the hash")


func test_sockets(t: TestCtx) -> void:
	var b: ViewMeshBuilder = _b()
	var pv: Vector3 = Vector3(0.0, 1.0, 0.0)
	b.set_part(Pt.TURRET, pv)
	b.box(Vector3(0.0, 1.2, 0.0), Vector3(1.0, 0.4, 1.0), 0.0)
	b.set_part(Pt.BARREL, pv, 1.0, 0.3, Vector2(1.2, -0.5))
	b.cylinder(Vector3(0.0, 1.2, -0.5), Vector3(0.0, 1.2, -2.5), 0.05, 8, 0.0)
	b.clear_part()
	b.socket(&"muzzle0_0", Vector3(0.0, 1.2, -2.5), Vector3(0.0, 0.0, -1.0), Pt.BARREL)
	b.socket(&"top", Vector3(0.0, 2.0, 0.0), Vector3.UP)
	b.build_arrays()
	var info: ViewModelInfo = b.info()
	t.check(info.has_socket(&"muzzle0_0") and info.has_socket(&"top"), "sockets stored")
	var rest: Vector3 = info.socket_world(&"muzzle0_0", Transform3D.IDENTITY, 0.0, 0.0, 0.0)
	t.near(rest.z, -2.5, 1.0e-5, "rest muzzle z")
	var yawed: Vector3 = info.socket_world(&"muzzle0_0", Transform3D.IDENTITY, PI * 0.5, 0.0, 0.0)
	t.near(yawed.x, -2.5, 1.0e-4, "turret yaw +90 deg swings the muzzle to -x (CCW from above)")
	var rec: Vector3 = info.socket_world(&"muzzle0_0", Transform3D.IDENTITY, 0.0, 0.0, 1.0)
	t.near(rec.z, -2.2, 1.0e-5, "full recoil pulls the muzzle back by extra")
	var elev: Vector3 = info.socket_world(&"muzzle0_0", Transform3D.IDENTITY, 0.0, 1.0, 0.0)
	t.gt(elev.y, 3.0, "elevation lifts the muzzle (param 1 = 90 deg)")
	var top: Vector3 = info.socket_world(&"top", Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 0.0)), 1.0, 1.0, 1.0)
	t.near(top.x, 5.0, 1.0e-5, "static socket ignores animation")
	t.eq(info.socket_world(&"nope", Transform3D.IDENTITY, 0.0, 0.0, 0.0), Vector3.ZERO, "unknown socket -> origin")


func test_lod_meshes_and_stats(t: TestCtx) -> void:
	var b: ViewMeshBuilder = _b()
	b.default_bevel = 0.04
	b.box(Vector3.ZERO, Vector3.ONE)
	b.tier = 1
	b.box(Vector3(2.0, 0.0, 0.0), Vector3.ONE)
	b.tier = 2
	b.box(Vector3(4.0, 0.0, 0.0), Vector3.ONE)
	var tc: Vector3i = b.tier_triangle_counts()
	t.gt(tc.x, tc.y, "LOD1 has fewer tris")
	t.gt(tc.y, tc.z, "LOD2 has fewer tris than LOD1")
	var mesh: ArrayMesh = b.build("lod")
	t.eq(mesh.get_surface_count(), 1, "single surface")
	t.eq(b.info().tris, tc, "info tri counts")
	t.gt(b.info().build_ms, -1.0, "build_ms recorded")


func test_compat_layout_uses_float_custom0(t: TestCtx) -> void:
	var b: ViewMeshBuilder = _b()
	b.compat_layout = true
	b.set_part(Pt.WHEEL, Vector3(0.0, 0.4, 0.0), 0.5, 0.4)
	b.box(Vector3.ZERO, Vector3.ONE, 0.0)
	var arrays: Array = b.build_arrays()["arrays"] as Array
	t.check(arrays[Mesh.ARRAY_CUSTOM0] is PackedFloat32Array, "CUSTOM0 as float array (Compatibility delivers only x of an RGBA8 attribute)")
	var c0: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array
	t.near(c0[1] * 255.0, float(Pt.WHEEL), 1.0e-4, "part kind survives as byte / 255")
	t.near(c0[2] * 255.0, 128.0, 1.0, "param byte")
	var plain: ViewMeshBuilder = _b()
	plain.set_part(Pt.WHEEL, Vector3(0.0, 0.4, 0.0), 0.5, 0.4)
	plain.box(Vector3.ZERO, Vector3.ONE, 0.0)
	var pc0: PackedByteArray = plain.build_arrays()["arrays"][Mesh.ARRAY_CUSTOM0] as PackedByteArray
	for i in 8:
		t.near(c0[i] * 255.0, float(pc0[i]), 1.0e-3, "same content as the byte layout at %d" % i)
	t.eq(b.build("compat").get_surface_count(), 1, "compat layout mesh builds")
