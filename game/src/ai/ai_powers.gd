class_name AiPowers
extends RefCounted
## Support powers, superweapon and dispersal of one AI (ai.md 5.12 / 5.13). Scheduler slot 12 (every 10 ticks, after the ops):
## `step` first re-enforces the dispersal orders, then steps the superweapon policy (AiSuperweapon) and finally runs the decision
## loop of the three support powers of my roster:
##   for each power: READY, difficulty level, anti-spam gap, 15 % spend cap, archetype benefit (AiPowerArch) >= price x ratio x
##   eagerness (x 0.6 with idle cash), credits after the price >= the low reserve, real target vision -> USE_POWER (class 0).
## The per-power trigger parameters (all 48) are the TABLE below; radius / duration / price come from the resolved DefPower.
## AiDispersal (slot 3) is a child module registered separately (AiPowers.install).

const A := AiTypes.PowerArch
const SPEND_WINDOW: int = 5 * 60 * SimConfig.TPS
const SPEND_CAP_PCT: int = 15
const EXCESS_CASH: int = 2500
const RESERVE_LOW: int = 300
const EVAL_BACKOFF: int = 20  ## ticks before an entry whose trigger did not hold is evaluated again

## id -> {a: archetype, l: min level, g: min gap ticks, r: min benefit/price %, s: selector mask, e: effect q8, d: duration s,
## n: engaged minimum, u: fixed utility, o: option flags, em: emergency}. Levels: 1 REVEAL / REPAIR, 2 buffs / strikes / production /
## smoke / guard, 3 the situational ones (moves, decoys, marks, holds, anti-EMP, transports).
const TABLE: Dictionary = {
	"power.napc.uav_sweep": {"a": A.REVEAL, "l": 1, "g": 3000, "o": "detect"},
	"power.napc.field_repair_drop": {"a": A.REPAIR_ZONE, "l": 1, "g": 600, "s": 2, "e": 51},
	"power.napc.combined_arms_window": {"a": A.BUFF, "l": 2, "g": 900, "s": 7, "e": 26, "d": 15, "n": 8},
	"power.napc.rapid_turnaround": {"a": A.PRODUCTION, "l": 2, "g": 900, "e": 128, "d": 20, "o": "rearm"},
	"power.napc.floating_workshop": {"a": A.REPAIR_ZONE, "l": 1, "g": 600, "s": 10, "e": 77},
	"power.napc.coordinated_advance": {"a": A.BUFF_MOVE, "l": 3, "g": 1800, "r": 100, "s": 1, "u": 900, "n": 8, "o": "adv,suppress"},
	"power.nec.survey_drone": {"a": A.REVEAL, "l": 1, "g": 3000, "o": "detect"},
	"power.nec.counterbattery_mission": {"a": A.STRIKE, "l": 2, "g": 900},
	"power.nec.treaty_coordination": {"a": A.BUFF, "l": 2, "g": 900, "s": 7, "e": 12, "d": 20, "n": 6, "o": "relay"},
	"power.nec.silent_watch": {"a": A.CAMO_HOLD, "l": 3, "g": 1800, "r": 100, "u": 800},
	"power.nec.armored_overwatch": {"a": A.BUFF, "l": 2, "g": 900, "s": 16, "e": 20, "d": 15, "n": 5, "o": "stationary"},
	"power.nec.emergency_earthworks": {"a": A.GUARD_STRUCT, "l": 2, "g": 900, "e": 51, "d": 15, "em": true, "o": "explosive"},
	"power.olm.dust_screen": {"a": A.SMOKE, "l": 2, "g": 900},
	"power.olm.mobile_workshop": {"a": A.REPAIR_ZONE, "l": 1, "g": 600, "s": 2, "e": 77},
	"power.olm.open_corridor": {"a": A.BUFF_MOVE, "l": 3, "g": 1800, "r": 100, "s": 2, "u": 700, "n": 5, "o": "adv,ret"},
	"power.olm.capacitor_discharge": {"a": A.BUFF, "l": 2, "g": 1800, "r": 100, "s": 2, "e": 51, "d": 10, "n": 4, "u": 800, "o": "finisher,silence4"},
	"power.olm.false_convoy": {"a": A.DECOY, "l": 3, "g": 2400, "r": 100, "u": 600},
	"power.olm.straits_crossfire": {"a": A.BUFF, "l": 2, "g": 900, "s": 9, "e": 20, "d": 15, "n": 6},
	"power.def.mobilization_order": {"a": A.PRODUCTION, "l": 2, "g": 1800, "e": 64, "d": 20},
	"power.def.tremor_barrage": {"a": A.STRIKE, "l": 2, "g": 900},
	"power.def.redundant_orders": {"a": A.ANTI_EMP, "l": 3, "g": 600, "r": 100, "u": 900, "em": true},
	"power.def.steel_advance": {"a": A.BUFF, "l": 2, "g": 900, "s": 2, "e": 38, "d": 12, "n": 6, "o": "no_pursuit"},
	"power.def.transit_priority": {"a": A.ECON_BOOST, "l": 3, "g": 1800, "r": 100, "u": 700},
	"power.def.false_front": {"a": A.DECOY, "l": 3, "g": 4800, "r": 100, "u": 600, "o": "observed"},
	"power.pd.maritime_patrol": {"a": A.REVEAL_CORRIDOR, "l": 1, "g": 3000},
	"power.pd.expeditionary_workshop": {"a": A.REPAIR_ZONE, "l": 1, "g": 600, "s": 10, "e": 77},
	"power.pd.joint_landing": {"a": A.TRANSPORT_BUFF, "l": 3, "g": 1800, "o": "landing"},
	"power.pd.long_watch": {"a": A.REVEAL, "l": 1, "g": 3000, "o": "spot_arty"},
	"power.pd.feint_landing": {"a": A.DECOY, "l": 3, "g": 2400, "r": 100, "u": 600, "o": "landing"},
	"power.pd.precision_window": {"a": A.BUFF, "l": 2, "g": 900, "s": 12, "e": 51, "d": 10, "n": 4},
	"power.han.wideband_scan": {"a": A.REVEAL, "l": 1, "g": 1800, "o": "detect,scout_new"},
	"power.han.software_surge": {"a": A.BUFF, "l": 2, "g": 1800, "r": 100, "s": 32, "e": 85, "d": 12, "n": 6, "u": 800, "o": "finisher"},
	"power.han.reserve_bandwidth": {"a": A.FIELD_BOOST, "l": 2, "g": 1800, "e": 26, "d": 20, "o": "reach"},
	"power.han.central_priority": {"a": A.FIELD_BOOST, "l": 2, "g": 1800, "e": 26, "d": 15},
	"power.han.broken_contact": {"a": A.BUFF_MOVE, "l": 3, "g": 1800, "r": 100, "s": 3, "u": 700, "n": 4, "o": "ret"},
	"power.han.repair_swarm": {"a": A.REPAIR_ZONE, "l": 1, "g": 600, "s": 34, "e": 51, "o": "structs"},
	"power.ae.survey_network": {"a": A.REVEAL, "l": 1, "g": 3000, "o": "wrecks"},
	"power.ae.field_refurbishment": {"a": A.REPAIR_ZONE, "l": 1, "g": 600, "s": 2, "e": 77, "o": "miss30"},
	"power.ae.recovery_priority": {"a": A.ECON_BOOST, "l": 3, "g": 1800, "r": 100, "o": "salvage"},
	"power.ae.civil_defense_net": {"a": A.BUFF, "l": 2, "g": 900, "s": 1, "e": 20, "d": 15, "n": 8, "o": "suppress"},
	"power.ae.concealed_crossing": {"a": A.SMOKE, "l": 3, "g": 1800, "o": "crossing"},
	"power.ae.counterbattery_solution": {"a": A.MARK, "l": 3, "g": 1800, "o": "need2"},
	"power.sap.recon_balloon": {"a": A.REVEAL, "l": 1, "g": 2400, "o": "detect"},
	"power.sap.emergency_fortification": {"a": A.GUARD_STRUCT, "l": 2, "g": 900, "e": 64, "d": 15, "em": true, "o": "min4"},
	"power.sap.protected_advance": {"a": A.BUFF, "l": 2, "g": 900, "s": 3, "e": 38, "d": 12, "n": 6},
	"power.sap.assault_coordination": {"a": A.BUFF, "l": 2, "g": 900, "s": 16, "e": 45, "d": 12, "n": 5},
	"power.sap.mobile_reserve": {"a": A.TRANSPORT_BUFF, "l": 3, "g": 1800, "r": 100, "u": 700},
	"power.sap.counterlaunch_plot": {"a": A.MARK, "l": 3, "g": 1800, "o": "strike"},
}

var arch: AiPowerArch = AiPowerArch.new()
var sw: AiSuperweapon = AiSuperweapon.new()
var dispersal: AiDispersal = AiDispersal.new()
var entries: Array[AiPowerArch.Entry] = []
var spend_ticks: PackedInt32Array = PackedInt32Array()
var spend_costs: PackedInt32Array = PackedInt32Array()
var cast_log: Array[PackedInt32Array] = []  ## tick, power idx, x, y, benefit
var casts: int = 0
var evals: int = 0
var holds_cap: int = 0
var last_why: int = AiTypes.Why.NONE
var perf: AiPerf = AiPerf.new()  ## diagnostic wall-clock of the power slot (only when the controller samples perf)
var disp_perf: AiPerf = AiPerf.new()
var _inited: bool = false


## Registers the whole group on a controller: powers on POWERS (12), dispersal on DISPERSAL (3). Returns the AiPowers.
static func install(ctrl: AiController, owner: AiPowers) -> AiPowers:
	ctrl.register(AiScheduler.Slot.POWERS, owner)
	ctrl.register(AiScheduler.Slot.DISPERSAL, owner.dispersal)
	return owner


func setup(ctx: AiContext) -> void:
	_inited = false
	sw.setup(ctx)
	dispersal.setup(ctx)
	_build_entries(ctx)


func _build_entries(ctx: AiContext) -> void:
	entries.clear()
	if not ctx.view.bound():
		return
	_inited = true
	var r: DefRoster = ctx.view.roster()
	if r == null:
		return
	for pidx: int in r.power_list:
		var e: AiPowerArch.Entry = make_entry(ctx.view.power_def(pidx), pidx)
		if e != null:
			entries.append(e)


## The evaluation entry of a power: TABLE row + the numbers of the resolved DefPower (null when the power has no row).
static func make_entry(pd: DefPower, pidx: int) -> AiPowerArch.Entry:
	if pd == null or not TABLE.has(pd.id):
		return null
	var row: Dictionary = TABLE[pd.id]
	var e: AiPowerArch.Entry = AiPowerArch.Entry.new()
	e.id = pd.id
	e.pidx = pidx
	e.arch = int(row["a"])
	e.min_level = int(row.get("l", 2))
	e.gap = int(row.get("g", 1800))
	e.ratio = int(row.get("r", 120))
	e.sel = int(row.get("s", 0))
	e.eff = int(row.get("e", 26))
	e.engaged_min = int(row.get("n", 6))
	e.util = int(row.get("u", 0))
	e.emergency = bool(row.get("em", false))
	e.opt = String(row.get("o", "")).split(",", false)
	e.cost = pd.cost
	e.radius = maxi(pd.radius, 0)
	e.length = pd.length
	var dur: int = 0
	for a: DefPowerAction in pd.actions:
		dur = maxi(dur, a.duration_t)
		if e.radius == 0:
			e.radius = a.radius
	e.dur = int(row["d"]) * SimConfig.TPS if row.has("d") else (dur if dur > 0 else 300)
	if e.radius == 0:
		e.radius = 6 * Fp.CELL
	return e


func entry_of(power_id: String) -> AiPowerArch.Entry:
	for e: AiPowerArch.Entry in entries:
		if e.id == power_id:
			return e
	return null


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([casts, evals, holds_cap, sw.state_hash(), dispersal.state_hash(), arch.state_hash()])
	for e: AiPowerArch.Entry in entries:
		v.append(e.last_cast)
		v.append(e.casts)
	return AiRng.hash_ints(v)


# ---------------------------------------------------------------------------------------------------------- step
func step(ctx: AiContext, budget: AiBudget) -> void:
	perf.enabled = ctx.cfg.perf
	perf.begin()
	if not _inited:
		_build_entries(ctx)
	dispersal.enforce(ctx, budget)
	sw.step(ctx, budget)
	if not entries.is_empty() and budget.spend(2):
		_decide(ctx, budget)
	perf.end()


func spent_recent(tick: int) -> int:
	var s: int = 0
	for i: int in spend_ticks.size():
		if tick - spend_ticks[i] <= SPEND_WINDOW:
			s += spend_costs[i]
	return s


func _decide(ctx: AiContext, budget: AiBudget) -> void:
	var v: AiWorldView = ctx.view
	var lvl: int = ctx.diff.powers_level
	arch.trapped = dispersal.trapped
	# the 15 % cap of the 5-minute income; idle cash above the excess line counts as disposable income too
	var income5: int = ctx.kb.income_per_min * 5 + maxi(v.credits() - EXCESS_CASH, 0)
	for e: AiPowerArch.Entry in entries:
		if e.min_level > lvl or ctx.tick - e.last_cast < e.gap or ctx.tick < e.next_eval:
			continue
		if v.power_status(e.pidx) != AiTypes.PowerStatus.READY:
			continue
		if not e.emergency and spent_recent(ctx.tick) + e.cost > income5 * SPEND_CAP_PCT / 100:
			holds_cap += 1
			last_why = AiTypes.Why.POWER_GATE
			continue
		if not budget.spend(4):
			return
		evals += 1
		if not arch.evaluate(ctx, e, budget):
			last_why = AiTypes.Why.POWER_BENEFIT_LOW
			e.next_eval = ctx.tick + EVAL_BACKOFF
			continue
		var need: int = e.cost * e.ratio / 100 * ctx.diff.eager_pct / 100
		if v.credits() >= EXCESS_CASH:
			need = need * 60 / 100
		if arch.benefit < need or v.credits() - RESERVE_LOW < e.cost:
			last_why = AiTypes.Why.POWER_BENEFIT_LOW
			continue
		var recon: bool = e.arch == A.REVEAL or e.arch == A.REVEAL_CORRIDOR or e.arch == A.MARK or e.arch == A.DECOY
		if not recon and e.arch != A.PRODUCTION and e.arch != A.ANTI_EMP and not v.power_target_ok(e.pidx, arch.bx, arch.by):
			last_why = AiTypes.Why.POWER_GATE
			continue
		if e.arch == A.DECOY and not v.power_target_ok(e.pidx, arch.bx, arch.by):
			continue
		_cast(ctx, e)


func _cast(ctx: AiContext, e: AiPowerArch.Entry) -> void:
	var ok: bool
	if arch.target_eid != 0:
		ok = ctx.cmd.use_power_on(e.pidx, arch.target_eid, arch.bx, arch.by)
	else:
		ok = ctx.cmd.use_power(e.pidx, arch.bx, arch.by, arch.bangle)
	if not ok:
		return
	e.last_cast = ctx.tick
	e.casts += 1
	casts += 1
	spend_ticks.append(ctx.tick)
	spend_costs.append(e.cost)
	if spend_ticks.size() > 40:
		spend_ticks = spend_ticks.slice(20)
		spend_costs = spend_costs.slice(20)
	arch.note_cast(e, arch.bx, arch.by, ctx.tick)
	cast_log.append(PackedInt32Array([ctx.tick, e.pidx, arch.bx, arch.by, arch.benefit]))
	if cast_log.size() > 64:
		cast_log.remove_at(0)
	ctx.telemetry.emit(AiTypes.Tele.POWER_USED, e.pidx, arch.benefit, ctx.tick)
	last_why = AiTypes.Why.WANT_ISSUED
	if e.arch == A.REPAIR_ZONE and not e.has("miss30"):
		_pull_to_zone(ctx, e)


## After a repair power: idle damaged units near the zone walk into it (AiRepair's role for the powers).
func _pull_to_zone(ctx: AiContext, e: AiPowerArch.Entry) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	var t: AiEntityTable = ctx.kb.own
	for i: int in arch.un:
		if (arch.u_sel[i] & e.sel) == 0 or arch.u_miss[i] < 38:
			continue
		var r: int = arch.u_row[i]
		if t.order[r] != AiTypes.OrderKind.IDLE:
			continue
		var dx: int = arch.u_x[i] - arch.bx
		var dy: int = arch.u_y[i] - arch.by
		if dx * dx + dy * dy <= 14 * Fp.CELL * 14 * Fp.CELL and dx * dx + dy * dy > e.radius * e.radius / 2:
			ids.append(arch.u_eid[i])
	if not ids.is_empty():
		ctx.cmd.move(ids, arch.bx, arch.by, false, 2)


# ---------------------------------------------------------------------------------------------------- introspection
func summary() -> Dictionary:
	var per: Dictionary = {}
	for e: AiPowerArch.Entry in entries:
		per[e.id] = e.casts
	return {"powers_us_avg": perf.avg_us(), "powers_us_worst": perf.worst_us, "casts": casts, "evals": evals, "per_power": per, "sw_launches": sw.launches, "sw_best": sw.best_seen,
		"sw_started": sw.built_tick, "sw_active": sw.active_tick, "sw_last": sw.last_target, "dispersal_zones": dispersal.zones_seen,
		"dispersal_units": dispersal.units_ordered, "cap_holds": holds_cap}
