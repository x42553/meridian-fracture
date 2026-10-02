class_name SimEconProdDouble
extends SimProductionSystem
## TEST DOUBLE for the economy slice (E0 / E2 / E4) until the production task (E3) lands: the construction queue of
## economy 5.1 / 5.3 only (BUILD_START / BUILD_CANCEL / BUILD_PLACE, progressive payment in bp-ticks, the power rate,
## READY, placement through SimPlacement). It lives in tests/support and is never a substitute for the real system.

const CQ_MAX: int = 5


func init_world(world: SimWorld) -> void:
	for op: int in [SimCmd.BUILD_START, SimCmd.BUILD_CANCEL, SimCmd.BUILD_PLACE]:
		world.commands.register_executor(op, Callable(self, "_command"))


func update(world: SimWorld) -> void:
	for p: SimPlayer in world.players:
		var pe: SimPlayerEcon = p.econ
		if pe == null or p.eliminated != 0 or pe.cq_def.is_empty():
			continue
		if pe.cq_state == SimEconConst.QS_READY:
			continue
		var total: int = pe.cq_ticks[0] * 10000
		var np: int = mini(pe.cq_progress + world.power.production_rate_bp(p.pid), total)
		var target: int = pe.cq_cost[0] * np / total
		var d: int = target - pe.cq_paid
		if d > p.credits:
			pe.cq_state = SimEconConst.QS_PAUSED_FUNDS
			continue
		world.economy.spend(world, p.pid, d, SimEconConst.CR_CONSTRUCTION)
		pe.cq_paid += d
		pe.cq_progress = np
		pe.cq_state = SimEconConst.QS_ACTIVE
		if np >= total:
			pe.cq_state = SimEconConst.QS_READY
			world.emit(SimEconConst.EVT_STRUCTURE_READY, 0, 0, p.pid, pe.cq_def[0])


func _command(world: SimWorld, cmd: SimCommand) -> int:
	var pe: SimPlayerEcon = world.players[cmd.pid].econ
	match cmd.op:
		SimCmd.BUILD_START:
			return _start(world, pe, cmd)
		SimCmd.BUILD_CANCEL:
			if pe.cq_def.is_empty():
				return SimCommand.Err.NO_TARGET
			world.economy.earn(world, cmd.pid, pe.cq_paid, SimEconConst.CR_REFUND)
			pe.cq_def.remove_at(0)
			pe.cq_cost.remove_at(0)
			pe.cq_ticks.remove_at(0)
			_reset_head(pe)
			return SimCommand.Err.OK
		SimCmd.BUILD_PLACE:
			return _place(world, pe, cmd)
	return SimCommand.Err.NOT_AVAILABLE


func _start(world: SimWorld, pe: SimPlayerEcon, cmd: SimCommand) -> int:
	var view: DefPlayerView = world.players[cmd.pid].view
	if pe.active_hq_count == 0:
		return _fail(cmd, SimEconConst.RSN_NO_HQ)
	if cmd.def < 0 or cmd.def >= view.struct_available.size() or view.struct_available[cmd.def] == 0:
		return _fail(cmd, SimEconConst.RSN_NOT_AVAILABLE)
	for r: int in world.data.structures[cmd.def].requires:
		if pe.struct_count[r] == 0:
			return _fail(cmd, SimEconConst.RSN_PREREQ)
	if pe.cq_def.size() + cmd.count > CQ_MAX:
		return _fail(cmd, SimEconConst.RSN_QUEUE_FULL)
	for _i: int in cmd.count:
		pe.cq_def.append(cmd.def)
		pe.cq_cost.append(view.struct_cost[cmd.def])
		pe.cq_ticks.append(view.struct_ticks[cmd.def])
	if pe.cq_state == SimEconConst.QS_EMPTY:
		pe.cq_state = SimEconConst.QS_ACTIVE
	return SimCommand.Err.OK


func _place(world: SimWorld, pe: SimPlayerEcon, cmd: SimCommand) -> int:
	if pe.cq_state != SimEconConst.QS_READY or pe.cq_def[0] != cmd.def:
		return _fail(cmd, SimEconConst.RSN_NOT_READY)
	var res: SimPlacementResult = SimPlacementResult.new()
	var reason: int = SimPlacement.validate(world, cmd.pid, cmd.def, cmd.x, cmd.y, cmd.mode, res)
	if reason != SimEconConst.RSN_OK:
		world.emit(SimEconConst.EVT_PLACE_REJECTED, 0, 0, cmd.pid, cmd.def, reason)
		return _fail(cmd, reason)
	var e: SimEntity = world.economy.life.place(world, cmd.pid, cmd.def, cmd.x, cmd.y, cmd.mode, pe.cq_paid, res)
	if e == null:
		return SimCommand.Err.BLOCKED
	pe.cq_def.remove_at(0)
	pe.cq_cost.remove_at(0)
	pe.cq_ticks.remove_at(0)
	_reset_head(pe)
	return SimCommand.Err.OK


func _reset_head(pe: SimPlayerEcon) -> void:
	pe.cq_progress = 0
	pe.cq_paid = 0
	pe.cq_state = SimEconConst.QS_ACTIVE if not pe.cq_def.is_empty() else SimEconConst.QS_EMPTY


func _fail(cmd: SimCommand, rsn: int) -> int:
	cmd.detail = rsn
	return SimEconomySystem.err_of(rsn)
