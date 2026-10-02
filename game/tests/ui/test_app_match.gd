extends RefCounted
## UI-05 match glue: the lobby setup model and its config (ui.md 5.14), `AppMatchJob` phases (S3 / D4 without a renderer),
## (the LOCAL `NetSession`, the AI hook, the config completion and the end model are in `test_app_net.gd`).

const ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla"]

var _data: GameData = null


func _gd() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


func _config(seed_value: int = 5) -> Dictionary:
	return AppMatch.simple_config(ROSTERS, seed_value, 96)


# ---------------------------------------------------------------- lobby state

func test_lobby_defaults_are_a_valid_duel(t: TestCtx) -> void:
	var s: UiLobbyState = UiLobbyState.create(_gd())
	t.eq(s.slots[0].kind, UiLobbyState.Kind.HUMAN, "slot 0 is the human")
	t.eq(s.active_count(), 2)
	t.eq(s.layout_players(), 2)
	t.eq(int(s.validate()["err"]), UiLobbyState.Err.OK, "the default setup starts")
	t.eq(_gd().factions[s.slots[0].faction].code, "NAPC", "default human faction")


func test_lobby_start_errors(t: TestCtx) -> void:
	var s: UiLobbyState = UiLobbyState.create(_gd())
	s.slots[1].kind = UiLobbyState.Kind.OPEN
	t.eq(int(s.validate()["err"]), UiLobbyState.Err.NOT_ENOUGH_PLAYERS)
	t.eq(int(s.validate()["slot"]), 1, "the first open slot is highlighted")
	s.slots[1].kind = UiLobbyState.Kind.AI
	s.slots[0].team = 1
	s.slots[1].team = 1
	t.eq(int(s.validate()["err"]), UiLobbyState.Err.SINGLE_TEAM)
	s.slots[1].team = 2
	t.eq(int(s.validate()["err"]), UiLobbyState.Err.OK)
	s.slots[1].start = 0
	s.slots[0].start = 0
	t.eq(int(s.validate()["err"]), UiLobbyState.Err.START_CONFLICT)
	s.slots[0].start = -1
	s.slots[1].start = -1
	# a 6-player layout on a 96 map is a map error until the size is fixed
	s.set_kind(2, UiLobbyState.Kind.AI)
	s.set_kind(3, UiLobbyState.Kind.AI)
	s.set_kind(4, UiLobbyState.Kind.AI)
	t.eq(s.layout_players(), 6)
	t.ge(s.size, 160, "adding players raises the size to the layout minimum")
	t.eq(int(s.validate()["err"]), UiLobbyState.Err.OK)
	s.size = 96
	t.eq(int(s.validate()["err"]), UiLobbyState.Err.MAP_INVALID)


func test_lobby_colour_swap_and_starts(t: TestCtx) -> void:
	var s: UiLobbyState = UiLobbyState.create(_gd())
	s.slots[1].color = 1
	s.set_color(0, 1)
	t.eq(s.slots[0].color, 1, "slot 0 takes colour 1")
	t.eq(s.slots[1].color, 0, "the previous owner receives the colour slot 0 had (swap)")
	s.slots[0].start = 1
	var st: PackedInt32Array = s.resolved_starts()
	t.eq(st[0], 1)
	t.eq(st[1], 0, "the automatic start takes the lowest free position")


func test_lobby_roster_picking(t: TestCtx) -> void:
	var d: GameData = _gd()
	var s: UiLobbyState = UiLobbyState.create(d)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9
	var napc: int = s.slots[0].faction
	s.slots[0].sub = 0
	t.eq(s.roster_id(0, rng), "roster.napc.vanilla")
	s.slots[0].sub = 2
	t.eq(s.roster_id(0, rng), d.rosters[d.factions[napc].sub_rosters[1]].id, "subfaction 2 of the faction")
	s.slots[0].faction = -1
	s.slots[0].sub = 0
	for _i: int in 6:
		var id: String = s.roster_id(0, rng)
		t.check(d.roster_idx(id) >= 0 and d.rosters[d.roster_idx(id)].is_vanilla, "random + vanilla gives a vanilla roster: " + id)
	s.slots[0].sub = 1
	for _i: int in 6:
		var id2: String = s.roster_id(0, rng)
		t.check(d.roster_idx(id2) >= 0 and not d.rosters[d.roster_idx(id2)].is_vanilla, "random + subfaction gives a subfaction: " + id2)
	t.eq(s.sub_options(-1).size(), 3, "random faction has three variants")
	t.eq(s.sub_options(napc).size(), 5, "vanilla, three subfactions, any")


func test_lobby_config_is_accepted_by_the_sim(t: TestCtx) -> void:
	var d: GameData = _gd()
	var s: UiLobbyState = UiLobbyState.create(d)
	s.set_kind(2, UiLobbyState.Kind.AI)
	s.slots[3].kind = UiLobbyState.Kind.AI
	s.slots[3].ai_level = 3
	s.slots[0].team = 1
	s.slots[1].team = 2
	s.slots[2].team = 2
	s.fix_size()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var cfg: Dictionary = s.to_config(rng)
	t.eq((cfg["players"] as Array).size(), 4)
	t.eq(int((cfg["map"] as Dictionary)["layout_players"]), 4)
	var p3: Dictionary = (cfg["players"] as Array)[3] as Dictionary
	t.eq(int(p3["handicap"]), 120, "a Brutal AI defaults to 120 % handicap")
	var sc: SimMatchConfig = SimMatchConfig.from_dict(cfg)
	var problems: PackedStringArray = sc.validate(d, 4)
	t.eq(problems.size(), 0, "SimMatchConfig.validate: " + ", ".join(problems))
	t.eq(sc.rules.start_credits, 7500)
	t.eq(int((cfg["net"] as Dictionary)["speed_pct"]), 100)


func test_lobby_persistence_roundtrip(t: TestCtx) -> void:
	var d: GameData = _gd()
	var s: UiLobbyState = UiLobbyState.create(d)
	s.apply_preset(UiLobbyState.presets()[1] as Dictionary)
	s.seed_value = 0xABCDEF01
	s.start_credits = 20000
	s.fog = false
	var copy: UiLobbyState = UiLobbyState.create(d)
	copy.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())) as Dictionary)
	t.eq(copy.seed_value, 0xABCDEF01)
	t.eq(copy.start_credits, 20000)
	t.eq(copy.fog, false)
	t.eq(copy.active_count(), 4, "the 2v2 preset has four players")
	t.eq(copy.slots[0].team, 1)
	# unknown faction ids fall back to Random
	var bad: Dictionary = s.to_dict()
	(bad["slots"] as Array)[1]["faction"] = 99
	copy.from_dict(bad)
	t.eq(copy.slots[1].faction, -1, "an unknown faction becomes Random")
	t.eq(UiLobbyState.presets().size(), 4, "four skirmish presets")


# ---------------------------------------------------------------- job and session

func test_match_job_phases_and_progress(t: TestCtx) -> void:
	var job: AppMatchJob = AppMatchJob.new(_config(), false, _gd())
	var last: int = -1
	var seen: Dictionary = {}
	var guard: int = 0
	while not job.step(4000) and guard < 4000:
		t.check(job.progress_pct() >= last, "progress is monotonic")
		last = job.progress_pct()
		seen[job.phase_name()] = true
		OS.delay_msec(2)
		guard += 1
	t.eq(job.error(), "", "no error")
	t.eq(job.progress_pct(), 100)
	t.not_null(job.take_world(), "a world came out")
	t.check(seen.has("Generating terrain"), "the MAP phase was visible")
	t.eq(job.local_pid(), 0)


func test_match_job_failure_paths(t: TestCtx) -> void:
	t.expect_errors(2)
	var bad: Dictionary = _config()
	((bad["map"] as Dictionary))["size"] = 100  # not a multiple of 8
	var job: AppMatchJob = AppMatchJob.new(bad, false, _gd())
	job.step(1000)
	t.check(job.error() != "", "an invalid map is reported")
	var no_map: AppMatchJob = AppMatchJob.new({"players": []}, false, _gd())
	no_map.step(1000)
	t.check(no_map.error() != "", "a config without a map is reported")
