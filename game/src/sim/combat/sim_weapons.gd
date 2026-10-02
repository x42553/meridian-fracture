class_name SimWeapons
extends RefCounted
## P4 of SimCombatSystem (combat 5.2 / 5.3 / 5.4.1): mount aiming and slew, firing gates, salvo / reload / ammo,
## hitscan resolution, continuous beams and muzzle geometry. One instance per world (`cs.weapons`); the only fields are
## per-entity scratch values that are rewritten before use (nothing here is state or hashed).
## Mount state lives in SimCompCombat.mnt (M_*): M_NEXT doubles as "last tick with a target" while no salvo runs
## (idle turret return), M_DOT doubles as the salvo start tick for non-beam mounts; M_BEAM = start tick or -1.

const G_OK: int = 0
const G_OFFLINE: int = 1
const G_STATE: int = 2
const G_NO_TARGET: int = 3
const G_RANGE: int = 4
const G_ARC: int = 5
const G_STANCE: int = 6
const G_MOVE: int = 7
const G_AMMO: int = 8
const G_HIDDEN: int = 9

const BR_LOST: int = 0
const BR_OVERHEAT: int = 1
const BR_DISABLED: int = 2
const BR_DEAD: int = 3
const BR_ORDER: int = 4
const BR_RANGE: int = 5

var _t: SimEntity = null  ## primary target of the current entity (null = ground point or none)
var _vs: int = 0
var _tx: int = 0
var _ty: int = 0
var _moving: bool = false


# ---------------------------------------------------------------------------------------------- pure helpers
## Reload with modifiers (combat 5.3): `pm_reload` = resolved ticks, `base` = unmodified ticks, `agg_bp` = temporary
## layer. The bible floor is 50 % of the base.
static func reload_eff(pm_reload: int, base: int, agg_bp: int) -> int:
	return maxi(Fp.ceil_div(pm_reload * maxi(0, 10000 + agg_bp), 10000), Fp.ceil_div(base, 2))


## One slew step: `cur` moves toward `goal` by at most `turn` (bat); both are hull-relative angles.
static func aim_step(cur: int, goal: int, turn: int) -> int:
	return (cur + clampi(SimCombatConsts.wrap_signed(goal - cur), -turn, turn)) & Fp.ANGLE_MASK


## Number of ticks a turret needs to close `err` bat at `turn` bat/tick.
static func slew_ticks(err: int, turn: int) -> int:
	return Fp.ceil_div(absi(err), maxi(turn, 1))


## Muzzle point of mount `m` (combat 5.2): turrets add their current angle to the hull facing.
static func muzzle_x(e: SimEntity, cd: SimCombatDef, m: int, cur: int) -> int:
	var f: int = _muzzle_angle(e, cd, m, cur)
	return e.x + ((cd.mount_val(m, SimCombatDef.MT_OFF_FWD) * Fp.cos(f) - cd.mount_val(m, SimCombatDef.MT_OFF_SIDE) * Fp.sin(f)) >> 16)


static func muzzle_y(e: SimEntity, cd: SimCombatDef, m: int, cur: int) -> int:
	var f: int = _muzzle_angle(e, cd, m, cur)
	return e.y + ((cd.mount_val(m, SimCombatDef.MT_OFF_FWD) * Fp.sin(f) + cd.mount_val(m, SimCombatDef.MT_OFF_SIDE) * Fp.cos(f)) >> 16)


static func _muzzle_angle(e: SimEntity, cd: SimCombatDef, m: int, cur: int) -> int:
	if cd.mount_val(m, SimCombatDef.MT_KIND) == SimCombatConsts.MK_TURRET:
		return (e.facing + cur) & Fp.ANGLE_MASK
	return e.facing


## Hitscan hit probability in bp (combat 5.4.1).
static func hit_chance_bp(acc: int, fall: int, move_pen: int, shooter_pen: int, d_eff: int, range_eff: int, tv_speed: int,
		t_radius: int, shooter_moving: bool, t_is_structure: bool) -> int:
	if t_is_structure:
		return 10000
	var p: int = acc - fall * mini(d_eff, range_eff) / maxi(range_eff, 1)
	p -= move_pen * mini(tv_speed, SimCombatConsts.ACC_V_REF) / SimCombatConsts.ACC_V_REF
	if shooter_moving:
		p -= shooter_pen
	p += mini(2500, t_radius * 2500 / 1024)
	return clampi(p, SimCombatConsts.ACC_MIN_BP, 10000)


## Beam damage multiplier in bp after `elapsed` ticks: 10000 rising linearly to `max_bp` over `ramp_t` (combat 5.3).
static func beam_ramp_bp(elapsed: int, ramp_t: int, max_bp: int) -> int:
	if ramp_t <= 0:
		return 10000
	return 10000 + (max_bp - 10000) * mini(elapsed, ramp_t) / ramp_t


# ---------------------------------------------------------------------------------------------- P4 driver
func update_all(world: SimWorld, cs: SimCombatSystem) -> void:
	var ids: PackedInt32Array = cs.armed_ids
	var n0: int = ids.size()
	for i: int in n0:
		if i >= ids.size():
			break
		var e: SimEntity = world.get_entity(ids[i])
		if e != null and e.combat != null and e.combat.n_mounts > 0:
			update_entity(world, cs, e)


func update_entity(world: SimWorld, cs: SimCombatSystem, e: SimEntity) -> void:
	var cc: SimCompCombat = e.combat
	if (e.flags & SimFlags.F_FIRING) != 0:
		e.flags &= ~SimFlags.F_FIRING
	if (e.flags & SimFlags.F_GONE) != 0 or ((e.flags & SimFlags.F_INSIDE) != 0 and (e.flags & SimFlags.F_GARRISONED) == 0) or (cc.cflags & (SimCombatConsts.CF_DEAD | SimCombatConsts.CF_DYING)) != 0:
		return  # FIX (AB2): garrisoned squads fire from the building (garrison_fire); other passengers never do
	if e.air != null and e.air.is_airfield == 0:
		var st: int = e.air.state
		if st == SimCombatConsts.AIR_PARKED or st == SimCombatConsts.AIR_REARM or st == SimCombatConsts.AIR_DOCKED:
			return
	var cd: SimCombatDef = cs.def_for(world, e)
	if cd == null:
		return
	var tick: int = world.tick
	if cc.want_deploy != -1 or cc.want_mode != -1 or cc.want_surface != -1:
		cc.want_deploy = -1
		cc.want_mode = -1
		cc.want_surface = -1
	_moving = cc.ext_moving == 1 or (e.flags & SimFlags.F_MOVING) != 0
	if _moving:
		cc.still_ticks = 0
	elif cc.still_ticks < 255:
		cc.still_ticks += 1
	if cc.target_id < 0 and cc.ground_on == 0 and _idle(cc, cd):
		return
	# primary target: validate every tick, urgent rescan when it was lost
	_t = null
	_vs = SimTargeting.VS_NONE
	if cc.ground_on == 1:
		_vs = SimTargeting.VS_OK
		_tx = cc.ground_x
		_ty = cc.ground_y
	elif cc.target_id >= 0:
		_vs = SimTargeting.validate(world, cs, e, cd, cc)
		if _vs == SimTargeting.VS_NONE:
			SimTargeting.urgent_scan(world, cs, e)
			if cc.target_id >= 0:
				_vs = SimTargeting.validate(world, cs, e, cd, cc)
		if _vs != SimTargeting.VS_NONE:
			_t = world.get_entity(cc.target_id)
			if _t != null:
				_tx = _t.x
				_ty = _t.y
			else:
				_vs = SimTargeting.VS_NONE
	if _vs != SimTargeting.VS_NONE and _t != null and _modal(cd):
		_request_mode(cc, cd, world, e)
	var online: bool = (cc.emp_until == 0 and cc.wlock_until == 0 and e.kind != SimEntity.Kind.STRUCTURE) or cs.weapons_online(world, e)
	for m: int in cd.n_mounts:
		_mount(world, cs, e, cc, cd, m, tick, online)


## No target, no salvo / beam running, no independent target, turrets at rest: nothing to do this tick.
static func _idle(cc: SimCompCombat, cd: SimCombatDef) -> bool:
	for m: int in cd.n_mounts:
		var b: int = m * SimCombatConsts.MS
		if cc.mnt[b + SimCombatConsts.M_BEAM] >= 0 or cc.mnt[b + SimCombatConsts.M_BURST] > 0 or cc.mnt[b + SimCombatConsts.M_TARGET] >= 0:
			return false
		if cd.mount_val(m, SimCombatDef.MT_TURN) > 0 and cc.mnt[b + SimCombatConsts.M_ANGLE] != cd.mount_val(m, SimCombatDef.MT_ARC_CENTER):
			return false
	return true


static func _modal(cd: SimCombatDef) -> bool:
	for m: int in cd.n_mounts:
		if cd.mount_val(m, SimCombatDef.MT_MODE_MASK) != 0:
			return true
	return false


## want_mode: no active mount can engage the target but a mount of another mode can.
func _request_mode(cc: SimCompCombat, cd: SimCombatDef, world: SimWorld, e: SimEntity) -> void:
	var pending: int = -1
	for m: int in cd.n_mounts:
		var mm: int = cd.mount_val(m, SimCombatDef.MT_MODE_MASK)
		if mm == 0:
			if SimTargeting.can_engage(world, e, cd, m, _t, cc.target_src == SimCombatConsts.TS_FORCE):
				return
			continue
		if SimTargeting.mount_active(cc, cd, m):
			if SimTargeting.can_engage(world, e, cd, m, _t, cc.target_src == SimCombatConsts.TS_FORCE):
				return
		elif pending < 0 and SimTargeting.can_engage(world, e, cd, m, _t, cc.target_src == SimCombatConsts.TS_FORCE):
			for k: int in 8:
				if ((mm >> k) & 1) == 1:
					pending = k
					break
	if pending >= 0:
		cc.want_mode = pending


# ---------------------------------------------------------------------------------------------- one mount
func _mount(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cc: SimCompCombat, cd: SimCombatDef, m: int, tick: int, online: bool) -> void:
	var b: int = m * SimCombatConsts.MS
	var mnt: PackedInt32Array = cc.mnt
	var pr: PackedInt32Array = cd.prof
	var pb: int = m * SimWeaponProfile.PN
	var mt: PackedInt32Array = cd.mounts
	var mb: int = m * SimCombatDef.MT
	var kind: int = pr[pb + SimWeaponProfile.PF_KIND]
	var is_beam: bool = kind == SimCombatConsts.PK_BEAM
	var indep: bool = cd.n_mounts > 1 and mt[mb + SimCombatDef.MT_INDEP] == 1
	var mmask: int = mt[mb + SimCombatDef.MT_MODE_MASK]
	var active: bool = mmask == 0 or (cc.ext_mode >= 0 and ((mmask >> cc.ext_mode) & 1) == 1)  # FIX (AB2): ext_mode -1 = switching
	var s: DefWeaponSlot = cd.slots[cd.slot_of_mount(m)]
	# ---- target of this mount
	var t: SimEntity = null
	var tx: int = 0
	var ty: int = 0
	var have: bool = false
	var src: int = cc.target_src
	var forced: bool = false
	if active:
		if indep:
			src = SimCombatConsts.TS_AUTO
			var tid: int = mnt[b + SimCombatConsts.M_TARGET]
			if tid >= 0:
				t = world.get_entity(tid)
				if t != null and (t.flags & SimFlags.F_GONE) == 0 and SimTargeting.can_engage(world, e, cd, m, t, false) \
						and world.fog.entity_visible(e.owner, t):
					have = true
					tx = t.x
					ty = t.y
				else:
					t = null
					cc.mnt[b + SimCombatConsts.M_TARGET] = -1
					cc.scan_next = mini(cc.scan_next, tick)
		elif _vs == SimTargeting.VS_OK:
			have = true
			t = _t
			tx = _tx
			ty = _ty
			forced = cc.ground_on == 1 or src == SimCombatConsts.TS_FORCE
			if t != null and cd.n_mounts > 1 and not SimTargeting.can_engage(world, e, cd, m, t, forced):
				have = false  # another mount's target class
	# ---- geometry and aiming
	var turn: int = mt[mb + SimCombatDef.MT_TURN]
	var center: int = mt[mb + SimCombatDef.MT_ARC_CENTER]
	var half: int = mt[mb + SimCombatDef.MT_ARC_HALF]
	var cur: int = mnt[b + SimCombatConsts.M_ANGLE]
	var d_eff: int = 0
	var aimed: bool = false
	var in_arc: bool = false
	if have:
		var dx: int = tx - e.x
		var dy: int = ty - e.y
		d_eff = Fp.dist(dx, dy)
		if t != null:
			d_eff = maxi(d_eff - t.radius, 0)
		var bearing: int = Fp.atan2(dy, dx) if (dx != 0 or dy != 0) else e.facing
		var rel: int = SimCombatConsts.wrap_signed(bearing - e.facing - center)
		in_arc = half >= Fp.ANGLE_HALF or absi(rel) <= half
		var goal: int = center
		if in_arc:
			goal = (center + rel) & Fp.ANGLE_MASK
		else:
			goal = (center + (half if rel > 0 else -half)) & Fp.ANGLE_MASK
		if turn == 0:
			cur = center
			aimed = in_arc  # fixed / hull mounts: pointing is the hull's job
		else:
			cur = aim_step(cur, goal, turn)
			aimed = in_arc and absi(SimCombatConsts.wrap_signed(goal - cur)) <= mt[mb + SimCombatDef.MT_AIM_TOL]
		mnt[b + SimCombatConsts.M_ANGLE] = cur
		if aimed:
			if mnt[b + SimCombatConsts.M_AIM_SINCE] < 0:
				mnt[b + SimCombatConsts.M_AIM_SINCE] = tick
		else:
			mnt[b + SimCombatConsts.M_AIM_SINCE] = -1
		if mnt[b + SimCombatConsts.M_BURST] == 0:
			mnt[b + SimCombatConsts.M_NEXT] = tick
	else:
		mnt[b + SimCombatConsts.M_AIM_SINCE] = -1
		if turn > 0 and cur != center and mnt[b + SimCombatConsts.M_BURST] == 0 and tick - mnt[b + SimCombatConsts.M_NEXT] >= SimCombatConsts.TURRET_IDLE_RETURN:
			mnt[b + SimCombatConsts.M_ANGLE] = aim_step(cur, center, maxi(turn / 2, 1))
	# ---- nothing to shoot at: end beams, let salvos time out
	var beam_on: bool = mnt[b + SimCombatConsts.M_BEAM] >= 0
	# ---- gates 1-6, 8
	var gate: int = G_OK
	var range_max: int = 0
	if not have:
		gate = G_HIDDEN if (active and not indep and _vs == SimTargeting.VS_HIDDEN) else G_NO_TARGET
	else:
		range_max = DefStatMath.apply_bp(cs.slot_stat(world, e, cd, m, DefEnums.Stat.RANGE), cc.agg_range_bp)
		gate = _gates(e, cc, cd, m, s, online, d_eff, range_max, in_arc, aimed, src, mnt[b + SimCombatConsts.M_BURST] == 0)
	# ---- beams
	if is_beam:
		_beam(world, cs, e, cc, cd, m, s, t, gate, beam_on, tick, mnt, b)
		return
	# ---- salvo / cooldown
	var burst_left: int = mnt[b + SimCombatConsts.M_BURST]
	var bi: int = pr[pb + SimWeaponProfile.PF_BURST_INT]
	if burst_left > 0:
		if tick >= mnt[b + SimCombatConsts.M_NEXT]:
			if gate == G_OK and aimed:
				_shoot(world, cs, e, cc, cd, m, s, t, tx, ty, d_eff, range_max, forced, kind, pr[pb + SimWeaponProfile.PF_BURST] - burst_left, tick)
				burst_left -= 1
				mnt[b + SimCombatConsts.M_BURST] = burst_left
				if burst_left == 0:
					_finish_salvo(world, cs, e, cc, cd, m, tick, mnt, b)
				else:
					mnt[b + SimCombatConsts.M_NEXT] = tick + bi
			elif tick - mnt[b + SimCombatConsts.M_NEXT] > 2 * bi + 2:
				mnt[b + SimCombatConsts.M_BURST] = 0
				mnt[b + SimCombatConsts.M_CD] = tick + reload_of(world, cs, e, cc, cd, m) / 2
		return
	if gate != G_OK or tick < mnt[b + SimCombatConsts.M_CD]:
		return
	var delay: int = pr[pb + SimWeaponProfile.PF_AIM_DELAY]
	if mnt[b + SimCombatConsts.M_AIM_SINCE] < 0 or tick - mnt[b + SimCombatConsts.M_AIM_SINCE] < delay:
		return
	# start a salvo
	var per: int = pr[pb + SimWeaponProfile.PF_AMMO_PER_SALVO]
	if mnt[b + SimCombatConsts.M_AMMO] >= 0:
		mnt[b + SimCombatConsts.M_AMMO] -= per
	mnt[b + SimCombatConsts.M_DOT] = tick
	_shoot(world, cs, e, cc, cd, m, s, t, tx, ty, d_eff, range_max, forced, kind, 0, tick)
	var total: int = pr[pb + SimWeaponProfile.PF_BURST]
	if total > 1:
		mnt[b + SimCombatConsts.M_BURST] = total - 1
		mnt[b + SimCombatConsts.M_NEXT] = tick + bi
	else:
		_finish_salvo(world, cs, e, cc, cd, m, tick, mnt, b)


## Reload is counted from the salvo start (the balance sheets' `reload_s` is the full cycle), never below the last
## shot + 1.
func _finish_salvo(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cc: SimCompCombat, cd: SimCombatDef, m: int, tick: int,
		mnt: PackedInt32Array, b: int) -> void:
	var rl: int = reload_of(world, cs, e, cc, cd, m)
	var start: int = mnt[b + SimCombatConsts.M_DOT]
	mnt[b + SimCombatConsts.M_CD] = maxi(tick + 1, start + rl)


## Effective reload of mount `m` in ticks (combat 5.3 formula).
func reload_of(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cc: SimCompCombat, cd: SimCombatDef, m: int) -> int:
	var pm: int = maxi(Fp.ceil_div(cs.slot_stat(world, e, cd, m, DefEnums.Stat.RELOAD), 1000), 1)
	return reload_eff(pm, _base_reload(world, e, cd, m), cc.agg_reload_bp)


static func _base_reload(world: SimWorld, e: SimEntity, cd: SimCombatDef, m: int) -> int:
	var si: int = cd.slot_of_mount(m)
	if e.kind == SimEntity.Kind.UNIT and e.def_idx >= 0 and e.def_idx < world.data.units.size():
		var ws: Array[DefWeaponSlot] = world.data.units[e.def_idx].weapons
		if si < ws.size():
			return ws[si].reload_ticks
	elif e.kind == SimEntity.Kind.STRUCTURE and e.def_idx >= 0 and e.def_idx < world.data.structures.size():
		var wt: Array[DefWeaponSlot] = world.data.structures[e.def_idx].weapons
		if si < wt.size():
			return wt[si].reload_ticks
	return cd.slots[si].reload_ticks


# ---------------------------------------------------------------------------------------------- gates (5.3)
func _gates(e: SimEntity, cc: SimCompCombat, cd: SimCombatDef, m: int, s: DefWeaponSlot, online: bool, d_eff: int, range_max: int,
		in_arc: bool, aimed: bool, src: int, starting: bool) -> int:
	var pr: PackedInt32Array = cd.prof
	var pb: int = m * SimWeaponProfile.PN
	# 1 weapons online
	if not online:
		return G_OFFLINE
	# 2 shooter state
	var rd: int = cd.mounts[m * SimCombatDef.MT + SimCombatDef.MT_REQ_DEPLOYED]
	if rd == 1 and cc.ext_deployed == 0:
		if d_eff <= range_max + 1024:
			cc.want_deploy = 1
		return G_STATE
	if rd == 0 and cc.ext_deployed == 1:
		return G_STATE
	if s.requires_surface_t > 0 and e.layer != SimCombatConsts.LAYER_SURFACE:
		if d_eff <= range_max + 1024:
			cc.want_surface = 1
		return G_STATE
	# 3 ammo
	var b: int = m * SimCombatConsts.MS
	var ammo: int = cc.mnt[b + SimCombatConsts.M_AMMO]
	if starting and ammo >= 0 and ammo < pr[pb + SimWeaponProfile.PF_AMMO_PER_SALVO]:
		return G_AMMO
	# 4 movement
	var settle: int = pr[pb + SimWeaponProfile.PF_SETTLE]
	if settle > 0 and (_moving or cc.still_ticks < settle):
		return G_MOVE
	# 5 reach
	if d_eff > range_max or d_eff < s.min_range:
		return G_RANGE
	# 6 aim
	if not in_arc:
		return G_ARC
	# 8 stance
	if cc.stance == SimCombatConsts.ST_HOLD_FIRE and src != SimCombatConsts.TS_ORDER and src != SimCombatConsts.TS_FORCE:
		return G_STANCE
	if not aimed:
		return G_ARC
	return G_OK


# ---------------------------------------------------------------------------------------------- firing
func _shoot(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cc: SimCompCombat, cd: SimCombatDef, m: int, s: DefWeaponSlot,
		t: SimEntity, tx: int, ty: int, d_eff: int, range_max: int, forced: bool, kind: int, burst_i: int, tick: int) -> void:
	var b: int = m * SimCombatConsts.MS
	var cur: int = cc.mnt[b + SimCombatConsts.M_ANGLE]
	var mx: int = muzzle_x(e, cd, m, cur)
	var my: int = muzzle_y(e, cd, m, cur)
	var wh_ref: int = cs.warhead_ref(world, e, cd, m)
	var wh: SimCombatWarhead = SimProjectiles.warhead_of(world, e.owner, wh_ref)
	var base: int = cs.slot_stat(world, e, cd, m, DefEnums.Stat.DAMAGE)
	var tmp: int = cc.agg_dmg_bp
	var barrels: int = maxi(cd.mount_val(m, SimCombatDef.MT_BARRELS), 1)
	var barrel: int = cc.mnt[b + SimCombatConsts.M_SHOTS] % barrels
	var result: int = 0
	var ix: int = tx
	var iy: int = ty
	if kind == SimCombatConsts.PK_HITSCAN:
		var pt: PackedInt32Array = _hitscan(world, cs, e, cc, cd, m, t, tx, ty, d_eff, range_max, forced, wh, base, tmp)
		result = pt[0]
		ix = pt[1]
		iy = pt[2]
	else:
		var spd: int = cs.slot_stat(world, e, cd, m, DefEnums.Stat.PROJ_SPEED)
		result = cs.proj.launch(world, e, cd, m, t, tx, ty, mx, my, base, range_max, spd, forced, wh_ref, wh, tmp)
	cc.mnt[b + SimCombatConsts.M_SHOTS] += 1
	cc.last_fire_tick = tick
	e.flags |= SimFlags.F_FIRING
	cs.counters[SimCombatSystem.CNT_SHOTS] += 1
	world.emit(SimCombatConsts.EV_FIRE, mx, my, e.id, s.arch, m | (barrel << 4) | (kind << 8) | (result << 12) | (burst_i << 16),
		t.id if t != null else -1, ix, iy)


## Resolves a hitscan shot now. Returns [result (1 hit / 2 miss), impact x, impact y]. RNG: 1 draw (0 when the chance is
## 10000), +2 on a miss (displacement bearing).
func _hitscan(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cc: SimCompCombat, cd: SimCombatDef, m: int, t: SimEntity, tx: int, ty: int,
		d_eff: int, range_max: int, forced: bool, wh: SimCombatWarhead, base: int, tmp: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array([1, tx, ty])
	var ifl: int = 0
	if (cc.cflags & SimCombatConsts.CF_ENEMY_ONLY) != 0:
		ifl |= SimCombatConsts.PI_ENEMY_ONLY
	if forced:
		ifl |= SimCombatConsts.PI_FORCED
	if e.layer != SimCombatConsts.LAYER_GROUND:
		ifl |= SimProjectiles.PI_AIR_SHOOTER
	if wh.packet == 1:
		ifl |= SimCombatConsts.PI_PACKET
	var p: int = 10000
	if t != null:
		p = hit_chance_bp(cd.pf(m, SimWeaponProfile.PF_ACC), cd.pf(m, SimWeaponProfile.PF_ACC_FALL), cd.pf(m, SimWeaponProfile.PF_ACC_MOVE),
			cd.pf(m, SimWeaponProfile.PF_ACC_SHOOTER), d_eff, range_max, Fp.dist(t.vx, t.vy), t.radius, _moving,
			t.kind == SimEntity.Kind.STRUCTURE)
	var hit: bool = p >= 10000 or world.rng.next_int(10000) < p
	var dir: int = Fp.atan2(e.y - ty, e.x - tx) if (e.x != tx or e.y != ty) else e.facing
	if hit:
		if t != null or wh.splash_r > 0:
			cs.proj.detonate(world, wh, tx, ty, t.id if t != null else -1, base, 10000, tmp, e.owner, e.id, ifl, (dir + Fp.ANGLE_HALF) & Fp.ANGLE_MASK, -1, wh.splash_r > 0)
		return out
	var a: int = world.rng.next_int(4096)
	var disp: int = 256 + d_eff / 16
	var mxp: int = tx + Fp.step_x(a, disp)
	var myp: int = ty + Fp.step_y(a, disp)
	if wh.splash_r > 0:
		cs.proj.detonate(world, wh, mxp, myp, -1, base, 10000, tmp, e.owner, e.id, ifl, -1, -1, true)
	out[0] = 2
	out[1] = mxp
	out[2] = myp
	return out


# ---------------------------------------------------------------------------------------------- beams (5.3)
func _beam(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cc: SimCompCombat, cd: SimCombatDef, m: int, s: DefWeaponSlot,
		t: SimEntity, gate: int, beam_on: bool, tick: int, mnt: PackedInt32Array, b: int) -> void:
	var beam_max: int = cd.pf(m, SimWeaponProfile.PF_BEAM_MAX)
	var indep: bool = cd.n_mounts > 1 and cd.mount_val(m, SimCombatDef.MT_INDEP) == 1
	if not beam_on:
		if gate != G_OK or t == null or tick < mnt[b + SimCombatConsts.M_CD]:
			return
		if mnt[b + SimCombatConsts.M_AIM_SINCE] < 0 or tick - mnt[b + SimCombatConsts.M_AIM_SINCE] < cd.pf(m, SimWeaponProfile.PF_AIM_DELAY):
			return
		mnt[b + SimCombatConsts.M_BEAM] = tick
		mnt[b + SimCombatConsts.M_DOT] = tick + maxi(s.reload_ticks, 1)
		if not indep:
			mnt[b + SimCombatConsts.M_TARGET] = t.id
		var cur: int = mnt[b + SimCombatConsts.M_ANGLE]
		world.emit(SimCombatConsts.EV_BEAM_START, muzzle_x(e, cd, m, cur), muzzle_y(e, cd, m, cur), e.id, s.arch, m, t.id, beam_max)
		return
	# beam is on
	var reason: int = -1
	if gate == G_OFFLINE:
		reason = BR_DISABLED
	elif t == null:
		reason = BR_DEAD if gate == G_NO_TARGET else BR_LOST
	elif not indep and mnt[b + SimCombatConsts.M_TARGET] != t.id:
		reason = BR_ORDER
	elif gate == G_RANGE:
		reason = BR_RANGE
	elif gate != G_OK:
		reason = BR_LOST
	elif beam_max > 0 and tick - mnt[b + SimCombatConsts.M_BEAM] >= beam_max:
		reason = BR_OVERHEAT
	if reason >= 0:
		mnt[b + SimCombatConsts.M_BEAM] = -1
		if not indep:
			mnt[b + SimCombatConsts.M_TARGET] = -1
		mnt[b + SimCombatConsts.M_CD] = tick + reload_of(world, cs, e, cc, cd, m)
		world.emit(SimCombatConsts.EV_BEAM_END, e.x, e.y, e.id, reason, m)
		return
	if tick >= mnt[b + SimCombatConsts.M_DOT]:
		var ramp: int = beam_ramp_bp(tick - mnt[b + SimCombatConsts.M_BEAM], s.ramp_t, s.ramp_max_bp)
		var dmg: int = cs.slot_stat(world, e, cd, m, DefEnums.Stat.DAMAGE)
		var base: int = maxi(1, SimDamage.mul(dmg, ramp))
		var wh: SimCombatWarhead = SimProjectiles.warhead_of(world, e.owner, cs.warhead_ref(world, e, cd, m))
		SimDamage.deal(world, t, wh, base, SimCombatConsts.DC_DIRECT, 0, e.id, e.owner, e.layer == SimCombatConsts.LAYER_GROUND, 10000,
			cc.agg_dmg_bp, 10000, Fp.atan2(e.y - t.y, e.x - t.x), 0, t.x, t.y)
		cc.last_fire_tick = tick
		e.flags |= SimFlags.F_FIRING
		mnt[b + SimCombatConsts.M_DOT] += maxi(s.reload_ticks, 1)
		mnt[b + SimCombatConsts.M_SHOTS] += 1
		cs.counters[SimCombatSystem.CNT_SHOTS] += 1
		var cur2: int = mnt[b + SimCombatConsts.M_ANGLE]
		world.emit(SimCombatConsts.EV_FIRE, muzzle_x(e, cd, m, cur2), muzzle_y(e, cd, m, cur2), e.id, s.arch, m | (SimCombatConsts.PK_BEAM << 8) | (3 << 12), t.id, t.x, t.y)
