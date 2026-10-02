class_name SimEconomyDocks
extends RefCounted
## The refinery dock protocol (economy 5.9), owned by SimEconomySystem (`world.economy.docks`, delegated through
## `dock_request / dock_unload_step / dock_release / dock_queue_len`). One dock cell per Refinery = its exit cell;
## deterministic FIFO. State lives in the Refinery's SimCompEcon (`dock_occupant`, `dock_queue`, `dock_timer`,
## `dock_since`), all hashed with the entity. Stateless helper: no world reference is stored.

const WATCHDOG_STRIDE: int = 10
const OCCUPY_LIMIT_TICKS: int = 400


## DOCK_DENIED if the refinery is gone / not ACTIVE / shut down; DOCK_GRANTED if the caller holds the dock or the
## dock is free and the caller is first; otherwise the caller is queued (FIFO, no duplicates) and gets DOCK_WAIT.
func request(world: SimWorld, refinery_id: int, collector_id: int) -> int:
	var r: SimEntity = usable(world, refinery_id)
	if r == null:
		return SimEconConst.DOCK_DENIED
	var ec: SimCompEcon = r.econ
	if ec.dock_occupant == collector_id:
		return SimEconConst.DOCK_GRANTED
	if ec.dock_occupant == 0 and (ec.dock_queue.is_empty() or ec.dock_queue[0] == collector_id):
		if not ec.dock_queue.is_empty():
			ec.dock_queue.remove_at(0)
		ec.dock_occupant = collector_id
		ec.dock_timer = 0
		ec.dock_since = world.tick
		return SimEconConst.DOCK_GRANTED
	if not ec.dock_queue.has(collector_id):
		ec.dock_queue.append(collector_id)
	return SimEconConst.DOCK_WAIT


## Credits moved this tick from the docked collector's cargo (0 while the caller is not the occupant).
## The unload rate is DefEconomy.unload_mcpt (milli-credits per tick, carried in dock_timer); every credit goes to
## the owner through SimEconomySystem.earn(CR_HARVEST) (handicap-scaled by the kernel). EVT_CREDITS_GAINED with the
## whole session's credited total is emitted when the cargo hits 0.
func unload_step(world: SimWorld, refinery_id: int, collector_id: int) -> int:
	var r: SimEntity = world.get_entity(refinery_id)
	var c: SimEntity = world.get_entity(collector_id)
	if r == null or r.econ == null or c == null or c.econ == null or r.econ.dock_occupant != collector_id:
		return 0
	var rc: SimCompEcon = r.econ
	var cc: SimCompEcon = c.econ
	rc.dock_timer += world.data.economy.unload_mcpt
	var whole: int = rc.dock_timer / 1000
	rc.dock_timer -= whole * 1000
	var move: int = mini(whole, cc.cargo)
	if move > 0:
		var pe: SimPlayerEcon = world.players[c.owner].econ
		var before: int = pe.stat_harvested
		world.economy.earn(world, c.owner, move, SimEconConst.CR_HARVEST)
		cc.cargo -= move
		cc.h_unload_total += pe.stat_harvested - before
	if cc.cargo == 0:
		world.emit(SimEconConst.EVT_CREDITS_GAINED, r.x, r.y, c.owner, cc.h_unload_total, r.x, r.y)
		cc.h_unload_total = 0
	return move


## Frees the dock (if the caller holds it) and removes the caller from the queue. Idempotent.
func release(world: SimWorld, refinery_id: int, collector_id: int) -> void:
	var r: SimEntity = world.get_entity(refinery_id)
	if r == null or r.econ == null:
		return
	var ec: SimCompEcon = r.econ
	if ec.dock_occupant == collector_id:
		ec.dock_occupant = 0
		ec.dock_timer = 0
		ec.dock_since = 0
	var i: int = ec.dock_queue.find(collector_id)
	if i >= 0:
		ec.dock_queue.remove_at(i)


func queue_len(world: SimWorld, refinery_id: int) -> int:
	var r: SimEntity = world.get_entity(refinery_id)
	return r.econ.dock_queue.size() if r != null and r.econ != null else 0


## The refinery entity if it can accept a collector now (alive, ACTIVE, registered, not EMP shut down), else null.
func usable(world: SimWorld, refinery_id: int) -> SimEntity:
	var r: SimEntity = world.get_entity(refinery_id)
	if r == null or r.econ == null or r.kind != SimEntity.Kind.STRUCTURE or (r.flags & SimFlags.F_GONE) != 0:
		return null
	if r.econ.st != SimEconConst.ST_ACTIVE or not r.econ.registered or r.econ.shutdown_until > world.tick:
		return null
	return r


## Dock cell (map index) of a refinery = its exit cell, -1 outside the map.
func dock_cell(world: SimWorld, r: SimEntity) -> int:
	var org: PackedInt32Array = PackedInt32Array([0, 0])
	SimPlacement.entity_origin(world, r, org)
	var fp: MapFootprint = SimPlacement.footprint_of_def(world, r.def_idx)
	var orient: int = ((r.facing >> 10) & 3) if fp.rotatable else 0
	return SimPlacement.exit_cell(world, r.def_idx, org[0], org[1], orient)


## Stage 3, every WATCHDOG_STRIDE ticks: clears an occupant that is dead, has been redirected or held the dock for
## more than 400 ticks, and purges dead / redirected ids from the queues.
func watchdog(world: SimWorld) -> void:
	if world.tick % WATCHDOG_STRIDE != 0:
		return
	for p: SimPlayer in world.players:
		var pe: SimPlayerEcon = p.econ
		if pe == null:
			continue
		for rid: int in pe.refinery_ids:
			var r: SimEntity = world.get_entity(rid)
			if r == null or r.econ == null:
				continue
			var ec: SimCompEcon = r.econ
			if ec.dock_occupant != 0 and (not _holds(world, ec.dock_occupant, rid, false) or world.tick - ec.dock_since > OCCUPY_LIMIT_TICKS):
				ec.dock_occupant = 0
				ec.dock_timer = 0
				ec.dock_since = 0
			var i: int = ec.dock_queue.size() - 1
			while i >= 0:
				if not _holds(world, ec.dock_queue[i], rid, true):
					ec.dock_queue.remove_at(i)
				i -= 1


## The collector still works on this refinery (queued: waiting for it; occupant: docking / unloading at it).
func _holds(world: SimWorld, cid: int, rid: int, queued: bool) -> bool:
	var c: SimEntity = world.get_entity(cid)
	if c == null or c.econ == null or (c.flags & SimFlags.F_GONE) != 0 or c.econ.h_refinery != rid:
		return false
	var s: int = c.econ.h_state
	if queued:
		return s == SimEconConst.H_WAIT_DOCK
	return s == SimEconConst.H_DOCK_IN or s == SimEconConst.H_UNLOAD
