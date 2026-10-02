class_name UiSimPortWorld
extends UiSimPort
## The real adapter over `SimWorld` (ui.md 3.2.4): the ONLY UI class that reads sim internals. Reads are as-of the end
## of the last executed tick and never mutate the world (the placement scratch result and the fill buffers are the
## adapter's own). Economy `RSN_*` reasons are mapped onto `Rule` here. Reads whose sim domain has not landed yet
## (strategic warnings, cargo counts, repair cost) degrade to neutral values; see the per-method notes.

var _w: SimWorld = null
var _local: int = 0
var _viewer: int = 0
var _alpha_fn: Callable = Callable()
var _alpha: float = 0.0
var _pres: SimPlacementResult = SimPlacementResult.new()
var _place_reason: int = 0
var _tmp: PackedInt32Array = PackedInt32Array()

const _GHOST_FLAGS: int = UiEntityRow.F_GHOST | UiEntityRow.F_STRUCT


func _init(world: SimWorld = null, local_pid_value: int = 0) -> void:
	_w = world
	_local = local_pid_value
	_viewer = local_pid_value


## Provider of the render interpolation alpha (net's `session.tick_alpha`); without it `tick_alpha()` is `set_alpha`'s value.
func bind_alpha(fn: Callable) -> void:
	_alpha_fn = fn


func set_alpha(a: float) -> void:
	_alpha = a


func sim_world() -> SimWorld:
	return _w


## A replay seek built a new world: reads continue on it (the viewer stays).
func set_world(world: SimWorld) -> void:
	_w = world


# ---- RSN -> Rule / place_reason ---------------------------------------------------------------------------------------
## Economy validation reason (SimEconConst.RSN_*) as a UiSimPort.Rule (ui.md 3.2.4).
static func rule_of_rsn(rsn: int) -> int:
	match rsn:
		SimEconConst.RSN_OK:
			return Rule.OK
		SimEconConst.RSN_NOT_AVAILABLE, SimEconConst.RSN_LOCKED, SimEconConst.RSN_FEATURE_OFF, SimEconConst.RSN_NO_LAUNCHER:
			return Rule.NOT_AVAILABLE
		SimEconConst.RSN_PREREQ, SimEconConst.RSN_NO_HQ:
			return Rule.NO_PREREQ
		SimEconConst.RSN_QUEUE_FULL:
			return Rule.QUEUE_FULL
		SimEconConst.RSN_NO_CREDITS:
			return Rule.NO_CREDITS
		SimEconConst.RSN_UNIT_CAP:
			return Rule.UNIT_CAP
		SimEconConst.RSN_OUT_OF_RADIUS, SimEconConst.RSN_TERRAIN, SimEconConst.RSN_STRUCTURE_BLOCK, SimEconConst.RSN_UNIT_BLOCK, \
		SimEconConst.RSN_NEEDS_SHORE, SimEconConst.RSN_DEPOSIT, SimEconConst.RSN_DEBRIS, SimEconConst.RSN_APRON, SimEconConst.RSN_STRATEGIC_LIMIT:
			return Rule.BAD_SITE
		SimEconConst.RSN_NO_VISION, SimEconConst.RSN_NOT_EXPLORED:
			return Rule.NO_VISION
		SimEconConst.RSN_COOLDOWN, SimEconConst.RSN_NOT_READY, SimEconConst.RSN_NOT_CHARGED:
			return Rule.NOT_READY
		SimEconConst.RSN_NO_POWER, SimEconConst.RSN_BUSY:
			return Rule.BLOCKED
		SimEconConst.RSN_BAD_TARGET:
			return Rule.NO_TARGET
		SimEconConst.RSN_WRONG_KIND:
			return Rule.WRONG_KIND
		SimEconConst.RSN_INVALID_INDEX:
			return Rule.BAD_FIELD
		SimEconConst.RSN_HOLD:
			return Rule.DISABLED
	return Rule.NOT_ALLOWED


## `place_reason()` value of an RSN_*: 1 outside radius, 2 blocked, 3 shoreline, 4 strategic limit, 5 shroud, 0 none.
static func place_reason_of(rsn: int) -> int:
	match rsn:
		SimEconConst.RSN_OUT_OF_RADIUS:
			return 1
		SimEconConst.RSN_TERRAIN, SimEconConst.RSN_STRUCTURE_BLOCK, SimEconConst.RSN_UNIT_BLOCK, SimEconConst.RSN_DEPOSIT, \
		SimEconConst.RSN_DEBRIS, SimEconConst.RSN_APRON:
			return 2
		SimEconConst.RSN_NEEDS_SHORE:
			return 3
		SimEconConst.RSN_STRATEGIC_LIMIT:
			return 4
		SimEconConst.RSN_NOT_EXPLORED, SimEconConst.RSN_NO_VISION:
			return 5
	return 0


## UiSimPort.QueueState of an economy head-of-queue QS_* (`power_short` = the owner's power rate is below 100 %).
static func queue_state_of(qs: int, power_short: bool) -> int:
	match qs:
		SimEconConst.QS_HOLD:
			return QueueState.HELD
		SimEconConst.QS_PAUSED_PREREQ:
			return QueueState.PREREQ_LOST
		SimEconConst.QS_PAUSED_FUNDS:
			return QueueState.WAIT_FUNDS
		SimEconConst.QS_PAUSED_CAP:
			return QueueState.UNIT_CAP
		SimEconConst.QS_PAUSED_EXIT:
			return QueueState.EXIT_BLOCKED
		SimEconConst.QS_PAUSED_SHUTDOWN:
			return QueueState.SHUTDOWN
		SimEconConst.QS_ACTIVE:
			return QueueState.LOW_POWER if power_short else QueueState.RUNNING
	return QueueState.RUNNING


# ---- time / identity -------------------------------------------------------------------------------------------------
func tick() -> int:
	return _w.tick


func tick_alpha() -> float:
	return float(_alpha_fn.call()) if _alpha_fn.is_valid() else _alpha


func local_pid() -> int:
	return _local


func viewer_pid() -> int:
	return _viewer


func set_viewer_pid(pid: int) -> void:
	_viewer = pid


func player_count() -> int:
	return _w.players.size()


func player_active(pid: int) -> bool:
	return pid >= 0 and pid < _w.players.size() and _w.is_player_active(pid)


func team_of(pid: int) -> int:
	return _w.team_of(pid)


func color_of(pid: int) -> int:
	return _w.players[pid].color if pid >= 0 and pid < _w.players.size() else 0


func name_of(pid: int) -> String:
	return _w.players[pid].name if pid >= 0 and pid < _w.players.size() else ""


func roster_of(pid: int) -> DefRoster:
	return _w.players[pid].roster if pid >= 0 and pid < _w.players.size() else null


func rel(a: int, b: int) -> int:
	return _w.rel(a, b)


func data() -> GameData:
	return _w.data


func def_flags(kind: int, def_idx: int) -> int:
	return compute_def_flags(_w.data, roster_of(_viewer), kind, def_idx)


func rule_flag(flag: int) -> bool:
	match flag:
		RF_FOG:
			return _w.rules.fog != 0
		RF_SUPERWEAPONS:
			return _w.rules.superweapons != 0
		RF_SHARED_VISION:
			return _w.rules.shared_vision != 0
		RF_VETERANCY:
			return _w.rules.veterancy != 0
	return false


func map_w() -> int:
	return _w.map.w


func map_h() -> int:
	return _w.map.h


# ---- viewer economy --------------------------------------------------------------------------------------------------
func _pl() -> SimPlayer:
	return _w.players[_viewer] if _viewer >= 0 and _viewer < _w.players.size() else null


func credits() -> int:
	var p: SimPlayer = _pl()
	return p.credits if p != null else 0


func harvested_total() -> int:
	var p: SimPlayer = _pl()
	return p.st_credits_earned if p != null else 0


func power_supply() -> int:
	var p: SimPlayer = _pl()
	return p.power_supply if p != null else 0


func power_demand() -> int:
	var p: SimPlayer = _pl()
	return p.power_demand if p != null else 0


func unit_cap() -> int:
	return _w.rules.unit_cap


func unit_count() -> int:
	var p: SimPlayer = _pl()
	return p.unit_count if p != null else 0


func player_stats(pid: int, out: Dictionary) -> void:
	out.clear()
	if pid < 0 or pid >= _w.players.size():
		return
	var p: SimPlayer = _w.players[pid]
	out["units_built"] = p.st_units_built
	out["units_lost"] = p.st_units_lost
	out["units_killed"] = p.st_units_killed
	out["structs_built"] = p.st_structs_built
	out["structs_lost"] = p.st_structs_lost
	out["structs_killed"] = p.st_structs_killed
	out["credits_earned"] = p.st_credits_earned
	out["credits_spent"] = p.st_credits_spent
	out["damage_dealt"] = p.st_damage_dealt
	out["damage_taken"] = p.st_damage_taken
	out["cmds"] = p.st_cmds
	out["peak_units"] = p.st_peak_units
	out["harvested"] = p.econ.stat_harvested + p.econ.stat_salvaged if p.econ != null else 0
	out["value_destroyed"] = 0


func player_overview(pid: int, out: Dictionary) -> void:
	out.clear()
	if pid < 0 or pid >= _w.players.size():
		return
	var p: SimPlayer = _w.players[pid]
	var army_n: int = 0
	var army_value: int = 0
	var ax: int = 0
	var ay: int = 0
	var sx: int = 0
	var sy: int = 0
	var sn: int = 0
	for id: int in _w.own_ids(pid):
		var e: SimEntity = _w.by_id[id]
		if e == null:
			continue
		if e.kind == SimEntity.Kind.UNIT:
			if e.combat != null and e.econ == null and (e.flags & SimFlags.F_INSIDE) == 0:
				army_n += 1
				army_value += e.paid_cost
				ax += e.x
				ay += e.y
		elif e.kind == SimEntity.Kind.STRUCTURE:
			sn += 1
			sx += e.x
			sy += e.y
	out["present"] = 0 if p.controller == SimPlayer.Controller.NONE else 1
	out["credits"] = p.credits
	out["earned"] = maxi(p.st_credits_earned, p.econ.stat_harvested + p.econ.stat_salvaged if p.econ != null else 0)
	out["spent"] = p.st_credits_spent
	out["units"] = p.unit_count
	out["structs"] = p.struct_count
	out["army_n"] = army_n
	out["army_value"] = army_value
	out["kills"] = p.st_units_killed + p.st_structs_killed
	out["losses"] = p.st_units_lost + p.st_structs_lost
	out["army_x"] = ax / army_n if army_n > 0 else -1
	out["army_y"] = ay / army_n if army_n > 0 else -1
	out["base_x"] = sx / sn if sn > 0 else -1
	out["base_y"] = sy / sn if sn > 0 else -1
	out["active"] = 1 if _w.is_player_active(pid) else 0
	out["commands"] = p.st_cmds


# ---- entities --------------------------------------------------------------------------------------------------------
func alive(eid: int) -> bool:
	return _w.is_alive(eid)


func read(eid: int, out: UiEntityRow) -> bool:
	var e: SimEntity = _w.get_entity(eid)
	if e == null or (e.flags & SimFlags.F_GONE) != 0 or e.kind == SimEntity.Kind.ZONE:
		return false
	if _viewer >= 0 and not _known_to_viewer(e):
		return _read_ghost(eid, out)
	out.clear()
	out.id = e.id
	out.def_idx = e.def_idx
	out.owner = e.owner
	out.x = e.x
	out.y = e.y
	out.prev_x = e.prev_x
	out.prev_y = e.prev_y
	out.facing = e.facing
	out.layer = e.layer
	out.hp = e.hp
	out.hp_max = e.hp_max
	out.paid_cost = e.paid_cost
	out.container = e.container_id
	out.kind = _ui_kind(e)
	out.flags = _ui_flags(e)
	out.order_kind = _order_kind(e)
	if e.combat != null:
		out.stance = e.combat.stance
		out.mode = e.combat.ext_mode
		out.ammo = _w.combat.ammo_of(e, 0)
	if e.kind == SimEntity.Kind.UNIT:
		out.cargo_cap = _transport_cap(e)
	if e.prod != null:
		out.queue_len = e.prod.q_def.size()
		out.is_primary = e.prod.is_primary
		if e.prod.rally_on:
			out.rally_x = e.prod.rally_x
			out.rally_y = e.prod.rally_y
			out.rally_target = e.prod.rally_target
	if e.kind == SimEntity.Kind.NEUTRAL and e.def_idx >= 0 and e.def_idx < _w.data.neutrals.size():
		var n: DefNeutral = _w.data.neutrals[e.def_idx]
		out.capturable = n.capturable and (e.flags & SimFlags.F_NO_CAPTURE) == 0
		out.garrison_free = maxi(n.garrison_squads - out.cargo, 0)
	elif e.kind == SimEntity.Kind.STRUCTURE and e.owner < 0:
		out.capturable = (e.flags & SimFlags.F_NO_CAPTURE) == 0
	return true


func own_ids(kind_mask: int, out: PackedInt32Array) -> int:
	out.resize(0)
	if _viewer < 0:
		return 0
	for id: int in _w.own_ids(_viewer):
		var e: SimEntity = _w.by_id[id]
		var bit: int = KM_STRUCTURE if e.kind == SimEntity.Kind.STRUCTURE else KM_UNIT
		if (kind_mask & bit) != 0 and e.kind <= SimEntity.Kind.STRUCTURE:
			out.append(id)
	return out.size()


func idle_units(out: PackedInt32Array) -> int:
	return _w.find_idle_units(_viewer, out) if _viewer >= 0 else 0


func ids_of_def(kind: int, def_idx: int, out: PackedInt32Array) -> int:
	return _w.find_by_def(SimEntity.Kind.STRUCTURE if kind == KIND_STRUCTURE else SimEntity.Kind.UNIT, def_idx, _viewer, out)


func snapshot(out: UiEntitySnapshot) -> void:
	out.clear()
	if _viewer < 0:
		for e: SimEntity in _w.entities:
			if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) == 0 and e.kind != SimEntity.Kind.ZONE:
				_push_snapshot(out, e)
		return
	_w.entities_visible_to(_viewer, _tmp)
	for id: int in _tmp:
		var e2: SimEntity = _w.by_id[id]
		if e2.kind != SimEntity.Kind.ZONE:
			_push_snapshot(out, e2)
	for gv: Variant in _w.fog.ghosts(_viewer):
		var g: SimGhost = gv as SimGhost
		if g != null:
			out.push(g.eid, g.x, g.y, g.def_idx, g.owner, _GHOST_FLAGS | (UiEntityRow.K_STRUCTURE << 16), g.hp_pct)


func visibility(cx: int, cy: int) -> int:
	if _viewer < 0:
		return Vis.VISIBLE
	if _w.cell_visible(_viewer, cx, cy):
		return Vis.VISIBLE
	if _w.cell_explored(_viewer, cx, cy):
		return Vis.FOG
	return Vis.SHROUD


func can_target(eid: int) -> bool:
	var e: SimEntity = _w.get_entity(eid)
	if e == null or (e.flags & SimFlags.F_GONE) != 0:
		return false
	if _viewer < 0:
		return true
	var r: int = _w.rel(_viewer, e.owner)
	if r == SimWorld.Rel.SELF or r == SimWorld.Rel.ALLY:
		return true
	return (e.flags & SimFlags.F_INSIDE) == 0 and _w.entity_visible(_viewer, e)


func can_attack(shooter_eid: int, target_eid: int, force: bool) -> bool:
	var s: SimEntity = _w.get_entity(shooter_eid)
	var t: SimEntity = _w.get_entity(target_eid)
	if s == null or t == null:
		return false
	return _w.combat.can_attack(_w, s, t, force)


func order_queue(eid: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var e: SimEntity = _w.get_entity(eid)
	if e == null:
		return 0
	for o: SimOrder in e.orders:
		out.append(o.type)
		out.append(o.x)
		out.append(o.y)
		out.append(o.target_id)
	return e.orders.size()


func range_max(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	if e == null or e.combat == null:
		return 0
	return _w.combat.range_max_eff(_w, e)


func detect_radius(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	if e == null:
		return 0
	if e.kind == SimEntity.Kind.UNIT and e.def_idx >= 0 and e.def_idx < _w.data.units.size():
		return _w.data.units[e.def_idx].detect_radius
	if e.kind == SimEntity.Kind.STRUCTURE and e.def_idx >= 0 and e.def_idx < _w.data.structures.size():
		return _w.data.structures[e.def_idx].detect_radius
	return 0


# ---- production / research -------------------------------------------------------------------------------------------
func _econ() -> SimPlayerEcon:
	var p: SimPlayer = _pl()
	return p.econ if p != null else null


func construction_state(out: PackedInt32Array) -> void:
	out.resize(7)
	out.fill(0)
	out[CS_DEF] = -1
	out[CS_READY_DEF] = -1
	var pe: SimPlayerEcon = _econ()
	if pe == null or pe.cq_def.is_empty():
		return
	var sim_state: int = pe.cq_state
	out[CS_DEF] = pe.cq_def[0]
	out[CS_PROGRESS] = _w.production.q_item_progress_bp(_w, _viewer, 0) / 10
	out[CS_RATE] = pe.rate_bp[SimEconConst.PROD_CONSTRUCTION] / 100
	out[CS_QSTATE] = queue_state_of(sim_state, pe.power_state == SimEconConst.PW_SHORTAGE)
	if sim_state == SimEconConst.QS_READY:
		out[CS_STATE] = Construction.READY_TO_PLACE
		out[CS_READY_DEF] = pe.cq_def[0]
	else:
		out[CS_STATE] = Construction.BUILDING
		var remaining: int = maxi(pe.cq_ticks[0], 1) * 10000 - pe.cq_progress
		var rate: int = maxi(pe.rate_bp[SimEconConst.PROD_CONSTRUCTION], 1)
		out[CS_ETA] = maxi((remaining + rate - 1) / rate, 0)


func construction_queue(out: PackedInt32Array) -> int:
	out.resize(0)
	var pe: SimPlayerEcon = _econ()
	if pe == null:
		return 0
	for i: int in range(1, pe.cq_def.size()):
		out.append(pe.cq_def[i])
	return out.size()


func producers(queue_kind: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var pe: SimPlayerEcon = _econ()
	if pe == null or queue_kind <= 0 or queue_kind >= pe.producer_ids.size():
		return 0
	out.append_array(pe.producer_ids[queue_kind])
	out.sort()
	return out.size()


func queue_of(producer_eid: int, out: PackedInt32Array) -> int:
	return _w.production.queue_of(producer_eid, out)


func queue_info(producer_eid: int, out: PackedInt32Array) -> void:
	out.resize(4)
	out.fill(0)
	var e: SimEntity = _w.get_entity(producer_eid)
	var pe: SimPlayerEcon = _econ()
	if e == null or e.prod == null or pe == null:
		return
	out[QI_PROGRESS] = _w.production.q_item_progress_bp(_w, _viewer, producer_eid) / 10
	var rate: int = pe.rate_bp[e.prod.kind]
	out[QI_RATE] = rate / 100
	out[QI_QSTATE] = queue_state_of(e.prod.head_state, pe.power_state == SimEconConst.PW_SHORTAGE)
	if not e.prod.q_ticks.is_empty():
		var remaining: int = e.prod.q_ticks[0] * 10000 - e.prod.head_progress
		out[QI_ETA] = maxi((remaining + maxi(rate, 1) - 1) / maxi(rate, 1), 0)


func research_state(out: PackedInt32Array) -> void:
	out.resize(0)
	var pe: SimPlayerEcon = _econ()
	if pe == null or pe.rq_def.is_empty():
		out.append_array(PackedInt32Array([-1, 0, 0, QueueState.RUNNING, 0]))
		return
	var rate: int = maxi(pe.rate_bp[SimEconConst.PROD_RESEARCH], 1)
	var remaining: int = maxi(pe.rq_ticks[0], 1) * 10000 - pe.rq_progress
	out.append(pe.rq_def[0])
	out.append(_w.production.q_item_progress_bp(_w, _viewer, -1) / 10)
	out.append(maxi((remaining + rate - 1) / rate, 0))
	out.append(queue_state_of(pe.rq_state, pe.power_state == SimEconConst.PW_SHORTAGE))
	out.append(pe.rq_def.size() - 1)
	for i: int in range(1, pe.rq_def.size()):
		out.append(pe.rq_def[i])


func research_done(res_idx: int) -> bool:
	return _w.production.research_done(_viewer, res_idx)


func check_build(struct_def: int) -> int:
	if _pl() == null:
		return Rule.NOT_ALLOWED
	return rule_of_rsn(_w.production.can_queue_structure(_w, _viewer, struct_def))


func check_place(struct_def: int, ax: int, ay: int, orient: int = 0) -> int:
	if _pl() == null or struct_def < 0 or struct_def >= _w.data.structures.size():
		return Rule.NOT_ALLOWED
	var rsn: int = SimPlacement.validate(_w, _viewer, struct_def, ax, ay, orient, _pres)
	_place_reason = place_reason_of(rsn)
	var r: int = rule_of_rsn(rsn)
	return r


func placement_result(struct_def: int, ax: int, ay: int, orient: int = 0) -> RefCounted:
	if _pl() == null or struct_def < 0 or struct_def >= _w.data.structures.size():
		return null
	SimPlacement.validate(_w, _viewer, struct_def, ax, ay, orient, _pres)
	return _pres


func footprint_rotatable(struct_def: int) -> bool:
	if struct_def < 0 or struct_def >= _w.data.structures.size():
		return false
	var fp: MapFootprint = SimPlacement.footprint_of_def(_w, struct_def)
	return fp != null and fp.rotatable


func place_reason() -> int:
	return _place_reason


func check_train(producer_eid: int, unit_def: int) -> int:
	if _pl() == null:
		return Rule.NOT_ALLOWED
	return rule_of_rsn(_w.production.can_queue_unit(_w, _viewer, producer_eid, unit_def))


func check_research(res_def: int) -> int:
	if _pl() == null:
		return Rule.NOT_ALLOWED
	return rule_of_rsn(_w.production.can_queue_research(_w, _viewer, res_def))


func build_radius_centers(out: PackedInt32Array) -> int:
	out.resize(0)
	if _viewer < 0:
		return 0
	var n: int = 0
	for e: SimEntity in _w.structures_of(_viewer):
		if (e.flags & (SimFlags.F_GONE | SimFlags.F_UNDER_CONSTRUCTION)) != 0 or e.def_idx < 0 or e.def_idx >= _w.data.structures.size():
			continue
		if _w.data.structures[e.def_idx].build_radius > 0 and (e.econ == null or e.econ.st == SimEconConst.ST_ACTIVE):
			out.append(e.x)
			out.append(e.y)
			n += 1
	return n


func sell_value(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	if e == null or e.kind != SimEntity.Kind.STRUCTURE or e.owner != _viewer or (e.flags & (SimFlags.F_GONE | SimFlags.F_SELLING | SimFlags.F_UNDER_CONSTRUCTION)) != 0:
		return 0
	if e.def_idx < 0 or e.def_idx >= _w.data.structures.size():
		return 0
	var s: DefStructure = _w.data.structures[e.def_idx]
	if (s.flags & DefEnums.SF_SELLABLE) == 0:
		return 0
	return e.paid_cost * s.sell_bp / 10000


# ---- powers / superweapon (economy slot records; the strategic system is still a stub) ------------------------------
func _slot_of_power(power_def: int) -> SimPowerSlot:
	var pe: SimPlayerEcon = _econ()
	if pe == null:
		return null
	for i: int in mini(3, pe.slots.size()):
		if pe.slots[i].def_idx == power_def:
			return pe.slots[i]
	return null


func power_slot(power_def: int) -> int:
	var pe: SimPlayerEcon = _econ()
	if pe == null:
		return -1
	for i: int in mini(3, pe.slots.size()):
		if pe.slots[i].def_idx == power_def:
			return i
	return -1


func power_status(power_def: int) -> int:
	var sl: SimPowerSlot = _slot_of_power(power_def)
	var pe: SimPlayerEcon = _econ()
	if sl == null or pe == null or power_def < 0 or power_def >= _w.data.powers.size():
		return PowerStatus.LOCKED_PREREQ
	var d: DefPower = _w.data.powers[power_def]
	for s: int in pe.struct_count.size():
		if s < 63 and (d.requires_mask & (1 << s)) != 0 and pe.struct_count[s] <= 0:
			return PowerStatus.LOCKED_PREREQ
	if _w.tick < sl.ready_tick:
		return PowerStatus.COOLDOWN
	if d.requires_powered and not pe.powers_online:
		return PowerStatus.UNPOWERED
	if credits() < d.cost:
		return PowerStatus.NO_CREDITS
	return PowerStatus.READY


func power_ready_tick(power_def: int) -> int:
	var sl: SimPowerSlot = _slot_of_power(power_def)
	return sl.ready_tick if sl != null else 0


func power_total_cooldown_ticks(power_def: int) -> int:
	return _w.data.powers[power_def].cooldown_t if power_def >= 0 and power_def < _w.data.powers.size() else 0


func power_target_ok(power_def: int, x: int, y: int) -> bool:
	var vis: int = visibility(x >> 10, y >> 10)
	if power_def < 0 or power_def >= _w.data.powers.size():
		return false
	match _w.data.powers[power_def].target_vision:
		DefEnums.TargetVision.ANY:
			return true
		DefEnums.TargetVision.EXPLORED:
			return vis >= Vis.FOG
	return vis == Vis.VISIBLE


func _sw_slot() -> SimPowerSlot:
	var pe: SimPlayerEcon = _econ()
	if pe == null or pe.slots.size() <= SimEconConst.SLOT_SW:
		return null
	return pe.slots[SimEconConst.SLOT_SW]


func sw_status() -> int:
	var sl: SimPowerSlot = _sw_slot()
	if sl == null:
		return SwStatus.NONE
	if sl.pending_attack != 0:
		return SwStatus.WARNING
	match sl.sw_state:
		SimEconConst.SW_CHARGING:
			return SwStatus.CHARGING
		SimEconConst.SW_READY:
			return SwStatus.READY
	return SwStatus.NONE


func sw_def() -> int:
	var sl: SimPowerSlot = _sw_slot()
	if sl != null and sl.def_idx >= 0:
		return sl.def_idx
	var r: DefRoster = roster_of(_viewer)
	return r.superweapon if r != null else -1


func sw_charge_permille() -> int:
	var sl: SimPowerSlot = _sw_slot()
	if sl == null or sl.recharge_ticks <= 0:
		return 0
	return clampi(sl.charge * 1000 / sl.recharge_ticks, 0, 1000)


func sw_ready_tick() -> int:
	var sl: SimPowerSlot = _sw_slot()
	if sl == null:
		return 0
	return _w.tick + maxi(sl.recharge_ticks - sl.charge, 0)


func sw_launcher_eid() -> int:
	var sl: SimPowerSlot = _sw_slot()
	return sl.launcher_id if sl != null else 0


## Flattened from SimStrategicSystem.warnings_affecting(pid, out) once that query exists (economy E7); empty until then.
func strategic_warnings(out: PackedInt32Array) -> int:
	out.resize(0)
	if _viewer < 0 or _w.strategic == null or not _w.strategic.has_method("warnings_affecting"):
		return 0
	var list: Array = []
	_w.strategic.call("warnings_affecting", _viewer, list)
	for wv: Variant in list:
		var w: SimWarning = wv as SimWarning
		if w == null:
			continue
		out.append_array(PackedInt32Array([w.id, w.owner, w.kind, w.src_idx, w.x, w.y, w.x2, w.y2, w.radius, w.width, w.angle, w.exec_tick]))
	return out.size() / WARN_STRIDE


# ---- scripted missions (MIS2) ----------------------------------------------------------------------------------------
func mission_id() -> String:
	return _w.mission.def.id if _w.mission != null else ""


func mission_state(out: PackedInt32Array) -> bool:
	out.clear()
	var m: SimMissionSystem = _w.mission
	if m == null:
		return false
	out.append(m.result)
	out.append(m.result_tick)
	out.append(m.obj_state.size())
	out.append_array(m.obj_state)
	out.append(m.timer_state.size())
	for i: int in m.timer_state.size():
		out.append(m.timer_state[i])
		out.append(m.timer_end[i])
		out.append(m.timer_len[i])
	return true


# ---- map -------------------------------------------------------------------------------------------------------------
func passable(cx: int, cy: int, move_class: int) -> bool:
	return _w.map.in_bounds(cx, cy) and _w.map.passable(cx, cy, move_class)


func deposit_at(cx: int, cy: int) -> int:
	if not _w.map.in_bounds(cx, cy):
		return 0
	var i: int = _w.map.idx(cx, cy)
	var vis: int = visibility(cx, cy)
	if vis == Vis.VISIBLE:
		return _w.map.deposit_at(i)
	if vis == Vis.FOG and i < _w.map.deposit_max.size():
		return _w.map.deposit_max[i]
	return 0


# ---- events ----------------------------------------------------------------------------------------------------------
func take_events() -> PackedInt32Array:
	return _w.events.take()


# ---- row helpers -----------------------------------------------------------------------------------------------------
## Own / allied entities and entities passing the fog rule; anything else must not be read live (fog integrity).
func _known_to_viewer(e: SimEntity) -> bool:
	var r: int = _w.rel(_viewer, e.owner)
	if r == SimWorld.Rel.SELF or r == SimWorld.Rel.ALLY:
		return true
	return (e.flags & SimFlags.F_INSIDE) == 0 and _w.entity_visible(_viewer, e)


## The remembered version of a fogged enemy structure (vision ghost), false if the viewer has no memory of it.
func _read_ghost(eid: int, out: UiEntityRow) -> bool:
	for gv: Variant in _w.fog.ghosts(_viewer):
		var g: SimGhost = gv as SimGhost
		if g != null and g.eid == eid:
			out.clear()
			out.id = eid
			out.def_idx = g.def_idx
			out.owner = g.owner
			out.x = g.x
			out.y = g.y
			out.prev_x = g.x
			out.prev_y = g.y
			out.facing = g.facing
			out.hp = g.hp_pct
			out.hp_max = 100
			out.kind = UiEntityRow.K_STRUCTURE
			out.flags = _GHOST_FLAGS
			return true
	return false

static func _ui_kind(e: SimEntity) -> int:
	match e.kind:
		SimEntity.Kind.UNIT:
			return UiEntityRow.K_UNIT
		SimEntity.Kind.STRUCTURE:
			return UiEntityRow.K_NEUTRAL_STRUCTURE if e.owner < 0 else UiEntityRow.K_STRUCTURE
		SimEntity.Kind.WRECK:
			return UiEntityRow.K_WRECK
	return UiEntityRow.K_NEUTRAL_STRUCTURE


func _ui_flags(e: SimEntity) -> int:
	var f: int = 0
	var fl: int = e.flags
	if e.kind == SimEntity.Kind.STRUCTURE:
		f |= UiEntityRow.F_STRUCT
		if (fl & SimFlags.F_POWERED) == 0 and (fl & SimFlags.F_UNDER_CONSTRUCTION) == 0 and _needs_power(e):
			f |= UiEntityRow.F_UNPOWERED
	if (fl & SimFlags.F_DEPLOYED) != 0:
		f |= UiEntityRow.F_DEPLOYED
	if (fl & SimFlags.F_CLOAKED) != 0:
		f |= UiEntityRow.F_CAMO
	if (fl & (SimFlags.F_EMP_SHUT | SimFlags.F_WEAPONS_OFF)) != 0:
		f |= UiEntityRow.F_EMP
	if (fl & SimFlags.F_INSIDE) != 0:
		f |= UiEntityRow.F_LOADED
	if (fl & SimFlags.F_GARRISONED) != 0:
		f |= UiEntityRow.F_GARRISONED
	if (fl & SimFlags.F_DECOY) != 0 and _w.fog.decoy_identified(_viewer, e):
		f |= UiEntityRow.F_DECOY
	if (fl & SimFlags.F_SUPPRESSED) != 0:
		f |= UiEntityRow.F_SUPPRESSED
	if (fl & SimFlags.F_REPAIR_ON) != 0:
		f |= UiEntityRow.F_REPAIRING
	if (fl & SimFlags.F_SELLING) != 0:
		f |= UiEntityRow.F_SELLING
	if (fl & SimFlags.F_UNDER_CONSTRUCTION) != 0:
		f |= UiEntityRow.F_CONSTRUCTING
	return f


func _needs_power(e: SimEntity) -> bool:
	return e.def_idx >= 0 and e.def_idx < _w.data.structures.size() and _w.data.structures[e.def_idx].power < 0


static func _order_kind(e: SimEntity) -> int:
	if e.orders.is_empty():
		return UiEntityRow.O_PRODUCING if (e.prod != null and not e.prod.q_def.is_empty()) else UiEntityRow.O_IDLE
	match e.orders[0].type:
		SimOrder.T_MOVE, SimOrder.T_PATROL, SimOrder.T_FOLLOW:
			return UiEntityRow.O_MOVING
		SimOrder.T_ATTACK, SimOrder.T_FORCE_FIRE:
			return UiEntityRow.O_ATTACKING
		SimOrder.T_ATTACK_MOVE:
			return UiEntityRow.O_ATTACK_MOVING
		SimOrder.T_GUARD:
			return UiEntityRow.O_GUARDING
		SimOrder.T_HOLD:
			return UiEntityRow.O_HOLDING
		SimOrder.T_HARVEST, SimOrder.T_RETURN_CARGO:
			return UiEntityRow.O_HARVESTING
		SimOrder.T_REPAIR:
			return UiEntityRow.O_REPAIRING
	return UiEntityRow.O_OTHER


func _transport_cap(e: SimEntity) -> int:
	if e.def_idx < 0 or e.def_idx >= _w.data.units.size():
		return 0
	for a: DefAbility in _w.data.units[e.def_idx].abilities:
		if a.kind == DefEnums.AbilityKind.TRANSPORT:
			return int(a.params.get("capacity_squads_n", 0))
	return 0


func _push_snapshot(out: UiEntitySnapshot, e: SimEntity) -> void:
	var k: int = _ui_kind(e)
	var fl: int = _ui_flags(e) | (k << 16)
	out.push(e.id, e.x, e.y, e.def_idx, e.owner, fl, e.hp * 100 / e.hp_max if e.hp_max > 0 else 100)
