class_name AiOpHunt
extends AiOp
## End-game sweep (ai.md 5.8.6): when the primary enemy lives but no structure of it is known, a few fast combat units attack-move
## over the map blocks in descending order of (staleness, closeness to the enemy start) until a structure ghost appears, which
## hands the job back to the attack planner. This guarantees that a match terminates. Blocks are 8x8 cells; a block is "seen"
## when it was visible at the last check.

const BLOCK: int = 8
const MAX_UNITS: int = 6
const TIMEOUT_PER_BLOCK: int = 900

var visited: PackedInt32Array = PackedInt32Array()  ## per block: tick it was last seen (NEVER = unexplored)
var bw: int = 0
var bh: int = 0
var block: int = -1
var block_since: int = 0
var blocks_done: int = 0
var found: bool = false


func start(ctx: AiContext) -> bool:
	type = AiTypes.OpType.HUNT
	priority = 35
	var b: AiBrain = ctx.brain as AiBrain
	var eco: AiEconomy = b.eco()
	var res: AiSquad = eco.squads.reserve
	if res == null:
		return false
	var t: AiEntityTable = ctx.kb.own
	var keys: PackedInt64Array = PackedInt64Array()
	for eid: int in res.units:
		var r: int = t.row(eid)
		if r < 0 or AiForce.is_sea(ctx, t.def[r]) or AiForce.is_air(ctx, t.def[r]):
			continue
		var p: AiUnitProfile = ctx.unit_profile(t.def[r])
		if p == null:
			continue
		# fastest first: key = (1000000 - speed) so that ascending sort puts the fast ones in front
		keys.append((maxi(1000000 - p.speed, 0) << 24) | (eid & 0xFFFFFF))
	if keys.is_empty():
		return false
	keys.sort()
	var pick: PackedInt32Array = PackedInt32Array()
	for k: int in keys:
		if pick.size() >= MAX_UNITS:
			break
		pick.append(k & 0xFFFFFF)
	var sq: AiSquad = eco.squads.create(AiTypes.SquadKind.SCOUT, id)
	sq.prio = priority
	squads.append(sq.id)
	b.assign_units(ctx, sq, pick)
	bw = (ctx.view.map_w() + BLOCK - 1) / BLOCK
	bh = (ctx.view.map_h() + BLOCK - 1) / BLOCK
	visited.resize(bw * bh)
	visited.fill(AiTypes.NEVER)
	period = maxi(20, ctx.diff.think_period_ticks)
	timeout_tick = ctx.tick + 12000
	set_state(ctx, AiTypes.OpState.ADVANCING)
	return true


func update(ctx: AiContext, budget: AiBudget) -> void:
	measure(ctx, budget)
	if alive == 0:
		release(ctx)
		state = AiTypes.OpState.DONE
		return
	# a real structure of the enemy is known again: the planner takes over
	var g: AiGhostTable = ctx.kb.ghosts
	for i: int in g.count:
		if g.eid[i] > 0 and g.owner[i] >= 0 and ctx.view.player_alive(g.owner[i]):
			found = true
	if found or ctx.kb.primary < 0:
		release(ctx)
		state = AiTypes.OpState.DONE
		return
	_stamp_visible(ctx, budget)
	if block < 0 or ctx.tick - block_since >= TIMEOUT_PER_BLOCK or _at_block():
		if block >= 0:
			visited[block] = ctx.tick
			blocks_done += 1
		block = _pick_block(ctx, budget)
		block_since = ctx.tick
		if block < 0:
			release(ctx)
			state = AiTypes.OpState.DONE
			return
		ctx.cmd.attack_move(ids, _bx(block), _by(block))


func _bx(b: int) -> int:
	return ((b % bw) * BLOCK + BLOCK / 2) * Fp.CELL


func _by(b: int) -> int:
	return ((b / bw) * BLOCK + BLOCK / 2) * Fp.CELL


func _at_block() -> bool:
	return block >= 0 and AiForce.dist(cx, cy, _bx(block), _by(block)) <= 5 * Fp.CELL


## Blocks whose centre cell is in sight are seen now.
func _stamp_visible(ctx: AiContext, budget: AiBudget) -> void:
	var n: int = bw * bh
	budget.spend(1 + n / 8)
	for b: int in n:
		if ctx.view.cell_visible(_bx(b) >> Fp.CELL_SHIFT, _by(b) >> Fp.CELL_SHIFT):
			visited[b] = ctx.tick


## Highest (staleness, closeness to an enemy start, closeness to the squad) among the passable blocks.
func _pick_block(ctx: AiContext, budget: AiBudget) -> int:
	var route: AiRouteGraph = ctx.kb.route
	var es: PackedInt32Array = ctx.kb.enemy_starts
	var best: int = -1
	var best_s: int = -(1 << 60)
	budget.spend(2 + bw * bh / 4)
	for b: int in bw * bh:
		if not route.block_open(_bx(b), _by(b), AiTypes.MoveClass.TRACKED):
			continue
		var age: int = mini(ctx.tick - visited[b], 9000) if visited[b] > AiTypes.NEVER else 9000
		var de: int = 1 << 20
		for i: int in es.size() / 2:
			de = mini(de, AiForce.cells(_bx(b), _by(b), es[2 * i] * Fp.CELL, es[2 * i + 1] * Fp.CELL))
		var dsq: int = AiForce.cells(_bx(b), _by(b), cx, cy)
		var s: int = age / 6 - de * 8 - dsq * 2
		if b == block:
			s -= 100000
		if s > best_s:
			best_s = s
			best = b
	return best


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), block, blocks_done, 1 if found else 0]))
