class_name SimAbilitySystem
extends SimSystem
## Pipeline stage 7 and the public facade of the abilities domain (abilities 3.2 / 5.6). AB-02 / AB-03 own the lifecycle
## hooks, slot instantiation, timed effects, the timer wheel, the watch pass (conditions, camouflage arming, end_on), heal
## pulses, the stat flush and the adapters movement calls (speed_units / is_immobile / is_turn_locked / request_pack).
## AB-04 / AB-05 / AB-06 add, in the order of 5.6.1: the mode protocol (SimMode: deploy, sensor_mast, mode_switch,
## submerge), the container step (SimTransport: passenger mirror, unload cadence), the aura update (SimAuraSystem:
## command / Relay fields, free healing, jammer, detector states), the auto-cast pass (SimChannel), and the executors of the
## commands DEPLOY / UNDEPLOY / SET_MODE / USE_ABILITY / SET_AUTOCAST / UNLOAD (SimAbilityCmds) plus the T_LOAD / T_UNLOAD /
## T_GARRISON order handlers (SimOrderCargo).
##
## Systems never store the SimWorld (a RefCounted cycle would leak); the movement adapters, which receive only the
## entity, reach it through a WeakRef set in init_world.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")

var fx_table: SimEffectTable = null
var wheel: SimTimerWheel = null
var watch_list: PackedInt32Array = PackedInt32Array()  ## ascending ids with abil.watch != 0
var dirty_ids: PackedInt32Array = PackedInt32Array()  ## ids whose stats.dirty went 0 -> nonzero (flushed at the end of update)
var heal_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids with an active HEAL effect
var bind_ids: PackedInt32Array = PackedInt32Array()  ## fresh entities whose conditional effects still need binding
var mode_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids of entities with a deploy / mode / submerge slot (SimMode.step)
var carrier_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids of containers with passengers or a running unload
var auto_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids of entities with an AUTOCAST repair slot
var aura: SimAuraSystem = null
var timer_digest: int = 0  ## rolling FNV over fired timers (tick, eid, kind)
var stat_timers: int = 0
var stat_watch_visits: int = 0

var _wr: WeakRef = null
var _due: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	stage_no = 7


func init_world(world: SimWorld) -> void:
	fx_table = SimEffectTable.new(world.data)
	wheel = SimTimerWheel.new()
	aura = SimAuraSystem.new()
	_wr = weakref(world)
	timer_digest = Checksum.FNV_OFFSET
	SimAbilityCmds.register(world)
	if world.orders != null:  # TM-14 cargo approach handlers (T_LOAD / T_UNLOAD / T_GARRISON)
		for t: int in [SimOrder.T_LOAD, SimOrder.T_UNLOAD, SimOrder.T_GARRISON]:
			if not world.orders.has_handler(t):
				world.orders.register_handler(t, SimOrderCargo.new(t))


func _w() -> SimWorld:
	return _wr.get_ref() as SimWorld if _wr != null else null


# ---- lifecycle hooks -------------------------------------------------------------------------------------------

func on_spawn(world: SimWorld, e: SimEntity) -> void:
	if fx_table == null or (e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE and e.kind != SimEntity.Kind.NEUTRAL):
		return
	var st: SimCompStats = SimCompStats.new()
	st.hp_max_last = e.hp_max
	st.dirty = K.K_ALL
	e.stats = st
	dirty_ids.append(e.id)
	_make_slots(world, e)
	if e.kind == SimEntity.Kind.NEUTRAL:
		_neutral_container(world, e)
	if e.owner >= 0 and _has_cond(world, e):
		bind_ids.append(e.id)  # leases need the combat component, which stage 8 allocates after this hook


## Called by the vision hook (stage 10, after combat's on_spawn): binds the conditional effects of a fresh entity now.
func finish_spawn(world: SimWorld, e: SimEntity) -> void:
	var n: int = bind_ids.size()
	if n > 0 and bind_ids[n - 1] == e.id:
		bind_ids.resize(n - 1)
		SimCond.bind_effects(world, e)


func _has_cond(world: SimWorld, e: SimEntity) -> bool:
	var l3: DefLayer3 = world.players[e.owner].view.layer3
	if e.kind == SimEntity.Kind.UNIT:
		return not l3.cond_effects_of_unit(e.def_idx).is_empty()
	return e.kind == SimEntity.Kind.STRUCTURE and not l3.cond_effects_of_struct(e.def_idx).is_empty()


func on_remove(world: SimWorld, e: SimEntity, _reason: int) -> void:
	if e.container_id >= 0:  # a passenger vanished inside its container
		var host: SimEntity = world.by_id[e.container_id] if e.container_id < world.by_id.size() else null
		if host != null:
			SimTransport.remove_passenger(world, host, e.id)
	if e.cargo != null and e.cargo.n_pax > 0:  # sold / consumed / scripted: everybody steps out unharmed
		SimTransport.eject_all(world, e, 0)
	if e.abil != null:
		if e.abil.watch != 0:
			watch_erase(e.id)
		if e.abil.n_fx != 0:
			heal_remove(e.id)
		_erase(mode_ids, e.id)
		_erase(auto_ids, e.id)
	_erase(carrier_ids, e.id)
	if aura != null:
		aura.on_remove(world, e)


func on_owner_changed(world: SimWorld, e: SimEntity, _old_owner: int) -> void:
	if e.stats == null:
		return
	SimStatus.clear_all(world, e, K.RR_OWNER)
	if e.abil != null:
		SimCond.unbind(world, e, e.abil, e.stats)
	if e.combat != null:
		SimCombatMods.clear_all(e.combat)
	if e.owner >= 0:
		SimCond.bind_effects(world, e)
	SimStats.mark_dirty(world, e, K.K_ALL)
	SimStealth.recompute(world, e, K.CR_MOVE)
	if aura != null:
		aura.forget(world, e)
	if e.cargo != null and e.cargo.n_pax > 0 and e.kind != SimEntity.Kind.NEUTRAL:
		SimTransport.eject_all(world, e, 0)  # a captured carrier does not keep the previous owner's passengers


## After DefLayer3.apply_research (production calls it): grants, conditional bindings, stat refresh, restamps.
func on_research_complete(pid: int, _research_idx: int) -> void:
	var world: SimWorld = _w()
	if world == null:
		return
	for id: int in world.own_ids(pid):
		var e: SimEntity = world.by_id[id]
		if e == null or e.stats == null or (e.flags & SimFlags.F_GONE) != 0:
			continue
		_grant_slots(world, e)
		SimCond.bind_effects(world, e)
		SimStats.mark_dirty(world, e, K.K_ALL)
		if world.vision != null and e.abil != null and e.abil.slot_of_kind(K.AK_DETECTOR) >= 0:
			world.vision.request_restamp(e.id)


## Capsule -> engine style def swap: rebuild slots, keep the hp fraction.
func on_def_changed(world: SimWorld, e: SimEntity, _old_def_idx: int) -> void:
	if e.stats == null:
		return
	if e.abil != null:
		SimStatus.clear_all(world, e, K.RR_CLEARED)
		SimCond.unbind(world, e, e.abil, e.stats)
		e.abil.n_slots = 0
		e.abil.slots.fill(0)
		e.abil.granted_mask = 0
		_erase(mode_ids, e.id)
		_erase(auto_ids, e.id)
		if aura != null:
			aura.forget(world, e)
			SimAbilitySystem._erase(aura.prov_ids, e.id)
			SimAbilitySystem._erase(aura.det_ids, e.id)
		if e.cargo != null and e.cargo.n_pax > 0:
			SimTransport.eject_all(world, e, 0)
		e.cargo = null
	_make_slots(world, e)
	SimCond.bind_effects(world, e)
	SimStats.mark_dirty(world, e, K.K_ALL)
	if world.vision != null:
		world.vision.request_restamp(e.id)


# ---- the stage ------------------------------------------------------------------------------------------------

func update(world: SimWorld) -> void:
	if wheel == null:
		return
	if not bind_ids.is_empty():
		var todo: PackedInt32Array = bind_ids
		bind_ids = PackedInt32Array()
		for bid: int in todo:
			var be: SimEntity = world.by_id[bid] if bid < world.by_id.size() else null
			if be != null and be.stats != null and (be.flags & SimFlags.F_GONE) == 0:
				SimCond.bind_effects(world, be)
	# b. due timers (stale ones re-validate and are ignored)
	wheel.pop_due(world.tick, _due)
	var n: int = _due.size()
	var i: int = 0
	while i < n:
		_on_timer(world, _due[i], _due[i + 1], _due[i + 2])
		i += 3
	# c. watch pass
	if not watch_list.is_empty():
		_watch_pass(world)
	# d. mode protocol: combat's wants in, transitions out, ext_deployed / ext_mode written before stage 8
	for mid: int in mode_ids:
		var me: SimEntity = world.by_id[mid]
		if me != null and (me.flags & SimFlags.F_GONE) == 0:
			SimMode.step(world, me)
	# e. containers: passenger position mirror and the unload cadence
	if not carrier_ids.is_empty():
		for cid: int in carrier_ids.duplicate():
			var ce: SimEntity = world.by_id[cid]
			if ce != null and (ce.flags & SimFlags.F_GONE) == 0:
				SimTransport.step(world, ce)
	# f. auras, command fields, Relay, detector states, free healing of the aura groups
	aura.update(world)
	# g. auto-cast pass (10 % of the entities per tick)
	if not auto_ids.is_empty():
		_auto_cast_pass(world)
	# free healing pulses of timed HEAL effects
	if world.tick % K.HEAL_PERIOD == 0 and not heal_ids.is_empty():
		_heal_pass(world)
	# lazy stats never leak into the hash: everything dirty is refreshed before the tick ends
	if not dirty_ids.is_empty():
		flush_stats(world)


func flush_stats(world: SimWorld) -> void:
	var ids: PackedInt32Array = dirty_ids
	dirty_ids = PackedInt32Array()
	ids.sort()
	for id: int in ids:
		var e: SimEntity = world.by_id[id] if id < world.by_id.size() else null
		if e != null and e.stats != null and e.stats.dirty != 0 and (e.flags & SimFlags.F_GONE) == 0:
			SimStats.refresh(world, e)


func _on_timer(world: SimWorld, eid: int, kind: int, gen: int) -> void:
	var e: SimEntity = world.by_id[eid] if eid < world.by_id.size() else null
	stat_timers += 1
	timer_digest = Checksum.mix(Checksum.mix(Checksum.mix(timer_digest, world.tick), eid), kind)
	if e == null or (e.flags & SimFlags.F_GONE) != 0:
		return
	match kind:
		K.TK_FX:
			SimStatus.expire_due(world, e)
		K.TK_CLOAK:
			SimStealth.recompute(world, e, K.CR_ARMED)
		K.TK_DISEMBARK:
			if e.abil != null and world.tick >= e.abil.disembark_until:
				SimCond.set_code(world, e, DefEnums.Cond.RECENTLY_DISEMBARKED, false)
		K.TK_BUILD, K.TK_COOLDOWN, K.TK_RESPAWN:
			SimZoneAbilities.on_timer(world, e, kind, gen)  # AB3: cover build / pack, spawn-ability cooldowns, drone respawn
		_:
			pass


func _watch_pass(world: SimWorld) -> void:
	var tick: int = world.tick
	var ids: PackedInt32Array = watch_list.duplicate()
	for id: int in ids:
		var e: SimEntity = world.by_id[id]
		if e == null or e.abil == null or (e.flags & SimFlags.F_GONE) != 0:
			continue
		var ab: SimCompAbility = e.abil
		var w: int = ab.watch
		stat_watch_visits += 1
		if (w & K.WF_CLOAK) != 0:
			for s: int in ab.n_slots:
				if ab.slots[s * K.SLOT_STRIDE] == K.AK_CAMOUFLAGE:
					SimStealth.arm_pass(world, e, s)
			SimStealth.recompute(world, e, K.CR_ARMED)
		if (w & K.WF_END_ON) != 0:
			SimStatus.check_end_on(world, e)
		if (w & K.WF_CELL) != 0:
			var cell: int = (e.y >> 10) * world.map.w + (e.x >> 10)
			if cell != ab.last_cell:
				ab.last_cell = cell
				SimCond.pull_pass(world, e, K.WF_CELL)
		if ((tick + id) & 1) == 0 and (w & (K.WF_STILL | K.WF_COMBAT)) != 0:
			SimCond.pull_pass(world, e, w & (K.WF_STILL | K.WF_COMBAT))
		if ((tick + id) & 3) == 0 and (w & K.WF_TARGET) != 0:
			SimCond.pull_pass(world, e, K.WF_TARGET)
		if (tick + id) % 10 == 0 and (w & K.WF_NEAR) != 0:
			SimCond.pull_pass(world, e, K.WF_NEAR)


func _heal_pass(world: SimWorld) -> void:
	var ids: PackedInt32Array = heal_ids.duplicate()
	for id: int in ids:
		var e: SimEntity = world.by_id[id]
		if e == null or e.abil == null or (e.flags & SimFlags.F_GONE) != 0:
			continue
		var ab: SimCompAbility = e.abil
		var rate: int = 0
		var lock: bool = false
		for j: int in K.MAX_FX:
			var idx: int = ab.fx[j * K.FX_STRIDE]
			if idx < 0:
				continue
			var fx: DefEffect = fx_table.effects[idx]
			if fx.op == DefEnums.EffectOp.HEAL:
				rate = maxi(rate, int(fx.params.get("rate_bps", 0)))
				lock = lock or bool(fx.params.get("cannot_fire", false))
		if rate <= 0 or e.hp >= e.hp_max or e.hp_max <= 0:
			continue
		ab.heal_frac += e.hp_max * rate / 20
		var whole: int = ab.heal_frac / 1000
		ab.heal_frac -= whole * 1000
		if whole > 0 and world.combat != null:
			world.combat.heal(world, e, whole)
		if lock:
			SimLeaseBridge.lock_weapons(world, e, world.tick + 2)


# ---- slots -----------------------------------------------------------------------------------------------------

## Owner's resolved ability list of e (roster clone when the owner has one).
func abilities_of(world: SimWorld, e: SimEntity) -> Array[DefAbility]:
	if e.kind == SimEntity.Kind.UNIT:
		if e.owner >= 0 and e.owner < world.players.size() and world.players[e.owner].roster.has_unit(e.def_idx):
			return world.players[e.owner].roster.unit(e.def_idx).abilities
		return world.data.units[e.def_idx].abilities
	if e.kind == SimEntity.Kind.STRUCTURE:
		if e.owner >= 0 and e.owner < world.players.size() and world.players[e.owner].roster.has_structure(e.def_idx):
			return world.players[e.owner].roster.structure(e.def_idx).abilities
		return world.data.structures[e.def_idx].abilities
	var none: Array[DefAbility] = []
	return none


func _make_slots(world: SimWorld, e: SimEntity) -> void:
	var list: Array[DefAbility] = abilities_of(world, e)
	for a: int in list.size():
		var da: DefAbility = list[a]
		if ((K.EXECUTED_MASK >> da.kind) & 1) != 0:
			_add_slot(world, e, da, a, false)
	_grant_slots(world, e)


## Research grants into free slots (kind already present = skipped, GRANTED flag).
func _grant_slots(world: SimWorld, e: SimEntity) -> void:
	if e.owner < 0 or e.owner >= world.players.size():
		return
	var l3: DefLayer3 = world.players[e.owner].view.layer3
	var granted: Array[DefAbility] = []
	if e.kind == SimEntity.Kind.UNIT:
		granted = l3.granted_abilities(e.def_idx)
	elif e.kind == SimEntity.Kind.STRUCTURE:
		granted = l3.struct_granted_abilities(e.def_idx)
	for g: int in granted.size():
		var da: DefAbility = granted[g]
		if ((K.EXECUTED_MASK >> da.kind) & 1) == 0 or (e.abil != null and e.abil.slot_of_kind(da.kind) >= 0):
			continue
		_add_slot(world, e, da, -1 - g, true)


func _add_slot(world: SimWorld, e: SimEntity, da: DefAbility, ab_idx: int, granted: bool) -> void:
	var ab: SimCompAbility = SimStatus.ensure_abil(world, e)
	if ab.n_slots >= K.MAX_SLOTS:
		return
	var s: int = ab.n_slots
	var b: int = s * K.SLOT_STRIDE
	ab.n_slots += 1
	ab.slots[b + K.SL_KIND] = da.kind
	ab.slots[b + K.SL_AB_IDX] = ab_idx
	ab.slots[b + K.SL_FLAGS] = K.SF_ENABLED | (K.SF_GRANTED if granted else 0)
	if granted:
		ab.granted_mask |= 1 << s
	var cc: SimCompCombat = e.combat
	match da.kind:
		K.AK_CAMOUFLAGE:
			var n: int = SimStealth.pack_camouflage(da.params)
			ab.slots[b + K.SL_N] = n
			ab.slots[b + K.SL_STATE] = K.CAM_ARMING
			ab.slots[b + K.SL_T_END] = world.tick + SimStealth.slot_delay(n)
			ab.slots[b + K.SL_AUX0] = cc.last_fire_tick if cc != null else SimCombatConsts.NEVER
			ab.slots[b + K.SL_AUX1] = cc.last_hit_tick if cc != null else SimCombatConsts.NEVER
			SimStealth.enable_watch(world, e)
			if e.vis != null:
				e.vis.stealth_kind |= K.SK_CAMOUFLAGE
		K.AK_DETECTOR:
			ab.slots[b + K.SL_STATE] = K.DET_ON
		K.AK_SUBMERGE:
			ab.slots[b + K.SL_STATE] = K.SUB_SUBMERGED
			ab.slots[b + K.SL_N] = int(da.params.get("surface_t", 160))
			SimStealth.enable_watch(world, e)
			if e.vis != null:
				e.vis.stealth_kind |= K.SK_SUBMARINE
			SimMode.init_slot(world, e, s)
		K.AK_DEPLOY, K.AK_SENSOR_MAST, K.AK_MODE_SWITCH:
			SimMode.init_slot(world, e, s)
			_insert(mode_ids, e.id)
		K.AK_COMMAND_FIELD:
			var dt: int = int(da.params.get("deploy_t", 0))
			ab.slots[b + K.SL_N] = dt
			if dt > 0:
				SimMode.init_slot(world, e, s)
		K.AK_TRANSPORT:
			var cg: SimCompCargo = SimCompCargo.new()
			cg.cap_slots = int(da.params.get("capacity_squads_n", 0))
			e.cargo = cg
		K.AK_REPAIR:
			if _repair_auto_default(world, e):
				ab.slots[b + K.SL_FLAGS] |= K.SF_AUTOCAST
				_insert(auto_ids, e.id)
	if aura != null:
		aura.on_slot_added(world, e, da.kind)


## Ability parameter after completed research (PARAM_MODs): unit or structure variant of DefLayer3.ability_param.
func ability_param(world: SimWorld, e: SimEntity, kind: int, key: String, base: int) -> int:
	if e.owner < 0 or e.owner >= world.players.size():
		return base
	var l3: DefLayer3 = world.players[e.owner].view.layer3
	var v: int
	if e.kind == SimEntity.Kind.STRUCTURE:
		v = l3.struct_ability_param(e.def_idx, kind, key, base)
	else:
		v = l3.ability_param(e.def_idx, kind, key, base)
	return SimStatus.fold_params(world, e, kind, key, v)  # AB3: active timed PARAM_MODs (Mobile Reserve ...)


## True when slot `slot` of e can be used now: it exists, is enabled and no transition or cooldown is running
## (cooldown kinds arrive with the zone task; their t_end is an absolute tick).
func slot_ready(e: SimEntity, slot: int) -> bool:
	var ab: SimCompAbility = e.abil
	if ab == null or slot < 0 or slot >= ab.n_slots:
		return false
	var b: int = slot * K.SLOT_STRIDE
	if (ab.slots[b + K.SL_FLAGS] & (K.SF_ENABLED | K.SF_SUSPENDED)) != K.SF_ENABLED:
		return false
	if ab.slots[b + K.SL_AUX0] >= 0 and ab.slots[b + K.SL_T_END] != 0 and SimMode.drives_kind(ab.slots[b + K.SL_KIND]):
		return false
	var w: SimWorld = _w()
	return w == null or ab.slots[b + K.SL_KIND] == K.AK_SUBMERGE or w.tick >= ab.slots[b + K.SL_T_END] or ab.slots[b + K.SL_AUX0] < 0


## Owner's resolved unit def of e (roster clone when the owner has one).
func unit_def(world: SimWorld, e: SimEntity) -> DefUnit:
	if e.kind != SimEntity.Kind.UNIT or e.def_idx < 0 or e.def_idx >= world.data.units.size():
		return null
	if e.owner >= 0 and e.owner < world.players.size() and world.players[e.owner].roster.has_unit(e.def_idx):
		return world.players[e.owner].roster.unit(e.def_idx)
	return world.data.units[e.def_idx]


## The DefAbility behind slot s (granted slots resolve through DefLayer3), null for virtual slots.
func slot_def(world: SimWorld, e: SimEntity, s: int) -> DefAbility:
	var ab: SimCompAbility = e.abil
	if ab == null or s < 0 or s >= ab.n_slots:
		return null
	var idx: int = ab.slots[s * K.SLOT_STRIDE + K.SL_AB_IDX]
	if idx >= 0:
		var list: Array[DefAbility] = abilities_of(world, e)
		return list[idx] if idx < list.size() else null
	if idx <= -100 or e.owner < 0 or e.owner >= world.players.size():
		return null
	var l3: DefLayer3 = world.players[e.owner].view.layer3
	var granted: Array[DefAbility] = l3.struct_granted_abilities(e.def_idx) if e.kind == SimEntity.Kind.STRUCTURE else l3.granted_abilities(e.def_idx)
	var g: int = -1 - idx
	return granted[g] if g < granted.size() else null


## Integer parameter `key` of slot s after completed research (bool params read as 0 / 1).
func sp(world: SimWorld, e: SimEntity, s: int, key: String, default: int) -> int:
	var ab: SimCompAbility = e.abil
	if ab == null or s < 0 or s >= ab.n_slots:
		return default
	var da: DefAbility = slot_def(world, e, s)
	var base: int = default
	if da != null and da.params.has(key):
		var v: Variant = da.params[key]
		if v is int or v is bool:
			base = int(v)
	return ability_param(world, e, ab.slots[s * K.SLOT_STRIDE + K.SL_KIND], key, base)


func mode_add(id: int) -> void:
	_insert(mode_ids, id)


func carrier_add(id: int) -> void:
	_insert(carrier_ids, id)


func carrier_remove(id: int) -> void:
	_erase(carrier_ids, id)


func autocast_note(id: int) -> void:
	var e: SimEntity = null
	var world: SimWorld = _w()
	if world != null:
		e = world.get_entity(id)
	var on: bool = false
	if e != null and e.abil != null:
		for s: int in e.abil.n_slots:
			var b: int = s * K.SLOT_STRIDE
			if e.abil.slots[b + K.SL_KIND] == K.AK_REPAIR and (e.abil.slots[b + K.SL_FLAGS] & K.SF_AUTOCAST) != 0:
				on = true
	if on:
		_insert(auto_ids, id)
	else:
		_erase(auto_ids, id)


## Repair actors default to auto-cast ON except the Engineer and Reclaimer classes (capture / salvage carriers).
func _repair_auto_default(world: SimWorld, e: SimEntity) -> bool:
	if e.kind != SimEntity.Kind.UNIT:
		return false
	var u: DefUnit = unit_def(world, e)
	return u != null and not u.has_ability(DefEnums.AbilityKind.CAPTURE) and not u.has_ability(DefEnums.AbilityKind.SALVAGE)


func _auto_cast_pass(world: SimWorld) -> void:
	var tick: int = world.tick
	for id: int in auto_ids:
		if (tick + id) % 10 != 0:
			continue
		var e: SimEntity = world.by_id[id]
		if e == null or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or e.abil == null:
			continue
		for s: int in e.abil.n_slots:
			var b: int = s * K.SLOT_STRIDE
			if e.abil.slots[b + K.SL_KIND] == K.AK_REPAIR and (e.abil.slots[b + K.SL_FLAGS] & K.SF_AUTOCAST) != 0:
				SimChannel.auto_cast(world, e, s)


## Neutral map structures with an ability side: the civilian garrison (cargo) and the Field Hospital (free heal aura).
func _neutral_container(world: SimWorld, e: SimEntity) -> void:
	if e.def_idx < 0 or e.def_idx >= world.data.neutrals.size():
		return
	var n: DefNeutral = world.data.neutrals[e.def_idx]
	if n.neutral_kind == DefEnums.NeutralKind.CIVILIAN_GARRISON and n.garrison_squads > 0:
		var cg: SimCompCargo = SimCompCargo.new()
		cg.cap_slots = n.garrison_squads
		e.cargo = cg
	elif n.neutral_kind == DefEnums.NeutralKind.FIELD_HOSPITAL:
		var ab: SimCompAbility = SimStatus.ensure_abil(world, e)
		var s: int = ab.n_slots
		ab.n_slots += 1
		var b: int = s * K.SLOT_STRIDE
		ab.slots[b + K.SL_KIND] = K.AK_HEAL
		ab.slots[b + K.SL_AB_IDX] = SimAuraSystem.HOSPITAL_ID
		ab.slots[b + K.SL_FLAGS] = K.SF_ENABLED
		aura.on_slot_added(world, e, K.AK_HEAL)


## Roster modifiers with the condition IN_CIVILIAN_GARRISON (El-Andalus +20 % damage): held as a DMG_OUT lease while the squad
## is garrisoned (key FXK(SRC_TRAIT, cond)), released when it leaves. The value comes from the roster's conditional
## applications, so the bible number stays in the data.
func garrison_bonus(world: SimWorld, p: SimEntity, inside: bool) -> void:
	if p.combat == null or p.owner < 0 or p.owner >= world.players.size():
		return
	var key: int = K.fxk(K.SRC_TRAIT, DefEnums.Cond.IN_CIVILIAN_GARRISON)
	if not inside:
		SimCombatMods.clear_key(p, key)
		return
	for ca: DefCondApplication in world.players[p.owner].roster.conditional_applications():
		if ca.cond == DefEnums.Cond.IN_CIVILIAN_GARRISON and ca.stat == DefEnums.Stat.DAMAGE and ca.units.has(p.def_idx):
			SimCombatMods.apply(world, p, key, SimCombatConsts.STAT_DMG_OUT, ca.delta_bp, 0, K.LEASE_HOLD)


## Disembark hook (5.6.6): the unloaded unit's disembark_buff ability grants its temporary leases unless a buff still runs.
func on_disembark(world: SimWorld, p: SimEntity) -> void:
	SimPowerFx.on_disembark(world, p)  # AB3: a running Joint Landing window
	var ab: SimCompAbility = p.abil
	if ab == null:
		return
	var s: int = ab.slot_of_kind(K.AK_DISEMBARK_BUFF)
	if s < 0:
		return
	var refresh: bool = sp(world, p, s, "refresh_on_reboard", 0) != 0
	if world.tick < ab.disembark_until and not refresh:
		return  # reboarding cannot refresh
	var dur: int = sp(world, p, s, "duration_t", 120)
	if dur <= 0:
		return
	ab.disembark_until = world.tick + dur
	var idx: int = ab.slots[s * K.SLOT_STRIDE + K.SL_AB_IDX]
	var key: int = K.fxk(K.SRC_DISEMBARK, idx if idx >= 0 else 0x800000 + s)
	var dmg: int = sp(world, p, s, "damage_bonus_bp", 0)
	var red: int = sp(world, p, s, "damage_taken_reduction_bp", 0)
	SimCombatMods.clear_key(p, key)
	if dmg != 0:
		SimCombatMods.apply(world, p, key, SimCombatConsts.STAT_DMG_OUT, dmg, 0, dur)
	if red != 0:
		SimCombatMods.apply(world, p, key, SimCombatConsts.STAT_TAKEN, red, SimCombatConsts.FILTER_ALL_WEAPON, dur)
	SimCond.set_code(world, p, DefEnums.Cond.RECENTLY_DISEMBARKED, true)
	wheel.schedule(world.tick + dur, p.id, K.TK_DISEMBARK, 0)


# ---- watch / heal lists (ascending, unique) ---------------------------------------------------------------------

func watch_insert(id: int) -> void:
	_insert(watch_list, id)


func watch_erase(id: int) -> void:
	_erase(watch_list, id)


func heal_add(id: int) -> void:
	_insert(heal_ids, id)


func heal_remove(id: int) -> void:
	_erase(heal_ids, id)


static func _insert(arr: PackedInt32Array, id: int) -> void:
	var lo: int = 0
	var hi: int = arr.size()
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if arr[mid] < id:
			lo = mid + 1
		else:
			hi = mid
	if lo < arr.size() and arr[lo] == id:
		return
	arr.insert(lo, id)


static func _erase(arr: PackedInt32Array, id: int) -> void:
	var lo: int = 0
	var hi: int = arr.size()
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if arr[mid] < id:
			lo = mid + 1
		else:
			hi = mid
	if lo < arr.size() and arr[lo] == id:
		arr.remove_at(lo)


# ---- hooks the next wave fills ----------------------------------------------------------------------------------

## Extra bp on local stat k from aura groups the entity is covered by (ew_jammer: SIGHT -bp).
func aura_extra_bp(_world: SimWorld, e: SimEntity, k: int) -> int:
	return aura.extra_bp(e, k) if aura != null else 0


## TARGET_NEAR_FRIENDLY_UNIT provider test (Forward Fire Control, Observer Network).
func target_near_friendly(world: SimWorld, e: SimEntity, params: Dictionary) -> bool:
	return aura != null and aura.target_near(world, e, params)


## NEAR_FRIENDLY_UNIT / NEAR_FRIENDLY_STRUCTURE test of a bound conditional effect.
func near_friendly(world: SimWorld, e: SimEntity, code: int, params: Dictionary) -> bool:
	return aura != null and aura.near_friendly(world, e, code, params)


# ---- public API -------------------------------------------------------------------------------------------------

func apply_timed_effect(target_id: int, fx_idx: int, dur_ticks: int, src_pid: int, src_key: int) -> bool:
	var world: SimWorld = _w()
	if world == null:
		return false
	return SimStatus.apply(world, world.get_entity(target_id), fx_idx, src_key, dur_ticks, src_pid)


func clear_timed_effects(target_id: int, src_key: int) -> void:
	var world: SimWorld = _w()
	if world == null:
		return
	var e: SimEntity = world.get_entity(target_id)
	if e != null:
		SimStatus.clear_source(world, e, src_key, K.RR_CLEARED)


## Effective SPEED in units per tick (movement adapter).
func speed_units(e: SimEntity) -> int:
	var st: SimCompStats = e.stats
	var v: int
	if st != null and st.dirty == 0:
		v = st.vals[K.K_SPEED]
	else:
		var world: SimWorld = _w()
		if world == null:
			return e.move.speed_base if e.move != null else 0
		v = SimStats.get_val(world, e, DefEnums.Stat.SPEED)
	if st != null and (st.flags & K.DF_UNLOAD_MOVING) != 0 and e.abil != null:  # Mobile Reserve: slower while unloading
		var w2: SimWorld = _w()
		var s: int = e.abil.slot_of_kind(K.AK_TRANSPORT)
		if w2 != null and s >= 0:
			v = v * sp(w2, e, s, "unload_moving_speed_bp", 10000) / 10000
	return v


func sight_units(e: SimEntity) -> int:
	var st: SimCompStats = e.stats
	if st != null and st.dirty == 0:
		return st.vals[K.K_SIGHT]
	var world: SimWorld = _w()
	return SimStats.get_val(world, e, DefEnums.Stat.SIGHT) if world != null else 0


## Deployed / deploying / building / packing (movement adapter).
func is_immobile(e: SimEntity) -> bool:
	var st: SimCompStats = e.stats
	if st != null and (st.flags & K.DF_IMMOBILE) != 0:
		return true
	if e.cargo != null and e.cargo.load_until > 0:  # a boarding holds the carrier for load_t ticks
		var w: SimWorld = _w()
		return w != null and e.cargo.load_until > w.tick
	return false


## AB3: summons flagged uncontrollable (decoys, swarm drones, zone bodies, engines) reject every order that is not the
## domain's own internal one (OF_AUTO), so commands from players never steer them.
func order_gate(_world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	if e.stats != null and (e.stats.flags & K.DF_UNCONTROLLABLE) != 0 and (o.flags & SimOrder.OF_AUTO) == 0:
		return SimCommand.Err.DISABLED
	return SimCommand.Err.OK


func is_turn_locked(e: SimEntity) -> bool:
	return e.stats != null and (e.stats.flags & K.DF_TURN_LOCKED) != 0


func is_concealed(e: SimEntity) -> bool:
	return e.vis != null and e.vis.concealed != 0


func in_garrison(e: SimEntity) -> bool:
	return e.stats != null and (e.stats.flags & K.DF_IN_GARRISON) != 0


## Team occupying a civilian garrison, -1 while free: combat treats an occupied garrison as this team's.
func garrison_claim_team(e: SimEntity) -> int:
	return e.cargo.claim_team if e.cargo != null and e.kind == SimEntity.Kind.NEUTRAL else -1


## Movement calls this before a move (rate-limited by movement): starts packing a deployed (or deploying) slot. Returns
## nothing (movement's stub double overrides it with `-> void`); ask `is_immobile(e)` whether the unit is free to move.
func request_pack(e: SimEntity) -> void:
	var world: SimWorld = _w()
	if world != null:
		SimZoneAbilities.request_pack(world, e)  # AB3: a cover under construction is dropped, a packable piece is packed
		SimMode.request_pack(world, e)


## Temporary production-rate windows (Mobilization Order); NOTE(AB-08): SimPlayerFx.
func production_rate_bp(_pid: int, _queue_kind: int) -> int:
	return 10000


func hash_state(_world: SimWorld, buf: PackedInt32Array) -> void:
	buf.append(timer_digest)
	aura.hash_into(buf)


## Invariants of abilities 10.3 that this task owns; empty = OK.
func debug_validate(world: SimWorld) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e: SimEntity in world.entities:
		var ab: SimCompAbility = e.abil
		if ab == null or (e.flags & SimFlags.F_GONE) != 0:
			continue
		if ab.n_slots < 0 or ab.n_slots > K.MAX_SLOTS:
			out.append("e%d: n_slots %d" % [e.id, ab.n_slots])
		var used: int = 0
		for i: int in K.MAX_FX:
			var b: int = i * K.FX_STRIDE
			var idx: int = ab.fx[b]
			if idx < 0:
				continue
			used += 1
			if idx >= fx_table.size():
				out.append("e%d: fx %d out of range" % [e.id, idx])
			if ab.fx[b + K.FX_EXPIRE] < world.tick:  # AB3 FIX: an entry due at tick T is removed by stage 7 of step T, so it is still present when world.tick == T
				out.append("e%d: fx %d expired but present" % [e.id, idx])
		if used != ab.n_fx:
			out.append("e%d: n_fx %d != %d used" % [e.id, ab.n_fx, used])
		if (ab.watch != 0) != (watch_list.find(e.id) >= 0):
			out.append("e%d: watch %d vs watch_list" % [e.id, ab.watch])
		if e.stats != null and e.stats.cond_fx.size() > K.MAX_COND_FX:
			out.append("e%d: too many bound conditions" % e.id)
	out.append_array(invariants(world))
	return out


## Structural invariants of the containers and the aura registries (also run by SimInvariants at step boundaries).
func invariants(world: SimWorld) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e2: SimEntity in world.entities:
		if (e2.flags & SimFlags.F_GONE) != 0:
			continue
		var c: SimCompCargo = e2.cargo
		if c != null:
			var used: int = 0
			for i2: int in c.n_pax:
				var p: SimEntity = world.by_id[c.pax[i2]] if c.pax[i2] > 0 and c.pax[i2] < world.by_id.size() else null
				if p == null:
					out.append("e%d: passenger %d does not exist" % [e2.id, c.pax[i2]])
					continue
				used += c.pax_slots[i2]
				if p.container_id != e2.id or (p.flags & SimFlags.F_INSIDE) == 0:
					out.append("e%d: passenger %d is not inside it (container %d)" % [e2.id, p.id, p.container_id])
			if used != c.used_slots or c.used_slots > c.cap_slots:
				out.append("e%d: used_slots %d vs %d (cap %d)" % [e2.id, c.used_slots, used, c.cap_slots])
			if (c.n_pax > 0) != (carrier_ids.find(e2.id) >= 0):
				out.append("e%d: carrier_ids out of sync (n_pax %d)" % [e2.id, c.n_pax])
			if c.n_pax == 0 and c.claim_team >= 0:
				out.append("e%d: claim without occupants" % e2.id)
		if e2.container_id >= 0:
			var host: SimEntity = world.by_id[e2.container_id] if e2.container_id < world.by_id.size() else null
			if host != null and (host.cargo == null or host.cargo.index_of(e2.id) < 0):
				out.append("e%d: container %d does not list it" % [e2.id, e2.container_id])
	out.append_array(aura.debug_validate(world))
	if world.zones != null:  # AB3: zone table, interception slots, bodies, summon registry
		out.append_array(world.zones.debug_validate(world))
	return out
