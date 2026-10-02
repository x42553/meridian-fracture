class_name ViewBlobShadows
extends Node3D
## Cheap fake shadows for the Low preset (sun shadow maps off): ONE MultiMesh of terrain-aligned quads, one draw call for any
## number of units, independent of the light set-up, works in every renderer (render spec 5.6 / 5.12). Aircraft use an alpha of
## `1 - altitude / 40`. The terrain normal comes from a lazily filled per-cell cache, so an update of 400 units stays near 0.5 ms.
## Presentation only.

const SHADER_PATH: String = "res://assets/shaders/blob_shadow.gdshader"
const LIFT_M: float = 0.07
const FLOATS: int = 16  ## 12 transform + 4 colour (rgb white, a = alpha)

var last_update_us: int = 0
var capacity: int = 0
var shown: int = 0
var material: ShaderMaterial = null

var _mmi: MultiMeshInstance3D = null
var _mm: MultiMesh = null
var _buf: PackedFloat32Array = PackedFloat32Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _normal_ok: PackedByteArray = PackedByteArray()
var _cache_terrain: ViewTerrain = null
var _cache_w: int = 0


func setup(cap: int) -> void:
	capacity = cap
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = cap
	_mm.visible_instance_count = 0
	_buf = PackedFloat32Array()
	_buf.resize(cap * FLOATS)
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = material
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mmi.layers = ViewLayers.MASK_WORLD
	_mmi.extra_cull_margin = 4000.0
	add_child(_mmi)


## `positions`: ground positions (world, y ignored); `radii`: blob radius in metres; `alphas`: per-blob opacity 0..1 (aircraft
## `1 - altitude / 40`; missing entries count as 1). Aligns each quad to the terrain normal.
func update(t: ViewTerrain, positions: PackedVector3Array, radii: PackedFloat32Array, alphas: PackedFloat32Array = PackedFloat32Array()) -> void:
	var t0: int = Time.get_ticks_usec()
	_bind(t)
	var n: int = mini(positions.size(), capacity)
	var cell_m: float = ViewConsts.CELL_M
	var buf: PackedFloat32Array = _buf
	for i: int in n:
		var p: Vector3 = positions[i]
		var cx: int = clampi(int(p.x / cell_m), 0, _cache_w - 1)
		var cz: int = clampi(int(p.z / cell_m), 0, _normals.size() / _cache_w - 1)
		var ci: int = cz * _cache_w + cx
		if _normal_ok[ci] == 0:
			_normals[ci] = t.normal_at((float(cx) + 0.5) * cell_m, (float(cz) + 0.5) * cell_m)
			_normal_ok[ci] = 1
		var up: Vector3 = _normals[ci]
		# tangent frame of the ground plane: bx x up = bz (up.y > 0 for any heightfield)
		var bx: Vector3 = Vector3(up.y, -up.x, 0.0).normalized()
		var bz: Vector3 = bx.cross(up)
		var r2: float = radii[i] * 2.0
		var y: float = t.height_at(p.x, p.z) + LIFT_M
		var o: int = i * FLOATS
		buf[o] = bx.x * r2
		buf[o + 1] = up.x
		buf[o + 2] = bz.x * r2
		buf[o + 3] = p.x
		buf[o + 4] = bx.y * r2
		buf[o + 5] = up.y
		buf[o + 6] = bz.y * r2
		buf[o + 7] = y
		buf[o + 8] = bx.z * r2
		buf[o + 9] = up.z
		buf[o + 10] = bz.z * r2
		buf[o + 11] = p.z
		buf[o + 12] = 1.0
		buf[o + 13] = 1.0
		buf[o + 14] = 1.0
		buf[o + 15] = clampf(alphas[i], 0.0, 1.0) if i < alphas.size() else 1.0
	_buf = buf
	_mm.buffer = buf  # must always equal instance_count * stride, even when visible_instance_count is smaller
	_mm.visible_instance_count = n
	shown = n
	last_update_us = Time.get_ticks_usec() - t0


func _bind(t: ViewTerrain) -> void:
	if t == _cache_terrain:
		return
	_cache_terrain = t
	_cache_w = t.src.width
	var cells: int = t.src.width * t.src.height
	_normals = PackedVector3Array()
	_normals.resize(cells)
	_normal_ok = PackedByteArray()
	_normal_ok.resize(cells)
