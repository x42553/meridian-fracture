class_name ViewDecorMeshes
extends RefCounted
## Procedural low-poly decoration meshes (no art files): broadleaf tree, conifer, rock, crystal cluster, scrap pile.
## Each is a single surface built by ViewMeshBuilder; triangle counts are returned by triangle_count().

static func broadleaf(seed_v: int) -> ArrayMesh:
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.27
	trunk.height = 2.7
	trunk.radial_segments = 6
	trunk.rings = 1
	b.add(trunk, Transform3D(Basis.IDENTITY, Vector3(0, 1.35, 0)), Color(0.34, 0.24, 0.15), 0.0, 0.0, 5.6, 0.10, 0.0, seed_v, 0.6)
	var blobs: Array[Vector4] = [Vector4(0.0, 3.7, 0.0, 1.55), Vector4(0.75, 3.2, 0.45, 1.15), Vector4(-0.7, 4.35, -0.4, 1.15), Vector4(0.1, 4.9, 0.3, 0.85)]
	var s: int = 0
	for bl in blobs:
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = bl.w
		sph.height = bl.w * 1.8
		sph.radial_segments = 8
		sph.rings = 5
		b.add(sph, Transform3D(Basis.IDENTITY, Vector3(bl.x, bl.y, bl.z)), Color(1, 1, 1), 1.0, 1.6, 5.8, 1.0, 0.16, seed_v + s, 0.5)
		s += 1
	return b.build(false)


static func conifer(seed_v: int) -> ArrayMesh:
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.22
	trunk.height = 1.6
	trunk.radial_segments = 6
	trunk.rings = 1
	b.add(trunk, Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)), Color(0.30, 0.21, 0.14), 0.0, 0.0, 6.4, 0.05, 0.0, seed_v, 0.6)
	var layers: Array[Vector3] = [Vector3(1.0, 1.9, 1.75), Vector3(2.1, 1.75, 1.4), Vector3(3.1, 1.6, 1.05), Vector3(4.0, 1.45, 0.7)]
	var s: int = 0
	for ly in layers:
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = ly.z
		cone.height = ly.y
		cone.radial_segments = 8
		cone.rings = 1
		cone.cap_bottom = false
		b.add(cone, Transform3D(Basis.IDENTITY, Vector3(0, ly.x + ly.y * 0.5, 0)), Color(0.72, 0.9, 0.78), 1.0, 0.8, 6.2, 1.0, 0.10, seed_v + s, 0.45)
		s += 1
	return b.build(false)


static func rock(seed_v: int) -> ArrayMesh:
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = 0.8
	sph.height = 1.35
	sph.radial_segments = 7
	sph.rings = 4
	b.add(sph, Transform3D(Basis.from_scale(Vector3(1.25, 0.8, 1.0)), Vector3(0, 0.45, 0)), Color(0.27, 0.255, 0.235), 0.0, 0.0, 1.4, 0.0, 0.24, seed_v, 0.6)
	var small: SphereMesh = SphereMesh.new()
	small.radius = 0.4
	small.height = 0.7
	small.radial_segments = 6
	small.rings = 3
	b.add(small, Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.2)), Vector3(0.75, 0.25, 0.3)), Color(0.23, 0.22, 0.21), 0.0, 0.0, 1.4, 0.0, 0.15, seed_v + 5, 0.6)
	return b.build(true)


static func crystal(seed_v: int) -> ArrayMesh:
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	var specs: Array[Vector4] = [Vector4(0.0, 0.0, 1.7, 0.0), Vector4(0.42, 0.12, 1.15, 0.30), Vector4(-0.38, 0.2, 1.3, -0.26), Vector4(0.12, -0.42, 0.9, 0.22), Vector4(-0.15, 0.4, 0.75, -0.32)]
	var s: int = 0
	for sp in specs:
		var h: float = sp.z
		var body: CylinderMesh = CylinderMesh.new()
		body.top_radius = 0.13
		body.bottom_radius = 0.2
		body.height = h
		body.radial_segments = 6
		body.rings = 1
		body.cap_top = false
		var tip: CylinderMesh = CylinderMesh.new()
		tip.top_radius = 0.0
		tip.bottom_radius = 0.13
		tip.height = 0.4
		tip.radial_segments = 6
		tip.rings = 1
		var tilt: Basis = Basis(Vector3.FORWARD, sp.w) * Basis(Vector3.RIGHT, sp.w * 0.7)
		var origin: Vector3 = Vector3(sp.x, 0.0, sp.y)
		b.add(body, Transform3D(tilt, origin + tilt * Vector3(0, h * 0.5, 0)), Color(1, 1, 1), 2.0, 0.0, 2.0, 0.0, 0.0, seed_v + s, 0.35)
		b.add(tip, Transform3D(tilt, origin + tilt * Vector3(0, h + 0.2, 0)), Color(1, 1, 1), 2.0, 0.0, 2.0, 0.0, 0.0, seed_v + s, 1.0)
		s += 1
	return b.build(true)


static func scrap(seed_v: int) -> ArrayMesh:
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	for k in 7:
		var h: int = MapNoise.hash2(k, 11, seed_v)
		var plate: BoxMesh = BoxMesh.new()
		plate.size = Vector3(0.9 + float(h & 0xFF) / 255.0 * 0.9, 0.07, 0.5 + float((h >> 8) & 0xFF) / 255.0 * 0.5)
		var rot: Basis = Basis(Vector3.UP, float((h >> 4) & 0xFFF) / 4095.0 * TAU) * Basis(Vector3.RIGHT, (float((h >> 16) & 0xFF) / 255.0 - 0.5) * 1.1) * Basis(Vector3.FORWARD, (float((h >> 20) & 0xFF) / 255.0 - 0.5) * 0.9)
		var pos: Vector3 = Vector3((float((h >> 6) & 0xFF) / 255.0 - 0.5) * 1.2, 0.12 + 0.07 * k, (float((h >> 12) & 0xFF) / 255.0 - 0.5) * 1.2)
		var rusty: bool = ((h >> 24) & 1) == 1
		b.add(plate, Transform3D(rot, pos), Color(0.24, 0.115, 0.055) if rusty else Color(0.17, 0.18, 0.20), 3.0, 0.0, 1.2, 0.0, 0.0, seed_v + k, 0.5)
	for k in 2:
		var barrel: CylinderMesh = CylinderMesh.new()
		barrel.top_radius = 0.27
		barrel.bottom_radius = 0.27
		barrel.height = 0.75
		barrel.radial_segments = 8
		barrel.rings = 1
		var rot2: Basis = Basis(Vector3.FORWARD, 0.5 + 0.9 * k) * Basis(Vector3.UP, 1.7 * k)
		b.add(barrel, Transform3D(rot2, Vector3(0.6 - 1.2 * k, 0.32, -0.5 + 0.9 * k)), Color(0.16, 0.085, 0.05), 3.0, 0.0, 1.2, 0.0, 0.0, seed_v + 20 + k, 0.5)
	return b.build(true)


static func triangle_count(mesh: ArrayMesh) -> int:
	var arr: Array = mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.size() > 0:
		return idx.size() / 3
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	return v.size() / 3
