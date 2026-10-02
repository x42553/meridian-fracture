extends SceneTree
## Micro-benchmark for the core units: `tools/gd run res://tests/bench/bench_sim_core.gd`.
## Reference (sim_core 9, M5 Max): query_circle 6.9 us at r = 4 cells, 15.4 us at r = 8 cells on a dense
## cluster; the acceptance bar is "within 2x". Not a test (timings are machine dependent).


func _initialize() -> void:
	var rng: SimRng = SimRng.new(1)
	var h: SpatialHash = SpatialHash.new(96, 96)
	for id: int in range(1, 1201):
		if id <= 800:
			h.insert(id, 30 * 1024 + rng.next_int(30 * 1024), 30 * 1024 + rng.next_int(30 * 1024), 33)
		else:
			h.insert(id, rng.next_int(96 * 1024), rng.next_int(96 * 1024), 33)
	var out: PackedInt32Array = PackedInt32Array()
	for cells: int in [4, 8]:
		var n: int = 20000
		var t0: int = Time.get_ticks_usec()
		var total: int = 0
		for i: int in n:
			total += h.query_circle(40 * 1024 + (i & 1023), 40 * 1024 + ((i * 7) & 1023), cells * 1024, out, 32, 0)
		var us: float = float(Time.get_ticks_usec() - t0) / float(n)
		print("SpatialHash.query_circle r=%d cells: %.2f us/query (avg hits %d)" % [cells, us, total / n])
	var t1: int = Time.get_ticks_usec()
	var acc: int = 0
	for i: int in 200000:
		acc += Fp.isqrt(i * 1000003 + 12345)
		acc += Fp.atan2(i & 1023, (i * 3) & 1023)
	print("Fp.isqrt+atan2: %.3f us/pair (acc %d)" % [float(Time.get_ticks_usec() - t1) / 200000.0, acc])
	var t2: int = Time.get_ticks_usec()
	var buf: PackedInt32Array = PackedInt32Array()
	buf.resize(4000)
	for i: int in 2000:
		buf[i] = i * 31
	for _i: int in 2000:
		acc += Checksum.digest32(buf)
	print("Checksum.digest32(4000 ints): %.2f us" % (float(Time.get_ticks_usec() - t2) / 2000.0))
	quit(0)
