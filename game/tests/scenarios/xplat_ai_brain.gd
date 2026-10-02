extends SceneTree
## Cross-platform determinism scenario for the full AI (AIC): two Hard AiBrain players (economy, strategy, defense, waves, scouting,
## harass, hunt) play 9000 ticks with fog on. The world hash chain, the AI state hash of both players (every module and op) and
## the op counters must be identical on macOS / linux-amd64 / linux-arm64:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_ai_brain.gd

const TICKS: int = 9000


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
	var m: Dictionary = AiSoakKit.make({"family": 0, "size": 96, "seed": 1, "rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]),
		"credits": 12000, "levels": [AiTypes.Difficulty.HARD, AiTypes.Difficulty.HARD], "fog": true})
	var w: SimWorld = m["world"]
	AiSoakKit.play(m, TICKS)
	var out: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=9001 %08x" % w.checksum())
	out.append("HASH tick=9004 %08x" % (m["factory"] as AiFactory).state_hash())
	var ops: int = 0
	for pid: int in (m["brains"] as Dictionary):
		var b: AiBrain = m["brains"][pid]
		ops = ops * 31 + b.waves_launched * 7 + b.defend_ops_total * 3 + b.harass_ops_total + b.next_op_id
	out.append("HASH tick=9006 %08x" % (ops & 0xFFFFFFFF))
	out.append("HASH tick=9005 %08x" % Checksum.fnv_string(w.dump_state()))
	AiSoakKit.dispose(m)
	return out
