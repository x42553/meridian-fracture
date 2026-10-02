class_name AiDispersal
extends RefCounted
## Reaction to the strategic warning zones of enemy superweapons (ai.md 5.13.3), scheduler slot 3 (every 2 ticks) plus `enforce`
## from AiPowers.step (slot 12, after the ops). The warning list comes from AiWorldView.strategic_warnings (the zones cannot be
## hidden). After the difficulty's reaction delay every mobile unit of mine inside the footprint (+ 2-cell margin) whose squad is
## eligible (`squad.id % 100 < dodge_pct`: Easy 0 %, Medium 50 %, Hard / Brutal 100 %) gets a class-0 `move` to the nearest passable
## cell outside the footprint (+ 3 cells) that it can reach in `time_left - max(20, dt + exec_lag)` ticks; the destinations are
## bucketed into <= 8 groups (one command each; the sim spreads a group around its point). Units that cannot escape move towards
## the nearest edge anyway. Structures cannot move.
##
## Weapon specifics: Aurora (vehicles and aircraft leave, infantry holds and counter-attacks at impact + 20 on Hard+, a trapped
## group of >= 6 vehicles is reported to AiPowers for Redundant Orders), Tempest (AA ring at 7-10 cells), Dragonfall (AT / tanks
## pre-position and attack the capsules, the rest keeps r + 4), Horizon (slow_debris and no_build avoid zones for 29 s), Trident
## (no_fire_artillery avoid zone for the dome life). The avoid zones are queried through `avoided`.

const AV_DEBRIS: int = 1
const AV_NO_BUILD: int = 2
const AV_NO_FIRE_ARTY: int = 3
const AV_DANGER: int = 4

const DANGER_MARGIN: int = 2 * Fp.CELL
const DEST_MARGIN: int = 3 * Fp.CELL
const MAX_GROUPS: int = 8
const BUCKET: int = 3 * Fp.CELL
const RING_STEPS: int = 18
const DIRS: int = 16
const ENFORCE_MIN: int = 10  ## ticks between two enforcement passes


## One live warning as I know it.
class Zone extends RefCounted:
	var owner: int = 0
	var sw: int = 0
	var kind: int = 0
	var x: int = 0
	var y: int = 0
	var angle: int = 0
	var start: int = 0
	var impact: int = 0
	var first_seen: int = 0
	var until: int = 0
	var extra: int = 0  ## additional keep-out beyond the edge for non-specialists (Dragonfall r + 4)
	var circles: PackedInt32Array = PackedInt32Array()  ## local dx, dy, r per part
	var wc: PackedInt32Array = PackedInt32Array()  ## world x, y, r per circle (rotated once at creation)
	var half_len: int = 0  ## Helios rectangle (0 = none)
	var half_w: int = 0
	var reacted: bool = false
	var post_done: bool = false
	var counter_done: bool = false
	var ring_done: bool = false


var zones: Array[Zone] = []
var avoid: PackedInt32Array = PackedInt32Array()  ## kind, x, y, r, until per row
var dodge_eid: PackedInt32Array = PackedInt32Array()
var dodge_x: PackedInt32Array = PackedInt32Array()
var dodge_y: PackedInt32Array = PackedInt32Array()
var dodge_until: PackedInt32Array = PackedInt32Array()
var trapped: PackedInt32Array = PackedInt32Array()  ## x, y, n, impact of the Aurora zone with my stuck vehicles
var zones_seen: int = 0
var units_ordered: int = 0
var orders_issued: int = 0
var units_in_footprint: int = 0
var counter_attacks: int = 0
var ring_orders: int = 0
var snipes: int = 0
var first_order_lag: int = AiTypes.NEVER  ## ticks between the first sighting of a warning and its first move command
var perf: AiPerf = AiPerf.new()
var _tmp: PackedInt32Array = PackedInt32Array()
var _known: Dictionary = {}
var _last_enforce: int = AiTypes.NEVER
var _ctx: AiContext = null


func setup(ctx: AiContext) -> void:
	_ctx = ctx


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([zones.size(), zones_seen, units_ordered, orders_issued, avoid.size(), dodge_eid.size(),
		counter_attacks, ring_orders]))


# ------------------------------------------------------------------------------------------------------- queries
## True when (x, y) lies inside an avoid zone of `kind` (or of any kind when kind == 0) at `tick`.
func avoided(x: int, y: int, kind: int, tick: int) -> bool:
	for i: int in avoid.size() / 5:
		if avoid[5 * i + 4] <= tick or (kind != 0 and avoid[5 * i] != kind):
			continue
		var dx: int = avoid[5 * i + 1] - x
		var dy: int = avoid[5 * i + 2] - y
		var r: int = avoid[5 * i + 3]
		if dx * dx + dy * dy <= r * r:
			return true
	return false


func active_zone_count(tick: int) -> int:
	var n: int = 0
	for z: Zone in zones:
		if tick <= z.until:
			n += 1
	return n


## True when the point is inside the footprint of zone z grown by `margin` units.
func inside(z: Zone, x: int, y: int, margin: int) -> bool:
	return _dist_outside(z, x, y) < margin


## Distance (units) from the point to the footprint edge; <= 0 inside... expressed as a non-negative "excess" (0 inside).
func _dist_outside(z: Zone, x: int, y: int) -> int:
	var best: int = 1 << 40
	for i: int in z.wc.size() / 3:
		var d: int = maxi(Fp.dist(x - z.wc[3 * i], y - z.wc[3 * i + 1]) - z.wc[3 * i + 2], 0)
		if d < best:
			best = d
	if z.half_len > 0:
		var inv: int = (Fp.TURN - z.angle) & Fp.ANGLE_MASK
		var u: int = Fp.rot_x(x - z.x, y - z.y, inv)
		var w: int = Fp.rot_y(x - z.x, y - z.y, inv)
		var du: int = maxi(absi(u) - z.half_len, 0)
		var dw: int = maxi(absi(w) - z.half_w, 0)
		best = mini(best, Fp.dist(du, dw))
	return best


# ----------------------------------------------------------------------------------------------------------- step
func step(ctx: AiContext, budget: AiBudget) -> void:
	_ctx = ctx
	perf.enabled = ctx.cfg.perf
	perf.begin()
	_step(ctx, budget)
	perf.end()


func _step(ctx: AiContext, budget: AiBudget) -> void:
	if not budget.spend(1):
		return
	_ingest(ctx)
	_expire(ctx.tick)
	trapped.resize(0)
	for z: Zone in zones:
		if ctx.tick > z.until:
			continue
		if not z.reacted and ctx.tick >= z.first_seen + ctx.diff.reaction_delay_ticks:
			if not budget.spend(4):
				return
			_react(ctx, z, budget)
		if z.reacted:
			_post(ctx, z, budget)


func _ingest(ctx: AiContext) -> void:
	var n: int = ctx.view.strategic_warnings(_tmp)
	for i: int in n / 7:
		var key: int = AiCommandBuilder.key2(_tmp[7 * i + 1] * 64 + _tmp[7 * i], _tmp[7 * i + 5])
		if _known.has(key):
			continue
		_known[key] = true
		var z: Zone = _make_zone(ctx, _tmp[7 * i], _tmp[7 * i + 1], _tmp[7 * i + 2], _tmp[7 * i + 3], _tmp[7 * i + 4], _tmp[7 * i + 5], _tmp[7 * i + 6])
		if z == null:
			continue
		z.first_seen = ctx.tick
		zones.append(z)
		zones_seen += 1
		ctx.telemetry.emit(AiTypes.Tele.DISPERSAL, z.sw, z.impact - ctx.tick, ctx.tick)
		_register_avoid(ctx, z)


func _make_zone(ctx: AiContext, owner: int, sw: int, x: int, y: int, angle: int, start: int, impact: int) -> Zone:
	var data: GameData = ctx.view.game_data()
	if sw < 0 or sw >= data.superweapons.size():
		return null
	var d: DefSuperweapon = data.superweapons[sw]
	var z: Zone = Zone.new()
	z.owner = owner
	z.sw = sw
	z.kind = d.action_kind
	z.x = x
	z.y = y
	z.angle = angle
	z.start = start
	z.impact = impact
	z.until = impact + _span(d) + 40
	match d.action_kind:
		DefEnums.SwAction.KINETIC_VOLLEY, DefEnums.SwAction.RAIL_STRIKE:
			for pk: DefImpactPacket in d.packets:
				z.circles.append(pk.offset_x)
				z.circles.append(pk.offset_y)
				z.circles.append(pk.radius)
		DefEnums.SwAction.BUNKER_BUSTER:
			var r: int = 0
			for pk2: DefImpactPacket in d.packets:
				r = maxi(r, pk2.radius)
			z.circles.append_array(PackedInt32Array([0, 0, r]))
		DefEnums.SwAction.BEAM_SWEEP:
			z.half_len = int(d.params.get("line_len_u", 16384)) / 2
			z.half_w = int(d.params.get("width_u", 3072)) / 2
		_:
			z.circles.append_array(PackedInt32Array([0, 0, d.radius]))
	if d.action_kind == DefEnums.SwAction.ENGINE_DROP:
		z.extra = 4 * Fp.CELL
	for i: int in z.circles.size() / 3:
		z.wc.append(x + Fp.rot_x(z.circles[3 * i], z.circles[3 * i + 1], angle))
		z.wc.append(y + Fp.rot_y(z.circles[3 * i], z.circles[3 * i + 1], angle))
		z.wc.append(z.circles[3 * i + 2])
	return z


## Ticks between the start of the execution and its last effect (mirrors the sim's exec span; data-derived).
static func _span(d: DefSuperweapon) -> int:
	match d.action_kind:
		DefEnums.SwAction.KINETIC_VOLLEY, DefEnums.SwAction.RAIL_STRIKE, DefEnums.SwAction.BUNKER_BUSTER:
			var m: int = 0
			for pk: DefImpactPacket in d.packets:
				m = maxi(m, pk.delay_t)
			return m
		DefEnums.SwAction.BEAM_SWEEP:
			return int(d.params.get("traverse_t", 240))
		DefEnums.SwAction.DRONE_SWARM:
			return 1200
		DefEnums.SwAction.ENGINE_DROP:
			return int(d.params.get("unfold_t", 100)) + 1200
		DefEnums.SwAction.INTERCEPT_ZONE:
			return d.duration_t
	return 0


func _register_avoid(ctx: AiContext, z: Zone) -> void:
	var r: int = 0
	for i: int in z.circles.size() / 3:
		r = maxi(r, Fp.dist(z.circles[3 * i], z.circles[3 * i + 1]) + z.circles[3 * i + 2])
	if z.half_len > 0:
		r = maxi(r, z.half_len + z.half_w)
	match z.kind:
		DefEnums.SwAction.RAIL_STRIKE:
			var until: int = z.impact + 580  # 29 s of debris after the first impact
			add_avoid(AV_DEBRIS, z.x, z.y, r + Fp.CELL, until)
			add_avoid(AV_NO_BUILD, z.x, z.y, r + Fp.CELL, until)
		DefEnums.SwAction.INTERCEPT_ZONE:
			add_avoid(AV_NO_FIRE_ARTY, z.x, z.y, r, z.impact + 500)
		DefEnums.SwAction.ENGINE_DROP:
			add_avoid(AV_DANGER, z.x, z.y, r + z.extra, z.impact + 1300)
		_:
			add_avoid(AV_DANGER, z.x, z.y, r + Fp.CELL, z.impact + 60)


func add_avoid(kind: int, x: int, y: int, r: int, until: int) -> void:
	avoid.append_array(PackedInt32Array([kind, x, y, r, until]))
	if avoid.size() > 5 * 32:
		avoid = avoid.slice(5 * 8)


func _expire(tick: int) -> void:
	var i: int = 0
	while i < zones.size():
		if tick > zones[i].until + 200:
			zones.remove_at(i)
		else:
			i += 1
	var keep: PackedInt32Array = PackedInt32Array()
	for j: int in avoid.size() / 5:
		if avoid[5 * j + 4] > tick:
			keep.append_array(avoid.slice(5 * j, 5 * j + 5))
	avoid = keep
	var k: int = dodge_eid.size() - 1
	while k >= 0:
		if dodge_until[k] <= tick:
			dodge_eid.remove_at(k)
			dodge_x.remove_at(k)
			dodge_y.remove_at(k)
			dodge_until.remove_at(k)
		k -= 1


# ---------------------------------------------------------------------------------------------------------- reaction
func _eligible(ctx: AiContext, r: int) -> bool:
	var t: AiEntityTable = ctx.kb.own
	var sid: int = t.squad[r]
	var key: int = sid if sid >= 0 else t.eid[r]
	return key % 100 < ctx.diff.dodge_pct


## Rows of my mobile entities inside the danger footprint of z (unit kind, not loaded).
func _movers(ctx: AiContext, z: Zone) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var t: AiEntityTable = ctx.kb.own
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or t.hp[r] <= 0 or (t.flags[r] & AiTypes.EF_LOADED) != 0:
			continue
		var prof: AiUnitProfile = ctx.unit_profile(t.def[r])
		if prof == null or prof.speed <= 0:
			continue
		if not _affected(ctx, z, prof, t.role_mask[r]):
			continue
		var margin: int = DANGER_MARGIN + (z.extra if not _is_specialist(z, t.role_mask[r]) else 0)
		if inside(z, t.x[r], t.y[r], margin + 1):
			out.append(r)
	return out


## Aircraft ignore the ground weapons; Aurora spares the infantry; Tempest and Dragonfall footprints are avoided by ground units.
func _affected(_ctx: AiContext, z: Zone, prof: AiUnitProfile, role_mask: int) -> bool:
	var air: bool = prof.move_class == AiTypes.MoveClass.AIR
	match z.kind:
		DefEnums.SwAction.EMP_BURST:
			return prof.move_class != AiTypes.MoveClass.FOOT
		DefEnums.SwAction.INTERCEPT_ZONE:
			return false
		DefEnums.SwAction.DRONE_SWARM:
			return not air and (role_mask & (1 << AiTypes.R_AA_MOBILE)) == 0
		DefEnums.SwAction.ENGINE_DROP:
			return not air and not _is_specialist(z, role_mask)
	return not air


func _is_specialist(z: Zone, role_mask: int) -> bool:
	if z.kind == DefEnums.SwAction.ENGINE_DROP:
		return (role_mask & ((1 << AiTypes.R_INFANTRY_AT) | (1 << AiTypes.R_TANK_MAIN) | (1 << AiTypes.R_HEAVY))) != 0
	return false


func _react(ctx: AiContext, z: Zone, budget: AiBudget) -> void:
	z.reacted = true
	var rows: PackedInt32Array = _movers(ctx, z)
	units_in_footprint += rows.size()
	if z.kind == DefEnums.SwAction.EMP_BURST:
		_aurora_trap(ctx, z, rows)
	if rows.is_empty() and z.kind != DefEnums.SwAction.DRONE_SWARM and z.kind != DefEnums.SwAction.ENGINE_DROP:
		return
	var t: AiEntityTable = ctx.kb.own
	budget.spend(1 + rows.size() / 3)
	var dests: PackedInt32Array = PackedInt32Array()  ## x, y per accepted row
	var used: PackedInt32Array = PackedInt32Array()
	var taken: PackedInt32Array = PackedInt32Array()  ## destinations already chosen (spread)
	var left: int = z.impact - ctx.tick
	var lag: int = maxi(20, ctx.dt + ctx.cmd.exec_lag_est)
	for r: int in rows:
		if not _eligible(ctx, r):
			continue
		var d: PackedInt32Array = _escape(ctx, z, r, left - lag, taken)
		if d.is_empty():
			continue
		used.append(r)
		dests.append(d[0])
		dests.append(d[1])
		taken.append(d[0])
		taken.append(d[1])
	_issue_groups(ctx, z, used, dests)
	if ctx.cfg.level >= AiTypes.Difficulty.BRUTAL:
		_snipe(ctx, z)
	if z.kind == DefEnums.SwAction.DRONE_SWARM:
		_tempest_ring(ctx, z)
	elif z.kind == DefEnums.SwAction.ENGINE_DROP:
		_dragonfall_stage(ctx, z)


## Nearest passable, threat-free cell outside the footprint (+ margin) that unit row r reaches in `budget_ticks`; when none is
## reachable, the point along the shortest escape direction the unit can still get to. Empty when there is no cell at all.
func _escape(ctx: AiContext, z: Zone, r: int, budget_ticks: int, taken: PackedInt32Array) -> PackedInt32Array:
	var t: AiEntityTable = ctx.kb.own
	var prof: AiUnitProfile = ctx.unit_profile(t.def[r])
	var ux: int = t.x[r]
	var uy: int = t.y[r]
	var reach: int = maxi(prof.speed * maxi(budget_ticks, 0), Fp.CELL)
	var out_dir: int = _outward_dir(z, ux, uy)
	var mc: int = prof.move_class
	var margin: int = DEST_MARGIN + (z.extra if not _is_specialist(z, t.role_mask[r]) else 0)
	var fallback: PackedInt32Array = PackedInt32Array()
	var mw: int = ctx.view.map_w()
	var mh: int = ctx.view.map_h()
	# moving k cells gains at most k cells of clearance: rings below the missing clearance cannot succeed
	var k0: int = clampi((margin - _dist_outside(z, ux, uy)) / Fp.CELL, 1, RING_STEPS)
	for k: int in range(k0, RING_STEPS + 1):
		var dist: int = k * Fp.CELL
		for j: int in DIRS:
			# 0, +1, -1, +2, -2 ... around the outward direction
			var off: int = (j + 1) / 2 if j % 2 == 1 else -(j / 2)
			var a: int = (out_dir + off * (Fp.TURN / DIRS)) & Fp.ANGLE_MASK
			var px: int = ux + Fp.step_x(a, dist)
			var py: int = uy + Fp.step_y(a, dist)
			var cx: int = px >> Fp.CELL_SHIFT
			var cy: int = py >> Fp.CELL_SHIFT
			if px < 0 or py < 0 or cx >= mw or cy >= mh or not ctx.view.passable(cx, cy, mc):
				continue
			if _dist_outside(z, px, py) < margin or _crowded(taken, px, py):
				continue
			if not _clear_of_others(ctx, z, px, py, margin):
				continue
			if ctx.kb.threat_at(px, py) > 0 and k < RING_STEPS - 4 and ctx.kb.threat_circle(px, py, 4 * Fp.CELL) > 400:
				continue
			if dist <= reach:
				return PackedInt32Array([px, py])
			if fallback.is_empty():
				fallback = PackedInt32Array([ux + Fp.step_x(a, reach), uy + Fp.step_y(a, reach)])
	return fallback


func _crowded(taken: PackedInt32Array, x: int, y: int) -> bool:
	for i: int in taken.size() / 2:
		var dx: int = taken[2 * i] - x
		var dy: int = taken[2 * i + 1] - y
		if dx * dx + dy * dy < Fp.CELL * Fp.CELL * 2:
			return true
	return false


func _clear_of_others(ctx: AiContext, z: Zone, x: int, y: int, margin: int) -> bool:
	for o: Zone in zones:
		if o != z and ctx.tick <= o.until and _dist_outside(o, x, y) < margin:
			return false
	return true


## Direction (binary angle) pointing away from the footprint at (x, y): from the nearest shape centre / axis point.
func _outward_dir(z: Zone, x: int, y: int) -> int:
	var best_d: int = 1 << 40
	var bx: int = z.x
	var by: int = z.y
	for i: int in z.circles.size() / 3:
		var px: int = z.x + Fp.rot_x(z.circles[3 * i], z.circles[3 * i + 1], z.angle)
		var py: int = z.y + Fp.rot_y(z.circles[3 * i], z.circles[3 * i + 1], z.angle)
		var d: int = Fp.dist(x - px, y - py)
		if d < best_d:
			best_d = d
			bx = px
			by = py
	if z.half_len > 0:
		# perpendicular to the axis, on the unit's side
		var inv: int = (Fp.TURN - z.angle) & Fp.ANGLE_MASK
		var w: int = Fp.rot_y(x - z.x, y - z.y, inv)
		var side: int = 1 if w >= 0 else -1
		return (z.angle + side * Fp.ANGLE_QUARTER) & Fp.ANGLE_MASK
	if x == bx and y == by:
		return (z.angle + Fp.ANGLE_QUARTER) & Fp.ANGLE_MASK
	return Fp.atan2(y - by, x - bx) & Fp.ANGLE_MASK


## Buckets the destinations into <= MAX_GROUPS points and sends one move command per group (class 0).
func _issue_groups(ctx: AiContext, z: Zone, rows: PackedInt32Array, dests: PackedInt32Array) -> void:
	if rows.is_empty():
		return
	var t: AiEntityTable = ctx.kb.own
	var keys: PackedInt32Array = PackedInt32Array()
	var gx: PackedInt32Array = PackedInt32Array()
	var gy: PackedInt32Array = PackedInt32Array()
	var members: Array[PackedInt32Array] = []
	for i: int in rows.size():
		var key: int = (dests[2 * i + 1] / BUCKET) * 4096 + dests[2 * i] / BUCKET
		var gi: int = keys.find(key)
		if gi < 0:
			gi = keys.size()
			keys.append(key)
			gx.append(dests[2 * i])
			gy.append(dests[2 * i + 1])
			members.append(PackedInt32Array())
		members[gi].append(t.eid[rows[i]])
	# merge the smallest groups into the nearest larger one
	while members.size() > MAX_GROUPS:
		var small: int = 0
		for g: int in members.size():
			if members[g].size() < members[small].size():
				small = g
		var near: int = -1
		var nd: int = 1 << 40
		for g2: int in members.size():
			if g2 == small:
				continue
			var d: int = Fp.dist(gx[g2] - gx[small], gy[g2] - gy[small])
			if d < nd:
				nd = d
				near = g2
		members[near].append_array(members[small])
		members.remove_at(small)
		keys.remove_at(small)
		gx.remove_at(small)
		gy.remove_at(small)
	for g3: int in members.size():
		if ctx.cmd.move(members[g3], gx[g3], gy[g3], false, 0):
			orders_issued += 1
			units_ordered += members[g3].size()
			if first_order_lag == AiTypes.NEVER:
				first_order_lag = ctx.tick - z.first_seen
		var b: AiBrain = ctx.brain as AiBrain
		if b != null:
			b.lease_units(members[g3], z.until if z.kind == DefEnums.SwAction.DRONE_SWARM or z.kind == DefEnums.SwAction.ENGINE_DROP \
					else mini(z.until, z.impact + 60))
		for eid: int in members[g3]:
			var di: int = dodge_eid.find(eid)
			if di >= 0:
				dodge_x[di] = gx[g3]
				dodge_y[di] = gy[g3]
				dodge_until[di] = z.until
			else:
				dodge_eid.append(eid)
				dodge_x.append(gx[g3])
				dodge_y.append(gy[g3])
				dodge_until.append(z.until)


## Launcher snipe (Brutal only, 5.13.3): a bomber flight that reaches the enemy launcher and kills it before the warning ends
## (destroying the launcher during the warning cancels the attack) when the AA around the launcher is weak.
func _snipe(ctx: AiContext, z: Zone) -> void:
	var gt: AiGhostTable = ctx.kb.ghosts
	var g: int = -1
	for j: int in gt.count:
		if gt.owner[j] == z.owner and gt.kind[j] == AiTypes.StructKind.SUPERWEAPON and gt.eid[j] >= 0:
			g = j
			break
	if g < 0:
		return
	var sp: AiUnitProfile = ctx.struct_profile_of(z.owner, gt.def[g])
	if sp == null:
		return
	var aa_dps: int = 0
	for k: int in gt.count:
		if gt.owner[k] == z.owner and AiForce.is_defense_kind(gt.kind[k]) and AiForce.dist(gt.x[k], gt.y[k], gt.x[g], gt.y[g]) <= 12 * Fp.CELL:
			var dp: AiUnitProfile = ctx.struct_profile_of(z.owner, gt.def[k])
			if dp != null and (dp.hits_mask & 2) != 0:
				aa_dps += dp.dps_avg_x100() / 100
	if aa_dps > 120:
		return
	var t: AiEntityTable = ctx.kb.own
	var left: int = z.impact - ctx.tick
	var ids: PackedInt32Array = PackedInt32Array()
	var dps: int = 0
	var slowest: int = 1 << 30
	var far: int = 0
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or t.hp[r] <= 0 or (t.role_mask[r] & (1 << AiTypes.R_BOMBER)) == 0:
			continue
		var prof: AiUnitProfile = ctx.unit_profile(t.def[r])
		if prof == null or prof.speed <= 0 or (prof.hits_mask & 1) == 0:
			continue
		ids.append(t.eid[r])
		dps += prof.dps_avg_x100() / 100
		slowest = mini(slowest, prof.speed)
		far = maxi(far, AiForce.dist(t.x[r], t.y[r], gt.x[g], gt.y[g]))
	if ids.is_empty() or dps <= 0:
		return
	var eta: int = far / slowest
	var hp: int = maxi(sp.hp * gt.hp_pct[g] / 100, 1)
	var ttk: int = hp * SimConfig.TPS / dps
	if eta + ttk > left - 40:
		return
	if ctx.cmd.attack_move(ids, gt.x[g], gt.y[g], false, 0):
		snipes += 1
		var b: AiBrain = ctx.brain as AiBrain
		if b != null:
			b.lease_units(ids, z.impact + 40)


## Aurora: vehicles that cannot leave r + margin in time are reported (Redundant Orders at impact - 30).
func _aurora_trap(ctx: AiContext, z: Zone, rows: PackedInt32Array) -> void:
	var t: AiEntityTable = ctx.kb.own
	var left: int = z.impact - ctx.tick
	var n: int = 0
	for r: int in rows:
		var prof: AiUnitProfile = ctx.unit_profile(t.def[r])
		if prof.move_class == AiTypes.MoveClass.AIR or (prof.role_mask & (1 << AiTypes.R_COMBAT)) == 0:
			continue
		var d: int = _dist_outside(z, t.x[r], t.y[r])
		var need: int = DEST_MARGIN + Fp.CELL  # roughly the distance to the edge from inside
		var edge: int = 0
		for i: int in z.circles.size() / 3:
			edge = maxi(edge, z.circles[3 * i + 2])
		var to_go: int = Fp.dist(t.x[r] - z.x, t.y[r] - z.y) - edge + need if d == 0 else need - d
		if prof.speed * maxi(left - 20, 0) < to_go:
			n += 1
	if n >= 1:
		trapped = PackedInt32Array([z.x, z.y, n, z.impact])


# ------------------------------------------------------------------------------------------------ post-warning actions
func _post(ctx: AiContext, z: Zone, budget: AiBudget) -> void:
	if z.kind == DefEnums.SwAction.EMP_BURST:
		_aurora_trap_refresh(ctx, z)
		if not z.counter_done and ctx.tick >= z.impact + 20 and ctx.cfg.level >= AiTypes.Difficulty.HARD:
			z.counter_done = true
			_aurora_counter(ctx, z, budget)
	elif z.kind == DefEnums.SwAction.ENGINE_DROP:
		if not z.post_done and ctx.tick >= z.impact + 5:
			z.post_done = true
			_dragonfall_attack(ctx, z)
	elif z.kind == DefEnums.SwAction.DRONE_SWARM:
		if not z.post_done and ctx.tick >= z.impact + 20:
			z.post_done = true
			_tempest_fighters(ctx, z)


func _aurora_trap_refresh(ctx: AiContext, z: Zone) -> void:
	if ctx.tick < z.impact and trapped.is_empty():
		var rows: PackedInt32Array = _movers(ctx, z)
		_aurora_trap(ctx, z, rows)


## Infantry and anti-tank units hold, and at impact + 20 attack into the zone where the disabled vehicles are.
func _aurora_counter(ctx: AiContext, z: Zone, _budget: AiBudget) -> void:
	var t: AiEntityTable = ctx.kb.own
	if AiForce.armed_enemy_rows(ctx, z.x, z.y, 14 * Fp.CELL, 200, _tmp) == 0:
		return
	var ids: PackedInt32Array = PackedInt32Array()
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or t.hp[r] <= 0 or (t.flags[r] & AiTypes.EF_LOADED) != 0:
			continue
		if (t.role_mask[r] & ((1 << AiTypes.R_INFANTRY_AT) | (1 << AiTypes.R_INFANTRY_BASIC))) == 0:
			continue
		if AiForce.dist(t.x[r], t.y[r], z.x, z.y) <= 30 * Fp.CELL:
			ids.append(t.eid[r])
	if ctx.cmd.attack_move(ids, z.x, z.y, false, 0):
		counter_attacks += 1


func _tempest_ring(ctx: AiContext, z: Zone) -> void:
	# AA units take a ring at 7-10 cells; with fewer than 3 AA the fighters go into the zone later
	var t: AiEntityTable = ctx.kb.own
	var ids: PackedInt32Array = PackedInt32Array()
	var aa_units: int = 0
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_UNIT and (t.role_mask[r] & (1 << AiTypes.R_AA_MOBILE)) != 0 and t.hp[r] > 0:
			aa_units += 1
			if AiForce.dist(t.x[r], t.y[r], z.x, z.y) <= 40 * Fp.CELL:
				ids.append(t.eid[r])
	for eid: int in ids:
		var r2: int = t.row(eid)
		var a: int = Fp.atan2(t.y[r2] - z.y, t.x[r2] - z.x) & Fp.ANGLE_MASK
		var px: int = z.x + Fp.step_x(a, 8 * Fp.CELL + Fp.CELL / 2)
		var py: int = z.y + Fp.step_y(a, 8 * Fp.CELL + Fp.CELL / 2)
		if ctx.cmd.attack_move(PackedInt32Array([eid]), px, py, false, 2):
			ring_orders += 1
	z.ring_done = true


func _tempest_fighters(ctx: AiContext, z: Zone) -> void:
	var t: AiEntityTable = ctx.kb.own
	var aa: int = 0
	var fighters: PackedInt32Array = PackedInt32Array()
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or t.hp[r] <= 0:
			continue
		if (t.role_mask[r] & (1 << AiTypes.R_AA_MOBILE)) != 0:
			aa += 1
		elif (t.role_mask[r] & (1 << AiTypes.R_FIGHTER)) != 0:
			fighters.append(t.eid[r])
	if aa < 3 and not fighters.is_empty():
		if ctx.cmd.attack_move(fighters, z.x, z.y, false, 2):
			ring_orders += 1


func _dragonfall_stage(ctx: AiContext, z: Zone) -> void:
	# pre-position up to 8 AT / tank units at 9 cells from the drop point
	var t: AiEntityTable = ctx.kb.own
	var mask: int = (1 << AiTypes.R_INFANTRY_AT) | (1 << AiTypes.R_TANK_MAIN) | (1 << AiTypes.R_HEAVY)
	var picked: PackedInt32Array = PackedInt32Array()
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_UNIT and t.hp[r] > 0 and (t.role_mask[r] & mask) != 0 and (t.flags[r] & AiTypes.EF_LOADED) == 0 \
				and AiForce.dist(t.x[r], t.y[r], z.x, z.y) <= 45 * Fp.CELL:
			picked.append(t.eid[r])
			if picked.size() >= 8:
				break
	for eid: int in picked:
		var r2: int = t.row(eid)
		var a: int = Fp.atan2(t.y[r2] - z.y, t.x[r2] - z.x) & Fp.ANGLE_MASK
		var px: int = z.x + Fp.step_x(a, 9 * Fp.CELL)
		var py: int = z.y + Fp.step_y(a, 9 * Fp.CELL)
		if ctx.cmd.attack_move(PackedInt32Array([eid]), px, py, false, 2):
			ring_orders += 1


## The capsules are on the ground: all anti-tank units attack them before the 5 s assembly ends.
func _dragonfall_attack(ctx: AiContext, z: Zone) -> void:
	var t: AiEntityTable = ctx.kb.own
	var mask: int = (1 << AiTypes.R_INFANTRY_AT) | (1 << AiTypes.R_TANK_MAIN) | (1 << AiTypes.R_HEAVY)
	var ids: PackedInt32Array = PackedInt32Array()
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_UNIT and t.hp[r] > 0 and (t.role_mask[r] & mask) != 0 and (t.flags[r] & AiTypes.EF_LOADED) == 0 \
				and AiForce.dist(t.x[r], t.y[r], z.x, z.y) <= 30 * Fp.CELL:
			ids.append(t.eid[r])
	if ctx.cmd.attack_move(ids, z.x, z.y, false, 2):
		counter_attacks += 1


# --------------------------------------------------------------------------------------------------------- enforce
## Re-issues the escape order of units that an op sent back into a live footprint (called after the ops each think).
func enforce(ctx: AiContext, budget: AiBudget) -> void:
	if dodge_eid.is_empty() or ctx.tick - _last_enforce < ENFORCE_MIN:
		return
	_last_enforce = ctx.tick
	var t: AiEntityTable = ctx.kb.own
	var groups: Dictionary = {}  ## dest key -> PackedInt32Array of eids
	var pos: Dictionary = {}
	for i: int in dodge_eid.size():
		var r: int = t.row(dodge_eid[i])
		if r < 0 or not budget.spend(1):
			continue
		var live: bool = false
		for z: Zone in zones:
			if ctx.tick <= z.until and z.reacted and inside(z, t.x[r], t.y[r], DANGER_MARGIN):
				live = true
				break
		if not live or t.order[r] == AiTypes.OrderKind.MOVE:
			continue
		var key: int = (dodge_y[i] / BUCKET) * 4096 + dodge_x[i] / BUCKET
		var g: PackedInt32Array = groups.get(key, PackedInt32Array())
		g.append(dodge_eid[i])
		groups[key] = g
		pos[key] = PackedInt32Array([dodge_x[i], dodge_y[i]])
	var n: int = 0
	for key2: Variant in groups:
		if n >= MAX_GROUPS:
			break
		var p: PackedInt32Array = pos[key2]
		ctx.cmd.move(groups[key2], p[0], p[1], false, 0)
		n += 1
