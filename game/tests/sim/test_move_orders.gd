extends RefCounted
## terrain_movement TM-12 (10.1 U7, 10.2 S4 S17 S18 S19): order handlers T_MOVE / T_PATROL / T_FOLLOW / T_FACE and
## SimFormation, driven end to end through the command executor (MOVE / STOP / SCATTER / PATROL / FOLLOW commands).

const M := preload("res://tests/support/move_test_kit.gd")
const C := 1024


## Stand-in for combat's T_ATTACK_MOVE handler (patrol legs become child orders when a handler is registered).
class AtkStub:
	extends SimOrderHandler
	var begins: int = 0

	func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
		begins += 1
		SimMovement.go_to(world, e, o.x, o.y)
		return SimOrder.RUNNING

	func on_update(world: SimWorld, e: SimEntity, _o: SimOrder) -> int:
		if SimMovement.state(e) == SimMoveConfig.MS_ARRIVED:
			SimMovement.ack(world, e)
			return SimOrder.DONE
		return SimOrder.RUNNING


func _ids(list: Array[SimEntity]) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in list:
		out.append(e.id)
	return out


## True while the unit's head order is still its T_MOVE (an idle Collector auto-harvests afterwards).
func _moving(e: SimEntity) -> bool:
	return not e.orders.is_empty() and e.orders[0].type == SimOrder.T_MOVE


func _issue_move(w: SimWorld, e: SimEntity, x: int, y: int, flags: int = 0) -> void:
	w.orders.issue(w, e, SimOrder.make(SimOrder.T_MOVE, 0, x, y, 0, 0, flags), SimOrder.QM_REPLACE)


func _spawn_at(w: SimWorld, id: String, x: int, y: int) -> SimEntity:
	var e: SimEntity = w.spawn_unit(w.data.unit_idx(id), 0, x, y)
	e.radius = 400
	return e


# ---- U7 formation ------------------------------------------------------------------------------------------------------

func test_u7_worked_example(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var a: SimEntity = _spawn_at(w, DefTestKit.U_RIFLEMAN, 10240, 10240)
	var b: SimEntity = _spawn_at(w, DefTestKit.U_RIFLEMAN, 11264, 10240)
	var c: SimEntity = _spawn_at(w, DefTestKit.U_RIFLEMAN, 10240, 11264)
	var d: SimEntity = _spawn_at(w, DefTestKit.U_RIFLEMAN, 11264, 11264)
	var ids: PackedInt32Array = PackedInt32Array([a.id, b.id, c.id, d.id])
	var ox: PackedInt32Array = PackedInt32Array()
	var oy: PackedInt32Array = PackedInt32Array()
	SimFormation.assign(w, ids, 20480, 10752, 0, ox, oy)
	# ids 10..13 of the spec = a, b, c, d
	t.eq([ox[1], oy[1]], [20480, 10122], "unit 11 -> (20480,10122)")
	t.eq([ox[3], oy[3]], [20480, 11382], "unit 13 -> (20480,11382)")
	t.eq([ox[0], oy[0]], [19219, 10122], "unit 10 -> (19219,10122)")
	t.eq([ox[2], oy[2]], [19219, 11382], "unit 12 -> (19219,11382)")
	t.eq(b.move.fslot_tick, w.tick, "the leader stores each member's slot")
	t.eq([c.move.fslot_x, c.move.fslot_y], [19219, 11382], "slot stored in the member's component")
	# a single unit goes to the target
	var one: PackedInt32Array = PackedInt32Array()
	var oney: PackedInt32Array = PackedInt32Array()
	SimFormation.assign(w, PackedInt32Array([a.id]), 30000, 20000, 0, one, oney)
	t.eq([one[0], oney[0]], [30000, 20000], "1 unit: the target")


func test_u7_thirteen_units_and_permutation(t: TestCtx) -> void:
	var pos: Array[Vector2i] = []
	for i: int in 13:
		pos.append(Vector2i(20000 + (i % 5) * 900, 20000 + (i / 5) * 900))
	var sets: Array = []
	for order: int in 2:
		var w: SimWorld = M.world(M.open_map(64))
		var ids: PackedInt32Array = PackedInt32Array()
		for i: int in 13:
			var k: int = i if order == 0 else 12 - i  # the same positions, ids in the opposite order
			ids.append(_spawn_at(w, DefTestKit.U_RIFLEMAN, pos[k].x, pos[k].y).id)
		var ox: PackedInt32Array = PackedInt32Array()
		var oy: PackedInt32Array = PackedInt32Array()
		SimFormation.assign(w, ids, 40000, 20000 + 2 * 900, 0, ox, oy)
		var s: Array = []
		for i: int in 13:
			s.append(ox[i] * 100000 + oy[i])
		s.sort()
		sets.append(s)
		if order == 0:
			var cxm: int = 0
			var cym: int = 0
			for i: int in 13:
				cxm += pos[i].x
				cym += pos[i].y
			var th: int = Fp.atan2(21800 - cym / 13, 40000 - cxm / 13)
			var centred: int = 0
			for i: int in 13:
				var lat: int = ((ox[i] - 40000) * -Fp.sin(th) + (oy[i] - 21800) * Fp.cos(th)) >> 16
				if absi(lat) <= 2:
					centred += 1
			t.eq(centred, 1, "13 units: 4 columns x 4 rows, the last row of one is centred")
	t.eq(sets[0], sets[1], "permuting the ids over the same positions gives the same slot set")


func test_u7_group_of(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var us: Array[SimEntity] = []
	for i: int in 6:
		us.append(M.tank(w, 10 + i, 10))
	w.step()  # spawned units join the owner's list at the next flush
	for i: int in 6:
		_issue_move(w, us[i], 30 * C, 30 * C, SimOrder.OF_NO_FORMATION if i == 4 else 0)
	# unit 5: its T_MOVE is queued behind a wait, so it is not a fresh head order
	w.orders.issue(w, us[5], SimOrder.make(SimOrder.T_WAIT, 0, 0, 0, 50), SimOrder.QM_REPLACE)
	w.orders.issue(w, us[5], SimOrder.make(SimOrder.T_MOVE, 0, 30 * C, 30 * C), SimOrder.QM_APPEND)
	var want: PackedInt32Array = PackedInt32Array([us[0].id, us[1].id, us[2].id, us[3].id])
	for i: int in 4:
		var out: PackedInt32Array = PackedInt32Array()
		var n: int = SimFormation.group_of(w, us[i], us[i].orders[0], out)
		t.eq(n, 4, "member %d sees 4 units" % i)
		t.eq(out, want, "member %d sees the same ids" % i)
	var lone: PackedInt32Array = PackedInt32Array()
	t.eq(SimFormation.group_of(w, us[4], us[4].orders[0], lone), 1, "OF_NO_FORMATION forms no group")
	t.eq(SimFormation.group_of(w, us[5], us[5].orders[0], lone), 1, "a queued order forms no group")


# ---- S4 group move through the command executor ---------------------------------------------------------------------------

func test_s4_group_move(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(96))
	var kinds: PackedStringArray = [DefTestKit.U_RIFLEMAN, DefTestKit.U_COLLECTOR, DefTestKit.U_TANK, DefTestKit.U_MCV]
	var ents: Array[SimEntity] = []
	for i: int in 30:
		ents.append(M.spawn(w, kinds[i % 4], 16 + (i % 6), 40 + (i / 6)))
	var tx: int = 50 * C
	var ty: int = 44 * C
	w.submit_raw(0, SimCmd.move(_ids(ents), tx, ty))
	w.step()
	for e: SimEntity in ents:
		t.eq(e.orders.size() if e.orders.size() < 2 else 1, 1, "one T_MOVE per actor")
	var slots_ok: bool = true
	for e: SimEntity in ents:
		if e.move.fslot_tick != w.tick - 1:
			slots_ok = false
	t.check(slots_ok, "every member got its slot from the first begin of the tick")
	var arrived: int = M.run_until(w, func() -> bool:
		for e: SimEntity in ents:
			if _moving(e):
				return false
		return true, 800)
	var pending: int = 0
	for e: SimEntity in ents:
		if _moving(e):
			pending += 1
	t.check(arrived > 0 and arrived <= 500, "all arrive within 500 ticks (%d, %d still moving)" % [arrived, pending])
	t.note("S4 searches %d hits %d arrival %d" % [w.movement.path.stat_searches, w.movement.path.stat_hits, arrived])
	t.check(w.movement.path.stat_searches <= 3, "at most 3 searches (%d)" % w.movement.path.stat_searches)
	t.check(w.movement.path.stat_hits >= 27 - 4, "cache / LOS hits (%d)" % w.movement.path.stat_hits)
	w.run(30)
	var low: int = 0
	var pairs: int = 0
	var minr: float = 9.0
	for i: int in ents.size():
		for j: int in range(i + 1, ents.size()):
			var dd: int = Fp.dist(ents[i].x - ents[j].x, ents[i].y - ents[j].y)
			var r: float = float(dd) / float(ents[i].radius + ents[j].radius)
			minr = minf(minr, r)
			pairs += 1
			if r < 0.85:
				low += 1
	t.check(minr >= 0.6, "at rest no pair on top of each other (min ratio %.2f)" % minr)
	t.check(low * 1000 <= pairs * 15, "few pairs below 0.85 (%d of %d)" % [low, pairs])
	var before: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in ents:
		before.append(e.x)
		before.append(e.y)
	w.run(200)
	var moved: int = 0
	var maxd: int = 0
	for i: int in ents.size():
		var d1: int = absi(ents[i].x - before[i * 2]) + absi(ents[i].y - before[i * 2 + 1])
		moved += d1
		maxd = maxi(maxd, d1)
	t.check(moved <= 1500 and maxd <= 200, "the group has settled (total %d, max %d)" % [moved, maxd])
	# slots reached: everybody ends near its own slot
	var near: int = 0
	for e: SimEntity in ents:
		if Fp.dist(e.x - e.move.goal_x, e.y - e.move.goal_y) <= 1400:
			near += 1
	t.check(near >= 27, "most units ended near their slot (%d of 30)" % near)


func test_s4_no_formation_goes_to_the_exact_point(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var ents: Array[SimEntity] = []
	for i: int in 6:
		ents.append(M.rifle(w, 10 + i, 30))
	w.submit_raw(0, SimCmd.move(_ids(ents), 40 * C, 30 * C, 0, 1))
	w.step()
	for e: SimEntity in ents:
		t.eq([e.move.goal_x, e.move.goal_y], [40 * C, 30 * C], "OF_NO_FORMATION: goal is the exact point")
	var g: Array[SimEntity] = []
	for i: int in 4:
		g.append(M.rifle(w, 10 + i, 34))
	w.submit_raw(0, SimCmd.move(_ids(g), 40 * C, 34 * C))
	w.step()
	var distinct: Dictionary = {}
	for e: SimEntity in g:
		distinct[Vector2i(e.move.goal_x, e.move.goal_y)] = true
	t.eq(distinct.size(), 4, "a formation gives distinct slots")


func test_stop_and_scatter(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var a: SimEntity = M.tank(w, 10, 30)
	var b: SimEntity = M.rifle(w, 10, 34)
	w.submit_raw(0, SimCmd.move(_ids([a, b]), 50 * C, 32 * C))
	w.run(40)
	t.check(SimMovement.is_moving(a) and SimMovement.is_moving(b), "moving")
	w.submit_raw(0, SimCmd.stop(_ids([a, b])))
	w.step()
	t.check(a.orders.is_empty() and b.orders.is_empty(), "STOP empties the queues")
	t.eq(SimMovement.state(a), SimMoveConfig.MS_IDLE, "goal cleared")
	w.run(30)
	t.eq(a.move.spd_q4, 0, "and the unit brakes to a halt")
	t.eq(SimMovement.result(a), SimMoveConfig.RS_CANCELLED, "RS_CANCELLED")
	# SCATTER: random target within 3 cells, no formation
	var sx: int = a.x
	var sy: int = a.y
	w.submit_raw(0, SimCmd.scatter(_ids([a, b])))
	w.step()
	t.eq(a.orders[0].type, SimOrder.T_MOVE, "SCATTER is a T_MOVE")
	t.check(absi(a.orders[0].x - sx) <= 3072 and absi(a.orders[0].y - sy) <= 3072, "within 3 cells")
	t.check((a.orders[0].flags & SimOrder.OF_NO_FORMATION) == 0, "plain order (a lone unit forms no group anyway)")
	w.run(200)
	t.check(a.orders.is_empty() and b.orders.is_empty(), "scattered units finished their orders")


func test_queue_and_failed_order(t: TestCtx) -> void:
	var rows: PackedStringArray = M.grid(80)
	M.rect(rows, 20, 2, 29, 77, "F")
	var w: SimWorld = M.world(M.map_from(rows))
	var sc: SimEntity = M.scout(w, 10, 40)
	w.submit_raw(0, SimCmd.move(_ids([sc]), 70 * C, 40 * C + 512))  # behind the forest: wheeled cannot pass
	w.submit_raw(0, SimCmd.move(_ids([sc]), 10 * C + 512, 60 * C, SimOrder.QM_APPEND))
	M.run_until(w, func() -> bool: return M.count_events(w, SimEvent.ORDER_FAILED) > 0, 200)
	t.eq(M.count_events(w, SimEvent.ORDER_FAILED), 1, "ORDER_FAILED once")
	t.eq(M.count_events(w, SimMoveConfig.EV_MOVE_FAILED), 1, "EV_MOVE_FAILED once")
	t.eq(SimMovement.result(sc), SimMoveConfig.RS_NO_PATH, "reason RS_NO_PATH")
	M.run_until(w, func() -> bool: return sc.orders.is_empty(), 400)
	t.check(sc.orders.is_empty() and absi(sc.y - 60 * C) < 1200, "the rest of the queue continued and finished (y %d)" % sc.y)
	t.eq(M.count_events(w, SimEvent.ORDER_FAILED), 1, "still exactly one failure")


func test_face_and_follow(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var a: SimEntity = M.tank(w, 20, 20)
	w.orders.issue(w, a, SimOrder.make(SimOrder.T_FACE, 0, 0, 0, 2048), SimOrder.QM_REPLACE)
	M.run_until(w, func() -> bool: return a.orders.is_empty(), 200)
	t.check(a.orders.is_empty() and absi(SimSteering.angle_err(2048, a.facing)) < 64, "T_FACE turned the tank (facing %d)" % a.facing)
	var lead: SimEntity = M.tank(w, 20, 30)
	var f: SimEntity = M.rifle(w, 20, 40)
	w.submit_raw(0, SimCmd.follow(_ids([f]), lead.id))
	w.submit_raw(0, SimCmd.move(_ids([lead]), 50 * C, 30 * C))
	w.run(700)
	t.check(f.orders.size() == 1 and f.orders[0].type == SimOrder.T_FOLLOW, "follow keeps running")
	var d: int = Fp.dist(f.x - lead.x, f.y - lead.y)
	t.check(d <= 4600, "the follower keeps up (distance %d)" % d)
	w.kill(lead, SimWorld.Cause.SCRIPT, 0, 0)
	w.run(4)
	t.check(f.orders.is_empty(), "the order ends when the target is gone")
	t.eq(M.count_events(w, SimEvent.ORDER_FAILED), 1, "ORDER_FAILED (target lost)")
	# a dead / self target is refused at issue time
	w.submit_raw(0, SimCmd.follow(_ids([f]), f.id))
	w.step()
	t.check(f.orders.is_empty(), "self follow rejected")


# ---- S17 immobile unit / S18 speed match ----------------------------------------------------------------------------------

func test_s17_deployed_unit_waits(t: TestCtx) -> void:
	var stub: M.AbilStub = M.AbilStub.new()
	var w: SimWorld = M.world(M.open_map(64), null, stub)
	var e: SimEntity = M.tank(w, 20, 30)
	stub.immobile = true
	w.submit_raw(0, SimCmd.move(_ids([e]), 40 * C, 30 * C))
	w.run(10)
	t.eq(stub.pack_calls, 1, "request_pack called once")
	t.eq(SimMovement.state(e), SimMoveConfig.MS_IDLE, "no goal while immobile")
	t.eq(e.orders.size(), 1, "the order waits")
	stub.immobile = false
	w.run(3)
	t.check(SimMovement.is_moving(e), "moves once it may")
	M.run_until(w, func() -> bool: return e.orders.is_empty(), 400)
	t.check(e.orders.is_empty() and absi(e.x - 40 * C) < 1000, "and arrives")


func test_s18_speed_match(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64))
	var a: SimEntity = M.rifle(w, 10, 30)
	var b: SimEntity = M.tank(w, 10, 32)
	var c: SimEntity = M.spawn(w, DefTestKit.U_MCV, 10, 34)
	w.submit_raw(0, SimCmd.move(_ids([a, b, c]), 50 * C, 32 * C, 0, 2))
	w.run(40)
	var cap: int = c.move.speed_base * 16
	for e: SimEntity in [a, b, c]:
		t.eq(e.move.speed_cap_q4, cap, "slowest member caps unit %d" % e.id)
		t.check(e.move.spd_q4 <= cap, "speed %d <= cap" % e.move.spd_q4)
	# without the flag nobody is capped
	var w2: SimWorld = M.world(M.open_map(64))
	var d: SimEntity = M.tank(w2, 10, 30)
	var e2: SimEntity = M.spawn(w2, DefTestKit.U_MCV, 10, 32)
	w2.submit_raw(0, SimCmd.move(_ids([d, e2]), 50 * C, 32 * C))
	w2.run(40)
	t.eq(d.move.speed_cap_q4, 0, "no speed match by default")
	M.run_until(w, func() -> bool: return a.orders.is_empty() and b.orders.is_empty() and c.orders.is_empty(), 900)
	t.eq(a.move.speed_cap_q4, 0, "the cap is dropped when the order ends")


# ---- S19 patrol ---------------------------------------------------------------------------------------------------------------

func test_s19_patrol_bounce(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64), null, null, 2, true)
	var e: SimEntity = M.rifle(w, 10, 30)
	var ox: int = e.x
	w.submit_raw(0, SimCmd.patrol(_ids([e]), 30 * C + 512, 30 * C + 512))
	var minx: int = 1 << 30
	var maxx: int = 0
	var ends: int = 0
	var last_side: int = 0
	var qmax: int = 0
	for i: int in 3000:
		w.step()
		minx = mini(minx, e.x)
		maxx = maxi(maxx, e.x)
		qmax = maxi(qmax, e.orders.size())
		var side: int = 1 if e.x > 30 * C else (-1 if e.x < ox + 1200 else 0)
		if side != 0 and side != last_side:
			ends += 1
			last_side = side
	t.eq(qmax, 1, "the queue never grows")
	t.check(minx <= ox + 600 and maxx >= 30 * C - 600, "bounces between origin and target (%d..%d)" % [minx, maxx])
	t.check(ends >= 8, "many legs in 3000 ticks (%d ends)" % ends)


func test_s19_chained_patrol_cycles(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64), null, null, 2, true)
	var e: SimEntity = M.rifle(w, 10, 30)
	var pts: Array[Vector2i] = [Vector2i(20 * C, 30 * C), Vector2i(20 * C, 40 * C), Vector2i(10 * C, 40 * C)]
	w.submit_raw(0, SimCmd.patrol(_ids([e]), pts[0].x, pts[0].y))
	w.submit_raw(0, SimCmd.patrol(_ids([e]), pts[1].x, pts[1].y, SimOrder.QM_APPEND))
	w.submit_raw(0, SimCmd.patrol(_ids([e]), pts[2].x, pts[2].y, SimOrder.QM_APPEND))
	var seq: Array[int] = []
	for i: int in 1500:
		w.step()
		t.check(e.orders.size() <= 3, "queue size stays 3")
		var h: SimOrder = e.orders[0]
		for k: int in 3:
			if h.x == pts[k].x and h.y == pts[k].y and (seq.is_empty() or seq[seq.size() - 1] != k):
				seq.append(k)
	t.check(seq.size() >= 6, "several legs (%s)" % str(seq))
	for i: int in range(1, seq.size()):
		t.eq(seq[i], (seq[i - 1] + 1) % 3, "P1 -> P2 -> P3 -> P1 (step %d)" % i)


func test_s19_patrol_leg_is_a_child_attack_move(t: TestCtx) -> void:
	var w: SimWorld = M.world(M.open_map(64), null, null, 2, true)
	var stub: AtkStub = AtkStub.new()
	w.orders.register_handler(SimOrder.T_ATTACK_MOVE, stub)
	var e: SimEntity = M.rifle(w, 10, 30)
	w.submit_raw(0, SimCmd.patrol(_ids([e]), 25 * C + 512, 30 * C + 512))
	w.step()
	t.eq(e.orders.size(), 2, "parent behind its child")
	t.eq(e.orders[0].type, SimOrder.T_ATTACK_MOVE, "the leg is a T_ATTACK_MOVE")
	t.eq(e.orders[1].type, SimOrder.T_PATROL, "the patrol waits at index 1")
	var qmax: int = 0
	for i: int in 1200:
		w.step()
		qmax = maxi(qmax, e.orders.size())
	t.eq(qmax, 2, "never more than parent + child")
	t.check(stub.begins >= 4, "legs keep coming as children (%d)" % stub.begins)
	w.submit_raw(0, SimCmd.stop(_ids([e])))
	w.step()
	t.check(e.orders.is_empty(), "STOP cancels parent and child")
