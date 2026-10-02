class_name SimPowerSystem
extends SimSystem
## Stage 4 (economy 3.5 / 5.7): the per-player power state machine over the balance the economy computed in
## stage 3, the SAP defense reserve, the derived flags (`defenses_online`, `powers_online`, F_POWERED on every
## structure), then the strategic helper. All state lives in SimPlayerEcon (hashed there).
##
## Timing convention (worked timeline of 5.7): the state a tick evaluates is the state its first stage-4 sees.
## A shortage first seen at tick S drains the reserve on ticks S .. S + max - 1 and `defenses_online` is false
## from tick S + max; power first adequate at tick R refills the reserve at tick R + 1200.

var _wref: WeakRef = null


func _init() -> void:
	stage_no = 4


## Keeps a weak reference so the pid-only queries of the spec work without a strong cycle.
func init_world(world: SimWorld) -> void:
	_wref = weakref(world)


func update(world: SimWorld) -> void:
	if world.economy == null:
		return  # the economy stage is disabled: no player records to evaluate
	for p: SimPlayer in world.players:
		var pe: SimPlayerEcon = p.econ
		if pe == null or p.eliminated != 0:
			continue
		_step_player(world, p, pe)
		p.power_supply = pe.power_supply
		p.power_demand = pe.power_demand
		for e: SimEntity in world.structures_of(p.pid):
			if e.econ == null:
				continue
			if world.economy.life.structure_online(world, e):
				e.flags |= SimFlags.F_POWERED
			else:
				e.flags &= ~SimFlags.F_POWERED
	if world.strategic != null and world.strategic.has_method("update"):
		world.strategic.call("update", world)


## The strategic helper's state (warnings, scheduler, windows) is part of the stage-4 hash.
func hash_state(world: SimWorld, buf: PackedInt32Array) -> void:
	if world.strategic != null:
		world.strategic.hash_into(buf)


func _step_player(world: SimWorld, p: SimPlayer, pe: SimPlayerEcon) -> void:
	var short: bool = pe.power_demand > pe.power_supply
	if short and pe.power_state == SimEconConst.PW_NORMAL:
		pe.power_state = SimEconConst.PW_SHORTAGE
		pe.shortage_since = world.tick
		pe.rates_dirty = true
		world.emit(SimEconConst.EVT_POWER_SHORTAGE, 0, 0, p.pid, pe.power_supply, pe.power_demand)
	elif not short and pe.power_state == SimEconConst.PW_SHORTAGE:
		pe.power_state = SimEconConst.PW_NORMAL
		pe.shortage_since = -1
		pe.rates_dirty = true
		world.emit(SimEconConst.EVT_POWER_RESTORED, 0, 0, p.pid)
	pe.powers_online = not short
	if (pe.flags & SimEconConst.PF_SAP_RESERVE) == 0:
		pe.defenses_online = not short
		pe.reserve_max = 0
		return
	pe.reserve_max = world.economy.knob(p.pid, SimEconConst.K_SAP_RESERVE_TICKS)
	if short:
		pe.adequate_streak = 0
		pe.defenses_online = pe.reserve_left > 0
		if pe.reserve_left > 0:
			pe.reserve_left -= 1
			if pe.reserve_left == 0:
				world.emit(SimEconConst.EVT_SAP_RESERVE_EMPTY, 0, 0, p.pid)
	else:
		pe.defenses_online = true
		if pe.adequate_streak >= SimEconConst.SAP_ADEQUATE_TICKS:
			pe.reserve_left = pe.reserve_max
		else:
			pe.adequate_streak += 1


func supply(pid: int) -> int:
	var pe: SimPlayerEcon = _econ(pid)
	return pe.power_supply if pe != null else 0


func demand(pid: int) -> int:
	var pe: SimPlayerEcon = _econ(pid)
	return pe.power_demand if pe != null else 0


## demand > supply (strict: exactly balanced is normal).
func is_shortage(pid: int) -> bool:
	var pe: SimPlayerEcon = _econ(pid)
	return pe != null and pe.power_state == SimEconConst.PW_SHORTAGE


func powered(pid: int) -> bool:
	return not is_shortage(pid)


## Powered OR the SAP reserve still lasts.
func defenses_online(pid: int) -> bool:
	var pe: SimPlayerEcon = _econ(pid)
	return pe == null or pe.defenses_online


## bp of normal speed production / research run at: 10000 normal, power_shortage_rate_bp (5000) in shortage.
func production_rate_bp(pid: int) -> int:
	var w: SimWorld = _w()
	if w != null and is_shortage(pid):
		return w.data.economy.power_shortage_rate_bp
	return 10000


func reserve_left_ticks(pid: int) -> int:
	var pe: SimPlayerEcon = _econ(pid)
	return pe.reserve_left if pe != null else 0


## A structure changed state; the economy recomputes the balance in its next stage 3.
func mark_dirty(pid: int) -> void:
	var pe: SimPlayerEcon = _econ(pid)
	if pe != null:
		pe.power_dirty = true


## >= 1 ACTIVE Radar (a SENSOR that is not the Laboratory), not shut down, powered.
func radar_online(world: SimWorld, pid: int) -> bool:
	return powered(pid) and _sensor_online(world, pid, "structure.shared.radar")


func lab_online(world: SimWorld, pid: int) -> bool:
	return powered(pid) and _sensor_online(world, pid, "structure.shared.laboratory")


## Structure-level online test (alias of SimStructureLife.structure_online) by entity id.
func is_powered(eid: int) -> bool:
	var w: SimWorld = _w()
	if w == null:
		return false
	var e: SimEntity = w.get_entity(eid)
	return e != null and w.economy.life.structure_online(w, e)


func defense_online(pid: int) -> bool:
	return defenses_online(pid)


func _sensor_online(world: SimWorld, pid: int, def_id: String) -> bool:
	var idx: int = world.data.structure_idx(def_id)
	if idx < 0 or pid < 0 or pid >= world.players.size():
		return false
	for e: SimEntity in world.structures_of(pid):
		if e.def_idx == idx and world.economy.life.structure_online(world, e):
			return true
	return false


func _econ(pid: int) -> SimPlayerEcon:
	var w: SimWorld = _w()
	if w == null or pid < 0 or pid >= w.players.size():
		return null
	return w.players[pid].econ


func _w() -> SimWorld:
	return _wref.get_ref() as SimWorld if _wref != null else null
