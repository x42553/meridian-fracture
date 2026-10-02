class_name SimOrderSalvage
extends SimOrderHandler
## T_SALVAGE (economy 3.7 / 5.12): an African Empire salvager walks to within 1.5 cells of an enemy wreck and works for the
## ability's action time without interruption; then the wreck pays out `payout_bp` of the dead unit's paid cost once.
## Phases: 1 = APPROACH, 2 = WORK. `o.p0` = progress in ticks (0 until the claim is taken). Any order change, displacement
## beyond reach + 1 cell, death or lost claim resets the progress and frees the claim (on_end always releases it).

const APPROACH: int = 1
const WORK: int = 2


func _init() -> void:
	requires_target = true


func can_issue(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var rsn: int = SimEconomyWork.salvage_can_target(world, e, world.get_entity(o.target_id))
	return SimCommand.Err.OK if rsn == SimEconConst.RSN_OK else SimEconomySystem.err_of(rsn)


func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var rsn: int = SimEconomyWork.salvage_can_target(world, e, world.get_entity(o.target_id))
	if rsn != SimEconConst.RSN_OK:
		return SimEconomyWork.fail(world, e, o, rsn)
	o.phase = APPROACH
	o.t0 = 0
	o.p0 = 0
	o.p1 = 0
	return SimOrder.RUNNING


func on_update(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var w: SimEntity = world.get_entity(o.target_id)
	if w == null or (w.flags & SimFlags.F_GONE) != 0:
		return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_BAD_TARGET)
	var a: DefAbility = SimEconomyWork.salvage_ability(world, e)
	if a == null:
		return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_WRONG_KIND)
	if o.phase == APPROACH:
		var r: int = SimEconomyWork.approach_step(world, e, w, o, SimEconomyWork.REACH_U)
		if r < 0:
			return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_BAD_TARGET)
		if r == 0:
			return SimOrder.RUNNING
		var rsn: int = SimEconomyWork.salvage_can_target(world, e, w)
		if rsn != SimEconConst.RSN_OK:
			return SimEconomyWork.fail(world, e, o, rsn)
		if not SimEconomyWork.salvage_begin(world, e, w, SimEconomyWork.salvage_duration(world, e, a)):
			return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_BUSY)
		o.phase = WORK
		o.p0 = 0
	if not SimEconomyWork.in_reach(world, e, w, SimEconomyWork.REACH_U + SimEconomyWork.REACH_SLACK_U):
		_cancel(w, e)
		o.phase = APPROACH
		o.p0 = 0
		o.t0 = 0
		return SimOrder.RUNNING
	if SimEconomyWork.salvage_tick(world, e, w) == SimEconConst.SALV_FAILED:
		return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_BUSY)
	o.p0 += 1
	if o.p0 < SimEconomyWork.salvage_duration(world, e, a):
		return SimOrder.RUNNING
	if SimEconomyWork.salvage_finish(world, e, w, a) < 0:
		return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_BAD_TARGET)
	return SimOrder.DONE


func on_end(world: SimWorld, e: SimEntity, o: SimOrder, _reason: int) -> void:
	var w: SimEntity = world.get_entity(o.target_id)
	if w != null:
		_cancel(w, e)
	o.p0 = 0
	if (e.flags & SimFlags.F_GONE) == 0:
		SimMovement.stop(world, e)


static func _cancel(w: SimEntity, e: SimEntity) -> void:
	SimEconomyWork.release_claim(w.econ, e.id)
