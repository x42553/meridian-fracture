extends SceneTree
## Cross-platform determinism scenario for the MISSION system (MIS1): the shipped demo mission (ambush wave, AI switched off, a lose by
## script) with scripted human commands, plus an in-memory mission that reaches a win through commands (spawns, orders, waves,
## timers, objectives, win). Run:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_mission.gd
## `HASH tick=<n> <hex>`: every checkpoint of both worlds' checksum logs (second world offset by 100000), then the final checksum,
## event digest and dump digest of each. Two runs in one process must be identical (SELFCHECK).

const DEMO_TICKS: int = 3400


func _initialize() -> void:
	var first: PackedStringArray = _run()
	var second: PackedStringArray = _run()
	if first != second:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE lines=%d" % first.size())
	MissionKit.release()
	quit(0)


func _win_mission() -> Dictionary:
	var start: Dictionary = {"mode": "hq", "units": [{"def": "unit.napc.guardian_tank", "count": 3, "dx": 4, "dy": 3}]}
	var players: Array = [
		{"slot": 0, "kind": "human", "roster": "roster.napc.vanilla", "team": 1, "start": start},
		{"slot": 1, "kind": "ai", "roster": "roster.nec.vanilla", "team": 2, "ai": {"active": false}, "start": {"mode": "none"}},
	]
	return MissionKit.base("x_win", {"players": players,
		"objectives": [{"id": "kill", "kind": "primary", "text": "Kill"}],
		"messages": [{"id": "hi", "text": "Hi", "announcer": "base_under_attack"}],
		"timers": [{"id": "tm", "seconds": 3, "repeat": true, "autostart": true}],
		"triggers": [
			{"id": "a_spawn", "when": {"kind": "time", "seconds": 2}, "then": [
				{"do": "spawn_units", "owner": 1, "def": "unit.nec.jager_squad", "count": 2, "area": "a_base", "wave": "raid"},
				{"do": "spawn_structure", "owner": 1, "def": "structure.shared.generator", "area": "a_far", "id": "gen"},
				{"do": "show_message", "message": "hi"}, {"do": "reveal_area", "owner": 0, "area": "a_far", "seconds": 4}]},
			{"id": "b_pay", "once": false, "cooldown_s": 3, "when": {"kind": "timer", "timer": "tm"}, "then": [{"do": "give_credits", "owner": 0, "amount": 50}]},
			{"id": "c_win", "when": {"kind": "wave", "wave": "raid", "state": "cleared"}, "then": [
				{"do": "set_objective", "objective": "kill", "state": "completed"}, {"do": "win", "owner": 0}]},
		]})


func _chain(w: SimWorld, base: int, out: PackedStringArray) -> void:
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [base + w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=%d %08x" % [base + 9001, w.checksum()])
	out.append("HASH tick=%d %08x" % [base + 9002, w.events.digest()])
	out.append("HASH tick=%d %08x" % [base + 9003, Checksum.fnv_string(w.dump_state())])


func _tanks(w: SimWorld) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in w.units_of(0):
		if e.def_idx == w.data.unit_idx("unit.napc.guardian_tank"):
			ids.append(e.id)
	ids.sort()
	return ids


func _run() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var d: GameData = MissionKit.data()
	var w: SimWorld = MissionKit.world(d, "demo_ambush")
	var cell: int = SimMissionSystem.start_cell(w, 0)
	var cx: int = cell % w.map.w
	var cy: int = cell / w.map.w
	for _i: int in DEMO_TICKS:
		if w.match_state != SimWorld.MATCH_RUNNING:
			break
		if w.tick == 100:
			w.submit_raw(0, SimCmd.move(_tanks(w), (cx + 6) * 1024, (cy + 2) * 1024))
		if w.tick == 1300 and not w.units_of(1).is_empty():
			w.submit_raw(0, SimCmd.attack(_tanks(w), w.units_of(1)[0].id))
		if w.tick == 1500:
			w.submit_raw(0, SimCmd.attack_move(_tanks(w), (cx + 10) * 1024, cy * 1024))
		w.step()
	_chain(w, 0, out)
	out.append("MISSION demo ended=%d reason=%d tick=%d winner=%d" % [w.match_state, w.end_reason, w.end_tick, w.winner_team])
	var d2: GameData = MissionKit.data({"x_win": _win_mission()})
	var w2: SimWorld = MissionKit.world(d2, "x_win")
	var commanded: bool = false
	for _i: int in 3000:
		if w2.match_state != SimWorld.MATCH_RUNNING:
			break
		if not commanded and w2.tick >= 50 and not w2.units_of(1).is_empty():
			commanded = true
			w2.submit_raw(0, SimCmd.attack(_tanks(w2), w2.units_of(1)[0].id))
		w2.step()
	_chain(w2, 100000, out)
	out.append("MISSION win ended=%d reason=%d tick=%d winner=%d" % [w2.match_state, w2.end_reason, w2.end_tick, w2.winner_team])
	return out
