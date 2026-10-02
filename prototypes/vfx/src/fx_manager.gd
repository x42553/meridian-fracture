class_name FxManager
extends Node3D
## Pooled, budgeted, presentation-only VFX runtime.
##
## Usage: add as a child of the view root at the world origin (identity transform), call setup(camera), then
## spawn(effect_id, a, b, scale) from the event router. Effects never touch simulation state.
##
## Architecture (see REPORT.md):
##  - Short-lived effects are ring-buffer instances of MultiMesh "batches" animated in shaders from the global
##    fx_time clock (FxBatch): no per-frame CPU work, one draw call per active kind, hard cap = ring size.
##  - Lights and scorch decals are small node pools (they must be nodes), updated only while they animate.
##  - Recipes (FxRecipes) compose primitives; delayed sub-effects go through schedule(); looping sources
##    (burning wreck, welding, beam impact) and moving stampers (dust, contrail) are emitters.
##  - Every spawn is budgeted: token bucket per class, distance + screen-size + frustum culling.

signal camera_shake(amount: float, world_pos: Vector3)

enum Quality { LOW, MEDIUM, HIGH, ULTRA }
enum Kind { POINT, LINE, AREA }
enum Cls { TINY, SMALL, MEDIUM, LARGE, BEAM, SUPER }

const CLS_MAX_DIST: PackedFloat32Array = [70.0, 110.0, 200.0, 350.0, 200.0, 2000.0]
const CLS_MIN_PX: PackedFloat32Array = [2.5, 4.0, 6.0, 8.0, 3.0, 0.0]
const CLS_RATE: PackedFloat32Array = [500.0, 200.0, 60.0, 30.0, 30.0, 10.0]
const CLS_BURST: PackedFloat32Array = [60.0, 40.0, 20.0, 10.0, 8.0, 4.0]
const MAX_LIGHTS: int = 6
const MAX_DECALS: int = 48
const SHAKE_RANGE: float = 140.0

class FxDef extends RefCounted:
	var id: StringName
	var cls: int
	var kind: int
	var radius: float
	var nominal_scale: float
	var recipe: Callable

class Sched extends RefCounted:
	var t: float
	var id: StringName
	var a: Vector3
	var b: Vector3
	var s: float

class Emitter extends RefCounted:
	var handle: int
	var id: StringName
	var node: Node3D
	var pos_a: Vector3
	var pos_b: Vector3
	var last_pos: Vector3
	var scale: float
	var interval: float
	var spacing: float
	var next: float
	var end: float
	var stamp: bool

var quality: Quality = Quality.HIGH
var paused: bool = false
var time_scale: float = 1.0
## Bypass budgets/culling (pre-warm, contact sheets).
var force: bool = false
## Debug: batch names whose emits are dropped (used to bisect which layer causes an artifact).
var hidden_batches: Dictionary = {}

var stat_requests: int = 0
var stat_spawned: int = 0
var stat_culled: int = 0
var stat_rate_dropped: int = 0
var stat_spawn_us: int = 0
var stat_process_us: int = 0
var stat_process_frames: int = 0

var _cam: Camera3D
var _clock: float = 0.0
var _cam_pos: Vector3 = Vector3.ZERO
var _vp: Vector2 = Vector2(1280.0, 720.0)
var _px_per_rad: float = 800.0
var _lod: float = 1.0
var _dist_mult: float = 1.0
var _use_lights: bool = true
var _use_decals: bool = true
var _use_distort: bool = true
var _light_limit: int = MAX_LIGHTS

var _batches: Dictionary = {}
var _batch_list: Array[FxBatch] = []
var _defs: Dictionary = {}
var _tokens: PackedFloat32Array = PackedFloat32Array([60.0, 40.0, 20.0, 10.0, 8.0, 4.0])
var _sched: Array[Sched] = []
var _emitters: Array[Emitter] = []
var _next_handle: int = 1
var _recording: bool = false
var _rec: PackedInt32Array = PackedInt32Array()
var _groups: Dictionary = {}

var _lights: Array[OmniLight3D] = []
var _light_t0: PackedFloat64Array = PackedFloat64Array()
var _light_dur: PackedFloat32Array = PackedFloat32Array()
var _light_e0: PackedFloat32Array = PackedFloat32Array()
var _light_cursor: int = 0
var _decals: Array[Decal] = []
var _decal_t0: PackedFloat64Array = PackedFloat64Array()
var _decal_life: PackedFloat32Array = PackedFloat32Array()
var _decal_hot: PackedFloat32Array = PackedFloat32Array()
var _decal_stage: PackedInt32Array = PackedInt32Array()
var _decal_cursor: int = 0


## Builds all pools and registers all recipes. Call once, after adding to the tree.
func setup(camera: Camera3D, q: Quality = Quality.HIGH) -> void:
	_cam = camera
	_ensure_globals()
	_build_batches()
	_build_pools()
	_register_recipes()
	set_quality(q)


func now() -> float:
	return _clock


## Applies a quality preset: sprite thinning (fx_lod), culling distance, lights, decals, refraction.
func set_quality(q: Quality) -> void:
	quality = q
	match q:
		Quality.LOW:
			_lod = 0.45
			_dist_mult = 0.6
			_use_lights = false
			_use_decals = false
			_use_distort = false
			_light_limit = 0
		Quality.MEDIUM:
			_lod = 0.7
			_dist_mult = 0.8
			_use_lights = true
			_use_decals = true
			_use_distort = false
			_light_limit = 3
		Quality.HIGH:
			_lod = 1.0
			_dist_mult = 1.0
			_use_lights = true
			_use_decals = true
			_use_distort = true
			_light_limit = MAX_LIGHTS
		Quality.ULTRA:
			_lod = 1.0
			_dist_mult = 1.4
			_use_lights = true
			_use_decals = true
			_use_distort = true
			_light_limit = MAX_LIGHTS
	RenderingServer.global_shader_parameter_set(&"fx_lod", _lod)


## Spawns effect `id`. `a` = origin (muzzle / impact / centre), `b` = destination for LINE effects (for AREA
## effects b.x may carry a duration in seconds), `scale` = effect-specific size (see the recipe table).
## Returns a handle (>0) usable with cancel(), or -1 when culled / rate-limited / unknown.
func spawn(id: StringName, a: Vector3, b: Vector3 = Vector3.ZERO, scale: float = 1.0) -> int:
	var t0: int = Time.get_ticks_usec()
	var def: FxDef = _defs.get(id)
	if def == null:
		push_error("FxManager: unknown effect '%s'" % id)
		return -1
	stat_requests += 1
	if not force and not _accept(def, a, b, scale):
		return -1
	_rec.clear()
	_recording = true
	def.recipe.call(self, a, b, scale)
	_recording = false
	var h: int = _next_handle
	_next_handle += 1
	if def.cls == Cls.SUPER:
		_groups[h] = _rec.duplicate()
	stat_spawned += 1
	stat_spawn_us += Time.get_ticks_usec() - t0
	return h


## Cancels a still-running SUPER-class effect (e.g. warning marker after the launcher was destroyed).
func cancel(handle: int) -> void:
	var g: PackedInt32Array = _groups.get(handle, PackedInt32Array())
	for i in range(0, g.size(), 2):
		_batch_list[g[i]].kill(g[i + 1])
	_groups.erase(handle)


## Runs `id` at fixed intervals for `duration` seconds (burning wreck, welding, beam impact).
func start_loop(id: StringName, a: Vector3, b: Vector3, scale: float, interval: float, duration: float) -> int:
	var e := Emitter.new()
	e.handle = _next_handle
	_next_handle += 1
	e.id = id
	e.pos_a = a
	e.pos_b = b
	e.scale = scale
	e.interval = interval
	e.next = _clock
	e.end = _clock + duration
	_emitters.append(e)
	return e.handle


## Stamps `id` every `spacing` metres travelled by `node` (vehicle dust, aircraft contrail).
func start_stamper(id: StringName, node: Node3D, spacing: float, duration: float, scale: float = 1.0) -> int:
	var e := Emitter.new()
	e.handle = _next_handle
	_next_handle += 1
	e.id = id
	e.node = node
	e.last_pos = node.global_position
	e.scale = scale
	e.spacing = spacing
	e.end = _clock + duration
	e.stamp = true
	_emitters.append(e)
	return e.handle


func stop_emitter(handle: int) -> void:
	for e in _emitters:
		if e.handle == handle:
			e.end = -1.0


## Queues a (re-culled) spawn `delay` seconds from now.
func schedule(delay: float, id: StringName, a: Vector3, b: Vector3, s: float) -> void:
	var e := Sched.new()
	e.t = _clock + delay
	e.id = id
	e.a = a
	e.b = b
	e.s = s
	_sched.append(e)


## Spawns every registered effect once in front of the camera so pipelines/shaders compile during loading.
## Call clear_all() a few frames later.
func prewarm() -> void:
	var fwd: Vector3 = -_cam.global_transform.basis.z
	var p: Vector3 = _cam.global_position + fwd * 22.0
	p.y = 0.0
	var was: bool = force
	force = true
	for id in _defs:
		var def: FxDef = _defs[id]
		spawn(id, p, p + Vector3(8.0, 0.0, -4.0), def.nominal_scale)
	force = was


func clear_all() -> void:
	for b in _batch_list:
		b.clear()
	for i in _lights.size():
		_lights[i].visible = false
		_light_dur[i] = 0.0
	for i in _decals.size():
		_decals[i].visible = false
		_decal_life[i] = 0.0
	_sched.clear()
	_emitters.clear()
	_groups.clear()


func get_stats() -> Dictionary:
	var per_batch: Dictionary = {}
	var shown: int = 0
	for b in _batch_list:
		per_batch[String(b.name)] = [b.spawned, b.overwritten]
		if b.node.visible:
			shown += 1
	var lights: int = 0
	for i in _lights.size():
		if _light_dur[i] > 0.0:
			lights += 1
	var decals: int = 0
	for i in _decals.size():
		if _decal_life[i] > 0.0:
			decals += 1
	return {
		"process_us_avg": float(stat_process_us) / maxf(float(stat_process_frames), 1.0), "requests": stat_requests, "spawned": stat_spawned, "culled": stat_culled,
		"rate_dropped": stat_rate_dropped, "spawn_us_avg": float(stat_spawn_us) / maxf(float(stat_spawned), 1.0),
		"batches_shown": shown, "lights": lights, "decals": decals, "sched": _sched.size(),
		"emitters": _emitters.size(), "per_batch": per_batch,
	}


func reset_stats() -> void:
	stat_requests = 0
	stat_spawned = 0
	stat_culled = 0
	stat_rate_dropped = 0
	stat_spawn_us = 0
	stat_process_us = 0
	stat_process_frames = 0
	for b in _batch_list:
		b.spawned = 0
		b.overwritten = 0

# ------------------------------------------------------------------ primitives used by recipes

## Cluster / billboard sprite effect. `scale_m` = radius in metres for clusters, diameter for flash/glow/puff.
func sprites(batch: StringName, pos: Vector3, scale_m: float, life: float, param: float = 1.0, palette: int = 0) -> void:
	var xf := Transform3D(Basis.from_scale(Vector3(scale_m, scale_m, scale_m)), pos)
	_emit(_batches[batch], xf, life, float(palette) + randf() * 0.99, param)


func puff(batch: StringName, pos: Vector3, size_m: float, life: float, alpha: float = 1.0) -> void:
	sprites(batch, pos, size_m, life, alpha, 0)


func ribbon(batch: StringName, from: Vector3, to: Vector3, life: float, width: float, tail: float,
		flight: float, linger: float, arc: Vector3, palette: int) -> void:
	var xf := Transform3D(Basis(arc, to - from, Vector3(tail, maxf(flight, 0.001), maxf(linger, 0.001))), from)
	_emit(_batches[batch], xf, life, float(palette) + randf() * 0.99, width)


func tracer(from: Vector3, to: Vector3, speed: float, tail: float, width: float, palette: int, arc: Vector3 = Vector3.ZERO) -> void:
	var flight: float = from.distance_to(to) / speed
	ribbon(&"tracer", from, to, flight + tail / speed, width, tail, flight, 0.0, arc, palette)


func trail(from: Vector3, to: Vector3, flight: float, linger: float, width: float, arc: Vector3 = Vector3.ZERO, batch: StringName = &"trail") -> void:
	ribbon(batch, from, to, flight + linger, width, 0.0, flight, linger, arc, 0)


func cone(from: Vector3, dir: Vector3, length: float, width: float, life: float) -> void:
	ribbon(&"cone", from, from + dir * length, life, width, 0.0, life, 0.0, Vector3.ZERO, 0)


func beam(from: Vector3, to: Vector3, life: float, width: float) -> void:
	ribbon(&"beam", from, to, life, width, 0.0, life, 0.0, Vector3.ZERO, 0)


func rail(from: Vector3, to: Vector3, life: float, width: float) -> void:
	ribbon(&"rail", from, to, life, width, 0.0, life, 0.0, Vector3.ZERO, 4)


func bolt(from: Vector3, to: Vector3, life: float, width: float, arc_h: float) -> void:
	ribbon(&"arc", from, to, life, width, 0.0, life, 0.0, Vector3(0.0, arc_h, 0.0), 7)


func shimmer(from: Vector3, to: Vector3, life: float, width: float) -> void:
	if _use_distort:
		ribbon(&"shimmer", from, to, life, width, 0.0, life, 0.0, Vector3.ZERO, 0)


func ring(batch: StringName, pos: Vector3, radius: float, life: float, palette: int = 0) -> void:
	if (batch == &"ring_distort" or batch == &"haze") and not _use_distort:
		return
	var xf := Transform3D(Basis.from_scale(Vector3(radius, 1.0, radius)), pos)
	_emit(_batches[batch], xf, life, float(palette) + randf() * 0.99, 1.0)


func dome(pos: Vector3, radius: float, life: float) -> void:
	var xf := Transform3D(Basis.from_scale(Vector3(radius, radius, radius)), pos)
	_emit(_batches[&"dome"], xf, life, randf() * 0.99, 1.0)


func column(batch: StringName, pos: Vector3, radius: float, height: float, life: float) -> void:
	var xf := Transform3D(Basis.from_scale(Vector3(radius, height, radius)), pos)
	_emit(_batches[batch], xf, life, randf() * 0.99, 1.0)


func light_flash(pos: Vector3, color: Color, energy: float, range_m: float, dur: float) -> void:
	if not _use_lights or _light_limit <= 0:
		return
	var i: int = _light_cursor % _light_limit
	_light_cursor += 1
	var l: OmniLight3D = _lights[i]
	l.global_position = pos
	l.light_color = color
	l.omni_range = range_m
	l.light_energy = energy
	l.visible = true
	_light_t0[i] = _clock
	_light_dur[i] = dur
	_light_e0[i] = energy


## Persistent ground scorch (Decal). `hot` > 0 adds an emissive glow that cools over ~2 s.
func scorch(pos: Vector3, radius: float, life: float, hot: float) -> void:
	if not _use_decals:
		return
	var i: int = _decal_cursor
	_decal_cursor = (i + 1) % MAX_DECALS
	var d: Decal = _decals[i]
	d.global_position = pos + Vector3(0.0, 0.6, 0.0)
	d.size = Vector3(radius * 2.0, 2.0, radius * 2.0)
	d.rotation = Vector3(0.0, randf() * TAU, 0.0)
	d.modulate = Color.WHITE
	d.emission_energy = hot * 3.0
	d.visible = true
	_decal_t0[i] = _clock
	_decal_life[i] = life
	_decal_hot[i] = hot
	_decal_stage[i] = 0 if hot > 0.0 else 1


## Emits the camera-shake hook (attenuated by distance to the camera).
func shake(amount: float, pos: Vector3) -> void:
	if amount <= 0.0:
		return
	var k: float = 1.0
	if _cam != null:
		k = clampf(1.0 - _cam_pos.distance_to(pos) / SHAKE_RANGE, 0.0, 1.0)
	if k > 0.0:
		camera_shake.emit(amount * k, pos)

# ------------------------------------------------------------------ internals

func _ensure_globals() -> void:
	# Production: declare both in project.godot [shader_globals] (RenderingServer.global_shader_parameter_get_list
	# is editor-only and errors at runtime). Runtime add is only a fallback for projects that forgot to.
	if not ProjectSettings.has_setting("shader_globals/fx_time"):
		RenderingServer.global_shader_parameter_add(&"fx_time", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	if not ProjectSettings.has_setting("shader_globals/fx_lod"):
		RenderingServer.global_shader_parameter_add(&"fx_lod", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)


func _add(id: StringName, mesh: Mesh, mat: Material, cap: int) -> void:
	var b := FxBatch.new(id, mesh, mat, cap, self)
	b.index = _batch_list.size()
	_batches[id] = b
	_batch_list.append(b)


func _build_batches() -> void:
	var c1: ArrayMesh = FxAssets.cluster_mesh(1, 66)
	var c9: ArrayMesh = FxAssets.cluster_mesh(9, 55)
	var c10: ArrayMesh = FxAssets.cluster_mesh(10, 22)
	var c12: ArrayMesh = FxAssets.cluster_mesh(12, 33)
	var c14: ArrayMesh = FxAssets.cluster_mesh(14, 11)
	var c16: ArrayMesh = FxAssets.cluster_mesh(16, 77)
	var c20: ArrayMesh = FxAssets.cluster_mesh(20, 44)
	var rib: ArrayMesh = FxAssets.ribbon_mesh(24)
	var flat: ArrayMesh = FxAssets.flat_quad_mesh()
	var dust: Color = Color(0.72, 0.64, 0.52, 0.85)
	var W: Color = Color.WHITE
	_add(&"gglow", c1, FxAssets.sprite_material(10, W, -4, 0.0), 96)
	_add(&"smoke", c10, FxAssets.sprite_material(1, W, -3), 128)
	_add(&"dustring", c12, FxAssets.sprite_material(4, dust, -2), 64)
	_add(&"dustcol", c9, FxAssets.sprite_material(5, Color(0.66, 0.58, 0.47, 0.95), -2), 48)
	_add(&"puff_dust", c1, FxAssets.sprite_material(6, dust, -2, 0.8, 1.0, false, 0.0, 0.85, 0.5), 768)
	_add(&"puff_smoke", c1, FxAssets.sprite_material(6, Color(0.36, 0.34, 0.32, 1.0), -2, 0.8, 1.0, false, 0.0, 0.85, 2.4), 384)
	_add(&"puff_white", c1, FxAssets.sprite_material(6, Color(0.93, 0.94, 0.96, 0.85), -1, 0.8, 1.0, false, 0.0, 0.85, 0.15), 1024)
	_add(&"fire", c14, FxAssets.sprite_material(0, W, 0), 128)
	_add(&"debris", c12, FxAssets.sprite_material(2, W, 1, 0.0), 128)
	_add(&"rubble", c20, FxAssets.sprite_material(2, W, 1, 0.0, 1.0, false, 1.3, 0.94), 48)
	_add(&"sparks", c20, FxAssets.sprite_material(3, W, 2, 0.0), 192)
	_add(&"splash", c16, FxAssets.sprite_material(7, W, 1, 0.0), 48)
	_add(&"flash", c1, FxAssets.sprite_material(8, W, 3, 0.0), 256)
	_add(&"glow", c1, FxAssets.sprite_material(9, W, 3, 0.0), 192)
	_add(&"trail", rib, FxAssets.ribbon_material(1, -1, Color(1.0, 1.0, 1.0, 0.9)), 96)
	_add(&"trail_dark", rib, FxAssets.ribbon_material(1, -1, Color(0.22, 0.22, 0.24, 1.0)), 32)
	_add(&"contrail", rib, FxAssets.ribbon_material(6, -1, Color(1.0, 1.0, 1.0, 0.55)), 32)
	_add(&"firetrail", rib, FxAssets.ribbon_material(7, 1), 32)
	_add(&"tracer", rib, FxAssets.ribbon_material(0, 2), 512)
	_add(&"beam", rib, FxAssets.ribbon_material(2, 2), 32)
	_add(&"rail", rib, FxAssets.ribbon_material(3, 2), 32)
	_add(&"arc", rib, FxAssets.ribbon_material(4, 2), 128)
	_add(&"cone", rib, FxAssets.ribbon_material(5, 2), 256)
	_add(&"shimmer", rib, FxAssets.shimmer_material(-10, 2.2), 16)
	_add(&"ring_add", flat, FxAssets.ring_material(0, false, 2), 32)
	_add(&"ring_distort", flat, FxAssets.ring_material(0, true, -9), 16)
	_add(&"ring_emp", flat, FxAssets.ring_material(1, false, 2), 16)
	_add(&"marker", flat, FxAssets.ring_material(2, false, 2), 16)
	_add(&"ripple", flat, FxAssets.ring_material(3, false, 0), 32)
	_add(&"haze", flat, FxAssets.ring_material(4, true, -9), 16)
	_add(&"dome", FxAssets.dome_mesh(), FxAssets.dome_material(0), 8)
	_add(&"beacon", FxAssets.column_mesh(), FxAssets.column_material(0), 16)
	_add(&"strike", FxAssets.column_mesh(), FxAssets.column_material(1), 16)


func _build_pools() -> void:
	for i in MAX_LIGHTS:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
	_light_t0.resize(MAX_LIGHTS)
	_light_dur.resize(MAX_LIGHTS)
	_light_e0.resize(MAX_LIGHTS)
	for i in MAX_DECALS:
		var d := Decal.new()
		d.texture_albedo = FxAssets.scorch_texture()
		d.texture_emission = FxAssets.scorch_glow_texture()
		d.emission_energy = 0.0
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.distance_fade_enabled = true
		d.distance_fade_begin = 110.0
		d.distance_fade_length = 40.0
		d.visible = false
		add_child(d)
		_decals.append(d)
	_decal_t0.resize(MAX_DECALS)
	_decal_life.resize(MAX_DECALS)
	_decal_hot.resize(MAX_DECALS)
	_decal_stage.resize(MAX_DECALS)


func _reg(id: StringName, cls: int, kind: int, radius: float, nominal_scale: float, recipe: Callable) -> void:
	var d := FxDef.new()
	d.id = id
	d.cls = cls
	d.kind = kind
	d.radius = radius
	d.nominal_scale = nominal_scale
	d.recipe = recipe
	_defs[id] = d


func _register_recipes() -> void:
	_reg(&"rifle_shot", Cls.SMALL, Kind.LINE, 1.5, 1.0, FxRecipes.rifle_shot)
	_reg(&"mg_burst", Cls.SMALL, Kind.LINE, 1.5, 1.0, FxRecipes.mg_burst)
	_reg(&"cannon_shot", Cls.MEDIUM, Kind.LINE, 3.0, 1.0, FxRecipes.cannon_shot)
	_reg(&"cannon_impact", Cls.MEDIUM, Kind.POINT, 3.0, 1.0, FxRecipes.cannon_impact)
	_reg(&"explosion_small", Cls.MEDIUM, Kind.POINT, 4.0, 1.0, FxRecipes.explosion_small)
	_reg(&"explosion_medium", Cls.MEDIUM, Kind.POINT, 8.0, 1.0, FxRecipes.explosion_medium)
	_reg(&"explosion_large", Cls.LARGE, Kind.POINT, 20.0, 1.0, FxRecipes.explosion_large)
	_reg(&"missile_launch", Cls.MEDIUM, Kind.LINE, 3.0, 1.0, FxRecipes.missile_launch)
	_reg(&"artillery_shell", Cls.LARGE, Kind.LINE, 4.0, 1.0, FxRecipes.artillery_shell)
	_reg(&"beam_thermal", Cls.BEAM, Kind.LINE, 4.0, 1.0, FxRecipes.beam_thermal)
	_reg(&"beam_tick", Cls.BEAM, Kind.LINE, 4.0, 1.0, FxRecipes.beam_tick)
	_reg(&"beam_rail", Cls.BEAM, Kind.LINE, 3.0, 1.0, FxRecipes.beam_rail)
	_reg(&"rail_impact", Cls.BEAM, Kind.POINT, 4.0, 1.0, FxRecipes.rail_impact)
	_reg(&"emp_pulse", Cls.LARGE, Kind.AREA, 1.0, 10.0, FxRecipes.emp_pulse)
	_reg(&"emp_arc", Cls.TINY, Kind.LINE, 1.0, 1.0, FxRecipes.emp_arc)
	_reg(&"vehicle_destroy", Cls.LARGE, Kind.POINT, 8.0, 1.0, FxRecipes.vehicle_destroy)
	_reg(&"wreck_tick", Cls.TINY, Kind.POINT, 2.0, 1.0, FxRecipes.wreck_tick)
	_reg(&"wreck_start", Cls.TINY, Kind.POINT, 2.0, 1.0, FxRecipes.wreck_start)
	_reg(&"building_collapse", Cls.LARGE, Kind.POINT, 20.0, 1.0, FxRecipes.building_collapse)
	_reg(&"collapse_burst", Cls.LARGE, Kind.POINT, 12.0, 1.0, FxRecipes.collapse_burst)
	_reg(&"infantry_hit", Cls.TINY, Kind.POINT, 1.2, 1.0, FxRecipes.infantry_hit)
	_reg(&"contrail_puff", Cls.MEDIUM, Kind.POINT, 3.0, 1.0, FxRecipes.contrail_puff)
	_reg(&"aircraft_contrail", Cls.MEDIUM, Kind.POINT, 3.0, 1.0, FxRecipes.contrail_puff)
	_reg(&"aircraft_crash", Cls.LARGE, Kind.LINE, 6.0, 1.0, FxRecipes.aircraft_crash)
	_reg(&"impact_ground", Cls.TINY, Kind.POINT, 1.2, 1.0, FxRecipes.impact_ground)
	_reg(&"impact_water", Cls.SMALL, Kind.POINT, 3.0, 1.0, FxRecipes.impact_water)
	_reg(&"vehicle_dust", Cls.SMALL, Kind.POINT, 2.5, 1.0, FxRecipes.vehicle_dust)
	_reg(&"construction_sparks", Cls.SMALL, Kind.POINT, 1.5, 1.0, FxRecipes.construction_sparks)
	_reg(&"weld_tick", Cls.TINY, Kind.POINT, 1.2, 1.0, FxRecipes.weld_tick)
	_reg(&"sw_warning_marker", Cls.SUPER, Kind.AREA, 1.0, 12.0, FxRecipes.sw_warning_marker)
	_reg(&"sw_orbital_strike", Cls.SUPER, Kind.AREA, 18.0, 1.0, FxRecipes.sw_orbital_strike)
	_reg(&"strike_one", Cls.SUPER, Kind.POINT, 8.0, 1.0, FxRecipes.strike_one)
	_reg(&"sw_shockwave", Cls.SUPER, Kind.AREA, 26.0, 1.0, FxRecipes.sw_shockwave)
	_reg(&"sw_microwave_dome", Cls.SUPER, Kind.AREA, 26.0, 1.0, FxRecipes.sw_microwave_dome)


func _emit(b: FxBatch, xf: Transform3D, life: float, seed_v: float, param: float) -> void:
	if not hidden_batches.is_empty() and hidden_batches.has(b.name):
		return
	var slot: int = b.emit(xf, _clock, life, seed_v, param)
	if _recording:
		_rec.append(b.index)
		_rec.append(slot)


func _accept(def: FxDef, a: Vector3, b: Vector3, scale: float) -> bool:
	var c: int = def.cls
	if _tokens[c] < 1.0:
		stat_rate_dropped += 1
		return false
	if _cam != null:
		var r: float = def.radius * scale
		var ok: bool = _in_view(a, r, c)
		if not ok and def.kind == Kind.LINE:
			ok = _in_view(b, r, c)
		if not ok:
			stat_culled += 1
			return false
	_tokens[c] -= 1.0
	return true


func _in_view(p: Vector3, r: float, c: int) -> bool:
	var d: float = _cam_pos.distance_to(p)
	if c != Cls.SUPER and d > CLS_MAX_DIST[c] * _dist_mult:
		return false
	var px: float = r * _px_per_rad / maxf(d, 0.5)
	if px < CLS_MIN_PX[c]:
		return false
	if _cam.is_position_behind(p):
		return d < r
	var sp: Vector2 = _cam.unproject_position(p)
	return sp.x > -px and sp.y > -px and sp.x < _vp.x + px and sp.y < _vp.y + px


func _process(delta: float) -> void:
	var t_begin: int = Time.get_ticks_usec()
	if not paused:
		_clock += delta * time_scale
	RenderingServer.global_shader_parameter_set(&"fx_time", _clock)
	for c in CLS_RATE.size():
		_tokens[c] = minf(CLS_BURST[c], _tokens[c] + CLS_RATE[c] * delta)
	if _cam != null:
		_cam_pos = _cam.global_position
		_vp = get_viewport().get_visible_rect().size
		_px_per_rad = _vp.y / (2.0 * tan(deg_to_rad(_cam.fov) * 0.5))
	_run_scheduled()
	_run_emitters()
	_update_lights()
	_update_decals()
	for b in _batch_list:
		b.sync_visibility(_clock)
	stat_process_us += Time.get_ticks_usec() - t_begin
	stat_process_frames += 1


func _run_scheduled() -> void:
	var i: int = _sched.size() - 1
	while i >= 0:
		var e: Sched = _sched[i]
		if _clock >= e.t:
			_sched.remove_at(i)
			spawn(e.id, e.a, e.b, e.s)
		i -= 1


func _run_emitters() -> void:
	var i: int = _emitters.size() - 1
	while i >= 0:
		var e: Emitter = _emitters[i]
		if _clock >= e.end or (e.stamp and not is_instance_valid(e.node)):
			_emitters.remove_at(i)
		elif e.stamp:
			var p: Vector3 = e.node.global_position
			var seg: Vector3 = p - e.last_pos
			var dist: float = seg.length()
			if dist >= e.spacing:
				var n: int = mini(int(dist / e.spacing), 8)
				var step: Vector3 = seg / float(maxi(int(dist / e.spacing), 1))
				for k in n:
					spawn(e.id, e.last_pos + step * float(k + 1), Vector3.ZERO, e.scale)
				e.last_pos = p
		else:
			var guard: int = 0
			while _clock >= e.next and guard < 4:
				spawn(e.id, e.pos_a, e.pos_b, e.scale)
				e.next += e.interval
				guard += 1
			if guard == 4:
				e.next = _clock + e.interval
		i -= 1


func _update_lights() -> void:
	for i in _lights.size():
		var dur: float = _light_dur[i]
		if dur <= 0.0:
			continue
		var t: float = (_clock - _light_t0[i]) / dur
		if t >= 1.0:
			_lights[i].visible = false
			_light_dur[i] = 0.0
		else:
			_lights[i].light_energy = _light_e0[i] * (1.0 - t) * (1.0 - t)


func _update_decals() -> void:
	for i in _decals.size():
		var life: float = _decal_life[i]
		if life <= 0.0:
			continue
		var t: float = _clock - _decal_t0[i]
		if t >= life:
			_decals[i].visible = false
			_decal_life[i] = 0.0
			continue
		var stage: int = _decal_stage[i]
		if stage == 0:
			if t < 2.0:
				var k: float = 1.0 - t / 2.0
				_decals[i].emission_energy = _decal_hot[i] * 3.0 * k * k
			else:
				_decals[i].emission_energy = 0.0
				_decal_stage[i] = 1
		elif stage == 1 and life - t < 4.0:
			_decal_stage[i] = 2
		if _decal_stage[i] == 2:
			_decals[i].modulate = Color(1.0, 1.0, 1.0, clampf((life - t) / 4.0, 0.0, 1.0))
