class_name SimOrderCargo
extends SimOrderHandler
## T_LOAD (50) / T_UNLOAD (51) / T_GARRISON (52): the cargo approach handlers of terrain_movement TM-14 / 5.8. The
## container rules (capacity, exclusions, team / claim, load_t / unload_t, exit cells) are SimTransport's; these handlers
## only walk units so its calls can be made.
##
## T_LOAD / T_GARRISON (passenger `e`, `target` = transport / building): FAILED unless SimTransport.can_board; approach
## to within 2 cells (garrison: 0.5 cell of the footprint edge), then SimTransport.board / garrison_enter -> DONE. A
## carrier that floats farther than 2 cells from any cell the passenger can reach ends the walk short: the order fails
## with BLOCKED (UI: "transport must be at the shore"). Timeout 600 ticks. The dispatcher skips units once F_INSIDE.
##
## T_UNLOAD (carrier `e`): arg bit0 = unload in place, bit1 = everybody (else `target_id` = the one passenger),
## x, y = drop point. begin: in place -> stop, else go_near(3 cells of the point). Once the carrier stands still (or
## carries Mobile Reserve) SimTransport.begin_unload runs; the order ends when the cargo is out (all) or the one
## passenger left. Timeout n_pax * unload_t + 100 ticks. A cancelled order cancels the unloading.

const LOAD_REACH_U: int = 2048
const GARRISON_REACH_U: int = 512
const REACH_SLACK_U: int = 256
const APPROACH_TIMEOUT: int = 600
const UNLOAD_NEAR_U: int = 3072
const UNLOAD_SLACK_T: int = 100

var order_type: int = SimOrder.T_LOAD


func _init(p_type: int = SimOrder.T_LOAD) -> void:
	order_type = p_type
	requires_target = p_type != SimOrder.T_UNLOAD


func can_issue(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	if order_type == SimOrder.T_UNLOAD:
		if e.cargo == null or e.cargo.n_pax == 0:
			return SimCommand.Err.NOT_ALLOWED
		return SimCommand.Err.OK
	var carrier: SimEntity = world.get_entity(o.target_id)
	if carrier == null or (carrier.flags & SimFlags.F_GONE) != 0:
		return SimCommand.Err.NO_TARGET
	if e.move == null or carrier.cargo == null:
		return SimCommand.Err.WRONG_KIND
	if (order_type == SimOrder.T_GARRISON) != SimTransport.is_garrison(carrier):
		return SimCommand.Err.WRONG_KIND
	var r: int = SimTransport.board_reject(world, carrier, e)
	if r == 0:
		return SimCommand.Err.OK
	return SimAbilityEvents.err_of(r)


func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	o.t0 = world.tick
	o.p1 = 0
	if order_type == SimOrder.T_UNLOAD:
		if world.movement != null and e.move != null:
			if (o.arg & 1) != 0:
				SimMovement.stop(world, e, false)
			else:
				SimMovement.go_near(world, e, o.x, o.y, UNLOAD_NEAR_U)
		return SimOrder.RUNNING
	var carrier: SimEntity = world.get_entity(o.target_id)
	if carrier == null:
		o.fail = SimCommand.Err.NO_TARGET
		return SimOrder.FAILED
	if not _in_reach(carrier, e):
		if world.movement != null:
			SimMovement.approach_entity(world, e, carrier.id, _reach())
		else:
			return _fail(o, SimCommand.Err.BLOCKED)
	return SimOrder.RUNNING


func on_update(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	if order_type == SimOrder.T_UNLOAD:
		return _update_unload(world, e, o)
	var carrier: SimEntity = world.get_entity(o.target_id)
	if carrier == null or (carrier.flags & SimFlags.F_GONE) != 0:
		return _fail(o, SimCommand.Err.NO_TARGET)
	if _in_reach(carrier, e):
		if world.movement != null:
			SimMovement.stop(world, e, false)
		var ok: bool
		if order_type == SimOrder.T_GARRISON:
			ok = SimTransport.garrison_enter(world, carrier, e)
		else:
			ok = SimTransport.board(world, carrier, e)
		return SimOrder.DONE if ok else _fail(o, SimCommand.Err.BLOCKED)
	if world.tick - o.t0 > APPROACH_TIMEOUT:
		return _fail(o, SimCommand.Err.NOT_ALLOWED)
	if world.movement != null and e.move != null:
		match e.move.state:
			SimMoveConfig.MS_NO_PATH:
				SimMovement.ack(world, e)
				return _fail(o, SimCommand.Err.BLOCKED)
			SimMoveConfig.MS_ARRIVED:
				SimMovement.ack(world, e)
				if not _in_reach(carrier, e):  # the walk ended short of the carrier (it floats too far out)
					return _fail(o, SimCommand.Err.BLOCKED)
			SimMoveConfig.MS_IDLE:
				if world.tick - o.t0 > 2 and not _in_reach(carrier, e):
					SimMovement.approach_entity(world, e, carrier.id, _reach())
	return SimOrder.RUNNING


func _update_unload(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var c: SimCompCargo = e.cargo
	if c == null:
		return _fail(o, SimCommand.Err.NOT_ALLOWED)
	if o.p1 == 0:  # waiting for the carrier to stand still
		if c.n_pax == 0:
			return SimOrder.DONE
		var mode: int = 1 if (o.arg & 2) != 0 else 2
		if SimTransport.unload_reject(world, e, mode, o.target_id) == 0:
			if SimTransport.begin_unload(world, e, mode, o.target_id, _drop_x(o, e), _drop_y(o, e)):
				o.p1 = 1
				o.p0 = c.n_pax
				return SimOrder.RUNNING
		elif mode == 2 and c.index_of(o.target_id) < 0:
			return _fail(o, SimCommand.Err.NO_TARGET)
		if world.tick - o.t0 > APPROACH_TIMEOUT:
			return _fail(o, SimCommand.Err.NOT_ALLOWED)
		return SimOrder.RUNNING
	# unloading: done when the cadence has finished
	if c.unload_mode == 0:
		return SimOrder.DONE
	if world.tick - o.t0 > c.n_pax * SimTransport.unload_interval(world, e) + UNLOAD_SLACK_T + APPROACH_TIMEOUT:
		return _fail(o, SimCommand.Err.NOT_ALLOWED)
	return SimOrder.RUNNING


func on_end(world: SimWorld, e: SimEntity, o: SimOrder, reason: int) -> void:
	if (e.flags & SimFlags.F_GONE) != 0:
		return
	if order_type == SimOrder.T_UNLOAD:
		if o.p1 == 1 and e.cargo != null and (reason == SimOrder.END_CANCELLED or reason == SimOrder.END_REPLACED or reason == SimOrder.END_FAILED):
			SimTransport.cancel_unload(world, e)
		if reason == SimOrder.END_CANCELLED and world.movement != null and e.move != null:
			SimMovement.stop(world, e, false)
		return
	if (reason == SimOrder.END_CANCELLED or reason == SimOrder.END_REPLACED or reason == SimOrder.END_DIED) and world.movement != null and e.move != null and (e.flags & SimFlags.F_INSIDE) == 0:
		if e.move.goal_tick >= o.t0 and e.move.goal_kind != SimMoveConfig.GK_NONE:
			SimMovement.stop(world, e, false)


func on_target_lost(_world: SimWorld, _e: SimEntity, o: SimOrder) -> int:
	o.fail = SimCommand.Err.NO_TARGET
	return SimOrder.FAILED


func _reach() -> int:
	return GARRISON_REACH_U if order_type == SimOrder.T_GARRISON else LOAD_REACH_U


func _in_reach(carrier: SimEntity, e: SimEntity) -> bool:
	var reach: int = _reach() + REACH_SLACK_U + (carrier.radius if order_type == SimOrder.T_LOAD else carrier.radius + 512)
	return Fp.dist(carrier.x - e.x, carrier.y - e.y) <= reach


static func _fail(o: SimOrder, err: int) -> int:
	o.fail = err
	return SimOrder.FAILED


## Drop point handed to begin_unload: the requested point when it lies within 4 cells of the carrier, else the carrier.
static func _drop_x(o: SimOrder, e: SimEntity) -> int:
	if (o.arg & 1) != 0 or Fp.dist(o.x - e.x, o.y - e.y) > 4096:
		return -1
	return o.x


static func _drop_y(o: SimOrder, e: SimEntity) -> int:
	if (o.arg & 1) != 0 or Fp.dist(o.x - e.x, o.y - e.y) > 4096:
		return -1
	return o.y
