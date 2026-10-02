class_name SimStats
extends RefCounted
## Effective stat cache of the abilities domain (abilities 5.2.2 / 5.2.3): SPEED, SIGHT and HEALTH per entity,
## folded as DefLayer3.effective_*_stat(stat, def_idx, extra_bp) where extra_bp is the sum over distinct stack groups
## of the largest-|delta| contribution of the active timed effects and true bound conditions (auras add theirs through
## SimAbilitySystem.aura_extra_bp). Refresh is lazy per dirty bit and flushed for the whole tick at the end of stage 7.
## The sim reads with get_val (which refreshes); presentation code must use peek (never writes sim state).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")


## SimAbilityConsts.K_* of a DefEnums.Stat id, -1 for stats that are not cached here.
static func key_index(stat: int) -> int:
	match stat:
		DefEnums.Stat.SPEED:
			return K.K_SPEED
		DefEnums.Stat.SIGHT:
			return K.K_SIGHT
		DefEnums.Stat.HEALTH:
			return K.K_HEALTH
	return -1


static func stat_of_key(k: int) -> int:
	match k:
		K.K_SPEED:
			return DefEnums.Stat.SPEED
		K.K_SIGHT:
			return DefEnums.Stat.SIGHT
	return DefEnums.Stat.HEALTH


## This domain's derived flags (SimAbilityConsts.DF_*).
static func flags(e: SimEntity) -> int:
	return e.stats.flags if e.stats != null else 0


static func has_flag(e: SimEntity, df: int) -> bool:
	return e.stats != null and (e.stats.flags & df) != 0


static func set_flag(e: SimEntity, df: int, on: bool) -> void:
	var st: SimCompStats = e.stats
	if st == null:
		return
	var old: int = st.flags
	st.flags = (old | df) if on else (old & ~df)


## Marks local stats dirty: bit 0 SPEED, 1 SIGHT, 2 HEALTH.
static func mark_dirty(world: SimWorld, e: SimEntity, key_mask: int) -> void:
	var st: SimCompStats = e.stats
	if st == null:
		return
	if st.dirty == 0 and world.abilities != null:
		world.abilities.dirty_ids.append(e.id)
	st.dirty |= key_mask


## Effective value of SPEED / SIGHT / HEALTH (a DefEnums.Stat id); refreshes when dirty.
static func get_val(world: SimWorld, e: SimEntity, stat: int) -> int:
	var st: SimCompStats = e.stats
	var k: int = key_index(stat)
	if st == null or k < 0:
		return effective(world, e, stat, 0)
	if st.dirty != 0:
		refresh(world, e)
	return st.vals[k]


## Same value without writing anything (presentation, tests).
static func peek(world: SimWorld, e: SimEntity, stat: int) -> int:
	var st: SimCompStats = e.stats
	var k: int = key_index(stat)
	if st == null or k < 0:
		return effective(world, e, stat, 0)
	if st.dirty == 0:
		return st.vals[k]
	return effective(world, e, stat, _extra(world, e, k))


## Recomputes every dirty local stat; a changed max health rescales hp through combat, a changed sight radius asks
## the vision system to restamp.
static func refresh(world: SimWorld, e: SimEntity) -> void:
	var st: SimCompStats = e.stats
	if st == null:
		return
	var mask: int = st.dirty
	st.dirty = 0
	if mask == 0:
		return
	for k: int in K.K_COUNT:
		if (mask & (1 << k)) == 0:
			continue
		var extra: int = _extra(world, e, k)
		st.extra[k] = extra
		var nv: int = effective(world, e, stat_of_key(k), extra)
		var old: int = st.vals[k]
		st.vals[k] = nv
		if k == K.K_HEALTH:
			_apply_health(world, e, st, nv)
		elif k == K.K_SIGHT and nv != old and world.vision != null:
			world.vision.request_restamp(e.id)
	var view: DefPlayerView = _view(world, e)
	if view != null:
		st.l3_version = view.layer3.version


## Layer 3 (research) plus `extra_bp` on the def's resolved value; owner-less entities use the def's base value.
static func effective(world: SimWorld, e: SimEntity, stat: int, extra_bp: int) -> int:
	var view: DefPlayerView = _view(world, e)
	var data: GameData = world.data
	match e.kind:
		SimEntity.Kind.UNIT, SimEntity.Kind.WRECK:
			if view != null:
				return view.layer3.effective_unit_stat(stat, e.def_idx, extra_bp)
			var base: int = DefLayer3.unit_stat_value(stat, data.units[e.def_idx])
			return DefStatMath.effective(stat, base, base, extra_bp, data.economy)
		SimEntity.Kind.STRUCTURE:
			if view != null:
				return view.layer3.effective_struct_stat(stat, e.def_idx, extra_bp)
			var sb: int = DefLayer3.struct_stat_value(stat, data.structures[e.def_idx])
			return DefStatMath.effective(stat, sb, sb, extra_bp, data.economy)
		SimEntity.Kind.NEUTRAL:
			var n: DefNeutral = data.neutrals[e.def_idx]
			var nv: int = n.sight if stat == DefEnums.Stat.SIGHT else (n.health if stat == DefEnums.Stat.HEALTH else 0)
			return DefStatMath.effective(stat, nv, nv, extra_bp, data.economy)
	return 0


static func _view(world: SimWorld, e: SimEntity) -> DefPlayerView:
	if e.owner < 0 or e.owner >= world.players.size():
		return null
	return world.players[e.owner].view


static func _apply_health(world: SimWorld, e: SimEntity, st: SimCompStats, nv: int) -> void:
	var last: int = st.hp_max_last
	if nv == last or nv <= 0:
		return
	st.hp_max_last = nv
	if last <= 0 or e.hp_max <= 0 or (e.flags & SimFlags.F_DEAD) != 0:
		return
	var target: int = (e.hp_max * nv * 2 + last) / (last * 2)
	if world.combat != null:
		world.combat.rescale_hp(world, e, maxi(target, 1))
	else:
		world.set_hp_max(e, maxi(target, 1))


## Sum over distinct stack groups of the largest |delta| among the contributions to local stat k.
static func _extra(world: SimWorld, e: SimEntity, k: int) -> int:
	var ab: SimCompAbility = e.abil
	var sys: SimAbilitySystem = world.abilities
	if ab == null or sys == null:
		return sys.aura_extra_bp(world, e, k) if sys != null else 0
	var gk: PackedInt32Array = PackedInt32Array()
	var gv: PackedInt32Array = PackedInt32Array()
	var tbl: SimEffectTable = sys.fx_table
	for i: int in K.MAX_FX:
		var idx: int = ab.fx[i * K.FX_STRIDE]
		if idx < 0:
			continue
		var fx: DefEffect = tbl.effects[idx]
		if SimLeaseBridge.local_stat_of(fx) != k:
			continue
		var key: int = fx.stack_group if fx.stack_group >= 0 else (0x40000000 | (ab.fx[i * K.FX_STRIDE + 1] & 0x3FFFFFFF))
		_add(gk, gv, key, fx.delta_bp)
	if ab.cond_bits != 0:
		var cf: PackedInt32Array = e.stats.cond_fx
		for i2: int in cf.size():
			if ((ab.cond_bits >> i2) & 1) == 0:
				continue
			var cx: DefEffect = tbl.effects[cf[i2]]
			if SimLeaseBridge.local_stat_of(cx) != k:
				continue
			_add(gk, gv, cx.stack_group if cx.stack_group >= 0 else (0x20000000 | cf[i2]), cx.delta_bp)
	var total: int = sys.aura_extra_bp(world, e, k)
	for v: int in gv:
		total += v
	return total


static func _add(gk: PackedInt32Array, gv: PackedInt32Array, key: int, amount: int) -> void:
	for j: int in gk.size():
		if gk[j] == key:
			gv[j] = DefStatMath.stack_pick(gv[j], amount)
			return
	gk.append(key)
	gv.append(amount)
