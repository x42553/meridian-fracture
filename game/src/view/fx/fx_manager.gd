class_name FxManager
extends Node3D
## Pooled, budgeted, presentation-only VFX runtime (render spec 3.6, 5.9). Never mutates simulation state.
##
## Architecture (spike docs/spikes/vfx.md):
##  - Short-lived effects are instances of MultiMesh ring-buffer "batches" (FxBatch) animated in shaders from the global
##    `fx_time` clock: no per-frame CPU work, one draw per ACTIVE batch, hard cap = ring size. No GPUParticles3D anywhere.
##  - Composite effects are data: FxRecipeBook interprets `fx.json` layers and calls the primitives below.
##  - Lights are a pool of 6 OmniLight3D; persistent ground marks are ViewScorchLayer paints (no Decal nodes).
##  - Long-lived sources are emitters: start_loop (fixed anchor), start_stamper (every N metres of a node's travel),
##    start_tracker (endpoints re-evaluated through Callables: continuous beams, Helios spot, repair tethers).
##  - Every spawn passes a per-class token bucket plus distance, projected-size and frustum culling (culling at spawn only).
##
## Usage: add as a child of the view root at the world origin (identity transform), call setup(), then spawn() from the
## event router. `advance(dt)` is the ONLY writer of `fx_time`; by default _process() calls it, tests and captures call
## set_process(false) and step explicitly.

signal camera_shake(amount: float, world_pos: Vector3)  ## ViewWorld connects this to ViewCamera.add_shake (falloff already applied)

enum Quality { LOW, MEDIUM, HIGH, ULTRA }
enum Kind { POINT, LINE, AREA }
enum Cls { TINY, SMALL, MEDIUM, LARGE, BEAM, SUPER }

const CLASS_NAMES: PackedStringArray = ["tiny", "small", "medium", "large", "beam", "super"]
const KIND_NAMES: PackedStringArray = ["point", "line", "area"]
## Defaults; fx.json `classes` overrides them (max_dist 0 = unlimited).
const CLS_MAX_DIST: PackedFloat32Array = [70.0, 110.0, 200.0, 350.0, 200.0, 0.0]
const CLS_MIN_PX: PackedFloat32Array = [2.5, 4.0, 6.0, 8.0, 3.0, 0.0]
const CLS_RATE: PackedFloat32Array = [500.0, 200.0, 60.0, 30.0, 90.0, 10.0]
const CLS_BURST: PackedFloat32Array = [60.0, 40.0, 20.0, 10.0, 24.0, 4.0]
const MAX_LIGHTS: int = 6
const MAX_TRACKERS: int = 24
const SHAKE_RANGE: float = 140.0
const SCORCH_FLUSH_S: float = 0.25

## Batch inventory (render spec 4.7): name -> [kind, capacity]. kind: sprite (cluster or billboard), ribbon, ring, dome, column.
## Capacities are HARD caps (ring sizes).
const BATCHES: Dictionary = {
	&"gglow": [&"sprite", 96], &"smoke": [&"sprite", 192], &"dustring": [&"sprite", 64], &"dustcol": [&"sprite", 96],
	&"puff_dust": [&"sprite", 768], &"puff_smoke": [&"sprite", 640], &"puff_white": [&"sprite", 1024], &"fire": [&"sprite", 128],
	&"debris": [&"sprite", 256], &"rubble": [&"sprite", 48], &"sparks": [&"sprite", 320], &"splash": [&"sprite", 48],
	&"flash": [&"sprite", 256], &"glow": [&"sprite", 192],
	&"trail": [&"ribbon", 96], &"trail_dark": [&"ribbon", 32], &"contrail": [&"ribbon", 32], &"firetrail": [&"ribbon", 32],
	&"tracer": [&"ribbon", 640], &"beam": [&"ribbon", 32], &"rail": [&"ribbon", 32], &"arc": [&"ribbon", 128],
	&"cone": [&"ribbon", 256], &"shimmer": [&"ribbon", 16],
	&"ring_add": [&"ring", 32], &"ring_distort": [&"ring", 32], &"ring_emp": [&"ring", 16], &"marker": [&"ring", 16],
	&"ripple": [&"ring", 32], &"haze": [&"ring", 16], &"wake": [&"ring", 128],
	&"dome": [&"dome", 8], &"beacon": [&"column", 16], &"strike": [&"column", 16],
}
## Batches that lie flat on the ground: their Y snaps to the terrain height (see _flat_y).
const FLAT_BATCHES: Array[StringName] = [&"gglow", &"ring_add", &"ring_distort", &"ring_emp", &"marker", &"haze", &"wake"]
const DISTORT_BATCHES: Array[StringName] = [&"ring_distort", &"haze", &"shimmer"]

enum EmitterKind { LOOP, STAMP, TRACK }


class Sched extends RefCounted:
	var t: float = 0.0
	var id: StringName = &""
	var a: Vector3 = Vector3.ZERO
	var b: Vector3 = Vector3.ZERO
	var s: float = 1.0
	var cb: Callable = Callable()  ## when valid: run this instead of spawning `id` (delayed recipe layers)
	var group: int = 0


class Emitter extends RefCounted:
	var handle: int = 0
	var kind: int = EmitterKind.LOOP
	var id: StringName = &""
	var node: Node3D = null
	var pos_a: Vector3 = Vector3.ZERO
	var pos_b: Vector3 = Vector3.ZERO
	var from_cb: Callable = Callable()
	var to_cb: Callable = Callable()
	var last_pos: Vector3 = Vector3.ZERO
	var scale: float = 1.0
	var interval: float = 0.1
	var spacing: float = 1.0
	var next: float = 0.0
	var end: float = 0.0
	var group: int = 0


var quality: Quality = Quality.HIGH
var paused: bool = false
var time_scale: float = 1.0
var force: bool = false  ## bypass budgets and culling (prewarm, contact sheets)
var hidden_batches: Dictionary = {}  ## debug: batch names whose emits are dropped (bisect which layer causes an artifact)
var camera_focus_dist: float = 60.0  ## metres camera -> focus (ViewWorld.frame); added to every class distance limit (FIX 1)
var viewport_size_override: Vector2 = Vector2.ZERO  ## tests / captures without a real viewport
var trace_emits: bool = false  ## tests: record every batch write in `emit_log` as [batch, Transform3D, t0, life, seed, param]
var emit_log: Array = []

var stat_requests: int = 0
var stat_spawned: int = 0
var stat_culled: int = 0
var stat_rate_dropped: int = 0
var stat_unknown: int = 0
var stat_spawn_us: int = 0
var stat_process_us: int = 0
var stat_process_frames: int = 0

var _cam: Camera3D = null
var _recipes: FxRecipeBook = null
var _ground: ViewTerrain = null
var _scorch: ViewScorchLayer = null
var _clock: float = 0.0
var _cam_pos: Vector3 = Vector3.ZERO
var _cam_inv: Transform3D = Transform3D.IDENTITY
var _cam_fwd: Vector3 = Vector3.FORWARD
var _cam_persp: bool = true
var _vp: Vector2 = Vector2(1920.0, 1080.0)
var _px_per_rad: float = 1568.0
var _lod: float = 1.0
var _dist_mult: float = 1.0
var _use_lights: bool = true
var _use_distort: bool = true
var _light_limit: int = MAX_LIGHTS

var _cls_max: PackedFloat32Array = CLS_MAX_DIST.duplicate()
var _cls_min_px: PackedFloat32Array = CLS_MIN_PX.duplicate()
var _cls_rate: PackedFloat32Array = CLS_RATE.duplicate()
var _cls_burst: PackedFloat32Array = CLS_BURST.duplicate()
var _tokens: PackedFloat32Array = CLS_BURST.duplicate()

var _batches: Dictionary = {}
var _batch_list: Array[FxBatch] = []
var _sched: Array[Sched] = []
var _emitters: Array[Emitter] = []
var _live_trackers: int = 0
var _next_handle: int = 1
var _group: int = 0  ## handle of the SUPER effect being spawned (0 = none): scheduled work and emitters are tagged with it
var _rec: PackedInt32Array = PackedInt32Array()  ## (batch index, slot) pairs recorded for the current SUPER effect
var _rec_t: PackedFloat32Array = PackedFloat32Array()
var _groups: Dictionary = {}  ## handle -> [PackedInt32Array, PackedFloat32Array]
var _tracker_emit: bool = false
var _warned: Dictionary = {}

var _lights: Array[OmniLight3D] = []
var _light_t0: PackedFloat64Array = PackedFloat64Array()
var _light_dur: PackedFloat32Array = PackedFloat32Array()
var _light_e0: PackedFloat32Array = PackedFloat32Array()
var _scorch_dirty: bool = false
var _scorch_next_flush: float = 0.0
var _built: bool = false
var _prewarming: bool = false  ## prewarm() spawns everything once: no permanent scorch marks


## Builds all batches and pools. Call once, after adding to the tree. `book` may be an empty book; `ground` and
## `scorch_layer` may be null (flat ground at the given Y, no persistent marks).
func setup(cam: Camera3D, q: Quality, book: FxRecipeBook, ground: ViewTerrain, scorch_layer: ViewScorchLayer) -> void:
	_cam = cam
	_recipes = book
	_ground = ground
	_scorch = scorch_layer
	ViewGlobals.ensure()
	if not _built:
		_build_batches()
		_build_lights()
		_built = true
	_apply_class_table()
	_refresh_camera()
	set_quality(q)


func now() -> float:
	return _clock


func recipe_book() -> FxRecipeBook:
	return _recipes


## Quality preset: sprite thinning (fx_lod), culling distance multiplier, lights and refraction. ViewQuality's
## `fx_distort` (renderer clamp) may override refraction afterwards through set_distort().
func set_quality(q: Quality) -> void:
	quality = q
	match q:
		Quality.LOW:
			_lod = 0.45
			_dist_mult = 0.6
			_use_distort = false
			_light_limit = 0
		Quality.MEDIUM:
			_lod = 0.7
			_dist_mult = 0.8
			_use_distort = false
			_light_limit = 3
		Quality.HIGH:
			_lod = 1.0
			_dist_mult = 1.0
			_use_distort = true
			_light_limit = MAX_LIGHTS
		Quality.ULTRA:
			_lod = 1.0
			_dist_mult = 1.4
			_use_distort = true
			_light_limit = MAX_LIGHTS
	_use_lights = _light_limit > 0
	for i: int in _lights.size():
		if i >= _light_limit:
			_lights[i].visible = false
			_light_dur[i] = 0.0
	RenderingServer.global_shader_parameter_set(&"fx_lod", _lod)


func set_distort(on: bool) -> void:
	_use_distort = on


func distort_enabled() -> bool:
	return _use_distort


func lod() -> float:
	return _lod


## Explicit stepping: the ONLY writer of the `fx_time` global. `dt` is real seconds; the FX clock advances by dt * time_scale
## unless `paused`. Also refills the class buckets, runs scheduled work, emitters, lights and the scorch flush.
func advance(dt: float) -> void:
	var t_begin: int = Time.get_ticks_usec()
	if not paused:
		var step: float = dt * time_scale
		_clock += step
		for c: int in _tokens.size():
			_tokens[c] = minf(_cls_burst[c], _tokens[c] + _cls_rate[c] * step)
	RenderingServer.global_shader_parameter_set(&"fx_time", _clock)
	_refresh_camera()
	if not paused:
		_run_scheduled()
		_run_emitters()
	_update_lights()
	if _scorch_dirty and _clock >= _scorch_next_flush:
		_flush_scorch()
	for b: FxBatch in _batch_list:
		b.sync_visibility(_clock)
	stat_process_us += Time.get_ticks_usec() - t_begin
	stat_process_frames += 1


func _process(delta: float) -> void:
	advance(delta)


## Re-reads the camera pose and viewport (advance() does it every frame; call it after moving the camera in tests).
func sync_camera() -> void:
	_refresh_camera()


## Spawns effect `id`. `a` = origin (muzzle / impact / centre), `b` = destination for LINE effects (for AREA effects b.x may
## carry a duration in seconds), `scale` = effect-specific size (see the recipe). Returns a handle (> 0) usable with cancel(),
## or -1 when culled / rate-limited / unknown.
func spawn(id: StringName, a: Vector3, b: Vector3 = Vector3.ZERO, scale_: float = 1.0) -> int:
	var t0: int = Time.get_ticks_usec()
	var d: FxRecipeBook.FxDef = _recipes.def(id) if _recipes != null else null
	if d == null:
		stat_unknown += 1
		_warn_once(id, "unknown effect '%s'" % id)
		return -1
	stat_requests += 1
	if not force and not _accept(d, a, b, scale_):
		return -1
	var h: int = _next_handle
	_next_handle += 1
	var own: bool = d.cls == Cls.SUPER and _group == 0
	var prev_rec: PackedInt32Array = _rec
	var prev_rec_t: PackedFloat32Array = _rec_t
	if own:
		_group = h
		_rec = PackedInt32Array()
		_rec_t = PackedFloat32Array()
	_recipes.run(d, self, a, b, scale_)
	if own:
		_groups[h] = [_rec, _rec_t]
		_group = 0
		_rec = prev_rec
		_rec_t = prev_rec_t
	stat_spawned += 1
	stat_spawn_us += Time.get_ticks_usec() - t0
	return h


## Cancels a still-running SUPER-class effect (a warning marker whose launcher was destroyed): kills its batch instances, its
## scheduled sub-effects and its emitters. Other handles are ignored (use stop_emitter for emitters).
func cancel(handle: int) -> void:
	if not _groups.has(handle):
		return
	var g: Array = _groups[handle]
	var slots: PackedInt32Array = g[0]
	var times: PackedFloat32Array = g[1]
	for i: int in times.size():
		_batch_list[slots[i * 2]].kill_if(slots[i * 2 + 1], times[i])
	_groups.erase(handle)
	var i: int = _sched.size() - 1
	while i >= 0:
		if _sched[i].group == handle:
			_sched.remove_at(i)
		i -= 1
	for e: Emitter in _emitters:
		if e.group == handle:
			e.end = -1.0


## Queues a (re-culled) spawn `delay` seconds from now.
func schedule(delay: float, id: StringName, a: Vector3, b: Vector3, s: float) -> void:
	var e: Sched = Sched.new()
	e.t = _clock + delay
	e.id = id
	e.a = a
	e.b = b
	e.s = s
	e.group = _group
	_sched.append(e)


## Queues a callable (delayed recipe layer); it belongs to the current SUPER group so cancel() drops it.
func schedule_call(delay: float, cb: Callable) -> void:
	var e: Sched = Sched.new()
	e.t = _clock + delay
	e.cb = cb
	e.group = _group
	_sched.append(e)


## Runs `id` at fixed intervals for `duration` seconds (burning wreck, welding, beam impact).
func start_loop(id: StringName, a: Vector3, b: Vector3, scale_: float, interval: float, duration: float, delay: float = 0.0) -> int:
	var e: Emitter = _new_emitter(EmitterKind.LOOP, id)
	e.pos_a = a
	e.pos_b = b
	e.scale = scale_
	e.interval = maxf(interval, 0.01)
	e.next = _clock + delay
	e.end = _clock + delay + duration
	return e.handle


## Stamps `id` every `spacing` metres travelled by `node` (vehicle dust, aircraft contrail); at most 8 stamps per frame.
func start_stamper(id: StringName, node: Node3D, spacing: float, duration: float, scale_: float = 1.0) -> int:
	var e: Emitter = _new_emitter(EmitterKind.STAMP, id)
	e.node = node
	e.last_pos = _node_pos(node)
	e.scale = scale_
	e.spacing = maxf(spacing, 0.05)
	e.end = _clock + duration
	return e.handle


## Continuous source with re-evaluated endpoints: every `interval` seconds `id` is spawned from `from_cb.call()` to
## `to_cb.call()` (both return Vector3). The tracker is admitted once (one bucket token) and its segments skip the bucket;
## at most 24 trackers are live. Returns -1 when refused.
func start_tracker(id: StringName, from_cb: Callable, to_cb: Callable, interval: float, duration: float, scale_: float = 1.0) -> int:
	var d: FxRecipeBook.FxDef = _recipes.def(id) if _recipes != null else null
	if d == null:
		_warn_once(id, "unknown effect '%s' (tracker)" % id)
		return -1
	if _live_trackers >= MAX_TRACKERS:
		stat_rate_dropped += 1
		return -1
	var pa: Vector3 = from_cb.call() as Vector3
	var pb: Vector3 = to_cb.call() as Vector3
	if not force and not _accept(d, pa, pb, scale_):
		return -1
	var e: Emitter = _new_emitter(EmitterKind.TRACK, id)
	e.from_cb = from_cb
	e.to_cb = to_cb
	e.scale = scale_
	e.interval = maxf(interval, 0.01)
	e.next = _clock
	e.end = _clock + duration
	_live_trackers += 1
	return e.handle


func stop_emitter(handle: int) -> void:
	for e: Emitter in _emitters:
		if e.handle == handle:
			e.end = -1.0


## Spawns every registered effect once in front of the camera so pipelines and shaders compile during loading.
## Call clear_all() a few frames later.
func prewarm() -> void:
	if _recipes == null:
		return
	_refresh_camera()
	var fwd: Vector3 = _cam_fwd
	var p: Vector3 = _cam_pos + fwd * 22.0
	p.y = _ground.height_at(p.x, p.z) if _ground != null else 0.0
	var was: bool = force
	force = true
	_prewarming = true
	for id: StringName in _recipes.ids():
		var d: FxRecipeBook.FxDef = _recipes.def(id)
		spawn(id, p, p + Vector3(8.0, 0.0, -4.0), d.nominal_scale)
	_prewarming = false
	force = was


func clear_all() -> void:
	for b: FxBatch in _batch_list:
		b.clear()
	for i: int in _lights.size():
		_lights[i].visible = false
		_light_dur[i] = 0.0
	_sched.clear()
	_emitters.clear()
	_live_trackers = 0
	_groups.clear()
	_group = 0


func get_stats() -> Dictionary:
	var per_batch: Dictionary = {}
	var shown: int = 0
	for b: FxBatch in _batch_list:
		per_batch[String(b.name)] = [b.spawned, b.overwritten]
		if b.node.visible:
			shown += 1
	var lights: int = 0
	for i: int in _lights.size():
		if _light_dur[i] > 0.0:
			lights += 1
	return {
		"process_us_avg": float(stat_process_us) / maxf(float(stat_process_frames), 1.0), "requests": stat_requests,
		"spawned": stat_spawned, "culled": stat_culled, "rate_dropped": stat_rate_dropped, "unknown": stat_unknown,
		"spawn_us_avg": float(stat_spawn_us) / maxf(float(stat_spawned), 1.0), "batches_shown": shown, "lights": lights,
		"sched": _sched.size(), "emitters": _emitters.size(), "trackers": _live_trackers, "per_batch": per_batch,
	}


func reset_stats() -> void:
	stat_requests = 0
	stat_spawned = 0
	stat_culled = 0
	stat_rate_dropped = 0
	stat_unknown = 0
	stat_spawn_us = 0
	stat_process_us = 0
	stat_process_frames = 0
	for b: FxBatch in _batch_list:
		b.reset_stats()


## Tokens currently in a class bucket (tests).
func bucket_tokens(cls: int) -> float:
	return _tokens[cls]


## The batch (tests, debug overlay).
func batch(name_: StringName) -> FxBatch:
	return _batches.get(name_) as FxBatch


func batch_names() -> Array:
	return _batches.keys()


## Live instances over all batches (tests, HUD stats).
func live_instances() -> int:
	var n: int = 0
	for b: FxBatch in _batch_list:
		n += b.active_count(_clock)
	return n


func live_lights() -> int:
	var n: int = 0
	for i: int in _lights.size():
		if _light_dur[i] > 0.0:
			n += 1
	return n


func pending_scheduled() -> int:
	return _sched.size()


func emitter_count() -> int:
	return _emitters.size()

# ------------------------------------------------------------------ primitives used by the recipe interpreter

## Cluster / billboard sprite effect. `size_m` = radius in metres for clusters, diameter for flash / glow / puff.
func sprites(batch_name: StringName, pos: Vector3, size_m: float, life: float, param: float = 1.0, palette: int = 0) -> void:
	var b: FxBatch = _batches.get(batch_name) as FxBatch
	if b == null:
		return
	if batch_name == &"gglow":
		pos.y = _flat_y(pos)
	var xf: Transform3D = Transform3D(Basis.from_scale(Vector3(size_m, size_m, size_m)), pos)
	_emit(b, xf, life, float(palette) + randf() * 0.99, param)


func puff(batch_name: StringName, pos: Vector3, size_m: float, life: float, alpha: float = 1.0) -> void:
	sprites(batch_name, pos, size_m, life, alpha, 0)


func ribbon(batch_name: StringName, from: Vector3, to: Vector3, life: float, width: float, tail: float, flight: float,
		linger: float, arc: Vector3, palette: int) -> void:
	var b: FxBatch = _batches.get(batch_name) as FxBatch
	if b == null:
		return
	var xf: Transform3D = Transform3D(Basis(arc, to - from, Vector3(tail, maxf(flight, 0.001), maxf(linger, 0.001))), from)
	_emit(b, xf, life, float(palette) + randf() * 0.99, width)


func tracer(from: Vector3, to: Vector3, speed: float, tail: float, width: float, palette: int, arc: Vector3 = Vector3.ZERO) -> void:
	var flight: float = from.distance_to(to) / maxf(speed, 0.01)
	ribbon(&"tracer", from, to, flight + tail / maxf(speed, 0.01), width, tail, flight, 0.0, arc, palette)


## VQ1: smoke trails were long, wide white ribbons that buried a barrage; thinner and shorter-lived they still mark the flight path.
const TRAIL_WIDTH_SCALE: float = 0.6
const TRAIL_LINGER_SCALE: float = 0.65


func trail(from: Vector3, to: Vector3, flight: float, linger: float, width: float, arc: Vector3 = Vector3.ZERO, batch_name: StringName = &"trail") -> void:
	linger *= TRAIL_LINGER_SCALE
	ribbon(batch_name, from, to, flight + linger, width * TRAIL_WIDTH_SCALE, 0.0, flight, linger, arc, 0)


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


func ring(batch_name: StringName, pos: Vector3, radius: float, life: float, palette: int = 0) -> void:
	var b: FxBatch = _batches.get(batch_name) as FxBatch
	if b == null:
		return
	if (batch_name == &"ring_distort" or batch_name == &"haze") and not _use_distort:
		return
	if FLAT_BATCHES.has(batch_name):
		pos.y = _flat_y(pos)
	var xf: Transform3D = Transform3D(Basis.from_scale(Vector3(radius, 1.0, radius)), pos)
	_emit(b, xf, life, float(palette) + randf() * 0.99, 1.0)


## Foam streak on the water along `heading` (a horizontal direction); `length` and `width` are full extents in metres.
func wake(pos: Vector3, heading: Vector3, length: float, width: float, life: float = 4.0) -> void:
	var b: FxBatch = _batches.get(&"wake") as FxBatch
	if b == null:
		return
	var h: Vector3 = Vector3(heading.x, 0.0, heading.z)
	h = h.normalized() if h.length_squared() > 0.000001 else Vector3.RIGHT
	var basis_x: Vector3 = h * (length * 0.5)
	var basis_z: Vector3 = Vector3(-h.z, 0.0, h.x) * (width * 0.5)
	_emit(b, Transform3D(Basis(basis_x, Vector3.UP, basis_z), pos), life, randf() * 0.99, 1.0)


func dome(pos: Vector3, radius: float, life: float, mode: int = 0) -> void:
	var b: FxBatch = _batches.get(&"dome") as FxBatch
	if b == null:
		return
	var xf: Transform3D = Transform3D(Basis.from_scale(Vector3(radius, radius, radius)), pos)
	_emit(b, xf, life, randf() * 0.99, float(mode))


func column(batch_name: StringName, pos: Vector3, radius: float, height: float, life: float) -> void:
	var b: FxBatch = _batches.get(batch_name) as FxBatch
	if b == null:
		return
	var xf: Transform3D = Transform3D(Basis.from_scale(Vector3(radius, height, radius)), pos)
	_emit(b, xf, life, randf() * 0.99, 1.0)


func light_flash(pos: Vector3, color: Color, energy: float, range_m: float, dur: float) -> void:
	if not _use_lights or _light_limit <= 0:
		return
	var pick: int = -1
	var oldest: float = INF
	for i: int in _light_limit:
		if _light_dur[i] <= 0.0:
			pick = i
			break
		var t0: float = _light_t0[i]
		if t0 < oldest:
			oldest = t0
			pick = i
	var l: OmniLight3D = _lights[pick]
	l.position = pos
	l.light_color = color
	l.omni_range = range_m
	l.light_energy = energy
	l.visible = true
	_light_t0[pick] = _clock
	_light_dur[pick] = maxf(dur, 0.01)
	_light_e0[pick] = energy


## Persistent ground mark: paints the ViewScorchLayer (terrain only, no Decal nodes). `life` is advisory (the layer is
## permanent); `hot` > 0 adds a ground-glow sprite (2 s) that cools like the spike's emissive decal.
func scorch(pos: Vector3, radius: float, _life: float, hot: float) -> void:
	if _scorch != null and not _prewarming and not (_ground != null and _ground.is_water_at(pos.x, pos.z)):
		var kind: int = ViewScorchLayer.Kind.CRATER if radius >= 3.0 else ViewScorchLayer.Kind.SCORCH
		_scorch.paint(Vector2(pos.x, pos.z), radius, kind)
		_scorch_dirty = true
	if hot > 0.0:
		sprites(&"gglow", pos, radius * 2.2, 2.0, 0.55 * hot, 6)


## Emits the camera-shake hook (attenuated linearly to 0 at 140 m from the camera).
func shake(amount: float, pos: Vector3) -> void:
	if amount <= 0.0:
		return
	var k: float = 1.0
	if _cam != null:
		k = clampf(1.0 - _cam_pos.distance_to(pos) / SHAKE_RANGE, 0.0, 1.0)
	if k > 0.0:
		camera_shake.emit(amount * k, pos)

# ------------------------------------------------------------------ internals

func _warn_once(id: StringName, msg: String) -> void:
	if _warned.has(id):
		return
	_warned[id] = true
	Log.warn("view", "FxManager: " + msg)


func _new_emitter(kind: int, id: StringName) -> Emitter:
	var e: Emitter = Emitter.new()
	e.handle = _next_handle
	_next_handle += 1
	e.kind = kind
	e.id = id
	e.group = _group
	_emitters.append(e)
	return e


static func _node_pos(n: Node3D) -> Vector3:
	return n.global_position if n.is_inside_tree() else n.position


func _apply_class_table() -> void:
	if _recipes == null:
		return
	for c: int in CLASS_NAMES.size():
		var row: Dictionary = _recipes.class_table.get(CLASS_NAMES[c], {}) as Dictionary
		if row.is_empty():
			continue
		_cls_max[c] = float(row.get("max_dist", _cls_max[c]))
		_cls_min_px[c] = float(row.get("min_px", _cls_min_px[c]))
		_cls_rate[c] = float(row.get("refill", _cls_rate[c]))
		_cls_burst[c] = float(row.get("burst", _cls_burst[c]))
		_tokens[c] = _cls_burst[c]


func _add(id: StringName, mesh: Mesh, mat: Material) -> void:
	var b: FxBatch = FxBatch.new(id, mesh, mat, int((BATCHES[id] as Array)[1]), self)
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
	var w: Color = Color.WHITE
	var pa: int = ViewLayers.PRIO_REFRACT_A
	var pb: int = ViewLayers.PRIO_REFRACT_B
	_add(&"gglow", c1, FxAssets.sprite_material(10, w, -4, 0.0))
	_add(&"smoke", c10, FxAssets.sprite_material(1, w, -3))
	_add(&"dustring", c12, FxAssets.sprite_material(4, dust, -2))
	_add(&"dustcol", c9, FxAssets.sprite_material(5, Color(0.66, 0.58, 0.47, 0.95), -2))
	_add(&"puff_dust", c1, FxAssets.sprite_material(6, dust, -2, 0.8, 1.0, false, 0.0, 0.85, 0.5))
	_add(&"puff_smoke", c1, FxAssets.sprite_material(6, Color(0.36, 0.34, 0.32, 1.0), -2, 0.8, 1.0, false, 0.0, 0.85, 2.4))
	_add(&"puff_white", c1, FxAssets.sprite_material(6, Color(0.93, 0.94, 0.96, 0.85), -1, 0.8, 1.0, false, 0.0, 0.85, 0.15))
	_add(&"fire", c14, FxAssets.sprite_material(0, w, 0))
	_add(&"debris", c12, FxAssets.sprite_material(2, w, 1, 0.0))
	_add(&"rubble", c20, FxAssets.sprite_material(2, w, 1, 0.0, 1.0, false, 1.3, 0.94))
	_add(&"sparks", c20, FxAssets.sprite_material(3, w, 2, 0.0))
	_add(&"splash", c16, FxAssets.sprite_material(7, w, 1, 0.0))
	_add(&"flash", c1, FxAssets.sprite_material(8, w, 3, 0.0))
	_add(&"glow", c1, FxAssets.sprite_material(9, w, 3, 0.0))
	_add(&"trail", rib, FxAssets.ribbon_material(1, -1, Color(0.92, 0.92, 0.94, 0.48)))
	_add(&"trail_dark", rib, FxAssets.ribbon_material(1, -1, Color(0.22, 0.22, 0.24, 1.0)))
	_add(&"contrail", rib, FxAssets.ribbon_material(6, -1, Color(1.0, 1.0, 1.0, 0.55)))
	_add(&"firetrail", rib, FxAssets.ribbon_material(7, 1))
	_add(&"tracer", rib, FxAssets.ribbon_material(0, 2))
	_add(&"beam", rib, FxAssets.ribbon_material(2, 2))
	_add(&"rail", rib, FxAssets.ribbon_material(3, 2))
	_add(&"arc", rib, FxAssets.ribbon_material(4, 2))
	_add(&"cone", rib, FxAssets.ribbon_material(5, 2))
	_add(&"shimmer", rib, FxAssets.shimmer_material(pa, 2.2))
	_add(&"ring_add", flat, FxAssets.ring_material(0, false, 2))
	_add(&"ring_distort", flat, FxAssets.ring_material(0, true, pb))
	_add(&"ring_emp", flat, FxAssets.ring_material(1, false, 2))
	_add(&"marker", flat, FxAssets.ring_material(2, false, 2))
	_add(&"ripple", flat, FxAssets.ring_material(3, false, 0))
	_add(&"haze", flat, FxAssets.ring_material(4, true, pb))
	_add(&"wake", flat, FxAssets.ring_material(5, false, -3))
	_add(&"dome", FxAssets.dome_mesh(), FxAssets.dome_material(0))
	_add(&"beacon", FxAssets.column_mesh(), FxAssets.column_material(0))
	_add(&"strike", FxAssets.column_mesh(), FxAssets.column_material(1))


func _build_lights() -> void:
	for i: int in MAX_LIGHTS:
		var l: OmniLight3D = OmniLight3D.new()
		l.shadow_enabled = false
		l.visible = false
		l.name = "FxLight%d" % i
		add_child(l)
		_lights.append(l)
	_light_t0.resize(MAX_LIGHTS)
	_light_dur.resize(MAX_LIGHTS)
	_light_e0.resize(MAX_LIGHTS)


func _emit(b: FxBatch, xf: Transform3D, life: float, seed_v: float, param: float) -> void:
	if not hidden_batches.is_empty() and hidden_batches.has(b.name):
		return
	var slot: int = b.emit(xf, _clock, life, seed_v, param)
	if trace_emits:
		emit_log.append([b.name, xf, _clock, life, seed_v, param])
	if _group != 0:
		_rec.append(b.index)
		_rec.append(slot)
		_rec_t.append(float(_clock))


func _flat_y(p: Vector3) -> float:
	if _ground == null:
		return p.y
	if _ground.is_water_at(p.x, p.z):
		return p.y
	var h: float = _ground.height_at(p.x, p.z)
	return h if p.y - h < 3.0 else p.y


func _refresh_camera() -> void:
	if _cam == null:
		return
	var xf: Transform3D = _cam.global_transform if _cam.is_inside_tree() else _cam.transform
	_cam_pos = xf.origin
	_cam_inv = xf.affine_inverse()
	_cam_fwd = -xf.basis.z.normalized()
	_cam_persp = _cam.projection == Camera3D.PROJECTION_PERSPECTIVE
	if viewport_size_override.x > 0.0:
		_vp = viewport_size_override
	elif _cam.is_inside_tree():
		_vp = _cam.get_viewport().get_visible_rect().size
	var half: float = tan(deg_to_rad(_cam.fov) * 0.5)
	if _cam.keep_aspect == Camera3D.KEEP_WIDTH:
		_px_per_rad = _vp.x / (2.0 * half)
	else:
		_px_per_rad = _vp.y / (2.0 * half)


# Admission (render spec 5.9.1): token bucket, then distance (+ camera focus distance), projected size and frustum.
func _accept(d: FxRecipeBook.FxDef, a: Vector3, b: Vector3, scale_: float) -> bool:
	var c: int = d.cls
	if not _tracker_emit and _tokens[c] < 1.0:
		stat_rate_dropped += 1
		return false
	if _cam != null:
		var r: float = d.radius * scale_
		var ok: bool = _in_view(a, r, c)
		if not ok and d.kind == Kind.LINE:
			ok = _in_view(b, r, c)
		if not ok:
			stat_culled += 1
			return false
	if not _tracker_emit:
		_tokens[c] -= 1.0
	return true


func _in_view(p: Vector3, r: float, c: int) -> bool:
	var dist: float = _cam_pos.distance_to(p)
	var mx: float = _cls_max[c]
	if mx > 0.0 and dist > mx * _dist_mult + camera_focus_dist:
		return false
	var px: float = r * _px_per_rad / maxf(dist, 0.5)
	if px < _cls_min_px[c]:
		return false
	if not _cam_persp:
		return true
	var v: Vector3 = _cam_inv * p
	if v.z >= 0.0:
		return dist < r
	var k: float = _px_per_rad / -v.z
	var sx: float = _vp.x * 0.5 + v.x * k
	var sy: float = _vp.y * 0.5 - v.y * k
	return sx > -px and sy > -px and sx < _vp.x + px and sy < _vp.y + px


func _run_scheduled() -> void:
	var i: int = _sched.size() - 1
	while i >= 0:
		if i < _sched.size():
			var e: Sched = _sched[i]
			if _clock >= e.t:
				_sched.remove_at(i)
				var was_group: int = _group
				_group = e.group
				if e.cb.is_valid():
					e.cb.call()
				else:
					spawn(e.id, e.a, e.b, e.s)
				_group = was_group
		i -= 1


func _run_emitters() -> void:
	var i: int = _emitters.size() - 1
	while i >= 0:
		if i >= _emitters.size():
			i -= 1
			continue
		var e: Emitter = _emitters[i]
		var dead: bool = _clock >= e.end
		if e.kind == EmitterKind.STAMP and not dead and not is_instance_valid(e.node):
			dead = true
		if e.kind == EmitterKind.TRACK and not dead and not (e.from_cb.is_valid() and e.to_cb.is_valid()):
			dead = true
		if dead:
			if e.kind == EmitterKind.TRACK:
				_live_trackers = maxi(_live_trackers - 1, 0)
			_emitters.remove_at(i)
			i -= 1
			continue
		var was_group: int = _group
		_group = e.group
		match e.kind:
			EmitterKind.STAMP:
				_run_stamper(e)
			EmitterKind.TRACK:
				var guard_t: int = 0
				while _clock >= e.next and guard_t < 2:
					_tracker_emit = true
					spawn(e.id, e.from_cb.call() as Vector3, e.to_cb.call() as Vector3, e.scale)
					_tracker_emit = false
					e.next += e.interval
					guard_t += 1
				if guard_t == 2 and _clock >= e.next:
					e.next = _clock + e.interval
			_:
				var guard: int = 0
				while _clock >= e.next and guard < 4:
					spawn(e.id, e.pos_a, e.pos_b, e.scale)
					e.next += e.interval
					guard += 1
				if guard == 4:
					e.next = _clock + e.interval
		_group = was_group
		i -= 1


func _run_stamper(e: Emitter) -> void:
	var p: Vector3 = _node_pos(e.node)
	var seg: Vector3 = p - e.last_pos
	var dist: float = seg.length()
	if dist < e.spacing:
		return
	var total: int = maxi(int(dist / e.spacing), 1)
	var n: int = mini(total, 8)
	var step: Vector3 = seg / float(total)
	for k: int in n:
		spawn(e.id, e.last_pos + step * float(k + 1), Vector3.ZERO, e.scale)
	e.last_pos = p


func _update_lights() -> void:
	for i: int in _lights.size():
		var dur: float = _light_dur[i]
		if dur <= 0.0:
			continue
		var t: float = float(_clock - _light_t0[i]) / dur
		if t >= 1.0:
			_lights[i].visible = false
			_light_dur[i] = 0.0
		else:
			_lights[i].light_energy = _light_e0[i] * (1.0 - t) * (1.0 - t)


func _flush_scorch() -> void:
	_scorch_dirty = false
	_scorch_next_flush = _clock + SCORCH_FLUSH_S
	if _scorch != null:
		_scorch.flush()
