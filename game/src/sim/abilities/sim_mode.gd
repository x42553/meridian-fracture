class_name SimMode
extends RefCounted
## Mode protocol of deploy / sensor_mast / mode_switch / submerge (and command_field slots with deploy_t > 0, the
## Mekong's embedded deploy) - abilities 5.6.4. Combat and abilities talk only through SimCompCombat: combat writes the
## levels `want_deploy / want_mode / want_surface`, this class writes `ext_deployed` (1 only while fully deployed) and
## `ext_mode` (current stable mode, -1 while a mode switch is in progress) whenever a transition starts or completes -
## always before combat runs (stage 7 precedes stage 8) - and the values persist in between.
##
## Slot layout (base = s * 8): state = stable mode (deploy: 0 mobile / 1 deployed; mode_switch: mode index; submerge:
## SUB_*), t_end = tick the running transition completes (0 = stable), aux0 = target mode of the running transition
## (-1 = stable), aux1 = mode queued to start right after it (-1 = none). Transitions complete inside `step` (no
## timers): the slot is the whole authoritative state.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const SUBMERGE_TRANSITION_T: int = 20
const MODE_MOBILE: int = 0
const MODE_DEPLOYED: int = 1


## Kinds whose slot runs the mode protocol (command_field only with deploy_t > 0, see drives).
static func drives_kind(kind: int) -> bool:
	return is_mode_kind(kind) or kind == K.AK_COMMAND_FIELD


static func is_mode_kind(kind: int) -> bool:
	return kind == K.AK_DEPLOY or kind == K.AK_SENSOR_MAST or kind == K.AK_MODE_SWITCH or kind == K.AK_SUBMERGE


## Slot kinds that follow the deploy protocol (mobile <-> deployed).
static func is_deploy_like(_world: SimWorld, e: SimEntity, s: int) -> bool:
	var kind: int = e.abil.slots[s * K.SLOT_STRIDE + K.SL_KIND]
	if kind == K.AK_DEPLOY or kind == K.AK_SENSOR_MAST:
		return true
	return kind == K.AK_COMMAND_FIELD and e.abil.slots[s * K.SLOT_STRIDE + K.SL_N] > 0  ## SL_N caches deploy_t


## True for a slot this class drives (its entity belongs to `mode_list`).
static func drives(world: SimWorld, e: SimEntity, s: int) -> bool:
	var kind: int = e.abil.slots[s * K.SLOT_STRIDE + K.SL_KIND]
	return is_mode_kind(kind) or (kind == K.AK_COMMAND_FIELD and is_deploy_like(world, e, s))


## Initialises a fresh slot (aux0 / aux1 = -1) and registers the entity in the mode list.
static func init_slot(world: SimWorld, e: SimEntity, s: int) -> void:
	var b: int = s * K.SLOT_STRIDE
	e.abil.slots[b + K.SL_AUX0] = -1
	e.abil.slots[b + K.SL_AUX1] = -1
	if world.abilities != null:
		world.abilities.mode_add(e.id)


static func mode_count(world: SimWorld, e: SimEntity, slot: int) -> int:
	var kind: int = e.abil.slots[slot * K.SLOT_STRIDE + K.SL_KIND]
	if kind == K.AK_MODE_SWITCH:
		return _modes(world, e, slot).size()
	return 2


static func current_mode(e: SimEntity, slot: int) -> int:
	if e.abil == null or slot < 0 or slot >= e.abil.n_slots:
		return -1
	return e.abil.slots[slot * K.SLOT_STRIDE + K.SL_STATE]


static func is_transitioning(e: SimEntity) -> bool:
	var ab: SimCompAbility = e.abil
	if ab == null:
		return false
	for s: int in ab.n_slots:
		var b: int = s * K.SLOT_STRIDE
		if ab.slots[b + K.SL_T_END] != 0 and ab.slots[b + K.SL_AUX0] >= 0 and drives_kind(ab.slots[b + K.SL_KIND]) and ab.slots[b + K.SL_KIND] != K.AK_SUBMERGE:
			return true
	return false


## Slot index of the first slot of the given deploy-like family for CMD_DEPLOY with slot -1: deploy, sensor_mast, then
## an embedded command_field deploy.
static func first_deploy_slot(world: SimWorld, e: SimEntity) -> int:
	var ab: SimCompAbility = e.abil
	if ab == null:
		return -1
	for s: int in ab.n_slots:
		if is_deploy_like(world, e, s):
			return s
	return -1


## True when a deploy-like slot is fully deployed (stable).
static func is_deployed(world: SimWorld, e: SimEntity) -> bool:
	var ab: SimCompAbility = e.abil
	if ab == null:
		return false
	for s: int in ab.n_slots:
		var b: int = s * K.SLOT_STRIDE
		if ab.slots[b + K.SL_STATE] == MODE_DEPLOYED and ab.slots[b + K.SL_AUX0] < 0 and is_deploy_like(world, e, s):
			return true
	return false


# ---- requests --------------------------------------------------------------------------------------------------

static func request(world: SimWorld, e: SimEntity, slot: int, target_mode: int) -> bool:
	return request_reason(world, e, slot, target_mode) == 0


## Starts a transition of the slot to target_mode. 0 = accepted, else an RJ_* reason (SimAbilityEvents).
static func request_reason(world: SimWorld, e: SimEntity, slot: int, target_mode: int) -> int:
	var ab: SimCompAbility = e.abil
	if ab == null or slot < 0 or slot >= ab.n_slots:
		return SimAbilityEvents.RJ_NO_SLOT
	if not drives(world, e, slot) or ab.slots[slot * K.SLOT_STRIDE + K.SL_KIND] == K.AK_SUBMERGE:
		return SimAbilityEvents.RJ_NO_SLOT
	var b: int = slot * K.SLOT_STRIDE
	if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return SimAbilityEvents.RJ_BAD_STATE
	if world.combat != null and not world.combat.is_functional(world, e):
		return SimAbilityEvents.RJ_DISABLED
	if ab.slots[b + K.SL_AUX0] >= 0:
		return SimAbilityEvents.RJ_BAD_STATE  # already transitioning
	var kind: int = ab.slots[b + K.SL_KIND]
	var n_modes: int = 2
	if kind == K.AK_MODE_SWITCH:
		n_modes = _modes(world, e, slot).size()
	if target_mode < 0 or target_mode >= n_modes:
		return SimAbilityEvents.RJ_BAD_STATE
	if ab.slots[b + K.SL_STATE] == target_mode:
		return SimAbilityEvents.RJ_BAD_STATE
	if kind == K.AK_MODE_SWITCH:
		var pad: int = world.abilities.sp(world, e, slot, "switch_at_structure_idx", -1)
		if pad >= 0 and not _on_pad(world, e, pad):
			return SimAbilityEvents.RJ_BAD_STATE
	_begin(world, e, slot, target_mode)
	return 0


static func _modes(world: SimWorld, e: SimEntity, slot: int) -> Array:
	var da: DefAbility = world.abilities.slot_def(world, e, slot)
	if da == null:
		return []
	var v: Variant = da.params.get("modes", [])
	return v as Array if v is Array else []


## Raptor loadout switch: the aircraft must sit on a pad of the matching airfield type.
static func _on_pad(world: SimWorld, e: SimEntity, structure_idx: int) -> bool:
	var a: SimCompAir = e.air
	if a == null or a.is_airfield != 0:
		return false
	if a.state != SimCombatConsts.AIR_PARKED and a.state != SimCombatConsts.AIR_REARM and a.state != SimCombatConsts.AIR_DOCKED:
		return false
	var home: SimEntity = world.get_entity(a.home_id)
	return home != null and home.kind == SimEntity.Kind.STRUCTURE and home.def_idx == structure_idx


static func _duration(world: SimWorld, e: SimEntity, slot: int, target: int) -> int:
	var kind: int = e.abil.slots[slot * K.SLOT_STRIDE + K.SL_KIND]
	var a: SimAbilitySystem = world.abilities
	match kind:
		K.AK_DEPLOY:
			return a.sp(world, e, slot, "deploy_t" if target == MODE_DEPLOYED else "pack_t", 0)
		K.AK_SENSOR_MAST:
			return a.sp(world, e, slot, "deploy_t", 0)
		K.AK_MODE_SWITCH:
			return a.sp(world, e, slot, "switch_t", 0)
		K.AK_COMMAND_FIELD:
			return e.abil.slots[slot * K.SLOT_STRIDE + K.SL_N]
	return 0


static func _begin(world: SimWorld, e: SimEntity, slot: int, target: int) -> void:
	var ab: SimCompAbility = e.abil
	var b: int = slot * K.SLOT_STRIDE
	var dur: int = _duration(world, e, slot, target)
	ab.slots[b + K.SL_AUX0] = target
	ab.slots[b + K.SL_T_END] = world.tick + dur
	# leaving the deployed mode drops its bonuses at once
	if ab.slots[b + K.SL_STATE] == MODE_DEPLOYED and is_deploy_like(world, e, slot):
		_release_deployed(world, e, slot)
	# no SimMovement.stop here: DF_IMMOBILE freezes the unit (movement brakes it to a halt) and its goal survives, so an
	# attack-move / move order resumes by itself when the transition ends; CMD_DEPLOY clears the queue explicitly instead
	refresh_flags(world, e)
	write_ext(world, e)
	if ab.slots[b + K.SL_KIND] == K.AK_SENSOR_MAST and world.vision != null:
		world.vision.request_restamp(e.id)  # the wide detector disc ends when the pack starts
	world.emit(K.EV_MODE_STARTED, e.x, e.y, e.id, slot, target)
	if dur <= 0:
		_complete(world, e, slot)


## One tick of the protocol for one entity (stage 7d): combat's wants in, transitions out. ext_deployed / ext_mode are
## written whenever a transition starts or completes (write_ext), so a quiet entity costs one scan of its slots.
static func step(world: SimWorld, e: SimEntity) -> void:
	var ab: SimCompAbility = e.abil
	var cc: SimCompCombat = e.combat
	if ab == null:
		return
	var tick: int = world.tick
	var wants: bool = cc != null and (cc.want_deploy != -1 or cc.want_mode != -1 or cc.want_surface != -1)
	if not wants:  # quiet: nothing to do unless a transition or a submarine phase is running
		var busy: bool = false
		for s0: int in ab.n_slots:
			var b0: int = s0 * K.SLOT_STRIDE
			if ab.slots[b0 + K.SL_AUX0] >= 0 and ab.slots[b0 + K.SL_T_END] != 0 and ab.slots[b0 + K.SL_KIND] != K.AK_SUBMERGE:
				busy = true
				break
			if ab.slots[b0 + K.SL_KIND] == K.AK_SUBMERGE and ab.slots[b0 + K.SL_STATE] != K.SUB_SUBMERGED:
				busy = true
				break
		if not busy:
			return
	var alive: bool = (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) == 0
	for s: int in ab.n_slots:
		var b: int = s * K.SLOT_STRIDE
		var kind: int = ab.slots[b + K.SL_KIND]
		if kind == K.AK_SUBMERGE:
			_step_submerge(world, e, s)
			continue
		if not drives(world, e, s):
			continue
		# completion
		if ab.slots[b + K.SL_AUX0] >= 0 and tick >= ab.slots[b + K.SL_T_END]:
			_complete(world, e, s)
		# combat's levels
		if alive and cc != null and ab.slots[b + K.SL_AUX0] < 0:
			if kind == K.AK_DEPLOY:
				if cc.want_deploy == 1 and ab.slots[b + K.SL_STATE] == MODE_MOBILE and cc.ext_moving == 0 and (e.flags & SimFlags.F_MOVING) == 0:
					request_reason(world, e, s, MODE_DEPLOYED)
				elif cc.want_deploy == 0 and ab.slots[b + K.SL_STATE] == MODE_DEPLOYED:
					request_reason(world, e, s, MODE_MOBILE)
			elif kind == K.AK_MODE_SWITCH and cc.want_mode >= 0 and ab.slots[b + K.SL_STATE] != cc.want_mode:
				request_reason(world, e, s, cc.want_mode)


## Publishes ext_deployed (1 only while fully deployed) and ext_mode (-1 during a mode switch) for combat.
static func write_ext(world: SimWorld, e: SimEntity) -> void:
	var cc: SimCompCombat = e.combat
	var ab: SimCompAbility = e.abil
	if cc == null or ab == null:
		return
	cc.ext_deployed = 1 if is_deployed(world, e) else 0
	var ms: int = ab.slot_of_kind(K.AK_MODE_SWITCH)
	if ms >= 0:
		var mb: int = ms * K.SLOT_STRIDE
		cc.ext_mode = -1 if ab.slots[mb + K.SL_AUX0] >= 0 else ab.slots[mb + K.SL_STATE]


static func _complete(world: SimWorld, e: SimEntity, slot: int) -> void:
	var ab: SimCompAbility = e.abil
	var b: int = slot * K.SLOT_STRIDE
	var target: int = ab.slots[b + K.SL_AUX0]
	if target < 0:
		return
	ab.slots[b + K.SL_STATE] = target
	ab.slots[b + K.SL_AUX0] = -1
	ab.slots[b + K.SL_T_END] = 0
	var kind: int = ab.slots[b + K.SL_KIND]
	if target == MODE_DEPLOYED and kind != K.AK_MODE_SWITCH:
		_apply_deployed(world, e, slot)
	if kind == K.AK_SENSOR_MAST:
		SimStealth.recompute(world, e, K.CR_MOVE)
		if world.vision != null:
			world.vision.request_restamp(e.id)
	elif kind == K.AK_COMMAND_FIELD and world.abilities.aura != null:
		world.abilities.aura.mark_provider(e.id)
	refresh_flags(world, e)
	write_ext(world, e)
	world.emit(K.EV_MODE_CHANGED, e.x, e.y, e.id, slot, target)
	var queued: int = ab.slots[b + K.SL_AUX1]
	ab.slots[b + K.SL_AUX1] = -1
	if queued >= 0 and queued != target:
		request_reason(world, e, slot, queued)


static func _key(ab: SimCompAbility, slot: int) -> int:
	var idx: int = ab.slots[slot * K.SLOT_STRIDE + K.SL_AB_IDX]
	return K.fxk(K.SRC_ABILITY, idx if idx >= 0 else 0x800000 + slot)


## Deployed: range and damage leases, restamp for masts.
static func _apply_deployed(world: SimWorld, e: SimEntity, slot: int) -> void:
	if e.combat == null:
		return
	var a: SimAbilitySystem = world.abilities
	var kind: int = e.abil.slots[slot * K.SLOT_STRIDE + K.SL_KIND]
	if kind != K.AK_DEPLOY:
		return
	var key: int = _key(e.abil, slot)
	var rb: int = a.sp(world, e, slot, "range_bonus_bp", 0)
	var db: int = a.sp(world, e, slot, "damage_bonus_bp", 0)
	if rb != 0:
		SimCombatMods.apply(world, e, key, SimCombatConsts.STAT_RANGE, rb, 0, K.LEASE_HOLD)
	if db != 0:
		SimCombatMods.apply(world, e, key, SimCombatConsts.STAT_DMG_OUT, db, 0, K.LEASE_HOLD)


static func _release_deployed(_world: SimWorld, e: SimEntity, slot: int) -> void:
	var kind: int = e.abil.slots[slot * K.SLOT_STRIDE + K.SL_KIND]
	if kind == K.AK_DEPLOY and e.combat != null:
		SimCombatMods.clear_key(e, _key(e.abil, slot))


## Recomputes the derived flags owned by this class from the slots: DF_IMMOBILE, DF_TURN_LOCKED, DF_EXPOSED and the
## F_DEPLOYED / F_DEPLOYING entity mirrors.
static func refresh_flags(world: SimWorld, e: SimEntity) -> void:
	var ab: SimCompAbility = e.abil
	if ab == null or e.stats == null:
		return
	var imm: bool = false
	var lock: bool = false
	var exposed: bool = false
	var deployed: bool = false
	var deploying: bool = false
	for s: int in ab.n_slots:
		var b: int = s * K.SLOT_STRIDE
		var kind: int = ab.slots[b + K.SL_KIND]
		if kind == K.AK_SUBMERGE or not drives(world, e, s):
			continue
		var transitioning: bool = ab.slots[b + K.SL_AUX0] >= 0
		var like: bool = is_deploy_like(world, e, s)
		if transitioning:
			imm = true
			deploying = deploying or like
		elif like and ab.slots[b + K.SL_STATE] == MODE_DEPLOYED:
			deployed = true
			if world.abilities.sp(world, e, s, "immobile", 1) != 0:
				imm = true
			if world.abilities.sp(world, e, s, "turn_locked", 0) != 0:
				lock = true
			if kind == K.AK_SENSOR_MAST:
				exposed = true
	var was_exposed: bool = (e.stats.flags & K.DF_EXPOSED) != 0
	SimStats.set_flag(e, K.DF_IMMOBILE, imm)
	SimStats.set_flag(e, K.DF_TURN_LOCKED, lock)
	SimStats.set_flag(e, K.DF_EXPOSED, exposed)
	e.flags = (e.flags | SimFlags.F_DEPLOYED) if deployed else (e.flags & ~SimFlags.F_DEPLOYED)
	e.flags = (e.flags | SimFlags.F_DEPLOYING) if deploying else (e.flags & ~SimFlags.F_DEPLOYING)
	if was_exposed != exposed:
		SimStealth.recompute(world, e, K.CR_MOVE)


## Movement asks (rate-limited) before a move order: starts packing the deployed / deploying slot.
static func request_pack(world: SimWorld, e: SimEntity) -> void:
	var ab: SimCompAbility = e.abil
	if ab == null:
		return
	for s: int in ab.n_slots:
		var b: int = s * K.SLOT_STRIDE
		if not drives(world, e, s) or not is_deploy_like(world, e, s):
			continue
		var target: int = ab.slots[b + K.SL_AUX0]
		if target < 0:
			if ab.slots[b + K.SL_STATE] == MODE_DEPLOYED and (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) == 0:
				_begin(world, e, s, MODE_MOBILE)  # combat's functional check is not applied: a shut-down unit may still pack
		elif target == MODE_DEPLOYED:
			ab.slots[b + K.SL_AUX1] = MODE_MOBILE  # unpack right after the deploy finished


# ---- submerge --------------------------------------------------------------------------------------------------

static func _step_submerge(world: SimWorld, e: SimEntity, s: int) -> void:
	var ab: SimCompAbility = e.abil
	var b: int = s * K.SLOT_STRIDE
	var cc: SimCompCombat = e.combat
	var tick: int = world.tick
	var want: bool = cc != null and cc.want_surface == 1
	var st: int = ab.slots[b + K.SL_STATE]
	var surface_t: int = ab.slots[b + K.SL_N]
	match st:
		K.SUB_SUBMERGED:
			if want:
				ab.slots[b + K.SL_STATE] = K.SUB_SURFACING
				ab.slots[b + K.SL_T_END] = tick + SUBMERGE_TRANSITION_T
				ab.slots[b + K.SL_AUX0] = tick
				SimStealth.recompute(world, e, K.CR_MOVE)
				world.emit(K.EV_MODE_STARTED, e.x, e.y, e.id, s, K.SUB_SURFACING)
		K.SUB_SURFACING:
			if tick >= ab.slots[b + K.SL_T_END]:
				_set_layer(world, e, SimEntity.Layer.SURFACE)
				ab.slots[b + K.SL_STATE] = K.SUB_SURFACED
				ab.slots[b + K.SL_T_END] = tick + surface_t
				world.emit(K.EV_MODE_CHANGED, e.x, e.y, e.id, s, K.SUB_SURFACED)
		K.SUB_SURFACED:
			if want:
				ab.slots[b + K.SL_T_END] = tick + surface_t
				ab.slots[b + K.SL_AUX0] = tick
			elif tick >= ab.slots[b + K.SL_T_END]:
				ab.slots[b + K.SL_STATE] = K.SUB_DIVING
				ab.slots[b + K.SL_T_END] = tick + SUBMERGE_TRANSITION_T
				world.emit(K.EV_MODE_STARTED, e.x, e.y, e.id, s, K.SUB_DIVING)
		K.SUB_DIVING:
			if tick >= ab.slots[b + K.SL_T_END]:
				_set_layer(world, e, SimEntity.Layer.UNDERWATER)
				ab.slots[b + K.SL_STATE] = K.SUB_SUBMERGED
				ab.slots[b + K.SL_T_END] = 0
				SimStealth.recompute(world, e, K.CR_ARMED)
				world.emit(K.EV_MODE_CHANGED, e.x, e.y, e.id, s, K.SUB_SUBMERGED)


static func _set_layer(world: SimWorld, e: SimEntity, layer: int) -> void:
	world.set_layer(e, layer)
	if e.move != null:
		e.move.lr_layer = -1
		e.move.hl = SimMoveConfig.HL_SUB if layer == SimEntity.Layer.UNDERWATER else SimMoveConfig.HL_WATER
	world.emit(SimMoveConfig.EV_LAYER_CHANGED, e.x, e.y, e.id, layer)
