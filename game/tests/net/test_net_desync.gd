extends RefCounted
## NET-9 (lean): NetDesync classification, package files + retention, session-level detection (S13) and
## NetSelfTest.run_double ok / failure detection.

const P := NetSession.Phase


func _dir() -> String:
	return "user://desync_unit_%d" % OS.get_process_id()


func _clean(dir: String) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(dir)


func _stepped_fake(ticks: int) -> NetSimAdapterFake:
	var f: NetSimAdapterFake = NetSimAdapterFake.new(3)
	for _i: int in ticks:
		f.step()
	return f


func test_classification_table(t: TestCtx) -> void:
	var K := NetProtocol.DesyncKind
	t.eq(NetDesync.classify(5, 5, 9, 9), K.NONE)
	t.eq(NetDesync.classify(5, 5, 9, 10), K.SIM, "chain equal, checksum differs")
	t.eq(NetDesync.classify(5, 6, 9, 9), K.INPUT_CHAIN, "chain differs, checksum equal")
	t.eq(NetDesync.classify(5, 6, 9, 10), K.BOTH)
	t.eq(NetDesync.classify(0xFFFFFFFF, -1, 1, 1), K.NONE, "compares as u32")
	t.eq(NetDesync.kind_name(K.SIM), "sim")
	t.eq(NetDesync.kind_name(K.INPUT_CHAIN), "input_chain")
	t.eq(NetDesync.kind_name(K.BOTH), "both")


func test_host_compare_pending_and_ring(t: TestCtx) -> void:
	var f: NetSimAdapterFake = NetSimAdapterFake.new(3)
	var d: NetDesync = NetDesync.new()
	d.setup(f, true, 0, "a3f19c0e5b7d2468", "{}")
	var found: Array = []
	d.on_detected = func(tick: int, kind: int, ents: Array) -> void: found.append([tick, kind, ents])
	# a report for a tick the host has not reached waits in the pending list
	d.on_report(1, 40, 0x1234, 0x99)
	for i: int in 40:
		f.step()
		if (i + 1) % 20 == 0:
			d.local_snapshot(i + 1, f.checksum_at(i + 1), 0x55)
	t.eq(found.size(), 1, "the pending report was compared when the host reached tick 40")
	t.eq(int((found[0] as Array)[0]), 40)
	t.eq(int((found[0] as Array)[1]), NetProtocol.DesyncKind.BOTH)
	var entries: Array = (found[0] as Array)[2] as Array
	t.eq(int((entries[0] as PackedInt64Array)[0]), 0, "the host's own entry first")
	t.eq(int((entries[1] as PackedInt64Array)[0]), 1)
	t.check(d.is_detected())
	t.eq(d.detected_tick(), 40)
	t.eq(d.last_good_tick(), 20)
	# matching reports are silent; later reports at the detected tick are collected
	var d2: NetDesync = NetDesync.new()
	d2.setup(f, true, 0, "a3f19c0e5b7d2468", "{}")
	var n2: PackedInt32Array = PackedInt32Array([0])
	d2.on_detected = func(_t: int, _k: int, _e: Array) -> void: n2[0] += 1
	d2.local_snapshot(20, f.checksum_at(20), 0x55)
	d2.on_report(1, 20, f.checksum_at(20), 0x55)
	t.eq(n2[0], 0)
	d2.on_report(1, 20, f.checksum_at(20) ^ 1, 0x55)
	t.eq(n2[0], 1)
	t.eq(d2.detected_kind(), NetProtocol.DesyncKind.SIM)
	d2.on_report(2, 20, 7, 0x55)
	t.eq(n2[0], 1, "only the first mismatch is announced")
	# reports older than the ring are ignored
	var d3: NetDesync = NetDesync.new()
	d3.setup(f, true, 0, "a3f19c0e5b7d2468", "{}")
	d3.on_detected = func(_t: int, _k: int, _e: Array) -> void: n2[0] += 100
	for i: int in 70:
		d3.local_snapshot((i + 1) * 20, i, 1)
	t.eq(d3.snapshot_count(), 64)
	d3.on_report(1, 20, 12345, 1)
	t.eq(n2[0], 1, "tick 20 fell out of the ring")
	# a client stores the host's notice
	var d4: NetDesync = NetDesync.new()
	d4.setup(f, false, 1, "a3f19c0e5b7d2468", "{}")
	d4.on_notice(60, NetProtocol.DesyncKind.SIM, [PackedInt64Array([0, 1, 2])])
	t.check(d4.is_detected() and d4.detected_tick() == 60)
	d4.on_report(0, 60, 1, 1)
	t.eq(d4.detected_kind(), NetProtocol.DesyncKind.SIM, "clients never run the host comparison")


func test_package_files_and_retention(t: TestCtx) -> void:
	var dir: String = _dir()
	_clean(dir)
	var f: NetSimAdapterFake = _stepped_fake(60)
	var made: PackedStringArray = PackedStringArray()
	for n: int in 12:
		var d: NetDesync = NetDesync.new()
		d.setup(f, false, 1, "%08x5b7d2468" % (0xa3f19c00 + n), "{\"x\":1}")
		d.dir = dir
		d.keep = 10
		d.context = {"peer_id": 2, "role": "client", "versions": {"game": "0.1.0", "proto": 1, "sim": 1}, "delay": 2, "violations": 0}
		d.local_snapshot(20, f.checksum_at(20), 7)
		d.local_snapshot(40, f.checksum_at(40), 8)
		d.on_notice(40, NetProtocol.DesyncKind.SIM, [PackedInt64Array([0, 99, 8]), PackedInt64Array([1, f.checksum_at(40), 8])])
		d.on_parts(0, 40, PackedInt32Array([11, 22]))
		var rep: Dictionary = d.write_package(PackedByteArray([1, 2, 3]), PackedStringArray(["[net] line one", "[net] line two"]))
		var base: String = str((rep["files"] as Dictionary)["json"]).trim_suffix(".json")
		made.append(base)
		t.eq(int(rep["tick"]), 40)
		t.eq(str(rep["kind"]), "sim")
		t.eq(rep["last_good_tick"], 20)
		t.eq(int((rep["local"] as Dictionary)["pid"]), 1)
		t.eq(rep["part_names"], ["cmds", "clock"])
		if n == 0:
			var files: Dictionary = rep["files"] as Dictionary
			for key: String in ["json", "state", "replay", "checks"]:
				t.check(files.has(key) and FileAccess.file_exists(dir.path_join(str(files[key]))), "package file " + key)
			var checks: String = FileAccess.get_file_as_string(dir.path_join(str(files["checks"])))
			t.check(checks.begins_with("tick,checksum,chain,cmds,clock\n20,"), "checks.csv rows")
			var state: String = FileAccess.get_file_as_string(dir.path_join(str(files["state"])))
			t.eq(state, f.dump_state())
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(str(files["json"]))))
			t.check(parsed is Dictionary and int((parsed as Dictionary)["format"]) == 1 and (parsed as Dictionary).has("platform"))
			t.check(str(rep["message"]).contains("00:02 (tick 40)"), str(rep["message"]))
	# foreign files are never deleted; only the newest 10 packages survive
	var probe: FileAccess = FileAccess.open(dir.path_join("notes.txt"), FileAccess.WRITE)
	probe.store_string("keep me")
	probe.close()
	var d5: NetDesync = NetDesync.new()
	d5.setup(f, false, 1, "ffffffffffffffff", "{}")
	d5.dir = dir
	d5.local_snapshot(20, 1, 1)
	d5.on_notice(20, NetProtocol.DesyncKind.SIM, [])
	d5.write_package(PackedByteArray(), PackedStringArray())
	var bases: PackedStringArray = d5.package_bases()
	t.eq(bases.size(), 10, "newest 10 kept")
	t.check(not bases.has(made[0]) and not bases.has(made[1]) and not bases.has(made[2]), "the oldest packages were removed")
	t.check(bases.has(made[11]))
	t.check(FileAccess.file_exists(dir.path_join("notes.txt")), "unrelated files are never deleted")
	t.check(not FileAccess.file_exists(dir.path_join(made[0] + ".json")))
	t.check(not FileAccess.file_exists(dir.path_join(made[0] + ".state.txt")))
	_clean(dir)


func _paced_options() -> Dictionary:
	return {"speed_pct_override": -1, "max_ticks_per_poll": 8}


func test_injected_divergence_is_detected_and_packaged(t: TestCtx) -> void:
	var kit: NetSessionKit = NetSessionKit.new()
	kit.builders["P3"] = func(cfg: Dictionary) -> NetWorldJob:
		var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
		return NetWorldJob.sync(func() -> NetSimAdapter:
			var f: NetSimAdapterFake = NetSimAdapterFake.new(seed_v)
			f.inject_divergence(400, 1)
			return f)
	var h: NetSession = kit.lobby_of(2, _paced_options(), _paced_options())
	for i: int in kit.sessions.size():
		kit.sessions[i].lobby.set_team(1 + i)
		if i > 0:
			kit.sessions[i].lobby.set_ready(true)
	kit.step(4)
	var reports: Array = []
	for s: NetSession in kit.sessions:
		s.desync_detected.connect(func(r: Dictionary) -> void: reports.append(r))
	h.lobby.host_start()
	t.check(kit.all_in(P.PLAYING, 200))
	var bad: NetSession = kit.sessions[2]
	# run until the diverging client passes tick 400
	t.check(kit.run_until(func() -> bool: return bad.adapter().current_tick() >= 400, 1200))
	var steps: int = 0
	while h.phase != P.DESYNCED and steps < 60:
		kit.step(1)
		steps += 1
	t.le(steps * 50, 1200, "detected within 1.2 s of virtual time after tick 400 (%d ms)" % (steps * 50))
	t.check(kit.all_in(P.DESYNCED, 100), "every peer is DESYNCED")
	t.check(kit.run_until(func() -> bool: return reports.size() >= 3, 200), "all three peers raised desync_detected")
	for r: Variant in reports:
		var rep: Dictionary = r as Dictionary
		t.eq(str(rep["kind"]), "sim")
		t.eq(int(rep["tick"]), 400)
		var local_pid: int = int((rep["local"] as Dictionary)["pid"])
		t.eq(rep["parts_diff"], ["clock"] if local_pid != 1 else [], "pid %d: only the diverging peer differs from the others" % local_pid)
		t.eq(int(rep["last_good_tick"]), 380)
		var files: Dictionary = rep["files"] as Dictionary
		for key: String in ["json", "state", "replay", "checks"]:
			t.check(files.has(key) and FileAccess.file_exists(kit.desync_dir.path_join(str(files[key]))), "%s file exists for pid %d" % [key, int((rep["local"] as Dictionary)["pid"])])
	var line_found: bool = false
	for l: String in kit.log_errors:
		if l.contains("DESYNC") and l.contains("kind=SIM") and l.contains("tick=400"):
			line_found = true
	t.check(line_found, "the greppable error line")
	# the world stays readable and the lockstep is stopped
	var tk: int = h.adapter().current_tick()
	kit.step(20)
	t.eq(h.adapter().current_tick(), tk)
	kit.shutdown_all()


func test_run_double_ok_and_failure_detection(t: TestCtx) -> void:
	var cfg: Dictionary = _fake_config()
	var script: Array = [
		{"tick": 5, "ints": PackedInt32Array([1, 2, 3])}, {"tick": 40, "ints": PackedInt32Array([9])},
		{"tick": 41, "ints": PackedInt32Array([4, -5, 262144])}, {"tick": 300, "ints": PackedInt32Array([7, 7])},
	]
	var builder: Callable = func(c: Dictionary) -> NetWorldJob: return NetSessionKit.fake_job(c)
	var r: Dictionary = NetSelfTest.run_double(cfg, builder, script, 600)
	t.eq(str(r["error"]), "")
	t.check(bool(r["ok"]), str(r))
	t.gt(int(r["compared"]), 25)
	t.eq(int(r["first_mismatch_tick"]), -1)
	t.eq(int(r["chain_a"]), int(r["chain_b"]))
	t.eq(int(r["final_a"]), int(r["final_b"]))
	t.eq(int(r["state_hash_a"]), int(r["state_hash_b"]))
	t.eq(str(r["mode"]), "commandlog+replay")
	t.check(bool(r["replay_ok"]), str(r["replay_error"]))
	t.gt(int(r["replay_compared"]), 0)
	# a second identical run gives the same numbers
	var r2: Dictionary = NetSelfTest.run_double(cfg, builder, script, 600)
	t.eq(int(r2["final_a"]), int(r["final_a"]))
	t.eq(int(r2["chain_a"]), int(r["chain_a"]))
	# with AI thinkers (commands travel through the bundles)
	var ai: Callable = func(pid: int, _l: int, _s: int, _seed: int) -> Callable:
		return func(_w: RefCounted, out: Array) -> void: out.append(PackedInt32Array([9, pid, 1]))
	var cfg_ai: Dictionary = _fake_config(true)
	var r3: Dictionary = NetSelfTest.run_double(cfg_ai, builder, [], 400, ai)
	t.check(bool(r3["ok"]), str(r3))
	# failure detection: the replay world is built with an injected divergence
	var calls: PackedInt32Array = PackedInt32Array([0])
	var faulty: Callable = func(c: Dictionary) -> NetWorldJob:
		calls[0] += 1
		var seed_v: int = int((c["map"] as Dictionary)["seed"])
		var second: bool = calls[0] >= 2
		return NetWorldJob.sync(func() -> NetSimAdapter:
			var f: NetSimAdapterFake = NetSimAdapterFake.new(seed_v)
			if second:
				f.inject_divergence(400, 1)
			return f)
	var bad: Dictionary = NetSelfTest.run_double(cfg, faulty, script, 600)
	t.check(not bool(bad["ok"]))
	t.eq(int(bad["first_mismatch_tick"]), 400)
	t.eq(bad["parts"], PackedStringArray(["clock"]))
	# an unbuildable config is reported, not crashed on
	var broken: Dictionary = NetSelfTest.run_double({"nonsense": 1}, builder, [], 100)
	t.check(not bool(broken["ok"]) and str(broken["error"]) != "")


## A minimal valid MatchConfig for the fake world: 1 human (peer 1) + 1 AI (or 2 humans-less when with_ai).
func _fake_config(two_ai: bool = false) -> Dictionary:
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.ae.a")
	st.map_size = 96
	st.layout_players = 2
	if two_ai:
		st.slots[0].kind = NetProtocol.SlotKind.AI
		st.slots[0].peer_id = 0
		st.slots[0].name = "AI 1"
	var ids: PackedStringArray = NetSessionKit.roster_ids()
	var raw: Dictionary = NetMatchConfig.from_lobby(st, 12345, {"game": "0", "proto": 1, "sim": 1, "data_hash": 0, "data_format": 0, "data_ids": 0}, 1_790_000_000, ids)
	return NetMatchConfig.parse(NetMatchConfig.canonical_json(raw))
