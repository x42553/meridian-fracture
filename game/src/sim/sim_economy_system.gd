class_name SimEconomySystem
extends SimSystem
## Stage 3 and the public facade of the economy (economy 3.2 / 5.1 / 5.3 / 5.7). Owns: the credits ledger API over
## the kernel ledger, player records, the unit-cap room, the income ring and statistics, the knob table, the
## SimWorld hooks (mapped onto SimSystem on_spawn / on_dying / on_remove / on_owner_changed), sell / HQ undeploy
## completion, BUILDUP -> ACTIVE, the power balance, neutral income and power. The structure lifecycle helper is
## `life` (SimStructureLife); placement is the static SimPlacement.
##
## The credits balance is `SimPlayer.credits` (kernel ledger): spend / earn are thin wrappers over
## world.try_spend / world.add_credits that add the per-category statistics, the income ring and the economy events.
## Handicap scaling of HARVEST / SALVAGE / DEPOT income is the kernel's (SimPlayer.income_frac).

## SimSystem rule: no strong world reference. The pid-only queries of the spec use this weak one.
var _wref: WeakRef = null
var life: SimStructureLife = SimStructureLife.new()
var deposits: SimDepositTable = SimDepositTable.new()  ## deposit fields of the map (economy E5)
var docks: SimEconomyDocks = SimEconomyDocks.new()  ## refinery dock protocol (economy E5)


func _init() -> void:
	stage_no = 3


# ---- setup ----
func init_world(world: SimWorld) -> void:
	_wref = weakref(world)
	life.setup(world)
	deposits.setup(world.map, world.data.economy)
	if world.strategic == null:
		world.strategic = SimStrategicSystem.new()
	world.strategic.setup(world)
	for p: SimPlayer in world.players:
		if p.controller != SimPlayer.Controller.NONE:
			init_player(world, p.pid, p.roster_idx)
	for op: int in [SimCmd.SELL, SimCmd.SET_STRUCT_REPAIR, SimCmd.UNDEPLOY_HQ, SimCmd.DEPLOY]:
		world.commands.register_executor(op, Callable(self, "handle_command"))
	world.orders.register_handler(SimOrder.T_DEPLOY_MCV, SimOrderDeploy.new())
	world.orders.register_handler(SimOrder.T_CAPTURE, SimOrderCapture.new())
	world.orders.register_handler(SimOrder.T_REPAIR, SimOrderRepair.new())
	world.orders.register_handler(SimOrder.T_SALVAGE, SimOrderSalvage.new())
	var harvest: SimOrderHarvest = SimOrderHarvest.new(SimOrder.T_HARVEST)
	world.orders.register_handler(SimOrder.T_HARVEST, harvest)
	world.orders.register_handler(SimOrder.T_RETURN_CARGO, SimOrderHarvest.new(SimOrder.T_RETURN_CARGO))
	world.orders.register_idle(harvest)


## Creates the economy record of a player. Start credits were given by the kernel (rules.start_credits x
## handicap); `start_credits` >= 0 overrides them (scaled by `handicap_pct`).
func init_player(world: SimWorld, pid: int, roster_idx: int, start_credits: int = -1, handicap_pct: int = 100) -> void:
	var p: SimPlayer = world.players[pid]
	var pe: SimPlayerEcon = SimPlayerEcon.new()
	p.econ = pe
	pe.pid = pid
	pe.roster_idx = roster_idx
	pe.unit_cap = world.rules.unit_cap
	pe.struct_count.resize(world.data.structures.size())
	pe.field_danger.resize(deposits.count)
	pe.researched.resize(world.data.research.size())
	pe.income_ring_epoch = world.tick / SimEconConst.INCOME_BUCKET_TICKS
	pe.income_ring_idx = pe.income_ring_epoch % SimEconConst.INCOME_BUCKETS
	if start_credits >= 0:
		p.credits = start_credits * handicap_pct / 100
	var fcode: String = ""
	if p.roster != null and p.roster.faction >= 0 and p.roster.faction < world.data.factions.size():
		fcode = world.data.factions[p.roster.faction].code
	match fcode:
		"SAP":
			pe.flags |= SimEconConst.PF_SAP_RESERVE
			pe.knob_base[SimEconConst.K_SAP_RESERVE_TICKS] = 400
			pe.reserve_max = 400
			pe.reserve_left = 400
		"AE":
			pe.flags |= SimEconConst.PF_CAN_SALVAGE
		"PD":
			pe.flags |= SimEconConst.PF_AMPHIBIOUS_COLLECTORS
	if world.rules.superweapons == 0:
		pe.flags |= SimEconConst.PF_SUPERWEAPONS_OFF
	if p.roster != null:
		for i: int in mini(p.roster.power_list.size(), SimEconConst.SLOT_SW):
			pe.slots[i].def_idx = p.roster.power_list[i]
		if world.rules.superweapons != 0:
			pe.slots[SimEconConst.SLOT_SW].def_idx = p.roster.superweapon


# ---- stage 3 ----
func update(world: SimWorld) -> void:
	life.tick_buildups(world)
	life.tick_transitions(world)
	deposits.update(world)
	docks.watchdog(world)
	SimEconomyWork.update(world)
	SimNeutrals.update(world)
	_neutral_income(world)
	_power_balance(world)
	for p: SimPlayer in world.players:
		if p.econ != null:
			_advance_ring(p.econ, world.tick)


## Balance = sum over registered structures of the owner (supply +delta, demand -delta), recomputed for players
## marked dirty and for everybody every POWER_RECHECK_TICKS.
func _power_balance(world: SimWorld) -> void:
	var all: bool = world.tick % SimEconConst.POWER_RECHECK_TICKS == 0
	var need: bool = all
	if not need:
		for p: SimPlayer in world.players:
			if p.econ != null and p.econ.power_dirty:
				need = true
				break
	if not need:
		return
	var n: int = world.players.size()
	var sup: PackedInt32Array = PackedInt32Array()
	var dem: PackedInt32Array = PackedInt32Array()
	sup.resize(n)
	dem.resize(n)
	for e: SimEntity in world.structures:
		_accumulate(e, sup, dem)
	for e: SimEntity in world.neutrals:
		_accumulate(e, sup, dem)
	for p: SimPlayer in world.players:
		var pe: SimPlayerEcon = p.econ
		if pe == null or not (all or pe.power_dirty):
			continue
		pe.power_supply = sup[p.pid]
		pe.power_demand = dem[p.pid]
		pe.power_dirty = false


func _accumulate(e: SimEntity, sup: PackedInt32Array, dem: PackedInt32Array) -> void:
	var ec: SimCompEcon = e.econ
	if ec == null or not ec.registered or e.owner < 0 or e.owner >= sup.size() or (e.flags & SimFlags.F_GONE) != 0:
		return
	if ec.power_delta > 0:
		sup[e.owner] += ec.power_delta
	else:
		dem[e.owner] -= ec.power_delta


## Player-owned neutral structures with an income reward (Salvage Depot): the milli-credit accumulator pays out
## whole payouts of NEUTRAL_PAY credits.
func _neutral_income(world: SimWorld) -> void:
	for e: SimEntity in world.neutrals:
		var ec: SimCompEcon = e.econ
		if ec == null or not ec.registered or e.owner < 0 or (e.flags & SimFlags.F_GONE) != 0:
			continue
		var mcpt: int = int(world.data.neutrals[e.def_idx].reward.get("income_mcpt", 0))
		if mcpt <= 0:
			continue
		ec.income_acc += mcpt
		if ec.income_acc >= 50000:
			var pay: int = ec.income_acc / 1000
			ec.income_acc -= pay * 1000
			earn(world, e.owner, pay, SimEconConst.CR_DEPOT, e.x, e.y)


func _advance_ring(pe: SimPlayerEcon, tick: int) -> void:
	var epoch: int = tick / SimEconConst.INCOME_BUCKET_TICKS
	if epoch == pe.income_ring_epoch:
		return
	var steps: int = mini(epoch - pe.income_ring_epoch, SimEconConst.INCOME_BUCKETS)
	var idx: int = pe.income_ring_idx
	for _i: int in steps:
		idx = (idx + 1) % SimEconConst.INCOME_BUCKETS
		pe.income_ring[idx] = 0
	pe.income_ring_epoch = epoch
	pe.income_ring_idx = epoch % SimEconConst.INCOME_BUCKETS


# ---- commands ----
## SELL, SET_STRUCT_REPAIR, UNDEPLOY_HQ, DEPLOY (registered in init_world; DEPLOY only unfolds MCVs: an MCV gets a
## T_DEPLOY_MCV order, another unit type is refused with WRONG_KIND unless a later domain replaces the executor).
## Returns a SimCommand.Err; the RSN_* of the last refusal is left in cmd.detail.
func handle_command(world: SimWorld, cmd: SimCommand) -> int:
	var any_ok: bool = false
	var last: int = SimEconConst.RSN_OK
	for e: SimEntity in cmd.actors:
		var r: int = SimEconConst.RSN_OK
		match cmd.op:
			SimCmd.DEPLOY:
				if SimPlacement.hq_def_of_mcv(world, e.def_idx) < 0:
					r = SimEconConst.RSN_WRONG_KIND
				elif world.orders.issue(world, e, SimOrder.make(SimOrder.T_DEPLOY_MCV), SimOrder.QM_REPLACE) != SimCommand.Err.OK:
					r = SimEconConst.RSN_NOT_AVAILABLE
			SimCmd.SELL:
				r = life.begin_sell(world, e)
			SimCmd.UNDEPLOY_HQ:
				r = life.begin_undeploy(world, e)
			SimCmd.SET_STRUCT_REPAIR:
				r = _set_repair(world, e, cmd.mode)
			_:
				r = SimEconConst.RSN_NOT_AVAILABLE
		if r == SimEconConst.RSN_OK:
			any_ok = true
		else:
			last = r
	if any_ok:
		return SimCommand.Err.OK
	cmd.detail = last
	return err_of(last)


func _set_repair(world: SimWorld, e: SimEntity, mode: int) -> int:
	var ec: SimCompEcon = e.econ
	if e.kind != SimEntity.Kind.STRUCTURE or ec == null:
		return SimEconConst.RSN_WRONG_KIND
	if ec.st != SimEconConst.ST_ACTIVE or (world.data.structures[e.def_idx].flags & DefEnums.SF_REPAIRABLE) == 0 \
			or (ec.flags & SimEconConst.EF_NO_REPAIR) != 0:
		return SimEconConst.RSN_DECOY if (ec.flags & SimEconConst.EF_NO_REPAIR) != 0 else SimEconConst.RSN_NOT_AVAILABLE
	var on: bool = (not ec.repair_on) if mode == 2 else mode == 1
	if on != ec.repair_on:
		ec.repair_on = on
		e.flags = (e.flags | SimFlags.F_REPAIR_ON) if on else (e.flags & ~SimFlags.F_REPAIR_ON)
		world.emit(SimEconConst.EVT_REPAIR_STATE, e.x, e.y, e.owner, e.id, 1 if on else 0)
	return SimEconConst.RSN_OK


## RSN_* -> SimCommand.Err (what CMD_REJECTED carries; the RSN itself goes to cmd.detail).
static func err_of(rsn: int) -> int:
	match rsn:
		SimEconConst.RSN_OK:
			return SimCommand.Err.OK
		SimEconConst.RSN_NOT_OWNER, SimEconConst.RSN_WRONG_KIND:
			return SimCommand.Err.WRONG_KIND
		SimEconConst.RSN_NOT_AVAILABLE, SimEconConst.RSN_INVALID_INDEX, SimEconConst.RSN_FEATURE_OFF:
			return SimCommand.Err.NOT_AVAILABLE
		SimEconConst.RSN_PREREQ, SimEconConst.RSN_NO_HQ:
			return SimCommand.Err.NO_PREREQ
		SimEconConst.RSN_QUEUE_FULL:
			return SimCommand.Err.QUEUE_FULL
		SimEconConst.RSN_NO_CREDITS:
			return SimCommand.Err.NO_CREDITS
		SimEconConst.RSN_UNIT_CAP:
			return SimCommand.Err.UNIT_CAP
		SimEconConst.RSN_NOT_READY:
			return SimCommand.Err.NOT_READY
		SimEconConst.RSN_BAD_TARGET:
			return SimCommand.Err.NO_TARGET
		SimEconConst.RSN_NO_VISION, SimEconConst.RSN_NOT_EXPLORED:
			return SimCommand.Err.NO_VISION
		SimEconConst.RSN_BUSY, SimEconConst.RSN_LOCKED, SimEconConst.RSN_HOLD, SimEconConst.RSN_NO_POWER:
			return SimCommand.Err.BLOCKED
	if rsn >= SimEconConst.RSN_OUT_OF_RADIUS and rsn <= SimEconConst.RSN_APRON:
		return SimCommand.Err.BAD_SITE
	return SimCommand.Err.NOT_ALLOWED


# ---- ledger: the ONLY functions that change credits ----
func credits(pid: int) -> int:
	var w: SimWorld = _w()
	return w.players[pid].credits if w != null and pid >= 0 and pid < w.players.size() else 0


func can_afford(pid: int, amount: int) -> bool:
	return credits(pid) >= amount


## All-or-nothing; false (no change) if credits < amount. Progressive-payment reasons are silent (no CASH event per
## tick); the per-category statistic is updated here.
func spend(world: SimWorld, pid: int, amount: int, reason: int) -> bool:
	if amount < 0 or pid < 0 or pid >= world.players.size():
		return false
	if amount == 0:
		return true
	var silent: bool = reason == SimEconConst.CR_CONSTRUCTION or reason == SimEconConst.CR_PRODUCTION \
		or reason == SimEconConst.CR_RESEARCH or reason == SimEconConst.CR_REPAIR
	if not world.try_spend(pid, amount, SimEvent.CASH_SPEND, 0, silent):
		return false
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe != null:
		match reason:
			SimEconConst.CR_CONSTRUCTION:
				pe.stat_spent_construction += amount
			SimEconConst.CR_PRODUCTION:
				pe.stat_spent_units += amount
			SimEconConst.CR_RESEARCH:
				pe.stat_spent_research += amount
			SimEconConst.CR_POWER_USE:
				pe.stat_spent_powers += amount
			SimEconConst.CR_REPAIR:
				pe.stat_spent_repair += amount
	return true


## Credits `amount` (handicap-scaled for HARVEST / SALVAGE / DEPOT by the kernel). Only those three feed the income
## ring; refunds and sells do not. EVT_CREDITS_GAINED when a position (ex, ey) is given.
func earn(world: SimWorld, pid: int, amount: int, reason: int, ex: int = 0, ey: int = 0) -> void:
	if amount <= 0 or pid < 0 or pid >= world.players.size():
		return
	var cash: int = SimEconConst.CR_TO_CASH[reason] if reason >= 0 and reason < SimEconConst.CR_TO_CASH.size() else SimEvent.CASH_SCRIPT
	var credited: int = world.add_credits(pid, amount, cash, ex, ey)
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe == null:
		return
	match reason:
		SimEconConst.CR_HARVEST:
			pe.stat_harvested += credited
		SimEconConst.CR_SALVAGE:
			pe.stat_salvaged += credited
		SimEconConst.CR_DEPOT:
			pe.stat_depot += credited
		SimEconConst.CR_REFUND:
			pe.stat_refunded += credited
		SimEconConst.CR_SELL:
			pe.stat_sold += credited
	if reason == SimEconConst.CR_HARVEST or reason == SimEconConst.CR_SALVAGE or reason == SimEconConst.CR_DEPOT:
		_advance_ring(pe, world.tick)
		pe.income_ring[pe.income_ring_idx] += credited
		if credited > 0 and (ex != 0 or ey != 0):
			world.emit(SimEconConst.EVT_CREDITS_GAINED, ex, ey, pid, credited, ex, ey)


## Aliases of economy 3.11 (abilities / combat specs).
func try_spend(pid: int, amount: int) -> bool:
	var w: SimWorld = _w()
	return w != null and spend(w, pid, amount, SimEconConst.CR_OTHER)


func add(pid: int, amount: int) -> void:
	var w: SimWorld = _w()
	if w != null:
		earn(w, pid, amount, SimEconConst.CR_OTHER)


## Monotonic income total (harvest + salvage + depot) for AI income deltas.
func income_total(pid: int) -> int:
	var pe: SimPlayerEcon = _pe(pid)
	return pe.stat_harvested + pe.stat_salvaged + pe.stat_depot if pe != null else 0


func power_supply(pid: int) -> int:
	var pe: SimPlayerEcon = _pe(pid)
	return pe.power_supply if pe != null else 0


func power_demand(pid: int) -> int:
	var pe: SimPlayerEcon = _pe(pid)
	return pe.power_demand if pe != null else 0


## cap - live - reserved (may be <= 0).
func unit_cap_room(pid: int) -> int:
	var w: SimWorld = _w()
	var pe: SimPlayerEcon = _pe(pid)
	if w == null or pe == null:
		return 0
	return pe.unit_cap - w.players[pid].unit_count - pe.cap_reserved


# ---- knobs (economy 4.5) ----
## Effective value of knob k for the pid at the current tick.
func knob(pid: int, k: int) -> int:
	var w: SimWorld = _w()
	var pe: SimPlayerEcon = _pe(pid)
	if pe == null or k < 0 or k >= SimEconConst.K_COUNT:
		return SimEconConst.KNOB_DEFAULT[k] if k >= 0 and k < SimEconConst.K_COUNT else 0
	return knob_of(pe, k, w.tick if w != null else 0)


static func knob_of(pe: SimPlayerEcon, k: int, tick: int) -> int:
	var base: int = pe.knob_base[k]
	if pe.knob_until[k] <= tick:
		return base
	var temp: int = pe.knob_temp[k]
	match SimEconConst.KNOB_MODE[k]:
		SimEconConst.KM_MUL:
			return base * temp / SimEconConst.KNOB_NEUTRAL_MUL
		SimEconConst.KM_ADD:
			return base + temp
		SimEconConst.KM_OVR:
			return temp
		SimEconConst.KM_MIN:
			return mini(base, temp)
	return base


## Roster / research write. K_SAP_RESERVE_TICKS: a full reserve becomes the new maximum (5.7).
func set_knob_base(world: SimWorld, pid: int, k: int, value: int) -> void:
	var pe: SimPlayerEcon = _pe(pid)
	if pe == null or k < 0 or k >= SimEconConst.K_COUNT:
		return
	var old_max: int = pe.reserve_max
	pe.knob_base[k] = value
	if k == SimEconConst.K_SAP_RESERVE_TICKS and (pe.flags & SimEconConst.PF_SAP_RESERVE) != 0:
		pe.reserve_max = value
		if pe.reserve_left == old_max:
			pe.reserve_left = value
	elif k == SimEconConst.K_PAD_EXTRA:
		for id: int in pe.producer_ids[SimEconConst.PROD_AIRFIELD]:
			var e: SimEntity = world.get_entity(id)
			if e != null and e.prod != null:
				e.prod.pad_ent.resize(world.data.structures[e.def_idx].pads + value)
				SimAirSortie.on_pads_changed(world, e)


## Power write: temporary layer until the absolute tick `until`.
func set_knob_temp(pid: int, k: int, value: int, until: int) -> void:
	var pe: SimPlayerEcon = _pe(pid)
	if pe == null or k < 0 or k >= SimEconConst.K_COUNT:
		return
	pe.knob_temp[k] = value
	pe.knob_until[k] = until


# ---- kernel hooks ----
func on_spawn(world: SimWorld, e: SimEntity) -> void:
	if e.kind == SimEntity.Kind.STRUCTURE or e.kind == SimEntity.Kind.NEUTRAL:
		_spawn_structure(world, e)
	elif e.kind == SimEntity.Kind.UNIT and world.data.units[e.def_idx].unit_class == DefEnums.UnitClass.SERVICE:
		var uc: SimCompEcon = SimCompEcon.new()
		uc.paid_cost = e.paid_cost
		_copy_flags(e, uc)
		e.econ = uc


func _spawn_structure(world: SimWorld, e: SimEntity) -> void:
	var ec: SimCompEcon = SimCompEcon.new()
	e.econ = ec
	ec.paid_cost = e.paid_cost
	_copy_flags(e, ec)
	if e.kind == SimEntity.Kind.STRUCTURE:
		ec.power_class = life.power_class_of(e.def_idx)
		var pk: int = life.prod_kind_of(e.def_idx)
		if pk != SimEconConst.PROD_NONE:
			var pr: SimCompProd = SimCompProd.new()
			pr.kind = pk
			e.prod = pr
	else:
		SimNeutrals.on_spawn(world, e)
	if (e.flags & SimFlags.F_UNDER_CONSTRUCTION) != 0:
		ec.st = SimEconConst.ST_BUILDUP
		ec.st_until = world.tick + SimEconConst.BUILDUP_TICKS
		return
	if (e.flags & SimFlags.F_INITIAL) != 0 and e.owner >= 0:
		ec.flags |= SimEconConst.EF_FREE
	life.activate(world, e, true)


static func _copy_flags(e: SimEntity, ec: SimCompEcon) -> void:
	if (e.flags & SimFlags.F_TEMPORARY) != 0:
		ec.flags |= SimEconConst.EF_TEMPORARY
	if (e.flags & SimFlags.F_DECOY) != 0:
		ec.flags |= SimEconConst.EF_DECOY
	if (e.flags & SimFlags.F_SUMMONED) != 0:
		ec.flags |= SimEconConst.EF_SUMMON
	if (e.flags & SimFlags.F_NO_REPAIR) != 0:
		ec.flags |= SimEconConst.EF_NO_REPAIR
	if (e.flags & SimFlags.F_NO_CAPTURE) != 0:
		ec.flags |= SimEconConst.EF_NO_CAPTURE
	if (e.flags & SimFlags.F_NO_SALVAGE) != 0:
		ec.flags |= SimEconConst.EF_NO_SALVAGE
	if (e.flags & SimFlags.F_NO_VISION_GRANT) != 0:
		ec.flags |= SimEconConst.EF_NO_VISION_GRANT
	if (e.flags & SimFlags.F_NO_UNIT_CAP) == 0 and e.kind == SimEntity.Kind.UNIT:
		ec.flags |= SimEconConst.EF_CAPPED


## Killed structures unregister and forfeit their queue (stage 11, before removal).
func on_dying(world: SimWorld, e: SimEntity, _cause: int, _killer_id: int, _killer_pid: int) -> void:
	_leave(world, e)


func on_remove(world: SimWorld, e: SimEntity, _reason: int) -> void:
	_leave(world, e)


func _leave(world: SimWorld, e: SimEntity) -> void:
	if e.econ == null or (e.kind != SimEntity.Kind.STRUCTURE and e.kind != SimEntity.Kind.NEUTRAL):
		return
	life.flush_queue(world, e, e.owner, false)
	life.deactivate(world, e, SimStructureLife.DC_DEATH)


func on_owner_changed(world: SimWorld, e: SimEntity, old_owner: int) -> void:
	if e.econ != null and (e.kind == SimEntity.Kind.STRUCTURE or e.kind == SimEntity.Kind.NEUTRAL):
		life.owner_changed(world, e, old_owner)


func on_player_eliminated(_world: SimWorld, pid: int) -> void:
	var pe: SimPlayerEcon = _pe(pid)
	if pe == null:
		return
	pe.flags |= SimEconConst.PF_ELIMINATED
	pe.power_dirty = true


# ---- refinery dock protocol (SimOrderHarvest; SimEconomyDocks holds the logic) ----
func dock_request(world: SimWorld, refinery_id: int, collector_id: int) -> int:
	return docks.request(world, refinery_id, collector_id)


func dock_unload_step(world: SimWorld, refinery_id: int, collector_id: int) -> int:
	return docks.unload_step(world, refinery_id, collector_id)


func dock_release(world: SimWorld, refinery_id: int, collector_id: int) -> void:
	docks.release(world, refinery_id, collector_id)


func dock_queue_len(refinery_id: int) -> int:
	var w: SimWorld = _w()
	return docks.queue_len(w, refinery_id) if w != null else 0


## System-private authoritative state: the deposit table bookkeeping (the credits are in the map).
func hash_state(_world: SimWorld, buf: PackedInt32Array) -> void:
	deposits.hash_into(buf)


# ---- read-only queries ----
## Collector unit ids of the player, ascending.
func q_collectors(pid: int, out: PackedInt32Array) -> void:
	out.clear()
	var w: SimWorld = _w()
	if w == null:
		return
	for e: SimEntity in w.units_of(pid):
		if e.econ != null and (e.flags & SimFlags.F_GONE) == 0 and w.data.units[e.def_idx].has_ability(DefEnums.AbilityKind.HARVEST):
			out.append(e.id)


## Deposit idx of the nearest field with at least `min_stock` credits left that `pid` has explored; -1 if none.
func q_deposit_nearest(world: SimWorld, pid: int, x: int, y: int, min_stock: int) -> int:
	return deposits.nearest(world, pid, x, y, min_stock)


## Income of the last 60 s (harvest + salvage + depot; not refunds or sells).
func q_income_per_minute(pid: int) -> int:
	var pe: SimPlayerEcon = _pe(pid)
	if pe == null:
		return 0
	var w: SimWorld = _w()
	if w != null:
		_advance_ring(pe, w.tick)
	var t: int = 0
	for v: int in pe.income_ring:
		t += v
	return t


# ---- engineer work (economy 3.2 signatures; the logic is SimEconomyWork, the order handlers are SimOrderCapture /
# SimOrderRepair / SimOrderSalvage). Salvage progress lives in the order, so there is no salvage_tick on the facade. ----
## Paid repair primitive: hp restored (0 = nothing due, -1 = paused, the payer lacks the credits).
func repair_step(world: SimWorld, repairer: SimEntity, target: SimEntity, rc: int, src_bit: int) -> int:
	return SimEconomyWork.repair_step(world, repairer, target, rc, src_bit)


## RSN_* ; `rc` (the category) is derived from the repairer's ability and only accepted for the spec's signature.
func repair_can_target(world: SimWorld, repairer: SimEntity, target: SimEntity, _rc: int = -1) -> int:
	return SimEconomyWork.repair_can_target(world, repairer, target)


func repair_basis_cost(world: SimWorld, target: SimEntity) -> int:
	return SimEconomyWork.repair_basis_cost(world, target)


func capture_can_target(world: SimWorld, engineer: SimEntity, target: SimEntity) -> int:
	return SimEconomyWork.capture_can_target(world, engineer, target)


func capture_channel(_world: SimWorld, engineer: SimEntity, target: SimEntity) -> void:
	SimEconomyWork.capture_channel(engineer, target)


func salvage_can_target(world: SimWorld, salvager: SimEntity, wreck: SimEntity) -> int:
	return SimEconomyWork.salvage_can_target(world, salvager, wreck)


## min(base action time, knob) for the player (Recovery Winches, Recovery Priority).
func salvage_duration_ticks(world: SimWorld, pid: int) -> int:
	return mini(world.data.economy.salvage_t, knob(pid, SimEconConst.K_SALVAGE_TICKS))


func salvage_begin(world: SimWorld, salvager: SimEntity, wreck: SimEntity) -> bool:
	return SimEconomyWork.salvage_begin(world, salvager, wreck, salvage_duration_ticks(world, salvager.owner))


func salvage_cancel(_world: SimWorld, salvager: SimEntity, wreck: SimEntity) -> void:
	SimEconomyWork.release_claim(wreck.econ, salvager.id)


## Salvage credits as basis points of the player's income (harvest + salvage + depot): the African Empire snowball check.
func q_salvage_share_bp(pid: int) -> int:
	var w: SimWorld = _w()
	return SimEconomyWork.salvage_share_bp(w, pid) if w != null else 0


func q_refineries(pid: int, out: PackedInt32Array) -> void:
	out.clear()
	var pe: SimPlayerEcon = _pe(pid)
	if pe != null:
		out.append_array(pe.refinery_ids)


func q_stats(pid: int) -> SimPlayerEcon:
	return _pe(pid)


## real structures or an MCV-class unit alive (the ARCH 12 elimination test).
func q_can_rebuild(pid: int) -> bool:
	var w: SimWorld = _w()
	if w == null or pid < 0 or pid >= w.players.size():
		return false
	return w.players[pid].struct_count > 0 or w.players[pid].rebuilders > 0


func _pe(pid: int) -> SimPlayerEcon:
	var w: SimWorld = _w()
	if w == null or pid < 0 or pid >= w.players.size():
		return null
	return w.players[pid].econ


func _w() -> SimWorld:
	return _wref.get_ref() as SimWorld if _wref != null else null
