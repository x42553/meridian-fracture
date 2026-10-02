extends SceneTree
## BAL2 balance-pass harness (slow, NOT part of the default test suite): ONE Hard-vs-Hard (or any level) AI match through
## AiSoakKit, with extra per-player metrics for the balance report. Prints one `BAL2_JSON {...}` line (and appends it to out=<file>).
##
##   tools/gd run --allow-errors res://tests/scenarios/bal2_match.gd -- a=roster.ae.vanilla b=roster.han.vanilla family=0 seed=5 [lv0=2 lv1=2 size=112 cap_min=16 credits=7500 ai_seed=777 out=f.jsonl]
##
## Extra per player (key "x"): first_born (tick of the first unit born with tank / aa / siege / t3 / air tags), built/lost value per unit
## def (scanned every SAMPLE ticks, so a unit born and killed inside one interval is missed), structure value lost, salvaged credits,
## harvested credits, superweapon launches and power casts of the AI.

var _args: Dictionary = {}
var _seen: Dictionary = {}  ## entity id -> [pid, def_idx, paid, kind]
var _x: Dictionary = {}  ## pid -> extra record


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			_args[kv[0]] = kv[1]
	if _args.has("bal"):
		GameData._cache = GameData.load_from_paths(GameData.BIBLE_PATH, str(_args["bal"]))  # bal=<dir>: a variant copy of game/data/balance (experiments)
	var rosters: PackedStringArray = PackedStringArray([str(_args.get("a", "roster.napc.vanilla")), str(_args.get("b", "roster.nec.vanilla"))])
	var m: Dictionary = AiSoakKit.make({
		"rosters": rosters, "levels": [_i("lv0", 2), _i("lv1", 2)], "family": _i("family", 0), "seed": _i("seed", 1), "size": _i("size", 112),
		"fog": _i("fog", 1) == 1, "credits": _i("credits", 7500), "ai_seed": _i("ai_seed", 777), "unit_cap": _i("unit_cap", 150),
		"map_params": {"start_near_water": _i("near_water", 0) == 1}, "pers_over": _neutral() if _i("neutral", 0) >= 1 else {}, "tuning": _tuning(),
	})
	var w: SimWorld = m["world"]
	for pid: int in rosters.size():
		_x[pid] = {"first_born": {}, "built_n": {}, "built_v": {}, "lost_n": {}, "lost_v": {}, "struct_lost_v": 0, "struct_lost_n": {}}
	var rec: Dictionary = AiSoakKit.play(m, _i("cap_min", 16) * 1200, _sample)
	_sample(m)
	for pid2: int in rosters.size():
		var x: Dictionary = _x[pid2]
		var pe: SimPlayerEcon = w.players[pid2].econ
		x["salvaged"] = pe.stat_salvaged
		x["harvested"] = pe.stat_harvested
		x["spent_units"] = pe.stat_spent_units
		x["spent_construction"] = pe.stat_spent_construction
		var pw: Dictionary = (m["brains"][pid2] as AiBrain).powers.summary()
		x["sw_launches"] = int(pw["sw_launches"])
		x["sw_started"] = int(pw["sw_started"])
		x["power_casts"] = int(pw["casts"])
		(rec["players"] as Array)[pid2]["x"] = x
	rec["tag"] = "bal2"
	rec["seed"] = _i("seed", 1)
	var line: String = JSON.stringify(rec)
	print("BAL2_JSON ", line)
	var out_path: String = str(_args.get("out", ""))
	if out_path != "":
		var f: FileAccess = FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()
	print("MATCH %s vs %s fam=%d seed=%d -> %s winner=%d at %d errors=%d" % [rosters[0], rosters[1], _i("family", 0), _i("seed", 1), rec["how"], rec["winner"], rec["ticks"], rec["error_count"]])
	quit(0)


## neutral=1: every AI gets the same numeric personality (the doctrine flags of the roster stay), so the result measures the roster's
## units / structures / economy modifiers and not the authored doctrine (economy weight, expansion appetite, style).
func _neutral() -> Dictionary:
	var row: Dictionary = {"aggression": 50, "tech": 50, "economy": 60, "defense_pct": 15, "harass_pct": 10, "air": 15, "naval": 10, "siege": 40,
		"infantry": 40, "micro": 50, "dispersion": 3, "retreat_hp_pct": 35, "return_hp_pct": 85, "sw_priority": 60, "expand": AiTypes.Expand.DEFENDED,
		"style": AiTypes.Style.PUSH, "attack_style": AiTypes.Style.PUSH, "style_alt": AiTypes.Style.PRONG}
	if _i("neutral", 0) >= 2:
		row["flags"] = 0  # neutral=2 also drops the doctrine flags (PRESERVE_VEHICLES, APRON_RETREAT, CAPTURE_POINTS, SALVAGE ...)
	return {0: row.duplicate(), 1: row.duplicate()}


## tune=a.b=1,c.d=0 : AI tuning overrides for every AI (ablations), e.g. tune=aix.repair=0
func _tuning() -> Dictionary:
	var out: Dictionary = {}
	if not _args.has("tune"):
		return out
	for kv: String in str(_args["tune"]).split(","):
		var p: PackedStringArray = kv.split("=")
		if p.size() == 2:
			out[p[0]] = int(p[1])
	return out


func _i(k: String, d: int) -> int:
	return int(_args[k]) if _args.has(k) else d


func _sample(m: Dictionary) -> void:
	var w: SimWorld = m["world"]
	if _i("trace", 0) == 2 and w.tick % 1200 == 0 and w.tick >= 6000:
		for pid1: int in _x:
			for u1: SimEntity in w.units_of(pid1):
				if (u1.flags & SimFlags.F_GONE) == 0 and u1.econ != null and (w.data.units[u1.def_idx].tags & DefEnums.UT_COLLECTOR) != 0:
					print("COLL t=%d p%d id=%d st=%d mode=%d field=%d last=%d cargo=%d pos=(%d,%d) hp=%d/%d bad_until=%d orders=%d" % [w.tick / 1200, pid1, u1.id, u1.econ.h_state, u1.econ.h_mode, u1.econ.h_field, u1.econ.h_last_field, u1.econ.cargo, u1.x / 1024, u1.y / 1024, u1.hp, u1.hp_max, u1.econ.h_bad_until, u1.orders.size()])
	if _i("trace", 0) == 1 and w.tick % 1200 == 0:
		for pid0: int in _x:
			var rp: Dictionary = SimMatchKit.report(w, pid0)
			var refs: int = 0
			var gens: int = 0
			for s0: SimEntity in w.structures_of(pid0):
				if (s0.flags & SimFlags.F_GONE) == 0:
					var sid: String = w.data.structures[s0.def_idx].id
					if sid.ends_with("refinery"):
						refs += 1
					elif sid.ends_with("generator"):
						gens += 1
			print("TRACE t=%d p%d cred=%d coll=%d refs=%d gens=%d structs=%d units=%d power=%s harv=%d lost=%d killed=%d" % [w.tick / 1200, pid0, rp["credits"], rp["collectors"], refs, gens, rp["structures"], rp["combat_units"], str(rp["power"]), rp["harvested"], rp["lost"], rp["killed"]])
	var alive: Dictionary = {}
	for pid: int in _x:
		var x: Dictionary = _x[pid]
		for u: SimEntity in w.units_of(pid):
			if (u.flags & SimFlags.F_GONE) != 0:
				continue
			alive[u.id] = true
			if _seen.has(u.id):
				continue
			var d: DefUnit = w.data.units[u.def_idx]
			_seen[u.id] = [pid, u.def_idx, u.paid_cost, 0]
			if (d.tags & DefEnums.UT_COMBAT) == 0 and (d.tags & DefEnums.UT_COLLECTOR) == 0:
				continue
			var did: String = d.id
			(x["built_n"] as Dictionary)[did] = int((x["built_n"] as Dictionary).get(did, 0)) + 1
			(x["built_v"] as Dictionary)[did] = int((x["built_v"] as Dictionary).get(did, 0)) + u.paid_cost
			var fb: Dictionary = x["first_born"]
			_first(fb, "tank", (d.tags & DefEnums.UT_TANK) != 0, u.born)
			_first(fb, "aa", (d.tags & DefEnums.UT_ANTI_AIR) != 0 and (d.tags & DefEnums.UT_INFANTRY) == 0, u.born)
			_first(fb, "siege", (d.tags & (DefEnums.UT_ARTILLERY | DefEnums.UT_SIEGE)) != 0, u.born)
			_first(fb, "t3", d.tier >= 3 and (d.tags & DefEnums.UT_COMBAT) != 0, u.born)
			_first(fb, "air", (d.tags & DefEnums.UT_AIRCRAFT) != 0 and (d.tags & DefEnums.UT_COMBAT) != 0, u.born)
		for s: SimEntity in w.structures_of(pid):
			if (s.flags & SimFlags.F_GONE) != 0:
				continue
			alive[s.id] = true
			if not _seen.has(s.id):
				_seen[s.id] = [pid, s.def_idx, w.data.structures[s.def_idx].cost, 1]
	var gone: Array = []
	for eid: int in _seen:
		if alive.has(eid):
			continue
		gone.append(eid)
		var r: Array = _seen[eid]
		var x2: Dictionary = _x[int(r[0])]
		if int(r[3]) == 1:
			x2["struct_lost_v"] = int(x2["struct_lost_v"]) + int(r[2])
			continue
		var d2: DefUnit = w.data.units[int(r[1])]
		if (d2.tags & DefEnums.UT_COMBAT) == 0 and (d2.tags & DefEnums.UT_COLLECTOR) == 0:
			continue
		var k: String = d2.id
		(x2["lost_n"] as Dictionary)[k] = int((x2["lost_n"] as Dictionary).get(k, 0)) + 1
		(x2["lost_v"] as Dictionary)[k] = int((x2["lost_v"] as Dictionary).get(k, 0)) + int(r[2])
	for eid2: int in gone:
		_seen.erase(eid2)


func _first(fb: Dictionary, key: String, cond: bool, tick: int) -> void:
	if cond and (not fb.has(key) or int(fb[key]) > tick):
		fb[key] = tick
