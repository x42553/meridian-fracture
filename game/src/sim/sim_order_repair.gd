class_name SimOrderRepair
extends SimOrderHandler
## T_REPAIR (economy 3.7 / 5.10 / 5.11): a repairer unit walks to its profile range of a friendly vehicle / structure,
## takes the unit claim on the target and pays for the repair every tick through SimEconomyWork.repair_step.
## Phases: 1 = APPROACH, 2 = CLAIM, 3 = REPAIRING. `o.p0` = tick the claim wait began. DONE at full health.

const APPROACH: int = 1
const CLAIM: int = 2
const REPAIRING: int = 3


func _init() -> void:
	requires_target = true


func can_issue(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var rsn: int = SimEconomyWork.repair_can_target(world, e, world.get_entity(o.target_id))
	return SimCommand.Err.OK if rsn == SimEconConst.RSN_OK else SimEconomySystem.err_of(rsn)


## The unit's working range: the ability radius, at least the 1.5-cell engineer reach.
static func reach_of(world: SimWorld, e: SimEntity) -> int:
	var a: DefAbility = SimEconomyWork.repair_ability(world, e)
	return maxi(int(a.params.get("radius_u", 0)) if a != null else 0, SimEconomyWork.REACH_U)


func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var rsn: int = SimEconomyWork.repair_can_target(world, e, world.get_entity(o.target_id))
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
	if t.hp >= t.hp_max:
		return SimOrder.DONE
	var reach: int = reach_of(world, e)
	if o.phase == APPROACH:
		var r: int = SimEconomyWork.approach_step(world, e, t, o, reach)
		if r < 0:
			return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_BAD_TARGET)
		if r == 0:
			return SimOrder.RUNNING
		o.phase = CLAIM
		o.p0 = maxi(world.tick, 1)
	if o.phase == CLAIM:
		var ec: SimCompEcon = SimEconomyWork.ensure_econ(t)
		if not SimEconomyWork.claimed_by_other(world, ec, e.id):
			SimEconomyWork.claim(world, ec, e.id)
			o.phase = REPAIRING
		elif world.tick - o.p0 >= SimEconomyWork.CLAIM_WAIT_TICKS:
			return SimEconomyWork.fail(world, e, o, SimEconConst.RSN_BUSY)
		else:
			return SimOrder.RUNNING
	if not SimEconomyWork.in_reach(world, e, t, reach + SimEconomyWork.REACH_SLACK_U):
		SimEconomyWork.release_claim(t.econ, e.id)
		o.phase = APPROACH
		o.t0 = 0
		return SimOrder.RUNNING
	var ec2: SimCompEcon = SimEconomyWork.ensure_econ(t)
	if SimEconomyWork.claimed_by_other(world, ec2, e.id):
		o.phase = CLAIM
		o.p0 = maxi(world.tick, 1)
		return SimOrder.RUNNING
	SimEconomyWork.claim(world, ec2, e.id)
	var a: DefAbility = SimEconomyWork.repair_ability(world, e)
	var rc: int = SimEconomyWork.repair_category(a) if a != null else SimEconConst.RC_ENGINEER
	var h: int = SimEconomyWork.repair_step(world, e, t, rc, SimEconConst.RS_UNIT)
	if h < 0 and world.tick % SimEconomyWork.REPAIR_FUNDS_PERIOD == 0:
		world.emit(SimEconConst.EVT_INSUFFICIENT_FUNDS, e.x, e.y, e.owner, e.id, 0)
	if t.hp >= t.hp_max:
		return SimOrder.DONE
	return SimOrder.RUNNING


func on_end(world: SimWorld, e: SimEntity, o: SimOrder, _reason: int) -> void:
	var t: SimEntity = world.get_entity(o.target_id)
	if t != null:
		SimEconomyWork.release_claim(t.econ, e.id)
	if (e.flags & SimFlags.F_GONE) == 0:
		SimMovement.stop(world, e)
