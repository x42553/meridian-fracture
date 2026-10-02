extends SceneTree
## Cross-platform determinism scenario for a bot-vs-bot match with SHIPS and AIRCRAFT (INT1): a generated 128x128 coast
## map (bays next to the starts), NAPC vs NEC, 30000 start credits, docks and airfields, 6000 ticks:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_match_navair.gd
## `HASH tick=<n> <hex>`: every checkpoint of world.checksum_log, then final checksum, event digest, dump digest.

const TICKS: int = 6000


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
	var lad: PackedStringArray = ["power", "refinery", "barracks", "factory", "dock", "airfield", "tech", "airfield", "power", "defense", "defense", "power"]
	var m: Dictionary = SimMatchKit.make_match({"family": 2, "size": 128, "seed": 1, "map_params": {"start_near_water": true}, "credits": 30000,
		"rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), "rules": {"fog": true, "unit_cap": 300},
		"bot_opts": {"ladder": lad, "air": true, "naval": true, "first_attack_tick": 3000, "wave_size": 8}})
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
