extends SceneTree
## Movement stage cost (terrain_movement 9.2): 256x256 map, 8 players, 1 200 unit entities, 300 of them moving.
## Run: tools/gd run res://tests/bench/bench_move.gd   (prints ms per tick of stage 6 and of the whole step)

const M := preload("res://tests/support/move_test_kit.gd")
const TICKS: int = 400


## Stage 6 with a stopwatch (the clock never feeds the simulation).
class TimedMove:
	extends SimMovementSystem
	var usec: int = 0
	var worst: int = 0
	var samples: int = 0
	var path_units: int = 0
	var ph: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])  ## flush, path, collect, grid, A, B, C, maintain

	func update(world: SimWorld) -> void:
		var t0: int = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch, never read by the sim
		var t1: int = t0
		_nav.flush_dirty(SimMoveConfig.NAV_DIRTY_BUDGET)
		t1 = _lap(t1, 0)
		path.process(world)
		t1 = _lap(t1, 1)
		_ents.resize(0)
		for id: int in _movers:
			var e: SimEntity = world.by_id[id]
			if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE | SimFlags.F_SCRIPTED_MOVE)) != 0 or e.move.mc >= MapTerrain.MC_AIR_FIXED:
				continue
			_ents.append(e)
		var n: int = _ents.size()
		if _sx.size() < n:
			_sx.resize(n * 2)
			_sy.resize(n * 2)
			_pd.resize(n * 4)
		for np: int in MapTerrain.NP_COUNT:
			_wg[np] = _nav.wgt_array(np)
		t1 = _lap(t1, 2)
		sep.refresh_relations(world)
		sep.rebuild(world, _ents, n)
		t1 = _lap(t1, 3)
		for i: int in n:
			_phase_a(world, i, _ents[i], _ents[i].move)
		t1 = _lap(t1, 4)
		sep.predict(_sx, _sy, n)
		sep.compute_all(n, world.tick, _pd)
		t1 = _lap(t1, 5)
		for i: int in n:
			_phase_c(world, i, _ents[i], _ents[i].move)
		t1 = _lap(t1, 6)
		for i: int in n:
			var mvm: SimCompMove = _ents[i].move
			var stm: int = mvm.state
			if stm == SimMoveConfig.MS_MOVING or stm == SimMoveConfig.MS_BLOCKED or stm == SimMoveConfig.MS_WAIT_PATH or mvm.stuck_cnt != 0:
				_maintain(world, i, _ents[i], mvm)
		t1 = _lap(t1, 7)
		var dt: int = t1 - t0
		usec += dt
		samples += 1
		worst = maxi(worst, dt)
		path_units += path.last_units

	func _lap(prev: int, slot: int) -> int:
		var now: int = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
		ph[slot] += now - prev
		return now


func _init() -> void:
	var m: MapData = M.clutter_map(256, 12, 21)
	var cfg: SimMatchConfig = load("res://tests/support/sim_test_kit.gd").make_config(8, 4242, {"start_mode": SimMatchRules.START_NONE, "victory": 0, "neutral_structures": 0, "unit_cap": 400})
	var tm: TimedMove = TimedMove.new()
	var systems: Array = [tm]
	if OS.get_cmdline_user_args().has("adapters"):
		systems.append(M.AbilStub.new())  # abilities adapters present: speed_units / is_immobile / is_turn_locked calls
		print("with abilities adapters")
	var w: SimWorld = SimWorld.create(M.data(), cfg, m, {"systems": systems})
	if w == null:
		print("world creation failed")
		quit(1)
		return
	var rng: SimRng = SimRng.new(5)
	var ids: PackedStringArray = [DefTestKit.U_RIFLEMAN, DefTestKit.U_TANK, DefTestKit.U_COLLECTOR, DefTestKit.U_MCV]
	var all: Array[SimEntity] = []
	var guard: int = 0
	while all.size() < 1200 and guard < 100000:
		guard += 1
		var cx: int = 8 + rng.next_int(240)
		var cy: int = 8 + rng.next_int(240)
		if m.nav.clear_at(MapTerrain.NP_TRACKED, cy * 256 + cx) < 2:
			continue
		var e: SimEntity = M.spawn(w, ids[all.size() % 4], cx, cy, all.size() % 8)
		if e != null:
			all.append(e)
	print("spawned ", all.size(), " units on ", m.w, "x", m.h)
	var movers: Array[SimEntity] = []
	for i: int in all.size():
		if movers.size() < 300 and i % 4 != 0:
			movers.append(all[i])
	var total_usec: int = 0
	var worst_step: int = 0
	for tick: int in TICKS:
		if tick % 60 == 0:
			for e: SimEntity in movers:
				if SimMovement.state(e) != SimMoveConfig.MS_MOVING and SimMovement.state(e) != SimMoveConfig.MS_WAIT_PATH:
					var gx: int = 8 + rng.next_int(240)
					var gy: int = 8 + rng.next_int(240)
					SimMovement.go_to(w, e, gx * 1024 + 512, gy * 1024 + 512)
		var t0: int = Time.get_ticks_usec()  # lint-allow: L003 benchmark stopwatch
		w.step()
		var dt: int = Time.get_ticks_usec() - t0  # lint-allow: L003 benchmark stopwatch
		total_usec += dt
		worst_step = maxi(worst_step, dt)
	var moving: int = 0
	for e: SimEntity in movers:
		if e.move.spd_q4 != 0:
			moving += 1
	print("moving at the end: ", moving, " of ", movers.size())
	print("stage 6 movement: avg %.3f ms/tick, worst %.2f ms (%d ticks); path units avg %d/tick" % [tm.usec / 1000.0 / tm.samples, tm.worst / 1000.0, tm.samples, tm.path_units / tm.samples])
	var names: PackedStringArray = ["flush", "path", "collect", "grid", "phaseA", "phaseB", "phaseC", "maintain"]
	var line: String = "phases (ms/tick):"
	for i: int in 8:
		line += " %s %.3f" % [names[i], tm.ph[i] / 1000.0 / tm.samples]
	print(line)
	print("whole step:       avg %.3f ms/tick, worst %.2f ms" % [total_usec / 1000.0 / TICKS, worst_step / 1000.0])
	print("path service: searches ", w.movement.path.stat_searches, " cache hits ", w.movement.path.stat_hits, " delivered ", w.movement.path.stat_delivered, " failed ", w.movement.path.stat_failed)
	quit()
