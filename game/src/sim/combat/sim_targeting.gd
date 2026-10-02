class_name SimTargeting
extends RefCounted
## Target acquisition (combat 5.10): filters, scoring, budgeted scan scheduling, stances and leashes, target validation
## (hidden / out of leash / no longer engageable), retaliation and assist. Stateless statics; the only persistent state is
## the SimCompCombat fields (target_*, seen_*, scan_next, focus_*, last_assist_tick) and SimCombatSystem.scan_cursor.
## Vision comes from `world.fog` (default: everything visible, no decoy identified).

const VS_NONE: int = 0  ## no valid target
const VS_OK: int = 1  ## valid and visible
const VS_HIDDEN: int = 2  ## valid but currently hidden: hold fire, keep the target for the give-up window
const SCORE_NONE: int = -0x40000000


# ---------------------------------------------------------------------------------------------- filters (5.10.1)
static func filter_bit(t: SimEntity) -> int:
	match t.kind:
		SimEntity.Kind.STRUCTURE, SimEntity.Kind.NEUTRAL:
			return SimCombatConsts.TF_STRUCTURE
		SimEntity.Kind.WRECK:
			return SimCombatConsts.TF_WRECK
	return 1 << t.layer


## true when mount `m` belongs to the current mode (DefWeaponSlot.mode_mask; 0 = always).
static func mount_active(cc: SimCompCombat, cd: SimCombatDef, m: int) -> bool:
	var mm: int = cd.mount_val(m, SimCombatDef.MT_MODE_MASK)
	return mm == 0 or (cc.ext_mode >= 0 and ((mm >> cc.ext_mode) & 1) == 1)  # FIX (AB2): ext_mode -1 = switching, never shift by -1


## can_engage of combat 5.10.1 for one mount (class, relation, cargo / untargetable, decoy and wreck rules).
static func can_engage(world: SimWorld, e: SimEntity, cd: SimCombatDef, m: int, t: SimEntity, force: bool) -> bool:
	if t == null or t == e or (t.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or t.container_id >= 0:
		return false
	var tc: SimCompCombat = t.combat
	if tc == null or t.kind == SimEntity.Kind.ZONE or (tc.cflags & SimCombatConsts.CF_UNTARGETABLE) != 0:
		return false
	var bit: int = filter_bit(t)
	var tf: int = cd.pf(m, SimWeaponProfile.PF_TF)
	var class_ok: bool = (tf & bit) != 0
	if not class_ok and force and bit == SimCombatConsts.TF_WRECK and (tf & (SimCombatConsts.TF_GROUND | SimCombatConsts.TF_STRUCTURE)) != 0:
		class_ok = true
	if not class_ok:
		return false
	var rel: int = world.rel(e.owner, t.owner)
	var relation_ok: bool = force or rel == SimCombatConsts.REL_ENEMY
	if (e.combat.cflags & SimCombatConsts.CF_ENEMY_ONLY) != 0:
		relation_ok = rel == SimCombatConsts.REL_ENEMY
	if not relation_ok:
		return false
	if not force:
		if t.kind == SimEntity.Kind.WRECK or (t.flags & SimFlags.F_UNTARGETABLE) != 0:
			return false
		if (tc.cflags & SimCombatConsts.CF_DECOY) != 0 and world.fog.decoy_identified(e.owner, t):
			return false
	return true


## Any active mount that can engage `target` (UI cursor / command validation / AI).
static func can_attack(world: SimWorld, shooter: SimEntity, target: SimEntity, force: bool = false, any_mode: bool = true) -> bool:
	var cc: SimCompCombat = shooter.combat
	if cc == null or cc.n_mounts == 0:
		return false
	var cd: SimCombatDef = world.combat.def_for(world, shooter)
	if cd == null:
		return false
	for m: int in cd.n_mounts:
		if (any_mode or mount_active(cc, cd, m)) and can_engage(world, shooter, cd, m, target, force):
			return true
	return false


# ---------------------------------------------------------------------------------------------- fire control (3.4)
## Validates can_engage (force for TS_FORCE) and sets the target; false if refused.
static func set_target(world: SimWorld, e: SimEntity, target_id: int, src: int) -> bool:
	var cc: SimCompCombat = e.combat
	if cc == null or cc.n_mounts == 0 or (e.flags & SimFlags.F_GONE) != 0:
		return false
	var t: SimEntity = world.get_entity(target_id)
	if t == null or not can_attack(world, e, t, src == SimCombatConsts.TS_FORCE, src == SimCombatConsts.TS_ORDER or src == SimCombatConsts.TS_FORCE):
		return false
	var tick: int = world.tick
	if cc.target_id != target_id:
		cc.target_since = tick
	cc.target_id = target_id
	cc.target_src = src
	cc.ground_on = 0
	cc.seen_x = t.x
	cc.seen_y = t.y
	cc.seen_tick = tick
	stamp_focus(world, e, t)
	return true


static func set_ground_target(e: SimEntity, gx: int, gy: int) -> void:
	var cc: SimCompCombat = e.combat
	if cc == null:
		return
	cc.target_id = -1
	cc.target_src = SimCombatConsts.TS_FORCE
	cc.ground_on = 1
	cc.ground_x = gx
	cc.ground_y = gy


## Drops the target, the ground point and the salvo remainder (beams end in the next weapon phase). `keep_auto`
## leaves a TS_AUTO / TS_RETAL / TS_GUARD target alone.
static func clear_target(e: SimEntity, keep_auto: bool = false) -> void:
	var cc: SimCompCombat = e.combat
	if cc == null:
		return
	if keep_auto and cc.target_src != SimCombatConsts.TS_ORDER and cc.target_src != SimCombatConsts.TS_FORCE and cc.target_id >= 0:
		return
	cc.target_id = -1
	cc.target_src = SimCombatConsts.TS_NONE
	cc.ground_on = 0
	for m: int in cc.n_mounts:
		var b: int = m * SimCombatConsts.MS
		if cc.mnt[b + SimCombatConsts.M_BURST] > 0:  # the abandoned salvo still owes its cooldown
			cc.mnt[b + SimCombatConsts.M_CD] = maxi(cc.mnt[b + SimCombatConsts.M_CD], cc.mnt[b + SimCombatConsts.M_NEXT])
		cc.mnt[b + SimCombatConsts.M_BURST] = 0


static func stamp_focus(world: SimWorld, e: SimEntity, t: SimEntity) -> void:
	var team: int = world.team_of(e.owner)
	if team >= 0 and t.combat != null:
		t.combat.focus_mask |= 1 << (team & 7)
		t.combat.focus_tick = world.tick


# ---------------------------------------------------------------------------------------------- stances (5.10.4)
static func r_acq_of(e: SimEntity, cc: SimCompCombat, range_eff: int) -> int:
	if e.kind == SimEntity.Kind.STRUCTURE or cc.hold_pos == 1 or cc.stance == SimCombatConsts.ST_DEFENSIVE:
		return range_eff
	if cc.stance == SimCombatConsts.ST_GUARD:
		return maxi(range_eff + 2048, SimCombatConsts.GUARD_RADIUS)
	return range_eff + 2048


static func leash_of(e: SimEntity, cc: SimCompCombat) -> int:
	if cc.hold_pos == 1:
		return 0
	if e.kind == SimEntity.Kind.STRUCTURE:
		return 0x3FFFFFFF
	match cc.stance:
		SimCombatConsts.ST_DEFENSIVE:
			return SimCombatConsts.LEASH_DEFENSIVE
		SimCombatConsts.ST_GUARD:
			return SimCombatConsts.LEASH_GUARD
	return SimCombatConsts.LEASH_AGGRESSIVE


static func within_leash(e: SimEntity, cc: SimCompCombat, t: SimEntity, range_eff: int) -> bool:
	if cc.anchor_on == 0 or e.kind == SimEntity.Kind.STRUCTURE:
		return true
	var d: int = maxi(Fp.dist(t.x - cc.anchor_x, t.y - cc.anchor_y) - t.radius, 0)
	return d <= leash_of(e, cc) + range_eff


static func scan_interval(e: SimEntity, cd: SimCombatDef) -> int:
	if e.kind == SimEntity.Kind.STRUCTURE:
		return SimCombatConsts.SCAN_INTERVAL_STRUCT
	if cd != null and cd.is_aircraft == 1:
		return SimCombatConsts.SCAN_INTERVAL_AIR
	return SimCombatConsts.SCAN_INTERVAL_UNIT


# ---------------------------------------------------------------------------------------------- scoring (5.10.3)
static func score_target(world: SimWorld, e: SimEntity, cc: SimCompCombat, t: SimEntity, td: SimCombatDef,
		d_eff: int, r_acq: int, m_best: int) -> int:
	var tick: int = world.tick
	var tc: SimCompCombat = t.combat
	var sc: int = (td.prio if td != null else 0) * SimCombatConsts.PRIO_TIER
	if e.layer == SimCombatConsts.LAYER_AIR and (tc.cflags & SimCombatConsts.CF_HAS_AA) != 0:
		sc += 2 * SimCombatConsts.PRIO_TIER
	sc += clampi((m_best - 10000) * 2048 / 10000, -4096, 4096)
	if tc.target_id > 0:
		var tt: SimEntity = world.get_entity(tc.target_id)
		if tt != null:
			var r: int = world.rel(e.owner, tt.owner)
			if r == SimCombatConsts.REL_SELF or r == SimCombatConsts.REL_ALLY:
				sc += SimCombatConsts.THREAT_BONUS
	var team: int = world.team_of(e.owner)
	if team >= 0 and ((tc.focus_mask >> (team & 7)) & 1) == 1 and tick - tc.focus_tick <= SimCombatConsts.FOCUS_TTL:
		sc += SimCombatConsts.FOCUS_BONUS
	sc += SimCombatConsts.WOUNDED_MAX * (10000 - t.hp * 10000 / maxi(t.hp_max, 1)) / 10000
	sc -= d_eff * 1024 / maxi(1, r_acq)
	if t.id == cc.target_id:
		sc += SimCombatConsts.STICK_BONUS
	if t.hp - tc.inflight_est <= 0 and (cc.target_src != SimCombatConsts.TS_ORDER and cc.target_src != SimCombatConsts.TS_FORCE):
		sc -= SimCombatConsts.OVERKILL_PENALTY
	return sc


## Best matrix (bp) among the active non-independent mounts that can hit `t` (0 = none).
static func m_best_of(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cd: SimCombatDef, cc: SimCompCombat, t: SimEntity,
		td: SimCombatDef, indep_only: int = -1) -> int:
	var best: int = 0
	var armor: int = td.armor if td != null else 0
	for m: int in cd.n_mounts:
		if not mount_active(cc, cd, m):
			continue
		var ind: bool = cd.n_mounts > 1 and cd.mount_val(m, SimCombatDef.MT_INDEP) == 1
		if indep_only >= 0:
			if m != indep_only:
				continue
		elif ind:
			continue
		if not can_engage(world, e, cd, m, t, false):
			continue
		best = maxi(best, cs.matrix(cd.slots[cd.slot_of_mount(m)].dtype, armor))
	return best


## Score of `t` as an auto target of `e` right now (SCORE_NONE when it does not qualify).
static func rate(world: SimWorld, cs: SimCombatSystem, e: SimEntity, t: SimEntity) -> int:
	var cc: SimCompCombat = e.combat
	var cd: SimCombatDef = cs.def_for(world, e)
	if cc == null or cd == null or t.combat == null:
		return SCORE_NONE
	var td: SimCombatDef = cs.def_for(world, t)
	var mb: int = m_best_of(world, cs, e, cd, cc, t, td)
	if mb < SimWeaponProfile.AUTO_MIN_BP:
		return SCORE_NONE
	var rng: int = cs.range_max_eff(world, e)
	var r_acq: int = r_acq_of(e, cc, rng)
	var d: int = maxi(Fp.dist(t.x - e.x, t.y - e.y) - t.radius, 0)
	return score_target(world, e, cc, t, td, d, r_acq, mb)


# ---------------------------------------------------------------------------------------------- scans (5.10.2)
## P3: budgeted round-robin scans over armed_ids. Entities that stay due are reached by the rotation.
static func run_scans(world: SimWorld, cs: SimCombatSystem) -> void:
	var ids: PackedInt32Array = cs.armed_ids
	var n: int = ids.size()
	if n == 0:
		return
	var budget: int = SimCombatConsts.SCAN_BUDGET_BASE + 4 * (n / 64)
	var cur: int = cs.scan_cursor % n
	var tick: int = world.tick
	var done: int = 0
	var visited: int = 0
	while visited < n and done < budget:
		var e: SimEntity = world.get_entity(ids[cur])
		cur += 1
		if cur >= n:
			cur = 0
		visited += 1
		if e == null or e.combat == null or e.combat.scan_next > tick or not scannable(world, cs, e):
			continue
		scan(world, cs, e)
		done += 1
	cs.scan_cursor = cur


## Armed, alive, on the map, weapons online, not a parked aircraft.
static func scannable(world: SimWorld, cs: SimCombatSystem, e: SimEntity) -> bool:
	var cc: SimCompCombat = e.combat
	if cc.n_mounts == 0 or (e.flags & SimFlags.F_GONE) != 0 or ((e.flags & SimFlags.F_INSIDE) != 0 and (e.flags & SimFlags.F_GARRISONED) == 0) \
			or (cc.cflags & (SimCombatConsts.CF_DEAD | SimCombatConsts.CF_DYING)) != 0:
		return false  # FIX (AB2): garrisoned squads scan from the building
	if e.owner < 0 or cc.stance == SimCombatConsts.ST_HOLD_FIRE:
		return false
	if e.air != null and e.air.is_airfield == 0:
		var st: int = e.air.state
		if st == SimCombatConsts.AIR_PARKED or st == SimCombatConsts.AIR_REARM or st == SimCombatConsts.AIR_DOCKED or st == SimCombatConsts.AIR_LANDING or st == SimCombatConsts.AIR_TAKEOFF:
			return false
	return cs.weapons_online(world, e)


## One scan of `e`: candidates within R_acq that pass the cheap prefilter (<= SCAN_CAND_CAP, ascending id), highest
## score wins (ties -> lowest id). Independent mounts (AA / ASW / secondary guns) pick their own target in M_TARGET.
static func scan(world: SimWorld, cs: SimCombatSystem, e: SimEntity) -> void:
	var cc: SimCompCombat = e.combat
	var cd: SimCombatDef = cs.def_for(world, e)
	var tick: int = world.tick
	cs.counters[SimCombatSystem.CNT_SCANS] += 1
	cc.scan_next = tick + scan_interval(e, cd)
	if cd == null or cc.stance == SimCombatConsts.ST_HOLD_FIRE:
		return
	var n: int = cd.n_mounts
	var rng: PackedInt32Array = PackedInt32Array()
	rng.resize(n)
	var union_tf: int = 0
	var prim_range: int = -1
	var r_query: int = 0
	var ind_r: PackedInt32Array = PackedInt32Array()
	ind_r.resize(n)
	for m: int in n:
		rng[m] = -1
		if not mount_active(cc, cd, m):
			continue
		var r: int = cs.range_max_eff(world, e, m)
		rng[m] = r
		union_tf |= cd.pf(m, SimWeaponProfile.PF_TF)
		if n > 1 and cd.mount_val(m, SimCombatDef.MT_INDEP) == 1:
			ind_r[m] = r
			r_query = maxi(r_query, r)
		else:
			prim_range = maxi(prim_range, r)
	var primary_ok: bool = prim_range >= 0 and cc.ground_on == 0 and cc.target_src != SimCombatConsts.TS_ORDER and cc.target_src != SimCombatConsts.TS_FORCE
	var r_prim: int = r_acq_of(e, cc, maxi(prim_range, 0))
	if primary_ok:
		r_query = maxi(r_query, r_prim)
	var has_ind: bool = false
	for m: int in n:
		if ind_r[m] > 0:
			has_ind = true
	if not primary_ok and not has_ind:
		return
	var cx: int = e.x
	var cy: int = e.y
	if cc.stance == SimCombatConsts.ST_GUARD and cc.anchor_on == 1:
		cx = cc.anchor_x
		cy = cc.anchor_y
	var avoid: int = world.non_enemy_mask(e.owner) | SimTag.kind_bit(SimEntity.Kind.WRECK) | SimTag.kind_bit(SimEntity.Kind.ZONE) | SimTag.kind_bit(SimEntity.Kind.NEUTRAL)
	var buf: PackedInt32Array = cs.scan_buf
	world.query_circle(cx, cy, r_query + SimCombatConsts.SPLASH_QUERY_MARGIN, buf, SimTag.ALIVE, avoid)
	var best_id: int = -1
	var best_sc: int = SCORE_NONE
	var ind_id: PackedInt32Array = PackedInt32Array()
	ind_id.resize(n)
	ind_id.fill(-1)
	var ind_sc: PackedInt32Array = PackedInt32Array()
	ind_sc.resize(n)
	ind_sc.fill(SCORE_NONE)
	var cand: int = 0
	for id: int in buf:
		var t: SimEntity = world.by_id[id]
		if t == null or t == e or t.combat == null or (t.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE | SimFlags.F_UNTARGETABLE)) != 0 or t.container_id >= 0:
			continue
		if t.kind != SimEntity.Kind.UNIT and t.kind != SimEntity.Kind.STRUCTURE:
			continue
		var tc: SimCompCombat = t.combat
		if (tc.cflags & SimCombatConsts.CF_UNTARGETABLE) != 0:
			continue
		if (union_tf & filter_bit(t)) == 0:
			continue
		var d: int = maxi(Fp.dist(t.x - cx, t.y - cy) - t.radius, 0)
		if d > r_query:
			continue
		if (tc.cflags & SimCombatConsts.CF_DECOY) != 0 and world.fog.decoy_identified(e.owner, t):
			continue
		if not world.fog.entity_visible(e.owner, t):
			continue
		cand += 1
		if cand > SimCombatConsts.SCAN_CAND_CAP:
			break
		var td: SimCombatDef = cs.def_for(world, t)
		if primary_ok and d <= r_prim:
			var mb: int = m_best_of(world, cs, e, cd, cc, t, td)
			if mb >= SimWeaponProfile.AUTO_MIN_BP and within_leash(e, cc, t, prim_range):
				var sc: int = score_target(world, e, cc, t, td, d, r_prim, mb)
				if sc > best_sc:
					best_sc = sc
					best_id = id
		if has_ind:
			for m: int in n:
				if ind_r[m] <= 0 or d > ind_r[m]:
					continue
				var mi: int = m_best_of(world, cs, e, cd, cc, t, td, m)
				if mi < SimWeaponProfile.AUTO_MIN_BP:
					continue
				var scm: int = score_target(world, e, cc, t, td, d, ind_r[m], mi)
				if scm > ind_sc[m]:
					ind_sc[m] = scm
					ind_id[m] = id
	if primary_ok and best_id > 0 and best_id != cc.target_id:
		var bt: SimEntity = world.by_id[best_id]
		cc.target_id = best_id
		cc.target_src = SimCombatConsts.TS_AUTO
		cc.target_since = tick
		cc.seen_x = bt.x
		cc.seen_y = bt.y
		cc.seen_tick = tick
		stamp_focus(world, e, bt)
	if has_ind:
		for m: int in n:
			if ind_r[m] > 0 and ind_id[m] > 0:
				var b: int = m * SimCombatConsts.MS + SimCombatConsts.M_TARGET
				if cc.mnt[b] != ind_id[m]:
					cc.mnt[b] = ind_id[m]
					stamp_focus(world, e, world.by_id[ind_id[m]])
	if cc.target_id >= 0 and (cc.target_src == SimCombatConsts.TS_AUTO or cc.target_src == SimCombatConsts.TS_RETAL) and e.kind == SimEntity.Kind.UNIT:
		cc.scan_next = tick + SimCombatConsts.RESCORE_INTERVAL


## Urgent rescan inside P4 (target just lost): at most 16 per tick, same code path as a normal scan.
static func urgent_scan(world: SimWorld, cs: SimCombatSystem, e: SimEntity) -> void:
	if cs.urgent_used >= 16 or not scannable(world, cs, e):
		return
	cs.urgent_used += 1
	scan(world, cs, e)


# ---------------------------------------------------------------------------------------------- validation (5.10.5 a)
## Checks the primary target every tick. Returns VS_*; an invalid target is cleared here.
static func validate(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cd: SimCombatDef, cc: SimCompCombat) -> int:
	if cc.ground_on == 1:
		return VS_OK
	if cc.target_id < 0:
		return VS_NONE
	var tick: int = world.tick
	var t: SimEntity = world.get_entity(cc.target_id)
	var src: int = cc.target_src
	var forced: bool = src == SimCombatConsts.TS_FORCE
	var ordered: bool = forced or src == SimCombatConsts.TS_ORDER
	var ok: bool = t != null and (t.flags & SimFlags.F_GONE) == 0
	if ok:
		ok = false
		for m: int in cd.n_mounts:
			if (ordered or mount_active(cc, cd, m)) and can_engage(world, e, cd, m, t, forced):
				ok = true
				break
	if ok and not ordered and cc.anchor_on == 1 and not within_leash(e, cc, t, cs.range_max_eff(world, e)):
		ok = false
	if ok:
		if forced or world.fog.entity_visible(e.owner, t):
			cc.seen_x = t.x
			cc.seen_y = t.y
			cc.seen_tick = tick
		elif tick - cc.seen_tick > (SimCombatConsts.HIDE_GIVEUP_ORDER if ordered else SimCombatConsts.HIDE_GIVEUP_AUTO):
			ok = false
		else:
			return VS_HIDDEN
	if ok:
		return VS_OK
	clear_target(e)
	return VS_NONE


# ---------------------------------------------------------------------------------------------- retaliation / assist (5.10.5 d, e)
## After the damage flush, once per victim: assist first, then the victim's own retaliation.
static func on_damaged(world: SimWorld, v: SimEntity, attacker_id: int) -> void:
	if attacker_id <= 0 or v.combat == null or (v.flags & SimFlags.F_GONE) != 0:
		return
	var atk: SimEntity = world.get_entity(attacker_id)
	if atk == null or (atk.flags & SimFlags.F_GONE) != 0 or atk.combat == null:
		return
	if world.rel(v.owner, atk.owner) != SimCombatConsts.REL_ENEMY:
		return
	var cs: SimCombatSystem = world.combat
	if not world.fog.entity_visible(v.owner, atk):
		return
	_assist(world, cs, v, atk)
	_retaliate(world, cs, v, atk)


static func _retaliate(world: SimWorld, cs: SimCombatSystem, v: SimEntity, atk: SimEntity) -> void:
	var cc: SimCompCombat = v.combat
	if cc.n_mounts == 0 or cc.stance == SimCombatConsts.ST_HOLD_FIRE or v.owner < 0:
		return
	if cc.target_id == atk.id or cc.ground_on == 1:
		return
	if cc.target_id >= 0:
		var src: int = cc.target_src
		if src != SimCombatConsts.TS_AUTO and src != SimCombatConsts.TS_GUARD and src != SimCombatConsts.TS_RETAL:
			return
		var cur: SimEntity = world.get_entity(cc.target_id)
		if cur != null and (cur.flags & SimFlags.F_GONE) == 0:
			var s_cur: int = rate(world, cs, v, cur)
			var s_atk: int = rate(world, cs, v, atk)
			if s_atk == SCORE_NONE or (s_cur != SCORE_NONE and s_atk < s_cur + SimCombatConsts.RETAL_MARGIN):
				return
	if can_attack(world, v, atk, false, false):
		set_target(world, v, atk.id, SimCombatConsts.TS_RETAL)


static func _assist(world: SimWorld, cs: SimCombatSystem, v: SimEntity, atk: SimEntity) -> void:
	var cc: SimCompCombat = v.combat
	var tick: int = world.tick
	if tick - cc.last_assist_tick < SimCombatConsts.ASSIST_COOLDOWN:
		return
	cc.last_assist_tick = tick
	var buf: PackedInt32Array = cs.scan_buf
	world.query_circle(v.x, v.y, SimCombatConsts.ASSIST_RADIUS, buf, SimTag.ALIVE, SimTag.kind_bit(SimEntity.Kind.ZONE) | SimTag.kind_bit(SimEntity.Kind.WRECK))
	var helped: int = 0
	for id: int in buf:
		if helped >= 12:
			break
		if id == v.id:
			continue
		var o: SimEntity = world.by_id[id]
		if o == null or o.combat == null or o.combat.n_mounts == 0 or (o.kind != SimEntity.Kind.UNIT and o.kind != SimEntity.Kind.STRUCTURE):
			continue
		var r: int = world.rel(v.owner, o.owner)
		if r != SimCombatConsts.REL_SELF and r != SimCombatConsts.REL_ALLY:
			continue
		var oc: SimCompCombat = o.combat
		if oc.stance == SimCombatConsts.ST_HOLD_FIRE or oc.target_id >= 0 or oc.ground_on == 1 or not o.orders.is_empty():
			continue
		if not world.fog.entity_visible(o.owner, atk):
			continue
		if set_target(world, o, atk.id, SimCombatConsts.TS_RETAL):
			helped += 1
