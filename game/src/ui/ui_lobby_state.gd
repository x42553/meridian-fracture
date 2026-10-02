class_name UiLobbyState
extends RefCounted
## The editable skirmish setup (ui.md 5.14): 8 slots (human / AI level / open / closed, faction + subfaction pick, team, colour,
## start position), the map choice (family, size, seed) and the match rules. Pure data plus the rules of the lobby: colour swaps,
## layout size, roster picking (5.14.3), the start validation with `NetLobby.StartError` codes (5.14.4) and the conversion to the
## match config dictionary of net.md 7.1 that `AppMatch` hands to the session. No nodes; unit tested.

enum Kind { HUMAN = 0, AI = 1, OPEN = 2, CLOSED = 3 }
## = `NetLobby.StartError` (ui.md 5.14.4).
enum Err { OK = 0, NO_PLAYERS = 1, NOT_ENOUGH_PLAYERS = 2, HUMAN_NOT_READY = 3, HUMAN_DISCONNECTED = 4, BAD_ROSTER = 5, COLOR_CONFLICT = 6,
		START_CONFLICT = 7, TOO_MANY_PLAYERS = 8, MAP_INVALID = 9, SINGLE_TEAM = 10, ALREADY_LAUNCHING = 11, AI_UNAVAILABLE = 12 }

const MAX_SLOTS: int = 8
const COLOR_COUNT: int = 12
const AI_LEVELS: PackedStringArray = ["Easy", "Medium", "Hard", "Brutal"]
const TEAMS: PackedStringArray = ["None", "Team A", "Team B", "Team C", "Team D"]
const CREDITS: PackedInt32Array = [2500, 5000, 7500, 10000, 15000, 20000, 50000]
const UNIT_CAPS: PackedInt32Array = [50, 100, 150, 200, 300, 500]
const SPEEDS: PackedInt32Array = [50, 75, 100, 125, 150, 200]
const SIZES: PackedInt32Array = [96, 128, 160, 192, 224, 256]
const PRESETS_PATH: String = "res://data/ui/skirmish_presets.json"
const SAVE_PATH: String = "user://last_skirmish.json"
## Where `save` / `load_saved` read and write (tests point it at a sandbox).
static var save_path: String = SAVE_PATH
## Error text (5.14.4).
const ERR_TEXT: Dictionary = {
	Err.NO_PLAYERS: "There is no player in the first slot.",
	Err.NOT_ENOUGH_PLAYERS: "Add at least one opponent.",
	Err.HUMAN_NOT_READY: "A player is not ready.",
	Err.HUMAN_DISCONNECTED: "A player has disconnected.",
	Err.BAD_ROSTER: "A slot has an unknown faction.",
	Err.COLOR_CONFLICT: "Two players share a colour.",
	Err.START_CONFLICT: "Two players share a start position.",
	Err.TOO_MANY_PLAYERS: "The map layout has fewer start positions than players.",
	Err.MAP_INVALID: "The map settings are not valid.",
	Err.SINGLE_TEAM: "Everyone is on the same team. Split the teams or use free-for-all.",
	Err.ALREADY_LAUNCHING: "",
	Err.AI_UNAVAILABLE: "AI players are not available in this build.",
}


## One lobby row.
class Slot extends RefCounted:
	var kind: int = 2  ## Kind
	var ai_level: int = 1
	## Index into `GameData.factions`, -1 = random.
	var faction: int = 0
	## Faction picked: 0 vanilla, 1..3 subfaction, 4 any of the four. Random faction: 0 vanilla, 1 subfaction, 2 any.
	var sub: int = 0
	var team: int = 0  ## 0 none, 1..4 = A..D
	var color: int = 0
	var start: int = -1  ## -1 = automatic
	var name: String = ""
	## LAN roles (UiLobbyNet.pull): handicap 50..200 %, the seated peer, ready flag, transport state and the host-measured ping.
	var handicap: int = 100
	var peer_id: int = 0
	var ready: bool = true
	var connected: bool = true
	var ping_ms: int = 0

	func duplicate_slot() -> Slot:
		var s: Slot = Slot.new()
		s.kind = kind
		s.ai_level = ai_level
		s.faction = faction
		s.sub = sub
		s.team = team
		s.color = color
		s.start = start
		s.name = name
		s.handicap = handicap
		s.peer_id = peer_id
		s.ready = ready
		s.connected = connected
		s.ping_ms = ping_ms
		return s

	func active() -> bool:
		return kind == 0 or kind == 1


var slots: Array[Slot] = []
var family: int = 0
var size: int = 96
var seed_value: int = 1
var start_credits: int = 7500
var unit_cap: int = 150
var speed_pct: int = 100
var superweapons: bool = true
var fog: bool = true
var shared_vision: bool = false
var veterancy: bool = false
var player_name: String = "Commander"
## LAN roles: the replicated start-position layout (2 / 4 / 6 / 8); 0 = skirmish (derived from the slots).
var net_layout: int = 0
## LAN host options replicated in the snapshot (net.md 4.5): pause policy (NetProtocol.PausePolicy), on-disconnect policy,
## auto-drop ms, spectators allowed, the lobby name / password flag and the spectator list `[{peer_id, name}]`.
var pause_policy: int = 1
var on_disconnect: int = 0
var auto_drop_ms: int = 60000
var allow_spectators: bool = true
var lobby_name: String = ""
var password_set: bool = false
var spectators: Array = []

var _data: GameData = null


static func create(game_data: GameData) -> UiLobbyState:
	var s: UiLobbyState = UiLobbyState.new()
	s._data = game_data
	for i: int in MAX_SLOTS:
		var sl: Slot = Slot.new()
		sl.color = i
		sl.faction = mini(i, maxi(game_data.factions.size() - 1, 0)) if game_data != null else 0
		s.slots.append(sl)
	s.slots[0].kind = Kind.HUMAN
	s.slots[0].faction = maxi(_faction_index(game_data, "NAPC"), 0)
	s.slots[1].kind = Kind.AI
	s.slots[1].faction = maxi(_faction_index(game_data, "NEC"), 0)
	s.seed_value = randi() & 0xFFFFFFFF
	return s


static func _faction_index(game_data: GameData, code: String) -> int:
	if game_data != null:
		for i: int in game_data.factions.size():
			if game_data.factions[i].code == code:
				return i
	return -1


func data() -> GameData:
	return _data


func faction_count() -> int:
	return _data.factions.size() if _data != null else 0


# ---------------------------------------------------------------- layout

func active_count() -> int:
	var n: int = 0
	for s: Slot in slots:
		if s.active():
			n += 1
	return n


## Start positions of the map layout (net `map.layout_players`): 2 / 4 / 6 / 8 (net has no 3-slot layout: three players use the 4-slot one).
func layout_players() -> int:
	if net_layout > 0:
		return net_layout
	return AppNetSetup.net_layout(maxi(active_count(), 2))


func min_size() -> int:
	return maxi(MapGenParams.SIZE_MIN, MapGenParams.min_size(layout_players()))


## Raises the size to the layout minimum; true when it changed.
func fix_size() -> bool:
	if size >= min_size():
		return false
	size = min_size()
	return true


## Opens / closes the trailing slots so that `n` (2..8) players fit; slots >= n become CLOSED (5.14.5), slots < n that were
## CLOSED become OPEN.
func set_layout_players(n: int) -> void:
	n = clampi(n, 2, MAX_SLOTS)
	if net_layout > 0:
		net_layout = AppNetSetup.net_layout(n)  # LAN: the host's NetLobby opens / closes the slots
		fix_size()
		return
	for i: int in MAX_SLOTS:
		if i >= n and slots[i].kind != Kind.CLOSED:
			slots[i].kind = Kind.CLOSED
		elif i < n and slots[i].kind == Kind.CLOSED:
			slots[i].kind = Kind.OPEN
	fix_size()


func set_kind(i: int, kind: int) -> void:
	if i <= 0 or i >= MAX_SLOTS:
		return
	slots[i].kind = kind
	fix_size()


## Gives slot `i` colour `c`; a slot that already used `c` receives the colour `i` had (swap, 5.14.2).
func set_color(i: int, c: int) -> void:
	c = posmod(c, COLOR_COUNT)
	var old: int = slots[i].color
	for j: int in MAX_SLOTS:
		if j != i and slots[j].active() and slots[j].color == c:
			slots[j].color = old
	slots[i].color = c


## Start position per slot: the explicit choice, else the lowest free position, -1 for inactive slots.
func resolved_starts() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(MAX_SLOTS)
	out.fill(-1)
	var used: Dictionary = {}
	for i: int in MAX_SLOTS:
		if slots[i].active() and slots[i].start >= 0:
			out[i] = slots[i].start
			used[slots[i].start] = true
	var next: int = 0
	for i: int in MAX_SLOTS:
		if slots[i].active() and slots[i].start < 0:
			while used.has(next):
				next += 1
			out[i] = next
			used[next] = true
	return out


# ---------------------------------------------------------------- roster picking (5.14.3)

## Subfaction dropdown items for a faction index (-1 = random faction).
func sub_options(faction: int) -> PackedStringArray:
	if faction < 0 or _data == null or faction >= _data.factions.size():
		return PackedStringArray(["Vanilla (any faction)", "Subfaction (any faction)", "Any"])
	var out: PackedStringArray = PackedStringArray(["Vanilla"])
	for ri: int in _data.factions[faction].sub_rosters:
		out.append(_data.rosters[ri].id.get_slice(".", 2).replace("_", " ").capitalize())
	out.append("Any (random of 4)")
	return out


## The roster id a slot stands for; random picks use `rng`. "" for an unknown faction.
func roster_id(i: int, rng: RandomNumberGenerator) -> String:
	if _data == null:
		return ""
	var s: Slot = slots[i]
	if s.faction < 0:
		var pool: Array[String] = []
		for f: DefFaction in _data.factions:
			if s.sub != 1:
				pool.append(_data.rosters[f.vanilla_roster].id)
			if s.sub != 0:
				for ri: int in f.sub_rosters:
					pool.append(_data.rosters[ri].id)
		return pool[rng.randi() % pool.size()] if not pool.is_empty() else ""
	if s.faction >= _data.factions.size():
		return ""
	var f2: DefFaction = _data.factions[s.faction]
	if s.sub == 0:
		return _data.rosters[f2.vanilla_roster].id
	if s.sub >= 1 and s.sub <= f2.sub_rosters.size():
		return _data.rosters[f2.sub_rosters[s.sub - 1]].id
	var all: Array[String] = [_data.rosters[f2.vanilla_roster].id]
	for ri2: int in f2.sub_rosters:
		all.append(_data.rosters[ri2].id)
	return all[rng.randi() % all.size()]


## The roster to show in the briefing / badge for a slot: exact when fixed, the vanilla / first sub for "any" picks (null = random faction).
func preview_roster(i: int) -> DefRoster:
	var s: Slot = slots[i]
	if _data == null or s.faction < 0 or s.faction >= _data.factions.size():
		return null
	var f: DefFaction = _data.factions[s.faction]
	if s.sub >= 1 and s.sub <= f.sub_rosters.size():
		return _data.rosters[f.sub_rosters[s.sub - 1]]
	return _data.rosters[f.vanilla_roster]


# ---------------------------------------------------------------- validation (5.14.4)

## {err: Err, slot: int (-1 = not slot-specific)}.
func validate() -> Dictionary:
	if slots[0].kind != Kind.HUMAN:
		return {"err": Err.NO_PLAYERS, "slot": 0}
	var active: Array[int] = []
	for i: int in MAX_SLOTS:
		if slots[i].active():
			active.append(i)
	if active.size() < 2:
		var open_slot: int = -1
		for i: int in MAX_SLOTS:
			if slots[i].kind == Kind.OPEN:
				open_slot = i
				break
		return {"err": Err.NOT_ENOUGH_PLAYERS, "slot": open_slot}
	if active.size() > layout_players():
		return {"err": Err.TOO_MANY_PLAYERS, "slot": -1}
	for i: int in active:
		if slots[i].faction >= faction_count() or (slots[i].faction >= 0 and slots[i].sub > 4):
			return {"err": Err.BAD_ROSTER, "slot": i}
	var seen: Dictionary = {}
	for i: int in active:
		if seen.has(slots[i].color):
			return {"err": Err.COLOR_CONFLICT, "slot": i}
		seen[slots[i].color] = true
	var starts: PackedInt32Array = resolved_starts()
	var used: Dictionary = {}
	for i: int in active:
		if starts[i] >= layout_players() or used.has(starts[i]):
			return {"err": Err.START_CONFLICT, "slot": i}
		used[starts[i]] = true
	var first_team: int = slots[active[0]].team
	var single: bool = first_team != 0
	for i: int in active:
		if slots[i].team != first_team or slots[i].team == 0:
			single = false
	if single:
		return {"err": Err.SINGLE_TEAM, "slot": -1}
	var problem: String = MapGenerator.validate_params(family, size, layout_players())
	if problem != "":
		return {"err": Err.MAP_INVALID, "slot": -1, "detail": problem}
	return {"err": Err.OK, "slot": -1}


static func error_text(err: int) -> String:
	return String(ERR_TEXT.get(err, "Cannot start."))


# ---------------------------------------------------------------- config

## The match config of net.md 7.1 (dictionary form) for the current setup. Random rosters are resolved with `rng`.
func to_config(rng: RandomNumberGenerator) -> Dictionary:
	var starts: PackedInt32Array = resolved_starts()
	var players: Array = []
	var team_ids: Dictionary = {}
	for i: int in MAX_SLOTS:
		if not slots[i].active():
			continue
		var s: Slot = slots[i]
		var pid: int = players.size()
		var human: bool = s.kind == Kind.HUMAN
		var nm: String = player_name if human else (s.name if s.name != "" else "Bot %d" % pid)
		var p: Dictionary = {"pid": pid, "kind": "human" if human else "ai", "name": nm, "roster": roster_id(i, rng),
			"team": s.team if s.team > 0 else 5 + i, "color": s.color, "start": starts[i], "handicap": 120 if (not human and s.ai_level == 3) else 100}
		if not human:
			p["ai"] = {"level": s.ai_level, "style": 0, "flags": 0}
		team_ids[i] = p["team"]
		players.append(p)
	return {
		"seed": rng.randi() & 0x7FFFFFFF,
		"map": {"family": family, "size": size, "seed": seed_value, "layout_players": layout_players(), "params": {}},
		"rules": {"start_credits": start_credits, "unit_cap": unit_cap, "superweapons": superweapons, "fog": fog, "shared_vision": shared_vision,
			"veterancy": veterancy, "victory": 1},
		"net": {"speed_pct": speed_pct},
		"players": players,
	}


# ---------------------------------------------------------------- persistence and presets

func to_dict() -> Dictionary:
	var arr: Array = []
	for s: Slot in slots:
		arr.append({"kind": s.kind, "ai_level": s.ai_level, "faction": s.faction, "sub": s.sub, "team": s.team, "color": s.color, "start": s.start})
	return {"format": 1, "family": family, "size": size, "seed": seed_value, "start_credits": start_credits, "unit_cap": unit_cap,
		"speed_pct": speed_pct, "superweapons": superweapons, "fog": fog, "shared_vision": shared_vision, "veterancy": veterancy, "slots": arr}


## Restores a saved setup; unknown or out-of-range values fall back to the current ones (factions become Random).
func from_dict(d: Dictionary) -> void:
	family = clampi(int(d.get("family", family)), 0, 2)
	size = int(d.get("size", size)) if SIZES.has(int(d.get("size", size))) else size
	seed_value = int(d.get("seed", seed_value)) & 0xFFFFFFFF
	start_credits = int(d.get("start_credits", start_credits)) if CREDITS.has(int(d.get("start_credits", start_credits))) else start_credits
	unit_cap = int(d.get("unit_cap", unit_cap)) if UNIT_CAPS.has(int(d.get("unit_cap", unit_cap))) else unit_cap
	speed_pct = int(d.get("speed_pct", speed_pct)) if SPEEDS.has(int(d.get("speed_pct", speed_pct))) else speed_pct
	superweapons = bool(d.get("superweapons", superweapons))
	fog = bool(d.get("fog", fog))
	shared_vision = bool(d.get("shared_vision", shared_vision))
	veterancy = bool(d.get("veterancy", veterancy))
	var arr: Variant = d.get("slots", [])
	if arr is Array:
		for i: int in mini((arr as Array).size(), MAX_SLOTS):
			var sd: Variant = (arr as Array)[i]
			if not (sd is Dictionary):
				continue
			var s: Slot = slots[i]
			s.kind = clampi(int((sd as Dictionary).get("kind", s.kind)), 0, 3)
			s.ai_level = clampi(int((sd as Dictionary).get("ai_level", s.ai_level)), 0, AI_LEVELS.size() - 1)
			var f: int = int((sd as Dictionary).get("faction", s.faction))
			s.faction = f if f >= -1 and f < faction_count() else -1
			s.sub = clampi(int((sd as Dictionary).get("sub", s.sub)), 0, 4)
			s.team = clampi(int((sd as Dictionary).get("team", s.team)), 0, 4)
			s.color = clampi(int((sd as Dictionary).get("color", s.color)), 0, COLOR_COUNT - 1)
			s.start = clampi(int((sd as Dictionary).get("start", s.start)), -1, MAX_SLOTS - 1)
	slots[0].kind = Kind.HUMAN
	fix_size()


func save() -> void:
	var f: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(to_dict()))


## Restores the last saved setup when the file exists; true when it did.
func load_saved() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not (parsed is Dictionary):
		return false
	from_dict(parsed as Dictionary)
	return true


static func presets() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESETS_PATH))
	if parsed is Dictionary and (parsed as Dictionary).get("presets") is Array:
		return (parsed as Dictionary)["presets"] as Array
	return []


## Applies a preset entry of `skirmish_presets.json` (slots not listed become OPEN, factions are spread over the roster).
func apply_preset(p: Dictionary) -> void:
	family = clampi(int(p.get("family", 0)), 0, 2)
	size = int(p.get("size", 96))
	var list: Array = p.get("slots", []) as Array
	for i: int in MAX_SLOTS:
		var s: Slot = slots[i]
		s.kind = Kind.OPEN
		s.team = 0
		s.start = -1
		s.color = i
		s.sub = 0
		s.faction = i % maxi(faction_count(), 1)
		if i < list.size():
			var e: Dictionary = list[i] as Dictionary
			s.kind = Kind.HUMAN if str(e.get("kind", "ai")) == "human" else Kind.AI
			s.ai_level = clampi(int(e.get("ai_level", e.get("level", 1))), 0, AI_LEVELS.size() - 1)
			s.team = clampi(int(e.get("team", 0)), 0, 4)
	slots[0].kind = Kind.HUMAN
	fix_size()
