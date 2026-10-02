class_name NetMatchConfig
extends RefCounted
## Static helpers over the MatchConfig Dictionary (schema: docs/spec/net.md 7.1): building it from the lobby
## (random rosters / teams / starts resolved on the host), strict normalisation of a parsed JSON tree, validation
## against the local build, canonical JSON and the config hash. Nothing here reads the clock or a global RNG: the
## same lobby + seed + timestamp always give the same bytes.

const OPTIONS_PATH: String = "res://data/net/lobby_options.json"
const FORMAT: int = 1
const LAYOUTS: PackedInt32Array = [2, 4, 6, 8]
const ROSTER_MAX_CHARS: int = 40
const MISSION_MAX_CHARS: int = 40
## Map generator parameters a config may carry in `map.params` (missions only use them; lobbies send {}). Inclusive ranges.
const MAP_PARAM_RANGES: Dictionary = {"water_pct": [0, 40], "density": [0, 100], "resources": [0, 100], "neutrals": [0, 100], "biome": [0, 2], "start_near_water": [0, 1]}

## Roster ids used to resolve random tokens when from_lobby gets no explicit list (the app sets it from GameData).
static var default_roster_ids: PackedStringArray = PackedStringArray()
static var _options: Dictionary = {}


# ---- lobby_options.json ----------------------------------------------------------------------------------

## The parsed game/data/net/lobby_options.json ({} if it cannot be read). Cached.
static func options() -> Dictionary:
	if _options.is_empty():
		var f: FileAccess = FileAccess.open(OPTIONS_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_options = parsed as Dictionary
	return _options


## rules_schema entries as {key, type ("int"|"bool"), min, max, default (int; bools 0/1)}, in file order.
static func rules_schema() -> Array:
	var out: Array = []
	for e: Variant in options().get("rules_schema", []) as Array:
		var d: Dictionary = e as Dictionary
		var is_bool: bool = str(d.get("type", "int")) == "bool"
		var def: int = (1 if bool(d.get("default", false)) else 0) if is_bool else int(d.get("default", 0))
		out.append({
			"key": str(d.get("key", "")), "type": "bool" if is_bool else "int",
			"min": 0 if is_bool else int(d.get("min", 0)), "max": 1 if is_bool else int(d.get("max", 0)), "default": def,
		})
	return out


## {key: default int} for every rules_schema key (bools as 0/1).
static func default_rules() -> Dictionary:
	var out: Dictionary = {}
	for e: Variant in rules_schema():
		out[(e as Dictionary)["key"]] = (e as Dictionary)["default"]
	return out


# ---- roster tokens ---------------------------------------------------------------------------------------

## "random", "random.vanilla", "random.subfaction" and "random.<fac>" (fac = second id component).
static func is_random_token(token: String) -> bool:
	return token == "random" or token.begins_with("random.")


## Matching roster ids of `ids` in ascending string order (empty for a concrete id or an unknown token).
static func token_candidates(token: String, ids: PackedStringArray) -> PackedStringArray:
	var sorted: PackedStringArray = ids.duplicate()
	sorted.sort()
	if token == "random":
		return sorted
	var out: PackedStringArray = PackedStringArray()
	for id: String in sorted:
		var parts: PackedStringArray = id.split(".")
		var vanilla: bool = parts.size() >= 3 and parts[2] == "vanilla"
		match token:
			"random.vanilla":
				if vanilla:
					out.append(id)
			"random.subfaction":
				if not vanilla:
					out.append(id)
			_:
				if token.begins_with("random.") and parts.size() >= 2 and parts[1] == token.substr(7):
					out.append(id)
	return out


## true for a concrete id of `ids` or a random token with at least one candidate. An empty `ids` accepts any
## non-empty string of a sane length (no list injected).
static func is_roster_ok(roster: String, ids: PackedStringArray) -> bool:
	if roster.is_empty() or roster.length() > ROSTER_MAX_CHARS:
		return false
	if ids.is_empty():
		return true
	if is_random_token(roster):
		return not token_candidates(roster, ids).is_empty()
	return ids.has(roster)


# ---- from_lobby -------------------------------------------------------------------------------------------

## Builds the MatchConfig from the lobby (host only). Resolves random rosters and start positions with
## lobby_rand(match_seed ^ 0xA5A5A5A5, counter) (spec 5.3.5). `versions`: {game, proto, sim, data_hash, data_format,
## data_ids, optional match_id (16 hex)}. `roster_ids` supplies the candidates for random tokens (default:
## NetMatchConfig.default_roster_ids). net.input_delay starts at D_MIN_LAN; the session overwrites it for LOCAL.
static func from_lobby(state: NetLobbyState, match_seed: int, versions: Dictionary, now_unix: int,
		roster_ids: PackedStringArray = PackedStringArray()) -> Dictionary:
	var ids: PackedStringArray = roster_ids if not roster_ids.is_empty() else default_roster_ids
	var seed32: int = match_seed & 0xFFFFFFFF
	var rs: int = seed32 ^ 0xA5A5A5A5
	var c: int = 0
	var active: PackedInt32Array = state.active_slot_indices()
	# (1) random rosters, slots ascending
	var roster: Dictionary = {}
	for i: int in active:
		var r: String = state.slots[i].roster_id
		if is_random_token(r):
			var cand: PackedStringArray = token_candidates(r, ids)
			if not cand.is_empty():
				r = cand[NetProtocol.lobby_rand(rs, c) % cand.size()]
				c += 1
		roster[i] = r
	# (2) final teams
	var team_final: Dictionary = {}
	for i: int in active:
		var t: int = state.slots[i].team
		team_final[i] = t if t > 0 else 8 + i
	# (3) start positions
	var start_of: Dictionary = {}
	var reserved: Dictionary = {}
	for i: int in active:
		var st: int = state.slots[i].start
		if st >= 0 and st < state.layout_players and not reserved.has(st):
			start_of[i] = st
			reserved[st] = true
	var free: PackedInt32Array = PackedInt32Array()
	for s: int in state.layout_players:
		if not reserved.has(s):
			free.append(s)
	var groups: Array = []  # [{team, members: Array[int]}] ordered by lowest slot index
	for i: int in active:
		if start_of.has(i):
			continue
		var found: Dictionary = {}
		for g: Variant in groups:
			if int((g as Dictionary)["team"]) == int(team_final[i]):
				found = g as Dictionary
				break
		if found.is_empty():
			found = {"team": int(team_final[i]), "members": []}
			groups.append(found)
		(found["members"] as Array).append(i)
	c = shuffle_groups(groups, rs, c)
	var k: int = 0
	for g: Variant in groups:
		for m: Variant in (g as Dictionary)["members"] as Array:
			start_of[int(m)] = free[k] if k < free.size() else -1
			k += 1
	# (4) players
	var players: Array = []
	for i: int in active:
		var s: NetPlayerSlot = state.slots[i]
		var p: Dictionary = {
			"pid": i, "kind": "human" if s.kind == NetProtocol.SlotKind.HUMAN else "ai",
			"peer": s.peer_id if s.kind == NetProtocol.SlotKind.HUMAN else 0,
			"name": NetProtocol.sanitize_name(s.name) if s.kind == NetProtocol.SlotKind.HUMAN else "AI %d" % (i + 1),
			"roster": str(roster[i]), "team": int(team_final[i]), "color": s.color, "start": int(start_of[i]),
			"handicap": s.handicap_pct,
		}
		if s.kind == NetProtocol.SlotKind.AI:
			p["ai"] = {"level": s.ai_level, "style": s.ai_style, "flags": s.ai_flags}
		players.append(p)
	# rules: bools for bool-typed schema keys
	var rules: Dictionary = {}
	for e: Variant in rules_schema():
		var d: Dictionary = e as Dictionary
		var key: String = str(d["key"])
		var v: int = int(state.rules.get(key, d["default"]))
		if str(d["type"]) == "bool":
			rules[key] = v != 0
		else:
			rules[key] = v
	var speeds: PackedInt32Array = NetProtocol.SPEED_PCT
	var mid: String = str(versions.get("match_id", ""))
	if not _is_hex16(mid):
		mid = "%08x%08x" % [NetProtocol.mix32(seed32 ^ 0x1D872B41), NetProtocol.mix32((now_unix & 0xFFFFFFFF) ^ seed32 ^ 0x7F4A7C15)]
	return {
		"format": FORMAT,
		"match_id": mid,
		"created_unix": maxi(now_unix, 0),
		"versions": {
			"game": NetProtocol.truncate_utf8(str(versions.get("game", "")), 24),
			"proto": int(versions.get("proto", NetProtocol.PROTO_VERSION)),
			"sim": int(versions.get("sim", 0)),
			"data_hash": int(versions.get("data_hash", 0)) & 0xFFFFFFFF,
			"data_format": int(versions.get("data_format", 0)),
			"data_ids": int(versions.get("data_ids", 0)) & 0xFFFFFFFF,
		},
		"seed": seed32,
		"map": {
			"family": state.map_family, "size": state.map_size, "seed": state.map_seed & 0xFFFFFFFF,
			"layout_players": state.layout_players, "params": {},
		},
		"rules": rules,
		"net": {
			"turn_ticks": NetProtocol.TURN_TICKS, "checksum_period": NetProtocol.CHECKSUM_PERIOD_TICKS,
			"input_delay": NetProtocol.D_MIN_LAN, "speed_pct": speeds[clampi(state.speed_code, 0, speeds.size() - 1)],
			"pause_policy": state.pause_policy, "on_disconnect": state.on_disconnect, "auto_drop_ms": state.auto_drop_ms,
			"allow_spectators": state.allow_spectators,
		},
		"players": players,
	}


## Fisher-Yates over `groups` in place: for i = n-1 .. 1: j = lobby_rand(rs, c++) % (i+1); swap(i, j). Returns the
## advanced counter.
static func shuffle_groups(groups: Array, rs: int, counter: int) -> int:
	var c: int = counter
	var i: int = groups.size() - 1
	while i >= 1:
		var j: int = NetProtocol.lobby_rand(rs, c) % (i + 1)
		c += 1
		var tmp: Variant = groups[i]
		groups[i] = groups[j]
		groups[j] = tmp
		i -= 1
	return c


static func _is_hex16(s: String) -> bool:
	if s.length() != 16:
		return false
	for i: int in 16:
		var ch: int = s.unicode_at(i)
		if not ((ch >= 48 and ch <= 57) or (ch >= 97 and ch <= 102) or (ch >= 65 and ch <= 70)):
			return false
	return true


# ---- normalize ---------------------------------------------------------------------------------------------

## Reader with a sticky failure flag: every accessor returns a harmless default after a violation.
class _Rd extends RefCounted:
	var ok: bool = true

	func fail() -> void:
		ok = false

	static func to_int(v: Variant) -> Variant:
		if typeof(v) == TYPE_INT:
			return v
		if typeof(v) == TYPE_FLOAT:
			var f: float = v
			if is_nan(f) or is_inf(f) or f != floorf(f) or absf(f) > 9007199254740992.0:
				return null
			return int(f)
		return null

	func i(d: Dictionary, key: String, lo: int, hi: int) -> int:
		var v: Variant = to_int(d.get(key))
		if v == null or int(v) < lo or int(v) > hi:
			ok = false
			return lo
		return int(v)

	func b(d: Dictionary, key: String) -> bool:
		var v: Variant = d.get(key)
		if typeof(v) != TYPE_BOOL:
			ok = false
			return false
		return bool(v)

	func s(d: Dictionary, key: String, min_len: int, max_len: int) -> String:
		var v: Variant = d.get(key)
		if typeof(v) != TYPE_STRING:
			ok = false
			return ""
		var str_v: String = v
		if str_v.length() < min_len or str_v.length() > max_len:
			ok = false
			return ""
		return str_v

	func dict(d: Dictionary, key: String) -> Dictionary:
		var v: Variant = d.get(key)
		if typeof(v) != TYPE_DICTIONARY:
			ok = false
			return {}
		return v as Dictionary

	## Exactly these keys, no more, no fewer.
	func keys(d: Dictionary, names: Array) -> void:
		if d.size() != names.size():
			ok = false
			return
		for n: Variant in names:
			if not d.has(n):
				ok = false
				return


## Rebuilds the config from a whitelist: unknown / missing keys, wrong types, non-integral or non-finite numbers,
## out-of-range values, duplicate pid / colour / start / peer and unsorted players give {}. Floats with an integral
## value are coerced to int (JSON has only one number type). Roster membership is validate()'s job.
static func normalize(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var r: _Rd = _Rd.new()
	var src: Dictionary = raw as Dictionary
	var top: Array = ["format", "match_id", "created_unix", "versions", "seed", "map", "rules", "net", "players"]
	if src.has("mission"):
		top.append("mission")  # MIS1: optional scripted-mission id (sim reads it as SimMatchConfig.mission_id)
	r.keys(src, top)
	if not r.ok:
		return {}
	var out: Dictionary = {}
	out["format"] = r.i(src, "format", FORMAT, FORMAT)
	var mid: String = r.s(src, "match_id", 16, 16)
	if r.ok and not _is_hex16(mid):
		r.fail()
	out["match_id"] = mid
	out["created_unix"] = r.i(src, "created_unix", 0, 0x7FFFFFFFFFFF)
	out["versions"] = _norm_versions(r, r.dict(src, "versions"))
	out["seed"] = r.i(src, "seed", 0, 0xFFFFFFFF)
	var map: Dictionary = _norm_map(r, r.dict(src, "map"))
	out["map"] = map
	out["rules"] = _norm_rules(r, r.dict(src, "rules"))
	out["net"] = _norm_net(r, r.dict(src, "net"))
	if src.has("mission"):
		var mid_s: String = r.s(src, "mission", 1, MISSION_MAX_CHARS)
		if r.ok and not is_mission_id(mid_s):
			r.fail()
		out["mission"] = mid_s
	if not r.ok:
		return {}
	out["players"] = _norm_players(r, src.get("players"), int(map["layout_players"]))
	return out if r.ok else {}


static func _norm_versions(r: _Rd, d: Dictionary) -> Dictionary:
	r.keys(d, ["game", "proto", "sim", "data_hash", "data_format", "data_ids"])
	return {
		"game": r.s(d, "game", 0, 24), "proto": r.i(d, "proto", 0, 0xFFFF), "sim": r.i(d, "sim", 0, 0xFFFFFFFF),
		"data_hash": r.i(d, "data_hash", 0, 0xFFFFFFFF), "data_format": r.i(d, "data_format", 0, 0xFFFF),
		"data_ids": r.i(d, "data_ids", 0, 0xFFFFFFFF),
	}


## Mission ids: lowercase [a-z][a-z0-9_]* (DefMissionParser.id_ok).
static func is_mission_id(s: String) -> bool:
	if s.is_empty() or s.length() > MISSION_MAX_CHARS:
		return false
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (i > 0 and ((c >= 48 and c <= 57) or c == 95))):
			return false
	return true


static func _norm_map(r: _Rd, d: Dictionary) -> Dictionary:
	r.keys(d, ["family", "size", "seed", "layout_players", "params"])
	var out: Dictionary = {
		"family": r.i(d, "family", 0, 2), "size": r.i(d, "size", 96, 256), "seed": r.i(d, "seed", 0, 0xFFFFFFFF),
		"layout_players": r.i(d, "layout_players", 2, 8), "params": {},
	}
	if int(out["size"]) % 8 != 0 or not LAYOUTS.has(int(out["layout_players"])):
		r.fail()
	var params: Dictionary = r.dict(d, "params")
	var clean: Dictionary = {}
	for k: Variant in params.keys():
		var key: String = str(k)
		if not MAP_PARAM_RANGES.has(key):
			r.fail()
			continue
		var rng: Array = MAP_PARAM_RANGES[key]
		var pv: Variant = _Rd.to_int(params[k])
		if typeof(params[k]) == TYPE_BOOL:
			pv = 1 if bool(params[k]) else 0
		if pv == null or int(pv) < int(rng[0]) or int(pv) > int(rng[1]):
			r.fail()
			continue
		clean[key] = int(pv)
	out["params"] = clean
	return out


static func _norm_rules(r: _Rd, d: Dictionary) -> Dictionary:
	var schema: Array = rules_schema()
	var names: Array = []
	for e: Variant in schema:
		names.append((e as Dictionary)["key"])
	r.keys(d, names)
	var out: Dictionary = {}
	for e: Variant in schema:
		var sd: Dictionary = e as Dictionary
		var key: String = str(sd["key"])
		if str(sd["type"]) == "bool":
			out[key] = r.b(d, key)
		else:
			out[key] = r.i(d, key, int(sd["min"]), int(sd["max"]))
	return out


static func _norm_net(r: _Rd, d: Dictionary) -> Dictionary:
	r.keys(d, ["turn_ticks", "checksum_period", "input_delay", "speed_pct", "pause_policy", "on_disconnect", "auto_drop_ms", "allow_spectators"])
	var out: Dictionary = {
		"turn_ticks": r.i(d, "turn_ticks", NetProtocol.TURN_TICKS, NetProtocol.TURN_TICKS),
		"checksum_period": r.i(d, "checksum_period", NetProtocol.CHECKSUM_PERIOD_TICKS, NetProtocol.CHECKSUM_PERIOD_TICKS),
		"input_delay": r.i(d, "input_delay", 1, NetProtocol.D_MAX),
		"speed_pct": r.i(d, "speed_pct", 50, 200),
		"pause_policy": r.i(d, "pause_policy", 0, 2), "on_disconnect": r.i(d, "on_disconnect", 0, 1),
		"auto_drop_ms": r.i(d, "auto_drop_ms", 0, 600000), "allow_spectators": r.b(d, "allow_spectators"),
	}
	if not NetProtocol.SPEED_PCT.has(int(out["speed_pct"])):
		r.fail()
	return out


static func _norm_players(r: _Rd, raw: Variant, layout: int) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		r.fail()
		return []
	var arr: Array = raw as Array
	if arr.is_empty() or arr.size() > NetProtocol.MAX_PLAYERS or arr.size() > layout:
		r.fail()
		return []
	var out: Array = []
	var pids: Dictionary = {}
	var colors: Dictionary = {}
	var starts: Dictionary = {}
	var peers: Dictionary = {}
	var prev_pid: int = -1
	for pv: Variant in arr:
		if typeof(pv) != TYPE_DICTIONARY:
			r.fail()
			return []
		var d: Dictionary = pv as Dictionary
		var kind: String = r.s(d, "kind", 2, 5)
		var is_ai: bool = kind == "ai"
		if kind != "ai" and kind != "human":
			r.fail()
			return []
		var names: Array = ["pid", "kind", "peer", "name", "roster", "team", "color", "start", "handicap"]
		if is_ai:
			names.append("ai")
		r.keys(d, names)
		if not r.ok:
			return []
		var pid: int = r.i(d, "pid", 0, NetProtocol.MAX_PLAYERS - 1)
		var p: Dictionary = {
			"pid": pid, "kind": kind, "peer": r.i(d, "peer", 1 if not is_ai else 0, 0xFFFF if not is_ai else 0),
			"name": r.s(d, "name", 1, NetProtocol.NAME_MAX_CHARS), "roster": r.s(d, "roster", 1, ROSTER_MAX_CHARS),
			"team": r.i(d, "team", 1, 8 + pid), "color": r.i(d, "color", 0, 11), "start": r.i(d, "start", 0, layout - 1),
			"handicap": r.i(d, "handicap", 50, 200),
		}
		var team: int = int(p["team"])
		if not ((team >= 1 and team <= 4) or team == 8 + pid):
			r.fail()
		if int(p["handicap"]) % 5 != 0 or NetProtocol.sanitize_name(str(p["name"])) != str(p["name"]):
			r.fail()
		if is_ai:
			var ai: Dictionary = r.dict(d, "ai")
			r.keys(ai, ["level", "style", "flags"])
			p["ai"] = {"level": r.i(ai, "level", 0, 15), "style": r.i(ai, "style", 0, 15), "flags": r.i(ai, "flags", 0, 255)}
		if pid <= prev_pid or pids.has(pid) or colors.has(p["color"]) or starts.has(p["start"]):
			r.fail()
		if not is_ai and peers.has(p["peer"]):
			r.fail()
		if not r.ok:
			return []
		prev_pid = pid
		pids[pid] = true
		colors[p["color"]] = true
		starts[p["start"]] = true
		peers[p["peer"]] = true
		out.append(p)
	return out


# ---- validate / canonical / helpers ---------------------------------------------------------------------------

## "" = ok, else a human-readable error. `cfg` must come from normalize(). `opts` (NetSessionOptions, duck typed, may
## be null) supplies sim_version, data_hash, data_handshake, roster_ids, color_count, ai_level_count, ai_style_count.
static func validate(cfg: Dictionary, opts: RefCounted = null) -> String:
	if cfg.is_empty():
		return "empty or malformed config"
	var v: Dictionary = cfg["versions"] as Dictionary
	if int(v["proto"]) != NetProtocol.PROTO_VERSION:
		return "protocol version mismatch (host %d, local %d)" % [int(v["proto"]), NetProtocol.PROTO_VERSION]
	if opts != null:
		var sim_v: Variant = opts.get("sim_version")
		if typeof(sim_v) == TYPE_INT and int(v["sim"]) != int(sim_v):
			return "simulation version mismatch (host %d, local %d)" % [int(v["sim"]), int(sim_v)]
		var dh: Variant = opts.get("data_hash")
		if typeof(dh) == TYPE_INT and int(v["data_hash"]) != int(dh):
			return "game data mismatch (host %08X, local %08X)" % [int(v["data_hash"]), int(dh)]
		var hs_c: Variant = opts.get("data_handshake")
		if hs_c is Callable and (hs_c as Callable).is_valid():
			var hs: Dictionary = (hs_c as Callable).call(false) as Dictionary
			if int(v["data_format"]) != int(hs.get("format", v["data_format"])):
				return "game data format mismatch"
			var tables: Dictionary = hs.get("tables", {}) as Dictionary
			if tables.has("ids") and int(v["data_ids"]) != int(tables["ids"]):
				return "game data ids mismatch"
	var ids: PackedStringArray = PackedStringArray()
	var color_count: int = 12
	var level_count: int = 16
	var style_count: int = 16
	if opts != null:
		var rid: Variant = opts.get("roster_ids")
		if rid is PackedStringArray:
			ids = rid as PackedStringArray
		color_count = _pos_int(opts.get("color_count"), color_count)
		level_count = _pos_int(opts.get("ai_level_count"), level_count)
		style_count = _pos_int(opts.get("ai_style_count"), style_count)
	for pv: Variant in cfg["players"] as Array:
		var p: Dictionary = pv as Dictionary
		var roster: String = str(p["roster"])
		if is_random_token(roster) or (not ids.is_empty() and not ids.has(roster)):
			return "player %d: unknown roster '%s'" % [int(p["pid"]), roster]
		if int(p["color"]) >= color_count:
			return "player %d: colour out of range" % int(p["pid"])
		if p.has("ai"):
			var ai: Dictionary = p["ai"] as Dictionary
			if int(ai["level"]) >= level_count or int(ai["style"]) >= style_count:
				return "player %d: AI level or style out of range" % int(p["pid"])
	return ""


static func _pos_int(v: Variant, def: int) -> int:
	return int(v) if typeof(v) == TYPE_INT and int(v) > 0 else def


## JSON.stringify(cfg, "", true): sorted keys, no whitespace, ints only.
static func canonical_json(cfg: Dictionary) -> String:
	return JSON.stringify(cfg, "", true)


## FNV-1a 32 over the exact transmitted UTF-8 bytes.
static func config_hash(json_bytes: PackedByteArray) -> int:
	return NetProtocol.fnv1a32(json_bytes)


## Parses transmitted JSON text and normalises it ({} on any failure).
static func parse(json_text: String) -> Dictionary:
	if json_text.length() > NetProtocol.MAX_CONFIG_JSON:
		return {}
	var j: JSON = JSON.new()
	if j.parse(json_text) != OK:
		return {}
	return normalize(j.data)


## -1 if `peer_id` is not a human player of the config.
static func pid_of_peer(cfg: Dictionary, peer_id: int) -> int:
	for pv: Variant in cfg.get("players", []) as Array:
		var p: Dictionary = pv as Dictionary
		if str(p.get("kind", "")) == "human" and int(p.get("peer", 0)) == peer_id:
			return int(p["pid"])
	return -1


## Final team id of `pid` (-1 if absent).
static func team_of(cfg: Dictionary, pid: int) -> int:
	for pv: Variant in cfg.get("players", []) as Array:
		if int((pv as Dictionary).get("pid", -1)) == pid:
			return int((pv as Dictionary)["team"])
	return -1
