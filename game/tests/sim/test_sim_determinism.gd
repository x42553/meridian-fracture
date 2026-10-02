extends RefCounted
## Determinism (sim_core 10.1 test_sim_determinism, 10.3, 10.4): the S-CORE-1 golden scenario, double runs, part
## attribution and sensitivity. The golden numbers are regenerated from THIS implementation on the data domain's
## `DefTestKit.small_data()` (the spec's numbers assume its own fixture and a hashing combat stand-in); when the
## kernel, the small data or the kit change results, bump SimConfig.SIM_VERSION and update GOLDEN_* below (print
## `w.checksum_log`, `w.checksum()`, `w.events.digest()` after `K.s_core_1_world()` + 200 scripted steps).

const K := preload("res://tests/support/sim_test_kit.gd")

## [tick, checksum] pairs of S-CORE-1 (ticks 0, 20 ... 100; the resign at s = 100 ends the match in that step).
const GOLDEN_LOG: Array = [0, 1649596721, 20, 4127926599, 40, 1483655847, 60, 3687723264, 80, 223597224, 100, 2585471319]
const GOLDEN_FINAL: int = 3327479964
const GOLDEN_EVENTS: int = 2831136714


class HashStage:
	extends SimVisionSystem
	var v: int = 0

	func hash_state(_world: SimWorld, buf: PackedInt32Array) -> void:
		buf.append(v)


func _s1() -> SimWorld:
	var w: SimWorld = K.s_core_1_world()
	K.run_script(w, 200, Callable(K, "s_core_1_script"))
	return w


func test_golden_scenario(t: TestCtx) -> void:
	var w: SimWorld = _s1()
	var want: PackedInt64Array = PackedInt64Array(GOLDEN_LOG)
	t.eq(w.checksum_log, want, "checkpoint chain 0..100")
	t.eq(w.checksum(), GOLDEN_FINAL, "final checksum")
	t.eq(w.events.digest(), GOLDEN_EVENTS, "event digest")
	t.eq([w.match_state, w.winner_team, w.end_reason, w.end_tick, w.tick], [SimWorld.MATCH_ENDED, 1, SimWorld.EndReason.ELIMINATION, 100, 101] as Array, "final state (structure identical to the spec's)")
	var ids: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in w.entities:
		ids.append(e.id)
	t.eq(ids, PackedInt32Array([1, 3, 4, 5, 6, 7, 9, 14]), "8 entities remain")
	t.eq([w.get_entity(1).x, w.get_entity(1).y], [20992, 20992] as Array, "HQ 1")
	for id: int in [5, 6, 7, 9]:
		t.eq([w.get_entity(id).x, w.get_entity(id).y, w.get_entity(id).orders.size()], [30720, 30720, 0] as Array, "unit %d arrived, queue empty" % id)
	t.eq([w.get_entity(3).x, w.get_entity(3).y, w.get_entity(4).x, w.get_entity(4).y], [21442, 22306, 24082, 26578] as Array, "scattered rifles 3 and 4 (the spec's positions)")
	var wr: SimEntity = w.get_entity(14)
	t.eq([wr.kind, wr.owner, wr.def_idx, wr.hp, wr.paid_cost, wr.expire_tick, wr.x, wr.y], [SimEntity.Kind.WRECK, 1, K.unit_def(DefTestKit.U_TANK), 50, 850, 1260, 57299, 58810] as Array, "wreck 14")
	t.eq(wr.flags, SimFlags.F_TEMPORARY | SimFlags.F_UNTARGETABLE | SimFlags.F_NO_SELECT | SimFlags.F_NO_UNIT_CAP, "wreck flags")
	var census: Dictionary = {}
	for i: int in w.events.count():
		var ty: int = w.events.data[i * 10]
		census[ty] = int(census.get(ty, 0)) + 1
	t.eq(w.events.count(), 26, "26 events")
	t.eq(census, {SimEvent.SPAWNED: 14, SimEvent.NAV_CHANGED: 3, SimEvent.REMOVED: 6, SimEvent.CMD_REJECTED: 1, SimEvent.PLAYER_ELIMINATED: 1, SimEvent.MATCH_END: 1}, "event census")
	var p0: SimPlayer = w.players[0]
	var p1: SimPlayer = w.players[1]
	t.eq([p0.st_units_built, p0.st_units_lost, p0.st_units_killed, p0.st_cmds, p0.st_peak_units], [7, 1, 1, 3, 7] as Array, "P0 counters")
	t.eq([p1.st_units_built, p1.st_units_lost, p1.st_units_killed, p1.st_cmds, p1.st_rejected], [4, 4, 0, 3, 1] as Array, "P1 counters")
	t.eq(w.rng.get_state(), PackedInt32Array([1164917686, 1157485396, -1740605161, -188843546]), "RNG state after the scatter (the spec's lanes)")
	t.eq(SimInvariants.check(w), PackedStringArray(), "invariants clean")
	t.eq(w.checksum_parts_at(100).size(), 16, "16 parts at the last checkpoint")


func test_invariants_every_step(t: TestCtx) -> void:
	var w: SimWorld = K.s_core_1_world({"opts": {"invariants_every": 1}})
	var seen: PackedStringArray = PackedStringArray()
	Log.sink = func(_lv: int, _tag: String, msg: String) -> void: seen.append(msg)
	K.run_script(w, 110, Callable(K, "s_core_1_script"))
	Log.sink = Callable()
	t.eq(seen, PackedStringArray(), "no invariant violation in any of the steps")
	var b: SimWorld = K.brawl_world()
	var bad: PackedStringArray = PackedStringArray()
	for s: int in 6:
		K.brawl_run(b, 100, 100 + s)
		bad.append_array(SimInvariants.check(b))
	t.eq(bad, PackedStringArray(), "brawl: invariants clean every 100 steps")


func test_double_run(t: TestCtx) -> void:
	var r: Dictionary = K.double_run(Callable(K, "s_core_1_world"), Callable(K, "s_core_1_script"), 200)
	t.check(r["ok"], "S-CORE-1: identical chains, event digests, checksums and dump_state texts")
	var b: SimWorld = K.brawl_world()
	var c: SimWorld = K.brawl_world()
	K.brawl_run(b, 300)
	K.brawl_run(c, 300)
	t.check(b.checksum_log == c.checksum_log and b.dump_state() == c.dump_state() and b.events.digest() == c.events.digest(), "brawl double run")
	var d: SimWorld = K.brawl_world()
	K.brawl_run(d, 300, 778)
	t.ne(d.checksum(), b.checksum(), "another command seed differs")
	t.ne(K.s_core_1_world({"seed": 999}).checksum(), K.s_core_1_world().checksum(), "another match seed differs")


func _parts(w: SimWorld) -> PackedInt32Array:
	return SimStateHash.compute(w)["parts"]


func _changed(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in a.size():
		if a[i] != b[i]:
			out.append(i)
	return out


func test_part_attribution(t: TestCtx) -> void:
	var hs: HashStage = HashStage.new()
	var w: SimWorld = K.make_world({"opts": {"systems": [hs]}})
	w.run(3)
	var base: PackedInt32Array = _parts(w)
	var base_sum: int = w.checksum()
	w.next_proj_id += 1
	t.eq(_changed(base, _parts(w)), PackedInt32Array([0]), "next_proj_id -> world")
	w.next_proj_id -= 1
	w.rng.next_u32()
	t.eq(_changed(base, _parts(w)), PackedInt32Array([1]), "one rng draw -> rng")
	w.rng.set_state(SimRng.new(w.config.seed_value).get_state())
	var fresh: SimRng = SimRng.new(w.config.seed_value)
	t.eq(w.rng.get_state(), fresh.get_state(), "rng restored")
	w.players[0].credits += 1
	t.eq(_changed(base, _parts(w)), PackedInt32Array([2]), "credits -> players")
	w.players[0].credits -= 1
	w.get_entity(1).hp -= 1
	t.eq(_changed(base, _parts(w)), PackedInt32Array([3]), "one hp point -> entities")
	w.get_entity(1).hp += 1
	w.get_entity(1).flags |= 1 << 34
	t.eq(_changed(base, _parts(w)), PackedInt32Array([3]), "flags bit 34 (high word) is hashed")
	w.get_entity(1).flags &= ~(1 << 34)
	w.get_entity(1).prev_x += 1
	t.eq(_changed(base, _parts(w)), PackedInt32Array([3]), "prev_x is hashed")
	w.get_entity(1).prev_x -= 1
	hs.v = 7
	t.eq(_changed(base, _parts(w)), PackedInt32Array([5 + 9]), "system-private state -> that stage's part (vision = stage 10)")
	hs.v = 0
	t.eq(w.checksum(), base_sum, "undoing every mutation restores the checksum")
	w.map.occupy_cells(500, PackedInt32Array([5 * 96 + 5]))
	t.eq(_changed(base, _parts(w)), PackedInt32Array([4]), "map occupancy -> map")


func test_sensitivity(t: TestCtx) -> void:
	var a: SimWorld = K.make_world()
	var b: SimWorld = K.make_world()
	var u: SimEntity = K.spawn_rifle(a, 0, 30000, 30000)
	var v: SimEntity = K.spawn_rifle(b, 0, 30000, 30000)
	a.submit_raw(0, SimCmd.move(PackedInt32Array([u.id]), 40000, 40000))
	b.submit_raw(0, SimCmd.move(PackedInt32Array([v.id]), 40001, 40000))
	a.run(20)
	b.run(20)
	t.ne(a.checksum(), b.checksum(), "one differing command field changes the chain")
	var c: SimWorld = K.make_world()
	K.spawn_rifle(c, 0, 30000, 30000)
	c.step()
	c.get_entity(3).hp -= 1
	var d: SimWorld = K.make_world()
	K.spawn_rifle(d, 0, 30000, 30000)
	d.step()
	t.ne(c.checksum(), d.checksum(), "one hp point changes the checksum")
	t.eq(K.make_world().checksum(), K.make_world().checksum(), "identical inputs agree")
