class_name SimOrderAir
extends SimOrderHandler
## T_LAND (terrain_movement 6.2): x, y = touchdown point, arg = approach heading (< 0 = straight in). DONE when the
## aircraft has touched down (SimMovement.air_at_goal). Exists so the AI / QA can land aircraft without combat's sortie
## state machine; a cancelled approach ends in a hold (hover / orbit).


func can_issue(_world: SimWorld, e: SimEntity, _o: SimOrder) -> int:
	if not SimAirMove.is_air(e.move):
		return SimCommand.Err.NOT_ALLOWED
	return SimCommand.Err.OK


func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	o.t0 = world.tick
	var mv: SimCompMove = e.move
	if e.layer != SimEntity.Layer.AIR and mv.air_mode != SimMoveConfig.AM_LANDING:
		o.fail = SimCommand.Err.NOT_ALLOWED  # grounded aircraft cannot land
		world.emit(SimMoveConfig.EV_MOVE_FAILED, e.x, e.y, e.id, SimMoveConfig.RS_NO_MOVE, o.type)
		return SimOrder.FAILED
	SimAirMove.land_at(world, e, o.x, o.y, o.arg)
	return SimOrder.RUNNING


func on_update(_world: SimWorld, e: SimEntity, _o: SimOrder) -> int:
	if SimAirMove.at_goal(e) or e.move.air_mode == SimMoveConfig.AM_PARKED:
		return SimOrder.DONE
	return SimOrder.RUNNING


func on_end(world: SimWorld, e: SimEntity, _o: SimOrder, reason: int) -> void:
	if e.move != null and (reason == SimOrder.END_CANCELLED or reason == SimOrder.END_REPLACED) and e.move.air_mode == SimMoveConfig.AM_APPROACH:
		SimAirMove.hover(world, e)
