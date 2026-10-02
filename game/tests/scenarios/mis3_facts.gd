extends SceneTree
## MIS3 dev tool: prints data facts (cost / build time / hp / speed / range) for structures, a roster's units, neutrals and powers.
##   tools/gd run res://tests/scenarios/mis3_facts.gd -- roster=roster.napc.vanilla

func _initialize() -> void:
	var a: Dictionary = {}
	for s: String in OS.get_cmdline_user_args():
		if "=" in s:
			var kv: PackedStringArray = s.split("=", true, 1)
			a[kv[0]] = kv[1]
	var d: GameData = GameData.load_default()
	if not a.has("only_units"):
		for st: DefStructure in d.structures:
			if str(a.get("roster", "")) != "" and st.faction >= 0 and not str(d.id_of(DefEnums.Kind.STRUCTURE, d.structures.find(st))).contains("." + str(a["roster"]).split(".")[1] + "."):
				continue
			print("S %s cost=%d t=%d hp=%d pw=%d fp=%dx%d br=%d sight=%d" % [d.id_of(DefEnums.Kind.STRUCTURE, d.structures.find(st)), st.cost, st.build_ticks / 20, st.health, st.power, st.fp_w, st.fp_h, st.build_radius, st.sight])
	var r: String = str(a.get("roster", ""))
	if r != "":
		for ui: int in d.units.size():
			var u: DefUnit = d.units[ui]
			var uid: String = d.id_of(DefEnums.Kind.UNIT, ui)
			if uid.begins_with("unit.shared") or uid.contains("." + r.split(".")[1] + "."):
				print("U %s T%d cost=%d t=%d hp=%d spd=%d rng=%d sight=%d pop=%d cls=%d" % [uid, u.tier, u.cost, u.build_ticks / 20, u.health, u.speed, u.max_range, u.sight, u.pop, u.unit_class])
	quit(0)
