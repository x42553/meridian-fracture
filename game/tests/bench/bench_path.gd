extends SceneTree
## Micro-benchmark of MapNavGraph / MapPathSearch (terrain_movement 9.1): `tools/gd run res://tests/bench/bench_path.gd`
## Bar (TM-05): <= 1.9 us per visited cell for the fine A* on an M-class machine. Not a test (machine dependent).
## Args after `--`: size=256 pairs=300

const Pf := preload("res://tests/fixtures/path_fixture.gd")


func _initialize() -> void:
	var size: int = 256
	var count: int = 300
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("size="):
			size = int(a.substr(5))
		elif a.begins_with("pairs="):
			count = int(a.substr(6))
	var maps: Array[Array] = [["clutter12", null], ["clutter25", null], ["clutter35", null], ["urban", null]]
	maps[0][1] = Pf.clutter(size, 12, 11)
	maps[1][1] = Pf.clutter(size, 25, 22)
	maps[2][1] = Pf.clutter(size, 35, 33)
	maps[3][1] = Pf.urban(size, 16, 4)
	for entry: Array in maps:
		var m: MapData = entry[1]
		_bench_map(str(entry[0]), m, MapTerrain.NP_WHEELED, 2, count)
		_bench_map(str(entry[0]) + "/foot", m, MapTerrain.NP_FOOT, 1, count)
	quit(0)


func _bench_map(label: String, m: MapData, np: int, sz: int, count: int) -> void:
	var t0: int = Time.get_ticks_usec()
	var g: MapNavGraph = MapNavGraph.new(m.nav, np, sz)
	g.build()
	var build_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var nodes: int = 0
	for k: int in g.nodes:
		if g.node_cnt[k] > 0:
			nodes += 1
	var srch: MapPathSearch = MapPathSearch.new(m.nav)
	var prs: PackedInt32Array = Pf.pairs(m, np, sz, count, 60, 7)
	var np_pairs: int = prs.size() / 2
	var fine_v: int = 0
	var fine_us: int = 0
	var fine_worst: int = 0
	var corr_v: int = 0
	var corr_us: int = 0
	var corr_worst: int = 0
	var auto_us: int = 0
	var auto_worst_us: int = 0
	var ratio_sum: int = 0
	var ratio_max: int = 0
	var ok: int = 0
	var none: PackedInt32Array = PackedInt32Array()
	for k: int in np_pairs:
		var s: int = prs[k * 2]
		var d: int = prs[k * 2 + 1]
		srch.force_mode = 1
		srch.begin(np, sz, s, d, 0, none)
		var t1: int = Time.get_ticks_usec()
		srch.step(1 << 30)
		var dt: int = Time.get_ticks_usec() - t1
		if srch.status != MapPathSearch.ST_DONE:
			continue
		ok += 1
		var fcost: int = srch.path_cost
		fine_v += srch.expanded
		fine_us += dt
		fine_worst = maxi(fine_worst, srch.expanded)
		srch.force_mode = 2
		srch.begin(np, sz, s, d, 0, none)
		var t2: int = Time.get_ticks_usec()
		srch.step(1 << 30)
		corr_us += Time.get_ticks_usec() - t2
		corr_v += srch.expanded
		corr_worst = maxi(corr_worst, srch.expanded)
		var r: int = srch.path_cost * 1000 / maxi(fcost, 1)
		ratio_sum += r
		ratio_max = maxi(ratio_max, r)
		srch.force_mode = 0
		srch.begin(np, sz, s, d, 0, none)
		var t3: int = Time.get_ticks_usec()
		srch.step(1 << 30)
		var dt3: int = Time.get_ticks_usec() - t3
		auto_us += dt3
		auto_worst_us = maxi(auto_worst_us, dt3)
	if ok == 0:
		print("%-14s no reachable pairs" % label)
		return
	print("%-14s graph: %d nodes, build %.1f ms | pairs %d" % [label, nodes, build_ms, ok])
	print("   fine A*  : %d visited/query mean, %d worst, %.2f us/visited, %.2f ms mean" % [
			fine_v / ok, fine_worst, float(fine_us) / float(maxi(fine_v, 1)), float(fine_us) / float(ok) / 1000.0])
	print("   corridor : %d visited/query mean, %d worst, %.2f us/visited, %.2f ms mean, cost ratio mean %.3f max %.3f" % [
			corr_v / ok, corr_worst, float(corr_us) / float(maxi(corr_v, 1)), float(corr_us) / float(ok) / 1000.0,
			float(ratio_sum) / float(ok) / 1000.0, float(ratio_max) / 1000.0])
	print("   auto     : %.2f ms mean, %.2f ms worst (incl. LOS, abstract, smoothing)" % [
			float(auto_us) / float(ok) / 1000.0, float(auto_worst_us) / 1000.0])
