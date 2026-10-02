class_name DefMissionTable
extends RefCounted
## data.ext["missions"]: every compiled mission, sorted by id (index == position).

var missions: Array[DefMission] = []
var _by_id: Dictionary = {}


func add(m: DefMission) -> void:
	m.index = missions.size()
	missions.append(m)
	_by_id[m.id] = m.index


func index_of(mission_id: String) -> int:
	return int(_by_id.get(mission_id, -1))


func get_mission(mission_id: String) -> DefMission:
	var i: int = index_of(mission_id)
	return missions[i] if i >= 0 else null


func ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for m: DefMission in missions:
		out.append(m.id)
	return out


## The missions table of a GameData (null when the data has none / no mission compiler).
static func of(data: GameData) -> DefMissionTable:
	if data == null:
		return null
	var v: Variant = data.ext.get("missions")
	return v as DefMissionTable
