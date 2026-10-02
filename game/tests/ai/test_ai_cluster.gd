extends RefCounted
## AiCluster over a scripted knowledge base (ai.md 10.1 test_ai_cluster).

const C: int = Fp.CELL


func _ctx() -> AiContext:
	var v: AiMockWorldView = AiMockWorldView.new(0)
	v.add_player(0, "roster.napc.vanilla", Vector2i(15, 15))
	v.add_player(1, "roster.nec.vanilla", Vector2i(80, 80))
	return AiMockWorldView.make_ctx(v)


func _ghost(ctx: AiContext, id: int, cx: int, cy: int, value: int = 2000) -> void:
	ctx.kb.ghosts.upsert(id, 22, 1, cx * C, cy * C, 0, 100, 0, AiTypes.StructKind.FACTORY, value)


func test_best_circle_centres_on_the_middle_factory(t: TestCtx) -> void:
	var ctx: AiContext = _ctx()
	for i: int in 3:
		_ghost(ctx, 100 + i, 30 + 3 * i, 40)
	var out: PackedInt32Array = PackedInt32Array()
	var n: int = ctx.kb.cluster.best_circle(ctx, 3 * C, AiCluster.MODE_STRUCT, 2, out)
	t.gt(n, 0)
	t.eq(out[2], 6000, "all three inside one circle")
	t.le(absi(out[0] - 33 * C), C / 2, "centred on the middle factory")
	t.eq(out[1], 40 * C)


func test_best_circle_returns_disjoint_clusters(t: TestCtx) -> void:
	var ctx: AiContext = _ctx()
	_ghost(ctx, 1, 20, 20)
	_ghost(ctx, 2, 21, 20)
	_ghost(ctx, 3, 70, 70, 900)
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(ctx.kb.cluster.best_circle(ctx, 3 * C, AiCluster.MODE_ALL, 3, out), 2, "two clusters found, no more")
	t.eq(out[2], 4000)
	t.eq(out[5], 900)


func test_shape_scores(t: TestCtx) -> void:
	var ctx: AiContext = _ctx()
	for i: int in 3:
		_ghost(ctx, 100 + i, 30 + 3 * i, 40)
	# Atlas-like: three circles at offsets 0 / -3 / +3 cells along the axis
	var atlas: Array = []
	for off: int in [0, -3, 3]:
		atlas.append({"t": "c", "dx": off * C, "dy": 0, "r": C, "w": 256})
	var cl: AiCluster = ctx.kb.cluster
	t.eq(cl.score_shape(ctx, atlas, 33 * C, 40 * C, 0, AiCluster.MODE_STRUCT), 6000, "3 x 2000 when centred")
	t.eq(cl.score_shape(ctx, atlas, 30 * C, 40 * C, 0, AiCluster.MODE_STRUCT), 4000, "two circles hit when off-centre")
	# rotated 90 degrees the row is no longer covered
	t.eq(cl.score_shape(ctx, atlas, 33 * C, 40 * C, 1024, AiCluster.MODE_STRUCT), 2000, "only the centre circle hits")
	# Helios-like rectangle over the row
	var helios: Array = [{"t": "r", "dx": 0, "dy": 0, "len": 6 * C, "hw": C, "w": 256}]
	t.eq(cl.score_shape(ctx, helios, 33 * C, 40 * C, 0, AiCluster.MODE_STRUCT), 6000)
	t.eq(cl.score_shape(ctx, helios, 33 * C, 40 * C, 1024, AiCluster.MODE_STRUCT), 2000, "rotated rectangle covers one")
	# Perun-like core 1.0 + ring 0.35
	var perun: Array = [{"t": "c", "r": C, "w": 256}, {"t": "a", "r0": 2 * C, "r1": 4 * C, "w": 90}]
	t.eq(cl.score_shape(ctx, perun, 33 * C, 40 * C, 0, AiCluster.MODE_STRUCT), 2000 + 2 * 2000 * 90 / 256, "core + weighted ring")


func test_value_grid(t: TestCtx) -> void:
	var ctx: AiContext = _ctx()
	_ghost(ctx, 1, 10, 10)
	_ghost(ctx, 2, 11, 10)
	var grid: PackedInt32Array = PackedInt32Array()
	ctx.kb.cluster.value_grid(ctx, 0x02, grid)
	var cl: AiCluster = ctx.kb.cluster
	t.eq(grid.size(), cl.grid_w * cl.grid_h)
	t.eq(grid[(10 * C / (3 * C)) * cl.grid_w + 10 * C / (3 * C)], 4000, "both factories in the 3-cell block")
	var total: int = 0
	for v: int in grid:
		total += v
	t.eq(total, 4000)
