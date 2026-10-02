class_name FxAmbient
extends RefCounted
## Continuous, state-driven effects that no single event owns (render spec 5.9.8, 5.9.1 stampers): damage smoke / fire on hurt
## entities (0.4 s interval, at most 24 scene-wide, the nearest to the camera win, re-evaluated at 2 Hz) and locomotion effects
## (vehicle dust, contrails, rotor wash, ship wakes; scanned at 4 Hz over a third of the entities per pass). Also the falling trail of
## a crashing aircraft. Presentation only.

const DAMAGE_CAP: int = 24
const DAMAGE_INTERVAL: float = 0.4
const RESELECT_S: float = 0.5
const SCAN_S: float = 0.25
const DUST_INTERVAL: float = 0.45
const WAKE_INTERVAL: float = 0.55
const TRAIL_INTERVAL: float = 0.3

var stat_damage_active: int = 0
var stat_spawned: int = 0
var damage_cap: int = DAMAGE_CAP

var _t: float = 0.0
var _next_reselect: float = 0.0
var _next_scan: float = 0.0
var _scan_phase: int = 0
var _cand: Dictionary = {}  # entity id -> true (has been hit)
var _active: Dictionary = {}  # entity id -> next spawn time
var _next_fx: Dictionary = {}  # entity id * 8 + kind -> next time (locomotion throttles)


func note_damaged(id: int) -> void:
	_cand[id] = true


func forget(id: int) -> void:
	_cand.erase(id)
	_active.erase(id)


## The number of entities currently emitting damage smoke / fire (tests, HUD stats).
func active_count() -> int:
	return _active.size()


func active_ids() -> Array:
	return _active.keys()


func start_crash_trail(r: FxEventRouter, ve: ViewEntity) -> void:
	if ve == null or ve.rig == null or r.fx == null:
		return
	if ve.stamper > 0:
		r.fx.stop_emitter(ve.stamper)
	ve.stamper = r.fx.start_stamper(&"crash_smoke", ve.rig, 1.1, 2.4, clampf(ve.radius_m / 1.6, 0.7, 2.0))


func stop_crash_trail(r: FxEventRouter, ve: ViewEntity) -> void:
	if ve != null and ve.stamper > 0:
		r.fx.stop_emitter(ve.stamper)
		ve.stamper = -1


func frame(r: FxEventRouter, dt: float) -> void:
	_t += dt
	if _t >= _next_reselect:
		_next_reselect = _t + RESELECT_S
		_reselect(r)
	_emit_damage(r)
	if _t >= _next_scan:
		_next_scan = _t + SCAN_S
		_scan_locomotion(r)


# ---------------------------------------------------------------------------------------------- damage emitters
func _reselect(r: FxEventRouter) -> void:
	var cam_pos: Vector3 = Vector3.ZERO
	var has_cam: bool = r.v.camera != null and r.v.camera.camera != null
	if has_cam:
		cam_pos = r.v.camera.camera.global_position if r.v.camera.camera.is_inside_tree() else r.v.camera.camera.position
	var scored: Array = []
	var drop: Array = []
	for id_v: Variant in _cand:
		var id: int = id_v as int
		var ve: ViewEntity = r.v.entity_view(id)
		if ve == null or ve.dead or ve.sim_gone or ve.max_hp <= 0:
			drop.append(id)
			continue
		var frac: float = float(ve.hp) / float(ve.max_hp)
		if frac >= r.fx_damage_threshold("smoke_below"):
			if frac > 0.75:
				drop.append(id)  # healed
			continue
		if ve.vs != ViewConsts.VS_VISIBLE or ve.kind == SimEntity.Kind.WRECK:
			continue
		var d2: float = 0.0
		if has_cam:
			d2 = cam_pos.distance_squared_to(Vector3(ve.wx, ve.wy, ve.wz))
		scored.append([d2, id])
	for id2: Variant in drop:
		_cand.erase(id2)
		_active.erase(id2)
	scored.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as float) < (b[0] as float))
	var keep: Dictionary = {}
	var n: int = mini(scored.size(), damage_cap)
	for i: int in n:
		var eid: int = (scored[i] as Array)[1] as int
		keep[eid] = true
		if not _active.has(eid):
			_active[eid] = _t + float(eid % 7) * 0.05
	for k: Variant in _active.keys():
		if not keep.has(k):
			_active.erase(k)
	stat_damage_active = _active.size()


func _emit_damage(r: FxEventRouter) -> void:
	if _active.is_empty():
		return
	var fire_below: float = r.fx_damage_threshold("fire_below")
	for id_v: Variant in _active:
		var nxt: float = _active[id_v] as float
		if _t < nxt:
			continue
		_active[id_v] = _t + DAMAGE_INTERVAL
		var ve: ViewEntity = r.v.entity_view(id_v as int)
		if ve == null or ve.max_hp <= 0:
			continue
		var frac: float = float(ve.hp) / float(ve.max_hp)
		var structural: bool = ve.kind == SimEntity.Kind.STRUCTURE or ve.kind == SimEntity.Kind.NEUTRAL
		var s: float = clampf(ve.radius_m / (1.6 if not structural else 2.4), 0.6, 3.2)
		var p: Vector3 = Vector3(ve.wx, ve.wy + ve.height_m * (0.55 if not structural else 0.8), ve.wz)
		if structural:
			p += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * ve.radius_m * 0.6
		stat_spawned += 1
		r.spawn(&"damage_fire" if frac < fire_below else &"damage_smoke", p, Vector3.ZERO, s)


# ---------------------------------------------------------------------------------------------- locomotion
func _scan_locomotion(r: FxEventRouter) -> void:
	_scan_phase = (_scan_phase + 1) % 3
	var ents: Array[ViewEntity] = r.v.entities()
	var rect: Rect2 = r.v.camera.visible_ground_rect() if r.v.camera != null else Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
	for ve: ViewEntity in ents:
		if (ve.id % 3) != _scan_phase or ve.vs != ViewConsts.VS_VISIBLE or ve.dead or not ve.in_view:
			continue
		if ve.kind != SimEntity.Kind.UNIT or ve.move01 < 0.3:
			continue
		if not rect.has_point(Vector2(ve.wx, ve.wz)):
			continue
		match ve.motion:
			ViewConsts.MOTION_WHEELED, ViewConsts.MOTION_TRACKED:
				_dust(r, ve)
			ViewConsts.MOTION_AMPHIBIOUS:
				if r.v.terrain != null and not r.v.terrain.is_water_at(ve.wx, ve.wz):
					_dust(r, ve)
				else:
					_wake(r, ve)
			ViewConsts.MOTION_NAVAL:
				_wake(r, ve)
			ViewConsts.MOTION_AIR_FIXED:
				_contrail(r, ve)
			ViewConsts.MOTION_AIR_HOVER:
				_rotor(r, ve)


func _due(id: int, kind: int, interval: float) -> bool:
	var key: int = id * 8 + kind
	if _t < (_next_fx.get(key, 0.0) as float):
		return false
	_next_fx[key] = _t + interval * randf_range(0.85, 1.15)
	if _next_fx.size() > 2048:
		_next_fx.clear()
	return true


func _forward(ve: ViewEntity) -> Vector3:
	return Basis(Vector3.UP, ve.yaw) * Vector3(0.0, 0.0, -1.0)


func _dust(r: FxEventRouter, ve: ViewEntity) -> void:
	if not _due(ve.id, 0, DUST_INTERVAL):
		return
	if r.v.terrain != null and r.v.terrain.is_water_at(ve.wx, ve.wz):
		return
	var p: Vector3 = Vector3(ve.wx, ve.wy, ve.wz) - _forward(ve) * ve.radius_m * 0.8
	stat_spawned += 1
	r.spawn(&"vehicle_dust", p, Vector3.ZERO, clampf(ve.radius_m / 1.9, 0.5, 1.6) * (0.6 + 0.4 * ve.move01))


func _wake(r: FxEventRouter, ve: ViewEntity) -> void:
	if not _due(ve.id, 1, WAKE_INTERVAL):
		return
	var f: Vector3 = _forward(ve)
	var p: Vector3 = Vector3(ve.wx, r.v.sea_level() if r.v.sea_level() > -900.0 else ve.wy, ve.wz) - f * ve.radius_m * 0.2
	stat_spawned += 1
	r.spawn(&"wake_foam", p, p + f, clampf(ve.radius_m / 3.0, 0.6, 2.4))


func _contrail(r: FxEventRouter, ve: ViewEntity) -> void:
	if not _due(ve.id, 2, TRAIL_INTERVAL):
		return
	if ve.wy - r.v.ground_at(ve.wx, ve.wz) < 9.0:
		return
	var p: Vector3 = Vector3(ve.wx, ve.wy, ve.wz) - _forward(ve) * ve.radius_m * 1.1
	stat_spawned += 1
	r.spawn(&"aircraft_contrail", p, Vector3.ZERO, clampf(ve.radius_m / 3.0, 0.5, 1.5))


func _rotor(r: FxEventRouter, ve: ViewEntity) -> void:
	var g: float = r.v.ground_at(ve.wx, ve.wz)
	if ve.wy - g > 9.0 or not _due(ve.id, 3, 0.5):
		return
	stat_spawned += 1
	r.spawn(&"rotor_wash", Vector3(ve.wx, g + 0.2, ve.wz), Vector3.ZERO, clampf(ve.radius_m / 3.0, 0.6, 1.6))
