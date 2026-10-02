class_name SimMatchConfig
extends RefCounted
## The sim's reader of net's MatchConfig (sim_core 3.8 / 5.10): seed, map dictionary, rules, players. Ignores
## `format, match_id, created_unix, versions, net` and each player's `peer`. Pure ints: the sim has no float
## handling (lint L003), so net's `NetMatchConfig.normalize` must already have folded JSON floats to ints;
## `validate` re-checks the `map` dictionary with `is_int_only`.

var seed_value: int = 0  ## u32
var map: Dictionary = {}  ## opaque to the sim: interpreted by the map domain (ints, strings, arrays only)
var rules: SimMatchRules = SimMatchRules.new()
var players: Array[SimPlayerSlot] = []  ## sorted by pid
## MIS1: id of a scripted mission (data.ext["missions"]); "" = a plain skirmish. The mission's script, rules overrides and
## start placement are applied by SimWorld; it enters config_hash only when set (plain matches keep their hashes).
var mission_id: String = ""


## Reads exactly net.md 7.1. Players are sorted by pid (insertion sort: stable and total).
static func from_dict(d: Dictionary) -> SimMatchConfig:
	var c: SimMatchConfig = SimMatchConfig.new()
	c.seed_value = int(d.get("seed", 0))
	c.mission_id = str(d.get("mission", ""))
	var m: Variant = d.get("map", {})
	c.map = (m as Dictionary).duplicate(true) if m is Dictionary else {}
	var r: Variant = d.get("rules", {})
	c.rules = SimMatchRules.from_dict(r as Dictionary) if r is Dictionary else SimMatchRules.new()
	var plist: Variant = d.get("players", [])
	if plist is Array:
		for pd: Variant in plist as Array:
			if pd is Dictionary:
				var s: SimPlayerSlot = SimPlayerSlot.from_dict(pd as Dictionary)
				var i: int = c.players.size()
				c.players.append(s)
				while i > 0 and c.players[i - 1].pid > s.pid:
					c.players[i] = c.players[i - 1]
					i -= 1
				c.players[i] = s
	return c


## Dictionary in the shape from_dict reads.
func to_dict() -> Dictionary:
	var pl: Array = []
	for s: SimPlayerSlot in players:
		pl.append(s.to_dict())
	var out: Dictionary = {"seed": seed_value, "map": map.duplicate(true), "rules": rules.to_dict(), "players": pl}
	if mission_id != "":
		out["mission"] = mission_id
	return out


## Highest pid in use, -1 without players.
func max_pid() -> int:
	var m: int = -1
	for s: SimPlayerSlot in players:
		m = maxi(m, s.pid)
	return m


## true when no float occurs anywhere inside v (ints, bools, strings, arrays and dictionaries thereof).
static func is_int_only(v: Variant) -> bool:
	if v is int or v is bool or v is String or v is StringName:
		return true
	if v is Array:
		for e: Variant in v as Array:
			if not is_int_only(e):
				return false
		return true
	if v is Dictionary:
		var dict: Dictionary = v
		for k: Variant in dict:
			if not is_int_only(k) or not is_int_only(dict[k]):
				return false
		return true
	return false


## Hash of everything sim-relevant after normalisation (names excluded); mixed into every checksum through the
## `world` part. Net computes its own hash over the exact transmitted bytes for the lobby handshake.
func config_hash() -> int:
	var h: int = Checksum.FNV_OFFSET
	h = Checksum.mix64(h, seed_value)
	var buf: PackedInt32Array = PackedInt32Array()
	rules.hash_into(buf)
	h = Checksum.mix(h, Checksum.digest32(buf))
	for s: SimPlayerSlot in players:
		h = Checksum.mix(h, s.pid)
		h = Checksum.mix(h, s.kind)
		h = Checksum.fnv_string(s.roster, h)
		h = Checksum.mix(h, s.team)
		h = Checksum.mix(h, s.color)
		h = Checksum.mix(h, s.start)
		h = Checksum.mix(h, s.handicap)
		h = Checksum.mix(h, s.ai_level)
		h = Checksum.mix(h, s.ai_style)
		h = Checksum.mix(h, s.ai_flags)
	h = Checksum.fnv_string(JSON.stringify(map, "", true), h)
	if mission_id != "":
		h = Checksum.fnv_string(mission_id, h)
	return Checksum.finalize(h)


## Deterministic validation; [] = valid. `data` is a GameData (only `roster_idx(id) -> int`, negative = unknown, is
## called; null skips the roster check), `start_count` = map.spawns.size() / MapData.SPAWN_STRIDE.
func validate(data: GameData, start_count: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if seed_value < 0 or seed_value > 0xFFFFFFFF:
		out.append("seed must be a u32")
	if not is_int_only(map):
		out.append("map must contain only ints, strings and arrays (no floats)")
	if players.size() < 1 or players.size() > SimConfig.MAX_PLAYERS:
		out.append("players must have 1..%d entries" % SimConfig.MAX_PLAYERS)
	var pids: Dictionary = {}
	var colors: Dictionary = {}
	var starts: Dictionary = {}
	for s: SimPlayerSlot in players:
		var tag: String = "pid %d" % s.pid
		if s.pid < 0 or s.pid >= SimConfig.MAX_PLAYERS:
			out.append("%s: pid out of range" % tag)
		elif pids.has(s.pid):
			out.append("%s: duplicate pid" % tag)
		pids[s.pid] = true
		if s.kind != SimPlayerSlot.HUMAN and s.kind != SimPlayerSlot.AI:
			out.append("%s: kind invalid" % tag)
		if data != null and data.roster_idx(s.roster) < 0:
			out.append("%s: unknown roster '%s'" % [tag, s.roster])
		if s.team < 1 or s.team > 15:
			out.append("%s: team out of range" % tag)
		if s.color < 0 or s.color > 11 or colors.has(s.color):
			out.append("%s: colour invalid or duplicated" % tag)
		colors[s.color] = true
		if s.start < 0 or s.start >= start_count or starts.has(s.start):
			out.append("%s: start invalid or duplicated" % tag)
		starts[s.start] = true
		if s.handicap < 50 or s.handicap > 200:
			out.append("%s: handicap out of range" % tag)
	out.append_array(rules.validate())
	if mission_id != "" and data != null:
		var t: DefMissionTable = DefMissionTable.of(data)
		var m: DefMission = t.get_mission(mission_id) if t != null else null
		if m == null:
			out.append("unknown mission '%s'" % mission_id)
		else:
			for p: DefMissionPlayer in m.players:
				var found: bool = false
				for s: SimPlayerSlot in players:
					found = found or s.pid == p.slot
				if not found:
					out.append("mission '%s' needs player slot %d" % [mission_id, p.slot])
	return out
