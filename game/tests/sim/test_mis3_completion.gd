extends RefCounted
## MIS3 acceptance: every operation is COMPLETABLE (the scripted bot of tests/support, MissionBot = SimBot macro play steered by MissionGoals, plays the
## human slot against the real AI and the scripted waves and reaches the win trigger within the time budget) and cannot be trivially auto-won (an idle
## player loses or stalls). Slow: ~15-40 s of wall time per operation; filter with `tools/gd test mis3_completion`. More seeds and the full AI
## (driver "ai") are run by `python3 tools/py/mis3_bench.py <ids> --driver bot|ai|idle --seeds a,b,c` (that is where the measured times in the
## MIS3 report come from).

const OPS: PackedStringArray = ["op_napc", "op_nec", "op_olm", "op_def", "op_pd", "op_han", "op_ae", "op_sap"]
const BUDGET_MIN: int = 22  ## every operation is designed for 10-20 minutes; the harness gives it 22


func _play(id: String, driver: String, ai_seed: int, sim_seed: int, minutes: int) -> Dictionary:
	var d: GameData = MissionKit.data()
	var m: Dictionary = MissionRun.make(d, id, {"driver": driver, "ai_seed": ai_seed, "sim_seed": sim_seed, "events": false})
	if m.is_empty():
		return {"outcome": "invalid", "seconds": 0, "errors": ["no world"], "objectives": {}}
	var r: Dictionary = MissionRun.play(m, minutes * 60 * MissionRun.TPS)
	MissionRun.dispose(m)
	return r


## (AI seed, sim seed): the mission's own sim seed (-1) and a second one; the AI of the scripted opponents is seeded by the first.
const SEEDS: Array = [[777, -1], [1234, 1077]]


func test_a_scripted_bot_wins_every_operation_on_two_seeds(t: TestCtx) -> void:
	for id: String in OPS:
		for sd: Variant in SEEDS:
			var pair: Array = sd as Array
			var r: Dictionary = _play(id, "bot", int(pair[0]), int(pair[1]), BUDGET_MIN)
			var tag: String = "%s seed %d/%d" % [id, int(pair[0]), int(pair[1])]
			t.eq(r["outcome"], "win", "%s: the bot reaches the win trigger (%d s)" % [tag, int(r["seconds"])])
			t.ge(int(r["seconds"]), 8 * 60, "%s: not trivially short (%d s)" % [tag, int(r["seconds"])])
			t.le(int(r["seconds"]), BUDGET_MIN * 60, "%s: inside the time budget" % tag)
			t.eq((r["errors"] as Array).size(), 0, "%s: no engine warnings or errors" % tag)
			t.note("%s bot win at %d s" % [tag, int(r["seconds"])])


func test_an_idle_player_never_wins_an_operation(t: TestCtx) -> void:
	for id: String in OPS:
		var r: Dictionary = _play(id, "idle", 777, -1, 14)
		t.ne(r["outcome"], "win", "%s: an idle player does not win (%s after %d s)" % [id, str(r["outcome"]), int(r["seconds"])])
		t.eq((r["errors"] as Array).size(), 0, "%s: idle run is clean" % id)
