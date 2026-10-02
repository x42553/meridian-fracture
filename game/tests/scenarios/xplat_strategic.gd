extends SceneTree
## Cross-platform determinism scenario of the strategic domain (task EC3B):
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_strategic.gd
## Eight players (all factions) on the REAL data, 4 v 4: every superweapon (Trident domes vs Atlas / Perun, Aurora cancelling
## the Horizon warning, Helios, Tempest, Dragonfall) and every roster's three support powers, see tests/support/strat_scenario.gd.
## `HASH tick=<n> <hex>`: every world checkpoint plus the final checksum, the event digest and a digest of dump_state().
## Self-check: two runs in one process must agree.


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
	var w: SimWorld = StratScenario.build()
	for s: int in StratScenario.TICKS:
		StratScenario.script(w, s)
		w.step()
	var out: PackedStringArray = PackedStringArray()
	out.append("INFO warnings=%d sched=%d entities=%d" % [w.strategic.warnings.size(), w.strategic.sched.size(), w.entities.size()])
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=%d %08x" % [9001, w.checksum()])
	out.append("HASH tick=%d %08x" % [9002, w.events.digest()])
	out.append("HASH tick=%d %08x" % [9003, Checksum.fnv_string(w.dump_state())])
	return out
