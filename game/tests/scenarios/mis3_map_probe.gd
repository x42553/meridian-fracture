extends SceneTree
## MIS3 map probe (dev tool, not part of the suite): generates the map of a mission-style map config with the real MapGenerator, prints the
## quality verdict (attempts / safe-template fallback / validator failures), the start cells, resource fields, neutrals and an ASCII picture.
##   tools/gd run res://tests/scenarios/mis3_map_probe.gd -- family=0 size=96 seed=7 players=2 [water_pct=.. density=.. resources=.. neutrals=.. biome=.. start_near_water=1] [ascii=2]
##   tools/gd run res://tests/scenarios/mis3_map_probe.gd -- mission=<id> [ascii=2]      (map of a shipped mission)
## ascii = down-sampling factor (default 2, 0 = no picture). Legend: ~ deep, - shallow, : ford/beach/marsh, . grass/dirt/sand, f forest, = road/pavement, # urban, r rock/rubble, ^ cliff, M mountain,
## digits = start cell (player start index), $ = resource field centre, n = neutral structure.

func _initialize() -> void:
	var a: Dictionary = {}
	for s: String in OS.get_cmdline_user_args():
		if "=" in s:
			var kv: PackedStringArray = s.split("=", true, 1)
			a[kv[0]] = kv[1]
	var cfg: Dictionary = {}
	if a.has("mission"):
		var d: GameData = GameData.load_default()
		var mc: Dictionary = SimMissionSetup.build_config(d, str(a["mission"]))
		cfg = mc["map"]
	else:
		var params: Dictionary = {}
		for k: String in ["water_pct", "density", "resources", "neutrals", "biome", "start_near_water"]:
			if a.has(k):
				params[k] = int(a[k])
		cfg = {"family": int(a.get("family", 0)), "size": int(a.get("size", 96)), "seed": int(a.get("seed", 1)),
			"layout_players": int(a.get("players", 2)), "params": params}
	if a.has("scan"):
		var first: int = int(cfg["seed"])
		for sd: int in int(a["scan"]):
			var c2: Dictionary = cfg.duplicate(true)
			c2["seed"] = first + sd
			var r2: Dictionary = MapGenerator.generate_report(c2)
			var m2: MapData = r2["map"]
			var f2: PackedStringArray = MapGenValidate.validate(m2)
			var me: Dictionary = MapGenValidate.metrics(m2)
			print("SCAN seed=%d attempts=%d template=%s fails=%d route=%s exits=%s fair=%s docks=%s starts=%s" % [first + sd, int(r2["attempts"]), str(r2["template"]), f2.size(), str(me.get("route_pct")), str(me.get("exits_per_start")), str(me.get("fairness_spread_permille")), str(me.get("dock_sites")), str(m2.start_cells)])
		quit(0)
		return
	var rep: Dictionary = MapGenerator.generate_report(cfg)
	var m: MapData = rep["map"]
	var fails: PackedStringArray = MapGenValidate.validate(m)
	print("MAP cfg=%s attempts=%d level=%d template=%s gen_failures=%s validate=%s" % [JSON.stringify(cfg), int(rep["attempts"]), int(rep["layout_level"]),
		str(rep["template"]), str(rep["failures"]), str(fails)])
	var met: Dictionary = MapGenValidate.metrics(m)
	print("METRICS " + JSON.stringify(met))
	var sc: PackedInt32Array = m.start_cells
	var parts: PackedStringArray = PackedStringArray()
	for i: int in sc.size() / 2:
		parts.append("%d:(%d,%d)" % [i, sc[i * 2], sc[i * 2 + 1]])
	print("STARTS %s  size=%dx%d" % [" ".join(parts), m.w, m.h])
	var nf: int = m.fields.size() / MapData.FIELD_STRIDE
	for i: int in nf:
		var o: int = i * MapData.FIELD_STRIDE
		var c: int = m.fields[o + 1]
		print("FIELD id=%d at (%d,%d) r=%d cells=%d total=%d kind=%d klass=%d owner_start=%d" % [m.fields[o], c % m.w, c / m.w, m.fields[o + 2], m.fields[o + 3], m.fields[o + 4], m.fields[o + 5], m.fields[o + 8], m.fields[o + 9]])
	var nn: int = m.neutrals.size() / MapData.NEUTRAL_STRIDE
	for i: int in nn:
		var o: int = i * MapData.NEUTRAL_STRIDE
		var c: int = m.neutrals[o + 1]
		print("NEUTRAL kind=%d (%d,%d) %dx%d" % [m.neutrals[o], c % m.w, c / m.w, m.neutrals[o + 2], m.neutrals[o + 3]])
	var f: int = int(a.get("ascii", 2))
	if f > 0:
		for y: int in range(0, m.h, f):
			var line: String = ""
			for x: int in range(0, m.w, f):
				var ch: String = _glyph(m.terrain[y * m.w + x])
				for i: int in sc.size() / 2:
					if absi(sc[i * 2] - x) < f and absi(sc[i * 2 + 1] - y) < f:
						ch = str(i)
				for i: int in nf:
					var c2: int = m.fields[i * MapData.FIELD_STRIDE + 1]
					if absi(c2 % m.w - x) < f and absi(c2 / m.w - y) < f:
						ch = "$"
				for i: int in nn:
					var c3: int = m.neutrals[i * MapData.NEUTRAL_STRIDE + 1]
					if absi(c3 % m.w - x) < f and absi(c3 / m.w - y) < f:
						ch = "n"
				line += ch
			print("%3d %s" % [y, line])
	quit(0)


func _glyph(t: int) -> String:
	match t:
		MapTerrain.T_DEEP:
			return "~"
		MapTerrain.T_SHALLOW:
			return "-"
		MapTerrain.T_FORD, MapTerrain.T_BEACH, MapTerrain.T_MARSH:
			return ":"
		MapTerrain.T_FOREST:
			return "f"
		MapTerrain.T_ROAD, MapTerrain.T_PAVEMENT:
			return "="
		MapTerrain.T_URBAN:
			return "#"
		MapTerrain.T_ROCK, MapTerrain.T_RUBBLE:
			return "r"
		MapTerrain.T_CLIFF:
			return "^"
		MapTerrain.T_MOUNTAIN:
			return "M"
	return "."
