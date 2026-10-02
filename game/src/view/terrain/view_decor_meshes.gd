class_name ViewDecorMeshes
extends RefCounted
## Procedural low-poly decoration meshes (no art files): broadleaf tree, conifer, rock, crystal cluster, scrap pile, palm, reed
## tuft and three urban building variants (render spec 5.5). Each is ONE surface built by a private merge builder.
## Vertex layout read by decor.gdshader: COLOR.rgb = baked albedo (AO gradient included), COLOR.a = wind weight,
## UV.x = material class (0 plain, 1 foliage, 2 crystal, 3 scrap metal, 4 building), UV.y = building variant (0 office,
## 1 apartment, 2 warehouse). Buildings are modelled in a unit box (footprint 1 x 1 centred on the origin, height 0..1) and
## scaled per instance. Presentation only.

const CLASS_PLAIN: float = 0.0
const CLASS_FOLIAGE: float = 1.0
const CLASS_CRYSTAL: float = 2.0
const CLASS_SCRAP: float = 3.0
const CLASS_BUILDING: float = 4.0


## Deterministic 32-bit integer hash of three ints (no floats, no Godot RNG): same scatter on every client.
static func hash3(a: int, b: int, c: int) -> int:
	var x: int = ((a & 0xFFFFF) * 374761393 + (b & 0xFFFFF) * 668265263 + (c & 0xFFFF) * 2246822519 + 0x9E3779B1) & 0xFFFFFFFF
	x = ((x ^ (x >> 13)) * 1274126177) & 0xFFFFFFFF
	return (x ^ (x >> 16)) & 0xFFFFFFFF


## Merges transformed, noise-perturbed primitives into one mesh.
class Merge extends RefCounted:
	var _v: PackedVector3Array = PackedVector3Array()
	var _n: PackedVector3Array = PackedVector3Array()
	var _c: PackedColorArray = PackedColorArray()
	var _u: PackedVector2Array = PackedVector2Array()
	var _i: PackedInt32Array = PackedInt32Array()

	## y0..y1 is the model's vertical extent (m) used for the wind weight and AO gradients.
	func add(prim: Mesh, xf: Transform3D, tint: Color, mat_class: float, y0: float, y1: float, wind: float, noise_amp: float, seed_v: int, ao_bottom: float = 0.55, variant: float = 0.0) -> void:
		var arr: Array = prim.get_mesh_arrays()
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nb: Basis = xf.basis.inverse().transposed()
		var base: int = _v.size()
		var span: float = maxf(y1 - y0, 0.001)
		for k: int in pv.size():
			var n: Vector3 = (nb * pn[k]).normalized()
			var p: Vector3 = xf * pv[k]
			if noise_amp > 0.0:
				var h: int = ViewDecorMeshes.hash3(roundi(p.x * 400.0), roundi(p.y * 400.0) ^ roundi(p.z * 400.0), seed_v)
				p += n * (float(h & 0xFFFF) / 65535.0 - 0.5) * 2.0 * noise_amp
			var f: float = clampf((p.y - y0) / span, 0.0, 1.0)
			var ao: float = lerpf(ao_bottom, 1.0, sqrt(f))
			_v.append(p)
			_n.append(n)
			_c.append(Color(tint.r * ao, tint.g * ao, tint.b * ao, pow(f, 1.4) * wind))
			_u.append(Vector2(mat_class, variant))
		for k: int in pi:
			_i.append(base + k)

	## flat = true un-indexes and writes per-face normals (crisp low-poly rocks, scrap and buildings).
	func build(flat: bool) -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		if flat:
			var v2: PackedVector3Array = PackedVector3Array()
			var n2: PackedVector3Array = PackedVector3Array()
			var c2: PackedColorArray = PackedColorArray()
			var u2: PackedVector2Array = PackedVector2Array()
			for t: int in range(0, _i.size(), 3):
				var a: int = _i[t]
				var b: int = _i[t + 1]
				var c: int = _i[t + 2]
				var fn: Vector3 = (_v[c] - _v[a]).cross(_v[b] - _v[a]).normalized()
				if fn.dot(_n[a] + _n[b] + _n[c]) < 0.0:
					fn = -fn
				for q: int in [a, b, c]:
					v2.append(_v[q])
					n2.append(fn)
					c2.append(_c[q])
					u2.append(_u[q])
			arrays[Mesh.ARRAY_VERTEX] = v2
			arrays[Mesh.ARRAY_NORMAL] = n2
			arrays[Mesh.ARRAY_COLOR] = c2
			arrays[Mesh.ARRAY_TEX_UV] = u2
		else:
			arrays[Mesh.ARRAY_VERTEX] = _v
			arrays[Mesh.ARRAY_NORMAL] = _n
			arrays[Mesh.ARRAY_COLOR] = _c
			arrays[Mesh.ARRAY_TEX_UV] = _u
			arrays[Mesh.ARRAY_INDEX] = _i
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


static func broadleaf(seed_v: int) -> ArrayMesh:
	var b: Merge = Merge.new()
	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.27
	trunk.height = 2.7
	trunk.radial_segments = 6
	trunk.rings = 1
	b.add(trunk, Transform3D(Basis.IDENTITY, Vector3(0, 1.35, 0)), Color(0.34, 0.24, 0.15), CLASS_PLAIN, 0.0, 5.6, 0.10, 0.0, seed_v, 0.6)
	var blobs: Array[Vector4] = [Vector4(0.0, 3.7, 0.0, 1.55), Vector4(0.75, 3.2, 0.45, 1.15), Vector4(-0.7, 4.35, -0.4, 1.15), Vector4(0.1, 4.9, 0.3, 0.85)]
	var s: int = 0
	for bl: Vector4 in blobs:
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = bl.w
		sph.height = bl.w * 1.8
		sph.radial_segments = 8
		sph.rings = 5
		b.add(sph, Transform3D(Basis.IDENTITY, Vector3(bl.x, bl.y, bl.z)), Color(1, 1, 1), CLASS_FOLIAGE, 1.6, 5.8, 1.0, 0.16, seed_v + s, 0.5)
		s += 1
	return b.build(false)


static func conifer(seed_v: int) -> ArrayMesh:
	var b: Merge = Merge.new()
	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.22
	trunk.height = 1.6
	trunk.radial_segments = 6
	trunk.rings = 1
	b.add(trunk, Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)), Color(0.30, 0.21, 0.14), CLASS_PLAIN, 0.0, 6.4, 0.05, 0.0, seed_v, 0.6)
	var layers: Array[Vector3] = [Vector3(1.0, 1.9, 1.75), Vector3(2.1, 1.75, 1.4), Vector3(3.1, 1.6, 1.05), Vector3(4.0, 1.45, 0.7)]
	var s: int = 0
	for ly: Vector3 in layers:
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = ly.z
		cone.height = ly.y
		cone.radial_segments = 8
		cone.rings = 1
		cone.cap_bottom = false
		b.add(cone, Transform3D(Basis.IDENTITY, Vector3(0, ly.x + ly.y * 0.5, 0)), Color(0.72, 0.9, 0.78), CLASS_FOLIAGE, 0.8, 6.2, 1.0, 0.10, seed_v + s, 0.45)
		s += 1
	return b.build(false)


static func rock(seed_v: int) -> ArrayMesh:
	var b: Merge = Merge.new()
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = 0.8
	sph.height = 1.35
	sph.radial_segments = 7
	sph.rings = 4
	b.add(sph, Transform3D(Basis.from_scale(Vector3(1.25, 0.8, 1.0)), Vector3(0, 0.45, 0)), Color(0.20, 0.19, 0.175), CLASS_PLAIN, 0.0, 1.4, 0.0, 0.24, seed_v, 0.6)
	var small: SphereMesh = SphereMesh.new()
	small.radius = 0.4
	small.height = 0.7
	small.radial_segments = 6
	small.rings = 3
	b.add(small, Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.2)), Vector3(0.75, 0.25, 0.3)), Color(0.17, 0.165, 0.155), CLASS_PLAIN, 0.0, 1.4, 0.0, 0.15, seed_v + 5, 0.6)
	return b.build(true)


static func crystal(seed_v: int) -> ArrayMesh:
	var b: Merge = Merge.new()
	var specs: Array[Vector4] = [Vector4(0.0, 0.0, 1.7, 0.0), Vector4(0.42, 0.12, 1.15, 0.30), Vector4(-0.38, 0.2, 1.3, -0.26), Vector4(0.12, -0.42, 0.9, 0.22), Vector4(-0.15, 0.4, 0.75, -0.32)]
	var s: int = 0
	for sp: Vector4 in specs:
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
		b.add(body, Transform3D(tilt, origin + tilt * Vector3(0, h * 0.5, 0)), Color(1, 1, 1), CLASS_CRYSTAL, 0.0, 2.0, 0.0, 0.0, seed_v + s, 0.35)
		b.add(tip, Transform3D(tilt, origin + tilt * Vector3(0, h + 0.2, 0)), Color(1, 1, 1), CLASS_CRYSTAL, 0.0, 2.0, 0.0, 0.0, seed_v + s, 1.0)
		s += 1
	return b.build(true)


static func scrap(seed_v: int) -> ArrayMesh:
	var b: Merge = Merge.new()
	for k: int in 7:
		var h: int = hash3(k, 11, seed_v)
		var plate: BoxMesh = BoxMesh.new()
		plate.size = Vector3(0.9 + float(h & 0xFF) / 255.0 * 0.9, 0.07, 0.5 + float((h >> 8) & 0xFF) / 255.0 * 0.5)
		var rot: Basis = Basis(Vector3.UP, float((h >> 4) & 0xFFF) / 4095.0 * TAU) * Basis(Vector3.RIGHT, (float((h >> 16) & 0xFF) / 255.0 - 0.5) * 1.1) * Basis(Vector3.FORWARD, (float((h >> 20) & 0xFF) / 255.0 - 0.5) * 0.9)
		var pos: Vector3 = Vector3((float((h >> 6) & 0xFF) / 255.0 - 0.5) * 1.2, 0.12 + 0.07 * k, (float((h >> 12) & 0xFF) / 255.0 - 0.5) * 1.2)
		var rusty: bool = ((h >> 24) & 1) == 1
		b.add(plate, Transform3D(rot, pos), Color(0.24, 0.115, 0.055) if rusty else Color(0.17, 0.18, 0.20), CLASS_SCRAP, 0.0, 1.2, 0.0, 0.0, seed_v + k, 0.5)
	for k: int in 2:
		var barrel: CylinderMesh = CylinderMesh.new()
		barrel.top_radius = 0.27
		barrel.bottom_radius = 0.27
		barrel.height = 0.75
		barrel.radial_segments = 8
		barrel.rings = 1
		var rot2: Basis = Basis(Vector3.FORWARD, 0.5 + 0.9 * k) * Basis(Vector3.UP, 1.7 * k)
		b.add(barrel, Transform3D(rot2, Vector3(0.6 - 1.2 * k, 0.32, -0.5 + 0.9 * k)), Color(0.16, 0.085, 0.05), CLASS_SCRAP, 0.0, 1.2, 0.0, 0.0, seed_v + 20 + k, 0.5)
	return b.build(true)


## Palm: a leaning three-segment trunk and eight drooping fronds (wind weight grows with height).
static func palm(seed_v: int) -> ArrayMesh:
	var b: Merge = Merge.new()
	var top: Vector3 = Vector3.ZERO
	for k: int in 3:
		var seg: CylinderMesh = CylinderMesh.new()
		seg.top_radius = 0.14 - 0.02 * float(k)
		seg.bottom_radius = 0.19 - 0.02 * float(k)
		seg.height = 1.55
		seg.radial_segments = 6
		seg.rings = 1
		var lean: Basis = Basis(Vector3.FORWARD, 0.11)
		var c: Vector3 = top + lean * Vector3(0, 0.775, 0)
		b.add(seg, Transform3D(lean, c), Color(0.42, 0.32, 0.20), CLASS_PLAIN, 0.0, 6.6, 0.06 * float(k + 1), 0.0, seed_v + k, 0.6)
		top += lean * Vector3(0, 1.55, 0)
	for f: int in 8:
		var yaw: Basis = Basis(Vector3.UP, TAU * float(f) / 8.0 + 0.2 * float(f % 3))
		var inner: BoxMesh = BoxMesh.new()
		inner.size = Vector3(1.3, 0.05, 0.42)
		var up: Basis = yaw * Basis(Vector3.FORWARD, -0.35)
		b.add(inner, Transform3D(up, top + yaw * Vector3(0.6, 0.15, 0)), Color(0.75, 0.95, 0.75), CLASS_FOLIAGE, 3.0, 5.6, 1.0, 0.03, seed_v + 10 + f, 0.6)
		var outer: BoxMesh = BoxMesh.new()
		outer.size = Vector3(1.2, 0.04, 0.3)
		var down: Basis = yaw * Basis(Vector3.FORWARD, 0.75)
		b.add(outer, Transform3D(down, top + yaw * Vector3(1.55, 0.05, 0)), Color(0.7, 0.9, 0.7), CLASS_FOLIAGE, 3.0, 5.6, 1.0, 0.03, seed_v + 30 + f, 0.6)
	return b.build(false)


## Reed tuft on shallow shore cells: five thin blades.
static func reed(seed_v: int) -> ArrayMesh:
	var b: Merge = Merge.new()
	for k: int in 6:
		var h: int = hash3(k, 3, seed_v)
		var blade: CylinderMesh = CylinderMesh.new()
		blade.top_radius = 0.0
		blade.bottom_radius = 0.05
		blade.height = 1.0 + float(h & 0xFF) / 255.0 * 0.7
		blade.radial_segments = 3
		blade.rings = 1
		blade.cap_bottom = false
		var tilt: Basis = Basis(Vector3.UP, float((h >> 8) & 0xFF) / 255.0 * TAU) * Basis(Vector3.FORWARD, (float((h >> 16) & 0xFF) / 255.0 - 0.5) * 0.5)
		var base: Vector3 = Vector3((float((h >> 4) & 0xFF) / 255.0 - 0.5) * 0.7, 0.0, (float((h >> 12) & 0xFF) / 255.0 - 0.5) * 0.7)
		b.add(blade, Transform3D(tilt, base + tilt * Vector3(0, blade.height * 0.5, 0)), Color(0.85, 0.95, 0.75), CLASS_FOLIAGE, 0.0, 1.7, 1.0, 0.0, seed_v + k, 0.5)
	return b.build(false)


## Urban building in a unit box (footprint 1 x 1 centred on the origin, y 0..1); `variant` 0 office block (setback crown and
## roof plant), 1 apartment slab (stair core and roof lip), 2 warehouse (sawtooth roof and a dark loading band).
static func building(variant: int, seed_v: int) -> ArrayMesh:
	var b: Merge = Merge.new()
	var v: float = float(variant)
	match variant:
		0:
			var body: BoxMesh = BoxMesh.new()
			body.size = Vector3(0.9, 0.9, 0.9)
			b.add(body, Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), Color(0.50, 0.54, 0.60), CLASS_BUILDING, 0.0, 1.0, 0.0, 0.0, seed_v, 0.62, v)
			var crown: BoxMesh = BoxMesh.new()
			crown.size = Vector3(0.62, 0.07, 0.62)
			b.add(crown, Transform3D(Basis.IDENTITY, Vector3(0, 0.935, 0)), Color(0.38, 0.41, 0.46), CLASS_BUILDING, 0.0, 1.0, 0.0, 0.0, seed_v + 1, 0.9, v)
			var plant: BoxMesh = BoxMesh.new()
			plant.size = Vector3(0.28, 0.06, 0.34)
			b.add(plant, Transform3D(Basis.IDENTITY, Vector3(-0.12, 1.0, 0.1)), Color(0.3, 0.32, 0.34), CLASS_BUILDING, 0.0, 1.0, 0.0, 0.0, seed_v + 2, 1.0, v)
		1:
			var slab: BoxMesh = BoxMesh.new()
			slab.size = Vector3(0.94, 0.92, 0.84)
			b.add(slab, Transform3D(Basis.IDENTITY, Vector3(0, 0.46, 0)), Color(0.62, 0.50, 0.42), CLASS_BUILDING, 0.0, 1.0, 0.0, 0.0, seed_v, 0.62, v)
			var lip: BoxMesh = BoxMesh.new()
			lip.size = Vector3(0.98, 0.035, 0.88)
			b.add(lip, Transform3D(Basis.IDENTITY, Vector3(0, 0.935, 0)), Color(0.46, 0.38, 0.32), CLASS_BUILDING, 0.0, 1.0, 0.0, 0.0, seed_v + 1, 1.0, v)
			var core: BoxMesh = BoxMesh.new()
			core.size = Vector3(0.22, 0.09, 0.26)
			b.add(core, Transform3D(Basis.IDENTITY, Vector3(0.3, 1.0, -0.18)), Color(0.5, 0.42, 0.36), CLASS_BUILDING, 0.0, 1.0, 0.0, 0.0, seed_v + 2, 1.0, v)
		_:
			var hall: BoxMesh = BoxMesh.new()
			hall.size = Vector3(0.96, 0.8, 0.9)
			b.add(hall, Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)), Color(0.50, 0.52, 0.50), CLASS_BUILDING, 0.0, 1.0, 0.0, 0.0, seed_v, 0.62, v)
			for k: int in 3:
				var tooth: PrismMesh = PrismMesh.new()
				tooth.size = Vector3(0.31, 0.2, 0.92)
				tooth.left_to_right = 0.0
				b.add(tooth, Transform3D(Basis.IDENTITY, Vector3(-0.32 + 0.32 * float(k), 0.9, 0)), Color(0.36, 0.38, 0.38), CLASS_BUILDING, 0.0, 1.0, 0.0, 0.0, seed_v + 1 + k, 1.0, v)
	return b.build(true)


static func triangle_count(mesh: ArrayMesh) -> int:
	var arr: Array = mesh.surface_get_arrays(0)
	var idx: Variant = arr[Mesh.ARRAY_INDEX]
	if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
		return (idx as PackedInt32Array).size() / 3
	return (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
