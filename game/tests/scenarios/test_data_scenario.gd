extends RefCounted
## data_balance 10.3 / 10.4 (scenario + determinism tests that need no SimWorld): double load, permutation
## invariance, single-change sensitivity, frozen tables. Roster-dependent scenarios (tech gating, roster matrix, research
## flow) arrive with DATA-06/07.


func _data(src: DefSources = null) -> GameData:
	return GameData.load_from_sources(src if src != null else DefTestKit.stub_sources())


## Same dictionary, keys re-inserted in a shuffled order (fixed-seed local LCG; test-only).
func _shuffled(v: Variant, seed_box: Array) -> Variant:
	if v is Dictionary:
		var keys: Array = (v as Dictionary).keys()
		for i: int in range(keys.size() - 1, 0, -1):
			seed_box[0] = (int(seed_box[0]) * 1103515245 + 12345) & 0x7FFFFFFF
			var j: int = int(seed_box[0]) % (i + 1)
			var tmp: Variant = keys[i]
			keys[i] = keys[j]
			keys[j] = tmp
		var out: Dictionary = {}
		for k: Variant in keys:
			out[k] = _shuffled((v as Dictionary)[k], seed_box)
		return out
	if v is Array:
		var arr: Array = []
		for e: Variant in v:
			arr.append(_shuffled(e, seed_box))
		return arr
	return v


func test_double_load(t: TestCtx) -> void:
	var a: GameData = _data()
	var b: GameData = _data()
	t.check(a != null and b != null, "loads")
	t.eq(a.data_hash(), b.data_hash(), "identical data_hash")
	t.eq(a.table_hashes, b.table_hashes, "identical table hashes")
	t.check(DefValidator.check_frozen(a), "frozen after load")


func test_permutation_invariance(t: TestCtx) -> void:
	var base: DefSources = DefTestKit.stub_sources()
	var box: Array = [12345]
	var shuffled: DefSources = DefSources.from_dicts(_shuffled(base.bible, box) as Dictionary, _shuffled(base.balance, box) as Dictionary)
	t.eq(_data(shuffled).data_hash(), _data(base).data_hash(), "dictionary insertion order does not change the data hash")
	t.eq(shuffled.manifest_files, base.manifest_files, "manifest order is sorted, not insertion order")
	var h_a: Dictionary = _data(base).file_hashes()
	var h_b: Dictionary = _data(shuffled).file_hashes()
	t.eq(h_a, h_b, "canonical file hashes ignore key order")
	# CRLF / whitespace mangled text hashes equal after parsing
	var text: String = FileAccess.get_file_as_string("res://data/balance/manifest.json")
	var mangled: String = text.replace("\n", "\r\n").replace("  ", "\t")
	t.eq(DefHash.hash_json(JSON.parse_string(text)), DefHash.hash_json(JSON.parse_string(mangled)), "CRLF / tabs do not change the canonical hash")


func test_single_change_sensitivity(t: TestCtx) -> void:
	var a: GameData = _data()
	var s: DefSources = DefTestKit.stub_sources()
	var m: Dictionary = (s.balance["global.json"] as Dictionary)["damage_matrix"]
	m["ap"]["medium_armor"] = int(m["ap"]["medium_armor"]) - 5
	var b: GameData = _data(s)
	t.ne(a.data_hash(), b.data_hash(), "data_hash changes")
	t.ne(a.table_hashes["global"], b.table_hashes["global"], "global table changes")
	var diff: PackedStringArray = GameData.diff_handshake(a.handshake(), b.handshake())
	t.check(diff.has("table global differs"), "diff names the table: " + str(diff))
	var sorted_diff: PackedStringArray = diff.duplicate()
	sorted_diff.sort()
	t.eq(diff, sorted_diff, "diff lines are sorted")
	var fdiff: PackedStringArray = GameData.diff_handshake(a.handshake(true), b.handshake(true))
	t.check(fdiff.has("file balance/global.json differs"), "file diff")
	t.eq(fdiff.size() - diff.size(), 1, "exactly one extra line: the changed file")


func test_frozen_defs_survive_use(t: TestCtx) -> void:
	var a: GameData = _data()
	var h: int = a.data_hash()
	var v: DefPlayerView = DefPlayerView.new(a, a.rosters[0])
	v.refresh()
	t.eq(GameData.compute_data_hash(GameData.compute_table_hashes(a)), h, "reading through a player view does not mutate defs")
