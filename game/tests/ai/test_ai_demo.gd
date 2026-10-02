extends RefCounted
## AI-01..03 demo: an AiController with a TRIVIAL op plays 2000 ticks inside a REAL SimMatchKit match (real GameData,
## generated map, every real system) through AiFactory / AiThinker exactly as net would drive it (think every N turns,
## sanitised commands, submit_raw). Checks: valid commands only, within the work-unit budget and the 1.5 ms average, the
## AI actually builds and trains, determinism (same world + same AI => same checksum and AI state hash), fog policy.

const PERIOD_TURNS: PackedInt32Array = [5, 3, 2, 1]  ## per-level think periods requested from net (ai.md 13.16)


## The trivial op: a tiny scripted economy + one attack wave, written only against the AI module's own APIs.
class TrivialOp extends RefCounted:
	var ladder: PackedInt32Array = PackedInt32Array()  ## structure defs in build order
	var infantry: int = -1
	var placing: int = -1
	var cand: PackedInt32Array = PackedInt32Array()
	var cand_i: int = 0
	var placed: int = 0
	var started: int = 0
	var trained: int = 0
	var waves: int = 0
	var _last_attack: int = -1000

	func setup(ctx: AiContext) -> void:
		for k: int in [AiTypes.StructKind.GENERATOR, AiTypes.StructKind.BARRACKS, AiTypes.StructKind.REFINERY, AiTypes.StructKind.GENERATOR,
				AiTypes.StructKind.FACTORY]:
			var s: int = ctx.res.structure_of_kind(k)
			if s >= 0:
				ladder.append(s)
		infantry = ctx.res.first(AiTypes.R_INFANTRY_BASIC)

	func step(ctx: AiContext, budget: AiBudget) -> void:
		var v: AiWorldView = ctx.view
		if not budget.spend(4):
			return
		_train(ctx, budget)
		_attack(ctx, budget)
		var cs: PackedInt32Array = PackedInt32Array()
		v.construction_state(cs)
		if cs[0] == 2:
			_place(ctx, budget, cs[3])
		elif cs[0] == 0 and v.has_hq():
			var have: Dictionary = {}
			for s: int in ladder:
				have[s] = int(have.get(s, 0)) + 1
				if v.struct_count(s) < int(have[s]) and v.can_build(s) == AiTypes.Rule.OK:
					if ctx.cmd.build_start(s):
						started += 1
					break

	func _place(ctx: AiContext, budget: AiBudget, s_def: int) -> void:
		var v: AiWorldView = ctx.view
		if placing != s_def:
			placing = s_def
			cand = PackedInt32Array()
			var hx: int = v.start_cell_x(v.me())
			var hy: int = v.start_cell_y(v.me())
			for ring: int in range(3, 12):
				for dy: int in range(-ring, ring + 1, 2):
					for dx: int in range(-ring, ring + 1, 2):
						if maxi(absi(dx), absi(dy)) == ring:
							cand.append(hx + dx)
							cand.append(hy + dy)
			cand_i = 0
		while cand_i < cand.size() / 2:
			if not budget.spend(5):
				return
			var cx: int = cand[2 * cand_i]
			var cy: int = cand[2 * cand_i + 1]
			cand_i += 1
			if v.can_place(s_def, cx, cy):
				if ctx.cmd.build_place(s_def, cx, cy):
					placed += 1
					placing = -1
				return
		placing = -1

	func _train(ctx: AiContext, budget: AiBudget) -> void:
		var v: AiWorldView = ctx.view
		if infantry < 0:
			return
		for id: int in v.producer_ids():
			if not budget.spend(3):
				return
			if v.producer_kind(id) != SimEconConst.PROD_BARRACKS:
				continue
			var q: PackedInt32Array = PackedInt32Array()
			if v.queue_of(id, q) == 0 and v.can_train(id, infantry) == AiTypes.Rule.OK:
				if ctx.cmd.train(id, infantry, 1):
					trained += 1

	func _attack(ctx: AiContext, budget: AiBudget) -> void:
		if ctx.tick < 1500 or ctx.tick - _last_attack < 200:
			return
		var kb: AiKnowledge = ctx.kb
		var ids: PackedInt32Array = PackedInt32Array()
		for r: int in kb.own.count:
			if not budget.spend(1):
				return
			if kb.own.kind[r] == AiTypes.KIND_UNIT and (kb.own.role_mask[r] & (1 << AiTypes.R_COMBAT)) != 0 and kb.own.order[r] == AiTypes.OrderKind.IDLE:
				ids.append(kb.own.eid[r])
		if ids.size() < 3 or kb.enemy_starts.size() < 2:
			return
		_last_attack = ctx.tick
		if ctx.cmd.attack_move(ids, kb.enemy_starts[0] * Fp.CELL + Fp.CELL / 2, kb.enemy_starts[1] * Fp.CELL + Fp.CELL / 2):
			waves += 1


## Runs a match with one AI (pid 0) for `ticks` ticks; returns the run summary.
func _play(level: int, ticks: int, fog: bool = false, map_seed: int = 3, second_level: int = -1) -> Dictionary:
	var m: Dictionary = SimMatchKit.make_match({"seed": map_seed, "bots": false, "rules": {"fog": fog, "victory": 0}, "credits": 10000})
	var w: SimWorld = m["world"]
	var factory: AiFactory = AiFactory.new()
	factory.perf = true
	var pids: Array = [0]
	if second_level >= 0:
		pids.append(1)
	var calls: Dictionary = {}
	var ops: Dictionary = {}
	for pid: int in pids:
		var lv: int = level if pid == 0 else second_level
		calls[pid] = factory.make(pid, lv, 0, AiRng.thinker_seed(777, pid))
		var op: TrivialOp = TrivialOp.new()
		ops[pid] = op
		factory.thinker(pid).controller.register(AiScheduler.Slot.ECONOMY, op)
	var errors: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv2: int, tag: String, msg: String) -> void:
		if lv2 >= Log.Level.WARN:
			errors.append("%s: %s" % [tag, msg])
	var emitted: int = 0
	var bad: int = 0
	var max_per_think: int = 0
	for _i: int in ticks:
		if w.tick % 2 == 0:
			for pid2: int in pids:
				var lv3: int = level if pid2 == 0 else second_level
				if (w.tick / 2 + pid2) % PERIOD_TURNS[lv3] == 0:
					var out: Array = []
					(calls[pid2] as Callable).call(w, out)
					max_per_think = maxi(max_per_think, out.size())
					for c: Variant in out:
						var cmd: PackedInt32Array = c
						if cmd.size() < 1 or cmd.size() > 1024 or cmd[0] < 0 or cmd[0] > 255:
							bad += 1
							continue
						emitted += 1
						w.submit_raw(pid2, cmd)
		w.step()
	Log.sink = old_sink
	return {"world": w, "factory": factory, "ops": ops, "errors": errors, "emitted": emitted, "bad": bad, "max_per_think": max_per_think}


func test_trivial_op_plays_2000_ticks_within_budget(t: TestCtx) -> void:
	var r: Dictionary = _play(AiTypes.Difficulty.HARD, 2000)
	var w: SimWorld = r["world"]
	var f: AiFactory = r["factory"]
	var op: TrivialOp = (r["ops"] as Dictionary)[0]
	var th: AiThinker = f.thinker(0)
	var c: AiController = th.controller
	t.eq(r["errors"], PackedStringArray(), "no Log warnings or errors")
	t.eq(r["bad"], 0, "every command has size 1..1024 and type 0..255")
	t.le(int(r["max_per_think"]), 64, "<= 64 commands per think")
	t.gt(int(r["emitted"]), 8, "the AI acted")
	var d: AiDifficultyProfile = c.ctx.diff
	t.le(c.total_wu, d.wu_per_tick * c.total_ticks + d.call_cap_wu, "average work units per tick within the profile")
	t.le(c.wu_max_think, d.call_cap_wu + 500, "one think stays near the call cap")
	var us_per_tick: int = th.controller.perf.total_us / maxi(c.total_ticks, 1)
	t.le(float(us_per_tick), 1500.0 * TestCtx.perf_factor(), "average wall time per tick <= 1.5 ms x perf_factor (measured %d us)" % us_per_tick)
	t.note("AI: %d thinks, %d cmds, avg %d wu/tick (profile %d), max think %d wu, %d us/tick, worst think %d us" % [
		th.thinks, int(r["emitted"]), c.total_wu / maxi(c.total_ticks, 1), d.wu_per_tick, c.wu_max_think, us_per_tick, c.perf.worst_us])
	# the commands were valid and effective
	var p: SimPlayer = w.players[0]
	t.gt(op.started, 1, "construction started")
	t.gt(op.placed, 0, "structures placed")
	t.gt(p.st_structs_built, 0, "the sim built what the AI asked for")
	t.gt(p.st_units_built, 0, "units were trained")
	t.lt(p.st_rejected * 100, maxi(p.st_cmds, 1) * 25, "rejected commands stay below 25 %% (%d of %d)" % [p.st_rejected, p.st_cmds])
	# the knowledge base tracked reality
	t.eq(c.ctx.kb.own.count, w.own_ids(0).size(), "own table == the world")
	t.check(c.ctx.pers != null and c.ctx.pers.aggression > 0)
	t.eq(c.ctx.kb.enemy_starts.size(), 2, "one enemy start known")
	var hq: PackedInt32Array = PackedInt32Array()
	t.check(c.ctx.kb.enemy_hq(1, hq), "enemy HQ known (fog is off in this match)")
	t.note("op: started %d placed %d trained %d waves %d | built %d/%d units %d credits %d" % [op.started, op.placed, op.trained, op.waves, p.st_structs_built, p.struct_count, p.st_units_built, p.credits])


func test_two_runs_are_identical(t: TestCtx) -> void:
	var a: Dictionary = _play(AiTypes.Difficulty.MEDIUM, 900, false, 5, AiTypes.Difficulty.EASY)
	var b: Dictionary = _play(AiTypes.Difficulty.MEDIUM, 900, false, 5, AiTypes.Difficulty.EASY)
	t.eq((a["world"] as SimWorld).checksum(), (b["world"] as SimWorld).checksum(), "same AI + same sim => same checksum")
	t.eq((a["factory"] as AiFactory).state_hash(), (b["factory"] as AiFactory).state_hash(), "same AI state hash")
	t.eq(int(a["emitted"]), int(b["emitted"]))
	t.gt(int(a["emitted"]), 5)


func test_fog_policy(t: TestCtx) -> void:
	# fog on: a fair AI sees no enemy at the start, Brutal (omniscient) reads the enemy structures through the fog
	var hard: Dictionary = _play(AiTypes.Difficulty.HARD, 40, true)
	var brutal: Dictionary = _play(AiTypes.Difficulty.BRUTAL, 40, true)
	var h: AiController = (hard["factory"] as AiFactory).thinker(0).controller
	var b: AiController = (brutal["factory"] as AiFactory).thinker(0).controller
	t.check_false(h.ctx.view.omniscient)
	t.check(b.ctx.view.omniscient)
	var ids: PackedInt32Array = PackedInt32Array()
	t.eq(h.ctx.view.visible_enemy_ids(ids), 0, "Hard: nothing of the enemy visible at tick 40")
	t.gt(b.ctx.view.visible_enemy_ids(ids), 0, "Brutal: enemy entities read through the fog")
	t.check_false(b.ctx.view.targetable_now(ids[0]), "but real vision decides whether an attack command is legal")
	t.check(b.ctx.view.cell_visible(b.ctx.view.start_cell_x(0), b.ctx.view.start_cell_y(0)), "own base is visible")
	t.check_false(b.ctx.view.cell_visible(b.ctx.view.start_cell_x(1), b.ctx.view.start_cell_y(1)), "cell_visible is never cheated")
