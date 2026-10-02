class_name SimOrderMove
extends SimOrderHandler
## T_MOVE / T_PATROL / T_FOLLOW / T_FACE (terrain_movement 3.10.3 / 5.5 / 6.2). One stateless instance per order type
## (`SimOrderMove.new(SimOrder.T_MOVE)`); all state lives in the order (`t0` tick begun, `p0` goal cell or last
## retry tick, `p1` phase marker) and in the unit's SimCompMove. The built-in command executor already turns MOVE /
## SCATTER / PATROL / FOLLOW commands into these orders and STOP into orders.clear (-> on_end -> SimMovement.stop).
##
## `p1` markers: T_MOVE / T_PATROL 1 = waiting for the unit to unpack (abilities.request_pack was asked), T_PATROL 2 =
## the leg runs as a child T_ATTACK_MOVE order in front of this one. T_PATROL keeps the bounce point in `arg, arg2`.

const FOLLOW_MAX_DEFAULT: int = 3072
const FOLLOW_MIN_DEFAULT: int = 1024
const FOLLOW_RETRY: int = 20  ## ticks between re-issuing a follow goal that ended
const PACK_TIMEOUT: int = 600  ## ticks a unit may take to become mobile
const FACE_TIMEOUT: int = 400
const FACE_DONE: int = 64  ## |error| below this counts as facing

var order_type: int = SimOrder.T_MOVE


func _init(p_type: int = SimOrder.T_MOVE) -> void:
	order_type = p_type
	requires_target = p_type == SimOrder.T_FOLLOW


func can_issue(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var mv: SimCompMove = e.move
	if mv == null:
		return SimCommand.Err.NOT_ALLOWED
	if order_type == SimOrder.T_FOLLOW:
		if mv.mc >= MapTerrain.MC_AIR_FIXED:
			return SimCommand.Err.NOT_ALLOWED
		var t: SimEntity = world.get_entity(o.target_id)
		if t == null or t.id == e.id or (t.flags & SimFlags.F_GONE) != 0:
			return SimCommand.Err.NO_TARGET
		if t.kind != SimEntity.Kind.UNIT:
			return SimCommand.Err.WRONG_KIND
	elif order_type == SimOrder.T_PATROL and mv.mc >= MapTerrain.MC_AIR_FIXED:
		return SimCommand.Err.NOT_ALLOWED
	return SimCommand.Err.OK


func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var mv: SimCompMove = e.move
	o.t0 = world.tick
	o.p1 = 0
	match order_type:
		SimOrder.T_FACE:
			return _begin_face(world, e, o, mv)
		SimOrder.T_FOLLOW:
			o.p0 = world.tick
			_follow(world, e, o)
			return SimOrder.RUNNING
	if mv.mc >= MapTerrain.MC_AIR_FIXED:
		return _begin_air(world, e, o, mv)
	if order_type == SimOrder.T_PATROL and o.arg == 0 and o.arg2 == 0:
		o.arg = e.x
		o.arg2 = e.y
	if world.movement.is_immobile(world, e):
		world.movement.request_pack(world, e)
		o.p1 = 1
		return SimOrder.RUNNING
	return _start_leg(world, e, o)


func on_update(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var mv: SimCompMove = e.move
	match order_type:
		SimOrder.T_FACE:
			return _update_face(world, e, o, mv)
		SimOrder.T_FOLLOW:
			return _update_follow(world, e, o, mv)
	if mv.mc >= MapTerrain.MC_AIR_FIXED:
		return _update_air(world, e, o, mv)
	if order_type == SimOrder.T_PATROL and o.p1 == 2:
		if o.t0 == world.tick:
			return SimOrder.RUNNING  # the child was queued this very tick and has not run yet
		return _leg_done(e, o)  # the child order is gone: this leg is over
	if o.p1 == 1:  # waiting for the pack animation
		if world.movement.is_immobile(world, e):
			if world.tick - o.t0 > PACK_TIMEOUT:
				return _fail(world, e, o, SimCommand.Err.NOT_ALLOWED, SimMoveConfig.RS_IMMOBILE)
			return SimOrder.RUNNING
		o.p1 = 0
		return _start_leg(world, e, o)
	match mv.state:
		SimMoveConfig.MS_ARRIVED:
			SimMovement.ack(world, e)
			return _leg_done(e, o)
		SimMoveConfig.MS_NO_PATH:
			var rs: int = mv.result
			SimMovement.ack(world, e)
			return _fail(world, e, o, SimCommand.Err.BLOCKED, rs)
		SimMoveConfig.MS_IDLE:
			return _leg_done(e, o)  # the goal was cleared by someone else: nothing left to do
	return SimOrder.RUNNING


func on_end(world: SimWorld, e: SimEntity, o: SimOrder, reason: int) -> void:
	var mv: SimCompMove = e.move
	if mv == null or (e.flags & SimFlags.F_GONE) != 0:
		return
	if order_type == SimOrder.T_MOVE:
		mv.speed_cap_q4 = 0
	if order_type == SimOrder.T_FACE:
		return
	if reason == SimOrder.END_CANCELLED or reason == SimOrder.END_REPLACED or reason == SimOrder.END_DIED or order_type == SimOrder.T_FOLLOW:
		if mv.goal_tick >= o.t0 and mv.goal_kind != SimMoveConfig.GK_NONE:  # only if this order set the current goal
			SimMovement.stop(world, e, false)


func on_target_lost(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	o.fail = SimCommand.Err.NO_TARGET
	world.emit(SimMoveConfig.EV_MOVE_FAILED, e.x, e.y, e.id, SimMoveConfig.RS_BAD_TARGET, o.type)
	return SimOrder.FAILED


# ---- T_MOVE / T_PATROL ------------------------------------------------------------------------------------------------

func _opts(o: SimOrder) -> int:
	var f: int = 0
	if (o.flags & SimOrder.OF_REVERSE_OK) != 0:
		f |= SimMoveConfig.OPT_REVERSE_OK
	if (o.flags & SimOrder.OF_SPEED_MATCH) != 0:
		f |= SimMoveConfig.OPT_SPEED_MATCH
	return f


func _start_leg(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var mv: SimCompMove = e.move
	var gx: int = o.x
	var gy: int = o.y
	var slot: bool = false
	if order_type == SimOrder.T_PATROL and world.orders.has_handler(SimOrder.T_ATTACK_MOVE) and _issue_child(world, e, o):
		o.p1 = 2
		return SimOrder.RUNNING
	if order_type == SimOrder.T_MOVE and (o.flags & SimOrder.OF_NO_FORMATION) == 0 and SimFormation.is_ground(mv):
		if mv.fslot_tick != world.tick:  # not assigned by an earlier member of this tick's group
			mv.speed_cap_q4 = 0
			var ids: PackedInt32Array = PackedInt32Array()
			if SimFormation.group_of(world, e, o, ids) > 1:
				var slots_x: PackedInt32Array = PackedInt32Array()
				var slots_y: PackedInt32Array = PackedInt32Array()
				var fl: int = SimFormation.F_SPEED_MATCH if ((o.flags & SimOrder.OF_SPEED_MATCH) != 0 or SimFormation.SPEED_MATCH_DEFAULT) else 0
				SimFormation.assign(world, ids, o.x, o.y, fl, slots_x, slots_y)
		if mv.fslot_tick == world.tick:
			gx = mv.fslot_x
			gy = mv.fslot_y
			slot = true
	var ok: bool
	if slot:
		ok = SimMovement.go_to_slot(world, e, gx, gy, o.x, o.y, _opts(o))
	else:
		ok = SimMovement.go_to(world, e, gx, gy, _opts(o))
	if not ok:
		return _fail(world, e, o, SimCommand.Err.NOT_ALLOWED, mv.result)
	o.p0 = mv.goal_cell
	return SimOrder.RUNNING


## Patrol leg as a child T_ATTACK_MOVE (combat registered its handler): the unit engages on the way.
func _issue_child(world: SimWorld, e: SimEntity, o: SimOrder) -> bool:
	var err: int = world.orders.issue_internal(world, e, SimOrder.T_ATTACK_MOVE, 0, o.x, o.y, SimOrder.QM_FRONT)
	return err == SimCommand.Err.OK


## A leg is over. A lone patrol swaps its end with the recorded origin, so the dispatcher's re-append bounces it.
func _leg_done(e: SimEntity, o: SimOrder) -> int:
	if order_type == SimOrder.T_PATROL and e.orders.size() == 1:
		var tx: int = o.x
		var ty: int = o.y
		o.x = o.arg
		o.y = o.arg2
		o.arg = tx
		o.arg2 = ty
	return SimOrder.DONE


func _fail(world: SimWorld, e: SimEntity, o: SimOrder, err: int, rs: int) -> int:
	o.fail = err
	world.emit(SimMoveConfig.EV_MOVE_FAILED, e.x, e.y, e.id, rs, o.type)
	return SimOrder.FAILED


# ---- aircraft given a plain move ---------------------------------------------------------------------------------------

func _begin_air(world: SimWorld, e: SimEntity, o: SimOrder, mv: SimCompMove) -> int:
	if e.layer != SimEntity.Layer.AIR and mv.air_mode == SimMoveConfig.AM_PARKED:
		return _fail(world, e, o, SimCommand.Err.NOT_ALLOWED, SimMoveConfig.RS_NO_MOVE)
	SimAirMove.fly_to(world, e, o.x, o.y)
	return SimOrder.RUNNING


func _update_air(world: SimWorld, e: SimEntity, o: SimOrder, mv: SimCompMove) -> int:
	if SimAirMove.at_goal(e):
		return SimOrder.DONE
	if mv.air_mode == SimMoveConfig.AM_PARKED:
		return _fail(world, e, o, SimCommand.Err.NOT_ALLOWED, SimMoveConfig.RS_NO_MOVE)
	return SimOrder.RUNNING


# ---- T_FOLLOW ------------------------------------------------------------------------------------------------------------

func _follow(world: SimWorld, e: SimEntity, o: SimOrder) -> void:
	var max_d: int = o.arg if o.arg > 0 else FOLLOW_MAX_DEFAULT
	var min_d: int = o.arg2 if o.arg2 > 0 else FOLLOW_MIN_DEFAULT
	if world.movement.is_immobile(world, e):
		world.movement.request_pack(world, e)
		return
	SimMovement.follow(world, e, o.target_id, min_d, max_d, _opts(o))


func _update_follow(world: SimWorld, e: SimEntity, o: SimOrder, mv: SimCompMove) -> int:
	if mv.goal_kind == SimMoveConfig.GK_FOLLOW and mv.goal_target == o.target_id and mv.state != SimMoveConfig.MS_NO_PATH:
		return SimOrder.RUNNING
	if mv.state == SimMoveConfig.MS_NO_PATH or mv.state == SimMoveConfig.MS_ARRIVED:
		SimMovement.ack(world, e)
	if world.tick - o.p0 >= FOLLOW_RETRY:  # the follow goal ended (no path, stopped, taken over): ask again
		o.p0 = world.tick
		_follow(world, e, o)
	return SimOrder.RUNNING


# ---- T_FACE ----------------------------------------------------------------------------------------------------------------

func _begin_face(world: SimWorld, e: SimEntity, o: SimOrder, mv: SimCompMove) -> int:
	if mv.mc >= MapTerrain.MC_AIR_FIXED:
		SimAirMove.face(world, e, o.arg)
	else:
		SimMovement.turn_to(world, e, o.arg)
	return SimOrder.RUNNING


func _update_face(world: SimWorld, e: SimEntity, o: SimOrder, mv: SimCompMove) -> int:
	if world.tick - o.t0 > FACE_TIMEOUT:
		return SimOrder.DONE
	if mv.mc >= MapTerrain.MC_AIR_FIXED:
		if mv.mc == MapTerrain.MC_AIR_FIXED or absi(SimSteering.angle_err(o.arg & 4095, e.facing)) < FACE_DONE:
			return SimOrder.DONE
		return SimOrder.RUNNING
	if mv.state == SimMoveConfig.MS_FACING and mv.goal_kind == SimMoveConfig.GK_FACE:
		return SimOrder.RUNNING
	return SimOrder.DONE
