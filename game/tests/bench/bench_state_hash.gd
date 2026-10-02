extends SceneTree
## Cost of the full-state checkpoint (SimStateHash.compute, every CHECKSUM_PERIOD ticks) at game scale:
##   tools/gd run res://tests/bench/bench_state_hash.gd -- units=60 players=8
## 8 players, `units` extra ground units each (AppStress), a few hundred ticks of the scripted bots, then the checksum is timed
## (whole + per part) so an optimisation can be judged against the 20-ticks-per-second budget (50 ms per tick).


func _initialize() -> void:
	var args: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			args[kv[0]] = kv[1]
	var players: int = int(args.get("players", 8))
	var units: int = int(args.get("units", 60))
	var rosters: Array = []
	var all: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla", "roster.han.vanilla", "roster.def.vanilla", "roster.olm.vanilla",
		"roster.pd.vanilla", "roster.ae.vanilla", "roster.sap.vanilla"]
	for i: int in players:
		rosters.append(all[i % all.size()])
	var m: Dictionary = SimMatchKit.make_match({"seed": 3, "size": 192, "rosters": rosters, "bots": true})
	var w: SimWorld = m["world"] as SimWorld
	SimMatchKit.run(m, 300)
	var made: int = AppStress.spawn(w, units)
	SimMatchKit.run(m, 20)
	var n: int = w.entities.size()
	var best: float = 1.0e9
	var total: float = 0.0
	for rep: int in 20:
		var t0: int = Time.get_ticks_usec()
		var cs: int = w.checksum()
		var us: float = float(Time.get_ticks_usec() - t0)
		best = minf(best, us)
		total += us
		if rep == 0:
			print("checksum ", cs)
	# per part
	var t1: int = Time.get_ticks_usec()
	var ed: PackedInt32Array = PackedInt32Array()
	var buf: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in w.entities:
		buf.resize(0)
		e.hash_into(buf)
		ed.append(Checksum.digest32(buf))
	var ent_us: float = float(Time.get_ticks_usec() - t1)
	var t2: int = Time.get_ticks_usec()
	for e: SimEntity in w.entities:
		buf.resize(0)
		e.hash_into(buf)
	var fill_us: float = float(Time.get_ticks_usec() - t2)
	var t3: int = Time.get_ticks_usec()
	for s: SimSystem in w.stages:
		buf.resize(0)
		s.hash_state(w, buf)
		Checksum.digest32(buf)
	var sys_us: float = float(Time.get_ticks_usec() - t3)
	var t4: int = Time.get_ticks_usec()
	for p: SimPlayer in w.players:
		buf.resize(0)
		p.hash_into(buf)
	var pl_us: float = float(Time.get_ticks_usec() - t4)
	var parts_us: Dictionary = {}
	for nm: String in ["view", "econ", "fx", "vis"]:
		var tp: int = Time.get_ticks_usec()
		for p: SimPlayer in w.players:
			buf.resize(0)
			match nm:
				"view":
					if p.view != null:
						p.view.checksum()
				"econ":
					if p.econ != null:
						p.econ.hash_into(buf)
				"fx":
					if p.fx != null:
						p.fx.hash_into(buf)
				"vis":
					if p.vis != null:
						p.vis.hash_into(buf)
		parts_us[nm] = snappedf(float(Time.get_ticks_usec() - tp) / 1000.0, 0.01)
	print("PLAYER_PARTS_MS ", parts_us, " p0 buf ")
	print("BENCH_STATE_HASH entities=%d spawned=%d best_ms=%.2f avg_ms=%.2f | entity loop %.2f ms (fill only %.2f ms) | stages %.2f ms | players %.2f ms | map dyn %s" % [
		n, made, best / 1000.0, total / 20000.0, ent_us / 1000.0, fill_us / 1000.0, sys_us / 1000.0, pl_us / 1000.0, "-"])
	quit()
