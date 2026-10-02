class_name ViewGroundMesh
extends RefCounted
## Terrain-conforming grid meshes for ground markings (zones, warning geometry, capture rings). The vertices are WORLD-space points on
## the terrain (ViewWorld.ground_at + lift), UV = position in the marking's local frame in metres (u along the axis, v across), so a
## shader draws discs, capsules and rings from signed-distance functions of UV without caring about slopes. COLOR.r of a layered
## mesh = layer index / (layers - 1) (smoke sheets at increasing height). Built once per marking (and again when it moves).

const MAX_N: int = 72


## One grid covering the local rectangle [-half.x, half.x] x [-half.y, half.y] around `center` (world xz) rotated by `yaw`
## (local u axis = (cos yaw, sin yaw) in world xz). `lifts` = one height above the ground per layer.
static func build(v: ViewWorld, center: Vector2, yaw: float, half: Vector2, step_m: float, lifts: PackedFloat32Array) -> ArrayMesh:
	var nx: int = clampi(int(ceil(half.x * 2.0 / maxf(step_m, 0.25))) + 1, 2, MAX_N)
	var nz: int = clampi(int(ceil(half.y * 2.0 / maxf(step_m, 0.25))) + 1, 2, MAX_N)
	var layers: int = maxi(lifts.size(), 1)
	var ax: Vector2 = Vector2(cos(yaw), sin(yaw))
	var az: Vector2 = Vector2(-ax.y, ax.x)
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	var norms: PackedVector3Array = PackedVector3Array()
	var idx: PackedInt32Array = PackedInt32Array()
	verts.resize(nx * nz * layers)
	uvs.resize(nx * nz * layers)
	cols.resize(nx * nz * layers)
	norms.resize(nx * nz * layers)
	for l: int in layers:
		var lk: float = float(l) / float(maxi(layers - 1, 1))
		var lift: float = lifts[l] if l < lifts.size() else 0.0
		for j: int in nz:
			var lv: float = -half.y + 2.0 * half.y * float(j) / float(nz - 1)
			for i: int in nx:
				var lu: float = -half.x + 2.0 * half.x * float(i) / float(nx - 1)
				var w: Vector2 = center + ax * lu + az * lv
				var n: int = l * nx * nz + j * nx + i
				verts[n] = Vector3(w.x, v.ground_at(w.x, w.y) + lift, w.y)
				uvs[n] = Vector2(lu, lv)
				cols[n] = Color(lk, 0.0, 0.0, 1.0)
				norms[n] = Vector3.UP
	for l2: int in layers:
		var base: int = l2 * nx * nz
		for j2: int in nz - 1:
			for i2: int in nx - 1:
				var a: int = base + j2 * nx + i2
				var b: int = a + 1
				var c: int = a + nx
				var d: int = c + 1
				idx.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(center.x - half.x - half.y - 2.0, -100.0, center.y - half.x - half.y - 2.0), Vector3((half.x + half.y + 2.0) * 2.0, 400.0, (half.x + half.y + 2.0) * 2.0))
	return mesh


## Convenience: a single layer lifted by `lift` metres.
static func build_flat(v: ViewWorld, center: Vector2, yaw: float, half: Vector2, step_m: float, lift: float) -> ArrayMesh:
	return build(v, center, yaw, half, step_m, PackedFloat32Array([lift]))
