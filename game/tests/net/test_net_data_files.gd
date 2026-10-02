extends RefCounted
## DATAFIX: terrain.json / map_gen.json are manifest files covered by the data hash and the per-file hashes of the
## lobby handshake. A modified COPY (in memory, via DefSources.deep_copy; the shared file is never touched) must change the
## data hash and make the join handshake fail naming the file.

const P := NetSession.Phase


class Opts extends RefCounted:
	var sim_version: int = 1
	var data_hash: int = 0


func _load(mutate: Callable) -> GameData:
	var src: DefSources = DefSources.from_disk(DefTestKit.BIBLE_PATH, DefTestKit.BALANCE_DIR)
	if mutate.is_valid():
		mutate.call(src)
	return GameData.load_from_sources(src)


func _hs(d: GameData) -> Callable:
	return func(with_files: bool) -> Dictionary: return d.handshake(with_files)


func test_map_files_are_in_manifest_and_file_hashes(t: TestCtx) -> void:
	var d: GameData = _load(Callable())
	if not t.not_null(d, "real data loads"):
		return
	var fh: Dictionary = d.file_hashes()
	t.check(fh.has("balance/terrain.json") and fh.has("balance/map_gen.json"), "per-file hashes: %s" % str(fh.keys().size()))
	t.check(d.table_hashes.has("map"), "table 'map' in the data hash")
	t.check(d.ext.has("map"), "compiled map tables kept in data.ext")


func test_modified_terrain_changes_hash_and_fails_handshake(t: TestCtx) -> void:
	var host: GameData = _load(Callable())
	var client: GameData = _load(func(s: DefSources) -> void:
		var td: Dictionary = s.balance["terrain.json"]
		var w: Dictionary = td["weight"]
		w["min"] = int(w["min"]) + 1)
	if not t.not_null(host, "host data") or not t.not_null(client, "modified data loads"):
		return
	t.check(host.data_hash() != client.data_hash(), "modified terrain.json changes the data hash")
	t.check(host.table_hashes["map"] != client.table_hashes["map"], "only the map table differs")
	t.eq(host.table_hashes["units"], client.table_hashes["units"], "units table unchanged")
	var diff: PackedStringArray = GameData.diff_handshake(host.handshake(true), client.handshake(true))
	t.eq(diff, PackedStringArray(["file balance/terrain.json differs", "table map differs"]), "diff names the file: %s" % str(diff))
	# the lobby join is refused with the file named
	var kit: NetSessionKit = NetSessionKit.new()
	kit.host("Host", {"data_handshake": _hs(host), "data_diff": GameData.diff_handshake, "data_hash": host.data_hash()})
	var c: NetSession = kit.join("Bob", {"data_handshake": _hs(client), "data_diff": GameData.diff_handshake, "data_hash": client.data_hash()})
	var got: Array = []
	c.join_rejected.connect(func(reason: int, info: Dictionary) -> void: got.append([reason, info]))
	kit.step(40)
	if t.eq(got.size(), 1, "one join_rejected"):
		var info: Dictionary = (got[0] as Array)[1] as Dictionary
		t.eq(int((got[0] as Array)[0]), NetProtocol.RejectReason.DATA_MISMATCH)
		var lines: PackedStringArray = info["diff_lines"] as PackedStringArray
		t.check(lines.has("file balance/terrain.json differs"), "reject names terrain.json: %s" % str(lines))
		t.check(not lines.has("file balance/global.json differs"), "no other file named")
	t.eq(c.phase, P.IDLE)
	kit.shutdown_all()
	# the launch-side config check also refuses the different data hash
	var cfg: Dictionary = (load("res://tests/net/test_net_match_config.gd") as GDScript).call("_example") as Dictionary
	(cfg["versions"] as Dictionary)["data_hash"] = host.data_hash()
	var msg: String = NetMatchConfig.validate(cfg, _opts(client.data_hash()))
	t.check(msg.contains("game data mismatch"), msg)


func test_modified_map_gen_changes_hash(t: TestCtx) -> void:
	var host: GameData = _load(Callable())
	var client: GameData = _load(func(s: DefSources) -> void:
		var gd: Dictionary = s.balance["map_gen.json"]
		(gd["layout"] as Dictionary)["start_r_step"] = int((gd["layout"] as Dictionary)["start_r_step"]) + 1)
	if not t.not_null(host, "host data") or not t.not_null(client, "modified data loads"):
		return
	t.check(host.data_hash() != client.data_hash(), "modified map_gen.json changes the data hash")
	var diff: PackedStringArray = GameData.diff_handshake(host.handshake(true), client.handshake(true))
	t.check(diff.has("file balance/map_gen.json differs"), str(diff))


func _opts(h: int) -> Opts:
	var o: Opts = Opts.new()
	o.data_hash = h
	return o
