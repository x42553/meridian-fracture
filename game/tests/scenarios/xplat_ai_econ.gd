extends SceneTree
## Cross-platform determinism scenario for an AI-vs-AI match (AIB): two AiController players with the AiEconomy module set
## (build orders, placement, tech, production, composition, squads, test waves) play 4800 ticks with fog on. The world hash chain
## AND the AI state hash (all modules, both players) must be identical on macOS / linux-amd64 / linux-arm64:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_ai_econ.gd

const TICKS: int = 4800


func _initialize() -> void:
	var first: PackedStringArray = _run()
	var second: PackedStringArray = _run()
	if first != second:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE lines=%d" % first.size())
	quit(0)


func _run() -> PackedStringArray:
	var m: Dictionary = AiEconKit.make({"family": 0, "size": 96, "seed": 1, "rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]),
		"credits": 12000, "level": AiTypes.Difficulty.HARD, "fog": true, "first_wave": 2400, "wave_every": 900})
	var w: SimWorld = m["world"]
	AiEconKit.run(m, TICKS)
	var out: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=9001 %08x" % w.checksum())
	out.append("HASH tick=9004 %08x" % (m["factory"] as AiFactory).state_hash())
	out.append("HASH tick=9005 %08x" % Checksum.fnv_string(w.dump_state()))
	return out
