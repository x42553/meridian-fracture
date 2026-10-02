extends SceneTree
## `tools/gd run res://tests/scenarios/snd_check.gd`: the audio data check of audio spec G1 (`--check-audio`): loads the
## data, the asset index and the event map, bakes the sound bank over the real GameData and prints the coverage. Exit 0 when
## `SndEventMap.missing(data)` is empty and the data loaded without errors.


func _initialize() -> void:
	var store: SndDataStore = SndDataStore.new()
	store.load_all(SndConfig.DATA_DIR)
	var index: SndAssetIndex = SndAssetIndex.new()
	index.setup(SndConfig.INDEX_PATH)
	var map: SndEventMap = SndEventMap.new()
	map.build(store, index)
	var data: GameData = GameData.load_default()
	var missing: PackedStringArray = map.missing(data)
	var bank: SndSoundBank = SndSoundBank.new()
	bank.bake(data, map, store.mix)
	print("SND_CHECK events=%d profiles=%d assets=%d data_version=%d store_errors=%d map_errors=%d missing=%d" % [
		map.event_ids().size(), map.profile_ids().size(), index.assets.size(), store.data_version, store.errors.size(), map.errors.size(), missing.size()])
	print("SND_COVERAGE %s" % str(bank.coverage))
	for e: String in store.errors:
		printerr("data: " + e)
	for e2: String in map.errors:
		printerr("events: " + e2)
	for m: String in missing:
		printerr("missing: " + m)
	quit(0 if store.errors.is_empty() and map.errors.is_empty() and missing.is_empty() else 1)
