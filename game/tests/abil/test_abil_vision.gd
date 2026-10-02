extends RefCounted
## AB-03: fog, shroud, ghosts, groups, temporary sources, budget, rebuild-compare (abilities 5.9, 10.2 S11, D4).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const CELL: int = 1024


func _data() -> GameData:
	var d: GameData = AbilKit.data()
	AbilKit.set_sight(d, DefTestKit.U_ENGINEER, 8192)  # the R = 8 walker
	AbilKit.set_sight(d, DefTestKit.S_TURRET, 8192, true)
	return d


func _fog(w: SimWorld, pid: int, cx: int, cy: int) -> int:
	return w.fog.fog_bytes(pid)[cy * w.map.w + cx]


func test_fog_states_and_disc_shape(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({}, _data())
	var e: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 40, 40)
	t.eq(_fog(w, 0, 40, 40), 0, "shroud before the first update")
	w.step()
	t.eq(_fog(w, 0, 40, 40), 2, "visible")
	t.eq(_fog(w, 0, 48, 40), 2, "R = 8: (8, 0) inside")
	t.eq(_fog(w, 0, 49, 40), 0, "(9, 0) outside")
	t.eq(_fog(w, 0, 46, 46), 0, "(6, 6): 72 > 64 outside")
	t.eq(_fog(w, 0, 45, 45), 2, "(5, 5): 50 <= 64 inside")
	t.eq(_fog(w, 1, 40, 40), 0, "the other player sees nothing")
	t.check(w.cell_visible(0, 44, 44) and not w.cell_visible(1, 44, 44), "world wrappers")
	t.check(w.cell_explored(0, 44, 44) and not w.cell_explored(1, 44, 44), "explored")
	var ver: int = w.fog.fog_version(0)
	t.ge(ver, 1, "version bumped by the first update")
	w.run(2)
	t.eq(w.fog.fog_version(0), ver, "no change, no bump")
	# walk 12 cells east: the trailing edge turns to fog (explored), the leading edge is visible
	for i: int in 60:
		w.set_pos(e, e.x + 205, e.y)
		w.step()
	var cx: int = e.x >> 10
	t.eq(_fog(w, 0, 40, 40), 1, "the start cell is now fog (explored, not visible)")
	t.eq(_fog(w, 0, cx + 8, 40), 2, "leading edge visible")
	t.eq(_fog(w, 0, cx + 9, 40), 0, "beyond it still shroud")
	t.gt(w.fog.fog_version(0), ver, "version changed while walking")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "counts equal a from-scratch rebuild")


func test_s11_walk_ghosts_and_rebuild(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({}, _data())
	w.vision.set_event_groups(1)
	var walker: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 20, 40)
	var tower: SimEntity = AbilKit.spawn_struct(w, DefTestKit.S_TURRET, 1, 36, 40)
	var bad_rebuild: int = 0
	var first_seen: int = -1
	var ghost_tick: int = -1
	var seen_by_0: PackedInt32Array = PackedInt32Array()
	for i: int in 400:
		var dir: int = 1 if i < 200 else -1
		if i < 60 or i >= 200 or i < 200:
			w.set_pos(walker, walker.x + dir * 205, walker.y)
		w.step()
		if w.tick % 50 == 0:
			bad_rebuild += w.vision.debug_rebuild_compare(w)
		var vis: bool = w.fog.entity_visible(0, tower)
		seen_by_0.append(1 if vis else 0)
		if vis and first_seen < 0:
			first_seen = w.tick
		if ghost_tick < 0 and w.fog.ghosts(0).size() > 0:
			ghost_tick = w.tick
	t.eq(bad_rebuild, 0, "rebuild-compare every 50th tick: 0 differing cells")
	t.eq(seen_by_0[0], 0, "the tower starts unseen")
	t.gt(first_seen, 0, "seen once the walker is within 8 cells")
	t.gt(ghost_tick, first_seen, "a ghost appears when it leaves vision")
	# out-and-back: seen -> ghost -> seen again (ghost removed) at least once
	var transitions: int = 0
	for i2: int in range(1, seen_by_0.size()):
		if seen_by_0[i2] != seen_by_0[i2 - 1]:
			transitions += 1
	t.ge(transitions, 3, "unseen -> seen -> unseen -> seen")
	var added: int = AbilKit.events(w, K.EV_GHOST_ADDED).size()
	var removed: int = AbilKit.events(w, K.EV_GHOST_REMOVED).size()
	t.ge(added, 1, "EV_GHOST_ADDED")
	t.ge(removed, 1, "EV_GHOST_REMOVED when seen again")
	t.eq(AbilKit.events(w, K.EV_VIS_CHANGED).size() > 0, true, "EV_VIS_CHANGED for the event group")
	t.check(tower.vis.ever_mask & 1 != 0, "ever_mask remembers group 0")


func test_ghost_record_and_destroyed_while_unseen(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({}, _data())
	var walker: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 30, 40)
	var tower: SimEntity = AbilKit.spawn_struct(w, DefTestKit.S_TURRET, 1, 36, 40)
	tower.facing = 1000
	w.run(2)
	t.check(w.fog.entity_visible(0, tower), "in view")
	t.eq(w.fog.ghosts(0).size(), 0, "no ghost while visible")
	tower.hp = tower.hp_max / 2
	for i: int in 30:  # walk west out of range
		w.set_pos(walker, walker.x - 410, walker.y)
		w.step()
	t.check_false(w.fog.entity_visible(0, tower), "out of view")
	var gl: Array = w.fog.ghosts(0)
	t.eq(gl.size(), 1, "one ghost")
	var gh: SimGhost = gl[0]
	t.eq([gh.eid, gh.def_idx, gh.owner, gh.x, gh.y, gh.facing], [tower.id, tower.def_idx, 1, tower.x, tower.y, 1000] as Array, "ghost fields")
	t.eq(gh.hp_pct, 50, "hp_pct at the last sight")
	t.check(SimVision.is_known(w, 0, tower), "is_known: a remembered structure")
	t.check_false(SimVision.can_see(w, 0, tower), "can_see: not now")
	t.gt(w.fog.ghost_version(0), 0, "ghost version bumped")
	# it dies unseen: the ghost stays until the cell is seen again
	w.kill(tower, SimWorld.Cause.SCRIPT)
	w.run(5)
	t.eq(w.fog.ghosts(0).size(), 1, "the ghost outlives the structure while its cell is unseen")
	for i2: int in 40:
		w.set_pos(walker, walker.x + 410, walker.y)
		w.step()
	w.run(12)
	t.eq(w.fog.ghosts(0).size(), 0, "the cell is visible and nothing is there: ghost dropped (within 10 ticks)")


func test_groups_and_shared_vision(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({"players": 4, "teams": PackedInt32Array([1, 1, 2, 2]), "rules": {"shared_vision": true}}, _data())
	t.eq(w.vision.n_groups(), 2, "two teams = two groups")
	t.eq(w.vision.group_of(0), w.vision.group_of(1), "allies share a group")
	t.ne(w.vision.group_of(0), w.vision.group_of(2), "enemies do not")
	var a: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 1, 40, 40)
	w.step()
	t.check(w.cell_visible(0, 44, 40), "player 0 sees through its ally")
	t.check_false(w.cell_visible(2, 44, 40), "the enemy team does not")
	var w2: SimWorld = AbilKit.world({"players": 4, "teams": PackedInt32Array([1, 1, 2, 2])}, _data())
	t.eq(w2.vision.n_groups(), 4, "without shared vision: one group per player")
	AbilKit.spawn(w2, DefTestKit.U_ENGINEER, 1, 40, 40)
	w2.step()
	t.check_false(w2.cell_visible(0, 44, 40), "no sharing")
	t.check(a != null, "cast")


func test_fog_disabled(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({"rules": {"fog": false}}, _data())
	var e: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 40, 40)
	var far: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 1, 80, 80)
	w.run(4)
	t.check(w.cell_visible(1, 10, 10) and w.cell_explored(0, 90, 90), "everything visible and explored")
	t.check(w.fog.entity_visible(0, far) and w.fog.entity_visible(1, e), "every entity visible")
	t.eq(w.fog.fog_bytes(0)[5], 2, "all cells 2")


func test_temp_sources(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({}, _data())
	var eye: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 10, 10)
	var camo: SimEntity = AbilKit.rifle(w, 1, 70, 70)
	AbilKit.run_to(w, 130)
	t.check_false(w.cell_visible(0, 70, 70), "far away")
	t.eq(eye.vis.revealed_until, 0, "cast")
	var mask: int = 1 << w.team_of(0)
	var h: int = SimVision.add_reveal(w, mask, K.SHAPE_DISC, 70 * CELL + 512, 70 * CELL + 512, 0, 0, 4096, w.tick + 60, false, 0)
	t.ge(h, 0, "handle")
	w.run(2)
	t.check(w.cell_visible(0, 70, 70) and w.cell_visible(0, 74, 70), "UAV disc reveals 4 cells")
	t.check_false(w.cell_visible(0, 75, 70), "not 5")
	t.check(w.fog.entity_visible(0, camo) == false, "a concealed unit stays hidden by a plain reveal")
	var h2: int = SimVision.add_reveal(w, mask, K.SHAPE_DISC, 70 * CELL + 512, 70 * CELL + 512, 0, 0, 3072, w.tick + 30, true, 0)
	w.run(2)
	t.check(w.fog.entity_visible(0, camo), "a detecting reveal shows it")
	t.check(eye.vis != null, "cast")
	AbilKit.run_to(w, w.tick + 40)
	t.check_false(w.cell_visible(0, 70, 70) and w.vision.temp_source_count() > 1, "the short one expired")
	AbilKit.run_to(w, w.tick + 30)
	t.eq(w.vision.temp_source_count(), 0, "both expired")
	t.eq(_fog(w, 0, 70, 70), 1, "revealed terrain stays explored")
	# capsule (Concealed Crossing style: 12-cell segment, half-width 2)
	var hc: int = SimVision.add_reveal(w, mask, K.SHAPE_CAPSULE, 20 * CELL + 512, 60 * CELL + 512, 32 * CELL + 512, 60 * CELL + 512, 2048, w.tick + 100, false, 0)
	w.run(2)
	t.check(w.cell_visible(0, 26, 60) and w.cell_visible(0, 26, 62), "capsule cells")
	t.check_false(w.cell_visible(0, 26, 63), "outside the half-width")
	SimVision.remove_reveal(w, hc)
	w.run(2)
	t.check_false(w.cell_visible(0, 26, 60), "removed at once")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "grids consistent")
	t.check(h2 >= 0, "second handle")
	# bound source: ends with its body
	var body: SimEntity = AbilKit.rifle(w, 1, 50, 20)
	var hb: int = SimVision.add_reveal(w, mask, K.SHAPE_DISC, body.x, body.y, 0, 0, 2048, w.tick + 400, false, body.id)
	w.run(2)
	t.check(w.cell_visible(0, 50, 20), "bound source visible")
	AbilKit.teleport_cell(w, body, 60, 20)
	w.run(3)
	t.check(w.cell_visible(0, 60, 20) and not w.cell_visible(0, 50, 20), "a disc follows its body")
	w.kill(body, SimWorld.Cause.SCRIPT)
	w.run(4)
	t.eq(w.vision.temp_source_count(), 0, "the source ends when the body dies")
	t.check(hb >= 0, "handle")


func test_restamp_budget_defers_deterministically(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({"rules": {"vision_budget": 16}}, _data())
	t.eq(w.vision.restamp_budget, 16, "budget from the match rules")
	var units: Array[SimEntity] = []
	for k: int in 40:
		units.append(AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 12 + (k % 10) * 6, 12 + (k / 10) * 6))
	w.run(4)
	var before: int = w.vision.stat_restamps
	for u: SimEntity in units:
		w.set_pos(u, u.x + CELL * 2, u.y)  # every unit crosses cells
	w.run(2)
	t.eq(w.vision.stat_restamps - before, 16, "one update processes exactly the budget")
	t.eq(w.vision.deferred.size(), 24, "the rest waits in the eid-ordered deferral list")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "grids stay consistent (stamped state is what the compare checks)")
	w.run(8)
	t.eq(w.vision.deferred.size(), 0, "the backlog drains within ceil(40 / 16) updates")
	for u2: SimEntity in units:
		t.eq(u2.vis.cx, u2.x >> 10, "every disc caught up")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "consistent after the drain")


func test_construction_radius_and_owner_change(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({}, _data())
	var s: SimEntity = w.spawn_structure(w.data.structure_idx(DefTestKit.S_TURRET), 0, 40 * CELL + 512, 40 * CELL + 512, 0, SimFlags.F_UNDER_CONSTRUCTION)
	w.run(2)
	t.eq(s.vis.r_cells, 3, "under construction: at most 3 cells")
	t.eq(_fog(w, 0, 43, 40), 2, "3 cells visible")
	t.eq(_fog(w, 0, 44, 40), 0, "not 4")
	s.flags &= ~SimFlags.F_UNDER_CONSTRUCTION
	w.run(4)
	t.eq(s.vis.r_cells, 8, "finished: full sight")
	t.eq(_fog(w, 0, 48, 40), 2, "8 cells visible")
	# capture: the new owner sees, the old one no longer does
	t.check(w.change_owner(s.id, 1), "captured")
	w.run(4)
	t.eq(s.vis.group, 1, "group follows the owner")
	t.check(w.cell_visible(1, 46, 40), "the new owner sees")
	t.eq(_fog(w, 0, 46, 40), 1, "the old owner keeps only the explored memory")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "grids consistent")


func test_death_and_removal_unstamp(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({}, _data())
	var e: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 40, 40)
	w.run(2)
	t.eq(_fog(w, 0, 44, 40), 2, "visible")
	w.kill(e, SimWorld.Cause.SCRIPT)
	w.run(4)
	t.eq(_fog(w, 0, 44, 40), 1, "the dead give no vision")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "consistent")


func test_explore_all(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({}, _data())
	w.vision.explore_all(0)
	t.check(w.cell_explored(0, 5, 5) and not w.cell_visible(0, 5, 5), "explored, not visible")
	t.check_false(w.cell_explored(1, 5, 5), "only that group")


func test_audit_catches_teleports_and_unannounced_activity(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({}, _data())
	var e: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 40, 40)
	w.run(2)
	w.set_pos(e, 60 * CELL + 512, 60 * CELL + 512, true)  # a teleport is not in the moved list
	w.run(12)
	t.eq(e.vis.cx, 60, "the audit restamped the teleported unit")
	t.eq(_fog(w, 0, 60, 60), 2, "its new position is visible")
	w.set_inside(e, 9999, true)  # loaded into a container without an announcement
	w.run(12)
	t.eq(e.vis.cx, -1, "an unannounced load unstamps the sight disc")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "grids consistent")


func test_stages_work_alone(t: TestCtx) -> void:
	for off: String in ["SimVisionSystem", "SimAbilitySystem"]:
		var w: SimWorld = AbilKit.world({"opts": {"disable": [off]}}, _data())
		var a: SimEntity = AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 40, 40)
		var b: SimEntity = AbilKit.rifle(w, 1, 44, 40)
		w.run(150)
		t.eq(a.flags & SimFlags.F_GONE, 0, "%s off: the world runs" % off)
		if off == "SimVisionSystem":
			t.is_null(w.vision, "no vision stage")
			t.eq(b.stats.vals[SimAbilityConsts.K_SIGHT], 7168, "stats still work without vision")
			t.eq(b.vis, null, "no vision component")
		else:
			t.is_null(w.abilities, "no abilities stage")
			t.is_null(b.stats, "no stats component")
			t.eq(_fog(w, 0, 44, 40), 2, "vision still stamps from the def's sight")
