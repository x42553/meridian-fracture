class_name AiOpAttack
extends AiOp
## Wave attack FSM (ai.md 5.8.2, lean): FORMING (gather at the staging point) -> ADVANCING (threat-aware route, regroup at each
## waypoint) -> ENGAGING (attack-move at the enemy / attack the target structures, local strength check every 20 ticks) ->
## CLEANUP (next target cluster) -> RETREATING (abort: ratio below the abort ratio or value below 40 %, or a recall) -> DONE.
## Aircraft of the wave stay home until the ground force is in contact. SIEGING (AiSiege): when the target is covered by defensive
## structures and the wave has artillery that outranges them, the wave stops out of reach and the artillery bombards the
## structures before the assault.

const CLUSTER_R: int = 12 * Fp.CELL

var kind: int = AiTypes.SquadKind.MAIN
var unit_ids: PackedInt32Array = PackedInt32Array()  ## the units of the wave (claimed at start)
var ratio_at_launch: int = 0
var target_value: int = 0  ## value of the target cluster at launch
var initial_value: int = 0
var waypoints: PackedInt32Array = PackedInt32Array()
var wp_i: int = 0
var avoid_route: PackedInt32Array = PackedInt32Array()  ## FLANK: the main route it must not share
var sibling: int = -1  ## the other prong's op id
var depart_tick: int = 0
var eta_ticks: int = 0
var adv_tick: int = -1
var stage_x: int = 0
var stage_y: int = 0
var retreat_x: int = 0
var retreat_y: int = 0
var orig_tx: int = 0
var orig_ty: int = 0
var r_now_q8: int = 0
var targets_done: int = 0
var contact_reported: bool = false
var recalled: bool = false
var _arrive_tick: int = -1
var _last_order_tick: int = AiTypes.NEVER
var _last_ox: int = -1
var _last_oy: int = -1
var _last_mode: int = -1
var _last_ratio_tick: int = AiTypes.NEVER
var _last_reinforce: int = AiTypes.NEVER
var _samples: PackedInt32Array = PackedInt32Array()  ## (tick, value) pairs of the last 300 ticks, for the attrition check
var _gv: PackedInt32Array = PackedInt32Array()  ## enemy structure value in reach of the wave, one entry per sample
var hidden_fire: bool = false
var initial_power: int = 0
var start_state: int = AiTypes.OpState.FORMING  ## ADVANCING for a landed force (no staging)
var siege: AiSiege = AiSiege.new()
var retreat_reason: String = "other"  ## why the wave turned back (statistics: attrition / ratio / value / recall)
var salvage_hold: int = 0  ## ticks CLEANUP held the battlefield for salvage (AE)


func setup_wave(p_kind: int, unit_list: PackedInt32Array, tgt: Dictionary, p_ratio: int) -> void:
	type = AiTypes.OpType.ATTACK
	kind = p_kind
	unit_ids = unit_list.duplicate()
	tx = int(tgt["x"])
	ty = int(tgt["y"])
	orig_tx = tx
	orig_ty = ty
	target_ghost = int(tgt["eid"])
	target_value = int(tgt.get("value", 0))
	ratio_at_launch = p_ratio
	priority = 60 if p_kind == AiTypes.SquadKind.MAIN else 55


func start(ctx: AiContext) -> bool:
	var b: AiBrain = ctx.brain as AiBrain
	var sm: AiSquadManager = b.squads()
	var sq: AiSquad = sm.create(kind, id)
	sq.prio = priority
	squads.append(sq.id)
	if b.assign_units(ctx, sq, unit_ids) == 0:
		return false
	var t: AiEntityTable = ctx.kb.own
	for eid: int in sq.units:
		var r: int = t.row(eid)
		committed_value += t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1)
	initial_value = committed_value
	initial_power = AiForce.power_of(ctx, sq.units)
	period = maxi(10, ctx.diff.think_period_ticks)
	stage_x = b.eco().production.stage_x
	stage_y = b.eco().production.stage_y
	retreat_x = stage_x
	retreat_y = stage_y
	timeout_tick = ctx.tick + ctx.tune("army.op_timeout_ticks", 12000)
	set_state(ctx, start_state)
	if start_state == AiTypes.OpState.ADVANCING:
		measure(ctx, AiBudget.new())
		adv_tick = ctx.tick
		depart_tick = ctx.tick
	return true


func update(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	measure(ctx, budget)
	if alive == 0:
		_finish(ctx, b)
		return
	if state != AiTypes.OpState.RETREATING and state != AiTypes.OpState.DONE and value_now * 100 < ctx.tune("army.abort_value_pct", 40) * initial_value:
		retreat_reason = "value"
		_retreat(ctx, b, true)
		return
	if (state == AiTypes.OpState.ADVANCING or state == AiTypes.OpState.ENGAGING or state == AiTypes.OpState.SIEGING) and _attrition(ctx, b):
		return
	match state:
		AiTypes.OpState.FORMING:
			_forming(ctx, b, budget)
		AiTypes.OpState.ADVANCING:
			_advancing(ctx, b, budget)
		AiTypes.OpState.ENGAGING:
			_engaging(ctx, b, budget)
		AiTypes.OpState.SIEGING:
			_sieging(ctx, b, budget)
		AiTypes.OpState.CLEANUP:
			_cleanup(ctx, b, budget)
		AiTypes.OpState.RETREATING:
			_retreating(ctx, b)


func abort(ctx: AiContext, reason: int) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b != null and state != AiTypes.OpState.DONE:
		measure(ctx, AiBudget.new())
		_report(ctx, b)
	super.abort(ctx, reason)


func nudge() -> void:
	_last_order_tick = AiTypes.NEVER


func note_detached(value: int) -> void:
	initial_value = maxi(initial_value - value, 1)
	var i: int = 1
	while i < _samples.size():
		_samples[i] = maxi(_samples[i] - value, 0)
		i += 2


## `_local_check` for the siege state machine: true = the wave was ordered to retreat.
func local_check_now(ctx: AiContext, b: AiBrain) -> bool:
	return _local_check(ctx, b)


## The base is in danger: go home to `x, y` and disband there.
func recall(ctx: AiContext, x: int, y: int) -> void:
	if state == AiTypes.OpState.RETREATING or is_over():
		return
	retreat_x = x
	retreat_y = y
	recalled = true
	retreat_reason = "recall"
	_retreat(ctx, ctx.brain as AiBrain, false)


# ------------------------------------------------------------------------------------------------ states
func _forming(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	var near: int = count_within(ctx, ground, stage_x, stage_y, 6 * Fp.CELL)
	var cnt: int = count_within(ctx, ground, cx, cy, 6 * Fp.CELL)
	var elapsed: int = ctx.tick - state_since
	var gathered: bool = near * 100 >= 80 * ground.size() or (cnt * 100 >= 80 * ground.size() and elapsed >= 40)
	if gathered or elapsed >= ctx.tune("army.stage_timeout_ticks", 900):
		_plan(ctx, b, budget)
		set_state(ctx, AiTypes.OpState.ADVANCING)
		adv_tick = ctx.tick
		return
	_order(ctx, ground, stage_x, stage_y, AiTypes.Intent.MOVE, 100)


## Route class of the wave: the slowest member decides. TRACKED normally; AMPHIBIOUS when there is no land route to the target and
## every ground unit is amphibious (or the water route is clearly shorter for an AMPHIBIOUS_ROUTES roster whose units all swim).
func route_class(ctx: AiContext) -> int:
	var route: AiRouteGraph = ctx.kb.route
	var all_amph: bool = not ground.is_empty()
	var t: AiEntityTable = ctx.kb.own
	for eid: int in ground:
		var r: int = t.row(eid)
		var p: AiUnitProfile = ctx.unit_profile(t.def[r]) if r >= 0 else null
		if p == null or (p.move_class != AiTypes.MoveClass.AMPHIBIOUS and (p.tag_mask & DefEnums.UT_AMPHIBIOUS) == 0):
			all_amph = false
			break
	if not all_amph:
		return AiTypes.MoveClass.TRACKED
	if not route.connected(cx, cy, tx, ty, AiTypes.MoveClass.TRACKED):
		return AiTypes.MoveClass.AMPHIBIOUS
	if ctx.pers.has_flag(AiTypes.doctrine_bit("AMPHIBIOUS_ROUTES")):
		var land: PackedInt32Array = PackedInt32Array()
		var wet: PackedInt32Array = PackedInt32Array()
		var nl: int = route.route(cx, cy, tx, ty, AiTypes.MoveClass.TRACKED, route.threat_weight_q8, land)
		var nw: int = route.route(cx, cy, tx, ty, AiTypes.MoveClass.AMPHIBIOUS, route.threat_weight_q8, wet)
		if nl > 0 and nw > 0 and route.route_cells(wet) * 100 < route.route_cells(land) * 75:
			return AiTypes.MoveClass.AMPHIBIOUS
	return AiTypes.MoveClass.TRACKED


func _plan(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	waypoints.resize(0)
	wp_i = 0
	var route: AiRouteGraph = ctx.kb.route
	var pts: PackedInt32Array = PackedInt32Array()
	var n: int = 0
	var mc: int = route_class(ctx)
	if kind == AiTypes.SquadKind.FLANK and not avoid_route.is_empty():
		n = route.disjoint_route(cx, cy, tx, ty, mc, avoid_route, pts)
	if n == 0:
		n = route.route(cx, cy, tx, ty, mc, route.threat_weight_q8, pts)
	budget.spend(20 + n * 2)
	var min_gap: int = ctx.tune("army.waypoint_spacing_c", 12) * Fp.CELL
	var lx: int = cx
	var ly: int = cy
	for i: int in n:
		var px: int = pts[2 * i]
		var py: int = pts[2 * i + 1]
		if i < n - 1 and AiForce.dist(px, py, lx, ly) < min_gap:
			continue
		waypoints.append(px)
		waypoints.append(py)
		lx = px
		ly = py
	if waypoints.is_empty():
		waypoints.append(tx)
		waypoints.append(ty)
	# ETA (ticks) from the route length and the slowest unit
	var speed: int = maxi(_speed_min(ctx), 1)
	var len_u: int = 0
	var px2: int = cx
	var py2: int = cy
	for j: int in waypoints.size() / 2:
		len_u += AiForce.dist(waypoints[2 * j], waypoints[2 * j + 1], px2, py2)
		px2 = waypoints[2 * j]
		py2 = waypoints[2 * j + 1]
	eta_ticks = len_u / speed
	if kind == AiTypes.SquadKind.FLANK:
		var main: AiOp = b.op_by_id(sibling)
		if main is AiOpAttack and not main.is_over() and (main as AiOpAttack).eta_ticks > 0:
			depart_tick = ctx.tick + maxi(0, (main as AiOpAttack).eta_ticks - 10 * SimConfig.TPS - eta_ticks)
		else:
			depart_tick = ctx.tick
	else:
		depart_tick = ctx.tick


func _speed_min(ctx: AiContext) -> int:
	var t: AiEntityTable = ctx.kb.own
	var s: int = 1 << 30
	for eid: int in ground:
		var r: int = t.row(eid)
		var p: AiUnitProfile = ctx.unit_profile(t.def[r])
		if p != null and p.speed > 0:
			s = mini(s, p.speed)
	return 0 if s == (1 << 30) else s


func _advancing(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	if ctx.tick < depart_tick:
		return
	if _local_check(ctx, b):
		return
	if AiForce.dist(cx, cy, tx, ty) < ctx.tune("siege.trigger_c", 32) * Fp.CELL and _begin_siege(ctx, b, budget):
		return
	if _contact(ctx, 14 * Fp.CELL):
		_engage(ctx)
		return
	if AiForce.dist(cx, cy, tx, ty) < 10 * Fp.CELL:
		_engage(ctx)
		return
	if wp_i >= waypoints.size() / 2:
		_engage(ctx)
		return
	var wx: int = waypoints[2 * wp_i]
	var wy: int = waypoints[2 * wp_i + 1]
	var lead: int = nearest_unit(ctx, ground, wx, wy)
	var row: int = ctx.kb.own.row(lead)
	if row >= 0:
		var lx: int = ctx.kb.own.x[row]
		var ly: int = ctx.kb.own.y[row]
		if AiForce.dist(lx, ly, wx, wy) <= 6 * Fp.CELL:
			if _arrive_tick < 0:
				_arrive_tick = ctx.tick
			var near: int = count_within(ctx, ground, lx, ly, 8 * Fp.CELL)
			if near * 100 >= ctx.tune("army.regroup_pct", 70) * ground.size() \
					or ctx.tick - _arrive_tick >= ctx.tune("army.regroup_timeout_ticks", 200):
				wp_i += 1
				_arrive_tick = -1
				_last_order_tick = AiTypes.NEVER
				if wp_i >= waypoints.size() / 2:
					_engage(ctx)
					return
				wx = waypoints[2 * wp_i]
				wy = waypoints[2 * wp_i + 1]
	_order(ctx, ground, wx, wy, AiTypes.Intent.ATTACK_MOVE, 80)
	budget.spend(2)


func _engage(ctx: AiContext) -> void:
	var bg: AiBudget = AiBudget.new()
	bg.reset(64, 64)
	if _begin_siege(ctx, brain(ctx), bg):
		return
	set_state(ctx, AiTypes.OpState.ENGAGING)
	_last_order_tick = AiTypes.NEVER
	if not contact_reported:
		contact_reported = true
		ctx.telemetry.emit(AiTypes.Tele.ATTACK_CONTACT, cx >> Fp.CELL_SHIFT, cy >> Fp.CELL_SHIFT, ctx.tick)


func _begin_siege(ctx: AiContext, b: AiBrain, budget: AiBudget) -> bool:
	if b == null or state == AiTypes.OpState.SIEGING or not siege.consider(ctx, b, self, budget):
		return false
	set_state(ctx, AiTypes.OpState.SIEGING)
	_last_order_tick = AiTypes.NEVER
	return true


func _sieging(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	var r: int = siege.update(ctx, b, self, budget)
	if r == 1:
		set_state(ctx, AiTypes.OpState.ENGAGING)
		_last_order_tick = AiTypes.NEVER
	elif r == 2:
		pass  # the local check already ordered the retreat


## Attrition check: a quarter of the wave's starting value lost within 300 ticks while the visible enemy is no match for the
## wave means unseen fire (artillery, defenses out of sight): remember the danger where it happened and pull back.
func _attrition(ctx: AiContext, b: AiBrain) -> bool:
	_samples.append(ctx.tick)
	_samples.append(value_now)
	_gv.append(_near_ghost_value(ctx))
	while _samples.size() > 4 and ctx.tick - _samples[0] > 300:
		_samples = _samples.slice(2)
		_gv = _gv.slice(1)
	var v0: int = _samples[1]
	var lost: int = v0 - value_now
	var thr: int = ctx.tune("army.attrition_pct", 25)
	# AIT: a wave that outweighs everything known around it (units in sight, defensive structures, remembered dangers) only turns
	# back when it is really bleeding: the losses of an assault on a defended base are the price of the base
	if r_now_q8 >= ctx.tune("army.attrition_surplus_x100", 300) * 256 / 100 and _hold_ok(ctx):
		thr = ctx.tune("army.attrition_surplus_pct", 45)
	if lost * 100 < thr * initial_value:
		return false
	# AIT: a wave that tears down the defenses as fast as it bleeds presses on (the exchange of the window is what counts)
	var gv_peak: int = 0
	for gv: int in _gv:
		gv_peak = maxi(gv_peak, gv)
	var progress: int = gv_peak - _gv[_gv.size() - 1]  # the structures in reach grow while they are discovered, then shrink as they fall
	if ctx.tune("aix.progress", 1) != 0 and progress * 100 >= ctx.tune("army.progress_pct", 60) * lost and value_now * 100 >= ctx.tune("army.progress_floor_pct", 55) * initial_value:
		b.bump("attr_progress")
		return false
	var theirs: AiStrengthGroup = AiForce.enemy_group(ctx, cx, cy, 16 * Fp.CELL, 100)
	var mine: AiStrengthGroup = AiForce.own_group(ctx, ids)
	if theirs.hp > 0 and AiForce.ratio(ctx, mine, theirs, id) < 3 * 256:
		return false  # the losses are explained by what is in sight: the normal ratio check decides
	hidden_fire = true
	_classify_hidden_fire(ctx, b)
	var power: int = initial_power * mini(lost * 100 / maxi(initial_value, 1), 100) / 100
	b.note_danger(cx, cy, power, ctx.tick)
	retreat_reason = "attrition"
	_retreat(ctx, b, true)
	return true


## The wave has been in the target area for a while (its ratio is a measured one, not the stale value of the approach).
func _hold_ok(ctx: AiContext) -> bool:
	return state == AiTypes.OpState.ENGAGING and ctx.tick - _last_ratio_tick <= 60


## Credits of enemy structures (ghosts of the primary enemy) within 22 cells of the wave.
func _near_ghost_value(ctx: AiContext) -> int:
	var g: AiGhostTable = ctx.kb.ghosts
	var r2: int = 22 * Fp.CELL * 22 * Fp.CELL
	var s: int = 0
	for i: int in g.count:
		if g.owner[i] < 0:
			continue
		var dx: int = g.x[i] - cx
		var dy: int = g.y[i] - cy
		if dx * dx + dy * dy <= r2:
			s += g.value[i]
	return s


## Statistics only: what probably killed the wave out of sight (enemy artillery / aircraft seen near, defensive structure ghosts near).
func _classify_hidden_fire(ctx: AiContext, b: AiBrain) -> void:
	var et: AiEntityTable = ctx.kb.enemy_units
	var arty: bool = false
	var air: bool = false
	for i: int in et.count:
		if ctx.tick - et.last_seen[i] > 400 or AiForce.dist(et.x[i], et.y[i], cx, cy) > 30 * Fp.CELL:
			continue
		var p: AiUnitProfile = ctx.unit_profile_of(et.owner[i], et.def[i])
		if p == null:
			continue
		if p.category == AiTypes.Cat.ARTILLERY:
			arty = true
		elif p.category == AiTypes.Cat.AIR and p.is_combat():
			air = true
	var g: AiGhostTable = ctx.kb.ghosts
	var defs: bool = false
	for j: int in g.count:
		if g.owner[j] >= 0 and AiForce.is_defense_kind(g.kind[j]) and AiForce.dist(g.x[j], g.y[j], cx, cy) <= 22 * Fp.CELL:
			defs = true
			break
	b.bump("attr_arty" if arty else ("attr_defense" if defs else ("attr_air" if air else "attr_unknown")))


## Local strength check every 20 ticks: enemy units in sight AND the defensive structures that cover the wave. True = the wave
## was ordered to retreat.
func _local_check(ctx: AiContext, b: AiBrain) -> bool:
	if ctx.tick - _last_ratio_tick < 20:
		return false
	_last_ratio_tick = ctx.tick
	var theirs: AiStrengthGroup = AiForce.enemy_group(ctx, cx, cy, 16 * Fp.CELL, 100)
	if theirs.hp <= 0:
		return false
	var mine: AiStrengthGroup = AiForce.own_group(ctx, ids)
	r_now_q8 = AiForce.ratio(ctx, mine, theirs, id)
	if r_now_q8 < ctx.tune("strength.abort_ratio_x100", 70) * 256 / 100:
		retreat_reason = "ratio"
		_retreat(ctx, b, true)
		return true
	return false


func _contact(ctx: AiContext, r: int) -> bool:
	var rows: PackedInt32Array = PackedInt32Array()
	return AiForce.armed_enemy_rows(ctx, cx, cy, r, 100, rows) > 0


func _engaging(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	var rows: PackedInt32Array = PackedInt32Array()
	var n: int = AiForce.armed_enemy_rows(ctx, cx, cy, 16 * Fp.CELL, 100, rows)
	budget.spend(2 + n)
	var t: AiEntityTable = ctx.kb.enemy_units
	if _local_check(ctx, b):
		return
	if n > 0:
		var sx: int = 0
		var sy: int = 0
		for r: int in rows:
			sx += t.x[r]
			sy += t.y[r]
		_order(ctx, ids, sx / n, sy / n, AiTypes.Intent.ATTACK_MOVE, 100)
		# winning the fight: the next units of the reserve join
		if r_now_q8 >= ctx.tune("army.reinforce_ratio_x100", 120) * 256 / 100 and ctx.tick - _last_reinforce >= ctx.tune("army.reinforce_ticks", 300):
			_last_reinforce = ctx.tick
			b.attack.reinforce(ctx, b, budget, self, sx / n, sy / n, 8)
		return
	# nobody armed in sight and still far from the target: resume the march (regroup at the next waypoint ahead)
	var d_target: int = AiForce.dist(cx, cy, tx, ty)
	if d_target > 25 * Fp.CELL and not waypoints.is_empty() and ctx.tick - state_since >= 40:
		wp_i = waypoints.size() / 2
		for k: int in waypoints.size() / 2:
			if AiForce.dist(waypoints[2 * k], waypoints[2 * k + 1], tx, ty) < d_target - 4 * Fp.CELL:
				wp_i = k
				break
		if wp_i < waypoints.size() / 2:
			_arrive_tick = -1
			_last_order_tick = AiTypes.NEVER
			set_state(ctx, AiTypes.OpState.ADVANCING)
			return
	# destroy the structures of the target cluster
	var gh: int = _nearest_target(ctx)
	if gh < 0:
		targets_done += 1
		set_state(ctx, AiTypes.OpState.CLEANUP)
		return
	var g: AiGhostTable = ctx.kb.ghosts
	tx = g.x[gh]
	ty = g.y[gh]
	target_ghost = g.eid[gh]
	if g.eid[gh] > 0 and ctx.view.targetable_now(g.eid[gh]):
		_order_attack(ctx, g.eid[gh])
	else:
		_order(ctx, ids, tx, ty, AiTypes.Intent.ATTACK_MOVE, 60)
	if ctx.tick - _last_reinforce >= ctx.tune("army.reinforce_ticks", 300):
		_last_reinforce = ctx.tick
		b.attack.reinforce(ctx, b, budget, self, tx, ty, 8)


## Ghost row of an enemy structure nearest to the wave that is still worth attacking (within the cluster of the current target,
## else within 30 cells of the wave); a presumed ghost in plain sight is dropped. -1 when none.
func _nearest_target(ctx: AiContext) -> int:
	var g: AiGhostTable = ctx.kb.ghosts
	var pid: int = ctx.kb.primary
	var best: int = -1
	var best_d: int = 1 << 60
	var reach2: int = (30 * Fp.CELL) * (30 * Fp.CELL)
	var cl2: int = CLUSTER_R * CLUSTER_R
	var i: int = g.count - 1
	while i >= 0:
		if g.owner[i] == pid or (pid < 0 and g.owner[i] >= 0):
			if g.eid[i] < 0 and ctx.view.cell_visible(g.x[i] >> Fp.CELL_SHIFT, g.y[i] >> Fp.CELL_SHIFT):
				g.remove(g.eid[i])
				i = mini(i, g.count) - 1
				continue
			var dxt: int = g.x[i] - tx
			var dyt: int = g.y[i] - ty
			var dxc: int = g.x[i] - cx
			var dyc: int = g.y[i] - cy
			var near_target: bool = dxt * dxt + dyt * dyt <= cl2
			var near_wave: bool = dxc * dxc + dyc * dyc <= reach2
			if near_target or near_wave:
				var d: int = dxc * dxc + dyc * dyc
				if d < best_d or (d == best_d and g.eid[i] < g.eid[best]):
					best_d = d
					best = i
		i -= 1
	return best


func _cleanup(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	if ctx.tick - state_since < ctx.tune("army.cleanup_ticks", 200):
		# a target may reappear (a unit walking into sight): fight it
		if _contact(ctx, 16 * Fp.CELL) or _nearest_target(ctx) >= 0:
			set_state(ctx, AiTypes.OpState.ENGAGING)
		return
	# AE doctrine: the wave holds the battlefield (<= 600 ticks) while enemy wrecks remain to be salvaged
	if salvage_hold < ctx.tune("salvage.hold_ticks", 600) and ctx.pers.has_flag(AiTypes.doctrine_bit("SALVAGE")) and _wrecks_left(ctx):
		salvage_hold += period
		return
	var fg: AiStrengthGroup = AiForce.own_group(ctx, ids)
	var planner: AiAttackPlanner = b.attack
	var tgt: Dictionary = planner.pick_target(ctx, budget, cx, cy, fg, -1, -1, 0, 256)
	if tgt.is_empty() or int(tgt["ratio"]) < ctx.tune("strength.abort_ratio_x100", 70) * 256 / 100:
		_finish(ctx, b)
		return
	tx = int(tgt["x"])
	ty = int(tgt["y"])
	target_ghost = int(tgt["eid"])
	orig_tx = tx
	orig_ty = ty
	target_value = int(tgt.get("value", 0))
	avoid_route.resize(0)
	_plan(ctx, b, budget)
	set_state(ctx, AiTypes.OpState.ADVANCING)
	_last_order_tick = AiTypes.NEVER


## A salvageable enemy wreck within 15 cells of the wave.
func _wrecks_left(ctx: AiContext) -> bool:
	var found: PackedInt32Array = PackedInt32Array()
	ctx.view.wrecks_in_circle(cx, cy, 15 * Fp.CELL, found)
	for wid: int in found:
		if ctx.view.wreck_salvageable(wid):
			return true
	return false


func _retreat(ctx: AiContext, b: AiBrain, aborted: bool) -> void:
	if aborted:
		ctx.telemetry.emit(AiTypes.Tele.ATTACK_ABORTED, r_now_q8, value_now * 100 / maxi(initial_value, 1), ctx.tick)
	ctx.telemetry.emit(AiTypes.Tele.RETREAT_ORDERED, ids.size(), 0, ctx.tick)
	if b != null:
		b.bump("wave_retreat_" + retreat_reason)
	set_state(ctx, AiTypes.OpState.RETREATING)
	_last_order_tick = AiTypes.NEVER
	if b != null and ids.size() > 0:
		ctx.cmd.move(ids, retreat_x, retreat_y)
		_last_order_tick = ctx.tick


func _retreating(ctx: AiContext, b: AiBrain) -> void:
	if AiForce.dist(cx, cy, retreat_x, retreat_y) <= 8 * Fp.CELL or ctx.tick - state_since >= 600:
		_finish(ctx, b)
		return
	if ctx.tick - _last_order_tick >= 100:
		ctx.cmd.move(ids, retreat_x, retreat_y)
		_last_order_tick = ctx.tick


func _finish(ctx: AiContext, b: AiBrain) -> void:
	if state != AiTypes.OpState.RETREATING and b != null:
		b.bump("wave_finished_clean")
	_report(ctx, b)
	release(ctx)
	state = AiTypes.OpState.DONE


func _report(ctx: AiContext, b: AiBrain) -> void:
	if kind != AiTypes.SquadKind.MAIN and sibling >= 0 and b.op_by_id(sibling) != null:
		return
	var now_val: int = _cluster_value(ctx, orig_tx, orig_ty)
	var destroyed: int = 100 - now_val * 100 / maxi(target_value, 1) if target_value > 0 else 0
	b.note_wave_end(ctx, initial_value, maxi(initial_value - value_now, 0), clampi(destroyed, 0, 100), ratio_at_launch)


func _cluster_value(ctx: AiContext, x: int, y: int) -> int:
	var g: AiGhostTable = ctx.kb.ghosts
	var s: int = 0
	var cl2: int = CLUSTER_R * CLUSTER_R
	for i: int in g.count:
		var dx: int = g.x[i] - x
		var dy: int = g.y[i] - y
		if g.owner[i] >= 0 and dx * dx + dy * dy <= cl2:
			s += g.value[i]
	return s


# ------------------------------------------------------------------------------------------------ orders
## Orders `list` to (x, y) unless the same order was given less than `every` ticks ago.
func _order(ctx: AiContext, all_units: PackedInt32Array, x: int, y: int, mode: int, every: int) -> void:
	var list: PackedInt32Array = free_ids(ctx, all_units)
	if list.is_empty():
		return
	# the same kind of order to (nearly) the same place is not repeated before `every` ticks: a re-issued attack-move resets
	# the units' target acquisition, so a moving enemy centroid must not cause an order per update
	if mode == _last_mode and AiForce.dist(x, y, _last_ox, _last_oy) <= 6 * Fp.CELL and ctx.tick - _last_order_tick < every:
		return
	var ok: bool
	if mode == AiTypes.Intent.MOVE:
		ok = ctx.cmd.move(list, x, y)
	else:
		ok = ctx.cmd.attack_move(list, x, y)
	if ok:
		_last_order_tick = ctx.tick
		_last_ox = x
		_last_oy = y
		_last_mode = mode


func _order_attack(ctx: AiContext, eid: int) -> void:
	if _last_mode == AiTypes.Intent.ATTACK and _last_ox == eid and ctx.tick - _last_order_tick < 60:
		return
	if ctx.cmd.attack(free_ids(ctx, ids), eid):
		_last_order_tick = ctx.tick
		_last_ox = eid
		_last_oy = 0
		_last_mode = AiTypes.Intent.ATTACK


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), kind, wp_i, waypoints.size(), initial_value, value_now, targets_done, r_now_q8, siege.state_hash(), salvage_hold, _gv.size(), _gv[_gv.size() - 1] if not _gv.is_empty() else 0]))
