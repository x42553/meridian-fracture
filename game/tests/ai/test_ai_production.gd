extends RefCounted
## AiProduction (ai.md 5.6.2 / 5.6.3): staging point and rally, queue depth, unit cap, aircraft cap and the deficit order.


func _match(extra: Dictionary = {}) -> Dictionary:
	var o: Dictionary = {"seed": 1, "waves": false, "rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), "level": AiTypes.Difficulty.HARD}
	o.merge(extra, true)
	return AiEconKit.make(o)


func test_stage_point_and_rally(t: TestCtx) -> void:
	var m: Dictionary = _match({"fog": false})
	AiEconKit.run(m, 5400)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var pr: AiProduction = eco.production
	var hx: int = ctx.kb.sites.home_x
	var hy: int = ctx.kb.sites.home_y
	var d_cells: int = Fp.dist(pr.stage_x - hx, pr.stage_y - hy) / Fp.CELL
	t.check(d_cells >= 8 and d_cells <= 16, "the staging point lies about 13 cells from the HQ (%d)" % d_cells)
	var ex: int = ctx.kb.enemy_starts[0] * Fp.CELL
	var ey: int = ctx.kb.enemy_starts[1] * Fp.CELL
	t.lt(Fp.dist(pr.stage_x - ex, pr.stage_y - ey), Fp.dist(hx - ex, hy - ey), "... towards the enemy")
	t.check(ctx.view.passable(pr.stage_x >> Fp.CELL_SHIFT, pr.stage_y >> Fp.CELL_SHIFT, AiTypes.MoveClass.TRACKED), "on passable ground")
	t.ge(pr.rally_cmds, 2, "Barracks and Factory got a rally point (%d commands)" % pr.rally_cmds)
	# produced combat units walk to the staging point
	var near: int = 0
	var total: int = 0
	var t_own: AiEntityTable = ctx.kb.own
	for r: int in t_own.count:
		if eco.squads.eligible(r):
			total += 1
			if Fp.dist(t_own.x[r] - pr.stage_x, t_own.y[r] - pr.stage_y) < 14 * Fp.CELL:
				near += 1
	t.ge(total, 2)  # AIT: the economy-first build has 3 combat units at 4:30
	t.ge(near * 2, total, "most of the army stands at the staging point (%d of %d)" % [near, total])
	# the brain may move the point; producers get a new rally when it moved more than 8 cells
	var before: int = pr.rally_cmds
	pr.set_stage(pr.stage_x + 12 * Fp.CELL, pr.stage_y)
	AiEconKit.run(m, 200)
	t.gt(pr.rally_cmds, before, "a moved staging point re-rallies the producers")


func test_queue_depth_unit_cap_and_lines(t: TestCtx) -> void:
	var m: Dictionary = _match({"rules": {"unit_cap": 24}, "credits": 30000})
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	AiEconKit.run(m, 60)
	var depth: int = ctx.diff.queue_depth
	var max_units: int = 0
	for k: int in 60:
		AiEconKit.run(m, 100)
		max_units = maxi(max_units, ctx.view.unit_count())
		for i: int in eco.prod_qlen.size():
			if eco.prod_kind[i] != AiTypes.StructKind.REFINERY:
				t.le(eco.prod_qlen[i], depth + 1, "queue depth respected (one command may be in flight)")
	t.le(max_units, 24, "the unit cap is never exceeded (%d)" % max_units)
	t.gt(eco.production.trained, 5)
	t.le(ctx.view.unit_count(), 24 * ctx.diff.unit_cap_pct / 100 + 4, "production stops near the cap minus the reserve")


func test_aircraft_are_limited_by_the_pads(t: TestCtx) -> void:
	var m: Dictionary = _match({"rosters": PackedStringArray(["roster.napc.usa", "roster.nec.vanilla"]), "credits": 40000, "fog": false})
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	AiEconKit.run(m, 50)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	eco.comp.phase_override = AiTypes.Phase.LATE
	var af: int = ctx.res.structure_of_kind(AiTypes.StructKind.AIRFIELD)
	var pads: int = maxi(ctx.view.structure_def(af).pads, 1)
	var worst_excess: int = -1000
	var air_seen: int = 0
	for k: int in 70:
		AiEconKit.run(m, 100)
		var n: int = 0
		for r: int in [AiTypes.R_FIGHTER, AiTypes.R_BOMBER, AiTypes.R_EW_AIR]:
			n += eco.role_alive[r] + eco.role_queued[r]
		air_seen = maxi(air_seen, n)
		worst_excess = maxi(worst_excess, n - eco.struct_own[af] * pads * 3 / 2)
	t.gt(air_seen, 0, "the USA builds aircraft")
	t.le(worst_excess, 0, "aircraft (alive + queued) never exceed pads x 3/2 (excess %d)" % worst_excess)
