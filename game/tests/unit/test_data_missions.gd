extends RefCounted
## MIS1 data side: the mission files are manifest content (parsed by DefMissionCompiler, covered by the data hash, the handshake and
## the per-file hashes) and every malformed field is a V-MIS-* error. Negative cases mutate in-memory copies only.

const FAM_NAMES: PackedStringArray = ["open", "urban", "coast"]


func _good() -> Dictionary:
	return MissionKit.base("t_good", {
		"objectives": [{"id": "o1", "kind": "primary", "text": "Do it"}, {"id": "o2", "kind": "hidden", "text": "Secret"}],
		"messages": [{"id": "m1", "text": "Hello", "announcer": "base_under_attack"}],
		"timers": [{"id": "tm1", "seconds": 5}],
		"triggers": [{"id": "t1", "when": {"kind": "time", "seconds": 1}, "then": [{"do": "show_message", "message": "m1"}]}],
	})


## Error text of loading the good mission after `mutate` (a Callable taking the mission Dictionary).
func _err(mutate: Callable) -> String:
	var m: Dictionary = _good()
	mutate.call(m)
	return MissionKit.load_error({"t_good": m})


func _rejects(t: TestCtx, rule: String, label: String, mutate: Callable) -> void:
	var e: String = _err(mutate)
	t.check(e.contains(rule), "%s: expected %s, got: %s" % [label, rule, e.substr(0, 300)])


func test_shipped_demo_mission_loads_and_is_in_the_table(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	if not t.not_null(d, "real data loads"):
		return
	var tab: DefMissionTable = DefMissionTable.of(d)
	if not t.not_null(tab, "missions table"):
		return
	var m: DefMission = tab.get_mission("demo_ambush")
	if not t.not_null(m, "demo_ambush"):
		return
	t.eq(m.players.size(), 2)
	t.eq(m.layout_players, 2)
	t.eq(m.triggers[0].id, "a_start", "triggers sorted by id")
	t.check(d.table_hashes.has("missions"), "table hash")
	t.check(d.file_hashes().has("missions/demo_ambush.json"), "per-file hash")
	t.eq(m.rules["victory"], 0, "missions default to victory 0")
	t.eq(m.waves, PackedStringArray(["raiders"]))
	t.eq(m.announcers, PackedStringArray(["base_under_attack"]))


func test_good_synthetic_mission_compiles_with_defaults(t: TestCtx) -> void:
	var d: GameData = MissionKit.data({"t_good": _good()})
	if not t.not_null(d, "loads"):
		return
	var m: DefMission = DefMissionTable.of(d).get_mission("t_good")
	t.eq(m.group, "custom")
	t.eq(m.players[0].ui_name, "Commander")
	t.eq(m.players[1].ui_name, "Hostiles")
	t.eq(m.players[1].ai_active, false)
	t.eq(m.players[1].ai_level, 1)
	t.eq(m.objectives[1].initial, 0, "hidden objective starts hidden")
	t.eq(m.objectives[0].initial, 1, "default initial state active")
	t.eq(m.timers[0].ticks, 100, "5 s = 100 ticks")
	t.eq(m.areas.size(), 4)
	t.eq(m.areas[0].anchor, DefMissionArea.Anchor.START)
	t.eq(m.sim_seed, 3, "sim_seed defaults to the map seed")
	t.eq(m.map_family, 0)


func test_data_hash_covers_mission_content_but_not_texts(t: TestCtx) -> void:
	var base: Dictionary = _good()
	var a: GameData = MissionKit.data({"t_good": base})
	var changed_number: Dictionary = _good()
	(changed_number["timers"] as Array)[0]["seconds"] = 6
	var b: GameData = MissionKit.data({"t_good": changed_number})
	var changed_text: Dictionary = _good()
	(changed_text["messages"] as Array)[0]["text"] = "Different words"
	var c: GameData = MissionKit.data({"t_good": changed_text})
	if not (t.not_null(a, "a") and t.not_null(b, "b") and t.not_null(c, "c")):
		return
	t.ne(a.data_hash(), b.data_hash(), "a changed number changes data_hash")
	t.ne(a.table_hashes["missions"], b.table_hashes["missions"])
	t.eq(a.table_hashes["units"], b.table_hashes["units"], "other tables untouched")
	t.eq(a.data_hash(), c.data_hash(), "a text edit is not part of data_hash")
	var diff_n: PackedStringArray = GameData.diff_handshake(a.handshake(true), b.handshake(true))
	t.eq(diff_n, PackedStringArray(["file missions/t_good.json differs", "table missions differs"]), "handshake names the file: %s" % str(diff_n))
	var diff_t: PackedStringArray = GameData.diff_handshake(a.handshake(true), c.handshake(true))
	t.eq(diff_t, PackedStringArray(["file missions/t_good.json differs"]), "text change: file differs only: %s" % str(diff_t))
	var none: GameData = MissionKit.data({})
	t.ne(none.data_hash(), a.data_hash(), "adding a mission file changes data_hash")


func test_schema_and_identity_errors(t: TestCtx) -> void:
	_rejects(t, "V-MIS-01", "wrong schema", func(m: Dictionary) -> void: m["schema"] = "meridian.mission/2")
	_rejects(t, "V-MIS-01", "id vs file", func(m: Dictionary) -> void: m["id"] = "other")
	_rejects(t, "V-MIS-01", "bad id chars", func(m: Dictionary) -> void: m["id"] = "T-Good")
	_rejects(t, "V-MIS-02", "unknown top key", func(m: Dictionary) -> void: m["typo"] = 1)
	_rejects(t, "V-MIS-02", "title missing", func(m: Dictionary) -> void: m.erase("title"))
	_rejects(t, "V-MIS-02", "float", func(m: Dictionary) -> void: m["order"] = 1.5)
	_rejects(t, "V-MIS-02", "order range", func(m: Dictionary) -> void: m["order"] = 10000)


func test_map_player_and_rule_errors(t: TestCtx) -> void:
	_rejects(t, "V-MIS-02", "bad family", func(m: Dictionary) -> void: (m["map"] as Dictionary)["family"] = "moon")
	_rejects(t, "V-MIS-06", "size not multiple of 8", func(m: Dictionary) -> void: (m["map"] as Dictionary)["size"] = 100)
	_rejects(t, "V-MIS-02", "size range", func(m: Dictionary) -> void: (m["map"] as Dictionary)["size"] = 64)
	_rejects(t, "V-MIS-02", "map param range", func(m: Dictionary) -> void: (m["map"] as Dictionary)["params"] = {"water_pct": 90})
	_rejects(t, "V-MIS-02", "map param key", func(m: Dictionary) -> void: (m["map"] as Dictionary)["params"] = {"lava": 1})
	_rejects(t, "V-MIS-06", "no human", func(m: Dictionary) -> void: (m["players"] as Array)[0]["kind"] = "ai")
	_rejects(t, "V-MIS-06", "two humans", func(m: Dictionary) -> void: (m["players"] as Array)[1]["kind"] = "human")
	_rejects(t, "V-MIS-04", "duplicate slot", func(m: Dictionary) -> void: (m["players"] as Array)[1]["slot"] = 0)
	_rejects(t, "V-MIS-04", "duplicate colour", func(m: Dictionary) -> void: (m["players"] as Array)[0]["color"] = 1)
	_rejects(t, "V-MIS-04", "duplicate start slot", func(m: Dictionary) -> void: (m["players"] as Array)[1]["start_slot"] = 0)
	_rejects(t, "V-MIS-03", "unknown roster", func(m: Dictionary) -> void: (m["players"] as Array)[1]["roster"] = "roster.nope.vanilla")
	_rejects(t, "V-MIS-02", "team range", func(m: Dictionary) -> void: (m["players"] as Array)[1]["team"] = 5)
	_rejects(t, "V-MIS-02", "player name chars", func(m: Dictionary) -> void: (m["players"] as Array)[1]["name"] = "Bad[Name]")
	_rejects(t, "V-MIS-02", "handicap step", func(m: Dictionary) -> void: (m["players"] as Array)[1]["handicap"] = 101)
	_rejects(t, "V-MIS-05", "ai block on human", func(m: Dictionary) -> void: (m["players"] as Array)[0]["ai"] = {"level": 1})
	_rejects(t, "V-MIS-02", "bad start mode", func(m: Dictionary) -> void: ((m["players"] as Array)[0]["start"] as Dictionary)["mode"] = "teleport")
	_rejects(t, "V-MIS-03", "unknown start unit", func(m: Dictionary) -> void: ((m["players"] as Array)[0]["start"] as Dictionary)["units"] = [{"def": "unit.nope"}])
	_rejects(t, "V-MIS-02", "unknown rule", func(m: Dictionary) -> void: (m["rules"] as Dictionary)["start_mode"] = 1)
	_rejects(t, "V-MIS-02", "rule range", func(m: Dictionary) -> void: (m["rules"] as Dictionary)["unit_cap"] = 5)
	_rejects(t, "V-MIS-06", "no players", func(m: Dictionary) -> void: m["players"] = [])


func test_area_message_objective_timer_errors(t: TestCtx) -> void:
	_rejects(t, "V-MIS-04", "duplicate area", func(m: Dictionary) -> void: (m["areas"] as Array)[1]["id"] = "a_base")
	_rejects(t, "V-MIS-02", "bad shape", func(m: Dictionary) -> void: (m["areas"] as Array)[0]["shape"] = "star")
	_rejects(t, "V-MIS-03", "bad anchor slot", func(m: Dictionary) -> void: (m["areas"] as Array)[0]["anchor"] = "start:5")
	_rejects(t, "V-MIS-02", "circle needs r", func(m: Dictionary) -> void: (m["areas"] as Array)[0].erase("r"))
	_rejects(t, "V-MIS-02", "map permille", func(m: Dictionary) -> void: (m["areas"] as Array)[2]["x"] = 1001)
	_rejects(t, "V-MIS-04", "duplicate message", func(m: Dictionary) -> void: (m["messages"] as Array).append({"id": "m1", "text": "x"}))
	_rejects(t, "V-MIS-04", "duplicate objective", func(m: Dictionary) -> void: (m["objectives"] as Array).append({"id": "o1", "kind": "primary", "text": "x"}))
	_rejects(t, "V-MIS-05", "hidden must start hidden", func(m: Dictionary) -> void: (m["objectives"] as Array)[1]["initial"] = "active")
	_rejects(t, "V-MIS-02", "objective kind", func(m: Dictionary) -> void: (m["objectives"] as Array)[0]["kind"] = "tertiary")
	_rejects(t, "V-MIS-02", "timer seconds", func(m: Dictionary) -> void: (m["timers"] as Array)[0]["seconds"] = 0)
	_rejects(t, "V-MIS-04", "duplicate trigger", func(m: Dictionary) -> void: (m["triggers"] as Array).append((m["triggers"] as Array)[0].duplicate(true)))
	_rejects(t, "V-MIS-03", "bad lore", func(m: Dictionary) -> void: m["briefing"] = [{"text": "x", "lore": "bogus.thing"}])


func test_condition_and_action_errors(t: TestCtx) -> void:
	var set_when: Callable = func(m: Dictionary, w: Dictionary) -> void: ((m["triggers"] as Array)[0] as Dictionary)["when"] = w
	var set_then: Callable = func(m: Dictionary, a: Dictionary) -> void: ((m["triggers"] as Array)[0] as Dictionary)["then"] = [a]
	_rejects(t, "V-MIS-05", "unknown cond kind", func(m: Dictionary) -> void: set_when.call(m, {"kind": "weather"}))
	_rejects(t, "V-MIS-02", "cond unknown key", func(m: Dictionary) -> void: set_when.call(m, {"kind": "time", "seconds": 1, "bogus": 1}))
	_rejects(t, "V-MIS-05", "time needs a value", func(m: Dictionary) -> void: set_when.call(m, {"kind": "time"}))
	_rejects(t, "V-MIS-05", "seconds xor ticks", func(m: Dictionary) -> void: set_when.call(m, {"kind": "time", "seconds": 1, "ticks": 20}))
	_rejects(t, "V-MIS-03", "unknown timer", func(m: Dictionary) -> void: set_when.call(m, {"kind": "timer", "timer": "nope"}))
	_rejects(t, "V-MIS-03", "unknown objective", func(m: Dictionary) -> void: set_when.call(m, {"kind": "objective", "objective": "nope", "state": "active"}))
	_rejects(t, "V-MIS-02", "bad cmp", func(m: Dictionary) -> void: set_when.call(m, {"kind": "credits", "owner": 0, "cmp": "=>", "value": 1}))
	_rejects(t, "V-MIS-03", "unknown owner slot", func(m: Dictionary) -> void: set_when.call(m, {"kind": "credits", "owner": 5, "value": 1}))
	_rejects(t, "V-MIS-02", "bad selector", func(m: Dictionary) -> void: set_when.call(m, {"kind": "credits", "owner": "everyone", "value": 1}))
	_rejects(t, "V-MIS-03", "unknown count def", func(m: Dictionary) -> void: set_when.call(m, {"kind": "count", "owner": 0, "def": "unit.nope", "value": 1}))
	_rejects(t, "V-MIS-03", "unknown tag", func(m: Dictionary) -> void: set_when.call(m, {"kind": "count", "owner": 0, "tag": "wizard", "value": 1}))
	_rejects(t, "V-MIS-03", "unknown area", func(m: Dictionary) -> void: set_when.call(m, {"kind": "count", "owner": 0, "area": "nope", "value": 1}))
	_rejects(t, "V-MIS-05", "of vs def", func(m: Dictionary) -> void: set_when.call(m, {"kind": "count", "owner": 0, "of": "structure", "def": "unit.napc.guardian_tank", "value": 1}))
	_rejects(t, "V-MIS-05", "destroyed needs placed", func(m: Dictionary) -> void: set_when.call(m, {"kind": "structure", "state": "destroyed", "owner": 0, "def": "structure.shared.generator"}))
	_rejects(t, "V-MIS-03", "unknown wave", func(m: Dictionary) -> void: set_when.call(m, {"kind": "wave", "wave": "nope", "state": "cleared"}))
	_rejects(t, "V-MIS-05", "empty all", func(m: Dictionary) -> void: set_when.call(m, {"all": []}))
	_rejects(t, "V-MIS-05", "combinator with siblings", func(m: Dictionary) -> void: set_when.call(m, {"all": [{"kind": "time", "seconds": 1}], "kind": "time"}))
	_rejects(t, "V-MIS-05", "unknown action", func(m: Dictionary) -> void: set_then.call(m, {"do": "explode"}))
	_rejects(t, "V-MIS-03", "unknown message", func(m: Dictionary) -> void: set_then.call(m, {"do": "show_message", "message": "nope"}))
	_rejects(t, "V-MIS-02", "action unknown key", func(m: Dictionary) -> void: set_then.call(m, {"do": "timer_stop", "timer": "tm1", "x": 1}))
	_rejects(t, "V-MIS-02", "spawn needs area", func(m: Dictionary) -> void: set_then.call(m, {"do": "spawn_units", "owner": 1, "def": "unit.nec.jager_squad"}))
	_rejects(t, "V-MIS-02", "attack_move needs an area", func(m: Dictionary) -> void: set_then.call(m, {"do": "spawn_units", "owner": 1, "def": "unit.nec.jager_squad", "area": "a_far", "order": {"kind": "attack_move"}}))
	_rejects(t, "V-MIS-05", "area xor cell", func(m: Dictionary) -> void: set_then.call(m, {"do": "spawn_structure", "owner": 1, "def": "structure.shared.generator"}))
	_rejects(t, "V-MIS-05", "neutral not allowed for win", func(m: Dictionary) -> void: set_then.call(m, {"do": "win", "owner": "neutral"}))
	_rejects(t, "V-MIS-05", "change_ai on a human", func(m: Dictionary) -> void: set_then.call(m, {"do": "change_ai", "owner": 0, "active": true}))
	_rejects(t, "V-MIS-05", "change_ai changes nothing", func(m: Dictionary) -> void: set_then.call(m, {"do": "change_ai", "owner": 1}))
	_rejects(t, "V-MIS-05", "transfer needs a target", func(m: Dictionary) -> void: set_then.call(m, {"do": "transfer", "to": 0}))
	_rejects(t, "V-MIS-02", "empty then", func(m: Dictionary) -> void: ((m["triggers"] as Array)[0] as Dictionary)["then"] = [])
	_rejects(t, "V-MIS-02", "unknown music state is rejected", func(m: Dictionary) -> void: set_then.call(m, {"do": "music_state", "state": "polka"}))


func test_placed_and_wave_ids(t: TestCtx) -> void:
	var two_spawns: Dictionary = MissionKit.base("t_good", {"triggers": [
		{"id": "t1", "when": {"kind": "time", "seconds": 1}, "then": [
			{"do": "spawn_structure", "owner": 1, "def": "structure.shared.generator", "area": "a_far", "id": "dup"},
			{"do": "spawn_structure", "owner": 1, "def": "structure.shared.generator", "area": "a_far", "id": "dup"}]}]})
	var e: String = MissionKit.load_error({"t_good": two_spawns})
	t.check(e.contains("V-MIS-04") and e.contains("dup"), "a placed id may be spawned once: %s" % e.substr(0, 200))
	var ok: Dictionary = MissionKit.base("t_good", {"triggers": [
		{"id": "t1", "when": {"kind": "time", "seconds": 1}, "then": [
			{"do": "spawn_structure", "owner": 1, "def": "structure.shared.generator", "area": "a_far", "id": "gen"},
			{"do": "spawn_units", "owner": 1, "def": "unit.nec.jager_squad", "area": "a_far", "wave": "w1"}]},
		{"id": "t2", "when": {"all": [{"kind": "structure", "state": "destroyed", "placed": "gen"}, {"kind": "wave", "wave": "w1", "state": "cleared"}]},
		 "then": [{"do": "win", "owner": 0}]}]})
	var d: GameData = MissionKit.data({"t_good": ok})
	if t.not_null(d, "placed + wave refs resolve: " + MissionKit.load_error({"t_good": ok}).substr(0, 200)):
		var m: DefMission = DefMissionTable.of(d).get_mission("t_good")
		t.eq(m.placed, PackedStringArray(["gen"]))
		t.eq(m.waves, PackedStringArray(["w1"]))


func test_manifest_rules(t: TestCtx) -> void:
	var src: DefSources = DefSources.from_disk(GameData.BIBLE_PATH, GameData.BALANCE_DIR)
	var m: Dictionary = _good()
	src.missions["t_b.json"] = m.duplicate(true)
	src.missions["t_a.json"] = m.duplicate(true)
	src.mission_files = PackedStringArray(["t_b.json", "t_a.json"])
	t.check(GameData.load_from_sources(src) == null and GameData.last_report.text().contains("sorted"), "unsorted missions list is rejected")
	var src2: DefSources = DefSources.from_disk(GameData.BIBLE_PATH, GameData.BALANCE_DIR)
	src2.mission_files = PackedStringArray(["gone.json"])
	t.check(GameData.load_from_sources(src2) == null, "a listed file that is not there is rejected")
	t.check(GameData.last_report.has_rule("V-SCH-01") or GameData.last_report.text().contains("gone"), "reported")


func test_copies_of_vocabulary_equal_the_sim_tables(t: TestCtx) -> void:
	for i: int in SimMatchRules.FIELDS.size():
		var n: String = SimMatchRules.FIELDS[i]
		if n == "start_mode":
			t.check(not DefMissionParser.RULE_RANGES.has(n), "start_mode cannot be overridden")
			continue
		var r: Array = DefMissionParser.RULE_RANGES.get(n, [])
		t.check(r.size() == 2 and int(r[0]) == SimMatchRules.MIN_VALUES[i] and int(r[1]) == SimMatchRules.MAX_VALUES[i], "rule range of " + n)
	for l: int in DefMissionParser.LAYOUTS:
		t.eq(int(DefMissionParser.MIN_SIZE[l]), MapGenParams.min_size(l), "min map size of layout %d" % l)
	t.eq(DefMissionParser.FAMILY_NAMES, FAM_NAMES)
	t.eq(DefMissionObjective.STATE_NAMES.size(), 4)
	t.eq(DefMissionScript.STRUCT_STATES[SimMissionConst.ST_CAPTURED], "captured")
	t.eq(DefMissionObjective.STATE_NAMES[SimMissionConst.OBJ_COMPLETED], "completed")


func test_lobby_style_tools(t: TestCtx) -> void:
	var d: GameData = MissionKit.data({"t_good": _good()})
	var cfg: Dictionary = SimMissionSetup.build_config(d, "t_good")
	t.eq(cfg["mission"], "t_good")
	t.eq((cfg["map"] as Dictionary)["layout_players"], 2)
	t.eq((cfg["players"] as Array).size(), 2)
	t.eq(((cfg["players"] as Array)[1] as Dictionary)["kind"], "ai")
	var ids: PackedStringArray = SimMissionSetup.ids_in_order(d)
	t.check(ids.has("demo_ambush") and ids.has("t_good"), "ids in menu order: %s" % str(ids))
	var seen: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(_lv: int, tag: String, msg: String) -> void: seen.append("%s: %s" % [tag, msg])
	t.eq(SimMissionSetup.build_config(d, "nope"), {}, "unknown mission -> {}")
	Log.sink = old_sink
	t.eq(seen.size(), 1, "one logged error: %s" % str(seen))
