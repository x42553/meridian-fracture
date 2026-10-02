extends RefCounted
## MIS1 net side: a mission id in the match config (normalisation, params whitelist, config hash), the LOCAL session path of the
## game (AppNetSetup.complete_config -> NetSession.local_from_config) and a recorded mission replay that verifies; the replay version
## gate refuses a build whose mission data differs.

const P := NetSession.Phase
var _dirs: PackedStringArray = PackedStringArray()


func _dir(tag: String) -> String:
	var d: String = "user://mis1_%s_%d" % [tag, OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(d)
	_dirs.append(d)
	return d


func after_all() -> void:
	for d: String in _dirs:
		var da: DirAccess = DirAccess.open(d)
		if da != null:
			for f: String in da.get_files():
				da.remove(f)
			DirAccess.remove_absolute(d)


func _options(data: GameData, clock: NetClock) -> NetSessionOptions:
	var o: NetSessionOptions = AppNetSetup.make_options(data, {"with_view": false, "events": false, "ai": AppAiHook.new()})
	o.clock = clock
	o.replay_dir = ""
	o.speed_pct_override = 0
	o.max_ticks_per_poll = 64
	o.fixed_input_delay_turns = 0
	o.log_sink = func(_l: int, _t: String) -> void: pass
	return o


func _full_config(data: GameData, o: NetSessionOptions, id: String) -> Dictionary:
	return NetMatchConfig.normalize(AppNetSetup.complete_config(SimMissionSetup.build_config(data, id), o, 1_790_000_000))


func test_config_carries_the_mission_and_map_params(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	var o: NetSessionOptions = _options(d, NetClock.manual(0))
	var full: Dictionary = _full_config(d, o, "demo_ambush")
	if not t.check(not full.is_empty(), "the completed mission config normalises"):
		return
	t.eq(full["mission"], "demo_ambush")
	t.eq(NetMatchConfig.validate(full, o), "", "and validates")
	var cfg: SimMatchConfig = SimMatchConfig.from_dict(full)
	t.eq(cfg.mission_id, "demo_ambush", "the sim reads the id")
	var json: String = NetMatchConfig.canonical_json(full)
	t.eq(NetMatchConfig.parse(json), full, "canonical JSON round trip")
	var plain: Dictionary = full.duplicate(true)
	plain.erase("mission")
	t.check(NetMatchConfig.canonical_json(plain) != json, "the mission id changes the transmitted bytes")
	t.eq(NetMatchConfig.normalize(plain)["players"], full["players"], "a plain config is still valid")
	var bad: Dictionary = full.duplicate(true)
	bad["mission"] = "Bad-Id"
	t.eq(NetMatchConfig.normalize(bad), {}, "a malformed mission id is refused")
	bad["mission"] = ""
	t.eq(NetMatchConfig.normalize(bad), {}, "an empty one too")
	var withp: Dictionary = full.duplicate(true)
	(withp["map"] as Dictionary)["params"] = {"density": 80, "biome": 2, "start_near_water": true}
	var n: Dictionary = NetMatchConfig.normalize(withp)
	t.eq((n["map"] as Dictionary)["params"], {"density": 80, "biome": 2, "start_near_water": 1}, "whitelisted map params are kept (bool -> int)")
	for bad_params: Variant in [{"density": 101}, {"lava": 1}, {"biome": -1}, {"density": 1.5}]:
		(withp["map"] as Dictionary)["params"] = bad_params
		t.eq(NetMatchConfig.normalize(withp), {}, "refused: %s" % str(bad_params))
	# complete_config forwards params only for missions
	var raw: Dictionary = SimMissionSetup.build_config(d, "demo_ambush")
	(raw["map"] as Dictionary)["params"] = {"density": 10}
	t.eq(((AppNetSetup.complete_config(raw, o)["map"]) as Dictionary)["params"], {"density": 10})
	raw.erase("mission")
	t.eq(((AppNetSetup.complete_config(raw, o)["map"]) as Dictionary)["params"], {}, "a skirmish config never carries params")
	t.check(not AppNetSetup.complete_config(raw, o).has("mission"))


func test_unknown_mission_is_refused_by_the_world_factory(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	var cfg: Dictionary = SimMissionSetup.build_config(d, "demo_ambush")
	cfg["mission"] = "does_not_exist"
	var map: MapData = MissionKit.map_for(cfg, d)
	var seen: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(_lv: int, tag: String, msg: String) -> void: seen.append("%s: %s" % [tag, msg])
	t.is_null(SimMatchSetup.create_world(d, SimMatchConfig.from_dict(cfg), map), "SimWorld.create refuses an unknown mission")
	Log.sink = old_sink
	t.eq(seen.size(), 1, "one logged error: %s" % str(seen))


func test_local_session_records_a_mission_replay_that_verifies(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	var clock: NetClock = NetClock.manual(1_000_000)
	var o: NetSessionOptions = _options(d, clock)
	var cfg: Dictionary = _full_config(d, o, "demo_ambush")
	var s: NetSession = NetSession.local_from_config(o, cfg)
	if not t.not_null(s, "session: " + NetSession.last_create_error):
		return
	var sent: bool = false
	var guard: int = 0
	var ticks: int = 1500
	while guard < 40000 and s.phase != P.ENDED and (s.adapter() == null or s.adapter().current_tick() < ticks):
		if s.adapter() != null and s.phase == P.PLAYING and not sent and s.adapter().current_tick() >= 60:
			sent = true
			var w: SimWorld = (s.adapter() as NetSimAdapterWorld).world()
			t.not_null(w.mission, "the session's world runs the mission")
			var ids: PackedInt32Array = PackedInt32Array()
			for e: SimEntity in w.units_of(0):
				ids.append(e.id)
			ids.sort()
			var cell: int = SimMissionSystem.start_cell(w, 0)
			s.submit_command(SimCmd.move(ids, (cell % w.map.w + 3) * 1024, (cell / w.map.w + 3) * 1024))
		clock.advance_us(50_000)
		s.poll()
		guard += 1
	t.check(sent, "the human command was sent")
	var w2: SimWorld = (s.adapter() as NetSimAdapterWorld).world()
	t.eq(w2.mission.passes, (s.adapter().current_tick() + 4) / 5, "the mission was evaluated on every 5th tick")
	var final_sum: int = s.adapter().checksum_now() & 0xFFFFFFFF
	s.shutdown()
	var bytes: PackedByteArray = s.replay_bytes()
	var rd: NetReplayData = NetReplayData.from_bytes(bytes)
	if not t.not_null(rd, "replay parses"):
		return
	t.eq(str(rd.config.get("mission", "")), "demo_ambush", "the replay header records the mission")
	var path: String = _dir("rep").path_join("m.mfreplay")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var local: Dictionary = NetReplay.local_versions(o)
	var res: Dictionary = NetReplayPlayer.verify_file(path, o.world_builder, 0, local)
	t.check(bool(res["ok"]), "the mission replay verifies: " + str(res))
	t.gt(int(res["compared"]), 10)
	t.eq(int(res["final_checksum"]), final_sum, "the replay reproduces the final checksum")
	# the data of the replaying build differs in the mission file only: the version gate refuses
	var changed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions/demo_ambush.json"))
	((changed["timers"] as Array)[0] as Dictionary)["seconds"] = 61
	var d2: GameData = MissionKit.data({"demo_ambush": changed})
	var o2: NetSessionOptions = _options(d2, clock)
	t.ne(o2.data_hash, o.data_hash, "a changed mission file changes the data hash")
	var res2: Dictionary = NetReplayPlayer.verify_file(path, o2.world_builder, 0, NetReplay.local_versions(o2))
	t.check(not bool(res2["ok"]), "a build with a different mission is refused: " + str(res2["error"]))
