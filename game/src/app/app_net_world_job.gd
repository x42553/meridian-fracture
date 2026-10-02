class_name AppNetWorldJob
extends NetWorldJob
## The `opts.world_builder` job of the app (net.md 3.3): a time-sliced `AppMatchJob` (map, world, view stage) that hands net a
## `NetSimAdapterWorld` when finished. The wrapped job stays reachable (`job`) for the loading screen and for the view hand-over
## (`take_stage`); net only sees the `NetWorldJob` surface.

var job: AppMatchJob = null
## Whether the finished world records sim events (the view and the notifier consume them; headless runs turn them off).
var events_enabled: bool = true


func _init(p_job: AppMatchJob = null, p_events: bool = true) -> void:
	job = p_job
	events_enabled = p_events


func step(budget_us: int) -> bool:
	return job.step(budget_us) if job != null else true


func progress_pct() -> int:
	return job.progress_pct() if job != null else 0


func error() -> String:
	return job.error() if job != null else "no world job"


func take_adapter() -> NetSimAdapter:
	if job == null:
		return null
	var w: SimWorld = job.take_world()
	if w == null:
		return null
	w.events.enabled = events_enabled
	return NetSimAdapterWorld.new(w)
