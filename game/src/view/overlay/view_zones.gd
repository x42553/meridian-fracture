class_name ViewZones
extends Node3D
## Zones drawn WITHOUT models (render spec 5.9.7): smoke Dust Screen, debris-slow field, repair station, sensor puck, shelter, portable
## cover, decoy hologram, buff aura, scan ping and the Trident interception dome. The zones are SimZone records
## (`sim.zones.active_zones()`, not entities); they are polled at 10 Hz and mirrored by one terrain-conforming grid mesh each
## (ViewGroundMesh + zone.gdshader), plus a hemisphere for the dome. Zones the local team may not see (`SimZoneSystem.visible_to`)
## are skipped, decoy zones only ever show to their own team, and zones of other teams fade with the fog of war.
## New zones fade in over FADE_IN_S, removed ones out over FADE_OUT_S (0.4 s). Presentation only.

const CAP: int = 32
const SYNC_S: float = 0.1
const FADE_IN_S: float = 0.3
const FADE_OUT_S: float = 0.4
const SHADER_PATH: String = "res://assets/shaders/zone.gdshader"
const DOME_SHADER_PATH: String = "res://assets/shaders/zone_dome.gdshader"
const SMOKE_LIFTS: Array[float] = [0.22, 1.1, 2.3, 3.5]
const FLAT_LIFT: float = 0.22
const MAX_CHARGES: float = 24.0
## Tint per DefEnums.ZoneKind (BUFF 0 SMOKE 1 INTERCEPT 2 DEBRIS 3 DECOY 4 PUCK 5 SHELTER 6 COVER 7 REPAIR 8 REVEAL 9), sRGB.
const TINTS: Array[Color] = [
	Color(0.45, 0.72, 1.0), Color(0.80, 0.78, 0.72), Color(0.35, 0.85, 1.0), Color(0.90, 0.62, 0.25), Color(0.35, 0.95, 0.85),
	Color(0.30, 0.90, 1.0), Color(0.95, 0.80, 0.45), Color(0.55, 0.75, 1.0), Color(0.45, 1.0, 0.75), Color(1.0, 0.85, 0.35),
]

class Vis extends RefCounted:
	var id: int = 0
	var kind: int = 0
	var node: MeshInstance3D = null
	var mat: ShaderMaterial = null
	var dome: MeshInstance3D = null
	var dome_mat: ShaderMaterial = null
	var center: Vector2 = Vector2.ZERO
	var yaw: float = 0.0
	var hl: float = 0.0
	var r: float = 6.0
	var t_start: int = 0
	var fade: float = 0.0
	var dying: bool = false
	var charge: float = 1.0
	var warm: float = 0.0
	var friendly: bool = true
	var seen: int = 0


var count: int = 0  ## zones drawn last update
var created: int = 0

var _v: ViewWorld = null
var _vis: Dictionary = {}  # zone id -> Vis
var _t: float = 1.0e9
var _shader: Shader = null
var _dome_shader: Shader = null
var _dome_mesh: SphereMesh = null
var _stamp: int = 0


func setup(v: ViewWorld) -> void:
	_v = v
	_shader = load(SHADER_PATH) as Shader
	_dome_shader = load(DOME_SHADER_PATH) as Shader
	_dome_mesh = SphereMesh.new()
	_dome_mesh.radius = 1.0
	_dome_mesh.height = 1.0
	_dome_mesh.is_hemisphere = true
	_dome_mesh.radial_segments = 48
	_dome_mesh.rings = 16


## Re-reads the zone table at the next update (a zone spawned or ended).
func request_sync() -> void:
	_t = 1.0e9


func zone_ids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k: Variant in _vis:
		out.append(k as int)
	out.sort()
	return out


func vis_of(zone_id: int) -> Vis:
	return _vis.get(zone_id) as Vis


func clear() -> void:
	for k: Variant in _vis.keys():
		_free(_vis[k] as Vis)
	_vis.clear()
	count = 0


func update(dt: float) -> void:
	if _v == null or _v.sim == null or _v.sim.zones == null:
		return
	_t += dt
	if _t >= SYNC_S:
		_t = 0.0
		_sync()
	var n: int = 0
	var now_t: float = _v.time
	var gone: Array[int] = []
	for k: Variant in _vis:
		var z: Vis = _vis[k] as Vis
		var target: float = 0.0 if z.dying else 1.0
		var rate: float = (1.0 / FADE_OUT_S) if z.dying else (1.0 / FADE_IN_S)
		z.fade = move_toward(z.fade, target, dt * rate)
		if z.dying and z.fade <= 0.0:
			gone.append(k as int)
			continue
		var age: float = maxf((float(_v.tick) + _v.alpha - float(z.t_start)) * 0.05, 0.0)
		z.mat.set_shader_parameter(&"tm", Vector4(now_t, age, z.fade, z.warm))
		if z.dome_mat != null:
			z.mat.set_shader_parameter(&"geom", Vector4(z.hl, z.r, 1.0, z.charge))
			z.dome_mat.set_shader_parameter(&"t_anim", now_t)
			z.dome_mat.set_shader_parameter(&"fade", z.fade)
			z.dome_mat.set_shader_parameter(&"charge01", z.charge)
		n += 1
	for id: int in gone:
		_free(_vis[id] as Vis)
		_vis.erase(id)
	count = n


func _sync() -> void:
	_stamp += 1
	var zones: Array[SimZone] = _v.sim.zones.active_zones()
	var team: int = -1
	if _v.local_pid >= 0 and _v.local_pid < _v.sim.players.size():
		team = _v.sim.players[_v.local_pid].team
	for zone: SimZone in zones:
		if zone.kind == SimZoneConsts.ZK_WARNING:
			continue
		var friendly: bool = _v.observer or zone.team == team
		if not _v.observer and not _v.sim.zones.visible_to(zone, _v.local_pid):
			continue
		if zone.kind == DefEnums.ZoneKind.DECOY and not friendly:
			continue
		var z: Vis = _vis.get(zone.id) as Vis
		if z == null:
			if _vis.size() >= CAP:
				continue
			z = _create(zone, friendly)
			_vis[zone.id] = z
		z.seen = _stamp
		z.dying = false
		z.charge = clampf(float(zone.charges) / MAX_CHARGES, 0.0, 1.0) if zone.kind == DefEnums.ZoneKind.INTERCEPT else 1.0
		z.warm = 1.0 if zone.state == SimZoneConsts.ZS_WARMUP else 0.0
		var c: Vector2 = Vector2(float(zone.x), float(zone.y)) * ViewConsts.M_PER_UNIT
		if c.distance_to(z.center) > 0.75:  # a zone that follows its body: rebuild the conforming mesh
			_rebuild(z, zone)
	for k: Variant in _vis:
		var z2: Vis = _vis[k] as Vis
		if z2.seen != _stamp:
			z2.dying = true


func _create(zone: SimZone, friendly: bool) -> Vis:
	var z: Vis = Vis.new()
	z.id = zone.id
	z.kind = zone.kind
	z.t_start = zone.t_start
	z.friendly = friendly
	z.mat = ShaderMaterial.new()
	z.mat.shader = _shader
	z.mat.render_priority = 4
	z.mat.set_shader_parameter(&"kind", clampi(zone.kind, 0, 9))
	var tint: Color = TINTS[clampi(zone.kind, 0, 9)]
	z.mat.set_shader_parameter(&"tint", tint)
	z.mat.set_shader_parameter(&"hostile", 0.0 if friendly else 1.0)
	z.mat.set_shader_parameter(&"use_fog", 0.0 if friendly else 1.0)
	z.node = MeshInstance3D.new()
	z.node.material_override = z.mat
	z.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	z.node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	z.node.layers = ViewLayers.MASK_OVERLAYS
	add_child(z.node)
	if zone.kind == DefEnums.ZoneKind.INTERCEPT:
		z.dome_mat = ShaderMaterial.new()
		z.dome_mat.shader = _dome_shader
		z.dome_mat.render_priority = 5
		z.dome_mat.set_shader_parameter(&"tint", tint)
		z.dome_mat.set_shader_parameter(&"hostile", 0.0 if friendly else 1.0)
		z.dome_mat.set_shader_parameter(&"use_fog", 0.0 if friendly else 1.0)
		z.dome = MeshInstance3D.new()
		z.dome.mesh = _dome_mesh
		z.dome.material_override = z.dome_mat
		z.dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		z.dome.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		z.dome.layers = ViewLayers.MASK_OVERLAYS
		add_child(z.dome)
	_rebuild(z, zone)
	created += 1
	return z


func _rebuild(z: Vis, zone: SimZone) -> void:
	z.center = Vector2(float(zone.x), float(zone.y)) * ViewConsts.M_PER_UNIT
	z.r = float(zone.radius) * ViewConsts.M_PER_UNIT
	z.hl = 0.0
	z.yaw = 0.0
	if zone.shape == DefEnums.ZoneShape.LINE:
		var dx: float = float(zone.bx - zone.ax)
		var dy: float = float(zone.by - zone.ay)
		z.hl = sqrt(dx * dx + dy * dy) * 0.5 * ViewConsts.M_PER_UNIT
		z.yaw = atan2(dy, dx)
	var margin: float = 1.2
	var half: Vector2 = Vector2(z.hl + z.r + margin, z.r + margin)
	var lifts: PackedFloat32Array = PackedFloat32Array()
	if zone.kind == DefEnums.ZoneKind.SMOKE:
		for l: float in SMOKE_LIFTS:
			lifts.append(l)
	else:
		lifts.append(FLAT_LIFT)
	var step: float = clampf(maxf(half.x, half.y) / 40.0, 0.6, 1.0)
	z.node.mesh = ViewGroundMesh.build(_v, z.center, z.yaw, half, step, lifts)
	z.mat.set_shader_parameter(&"geom", Vector4(z.hl, z.r, float(lifts.size()), z.charge))
	if z.dome != null:
		z.dome.transform = Transform3D(Basis.from_scale(Vector3(z.r, z.r, z.r)), Vector3(z.center.x, _v.ground_at(z.center.x, z.center.y), z.center.y))


func _free(z: Vis) -> void:
	if z.node != null:
		z.node.queue_free()
		z.node = null
	if z.dome != null:
		z.dome.queue_free()
		z.dome = null
