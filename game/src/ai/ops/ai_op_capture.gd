class_name AiOpCapture
extends AiOp
## Engineer capture of a neutral tech structure (ai.md 5.11): Substation (power), Salvage Depot (income), Observation Tower (sight),
## Field Hospital (heals infantry), Harbor Terminal (a free Dock, coast maps). Team: 1 Engineer + 2 escorts from the reserve;
## the escorts lead (attack-move to the structure), the Engineer gets its `capture` order when they are near (or after 300 ticks),
## the outcome is read from the structure's owner every 40 ticks; timeout 2400 ticks (the structure is then blocked for a while).
## `try_launch` is called by AiStrategy: the candidate needs an explored cell, no threat, a path of at most 45 cells from my
## base or army, no owner and `value_credits >= 300` (0.6 x the 500-credit Engineer). Mexico / Nigeria (CAPTURE_POINTS) raise the
## priority to 55 and send the first Engineer at 120 s. Without an Engineer the repair module is asked for one.

const MIN_VALUE: int = 300
const MAX_PATH_CELLS: int = 45
const TIMEOUT: int = 2400
const BLOCK_TICKS: int = 4800

var target_id: int = -1
var target_def: int = -1
var engineer: int = -1
var escorts: PackedInt32Array = PackedInt32Array()
var value: int = 0
var ordered: bool = false
var success: bool = false
var _last_check: int = AiTypes.NEVER
var _last_cmd: int = AiTypes.NEVER
var _sq_id: int = -1


## Credit value of capturing a neutral of `nd` for this AI (0 = not worth an Engineer).
static func value_of(ctx: AiContext, nd: DefNeutral) -> int:
	match nd.neutral_kind:
		DefEnums.NeutralKind.POWER_SUBSTATION:
			var short: bool = ctx.view.power_supply() - ctx.view.power_demand() < 60
			return int(nd.reward.get("power_n", 100)) * (8 if short else 4)
		DefEnums.NeutralKind.SALVAGE_DEPOT:
			return 1500
		DefEnums.NeutralKind.OBSERVATION_POST:
			return 320
		DefEnums.NeutralKind.FIELD_HOSPITAL:
			return 380 if ctx.pers.infantry >= 40 else 260
		DefEnums.NeutralKind.HARBOR_TERMINAL:
			return 420 if ctx.pers.naval >= 20 else 0
	return 0


## Best free candidate: {eid, def, x, y, value} or an empty dictionary.
static func best_candidate(ctx: AiContext, b: AiBrain, budget: AiBudget) -> Dictionary:
	var ids: PackedInt32Array = PackedInt32Array()
	ctx.view.neutral_ids(ids)
	budget.spend(2 + ids.size())
	var hx: int = ctx.kb.sites.home_x
	var hy: int = ctx.kb.sites.home_y
	var best: Dictionary = {}
	var best_s: int = -1
	for nid: int in ids:
		if int(b.capture_blocked.get(nid, 0)) > ctx.tick or ctx.view.e_owner(nid) >= 0:
			continue
		var nd: DefNeutral = ctx.view.neutral_def(ctx.view.e_def(nid))
		if nd == null or not nd.capturable:
			continue
		var x: int = ctx.view.e_x(nid)
		var y: int = ctx.view.e_y(nid)
		if not ctx.view.cell_explored(x >> Fp.CELL_SHIFT, y >> Fp.CELL_SHIFT):
			continue
		var val: int = value_of(ctx, nd)
		if val < MIN_VALUE:
			continue
		var d: int = AiForce.cells(x, y, hx, hy)
		if d > MAX_PATH_CELLS or not ctx.kb.route.connected(hx, hy, x, y, AiTypes.MoveClass.WHEELED) \
				or ctx.kb.threat_circle(x, y, 8 * Fp.CELL) > 0:
			continue
		var s: int = val * 100 / (d + 20)
		if s > best_s:
			best_s = s
			best = {"eid": nid, "def": ctx.view.e_def(nid), "x": x, "y": y, "value": val}
	return best


## Launches a capture op when the conditions of 5.11 hold. Returns true when an op was added.
static func try_launch(ctx: AiContext, b: AiBrain, budget: AiBudget) -> bool:
	var points: bool = ctx.pers.has_flag(AiTypes.doctrine_bit("CAPTURE_POINTS"))
	var earliest: int = (120 if points else ctx.tune("capture.start_s", 240)) * SimConfig.TPS
	if ctx.tick < earliest or b.desperate or b.phase < AiTypes.Phase.BUILDUP:
		return false
	if b.count_ops(AiTypes.OpType.CAPTURE) >= (2 if points else 1) or ctx.tick < b.capture_block_until:
		return false
	if b.posture == AiTypes.Posture.TURTLE and not points:
		return false
	if not budget.spend(6):
		return false
	var cand: Dictionary = best_candidate(ctx, b, budget)
	if cand.is_empty():
		b.capture_block_until = ctx.tick + 600
		return false
	if AiOpKit.engineer_count(ctx) == 0 or ctx.view.credits() < 400:
		b.repair.extra_engineers = 1  # ask the repair module for an Engineer
		b.capture_block_until = ctx.tick + 200
		return false
	var op: AiOpCapture = AiOpCapture.new()
	op.target_id = int(cand["eid"])
	op.target_def = int(cand["def"])
	op.tx = int(cand["x"])
	op.ty = int(cand["y"])
	op.value = int(cand["value"])
	op.priority = 55 if points else 40
	if b.add_op(ctx, op):
		b.repair.extra_engineers = 0
		b.bump("capture_ops")
		ctx.telemetry.emit(AiTypes.Tele.CAPTURE_STARTED, op.target_id, op.value, ctx.tick)
		return true
	b.capture_block_until = ctx.tick + 300
	return false


func start(ctx: AiContext) -> bool:
	type = AiTypes.OpType.CAPTURE
	var b: AiBrain = ctx.brain as AiBrain
	engineer = AiOpKit.claim_engineer(ctx, b, id, tx, ty)
	if engineer < 0:
		return false
	var sm: AiSquadManager = b.squads()
	var sq: AiSquad = sm.create(AiTypes.SquadKind.CAPTURE, id)
	sq.prio = priority
	_sq_id = sq.id
	squads.append(sq.id)
	b.assign_units(ctx, sq, PackedInt32Array([engineer]))
	# two escorts from the reserve, nearest to the engineer
	var t: AiEntityTable = ctx.kb.own
	var er: int = t.row(engineer)
	var got: int = sm.claim(1 << AiTypes.R_COMBAT, 2, t.x[er], t.y[er], 0, priority, sq)
	escorts = PackedInt32Array()
	for eid: int in sq.units:
		if eid != engineer:
			escorts.append(eid)
	committed_value = 500 + got * 300
	period = 20
	timeout_tick = ctx.tick + TIMEOUT
	set_state(ctx, AiTypes.OpState.ADVANCING)
	return true


func release(ctx: AiContext) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null:
		return
	AiOpKit.release_engineers(b, id)
	var sm: AiSquadManager = b.squads()
	for sid: int in squads:
		var sq: AiSquad = sm.squad(sid)
		if sq != null:
			AiOpKit.detach_support(ctx, sq)
	super.release(ctx)


func abort(ctx: AiContext, reason: int) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b != null and not success:
		b.capture_blocked[target_id] = ctx.tick + BLOCK_TICKS
		b.bump("capture_fail")
	super.abort(ctx, reason)


func update(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	measure(ctx, budget)
	var t: AiEntityTable = ctx.kb.own
	if t.row(engineer) < 0 or not ctx.view.alive(target_id):
		abort(ctx, AiTypes.Err.NO_EFFECT)
		return
	# the outcome
	if ctx.tick - _last_check >= 40:
		_last_check = ctx.tick
		if ctx.view.e_owner(target_id) == ctx.pid:
			success = true
			b.bump("capture_done")
			ctx.telemetry.emit(AiTypes.Tele.CAPTURE_DONE, target_id, value, ctx.tick)
			# hospitals and depots are worth defending a little: the escorts stay a while as a DEFENSE-less picket (released)
			release(ctx)
			state = AiTypes.OpState.DONE
			return
		if ctx.view.e_owner(target_id) >= 0:
			abort(ctx, AiTypes.Err.NO_EFFECT)  # somebody else took it
			return
	# escorts lead
	var er: int = t.row(engineer)
	if not ordered:
		var lead: int = nearest_unit(ctx, escorts, tx, ty)
		var near: bool = lead < 0
		if lead >= 0:
			var lr: int = t.row(lead)
			near = AiForce.dist(t.x[lr], t.y[lr], tx, ty) <= 12 * Fp.CELL
		if near or ctx.tick - state_since >= 300:
			ordered = true
			ctx.cmd.capture(PackedInt32Array([engineer]), target_id)
			_last_cmd = ctx.tick
			set_state(ctx, AiTypes.OpState.ENGAGING)
		elif not escorts.is_empty() and ctx.tick - _last_cmd >= 100:
			_last_cmd = ctx.tick
			ctx.cmd.attack_move(free_ids(ctx, escorts), tx, ty)
			ctx.cmd.move(PackedInt32Array([engineer]), t.x[er] + (tx - t.x[er]) / 2, t.y[er] + (ty - t.y[er]) / 2)
		return
	# the engineer walks / channels: re-issue when it is idle away from the target (interrupted), escorts hold near it
	if t.order[er] == AiTypes.OrderKind.IDLE and ctx.tick - _last_cmd >= 60:
		_last_cmd = ctx.tick
		ctx.cmd.capture(PackedInt32Array([engineer]), target_id)
	if not escorts.is_empty() and ctx.tick - state_since >= 60 and ctx.tick % 200 < period:
		ctx.cmd.attack_move(free_ids(ctx, escorts), tx, ty)


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), target_id, engineer, 1 if ordered else 0, 1 if success else 0]))
