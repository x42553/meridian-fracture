class_name AiOpExpand
extends AiOp
## MCV expansion to a new resource field (ai.md 5.4.4 / AI-08). AiExpansion decides WHEN and WHERE (site score, training the MCV);
## this op moves the MCV to the deploy cell with an escort of up to 3 combat units from the reserve (they attack-move ahead of
## it and stay as its picket), deploys it and reports success when the number of my HQs grew. A refused deploy is retried a few
## cells closer to home (3 tries); the op fails when the MCV dies or after 6000 ticks. The escorts are released to the reserve
## when the op ends.
##  ADVANCING: the MCV `move`s to the cell (re-issued when idle), the escorts `attack_move` to a point 4 cells beyond it;
##  ENGAGING: the deploy order is out; success = one more HQ; after 300 ticks without one the cell moves 1/12 of the way home.

const DEPLOY_WAIT: int = 300
const MAX_TRIES: int = 3
const ESCORTS: int = 3

var mcv: int = -1
var hq_before: int = 0
var tries: int = 0
var success: bool = false
var fail_reason: String = ""
var escort_ids: PackedInt32Array = PackedInt32Array()
var _t_deploy: int = AiTypes.NEVER
var _last_cmd: int = AiTypes.NEVER
var _sq_id: int = -1


func setup_expand(p_mcv: int, x: int, y: int, p_hq_before: int) -> void:
	type = AiTypes.OpType.EXPAND
	mcv = p_mcv
	tx = x
	ty = y
	hq_before = p_hq_before
	priority = 58


func start(ctx: AiContext) -> bool:
	type = AiTypes.OpType.EXPAND
	var b: AiBrain = ctx.brain as AiBrain
	var t: AiEntityTable = ctx.kb.own
	var r: int = t.row(mcv)
	if r < 0:
		return false
	var sm: AiSquadManager = b.squads()
	var sq: AiSquad = sm.create(AiTypes.SquadKind.EXPANSION, id)
	sq.prio = priority
	_sq_id = sq.id
	squads.append(sq.id)
	b.assign_units(ctx, sq, PackedInt32Array([mcv]))
	if sm.reserve != null and sm.reserve.units.size() >= 4:
		sm.claim(1 << AiTypes.R_COMBAT, ESCORTS, t.x[r], t.y[r], 0, priority, sq)
	escort_ids = PackedInt32Array()
	for eid: int in sq.units:
		if eid != mcv:
			escort_ids.append(eid)
	committed_value = 3000
	period = 20
	timeout_tick = ctx.tick + 6000
	set_state(ctx, AiTypes.OpState.ADVANCING)
	_go(ctx)
	return true


func _go(ctx: AiContext) -> void:
	_last_cmd = ctx.tick
	ctx.cmd.move(PackedInt32Array([mcv]), tx, ty)
	if not escort_ids.is_empty():
		var t: AiEntityTable = ctx.kb.own
		var r: int = t.row(mcv)
		var dx: int = tx - (t.x[r] if r >= 0 else tx)
		var dy: int = ty - (t.y[r] if r >= 0 else ty)
		var d: int = maxi(Fp.dist(dx, dy), 1)
		ctx.cmd.attack_move(free_ids(ctx, escort_ids), tx + dx * 4 * Fp.CELL / d, ty + dy * 4 * Fp.CELL / d)


func release(ctx: AiContext) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b != null:
		for sid: int in squads:
			var sq: AiSquad = b.squads().squad(sid)
			if sq != null:
				AiOpKit.detach_support(ctx, sq)
	super.release(ctx)


func update(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	var t: AiEntityTable = ctx.kb.own
	measure(ctx, budget)
	var r: int = t.row(mcv)
	var eco: AiEconomy = b.eco()
	var hq: int = ctx.res.structure_of_kind(AiTypes.StructKind.HQ)
	if hq >= 0 and eco.struct_own[hq] > hq_before:
		success = true
		b.bump("expand_done")
		release(ctx)
		state = AiTypes.OpState.DONE
		return
	if r < 0:
		# the MCV is gone: deployed (the HQ shows up next census) or lost
		if state == AiTypes.OpState.ENGAGING and ctx.tick - _t_deploy < 40:
			return
		fail_reason = "mcv lost"
		abort(ctx, AiTypes.Err.NO_EFFECT)
		return
	if state == AiTypes.OpState.ADVANCING:
		var dx: int = t.x[r] - tx
		var dy: int = t.y[r] - ty
		var d2: int = dx * dx + dy * dy
		var stalled: bool = t.order[r] == AiTypes.OrderKind.IDLE and d2 <= 10 * 10 * Fp.CELL * Fp.CELL
		if d2 <= 3 * 3 * Fp.CELL * Fp.CELL or stalled:
			ctx.cmd.deploy(PackedInt32Array([mcv]))
			_t_deploy = ctx.tick
			set_state(ctx, AiTypes.OpState.ENGAGING)
			return
		if t.order[r] == AiTypes.OrderKind.IDLE and ctx.tick - _last_cmd >= 100:
			_go(ctx)
		elif ctx.tick - _last_cmd >= 300:
			_go(ctx)
		return
	# ENGAGING: the deploy order is out
	if ctx.tick - _t_deploy < DEPLOY_WAIT:
		return
	tries += 1
	if tries > MAX_TRIES:
		fail_reason = "deploy refused"
		abort(ctx, AiTypes.Err.NO_EFFECT)
		return
	var sites: AiResourceSites = ctx.kb.sites
	tx += (sites.home_x - tx) / 12
	ty += (sites.home_y - ty) / 12
	set_state(ctx, AiTypes.OpState.ADVANCING)
	_go(ctx)


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), mcv, tries, 1 if success else 0, escort_ids.size()]))
