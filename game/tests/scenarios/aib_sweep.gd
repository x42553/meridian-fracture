extends SceneTree
## AIB roster sweep (not part of the suite): every roster plays a match against another one with two AiEconomy AIs.
##   tools/gd run res://tests/scenarios/aib_sweep.gd -- ticks=7200 first=0 count=32 family=0 level=2

var _args: Dictionary = {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			_args[kv[0]] = kv[1]
	var ids: PackedStringArray = SimMatchKit.data().roster_ids()
	var first: int = int(_args.get("first", 0))
	var count: int = int(_args.get("count", ids.size()))
	var ticks: int = int(_args.get("ticks", 7200))
	var bad: int = 0
	var us_sum: int = 0
	var n: int = 0
	for i: int in range(first, mini(first + count, ids.size())):
		var m: Dictionary = AiEconKit.make({
			"seed": 100 + i, "rosters": PackedStringArray([ids[i], ids[(i + 8) % ids.size()]]), "credits": int(_args.get("credits", 7500)),
			"level": int(_args.get("level", 2)), "fog": int(_args.get("fog", 1)) == 1, "family": int(_args.get("family", 0)),
			"first_wave": int(_args.get("first_wave", 3600)),
		})
		var r: Dictionary = AiEconKit.run(m, ticks)
		us_sum += int(r["ai_us_per_tick"])
		n += 1
		var errs: int = (r["errors"] as PackedStringArray).size() + int(r["bad"])
		bad += errs
		print("SWEEP ", ids[i], " vs ", ids[(i + 8) % ids.size()], " errors=", errs, " ai_us=", r["ai_us_per_tick"], " worst=", r["ai_worst_us"])
		for pid: int in (m["ecos"] as Dictionary):
			print("   ", AiEconKit.summary(m, pid))
		for e: String in (r["errors"] as PackedStringArray).slice(0, 3):
			print("   ERR ", e)
	print("SWEEP_DONE errors=", bad, " avg_ai_us_per_tick=", us_sum / maxi(n, 1))
	quit(1 if bad > 0 else 0)
