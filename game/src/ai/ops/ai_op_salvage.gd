class_name AiOpSalvage
extends AiOp
## African Empire wreck salvage (ai.md 5.11, doctrine SALVAGE). One long-lived op per AI that owns the salvagers - Engineers,
## Reclaimers and River Wardens that stand idle in the reserve - and sends them to enemy wrecks:
##  * candidates: enemy land-vehicle wrecks the sim flags salvageable (never friendly / self-destroyed / decoy / summoned), in sight
##    now, near my base or one of my ops, with payout (20 % of the paid cost) >= 150;
##  * an assignment needs `ETA + action + 100 ticks <= wreck expiry - now` and no threat within 10 cells of the wreck;
##  * one salvager per wreck (the sim keeps one claim per wreck), nearest free salvager first, wrecks batched by proximity.
## The attack op's CLEANUP state holds the battlefield while wrecks remain (AiOpAttack, `salvage_hold`).

const ACTION_TICKS: int = 160  ## 8 s (5 s with Recovery Winches: the sim decides; this is the planning value)
const MIN_PAYOUT: int = 150
const PAYOUT_PCT: int = 20
const SCAN_PERIOD: int = 20
const MAX_ASSIGN_PER_PASS: int = 3

var assigned: Dictionary = {}  ## salvager eid -> [wreck id, tick]
var done_count: int = 0
var paid_out: int = 0
var assigned_total: int = 0
var _wreck_pos: Dictionary = {}  ## wreck id -> [x, y, value] while assigned
var _last_scan: int = AiTypes.NEVER
var _idle_since: int = AiTypes.NEVER


static func try_launch(ctx: AiContext, b: AiBrain, _budget: AiBudget) -> bool:
	if not ctx.pers.has_flag(AiTypes.doctrine_bit("SALVAGE")) or b.count_ops(AiTypes.OpType.SALVAGE) > 0:
		return false
	if ctx.tick < ctx.tune("salvage.start_s", 150) * SimConfig.TPS or ctx.tick < b.salvage_block_until:
		return false
	if salvagers(ctx, b).is_empty():
		b.salvage_block_until = ctx.tick + 200
		return false
	var op: AiOpSalvage = AiOpSalvage.new()
	op.priority = 50
	if b.add_op(ctx, op):
		b.bump("salvage_ops")
		return true
	b.salvage_block_until = ctx.tick + 400
	return false


## Idle salvagers: Engineers not borrowed by another op and Reclaimer / Warden style units standing in the reserve.
static func salvagers(ctx: AiContext, b: AiBrain) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var t: AiEntityTable = ctx.kb.own
	var sal_bit: int = 1 << AiTypes.R_SALVAGER
	var eng_bit: int = 1 << AiTypes.R_ENGINEER
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or (t.role_mask[r] & sal_bit) == 0 or (t.flags[r] & AiTypes.EF_LOADED) != 0:
			continue
		var eid: int = t.eid[r]
		if (t.role_mask[r] & eng_bit) != 0:
			if b.eng_claim.has(eid):
				continue
		elif t.squad[r] != 0 and not (b.eng_claim.has(eid)):
			continue  # a combat salvager of a wave / defense squad stays with it
		out.append(eid)
	return out


func start(ctx: AiContext) -> bool:
	type = AiTypes.OpType.SALVAGE
	period = SCAN_PERIOD
	timeout_tick = ctx.tick + 24000
	set_state(ctx, AiTypes.OpState.ENGAGING)
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


func update(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if ctx.tick - _last_scan < SCAN_PERIOD or not budget.spend(6):
		return
	_last_scan = ctx.tick
	timeout_tick = ctx.tick + 24000  # a standing job: renewed while the op works
	_bookkeeping(ctx, b)
	var free: PackedInt32Array = PackedInt32Array()
	for eid: int in salvagers(ctx, b):
		if not assigned.has(eid):
			free.append(eid)
	if free.is_empty():
		return
	var t: AiEntityTable = ctx.kb.own
	var wrecks: PackedInt32Array = _candidate_wrecks(ctx, b, budget)
	var cmds: int = 0
	for wid: int in wrecks:
		if cmds >= MAX_ASSIGN_PER_PASS or free.is_empty():
			break
		if _wreck_pos.has(wid):
			continue
		var info: PackedInt32Array = PackedInt32Array()
		ctx.view.wreck_info(wid, info)
		# nearest free salvager
		var best: int = -1
		var best_d: int = 1 << 60
		for i: int in free.size():
			var r: int = t.row(free[i])
			if r < 0:
				continue
			var d: int = AiForce.dist(t.x[r], t.y[r], info[0], info[1])
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			continue
		var sal: int = free[best]
		var sr: int = t.row(sal)
		var speed: int = maxi(ctx.unit_profile(t.def[sr]).speed, 1)
		var eta: int = best_d / speed
		if eta + ACTION_TICKS + 100 > info[3] - ctx.tick:
			continue
		# workers must be borrowed: engineers are, reclaimers stay in the reserve squad
		if (t.role_mask[sr] & (1 << AiTypes.R_ENGINEER)) != 0:
			b.eng_claim[sal] = id
		if ctx.cmd.salvage(PackedInt32Array([sal]), wid):
			assigned[sal] = [wid, ctx.tick]
			_wreck_pos[wid] = [info[0], info[1], info[2]]
			assigned_total += 1
			cmds += 1
			free.remove_at(best)
			b.bump("salvage_orders")
		elif b.eng_claim.get(sal, -1) == id:
			b.eng_claim.erase(sal)
	# idle op with no salvager for a long time ends (a new one launches when salvagers exist again)
	if free.is_empty() and assigned.is_empty() and salvagers(ctx, b).is_empty():
		if _idle_since == AiTypes.NEVER:
			_idle_since = ctx.tick
		elif ctx.tick - _idle_since > 1200:
			release(ctx)
			state = AiTypes.OpState.DONE
	else:
		_idle_since = AiTypes.NEVER


## Salvage bookkeeping: a wreck that is gone while its salvager worked on it counts as paid; assignments of dead / idle
## salvagers are dropped.
func _bookkeeping(ctx: AiContext, b: AiBrain) -> void:
	var t: AiEntityTable = ctx.kb.own
	for eid: int in assigned.keys():
		var ent: Array = assigned[eid]
		var wid: int = int(ent[0])
		var r: int = t.row(eid)
		var wreck_alive: bool = ctx.view.alive(wid)
		if r < 0:
			assigned.erase(eid)
			_wreck_pos.erase(wid)
			continue
		if not wreck_alive:
			var pos: Array = _wreck_pos.get(wid, [0, 0, 0])
			if t.order[r] == AiTypes.OrderKind.IDLE or t.order[r] == AiTypes.OrderKind.SALVAGE:
				if AiForce.dist(t.x[r], t.y[r], int(pos[0]), int(pos[1])) <= 4 * Fp.CELL:
					done_count += 1
					paid_out += int(pos[2]) * PAYOUT_PCT / 100
					b.bump("salvage_done")
					b.bump("salvage_credits", int(pos[2]) * PAYOUT_PCT / 100)
					ctx.telemetry.emit(AiTypes.Tele.SALVAGE_DONE, wid, int(pos[2]), ctx.tick)
			assigned.erase(eid)
			_wreck_pos.erase(wid)
			_return_worker(ctx, b, eid)
			continue
		if ctx.tick - int(ent[1]) > 90 and t.order[r] != AiTypes.OrderKind.SALVAGE:
			# the order failed or was overwritten: give the wreck up for a while
			assigned.erase(eid)
			_wreck_pos.erase(wid)
			b.salvage_block[wid] = ctx.tick + 1200
			_return_worker(ctx, b, eid)


func _return_worker(ctx: AiContext, b: AiBrain, eid: int) -> void:
	if b.eng_claim.get(eid, -1) == id:
		b.eng_claim.erase(eid)


## Ids of salvageable enemy land-vehicle wrecks in sight near my base / ops, best payout first.
func _candidate_wrecks(ctx: AiContext, b: AiBrain, budget: AiBudget) -> PackedInt32Array:
	var centres: PackedInt32Array = PackedInt32Array([ctx.kb.sites.home_x, ctx.kb.sites.home_y])
	for o: AiOp in b.ops:
		if (o.type == AiTypes.OpType.ATTACK or o.type == AiTypes.OpType.DEFEND) and not o.is_over() and o.alive > 0:
			centres.append(o.cx)
			centres.append(o.cy)
	var seen: Dictionary = {}
	var keyed: PackedInt64Array = PackedInt64Array()
	var ids: PackedInt32Array = PackedInt32Array()
	var info: PackedInt32Array = PackedInt32Array()
	for i: int in centres.size() / 2:
		ctx.view.wrecks_in_circle(centres[2 * i], centres[2 * i + 1], 22 * Fp.CELL, ids)
		budget.spend(1 + ids.size() / 4)
		for wid: int in ids:
			if seen.has(wid) or int(b.salvage_block.get(wid, 0)) > ctx.tick:
				continue
			seen[wid] = true
			if not ctx.view.wreck_salvageable(wid):
				continue
			ctx.view.wreck_info(wid, info)
			if not ctx.view.cell_visible(info[0] >> Fp.CELL_SHIFT, info[1] >> Fp.CELL_SHIFT):
				continue
			if info[2] * PAYOUT_PCT / 100 < MIN_PAYOUT:
				continue
			if ctx.kb.threat_circle(info[0], info[1], 10 * Fp.CELL) > 0:
				continue
			keyed.append(((1 << 22) - mini(info[2], (1 << 22) - 1)) << 24 | (wid & 0xFFFFFF))
	keyed.sort()
	var out: PackedInt32Array = PackedInt32Array()
	for k: int in keyed:
		out.append(k & 0xFFFFFF)
	return out


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), assigned.size(), done_count, paid_out, assigned_total]))
