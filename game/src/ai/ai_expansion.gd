class_name AiExpansion
extends RefCounted
## MCV expansion (ai.md 5.4.4, lean; the full AiOpExpand with escorts belongs to AI-08). Also the deploy of a START_MCV start.
## Launch conditions: expansions enabled (difficulty expansions_max > 0 and a non-MINIMAL style, or an `expand` opener step),
## Radar built, the opener finished, no recent attack, fewer than expansions_max done, style timing
## (EARLY 240 s, DEFENDED 330 s, LATE 540 s) and
##   expand_score = 30 + (100 - main_field_left_pct) / 2 + economy / 4 - threat_q8 / 16 >= 55.
## The MCV is trained by a UNIT_ROLE want (prio EXPANSION), sent to a cell 5 cells from the chosen free field on my half of the
## map, deployed there, and the new HQ gets a Refinery want on that field. A failed attempt (MCV lost, deploy refused, timeout
## 3600 ticks) blocks the site for 3600 ticks.

enum State { IDLE = 0, TRAINING = 1, MOVING = 2, DEPLOYING = 3 }

const CHECK_PERIOD: int = 100
const SCORE_MIN: int = 55
const MAX_PATH_CELLS: int = 70
const TIMEOUT_TICKS: int = 6000
const BLOCK_TICKS: int = 3600
const DEPLOY_WAIT: int = 300
const STYLE_MIN_S: PackedInt32Array = [240, 330, 540, 1 << 20]  ## AiTypes.Expand EARLY / DEFENDED / LATE / MINIMAL

var enabled: bool = false
var state: int = State.IDLE
var started: int = 0
var done: int = 0
var failed: int = 0
var site: int = -1
var target_x: int = 0  ## sub-cells
var target_y: int = 0
var mcv_id: int = -1
var op_id: int = -1  ## AiOpExpand escorting the MCV (-1: the plain move / deploy below)
var op_runs: int = 0

var _nominal: PackedInt32Array = PackedInt32Array()  ## per resource site: the largest stock ever seen
var _blocked: Dictionary = {}  ## site row -> until tick
var _t_start: int = 0
var _t_deploy: int = AiTypes.NEVER
var _hq_before: int = 0
var _last_check: int = AiTypes.NEVER
var _last_start_deploy: int = AiTypes.NEVER
var _tries: int = 0


func setup(ctx: AiContext, _hub: AiEconomy) -> void:
	enabled = ctx.diff.expansions_max > 0 and ctx.pers != null and ctx.pers.expand != AiTypes.Expand.MINIMAL
	_nominal.resize(ctx.kb.sites.count)
	for i: int in ctx.kb.sites.count:
		_nominal[i] = ctx.kb.sites.left[i]


func step(ctx: AiContext, budget: AiBudget, eco: AiEconomy) -> void:
	if not budget.spend(3):
		return
	_start_mcv(ctx)
	for i: int in ctx.kb.sites.count:
		_nominal[i] = maxi(_nominal[i], ctx.kb.sites.left[i])
	match state:
		State.IDLE:
			_consider(ctx, budget, eco)
		State.TRAINING:
			_training(ctx, eco)
		State.MOVING:
			_moving(ctx, eco)
		State.DEPLOYING:
			_deploying(ctx, eco)


## START_MCV matches: no HQ yet, an MCV stands on the map -> deploy it where it is.
func _start_mcv(ctx: AiContext) -> void:
	if ctx.view.has_hq() or ctx.tick - _last_start_deploy < 100:
		return
	var ids: PackedInt32Array = _mcvs(ctx)
	if ids.is_empty():
		return
	_last_start_deploy = ctx.tick
	ctx.cmd.deploy(PackedInt32Array([ids[0]]))


func _mcvs(ctx: AiContext) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var t: AiEntityTable = ctx.kb.own
	var bit: int = 1 << AiTypes.R_MCV
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_UNIT and (t.role_mask[r] & bit) != 0:
			out.append(t.eid[r])
	out.sort()
	return out


func _main_left_pct(ctx: AiContext) -> int:
	var sites: AiResourceSites = ctx.kb.sites
	var left: int = 0
	var nom: int = 0
	for i: int in sites.count:
		if sites.kind[i] == AiResourceSites.K_MAIN:
			left += sites.left[i]
			nom += _nominal[i]
	return left * 100 / maxi(nom, 1) if nom > 0 else 100


## Expansions allowed for this AI (tuning exp.extra adds to the difficulty's expansions_max).
func expansions_max(ctx: AiContext) -> int:
	return ctx.diff.expansions_max + (ctx.tune("exp.extra", 0) if ctx.diff.expansions_max > 0 else 0)


func score(ctx: AiContext, site_row: int = -1) -> int:
	var s: int = 30 + (100 - _main_left_pct(ctx)) / 2 + ctx.pers.economy / 4
	if site_row >= 0:
		s -= ctx.kb.sites.threat_q8[site_row] / 16
	return s


func _consider(ctx: AiContext, budget: AiBudget, eco: AiEconomy) -> void:
	if not enabled or ctx.tick - _last_check < CHECK_PERIOD:
		return
	_last_check = ctx.tick
	var mcv_def: int = ctx.res.first(AiTypes.R_MCV)
	if mcv_def < 0 or done >= expansions_max(ctx):
		return
	# AIT: the start fields run dry after about 8 minutes, so the first MCV is due as soon as the economy stands (two Refineries,
	# a Factory, a few Collectors) instead of after the opener / Radar; later ones when the stock of the active fields is low.
	var early: bool = ctx.tune("exp.early", 1) != 0
	if not early and (not eco.opener_done() or eco.planner.tier(ctx) < 2):
		return
	if early and (eco.refineries_active < 2 or eco.collectors_alive < 2 or eco.prod_count_of(AiTypes.StructKind.FACTORY) < 1):
		return
	# an army that is not small against the believed enemy army comes first (a raid on an army-less base ends the game)
	if early and not eco.econ_safe(ctx):
		return
	if ctx.tick < STYLE_MIN_S[ctx.pers.expand] * SimConfig.TPS or eco.collapse or (eco.need_collector and eco.collectors_alive < 3):
		return
	if eco.role_have(AiTypes.R_MCV) > 0:
		return
	for p: int in ctx.kb.enemy_pids:
		if ctx.tick - ctx.kb.attacked_by_tick[p] < 30 * SimConfig.TPS:
			return
	if not budget.spend(20):
		return
	var s: int = _pick_site(ctx)
	if s < 0 or score(ctx, s) < SCORE_MIN:
		return
	site = s
	_compute_target(ctx, s)
	state = State.TRAINING
	started += 1
	_t_start = ctx.tick
	_tries = 0
	_want_mcv(ctx, eco)
	_hq_before = _hq_count(ctx, eco)


func _want_mcv(ctx: AiContext, eco: AiEconomy) -> void:
	var mcv_def: int = ctx.res.first(AiTypes.R_MCV)
	var w: AiWant = AiWant.make(AiTypes.WantKind.UNIT_ROLE, mcv_def, AiTypes.R_MCV, 1, AiEconomy.P_EXPAND, AiTypes.WantOrigin.EXPANSION)
	w.deadline = ctx.tick + 400
	eco.add_want(w)


func _hq_count(ctx: AiContext, eco: AiEconomy) -> int:
	var hq: int = ctx.res.structure_of_kind(AiTypes.StructKind.HQ)
	return eco.struct_own[hq] if hq >= 0 else 0


## Free field row on my half of the map, close by, not threatened; -1 if none.
func _pick_site(ctx: AiContext) -> int:
	var sites: AiResourceSites = ctx.kb.sites
	var kb: AiKnowledge = ctx.kb
	var hcx: int = sites.home_x >> Fp.CELL_SHIFT
	var hcy: int = sites.home_y >> Fp.CELL_SHIFT
	var best: int = -1
	var best_len: int = 1 << 20
	for i: int in sites.count:
		if sites.kind[i] != AiResourceSites.K_NEAR and sites.kind[i] != AiResourceSites.K_FAR:
			continue
		if sites.left[i] <= 0 or sites.threat_q8[i] > 64 or int(_blocked.get(i, 0)) > ctx.tick:
			continue
		if sites.path_len_c[i] < 0 or sites.path_len_c[i] > MAX_PATH_CELLS:
			continue
		var fx: int = sites.x[i] >> Fp.CELL_SHIFT
		var fy: int = sites.y[i] >> Fp.CELL_SHIFT
		if _own_structure_near(ctx, sites.x[i], sites.y[i], 10):
			continue
		var dme: int = maxi(absi(fx - hcx), absi(fy - hcy))
		var de: int = 1 << 20
		for e: int in kb.enemy_starts.size() / 2:
			de = mini(de, maxi(absi(fx - kb.enemy_starts[2 * e]), absi(fy - kb.enemy_starts[2 * e + 1])))
		if dme * 10 > de * 11:
			continue
		if sites.path_len_c[i] < best_len:
			best_len = sites.path_len_c[i]
			best = i
	return best


func _own_structure_near(ctx: AiContext, x: int, y: int, cells: int) -> bool:
	var t: AiEntityTable = ctx.kb.own
	var r2: int = cells * cells * Fp.CELL * Fp.CELL
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_STRUCTURE:
			continue
		var dx: int = t.x[r] - x
		var dy: int = t.y[r] - y
		if dx * dx + dy * dy <= r2:
			return true
	return false


## The deploy cell: 5 cells from the field towards my base, moved to a passable cell of my land region.
func _compute_target(ctx: AiContext, s: int) -> void:
	var sites: AiResourceSites = ctx.kb.sites
	var v: AiWorldView = ctx.view
	var dx: int = sites.home_x - sites.x[s]
	var dy: int = sites.home_y - sites.y[s]
	var dist: int = maxi(Fp.dist(dx, dy), 1)
	var cx: int = (sites.x[s] + dx * 5 * Fp.CELL / dist) >> Fp.CELL_SHIFT
	var cy: int = (sites.y[s] + dy * 5 * Fp.CELL / dist) >> Fp.CELL_SHIFT
	var region: int = v.region(sites.home_x >> Fp.CELL_SHIFT, sites.home_y >> Fp.CELL_SHIFT, AiTypes.MoveClass.TRACKED)
	for ring: int in 8:
		for oy: int in range(-ring, ring + 1):
			for ox: int in range(-ring, ring + 1):
				if maxi(absi(ox), absi(oy)) != ring:
					continue
				var px: int = cx + ox
				var py: int = cy + oy
				if v.passable(px, py, AiTypes.MoveClass.TRACKED) and v.region(px, py, AiTypes.MoveClass.TRACKED) == region \
						and _open_around(v, px, py):
					target_x = px * Fp.CELL + Fp.CELL / 2
					target_y = py * Fp.CELL + Fp.CELL / 2
					return
	target_x = cx * Fp.CELL + Fp.CELL / 2
	target_y = cy * Fp.CELL + Fp.CELL / 2


## The HQ footprint needs open ground: a 5 x 5 block that is passable.
func _open_around(v: AiWorldView, cx: int, cy: int) -> bool:
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			if not v.passable(cx + dx, cy + dy, AiTypes.MoveClass.TRACKED):
				return false
	return true


func _fail(ctx: AiContext, eco: AiEconomy, why: String) -> void:
	failed += 1
	if site >= 0:
		_blocked[site] = ctx.tick + BLOCK_TICKS
	Log.debug("ai", "expansion failed: %s" % why)
	for w: AiWant in eco.wants:
		if w.origin == AiTypes.WantOrigin.EXPANSION and w.role == AiTypes.R_MCV:
			w.state = AiTypes.WantState.DROPPED
	state = State.IDLE
	site = -1
	mcv_id = -1
	op_id = -1


func _training(ctx: AiContext, eco: AiEconomy) -> void:
	var ids: PackedInt32Array = _mcvs(ctx)
	if not ids.is_empty():
		mcv_id = ids[0]
		state = State.MOVING
		_t_start = ctx.tick
		var b: AiBrain = ctx.brain as AiBrain
		if b != null:
			var op: AiOpExpand = AiOpExpand.new()
			op.setup_expand(mcv_id, target_x, target_y, _hq_count(ctx, eco))
			if b.add_op(ctx, op):
				op_id = op.id
				op_runs += 1
				b.bump("expand_ops")
				ctx.telemetry.emit(AiTypes.Tele.EXPAND_OP, site, op.id, ctx.tick)
				return
		ctx.cmd.move(PackedInt32Array([mcv_id]), target_x, target_y)
		return
	if ctx.tick - _t_start > TIMEOUT_TICKS:
		_fail(ctx, eco, "no mcv")
	else:
		_want_mcv(ctx, eco)


func _moving(ctx: AiContext, eco: AiEconomy) -> void:
	if op_id >= 0:
		var b: AiBrain = ctx.brain as AiBrain
		var op: AiOp = b.op_by_id(op_id) if b != null else null
		if op == null or op.is_over():
			var ok: bool = _hq_count(ctx, eco) > _hq_before
			op_id = -1
			if ok:
				_succeed(ctx, eco)
			else:
				_fail(ctx, eco, "op failed")
		elif ctx.tick - _t_start > TIMEOUT_TICKS:
			op.abort(ctx, AiTypes.Err.OP_TIMEOUT)
		return
	var t: AiEntityTable = ctx.kb.own
	var r: int = t.row(mcv_id)
	if r < 0:
		_fail(ctx, eco, "mcv lost")
		return
	var dx: int = t.x[r] - target_x
	var dy: int = t.y[r] - target_y
	var d2: int = dx * dx + dy * dy
	var near: bool = d2 <= 3 * 3 * Fp.CELL * Fp.CELL
	var stalled: bool = t.order[r] == AiTypes.OrderKind.IDLE and d2 <= 10 * 10 * Fp.CELL * Fp.CELL
	if near or stalled:
		ctx.cmd.deploy(PackedInt32Array([mcv_id]))
		state = State.DEPLOYING
		_t_deploy = ctx.tick
		return
	if ctx.tick - _t_start > TIMEOUT_TICKS:
		_fail(ctx, eco, "timeout")
	elif t.order[r] == AiTypes.OrderKind.IDLE and ctx.tick % 200 < ctx.dt:
		ctx.cmd.move(PackedInt32Array([mcv_id]), target_x, target_y)


func _deploying(ctx: AiContext, eco: AiEconomy) -> void:
	if _hq_count(ctx, eco) > _hq_before:
		_succeed(ctx, eco)
		return
	if ctx.tick - _t_deploy < DEPLOY_WAIT:
		return
	var t: AiEntityTable = ctx.kb.own
	var r: int = t.row(mcv_id)
	if r < 0:
		_fail(ctx, eco, "mcv lost")
		return
	_tries += 1
	if _tries > 3:
		_fail(ctx, eco, "deploy refused")
		return
	# the spot was refused: try a spot a few cells closer to home
	var sites: AiResourceSites = ctx.kb.sites
	target_x += (sites.home_x - target_x) / 12
	target_y += (sites.home_y - target_y) / 12
	ctx.cmd.move(PackedInt32Array([mcv_id]), target_x, target_y)
	state = State.MOVING


func _succeed(ctx: AiContext, eco: AiEconomy) -> void:
	done += 1
	state = State.IDLE
	var rdef: int = ctx.res.structure_of_kind(AiTypes.StructKind.REFINERY)
	if rdef >= 0 and site >= 0:
		var sites: AiResourceSites = ctx.kb.sites
		var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, rdef, -1, eco.struct_own[rdef] + eco.struct_q[rdef] + 1, AiEconomy.P_ECON,
			AiTypes.WantOrigin.EXPANSION)
		w.site_kind = AiPlacer.Site.FIELD
		w.site_x = sites.x[site]
		w.site_y = sites.y[site]
		eco.add_want(w)
	ctx.telemetry.emit(AiTypes.Tele.EXPANSION_DEPLOYED, site, done, ctx.tick)
	site = -1
	mcv_id = -1


## Tick the current TRAINING state began (0 when idle).
func training_since() -> int:
	return _t_start


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([state, started, done, failed, site, op_runs, _t_start]))
