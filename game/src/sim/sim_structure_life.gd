class_name SimStructureLife
extends RefCounted
## Structure lifecycle helper (economy 3.4 / 5.3): BUILDUP -> ACTIVE (registration in the owner's counters, power
## and producer lists), sell, HQ undeploy, MCV deploy, derived power gating. Owned by SimEconomySystem
## (`world.economy.life`; the kernel has no `world.life` member). Stateless apart from the per-def tables derived from
## the data at setup (not authoritative, not hashed).

## deactivate() causes.
const DC_SELL: int = 0
const DC_DEATH: int = 1
const DC_OWNER: int = 2
const DC_UNDEPLOY: int = 3
const DC_REMOVED: int = 4

var _pclass: PackedInt32Array = PackedInt32Array()  ## by s_idx: PC_*
var _pkind: PackedInt32Array = PackedInt32Array()  ## by s_idx: PROD_* of the structure's own queue
var _is_hq: PackedByteArray = PackedByteArray()  ## by s_idx: 1 = HQ (build radius > 0)


## Derives the per-def tables from the data (call once, after the data exists).
func setup(world: SimWorld) -> void:
	var n: int = world.data.structures.size()
	_pclass.resize(n)
	_pkind.resize(n)
	_is_hq.resize(n)
	for i: int in n:
		var s: DefStructure = world.data.structures[i]
		var pk: int = SimEconConst.PROD_NONE
		match s.queue_kind:
			DefEnums.QueueKind.INFANTRY:
				pk = SimEconConst.PROD_BARRACKS
			DefEnums.QueueKind.VEHICLE:
				pk = SimEconConst.PROD_FACTORY
			DefEnums.QueueKind.AIRCRAFT:
				pk = SimEconConst.PROD_AIRFIELD
			DefEnums.QueueKind.NAVAL:
				pk = SimEconConst.PROD_DOCK
			DefEnums.QueueKind.COLLECTOR:
				pk = SimEconConst.PROD_REFINERY
		_pkind[i] = pk
		var pc: int = SimEconConst.PC_NONE
		if pk == SimEconConst.PROD_REFINERY:
			pc = SimEconConst.PC_ECON
		elif pk != SimEconConst.PROD_NONE:
			pc = SimEconConst.PC_PRODUCER
		elif (s.flags & DefEnums.SF_STRATEGIC) != 0:
			pc = SimEconConst.PC_STRATEGIC
		elif (s.flags & DefEnums.SF_RELAY) != 0:
			pc = SimEconConst.PC_RELAY
		elif (s.flags & DefEnums.SF_POWERED_DEFENSE) != 0:
			pc = SimEconConst.PC_DEFENSE
		elif s.power < 0:
			pc = SimEconConst.PC_SENSOR
		_pclass[i] = pc
		_is_hq[i] = 1 if s.build_radius > 0 else 0


func power_class_of(s_idx: int) -> int:
	return _pclass[s_idx] if s_idx >= 0 and s_idx < _pclass.size() else SimEconConst.PC_NONE


func prod_kind_of(s_idx: int) -> int:
	return _pkind[s_idx] if s_idx >= 0 and s_idx < _pkind.size() else SimEconConst.PROD_NONE


func is_hq_def(s_idx: int) -> bool:
	return s_idx >= 0 and s_idx < _is_hq.size() and _is_hq[s_idx] == 1


# ---- registration ----
## BUILDUP -> ACTIVE (or a first activation at spawn): registers counters, power, producer lists, pads, the free
## Collector (`first`); `announce` emits EVT_STRUCTURE_ACTIVE (a finished build-up, not a structure that spawns
## active). Idempotent.
func activate(world: SimWorld, ent: SimEntity, first: bool = true, announce: bool = false) -> void:
	var ec: SimCompEcon = ent.econ
	if ec == null:
		return
	ec.st = SimEconConst.ST_ACTIVE
	ec.st_until = 0
	ent.flags &= ~SimFlags.F_UNDER_CONSTRUCTION
	if ent.owner < 0 or ent.owner >= world.players.size() or ec.registered:
		return
	var pe: SimPlayerEcon = world.players[ent.owner].econ
	if pe == null or (ec.flags & (SimEconConst.EF_TEMPORARY | SimEconConst.EF_DECOY | SimEconConst.EF_SUMMON)) != 0:
		return
	ec.registered = true
	var pw: int = 0
	if ent.kind == SimEntity.Kind.STRUCTURE:
		if ent.def_idx >= pe.struct_count.size():
			pe.struct_count.resize(world.data.structures.size())
		pe.struct_count[ent.def_idx] += 1
		if is_hq_def(ent.def_idx):
			pe.active_hq_count += 1
		pw = world.players[ent.owner].view.struct_power[ent.def_idx]
	elif ent.kind == SimEntity.Kind.NEUTRAL:
		pw = int(world.data.neutrals[ent.def_idx].reward.get("power_n", 0))
	ec.power_delta = pw
	pe.power_dirty = true
	pe.rates_dirty = true
	var pk: int = prod_kind_of(ent.def_idx) if ent.kind == SimEntity.Kind.STRUCTURE else SimNeutrals.producer_kind(world, ent)
	if pk != SimEconConst.PROD_NONE:
		_register_producer(world, ent, pe, pk)
	ent.flags = (ent.flags | SimFlags.F_POWERED) if structure_online(world, ent) else (ent.flags & ~SimFlags.F_POWERED)
	if announce:
		world.emit(SimEconConst.EVT_STRUCTURE_ACTIVE, ent.x, ent.y, ent.owner, ent.id, ent.def_idx)
	if first and pk == SimEconConst.PROD_REFINERY:
		_spawn_free_collectors(world, ent)


## Unregisters counters / power / producer lists (sell start, death, capture loss, undeploy). Idempotent.
func deactivate(world: SimWorld, ent: SimEntity, cause: int) -> void:
	_unregister(world, ent, ent.owner)
	if cause == DC_DEATH or cause == DC_REMOVED:
		ent.flags &= ~SimFlags.F_POWERED


## The owner changed (capture): moves counters / power to the new owner and resets the queues of a producer
## (the old owner is refunded the paid head cost).
func owner_changed(world: SimWorld, ent: SimEntity, old_pid: int) -> void:
	var ec: SimCompEcon = ent.econ
	if ec == null:
		return
	if ent.prod != null:
		flush_queue(world, ent, old_pid, true)
	_unregister(world, ent, old_pid)
	ec.cap_pid = -1
	ec.cap_progress = 0
	if ec.st == SimEconConst.ST_ACTIVE:
		activate(world, ent, false)


func _unregister(world: SimWorld, ent: SimEntity, pid: int) -> void:
	var ec: SimCompEcon = ent.econ
	if ec == null or not ec.registered:
		return
	ec.registered = false
	ec.power_delta = 0
	ent.flags &= ~SimFlags.F_POWERED
	if pid < 0 or pid >= world.players.size():
		return
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe == null:
		return
	pe.power_dirty = true
	pe.rates_dirty = true
	if ent.kind == SimEntity.Kind.NEUTRAL:
		var npk: int = SimNeutrals.producer_kind(world, ent)  # a Harbor Terminal's forward Dock queue
		if npk != SimEconConst.PROD_NONE:
			_drop_producer(world, ent, pe, npk)
		return
	if ent.kind != SimEntity.Kind.STRUCTURE:
		return
	if ent.def_idx < pe.struct_count.size():
		pe.struct_count[ent.def_idx] = maxi(pe.struct_count[ent.def_idx] - 1, 0)
	if is_hq_def(ent.def_idx):
		pe.active_hq_count = maxi(pe.active_hq_count - 1, 0)
	var pk: int = prod_kind_of(ent.def_idx)
	if pk != SimEconConst.PROD_NONE:
		_drop_producer(world, ent, pe, pk)


func _drop_producer(world: SimWorld, ent: SimEntity, pe: SimPlayerEcon, pk: int) -> void:
	_remove_id(pe.producer_ids[pk], ent.id)
	_remove_id(pe.producer_flat, ent.id)
	if pk == SimEconConst.PROD_REFINERY:
		_remove_id(pe.refinery_ids, ent.id)
	if ent.prod != null and ent.prod.is_primary:
		ent.prod.is_primary = false
		_elect_primary(world, pe, pk)


func _register_producer(world: SimWorld, ent: SimEntity, pe: SimPlayerEcon, pk: int) -> void:
	var pr: SimCompProd = ent.prod
	var had_primary: bool = false
	for id: int in pe.producer_ids[pk]:
		var o: SimEntity = world.get_entity(id)
		if o != null and o.prod != null and o.prod.is_primary:
			had_primary = true
			break
	_insert_id(pe.producer_ids[pk], ent.id)
	_insert_id(pe.producer_flat, ent.id)
	if pk == SimEconConst.PROD_REFINERY:
		_insert_id(pe.refinery_ids, ent.id)
	if pr != null:
		if not had_primary:
			pr.is_primary = true
		if pk == SimEconConst.PROD_AIRFIELD:
			pr.pad_ent.resize(world.data.structures[ent.def_idx].pads + world.economy.knob(ent.owner, SimEconConst.K_PAD_EXTRA))


## The lowest-id producer of a kind becomes primary when the previous primary left.
func _elect_primary(world: SimWorld, pe: SimPlayerEcon, pk: int) -> void:
	for id: int in pe.producer_ids[pk]:
		var o: SimEntity = world.get_entity(id)
		if o != null and o.prod != null:
			o.prod.is_primary = true
			return


static func _insert_id(arr: PackedInt32Array, id: int) -> void:
	var i: int = arr.bsearch(id)
	if i < arr.size() and arr[i] == id:
		return
	arr.insert(i, id)


static func _remove_id(arr: PackedInt32Array, id: int) -> void:
	var i: int = arr.bsearch(id)
	if i < arr.size() and arr[i] == id:
		arr.remove_at(i)


## Empties a producer's queue. `refund`: the paid head cost goes back to `pid` (sell / capture); false = forfeit.
func flush_queue(world: SimWorld, ent: SimEntity, pid: int, refund: bool) -> void:
	var pr: SimCompProd = ent.prod
	if pr == null:
		return
	var pe: SimPlayerEcon = world.players[pid].econ if pid >= 0 and pid < world.players.size() else null
	if refund and pr.head_paid > 0 and pe != null:
		world.economy.earn(world, pid, pr.head_paid, SimEconConst.CR_REFUND)
	if pr.head_cap_reserved and pe != null and not pr.q_def.is_empty():
		pe.cap_reserved = maxi(pe.cap_reserved - world.players[pid].view.unit_cap_cost[pr.q_def[0]], 0)
	pr.q_def.clear()
	pr.q_cost.clear()
	pr.q_ticks.clear()
	pr.head_progress = 0
	pr.head_paid = 0
	pr.head_state = SimEconConst.QS_EMPTY
	pr.head_cap_reserved = false


func _spawn_free_collectors(world: SimWorld, ent: SimEntity) -> void:
	var p: SimPlayer = world.players[ent.owner]
	var made: PackedInt32Array = p.roster.units_produced_by(ent.def_idx)
	if made.is_empty():
		return
	var org: PackedInt32Array = PackedInt32Array([0, 0])
	SimPlacement.entity_origin(world, ent, org)
	var fp: MapFootprint = SimPlacement.footprint_of_def(world, ent.def_idx)
	var orient: int = ((ent.facing >> 10) & 3) if fp.rotatable else 0
	var cell: int = SimPlacement.exit_cell(world, ent.def_idx, org[0], org[1], orient)
	if cell < 0:
		return
	cell = find_free_cell(world, cell, 4)
	if cell < 0:
		return
	for _i: int in world.data.economy.refinery_free_collectors_n:
		var u: SimEntity = world.spawn_unit(made[0], ent.owner, world.map.center_x(cell), world.map.center_y(cell), 1024, 0, 0, 0, SimEvent.SPAWN_PRODUCED)
		if u != null and u.econ != null:
			u.econ.flags |= SimEconConst.EF_FREE


## Nearest free ground cell (index) to `cell` in ring order, then row-major; -1 if none within max_ring.
func find_free_cell(world: SimWorld, cell: int, max_ring: int) -> int:
	var map: MapData = world.map
	var cx: int = map.cell_x(cell)
	var cy: int = map.cell_y(cell)
	for r: int in range(0, max_ring + 1):
		for y: int in range(cy - r, cy + r + 1):
			var step: int = 1 if (y == cy - r or y == cy + r) else maxi(2 * r, 1)
			var x: int = cx - r
			while x <= cx + r:
				if map.in_bounds(x, y) and map.is_clear(x, y, MapData.LAYER_GROUND):
					return map.idx(x, y)
				x += step
	return -1


# ---- transitions ----
## Stage 2 / 3: every BUILDUP structure whose timer ended becomes ACTIVE (ascending id). Idempotent.
func tick_buildups(world: SimWorld) -> void:
	for e: SimEntity in world.structures:
		var ec: SimCompEcon = e.econ
		if ec != null and ec.st == SimEconConst.ST_BUILDUP and ec.st_until <= world.tick and (e.flags & SimFlags.F_GONE) == 0:
			activate(world, e, true, true)


## Stage 3: completes finished sales and HQ undeploys (ascending id).
func tick_transitions(world: SimWorld) -> void:
	for e: SimEntity in world.structures:
		var ec: SimCompEcon = e.econ
		if ec == null or (e.flags & SimFlags.F_GONE) != 0 or ec.st_until > world.tick:
			continue
		if ec.st == SimEconConst.ST_SELLING:
			_complete_sell(world, e)
		elif ec.st == SimEconConst.ST_UNDEPLOYING:
			_complete_undeploy(world, e)


## Placement command effect (economy 5.3): spawns the structure in BUILDUP (inert, footprint occupied) with the
## paid cost, pushes the placer's units out of the footprint first when `res` (the successful validate result) is
## given, emits EVT_STRUCTURE_PLACED. Returns null when the world refuses the spawn (entity cap). The caller has
## validated and pops its queue head.
func place(world: SimWorld, pid: int, s_idx: int, cx: int, cy: int, rot: int, paid_cost: int, res: SimPlacementResult = null) -> SimEntity:
	if res != null:
		SimPlacement.eject_units(world, pid, res)
	var fp: MapFootprint = SimPlacement.footprint_of_def(world, s_idx)
	var orient: int = (rot & 3) if fp.rotatable else 0
	var x: int = SimPlacement.footprint_center_x(world, s_idx, cx, orient)
	var y: int = SimPlacement.footprint_center_y(world, s_idx, cy, orient)
	var e: SimEntity = world.spawn_structure(s_idx, pid, x, y, orient * 1024, SimFlags.F_UNDER_CONSTRUCTION, paid_cost, 0, SimEvent.SPAWN_PLACED)
	if e != null:
		world.emit(SimEconConst.EVT_STRUCTURE_PLACED, x, y, pid, e.id, s_idx)
	return e


func begin_sell(world: SimWorld, ent: SimEntity) -> int:
	var ec: SimCompEcon = ent.econ
	if ent.kind != SimEntity.Kind.STRUCTURE or ec == null:
		return SimEconConst.RSN_WRONG_KIND
	if (ent.flags & SimFlags.F_GONE) != 0:
		return SimEconConst.RSN_BAD_TARGET
	if ent.owner < 0:
		return SimEconConst.RSN_NOT_OWNER
	if (world.data.structures[ent.def_idx].flags & DefEnums.SF_SELLABLE) == 0:
		return SimEconConst.RSN_NOT_AVAILABLE
	if ec.st == SimEconConst.ST_SELLING or ec.st == SimEconConst.ST_UNDEPLOYING:
		return SimEconConst.RSN_BUSY
	if ec.st == SimEconConst.ST_BUILDUP or (ec.flags & SimEconConst.EF_SELL_LOCKED) != 0:
		return SimEconConst.RSN_LOCKED
	if world.strategic != null and world.strategic.has_method("sell_locked") and world.strategic.call("sell_locked", ent.owner, ent.id):
		return SimEconConst.RSN_LOCKED
	flush_queue(world, ent, ent.owner, true)
	_unregister(world, ent, ent.owner)
	ec.st = SimEconConst.ST_SELLING
	ec.st_until = world.tick + SimEconConst.SELL_TICKS
	ent.flags |= SimFlags.F_SELLING
	world.emit(SimEconConst.EVT_STRUCTURE_SELLING, ent.x, ent.y, ent.owner, ent.id, ec.st_until)
	return SimEconConst.RSN_OK


func begin_undeploy(world: SimWorld, ent: SimEntity) -> int:
	var ec: SimCompEcon = ent.econ
	if ent.kind != SimEntity.Kind.STRUCTURE or ec == null:
		return SimEconConst.RSN_WRONG_KIND
	if (ent.flags & SimFlags.F_GONE) != 0:
		return SimEconConst.RSN_BAD_TARGET
	if ent.owner < 0 or world.data.structures[ent.def_idx].deploy_unit < 0:
		return SimEconConst.RSN_WRONG_KIND
	if ec.st == SimEconConst.ST_SELLING or ec.st == SimEconConst.ST_UNDEPLOYING:
		return SimEconConst.RSN_BUSY
	if ec.st == SimEconConst.ST_BUILDUP:
		return SimEconConst.RSN_LOCKED
	flush_queue(world, ent, ent.owner, true)
	_unregister(world, ent, ent.owner)
	ec.st = SimEconConst.ST_UNDEPLOYING
	ec.st_until = world.tick + SimEconConst.UNDEPLOY_TICKS
	return SimEconConst.RSN_OK


## Replaces the MCV with an HQ in BUILDUP; returns the new HQ id or 0 (EVT_ORDER_FAILED with the reason).
func deploy_mcv(world: SimWorld, mcv: SimEntity) -> int:
	var res: SimPlacementResult = SimPlacementResult.new()
	var reason: int = SimPlacement.validate_hq_site(world, mcv.owner, mcv, res)
	if reason != SimEconConst.RSN_OK:
		world.emit(SimEconConst.EVT_ORDER_FAILED, mcv.x, mcv.y, mcv.owner, mcv.id, SimOrder.T_DEPLOY_MCV, reason)
		return 0
	SimPlacement.eject_units(world, mcv.owner, res)
	var s_idx: int = SimPlacement.hq_def_of_mcv(world, mcv.def_idx)
	var hx: int = SimPlacement.footprint_center_x(world, s_idx, res.ox, 0)
	var hy: int = SimPlacement.footprint_center_y(world, s_idx, res.oy, 0)
	var paid: int = mcv.paid_cost
	var pid: int = mcv.owner
	var hq: SimEntity = world.spawn_structure(s_idx, pid, hx, hy, 0, SimFlags.F_UNDER_CONSTRUCTION, 0, 0, SimEvent.SPAWN_DEPLOYED)
	if hq == null:
		return 0
	world.remove_entity(mcv.id, SimEvent.REM_DEPLOYED)
	var hec: SimCompEcon = hq.econ
	if hec != null:
		hec.mcv_paid_cost = paid
		hec.flags |= SimEconConst.EF_FREE
		var dt: int = world.data.structures[s_idx].deploy_t
		hec.st_until = world.tick + (dt if dt > 0 else SimEconConst.BUILDUP_TICKS)
	world.emit(SimEconConst.EVT_HQ_DEPLOYED, hq.x, hq.y, pid, hq.id)
	return hq.id


## ACTIVE && not shut down && the power rule of its class (economy 5.7).
func structure_online(world: SimWorld, ent: SimEntity) -> bool:
	var ec: SimCompEcon = ent.econ
	if ec == null or ec.st != SimEconConst.ST_ACTIVE or (ent.flags & SimFlags.F_GONE) != 0:
		return false
	if ec.shutdown_until > world.tick:
		return false
	if ent.owner < 0 or world.power == null:
		return true
	match ec.power_class:
		SimEconConst.PC_SENSOR, SimEconConst.PC_RELAY, SimEconConst.PC_STRATEGIC:
			return world.power.powered(ent.owner)
		SimEconConst.PC_DEFENSE:
			return world.power.defenses_online(ent.owner)
	return true


func _complete_sell(world: SimWorld, ent: SimEntity) -> void:
	var refund: int = ent.paid_cost * world.data.structures[ent.def_idx].sell_bp / 10000
	var pid: int = ent.owner
	if refund > 0:
		world.economy.earn(world, pid, refund, SimEconConst.CR_SELL)
	world.emit(SimEconConst.EVT_STRUCTURE_SOLD, ent.x, ent.y, pid, ent.id, refund)
	world.remove_entity(ent.id, SimEvent.REM_SOLD)


func _complete_undeploy(world: SimWorld, ent: SimEntity) -> void:
	var s: DefStructure = world.data.structures[ent.def_idx]
	var org: PackedInt32Array = PackedInt32Array([0, 0])
	SimPlacement.entity_origin(world, ent, org)
	var cell: int = SimPlacement.exit_cell(world, ent.def_idx, org[0], org[1], 0)
	if cell >= 0:
		cell = find_free_cell(world, cell, 6)
	var px: int = world.map.center_x(cell) if cell >= 0 else ent.x
	var py: int = world.map.center_y(cell) if cell >= 0 else ent.y
	var mcv: SimEntity = world.spawn_unit(s.deploy_unit, ent.owner, px, py, 1024, 0, ent.econ.mcv_paid_cost, 0, SimEvent.SPAWN_DEPLOYED)
	if mcv == null:
		return  # entity cap: retry next tick
	world.emit(SimEconConst.EVT_HQ_UNDEPLOYED, ent.x, ent.y, ent.owner, mcv.id)
	world.remove_entity(ent.id, SimEvent.REM_DEPLOYED)
