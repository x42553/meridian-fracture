class_name DefMissionCompiler
extends DefDomainCompiler
## Brings the scripted missions (game/data/missions/<id>.json, listed in balance/manifest.json "missions") under the data
## pipeline: parsed and validated at load (DefMissionParser, rules V-MIS-*), kept as data.ext["missions"] (DefMissionTable), folded
## into the data hash as table "missions" and into the per-file hashes ("missions/<file>") of the lobby handshake and replays.
## A mission file is therefore covered exactly like a balance file: a modified copy changes the data hash.


func domain_id() -> String:
	return "missions"


func file_names() -> PackedStringArray:
	return PackedStringArray()  # the manifest key is "missions", not "files"


func compile(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var sorted_files: PackedStringArray = src.mission_files.duplicate()
	sorted_files.sort()
	if sorted_files != src.mission_files:
		rep.error("V-MIS-01", "manifest.json missions", "must be sorted ascending")
	var table: DefMissionTable = DefMissionTable.new()
	var seen: Dictionary = {}
	for f: String in sorted_files:
		if seen.has(f):
			rep.error("V-MIS-04", "manifest.json missions", "duplicate entry '%s'" % f)
			continue
		seen[f] = true
		if not f.ends_with(".json") or not DefMissionParser.id_ok(f.trim_suffix(".json")):
			rep.error("V-MIS-01", "manifest.json missions", "'%s' is not <id>.json" % f)
			continue
		if not src.missions.has(f):
			if not " ".join(rep.errors).contains("missions/" + f):  # unreadable files were already reported by the source reader
				rep.error("V-SCH-01", "manifest.json missions", "'%s' is listed but was not loaded" % f)
			continue
		var m: DefMission = DefMissionParser.parse(src.missions[f] as Dictionary, f, data, rep)
		if m != null:
			table.add(m)
	data.ext["missions"] = table


func table_hashes(data: GameData) -> Dictionary:
	var t: DefMissionTable = DefMissionTable.of(data)
	if t == null:
		return {"missions": 0}
	var h: int = DefHash.mix_int(DefHash.OFFSET, t.missions.size())
	for m: DefMission in t.missions:
		h = DefHash.hash_def(h, m)
	return {"missions": h}
