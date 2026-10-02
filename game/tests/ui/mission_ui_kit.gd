extends RefCounted
## Fixtures of the MIS2 tests (not a test file): in-memory mission sets over the real data (never touches the shared data files).
##   var d: GameData = Kit.data(Kit.campaign_set())           # only these missions, no shipped ones
##   var d: GameData = Kit.data(Kit.hud_set(), true)          # the shipped missions plus these

const MK := preload("res://tests/support/mission_kit.gd")


## The real data with `extra` missions (id -> dict). `keep_shipped` false drops the shipped missions so the lists are exactly `extra`.
static func data(extra: Dictionary, keep_shipped: bool = false) -> GameData:
	if keep_shipped:
		return MK.data(extra)
	var src: DefSources = DefSources.from_disk(GameData.BIBLE_PATH, GameData.BALANCE_DIR)
	src.missions.clear()
	src.mission_files = PackedStringArray()
	var ids: Array = extra.keys()
	ids.sort()
	for id: Variant in ids:
		var f: String = "%s.json" % str(id)
		src.missions[f] = (extra[id] as Dictionary).duplicate(true)
		src.mission_files.append(f)
	return GameData.load_from_sources(src)


static func _human(roster: String, units: Array = []) -> Dictionary:
	return {"slot": 0, "kind": "human", "name": "Commander", "roster": roster, "team": 1, "start": {"mode": "hq", "units": units}}


static func _ai(level: int = 1, active: bool = false) -> Dictionary:
	return {"slot": 1, "kind": "ai", "name": "Hostiles", "roster": "roster.nec.vanilla", "team": 2, "ai": {"level": level, "active": active}, "start": {"mode": "none"}}


## A tutorial, two operations (NEC and OLM humans) and a demo: the menu order is ut_tut, ut_op_a, ut_op_b, ut_demo.
static func campaign_set() -> Dictionary:
	var briefing: Array = [{"heading": "Situation", "text": "Hostiles gather at the ridge. Hold the line, then strike back. More text follows here.", "lore": "faction.nec"},
		{"text": "Second block."}]
	var objectives: Array = [{"id": "o_main", "kind": "primary", "text": "Destroy the camp"}, {"id": "o_side", "kind": "secondary", "text": "Lose nobody"},
		{"id": "o_late", "kind": "primary", "text": "Revealed later", "initial": "hidden"}]
	return {
		"ut_tut": MK.base("ut_tut", {"title": "Training Day", "group": "tutorial", "order": 0, "briefing": briefing, "objectives": objectives}),
		"ut_op_a": MK.base("ut_op_a", {"title": "Operation Alpha", "group": "operation", "order": 1, "briefing": briefing, "objectives": objectives,
			"players": [_human("roster.nec.vanilla"), _ai(2)]}),
		"ut_op_b": MK.base("ut_op_b", {"title": "Operation Bravo", "group": "operation", "order": 2, "briefing": briefing, "objectives": objectives,
			"players": [_human("roster.olm.vanilla"), _ai(0)]}),
		"ut_demo": MK.base("ut_demo", {"title": "Demo Piece", "group": "demo", "order": 1}),
	}


## A mission that ends by itself: objective o1 completes at tick 60, o2 (hidden at first) turns active at 30 and fails at 80, the
## mission is won at 100 (`win`) or lost (`lose`).
static func scripted(id: String, outcome: String = "win") -> Dictionary:
	return MK.base(id, {
		"title": "Scripted " + id,
		"briefing": [{"heading": "Brief", "text": "Do the thing."}],
		"objectives": [{"id": "o1", "kind": "primary", "text": "First thing"}, {"id": "o2", "kind": "secondary", "text": "Optional thing", "initial": "hidden"},
			{"id": "o3", "kind": "primary", "text": "Keep the base"}],
		"messages": [{"id": "m_intro", "text": "Commander, the raid begins soon.", "speaker": "Command", "announcer": "base_under_attack"},
			{"id": "m_late", "text": "Second message.", "speaker": "Command"}],
		"timers": [{"id": "tm", "seconds": 20, "label": "Reinforcements", "autostart": true}, {"id": "tm_quiet", "seconds": 20, "autostart": true}],
		"triggers": [
			{"id": "t00", "when": {"kind": "time", "ticks": 0}, "then": [{"do": "show_message", "message": "m_intro"}, {"do": "camera_hint", "area": "a_far", "seconds": 4},
				{"do": "music_state", "state": "combat"}]},
			{"id": "t30", "when": {"kind": "time", "ticks": 30}, "then": [{"do": "set_objective", "objective": "o2", "state": "active"}, {"do": "show_message", "message": "m_late"}]},
			{"id": "t60", "when": {"kind": "time", "ticks": 60}, "then": [{"do": "set_objective", "objective": "o1", "state": "completed"}]},
			{"id": "t80", "when": {"kind": "time", "ticks": 80}, "then": [{"do": "set_objective", "objective": "o2", "state": "failed"}]},
			{"id": "t99", "when": {"kind": "time", "ticks": 100}, "then": [{"do": outcome, "owner": 0}]},
		]})
