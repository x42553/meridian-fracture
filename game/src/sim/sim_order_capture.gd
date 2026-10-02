class_name SimOrderCapture
extends SimOrderHandler
## T_CAPTURE (economy 3.7 / 5.13): an Engineer walks to within 1.5 cells of a neutral tech structure's footprint edge and
## channels (SimEconomyWork.capture_channel) until the stage-3 evaluation flips the owner. Engineers are not consumed.
## Phases (SimOrder.phase): 1 = APPROACH, 2 = CHANNEL. No state outside the order: the channel count and the progress
## live on the target's SimCompEcon.

const APPROACH: int = 1
const CHANNEL: int = 2


func _init() -> void:
	requires_target = true


func can_issue(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var rsn: int = SimEconomyWork.capture_can_target(world, e, world.get_entity(o.target_id))
	return SimCommand.Err.OK if rsn == SimEconConst.RSN_OK else SimEconomySystem.err_of(rsn)


func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var rsn: int = SimEconomyWork.capture_can_target(world, e, world.get_entity(o.target_id))
	if rsn != SimEconConst.RSN_OK:
		return SimEconomyWork.fail(world, e, o, rsn)
	o.phase = APPROACH
	o.t0 = 0
	o.p0 = 0
	o.p1 = 0
	return SimOrder.RUNNING


func on_update(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var t: SimEntity = world.get_entity(o.target_id)
	if t == null or (t.flags & SimFlags.F_GONE) != 0:
		return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_BAD_TARGET)
	if e.owner >= 0 and t.owner >= 0 and world.team_of(e.owner) == world.team_of(t.owner):
		return SimOrder.DONE  # captured (by us or an ally)
	if o.phase == APPROACH:
		var r: int = SimEconomyWork.approach_step(world, e, t, o, SimEconomyWork.REACH_U)
		if r < 0:
			return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_BAD_TARGET)
		if r == 0:
			return SimOrder.RUNNING
		o.phase = CHANNEL
	if not SimEconomyWork.in_reach(world, e, t, SimEconomyWork.REACH_U + SimEconomyWork.REACH_SLACK_U):
		o.phase = APPROACH
		o.t0 = 0
		return SimOrder.RUNNING
	SimEconomyWork.capture_channel(e, t)
	return SimOrder.RUNNING


func on_end(world: SimWorld, e: SimEntity, _o: SimOrder, _reason: int) -> void:
	if (e.flags & SimFlags.F_GONE) == 0:
		SimMovement.stop(world, e)
