class_name ViewRubble
extends Node3D
## Rubble heaps of destroyed structures (render spec 5.9.8, art_direction 5.9.6 "Destroyed"): a procedural pile of charred slabs and
## girders in the footprint, rising while the model sinks, with one team-coloured roof-plate fragment so the wreck still says whose
## building it was. Stays RUBBLE_S seconds (30 s), sinks into the ground in the last SINK_S (1.5 s), smoulders via the FX port
## (wreck_start loop). Purely visual: the sim keeps no structure wreck. Cap MAX_HEAPS, oldest recycled.

const MAX_HEAPS: int = 24
const RUBBLE_S: float = 30.0
const SINK_S: float = 1.5
const GROW_DELAY_S: float = 0.35
const GROW_S: float = 0.9
const SINK_M: float = 1.0

class Heap extends RefCounted:
	var id: int = 0
	var node: MeshInstance3D = null
	var t0: float = 0.0
	var pos: Vector3 = Vector3.ZERO
	var loop_handle: int = -1
	var seed_val: int = 0


var count: int = 0

var _v: ViewWorld = null
var _heaps: Array[Heap] = []
var _mat: StandardMaterial3D = null
var _t: float = 0.0


func setup(v: ViewWorld) -> void:
	_v = v
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.95
	_mat.metallic = 0.08
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


## Starts a heap for structure `sid` at ground point `pos`. `ext` = footprint extent in metres (x, z) after rotation.
func add(sid: int, pos: Vector3, ext: Vector2, _rot: int, height_m: float, _style: StringName, team_index: int) -> void:
	if _v == null:
		return
	if _heaps.size() >= MAX_HEAPS:
		_free(_heaps[0])
		_heaps.remove_at(0)
	var h: Heap = Heap.new()
	h.id = sid
	h.pos = pos
	h.t0 = _t
	h.seed_val = sid * 7919 + 13
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = build_mesh(h.seed_val, ext, height_m, ViewTeamColors.color(team_index) if team_index >= -1 else Color(0.6, 0.6, 0.6))
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.layers = ViewLayers.MASK_UNITS
	mi.transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.02, 1.0)), pos)
	add_child(mi)
	h.node = mi
	_heaps.append(h)
	var tier: float = 0.5 + 0.2 * sqrt(maxf(ext.x * ext.y, 1.0) / 9.0)
	h.loop_handle = _v.fx.loop(&"wreck_start", pos + Vector3(0.0, 0.6, 0.0), Vector3.ZERO, tier, 0.22, 14.0, GROW_DELAY_S)


func update(dt: float) -> void:
	_t += dt
	var i: int = 0
	while i < _heaps.size():
		var h: Heap = _heaps[i]
		var age: float = _t - h.t0
		if age >= RUBBLE_S:
			_free(h)
			_heaps.remove_at(i)
			continue
		i += 1
		var k: float = clampf((age - GROW_DELAY_S) / GROW_S, 0.02, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var sink: float = 0.0
		if age > RUBBLE_S - SINK_S:
			sink = SINK_M * (age - (RUBBLE_S - SINK_S)) / SINK_S
		h.node.transform = Transform3D(Basis.from_scale(Vector3(1.0, maxf(k, 0.02), 1.0)), h.pos + Vector3(0.0, -sink, 0.0))
	count = _heaps.size()


func heap_count() -> int:
	return _heaps.size()


func has_heap(sid: int) -> bool:
	for h: Heap in _heaps:
		if h.id == sid:
			return true
	return false


func clear() -> void:
	for h: Heap in _heaps:
		_free(h)
	_heaps.clear()
	count = 0


func _free(h: Heap) -> void:
	if h.loop_handle > 0 and _v != null:
		_v.fx.stop(h.loop_handle)
	if h.node != null:
		h.node.queue_free()
		h.node = null


## The heap mesh: chunks scattered over an ellipse of the footprint, tallest in the middle. Deterministic per `seed_val`.
static func build_mesh(seed_val: int, ext: Vector2, height_m: float, team: Color) -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var area: float = ext.x * ext.y
	var n: int = clampi(int(area / 1.5), 18, 96)
	var k: float = clampf(minf(ext.x, ext.y) / 5.0, 0.6, 1.8)
	var hmax: float = clampf(height_m * 0.28, 0.9, 3.2)
	for i: int in n:
		var ang: float = rng.randf() * TAU
		var rr: float = sqrt(rng.randf()) * 0.46
		var px: float = cos(ang) * rr * ext.x
		var pz: float = sin(ang) * rr * ext.y
		var prof: float = clampf(1.0 - rr * rr * 4.0, 0.05, 1.0)
		var sz: Vector3 = Vector3(rng.randf_range(0.5, 1.7), rng.randf_range(0.25, 0.9), rng.randf_range(0.5, 1.5)) * k
		if rng.randf() < 0.2:
			sz = Vector3(rng.randf_range(2.0, 3.4), rng.randf_range(0.12, 0.22), rng.randf_range(0.14, 0.25)) * k  # girder
		var py: float = prof * hmax * rng.randf_range(0.35, 1.0) + sz.y * 0.35
		var tilt: Basis = Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
		var g: float = rng.randf_range(0.03, 0.075)
		var col: Color = Color(g * 1.5, g * 1.05, g * 0.8)  # charred debris
		var pick: float = rng.randf()
		if pick < 0.22:
			col = Color(0.12, 0.10, 0.08) * rng.randf_range(0.6, 1.0)  # scorched concrete slab
		elif pick < 0.36:
			col = Color(0.12, 0.045, 0.018) * rng.randf_range(0.7, 1.2)  # rusted plate
		_box(st, Transform3D(tilt, Vector3(px, py, pz)), sz, col)
	# the roof plate: one flat slab in the owner's colour, on top of the heap
	var plate_col: Color = team.darkened(0.55)
	_box(st, Transform3D(Basis.from_euler(Vector3(0.12, 0.6, -0.1)), Vector3(ext.x * 0.06, hmax * 0.85, ext.y * 0.05)), Vector3(1.3, 0.08, 0.9) * k, plate_col)
	return st.commit()


static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h: Vector3 = size * 0.5
	var faces: Array = [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
		[Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT],
		[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for f: Array in faces:
		var n: Vector3 = f[0] as Vector3
		var u: Vector3 = f[1] as Vector3
		var w: Vector3 = f[2] as Vector3
		var c: Vector3 = n * h
		var a: Vector3 = xf * (c - u * h - w * h)
		var b: Vector3 = xf * (c - u * h + w * h)
		var d: Vector3 = xf * (c + u * h + w * h)
		var e: Vector3 = xf * (c + u * h - w * h)
		var nn: Vector3 = (xf.basis * n).normalized()
		# subtle per-face shading so the flat boxes read as chunky stone
		var shade: float = 0.85 + 0.3 * maxf(nn.y, 0.0)
		var cc: Color = Color(col.r * shade, col.g * shade, col.b * shade)
		for p: Vector3 in [a, b, d, a, d, e]:
			st.set_color(cc)
			st.set_normal(nn)
			st.add_vertex(p)
