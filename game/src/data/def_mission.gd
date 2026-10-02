class_name DefMission
extends DefBase
## A compiled scripted mission (schema key `meridian.mission/1`, file game/data/missions/<id>.json, listed in
## balance/manifest.json under "missions"). ALL integers: the compiler (DefMissionParser) converts the JSON once at load.
## The JSON schema is documented field by field in DefMissionParser (header comment) and printed by
## `python3 tools/py/validate_missions.py --schema`.
##
## Hash rule (DefBase): `ui_*` fields (texts) are NOT part of the data hash; everything else is, so a changed script,
## map, roster or number changes data_hash and the lobby / replay handshake. Texts still change the per-file hash.

var group: String = "custom"  ## "tutorial" | "operation" | "demo" | any lowercase word
var order: int = 0  ## sort key inside the group (menu order)
var ui_title: String = ""
var ui_briefing: Array = []  ## [{"heading": String, "text": String, "lore": String}]
var map_family: int = 0  ## MapGenParams.FAM_*
var map_size: int = 96
var map_seed: int = 1
var map_params: Dictionary = {}  ## water_pct, density, resources, neutrals, biome, start_near_water (ints)
var layout_players: int = 2  ## 2 / 4 / 6 / 8 (net's start layouts), derived from the player count and start slots
var sim_seed: int = 1  ## SimMatchConfig.seed_value
var rules: Dictionary = {}  ## SimMatchRules field name -> int; ONLY the overridden fields (start_mode is always forced to NONE)
var players: Array[DefMissionPlayer] = []
var areas: Array[DefMissionArea] = []
var messages: Array[DefMissionMessage] = []
var objectives: Array[DefMissionObjective] = []
var timers: Array[DefMissionTimer] = []
var triggers: Array[DefMissionTrigger] = []  ## sorted by id: the evaluation order
var announcers: PackedStringArray = PackedStringArray()  ## distinct announcer line ids used by messages / show_message, sorted
var latches: int = 0  ## number of area_left conditions (each owns one latch bit in the runtime state)
var waves: PackedStringArray = PackedStringArray()  ## wave ids in index order (sorted)
var placed: PackedStringArray = PackedStringArray()  ## placed-structure ids in index order (sorted)


func player_of(pid: int) -> DefMissionPlayer:
	for p: DefMissionPlayer in players:
		if p.slot == pid:
			return p
	return null


func area_idx(area_id: String) -> int:
	for i: int in areas.size():
		if areas[i].id == area_id:
			return i
	return -1


func objective_idx(obj_id: String) -> int:
	for i: int in objectives.size():
		if objectives[i].id == obj_id:
			return i
	return -1
