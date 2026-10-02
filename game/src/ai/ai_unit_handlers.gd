class_name AiUnitHandlers
extends RefCounted
## Special-unit rules (ai.md 5.9.3 - 5.9.5), stepped every 20 ticks from AiBrain.step. Handler bits come from the resolved defs
## (AiRoleResolver seeds them from the abilities, ai_roles.json adds explicit ones). Implemented rules:
##  * DEPLOY_SIEGE (idle / defending artillery): pack when armed enemies come within 60 % of the minimum range or 6 cells and no
##    escort is near (the wave's own siege is driven by AiOpAttack SIEGING; combat deploys a unit by itself when it engages).
##  * MODE_SWITCH (Shinano, Protea): siege mode when no armed enemy is within 12 cells and a target is inside the siege range,
##    close-range mode when an enemy is within 8 cells; minimum dwell 120 ticks.
##  * LOADOUT (Raptor, parked on a pad): air loadout when the enemy air share is >= 15 % or air was seen in the last 60 s, else
##    ground. WING_SWITCH (Shogun): interceptor wing at >= 20 % air share, strike wing otherwise, every 400 ticks.
##  * MAST_DEPLOY (Fen): deploy at the staging point when nothing armed is within 12 cells, pack when it is.
##  * HEALER_FOLLOW / REPAIR_FOLLOW: guard the nearest suitable unit of the op they belong to (infantry for healers).
##  * ESCORT_PROVIDER (Link Operator, Command Walkers): keep the provider on the value-weighted centroid of the unmanned units of
##    its op (3 cells behind it) when less than 60 % of the eligible value is inside the field radius.
##  * DECOY_PLACE / PUCK_PLACE / COVER_DEPLOY: periodic zone abilities (decoy every 40 s, puck every 30 s, cover when stationary
##    near enemies); Fortress Guard style deployables deploy at defense points.
##  * GARRISON_PREF (Gate Guard): garrison a civilian building near my structures.

const PERIOD: int = 20
const DWELL_TICKS: int = 120
const WING_PERIOD: int = 400
const AIR_SHARE_LOADOUT_Q8: int = 38  ## 15 % of 256
const AIR_SHARE_WING_Q8: int = 51  ## 20 % of 256

var actions: int = 0
var by_handler: PackedInt32Array = PackedInt32Array()
var _last: int = AiTypes.NEVER
var _dwell: Dictionary = {}  ## eid -> tick of the last mode change order
var _cool: Dictionary = {}  ## eid -> tick until which an ability / follow order is not repeated
var _modes: Dictionary = {}  ## def -> PackedStringArray of mode ids
var _ex: PackedInt32Array = PackedInt32Array()  ## fresh armed ground enemies of this pass: x, y pairs
var _ex_air: PackedInt32Array = PackedInt32Array()
var _air_share_q8: int = 0
var _air_seen_tick: int = AiTypes.NEVER
var _h: PackedInt32Array = PackedInt32Array()  ## handler bits by name index
var _garrison_cool: int = 0
var _gar_tried: Dictionary = {}  ## civilian building eid -> tick until which no garrison order is given for it again


func setup(_ctx: AiContext) -> void:
	by_handler.resize(AiTypes.HANDLER_NAMES.size())
	_h.resize(AiTypes.HANDLER_NAMES.size())
	for i: int in AiTypes.HANDLER_NAMES.size():
		_h[i] = 1 << i


func has(mask: int, hname: String) -> bool:
	var b: int = AiTypes.handler_bit(hname)
	return b >= 0 and (mask & (1 << b)) != 0


func step(ctx: AiContext, budget: AiBudget, b: AiBrain) -> void:
	if ctx.tick - _last < PERIOD or not budget.spend(3):
		return
	_last = ctx.tick
	if by_handler.is_empty():
		setup(ctx)
	var t: AiEntityTable = ctx.kb.own
	_scan_enemies(ctx, budget)
	var any: bool = false
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or (t.flags[r] & AiTypes.EF_LOADED) != 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile(t.def[r])
		if p == null or p.handler_mask == 0:
			continue
		if not budget.spend(2):
			return
		any = true
		_unit(ctx, b, r, p)
	if any:
		_garrison_cool = maxi(_garrison_cool - PERIOD, 0)


# ----------------------------------------------------------------------------------------------- shared queries
func _scan_enemies(ctx: AiContext, budget: AiBudget) -> void:
	var et: AiEntityTable = ctx.kb.enemy_units
	_ex.resize(0)
	_ex_air.resize(0)
	budget.spend(1 + et.count / 16)
	for i: int in et.count:
		if ctx.tick - et.last_seen[i] > 40 or (et.flags[i] & AiTypes.EF_DECOY) != 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile_of(et.owner[i], et.def[i])
		if p == null or not p.is_combat():
			continue
		if p.move_class == AiTypes.MoveClass.AIR:
			_ex_air.append(et.x[i])
			_ex_air.append(et.y[i])
			_air_seen_tick = ctx.tick
		else:
			_ex.append(et.x[i])
			_ex.append(et.y[i])
	# the OBSERVED air share of the enemy (the roster prior of the knowledge base would keep the air loadout on for ever)
	_air_share_q8 = 0
	for pid: int in ctx.kb.enemy_pids:
		if not ctx.view.player_alive(pid):
			continue
		var prof: AiEnemyProfile = ctx.kb.profiles[pid]
		var total: int = 0
		for v: int in prof.seen_value:
			total += v
		if total >= 600:
			_air_share_q8 = maxi(_air_share_q8, prof.seen_value[AiTypes.Cat.AIR] * 256 / total)


## Distance (sub-cells) to the nearest fresh armed ground enemy within `limit`; limit + 1 when none.
func enemy_dist(x: int, y: int, limit: int) -> int:
	var best: int = limit + 1
	for i: int in _ex.size() / 2:
		var dx: int = _ex[2 * i] - x
		if dx > limit or dx < -limit:
			continue
		var dy: int = _ex[2 * i + 1] - y
		if dy > limit or dy < -limit:
			continue
		var d: int = Fp.isqrt(dx * dx + dy * dy)
		if d < best:
			best = d
	return best


func _mode_ids(ctx: AiContext, def: int) -> PackedStringArray:
	if _modes.has(def):
		return _modes[def]
	var out: PackedStringArray = PackedStringArray()
	var d: DefUnit = ctx.view.unit_def(def)
	if d != null:
		var a: DefAbility = d.ability_of(DefEnums.AbilityKind.MODE_SWITCH)
		if a != null:
			for m: Variant in a.params.get("modes", []):
				out.append(str((m as Dictionary).get("id", "")))
	_modes[def] = out
	return out


func _mode_idx(ctx: AiContext, def: int, part: String, exclude: bool = false) -> int:
	var ids: PackedStringArray = _mode_ids(ctx, def)
	for i: int in ids.size():
		if ids[i].contains(part) != exclude:
			return i
	return -1


func _ready_to_act(eid: int, tick: int) -> bool:
	return int(_cool.get(eid, 0)) <= tick


func _unit(ctx: AiContext, b: AiBrain, r: int, p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	var m: int = p.handler_mask
	var eid: int = t.eid[r]
	if has(m, "MODE_SWITCH"):
		_mode_switch(ctx, b, r, p)
	if has(m, "LOADOUT"):
		_loadout(ctx, b, r, p)
	if has(m, "WING_SWITCH"):
		_wing(ctx, b, r, p)
	if has(m, "MAST_DEPLOY"):
		_mast(ctx, b, r, p)
	if has(m, "DEPLOY_SIEGE"):
		_siege_pack(ctx, b, r, p)
	if has(m, "HEALER_FOLLOW") or has(m, "REPAIR_FOLLOW"):
		_follow(ctx, b, r, p, has(m, "HEALER_FOLLOW"))
	if has(m, "ESCORT_PROVIDER") and (t.role_mask[r] & (1 << AiTypes.R_COMMAND_PROVIDER)) != 0:
		_provider(ctx, b, r, p)
	if has(m, "DECOY_PLACE") or has(m, "PUCK_PLACE"):
		_zone_ability(ctx, b, r, p)
	if has(m, "COVER_DEPLOY"):
		_cover(ctx, b, r, p)
	if has(m, "GARRISON_PREF") and _ready_to_act(eid, ctx.tick):
		_garrison(ctx, b, r, p)


func _note(b: AiBrain, hname: String) -> void:
	actions += 1
	var i: int = AiTypes.handler_bit(hname)
	if i >= 0 and i < by_handler.size():
		by_handler[i] += 1
	b.bump("h_" + hname.to_lower())


# ---------------------------------------------------------------------------------------------------- mode switch
## The mode a siege / close-range unit wants: the close mode when an armed enemy is within 8 cells, the siege mode when nothing is
## within 12 cells and a target is in the siege range (`target_ok`); in between it keeps its mode (hysteresis).
static func mode_decision(cur: int, siege_m: int, close_m: int, nearest_enemy: int, target_ok: bool) -> int:
	if cur == siege_m and nearest_enemy <= 8 * Fp.CELL:
		return close_m
	if cur != siege_m and target_ok:
		return siege_m
	return cur


func _mode_switch(ctx: AiContext, b: AiBrain, r: int, p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	var eid: int = t.eid[r]
	if ctx.tick - int(_dwell.get(eid, AiTypes.NEVER)) < DWELL_TICKS:
		return
	var siege_m: int = _mode_idx(ctx, t.def[r], "siege")
	var close_m: int = _mode_idx(ctx, t.def[r], "siege", true)
	if siege_m < 0 or close_m < 0:
		return
	var cur: int = ctx.view.e_mode(eid)
	var near: int = enemy_dist(t.x[r], t.y[r], 14 * Fp.CELL)
	var target_ok: bool = near > 12 * Fp.CELL and _target_in_range(ctx, t.x[r], t.y[r], p.range + 2 * Fp.CELL)
	var want: int = mode_decision(cur, siege_m, close_m, near, target_ok)
	if want == cur:
		return
	if ctx.cmd.set_mode(PackedInt32Array([eid]), want):
		_dwell[eid] = ctx.tick
		_note(b, "MODE_SWITCH")


## An enemy structure ghost or a seen enemy unit within `reach` of (x, y).
func _target_in_range(ctx: AiContext, x: int, y: int, reach: int) -> bool:
	var g: AiGhostTable = ctx.kb.ghosts
	var r2: int = reach * reach
	for i: int in g.count:
		if g.owner[i] < 0:
			continue
		var dx: int = g.x[i] - x
		var dy: int = g.y[i] - y
		if dx * dx + dy * dy <= r2:
			return true
	return enemy_dist(x, y, reach) <= reach


func _loadout(ctx: AiContext, b: AiBrain, r: int, _p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	var eid: int = t.eid[r]
	if ctx.view.e_air_state(eid) != AiTypes.AIR_PARKED:
		return
	if ctx.tick - int(_dwell.get(eid, AiTypes.NEVER)) < DWELL_TICKS:
		return
	var air_m: int = _mode_idx(ctx, t.def[r], "air")
	var gnd_m: int = _mode_idx(ctx, t.def[r], "ground")
	if air_m < 0 or gnd_m < 0:
		return
	var want_air: bool = _air_share_q8 >= AIR_SHARE_LOADOUT_Q8 or ctx.tick - _air_seen_tick <= 60 * SimConfig.TPS
	var want: int = air_m if want_air else gnd_m
	if ctx.view.e_mode(eid) == want:
		return
	if ctx.cmd.set_mode(PackedInt32Array([eid]), want):
		_dwell[eid] = ctx.tick
		_note(b, "LOADOUT")


func _wing(ctx: AiContext, b: AiBrain, r: int, _p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	var eid: int = t.eid[r]
	if ctx.tick - int(_dwell.get(eid, AiTypes.NEVER)) < WING_PERIOD:
		return
	var int_m: int = _mode_idx(ctx, t.def[r], "interceptor")
	var str_m: int = _mode_idx(ctx, t.def[r], "interceptor", true)
	if int_m < 0 or str_m < 0:
		return
	var want: int = int_m if _air_share_q8 >= AIR_SHARE_WING_Q8 else str_m
	if ctx.view.e_mode(eid) == want:
		_dwell[eid] = ctx.tick - WING_PERIOD + 100
		return
	if ctx.cmd.set_mode(PackedInt32Array([eid]), want):
		_dwell[eid] = ctx.tick
		_note(b, "WING_SWITCH")


# ------------------------------------------------------------------------------------------- deploy / mast / pack
func _mast(ctx: AiContext, b: AiBrain, r: int, _p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	var eid: int = t.eid[r]
	if not _ready_to_act(eid, ctx.tick) or b.leased(eid, ctx.tick):
		return
	var deployed: bool = (t.flags[r] & AiTypes.EF_DEPLOYED) != 0
	var near: int = enemy_dist(t.x[r], t.y[r], 16 * Fp.CELL)
	if deployed and near <= 12 * Fp.CELL:
		if ctx.cmd.pack(PackedInt32Array([eid])):
			_cool[eid] = ctx.tick + 400
			_note(b, "MAST_DEPLOY")
		return
	# (deploy only when nothing armed is within 16 cells: with the 12-cell pack rule the mast does not flap)
	if deployed or t.squad[r] != 0 or t.order[r] != AiTypes.OrderKind.IDLE or near <= 16 * Fp.CELL:
		return
	var pr: AiProduction = b.eco().production
	if AiForce.dist(t.x[r], t.y[r], pr.stage_x, pr.stage_y) <= 6 * Fp.CELL:
		if ctx.cmd.deploy(PackedInt32Array([eid])):
			_cool[eid] = ctx.tick + 200
			_note(b, "MAST_DEPLOY")


func _siege_pack(ctx: AiContext, b: AiBrain, r: int, p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	var eid: int = t.eid[r]
	if (t.flags[r] & AiTypes.EF_DEPLOYED) == 0 or not _ready_to_act(eid, ctx.tick):
		return
	var lim: int = maxi(6 * Fp.CELL, p.min_range * 60 / 100)
	if enemy_dist(t.x[r], t.y[r], lim) > lim:
		return
	# escorts: a non-artillery combat unit of mine within 6 cells
	var esc: int = 6 * Fp.CELL
	for r2: int in t.count:
		if r2 == r or t.kind[r2] != AiTypes.KIND_UNIT or (t.role_mask[r2] & (1 << AiTypes.R_COMBAT)) == 0:
			continue
		var p2: AiUnitProfile = ctx.unit_profile(t.def[r2])
		if p2 == null or p2.category == AiTypes.Cat.ARTILLERY or not p2.is_combat():
			continue
		if absi(t.x[r2] - t.x[r]) <= esc and absi(t.y[r2] - t.y[r]) <= esc:
			return
	var pr: AiProduction = b.eco().production
	if ctx.cmd.pack(PackedInt32Array([eid])):
		ctx.cmd.move(PackedInt32Array([eid]), pr.stage_x, pr.stage_y, true)
		b.lease_one(eid, ctx.tick + 200)
		_cool[eid] = ctx.tick + 200
		_note(b, "DEPLOY_SIEGE")


# ---------------------------------------------------------------------------------------------- follow / provider
func _op_of(ctx: AiContext, b: AiBrain, r: int) -> AiOp:
	var sid: int = ctx.kb.own.squad[r]
	if sid <= 0:
		return null
	var sq: AiSquad = b.squads().squad(sid)
	if sq == null or sq.op_id < 0:
		return null
	var o: AiOp = b.op_by_id(sq.op_id)
	if o == null or o.is_over() or (o.type != AiTypes.OpType.ATTACK and o.type != AiTypes.OpType.DEFEND):
		return null
	return o


func _follow(ctx: AiContext, b: AiBrain, r: int, _p: AiUnitProfile, healer: bool) -> void:
	var t: AiEntityTable = ctx.kb.own
	var eid: int = t.eid[r]
	if not _ready_to_act(eid, ctx.tick):
		return
	var o: AiOp = _op_of(ctx, b, r)
	if o == null or o.state == AiTypes.OpState.RETREATING or o.state == AiTypes.OpState.FORMING:
		return
	# the anchor: the unit of the op nearest to its centroid that this unit supports
	var best: int = -1
	var best_d: int = 1 << 60
	var want_inf: bool = healer
	for eid2: int in o.ids:
		if eid2 == eid:
			continue
		var r2: int = t.row(eid2)
		if r2 < 0:
			continue
		var p2: AiUnitProfile = ctx.unit_profile(t.def[r2])
		if p2 == null or (t.role_mask[r2] & ((1 << AiTypes.R_HEALER) | (1 << AiTypes.R_REPAIRER) | (1 << AiTypes.R_COMMAND_PROVIDER))) != 0:
			continue
		if (p2.category == AiTypes.Cat.INFANTRY) != want_inf or p2.category == AiTypes.Cat.AIR:
			continue
		var d: int = AiForce.dist(t.x[r2], t.y[r2], o.cx, o.cy)
		if d < best_d:
			best_d = d
			best = eid2
	if best < 0:
		return
	var rb: int = t.row(best)
	if AiForce.dist(t.x[r], t.y[r], t.x[rb], t.y[rb]) <= 4 * Fp.CELL and t.order[r] == AiTypes.OrderKind.GUARD:
		return
	if ctx.cmd.guard(PackedInt32Array([eid]), best, 0, 0):
		b.lease_one(eid, ctx.tick + 300)
		_cool[eid] = ctx.tick + 100
		_note(b, "HEALER_FOLLOW" if healer else "REPAIR_FOLLOW")


func _provider(ctx: AiContext, b: AiBrain, r: int, _p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	var eid: int = t.eid[r]
	if not _ready_to_act(eid, ctx.tick):
		return
	var o: AiOp = _op_of(ctx, b, r)
	if o == null or o.state == AiTypes.OpState.RETREATING or o.state == AiTypes.OpState.FORMING:
		return
	var sx: int = 0
	var sy: int = 0
	var sv: int = 0
	var n: int = 0
	for eid2: int in o.ids:
		var r2: int = t.row(eid2)
		if r2 < 0 or (t.role_mask[r2] & (1 << AiTypes.R_UNMANNED)) == 0 or (t.role_mask[r2] & (1 << AiTypes.R_COMMAND_PROVIDER)) != 0:
			continue
		var v: int = maxi(t.paid[r2], 1)
		sx += t.x[r2] * v
		sy += t.y[r2] * v
		sv += v
		n += 1
	if n < 2 or sv <= 0:
		return
	var cx: int = sx / sv
	var cy: int = sy / sv
	var field: int = ctx.tune("handlers.field_radius_c", 5) * Fp.CELL
	var inside: int = 0
	for eid3: int in o.ids:
		var r3: int = t.row(eid3)
		if r3 < 0 or (t.role_mask[r3] & (1 << AiTypes.R_UNMANNED)) == 0 or (t.role_mask[r3] & (1 << AiTypes.R_COMMAND_PROVIDER)) != 0:
			continue
		if AiForce.dist(t.x[r3], t.y[r3], t.x[r], t.y[r]) <= field:
			inside += maxi(t.paid[r3], 1)
	if inside * 100 >= 60 * sv:
		return
	# 3 cells behind the centroid (away from the target)
	var dx: int = cx - o.tx
	var dy: int = cy - o.ty
	var dist: int = maxi(Fp.dist(dx, dy), 1)
	var px: int = cx + dx * 3 * Fp.CELL / dist
	var py: int = cy + dy * 3 * Fp.CELL / dist
	if ctx.cmd.move(PackedInt32Array([eid]), px, py, false, 3):
		b.lease_one(eid, ctx.tick + 60)
		_cool[eid] = ctx.tick + 60
		_note(b, "ESCORT_PROVIDER")


# ------------------------------------------------------------------------------------------- zone abilities / cover
func _ability_slot(ctx: AiContext, def: int, kind: int) -> int:
	var d: DefUnit = ctx.view.unit_def(def)
	if d == null or kind >= d.ability_slot_of_kind.size():
		return -1
	return d.ability_slot_of_kind[kind]


func _zone_ability(ctx: AiContext, b: AiBrain, r: int, p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	var eid: int = t.eid[r]
	if not _ready_to_act(eid, ctx.tick) or b.leased(eid, ctx.tick) or t.order[r] != AiTypes.OrderKind.IDLE:
		return
	var decoy: bool = has(p.handler_mask, "DECOY_PLACE")
	var slot: int = _ability_slot(ctx, t.def[r], DefEnums.AbilityKind.DECOY_SPAWN if decoy else DefEnums.AbilityKind.SENSOR_PUCK)
	if slot < 0:
		return
	# the spot: the base edge facing the approach (decoy) or the staging point (puck)
	var pr: AiProduction = b.eco().production
	var hx: int = ctx.kb.sites.home_x
	var hy: int = ctx.kb.sites.home_y
	var sx: int = pr.stage_x
	var sy: int = pr.stage_y
	if decoy:
		var dx: int = sx - hx
		var dy: int = sy - hy
		var dist: int = maxi(Fp.dist(dx, dy), 1)
		sx = hx + dx * 9 * Fp.CELL / dist
		sy = hy + dy * 9 * Fp.CELL / dist
	if AiForce.dist(t.x[r], t.y[r], sx, sy) > 4 * Fp.CELL:
		if t.squad[r] <= 0 and ctx.cmd.move(PackedInt32Array([eid]), sx, sy, false, 3):
			_cool[eid] = ctx.tick + 100
		return
	if ctx.cmd.use_ability(PackedInt32Array([eid]), slot, t.x[r], t.y[r]):
		_cool[eid] = ctx.tick + (40 if decoy else 30) * SimConfig.TPS
		_note(b, "DECOY_PLACE" if decoy else "PUCK_PLACE")


func _cover(ctx: AiContext, b: AiBrain, r: int, p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	var eid: int = t.eid[r]
	if not _ready_to_act(eid, ctx.tick) or (t.flags[r] & AiTypes.EF_MOVING) != 0 or t.order[r] == AiTypes.OrderKind.MOVE:
		return
	if (t.flags[r] & AiTypes.EF_DEPLOYED) != 0:
		# a deployed guard packs up once nothing armed has been near for a while
		if enemy_dist(t.x[r], t.y[r], 16 * Fp.CELL) > 16 * Fp.CELL and _cool.get(eid, 0) <= ctx.tick:
			if ctx.cmd.pack(PackedInt32Array([eid])):
				_cool[eid] = ctx.tick + 200
		return
	var reach: int = p.range * 13 / 10
	if enemy_dist(t.x[r], t.y[r], reach) > reach:
		return
	var slot: int = _ability_slot(ctx, t.def[r], DefEnums.AbilityKind.PORTABLE_COVER)
	if slot >= 0:
		if ctx.cmd.use_ability(PackedInt32Array([eid]), slot, t.x[r], t.y[r]):
			_cool[eid] = ctx.tick + 45 * SimConfig.TPS
			_note(b, "COVER_DEPLOY")
		return
	# a deployable guard (Fortress Guard): only at defense points (own units in a DEFEND squad or the reserve)
	if (t.squad[r] == 0 or _op_of_type(ctx, b, r) == AiTypes.OpType.DEFEND) and ctx.view.unit_def(t.def[r]).has_ability(DefEnums.AbilityKind.DEPLOY):
		if ctx.cmd.deploy(PackedInt32Array([eid])):
			_cool[eid] = ctx.tick + 300
			_note(b, "COVER_DEPLOY")


func _op_of_type(ctx: AiContext, b: AiBrain, r: int) -> int:
	var sid: int = ctx.kb.own.squad[r]
	if sid <= 0:
		return AiTypes.OpType.NONE
	var sq: AiSquad = b.squads().squad(sid)
	if sq == null or sq.op_id < 0:
		return AiTypes.OpType.NONE
	var o: AiOp = b.op_by_id(sq.op_id)
	return o.type if o != null else AiTypes.OpType.NONE


# ---------------------------------------------------------------------------------------------------- garrison
func _garrison(ctx: AiContext, b: AiBrain, r: int, _p: AiUnitProfile) -> void:
	var t: AiEntityTable = ctx.kb.own
	if t.squad[r] != 0 or (t.flags[r] & AiTypes.EF_GARRISONED) != 0 or _garrison_cool > 0:
		return
	if t.order[r] != AiTypes.OrderKind.IDLE:
		return
	var ids: PackedInt32Array = PackedInt32Array()
	ctx.view.neutral_ids(ids)
	var best: int = -1
	var best_d: int = 1 << 60
	var reach: int = 14 * Fp.CELL
	for nid: int in ids:
		var nd: DefNeutral = ctx.view.neutral_def(ctx.view.e_def(nid))
		if nd == null or nd.neutral_kind != DefEnums.NeutralKind.CIVILIAN_GARRISON or int(_gar_tried.get(nid, 0)) > ctx.tick:
			continue
		if not ctx.view.cell_explored(ctx.view.e_x(nid) >> Fp.CELL_SHIFT, ctx.view.e_y(nid) >> Fp.CELL_SHIFT):
			continue
		var d: int = AiForce.dist(ctx.view.e_x(nid), ctx.view.e_y(nid), ctx.kb.sites.home_x, ctx.kb.sites.home_y)
		if d <= reach + 20 * Fp.CELL and d < best_d:
			best_d = d
			best = nid
	if best < 0:
		return
	# up to 4 squads of Gate Guards (any unit with the handler) go in together
	var group: PackedInt32Array = PackedInt32Array()
	for r2: int in t.count:
		if group.size() >= 4:
			break
		if t.kind[r2] == AiTypes.KIND_UNIT and t.squad[r2] == 0 and t.def[r2] == t.def[r] and t.order[r2] == AiTypes.OrderKind.IDLE:
			group.append(t.eid[r2])
	if ctx.cmd.garrison(group, best):
		_gar_tried[best] = ctx.tick + 6000  # one try per building per 5 minutes: the order may be refused (claimed by an enemy)
		for g: int in group:
			_cool[g] = ctx.tick + 1200
			b.lease_one(g, ctx.tick + 1200)
		_garrison_cool = 400
		_note(b, "GARRISON_PREF")


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([actions, _dwell.size(), _cool.size()])
	v.append_array(by_handler)
	return AiRng.hash_ints(v)
