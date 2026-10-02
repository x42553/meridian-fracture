extends RefCounted
## Entity lifecycle, cleanup and victory (sim_core 5.4 / 5.9, 10.1 test_sim_lifecycle): defeat cascade, deaths in
## id order, tether chains, lingering corpses, wrecks, expiry, elimination and match end.

const K := preload("res://tests/support/sim_test_kit.gd")


## Keeps every corpse for 5 ticks (an aircraft crash sequence stand-in).
class Linger:
	extends SimCombatSystem
	var dying: PackedInt32Array = PackedInt32Array()

	func on_dying(world: SimWorld, e: SimEntity, _cause: int, _kid: int, _kpid: int) -> void:
		dying.append(e.id)
		world.remove_deferred(e.id, world.tick + 5)


func _units_left(w: SimWorld, pid: int) -> int:
	var n: int = 0
	for e: SimEntity in w.units_of(pid):
		if (e.flags & SimFlags.F_GONE) == 0:
			n += 1
	return n


func test_defeat_cascade_timeline(t: TestCtx) -> void:
	var w: SimWorld = K.make_world({"players": 3, "opts": {"invariants_every": 1}})
	for i: int in 20:
		K.spawn_rifle(w, 1, 50 * 1024 + i * 300, 50 * 1024)
	w.step()
	w.submit_raw(1, SimCmd.resign(0))
	var left: PackedInt32Array = PackedInt32Array()
	for _i: int in 5:
		w.step()
		left.append(_units_left(w, 1))
	t.eq(left, PackedInt32Array([14, 8, 2, 0, 0]), "units left after each step: at most 6 die per tick")
	t.eq(w.structures_of(1).size(), 0, "the HQ died once the units were gone (step 4)")
	t.check_false(w.is_match_over(), "two other teams remain")
	t.eq(w.players[1].elim_reason, SimPlayer.Elim.RESIGN, "reason")
	t.eq(w.players[1].unit_count, 0, "counters")


func test_kill_is_immediate_but_removal_waits(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	var e: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	w.step()
	var out: PackedInt32Array = PackedInt32Array()
	w.kill(e, SimWorld.Cause.DAMAGE)
	t.check((e.flags & SimFlags.F_DEAD) != 0 and e.hp == 0, "F_DEAD and hp 0 at once")
	t.check_false(w.is_alive(e.id), "not alive")
	t.eq(w.query_circle(30000, 30000, 100, out), 0, "invisible to spatial queries")
	t.eq(w.get_entity(e.id), e, "get_entity still returns it before stage 11")
	t.eq(w.players[0].unit_count, 0, "no longer counted")
	w.kill(e, SimWorld.Cause.SCRIPT)  # idempotent
	w.step()
	t.is_null(w.get_entity(e.id), "gone after stage 11")
	t.eq(w.units.size(), 0, "compacted out of the lists")
	t.eq([w.players[0].st_units_lost, w.combat.dying.size() if w.combat is K.CombatStub else -1], [1, 1] as Array, "one loss, one on_dying")


func test_wreck_lifecycle(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	var mine: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)  # id 3
	var tank: SimEntity = K.spawn_tank(w, 1, 60000, 60000)  # id 4
	var own: SimEntity = K.spawn_tank(w, 1, 61000, 60000)  # id 5
	w.step()
	var born: int = w.tick
	w.kill(tank, SimWorld.Cause.DAMAGE, mine.id)
	w.step()
	t.eq(w.wrecks.size(), 1, "an enemy kill leaves a wreck")
	var wr: SimEntity = w.wrecks[0]
	t.eq([wr.kind, wr.owner, wr.def_idx, wr.paid_cost, wr.hp, wr.hp_max], [SimEntity.Kind.WRECK, 1, tank.def_idx, 850, 50, 50] as Array, "wreck: kind, original owner, def, paid_cost, hp 50/50")
	t.check((wr.flags & SimFlags.F_NO_SALVAGE) == 0 and (wr.flags & SimFlags.F_TEMPORARY) != 0, "salvageable, temporary")
	t.eq(wr.expire_tick, born + 1200, "expires 1200 ticks after it was spawned")
	t.eq([w.players[0].st_units_killed, w.players[1].st_units_lost], [1, 1] as Array, "kill statistics: credited to the killer, lost to the owner")
	t.eq(w.players[1].unit_count, 1, "the wreck is not counted")
	w.kill(own, SimWorld.Cause.DAMAGE, tank.id, 1)  # friendly fire
	w.step()
	t.check((w.wrecks[1].flags & SimFlags.F_NO_SALVAGE) != 0, "friendly-fire wreck has F_NO_SALVAGE")
	t.eq(w.players[1].st_units_killed, 0, "no kill credit for an own-owner kill")
	w.run(1196)
	t.check(w.get_entity(wr.id) != null, "the wreck is still there shortly before its expiry")
	w.run(6)
	t.is_null(w.get_entity(wr.id), "and gone after it")
	t.eq(SimInvariants.check(w), PackedStringArray(), "invariants")
	var scut: SimEntity = K.spawn_tank(w, 0, 20000, 20000)
	w.step()
	var n: int = w.wrecks.size()
	w.submit_raw(0, SimCmd.scuttle(PackedInt32Array([scut.id])))
	w.step()
	t.eq(w.wrecks.size(), n, "SCUTTLE leaves no wreck")


func test_deaths_in_id_order_and_tethers(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	var rifle: int = K.unit_def(DefTestKit.U_RIFLEMAN)
	var g: Array[SimEntity] = []
	g.append(K.spawn_rifle(w, 0, 30000, 30000))  # g1
	g.append(w.spawn_unit(rifle, 0, 30100, 30000, 0, SimFlags.F_TETHERED, 0, g[0].id))  # g2 child of g1
	g.append(w.spawn_unit(rifle, 0, 30200, 30000, 0, SimFlags.F_TETHERED, 0, g[1].id))  # g3 child of g2
	g.append(w.spawn_unit(rifle, 0, 30300, 30000, 0, SimFlags.F_TETHERED, 0, g[0].id))  # g4 child of g1
	t.check((g[0].flags & SimFlags.F_HAS_CHILDREN) != 0, "F_HAS_CHILDREN set on the parent")
	w.step()
	var stub: K.CombatStub = w.combat as K.CombatStub
	w.kill(g[0], SimWorld.Cause.SCRIPT)
	w.step()
	t.eq(stub.dying, PackedInt32Array([g[0].id, g[1].id, g[3].id, g[2].id]), "one tick, in generations, ascending id inside a generation")
	t.eq(w.units_of(0).size(), 0, "the whole chain is gone in that tick")
	t.eq(SimInvariants.check(w), PackedStringArray(), "no zombies (INV-17)")
	# kills requested 3, 1, 4, 2 -> hooks 1, 2, 3, 4
	var a: Array[SimEntity] = []
	for i: int in 4:
		a.append(K.spawn_rifle(w, 0, 40000 + i * 100, 30000))
	w.step()
	stub.dying.resize(0)
	for i: int in [2, 0, 3, 1]:
		w.kill(a[i], SimWorld.Cause.SCRIPT)
	w.step()
	t.eq(stub.dying, PackedInt32Array([a[0].id, a[1].id, a[2].id, a[3].id]), "deaths run in ascending id order")


func test_lingering_corpse(t: TestCtx) -> void:
	var lg: Linger = Linger.new()
	var w: SimWorld = K.make_world({"combat_stub": false, "opts": {"systems": [lg], "invariants_every": 1}})
	var e: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	w.step()
	var t0: int = w.tick
	w.kill(e, SimWorld.Cause.DAMAGE)
	w.step()
	t.check(w.get_entity(e.id) != null, "the corpse stays")
	t.eq([e.hp, w.players[0].unit_count], [0, 0] as Array, "dead, not counted")
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(w.query_circle(30000, 30000, 100, out), 0, "invisible to queries")
	w.set_pos(e, 30500, 30000)  # combat may still move it
	w.run(4)
	t.check(w.get_entity(e.id) != null, "still present while the deadline is ahead")
	t.eq(w.tick, t0 + 5, "tick: the deadline (t0 + 5) is the next simulated tick")
	w.step()
	t.is_null(w.get_entity(e.id), "removed at stage 11 of the first tick >= the deadline")
	t.eq(lg.dying.size(), 1, "on_dying ran once")


func test_remove_entity_and_expiry(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	var a: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	var b: SimEntity = K.spawn_rifle(w, 0, 31000, 30000)
	var c: SimEntity = w.spawn_unit(K.unit_def(DefTestKit.U_RIFLEMAN), 0, 32000, 30000, 0, SimFlags.F_TEMPORARY | SimFlags.F_SUMMONED | SimFlags.F_EXPIRE_KILLS)
	w.step()
	t.check(w.remove_entity(a.id, SimEvent.REM_CONSUMED), "remove_entity")
	t.check_false(w.remove_entity(a.id, SimEvent.REM_CONSUMED), "second call: already leaving")
	t.check_false(w.remove_entity(9999, 0), "unknown id")
	t.eq(w.players[0].unit_count, 2, "counters drop when the removal is queued (b and the summon remain)")
	w.remove_deferred(b.id, w.tick + 3)
	c.expire_tick = w.tick + 2
	w.events.clear()
	w.run(3)
	var reasons: Dictionary = {}
	for i: int in w.events.count():
		if w.events.data[i * 10] == SimEvent.REMOVED:
			reasons[w.events.data[i * 10 + 4]] = w.events.data[i * 10 + 8]
	t.eq(reasons.get(a.id), SimEvent.REM_CONSUMED, "silent removal carries its reason")
	t.eq(reasons.get(c.id), SimEvent.REM_KILLED, "an F_EXPIRE_KILLS summon dies through on_dying (REM_KILLED)")
	t.check(w.get_entity(b.id) != null, "deferred removal has not fired yet")
	w.step()
	t.is_null(w.get_entity(b.id), "deferred removal of a live entity fires at its tick")
	t.eq((w.combat as K.CombatStub).dying, PackedInt32Array([c.id]), "only the summon went through on_dying (cause EXPIRE)")


func test_victory_cases(t: TestCtx) -> void:
	# last opponent's HQ dies -> NO_ASSETS elimination in the same tick, winner = team 1
	var w: SimWorld = K.make_world()
	w.step()
	w.kill(w.get_entity(2), SimWorld.Cause.DAMAGE, 1, 0)
	w.step()
	t.eq([w.players[1].eliminated, w.players[1].elim_reason], [1, SimPlayer.Elim.NO_ASSETS] as Array, "no structures and no MCV -> eliminated")
	t.check(w.is_match_over(), "match over")
	t.eq(w.match_result(), {"winner_team": 1, "reason": SimWorld.EndReason.ELIMINATION}, "winner team 1")
	t.eq(w.end_tick, 1, "end_tick = the tick simulated")
	var tick: int = w.tick
	w.run(5)
	t.eq(w.tick, tick, "the tick is frozen after the match")
	t.is_null(w.spawn_unit(0, 0, 0, 0), "spawn returns null")
	var last: int = w.events.count() - 1
	t.eq(w.events.data[last * 10], SimEvent.MATCH_END, "MATCH_END is the last event")
	t.eq(w.events.data.slice(last * 10 + 4, last * 10 + 7), PackedInt32Array([1, SimWorld.EndReason.ELIMINATION, 1]), "winner, reason, tick")
	# an MCV keeps its owner alive
	var m: SimWorld = K.make_world()
	K.spawn_unit_id(m, DefTestKit.U_MCV, 1, 60000, 60000)
	m.step()
	m.kill(m.get_entity(2), SimWorld.Cause.DAMAGE)
	m.run(2)
	t.check_false(m.is_match_over(), "an MCV-class unit prevents defeat")
	# a temporary MCV does not
	var tmp: SimWorld = K.make_world()
	tmp.spawn_unit(K.unit_def(DefTestKit.U_MCV), 1, 60000, 60000, 0, SimFlags.F_TEMPORARY)
	tmp.step()
	tmp.kill(tmp.get_entity(2), SimWorld.Cause.DAMAGE)
	tmp.step()
	t.check(tmp.is_match_over(), "temporary units never keep a player alive")
	# allies win together (4 players, teams 1 1 2 2)
	var a: SimWorld = K.make_world({"players": 4, "teams": PackedInt32Array([1, 1, 2, 2])})
	a.step()
	a.submit_raw(2, SimCmd.resign(0))
	a.step()
	t.check_false(a.is_match_over(), "one team-2 player left")
	a.submit_raw(3, SimCmd.resign(0))
	a.step()
	t.eq(a.match_result(), {"winner_team": 1, "reason": SimWorld.EndReason.ELIMINATION}, "allies win together")
	# everybody dies in the same tick -> draw
	var d: SimWorld = K.make_world()
	d.step()
	d.kill(d.get_entity(1), SimWorld.Cause.SCRIPT)
	d.kill(d.get_entity(2), SimWorld.Cause.SCRIPT)
	d.step()
	t.eq(d.match_result(), {"winner_team": -1, "reason": SimWorld.EndReason.DRAW}, "no team left = draw")
	# no human left -> NO_HUMANS (3 players, human pid 0 resigns while two AIs of different teams remain)
	var h: SimWorld = K.make_world({"players": 3})
	h.step()
	h.submit_raw(0, SimCmd.resign(0))
	h.step()
	t.eq(h.match_result(), {"winner_team": -1, "reason": SimWorld.EndReason.NO_HUMANS}, "no human left")
	# sandbox: victory = 0 never ends and never eliminates by assets
	var s: SimWorld = K.make_world({"rules": {"victory": 0}})
	s.step()
	s.kill(s.get_entity(2), SimWorld.Cause.SCRIPT)
	s.run(3)
	t.check(not s.is_match_over() and s.players[1].eliminated == 0, "victory = 0 is a sandbox")
	# a lone participant is not a match
	var one: SimWorld = K.make_world({"players": 1})
	one.run(3)
	t.check_false(one.is_match_over(), "a single participant never ends the match")


func test_hash_coverage(t: TestCtx) -> void:
	t.eq(K.check_hash_coverage(SimEntity, SimEntity.HASH_EXEMPT), PackedStringArray(), "every non-exempt SimEntity field is hashed")
	t.eq(K.check_hash_coverage(SimPlayer, SimPlayer.HASH_EXEMPT), PackedStringArray(), "every non-exempt SimPlayer field is hashed")
