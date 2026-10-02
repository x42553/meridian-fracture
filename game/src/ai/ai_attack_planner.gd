class_name AiAttackPlanner
extends RefCounted
## Slot 10 (ai.md 5.8.1, every think x 4): wave planning. Decides WHEN a wave leaves (launch gate), WHAT it takes (available
## force = the combat units of the reserve minus the defense reserve), WHERE it goes (weighted enemy clusters scored by path
## length and defense penalty) and HOW (PUSH: one MAIN op; PRONG: MAIN 65 % + FLANK 35 % on a second target over a disjoint
## route). The ops themselves are AiOpAttack. Not built yet: LANDING / AIR / naval styles (they fall back to PUSH), artillery
## SIEGING, CAPTURE / SALVAGE targets.
##
## Launch gate (all): time (first_attack_min_s x jitter, later wave_interval_s x jitter since the last wave ended, one wave at
## a time), posture >= BALANCED (TURTLE only on overflow), style gates (RAID and FORTRESS wait for an overflow or a grace time),
## units(F) >= min_wave_units, no DEFEND op of priority >= 90, strength ratio >= launch ratio. The ratio requirement relaxes
## after a rest (`attack.ratio_decay_*`) so two careful AIs never wait for ever; Easy ignores it after 900 s.

const W_SUPERWEAPON: int = 70
const W_GENERATOR: int = 60
const W_REFINERY: int = 55
const W_RADAR: int = 55
const W_PRODUCTION: int = 50  ## Laboratory, Factory
const W_HQ: int = 45
const W_AIRFIELD: int = 40
const W_LOW: int = 30  ## Barracks, Dock
const W_OTHER: int = 10  ## defenses and everything else
const W_MCV: int = 60
const W_COLLECTOR: int = 45
const CLUSTER_CELLS: int = 12
const SEEDS_MAX: int = 6

var evaluations: int = 0
var launches: int = 0
var prong_tried: int = 0  ## PRONG waves considered / found no second target / found no disjoint route / launched
var prong_no_target: int = 0
var prong_no_route: int = 0
var prong_ok: int = 0
var reinforcements: int = 0  ## units sent to running waves
var why: int = AiTypes.Why.NONE  ## last reason a launch was held back (AiTypes.Why)
var last_ratio_q8: int = 0
var last_min_units: int = 0
var last_force_units: int = 0
var gate_tick: int = 0  ## tick of the first-wave time gate
var ready_first: int = -1  ## first tick the time gate and the wave size were both met
var last_target_x: int = -1
var last_target_y: int = -1
var _ready_since: int = -1
var _cx: PackedInt32Array = PackedInt32Array()  ## candidate columns
var _cy: PackedInt32Array = PackedInt32Array()
var _cw: PackedInt32Array = PackedInt32Array()
var _ce: PackedInt32Array = PackedInt32Array()  ## ghost eid, or unit eid (negative sign is not used: see _cu)
var _cu: PackedByteArray = PackedByteArray()  ## 1 = unit candidate
var _cv: PackedInt32Array = PackedInt32Array()  ## credit value


func setup(_ctx: AiContext) -> void:
	pass


func step(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null or not budget.spend(4):
		return
	var eco: AiEconomy = b.eco()
	eco.refresh(ctx, budget)
	_prune_ghosts(ctx, budget)
	evaluations += 1
	if ctx.kb.primary < 0 or b.count_ops(AiTypes.OpType.ATTACK) > 0 or b.count_ops(AiTypes.OpType.LANDING) > 0:
		return
	# ---- time gate
	var first: int = first_wave_ticks(ctx)
	gate_tick = first
	var all_in: bool = b.posture == AiTypes.Posture.ALL_IN or b.desperate
	if b.waves_launched == 0:
		if ctx.tick < first and not b.desperate:
			why = AiTypes.Why.LAUNCH_GATE_TIME
			return
	elif ctx.tick - b.last_wave_end < ctx.pers.wave_interval_ticks(ctx.diff) * _interval_pct(ctx, b) / 100 and not b.desperate:
		why = AiTypes.Why.LAUNCH_GATE_TIME
		return
	# ---- posture / style gates
	if b.posture == AiTypes.Posture.TURTLE and not b.overflow() and not b.desperate:
		why = AiTypes.Why.LAUNCH_GATE_RATIO
		return
	if not _style_ok(ctx, b, first):
		why = AiTypes.Why.LAUNCH_GATE_TIME
		return
	if b.top_priority(AiTypes.OpType.DEFEND) >= 90 and not b.desperate:
		why = AiTypes.Why.LAUNCH_GATE_RATIO
		return
	# ---- force
	var force: PackedInt32Array = PackedInt32Array()
	var counted: int = _available(ctx, b, eco, force, budget)
	last_force_units = counted
	var min_units: int = _min_wave_units(ctx, b)
	last_min_units = min_units
	if b.desperate:
		min_units = 1
	if counted < min_units or counted == 0:
		why = AiTypes.Why.NO_FUNDS  # not enough force (the code is reused: this is the "not enough units" hold)
		return
	if _ready_since < 0:
		_ready_since = ctx.tick
	if ready_first < 0:
		ready_first = ctx.tick
	# ---- target and ratio
	var fg: AiStrengthGroup = AiForce.own_group(ctx, force)
	var home_x: int = ctx.kb.sites.home_x
	var home_y: int = ctx.kb.sites.home_y
	var need: int = _need_ratio_q8(ctx, all_in, b.waves_launched == 0, b.desperate)
	var tgt: Dictionary = pick_target(ctx, budget, home_x, home_y, fg, -1, -1, 0, need)
	if tgt.is_empty():
		why = AiTypes.Why.BLACKLISTED  # no known target (the code is reused: "nothing to attack")
		return
	last_ratio_q8 = int(tgt["ratio"])
	last_target_x = int(tgt["x"])
	last_target_y = int(tgt["y"])
	if int(tgt["ratio"]) < need:
		why = AiTypes.Why.LAUNCH_GATE_RATIO
		return
	_launch(ctx, b, budget, force, fg, tgt, min_units)


## Sends up to `max_n` fresh units of the available force (reserve minus the defense reserve) to a running wave; returns how
## many joined. The units are added to the wave's first squad and attack-move to `x, y`.
func reinforce(ctx: AiContext, b: AiBrain, budget: AiBudget, op: AiOp, x: int, y: int, max_n: int) -> int:
	var sq: AiSquad = b.squads().squad(op.squads[0]) if not op.squads.is_empty() else null
	if sq == null or not budget.spend(6):
		return 0
	var force: PackedInt32Array = PackedInt32Array()
	var counted: int = _available(ctx, b, b.eco(), force, budget)
	if counted < ctx.tune("army.reinforce_min_units", 3):
		return 0
	var pick: PackedInt32Array = force.slice(0, max_n)
	var got: int = b.assign_units(ctx, sq, pick)
	if got > 0:
		ctx.cmd.attack_move(pick, x, y)
		reinforcements += got
	return got


## Tick of the first wave gate: the difficulty's first_attack_min_s with the personality / style scale and jitter
## (AiPersonality.first_attack_ticks) times `attack.first_attack_scale_pct` of the level (Medium 55 %: a 96x96 map is small, so
## the first wave of a Medium AI is due at about 5:30 to 7:00 instead of the 10:00 of the spec table).
static func first_wave_ticks(ctx: AiContext) -> int:
	return ctx.pers.first_attack_ticks(ctx.diff) * ctx.store.tune_by_level("attack.first_attack_scale_pct", ctx.cfg.level, 100) / 100


## Percent of the wave interval that must pass: 40 % while my army is at least twice the known enemy army.
func _interval_pct(ctx: AiContext, b: AiBrain) -> int:
	return 40 if b.strategy.ratio_q8 >= ctx.tune("attack.rush_ratio_x100", 200) * 256 / 100 else 100


## RAID and FORTRESS styles wait for an overflow (RAID: the harass ops go first), with a grace time so they still attack.
func _style_ok(ctx: AiContext, b: AiBrain, first: int) -> bool:
	var s: int = ctx.pers.attack_style
	var grace: int = ctx.tune("attack.style_grace_s", 240) * SimConfig.TPS
	if s == AiTypes.Style.RAID or s == AiTypes.Style.FORTRESS:
		if b.waves_launched == 0 and ctx.tick < first + grace and not b.overflow() and not b.desperate:
			return false
	return true


func _min_wave_units(ctx: AiContext, b: AiBrain) -> int:
	# grows with the game clock up to the time the first wave was due (an army that stalls must still be able to leave)
	var t_min: int = mini(ctx.tick, first_wave_ticks(ctx)) / (SimConfig.TPS * 60)
	var base: int = ctx.tune("army.min_wave_units_base", 6)
	var cap: int = ctx.tune("army.min_wave_units_cap", 24)
	var n: int = clampi(base + t_min / 8, base, cap)
	if ctx.cfg.level == AiTypes.Difficulty.EASY:
		n = n * 7 / 10
	return maxi(n + b.min_wave_extra, 3)


## Required Q8 ratio: the difficulty's launch ratio, relaxed while the AI has been ready for a while (never below 1.0).
func _need_ratio_q8(ctx: AiContext, all_in: bool, first_wave: bool, desperate: bool) -> int:
	if desperate:
		return 0
	var pct: int = ctx.diff.launch_ratio_x100
	if ctx.cfg.level == AiTypes.Difficulty.EASY and ctx.tick >= 900 * SimConfig.TPS:
		return 0
	var wait_s: int = (ctx.tick - _ready_since) / SimConfig.TPS if _ready_since >= 0 else 0
	var start: int = ctx.tune("attack.ratio_decay_start_s", 60) if first_wave else ctx.tune("attack.ratio_decay_later_start_s", 420)
	if wait_s > start:
		var steps: int = (wait_s - start) / 30
		pct = maxi(ctx.tune("attack.ratio_floor_x100", 100) - escalation_floor_drop(ctx), pct - steps * ctx.tune("attack.ratio_decay_pct_per_30s", 6))
	if all_in:
		pct = maxi(ctx.tune("attack.ratio_floor_x100", 100), pct * 70 / 100)
	return pct * 256 / 100


## Late-game escalation of the ratio floor: -3 points per minute after the 14th minute, at most -25 (never for Easy).
static func escalation_floor_drop(ctx: AiContext) -> int:
	if ctx.cfg.level == AiTypes.Difficulty.EASY or ctx.tune("aix.escalation", 0) == 0:
		return 0
	var minutes: int = ctx.tick / (SimConfig.TPS * 60)
	return clampi((minutes - ctx.tune("escalation.floor_start_min", 14)) * 3, 0, 25)


# ----------------------------------------------------------------------------------------------- force
## Fills `out` with the units of the next wave (reserve minus the defense reserve, nearest to the HQ stay); returns how many
## COUNT for the wave size (ground and support units; aircraft ride along but are not counted).
func _available(ctx: AiContext, b: AiBrain, eco: AiEconomy, out: PackedInt32Array, budget: AiBudget) -> int:
	out.resize(0)
	var t: AiEntityTable = ctx.kb.own
	var res: AiSquad = eco.squads.reserve
	if res == null:
		return 0
	budget.spend(1 + res.units.size() / 4)
	var keys: PackedInt64Array = PackedInt64Array()
	var total: int = 0
	var hx: int = ctx.kb.sites.home_x
	var hy: int = ctx.kb.sites.home_y
	for eid: int in res.units:
		var r: int = t.row(eid)
		if r < 0 or AiForce.is_sea(ctx, t.def[r]) or (t.flags[r] & AiTypes.EF_LOADED) != 0:
			continue
		var val: int = t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1)
		total += val
		var dx: int = t.x[r] - hx
		var dy: int = t.y[r] - hy
		keys.append((mini((dx * dx + dy * dy) / 1024, 0x3FFFFFFF) << 24) | (eid & 0xFFFFFF))
	keys.sort()
	var frac: int = _reserve_pct(ctx, b)
	var keep_value: int = total * frac / 100
	var kept: int = 0
	var counted: int = 0
	var support_mask: int = (1 << AiTypes.R_HEALER) | (1 << AiTypes.R_SPOTTER) | (1 << AiTypes.R_COMMAND_PROVIDER)
	for k: int in keys:
		var eid2: int = k & 0xFFFFFF
		var r2: int = t.row(eid2)
		var v2: int = t.paid[r2] * t.hp[r2] / maxi(t.hp_max[r2], 1)
		if kept < keep_value:
			kept += v2
			continue
		out.append(eid2)
		if (t.role_mask[r2] & support_mask) == 0 and not AiForce.is_air(ctx, t.def[r2]):
			counted += 1
	out.sort()
	return counted


func _reserve_pct(ctx: AiContext, b: AiBrain) -> int:
	var key: String = "turtle"
	match b.posture:
		AiTypes.Posture.BALANCED:
			key = "balanced"
		AiTypes.Posture.AGGRESSIVE:
			key = "aggressive"
		AiTypes.Posture.ALL_IN:
			key = "all_in"
	if b.desperate:
		key = "all_in"
	return ctx.tune("army.reserve_frac_pct." + key, 25)


# ---------------------------------------------------------------------------------------------- targets
func _weight_of(ctx: AiContext, kind: int, gens: int, refs: int, only_hq: bool, ahead: bool = false) -> int:
	var w: int = W_OTHER
	match kind:
		AiTypes.StructKind.SUPERWEAPON:
			w = W_SUPERWEAPON
		AiTypes.StructKind.GENERATOR:
			w = W_GENERATOR * 3 / 2 if gens <= 2 else W_GENERATOR
		AiTypes.StructKind.REFINERY:
			w = W_REFINERY
			if ctx.pers.has_flag(AiTypes.doctrine_bit("COLLECTOR_RAID")):
				w += 15
			if refs <= 1:
				w = w * 12 / 10
		AiTypes.StructKind.RADAR:
			w = W_RADAR
		AiTypes.StructKind.LAB, AiTypes.StructKind.FACTORY:
			w = W_PRODUCTION * 14 / 10 if ahead else W_PRODUCTION  # AIT: ahead, the sites that rebuild the enemy go first
		AiTypes.StructKind.HQ:
			w = W_HQ * 2 if (only_hq or ahead) else W_HQ
		AiTypes.StructKind.AIRFIELD:
			w = W_AIRFIELD
		AiTypes.StructKind.DOCK, AiTypes.StructKind.BARRACKS:
			w = W_LOW
	return w


## Fills the candidate columns with the targets of enemy player `pid` (structure ghosts, MCVs and up to 3 collectors).
func _collect(ctx: AiContext, pid: int) -> void:
	_cx.resize(0)
	_cy.resize(0)
	_cw.resize(0)
	_ce.resize(0)
	_cu.resize(0)
	_cv.resize(0)
	var g: AiGhostTable = ctx.kb.ghosts
	var gens: int = 0
	var refs: int = 0
	var hqs: int = 0
	var bz: AiBrain = ctx.brain as AiBrain
	var ahead: bool = bz != null and bz.strategy.ratio_q8 >= ctx.tune("attack.ahead_ratio_x100", 160) * 256 / 100
	for i: int in g.count:
		if g.owner[i] != pid:
			continue
		if g.kind[i] == AiTypes.StructKind.GENERATOR:
			gens += 1
		elif g.kind[i] == AiTypes.StructKind.REFINERY:
			refs += 1
		elif g.kind[i] == AiTypes.StructKind.HQ:
			hqs += 1
	for i2: int in g.count:
		if g.owner[i2] != pid:
			continue
		_cx.append(g.x[i2])
		_cy.append(g.y[i2])
		_cw.append(_weight_of(ctx, g.kind[i2], gens, refs, hqs <= 1, ahead))
		_ce.append(g.eid[i2])
		_cu.append(0)
		_cv.append(g.value[i2])
	var t: AiEntityTable = ctx.kb.enemy_units
	var cols: int = 0
	for j: int in t.count:
		if t.owner[j] != pid or ctx.tick - t.last_seen[j] > 600:
			continue
		var m: int = t.role_mask[j]
		var w: int = 0
		if (m & (1 << AiTypes.R_MCV)) != 0:
			w = W_MCV
		elif (m & (1 << AiTypes.R_COLLECTOR)) != 0 and cols < 3:
			w = W_COLLECTOR
			cols += 1
		if w > 0:
			_cx.append(t.x[j])
			_cy.append(t.y[j])
			_cw.append(w)
			_ce.append(t.eid[j])
			_cu.append(1)
			_cv.append(t.paid[j])


## Best target for a force `fg` standing at (fx, fy): {x, y, eid, is_unit, score, ratio, weight, value, dist_c}. A candidate
## within `sep` of (avoid_x, avoid_y) is skipped (the second prong). Empty dictionary when there is nothing to attack.
func pick_target(ctx: AiContext, budget: AiBudget, fx: int, fy: int, fg: AiStrengthGroup, avoid_x: int, avoid_y: int, sep: int, min_ratio_q8: int = 0) -> Dictionary:
	var kb: AiKnowledge = ctx.kb
	var pid: int = kb.primary
	if pid < 0:
		return {}
	_collect(ctx, pid)
	var n: int = _cx.size()
	if n == 0:
		return {}
	budget.spend(2 + n)
	var cr2: int = CLUSTER_CELLS * Fp.CELL * CLUSTER_CELLS * Fp.CELL
	var taken: PackedInt32Array = PackedInt32Array()  # seeds already scored
	var best: Dictionary = {}
	var best_score: int = -1
	var soft: Dictionary = {}  ## the cluster with the best ratio, used when no cluster reaches `min_ratio_q8`
	for _round: int in mini(SEEDS_MAX, n):
		var seed_i: int = -1
		for i: int in n:
			if taken.has(i):
				continue
			if sep > 0 and avoid_x >= 0 and (_cx[i] - avoid_x) * (_cx[i] - avoid_x) + (_cy[i] - avoid_y) * (_cy[i] - avoid_y) < sep * sep:
				continue
			if seed_i < 0 or _cw[i] > _cw[seed_i] or (_cw[i] == _cw[seed_i] and _ce[i] < _ce[seed_i]):
				seed_i = i
		if seed_i < 0:
			break
		# everything of the cluster around the seed is consumed by this round
		var cw: int = 0
		var cval: int = 0
		for j: int in n:
			var dx: int = _cx[j] - _cx[seed_i]
			var dy: int = _cy[j] - _cy[seed_i]
			if dx * dx + dy * dy <= cr2:
				cw += _cw[j]
				cval += _cv[j]
				taken.append(j)
		# AIT: the first cluster is always scored (a 100-unit army leaves the slot budget empty before the target search: the planner then
		# found "no target" for ever); further clusters only while the budget lasts
		if _round == 0:
			budget.spend(6)
		elif not budget.spend(6):
			break
		var dg: AiStrengthGroup = defenders(ctx, _cx[seed_i], _cy[seed_i], pid)
		_siege_discount(ctx, fg, dg, _cx[seed_i], _cy[seed_i])
		var r_q8: int = AiForce.ratio(ctx, fg, dg, _ce[seed_i] & 0xFFFF)
		var pen: int = mini(768, 65536 / maxi(r_q8, 1))
		var path_c: int = AiForce.cells(fx, fy, _cx[seed_i], _cy[seed_i])
		var score: int = cw * 65536 / ((256 + path_c) * (256 + pen))
		var cand: Dictionary = {"x": _cx[seed_i], "y": _cy[seed_i], "eid": _ce[seed_i], "is_unit": _cu[seed_i] != 0, "score": score,
			"ratio": r_q8, "weight": cw, "value": cval, "dist_c": path_c}
		if r_q8 >= min_ratio_q8 and score > best_score:
			best_score = score
			best = cand
		if soft.is_empty() or r_q8 > int(soft["ratio"]):
			soft = cand
	# a cluster the force can beat wins over a juicier one it cannot; if none is beatable the weakest one is reported (the
	# caller's ratio gate then holds the wave back)
	return best if not best.is_empty() else soft


## Artillery in the wave shells the defensive structures of the target before the assault (AiSiege): when at least 10 % of the
## wave's damage is artillery, half of what the structures add to the defenders is taken off (tuning `siege.defense_discount_pct`).
func _siege_discount(ctx: AiContext, fg: AiStrengthGroup, dg: AiStrengthGroup, x: int, y: int) -> void:
	var total: int = fg.total_dps_x100()
	if total <= 0 or fg.arty_dps_x100 * 100 < 10 * total:
		return
	var st: AiStrengthGroup = AiForce.static_defense_group(ctx, x, y, ctx.tune("threat.defense_radius_c", 16) * Fp.CELL)
	if st.count > 0:
		dg.discount(st, ctx.tune("siege.defense_discount_pct", 50))


## Credits of army an enemy is assumed to own at this time: (a0 + a1 x minutes) x attack.assumed_scale_pct.
static func assumed_army(ctx: AiContext) -> int:
	var minutes: int = ctx.tick / (SimConfig.TPS * 60)
	var a: int = ctx.tune("strength.assumed_base_a0", 1500) + ctx.tune("strength.assumed_base_a1_per_min", 900) * minutes
	return a * ctx.tune("attack.assumed_scale_pct", 45) / 100


## Defender group of a target: the seen armed units + defensive structure ghosts near it, plus an assumed reserve for the
## army that is not in sight: the enemy is believed to own `assumed(t) x attack.assumed_scale_pct` credits of army
## (a0 + a1 x minutes, ai.md 5.3.4) minus what is currently seen of it anywhere (`unseen_reserve_pct` of the structure-defense
## value is added when the target information is stale).
func defenders(ctx: AiContext, x: int, y: int, pid: int) -> AiStrengthGroup:
	var r: int = ctx.tune("threat.defense_radius_c", 16) * Fp.CELL
	var dg: AiStrengthGroup = AiForce.enemy_group(ctx, x, y, r, 200)
	# AIT: units of the enemy within `attack.remote_radius_c` cells but outside the defense radius come to its help (remote_pct of their strength)
	AiForce.add_ring(ctx, dg, x, y, r, ctx.tune("attack.remote_radius_c", 45) * Fp.CELL, 200, ctx.tune("attack.remote_pct", 60))
	# information age of the target area: the newest sighting of one of its structures
	var newest: int = AiTypes.NEVER
	var g: AiGhostTable = ctx.kb.ghosts
	var r2: int = r * r
	for i: int in g.count:
		if g.owner[i] == pid and g.eid[i] > 0:
			var dx: int = g.x[i] - x
			var dy: int = g.y[i] - y
			if dx * dx + dy * dy <= r2:
				newest = maxi(newest, g.last_seen[i])
	var stale_ticks: int = maxi(ctx.tune("strength.target_stale_ticks", 1200), 1)
	# a base that is in sight right now hides little army (25 % of the assumption stays); the doubt grows back with the age
	var unseen_pct: int = clampi((ctx.tick - newest) * 100 / stale_ticks, 25, 100) if newest > AiTypes.NEVER else 100
	var assumed: int = assumed_army(ctx) * unseen_pct / 100
	var b: AiBrain = ctx.brain as AiBrain
	var reserve: int = assumed - ctx.kb.est_enemy_army_value(pid)
	if b != null and not ctx.diff.info_omniscient:
		# the army that was in sight a moment ago but is not now (fog) still exists: remote_pct of the decayed peak, minus what is counted
		reserve = maxi(reserve, b.strategy.enemy_peak * ctx.tune("attack.remote_pct", 60) / 100 - dg.value)
	AiForce.add_reserve(ctx, dg, pid, reserve)
	# what killed my earlier waves out of sight (artillery, defense clusters) still defends this area
	if b != null:
		AiForce.add_power(ctx, dg, pid, b.danger_power(x, y, r + 8 * Fp.CELL, ctx.tick))
	if unseen_pct >= 100 and dg.value > 0:
		AiForce.add_reserve(ctx, dg, pid, dg.value * ctx.tune("strength.unseen_reserve_pct", 35) / 100)
	return dg


## Removes presumed HQ ghosts whose cell is in sight (nothing there) and the ghosts of defeated players.
func _prune_ghosts(ctx: AiContext, budget: AiBudget) -> void:
	var g: AiGhostTable = ctx.kb.ghosts
	var v: AiWorldView = ctx.view
	budget.spend(1 + g.count / 8)
	var i: int = g.count - 1
	while i >= 0:
		var drop: bool = false
		if g.owner[i] >= 0 and not v.player_alive(g.owner[i]):
			drop = true
		elif g.eid[i] < 0 and v.cell_visible(g.x[i] >> Fp.CELL_SHIFT, g.y[i] >> Fp.CELL_SHIFT):
			drop = true
		if drop:
			g.remove(g.eid[i])
		i -= 1
		if i >= g.count:
			i = g.count - 1


# ---------------------------------------------------------------------------------------------- launch
func _launch(ctx: AiContext, b: AiBrain, budget: AiBudget, force: PackedInt32Array, fg: AiStrengthGroup, tgt: Dictionary, min_units: int) -> void:
	# the target is over the water (or the water route is much shorter for a TRANSPORT_ASSAULT roster): a landing op
	var lr: int = AiOpLanding.consider(ctx, b, budget, force, tgt, int(tgt["ratio"]))
	if lr == 2:
		why = AiTypes.Why.NO_FUNDS
		return
	if lr == 1:
		b.waves_launched += 1
		launches += 1
		if b.first_wave_tick < 0:
			b.first_wave_tick = ctx.tick
		_ready_since = -1
		why = AiTypes.Why.WANT_ISSUED
		ctx.telemetry.emit(AiTypes.Tele.ATTACK_LAUNCHED, force.size(), int(tgt["ratio"]), ctx.tick)
		return
	var main_ids: PackedInt32Array = force
	var flank_ids: PackedInt32Array = PackedInt32Array()
	var flank_tgt: Dictionary = {}
	var main_route: PackedInt32Array = PackedInt32Array()
	var flank_route: PackedInt32Array = PackedInt32Array()
	var hx: int = ctx.kb.sites.home_x
	var hy: int = ctx.kb.sites.home_y
	# PRONG: a second target on a disjoint route
	# AIT: Hard and Brutal also split a wave that is far ahead (ratio at least `attack.prong_ratio_x100`) and twice the minimum size
	var prong: bool = ctx.pers.attack_style == AiTypes.Style.PRONG and ctx.diff.prongs_max >= 2 and force.size() * 10 >= min_units * 16
	if not prong and ctx.diff.prongs_max >= 3 and force.size() >= min_units * 2 and int(tgt["ratio"]) >= ctx.tune("attack.prong_ratio_x100", 200) * 256 / 100:
		prong = true
	if prong:
		prong_tried += 1
		flank_tgt = pick_target(ctx, budget, hx, hy, fg, int(tgt["x"]), int(tgt["y"]), 10 * Fp.CELL, 256)
		if flank_tgt.is_empty():
			prong_no_target += 1
		else:
			ctx.kb.route.route(hx, hy, int(tgt["x"]), int(tgt["y"]), AiTypes.MoveClass.TRACKED, ctx.kb.route.threat_weight_q8, main_route)
			var fr: int = ctx.kb.route.disjoint_route(hx, hy, int(flank_tgt["x"]), int(flank_tgt["y"]), AiTypes.MoveClass.TRACKED, main_route, flank_route)
			if fr == 0 or main_route.is_empty():
				flank_tgt = {}
				prong_no_route += 1
	if not flank_tgt.is_empty():
		main_ids = PackedInt32Array()
		var t: AiEntityTable = ctx.kb.own
		var sent: int = 0
		var flank_val: int = 0
		for eid2: int in force:
			var r2: int = t.row(eid2)
			var v2: int = t.paid[r2]
			sent += v2
			if flank_val * 100 < 35 * sent:
				flank_ids.append(eid2)
				flank_val += v2
			else:
				main_ids.append(eid2)
		if main_ids.is_empty() or flank_ids.is_empty():
			main_ids = force
			flank_ids = PackedInt32Array()
			flank_tgt = {}
		else:
			prong_ok += 1
	var main_op: AiOpAttack = AiOpAttack.new()
	main_op.setup_wave(AiTypes.SquadKind.MAIN, main_ids, tgt, int(tgt["ratio"]))
	if not b.add_op(ctx, main_op):
		return
	if not flank_tgt.is_empty():
		var fop: AiOpAttack = AiOpAttack.new()
		fop.setup_wave(AiTypes.SquadKind.FLANK, flank_ids, flank_tgt, int(flank_tgt["ratio"]))
		fop.avoid_route = main_route
		fop.sibling = main_op.id
		if b.add_op(ctx, fop):
			main_op.sibling = fop.id
	b.waves_launched += 1
	launches += 1
	if b.first_wave_tick < 0:
		b.first_wave_tick = ctx.tick
	_ready_since = -1
	why = AiTypes.Why.WANT_ISSUED
	ctx.telemetry.emit(AiTypes.Tele.ATTACK_LAUNCHED, force.size(), int(tgt["ratio"]), ctx.tick)


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([evaluations, launches, why, last_ratio_q8, _ready_since, last_force_units, prong_ok, reinforcements]))
