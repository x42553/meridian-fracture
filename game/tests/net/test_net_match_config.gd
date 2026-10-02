extends RefCounted
## NET-5: NetMatchConfig (spec 7.1, 5.3.4-5.3.5), NetLobbyState / NetPlayerSlot (4.5), lobby_options.json (7.2).

const EXAMPLE: String = """{
  "created_unix": 1790677613,
  "format": 1,
  "map": {"family": 0, "layout_players": 4, "params": {}, "seed": 20240517, "size": 128},
  "match_id": "a3f19c0e5b7d2468",
  "net": {"allow_spectators": true, "auto_drop_ms": 60000, "checksum_period": 20, "input_delay": 2, "on_disconnect": 0, "pause_policy": 1, "speed_pct": 100, "turn_ticks": 2},
  "players": [
    {"color": 1, "handicap": 100, "kind": "human", "name": "Simon", "peer": 1, "pid": 0, "roster": "roster.napc.canada", "start": 0, "team": 1},
    {"color": 4, "handicap": 100, "kind": "human", "name": "Mia", "peer": 2, "pid": 1, "roster": "roster.nec.vanilla", "start": 1, "team": 1},
    {"ai": {"flags": 0, "level": 2, "style": 0}, "color": 0, "handicap": 100, "kind": "ai", "name": "AI 3", "peer": 0, "pid": 2, "roster": "roster.han.china", "start": 2, "team": 10}
  ],
  "rules": {"fog": true, "shared_vision": false, "start_credits": 7500, "superweapons": true, "unit_cap": 150, "veterancy": false, "vision_budget": 128, "vision_stride": 2},
  "seed": 3141592653,
  "versions": {"data_format": 1, "data_hash": 2882343476, "data_ids": 1360295431, "game": "0.1.0", "proto": 1, "sim": 1}
}"""

const FACTIONS: PackedStringArray = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]


class StubOpts extends RefCounted:
	var sim_version: int = 1
	var data_hash: int = 2882343476
	var roster_ids: PackedStringArray = PackedStringArray()
	var color_count: int = 12
	var ai_level_count: int = 4
	var ai_style_count: int = 4
	var data_handshake: Callable = Callable()
	var allow_spectators: bool = true
	var password: String = ""
	var dedicated: bool = false
	var ai_default_handicap: Callable = Callable()


static func _ids32() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f: String in FACTIONS:
		for sub: String in ["vanilla", "alpha", "beta", "gamma"]:
			out.append("roster.%s.%s" % [f, sub])
	return out


static func _example() -> Dictionary:
	return NetMatchConfig.normalize(JSON.parse_string(EXAMPLE))


func test_options_file(t: TestCtx) -> void:
	var o: Dictionary = NetMatchConfig.options()
	t.eq(o["format"], 1.0)
	t.eq((o["speeds"] as Array).size(), 6)
	t.eq(NetProtocol.SPEED_PCT.size(), 6)
	for sp: Variant in o["speeds"] as Array:
		t.eq(int((sp as Dictionary)["pct"]), NetProtocol.SPEED_PCT[int((sp as Dictionary)["code"])])
	t.eq((o["colors"] as Array).size(), 12)
	t.eq((o["map_sizes"] as Array).size(), 6)
	var keys: Array = []
	for e: Variant in NetMatchConfig.rules_schema():
		keys.append((e as Dictionary)["key"])
	t.eq(keys, ["start_credits", "unit_cap", "superweapons", "fog", "shared_vision", "veterancy", "vision_stride", "vision_budget"])
	t.eq(NetMatchConfig.default_rules(), {"start_credits": 7500, "unit_cap": 150, "superweapons": 1, "fog": 1, "shared_vision": 0,
		"veterancy": 0, "vision_stride": 2, "vision_budget": 128})


func test_example_round_trip(t: TestCtx) -> void:
	var cfg: Dictionary = _example()
	t.check(not cfg.is_empty(), "the spec example normalises")
	t.eq(cfg["seed"], 3141592653)
	t.eq(typeof(cfg["seed"]), TYPE_INT, "floats from JSON are folded to int")
	t.eq(cfg["rules"]["fog"], true)
	t.eq(cfg["players"].size(), 3)
	var j: String = NetMatchConfig.canonical_json(cfg)
	t.eq(NetMatchConfig.canonical_json(_example()), j, "canonical json is byte-stable")
	t.check(not j.contains("\n") and not j.contains("\": ") and not j.contains(", ") and not j.contains("00.0") and not j.contains("9.0,"), "no whitespace, no float syntax")
	var again: Dictionary = NetMatchConfig.parse(j)
	t.eq(again, cfg, "parse(canonical) == config")
	t.eq(NetMatchConfig.canonical_json(again), j)
	# keys are sorted: the first key is created_unix
	t.check(j.begins_with("{\"created_unix\":1790677613,\"format\":1,\"map\":{\"family\":0"))
	var h: int = NetMatchConfig.config_hash(j.to_utf8_buffer())
	t.eq(h, NetProtocol.fnv1a32(j.to_utf8_buffer()))
	t.eq(NetMatchConfig.pid_of_peer(cfg, 2), 1)
	t.eq(NetMatchConfig.pid_of_peer(cfg, 3), -1)
	t.eq(NetMatchConfig.pid_of_peer(cfg, 0), -1, "AI slots have no peer")
	t.eq(NetMatchConfig.team_of(cfg, 2), 10)
	t.eq(NetMatchConfig.team_of(cfg, 6), -1)
	# the sim reads exactly this dictionary
	var sc: SimMatchConfig = SimMatchConfig.from_dict(cfg)
	t.eq(sc.players.size(), 3)
	t.eq(sc.seed_value, 3141592653)
	t.eq(sc.rules.start_credits, 7500)


func _mutate(path: Array, value: Variant) -> Dictionary:
	var raw: Variant = JSON.parse_string(EXAMPLE)
	var cur: Variant = raw
	for i: int in path.size() - 1:
		cur = (cur as Array)[path[i]] if cur is Array else (cur as Dictionary)[path[i]]
	if value is StringName and str(value) == "__erase__":
		(cur as Dictionary).erase(path[-1])
	elif cur is Array:
		(cur as Array)[path[-1]] = value
	else:
		(cur as Dictionary)[path[-1]] = value
	return NetMatchConfig.normalize(raw)


func test_normalize_rejects(t: TestCtx) -> void:
	t.check(_mutate(["seed"], 5).size() > 0, "sanity: a valid mutation still passes")
	var erase: StringName = &"__erase__"
	var bad: Array = [
		[["extra"], 1], [["seed"], 1.5], [["seed"], "7"], [["seed"], -1], [["seed"], 4294967296], [["seed"], null],
		[["net", "input_delay"], 0], [["net", "input_delay"], 9], [["net", "speed_pct"], 60], [["net", "turn_ticks"], 3],
		[["net", "checksum_period"], 10], [["net", "allow_spectators"], 1], [["net", "pause_policy"], 3],
		[["net", "unknown"], 1], [["map", "size"], 100], [["map", "size"], 264], [["map", "size"], 88], [["map", "family"], 3],
		[["map", "layout_players"], 3], [["map", "params"], {"a": 1}], [["map", "seed"], -5],
		[["rules", "unit_cap"], 10], [["rules", "unit_cap"], 501], [["rules", "fog"], 1], [["rules", "start_credits"], true],
		[["rules", "mystery"], 1], [["rules", "vision_stride"], 5],
		[["versions", "game"], "x".repeat(25)], [["versions", "data_hash"], -1], [["format"], 2], [["format"], 1.5],
		[["match_id"], "zzzzzzzzzzzzzzzz"], [["match_id"], "abc"], [["created_unix"], -1],
		[["players", 0, "pid"], -1], [["players", 0, "pid"], 8], [["players", 1, "pid"], 0], [["players", 0, "color"], 4],
		[["players", 0, "color"], 12], [["players", 0, "start"], 1], [["players", 0, "start"], 4], [["players", 0, "handicap"], 45],
		[["players", 0, "handicap"], 103], [["players", 0, "handicap"], 205], [["players", 0, "team"], 5], [["players", 0, "team"], 0],
		[["players", 0, "team"], 9], [["players", 0, "name"], ""], [["players", 0, "name"], "n".repeat(25)], [["players", 0, "name"], "[b]X"],
		[["players", 0, "kind"], "bot"], [["players", 0, "peer"], 0], [["players", 1, "peer"], 1],
		[["players", 0, "roster"], ""], [["players", 0, "roster"], "r".repeat(41)], [["players", 2, "peer"], 3],
		[["players", 2, "ai", "level"], 16], [["players", 2, "ai", "flags"], 256], [["players", 2, "ai"], 5],
		[["players", 0, "ai"], {"level": 1, "style": 0, "flags": 0}],
		[["players", 0, "unknown"], 1], [["players", 2, "team"], 11],
	]
	for row: Variant in bad:
		var r: Array = row as Array
		t.eq(_mutate(r[0] as Array, r[1]), {}, "rejects %s = %s" % [str(r[0]), str(r[1])])
	for key: String in ["seed", "map", "rules", "net", "players", "versions", "format", "match_id", "created_unix"]:
		t.eq(_mutate([key], erase), {}, "missing %s" % key)
	t.eq(_mutate(["players", 0, "pid"], erase), {})
	t.eq(_mutate(["net", "speed_pct"], erase), {})
	t.eq(_mutate(["rules", "fog"], erase), {})
	# non-finite numbers ("1e400" parses to inf) and NaN
	var inf_text: String = EXAMPLE.replace("\"seed\": 3141592653", "\"seed\": 1e400")
	t.eq(NetMatchConfig.normalize(JSON.parse_string(inf_text)), {})
	var raw: Variant = JSON.parse_string(EXAMPLE)
	(raw as Dictionary)["seed"] = NAN
	t.eq(NetMatchConfig.normalize(raw), {})
	(raw as Dictionary)["seed"] = INF
	t.eq(NetMatchConfig.normalize(raw), {})
	# structure: wrong container types, 9 players, unsorted, nesting
	t.eq(NetMatchConfig.normalize(null), {})
	t.eq(NetMatchConfig.normalize([]), {})
	t.eq(NetMatchConfig.normalize("x"), {})
	t.eq(_mutate(["players"], {}), {})
	t.eq(_mutate(["players"], []), {})
	t.eq(_mutate(["rules"], []), {})
	t.eq(_mutate(["map"], 5), {})
	var nine: Array = []
	for i: int in 9:
		nine.append({"color": i, "handicap": 100, "kind": "human", "name": "P%d" % i, "peer": i + 1, "pid": i, "roster": "r", "start": i % 8, "team": 8 + i})
	t.eq(_mutate(["players"], nine), {})
	var unsorted: Variant = JSON.parse_string(EXAMPLE)
	var pl: Array = (unsorted as Dictionary)["players"] as Array
	var tmp: Variant = pl[0]
	pl[0] = pl[1]
	pl[1] = tmp
	t.eq(NetMatchConfig.normalize(unsorted), {}, "players must be sorted by pid")
	# more players than layout slots
	var too_many: Variant = JSON.parse_string(EXAMPLE)
	(too_many as Dictionary)["map"]["layout_players"] = 2
	t.eq(NetMatchConfig.normalize(too_many), {})
	# integral floats are accepted and coerced
	var floats: String = EXAMPLE.replace("\"seed\": 3141592653", "\"seed\": 3141592653.0").replace("\"size\": 128", "\"size\": 128.0")
	var f: Dictionary = NetMatchConfig.normalize(JSON.parse_string(floats))
	t.check(not f.is_empty())
	t.eq(typeof(f["map"]["size"]), TYPE_INT)
	t.eq(NetMatchConfig.canonical_json(f), NetMatchConfig.canonical_json(_example()))
	# oversize JSON text is refused by parse()
	t.eq(NetMatchConfig.parse(" ".repeat(NetProtocol.MAX_CONFIG_JSON + 1)), {})
	t.eq(NetMatchConfig.parse("{not json"), {})


func test_validate(t: TestCtx) -> void:
	var cfg: Dictionary = _example()
	var o: StubOpts = StubOpts.new()
	o.roster_ids = PackedStringArray(["roster.napc.canada", "roster.nec.vanilla", "roster.han.china"])
	t.eq(NetMatchConfig.validate(cfg, o), "")
	t.eq(NetMatchConfig.validate(cfg, null), "", "no options: structural only")
	t.eq(NetMatchConfig.validate({}, o) != "", true)
	o.sim_version = 2
	t.check(NetMatchConfig.validate(cfg, o).contains("simulation"))
	o.sim_version = 1
	o.data_hash = 5
	t.check(NetMatchConfig.validate(cfg, o).contains("game data"))
	o.data_hash = 2882343476
	o.roster_ids = PackedStringArray(["roster.napc.canada"])
	t.check(NetMatchConfig.validate(cfg, o).contains("roster"))
	o.roster_ids = PackedStringArray()
	o.ai_level_count = 2
	t.check(NetMatchConfig.validate(cfg, o).contains("AI level"))
	o.ai_level_count = 4
	o.color_count = 4
	t.check(NetMatchConfig.validate(cfg, o).contains("colour"), "colour 4 with 4 colours")
	o.color_count = 12
	o.data_handshake = func(_files: bool) -> Dictionary: return {"format": 1, "hash": 2882343476, "tables": {"ids": 1360295431}}
	t.eq(NetMatchConfig.validate(cfg, o), "")
	o.data_handshake = func(_files: bool) -> Dictionary: return {"format": 1, "hash": 2882343476, "tables": {"ids": 7}}
	t.check(NetMatchConfig.validate(cfg, o).contains("ids"))
	var proto: Dictionary = _mutate(["versions", "proto"], 2)
	t.check(NetMatchConfig.validate(proto, null).contains("protocol"))
	# random tokens must have been resolved
	var tok: Dictionary = _mutate(["players", 0, "roster"], "random")
	t.check(NetMatchConfig.validate(tok, null).contains("roster"))


func test_roster_tokens(t: TestCtx) -> void:
	var ids: PackedStringArray = _ids32()
	t.eq(NetMatchConfig.token_candidates("random", ids).size(), 32)
	t.eq(NetMatchConfig.token_candidates("random.vanilla", ids).size(), 8)
	t.eq(NetMatchConfig.token_candidates("random.subfaction", ids).size(), 24)
	for f: String in FACTIONS:
		var c: PackedStringArray = NetMatchConfig.token_candidates("random." + f, ids)
		t.eq(c.size(), 4, f)
		for id: String in c:
			t.check(id.begins_with("roster.%s." % f))
	t.eq(NetMatchConfig.token_candidates("random.xyz", ids).size(), 0)
	t.eq(NetMatchConfig.token_candidates("roster.napc.alpha", ids).size(), 0, "a concrete id is not a token")
	var c0: PackedStringArray = NetMatchConfig.token_candidates("random", ids)
	var sorted: PackedStringArray = c0.duplicate()
	sorted.sort()
	t.eq(c0, sorted, "ascending string order")
	t.check(NetMatchConfig.is_roster_ok("roster.ae.beta", ids))
	t.check(NetMatchConfig.is_roster_ok("random.sap", ids))
	t.check(not NetMatchConfig.is_roster_ok("roster.zz.beta", ids))
	t.check(not NetMatchConfig.is_roster_ok("random.zz", ids))
	t.check(not NetMatchConfig.is_roster_ok("", ids))


func test_shuffle_vector(t: TestCtx) -> void:
	var groups: Array = [0, 1, 2, 3, 4, 5, 6, 7]
	var c: int = NetMatchConfig.shuffle_groups(groups, 12345, 0)
	t.eq(groups, [7, 3, 2, 0, 1, 6, 5, 4], "spec 5.3.5 vector")
	t.eq(c, 7)
	t.eq(NetMatchConfig.shuffle_groups([1], 5, 3), 3, "a single group consumes nothing")


func _lobby(order: Array) -> NetLobbyState:
	var st: NetLobbyState = NetLobbyState.create_default("Host", 0x1234, 777)
	st.layout_players = 8
	for s: NetPlayerSlot in st.slots:
		s.kind = NetProtocol.SlotKind.CLOSED
	# the same final content, applied in the given slot order
	var spec: Dictionary = {
		0: {"k": NetProtocol.SlotKind.HUMAN, "team": 1, "roster": "random.vanilla", "start": -1, "peer": 1, "name": "Host"},
		1: {"k": NetProtocol.SlotKind.HUMAN, "team": 1, "roster": "random", "start": 3, "peer": 2, "name": "Mia"},
		2: {"k": NetProtocol.SlotKind.AI, "team": 0, "roster": "random.napc", "start": -1, "peer": 0, "name": ""},
		3: {"k": NetProtocol.SlotKind.AI, "team": 2, "roster": "roster.han.alpha", "start": -1, "peer": 0, "name": ""},
		5: {"k": NetProtocol.SlotKind.AI, "team": 2, "roster": "random.subfaction", "start": -1, "peer": 0, "name": ""},
	}
	for i: Variant in order:
		var d: Dictionary = spec[i] as Dictionary
		var s: NetPlayerSlot = st.slots[int(i)]
		s.kind = int(d["k"])
		s.team = int(d["team"])
		s.roster_id = str(d["roster"])
		s.start = int(d["start"])
		s.peer_id = int(d["peer"])
		s.name = str(d["name"])
		s.color = int(i)
	return st


func test_from_lobby_resolution_is_reproducible(t: TestCtx) -> void:
	var ids: PackedStringArray = _ids32()
	var versions: Dictionary = {"game": "0.1.0", "proto": 1, "sim": 1, "data_hash": 9, "data_format": 1, "data_ids": 5}
	var a: Dictionary = NetMatchConfig.from_lobby(_lobby([0, 1, 2, 3, 5]), 424242, versions, 1790000000, ids)
	var b: Dictionary = NetMatchConfig.from_lobby(_lobby([5, 3, 2, 1, 0]), 424242, versions, 1790000000, ids)
	t.eq(NetMatchConfig.canonical_json(a), NetMatchConfig.canonical_json(b), "independent of slot edit order")
	t.eq(NetMatchConfig.normalize(JSON.parse_string(NetMatchConfig.canonical_json(a))), a, "what the host builds survives the wire")
	t.eq(NetMatchConfig.validate(a, null), "")
	var players: Array = a["players"] as Array
	t.eq(players.size(), 5)
	var starts: Dictionary = {}
	for pv: Variant in players:
		var p: Dictionary = pv as Dictionary
		t.check(ids.has(str(p["roster"])), "concrete roster: %s" % p["roster"])
		t.check(not starts.has(p["start"]), "unique start")
		starts[p["start"]] = true
		t.check(int(p["start"]) >= 0 and int(p["start"]) < 8)
	t.check(str((players[0] as Dictionary)["roster"]).ends_with(".vanilla"), "random.vanilla")
	t.check(str((players[2] as Dictionary)["roster"]).begins_with("roster.napc."), "random.napc")
	t.check(not str((players[4] as Dictionary)["roster"]).ends_with(".vanilla"), "random.subfaction")
	t.eq((players[3] as Dictionary)["roster"], "roster.han.alpha")
	t.eq((players[1] as Dictionary)["start"], 3, "fixed starts are reserved")
	t.eq((players[2] as Dictionary)["team"], 10, "no team -> 8 + pid")
	t.eq((players[2] as Dictionary)["name"], "AI 3")
	t.eq((players[2] as Dictionary)["kind"], "ai")
	t.eq((players[0] as Dictionary)["peer"], 1)
	t.check(not (players[0] as Dictionary).has("ai"))
	t.eq((players[3] as Dictionary)["ai"], {"level": 1, "style": 0, "flags": 0})
	# team members occupy consecutive free starts: team 2 (slots 3, 5) and team 1 (slot 0; slot 1 fixed at 3)
	var s3: int = (players[3] as Dictionary)["start"]
	var s5: int = (players[4] as Dictionary)["start"]
	var free: Array = [0, 1, 2, 4, 5, 6, 7]
	t.eq(free.find(s5) - free.find(s3), 1, "teammates are adjacent among the free starts")
	# a different seed changes the resolution (over several seeds at least one differs)
	var differs: bool = false
	for s: int in range(1, 12):
		var o: Dictionary = NetMatchConfig.from_lobby(_lobby([0, 1, 2, 3, 5]), 424242 + s, versions, 1790000000, ids)
		if NetMatchConfig.canonical_json({"p": o["players"]}) != NetMatchConfig.canonical_json({"p": a["players"]}):
			differs = true
	t.check(differs)
	# the same call twice is byte-identical, including the derived match id
	var again: Dictionary = NetMatchConfig.from_lobby(_lobby([0, 1, 2, 3, 5]), 424242, versions, 1790000000, ids)
	t.eq(NetMatchConfig.canonical_json(again), NetMatchConfig.canonical_json(a))
	t.eq(String(a["match_id"]).length(), 16)
	var given: Dictionary = NetMatchConfig.from_lobby(_lobby([0, 1]), 1, {"match_id": "0123456789abcdef"}, 5, ids)
	t.eq(given["match_id"], "0123456789abcdef")
	# default_roster_ids is used when no list is passed
	NetMatchConfig.default_roster_ids = ids
	var d: Dictionary = NetMatchConfig.from_lobby(_lobby([0, 1, 2, 3, 5]), 424242, versions, 1790000000)
	NetMatchConfig.default_roster_ids = PackedStringArray()
	t.eq(NetMatchConfig.canonical_json(d), NetMatchConfig.canonical_json(a))


func test_from_lobby_copies_options_and_rules(t: TestCtx) -> void:
	var st: NetLobbyState = _lobby([0, 1])
	st.rules["start_credits"] = 20000
	st.rules["fog"] = 0
	st.speed_code = 4
	st.pause_policy = 0
	st.on_disconnect = 1
	st.auto_drop_ms = 30000
	st.allow_spectators = false
	st.map_family = 2
	st.map_size = 160
	st.map_seed = 99
	st.layout_players = 6
	st.slots[1].handicap_pct = 120
	var cfg: Dictionary = NetMatchConfig.from_lobby(st, 5, {}, 0, _ids32())
	t.eq(cfg["rules"]["start_credits"], 20000)
	t.eq(cfg["rules"]["fog"], false)
	t.eq(cfg["net"]["speed_pct"], 150)
	t.eq(cfg["net"]["pause_policy"], 0)
	t.eq(cfg["net"]["on_disconnect"], 1)
	t.eq(cfg["net"]["auto_drop_ms"], 30000)
	t.eq(cfg["net"]["allow_spectators"], false)
	t.eq(cfg["net"]["input_delay"], NetProtocol.D_MIN_LAN)
	t.eq(cfg["map"], {"family": 2, "size": 160, "seed": 99, "layout_players": 6, "params": {}})
	t.eq(cfg["players"][1]["handicap"], 120)
	t.eq(cfg["seed"], 5)
	t.check(not NetMatchConfig.normalize(cfg).is_empty())


func test_lobby_state_defaults_and_queries(t: TestCtx) -> void:
	var o: StubOpts = StubOpts.new()
	var st: NetLobbyState = NetLobbyState.create_default("  Simon  ", 0xFFFFFFFFF, 0x1FFFFFFFF, o)
	t.eq(st.host_name, "Simon")
	t.eq(st.session_id, 0xFFFFFFFF)
	t.eq(st.map_seed, 0xFFFFFFFF)
	t.eq(st.slots.size(), 8)
	t.eq(st.slots[0].kind, NetProtocol.SlotKind.HUMAN)
	t.eq(st.slots[0].peer_id, 1)
	t.check(st.slots[0].ready and st.slots[0].connected)
	t.eq(st.slots[0].name, "Simon")
	t.eq(st.first_open_slot(), 1)
	t.eq(st.slots[3].kind, NetProtocol.SlotKind.OPEN)
	t.eq(st.slots[4].kind, NetProtocol.SlotKind.CLOSED, "slots >= layout_players")
	t.eq([st.map_family, st.map_size, st.layout_players], [0, 128, 4])
	t.eq([st.speed_code, st.pause_policy, st.on_disconnect, st.auto_drop_ms, st.allow_spectators], [2, 1, 0, 60000, true])
	t.eq(st.rules, NetMatchConfig.default_rules())
	t.eq(st.human_count(), 1)
	t.eq(st.ai_count(), 0)
	t.eq(st.active_slot_indices(), PackedInt32Array([0]))
	t.eq(st.slot_of_peer(1), 0)
	t.eq(st.slot_of_peer(2), -1)
	t.eq(st.slot_of_peer(0), -1)
	var colors: Dictionary = {}
	for s: NetPlayerSlot in st.slots:
		colors[s.color] = true
	t.eq(colors.size(), 8, "colours unique")
	# options flow through
	o.allow_spectators = false
	o.password = "pw"
	o.dedicated = true
	var d: NetLobbyState = NetLobbyState.create_default("Srv", 1, 2, o)
	t.eq(d.allow_spectators, false)
	t.eq(d.password_set, true)
	t.eq(d.slots[0].kind, NetProtocol.SlotKind.OPEN, "dedicated host has no seat")
	# duplicate is deep
	var c: NetLobbyState = st.duplicate_state()
	c.slots[0].name = "X"
	c.rules["fog"] = 0
	c.spectators.append({"peer_id": 9, "name": "S"})
	t.eq(st.slots[0].name, "Simon")
	t.eq(st.rules["fog"], 1)
	t.eq(st.spectators.size(), 0)
	t.eq(c.slots[1].index, 1)
	c.slots[0].duplicate_slot().name = "y"


func test_skirmish_lobby(t: TestCtx) -> void:
	var o: StubOpts = StubOpts.new()
	o.ai_default_handicap = func(level: int) -> int: return 120 if level == 3 else 100
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.nec.vanilla", o)
	t.eq(st.slots[0].kind, NetProtocol.SlotKind.HUMAN)
	t.eq(st.slots[0].roster_id, "roster.nec.vanilla")
	t.eq(st.slots[1].kind, NetProtocol.SlotKind.AI)
	t.check(st.slots[1].ready and st.slots[1].connected)
	t.eq(st.slots[1].ai_level, 1)
	t.eq(st.slots[1].handicap_pct, 100)
	for i: int in range(2, 8):
		t.eq(st.slots[i].kind, NetProtocol.SlotKind.CLOSED)
	t.eq(st.active_slot_indices(), PackedInt32Array([0, 1]))
	t.eq(st.human_count(), 1)
	t.eq(st.ai_count(), 1)
	t.eq(st.first_open_slot(), -1)
	t.eq(st.allow_spectators, false)
	var cfg: Dictionary = NetMatchConfig.from_lobby(st, 7, {}, 0, _ids32())
	t.eq(cfg["players"].size(), 2)
	t.eq(cfg["players"][0]["roster"], "roster.nec.vanilla")
	t.check(not NetMatchConfig.normalize(cfg).is_empty())


func test_snapshot_codec_round_trip_with_the_real_model(t: TestCtx) -> void:
	var st: NetLobbyState = _lobby([0, 1, 2, 3, 5])
	st.revision = 12
	st.phase = NetProtocol.LobbyPhase.OPEN
	st.spectators.append({"peer_id": 7, "name": "Spec"})
	st.slots[2].handicap_pct = 120
	st.slots[2].ai_level = 3
	st.slots[2].ai_flags = 1
	st.slots[2].connected = true
	var bytes: PackedByteArray = NetLobbyCodec.encode_snapshot(st)
	t.check(not bytes.is_empty())
	var back: NetLobbyState = NetLobbyCodec.decode_snapshot(bytes) as NetLobbyState
	if not t.not_null(back, "decodes to a NetLobbyState"):
		return
	t.eq(back.revision, 12)
	t.eq(back.rules, st.rules)
	t.eq(back.slots.size(), 8)
	t.eq(back.slots[2].handicap_pct, 120)
	t.eq(back.slots[2].ai_level, 3)
	t.eq(back.slots[1].name, "Mia")
	t.eq(back.slots[3].roster_id, "roster.han.alpha")
	t.eq(back.spectators.size(), 1)
	t.eq(NetLobbyCodec.encode_snapshot(back), bytes, "canonical")
