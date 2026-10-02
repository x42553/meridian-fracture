class_name AiProduction
extends RefCounted
## Slot 7 (ai.md 5.6.2 / 5.6.3): per-producer queue refill by composition deficit.
##   value_now[r] = cost x hp fraction of the alive units of role r + the cost of the queued ones (AiEconomy census);
##   deficit[r]   = share_q8[r] x max(V, V_floor) / 256 - value_now[r]        (V_floor 1500 opening, 4000 later)
## A producer with fewer than `queue_depth` queued items gets the producible def of the role with the largest deficit whose
## producer kind matches (ties: lowest role bit); the minimum counts of the opener's `train` steps are served first. A line
## only starts when AiEconomy.fund_status allows it (collector reserve, collapse rule, burn cap). Also: rally points (staging
## point 11 cells from the HQ towards the primary enemy), aircraft <= pads x 3/2, carriers <= 1 per 6 escorts, unit cap
## (`unit_cap x unit_cap_pct - 6`), and the squad manager upkeep.

const V_FLOOR_OPENING: int = 1500
const V_FLOOR: int = 4000
const STAGE_REEVAL_TICKS: int = 600
const STAGE_MOVE_CELLS: int = 8
const STAGE_DIST_CELLS: int = 13
const STAGE_BORDER_CELLS: int = 10  ## a staging cell is at least this far from the map border
const CAP_RESERVE: int = 6
const MAX_LINES_PER_PASS: int = 6

var stage_x: int = 0  ## sub-cells
var stage_y: int = 0
var stage_aa_x: int = 0
var stage_aa_y: int = 0
var trained: int = 0
var rally_cmds: int = 0
var last_role: int = -1
var trained_role: PackedInt32Array = PackedInt32Array()  ## units queued so far, by composition role (telemetry / tests)

var _hub: WeakRef = null
var _stage_tick: int = AiTypes.NEVER
var _stage_primary: int = -2
var _rallied: Dictionary = {}  ## producer eid -> [x, y]
var _empty_since: Dictionary = {}  ## producer eid -> tick
var _cand_role: PackedInt32Array = PackedInt32Array()
var _cand_def: PackedInt32Array = PackedInt32Array()
var _cand_deficit: PackedInt32Array = PackedInt32Array()
var _value_now: PackedInt32Array = PackedInt32Array()


func bind(hub: AiEconomy) -> void:
	_hub = weakref(hub)


func setup(ctx: AiContext) -> void:
	var hx: int = ctx.view.start_cell_x(ctx.view.me()) * Fp.CELL + Fp.CELL / 2
	var hy: int = ctx.view.start_cell_y(ctx.view.me()) * Fp.CELL + Fp.CELL / 2
	stage_x = hx
	stage_y = hy
	stage_aa_x = hx
	stage_aa_y = hy
	_value_now.resize(AiTypes.ROLE_COUNT)
	trained_role.resize(AiTypes.ROLE_COUNT)


func set_stage(x: int, y: int) -> void:
	stage_x = x
	stage_y = y
	_stage_tick = _hub_tick()


func _hub_tick() -> int:
	var eco: AiEconomy = _hub.get_ref()
	return eco.now_tick() if eco != null else 0


func step(ctx: AiContext, budget: AiBudget) -> void:
	var eco: AiEconomy = _hub.get_ref()
	if eco == null or not budget.spend(4):
		return
	eco.refresh(ctx, budget)
	eco.comp.update(ctx, budget)
	_stage(ctx, budget)
	_rally(ctx, budget, eco)
	_refill(ctx, budget, eco)
	eco.squads.step(ctx, budget)


# ------------------------------------------------------------------------------------------ staging point
func _stage(ctx: AiContext, budget: AiBudget) -> void:
	var kb: AiKnowledge = ctx.kb
	if ctx.tick - _stage_tick < STAGE_REEVAL_TICKS and kb.primary == _stage_primary:
		return
	if not budget.spend(20):
		return
	_stage_tick = ctx.tick
	_stage_primary = kb.primary
	var v: AiWorldView = ctx.view
	var hx: int = kb.sites.home_x
	var hy: int = kb.sites.home_y
	var tx: int = v.map_w() * Fp.CELL / 2
	var ty: int = v.map_h() * Fp.CELL / 2
	var hq: PackedInt32Array = PackedInt32Array()
	if kb.primary >= 0 and kb.enemy_hq(kb.primary, hq):
		# AIT: aim half way between the enemy HQ and the map centre: on a ring of start positions (8 players) the nearest enemy lies along the
		# border, and an army staged towards it stands at the map edge; half the pull towards the centre puts it in front of the base
		var cxm: int = v.map_w() * Fp.CELL / 2
		var cym: int = v.map_h() * Fp.CELL / 2
		var pull: int = ctx.tune("army.stage_center_pull_pct", 50)
		tx = (hq[0] * (100 - pull) + cxm * pull) / 100
		ty = (hq[1] * (100 - pull) + cym * pull) / 100
	var dx: int = tx - hx
	var dy: int = ty - hy
	var dist: int = maxi(Fp.dist(dx, dy), 1)
	var px: int = (hx + dx * STAGE_DIST_CELLS * Fp.CELL / dist) >> Fp.CELL_SHIFT
	var py: int = (hy + dy * STAGE_DIST_CELLS * Fp.CELL / dist) >> Fp.CELL_SHIFT
	# snap: nearest cell with >= 2 passable neighbours and no threat, rings up to 6
	var found: bool = false
	for ring: int in 7:
		for oy: int in range(-ring, ring + 1):
			for ox: int in range(-ring, ring + 1):
				if maxi(absi(ox), absi(oy)) != ring or found:
					continue
				if _stage_ok(ctx, px + ox, py + oy):
					px += ox
					py += oy
					found = true
		if found:
			break
	stage_x = px * Fp.CELL + Fp.CELL / 2
	stage_y = py * Fp.CELL + Fp.CELL / 2
	stage_aa_x = hx
	stage_aa_y = hy


func _stage_ok(ctx: AiContext, cx: int, cy: int) -> bool:
	var v: AiWorldView = ctx.view
	if cx < STAGE_BORDER_CELLS or cy < STAGE_BORDER_CELLS or cx >= v.map_w() - STAGE_BORDER_CELLS or cy >= v.map_h() - STAGE_BORDER_CELLS:
		return false
	if not v.passable(cx, cy, AiTypes.MoveClass.TRACKED):
		return false
	var n: int = 0
	for d: int in 4:
		var nx: int = cx + (1 if d == 0 else (-1 if d == 1 else 0))
		var ny: int = cy + (1 if d == 2 else (-1 if d == 3 else 0))
		if v.passable(nx, ny, AiTypes.MoveClass.TRACKED):
			n += 1
	if n < 2 or ctx.kb.threat_at(cx * Fp.CELL, cy * Fp.CELL) != 0:
		return false
	# AIT: never rally the army into a live warning zone (Horizon debris, Atlas / Perun footprints)
	var b: AiBrain = ctx.brain as AiBrain
	if b != null and not b.powers.dispersal.avoid.is_empty():
		var px: int = cx * Fp.CELL + Fp.CELL / 2
		var py: int = cy * Fp.CELL + Fp.CELL / 2
		if b.powers.dispersal.avoided(px, py, AiDispersal.AV_DANGER, ctx.tick) or b.powers.dispersal.avoided(px, py, AiDispersal.AV_DEBRIS, ctx.tick):
			return false
	return true


func _rally(ctx: AiContext, budget: AiBudget, eco: AiEconomy) -> void:
	for i: int in eco.prod_eid.size():
		var k: int = eco.prod_kind[i]
		if k != AiTypes.StructKind.BARRACKS and k != AiTypes.StructKind.FACTORY:
			continue
		var id: int = eco.prod_eid[i]
		var cur: Array = _rallied.get(id, [])
		var need: bool = cur.is_empty()
		if not need:
			var dx: int = int(cur[0]) - stage_x
			var dy: int = int(cur[1]) - stage_y
			need = dx * dx + dy * dy > STAGE_MOVE_CELLS * STAGE_MOVE_CELLS * Fp.CELL * Fp.CELL
		if need and budget.spend(1) and ctx.cmd.set_rally(id, stage_x, stage_y):
			_rallied[id] = [stage_x, stage_y]
			rally_cmds += 1


# ------------------------------------------------------------------------------------------------ refill
func _refill(ctx: AiContext, budget: AiBudget, eco: AiEconomy) -> void:
	if eco.collapse:
		return
	var v: AiWorldView = ctx.view
	var cap_stop: int = v.unit_cap() * ctx.diff.unit_cap_pct / 100 - CAP_RESERVE
	if v.unit_count() >= cap_stop:
		return
	var comp: AiComposition = eco.comp
	var depth: int = ctx.diff.queue_depth
	_value_now = eco.role_value.duplicate()
	var mcv_row: int = eco.mcv_slot_row() if eco.mcv_wanted_unqueued() else -1  # AIT: the Factory the expansion MCV will use stays free
	var total: int = 0
	for r: int in comp.roles:
		total += _value_now[r]
	var floor_v: int = V_FLOOR_OPENING if comp.phase == AiTypes.Phase.OPENING else V_FLOOR
	# The line with the LARGEST deficit is served first (across all producers), so an expensive need such as anti-air is not
	# starved by cheap infantry lines eating the burn cap; when the best line cannot be funded nothing else starts.
	for _n: int in MAX_LINES_PER_PASS:
		var best_i: int = -1
		var best_d: int = -1
		var best_role: int = -1
		var best_deficit: int = -(1 << 30)
		for i: int in eco.prod_eid.size():
			var kind: int = eco.prod_kind[i]
			if kind == AiTypes.StructKind.REFINERY or kind < 0:
				continue
			var id: int = eco.prod_eid[i]
			if eco.prod_qlen[i] >= depth or eco.is_held(id) or i == mcv_row:
				continue
			if eco.prod_qlen[i] == 0:
				if not _empty_since.has(id):
					_empty_since[id] = ctx.tick
				if ctx.tick - int(_empty_since[id]) < ctx.diff.idle_tolerance_ticks:
					continue
			if not budget.spend(6):
				return
			_candidates(ctx, eco, kind, maxi(total, floor_v))
			for c: int in _cand_def.size():
				if v.can_train(id, _cand_def[c]) != AiTypes.Rule.OK:
					continue
				if _cand_deficit[c] > best_deficit:
					best_deficit = _cand_deficit[c]
					best_i = i
					best_d = _cand_def[c]
					best_role = _cand_role[c]
				break
		if best_i < 0:
			return
		var cost: int = v.unit_cost(best_d)
		var ticks: int = v.unit_ticks(best_d)
		if eco.fund_status(AiEconomy.P_ARMY, cost, ticks) != 0:
			return  # no funds / burn cap
		if not ctx.cmd.train(eco.prod_eid[best_i], best_d, 1):
			return
		eco.take_fund(cost, ticks)
		eco.prod_qlen[best_i] += 1
		eco.unit_queued[best_d] += 1
		if best_role >= 0:
			_value_now[best_role] += cost
			total += cost
			trained_role[best_role] += 1
		last_role = best_role
		trained += 1
		_empty_since.erase(eco.prod_eid[best_i])


## Fills _cand_* for one producer kind: the opener's minimum counts first, then the roles by descending deficit.
func _candidates(ctx: AiContext, eco: AiEconomy, kind: int, v_eff: int) -> void:
	_cand_role.resize(0)
	_cand_def.resize(0)
	_cand_deficit.resize(0)
	for req: Variant in eco.planner.train_requests:
		var a: Array = req
		var d: int = int(a[1])
		if d < 0 or eco.producer_kind_of(ctx, d) != kind:
			continue
		var have: int = eco.role_have(int(a[0])) if int(a[0]) >= 0 else eco.unit_alive[d] + eco.unit_queued[d]
		if have < int(a[2]):
			_cand_role.append(eco.comp.comp_role_of_def[d])
			_cand_def.append(d)
			_cand_deficit.append(1 << 20)
	for r: int in eco.comp.roles:
		var share: int = eco.comp.share_q8[r]
		if share <= 0:
			continue
		var d2: int = eco.comp.def_pick[r]
		if d2 < 0 or eco.producer_kind_of(ctx, d2) != kind or _role_capped(ctx, eco, r):
			continue
		var deficit: int = share * v_eff / 256 - _value_now[r]
		_insert_candidate(r, d2, deficit)


func _insert_candidate(role: int, def: int, deficit: int) -> void:
	var pos: int = _cand_deficit.size()
	while pos > 0 and _cand_deficit[pos - 1] < deficit:
		pos -= 1
	_cand_role.insert(pos, role)
	_cand_def.insert(pos, def)
	_cand_deficit.insert(pos, deficit)


## Role-specific caps: aircraft <= pads x 3/2, one carrier per six escorts.
func _role_capped(ctx: AiContext, eco: AiEconomy, role: int) -> bool:
	if role == AiTypes.R_FIGHTER or role == AiTypes.R_BOMBER or role == AiTypes.R_EW_AIR:
		var af: int = ctx.res.structure_of_kind(AiTypes.StructKind.AIRFIELD)
		if af < 0:
			return true
		var sd: DefStructure = ctx.view.structure_def(af)
		var cap: int = eco.struct_own[af] * maxi(sd.pads, 1) * 3 / 2
		var n: int = eco.role_alive[AiTypes.R_FIGHTER] + eco.role_queued[AiTypes.R_FIGHTER] + eco.role_alive[AiTypes.R_BOMBER] \
			+ eco.role_queued[AiTypes.R_BOMBER] + eco.role_alive[AiTypes.R_EW_AIR] + eco.role_queued[AiTypes.R_EW_AIR]
		return n >= cap
	if role == AiTypes.R_CARRIER:
		var carriers: int = eco.role_alive[AiTypes.R_CARRIER] + eco.role_queued[AiTypes.R_CARRIER]
		var escorts: int = eco.role_alive[AiTypes.R_ESCORT_SHIP] + eco.role_queued[AiTypes.R_ESCORT_SHIP]
		return escorts < 6 * (carriers + 1)
	return false


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([trained, rally_cmds, stage_x, stage_y, last_role]))
