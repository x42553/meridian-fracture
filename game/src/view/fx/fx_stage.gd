class_name FxStage
extends Node3D
## The composed FX layer of a match (VIEW-F1 + F3 + F4 + W3 in one node): FxManager (batches, budgets), the shipped fx.json
## FxRecipeBook, the ground-mark layer (ViewScorchLayer), FxEventRouter (kernel events -> effects) and ViewProjectiles (projectile
## mirror). One call wires everything to a ViewWorld:
##
##   var stage: FxStage = FxStage.attach(view_world)          # once, after ViewWorld.build_*; needs view.terrain / view.camera
##   ...                                                       # events flow through view.router.extra_handler by themselves
##   stage.fx.paused = paused                                  # optional: freeze the FX clock with the game
##   stage.detach()                                            # before ViewWorld.teardown()
##
## The stage advances the FX clock (FxManager._process), the router upkeep and the projectile mirror by itself (`_process`), and feeds
## the camera-focus distance and the camera shake. Presentation only.

var fx: FxManager = null
var book: FxRecipeBook = null
var router: FxEventRouter = null
var projectiles: ViewProjectiles = null
var scorch: ViewScorchLayer = null
var view: ViewWorld = null
var stat_frame_us: int = 0
var stat_frames: int = 0

var _prewarm_left: int = 0


## Builds the stage as a child of `world` (identity transform, like the manager requires) and hooks the event router.
static func attach(world: ViewWorld, q: ViewQuality = null) -> FxStage:
	ViewGlobals.ensure()
	var st: FxStage = FxStage.new()
	st.name = "FxStage"
	world.add_child(st)
	st._build(world, q if q != null else world.quality)
	return st


func _build(world: ViewWorld, q: ViewQuality) -> void:
	view = world
	book = FxRecipeBook.new()
	if not book.load_file():
		Log.error("view.fx", "fx.json: %s" % "; ".join(book.errors()))
	if world.terrain != null:
		var res: int = q.get_int(&"scorch_res") if q != null else 1024
		scorch = ViewScorchLayer.new()
		scorch.setup(world.terrain.world_size(), res)
		world.terrain.set_scorch_texture(scorch.texture)
	fx = FxManager.new()
	fx.name = "Fx"
	add_child(fx)
	var cam: Camera3D = world.camera.camera if world.camera != null else null
	var quality: FxManager.Quality = FxManager.Quality.HIGH
	if q != null:
		quality = clampi(q.fx_quality(), 0, 3) as FxManager.Quality
	fx.setup(cam, quality, book, world.terrain, scorch)
	if q != null:
		fx.set_distort(q.get_bool(&"fx_distort") and fx.distort_enabled())
	if world.camera != null:
		fx.camera_shake.connect(_on_shake)
	projectiles = ViewProjectiles.new()
	router = FxEventRouter.new()
	router.setup(world, fx, null)
	projectiles.setup(world, fx, router.catalog)
	router.projectiles = projectiles
	router.attach(world)


## Trauma ceilings by impact size: a big battle fires hundreds of tier 1-3 impacts, which with plain addition pinned the camera trauma at 1.0 for the whole
## fight (measured, VQ2B: mean 0.94). Small impacts now only lift the trauma to AMBIENT_CAP (a faint tremor), medium ones to MEDIUM_CAP, and only
## tier 5 / superweapon shakes (>= BIG_AMOUNT) can reach full trauma, which then decays within a second.
const AMBIENT_CAP: float = 0.28
const MEDIUM_CAP: float = 0.55
const MEDIUM_AMOUNT: float = 0.3
const BIG_AMOUNT: float = 0.7


func _on_shake(amount: float, _pos: Vector3) -> void:
	if view == null or view.camera == null:
		return
	if view.quality != null:
		amount *= view.quality.shake_scale()  # accessibility: reduce_motion x0.2, reduce_flash silences the shake
		if amount <= 0.0:
			return
	view.camera.add_shake(shake_increment(amount, view.camera.trauma()))


## The part of a shake of `amount` that is added to a camera at `trauma` (the ceilings above).
static func shake_increment(amount: float, trauma: float) -> float:
	var cap: float = 1.0 if amount >= BIG_AMOUNT else (MEDIUM_CAP if amount >= MEDIUM_AMOUNT else AMBIENT_CAP)
	return minf(amount, maxf(cap - trauma, 0.0))


## Registers the effect ids that the router owns in a ViewFxPort, so state views that emit the same ids do not spawn them twice.
func bind_port(port: ViewFxPort) -> void:
	port.bind(fx)
	for id: StringName in [&"building_collapse", &"damage_smoke", &"damage_fire", &"wreck_start", &"wreck_smoke"]:
		port.suppressed[id] = true
	router.port = port


## Spawns every registered effect once in front of the camera (pipelines compile behind the loading screen); call `finish_prewarm`
## a few frames later (or let `_process` do it: `prewarm(frames)`).
func prewarm(frames: int = 8) -> void:
	fx.prewarm()
	_prewarm_left = frames


func finish_prewarm() -> void:
	fx.clear_all()
	if scorch != null:
		scorch.setup(view.terrain.world_size(), scorch.texture.get_width())
		view.terrain.set_scorch_texture(scorch.texture)


func _process(dt: float) -> void:
	if fx == null or router == null or router.v == null:
		return  # not built yet, or detached (the node is freed at the end of the frame)
	var t0: int = Time.get_ticks_usec()
	if view.camera != null and view.camera.camera != null and view.camera.camera.is_inside_tree():
		fx.camera_focus_dist = view.camera.camera.global_position.distance_to(view.camera.current_focus())
	router.frame(dt)
	if _prewarm_left > 0:
		_prewarm_left -= 1
		if _prewarm_left == 0:
			finish_prewarm()
	stat_frame_us += Time.get_ticks_usec() - t0
	stat_frames += 1


## Live quality switch (ViewQuality): FX preset, refraction and the projectile-mesh cap.
func apply_quality(q: ViewQuality) -> void:
	if q == null or fx == null:
		return
	fx.set_quality(clampi(q.fx_quality(), 0, 3) as FxManager.Quality)
	fx.set_distort(q.get_bool(&"fx_distort"))
	if projectiles != null:
		projectiles.cap = maxi(q.get_int(&"proj_mesh_cap"), 8)


## Removes the router hook and frees the layer. Safe to call twice.
func detach() -> void:
	if view != null and view.router != null and router != null:
		router.detach(view)
	if projectiles != null:
		projectiles.teardown()
	if router != null:
		router.teardown()
	if fx != null:
		fx.clear_all()  # trackers / scheduled calls hold Callables bound to view entities: drop them so the world graph can be freed
	if is_inside_tree():
		queue_free()


func stats() -> Dictionary:
	return {"fx": fx.get_stats() if fx != null else {}, "router": router.stats.duplicate() if router != null else {},
		"script_us_avg": float(stat_frame_us) / maxf(float(stat_frames), 1.0), "meshes": projectiles.live_meshes() if projectiles != null else 0,
		"damage_emitters": router.ambient.active_count() if router != null else 0}
