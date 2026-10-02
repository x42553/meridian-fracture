class_name AppMatchJob
extends RefCounted
## Time-sliced match construction (ui.md 5.3, net.md `NetWorldJob` shape): `step(budget_us)` is polled once per frame by the
## session while it is LOADING and never blocks. Phases and progress bands:
##   MAP   0-45 %   `MapGenJob` on its worker thread (progress from the generator)
##   WORLD 45-50 %  `SimMatchSetup.create_world` (footprints, players, start HQs)
##   VIEW  50-99 %  `AppViewStage.build_async` (terrain, camera, models, atmosphere, water, decor, minimap); skipped with
##                  `with_view = false` (headless runs: no renderer, `frame_post_draw` never fires)
## The finished job hands over `take_world()` (and `take_stage()`); `error()` is "" on success. The same config with and
## without a view yields the same world (the view never touches the sim).

enum Phase { MAP = 0, WORLD = 1, VIEW = 2, DONE = 3, FAILED = 4 }

const VIEW_FROM_CONFIG: int = -2
const PHASE_NAMES: PackedStringArray = ["Generating terrain", "Building the world", "Preparing the battlefield", "Ready", "Failed"]

var config: Dictionary = {}
var with_view: bool = true
var data: GameData = null
## Where the view stage is parented for the build (`AppScenes.backdrop_host()`); needed when `with_view`.
var stage_parent: Node = null
var phase: int = Phase.MAP
## Set by the finished MAP phase (also useful to the lobby preview).
var map: MapData = null
var world: SimWorld = null
var stage: AppViewStage = null
## Sim-world options (`SimWorld.create` opts).
var world_opts: Dictionary = {}
## The viewer the stage is built for: VIEW_FROM_CONFIG = the first human slot, -1 = observer (replays), else a pid.
var view_pid: int = VIEW_FROM_CONFIG

var _err: String = ""
var _map_job: MapGenJob = null
var _view_frac: float = 0.0
var _view_label: String = ""
var _shown: int = 0
var _view_started: bool = false
var _t0_us: int = 0
var _timings: Dictionary = {}


func _init(p_config: Dictionary = {}, p_with_view: bool = true, p_data: GameData = null, p_stage_parent: Node = null) -> void:
	config = p_config
	with_view = p_with_view
	data = p_data
	stage_parent = p_stage_parent


## Advances the build for at most about `budget_us` microseconds of main-thread work; true when finished (check `error()`).
func step(budget_us: int) -> bool:
	if phase >= Phase.DONE:
		return true
	if _t0_us == 0:
		_t0_us = Time.get_ticks_usec()
	match phase:
		Phase.MAP:
			_step_map(budget_us)
		Phase.WORLD:
			_step_world()
		Phase.VIEW:
			_step_view()
	_shown = maxi(_shown, _compute_pct())
	return phase >= Phase.DONE


func _step_map(budget_us: int) -> void:
	if _map_job == null:
		var mcfg: Variant = config.get("map", null)
		if not (mcfg is Dictionary):
			_fail("match config has no map")
			return
		var problem: String = MapGenerator.validate_params(int((mcfg as Dictionary).get("family", 0)),
			int((mcfg as Dictionary).get("size", 128)), int((mcfg as Dictionary).get("layout_players", 2)))
		if problem != "":
			_fail("map parameters: " + problem)
			return
		_map_job = MapGenJob.begin(mcfg as Dictionary, null, true)
	if _map_job.step(budget_us):
		map = _map_job.result()
		_timings["map_ms"] = (Time.get_ticks_usec() - _t0_us) / 1000
		if map == null:
			_fail("map generation failed")
			return
		phase = Phase.WORLD


func _step_world() -> void:
	var t0: int = Time.get_ticks_usec()
	if data == null:
		data = GameData.load_default()
	if data == null:
		_fail("game data could not be loaded")
		return
	var cfg: SimMatchConfig = SimMatchConfig.from_dict(config)
	world = SimMatchSetup.create_world(data, cfg, map, world_opts)
	_timings["world_ms"] = (Time.get_ticks_usec() - t0) / 1000
	if world == null:
		_fail("the simulation rejected the match configuration")
		return
	phase = Phase.VIEW if with_view else Phase.DONE


func _step_view() -> void:
	if not _view_started:
		_view_started = true
		if stage_parent == null or not stage_parent.is_inside_tree():
			_fail("no scene tree to build the view in")
			return
		stage = AppViewStage.new()
		stage.name = "MatchStage"
		stage.build_progress.connect(func(f: float, s: String) -> void:
			_view_frac = f
			_view_label = s)
		stage_parent.add_child(stage)
		@warning_ignore("missing_await")
		stage.build_async(world, local_pid() if view_pid == VIEW_FROM_CONFIG else view_pid, AppViewStage.make_quality())
		return
	if stage != null and stage.built:
		_timings["total_ms"] = (Time.get_ticks_usec() - _t0_us) / 1000
		phase = Phase.DONE


func _fail(message: String) -> void:
	_err = message
	phase = Phase.FAILED
	Log.error("app", "match job: " + message)


func _compute_pct() -> int:
	match phase:
		Phase.MAP:
			return int(0.45 * float(_map_job.progress_pct())) if _map_job != null else 0
		Phase.WORLD:
			return 45
		Phase.VIEW:
			return 50 + int(49.0 * clampf(_view_frac, 0.0, 1.0))
		Phase.DONE:
			return 100
	return _shown


## 0..100, monotonic.
func progress_pct() -> int:
	return _shown


func error() -> String:
	return _err


func phase_name() -> String:
	if phase == Phase.VIEW and _view_label != "":
		return PHASE_NAMES[Phase.VIEW]
	return PHASE_NAMES[clampi(phase, 0, PHASE_NAMES.size() - 1)]


## Stage label of the VIEW phase ("terrain", "models", ...), "" otherwise.
func view_stage() -> String:
	return _view_label


func timings() -> Dictionary:
	return _timings.duplicate()


## The finished world (ownership moves to the caller).
func take_world() -> SimWorld:
	var w: SimWorld = world
	return w


func take_stage() -> AppViewStage:
	return stage


## `local_pid`: the first human slot of the config, -1 (observer) when there is none.
func local_pid() -> int:
	for p: Variant in config.get("players", []) as Array:
		if p is Dictionary and (p as Dictionary).get("kind", "human") == "human":
			return int((p as Dictionary).get("pid", 0))
	return -1


func cancel() -> void:
	if _map_job != null and phase == Phase.MAP:
		_map_job.cancel()
	phase = Phase.FAILED
	_err = "cancelled"
	if stage != null and is_instance_valid(stage):
		if stage.built:
			stage.queue_free()
		else:
			# a build coroutine is suspended inside the stage: freeing it now would resume into a dead instance, so it is
			# hidden and freed by its own final progress signal
			stage.visible = false
			var doomed: AppViewStage = stage
			doomed.build_progress.connect(func(f: float, _s: String) -> void:
				if f >= 1.0 and is_instance_valid(doomed):
					doomed.queue_free())
	stage = null
