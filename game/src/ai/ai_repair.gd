class_name AiRepair
extends RefCounted
## Retreat and repair (ai.md 5.9.2), stepped every 20 ticks from AiBrain.step.
##  * PER-UNIT RETREAT: a combat unit of an ATTACK / DEFEND / HARASS squad below `retreat_hp_pct` (35 default, 50 NAPC, 40 AE;
##    infantry `retreat.infantry_hp_pct` 20) leaves its squad for the REPAIR squad and moves to the repair point - but only when
##    the roster has something that repairs it (a service apron at a Factory, a Lotus Tender / Reef Technician, an idle
##    Engineer with credits >= 300, a Combat Medic for infantry). It returns to its op (or the reserve) at `return_hp_pct`.
##  * REPAIR POINT: next to an own Factory (the NAPC apron heals vehicles within 5 cells), or on the Tender for REPAIR_TENDERS.
##  * ENGINEERS: `clamp(ceil(land vehicles / 10), 1, 4)` (AE: at least its salvage team) are kept alive by a unit-role want; the
##    idle ones stand at the repair point and `repair` the most damaged vehicle with value x missing hp >= 100 (one Engineer per
##    target: the sim keeps one repair claim per unit). Engineers borrowed by a capture / salvage op (brain.eng_claim) are skipped.

const PERIOD: int = 20
const APRON_CELLS: int = 4
const MAX_RETREAT_PER_PASS: int = 12
const WAIT_MAX_TICKS: int = 2400  ## a unit that heals nowhere returns after this long

var squad_id: int = -1
var retreats: int = 0
var returns: int = 0
var repair_orders: int = 0
var engineer_want: int = 0
var extra_engineers: int = 0  ## requested by capture ops
var point_x: int = 0
var point_y: int = 0
var source: int = 0  ## 0 none, 1 apron, 2 tender, 3 engineers (vehicles)
var _origin: Dictionary = {}  ## eid -> [origin squad id, tick]
var _last: int = AiTypes.NEVER
var _b_apron: int = 0
var _b_tender: int = 0
var _eng_def: int = -1
var _factory_def: int = -1
var _healer_units: PackedInt32Array = PackedInt32Array()


func setup(ctx: AiContext) -> void:
	_b_apron = 1 << AiTypes.doctrine_bit("APRON_RETREAT")
	_b_tender = 1 << AiTypes.doctrine_bit("REPAIR_TENDERS")
	_eng_def = ctx.res.first(AiTypes.R_ENGINEER)
	_factory_def = ctx.res.structure_of_kind(AiTypes.StructKind.FACTORY)
	point_x = ctx.kb.sites.home_x
	point_y = ctx.kb.sites.home_y


func step(ctx: AiContext, budget: AiBudget, b: AiBrain) -> void:
	if ctx.tick - _last < PERIOD or not budget.spend(3):
		return
	_last = ctx.tick
	var sm: AiSquadManager = b.squads()
	if squad_id < 0 or sm.squad(squad_id) == null:
		var sq: AiSquad = sm.create(AiTypes.SquadKind.REPAIR, -1)
		sq.prio = 100
		squad_id = sq.id
	_point(ctx, b, budget)
	_returns(ctx, b, sm, budget)
	_retreats(ctx, b, sm, budget)
	_engineers(ctx, b, budget)


# ------------------------------------------------------------------------------------------------------ sources
func _point(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	var t: AiEntityTable = ctx.kb.own
	budget.spend(1 + t.count / 24)
	var eco: AiEconomy = b.eco()
	var stage_x: int = eco.production.stage_x
	var stage_y: int = eco.production.stage_y
	var best: int = -1
	var best_d: int = 1 << 60
	var tender: int = -1
	var tender_d: int = 1 << 60
	var rep_bit: int = 1 << AiTypes.R_REPAIRER
	var healer_bit: int = 1 << AiTypes.R_HEALER
	_healer_units.resize(0)
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_STRUCTURE:
			if t.def[r] == _factory_def and (t.flags[r] & AiTypes.EF_UNDER_CONSTRUCTION) == 0:
				var d: int = AiForce.dist(t.x[r], t.y[r], stage_x, stage_y)
				if d < best_d:
					best_d = d
					best = r
		elif (t.role_mask[r] & rep_bit) != 0 and (t.flags[r] & AiTypes.EF_LOADED) == 0:
			var dt: int = AiForce.dist(t.x[r], t.y[r], ctx.kb.sites.home_x, ctx.kb.sites.home_y)
			if dt < tender_d:
				tender_d = dt
				tender = r
		elif (t.role_mask[r] & healer_bit) != 0:
			_healer_units.append(t.eid[r])
	source = 0
	if ctx.pers.flags & _b_apron != 0 and best >= 0:
		source = 1
	elif ctx.pers.flags & _b_tender != 0 and tender >= 0:
		source = 2
	if source == 2:
		point_x = t.x[tender]
		point_y = t.y[tender]
	elif best >= 0:
		# 3 cells from the Factory towards the staging point
		var dx: int = stage_x - t.x[best]
		var dy: int = stage_y - t.y[best]
		var dist: int = maxi(Fp.dist(dx, dy), 1)
		point_x = t.x[best] + dx * 3 * Fp.CELL / dist
		point_y = t.y[best] + dy * 3 * Fp.CELL / dist
		_snap(ctx)
	else:
		point_x = ctx.kb.sites.home_x
		point_y = ctx.kb.sites.home_y
	if source == 0 and _idle_engineers(ctx, b).size() > 0 and ctx.view.credits() >= ctx.tune("repair.min_credits", 300):
		source = 3


func _snap(ctx: AiContext) -> void:
	var v: AiWorldView = ctx.view
	var cx: int = point_x >> Fp.CELL_SHIFT
	var cy: int = point_y >> Fp.CELL_SHIFT
	for ring: int in 5:
		for oy: int in range(-ring, ring + 1):
			for ox: int in range(-ring, ring + 1):
				if maxi(absi(ox), absi(oy)) == ring and v.passable(cx + ox, cy + oy, AiTypes.MoveClass.TRACKED):
					point_x = (cx + ox) * Fp.CELL + Fp.CELL / 2
					point_y = (cy + oy) * Fp.CELL + Fp.CELL / 2
					return


func has_source(is_infantry: bool) -> bool:
	if is_infantry:
		return not _healer_units.is_empty()
	return source != 0


# ------------------------------------------------------------------------------------------------------ retreat
static func is_infantry_def(ctx: AiContext, def: int) -> bool:
	var p: AiUnitProfile = ctx.unit_profile(def)
	return p != null and p.category == AiTypes.Cat.INFANTRY


## Retreat threshold (percent of max hp) of a unit def for this AI.
func threshold_of(ctx: AiContext, def: int) -> int:
	var inf: int = ctx.tune("retreat.infantry_hp_pct", 20)
	if is_infantry_def(ctx, def):
		return mini(inf, ctx.pers.retreat_hp_pct)
	return ctx.pers.retreat_hp_pct


func _retreats(ctx: AiContext, b: AiBrain, sm: AiSquadManager, budget: AiBudget) -> void:
	if not ctx.diff.micro_retreat:
		return
	var t: AiEntityTable = ctx.kb.own
	var go: PackedInt32Array = PackedInt32Array()
	var rep: AiSquad = sm.squad(squad_id)
	for o: AiOp in b.ops:
		if o.is_over() or o.state == AiTypes.OpState.RETREATING:
			continue
		if o.type != AiTypes.OpType.ATTACK and o.type != AiTypes.OpType.DEFEND and o.type != AiTypes.OpType.HARASS:
			continue
		for sid: int in o.squads:
			var sq: AiSquad = sm.squad(sid)
			if sq == null:
				continue
			if not budget.spend(1 + sq.units.size() / 10):
				return
			for eid: int in sq.units:
				if go.size() >= MAX_RETREAT_PER_PASS:
					break
				var r: int = t.row(eid)
				if r < 0 or t.kind[r] != AiTypes.KIND_UNIT or (t.flags[r] & AiTypes.EF_LOADED) != 0:
					continue
				if t.hp[r] * 100 >= t.hp_max[r] * threshold_of(ctx, t.def[r]):
					continue
				var pr: AiUnitProfile = ctx.unit_profile(t.def[r])
				if pr == null or not pr.is_combat() or pr.move_class == AiTypes.MoveClass.AIR or AiForce.is_sea(ctx, t.def[r]):
					continue
				if not has_source(pr.category == AiTypes.Cat.INFANTRY):
					continue
				# a nearly dead cheap infantry squad is not worth the walk
				if pr.category == AiTypes.Cat.INFANTRY and t.paid[r] < 150 and t.hp[r] * 100 >= t.hp_max[r] * 20:
					continue
				go.append(eid)
				_origin[eid] = [sq.id, ctx.tick]
				o.note_detached(t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1))
	# wounded units that came back to the reserve heal too (below 60 %), so that the next wave does not take them along
	if rep != null and go.size() < MAX_RETREAT_PER_PASS and sm.reserve != null:
		for eid2: int in sm.reserve.units:
			if go.size() >= MAX_RETREAT_PER_PASS:
				break
			var r2: int = t.row(eid2)
			if r2 < 0 or t.kind[r2] != AiTypes.KIND_UNIT or t.hp[r2] * 100 >= t.hp_max[r2] * ctx.tune("repair.reserve_hp_pct", 60):
				continue
			var p2: AiUnitProfile = ctx.unit_profile(t.def[r2])
			if p2 == null or not p2.is_combat() or p2.move_class == AiTypes.MoveClass.AIR or AiForce.is_sea(ctx, t.def[r2]) \
					or not has_source(p2.category == AiTypes.Cat.INFANTRY):
				continue
			if AiForce.dist(t.x[r2], t.y[r2], point_x, point_y) <= 5 * Fp.CELL:
				continue
			go.append(eid2)
			_origin[eid2] = [0, ctx.tick]
	if go.is_empty() or rep == null:
		return
	b.assign_units(ctx, rep, go)
	if ctx.cmd.move(go, point_x, point_y, false, 1):
		retreats += go.size()
		b.bump("retreat", go.size())
		ctx.telemetry.emit(AiTypes.Tele.UNIT_RETREAT, go.size(), source, ctx.tick)


func _returns(ctx: AiContext, b: AiBrain, sm: AiSquadManager, budget: AiBudget) -> void:
	var rep: AiSquad = sm.squad(squad_id)
	if rep == null or rep.units.is_empty():
		_origin.clear()
		return
	var t: AiEntityTable = ctx.kb.own
	var ret_pct: int = ctx.pers.return_hp_pct
	var back: Dictionary = {}  ## op id -> PackedInt32Array
	var to_reserve: PackedInt32Array = PackedInt32Array()
	budget.spend(1 + rep.units.size() / 8)
	for eid: int in rep.units:
		var r: int = t.row(eid)
		if r < 0:
			continue
		var ent: Array = _origin.get(eid, [0, ctx.tick])
		var waited: int = ctx.tick - int(ent[1])
		var healed: bool = t.hp[r] * 100 >= t.hp_max[r] * ret_pct
		if not healed and waited < WAIT_MAX_TICKS and has_source(is_infantry_def(ctx, t.def[r])):
			continue
		if not healed and waited < 400:
			continue
		var origin: AiSquad = sm.squad(int(ent[0]))
		var op: AiOp = b.op_by_id(origin.op_id) if origin != null and origin.op_id >= 0 else null
		if op != null and not op.is_over() and op.state != AiTypes.OpState.RETREATING and healed:
			var lst: PackedInt32Array = back.get(op.id, PackedInt32Array())
			lst.append(eid)  # (a packed array taken out of a Dictionary is a copy: it is stored back)
			back[op.id] = lst
		else:
			to_reserve.append(eid)
	for oid: int in back:
		var op2: AiOp = b.op_by_id(oid)
		var list: PackedInt32Array = back[oid]
		var target_sq: AiSquad = sm.squad(op2.squads[0]) if op2 != null and not op2.squads.is_empty() else null
		if target_sq == null:
			to_reserve.append_array(list)
			continue
		b.assign_units(ctx, target_sq, list)
		ctx.cmd.attack_move(list, op2.tx, op2.ty, false, 2)
		returns += list.size()
		for e1: int in list:
			_origin.erase(e1)
	if not to_reserve.is_empty():
		b.assign_units(ctx, sm.reserve, to_reserve)
		var pr: AiProduction = b.eco().production
		ctx.cmd.move(to_reserve, pr.stage_x, pr.stage_y, false, 2)
		returns += to_reserve.size()
		for e2: int in to_reserve:
			_origin.erase(e2)


# ---------------------------------------------------------------------------------------------------- engineers
func _idle_engineers(ctx: AiContext, b: AiBrain) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var t: AiEntityTable = ctx.kb.own
	var bit: int = 1 << AiTypes.R_ENGINEER
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_UNIT and (t.role_mask[r] & bit) != 0 and not b.eng_claim.has(t.eid[r]) and (t.flags[r] & AiTypes.EF_LOADED) == 0:
			out.append(t.eid[r])
	return out


## The Engineer count this AI wants: repair crew (1 per 10 land vehicles) or the AE salvage team, plus what capture ops ask for.
func wanted_engineers(ctx: AiContext, b: AiBrain) -> int:
	var eco: AiEconomy = b.eco()
	if _eng_def < 0 or not eco.opener_done() or ctx.tick < ctx.tune("repair.engineers_from_s", 150) * SimConfig.TPS:
		return 0
	var t: AiEntityTable = ctx.kb.own
	var veh: int = 0
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT:
			continue
		var mc: int = ctx.unit_profile(t.def[r]).move_class if ctx.unit_profile(t.def[r]) != null else 0
		if (mc == AiTypes.MoveClass.WHEELED or mc == AiTypes.MoveClass.TRACKED) and (t.role_mask[r] & (1 << AiTypes.R_COMBAT)) != 0:
			veh += 1
	var n: int = clampi((veh + 9) / 10, 1, 4)
	if ctx.pers.has_flag(AiTypes.doctrine_bit("SALVAGE")):
		n = maxi(n, clampi(2 + eco.army_value / 8000, 2, 6))
	if ctx.pers.has_flag(AiTypes.doctrine_bit("APRON_RETREAT")) or ctx.pers.has_flag(AiTypes.doctrine_bit("REPAIR_TENDERS")):
		n = mini(n, 2)  # the apron / tenders do most of the repairs
	return n + extra_engineers


func _engineers(ctx: AiContext, b: AiBrain, budget: AiBudget) -> void:
	var eco: AiEconomy = b.eco()
	engineer_want = wanted_engineers(ctx, b)
	if engineer_want > 0 and _eng_def >= 0 and eco.role_have(AiTypes.R_ENGINEER) < engineer_want and ctx.view.credits() >= 900:
		b.add_want(AiWant.make(AiTypes.WantKind.UNIT_ROLE, _eng_def, AiTypes.R_ENGINEER, engineer_want, ctx.tune("repair.engineer_prio", 44), AiTypes.WantOrigin.ARMY))
	var idle: PackedInt32Array = _idle_engineers(ctx, b)
	if idle.is_empty() or not budget.spend(2 + idle.size()):
		return
	var t: AiEntityTable = ctx.kb.own
	# candidate patients: vehicles waiting at the repair point or out of combat, most valuable damage first
	var pat: PackedInt64Array = PackedInt64Array()
	var reach2: int = 14 * Fp.CELL * 14 * Fp.CELL
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or t.hp[r] >= t.hp_max[r] or (t.flags[r] & AiTypes.EF_LOADED) != 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile(t.def[r])
		if p == null or p.category == AiTypes.Cat.INFANTRY or p.category == AiTypes.Cat.AIR or (t.role_mask[r] & (1 << AiTypes.R_ENGINEER)) != 0:
			continue
		var dx: int = t.x[r] - point_x
		var dy: int = t.y[r] - point_y
		if dx * dx + dy * dy > reach2 or ctx.tick - t.last_dmg[r] < 120:
			continue
		var missing: int = t.paid[r] * (t.hp_max[r] - t.hp[r]) / maxi(t.hp_max[r], 1)
		if missing < ctx.tune("repair.min_missing_value", 100):
			continue
		pat.append((mini(missing, 0x3FFFFF) << 24) | (t.eid[r] & 0xFFFFFF))
	pat.sort()
	var used: Dictionary = {}
	var cmds: int = 0
	var k: int = pat.size() - 1
	for eng: int in idle:
		var er: int = t.row(eng)
		if er < 0:
			continue
		if t.order[er] != AiTypes.OrderKind.IDLE:
			continue
		if ctx.view.credits() < ctx.tune("repair.min_credits", 300):
			break
		var picked: int = -1
		while k >= 0:
			var cand: int = int(pat[k] & 0xFFFFFF)
			k -= 1
			if not used.has(cand):
				picked = cand
				break
		if picked >= 0 and cmds < 3:
			used[picked] = true
			if ctx.cmd.repair(PackedInt32Array([eng]), picked):
				repair_orders += 1
				cmds += 1
				b.bump("eng_repair")
			continue
		# nothing to repair: wait at the repair point
		var dx2: int = t.x[er] - point_x
		var dy2: int = t.y[er] - point_y
		if dx2 * dx2 + dy2 * dy2 > 8 * Fp.CELL * 8 * Fp.CELL and cmds < 3:
			if ctx.cmd.move(PackedInt32Array([eng]), point_x, point_y, false, 2):
				cmds += 1


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([retreats, returns, repair_orders, source, engineer_want, squad_id]))
