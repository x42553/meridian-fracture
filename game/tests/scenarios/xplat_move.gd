extends SceneTree
## Cross-platform determinism scenario for the movement domain (terrain_movement TM-10 / TM-11).
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_move.gd
## 40 mixed units (foot / wheeled / tracked heavy) on a 96x96 map with 12 % cliff clutter receive seeded random goals
## (go_to / go_near / stop / turn_to) every 25 ticks for 500 ticks. `HASH tick=<n> <hex>` lines: every checkpoint of
## `world.checksum_log`, then the final checksum, the event digest and a digest of `dump_state()` (tick 9001-9003).
## The scenario runs itself twice per process as a self-check.

const M := preload("res://tests/support/move_test_kit.gd")
const K := preload("res://tests/support/sim_test_kit.gd")
const C: int = 1024


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
	var m: MapData = M.clutter_map(96, 12, 3)
	var w: SimWorld = M.world(m, null, null, 4)
	var rng: SimRng = SimRng.new(99)
	var ids: PackedStringArray = [DefTestKit.U_RIFLEMAN, DefTestKit.U_TANK, DefTestKit.U_COLLECTOR, DefTestKit.U_MCV]
	var spawned: int = 0
	var guard: int = 0
	while spawned < 40 and guard < 4000:
		guard += 1
		var cx: int = 8 + rng.next_int(80)
		var cy: int = 8 + rng.next_int(80)
		if m.nav.clear_at(MapTerrain.NP_TRACKED, cy * 96 + cx) < 2:
			continue
		M.spawn(w, ids[spawned % 4], cx, cy, spawned % 4)
		spawned += 1
	K.run_script(w, 500, _script)
	var out: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=9001 %08x" % w.checksum())
	out.append("HASH tick=9002 %08x" % w.events.digest())
	out.append("HASH tick=9003 %08x" % Checksum.fnv_string(w.dump_state()))
	return out


func _script(w: SimWorld, s: int) -> void:
	if s % 25 != 0:
		return
	var rng: SimRng = SimRng.new(1000 + s)
	for e: SimEntity in w.units:
		if e.move == null or rng.next_int(3) == 0:
			continue
		var cx: int = 6 + rng.next_int(84)
		var cy: int = 6 + rng.next_int(84)
		match rng.next_int(5):
			0:
				SimMovement.go_near(w, e, cx * C + 512, cy * C + 512, 3 * C)
			1:
				SimMovement.stop(w, e)
			2:
				SimMovement.turn_to(w, e, rng.next_int(4096))
			_:
				SimMovement.go_to(w, e, cx * C + 512, cy * C + 512)
