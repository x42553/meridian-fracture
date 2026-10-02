class_name AiBuildPlanner
extends RefCounted
## Slot 5 (ai.md 5.5.2 / 5.4.1): executes the roster's opener script and target table and drives the single construction queue.
##  * `update_wants` (called by AiEconomy each think): advances the script pointer (non-parallel steps run strictly in order,
##    parallel ones are background wants), turns `build` steps and due `targets` entries into AiWant, keeps the `train_requests`
##    (minimum counts the production honours first) and the research requests of `research` steps.
##  * `issue_struct` (called by AiEconomy.allocate for the granted want): BUILD_START; `start_pending` stops a second grant
##    while the command is still on its way.
##  * `step`: placement. At >= 80 % progress the AiPlacer job for the structure in progress starts, so the cell is ready when
##    the structure finishes; after `place_latency_ticks` the BUILD_PLACE command is issued. A cell the sim did not accept
##    is blacklisted and another one is searched; no site for 600 ticks cancels the construction (refund) and blocks the def.
## The condition vocabulary (`eval_cond`) is the subset of AiCond (5.5.2) the shipped data uses; unknown keys are logged once
## and count as true.

const ST_WAIT: int = 0
const ST_ACTIVE: int = 1
const ST_DONE: int = 2
const ST_SKIPPED: int = 3
const START_LAG: int = 30
const PLACE_LAG: int = 14
const NO_SITE_TICKS: int = 600
const PREPARE_PCT: int = 80

var steps: Array[Step] = []
var targets: Array[Target] = []
var spine_done: bool = false
var train_requests: Array = []  ## [role, def, n] triples of the active train steps
var flags: Dictionary = {}
var stalls: int = 0
var placed: int = 0
var place_fails: int = 0

var _hub: WeakRef = null
var _job: AiJob = null
var _job_def: int = -1
var _job_res: PackedInt32Array = PackedInt32Array()
var _ready_def: int = -1
var _ready_since: int = 0
var _place_tick: int = -1
var _place_cell: PackedInt32Array = PackedInt32Array()
var _start_tick: int = -1
var _no_site_since: int = -1
var _site_of: Dictionary = {}  ## struct def -> [site_kind, hint_x, hint_y]
var _warned: Dictionary = {}
var _cstate: PackedInt32Array = PackedInt32Array()


class Step extends RefCounted:
	var d: Dictionary = {}
	var id: String = ""
	var op: String = ""
	var parallel: bool = false
	var state: int = 0
	var want: AiWant = null
	var kind: int = -1
	var def: int = -1
	var role: int = -1
	var n: int = 0
	var base: int = 0
	var t_first: int = -1
	var t_active: int = -1
	var timeout: int = 240 * 20
	var res_idx: int = -1


class Target extends RefCounted:
	var d: Dictionary = {}
	var id: String = ""
	var def: int = -1
	var kind: int = -1
	var n: int = 1
	var from_ticks: int = 0


func bind(hub: AiEconomy) -> void:
	_hub = weakref(hub)


func setup(ctx: AiContext) -> void:
	var eco: AiEconomy = _hub.get_ref()
	var data: GameData = ctx.view.game_data()
	steps.clear()
	targets.clear()
	for sd: Variant in eco.doctrine.opener:
		var d: Dictionary = sd
		var s: Step = Step.new()
		s.d = d
		s.id = str(d.get("id", ""))
		s.op = str(d.get("op", ""))
		s.parallel = bool(d.get("parallel", false))
		s.n = int(d.get("n", 0))
		s.timeout = int(d.get("timeout_s", 600 if s.op == "build" and not s.parallel else 240)) * SimConfig.TPS
		match s.op:
			"build":
				s.kind = AiDoctrine.struct_kind_of(str(d.get("struct", "")))
				s.def = ctx.res.structure_of_kind(s.kind) if s.kind >= 0 else -1
				if s.def < 0:
					s.state = ST_SKIPPED
			"train":
				if d.has("def"):
					s.def = data.unit_idx(str(d["def"]))
					if s.def < 0 or not ctx.view.roster().has_unit(s.def):
						s.state = ST_SKIPPED
				else:
					s.role = AiTypes.role_bit(str(d.get("role", "")))
					if s.role < 0 or not ctx.res.has_role(s.role):
						s.state = ST_SKIPPED
					else:
						s.def = ctx.res.first(s.role)
			"research":
				s.res_idx = data.research_idx(str(d.get("research", "")))
				if s.res_idx < 0 or not ctx.view.roster().research_list.has(s.res_idx):
					s.state = ST_SKIPPED
		if bool(d.get("opt", false)) and s.state == ST_WAIT:
			if ctx.rng.range_i(0, 99) >= ctx.diff.opt_step_keep_pct:
				s.state = ST_SKIPPED
		steps.append(s)
	for td: Variant in eco.doctrine.targets:
		var e: Dictionary = td
		var t: Target = Target.new()
		t.d = e
		t.id = str(e.get("id", ""))
		t.kind = AiDoctrine.struct_kind_of(str(e.get("struct", "")))
		t.def = ctx.res.structure_of_kind(t.kind) if t.kind >= 0 else -1
		t.n = int(e.get("n", 1))
		t.from_ticks = int(e.get("from_s", 0)) * SimConfig.TPS * ctx.diff.tech_delay_x100 / 100
		if t.def >= 0:
			targets.append(t)


# ------------------------------------------------------------------------------------------ script
func update_wants(ctx: AiContext, budget: AiBudget) -> void:
	var eco: AiEconomy = _hub.get_ref()
	train_requests.clear()
	var blocked: bool = false
	var spine: bool = true
	for s: Step in steps:
		if s.state >= ST_DONE:
			continue
		if not s.parallel:
			spine = false
		if not s.parallel and blocked:
			continue
		if not budget.spend(2):
			return
		_eval_step(ctx, s, eco)
		if not s.parallel and s.state < ST_DONE:
			blocked = true
	if spine and not spine_done:
		ctx.telemetry.emit_first(AiTypes.Tele.OPENER_DONE, stalls, 0, ctx.tick)
	spine_done = spine
	_targets(ctx, eco, budget)


func _eval_step(ctx: AiContext, s: Step, eco: AiEconomy) -> void:
	var tick: int = ctx.tick
	if s.t_first < 0:
		s.t_first = tick
	if s.d.has("skip_if") and eval_cond(ctx, s.d["skip_if"]):
		s.state = ST_SKIPPED
		return
	if s.state == ST_WAIT:
		if not eval_cond(ctx, s.d.get("when", true)):
			if not s.parallel and tick - s.t_first > s.timeout:
				_stall(ctx, s)
			return
		_activate(ctx, s, eco)
		if s.state >= ST_DONE:
			return
	if tick - s.t_active > s.timeout:
		_stall(ctx, s)
		return
	match s.op:
		"build":
			if eco.struct_own[s.def] >= _target_count(s):
				s.state = ST_DONE
		"train":
			var have: int = eco.unit_alive[s.def] + eco.unit_queued[s.def] if s.role < 0 else eco.role_have(s.role)
			if have >= s.n:
				s.state = ST_DONE
			else:
				train_requests.append([s.role, s.def, s.n])
		"research":
			if ctx.view.research_done(s.res_idx):
				s.state = ST_DONE


func _target_count(s: Step) -> int:
	return s.n if s.n > 0 else s.base + 1


func _activate(ctx: AiContext, s: Step, eco: AiEconomy) -> void:
	s.state = ST_ACTIVE
	s.t_active = ctx.tick
	match s.op:
		"build":
			s.base = eco.struct_own[s.def]
			var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, s.def, -1, _target_count(s), int(s.d.get("prio", AiEconomy.P_OPENER if not s.parallel else AiEconomy.P_OPENER + 8)),
				AiTypes.WantOrigin.OPENER)
			w.step_id = s.id
			w.site_kind = _site_kind(str(s.d.get("site", "")), s.kind)
			s.want = eco.add_want(w)
		"research":
			var rd: DefResearch = ctx.view.research_def(s.res_idx)
			if rd != null:
				eco.tech.requested[rd.id] = int(s.d.get("prio", 30))
		"expand":
			eco.expansion.enabled = true
			s.state = ST_DONE
		_:
			if s.op != "train":
				s.state = ST_DONE  # scout / power / set: owned by other modules


func _stall(ctx: AiContext, s: Step) -> void:
	s.state = ST_SKIPPED
	stalls += 1
	if s.want != null:
		s.want.state = AiTypes.WantState.DROPPED
	ctx.telemetry.emit(AiTypes.Tele.STALL, AiTypes.Err.STALL_QUEUE, s.id.hash(), ctx.tick)


func _site_kind(name: String, struct_kind: int) -> int:
	match name:
		"back":
			return AiPlacer.Site.BACK
		"front":
			return AiPlacer.Site.FRONT
		"field":
			return AiPlacer.Site.FIELD
		"choke":
			return AiPlacer.Site.CHOKE
		"relay_zone":
			return AiPlacer.Site.RELAY
	return default_site(struct_kind)


static func default_site(struct_kind: int) -> int:
	match struct_kind:
		AiTypes.StructKind.GENERATOR, AiTypes.StructKind.RADAR, AiTypes.StructKind.LAB, AiTypes.StructKind.SUPERWEAPON:
			return AiPlacer.Site.BACK
		AiTypes.StructKind.REFINERY:
			return AiPlacer.Site.FIELD
		AiTypes.StructKind.AT_TURRET, AiTypes.StructKind.ADV_DEFENSE:
			return AiPlacer.Site.FRONT
		AiTypes.StructKind.WATCHTOWER, AiTypes.StructKind.AA_BATTERY:
			return AiPlacer.Site.RING
	return AiPlacer.Site.ANY


func _targets(ctx: AiContext, eco: AiEconomy, budget: AiBudget) -> void:
	for t: Target in targets:
		if ctx.tick < t.from_ticks or not budget.spend(1):
			continue
		if eco.struct_own[t.def] + eco.struct_q[t.def] >= t.n:
			continue
		if t.d.has("when") and not eval_cond(ctx, t.d["when"]):
			continue
		var prio: int = AiEconomy.P_ECON if t.kind == AiTypes.StructKind.REFINERY else AiEconomy.P_TECH
		var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, t.def, -1, t.n, prio, AiTypes.WantOrigin.TARGET)
		w.step_id = t.id
		w.site_kind = default_site(t.kind)
		w.deadline = ctx.tick + 200
		eco.add_want(w)


# ---------------------------------------------------------------------------------------- construction
## BUILD_START for the granted want. The site preferences of the want are remembered for the placement.
func issue_struct(ctx: AiContext, w: AiWant, target: int) -> bool:
	if not ctx.cmd.build_start(target):
		return false
	_start_tick = ctx.tick
	var kind_target: int = ctx.res.kind_of_structure(target)
	var sk: int = w.site_kind if target == w.def else default_site(kind_target)
	_site_of[target] = [sk, w.site_x if target == w.def else -1, w.site_y if target == w.def else -1]
	return true


func start_pending(ctx: AiContext) -> bool:
	return _start_tick >= 0 and ctx.tick - _start_tick < START_LAG


func on_cancelled(_ctx: AiContext) -> void:
	_job = null
	_job_def = -1
	_ready_def = -1
	_place_tick = -1
	_start_tick = -1


func step(ctx: AiContext, budget: AiBudget) -> void:
	var eco: AiEconomy = _hub.get_ref()
	if eco == null or not budget.spend(3):
		return
	eco.refresh(ctx, budget)
	var v: AiWorldView = ctx.view
	v.construction_state(_cstate)
	var st: int = _cstate[0]
	if _start_tick >= 0 and st != 0:
		_start_tick = -1
	elif _start_tick >= 0 and ctx.tick - _start_tick >= START_LAG:
		ctx.cmd.note_no_effect(AiTypes.Intent.BUILD_START, 0, ctx.tick)
		_start_tick = -1
	match st:
		2:
			_place(ctx, budget, eco, _cstate[3])
		1:
			_ready_def = -1
			if _cstate[2] >= PREPARE_PCT:
				_prepare(ctx, budget, eco, _cstate[1])
		0:
			_ready_def = -1
			_job = null
			_no_site_since = -1


func _site_for(ctx: AiContext, eco: AiEconomy, def: int) -> PackedInt32Array:
	var kind: int = ctx.res.kind_of_structure(def)
	var sk: int = default_site(kind)
	var hx: int = -1
	var hy: int = -1
	if _site_of.has(def):
		var a: Array = _site_of[def]
		sk = int(a[0])
		hx = int(a[1])
		hy = int(a[2])
	if kind == AiTypes.StructKind.REFINERY and hx < 0:
		var f: PackedInt32Array = free_field(ctx, eco)
		if f.size() == 2:
			hx = f[0]
			hy = f[1]
			sk = AiPlacer.Site.FIELD
	if sk == AiPlacer.Site.FIELD and hx < 0:
		sk = AiPlacer.Site.RING
	return PackedInt32Array([sk, hx, hy])


## Centre of the nearest deposit field (to my HQ) that has no refinery of mine next to it; [] if there is no field.
func free_field(ctx: AiContext, eco: AiEconomy) -> PackedInt32Array:
	var sites: AiResourceSites = ctx.kb.sites
	var best: int = -1
	var best_d: int = 1 << 60
	var second: int = -1
	var second_d: int = 1 << 60
	for i: int in sites.count:
		if sites.left[i] <= 0 or sites.kind[i] > AiResourceSites.K_NEAR:
			continue
		var dx: int = sites.x[i] - sites.home_x
		var dy: int = sites.y[i] - sites.home_y
		var d2: int = dx * dx + dy * dy
		var taken: bool = false
		for j: int in eco.ref_pos.size() / 2:
			var rx: int = eco.ref_pos[2 * j] - sites.x[i]
			var ry: int = eco.ref_pos[2 * j + 1] - sites.y[i]
			if rx * rx + ry * ry < 7 * 7 * Fp.CELL * Fp.CELL:
				taken = true
		if taken:
			if d2 < second_d:
				second_d = d2
				second = i
			continue
		if d2 < best_d:
			best_d = d2
			best = i
	if best < 0:
		best = second
	if best < 0:
		return PackedInt32Array()
	return PackedInt32Array([sites.x[best], sites.y[best]])


func _start_job(ctx: AiContext, eco: AiEconomy, def: int) -> void:
	var s: PackedInt32Array = _site_for(ctx, eco, def)
	_job = eco.placer.request(def, s[0], s[1], s[2])
	_job_def = def
	_job_res = PackedInt32Array()


func _prepare(ctx: AiContext, budget: AiBudget, eco: AiEconomy, def: int) -> void:
	if _job == null or _job_def != def:
		_start_job(ctx, eco, def)
	if not _job.done:
		_job.step(budget)
		if _job.done:
			_job_res = _job.result()


func _place(ctx: AiContext, budget: AiBudget, eco: AiEconomy, def: int) -> void:
	var v: AiWorldView = ctx.view
	var tick: int = ctx.tick
	if _ready_def != def:
		_ready_def = def
		_ready_since = tick
		_place_tick = -1
		_no_site_since = -1
	if _place_tick >= 0:
		if tick - _place_tick < PLACE_LAG:
			return
		# still waiting to be placed: the sim did not take that cell
		if _place_cell.size() >= 2:
			eco.placer.blacklist(_place_cell[0], _place_cell[1], tick + AiPlacer.BL_TICKS)
		ctx.cmd.note_no_effect(AiTypes.Intent.BUILD_PLACE, def, tick)
		place_fails += 1
		_place_tick = -1
		_job = null
		_job_res = PackedInt32Array()
	if _job == null or _job_def != def:
		_start_job(ctx, eco, def)
	if not _job.done:
		_job.step(budget)
		if not _job.done:
			return
		_job_res = _job.result()
	if tick - _ready_since < ctx.diff.place_latency_ticks:
		return
	if _job_res.size() != 3:
		if _no_site_since < 0:
			_no_site_since = tick
		_job = null
		if tick - _no_site_since > NO_SITE_TICKS:
			if ctx.cmd.build_cancel():
				eco.cancels += 1
				eco.block_def(def, tick + AiPlacer.BL_TICKS)
				on_cancelled(ctx)
		return
	if not v.can_place(def, _job_res[0], _job_res[1], _job_res[2]):
		eco.placer.blacklist(_job_res[0], _job_res[1], tick + 60)
		_job = null
		_job_res = PackedInt32Array()
		return
	if ctx.cmd.build_place(def, _job_res[0], _job_res[1], _job_res[2]):
		_place_tick = tick
		_place_cell = _job_res.duplicate()
		placed += 1
		_job = null
		_job_res = PackedInt32Array()


# ------------------------------------------------------------------------------------------- conditions
func eval_cond(ctx: AiContext, c: Variant) -> bool:
	if c == null:
		return true
	if c is bool:
		return c
	if not (c is Dictionary):
		return true
	var d: Dictionary = c
	for key: String in d:
		if not _eval_key(ctx, key, d[key]):
			return false
	return true


func _eval_key(ctx: AiContext, key: String, arg: Variant) -> bool:
	var eco: AiEconomy = _hub.get_ref()
	var v: AiWorldView = ctx.view
	match key:
		"all":
			for c: Variant in arg:
				if not eval_cond(ctx, c):
					return false
			return true
		"any":
			for c2: Variant in arg:
				if eval_cond(ctx, c2):
					return true
			return false
		"not":
			return not eval_cond(ctx, arg)
		"t_ge_s":
			return ctx.tick >= int(arg) * SimConfig.TPS
		"t_lt_s":
			return ctx.tick < int(arg) * SimConfig.TPS
		"have":
			return _count_of(ctx, eco, arg as Dictionary, false) >= int((arg as Dictionary).get("n", 1))
		"have_lt":
			return _count_of(ctx, eco, arg as Dictionary, false) < int((arg as Dictionary).get("n", 1))
		"queued":
			return _count_of(ctx, eco, arg as Dictionary, true) >= int((arg as Dictionary).get("n", 1))
		"credits_ge":
			return v.credits() >= int(arg)
		"credits_lt":
			return v.credits() < int(arg)
		"income_ge":
			return ctx.kb.income_per_min >= int(arg)
		"power_margin_ge":
			return eco.margin >= int(arg)
		"power_margin_lt":
			return eco.margin + eco.pending_power < int(arg)
		"tier_ge":
			return tier(ctx) >= int(arg)
		"researched":
			var ri: int = ctx.view.game_data().research_idx(str(arg))
			return ri >= 0 and v.research_done(ri)
		"enemy_seen":
			return enemy_seen(ctx, AiDoctrine.cat_of(str(arg)))
		"enemy_share_ge":
			var cat: int = AiDoctrine.cat_of(str((arg as Dictionary).get("cat", "")))
			return cat >= 0 and _enemy_share(ctx, cat) >= int((arg as Dictionary).get("pct", 0))
		"army_value_ge":
			return eco.army_value >= int(arg)
		"army_units_ge":
			return eco.army_units >= int(arg)
		"phase_ge":
			return eco.comp.phase >= int(arg)
		"roster_has_role":
			var rb: int = AiTypes.role_bit(str(arg))
			return rb >= 0 and ctx.res.has_role(rb)
		"flag":
			var fb: int = AiTypes.doctrine_bit(str(arg))
			return fb >= 0 and ctx.pers.has_flag(fb)
		"under_attack":
			var hot: bool = false
			for p: int in ctx.kb.enemy_pids:
				if ctx.tick - ctx.kb.attacked_by_tick[p] < 60 * SimConfig.TPS:
					hot = true
			return hot == bool(arg)
		"dock_placeable":
			return eco.placer.dock_placeable(ctx) == bool(arg)
		"map_trait":
			var nm: String = str((arg as Dictionary).get("name", ""))
			var ge: int = int((arg as Dictionary).get("ge_pct", 0))
			match nm:
				"water":
					return eco.comp.water_pct >= ge
				"urban":
					return (100 if v.map_family() == AiTypes.MapFamily.URBAN else 0) >= ge
				"open":
					return (100 if v.map_family() == AiTypes.MapFamily.OPEN else 0) >= ge
			return false
	if not _warned.has(key):
		_warned[key] = true
		Log.warn("ai", "unknown condition key '%s'" % key)
	return true


## alive (or alive + queued when `with_queue`) count of a {struct | role | def} argument.
func _count_of(ctx: AiContext, eco: AiEconomy, a: Dictionary, queued_only: bool) -> int:
	if a.has("struct"):
		var def: int = ctx.res.structure_of_kind(AiDoctrine.struct_kind_of(str(a["struct"])))
		if def < 0:
			return 0
		return eco.struct_q[def] if queued_only else eco.struct_own[def]
	if a.has("role"):
		var rb: int = AiTypes.role_bit(str(a["role"]))
		if rb < 0:
			return 0
		var n: int = 0
		for d: int in ctx.res.units_of(rb):
			n += eco.unit_queued[d] + (0 if queued_only else eco.unit_alive[d])
		return n
	if a.has("def"):
		var ui: int = ctx.view.game_data().unit_idx(str(a["def"]))
		if ui < 0:
			return 0
		return eco.unit_queued[ui] + (0 if queued_only else eco.unit_alive[ui])
	return 0


## 1 = base, 2 = Radar active, 3 = Laboratory active (completed structures).
func tier(ctx: AiContext) -> int:
	var v: AiWorldView = ctx.view
	var lab: int = ctx.res.structure_of_kind(AiTypes.StructKind.LAB)
	if lab >= 0 and v.struct_count(lab) > 0:
		return 3
	var rad: int = ctx.res.structure_of_kind(AiTypes.StructKind.RADAR)
	if rad >= 0 and v.struct_count(rad) > 0:
		return 2
	return 1


func enemy_seen(ctx: AiContext, cat: int) -> bool:
	if cat < 0:
		return false
	for p: int in ctx.kb.enemy_pids:
		if ctx.kb.profiles[p].seen_value[cat] > 0:
			return true
	return false


func _enemy_share(ctx: AiContext, cat: int) -> int:
	var best: int = 0
	for p: int in ctx.kb.enemy_pids:
		var pr: AiEnemyProfile = ctx.kb.profiles[p]
		if pr.seen_value[cat] > 0:
			best = maxi(best, pr.share_q8[cat] * 100 / 256)
	return best


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([placed, place_fails, stalls, 1 if spine_done else 0])
	for s: Step in steps:
		v.append(s.state)
	return AiRng.hash_ints(v)
