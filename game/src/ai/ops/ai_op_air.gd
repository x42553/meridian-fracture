class_name AiOpAir
extends AiOp
## Aircraft sorties (ai.md 5.10.4). One standing op per AI that owns the aircraft of the reserve (they no longer ride along with
## the ground waves): bombers / gunships form the STRIKE group, fighters and EW aircraft the PATROL group.
##  * Capacity is the production side (pads x 3/2, AiProduction); the AI rearms at its own airfields (the sim's sortie machine lands
##    an aircraft that is out of ammo and reloads it on a pad).
##  * STRIKE: PARKED -> LAUNCH (>= min_sortie = max(3, 60 % of the group) aircraft parked and healthy, target chosen, AA acceptable)
##    -> ATTACK (`force_fire` at the target structure ghost: no vision needed) -> RETURNING / REARM (the sortie machine) -> PARKED.
##    air_score = value(target cluster) x 256 / (256 + aa_pen_q8), aa_pen_q8 = AA dps within 8 cells x 8 s x 256 / bomber hp pool;
##    a sortie needs aa_pen_q8 <= 128, or a superweapon / production / tech target with air_score >= 2 x the flight's cost.
##    Camouflage bombers avoid targets covered by a Watchtower / AA battery (detector anchors).
##  * PATROL: fighters wait on their pads; when enemy aircraft are within 20 cells of my base or my ops they `attack_move` at them
##    and return to base 400 ticks after the sky is clear again.

const PERIOD: int = 30
const EXPOSURE_S: int = 8
const AA_PEN_MAX_Q8: int = 128
const COOLDOWN_TICKS: int = 300
const NO_AIRCRAFT_END: int = 3600

var strike_sq: int = -1
var patrol_sq: int = -1
var sorties: int = 0
var sortie_units: int = 0
var scrambles: int = 0
var held_aa: int = 0
var last_target_x: int = 0
var last_target_y: int = 0
var _next_sortie: int = 0
var _last_air_seen: int = AiTypes.NEVER
var cas_orders: int = 0
var _cas_out: bool = false
var _cas_last_op: int = AiTypes.NEVER
var _patrol_out: bool = false
var _empty_since: int = AiTypes.NEVER
var _strike_ids: PackedInt32Array = PackedInt32Array()
var _patrol_ids: PackedInt32Array = PackedInt32Array()


## Standing air op: launched when the roster has aircraft, an active airfield stands and >= 2 aircraft wait in the reserve.
static func try_launch(ctx: AiContext, b: AiBrain, _budget: AiBudget) -> bool:
	if b.count_ops(AiTypes.OpType.AIR) > 0 or ctx.tick < b.air_block_until or b.desperate:
		return false
	var af: int = ctx.res.structure_of_kind(AiTypes.StructKind.AIRFIELD)
	if af < 0 or ctx.view.struct_count(af) == 0:
		return false
	var n: int = 0
	var t: AiEntityTable = ctx.kb.own
	var mask: int = (1 << AiTypes.R_FIGHTER) | (1 << AiTypes.R_BOMBER) | (1 << AiTypes.R_EW_AIR)
	for eid: int in b.squads().reserve.units:
		var r: int = t.row(eid)
		if r >= 0 and (t.role_mask[r] & mask) != 0:
			n += 1
	if n < 2:
		b.air_block_until = ctx.tick + 300
		return false
	var op: AiOpAir = AiOpAir.new()
	if b.add_op(ctx, op):
		b.bump("air_ops")
		return true
	b.air_block_until = ctx.tick + 600
	return false


func start(ctx: AiContext) -> bool:
	type = AiTypes.OpType.AIR
	priority = 45
	var b: AiBrain = ctx.brain as AiBrain
	var sm: AiSquadManager = b.squads()
	var s1: AiSquad = sm.create(AiTypes.SquadKind.AIR_STRIKE, id)
	s1.prio = priority
	var s2: AiSquad = sm.create(AiTypes.SquadKind.AIR_PATROL, id)
	s2.prio = priority
	strike_sq = s1.id
	patrol_sq = s2.id
	squads.append(s1.id)
	squads.append(s2.id)
	_claim(ctx, b)
	if s1.units.is_empty() and s2.units.is_empty():
		return false
	period = PERIOD
	timeout_tick = ctx.tick + 24000
	set_state(ctx, AiTypes.OpState.ENGAGING)
	return true


func _claim(ctx: AiContext, b: AiBrain) -> void:
	var sm: AiSquadManager = b.squads()
	var hx: int = ctx.kb.sites.home_x
	var hy: int = ctx.kb.sites.home_y
	var s1: AiSquad = sm.squad(strike_sq)
	var s2: AiSquad = sm.squad(patrol_sq)
	if s1 != null:
		sm.claim(1 << AiTypes.R_BOMBER, 99, hx, hy, 0, priority, s1)
	if s2 != null:
		sm.claim((1 << AiTypes.R_FIGHTER) | (1 << AiTypes.R_EW_AIR), 99, hx, hy, 0, priority, s2)


func update(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if not budget.spend(6):
		return
	timeout_tick = ctx.tick + 24000
	_claim(ctx, b)
	var sm: AiSquadManager = b.squads()
	var s1: AiSquad = sm.squad(strike_sq)
	var s2: AiSquad = sm.squad(patrol_sq)
	_strike_ids = s1.units.duplicate() if s1 != null else PackedInt32Array()
	_patrol_ids = s2.units.duplicate() if s2 != null else PackedInt32Array()
	if _strike_ids.is_empty() and _patrol_ids.is_empty():
		if _empty_since == AiTypes.NEVER:
			_empty_since = ctx.tick
		elif ctx.tick - _empty_since > NO_AIRCRAFT_END:
			release(ctx)
			state = AiTypes.OpState.DONE
		return
	_empty_since = AiTypes.NEVER
	measure(ctx, budget)
	_patrol(ctx, b, budget)
	_strike(ctx, b, budget)


# ------------------------------------------------------------------------------------------------------ patrol
func _patrol(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	if _patrol_ids.is_empty():
		return
	var et: AiEntityTable = ctx.kb.enemy_units
	var t: AiEntityTable = ctx.kb.own
	var sx: int = 0
	var sy: int = 0
	var n: int = 0
	# my assets: the base and the fighting ops
	var assets: PackedInt32Array = PackedInt32Array([ctx.kb.sites.home_x, ctx.kb.sites.home_y])
	for o: AiOp in b.ops:
		if (o.type == AiTypes.OpType.ATTACK or o.type == AiTypes.OpType.DEFEND) and not o.is_over() and o.alive > 0:
			assets.append(o.cx)
			assets.append(o.cy)
	budget.spend(2 + et.count / 8)
	for i: int in et.count:
		if ctx.tick - et.last_seen[i] > 60:
			continue
		var p: AiUnitProfile = ctx.unit_profile_of(et.owner[i], et.def[i])
		if p == null or p.category != AiTypes.Cat.AIR or not p.is_combat():
			continue
		var near: bool = false
		for k: int in assets.size() / 2:
			if AiForce.dist(et.x[i], et.y[i], assets[2 * k], assets[2 * k + 1]) <= 20 * Fp.CELL:
				near = true
				break
		if near:
			sx += et.x[i]
			sy += et.y[i]
			n += 1
	if n > 0:
		_last_air_seen = ctx.tick
		var ready: PackedInt32Array = PackedInt32Array()
		for eid: int in _patrol_ids:
			var r: int = t.row(eid)
			if r >= 0 and t.hp[r] * 100 >= t.hp_max[r] * 50 and (t.order[r] == AiTypes.OrderKind.IDLE or _patrol_out):
				ready.append(eid)
		if not ready.is_empty() and (not _patrol_out or ctx.tick % 120 < PERIOD):
			if ctx.cmd.attack_move(ready, sx / n, sy / n):
				_patrol_out = true
				scrambles += 1
				b.bump("air_scramble")
		return
	if _patrol_out and ctx.tick - _last_air_seen >= 400:
		_patrol_out = false
		ctx.cmd.return_to_base(_patrol_ids)


# ------------------------------------------------------------------------------------------------------ strike
func _strike(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	if _strike_ids.is_empty() or ctx.tick < _next_sortie or ctx.kb.primary < 0:
		return
	var t: AiEntityTable = ctx.kb.own
	var ready: PackedInt32Array = PackedInt32Array()
	var hp_pool: int = 0
	var flight_cost: int = 0
	var camo: bool = false
	for eid: int in _strike_ids:
		var r: int = t.row(eid)
		if r < 0:
			continue
		if ctx.view.e_air_state(eid) == AiTypes.AIR_PARKED and t.hp[r] * 100 >= t.hp_max[r] * 60:
			ready.append(eid)
			hp_pool += t.hp[r]
			flight_cost += t.paid[r]
			if (t.flags[r] & AiTypes.EF_CAMO) != 0 or (ctx.unit_profile(t.def[r]).handler_mask & (1 << AiTypes.handler_bit("CAMO_HOLD"))) != 0:
				camo = true
	ready = _cas(ctx, b, ready, hp_pool)
	if ready.is_empty():
		return
	var min_sortie: int = mini(maxi(3, _strike_ids.size() * 60 / 100), _strike_ids.size())
	if ready.size() < min_sortie:
		return
	var tgt: Dictionary = pick_target(ctx, budget, ready, hp_pool, flight_cost, camo)
	if tgt.is_empty():
		_next_sortie = ctx.tick + 200
		return
	if ctx.cmd.force_fire(ready, int(tgt["x"]), int(tgt["y"]), 0, maxi(int(tgt["eid"]), 0)):
		sorties += 1
		sortie_units += ready.size()
		last_target_x = int(tgt["x"])
		last_target_y = int(tgt["y"])
		_next_sortie = ctx.tick + COOLDOWN_TICKS
		b.bump("air_sortie")
		b.bump("air_sortie_units", ready.size())
		ctx.telemetry.emit(AiTypes.Tele.AIR_SORTIE, ready.size(), int(tgt["score"]), ctx.tick)


## Close air support: hovering gunships (move class hover) that are ready join an ATTACK op in ENGAGING when the anti-air at its
## position is below 30 % of their hit points (ai.md 5.10.4); they return to base 300 ticks after the last engagement. Returns the
## aircraft left for structure strikes (all of them when no wave is engaged).
func _cas(ctx: AiContext, b: AiBrain, ready: PackedInt32Array, hp_pool: int) -> PackedInt32Array:
	var t: AiEntityTable = ctx.kb.own
	var gun: PackedInt32Array = PackedInt32Array()
	var rest: PackedInt32Array = PackedInt32Array()
	for eid: int in ready:
		var r: int = t.row(eid)
		if r >= 0 and ctx.unit_profile(t.def[r]).move_class == AiForce.AIR_HOVER:
			gun.append(eid)
		else:
			rest.append(eid)
	var eng: AiOp = null
	for o: AiOp in b.ops:
		if o.type == AiTypes.OpType.ATTACK and o.state == AiTypes.OpState.ENGAGING and not o.is_over() and o.alive > 0:
			eng = o
			break
	if eng != null:
		_cas_last_op = ctx.tick
	elif _cas_out and ctx.tick - _cas_last_op >= 300:
		_cas_out = false
		ctx.cmd.return_to_base(_strike_ids)
	if eng == null or gun.is_empty():
		return ready
	var pen: int = _aa_dps(ctx, eng.cx, eng.cy) * EXPOSURE_S * 256 / maxi(hp_pool, 1)
	if pen * 100 > 30 * 256:
		return ready
	if ctx.cmd.attack_move(gun, eng.cx, eng.cy):
		_cas_out = true
		cas_orders += 1
		b.bump("air_cas")
	return rest


## Best structure ghost of a living enemy for a flight: {x, y, eid, score, aa_pen}. Empty when nothing is worth the risk.
func pick_target(ctx: AiContext, budget: AiBudget, ready: PackedInt32Array, hp_pool: int, flight_cost: int, camo: bool) -> Dictionary:
	var g: AiGhostTable = ctx.kb.ghosts
	var kb: AiKnowledge = ctx.kb
	budget.spend(2 + g.count / 4)
	var best: Dictionary = {}
	var best_s: int = 0
	var hx: int = kb.sites.home_x
	var hy: int = kb.sites.home_y
	for i: int in g.count:
		if g.owner[i] < 0 or not ctx.view.player_alive(g.owner[i]) or g.eid[i] <= 0:
			continue
		var k: int = g.kind[i]
		if k == AiTypes.StructKind.WATCHTOWER or k == AiTypes.StructKind.AT_TURRET or k == AiTypes.StructKind.ADV_DEFENSE \
				or k == AiTypes.StructKind.AA_BATTERY:
			continue  # defenses are not worth a flight
		var w: int = 100
		var vital: bool = false
		match k:
			AiTypes.StructKind.SUPERWEAPON:
				w = 300
				vital = true
			AiTypes.StructKind.LAB, AiTypes.StructKind.FACTORY, AiTypes.StructKind.RADAR:
				w = 150
				vital = true
			AiTypes.StructKind.GENERATOR:
				w = 150
			AiTypes.StructKind.REFINERY:
				w = 130
			AiTypes.StructKind.HQ:
				w = 120
		var value: int = g.value[i] * w / 100
		# the cluster around it counts too
		for j: int in g.count:
			if j != i and g.owner[j] == g.owner[i]:
				var dx: int = g.x[j] - g.x[i]
				var dy: int = g.y[j] - g.y[i]
				if dx * dx + dy * dy <= 6 * Fp.CELL * 6 * Fp.CELL:
					value += g.value[j] / 3
		var aa: int = _aa_dps(ctx, g.x[i], g.y[i])
		var pen: int = aa * EXPOSURE_S * 256 / maxi(hp_pool, 1)
		if pen > AA_PEN_MAX_Q8 and not (vital and value * 256 / (256 + pen) >= 2 * flight_cost):
			held_aa += 1
			continue
		if camo and _detector_near(g, i):
			continue
		var score: int = value * 256 / (256 + pen)
		if score * 2 < flight_cost:
			continue
		var d_c: int = AiForce.cells(g.x[i], g.y[i], hx, hy)
		var s: int = score * 100 / (100 + d_c)
		if s > best_s:
			best_s = s
			best = {"x": g.x[i], "y": g.y[i], "eid": g.eid[i], "score": score, "aa_pen": pen}
	return best


## Enemy anti-air damage per second within 8 cells of (x, y): AA structure ghosts and recently seen AA units (dps vs light air).
func _aa_dps(ctx: AiContext, x: int, y: int) -> int:
	var r2: int = 8 * Fp.CELL * 8 * Fp.CELL
	var total: int = 0
	var g: AiGhostTable = ctx.kb.ghosts
	for i: int in g.count:
		if g.owner[i] < 0:
			continue
		var dx: int = g.x[i] - x
		var dy: int = g.y[i] - y
		if dx * dx + dy * dy > r2 or not AiForce.is_defense_kind(g.kind[i]):
			continue
		var sp: AiUnitProfile = ctx.struct_profile_of(g.owner[i], g.def[i])
		if sp != null:
			total += sp.dps_x100[DefEnums.ArmorClass.AIR_LIGHT] / 100
	var et: AiEntityTable = ctx.kb.enemy_units
	for j: int in et.count:
		if ctx.tick - et.last_seen[j] > 600:
			continue
		var ex: int = et.x[j] - x
		var ey: int = et.y[j] - y
		if ex * ex + ey * ey > r2:
			continue
		var p: AiUnitProfile = ctx.unit_profile_of(et.owner[j], et.def[j])
		if p != null:
			total += p.dps_x100[DefEnums.ArmorClass.AIR_LIGHT] / 100
	return total


func _detector_near(g: AiGhostTable, i: int) -> bool:
	var r2: int = 6 * Fp.CELL * 6 * Fp.CELL
	for j: int in g.count:
		if g.owner[j] != g.owner[i]:
			continue
		if g.kind[j] != AiTypes.StructKind.WATCHTOWER and g.kind[j] != AiTypes.StructKind.AA_BATTERY:
			continue
		var dx: int = g.x[j] - g.x[i]
		var dy: int = g.y[j] - g.y[i]
		if dx * dx + dy * dy <= r2:
			return true
	return false


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), sorties, sortie_units, scrambles, held_aa, _strike_ids.size(), _patrol_ids.size()]))
