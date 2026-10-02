class_name SimStatus
extends RefCounted
## Timed-effect engine (abilities 5.4): one compiled DefEffect on one entity for a duration. The per-entity table
## (SimCompAbility.fx, 10 entries of [fx_idx, src_key, expire_tick, aux]) is the only state; leases, local stats,
## camouflage and heal pulses are derived from it through SimLeaseBridge / SimStats / SimStealth / the heal pass.
## Window semantics: an effect applied in tick T with duration D is removed by the timer of tick T + D (start of stage 7).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")


static func _sys(world: SimWorld) -> SimAbilitySystem:
	return world.abilities


## Allocates e.abil when missing.
static func ensure_abil(world: SimWorld, e: SimEntity) -> SimCompAbility:
	if e.abil == null:
		var ab: SimCompAbility = SimCompAbility.new()
		ab.spawn_tick = world.tick
		ab.moved_t = world.tick - 1
		e.abil = ab
	return e.abil


## Applies (or refreshes) effect fx_idx on e for dur_ticks (0 = the effect's own duration). true when stored.
static func apply(world: SimWorld, e: SimEntity, fx_idx: int, src_key: int, dur_ticks: int, src_pid: int) -> bool:
	var sys: SimAbilitySystem = _sys(world)
	if sys == null or e == null or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or e.stats == null:
		return false
	var fx: DefEffect = sys.fx_table.get_effect(fx_idx)
	if fx == null:
		return false
	var dur: int = dur_ticks if dur_ticks > 0 else fx.duration_t
	if dur <= 0:
		return false  # permanent effects live in DefLayer3
	if fx.op == DefEnums.EffectOp.CAMOUFLAGE and ((e.stats.flags & K.DF_EXPOSED) != 0 or (e.combat != null and e.combat.ext_moving != 0)):
		return false  # exposed masts never hide; a grant only takes hold on an entity that is standing still
	var ab: SimCompAbility = ensure_abil(world, e)
	var expire: int = world.tick + dur
	var key: int = SimLeaseBridge.key_of_source(src_key)
	for i: int in K.MAX_FX:
		var b: int = i * K.FX_STRIDE
		if ab.fx[b] == fx_idx and ab.fx[b + K.FX_SRC] == src_key:
			ab.fx[b + K.FX_EXPIRE] = maxi(ab.fx[b + K.FX_EXPIRE], expire)
			ab.fx[b + K.FX_AUX] = world.tick
			_execute(world, e, fx, key, ab.fx[b + K.FX_EXPIRE] - world.tick, src_pid)
			sys.wheel.schedule(ab.fx[b + K.FX_EXPIRE], e.id, K.TK_FX, 0)
			world.emit(K.EV_FX_APPLIED, e.x, e.y, e.id, fx_idx, ab.fx[b + K.FX_EXPIRE])
			return true
	var slot: int = -1
	for i2: int in K.MAX_FX:
		if ab.fx[i2 * K.FX_STRIDE] < 0:
			slot = i2
			break
	if slot < 0:
		var min_i: int = 0
		var min_exp: int = 0x7FFFFFFF
		for i3: int in K.MAX_FX:
			var ex: int = ab.fx[i3 * K.FX_STRIDE + K.FX_EXPIRE]
			if ex < min_exp:
				min_exp = ex
				min_i = i3
		if expire <= min_exp:
			return false
		_remove_at(world, e, ab, min_i, K.RR_EVICTED)
		slot = min_i
	var w: int = slot * K.FX_STRIDE
	ab.fx[w] = fx_idx
	ab.fx[w + K.FX_SRC] = src_key
	ab.fx[w + K.FX_EXPIRE] = expire
	ab.fx[w + K.FX_AUX] = world.tick
	ab.n_fx += 1
	_execute(world, e, fx, key, dur, src_pid)
	if end_mask(fx) != 0:
		SimCond.watch_add(world, e, K.WF_END_ON)
	sys.wheel.schedule(expire, e.id, K.TK_FX, 0)
	world.emit(K.EV_FX_APPLIED, e.x, e.y, e.id, fx_idx, expire)
	return true


static func has(e: SimEntity, fx_idx: int) -> bool:
	var ab: SimCompAbility = e.abil
	if ab == null or ab.n_fx == 0:
		return false
	for i: int in K.MAX_FX:
		if ab.fx[i * K.FX_STRIDE] == fx_idx:
			return true
	return false


## true when effect fx_idx is active on e from exactly this source.
static func has_from(e: SimEntity, fx_idx: int, src_key: int) -> bool:
	var ab: SimCompAbility = e.abil
	if ab == null or ab.n_fx == 0:
		return false
	for i: int in K.MAX_FX:
		var b: int = i * K.FX_STRIDE
		if ab.fx[b] == fx_idx and ab.fx[b + K.FX_SRC] == src_key:
			return true
	return false


## Ability parameter after the entity's ACTIVE timed PARAM_MOD effects (a zone or power buff, e.g. Mobile Reserve's
## unload_moving_speed): order set -> add -> mul_bp, like DefLayer3._fold_params. `base` already holds research.
static func fold_params(world: SimWorld, e: SimEntity, kind: int, key: String, base: int) -> int:
	var ab: SimCompAbility = e.abil
	var sys: SimAbilitySystem = _sys(world)
	if ab == null or ab.n_fx == 0 or sys == null:
		return base
	var recs: Array[DefEffect] = []
	for i: int in K.MAX_FX:
		var idx: int = ab.fx[i * K.FX_STRIDE]
		if idx < 0:
			continue
		var fx: DefEffect = sys.fx_table.effects[idx]
		if fx.op == DefEnums.EffectOp.PARAM_MOD and fx.scope == DefEnums.ParamScope.ABILITY and fx.ability_kind == kind and fx.key == key:
			recs.append(fx)
	if recs.is_empty():
		return base
	recs = _dedupe_groups(recs)
	var v: int = base
	for r: DefEffect in recs:
		if r.param_op == DefEnums.ParamOp.SET:
			v = r.value
	for r2: DefEffect in recs:
		if r2.param_op == DefEnums.ParamOp.ADD:
			v += r2.value
	for r3: DefEffect in recs:
		if r3.param_op == DefEnums.ParamOp.MUL_BP:
			v = DefStatMath.apply_bp(v, r3.value - 10000)
	return v


## Entries sharing a stack_group and an operation count once: the largest magnitude wins (data_balance 5.8.2).
static func _dedupe_groups(recs: Array[DefEffect]) -> Array[DefEffect]:
	var out: Array[DefEffect] = []
	for r: DefEffect in recs:
		var replaced: bool = false
		if r.stack_group >= 0:
			for i: int in out.size():
				var o: DefEffect = out[i]
				if o.stack_group == r.stack_group and o.param_op == r.param_op:
					var mag_r: int = absi(r.value - 10000) if r.param_op == DefEnums.ParamOp.MUL_BP else absi(r.value)
					var mag_o: int = absi(o.value - 10000) if o.param_op == DefEnums.ParamOp.MUL_BP else absi(o.value)
					if mag_r > mag_o:
						out[i] = r
					replaced = true
					break
		if not replaced:
			out.append(r)
	return out


## Removes one effect (any src_key when src_key < 0).
static func remove(world: SimWorld, e: SimEntity, fx_idx: int, src_key: int, reason: int) -> void:
	var ab: SimCompAbility = e.abil
	if ab == null:
		return
	for i: int in K.MAX_FX:
		var b: int = i * K.FX_STRIDE
		if ab.fx[b] == fx_idx and (src_key < 0 or ab.fx[b + K.FX_SRC] == src_key):
			_remove_at(world, e, ab, i, reason)


## Removes every effect of one source (clear_timed_effects).
static func clear_source(world: SimWorld, e: SimEntity, src_key: int, reason: int) -> void:
	var ab: SimCompAbility = e.abil
	if ab == null or ab.n_fx == 0:
		return
	for i: int in K.MAX_FX:
		var b: int = i * K.FX_STRIDE
		if ab.fx[b] >= 0 and ab.fx[b + K.FX_SRC] == src_key:
			_remove_at(world, e, ab, i, reason)


static func clear_all(world: SimWorld, e: SimEntity, reason: int) -> void:
	var ab: SimCompAbility = e.abil
	if ab == null or ab.n_fx == 0:
		return
	for i: int in K.MAX_FX:
		if ab.fx[i * K.FX_STRIDE] >= 0:
			_remove_at(world, e, ab, i, reason)


## Removes every effect whose end_on mask intersects `event_mask` (RE_*).
static func remove_on_event(world: SimWorld, e: SimEntity, event_mask: int) -> void:
	var ab: SimCompAbility = e.abil
	var sys: SimAbilitySystem = _sys(world)
	if ab == null or ab.n_fx == 0 or sys == null:
		return
	for i: int in K.MAX_FX:
		var idx: int = ab.fx[i * K.FX_STRIDE]
		if idx >= 0 and (end_mask(sys.fx_table.effects[idx]) & event_mask) != 0:
			_remove_at(world, e, ab, i, K.RR_EVENT)


## Removes the entries whose expiry has come (timer TK_FX).
static func expire_due(world: SimWorld, e: SimEntity) -> void:
	var ab: SimCompAbility = e.abil
	if ab == null or ab.n_fx == 0:
		return
	for i: int in K.MAX_FX:
		var b: int = i * K.FX_STRIDE
		if ab.fx[b] >= 0 and ab.fx[b + K.FX_EXPIRE] <= world.tick:
			_remove_at(world, e, ab, i, K.RR_EXPIRED)


## Pull-based end_on checks of the every-tick watch pass (5.4.4): MOVE and FIRE.
static func check_end_on(world: SimWorld, e: SimEntity) -> void:
	var ab: SimCompAbility = e.abil
	var sys: SimAbilitySystem = _sys(world)
	if ab == null or sys == null:
		return
	if ab.n_fx == 0:
		SimCond.watch_clear(world, e, K.WF_END_ON)  # FIX (EC3B): a bare `watch &= ~flag` left the id in watch_list
		return
	var cc: SimCompCombat = e.combat
	if cc == null:
		return
	var pending: bool = false
	for i: int in K.MAX_FX:
		var b: int = i * K.FX_STRIDE
		var idx: int = ab.fx[b]
		if idx < 0:
			continue
		var m: int = end_mask(sys.fx_table.effects[idx])
		if m == 0:
			continue
		if ((m & K.RE_MOVE) != 0 and cc.ext_moving != 0) or ((m & K.RE_FIRE) != 0 and cc.last_fire_tick >= ab.fx[b + K.FX_AUX]):
			_remove_at(world, e, ab, i, K.RR_EVENT)
		else:
			pending = true
	if not pending:
		SimCond.watch_clear(world, e, K.WF_END_ON)


## RE_* mask of an effect's `end_on` list (move / fire / detected).
static func end_mask(fx: DefEffect) -> int:
	var m: int = 0
	for key: String in ["end_on", "breaks_on"]:  # Silent Watch spells it breaks_on
		if not fx.params.has(key):
			continue
		var v: Variant = fx.params[key]
		if v is String:
			m |= _end_bit(v)
		elif v is Array:
			for x: Variant in v:
				m |= _end_bit(str(x))
	if bool(fx.params.get("ends_on_move", false)) or fx.cond_codes.has(DefEnums.Cond.STATIONARY):
		m |= K.RE_MOVE  # "while stationary" as a timed effect: movement ends it (Armored Overwatch), Field Refurbishment
	return m


static func _end_bit(s: String) -> int:
	match s:
		"move":
			return K.RE_MOVE
		"fire":
			return K.RE_FIRE
		"detected", "detect":
			return K.RE_DETECT
	return 0


static func _execute(world: SimWorld, e: SimEntity, fx: DefEffect, key: int, ticks: int, src_pid: int) -> void:
	if fx.op == DefEnums.EffectOp.DISABLE and bool(fx.params.get("on_expire", false)):
		return  # "then cannot fire for N s": the lock starts when the window ends (_remove_at)
	var lk: int = SimLeaseBridge.local_stat_of(fx)
	if lk >= 0:
		SimStats.mark_dirty(world, e, 1 << lk)
		return
	match fx.op:
		DefEnums.EffectOp.CAMOUFLAGE:
			SimStealth.grant_camouflage(world, e, true)
		DefEnums.EffectOp.REVEAL:
			if world.vision != null:
				world.vision.force_reveal(world, e, world.tick + ticks)
		DefEnums.EffectOp.HEAL:
			world.abilities.heal_add(e.id)
		DefEnums.EffectOp.MARK:
			SimLeaseBridge.hold(world, e, key, fx, 0, ticks, world.team_of(src_pid))
			world.emit(K.EV_MARKED, e.x, e.y, e.id, 1)
		_:
			SimLeaseBridge.hold(world, e, key, fx, 0, ticks)


static func _remove_at(world: SimWorld, e: SimEntity, ab: SimCompAbility, i: int, reason: int) -> void:
	var sys: SimAbilitySystem = _sys(world)
	var b: int = i * K.FX_STRIDE
	var idx: int = ab.fx[b]
	if idx < 0:
		return
	var src: int = ab.fx[b + K.FX_SRC]
	ab.fx[b] = -1
	ab.fx[b + 1] = -1
	ab.fx[b + 2] = -1
	ab.fx[b + 3] = -1
	ab.n_fx -= 1
	var fx: DefEffect = sys.fx_table.effects[idx]
	var key: int = SimLeaseBridge.key_of_source(src)
	var lk: int = SimLeaseBridge.local_stat_of(fx)
	if lk >= 0:
		SimStats.mark_dirty(world, e, 1 << lk)
	else:
		SimLeaseBridge.release(world, e, key)
		# other entries of the same source share the lease key: re-hold what is still active
		for j: int in K.MAX_FX:
			var bj: int = j * K.FX_STRIDE
			var ij: int = ab.fx[bj]
			if ij >= 0 and SimLeaseBridge.key_of_source(ab.fx[bj + 1]) == key:
				var fj: DefEffect = sys.fx_table.effects[ij]
				SimLeaseBridge.hold(world, e, key, fj, 0, maxi(ab.fx[bj + 2] - world.tick, 1))
		match fx.op:
			DefEnums.EffectOp.CAMOUFLAGE:
				if not _has_op(sys, ab, DefEnums.EffectOp.CAMOUFLAGE):
					SimStealth.grant_camouflage(world, e, false)
			DefEnums.EffectOp.HEAL:
				if not _has_op(sys, ab, DefEnums.EffectOp.HEAL):
					sys.heal_remove(e.id)
			DefEnums.EffectOp.MARK:
				world.emit(K.EV_MARKED, e.x, e.y, e.id, 0)
	if reason == K.RR_EXPIRED and fx.op == DefEnums.EffectOp.DISABLE and bool(fx.params.get("on_expire", false)) and fx.duration_t > 0:
		SimLeaseBridge.lock_weapons(world, e, world.tick + fx.duration_t)
	world.emit(K.EV_FX_REMOVED, e.x, e.y, e.id, idx, reason)


static func _has_op(sys: SimAbilitySystem, ab: SimCompAbility, op: int) -> bool:
	for i: int in K.MAX_FX:
		var idx: int = ab.fx[i * K.FX_STRIDE]
		if idx >= 0 and sys.fx_table.effects[idx].op == op:
			return true
	return false
