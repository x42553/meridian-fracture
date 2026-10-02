extends RefCounted
## Command framework (sim_core 3.5 / 4.8 / 5.5, 10.1 test_sim_commands): SimCmd catalog + goldens, codec totality,
## validation matrix, canonical ordering, built-in executors.

const K := preload("res://tests/support/sim_test_kit.gd")


## Order handler that never finishes; the test reads the queue.
class Rec:
	extends SimOrderHandler

	func on_update(_world: SimWorld, _e: SimEntity, _o: SimOrder) -> int:
		return SimOrder.RUNNING


class DebugStage:
	extends SimCombatSystem
	var calls: Array = []

	func on_debug(_world: SimWorld, pid: int, mode: int, target: int, _def_idx: int, count: int, _x: int, _y: int) -> int:
		if mode != 5:
			return -1
		calls.append([pid, target, count])
		return SimCommand.Err.OK


static func _ids(a: Array) -> PackedInt32Array:
	return PackedInt32Array(a)


func _world(extra: Dictionary = {}) -> SimWorld:
	var w: SimWorld = K.make_world(extra)
	var rec: Rec = Rec.new()
	for ty: int in [SimOrder.T_FOLLOW, SimOrder.T_LOAD, SimOrder.T_GARRISON, SimOrder.T_CAPTURE, SimOrder.T_REPAIR, SimOrder.T_SALVAGE, SimOrder.T_HARVEST,
			SimOrder.T_RETURN_CARGO, SimOrder.T_ATTACK, SimOrder.T_ATTACK_MOVE, SimOrder.T_GUARD, SimOrder.T_HOLD, SimOrder.T_FORCE_FIRE, SimOrder.T_RETURN_BASE]:
		w.orders.replace_handler(ty, rec)  # replace: the economy / movement / combat domains register their own
	return w


func test_golden_vectors(t: TestCtx) -> void:
	t.eq(SimCmd.move(_ids([40, 12, 16, 15]), 5000, 7168), PackedInt32Array([1, 5000, 7168, 0, 0, 12, 15, 16, 40]), "move (ids canonicalised)")
	t.eq(SimCmd.attack(_ids([301, 305]), 777, 1), PackedInt32Array([40, 777, 1, 0, 301, 305]), "attack")
	t.eq(SimCmd.train(55, 17, 3), PackedInt32Array([124, 55, 17, 3]), "train")
	t.eq(SimCmd.build_place(9, 12, 20, 0), PackedInt32Array([123, 9, 12, 20, 0]), "build_place")
	t.eq(SimCmd.use_power(1, 90000, 131072, 1024), PackedInt32Array([140, 1, 90000, 131072, 1024, 0]), "use_power")
	t.eq(SimCmd.resign(0), PackedInt32Array([250, 0]), "resign")
	for ints: PackedInt32Array in [SimCmd.move(_ids([40, 12]), 5000, 7168), SimCmd.attack(_ids([301]), 777, 1), SimCmd.train(55, 17, 3), SimCmd.resign(0)]:
		var c: SimCommand = SimCommand.from_ints(0, ints)
		t.not_null(c, "decodes")
		t.eq(c.to_ints(), ints, "from_ints -> to_ints round trip")
	# use_power decodes fine at the codec level (range checks belong to validation)
	t.not_null(SimCommand.from_ints(0, SimCmd.use_power(1, 90000, 131072, 1024)), "use_power decodes")


func test_catalog(t: TestCtx) -> void:
	var ops: PackedInt32Array = SimCmd.all_ops()
	t.eq(ops.size(), 45, "45 ops")
	var sorted: PackedInt32Array = ops.duplicate()
	sorted.sort()
	t.eq(ops, sorted, "ascending")
	var lay: PackedInt32Array
	var bad: int = 0
	for op: int in ops:
		t.check(SimCmd.is_known(op), "known %d" % op)
		lay = SimCmd.layout_of(op)
		var values: Array = []
		for i: int in lay.size():
			values.append(10 + i * 3)
		var ids: PackedInt32Array = PackedInt32Array()
		if (SimCmd.meta_of(op) & SimCmd.M_IDS) != 0:
			ids = _ids([9, 3, 9, 5])
		var ints: PackedInt32Array = SimCmd.build(op, values, ids)
		var dc: SimCommand = SimCommand.from_ints(2, ints)
		if dc == null:
			bad += 1
			continue
		if dc.op != op or dc.pid != 2:
			bad += 1
		if not ids.is_empty() and dc.ids != _ids([3, 5, 9]):
			bad += 1
		var back: PackedInt32Array = dc.to_ints()
		var want: PackedInt32Array = ints.duplicate()
		if not ids.is_empty():
			want = SimCmd.build(op, values, _ids([3, 5, 9]))
		if back != want:
			bad += 1
	t.eq(bad, 0, "every op of the catalog builds, decodes and re-encodes identically")
	t.check_false(SimCmd.is_known(0) or SimCmd.is_known(200) or SimCmd.is_known(-1), "unknown ops")
	t.eq(SimCmd.name_of(SimCmd.RESIGN), "RESIGN", "name_of")
	t.eq(SimCmd.load(_ids([4, 2]), 9, 1), PackedInt32Array([5, 9, 1, 2, 4]), "the LOAD builder (a method named like the global load())")
	# the movement flag bits and the field slots
	var c: SimCommand = SimCommand.from_ints(0, SimCmd.follow(_ids([3]), 77, 1))
	t.eq([c.target, c.mode], [77, 1] as Array, "FOLLOW: target, mode")
	c = SimCommand.from_ints(0, SimCmd.return_to_base(_ids([3]), 55, 0))
	t.eq(c.target, 55, "RETURN_TO_BASE.target")
	c = SimCommand.from_ints(0, SimCmd.debug(2, 5, 6, 7, 8, 9))
	t.eq([c.mode, c.target, c.def, c.count, c.x, c.y], [2, 5, 6, 7, 8, 9] as Array, "DEBUG wire order mode, target, def, count, x, y")


func test_codec_rejects(t: TestCtx) -> void:
	var many: PackedInt32Array = PackedInt32Array()
	many.resize(1025)
	many.fill(1)
	many[0] = SimCmd.RESIGN
	var ids513: PackedInt32Array = PackedInt32Array([SimCmd.STOP])
	for i: int in 513:
		ids513.append(i + 1)
	var ids512: PackedInt32Array = PackedInt32Array([SimCmd.STOP])
	for i: int in 512:
		ids512.append(i + 1)
	var cases: Array = [
		["empty", PackedInt32Array(), SimCommand.Err.BAD_FIELD],
		["op 0", PackedInt32Array([0]), SimCommand.Err.UNKNOWN_OP],
		["op 200", PackedInt32Array([200, 1]), SimCommand.Err.UNKNOWN_OP],
		["negative op", PackedInt32Array([-5, 1]), SimCommand.Err.UNKNOWN_OP],
		["short fields", PackedInt32Array([SimCmd.MOVE, 1, 2]), SimCommand.Err.BAD_FIELD],
		["trailing ints on an id-less op", PackedInt32Array([SimCmd.RESIGN, 0, 7]), SimCommand.Err.BAD_FIELD],
		["id 0", PackedInt32Array([SimCmd.STOP, 0]), SimCommand.Err.BAD_FIELD],
		["negative id", PackedInt32Array([SimCmd.STOP, 4, -2]), SimCommand.Err.BAD_FIELD],
		["1025 ints", many, SimCommand.Err.BAD_FIELD],
		["513 ids", ids513, SimCommand.Err.BAD_FIELD],
		["512 ids are fine", ids512, SimCommand.Err.OK],
		["no ids is decodable", PackedInt32Array([SimCmd.STOP]), SimCommand.Err.OK],
	]
	for row: Array in cases:
		var c: SimCommand = SimCommand.new()
		c.raw = row[1]
		t.eq(SimCommandCodec.decode(c), row[2], row[0])
	t.is_null(SimCommand.from_ints(0, PackedInt32Array()), "from_ints: null if malformed")


func test_validation_matrix(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var r0: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)  # 3
	var r1: SimEntity = K.spawn_rifle(w, 1, 60000, 60000)  # 4
	w.step()
	var cs: SimCommandSystem = w.commands
	var ex: Callable = func(pid: int, ints: PackedInt32Array) -> int: return cs.execute(w, SimCommand.from_ints(pid, ints))
	t.eq(ex.call(0, SimCmd.move(_ids([r1.id]), 100, 100)), SimCommand.Err.NO_ACTORS, "foreign ids -> NO_ACTORS")
	t.eq(ex.call(0, SimCmd.move(_ids([999]), 100, 100)), SimCommand.Err.NO_ACTORS, "unknown ids -> NO_ACTORS")
	t.eq(ex.call(0, SimCmd.move(_ids([1]), 100, 100)), SimCommand.Err.NO_ACTORS, "M_UNITS: an own structure is not an actor")
	t.eq(ex.call(0, SimCmd.move(_ids([r1.id, r0.id]), 100, 100)), SimCommand.Err.OK, "a partially stale selection still works")
	t.eq(r0.orders.size(), 1, "only the own unit got the order")
	t.eq(r1.orders.size(), 0, "the foreign one did not")
	t.eq(ex.call(0, SimCmd.move(_ids([r0.id]), 96 * 1024, 100)), SimCommand.Err.BAD_FIELD, "x = map width")
	t.eq(ex.call(0, SimCmd.move(_ids([r0.id]), 100, -1)), SimCommand.Err.BAD_FIELD, "negative y")
	t.eq(ex.call(0, SimCmd.move(_ids([r0.id]), 100, 100, 3)), SimCommand.Err.BAD_FIELD, "queue mode 3")
	t.eq(ex.call(0, SimCmd.move(_ids([r0.id]), 100, 100, 0, 8)), SimCommand.Err.BAD_FIELD, "undefined flag bit")
	t.eq(ex.call(0, SimCmd.build_place(3, 96, 5)), SimCommand.Err.BAD_FIELD, "M_CELL: cell out of range")
	t.eq(ex.call(0, SimCmd.use_power(0, 0, 0, 4096)), SimCommand.Err.BAD_FIELD, "M_ANGLE")
	t.eq(ex.call(0, SimCmd.use_power(1, 90000, 131072, 1024)), SimCommand.Err.BAD_FIELD, "use_power y beyond a 96-cell map")
	t.eq(ex.call(0, SimCmd.debug(1, 0, 0, 500)), SimCommand.Err.NOT_ALLOWED, "DEBUG without allow_debug")
	t.eq(ex.call(0, SimCmd.set_stance(_ids([r0.id]), 1)), SimCommand.Err.NOT_AVAILABLE, "SET_STANCE has no executor")
	t.eq(ex.call(9, SimCmd.resign(0)), SimCommand.Err.BAD_PLAYER, "pid 9")
	t.eq(ex.call(-1, SimCmd.resign(0)), SimCommand.Err.BAD_PLAYER, "pid -1")
	t.eq(ex.call(0, SimCmd.train(1, 2, 3)), SimCommand.Err.WRONG_KIND, "TRAIN reaches the production domain's executor (entity 1 is no producer)")
	# custom executor registration, replacing wins
	cs.register_executor(SimCmd.TRAIN, func(_w: SimWorld, c: SimCommand) -> int:
		c.detail = 7
		return SimCommand.Err.NO_CREDITS)
	t.eq(ex.call(0, SimCmd.train(1, 2, 3)), SimCommand.Err.NO_CREDITS, "registered executor")
	cs.register_executor(SimCmd.TRAIN, func(_w: SimWorld, _c: SimCommand) -> int: return SimCommand.Err.OK)
	t.eq(ex.call(0, SimCmd.train(1, 2, 3)), SimCommand.Err.OK, "a later registration replaces the earlier one")


func test_counters_and_rejection_events(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var r0: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	w.step()
	w.events.clear()
	w.submit_raw(0, SimCmd.move(_ids([r0.id]), 5000, 5000))  # accepted
	w.submit_raw(0, SimCmd.move(_ids([77]), 5000, 5000))  # NO_ACTORS
	w.submit_raw(0, SimCmd.move(_ids([r0.id]), 5000, 5000, 3))  # BAD_FIELD (throttled away)
	w.submit_raw(0, PackedInt32Array([200]))  # UNKNOWN_OP
	w.submit_raw(0, PackedInt32Array())  # empty
	w.submit_raw(0, SimCmd.set_stance(_ids([r0.id]), 1))  # NOT_AVAILABLE
	w.submit_raw(9, SimCmd.resign(0))  # unknown player: ignored
	w.step()
	t.eq([w.players[0].st_cmds, w.players[0].st_rejected], [1, 5] as Array, "1 accepted / 5 rejected")
	var n: int = 0
	for i: int in w.events.count():
		if w.events.data[i * 10] == SimEvent.CMD_REJECTED:
			n += 1
			t.eq(w.events.data[i * 10 + 4], 0, "CMD_REJECTED carries the pid")
			t.eq(w.events.data[i * 10 + 6], SimCommand.Err.NO_ACTORS, "first rejection reported")
	t.eq(n, 1, "CMD_REJECTED throttled to one per 10 ticks per player")
	t.check(w.players[1].st_rejected == 0 and w.players[1].st_cmds == 0, "the other player is untouched")


func test_canonical_order(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	var b: SimEntity = K.spawn_rifle(w, 1, 60000, 60000)
	w.step()
	var seen: PackedInt32Array = PackedInt32Array()
	w.commands.register_executor(SimCmd.SET_STANCE, func(_w: SimWorld, c: SimCommand) -> int:
		seen.append(c.pid * 10 + c.mode)
		return SimCommand.Err.OK)
	w.submit_raw(1, SimCmd.set_stance(_ids([b.id]), 1))
	w.submit_raw(0, SimCmd.set_stance(_ids([a.id]), 1))
	w.submit_raw(1, SimCmd.set_stance(_ids([b.id]), 2))
	w.submit_raw(0, SimCmd.set_stance(_ids([a.id]), 3))
	w.step()
	t.eq(seen, PackedInt32Array([1, 3, 11, 12]), "sorted by pid, submission order kept inside a pid")


func test_order_ops(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	var b: SimEntity = K.spawn_rifle(w, 0, 31000, 30000)
	w.step()
	var ids: PackedInt32Array = _ids([a.id, b.id])
	var run: Callable = func(ints: PackedInt32Array) -> void:
		w.submit_raw(0, ints)
		w.step()
	run.call(SimCmd.move(ids, 5000, 6000, 0, 7))
	var o: SimOrder = a.orders[0]
	t.eq([o.type, o.x, o.y, o.flags], [SimOrder.T_MOVE, 5000, 6000, SimOrder.OF_NO_FORMATION | SimOrder.OF_SPEED_MATCH | SimOrder.OF_REVERSE_OK] as Array, "MOVE flags b0 + b1 + b2 -> the three OF_ bits")
	t.check(a.orders[0] != b.orders[0], "a fresh SimOrder per actor")
	run.call(SimCmd.attack_move(ids, 100, 100, 0, 5))
	t.eq(a.orders[0].flags, SimOrder.OF_NO_FORMATION | SimOrder.OF_REVERSE_OK, "ATTACK_MOVE maps the same bits")
	run.call(SimCmd.patrol(ids, 100, 100, 0, 2))
	t.eq([a.orders[0].type, a.orders[0].flags], [SimOrder.T_PATROL, SimOrder.OF_CYCLIC | SimOrder.OF_SPEED_MATCH] as Array, "PATROL keeps OF_CYCLIC")
	run.call(SimCmd.follow(ids, 4, 0))
	t.eq([a.orders[0].type, a.orders[0].target_id], [SimOrder.T_FOLLOW, 4] as Array, "FOLLOW issues T_FOLLOW with its target")
	run.call(SimCmd.attack(ids, 4, 0, 1))
	t.eq([a.orders[0].type, a.orders[0].flags], [SimOrder.T_ATTACK, SimOrder.OF_FORCED] as Array, "ATTACK flag b0 = OF_FORCED")
	run.call(SimCmd.return_to_base(ids, 12))
	t.eq([a.orders[0].type, a.orders[0].target_id], [SimOrder.T_RETURN_BASE, 12] as Array, "RETURN_TO_BASE carries its airfield id")
	run.call(SimCmd.force_fire(ids, 0, 500, 600, 3))
	t.eq([a.orders[0].type, a.orders[0].x, a.orders[0].arg], [SimOrder.T_FORCE_FIRE, 500, 3] as Array, "FORCE_FIRE arg = count")
	run.call(SimCmd.hold(ids))
	t.eq(a.orders[0].type, SimOrder.T_HOLD, "HOLD")
	run.call(SimCmd.harvest(ids, 0, 500, 600))
	t.eq(a.orders[0].type, SimOrder.T_HARVEST, "HARVEST")
	run.call(SimCmd.move(ids, 100, 100, SimOrder.QM_APPEND))
	t.eq(a.orders.size(), 2, "queue mode APPEND keeps the head")
	run.call(SimCmd.move(ids, 100, 100, SimOrder.QM_FRONT))
	t.eq([a.orders.size(), a.orders[0].type, a.orders[1].type], [3, SimOrder.T_MOVE, SimOrder.T_HARVEST] as Array, "FRONT inserts at index 0")
	run.call(SimCmd.stop(ids))
	t.eq([a.orders.size(), b.orders.size()], [0, 0] as Array, "STOP clears the whole queue")


func test_scatter_draws(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var a: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	var b: SimEntity = K.spawn_rifle(w, 0, 33000, 30000)
	w.step()
	var expect: SimRng = SimRng.new(1)
	expect.set_state(w.rng.get_state())
	var draws: PackedInt32Array = PackedInt32Array()
	for _i: int in 4:
		draws.append(expect.range_i(-3072, 3072))
	w.submit_raw(0, SimCmd.scatter(_ids([b.id, a.id])))
	w.step()
	t.eq(w.rng.get_state(), expect.get_state(), "2 draws per actor")
	var o: SimOrder = a.orders[0]
	t.eq([o.type, o.x, o.y], [SimOrder.T_MOVE, 30000 + draws[0], 30000 + draws[1]] as Array, "id order: actor a draws first, x then y")
	t.eq(b.orders[0].x, 33000 + draws[2], "then actor b")


func test_resign_and_debug(t: TestCtx) -> void:
	var w: SimWorld = _world({"players": 3, "rules": {"allow_debug": 1}})
	var r: SimEntity = K.spawn_rifle(w, 1, 60000, 60000)
	w.step()
	w.submit_raw(1, SimCmd.resign(2))
	w.step()
	t.eq([w.players[1].eliminated, w.players[1].elim_reason], [1, SimPlayer.Elim.KICKED] as Array, "RESIGN mode 2 -> KICKED")
	var ev: int = w.events.count()
	w.submit_raw(1, SimCmd.resign(0))
	w.step()
	t.eq(w.players[1].elim_reason, SimPlayer.Elim.KICKED, "second RESIGN is idempotent")
	t.eq(w.players[1].st_rejected, 0, "and legal in any state (accepted)")
	w.submit_raw(1, SimCmd.move(_ids([r.id]), 100, 100))
	w.step()
	t.eq(w.players[1].st_rejected, 1, "other commands of an eliminated player are rejected")
	t.check(w.events.count() >= ev, "events")
	# DEBUG (allow_debug = 1)
	w.submit_raw(0, SimCmd.debug(1, 0, 0, 500))
	w.submit_raw(0, SimCmd.debug(2, 0, K.unit_def(DefTestKit.U_TANK), 2, 40000, 40000))
	w.step()
	t.eq(w.players[0].credits, 8000, "mode 1: +500 credits")
	t.eq(w.units_of(0).size(), 2, "mode 2: two tanks spawned")
	var tank_id: int = w.units_of(0)[0].id
	w.submit_raw(0, SimCmd.debug(3, tank_id))
	w.submit_raw(0, SimCmd.debug(3, 9999))
	w.step()
	t.check(not w.is_alive(tank_id), "mode 3 kills the target")
	t.eq(w.players[0].st_rejected, 1, "a vanished target is NO_TARGET (rejected)")
	# mode 5 reaches a stage's on_debug, an unclaimed mode is BAD_FIELD
	var dbg: DebugStage = DebugStage.new()
	var w2: SimWorld = K.make_world({"combat_stub": false, "rules": {"allow_debug": 1}, "opts": {"systems": [dbg]}})
	var c5: SimCommand = SimCommand.from_ints(0, SimCmd.debug(5, 3, 0, 77))
	t.eq(w2.commands.execute(w2, c5), SimCommand.Err.OK, "mode 5 handled by the combat double")
	t.eq(dbg.calls, [[0, 3, 77]] as Array, "on_debug args")
	t.eq(w2.commands.execute(w2, SimCommand.from_ints(0, SimCmd.debug(6))), SimCommand.Err.BAD_FIELD, "unclaimed mode 6")
	t.eq(w2.commands.execute(w2, SimCommand.from_ints(0, SimCmd.debug(2, 0, 99, 1))), SimCommand.Err.BAD_FIELD, "unknown def")


func test_scuttle_and_ended(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var r: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	w.step()
	w.submit_raw(0, SimCmd.scuttle(_ids([r.id])))
	w.step()
	t.check(w.get_entity(r.id) == null, "scuttled unit is gone after the step")
	t.eq(w.wrecks.size(), 0, "SCUTTLE leaves no wreck")
	w.end_match(-1, SimWorld.EndReason.DRAW)
	t.eq(w.commands.execute(w, SimCommand.from_ints(0, SimCmd.stop(_ids([1])))), SimCommand.Err.MATCH_ENDED, "MATCH_ENDED")
	w.submit_raw(0, SimCmd.resign(0))
	w.step()
	t.eq(w.players[0].eliminated, 0, "frozen: pending commands are dropped")
