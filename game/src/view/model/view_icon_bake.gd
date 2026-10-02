class_name ViewIconBake
extends Node
## Build-card icons and selection portraits (render spec 5.8.10, VIEW-M9). One persistent SubViewport studio (own World3D,
## transparent background, MSAA 4x, LOD0 only, key + fill light, 30 degree camera at 24 degrees pitch) renders a model in
## its style's accent colour (icons are faction-branded, not player-coloured), framed from the mesh's `rest_aabb`.
##
## Requests are asynchronous: `request()` returns the texture when it is already known and otherwise queues a job and
## returns null; `icon_ready(tag)` fires when the texture exists. A job first looks for `user://cache/icons/<key>.png`
## (key = model content hash + style look + studio version + size, so a stale file is impossible); only a miss renders,
## one icon per frame (two frame waits, about 19 ms warm), and the PNG is written on a worker thread. The cache-hit path is
## a file read plus ImageTexture creation (stats `hit_us_*`). Without a renderer (headless) only cache hits are served.
##
## Two ways to get one: `setup(book, models, mats, quality)` shares the match's builders, `ViewIconBake.shared()` owns a
## private recipe book + model builder and lives under the SceneTree root (menus, Field Manual, tests).

signal icon_ready(tag: StringName)
signal idle()  ## the job queue ran empty

const VERSION: int = 7  ## bump when the studio look changes: old cache files simply stop matching
const S_ICON: int = 0  ## 128 x 96
const S_PORTRAIT: int = 1  ## 384 x 288
const S_CARD: int = 2  ## 188 x 124 (build cards, 3:2)
const S_BANNER: int = 3  ## 304 x 152 (selection portrait, 2:1)
const SIZES: Array[Vector2i] = [Vector2i(128, 96), Vector2i(384, 288), Vector2i(188, 124), Vector2i(304, 152)]
const YAW_DEG: float = 150.0  ## model yaw: a 3/4 front view (front = -Z model space)
const PITCH_DEG: float = 24.0
const FOV_DEG: float = 30.0
const MARGIN: float = 0.95  ## the projected AABB fills this fraction of the frame (the silhouette is tighter than its box)
const DEFAULT_DIR: String = "user://cache/icons"
const HIT_BUDGET_US: int = 6000  ## cache hits served per frame before yielding
const RESERVE: Array[float] = [0.0, 0.0, 0.16, 0.0]  ## bottom fraction of the frame left free for the card's cost strip (per size)
const MAX_ATTEMPTS: int = 3  ## a render that fails the sanity check is repeated with more frame waits

var cache_dir: String = DEFAULT_DIR
var use_disk: bool = true
var render_enabled: bool = true
var stats: Dictionary = {"hits": 0, "bakes": 0, "mem_hits": 0, "skipped": 0, "hit_us_last": 0, "hit_us_max": 0, "hit_us_sum": 0,
	"bake_ms_last": 0.0, "bake_ms_sum": 0.0, "saved": 0, "retries": 0, "failed": 0}

var _book: ViewRecipeBook = null
var _models: ViewModelBuilder = null
var _mats: ViewMaterials = null
var _quality: ViewQuality = null
var _own_stack: bool = false
var _queue: Array[Dictionary] = []
var _wanted: Dictionary = {}  # request key -> Array of tags
var _tex: Dictionary = {}  # request key -> Texture2D
var _by_content: Dictionary = {}  # content key -> Texture2D
var _running: bool = false
var _tasks: Array[int] = []
var _vp: SubViewport = null
var _cam: Camera3D = null
var _rig: MeshInstance3D = null
var _blob: MeshInstance3D = null
var _mat_of: Dictionary = {}  # style id -> ShaderMaterial (accent team colour)
var _style_cache: Dictionary = {}  # style id -> [look hash, accent Color]

static var _shared: ViewIconBake = null


## Orderly quit: drops the shared service's baked textures and forgets it (the node itself is freed with the tree: removing children is not allowed
## while the tree tears down, and this runs from AppState._exit_tree).
static func release_shared() -> void:
	if _shared != null and is_instance_valid(_shared):
		_shared.flush()
		_shared.clear_memory()
	_shared = null


## The process-wide standalone service (private recipe book, model builder and materials), added under the SceneTree root.
static func shared() -> ViewIconBake:
	if _shared != null and is_instance_valid(_shared):
		return _shared
	var b: ViewIconBake = ViewIconBake.new()
	b.name = "ViewIconBake"
	b.setup_standalone()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child.call_deferred(b)
	_shared = b
	return b


## Shares the builders of a running ViewWorld (recipes are parsed once).
func setup(book: ViewRecipeBook, models: ViewModelBuilder, mats: ViewMaterials, q: ViewQuality) -> void:
	_book = book
	_models = models
	_mats = mats
	_quality = q
	_own_stack = false
	_mat_of.clear()
	_style_cache.clear()
	render_enabled = DisplayServer.get_name() != "headless"


## Private stack: loads all recipes (once) and builds models on demand.
func setup_standalone() -> void:
	ViewGlobals.ensure()
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var models: ViewModelBuilder = ViewModelBuilder.new()
	models.setup(book, q)
	var mats: ViewMaterials = ViewMaterials.new()
	mats.setup(book, q)
	setup(book, models, mats, q)
	_own_stack = true


func _enter_tree() -> void:
	if not _queue.is_empty():
		_kick()


func _exit_tree() -> void:
	flush()


func recipe_book() -> ViewRecipeBook:
	return _book


func model_builder() -> ViewModelBuilder:
	return _models


# ---- public API -------------------------------------------------------------------------------------------------------

## Cached texture or null (a job is queued; `icon_ready(tag)` follows). `size` = S_*.
func request(tag: StringName, recipe_id: StringName, style_id: StringName, scale_bp: int = 10000, size: int = S_ICON) -> Texture2D:
	var sz: int = clampi(size, 0, SIZES.size() - 1)
	var rk: String = request_key(recipe_id, style_id, scale_bp, sz)
	var hit: Texture2D = _tex.get(rk) as Texture2D
	if hit != null:
		stats["mem_hits"] = int(stats["mem_hits"]) + 1
		return hit
	if _wanted.has(rk):
		var tags: Array = _wanted[rk] as Array
		if not tags.has(tag):
			tags.append(tag)
		return null
	_wanted[rk] = [tag]
	_queue.append({"rk": rk, "recipe": recipe_id, "style": style_id, "scale": scale_bp, "size": sz})
	_kick()
	return null


## Same for a resolved def: recipe and scale from the ViewDef, style from the def id and the owner's roster (`roster.napc.canada`).
func request_def(tag: StringName, vd: ViewDef, roster_id: String, size: int = S_ICON) -> Texture2D:
	return request(tag, vd.recipe_id, _book.style_for_def(vd.id, roster_id), vd.scale_bp, size)


## Queues many icons at once: entries `{tag, recipe, style, scale_bp, size}`. Returns the number of new jobs.
func prewarm(reqs: Array) -> int:
	var before: int = _queue.size()
	for r: Variant in reqs:
		var d: Dictionary = r as Dictionary
		request(d["tag"] as StringName, d["recipe"] as StringName, d["style"] as StringName, int(d.get("scale_bp", 10000)), int(d.get("size", S_ICON)))
	return _queue.size() - before


## The texture when it is already in memory, without queueing anything.
func peek(recipe_id: StringName, style_id: StringName, scale_bp: int = 10000, size: int = S_ICON) -> Texture2D:
	return _tex.get(request_key(recipe_id, style_id, scale_bp, clampi(size, 0, SIZES.size() - 1))) as Texture2D


func pending() -> int:
	return _queue.size() + (1 if _running and _queue.is_empty() else 0)


func is_idle() -> bool:
	return _queue.is_empty() and not _running


## Coroutine: returns once every queued job is done (the caller must be in the tree).
func wait_idle() -> void:
	while not is_idle():
		await get_tree().process_frame


## Waits for the background PNG writers.
func flush() -> void:
	for id: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


## The disk-cache file key of a request (builds the model when it is not cached yet).
func cache_key_for(recipe_id: StringName, style_id: StringName, scale_bp: int, size: int) -> String:
	var model: ViewModel = _models.get_model(recipe_id, style_id, scale_bp)
	return content_key(model.info.content_hash, _look_of(style_id)[0] as int, SIZES[clampi(size, 0, SIZES.size() - 1)])


static func request_key(recipe_id: StringName, style_id: StringName, scale_bp: int, size: int) -> String:
	return "%s@%s#%d|%d" % [recipe_id, style_id, scale_bp, size]


## Cache file key: content of the mesh + the style's look + studio version + size.
static func content_key(content_hash: int, look_hash: int, size: Vector2i) -> String:
	return "%016x_%08x_v%d_%dx%d" % [content_hash, look_hash & 0xFFFFFFFF, VERSION, size.x, size.y]


func cache_path(content_key_str: String) -> String:
	return "%s/%s.png" % [cache_dir, content_key_str]


## Deletes every cached icon file (tests, "clear caches").
func clear_disk_cache() -> int:
	flush()
	var n: int = 0
	var da: DirAccess = DirAccess.open(cache_dir)
	if da == null:
		return 0
	for f: String in da.get_files():
		if f.ends_with(".png") and da.remove(f) == OK:
			n += 1
	return n


## Forgets the in-memory textures (the disk cache stays): the next request takes the cache-hit path again.
func clear_memory() -> void:
	_tex.clear()
	_by_content.clear()


# ---- framing (pure maths; unit tested) ---------------------------------------------------------------------------------

## Camera pose that shows `box` (model space, rotated by `yaw_deg` about Y) inside `margin` of the frame: {pos, target,
## basis, distance, fill} where `fill` is the largest projected half extent (<= margin).
static func frame_camera(box: AABB, yaw_deg: float, pitch_deg: float, fov_deg: float, aspect: float, margin: float, reserve: float = 0.0) -> Dictionary:
	var rot: Basis = Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var corners: PackedVector3Array = PackedVector3Array()
	for i: int in 8:
		corners.append(rot * box.get_endpoint(i))
	var cb: Basis = Basis(Vector3.RIGHT, deg_to_rad(-pitch_deg))
	var inv: Basis = cb.inverse()
	var tan_v: float = tan(deg_to_rad(fov_deg) * 0.5)
	var tan_h: float = tan_v * aspect
	var target: Vector3 = rot * box.get_center()
	var dist: float = maxf(box.size.length(), 0.5) * 2.0
	var fill: float = 1.0
	for _it: int in 24:
		var pos: Vector3 = target + cb.z * dist
		var lo: Vector2 = Vector2(INF, INF)
		var hi: Vector2 = Vector2(-INF, -INF)
		for c: Vector3 in corners:
			var v: Vector3 = inv * (c - pos)
			var depth: float = maxf(-v.z, 0.05)
			var p: Vector2 = Vector2(v.x / (depth * tan_h), v.y / (depth * tan_v))
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		# `reserve` keeps the lowest part of the frame free: the box is fitted into [-1 + 2 * reserve, 1] vertically
		var half_y: float = (hi.y - lo.y) * 0.5 / (1.0 - reserve)
		var half: float = maxf((hi.x - lo.x) * 0.5, half_y)
		fill = half
		var mid: Vector2 = (lo + hi) * 0.5
		target += cb.x * (mid.x * dist * tan_h) + cb.y * ((mid.y - reserve) * dist * tan_v)
		if half > 0.0001:
			dist = clampf(dist * half / margin, 0.3, 500.0)
	return {"pos": target + cb.z * dist, "target": target, "basis": cb, "distance": dist, "fill": fill}


# ---- job loop -----------------------------------------------------------------------------------------------------------

func _kick() -> void:
	if _running or _queue.is_empty() or not is_inside_tree():
		return
	_running = true
	_run.call_deferred()


func _run() -> void:
	var hit_us: int = 0
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front() as Dictionary
		var rk: String = job["rk"] as String
		if _tex.has(rk):
			_finish(rk, _tex[rk] as Texture2D)
			continue
		var size: Vector2i = SIZES[job["size"] as int]
		var model: ViewModel = _models.get_model(job["recipe"] as StringName, job["style"] as StringName, job["scale"] as int)
		var look: Array = _look_of(job["style"] as StringName)
		var ck: String = content_key(model.info.content_hash, look[0] as int, size)
		var t0: int = Time.get_ticks_usec()
		var tex: Texture2D = _by_content.get(ck) as Texture2D
		if tex == null:
			tex = _load_png(ck)
		if tex != null:
			_by_content[ck] = tex
			var us: int = Time.get_ticks_usec() - t0
			_note_hit(us)
			_finish(rk, tex)
			hit_us += us
			if hit_us > HIT_BUDGET_US:
				hit_us = 0
				await get_tree().process_frame
			continue
		if not render_enabled:
			stats["skipped"] = int(stats["skipped"]) + 1
			_wanted.erase(rk)
			continue
		var b0: int = Time.get_ticks_usec()
		var img: Image = null
		for attempt: int in MAX_ATTEMPTS:
			img = await _bake(model, job["style"] as StringName, size, look[1] as Color, 2 + attempt * 2, RESERVE[job["size"] as int])
			if img == null or image_ok(img):
				break
			stats["retries"] = int(stats["retries"]) + 1
			img = null
		if img == null:
			_wanted.erase(rk)
			stats["failed"] = int(stats["failed"]) + 1
			continue
		var ms: float = float(Time.get_ticks_usec() - b0) / 1000.0
		stats["bakes"] = int(stats["bakes"]) + 1
		stats["bake_ms_last"] = ms
		stats["bake_ms_sum"] = float(stats["bake_ms_sum"]) + ms
		var made: ImageTexture = ImageTexture.create_from_image(img)
		_by_content[ck] = made
		_save_png(img, ck)
		_finish(rk, made)
		await get_tree().process_frame  # one bake per frame
	_running = false
	idle.emit()


func _finish(rk: String, tex: Texture2D) -> void:
	_tex[rk] = tex
	var tags: Array = _wanted.get(rk, []) as Array
	_wanted.erase(rk)
	for tag: Variant in tags:
		icon_ready.emit(tag as StringName)


func _note_hit(us: int) -> void:
	stats["hits"] = int(stats["hits"]) + 1
	stats["hit_us_last"] = us
	stats["hit_us_max"] = maxi(int(stats["hit_us_max"]), us)
	stats["hit_us_sum"] = int(stats["hit_us_sum"]) + us


## [look hash, accent colour] of a style: the material parameters that are not baked into the mesh.
func _look_of(style_id: StringName) -> Array:
	var c: Array = _style_cache.get(style_id, []) as Array
	if not c.is_empty():
		return c
	var st: Dictionary = _book.style(style_id) if _book != null else {}
	var pal: Dictionary = st.get("palette", {}) as Dictionary
	var acc: Color = Color(str(pal.get("acc", "#e0b020")))
	var mat: Dictionary = st.get("material", {}) as Dictionary
	var h: int = ViewModelBuilder.fnv1a32(JSON.stringify(mat, "", true) + str(acc.to_html()))
	c = [h, acc]
	_style_cache[style_id] = c
	return c


# ---- disk cache ---------------------------------------------------------------------------------------------------------

func _load_png(ck: String) -> Texture2D:
	if not use_disk:
		return null
	var path: String = cache_path(ck)
	if not FileAccess.file_exists(path):
		return null
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _save_png(img: Image, ck: String) -> void:
	if not use_disk:
		return
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var path: String = cache_path(ck)
	var copy: Image = img.duplicate() as Image
	_tasks.append(WorkerThreadPool.add_task(func() -> void: copy.save_png(path), false, "ViewIconBake save"))
	stats["saved"] = int(stats["saved"]) + 1
	if _tasks.size() > 24:
		flush()


# ---- studio -------------------------------------------------------------------------------------------------------------

func _ensure_studio() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "IconStudio"
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.mesh_lod_threshold = 0.0
	_vp.size = SIZES[0]
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.positional_shadow_atlas_size = 0
	add_child(_vp)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 1.25
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.05
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = FOV_DEG
	_cam.near = 0.2
	_cam.far = 400.0
	_cam.environment = env
	_cam.cull_mask = ViewLayers.MASK_ICON_STUDIO
	_vp.add_child(_cam)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	key.light_energy = 2.3
	key.light_color = Color(1.0, 0.96, 0.9)
	key.light_cull_mask = ViewLayers.MASK_ICON_STUDIO
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 120.0
	key.shadow_bias = 0.04
	key.shadow_normal_bias = 1.2
	_vp.add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-24.0, 142.0, 0.0)
	fill.light_energy = 0.9
	fill.light_color = Color(0.72, 0.8, 1.0)
	fill.light_cull_mask = ViewLayers.MASK_ICON_STUDIO
	_vp.add_child(fill)
	_rig = MeshInstance3D.new()
	_rig.name = "Rig"
	_rig.layers = ViewLayers.MASK_ICON_STUDIO
	_rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_vp.add_child(_rig)
	_blob = _make_blob()
	_vp.add_child(_blob)


## A soft dark ellipse under the model so the icon reads as standing on something.
func _make_blob() -> MeshInstance3D:
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	var sh: Shader = Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;\n" \
		+ "void fragment() { float r = length(UV * 2.0 - 1.0); float a = (1.0 - smoothstep(0.35, 1.0, r)); ALBEDO = vec3(0.0); ALPHA = a * a * 0.5; }\n"
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Blob"
	mi.mesh = qm
	mi.material_override = m
	mi.layers = ViewLayers.MASK_ICON_STUDIO
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _material_for(style_id: StringName, accent: Color) -> ShaderMaterial:
	var m: ShaderMaterial = _mat_of.get(style_id) as ShaderMaterial
	if m == null:
		m = _mats.new_entity_material(style_id, 0)
		m.set_shader_parameter(ViewMaterials.P_TEAM, accent)
		_mat_of[style_id] = m
	return m


## A finished icon has transparent corners and a solid body; a half-rendered first frame (uninitialised target) has neither.
static func image_ok(img: Image) -> bool:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 8 or h < 8:
		return false
	for c: Vector2i in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		if img.get_pixelv(c).a > 0.02:
			return false
	var solid: int = 0
	var step: int = 2
	for y: int in range(0, h, step):
		for x: int in range(0, w, step):
			if img.get_pixel(x, y).a > 0.5:
				solid += 1
	return solid * step * step > w * h / 60


## Renders one model; null when the studio cannot draw (no renderer). `waits` = frames to wait for the draw.
func _bake(model: ViewModel, style_id: StringName, size: Vector2i, accent: Color, waits: int = 2, reserve: float = 0.0) -> Image:
	if not is_inside_tree():
		return null
	if _vp == null:
		_ensure_studio()
		# the first render into a fresh target can come back half-written: burn it on an empty studio
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		for _i: int in 3:
			await RenderingServer.frame_post_draw
	_vp.size = size
	_rig.mesh = model.mesh
	_rig.material_override = _material_for(style_id, accent)
	_rig.rotation = Vector3(0.0, deg_to_rad(YAW_DEG), 0.0)
	var box: AABB = model.info.rest_aabb
	if box.size.length() < 0.01:
		box = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 1.5, 2.0))
	var pose: Dictionary = frame_camera(box, YAW_DEG, PITCH_DEG, FOV_DEG, float(size.x) / float(size.y), MARGIN, reserve)
	_cam.global_transform = Transform3D(pose["basis"] as Basis, pose["pos"] as Vector3)
	# ground blob under the rotated footprint
	var rot: Basis = Basis(Vector3.UP, deg_to_rad(YAW_DEG))
	var ext: Vector3 = box.size
	var rr: float = maxf(Vector2(ext.x, ext.z).length() * 0.5, 0.6)
	var c: Vector3 = rot * box.get_center()
	_blob.global_transform = Transform3D(Basis().scaled(Vector3(rr * 1.05, 1.0, rr * 0.8)), Vector3(c.x, box.position.y + 0.02, c.z))
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	for _w: int in waits:
		await RenderingServer.frame_post_draw
	var img: Image = _vp.get_texture().get_image()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if img == null or img.is_empty():
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.fix_alpha_edges()
	return img
