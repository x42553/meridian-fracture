class_name AiSuperweapon
extends RefCounted
## Superweapon policy of one AI (ai.md 5.13.1 / 5.13.2): when to start the launcher, how to choose a target once it is READY
## (resumable candidate search over the known enemy structures and armies, per-weapon scoring from the resolved DefSuperweapon
## geometry), when to fire (score threshold, hold limit, combo timing with an attack op) and the Trident interception use.
## Stepped by AiPowers.step (slot 12, every 10 ticks); the launch is a LAUNCH_SW command (class 0) through AiCommandBuilder.
##
## Item flags of the search (one row per enemy structure ghost or fresh enemy unit): F_STRUCT, F_STILL (structure or unmoved unit),
## F_VEH (vehicle or aircraft), F_INF, F_DEF (powered defense), F_PROD (powered production / power / tech), F_KEY (HQ, Laboratory,
## Radar, superweapon), F_MCV, F_CHARGING (an enemy superweapon launcher).

const F_STRUCT: int = 1
const F_STILL: int = 2
const F_VEH: int = 4
const F_INF: int = 8
const F_DEF: int = 16
const F_PROD: int = 32
const F_KEY: int = 64
const F_MCV: int = 128
const F_CHARGING: int = 256

const UNIT_FRESH: int = 100
const MIN_SCORE_FRAC_PCT: int = 40  ## a held target is fired at 40 % of the superweapon price
const LATE_SCORE_FRAC_PCT: int = 20  ## after twice the hold limit even a 20 % target is taken (deviation: the spec waits forever)
const REEVAL_TICKS: int = 60
const TOP_BLOCKS: int = 10
const ANGLES: int = 16
const SHAPE_R_MARGIN: int = 4 * Fp.CELL
const DRONE_HP: int = 90

var sw_idx: int = -1
var launcher_def: int = -1
var kind: int = -1  ## DefEnums.SwAction
var def: DefSuperweapon = null
var jitter_pct: int = 0
var built_tick: int = AiTypes.NEVER  ## tick the launcher want was created
var active_tick: int = AiTypes.NEVER  ## first tick the launcher was active
var ready_since: int = AiTypes.NEVER
var last_launch_tick: int = AiTypes.NEVER
var launch_pending_until: int = AiTypes.NEVER
var launches: int = 0
var power_wants: int = 0
var guard_done: bool = false
var last_score: int = 0
var last_target: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])  ## x, y, angle, score of the last launch
var best_seen: int = 0
var combos: int = 0
var counter_casts: int = 0
var rejected: int = 0  ## launches that the sim did not start
var bad: PackedInt32Array = PackedInt32Array()  ## x, y of rejected targets (skipped by the search)
var why: int = AiTypes.Why.NONE
var build_why: String = ""  ## short reason the launcher was not started yet (debug / tests)
var _setup_done: bool = false
var _next_eval: int = 0
var _plan_x: int = 0
var _plan_y: int = 0
var _plan_angle: int = 0
var _plan_score: int = 0
var _plan_fire_at: int = -1
var _plan_tick: int = AiTypes.NEVER
var _wants_added: bool = false
var _start_min_tick: int = 0
var _tmp: PackedInt32Array = PackedInt32Array()
# item table of the search
var n_items: int = 0
var ix: PackedInt32Array = PackedInt32Array()
var iy: PackedInt32Array = PackedInt32Array()
var iv: PackedInt32Array = PackedInt32Array()
var ihp: PackedInt32Array = PackedInt32Array()
var iflag: PackedInt32Array = PackedInt32Array()
var iaa: PackedInt32Array = PackedInt32Array()  ## dps against air x100 (Tempest)
var ig: PackedInt32Array = PackedInt32Array()  ## dps against ground x100 (Dragonfall)
var n_own: int = 0
var ox: PackedInt32Array = PackedInt32Array()
var oy: PackedInt32Array = PackedInt32Array()
var ov: PackedInt32Array = PackedInt32Array()


func setup(ctx: AiContext) -> void:
	_setup_done = false
	_resolve(ctx)


func _resolve(ctx: AiContext) -> void:
	if _setup_done or not ctx.view.bound():
		return
	_setup_done = true
	var r: DefRoster = ctx.view.roster()
	if r == null or r.superweapon < 0 or r.superweapon_def == null:
		return
	sw_idx = r.superweapon
	def = r.superweapon_def
	launcher_def = def.launcher
	kind = def.action_kind
	jitter_pct = ctx.rng.range_i(-10, 10)  # draw (5) of ai.md 5.14.3
	ctx.pers.sw_jitter_pct = jitter_pct


func has_weapon() -> bool:
	return def != null


func is_shield() -> bool:
	return kind == DefEnums.SwAction.INTERCEPT_ZONE


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([sw_idx, launches, rejected, bad.size(), ready_since, last_launch_tick, last_score, best_seen, jitter_pct,
		1 if guard_done else 0, _plan_fire_at, counter_casts, combos]))


# ------------------------------------------------------------------------------------------------------------ step
func step(ctx: AiContext, budget: AiBudget) -> void:
	_resolve(ctx)
	if def == null or not ctx.view.rule_flag(AiTypes.RF_SUPERWEAPONS):
		return
	if not budget.spend(2):
		return
	_build(ctx, budget)
	var st: int = ctx.view.sw_status()
	if st == AiTypes.SwStatus.READY:
		if ready_since == AiTypes.NEVER:
			ready_since = ctx.tick
		if launch_pending_until != AiTypes.NEVER and ctx.tick >= launch_pending_until:
			# the command was queued but the sim did not start the attack (rejected or throttled): remember the point as bad
			rejected += 1
			bad.append(last_target[0])
			bad.append(last_target[1])
			if bad.size() > 16:
				bad = bad.slice(bad.size() - 16)
			ctx.cmd.note_no_effect(AiTypes.Intent.LAUNCH_SW, 0, ctx.tick)
			launch_pending_until = AiTypes.NEVER
		if ctx.tick >= launch_pending_until:
			if is_shield():
				_use_shield(ctx, budget)
			else:
				_use(ctx, budget)
	else:
		if ready_since != AiTypes.NEVER and launch_pending_until > ctx.tick:
			_confirm_launch(ctx)
		ready_since = AiTypes.NEVER
		_plan_fire_at = -1
	if st != AiTypes.SwStatus.NONE and active_tick == AiTypes.NEVER:
		active_tick = ctx.tick
		ctx.telemetry.emit(AiTypes.Tele.SW_STRUCT_DONE, sw_idx, 0, ctx.tick)


func _confirm_launch(ctx: AiContext) -> void:
	launches += 1
	last_launch_tick = ctx.tick
	launch_pending_until = AiTypes.NEVER
	ctx.telemetry.emit(AiTypes.Tele.SW_LAUNCHED, last_target[0] >> Fp.CELL_SHIFT, last_target[1] >> Fp.CELL_SHIFT, ctx.tick)


# ---------------------------------------------------------------------------------------------------- build policy
func min_start_tick(ctx: AiContext) -> int:
	# AIT: the launcher needs its full recharge (7-8 minutes) before the first shot, so a launcher started at 10 minutes fires after 19: the
	# start is scaled by `sw.time_scale_pct` (75 %: about 7:30 at Hard, a first strike around 16-17 minutes)
	var base: int = ctx.diff.sw_min_time_s * SimConfig.TPS * (150 - ctx.pers.sw_priority) / 100 * ctx.tune("sw.time_scale_pct", 100) / 100
	# AIT: an AI that is clearly ahead builds the launcher earlier (the strike ends the game instead of waiting for the clock)
	var b: AiBrain = ctx.brain as AiBrain
	if b != null and b.strategy.ratio_q8 >= ctx.tune("sw.ahead_ratio_x100", 150) * 256 / 100:
		base = base * ctx.tune("sw.ahead_time_pct", 65) / 100
	return base + base * jitter_pct / 100


func _build(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null or launcher_def < 0:
		return
	var eco: AiEconomy = b.eco()
	var v: AiWorldView = ctx.view
	if eco.struct_own[launcher_def] > 0:
		build_why = "built"
		_guards(ctx, eco)
		return
	if _wants_added and eco.find_want(AiTypes.WantKind.STRUCT, launcher_def, AiTypes.WantOrigin.SUPERWEAPON) != null:
		return
	if ctx.tick < min_start_tick(ctx):
		build_why = "time"
		return
	var rule: int = v.can_build(launcher_def)
	if rule != AiTypes.Rule.OK and rule != AiTypes.Rule.NO_CREDITS:
		why = AiTypes.Why.PREREQ_MISSING
		build_why = "prereq %d" % rule
		return
	# The bank rule of 5.13.1 (credits >= 2500) is replaced by the income rule plus a want that outranks the army lines: the
	# economy reserves the funds itself (a structure want that waits unfunded holds the unit lines, ai.md 5.4.1).
	if eco.income_per_s * 240 < 2500:
		why = AiTypes.Why.NO_FUNDS
		build_why = "funds"
		return
	var margin: int = v.power_supply() - v.power_demand()
	if margin < 200 + eco.margin_min:
		eco.ensure_generator(ctx)
		power_wants += 1
		why = AiTypes.Why.WANT_ISSUED
		build_why = "power"
		return
	for w: AiWant in eco.wants:
		if w.is_open() and (w.origin == AiTypes.WantOrigin.EMERGENCY or w.origin == AiTypes.WantOrigin.OPENER):
			build_why = "wants"
			return
	var ahead: bool = b.strategy.ratio_q8 >= ctx.tune("sw.ahead_ratio_x100", 150) * 256 / 100
	for p: int in ctx.kb.enemy_pids:
		if ctx.tick - ctx.kb.attacked_by_tick[p] < 60 * SimConfig.TPS and not ahead:  # AIT: skirmishes never stop an AI that is ahead from building it
			build_why = "attacked"
			return
	var prim: int = ctx.kb.primary
	if prim >= 0 and eco.army_value * 100 < 60 * ctx.kb.est_enemy_army_value(prim):
		build_why = "army"
		return
	build_why = "wanted"
	budget.spend(2)
	var w2: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, launcher_def, -1, 1, ctx.tune("sw.want_prio", AiEconomy.P_COUNTER), AiTypes.WantOrigin.SUPERWEAPON)
	w2.site_kind = AiPlacer.Site.BACK
	if eco.add_want(w2) != null:
		_wants_added = true
		built_tick = ctx.tick
		why = AiTypes.Why.WANT_ISSUED


## One AA battery and one AT turret near the launcher (prio 55).
func _guards(ctx: AiContext, eco: AiEconomy) -> void:
	if guard_done or eco.struct_own[launcher_def] == 0 or ctx.view.struct_count(launcher_def) == 0:
		return
	var t: AiEntityTable = ctx.kb.own
	var lx: int = -1
	var ly: int = -1
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_STRUCTURE and t.def[r] == launcher_def:
			lx = t.x[r]
			ly = t.y[r]
			break
	if lx < 0:
		return
	guard_done = true
	for k: int in [AiTypes.StructKind.AA_BATTERY, AiTypes.StructKind.AT_TURRET]:
		var d: int = ctx.res.structure_of_kind(k)
		if d < 0:
			continue
		var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, d, -1, eco.struct_own[d] + eco.struct_q[d] + 1, 55, AiTypes.WantOrigin.SUPERWEAPON)
		w.site_kind = AiPlacer.Site.FIELD
		w.site_x = lx
		w.site_y = ly
		eco.add_want(w)


# ------------------------------------------------------------------------------------------------------ item table
func _thresholds(ctx: AiContext) -> PackedInt32Array:
	var lv: int = ctx.cfg.level
	var min_score: int = ctx.tune("sw.min_score", 4000)
	match lv:
		AiTypes.Difficulty.EASY:
			min_score = min_score * 3 / 2
		AiTypes.Difficulty.BRUTAL:
			min_score = min_score * 3 / 4
	var hold: int = ctx.store.tune_by_level("sw.hold_max_ticks", lv, 900)
	return PackedInt32Array([min_score, hold])


func _collect(ctx: AiContext, budget: AiBudget) -> void:
	for a: PackedInt32Array in [ix, iy, iv, ihp, iflag, iaa, ig, ox, oy, ov]:
		a.resize(0)
	n_items = 0
	n_own = 0
	var kb: AiKnowledge = ctx.kb
	var v: AiWorldView = ctx.view
	var gt: AiGhostTable = kb.ghosts
	for j: int in gt.count:
		var o: int = gt.owner[j]
		if o < 0 or not v.is_enemy(o) or not v.player_alive(o):
			continue
		var sp: AiUnitProfile = ctx.struct_profile_of(o, gt.def[j])
		var f: int = F_STRUCT | F_STILL
		var k: int = gt.kind[j]
		var powered: bool = (gt.flags[j] & AiTypes.EF_UNPOWERED) == 0
		if AiForce.is_defense_kind(k) and powered:
			f |= F_DEF
		if powered and (k == AiTypes.StructKind.BARRACKS or k == AiTypes.StructKind.FACTORY or k == AiTypes.StructKind.AIRFIELD \
				or k == AiTypes.StructKind.DOCK or k == AiTypes.StructKind.GENERATOR or k == AiTypes.StructKind.RADAR \
				or k == AiTypes.StructKind.LAB or k == AiTypes.StructKind.REFINERY):
			f |= F_PROD
		if k == AiTypes.StructKind.HQ or k == AiTypes.StructKind.LAB or k == AiTypes.StructKind.RADAR or k == AiTypes.StructKind.SUPERWEAPON:
			f |= F_KEY
		if k == AiTypes.StructKind.SUPERWEAPON:
			f |= F_CHARGING
		ix.append(gt.x[j])
		iy.append(gt.y[j])
		iv.append(gt.value[j] * maxi(gt.hp_pct[j], 1) / 100)
		ihp.append(maxi(sp.hp * gt.hp_pct[j] / 100, 1) if sp != null else 1000)
		iflag.append(f)
		iaa.append(_dps_vs(sp, true))
		ig.append(_dps_vs(sp, false))
		n_items += 1
	var et: AiEntityTable = kb.enemy_units
	for i: int in et.count:
		if not v.is_enemy(et.owner[i]) or ctx.tick - et.last_seen[i] > UNIT_FRESH or (et.flags[i] & AiTypes.EF_DECOY) != 0 or et.hp[i] <= 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile_of(et.owner[i], et.def[i])
		if p == null:
			continue
		var f2: int = 0
		if ctx.tick - et.last_moved[i] >= AiPowerArch.STATIONARY_TICKS:
			f2 |= F_STILL
		match p.move_class:
			AiTypes.MoveClass.FOOT:
				f2 |= F_INF
			AiTypes.MoveClass.WHEELED, AiTypes.MoveClass.TRACKED, AiTypes.MoveClass.AMPHIBIOUS, AiTypes.MoveClass.AIR:
				f2 |= F_VEH
		if (p.role_mask & (1 << AiTypes.R_MCV)) != 0:
			f2 |= F_MCV
		ix.append(et.x[i])
		iy.append(et.y[i])
		iv.append(et.paid[i] * et.hp[i] / maxi(et.hp_max[i], 1))
		ihp.append(maxi(et.hp[i], 1))
		iflag.append(f2)
		iaa.append(_dps_vs(p, true))
		ig.append(_dps_vs(p, false))
		n_items += 1
	# my own value (the friendly-fire penalty)
	var t: AiEntityTable = kb.own
	for r: int in t.count:
		if t.hp[r] <= 0 or (t.flags[r] & AiTypes.EF_LOADED) != 0 or t.kind[r] > AiTypes.KIND_STRUCTURE:
			continue
		ox.append(t.x[r])
		oy.append(t.y[r])
		ov.append(t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1))
		n_own += 1
	budget.spend(2 + (n_items + n_own) / 8)


## dps x100 of a profile against air (true) or ground (false) targets.
static func _dps_vs(p: AiUnitProfile, air: bool) -> int:
	if p == null or not p.is_combat():
		return 0
	var bit: int = 2 if air else 1
	if (p.hits_mask & bit) == 0:
		return 0
	return p.dps_avg_x100()


# ------------------------------------------------------------------------------------------------------ target job
func _use(ctx: AiContext, budget: AiBudget) -> void:
	if ctx.tick < _next_eval:
		return
	if ctx.tick - ready_since < 0:
		return
	if not budget.spend(6):
		return
	var th: PackedInt32Array = _thresholds(ctx)
	var min_score: int = th[0]
	var hold_max: int = th[1]
	var held: int = ctx.tick - ready_since
	# an earlier combo plan waits for its moment
	if _plan_fire_at >= 0 and ctx.tick - _plan_tick < 400:
		if ctx.tick >= _plan_fire_at:
			_fire(ctx, _plan_x, _plan_y, _plan_angle, _plan_score, true)
			_plan_fire_at = -1
			return
		if held < hold_max + 400:
			return
	_collect(ctx, budget)
	var best: PackedInt32Array = _search(ctx, budget)
	if best.size() < 4:
		why = AiTypes.Why.SW_HOLD
		_next_eval = ctx.tick + REEVAL_TICKS
		return
	last_score = best[3]
	best_seen = maxi(best_seen, best[3])
	var fire_now: bool = best[3] >= min_score or (held >= hold_max and best[3] >= def_price(ctx) * MIN_SCORE_FRAC_PCT / 100) \
			or (held >= 2 * hold_max and best[3] >= def_price(ctx) * LATE_SCORE_FRAC_PCT / 100)
	if not fire_now:
		why = AiTypes.Why.SW_HOLD
		_next_eval = ctx.tick + REEVAL_TICKS
		return
	var fire_at: int = _combo_time(ctx, best[0], best[1])
	if fire_at > ctx.tick and held < hold_max + 400:
		_plan_x = best[0]
		_plan_y = best[1]
		_plan_angle = best[2]
		_plan_score = best[3]
		_plan_fire_at = fire_at
		_plan_tick = ctx.tick
		combos += 1
		why = AiTypes.Why.SW_HOLD
		return
	_fire(ctx, best[0], best[1], best[2], best[3], false)


func def_price(_ctx: AiContext) -> int:
	return 5000


func _fire(ctx: AiContext, x: int, y: int, angle: int, score: int, combo: bool) -> void:
	# refresh: the plan may be stale (the target explored terrain is fine, but never fire at a point outside the map)
	x = clampi(x, 0, ctx.view.map_w() * Fp.CELL - 1)
	y = clampi(y, 0, ctx.view.map_h() * Fp.CELL - 1)
	if ctx.cmd.launch_superweapon(x, y, angle):
		last_target[0] = x
		last_target[1] = y
		last_target[2] = angle
		last_target[3] = score
		launch_pending_until = ctx.tick + 60
		why = AiTypes.Why.SW_FIRE
		if kind == DefEnums.SwAction.RAIL_STRIKE:
			# the Horizon debris slows and blocks MY vehicles and construction too (Kongo note): keep out of the line for 29 s
			var b: AiBrain = ctx.brain as AiBrain
			if b != null:
				var r: int = _reach()
				b.powers.dispersal.add_avoid(AiDispersal.AV_DEBRIS, x, y, r, ctx.tick + def.warning_t + 580)
				b.powers.dispersal.add_avoid(AiDispersal.AV_NO_BUILD, x, y, r, ctx.tick + def.warning_t + 580)
		if combo:
			ctx.telemetry.emit(AiTypes.Tele.POWER_USED, sw_idx, 1, ctx.tick)


## Combo timing (5.13.2 step 3): an ATTACK / LANDING op that reaches the target region within ~60 s. Hard combos only Aurora and
## Dragonfall, Brutal all weapons. Returns the tick to fire (arrival - warning - 20) or -1.
func _combo_time(ctx: AiContext, x: int, y: int) -> int:
	var lv: int = ctx.cfg.level
	var allowed: bool = lv >= AiTypes.Difficulty.BRUTAL or (lv == AiTypes.Difficulty.HARD and (kind == DefEnums.SwAction.EMP_BURST or kind == DefEnums.SwAction.ENGINE_DROP))
	if not allowed:
		return -1
	var b: AiBrain = ctx.brain as AiBrain
	if b == null:
		return -1
	var best: int = -1
	for o: AiOp in b.ops:
		if o.is_over() or (o.type != AiTypes.OpType.ATTACK and o.type != AiTypes.OpType.LANDING):
			continue
		if o.state != AiTypes.OpState.STAGING and o.state != AiTypes.OpState.ADVANCING and o.state != AiTypes.OpState.FORMING:
			continue
		if AiForce.cells(o.tx, o.ty, x, y) > 16:
			continue
		var arrival: int = ctx.tick + 400
		if o is AiOpAttack:
			var oa: AiOpAttack = o as AiOpAttack
			arrival = oa.depart_tick + oa.eta_ticks
		if arrival - ctx.tick > 60 * SimConfig.TPS or arrival < ctx.tick:
			continue
		var at: int = arrival - def.warning_t - 20
		if best < 0 or at < best:
			best = at
	return best


# ---- the search itself
## Returns [x, y, angle, score] of the best candidate or an empty array.
func _search(ctx: AiContext, budget: AiBudget) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if n_items == 0:
		return out
	var cand: PackedInt32Array = _candidates(ctx, budget)
	var lines: bool = _uses_angle()
	var best_score: int = 0
	var bx: int = 0
	var by: int = 0
	var ba: int = 0
	var reach: int = _reach() + SHAPE_R_MARGIN
	var n_angle: int = ANGLES if lines else 1
	for c: int in cand.size() / 2:
		var cx: int = cand[2 * c]
		var cy: int = cand[2 * c + 1]
		if _is_bad(cx, cy):
			continue
		if not budget.spend(2 + (n_items + n_own) / 24):
			break
		var loc: PackedInt32Array = _local_items(cx, cy, reach)
		var oloc: PackedInt32Array = _local_own(cx, cy, reach)
		for a: int in n_angle:
			var ang: int = a * 256
			var s: int = _score(ctx, loc, oloc, cx, cy, ang)
			if s > best_score:
				best_score = s
				bx = cx
				by = cy
				ba = ang
	if best_score <= 0:
		return out
	out.append(bx)
	out.append(by)
	out.append(ba)
	out.append(best_score)
	return out


func _is_bad(x: int, y: int) -> bool:
	for i: int in bad.size() / 2:
		var dx: int = bad[2 * i] - x
		var dy: int = bad[2 * i + 1] - y
		if dx * dx + dy * dy < 9 * Fp.CELL * Fp.CELL:
			return true
	return false


func _uses_angle() -> bool:
	return kind == DefEnums.SwAction.KINETIC_VOLLEY or kind == DefEnums.SwAction.BEAM_SWEEP or kind == DefEnums.SwAction.RAIL_STRIKE


## Maximum distance of a shape point from its centre (units).
func _reach() -> int:
	match kind:
		DefEnums.SwAction.KINETIC_VOLLEY, DefEnums.SwAction.RAIL_STRIKE, DefEnums.SwAction.BUNKER_BUSTER:
			var m: int = 0
			for pk: DefImpactPacket in def.packets:
				m = maxi(m, Fp.dist(pk.offset_x, pk.offset_y) + pk.radius)
			return m
		DefEnums.SwAction.BEAM_SWEEP:
			return int(def.params.get("line_len_u", 16384)) / 2 + int(def.params.get("width_u", 3072)) / 2
	return maxi(def.radius, 6 * Fp.CELL)


func _candidates(ctx: AiContext, budget: AiBudget) -> PackedInt32Array:
	var bs: int = AiCluster.BLOCK_CELLS * Fp.CELL
	var gw: int = (ctx.view.map_w() * Fp.CELL + bs - 1) / bs
	var gh: int = (ctx.view.map_h() * Fp.CELL + bs - 1) / bs
	var grid: Dictionary = {}  ## block key -> [sum, sx, sy, sw]
	for i: int in n_items:
		var bxk: int = clampi(ix[i] / bs, 0, gw - 1)
		var byk: int = clampi(iy[i] / bs, 0, gh - 1)
		var key: int = byk * gw + bxk
		var e: PackedInt32Array = grid.get(key, PackedInt32Array([0, 0, 0, 0]))
		e[0] += iv[i]
		e[1] += ix[i] * maxi(iv[i], 1)
		e[2] += iy[i] * maxi(iv[i], 1)
		e[3] += maxi(iv[i], 1)
		grid[key] = e
	budget.spend(1 + n_items / 8)
	# local 3 x 3 sums
	var keys: Array = grid.keys()
	keys.sort()
	var rows: Array[PackedInt32Array] = []  ## [local_sum, key]
	for k: Variant in keys:
		var key2: int = int(k)
		var kx: int = key2 % gw
		var ky: int = key2 / gw
		var sum: int = 0
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var nk: int = (ky + dy) * gw + kx + dx
				if kx + dx >= 0 and kx + dx < gw and grid.has(nk):
					sum += (grid[nk] as PackedInt32Array)[0]
		rows.append(PackedInt32Array([sum, key2]))
	rows.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: PackedInt32Array = PackedInt32Array()
	for i2: int in mini(rows.size(), TOP_BLOCKS):
		var e2: PackedInt32Array = grid[rows[i2][1]]
		out.append(e2[1] / maxi(e2[3], 1))
		out.append(e2[2] / maxi(e2[3], 1))
	# every single high-value ghost (superweapon, Laboratory, Radar, HQ)
	var extra: int = 0
	for j: int in n_items:
		if (iflag[j] & F_KEY) != 0 and extra < 6:
			out.append(ix[j])
			out.append(iy[j])
			extra += 1
	# refine the top three with the units of the sim (fog-honouring): positions of items near the centre are re-read
	return _dedupe(out)


func _dedupe(c: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in c.size() / 2:
		var dup: bool = false
		for j: int in out.size() / 2:
			var dx: int = out[2 * j] - c[2 * i]
			var dy: int = out[2 * j + 1] - c[2 * i + 1]
			if dx * dx + dy * dy < Fp.CELL * Fp.CELL:
				dup = true
				break
		if not dup:
			out.append(c[2 * i])
			out.append(c[2 * i + 1])
	return out


func _local_items(cx: int, cy: int, reach: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var r2: int = reach * reach
	for i: int in n_items:
		var dx: int = ix[i] - cx
		var dy: int = iy[i] - cy
		if dx * dx + dy * dy <= r2:
			out.append(i)
	return out


func _local_own(cx: int, cy: int, reach: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var r2: int = reach * reach
	for i: int in n_own:
		var dx: int = ox[i] - cx
		var dy: int = oy[i] - cy
		if dx * dx + dy * dy <= r2:
			out.append(i)
	return out


# ------------------------------------------------------------------------------------------------ per-weapon scores
func _score(ctx: AiContext, loc: PackedInt32Array, oloc: PackedInt32Array, cx: int, cy: int, ang: int) -> int:
	var gain: int = 0
	var pen: int = 0
	var pen_k: int = 2
	match kind:
		DefEnums.SwAction.KINETIC_VOLLEY:
			gain = _packets_gain(loc, cx, cy, ang)
			pen = _own_in_packets(oloc, cx, cy, ang)
			pen_k = 3
		DefEnums.SwAction.RAIL_STRIKE:
			gain = _rail_gain(loc, cx, cy, ang)
			pen = _own_in_packets(oloc, cx, cy, ang)
			pen_k = 3
		DefEnums.SwAction.BUNKER_BUSTER:
			gain = _perun_gain(loc, cx, cy)
			pen = _own_in_circle(oloc, cx, cy, 7 * Fp.CELL)
		DefEnums.SwAction.EMP_BURST:
			gain = _aurora_gain(loc, cx, cy)
			pen = 0
		DefEnums.SwAction.BEAM_SWEEP:
			gain = _helios_gain(loc, cx, cy, ang)
			pen = _own_in_rect(oloc, cx, cy, ang)
		DefEnums.SwAction.DRONE_SWARM:
			gain = _tempest_gain(loc, cx, cy)
			pen = _own_in_circle(oloc, cx, cy, def.radius) / 2
		DefEnums.SwAction.ENGINE_DROP:
			gain = _dragon_gain(loc, cx, cy)
			pen = _own_in_circle(oloc, cx, cy, def.radius) / 2
	var net: int = gain - pen * pen_k / 2
	if pen > 0 and pen * pen_k / 2 * 2 > gain:
		return 0  # never fire when the own loss exceeds half of the gain
	return net


func _packets_gain(loc: PackedInt32Array, cx: int, cy: int, ang: int) -> int:
	# Atlas: cumulative damage of the rods over each item, mobile units count a quarter
	var total: int = 0
	for i: int in loc:
		var dmg: int = 0
		for pk: DefImpactPacket in def.packets:
			var px: int = cx + Fp.rot_x(pk.offset_x, pk.offset_y, ang)
			var py: int = cy + Fp.rot_y(pk.offset_x, pk.offset_y, ang)
			var dx: int = ix[i] - px
			var dy: int = iy[i] - py
			var d2: int = dx * dx + dy * dy
			if d2 <= pk.radius * pk.radius:
				# linear falloff from the full damage at the centre to `edge_bp` at the rim
				var d: int = Fp.isqrt(d2)
				dmg += pk.damage * (10000 - (10000 - pk.edge_bp) * d / maxi(pk.radius, 1)) / 10000
		if dmg == 0:
			continue
		var frac: int = mini(256, dmg * 256 / maxi(ihp[i], 1))
		var w: int = 256 if (iflag[i] & F_STILL) != 0 else 64
		total += iv[i] * frac / 256 * w / 256
	return total


func _rail_gain(loc: PackedInt32Array, cx: int, cy: int, ang: int) -> int:
	var total: int = 0
	var mcv_bonus: bool = false
	for pk: DefImpactPacket in def.packets:
		var px: int = cx + Fp.rot_x(pk.offset_x, pk.offset_y, ang)
		var py: int = cy + Fp.rot_y(pk.offset_x, pk.offset_y, ang)
		for i: int in loc:
			var dx: int = ix[i] - px
			var dy: int = iy[i] - py
			if dx * dx + dy * dy > pk.radius * pk.radius:
				continue
			if (iflag[i] & F_STRUCT) != 0:
				total += iv[i]
			elif (iflag[i] & F_STILL) != 0:
				total += iv[i] * 80 / 100
			else:
				total += iv[i] * 30 / 100
			if (iflag[i] & F_MCV) != 0:
				mcv_bonus = true
	if mcv_bonus:
		total += 1500
	return total


func _perun_gain(loc: PackedInt32Array, cx: int, cy: int) -> int:
	var total: int = 0
	var core: int = 3 * Fp.CELL
	var ring: int = 7 * Fp.CELL
	for pk: DefImpactPacket in def.packets:
		if pk.damage > 2000:
			core = pk.radius
		else:
			ring = maxi(pk.radius, 1)
	for i: int in loc:
		var dx: int = ix[i] - cx
		var dy: int = iy[i] - cy
		var d2: int = dx * dx + dy * dy
		var w: int = 100 if (iflag[i] & (F_STRUCT | F_STILL)) != 0 else 40
		if d2 <= core * core:
			var v: int = iv[i] * w / 100
			if (iflag[i] & F_CHARGING) != 0:
				v = v * 150 / 100
			elif (iflag[i] & F_KEY) != 0:
				v = v * 130 / 100
			total += v
		elif d2 <= ring * ring:
			total += iv[i] * w / 100 * 35 / 100
	return total


func _aurora_gain(loc: PackedInt32Array, cx: int, cy: int) -> int:
	var total: int = 0
	var r2: int = def.radius * def.radius
	for i: int in loc:
		var dx: int = ix[i] - cx
		var dy: int = iy[i] - cy
		if dx * dx + dy * dy > r2:
			continue
		var f: int = iflag[i]
		if (f & F_STRUCT) != 0:
			if (f & F_DEF) != 0:
				total += iv[i] * 80 / 100
			elif (f & F_PROD) != 0:
				total += iv[i] * 30 / 100
		elif (f & F_VEH) != 0:
			total += iv[i] * 50 / 100
	return total


func _helios_gain(loc: PackedInt32Array, cx: int, cy: int, ang: int) -> int:
	var total: int = 0
	var half_len: int = int(def.params.get("line_len_u", 16384)) / 2
	var half_w: int = int(def.params.get("width_u", 3072)) / 2
	var inv: int = (Fp.TURN - ang) & Fp.ANGLE_MASK
	for i: int in loc:
		var lx: int = ix[i] - cx
		var ly: int = iy[i] - cy
		var u: int = Fp.rot_x(lx, ly, inv)
		var w: int = Fp.rot_y(lx, ly, inv)
		if absi(u) > half_len or absi(w) > half_w:
			continue
		if (iflag[i] & F_STRUCT) != 0:
			total += iv[i]
		elif (iflag[i] & F_STILL) != 0:
			total += iv[i] * 80 / 100
		else:
			total += iv[i] * 15 / 100
	return total


func _tempest_gain(loc: PackedInt32Array, cx: int, cy: int) -> int:
	var total: int = 0
	var r2: int = def.radius * def.radius
	for i: int in loc:
		var dx: int = ix[i] - cx
		var dy: int = iy[i] - cy
		if dx * dx + dy * dy > r2:
			continue
		if (iflag[i] & F_STRUCT) != 0:
			total += iv[i] * 60 / 100
		elif (iflag[i] & F_STILL) != 0:
			total += iv[i]
		else:
			total += iv[i] * 40 / 100
	var aa: int = 0
	var far: int = 14 * Fp.CELL
	for j: int in loc:
		var ex: int = ix[j] - cx
		var ey: int = iy[j] - cy
		if ex * ex + ey * ey <= far * far:
			aa += iaa[j] / 100
	var aa_red: int = mini(230, aa * 20 * 256 / maxi(24 * DRONE_HP / 2, 1))
	return total * (256 - aa_red) / 256


func _dragon_gain(loc: PackedInt32Array, cx: int, cy: int) -> int:
	var structs: int = 0
	var at_dps: int = 0
	var reach: int = 10 * Fp.CELL
	for i: int in loc:
		var dx: int = ix[i] - cx
		var dy: int = iy[i] - cy
		if dx * dx + dy * dy > reach * reach:
			continue
		if (iflag[i] & F_STRUCT) != 0:
			structs += iv[i]
		at_dps += ig[i] / 100
	var pen: int = mini(structs, at_dps * 60 / 2)
	return structs * 60 / 100 - pen


func _own_in_circle(oloc: PackedInt32Array, cx: int, cy: int, r: int) -> int:
	var s: int = 0
	for i: int in oloc:
		var dx: int = ox[i] - cx
		var dy: int = oy[i] - cy
		if dx * dx + dy * dy <= r * r:
			s += ov[i]
	return s


func _own_in_packets(oloc: PackedInt32Array, cx: int, cy: int, ang: int) -> int:
	var s: int = 0
	for i: int in oloc:
		for pk: DefImpactPacket in def.packets:
			var px: int = cx + Fp.rot_x(pk.offset_x, pk.offset_y, ang)
			var py: int = cy + Fp.rot_y(pk.offset_x, pk.offset_y, ang)
			var dx: int = ox[i] - px
			var dy: int = oy[i] - py
			if dx * dx + dy * dy <= pk.radius * pk.radius:
				s += ov[i]
				break
	return s


func _own_in_rect(oloc: PackedInt32Array, cx: int, cy: int, ang: int) -> int:
	var s: int = 0
	var half_len: int = int(def.params.get("line_len_u", 16384)) / 2
	var half_w: int = int(def.params.get("width_u", 3072)) / 2
	var inv: int = (Fp.TURN - ang) & Fp.ANGLE_MASK
	for i: int in oloc:
		var u: int = Fp.rot_x(ox[i] - cx, oy[i] - cy, inv)
		var w: int = Fp.rot_y(ox[i] - cx, oy[i] - cy, inv)
		if absi(u) <= half_len and absi(w) <= half_w:
			s += ov[i]
	return s


## Score of a fixed placement, for tests and the debug view: collects the items and scores (x, y, angle).
func score_at(ctx: AiContext, x: int, y: int, angle: int) -> int:
	_resolve(ctx)
	if def == null:
		return 0
	var scratch: AiBudget = AiBudget.new()
	scratch.reset(1000000, 1000000)
	_collect(ctx, scratch)
	var reach: int = _reach() + SHAPE_R_MARGIN
	return _score(ctx, _local_items(x, y, reach), _local_own(x, y, reach), x, y, angle)


## Runs the whole target search once (tests): [x, y, angle, score] or empty.
func search_now(ctx: AiContext) -> PackedInt32Array:
	_resolve(ctx)
	if def == null:
		return PackedInt32Array()
	var scratch: AiBudget = AiBudget.new()
	scratch.reset(1000000, 1000000)
	_collect(ctx, scratch)
	return _search(ctx, scratch)


# ------------------------------------------------------------------------------------------------------ Trident
func _use_shield(ctx: AiContext, budget: AiBudget) -> void:
	if not budget.spend(4):
		return
	var v: AiWorldView = ctx.view
	var n: int = v.strategic_warnings(_tmp)
	var arch_snapshot: AiPowerArch = null
	var b: AiBrain = ctx.brain as AiBrain
	if b != null and b.powers != null:
		arch_snapshot = b.powers.arch
		arch_snapshot.snapshot(ctx, budget)
	for i: int in n / 7:
		var owner: int = _tmp[7 * i]
		var sidx: int = _tmp[7 * i + 1]
		var wx: int = _tmp[7 * i + 2]
		var wy: int = _tmp[7 * i + 3]
		var start: int = _tmp[7 * i + 5]
		var impact: int = _tmp[7 * i + 6]
		if sidx < 0 or sidx >= v.game_data().superweapons.size() or not v.is_enemy(owner):
			continue
		var wd: DefSuperweapon = v.game_data().superweapons[sidx]
		# packet weapons only: beams, EMP and drones bypass the dome
		if wd.action_kind != DefEnums.SwAction.KINETIC_VOLLEY and wd.action_kind != DefEnums.SwAction.BUNKER_BUSTER \
				and wd.action_kind != DefEnums.SwAction.RAIL_STRIKE:
			continue
		if ctx.tick - start > 80 or ctx.tick - start < ctx.diff.reaction_delay_ticks or impact - ctx.tick < def.warning_t + 6:
			continue  # cast within 4 s of the warning (after the human reaction delay); the dome needs its own warning time
		var covered: int = 0
		var mine: int = 0
		if arch_snapshot != null:
			mine = arch_snapshot.own_value_in_circle(wx, wy, def.radius + 2 * Fp.CELL)
			covered = _packets_inside(wd, wx, wy)
		var benefit: int = mine / 2 * covered / maxi(wd.packets.size(), 1)
		if mine >= 5000 and benefit >= 2000:
			if ctx.cmd.launch_superweapon(wx, wy, 0):
				last_target[0] = wx
				last_target[1] = wy
				last_target[3] = benefit
				launch_pending_until = ctx.tick + 60
				counter_casts += 1
				why = AiTypes.Why.SW_FIRE
				return
	# defensive: artillery-heavy assault on my base with my structures in the dome
	if b != null and arch_snapshot != null and ctx.tick >= _next_eval:
		_next_eval = ctx.tick + 40
		var art: int = 0
		var hx: int = 0
		var hy: int = 0
		for j: int in arch_snapshot.en:
			if arch_snapshot.e_arty[j] != 0 and arch_snapshot.e_kind[j] == AiPowerArch.KIND_UNIT_ITEM:
				for k: int in arch_snapshot.sn:
					var d: int = Fp.dist(arch_snapshot.e_x[j] - arch_snapshot.s_x[k], arch_snapshot.e_y[j] - arch_snapshot.s_y[k])
					if d <= 18 * Fp.CELL:
						art += arch_snapshot.e_v[j]
						hx = arch_snapshot.s_x[k]
						hy = arch_snapshot.s_y[k]
						break
		if art >= 3000 and arch_snapshot.own_value_in_circle(hx, hy, def.radius) >= 4000:
			if ctx.cmd.launch_superweapon(hx, hy, 0):
				last_target[0] = hx
				last_target[1] = hy
				last_target[3] = art
				launch_pending_until = ctx.tick + 60
				counter_casts += 1


## How many of the packets of `wd` (target x, y) land inside my dome placed on the same point.
func _packets_inside(wd: DefSuperweapon, x: int, y: int) -> int:
	var n: int = 0
	for pk: DefImpactPacket in wd.packets:
		var d: int = Fp.dist(pk.offset_x, pk.offset_y)
		if d <= def.radius:
			n += 1
	if n == 0 and not wd.packets.is_empty():
		n = 1
	return n
