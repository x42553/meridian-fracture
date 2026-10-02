extends SceneTree
## Cross-platform determinism scenario for a FULL bot-vs-bot match (INT1): real data, a generated 96x96 open map,
## NAPC vs NEC with fog of war and 25000 start credits (first battles inside the window), three minutes (3600 ticks)
## of scripted bots:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_match.gd
## `HASH tick=<n> <hex>`: every checkpoint of world.checksum_log, then final checksum, event digest, dump digest.

const TICKS: int = 3600


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
	var m: Dictionary = SimMatchKit.make_match({"family": 0, "size": 96, "seed": 1, "rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]),
		"credits": 25000, "rules": {"fog": true, "unit_cap": 300}, "bot_opts": {"first_attack_tick": 1500, "wave_size": 6, "wave_growth_ticks": 1000000}})
	var w: SimWorld = m["world"]
	SimMatchKit.run(m, TICKS)
	var out: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=9001 %08x" % w.checksum())
	out.append("HASH tick=9002 %08x" % w.events.digest())
	out.append("HASH tick=9003 %08x" % Checksum.fnv_string(w.dump_state()))
	return out
