class_name AiDefense
extends RefCounted
## Slot 9 (ai.md 5.8.4, every 10 ticks): alarms and DEFEND ops. Sites are the clusters of my key structures (HQ, refineries,
## production, radar / laboratory, superweapon). For every site with visible armed enemies within 16 cells (after the
## difficulty's reaction delay) an AiOpDefend is created that claims reserve units nearest to the site until the local strength
## ratio (my units + my powered defenses vs the intruders) reaches 1.3; a key site (HQ / production / superweapon) may also
## take units from lower-priority ops within 30 cells, and when the ratio stays below 1.0 the attack ops are recalled and the
## posture is pushed down (`severe`). Air intruders make the claim prefer AA_MOBILE and FIGHTER units. Defense STRUCTURE wants
## are AiEconomy's job (5.4.5).

const SITE_SPACING: int = 12 * Fp.CELL
const THREAT_R: int = 16 * Fp.CELL
const REFRESH_TICKS: int = 100

var sites: PackedInt32Array = PackedInt32Array()  ## triples x, y, key (1 = HQ / production / superweapon)
var responses: int = 0
var reinforced: int = 0
var recalls: int = 0
var _sites_tick: int = AiTypes.NEVER
var _first_seen: Dictionary = {}  ## site cell key -> tick the intruders were first seen
var _rows: PackedInt32Array = PackedInt32Array()


func setup(_ctx: AiContext) -> void:
	pass


func step(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null or not budget.spend(3):
		return
	if ctx.tick - _sites_tick >= REFRESH_TICKS:
		_refresh_sites(ctx, budget)
	for i: int in sites.size() / 3:
		if not budget.spend(3):
			return
		var sx: int = sites[3 * i]
		var sy: int = sites[3 * i + 1]
		var key: bool = sites[3 * i + 2] != 0
		var n: int = AiForce.armed_enemy_rows(ctx, sx, sy, THREAT_R, 60, _rows)
		var ck: int = AiCommandBuilder.cell_key(sx, sy)
		if n == 0:
			_first_seen.erase(ck)
			continue
		var first: int = int(_first_seen.get(ck, ctx.tick))
		_first_seen[ck] = first
		if ctx.tick - first < ctx.diff.reaction_delay_ticks:
			continue
		var op: AiOpDefend = _op_at(b, sx, sy)
		var threat: AiStrengthGroup = AiForce.enemy_group(ctx, sx, sy, THREAT_R, 60)
		if op != null:
			_top_up(ctx, b, op, threat, key)
			continue
		if b.count_ops(AiTypes.OpType.DEFEND) >= 4:
			continue
		_respond(ctx, b, sx, sy, key, threat, budget)


func _op_at(b: AiBrain, x: int, y: int) -> AiOpDefend:
	for o: AiOp in b.ops:
		if o.type == AiTypes.OpType.DEFEND and not o.is_over():
			var d: AiOpDefend = o as AiOpDefend
			if AiForce.dist(d.site_x, d.site_y, x, y) <= SITE_SPACING:
				return d
	return null


func _respond(ctx: AiContext, b: AiBrain, sx: int, sy: int, key: bool, threat: AiStrengthGroup, budget: AiBudget) -> void:
	var eco: AiEconomy = b.eco()
	var defs: AiStrengthGroup = AiForce.own_defenses_group(ctx, sx, sy, THREAT_R)
	var air_threat: bool = _has_air(ctx)
	var picked: PackedInt32Array = _pick(ctx, eco, sx, sy, threat, defs, air_threat, budget)
	var op: AiOpDefend = AiOpDefend.new()
	op.setup_defense(sx, sy, key, picked)
	if picked.is_empty() or not b.add_op(ctx, op):
		if key and picked.is_empty():
			# nothing in the reserve: try the lower-priority ops right away
			var empty_op: AiOpDefend = AiOpDefend.new()
			empty_op.setup_defense(sx, sy, key, PackedInt32Array())
			_steal_only(ctx, b, eco, sx, sy, threat, empty_op)
		return
	responses += 1
	b.defend_ops_total += 1
	ctx.telemetry.emit(AiTypes.Tele.DEFEND_STARTED, sx >> Fp.CELL_SHIFT, sy >> Fp.CELL_SHIFT, ctx.tick)
	_top_up(ctx, b, op, threat, key)


## The reserve is empty: a key site steals units from lower-priority squads and starts the op with them.
func _steal_only(ctx: AiContext, b: AiBrain, eco: AiEconomy, sx: int, sy: int, threat: AiStrengthGroup, op: AiOpDefend) -> void:
	var tmp: AiSquad = eco.squads.create(AiTypes.SquadKind.DEFENSE, -1)
	tmp.prio = 90
	var got: int = eco.squads.claim(1 << AiTypes.R_COMBAT, 12, sx, sy, 30 * Fp.CELL, 90, tmp)
	if got == 0:
		eco.squads.release(tmp.id, true)
		b.severe_until = ctx.tick + 400
		return
	var ids: PackedInt32Array = tmp.units.duplicate()
	eco.squads.release(tmp.id, true)
	op.unit_ids = ids
	if b.add_op(ctx, op):
		responses += 1
		reinforced += got
		b.defend_ops_total += 1
		ctx.telemetry.emit(AiTypes.Tele.DEFEND_STARTED, sx >> Fp.CELL_SHIFT, sy >> Fp.CELL_SHIFT, ctx.tick)
		_top_up(ctx, b, op, threat, true)


## Reserve units nearest to the site (AA first against aircraft) until the local ratio reaches 1.3.
func _pick(ctx: AiContext, eco: AiEconomy, sx: int, sy: int, threat: AiStrengthGroup, defs: AiStrengthGroup, air_threat: bool, budget: AiBudget) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var res: AiSquad = eco.squads.reserve
	if res == null:
		return out
	var t: AiEntityTable = ctx.kb.own
	budget.spend(1 + res.units.size() / 4)
	var aa_mask: int = (1 << AiTypes.R_AA_MOBILE) | (1 << AiTypes.R_FIGHTER)
	var keys: PackedInt64Array = PackedInt64Array()
	for eid: int in res.units:
		var r: int = t.row(eid)
		if r < 0 or AiForce.is_sea(ctx, t.def[r]) or (t.flags[r] & AiTypes.EF_LOADED) != 0:
			continue
		var dx: int = t.x[r] - sx
		var dy: int = t.y[r] - sy
		var d: int = mini((dx * dx + dy * dy) / 1024, 0x1FFFFFFF)
		if air_threat and (t.role_mask[r] & aa_mask) != 0:
			d /= 16
		keys.append((d << 24) | (eid & 0xFFFFFF))
	keys.sort()
	var mine: AiStrengthGroup = AiStrengthGroup.new()
	var need: int = ctx.tune("defense.claim_ratio_x100", 130) * 256 / 100
	for k: int in keys:
		var eid2: int = k & 0xFFFFFF
		var r2: int = t.row(eid2)
		var p: AiUnitProfile = ctx.unit_profile(t.def[r2])
		if p == null:
			continue
		out.append(eid2)
		mine.add(p, 1, t.hp[r2], t.paid[r2])
		if out.size() % 3 == 0 or out.size() >= 24:
			var total: AiStrengthGroup = _merge(mine, defs)
			if AiStrength.ratio_q8(total, threat, 0, 0) >= need:
				break
	return out


static func _merge(a: AiStrengthGroup, b: AiStrengthGroup) -> AiStrengthGroup:
	var g: AiStrengthGroup = AiStrengthGroup.new()
	g.hp = a.hp + b.hp
	for c: int in AiStrengthGroup.NCLASS:
		g.dps_x100_by_class[c] = a.dps_x100_by_class[c] + b.dps_x100_by_class[c]
		g.hp_by_class[c] = a.hp_by_class[c] + b.hp_by_class[c]
	var wa: int = a.total_dps_x100()
	var wb: int = b.total_dps_x100()
	g.avg_range = (a.avg_range * wa + b.avg_range * wb) / maxi(wa + wb, 1)
	g.value = a.value + b.value
	g.count = a.count + b.count
	g.arty_dps_x100 = a.arty_dps_x100 + b.arty_dps_x100
	g.arty_hp = a.arty_hp + b.arty_hp
	return g


## Checks the ratio of a running op; a key site claims more units from lower-priority ops; a hopeless key site recalls the waves.
func _top_up(ctx: AiContext, b: AiBrain, op: AiOpDefend, threat: AiStrengthGroup, key: bool) -> void:
	var sq: AiSquad = op.squad(ctx)
	if sq == null:
		return
	var eco: AiEconomy = b.eco()
	var defs: AiStrengthGroup = AiForce.own_defenses_group(ctx, op.site_x, op.site_y, THREAT_R)
	var mine: AiStrengthGroup = AiForce.own_group(ctx, sq.units)
	var r_q8: int = AiStrength.ratio_q8(_merge(mine, defs), threat, 0, 0)
	if r_q8 >= ctx.tune("defense.claim_ratio_x100", 130) * 256 / 100:
		return
	# more from the reserve
	var got: int = 0
	var picked: PackedInt32Array = _pick(ctx, eco, op.site_x, op.site_y, threat, _merge(mine, defs), _has_air(ctx), AiBudget.new())
	if not picked.is_empty():
		got += b.assign_units(ctx, sq, picked)
	if key and got == 0 and ctx.tick - op.created_tick >= 20:
		got += eco.squads.claim(1 << AiTypes.R_COMBAT, 12, op.site_x, op.site_y, 30 * Fp.CELL, 90, sq)
	reinforced += got
	if key:
		var mine2: AiStrengthGroup = AiForce.own_group(ctx, sq.units)
		if AiStrength.ratio_q8(_merge(mine2, defs), threat, 0, 0) < 256:
			b.severe_until = ctx.tick + 400
			if b.count_ops(AiTypes.OpType.ATTACK) > 0 and ctx.tick >= b.recall_until:
				recalls += 1
				b.recall_attacks(ctx, op.site_x, op.site_y)


func _has_air(ctx: AiContext) -> bool:
	for r: int in _rows:
		var p: AiUnitProfile = ctx.unit_profile_of(ctx.kb.enemy_units.owner[r], ctx.kb.enemy_units.def[r])
		if p != null and p.move_class == AiTypes.MoveClass.AIR:
			return true
	return false


## Site clusters from my key structures (greedy merge within 12 cells).
func _refresh_sites(ctx: AiContext, budget: AiBudget) -> void:
	_sites_tick = ctx.tick
	var t: AiEntityTable = ctx.kb.own
	budget.spend(1 + t.count / 8)
	sites.resize(0)
	var kinds: PackedInt32Array = PackedInt32Array([AiTypes.StructKind.HQ, AiTypes.StructKind.REFINERY, AiTypes.StructKind.FACTORY,
		AiTypes.StructKind.BARRACKS, AiTypes.StructKind.RADAR, AiTypes.StructKind.LAB, AiTypes.StructKind.SUPERWEAPON,
		AiTypes.StructKind.AIRFIELD, AiTypes.StructKind.DOCK])
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_STRUCTURE or (t.flags[r] & AiTypes.EF_UNDER_CONSTRUCTION) != 0:
			continue
		var k: int = ctx.res.kind_of_structure(t.def[r])
		if not kinds.has(k):
			continue
		var is_key: int = 0 if k == AiTypes.StructKind.REFINERY else 1
		var merged: bool = false
		for i: int in sites.size() / 3:
			if AiForce.dist(sites[3 * i], sites[3 * i + 1], t.x[r], t.y[r]) <= SITE_SPACING:
				sites[3 * i + 2] = maxi(sites[3 * i + 2], is_key)
				merged = true
				break
		if not merged and sites.size() < 3 * 10:
			sites.append(t.x[r])
			sites.append(t.y[r])
			sites.append(is_key)


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([responses, reinforced, recalls, sites.size(), _first_seen.size()]))
