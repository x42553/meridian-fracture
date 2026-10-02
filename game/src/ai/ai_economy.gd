class_name AiEconomy
extends RefCounted
## Slot 4 (ai.md 5.4): the money side of one AI and the hub of the AI-04/05 modules (build planner, placer, tech, watchdog,
## production, composition, squads, expansion), created by `AiEconomy.install(controller)`.
##  * CENSUS (once per think): what I own by def / role, what sits in the queues, the burn rate of the running lines.
##  * WANTS: a sorted list of AiWant (structures and units). `allocate` grants at most one structure per pass (single
##    construction queue) and unit wants (collectors, MCV) under the burn-rate rule of 5.4.1: a line starts only when
##    `avail >= min(cost, 8 s of its burn)` and (prio > 20) `burn_total + line_burn <= income + credits / 30 s`.
##  * COLLECTOR RESERVE: when a refinery exists and collectors (alive + queued) < target, everything of prio > 20 (tech,
##    defense, army, counters) may only spend what is above the price of a Collector, so a raid on the collectors can always be
##    answered. When NO collector is alive or queued the AI is in COLLAPSE: only EMERGENCY (prio 0) wants may spend; running
##    construction (not a refinery) is cancelled and the heads of the unit queues are cancelled / held to refund credits until
##    a collector (and if needed a refinery) can be paid. Holds are released when the collapse is over.
##  * POWER: a structure with a power draw needs `margin + pending - |d| >= margin_min`, otherwise a Generator want (prio 15)
##    is inserted; a shortage makes the Generator EMERGENCY and pauses every other structure want.
##  * DEFENSE investment (5.4.5): defense wants until the spend share `defense_pct x phase_mult` is reached, capped at 40 %.
## The want / fund API used by the other modules: add_want, try_fund, avail_for, refresh, healthy, opener_done.

enum SC { ECON = 0, ARMY = 1, DEFENSE = 2, TECH = 3 }
const SC_COUNT: int = 4
const P_EMERGENCY: int = 0
const P_OPENER: int = 10
const P_POWER: int = 15
const P_ECON: int = 20
const P_COUNTER: int = 25
const P_LAB: int = 28  ## the Laboratory (T3, advanced defense, superweapon) goes before the second Barracks / Factory
const P_TECH: int = 30
const P_ARMY: int = 40
const P_EXPAND: int = 24  ## deviation from 5.4.1 (50): an expansion is an economy investment, so the MCV outranks tech, defense and army
const P_DEFENSE: int = 55
const P_DEFENSE_HOT: int = 25
const FUND_SECONDS: int = 8
const SPEND_DECAY_DIV: int = 300  ## per 20 ticks: a 300 s memory for the spend classes
const ISSUE_RETRY_TICKS: int = 60
const RECOVER_PERIOD: int = 40
const REPAIR_PERIOD: int = 100
const REPAIR_ROWS: int = 48
const REPAIR_MIN_CREDITS: int = 300
const COLLAPSE_CANCEL_MARGIN: int = 300  ## the running lines are cancelled while credits < Collector price + this
const INCOME_STEP: int = 100  ## ticks between the samples of the income history
const BANK_LOW_PCT: int = 50  ## of a Collector's price: below it the unit lines pause
const BANK_HIGH_PCT: int = 100  ## ... and resume at it
const STRUCT_WAIT_HOLD: int = 60  ## ticks a structure want may wait unfunded before the unit lines are held
const MCV_LINE_TICKS: int = 900  ## how long a Factory line is kept free for the expansion MCV (it must be queued within 45 s, else the army lines go on)
const PHASE_DEF_MULT: PackedInt32Array = [60, 100, 100, 80, 80]  ## % by AiTypes.Phase

# ---- modules (strong refs; they hold the hub weakly)
var placer: AiPlacer = AiPlacer.new()
var planner: AiBuildPlanner = AiBuildPlanner.new()
var tech: AiTech = AiTech.new()
var watchdog: AiWatchdog = AiWatchdog.new()
var production: AiProduction = AiProduction.new()
var comp: AiComposition = AiComposition.new()
var squads: AiSquadManager = AiSquadManager.new()
var expansion: AiExpansion = AiExpansion.new()
var doctrine: AiDoctrine = null

# ---- wants
var wants: Array[AiWant] = []
var _next_id: int = 1

# ---- census (valid for `census_tick`)
var census_tick: int = -1
var struct_own: PackedInt32Array = PackedInt32Array()  ## by structure def: own entities (also under construction)
var struct_q: PackedInt32Array = PackedInt32Array()  ## by structure def: waiting in the construction queue
var unit_alive: PackedInt32Array = PackedInt32Array()  ## by unit def
var unit_queued: PackedInt32Array = PackedInt32Array()
var role_alive: PackedInt32Array = PackedInt32Array()  ## composition role -> alive units
var role_queued: PackedInt32Array = PackedInt32Array()
var role_value: PackedInt32Array = PackedInt32Array()  ## composition role -> cost x hp fraction of alive units
var army_value: int = 0
var army_units: int = 0
var detector_alive: int = 0
var collectors_alive: int = 0
var collectors_queued: int = 0
var collector_target: int = 0
var collector_base: int = 0  ## the collector target without the AIT boost (what the reserve and hold rules protect)
var want_collectors: bool = false  ## fewer collectors than collector_target (base + boost)
var refineries_active: int = 0
var refineries_total: int = 0
var ref_pos: PackedInt32Array = PackedInt32Array()  ## [x, y] of my refineries
var prod_eid: PackedInt32Array = PackedInt32Array()  ## active producers (kind != refinery-only too)
var prod_kind: PackedInt32Array = PackedInt32Array()  ## AiTypes.StructKind of each
var prod_qlen: PackedInt32Array = PackedInt32Array()
var defense_count: int = 0

# ---- money
var credits: int = 0
var income_per_s: int = 0
var avail: int = 0  ## credits above the base reserve, minus what was granted in this pass
var burn_total: int = 0
var burn_cap: int = 0
var collector_price: int = 1400
var need_collector: bool = false
var collapse: bool = false
var collapse_since: int = -1
var pass_tick: int = -1
var struct_wait: bool = false  ## a structure want of prio <= 30 waits for funds: the unit lines must not eat the credits
var struct_wait_since: int = -1
var struct_reserve: int = 0
var spent: PackedInt32Array = PackedInt32Array()  ## by SC, decayed
var spent_total: int = 0
var cancels: int = 0
var min_credits_seen: int = 1 << 30

# ---- power
var margin: int = 0
var pending_power: int = 0
var margin_min: int = 0
var power_short_since: int = -1

var collector_def: int = -1
var _ctx: AiContext = null
var repairs: int = 0  ## structure repair switched on so far
var _last_repair: int = AiTypes.NEVER
var _repair_cursor: int = 0
var _bank_hold: bool = false
var _refinery_seen: bool = false  ## a Refinery has been active at least once: from then on "no collector" is a collapse
var _hist_t: PackedInt32Array = PackedInt32Array()
var _hist_v: PackedInt32Array = PackedInt32Array()
var _held: Dictionary = {}  ## producer eid -> true (queues I put on hold)
var _last_recover: int = AiTypes.NEVER
var _last_decay: int = 0
var _idle_since: Dictionary = {}
var _defense_rr: int = 0
var _blocked_defs: Dictionary = {}  ## struct def -> until tick (watchdog blacklist)


## Creates the hub, registers every module on its slot and returns it. Call before the first think.
static func install(ctrl: AiController) -> AiEconomy:
	var e: AiEconomy = AiEconomy.new()
	e.planner.bind(e)
	e.tech.bind(e)
	e.watchdog.bind(e)
	e.production.bind(e)
	ctrl.register(AiScheduler.Slot.ECONOMY, e)
	ctrl.register(AiScheduler.Slot.WATCHDOG, e.watchdog)
	ctrl.register(AiScheduler.Slot.BUILD, e.planner)
	ctrl.register(AiScheduler.Slot.TECH, e.tech)
	ctrl.register(AiScheduler.Slot.PRODUCTION, e.production)
	return e


func setup(ctx: AiContext) -> void:
	_ctx = ctx
	var data: GameData = ctx.view.game_data()
	doctrine = AiDoctrine.resolve(ctx.store, ctx.view.roster_id_of(ctx.pid))
	for msg: String in doctrine.errors:
		Log.warn("ai", "doctrine: %s" % msg)
	placer.setup(ctx)
	comp.setup(ctx, doctrine, self)
	squads.setup(ctx)
	expansion.setup(ctx, self)
	struct_own.resize(data.structures.size())
	struct_q.resize(data.structures.size())
	unit_alive.resize(data.units.size())
	unit_queued.resize(data.units.size())
	role_alive.resize(AiTypes.ROLE_COUNT)
	role_queued.resize(AiTypes.ROLE_COUNT)
	role_value.resize(AiTypes.ROLE_COUNT)
	spent.resize(SC_COUNT)
	spent.fill(0)
	collector_def = ctx.res.first(AiTypes.R_COLLECTOR)
	if collector_def >= 0:
		collector_price = ctx.view.unit_cost(collector_def)
	margin_min = ctx.store.tune_by_level("econ.margin_min", ctx.cfg.level, 20)
	_last_decay = ctx.tick


## Credits kept back for the expansion MCV that is being trained (its price, 0 when it is already paid for).
func _mcv_reserve() -> int:
	var def: int = _ctx.res.first(AiTypes.R_MCV)
	if def < 0:
		return 0
	var pct: int = _ctx.tune("exp.reserve_queued_pct", 20) if unit_queued[def] > 0 else _ctx.tune("exp.reserve_pct", 40)
	return _ctx.view.unit_cost(def) * pct / 100


## True while an expansion MCV is wanted but neither queued nor built: the production lines leave one Factory free for it.
func mcv_wanted_unqueued() -> bool:
	if expansion.state != AiExpansion.State.TRAINING or _ctx == null or _ctx.tick - expansion.training_since() > MCV_LINE_TICKS:
		return false
	var def: int = _ctx.res.first(AiTypes.R_MCV)
	return def >= 0 and unit_queued[def] == 0 and role_have(AiTypes.R_MCV) == 0


## Row of the producer (of the MCV's kind) with the shortest queue: the line `mcv_wanted_unqueued` keeps free; -1 if none.
func mcv_slot_row() -> int:
	var def: int = _ctx.res.first(AiTypes.R_MCV)
	if def < 0:
		return -1
	var kind: int = producer_kind_of(_ctx, def)
	var best: int = -1
	for i: int in prod_eid.size():
		if prod_kind[i] == kind and (best < 0 or prod_qlen[i] < prod_qlen[best]):
			best = i
	return best


## True when the army is not small against the enemy army the AI believes in (`econ.safe_army_pct` of the larger of the assumed army of this
## minute and the decayed peak of the army seen): economy investments beyond the base group (extra Collectors, the expansion MCV) wait for
## the army otherwise, so a raided army never leaves the base with a 10-Collector economy and nothing to defend it.
func econ_safe(ctx: AiContext, pct: int = -1) -> bool:
	var b: AiBrain = ctx.brain as AiBrain
	var peak: int = b.strategy.enemy_peak if b != null else 0
	var need: int = maxi(AiAttackPlanner.assumed_army(ctx), peak) * (ctx.store.tune("econ.safe_army_pct", 60) if pct < 0 else pct) / 100
	return army_value >= need and (army_units >= ctx.store.tune("econ.safe_army_units", 3) or ctx.tick >= ctx.store.tune("econ.early_army_until_s", 330) * SimConfig.TPS)


## Number of active producers of a structure kind (census of this pass).
func prod_count_of(kind: int) -> int:
	var n: int = 0
	for k: int in prod_kind:
		if k == kind:
			n += 1
	return n


func is_held(producer_eid: int) -> bool:
	return _held.has(producer_eid)


func now_tick() -> int:
	return _ctx.tick if _ctx != null else 0


func step(ctx: AiContext, budget: AiBudget) -> void:
	if not budget.spend(6):
		return
	refresh(ctx, budget)
	planner.update_wants(ctx, budget)
	_collectors(ctx, budget)
	_power(ctx)
	_recover(ctx, budget)
	_holds(ctx, budget)
	expansion.step(ctx, budget, self)
	_defense(ctx)
	_allocate(ctx, budget)
	_idle_collectors(ctx, budget)
	_repair_structs(ctx, budget)


# ------------------------------------------------------------------------------------------------- census
func refresh(ctx: AiContext, budget: AiBudget) -> void:
	if census_tick == ctx.tick:
		return
	census_tick = ctx.tick
	_ctx = ctx
	var v: AiWorldView = ctx.view
	var kb: AiKnowledge = ctx.kb
	var t: AiEntityTable = kb.own
	budget.spend(2 + t.count / 8)
	struct_own.fill(0)
	struct_q.fill(0)
	unit_alive.fill(0)
	unit_queued.fill(0)
	role_alive.fill(0)
	role_queued.fill(0)
	role_value.fill(0)
	army_value = 0
	army_units = 0
	detector_alive = 0
	collectors_alive = 0
	collectors_queued = 0
	defense_count = 0
	ref_pos.resize(0)
	prod_eid.resize(0)
	prod_kind.resize(0)
	prod_qlen.resize(0)
	var col_bit: int = 1 << AiTypes.R_COLLECTOR
	var combat_bit: int = 1 << AiTypes.R_COMBAT
	var det_bit: int = 1 << AiTypes.R_DETECTOR
	for r: int in t.count:
		var d: int = t.def[r]
		if t.kind[r] == AiTypes.KIND_STRUCTURE:
			struct_own[d] += 1
			var sk: int = ctx.res.kind_of_structure(d)
			if sk == AiTypes.StructKind.REFINERY:
				ref_pos.append(t.x[r])
				ref_pos.append(t.y[r])
			elif sk == AiTypes.StructKind.WATCHTOWER or sk == AiTypes.StructKind.AT_TURRET or sk == AiTypes.StructKind.AA_BATTERY \
					or sk == AiTypes.StructKind.ADV_DEFENSE:
				defense_count += 1
		elif t.kind[r] == AiTypes.KIND_UNIT:
			unit_alive[d] += 1
			var m: int = t.role_mask[r]
			if (m & col_bit) != 0:
				collectors_alive += 1
				continue
			var val: int = t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1)
			var cr: int = comp.comp_role_of_def[d]
			if cr >= 0:
				role_alive[cr] += 1
				role_value[cr] += val
			if (m & combat_bit) != 0:
				army_units += 1
				army_value += val
				if (m & det_bit) != 0:
					detector_alive += 1
	for s: int in v.construction_queue():
		struct_q[s] += 1
	# producers and their queues
	var q: PackedInt32Array = PackedInt32Array()
	var col_units: PackedInt32Array = ctx.res.units_of(AiTypes.R_COLLECTOR)
	for id: int in v.producer_ids():
		var row: int = t.row(id)
		if row < 0 or (t.flags[row] & AiTypes.EF_UNDER_CONSTRUCTION) != 0:
			continue
		var k: int = ctx.res.kind_of_structure(t.def[row])
		var n: int = v.queue_of(id, q)
		prod_eid.append(id)
		prod_kind.append(k)
		prod_qlen.append(n)
		budget.spend(1)
		for u: int in q:
			unit_queued[u] += 1
			if col_units.has(u):
				collectors_queued += 1
			var cr2: int = comp.comp_role_of_def[u]
			if cr2 >= 0:
				role_queued[cr2] += 1
				role_value[cr2] += v.unit_cost(u)
	refineries_total = 0
	refineries_active = 0
	var rdef: int = ctx.res.structure_of_kind(AiTypes.StructKind.REFINERY)
	if rdef >= 0:
		refineries_total = struct_own[rdef] + struct_q[rdef]
		refineries_active = v.struct_count(rdef)
	_events(ctx)
	_spend_decay(ctx)
	_metrics(ctx)


func _events(ctx: AiContext) -> void:
	var kb: AiKnowledge = ctx.kb
	for rec: PackedInt32Array in kb.events:
		if rec[0] != AiTypes.Ev.OWN_SPAWNED:
			continue
		var row: int = kb.own.row(rec[1])
		if row < 0:
			continue
		var paid: int = rec[5]
		var d: int = rec[2]
		if kb.own.kind[row] == AiTypes.KIND_STRUCTURE:
			var k: int = ctx.res.kind_of_structure(d)
			var sc: int = SC.ECON
			var tele: int = 0
			match k:
				AiTypes.StructKind.RADAR:
					sc = SC.TECH
					tele = AiTypes.Tele.FIRST_RADAR
				AiTypes.StructKind.LAB, AiTypes.StructKind.RELAY, AiTypes.StructKind.SUPERWEAPON:
					sc = SC.TECH
					tele = AiTypes.Tele.FIRST_LAB
				AiTypes.StructKind.WATCHTOWER, AiTypes.StructKind.AT_TURRET, AiTypes.StructKind.ADV_DEFENSE:
					sc = SC.DEFENSE
				AiTypes.StructKind.AA_BATTERY:
					sc = SC.DEFENSE
					tele = AiTypes.Tele.FIRST_AA
				AiTypes.StructKind.BARRACKS:
					tele = AiTypes.Tele.FIRST_BARRACKS
				AiTypes.StructKind.FACTORY:
					tele = AiTypes.Tele.FIRST_FACTORY
			_add_spent(sc, paid)
			if tele != 0:
				ctx.telemetry.emit_first(tele, d, 0, ctx.tick)
		elif kb.own.kind[row] == AiTypes.KIND_UNIT:
			var m: int = kb.own.role_mask[row]
			var econ_unit: bool = (m & ((1 << AiTypes.R_COLLECTOR) | (1 << AiTypes.R_MCV) | (1 << AiTypes.R_ENGINEER))) != 0
			_add_spent(SC.ECON if econ_unit else SC.ARMY, paid)
			if (m & (1 << AiTypes.R_TANK_MAIN)) != 0:
				ctx.telemetry.emit_first(AiTypes.Tele.FIRST_TANK, d, 0, ctx.tick)


func _add_spent(sc: int, amount: int) -> void:
	spent[sc] += amount
	spent_total += amount


func _spend_decay(ctx: AiContext) -> void:
	while ctx.tick - _last_decay >= 20:
		_last_decay += 20
		spent_total = 0
		for c: int in SC_COUNT:
			spent[c] -= spent[c] / SPEND_DECAY_DIV
			spent_total += spent[c]


func _metrics(ctx: AiContext) -> void:
	var v: AiWorldView = ctx.view
	credits = v.credits()
	min_credits_seen = mini(min_credits_seen, credits)
	income_per_s = _income_window(ctx)
	# collector target
	var field_slots: int = 0
	var sites: AiResourceSites = ctx.kb.sites
	var slots_per: int = ctx.store.tune("econ.collector_slots_per_field", 3)
	for i: int in sites.count:
		if sites.kind[i] <= AiResourceSites.K_NEAR and sites.left[i] > 0:
			field_slots += slots_per
	collector_target = 0
	if refineries_active > 0:
		var kx10: int = ctx.diff.collector_k_x10
		collector_base = clampi((refineries_active * kx10 + 9) / 10, 1, maxi(field_slots, 1))
		if ctx.cfg.level != AiTypes.Difficulty.EASY:
			kx10 += ctx.store.tune("econ.collector_k_boost_x10", 0) + clampi(ctx.pers.eco_x10, -10, 10)  # AIT: the data sheet recommends 3 Collectors per Refinery
		collector_target = clampi((refineries_active * kx10 + 9) / 10, 1, maxi(field_slots, 1))
	else:
		collector_base = 0
	var have: int = collectors_alive + collectors_queued
	need_collector = collector_base > 0 and have < collector_base  # the reserve / hold rules protect the base group only
	want_collectors = collector_target > 0 and have < collector_target
	if refineries_active > 0:
		_refinery_seen = true
	var seen_refinery: bool = _refinery_seen
	var was: bool = collapse
	collapse = seen_refinery and collector_def >= 0 and collectors_alive == 0
	if collapse and not was:
		collapse_since = ctx.tick
	elif not collapse:
		collapse_since = -1
	# power
	margin = v.power_supply() - v.power_demand()
	pending_power = 0
	for s: int in v.construction_queue():
		pending_power += v.struct_power(s)
	var t: AiEntityTable = ctx.kb.own
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_STRUCTURE and (t.flags[r] & AiTypes.EF_UNDER_CONSTRUCTION) != 0:
			pending_power += v.struct_power(t.def[r])
	if v.power_shortage():
		if power_short_since < 0:
			power_short_since = ctx.tick
	else:
		power_short_since = -1
	# base allowance of this pass
	var reserve: int = ctx.store.tune("econ.reserve_credits", 300)
	if ctx.tick < 1200 or not opener_done():
		reserve = 0
	avail = credits - reserve
	burn_cap = income_per_s + credits / maxi(ctx.store.tune("econ.burn_horizon_s", 30), 1)
	burn_total = _running_burn(ctx)
	pass_tick = ctx.tick


## Credits per second earned over the last 1200 ticks (a 13-sample history of the monotonic income counter); the knowledge
## base EMA is far too jumpy for this (income arrives in lumps of ~700 per unload).
func _income_window(ctx: AiContext) -> int:
	var total: int = ctx.view.income_total()
	var n: int = _hist_t.size()
	if n == 0 or ctx.tick - _hist_t[n - 1] >= INCOME_STEP:
		_hist_t.append(ctx.tick)
		_hist_v.append(total)
		if _hist_t.size() > 13:
			_hist_t.remove_at(0)
			_hist_v.remove_at(0)
	var first: int = 0
	var span: int = ctx.tick - _hist_t[first]
	if span < 200:
		return ctx.kb.income_ema_q8 >> 8
	return (total - _hist_v[first]) * SimConfig.TPS / span


## Credits per second the running lines draw (construction, unit queues, research). Held queues draw nothing.
func _running_burn(ctx: AiContext) -> int:
	var v: AiWorldView = ctx.view
	var b: int = 0
	var cs: PackedInt32Array = PackedInt32Array()
	v.construction_state(cs)
	if cs[0] == 1:
		b += v.struct_cost(cs[1]) * SimConfig.TPS / maxi(v.struct_ticks(cs[1]), 1)
	var q: PackedInt32Array = PackedInt32Array()
	for id: int in prod_eid:
		if not _held.has(id) and v.queue_of(id, q) > 0:
			b += v.unit_cost(q[0]) * SimConfig.TPS / maxi(v.unit_ticks(q[0]), 1)
	return b


# ---------------------------------------------------------------------------------------------- funding
## Credits usable by a line of priority `prio` in this pass (the collector reserve and the collapse rule applied).
func avail_for(prio: int) -> int:
	if prio <= P_EMERGENCY:
		return credits
	if collapse:
		return -1
	var a: int = avail
	if prio > P_EXPAND and expansion.state == AiExpansion.State.TRAINING and _ctx != null and _ctx.tune("exp.reserve", 1) != 0:
		a -= _mcv_reserve()  # AIT: an expansion MCV in training is paid before tech, defense and army lines may start
	if prio > P_ECON and need_collector:
		a -= collector_price
	elif prio > P_TECH and opener_done():
		a -= collector_price / 2  # standing reserve: half a Collector, so a raid on the collectors can be answered
	return a


## 0 = the line may start, 1 = gated by the burn cap, 2 = not enough credits (progressive payment needs 8 s of the burn).
func fund_status(prio: int, cost: int, ticks: int) -> int:
	var lb: int = cost * SimConfig.TPS / maxi(ticks, 1)
	if avail_for(prio) < mini(cost, lb * FUND_SECONDS):
		return 2
	if prio > P_ECON and burn_total + lb > burn_cap:
		return 1
	return 0


func take_fund(cost: int, ticks: int) -> void:
	var lb: int = cost * SimConfig.TPS / maxi(ticks, 1)
	avail -= mini(cost, lb * FUND_SECONDS)
	burn_total += lb


## Reserves funding for a new line: true and the pass state is updated when the line may start.
func try_fund(prio: int, cost: int, ticks: int) -> bool:
	if fund_status(prio, cost, ticks) != 0:
		return false
	take_fund(cost, ticks)
	return true


func healthy() -> bool:
	return refineries_active >= 2 and collectors_alive >= mini(2, maxi(collector_base, 1)) and not collapse


func opener_done() -> bool:
	return planner.spine_done


func block_def(def: int, until_tick: int) -> void:
	_blocked_defs[def] = until_tick


func def_blocked(def: int) -> bool:
	return _blocked_defs.has(def) and int(_blocked_defs[def]) > now_tick()


# ----------------------------------------------------------------------------------------------- wants
func add_want(w: AiWant) -> AiWant:
	for o: AiWant in wants:
		if o.kind == w.kind and o.def == w.def and o.role == w.role and o.origin == w.origin and o.step_id == w.step_id and o.is_open():
			o.prio = mini(o.prio, w.prio)
			o.count = maxi(o.count, w.count)
			if w.deadline > 0:
				o.deadline = w.deadline
			if w.site_x >= 0:
				o.site_x = w.site_x
				o.site_y = w.site_y
			return o
	w.id = _next_id
	_next_id += 1
	w.created = now_tick()
	wants.append(w)
	return w


func drop_want(id: int) -> void:
	for w: AiWant in wants:
		if w.id == id:
			w.state = AiTypes.WantState.DROPPED


func find_want(kind: int, def: int, origin: int) -> AiWant:
	for w: AiWant in wants:
		if w.kind == kind and w.def == def and w.origin == origin and w.is_open():
			return w
	return null


## Sets the placement hint of `w` to my `idx`-th refinery (round robin), if any.
func site_hint_refinery(w: AiWant, idx: int) -> void:
	var n: int = ref_pos.size() / 2
	if n <= 0:
		return
	var i: int = idx % n
	w.site_x = ref_pos[2 * i]
	w.site_y = ref_pos[2 * i + 1]


func role_have(role: int) -> int:
	var n: int = 0
	for d: int in _ctx.res.units_of(role):
		n += unit_alive[d] + unit_queued[d]
	return n


func _satisfied(w: AiWant) -> bool:
	match w.kind:
		AiTypes.WantKind.STRUCT:
			return struct_own[w.def] >= w.count
		AiTypes.WantKind.UNIT_ROLE:
			return role_have(w.role) >= w.count
		AiTypes.WantKind.UNIT_DEF:
			return unit_alive[w.def] + unit_queued[w.def] >= w.count
	return false


# ----------------------------------------------------------------------------------------------- collectors
func _collectors(ctx: AiContext, budget: AiBudget) -> void:
	if collector_def < 0 or not budget.spend(2):
		return
	if collapse:
		if collectors_queued == 0:
			var w: AiWant = AiWant.make(AiTypes.WantKind.UNIT_ROLE, collector_def, AiTypes.R_COLLECTOR, 1, P_EMERGENCY, AiTypes.WantOrigin.EMERGENCY)
			w.deadline = ctx.tick + 200
			add_want(w)
	elif want_collectors and collectors_queued < (1 if credits < 2500 else 2):
		var w2: AiWant = AiWant.make(AiTypes.WantKind.UNIT_ROLE, collector_def, AiTypes.R_COLLECTOR, collector_target, P_ECON, AiTypes.WantOrigin.ECONOMY)
		w2.count = collector_target
		w2.deadline = ctx.tick + 200
		add_want(w2)


func _idle_collectors(ctx: AiContext, budget: AiBudget) -> void:
	# the sim gives an idle Collector an auto-harvest order; this only catches one that stayed idle for a long time
	var t: AiEntityTable = ctx.kb.own
	var col_bit: int = 1 << AiTypes.R_COLLECTOR
	var idle: PackedInt32Array = PackedInt32Array()
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or (t.role_mask[r] & col_bit) == 0:
			continue
		var id: int = t.eid[r]
		if t.order[r] != AiTypes.OrderKind.IDLE:
			_idle_since.erase(id)
			continue
		if not _idle_since.has(id):
			_idle_since[id] = ctx.tick
		elif ctx.tick - int(_idle_since[id]) >= 200:
			idle.append(id)
	if idle.is_empty() or not budget.spend(4):
		return
	var site: int = ctx.kb.sites.best_free_site(ctx.kb.sites.home_x, ctx.kb.sites.home_y, AiResourceSites.K_FAR)
	if site < 0:
		return
	var sites: AiResourceSites = ctx.kb.sites
	ctx.cmd.harvest(idle, sites.id[site], sites.x[site], sites.y[site])
	for id2: int in idle:
		_idle_since[id2] = ctx.tick


# ------------------------------------------------------------------------------------------ repair spending
## Structure repair (5.4.6): on below 60 % hp when no enemy stands within 10 cells and there is money, off at 95 %.
func _repair_structs(ctx: AiContext, budget: AiBudget) -> void:
	if ctx.tick - _last_repair < REPAIR_PERIOD or not budget.spend(2):
		return
	_last_repair = ctx.tick
	var t: AiEntityTable = ctx.kb.own
	var near: PackedInt32Array = PackedInt32Array()
	var checked: int = 0
	while checked < mini(t.count, REPAIR_ROWS):
		if _repair_cursor >= t.count:
			_repair_cursor = 0
		var r: int = _repair_cursor
		_repair_cursor += 1
		checked += 1
		if t.kind[r] != AiTypes.KIND_STRUCTURE or t.hp_max[r] <= 0 or (t.flags[r] & AiTypes.EF_UNDER_CONSTRUCTION) != 0:
			continue
		var pct: int = t.hp[r] * 100 / t.hp_max[r]
		var on: bool = (t.flags[r] & AiTypes.EF_REPAIRING) != 0
		if on and pct >= 95:
			if budget.spend(1):
				ctx.cmd.set_structure_repair(t.eid[r], false)
		elif not on and pct < 60 and credits >= REPAIR_MIN_CREDITS and budget.spend(3):
			if ctx.kb.enemies_near(t.x[r], t.y[r], 10 * Fp.CELL, near) == 0:
				ctx.cmd.set_structure_repair(t.eid[r], true)
				repairs += 1


# ------------------------------------------------------------------------------------------------- power
func _power(ctx: AiContext) -> void:
	var gen: int = ctx.res.structure_of_kind(AiTypes.StructKind.GENERATOR)
	if gen < 0 or not ctx.view.has_hq():
		return
	if ctx.view.power_shortage() and struct_q[gen] == 0:
		var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, gen, -1, struct_own[gen] + 1, P_EMERGENCY, AiTypes.WantOrigin.EMERGENCY)
		w.site_kind = AiPlacer.Site.BACK
		w.deadline = ctx.tick + 200
		add_want(w)


func ensure_generator(ctx: AiContext) -> void:
	var gen: int = ctx.res.structure_of_kind(AiTypes.StructKind.GENERATOR)
	if gen < 0:
		return
	var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, gen, -1, struct_own[gen] + struct_q[gen] + 1, P_POWER, AiTypes.WantOrigin.POWER_GRID)
	w.site_kind = AiPlacer.Site.BACK
	w.deadline = ctx.tick + 300
	add_want(w)


func _power_ok(ctx: AiContext, w: AiWant, target: int) -> bool:
	var d: int = ctx.view.struct_power(target)
	if d >= 0 or w.origin == AiTypes.WantOrigin.EMERGENCY:
		return true
	if ctx.view.power_shortage():
		return false
	if margin + pending_power + d >= margin_min:
		return true
	ensure_generator(ctx)
	return false


# -------------------------------------------------------------------------------------- collapse recovery
func _recover(ctx: AiContext, budget: AiBudget) -> void:
	if not collapse or ctx.tick - _last_recover < RECOVER_PERIOD or not budget.spend(6):
		return
	_last_recover = ctx.tick
	var v: AiWorldView = ctx.view
	# the Collector line comes first: every other unit line pauses, and when the bank cannot pay a Collector the running
	# lines are cancelled for their refunds (a running construction is cancelled unless it is a Refinery)
	var broke: bool = credits < collector_price + COLLAPSE_CANCEL_MARGIN
	var cs: PackedInt32Array = PackedInt32Array()
	v.construction_state(cs)
	if broke and cs[0] != 0 and ctx.res.kind_of_structure(cs[1]) != AiTypes.StructKind.REFINERY:
		if ctx.cmd.build_cancel():
			cancels += 1
			planner.on_cancelled(ctx)
	var q: PackedInt32Array = PackedInt32Array()
	for i: int in prod_eid.size():
		if prod_kind[i] == AiTypes.StructKind.REFINERY:
			continue
		if broke and v.queue_of(prod_eid[i], q) > 0:
			if ctx.cmd.train_cancel(prod_eid[i], 0):
				cancels += 1
		if not _held.has(prod_eid[i]):
			if ctx.cmd.queue_hold(prod_eid[i], true):
				_held[prod_eid[i]] = true
	if broke:
		ctx.telemetry.emit(AiTypes.Tele.STALL, AiTypes.Err.STALL_ECON, credits, ctx.tick)


func _holds(ctx: AiContext, budget: AiBudget) -> void:
	# low-funds hold (5.4.1) for the army lines; released at >= 400 credits and no collapse. Also held while a lost Collector is
	# being replaced and the bank is below its price, so the replacement is not starved by the other lines.
	var thin: bool = collectors_alive <= 1 or collectors_alive * 2 < collector_base
	var fragile: bool = need_collector and thin and credits < collector_price and opener_done()
	var starved: bool = struct_wait and struct_wait_since >= 0 and ctx.tick - struct_wait_since >= STRUCT_WAIT_HOLD
	var mcv_def: int = ctx.res.first(AiTypes.R_MCV)
	var mcv_line: bool = mcv_def >= 0 and unit_queued[mcv_def] > 0 and credits < 600  # a running expansion MCV is paid first
	# the bank: below `low` (half a Collector) the unit lines pause until `high` (a whole Collector) is reached again, so the loss
	# of every Collector can be answered from the bank plus the refunds of the cancelled lines
	var low: int = collector_price * ctx.store.tune("econ.bank_low_pct", BANK_LOW_PCT) / 100
	var high: int = collector_price * ctx.store.tune("econ.bank_high_pct", BANK_HIGH_PCT) / 100
	if not opener_done() or ctx.tick < 1500:
		_bank_hold = false
	elif credits < low:
		_bank_hold = true
	elif credits >= high:
		_bank_hold = false
	var want_hold: bool = collapse or fragile or starved or mcv_line or _bank_hold or (credits < 100 and burn_total > income_per_s and ctx.tick > 1200)
	# AIT: the line that builds the expansion MCV is never held by the bank rule (an earlier hold of it is lifted)
	if not _held.is_empty() and _bank_only(collapse, fragile, starved) and expansion.state == AiExpansion.State.TRAINING:
		for hid: int in _held.keys():
			if _queue_has_role(ctx, hid, AiTypes.R_MCV) and budget.spend(1) and ctx.cmd.queue_hold(hid, false):
				_held.erase(hid)
	if want_hold:
		if collapse:
			return  # _recover holds them
		for i: int in prod_eid.size():
			if prod_kind[i] == AiTypes.StructKind.REFINERY or prod_qlen[i] == 0 or _held.has(prod_eid[i]):
				continue
			if _bank_only(collapse, fragile, starved) and expansion.state == AiExpansion.State.TRAINING and _queue_has_role(ctx, prod_eid[i], AiTypes.R_MCV):
				continue  # an expansion MCV is an economy investment: the bank rule does not hold its line
			if budget.spend(1) and ctx.cmd.queue_hold(prod_eid[i], true):
				_held[prod_eid[i]] = true
	elif not _held.is_empty() and credits >= low:
		for id: int in _held.keys():
			if budget.spend(1) and ctx.cmd.queue_hold(id, false):
				_held.erase(id)
		# a producer that died is gone from the world: forget it
		for id2: int in _held.keys():
			if not ctx.view.alive(id2):
				_held.erase(id2)


func _bank_only(is_collapse: bool, is_fragile: bool, is_starved: bool) -> bool:
	return not is_collapse and not is_fragile and not is_starved


func _queue_has_role(ctx: AiContext, producer: int, role: int) -> bool:
	var q: PackedInt32Array = PackedInt32Array()
	ctx.view.queue_of(producer, q)
	for u: int in q:
		if ctx.res.units_of(role).has(u):
			return true
	return false


# ------------------------------------------------------------------------------------------------ defense
func _defense(ctx: AiContext) -> void:
	if not opener_done() or spent_total < 3000:
		return
	for w: AiWant in wants:
		if w.origin == AiTypes.WantOrigin.DEFENSE and w.is_open():
			return
	var kb: AiKnowledge = ctx.kb
	var phase: int = comp.phase
	var share: int = clampi(ctx.pers.defense_pct, 0, 40) * PHASE_DEF_MULT[phase] / 100 * _defense_scale(ctx) / 100
	var cur: int = spent[SC.DEFENSE] * 100 / maxi(spent_total, 1)
	if cur >= share or cur >= 40:
		return
	var last_hit: int = AiTypes.NEVER
	for p: int in kb.enemy_pids:
		last_hit = maxi(last_hit, kb.attacked_by_tick[p])
	var hot: bool = ctx.tick - last_hit < 60 * SimConfig.TPS
	var est: int = 0
	if kb.primary >= 0:
		est = kb.est_enemy_army_value(kb.primary)
	if not hot and army_value * 2 < est:
		return  # army first: no defenses while the army is under half of the enemy's known army
	var kind: int = AiTypes.StructKind.WATCHTOWER if _defense_rr % 2 == 0 else AiTypes.StructKind.AT_TURRET
	var advanced: bool = (ctx.pers.defense_pct >= 25 or (hot and defense_count >= 4)) and cur * 2 < share
	if advanced:
		kind = AiTypes.StructKind.ADV_DEFENSE
	var def: int = ctx.res.structure_of_kind(kind)
	if def < 0:
		def = ctx.res.structure_of_kind(AiTypes.StructKind.WATCHTOWER)
	if def < 0:
		return
	_defense_rr += 1
	var w2: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, def, -1, struct_own[def] + 1, P_DEFENSE_HOT if hot else P_DEFENSE, AiTypes.WantOrigin.DEFENSE)
	w2.site_kind = AiPlacer.Site.FIELD if kind == AiTypes.StructKind.WATCHTOWER else AiPlacer.Site.FRONT
	site_hint_refinery(w2, _defense_rr)
	w2.deadline = ctx.tick + 900
	add_want(w2)


## Percent of the personality's defense share that is spent on defensive structures. AIT: static defenses were the reason that two equal
## AIs never finished each other (a wave loses half its army against ten towers); the per-level row `econ.defense_scale_by_level`
## sets it, `econ.defense_scale_pct` overrides all levels (experiments).
func _defense_scale(ctx: AiContext) -> int:
	var over: int = ctx.store.tune("econ.defense_scale_pct", -1)
	if over >= 0:
		return over
	return ctx.store.tune_by_level("econ.defense_scale_by_level", ctx.cfg.level, 100)


# ------------------------------------------------------------------------------------------- allocation
func _allocate(ctx: AiContext, budget: AiBudget) -> void:
	wants.sort_custom(AiWant.before)
	var v: AiWorldView = ctx.view
	var cs: PackedInt32Array = PackedInt32Array()
	v.construction_state(cs)
	var struct_slot_free: bool = cs[0] == 0 and not planner.start_pending(ctx)
	var struct_blocker: int = 1 << 20  ## a higher-priority structure that could not be funded blocks the lower ones
	var starved: bool = _army_starved(ctx)
	var tick: int = ctx.tick
	var unfunded_need: int = 0
	var gated_burn: int = 0
	for w: AiWant in wants:
		if not budget.spend(2):
			break
		if w.state == AiTypes.WantState.DONE or w.state == AiTypes.WantState.DROPPED:
			continue
		if _satisfied(w):
			w.state = AiTypes.WantState.DONE
			continue
		if w.deadline > 0 and tick > w.deadline and w.state == AiTypes.WantState.OPEN:
			w.state = AiTypes.WantState.DROPPED
			continue
		if w.state == AiTypes.WantState.ISSUED:
			# a granted structure that vanished from the queue without appearing: back to OPEN
			if w.kind == AiTypes.WantKind.STRUCT and struct_q[w.def] == 0 and tick - w.issued_tick > 120:
				w.state = AiTypes.WantState.OPEN
				w.fail_count += 1
			elif w.kind != AiTypes.WantKind.STRUCT and tick - w.issued_tick > 300:
				w.state = AiTypes.WantState.OPEN
				w.fail_count += 1
			continue
		if tick < w.block_until:
			continue
		if w.kind == AiTypes.WantKind.STRUCT:
			if not struct_slot_free or w.prio > struct_blocker:
				continue
			var r: int = _try_struct(ctx, w, starved)
			if r == 0:
				struct_slot_free = false
			elif r >= 2:
				struct_blocker = w.prio
				if r == 2 and unfunded_need == 0:
					unfunded_need = _struct_need(ctx, w)
				elif r == 3 and gated_burn == 0:
					gated_burn = v.struct_cost(w.def) * SimConfig.TPS / maxi(v.struct_ticks(w.def), 1)
		else:
			var ur: int = _try_unit(ctx, w)
			if w.prio <= P_EXPAND and w.def >= 0:
				var lbu: int = v.unit_cost(w.def) * SimConfig.TPS / maxi(v.unit_ticks(w.def), 1)
				if ur == 2 and unfunded_need == 0:
					unfunded_need = mini(v.unit_cost(w.def), lbu * FUND_SECONDS)
				elif ur == 3 and gated_burn == 0:
					gated_burn = lbu
	struct_reserve = unfunded_need
	burn_total += gated_burn  # the cap room of a gated high-priority line is kept free from the lower lines
	if unfunded_need > 0:
		avail -= unfunded_need  # the unit lines and research of this pass must leave it alone
		if struct_wait_since < 0:
			struct_wait_since = tick
	else:
		struct_wait_since = -1
	struct_wait = unfunded_need > 0
	var keep: Array[AiWant] = []
	for w2: AiWant in wants:
		if w2.state != AiTypes.WantState.DONE and w2.state != AiTypes.WantState.DROPPED:
			keep.append(w2)
	wants = keep


## After the opening the army should get >= army_min_share_pct of the recent spend: structure wants of prio >= 26 then keep
## 800 credits of headroom for the unit lines.
func _army_starved(ctx: AiContext) -> bool:
	if not opener_done() or spent_total < 4000:
		return false
	var pct: int = ctx.store.tune("econ.army_min_share_pct", 45) * (35 if ctx.cfg.level == AiTypes.Difficulty.EASY else 45) / 45
	return spent[SC.ARMY] * 100 < pct * spent_total and credits >= 800


## Credits needed to start the line of a structure want (8 s of its burn, at most its cost).
func _struct_need(ctx: AiContext, w: AiWant) -> int:
	var v: AiWorldView = ctx.view
	var cost: int = v.struct_cost(w.def)
	return mini(cost, cost * SimConfig.TPS / maxi(v.struct_ticks(w.def), 1) * FUND_SECONDS)


## 0 issued, 1 skipped, 2 not fundable, 3 gated by the burn cap (2 and 3 block the lower priorities).
func _try_struct(ctx: AiContext, w: AiWant, starved: bool) -> int:
	var v: AiWorldView = ctx.view
	var target: int = w.def
	var miss: PackedInt32Array = ctx.tech.missing(w.def, v.struct_counts(), struct_q)
	if not miss.is_empty():
		target = miss[0]
	if def_blocked(target):
		return 1
	if target != w.def and struct_own[target] > v.struct_count(target):
		return 1  # a prerequisite is placed but not active yet: wait
	if v.power_shortage() and w.origin != AiTypes.WantOrigin.EMERGENCY and w.origin != AiTypes.WantOrigin.POWER_GRID \
			and ctx.res.kind_of_structure(target) != AiTypes.StructKind.GENERATOR:
		return 1  # a power shortage pauses every non-emergency structure
	if not _power_ok(ctx, w, target):
		return 1
	var rule: int = v.can_build(target)
	if rule == AiTypes.Rule.NO_CREDITS:
		return 2
	if rule != AiTypes.Rule.OK:
		return 1
	var cost: int = v.struct_cost(target)
	if starved and w.prio >= P_COUNTER + 1 and credits < cost + 800:
		return 1
	var fs: int = fund_status(w.prio, cost, v.struct_ticks(target))
	if fs != 0:
		return (2 if fs == 2 else 3) if w.prio <= P_TECH else 1
	if not planner.issue_struct(ctx, w, target):
		return 1
	take_fund(cost, v.struct_ticks(target))
	w.state = AiTypes.WantState.ISSUED
	w.issued_tick = ctx.tick
	return 0


## 0 queued, 1 skipped, 2 not fundable, 3 gated by the burn cap.
func _try_unit(ctx: AiContext, w: AiWant) -> int:
	var v: AiWorldView = ctx.view
	var def: int = w.def
	if def < 0:
		return 1
	if w.role == AiTypes.R_COLLECTOR and w.prio > P_EMERGENCY and collectors_queued >= (1 if credits < 2500 else 2):
		return 1  # one Collector line at a time unless the bank is full
	# AIT: the Collectors beyond the base group are bought only with a little cash in hand (a raid on all of them must stay answerable)
	if w.role == AiTypes.R_COLLECTOR and w.prio > P_EMERGENCY and collectors_alive + collectors_queued >= maxi(collector_base, 1):
		if credits < collector_price * ctx.store.tune("econ.collector_min_credits_pct", 30) / 100:
			return 1  # skipped (not "unfunded": that would hold the army lines for it)
		if not econ_safe(ctx) and credits < 3500:
			return 1  # an army that is small against what the enemy is believed to field comes before the economy grows beyond its base
	var best: int = -1
	var best_len: int = 1 << 20
	var kind: int = producer_kind_of(ctx, def)
	for i: int in prod_eid.size():
		if prod_kind[i] != kind or prod_qlen[i] >= best_len:
			continue
		if v.can_train(prod_eid[i], def) == AiTypes.Rule.OK:
			best = i
			best_len = prod_qlen[i]
	if best < 0:
		return 1
	var fs: int = fund_status(w.prio, v.unit_cost(def), v.unit_ticks(def))
	if fs != 0:
		return 2 if fs == 2 else 3
	take_fund(v.unit_cost(def), v.unit_ticks(def))
	if ctx.cmd.train(prod_eid[best], def, 1, 0 if w.prio <= P_EMERGENCY else 1):
		w.block_until = ctx.tick + ISSUE_RETRY_TICKS
		prod_qlen[best] += 1
		unit_queued[def] += 1
		if w.role == AiTypes.R_COLLECTOR:
			collectors_queued += 1
		return 0
	return 1


## AiTypes.StructKind of the structure that produces a unit def.
func producer_kind_of(ctx: AiContext, unit_def: int) -> int:
	var ud: DefUnit = ctx.view.unit_def(unit_def)
	if ud == null or ud.producer < 0:
		return -1
	return ctx.res.kind_of_structure(ud.producer)


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([wants.size(), spent_total, cancels, collector_target, collector_base, 1 if collapse else 0,
		placer.state_hash(), comp.state_hash(), squads.state_hash(), expansion.state_hash()])
	for w: AiWant in wants:
		v.append(w.id * 31 + w.state)
	return AiRng.hash_ints(v)
