extends SceneTree
## Cross-platform determinism scenario of the zones / summons / power glue (task AB3):
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_ab3.gd
## Six players on the REAL balance data (see tests/support/ab3_kit.gd): smoke, cover, sensor puck, decoys, Trident domes,
## repair stations, global-effect windows, marks and shell barrages, a Tempest swarm, Dragonfall engines, the Lagos drone,
## Horizon debris, Aurora, Helios, Atlas, all in one fight. `HASH tick=<n> <hex>`: every world checkpoint plus the final
## checksum, the event digest and a digest of dump_state(). Self-check: two runs in one process must agree.


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
	var w: SimWorld = Ab3Kit.build()
	for s: int in Ab3Kit.TICKS:
		Ab3Kit.script(w, s)
		w.step()
	var out: PackedStringArray = PackedStringArray()
	var cov: Dictionary = Ab3Kit.coverage(w)
	out.append("INFO zones=%d ended=%d summoned=%d expired=%d fx=%d fire=%d" % [int(cov.get(SimZoneConsts.EV_ZONE_SPAWNED, 0)), int(cov.get(SimZoneConsts.EV_ZONE_ENDED, 0)),
		int(cov.get(SimZoneConsts.EV_SUMMONED, 0)), int(cov.get(SimZoneConsts.EV_SUMMON_EXPIRED, 0)), int(cov.get(238, 0)), int(cov.get(200, 0))])
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=%d %08x" % [9001, w.checksum()])
	out.append("HASH tick=%d %08x" % [9002, w.events.digest()])
	out.append("HASH tick=%d %08x" % [9003, Checksum.fnv_string(w.dump_state())])
	out.append("HASH tick=%d %08x" % [9004, w.abilities.timer_digest])
	return out
