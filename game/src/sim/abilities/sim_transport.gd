class_name SimTransport
extends RefCounted
## Containers (abilities 5.10): transports, the Landing Transport, amphibious cargo and civilian garrisons. Cargo state
## is SimCompCargo on the container; a passenger is `F_INSIDE` with `container_id` set (world.set_inside), outside the
## spatial hash, and mirrors the container's position every tick (SimAbilitySystem stage 7e).
##
## Capacity is counted in slots: an infantry entity uses 1; a non-amphibious land vehicle uses
## ceil(capacity_squads_n / capacity_vehicles_n) (2 in the Landing Transport). Transports, MCVs and amphibious vehicles
## are never carried. Exit cells are searched on rings 1..3 (east first, clockwise, 8r cells per ring).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const EXIT_RINGS: int = 3
const EXIT_MAX_PER_CELL: int = 4
const GARRISON_UNLOAD_T: int = 10
const GARRISON_LOSS_BP: int = 3500  ## abilities 5.10.4: garrison default when combat gives none
const DEFAULT_LOSS_BP: int = 4000
const CAUSE_CARGO: int = 4  ## SimCombatConsts.CAUSE_CARGO


# ---- queries ---------------------------------------------------------------------------------------------------

static func is_container(e: SimEntity) -> bool:
	return e != null and e.cargo != null


static func is_garrison(e: SimEntity) -> bool:
	return e != null and e.kind == SimEntity.Kind.NEUTRAL and e.cargo != null


## Passenger ids in load order (a copy).
static func cargo_of(container: SimEntity) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var c: SimCompCargo = container.cargo if container != null else null
	if c == null:
		return out
	for i: int in c.n_pax:
		out.append(c.pax[i])
	return out


static func free_slots(carrier: SimEntity) -> int:
	var c: SimCompCargo = carrier.cargo if carrier != null else null
	return maxi(c.cap_slots - c.used_slots, 0) if c != null else 0


static func claim_team(building: SimEntity) -> int:
	return building.cargo.claim_team if building != null and building.cargo != null else -1


## True while the carrier is held by a boarding (load_t) - movement's immobile adapter reads this.
static func is_loading(world_tick: int, carrier: SimEntity) -> bool:
	return carrier.cargo != null and carrier.cargo.load_until > world_tick


## Slots the passenger would use in this carrier, 0 = cannot be carried.
static func slots_of(world: SimWorld, carrier: SimEntity, pax: SimEntity) -> int:
	if carrier.cargo == null or pax.kind != SimEntity.Kind.UNIT:
		return 0
	if pax.layer != SimEntity.Layer.GROUND:
		return 0
	var u: DefUnit = world.abilities.unit_def(world, pax)
	if u == null or (u.tags & DefEnums.UT_AIRCRAFT) != 0 or (u.tags & DefEnums.UT_SHIP) != 0:
		return 0
	if (u.tags & DefEnums.UT_INFANTRY) != 0:
		return 1
	if not is_garrison(carrier):
		var s: int = carrier.abil.slot_of_kind(K.AK_TRANSPORT) if carrier.abil != null else -1
		if s < 0:
			return 0
		var sq: int = world.abilities.sp(world, carrier, s, "capacity_squads_n", 0)
		var vh: int = world.abilities.sp(world, carrier, s, "capacity_vehicles_n", 0)
		if vh <= 0 or (u.tags & DefEnums.UT_LAND_VEHICLE) == 0:
			return 0
		if (u.tags & (DefEnums.UT_AMPHIBIOUS | DefEnums.UT_TRANSPORT)) != 0 or u.move_class == MapTerrain.MC_AMPHIBIOUS:
			return 0
		if u.has_ability(DefEnums.AbilityKind.DEPLOY_STRUCTURE):
			return 0
		var ex: int = world.abilities.sp(world, carrier, s, "excluded_unit_mask", 0)
		if (u.tags & ex) != 0:
			return 0
		return maxi((sq + vh - 1) / vh, 1)
	return 0


static func can_board(world: SimWorld, carrier: SimEntity, pax: SimEntity) -> bool:
	return board_reject(world, carrier, pax) == 0


## 0 = legal, else an RJ_* reason (SimAbilityEvents).
static func board_reject(world: SimWorld, carrier: SimEntity, pax: SimEntity) -> int:
	if carrier == null or pax == null or carrier == pax:
		return SimAbilityEvents.RJ_BAD_TARGET
	if (carrier.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or (pax.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return SimAbilityEvents.RJ_BAD_TARGET
	var c: SimCompCargo = carrier.cargo
	if c == null:
		return SimAbilityEvents.RJ_BAD_TARGET
	if pax.owner < 0:
		return SimAbilityEvents.RJ_NOT_OWNER
	if is_garrison(carrier):
		if c.claim_team >= 0 and c.claim_team != pax.team:
			return SimAbilityEvents.RJ_BAD_TARGET
	else:
		if carrier.owner < 0 or carrier.team != pax.team:
			return SimAbilityEvents.RJ_BAD_TARGET
		if c.unload_mode != 0:
			return SimAbilityEvents.RJ_BAD_STATE
	var need: int = slots_of(world, carrier, pax)
	if need <= 0:
		return SimAbilityEvents.RJ_BAD_TARGET
	if c.used_slots + need > c.cap_slots or c.n_pax >= SimCompCargo.MAX_PAX:
		return SimAbilityEvents.RJ_NO_ROOM
	if world.combat != null and not world.combat.is_functional(world, carrier) and not is_garrison(carrier):
		return SimAbilityEvents.RJ_DISABLED
	return 0


# ---- boarding --------------------------------------------------------------------------------------------------

## Instant boarding (orders walk the passenger to within 2 cells first). The passenger's queue is cleared.
static func board(world: SimWorld, carrier: SimEntity, pax: SimEntity, clear_orders: bool = true) -> bool:
	if board_reject(world, carrier, pax) != 0:
		return false
	var c: SimCompCargo = carrier.cargo
	var need: int = slots_of(world, carrier, pax)
	c.pax[c.n_pax] = pax.id
	c.pax_slots[c.n_pax] = need
	c.n_pax += 1
	c.used_slots += need
	if clear_orders and not pax.orders.is_empty():
		world.orders.clear(world, pax, SimOrder.END_CANCELLED)
	if world.movement != null:
		SimMovement.stop(world, pax, true)
	var garrison: bool = is_garrison(carrier)
	if not garrison and world.combat != null:
		world.combat.clear_target(pax)  # a passenger holds no target while aboard (garrisoned squads keep theirs)
	if garrison and c.claim_team < 0:
		c.claim_team = pax.team
	world.set_inside(pax, carrier.id, true)
	world.set_pos(pax, carrier.x, carrier.y, true)
	if garrison:
		pax.flags |= SimFlags.F_GARRISONED
		SimStats.set_flag(pax, K.DF_IN_GARRISON, true)
		SimCond.set_code(world, pax, DefEnums.Cond.IN_CIVILIAN_GARRISON, true)
		world.abilities.garrison_bonus(world, pax, true)
	carrier.flags |= SimFlags.F_GARRISONED
	SimStatus.remove_on_event(world, pax, K.RE_LOAD)
	if not garrison:
		var lt: int = _load_t(world, carrier)
		if lt > 0:
			c.load_until = maxi(c.load_until, world.tick + lt)
	world.abilities.carrier_add(carrier.id)
	if world.vision != null:
		world.vision.request_restamp(pax.id)
	world.emit(K.EV_LOADED, carrier.x, carrier.y, pax.id, carrier.id)
	if garrison:
		world.emit(K.EV_GARRISON_CHANGED, carrier.x, carrier.y, carrier.id, c.n_pax, c.claim_team)
	return true


static func garrison_enter(world: SimWorld, building: SimEntity, pax: SimEntity) -> bool:
	if not is_garrison(building):
		return false
	return board(world, building, pax)


static func _load_t(world: SimWorld, carrier: SimEntity) -> int:
	var s: int = carrier.abil.slot_of_kind(K.AK_TRANSPORT) if carrier.abil != null else -1
	if s < 0:
		return 0
	return world.abilities.sp(world, carrier, s, "load_t", 0)


# ---- unloading -------------------------------------------------------------------------------------------------

## 0 = legal, else an RJ_* reason.
static func unload_reject(world: SimWorld, carrier: SimEntity, mode: int, pax_eid: int) -> int:
	if carrier == null or carrier.cargo == null or (carrier.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return SimAbilityEvents.RJ_BAD_STATE
	var c: SimCompCargo = carrier.cargo
	if c.n_pax == 0 or c.unload_mode != 0:
		return SimAbilityEvents.RJ_BAD_STATE
	if mode == 2 and c.index_of(pax_eid) < 0:
		return SimAbilityEvents.RJ_BAD_TARGET
	if carrier.kind == SimEntity.Kind.UNIT and not _stationary(carrier) and not _unload_moving_ok(world, carrier):
		return SimAbilityEvents.RJ_NOT_STATIONARY
	return 0


## Not moving this tick: movement's F_MOVING mirror (combat's still_ticks only counts for armed entities, and the
## Landing Transport is unarmed).
static func _stationary(carrier: SimEntity) -> bool:
	return (carrier.flags & SimFlags.F_MOVING) == 0 and (carrier.combat == null or carrier.combat.ext_moving == 0)


static func _unload_moving_ok(world: SimWorld, carrier: SimEntity) -> bool:
	var s: int = carrier.abil.slot_of_kind(K.AK_TRANSPORT) if carrier.abil != null else -1
	return s >= 0 and world.abilities.sp(world, carrier, s, "unload_moving_speed_bp", 0) > 0


## mode: 1 = everybody, 2 = the passenger `pax_eid` (0 / other values of the command are mapped by the caller).
## (x, y) = drop point in sub-cell units, -1 = the carrier's own cell.
static func begin_unload(world: SimWorld, carrier: SimEntity, mode: int, pax_eid: int, x: int, y: int) -> bool:
	if unload_reject(world, carrier, mode, pax_eid) != 0:
		return false
	var c: SimCompCargo = carrier.cargo
	c.unload_mode = 2 if mode == 2 else 1
	c.unload_target = pax_eid if mode == 2 else -1
	c.unload_x = x
	c.unload_y = y
	c.unload_next = world.tick + unload_interval(world, carrier)
	if carrier.abil != null:
		var s: int = carrier.abil.slot_of_kind(K.AK_TRANSPORT)
		if s >= 0:
			carrier.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE] = 1
			carrier.abil.slots[s * K.SLOT_STRIDE + K.SL_T_END] = c.unload_next
		if carrier.kind == SimEntity.Kind.UNIT and not _stationary(carrier) and _unload_moving_ok(world, carrier):
			SimStats.set_flag(carrier, K.DF_UNLOAD_MOVING, true)
			SimStats.mark_dirty(world, carrier, 1 << K.K_SPEED)
	world.abilities.carrier_add(carrier.id)
	return true


static func unload_interval(world: SimWorld, carrier: SimEntity) -> int:
	if is_garrison(carrier):
		return GARRISON_UNLOAD_T
	var s: int = carrier.abil.slot_of_kind(K.AK_TRANSPORT) if carrier.abil != null else -1
	if s < 0:
		return GARRISON_UNLOAD_T
	var t: int = world.abilities.sp(world, carrier, s, "unload_t", GARRISON_UNLOAD_T)
	var sp: int = maxi(world.abilities.sp(world, carrier, s, "unload_speed_bp", 10000), 1)
	return maxi((t * 10000 + sp / 2) / sp, 1)


static func cancel_unload(world: SimWorld, carrier: SimEntity) -> void:
	var c: SimCompCargo = carrier.cargo
	if c == null:
		return
	c.unload_mode = 0
	c.unload_target = -1
	c.unload_x = -1
	c.unload_y = -1
	c.unload_next = 0
	if carrier.abil != null:
		var s: int = carrier.abil.slot_of_kind(K.AK_TRANSPORT)
		if s >= 0:
			carrier.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE] = 0
			carrier.abil.slots[s * K.SLOT_STRIDE + K.SL_T_END] = 0
	if carrier.stats != null and (carrier.stats.flags & K.DF_UNLOAD_MOVING) != 0:
		SimStats.set_flag(carrier, K.DF_UNLOAD_MOVING, false)
		SimStats.mark_dirty(world, carrier, 1 << K.K_SPEED)


## Stage 7e for one container: mirrors the passengers' position and runs the unload cadence.
static func step(world: SimWorld, carrier: SimEntity) -> void:
	var c: SimCompCargo = carrier.cargo
	if c == null:
		return
	for i: int in c.n_pax:
		var p: SimEntity = world.by_id[c.pax[i]]
		if p != null and (p.x != carrier.x or p.y != carrier.y):
			world.set_pos(p, carrier.x, carrier.y, true)
	if c.unload_mode == 0 or world.tick < c.unload_next:
		return
	if carrier.kind == SimEntity.Kind.UNIT and not _stationary(carrier) and not (carrier.stats != null and (carrier.stats.flags & K.DF_UNLOAD_MOVING) != 0):
		return  # waits until the carrier stands still
	var idx: int = 0
	if c.unload_mode == 2:
		idx = c.index_of(c.unload_target)
	if idx < 0 or c.n_pax == 0:
		cancel_unload(world, carrier)
		return
	var p2: SimEntity = world.by_id[c.pax[idx]]
	if p2 == null:
		remove_passenger(world, carrier, c.pax[idx])
		return
	var cell: int = find_exit_cell(world, carrier, p2, c.unload_x, c.unload_y)
	if cell < 0:
		world.emit(K.EV_UNLOAD_BLOCKED, carrier.x, carrier.y, carrier.id, 1)
		cancel_unload(world, carrier)
		return
	_exit_to(world, carrier, p2, cell, false)
	if c.unload_mode == 2 or c.n_pax == 0:
		cancel_unload(world, carrier)
	else:
		c.unload_next = world.tick + unload_interval(world, carrier)
		if carrier.abil != null:
			var s: int = carrier.abil.slot_of_kind(K.AK_TRANSPORT)
			if s >= 0:
				carrier.abil.slots[s * K.SLOT_STRIDE + K.SL_T_END] = c.unload_next


## Puts a passenger on the map at `cell`, updates the container and fires the disembark hooks.
static func _exit_to(world: SimWorld, carrier: SimEntity, p: SimEntity, cell: int, forced: bool) -> void:
	var map: MapData = world.map
	unlink(world, carrier, p.id)
	world.set_pos(p, map.center_x(cell), map.center_y(cell), true)
	world.set_inside(p, -1, false)
	p.flags &= ~SimFlags.F_GARRISONED
	if p.stats != null and (p.stats.flags & K.DF_IN_GARRISON) != 0:
		SimStats.set_flag(p, K.DF_IN_GARRISON, false)
		SimCond.set_code(world, p, DefEnums.Cond.IN_CIVILIAN_GARRISON, false)
		world.abilities.garrison_bonus(world, p, false)
	if world.vision != null:
		world.vision.request_restamp(p.id)
	if not forced:
		world.emit(K.EV_UNLOADED, p.x, p.y, p.id, carrier.id)
		world.abilities.on_disembark(world, p)
	if is_garrison(carrier):
		world.emit(K.EV_GARRISON_CHANGED, carrier.x, carrier.y, carrier.id, carrier.cargo.n_pax, carrier.cargo.claim_team)


## Removes the passenger from the container's list (no world change).
static func unlink(world: SimWorld, carrier: SimEntity, pax_id: int) -> void:
	var c: SimCompCargo = carrier.cargo
	if c == null:
		return
	var i: int = c.index_of(pax_id)
	if i < 0:
		return
	c.used_slots -= c.pax_slots[i]
	for j: int in range(i, c.n_pax - 1):
		c.pax[j] = c.pax[j + 1]
		c.pax_slots[j] = c.pax_slots[j + 1]
	c.pax[c.n_pax - 1] = -1
	c.pax_slots[c.n_pax - 1] = 0
	c.n_pax -= 1
	if c.n_pax == 0:
		c.claim_team = -1
		c.used_slots = 0
		carrier.flags &= ~SimFlags.F_GARRISONED
		world.abilities.carrier_remove(carrier.id)


## A passenger vanished (killed inside): drop it from its container.
static func remove_passenger(world: SimWorld, carrier: SimEntity, pax_id: int) -> void:
	unlink(world, carrier, pax_id)
	if carrier.cargo != null:
		if carrier.cargo.unload_mode == 2 and carrier.cargo.unload_target == pax_id:
			cancel_unload(world, carrier)
		elif carrier.cargo.n_pax == 0:
			cancel_unload(world, carrier)
		if is_garrison(carrier):
			world.emit(K.EV_GARRISON_CHANGED, carrier.x, carrier.y, carrier.id, carrier.cargo.n_pax, carrier.cargo.claim_team)


# ---- exit cells ------------------------------------------------------------------------------------------------

## Offset (dx, dy) of cell k (0-based) on ring r >= 1: east first ((r, 0)), clockwise on the screen (y grows downward),
## 8r cells. Packed as (dx + 64) | (dy + 64) << 8.
static func ring_offset(r: int, k: int) -> int:
	var dx: int
	var dy: int
	if k < r:  # east side going south: (r, 0) -> (r, r - 1)
		dx = r
		dy = k
	elif k < 3 * r:  # bottom side going west: (r, r) -> (-r + 1, r)
		dx = r - (k - r)
		dy = r
	elif k < 5 * r:  # west side going north: (-r, r) -> (-r, -r + 1)
		dx = -r
		dy = r - (k - 3 * r)
	elif k < 7 * r:  # top side going east: (-r, -r) -> (r - 1, -r)
		dx = -r + (k - 5 * r)
		dy = -r
	else:  # east side going south again: (r, -r) -> (r, -1)
		dx = r
		dy = -r + (k - 7 * r)
	return (dx + 64) | ((dy + 64) << 8)


## First legal exit cell (rings 1..EXIT_RINGS around the drop point / the container) for p, -1 if none.
static func find_exit_cell(world: SimWorld, container: SimEntity, p: SimEntity, x: int, y: int) -> int:
	var map: MapData = world.map
	var px: int = x if x >= 0 else container.x
	var py: int = y if y >= 0 else container.y
	var cx: int = clampi(px >> 10, 0, map.w - 1)
	var cy: int = clampi(py >> 10, 0, map.h - 1)
	var mc: int = p.move.mc if p.move != null else world.abilities.unit_def(world, p).move_class
	var amphibious: bool = mc == MapTerrain.MC_AMPHIBIOUS
	var buf: PackedInt32Array = PackedInt32Array()
	var need: int = SimTag.ALIVE | SimTag.layer_bit(p.layer) | SimTag.kind_bit(SimEntity.Kind.UNIT)
	for r: int in range(1, EXIT_RINGS + 1):
		for k: int in 8 * r:
			var o: int = ring_offset(r, k)
			var qx: int = cx + (o & 0xFF) - 64
			var qy: int = cy + (o >> 8) - 64
			if not map.in_bounds(qx, qy):
				continue
			var i: int = qy * map.w + qx
			if map.occupant_at(i) >= 0 or not map.passable(qx, qy, mc):
				continue
			if not amphibious and map.is_water(qx, qy):
				continue
			buf.resize(0)
			world.query_rect(qx * SimConfig.CELL, qy * SimConfig.CELL, (qx + 1) * SimConfig.CELL - 1, (qy + 1) * SimConfig.CELL - 1, buf, need)
			if buf.size() >= EXIT_MAX_PER_CELL:
				continue
			return i
	return -1


# ---- container death -------------------------------------------------------------------------------------------

## Loss of max health (bp) when the container dies: the transport default 4000 minus the ability's
## passenger_damage_reduction_bp (Beaver 2000, giving 2000), garrison 3500.
static func eject_loss_bp(world: SimWorld, container: SimEntity) -> int:
	if is_garrison(container):
		return GARRISON_LOSS_BP
	var s: int = container.abil.slot_of_kind(K.AK_TRANSPORT) if container.abil != null else -1
	var red: int = world.abilities.sp(world, container, s, "passenger_damage_reduction_bp", 0) if s >= 0 else 0
	return maxi(DEFAULT_LOSS_BP - red, 0)  # Beaver: 4000 - 2000 = 2000


## Everybody leaves at exit cells around the container, losing `hp_loss_bp` of max health (never below 1 hp). A
## passenger with no legal cell (non-amphibious over deep water) drowns through combat.kill(CAUSE_CARGO). A carrier that
## is sold or consumed passes 0. Safe to call for a container that is already dying (its cell is not in the hash).
static func eject_all(world: SimWorld, container: SimEntity, hp_loss_bp: int) -> void:
	var c: SimCompCargo = container.cargo
	if c == null or c.n_pax == 0:
		return
	var ids: PackedInt32Array = cargo_of(container)
	var cause: int = 0 if container.kind == SimEntity.Kind.UNIT else 1
	if c.unload_mode != 0:
		cancel_unload(world, container)
	for id: int in ids:
		var p: SimEntity = world.by_id[id] if id < world.by_id.size() else null
		if p == null or (p.flags & SimFlags.F_GONE) != 0:
			unlink(world, container, id)
			continue
		var cell: int = find_exit_cell(world, container, p, -1, -1)
		if cell < 0:
			unlink(world, container, id)
			if p.stats != null and (p.stats.flags & K.DF_IN_GARRISON) != 0:
				SimStats.set_flag(p, K.DF_IN_GARRISON, false)
			world.emit(K.EV_DROWNED, container.x, container.y, p.id)
			if world.combat != null:
				world.combat.kill(world, p, CAUSE_CARGO, -1, -1)
			continue
		_exit_to(world, container, p, cell, true)
		var lost: int = 0
		if hp_loss_bp > 0 and p.hp_max > 0:
			lost = mini(SimDamage.mul(p.hp_max, hp_loss_bp), maxi(p.hp - 1, 0))
			p.hp -= lost
		world.emit(K.EV_EJECTED, p.x, p.y, p.id, cause, lost)
	c.claim_team = -1
	container.flags &= ~SimFlags.F_GARRISONED
	world.abilities.carrier_remove(container.id)
