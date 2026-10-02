extends SceneTree
## Cross-platform determinism scenario for the core units (Fp, SimRng, Checksum, SpatialHash).
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_core.gd [-- --ticks=N]
## Every "tick" mixes the results of a fixed batch of integer-math, RNG, hashing and spatial-hash operations into
## one running Checksum; `HASH tick=<n> <hex>` is printed every 20 ticks. Identical chains on macOS arm64,
## linux/amd64 and linux/arm64 are required. The scenario also runs itself twice per process as a self-check.

const REPORT_EVERY: int = 20
const ENTITIES: int = 300


func _initialize() -> void:
	var ticks: int = 200
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			ticks = arg.substr("--ticks=".length()).to_int()
	var problems: PackedStringArray = Fp.self_test()
	if not problems.is_empty():
		printerr("Fp.self_test failed: %s" % ", ".join(problems))
		quit(1)
		return
	var first: PackedStringArray = _run(ticks)
	var second: PackedStringArray = _run(ticks)
	if first != second:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE ticks=%d lines=%d" % [ticks, first.size()])
	quit(0)


func _run(ticks: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var rng: SimRng = SimRng.new(20240517)
	var acc: Checksum = Checksum.new()
	var sh: SpatialHash = SpatialHash.new(128, 128)
	var xs: PackedInt32Array = PackedInt32Array()
	var ys: PackedInt32Array = PackedInt32Array()
	xs.resize(ENTITIES + 1)
	ys.resize(ENTITIES + 1)
	for id: int in range(1, ENTITIES + 1):
		xs[id] = rng.next_int(128 * 1024)
		ys[id] = rng.next_int(128 * 1024)
		sh.insert(id, xs[id], ys[id], rng.next_u32() & 0x7FFFF)
	var q: PackedInt32Array = PackedInt32Array()
	var buf: PackedInt32Array = PackedInt32Array()
	for tick: int in range(1, ticks + 1):
		# Fp: rounding division in all modes, exact sqrt, trig, layered modifiers
		for _i: int in 4:
			var a: int = rng.range_i(-1000000, 1000000)
			var b: int = rng.range_i(-100000, 100000)
			var c: int = rng.range_i(1, 5000) * (1 if rng.next_int(2) == 0 else -1)
			for mode: int in 5:
				acc.add64(Fp.mul_div(a, b, c, mode))
			acc.add(Fp.floor_div(a, c))
			acc.add(Fp.floor_mod(a, c))
			acc.add(Fp.ceil_div(b, c))
			acc.add(Fp.pct(a, absi(c) % 200))
		var dx: int = rng.range_i(-200000, 200000)
		var dy: int = rng.range_i(-200000, 200000)
		var ang: int = rng.next_int(4096)
		acc.add64(Fp.isqrt(rng.next_u32() * rng.next_u32()))
		acc.add(Fp.dist(dx, dy))
		acc.add(Fp.atan2(dy, dx))
		acc.add(Fp.rot_x(dx, dy, ang))
		acc.add(Fp.rot_y(dx, dy, ang))
		acc.add(Fp.step_x(ang, 300))
		acc.add(Fp.step_y(ang, 300))
		acc.add(Fp.turn_toward(ang, rng.next_int(4096), 30))
		acc.add(Fp.apply_layers(rng.range_i(100, 5000), PackedInt32Array([rng.range_i(-2000, 2000), rng.range_i(-2000, 2000)]), 60, 0))
		acc.add(Fp.seconds_to_ticks(rng.range_i(0, 100000)))
		acc.add(Fp.cps_to_units_per_tick(rng.range_i(0, 20000)))
		# SpatialHash: move some entities, remove / re-insert one, then filtered circle and rect queries
		for _i: int in 20:
			var id: int = rng.range_i(1, ENTITIES)
			xs[id] = clampi(xs[id] + rng.range_i(-900, 900), 0, 128 * 1024 - 1)
			ys[id] = clampi(ys[id] + rng.range_i(-900, 900), 0, 128 * 1024 - 1)
			sh.move(id, xs[id], ys[id])
		var victim: int = rng.range_i(1, ENTITIES)
		sh.remove(victim)
		sh.insert(victim, xs[victim], ys[victim], rng.next_u32() & 0x7FFFF)
		var need: int = rng.next_u32() & rng.next_u32() & 0x7FFFF
		var avoid: int = rng.next_u32() & rng.next_u32() & rng.next_u32() & 0x7FFFF
		sh.query_circle(rng.next_int(128 * 1024), rng.next_int(128 * 1024), rng.range_i(1000, 9000), q, need, avoid)
		acc.add_packed(q)
		sh.query_rect(xs[victim] - 3000, ys[victim] - 3000, xs[victim] + 3000, ys[victim] + 3000, q)
		acc.add_packed(q)
		sh.cell_bucket(xs[victim] >> 10, ys[victim] >> 10, q)
		acc.add_packed(q)
		# Checksum: string FNV, MD5 digests of a growing array, RNG state and shuffle
		acc.add(Checksum.fnv_string("tick %d ä€" % tick))
		buf.append(tick * 2654435761)
		buf.append(acc.h)
		acc.add(Checksum.digest32(buf))
		var deck: Array = [1, 2, 3, 4, 5, 6, 7, 8]
		rng.shuffle(deck)
		for v: int in deck:
			acc.add(v)
		rng.hash_into(buf)
		if tick % REPORT_EVERY == 0:
			out.append("HASH tick=%d %08x" % [tick, acc.value()])
	return out
