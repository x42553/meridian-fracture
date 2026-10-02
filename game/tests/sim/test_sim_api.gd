extends RefCounted
## SimWorld public API (sim_core 3.4.4 - 3.4.7, 10.1 test_sim_api): credits, cap, containers, queries and filters,
## hit points, ownership transfer, footprints (map contract), fog wrappers, motion bookkeeping.

const K := preload("res://tests/support/sim_test_kit.gd")


class HideAllFog:
	extends SimFogApi

	func entity_visible(_pid: int, _e: SimEntity) -> bool:
		return false


func test_credits(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	w.players[1].handicap = 120
	t.eq(w.add_credits(0, 500, SimEvent.CASH_HARVEST, 100, 200, 9), 500, "harvest at 100 % is exact")
	t.eq(w.players[0].credits, 8000, "credits")
	t.eq(w.players[0].st_credits_earned, 500, "earned")
	var ev: PackedInt32Array = w.events.data.slice(w.events.data.size() - 10)
	t.eq(ev, PackedInt32Array([SimEvent.CASH, 0, 100, 200, 0, 500, 8000, SimEvent.CASH_HARVEST, 9, 0]), "CASH event: pid, delta, total, reason, source; x,y in the header")
	var paid: int = 0
	for _i: int in 5:
		paid += w.add_credits(1, 1, SimEvent.CASH_HARVEST)
	t.eq(paid, 6, "five 1-credit pulses at 120 % pay exactly 6")
	t.eq(w.players[1].income_frac, 0, "remainder carried back to 0")
	t.eq(w.add_credits(1, 100, SimEvent.CASH_SELL), 100, "sell is never scaled")
	t.eq(w.add_credits(1, 100, SimEvent.CASH_REFUND), 100, "refund is never scaled")
	t.check(w.try_spend(0, 1000), "spend 1000")
	t.eq(w.players[0].credits, 7000, "after spending")
	t.check_false(w.try_spend(0, 999999), "cannot overspend")
	t.eq(w.players[0].credits, 7000, "credits intact after a refused spend")
	t.eq(w.players[0].st_credits_spent, 1000, "spent")
	var before: int = w.players[1].st_credits_spent
	w.add_credits(1, 50, SimEvent.CASH_REFUND)
	t.eq(w.players[1].st_credits_spent, before - 50, "a refund lowers the net spend")
	var n: int = w.events.count()
	w.add_credits(0, 5, SimEvent.CASH_HARVEST, 0, 0, 0, true)
	t.eq(w.events.count(), n, "silent suppresses the CASH event")
	var h: SimWorld = K.make_world()
	h.players[1].handicap = 120  # start credits use the config handicap, checked below
	var cfg: SimMatchConfig = K.make_config(2)
	cfg.players[1].handicap = 120
	t.eq(SimWorld.create(K.data(), cfg, K.make_map()).players[1].credits, 9000, "start credits x handicap")


func test_cap_and_counters(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	K.spawn_rifle(w, 0, 30720, 30720)
	K.spawn_rifle(w, 0, 31720, 30720)
	t.eq(w.unit_cap_room(0), 148, "two rifles")
	var col: SimEntity = K.spawn_collector(w, 0, 32720, 30720)
	t.eq(w.unit_cap_room(0), 148, "a pop-0 unit is free")
	t.check((col.flags & SimFlags.F_NO_UNIT_CAP) != 0, "F_NO_UNIT_CAP set at spawn")
	t.eq(w.players[0].st_units_built, 3, "produced units count as built")
	t.eq(w.players[0].st_peak_units, 2, "peak")
	w.step()
	w.kill(w.get_entity(3), SimWorld.Cause.SCRIPT)
	t.eq(w.unit_cap_room(0), 149, "kill drops the counter at once")
	t.eq(w.players[0].rebuilders, 0, "no rebuilders")
	var mcv: SimEntity = K.spawn_unit_id(w, DefTestKit.U_MCV, 0, 40000, 30720)
	t.eq(w.players[0].rebuilders, 1, "an MCV is a rebuilder")
	var tmp: SimEntity = w.spawn_unit(K.unit_def(DefTestKit.U_MCV), 0, 40000, 32000, 0, SimFlags.F_TEMPORARY, 0, 0, SimEvent.SPAWN_SUMMONED)
	t.eq(w.players[0].rebuilders, 1, "a temporary MCV never counts as an asset")
	t.check(mcv != null and tmp != null, "spawned")


func test_spawn_rules(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	var rifle: int = K.unit_def(DefTestKit.U_RIFLEMAN)
	t.is_null(w.spawn_unit(99, 0, 0, 0), "bad def")
	t.is_null(w.spawn_unit(rifle, 5, 0, 0), "owner beyond the players")
	t.is_null(w.spawn_unit(rifle, -2, 0, 0), "owner below -1")
	var n: SimEntity = w.spawn_unit(rifle, -1, 5000, 5000)
	t.not_null(n, "neutral owner allowed")
	t.eq(n.team, -1, "neutral team")
	t.eq(w.units_of(-1).size(), 0, "parked until the next flush")
	w.step()
	t.eq(w.units_of(-1).size(), 1, "listed after the stage")
	var e: SimEntity = w.spawn_unit(rifle, 0, -500, 99999999, 5000)
	t.eq([e.x, e.y, e.facing], [0, 96 * 1024 - 1, 5000 & 4095], "position clamped into the map, facing wrapped")
	t.eq(e.born, w.tick, "born")
	t.eq(w.events.data[w.events.data.size() - 10], SimEvent.SPAWNED, "SPAWNED is the entity's first event")
	# eliminated owner cannot spawn (wrecks excepted), match end freezes spawning
	w.eliminate(1, SimPlayer.Elim.SCRIPT)
	t.is_null(w.spawn_unit(rifle, 1, 0, 0), "eliminated owner")
	var dead: SimEntity = w.spawn_unit(rifle, 0, 9000, 9000)
	w.eliminate(0, SimPlayer.Elim.SCRIPT)
	t.not_null(w.spawn_wreck(dead, true, 10, 0), "wrecks of an eliminated owner are allowed")
	w.end_match(-1, SimWorld.EndReason.DRAW)
	t.is_null(w.spawn_unit(rifle, -1, 0, 0), "no spawns after the match ended")
	t.check_false(w.remove_entity(dead.id, SimEvent.REM_SCRIPT), "no removals after the match ended")


func test_containers_and_queries(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	var a: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)  # id 3
	K.spawn_rifle(w, 1, 30300, 30000)  # id 4
	var c: SimEntity = K.spawn_tank(w, 0, 31000, 30000)  # id 5
	w.step()
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(w.query_circle(30000, 30000, 2000, out), 3, "all three alive in range")
	t.eq(out, PackedInt32Array([3, 4, 5]), "ascending")
	t.eq(w.query_circle(30000, 30000, 2000, out, SimTag.ALIVE, w.non_enemy_mask(0)), 1, "enemies of player 0 only")
	t.eq(out[0], 4, "player 1's rifle")
	t.eq(w.query_rect(29900, 29900, 30400, 30100, out), 2, "rect")
	t.eq(w.nearest(30250, 30000, 5000), 4, "nearest")
	t.eq(w.nearest(30000, 30000, 5000, SimTag.ALIVE, 0, 3), 4, "exclude_id")
	t.eq(w.nearest(0, 0, 100), 0, "nothing in range")
	t.eq([w.rel(0, 0), w.rel(0, 1), w.rel(0, -1), w.team_of(1), w.team_of(-1), w.team_of(9)], [SimWorld.Rel.SELF, SimWorld.Rel.ENEMY, SimWorld.Rel.NEUTRAL, 2, -1, -1] as Array, "rel / team_of")
	t.check(w.are_enemies(0, 1) and not w.are_allied(0, 1) and w.are_allied(0, 0) and not w.are_allied(0, -1), "are_enemies / are_allied")
	t.eq(w.enemies_in_circle(0, 30000, 30000, 2000, out), 1, "enemies_in_circle: default fog sees it")
	t.eq(out[0], 4, "the enemy rifle")
	w.fog = HideAllFog.new()
	t.eq(w.enemies_in_circle(0, 30000, 30000, 2000, out), 0, "a hide-all fog empties it")
	t.eq(w.enemies_in_circle(0, 30000, 30000, 2000, out, true), 1, "ignore_fog goes through entity_revealed only")
	t.eq(w.visible_enemy_ids(0, out), 0, "visible_enemy_ids honours the fog")
	w.fog = SimFogApi.new()
	t.eq(w.visible_enemy_ids(0, out), 2, "player 1's HQ and rifle")
	# containers
	w.set_inside(a, 999, true)
	t.eq(w.query_circle(30000, 30000, 2000, out), 2, "inside entities leave the queries")
	t.eq([a.container_id, (a.flags & SimFlags.F_INSIDE) != 0], [999, true] as Array, "container_id + F_INSIDE")
	t.eq(SimInvariants.check(w), PackedStringArray(), "INV-13 holds")
	w.set_inside(a, -1, false)
	t.eq([a.container_id, w.query_circle(30000, 30000, 2000, out)], [-1, 3] as Array, "leaving restores")
	# idle finder
	t.eq(w.find_idle_units(0, out), 2, "two idle units of player 0")
	w.orders.issue_internal(w, a, SimOrder.T_MOVE, 0, 40000, 30000)
	t.eq(w.find_idle_units(0, out), 1, "an ordered unit is not idle")
	t.eq(out[0], c.id, "the tank")
	# own_ids / find_by_def / entities_visible_to
	t.eq(w.own_ids(0), PackedInt32Array([1, 3, 5]), "own_ids: HQ + rifle + tank, ascending")
	w.kill(c, SimWorld.Cause.SCRIPT)
	t.eq(w.own_ids(0), PackedInt32Array([1, 3]), "dead entities leave own_ids at once")
	t.eq(w.find_by_def(SimEntity.Kind.UNIT, K.unit_def(DefTestKit.U_RIFLEMAN), 0, out), 1, "find_by_def")
	t.eq(w.find_by_def(SimEntity.Kind.STRUCTURE, w.get_entity(1).def_idx, 0, out), 1, "find_by_def structures")
	w.step()
	t.eq(w.entities_visible_to(0, out), 4, "HQ 1, rifle 3, enemy HQ 2, enemy rifle 4 (default fog)")
	w.fog = HideAllFog.new()
	t.eq(w.entities_visible_to(0, out), 2, "own entities only under a hide-all fog")
	t.check(w.cell_visible(0, 1, 1) and w.cell_explored(0, 1, 1), "default fog: everything visible")


func test_hit_points(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	var e: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	e.hp = 100
	e.hp_max = 100
	w.set_hp_max(e, 110)
	t.eq([e.hp, e.hp_max], [110, 110] as Array, "100/100 -> 110/110")
	e.hp = 55
	e.hp_max = 110
	w.set_hp_max(e, 130)
	t.eq([e.hp, e.hp_max], [65, 130] as Array, "55/110 -> 65/130 (ratio kept, half-up)")
	e.hp = 1
	w.set_hp_max(e, 2)
	t.eq(e.hp, 1, "never below 1 while alive")
	var p: SimEntity = w.get_entity(1)
	t.eq(p.hp_max, w.defs.hp_max(w.players[0].view, SimEntity.Kind.STRUCTURE, p.def_idx), "spawn uses the owner's view")


func test_change_owner(t: TestCtx) -> void:
	var recs: PackedInt32Array = PackedInt32Array([0, 50 * 96 + 40, 2, 2, 0, 0, 0, 0])
	var w: SimWorld = K.make_world({"neutrals": recs})
	var n: SimEntity = w.get_entity(1)
	t.eq(w.players[0].struct_count, 1, "neutral barracks not counted")
	n.hp = n.hp_max / 2
	t.check(w.change_owner(1, 0, SimEvent.OWNER_CAPTURE), "capture")
	t.eq([n.owner, n.team, w.players[0].struct_count], [0, 1, 2] as Array, "owner, team cache, counter")
	t.eq(n.hp_max, w.defs.hp_max(w.players[0].view, SimEntity.Kind.STRUCTURE, n.def_idx), "hp_max from the new owner's view")
	t.check(n.hp > 0 and n.hp < n.hp_max, "hp keeps its ratio")
	t.eq([w.structures_of(-1).size(), w.structures_of(0).size()], [0, 2] as Array, "lists moved")
	t.eq(w.structures_of(0)[0].id, 1, "inserted in id order (id 1 before the HQ id 2)")
	t.check_false(w.change_owner(1, 0), "second call: same owner")
	t.check_false(w.change_owner(1, 7), "invalid owner")
	w.eliminate(1, SimPlayer.Elim.SCRIPT)
	t.check_false(w.change_owner(1, 1), "eliminated owner")
	t.check(w.struct_at(40, 50) == 1, "occupancy untouched")
	t.eq(SimInvariants.check(w), PackedStringArray(), "invariants after capture")
	var last: PackedInt32Array = PackedInt32Array()
	for i: int in w.events.count():
		var r: PackedInt32Array = w.events.data.slice(i * 10, i * 10 + 10)
		if r[0] == SimEvent.OWNER_CHANGED:
			last = r
	t.eq(last.slice(4, 8), PackedInt32Array([1, -1, 0, SimEvent.OWNER_CAPTURE]), "OWNER_CHANGED: id, old, new, reason")


func test_footprints(t: TestCtx) -> void:
	var w: SimWorld = K.make_world({"rules": {"start_mode": SimMatchRules.START_NONE, "victory": 0}})
	var brk: int = K.structure_def(DefTestKit.S_BARRACKS)
	var fac: int = K.structure_def(DefTestKit.S_FACTORY)
	var b: SimEntity = w.spawn_structure(brk, 0, 60 * 1024, 60 * 1024)
	t.eq([w.struct_at(59, 59), w.struct_at(60, 60), w.struct_at(61, 60), w.struct_at(58, 59)], [b.id, b.id, 0, 0] as Array, "2x2 at a cell corner covers 59..60")
	var ev: PackedInt32Array = w.events.data.slice(w.events.data.size() - 20)
	t.eq([ev[0], ev[10], ev[14 + 3], ev[10 + 6], ev[10 + 7]], [SimEvent.SPAWNED, SimEvent.NAV_CHANGED, 1, b.id, 1] as Array, "SPAWNED then NAV_CHANGED (occupied)")
	t.eq(ev[14], (59 << 24) | (59 << 16) | (60 << 8) | 60, "NAV_CHANGED.a = packed bbox")
	# rotation: the factory is a rotatable 3x2
	var d0: SimEntity = w.spawn_structure(fac, 0, 18 * 1024 + 1536, 19 * 1024 + 1024)
	t.eq([w.struct_at(18, 19), w.struct_at(20, 20), w.struct_at(21, 20), w.struct_at(18, 21)], [d0.id, d0.id, 0, 0] as Array, "orient 0: 3 wide, 2 tall")
	var d1: SimEntity = w.spawn_structure(fac, 0, 40 * 1024 + 1024, 40 * 1024 + 1536, 1024)
	t.eq([w.struct_at(40, 40), w.struct_at(41, 42), w.struct_at(42, 40), w.struct_at(40, 43)], [d1.id, d1.id, 0, 0] as Array, "orient 1: 2 wide, 3 tall")
	var d3: SimEntity = w.spawn_structure(fac, 0, 70 * 1024 + 1024, 30 * 1024 + 1536, 3149)
	t.eq(w.struct_at(70, 31), d3.id, "facing 3149 -> orient 3 (2 x 3)")
	var nf: SimEntity = w.spawn_structure(brk, 0, 10 * 1024, 10 * 1024, 0, SimFlags.F_NO_FOOTPRINT)
	t.eq(w.struct_at(10, 10), 0, "F_NO_FOOTPRINT occupies nothing")
	t.not_null(nf, "still spawned")
	w.step()
	# removal vacates and emits NAV_CHANGED(d = 0) before REMOVED
	w.events.clear()
	t.check(w.remove_entity(b.id, SimEvent.REM_SOLD), "remove")
	t.eq(w.struct_at(59, 59), b.id, "still occupied until stage 11")
	w.step()
	t.eq(w.struct_at(59, 59), 0, "vacated at stage 11")
	var types: PackedInt32Array = PackedInt32Array()
	for i: int in w.events.count():
		types.append(w.events.data[i * 10])
	t.eq(types, PackedInt32Array([SimEvent.NAV_CHANGED, SimEvent.REMOVED]), "NAV_CHANGED(0) precedes REMOVED")
	t.eq(w.events.data[7], 0, "d = 0: vacated")
	t.eq(w.events.data[10 + 8], SimEvent.REM_SOLD, "REMOVED carries the reason")
	# a dead structure keeps its cells until its removal; units never occupy
	w.kill(d0, SimWorld.Cause.DAMAGE)
	t.eq(w.struct_at(20, 20), d0.id, "dead structure keeps its cells until stage 11")
	K.spawn_rifle(w, 0, 19 * 1024, 19 * 1024)
	t.eq(w.struct_at(19, 19), d0.id, "units do not occupy")
	w.step()
	t.eq(w.struct_at(20, 20), 0, "gone after stage 11")
	t.eq(SimInvariants.check(w), PackedStringArray(), "invariants")


func test_motion(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	var e: SimEntity = K.spawn_rifle(w, 0, 30000, 30000)
	w.step()
	t.eq([e.prev_x == e.x, e.vx], [true, 0] as Array, "idle: prev == pos, v == 0")
	w.set_pos(e, 30100, 30050)
	t.eq([e.prev_x, e.prev_y, e.vx, e.vy], [30000, 30000, 100, 50] as Array, "first set_pos: prev = start, v = displacement")
	w.set_pos(e, 30200, 30050)
	t.eq([e.prev_x, e.vx, e.vy], [30000, 200, 50] as Array, "second call accumulates")
	t.eq(w.moved_prev2(), PackedInt32Array([e.id]), "in moved_prev2 this tick")
	w.step()
	t.eq([e.vx, e.prev_x == e.x], [0, true] as Array, "the next step forgets the motion")
	t.eq(w.moved_prev2(), PackedInt32Array([e.id]), "and the next tick still lists it")
	w.step()
	t.eq(w.moved_prev2().size(), 0, "but not the one after")
	w.set_pos(e, 1, 1, true)
	t.eq([e.prev_x, e.vx], [1, 0] as Array, "teleport snaps")
	t.eq(w.spatial.x_of(e.id), 1, "hash follows")
	t.eq(SimInvariants.check(w), PackedStringArray(), "INV-15 holds")
	w.set_layer(e, SimEntity.Layer.AIR)
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(w.query_circle(1, 1, 100, out, SimTag.ALIVE | SimTag.layer_bit(SimEntity.Layer.AIR)), 1, "layer change refreshes the tag")
