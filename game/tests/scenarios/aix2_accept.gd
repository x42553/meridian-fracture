extends SceneTree
## AIX2 acceptance (slow, NOT part of the default test suite): Hard AI vs Hard AI on the vanilla rosters of all 8 factions.
##   tools/gd run res://tests/scenarios/aix2_accept.gd -- mode=match pair=0 cap=32000      one pair (0..3): the AIs build their superweapon,
##                                                                                            fire it, cast support powers
##   tools/gd run res://tests/scenarios/aix2_accept.gd -- mode=all                           the four pairs (all 8 factions)
##   tools/gd run res://tests/scenarios/aix2_accept.gd -- mode=dispersal                     damage of every weapon with / without dispersal
##   tools/gd run res://tests/scenarios/aix2_accept.gd -- mode=det pair=1 cap=6000           determinism: the same match twice
## Args: accel=1 (default) starts with 15000 credits and sw_priority 100 so a launcher is up early (the charge time is the bible's);
## accel=0 plays the plain match; level=2 (Hard); seed=<n>; family=<0..2>.
## Output lines: AIX2_JSON {...} per match, AIX2_DISP {...} per weapon.

var PAIRS: Array = [
	["roster.napc.vanilla", "roster.nec.vanilla"], ["roster.olm.vanilla", "roster.def.vanilla"],
	["roster.pd.vanilla", "roster.han.vanilla"], ["roster.ae.vanilla", "roster.sap.vanilla"],
]
var _args: Dictionary = {}
var _errors: int = 0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			_args[kv[0]] = kv[1]
	match str(_args.get("mode", "match")):
		"team":
			_errors += _team()
		"duel":
			PAIRS.append([str(_args.get("a", "roster.def.vanilla")), str(_args.get("b", "roster.napc.vanilla"))])
			_errors += _match(PAIRS.size() - 1)
		"all":
			for i: int in PAIRS.size():
				_errors += _match(i)
		"dispersal":
			_dispersal()
		"det":
			_det()
		_:
			_errors += _match(_i("pair", 0))
	quit(1 if _errors > 0 else 0)


func _i(k: String, d: int) -> int:
	return int(_args[k]) if _args.has(k) else d


## Teams: the 8 vanilla rosters in one 4 v 4 match (napc, def, pd, ae against nec, olm, han, sap), all Hard.
func _team_opts() -> Dictionary:
	var accel: bool = _i("accel", 1) == 1
	var ros: PackedStringArray = PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla", "roster.def.vanilla", "roster.olm.vanilla",
		"roster.pd.vanilla", "roster.han.vanilla", "roster.ae.vanilla", "roster.sap.vanilla"])
	var opts: Dictionary = {
		"seed": _i("seed", 5), "rosters": ros, "levels": [_i("level", 2), _i("level", 2), _i("level", 2), _i("level", 2), _i("level", 2), _i("level", 2), _i("level", 2), _i("level", 2)],
		"family": _i("family", 0), "fog": true, "credits": 15000 if accel else 7500, "ai_seed": 777, "size": _i("size", 128),
		"teams": PackedInt32Array([1, 2, 1, 2, 1, 2, 1, 2]),
	}
	if accel:
		var po: Dictionary = {}
		for pid: int in 8:
			po[pid] = {"sw_priority": 100}
		opts["pers_over"] = po
	return opts


func _team() -> int:
	var m: Dictionary = AiSoakKit.make(_team_opts())
	return _report(m, "team", ros_for_team())


func ros_for_team() -> Array:
	return ["roster.napc.vanilla", "roster.nec.vanilla", "roster.def.vanilla", "roster.olm.vanilla", "roster.pd.vanilla", "roster.han.vanilla", "roster.ae.vanilla", "roster.sap.vanilla"]


func _make(pair: int) -> Dictionary:
	var accel: bool = _i("accel", 1) == 1
	var lv: int = _i("level", 2)
	var opts: Dictionary = {
		"seed": _i("seed", 3 + pair), "rosters": PackedStringArray(PAIRS[pair]), "levels": [lv, lv], "family": _i("family", 0),
		"fog": true, "credits": 15000 if accel else 7500, "ai_seed": 777 + pair,
	}
	if accel:
		opts["pers_over"] = {0: {"sw_priority": 100}, 1: {"sw_priority": 100}}
	return AiSoakKit.make(opts)


func _match(pair: int) -> int:
	return _report(_make(pair), "pair %d" % pair, PAIRS[pair])


func _report(m: Dictionary, tag: String, rosters: Array) -> int:
	var w: SimWorld = m["world"]
	var cap: int = _i("cap", 32000)
	var errors: PackedStringArray = m["errors"]
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, ltag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errors.append("[%d] %s: %s (tick %d)" % [lv, ltag, msg, w.tick])
	var t0: int = Time.get_ticks_usec()
	var seen: Dictionary = {}  ## pid -> casts processed
	var effects: Array = []
	var pending: Array = []
	var sw_fired: Dictionary = {}
	var launches: Array = []
	var seen_launches: int = 0
	while w.tick < cap and w.match_state == SimWorld.MATCH_RUNNING:
		AiSoakKit.step_once(m)
		if w.strategic.stat_launches > seen_launches:
			seen_launches = w.strategic.stat_launches
			var wr: SimWarning = w.strategic.warnings[w.strategic.warnings.size() - 1]
			launches.append(_launch_record(w, wr))
		for pid: int in m["brains"]:
			var b: AiBrain = m["brains"][pid]
			var log_: Array = b.powers.cast_log
			var n: int = int(seen.get(pid, 0))
			if b.powers.casts > n:
				for k: int in range(maxi(log_.size() - (b.powers.casts - n), 0), log_.size()):
					var rec: PackedInt32Array = log_[k]
					pending.append({"pid": pid, "pidx": rec[1], "x": rec[2], "y": rec[3], "tick": rec[0], "end": w.tick + 300, "vis0": _visible(w, pid, rec[1], rec[2], rec[3]),
						"vis_peak": 0, "members": 0, "hp_first": {}, "hp_last": {}, "zone_seen": false})
				seen[pid] = b.powers.casts
		var i: int = 0
		while i < pending.size():
			var p: Dictionary = pending[i]
			_observe(w, p)
			if w.tick >= int(p["end"]):
				var healed: int = 0
				for eid: Variant in (p["hp_last"] as Dictionary):
					healed += int(p["hp_last"][eid]) - int(p["hp_first"][eid])
				effects.append({"pid": p["pid"], "power": w.data.powers[int(p["pidx"])].id, "tick": p["tick"], "visible_cells_before": p["vis0"],
					"visible_cells_peak": p["vis_peak"], "zone_members_peak": p["members"], "member_hp_gain": healed, "zone_seen": p["zone_seen"]})
				pending.remove_at(i)
			else:
				i += 1
	Log.sink = old_sink
	var wall_ms: int = (Time.get_ticks_usec() - t0) / 1000
	var out: Dictionary = {"tag": tag, "rosters": rosters, "ticks": w.tick, "ended": w.match_state != SimWorld.MATCH_RUNNING,
		"wall_ms": wall_ms, "errors": Array(errors), "checksum": w.checksum(), "players": [], "effects": effects,
		"sim_activations": w.strategic.stat_activations, "sim_launches": w.strategic.stat_launches, "launches": launches}
	for pid2: int in m["brains"]:
		var b2: AiBrain = m["brains"][pid2]
		var c: AiController = (m["factory"] as AiFactory).thinker(pid2).controller
		var pw: AiPowers = b2.powers
		var sm: Dictionary = pw.summary()
		sm["pid"] = pid2
		sm["roster"] = rosters[pid2]
		sm["sw_target_cells"] = [pw.sw.last_target[0] / Fp.CELL, pw.sw.last_target[1] / Fp.CELL]
		sm["sw_angle"] = pw.sw.last_target[2]
		sm["sw_score"] = pw.sw.last_target[3]
		sm["sw_last_launch"] = pw.sw.last_launch_tick
		sm["sw_kind"] = pw.sw.kind
		sm["sw_jitter"] = pw.sw.jitter_pct
		sm["ai_us_avg"] = c.perf.total_us / maxi(c.total_ticks, 1)
		sm["ai_us_worst_think"] = c.perf.worst_us
		sm["wu_avg"] = c.total_wu / maxi(c.total_ticks, 1)
		sm["disp_us_avg"] = pw.dispersal.perf.avg_us()
		sm["disp_us_worst"] = pw.dispersal.perf.worst_us
		sm["disp_first_lag"] = pw.dispersal.first_order_lag
		sm["disp_units"] = pw.dispersal.units_ordered
		sm["disp_inside"] = pw.dispersal.units_in_footprint
		sm["trident_counters"] = pw.sw.counter_casts
		sm["eliminated"] = SimMatchKit.report(w, pid2)["eliminated"]
		sm["st_rejected"] = w.players[pid2].st_rejected
		sm["st_cmds"] = w.players[pid2].st_cmds
		sm["sw_launch_ok"] = w.strategic.stat_launches
		(out["players"] as Array).append(sm)
		sw_fired[pid2] = pw.sw.launches
	print("AIX2_JSON ", JSON.stringify(out))
	print("PAIR %s %s -> %d ticks (ended=%s) wall=%.1fs errors=%d launches=%s" % [tag, rosters, w.tick, out["ended"], float(wall_ms) / 1000.0, errors.size(), sw_fired])
	for e: String in errors.slice(0, 6):
		print("  ERR ", e)
	return errors.size()


## Enemy and own value inside the footprint of a fresh warning (what the launch is aimed at).
func _launch_record(w: SimWorld, wr: SimWarning) -> Dictionary:
	var enemy_structs: int = 0
	var enemy_units: int = 0
	var own: int = 0
	var reach: int = wr.radius + 2 * Fp.CELL
	for e: SimEntity in w.entities:
		if (e.flags & SimFlags.F_GONE) != 0 or (e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE):
			continue
		var inside: bool = false
		if wr.width > 0:
			inside = SimShape.capsule_contains(wr.x, wr.y, wr.x2, wr.y2, reach, e.x, e.y)
		else:
			inside = SimShape.circle_contains(wr.x, wr.y, reach, e.x, e.y)
		if not inside:
			continue
		var v: int = e.paid_cost if e.kind == SimEntity.Kind.UNIT else w.data.structures[e.def_idx].cost
		if e.owner == wr.owner:
			own += v
		elif e.kind == SimEntity.Kind.STRUCTURE:
			enemy_structs += v
		else:
			enemy_units += v
	return {"tick": wr.start_tick, "owner": wr.owner, "sw": w.data.superweapons[wr.src_idx].id, "x": wr.x / Fp.CELL, "y": wr.y / Fp.CELL,
		"enemy_structure_value": enemy_structs, "enemy_unit_value": enemy_units, "own_value": own}


## Cells of the power's radius around (x, y) that player pid sees right now.
func _visible(w: SimWorld, pid: int, pidx: int, x: int, y: int) -> int:
	var r: int = maxi(w.data.powers[pidx].radius, 6 * Fp.CELL)
	var cr: int = r >> Fp.CELL_SHIFT
	var cx: int = x >> Fp.CELL_SHIFT
	var cy: int = y >> Fp.CELL_SHIFT
	var n: int = 0
	for dy: int in range(-cr, cr + 1):
		for dx: int in range(-cr, cr + 1):
			if dx * dx + dy * dy <= cr * cr and w.map.in_bounds(cx + dx, cy + dy) and w.cell_visible(pid, cx + dx, cy + dy):
				n += 1
	return n


## One tick of observation of a cast: peak vision around the target, members of the power's zone and their health.
func _observe(w: SimWorld, p: Dictionary) -> void:
	var pidx: int = int(p["pidx"])
	if w.tick % 10 == 0:
		p["vis_peak"] = maxi(int(p["vis_peak"]), _visible(w, int(p["pid"]), pidx, int(p["x"]), int(p["y"])))
	for z: SimZone in w.zones.active_zones():
		if z.power_idx != pidx or z.owner_pid != int(p["pid"]):
			continue
		p["zone_seen"] = true
		p["members"] = maxi(int(p["members"]), z.n_members)
		for j: int in z.n_members:
			var e: SimEntity = w.get_entity(z.members[j])
			if e != null and (e.flags & SimFlags.F_GONE) == 0:
				if not (p["hp_first"] as Dictionary).has(e.id):
					p["hp_first"][e.id] = e.hp
				p["hp_last"][e.id] = e.hp


func _dispersal() -> void:
	var D := preload("res://tests/ai/test_ai_dispersal.gd")
	var tot_none: int = 0
	var tot_hard: int = 0
	for weapon: String in ["atlas", "perun", "helios", "horizon", "aurora", "tempest", "dragonfall"]:
		var none: Dictionary = D.run_strike(weapon, -1, false, 0, 900)
		var off: Dictionary = D.run_strike(weapon, AiTypes.Difficulty.HARD, true, 0, 900)
		var hard: Dictionary = D.run_strike(weapon, AiTypes.Difficulty.HARD, false, 0, 900)
		var med: Dictionary = D.run_strike(weapon, AiTypes.Difficulty.MEDIUM, false, 0, 900)
		var rec: Dictionary = {"weapon": weapon, "value_total": none["value0"], "lost_no_ai": none["lost"], "lost_hard_no_dodge": off["lost"],
			"lost_hard": hard["lost"], "lost_medium": med["lost"], "ordered_hard": hard.get("ordered", 0), "inside_at_impact_hard": hard["inside_at_impact"],
			"first_lag": hard.get("first_lag", -1), "errors": (hard["errors"] as PackedStringArray).size() + (none["errors"] as PackedStringArray).size()}
		tot_none += int(none["lost"])
		tot_hard += int(hard["lost"])
		_errors += int(rec["errors"])
		print("AIX2_DISP ", JSON.stringify(rec))
	print("DISPERSAL TOTAL value lost without dispersal %d, Hard with dispersal %d" % [tot_none, tot_hard])


func _det() -> void:
	var pair: int = _i("pair", 0)
	var sums: Array = []
	for run_i: int in 2:
		var m: Dictionary = _make(pair)
		var w: SimWorld = m["world"]
		var cap: int = _i("cap", 6000)
		while w.tick < cap and w.match_state == SimWorld.MATCH_RUNNING:
			AiSoakKit.step_once(m)
		sums.append([w.checksum(), (m["factory"] as AiFactory).state_hash()])
	print("DET ", sums, " identical=", sums[0] == sums[1])
	if sums[0] != sums[1]:
		_errors += 1
