class_name SimCond
extends RefCounted
## Runtime conditions of conditional effects (abilities 5.3). A bound effect is a DefEffect from
## DefLayer3.cond_effects_of_unit / struct; its truth is the AND of its condition codes. Pulled codes (STATIONARY,
## OUT_OF_COMBAT, ON_WATER, TARGET_NEAR) are evaluated in the watch pass per bound effect (each has its own
## threshold); pushed codes (DEPLOYED, IN_ZONE, RECENTLY_DISEMBARKED, IN_RELAY_FIELD, NEAR_FRIENDLY_*, CAMOUFLAGED,
## IN_CIVILIAN_GARRISON, STRUCTURE_POWERED) are set by their owner through `set_code` and stored in abil.cond_ext.
## A true bound effect is either a lease held with LEASE_HOLD (damage / range / reload / resist ...) or a local stat
## contribution (speed / sight / health) folded by SimStats.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const C := DefEnums.Cond

## Codes evaluated by pulling combat / map state.
const PULLED_MASK: int = (1 << C.ON_WATER) | (1 << C.ON_WATER_RT) | (1 << C.STATIONARY) | (1 << C.OUT_OF_COMBAT) | (1 << C.TARGET_NEAR_FRIENDLY_UNIT) \
	| (1 << C.NEAR_FRIENDLY_UNIT) | (1 << C.NEAR_FRIENDLY_STRUCTURE)


static func watch_add(world: SimWorld, e: SimEntity, flag: int) -> void:
	var ab: SimCompAbility = SimStatus.ensure_abil(world, e)
	if ab.watch == 0 and world.abilities != null:
		world.abilities.watch_insert(e.id)
	ab.watch |= flag
	if (flag & K.WF_CELL) != 0 and ab.last_cell < 0:
		ab.last_cell = (e.y >> 10) * world.map.w + (e.x >> 10)


static func watch_clear(world: SimWorld, e: SimEntity, flag: int) -> void:
	var ab: SimCompAbility = e.abil
	if ab == null or (ab.watch & flag) == 0:
		return
	ab.watch &= ~flag
	if ab.watch == 0:
		ab.last_cell = -1
		if world.abilities != null:
			world.abilities.watch_erase(e.id)


## (Re)builds stats.cond_fx from DefLayer3 and evaluates every bound effect once (never assumed false).
static func bind_effects(world: SimWorld, e: SimEntity) -> void:
	var st: SimCompStats = e.stats
	var sys: SimAbilitySystem = world.abilities
	if st == null or sys == null or e.owner < 0 or e.owner >= world.players.size():
		return
	var l3: DefLayer3 = world.players[e.owner].view.layer3
	var list: Array[DefEffect] = []
	if e.kind == SimEntity.Kind.UNIT:
		list = l3.cond_effects_of_unit(e.def_idx)
	elif e.kind == SimEntity.Kind.STRUCTURE:
		list = l3.cond_effects_of_struct(e.def_idx)
	var idxs: PackedInt32Array = PackedInt32Array()
	for fx: DefEffect in list:
		if idxs.size() >= K.MAX_COND_FX:
			break
		var ix: int = sys.fx_table.index_of(fx)
		if ix >= 0:
			idxs.append(ix)
	if idxs == st.cond_fx and e.abil != null:
		return
	if idxs.is_empty() and st.cond_fx.is_empty():
		return
	var ab: SimCompAbility = SimStatus.ensure_abil(world, e)
	unbind(world, e, ab, st)
	st.cond_fx = idxs
	var watch: int = 0
	for i: int in idxs.size():
		watch |= _watch_of(sys.fx_table.effects[idxs[i]])
	if watch != 0:
		watch_add(world, e, watch)
	for i2: int in idxs.size():
		var t: bool = truth(world, e, sys.fx_table.effects[idxs[i2]])
		if t:
			_flip(world, e, ab, st, i2, true)
	SimStats.mark_dirty(world, e, K.K_ALL)


## Drops every bound effect (leases released, stat contributions removed).
static func unbind(world: SimWorld, e: SimEntity, ab: SimCompAbility, st: SimCompStats) -> void:
	for i: int in st.cond_fx.size():
		if ((ab.cond_bits >> i) & 1) != 0:
			_flip(world, e, ab, st, i, false)
	ab.cond_bits = 0
	st.cond_fx = PackedInt32Array()


static func _watch_of(fx: DefEffect) -> int:
	var w: int = 0
	for code: int in fx.cond_codes:
		match code:
			C.STATIONARY:
				w |= K.WF_STILL
			C.OUT_OF_COMBAT:
				w |= K.WF_COMBAT
			C.TARGET_NEAR_FRIENDLY_UNIT:
				w |= K.WF_TARGET
			C.NEAR_FRIENDLY_UNIT, C.NEAR_FRIENDLY_STRUCTURE:
				w |= K.WF_NEAR
			C.ON_WATER, C.ON_WATER_RT:
				w |= K.WF_CELL
	return w


## Truth of all codes of `fx` for e now (pulled codes evaluated fresh, pushed codes read from cond_ext).
static func truth(world: SimWorld, e: SimEntity, fx: DefEffect) -> bool:
	var ab: SimCompAbility = e.abil
	for i: int in fx.cond_codes.size():
		var code: int = fx.cond_codes[i]
		var ok: bool
		if ((PULLED_MASK >> code) & 1) != 0:
			ok = _pull(world, e, code, fx.cond_params[i])
		else:
			ok = ab != null and ((ab.cond_ext >> code) & 1) != 0
		if not ok:
			return false
	return true


static func _pull(world: SimWorld, e: SimEntity, code: int, params: Dictionary) -> bool:
	var cc: SimCompCombat = e.combat
	match code:
		C.STATIONARY:
			return cc != null and cc.still_ticks >= int(params.get("for_t", 0))
		C.OUT_OF_COMBAT:
			return world.combat != null and world.combat.ticks_since_combat(world, e) >= int(params.get("for_t", 0))
		C.ON_WATER, C.ON_WATER_RT:
			return (e.flags & SimFlags.F_ON_WATER) != 0 or world.map.is_water(e.x >> 10, e.y >> 10)
		C.TARGET_NEAR_FRIENDLY_UNIT:
			return world.abilities != null and world.abilities.target_near_friendly(world, e, params)
		C.NEAR_FRIENDLY_UNIT, C.NEAR_FRIENDLY_STRUCTURE:
			return world.abilities != null and world.abilities.near_friendly(world, e, code, params)
	return false


## Re-reads every bound effect that has a pulled code (the watch pass calls this with the due watch flags).
static func pull_pass(world: SimWorld, e: SimEntity, watch_mask: int) -> void:
	var ab: SimCompAbility = e.abil
	var st: SimCompStats = e.stats
	var sys: SimAbilitySystem = world.abilities
	if ab == null or st == null or sys == null:
		return
	for i: int in st.cond_fx.size():
		var fx: DefEffect = sys.fx_table.effects[st.cond_fx[i]]
		if (_watch_of(fx) & watch_mask) == 0:
			continue
		var t: bool = truth(world, e, fx)
		if t != (((ab.cond_bits >> i) & 1) != 0):
			_flip(world, e, ab, st, i, t)


## Sets or clears a pushed condition code and re-evaluates the bound effects that use it.
static func set_code(world: SimWorld, e: SimEntity, code: int, value: bool) -> void:
	var st: SimCompStats = e.stats
	var sys: SimAbilitySystem = world.abilities
	if st == null or sys == null:
		return
	var ab: SimCompAbility = SimStatus.ensure_abil(world, e)
	var bit: int = 1 << code
	if ((ab.cond_ext & bit) != 0) == value:
		return
	ab.cond_ext = (ab.cond_ext | bit) if value else (ab.cond_ext & ~bit)
	for i: int in st.cond_fx.size():
		var fx: DefEffect = sys.fx_table.effects[st.cond_fx[i]]
		if not fx.cond_codes.has(code):
			continue
		var t: bool = truth(world, e, fx)
		if t != (((ab.cond_bits >> i) & 1) != 0):
			_flip(world, e, ab, st, i, t)


static func _flip(world: SimWorld, e: SimEntity, ab: SimCompAbility, st: SimCompStats, i: int, on: bool) -> void:
	var sys: SimAbilitySystem = world.abilities
	var fx_i: int = st.cond_fx[i]
	var fx: DefEffect = sys.fx_table.effects[fx_i]
	ab.cond_bits = (ab.cond_bits | (1 << i)) if on else (ab.cond_bits & ~(1 << i))
	var lk: int = SimLeaseBridge.local_stat_of(fx)
	if lk >= 0:
		SimStats.mark_dirty(world, e, 1 << lk)
		return
	var key: int = SimLeaseBridge.fxk(K.SRC_COND, fx_i)
	if on:
		SimLeaseBridge.hold(world, e, key, fx, 0, K.LEASE_HOLD)
	else:
		SimLeaseBridge.release(world, e, key)
