extends SceneTree
## Cross-platform determinism scenario for the simulation kernel (sim_core SC-11).
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_sim_core.gd
## Part 1 = S-CORE-1 (orders, scatter, scuttle, kill + wreck, resign, match end; 200 steps), part 2 = a 4-player
## brawl (600 steps of seeded random commands with kills). `HASH tick=<n> <hex>` lines: every checkpoint of
## `world.checksum_log` (part 2 ticks are offset by 1000) plus the final checksum, the event digest and a digest of
## `dump_state()` (tick 9001-9003 / 9101-9103). The scenario runs itself twice per process as a self-check.

const K := preload("res://tests/support/sim_test_kit.gd")


func _initialize() -> void:
	var first: PackedStringArray = _run()
	var second: PackedStringArray = _run()
	if first != second:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE lines=%d" % first.size())
	quit(0)


func _run() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var w1: SimWorld = K.s_core_1_world()
	K.run_script(w1, 200, Callable(K, "s_core_1_script"))
	_report(out, w1, 0, 9000)
	var w2: SimWorld = K.brawl_world()
	K.brawl_run(w2, 600)
	_report(out, w2, 1000, 9100)
	return out


func _report(out: PackedStringArray, w: SimWorld, tick_offset: int, tail_base: int) -> void:
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [tick_offset + w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=%d %08x" % [tail_base + 1, w.checksum()])
	out.append("HASH tick=%d %08x" % [tail_base + 2, w.events.digest()])
	out.append("HASH tick=%d %08x" % [tail_base + 3, Checksum.fnv_string(w.dump_state())])
