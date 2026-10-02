class_name AiMicro
extends RefCounted
## Slot 13 (ai.md 5.9.1): focus fire (Medium and up) and kiting (Hard and up, only when the think interval is <= 4 ticks) for the
## squads of the ops that are fighting (AiOpAttack ENGAGING / SIEGING, AiOpDefend). Commands are few by design (the APM bucket is
## small): one focus order per op and re-focus, at most `micro.max_kite_cmds` kite moves per pass. A unit that receives an order here
## is LEASED in the brain for a few ticks so that the op does not overwrite it; when the focused target dies (the unit's order goes
## idle) the lease ends at once and the op is nudged to re-issue its own order.
##  * Focus: prio = base(class) + (100 - hp_pct) / 4 - distance in cells over the visible armed enemies within 1.2 x the squad's
##    average range; command provider 90, healer 85, detector 80, artillery 75, anti-tank infantry 70 (squad >= 50 % armor), AA 70
##    (my air present), tank 60, infantry 50, collector 45, scout 20, decoy 0. A target under 25 % hp is kept.
##  * Kite (KITER units: ranged, not deployable, not stationary-fire): if the nearest enemy that can hit the unit is inside
##    0.7 x its range and the unit is at least as fast, move to 0.9 x range from that enemy.

const BASE_COMMAND: int = 90
const BASE_HEALER: int = 85
const BASE_DETECTOR: int = 80
const BASE_ARTILLERY: int = 75
const BASE_AT: int = 70
const BASE_AA: int = 70
const BASE_TANK: int = 60
const BASE_INFANTRY: int = 50
const BASE_COLLECTOR: int = 45
const BASE_SCOUT: int = 20
const BASE_DECOY: int = 0

var focus_orders: int = 0
var focus_swaps: int = 0
var kite_orders: int = 0
var lease_ends: int = 0
var passes: int = 0
var _focus: Dictionary = {}  ## op id -> PackedInt32Array [target eid, tick set, prio, hp_pct]
var _leased: Dictionary = {}  ## op id -> PackedInt32Array of the units given a focus order
var _cursor: int = 0
var _nudge_at: Dictionary = {}  ## op id -> tick at which the op is asked to re-issue its orders (kite leases have ended)


func setup(_ctx: AiContext) -> void:
	pass


func step(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null or not budget.spend(2):
		return
	if ctx.tune("aix.micro", 1) == 0:
		return
	var focus_on: bool = ctx.diff.micro_focus
	var kite_on: bool = ctx.diff.micro_kite and ctx.dt <= 4 and ctx.pers.micro > 0
	if not focus_on and not kite_on:
		return
	passes += 1
	for o: AiOp in b.ops:
		if o.is_over() or o.alive == 0 or not _fighting(o):
			continue
		if not budget.spend(3 + o.ids.size() / 6):
			return
		_end_finished_leases(ctx, b, o)
		if _nudge_at.has(o.id) and ctx.tick >= int(_nudge_at[o.id]):
			_nudge_at.erase(o.id)
			o.nudge()
		if focus_on:
			_focus_fire(ctx, b, o, budget)
		if kite_on:
			_kite(ctx, b, o, budget)
	# forget ops that are gone
	if _focus.size() > 8:
		for id: int in _focus.keys():
			if b.op_by_id(id) == null:
				_focus.erase(id)
				_leased.erase(id)


static func _fighting(o: AiOp) -> bool:
	if o.type == AiTypes.OpType.ATTACK:
		return o.state == AiTypes.OpState.ENGAGING or o.state == AiTypes.OpState.SIEGING
	return o.type == AiTypes.OpType.DEFEND


# ---------------------------------------------------------------------------------------------------- focus fire
## Base priority of an enemy unit row by class (5.9.1).
static func base_prio(ctx: AiContext, row: int, my_armor_share_pct: int, my_air: bool) -> int:
	var t: AiEntityTable = ctx.kb.enemy_units
	if (t.flags[row] & AiTypes.EF_DECOY) != 0:
		return BASE_DECOY
	var m: int = t.role_mask[row]
	if (m & (1 << AiTypes.R_COMMAND_PROVIDER)) != 0:
		return BASE_COMMAND
	if (m & (1 << AiTypes.R_HEALER)) != 0:
		return BASE_HEALER
	if (m & (1 << AiTypes.R_DETECTOR)) != 0 and (m & (1 << AiTypes.R_COMBAT)) == 0:
		return BASE_DETECTOR
	if (m & (1 << AiTypes.R_ARTILLERY)) != 0:
		return BASE_ARTILLERY
	if (m & (1 << AiTypes.R_INFANTRY_AT)) != 0 and my_armor_share_pct >= 50:
		return BASE_AT
	if (m & (1 << AiTypes.R_AA_MOBILE)) != 0 and my_air:
		return BASE_AA
	if (m & ((1 << AiTypes.R_TANK_MAIN) | (1 << AiTypes.R_HEAVY))) != 0:
		return BASE_TANK
	if (m & ((1 << AiTypes.R_INFANTRY_BASIC) | (1 << AiTypes.R_INFANTRY_AT) | (1 << AiTypes.R_INFANTRY_SUPPORT))) != 0:
		return BASE_INFANTRY
	if (m & (1 << AiTypes.R_COLLECTOR)) != 0:
		return BASE_COLLECTOR
	if (m & (1 << AiTypes.R_SCOUT_LIGHT)) != 0:
		return BASE_SCOUT
	return BASE_INFANTRY - 5


func _focus_fire(ctx: AiContext, b: AiBrain, o: AiOp, budget: AiBudget) -> void:
	var t: AiEntityTable = ctx.kb.own
	var et: AiEntityTable = ctx.kb.enemy_units
	if et.count == 0:
		return
	# the squad's shape: average range, armor share, air presence
	var range_sum: int = 0
	var n_ground: int = 0
	var armor_val: int = 0
	var total_val: int = 0
	var my_air: bool = false
	for eid: int in o.ids:
		var r: int = t.row(eid)
		if r < 0:
			continue
		if AiForce.is_air(ctx, t.def[r]):
			my_air = true
			continue
		var p: AiUnitProfile = ctx.unit_profile(t.def[r])
		if p == null or not p.is_combat():
			continue
		n_ground += 1
		range_sum += p.range
		total_val += t.paid[r]
		if p.category == AiTypes.Cat.ARMOR:
			armor_val += t.paid[r]
	if n_ground == 0:
		return
	var reach: int = clampi(range_sum / n_ground * ctx.tune("micro.focus_range_pct", 120) / 100, 8 * Fp.CELL, 16 * Fp.CELL)
	var armor_pct: int = armor_val * 100 / maxi(total_val, 1)
	var best: int = -1
	var best_s: int = -(1 << 30)
	var keep: PackedInt32Array = _focus.get(o.id, PackedInt32Array())
	var reach2: int = reach * reach
	for r2: int in et.count:
		if ctx.tick - et.last_seen[r2] > 20:
			continue
		var dx: int = et.x[r2] - o.cx
		if dx > reach or dx < -reach:
			continue
		var dy: int = et.y[r2] - o.cy
		var d2: int = dx * dx + dy * dy
		if d2 > reach2:
			continue
		var p2: AiUnitProfile = ctx.unit_profile_of(et.owner[r2], et.def[r2])
		if p2 == null:
			continue
		var hp_pct: int = et.hp[r2] * 100 / maxi(et.hp_max[r2], 1)
		var s: int = base_prio(ctx, r2, armor_pct, my_air) + (100 - hp_pct) / 4 - Fp.isqrt(d2) / Fp.CELL
		if not p2.is_combat() and base_prio(ctx, r2, armor_pct, my_air) < BASE_COLLECTOR:
			s -= 10
		if not keep.is_empty() and et.eid[r2] == keep[0]:
			if hp_pct < 25:
				s += 1000  # finish the wounded target
			else:
				s += 6  # hysteresis
		if s > best_s or (s == best_s and et.eid[r2] < et.eid[best]):
			best_s = s
			best = r2
	budget.spend(2 + et.count / 8)
	if best < 0:
		return
	var tgt: int = et.eid[best]
	var same: bool = not keep.is_empty() and keep[0] == tgt
	if same and ctx.tick - keep[1] < ctx.tune("micro.focus_hold_ticks", 80):
		return
	if not ctx.view.targetable_now(tgt):
		return
	# the units that can hurt it and are close enough to join in
	var tp: AiUnitProfile = ctx.unit_profile_of(et.owner[best], et.def[best])
	var subset: PackedInt32Array = PackedInt32Array()
	for eid2: int in o.ids:
		var r3: int = t.row(eid2)
		if r3 < 0 or (t.flags[r3] & AiTypes.EF_DEPLOYED) != 0 or (t.flags[r3] & AiTypes.EF_LOADED) != 0:
			continue
		var p3: AiUnitProfile = ctx.unit_profile(t.def[r3])
		if p3 == null or p3.dps_x100[tp.armor_class] <= 0:
			continue
		var ddx: int = t.x[r3] - et.x[best]
		var ddy: int = t.y[r3] - et.y[best]
		var lim: int = p3.range + 3 * Fp.CELL
		if ddx * ddx + ddy * ddy > lim * lim or b.leased(eid2, ctx.tick):
			continue
		subset.append(eid2)
	if subset.size() < 2:
		return
	if ctx.cmd.attack(subset, tgt, false, 3):
		focus_orders += 1
		if not same:
			focus_swaps += 1
		_focus[o.id] = PackedInt32Array([tgt, ctx.tick, best_s, et.hp[best] * 100 / maxi(et.hp_max[best], 1)])
		_leased[o.id] = subset
		b.lease_units(subset, ctx.tick + ctx.tune("micro.lease_ticks", 100))
		b.bump("focus")


## A focus lease ends when the unit's order is idle again (the target died): the op takes over at once.
func _end_finished_leases(ctx: AiContext, b: AiBrain, o: AiOp) -> void:
	if not _leased.has(o.id):
		return
	var list: PackedInt32Array = _leased[o.id]
	var t: AiEntityTable = ctx.kb.own
	var keep: PackedInt32Array = PackedInt32Array()
	var ended: int = 0
	for eid: int in list:
		var r: int = t.row(eid)
		if r < 0:
			continue
		if t.order[r] == AiTypes.OrderKind.IDLE and b.leased(eid, ctx.tick):
			b.release_lease(eid)
			ended += 1
		elif b.leased(eid, ctx.tick):
			keep.append(eid)
	_leased[o.id] = keep
	if ended > 0:
		lease_ends += ended
		o.nudge()


# ------------------------------------------------------------------------------------------------------- kiting
static func is_kiter(ctx: AiContext, def: int) -> bool:
	var p: AiUnitProfile = ctx.unit_profile(def)
	if p == null or not p.is_combat() or p.speed <= 0:
		return false
	if (p.role_mask & (1 << AiTypes.R_KITER)) != 0:
		return true
	if (p.role_mask & (1 << AiTypes.R_STATIONARY_FIRE)) != 0 or p.category == AiTypes.Cat.ARTILLERY or p.category == AiTypes.Cat.AIR:
		return false
	if (p.handler_mask & ((1 << AiTypes.handler_bit("DEPLOY_SIEGE")) | (1 << AiTypes.handler_bit("COVER_DEPLOY")))) != 0:
		return false
	return p.range >= 9 * Fp.CELL and p.min_range == 0 and p.move_class != AiTypes.MoveClass.NAVAL and p.move_class != AiTypes.MoveClass.SUBMERGED


func _kite(ctx: AiContext, b: AiBrain, o: AiOp, budget: AiBudget) -> void:
	var t: AiEntityTable = ctx.kb.own
	var et: AiEntityTable = ctx.kb.enemy_units
	if et.count == 0:
		return
	var max_units: int = ctx.tune("micro.max_kiters", 8)
	var max_cmds: int = ctx.tune("micro.max_kite_cmds", 3)
	var cmds: int = 0
	var seen: int = 0
	var n: int = o.ids.size()
	var start: int = _cursor % maxi(n, 1)
	for k: int in n:
		if seen >= max_units or cmds >= max_cmds or not budget.spend(2):
			break
		var eid: int = o.ids[(start + k) % n]
		var r: int = t.row(eid)
		if r < 0 or (t.flags[r] & (AiTypes.EF_DEPLOYED | AiTypes.EF_LOADED)) != 0 or b.leased(eid, ctx.tick) or not is_kiter(ctx, t.def[r]):
			continue
		seen += 1
		var mine: AiUnitProfile = ctx.unit_profile(t.def[r])
		# nearest enemy that can hit this unit
		var best: int = -1
		var best_d2: int = 1 << 60
		var limit: int = mine.range * ctx.tune("micro.kite_trigger_pct", 70) / 100
		for r2: int in et.count:
			if ctx.tick - et.last_seen[r2] > 30 or (et.flags[r2] & AiTypes.EF_DECOY) != 0:
				continue
			var dx: int = et.x[r2] - t.x[r]
			if dx > limit or dx < -limit:
				continue
			var dy: int = et.y[r2] - t.y[r]
			var d2: int = dx * dx + dy * dy
			if d2 > limit * limit or d2 >= best_d2:
				continue
			var ep: AiUnitProfile = ctx.unit_profile_of(et.owner[r2], et.def[r2])
			if ep == null or ep.dps_x100[mine.armor_class] <= 0 or ep.range * ep.range < d2 or ep.speed > mine.speed:
				continue
			best_d2 = d2
			best = r2
		if best < 0:
			continue
		var dist: int = maxi(Fp.isqrt(best_d2), 1)
		var back: int = mine.range * ctx.tune("micro.kite_back_pct", 90) / 100
		var px: int = et.x[best] + (t.x[r] - et.x[best]) * back / dist
		var py: int = et.y[best] + (t.y[r] - et.y[best]) * back / dist
		var cx: int = clampi(px >> Fp.CELL_SHIFT, 1, ctx.view.map_w() - 2)
		var cy: int = clampi(py >> Fp.CELL_SHIFT, 1, ctx.view.map_h() - 2)
		if not ctx.view.passable(cx, cy, mine.move_class):
			continue
		if ctx.cmd.move(PackedInt32Array([eid]), cx * Fp.CELL + Fp.CELL / 2, cy * Fp.CELL + Fp.CELL / 2, false, 3):
			cmds += 1
			kite_orders += 1
			b.lease_one(eid, ctx.tick + ctx.tune("micro.kite_lease_ticks", 24))
			_nudge_at[o.id] = ctx.tick + ctx.tune("micro.kite_lease_ticks", 24) + 2
			b.bump("kite")
	_cursor += max_units


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([focus_orders, focus_swaps, kite_orders, lease_ends, passes]))
