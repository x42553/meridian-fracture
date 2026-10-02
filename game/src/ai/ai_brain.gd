class_name AiBrain
extends RefCounted
## The strategic hub of one AI (ai.md 2.4 / 3.5b, lean): owns the op list, the phase / posture state, the wave history and the
## strategy modules (AiStrategy slot 8, AiDefense slot 9, AiAttackPlanner slot 10, AiScout slot 14) and itself runs the ops
## (slot 11, every think). The economy hub (wants, squads, production) stays in AiEconomy; the brain reaches it through a weak
## reference (`eco()`), and forwards `add_want` / `drop_want`. `AiBrain.install(ctrl)` installs the whole set
## (AiEconomy.install + the strategy modules) and sets `ctx.brain`; call it before the first think.
##
## Extension points (systems that are not built yet): a new op type is an AiOp subclass added with `add_op`; a new strategy
## module registers itself on a free slot in `install`; AiStrategy._launch_ops is the utility table of the non-attack ops.

const OP_LIMIT: int = 16
const DANGER_TICKS: int = 4800  ## how long a hidden danger is remembered

var strategy: AiStrategy = AiStrategy.new()
var defense: AiDefense = AiDefense.new()
var attack: AiAttackPlanner = AiAttackPlanner.new()
var scout: AiScout = AiScout.new()
var powers: AiPowers = AiPowers.new()  ## support powers + superweapon (slot POWERS) and dispersal (slot DISPERSAL)
var micro: AiMicro = AiMicro.new()  ## slot 13: focus fire and kiting (Medium+ / Hard+)
var repair: AiRepair = AiRepair.new()  ## per-unit retreat, repair point, engineers (stepped from `step`)
var handlers: AiUnitHandlers = AiUnitHandlers.new()  ## special-unit rules (stepped from `step`)

var ops: Array[AiOp] = []  ## ascending id
var next_op_id: int = 1
var phase: int = AiTypes.Phase.OPENING
var posture: int = AiTypes.Posture.BALANCED
var base_phase: int = AiTypes.Phase.OPENING  ## the phase without the DESPERATE overlay
var desperate: bool = false
var aggression_delta: int = 0  ## attack-history adaptation of the personality aggression (5.7)
var min_wave_extra: int = 0
var waves_launched: int = 0
var waves_finished: int = 0
var waves_won: int = 0
var waves_lost: int = 0
var first_wave_tick: int = -1
var last_wave_end: int = AiTypes.NEVER
var severe_until: int = AiTypes.NEVER  ## a key site is under attack and the local ratio is bad
var recall_until: int = AiTypes.NEVER
var defend_ops_total: int = 0
var harass_ops_total: int = 0
var hunt_ops_total: int = 0
var op_timeouts: int = 0
var ops_aborted: int = 0
var last_wave: PackedInt32Array = PackedInt32Array([0, 0, 0])  ## ratio_q8 at launch, lost pct, destroyed pct
var danger: PackedInt32Array = PackedInt32Array()  ## remembered hidden dangers: x, y, power, tick per entry
var stats: Dictionary = {}  ## counters of the AIX1 systems (name -> count), reported by `summary`
var eng_claim: Dictionary = {}  ## engineer eid -> op id (capture / salvage ops borrow engineers from the repair pool)
var _lease: Dictionary = {}  ## unit eid -> tick until which micro / a handler controls it (ops leave it alone)
var capture_blocked: Dictionary = {}  ## neutral eid -> tick until which no capture op is started for it
var capture_block_until: int = 0
var salvage_block: Dictionary = {}  ## wreck id -> tick until which it is not tried again
var salvage_block_until: int = 0
var landing_block_until: int = 0
var naval_block_until: int = 0
var dock_block_until: int = 0
var air_block_until: int = 0
var landing_watch: PackedInt32Array = PackedInt32Array()  ## [x, y, tick] of the landing zone of a crossing landing op (the fleet escorts it)
var _last_prune: int = 0
var _eco: WeakRef = null
var _rich_since: int = -1
var _overflow_cache: bool = false


## Installs the economy hub and the strategy modules on `ctrl`; sets ctx.brain. Returns the brain. Idempotent: a controller that
## already has a brain (AiFactory.make installs one) keeps it.
static func install(ctrl: AiController) -> AiBrain:
	if ctrl.ctx.brain != null:
		return ctrl.ctx.brain as AiBrain
	var e: AiEconomy = AiEconomy.install(ctrl)
	var b: AiBrain = AiBrain.new()
	b._eco = weakref(e)
	ctrl.ctx.brain = b
	ctrl.register(AiScheduler.Slot.STRATEGY, b.strategy)
	ctrl.register(AiScheduler.Slot.DEFENSE, b.defense)
	ctrl.register(AiScheduler.Slot.ATTACK, b.attack)
	ctrl.register(AiScheduler.Slot.OPS, b)
	ctrl.register(AiScheduler.Slot.SUPPORT, b.scout)
	AiPowers.install(ctrl, b.powers)
	ctrl.register(AiScheduler.Slot.MICRO, b.micro)
	return b


## Adapter for hosts that hold an AiFactory: a `Callable(pid, level, style, seed) -> Callable(world, out)` (kept for callers that
## pre-date the install inside AiFactory.make; `install` is idempotent).
static func factory_fn(factory: AiFactory) -> Callable:
	return func(pid: int, level: int, style: int, p_seed: int) -> Callable:
		var made: Callable = factory.make(pid, level, style, p_seed)
		AiBrain.install(factory.thinker(pid).controller)
		return made


func eco() -> AiEconomy:
	return _eco.get_ref() as AiEconomy


func squads() -> AiSquadManager:
	return eco().squads


func setup(ctx: AiContext) -> void:
	repair.setup(ctx)
	handlers.setup(ctx)


# ------------------------------------------------------------------------------------------------- wants
func add_want(w: AiWant) -> AiWant:
	return eco().add_want(w)


func drop_want(id: int) -> void:
	eco().drop_want(id)


# --------------------------------------------------------------------------------------------------- ops
## Assigns an id, starts the op (claims its units). False => the op was discarded.
func add_op(ctx: AiContext, op: AiOp) -> bool:
	if ops.size() >= OP_LIMIT:
		return false
	op.id = next_op_id
	next_op_id += 1
	op.created_tick = ctx.tick
	op.state_since = ctx.tick
	op.next_update_tick = ctx.tick
	if op.timeout_tick == 0:
		op.timeout_tick = ctx.tick + 12000
	if not op.start(ctx):
		op.release(ctx)
		return false
	ops.append(op)
	return true


func op_by_id(id: int) -> AiOp:
	for o: AiOp in ops:
		if o.id == id:
			return o
	return null


func count_ops(type: int) -> int:
	var n: int = 0
	for o: AiOp in ops:
		if o.type == type and not o.is_over():
			n += 1
	return n


func ops_of(type: int) -> Array[AiOp]:
	var out: Array[AiOp] = []
	for o: AiOp in ops:
		if o.type == type and not o.is_over():
			out.append(o)
	return out


## Highest priority among the live ops of a type (0 when none).
func top_priority(type: int) -> int:
	var p: int = 0
	for o: AiOp in ops:
		if o.type == type and not o.is_over():
			p = maxi(p, o.priority)
	return p


## Slot 11: removes finished ops, times them out and updates every op that is due (ascending id).
func step(ctx: AiContext, budget: AiBudget) -> void:
	if not budget.spend(2):
		return
	_track_wealth(ctx)
	_prune_leases(ctx.tick)
	if ctx.tune("aix.repair", 1) != 0:
		repair.step(ctx, budget, self)
	if ctx.tune("aix.handlers", 1) != 0:
		handlers.step(ctx, budget, self)
	var i: int = 0
	while i < ops.size():
		var o: AiOp = ops[i]
		if o.is_over():
			o.release(ctx)
			ops.remove_at(i)
			continue
		i += 1
	for o2: AiOp in ops:
		if o2.is_over() or ctx.tick < o2.next_update_tick:
			continue
		if not budget.spend(3):
			return
		if ctx.tick >= o2.timeout_tick:
			op_timeouts += 1
			ctx.telemetry.emit(AiTypes.Tele.STALL, AiTypes.Err.OP_TIMEOUT, o2.type, ctx.tick)
			o2.abort(ctx, AiTypes.Err.OP_TIMEOUT)
			continue
		o2.next_update_tick = ctx.tick + o2.period
		o2.update(ctx, budget)


func _track_wealth(ctx: AiContext) -> void:
	if ctx.view.credits() > 4000:
		if _rich_since < 0:
			_rich_since = ctx.tick
	else:
		_rich_since = -1
	var cap: int = maxi(ctx.view.unit_cap(), 1)
	_overflow_cache = ctx.view.unit_count() * 100 >= 85 * cap or (_rich_since >= 0 and ctx.tick - _rich_since >= 1200)


## unit count >= 85 % of the cap, or credits > 4000 for 1200 ticks (ai.md 3.5b).
func overflow() -> bool:
	return _overflow_cache


## Moves `eids` (own units) into `sq`, leaving whatever squad they were in.
func assign_units(ctx: AiContext, sq: AiSquad, eids: PackedInt32Array) -> int:
	var sm: AiSquadManager = squads()
	var t: AiEntityTable = ctx.kb.own
	var n: int = 0
	for eid: int in eids:
		var r: int = t.row(eid)
		if r < 0:
			continue
		var old: AiSquad = sm.squad(t.squad[r])
		if old != null and old.id != sq.id:
			old.remove(eid)
		t.squad[r] = sq.id
		sq.add(eid)
		n += 1
	return n


## Recalls the attack ops to the site (a key site is in danger and the defenders are outmatched).
func recall_attacks(ctx: AiContext, x: int, y: int) -> int:
	var n: int = 0
	for o: AiOp in ops:
		if o.type == AiTypes.OpType.ATTACK and not o.is_over():
			var w: AiOpAttack = o as AiOpAttack
			# a wave that is winning at the enemy's gates presses on (a base race is decided by the stronger side)
			if (w.state == AiTypes.OpState.ENGAGING or w.state == AiTypes.OpState.SIEGING) and w.r_now_q8 >= 384 \
					and AiForce.dist(w.cx, w.cy, w.tx, w.ty) <= 14 * Fp.CELL:
				bump("recall_skipped")
				continue
			w.recall(ctx, x, y)
			n += 1
	recall_until = ctx.tick + 400
	return n


## Remembers a danger that killed my units without being seen (artillery, camouflage, a defense cluster out of sight): the
## attack planner adds it to the defenders of the targets nearby for `DANGER_TICKS`.
func note_danger(x: int, y: int, power: int, tick: int) -> void:
	if power <= 0:
		return
	if danger.size() >= 4 * 12:
		danger = danger.slice(4)
	danger.append(x)
	danger.append(y)
	danger.append(power)
	danger.append(tick)


## Power of the remembered dangers within `r` of (x, y), fading linearly to zero over DANGER_TICKS.
func danger_power(x: int, y: int, r: int, tick: int) -> int:
	var sum: int = 0
	var r2: int = r * r
	for i: int in danger.size() / 4:
		var age: int = tick - danger[4 * i + 3]
		if age >= DANGER_TICKS:
			continue
		var dx: int = danger[4 * i] - x
		var dy: int = danger[4 * i + 1] - y
		if dx * dx + dy * dy <= r2:
			sum += danger[4 * i + 2] * (DANGER_TICKS - age) / DANGER_TICKS
	return sum


func is_severe(ctx: AiContext) -> bool:
	return ctx.tick < severe_until


## Effective aggression: personality + the attack-history adaptation.
func aggression(ctx: AiContext) -> int:
	return clampi(ctx.pers.aggression + aggression_delta, 0, 100)


## A finished wave (5.7 attack history): value lost / value sent and the fraction of the target cluster destroyed.
func note_wave_end(ctx: AiContext, sent_value: int, lost_value: int, destroyed_pct: int, ratio_q8: int) -> void:
	waves_finished += 1
	last_wave_end = ctx.tick
	var lost_pct: int = lost_value * 100 / maxi(sent_value, 1)
	last_wave[0] = ratio_q8
	last_wave[1] = lost_pct
	last_wave[2] = destroyed_pct
	var base: int = ctx.pers.aggression
	if lost_pct > 70 and destroyed_pct < 40:
		waves_lost += 1
		aggression_delta = maxi(aggression_delta - 5, 10 - base)
		min_wave_extra = mini(min_wave_extra + 2, 12)
	elif destroyed_pct >= 70 and lost_pct < 40:
		waves_won += 1
		aggression_delta = mini(aggression_delta + 3, 15)


# ------------------------------------------------------------------------------------------------ leases and stats
## Puts `eids` under the control of micro / a handler until `until` (ops skip leased units when they issue orders).
func lease_units(eids: PackedInt32Array, until: int) -> void:
	for eid: int in eids:
		_lease[eid] = until


func lease_one(eid: int, until: int) -> void:
	_lease[eid] = until


func leased(eid: int, tick: int) -> bool:
	return _lease.has(eid) and int(_lease[eid]) > tick


func release_lease(eid: int) -> void:
	_lease.erase(eid)


func lease_count() -> int:
	return _lease.size()


func _prune_leases(tick: int) -> void:
	if _lease.is_empty() or tick - _last_prune < 40:
		return
	_last_prune = tick
	for eid: int in _lease.keys():
		if int(_lease[eid]) <= tick:
			_lease.erase(eid)


func bump(key: String, n: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n


func stat(key: String) -> int:
	return int(stats.get(key, 0))


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([phase, posture, base_phase, 1 if desperate else 0, aggression_delta, min_wave_extra,
		waves_launched, waves_finished, last_wave_end, next_op_id, defend_ops_total, harass_ops_total, hunt_ops_total,
		strategy.state_hash(), defense.state_hash(), attack.state_hash(), scout.state_hash(), danger.size(), _lease.size(),
		micro.state_hash(), repair.state_hash(), handlers.state_hash()])
	for o: AiOp in ops:
		v.append(o.state_hash())
	return AiRng.hash_ints(v)


## Compact one-line status for logs and the soak harness.
func summary() -> Dictionary:
	return {
		"phase": phase, "posture": posture, "desperate": desperate, "ops": ops.size(), "waves": waves_launched,
		"waves_done": waves_finished, "won": waves_won, "lost": waves_lost, "first_wave": first_wave_tick,
		"defends": defend_ops_total, "harass": harass_ops_total, "hunts": hunt_ops_total, "agg_delta": aggression_delta,
		"timeouts": op_timeouts, "prong_ok": attack.prong_ok, "prong_tried": attack.prong_tried, "scouts": scout.launched,
		"defend_resp": defense.responses, "recalls": defense.recalls, "why": attack.why, "last_ratio": attack.last_ratio_q8,
		"gate": attack.gate_tick, "ready": attack.ready_first, "force": attack.last_force_units, "min_units": attack.last_min_units,
		"stats": stats.duplicate(),
	}
