class_name ViewBlobShadows
extends Node3D
## Cheap fake shadows for the Low preset (real shadow maps off): one MultiMesh of terrain-aligned quads, one draw call
## for any number of units, no dependence on light setup, works in every renderer.

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var last_update_us: int = 0


func setup(capacity: int) -> void:
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/blob_shadow.gdshader")
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = quad
	_mm.instance_count = capacity
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 4000.0
	add_child(_mmi)


## positions: ground positions; radii: blob radius in metres. Aligns each quad to the terrain normal.
func update(terrain: ViewTerrain, positions: PackedVector3Array, radii: PackedFloat32Array) -> void:
	var t0: int = Time.get_ticks_usec()
	var n: int = mini(positions.size(), _mm.instance_count)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(_mm.instance_count * 12)   # MultiMesh.buffer must always match instance_count*stride
	for i in n:
		var p: Vector3 = positions[i]
		var up: Vector3 = terrain.normal_at(p.x, p.z)
		var b: Basis = Basis(Quaternion(Vector3.UP, up)).scaled_local(Vector3(radii[i] * 2.0, 1.0, radii[i] * 2.0))
		var y: float = terrain.height_at(p.x, p.z) + 0.07
		var o: int = i * 12
		buf[o] = b.x.x
		buf[o + 1] = b.y.x
		buf[o + 2] = b.z.x
		buf[o + 3] = p.x
		buf[o + 4] = b.x.y
		buf[o + 5] = b.y.y
		buf[o + 6] = b.z.y
		buf[o + 7] = y
		buf[o + 8] = b.x.z
		buf[o + 9] = b.y.z
		buf[o + 10] = b.z.z
		buf[o + 11] = p.z
	_mm.buffer = buf
	_mm.visible_instance_count = n
	last_update_us = Time.get_ticks_usec() - t0
