class_name SimZoneFx
extends RefCounted
## Membership passes and effect application of zones (abilities 5.11.2). A continuous zone (smoke, cover, shelter,
## debris, repair station) re-evaluates its member list every PERIOD ticks: members gain each template effect as a timed
## effect (SimStatus, src_key FXK(SRC_ZONE, zone_idx), lasting until the zone's end) and lose it the moment they leave;
## one entry per (effect, source) means overlapping zones of one template never stack. A latched zone (every unit-buff
## power) applies once at creation and then only remains as a marker.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")


static func src_key_of(z: SimZone) -> int:
	return SimAbilityConsts.fxk(K.SRC_ZONE, z.zone_idx)


## Relation of the zone owner to entity e (DefEnums.AFFECTS_*).
static func related(z: SimZone, e: SimEntity) -> bool:
	if e.owner < 0:
		return false
	match z.affects:
		DefEnums.AFFECTS_FRIENDLY:
			return e.team == z.team
		DefEnums.AFFECTS_ENEMY:
			return e.team != z.team
	return true


static func is_moving(e: SimEntity) -> bool:
	return (e.flags & SimFlags.F_MOVING) != 0 or (e.combat != null and e.combat.ext_moving != 0)


## Standing still for cover purposes: not moving and, for armed entities, combat's still counter has started.
static func is_still(e: SimEntity) -> bool:
	if is_moving(e):
		return false
	var cc: SimCompCombat = e.combat
	return cc == null or cc.n_mounts == 0 or cc.still_ticks >= 1


## true when the entity is a zone body / temporary summon that must not be healed or buffed by station zones.
static func is_body(e: SimEntity) -> bool:
	return e.summon != null and (e.summon.flags & SimZoneConsts.SM_BODY) != 0


## Members of a continuous zone right now (ascending, <= MAX_MEMBERS): candidates in the shape that are eligible for the
## zone kind and match at least one effect selector.
static func collect(world: SimWorld, sys: SimZoneSystem, z: SimZone, d: DefZone, skip_excl: bool) -> PackedInt32Array:
	var cands: PackedInt32Array = PackedInt32Array()
	SimShape.query_shape(world, z.shape, z.ax, z.ay, z.bx, z.by, z.radius, cands)
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in cands:
		var e: SimEntity = world.by_id[id]
		if e == null or not _eligible(world, sys, z, d, e):
			continue
		if skip_excl and z.excl.has(id):
			continue
		out.append(id)
	if z.occ_max > 0:
		out = _occupants(world, z, out)
	if out.size() > SimZoneConsts.MAX_MEMBERS:
		out.resize(SimZoneConsts.MAX_MEMBERS)
	return out


static func _eligible(world: SimWorld, sys: SimZoneSystem, z: SimZone, d: DefZone, e: SimEntity) -> bool:
	if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
		return false
	if e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE:
		return false
	if not related(z, e):
		return false
	var any_sel: bool = false
	for fx: DefEffect in d.effects:
		if fx.op == DefEnums.EffectOp.REVEAL:
			continue
		if sys.selector_ok(world, e, fx.selector):
			any_sel = true
			break
	if not any_sel:
		return false
	match z.kind:
		DefEnums.ZoneKind.DEBRIS:
			if e.layer != SimEntity.Layer.GROUND or (e.flags & SimFlags.F_ON_WATER) != 0:
				return false
		DefEnums.ZoneKind.COVER, DefEnums.ZoneKind.SHELTER:
			if e.kind != SimEntity.Kind.UNIT or not is_still(e):
				return false
			if z.has_flag(SimZoneConsts.ZF_BUILDER_ONLY) and e.id != z.src_eid:
				return false
		DefEnums.ZoneKind.REPAIR:
			if e.id == z.bind_eid or e.id == z.body_eid or is_body(e):
				return false
			if z.has_flag(SimZoneConsts.ZF_ENDS_ON_MOVE) and is_moving(e):
				return false
	return true


## Cover / shelter: at most occ_max occupants, lowest ids first (the builder first for builder-only pieces).
static func _occupants(_world: SimWorld, z: SimZone, ids: PackedInt32Array) -> PackedInt32Array:
	if ids.size() <= z.occ_max:
		return ids
	var out: PackedInt32Array = PackedInt32Array()
	# incumbents keep their place: a full cover does not swap occupants every pass
	for id: int in ids:
		if out.size() < z.occ_max and z.is_member(id):
			out.append(id)
	for id2: int in ids:
		if out.size() >= z.occ_max:
			break
		if not out.has(id2):
			out.append(id2)
	out.sort()
	return out


## One membership pass of a continuous zone.
static func run_pass(world: SimWorld, sys: SimZoneSystem, z: SimZone) -> void:
	var d: DefZone = world.data.zones[z.zone_idx]
	if d.effects.is_empty():
		return
	var prev: PackedInt32Array = z.members
	if z.has_flag(SimZoneConsts.ZF_ENDS_ON_MOVE):
		for pid: int in prev:  # a member that is moving right now is out for the rest of the zone
			var pe: SimEntity = world.by_id[pid]
			if pe != null and is_moving(pe) and not z.excl.has(pid):
				z.excl.append(pid)
	var next: PackedInt32Array = collect(world, sys, z, d, true)
	var key: int = src_key_of(z)
	var tbl: SimEffectTable = world.abilities.fx_table
	if z.has_flag(SimZoneConsts.ZF_ENDS_ON_MOVE) and not prev.is_empty():
		# a member whose timed effect ended because it moved stays out for the rest of the zone
		var kept: PackedInt32Array = PackedInt32Array()
		for id: int in next:
			if prev.has(id) and _lost_effect(world, sys, z, d, tbl, world.by_id[id], key):
				z.excl.append(id)
			else:
				kept.append(id)
		next = kept
	for id2: int in prev:
		if not next.has(id2):
			release(world, sys, z, d, tbl, id2, key)
	for id3: int in next:
		var e: SimEntity = world.by_id[id3]
		for k: int in d.effects.size():
			var fx: DefEffect = d.effects[k]
			if fx.op == DefEnums.EffectOp.REVEAL or fx.op == DefEnums.EffectOp.SPAWN_ZONE:
				continue
			if not sys.selector_ok(world, e, fx.selector):
				continue
			if z.pa != 0 and fx.op == DefEnums.EffectOp.RESIST_MOD:
				# a builder's own magnitude (Alpine shelter 25 %, the ability's resist_bp) replaces the template's
				if not prev.has(id3):
					SimCombatMods.apply(world, e, key, SimCombatConsts.STAT_TAKEN, z.pa, SimLeaseBridge.filter_of(world, fx), maxi(z.t_end - world.tick, 1))
				continue
			var fx_idx: int = tbl.zone_effect(z.zone_idx, k)
			if fx_idx >= 0 and not SimStatus.has_from(e, fx_idx, key):
				SimStatus.apply(world, e, fx_idx, key, maxi(z.t_end - world.tick, 1), z.owner_pid)
	z.members = next
	z.n_members = next.size()
	sys.stat_members += next.size()


static func _lost_effect(world: SimWorld, sys: SimZoneSystem, z: SimZone, d: DefZone, tbl: SimEffectTable, e: SimEntity, key: int) -> bool:
	if e == null:
		return false
	for k: int in d.effects.size():
		var fx: DefEffect = d.effects[k]
		if fx.op == DefEnums.EffectOp.HEAL and sys.selector_ok(world, e, fx.selector):
			var fx_idx: int = tbl.zone_effect(z.zone_idx, k)
			return not SimStatus.has_from(e, fx_idx, key)
	return false


## Removes every effect of the zone from entity `id` (unless another zone of the same template still covers it).
static func release(world: SimWorld, sys: SimZoneSystem, z: SimZone, d: DefZone, tbl: SimEffectTable, id: int, key: int) -> void:
	var e: SimEntity = world.by_id[id] if id > 0 and id < world.by_id.size() else null
	if e == null or (e.flags & SimFlags.F_GONE) != 0:
		return
	if sys.covered_by_other(z, id):
		return
	if z.pa != 0:
		SimCombatMods.clear_key(e, key)
	for k: int in d.effects.size():
		var fx_idx: int = tbl.zone_effect(z.zone_idx, k)
		if fx_idx >= 0:
			SimStatus.remove(world, e, fx_idx, key, K.RR_EVENT)


## Ends a zone's hold on its members (zone end / cancel).
static func release_all(world: SimWorld, sys: SimZoneSystem, z: SimZone) -> void:
	if z.zone_idx < 0 or z.members.is_empty() or z.kind == DefEnums.ZoneKind.DECOY:
		return
	if z.membership == DefEnums.Membership.LATCHED:
		return  # a snapshot keeps its effects for their own duration
	var d: DefZone = world.data.zones[z.zone_idx]
	var tbl: SimEffectTable = world.abilities.fx_table
	var key: int = src_key_of(z)
	for id: int in z.members:
		release(world, sys, z, d, tbl, id, key)


## The snapshot of a latched (BUFF) zone: every friendly / eligible entity in the shape gains each matching effect once.
## Returns the number of distinct entities affected.
static func latch(world: SimWorld, sys: SimZoneSystem, z: SimZone) -> int:
	var d: DefZone = world.data.zones[z.zone_idx]
	var tbl: SimEffectTable = world.abilities.fx_table
	var key: int = src_key_of(z)
	var window: int = maxi(z.t_end - world.tick, 1)
	var cands: PackedInt32Array = PackedInt32Array()
	SimShape.query_shape(world, z.shape, z.ax, z.ay, z.bx, z.by, z.radius, cands)
	var hit: PackedInt32Array = PackedInt32Array()
	var smoke_at: PackedInt32Array = PackedInt32Array()
	var clears_sup: bool = bool(d.params.get("clears_existing_suppression", false))
	var clears_emp: bool = bool(d.params.get("clears_existing_emp_weapons_off", false))
	for id: int in cands:
		var e: SimEntity = world.by_id[id]
		if e == null or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
			continue
		if e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE:
			continue
		if not related(z, e):
			continue
		var touched: bool = false
		for k: int in d.effects.size():
			var fx: DefEffect = d.effects[k]
			if fx.op == DefEnums.EffectOp.REVEAL or not sys.selector_ok(world, e, fx.selector):
				continue
			if fx.cond_codes.has(DefEnums.Cond.STATIONARY) and is_moving(e):
				continue  # "while stationary": a moving unit gets nothing from a snapshot
			touched = true
			if fx.op == DefEnums.EffectOp.SPAWN_ZONE:
				if e.kind == SimEntity.Kind.UNIT:
					smoke_at.append(e.id)
				continue
			var fx_idx: int = tbl.zone_effect(z.zone_idx, k)
			if fx_idx < 0:
				continue
			var dur: int = window
			if fx.duration_t > 0 and not bool(fx.params.get("on_expire", false)):
				dur = mini(fx.duration_t, window)
			SimStatus.apply(world, e, fx_idx, key, dur, z.owner_pid)
		if touched:
			hit.append(id)
			if clears_sup:
				SimDamage.clear_suppression(world, e)
			if clears_emp and e.combat != null and e.combat.emp_until > world.tick:
				e.combat.emp_until = world.tick
				if world.combat != null:
					world.combat.note_status(e.id)
	if hit.size() > SimZoneConsts.MAX_MEMBERS:
		hit.resize(SimZoneConsts.MAX_MEMBERS)
	z.members = hit
	z.n_members = hit.size()
	z.flags |= SimZoneConsts.ZF_LATCHED_DONE
	if not smoke_at.is_empty():
		_spawn_effect_zones(world, sys, z, d, smoke_at)
	return hit.size()


## SPAWN_ZONE effects (Broken Contact): one zone per matching unit position, at most 8.
static func _spawn_effect_zones(world: SimWorld, sys: SimZoneSystem, z: SimZone, d: DefZone, at: PackedInt32Array) -> void:
	for k: int in d.effects.size():
		var fx: DefEffect = d.effects[k]
		if fx.op != DefEnums.EffectOp.SPAWN_ZONE:
			continue
		var zi: int = int(fx.params.get("zone_idx", -1))
		if zi < 0:
			continue
		var n: int = 0
		for id: int in at:
			if n >= 8:
				break
			var e: SimEntity = world.by_id[id]
			if e == null or (e.flags & SimFlags.F_GONE) != 0 or not sys.selector_ok(world, e, fx.selector):
				continue
			var life: int = fx.duration_t if fx.duration_t > 0 else 0
			var rad: int = int(fx.params.get("radius_u", 3072))
			sys.create_zone(zi, z.owner_pid, e.x, e.y, 0, world.tick + life if life > 0 else 0, -1, rad, 0, 0, 0, z.power_idx, -1)
			n += 1
