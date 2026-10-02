class_name ViewProjectiles
extends RefCounted
## Projectile mirror (render spec 5.9.2 "Projectile mirror", VIEW-W3): turns EV_PROJ_SPAWN / EV_PROJ_END / EV_IMPACT records into
## projectile visuals and mirrors the combat pool for the mesh kinds.
##
## Look per weapon archetype comes from `fx.json -> mappings.projectiles[family]`:
##   tracer  analytic ribbon effect `tr_*` (s = flight seconds)            arc   shell ribbon `arc_*` (parabola, s = flight)
##   mesh    pooled rig (proj.missile / rocket / torpedo / bomb) + smoke ribbon effect `trail_*` (line effect, s = flight)
##   none    nothing (hit-scan field weapons, breach charges)
## Mesh projectiles follow the combat pool exactly: once per sim tick the pool is read through `SimProjectiles.snapshot()`, the
## record with the same `serial` is updated (x, y, px, py, heading) and the rig is placed at lerp((px, py), (x, y), alpha), the
## same interpolation the entity mirror uses; a serial that is missing from the snapshot has ended and its rig is recycled.
## Arc-flying kinds (ARC / BOMB) add the vertical part analytically: height = lerp(start, ground) + 4 * apex * u * (1 - u) with
## u = (t - t_launch) / flight. The cap (`proj_mesh_cap`) recycles the oldest mesh; only its trail effect stays.
## Presentation only: never writes the sim.

const PK_BULLET: int = 1
const PK_MISSILE: int = 2
const PK_ARC: int = 3
const PK_BOMB: int = 4
const PK_STRIKE: int = 5
const PK_SWEEP: int = 6
const SNAP_STRIDE: int = 11  ## SimProjectiles.SNAP_STRIDE: serial, kind, pdef, x, y, px, py, heading, owner_pid, target, t_end
const TICK_S: float = 0.05
const HITSCAN_SPEED: float = 150.0  ## m/s of instant tracers
const LOOK_NONE: int = 0
const LOOK_TRACER: int = 1
const LOOK_ARC: int = 2
const LOOK_MESH: int = 3
const ARC_ARCHES: Array[int] = [9, 11, 21, 24, 10, 12, 25]  ## weapon archetypes that legitimately fly ARC (others with kind ARC are remote shells)


class Rec extends RefCounted:
	var serial: int = 0
	var kind: int = 0
	var arch: int = -1
	var remote: bool = false
	var t0_tick: int = 0
	var flight_ticks: int = 1
	var start: Vector3 = Vector3.ZERO
	var end: Vector3 = Vector3.ZERO
	var target_id: int = -1
	var rig: ViewModelRig = null
	var apex: float = 0.0
	var look: int = LOOK_NONE
	var px: int = 0  ## pool snapshot sim units (previous / current tick)
	var py: int = 0
	var cx: int = 0
	var cy: int = 0
	var seen_tick: int = -1
	var ended: bool = false
	var end_tick: int = 0
	var ground_end: float = 0.0
	var start_h: float = 0.0
	var owner_style: StringName = &"auto"
	var team_index: int = 0


var cap: int = 64  ## live mesh rigs (quality key proj_mesh_cap)
var stat_launched: int = 0
var stat_mesh: int = 0
var stat_recycled: int = 0
var stat_pool_reads: int = 0

var _v: ViewWorld = null
var _fx: FxManager = null
var _catalog: FxCatalog = null
var _map: Dictionary = {}  # weapon family -> mapping row
var _recs: Dictionary = {}  # serial -> Rec
var _mesh_order: Array[Rec] = []  # live mesh records, oldest first
var _free: Dictionary = {}  # model key -> Array[ViewModelRig]
var _root: Node3D = null
var _snap: PackedInt32Array = PackedInt32Array()
var _snap_tick: int = -1
var _models: Dictionary = {}  # style|recipe -> ViewModel


func setup(v: ViewWorld, fx: FxManager, catalog: FxCatalog) -> void:
	_v = v
	_fx = fx
	_catalog = catalog
	var book: FxRecipeBook = fx.recipe_book()
	var m: Variant = book.mappings.get("projectiles", {}) if book != null else {}
	_map = m as Dictionary if m is Dictionary else {}
	if v.quality != null:
		cap = maxi(v.quality.get_int(&"proj_mesh_cap"), 8)
	_root = Node3D.new()
	_root.name = "Projectiles"
	v.add_child(_root)


func teardown() -> void:
	for r: Variant in _recs.values():
		_drop_rig(r as Rec)
	_recs.clear()
	_mesh_order.clear()
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_free.clear()
	_models.clear()


func live_meshes() -> int:
	return _mesh_order.size()


func record_count() -> int:
	return _recs.size()


## Record of a still known projectile (impact handling reads the archetype and kind), null when unknown / already forgotten.
func record_of(serial: int) -> Rec:
	return _recs.get(serial) as Rec


func look_of(arch: int) -> int:
	var row: Dictionary = _row(arch)
	match str(row.get("look", "none")):
		"tracer", "rail":
			return LOOK_TRACER
		"arc":
			return LOOK_ARC
		"mesh":
			return LOOK_MESH
	return LOOK_NONE


## Mapping row of an archetype (`fx.json -> mappings.projectiles`), empty for none.
func _row(arch: int) -> Dictionary:
	if arch < 0 or arch >= FxCatalog.FAMILIES.size():
		return {}
	return _map.get(FxCatalog.FAMILIES[arch], {}) as Dictionary


# ---------------------------------------------------------------------------------------------- events
## EV_PROJ_SPAWN: x, y start . a serial . b pdef . c owner | kind << 4 | flight << 16 . d target . e, f end.
## `visible` = the router's fog gate for the launch or the end point.
func on_launch(events: PackedInt32Array, o: int, visible: bool) -> void:
	var serial: int = events[o + 4]
	var pdef: int = events[o + 5]
	var c: int = events[o + 6]
	var kind: int = (c >> 4) & 15
	var flight: int = maxi((c >> 16) & 0xFFFF, 1)
	stat_launched += 1
	if kind == PK_STRIKE or kind == PK_SWEEP:
		return  # strategic strikes are presented by the superweapon sequences
	var rec: Rec = Rec.new()
	rec.serial = serial
	rec.kind = kind
	rec.t0_tick = events[o + 1]
	rec.flight_ticks = flight
	rec.target_id = events[o + 7]
	rec.remote = _is_remote(kind, pdef)
	rec.arch = -1 if rec.remote else pdef
	var xs: int = events[o + 2]
	var ys: int = events[o + 3]
	var xe: int = events[o + 8]
	var ye: int = events[o + 9]
	rec.cx = xs
	rec.cy = ys
	rec.px = xs
	rec.py = ys
	rec.start = _start_pos(events[o + 4], xs, ys)
	rec.end = _end_pos(rec.target_id, xe, ye)
	rec.start_h = rec.start.y
	rec.ground_end = _v.ground_at(rec.end.x, rec.end.z)
	var flight_s: float = maxf(float(flight) * TICK_S, 0.05)
	if rec.remote:
		rec.look = LOOK_ARC if kind == PK_ARC else LOOK_MESH
	else:
		rec.look = look_of(rec.arch)
	_recs[serial] = rec
	if not visible or _fx == null:
		if rec.look != LOOK_MESH:
			_forget_later(rec)
		return
	match rec.look:
		LOOK_TRACER:
			_spawn_tracer(rec, flight_s)
		LOOK_ARC:
			_spawn_arc(rec, flight_s)
		LOOK_MESH:
			_spawn_mesh(rec, flight_s, events[o + 4], c & 15)
	if rec.look != LOOK_MESH:
		_forget_later(rec)


## EV_PROJ_END: x, y . a serial . b reason (0 expired, 1 APS, 2 zone, 3 instant fallback, 4 sweep done). Recycles the mesh.
func on_end(serial: int, tick: int) -> void:
	var rec: Rec = _recs.get(serial) as Rec
	if rec == null:
		return
	rec.ended = true
	rec.end_tick = tick
	_release_mesh(rec)


## EV_IMPACT of a projectile: the mesh disappears with the detonation.
func on_impact(serial: int, tick: int) -> void:
	on_end(serial, tick)


## Per rendered frame: mirrors the pool for the live mesh records and forgets old bookkeeping.
func frame(_dt: float) -> void:
	if _mesh_order.is_empty() and _recs.is_empty():
		return
	var sim: SimWorld = _v.sim
	if sim == null:
		return
	if sim.tick != _snap_tick:
		_snap_tick = sim.tick
		_read_pool(sim)
	var t: float = float(sim.tick - 1) + _v.alpha  # displayed sim time (the entity mirror shows tick - 1 + alpha)
	var i: int = _mesh_order.size() - 1
	while i >= 0:
		var rec: Rec = _mesh_order[i]
		if rec.ended or rec.rig == null:
			_mesh_order.remove_at(i)
			i -= 1
			continue
		_place(rec, t)
		i -= 1
	_prune(sim.tick)


# ---------------------------------------------------------------------------------------------- internals
static func _is_remote(kind: int, pdef: int) -> bool:
	if kind == PK_ARC:
		return not ARC_ARCHES.has(pdef)
	if kind == PK_BOMB:
		return pdef != 16 and pdef != 17
	return pdef < 0 or pdef >= FxCatalog.FAMILIES.size()


func _start_pos(shooter_id: int, xs: int, ys: int) -> Vector3:
	var p: Vector3 = _v.sim_to_world(xs, ys)
	var ve: ViewEntity = _v.entity_view(shooter_id)
	if ve != null:
		p.y = maxf(ve.wy + minf(ve.height_m * 0.7, 3.0), p.y + 0.6)
	else:
		p.y += 1.4
	return p


func _end_pos(target_id: int, xe: int, ye: int) -> Vector3:
	var p: Vector3 = _v.sim_to_world(xe, ye)
	var ve: ViewEntity = _v.entity_view(target_id) if target_id > 0 else null
	if ve != null:
		p.y = ve.wy + ve.height_m * 0.5
	else:
		p.y += 0.6
	return p


func _spawn_tracer(rec: Rec, flight_s: float) -> void:
	var row: Dictionary = _row(rec.arch)
	var id: StringName = StringName(str(row.get("fx", "")))
	if id == &"":
		return
	var pellets: int = int(row.get("pellets", 1))
	for k: int in pellets:
		var aim: Vector3 = rec.end
		if pellets > 1:
			aim += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (0.7 + 0.15 * float(k))
		_fx.spawn(id, rec.start, aim, flight_s)


func _spawn_arc(rec: Rec, flight_s: float) -> void:
	var id: StringName = &"arc_remote"
	if not rec.remote:
		id = StringName(str(_row(rec.arch).get("fx", "")))
	if id == &"":
		return
	var start: Vector3 = rec.start
	if rec.remote and start.distance_to(rec.end) > 100.0:
		start.y += 60.0  # power shells arrive from off-map
	_fx.spawn(id, start, rec.end, flight_s)


func _spawn_mesh(rec: Rec, flight_s: float, shooter_id: int, _owner_pid: int) -> void:
	var row: Dictionary = _row(rec.arch)
	var trail: StringName = StringName(str(row.get("trail", "trail_missile"))) if not rec.remote else &"trail_missile_high"
	rec.apex = float(row.get("apex", 0.0)) if not rec.remote else 0.3
	if trail != &"":
		_fx.spawn(trail, rec.start, rec.end, flight_s)
	var mesh_id: StringName = StringName(str(row.get("mesh", "proj.missile"))) if not rec.remote else &"proj.missile"
	if rec.kind == PK_BOMB:
		mesh_id = &"proj.bomb"
	var shooter: ViewEntity = _v.entity_view(shooter_id)
	if shooter != null:
		rec.owner_style = shooter.style_id
		rec.team_index = shooter.team_index
	# cap: recycle the oldest mesh; its trail effect keeps running
	while _mesh_order.size() >= cap:
		var old: Rec = _mesh_order.pop_front() as Rec
		_release_mesh(old)
		stat_recycled += 1
	var rig: ViewModelRig = _take_rig(mesh_id, rec.owner_style, rec.team_index)
	if rig == null:
		return
	rec.rig = rig
	rig.visible = false  # shown by the first _place
	_mesh_order.append(rec)
	stat_mesh += 1


func _take_rig(mesh_id: StringName, style: StringName, team_index: int) -> ViewModelRig:
	if _root == null or _v.models == null or _v.materials == null:
		return null
	var key: String = "%s|%s" % [mesh_id, style]
	var model: ViewModel = _models.get(key) as ViewModel
	if model == null:
		model = _v.models.get_model(mesh_id, style, 10000)
		_models[key] = model
	var pool: Array = _free.get(key, []) as Array
	var rig: ViewModelRig = null
	var plain: bool = _v.quality != null and _v.quality.renderer == ViewQuality.Renderer.COMPATIBILITY  # no instance uniforms there (GL buffer cap)
	var mat: ShaderMaterial = _v.materials.unit_material(style, ViewMaterials.Variant.MATERIAL_UNIFORMS if plain else ViewMaterials.Variant.NODE, team_index)
	if not pool.is_empty():
		rig = pool.pop_back() as ViewModelRig
		rig.material_override = mat
	else:
		rig = ViewModelRig.new().setup(model.mesh, mat)
		rig.set_meta(&"pool_key", key)
		rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(rig)
	return rig


func _release_mesh(rec: Rec) -> void:
	if rec.rig != null:
		_drop_rig(rec)
	var i: int = _mesh_order.find(rec)
	if i >= 0:
		_mesh_order.remove_at(i)


func _drop_rig(rec: Rec) -> void:
	var rig: ViewModelRig = rec.rig
	rec.rig = null
	if rig == null or not is_instance_valid(rig):
		return
	rig.visible = false
	var key: String = str(rig.get_meta(&"pool_key", ""))
	var pool: Array = _free.get(key, []) as Array
	if pool.size() < 32:
		pool.append(rig)
		_free[key] = pool
	else:
		rig.queue_free()


func _read_pool(sim: SimWorld) -> void:
	if _mesh_order.is_empty():
		return
	stat_pool_reads += 1
	var n: int = sim.combat.proj.snapshot(_snap)
	var tick: int = sim.tick
	for r: int in n:
		var b: int = r * SNAP_STRIDE
		var rec: Rec = _recs.get(_snap[b]) as Rec
		if rec == null or rec.rig == null:
			continue
		rec.seen_tick = tick
		rec.px = _snap[b + 5]
		rec.py = _snap[b + 6]
		rec.cx = _snap[b + 3]
		rec.cy = _snap[b + 4]
	# a mesh record the pool no longer holds has ended (impact / interception whose event was fogged or dropped)
	for k: int in range(_mesh_order.size() - 1, -1, -1):
		var m: Rec = _mesh_order[k]
		if m.seen_tick != tick and tick - m.t0_tick > 1:
			m.ended = true
			_release_mesh(m)


func _place(rec: Rec, t: float) -> void:
	var rig: ViewModelRig = rec.rig
	var a: float = _v.alpha
	var xs: float = lerpf(float(rec.px), float(rec.cx), a)
	var ys: float = lerpf(float(rec.py), float(rec.cy), a)
	var wx: float = xs * ViewConsts.M_PER_UNIT
	var wz: float = ys * ViewConsts.M_PER_UNIT
	var u: float = clampf((t - float(rec.t0_tick)) / float(maxi(rec.flight_ticks, 1)), 0.0, 1.0)
	var g: float = _v.ground_at(wx, wz)
	var y: float
	var fwd: Vector3 = rec.end - rec.start
	fwd.y = 0.0
	if rec.kind == PK_BOMB:
		y = lerpf(rec.start_h, rec.ground_end + 0.4, u * u)
	elif rec.kind == PK_ARC:
		var dist: float = fwd.length()
		y = lerpf(rec.start_h, rec.ground_end + 0.6, u) + 4.0 * rec.apex * dist * u * (1.0 - u)
	else:
		y = lerpf(rec.start_h, rec.end.y, u) + 4.0 * rec.apex * fwd.length() * u * (1.0 - u)
	y = maxf(y, g + 0.3)
	var pos: Vector3 = Vector3(wx, y, wz)
	var dir: Vector3
	if rec.kind == PK_BOMB:
		dir = Vector3(fwd.x * 0.12, -1.0, fwd.z * 0.12).normalized()
	else:
		var ahead: float = minf(u + 0.03, 1.0)
		var wx2: float = lerpf(rec.start.x, rec.end.x, ahead)
		var wz2: float = lerpf(rec.start.z, rec.end.z, ahead)
		var y2: float = lerpf(rec.start_h, rec.end.y, ahead) + 4.0 * rec.apex * fwd.length() * ahead * (1.0 - ahead)
		var y1: float = lerpf(rec.start_h, rec.end.y, u) + 4.0 * rec.apex * fwd.length() * u * (1.0 - u)
		dir = Vector3(wx2 - lerpf(rec.start.x, rec.end.x, u), y2 - y1, wz2 - lerpf(rec.start.z, rec.end.z, u))
		if dir.length_squared() < 0.0001:
			dir = fwd
		if rec.kind == PK_MISSILE:
			dir = Vector3(float(rec.cx - rec.px), 0.0, float(rec.cy - rec.py)) * ViewConsts.M_PER_UNIT
			dir.y = (rec.end.y - rec.start_h) / maxf(fwd.length(), 1.0) * dir.length()
			if dir.length_squared() < 0.0001:
				dir = fwd
		dir = dir.normalized() if dir.length_squared() > 0.000001 else Vector3.FORWARD
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	rig.transform = Transform3D(Basis.looking_at(dir, up), pos)
	rig.visible = true
	if rec.kind == PK_BOMB:
		rig.rotate_object_local(Vector3.FORWARD, t * 3.0)


func _forget_later(rec: Rec) -> void:
	rec.ended = true
	rec.end_tick = rec.t0_tick + rec.flight_ticks + 2


## Drops records whose flight is long over (kept for a few ticks so the impact event can still read the archetype).
func _prune(tick: int) -> void:
	if _recs.size() < 128 and (tick & 7) != 0:
		return
	var dead: Array = []
	for k: Variant in _recs:
		var rec: Rec = _recs[k] as Rec
		if rec.ended and tick > rec.end_tick + 6:
			dead.append(k)
		elif not rec.ended and tick > rec.t0_tick + rec.flight_ticks + 80:
			dead.append(k)
	for k: Variant in dead:
		var rec2: Rec = _recs[k] as Rec
		_release_mesh(rec2)
		_recs.erase(k)
