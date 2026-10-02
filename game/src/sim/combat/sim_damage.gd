class_name SimDamage
extends RefCounted
## The damage pipeline (combat 5.6 / 5.8 / 5.9): `compute` (pure, ordered, Q8 half-up arithmetic), `deal` (compute +
## enqueue), `flush` (the only place where queued damage reaches `hp`), EMP status, suppression, attack alerts and
## the coalesced `EV_HIT`. The queue lives on SimCombatSystem (`dmg_queue`, stride 10, empty between ticks).

const STRIDE: int = 10
const Q_VICTIM: int = 0
const Q_DMG: int = 1
const Q_DTYPE: int = 2
const Q_DC: int = 3
const Q_FLAGS: int = 4  ## DF_* | HITF_* << 8 (hit-event flags derived at compute time)
const Q_ATK: int = 5
const Q_ATK_PID: int = 6
const Q_IX: int = 7
const Q_IY: int = 8
const Q_AUX: int = 9  ## EMP base ticks (class-resolved, 0 = none)


## half-up x * bp / 10000 for x >= 0, bp >= 0 (DR-5).
static func mul(x: int, bp: int) -> int:
	return (x * bp + 5000) / 10000


## Final integer damage of one instance (combat 5.6). `base` = warhead damage (beams: ramped); `static_bp` =
## static attacker layer product (10000 when the weapon's slot values are already resolved); `tmp_bp` = summed
## temporary attacker leases; `atk_team` (-1 none) / `atk_ground` feed the victim's STAT_MARK leases;
## `falloff_bp` 10000 for direct hits; `from_bat` = bearing from the victim toward the attack origin; `pkt_bp` =
## Trident packet reduction (0 / 5000). Returns 0 when the matrix is 0 (immune).
static func compute(world: SimWorld, v: SimEntity, wh: SimCombatWarhead, base: int, dc: int, static_bp: int, tmp_bp: int,
		atk_team: int, atk_ground: bool, falloff_bp: int, from_bat: int, pkt_bp: int) -> int:
	var cs: SimCombatSystem = world.combat
	var cd: SimCombatDef = cs.def_for(world, v)
	var m: int = cs.matrix(wh.dtype, cd.armor if cd != null else 0)
	if m == 0:
		return 0
	var cc: SimCompCombat = v.combat
	var x: int = mul(base << 8, m)
	x = mul(x, static_bp)
	var mark: int = SimCombatMods.mark_bp(cc, world.tick, atk_team, atk_ground) if cc != null else 0
	x = mul(x, clampi(10000 + tmp_bp + mark, 0, 40000))
	x = mul(x, falloff_bp)
	x = mul(x, taken_bp(world, v, cd, wh.dtype, dc, from_bat, pkt_bp))
	var dmg: int = (x + 128) >> 8
	if dmg < 1 and m >= SimCombatConsts.CHIP_FLOOR_BP and x > 0:
		dmg = 1
	return dmg


## Defender multiplier in bp (5.6.1): rows add within a layer, layer factors multiply, result clamped to
## [TAKEN_MIN_BP, TAKEN_MAX_BP]. Sets `world.combat.scratch_hitf` to the HITF_CAP / HITF_DIRECTIONAL / HITF_PACKET bits.
static func taken_bp(world: SimWorld, v: SimEntity, cd: SimCombatDef, dtype: int, dc: int, from_bat: int, pkt_bp: int) -> int:
	var cs: SimCombatSystem = world.combat
	var l0: int = 0
	var l1: int = 0
	var l2: int = 0
	var l3: int = pkt_bp
	var hitf: int = SimCombatConsts.HITF_PACKET if pkt_bp > 0 else 0
	var tick: int = world.tick
	if cd != null:
		var rr: PackedInt32Array = cd.resist_rows
		for i: int in rr.size() / 4:
			var b: int = i * 4
			if not SimCombatConsts.filter_match(rr[b], dtype, dc):
				continue
			if (rr[b + 3] & SimCombatConsts.COND_ON_WATER) != 0 and v.layer != SimCombatConsts.LAYER_SURFACE:
				continue
			match rr[b + 2]:
				0:
					l0 += rr[b + 1]
				1:
					l1 += rr[b + 1]
				2:
					l2 += rr[b + 1]
				_:
					l3 += rr[b + 1]
		if dtype != SimCombatConsts.DT_EMP:
			l1 += cd.static_resist[0]
			l2 += cd.static_resist[1]
		var dr: PackedInt32Array = cd.dir_rows
		for i: int in dr.size() / 5:
			var b2: int = i * 5
			if not SimCombatConsts.filter_match(dr[b2], dtype, dc):
				continue
			var rel: int = SimCombatConsts.wrap_signed(SimCombatConsts.wrap_signed(from_bat - v.facing) - dr[b2 + 1])
			if absi(rel) > dr[b2 + 2]:
				continue
			hitf |= SimCombatConsts.HITF_DIRECTIONAL
			match dr[b2 + 4]:
				0:
					l0 += dr[b2 + 3]
				1:
					l1 += dr[b2 + 3]
				2:
					l2 += dr[b2 + 3]
				_:
					l3 += dr[b2 + 3]
	l3 += cs.research_resist_bp(world, v, dtype)
	var cc: SimCompCombat = v.combat
	if cc != null:
		l3 += SimCombatMods.sum_bp(cc, SimCombatConsts.STAT_TAKEN, tick, dtype, dc)
	var taken: int = 10000
	taken = mul(taken, clampi(10000 - l0, 0, SimCombatConsts.TAKEN_MAX_BP))
	taken = mul(taken, clampi(10000 - l1, 0, SimCombatConsts.TAKEN_MAX_BP))
	taken = mul(taken, clampi(10000 - l2, 0, SimCombatConsts.TAKEN_MAX_BP))
	taken = mul(taken, clampi(10000 - l3, 0, SimCombatConsts.TAKEN_MAX_BP))
	if taken < SimCombatConsts.TAKEN_MIN_BP:
		hitf |= SimCombatConsts.HITF_CAP
	cs.scratch_hitf = hitf
	return clampi(taken, SimCombatConsts.TAKEN_MIN_BP, SimCombatConsts.TAKEN_MAX_BP)


## EMP class of a victim (EC_*), 0 for entities EMP never touches (wrecks, zones, neutrals).
static func emp_class(v: SimEntity, cd: SimCombatDef) -> int:
	if v.kind == SimEntity.Kind.STRUCTURE:
		return SimCombatConsts.EC_STRUCTURE
	if v.kind != SimEntity.Kind.UNIT:
		return 0
	var tags: int = cd.tags if cd != null else 0
	if v.layer == SimCombatConsts.LAYER_AIR or (cd != null and cd.is_aircraft == 1):
		return SimCombatConsts.EC_AIRCRAFT
	if (tags & (DefEnums.UT_SHIP | DefEnums.UT_SUBMARINE)) != 0:
		return SimCombatConsts.EC_SHIP
	if (tags & DefEnums.UT_INFANTRY) != 0:
		return SimCombatConsts.EC_INFANTRY
	return SimCombatConsts.EC_VEHICLE


## Class-resolved EMP base ticks of `wh` against `v` (0 = no status): class mask, structure susceptibility.
static func emp_base_ticks(v: SimEntity, cd: SimCombatDef, wh: SimCombatWarhead) -> int:
	if wh.emp_unit_ticks <= 0 and wh.emp_struct_ticks <= 0:
		return 0
	var ec: int = emp_class(v, cd)
	if (wh.emp_class_mask & ec) == 0:
		return 0
	if ec == SimCombatConsts.EC_STRUCTURE:
		return wh.emp_struct_ticks if (cd != null and cd.emp_susceptible == 1) else 0
	return wh.emp_unit_ticks


## compute + enqueue one damage instance. Returns the queued damage (0 and nothing queued when the matrix is 0 or the
## victim is gone). EMP durations, suppression and nonlethal ride on the instance.
static func deal(world: SimWorld, v: SimEntity, wh: SimCombatWarhead, base: int, dc: int, dflags: int, atk_id: int, atk_pid: int,
		atk_ground: bool, static_bp: int, tmp_bp: int, falloff_bp: int, from_bat: int, pkt_bp: int, ix: int, iy: int) -> int:
	if v == null or v.combat == null or (v.flags & SimFlags.F_GONE) != 0:
		return 0
	var cs: SimCombatSystem = world.combat
	var cd: SimCombatDef = cs.def_for(world, v)
	if cs.matrix(wh.dtype, cd.armor if cd != null else 0) == 0:
		return 0
	var dmg: int = compute(world, v, wh, base, dc, static_bp, tmp_bp, world.team_of(atk_pid), atk_ground, falloff_bp, from_bat, pkt_bp)
	var hitf: int = cs.scratch_hitf
	var f: int = dflags | (hitf << 8)
	if wh.nonlethal == 1 or wh.dtype == SimCombatConsts.DT_EMP:
		f |= SimCombatConsts.DF_NONLETHAL
	if wh.suppressive == 1:
		f |= SimCombatConsts.DF_SUPPRESSIVE
	if wh.packet == 1:
		f |= SimCombatConsts.DF_PACKET
	var q: PackedInt32Array = cs.dmg_queue
	q.append(v.id)
	q.append(dmg)
	q.append(wh.dtype)
	q.append(dc)
	q.append(f)
	q.append(atk_id)
	q.append(atk_pid)
	q.append(ix)
	q.append(iy)
	q.append(emp_base_ticks(v, cd, wh))
	cs.counters[SimCombatSystem.CNT_DAMAGE] += 1
	return dmg


## P6: applies the queued instances in queue order (5.6.2), emits one EV_HIT per touched victim, clears the queue.
static func flush(world: SimWorld) -> void:
	var cs: SimCombatSystem = world.combat
	var q: PackedInt32Array = cs.dmg_queue
	if q.is_empty():
		return
	var tick: int = world.tick
	var touched: PackedInt32Array = PackedInt32Array()
	for i: int in q.size() / STRIDE:
		var b: int = i * STRIDE
		var v: SimEntity = world.get_entity(q[b + Q_VICTIM])
		if v == null or v.combat == null or (v.flags & SimFlags.F_GONE) != 0:
			continue
		var cc: SimCompCombat = v.combat
		if v.hp_max <= 0 or ((cc.cflags & SimCombatConsts.CF_INVULNERABLE) != 0) or ((v.flags & SimFlags.F_INVULNERABLE) != 0):
			continue
		var dmg: int = q[b + Q_DMG]
		var dtype: int = q[b + Q_DTYPE]
		var dc: int = q[b + Q_DC]
		var qf: int = q[b + Q_FLAGS]
		var atk_id: int = q[b + Q_ATK]
		var atk_pid: int = q[b + Q_ATK_PID]
		var aux: int = q[b + Q_AUX]
		if (qf & SimCombatConsts.DF_NONLETHAL) != 0:
			dmg = mini(dmg, v.hp - 1)
		var applied: int = mini(dmg, v.hp)
		v.hp -= dmg
		cc.last_hit_tick = tick
		cc.last_attacker_id = atk_id
		cc.last_attacker_pid = atk_pid
		var atk: SimEntity = world.get_entity(atk_id) if atk_id > 0 else null
		if atk != null and atk.combat != null and (atk.flags & SimFlags.F_GONE) == 0:
			atk.combat.last_dealt_tick = tick
		var atk_team: int = world.team_of(atk_pid)
		if atk_team >= 0:
			cc.focus_mask |= 1 << (atk_team & 7)
			cc.focus_tick = tick
		_stats(world, v, atk_pid, applied)
		var hf: int = (qf >> 8) & 0xFF
		if aux > 0:
			apply_emp(world, v, aux, atk_pid)
			hf |= SimCombatConsts.HITF_EMP
		if (qf & SimCombatConsts.DF_SUPPRESSIVE) != 0 and (cc.cflags & SimCombatConsts.CF_SUPPRESSIBLE) != 0:
			if suppress_hit(world, v):
				hf |= SimCombatConsts.HITF_SUPPRESSION
		if dmg > 0 or aux > 0:
			_alert(world, v, atk_pid)
		if cc.hit_stamp != tick:
			cc.hit_stamp = tick
			cc.hit_dmg = 0
			cc.hit_flags = 0
			cc.hit_hp0 = v.hp + dmg
			touched.append(v.id)
		cc.hit_dmg += dmg
		cc.hit_atk = atk_id
		cc.hit_flags = (cc.hit_flags & ~0xFFFF) | dtype | (dc << 8)
		cc.hit_flags |= hf << 16
		if v.hp <= 0:
			cc.hit_flags |= SimCombatConsts.HITF_KILLED << 16
			cs.kill(world, v, SimCombatConsts.CAUSE_DAMAGE, atk_id, atk_pid)
	for id: int in touched:
		var t: SimEntity = world.get_entity(id)
		if t == null or t.combat == null:
			continue
		var c: SimCompCombat = t.combat
		world.emit(SimCombatConsts.EV_HIT, t.x, t.y, t.id, c.hit_dmg, c.hit_atk, c.hit_flags, t.hp, t.hp_max)
	cs.dmg_queue.clear()
	for id2: int in touched:
		var t2: SimEntity = world.get_entity(id2)
		if t2 != null and t2.combat != null and (t2.flags & SimFlags.F_GONE) == 0:
			SimTargeting.on_damaged(world, t2, t2.combat.hit_atk)


## EMP status (5.8): `base` = class-resolved base ticks. Immunity blocks it (EV_EMP blocked); recovery bonuses
## (static def param + STAT_EMP_RECOVER leases, clamped 0..5000 bp) shorten it; re-hits refresh, never stack.
## Returns the applied duration (0 when blocked).
static func apply_emp(world: SimWorld, v: SimEntity, base: int, atk_pid: int) -> int:
	var cc: SimCompCombat = v.combat
	var tick: int = world.tick
	var is_struct: int = 1 if v.kind == SimEntity.Kind.STRUCTURE else 0
	if SimCombatMods.has_flag(cc, SimCombatConsts.STAT_FLAG_EMP_IMMUNE, tick):
		world.emit(SimCombatConsts.EV_EMP, v.x, v.y, v.id, 0, is_struct, atk_pid, 1, 0)
		return 0
	var rec: int = clampi(world.combat.emp_recover_bp(world, v) + SimCombatMods.sum_bp(cc, SimCombatConsts.STAT_EMP_RECOVER, tick), 0, SimCombatConsts.EMP_RECOVER_MAX_BP)
	var dur: int = (base * (10000 - rec) + 9999) / 10000
	var was_off: bool = cc.emp_until > tick or cc.wlock_until > tick
	cc.emp_until = maxi(cc.emp_until, tick + dur)
	if is_struct == 1 and v.econ != null:
		v.econ.shutdown_until = maxi(v.econ.shutdown_until, tick + dur)  # FIX (EC3B): economy / production / superweapons read this
	v.flags |= SimFlags.F_EMP_SHUT | SimFlags.F_WEAPONS_OFF
	world.combat.note_status(v.id)
	world.emit(SimCombatConsts.EV_EMP, v.x, v.y, v.id, dur, is_struct, atk_pid, 0, 0)
	if is_struct == 0 and not was_off:
		world.emit(SimCombatConsts.EV_WEAPON_LOCK, v.x, v.y, v.id, 1, 0)
	return dur


## Suppression (5.9) for one applied suppressive instance on a CF_SUPPRESSIBLE victim; true when it just began.
static func suppress_hit(world: SimWorld, v: SimEntity) -> bool:
	var cc: SimCompCombat = v.combat
	var tick: int = world.tick
	if SimCombatMods.has_flag(cc, SimCombatConsts.STAT_FLAG_SUP_IMMUNE, tick):
		return false
	var tail: int = SimCombatConsts.SUP_TAIL * 256
	if cc.sup_left_q8 > 0:
		cc.sup_left_q8 = tail
		return false
	match cc.sup_i:
		0:
			cc.sup_t0 = tick
		1:
			cc.sup_t1 = tick
		_:
			cc.sup_t2 = tick
	cc.sup_i = (cc.sup_i + 1) % 3
	var oldest: int = cc.sup_t0 if cc.sup_i == 0 else (cc.sup_t1 if cc.sup_i == 1 else cc.sup_t2)
	if tick - oldest <= SimCombatConsts.SUP_WINDOW:
		cc.sup_left_q8 = tail
		v.flags |= SimFlags.F_SUPPRESSED
		world.combat.note_status(v.id)
		world.emit(SimCombatConsts.EV_SUPPRESS, v.x, v.y, v.id, 1)
		return true
	return false


## Zeroes suppression and its hit ring (Coordinated Advance).
static func clear_suppression(world: SimWorld, v: SimEntity) -> void:
	var cc: SimCompCombat = v.combat
	if cc == null:
		return
	if cc.sup_left_q8 > 0:
		world.emit(SimCombatConsts.EV_SUPPRESS, v.x, v.y, v.id, 0)
	cc.sup_left_q8 = 0
	cc.sup_t0 = SimCombatConsts.NEVER
	cc.sup_t1 = SimCombatConsts.NEVER
	cc.sup_t2 = SimCombatConsts.NEVER
	cc.sup_i = 0
	v.flags &= ~SimFlags.F_SUPPRESSED


static func _stats(world: SimWorld, v: SimEntity, atk_pid: int, dmg: int) -> void:
	if v.owner >= 0 and v.owner < world.players.size():
		world.players[v.owner].st_damage_taken += dmg
	if atk_pid >= 0 and atk_pid < world.players.size():
		world.players[atk_pid].st_damage_dealt += dmg


## EV_ATTACK_ALERT with the per-player cooldown / distance throttle (output only, not hashed).
static func _alert(world: SimWorld, v: SimEntity, atk_pid: int) -> void:
	var cs: SimCombatSystem = world.combat
	var pid: int = v.owner
	if pid < 0 or pid >= cs.alert_tick.size() or v.kind == SimEntity.Kind.WRECK:
		return
	if (v.flags & SimFlags.F_DECOY) != 0 or (v.combat.cflags & SimCombatConsts.CF_DECOY) != 0:
		return
	var rel: int = world.rel(pid, atk_pid)
	if rel == SimCombatConsts.REL_SELF or rel == SimCombatConsts.REL_ALLY:
		return
	var tick: int = world.tick
	var far: bool = Fp.dist(v.x - cs.alert_x[pid], v.y - cs.alert_y[pid]) >= SimCombatConsts.ALERT_DIST
	if tick - cs.alert_tick[pid] < SimCombatConsts.ALERT_COOLDOWN and not far:
		return
	cs.alert_tick[pid] = tick
	cs.alert_x[pid] = v.x
	cs.alert_y[pid] = v.y
	var cd: SimCombatDef = cs.def_for(world, v)
	var cls: int = 0
	if v.kind == SimEntity.Kind.STRUCTURE:
		cls = 1
	elif cd != null and (cd.tags & DefEnums.UT_COLLECTOR) != 0:
		cls = 2
	elif v.layer == SimCombatConsts.LAYER_AIR or (cd != null and cd.is_aircraft == 1):
		cls = 3
	world.emit(SimCombatConsts.EV_ATTACK_ALERT, v.x, v.y, pid, v.id, atk_pid, cls)
