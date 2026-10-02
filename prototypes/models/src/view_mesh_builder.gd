class_name ViewMeshBuilder
extends RefCounted
## Procedural hard-surface mesh builder. Composes primitives into ONE ArrayMesh surface per model.
##
## Conventions: +X = right, +Y = up, -Z = FORWARD (Godot native). Units are metres. All primitives are closed convex
## solids; faces are emitted with per-face data so a single shader can paint, wear and animate them.
##
## Vertex encoding (written here, decoded by shaders/unit.gdshader):
##   COLOR   RGBA8         rgb = paint albedo (sRGB-authored), a = team-colour mask 0..1
##   UV      float2        planar face coordinates in metres (+ per-primitive random offset) for panel lines;
##                         for Part.TRACK it is (lateral m, arc length m along the belt loop)
##   UV2     float2        (trunnion_y, trunnion_z): secondary pivot for Part.BARREL elevation
##   CUSTOM0 RGBA8_UNORM   r = (ao4 << 4) | (wear << 3) | Mat class, g = Part kind, b = part param (0..255), a = unused
##   CUSTOM1 RGBA_FLOAT    xyz = part pivot (model space), w = part extra (wheel radius / recoil m / travel m)
## Pivots are always given in MODEL space, independent of the push()/pop() transform stack.
##
## LOD: primitives carry a `tier` (0 = essential mass, 1 = detail, 2 = micro). build() emits index-buffer subsets
## (tier<=1, tier==0) as mesh LODs that share the single vertex buffer.

enum Mat { PAINT = 0, METAL = 1, GLASS = 2, RUBBER = 3, EMISSIVE = 4 }
enum Part {
	STATIC = 0, TURRET = 1, BARREL = 2, WHEEL = 3, TRACK = 4, ROTOR = 5, TAIL_ROTOR = 6, RADAR = 7,
	LEG_A = 8, LEG_B = 9, ARM_A = 10, ARM_B = 11, BODY_BOB = 12, DOOR = 13, BLINK = 14, DEPLOY = 15,
}

const EPS: float = 1.0e-6
## Mesh LOD keys (world-space 'edge length' error in metres); tuned by the LOD probe in proto_main.
static var lod1_key: float = 0.02
static var lod2_key: float = 0.06

# ------------------------------------------------------------------ brush (state applied to the next primitives)
var paint: Color = Color(0.5, 0.5, 0.5)
var team_mask: float = 0.0
var mat: int = Mat.PAINT
var part: int = Part.STATIC
var pivot: Vector3 = Vector3.ZERO
var part_param: float = 0.0
var part_extra: float = 0.0
var trunnion: Vector2 = Vector2.ZERO
var ao: float = 1.0
var tier: int = 0
var default_bevel: float = 0.0
var jitter: float = 0.035
## true: CUSTOM1 as RGBA_HALF (8 B/vertex, must be a PackedByteArray of half bits); false: RGBA_FLOAT (16 B/vertex).
var pack_half: bool = true
## Uniform scale applied at build(): positions, pivots, extras and trunnions (e.g. enlarge infantry for RTS readability).
var model_scale: float = 1.0

# ------------------------------------------------------------------ output arrays
var _pos := PackedVector3Array()
var _nrm := PackedVector3Array()
var _col := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _c0 := PackedByteArray()
var _c1 := PackedFloat32Array()
var _idx := PackedInt32Array()
var _idx_l1 := PackedInt32Array()
var _idx_l2 := PackedInt32Array()

var _xf: Transform3D = Transform3D.IDENTITY
var _xf_stack: Array[Transform3D] = []
var _rng := RandomNumberGenerator.new()
var _uv_off: Vector2 = Vector2.ZERO
var _prim_rand: float = 0.0
var _cur_col: Color = Color.WHITE
var _blocks: Dictionary = {}
var _pivot_box: AABB = AABB()
var _has_pivot_box: bool = false
var _anim_max_r: float = 0.0
var _mask_override: int = -1


func seed_rng(s: int) -> ViewMeshBuilder:
	_rng.seed = s
	return self


# ------------------------------------------------------------------ brush API
## Sets paint colour, material class and team-colour mask in one call.
func brush(c: Color, m: int = Mat.PAINT, team: float = 0.0) -> ViewMeshBuilder:
	paint = c
	mat = m
	team_mask = team
	return self


## Marks following primitives as an animated part. pivot is in model space.
## param (0..1) and extra are part specific (see shaders/unit.gdshader header).
func set_part(kind: int, pivot_pos: Vector3 = Vector3.ZERO, param: float = 0.0, extra: float = 0.0, trunnion_yz: Vector2 = Vector2.ZERO) -> ViewMeshBuilder:
	part = kind
	pivot = pivot_pos
	part_param = param
	part_extra = extra
	trunnion = trunnion_yz
	return self


func clear_part() -> ViewMeshBuilder:
	part = Part.STATIC
	pivot = Vector3.ZERO
	part_param = 0.0
	part_extra = 0.0
	trunnion = Vector2.ZERO
	return self


# ------------------------------------------------------------------ transform stack
static func xf(pos: Vector3, euler_deg: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(euler_deg * (PI / 180.0)), pos)


func push(t: Transform3D) -> void:
	_xf_stack.append(_xf)
	_xf = _xf * t


func pop() -> void:
	_xf = _xf_stack.pop_back()


# ------------------------------------------------------------------ stats
func vertex_count() -> int:
	return _pos.size()


func triangle_count() -> int:
	return _idx.size() / 3


## Triangle counts of the three index sets: (full, tier<=1, tier==0).
func tier_triangle_counts() -> Vector3i:
	return Vector3i(_idx.size() / 3, _idx_l1.size() / 3, _idx_l2.size() / 3)


# ------------------------------------------------------------------ low-level emission
func _begin_prim() -> void:
	var j: float = 1.0 + _rng.randf_range(-jitter, jitter)
	_cur_col = Color(clampf(paint.r * j, 0.0, 1.0), clampf(paint.g * j, 0.0, 1.0), clampf(paint.b * j, 0.0, 1.0), team_mask)
	_uv_off = Vector2(_rng.randf() * 3.0, _rng.randf() * 3.0)
	_prim_rand = _rng.randf()
	_blocks.clear()
	if _moves_vertices():
		if _has_pivot_box:
			_pivot_box = _pivot_box.expand(pivot)
		else:
			_pivot_box = AABB(pivot, Vector3.ZERO)
			_has_pivot_box = true


## Index-set membership of the current brush tier: bit0 = LOD0 list, bit1 = LOD1 list, bit2 = LOD2 list.
## tier 0 = essential mass (all LODs), tier 1 = detail (LOD0+LOD1), tier 2 = micro detail (LOD0 only).
func _tier_mask() -> int:
	return 7 if tier == 0 else (3 if tier == 1 else 1)


## TRACK scrolls in the fragment stage and BLINK only modulates emission: neither moves vertices.
func _moves_vertices() -> bool:
	return part != Part.STATIC and part != Part.TRACK and part != Part.BLINK


func _attr_block(k: int, wear: int) -> Array:
	var key: int = k * 16 + wear
	if _blocks.has(key):
		return _blocks[key]
	var col := PackedColorArray()
	col.resize(k)
	col.fill(_cur_col)
	var uv2 := PackedVector2Array()
	uv2.resize(k)
	uv2.fill(trunnion)
	var c0 := PackedByteArray()
	var c1 := PackedFloat32Array()
	# CUSTOM0.x = (ao4 << 4) | (wear << 3) | mat  (never rely on the 4th component: gl_compatibility drops it)
	var packed: int = (int(roundf(ao * 15.0)) << 4) | (8 if wear > 0 else 0) | mat
	# static primitives reuse `param` as a random panel-grid size seed; animated parts need it for phase / limits
	var pp: int = int(roundf(clampf(part_param if part != Part.STATIC else _prim_rand, 0.0, 1.0) * 255.0))
	for i in k:
		c0.append(packed)
		c0.append(part)
		c0.append(pp)
		c0.append(0)
		c1.append(pivot.x)
		c1.append(pivot.y)
		c1.append(pivot.z)
		c1.append(part_extra)
	var blk: Array = [col, uv2, c0, c1]
	_blocks[key] = blk
	return blk


## Emits one convex polygon given in MODEL space. ref_n (model space) picks the winding: Godot front faces are clockwise.
func _emit(pts: PackedVector3Array, nrm: PackedVector3Array, uvs: PackedVector2Array, wear: int, ref_n: Vector3) -> void:
	var k: int = pts.size()
	var nl := Vector3.ZERO
	for i in k:
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[(i + 1) % k]
		nl.x += (a.y - c.y) * (a.z + c.z)
		nl.y += (a.z - c.z) * (a.x + c.x)
		nl.z += (a.x - c.x) * (a.y + c.y)
	if nl.length_squared() < 1.0e-14:
		return
	var base: int = _pos.size()
	if nl.dot(ref_n) > 0.0:
		for j in range(k - 1, -1, -1):
			_pos.append(pts[j])
			_nrm.append(nrm[j])
			_uv.append(uvs[j])
	else:
		_pos.append_array(pts)
		_nrm.append_array(nrm)
		_uv.append_array(uvs)
	var blk: Array = _attr_block(k, wear)
	_col.append_array(blk[0])
	_uv2.append_array(blk[1])
	_c0.append_array(blk[2])
	_c1.append_array(blk[3])
	var mask: int = _mask_override if _mask_override >= 0 else _tier_mask()
	for i in range(1, k - 1):
		if mask & 1:
			_idx.append(base)
			_idx.append(base + i)
			_idx.append(base + i + 1)
		if mask & 2:
			_idx_l1.append(base)
			_idx_l1.append(base + i)
			_idx_l1.append(base + i + 1)
		if mask & 4:
			_idx_l2.append(base)
			_idx_l2.append(base + i)
			_idx_l2.append(base + i + 1)
	if _moves_vertices():
		for i in k:
			_anim_max_r = maxf(_anim_max_r, pts[i].distance_to(pivot))


## Flat-shaded convex polygon in the CURRENT local space (n = outward local normal).
func _flat(pts: PackedVector3Array, n: Vector3, wear: int = 0) -> void:
	var k: int = pts.size()
	var t1: Vector3 = pts[1] - pts[0]
	if t1.length_squared() < EPS:
		t1 = pts[2] - pts[0]
	t1 = t1.normalized()
	var t2: Vector3 = n.cross(t1)
	var wn: Vector3 = (_xf.basis * n).normalized()
	var wp := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uvs := PackedVector2Array()
	wp.resize(k)
	nrm.resize(k)
	uvs.resize(k)
	for i in k:
		var p: Vector3 = pts[i]
		wp[i] = _xf * p
		nrm[i] = wn
		uvs[i] = Vector2(p.dot(t1), p.dot(t2)) + _uv_off
	_emit(wp, nrm, uvs, wear, wn)


# ------------------------------------------------------------------ prism family: box, tapered box, extrusion, n-gon loft
## Loft between two convex n-gons a[] and b[] (same vertex order, planar side quads). bevel < 0 uses default_bevel.
## Bevels are real geometry (inset faces + chamfer strips + corner tris): boolean-free, ~4x the vertices of a plain box.
func prism(a: PackedVector3Array, b: PackedVector3Array, bevel: float = -1.0) -> void:
	var n: int = a.size()
	if n < 3 or b.size() != n:
		push_error("ViewMeshBuilder.prism: caps must be convex n-gons of equal size")
		return
	_begin_prim()
	var bw: float = default_bevel if bevel < 0.0 else bevel
	var v := PackedVector3Array()
	v.append_array(a)
	v.append_array(b)
	var cen := Vector3.ZERO
	for p in v:
		cen += p
	cen /= float(v.size())
	var nf: int = n + 2
	var ids: Array[PackedInt32Array] = []
	var ia := PackedInt32Array()
	var ib := PackedInt32Array()
	for i in n:
		ia.append(i)
		ib.append(n + i)
	ids.append(ia)
	ids.append(ib)
	for i in n:
		var j: int = (i + 1) % n
		ids.append(PackedInt32Array([i, j, n + j, n + i]))
	var fn: Array[Vector3] = []
	var fp: Array[PackedVector3Array] = []
	var min_edge: float = INF
	for f in nf:
		var loop := PackedVector3Array()
		for id in ids[f]:
			loop.append(v[id])
		var m: int = loop.size()
		var nn := Vector3.ZERO
		var fc := Vector3.ZERO
		for i in m:
			var p0: Vector3 = loop[i]
			var p1: Vector3 = loop[(i + 1) % m]
			nn.x += (p0.y - p1.y) * (p0.z + p1.z)
			nn.y += (p0.z - p1.z) * (p0.x + p1.x)
			nn.z += (p0.x - p1.x) * (p0.y + p1.y)
			fc += p0
			min_edge = minf(min_edge, p0.distance_to(p1))
		fc /= float(m)
		nn = nn.normalized()
		if nn.dot(fc - cen) < 0.0:
			nn = -nn
		fp.append(loop)
		fn.append(nn)
	bw = minf(bw, min_edge * 0.4)
	if bw <= 1.0e-4:
		for f in nf:
			_flat(fp[f], fn[f], 0)
		return
	# LOD1/LOD2 representation: the plain un-bevelled faces (separate vertices, only in the LOD index lists)
	var base_mask: int = _tier_mask()
	if base_mask & 6 != 0:
		_mask_override = base_mask & 6
		for f in nf:
			_flat(fp[f], fn[f], 0)
	_mask_override = base_mask & 1
	var fi: Array[PackedVector3Array] = []
	for f in nf:
		fi.append(_inset_loop(fp[f], fn[f], bw))
		_flat(fi[f], fn[f], 0)
	for i in n:
		var j: int = (i + 1) % n
		var prev_side: int = 2 + (i + n - 1) % n
		_strip(ids, fi, fn, 0, 2 + i, i, j)
		_strip(ids, fi, fn, 1, 2 + i, n + i, n + j)
		_strip(ids, fi, fn, prev_side, 2 + i, i, n + i)
		_corner(ids, fi, fn, 0, prev_side, 2 + i, i)
		_corner(ids, fi, fn, 1, prev_side, 2 + i, n + i)
	_mask_override = -1


func _inset_loop(loop: PackedVector3Array, n: Vector3, bw: float) -> PackedVector3Array:
	var m: int = loop.size()
	var c := Vector3.ZERO
	for p in loop:
		c += p
	c /= float(m)
	var inward: Array[Vector3] = []
	for i in m:
		var e: Vector3 = (loop[(i + 1) % m] - loop[i]).normalized()
		var d: Vector3 = n.cross(e)
		if d.dot(c - loop[i]) < 0.0:
			d = -d
		inward.append(d)
	var out := PackedVector3Array()
	for i in m:
		var d1: Vector3 = inward[(i + m - 1) % m]
		var d2: Vector3 = inward[i]
		var den: float = maxf(1.0 + d1.dot(d2), 0.25)
		out.append(loop[i] + (d1 + d2) * (bw / den))
	return out


func _strip(ids: Array[PackedInt32Array], fi: Array[PackedVector3Array], fn: Array[Vector3], fa: int, fb: int, va: int, vb: int) -> void:
	var a0: Vector3 = fi[fa][ids[fa].find(va)]
	var a1: Vector3 = fi[fa][ids[fa].find(vb)]
	var b1: Vector3 = fi[fb][ids[fb].find(vb)]
	var b0: Vector3 = fi[fb][ids[fb].find(va)]
	_flat(PackedVector3Array([a0, a1, b1, b0]), (fn[fa] + fn[fb]).normalized(), 15)


func _corner(ids: Array[PackedInt32Array], fi: Array[PackedVector3Array], fn: Array[Vector3], f0: int, f1: int, f2: int, vid: int) -> void:
	var pts := PackedVector3Array([fi[f0][ids[f0].find(vid)], fi[f1][ids[f1].find(vid)], fi[f2][ids[f2].find(vid)]])
	_flat(pts, (fn[f0] + fn[f1] + fn[f2]).normalized(), 15)


static func _rect_loop(cx: float, cz: float, half: Vector2, y: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(cx - half.x, y, cz - half.y), Vector3(cx + half.x, y, cz - half.y),
		Vector3(cx + half.x, y, cz + half.y), Vector3(cx - half.x, y, cz + half.y)])


## Axis-aligned box centred on `center`.
func box(center: Vector3, size: Vector3, bevel: float = -1.0) -> void:
	var h: Vector2 = Vector2(size.x, size.z) * 0.5
	var a := _rect_loop(center.x, center.z, h, center.y - size.y * 0.5)
	var b := _rect_loop(center.x, center.z, h, center.y + size.y * 0.5)
	prism(a, b, bevel)


## Frustum with rectangular cross-section (y extent = height around center.y). top_shift = (dx, dz) of the top rectangle.
func tapered_box(center: Vector3, size_bottom: Vector2, size_top: Vector2, height: float, top_shift: Vector2 = Vector2.ZERO, bevel: float = -1.0) -> void:
	var sb: Vector2 = size_bottom.max(Vector2(0.01, 0.01)) * 0.5
	var st: Vector2 = size_top.max(Vector2(0.01, 0.01)) * 0.5
	var a := _rect_loop(center.x, center.z, sb, center.y - height * 0.5)
	var b := _rect_loop(center.x + top_shift.x, center.z + top_shift.y, st, center.y + height * 0.5)
	prism(a, b, bevel)


## Extrudes a CONVEX side profile (x = forward distance, y = up) between x0 and x1 (model X). Wedges, hulls, canopies.
func extrude(profile: PackedVector2Array, x0: float, x1: float, bevel: float = -1.0) -> void:
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	for p in profile:
		a.append(Vector3(x0, p.y, -p.x))
		b.append(Vector3(x1, p.y, -p.x))
	prism(a, b, bevel)


## Horizontal (XZ-plane) n-gon; feed two of them to prism() for turrets, faceted domes, boat hulls.
static func ngon(center: Vector3, rx: float, rz: float, n: int, rot_deg: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var a: float = deg_to_rad(rot_deg) + TAU * float(i) / float(n)
		out.append(Vector3(center.x + cos(a) * rx, center.y, center.z + sin(a) * rz))
	return out


## Box whose top face carries recessed pockets (panel insets), built by grid subdivision: no booleans.
## pockets are Rect2 in normalised top-face coordinates (x across size.x, y across size.z).
func pocket_box(center: Vector3, size: Vector3, pockets: Array[Rect2], depth: float) -> void:
	_begin_prim()
	var h: Vector3 = size * 0.5
	var x0: float = center.x - h.x
	var x1: float = center.x + h.x
	var y0: float = center.y - h.y
	var y1: float = center.y + h.y
	var z0: float = center.z - h.z
	var z1: float = center.z + h.z
	_flat(PackedVector3Array([Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)]), Vector3.DOWN)
	_flat(PackedVector3Array([Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1)]), Vector3.LEFT)
	_flat(PackedVector3Array([Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1)]), Vector3.RIGHT)
	_flat(PackedVector3Array([Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0)]), Vector3.FORWARD)
	_flat(PackedVector3Array([Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]), Vector3.BACK)
	var us: Array[float] = [0.0, 1.0]
	var vs: Array[float] = [0.0, 1.0]
	for p in pockets:
		us.append(clampf(p.position.x, 0.0, 1.0))
		us.append(clampf(p.end.x, 0.0, 1.0))
		vs.append(clampf(p.position.y, 0.0, 1.0))
		vs.append(clampf(p.end.y, 0.0, 1.0))
	us.sort()
	vs.sort()
	us = _dedupe(us)
	vs = _dedupe(vs)
	var nu: int = us.size() - 1
	var nv: int = vs.size() - 1
	var inp := PackedByteArray()
	inp.resize(nu * nv)
	for i in nu:
		for j in nv:
			var c := Vector2((us[i] + us[i + 1]) * 0.5, (vs[j] + vs[j + 1]) * 0.5)
			for p in pockets:
				if p.has_point(c):
					inp[i * nv + j] = 1
	var sx: float = size.x
	var sz: float = size.z
	for i in nu:
		for j in nv:
			var deep: bool = inp[i * nv + j] == 1
			var ya: float = y1 - (depth if deep else 0.0)
			var xa: float = x0 + us[i] * sx
			var xb: float = x0 + us[i + 1] * sx
			var za: float = z0 + vs[j] * sz
			var zb: float = z0 + vs[j + 1] * sz
			_flat(PackedVector3Array([Vector3(xa, ya, za), Vector3(xb, ya, za), Vector3(xb, ya, zb), Vector3(xa, ya, zb)]), Vector3.UP, 0)
			if i < nu - 1 and inp[i * nv + j] != inp[(i + 1) * nv + j]:
				var nx: Vector3 = Vector3.LEFT if deep else Vector3.RIGHT
				_flat(PackedVector3Array([Vector3(xb, y1 - depth, za), Vector3(xb, y1, za), Vector3(xb, y1, zb), Vector3(xb, y1 - depth, zb)]), nx)
			if j < nv - 1 and inp[i * nv + j] != inp[i * nv + j + 1]:
				var nz: Vector3 = Vector3.FORWARD if deep else Vector3.BACK
				_flat(PackedVector3Array([Vector3(xa, y1 - depth, zb), Vector3(xa, y1, zb), Vector3(xb, y1, zb), Vector3(xb, y1 - depth, zb)]), nz)


static func _dedupe(a: Array[float]) -> Array[float]:
	var out: Array[float] = []
	for x in a:
		if out.is_empty() or x - out[out.size() - 1] > 1.0e-4:
			out.append(x)
	return out


# ------------------------------------------------------------------ surfaces of revolution
static func _basis_from_y(y: Vector3) -> Basis:
	var ref: Vector3 = Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x: Vector3 = y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


## Lathe around the axis from->to. profile points are (radius, distance along axis from `from`, wear flag of the band
## that STARTS at this point). Consecutive bands are smooth-shaded when their angle is below smooth_deg.
func lathe(from: Vector3, to: Vector3, profile: PackedVector3Array, segments: int = 12, smooth_deg: float = 38.0) -> void:
	if (to - from).length() < EPS or profile.size() < 2:
		return
	_begin_prim()
	var base_mask: int = _tier_mask()
	if segments >= 10 and base_mask & 6 != 0:
		# coarse representation (half the segments) for LOD1/LOD2, fine one for LOD0 only
		_mask_override = base_mask & 6
		_lathe_emit(from, to, profile, maxi(segments / 2, 5), smooth_deg)
		_mask_override = base_mask & 1
		_lathe_emit(from, to, profile, segments, smooth_deg)
		_mask_override = -1
	else:
		_lathe_emit(from, to, profile, segments, smooth_deg)


func _lathe_emit(from: Vector3, to: Vector3, profile: PackedVector3Array, segments: int, smooth_deg: float) -> void:
	var axis: Vector3 = to - from
	var m: int = profile.size()
	var full: Transform3D = _xf * Transform3D(_basis_from_y(axis.normalized()), from)
	var cs := PackedFloat32Array()
	var sn := PackedFloat32Array()
	for j in segments + 1:
		var th: float = TAU * float(j) / float(segments)
		cs.append(cos(th))
		sn.append(sin(th))
	var bn: Array[Vector2] = []
	var slen := PackedFloat32Array()
	slen.append(0.0)
	for i in m - 1:
		var t := Vector2(profile[i + 1].x - profile[i].x, profile[i + 1].y - profile[i].y)
		var l: float = t.length()
		bn.append(Vector2(t.y, -t.x) / l if l > EPS else Vector2.ZERO)
		slen.append(slen[i] + l)
	var cos_smooth: float = cos(deg_to_rad(smooth_deg))
	var bas: Basis = full.basis
	for i in m - 1:
		if bn[i] == Vector2.ZERO:
			continue
		var ns: Vector2 = bn[i]
		var ne: Vector2 = bn[i]
		if i > 0 and bn[i - 1] != Vector2.ZERO and bn[i - 1].dot(bn[i]) > cos_smooth:
			ns = (bn[i - 1] + bn[i]).normalized()
		if i < m - 2 and bn[i + 1] != Vector2.ZERO and bn[i + 1].dot(bn[i]) > cos_smooth:
			ne = (bn[i + 1] + bn[i]).normalized()
		var r0: float = profile[i].x
		var y0: float = profile[i].y
		var r1: float = profile[i + 1].x
		var y1: float = profile[i + 1].y
		var wear: int = 15 if profile[i].z > 0.5 else 0
		for j in segments:
			var c0: float = cs[j]
			var s0: float = sn[j]
			var c1: float = cs[j + 1]
			var s1: float = sn[j + 1]
			var th0: float = TAU * float(j) / float(segments)
			var th1: float = TAU * float(j + 1) / float(segments)
			var p00: Vector3 = full * Vector3(r0 * c0, y0, r0 * s0)
			var p01: Vector3 = full * Vector3(r0 * c1, y0, r0 * s1)
			var p11: Vector3 = full * Vector3(r1 * c1, y1, r1 * s1)
			var p10: Vector3 = full * Vector3(r1 * c0, y1, r1 * s0)
			var n00: Vector3 = (bas * Vector3(ns.x * c0, ns.y, ns.x * s0)).normalized()
			var n01: Vector3 = (bas * Vector3(ns.x * c1, ns.y, ns.x * s1)).normalized()
			var n11: Vector3 = (bas * Vector3(ne.x * c1, ne.y, ne.x * s1)).normalized()
			var n10: Vector3 = (bas * Vector3(ne.x * c0, ne.y, ne.x * s0)).normalized()
			var u00 := Vector2(th0 * r0, slen[i]) + _uv_off
			var u01 := Vector2(th1 * r0, slen[i]) + _uv_off
			var u11 := Vector2(th1 * r1, slen[i + 1]) + _uv_off
			var u10 := Vector2(th0 * r1, slen[i + 1]) + _uv_off
			var ref_n: Vector3 = n00 + n01 + n11 + n10
			if r0 < 1.0e-4:
				_emit(PackedVector3Array([p00, p11, p10]), PackedVector3Array([n00, n11, n10]), PackedVector2Array([u00, u11, u10]), wear, ref_n)
			elif r1 < 1.0e-4:
				_emit(PackedVector3Array([p00, p01, p11]), PackedVector3Array([n00, n01, n11]), PackedVector2Array([u00, u01, u11]), wear, ref_n)
			else:
				_emit(PackedVector3Array([p00, p01, p11, p10]), PackedVector3Array([n00, n01, n11, n10]), PackedVector2Array([u00, u01, u11, u10]), wear, ref_n)


## Chamfered cylinder between two points.
func cylinder(from: Vector3, to: Vector3, radius: float, segments: int = 12, bevel: float = 0.0, caps: bool = true) -> void:
	var length: float = from.distance_to(to)
	var bw: float = minf(bevel, minf(radius, length) * 0.45)
	var prof := PackedVector3Array()
	if caps:
		prof.append(Vector3(0.0, 0.0, 0.0))
	if bw > EPS:
		prof.append(Vector3(radius - bw, 0.0, 1.0))
		prof.append(Vector3(radius, bw, 0.0))
		prof.append(Vector3(radius, length - bw, 1.0))
		prof.append(Vector3(radius - bw, length, 0.0))
	else:
		prof.append(Vector3(radius, 0.0, 0.0))
		prof.append(Vector3(radius, length, 0.0))
	if caps:
		prof.append(Vector3(0.0, length, 0.0))
	lathe(from, to, prof, segments)


func frustum(from: Vector3, to: Vector3, r_from: float, r_to: float, segments: int = 12, caps: bool = true) -> void:
	var length: float = from.distance_to(to)
	var prof := PackedVector3Array()
	if caps:
		prof.append(Vector3(0.0, 0.0, 0.0))
	prof.append(Vector3(r_from, 0.0, 0.0))
	prof.append(Vector3(r_to, length, 0.0))
	if caps:
		prof.append(Vector3(0.0, length, 0.0))
	lathe(from, to, prof, segments)


## Hemisphere (or squashed dome) bulging along `up` from `base`.
func dome(base: Vector3, up: Vector3, radius: float, height: float, segments: int = 12, rings: int = 4) -> void:
	var prof := PackedVector3Array()
	prof.append(Vector3(0.0, 0.0, 0.0))
	for k in rings + 1:
		var a: float = 0.5 * PI * float(k) / float(rings)
		prof.append(Vector3(radius * cos(a), height * sin(a), 0.0))
	lathe(base, base + up.normalized() * height, prof, segments, 60.0)


## Wheel rolling about the model X axis. Tyre + hub + (detail 2) bolt bars, animated as Part.WHEEL.
## detail: 0 = tyre + hub, 1 = + caps, 2 = + spokes.
func wheel(center: Vector3, radius: float, width: float, tyre: Color, hub: Color, detail: int = 2, segments: int = 14, animated: bool = true) -> void:
	var s_paint: Color = paint
	var s_mat: int = mat
	var s_team: float = team_mask
	var s_part: int = part
	var s_pivot: Vector3 = pivot
	var s_param: float = part_param
	var s_extra: float = part_extra
	if animated:
		set_part(Part.WHEEL, center, 0.0, radius)
	var hw: float = width * 0.5
	var rr: float = radius * 0.62
	var xa: Vector3 = center - Vector3(hw, 0.0, 0.0)
	var xb: Vector3 = center + Vector3(hw, 0.0, 0.0)
	brush(tyre, Mat.RUBBER)
	var prof := PackedVector3Array([
		Vector3(rr, 0.0, 0.0), Vector3(radius * 0.93, 0.0, 1.0), Vector3(radius, width * 0.18, 0.0),
		Vector3(radius, width * 0.82, 1.0), Vector3(radius * 0.93, width, 0.0), Vector3(rr, width, 0.0)])
	lathe(xa, xb, prof, segments)
	brush(hub, Mat.METAL)
	cylinder(center - Vector3(hw * 0.86, 0.0, 0.0), center + Vector3(hw * 0.86, 0.0, 0.0), rr * 1.02, mini(segments, 10), 0.0, true)
	if detail >= 1:
		frustum(center + Vector3(hw * 0.86, 0.0, 0.0), center + Vector3(hw + 0.02, 0.0, 0.0), rr * 0.55, rr * 0.4, 8)
		frustum(center - Vector3(hw * 0.86, 0.0, 0.0), center - Vector3(hw + 0.02, 0.0, 0.0), rr * 0.55, rr * 0.4, 8)
	if detail >= 2:
		var bar: float = rr * 1.7
		for s in [-1.0, 1.0]:
			var bx: float = center.x + s * (hw * 0.86 + 0.004)
			box(Vector3(bx, center.y, center.z), Vector3(0.012, 0.03, bar), 0.0)
			box(Vector3(bx, center.y, center.z), Vector3(0.012, bar, 0.03), 0.0)
	paint = s_paint
	mat = s_mat
	team_mask = s_team
	part = s_part
	pivot = s_pivot
	part_param = s_param
	part_extra = s_extra


# ------------------------------------------------------------------ track belts
## Closed track loop around circles (each Vector3(z, y, radius)) as the convex hull, side profile in the ZY plane.
## Emit with set_part(Part.TRACK): UV.y is arc length so the shader can scroll the tread with roll distance.
## The loop is oriented so that arc length grows along the TOP run moving forward (-Z).
func track_belt(x_center: float, width: float, circles: Array[Vector3], thickness: float = 0.06, samples: int = 12) -> void:
	var pts := PackedVector2Array()
	for c in circles:
		for k in samples:
			var a: float = TAU * float(k) / float(samples)
			pts.append(Vector2(c.x + cos(a) * c.z, c.y + sin(a) * c.z))
	var hull: PackedVector2Array = Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	var m: int = hull.size()
	var top: int = 0
	for i in m:
		if hull[i].y > hull[top].y + 1.0e-5:
			top = i
	if hull[(top + 1) % m].x > hull[top].x:
		hull.reverse()
	var cen2 := Vector2.ZERO
	for p in hull:
		cen2 += p
	cen2 /= float(m)
	_begin_prim()
	var outer := PackedVector2Array()
	var nv := PackedVector2Array()
	var s := PackedFloat32Array()
	var acc: float = 0.0
	for i in m:
		var p: Vector2 = hull[i]
		var e1: Vector2 = (p - hull[(i + m - 1) % m]).normalized()
		var e2: Vector2 = (hull[(i + 1) % m] - p).normalized()
		var n1 := Vector2(e1.y, -e1.x)
		var n2 := Vector2(e2.y, -e2.x)
		if n1.dot(p - cen2) < 0.0:
			n1 = -n1
		if n2.dot(p - cen2) < 0.0:
			n2 = -n2
		var nn: Vector2 = (n1 + n2).normalized()
		nv.append(nn)
		outer.append(p + nn * thickness)
		if i > 0:
			acc += p.distance_to(hull[i - 1])
		s.append(acc)
	var total: float = acc + hull[0].distance_to(hull[m - 1])
	var xa: float = x_center - width * 0.5
	var plate_x: float = xa + 0.04
	var plate := PackedVector3Array()
	var plate_n := PackedVector3Array()
	var plate_uv := PackedVector2Array()
	var pn: Vector3 = (_xf.basis * Vector3.RIGHT).normalized()
	for i in m:
		plate.append(_xf * Vector3(plate_x, hull[i].y, hull[i].x))
		plate_n.append(pn)
		plate_uv.append(Vector2(0.0, s[i]))
	_emit(plate, plate_n, plate_uv, 0, pn)
	var xb: float = x_center + width * 0.5
	var bas: Basis = _xf.basis
	for i in m:
		var j: int = (i + 1) % m
		var sj: float = s[j] if j > 0 else total
		var oi: Vector2 = outer[i]
		var oj: Vector2 = outer[j]
		var q := PackedVector3Array([_xf * Vector3(xa, oi.y, oi.x), _xf * Vector3(xb, oi.y, oi.x), _xf * Vector3(xb, oj.y, oj.x), _xf * Vector3(xa, oj.y, oj.x)])
		var ni: Vector3 = (bas * Vector3(0.0, nv[i].y, nv[i].x)).normalized()
		var nj: Vector3 = (bas * Vector3(0.0, nv[j].y, nv[j].x)).normalized()
		_emit(q, PackedVector3Array([ni, ni, nj, nj]), PackedVector2Array([Vector2(0.0, s[i]), Vector2(width, s[i]), Vector2(width, sj), Vector2(0.0, sj)]), 0, ni + nj)
		for side in 2:
			var xs: float = xa if side == 0 else xb
			var sn: Vector3 = (bas * Vector3(-1.0 if side == 0 else 1.0, 0.0, 0.0)).normalized()
			var pi_: Vector2 = hull[i]
			var pj_: Vector2 = hull[j]
			var sq := PackedVector3Array([_xf * Vector3(xs, pi_.y, pi_.x), _xf * Vector3(xs, pj_.y, pj_.x), _xf * Vector3(xs, oj.y, oj.x), _xf * Vector3(xs, oi.y, oi.x)])
			_emit(sq, PackedVector3Array([sn, sn, sn, sn]), PackedVector2Array([Vector2(0.0, s[i]), Vector2(0.0, sj), Vector2(thickness, sj), Vector2(thickness, s[i])]), 0, sn)


# ------------------------------------------------------------------ greebles
## Scatters small raised boxes/cylinders on a rectangle: centre + outward `normal`, half extents u_half / v_half (in-plane).
func greebles(center: Vector3, normal: Vector3, u_half: Vector3, v_half: Vector3, count: int, size_min: float, size_max: float, h_min: float, h_max: float, cyl_prob: float = 0.25) -> void:
	var n: Vector3 = normal.normalized()
	var ud: Vector3 = u_half.normalized()
	var zd: Vector3 = ud.cross(n)
	var hu: float = u_half.length()
	var hv: float = v_half.length()
	var placed: Array[Rect2] = []
	var saved_tier: int = tier
	tier = maxi(tier, 1)
	var tries: int = 0
	while placed.size() < count and tries < count * 8:
		tries += 1
		var sx: float = _rng.randf_range(size_min, size_max)
		var sz: float = _rng.randf_range(size_min, size_max)
		var h: float = _rng.randf_range(h_min, h_max)
		var a: float = _rng.randf_range(-hu + sx * 0.5, hu - sx * 0.5)
		var b: float = _rng.randf_range(-hv + sz * 0.5, hv - sz * 0.5)
		var r := Rect2(a - sx * 0.5 - 0.02, b - sz * 0.5 - 0.02, sx + 0.04, sz + 0.04)
		var ok: bool = true
		for q in placed:
			if q.intersects(r):
				ok = false
				break
		if not ok:
			continue
		placed.append(r)
		push(Transform3D(Basis(ud, n, zd), center + ud * a + zd * b + n * (h * 0.5)))
		if _rng.randf() < cyl_prob:
			cylinder(Vector3(0.0, -h * 0.5, 0.0), Vector3(0.0, h * 0.5, 0.0), minf(sx, sz) * 0.5, 8, 0.0, true)
		else:
			box(Vector3.ZERO, Vector3(sx, h, sz), 0.0)
		pop()
	tier = saved_tier


# ------------------------------------------------------------------ mirroring
## Returns a marker for mirror_x(): remembers how much geometry exists now.
func mark() -> PackedInt32Array:
	return PackedInt32Array([_pos.size(), _idx.size(), _idx_l1.size(), _idx_l2.size()])


## Duplicates everything emitted since `m` across the model X=0 plane (positions, normals, pivots, winding).
func mirror_x(m: PackedInt32Array) -> void:
	var v0: int = m[0]
	var v1: int = _pos.size()
	var shift: int = v1 - v0
	for i in range(v0, v1):
		var p: Vector3 = _pos[i]
		var nn: Vector3 = _nrm[i]
		_pos.append(Vector3(-p.x, p.y, p.z))
		_nrm.append(Vector3(-nn.x, nn.y, nn.z))
		_uv.append(_uv[i])
		_uv2.append(_uv2[i])
		_col.append(_col[i])
		_c0.append(_c0[i * 4])
		_c0.append(_c0[i * 4 + 1])
		_c0.append(_c0[i * 4 + 2])
		_c0.append(_c0[i * 4 + 3])
		_c1.append(-_c1[i * 4])
		_c1.append(_c1[i * 4 + 1])
		_c1.append(_c1[i * 4 + 2])
		_c1.append(_c1[i * 4 + 3])
	_mirror_idx(_idx, m[1], shift)
	_mirror_idx(_idx_l1, m[2], shift)
	_mirror_idx(_idx_l2, m[3], shift)


static func _mirror_idx(arr: PackedInt32Array, from_i: int, shift: int) -> void:
	var end: int = arr.size()
	for t in range(from_i, end, 3):
		arr.append(arr[t] + shift)
		arr.append(arr[t + 2] + shift)
		arr.append(arr[t + 1] + shift)


# ------------------------------------------------------------------ output
## Builds the ArrayMesh (single surface, PRIMITIVE_TRIANGLES) with LODs and a conservative custom AABB.
func build(mesh_name: String = "") -> ArrayMesh:
	var pos: PackedVector3Array = _pos
	var c1: PackedFloat32Array = _c1
	var uv2: PackedVector2Array = _uv2
	var pbox: AABB = _pivot_box
	var anim_r: float = _anim_max_r
	if not is_equal_approx(model_scale, 1.0):
		pos = Transform3D(Basis.from_scale(Vector3.ONE * model_scale), Vector3.ZERO) * _pos
		c1 = _c1.duplicate()
		for i in c1.size():
			c1[i] *= model_scale
		uv2 = _uv2.duplicate()
		for i in uv2.size():
			uv2[i] *= model_scale
		pbox = AABB(_pivot_box.position * model_scale, _pivot_box.size * model_scale)
		anim_r *= model_scale
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = _nrm
	arrays[Mesh.ARRAY_COLOR] = _col
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_CUSTOM0] = _c0
	arrays[Mesh.ARRAY_INDEX] = _idx
	var c1_fmt: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT
	if pack_half:
		var halves := PackedByteArray()
		halves.resize(c1.size() * 2)
		for i in c1.size():
			halves.encode_half(i * 2, c1[i])
		arrays[Mesh.ARRAY_CUSTOM1] = halves
		c1_fmt = Mesh.ARRAY_CUSTOM_RGBA_HALF
	else:
		arrays[Mesh.ARRAY_CUSTOM1] = c1
	var flags: int = (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (c1_fmt << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var lods: Dictionary = {}
	if _idx_l1.size() > 0 and _idx_l1.size() < _idx.size():
		lods[lod1_key] = _idx_l1
	if _idx_l2.size() > 0 and _idx_l2.size() < _idx_l1.size():
		lods[lod2_key] = _idx_l2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods, flags)
	if not mesh_name.is_empty():
		mesh.resource_name = mesh_name
	var bb: AABB = mesh.get_aabb()
	mesh.set_meta("rest_aabb", bb)
	if _has_pivot_box:
		bb = bb.merge(pbox.grow(anim_r))
	mesh.custom_aabb = bb.grow(0.05)
	return mesh
