extends RefCounted
## AiPlacer (ai.md 3.5b): valid cells only, site preferences, blacklist, budget resume, dock heuristic.

const BIG: int = 1000000


func _match(extra: Dictionary = {}) -> Dictionary:
	var o: Dictionary = {"seed": 3, "waves": false, "rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"])}
	o.merge(extra, true)
	var m: Dictionary = AiEconKit.make(o)
	AiEconKit.run(m, 40)  # bootstraps the controllers (first think)
	return m


func _solve(eco: AiEconomy, def: int, site: int, hx: int = -1, hy: int = -1) -> PackedInt32Array:
	var job: AiJob = eco.placer.request(def, site, hx, hy)
	var b: AiBudget = AiBudget.new()
	var guard: int = 0
	while not job.done and guard < 100:
		b.reset(BIG, BIG)
		job.step(b)
		guard += 1
	return job.result()


func _d2_to_enemy(ctx: AiContext, cell: PackedInt32Array) -> int:
	var ex: int = ctx.kb.enemy_starts[0]
	var ey: int = ctx.kb.enemy_starts[1]
	return (cell[0] - ex) * (cell[0] - ex) + (cell[1] - ey) * (cell[1] - ey)


func test_result_is_valid_for_the_sim(t: TestCtx) -> void:
	var m: Dictionary = _match()
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	for kind: int in [AiTypes.StructKind.BARRACKS, AiTypes.StructKind.GENERATOR, AiTypes.StructKind.FACTORY, AiTypes.StructKind.WATCHTOWER]:
		var def: int = ctx.res.structure_of_kind(kind)
		var r: PackedInt32Array = _solve(eco, def, AiBuildPlanner.default_site(kind))
		t.eq(r.size(), 3, "a site for kind %d" % kind)
		if r.size() == 3:
			t.check(ctx.view.can_place(def, r[0], r[1], r[2]), "the sim accepts the cell of kind %d" % kind)


func test_back_is_farther_from_the_enemy_than_front(t: TestCtx) -> void:
	var m: Dictionary = _match()
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var def: int = ctx.res.structure_of_kind(AiTypes.StructKind.GENERATOR)
	var back: PackedInt32Array = _solve(eco, def, AiPlacer.Site.BACK)
	var front: PackedInt32Array = _solve(eco, def, AiPlacer.Site.FRONT)
	t.eq(back.size(), 3)
	t.eq(front.size(), 3)
	t.gt(_d2_to_enemy(ctx, back), _d2_to_enemy(ctx, front), "BACK sits behind FRONT relative to the enemy start")


func test_field_site_is_next_to_the_field(t: TestCtx) -> void:
	var m: Dictionary = _match()
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var def: int = ctx.res.structure_of_kind(AiTypes.StructKind.REFINERY)
	var f: PackedInt32Array = eco.planner.free_field(ctx, eco)
	t.eq(f.size(), 2, "a free field exists")
	var r: PackedInt32Array = _solve(eco, def, AiPlacer.Site.FIELD, f[0], f[1])
	t.eq(r.size(), 3)
	var dx: int = r[0] + 1 - (f[0] >> Fp.CELL_SHIFT)
	var dy: int = r[1] + 1 - (f[1] >> Fp.CELL_SHIFT)
	t.le(maxi(absi(dx), absi(dy)), 9, "the refinery stands within 9 cells of the field centre")
	t.check(ctx.view.can_place(def, r[0], r[1], r[2]))


func test_spacing_keeps_a_lane_between_structures(t: TestCtx) -> void:
	var m: Dictionary = _match()
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var def: int = ctx.res.structure_of_kind(AiTypes.StructKind.FACTORY)
	var r: PackedInt32Array = _solve(eco, def, AiPlacer.Site.ANY)
	t.eq(r.size(), 3)
	var d: DefStructure = ctx.view.structure_def(def)
	var t_own: AiEntityTable = ctx.kb.own
	for row: int in t_own.count:
		if t_own.kind[row] != AiTypes.KIND_STRUCTURE:
			continue
		var sd: DefStructure = ctx.view.structure_def(t_own.def[row])
		var x0: int = (t_own.x[row] - sd.fp_w * (Fp.CELL / 2)) >> Fp.CELL_SHIFT
		var y0: int = (t_own.y[row] - sd.fp_h * (Fp.CELL / 2)) >> Fp.CELL_SHIFT
		var gx: int = maxi(x0 - (r[0] + d.fp_w - 1), r[0] - (x0 + sd.fp_w - 1)) - 1
		var gy: int = maxi(y0 - (r[1] + d.fp_h - 1), r[1] - (y0 + sd.fp_h - 1)) - 1
		t.ge(maxi(gx, gy), 1, "at least one free cell to structure row %d" % row)


func test_blacklist_and_budget_resume(t: TestCtx) -> void:
	var m: Dictionary = _match()
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var def: int = ctx.res.structure_of_kind(AiTypes.StructKind.BARRACKS)
	var first: PackedInt32Array = _solve(eco, def, AiPlacer.Site.ANY)
	eco.placer.blacklist(first[0], first[1], ctx.tick + 1000)
	var second: PackedInt32Array = _solve(eco, def, AiPlacer.Site.ANY)
	t.eq(second.size(), 3)
	t.check(second[0] != first[0] or second[1] != first[1], "a blacklisted cell is not offered again")
	# a tiny budget only advances the job; it still finishes with the same answer
	var job: AiJob = eco.placer.request(def, AiPlacer.Site.ANY)
	var b: AiBudget = AiBudget.new()
	var steps: int = 0
	while not job.done and steps < 2000:
		b.reset(12, 12)
		job.step(b)
		steps += 1
	t.check(job.done)
	t.gt(steps, 2, "the job was sliced over several calls")
	t.eq(job.result(), second, "slicing does not change the result")
	t.eq(eco.placer.is_blacklisted(first[0], first[1], ctx.tick + 2000), false, "blacklist entries expire")


func test_dock_placeable_heuristic(t: TestCtx) -> void:
	var open: Dictionary = _match({"family": 0})
	t.check_false(AiEconKit.eco_of(open, 0).placer.dock_placeable(AiEconKit.ctx_of(open, 0)), "open map: no water next to the base")
	var coast: Dictionary = _match({"family": 2, "map_params": {"start_near_water": true}})
	var ctx: AiContext = AiEconKit.ctx_of(coast, 0)
	var eco: AiEconomy = AiEconKit.eco_of(coast, 0)
	t.check(eco.placer.dock_placeable(ctx), "coast map with start_near_water")
	var dock: int = ctx.res.structure_of_kind(AiTypes.StructKind.DOCK)
	var r: PackedInt32Array = _solve(eco, dock, AiPlacer.Site.ANY)
	if r.size() == 3:
		t.check(ctx.view.can_place(dock, r[0], r[1], r[2]), "a Dock cell the sim accepts")
	else:
		t.note("no dock cell found on this coast seed (heuristic only)")
