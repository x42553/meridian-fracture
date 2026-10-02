extends SceneTree
## Per-system cost of one sim tick at game scale (the profile behind the 8-player 400+ entity frame budget):
##   tools/gd run res://tests/bench/bench_sim_stages.gd -- units=60 players=8 ticks=200
## Mirrors SimWorld.step() (commands, then every stage with its stride) and times each stage; prints the total ms/tick and the stages sorted by
## average cost, plus each stage's worst tick. The state hash checkpoint (every CHECKSUM_PERIOD ticks) is listed as its own row.


func _initialize() -> void:
	var args: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			args[kv[0]] = kv[1]
	var players: int = int(args.get("players", 8))
	var units: int = int(args.get("units", 60))
	var ticks: int = int(args.get("ticks", 200))
	var all: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla", "roster.han.vanilla", "roster.def.vanilla", "roster.olm.vanilla",
		"roster.pd.vanilla", "roster.ae.vanilla", "roster.sap.vanilla"]
	var rosters: Array = []
	for i: int in players:
		rosters.append(all[i % all.size()])
	var m: Dictionary = SimMatchKit.make_match({"seed": 3, "size": 192, "rosters": rosters, "bots": true})
	var w: SimWorld = m["world"] as SimWorld
	SimMatchKit.run(m, 300)
	AppStress.spawn(w, units)
	SimMatchKit.run(m, 40)
	var sum: Dictionary = {}
	var worst: Dictionary = {}
	var samples: Dictionary = {}  # stage -> PackedFloat32Array of ms (every tick it ran)
	var bots: Array = m["bots"]
	var total_us: int = 0
	for _t: int in ticks:
		for b: SimBot in bots:
			b.think(w)
		var t_all: int = Time.get_ticks_usec()
		w.events.tick = w.tick
		var t0: int = Time.get_ticks_usec()
		w._begin_tick_moves()
		w.commands.update(w)
		w._flush_spawns()
		_acc(sum, worst, "commands+begin", Time.get_ticks_usec() - t0, samples)
		for i: int in range(1, w.stages.size()):
			var s: SimSystem = w.stages[i]
			if s.stride > 1 and (w.tick + s.stride_offset) % s.stride != 0:
				continue
			var t1: int = Time.get_ticks_usec()
			if s is SimCombatSystem and args.has("phases"):
				var cs: SimCombatSystem = s as SimCombatSystem
				var tp: int = Time.get_ticks_usec()
				cs._upkeep(w)
				SimDeath.drain_chains(w, cs)
				SimAirSortie.update_all(w, cs)
				cs.urgent_used = 0
				_acc(sum, worst, "  combat: upkeep+chains+sortie", Time.get_ticks_usec() - tp, samples)
				tp = Time.get_ticks_usec()
				SimTargeting.run_scans(w, cs)
				_acc(sum, worst, "  combat: targeting scans", Time.get_ticks_usec() - tp, samples)
				tp = Time.get_ticks_usec()
				cs.weapons.update_all(w, cs)
				_acc(sum, worst, "  combat: weapons.update_all", Time.get_ticks_usec() - tp, samples)
				tp = Time.get_ticks_usec()
				cs.proj.update(w)
				SimDamage.flush(w)
				_acc(sum, worst, "  combat: projectiles+damage", Time.get_ticks_usec() - tp, samples)
			else:
				s.update(w)
			w._flush_spawns()
			_acc(sum, worst, str(s.get_script().get_global_name()), Time.get_ticks_usec() - t1, samples)
		w.tick += 1
		w.events.tick = w.tick
		if w.tick % w._ckpt_interval == 0:
			var t2: int = Time.get_ticks_usec()
			w._record_checkpoint()
			_acc(sum, worst, "checkpoint(hash)", Time.get_ticks_usec() - t2, samples)
		total_us += Time.get_ticks_usec() - t_all
		w.events.clear()
	var rows: Array = []
	for k: String in sum.keys():
		var sm: PackedFloat32Array = samples[k] as PackedFloat32Array
		sm.sort()
		rows.append([k, float(sum[k]) / float(ticks) / 1000.0, float(worst[k]) / 1000.0, sm[int(sm.size() * 0.95)], sm[int(sm.size() * 0.99)] if sm.size() > 1 else sm[0]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as float) > (b[1] as float))
	print("BENCH_SIM_STAGES entities=%d players=%d ticks=%d avg_ms_per_tick=%.3f" % [w.entities.size(), players, ticks, float(total_us) / float(ticks) / 1000.0])
	for r: Array in rows:
		print("  %-28s avg %.3f ms/tick   p95 %.2f  p99 %.2f  worst %.2f ms" % [r[0], r[1], r[3], r[4], r[2]])
	quit()


static func _acc(sum: Dictionary, worst: Dictionary, k: String, us: int, samples: Dictionary) -> void:
	var sm: PackedFloat32Array = samples.get(k, PackedFloat32Array()) as PackedFloat32Array
	sm.append(float(us) / 1000.0)
	samples[k] = sm  # packed arrays are values: store back
	sum[k] = int(sum.get(k, 0)) + us
	worst[k] = maxi(int(worst.get(k, 0)), us)
