class_name AiOpDefend
extends AiOp
## Reactive defense at a threatened site (ai.md 5.8.4): the units claimed by AiDefense attack-move at the visible enemies near
## the site (kept within a leash of the site) and go back to the staging point once no armed enemy has been within 20 cells for
## 200 ticks. Priority 90 for the HQ / production / superweapon sites, 70 for outposts.

const CALM_TICKS: int = 200
const LEASH: int = 22 * Fp.CELL

var site_x: int = 0
var site_y: int = 0
var key_site: bool = true
var unit_ids: PackedInt32Array = PackedInt32Array()
var calm_since: int = 0
var reported: bool = false
var enemies_seen: int = 0
var _ord_tick: int = AiTypes.NEVER
var _ord_x: int = -1
var _ord_y: int = -1


func setup_defense(x: int, y: int, key: bool, unit_list: PackedInt32Array) -> void:
	type = AiTypes.OpType.DEFEND
	site_x = x
	site_y = y
	tx = x
	ty = y
	key_site = key
	unit_ids = unit_list.duplicate()
	priority = 90 if key else 70


func start(ctx: AiContext) -> bool:
	var b: AiBrain = ctx.brain as AiBrain
	var sq: AiSquad = b.squads().create(AiTypes.SquadKind.DEFENSE, id)
	sq.prio = priority
	squads.append(sq.id)
	if b.assign_units(ctx, sq, unit_ids) == 0:
		return false
	committed_value = sq.value
	period = 10
	calm_since = ctx.tick
	timeout_tick = ctx.tick + 6000
	set_state(ctx, AiTypes.OpState.ENGAGING)
	return true


## The squad the op owns (extra units are claimed straight into it).
func squad(ctx: AiContext) -> AiSquad:
	if squads.is_empty():
		return null
	return (ctx.brain as AiBrain).squads().squad(squads[0])


func update(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	measure(ctx, budget)
	if alive == 0:
		release(ctx)
		state = AiTypes.OpState.DONE
		return
	var rows: PackedInt32Array = PackedInt32Array()
	var n: int = AiForce.armed_enemy_rows(ctx, site_x, site_y, 20 * Fp.CELL, 100, rows)
	budget.spend(2 + n)
	if n > 0:
		calm_since = ctx.tick
		enemies_seen = maxi(enemies_seen, n)
		var t: AiEntityTable = ctx.kb.enemy_units
		var sx: int = 0
		var sy: int = 0
		for r: int in rows:
			sx += t.x[r]
			sy += t.y[r]
		sx /= n
		sy /= n
		var d: int = AiForce.dist(sx, sy, site_x, site_y)
		if d > LEASH:
			sx = site_x + (sx - site_x) * LEASH / d
			sy = site_y + (sy - site_y) * LEASH / d
		tx = sx
		ty = sy
		if ctx.tick - _ord_tick >= 80 or AiForce.dist(tx, ty, _ord_x, _ord_y) > 8 * Fp.CELL:
			if ctx.cmd.attack_move(free_ids(ctx, ids), tx, ty):
				_ord_tick = ctx.tick
				_ord_x = tx
				_ord_y = ty
		return
	if ctx.tick - calm_since >= CALM_TICKS:
		var pr: AiProduction = b.eco().production
		ctx.cmd.move(ids, pr.stage_x, pr.stage_y)
		release(ctx)
		state = AiTypes.OpState.DONE


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), site_x, site_y, calm_since, enemies_seen]))
