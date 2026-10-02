class_name SimProductionSystem
extends SimSystem
## Stage 2 (economy 3.3 / 5.1 / 5.3-5.6 / 5.8 / 5.14): the construction queue, the unit queues of the producer
## structures (Barracks, Factory, Airfield, Dock, Refinery = Collector queue) and the player-wide research queue,
## with progressive payment in bp-ticks, the power/knob rate table, prerequisite pauses, unit-cap reservation, exit
## and rally, the airfield pad API, the economy-side research knobs and the executors of commands 120-131.
##
## All queue state is in SimPlayerEcon (cq_* / rq_*) and SimCompProd (hashed there); the system itself is stateless
## apart from a weak world reference for the pid-only queries. Money moves only through SimEconomySystem.spend/earn.

const ADV_ACTIVE: int = 0
const ADV_FUNDS: int = 1
const ADV_DONE: int = 2
const EXIT_RETRY_TICKS: int = 10
const EXIT_SEARCH_RINGS: int = 4
const RESEARCH_QUEUE_LEN: int = 3
const RATE_ONE: int = 10000
const EXIT_FACING: int = 1024

## Economy-side research effects (economy 5.8): research id -> flat [knob, value, ...] writes at completion.
const RESEARCH_KNOBS: Dictionary = {
	"research.napc.dispersed_runways": [SimEconConst.K_PAD_EXTRA, 2],
	"research.pd.integrated_flight_decks": [SimEconConst.K_REARM_RATE_BP, 11765],
	"research.ae.recovery_winches": [SimEconConst.K_SALVAGE_TICKS, 100],
	"research.sap.reserve_capacitors": [SimEconConst.K_SAP_RESERVE_TICKS, 700],
	"research.def.standardized_parts": [SimEconConst.K_REPAIR_COST_ENG_VEH_BP, 8500],
	"research.nec.tunnel_workshops": [SimEconConst.K_REPAIR_RATE_DEF_BP, 12500],
	"research.pd.expeditionary_maintenance": [SimEconConst.K_REPAIR_RATE_TECH_BP, 12500],
	"research.han.modular_servicing": [SimEconConst.K_REPAIR_RATE_TENDER_BP, 15000],
	"research.def.buried_command_lines": [SimEconConst.K_EMP_RECOVERY_STRUCT_BP, 7500],
	"research.han.resilient_mesh": [SimEconConst.K_EMP_RECOVERY_UNMANNED_BP, 7500],
	"research.nec.distributed_control": [SimEconConst.K_RELAY_RADIUS_CELLS, 8, SimEconConst.K_RELAY_HOLD_TICKS, 200],
	"research.han.distributed_cognition": [SimEconConst.K_CMD_RADIUS_CELLS, 7],
}

var _wref: WeakRef = null
var _adv: PackedInt32Array = PackedInt32Array([0, 0])  ## scratch: [progress, paid] after _advance
var _scratch: PackedInt32Array = PackedInt32Array([0, 0])


func _init() -> void:
	stage_no = 2


func init_world(world: SimWorld) -> void:
	_wref = weakref(world)
	for op: int in range(SimCmd.BUILD_START, SimCmd.RESEARCH_HOLD + 1):
		world.commands.register_executor(op, Callable(self, "handle_command"))


# ---------------------------------------------------------------------------------------------------------- stage 2
func update(world: SimWorld) -> void:
	for p: SimPlayer in world.players:
		if p.econ != null and p.eliminated == 0:
			refresh_rates(world, p.pid)
	for p: SimPlayer in world.players:
		var pe: SimPlayerEcon = p.econ
		if pe == null or p.eliminated != 0:
			continue
		var n: int = 2 + pe.producer_flat.size()
		var start: int = (world.tick + p.pid) % n
		for k: int in n:
			var slot: int = (start + k) % n
			if slot == 0:
				_update_construction(world, p, pe)
			elif slot == 1:
				_update_research(world, p, pe)
			elif slot - 2 < pe.producer_flat.size():
				var e: SimEntity = world.get_entity(pe.producer_flat[slot - 2])
				if e != null and e.prod != null and e.econ != null and (e.flags & SimFlags.F_GONE) == 0:
					_update_unit_queue(world, p, pe, e)


## Recomputes SimPlayerEcon.rate_bp from the power state and the production knobs (5.1 worked example: shortage
## 5000 x Mobilization 12500 = 6250). Runs every tick, so an expiring temporary knob needs no notification.
func refresh_rates(world: SimWorld, pid: int) -> void:
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe == null:
		return
	var base: int = world.data.economy.power_shortage_rate_bp if pe.power_state == SimEconConst.PW_SHORTAGE else RATE_ONE
	for k: int in SimEconConst.PROD_COUNT:
		var r: int = base
		if k == SimEconConst.PROD_BARRACKS:
			r = base * SimEconomySystem.knob_of(pe, SimEconConst.K_PROD_RATE_BARRACKS_BP, world.tick) / RATE_ONE
		elif k == SimEconConst.PROD_FACTORY:
			r = base * SimEconomySystem.knob_of(pe, SimEconConst.K_PROD_RATE_FACTORY_BP, world.tick) / RATE_ONE
		pe.rate_bp[k] = r
	pe.rates_dirty = false


## Progressive payment (5.1). Reads/writes nothing but the scratch pair `_adv` = [progress, paid] and the ledger.
func _advance(world: SimWorld, pid: int, cost: int, ticks: int, progress: int, paid: int, rate: int, reason: int) -> int:
	var total: int = maxi(ticks, 1) * RATE_ONE
	var np: int = mini(progress + rate, total)
	var target: int = cost * np / total
	var d: int = target - paid
	if d > 0 and (d > world.players[pid].credits or not world.economy.spend(world, pid, d, reason)):
		_adv[0] = progress
		_adv[1] = paid
		return ADV_FUNDS
	_adv[0] = np
	_adv[1] = paid + maxi(d, 0)
	return ADV_DONE if np >= total else ADV_ACTIVE


func _set_state(world: SimWorld, pid: int, qid: int, old: int, new: int, needed: int = 0) -> int:
	if old != new:
		world.emit(SimEconConst.EVT_QUEUE_STATE, 0, 0, pid, qid, new, 0)
		if new == SimEconConst.QS_PAUSED_FUNDS:
			world.emit(SimEconConst.EVT_INSUFFICIENT_FUNDS, 0, 0, pid, qid, needed)
		elif new == SimEconConst.QS_PAUSED_CAP:
			world.emit(SimEconConst.EVT_UNIT_CAP_REACHED, 0, 0, pid)
	return new


# ---- construction ----
func _update_construction(world: SimWorld, p: SimPlayer, pe: SimPlayerEcon) -> void:
	if pe.cq_def.is_empty():
		pe.cq_state = _set_state(world, p.pid, 0, pe.cq_state, SimEconConst.QS_EMPTY)
		return
	if pe.cq_state == SimEconConst.QS_READY and not pe.cq_hold:
		return
	var s: int = pe.cq_def[0]
	var st: int
	if pe.cq_progress >= maxi(pe.cq_ticks[0], 1) * RATE_ONE:
		st = SimEconConst.QS_READY  # finished, waiting for placement (a hold does not un-finish it)
	elif pe.cq_hold:
		st = SimEconConst.QS_HOLD
	elif pe.active_hq_count == 0 or not prereqs_met(world, p.pid, world.data.structures[s].requires):
		st = SimEconConst.QS_PAUSED_PREREQ
	else:
		var r: int = _advance(world, p.pid, pe.cq_cost[0], pe.cq_ticks[0], pe.cq_progress, pe.cq_paid, pe.rate_bp[SimEconConst.PROD_CONSTRUCTION], SimEconConst.CR_CONSTRUCTION)
		if r == ADV_FUNDS:
			st = SimEconConst.QS_PAUSED_FUNDS
		else:
			pe.cq_progress = _adv[0]
			pe.cq_paid = _adv[1]
			st = SimEconConst.QS_READY if r == ADV_DONE else SimEconConst.QS_ACTIVE
			if r == ADV_DONE:
				world.emit(SimEconConst.EVT_STRUCTURE_READY, 0, 0, p.pid, s)
	var needed: int = pe.cq_cost[0] * (pe.cq_progress + 1) / (maxi(pe.cq_ticks[0], 1) * RATE_ONE) - pe.cq_paid
	pe.cq_state = _set_state(world, p.pid, 0, pe.cq_state, st, needed)


func _pop_construction(pe: SimPlayerEcon) -> void:
	pe.cq_def.remove_at(0)
	pe.cq_cost.remove_at(0)
	pe.cq_ticks.remove_at(0)
	pe.cq_progress = 0
	pe.cq_paid = 0
	pe.cq_state = SimEconConst.QS_ACTIVE if not pe.cq_def.is_empty() else SimEconConst.QS_EMPTY
	if pe.cq_def.is_empty():
		pe.cq_hold = false


# ---- research ----
func _update_research(world: SimWorld, p: SimPlayer, pe: SimPlayerEcon) -> void:
	if pe.rq_def.is_empty():
		pe.rq_state = _set_state(world, p.pid, -1, pe.rq_state, SimEconConst.QS_EMPTY)
		return
	var r_idx: int = pe.rq_def[0]
	var st: int
	if pe.rq_hold:
		st = SimEconConst.QS_HOLD
	elif not research_prereqs_met(world, p.pid, r_idx):
		st = SimEconConst.QS_PAUSED_PREREQ
	else:
		var r: int = _advance(world, p.pid, pe.rq_cost[0], pe.rq_ticks[0], pe.rq_progress, pe.rq_paid, pe.rate_bp[SimEconConst.PROD_RESEARCH], SimEconConst.CR_RESEARCH)
		if r == ADV_FUNDS:
			st = SimEconConst.QS_PAUSED_FUNDS
		else:
			pe.rq_progress = _adv[0]
			pe.rq_paid = _adv[1]
			st = SimEconConst.QS_ACTIVE
			if r == ADV_DONE:
				_complete_research(world, p, pe)
				return
	pe.rq_state = _set_state(world, p.pid, -1, pe.rq_state, st, 1)


func _complete_research(world: SimWorld, p: SimPlayer, pe: SimPlayerEcon) -> void:
	var r_idx: int = pe.rq_def[0]
	pe.rq_def.remove_at(0)
	pe.rq_cost.remove_at(0)
	pe.rq_ticks.remove_at(0)
	pe.rq_progress = 0
	pe.rq_paid = 0
	pe.rq_state = SimEconConst.QS_ACTIVE if not pe.rq_def.is_empty() else SimEconConst.QS_EMPTY
	if pe.rq_def.is_empty():
		pe.rq_hold = false
	if pe.researched[r_idx] == 1:
		return
	pe.researched[r_idx] = 1
	if p.view != null:
		p.view.apply_research(r_idx)
	apply_research_knobs(world, p.pid, r_idx)
	if world.abilities != null and world.abilities.has_method("on_research_complete"):
		world.abilities.call("on_research_complete", p.pid, r_idx)
	world.emit(SimEconConst.EVT_RESEARCH_COMPLETE, 0, 0, p.pid, r_idx)


## Writes the economy knobs of a completed research (idempotent: same values every time).
func apply_research_knobs(world: SimWorld, pid: int, r_idx: int) -> void:
	if r_idx < 0 or r_idx >= world.data.research.size():
		return
	var id: String = world.data.research[r_idx].id
	if not RESEARCH_KNOBS.has(id):
		return
	var writes: Array = RESEARCH_KNOBS[id]
	var i: int = 0
	while i + 1 < writes.size():
		world.economy.set_knob_base(world, pid, int(writes[i]), int(writes[i + 1]))
		i += 2


func research_prereqs_met(world: SimWorld, pid: int, r_idx: int) -> bool:
	var mask: int = world.data.research[r_idx].requires_mask
	var pe: SimPlayerEcon = world.players[pid].econ
	var s: int = 0
	while mask != 0:
		if (mask & 1) != 0 and (s >= pe.struct_count.size() or pe.struct_count[s] <= 0):
			return false
		mask >>= 1
		s += 1
	return true


# ---- unit queues ----
func _update_unit_queue(world: SimWorld, p: SimPlayer, pe: SimPlayerEcon, e: SimEntity) -> void:
	var pr: SimCompProd = e.prod
	if pr.q_def.is_empty():
		pr.head_state = _set_state(world, p.pid, e.id, pr.head_state, SimEconConst.QS_EMPTY)
		return
	var u: int = pr.q_def[0]
	var ud: DefUnit = world.data.units[u]
	var view: DefPlayerView = p.view
	var cap_cost: int = view.unit_cap_cost[u]
	var st: int
	if pr.hold:
		st = SimEconConst.QS_HOLD
	elif e.econ.shutdown_until > world.tick:
		st = SimEconConst.QS_PAUSED_SHUTDOWN
	elif not queue_prereqs_met(world, p.pid, e, ud):
		st = SimEconConst.QS_PAUSED_PREREQ
	elif not pr.head_cap_reserved and cap_cost > 0 and world.economy.unit_cap_room(p.pid) < cap_cost:
		st = SimEconConst.QS_PAUSED_CAP
	elif pr.head_state == SimEconConst.QS_PAUSED_EXIT and world.tick < pr.exit_retry_tick:
		return
	else:
		if not pr.head_cap_reserved and cap_cost > 0:
			pr.head_cap_reserved = true
			pe.cap_reserved += cap_cost
		var r: int = _advance(world, p.pid, pr.q_cost[0], pr.q_ticks[0], pr.head_progress, pr.head_paid, pe.rate_bp[pr.kind], SimEconConst.CR_PRODUCTION)
		if r == ADV_FUNDS:
			st = SimEconConst.QS_PAUSED_FUNDS
		else:
			pr.head_progress = _adv[0]
			pr.head_paid = _adv[1]
			st = SimEconConst.QS_ACTIVE
			if r == ADV_DONE:
				var uid: int = spawn_from_producer(world, e, u, pr.head_paid)
				if uid != 0:
					_pop_unit_head(pe, pr, cap_cost)
					pr.head_state = _set_state(world, p.pid, e.id, pr.head_state, SimEconConst.QS_ACTIVE if not pr.q_def.is_empty() else SimEconConst.QS_EMPTY)
					return
				st = SimEconConst.QS_PAUSED_EXIT
				pr.exit_retry_tick = world.tick + EXIT_RETRY_TICKS
	var needed: int = pr.q_cost[0] * (pr.head_progress + 1) / (maxi(pr.q_ticks[0], 1) * RATE_ONE) - pr.head_paid
	pr.head_state = _set_state(world, p.pid, e.id, pr.head_state, st, needed)


func _pop_unit_head(pe: SimPlayerEcon, pr: SimCompProd, cap_cost: int) -> void:
	if pr.head_cap_reserved:
		pe.cap_reserved = maxi(pe.cap_reserved - cap_cost, 0)
	pr.q_def.remove_at(0)
	pr.q_cost.remove_at(0)
	pr.q_ticks.remove_at(0)
	pr.head_progress = 0
	pr.head_paid = 0
	pr.head_cap_reserved = false
	pr.exit_retry_tick = 0


## Creates the unit at the producer's exit (Airfield: lowest free pad; Dock: nearest free water cell), applies the
## rally point and emits EVT_UNIT_PRODUCED. Returns the entity id, 0 when the exit is blocked (no free cell within
## 4 rings). Does NOT touch the queue or the cap reservation (the caller does).
func spawn_from_producer(world: SimWorld, producer: SimEntity, u_idx: int, paid: int) -> int:
	var pr: SimCompProd = producer.prod
	var ud: DefUnit = world.data.units[u_idx]
	var cell: int = -1
	var pad: int = -1
	if producer.kind == SimEntity.Kind.NEUTRAL:  # Harbor Terminal: units leave over its berth strip
		cell = SimNeutrals.spawn_cell(world, producer, ud.home_layer, EXIT_SEARCH_RINGS)
	else:
		var org: PackedInt32Array = _scratch
		SimPlacement.entity_origin(world, producer, org)
		var fp: MapFootprint = SimPlacement.footprint_of_def(world, producer.def_idx)
		var orient: int = ((producer.facing >> 10) & 3) if fp.rotatable else 0
		if pr != null and pr.kind == SimEconConst.PROD_AIRFIELD:
			for i: int in pr.pad_ent.size():
				if pr.pad_ent[i] == 0:
					pad = i
					break
		if pad >= 0:
			cell = airfield_pad_cell(world, producer.id, pad)
		else:
			var ec: int = SimPlacement.exit_cell(world, producer.def_idx, org[0], org[1], orient)
			if ec < 0:
				return 0
			cell = SimMovement.find_free_cell_near(world, ec, ud.home_layer, EXIT_SEARCH_RINGS)
	if cell < 0:
		return 0
	var u: SimEntity = world.spawn_unit(u_idx, producer.owner, world.map.center_x(cell), world.map.center_y(cell), EXIT_FACING, 0, paid, 0, SimEvent.SPAWN_PRODUCED)
	if u == null:
		return 0
	if pad >= 0:
		pr.pad_ent[pad] = u.id
	world.emit(SimEconConst.EVT_UNIT_PRODUCED, u.x, u.y, producer.owner, u.id, u_idx, producer.id)
	if pad >= 0:
		SimAirSortie.on_aircraft_spawned(world, u, producer.id)  # combat: parked on its pad, fuelled, home set
	_apply_rally(world, producer, u, ud)
	return u.id


func _apply_rally(world: SimWorld, producer: SimEntity, u: SimEntity, ud: DefUnit) -> void:
	var pr: SimCompProd = producer.prod
	if pr == null or not pr.rally_on or ud.home_layer == SimEntity.Layer.AIR:
		return
	if ud.has_ability(DefEnums.AbilityKind.HARVEST):
		if pr.rally_target < 0:
			world.orders.issue_internal(world, u, SimOrder.T_HARVEST, 0, 0, 0, SimOrder.QM_REPLACE, -pr.rally_target)
		return
	world.orders.issue_internal(world, u, SimOrder.T_MOVE, 0, pr.rally_x, pr.rally_y)


## A structure became ACTIVE (called by whoever activates it; the Refinery's free Collector is spawned by
## SimStructureLife.activate): (re)sizes the pad list of an Airfield.
func on_structure_activated(world: SimWorld, ent: SimEntity) -> void:
	if ent.prod != null and ent.prod.kind == SimEconConst.PROD_AIRFIELD:
		var n: int = world.data.structures[ent.def_idx].pads + world.economy.knob(ent.owner, SimEconConst.K_PAD_EXTRA)
		if ent.prod.pad_ent.size() != n:
			ent.prod.pad_ent.resize(n)
			SimAirSortie.on_pads_changed(world, ent)


# ------------------------------------------------------------------------------------------------- validation
func has_active_hq(world: SimWorld, pid: int) -> bool:
	var pe: SimPlayerEcon = world.players[pid].econ
	return pe != null and pe.active_hq_count > 0


func prereqs_met(world: SimWorld, pid: int, req: PackedInt32Array) -> bool:
	var pe: SimPlayerEcon = world.players[pid].econ
	for s: int in req:
		if s < 0 or s >= pe.struct_count.size() or pe.struct_count[s] <= 0:
			return false
	return true


func can_queue_structure(world: SimWorld, pid: int, s_idx: int) -> int:
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe == null or s_idx < 0 or s_idx >= world.data.structures.size():
		return SimEconConst.RSN_INVALID_INDEX
	var d: DefStructure = world.data.structures[s_idx]
	if pe.active_hq_count == 0:
		return SimEconConst.RSN_NO_HQ
	if world.players[pid].view.struct_available[s_idx] == 0:
		return SimEconConst.RSN_NOT_AVAILABLE
	# a prerequisite that is itself waiting in the construction queue does not refuse the enqueue (the item then
	# pauses as PAUSED_PREREQ until the structure is ACTIVE: spec 10.2 S1 queues the whole opening at tick 0)
	for r: int in d.requires:
		if (r < 0 or r >= pe.struct_count.size() or pe.struct_count[r] <= 0) and not pe.cq_def.has(r):
			return SimEconConst.RSN_PREREQ
	if d.superweapon >= 0 and (pe.flags & SimEconConst.PF_SUPERWEAPONS_OFF) != 0:
		return SimEconConst.RSN_FEATURE_OFF
	if d.max_per_player > 0:
		var have: int = pe.struct_count[s_idx]
		for q: int in pe.cq_def:
			if q == s_idx:
				have += 1
		if have + 1 > d.max_per_player:
			return SimEconConst.RSN_STRATEGIC_LIMIT
	if pe.cq_def.size() >= world.data.economy.queue_length_n:
		return SimEconConst.RSN_QUEUE_FULL
	return SimEconConst.RSN_OK


## Prerequisites of a unit at a given producer: the owner's structures, or for a Harbor Terminal's forward queue the
## dock-only rule (SimNeutrals.forward_prereqs_ok).
func queue_prereqs_met(world: SimWorld, pid: int, producer: SimEntity, ud: DefUnit) -> bool:
	if producer.kind == SimEntity.Kind.NEUTRAL:
		return SimNeutrals.forward_prereqs_ok(world, producer, ud)
	return prereqs_met(world, pid, ud.requires)


func can_queue_unit(world: SimWorld, pid: int, producer_id: int, u_idx: int) -> int:
	if u_idx < 0 or u_idx >= world.data.units.size():
		return SimEconConst.RSN_INVALID_INDEX
	var prod: SimEntity = world.get_entity(producer_id)
	if prod == null or (prod.flags & SimFlags.F_GONE) != 0:
		return SimEconConst.RSN_BAD_TARGET
	if prod.owner != pid:
		return SimEconConst.RSN_NOT_OWNER
	if prod.prod == null or prod.econ == null:
		return SimEconConst.RSN_WRONG_KIND
	if prod.econ.st != SimEconConst.ST_ACTIVE or not prod.econ.registered:
		return SimEconConst.RSN_LOCKED
	var ud: DefUnit = world.data.units[u_idx]
	if world.economy.life.prod_kind_of(ud.producer) != prod.prod.kind:
		return SimEconConst.RSN_WRONG_KIND
	if world.players[pid].view.unit_available[u_idx] == 0:
		return SimEconConst.RSN_NOT_AVAILABLE
	if not queue_prereqs_met(world, pid, prod, ud):
		return SimEconConst.RSN_PREREQ
	if prod.prod.q_def.size() >= world.data.economy.queue_length_n:
		return SimEconConst.RSN_QUEUE_FULL
	return SimEconConst.RSN_OK


func can_queue_research(world: SimWorld, pid: int, r_idx: int) -> int:
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe == null or r_idx < 0 or r_idx >= world.data.research.size():
		return SimEconConst.RSN_INVALID_INDEX
	if world.players[pid].view.research_available[r_idx] == 0:
		return SimEconConst.RSN_NOT_AVAILABLE
	if pe.researched[r_idx] == 1 or pe.rq_def.has(r_idx):
		return SimEconConst.RSN_NOT_AVAILABLE
	if not research_prereqs_met(world, pid, r_idx):
		return SimEconConst.RSN_PREREQ
	if pe.rq_def.size() >= RESEARCH_QUEUE_LEN:
		return SimEconConst.RSN_QUEUE_FULL
	return SimEconConst.RSN_OK


# ----------------------------------------------------------------------------------------------- catalog queries
func q_buildable_structures(world: SimWorld, pid: int, out: PackedInt32Array, include_locked: bool) -> void:
	out.clear()
	for s: int in world.players[pid].roster.producible_structures:
		var r: int = can_queue_structure(world, pid, s)
		if r == SimEconConst.RSN_OK or r == SimEconConst.RSN_QUEUE_FULL or (include_locked and (r == SimEconConst.RSN_PREREQ or r == SimEconConst.RSN_NO_HQ)):
			out.append(s)


func q_buildable_units(world: SimWorld, pid: int, producer_id: int, out: PackedInt32Array, include_locked: bool) -> void:
	out.clear()
	var prod: SimEntity = world.get_entity(producer_id)
	if prod == null or prod.prod == null or prod.owner != pid:
		return
	for u: int in world.players[pid].roster.producible_units:
		var r: int = can_queue_unit(world, pid, producer_id, u)
		if r == SimEconConst.RSN_OK or r == SimEconConst.RSN_QUEUE_FULL or (include_locked and r == SimEconConst.RSN_PREREQ):
			out.append(u)


func q_researchable(world: SimWorld, pid: int, out: PackedInt32Array, include_locked: bool) -> void:
	out.clear()
	for r_idx: int in world.players[pid].roster.research_list:
		var r: int = can_queue_research(world, pid, r_idx)
		if r == SimEconConst.RSN_OK or r == SimEconConst.RSN_QUEUE_FULL or (include_locked and r == SimEconConst.RSN_PREREQ):
			out.append(r_idx)


## Primary building first, else the fewest queued items, ties lowest id; 0 = none (or every candidate full).
func q_find_producer(world: SimWorld, pid: int, prod_kind: int, _u_idx: int) -> int:
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe == null or prod_kind <= 0 or prod_kind >= pe.producer_ids.size():
		return 0
	var qmax: int = world.data.economy.queue_length_n
	var best: int = 0
	var best_n: int = 1 << 30
	for id: int in pe.producer_ids[prod_kind]:
		var e: SimEntity = world.get_entity(id)
		if e == null or e.prod == null or (e.flags & SimFlags.F_GONE) != 0 or e.prod.q_def.size() >= qmax:
			continue
		if e.prod.is_primary:
			return id
		if e.prod.q_def.size() < best_n:
			best = id
			best_n = e.prod.q_def.size()
	return best


## 0..10000 for the head item; producer_id 0 = construction, -1 = research.
func q_item_progress_bp(world: SimWorld, pid: int, producer_id: int) -> int:
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe == null:
		return 0
	if producer_id == 0:
		return 0 if pe.cq_def.is_empty() else pe.cq_progress / maxi(pe.cq_ticks[0], 1)
	if producer_id < 0:
		return 0 if pe.rq_def.is_empty() else pe.rq_progress / maxi(pe.rq_ticks[0], 1)
	var e: SimEntity = world.get_entity(producer_id)
	if e == null or e.prod == null or e.prod.q_def.is_empty():
		return 0
	return e.prod.head_progress / maxi(e.prod.q_ticks[0], 1)


func q_rate_bp(pid: int, prod_kind: int) -> int:
	var w: SimWorld = _w()
	if w == null or pid < 0 or pid >= w.players.size() or w.players[pid].econ == null or prod_kind < 0 or prod_kind >= SimEconConst.PROD_COUNT:
		return RATE_ONE
	return w.players[pid].econ.rate_bp[prod_kind]


func q_unit_cost(world: SimWorld, pid: int, u_idx: int) -> int:
	return world.players[pid].view.unit_cost[u_idx]


func q_unit_ticks(world: SimWorld, pid: int, u_idx: int) -> int:
	return world.players[pid].view.unit_ticks[u_idx]


func q_structure_cost(world: SimWorld, pid: int, s_idx: int) -> int:
	return world.players[pid].view.struct_cost[s_idx]


func q_structure_ticks(world: SimWorld, pid: int, s_idx: int) -> int:
	return world.players[pid].view.struct_ticks[s_idx]


## Aliases of economy 3.11: out = [state 0 idle / 1 building / 2 ready / 3 paused, s_idx, progress_pct, ready_s_idx].
func construction_state(pid: int, out: PackedInt32Array) -> void:
	out.resize(4)
	out.fill(0)
	out[3] = -1
	var w: SimWorld = _w()
	if w == null or pid < 0 or pid >= w.players.size() or w.players[pid].econ == null:
		return
	var pe: SimPlayerEcon = w.players[pid].econ
	if pe.cq_def.is_empty():
		return
	out[1] = pe.cq_def[0]
	out[2] = pe.cq_progress / (maxi(pe.cq_ticks[0], 1) * 100)
	match pe.cq_state:
		SimEconConst.QS_READY:
			out[0] = 2
			out[3] = pe.cq_def[0]
		SimEconConst.QS_ACTIVE:
			out[0] = 1
		_:
			out[0] = 3


func queue_of(producer_id: int, out: PackedInt32Array) -> int:
	out.clear()
	var w: SimWorld = _w()
	var e: SimEntity = w.get_entity(producer_id) if w != null else null
	if e == null or e.prod == null:
		return 0
	out.append_array(e.prod.q_def)
	return out.size()


func queue_progress_pct(producer_id: int) -> int:
	var w: SimWorld = _w()
	var e: SimEntity = w.get_entity(producer_id) if w != null else null
	if e == null or e.prod == null or e.prod.q_def.is_empty():
		return 0
	return e.prod.head_progress / (maxi(e.prod.q_ticks[0], 1) * 100)


func research_active(pid: int) -> int:
	var w: SimWorld = _w()
	if w == null or pid < 0 or pid >= w.players.size() or w.players[pid].econ == null or w.players[pid].econ.rq_def.is_empty():
		return -1
	return w.players[pid].econ.rq_def[0]


func research_done(pid: int, r_idx: int) -> bool:
	var w: SimWorld = _w()
	if w == null or pid < 0 or pid >= w.players.size() or w.players[pid].econ == null:
		return false
	var pe: SimPlayerEcon = w.players[pid].econ
	return r_idx >= 0 and r_idx < pe.researched.size() and pe.researched[r_idx] == 1


# ---------------------------------------------------------------------------------------------------- pads (5.14)
func airfield_pad_acquire(world: SimWorld, airfield_id: int, aircraft_id: int) -> int:
	var af: SimEntity = world.get_entity(airfield_id)
	if af == null or af.prod == null or af.econ == null or af.econ.st != SimEconConst.ST_ACTIVE:
		return -1
	var pads: PackedInt32Array = af.prod.pad_ent
	var at: int = pads.find(aircraft_id)
	if at >= 0:
		return at
	for i: int in pads.size():
		if pads[i] == 0:
			pads[i] = aircraft_id
			return i
	return -1


func airfield_pad_release(world: SimWorld, airfield_id: int, aircraft_id: int) -> void:
	var af: SimEntity = world.get_entity(airfield_id)
	if af == null or af.prod == null:
		return
	var i: int = af.prod.pad_ent.find(aircraft_id)
	if i >= 0:
		af.prod.pad_ent[i] = 0


## Map cell index of pad `pad`: the middle footprint row, pads centred along it (a 6x3 airfield with 4 pads uses
## columns 1..4). -1 for an invalid pad.
func airfield_pad_cell(world: SimWorld, airfield_id: int, pad: int) -> int:
	var af: SimEntity = world.get_entity(airfield_id)
	if af == null or af.prod == null or pad < 0 or pad >= af.prod.pad_ent.size():
		return -1
	var fp: MapFootprint = SimPlacement.footprint_of_def(world, af.def_idx)
	var org: PackedInt32Array = PackedInt32Array([0, 0])
	SimPlacement.entity_origin(world, af, org)
	var n: int = af.prod.pad_ent.size()
	var cx: int = org[0] + maxi(fp.w - n, 0) / 2 + pad
	var cy: int = org[1] + fp.h / 2
	return world.map.idx(clampi(cx, 0, world.map.w - 1), clampi(cy, 0, world.map.h - 1))


func airfield_service_rate_bp(world: SimWorld, airfield_id: int) -> int:
	var af: SimEntity = world.get_entity(airfield_id)
	if af == null or af.prod == null or af.econ == null or af.econ.st != SimEconConst.ST_ACTIVE:
		return 0
	if not world.economy.life.structure_online(world, af):
		return 0
	var rate: int = world.economy.knob(af.owner, SimEconConst.K_REARM_RATE_BP)
	if af.prod.rearm_boost_until > world.tick:
		rate = rate * af.prod.rearm_boost_bp / RATE_ONE
	return rate


# --------------------------------------------------------------------------------------------------- commands
## Executor of commands 120-131. Returns a SimCommand.Err; the RSN_* of a refusal is left in cmd.detail.
func handle_command(world: SimWorld, cmd: SimCommand) -> int:
	var pe: SimPlayerEcon = world.players[cmd.pid].econ
	if pe == null:
		return SimCommand.Err.NOT_AVAILABLE
	var rsn: int = SimEconConst.RSN_OK
	match cmd.op:
		SimCmd.BUILD_START:
			rsn = _cmd_build_start(world, pe, cmd)
		SimCmd.BUILD_CANCEL:
			rsn = _cmd_build_cancel(world, pe, cmd)
		SimCmd.BUILD_HOLD:
			pe.cq_hold = cmd.mode != 0 and not pe.cq_def.is_empty()
		SimCmd.BUILD_PLACE:
			rsn = _cmd_build_place(world, pe, cmd)
		SimCmd.TRAIN:
			rsn = _cmd_train(world, cmd)
		SimCmd.TRAIN_CANCEL:
			rsn = _cmd_train_cancel(world, pe, cmd)
		SimCmd.QUEUE_HOLD, SimCmd.SET_RALLY:
			rsn = _cmd_producer_flags(cmd)
		SimCmd.SET_PRIMARY:
			rsn = _cmd_set_primary(world, pe, cmd)
		SimCmd.RESEARCH:
			rsn = _cmd_research(world, pe, cmd)
		SimCmd.RESEARCH_CANCEL:
			rsn = _cmd_research_cancel(world, pe, cmd)
		SimCmd.RESEARCH_HOLD:
			pe.rq_hold = cmd.mode != 0 and not pe.rq_def.is_empty()
		_:
			rsn = SimEconConst.RSN_NOT_AVAILABLE
	if rsn == SimEconConst.RSN_OK:
		return SimCommand.Err.OK
	cmd.detail = rsn
	return SimEconomySystem.err_of(rsn)


func _cmd_build_start(world: SimWorld, pe: SimPlayerEcon, cmd: SimCommand) -> int:
	var n: int = maxi(cmd.count, 1)
	if n > world.data.economy.queue_length_n:
		return SimEconConst.RSN_QUEUE_FULL
	var view: DefPlayerView = world.players[cmd.pid].view
	for i: int in n:
		var r: int = can_queue_structure(world, cmd.pid, cmd.def)  # re-evaluated with the copies queued so far
		if r != SimEconConst.RSN_OK:
			# all-or-nothing: undo the copies of this command
			for _j: int in i:
				pe.cq_def.remove_at(pe.cq_def.size() - 1)
				pe.cq_cost.remove_at(pe.cq_cost.size() - 1)
				pe.cq_ticks.remove_at(pe.cq_ticks.size() - 1)
			return r
		pe.cq_def.append(cmd.def)
		pe.cq_cost.append(view.struct_cost[cmd.def])
		pe.cq_ticks.append(view.struct_ticks[cmd.def])
	if pe.cq_state == SimEconConst.QS_EMPTY:
		pe.cq_state = SimEconConst.QS_ACTIVE
	return SimEconConst.RSN_OK


func _cmd_build_cancel(world: SimWorld, pe: SimPlayerEcon, cmd: SimCommand) -> int:
	if cmd.mode < 0 or cmd.mode >= pe.cq_def.size():
		return SimEconConst.RSN_INVALID_INDEX
	if cmd.mode > 0:
		pe.cq_def.remove_at(cmd.mode)
		pe.cq_cost.remove_at(cmd.mode)
		pe.cq_ticks.remove_at(cmd.mode)
		return SimEconConst.RSN_OK
	if pe.cq_paid > 0:
		world.economy.earn(world, cmd.pid, pe.cq_paid, SimEconConst.CR_REFUND)
	_pop_construction(pe)
	return SimEconConst.RSN_OK


func _cmd_build_place(world: SimWorld, pe: SimPlayerEcon, cmd: SimCommand) -> int:
	if pe.cq_def.is_empty() or pe.cq_state != SimEconConst.QS_READY or pe.cq_def[0] != cmd.def:
		return SimEconConst.RSN_NOT_READY
	var res: SimPlacementResult = SimPlacementResult.new()
	var reason: int = SimPlacement.validate(world, cmd.pid, cmd.def, cmd.x, cmd.y, cmd.mode, res)
	if reason != SimEconConst.RSN_OK:
		world.emit(SimEconConst.EVT_PLACE_REJECTED, 0, 0, cmd.pid, cmd.def, reason)
		return reason
	var e: SimEntity = world.economy.life.place(world, cmd.pid, cmd.def, cmd.x, cmd.y, cmd.mode, pe.cq_paid, res)
	if e == null:
		return SimEconConst.RSN_BUSY
	_pop_construction(pe)
	return SimEconConst.RSN_OK


func _cmd_train(world: SimWorld, cmd: SimCommand) -> int:
	if cmd.def < 0 or cmd.def >= world.data.units.size():
		return SimEconConst.RSN_INVALID_INDEX
	var pid: int = cmd.pid
	var prod_id: int = cmd.target
	if prod_id == 0:
		prod_id = q_find_producer(world, pid, world.economy.life.prod_kind_of(world.data.units[cmd.def].producer), cmd.def)
		if prod_id == 0:
			return SimEconConst.RSN_NOT_AVAILABLE
	var n: int = maxi(cmd.count, 1)
	var r: int = can_queue_unit(world, pid, prod_id, cmd.def)
	if r != SimEconConst.RSN_OK:
		return r
	var pr: SimCompProd = world.get_entity(prod_id).prod
	if pr.q_def.size() + n > world.data.economy.queue_length_n:
		return SimEconConst.RSN_QUEUE_FULL
	var view: DefPlayerView = world.players[pid].view
	for _i: int in n:
		pr.q_def.append(cmd.def)
		pr.q_cost.append(view.unit_cost[cmd.def])
		pr.q_ticks.append(view.unit_ticks[cmd.def])
	if pr.head_state == SimEconConst.QS_EMPTY:
		pr.head_state = SimEconConst.QS_ACTIVE
	return SimEconConst.RSN_OK


func _own_producer(world: SimWorld, pid: int, id: int) -> SimEntity:
	var e: SimEntity = world.get_entity(id)
	if e == null or (e.flags & SimFlags.F_GONE) != 0 or e.prod == null or e.owner != pid:
		return null
	return e


func _cmd_train_cancel(world: SimWorld, pe: SimPlayerEcon, cmd: SimCommand) -> int:
	var e: SimEntity = _own_producer(world, cmd.pid, cmd.target)
	if e == null:
		return SimEconConst.RSN_BAD_TARGET
	var pr: SimCompProd = e.prod
	if cmd.mode < 0 or cmd.mode >= pr.q_def.size():
		return SimEconConst.RSN_INVALID_INDEX
	if cmd.mode > 0:
		pr.q_def.remove_at(cmd.mode)
		pr.q_cost.remove_at(cmd.mode)
		pr.q_ticks.remove_at(cmd.mode)
		return SimEconConst.RSN_OK
	if pr.head_paid > 0:
		world.economy.earn(world, cmd.pid, pr.head_paid, SimEconConst.CR_REFUND)
	_pop_unit_head(pe, pr, world.players[cmd.pid].view.unit_cap_cost[pr.q_def[0]])
	pr.head_state = SimEconConst.QS_ACTIVE if not pr.q_def.is_empty() else SimEconConst.QS_EMPTY
	if pr.q_def.is_empty():
		pr.hold = false
	return SimEconConst.RSN_OK


func _cmd_producer_flags(cmd: SimCommand) -> int:
	var any: bool = false
	for e: SimEntity in cmd.actors:
		if e.prod == null:
			continue
		any = true
		if cmd.op == SimCmd.QUEUE_HOLD:
			e.prod.hold = cmd.mode != 0
		else:
			var clear: bool = (cmd.flags & 1) != 0
			e.prod.rally_on = not clear
			e.prod.rally_x = 0 if clear else cmd.x
			e.prod.rally_y = 0 if clear else cmd.y
			e.prod.rally_target = 0 if clear else cmd.target
	return SimEconConst.RSN_OK if any else SimEconConst.RSN_WRONG_KIND


func _cmd_set_primary(world: SimWorld, pe: SimPlayerEcon, cmd: SimCommand) -> int:
	var e: SimEntity = _own_producer(world, cmd.pid, cmd.target)
	if e == null:
		return SimEconConst.RSN_BAD_TARGET
	if e.econ == null or e.econ.st != SimEconConst.ST_ACTIVE or not e.econ.registered:
		return SimEconConst.RSN_LOCKED
	for id: int in pe.producer_ids[e.prod.kind]:
		var o: SimEntity = world.get_entity(id)
		if o != null and o.prod != null:
			o.prod.is_primary = id == e.id
	return SimEconConst.RSN_OK


func _cmd_research(world: SimWorld, pe: SimPlayerEcon, cmd: SimCommand) -> int:
	var r: int = can_queue_research(world, cmd.pid, cmd.def)
	if r != SimEconConst.RSN_OK:
		return r
	var rd: DefResearch = world.data.research[cmd.def]
	pe.rq_def.append(cmd.def)
	pe.rq_cost.append(rd.cost)
	pe.rq_ticks.append(rd.time_t)
	if pe.rq_state == SimEconConst.QS_EMPTY:
		pe.rq_state = SimEconConst.QS_ACTIVE
	return SimEconConst.RSN_OK


func _cmd_research_cancel(world: SimWorld, pe: SimPlayerEcon, cmd: SimCommand) -> int:
	if cmd.mode < 0 or cmd.mode >= pe.rq_def.size():
		return SimEconConst.RSN_INVALID_INDEX
	if cmd.mode == 0 and pe.rq_paid > 0:
		world.economy.earn(world, cmd.pid, pe.rq_paid, SimEconConst.CR_REFUND)
	pe.rq_def.remove_at(cmd.mode)
	pe.rq_cost.remove_at(cmd.mode)
	pe.rq_ticks.remove_at(cmd.mode)
	if cmd.mode == 0:
		pe.rq_progress = 0
		pe.rq_paid = 0
		pe.rq_state = SimEconConst.QS_ACTIVE if not pe.rq_def.is_empty() else SimEconConst.QS_EMPTY
	if pe.rq_def.is_empty():
		pe.rq_hold = false
	return SimEconConst.RSN_OK


func _w() -> SimWorld:
	return _wref.get_ref() as SimWorld if _wref != null else null
