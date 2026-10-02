extends SceneTree
## Cross-platform determinism scenario for the movement order layer (terrain_movement TM-12 / TM-13 / TM-15):
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_move_orders.gd
## The world and script of tests/sim/test_move_determinism.gd (group orders, patrols, aircraft, eject, glide) for 450
## ticks. `HASH tick=<n> <hex>`: every checkpoint of world.checksum_log, then final checksum, event digest, dump digest.

const D := preload("res://tests/sim/test_move_determinism.gd")
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
	var w: SimWorld = D.build()
	K.run_script(w, D.STEPS, D.on_step)
	var out: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=9001 %08x" % w.checksum())
	out.append("HASH tick=9002 %08x" % w.events.digest())
	out.append("HASH tick=9003 %08x" % Checksum.fnv_string(w.dump_state()))
	return out
