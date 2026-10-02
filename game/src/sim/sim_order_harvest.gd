class_name SimOrderHarvest
extends SimOrderHandler
## T_HARVEST and T_RETURN_CARGO (economy 3.7 / 5.9): the Collector state machine. One instance per order type
## (`SimOrderHarvest.new(SimOrder.T_HARVEST)`), stateless; every piece of state lives in the unit's SimCompEcon
## (`h_*`, `cargo`), the deposit table (harvester counts) and the refinery's dock fields.
##
## T_HARVEST: `arg` = deposit idx + 1 (manual field), or x / y = a point on a field (a player command), or OF_AUTO with
## arg 0 = auto. Never DONE (a manual field that runs dry falls back to auto). T_RETURN_CARGO: `target_id` = refinery
## id (0 = choose), DONE after the unload. The same T_HARVEST instance is registered as the idle handler, which
## gives every idle Collector an auto-harvest order.
##
## Numbers come from DefEconomy (global.json): capacity, harvest_mcpt (milli-credits per tick), unload_mcpt and
## unload_overhead_t, which is split 60 / 40 into the dock-in and dock-out glides.

const APPROACH_RANGE: int = 1536
const NEAR_SLACK: int = 512
const SEARCH_STRIDE: int = 20
const MAX_SEARCHES_PER_TICK: int = 6
const RETRY_TICKS: int = 60
const BAD_FIELD_TICKS: int = 600
const SCAN_STRIDE: int = 10
const THREAT_R: int = 6144
const CLEAR_R: int = 8192
const FLEE_TICKS: int = 200
const DANGER_TICKS: int = 400
const FULL_PCT: int = 90
const REPICK_WAIT: int = 400
const REPICK_GAP: int = 2
const NO_REFINERY_PERIOD: int = 600
const FIELD_INNER: int = 1024
const DIST_PENALTY: int = 4096
const LAST_FIELD_BONUS: int = 2048
const REFINERY_QUEUE_PENALTY: int = 3072

var order_type: int = SimOrder.T_HARVEST


func _init(p_type: int = SimOrder.T_HARVEST) -> void:
	order_type = p_type


func can_issue(world: SimWorld, e: SimEntity, _o: SimOrder) -> int:
	if e.econ == null or not world.data.units[e.def_idx].has_ability(DefEnums.AbilityKind.HARVEST):
		return SimCommand.Err.NOT_ALLOWED
	return SimCommand.Err.OK


func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var ec: SimCompEcon = e.econ
	_release_field(world, ec)
	ec.h_state = SimEconConst.H_IDLE
	ec.h_mode = 0
	ec.h_refinery = 0
	ec.h_timer = 0
	if order_type == SimOrder.T_RETURN_CARGO:
		if ec.cargo <= 0:
			return SimOrder.DONE
		var ru: SimEntity = world.economy.docks.usable(world, o.target_id)
		if ru != null and ru.owner == e.owner:
			ec.h_refinery = ru.id
		ec.h_state = SimEconConst.H_TO_REFINERY
		return SimOrder.RUNNING
	var deps: SimDepositTable = world.economy.deposits
	var f: int = -1
	if o.arg > 0:
		f = o.arg - 1
	elif (o.flags & SimOrder.OF_AUTO) == 0:
		f = deps.idx_at(world.map, o.x, o.y)
	if f >= 0 and f < deps.count:
		ec.h_mode = 1
		ec.h_last_field = f
	ec.h_state = SimEconConst.H_SEEK
	return SimOrder.RUNNING


func on_end(world: SimWorld, e: SimEntity, _o: SimOrder, _reason: int) -> void:
	var ec: SimCompEcon = e.econ
	if ec == null:
		return
	_release_field(world, ec)
	var s: int = ec.h_state
	if ec.h_refinery != 0 and (s == SimEconConst.H_WAIT_DOCK or s == SimEconConst.H_DOCK_IN or s == SimEconConst.H_UNLOAD or s == SimEconConst.H_DOCK_OUT):
		world.economy.docks.release(world, ec.h_refinery, e.id)
		if s != SimEconConst.H_WAIT_DOCK and (e.flags & SimFlags.F_GONE) == 0:
			_place_outside(world, e, ec)
	if (e.flags & SimFlags.F_GONE) == 0:
		SimMovement.stop(world, e, false)
	ec.h_state = SimEconConst.H_IDLE
	ec.h_refinery = 0
	ec.h_mode = 0
	ec.h_timer = 0


## An idle Collector starts auto-harvesting.
func on_idle(world: SimWorld, e: SimEntity) -> void:
	if e.econ == null or e.owner < 0 or not world.data.units[e.def_idx].has_ability(DefEnums.AbilityKind.HARVEST):
		return
	world.orders.issue_internal(world, e, SimOrder.T_HARVEST, 0, 0, 0)


func on_update(world: SimWorld, e: SimEntity, _o: SimOrder) -> int:
	var ec: SimCompEcon = e.econ
	var hurt: bool = ec.h_last_hp > 0 and e.hp < ec.h_last_hp
	ec.h_last_hp = e.hp
	match ec.h_state:
		SimEconConst.H_IDLE:
			if world.tick >= ec.h_timer:
				ec.h_state = SimEconConst.H_SEEK
		SimEconConst.H_SEEK:
			_seek(world, e, ec, hurt)
		SimEconConst.H_TO_FIELD:
			_to_field(world, e, ec, hurt)
		SimEconConst.H_HARVEST:
			_harvest(world, e, ec, hurt)
		SimEconConst.H_TO_REFINERY:
			_to_refinery(world, e, ec)
		SimEconConst.H_WAIT_DOCK:
			_wait_dock(world, e, ec)
		SimEconConst.H_DOCK_IN:
			_dock_in(world, e, ec)
		SimEconConst.H_UNLOAD:
			_unload(world, e, ec)
		SimEconConst.H_DOCK_OUT:
			return _dock_out(world, e, ec)
		SimEconConst.H_FLEE:
			_flee_wait(world, e, ec)
		_:
			ec.h_state = SimEconConst.H_SEEK
	return SimOrder.RUNNING


# ---------------------------------------------------------------------------------------------------------- states
func _capacity(world: SimWorld, e: SimEntity) -> int:
	var a: DefAbility = world.data.units[e.def_idx].ability_of(DefEnums.AbilityKind.HARVEST)
	if a != null and a.params.has("capacity_cr"):
		return int(a.params["capacity_cr"])
	return world.data.economy.collector_capacity_cr


func _seek(world: SimWorld, e: SimEntity, ec: SimCompEcon, hurt: bool) -> void:
	var cap: int = _capacity(world, e)
	if ec.cargo * 100 >= cap * FULL_PCT:
		ec.h_state = SimEconConst.H_TO_REFINERY
		return
	if _threat_check(world, e, ec, hurt):
		return
	var deps: SimDepositTable = world.economy.deposits
	var f: int = -1
	if ec.h_mode == 1:
		if deps.stock(world.map, ec.h_last_field) > 0:
			f = ec.h_last_field
		else:
			ec.h_mode = 0
	if f < 0 and ec.h_last_field >= 0 and _field_ok(world, e, ec, ec.h_last_field):
		f = ec.h_last_field  # back to the field it just left: no search, no stagger
	if f < 0:
		if world.tick < ec.h_timer or (e.id + world.tick) % SEARCH_STRIDE != 0:
			return
		if deps.search_tick != world.tick:
			deps.search_tick = world.tick
			deps.search_used = 0
		if deps.search_used >= MAX_SEARCHES_PER_TICK:
			return
		deps.search_used += 1
		f = choose_field(world, e, ec)
		if f < 0:
			ec.h_timer = world.tick + RETRY_TICKS
			if ec.cargo > 0:
				ec.h_state = SimEconConst.H_TO_REFINERY
			return
	deps.harvesters[f] += 1
	ec.h_field = f
	ec.h_last_field = f
	ec.h_state = SimEconConst.H_TO_FIELD
	_go_to_field(world, e, f)


func _go_to_field(world: SimWorld, e: SimEntity, f: int) -> void:
	var deps: SimDepositTable = world.economy.deposits
	var dx: int = e.x - deps.x[f]
	var dy: int = e.y - deps.y[f]
	var d: int = Fp.dist(dx, dy)
	var inner: int = maxi(deps.radius[f] - FIELD_INNER, 0)
	if d <= inner:
		return
	SimMovement.go_to(world, e, deps.x[f] + dx * inner / d, deps.y[f] + dy * inner / d, SimMoveConfig.OPT_PRIO_ECON)


func _to_field(world: SimWorld, e: SimEntity, ec: SimCompEcon, hurt: bool) -> void:
	var deps: SimDepositTable = world.economy.deposits
	var f: int = ec.h_field
	if f < 0 or deps.stock(world.map, f) <= 0:
		_release_field(world, ec)
		ec.h_state = SimEconConst.H_SEEK if ec.cargo == 0 else SimEconConst.H_TO_REFINERY
		SimMovement.stop(world, e, false)
		return
	if _threat_check(world, e, ec, hurt):
		return
	if SimMovement.path_failed(e):
		ec.h_bad_field = f
		ec.h_bad_until = world.tick + BAD_FIELD_TICKS
		_release_field(world, ec)
		ec.h_state = SimEconConst.H_SEEK
		SimMovement.ack(world, e)
		return
	if Fp.dist(e.x - deps.x[f], e.y - deps.y[f]) <= deps.radius[f] - 512:
		SimMovement.stop(world, e, false)
		ec.h_timer = 0
		ec.h_state = SimEconConst.H_HARVEST
		return
	var ms: int = SimMovement.state(e)
	if ms == SimMoveConfig.MS_IDLE or ms == SimMoveConfig.MS_ARRIVED:
		SimMovement.ack(world, e)
		if not SimMovement.go_to(world, e, deps.x[f], deps.y[f], SimMoveConfig.OPT_PRIO_ECON):
			ec.h_bad_field = f
			ec.h_bad_until = world.tick + BAD_FIELD_TICKS
			_release_field(world, ec)
			ec.h_state = SimEconConst.H_SEEK


func _harvest(world: SimWorld, e: SimEntity, ec: SimCompEcon, hurt: bool) -> void:
	var deps: SimDepositTable = world.economy.deposits
	var f: int = ec.h_field
	var cap: int = _capacity(world, e)
	if f < 0 or deps.stock(world.map, f) <= 0:
		_release_field(world, ec)
		ec.h_state = SimEconConst.H_TO_REFINERY if ec.cargo > 0 else SimEconConst.H_SEEK
		return
	if _threat_check(world, e, ec, hurt):
		return
	ec.h_timer += world.data.economy.harvest_mcpt
	var n: int = ec.h_timer / 1000
	ec.h_timer -= n * 1000
	if n > 0:
		var cell: int = world.map.idx(clampi(e.x >> 10, 0, world.map.w - 1), clampi(e.y >> 10, 0, world.map.h - 1))
		ec.cargo += deps.take(world, f, cell, mini(n, cap - ec.cargo))
	if ec.cargo >= cap or deps.stock(world.map, f) <= 0:
		_release_field(world, ec)
		ec.h_state = SimEconConst.H_TO_REFINERY if ec.cargo > 0 else SimEconConst.H_SEEK
		ec.h_timer = 0


func _to_refinery(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> void:
	var docks: SimEconomyDocks = world.economy.docks
	var r: SimEntity = docks.usable(world, ec.h_refinery)
	if r == null or r.owner != e.owner:
		ec.h_refinery = 0
		r = choose_refinery(world, e)
		if r == null:
			if world.tick % NO_REFINERY_PERIOD < 2 * RETRY_TICKS:  # about one hint per 600 ticks
				world.emit(SimEconConst.EVT_NO_REFINERY, e.x, e.y, e.owner)
			SimMovement.stop(world, e, false)
			_idle(world, ec)
			return
		ec.h_refinery = r.id
		if not SimMovement.approach_entity(world, e, r.id, APPROACH_RANGE, SimMoveConfig.OPT_PRIO_ECON):
			ec.h_refinery = 0
			_idle(world, ec)
		return
	if SimMovement.at_goal(e) or _near(e, r):
		match docks.request(world, r.id, e.id):
			SimEconConst.DOCK_GRANTED:
				_begin_dock_in(world, e, ec, r)
			SimEconConst.DOCK_WAIT:
				SimMovement.stop(world, e, false)
				ec.h_state = SimEconConst.H_WAIT_DOCK
				ec.h_timer = world.tick
			_:
				ec.h_refinery = 0
		return
	if SimMovement.path_failed(e):
		ec.h_refinery = 0
		_idle(world, ec)
		SimMovement.ack(world, e)
		return
	if SimMovement.state(e) == SimMoveConfig.MS_IDLE:
		if not SimMovement.approach_entity(world, e, r.id, APPROACH_RANGE, SimMoveConfig.OPT_PRIO_ECON):
			ec.h_refinery = 0
			_idle(world, ec)


func _near(e: SimEntity, r: SimEntity) -> bool:
	return Fp.dist(e.x - r.x, e.y - r.y) - r.radius <= APPROACH_RANGE + NEAR_SLACK


func _begin_dock_in(world: SimWorld, e: SimEntity, ec: SimCompEcon, r: SimEntity) -> void:
	var dock_in: int = maxi(world.data.economy.unload_overhead_t * 3 / 5, 1)
	var cell: int = world.economy.docks.dock_cell(world, r)
	var tx: int = r.x if cell < 0 else world.map.center_x(cell)
	var ty: int = r.y if cell < 0 else world.map.center_y(cell)
	SimMovement.stop(world, e, true)
	SimMovement.glide(world, e, tx, ty, dock_in)
	ec.h_state = SimEconConst.H_DOCK_IN
	ec.h_timer = world.tick + dock_in


func _wait_dock(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> void:
	var docks: SimEconomyDocks = world.economy.docks
	var r: SimEntity = docks.usable(world, ec.h_refinery)
	if r == null:
		ec.h_refinery = 0
		ec.h_state = SimEconConst.H_TO_REFINERY
		return
	match docks.request(world, r.id, e.id):
		SimEconConst.DOCK_GRANTED:
			_begin_dock_in(world, e, ec, r)
			return
		SimEconConst.DOCK_DENIED:
			ec.h_refinery = 0
			ec.h_state = SimEconConst.H_TO_REFINERY
			return
	if world.tick - ec.h_timer > REPICK_WAIT:
		var alt: SimEntity = choose_refinery(world, e)
		if alt != null and alt.id != r.id and docks.queue_len(world, alt.id) + REPICK_GAP <= docks.queue_len(world, r.id):
			docks.release(world, r.id, e.id)
			ec.h_refinery = alt.id
			ec.h_state = SimEconConst.H_TO_REFINERY
			SimMovement.approach_entity(world, e, alt.id, APPROACH_RANGE, SimMoveConfig.OPT_PRIO_ECON)


func _dock_in(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> void:
	if world.economy.docks.usable(world, ec.h_refinery) == null:
		_begin_dock_out(world, e, ec, null)
	elif world.tick >= ec.h_timer:
		ec.h_state = SimEconConst.H_UNLOAD


func _unload(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> void:
	var docks: SimEconomyDocks = world.economy.docks
	var r: SimEntity = docks.usable(world, ec.h_refinery)
	if r == null:
		_begin_dock_out(world, e, ec, null)
		return
	docks.unload_step(world, r.id, e.id)
	if ec.cargo <= 0:
		docks.release(world, r.id, e.id)
		_begin_dock_out(world, e, ec, r)


func _begin_dock_out(world: SimWorld, e: SimEntity, ec: SimCompEcon, r: SimEntity) -> void:
	var overhead: int = world.data.economy.unload_overhead_t
	var dock_out: int = maxi(overhead - overhead * 3 / 5, 1)
	var base: int = world.economy.docks.dock_cell(world, r) if r != null else -1
	if base < 0:
		base = world.map.idx(clampi(e.x >> 10, 0, world.map.w - 1), clampi(e.y >> 10, 0, world.map.h - 1))
	var cell: int = SimMovement.find_free_cell_near(world, base, e.layer, 4)
	if cell < 0:
		cell = base
	SimMovement.glide(world, e, world.map.center_x(cell), world.map.center_y(cell), dock_out)
	ec.h_state = SimEconConst.H_DOCK_OUT
	ec.h_timer = world.tick + dock_out


func _dock_out(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> int:
	if world.tick < ec.h_timer:
		return SimOrder.RUNNING
	SimMovement.ack(world, e)
	ec.h_refinery = 0
	ec.h_timer = 0
	if ec.cargo > 0:
		ec.h_state = SimEconConst.H_TO_REFINERY
		return SimOrder.RUNNING
	ec.h_state = SimEconConst.H_SEEK
	return SimOrder.DONE if order_type == SimOrder.T_RETURN_CARGO else SimOrder.RUNNING


# ---------------------------------------------------------------------------------------------------- selection
## Best field for the collector (economy 5.9): lower score wins, ties lowest index; -1 if none.
func choose_field(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> int:
	var deps: SimDepositTable = world.economy.deposits
	var best: int = -1
	var best_score: int = 1 << 60
	for i: int in deps.count:
		if not _field_ok(world, e, ec, i):
			continue
		var score: int = Fp.dist(e.x - deps.x[i], e.y - deps.y[i]) + DIST_PENALTY * deps.harvesters[i]
		if i == ec.h_last_field:
			score -= LAST_FIELD_BONUS
		if score < best_score:
			best = i
			best_score = score
	return best


## Candidate rules of choose_field: stock left, room for another harvester, not this collector's bad field, not
## marked dangerous by a flee of the owner, explored by the owner.
func _field_ok(world: SimWorld, e: SimEntity, ec: SimCompEcon, i: int) -> bool:
	var deps: SimDepositTable = world.economy.deposits
	if i < 0 or i >= deps.count or deps.stock(world.map, i) <= 0 or deps.harvesters[i] >= deps.max_harvesters(i):
		return false
	if i == ec.h_bad_field and world.tick < ec.h_bad_until:
		return false
	var pe: SimPlayerEcon = world.players[e.owner].econ
	if i < pe.field_danger.size() and pe.field_danger[i] > world.tick:
		return false
	return world.cell_explored(e.owner, deps.x[i] >> 10, deps.y[i] >> 10)


## ACTIVE, non-shut-down refinery of the owner with the lowest score (distance to the dock cell + queue penalty).
func choose_refinery(world: SimWorld, e: SimEntity) -> SimEntity:
	var pe: SimPlayerEcon = world.players[e.owner].econ
	var docks: SimEconomyDocks = world.economy.docks
	var best: SimEntity = null
	var best_score: int = 1 << 60
	for rid: int in pe.refinery_ids:
		var r: SimEntity = docks.usable(world, rid)
		if r == null:
			continue
		var cell: int = docks.dock_cell(world, r)
		var px: int = r.x if cell < 0 else world.map.center_x(cell)
		var py: int = r.y if cell < 0 else world.map.center_y(cell)
		var q: int = r.econ.dock_queue.size() + (1 if r.econ.dock_occupant != 0 else 0)
		var score: int = Fp.dist(e.x - px, e.y - py) + REFINERY_QUEUE_PENALTY * q
		if score < best_score:
			best = r
			best_score = score
	return best


# ------------------------------------------------------------------------------------------------------- flee
func _threat_check(world: SimWorld, e: SimEntity, ec: SimCompEcon, hurt: bool) -> bool:
	if not hurt and world.tick - ec.h_scan_tick < SCAN_STRIDE:
		return false
	ec.h_scan_tick = world.tick
	if not hurt and not hostile_near(world, e.owner, e.x, e.y, THREAT_R):
		return false
	_flee(world, e, ec)
	return true


## An armed, non-air enemy unit / structure visible to `pid` within `r` of (x, y).
func hostile_near(world: SimWorld, pid: int, x: int, y: int, r: int) -> bool:
	var buf: PackedInt32Array = PackedInt32Array()
	world.enemies_in_circle(pid, x, y, r, buf)
	for id: int in buf:
		var t: SimEntity = world.by_id[id]
		if t.layer == SimEntity.Layer.AIR:
			continue
		if t.kind == SimEntity.Kind.UNIT and not world.data.units[t.def_idx].weapons.is_empty():
			return true
		if t.kind == SimEntity.Kind.STRUCTURE and not world.data.structures[t.def_idx].weapons.is_empty():
			return true
	return false


func _flee(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> void:
	var pe: SimPlayerEcon = world.players[e.owner].econ
	if ec.h_field >= 0 and ec.h_field < pe.field_danger.size():
		pe.field_danger[ec.h_field] = world.tick + DANGER_TICKS
	_release_field(world, ec)
	ec.h_flee_until = world.tick + FLEE_TICKS
	world.emit(SimEconConst.EVT_COLLECTOR_ATTACKED, e.x, e.y, e.owner, e.id)
	var safe: SimEntity = _safe_refinery(world, e)
	if ec.cargo > 0 and safe != null:
		ec.h_refinery = safe.id
		ec.h_state = SimEconConst.H_TO_REFINERY
		SimMovement.approach_entity(world, e, safe.id, APPROACH_RANGE, SimMoveConfig.OPT_PRIO_ECON)
		return
	var dest: SimEntity = safe
	if dest == null:
		dest = _nearest_structure(world, e)
	ec.h_state = SimEconConst.H_FLEE
	if dest != null:
		SimMovement.approach_entity(world, e, dest.id, APPROACH_RANGE, SimMoveConfig.OPT_PRIO_ECON)
	else:
		SimMovement.stop(world, e, false)


func _flee_wait(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> void:
	if world.tick < ec.h_flee_until or hostile_near(world, e.owner, e.x, e.y, CLEAR_R):
		return
	SimMovement.ack(world, e)
	ec.h_state = SimEconConst.H_TO_REFINERY if ec.cargo > 0 else SimEconConst.H_SEEK


func _safe_refinery(world: SimWorld, e: SimEntity) -> SimEntity:
	var pe: SimPlayerEcon = world.players[e.owner].econ
	var best: SimEntity = null
	var best_d: int = 1 << 60
	for rid: int in pe.refinery_ids:
		var r: SimEntity = world.economy.docks.usable(world, rid)
		if r == null:
			continue
		var d: int = Fp.dist(e.x - r.x, e.y - r.y)
		if d < best_d and not hostile_near(world, e.owner, r.x, r.y, CLEAR_R):
			best = r
			best_d = d
	return best


func _nearest_structure(world: SimWorld, e: SimEntity) -> SimEntity:
	var best: SimEntity = null
	var best_d: int = 1 << 60
	for s: SimEntity in world.structures_of(e.owner):
		if (s.flags & SimFlags.F_GONE) != 0:
			continue
		var d: int = Fp.dist(e.x - s.x, e.y - s.y)
		if d < best_d:
			best = s
			best_d = d
	return best


# ------------------------------------------------------------------------------------------------------ helpers
## Waits (RETRY_TICKS) inside the order before looking for work again; cargo stays on board.
func _idle(world: SimWorld, ec: SimCompEcon) -> void:
	ec.h_state = SimEconConst.H_IDLE
	ec.h_timer = world.tick + RETRY_TICKS


func _release_field(world: SimWorld, ec: SimCompEcon) -> void:
	if ec.h_field >= 0:
		var deps: SimDepositTable = world.economy.deposits
		if ec.h_field < deps.count:
			deps.harvesters[ec.h_field] = maxi(deps.harvesters[ec.h_field] - 1, 0)
		ec.h_field = -1


## A collector still inside a refinery footprint (order replaced / killed refinery) steps out to a free cell.
func _place_outside(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> void:
	var r: SimEntity = world.get_entity(ec.h_refinery)
	var base: int = world.economy.docks.dock_cell(world, r) if r != null else -1
	if base < 0:
		base = world.map.idx(clampi(e.x >> 10, 0, world.map.w - 1), clampi(e.y >> 10, 0, world.map.h - 1))
	var cell: int = SimMovement.find_free_cell_near(world, base, e.layer, 4)
	if cell >= 0:
		world.set_pos(e, world.map.center_x(cell), world.map.center_y(cell))
