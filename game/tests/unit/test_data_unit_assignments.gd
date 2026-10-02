extends RefCounted
## HARD1: `global.json` `unit_assignments.<unit>.abilities` only feeds the balance tools (balance_calc, validate_balance V-ABL-05); the loader
## reads it ONLY for a sheet without its own `abilities` list. Proof that the V-ABL-05 alignment edits changed no sim input: emptying every
## assignment ability list gives the identical data hash, identical table hashes and no load error.


func test_unit_assignment_abilities_do_not_reach_the_compiled_data(t: TestCtx) -> void:
	# both sides are loaded from the same files right now (not `load_default()`, which is a per-process cache)
	var base: GameData = GameData.load_from_sources(DefSources.from_disk(GameData.BIBLE_PATH, GameData.BALANCE_DIR))
	if not t.not_null(base, "the shipped data loads"):
		return
	var src: DefSources = DefSources.from_disk(GameData.BIBLE_PATH, GameData.BALANCE_DIR)
	var glob: Dictionary = src.balance["global.json"] as Dictionary
	var ua: Dictionary = glob["unit_assignments"] as Dictionary
	var emptied: int = 0
	for uid: Variant in ua.keys():
		var e: Dictionary = ua[uid] as Dictionary
		if not (e.get("abilities", []) as Array).is_empty():
			e["abilities"] = []
			emptied += 1
	t.gt(emptied, 10, "the shipped assignments carry abilities (so the comparison is meaningful)")
	var alt: GameData = GameData.load_from_sources(src)
	if not t.not_null(alt, "the data still loads with every assignment ability list empty"):
		return
	t.eq(alt.data_hash(), base.data_hash(), "same data hash")
	t.eq(alt.table_hashes, base.table_hashes, "same table hashes")
