class_name MapDataTables
extends RefCounted
## The compiled map tables of one GameData (data.ext["map"]); built by MapDataCompiler.

var terrain: MapTerrain = null
var gen: MapGenTables = null


func _init(p_terrain: MapTerrain = null, p_gen: MapGenTables = null) -> void:
	terrain = p_terrain
	gen = p_gen
