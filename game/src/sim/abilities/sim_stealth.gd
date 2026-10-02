class_name SimStealth
extends RefCounted
## Camouflage arming, concealment and detection reveal rules (abilities 5.8). Pull-based: combat publishes
## last_fire_tick / last_hit_tick / still_ticks, so no hooks exist. Entities with a camouflage slot (or a timed
## camouflage grant, or a submerge slot) sit on the every-tick watch pass (WF_CLOAK).
##
## Camouflage slot packing (slots[base + SL_N]): bits 0..5 flags, bits 6..16 delay_t, bits 17..27 reveal_t.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const CF_NEEDS_STATIONARY: int = 1
const CF_NEEDS_NO_ATTACK: int = 2
const CF_MOVING_OK: int = 4
const CF_REVEAL_ON_FIRE: int = 8
const CF_REVEAL_ON_DAMAGE: int = 16
const CF_KEEPS_ABILITIES: int = 32


static func is_cloaked(e: SimEntity) -> bool:
	return e.vis != null and e.vis.concealed != 0 and (e.vis.stealth_kind & K.SK_CAMOUFLAGE) != 0 and not is_submerged(e)


static func is_submerged(e: SimEntity) -> bool:
	var ab: SimCompAbility = e.abil
	if ab == null:
		return false
	var s: int = ab.slot_of_kind(K.AK_SUBMERGE)
	return s >= 0 and ab.slots[s * K.SLOT_STRIDE + K.SL_STATE] == K.SUB_SUBMERGED


## Packs the hot camouflage parameters of an ability into the slot's `n` field.
static func pack_camouflage(p: Dictionary) -> int:
	var f: int = 0
	if bool(p.get("needs_stationary", false)):
		f |= CF_NEEDS_STATIONARY
	if bool(p.get("needs_no_attack", true)):
		f |= CF_NEEDS_NO_ATTACK
	if bool(p.get("moving_ok", false)):
		f |= CF_MOVING_OK
	if bool(p.get("reveal_on_fire", true)):
		f |= CF_REVEAL_ON_FIRE
	if bool(p.get("reveal_on_damage", true)):
		f |= CF_REVEAL_ON_DAMAGE
	if bool(p.get("keeps_abilities_active", false)):
		f |= CF_KEEPS_ABILITIES
	var delay: int = clampi(int(p.get("delay_t", 0)), 0, 2047)
	var reveal: int = clampi(int(p.get("reveal_t", 0)), 0, 2047)
	return f | (delay << 6) | (reveal << 17)


static func slot_delay(n: int) -> int:
	return (n >> 6) & 2047


static func slot_reveal(n: int) -> int:
	return (n >> 17) & 2047


## Entities with any stealth source join the every-tick pass.
static func enable_watch(world: SimWorld, e: SimEntity) -> void:
	SimCond.watch_add(world, e, K.WF_CLOAK)


## Timed camouflage grant (Silent Watch): sets / clears DF_CAMO_GRANTED.
static func grant_camouflage(world: SimWorld, e: SimEntity, on: bool) -> void:
	if e.stats == null:
		return
	SimStats.set_flag(e, K.DF_CAMO_GRANTED, on)
	if on:
		SimCond.watch_add(world, e, K.WF_CLOAK)
		if e.vis != null:
			e.vis.stealth_kind |= K.SK_CAMOUFLAGE
	recompute(world, e, K.CR_GRANT if on else K.CR_MOVE)


## Camouflage arming for one slot (every tick). Writes the slot state and re-derives concealment.
static func arm_pass(world: SimWorld, e: SimEntity, s: int) -> void:
	var ab: SimCompAbility = e.abil
	var cc: SimCompCombat = e.combat
	var b: int = s * K.SLOT_STRIDE
	var n: int = ab.slots[b + K.SL_N]
	var delay: int = slot_delay(n)
	var t_end: int = ab.slots[b + K.SL_T_END]
	var reason: int = 0
	if cc != null:
		var lf: int = cc.last_fire_tick
		var lh: int = cc.last_hit_tick
		if (n & CF_REVEAL_ON_FIRE) != 0 and lf > ab.slots[b + K.SL_AUX0]:
			t_end = maxi(t_end, lf + delay)
			ab.slots[b + K.SL_AUX0] = lf
			reason = K.CR_FIRE
		if (n & CF_REVEAL_ON_DAMAGE) != 0 and lh > ab.slots[b + K.SL_AUX1]:
			t_end = maxi(t_end, lh + maxi(delay, slot_reveal(n)))
			ab.slots[b + K.SL_AUX1] = lh
			reason = K.CR_DAMAGE
	# combat counts still_ticks only for armed entities, so the arming pass keeps its own clock: the last tick the
	# entity was seen moving; same numbers as combat's counter (0 on the tick after a move, +1 per quiet tick)
	if (cc != null and cc.ext_moving != 0) or (e.flags & SimFlags.F_MOVING) != 0:
		ab.moved_t = world.tick
	var still_ok: bool = (n & CF_NEEDS_STATIONARY) == 0 or world.tick - ab.moved_t - 1 >= delay
	ab.slots[b + K.SL_T_END] = t_end
	var cloaked: bool = world.tick >= t_end and still_ok
	var new_state: int = K.CAM_CLOAKED if cloaked else K.CAM_ARMING
	if ab.slots[b + K.SL_STATE] != new_state:
		ab.slots[b + K.SL_STATE] = new_state
		if reason == 0:
			reason = K.CR_ARMED if cloaked else K.CR_MOVE
		recompute(world, e, reason)


## Channel work by a unit with reveal_on_work (SimChannel): re-arm and decloak.
static func note_work(world: SimWorld, e: SimEntity, slot: int) -> void:
	var ab: SimCompAbility = e.abil
	if ab == null or slot < 0:
		return
	var b: int = slot * K.SLOT_STRIDE
	ab.slots[b + K.SL_T_END] = world.tick + slot_delay(ab.slots[b + K.SL_N])
	ab.slots[b + K.SL_STATE] = K.CAM_ARMING
	recompute(world, e, K.CR_WORK)


## Concealment = a source is active, DF_EXPOSED clear and tick >= revealed_until (5.8.1).
static func compute_concealed(world: SimWorld, e: SimEntity) -> bool:
	if e.kind != SimEntity.Kind.UNIT or e.stats == null or e.vis == null:
		return false
	if (e.stats.flags & K.DF_EXPOSED) != 0 or world.tick < e.vis.revealed_until:
		return false
	if (e.stats.flags & K.DF_CAMO_GRANTED) != 0:
		return true
	var ab: SimCompAbility = e.abil
	if ab == null:
		return false
	for s: int in ab.n_slots:
		var b: int = s * K.SLOT_STRIDE
		var kind: int = ab.slots[b]
		if kind == K.AK_CAMOUFLAGE and ab.slots[b + K.SL_STATE] == K.CAM_CLOAKED:
			return true
		if kind == K.AK_SUBMERGE and ab.slots[b + K.SL_STATE] == K.SUB_SUBMERGED:
			return true
	return false


## Re-derives vis.concealed; on a flip: flag, event, condition CAMOUFLAGED and an immediate mask recompute.
static func recompute(world: SimWorld, e: SimEntity, reason: int) -> void:
	var v: SimCompVision = e.vis
	if v == null:
		return
	var now: int = 1 if compute_concealed(world, e) else 0
	if now == v.concealed:
		return
	v.concealed = now
	if now != 0:
		e.flags |= SimFlags.F_CLOAKED
	else:
		e.flags &= ~SimFlags.F_CLOAKED
	world.emit(K.EV_CLOAK_CHANGED, e.x, e.y, e.id, now, reason)
	SimCond.set_code(world, e, DefEnums.Cond.CAMOUFLAGED, now != 0)
	if world.vision != null:
		world.vision.on_conceal_changed(world, e)
