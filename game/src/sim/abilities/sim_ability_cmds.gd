class_name SimAbilityCmds
extends RefCounted
## Executors of the abilities commands DEPLOY / UNDEPLOY / SET_MODE / USE_ABILITY / SET_AUTOCAST / UNLOAD (kernel ops
## 100..105, abilities 5.6.2 / 6.1). The kernel has already resolved the actors (owned, alive, not inside a container);
## an executor returns SimCommand.Err.OK when at least one actor accepted, else the last refusal, and leaves the
## abilities reject reason (SimAbilityEvents.RJ_*) in `cmd.detail`, which the kernel reports in CMD_REJECTED.
##
## Wire fields (SimCmd): DEPLOY / UNDEPLOY def = slot (-1 = the unit's first deploy / sensor_mast); SET_MODE def = slot,
## mode = mode index (-1 = cycle); USE_ABILITY def = slot, mode = op (0 start, 1 cancel), target, x, y;
## SET_AUTOCAST def = slot, mode = 0 / 1; UNLOAD mode = 0 all / 1 one, target = passenger, x, y = drop point.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
## Kinds whose slot may carry the AUTOCAST bit (5.6.3); only repair has a behaviour, deploy is a UI mirror.
const IN_PLACE_U: int = 2048  ## a drop point this close to the carrier means "unload here"
const AUTOCAST_KINDS: PackedInt32Array = [3, 7, 11, 12, 13, 16, 17, 21]


static func register(world: SimWorld) -> void:
	var c: SimCommandSystem = world.commands
	if c == null:
		return
	c.register_executor(SimCmd.DEPLOY, SimAbilityCmds.cmd_deploy)
	c.register_executor(SimCmd.UNDEPLOY, SimAbilityCmds.cmd_undeploy)
	c.register_executor(SimCmd.SET_MODE, SimAbilityCmds.cmd_set_mode)
	c.register_executor(SimCmd.USE_ABILITY, SimAbilityCmds.cmd_use_ability)
	c.register_executor(SimCmd.SET_AUTOCAST, SimAbilityCmds.cmd_set_autocast)
	c.register_executor(SimCmd.UNLOAD, SimAbilityCmds.cmd_unload)


## Kernel-facing dispatcher (also usable by tests): `execute(world, cmd)` runs the executor of cmd.op.
static func execute(world: SimWorld, cmd: SimCommand) -> int:
	match cmd.op:
		SimCmd.DEPLOY:
			return cmd_deploy(world, cmd)
		SimCmd.UNDEPLOY:
			return cmd_undeploy(world, cmd)
		SimCmd.SET_MODE:
			return cmd_set_mode(world, cmd)
		SimCmd.USE_ABILITY:
			return cmd_use_ability(world, cmd)
		SimCmd.SET_AUTOCAST:
			return cmd_set_autocast(world, cmd)
		SimCmd.UNLOAD:
			return cmd_unload(world, cmd)
	return SimCommand.Err.UNKNOWN_OP


# ---- shared bookkeeping ----------------------------------------------------------------------------------------

## Folds one actor's outcome into the command result: reason 0 = accepted.
class Result:
	var ok: bool = false
	var reason: int = 0


static func _note(res: Result, reason: int) -> void:
	if reason == 0:
		res.ok = true
	else:
		res.reason = reason


static func _finish(cmd: SimCommand, res: Result) -> int:
	if res.ok:
		return SimCommand.Err.OK
	cmd.detail = res.reason if res.reason != 0 else SimAbilityEvents.RJ_NO_SLOT
	return SimAbilityEvents.err_of(cmd.detail)


static func _used(world: SimWorld, e: SimEntity, slot: int, x: int = 0, y: int = 0) -> void:
	var kind: int = e.abil.slots[slot * K.SLOT_STRIDE + K.SL_KIND] if e.abil != null and slot >= 0 and slot < e.abil.n_slots else 0
	world.emit(K.EV_ABILITY_USED, x if x > 0 else e.x, y if y > 0 else e.y, e.id, kind, slot)


# ---- deploy / undeploy / set mode ------------------------------------------------------------------------------

static func cmd_deploy(world: SimWorld, cmd: SimCommand) -> int:
	var res: Result = Result.new()
	var mcvs: Array[SimEntity] = []
	for e: SimEntity in cmd.actors:
		if e.kind == SimEntity.Kind.UNIT and world.economy != null and SimPlacement.hq_def_of_mcv(world, e.def_idx) >= 0:
			mcvs.append(e)
			continue
		_note(res, _deploy_one(world, e, cmd.def, SimMode.MODE_DEPLOYED))
	if not mcvs.is_empty():  # the MCV unfolds through economy's T_DEPLOY_MCV order
		var sub: SimCommand = SimCommand.new()
		sub.op = cmd.op
		sub.pid = cmd.pid
		sub.actors = mcvs
		var r2: int = world.economy.handle_command(world, sub)
		if r2 == SimCommand.Err.OK:
			res.ok = true
		elif not res.ok:
			cmd.detail = sub.detail
			return r2
	return _finish(cmd, res)


static func cmd_undeploy(world: SimWorld, cmd: SimCommand) -> int:
	var res: Result = Result.new()
	for e: SimEntity in cmd.actors:
		_note(res, _deploy_one(world, e, cmd.def, SimMode.MODE_MOBILE))
	return _finish(cmd, res)


static func _deploy_one(world: SimWorld, e: SimEntity, slot_arg: int, target: int) -> int:
	if e.abil == null:
		return SimAbilityEvents.RJ_NO_SLOT
	var slot: int = slot_arg if slot_arg >= 0 else SimMode.first_deploy_slot(world, e)
	if slot < 0 or slot >= e.abil.n_slots or not SimMode.is_deploy_like(world, e, slot):
		return SimAbilityEvents.RJ_NO_SLOT
	var r: int = SimMode.request_reason(world, e, slot, target)
	if r == 0:
		if not e.orders.is_empty():
			world.orders.clear(world, e, SimOrder.END_CANCELLED)  # a deploy order replaces the queue
		_used(world, e, slot)
	return r


static func cmd_set_mode(world: SimWorld, cmd: SimCommand) -> int:
	var res: Result = Result.new()
	for e: SimEntity in cmd.actors:
		_note(res, _set_mode_one(world, e, cmd.def, cmd.mode))
	return _finish(cmd, res)


static func _set_mode_one(world: SimWorld, e: SimEntity, slot_arg: int, mode: int) -> int:
	if e.abil == null:
		return SimAbilityEvents.RJ_NO_SLOT
	var slot: int = slot_arg
	if slot < 0:
		slot = e.abil.slot_of_kind(K.AK_MODE_SWITCH)
	if slot < 0 or slot >= e.abil.n_slots or e.abil.slots[slot * K.SLOT_STRIDE + K.SL_KIND] != K.AK_MODE_SWITCH:
		return SimAbilityEvents.RJ_NO_SLOT
	var target: int = mode
	if mode < 0:  # cycle
		var n: int = SimMode.mode_count(world, e, slot)
		target = (e.abil.slots[slot * K.SLOT_STRIDE + K.SL_STATE] + 1) % maxi(n, 1)
	var r: int = SimMode.request_reason(world, e, slot, target)
	if r == 0:
		_used(world, e, slot)
	return r


# ---- use ability / autocast ------------------------------------------------------------------------------------

static func cmd_use_ability(world: SimWorld, cmd: SimCommand) -> int:
	var res: Result = Result.new()
	for e: SimEntity in cmd.actors:
		_note(res, _use_one(world, e, cmd))
	return _finish(cmd, res)


static func _use_one(world: SimWorld, e: SimEntity, cmd: SimCommand) -> int:
	var ab: SimCompAbility = e.abil
	var slot: int = cmd.def
	if ab == null or slot < 0 or slot >= ab.n_slots:
		return SimAbilityEvents.RJ_NO_SLOT
	if e.container_id >= 0:
		return SimAbilityEvents.RJ_BAD_STATE
	var kind: int = ab.slots[slot * K.SLOT_STRIDE + K.SL_KIND]
	if world.combat != null and not world.combat.is_functional(world, e):
		return SimAbilityEvents.RJ_DISABLED
	if (ab.slots[slot * K.SLOT_STRIDE + K.SL_FLAGS] & K.SF_SUSPENDED) != 0:
		return SimAbilityEvents.RJ_DISABLED  # AB3: e.g. a Lagos carrier whose repair drone is down
	if SimChannel.is_channel_kind(kind):
		if cmd.mode == 1:
			SimChannel.cancel(world, e, slot)
			return 0
		var r: int = SimChannel.begin(world, e, slot, cmd.target)
		if r == 0:
			_used(world, e, slot)
		return r
	if world.zones != null and world.zones.has_method("use_ability"):
		var zr: int = int(world.zones.call("use_ability", world, e, slot, cmd.mode, cmd.target, cmd.x, cmd.y))
		if zr == 0:
			_used(world, e, slot, cmd.x, cmd.y)
		return zr
	return SimAbilityEvents.RJ_NO_SLOT  # zone-spawning abilities belong to the zone task


static func cmd_set_autocast(world: SimWorld, cmd: SimCommand) -> int:
	var res: Result = Result.new()
	for e: SimEntity in cmd.actors:
		_note(res, _autocast_one(world, e, cmd.def, cmd.mode))
	return _finish(cmd, res)


static func _autocast_one(world: SimWorld, e: SimEntity, slot: int, on: int) -> int:
	var ab: SimCompAbility = e.abil
	if ab == null or slot < 0 or slot >= ab.n_slots:
		return SimAbilityEvents.RJ_NO_SLOT
	var b: int = slot * K.SLOT_STRIDE
	if not AUTOCAST_KINDS.has(ab.slots[b + K.SL_KIND]):
		return SimAbilityEvents.RJ_NO_SLOT
	if on != 0:
		ab.slots[b + K.SL_FLAGS] |= K.SF_AUTOCAST
	else:
		ab.slots[b + K.SL_FLAGS] &= ~K.SF_AUTOCAST
	world.abilities.autocast_note(e.id)
	return 0


# ---- unload ----------------------------------------------------------------------------------------------------

static func cmd_unload(world: SimWorld, cmd: SimCommand) -> int:
	var res: Result = Result.new()
	for e: SimEntity in cmd.actors:
		_note(res, _unload_one(world, e, cmd))
	return _finish(cmd, res)


static func _unload_one(world: SimWorld, e: SimEntity, cmd: SimCommand) -> int:
	if e.cargo == null:
		return SimAbilityEvents.RJ_NO_SLOT
	var mode: int = 2 if cmd.mode == 1 else 1
	if e.cargo.n_pax == 0:
		return SimAbilityEvents.RJ_BAD_STATE
	if mode == 2 and e.cargo.index_of(cmd.target) < 0:
		return SimAbilityEvents.RJ_BAD_TARGET
	if e.kind == SimEntity.Kind.UNIT and world.orders.has_handler(SimOrder.T_UNLOAD):
		# units stop (or go to the drop point) first: the T_UNLOAD order calls begin_unload once they stand still
		var dx: int = cmd.x - e.x
		var dy: int = cmd.y - e.y
		var flags: int = (1 if dx * dx + dy * dy < IN_PLACE_U * IN_PLACE_U else 0) | (2 if mode == 1 else 0)
		var o: SimOrder = SimOrder.make(SimOrder.T_UNLOAD, cmd.target if mode == 2 else 0, cmd.x, cmd.y, flags)
		var err: int = world.orders.issue(world, e, o, SimOrder.QM_REPLACE)
		if err != SimCommand.Err.OK:
			return SimAbilityEvents.RJ_BAD_STATE
		_used(world, e, e.abil.slot_of_kind(K.AK_TRANSPORT) if e.abil != null else 0)
		return 0
	var r: int = SimTransport.unload_reject(world, e, mode, cmd.target)
	if r != 0:
		return r
	SimTransport.begin_unload(world, e, mode, cmd.target, cmd.x, cmd.y)
	return 0
