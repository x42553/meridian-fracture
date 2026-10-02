extends RefCounted
## MIS1: every action of the mission system, run by the real sim. The mission's triggers are all DISABLED with a condition that is
## always true; a test enables one (MissionKit.fire) and inspects the world and the UI events.

const TANK: String = "unit.napc.guardian_tank"
const JAGER: String = "unit.nec.jager_squad"
const GEN: String = "structure.shared.generator"
const WATCH: String = "structure.shared.watchtower"


func _trig(id: String, then: Array) -> Dictionary:
	return {"id": id, "enabled": false, "when": {"kind": "time", "ticks": 0}, "then": then}


func _mission() -> Dictionary:
	var t: Array = [
		_trig("t_obj", [{"do": "set_objective", "objective": "o1", "state": "completed"}, {"do": "set_objective", "objective": "o2", "state": "active"}]),
		_trig("t_msg", [{"do": "show_message", "message": "m1"}, {"do": "show_message", "message": "m1", "announcer": "unit_ready"}, {"do": "show_message", "message": "m2"}]),
		_trig("t_timer_start", [{"do": "timer_start", "timer": "tm", "seconds": 2}]),
		_trig("t_timer_stop", [{"do": "timer_stop", "timer": "tm"}]),
		_trig("t_spawn", [{"do": "spawn_units", "owner": 1, "def": JAGER, "count": 4, "area": "a_far", "wave": "w1", "order": {"kind": "attack_move", "area": "a_base"}}]),
		_trig("t_spawn_hold", [{"do": "spawn_units", "owner": 1, "def": JAGER, "count": 1, "area": "a_far", "order": {"kind": "hold"}}]),
		_trig("t_spawn_guard", [{"do": "spawn_units", "owner": 1, "def": JAGER, "count": 1, "area": "a_far", "order": {"kind": "guard", "area": "a_far"}}]),
		_trig("t_spawn_move", [{"do": "spawn_units", "owner": 1, "def": JAGER, "count": 3, "area": "a_far", "order": {"kind": "move", "area": "a_mid"}}]),
		_trig("t_spawn_neutral", [{"do": "spawn_units", "owner": "neutral", "def": JAGER, "count": 2, "area": "a_mid"}]),
		_trig("t_spawn_more", [{"do": "spawn_units", "owner": 1, "def": JAGER, "count": 2, "area": "a_far", "wave": "w1"}]),
		_trig("t_struct", [{"do": "spawn_structure", "owner": 1, "def": GEN, "area": "a_far", "id": "gen1"}]),
		_trig("t_struct_neutral", [{"do": "spawn_structure", "owner": "neutral", "def": WATCH, "area": "a_mid", "id": "n1"}]),
		_trig("t_struct_cell", [{"do": "spawn_structure", "owner": 0, "def": GEN, "cell": [30, 30], "id": "gen2"}]),
		_trig("t_credits_give", [{"do": "give_credits", "owner": 0, "amount": 700}]),
		_trig("t_credits_take", [{"do": "give_credits", "owner": 0, "amount": -300}]),
		_trig("t_credits_all", [{"do": "give_credits", "owner": 0, "amount": -100000}]),
		_trig("t_lock", [{"do": "lock_power", "owner": 0, "slot": 1}]),
		_trig("t_grant", [{"do": "grant_power", "owner": 0, "slot": 1}]),
		_trig("t_reveal", [{"do": "reveal_area", "owner": 0, "area": "a_far", "seconds": 5}]),
		_trig("t_ai_on", [{"do": "change_ai", "owner": 1, "active": true, "level": 3, "style": 2, "aggression": 80}]),
		_trig("t_ai_off", [{"do": "change_ai", "owner": 1, "active": false}]),
		_trig("t_transfer_placed", [{"do": "transfer", "to": 0, "placed": "gen1"}]),
		_trig("t_transfer_filter", [{"do": "transfer", "to": 0, "owner": 1, "def": JAGER, "area": "a_far"}]),
		_trig("t_transfer_neutral", [{"do": "transfer", "to": "neutral", "owner": 1, "of": "structure"}]),
		_trig("t_destroy_placed", [{"do": "destroy", "placed": "gen1"}]),
		_trig("t_destroy_filter", [{"do": "destroy", "owner": 1, "of": "unit"}]),
		_trig("t_order_units", [{"do": "order_units", "owner": 0, "tag": "tank", "area": "a_base", "order": {"kind": "move", "area": "a_mid"}}]),
		_trig("t_eliminate", [{"do": "eliminate", "owner": 1}]),
		_trig("t_en_dis", [{"do": "trigger_enable", "trigger": "t_obj"}, {"do": "trigger_disable", "trigger": "t_msg"}]),
		_trig("t_win", [{"do": "win", "owner": 0}, {"do": "set_objective", "objective": "o1", "state": "completed"}]),
		_trig("t_lose", [{"do": "lose", "owner": 0}]),
		_trig("t_camera", [{"do": "camera_hint", "area": "a_mid", "seconds": 3}, {"do": "camera_hint", "cell": [10, 20]}]),
		_trig("t_music", [{"do": "music_state", "state": "combat"}]),
	]
	var start: Dictionary = {"mode": "hq", "units": [{"def": TANK, "count": 3, "dx": 4, "dy": 3}]}
	var players: Array = [
		{"slot": 0, "kind": "human", "roster": "roster.napc.vanilla", "team": 1, "start": start},
		{"slot": 1, "kind": "ai", "roster": "roster.nec.vanilla", "team": 2, "ai": {"active": false}, "start": {"mode": "none"}},
	]
	return MissionKit.base("a_all", {"triggers": t, "players": players, "rules": {"fog": true, "start_credits": 5000},
		"objectives": [{"id": "o1", "kind": "primary", "text": "One"}, {"id": "o2", "kind": "hidden", "text": "Two"}],
		"messages": [{"id": "m1", "text": "One", "announcer": "base_under_attack"}, {"id": "m2", "text": "Two"}],
		"timers": [{"id": "tm", "seconds": 10}]})


func _world(events: bool = true) -> SimWorld:
	return MissionKit.world(MissionKit.data({"a_all": _mission()}), "a_all", {"events": events})


func _placed(w: SimWorld, id: String) -> SimEntity:
	return w.get_entity(w.mission.placed_id[w.mission.def.placed.find(id)])


func _cell_dist2(w: SimWorld, e: SimEntity, area: int) -> int:
	var c: int = w.mission.area_center_cell(w, area)
	var dx: int = (e.x >> 10) - (c % w.map.w)
	var dy: int = (e.y >> 10) - (c / w.map.w)
	return dx * dx + dy * dy


func test_objective_message_timer_and_ui_events(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	t.eq(w.mission.obj_state[0], SimMissionConst.OBJ_ACTIVE, "o1 starts active")
	t.eq(w.mission.obj_state[1], SimMissionConst.OBJ_HIDDEN, "o2 starts hidden")
	var initial: Array = MissionKit.events_of(w, SimEvent.MISSION_OBJECTIVE)
	t.eq(initial.size(), 1, "an event for the one visible objective only")
	MissionKit.fire(w, "t_obj")
	t.eq(w.mission.obj_state[0], SimMissionConst.OBJ_COMPLETED)
	t.eq(w.mission.obj_state[1], SimMissionConst.OBJ_ACTIVE)
	var ev: Array = MissionKit.events_of(w, SimEvent.MISSION_OBJECTIVE)
	t.eq(ev.size(), 3, "initial + two changes")
	t.eq((ev[1] as Array).slice(3, 7), [0, SimMissionConst.OBJ_COMPLETED, 0, SimMissionConst.OBJ_ACTIVE], "objective idx, new state, kind, previous")
	MissionKit.fire(w, "t_obj")  # a once trigger: no second change
	t.eq(MissionKit.events_of(w, SimEvent.MISSION_OBJECTIVE).size(), 3, "a fired once-trigger does not run again")
	MissionKit.fire(w, "t_msg")
	var msgs: Array = MissionKit.events_of(w, SimEvent.MISSION_MESSAGE)
	t.eq(msgs.size(), 3)
	t.eq((msgs[0] as Array).slice(3, 5), [0, w.mission.def.announcers.find("base_under_attack")], "message 0 carries its own announcer")
	t.eq((msgs[1] as Array).slice(3, 5), [0, w.mission.def.announcers.find("unit_ready")], "announcer override")
	t.eq((msgs[2] as Array).slice(3, 5), [1, -1], "no announcer")
	MissionKit.fire(w, "t_timer_start")
	t.eq(w.mission.timer_state[0], SimMissionConst.TM_RUNNING)
	t.eq(w.mission.timer_len[0], 40, "seconds override = 2 s")
	MissionKit.run(w, 50)
	t.eq(w.mission.timer_state[0], SimMissionConst.TM_EXPIRED, "expired after its duration")
	var tev: Array = MissionKit.events_of(w, SimEvent.MISSION_TIMER)
	t.eq(tev.size(), 2, "started + expired")
	MissionKit.fire(w, "t_timer_start")  # once: nothing
	var w2: SimWorld = _world()
	MissionKit.fire(w2, "t_timer_start")
	MissionKit.fire(w2, "t_timer_stop")
	t.eq(w2.mission.timer_state[0], SimMissionConst.TM_STOPPED)
	MissionKit.run(w2, 100)
	t.eq(w2.mission.timer_state[0], SimMissionConst.TM_STOPPED, "a stopped timer never expires")


func test_spawn_units_positions_wave_and_orders(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	var before: int = w.units_of(1).size()
	MissionKit.fire(w, "t_spawn")
	var made: Array[SimEntity] = w.units_of(1)
	t.eq(made.size() - before, 4, "four units")
	var far: int = w.mission.def.area_idx("a_far")
	var base_c: int = w.mission.area_center_cell(w, w.mission.def.area_idx("a_base"))
	for e: SimEntity in made:
		t.eq(e.owner, 1)
		t.check(_cell_dist2(w, e, far) <= 13 * 13, "spawned near the area centre")
		if t.check(not e.orders.is_empty(), "has an order"):
			t.eq(e.orders[0].type, SimOrder.T_ATTACK_MOVE, "scripted attack-move (a plain sim order)")
			var dx: int = (e.orders[0].x >> 10) - (base_c % w.map.w)
			var dy: int = (e.orders[0].y >> 10) - (base_c / w.map.w)
			t.check(dx * dx + dy * dy <= 9 * 9, "target spread around the base area")
	var cells: Dictionary = {}
	for e: SimEntity in made:
		cells[(e.y >> 10) * w.map.w + (e.x >> 10)] = true
	t.eq(cells.size(), 4, "units are on distinct cells")
	t.eq(w.mission.wave_spawned[0], 1)
	t.eq(w.mission.wave_ids[0].size(), 4)
	t.eq(MissionKit.events_of(w, SimEvent.MISSION_WAVE).size(), 1)
	MissionKit.fire(w, "t_spawn_more")
	t.eq(w.mission.wave_ids[0].size(), 6, "a second spawn adds to the same wave")


func test_spawn_order_kinds_and_neutral_owner(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.fire(w, "t_spawn_hold")
	MissionKit.fire(w, "t_spawn_guard")
	MissionKit.fire(w, "t_spawn_move")
	MissionKit.fire(w, "t_spawn_neutral")
	var types: Dictionary = {}
	for e: SimEntity in w.units_of(1):
		types[e.orders[0].type if not e.orders.is_empty() else -1] = int(types.get(e.orders[0].type if not e.orders.is_empty() else -1, 0)) + 1
	t.eq(int(types.get(SimOrder.T_HOLD, 0)), 1, "hold")
	t.eq(int(types.get(SimOrder.T_GUARD, 0)), 1, "guard")
	t.eq(int(types.get(SimOrder.T_MOVE, 0)), 3, "move")
	t.eq(w.units_of(-1).size(), 2, "neutral units")
	for e: SimEntity in w.units_of(-1):
		t.eq(e.owner, -1)


func test_spawn_structure_owned_neutral_cell_and_blocked_site(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.fire(w, "t_struct")
	var g: SimEntity = _placed(w, "gen1")
	if t.not_null(g, "gen1 spawned"):
		t.eq(g.owner, 1)
		t.eq(g.kind, SimEntity.Kind.STRUCTURE)
		t.eq(g.def_idx, w.data.structure_idx(GEN))
		t.check((g.flags & SimFlags.F_INITIAL) != 0, "free, active structure")
		t.check(w.map.occupant_at((g.y >> 10) * w.map.w + (g.x >> 10)) >= 0, "occupies the map")
		t.check(w.players[1].struct_count >= 1, "counted for its owner")
	MissionKit.fire(w, "t_struct_neutral")
	var n: SimEntity = _placed(w, "n1")
	if t.not_null(n, "neutral structure"):
		t.eq(n.owner, -1)
	# a site on top of the HQ is moved to the nearest free spot
	var hq: SimEntity = w.structures_of(0)[0]
	var cx: int = hq.x >> 10
	var cy: int = hq.y >> 10
	var act: DefMissionAction = DefMissionAction.new()
	act.op = DefMissionAction.Op.SPAWN_STRUCTURE
	act.owner_mode = DefMissionCond.OWN_PID
	act.owner_val = 0
	act.def_idx = w.data.structure_idx(GEN)
	act.cell_x = cx
	act.cell_y = cy
	act.placed = w.mission.def.placed.find("gen2")
	SimMissionActions.run(w.mission, w, act)
	w.step()
	var g2: SimEntity = _placed(w, "gen2")
	if t.not_null(g2, "moved to a free site"):
		t.check(g2.x != hq.x or g2.y != hq.y, "not on the HQ")
		t.eq(g2.owner, 0)
	var gens: int = 0
	for s: SimEntity in w.structures_of(0):
		gens += 1
	t.eq(gens, 2, "HQ + generator")


func test_credits(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	var c0: int = w.players[0].credits
	MissionKit.fire(w, "t_credits_give")
	t.eq(w.players[0].credits, c0 + 700)
	MissionKit.fire(w, "t_credits_take")
	t.eq(w.players[0].credits, c0 + 400)
	MissionKit.fire(w, "t_credits_all")
	t.eq(w.players[0].credits, 0, "taking more than the player has takes everything")


func test_lock_and_grant_support_power(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	var slot: SimPowerSlot = w.players[0].econ.slots[1]
	MissionKit.fire(w, "t_lock")
	t.eq(slot.ready_tick, SimMissionConst.POWER_LOCK_TICK)
	t.gt(w.strategic.cooldown_left_ticks(w, 0, 1), 1000000, "a locked power shows a cooldown that never ends")
	MissionKit.fire(w, "t_grant")
	t.eq(slot.ready_tick, 0)
	t.eq(MissionKit.events_of(w, SimEvent.MISSION_POWER).size(), 2)


func test_reveal_area(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.run(w, 4)
	var c: int = w.mission.area_center_cell(w, w.mission.def.area_idx("a_far"))
	var cx: int = c % w.map.w
	var cy: int = c / w.map.w
	t.check(not w.cell_visible(0, cx, cy), "the enemy start is hidden by the fog")
	MissionKit.fire(w, "t_reveal")
	MissionKit.run(w, 6)
	t.check(w.cell_visible(0, cx, cy), "revealed")
	t.check(w.cell_explored(0, cx, cy), "and explored")
	MissionKit.run(w, 140)
	t.check(not w.cell_visible(0, cx, cy), "the reveal ends after its duration")
	t.check(w.cell_explored(0, cx, cy), "the cell stays explored")


func test_change_ai_gates_commands(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.fire(w, "t_spawn_hold")
	var u: SimEntity = w.units_of(1)[0]
	var target_x: int = u.x + 3 * 1024
	w.submit_raw(1, SimCmd.move(PackedInt32Array([u.id]), target_x, u.y))
	var rej0: int = w.players[1].st_rejected
	MissionKit.run(w, 2)
	t.eq(w.players[1].st_rejected, rej0 + 1, "an AI that the mission has not switched on is refused")
	t.check(u.orders.is_empty() or u.orders[0].type != SimOrder.T_MOVE, "no move order")
	MissionKit.fire(w, "t_ai_on")
	t.eq(w.mission.ai_active[1], 1)
	t.eq(w.players[1].ai_level, 3)
	t.eq(w.players[1].ai_style, 2)
	t.eq(w.mission.ai_aggr[1], 80)
	w.submit_raw(1, SimCmd.move(PackedInt32Array([u.id]), target_x, u.y))
	MissionKit.run(w, 2)
	t.check(not u.orders.is_empty() and u.orders[0].type == SimOrder.T_MOVE, "the switched-on AI is obeyed")
	t.eq(MissionKit.events_of(w, SimEvent.MISSION_AI).size(), 1)
	var human_rej: int = w.players[0].st_rejected
	w.submit_raw(0, SimCmd.stop(PackedInt32Array([w.units_of(0)[0].id])))
	MissionKit.run(w, 2)
	t.eq(w.players[0].st_rejected, human_rej, "a human is never gated")
	MissionKit.fire(w, "t_ai_off")
	t.eq(w.mission.ai_active[1], 0)


func test_transfer_and_destroy(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.fire(w, "t_struct")
	MissionKit.fire(w, "t_spawn")
	var g: SimEntity = _placed(w, "gen1")
	MissionKit.fire(w, "t_transfer_placed")
	t.eq(g.owner, 0, "a placed structure changed hands")
	t.eq(w.players[1].struct_count, 0)
	MissionKit.fire(w, "t_transfer_filter")
	var moved: int = 0
	for e: SimEntity in w.units_of(0):
		if e.def_idx == w.data.unit_idx(JAGER):
			moved += 1
	t.eq(moved, 4, "every matching unit in the area is transferred")
	t.eq(MissionKit.events_of(w, SimEvent.OWNER_CHANGED).size(), 5)
	MissionKit.fire(w, "t_destroy_placed")
	t.check(not w.is_alive(g.id), "destroyed")
	var w2: SimWorld = _world()
	MissionKit.fire(w2, "t_spawn")
	MissionKit.fire(w2, "t_destroy_filter")
	MissionKit.run(w2, 3)
	t.eq(w2.units_of(1).size(), 0, "destroy by filter")
	var w3: SimWorld = _world()
	MissionKit.fire(w3, "t_struct")
	MissionKit.fire(w3, "t_transfer_neutral")
	t.eq(_placed(w3, "gen1").owner, -1, "transfer to neutral")


func test_order_units_and_eliminate(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.fire(w, "t_order_units")
	var mid: int = w.mission.area_center_cell(w, w.mission.def.area_idx("a_mid"))
	var tanks: int = 0
	for e: SimEntity in w.units_of(0):
		if not e.orders.is_empty() and e.orders[0].type == SimOrder.T_MOVE:
			tanks += 1
			var dx: int = (e.orders[0].x >> 10) - (mid % w.map.w)
			var dy: int = (e.orders[0].y >> 10) - (mid / w.map.w)
			t.check(dx * dx + dy * dy <= 9 * 9, "move target near the mid area")
	t.eq(tanks, 3, "the three tanks got the order")
	MissionKit.fire(w, "t_spawn")
	MissionKit.fire(w, "t_eliminate")
	t.eq(w.players[1].eliminated, 1)
	t.eq(w.players[1].elim_reason, SimPlayer.Elim.SCRIPT)
	MissionKit.run(w, 30)
	t.eq(w.units_of(1).size(), 0, "the defeat cascade removes its units")


func test_trigger_enable_disable(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.fire(w, "t_en_dis")
	t.eq(w.mission.trig_enabled[MissionKit.trig(w, "t_msg")], 0, "disabled")
	# t_obj sorts after t_en_dis, so the trigger that was just enabled runs in the same pass (and, being once, disables itself again)
	t.eq(w.mission.obj_state[0], SimMissionConst.OBJ_COMPLETED, "the enabled trigger ran in the same pass")
	t.eq(w.mission.trig_fired[MissionKit.trig(w, "t_obj")], 1)
	t.eq(w.mission.trig_enabled[MissionKit.trig(w, "t_obj")], 0)


func test_win_and_lose_feed_the_match_result(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.fire(w, "t_win")
	t.eq(w.match_state, SimWorld.MATCH_ENDED)
	t.eq(w.end_reason, SimWorld.EndReason.MISSION_WIN)
	t.eq(w.winner_team, 1)
	t.eq(w.match_result(), {"winner_team": 1, "reason": SimWorld.EndReason.MISSION_WIN})
	t.eq(w.mission.result, SimMissionConst.RES_WIN)
	t.eq(w.mission.obj_state[0], SimMissionConst.OBJ_ACTIVE, "actions after win are not run")
	t.eq(MissionKit.events_of(w, SimEvent.MATCH_END).size(), 1)
	t.eq(MissionKit.events_of(w, SimEvent.MISSION_RESULT).size(), 1)
	var steps: int = w.tick
	w.step()
	t.eq(w.tick, steps, "a finished world does not advance")
	var l: SimWorld = _world()
	MissionKit.fire(l, "t_lose")
	t.eq(l.end_reason, SimWorld.EndReason.MISSION_LOSE)
	t.eq(l.winner_team, 2, "the other team is the winner")
	t.eq(l.players[0].eliminated, 1, "the loser is eliminated")
	t.eq(l.players[0].elim_reason, SimPlayer.Elim.SCRIPT)
	var s: Dictionary = UiMatchStats.new().build(l, {}, {"reason": 0, "winner_team": l.winner_team, "final_tick": l.tick}, 0)
	t.eq(s["result"], "defeat", "the end screen reads a defeat")
	var s2: Dictionary = UiMatchStats.new().build(w, {}, {"reason": 0, "winner_team": w.winner_team, "final_tick": w.tick}, 0)
	t.eq(s2["result"], "victory", "and a victory")


func test_camera_and_music_events(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.fire(w, "t_camera")
	var cam: Array = MissionKit.events_of(w, SimEvent.MISSION_CAMERA)
	t.eq(cam.size(), 2)
	var mid: int = w.mission.area_center_cell(w, w.mission.def.area_idx("a_mid"))
	t.eq((cam[0] as Array)[1], (mid % w.map.w) * 1024 + 512, "x of the area centre")
	t.eq((cam[0] as Array)[3], w.mission.def.area_idx("a_mid"))
	t.eq((cam[0] as Array)[4], 60, "3 s = 60 ticks")
	t.eq((cam[1] as Array)[1], 10 * 1024 + 512, "an absolute cell")
	t.eq((cam[1] as Array)[3], -1)
	MissionKit.fire(w, "t_music")
	var mus: Array = MissionKit.events_of(w, SimEvent.MISSION_MUSIC)
	t.eq((mus[0] as Array)[3], DefMissionAction.MUSIC_NAMES.find("combat"))
