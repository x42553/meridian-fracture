class_name AiStrategy
extends RefCounted
## Slot 8 (ai.md 5.7, every 40 ticks): game phase, posture and the launch of the non-attack ops.
##  * PHASE: OPENING until the opener has no open non-optional steps or 300 s (Easy 420 s); BUILDUP until tier >= 2 and 10 army
##    units or 600 s; MIDGAME until tier 3 or 1080 s; LATE afterwards. DESPERATE overlays them when there is no production
##    structure and no MCV, or no income for 120 s with less than 300 credits. The composition follows through
##    `comp.phase_override` (the DESPERATE overlay never changes the composition phase).
##  * POSTURE: agg = aggression + clamp((ratio_q8 - 256) / 4, -30, 30) + overflow 25 - severe attack 40; TURTLE < 25,
##    BALANCED < 60, AGGRESSIVE < 85, ALL_IN otherwise (ALL_IN only with ratio >= 2.0 or DESPERATE). A change needs two
##    consecutive evaluations.
##  * OPS: at most one new non-DEFEND op per evaluation: HARASS (harass_pct + 30 when exposed enemy collectors are known >= 40)
##    and HUNT (enemy alive, no known enemy structure). ATTACK ops come from AiAttackPlanner, DEFEND ops from AiDefense.
##    EXPAND is handled by the economy's AiExpansion; CAPTURE / LANDING / NAVAL / AIR are not built yet (extension points:
##    add a branch to `_launch_ops`).

const PHASE_NAMES: PackedStringArray = ["OPENING", "BUILDUP", "MIDGAME", "LATE", "DESPERATE"]
const POSTURE_NAMES: PackedStringArray = ["TURTLE", "BALANCED", "AGGRESSIVE", "ALL_IN"]

var evals: int = 0
var ratio_q8: int = 256  ## my army value / known enemy army value of the primary enemy (Q8)
var pending_posture: int = -1
var _last_eval: int = AiTypes.NEVER
var _no_income_since: int = -1
var _harass_block_until: int = 0
var _hunt_block_until: int = 0
var _tier: int = 1
var enemy_peak: int = 0  ## decayed peak of the enemy army value seen at once (the AI forgets units a few seconds after they leave its sight)


func setup(_ctx: AiContext) -> void:
	pass


func step(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null or ctx.tick == _last_eval or not budget.spend(6):
		return
	_last_eval = ctx.tick
	var eco: AiEconomy = b.eco()
	eco.refresh(ctx, budget)
	evals += 1
	_track_enemy_peak(ctx)
	_update_tier(ctx)
	_phase(ctx, b, eco)
	_posture(ctx, b, eco)
	if b.desperate:
		_desperate_moves(ctx, b, eco)
	_launch_ops(ctx, b, budget)


## AIT: peak of the known enemy army, decaying with an e-folding time of about 130 s. The defender estimate of a target adds the part of it that
## is not at the target (units elsewhere come to help) so a wave does not leave against a base whose army was just out of sight.
func _track_enemy_peak(ctx: AiContext) -> void:
	var seen: int = ctx.kb.est_enemy_army_value(ctx.kb.primary) if ctx.kb.primary >= 0 else 0
	enemy_peak = maxi(seen, enemy_peak - maxi(enemy_peak * 40 / 2600, 1))


# ------------------------------------------------------------------------------------------------- phase
func _update_tier(ctx: AiContext) -> void:
	var v: AiWorldView = ctx.view
	var rd: int = ctx.res.structure_of_kind(AiTypes.StructKind.RADAR)
	var lb: int = ctx.res.structure_of_kind(AiTypes.StructKind.LAB)
	var t: int = 1
	if rd >= 0 and v.struct_count(rd) > 0:
		t = 2
		if lb >= 0 and v.struct_count(lb) > 0:
			t = 3
	_tier = t


## Late-game escalation (OFF by default: `aix.escalation` 1 turns it on; the A/B soak showed no change of the outcomes): from the 12th minute the aggression grows by 4 points per minute up to +24 (Easy keeps its
## pace). The attack planner lowers its ratio floor in the same way (AiAttackPlanner.escalation_floor_drop).
static func late_escalation(ctx: AiContext) -> int:
	if ctx.cfg.level == AiTypes.Difficulty.EASY or ctx.tune("aix.escalation", 0) == 0:
		return 0
	var minutes: int = ctx.tick / (SimConfig.TPS * 60)
	return clampi((minutes - ctx.tune("escalation.start_min", 12)) * ctx.tune("escalation.agg_per_min", 4), 0, ctx.tune("escalation.agg_max", 24))


func tier() -> int:
	return _tier


func _phase(ctx: AiContext, b: AiBrain, eco: AiEconomy) -> void:
	var sec: int = ctx.tick / SimConfig.TPS
	var open_max: int = ctx.tune("strategy.opening_max_s", 300)
	if ctx.cfg.level == AiTypes.Difficulty.EASY:
		open_max = ctx.tune("strategy.opening_max_easy_s", 420)
	var ph: int = b.base_phase
	if ph == AiTypes.Phase.OPENING and (eco.opener_done() or sec >= open_max):
		ph = AiTypes.Phase.BUILDUP
	if ph == AiTypes.Phase.BUILDUP and ((_tier >= 2 and eco.army_units >= ctx.tune("strategy.buildup_army_units", 10)) \
			or sec >= ctx.tune("strategy.buildup_max_s", 600)):
		ph = AiTypes.Phase.MIDGAME
	if ph == AiTypes.Phase.MIDGAME and (_tier >= 3 or sec >= ctx.tune("strategy.midgame_max_s", 1080)):
		ph = AiTypes.Phase.LATE
	# desperate overlay
	var no_prod: bool = eco.prod_eid.is_empty() and _mcv_count(ctx, eco) == 0 and ctx.tick > 3600
	if ctx.kb.income_per_min <= 0 and ctx.tick > 2400:
		if _no_income_since < 0:
			_no_income_since = ctx.tick
	else:
		_no_income_since = -1
	var broke: bool = _no_income_since >= 0 and ctx.tick - _no_income_since >= ctx.tune("strategy.desperate_no_income_s", 120) * SimConfig.TPS \
		and eco.credits < ctx.tune("strategy.desperate_credits", 300)
	var desperate_now: bool = no_prod or broke
	if desperate_now != b.desperate:
		b.desperate = desperate_now
		ctx.telemetry.emit(AiTypes.Tele.PHASE_CHANGE, AiTypes.Phase.DESPERATE if desperate_now else ph, 1 if desperate_now else 0, ctx.tick)
	if ph != b.base_phase:
		b.base_phase = ph
		ctx.telemetry.emit(AiTypes.Tele.PHASE_CHANGE, ph, 0, ctx.tick)
	b.phase = AiTypes.Phase.DESPERATE if b.desperate else b.base_phase
	eco.comp.phase_override = b.base_phase


func _mcv_count(ctx: AiContext, eco: AiEconomy) -> int:
	var n: int = 0
	for d: int in ctx.res.units_of(AiTypes.R_MCV):
		n += eco.unit_alive[d]
	return n


# ----------------------------------------------------------------------------------------------- posture
func _posture(ctx: AiContext, b: AiBrain, eco: AiEconomy) -> void:
	var kb: AiKnowledge = ctx.kb
	var est: int = 0
	if kb.primary >= 0:
		# what is in sight, or the assumed army of that time when less is known (never "zero enemy army")
		est = maxi(kb.est_enemy_army_value(kb.primary), AiAttackPlanner.assumed_army(ctx))
	ratio_q8 = eco.army_value * 256 / maxi(1, est)
	var agg: int = b.aggression(ctx) + clampi((ratio_q8 - 256) / 4, -30, 30)
	if b.overflow():
		agg += 25
	if b.is_severe(ctx):
		agg -= 40
	agg += late_escalation(ctx)
	agg -= ctx.pers.posture_threshold_shift  # aggressive style: thresholds -10 == aggression +10 (shift is 0 or -10)
	var post: int = AiTypes.Posture.TURTLE
	if agg >= 85:
		post = AiTypes.Posture.ALL_IN
	elif agg >= 60:
		post = AiTypes.Posture.AGGRESSIVE
	elif agg >= 25:
		post = AiTypes.Posture.BALANCED
	if post == AiTypes.Posture.ALL_IN and ratio_q8 < 512 and not b.desperate:
		post = AiTypes.Posture.AGGRESSIVE
	if b.desperate and eco.army_value > 0:
		post = AiTypes.Posture.ALL_IN
	if post == b.posture:
		pending_posture = -1
		return
	if post == pending_posture or b.desperate:
		b.posture = post
		pending_posture = -1
		ctx.telemetry.emit(AiTypes.Tele.POSTURE_CHANGE, post, ratio_q8, ctx.tick)
	else:
		pending_posture = post


## DESPERATE (5.7): deploy an MCV where it stands when no production structure is left; the all-in attack comes from the
## planner (posture ALL_IN, gates relaxed) and the hunt from `_launch_ops`.
func _desperate_moves(ctx: AiContext, _b: AiBrain, eco: AiEconomy) -> void:
	if not eco.prod_eid.is_empty():
		return
	var t: AiEntityTable = ctx.kb.own
	var mcvs: PackedInt32Array = PackedInt32Array()
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_UNIT and (t.role_mask[r] & (1 << AiTypes.R_MCV)) != 0 and t.order[r] == AiTypes.OrderKind.IDLE:
			mcvs.append(t.eid[r])
	if not mcvs.is_empty():
		ctx.cmd.deploy(PackedInt32Array([mcvs[0]]))


# ------------------------------------------------------------------------------------------------- ops
func _launch_ops(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	if not budget.spend(8):
		return
	# standing and support operations (AIX1): the Dock policy, aircraft, fleet, wreck salvage, neutral capture
	if ctx.tune("aix.naval", 1) != 0:
		AiOpNaval.ensure_dock(ctx, b, budget)
	if (ctx.tune("aix.air", 1) != 0 and AiOpAir.try_launch(ctx, b, budget)) or (ctx.tune("aix.naval", 1) != 0 and AiOpNaval.try_launch(ctx, b, budget)) \
			or (ctx.tune("aix.salvage", 1) != 0 and AiOpSalvage.try_launch(ctx, b, budget)) \
			or (ctx.tune("aix.capture", 1) != 0 and AiOpCapture.try_launch(ctx, b, budget)):
		return
	# HARASS: utility = harass_pct + 30 when exposed enemy collectors are known
	if ctx.tick >= _harass_block_until and b.phase >= AiTypes.Phase.BUILDUP and b.posture >= AiTypes.Posture.BALANCED \
			and not b.desperate and b.count_ops(AiTypes.OpType.HARASS) < ctx.diff.harass_ops_max:
		var util: int = ctx.pers.harass_pct
		if _exposed_collectors(ctx) > 0:
			util += 30
		if util >= ctx.tune("strategy.harass_launch_util", 40):
			var op: AiOpHarass = AiOpHarass.new()
			if b.add_op(ctx, op):
				b.harass_ops_total += 1
				return
			_harass_block_until = ctx.tick + 600
	# HUNT: the enemy lives but no structure of it is known
	if ctx.tick >= _hunt_block_until and b.count_ops(AiTypes.OpType.HUNT) == 0 and ctx.kb.primary >= 0 \
			and ctx.tick >= ctx.tune("hunt.min_s", 480) * SimConfig.TPS and _known_enemy_structures(ctx) == 0:
		var hop: AiOpHunt = AiOpHunt.new()
		if b.add_op(ctx, hop):
			b.hunt_ops_total += 1
			return
		_hunt_block_until = ctx.tick + 400


## Enemy collectors seen within the last 60 s (the harass targets).
func _exposed_collectors(ctx: AiContext) -> int:
	var t: AiEntityTable = ctx.kb.enemy_units
	var n: int = 0
	for i: int in t.count:
		if (t.role_mask[i] & (1 << AiTypes.R_COLLECTOR)) != 0 and ctx.tick - t.last_seen[i] <= 60 * SimConfig.TPS:
			n += 1
	return n


## Structure ghosts (real or presumed) of live enemies: while there is one, the attack planner has somewhere to go.
func _known_enemy_structures(ctx: AiContext) -> int:
	var g: AiGhostTable = ctx.kb.ghosts
	var n: int = 0
	for i: int in g.count:
		if g.owner[i] >= 0 and ctx.view.player_alive(g.owner[i]):
			n += 1
	return n


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([evals, ratio_q8, pending_posture, _tier, _harass_block_until, _hunt_block_until, enemy_peak]))
