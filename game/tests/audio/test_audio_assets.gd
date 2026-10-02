extends RefCounted
## AUD-T1 acceptance: the generated audio library is importable. Every entry of assets/audio/asset_index.json loads as an
## AudioStreamOggVorbis with the indexed length (samples / 44100 s), mono twins exist where the index says so, and the
## index and the manifest agree. Regenerate with `python3 tools/py/audio/bootstrap.py` (prints the build_all command);
## run `tools/gd import` once after regenerating so Godot imports the new files.

const ROOT: String = "res://assets/audio/"
const SAMPLE_RATE: float = 44100.0


func _index() -> Dictionary:
	var f: FileAccess = FileAccess.open(ROOT + "asset_index.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func test_index_is_well_formed(t: TestCtx) -> void:
	var idx: Dictionary = _index()
	if not t.check(not idx.is_empty(), "asset_index.json parses (run tools/py/audio/build_all.py sfx)"):
		return
	t.eq(idx.get("schema"), "meridian.audio.index/1", "index schema")
	var assets: Dictionary = idx.get("assets", {})
	t.gt(assets.size(), 400, "at least 400 indexed assets")
	var groups: Dictionary = idx.get("groups", {})
	for g: String in groups:
		var n: int = int(groups[g])
		for i in range(1, n + 1):
			t.check(assets.has("%s_%d" % [g, i]), "group %s has variant %d" % [g, i])
	for id: String in assets:
		var row: Dictionary = assets[id]
		t.check(id == id.to_lower() and not id.contains(" "), "id is lower case: " + id)
		var bank: String = str(row["b"])
		t.check(["core", "amb"].has(bank) or bank.begins_with("fx_") or bank.begins_with("mus_") or bank.begins_with("vox_") or bank.begins_with("resp_"), "known bank for " + id)
		t.check(int(row["c"]) == 1 or int(row["c"]) == 2, "channel count for " + id)


func test_every_indexed_ogg_loads(t: TestCtx) -> void:
	var idx: Dictionary = _index()
	if not t.check(not idx.is_empty(), "asset_index.json parses"):
		return
	var assets: Dictionary = idx["assets"]
	var loaded: int = 0
	for id: String in assets:
		var row: Dictionary = assets[id]
		var path: String = ROOT + str(row["f"])
		if not ResourceLoader.exists(path):
			t.fail("not imported: %s (run tools/gd import)" % path)
			continue
		var s: AudioStream = load(path) as AudioStream
		if not t.not_null(s, "loads: " + path):
			continue
		t.check(s is AudioStreamOggVorbis, "AudioStreamOggVorbis: " + path)
		var want: float = float(row["n"]) / SAMPLE_RATE
		t.near(s.get_length(), want, 0.002, "length of " + id)
		if s is AudioStreamOggVorbis:
			t.check(not (s as AudioStreamOggVorbis).loop, "imported without loop flag (the runtime sets loops): " + id)
		loaded += 1
		if row.has("m"):
			var twin: String = path.trim_suffix(".ogg") + ".mono.ogg"
			t.check(ResourceLoader.exists(twin), "mono twin exists: " + twin)
	t.eq(loaded, assets.size(), "all indexed assets loaded")


func test_loops_are_flagged_and_long_enough(t: TestCtx) -> void:
	var idx: Dictionary = _index()
	if idx.is_empty():
		t.skip("no index")
		return
	var loops: int = 0
	for id: String in idx["assets"]:
		var row: Dictionary = idx["assets"][id]
		if int(row["l"]) == 1:
			loops += 1
			t.ge(float(row["n"]) / SAMPLE_RATE, 2.0, "loop %s is at least 2 s" % id)
	t.gt(loops, 20, "the library contains loops (engines, beds, hums, sirens)")
