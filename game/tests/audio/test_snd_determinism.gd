extends RefCounted
## Audio stays presentation-only (DR-12): it never uses the sim RNG, never writes the world, and equal inputs give equal decisions.

const C = preload("res://src/audio/snd_event_codes.gd")


func test_source_is_read_only(t: TestCtx) -> void:
	var dir: DirAccess = DirAccess.open("res://src/audio")
	var bad: PackedStringArray = PackedStringArray()
	var checked: int = 0
	for f: String in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		checked += 1
		var text: String = FileAccess.get_file_as_string("res://src/audio/" + f)
		var n: int = 0
		for line: String in text.split("\n"):
			n += 1
			var code: String = line.strip_edges()
			if code.begins_with("#") or code.begins_with("##"):
				continue
			var hash_at: int = code.find("#")
			if hash_at >= 0:
				code = code.substr(0, hash_at)
			for needle: String in ["SimRng", "world.rng", "reader.world.", "submit(", "submit_raw", "SimCommand.new"]:
				if code.contains(needle) and f != "snd_world_reader.gd":
					bad.append("%s:%d uses %s" % [f, n, needle])
			# no assignment into the world outside the reader
			if f != "snd_world_reader.gd" and (code.contains("world.tick =") or code.contains("world.events.") or code.contains("world.players[")):
				bad.append("%s:%d touches the world" % [f, n])
	t.gt(checked, 20, "audio files scanned")
	t.eq(bad.size(), 0, "no sim mutation and no SimRng in game/src/audio: %s" % str(bad))


func test_only_the_reader_touches_simworld(t: TestCtx) -> void:
	var dir: DirAccess = DirAccess.open("res://src/audio")
	var offenders: PackedStringArray = PackedStringArray()
	for f: String in dir.get_files():
		if not f.ends_with(".gd") or f == "snd_world_reader.gd":
			continue
		var text: String = FileAccess.get_file_as_string("res://src/audio/" + f)
		for line: String in text.split("\n"):
			var code: String = line.strip_edges()
			if code.begins_with("#"):
				continue
			# SimWorld may be a parameter type of the facade and the match config (the app hands the world over); calls go through the reader
			if code.contains("world.get_entity") or code.contains("world.query_") or code.contains("world.cell_visible") or code.contains("world.fog"):
				offenders.append("%s: %s" % [f, code])
	t.eq(offenders.size(), 0, "sim queries only in the reader: %s" % str(offenders.slice(0, 3)))


func test_equal_input_equal_decisions(t: TestCtx) -> void:
	var logs: Array[PackedStringArray] = []
	for run: int in 2:
		var rig: SndTestKit.Rig = SndTestKit.Rig.new()
		rig.reader.everything_visible = true
		rig.reader.rel = {0: SndWorldReader.REL_SELF}
		var inf: int = SndTestKit.game_data().unit_idx("unit.napc.rifle_squad")
		for i: int in 12:
			rig.reader.add_entity(100 + i, SimEntity.Kind.UNIT, inf, i % 2, (5 + i) * 1024, (3 + i) * 700)
		var recs: Array = []
		for i: int in 60:
			recs.append(SndTestKit.rec(C.EV_FIRE, 100 + i, (5 + i % 12) * 1024, (3 + i % 12) * 700, 100 + i % 12, i % 5, 0, -1, 0, 0))
			if i % 7 == 0:
				recs.append(SndTestKit.rec(C.EV_IMPACT, 100 + i, (10 + i % 9) * 1024, (4 + i % 5) * 1024, 0, -1, 0, 600 + i * 40, 50, 0))
		rig.reader.dtypes = {0: 2}
		for step: int in 6:
			rig.run(recs.slice(step * 10, step * 10 + 12))
			rig.clock.advance(120)
			rig.pool.update(0.12)
		logs.append(rig.bridge.decision_log.duplicate())
	t.gt(logs[0].size(), 5, "decisions were made")
	t.eq(logs[0], logs[1], "identical decision logs")
