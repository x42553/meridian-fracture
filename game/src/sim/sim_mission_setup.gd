class_name SimMissionSetup
extends RefCounted
## Builds the match configuration of a mission (MIS1) in the UI shape that the skirmish path understands
## (`AppNetSetup.complete_config` -> `NetMatchConfig.normalize` -> `NetSession.local_from_config`; also `SimMatchConfig.from_dict`):
## {seed, mission, map {family, size, seed, layout_players, params}, rules {8 lobby keys}, players [...]}. The sim reads the
## mission itself from GameData (config.mission) and applies its remaining rules (victory, neutral structures, ...), so the dictionary
## only has to carry the lobby-visible values. Missions are LOCAL matches: one human, everybody else scripted / AI.


## {} (+ Log.error) when `mission_id` is unknown.
static func build_config(data: GameData, mission_id: String) -> Dictionary:
	var t: DefMissionTable = DefMissionTable.of(data)
	var m: DefMission = t.get_mission(mission_id) if t != null else null
	if m == null:
		Log.error("mission", "build_config: unknown mission '%s'" % mission_id)
		return {}
	var rules: SimMatchRules = SimMatchRules.new()
	for k: Variant in m.rules.keys():
		rules.set(str(k), int(m.rules[k]))
	var lobby_rules: Dictionary = {}
	var full: Dictionary = rules.to_dict()
	for k: String in SimMatchRules.FIELDS.slice(0, 8):
		lobby_rules[k] = full[k]
	var players: Array = []
	for p: DefMissionPlayer in m.players:
		var d: Dictionary = {"pid": p.slot, "kind": "human" if p.human else "ai", "name": p.ui_name, "roster": p.roster, "team": p.team,
			"color": p.color, "start": p.start_slot, "handicap": p.handicap}
		if not p.human:
			d["ai"] = {"level": p.ai_level, "style": p.ai_style, "flags": 0}
		players.append(d)
	return {
		"seed": m.sim_seed, "mission": m.id,
		"map": {"family": m.map_family, "size": m.map_size, "seed": m.map_seed, "layout_players": m.layout_players, "params": m.map_params.duplicate()},
		"rules": lobby_rules, "players": players,
	}


## Mission ids in menu order (group, order, id).
static func ids_in_order(data: GameData) -> PackedStringArray:
	var t: DefMissionTable = DefMissionTable.of(data)
	var out: PackedStringArray = PackedStringArray()
	if t == null:
		return out
	var list: Array[DefMission] = t.missions.duplicate()
	list.sort_custom(func(a: DefMission, b: DefMission) -> bool:
		if a.group != b.group:
			return a.group < b.group
		if a.order != b.order:
			return a.order < b.order
		return a.id < b.id)
	for m: DefMission in list:
		out.append(m.id)
	return out
