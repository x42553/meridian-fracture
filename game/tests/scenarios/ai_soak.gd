extends SceneTree
## AI-vs-AI soak (AIC, slow, NOT part of the default test suite): round-robin matches of the full AI (AiBrain: economy, strategy,
## defense, waves, scouting, harass, hunt) on generated maps, one JSON record per match (`AISOAK_JSON {...}` lines, optionally also
## appended to `out=<file>`), aggregated by `python3 tools/py/ai_soak_report.py <log or json-lines file>`.
##
##   tools/gd run res://tests/scenarios/ai_soak.gd -- mode=round            8 vanilla rosters, 16 matches, Medium vs Medium
##   tools/gd run res://tests/scenarios/ai_soak.gd -- mode=ladder hi=2 lo=0 n=10   Hard vs Easy (sides alternate), n matches
##   tools/gd run res://tests/scenarios/ai_soak.gd -- mode=one a=roster.napc.vanilla b=roster.nec.vanilla lv0=1 lv1=1 family=0 seed=1
##   tools/gd run res://tests/scenarios/ai_soak.gd -- mode=det              determinism: one match twice, must be identical
## Args (after `--`): list=<comma separated roster ids> (round/ladder use exactly these) tune=a.b=1,c.d=0 (tuning overrides) near_water=1 (coast maps: start positions at the shore, so docks are placeable) rosters=8|32 (round: how many rosters, in roster order of the data; 8 = the vanilla ones) level=1 cap_min=20
##   families=0,1,2 size=96 fog=1 seed=<n> out=<file> first=<i> count=<n> credits=7500 (round); lv0/lv1 (one/det); ai_seed=777.
## Round schedule: match (i, (i + d) % R) for d in 1, 3 (R rosters) => 2R matches; map family cycles through `families`.

var _args: Dictionary = {}
var _errors_total: int = 0
var _out_path: String = ""
var _seed_bump: int = 0  ## added to ai_seed per match so the seeded jitter differs between matches


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			_args[kv[0]] = kv[1]
	_out_path = str(_args.get("out", ""))
	match str(_args.get("mode", "round")):
		"ladder":
			_ladder()
		"one":
			_one()
		"det":
			_det()
		_:
			_round()
	quit(1 if _errors_total > 0 else 0)


func _i(k: String, d: int) -> int:
	return int(_args[k]) if _args.has(k) else d


## tune=path=value,path=value : tuning overrides for every AI (ablation runs), e.g. tune=aix.micro=0,aix.capture=0
func _tuning() -> Dictionary:
	var out: Dictionary = {}
	if not _args.has("tune"):
		return out
	for kv: String in str(_args["tune"]).split(","):
		var p: PackedStringArray = kv.split("=")
		if p.size() == 2:
			out[p[0]] = int(p[1])
	return out


func _families() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for s: String in str(_args.get("families", "0,1,2")).split(","):
		out.append(int(s))
	return out


func _emit(rec: Dictionary, tag: String) -> void:
	rec["tag"] = tag
	var line: String = JSON.stringify(rec)
	print("AISOAK_JSON ", line)
	_errors_total += int(rec["error_count"])
	if _out_path != "":
		var f: FileAccess = FileAccess.open(_out_path, FileAccess.READ_WRITE if FileAccess.file_exists(_out_path) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()


func _play(rosters: PackedStringArray, levels: Array, family: int, map_seed: int, tag: String) -> Dictionary:
	var m: Dictionary = AiSoakKit.make({
		"rosters": rosters, "levels": levels, "family": family, "seed": map_seed, "size": _i("size", 96), "fog": _i("fog", 1) == 1,
		"credits": _i("credits", 7500), "ai_seed": _i("ai_seed", 777) + _seed_bump, "unit_cap": _i("unit_cap", 150),
		"map_params": {"start_near_water": _i("near_water", 0) == 1}, "tuning": _tuning(),
		"pers_over": {0: {"attack_style": _i("attack_style", -1)}, 1: {"attack_style": _i("attack_style", -1)}} if _i("attack_style", -1) >= 0 else {},
	})
	var rec: Dictionary = AiSoakKit.play(m, _i("cap_min", 20) * 1200, _verbose_cb if _i("verbose", 0) == 1 else Callable())
	_emit(rec, tag)
	print("MATCH %s %s vs %s fam=%d seed=%d L%d/L%d -> %s winner=%d at %d (%.2f ms/tick) errors=%d" % [tag, rosters[0], rosters[1], family, map_seed,
		levels[0], levels[1], rec["how"], rec["winner"], rec["ticks"], rec["ms_per_tick"], rec["error_count"]])
	for p: Dictionary in rec["players"]:
		print("  p%d first=%s waves=%s ai_us=%d idle_prod=%.2f army=%d" % [p["pid"], p["first"], (p["brain"] as Dictionary)["waves"], p["ai_us_avg"], p["idle_production"], p["combat_units"]])
	for e: String in (rec["errors"] as Array).slice(0, 5):
		print("  ERR ", e)
	AiSoakKit.dispose(m)  # a long round-robin must not keep every finished world alive
	return rec


func _verbose_cb(m: Dictionary) -> void:
	var w: SimWorld = m["world"]
	if w.tick % _i("every", 1200) != 0:
		return
	for pid: int in (m["brains"] as Dictionary):
		var b: AiBrain = m["brains"][pid]
		var e: AiEconomy = b.eco()
		var pl: AiAttackPlanner = b.attack
		for o: AiOp in b.ops:
			if o is AiOpAttack:
				var c: AiContext = b.eco()._ctx
				var th: AiStrengthGroup = AiForce.enemy_group(c, o.cx, o.cy, 16 * Fp.CELL, 100)
				var my: AiStrengthGroup = AiForce.own_group(c, o.ids)
				print("   wave r_now=%d enemy(count=%d hp=%d) mine(count=%d hp=%d) wp=%d/%d dist_tgt=%d" % [(o as AiOpAttack).r_now_q8, th.count, th.hp, my.count, my.hp, (o as AiOpAttack).wp_i, (o as AiOpAttack).waypoints.size() / 2, AiForce.dist(o.cx, o.cy, o.tx, o.ty) / 1024])
			print("   op#%d kind=%d type=%d st=%d alive=%d val=%d/%s at=(%d,%d) tgt=(%d,%d)" % [o.id, (o as AiOpAttack).kind if o is AiOpAttack else -1, o.type, o.state, o.alive, o.value_now, str((o as AiOpAttack).initial_value) if o is AiOpAttack else "-", o.cx >> 10, o.cy >> 10, o.tx >> 10, o.ty >> 10])
		print("t=%d p%d ph=%d po=%d cred=%d army=%d/%d ratio=%d(need~%d) force=%d/%d why=%d waves=%d ops=%d tgt=(%d,%d) prim=%d ghosts=%d en=%d" % [w.tick, pid, b.phase, b.posture, e.credits,
			e.army_units, e.army_value, pl.last_ratio_q8, 0, pl.last_force_units, pl.last_min_units, pl.why, b.waves_launched, b.ops.size(),
			pl.last_target_x >> 10, pl.last_target_y >> 10, b.eco()._ctx.kb.primary, b.eco()._ctx.kb.ghosts.count, b.eco()._ctx.kb.enemy_units.count])


func _roster_ids() -> PackedStringArray:
	if _args.has("list"):
		return PackedStringArray(str(_args["list"]).split(","))  # list=roster.a,roster.b,... : an explicit roster ring
	var ids: PackedStringArray = SimMatchKit.data().roster_ids()
	var n: int = _i("rosters", 8)
	var out: PackedStringArray = PackedStringArray()
	if n == 8:
		for id: String in ids:
			if id.ends_with(".vanilla"):
				out.append(id)
	else:
		for id2: String in ids:
			out.append(id2)
	return out


func _round() -> void:
	var ids: PackedStringArray = _roster_ids()
	var fams: PackedInt32Array = _families()
	var lv: int = _i("level", 1)
	var idx: int = 0
	var first: int = _i("first", 0)
	var count: int = _i("count", 1000)
	for d: int in [1, 3]:
		for i: int in ids.size():
			if idx >= first and idx < first + count:
				var a: String = ids[i]
				var b: String = ids[(i + d) % ids.size()]
				_seed_bump = idx * 101
				_play(PackedStringArray([a, b]), [lv, lv], fams[idx % fams.size()], 100 + idx + _i("seed", 0), "round%d" % idx)
			idx += 1


func _ladder() -> void:
	var ids: PackedStringArray = _roster_ids()
	var fams: PackedInt32Array = _families()
	var hi: int = _i("hi", 2)
	var lo: int = _i("lo", 0)
	var n: int = _i("n", 10)
	var wins: int = 0
	var adj: int = 0
	for k: int in n:
		var a: String = ids[k % ids.size()]
		var b: String = ids[(k * 3 + 1) % ids.size()]
		var hi_first: bool = k % 2 == 0
		var lvls: Array = [hi, lo] if hi_first else [lo, hi]
		_seed_bump = k * 101
		var rec: Dictionary = _play(PackedStringArray([a, b]), lvls, fams[k % fams.size()], 300 + k + _i("seed", 0), "ladder%d" % k)
		var hi_pid: int = 0 if hi_first else 1
		if int(rec["winner"]) == hi_pid:
			wins += 1
			if bool(rec["adjudicated"]):
				adj += 1
	print("LADDER level %d beat level %d in %d of %d (%d by adjudication)" % [hi, lo, wins, n, adj])


func _one() -> void:
	var fam: int = _i("family", 0)
	_play(PackedStringArray([str(_args.get("a", "roster.napc.vanilla")), str(_args.get("b", "roster.nec.vanilla"))]), [_i("lv0", 1), _i("lv1", 1)], fam, _i("seed", 1), "one")


func _det() -> void:
	var rosters: PackedStringArray = PackedStringArray([str(_args.get("a", "roster.napc.vanilla")), str(_args.get("b", "roster.nec.vanilla"))])
	var lv: Array = [_i("lv0", 1), _i("lv1", 1)]
	var r1: Dictionary = _play(rosters, lv, _i("family", 0), _i("seed", 1), "det1")
	var r2: Dictionary = _play(rosters, lv, _i("family", 0), _i("seed", 1), "det2")
	var same: bool = r1["checksum"] == r2["checksum"] and r1["ai_hash"] == r2["ai_hash"] and r1["ticks"] == r2["ticks"]
	print("DET %s checksum %s/%s ai_hash %s/%s ticks %d/%d" % ["IDENTICAL" if same else "DIFFERENT", r1["checksum"], r2["checksum"], r1["ai_hash"], r2["ai_hash"], r1["ticks"], r2["ticks"]])
	if not same:
		_errors_total += 1
