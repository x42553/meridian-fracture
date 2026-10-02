extends SceneTree
## INT2 cross-platform determinism for a SOAK SUBSET: three full bot-vs-bot matches (fog on, variety bots, air / naval /
## research on) on all three map families, each with a different roster pair, checked on macOS / linux-amd64 / linux-arm64:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_soak.gd [-- ticks=2400]
## `HASH tick=<n> <hex>` lines: every checkpoint of every match's world.checksum_log (tick numbers are offset by
## 100000 * match number so the chains concatenate), then per match the final checksum (9001), event digest (9002) and state dump digest (9003).
## The scenario also runs every match twice in the process and fails on any difference (double-run check).

const MATCHES: Array = [
	{"family": 0, "seed": 101, "rosters": ["roster.ae.kongo", "roster.han.cambodia"]},
	{"family": 1, "seed": 133, "rosters": ["roster.def.russia", "roster.napc.usa"]},
	{"family": 2, "seed": 165, "rosters": ["roster.pd.japan", "roster.sap.india"]},
]


func _initialize() -> void:
	var ticks: int = 2400
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("ticks="):
			ticks = int(a.substr(6))
	var out: PackedStringArray = PackedStringArray()
	for mi: int in MATCHES.size():
		var first: PackedStringArray = _run(mi, ticks)
		var second: PackedStringArray = _run(mi, ticks)
		if first != second:
			printerr("SELFCHECK FAILED: match %d differs between two runs in one process" % mi)
			quit(1)
			return
		out.append_array(first)
	for line: String in out:
		print(line)
	print("SCENARIO_DONE lines=%d" % out.size())
	quit(0)


func _run(mi: int, ticks: int) -> PackedStringArray:
	var md: Dictionary = MATCHES[mi]
	var m: Dictionary = SimMatchKit.make_match({"family": int(md["family"]), "size": 96, "seed": int(md["seed"]), "rosters": PackedStringArray(md["rosters"]), "credits": 15000,
		"rules": {"fog": true, "unit_cap": 300}, "opts": {"invariants_every": 400},
		"bot_opts": {"first_attack_tick": 1500, "wave_size": 6, "wave_growth_ticks": 1000000, "variety": true, "air": true, "naval": true, "research": true}})
	var w: SimWorld = m["world"]
	var r: Dictionary = SimMatchKit.run(m, ticks)
	var out: PackedStringArray = PackedStringArray()
	var base: int = 100000 * (mi + 1)
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [base + int(w.checksum_log[i]), w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=%d %08x" % [base + 9001, w.checksum()])
	out.append("HASH tick=%d %08x" % [base + 9002, w.events.digest()])
	out.append("HASH tick=%d %08x" % [base + 9003, Checksum.fnv_string(w.dump_state())])
	if not (r["errors"] as PackedStringArray).is_empty():
		printerr("match %d engine errors: %s" % [mi, r["errors"]])
	return out
