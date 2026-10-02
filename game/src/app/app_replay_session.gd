class_name AppReplaySession
extends RefCounted
## The playback engine of a replay inside the app (task REP2, ui.md 5.16.3): owns a `NetReplayPlayer`, builds its worlds through the
## same `AppMatchJob` path as a live match (the first one with the 3D stage, rebuilds after a backward seek without a view: the
## stage is re-bound to the new world), and exposes what the match context and the observer UI need. It plays no part in the
## simulation: it only feeds the recorded commands to a world of its own. Created by `AppReplay.start`.
##
## Signals: `ready` (first world built; `take_stage()` hands the stage over), `failed(text)`, `finished` (recorded end reached),
## `diverged(tick)` (a CHECK did not match: recorded on a different build), `world_rebuilt(world)` (backward seek finished
## building the new world: re-bind views and ports).

signal ready()
signal failed(text: String)
signal finished()
signal diverged(tick: int)
signal world_rebuilt(world: SimWorld)

const BUDGET_PACED_US: int = 6000
const BUDGET_SEEK_US: int = 14000

var player: NetReplayPlayer = NetReplayPlayer.new()
var data: NetReplayData = null
var path: String = ""
var error_text: String = ""
## Build the 3D stage with the first world (false in headless runs and tests).
var with_view: bool = true
## The world records sim events for the view / UI (headless proofs turn it off).
var events: bool = true
## Called with every world job (the loading screen reads the progress of the current one).
var job_sink: Callable = Callable()
var is_ready: bool = false
var is_failed: bool = false

var _builds: int = 0
var _first_job: AppMatchJob = null
var _job: AppMatchJob = null
var _stage: AppViewStage = null
var _end_reported: bool = false
var _marks: Array[Dictionary] = []


## Validates the replay (version gate) and starts building the world (time-sliced: `frame()` advances it). OK or an error code;
## `error_text` says why.
func begin(p_data: NetReplayData, p_path: String = "", opts: Dictionary = {}) -> int:
	data = p_data
	path = p_path
	with_view = bool(opts.get("with_view", true))
	events = bool(opts.get("events", with_view))
	job_sink = opts.get("job_sink", Callable()) as Callable
	player.local_versions = opts.get("local_versions", AppReplay.local_versions()) as Dictionary
	player.strict = bool(opts.get("strict", false))
	player.allow_version_mismatch = bool(opts.get("allow_mismatch", false))
	player.auto_clear_events = not events
	player.world_rebuilt.connect(_on_rebuilt)
	player.finished.connect(_on_finished)
	player.verify_failed.connect(_on_verify_failed)
	var err: int = player.setup(data, Callable(self, "_world_job"), NetClock.real(), false)
	if err != OK:
		error_text = player.error_text
		is_failed = true
		return err
	return OK


func _world_job(cfg: Dictionary) -> NetWorldJob:
	var first: bool = _builds == 0
	_builds += 1
	var job: AppMatchJob = AppMatch.begin_build(cfg, with_view and first)
	job.view_pid = -1
	_job = job
	if first:
		_first_job = job
	if job_sink.is_valid():
		job_sink.call(job)
	return AppNetWorldJob.new(job, events)


## The current world job (loading progress), null once nothing is building.
func job() -> AppMatchJob:
	return _job


## The stage of the first build (ownership moves to the caller; null headless or when taken already).
func take_stage() -> AppViewStage:
	var s: AppViewStage = _stage if _stage != null else (_first_job.take_stage() if _first_job != null else null)
	_stage = null
	return s


## Once per rendered frame: advances the build, then the playback. Returns the sim ticks executed.
func frame() -> int:
	if is_failed:
		return 0
	var before: int = player.current_tick()
	player.poll(BUDGET_SEEK_US if (player.is_seeking() or player.speed() <= 0.0) else BUDGET_PACED_US)
	if player.is_loading():
		return 0
	if not is_ready:
		if player.adapter() == null:
			is_failed = true
			error_text = player.error_text if player.error_text != "" else "the replay could not be built"
			failed.emit(error_text)
			return 0
		is_ready = true
		ready.emit()
	return maxi(player.current_tick() - before, 0)


## The current world (during a backward seek the old one stays readable and frozen until the new one is built).
func world() -> SimWorld:
	var a: NetSimAdapter = player.adapter()
	return a.world() as SimWorld if a != null else null


func tick() -> int:
	return player.current_tick()


func end_tick() -> int:
	return player.end_tick()


func tick_alpha() -> float:
	return player.tick_alpha()


# ---- control (the replay bar) -----------------------------------------------------------------------------------------

func set_paused(p: bool) -> void:
	player.set_paused(p)


func toggle_pause() -> void:
	if player.is_finished() and player.current_tick() >= player.end_tick():
		seek(0)
		player.set_paused(false)
		return
	player.set_paused(not player.is_paused())


func is_paused() -> bool:
	return player.is_paused()


func set_speed(multiplier: float) -> void:
	player.set_speed(multiplier)


func speed() -> float:
	return player.speed()


func seek(target_tick: int) -> void:
	if target_tick < player.end_tick():
		_end_reported = false
	player.seek_tick(target_tick)


func seek_by_seconds(delta_s: int) -> void:
	player.seek_tick(player.current_tick() + delta_s * (1000 / SimConfig.TICK_MS))


func is_seeking() -> bool:
	return player.is_seeking()


func is_finished() -> bool:
	return player.is_finished()


func verified_through() -> int:
	return player.verified_through_tick()


func diverged_tick() -> int:
	return player.diverged_tick()


## Tick marks of the seek bar: every 600 ticks (30 s).
static func checkpoints(end_tick_value: int, every: int = 600) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var t: int = every
	while t < end_tick_value and out.size() < 2000:
		out.append(t)
		t += every
	return out


## The events of the recording the user can jump to: `[{tick, kind: "defeated"|"resigned"|"left"|"chat", pid, text}]`, ascending.
func event_marks() -> Array[Dictionary]:
	if not _marks.is_empty() or data == null:
		return _marks
	_marks = AppReplay.event_marks(data)
	return _marks


func dispose() -> void:
	if _job != null and _job.phase < AppMatchJob.Phase.DONE:
		_job.cancel()
	_job = null
	_first_job = null
	if is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	if player != null:
		for sig: Dictionary in player.get_signal_list():
			for conn: Dictionary in player.get_signal_connection_list(String(sig["name"])):
				(conn["signal"] as Signal).disconnect(conn["callable"] as Callable)


func _on_rebuilt() -> void:
	world_rebuilt.emit(world())


func _on_verify_failed(tick: int, _expected: int, _actual: int) -> void:
	diverged.emit(tick)


func _on_finished() -> void:
	if _end_reported:
		return
	_end_reported = true
	finished.emit()
