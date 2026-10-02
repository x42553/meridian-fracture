extends SceneTree
## AIB debug scenario (not part of the suite): two AiEconomy-driven AIs play; prints a status line per player every N ticks.
##   tools/gd run res://tests/scenarios/aib_match.gd -- ticks=9000 every=1200 seed=1 a=roster.napc.vanilla b=roster.nec.vanilla level=2

var _args: Dictionary = {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			_args[kv[0]] = kv[1]
	var rosters: PackedStringArray = PackedStringArray([str(_args.get("a", "roster.napc.vanilla")), str(_args.get("b", "roster.nec.vanilla"))])
	var m: Dictionary = AiEconKit.make({
		"seed": int(_args.get("seed", 1)), "rosters": rosters, "credits": int(_args.get("credits", 7500)),
		"level": int(_args.get("level", 2)), "fog": int(_args.get("fog", 0)) == 1, "family": int(_args.get("family", 0)),
		"waves": int(_args.get("waves", 1)) == 1,
	})
	var total: int = int(_args.get("ticks", 6000))
	var every: int = int(_args.get("every", 1200))
	var done: int = 0
	var worst_us: int = 0
	var ai_us: int = 0
	while done < total:
		var r: Dictionary = AiEconKit.run(m, mini(every, total - done))
		done += int(r["ticks"])
		worst_us = maxi(worst_us, int(r["ai_worst_us"]))
		ai_us += int(r["ai_us_per_tick"]) * int(r["ticks"])
		for pid: int in (m["ecos"] as Dictionary):
			print(AiEconKit.summary(m, pid))
		for e: String in r["errors"]:
			print("ERR ", e)
		if (m["world"] as SimWorld).match_state != SimWorld.MATCH_RUNNING:
			print("MATCH OVER at ", (m["world"] as SimWorld).tick)
			break
	print("AI us/tick avg %d worst think %d us; sim+ai ms/tick" % [ai_us / maxi(done, 1), worst_us])
	quit(0)
