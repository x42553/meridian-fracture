extends RefCounted
## Order system (sim_core 3.6 / 5.6, 10.1 test_sim_orders): dispatcher, queue modes, cyclic, failure, on_end reasons,
## idle hooks, order_gate.

const K := preload("res://tests/support/sim_test_kit.gd")
const T1: int = SimOrder.T_ATTACK
const T2: int = SimOrder.T_GUARD
const T3: int = SimOrder.T_HOLD


## Records "b<type>" (begin), "u<type>.<n>" (nth update of the order), "e<type>/<reason>" (end).
class Tracer:
	extends SimOrderHandler
	var lg: Array[String] = []
	var type: int = 0
	var done_after: int = 0  ## DONE on this update count (0 = never)
	var fail_after: int = 0
	var fail_err: int = SimCommand.Err.BLOCKED
	var lost: int = 0

	func on_begin(_w: SimWorld, _e: SimEntity, o: SimOrder) -> int:
		lg.append("b%d" % o.type)
		return SimOrder.RUNNING

	func on_update(_w: SimWorld, _e: SimEntity, o: SimOrder) -> int:
		o.p0 += 1
		lg.append("u%d.%d" % [o.type, o.p0])
		if fail_after > 0 and o.p0 >= fail_after:
			o.fail = fail_err
			return SimOrder.FAILED
		if done_after > 0 and o.p0 >= done_after:
			return SimOrder.DONE
		return SimOrder.RUNNING

	func on_end(_w: SimWorld, _e: SimEntity, o: SimOrder, reason: int) -> void:
		lg.append("e%d/%d" % [o.type, reason])

	func on_target_lost(_w: SimWorld, _e: SimEntity, o: SimOrder) -> int:
		lost += 1
		return super.on_target_lost(_w, _e, o)


class Idle:
	extends SimOrderHandler
	var tag: String
	var lg: Array[String]
	var enqueue: bool

	func _init(p_tag: String, p_log: Array[String], p_enqueue: bool) -> void:
		tag = p_tag
		lg = p_log
		enqueue = p_enqueue

	func on_idle(world: SimWorld, e: SimEntity) -> void:
		lg.append(tag)
		if enqueue:
			world.orders.issue_internal(world, e, SimOrder.T_WAIT, 0, 0, 0, SimOrder.QM_REPLACE, 5)


class Gate:
	extends SimPowerSystem
	var deny_type: int = 0

	func order_gate(_world: SimWorld, _e: SimEntity, o: SimOrder) -> int:
		return SimCommand.Err.DISABLED if o.type == deny_type else SimCommand.Err.OK


func _setup(extra: Dictionary = {}) -> Array:
	var w: SimWorld = K.make_world(extra)
	var trs: Array = []
	for ty: int in [T1, T2, T3]:
		var trc: Tracer = Tracer.new()
		trc.type = ty
		w.orders.register_handler(ty, trc)
		trs.append(trc)
	var u: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	w.step()
	return [w, u, trs[0]]


func _issue(w: SimWorld, u: SimEntity, type: int, mode: int = SimOrder.QM_REPLACE, arg: int = 0) -> int:
	return w.orders.issue(w, u, SimOrder.make(type, 0, 0, 0, arg), mode)


func test_begin_update_fusion_and_done(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var u: SimEntity = s[1]
	var trc: Tracer = s[2]
	trc.done_after = 3
	t.eq(_issue(w, u, T1), SimCommand.Err.OK, "issue")
	w.step()
	t.eq(trc.lg, ["b40", "u40.1"] as Array[String], "on_begin and on_update run in the same pass")
	w.run(2)
	t.eq(trc.lg, ["b40", "u40.1", "u40.2", "u40.3", "e40/0"] as Array[String], "DONE calls on_end(DONE) once")
	t.eq(u.orders.size(), 0, "queue empty")
	w.step()
	t.eq(trc.lg.size(), 5, "nothing more")


func test_duplicate_registration_and_wait(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var u: SimEntity = s[1]
	var trc: Tracer = s[2]
	var other: Tracer = Tracer.new()
	Log.quiet = true
	w.orders.register_handler(T1, other)
	Log.quiet = false
	t.check("already has a handler" in Log.ring[Log.ring.size() - 1], "duplicate is logged")
	_issue(w, u, T1)
	w.step()
	t.eq(other.lg.size(), 0, "first registration wins")
	t.eq(trc.lg.size(), 2, "the original ran")
	w.orders.replace_handler(T1, other)
	_issue(w, u, T1)
	w.step()
	t.eq(other.lg, ["e40/3", "b40", "u40.1"] as Array[String], "replace_handler is the deliberate override (the old order ends in the new handler)")
	t.check(w.orders.has_handler(SimOrder.T_WAIT) and not w.orders.has_handler(SimOrder.T_LAND), "has_handler")
	_issue(w, u, SimOrder.T_WAIT, SimOrder.QM_REPLACE, 3)
	w.step()
	t.eq(u.orders.size(), 1, "waiting")
	w.run(2)
	t.eq(u.orders.size(), 1, "still waiting after 3 updates")
	w.step()
	t.eq(u.orders.size(), 0, "WAIT(3) done")
	t.eq(_issue(w, u, SimOrder.T_LAND), SimCommand.Err.NOT_AVAILABLE, "no handler")


func test_queue_modes(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var u: SimEntity = s[1]
	var trc: Tracer = s[2]
	_issue(w, u, T1)
	w.step()
	_issue(w, u, T2, SimOrder.QM_APPEND)
	t.eq(u.orders.size(), 2, "append")
	t.eq(_issue(w, u, T3), SimCommand.Err.OK, "replace")
	t.eq(trc.lg, ["b40", "u40.1", "e40/3"] as Array[String], "REPLACE: on_end(REPLACED) for the begun order only (the appended one never began)")
	t.eq(u.orders.size(), 1, "one order left")
	w.orders.clear(w, u)
	t.eq(u.orders.size(), 0, "clear")
	# FRONT: the interrupted order keeps its phase and resumes
	var s2: Array = _setup()
	var w2: SimWorld = s2[0]
	var u2: SimEntity = s2[1]
	var t1: Tracer = s2[2]
	_issue(w2, u2, T1)
	w2.step()  # b40 u40.1
	var t2: Tracer = w2.orders._handlers[T2]
	t2.done_after = 2
	t2.lg = t1.lg  # one shared lg
	_issue(w2, u2, T2, SimOrder.QM_FRONT)
	w2.run(3)
	t.eq(t1.lg, ["b40", "u40.1", "b42", "u42.1", "u42.2", "e42/0", "u40.2"] as Array[String], "FRONT: b42 u42.1 u42.2 e42/0, then the interrupted order resumes at its phase")


func test_queue_full_and_cyclic(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var u: SimEntity = s[1]
	for _i: int in SimConfig.MAX_ORDERS:
		t.eq(_issue(w, u, T2, SimOrder.QM_APPEND), SimCommand.Err.OK, "append")
	t.eq(_issue(w, u, T2, SimOrder.QM_APPEND), SimCommand.Err.QUEUE_FULL, "QUEUE_FULL at 32")
	t.eq(_issue(w, u, T2, SimOrder.QM_FRONT), SimCommand.Err.QUEUE_FULL, "and for FRONT")
	t.eq(_issue(w, u, T2), SimCommand.Err.OK, "REPLACE still works")
	var s2: Array = _setup()
	var w2: SimWorld = s2[0]
	var u2: SimEntity = s2[1]
	var trc: Tracer = s2[2]
	trc.done_after = 1
	var o: SimOrder = SimOrder.make(T1)
	o.flags = SimOrder.OF_CYCLIC
	w2.orders.issue(w2, u2, o, SimOrder.QM_REPLACE)
	w2.run(3)
	t.eq(trc.lg, ["b40", "u40.1", "e40/0", "b40", "u40.2", "e40/0", "b40", "u40.3", "e40/0"] as Array[String], "OF_CYCLIC re-queues with the phase reset")
	t.eq(u2.orders.size(), 1, "still queued")


func test_failure_and_target_loss(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var u: SimEntity = s[1]
	var trc: Tracer = s[2]
	trc.fail_after = 2
	_issue(w, u, T1)
	_issue(w, u, T2, SimOrder.QM_APPEND)
	w.events.clear()
	w.run(2)
	t.eq(trc.lg.slice(0, 4), ["b40", "u40.1", "u40.2", "e40/1"] as Array[String], "FAILED: on_end(FAILED)")
	t.eq(u.orders.size(), 1, "FAILED drops only that order")
	t.eq(u.orders[0].type, T2, "the rest of the queue continues")
	var found: bool = false
	for i: int in w.events.count():
		if w.events.data[i * 10] == SimEvent.ORDER_FAILED:
			found = true
			t.eq(w.events.data.slice(i * 10 + 4, i * 10 + 8), PackedInt32Array([u.id, T1, SimCommand.Err.BLOCKED, 0]), "ORDER_FAILED: unit, type, o.fail, detail")
	t.check(found, "ORDER_FAILED emitted")
	# on_target_lost then on_end(FAILED)
	var s2: Array = _setup()
	var w2: SimWorld = s2[0]
	var u2: SimEntity = s2[1]
	var trc2: Tracer = s2[2]
	trc2.requires_target = true
	var victim: SimEntity = K.spawn_rifle(w2, 1, 60000, 60000)
	w2.step()
	w2.orders.issue(w2, u2, SimOrder.make(T1, victim.id), SimOrder.QM_REPLACE)
	w2.step()
	w2.remove_entity(victim.id, SimEvent.REM_SCRIPT)
	w2.run(2)
	t.eq(trc2.lost, 1, "on_target_lost called")
	t.eq(trc2.lg.slice(2), ["e40/1"] as Array[String], "then on_end(FAILED)")
	t.eq(u2.orders.size(), 0, "order dropped")


func test_end_reasons(t: TestCtx) -> void:
	var s: Array = _setup()
	var w: SimWorld = s[0]
	var u: SimEntity = s[1]
	var trc: Tracer = s[2]
	_issue(w, u, T1)
	w.step()
	w.submit_raw(0, SimCmd.stop(PackedInt32Array([u.id])))
	w.step()
	t.eq(trc.lg.back(), "e40/2", "STOP -> END_CANCELLED")
	_issue(w, u, T1)
	w.step()
	w.remove_entity(u.id, SimEvent.REM_SCRIPT)
	w.step()
	t.eq(trc.lg.back(), "e40/4", "unit removal -> END_DIED")
	# a killed unit: the order ends when the entity is finalised
	var s2: Array = _setup()
	var w2: SimWorld = s2[0]
	var u2: SimEntity = s2[1]
	_issue(w2, u2, T1)
	w2.step()
	w2.kill(u2, SimWorld.Cause.SCRIPT)
	w2.step()
	t.eq((s2[2] as Tracer).lg.back(), "e40/4", "kill -> END_DIED")
	# ownership change cancels
	var s3: Array = _setup({"players": 2})
	var w3: SimWorld = s3[0]
	var u3: SimEntity = s3[1]
	_issue(w3, u3, T1)
	w3.step()
	w3.change_owner(u3.id, 1)
	t.eq((s3[2] as Tracer).lg.back(), "e40/2", "change_owner -> END_CANCELLED")


func test_idle_hooks(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	var u: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	var lg: Array[String] = []
	w.orders.register_idle(Idle.new("first", lg, false))
	w.orders.register_idle(Idle.new("second", lg, true))
	w.orders.register_idle(Idle.new("third", lg, false))
	w.step()
	t.eq(lg, ["first", "second"] as Array[String], "registration order; the chain stops once an order is enqueued")
	t.eq([u.orders.size(), u.orders[0].type, u.orders[0].flags & SimOrder.OF_AUTO], [1, SimOrder.T_WAIT, SimOrder.OF_AUTO] as Array, "issue_internal sets OF_AUTO")
	w.step()
	t.eq(lg.size(), 2, "not idle any more")


func test_order_gate(t: TestCtx) -> void:
	var gate: Gate = Gate.new()
	gate.deny_type = SimOrder.T_MOVE
	var w: SimWorld = K.make_world({"opts": {"systems": [gate]}})
	var u: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	w.step()
	t.eq(w.orders.issue(w, u, SimOrder.make(SimOrder.T_MOVE, 0, 5, 5), SimOrder.QM_REPLACE), SimCommand.Err.DISABLED, "the gate vetoes")
	t.eq(u.orders.size(), 0, "nothing queued")
	w.submit_raw(0, SimCmd.move(PackedInt32Array([u.id]), 500, 500))
	w.step()
	t.eq(w.players[0].st_rejected, 1, "a vetoed MOVE command is rejected and counted")
	t.eq(u.orders.size(), 0, "no effect")
	gate.deny_type = 0
	w.submit_raw(0, SimCmd.move(PackedInt32Array([u.id]), 500, 500))
	w.step()
	t.eq(w.players[0].st_cmds, 1, "accepted once the gate opens")
