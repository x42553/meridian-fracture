class_name AiWatchdog
extends RefCounted
## Slot 2 (ai.md 5.15), the economy / production part: W1 economy stall, W2 line stall, W8 power stall.
##  * W1 STALL_ECON: no income for >= 1200 ticks while credits < 1400 and no collector or no refinery -> telemetry + `desperate`
##    after 2400 ticks (AiEconomy already runs the EMERGENCY wants and the collapse refund; this only reports).
##  * W2 STALL_QUEUE: the construction line, or the head of a unit queue, shows 0 progress for >= 600 ticks while credits >= 100
##    and there is no power shortage: cancel it once (refund) and re-issue; a second stall of the same def blocks it for 1200 ticks.
##  * W8 STALL_POWER: a power shortage for >= 600 ticks -> telemetry (the EMERGENCY Generator and the pause of every other
##    structure want are AiEconomy rules).
## The army / op / budget codes (W3-W7) belong to the brain and are not handled here.

const W1_TICKS: int = 1200
const W1_DESPERATE_TICKS: int = 2400
const W2_TICKS: int = 600
const W8_TICKS: int = 600
const BLOCK_TICKS: int = 1200

var desperate: bool = false
var w1_reports: int = 0
var w2_reports: int = 0
var w8_reports: int = 0
var reissues: int = 0
var _hub: WeakRef = null
var _no_income_since: int = -1
var _c_def: int = -1
var _c_prog: int = -1
var _c_since: int = 0
var _c_strikes: Dictionary = {}
var _q_prog: Dictionary = {}  ## producer eid -> [head def, progress pct, since tick]
var _last_short_report: int = AiTypes.NEVER
var _cs: PackedInt32Array = PackedInt32Array()


func bind(hub: AiEconomy) -> void:
	_hub = weakref(hub)


func setup(_ctx: AiContext) -> void:
	pass


func step(ctx: AiContext, budget: AiBudget) -> void:
	var eco: AiEconomy = _hub.get_ref()
	if eco == null or not budget.spend(8):
		return
	eco.refresh(ctx, budget)
	_w1(ctx, eco)
	_w2_construction(ctx, eco)
	_w2_queues(ctx, budget, eco)
	_w8(ctx, eco)


func _w1(ctx: AiContext, eco: AiEconomy) -> void:
	if ctx.kb.income_per_min > 0:
		_no_income_since = -1
		desperate = false
		return
	if _no_income_since < 0:
		_no_income_since = ctx.tick
	var idle: int = ctx.tick - _no_income_since
	var broken: bool = eco.collectors_alive == 0 or eco.refineries_active == 0
	if idle >= W1_TICKS and broken and eco.credits < eco.collector_price:
		w1_reports += 1
		ctx.telemetry.emit(AiTypes.Tele.STALL, AiTypes.Err.STALL_ECON, idle, ctx.tick)
		if idle >= W1_DESPERATE_TICKS:
			desperate = true


func _w2_construction(ctx: AiContext, eco: AiEconomy) -> void:
	var v: AiWorldView = ctx.view
	v.construction_state(_cs)
	if _cs[0] == 0 or _cs[0] == 2:
		_c_def = -1
		return
	if _cs[1] != _c_def or _cs[2] != _c_prog:
		_c_def = _cs[1]
		_c_prog = _cs[2]
		_c_since = ctx.tick
		return
	if ctx.tick - _c_since < W2_TICKS or eco.credits < 100 or v.power_shortage():
		return
	w2_reports += 1
	ctx.telemetry.emit(AiTypes.Tele.STALL, AiTypes.Err.STALL_QUEUE, _c_def, ctx.tick)
	var strikes: int = int(_c_strikes.get(_c_def, 0)) + 1
	_c_strikes[_c_def] = strikes
	if strikes >= 2:
		eco.block_def(_c_def, ctx.tick + BLOCK_TICKS)
	if ctx.cmd.build_cancel():
		eco.cancels += 1
		reissues += 1
		eco.planner.on_cancelled(ctx)
	_c_since = ctx.tick


func _w2_queues(ctx: AiContext, budget: AiBudget, eco: AiEconomy) -> void:
	var v: AiWorldView = ctx.view
	var q: PackedInt32Array = PackedInt32Array()
	for i: int in eco.prod_eid.size():
		if not budget.spend(1):
			return
		var id: int = eco.prod_eid[i]
		if v.queue_of(id, q) == 0:
			_q_prog.erase(id)
			continue
		var pct: int = v.queue_progress_pct(id)
		var rec: Array = _q_prog.get(id, [-1, -1, ctx.tick])
		if int(rec[0]) != q[0] or int(rec[1]) != pct:
			_q_prog[id] = [q[0], pct, ctx.tick]
			continue
		if ctx.tick - int(rec[2]) >= W2_TICKS and eco.credits >= 100 and not v.power_shortage() and not eco.collapse \
				and v.unit_cap_room() > 0 and not eco.is_held(id):
			w2_reports += 1
			ctx.telemetry.emit(AiTypes.Tele.STALL, AiTypes.Err.STALL_QUEUE, q[0], ctx.tick)
			if ctx.cmd.train_cancel(id, 0):
				eco.cancels += 1
				reissues += 1
			_q_prog[id] = [q[0], -1, ctx.tick]


func _w8(ctx: AiContext, eco: AiEconomy) -> void:
	if eco.power_short_since >= 0 and ctx.tick - eco.power_short_since >= W8_TICKS and ctx.tick - _last_short_report >= W8_TICKS:
		_last_short_report = ctx.tick
		w8_reports += 1
		ctx.telemetry.emit(AiTypes.Tele.STALL, AiTypes.Err.STALL_POWER, ctx.tick - eco.power_short_since, ctx.tick)


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([w1_reports, w2_reports, w8_reports, reissues, 1 if desperate else 0]))
