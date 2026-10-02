extends RefCounted
## AiEntityTable / AiGhostTable / AiEnemyProfile / AiResourceSites / AiKnowledge queries on scripted data.

const C: int = Fp.CELL


func test_entity_table_swap_remove(t: TestCtx) -> void:
	var e: AiEntityTable = AiEntityTable.new()
	for id: int in [5, 3, 9, 7]:
		var r: int = e.upsert(id)
		e.x[r] = id * 10
	t.eq(e.count, 4)
	t.eq(e.row(3), 1)
	t.check(e.remove(5), "removes the first row")
	t.eq(e.count, 3)
	t.eq(e.x[e.row(7)], 70, "the last row was swapped in and keeps its data")
	t.eq(e.row(5), -1)
	t.check_false(e.remove(5))
	t.eq(e.sorted_eids(), PackedInt32Array([3, 7, 9]), "iteration order is by eid, never by row")
	for i: int in 200:
		e.upsert(1000 + i)
	t.eq(e.count, 203, "growth")
	t.eq(e.squad[e.row(1100)], -1)


func test_ghost_table_rules(t: TestCtx) -> void:
	var g: AiGhostTable = AiGhostTable.new()
	g.seed_presumed_hq(1, 24, 80 * C, 80 * C, 0, 0)
	t.eq(g.conf[g.row(-2)], 30, "presumed HQ starts at conf 30")
	g.upsert(50, 22, 1, 70 * C, 70 * C, 100, 80, 0, AiTypes.StructKind.FACTORY, 2000)
	g.upsert(49, 21, 1, 71 * C, 70 * C, 100, 100, 0, AiTypes.StructKind.BARRACKS, 800)
	t.eq(g.conf[g.row(50)], 100)
	g.decay(100 + 20 * 30)
	t.eq(g.conf[g.row(50)], 70, "-1 per 20 ticks")
	g.decay(100 + 20 * 500)
	t.eq(g.conf[g.row(50)], 30, "floor 30")
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(g.near(70 * C, 70 * C, 3 * C, 1 << AiTypes.StructKind.FACTORY, out), 1, "kind mask filter")
	t.eq(g.near(70 * C, 70 * C, 3 * C, -1, out), 2)
	t.eq(g.eid[out[0]], 49, "ascending eid")
	g.replace_presumed(1)
	t.check_false(g.has(-2))
	t.eq(g.value_of_owner(1), 2800)


func test_enemy_profile_blend_and_decay(t: TestCtx) -> void:
	var p: AiEnemyProfile = AiEnemyProfile.new()
	var prior: PackedInt32Array = PackedInt32Array()
	prior.resize(AiTypes.Cat.COUNT)
	prior[AiTypes.Cat.ARMOR] = 128
	prior[AiTypes.Cat.INFANTRY] = 128
	p.set_prior(prior)
	t.eq(p.share(AiTypes.Cat.ARMOR), 128, "no observation => the prior")
	p.observe(AiTypes.Cat.AIR, 4000, 50)
	p.recompute()
	t.eq(p.first_seen_tick[AiTypes.Cat.AIR], 50)
	t.eq(p.share(AiTypes.Cat.AIR), 256, "enough evidence: the prior faded out")
	t.eq(p.share(AiTypes.Cat.ARMOR), 0)
	p.decay(200)
	t.eq(p.seen_value[AiTypes.Cat.AIR], 3500, "x7/8 per 200 ticks")
	t.eq(p.air_peak, 4000)


func test_sites_and_queries(t: TestCtx) -> void:
	var v: AiMockWorldView = AiMockWorldView.new(0)
	v.add_player(0, "roster.napc.vanilla", Vector2i(15, 15))
	v.add_player(1, "roster.nec.vanilla", Vector2i(80, 80))
	v.deposits = [{"x": 18 * C, "y": 15 * C, "left": 4000}, {"x": 40 * C, "y": 20 * C, "left": 3000}, {"x": 75 * C, "y": 78 * C, "left": 5000}]
	var ctx: AiContext = AiMockWorldView.make_ctx(v)
	var s: AiResourceSites = ctx.kb.sites
	t.eq(s.count, 3)
	t.eq(s.kind[0], AiResourceSites.K_MAIN)
	t.eq(s.kind[1], AiResourceSites.K_NEAR)
	t.eq(s.kind[2], AiResourceSites.K_ENEMY)
	for _i: int in 6:
		s.refresh_step(v, ctx.kb, ctx.kb.route)
	t.gt(s.path_len_c[1], 15, "route length from home filled in")
	t.eq(s.best_free_site(15 * C, 15 * C), 0)
	s.claimed_refinery_eid[0] = 77
	t.eq(s.best_free_site(15 * C, 15 * C), 1, "claimed sites are skipped")
	# presumed enemy HQ + primary enemy
	var hq: PackedInt32Array = PackedInt32Array()
	t.check(ctx.kb.enemy_hq(1, hq))
	t.eq(hq[0], 80 * C + C / 2)
	ctx.kb.update_primary(ctx)
	t.eq(ctx.kb.primary_enemy(), 1)
	# enemies_near is ascending by eid
	var r2: int = ctx.kb.enemy_units.upsert(20)
	ctx.kb.enemy_units.x[r2] = 30 * C
	ctx.kb.enemy_units.y[r2] = 30 * C
	var r1: int = ctx.kb.enemy_units.upsert(10)
	ctx.kb.enemy_units.x[r1] = 31 * C
	ctx.kb.enemy_units.y[r1] = 30 * C
	var near: PackedInt32Array = PackedInt32Array()
	t.eq(ctx.kb.enemies_near(30 * C, 30 * C, 3 * C, near), 2)
	t.eq(ctx.kb.enemy_units.eid[near[0]], 10)


func test_primary_enemy_prefers_close_weak_hostile(t: TestCtx) -> void:
	var v: AiMockWorldView = AiMockWorldView.new(0)
	v.add_player(0, "roster.napc.vanilla", Vector2i(15, 15))
	v.add_player(1, "roster.nec.vanilla", Vector2i(25, 15))
	v.add_player(2, "roster.def.vanilla", Vector2i(90, 90))
	var ctx: AiContext = AiMockWorldView.make_ctx(v)
	ctx.tick = 100
	ctx.kb.update_primary(ctx)
	t.eq(ctx.kb.primary_enemy(), 1, "the near enemy")
	# hysteresis: inside 3600 ticks the primary stays unless another scores 25 more
	ctx.tick = 400
	ctx.kb.note_hostile(2, 390)
	ctx.kb.update_primary(ctx)
	t.eq(ctx.kb.primary_enemy(), 1, "hysteresis keeps the current primary")
	ctx.tick = 4000
	ctx.kb.update_primary(ctx)
	t.eq(ctx.kb.primary_enemy(), 1, "still the closest after the window")
