class_name ViewInstanceBuffer
extends RefCounted
## Bulk-written MultiMesh (stride 20 floats: 12 transform + 4 colour + 4 custom) used by every overlay batch.
## Colour AND custom data are always enabled: the Compatibility renderer feeds custom data into COLOR otherwise.
## MultiMesh.buffer must always hold exactly capacity * STRIDE floats, so the array is allocated once and reused.

const STRIDE: int = 20

var node: MultiMeshInstance3D = null
var multimesh: MultiMesh = null
var capacity: int = 0
var count: int = 0
var overflow: int = 0  ## pushes dropped at capacity since the last begin()
var _buf: PackedFloat32Array = PackedFloat32Array()


## Creates the MultiMesh and the MultiMeshInstance3D under `parent`. The custom AABB is one large box so that the
## MultiMesh is never wrongly culled; call set_bounds() to tighten it to the map.
func setup(parent: Node3D, mesh: Mesh, mat: Material, cap: int, cast_shadow: bool = false) -> void:
	capacity = maxi(cap, 1)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	_buf.resize(capacity * STRIDE)
	_buf.fill(0.0)
	multimesh.buffer = _buf
	node = MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_bounds(Rect2(-4096.0, -4096.0, 8192.0, 8192.0))
	parent.add_child(node)


## Map rectangle in metres (x, z); the AABB spans it plus 100 m and generous height.
func set_bounds(map_rect: Rect2) -> void:
	multimesh.custom_aabb = AABB(Vector3(map_rect.position.x - 100.0, -200.0, map_rect.position.y - 100.0),
		Vector3(map_rect.size.x + 200.0, 600.0, map_rect.size.y + 200.0))


func begin() -> void:
	count = 0
	overflow = 0


## Drops silently at capacity, counting the overflow.
func push(xf: Transform3D, color: Color, custom: Color) -> void:
	if count >= capacity:
		overflow += 1
		return
	var o: int = count * STRIDE
	var b: Basis = xf.basis
	var t: Vector3 = xf.origin
	_buf[o] = b.x.x
	_buf[o + 1] = b.y.x
	_buf[o + 2] = b.z.x
	_buf[o + 3] = t.x
	_buf[o + 4] = b.x.y
	_buf[o + 5] = b.y.y
	_buf[o + 6] = b.z.y
	_buf[o + 7] = t.y
	_buf[o + 8] = b.x.z
	_buf[o + 9] = b.y.z
	_buf[o + 10] = b.z.z
	_buf[o + 11] = t.z
	_buf[o + 12] = color.r
	_buf[o + 13] = color.g
	_buf[o + 14] = color.b
	_buf[o + 15] = color.a
	_buf[o + 16] = custom.r
	_buf[o + 17] = custom.g
	_buf[o + 18] = custom.b
	_buf[o + 19] = custom.a
	count += 1


## Assigns the buffer and shows `count` instances. Stale tail data is harmless (visible_instance_count hides it).
func commit() -> void:
	multimesh.buffer = _buf
	multimesh.visible_instance_count = count


func set_visible(v: bool) -> void:
	if node != null:
		node.visible = v
