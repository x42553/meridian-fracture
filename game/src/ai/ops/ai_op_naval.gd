class_name AiOpNaval
extends AiOp
## Fleet operations (ai.md 5.10.3). One standing op per AI owns the ships of the reserve (ships never join the ground waves):
## a fleet needs ESCORT_SHIPs (>= 2) and light boats; siege ships, carriers and submarines only sail with >= 2 escorts.
## Tasks, in order: (1) escort a landing (the fleet goes to the water next to the landing zone), (2) kill enemy ships within 30 cells
## of my coast / docks, (3) bombard a coastal enemy structure ghost inside the reach of my siege ships, (4) wait at the anchor
## (my Dock). Launch ratio 1.3, abort ratio 0.7 on the strength of the naval groups (defense structures near the target count for
## the enemy). The anchor is the water cell next to my Dock; without a Dock the op does not start.

const PERIOD: int = 40
const COAST_CELLS: int = 30
const MIN_ESCORTS: int = 2

var anchor_x: int = 0
var anchor_y: int = 0
var task: int = 0  ## 0 anchor, 1 hunt ships, 2 bombard, 3 escort landing
var task_x: int = 0
var task_y: int = 0
var bombard_eid: int = 0
var bombard_x: int = 0
var bombard_y: int = 0
var hunts: int = 0
var bombards: int = 0
var escorts_done: int = 0
var retreats: int = 0
var _last_order: int = AiTypes.NEVER
var _last_fire: int = AiTypes.NEVER
var _sq_id: int = -1
var _empty_since: int = AiTypes.NEVER
var _rest_until: int = 0


static func fleet_mask() -> int:
	return (1 << AiTypes.R_BOAT_LIGHT) | (1 << AiTypes.R_ESCORT_SHIP) | (1 << AiTypes.R_SIEGE_SHIP) | (1 << AiTypes.R_CARRIER) | (1 << AiTypes.R_SUBMARINE)


## Nearest water cell (naval-passable) to the point as a sub-cell point; the input point when none within `radius` cells.
static func water_near(ctx: AiContext, x: int, y: int, radius: int = 10) -> PackedInt32Array:
	return AiOpKit.snap(ctx, x, y, AiTypes.MoveClass.NAVAL, radius)


## Water policy (ai.md 5.10.1): a Dock is wanted when one can be placed AND (a) naval doctrine: personality naval >= 30 on a map
## with water, (b) the primary enemy cannot be reached over land, or (c) a TRANSPORT_ASSAULT roster finds a water route at least
## 25 % shorter than the land route. Docks are never built for any other reason (land maps never see one). Checked every 1200 ticks.
static func ensure_dock(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	if ctx.tick < b.dock_block_until or not budget.spend(6):
		return
	b.dock_block_until = ctx.tick + 1200
	var dock: int = ctx.res.structure_of_kind(AiTypes.StructKind.DOCK)
	var eco: AiEconomy = b.eco()
	if dock < 0 or eco.struct_own[dock] + eco.struct_q[dock] > 0 or not eco.opener_done() or eco.planner.tier(ctx) < 2:
		return
	if ctx.view.credits() < ctx.tune("naval.dock_min_credits", 500) or not eco.placer.dock_placeable(ctx):  # AIT: the economy-first AI rarely holds 1200
		return
	var why: int = 0
	if ctx.pers.naval >= 30 and eco.comp.water_pct > 0:
		why = 1
	elif ctx.kb.primary >= 0:
		var hq: PackedInt32Array = PackedInt32Array()
		if ctx.kb.enemy_hq(ctx.kb.primary, hq):
			var route: AiRouteGraph = ctx.kb.route
			var hx: int = ctx.kb.sites.home_x
			var hy: int = ctx.kb.sites.home_y
			if not route.connected(hx, hy, hq[0], hq[1], AiTypes.MoveClass.TRACKED):
				why = 2
			elif ctx.pers.has_flag(AiTypes.doctrine_bit("TRANSPORT_ASSAULT")):
				var land: PackedInt32Array = PackedInt32Array()
				var wet: PackedInt32Array = PackedInt32Array()
				var nl: int = route.route(hx, hy, hq[0], hq[1], AiTypes.MoveClass.TRACKED, route.threat_weight_q8, land)
				var nw: int = route.route(hx, hy, hq[0], hq[1], AiTypes.MoveClass.AMPHIBIOUS, route.threat_weight_q8, wet)
				budget.spend(30)
				if nl > 0 and nw > 0 and route.route_cells(wet) * 100 <= route.route_cells(land) * 75:
					why = 3
	if why == 0:
		return
	var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, dock, -1, 1, AiEconomy.P_TECH, AiTypes.WantOrigin.ARMY)
	w.deadline = ctx.tick + 1800
	b.add_want(w)
	b.bump("dock_wanted_%d" % why)


static func try_launch(ctx: AiContext, b: AiBrain, _budget: AiBudget) -> bool:
	if b.count_ops(AiTypes.OpType.NAVAL) > 0 or ctx.tick < b.naval_block_until or b.desperate:
		return false
	var t: AiEntityTable = ctx.kb.own
	var esc: int = 0
	var boats: int = 0
	for eid: int in b.squads().reserve.units:
		var r: int = t.row(eid)
		if r < 0:
			continue
		if (t.role_mask[r] & (1 << AiTypes.R_ESCORT_SHIP)) != 0:
			esc += 1
		elif (t.role_mask[r] & (1 << AiTypes.R_BOAT_LIGHT)) != 0:
			boats += 1
	if esc < MIN_ESCORTS and esc + boats < 3:
		b.naval_block_until = ctx.tick + 300
		return false
	var op: AiOpNaval = AiOpNaval.new()
	if b.add_op(ctx, op):
		b.bump("naval_ops")
		ctx.telemetry.emit(AiTypes.Tele.NAVAL_LAUNCHED, esc, boats, ctx.tick)
		return true
	b.naval_block_until = ctx.tick + 600
	return false


func start(ctx: AiContext) -> bool:
	type = AiTypes.OpType.NAVAL
	priority = 45
	var b: AiBrain = ctx.brain as AiBrain
	var dock: int = ctx.res.structure_of_kind(AiTypes.StructKind.DOCK)
	if dock < 0:
		return false
	var t: AiEntityTable = ctx.kb.own
	var dx: int = -1
	var dy: int = -1
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_STRUCTURE and t.def[r] == dock:
			dx = t.x[r]
			dy = t.y[r]
			break
	if dx < 0:
		return false
	var w: PackedInt32Array = water_near(ctx, dx, dy, 12)
	anchor_x = w[0]
	anchor_y = w[1]
	var sm: AiSquadManager = b.squads()
	var sq: AiSquad = sm.create(AiTypes.SquadKind.NAVAL, id)
	sq.prio = priority
	_sq_id = sq.id
	squads.append(sq.id)
	_claim(ctx, b)
	if sq.units.is_empty():
		return false
	period = PERIOD
	timeout_tick = ctx.tick + 24000
	set_state(ctx, AiTypes.OpState.STAGING)
	return true


func _claim(ctx: AiContext, b: AiBrain) -> void:
	var sq: AiSquad = b.squads().squad(_sq_id)
	if sq != null:
		b.squads().claim(fleet_mask(), 99, anchor_x, anchor_y, 0, priority, sq)


func update(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if not budget.spend(6):
		return
	timeout_tick = ctx.tick + 24000
	_claim(ctx, b)
	measure(ctx, budget)
	if alive == 0:
		if _empty_since == AiTypes.NEVER:
			_empty_since = ctx.tick
		elif ctx.tick - _empty_since > 3600:
			release(ctx)
			state = AiTypes.OpState.DONE
		return
	_empty_since = AiTypes.NEVER
	var t: AiEntityTable = ctx.kb.own
	# the sailing part of the fleet: big ships only with >= 2 escorts
	var escorts: int = 0
	var sail: PackedInt32Array = PackedInt32Array()
	for eid: int in ids:
		var r: int = t.row(eid)
		if (t.role_mask[r] & (1 << AiTypes.R_ESCORT_SHIP)) != 0:
			escorts += 1
	var big: int = (1 << AiTypes.R_SIEGE_SHIP) | (1 << AiTypes.R_CARRIER) | (1 << AiTypes.R_SUBMARINE)
	for eid2: int in ids:
		var r2: int = t.row(eid2)
		if escorts >= MIN_ESCORTS or (t.role_mask[r2] & big) == 0:
			sail.append(eid2)
	if sail.is_empty():
		return
	if ctx.tick < _rest_until:
		return
	var mine: AiStrengthGroup = AiForce.own_group(ctx, sail)
	# (1) escort a landing
	var lw: PackedInt32Array = (ctx.brain as AiBrain).landing_watch
	if lw.size() == 3 and ctx.tick - lw[2] < 900:
		var w: PackedInt32Array = water_near(ctx, lw[0], lw[1], 10)
		_set_task(ctx, 3, w[0], w[1])
		_go(ctx, sail, w[0], w[1])
		escorts_done += 1
		return
	# (2) enemy ships near my coast
	var foe: AiStrengthGroup = AiStrengthGroup.new()
	var fx: int = 0
	var fy: int = 0
	var n: int = _enemy_ships(ctx, foe, ctx.kb.sites.home_x, ctx.kb.sites.home_y)
	var fleet_x: int = cx
	var fleet_y: int = cy
	if n > 0:
		var ep: PackedInt32Array = _last_enemy
		fx = ep[0]
		fy = ep[1]
		var ratio: int = AiForce.ratio(ctx, mine, foe, id)
		var need: int = ctx.tune("strength.abort_ratio_x100", 70) * 256 / 100 if task == 1 else ctx.tune("strength.launch_ratio_x100", 130) * 256 / 100
		if ratio >= need:
			var wp: PackedInt32Array = water_near(ctx, fx, fy, 6)
			_set_task(ctx, 1, wp[0], wp[1])
			hunts += 1 if ctx.tick - _last_order > 400 else 0
			_go(ctx, sail, wp[0], wp[1])
			return
		# outmatched: back to the anchor
		if task == 1:
			retreats += 1
			b.bump("naval_retreat")
			_rest_until = ctx.tick + 400
			_set_task(ctx, 0, anchor_x, anchor_y)
			ctx.cmd.move(sail, anchor_x, anchor_y)
			return
	# (3) bombardment of a coastal ghost
	if _bombard(ctx, b, sail, mine):
		return
	# (4) the anchor
	_set_task(ctx, 0, anchor_x, anchor_y)
	if AiForce.dist(fleet_x, fleet_y, anchor_x, anchor_y) > 10 * Fp.CELL and ctx.tick - _last_order > 200:
		_last_order = ctx.tick
		ctx.cmd.move(sail, anchor_x, anchor_y)


var _last_enemy: PackedInt32Array = PackedInt32Array([0, 0])


## Adds the enemy ships within COAST_CELLS of (hx, hy) or of one of my docks to `g`; sets _last_enemy to their centroid. Returns the count.
func _enemy_ships(ctx: AiContext, g: AiStrengthGroup, hx: int, hy: int) -> int:
	var et: AiEntityTable = ctx.kb.enemy_units
	var sx: int = 0
	var sy: int = 0
	var n: int = 0
	var lim: int = COAST_CELLS * Fp.CELL
	for i: int in et.count:
		if ctx.tick - et.last_seen[i] > 100:
			continue
		var p: AiUnitProfile = ctx.unit_profile_of(et.owner[i], et.def[i])
		if p == null or (p.category != AiTypes.Cat.NAVAL and p.category != AiTypes.Cat.SUB) or not p.is_combat():
			continue
		if AiForce.dist(et.x[i], et.y[i], hx, hy) > lim and AiForce.dist(et.x[i], et.y[i], anchor_x, anchor_y) > lim:
			continue
		g.add(p, 1, et.hp[i], p.value * et.hp[i] / maxi(et.hp_max[i], 1))
		sx += et.x[i]
		sy += et.y[i]
		n += 1
	if n > 0:
		_last_enemy = PackedInt32Array([sx / n, sy / n])
	return n


func _bombard(ctx: AiContext, b: AiBrain, sail: PackedInt32Array, mine: AiStrengthGroup) -> bool:
	var t: AiEntityTable = ctx.kb.own
	var reach: int = 0
	var shooters: PackedInt32Array = PackedInt32Array()
	for eid: int in sail:
		var r: int = t.row(eid)
		if r >= 0 and (t.role_mask[r] & (1 << AiTypes.R_SIEGE_SHIP)) != 0:
			shooters.append(eid)
			reach = maxi(reach, ctx.unit_profile(t.def[r]).range)
	if shooters.is_empty() or ctx.kb.primary < 0:
		return false
	var g: AiGhostTable = ctx.kb.ghosts
	var best: int = -1
	var best_s: int = 0
	var best_w: PackedInt32Array = PackedInt32Array()
	for i: int in g.count:
		if g.owner[i] != ctx.kb.primary or g.eid[i] <= 0 or AiForce.is_defense_kind(g.kind[i]):
			continue
		var w: PackedInt32Array = water_near(ctx, g.x[i], g.y[i], reach / Fp.CELL - 1)
		if w[0] == g.x[i] and w[1] == g.y[i]:
			continue  # no water within the ships' reach
		if AiForce.dist(w[0], w[1], g.x[i], g.y[i]) > reach * 9 / 10:
			continue
		if not ctx.kb.route.connected(anchor_x, anchor_y, w[0], w[1], AiTypes.MoveClass.NAVAL):
			continue
		var s: int = g.value[i] * 100 / (100 + AiForce.cells(w[0], w[1], cx, cy))
		if s > best_s:
			best_s = s
			best = i
			best_w = w
	if best < 0:
		return false
	# what defends the spot: enemy ships and defense structures in reach
	var dg: AiStrengthGroup = AiForce.enemy_group(ctx, g.x[best], g.y[best], 16 * Fp.CELL, 200)
	var ratio: int = AiForce.ratio(ctx, mine, dg, id)
	if dg.count > 0 and ratio < ctx.tune("strength.launch_ratio_x100", 130) * 256 / 100:
		return false
	bombard_eid = g.eid[best]
	bombard_x = g.x[best]
	bombard_y = g.y[best]
	_set_task(ctx, 2, best_w[0], best_w[1])
	if AiForce.dist(cx, cy, best_w[0], best_w[1]) > 6 * Fp.CELL:
		_go(ctx, sail, best_w[0], best_w[1])
	elif ctx.tick - _last_fire >= 200:
		_last_fire = ctx.tick
		bombards += 1
		b.bump("naval_bombard")
		ctx.cmd.force_fire(shooters, bombard_x, bombard_y, 0, bombard_eid)
		ctx.cmd.attack_move(free_ids(ctx, sail), best_w[0], best_w[1])
	return true


func _set_task(ctx: AiContext, tk: int, x: int, y: int) -> void:
	if tk != task:
		task = tk
		set_state(ctx, AiTypes.OpState.ENGAGING if tk != 0 else AiTypes.OpState.STAGING)
	task_x = x
	task_y = y


func _go(ctx: AiContext, list: PackedInt32Array, x: int, y: int) -> void:
	if ctx.tick - _last_order < 80 and AiForce.dist(x, y, tx, ty) < 6 * Fp.CELL:
		return
	_last_order = ctx.tick
	tx = x
	ty = y
	ctx.cmd.attack_move(free_ids(ctx, list), x, y)


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), task, hunts, bombards, escorts_done, retreats]))
