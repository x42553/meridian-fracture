class_name SimProjectiles
extends RefCounted
## The projectile pool (combat 4.4 / 5.4 / 5.5 / 5.7 / 3.5): struct of arrays of capacity PROJ_POOL, LIFO free list,
## `serial` = identity used by events. Owned by SimCombatSystem (`cs.proj`). Every field is public read-only for the
## view (`snapshot`). Kinds: BULLET (straight, swept test), MISSILE (guided), ARC (integer flight time), BOMB (arc with
## fall time), STRIKE (delayed detonation), SWEEP (Helios line; `turn` = spot length, `hit_r` = width). Hitscan and
## beams are not projectiles (SimWeapons). All arithmetic is integer; RNG draws happen only in `launch`.

const CAP: int = SimCombatConsts.PROJ_POOL
const PI_AIR_SHOOTER: int = 64  ## shooter was not on LAYER_GROUND (STAT_MARK ground-only filter)
const REMOTE_ARC_SPEED: int = 768  ## u/tick of remote (power) shells
const SPAWN_MISSILE_GRACE: int = 20
const SNAP_STRIDE: int = 11  ## snapshot record: serial, kind, pdef, x, y, px, py, heading, owner_pid, target, t_end
const NEUTRAL_REF: int = 1 << 20  ## `wh` bit: index refers to the neutral table

var alive: PackedInt32Array = PackedInt32Array()
var serial: PackedInt32Array = PackedInt32Array()
var kind: PackedInt32Array = PackedInt32Array()
var pdef: PackedInt32Array = PackedInt32Array()  ## visual id: DefEnums.WeaponArch of the source weapon (-1 remote)
var wh: PackedInt32Array = PackedInt32Array()  ## warhead index in the owner's tables (| NEUTRAL_REF)
var wpn: PackedInt32Array = PackedInt32Array()  ## mount slot index of the source weapon, -1 remote
var owner_pid: PackedInt32Array = PackedInt32Array()
var owner_id: PackedInt32Array = PackedInt32Array()
var owner_team: PackedInt32Array = PackedInt32Array()
var x: PackedInt32Array = PackedInt32Array()
var y: PackedInt32Array = PackedInt32Array()
var px: PackedInt32Array = PackedInt32Array()
var py: PackedInt32Array = PackedInt32Array()
var sx: PackedInt32Array = PackedInt32Array()
var sy: PackedInt32Array = PackedInt32Array()
var ex: PackedInt32Array = PackedInt32Array()
var ey: PackedInt32Array = PackedInt32Array()
var vx: PackedInt32Array = PackedInt32Array()
var vy: PackedInt32Array = PackedInt32Array()
var heading: PackedInt32Array = PackedInt32Array()
var speed: PackedInt32Array = PackedInt32Array()
var t0: PackedInt32Array = PackedInt32Array()
var t_end: PackedInt32Array = PackedInt32Array()
var flight: PackedInt32Array = PackedInt32Array()
var target: PackedInt32Array = PackedInt32Array()
var dmg: PackedInt32Array = PackedInt32Array()  ## resolved base damage per instance (research applied)
var dmg_bp: PackedInt32Array = PackedInt32Array()
var dmg_tmp: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()  ## PI_*
var pflags: PackedInt32Array = PackedInt32Array()  ## PF_*
var est: PackedInt32Array = PackedInt32Array()
var aux0: PackedInt32Array = PackedInt32Array()  ## missile homing delay left / sweep dot interval
var aux1: PackedInt32Array = PackedInt32Array()  ## missile launch delay left / sweep next dot tick
var hit_r: PackedInt32Array = PackedInt32Array()  ## hit radius (sweep: width)
var turn: PackedInt32Array = PackedInt32Array()  ## missile turn rate (sweep: spot length)

var live: int = 0
var free_stack: PackedInt32Array = PackedInt32Array()
var hi: int = 0  ## 1 + highest slot ever allocated since the last shrink (iteration bound, not hashed)
var _buf: PackedInt32Array = PackedInt32Array()
var _hit: PackedInt32Array = PackedInt32Array([0, 0])


func _init() -> void:
	alive.resize(CAP)
	serial.resize(CAP)
	kind.resize(CAP)
	pdef.resize(CAP)
	wh.resize(CAP)
	wpn.resize(CAP)
	owner_pid.resize(CAP)
	owner_id.resize(CAP)
	owner_team.resize(CAP)
	x.resize(CAP)
	y.resize(CAP)
	px.resize(CAP)
	py.resize(CAP)
	sx.resize(CAP)
	sy.resize(CAP)
	ex.resize(CAP)
	ey.resize(CAP)
	vx.resize(CAP)
	vy.resize(CAP)
	heading.resize(CAP)
	speed.resize(CAP)
	t0.resize(CAP)
	t_end.resize(CAP)
	flight.resize(CAP)
	target.resize(CAP)
	dmg.resize(CAP)
	dmg_bp.resize(CAP)
	dmg_tmp.resize(CAP)
	flags.resize(CAP)
	pflags.resize(CAP)
	est.resize(CAP)
	aux0.resize(CAP)
	aux1.resize(CAP)
	hit_r.resize(CAP)
	turn.resize(CAP)
	free_stack.resize(CAP)
	for i: int in CAP:
		free_stack[i] = CAP - 1 - i  # pop_back yields 0, 1, 2 ...


# ---------------------------------------------------------------------------------------------- read API
func live_count() -> int:
	return live


func is_live(slot: int) -> bool:
	return slot >= 0 and slot < CAP and alive[slot] == 1


## Slot of a live projectile by serial, -1 when it ended.
func slot_of_serial(ser: int) -> int:
	for i: int in hi:
		if alive[i] == 1 and serial[i] == ser:
			return i
	return -1


## View snapshot: appends SNAP_STRIDE ints per live projectile (ascending slot) to `out` (cleared first). Returns the count.
func snapshot(out: PackedInt32Array) -> int:
	out.resize(0)
	var n: int = 0
	for i: int in hi:
		if alive[i] == 0:
			continue
		out.append(serial[i])
		out.append(kind[i])
		out.append(pdef[i])
		out.append(x[i])
		out.append(y[i])
		out.append(px[i])
		out.append(py[i])
		out.append(heading[i])
		out.append(owner_pid[i])
		out.append(target[i])
		out.append(t_end[i])
		n += 1
	return n


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(live)
	buf.append(free_stack.size())
	buf.append_array(free_stack)
	for i: int in hi:
		if alive[i] == 0:
			continue
		buf.append(i)
		buf.append(serial[i])
		buf.append(kind[i])
		buf.append(pdef[i])
		buf.append(wh[i])
		buf.append(wpn[i])
		buf.append(owner_pid[i])
		buf.append(owner_id[i])
		buf.append(owner_team[i])
		buf.append(x[i])
		buf.append(y[i])
		buf.append(px[i])
		buf.append(py[i])
		buf.append(sx[i])
		buf.append(sy[i])
		buf.append(ex[i])
		buf.append(ey[i])
		buf.append(vx[i])
		buf.append(vy[i])
		buf.append(heading[i])
		buf.append(speed[i])
		buf.append(t0[i])
		buf.append(t_end[i])
		buf.append(flight[i])
		buf.append(target[i])
		buf.append(dmg[i])
		buf.append(dmg_bp[i])
		buf.append(dmg_tmp[i])
		buf.append(flags[i])
		buf.append(pflags[i])
		buf.append(est[i])
		buf.append(aux0[i])
		buf.append(aux1[i])
		buf.append(hit_r[i])
		buf.append(turn[i])


# ---------------------------------------------------------------------------------------------- pure geometry
## Swept segment (x0,y0)->(x1,y1) versus circle (tx,ty,r) (combat 5.4.8). true on hit; `out` = closest point.
static func swept_hit(x0: int, y0: int, x1: int, y1: int, tx: int, ty: int, r: int, out: PackedInt32Array) -> bool:
	var sxx: int = x1 - x0
	var syy: int = y1 - y0
	var len2: int = sxx * sxx + syy * syy
	var cx: int = x0
	var cy: int = y0
	if len2 > 0:
		var tn: int = clampi((tx - x0) * sxx + (ty - y0) * syy, 0, len2)
		cx = x0 + sxx * tn / len2
		cy = y0 + syy * tn / len2
	out[0] = cx
	out[1] = cy
	var dx: int = tx - cx
	var dy: int = ty - cy
	return dx * dx + dy * dy <= r * r


## Arc flight time (combat 5.4.4): ceil_div(dist, speed) clamped.
static func arc_flight(dist: int, spd: int, min_f: int, max_f: int) -> int:
	return clampi(Fp.ceil_div(dist, maxi(spd, 1)), min_f, max_f)


## Scatter radius at distance `d` (combat 5.4.4).
static func scatter_radius(sc_min: int, sc_max: int, d: int, range_max: int) -> int:
	return sc_min + (sc_max - sc_min) * mini(d, range_max) / maxi(range_max, 1)


## Uniform-in-disc sample radius from a 16-bit draw `u`.
static func disc_radius(sc: int, u: int) -> int:
	return (sc * Fp.isqrt(u << 16)) >> 16


## Splash falloff in bp (combat 5.5): 10000 inside `inner`, `edge` at/after `outer`, linear between.
static func falloff_bp(d: int, inner: int, outer: int, edge: int) -> int:
	if d <= inner:
		return 10000
	if d >= outer:
		return edge
	return 10000 - (10000 - edge) * (d - inner) / (outer - inner)


# ---------------------------------------------------------------------------------------------- pool
## Slot for a new projectile or -1 when refused. Non-strategic spawns stop PROJ_STRATEGIC_RESERVE before the cap.
func alloc(strategic: bool, world: SimWorld, kind_: int, pid: int) -> int:
	var limit: int = CAP if strategic else CAP - SimCombatConsts.PROJ_STRATEGIC_RESERVE
	if live >= limit or free_stack.is_empty():
		return -1
	var s: int = free_stack[free_stack.size() - 1]
	free_stack.resize(free_stack.size() - 1)
	alive[s] = 1
	live += 1
	if s + 1 > hi:
		hi = s + 1
	serial[s] = world.alloc_proj_id()
	kind[s] = kind_
	owner_pid[s] = pid
	owner_team[s] = world.team_of(pid)
	pdef[s] = -1
	wh[s] = 0
	wpn[s] = -1
	owner_id[s] = -1
	px[s] = 0
	py[s] = 0
	vx[s] = 0
	vy[s] = 0
	heading[s] = 0
	speed[s] = 0
	flight[s] = 0
	target[s] = -1
	dmg[s] = 0
	dmg_bp[s] = 10000
	dmg_tmp[s] = 0
	flags[s] = 0
	pflags[s] = 0
	est[s] = 0
	aux0[s] = 0
	aux1[s] = 0
	hit_r[s] = 64
	turn[s] = 0
	return s


func _release(s: int) -> void:
	alive[s] = 0
	live -= 1
	free_stack.append(s)


## Ends slot `s` without detonation: EV_PROJ_END, inflight estimate returned.
func end_proj(world: SimWorld, s: int, reason: int, by: int = -1) -> void:
	_return_est(world, s)
	world.emit(SimCombatConsts.EV_PROJ_END, x[s], y[s], serial[s], reason, by)
	_release(s)


func _return_est(world: SimWorld, s: int) -> void:
	if est[s] == 0:
		return
	var t: SimEntity = world.get_entity(target[s])
	if t != null and t.combat != null:
		t.combat.inflight_est = maxi(t.combat.inflight_est - est[s], 0)
	est[s] = 0


func _warhead(world: SimWorld, s: int) -> SimCombatWarhead:
	return warhead_of(world, owner_pid[s], wh[s])


static func warhead_of(world: SimWorld, pid: int, ref: int) -> SimCombatWarhead:
	var cs: SimCombatSystem = world.combat
	if (ref & NEUTRAL_REF) != 0:
		return cs.neutral_tables.warheads[ref & (NEUTRAL_REF - 1)]
	return cs.tables_of(pid).warheads[ref]


# ---------------------------------------------------------------------------------------------- launch (P4)
## Fires a projectile weapon. `t` null = ground point (tx,ty). Returns 0 projectile spawned, 1 resolved instantly
## (pool-cap fallback). RNG draws (combat 8): bullet spread 1 iff spread > 0; arc / bomb scatter 2 iff radius > 0.
func launch(world: SimWorld, e: SimEntity, cd: SimCombatDef, m: int, t: SimEntity, tx: int, ty: int, mx: int, my: int,
		base: int, range_eff: int, spd: int, forced: bool, wh_ref: int, wh_: SimCombatWarhead, tmp_bp: int) -> int:
	var cs: SimCombatSystem = world.combat
	var pk: int = cd.pf(m, SimWeaponProfile.PF_KIND)
	var pfl: int = cd.pf(m, SimWeaponProfile.PF_FLAGS)
	var ifl: int = 0
	if (e.combat.cflags & SimCombatConsts.CF_ENEMY_ONLY) != 0:
		ifl |= SimCombatConsts.PI_ENEMY_ONLY
	if forced:
		ifl |= SimCombatConsts.PI_FORCED
	if e.layer != SimCombatConsts.LAYER_GROUND:
		ifl |= PI_AIR_SHOOTER
	if wh_.packet == 1:
		ifl |= SimCombatConsts.PI_PACKET
	if wh_.suppressive == 1:
		ifl |= SimCombatConsts.PI_SUPPRESSIVE
	var spd_u: int = maxi(spd, 1)
	var tv_x: int = t.vx if t != null else 0
	var tv_y: int = t.vy if t != null else 0
	var rng: SimRng = world.rng
	var lead: int = cd.pf(m, SimWeaponProfile.PF_LEAD_BP)
	# ---- aim point and flight per kind
	var aim_x: int = tx
	var aim_y: int = ty
	var flight_t: int = 0
	var h: int = 0
	var end_x: int = tx
	var end_y: int = ty
	var vel_x: int = 0
	var vel_y: int = 0
	match pk:
		SimCombatConsts.PK_BULLET, SimCombatConsts.PK_MISSILE:
			var t1: int = Fp.ceil_div(Fp.dist(tx - mx, ty - my), spd_u)
			if t != null and lead != 0:
				aim_x = tx + tv_x * t1 * lead / 10000
				aim_y = ty + tv_y * t1 * lead / 10000
			h = Fp.atan2(aim_y - my, aim_x - mx) if (aim_x != mx or aim_y != my) else e.facing
			if pk == SimCombatConsts.PK_BULLET:
				var spread: int = cd.pf(m, SimWeaponProfile.PF_SPREAD)
				if spread > 0:
					h = (h + rng.next_int(2 * spread + 1) - spread) & Fp.ANGLE_MASK
				vel_x = Fp.step_x(h, spd_u)
				vel_y = Fp.step_y(h, spd_u)
			flight_t = Fp.ceil_div(Fp.dist(aim_x - mx, aim_y - my), spd_u)
			end_x = aim_x
			end_y = aim_y
		SimCombatConsts.PK_ARC:
			var d0: int = Fp.dist(tx - mx, ty - my)
			var tt: int = Fp.ceil_div(d0, spd_u)
			aim_x = tx + tv_x * tt * lead / 10000
			aim_y = ty + tv_y * tt * lead / 10000
			tt = Fp.ceil_div(Fp.dist(aim_x - mx, aim_y - my), spd_u)
			aim_x = tx + tv_x * tt * lead / 10000
			aim_y = ty + tv_y * tt * lead / 10000
			end_x = aim_x
			end_y = aim_y
			var sc: int = scatter_radius(cd.pf(m, SimWeaponProfile.PF_SC_MIN), cd.pf(m, SimWeaponProfile.PF_SC_MAX), Fp.dist(aim_x - mx, aim_y - my), range_eff)
			if sc > 0:
				var u: int = rng.next_int(65536)
				var a: int = rng.next_int(4096)
				var r: int = disc_radius(sc, u)
				end_x += (r * Fp.cos(a)) >> 16
				end_y += (r * Fp.sin(a)) >> 16
			flight_t = arc_flight(Fp.dist(end_x - mx, end_y - my), spd_u, cd.pf(m, SimWeaponProfile.PF_MIN_FLIGHT), cd.pf(m, SimWeaponProfile.PF_MAX_FLIGHT))
			h = Fp.atan2(end_y - my, end_x - mx) if (end_x != mx or end_y != my) else e.facing
		SimCombatConsts.PK_BOMB:
			flight_t = SimWeaponProfile.FALL_TICKS
			end_x = mx + e.vx * flight_t
			end_y = my + e.vy * flight_t
			var scb: int = scatter_radius(cd.pf(m, SimWeaponProfile.PF_SC_MIN), cd.pf(m, SimWeaponProfile.PF_SC_MAX), 0, 1)
			if scb > 0:
				var ub: int = rng.next_int(65536)
				var ab: int = rng.next_int(4096)
				var rb: int = disc_radius(scb, ub)
				end_x += (rb * Fp.cos(ab)) >> 16
				end_y += (rb * Fp.sin(ab)) >> 16
			h = e.facing
		_:
			return 1
	var use_target: bool = t != null
	# ---- pool caps (combat 5.4.9): count based, identical on every client
	var hard: bool = live >= CAP - SimCombatConsts.PROJ_STRATEGIC_RESERVE
	var soft: bool = live >= SimCombatConsts.PROJ_SOFT_CAP and (pk == SimCombatConsts.PK_BULLET or pk == SimCombatConsts.PK_MISSILE) and wh_.splash_r == 0
	if hard or soft:
		var dir: int = Fp.atan2(ty - my, tx - mx)
		var ix: int = tx if soft else end_x
		var iy: int = ty if soft else end_y
		detonate(world, wh_, ix, iy, t.id if (use_target and (soft or pk == SimCombatConsts.PK_BULLET or pk == SimCombatConsts.PK_MISSILE)) else -1,
			base, 10000, tmp_bp, e.owner, e.id, ifl, dir, -1, false)
		return 1
	var s: int = alloc(false, world, pk, e.owner)
	if s < 0:
		return 1
	var tick: int = world.tick
	pdef[s] = cd.slots[cd.slot_of_mount(m)].arch
	wh[s] = wh_ref
	wpn[s] = cd.slot_of_mount(m)
	owner_id[s] = e.id
	x[s] = mx
	y[s] = my
	px[s] = mx
	py[s] = my
	sx[s] = mx
	sy[s] = my
	ex[s] = end_x
	ey[s] = end_y
	vx[s] = vel_x
	vy[s] = vel_y
	heading[s] = h
	speed[s] = spd_u
	t0[s] = tick
	flight[s] = flight_t
	target[s] = t.id if use_target else -1
	dmg[s] = base
	dmg_bp[s] = 10000
	dmg_tmp[s] = tmp_bp
	flags[s] = ifl
	pflags[s] = pfl
	hit_r[s] = cd.pf(m, SimWeaponProfile.PF_HIT_R)
	turn[s] = cd.pf(m, SimWeaponProfile.PF_TURN)
	match pk:
		SimCombatConsts.PK_BULLET:
			t_end[s] = tick + flight_t + 2
		SimCombatConsts.PK_MISSILE:
			aux0[s] = cd.pf(m, SimWeaponProfile.PF_HOMING_DELAY)
			aux1[s] = cd.pf(m, SimWeaponProfile.PF_LAUNCH_DELAY)
			t_end[s] = tick + maxi(cd.pf(m, SimWeaponProfile.PF_LIFE), 2 * flight_t + SPAWN_MISSILE_GRACE)
		_:
			t_end[s] = tick + flight_t
	if use_target and t.combat != null:
		var td: SimCombatDef = cs.def_for(world, t)
		var ev: int = SimDamage.mul(base, cs.matrix(wh_.dtype, td.armor if td != null else 0))
		est[s] = ev
		t.combat.inflight_est += ev
	cs.counters[SimCombatSystem.CNT_PROJ] += 1
	world.emit(SimCombatConsts.EV_PROJ_SPAWN, mx, my, serial[s], pdef[s], e.owner | (pk << 4) | (flight_t << 16), target[s], end_x, end_y)
	return 0


# ---------------------------------------------------------------------------------------------- remote spawns (3.5)
## Projectile without a shooter entity. `proj_idx` is a PK_* code: PK_STRIKE (default) detonates at (tx,ty) exactly
## `delay_ticks` from now; PK_ARC launches after the delay from (ox,oy) and flies to (tx,ty). `wh_idx` indexes the owner's
## warhead table. Uses the strategic reserve; returns the serial or -1 when even the reserve is exhausted.
func spawn_remote(world: SimWorld, owner_pid_: int, owner_id_: int, proj_idx: int, wh_idx: int, ox: int, oy: int, tx: int, ty: int,
		delay_ticks: int, dmg_bp_: int, inst_flags: int) -> int:
	var k: int = proj_idx if (proj_idx == SimCombatConsts.PK_ARC or proj_idx == SimCombatConsts.PK_BOMB) else SimCombatConsts.PK_STRIKE
	var s: int = alloc(true, world, k, owner_pid_)
	if s < 0:
		return -1
	var tick: int = world.tick
	var w: SimCombatWarhead = warhead_of(world, owner_pid_, wh_idx)
	pdef[s] = proj_idx
	wh[s] = wh_idx
	owner_id[s] = owner_id_
	x[s] = ox
	y[s] = oy
	px[s] = ox
	py[s] = oy
	sx[s] = ox
	sy[s] = oy
	ex[s] = tx
	ey[s] = ty
	dmg[s] = w.damage
	dmg_bp[s] = dmg_bp_
	flags[s] = inst_flags | SimCombatConsts.PI_REMOTE
	pflags[s] = SimCombatConsts.PF_STRATEGIC
	if k == SimCombatConsts.PK_STRIKE:
		t0[s] = tick
		t_end[s] = tick + maxi(delay_ticks, 0)
		flight[s] = maxi(delay_ticks, 0)
		x[s] = tx
		y[s] = ty
	else:
		var f: int = arc_flight(Fp.dist(tx - ox, ty - oy), REMOTE_ARC_SPEED, 10, 400)
		t0[s] = tick + maxi(delay_ticks, 0)
		flight[s] = f
		t_end[s] = t0[s] + f
		speed[s] = REMOTE_ARC_SPEED
		heading[s] = Fp.atan2(ty - oy, tx - ox)
		if (inst_flags & SimCombatConsts.PI_PACKET) == 0 and w.packet == 0:
			pflags[s] |= SimCombatConsts.PF_ZONE_INTERCEPTABLE
	world.emit(SimCombatConsts.EV_PROJ_SPAWN, ox, oy, serial[s], proj_idx, owner_pid_ | (k << 4) | (flight[s] << 16), -1, tx, ty)
	return serial[s]


## Helios-style swept line (combat 5.4.7): the hot spot travels A -> B in `duration_ticks`, damage every `dot` ticks.
func spawn_sweep(world: SimWorld, owner_pid_: int, owner_id_: int, proj_idx: int, wh_idx: int, ax: int, ay: int, bx: int, by: int,
		delay_ticks: int, duration_ticks: int, width: int = 3072, spot_len: int = 3072, dot: int = 5) -> int:
	var s: int = alloc(true, world, SimCombatConsts.PK_SWEEP, owner_pid_)
	if s < 0:
		return -1
	var tick: int = world.tick
	var w: SimCombatWarhead = warhead_of(world, owner_pid_, wh_idx)
	pdef[s] = proj_idx
	wh[s] = wh_idx
	owner_id[s] = owner_id_
	x[s] = ax
	y[s] = ay
	px[s] = ax
	py[s] = ay
	sx[s] = ax
	sy[s] = ay
	ex[s] = bx
	ey[s] = by
	t0[s] = tick + maxi(delay_ticks, 0)
	flight[s] = maxi(duration_ticks, 1)
	t_end[s] = t0[s] + flight[s]
	dmg[s] = w.damage
	flags[s] = SimCombatConsts.PI_REMOTE
	pflags[s] = SimCombatConsts.PF_STRATEGIC
	aux0[s] = maxi(dot, 1)
	aux1[s] = t0[s] + maxi(dot, 1)
	hit_r[s] = width
	turn[s] = spot_len
	world.emit(SimCombatConsts.EV_SWEEP, ax, ay, serial[s], w.idx, flight[s] | (maxi(delay_ticks, 0) << 16), width, bx, by)
	return serial[s]


# ---------------------------------------------------------------------------------------------- P5
func update(world: SimWorld) -> void:
	var tick: int = world.tick
	var n: int = hi
	for s: int in n:
		if alive[s] == 0:
			continue
		match kind[s]:
			SimCombatConsts.PK_BULLET:
				_step_bullet(world, s, tick)
			SimCombatConsts.PK_MISSILE:
				_step_missile(world, s, tick)
			SimCombatConsts.PK_ARC, SimCombatConsts.PK_BOMB:
				_step_arc(world, s, tick)
			SimCombatConsts.PK_STRIKE:
				if tick >= t_end[s]:
					_detonate_slot(world, s, ex[s], ey[s], -1)
			SimCombatConsts.PK_SWEEP:
				_step_sweep(world, s, tick)
			_:
				_return_est(world, s)
				_release(s)
	while hi > 0 and alive[hi - 1] == 0:
		hi -= 1


func _target_alive(world: SimWorld, s: int) -> SimEntity:
	if target[s] < 0:
		return null
	var t: SimEntity = world.get_entity(target[s])
	if t == null or (t.flags & SimFlags.F_GONE) != 0:
		return null
	return t


func _step_bullet(world: SimWorld, s: int, tick: int) -> void:
	if t0[s] >= tick:
		return
	var x0: int = x[s]
	var y0: int = y[s]
	var x1: int = x0 + vx[s]
	var y1: int = y0 + vy[s]
	px[s] = x0
	py[s] = y0
	x[s] = x1
	y[s] = y1
	var t: SimEntity = _target_alive(world, s)
	if t != null and (t.flags & SimFlags.F_INSIDE) == 0:
		if swept_hit(x0, y0, x1, y1, t.x, t.y, t.radius + hit_r[s], _hit):
			_detonate_slot(world, s, _hit[0], _hit[1], t.id)
			return
	if target[s] < 0 and tick - t0[s] >= flight[s]:
		# a shot at a ground point (force-fire) lands exactly there
		var wg: SimCombatWarhead = _warhead(world, s)
		if wg.splash_r > 0 or (flags[s] & SimCombatConsts.PI_FORCED) != 0:
			_detonate_slot(world, s, ex[s], ey[s], -1)
		else:
			end_proj(world, s, 0)
		return
	if tick >= t_end[s]:
		var w: SimCombatWarhead = _warhead(world, s)
		if w.splash_r > 0 or (pflags[s] & SimCombatConsts.PF_AIRBURST_ON_EXPIRE) != 0 or (flags[s] & SimCombatConsts.PI_FORCED) != 0:
			_detonate_slot(world, s, x1, y1, -1)
		else:
			end_proj(world, s, 0)


func _step_missile(world: SimWorld, s: int, tick: int) -> void:
	if t0[s] >= tick:
		return
	var x0: int = x[s]
	var y0: int = y[s]
	px[s] = x0
	py[s] = y0
	if aux1[s] > 0:
		aux1[s] -= 1  # pop-up at the muzzle
	else:
		var t: SimEntity = _target_alive(world, s)
		if aux0[s] > 0:
			aux0[s] -= 1
		elif t != null and (t.flags & SimFlags.F_INSIDE) == 0:
			var desired: int = Fp.atan2(t.y - y0, t.x - x0)
			heading[s] = (heading[s] + clampi(SimCombatConsts.wrap_signed(desired - heading[s]), -turn[s], turn[s])) & Fp.ANGLE_MASK
		vx[s] = Fp.step_x(heading[s], speed[s])
		vy[s] = Fp.step_y(heading[s], speed[s])
		x[s] = x0 + vx[s]
		y[s] = y0 + vy[s]
	var x1: int = x[s]
	var y1: int = y[s]
	if _try_aps(world, s, tick):
		return
	if _try_zone(world, s, x0, y0, x1, y1):
		return
	var tg: SimEntity = _target_alive(world, s)
	if tg != null and (tg.flags & SimFlags.F_INSIDE) == 0:
		if swept_hit(x0, y0, x1, y1, tg.x, tg.y, tg.radius + hit_r[s], _hit):
			_detonate_slot(world, s, _hit[0], _hit[1], tg.id)
			return
	if tick >= t_end[s]:
		if (pflags[s] & SimCombatConsts.PF_AIRBURST_ON_EXPIRE) != 0:
			_detonate_slot(world, s, x1, y1, -1)
		else:
			end_proj(world, s, 0)


func _step_arc(world: SimWorld, s: int, tick: int) -> void:
	if t0[s] >= tick:
		return
	var k: int = tick - t0[s]
	var f: int = maxi(flight[s], 1)
	var x0: int = x[s]
	var y0: int = y[s]
	px[s] = x0
	py[s] = y0
	if k >= f:
		x[s] = ex[s]
		y[s] = ey[s]
	else:
		x[s] = sx[s] + (ex[s] - sx[s]) * k / f
		y[s] = sy[s] + (ey[s] - sy[s]) * k / f
	if _try_aps(world, s, tick):
		return
	if _try_zone(world, s, x0, y0, x[s], y[s]):
		return
	if k >= f:
		var direct: int = -1
		var w: SimCombatWarhead = _warhead(world, s)
		if w.splash_r == 0:
			var t: SimEntity = _target_alive(world, s)
			if t != null:
				var dx: int = t.x - ex[s]
				var dy: int = t.y - ey[s]
				var rr: int = t.radius + hit_r[s]
				if dx * dx + dy * dy <= rr * rr:
					direct = t.id
		_detonate_slot(world, s, ex[s], ey[s], direct)


## Point defence (combat 5.7): one projectile per interceptor per cooldown.
func _try_aps(world: SimWorld, s: int, tick: int) -> bool:
	if (pflags[s] & SimCombatConsts.PF_APS_INTERCEPTABLE) == 0:
		return false
	var t: SimEntity = _target_alive(world, s)
	if t == null or t.combat == null or t.combat.aps_next.is_empty():
		return false
	if world.rel(owner_pid[s], t.owner) != SimCombatConsts.REL_ENEMY:
		return false
	var cs: SimCombatSystem = world.combat
	var cd: SimCombatDef = cs.def_for(world, t)
	if cd == null:
		return false
	var dx: int = x[s] - t.x
	var dy: int = y[s] - t.y
	var rr: int = cd.aps_radius + t.radius
	if dx * dx + dy * dy > rr * rr:
		return false
	var aps: PackedInt32Array = t.combat.aps_next
	for i: int in aps.size():
		if aps[i] <= tick:
			aps[i] = tick + cd.aps_cooldown
			t.combat.aps_next = aps
			world.emit(SimCombatConsts.EV_INTERCEPT, x[s], y[s], serial[s], t.id, 0, aps[i], owner_pid[s], t.owner)
			end_proj(world, s, 1, t.id)
			return true
	return false


## Trident ordinary charges (combat 5.7): asks the zone system once per interceptable projectile per tick.
func _try_zone(world: SimWorld, s: int, x0: int, y0: int, x1: int, y1: int) -> bool:
	if (pflags[s] & SimCombatConsts.PF_ZONE_INTERCEPTABLE) == 0 or (flags[s] & SimCombatConsts.PI_PACKET) != 0:
		return false
	if not world.zones.has_method("intercept_ordinary"):
		return false
	var zid: int = int(world.zones.call("intercept_ordinary", world, owner_team[s], x0, y0, x1, y1, sx[s], sy[s], pflags[s]))
	if zid < 0:
		return false
	world.emit(SimCombatConsts.EV_INTERCEPT, x1, y1, serial[s], zid, 1, 0, owner_pid[s], -1)
	end_proj(world, s, 2, zid)
	return true


func _zone_packet(world: SimWorld, team: int, cx: int, cy: int) -> int:
	if not world.zones.has_method("intercept_packet"):
		return 0
	return int(world.zones.call("intercept_packet", world, team, cx, cy))


func _detonate_slot(world: SimWorld, s: int, cx: int, cy: int, direct_id: int) -> void:
	var w: SimCombatWarhead = _warhead(world, s)
	var dir: int = heading[s] if (kind[s] == SimCombatConsts.PK_BULLET or kind[s] == SimCombatConsts.PK_MISSILE) else -1
	_return_est(world, s)
	var ser: int = serial[s]
	var op: int = owner_pid[s]
	var oid: int = owner_id[s]
	var d: int = dmg[s]
	var bp: int = dmg_bp[s]
	var tmp: int = dmg_tmp[s]
	var fl: int = flags[s]
	_release(s)
	detonate(world, w, cx, cy, direct_id, d, bp, tmp, op, oid, fl, dir, ser, true)


# ---------------------------------------------------------------------------------------------- detonation (5.5)
## Applies `wh_` at (cx,cy): packet reduction, victim set, falloff, per-victim SimDamage.deal. `dir_bat` = travel
## direction of a direct projectile (-1: derive from the impact point). Returns the total damage enqueued.
func detonate(world: SimWorld, wh_: SimCombatWarhead, cx: int, cy: int, direct_id: int, base: int, static_bp: int, tmp_bp: int,
		pid: int, oid: int, iflags: int, dir_bat: int, ser: int, emit_impact: bool) -> int:
	var team: int = world.team_of(pid)
	var pkt_bp: int = 0
	var reduced: int = 0
	if wh_.packet == 1 or (iflags & SimCombatConsts.PI_PACKET) != 0:
		pkt_bp = _zone_packet(world, team, cx, cy)
		if pkt_bp > 0:
			reduced = 1
			world.emit(SimCombatConsts.EV_INTERCEPT, cx, cy, -1, -1, 2, 0, pid, -1)
	var enemy_only: bool = wh_.friendly_fire == 0 or (iflags & SimCombatConsts.PI_ENEMY_ONLY) != 0
	var dflags: int = 0
	if (iflags & SimCombatConsts.PI_FORCED) != 0:
		dflags |= SimCombatConsts.DF_FORCED
	if (iflags & SimCombatConsts.PI_PACKET) != 0:
		dflags |= SimCombatConsts.DF_PACKET
	if (iflags & SimCombatConsts.PI_CHAIN) != 0:
		dflags |= SimCombatConsts.DF_CHAIN
	if (iflags & SimCombatConsts.PI_SUPPRESSIVE) != 0:
		dflags |= SimCombatConsts.DF_SUPPRESSIVE
	var atk_ground: bool = (iflags & PI_AIR_SHOOTER) == 0
	var dc_base: int = SimCombatConsts.DC_DIRECT
	if wh_.delivery == SimCombatConsts.DELIV_INDIRECT:
		dc_base = SimCombatConsts.DC_INDIRECT
	elif wh_.delivery == SimCombatConsts.DELIV_STRATEGIC:
		dc_base = SimCombatConsts.DC_STRATEGIC
	var total: int = 0
	var victims: int = 0
	var hit_kind: int = 0
	var order: PackedInt32Array = PackedInt32Array()
	if direct_id > 0:
		order.append(direct_id)
	if wh_.splash_r > 0:
		world.query_circle(cx, cy, wh_.splash_r + SimCombatConsts.SPLASH_QUERY_MARGIN, _buf, SimTag.ALIVE, SimTag.kind_bit(SimEntity.Kind.ZONE))
		for id: int in _buf:
			if id != direct_id:
				order.append(id)
	for id: int in order:
		var v: SimEntity = world.get_entity(id)
		if v == null or v.combat == null or (v.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or v.container_id >= 0:
			continue
		if (v.combat.cflags & SimCombatConsts.CF_UNTARGETABLE) != 0:
			continue
		if ((wh_.layer_mask >> v.layer) & 1) == 0:
			continue
		var is_direct: bool = id == direct_id
		if world.rel(pid, v.owner) != SimCombatConsts.REL_ENEMY:
			if (iflags & SimCombatConsts.PI_ENEMY_ONLY) != 0 or (enemy_only and not is_direct):
				continue
		var f: int = 10000
		var dc: int = dc_base
		var from_bat: int = 0
		if is_direct:
			from_bat = SimCombatConsts.wrap_signed(dir_bat + Fp.ANGLE_HALF) if dir_bat >= 0 else Fp.atan2(cy - v.y, cx - v.x)
		else:
			var d: int = maxi(Fp.dist(v.x - cx, v.y - cy) - v.radius, 0)
			if d > wh_.splash_r or d < wh_.splash_min_r:
				continue
			f = falloff_bp(d, wh_.splash_inner, wh_.splash_r, wh_.splash_edge_bp)
			dc |= SimCombatConsts.DC_SPLASH
			from_bat = Fp.atan2(cy - v.y, cx - v.x)
		total += SimDamage.deal(world, v, wh_, base, dc, dflags, oid, pid, atk_ground, static_bp, tmp_bp, f, from_bat, pkt_bp, cx, cy)
		victims += 1
		if is_direct:
			hit_kind = _hit_kind(v)
	if emit_impact:
		world.emit(SimCombatConsts.EV_IMPACT, cx, cy, wh_.idx, ser, hit_kind | (reduced << 4) | ((1 if victims == 0 else 0) << 5), wh_.splash_r, total, pid | (victims << 4))
	world.combat.counters[SimCombatSystem.CNT_IMPACTS] += 1
	return total


static func _hit_kind(v: SimEntity) -> int:
	if v.kind == SimEntity.Kind.STRUCTURE:
		return 2
	if v.kind == SimEntity.Kind.WRECK:
		return 6
	match v.layer:
		SimCombatConsts.LAYER_AIR:
			return 3
		SimCombatConsts.LAYER_SURFACE:
			return 4
		SimCombatConsts.LAYER_UNDERWATER:
			return 5
	return 1


# ---------------------------------------------------------------------------------------------- sweeps (5.4.7)
func _step_sweep(world: SimWorld, s: int, tick: int) -> void:
	if tick < t0[s]:
		return
	var k: int = mini(tick - t0[s], flight[s])
	var ax: int = sx[s]
	var ay: int = sy[s]
	var dxl: int = ex[s] - ax
	var dyl: int = ey[s] - ay
	var cx: int = ax + dxl * k / flight[s]
	var cy: int = ay + dyl * k / flight[s]
	px[s] = x[s]
	py[s] = y[s]
	x[s] = cx
	y[s] = cy
	if tick >= aux1[s]:
		aux1[s] += aux0[s]
		_sweep_dot(world, s, cx, cy, dxl, dyl)
	if tick - t0[s] >= flight[s]:
		end_proj(world, s, 4)


func _sweep_dot(world: SimWorld, s: int, cx: int, cy: int, dxl: int, dyl: int) -> void:
	var w: SimCombatWarhead = _warhead(world, s)
	var len_: int = Fp.dist(dxl, dyl)
	var ux: int = Fp.Q16
	var uy: int = 0
	if len_ > 0:
		ux = (dxl << 16) / len_
		uy = (dyl << 16) / len_
	var half_len: int = turn[s] / 2
	var half_w: int = hit_r[s] / 2
	world.query_circle(cx, cy, half_len + half_w + SimCombatConsts.SPLASH_QUERY_MARGIN, _buf, SimTag.ALIVE, SimTag.kind_bit(SimEntity.Kind.ZONE))
	var pid: int = owner_pid[s]
	var enemy_only: bool = w.friendly_fire == 0 or (flags[s] & SimCombatConsts.PI_ENEMY_ONLY) != 0
	for id: int in _buf:
		var v: SimEntity = world.get_entity(id)
		if v == null or v.combat == null or (v.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or v.container_id >= 0:
			continue
		if (v.combat.cflags & SimCombatConsts.CF_UNTARGETABLE) != 0 or ((w.layer_mask >> v.layer) & 1) == 0:
			continue
		if enemy_only and world.rel(pid, v.owner) != SimCombatConsts.REL_ENEMY:
			continue
		var along: int = ((v.x - cx) * ux + (v.y - cy) * uy) >> 16
		var across: int = ((v.x - cx) * (-uy) + (v.y - cy) * ux) >> 16
		if absi(along) > half_len + v.radius or absi(across) > half_w + v.radius:
			continue
		SimDamage.deal(world, v, w, dmg[s], SimCombatConsts.DC_DIRECT, 0, owner_id[s], pid, true, dmg_bp[s], dmg_tmp[s], 10000,
			Fp.atan2(cy - v.y, cx - v.x), 0, cx, cy)
