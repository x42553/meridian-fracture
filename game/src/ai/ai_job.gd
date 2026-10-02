class_name AiJob
extends RefCounted
## Base class of resumable, budgeted jobs (placement search, A*, superweapon target search; ai.md 3.5). A job is stepped
## by the module that owns it, `step(budget)` does at most budget-worth of work and sets `done` when finished.

var done: bool = false


func step(_budget: AiBudget) -> void:
	done = true


## Valid once done (for example a PackedInt32Array of waypoints).
func result() -> Variant:
	return null
