class_name SimPowerFx
extends RefCounted
## Power and superweapon glue (abilities 5.13): interprets the data-encoded actions of a support power (`DefPower.actions`:
## zone, summon, strike, mark, global_effect) and of a superweapon (`DefSuperweapon.action_kind`) with the primitives of
## this domain. Economy's power framework (slots, prerequisites, cost, cooldown, target vision, warnings, the RNG draws)
## calls `validate` / `apply` at activation time; nothing here draws random numbers or keeps a scheduler of its own beyond
## the small deferred-action queue in SimZoneSystem.pend (delay_s of the delivery powers, the Horizon debris impacts).
##
##   apply(world, power_idx, pid, x, y, angle, aux) -> PW_OK / PW_ERR_*
##       (x, y) the target point; angle the binary angle of the target line (LINE targets) or the approach bearing of
##       summons; aux an integer drawn once by economy at activation (decoy scatter, shell scatter) - except for a
##       power with `params.target_structure_idx` (Rapid Turnaround), where aux is the chosen structure's entity id.
##   apply_superweapon(world, sw_idx, pid, x, y, angle, hub_x, hub_y, aux, owner_eid)
##
## Public primitives for callers that schedule themselves (economy's SK_* scheduler): SimPowerFx.create_zone,
## SimPowerFx.spawn_summon, SimPowerFx.apply_timed_effect, SimPowerFx.strike_packet.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const PO_ZONE: int = 1  ## deferred zone action: a = action idx, b = body eid (-1), c = aux, d = angle
const PO_DEBRIS: int = 2  ## Horizon debris disc: a = zone idx, b = until tick, c = radius, d = angle
const SHELL_ORIGIN_U: int = 48 * 1024  ## off-map launch distance of artillery shells (they cross Trident's dome)
const ORBIT_DEFAULT_U: int = 4096
const APPROACH_U: int = 8 * 1024


# ---- public primitives ---------------------------------------------------------------------------------------------

## Zone entry point of the power framework. (x, y) centre; until_tick 0 = the template duration; radius / length / width
## override the template when > 0. See SimZoneSystem.create_zone for every parameter. Returns the zone id or -1.
static func create_zone(world: SimWorld, zone_idx: int, pid: int, x: int, y: int, angle: int = 0, until_tick: int = 0, bind_eid: int = -1,
		radius: int = 0, length: int = 0, width: int = 0, warmup: int = 0, power_idx: int = -1, src_eid: int = -1, count: int = 1,
		scatter_u: int = 0, aux: int = 0) -> int:
	if world.zones == null:
		return -1
	return world.zones.create_zone(zone_idx, pid, x, y, angle, until_tick, bind_eid, radius, length, width, warmup, power_idx, src_eid, count, scatter_u, aux)


## Summon entry point: a temporary unit created for a power. Aircraft fly in and circle (x, y) at the def's orbit radius
## (SD_ORBITER); ground defs stand at (x, y) (SD_STATIC). life_ticks 0 = the def's lifetime. Returns the entity id or -1.
static func spawn_summon(world: SimWorld, def_idx: int, pid: int, x: int, y: int, life_ticks: int = 0, angle: int = 0, parent_eid: int = -1,
		src_idx: int = -1) -> int:
	if def_idx < 0 or def_idx >= world.data.units.size():
		return -1
	var u: DefUnit = world.data.units[def_idx]
	var flags: int = SimZoneConsts.SM_DEFAULT_POWER | SimZoneConsts.SM_SHOOTABLE | SimZoneConsts.SM_UNCONTROLLABLE | SimZoneConsts.SM_NO_CMD_FIELD
	var id: int = -1
	if u.home_layer == SimEntity.Layer.AIR:
		var r: int = _orbit_radius(u)
		var sx: int = x + Fp.mul_q16(r + APPROACH_U, Fp.cos(angle))
		var sy: int = y + Fp.mul_q16(r + APPROACH_U, Fp.sin(angle))
		id = SimSummons.spawn(world, def_idx, pid, sx, sy, parent_eid, flags, life_ticks, SimZoneConsts.SD_ORBITER, x, y, r)
	else:
		id = SimSummons.spawn(world, def_idx, pid, x, y, parent_eid, flags, life_ticks, SimZoneConsts.SD_STATIC, x, y, 0)
	if id > 0:
		world.by_id[id].summon.src_idx = src_idx
		world.by_id[id].summon.src_pid = pid
	return id


static func _orbit_radius(u: DefUnit) -> int:
	var da: DefAbility = u.ability_of(DefEnums.AbilityKind.SUMMON_ORBIT)
	if da != null:
		var r: int = int(da.params.get("orbit_radius_u", 0))
		if r > 0:
			return r
	return ORBIT_DEFAULT_U


## Timed effect entry point (economy ask 17): effect fx_idx (SimEffectTable index) on entity target_id for dur_ticks (0 = the
## effect's own duration) under src_key (a power index below 2^24, or a complete FXK). true when stored.
static func apply_timed_effect(world: SimWorld, target_id: int, fx_idx: int, dur_ticks: int, src_pid: int, src_key: int) -> bool:
	return SimStatus.apply(world, world.get_entity(target_id), fx_idx, src_key, dur_ticks, src_pid)


# ---- validation ----------------------------------------------------------------------------------------------------

## Ability-side limits only (zone table space); vision and terrain rules stay in economy's can_activate.
static func validate(world: SimWorld, power_idx: int, pid: int, _x: int, _y: int) -> int:
	if power_idx < 0 or power_idx >= world.data.powers.size():
		return SimZoneConsts.PW_ERR_UNKNOWN
	if pid < 0 or pid >= world.players.size() or world.zones == null:
		return SimZoneConsts.PW_ERR_OWNER
	var p: DefPower = world.data.powers[power_idx]
	var need: int = 0
	for a: DefPowerAction in p.actions:
		if a.op == DefEnums.PowerOp.ZONE:
			need += 1
		elif a.op == DefEnums.PowerOp.SUMMON and _summon_def(world, a) < 0:
			return SimZoneConsts.PW_ERR_NO_SUMMON
	if world.zones.zone_count() + need > SimZoneConsts.MAX_ZONES:
		return SimZoneConsts.PW_ERR_LIMIT
	return SimZoneConsts.PW_OK


## Validates the chosen structure of a power with a structure target (Rapid Turnaround): own, of a listed kind, powered.
static func validate_target(world: SimWorld, power_idx: int, pid: int, target_eid: int) -> int:
	var base: int = validate(world, power_idx, pid, 0, 0)
	if base != SimZoneConsts.PW_OK:
		return base
	var p: DefPower = world.data.powers[power_idx]
	if not p.params.has("target_structure_idx"):
		return SimZoneConsts.PW_OK
	var t: SimEntity = world.get_entity(target_eid)
	if t == null or t.kind != SimEntity.Kind.STRUCTURE or t.owner != pid or (t.flags & SimFlags.F_GONE) != 0:
		return SimZoneConsts.PW_ERR_TARGET
	if not (p.params["target_structure_idx"] as PackedInt32Array).has(t.def_idx):
		return SimZoneConsts.PW_ERR_TARGET
	if bool(p.params.get("target_powered_required", false)) and (t.flags & SimFlags.F_POWERED) == 0:
		return SimZoneConsts.PW_ERR_TARGET
	return SimZoneConsts.PW_OK


## true when the power's own zone opens with a warm-up (Wideband Scan): economy activates it at once instead of
## scheduling a warning.
static func self_warned(world: SimWorld, power_idx: int) -> bool:
	var p: DefPower = world.data.powers[power_idx]
	if p.warning_t <= 0:
		return false
	for a: DefPowerAction in p.actions:
		if a.op == DefEnums.PowerOp.ZONE and a.zone >= 0 and world.data.zones[a.zone].zone_kind == DefEnums.ZoneKind.REVEAL:
			return true
	return false


# ---- support powers ------------------------------------------------------------------------------------------------

## Executes every action of the power in order. Returns PW_OK or PW_ERR_*.
## `strike_shift`: ticks added to the delay of every strike / mark shell (the warning of Tremor Barrage, Counterbattery Mission and
## Counterlaunch Plot: marks and frozen positions are taken now, the shells leave when the warning ends).
static func apply(world: SimWorld, power_idx: int, pid: int, x: int, y: int, angle: int, aux: int, strike_shift: int = 0) -> int:
	var v: int = validate(world, power_idx, pid, x, y)
	if v != SimZoneConsts.PW_OK:
		return v
	var p: DefPower = world.data.powers[power_idx]
	if p.params.has("target_structure_idx"):
		var tv: int = validate_target(world, power_idx, pid, aux)
		if tv != SimZoneConsts.PW_OK:
			return tv
	var body: int = -1
	var fx_base: int = 0
	for ai: int in p.actions.size():
		var a: DefPowerAction = p.actions[ai]
		match a.op:
			DefEnums.PowerOp.SUMMON:
				body = _act_summon(world, p, a, pid, x, y, angle)
			DefEnums.PowerOp.ZONE:
				var delay: int = int(a.params.get("delay_t", 0))
				if delay > 0:
					_defer_zone(world, power_idx, ai, pid, x, y, angle, aux, body, delay)
				else:
					_act_zone(world, power_idx, ai, pid, x, y, angle, aux, body)
			DefEnums.PowerOp.STRIKE:
				_act_strike(world, power_idx, a, pid, x, y, aux, strike_shift)
			DefEnums.PowerOp.MARK:
				_act_mark(world, power_idx, a, pid, x, y, strike_shift)
			DefEnums.PowerOp.GLOBAL_EFFECT:
				_act_global(world, power_idx, a, fx_base, pid, aux)
		fx_base += a.effects.size()
	return SimZoneConsts.PW_OK


## Unit def of a summon action. Survey Drone (NEC) and Recon Balloon (SAP) name summon defs that no unit sheet defines yet
## (data request); until then the shared recon aircraft `summon.napc.uav` stands in, so the power still reveals its area.
static func _summon_def(world: SimWorld, a: DefPowerAction) -> int:
	if a.summon >= 0:
		return a.summon
	return world.data.unit_idx("summon.napc.uav")


static func _act_summon(world: SimWorld, p: DefPower, a: DefPowerAction, pid: int, x: int, y: int, angle: int) -> int:
	var def_idx: int = _summon_def(world, a)
	if def_idx < 0:
		return -1
	var last: int = -1
	for k: int in maxi(a.count, 1):
		var id: int = spawn_summon(world, def_idx, pid, x, y, a.duration_t, angle + k * 1365, -1, p.index)
		if id > 0:
			last = id
	return last


static func _act_zone(world: SimWorld, power_idx: int, ai: int, pid: int, x: int, y: int, angle: int, aux: int, body: int) -> int:
	var p: DefPower = world.data.powers[power_idx]
	var a: DefPowerAction = p.actions[ai]
	if a.zone < 0:
		return -1
	if bool(a.params.get("fizzle_if_summon_lost", false)):
		var b: SimEntity = world.get_entity(body) if body > 0 else null
		if b == null or (b.flags & SimFlags.F_GONE) != 0:
			return -1
	var d: DefZone = world.data.zones[a.zone]
	var until: int = world.tick + a.duration_t if a.duration_t > 0 else 0
	var length: int = int(a.params.get("length_u", 0))
	var width: int = int(a.params.get("width_u", 0))
	var warmup: int = 0
	if d.zone_kind == DefEnums.ZoneKind.REVEAL and p.warning_t > 0 and self_warned(world, power_idx):
		warmup = p.warning_t
	var bind: int = body if (d.follow_source and body > 0) else -1
	var count: int = maxi(a.count, 1)
	var scatter: int = int(a.params.get("cluster_radius_u", 4096 if count > 1 else 0))
	return world.zones.create_zone(a.zone, pid, x, y, angle, until, bind, a.radius, length, width, warmup, power_idx, body, count, scatter, aux)


static func _defer_zone(world: SimWorld, power_idx: int, ai: int, pid: int, x: int, y: int, angle: int, aux: int, body: int, delay: int) -> void:
	_pend_add(world.zones, world.tick + delay, PO_ZONE, power_idx, pid, x, y, ai, body, aux, angle)


static func _pend_add(sys: SimZoneSystem, due: int, op: int, src: int, pid: int, x: int, y: int, a: int, b: int, c: int, d: int) -> void:
	var st: int = SimZoneSystem.PEND_STRIDE
	var n: int = sys.pend.size() / st
	var at: int = n
	while at > 0 and sys.pend[(at - 1) * st] > due:
		at -= 1
	var rec: PackedInt32Array = PackedInt32Array([due, op, src, pid, x, y, a, b, c, d])
	for i: int in st:
		sys.pend.insert(at * st + i, rec[i])


## Runs the deferred actions that came due (SimZoneSystem.update).
static func process_pending(world: SimWorld, sys: SimZoneSystem) -> void:
	var st: int = SimZoneSystem.PEND_STRIDE
	while sys.pend.size() >= st and sys.pend[0] <= world.tick:
		var r: PackedInt32Array = sys.pend.slice(0, st)
		sys.pend = sys.pend.slice(st)
		match r[1]:
			PO_ZONE:
				_act_zone(world, r[2], r[6], r[3], r[4], r[5], r[9], r[8], r[7])
			PO_DEBRIS:
				if r[3] >= 0 and r[3] < world.players.size():
					sys.create_zone(r[6], r[3], r[4], r[5], r[9], r[7], -1, r[8], 0, 0, 0, r[2], -1, 1, 0, 0, DefEnums.ZoneShape.CIRCLE)


# ---- strikes ---------------------------------------------------------------------------------------------------------

## Index of the warhead of `packet` in the owner's combat table (built on first use; `shell` = an ordinary interceptable
## shell rather than a strategic packet). The result is cached per (pid, source, packet).
static func warhead_for(world: SimWorld, pid: int, cache_key: String, packet: DefImpactPacket, sw: DefSuperweapon, shell: bool) -> int:
	var sys: SimZoneSystem = world.zones
	var key: String = "%d|%s|%d" % [pid, cache_key, 1 if shell else 0]
	if sys.wh_cache.has(key):
		return int(sys.wh_cache[key])
	var w: SimCombatWarhead = SimCombatWarhead.from_packet(packet, sw, world.data.damage.nonlethal_mask, cache_key)
	if shell:
		w.packet = 0
	var idx: int = world.combat.tables_of(pid).add_warhead(w)
	sys.wh_cache[key] = idx
	return idx


## One impact of a packet at (tx, ty) after `delay` ticks. Strategic packets detonate in place (PK_STRIKE); shells arc in from
## off the map so that Trident sees them cross its dome. Returns the projectile serial or -1.
static func strike_packet(world: SimWorld, pid: int, owner_eid: int, wh_idx: int, tx: int, ty: int, delay: int, shell: bool) -> int:
	if world.combat == null:
		return -1
	if shell:
		var ox: int = maxi(tx - SHELL_ORIGIN_U, 0)
		return world.combat.proj.spawn_remote(world, pid, owner_eid, SimCombatConsts.PK_ARC, wh_idx, ox, ty, tx, ty, delay, 10000, 0)
	return world.combat.proj.spawn_remote(world, pid, owner_eid, SimCombatConsts.PK_STRIKE, wh_idx, tx, ty, tx, ty, delay, 10000, 0)


static func _scatter(aux: int, k: int, radius: int) -> int:
	var h: int = Checksum.mix(Checksum.mix(Checksum.FNV_OFFSET, aux), k) & 0x7FFFFFFF
	var ang: int = h & 4095
	var rr: int = (((h >> 12) & 0xFFFF) * radius) >> 16
	return (rr << 12) | ang  # packed: high bits radius, low 12 bits angle


static func _act_strike(world: SimWorld, power_idx: int, a: DefPowerAction, pid: int, x: int, y: int, aux: int, shift: int = 0) -> void:
	if a.impacts.is_empty() or world.combat == null:
		return
	var wh: int = warhead_for(world, pid, "power:%d" % power_idx, a.impacts[0], null, true)
	var waves: int = maxi(int(a.params.get("waves_n", 1)), 1)
	var total: int = maxi(a.count, 1) * waves
	for k: int in total:
		var delay: int = shift + DefLoaderEffects.strike_delay(a.duration_t, total, k)
		var sc: int = _scatter(aux, k, a.radius)
		var ang: int = sc & 4095
		var rr: int = sc >> 12
		strike_packet(world, pid, 0, wh, x + Fp.mul_q16(rr, Fp.cos(ang)), y + Fp.mul_q16(rr, Fp.sin(ang)), delay, true)


# ---- marks -----------------------------------------------------------------------------------------------------------

## Counterbattery Solution / Counterlaunch Plot: enemy entities of the find selector inside the radius that fired within
## the lookback are marked (damage bonus lease for the caster's team, ground weapons), optionally revealed, and their
## positions frozen for the follow-up strike.
static func _act_mark(world: SimWorld, power_idx: int, a: DefPowerAction, pid: int, x: int, y: int, shift: int = 0) -> void:
	var sel: int = int(a.params.get("find_selector_idx", -1))
	var lookback: int = int(a.params.get("lookback_t", 0))
	var found: PackedInt32Array = PackedInt32Array()
	var ids: PackedInt32Array = PackedInt32Array()
	world.query_circle(x, y, a.radius, ids, SimTag.ALIVE, world.non_enemy_mask(pid) | SimTag.kind_bit(SimEntity.Kind.WRECK))
	var cap: int = int(a.params.get("max_marks_n", 8))
	for id: int in ids:
		var t: SimEntity = world.by_id[id]
		if t == null or t.kind != SimEntity.Kind.UNIT or t.combat == null or (t.flags & SimFlags.F_GONE) != 0:
			continue
		if not world.zones.selector_ok(world, t, sel):
			continue
		if t.combat.last_fire_tick < world.tick - lookback or t.combat.last_fire_tick == SimCombatConsts.NEVER:
			continue
		found.append(id)
		if found.size() >= cap:
			break
	var bonus: int = int(a.params.get("damage_bonus_bp", 0))
	var team: int = world.team_of(pid)
	var key: int = K.fxk(K.SRC_POWER, power_idx)
	for id2: int in found:
		var t2: SimEntity = world.by_id[id2]
		if bonus != 0 and a.duration_t > 0:
			SimCombatMods.apply(world, t2, key, SimCombatConsts.STAT_MARK, bonus, SimCombatMods.mark_filter(team, true), a.duration_t)
			world.emit(K.EV_MARKED, t2.x, t2.y, t2.id, 1)
		if bool(a.params.get("reveal", false)) and a.duration_t > 0:
			SimVision.add_reveal_entity(world, 1 << (team & 15), id2, world.tick + a.duration_t)
	if a.impacts.is_empty() or not a.params.has("strike_pattern") or world.combat == null:
		return
	var wh: int = warhead_for(world, pid, "power:%d" % power_idx, a.impacts[0], null, true)
	var gap: int = int(a.params.get("shell_gap_t", 12))
	for id3: int in found:  # positions are frozen now: the marked entity may move before the shells land
		var t3: SimEntity = world.by_id[id3]
		for j: int in maxi(a.count, 1):
			strike_packet(world, pid, 0, wh, t3.x, t3.y, shift + j * gap, true)


# ---- global effects (windows) ----------------------------------------------------------------------------------------

static func _act_global(world: SimWorld, power_idx: int, a: DefPowerAction, fx_base: int, pid: int, aux: int) -> void:
	var tbl: SimEffectTable = world.abilities.fx_table
	var until: int = world.tick + a.duration_t
	var src: int = K.fxk(K.SRC_POWER, power_idx)
	var chosen: bool = str(a.params.get("scope", "")) == "chosen_target"
	var pfx: SimPlayerFx = world.players[pid].fx
	var touched: int = 0
	for k: int in a.effects.size():
		var fx: DefEffect = a.effects[k]
		var fx_idx: int = tbl.power_effect(power_idx, fx_base + k)
		if fx_idx < 0 or tbl.effects[fx_idx] != fx:
			fx_idx = tbl.index_of(fx)
		if fx_idx < 0:
			continue
		match fx.op:
			DefEnums.EffectOp.PARAM_MOD:
				_global_param(world, fx, pid, until)
				if pfx != null:
					pfx.add(fx_idx, until, src, -1)
			DefEnums.EffectOp.STAT_MOD:
				if fx.stat == DefEnums.Stat.PROD_RATE:
					_global_prod_rate(world, fx, pid, until)
					if pfx != null:
						pfx.add(fx_idx, until, src, -1)
				elif chosen:
					if SimStatus.apply(world, world.get_entity(aux), fx_idx, src, a.duration_t, pid):
						touched += 1
				else:
					touched += _apply_to_units(world, fx, fx_idx, src, pid, a.duration_t)
					if pfx != null:
						pfx.add(fx_idx, until, src, -1)
			_:
				if pfx != null:
					pfx.add(fx_idx, until, src, -1)  # Joint Landing (resist_mod behind a disembark condition): applied by the unload hook
	world.emit(K.EV_BUFF_APPLIED, 0, 0, -1, power_idx, touched, pid)


## PARAM_MOD windows of a player: command / relay field windows (aura), salvage time (economy knob).
static func _global_param(world: SimWorld, fx: DefEffect, pid: int, until: int) -> void:
	if fx.scope == DefEnums.ParamScope.ABILITY and (fx.ability_kind == DefEnums.AbilityKind.COMMAND_FIELD or fx.ability_kind == DefEnums.AbilityKind.RELAY_FIELD):
		var g: int = SimAuraSystem.G_CMD if fx.ability_kind == DefEnums.AbilityKind.COMMAND_FIELD else SimAuraSystem.G_RELAY
		var aura: SimAuraSystem = world.abilities.aura
		var i: int = pid * SimAuraSystem.G_COUNT + g
		var bp: int = aura.win_bp[i] if aura.win_until[i] > world.tick else 0
		var rad: int = aura.win_rad[i] if aura.win_until[i] > world.tick else 0
		var end: int = maxi(until, aura.win_until[i]) if aura.win_until[i] > world.tick else until
		if fx.key == "damage_bonus_bp":
			bp = fx.value
		elif fx.key == "radius_u":
			rad = fx.value
		aura.set_window(pid, g, bp, rad, end)
	elif fx.scope == DefEnums.ParamScope.ABILITY and fx.ability_kind == DefEnums.AbilityKind.SALVAGE and fx.key == "action_t":
		if world.economy != null:
			world.economy.set_knob_temp(pid, SimEconConst.K_SALVAGE_TICKS, fx.value, until)


static func _global_prod_rate(world: SimWorld, fx: DefEffect, pid: int, until: int) -> void:
	if world.economy == null or fx.selector < 0:
		return
	var structs: PackedInt32Array = world.players[pid].roster.selector_structures(fx.selector)
	for si: int in structs:
		var id: String = world.data.structures[si].id
		var k: int = -1
		if id == "structure.shared.barracks":
			k = SimEconConst.K_PROD_RATE_BARRACKS_BP
		elif id == "structure.shared.factory":
			k = SimEconConst.K_PROD_RATE_FACTORY_BP
		if k >= 0:
			world.economy.set_knob_temp(pid, k, 10000 + fx.delta_bp, until)


## A unit-effect global window: every matching unit of the player gains it now (and new units at spawn, see on_unit_spawn).
static func _apply_to_units(world: SimWorld, fx: DefEffect, fx_idx: int, src: int, pid: int, dur: int) -> int:
	var n: int = 0
	for id: int in world.own_ids(pid):
		var e: SimEntity = world.by_id[id]
		if e == null or (e.flags & SimFlags.F_GONE) != 0 or not world.zones.selector_ok(world, e, fx.selector):
			continue
		if SimStatus.apply(world, e, fx_idx, src, dur, pid):
			n += 1
	return n


## Units created inside a running window receive its unit effects (Recovery Priority: also for units spawned during it).
static func on_unit_spawn(world: SimWorld, e: SimEntity) -> void:
	if e.owner < 0 or e.owner >= world.players.size() or e.stats == null:
		return
	var pfx: SimPlayerFx = world.players[e.owner].fx
	if pfx == null or pfx.n_active == 0:
		return
	var tbl: SimEffectTable = world.abilities.fx_table
	for i: int in SimPlayerFx.MAX_ACTIVE:
		var b: int = i * SimPlayerFx.STRIDE
		var idx: int = pfx.active[b + SimPlayerFx.E_FX]
		if idx < 0 or pfx.active[b + SimPlayerFx.E_UNTIL] <= world.tick:
			continue
		var fx: DefEffect = tbl.effects[idx]
		if fx.op != DefEnums.EffectOp.STAT_MOD or fx.stat == DefEnums.Stat.PROD_RATE or pfx.active[b + SimPlayerFx.E_TARGET] >= 0:
			continue
		if world.zones.selector_ok(world, e, fx.selector):
			SimStatus.apply(world, e, idx, pfx.active[b + SimPlayerFx.E_SRC], pfx.active[b + SimPlayerFx.E_UNTIL] - world.tick, e.owner)


## Unload hook (5.6.6): a unit that disembarks inside a Joint Landing window gets the window's effects for their `within`
## time; a second unload inside it changes nothing.
static func on_disembark(world: SimWorld, p: SimEntity) -> void:
	if p.owner < 0 or p.owner >= world.players.size():
		return
	var pfx: SimPlayerFx = world.players[p.owner].fx
	if pfx == null or pfx.n_active == 0:
		return
	var tbl: SimEffectTable = world.abilities.fx_table
	for i: int in SimPlayerFx.MAX_ACTIVE:
		var b: int = i * SimPlayerFx.STRIDE
		var idx: int = pfx.active[b + SimPlayerFx.E_FX]
		if idx < 0 or pfx.active[b + SimPlayerFx.E_UNTIL] <= world.tick:
			continue
		var fx: DefEffect = tbl.effects[idx]
		var ci: int = fx.cond_codes.find(DefEnums.Cond.RECENTLY_DISEMBARKED)
		if ci < 0 or not world.zones.selector_ok(world, p, fx.selector):
			continue
		var src: int = pfx.active[b + SimPlayerFx.E_SRC]
		if SimStatus.has_from(p, idx, src):
			continue
		var within: int = int(fx.cond_params[ci].get("within_t", 120))
		SimStatus.apply(world, p, idx, src, within, p.owner)


# ---- superweapons ----------------------------------------------------------------------------------------------------

## Executes a superweapon activation. (x, y) target; angle the line direction (Helios, Horizon); (hub_x, hub_y) the launcher
## (Tempest drones start on a ring around it); aux an integer drawn once by economy (Dragonfall capsule base angle);
## owner_eid the launcher entity (projectile owner) or 0.
static func apply_superweapon(world: SimWorld, sw_idx: int, pid: int, x: int, y: int, angle: int, hub_x: int, hub_y: int, aux: int, owner_eid: int = 0) -> int:
	if sw_idx < 0 or sw_idx >= world.data.superweapons.size():
		return SimZoneConsts.PW_ERR_UNKNOWN
	if pid < 0 or pid >= world.players.size() or world.zones == null:
		return SimZoneConsts.PW_ERR_OWNER
	var w: DefSuperweapon = world.data.superweapons[sw_idx]
	var tag: String = "sw:%d" % sw_idx
	match w.action_kind:
		DefEnums.SwAction.KINETIC_VOLLEY, DefEnums.SwAction.BUNKER_BUSTER, DefEnums.SwAction.EMP_BURST:
			for pk: int in w.packets.size():
				var p: DefImpactPacket = w.packets[pk]
				var wh: int = warhead_for(world, pid, "%s:%d" % [tag, pk], p, w, false)
				strike_packet(world, pid, owner_eid, wh, x + Fp.rot_x(p.offset_x, 0, angle), y + Fp.rot_y(p.offset_x, 0, angle), p.delay_t, false)
		DefEnums.SwAction.RAIL_STRIKE:
			var deb_len: int = int(w.params.get("debris_duration_t", 400))
			for pk2: int in w.packets.size():
				var p2: DefImpactPacket = w.packets[pk2]
				var wh2: int = warhead_for(world, pid, "%s:%d" % [tag, pk2], p2, w, false)
				var px: int = x + Fp.rot_x(p2.offset_x, 0, angle)
				var py: int = y + Fp.rot_y(p2.offset_x, 0, angle)
				strike_packet(world, pid, owner_eid, wh2, px, py, p2.delay_t, false)
				if w.zone >= 0:
					var due: int = world.tick + p2.delay_t
					if p2.delay_t <= 0:
						world.zones.create_zone(w.zone, pid, px, py, angle, due + deb_len, -1, p2.radius, 0, 0, 0, sw_idx, -1, 1, 0, 0, DefEnums.ZoneShape.CIRCLE)
					else:
						_pend_add(world.zones, due, PO_DEBRIS, sw_idx, pid, px, py, w.zone, due + deb_len, p2.radius, angle)
		DefEnums.SwAction.BEAM_SWEEP:
			var half: int = int(w.params.get("line_len_u", 0)) / 2
			var ax: int = x - Fp.mul_q16(half, Fp.cos(angle))
			var ay: int = y - Fp.mul_q16(half, Fp.sin(angle))
			var bx: int = x + Fp.mul_q16(half, Fp.cos(angle))
			var by: int = y + Fp.mul_q16(half, Fp.sin(angle))
			var every: int = int(w.params.get("hit_every_t", 5))
			var pulse: DefImpactPacket = w.packets[0]
			if bool(pulse.params.get("per_second", false)):
				# FIX (EC3B): the packet holds damage PER SECOND (dps); each pulse deals its share, so a centreline unit
				# takes about dps x dwell instead of dps x number of pulses
				pulse = pulse.copy_resolved()
				pulse.damage = pulse.damage * every / SimConfig.TPS
			var wh3: int = warhead_for(world, pid, "%s:0" % tag, pulse, w, false)
			if world.combat != null:
				world.combat.proj.spawn_sweep(world, pid, owner_eid, SimCombatConsts.PK_SWEEP, wh3, ax, ay, bx, by, 0, int(w.params.get("traverse_t", 240)),
					int(w.params.get("width_u", 3072)), 3072, every)
		DefEnums.SwAction.DRONE_SWARM:
			_swarm(world, w, sw_idx, pid, x, y, hub_x, hub_y)
		DefEnums.SwAction.ENGINE_DROP:
			_dragonfall(world, w, sw_idx, pid, x, y, aux)
		DefEnums.SwAction.INTERCEPT_ZONE:
			var rad: int = w.radius
			var until: int = world.tick + w.duration_t
			var zid: int = world.zones.create_zone(w.zone, pid, x, y, angle, until, -1, rad, 0, 0, 0, sw_idx, owner_eid)
			if zid < 0:
				return SimZoneConsts.PW_ERR_LIMIT
			var z: SimZone = world.zones.get_zone(zid)
			z.charges = int(w.params.get("charges_n", z.charges))
	return SimZoneConsts.PW_OK


## Tempest: 24 drones on a ring of 1.5 cells around the hub at angle index k * 170, flying to the area.
static func _swarm(world: SimWorld, w: DefSuperweapon, sw_idx: int, pid: int, tx: int, ty: int, hub_x: int, hub_y: int) -> void:
	if w.summon < 0:
		return
	var group: int = world.tick + 1
	for k: int in w.summon_count:
		var ang: int = (k * 170) & 4095
		SimSummons.spawn_swarm_drone(world, w.summon, pid, hub_x + Fp.mul_q16(1536, Fp.cos(ang)), hub_y + Fp.mul_q16(1536, Fp.sin(ang)), tx, ty, w.radius, group, sw_idx)
	world.emit(SimZoneConsts.EV_SWARM_LAUNCHED, hub_x, hub_y, -1, tx, ty)


## Dragonfall: three capsules at radius min(2.5 cells, area radius), angles base + k * 1365; each becomes an engine after
## the unfold time.
static func _dragonfall(world: SimWorld, w: DefSuperweapon, sw_idx: int, pid: int, tx: int, ty: int, base: int) -> void:
	if w.summon < 0:
		return
	var cap_idx: int = int(w.params.get("capsule_summon_idx", -1))
	if cap_idx < 0:
		return
	var unfold: int = int(w.params.get("unfold_t", 100))
	var r: int = mini(2560, w.radius) if w.radius > 0 else 2560
	var group: int = world.tick + 1
	for k: int in w.summon_count:
		var ang: int = (base + k * 1365) & 4095
		SimSummons.spawn_capsule(world, cap_idx, w.summon, pid, tx + Fp.mul_q16(r, Fp.cos(ang)), ty + Fp.mul_q16(r, Fp.sin(ang)), tx, ty, w.radius, unfold, group, sw_idx)
