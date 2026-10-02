class_name AiSiege
extends RefCounted
## SIEGING behaviour of a wave (ai.md 5.8.2 SIEGING, 5.9.3 deploy rules): when the target cluster is covered by defensive
## structures (or remembered dangers) and the wave brought artillery that OUTRANGES them, the wave stops at a siege position out
## of the defenders' reach, the artillery bombards the defensive structure ghosts one by one (`force_fire` on the remembered
## structure: no vision is needed, the sim keeps a forced target alive while it is hidden) and the direct-fire units screen the
## artillery (attack-move to the siege position, leashed to it). When the defenses are down, the ratio of the whole wave against
## what is left of the defenders is good enough, the siege times out or the artillery is gone, the op goes on with the normal
## assault (ENGAGING). The state machine belongs to one AiOpAttack (`op.siege`); the op calls `consider` before it engages and
## `update` in its SIEGING state.
##  phase 0 GATHER: artillery `move` to the siege position, the rest attack-moves there (re-issued every 100 ticks);
##  phase 1 FIRE:   `force_fire` at the current defensive ghost (re-issued when the target changes or every 200 ticks).

const GATHER: int = 0
const FIRE: int = 1
const REISSUE_TICKS: int = 100
const FIRE_REISSUE_TICKS: int = 200

var active: bool = false
var phase: int = GATHER
var pos_x: int = 0
var pos_y: int = 0
var target_eid: int = 0
var target_x: int = 0
var target_y: int = 0
var started: int = 0
var phase_since: int = 0
var kills: int = 0
var sieges: int = 0
var block_until: int = 0
var art_ids: PackedInt32Array = PackedInt32Array()
var escort_ids: PackedInt32Array = PackedInt32Array()
var art_range: int = 0
var _last_gather: int = AiTypes.NEVER
var _last_fire: int = AiTypes.NEVER
var _last_escort: int = AiTypes.NEVER
var _fired_target: int = -1
var _last_eval: int = AiTypes.NEVER


## True for a unit def that can bombard from far behind: indirect-fire artillery or a deployable siege piece with >= 9 cells range.
static func is_siege_def(ctx: AiContext, def: int) -> bool:
	var p: AiUnitProfile = ctx.unit_profile(def)
	if p == null or not p.is_combat() or p.speed <= 0 or p.move_class == AiTypes.MoveClass.AIR:
		return false
	if p.range < ctx.tune("siege.min_range_c", 9) * Fp.CELL:
		return false
	var ds: int = AiTypes.handler_bit("DEPLOY_SIEGE")
	return p.category == AiTypes.Cat.ARTILLERY or (p.role_mask & (1 << AiTypes.R_ARTILLERY)) != 0 or (ds >= 0 and (p.handler_mask & (1 << ds)) != 0)


## True when ghost row `i` is a defensive structure that can hurt ground units (an AA battery is not worth a bombardment).
static func ground_defense(ctx: AiContext, g: AiGhostTable, i: int) -> bool:
	if g.owner[i] < 0 or not AiForce.is_defense_kind(g.kind[i]) or g.kind[i] == AiTypes.StructKind.AA_BATTERY:
		return false
	var sp: AiUnitProfile = ctx.struct_profile_of(g.owner[i], g.def[i])
	return sp != null and sp.is_combat() and (sp.hits_mask & DefEnums.L_GROUND) != 0


## Decides whether the wave `op` (about to reach its target) should siege. Fills the plan and activates when yes.
func consider(ctx: AiContext, b: AiBrain, op: AiOp, budget: AiBudget) -> bool:
	if active or ctx.tick < block_until or ctx.tick - _last_eval < 40 or ctx.tune("aix.siege", 1) == 0 or not budget.spend(6):
		return false
	_last_eval = ctx.tick
	var t: AiEntityTable = ctx.kb.own
	var arts: PackedInt32Array = PackedInt32Array()
	var esc: PackedInt32Array = PackedInt32Array()
	var art_val: int = 0
	var rng: int = 1 << 30
	for eid: int in op.ground:
		var r: int = t.row(eid)
		if r < 0:
			continue
		if is_siege_def(ctx, t.def[r]):
			arts.append(eid)
			art_val += t.paid[r]
			rng = mini(rng, ctx.unit_profile(t.def[r]).range)
		else:
			esc.append(eid)
	if arts.size() < ctx.tune("siege.min_pieces", 2) or esc.is_empty():
		return false  # a single gun cannot break a defended cluster: the wave assaults (or retreats) instead
	var need_pct: int = ctx.tune("siege.min_value_pct", 18)
	if ctx.pers.has_flag(AiTypes.doctrine_bit("SIEGE_DEPLOY")):
		need_pct = ctx.tune("siege.min_value_pct_doctrine", 12)
	if art_val * 100 < need_pct * maxi(op.value_now, 1):
		return false
	# the defensive structures of the target cluster and how far they reach
	var g: AiGhostTable = ctx.kb.ghosts
	var cl2: int = AiOpAttack.CLUSTER_R * AiOpAttack.CLUSTER_R
	var def_rows: int = 0
	var reach: int = 0
	for i: int in g.count:
		if not ground_defense(ctx, g, i):
			continue
		var dx: int = g.x[i] - op.tx
		var dy: int = g.y[i] - op.ty
		if dx * dx + dy * dy > cl2:
			continue
		def_rows += 1
		reach = maxi(reach, ctx.struct_profile_of(g.owner[i], g.def[i]).range)
	if def_rows == 0:
		return false
	var can_reach: int = rng * ctx.tune("siege.range_pct", 92) / 100
	if can_reach < reach + ctx.tune("siege.outrange_c", 2) * Fp.CELL:
		return false  # the artillery cannot outrange the defenses: a plain assault (or a retreat) is better
	art_ids = arts
	escort_ids = esc
	art_range = can_reach
	active = true
	phase = GATHER
	started = ctx.tick
	phase_since = ctx.tick
	target_eid = 0
	_fired_target = -1
	_last_gather = AiTypes.NEVER
	_last_fire = AiTypes.NEVER
	sieges += 1
	b.bump("siege")
	ctx.telemetry.emit(AiTypes.Tele.SIEGE_STARTED, arts.size(), def_rows, ctx.tick)
	_pick_target(ctx, op)
	if target_eid == 0:
		active = false
		return false
	return true


## Returns 0 while the siege goes on, 1 when the op should assault (ENGAGING), 2 when it should retreat.
func update(ctx: AiContext, b: AiBrain, op: AiOpAttack, budget: AiBudget) -> int:
	if not active:
		return 1
	var t: AiEntityTable = ctx.kb.own
	# live units
	art_ids = _alive(t, art_ids)
	escort_ids = _alive(t, escort_ids)
	budget.spend(2 + art_ids.size() / 4)
	if art_ids.is_empty():
		return _finish(ctx, 1)
	if ctx.tick - started > ctx.tune("siege.max_ticks", 2400):
		return _finish(ctx, 1)
	# a dead target is confirmed by the order that ends (the ghost then goes)
	if target_eid > 0 and not ctx.view.alive(target_eid):
		ctx.kb.ghosts.remove(target_eid)
		kills += 1
		b.bump("siege_kills")
		target_eid = 0
		_fired_target = -1
	if target_eid == 0:
		_pick_target(ctx, op)
	if target_eid == 0:
		return _finish(ctx, 1)  # no defensive structure left
	# the whole wave against what is left: assault once it is clearly enough
	if _defenses_left(ctx, op) == 0:
		return _finish(ctx, 1)
	var dg: AiStrengthGroup = AiForce.enemy_group(ctx, op.tx, op.ty, 16 * Fp.CELL, 200)
	var mine: AiStrengthGroup = AiForce.own_group(ctx, op.ids)
	if dg.count > 0 and AiForce.ratio(ctx, mine, dg, op.id) >= ctx.tune("siege.assault_ratio_x100", 200) * 256 / 100:
		return _finish(ctx, 1)
	# enemies at the siege position: the wave fights (ratio check may retreat)
	var rows: PackedInt32Array = PackedInt32Array()
	var n: int = AiForce.armed_enemy_rows(ctx, pos_x, pos_y, 13 * Fp.CELL, 60, rows)
	budget.spend(2 + n)
	if n > 0 and op.local_check_now(ctx, b):
		return 2
	match phase:
		GATHER:
			_gather(ctx, op, n, rows)
		FIRE:
			_fire(ctx, op, n, rows)
	return 0


func _alive(t: AiEntityTable, list: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for eid: int in list:
		if t.row(eid) >= 0:
			out.append(eid)
	return out


func _finish(ctx: AiContext, code: int) -> int:
	active = false
	block_until = ctx.tick + ctx.tune("siege.block_ticks", 900)
	return code


func _gather(ctx: AiContext, op: AiOpAttack, n_enemy: int, rows: PackedInt32Array) -> void:
	var t: AiEntityTable = ctx.kb.own
	if ctx.tick - _last_gather >= REISSUE_TICKS:
		_last_gather = ctx.tick
		var fa: PackedInt32Array = op.free_ids(ctx, art_ids)
		ctx.cmd.move(fa, pos_x, pos_y)
		ctx.cmd.attack_move(op.free_ids(ctx, escort_ids), pos_x, pos_y)
	# the artillery is there (or has waited long enough): open fire
	var near: int = 0
	for eid: int in art_ids:
		var r: int = t.row(eid)
		if r >= 0 and AiForce.dist(t.x[r], t.y[r], pos_x, pos_y) <= 6 * Fp.CELL:
			near += 1
	if near * 2 >= art_ids.size() or ctx.tick - phase_since > 700:
		phase = FIRE
		phase_since = ctx.tick
	if n_enemy > 0:
		_screen(ctx, op, rows)


func _fire(ctx: AiContext, op: AiOpAttack, n_enemy: int, rows: PackedInt32Array) -> void:
	# AIT: shells fired into an enemy Trident dome (no-fire-artillery zone) are lost: hold fire while the target is covered
	var zb: AiBrain = ctx.brain as AiBrain
	if zb != null and not zb.powers.dispersal.avoid.is_empty() and zb.powers.dispersal.avoided(target_x, target_y, AiDispersal.AV_NO_FIRE_ARTY, ctx.tick):
		zb.bump("siege_nofire_hold")
		if n_enemy > 0:
			_screen(ctx, op, rows)
		return
	if target_eid != _fired_target or ctx.tick - _last_fire >= FIRE_REISSUE_TICKS:
		_fired_target = target_eid
		_last_fire = ctx.tick
		ctx.cmd.force_fire(op.free_ids(ctx, art_ids), target_x, target_y, 0, maxi(target_eid, 0))
	if n_enemy > 0:
		_screen(ctx, op, rows)
	elif ctx.tick - _last_escort >= 150:
		_last_escort = ctx.tick
		ctx.cmd.attack_move(op.free_ids(ctx, escort_ids), pos_x, pos_y)


## Enemy units at the artillery: the escorts meet them (leashed to the siege position).
func _screen(ctx: AiContext, op: AiOpAttack, rows: PackedInt32Array) -> void:
	if ctx.tick - _last_escort < 60 or rows.is_empty():
		return
	var et: AiEntityTable = ctx.kb.enemy_units
	var sx: int = 0
	var sy: int = 0
	for r: int in rows:
		sx += et.x[r]
		sy += et.y[r]
	sx /= rows.size()
	sy /= rows.size()
	var d: int = AiForce.dist(sx, sy, pos_x, pos_y)
	var leash: int = 10 * Fp.CELL
	if d > leash:
		sx = pos_x + (sx - pos_x) * leash / d
		sy = pos_y + (sy - pos_y) * leash / d
	_last_escort = ctx.tick
	ctx.cmd.attack_move(op.free_ids(ctx, escort_ids), sx, sy)


func _defenses_left(ctx: AiContext, op: AiOp) -> int:
	var g: AiGhostTable = ctx.kb.ghosts
	var cl2: int = AiOpAttack.CLUSTER_R * AiOpAttack.CLUSTER_R
	var n: int = 0
	for i: int in g.count:
		if not ground_defense(ctx, g, i):
			continue
		var dx: int = g.x[i] - op.tx
		var dy: int = g.y[i] - op.ty
		if dx * dx + dy * dy <= cl2:
			n += 1
	return n


## Chooses the next defensive ghost of the cluster (the one nearest to the wave first) and the siege position for it.
func _pick_target(ctx: AiContext, op: AiOp) -> void:
	var g: AiGhostTable = ctx.kb.ghosts
	var cl2: int = AiOpAttack.CLUSTER_R * AiOpAttack.CLUSTER_R
	var best: int = -1
	var best_d: int = 1 << 60
	for i: int in g.count:
		if not ground_defense(ctx, g, i) or g.eid[i] <= 0:
			continue
		var dx: int = g.x[i] - op.tx
		var dy: int = g.y[i] - op.ty
		if dx * dx + dy * dy > cl2:
			continue
		var d: int = AiForce.dist(g.x[i], g.y[i], op.cx, op.cy)
		if d < best_d or (d == best_d and g.eid[i] < g.eid[best]):
			best_d = d
			best = i
	if best < 0:
		target_eid = 0
		return
	target_eid = g.eid[best]
	target_x = g.x[best]
	target_y = g.y[best]
	var sp: AiUnitProfile = ctx.struct_profile_of(g.owner[best], g.def[best])
	var r_def: int = sp.range if sp != null else 8 * Fp.CELL
	var dist_c: int = clampi(r_def + ctx.tune("siege.standoff_c", 3) * Fp.CELL, 6 * Fp.CELL, art_range)
	# from the target towards the wave
	var dx2: int = op.cx - target_x
	var dy2: int = op.cy - target_y
	var dd: int = maxi(Fp.dist(dx2, dy2), 1)
	if dd < dist_c:
		dist_c = dd  # already closer than the stand-off: stay where the wave is
	var old_x: int = pos_x
	var old_y: int = pos_y
	pos_x = target_x + dx2 * dist_c / dd
	pos_y = target_y + dy2 * dist_c / dd
	_snap(ctx)
	if AiForce.dist(old_x, old_y, pos_x, pos_y) > 3 * Fp.CELL:
		phase = GATHER
		phase_since = ctx.tick
		_last_gather = AiTypes.NEVER


func _snap(ctx: AiContext) -> void:
	var v: AiWorldView = ctx.view
	var cx: int = clampi(pos_x >> Fp.CELL_SHIFT, 1, v.map_w() - 2)
	var cy: int = clampi(pos_y >> Fp.CELL_SHIFT, 1, v.map_h() - 2)
	for ring: int in 6:
		for oy: int in range(-ring, ring + 1):
			for ox: int in range(-ring, ring + 1):
				if maxi(absi(ox), absi(oy)) == ring and v.passable(cx + ox, cy + oy, AiTypes.MoveClass.TRACKED):
					pos_x = (cx + ox) * Fp.CELL + Fp.CELL / 2
					pos_y = (cy + oy) * Fp.CELL + Fp.CELL / 2
					return


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([1 if active else 0, phase, sieges, kills, target_eid, pos_x, pos_y]))
