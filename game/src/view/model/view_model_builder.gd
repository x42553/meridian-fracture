class_name ViewModelBuilder
extends RefCounted
## Model cache and build pipeline (render spec 5.8.1). `get_model` is synchronous and cached; `request` builds on a
## WorkerThreadPool task (interpreter + mesh arrays only: a pure function of recipe / style / scale, no engine singletons) and
## `pump` finalises the ArrayMesh on the main thread within a time budget. A missing or failing recipe yields a placeholder box
## sized by the archetype's size class, with ONE Log.warn per recipe id (missing) or Log.error (op-path error).
##
## key      = recipe_id + "@" + style_id + "#" + scale_bp
## seed     = fnv1a32(recipe_id) xor fnv1a32(style_id) (xor the recipe's own `seed` when set): the same look on every client
## scale    = recipe.scale * archetype.scale * scale_bp / 10000

signal model_ready(key: StringName)

const MAX_VERTS: int = 65535
## size class -> placeholder box (x width, y height, z length) in metres
const SIZE_BOX: Dictionary = {
	"inf": Vector3(1.4, 1.3, 1.4), "squad": Vector3(1.4, 1.3, 1.4), "light": Vector3(1.9, 1.5, 3.4), "medium": Vector3(2.0, 1.7, 3.6),
	"heavy": Vector3(2.6, 2.1, 4.8), "huge": Vector3(4.6, 3.2, 7.0), "air": Vector3(3.5, 1.2, 4.5), "ship": Vector3(2.0, 1.6, 5.0),
	"structure": Vector3(5.0, 4.0, 5.0),
}

## Godot 4.7.2 engine bug worked around here (found by QA2 on the exported build, ~2 % of real-renderer match boots crashed with SIGSEGV in a
## WorkerThread inside the recipe interpreter): the GDScript VM caches the evaluator of an UNTYPED operator inside the function's bytecode on
## its first execution, and publishes it without synchronisation (type pair first, function pointer second). A second thread running the same
## site at that moment reads a null / torn pointer and jumps to it. The burst of model builds that starts a match is exactly that (every worker
## starts in `ViewRecipeInterpreter._num`), so the first builds run alone on the main thread: they execute (and cache) the common sites before
## any worker does. One build per distinct archetype up to WARM_MAX covers the op-specific functions too. tools/py/gdscript_race_probe.py
## reproduces the engine bug in isolation. The crash handler's `caller thread can't call propagate_notification()` line is its side effect.
const WARM_MAX: int = 24
static var _warm_archs: Dictionary = {}  # archetype id -> true (warmed on the main thread)
static var _warm_count: int = 0

## Builders with background builds in flight (instance id -> WeakRef): `cancel_all()` joins them at quit even if their owner never told them to stop.
static var _live: Dictionary = {}

var _book: ViewRecipeBook = null
var _quality: ViewQuality = null
var _cache: Dictionary = {}  # StringName -> ViewModel
var _inflight: Dictionary = {}  # StringName -> worker task id
var _cancel: bool = false  # read by the worker tasks under `_lock`
var _done: Array = []  # finished worker results awaiting pump()
var _lock: Mutex = Mutex.new()
var _warned: Dictionary = {}  # recipe id -> true
## Models built synchronously on the calling (main) thread because nothing requested them in advance: each is a visible hitch mid-match
## (the prewarm of ViewWorld should leave this at 0 after the loading screen). Count, total ms, last recipe key.
var stat_sync_builds: int = 0
var stat_sync_ms: float = 0.0
var stat_sync_last: String = ""


func setup(book: ViewRecipeBook, q: ViewQuality) -> void:
	_book = book
	_quality = q
	ViewExpr.quiet = true  # recipe expression errors are reported (with the op path) by this builder


static func key_of(recipe_id: StringName, style_id: StringName, scale_bp: int) -> StringName:
	return StringName("%s@%s#%d" % [recipe_id, style_id, scale_bp])


static func fnv1a32(s: String) -> int:
	var h: int = 2166136261
	for byte: int in s.to_utf8_buffer():
		h = ((h ^ byte) * 16777619) & 0xFFFFFFFF
	return h


## Synchronous, cached. Placeholder box when the recipe is missing or invalid.
func get_model(recipe_id: StringName, style_id: StringName, scale_bp: int = 10000) -> ViewModel:
	var key: StringName = key_of(recipe_id, style_id, scale_bp)
	var m: ViewModel = _cache.get(key) as ViewModel
	if m != null:
		return m
	var t0: int = Time.get_ticks_usec()
	var built: ViewModel = _finalize(build_data(_book, recipe_id, style_id, scale_bp))
	stat_sync_builds += 1
	stat_sync_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	stat_sync_last = String(key)
	return built


## Background build; the model appears in the cache (and model_ready fires) after a later pump().
func request(recipe_id: StringName, style_id: StringName, scale_bp: int = 10000) -> void:
	var key: StringName = key_of(recipe_id, style_id, scale_bp)
	if _cache.has(key) or _inflight.has(key):
		return
	if _warm_on_main(recipe_id):
		_finalize(build_data(_book, recipe_id, style_id, scale_bp))
		model_ready.emit(key)
		return
	_inflight[key] = WorkerThreadPool.add_task(_worker.bind(recipe_id, style_id, scale_bp), false, "ViewModelBuilder " + String(key))
	_live[get_instance_id()] = weakref(self)


## True (and the archetype is marked warm) when this request must be built right now on the main thread: see WARM_MAX.
func _warm_on_main(recipe_id: StringName) -> bool:
	if _warm_count >= WARM_MAX or _book == null or OS.get_thread_caller_id() != OS.get_main_thread_id():
		return false
	var r: ViewRecipe = _book.recipe(recipe_id)
	if r == null or r.arch == null or _warm_archs.has(r.arch.id):
		return false
	_warm_archs[r.arch.id] = true
	_warm_count += 1
	return true


## Tests: forget which archetypes were warmed (the process-wide state outlives a builder).
static func reset_warm() -> void:
	_warm_archs.clear()
	_warm_count = 0


## Finalises finished background builds on the main thread until `budget_ms` is spent (at least one). Returns how many finished.
func pump(budget_ms: float = 4.0) -> int:
	var t0: int = Time.get_ticks_usec()
	var n: int = 0
	while true:
		_lock.lock()
		var res: Variant = _done.pop_front() if not _done.is_empty() else null
		_lock.unlock()
		if res == null:
			break
		var data: Dictionary = res as Dictionary
		var key: StringName = data["key"] as StringName
		if _inflight.has(key):
			WorkerThreadPool.wait_for_task_completion(_inflight[key] as int)
			_inflight.erase(key)
		if _cache.has(key):
			continue  # a synchronous get_model() won the race
		_finalize(data)
		n += 1
		model_ready.emit(key)
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	return n


## Requested builds not yet finalised (running or waiting for pump()).
func pending() -> int:
	return _inflight.size()


func cached_count() -> int:
	return _cache.size()


func has_model(recipe_id: StringName, style_id: StringName, scale_bp: int = 10000) -> bool:
	return _cache.has(key_of(recipe_id, style_id, scale_bp))


func clear() -> void:
	_wait_all()
	_cache.clear()
	_warned.clear()


## Cooperative cancel (quit / teardown): queued background builds return at once, running ones finish, then every task is joined. The builder is
## reusable afterwards. A task left running or queued when the engine shuts down hangs `Main::cleanup` (task of a freed script object).
## Cancels and joins the background builds of every live builder (quit). Main thread only.
static func cancel_all() -> int:
	var n: int = 0
	for id: Variant in _live.keys():
		var b: ViewModelBuilder = (_live[id] as WeakRef).get_ref() as ViewModelBuilder
		if b != null and not b._inflight.is_empty():
			b.cancel()
			n += 1
	_live.clear()
	return n


func cancel() -> void:
	_lock.lock()
	_cancel = true
	_lock.unlock()
	_wait_all()
	_lock.lock()
	_cancel = false
	_lock.unlock()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _inflight.is_empty():
		# inline (no method call on self: the object is being destroyed): skip queued builds, join the running ones
		_lock.lock()
		_cancel = true
		_lock.unlock()
		if WorkerThreadPool.get_caller_task_id() == -1:  # a pool task that dropped the last reference must not join itself
			for k: Variant in _inflight:
				WorkerThreadPool.wait_for_task_completion(_inflight[k] as int)
		_inflight.clear()


func _wait_all() -> void:
	for k: Variant in _inflight:
		WorkerThreadPool.wait_for_task_completion(_inflight[k] as int)
	_inflight.clear()
	_lock.lock()
	_done.clear()
	_lock.unlock()


func _worker(recipe_id: StringName, style_id: StringName, scale_bp: int) -> void:
	_lock.lock()
	var stop: bool = _cancel
	_lock.unlock()
	if stop:
		return
	var data: Dictionary = build_data(_book, recipe_id, style_id, scale_bp)
	_lock.lock()
	_done.append(data)
	_lock.unlock()


## Main-thread step: ArrayMesh from the arrays, logging, cache.
func _finalize(data: Dictionary) -> ViewModel:
	var key: StringName = data["key"] as StringName
	var m: ViewModel = ViewModel.new()
	m.key = key
	m.recipe_id = data["recipe"] as StringName
	m.style_id = data["style"] as StringName
	m.mesh = ViewMeshBuilder.mesh_from_arrays(data["mesh"] as Dictionary, String(key))
	m.info = data["info"] as ViewModelInfo
	m.meta = data["meta"] as Dictionary
	m.placeholder = data["placeholder"] as bool
	m.error = data["error"] as String
	if m.placeholder:
		if data["missing"] as bool:
			if not _warned.has(m.recipe_id):
				_warned[m.recipe_id] = true
				Log.warn("view", "no recipe '%s': placeholder box (%s)" % [m.recipe_id, data["size_class"]])
		else:
			Log.error("view", "recipe build failed, placeholder used: %s" % m.error)
	_cache[key] = m
	return m


## Pure build of one model (safe on any thread): {key, recipe, style, mesh (arrays for mesh_from_arrays), info, meta, placeholder,
## missing, error, size_class}.
static func build_data(book: ViewRecipeBook, recipe_id: StringName, style_id: StringName, scale_bp: int) -> Dictionary:
	var out: Dictionary = {"key": key_of(recipe_id, style_id, scale_bp), "recipe": recipe_id, "style": style_id, "placeholder": false,
		"missing": false, "error": "", "size_class": "medium", "meta": {}}
	var r: ViewRecipe = book.recipe(recipe_id) if book != null else null
	if r == null:
		out["missing"] = true
	else:
		var arch: ViewRecipe.Archetype = r.arch
		out["size_class"] = String(arch.size_class) if arch != null else "medium"
		var sid: StringName = style_id
		if sid == &"" or sid == &"auto":
			sid = r.style if r.style != &"auto" else ViewRecipeBook.NEUTRAL
		var b: ViewMeshBuilder = ViewMeshBuilder.new()
		var seed_v: int = fnv1a32(String(recipe_id)) ^ fnv1a32(String(style_id))
		if r.seed_override != 0:
			seed_v ^= r.seed_override
		b.seed_rng(seed_v)
		if arch != null:
			b.default_bevel = r.bevel if r.bevel >= 0.0 else arch.bevel
			b.model_scale = r.scale * arch.scale * ViewConsts.visual_boost(arch.id, arch.size_class) * float(scale_bp) / 10000.0
		var ip: ViewRecipeInterpreter = ViewRecipeInterpreter.new()
		ip.seed_base = seed_v
		ip.style_id = sid
		ip.extra_vars = book.footprint_vars(recipe_id)  # structures: fw, fh, door_cx, ... (empty for units)
		ip.run(r, book.style(sid), b)
		if ip.error == "":
			var data: Dictionary = b.build_arrays()
			var mi: ViewModelInfo = b.info()
			if mi.verts > MAX_VERTS:
				ip.error = "%s: %d vertices exceed the 16-bit index limit %d" % [recipe_id, mi.verts, MAX_VERTS]
			elif mi.verts == 0 or not _finite_aabb(mi.rest_aabb):
				ip.error = "%s: the recipe produced no geometry or a non-finite bounding box" % recipe_id
			else:
				mi.livery_tris = ip.livery_tris
				mi.boost = ViewConsts.visual_boost(arch.id, arch.size_class) if arch != null else 1.0
				out["mesh"] = data
				out["info"] = mi
				out["meta"] = ip.meta
				return out
		out["error"] = ip.error
	out["placeholder"] = true
	var sz: Vector3 = SIZE_BOX.get(out["size_class"], SIZE_BOX["medium"]) as Vector3
	var pb: ViewMeshBuilder = ViewMeshBuilder.new()
	pb.brush(Color(0.85, 0.22, 0.75))
	pb.box(Vector3(0.0, sz.y * 0.5, 0.0), sz, 0.03)
	out["mesh"] = pb.build_arrays()
	out["info"] = pb.info()
	return out


static func _finite_aabb(bb: AABB) -> bool:
	return is_finite(bb.position.x) and is_finite(bb.position.y) and is_finite(bb.position.z) \
		and is_finite(bb.size.x) and is_finite(bb.size.y) and is_finite(bb.size.z)
