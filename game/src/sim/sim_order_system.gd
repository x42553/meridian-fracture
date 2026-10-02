class_name SimOrderSystem
extends SimSystem
## Stage 5 (sim_core 3.6 / 5.6): handler registry, queue semantics, the order gate and the dispatcher. Stage 5
## iterates UNITS only (structures have no queue). All order state lives in the entities (hashed), none here.


## Built-in T_WAIT: `arg` = ticks.
class WaitHandler:
	extends SimOrderHandler

	func on_begin(world: SimWorld, _e: SimEntity, o: SimOrder) -> int:
		o.t0 = world.tick
		return SimOrder.RUNNING

	func on_update(world: SimWorld, _e: SimEntity, o: SimOrder) -> int:
		return SimOrder.DONE if world.tick - o.t0 >= o.arg else SimOrder.RUNNING


var _handlers: Array[SimOrderHandler] = []
var _idle: Array[SimOrderHandler] = []


func _init() -> void:
	stage_no = 5
	_handlers.resize(SimOrder.TYPE_COUNT)
	_handlers[SimOrder.T_WAIT] = WaitHandler.new()


## One handler per type; a duplicate is logged (Log.error) and ignored (first wins).
func register_handler(type: int, h: SimOrderHandler) -> void:
	if type <= 0 or type >= SimOrder.TYPE_COUNT or h == null:
		Log.error("orders", "register_handler: bad type %d" % type)
		return
	if _handlers[type] != null:
		Log.error("orders", "register_handler: order type %d already has a handler (first wins)" % type)
		return
	_handlers[type] = h


## Deliberate override (tests).
func replace_handler(type: int, h: SimOrderHandler) -> void:
	if type <= 0 or type >= SimOrder.TYPE_COUNT:
		Log.error("orders", "replace_handler: bad type %d" % type)
		return
	_handlers[type] = h


## Called (registration order) for units with an empty queue until one enqueues an order.
func register_idle(h: SimOrderHandler) -> void:
	_idle.append(h)


func has_handler(type: int) -> bool:
	return type > 0 and type < SimOrder.TYPE_COUNT and _handlers[type] != null


## Every stage's order_gate, then handler.can_issue; QUEUE_FULL at MAX_ORDERS; REPLACE ends begun orders with
## END_REPLACED. Returns a SimCommand.Err.
func issue(world: SimWorld, e: SimEntity, o: SimOrder, mode: int) -> int:
	if e == null or e.kind != SimEntity.Kind.UNIT or (e.flags & SimFlags.F_GONE) != 0:
		return SimCommand.Err.BAD_ORDER
	if not has_handler(o.type):
		return SimCommand.Err.NOT_AVAILABLE
	for s: SimSystem in world.stages:
		var g: int = s.order_gate(world, e, o)
		if g != SimCommand.Err.OK:
			return g
	var h: SimOrderHandler = _handlers[o.type]
	var err: int = h.can_issue(world, e, o)
	if err != SimCommand.Err.OK:
		return err
	var q: Array[SimOrder] = e.orders
	if mode == SimOrder.QM_APPEND:
		if q.size() >= SimConfig.MAX_ORDERS:
			return SimCommand.Err.QUEUE_FULL
		q.append(o)
	elif mode == SimOrder.QM_FRONT:
		if q.size() >= SimConfig.MAX_ORDERS:
			return SimCommand.Err.QUEUE_FULL
		q.push_front(o)
	else:
		clear(world, e, SimOrder.END_REPLACED)
		q.append(o)
	return SimCommand.Err.OK


## Domain-created orders (auto-harvest, retaliation): same validation, flag OF_AUTO.
func issue_internal(world: SimWorld, e: SimEntity, type: int, target_id: int = 0, x: int = 0, y: int = 0, mode: int = SimOrder.QM_REPLACE, arg: int = 0) -> int:
	var o: SimOrder = SimOrder.make(type, target_id, x, y, arg, 0, SimOrder.OF_AUTO)
	return issue(world, e, o, mode)


## on_end(reason) for every begun order, then empty the queue.
func clear(world: SimWorld, e: SimEntity, reason: int = SimOrder.END_CANCELLED) -> void:
	var q: Array[SimOrder] = e.orders
	if q.is_empty():
		return
	var old: Array[SimOrder] = q.duplicate()
	q.clear()
	for o: SimOrder in old:
		if o.phase != SimOrder.PH_NEW:
			var h: SimOrderHandler = _handlers[o.type]
			if h != null:
				h.on_end(world, e, o, reason)


func update(world: SimWorld) -> void:
	var list: Array[SimEntity] = world.units
	var n: int = list.size()
	for i: int in n:
		var e: SimEntity = list[i]
		if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
			continue
		var q: Array[SimOrder] = e.orders
		if q.is_empty():
			for ih: SimOrderHandler in _idle:
				ih.on_idle(world, e)
				if not q.is_empty():
					break
			continue
		var o: SimOrder = q[0]
		var h: SimOrderHandler = _handlers[o.type]
		if h == null:
			q.pop_front()
			continue
		var st: int
		if h.requires_target and o.target_id != 0 and not world.is_alive(o.target_id):
			st = h.on_target_lost(world, e, o)
		elif o.phase == SimOrder.PH_NEW:
			o.phase = 1
			st = h.on_begin(world, e, o)
			if st == SimOrder.RUNNING:
				st = h.on_update(world, e, o)
		else:
			st = h.on_update(world, e, o)
		if st != SimOrder.RUNNING:
			var idx: int = q.find(o)
			if idx >= 0:
				q.remove_at(idx)
			if o.phase != SimOrder.PH_NEW:
				h.on_end(world, e, o, SimOrder.END_FAILED if st == SimOrder.FAILED else SimOrder.END_DONE)
			if st == SimOrder.FAILED:
				world.events.emit(SimEvent.ORDER_FAILED, e.x, e.y, e.id, o.type, o.fail, 0)
			elif (o.flags & SimOrder.OF_CYCLIC) != 0 and q.size() < SimConfig.MAX_ORDERS:
				o.phase = SimOrder.PH_NEW
				q.append(o)
