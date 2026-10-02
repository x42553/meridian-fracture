class_name ViewMeshBuilder
extends RefCounted
## Merges transformed, noise-perturbed primitive meshes into ONE ArrayMesh (one draw call per model).
## Vertex layout used by decor.gdshader / unit_demo.gdshader:
##   COLOR.rgb = baked albedo (AO gradient included), COLOR.a = wind weight, UV.x = material class
##   (0 plain, 1 foliage, 2 crystal, 3 scrap metal), UV.y unused.

var _v: PackedVector3Array = PackedVector3Array()
var _n: PackedVector3Array = PackedVector3Array()
var _c: PackedColorArray = PackedColorArray()
var _u: PackedVector2Array = PackedVector2Array()
var _i: PackedInt32Array = PackedInt32Array()


## y0..y1 is the model's vertical extent (metres) used for the wind weight and AO gradients.
func add(prim: Mesh, xf: Transform3D, tint: Color, mat_class: float, y0: float, y1: float, wind: float, noise_amp: float, seed_v: int, ao_bottom: float = 0.55) -> void:
	var arr: Array = prim.get_mesh_arrays()
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nb: Basis = xf.basis.inverse().transposed()
	var base: int = _v.size()
	var span: float = maxf(y1 - y0, 0.001)
	for k in pv.size():
		var n: Vector3 = (nb * pn[k]).normalized()
		var p: Vector3 = xf * pv[k]
		if noise_amp > 0.0:
			var h: int = MapNoise.hash2(roundi(p.x * 400.0), roundi(p.y * 400.0) ^ roundi(p.z * 400.0), seed_v)
			p += n * (float(h & 0xFFFF) / 65535.0 - 0.5) * 2.0 * noise_amp
		var f: float = clampf((p.y - y0) / span, 0.0, 1.0)
		var ao: float = lerpf(ao_bottom, 1.0, sqrt(f))
		_v.append(p)
		_n.append(n)
		_c.append(Color(tint.r * ao, tint.g * ao, tint.b * ao, pow(f, 1.4) * wind))
		_u.append(Vector2(mat_class, 0.0))
	for k in pi:
		_i.append(base + k)


## flat=true un-indexes and writes per-face normals (crisp low-poly rocks and scrap).
func build(flat: bool) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	if flat:
		var v2: PackedVector3Array = PackedVector3Array()
		var n2: PackedVector3Array = PackedVector3Array()
		var c2: PackedColorArray = PackedColorArray()
		var u2: PackedVector2Array = PackedVector2Array()
		for t in range(0, _i.size(), 3):
			var a: int = _i[t]
			var b: int = _i[t + 1]
			var c: int = _i[t + 2]
			var fn: Vector3 = (_v[c] - _v[a]).cross(_v[b] - _v[a]).normalized()
			if fn.dot(_n[a] + _n[b] + _n[c]) < 0.0:
				fn = -fn
			for q in [a, b, c]:
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
