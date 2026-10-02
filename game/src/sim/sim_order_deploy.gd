class_name SimOrderDeploy
extends SimOrderHandler
## T_DEPLOY_MCV (35; economy 3.7 / 5.3): the MCV unfolds into its HQ. This is the one handler of the order (INT1's
## executor, extended by EC3A; there is no second SimOrderDeployMcv). Without a cell it deploys where it stands; with
## a cell (`o.arg == 1`, x / y in sub-cell units) it first drives to the cell centre (phase 1 = MOVE) and deploys within
## half a cell of it or when the movement gives up (phase 2 = DEPLOY). The HQ site is validated when the order runs
## (SimPlacement.validate_hq_site: rules 1 and 3-9, footprint centred on the MCV's cell); a blocked site fails the
## order with BAD_SITE and EVT_ORDER_FAILED carries the RSN_*.

const MOVE: int = 1
const DEPLOY: int = 2
const ARRIVE_U: int = 512  ## half a cell
const MOVE_TIMEOUT: int = 1200  ## ticks


func can_issue(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	if SimPlacement.hq_def_of_mcv(world, e.def_idx) < 0:
		return SimCommand.Err.WRONG_KIND
	if o.arg == 1 and (o.x < 0 or o.y < 0 or o.x >= world.map.w * SimConfig.CELL or o.y >= world.map.h * SimConfig.CELL):
		return SimCommand.Err.BAD_FIELD
	return SimCommand.Err.OK


func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	if o.arg == 1:
		o.phase = MOVE
		o.t0 = world.tick
		if not SimMovement.request_move(world, e, o.x, o.y):
			o.fail = SimCommand.Err.BLOCKED
			return SimOrder.FAILED
		return SimOrder.RUNNING
	o.phase = DEPLOY
	SimMovement.stop(world, e)
	return SimOrder.RUNNING


func on_update(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	if o.phase == MOVE:
		var dx: int = e.x - o.x
		var dy: int = e.y - o.y
		var arrived: bool = dx * dx + dy * dy <= ARRIVE_U * ARRIVE_U
		if not arrived:
			if SimMovement.path_failed(e) or world.tick - o.t0 > MOVE_TIMEOUT:
				o.fail = SimCommand.Err.BLOCKED
				return SimOrder.FAILED
			if SimMovement.at_goal(e):
				arrived = true  # as close as the movement gets
			else:
				return SimOrder.RUNNING
		SimMovement.stop(world, e)
		o.phase = DEPLOY
	if world.economy.life.deploy_mcv(world, e) > 0:
		return SimOrder.DONE
	o.fail = SimCommand.Err.BAD_SITE
	return SimOrder.FAILED


func on_end(world: SimWorld, e: SimEntity, _o: SimOrder, reason: int) -> void:
	if reason != SimOrder.END_DONE and (e.flags & SimFlags.F_GONE) == 0:
		SimMovement.stop(world, e)
