extends RefCounted
## MIS1: trigger semantics (once / repeat / cooldown / edge / evaluation order and cadence), timers, area geometry, start modes and
## rules, checksum coverage (DR-13), determinism, and complete scripted missions that reach a win and a lose through player
## commands (plus a resignation turned into a defeat by a trigger).

const TANK: String = "unit.napc.guardian_tank"
const JAGER: String = "unit.nec.jager_squad"
const LEO: String = "unit.nec.leopard_tank"
const GEN: String = "structure.shared.generator"


func _sem() -> Dictionary:
	var start: Dictionary = {"mode": "hq", "units": [{"def": TANK, "count": 3, "dx": 4, "dy": 3}]}
	var players: Array = [
		{"slot": 0, "kind": "human", "roster": "roster.napc.vanilla", "team": 1, "start": start},
		{"slot": 1, "kind": "ai", "roster": "roster.nec.vanilla", "team": 2, "ai": {"active": false}, "start": {"mode": "none"}},
	]
	var tanks3: Dictionary = {"kind": "count", "owner": 0, "tag": "tank", "value": 3}
	var no_op: Array = [{"do": "music_state", "state": "calm"}]
	return MissionKit.base("f_sem", {"players": players,
		"objectives": [{"id": "o1", "kind": "secondary", "text": "1"}, {"id": "o2", "kind": "secondary", "text": "2"}, {"id": "o3", "kind": "secondary", "text": "3"},
			{"id": "o4", "kind": "secondary", "text": "4"}],
		"timers": [{"id": "tm_rep", "seconds": 1, "repeat": true, "autostart": true}, {"id": "tm_once", "seconds": 1, "autostart": true}],
		"triggers": [
			{"id": "t_once", "when": {"kind": "time", "ticks": 0}, "then": no_op},
			{"id": "t_repeat", "once": false, "when": {"kind": "time", "ticks": 0}, "then": no_op},
			{"id": "t_cool", "once": false, "cooldown_s": 2, "when": {"kind": "time", "ticks": 0}, "then": no_op},
			{"id": "t_edge", "once": false, "edge": true, "when": tanks3, "then": no_op},
			{"id": "t_level", "once": false, "when": tanks3, "then": no_op},
			{"id": "t_off", "enabled": false, "when": {"kind": "time", "ticks": 0}, "then": no_op},
			{"id": "t_tick7", "when": {"kind": "time", "ticks": 7}, "then": [{"do": "set_objective", "objective": "o4", "state": "completed"}]},
			{"id": "t_a", "when": {"kind": "time", "ticks": 0}, "then": [{"do": "set_objective", "objective": "o1", "state": "completed"}]},
			{"id": "t_b", "when": {"kind": "objective", "objective": "o1", "state": "completed"}, "then": [{"do": "set_objective", "objective": "o2", "state": "completed"}]},
			{"id": "t_c", "when": {"kind": "objective", "objective": "o3", "state": "completed"}, "then": no_op},
			{"id": "t_d", "when": {"kind": "time", "ticks": 0}, "then": [{"do": "set_objective", "objective": "o3", "state": "completed"}]},
			{"id": "t_rep_timer", "once": false, "when": {"kind": "timer", "timer": "tm_rep"}, "then": no_op},
			{"id": "t_once_timer", "once": false, "when": {"kind": "timer", "timer": "tm_once"}, "then": no_op},
			{"id": "t_z_setup", "when": {"kind": "time", "ticks": 0}, "then": [
				{"do": "spawn_structure", "owner": 1, "def": GEN, "area": "a_far", "id": "g1"},
				{"do": "spawn_units", "owner": 1, "def": JAGER, "count": 1, "area": "a_far", "wave": "w1"}]},
			{"id": "t_z_left", "when": {"kind": "area_left", "owner": 1, "area": "a_far"}, "then": no_op},
		]})


func _fires(w: SimWorld, id: String) -> int:
	return w.mission.trig_fired[MissionKit.trig(w, id)]


func test_once_repeat_cooldown_edge_and_disabled(t: TestCtx) -> void:
	var w: SimWorld = MissionKit.world(MissionKit.data({"f_sem": _sem()}), "f_sem", {"events": false})
	if w == null:
		return
	MissionKit.run(w, 100)  # passes at ticks 0, 5, ..., 95
	t.eq(w.mission.passes, 20)
	t.eq(_fires(w, "t_once"), 1, "once")
	t.eq(_fires(w, "t_repeat"), 20, "repeat fires on every pass")
	t.eq(_fires(w, "t_cool"), 3, "cooldown 40 ticks: fires at 0, 40, 80")
	t.eq(_fires(w, "t_level"), 20, "level trigger fires while its condition holds")
	t.eq(_fires(w, "t_edge"), 1, "edge trigger fires once while the condition stays true")
	t.eq(_fires(w, "t_off"), 0, "a disabled trigger never fires")
	# make the condition false for a while, then true again
	var tank: SimEntity = null
	for e: SimEntity in w.units_of(0):
		if e.def_idx == w.data.unit_idx(TANK):
			tank = e
			break
	w.kill(tank, SimWorld.Cause.SCRIPT)
	MissionKit.run(w, 20)
	var level_before: int = _fires(w, "t_level")
	t.eq(_fires(w, "t_edge"), 1, "false: no fire")
	w.spawn_unit(w.data.unit_idx(TANK), 0, tank.x, tank.y)
	MissionKit.run(w, 10)
	t.eq(_fires(w, "t_edge"), 2, "edge fires again when the condition turns true again")
	t.gt(_fires(w, "t_level"), level_before, "level fires again")


func test_evaluation_cadence_and_id_order(t: TestCtx) -> void:
	var w: SimWorld = MissionKit.world(MissionKit.data({"f_sem": _sem()}), "f_sem")
	if w == null:
		return
	MissionKit.run(w, 30)
	var ev: Array = MissionKit.events_of(w, SimEvent.MISSION_OBJECTIVE)
	var tick_of: Dictionary = {}
	for e: Variant in ev:
		var a: Array = e as Array
		if int(a[4]) == SimMissionConst.OBJ_COMPLETED:
			tick_of[int(a[3])] = int(a[0])
	t.eq(int(tick_of.get(3, -1)), 10, "time >= 7 is first seen by the pass at tick 10 (evaluation every 5 ticks)")
	t.eq(int(tick_of.get(0, -1)), 0, "t_a at tick 0")
	t.eq(int(tick_of.get(1, -1)), 0, "t_b (sorts after t_a) sees o1 completed in the SAME pass")
	t.eq(_fires(w, "t_c"), 1, "t_c (sorts before t_d) sees o3 only in the next pass")
	var ctick: int = w.mission.trig_last_tick[MissionKit.trig(w, "t_c")]
	t.eq(ctick, 5, "at tick 5")


func test_timers_repeat_and_expire(t: TestCtx) -> void:
	var w: SimWorld = MissionKit.world(MissionKit.data({"f_sem": _sem()}), "f_sem")
	if w == null:
		return
	MissionKit.run(w, 100)
	var tev: Array = MissionKit.events_of(w, SimEvent.MISSION_TIMER)
	var expired_rep: int = 0
	var expired_once: int = 0
	for e: Variant in tev:
		var a: Array = e as Array
		if int(a[4]) == 2 and int(a[3]) == 0:
			expired_rep += 1
		if int(a[4]) == 2 and int(a[3]) == 1:
			expired_once += 1
	t.eq(expired_rep, 4, "a repeating 1 s timer expires at 20, 40, 60, 80")
	t.eq(expired_once, 1)
	t.eq(_fires(w, "t_rep_timer"), 4, "the expired state is seen once per expiry")
	t.gt(_fires(w, "t_once_timer"), 10, "a one-shot timer stays expired: a level trigger keeps firing")


func _areas() -> Dictionary:
	return MissionKit.base("f_areas", {"areas": [
		{"id": "c0", "shape": "circle", "x": 20, "y": 20, "r": 0},
		{"id": "c3", "shape": "circle", "x": 30, "y": 30, "r": 3},
		{"id": "redge", "shape": "rect", "x": 90, "y": 90, "w": 20, "h": 20},
		{"id": "mmax", "shape": "circle", "anchor": "map", "x": 1000, "y": 1000, "r": 2},
		{"id": "mzero", "shape": "circle", "anchor": "map", "x": 0, "y": 0, "r": 1},
		{"id": "neg", "shape": "circle", "anchor": "start:0", "x": -255, "y": -255, "r": 2},
		{"id": "ring", "shape": "rect", "anchor": "start:0", "x": -1, "y": -1, "w": 3, "h": 3},
	]})


func test_area_geometry_and_edge_cases(t: TestCtx) -> void:
	var w: SimWorld = MissionKit.world(MissionKit.data({"f_areas": _areas()}), "f_areas")
	if w == null:
		return
	var m: SimMissionSystem = w.mission
	var ix: Callable = func(id: String) -> int: return m.def.area_idx(id)
	t.check(m.in_area(ix.call("c0"), 20, 20), "r = 0 is the single cell")
	t.check(not m.in_area(ix.call("c0"), 21, 20) and not m.in_area(ix.call("c0"), 20, 19), "and nothing else")
	var c3: int = ix.call("c3")
	t.check(m.in_area(c3, 33, 30), "dx*dx = r*r is inside")
	t.check(not m.in_area(c3, 33, 31), "9 + 1 > 9 is outside")
	t.check(m.in_area(c3, 32, 32), "8 <= 9 inside")
	t.check(not m.in_area(c3, 33, 33), "18 > 9 outside")
	t.check(m.in_area(c3, 27, 30) and not m.in_area(c3, 26, 30), "west edge")
	var redge: int = ix.call("redge")
	t.check(m.in_area(redge, 95, 95), "a rect past the map edge is clamped to the last cell")
	t.check(m.in_area(redge, 90, 90) and not m.in_area(redge, 89, 90), "rect top-left")
	t.eq(m.area_center_cell(w, redge), 92 * 96 + 92, "clamped rect centre")
	var mmax: int = ix.call("mmax")
	t.check(m.in_area(mmax, 95, 95), "map anchor 1000 permille = last cell")
	t.check(m.in_area(mmax, 93, 95) and not m.in_area(mmax, 92, 95), "r 2 around it")
	var mzero: int = ix.call("mzero")
	t.check(m.in_area(mzero, 0, 0) and m.in_area(mzero, 1, 0) and not m.in_area(mzero, 1, 1), "map anchor 0, r 1 at the corner")
	var neg: int = ix.call("neg")
	t.check(m.in_area(neg, 0, 0), "a start offset beyond the map edge is clamped to the corner cell")
	var sc: int = SimMissionSystem.start_cell(w, 0)
	var sx: int = sc % w.map.w
	var sy: int = sc / w.map.w
	var ring: int = ix.call("ring")
	t.check(m.in_area(ring, sx, sy) and m.in_area(ring, sx - 1, sy - 1) and m.in_area(ring, sx + 1, sy + 1), "3x3 rect around the start cell")
	t.check(not m.in_area(ring, sx + 2, sy), "outside the rect")
	t.eq(m.area_center_cell(w, ring), sc, "its centre is the start cell")
	# entity membership uses the cell the entity stands on: x = cell * 1024 + 1023 is still that cell
	var e: SimEntity = w.units_of(0)[0] if not w.units_of(0).is_empty() else null
	var hq: SimEntity = w.structures_of(0)[0]
	t.check(m.matches(hq, -1, 0, ring), "the HQ stands on the start cell")
	if e != null:
		w.set_pos(e, sx * 1024 + 1023, sy * 1024 + 1023, true)
		t.check(m.matches(e, -1, 0, ring), "last sub-cell unit is still the same cell")
		w.set_pos(e, (sx + 2) * 1024, sy * 1024, true)
		t.check(not m.matches(e, -1, 0, ring), "first sub-cell unit of the next cell is outside")


func _starts() -> Dictionary:
	var p0: Dictionary = {"slot": 0, "kind": "human", "roster": "roster.napc.vanilla", "team": 1, "start": {"mode": "mcv",
		"units": [{"def": TANK, "count": 2, "dx": 5, "dy": 0}], "structures": [{"def": GEN, "dx": -6, "dy": 0, "id": "own_gen"}]}}
	var p1: Dictionary = {"slot": 1, "kind": "ai", "roster": "roster.nec.vanilla", "team": 2, "credits": 1200, "handicap": 150, "ai": {"active": false}, "start": {"mode": "hq"}}
	return MissionKit.base("f_starts", {"players": [p0, p1], "rules": {"fog": false, "unit_cap": 100, "start_credits": 3000},
		"triggers": [{"id": "t_x", "when": {"kind": "structure", "state": "exists", "placed": "own_gen"}, "then": [{"do": "music_state", "state": "calm"}]}]})


func test_start_modes_credits_and_rules(t: TestCtx) -> void:
	var d: GameData = MissionKit.data({"f_starts": _starts()})
	var cfg: Dictionary = SimMissionSetup.build_config(d, "f_starts")
	var sc: SimMatchConfig = SimMatchConfig.from_dict(cfg)
	var w: SimWorld = MissionKit.world(d, "f_starts")
	if w == null:
		return
	t.eq(w.rules.start_mode, SimMatchRules.START_NONE, "the world forces start_mode NONE")
	t.eq(w.rules.victory, 0, "missions default to victory 0")
	t.eq(w.rules.unit_cap, 100, "rules override")
	t.eq(sc.rules.victory, 1, "the caller's config is left as it was (private copy)")
	t.eq(w.players[0].credits, 3000, "start_credits")
	t.eq(w.players[1].credits, 1200 * 150 / 100, "player credits x handicap")
	var mcv: int = 0
	var tanks: int = 0
	for e: SimEntity in w.units_of(0):
		if w.data.units[e.def_idx].id == "unit.shared.mobile_construction_vehicle" or e.def_idx == w.players[0].roster.mcv_idx:
			mcv += 1
		if e.def_idx == w.data.unit_idx(TANK):
			tanks += 1
	t.eq(mcv, 1, "mcv start")
	t.eq(tanks, 2)
	t.eq(w.structures_of(0).size(), 1, "the extra generator (no HQ with an MCV start)")
	t.gt(w.mission.placed_id[0], 0, "start structure registered under its placed id")
	t.eq(w.structures_of(1).size(), 1, "hq start of player 1")
	t.eq(w.structures_of(1)[0].def_idx, w.players[1].roster.hq_idx)
	var p0_cell: int = SimMissionSystem.start_cell(w, 0)
	var gen: SimEntity = w.get_entity(w.mission.placed_id[0])
	var fpw: int = w.data.structures[gen.def_idx].fp_w
	t.eq((gen.x - fpw * 512) >> 10, (p0_cell % w.map.w) - 6, "the footprint origin is the start cell + the offset (cells)")
	MissionKit.run(w, 20)
	t.eq(w.players[0].eliminated, 0, "victory 0: nobody is eliminated for lacking assets")
	t.eq(w.match_state, SimWorld.MATCH_RUNNING)
	t.eq(w.mission.trig_fired[0], 1, "structure exists (placed) is true")


func test_every_runtime_field_is_in_the_checksum(t: TestCtx) -> void:
	var w: SimWorld = MissionKit.world(MissionKit.data({"f_sem": _sem()}), "f_sem", {"events": false})
	if w == null:
		return
	MissionKit.run(w, 20)
	var cleanup_part: int = SimWorld.CHECKSUM_PART_NAMES.find("sys.cleanup")
	var base: int = int(SimStateHash.compute(w)["parts"][cleanup_part])
	var skip: PackedStringArray = ["def", "data"]
	var n: int = 0
	for p: Dictionary in w.mission.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or skip.has(str(p["name"])):
			continue
		var name: String = p["name"]
		var v: Variant = w.mission.get(name)
		var restore: Variant = v
		if typeof(v) == TYPE_INT:
			w.mission.set(name, int(v) + 1)
		elif v is PackedInt32Array:
			var a: PackedInt32Array = (v as PackedInt32Array).duplicate()
			if a.is_empty():
				continue
			a[a.size() - 1] += 1
			w.mission.set(name, a)
		elif v is Array:
			var arr: Array[PackedInt32Array] = []
			arr.assign(v as Array)
			var extra: PackedInt32Array = PackedInt32Array([7])
			arr.append(extra)
			w.mission.set(name, arr)
		else:
			t.fail("unhandled field type of " + name)
			continue
		n += 1
		t.ne(int(SimStateHash.compute(w)["parts"][cleanup_part]), base, "field %s is hashed" % name)
		w.mission.set(name, restore)
	t.ge(n, 20, "reflection covered every field (%d)" % n)
	t.eq(int(SimStateHash.compute(w)["parts"][cleanup_part]), base, "restored")


func test_skirmish_checksums_are_untouched(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"seed": 1, "bots": false})
	var w: SimWorld = m["world"]
	var cleanup_part: int = SimWorld.CHECKSUM_PART_NAMES.find("sys.cleanup")
	t.eq(int(SimStateHash.compute(w)["parts"][cleanup_part]) & 0xFFFFFFFF, Checksum.digest32(PackedInt32Array()) & 0xFFFFFFFF, "no mission: sys.cleanup digests nothing")
	t.is_null(w.mission)
	var cfg: SimMatchConfig = SimMatchKit.make_config({"seed": 1})
	var h0: int = cfg.config_hash()
	cfg.mission_id = "x"
	t.ne(cfg.config_hash(), h0, "a mission id is part of the config hash")
	cfg.mission_id = ""
	t.eq(cfg.config_hash(), h0, "and without it the hash is the old one")
	t.check(not cfg.to_dict().has("mission"), "no mission key in a plain config")


func _scenario_win() -> Dictionary:
	var start: Dictionary = {"mode": "hq", "units": [{"def": TANK, "count": 3, "dx": 4, "dy": 3}]}
	var players: Array = [
		{"slot": 0, "kind": "human", "roster": "roster.napc.vanilla", "team": 1, "start": start},
		{"slot": 1, "kind": "ai", "roster": "roster.nec.vanilla", "team": 2, "ai": {"active": false}, "start": {"mode": "none"}},
	]
	return MissionKit.base("s_win", {"players": players,
		"objectives": [{"id": "kill", "kind": "primary", "text": "Kill the raiders"}, {"id": "hq", "kind": "primary", "text": "Keep the HQ"}],
		"messages": [{"id": "hi", "text": "Here they come"}],
		"triggers": [
			{"id": "a_spawn", "when": {"kind": "time", "seconds": 2}, "then": [
				{"do": "spawn_units", "owner": 1, "def": JAGER, "count": 2, "area": "a_base", "wave": "raid"}, {"do": "show_message", "message": "hi"}]},
			{"id": "b_win", "when": {"kind": "wave", "wave": "raid", "state": "cleared"}, "then": [
				{"do": "set_objective", "objective": "kill", "state": "completed"}, {"do": "win", "owner": 0}]},
			{"id": "c_lose", "when": {"kind": "count", "owner": 0, "of": "structure", "cmp": "<=", "value": 0}, "then": [
				{"do": "set_objective", "objective": "hq", "state": "failed"}, {"do": "lose", "owner": 0}]},
		]})


func _play_win(w: SimWorld) -> void:
	var commanded: bool = false
	var guard: int = 0
	while w.match_state == SimWorld.MATCH_RUNNING and guard < 3000:
		guard += 1
		if not commanded and w.tick >= 50 and not w.units_of(1).is_empty():
			commanded = true
			var ids: PackedInt32Array = PackedInt32Array()
			for e: SimEntity in w.units_of(0):
				if e.def_idx == w.data.unit_idx(TANK):
					ids.append(e.id)
			ids.sort()
			w.submit_raw(0, SimCmd.attack(ids, w.units_of(1)[0].id))
		w.step()


func test_scripted_mission_reaches_a_win_through_commands(t: TestCtx) -> void:
	var w: SimWorld = MissionKit.world(MissionKit.data({"s_win": _scenario_win()}), "s_win")
	if w == null:
		return
	_play_win(w)
	t.eq(w.match_state, SimWorld.MATCH_ENDED, "the mission ended")
	t.eq(w.end_reason, SimWorld.EndReason.MISSION_WIN, "by the win action (tick %d)" % w.tick)
	t.eq(w.winner_team, 1)
	t.eq(w.mission.obj_state[0], SimMissionConst.OBJ_COMPLETED)
	t.eq(w.mission.obj_state[1], SimMissionConst.OBJ_ACTIVE)
	t.gt(w.players[0].st_cmds, 0, "the player's command was executed")
	t.gt(w.players[0].st_units_killed, 0, "kills are counted for the end screen")
	t.eq(w.players[1].st_units_lost, 2)
	t.check(w.end_tick > 40 and w.end_tick < 3000, "ended at a plausible tick %d" % w.end_tick)


func test_scripted_mission_reaches_a_lose_by_timeout(t: TestCtx) -> void:
	var m: Dictionary = _scenario_win()
	m["id"] = "s_lose"
	m["timers"] = [{"id": "limit", "seconds": 10, "autostart": true}]
	(m["triggers"] as Array).append({"id": "d_timeout", "when": {"kind": "timer", "timer": "limit"}, "then": [
		{"do": "set_objective", "objective": "kill", "state": "failed"}, {"do": "lose", "owner": 0}]})
	# nobody fights: no raid is ever spawned
	(m["triggers"] as Array)[0]["when"] = {"kind": "time", "seconds": 1000}
	var w: SimWorld = MissionKit.world(MissionKit.data({"s_lose": m}), "s_lose")
	if w == null:
		return
	MissionKit.run(w, 400)
	t.eq(w.end_reason, SimWorld.EndReason.MISSION_LOSE)
	t.check(w.end_tick >= 200 and w.end_tick <= 205, "at the timer: %d" % w.end_tick)
	t.eq(w.winner_team, 2)
	t.eq(w.mission.obj_state[0], SimMissionConst.OBJ_FAILED)
	t.eq(w.players[0].eliminated, 1)


func test_resignation_becomes_a_mission_defeat(t: TestCtx) -> void:
	var m: Dictionary = _scenario_win()
	m["id"] = "s_resign"
	(m["triggers"] as Array)[0]["when"] = {"kind": "time", "seconds": 1000}
	(m["triggers"] as Array).append({"id": "e_defeated", "when": {"kind": "defeated", "owner": 0}, "then": [{"do": "lose", "owner": 0}]})
	var w: SimWorld = MissionKit.world(MissionKit.data({"s_resign": m}), "s_resign")
	if w == null:
		return
	MissionKit.run(w, 10)
	w.submit_raw(0, SimCmd.resign())
	MissionKit.run(w, 20)
	t.eq(w.players[0].elim_reason, SimPlayer.Elim.RESIGN)
	t.eq(w.end_reason, SimWorld.EndReason.MISSION_LOSE, "victory 0 does not end the match; the trigger does")
	t.eq(w.match_state, SimWorld.MATCH_ENDED)


func test_two_runs_are_identical_and_events_do_not_matter(t: TestCtx) -> void:
	var d: GameData = MissionKit.data({"s_win": _scenario_win()})
	var a: SimWorld = MissionKit.world(d, "s_win", {"events": true})
	var b: SimWorld = MissionKit.world(d, "s_win", {"events": false})
	if a == null or b == null:
		return
	_play_win(a)
	_play_win(b)
	t.eq(a.checksum_log, b.checksum_log, "identical checksum chains (events on / off)")
	t.eq(a.dump_state(), b.dump_state(), "identical dumps")
	t.gt(a.checksum_log.size(), 10)
	var c: SimWorld = MissionKit.world(d, "s_win")
	_play_win(c)
	t.eq(a.events.digest(), c.events.digest(), "identical event streams")
	t.eq(c.checksum(), a.checksum())
