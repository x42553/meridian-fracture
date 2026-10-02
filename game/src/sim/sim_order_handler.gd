class_name SimOrderHandler
extends RefCounted
## Base of every order handler (sim_core 3.6). Handlers are STATELESS and deterministic: ONE instance per order
## type, all state lives in the SimOrder (`phase, t0, p0, p1`) or in components (both hashed). The defaults accept
## everything and finish at once.

## If true and `order.target_id != 0` no longer resolves to an alive entity, the dispatcher calls
## on_target_lost() instead of on_update().
var requires_target: bool = false


## SimCommand.Err.OK to accept (pure validation, no side effects).
func can_issue(_world: SimWorld, _e: SimEntity, _o: SimOrder) -> int:
	return SimCommand.Err.OK


## First time the order becomes the head (phase 0 -> 1). Returns SimOrder.RUNNING / DONE / FAILED.
func on_begin(_world: SimWorld, _e: SimEntity, _o: SimOrder) -> int:
	return SimOrder.RUNNING


## Every tick while the order is the head. RUNNING / DONE / FAILED; set `o.fail` (a SimCommand.Err) before FAILED.
func on_update(_world: SimWorld, _e: SimEntity, _o: SimOrder) -> int:
	return SimOrder.DONE


## Exactly once for every order whose on_begin ran, when it leaves the queue: SimOrder.END_DONE / FAILED /
## CANCELLED (stop) / REPLACED / DIED (unit removed). Release reservations here.
func on_end(_world: SimWorld, _e: SimEntity, _o: SimOrder, _reason: int) -> void:
	pass


## The order's target no longer exists. Default: FAILED.
func on_target_lost(_world: SimWorld, _e: SimEntity, o: SimOrder) -> int:
	o.fail = SimCommand.Err.NO_TARGET
	return SimOrder.FAILED


## Only for handlers registered with SimOrderSystem.register_idle: called for a unit with an empty queue.
func on_idle(_world: SimWorld, _e: SimEntity) -> void:
	pass
