class_name SimChannel
extends RefCounted
## Channel abilities repair / salvage / capture (abilities 5.6.5). The work itself (walk-up, the paid-repair primitive,
## capture progress and the salvage action) is the economy domain's order state machines (SimOrderRepair /
## SimOrderSalvage / SimOrderCapture over SimEconomyWork); this class is the ability-side entry: CMD_USE_ABILITY and the
## auto-cast pass validate the slot and start / cancel exactly those orders, so there is ONE implementation of the
## numbers (1 % hp per second for 0.5 % of the paid price, 160-tick salvage action, ...).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const AUTO_RANGE_MUL: int = 2  ## auto-cast looks at 2 x the ability radius (5.6.3)
const AUTO_MIN_RANGE_U: int = 3072


static func is_channel_kind(kind: int) -> bool:
	return kind == K.AK_REPAIR or kind == K.AK_SALVAGE or kind == K.AK_CAPTURE


static func order_of(kind: int) -> int:
	match kind:
		K.AK_REPAIR:
			return SimOrder.T_REPAIR
		K.AK_SALVAGE:
			return SimOrder.T_SALVAGE
		K.AK_CAPTURE:
			return SimOrder.T_CAPTURE
	return SimOrder.T_NONE


static func find_slot(e: SimEntity, kind: int) -> int:
	return e.abil.slot_of_kind(kind) if e.abil != null else -1


## Starts the channel of `slot` on `target_eid`: 0 = accepted, else an RJ_* reason.
static func begin(world: SimWorld, e: SimEntity, slot: int, target_eid: int, auto: bool = false) -> int:
	if e.abil == null or slot < 0 or slot >= e.abil.n_slots:
		return SimAbilityEvents.RJ_NO_SLOT
	var kind: int = e.abil.slots[slot * K.SLOT_STRIDE + K.SL_KIND]
	if not is_channel_kind(kind) or e.kind != SimEntity.Kind.UNIT:
		return SimAbilityEvents.RJ_NO_SLOT
	var t: SimEntity = world.get_entity(target_eid)
	if t == null or (t.flags & SimFlags.F_GONE) != 0 or t == e:
		return SimAbilityEvents.RJ_BAD_TARGET
	var o: SimOrder = SimOrder.make(order_of(kind), target_eid, t.x, t.y, 0, 0, SimOrder.OF_AUTO if auto else 0)
	var err: int = world.orders.issue(world, e, o, SimOrder.QM_REPLACE)
	if err == SimCommand.Err.OK:
		return 0
	match err:
		SimCommand.Err.NO_TARGET, SimCommand.Err.WRONG_KIND, SimCommand.Err.BAD_ORDER:
			return SimAbilityEvents.RJ_BAD_TARGET
		SimCommand.Err.DISABLED:
			return SimAbilityEvents.RJ_DISABLED
		SimCommand.Err.NOT_AVAILABLE:
			return SimAbilityEvents.RJ_NO_SLOT
	return SimAbilityEvents.RJ_BAD_STATE


## Ends the channel: the actor's queue is cleared when its head is the channel's order.
static func cancel(world: SimWorld, e: SimEntity, slot: int) -> void:
	if e.abil == null or slot < 0 or slot >= e.abil.n_slots or e.orders.is_empty():
		return
	var kind: int = e.abil.slots[slot * K.SLOT_STRIDE + K.SL_KIND]
	if is_channel_kind(kind) and e.orders[0].type == order_of(kind):
		world.orders.clear(world, e, SimOrder.END_CANCELLED)


## Auto-cast repair (5.6.3): an idle repair actor with the AUTOCAST bit picks the eligible friendly target with the
## lowest health fraction within 2 x its ability radius (ties: lowest id) and starts repairing it.
static func auto_cast(world: SimWorld, e: SimEntity, slot: int) -> void:
	if not e.orders.is_empty() or e.kind != SimEntity.Kind.UNIT or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return
	var a: SimAbilitySystem = world.abilities
	var radius: int = maxi(a.sp(world, e, slot, "radius_u", 0) * AUTO_RANGE_MUL, AUTO_MIN_RANGE_U)
	var ids: PackedInt32Array = PackedInt32Array()
	world.query_circle(e.x, e.y, radius, ids, SimTag.ALIVE)
	var best: int = 0
	var best_num: int = 0
	var best_den: int = 1
	for id: int in ids:
		var t: SimEntity = world.by_id[id]
		if t == e or t.hp_max <= 0 or t.hp >= t.hp_max or t.owner < 0 or t.team != e.team:
			continue
		if t.kind != SimEntity.Kind.UNIT and t.kind != SimEntity.Kind.STRUCTURE:
			continue
		if SimEconomyWork.repair_can_target(world, e, t) != SimEconConst.RSN_OK:
			continue
		# lowest hp / hp_max wins: compare t.hp * best_den < best_num * t.hp_max
		if best == 0 or t.hp * best_den < best_num * t.hp_max:
			best = id
			best_num = t.hp
			best_den = t.hp_max
	if best != 0:
		begin(world, e, slot, best, true)
