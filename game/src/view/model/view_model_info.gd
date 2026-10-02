class_name ViewModelInfo
extends RefCounted
## Metadata of a built model (render spec 3.5): bounds, radius / height, animated part mask, sockets, tri counts,
## recipe meta. Filled by ViewMeshBuilder.build(); the recipe interpreter sets the meta fields (hover, footprint, ...).

## Named attach point (muzzle, exhaust, weld, door_exit, top ...). A socket on a moving part carries that part's record so
## socket_world() can replay the vertex-shader transform on the CPU.
class ViewSocket extends RefCounted:
	var pos: Vector3 = Vector3.ZERO
	var dir: Vector3 = Vector3.FORWARD
	var part: int = 0  ## ViewMeshBuilder.Part kind, 0 = static
	var pivot: Vector3 = Vector3.ZERO
	var param: float = 0.0  ## part param 0..1 (barrel elevation scale)
	var extra: float = 0.0  ## part extra (recoil travel m)
	var trunnion: Vector2 = Vector2.ZERO  ## barrel trunnion (y, z), model space

var rest_aabb: AABB = AABB()
var radius: float = 0.0  ## max horizontal extent from the origin (m)
var height: float = 0.0  ## top of the rest AABB (m)
var hover: float = 0.0  ## default air altitude (m)
var parts_mask: int = 0  ## bit k set = Part kind k present
var members: int = 1  ## squad size (gait parts)
var footprint: Vector2i = Vector2i.ZERO  ## cells (structures)
var death_kind: StringName = &""
var death_ticks: int = 0
var buildup_ticks: int = 30
var spawn_fx: StringName = &""
var sockets: Dictionary = {}  ## StringName -> ViewSocket
var tris: Vector3i = Vector3i.ZERO  ## triangle counts of LOD0, LOD1, LOD2
var verts: int = 0
var build_ms: float = 0.0
var content_hash: int = 0
var livery_tris: Vector3i = Vector3i.ZERO  ## triangles (LOD0 / 1 / 2) of the subfaction livery (ViewLivery); the art direction budgets exclude them
var boost: float = 1.0  ## VQ2A readability boost baked into this model (ViewConsts.visual_boost); size caps of the art direction cards are design-scale, multiply them by it


func has_part(kind: int) -> bool:
	return (parts_mask >> kind) & 1 == 1


func has_socket(sock_name: StringName) -> bool:
	return sockets.has(sock_name)


## World-space (model-space through `xf`) position of a socket, replicating the unit shader's part transform:
## BARREL parts recoil along +Z by recoil * extra, elevate about the trunnion by elev * param * PI/2, then yaw with the
## turret; TURRET parts yaw about their pivot; everything else is static. Missing sockets return `xf.origin`.
func socket_world(sock_name: StringName, xf: Transform3D, turret_yaw: float, elev: float, recoil: float) -> Vector3:
	var s: ViewSocket = sockets.get(sock_name) as ViewSocket
	if s == null:
		return xf.origin
	return xf * _part_transform(s, s.pos, turret_yaw, elev, recoil)


## Direction of a socket (unit vector) in the same frame as socket_world().
func socket_dir_world(sock_name: StringName, xf: Transform3D, turret_yaw: float, elev: float, recoil: float) -> Vector3:
	var s: ViewSocket = sockets.get(sock_name) as ViewSocket
	if s == null:
		return -xf.basis.z
	var a: Vector3 = _part_transform(s, s.pos, turret_yaw, elev, recoil)
	var b: Vector3 = _part_transform(s, s.pos + s.dir, turret_yaw, elev, recoil)
	return (xf.basis * (b - a)).normalized()


static func _is_turret(kind: int) -> bool:
	return kind == ViewMeshBuilder.Part.TURRET or kind == ViewMeshBuilder.Part.TURRET1 \
		or kind == ViewMeshBuilder.Part.TURRET2 or kind == ViewMeshBuilder.Part.TURRET3


static func _is_barrel(kind: int) -> bool:
	return kind == ViewMeshBuilder.Part.BARREL or kind == ViewMeshBuilder.Part.BARREL1 \
		or kind == ViewMeshBuilder.Part.BARREL2 or kind == ViewMeshBuilder.Part.BARREL3


func _part_transform(s: ViewSocket, p: Vector3, turret_yaw: float, elev: float, recoil: float) -> Vector3:
	if _is_barrel(s.part):
		var q: Vector3 = p - s.pivot
		var trn: Vector3 = Vector3(0.0, s.trunnion.x - s.pivot.y, s.trunnion.y - s.pivot.z)
		var r: Vector3 = q - trn
		r.z += recoil * s.extra
		r = Basis(Vector3.RIGHT, elev * s.param * PI * 0.5) * r
		q = trn + r
		return s.pivot + Basis(Vector3.UP, turret_yaw) * q
	if _is_turret(s.part):
		return s.pivot + Basis(Vector3.UP, turret_yaw) * (p - s.pivot)
	return p
