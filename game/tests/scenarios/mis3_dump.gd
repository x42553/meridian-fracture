extends SceneTree
## MIS3 dev tool: prints the entities of every player at tick 0 (and after `ticks=N`, idle) of a shipped mission, with the resolved area centres.
##   tools/gd run res://tests/scenarios/mis3_dump.gd -- mission=demo_ambush [ticks=0]

func _initialize() -> void:
	var a: Dictionary = {}
	for s: String in OS.get_cmdline_user_args():
		if "=" in s:
			var kv: PackedStringArray = s.split("=", true, 1)
			a[kv[0]] = kv[1]
	var d: GameData = MissionKit.data()
	var w: SimWorld = MissionKit.world(d, str(a["mission"]))
	MissionKit.run(w, int(a.get("ticks", 0)))
	print("tick=%d players=%d map=%dx%d starts=%s" % [w.tick, w.players.size(), w.map.w, w.map.h, str(w.map.start_cells)])
	for i: int in w.mission.def.areas.size():
		var c: int = w.mission.area_center_cell(w, i)
		print("AREA %s centre=(%d,%d) r=%d" % [w.mission.def.areas[i].id, c % w.map.w, c / w.map.w, w.mission.area_radius_units(i) / 1024])
	for p: SimPlayer in w.players:
		var parts: PackedStringArray = PackedStringArray()
		for e: SimEntity in w.structures_of(p.pid):
			parts.append("%s@(%d,%d)" % [d.structures[e.def_idx].pres_recipe if false else str(d.id_of(DefEnums.Kind.STRUCTURE, e.def_idx)).replace("structure.", ""), e.x >> 10, e.y >> 10])
		for e: SimEntity in w.units_of(p.pid):
			parts.append("%s@(%d,%d)" % [str(d.id_of(DefEnums.Kind.UNIT, e.def_idx)).replace("unit.", ""), e.x >> 10, e.y >> 10])
		print("P%d %s credits=%d: %s" % [p.pid, p.name, p.credits, ", ".join(parts)])
	MissionKit.release()
	quit(0)
