extends RefCounted
## SimCommandLog (sim_core 3.8, 10.1 test_sim_command_log): flat round trip, play() reproduces the checkpoints,
## tamper detection.

const K := preload("res://tests/support/sim_test_kit.gd")


## Records the S-CORE-1 opening as commands only (no direct API calls, which a log cannot replay).
func _record(steps: int) -> Array:
	var w: SimWorld = K.s_core_1_world()
	var cl: SimCommandLog = SimCommandLog.new()
	for s: int in steps:
		match s:
			2:
				cl.submit(w, 0, SimCmd.move(PackedInt32Array([3, 4, 5, 6, 7, 8, 9]), 30 * 1024, 30 * 1024))
			5:
				cl.submit(w, 1, SimCmd.move(PackedInt32Array([13]), 50 * 1024, 50 * 1024))
				cl.submit(w, 1, SimCmd.move(PackedInt32Array([13]), 60 * 1024, 40 * 1024, SimOrder.QM_APPEND))
			8:
				cl.submit(w, 0, SimCmd.scatter(PackedInt32Array([3, 4])))
			30:
				cl.submit(w, 0, SimCmd.scuttle(PackedInt32Array([8])))
			100:
				cl.submit(w, 1, SimCmd.resign(0))
		w.step()
	cl.finish(w)
	return [w, cl]


func test_flat_round_trip(t: TestCtx) -> void:
	var r: Array = _record(130)
	var cl: SimCommandLog = r[1]
	t.eq(cl.cmds.size(), 6, "6 records")
	var flat: PackedInt32Array = cl.to_ints()
	var want: int = 1
	for c: PackedInt32Array in cl.cmds:
		want += 3 + c.size()
	t.eq(flat.size(), want, "[n, (tick, pid, len, ints...) x n]")
	t.eq(flat[0], 6, "count first")
	t.eq(flat.slice(1, 4), PackedInt32Array([2, 0, cl.cmds[0].size()]), "first record header")
	var back: SimCommandLog = SimCommandLog.from_ints(flat)
	t.not_null(back, "parses")
	t.eq([back.ticks, back.pids, back.cmds], [cl.ticks, cl.pids, cl.cmds] as Array, "round trip")
	t.eq(back.to_ints(), flat, "and back again")
	t.is_null(SimCommandLog.from_ints(PackedInt32Array()), "empty is malformed")
	t.is_null(SimCommandLog.from_ints(PackedInt32Array([2, 0, 0, 1, 5])), "truncated is malformed")
	t.is_null(SimCommandLog.from_ints(flat.slice(0, flat.size() - 1)), "one int short is malformed")


func test_play_reproduces(t: TestCtx) -> void:
	var r: Array = _record(130)
	var w: SimWorld = r[0]
	var cl: SimCommandLog = r[1]
	t.eq(cl.checkpoints, w.checksum_log, "finish() copies the checkpoints")
	var fresh: SimWorld = K.s_core_1_world()
	var res: Dictionary = cl.play(fresh, 130)
	t.check(res["ok"], "play() reproduces every checkpoint")
	t.eq(res["mismatch_tick"], -1, "no mismatch")
	t.eq(res["final"], w.checksum(), "and the final checksum")
	t.eq(fresh.dump_state(), w.dump_state(), "and the dump_state text")
	t.check(fresh.is_match_over(), "the resign ended the match")
	# the flat form replays too
	var again: Dictionary = SimCommandLog.from_ints(cl.to_ints()).play(K.s_core_1_world(), 130)
	t.eq(again["final"], w.checksum(), "a log rebuilt from ints plays identically")


func test_tamper_detection(t: TestCtx) -> void:
	var r: Array = _record(130)
	var cl: SimCommandLog = r[1]
	cl.cmds[0] = SimCmd.move(PackedInt32Array([3, 4, 5, 6, 7, 8, 9]), 30 * 1024 + 1, 30 * 1024)
	var res: Dictionary = cl.play(K.s_core_1_world(), 130)
	t.check_false(res["ok"], "a tampered first command is detected")
	t.eq(res["mismatch_tick"], 20, "at the first checkpoint after it")
	# a world built from other inputs mismatches at tick 0
	var other: Dictionary = (r[1] as SimCommandLog).play(K.s_core_1_world({"seed": 5}), 130)
	t.eq(other["mismatch_tick"], 0, "different construction inputs mismatch at the tick-0 checkpoint")
