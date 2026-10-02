class_name ViewRibbon
extends RefCounted
## CPU builder of the ground ribbons drawn by line.gdshader (render spec 5.10): polylines and rings become triangle strips
## with `UV = (side, distance)`, `NORMAL = tangent`, `UV2 = (style, width multiplier)`, `COLOR = colour`. One instance owns
## one ArrayMesh (a single surface, rebuilt in `commit()`), so a whole overlay is one draw call. Presentation only.

const STYLE_MARCH: float = 0.0
const STYLE_SOLID: float = 1.0
const STYLE_DASH: float = 2.0
const STYLE_DOTS: float = 3.0
const STYLE_BUILD: float = 4.0
const CORNER_SPLIT_DOT: float = 0.6  ## a turn sharper than this splits the strip (no pinched joint)
const SHADER_PATH: String = "res://assets/shaders/line.gdshader"

var mesh: ArrayMesh = ArrayMesh.new()
var node: MeshInstance3D = null
var material: ShaderMaterial = null
var vertex_count: int = 0
var strips: int = 0

var _pos: PackedVector3Array = PackedVector3Array()
var _tan: PackedVector3Array = PackedVector3Array()
var _uv: PackedVector2Array = PackedVector2Array()
var _uv2: PackedVector2Array = PackedVector2Array()
var _col: PackedColorArray = PackedColorArray()
var _idx: PackedInt32Array = PackedInt32Array()


## Creates the MeshInstance3D under `parent` with a `line.gdshader` material of the given stroke width.
func setup(parent: Node3D, width_px: float, priority: int, map_rect: Rect2 = Rect2(-4096.0, -4096.0, 8192.0, 8192.0)) -> void:
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	material.render_priority = priority
	material.set_shader_parameter(&"width_px", width_px)
	node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.layers = ViewLayers.MASK_OVERLAYS
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.extra_cull_margin = 16384.0
	parent.add_child(node)
	set_bounds(map_rect)


func set_bounds(map_rect: Rect2) -> void:
	mesh.custom_aabb = AABB(Vector3(map_rect.position.x - 100.0, -200.0, map_rect.position.y - 100.0), Vector3(map_rect.size.x + 200.0, 600.0, map_rect.size.y + 200.0))


func begin() -> void:
	_pos.clear()
	_tan.clear()
	_uv.clear()
	_uv2.clear()
	_col.clear()
	_idx.clear()
	vertex_count = 0
	strips = 0


## Appends `pts` (>= 2 points, ground positions already lifted) as one or more strips. `closed` joins the last point to the first.
func add_polyline(pts: PackedVector3Array, color: Color, style: float, width_mul: float = 1.0, closed: bool = false) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var p: PackedVector3Array = pts
	if closed:
		p = pts.duplicate()
		p.append(pts[0])
		n += 1
	# per-segment unit directions
	var dirs: PackedVector3Array = PackedVector3Array()
	dirs.resize(n - 1)
	for i: int in n - 1:
		var d: Vector3 = p[i + 1] - p[i]
		var l: float = d.length()
		dirs[i] = d / l if l > 0.0001 else Vector3.RIGHT
	# split at sharp corners
	var start: int = 0
	var dist0: float = 0.0
	var run_dist: float = 0.0
	for i2: int in n - 1:
		var last: bool = i2 == n - 2
		var split: bool = last or dirs[i2].dot(dirs[i2 + 1]) < CORNER_SPLIT_DOT
		run_dist += p[i2].distance_to(p[i2 + 1])
		if split:
			_strip(p, dirs, start, i2 + 1, dist0, color, style, width_mul)
			start = i2 + 1
			dist0 = run_dist
	strips += 1


func _strip(p: PackedVector3Array, dirs: PackedVector3Array, from: int, to: int, dist0: float, color: Color, style: float, wmul: float) -> void:
	var base: int = _pos.size()
	var d: float = dist0
	for i: int in range(from, to + 1):
		var t: Vector3
		if i == from:
			t = dirs[from]
		elif i == to:
			t = dirs[to - 1]
		else:
			t = (dirs[i - 1] + dirs[i]).normalized()
		if i > from:
			d += p[i].distance_to(p[i - 1])
		for s: int in 2:
			_pos.append(p[i])
			_tan.append(t)
			_uv.append(Vector2(-1.0 if s == 0 else 1.0, d))
			_uv2.append(Vector2(style, wmul))
			_col.append(color)
	var segs: int = to - from
	for k: int in segs:
		var a: int = base + k * 2
		_idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	vertex_count = _pos.size()


## Uploads everything added since begin(); an empty set clears the surface.
func commit() -> void:
	mesh.clear_surfaces()
	if _idx.is_empty():
		if node != null:
			node.visible = false
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _pos
	arrays[Mesh.ARRAY_NORMAL] = _tan
	arrays[Mesh.ARRAY_COLOR] = _col
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_INDEX] = _idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if node != null:
		node.visible = true


## Number of triangles in the committed surface (tests).
func triangle_count() -> int:
	return _idx.size() / 3


## Ground polyline helper: samples `a -> b` every `step` metres and lifts each point above `ground` (Callable(x, z) -> y).
static func sample_segment(out: PackedVector3Array, a: Vector2, b: Vector2, step: float, ground: Callable, lift: float, include_start: bool) -> void:
	var span: float = a.distance_to(b)
	var n: int = maxi(int(ceilf(span / step)), 1)
	for i: int in range(0 if include_start else 1, n + 1):
		var q: Vector2 = a.lerp(b, float(i) / float(n))
		out.append(Vector3(q.x, (ground.call(q.x, q.y) as float) + lift, q.y))


## Ground circle of `radius_m` around (cx, cz), `n` points, lifted above the terrain.
static func circle_points(cx: float, cz: float, radius_m: float, n: int, ground: Callable, lift: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(n)
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		var x: float = cx + cos(a) * radius_m
		var z: float = cz + sin(a) * radius_m
		out[i] = Vector3(x, (ground.call(x, z) as float) + lift, z)
	return out
