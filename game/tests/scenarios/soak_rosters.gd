extends SceneTree
## INT2 SOAK (slow, NOT part of the default test suite): plays every one of the 32 rosters (8 vanilla + 24 subfactions)
## in 2-player 96x96 bot-vs-bot matches of 4 minutes of game time (4800 ticks at 20 Hz) against a rotating opponent
## on all three map families, and prints one line per match. Engine errors (Log warnings / errors / invariant
## violations) must be 0; every anomaly the diagnostics see (stuck movers, production stalls, idle rich players)
## is printed as a `NOTE` line below the match line.
##
##   tools/gd run res://tests/scenarios/soak_rosters.gd                         full matrix (32 rosters x 3 families = 96 matches)
##   tools/gd run res://tests/scenarios/soak_rosters.gd -- families=0 first=0 count=8   a slice
##   tools/gd run res://tests/scenarios/soak_rosters.gd -- stress                one 8-player 192x192 6-minute match (memory + ms/tick)
##   tools/gd run res://tests/scenarios/soak_rosters.gd -- ticks=1200 verbose     shorter matches, per-def detail
##   tools/gd run res://tests/scenarios/soak_rosters.gd -- profile [swarm=90]    the stress match again with per-stage timing (mirrors SimWorld.step)
## Args (after `--`): families=0,1,2  first=<roster idx>  count=<n>  ticks=<n>  seed=<n>  credits=<n (15000)>  noair  nonaval  noresearch  nofog  novariety
##
## Matrix: match (family f, roster i) is roster i (pid 0) vs roster (i + 8 + 5 f) % 32 (pid 1), map seed 100 + 32 f + i,
## so every roster plays pid 0 once per family and pid 1 at least once per family.
##
## Line format:
##   SOAK f=<family> <rosterA> vs <rosterB> ticks=<n> ms/tick=<avg> worst=<ms> earned=<a>/<b> built=<a>/<b> lost=<a>/<b>
##        structs=<a>/<b> errors=<n> digest=<hex>
## `digest` folds the whole checksum chain plus the final state, so two runs (or two OSes) can be diffed.
## Diagnostics: STUCK = a unit with a move / attack-move / harvest / return order that has not moved one cell in 30 s
## of game time (aggregated per def and order type); STALL = a producer that never produced although the player had the credits;
## the total number of distinct unit defs seen alive per player is printed as `types=`.

const TICKS_DEFAULT: int = 4800
const SAMPLE: int = 100  ## ticks between diagnostics samples
const STUCK_TICKS: int = 600
const CELL: int = SimConfig.CELL

var _args: Dictionary = {}
var _flags: Dictionary = {}
var _total_errors: int = 0
var _agg_stuck: Dictionary = {}  ## "def@order" -> count (all matches)
var _agg_types: Dictionary = {}  ## unit def id -> matches in which it was seen alive
var _agg_ms: float = 0.0
var _agg_ticks: int = 0
var _worst_ms: float = 0.0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			_args[kv[0]] = kv[1]
		else:
			_flags[a] = true
	if _flags.has("profile"):
		_profile()
	elif _flags.has("stress"):
		_stress()
	else:
		_soak()
	quit(1 if _total_errors > 0 else 0)


func _int_arg(k: String, dflt: int) -> int:
	return int(_args[k]) if _args.has(k) else dflt


func _soak() -> void:
	var ids: PackedStringArray = SimMatchKit.data().roster_ids()
	var fams: PackedInt32Array = PackedInt32Array([0, 1, 2])
	if _args.has("families"):
		fams = PackedInt32Array()
		for s: String in (_args["families"] as String).split(","):
			fams.append(int(s))
	var first: int = _int_arg("first", 0)
	var count: int = _int_arg("count", ids.size())
	var ticks: int = _int_arg("ticks", TICKS_DEFAULT)
	print("SOAK rosters=%d families=%s ticks=%d" % [ids.size(), fams, ticks])
	var n_match: int = 0
	var seen_rosters: Dictionary = {}
	for f: int in fams:
		for i: int in range(first, mini(first + count, ids.size())):
			var j: int = (i + 8 + 5 * f) % ids.size()
			_match(ids[i], ids[j], f, 100 + 32 * f + i + _int_arg("seed", 0), ticks)
			seen_rosters[ids[i]] = true
			seen_rosters[ids[j]] = true
			n_match += 1
	print("SOAK_SUMMARY matches=%d rosters_played=%d errors=%d avg_ms/tick=%.3f worst_tick_ms=%.2f" % [
		n_match, seen_rosters.size(), _total_errors, _agg_ms / float(maxi(_agg_ticks, 1)), _worst_ms])
	var stuck_keys: Array = _agg_stuck.keys()
	stuck_keys.sort()
	for k: Variant in stuck_keys:
		print("SOAK_STUCK_TOTAL %s x%d" % [k, _agg_stuck[k]])
	var d: GameData = SimMatchKit.data()
	var never: PackedStringArray = PackedStringArray()
	for u: DefUnit in d.units:
		if not _agg_types.has(u.id):
			never.append(u.id)
	print("SOAK_UNITS_NEVER_SEEN (%d of %d): %s" % [never.size(), d.units.size(), ", ".join(never)])
	print("SOAK_DONE")


func _opts_for(rosters: PackedStringArray, family: int, size: int, seed_v: int) -> Dictionary:
	var bo: Dictionary = {"first_attack_tick": 1500, "wave_size": 6, "wave_growth_ticks": 1000000,
		"variety": not _flags.has("novariety"), "air": not _flags.has("noair"), "naval": not _flags.has("nonaval"), "research": not _flags.has("noresearch")}
	return {"family": family, "size": size, "seed": seed_v, "rosters": rosters, "credits": _int_arg("credits", 15000),
		"rules": {"fog": not _flags.has("nofog"), "unit_cap": 300}, "opts": {"invariants_every": 400}, "bot_opts": bo}


func _match(ra: String, rb: String, family: int, seed_v: int, ticks: int) -> void:
	var errs: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errs.append("[%d] %s: %s" % [lv, tag, msg])
	var m: Dictionary = SimMatchKit.make_match(_opts_for(PackedStringArray([ra, rb]), family, 96, seed_v))
	Log.sink = old_sink
	var w: SimWorld = m["world"]
	if w == null:
		_total_errors += 1
		print("SOAK f=%d %s vs %s WORLD NOT CREATED: %s" % [family, ra, rb, errs])
		return
	var diag: Dictionary = {"anchor": {}, "stuck": {}, "seen": [{}, {}], "samples": 0, "no_coll": [0, 0]}
	var r: Dictionary = SimMatchKit.run(m, ticks, func(world: SimWorld, tick: int) -> void:
		if tick % SAMPLE == 0:
			_sample(world, tick, diag))
	errs.append_array(r["errors"] as PackedStringArray)
	var chain_digest: int = Checksum.fnv_string(str(r["chain"]))
	var digest: int = (chain_digest ^ int(r["checksum"]) ^ (Checksum.fnv_string(w.dump_state()) * 31)) & 0xFFFFFFFF
	var rp0: Dictionary = SimMatchKit.report(w, 0)
	var rp1: Dictionary = SimMatchKit.report(w, 1)
	var earn0: int = (w.players[0] as SimPlayer).st_credits_earned
	var earn1: int = (w.players[1] as SimPlayer).st_credits_earned
	var ends: String = "" if w.match_state == SimWorld.MATCH_RUNNING else " END(state=%d)" % w.match_state
	print("SOAK f=%d %s vs %s ticks=%d ms/tick=%.3f worst=%.2f@%d earned=%d/%d built=%d/%d lost=%d/%d structs=%d/%d types=%d/%d errors=%d digest=%08x%s" % [
		family, ra, rb, r["ticks"], r["ms_avg"], r["ms_max"], r["worst_tick"], earn0, earn1, rp0["built"], rp1["built"], rp0["lost"], rp1["lost"],
		rp0["structures"], rp1["structures"], (diag["seen"][0] as Dictionary).size(), (diag["seen"][1] as Dictionary).size(),
		errs.size(), digest, ends])
	_total_errors += errs.size()
	_agg_ms += float(r["ms_total"])
	_agg_ticks += int(r["ticks"])
	_worst_ms = maxf(_worst_ms, float(r["ms_max"]))
	for e: String in errs.slice(0, 8):
		print("  ERR %s" % e)
	# diagnostics
	var stuck: Dictionary = diag["stuck"]
	for k: Variant in stuck.keys():
		print("  NOTE stuck %s x%d" % [k, stuck[k]])
		_agg_stuck[k] = int(_agg_stuck.get(k, 0)) + int(stuck[k])
	for pid: int in 2:
		for did: Variant in (diag["seen"][pid] as Dictionary).keys():
			_agg_types[w.data.units[int(did)].id] = int(_agg_types.get(w.data.units[int(did)].id, 0)) + 1
		var rp: Dictionary = rp0 if pid == 0 else rp1
		if int(rp["built"]) < 8 and w.players[pid].eliminated == 0:
			print("  NOTE STALL P%d built only %d units (credits %d, structures %d)" % [pid, rp["built"], rp["credits"], rp["structures"]])
		if int(rp["harvested"]) < 500 and w.players[pid].eliminated == 0:
			print("  NOTE LOW-INCOME P%d harvested %d" % [pid, rp["harvested"]])
		if int((diag["no_coll"] as Array)[pid]) * 4 > int(diag["samples"]):
			print("  NOTE NO-COLLECTORS P%d for %d of %d samples after tick 2400" % [pid, (diag["no_coll"] as Array)[pid], diag["samples"]])
		if _flags.has("verbose"):
			var names: PackedStringArray = PackedStringArray()
			for did: Variant in (diag["seen"][pid] as Dictionary).keys():
				names.append(w.data.units[int(did)].id)
			print("  UNITS P%d: %s" % [pid, ", ".join(names)])


## Diagnostics sampler (read-only): distinct unit defs alive per player, unit stuck detection.
func _sample(w: SimWorld, tick: int, diag: Dictionary) -> void:
	var anchor: Dictionary = diag["anchor"]
	var stuck: Dictionary = diag["stuck"]
	if tick >= 2400:
		diag["samples"] = int(diag["samples"]) + 1
		for pid: int in 2:
			if w.players[pid].eliminated == 0 and SimMatchKit.report(w, pid)["collectors"] == 0:
				(diag["no_coll"] as Array)[pid] += 1
	for u: SimEntity in w.units:
		if (u.flags & SimFlags.F_GONE) != 0 or u.owner < 0 or u.owner > 1:
			continue
		(diag["seen"][u.owner] as Dictionary)[u.def_idx] = true
		if (u.flags & SimFlags.F_INSIDE) != 0 or u.orders.is_empty() or u.layer == SimEntity.Layer.AIR:
			anchor.erase(u.id)
			continue
		var head: SimOrder = u.orders[0]
		if u.econ != null and head.type == SimOrder.T_HARVEST and u.econ.h_state == SimEconConst.H_HARVEST:
			# a collector loading is stationary by design: stuck only when its cargo does not grow
			var ca: Variant = anchor.get(u.id)
			if ca == null or int(ca[3]) != 1000 + u.econ.cargo:
				anchor[u.id] = [u.x, u.y, tick, 1000 + u.econ.cargo]
			elif tick - int(ca[2]) >= STUCK_TICKS:
				var hk: String = "%s@harvest-no-progress" % w.data.units[u.def_idx].id
				stuck[hk] = int(stuck.get(hk, 0)) + 1
				anchor[u.id] = [u.x, u.y, tick, 1000 + u.econ.cargo]
			continue
		if head.type != SimOrder.T_MOVE and head.type != SimOrder.T_ATTACK_MOVE and head.type != SimOrder.T_HARVEST and head.type != SimOrder.T_RETURN_CARGO:
			anchor.erase(u.id)
			continue
		if head.type == SimOrder.T_ATTACK_MOVE and u.combat != null and (u.combat.target_id > 0 or tick - u.combat.last_fire_tick < 100):
			anchor.erase(u.id)  # fighting on the way: stationary by design
			continue
		var a: Variant = anchor.get(u.id)
		if a == null or absi(u.x - int(a[0])) + absi(u.y - int(a[1])) >= CELL or int(a[3]) != head.type:
			anchor[u.id] = [u.x, u.y, tick, head.type]
		elif tick - int(a[2]) >= STUCK_TICKS:
			var key: String = "%s@%d" % [w.data.units[u.def_idx].id, head.type]
			if not stuck.has(key):
				stuck[key] = 0
				print("  STUCK %s id=%d at cell (%d,%d) since tick %d order type %d target %d dest (%d,%d) harvest state %d" % [w.data.units[u.def_idx].id, u.id, u.x / CELL, u.y / CELL, int(a[2]), head.type, head.target_id, head.x / CELL, head.y / CELL, u.econ.h_state if u.econ != null else -1])
			stuck[key] = int(stuck[key]) + 1
			anchor[u.id] = [u.x, u.y, tick, head.type]


## `n` cheap ground combat units per player around its HQ at tick 0 (the stress starts with a crowd).
func _swarm(w: SimWorld, n: int) -> void:
	for pid: int in w.players.size():
		var roster: DefRoster = w.players[pid].roster
		var pool: Array[int] = []
		for u_idx: int in roster.producible_units:
			var ud: DefUnit = w.data.units[u_idx]
			if (ud.tags & DefEnums.UT_COMBAT) != 0 and (ud.tags & (DefEnums.UT_AIRCRAFT | DefEnums.UT_SHIP | DefEnums.UT_SUBMARINE | DefEnums.UT_AMPHIBIOUS)) == 0 and (ud.flags & DefEnums.UF_UNARMED) == 0:
				pool.append(u_idx)
		var hqs: Array[SimEntity] = w.structures_of(pid)
		if pool.is_empty() or hqs.is_empty():
			continue
		var hq: SimEntity = hqs[0]
		for i: int in n:
			var ring: int = 5 + i / 12
			var sgn: int = 1 if pid % 2 == 0 else -1
			w.spawn_unit(pool[i % pool.size()], pid, hq.x + ((i % 12) - 6) * 2 * CELL, hq.y + (ring + 3) * CELL * sgn)


## One 8-player 192x192 6-minute (7200 ticks) match with mixed rosters: ms/tick avg and worst, entity counts, memory.
func _stress_opts() -> Dictionary:
	var ros: PackedStringArray = PackedStringArray(["roster.napc.usa", "roster.nec.vanilla", "roster.ae.kongo", "roster.def.russia",
		"roster.han.china", "roster.olm.vanilla", "roster.pd.japan", "roster.sap.india"])
	var o: Dictionary = _opts_for(ros, 0, 192, _int_arg("seed", 7))
	o["credits"] = 100000
	(o["rules"] as Dictionary)["unit_cap"] = 500
	(o["rules"] as Dictionary)["victory"] = 0  # nobody is eliminated: the load stays up for the whole 6 minutes
	(o["bot_opts"] as Dictionary)["ladder"] = PackedStringArray(["power", "refinery", "barracks", "factory", "power", "barracks", "factory", "refinery", "power", "barracks", "factory",
		"tech", "airfield", "dock", "power", "barracks", "factory", "defense", "defense", "power", "defense", "defense", "tech"])
	(o["bot_opts"] as Dictionary)["interval"] = 10
	(o["rules"] as Dictionary)["fog"] = true
	(o["opts"] as Dictionary)["invariants_every"] = 0
	o["teams"] = PackedInt32Array([1, 1, 1, 1, 2, 2, 2, 2])  # 4 v 4: the load builds up instead of a free-for-all slaughter
	(o["bot_opts"] as Dictionary)["first_attack_tick"] = 4200
	(o["bot_opts"] as Dictionary)["wave_size"] = 30
	return o


func _stress() -> void:
	var ticks: int = _int_arg("ticks", 7200)
	var o: Dictionary = _stress_opts()
	var mem0: int = OS.get_static_memory_usage()
	var m: Dictionary = SimMatchKit.make_match(o)
	var w: SimWorld = m["world"]
	_swarm(w, _int_arg("swarm", 40))
	var peak: PackedInt32Array = PackedInt32Array([0, 0, 0])  # peak entities, peak units, peak memory MB
	var r: Dictionary = SimMatchKit.run(m, ticks, func(world: SimWorld, tick: int) -> void:
		if tick % 200 == 0:
			var n_units: int = 0
			var n_all: int = world.units.size() + world.structures.size()
			for u: SimEntity in world.units:
				if (u.flags & SimFlags.F_GONE) == 0:
					n_units += 1
			peak[0] = maxi(peak[0], n_all)
			peak[1] = maxi(peak[1], n_units)
			peak[2] = maxi(peak[2], int((OS.get_static_memory_usage() - mem0) / 1048576))
			if tick % 1200 == 0:
				print("STRESS t=%d units=%d entities=%d mem+%dMB" % [tick, n_units, n_all, int((OS.get_static_memory_usage() - mem0) / 1048576)]))
	print("STRESS_RESULT players=8 map=192 ticks=%d ms/tick avg=%.3f worst=%.2f peak_entities=%d peak_units=%d mem_growth_mb=%d static_mem_mb=%d errors=%d digest=%08x" % [
		r["ticks"], r["ms_avg"], r["ms_max"], peak[0], peak[1], peak[2], int(OS.get_static_memory_usage() / 1048576), (r["errors"] as PackedStringArray).size(),
		Checksum.fnv_string(str(r["chain"])) ^ int(r["checksum"])])
	for e: String in (r["errors"] as PackedStringArray).slice(0, 10):
		print("  ERR %s" % e)
	_total_errors += (r["errors"] as PackedStringArray).size()
	for pid: int in 8:
		var rp: Dictionary = SimMatchKit.report(w, pid)
		print("STRESS P%d %s built=%d lost=%d killed=%d structs=%d harvested=%d elim=%s" % [pid, w.players[pid].roster.id, rp["built"], rp["lost"], rp["killed"], rp["structures"], rp["harvested"], rp["eliminated"]])
	print("STRESS_DONE")


## The stress match stepped by hand (mirror of SimWorld.step without the invariant / checkpoint extras) with a timer around
## every pipeline stage: prints ms per tick per stage (average over the whole match) and the bots' think cost.
func _profile() -> void:
	var o: Dictionary = _stress_opts()
	var m: Dictionary = SimMatchKit.make_match(o)
	var w: SimWorld = m["world"]
	_swarm(w, _int_arg("swarm", 40))
	var ticks: int = _int_arg("ticks", 7200)
	var names: PackedStringArray = w.checksum_part_names()
	var us: PackedInt64Array = PackedInt64Array()
	us.resize(w.stages.size() + 3)
	var bots_us: int = 0
	for _i: int in ticks:
		var t0: int = Time.get_ticks_usec()
		for b: SimBot in m["bots"]:
			b.think(w)
		bots_us += Time.get_ticks_usec() - t0
		w.events.tick = w.tick
		t0 = Time.get_ticks_usec()
		w._begin_tick_moves()
		w.commands.update(w)
		w._flush_spawns()
		us[0] += Time.get_ticks_usec() - t0
		for i: int in range(1, w.stages.size()):
			var st: SimSystem = w.stages[i]
			t0 = Time.get_ticks_usec()
			if not (st.stride > 1 and (w.tick + st.stride_offset) % st.stride != 0):
				st.update(w)
				w._flush_spawns()
			us[i] += Time.get_ticks_usec() - t0
		w.tick += 1
		w.events.tick = w.tick
		if w.tick % w._ckpt_interval == 0:
			w._record_checkpoint()
	var total: int = 0
	for v: int in us:
		total += v
	print("PROFILE ticks=%d sim ms/tick=%.3f (bots %.3f ms/tick extra)" % [ticks, float(total) / 1000.0 / float(ticks), float(bots_us) / 1000.0 / float(ticks)])
	for i: int in w.stages.size():
		print("PROFILE stage %2d %-14s %.3f ms/tick" % [i, names[5 + i] if 5 + i < names.size() and i > 0 else ("commands" if i == 0 else str(i)), float(us[i]) / 1000.0 / float(ticks)])
	print("PROFILE_DONE")
