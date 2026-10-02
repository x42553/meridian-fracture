class_name SndMatchConfig
extends RefCounted
## Typed input of SndManager.begin_match (audio spec 4.4).

const RESULT_NONE: int = 0
const RESULT_VICTORY: int = 1
const RESULT_DEFEAT: int = 2
const RESULT_DRAW: int = 3
const RESULT_ABORT: int = 4

var data: GameData = null
var local_pid: int = 0
var local_team: int = -1
var observer: bool = false
var replay: bool = false
var player_factions: PackedStringArray = PackedStringArray()  ## index = pid -> lower-case faction code, "" = empty slot
var local_roster_id: String = ""
var family: int = 0  ## MapData.family
var biome: int = 0  ## MapData.biome
var match_seed: int = 0


func local_faction() -> String:
	if local_pid >= 0 and local_pid < player_factions.size():
		return player_factions[local_pid]
	return ""


func factions_in_match() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f: String in player_factions:
		if f != "" and not out.has(f):
			out.append(f)
	return out


## Builds the config from a live world (the app glue): factions per pid, map family and biome, seed from the world config.
static func from_world(world: SimWorld, viewer_pid: int) -> SndMatchConfig:
	var c: SndMatchConfig = SndMatchConfig.new()
	c.data = world.data
	c.local_pid = viewer_pid
	c.local_team = world.team_of(viewer_pid)
	c.observer = viewer_pid < 0
	for p: SimPlayer in world.players:
		var code: String = ""
		if p.controller != SimPlayer.Controller.NONE and p.faction_idx >= 0 and p.faction_idx < world.data.factions.size():
			code = world.data.factions[p.faction_idx].code.to_lower()
		c.player_factions.append(code)
	if world.map != null:
		c.family = world.map.family
		c.biome = world.map.biome
	c.match_seed = world.map_hash() if world.map != null else 0
	return c
