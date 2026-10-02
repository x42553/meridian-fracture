extends SceneTree
## BAL2: lists the producible combat units of the rosters given as `list=` with tier / cost / tags / layer (analysis helper, not a test).
func _initialize() -> void:
	var _args: Dictionary = {}
	for a0: String in OS.get_cmdline_user_args():
		if "=" in a0:
			var kv0: PackedStringArray = a0.split("=", true, 1)
			_args[kv0[0]] = kv0[1]
	if _args.has("bal"):
		GameData._cache = GameData.load_from_paths(GameData.BIBLE_PATH, str(_args["bal"]))  # bal=<dir>: a variant copy of game/data/balance (experiments)
	var d: GameData = SimMatchKit.data()
	var names: PackedStringArray = DefEnums.UNIT_TAG_NAMES if "UNIT_TAG_NAMES" in DefEnums else PackedStringArray()
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("list="):
			continue
		for rid: String in a.substr(5).split(","):
			var r: DefRoster = d.roster_for(rid.split(".")[1], rid.split(".")[2])
			print("== ", rid)
			for ui: int in r.producible_units:
				var u: DefUnit = r.units[ui]
				var tg: PackedStringArray = PackedStringArray()
				for b: int in 29:
					if (u.tags & (1 << b)) != 0:
						tg.append(names[b] if b < names.size() else str(b))
				var dps: float = 0.0
				var rng: int = 0
				for ws: DefWeaponSlot in u.weapons:
					dps += float(ws.damage * ws.hits_per_volley) * 1000.0 / float(maxi(ws.reload_mt, 1)) * 20.0
					rng = maxi(rng, ws.range)
				print("%s\t%s\tT%d\tc=%d\thp=%d\tspd=%d\tdps=%.0f\trng=%.1f\t%s" % [rid, u.id, u.tier, u.cost, u.health, u.speed, dps, float(rng) / 1024.0, ",".join(tg)])
	quit(0)
