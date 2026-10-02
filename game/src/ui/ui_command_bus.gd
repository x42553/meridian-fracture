class_name UiCommandBus
extends RefCounted
## The only path UI -> sim (ui.md 3.3, 5.8): turns intents and widget actions into command int arrays through
## `UiCmdCodec`, pre-validates them against the `UiSimPort` (ids alive and viewer-owned, fog, rules), enforces the
## per-turn budget, submits through the `UiNetPort` and gives the immediate feedback. Everything else is the sim's
## authority. `kind` in `issued` / `refused` is the SimCmd op of the command (0 for a resolver DENIED).

signal issued(kind: int, cmd: PackedInt32Array)  ## after a successful submit; cmd = the int array that was sent
signal refused(kind: int, reason: int)  ## pre-validation or port refusal; reason = UiSimPort.Rule or REFUSE_*

const REFUSE_NOT_ALLOWED: int = 100  ## observer / not playing
const REFUSE_RATE: int = 101  ## per-turn budget exceeded
const REFUSE_EMPTY: int = 102  ## no eligible units
const MAX_PER_TURN: int = 40
const ERROR_GAP_TICKS: int = 20  ## the rate-limit error cue plays at most once per second

## Settings mirrored by the app (input/move_speed_match, input/move_reverse): MOVE / ATTACK_MOVE / PATROL flag bits.
var move_speed_match: bool = false
var move_reverse: bool = false
## func() -> PackedInt32Array: the producers of the active sidebar tab, used by SET_RALLY when no producer is selected.
var rally_fallback: Callable = Callable()

var _net: UiNetPort = null
var _sim: UiSimPort = null
var _view: Object = null
var _audio: UiAudioPort = null
var _feedback: UiFeedback = null
var _turn: int = -1
var _count: int = 0
var _last: PackedInt32Array = PackedInt32Array()
var _last_error_tick: int = -1000
var _row: UiEntityRow = UiEntityRow.new()


func setup(net: UiNetPort, sim: UiSimPort, view: Object, audio: UiAudioPort, feedback: UiFeedback) -> void:
	_net = net
	_sim = sim
	_view = view
	_audio = audio
	_feedback = feedback


## Resets the per-turn command counter for the turn of `now_tick` (the bus also resets itself when net.tick() / 2 changes).
func begin_turn_budget(now_tick: int) -> void:
	_turn = now_tick >> 1
	_count = 0
	_last = PackedInt32Array()


## Commands submitted in the current turn.
func turn_count() -> int:
	return _count


# ---- intents ---------------------------------------------------------------------------------------------------------
## Submits the primary intent, then its extras in order; returns the number of commands submitted (0 = refused).
func dispatch(intent: UiOrderIntent) -> int:
	var n: int = 0
	for it: UiOrderIntent in intent.all_intents():
		n += _dispatch_one(it)
	return n


func _dispatch_one(it: UiOrderIntent) -> int:
	if it.kind == UiOrderIntent.Kind.NONE:
		return 0
	if it.kind == UiOrderIntent.Kind.DENIED:
		refused.emit(0, UiSimPort.Rule.BAD_ORDER)
		if _feedback != null:
			_feedback.denied(UiSimPort.Rule.BAD_ORDER, it.deny_reason)
		return 0
	var ids: PackedInt32Array = it.ids
	if it.kind == UiOrderIntent.Kind.SET_RALLY and ids.is_empty() and rally_fallback.is_valid():
		ids = rally_fallback.call()
	ids = _own(ids)
	if it.kind == UiOrderIntent.Kind.SELL:
		ids = _sellable(ids)
	if ids.is_empty() and it.kind != UiOrderIntent.Kind.USE_POWER and it.kind != UiOrderIntent.Kind.LAUNCH_SUPERWEAPON:
		refused.emit(_op_of_kind(it.kind), REFUSE_EMPTY)
		if _feedback != null:
			_feedback.denied(REFUSE_EMPTY, &"order.deny.no_valid_order")
		return 0
	if _needs_visible_target(it.kind) and it.target_eid > 0 and not _sim.can_target(it.target_eid):
		refused.emit(_op_of_kind(it.kind), UiSimPort.Rule.NO_VISION)
		if _feedback != null:
			_feedback.denied(UiSimPort.Rule.NO_VISION, UiContextResolver.DENY_NOT_VISIBLE, _def_of(ids))
		return 0
	var flags: int = it.move_flags | (UiCmdCodec.MF_SPEED_MATCH if move_speed_match else 0) | (UiCmdCodec.MF_REVERSE if move_reverse else 0)
	var target: int = maxi(it.target_eid, 0)
	var sent: int = 0
	match it.kind:
		UiOrderIntent.Kind.MOVE:
			sent = int(_submit(UiCmdCodec.move(ids, it.x, it.y, it.queued, flags)))
		UiOrderIntent.Kind.ATTACK:
			sent = int(_submit(UiCmdCodec.attack(ids, target, it.queued, it.force)))
		UiOrderIntent.Kind.ATTACK_MOVE:
			sent = int(_submit(UiCmdCodec.attack_move(ids, it.x, it.y, it.queued, flags)))
		UiOrderIntent.Kind.PATROL:
			sent = int(_submit(UiCmdCodec.patrol(ids, it.x, it.y, it.queued, flags)))
		UiOrderIntent.Kind.GUARD:
			sent = int(_submit(UiCmdCodec.guard(ids, target, 0 if target > 0 else it.x, 0 if target > 0 else it.y, it.queued)))
		UiOrderIntent.Kind.FORCE_FIRE:
			sent = int(_submit(UiCmdCodec.force_fire(ids, 0, it.x, it.y)))
		UiOrderIntent.Kind.CAPTURE:
			sent = int(_submit(UiCmdCodec.capture(ids, target, it.queued)))
		UiOrderIntent.Kind.REPAIR:
			sent = int(_submit(UiCmdCodec.repair(ids, target, it.queued)))
		UiOrderIntent.Kind.LOAD:
			sent = int(_submit(UiCmdCodec.load_units(ids, target, it.queued)))
		UiOrderIntent.Kind.GARRISON:
			sent = int(_submit(UiCmdCodec.garrison(ids, target, it.queued)))
		UiOrderIntent.Kind.SALVAGE:
			sent = int(_submit(UiCmdCodec.salvage(ids, target, it.queued)))
		UiOrderIntent.Kind.HARVEST:
			sent = int(_submit(UiCmdCodec.harvest(ids, it.x, it.y, it.queued)))
		UiOrderIntent.Kind.RETURN_BASE:
			sent = int(_submit(UiCmdCodec.return_to_base(ids, target, it.queued)))
		UiOrderIntent.Kind.RETURN_CASH:
			sent = int(_submit(UiCmdCodec.return_cargo(ids, target, it.queued)))
		UiOrderIntent.Kind.FOLLOW:
			sent = int(_submit(UiCmdCodec.follow(ids, target, it.queued)))
		UiOrderIntent.Kind.SET_RALLY:
			sent = int(_submit(UiCmdCodec.set_rally(ids, it.x, it.y, target)))
		UiOrderIntent.Kind.SELL:
			sent = int(_submit(UiCmdCodec.sell(ids)))
		UiOrderIntent.Kind.STRUCT_REPAIR:
			sent = int(_submit(UiCmdCodec.set_struct_repair(ids, it.arg)))
		UiOrderIntent.Kind.STANCE:
			sent = int(_submit(UiCmdCodec.set_stance(ids, it.arg)))
		UiOrderIntent.Kind.HOLD:
			sent = int(_submit(UiCmdCodec.hold(ids)))
		UiOrderIntent.Kind.STOP:
			sent = int(_submit(UiCmdCodec.stop(ids)))
		UiOrderIntent.Kind.SCATTER:
			sent = int(_submit(UiCmdCodec.scatter(ids)))
		UiOrderIntent.Kind.SCUTTLE:
			sent = int(_submit(UiCmdCodec.scuttle(ids)))
		UiOrderIntent.Kind.DEPLOY:
			sent = int(_submit(UiCmdCodec.deploy(ids, it.arg if it.arg != 0 else -1)))
		UiOrderIntent.Kind.UNDEPLOY:
			sent = int(_submit(UiCmdCodec.undeploy(ids, it.arg if it.arg != 0 else -1)))
		UiOrderIntent.Kind.UNLOAD:
			sent = _unload_ids(ids, it.arg2 == 0, target)
		UiOrderIntent.Kind.ABILITY:
			sent = int(_submit(UiCmdCodec.use_ability(ids, it.arg, target, it.x, it.y)))
		UiOrderIntent.Kind.USE_POWER:
			sent = int(use_power(it.arg, it.x, it.y, it.arg2, target))
		UiOrderIntent.Kind.LAUNCH_SUPERWEAPON:
			sent = int(launch_superweapon(it.x, it.y, it.arg2))
	if sent > 0 and _feedback != null and it.kind != UiOrderIntent.Kind.USE_POWER and it.kind != UiOrderIntent.Kind.LAUNCH_SUPERWEAPON:
		_feedback.order_issued(it.kind, it.x, it.y, ids, it.def_idx if it.def_idx >= 0 else _def_of(ids), it.target_eid)
	return sent


# ---- production ------------------------------------------------------------------------------------------------------
## TRAIN (count 1..5): one command, never `count` commands.
func train(producer_eid: int, unit_def: int, count: int) -> bool:
	count = clampi(count, 1, 5)
	var r: int = _sim.check_train(producer_eid, unit_def)
	if r != UiSimPort.Rule.OK:
		return _refuse(SimCmd.TRAIN, r)
	if _sim.unit_count() + _queued_units() + count > _sim.unit_cap():
		return _refuse(SimCmd.TRAIN, UiSimPort.Rule.UNIT_CAP)
	return _submit(UiCmdCodec.train(producer_eid, unit_def, count))


## TRAIN_CANCEL: removes that queue slot; the head refunds what it was paid (the sim).
func train_cancel(producer_eid: int, queue_index: int) -> bool:
	return _submit(UiCmdCodec.train_cancel(producer_eid, queue_index))


## TRAIN_CANCEL of the LAST instance of `unit_def` in the producer's queue; false if it is not queued.
func train_cancel_def(producer_eid: int, unit_def: int) -> bool:
	var q: PackedInt32Array = PackedInt32Array()
	var n: int = _sim.queue_of(producer_eid, q)
	for i: int in range(n - 1, -1, -1):
		if q[i] == unit_def:
			return train_cancel(producer_eid, i)
	return false


## Hold / resume: PRODUCER -> QUEUE_HOLD (ids = producers), CONSTRUCTION -> BUILD_HOLD, RESEARCH -> RESEARCH_HOLD.
func queue_hold(queue_kind: int, producer_ids: PackedInt32Array, hold_on: bool) -> bool:
	var ids: PackedInt32Array = producer_ids
	if queue_kind == UiCmdCodec.Hold.PRODUCER:
		ids = _own(producer_ids)
		if ids.is_empty():
			return _refuse(SimCmd.QUEUE_HOLD, REFUSE_EMPTY)
	return _submit(UiCmdCodec.queue_hold(queue_kind, ids, hold_on))


func build_start(struct_def: int, count: int = 1) -> bool:
	var r: int = _sim.check_build(struct_def)
	if r != UiSimPort.Rule.OK:
		return _refuse(SimCmd.BUILD_START, r)
	return _submit(UiCmdCodec.build_start(struct_def, clampi(count, 1, 5)))


## BUILD_PLACE at the footprint's top-left CELL, rot 0-3.
func build_place(struct_def: int, cx: int, cy: int, rot: int = 0) -> bool:
	if _sim.check_place(struct_def, cx, cy, rot) != UiSimPort.Rule.OK:
		if _audio != null:
			_audio.ui(UiAudioPort.PLACE_FAIL)
		refused.emit(SimCmd.BUILD_PLACE, UiSimPort.Rule.BAD_SITE)
		return false
	var ok: bool = _submit(UiCmdCodec.build_place(struct_def, cx, cy, rot))
	if ok and _audio != null:
		_audio.ui(UiAudioPort.PLACE_OK)
	return ok


func build_cancel(queue_index: int) -> bool:
	return _submit(UiCmdCodec.build_cancel(queue_index))


func research(res_def: int) -> bool:
	var r: int = _sim.check_research(res_def)
	if r != UiSimPort.Rule.OK:
		return _refuse(SimCmd.RESEARCH, r)
	return _submit(UiCmdCodec.research(res_def))


func research_cancel(queue_index: int) -> bool:
	return _submit(UiCmdCodec.research_cancel(queue_index))


## SET_PRIMARY: the star on the queue strip.
func set_primary(producer_eid: int) -> bool:
	if _own(PackedInt32Array([producer_eid])).is_empty():
		return _refuse(SimCmd.SET_PRIMARY, REFUSE_EMPTY)
	return _submit(UiCmdCodec.set_primary(producer_eid))


## USE_POWER: `power_def` is the roster power index (the slot only orders the dock).
func use_power(power_def: int, x: int, y: int, angle: int, target_eid: int = 0) -> bool:
	var st: int = _sim.power_status(power_def)
	if st != UiSimPort.PowerStatus.READY:
		return _refuse(SimCmd.USE_POWER, UiSimPort.Rule.NO_CREDITS if st == UiSimPort.PowerStatus.NO_CREDITS else UiSimPort.Rule.NOT_READY)
	var d: GameData = _sim.data()
	var targeted: bool = d == null or power_def < 0 or power_def >= d.powers.size() or d.powers[power_def].target_mode != DefEnums.TargetMode.NONE
	if targeted and not _sim.power_target_ok(power_def, x, y):  # a power without a target has no point to see (x, y are 0)
		return _refuse(SimCmd.USE_POWER, UiSimPort.Rule.NO_VISION)
	return _submit(UiCmdCodec.use_power(power_def, x, y, angle, target_eid))


func launch_superweapon(x: int, y: int, angle: int) -> bool:
	if _sim.sw_status() != UiSimPort.SwStatus.READY:
		return _refuse(SimCmd.LAUNCH_SUPERWEAPON, UiSimPort.Rule.NOT_READY)
	if _sim.visibility(x >> 10, y >> 10) == UiSimPort.Vis.SHROUD:
		return _refuse(SimCmd.LAUNCH_SUPERWEAPON, UiSimPort.Rule.NO_VISION)
	return _submit(UiCmdCodec.launch_superweapon(x, y, angle))


# ---- structures ------------------------------------------------------------------------------------------------------
func sell(struct_ids: PackedInt32Array) -> bool:
	var ids: PackedInt32Array = _sellable(_own(struct_ids))
	if ids.is_empty():
		return _refuse(SimCmd.SELL, REFUSE_EMPTY)
	return _submit(UiCmdCodec.sell(ids))


## SET_STRUCT_REPAIR: 0 off / 1 on / 2 toggle.
func set_struct_repair(struct_ids: PackedInt32Array, mode: int) -> bool:
	var ids: PackedInt32Array = _own(struct_ids)
	if ids.is_empty():
		return _refuse(SimCmd.SET_STRUCT_REPAIR, REFUSE_EMPTY)
	return _submit(UiCmdCodec.set_struct_repair(ids, mode))


## UNDEPLOY_HQ (HQ -> MCV).
func undeploy_hq(hq_ids: PackedInt32Array) -> bool:
	var ids: PackedInt32Array = _own(hq_ids)
	if ids.is_empty():
		return _refuse(SimCmd.UNDEPLOY_HQ, REFUSE_EMPTY)
	return _submit(UiCmdCodec.undeploy_hq(ids))


func set_rally(producer_ids: PackedInt32Array, x: int, y: int, target_eid: int = 0, clear: bool = false) -> bool:
	var ids: PackedInt32Array = _own(producer_ids)
	if ids.is_empty():
		return _refuse(SimCmd.SET_RALLY, REFUSE_EMPTY)
	var ok: bool = _submit(UiCmdCodec.set_rally(ids, x, y, target_eid, clear))
	if ok and _audio != null:
		_audio.ui(UiAudioPort.RALLY_SET)
	return ok


# ---- unit orders -----------------------------------------------------------------------------------------------------
## SET_STANCE: 0 aggressive / 1 defensive / 2 hold fire / 3 guard.
func stance(ids: PackedInt32Array, stance_value: int) -> bool:
	return _unit_cmd(ids, UiOrderIntent.Kind.STANCE, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.set_stance(o, clampi(stance_value, 0, 3)))


## HOLD (hold position is an order, not a stance).
func hold(ids: PackedInt32Array) -> bool:
	return _unit_cmd(ids, UiOrderIntent.Kind.HOLD, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.hold(o))


## STOP / SCATTER / RETURN_CASH (RETURN_CARGO to the nearest refinery) / SCUTTLE; `kind` = UiOrderIntent.Kind.
func simple(kind: int, ids: PackedInt32Array) -> bool:
	match kind:
		UiOrderIntent.Kind.STOP:
			return _unit_cmd(ids, kind, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.stop(o))
		UiOrderIntent.Kind.SCATTER:
			return _unit_cmd(ids, kind, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.scatter(o))
		UiOrderIntent.Kind.RETURN_CASH:
			return _unit_cmd(ids, kind, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.return_cargo(o, 0, false))
		UiOrderIntent.Kind.SCUTTLE:
			return _unit_cmd(ids, kind, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.scuttle(o))
	return false


func follow(ids: PackedInt32Array, target_eid: int, queued: bool = false) -> bool:
	if ids.has(target_eid):
		return _refuse(SimCmd.FOLLOW, UiSimPort.Rule.NO_TARGET)
	return _unit_cmd(ids, UiOrderIntent.Kind.FOLLOW, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.follow(o, target_eid, queued))


## RETURN_TO_BASE: the clicked airfield / carrier, 0 = the nearest free pad or the carrier.
func return_to_base(ids: PackedInt32Array, base_eid: int = 0, queued: bool = false) -> bool:
	return _unit_cmd(ids, UiOrderIntent.Kind.RETURN_BASE, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.return_to_base(o, base_eid, queued))


## HARVEST target 0 at the deposit cell's centre.
func harvest(ids: PackedInt32Array, cell_x: int, cell_y: int, queued: bool = false) -> bool:
	var cx: int = UiCmdCodec.cell_center(cell_x)
	var cy: int = UiCmdCodec.cell_center(cell_y)
	return _unit_cmd(ids, UiOrderIntent.Kind.HARVEST, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.harvest(o, cx, cy, queued))


## DEPLOY (def -1: the sim routes an MCV) for units without F_DEPLOYED, UNDEPLOY(slot) for those with it: <= 2 commands
## per distinct slot.
func deploy_toggle(ids: PackedInt32Array) -> bool:
	var own: PackedInt32Array = _own(ids)
	if own.is_empty():
		return _refuse(SimCmd.DEPLOY, REFUSE_EMPTY)
	var plain: PackedInt32Array = PackedInt32Array()
	var packed: Dictionary = {}  ## slot -> ids
	for id: int in own:
		_sim.read(id, _row)
		if (_row.flags & UiEntityRow.F_DEPLOYED) != 0:
			var slot: int = _deploy_slot(_row.def_idx)
			var group: PackedInt32Array = packed.get(slot, PackedInt32Array())
			group.append(id)
			packed[slot] = group
		else:
			plain.append(id)
	var ok: bool = true
	var any: bool = false
	if not plain.is_empty():
		ok = _submit(UiCmdCodec.deploy(plain, -1)) and ok
		any = true
	for slot: Variant in packed:
		ok = _submit(UiCmdCodec.undeploy(packed[slot] as PackedInt32Array, int(slot))) and ok
		any = true
	if any and _feedback != null:
		_feedback.order_issued(UiOrderIntent.Kind.DEPLOY, 0, 0, own, _def_of(own))
	return any and ok


## USE_ABILITY op 0 (start); x, y -1 = none.
func use_ability(ids: PackedInt32Array, slot: int, target_eid: int = 0, x: int = -1, y: int = -1) -> bool:
	return _unit_cmd(ids, UiOrderIntent.Kind.ABILITY, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.use_ability(o, slot, target_eid, x, y))


func cancel_ability(ids: PackedInt32Array, slot: int) -> bool:
	return _unit_cmd(ids, UiOrderIntent.Kind.ABILITY, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.cancel_ability(o, slot))


## SET_MODE with an explicit target mode index (never -1), so a mixed group converges on one mode.
func set_mode(ids: PackedInt32Array, slot: int, mode: int) -> bool:
	return _unit_cmd(ids, UiOrderIntent.Kind.ABILITY, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.set_mode(o, slot, maxi(mode, 0)))


func set_autocast(ids: PackedInt32Array, slot: int, on: bool) -> bool:
	return _unit_cmd(ids, UiOrderIntent.Kind.ABILITY, func(o: PackedInt32Array) -> PackedInt32Array: return UiCmdCodec.set_autocast(o, slot, on))


## UNLOAD: one command per carrier at its own position (the exit-cell search starts there).
func unload(carrier_ids: PackedInt32Array, all: bool = true, passenger_eid: int = 0) -> bool:
	var ids: PackedInt32Array = _own(carrier_ids)
	if ids.is_empty():
		return _refuse(SimCmd.UNLOAD, REFUSE_EMPTY)
	return _unload_ids(ids, all, passenger_eid) == ids.size()


## Team map ping at a sim position (net relays it; the local marker is the caller's).
func ping(sim_x: int, sim_y: int) -> void:
	if _net != null and _net.can_submit():
		_net.send_map_ping(sim_x >> 10, sim_y >> 10)
	if _audio != null:
		_audio.ui(UiAudioPort.MINIMAP_PING)


# ---- internals -------------------------------------------------------------------------------------------------------
func _unload_ids(ids: PackedInt32Array, all: bool, passenger: int) -> int:
	var n: int = 0
	for id: int in ids:
		if not _sim.read(id, _row):
			continue
		var cmd: PackedInt32Array = UiCmdCodec.unload(PackedInt32Array([id]), all, passenger, _row.x, _row.y)
		if _submit(cmd):
			n += 1
	return n


## Filters to viewer-owned alive ids, builds with `build`, submits, then acknowledges.
func _unit_cmd(ids: PackedInt32Array, kind: int, build: Callable) -> bool:
	var own: PackedInt32Array = _own(ids)
	if own.is_empty():
		return _refuse(_op_of_kind(kind), REFUSE_EMPTY)
	var ok: bool = _submit(build.call(own))
	if ok and _feedback != null:
		_feedback.order_issued(kind, 0, 0, own, _def_of(own))
	return ok


func _refuse(kind: int, reason: int) -> bool:
	refused.emit(kind, reason)
	if _feedback != null:
		var key: StringName = &"notice.unit_cap" if reason == UiSimPort.Rule.UNIT_CAP else StringName("reject.%d" % reason)
		_feedback.denied(reason, key)
	elif _audio != null:
		_audio.ui(UiAudioPort.ERROR)
	return false


func _submit(cmd: PackedInt32Array) -> bool:
	var op: int = cmd[0]
	if _net == null or not _net.can_submit():
		refused.emit(op, REFUSE_NOT_ALLOWED)
		return false
	var turn: int = _net.tick() >> 1
	if turn != _turn:
		_turn = turn
		_count = 0
		_last = PackedInt32Array()
	if cmd == _last:
		return false
	if _count >= MAX_PER_TURN:
		refused.emit(op, REFUSE_RATE)
		var now: int = _net.tick()
		if _audio != null and now - _last_error_tick >= ERROR_GAP_TICKS:
			_last_error_tick = now
			_audio.ui(UiAudioPort.ERROR)
		return false
	if not _net.submit(cmd):
		refused.emit(op, REFUSE_NOT_ALLOWED)
		return false
	_count += 1
	_last = cmd.duplicate()
	issued.emit(op, cmd)
	return true


## Ids (ascending, unique) that are alive, owned by the viewer and not inside a container.
func _own(ids: PackedInt32Array) -> PackedInt32Array:
	var viewer: int = _sim.viewer_pid()
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		if id > 0 and _sim.read(id, _row) and _row.owner == viewer and (_row.flags & UiEntityRow.F_LOADED) == 0:
			out.append(id)
	out.sort()
	return out


func _sellable(ids: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		if _sim.sell_value(id) > 0:
			out.append(id)
	return out


func _def_of(ids: PackedInt32Array) -> int:
	if ids.is_empty() or not _sim.read(ids[0], _row):
		return -1
	return _row.def_idx


func _queued_units() -> int:
	var n: int = 0
	var p: PackedInt32Array = PackedInt32Array()
	var q: PackedInt32Array = PackedInt32Array()
	for qk: int in range(1, 6):
		var cnt: int = _sim.producers(qk, p)
		for i: int in cnt:
			n += _sim.queue_of(p[i], q)
	return n


func _deploy_slot(def_idx: int) -> int:
	var d: GameData = _sim.data()
	if d == null or def_idx < 0 or def_idx >= d.units.size():
		return -1
	var u: DefUnit = d.units[def_idx]
	if DefEnums.AbilityKind.DEPLOY < u.ability_slot_of_kind.size():
		return u.ability_slot_of_kind[DefEnums.AbilityKind.DEPLOY]
	return -1


static func _needs_visible_target(kind: int) -> bool:
	match kind:
		UiOrderIntent.Kind.ATTACK, UiOrderIntent.Kind.CAPTURE, UiOrderIntent.Kind.GARRISON, UiOrderIntent.Kind.LOAD, \
		UiOrderIntent.Kind.REPAIR, UiOrderIntent.Kind.SALVAGE, UiOrderIntent.Kind.FOLLOW:
			return true
	return false


## The SimCmd op an intent kind maps to (for `refused` before any command exists).
static func _op_of_kind(kind: int) -> int:
	match kind:
		UiOrderIntent.Kind.MOVE:
			return SimCmd.MOVE
		UiOrderIntent.Kind.ATTACK:
			return SimCmd.ATTACK
		UiOrderIntent.Kind.ATTACK_MOVE:
			return SimCmd.ATTACK_MOVE
		UiOrderIntent.Kind.GUARD:
			return SimCmd.GUARD
		UiOrderIntent.Kind.FORCE_FIRE:
			return SimCmd.FORCE_FIRE
		UiOrderIntent.Kind.CAPTURE:
			return SimCmd.CAPTURE
		UiOrderIntent.Kind.REPAIR:
			return SimCmd.REPAIR
		UiOrderIntent.Kind.LOAD:
			return SimCmd.LOAD
		UiOrderIntent.Kind.GARRISON:
			return SimCmd.GARRISON
		UiOrderIntent.Kind.SALVAGE:
			return SimCmd.SALVAGE
		UiOrderIntent.Kind.HARVEST:
			return SimCmd.HARVEST
		UiOrderIntent.Kind.RETURN_BASE:
			return SimCmd.RETURN_TO_BASE
		UiOrderIntent.Kind.RETURN_CASH:
			return SimCmd.RETURN_CARGO
		UiOrderIntent.Kind.SET_RALLY:
			return SimCmd.SET_RALLY
		UiOrderIntent.Kind.SELL:
			return SimCmd.SELL
		UiOrderIntent.Kind.STRUCT_REPAIR:
			return SimCmd.SET_STRUCT_REPAIR
		UiOrderIntent.Kind.STANCE:
			return SimCmd.SET_STANCE
		UiOrderIntent.Kind.HOLD:
			return SimCmd.HOLD
		UiOrderIntent.Kind.STOP:
			return SimCmd.STOP
		UiOrderIntent.Kind.SCATTER:
			return SimCmd.SCATTER
		UiOrderIntent.Kind.PATROL:
			return SimCmd.PATROL
		UiOrderIntent.Kind.FOLLOW:
			return SimCmd.FOLLOW
		UiOrderIntent.Kind.SCUTTLE:
			return SimCmd.SCUTTLE
		UiOrderIntent.Kind.DEPLOY:
			return SimCmd.DEPLOY
		UiOrderIntent.Kind.UNDEPLOY:
			return SimCmd.UNDEPLOY
		UiOrderIntent.Kind.UNLOAD:
			return SimCmd.UNLOAD
		UiOrderIntent.Kind.ABILITY:
			return SimCmd.USE_ABILITY
		UiOrderIntent.Kind.USE_POWER:
			return SimCmd.USE_POWER
		UiOrderIntent.Kind.LAUNCH_SUPERWEAPON:
			return SimCmd.LAUNCH_SUPERWEAPON
	return 0
