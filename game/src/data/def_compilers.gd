class_name DefCompilers
extends RefCounted
## Static registry of DefDomainCompiler plug-ins, sorted by domain_id; each domain adds ONE line to `all()`
## (data_balance 3.12, CMR-26). Registered: "map" (terrain.json + map_gen.json, DATAFIX), "missions" (game/data/missions, MIS1).


static func all() -> Array[DefDomainCompiler]:
	var out: Array[DefDomainCompiler] = []
	# loaded by path: src/data must not name map classes (lint L005); the compiler class lives in src/map
	# lint-allow: L005 DefCompilers IS the plug-in registry (data_balance 3.12); the map domain registers its compiler by path
	var sc: Script = load("res://src/map/map_data_compiler.gd") as Script
	out.append(sc.new() as DefDomainCompiler)
	out.append(DefMissionCompiler.new())
	return out
