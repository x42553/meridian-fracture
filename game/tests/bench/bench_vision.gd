extends SceneTree
## Vision calibration gate (abilities 9.3): (1) microbenchmark of SimCoverGrid.move_disc for R = 8; (2) stage 10 with
## 8 players x 150 units (+ 60 structures each) on a 256x256 map, 40 % of the units moving.
## Run: tools/gd run res://tests/bench/bench_vision.gd   (prints ns per cell write, us per step, ms per tick)
## Decision rule (9.3): a move_disc step of R = 8 above 12 us makes the default preset Low (budget 64, stride 3).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const TICKS: int = 400
const WARMUP: int = 60


## Stage 10 with a stopwatch (the clock never feeds the simulation).
class TimedVision:
	extends SimVisionSystem
	var usec: int = 0
	var worst: int = 0
	var samples: int = 0
	var updates: int = 0

	func update(world: SimWorld) -> void:
		var t0: int = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch, never read by the sim
		var u0: int = stat_updates
		super.update(world)
		var dt: int = Time.get_ticks_usec() - t0  # lint-allow: L003 benchmark stopwatch
		if world.tick >= WARMUP:
			usec += dt
			samples += 1
			updates += stat_updates - u0
			worst = maxi(worst, dt)


## Stage 7 with a stopwatch.
class TimedAbil:
	extends SimAbilitySystem
	var usec: int = 0

	func update(world: SimWorld) -> void:
		var t0: int = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
		super.update(world)
		if world.tick >= WARMUP:
			usec += Time.get_ticks_usec() - t0  # lint-allow: L003 benchmark stopwatch


func _init() -> void:
	_micro()
	_stage(OS.get_cmdline_user_args().has("low"))
	quit(0)


func _micro() -> void:
	var disc: SimDisc = SimDisc.new()
	var g: SimCoverGrid = SimCoverGrid.new(256, 256, disc)
	var sink: SimCoverGrid.Sink = SimCoverGrid.Sink.new()
	# a dense blob: 200 discs around the test disc so transitions are as rare as in a real march
	for i: int in 200:
		g.stamp_disc(100 + (i % 14) * 3, 100 + (i / 14) * 3, 8, 1, null)
	var n: int = 20000
	var cx: int = 110
	var cy: int = 110
	g.stamp_disc(cx, cy, 8, 1, null)
	var t0: int = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
	var w0: int = g.stat_cells_written
	for i: int in n:
		var nx: int = cx + (1 if (i & 1) == 0 else -1)
		g.move_disc(cx, cy, nx, cy, 8, sink)
		cx = nx
		if sink.cells.size() > 4096:
			sink.clear()
	var t1: int = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
	var writes: int = g.stat_cells_written - w0
	print("move_disc R=8 x-step (with sink, dense): %.2f us/step, %d cell writes/step, %.1f ns/write" % [
		float(t1 - t0) / n, writes / n, float(t1 - t0) * 1000.0 / writes])
	t0 = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
	for i2: int in n:
		var ny: int = cy + (1 if (i2 & 1) == 0 else -1)
		g.move_disc(cx, cy, cx, ny, 8, sink)
		cy = ny
		if sink.cells.size() > 4096:
			sink.clear()
	t1 = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
	print("move_disc R=8 y-step: %.2f us/step" % (float(t1 - t0) / n))
	t0 = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
	for i3: int in n:
		var dx: int = 1 if (i3 & 1) == 0 else -1
		g.move_disc(cx, cy, cx + dx, cy + dx, 8, sink)
		cx += dx
		cy += dx
		if sink.cells.size() > 4096:
			sink.clear()
	t1 = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
	print("move_disc R=8 diagonal step: %.2f us/step" % (float(t1 - t0) / n))
	var gate: float = float(t1 - t0) / n
	print("calibration gate: %s (12 us limit for a one-cell step)" % ("PASS" if gate <= 12.0 else "FAIL -> Low preset"))


func _stage(low: bool) -> void:
	var d: GameData = AbilKit.data()
	var cells: PackedInt32Array = PackedInt32Array()
	for i: int in 8:
		cells.append((20 + (i % 4) * 60) * 256 + (20 + (i / 4) * 120))
	var m: MapData = MapData.for_test(256, 256, cells, PackedInt32Array(), 0x5678EF02)
	m.set_footprint(SimEntity.Kind.STRUCTURE, d.structure_idx(DefTestKit.S_TURRET), MapFootprint.new(1, 1))
	var rules: Dictionary = {"start_mode": SimMatchRules.START_NONE, "victory": 0, "neutral_structures": 0, "unit_cap": 400, "fog": true}
	if low:
		rules["vision_budget"] = 64
		rules["vision_stride"] = 3
	var cfg: SimMatchConfig = SimTestKit.make_config(8, 4242, rules)
	var tv: TimedVision = TimedVision.new()
	var ta: TimedAbil = TimedAbil.new()
	var w: SimWorld = SimWorld.create(d, cfg, m, {"systems": [tv, ta], "disable": ["SimMovementSystem", "SimCombatSystem"]})
	if w == null:
		print("world creation failed")
		quit(1)
		return
	var defs: PackedStringArray = [DefTestKit.U_RIFLEMAN, DefTestKit.U_TANK, DefTestKit.U_ENGINEER, DefTestKit.U_ENGINEER]  # 25 % camouflage, 25 % detectors
	var t_spawn: int = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
	for pid: int in 8:
		var bx: int = 20 + (pid % 4) * 60
		var by: int = 20 + (pid / 4) * 120
		for k: int in 150:
			AbilKit.spawn(w, defs[k % 4], pid, bx + (k % 15) * 2 - 14, by + (k / 15) * 2 - 10)
		for k2: int in 60:
			AbilKit.spawn_struct(w, DefTestKit.S_TURRET, pid, bx + (k2 % 12) * 2 - 12, by + 14 + (k2 / 12) * 2)
	w.step()  # spawns join the world's lists at the flush
	print("spawned %d entities in %.0f ms" % [w.entities.size(), float(Time.get_ticks_usec() - t_spawn) / 1000.0])  # lint-allow: L003 benchmark stopwatch
	var movers: Array[SimEntity] = []
	for e: SimEntity in w.units:
		if e.id % 5 < 2:
			movers.append(e)
	print("movers %d of %d units, stride %d budget %d" % [movers.size(), w.units.size(), w.vision.vstride, w.vision.restamp_budget])
	var t_all: int = 0
	for s: int in TICKS:
		for e2: SimEntity in movers:
			var dir: int = ((e2.id + s / 120) % 4)
			var nx: int = e2.x + (100 if dir == 0 else (-100 if dir == 1 else 0))
			var ny: int = e2.y + (100 if dir == 2 else (-100 if dir == 3 else 0))
			w.set_pos(e2, clampi(nx, 3072, 252000), clampi(ny, 3072, 252000))
		var a: int = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
		w.step()
		if s >= WARMUP:
			t_all += Time.get_ticks_usec() - a  # lint-allow: L003 benchmark stopwatch
	var ticks: int = TICKS - WARMUP
	print("stage 10 over %d ticks: avg %.3f ms/tick; %.3f ms per update (%d updates), worst call %.3f ms" % [
		ticks, float(tv.usec) / 1000.0 / ticks, float(tv.usec) / 1000.0 / maxi(tv.updates, 1), tv.updates, float(tv.worst) / 1000.0])
	print("stage 7 (abilities): avg %.3f ms/tick, watch list %d" % [float(ta.usec) / 1000.0 / ticks, w.abilities.watch_list.size()])
	print("whole step (vision + abilities + kernel, no movement / combat): %.3f ms/tick" % (float(t_all) / 1000.0 / ticks))
	print("counters: restamps %d, recomputes %d, cells written %d, deferred now %d" % [
		w.vision.stat_restamps, w.vision.stat_recomputes, w.vision.cells_written(), w.vision.deferred.size()])
	print("rebuild-compare: %d differing cells" % w.vision.debug_rebuild_compare(w))
