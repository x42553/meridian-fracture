extends RefCounted
## Determinism D1-D3 of the strategic domain (economy 10.3): the 8-player scenario of tests/support/strat_scenario.gd (every
## faction, every superweapon, every roster's three powers, Trident domes, EMP cancelling a warning) run twice in one
## process, by two worlds stepped alternately, and replayed from its recorded commands; plus proof that the run really
## exercised the features. The cross-platform chain is tests/scenarios/xplat_strategic.gd.

const SC := preload("res://tests/support/strat_scenario.gd")


func test_double_run_identical_chain(t: TestCtx) -> void:
	var a: PackedInt64Array = SC.run_chain()
	var b: PackedInt64Array = SC.run_chain()
	t.gt(a.size(), 90, "a chain of checkpoints (every 20 ticks) plus final, event digest and state dump")
	t.eq(a, b, "two runs: identical checkpoints, checksum, event digest and state dump")


func test_replay_from_the_recorded_commands(t: TestCtx) -> void:
	var cmd_log: SimCommandLog = SimCommandLog.new()
	var w: SimWorld = SC.build()
	for s: int in SC.TICKS:
		SC.script(w, s, cmd_log)
		w.step()
	cmd_log.finish(w)
	t.gt(cmd_log.cmds.size(), 30, "commands recorded (24 powers + 8 launches)")
	var w2: SimWorld = SC.build()
	var i: int = 0
	while w2.tick < w.tick:
		while i < cmd_log.cmds.size() and cmd_log.ticks[i] == w2.tick:
			w2.submit_raw(cmd_log.pids[i], cmd_log.cmds[i])
			i += 1
		w2.step()
	var bad: int = -1
	var k: int = 0
	while k + 1 < cmd_log.checkpoints.size():
		if cmd_log.checkpoints[k] <= w2.tick and w2.checksum_at(int(cmd_log.checkpoints[k])) != cmd_log.checkpoints[k + 1]:
			bad = int(cmd_log.checkpoints[k])
			break
		k += 2
	t.eq(bad, -1, "every recorded checkpoint agrees (first mismatch at %d)" % bad)
	t.eq(w2.checksum(), w.checksum(), "and the final checksum")
	var wire: SimCommandLog = SimCommandLog.from_ints(cmd_log.to_ints())
	t.not_null(wire, "the cmd_log round-trips through its wire form")


func test_two_worlds_stepped_alternately_agree(t: TestCtx) -> void:
	var w1: SimWorld = SC.build()
	var w2: SimWorld = SC.build()
	for s: int in 700:
		SC.script(w1, s)
		SC.script(w2, s)
		w1.step()
		w2.step()
		if s % 50 == 0:
			t.eq(w1.checksum(), w2.checksum(), "tick %d" % s)
	t.eq(w1.checksum(), w2.checksum(), "tick 700")


func test_reads_do_not_change_state(t: TestCtx) -> void:
	var plain: PackedInt64Array = SC.run_chain()
	var w: SimWorld = SC.build()
	var out: Array[SimWarning] = []
	for s: int in SC.TICKS:
		SC.script(w, s)
		w.step()
		if s % 7 == 0:
			out.clear()
			for pid: int in 8:
				w.strategic.warnings_affecting(pid, out)
				w.strategic.attacks_pending_against(pid, out)
				w.strategic.cooldown_left_ticks(w, pid, 3)
				w.strategic.can_activate(w, pid, 0, 30 * 1024, 30 * 1024, 0, 0)
			for wr: SimWarning in w.strategic.warnings:
				SimSuperweapons.danger_fraction_bp(w, wr, 40 * 1024, 30 * 1024, w.tick + 100)
	t.eq(w.checksum(), plain[plain.size() - 3], "queries in between change nothing")


func test_the_scenario_exercises_the_features_and_stays_valid(t: TestCtx) -> void:
	var cov: Dictionary = SC.run_counting()
	var w: SimWorld = cov["_world"]
	t.ge(int(cov.get(SimEconConst.EVT_POWER_ACTIVATED, 0)), 30, "24 powers (minus rejections) and 8 launches")
	t.ge(int(cov.get(SimEconConst.EVT_WARNING, 0)), 10, "warnings: 8 superweapons + the warned powers")
	t.eq(int(cov.get(SimEconConst.EVT_SW_CANCELLED, 0)), 1, "the EMP cancelled the Horizon warning")
	t.ge(int(cov.get(SimEconConst.EVT_SW_EXEC_START, 0)), 9, "seven superweapons and the warned powers executed")
	t.ge(int(cov.get(SimEconConst.EVT_SW_IMPACT, 0)), 8, "impact events")
	t.ge(int(cov.get(SimEconConst.EVT_POWER_EFFECT_END, 0)), 15, "effect ends")
	t.eq(w.strategic.warnings.size(), 0, "no warning record left")
	t.eq(w.zones.debug_validate(w), PackedStringArray(), "zones validate")
	t.eq(w.abilities.debug_validate(w), PackedStringArray(), "abilities validate")
	var launched: int = 0
	for pid: int in 8:
		if w.players[pid].econ.slots[SimEconConst.SLOT_SW].last_activation_tick >= 0:
			launched += 1
	t.eq(launched, 8, "all eight superweapons were fired")


func _h(sys: SimStrategicSystem) -> int:
	var buf: PackedInt32Array = PackedInt32Array()
	sys.hash_into(buf)
	return Checksum.digest32(buf) if not buf.is_empty() else 0


func test_every_persistent_field_is_hashed(t: TestCtx) -> void:
	var sys: SimStrategicSystem = SimStrategicSystem.new()
	t.eq(_h(sys), 0, "a pristine system hashes nothing (goldens of matches without powers are unchanged)")
	var base_fields: PackedStringArray = PackedStringArray(["warnings", "sched", "next_warning_id", "next_seq", "windows", "stat_activations", "stat_launches"])
	for p: Dictionary in sys.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and not str(p["name"]).begins_with("_"):
			t.check(base_fields.has(str(p["name"])), "field %s is known to the hash test" % str(p["name"]))
	var w: SimWarning = SimWarning.new()
	w.id = 1
	var mutators: Array[Callable] = [
		func(s: SimStrategicSystem) -> void: s.warnings.append(w),
		func(s: SimStrategicSystem) -> void: s.schedule(50, SimEconConst.SK_WINDOW_END, 0, 1, 0),
		func(s: SimStrategicSystem) -> void: s.next_warning_id = 7,
		func(s: SimStrategicSystem) -> void: s.next_seq = 9,
		func(s: SimStrategicSystem) -> void: s.set_window(0, 3, 100),
		func(s: SimStrategicSystem) -> void: s.stat_activations = 4,
		func(s: SimStrategicSystem) -> void: s.stat_launches = 5,
	]
	var seen: Dictionary = {}
	for i: int in mutators.size():
		var s2: SimStrategicSystem = SimStrategicSystem.new()
		mutators[i].call(s2)
		var h: int = _h(s2)
		t.ne(h, 0, "mutator %d changes the hash" % i)
		seen[h] = true
	t.eq(seen.size(), mutators.size(), "and each one differently")
	# every SimWarning / SimScheduled / SimPowerSlot field is covered by the record hash (economy reflection test)
	var a: SimStrategicSystem = SimStrategicSystem.new()
	var b: SimStrategicSystem = SimStrategicSystem.new()
	var w1: SimWarning = SimWarning.new()
	var w2: SimWarning = SimWarning.new()
	w1.id = 1
	w2.id = 1
	a.warnings.append(w1)
	b.warnings.append(w2)
	t.eq(_h(a), _h(b), "equal state, equal hash")
	w2.affected_mask = 3
	t.ne(_h(a), _h(b), "affected_mask is hashed")
	w2.affected_mask = 0
	w2.payload_ids = PackedInt32Array([4])
	t.ne(_h(a), _h(b), "payload_ids is hashed")
