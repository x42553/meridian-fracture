class_name AiKnowledge
extends RefCounted
## The blackboard (ai.md 2.3 / 3.5b): own and seen-enemy entity tables, structure ghosts, threat map, per-enemy composition
## profiles, resource sites, economy statistics and the primary-enemy choice. Modules read it through the query API and never
## touch each other's internals. AiEventIngest fills it; `step()` is the slot-1 upkeep (ghost validation, decay, site
## refresh, primary enemy) and is cursor based.

var own: AiEntityTable = AiEntityTable.new()
var enemy_units: AiEntityTable = AiEntityTable.new()
var ghosts: AiGhostTable = AiGhostTable.new()
var threat: AiThreatMap = AiThreatMap.new()
var profiles: Array[AiEnemyProfile] = []  ## by pid (8 slots)
var sites: AiResourceSites = AiResourceSites.new()
var route: AiRouteGraph = null  ## shared with the other AIs (AiSharedData)
var cluster: AiCluster = AiCluster.new()

## Derived records of the current think (ready alerts + state records), consumed by the modules in slot order.
var events: Array[PackedInt32Array] = []
var sweep_tick: int = -1  ## tick the last full enemy sweep completed
var now: int = 0  ## tick of the current think (set by the ingest and upkeep slots); the time base of the threat reads

# economy statistics (ai.md 4.2 AiEconomyStats, lean)
var income_ema_q8: int = 0  ## credits per second x 256
var income_per_min: int = 0
var last_income_total: int = 0
var last_income_tick: int = 0
var gained_window: int = 0
var collectors_alive: int = 0
var spent_total: int = 0

var camo: PackedInt32Array = PackedInt32Array([0, 0, AiTypes.NEVER])  ## latest camouflage alert [x, y, tick]
var attacked_by_tick: PackedInt32Array = PackedInt32Array()  ## by pid: tick an enemy of that player last hurt me
var enemy_starts: PackedInt32Array = PackedInt32Array()  ## [cx, cy] per enemy player (public)
var enemy_pids: PackedInt32Array = PackedInt32Array()
var primary: int = -1
var primary_since: int = AiTypes.NEVER
var ghost_cursor: int = 0
var ready: bool = false


func _init() -> void:
	for _p: int in 8:
		profiles.append(AiEnemyProfile.new())
	attacked_by_tick.resize(8)
	attacked_by_tick.fill(AiTypes.NEVER)


## Builds the static parts from the bound view: threat grid, presumed HQ ghosts of every enemy start, resource sites.
func setup(ctx: AiContext) -> void:
	var v: AiWorldView = ctx.view
	route = ctx.shared.route_graph(v).fork()
	route.threat = threat
	threat.setup(v.map_w(), v.map_h(), ctx.store.tune("threat.block_shift", 13), ctx.store.tune("threat.decay_ticks", 600))
	ghosts.conf_floor = ctx.store.tune("ingest.ghost_conf_floor", 30)
	ghosts.decay_ticks = maxi(1, ctx.store.tune("ingest.ghost_decay_ticks", 20))
	enemy_starts.resize(0)
	enemy_pids.resize(0)
	for p: int in v.player_slots():
		if not v.is_enemy(p):
			continue
		enemy_pids.append(p)
		var cx: int = v.start_cell_x(p)
		var cy: int = v.start_cell_y(p)
		enemy_starts.append(cx)
		enemy_starts.append(cy)
		var rost: AiRoleResolver = ctx.shared.resolver(v.roster_of(p))
		var hq: int = v.roster(p).hq_idx
		var hq_cost: int = v.structure_def(hq, p).cost if v.structure_def(hq, p) != null else 0
		if cx >= 0:
			ghosts.seed_presumed_hq(p, hq, cx * Fp.CELL + Fp.CELL / 2, cy * Fp.CELL + Fp.CELL / 2, v.tick(), hq_cost)
		profiles[p].set_prior(_prior_of(ctx, rost))
	sites.setup(v, enemy_starts)
	last_income_total = v.income_total()
	last_income_tick = v.tick()
	ready = true


## Flat prior over the categories the roster can field (a roster with no air gets no air share): sums to 256.
func _prior_of(ctx: AiContext, rost: AiRoleResolver) -> PackedInt32Array:
	var pri: PackedInt32Array = PackedInt32Array()
	pri.resize(AiTypes.Cat.COUNT)
	var w: PackedInt32Array = PackedInt32Array()
	w.resize(AiTypes.Cat.COUNT)
	if rost.has_role(AiTypes.R_FIGHTER) or rost.has_role(AiTypes.R_BOMBER):
		w[AiTypes.Cat.AIR] = 15
	w[AiTypes.Cat.ARMOR] = 35
	w[AiTypes.Cat.INFANTRY] = 25
	w[AiTypes.Cat.ARTILLERY] = 10 if rost.has_role(AiTypes.R_ARTILLERY) else 0
	w[AiTypes.Cat.NAVAL] = 5 if rost.has_role(AiTypes.R_ESCORT_SHIP) or rost.has_role(AiTypes.R_SIEGE_SHIP) else 0
	w[AiTypes.Cat.LIGHT] = 10
	var total: int = 0
	for x: int in w:
		total += x
	for c: int in AiTypes.Cat.COUNT:
		pri[c] = w[c] * 256 / maxi(total, 1)
	if ctx.diff.enemy_prior == 0:
		pri.fill(0)
	elif ctx.diff.enemy_prior == 1:
		for c2: int in AiTypes.Cat.COUNT:
			if c2 != AiTypes.Cat.AIR:
				pri[c2] = 0
	return pri


# ------------------------------------------------------------------------------------------------ queries
func threat_at(x: int, y: int) -> int:
	return threat.at(x, y, now)


func threat_circle(x: int, y: int, r: int) -> int:
	return threat.circle(x, y, r, now)


## Rows of `enemy_units` within r of (x, y), ascending eid.
func enemies_near(x: int, y: int, r: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var r2: int = r * r
	var t: AiEntityTable = enemy_units
	for i: int in t.count:
		var dx: int = t.x[i] - x
		var dy: int = t.y[i] - y
		if dx * dx + dy * dy <= r2:
			out.append(i)
	for i2: int in range(1, out.size()):
		var v: int = out[i2]
		var j: int = i2 - 1
		while j >= 0 and t.eid[out[j]] > t.eid[v]:
			out[j + 1] = out[j]
			j -= 1
		out[j + 1] = v
	return out.size()


func ghosts_near(x: int, y: int, r: int, kind_mask: int, out: PackedInt32Array) -> int:
	return ghosts.near(x, y, r, kind_mask, out)


## Known army value of one enemy (seen units at their unit cost).
func est_enemy_army_value(pid: int) -> int:
	return enemy_units.value_of(pid)


func est_enemy_total_value(pid: int) -> int:
	return enemy_units.value_of(pid) + ghosts.value_of_owner(pid)


func primary_enemy() -> int:
	return primary


## Fills [x, y, tick] of the latest camouflage alert; false if none.
func camo_alert(out: PackedInt32Array) -> bool:
	out.resize(3)
	out[0] = camo[0]
	out[1] = camo[1]
	out[2] = camo[2]
	return camo[2] > AiTypes.NEVER


## Last known HQ position of an enemy (real or presumed ghost); false when unknown.
func enemy_hq(pid: int, out: PackedInt32Array) -> bool:
	var best: int = -1
	for r: int in ghosts.count:
		if ghosts.owner[r] == pid and ghosts.kind[r] == AiTypes.StructKind.HQ:
			if best < 0 or ghosts.conf[r] > ghosts.conf[best]:
				best = r
	if best < 0:
		return false
	out.resize(2)
	out[0] = ghosts.x[best]
	out[1] = ghosts.y[best]
	return true


func note_hostile(pid: int, tick: int) -> void:
	if pid >= 0 and pid < 8:
		attacked_by_tick[pid] = tick


# ------------------------------------------------------------------------------------------------ economy
## Folds the monotonic income counter into the EMA (credits per second x 256), once per >= 20 ticks.
func update_income(income_total: int, tick: int) -> void:
	var elapsed: int = tick - last_income_tick
	if elapsed < 20:
		return
	var gained: int = income_total - last_income_total
	var sample: int = gained * 20 * 256 / elapsed
	income_ema_q8 += (sample - income_ema_q8) / 4
	income_per_min = income_ema_q8 * 60 >> 8
	gained_window = gained
	last_income_total = income_total
	last_income_tick = tick


# ----------------------------------------------------------------------------------------- slot 1: upkeep
## Ghost validation (cursor), confidence / profile decay, resource-site refresh and the primary-enemy choice.
func step(ctx: AiContext, budget: AiBudget) -> void:
	if not ready:
		return
	var v: AiWorldView = ctx.view
	now = ctx.tick
	route.tick_hint = ctx.tick
	var kb_brain: AiBrain = ctx.brain as AiBrain
	route.avoid_zones = kb_brain.powers.dispersal.avoid if kb_brain != null else PackedInt32Array()
	ghosts.decay(ctx.tick)
	var n: int = ghosts.count
	var checked: int = 0
	while checked < n and budget.spend(2):
		if ghost_cursor >= ghosts.count:
			ghost_cursor = 0
			break
		var r: int = ghost_cursor
		ghost_cursor += 1
		checked += 1
		# a ghost whose cell is visible while the structure is not there any more (real ids only) is gone
		if ghosts.eid[r] > 0:
			var cx: int = ghosts.x[r] >> Fp.CELL_SHIFT
			var cy: int = ghosts.y[r] >> Fp.CELL_SHIFT
			if ghosts.last_seen[r] < ctx.tick and v.cell_visible(cx, cy) and not v.alive(ghosts.eid[r]):
				ghosts.remove(ghosts.eid[r])
				ghost_cursor = maxi(0, ghost_cursor - 1)
				n = ghosts.count
	for p: int in enemy_pids:
		profiles[p].decay(ctx.tick)
	if budget.spend(4):
		sites.refresh_step(v, self, route)
	if ctx.tick - primary_since >= 40 and budget.spend(6 + enemy_pids.size() * 2):
		update_primary(ctx)


# -------------------------------------------------------------------------------- primary enemy (ai.md 5.3.6)
func update_primary(ctx: AiContext) -> void:
	var v: AiWorldView = ctx.view
	var cand: PackedInt32Array = PackedInt32Array()
	for p: int in enemy_pids:
		if v.player_alive(p):
			cand.append(p)
	if cand.is_empty():
		primary = -1
		return
	if cand.size() == 1:
		primary = cand[0]
		return
	var mine_x: int = v.start_cell_x(v.me()) * Fp.CELL
	var mine_y: int = v.start_cell_y(v.me()) * Fp.CELL
	var est_max: int = 1
	var est: PackedInt32Array = PackedInt32Array()
	for p2: int in cand:
		var e: int = est_enemy_total_value(p2)
		est.append(e)
		est_max = maxi(est_max, e)
	var best: int = -1
	var best_s: int = -1
	var cur_s: int = -1
	var hq: PackedInt32Array = PackedInt32Array()
	for i: int in cand.size():
		var p3: int = cand[i]
		var d_c: int = 256
		if enemy_hq(p3, hq):
			d_c = Fp.dist(hq[0] - mine_x, hq[1] - mine_y) / Fp.CELL
		var prox: int = 100 * 256 / (256 + d_c)
		var weak: int = 100 - 100 * est[i] / est_max
		var host: int = 0
		var since: int = ctx.tick - attacked_by_tick[p3]
		if since < 300 * SimConfig.TPS:
			host = 100 - 100 * since / (300 * SimConfig.TPS)
		var swt: int = 0
		for r: int in ghosts.count:
			if ghosts.owner[r] == p3 and ghosts.kind[r] == AiTypes.StructKind.SUPERWEAPON:
				swt = 100
				break
		var s: int = (40 * prox + 30 * weak + 20 * host + 10 * swt) / 100
		if s > best_s:  # ties: lowest pid (cand ascending)
			best_s = s
			best = p3
		if p3 == primary:
			cur_s = s
	var keep: bool = primary >= 0 and cand.has(primary) and ctx.tick - primary_since < 3600 and best_s <= cur_s + 25
	if not keep:
		primary = best
		primary_since = ctx.tick


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([own.state_hash(), enemy_units.state_hash(), ghosts.state_hash(), threat.state_hash(),
		sites.state_hash(), primary, income_per_min])
	return AiRng.hash_ints(v)
