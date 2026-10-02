class_name AiScout
extends RefCounted
## Scouting (ai.md 5.8.6), slot 14 (every 20 ticks). `scout_level` 0 (Easy): one scout at 300 s to the nearest enemy start;
## 1 (Medium): the first scout at about 90 s to the nearest enemy start, then the expansion sites every 240 s; 2 (Hard): two
## scouts cycling the enemy starts, the deposit fields and unexplored 8-cell blocks; 3 (Brutal): omniscient, no scouting.
## Safety: scouts only `move` (never attack-move), retreat when an armed enemy is within 10 cells, give a target up after 1800
## ticks and skip targets that are in sight. The scout is a SCOUT_LIGHT unit of the reserve; from `fallback_s` later the
## cheapest ground combat unit of the reserve is used when the roster has no scout unit yet.

const ARRIVE: int = 8 * Fp.CELL
const DANGER: int = 10 * Fp.CELL
const TARGET_TIMEOUT: int = 1800
const BLOCK: int = 8
const BLOCKS_PER_PASS: int = 64

var scouts: Array[Dictionary] = []  ## {eid, sq, tx, ty, since, flee, key}
var visited: Dictionary = {}  ## target key -> tick it was visited / abandoned
var launched: int = 0
var lost: int = 0
var visits: int = 0
var _next_launch: int = 0
var _cursor: int = 0
var _tmp: PackedInt32Array = PackedInt32Array()


func setup(_ctx: AiContext) -> void:
	pass


func step(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	var lvl: int = ctx.diff.scout_level
	if b == null or lvl >= 3 or not budget.spend(3):
		return
	_update_scouts(ctx, b, budget)
	var want: int = 2 if lvl >= 2 else 1
	var start_s: int = ctx.tune("scout.start_s.%d" % lvl, 300 if lvl == 0 else 90)
	if scouts.size() < want and ctx.tick >= start_s * SimConfig.TPS and ctx.tick >= _next_launch:
		_launch(ctx, b, budget, start_s)


func _launch(ctx: AiContext, b: AiBrain, budget: AiBudget, start_s: int) -> void:
	var eco: AiEconomy = b.eco()
	var res: AiSquad = eco.squads.reserve
	if res == null or not budget.spend(4 + res.units.size() / 4):
		return
	var t: AiEntityTable = ctx.kb.own
	var best: int = -1
	var best_d: int = 1 << 60
	for eid: int in res.units:
		var r: int = t.row(eid)
		if r < 0 or (t.role_mask[r] & (1 << AiTypes.R_SCOUT_LIGHT)) == 0 or AiForce.is_sea(ctx, t.def[r]) or AiForce.is_air(ctx, t.def[r]):
			continue
		var dx: int = t.x[r] - ctx.kb.sites.home_x
		var dy: int = t.y[r] - ctx.kb.sites.home_y
		if dx * dx + dy * dy < best_d:
			best_d = dx * dx + dy * dy
			best = eid
	if best < 0 and ctx.tick >= (start_s + ctx.tune("scout.fallback_s", 90)) * SimConfig.TPS:
		var best_cost: int = 1 << 30
		for eid2: int in res.units:
			var r2: int = t.row(eid2)
			if r2 < 0 or AiForce.is_sea(ctx, t.def[r2]) or AiForce.is_air(ctx, t.def[r2]):
				continue
			var p: AiUnitProfile = ctx.unit_profile(t.def[r2])
			if p != null and p.cost < best_cost and (t.role_mask[r2] & (1 << AiTypes.R_HEALER)) == 0:
				best_cost = p.cost
				best = eid2
	if best < 0:
		_next_launch = ctx.tick + 100
		return
	var tgt: PackedInt32Array = _pick_target(ctx, budget, t.x[t.row(best)], t.y[t.row(best)])
	if tgt.is_empty():
		_next_launch = ctx.tick + 1200
		return
	var sq: AiSquad = eco.squads.create(AiTypes.SquadKind.SCOUT, -1)
	sq.prio = 30
	b.assign_units(ctx, sq, PackedInt32Array([best]))
	scouts.append({"eid": best, "sq": sq.id, "tx": tgt[0], "ty": tgt[1], "since": ctx.tick, "flee": false, "key": tgt[2]})
	launched += 1
	_next_launch = ctx.tick + 200
	ctx.telemetry.emit_first(AiTypes.Tele.FIRST_SCOUT_SENT, tgt[0] >> Fp.CELL_SHIFT, tgt[1] >> Fp.CELL_SHIFT, ctx.tick)
	ctx.cmd.move(PackedInt32Array([best]), tgt[0], tgt[1])


func _update_scouts(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	var t: AiEntityTable = ctx.kb.own
	var i: int = scouts.size() - 1
	while i >= 0:
		var s: Dictionary = scouts[i]
		var r: int = t.row(int(s["eid"]))
		if r < 0:
			# killed: the target is not tried again for a while
			lost += 1
			visited[int(s["key"])] = ctx.tick + 1800
			b.squads().release(int(s["sq"]), true)
			scouts.remove_at(i)
			i -= 1
			continue
		if not budget.spend(3):
			return
		var x: int = t.x[r]
		var y: int = t.y[r]
		var eid: int = int(s["eid"])
		if bool(s["flee"]):
			if AiForce.dist(x, y, ctx.kb.sites.home_x, ctx.kb.sites.home_y) <= 10 * Fp.CELL or ctx.tick - int(s["since"]) > 600:
				_retarget(ctx, b, budget, s, i)
			i -= 1
			continue
		var danger: int = AiForce.armed_enemy_rows(ctx, x, y, DANGER, 60, _tmp)
		if danger > 0:
			s["flee"] = true
			s["since"] = ctx.tick
			visited[int(s["key"])] = ctx.tick
			ctx.cmd.move(PackedInt32Array([eid]), ctx.kb.sites.home_x, ctx.kb.sites.home_y)
			i -= 1
			continue
		var tx: int = int(s["tx"])
		var ty: int = int(s["ty"])
		var arrived: bool = AiForce.dist(x, y, tx, ty) <= ARRIVE
		if arrived or ctx.tick - int(s["since"]) > TARGET_TIMEOUT or ctx.view.cell_visible(tx >> Fp.CELL_SHIFT, ty >> Fp.CELL_SHIFT) and ctx.view.cell_explored(tx >> Fp.CELL_SHIFT, ty >> Fp.CELL_SHIFT) and AiForce.dist(x, y, tx, ty) <= 12 * Fp.CELL:
			visited[int(s["key"])] = ctx.tick
			visits += 1
			_retarget(ctx, b, budget, s, i)
		i -= 1


## Next target for a scout that finished (or fled): a new order, or the scout goes back into the reserve.
func _retarget(ctx: AiContext, b: AiBrain, budget: AiBudget, s: Dictionary, idx: int) -> void:
	var t: AiEntityTable = ctx.kb.own
	var r: int = t.row(int(s["eid"]))
	if r < 0:
		return
	var tgt: PackedInt32Array = _pick_target(ctx, budget, t.x[r], t.y[r])
	if tgt.is_empty():
		ctx.cmd.move(PackedInt32Array([int(s["eid"])]), ctx.kb.sites.home_x, ctx.kb.sites.home_y)
		b.squads().release(int(s["sq"]), true)
		scouts.remove_at(idx)
		_next_launch = ctx.tick + ctx.tune("scout.recheck_s", 240) * SimConfig.TPS
		return
	s["tx"] = tgt[0]
	s["ty"] = tgt[1]
	s["key"] = tgt[2]
	s["since"] = ctx.tick
	s["flee"] = false
	ctx.cmd.move(PackedInt32Array([int(s["eid"])]), tgt[0], tgt[1])


## Least recently visited eligible target: enemy starts first, then deposit fields, then (Hard) unexplored blocks.
## Returns [x, y, key] or empty.
func _pick_target(ctx: AiContext, budget: AiBudget, from_x: int, from_y: int) -> PackedInt32Array:
	var kb: AiKnowledge = ctx.kb
	var recheck: int = ctx.tune("scout.recheck_s", 240) * SimConfig.TPS
	var cand: Array[PackedInt32Array] = []
	var es: PackedInt32Array = kb.enemy_starts
	for i: int in es.size() / 2:
		cand.append(PackedInt32Array([es[2 * i] * Fp.CELL + Fp.CELL / 2, es[2 * i + 1] * Fp.CELL + Fp.CELL / 2, 1000 + i, 0]))
	var sites: AiResourceSites = kb.sites
	for j: int in sites.count:
		if sites.kind[j] == AiResourceSites.K_MAIN:
			continue
		cand.append(PackedInt32Array([sites.x[j], sites.y[j], 2000 + j, 1]))
	if ctx.diff.scout_level >= 2:
		var blocks: int = _unexplored_block(ctx, budget)
		if blocks >= 0:
			cand.append(PackedInt32Array([blocks % 4096 * Fp.CELL, blocks / 4096 * Fp.CELL, 100000 + blocks, 2]))
	budget.spend(2 + cand.size())
	var best: int = -1
	var best_score: int = -(1 << 60)
	for k: int in cand.size():
		var c: PackedInt32Array = cand[k]
		var last: int = int(visited.get(c[2], AiTypes.NEVER))
		if ctx.tick - last < recheck:
			continue
		if ctx.view.cell_visible(c[0] >> Fp.CELL_SHIFT, c[1] >> Fp.CELL_SHIFT):
			continue
		var d: int = AiForce.cells(from_x, from_y, c[0], c[1])
		# enemy starts before fields before blocks; then the nearest one
		var score: int = (2 - c[3]) * 100000 - d
		if score > best_score:
			best_score = score
			best = k
	if best < 0:
		return PackedInt32Array()
	return PackedInt32Array([cand[best][0], cand[best][1], cand[best][2]])


## Centre (packed cx + cy * 4096, in cells) of a block that is passable but unexplored; the sampling cursor advances 64 blocks
## per pass. -1 when none was found.
func _unexplored_block(ctx: AiContext, budget: AiBudget) -> int:
	var v: AiWorldView = ctx.view
	var bw: int = (v.map_w() + BLOCK - 1) / BLOCK
	var bh: int = (v.map_h() + BLOCK - 1) / BLOCK
	var total: int = bw * bh
	budget.spend(1 + BLOCKS_PER_PASS / 4)
	var route: AiRouteGraph = ctx.kb.route
	for _n: int in mini(BLOCKS_PER_PASS, total):
		var blk: int = _cursor % total
		_cursor += 1
		var cxc: int = (blk % bw) * BLOCK + BLOCK / 2
		var cyc: int = (blk / bw) * BLOCK + BLOCK / 2
		if not v.cell_explored(cxc, cyc) and route.block_open(cxc * Fp.CELL, cyc * Fp.CELL, AiTypes.MoveClass.TRACKED):
			return cxc + cyc * 4096
	return -1


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([launched, lost, visits, scouts.size(), _next_launch, visited.size()])
	for s: Dictionary in scouts:
		v.append(int(s["eid"]))
		v.append(int(s["tx"]))
	return AiRng.hash_ints(v)
