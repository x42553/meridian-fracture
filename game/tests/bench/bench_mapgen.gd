extends SceneTree
## Map generator bench / matrix probe: `tools/gd run res://tests/bench/bench_mapgen.gd -- <family> <slots> <size> <seeds> [snw]`
## Prints per map: attempts, layout level, template, failures and the ms breakdown; then a summary line.


func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var fam: int = a[0].to_int() if a.size() > 0 else 0
	var slots: int = a[1].to_int() if a.size() > 1 else 4
	var size: int = a[2].to_int() if a.size() > 2 else 128
	var seeds: int = a[3].to_int() if a.size() > 3 else 3
	var snw: bool = a.size() > 4 and a[4] == "snw"
	var first_ok: int = 0
	var tot: int = 0
	var worst: int = 0
	for s: int in seeds:
		var cfg: Dictionary = {"family": fam, "layout_players": slots, "size": size, "seed": 1000 + 7919 * s,
			"params": {"start_near_water": snw}}
		var t0: int = Time.get_ticks_usec()
		var r: Dictionary = MapGenerator.generate_report(cfg)
		var ms: int = (Time.get_ticks_usec() - t0) / 1000
		worst = maxi(worst, ms)
		var ok1: bool = (r["attempts"] as int) == 1 and (r["layout_level"] as int) == 0 and not (r["template"] as bool)
		if ok1:
			first_ok += 1
		tot += ms
		var m: Dictionary = r["ms"] as Dictionary
		print("seed %d: att=%d lvl=%d tpl=%s total=%dms A=%d L=%d F=%d V=%d fails=%s" % [cfg["seed"], r["attempts"], r["layout_level"],
			r["template"], ms, (m.get("phase_a", 0) as int) / 1000, (m.get("layout", 0) as int) / 1000,
			(m.get("finalize", 0) as int) / 1000, (m.get("validate", 0) as int) / 1000, r["failures"]])
	print("SUMMARY fam=%d slots=%d size=%d first_try=%d/%d avg=%dms worst=%dms" % [fam, slots, size, first_ok, seeds, tot / seeds, worst])
	quit(0)
