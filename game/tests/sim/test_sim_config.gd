extends RefCounted
## SimMatchRules / SimPlayerSlot / SimMatchConfig: validation messages, net.md 7.1 example, config_hash (sim_core 5.10).

const NET_EXAMPLE: String = """{"map":{"family":0,"layout_players":4,"params":{},"seed":20240517,"size":128},
 "players":[{"color":1,"handicap":100,"kind":"human","name":"Simon","peer":1,"pid":0,"roster":"roster.fx.a","start":0,"team":1},
            {"color":4,"handicap":100,"kind":"human","name":"Mia","peer":2,"pid":1,"roster":"roster.fx.b","start":1,"team":1},
            {"ai":{"flags":0,"level":2,"style":0},"color":0,"handicap":120,"kind":"ai","name":"AI 3","peer":0,"pid":5,"roster":"roster.fx.c","start":2,"team":10}],
 "rules":{"fog":true,"shared_vision":false,"start_credits":7500,"superweapons":true,"unit_cap":150,"veterancy":false,"vision_budget":128,"vision_stride":2},
 "seed":3141592653}"""


## Private double of GameData (a subclass): only roster_idx(id) is read by validate().
class StubData:
	extends GameData
	var fx_names: PackedStringArray = ["roster.fx.a", "roster.fx.b", "roster.fx.c", "roster.fx.d", "roster.fx.e", "roster.fx.f", "roster.fx.g", "roster.fx.h"]

	func roster_idx(id: String) -> int:
		return fx_names.find(id)


## Test stand-in for net's NetMatchConfig.normalize: JSON floats -> ints.
func _fold_ints(v: Variant) -> Variant:
	if v is float:
		return int(v)
	if v is Array:
		var out: Array = []
		for e: Variant in v as Array:
			out.append(_fold_ints(e))
		return out
	if v is Dictionary:
		var d: Dictionary = {}
		var src: Dictionary = v
		for k: Variant in src:
			d[k] = _fold_ints(src[k])
		return d
	return v


func _slot(pid: int, roster: String, team: int, color: int, start: int, handicap: int = 100) -> SimPlayerSlot:
	var s: SimPlayerSlot = SimPlayerSlot.new()
	s.pid = pid
	s.roster = roster
	s.team = team
	s.color = color
	s.start = start
	s.handicap = handicap
	s.name = "P%d" % pid
	return s


func _two_player() -> SimMatchConfig:
	var c: SimMatchConfig = SimMatchConfig.new()
	c.seed_value = 424242
	c.map = {"family": 0, "size": 96}
	c.players.append(_slot(0, "roster.fx.a", 1, 0, 0))
	c.players.append(_slot(1, "roster.fx.b", 2, 1, 1))
	return c


func _net_example() -> SimMatchConfig:
	var parsed: Variant = JSON.parse_string(NET_EXAMPLE)
	return SimMatchConfig.from_dict(_fold_ints(parsed) as Dictionary)


func test_valid_config(t: TestCtx) -> void:
	t.eq(_two_player().validate(StubData.new(), 8), PackedStringArray(), "valid config has no messages")


func test_bad_config_messages(t: TestCtx) -> void:
	var c: SimMatchConfig = _two_player()
	c.seed_value = 4294967296
	c.players[0].handicap = 500
	c.players[1].roster = "roster.nope"
	c.players[1].team = 16
	c.players[1].color = 0  # duplicates pid 0
	c.rules.unit_cap = 5
	var want: PackedStringArray = [
		"seed must be a u32", "pid 0: handicap out of range", "pid 1: unknown roster 'roster.nope'",
		"pid 1: team out of range", "pid 1: colour invalid or duplicated", "rules.unit_cap out of range",
	]
	t.eq(c.validate(StubData.new(), 8), want, "the six exact messages of sim_core 5.10")


func test_more_validation(t: TestCtx) -> void:
	var c: SimMatchConfig = _two_player()
	c.players[1].start = 0
	var msgs: PackedStringArray = c.validate(StubData.new(), 8)
	t.eq(msgs, PackedStringArray(["pid 1: start invalid or duplicated"]), "duplicate start")
	c = _two_player()
	c.players[1].start = 8
	t.eq(c.validate(StubData.new(), 8), PackedStringArray(["pid 1: start invalid or duplicated"]), "start beyond the map's slots")
	c = _two_player()
	c.players.clear()
	t.check(c.validate(StubData.new(), 8).size() == 1, "no players")
	c = _two_player()
	c.players[1].pid = 0
	t.check("pid 0: duplicate pid" in c.validate(StubData.new(), 8), "duplicate pid")
	c = _two_player()
	c.players[1].pid = 9
	t.check("pid 9: pid out of range" in c.validate(StubData.new(), 8), "pid out of range")


func test_float_in_map_is_reported(t: TestCtx) -> void:
	var c: SimMatchConfig = _two_player()
	c.map = {"family": 0, "params": {"density": 0.5}}
	t.check(c.validate(StubData.new(), 8).size() == 1, "float in map reported")
	t.check(SimMatchConfig.is_int_only({"a": [1, "x", {"b": true}]}), "ints / strings / bools / nesting are fine")
	t.check_false(SimMatchConfig.is_int_only([1, [2, 3.5]]), "nested float found")
	t.check_false(SimMatchConfig.is_int_only({"a": 1.0}), "1.0 is a float")


func test_net_example(t: TestCtx) -> void:
	var c: SimMatchConfig = _net_example()
	t.eq(c.players.size(), 3, "3 players")
	t.eq(c.max_pid(), 5, "non-contiguous pids -> max_pid 5")
	t.eq(c.validate(StubData.new(), 8), PackedStringArray(), "validates against fixture rosters")
	t.eq(c.seed_value, 3141592653, "seed")
	t.eq(c.players[2].kind, SimPlayerSlot.AI, "AI slot")
	t.eq(c.players[2].ai_level, 2, "ai level")
	t.eq(c.players[2].handicap, 120, "handicap")
	t.eq(c.rules.fog, 1, "bool rule folded to 1")
	t.eq(c.rules.shared_vision, 0, "bool rule folded to 0")
	t.eq(c.rules.start_mode, SimMatchRules.START_HQ, "kernel-only rule default")
	t.eq(c.config_hash(), 3200203660, "config_hash of the net.md 7.1 example (sim_core golden)")


func test_hash_stability(t: TestCtx) -> void:
	var c: SimMatchConfig = _net_example()
	var h: int = c.config_hash()
	var c2: SimMatchConfig = SimMatchConfig.from_dict(c.to_dict())
	t.eq(c2.config_hash(), h, "to_dict -> from_dict keeps the hash")
	c2.players[0].name = "Somebody else"
	t.eq(c2.config_hash(), h, "renaming a player keeps the hash")
	c2.players[1].handicap = 110
	t.ne(c2.config_hash(), h, "changing a handicap changes the hash")
	var c3: SimMatchConfig = _net_example()
	c3.seed_value += 1
	t.ne(c3.config_hash(), h, "seed")
	c3 = _net_example()
	c3.rules.unit_cap = 151
	t.ne(c3.config_hash(), h, "rules")
	c3 = _net_example()
	c3.map["size"] = 96
	t.ne(c3.config_hash(), h, "map")


func test_players_sorted_and_roundtrip(t: TestCtx) -> void:
	var d: Dictionary = {"seed": 1, "map": {}, "rules": {}, "players": [
		{"pid": 5, "roster": "roster.fx.c"}, {"pid": 0, "roster": "roster.fx.a"}, {"pid": 2, "roster": "roster.fx.b"}]}
	var c: SimMatchConfig = SimMatchConfig.from_dict(d)
	t.eq(c.players[0].pid, 0, "sorted by pid")
	t.eq(c.players[1].pid, 2, "sorted by pid")
	t.eq(c.players[2].pid, 5, "sorted by pid")
	var s: SimPlayerSlot = SimPlayerSlot.from_dict({"pid": 3, "kind": "ai", "ai": {"level": 3, "style": 1, "flags": 1}, "peer": 9, "handicap": 80})
	var s2: SimPlayerSlot = SimPlayerSlot.from_dict(s.to_dict())
	t.eq([s2.pid, s2.kind, s2.ai_level, s2.ai_style, s2.ai_flags, s2.handicap], [3, SimPlayerSlot.AI, 3, 1, 1, 80] as Array, "slot round trip")


func test_rules(t: TestCtx) -> void:
	var r: SimMatchRules = SimMatchRules.new()
	var buf: PackedInt32Array = PackedInt32Array()
	r.hash_into(buf)
	t.eq(buf, PackedInt32Array([7500, 150, 1, 1, 0, 0, 2, 128, 0, 1, 1, 1, 0]), "13 defaults in FIELDS order")
	t.eq(SimMatchRules.FIELDS.size(), 13, "13 fields")
	t.eq(r.validate(), PackedStringArray(), "defaults are valid")
	var d: Dictionary = r.to_dict()
	t.eq(d.keys().size(), 8, "only the lobby keys at defaults")
	t.eq(d["fog"], true, "lobby booleans are written as booleans")
	r.allow_debug = 1
	r.start_mode = SimMatchRules.START_MCV
	var r2: SimMatchRules = SimMatchRules.from_dict(r.to_dict())
	t.eq(r2.allow_debug, 1, "kernel-only key round trips")
	t.eq(r2.start_mode, 1, "start_mode round trips")
	var r3: SimMatchRules = SimMatchRules.from_dict({"fog": false, "bogus": 3, "unit_cap": 99.0})
	t.eq(r3.fog, 0, "false -> 0")
	t.eq(r3.unit_cap, 99, "float value read with int()")
	r3.vision_stride = 9
	t.eq(r3.validate(), PackedStringArray(["rules.vision_stride out of range"]), "range message")
