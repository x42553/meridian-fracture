class_name AiOpHarass
extends AiOp
## Small fast raid group against collectors and outlying economy (ai.md 5.8.5, lean): 3-5 SCOUT_LIGHT / KITER units. Targets in
## order: enemy Collectors seen in the last 60 s, Refineries, Generators. A target is dropped when the threat within 10 cells
## exceeds 70 % of the squad power. Cycle: approach (attack-move) -> engage <= 160 ticks -> retreat 15 cells when the squad is
## below 70 % hp or outmatched (ratio < 0.8) -> wait 400 ticks -> pick again. Ends when nothing to raid for 600 ticks or the
## squad is gone.

const MIN_UNITS: int = 3
const MAX_UNITS: int = 5
const ENGAGE_TICKS: int = 160
const WAIT_TICKS: int = 400
const IDLE_END_TICKS: int = 600

var target_eid: int = -1
var target_unit: bool = false
var kills_seen: int = 0
var engage_since: int = 0
var rest_until: int = 0
var idle_since: int = -1
var raids: int = 0
var _ord_tick: int = AiTypes.NEVER


func start(ctx: AiContext) -> bool:
	type = AiTypes.OpType.HARASS
	priority = 45
	var b: AiBrain = ctx.brain as AiBrain
	var eco: AiEconomy = b.eco()
	var res: AiSquad = eco.squads.reserve
	if res == null:
		return false
	var t: AiEntityTable = ctx.kb.own
	var mask: int = (1 << AiTypes.R_SCOUT_LIGHT) | (1 << AiTypes.R_KITER)
	var keys: PackedInt64Array = PackedInt64Array()
	for eid: int in res.units:
		var r: int = t.row(eid)
		if r < 0 or (t.role_mask[r] & mask) == 0 or AiForce.is_air(ctx, t.def[r]) or AiForce.is_sea(ctx, t.def[r]):
			continue
		if (t.role_mask[r] & (1 << AiTypes.R_BOMBER)) != 0:
			continue
		var dx: int = t.x[r] - ctx.kb.sites.home_x
		var dy: int = t.y[r] - ctx.kb.sites.home_y
		keys.append((mini((dx * dx + dy * dy) / 1024, 0x3FFFFFFF) << 24) | (eid & 0xFFFFFF))
	if keys.size() < MIN_UNITS:
		return false
	keys.sort()
	var pick: PackedInt32Array = PackedInt32Array()
	for k: int in keys:
		if pick.size() >= MAX_UNITS:
			break
		pick.append(k & 0xFFFFFF)
	var sq: AiSquad = eco.squads.create(AiTypes.SquadKind.HARASS, id)
	sq.prio = priority
	squads.append(sq.id)
	b.assign_units(ctx, sq, pick)
	period = maxi(10, ctx.diff.think_period_ticks)
	timeout_tick = ctx.tick + 9000
	set_state(ctx, AiTypes.OpState.FORMING)
	return true


func update(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	measure(ctx, budget)
	if alive == 0:
		release(ctx)
		state = AiTypes.OpState.DONE
		return
	match state:
		AiTypes.OpState.FORMING:
			_choose(ctx, budget)
		AiTypes.OpState.ADVANCING:
			_advance(ctx, budget)
		AiTypes.OpState.ENGAGING:
			_engage(ctx, budget)
		AiTypes.OpState.RETREATING:
			_retreat(ctx)
	if state == AiTypes.OpState.FORMING and idle_since >= 0 and ctx.tick - idle_since >= IDLE_END_TICKS:
		_end(ctx, b)


func _end(ctx: AiContext, b: AiBrain) -> void:
	var pr: AiProduction = b.eco().production
	ctx.cmd.move(ids, pr.stage_x, pr.stage_y)
	release(ctx)
	state = AiTypes.OpState.DONE


## Picks the next target: exposed collectors, then refineries, then generators (nearest first, safe ones only).
func _choose(ctx: AiContext, budget: AiBudget) -> void:
	if ctx.tick < rest_until:
		return
	var kb: AiKnowledge = ctx.kb
	var pid: int = kb.primary
	var power: int = AiForce.power_of(ctx, ids)
	var best_x: int = -1
	var best_y: int = -1
	var best_e: int = -1
	var best_u: bool = false
	var have: bool = false
	var best_d: int = 1 << 60
	var t: AiEntityTable = kb.enemy_units
	budget.spend(2 + t.count / 4 + kb.ghosts.count / 4)
	var safe_limit: int = power * 7 / 10
	for i: int in t.count:
		if (t.owner[i] != pid and pid >= 0) or (t.role_mask[i] & (1 << AiTypes.R_COLLECTOR)) == 0 or ctx.tick - t.last_seen[i] > 60 * SimConfig.TPS:
			continue
		if kb.threat_circle(t.x[i], t.y[i], 10 * Fp.CELL) > safe_limit:
			continue
		var d: int = (t.x[i] - cx) * (t.x[i] - cx) + (t.y[i] - cy) * (t.y[i] - cy)
		if d < best_d:
			best_d = d
			best_x = t.x[i]
			best_y = t.y[i]
			best_e = t.eid[i]
			best_u = true
			have = true
	if not have:
		for kind: int in [AiTypes.StructKind.REFINERY, AiTypes.StructKind.GENERATOR]:
			for j: int in kb.ghosts.count:
				var g: AiGhostTable = kb.ghosts
				if g.kind[j] != kind or g.owner[j] < 0 or (g.owner[j] != pid and pid >= 0):
					continue
				if kb.threat_circle(g.x[j], g.y[j], 10 * Fp.CELL) > safe_limit:
					continue
				var d2: int = (g.x[j] - cx) * (g.x[j] - cx) + (g.y[j] - cy) * (g.y[j] - cy)
				if d2 < best_d:
					best_d = d2
					best_x = g.x[j]
					best_y = g.y[j]
					best_e = g.eid[j]
					best_u = false
					have = true
			if have:
				break
	if not have:
		if idle_since < 0:
			idle_since = ctx.tick
		return
	idle_since = -1
	tx = best_x
	ty = best_y
	target_eid = best_e
	target_unit = best_u
	raids += 1
	set_state(ctx, AiTypes.OpState.ADVANCING)
	_go(ctx)


func _go(ctx: AiContext) -> void:
	if ctx.cmd.attack_move(free_ids(ctx, ids), tx, ty):
		_ord_tick = ctx.tick


func _advance(ctx: AiContext, budget: AiBudget) -> void:
	var power: int = AiForce.power_of(ctx, ids)
	if ctx.kb.threat_circle(tx, ty, 10 * Fp.CELL) > power * 7 / 10:
		_pull_back(ctx)  # the target is guarded: give up on it
		return
	if AiForce.dist(cx, cy, tx, ty) <= 10 * Fp.CELL or _enemy_near(ctx, budget):
		engage_since = ctx.tick
		set_state(ctx, AiTypes.OpState.ENGAGING)
		_go(ctx)
		return
	if ctx.tick - _ord_tick >= 80:
		_go(ctx)


func _enemy_near(ctx: AiContext, budget: AiBudget) -> bool:
	var rows: PackedInt32Array = PackedInt32Array()
	budget.spend(2)
	return AiForce.armed_enemy_rows(ctx, cx, cy, 8 * Fp.CELL, 100, rows) > 0


func _engage(ctx: AiContext, budget: AiBudget) -> void:
	var rows: PackedInt32Array = PackedInt32Array()
	var n: int = AiForce.armed_enemy_rows(ctx, cx, cy, 12 * Fp.CELL, 100, rows)
	budget.spend(2 + n)
	if hp_frac_q8 * 100 < 70 * 256:
		_pull_back(ctx)
		return
	if n > 0:
		var mine: AiStrengthGroup = AiForce.own_group(ctx, ids)
		var theirs: AiStrengthGroup = AiForce.enemy_group(ctx, cx, cy, 12 * Fp.CELL, 100)
		if AiForce.ratio(ctx, mine, theirs, id) < 80 * 256 / 100:
			_pull_back(ctx)
			return
	if ctx.tick - engage_since >= ENGAGE_TICKS:
		_pull_back(ctx)
		return
	if ctx.tick - _ord_tick >= 60:
		_go(ctx)


## Retreats 15 cells back towards the base and rests before the next raid.
func _pull_back(ctx: AiContext) -> void:
	var hx: int = ctx.kb.sites.home_x
	var hy: int = ctx.kb.sites.home_y
	var d: int = maxi(AiForce.dist(cx, cy, hx, hy), 1)
	var back: int = mini(15 * Fp.CELL, d)
	var rx: int = cx + (hx - cx) * back / d
	var ry: int = cy + (hy - cy) * back / d
	ctx.cmd.move(ids, rx, ry)
	ctx.telemetry.emit(AiTypes.Tele.RETREAT_ORDERED, ids.size(), 1, ctx.tick)
	rest_until = ctx.tick + WAIT_TICKS
	set_state(ctx, AiTypes.OpState.RETREATING)


func _retreat(ctx: AiContext) -> void:
	if ctx.tick >= rest_until:
		set_state(ctx, AiTypes.OpState.FORMING)


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), raids, rest_until, target_eid]))
