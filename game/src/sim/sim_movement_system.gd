class_name SimMovementSystem
extends SimSystem
## Pipeline stage 6 (terrain_movement 3.10.1 / 3.11 / 5.4): path service drain, separation grids and the three
## movement phases for ground, naval and submerged units. Phase A (intent, own state + map only), phase B
## (separation from the tick-start snapshot), phase C (apply in ascending id: terrain rule, medium switch, flag
## mirrors), then the strided maintenance (stuck / validity / follow). Aircraft, formations, order handlers,
## cargo approaches (task TM-14, later) are not here. Aircraft are flown by SimAirMove after the ground phases; the
## order handlers (SimOrderMove / SimOrderAir) are registered in init_world. The facade other domains call is `SimMovement`.

var path: SimPathService = null
var sep: SimSeparation = null
var prof: SimMoveProfiles = null

var ready: bool = false
var _movers: PackedInt32Array = PackedInt32Array()  ## ids with a move slot, ascending
var _ents: Array[SimEntity] = []
var _n: int = 0
var _sx: PackedInt32Array = PackedInt32Array()
var _sy: PackedInt32Array = PackedInt32Array()
var _pd: PackedInt32Array = PackedInt32Array()  ## separation displacement, 2 ints per entry
var _w: int = 0
var _h: int = 0
var _max_x: int = 0
var _max_y: int = 0
var _terrain: PackedByteArray = PackedByteArray()
var _kind: PackedByteArray = PackedByteArray()
var _wg: Array[PackedByteArray] = []
var _nav: MapNav = null
var _tt: MapTerrain = null
var _sin: PackedInt32Array = FpTables.SIN_Q16
var _sp: PackedInt32Array = PackedInt32Array()  ## [mc * 8 + TerrainKind] -> speed bp
# adapters (abilities / combat), resolved once in init_world; any may be missing
var _has_speed: bool = false
var _has_immob: bool = false
var _has_lock: bool = false
var _has_pack: bool = false
var _has_supp: bool = false
var _c_speed: Callable = Callable()
var _c_immob: Callable = Callable()
var _c_lock: Callable = Callable()
var _c_pack: Callable = Callable()
var _c_supp: Callable = Callable()
const SLOT_CUT_DIST: int = 6144
var side_tick: int = -1
var side_cnt: int = 0
var _air: Array[SimEntity] = []  ## airborne aircraft of this tick (ascending id)
var _avoid_buf: PackedInt32Array = PackedInt32Array()
var _qbuf: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	stage_no = 6


func system_name() -> String:
	return "movement"


static func of(world: SimWorld) -> SimMovementSystem:
	return world.movement


func init_world(world: SimWorld) -> void:
	if not _mirrors_ok():
		Log.error("movement", "enum mirrors differ from DefEnums / SimEntity: movement disabled")
		return
	var map: MapData = world.map
	prof = SimMoveProfiles.build(world.data, map.tt)
	_tt = map.tt
	_nav = map.nav
	if _nav.graphs.is_empty():
		_nav.prepare_all()
	path = SimPathService.new(map)
	sep = SimSeparation.new(map.w, map.h)
	_w = map.w
	_h = map.h
	_max_x = map.w * SimMoveConfig.CELL - 1
	_max_y = map.h * SimMoveConfig.CELL - 1
	_terrain = map.terrain
	_kind = map.kind
	_sp.resize(MapTerrain.MC_COUNT * MapTerrain.TK_COUNT)
	for mc: int in MapTerrain.MC_COUNT:
		for ter: int in MapTerrain.COUNT:
			_sp[mc * MapTerrain.TK_COUNT + map.tt.kind_of(ter)] = map.tt.speed_bp(mc, ter)
	_wg.clear()
	for np: int in MapTerrain.NP_COUNT:
		_wg.append(_nav.wgt_array(np))
	var ab: Object = world.abilities  # any adapter target may be null (disabled stage) or lack a method
	_has_speed = ab != null and ab.has_method("speed_units")
	_has_immob = ab != null and ab.has_method("is_immobile")
	_has_lock = ab != null and ab.has_method("is_turn_locked")
	_has_pack = ab != null and ab.has_method("request_pack")
	if _has_speed:
		_c_speed = Callable(ab, "speed_units")
	if _has_immob:
		_c_immob = Callable(ab, "is_immobile")
	if _has_lock:
		_c_lock = Callable(ab, "is_turn_locked")
	if _has_pack:
		_c_pack = Callable(ab, "request_pack")
	var cb: Object = world.combat
	_has_supp = cb != null and cb.has_method("suppression_speed_bp")
	if _has_supp:
		_c_supp = Callable(cb, "suppression_speed_bp")
	# order handlers (T_LOAD / T_UNLOAD / T_GARRISON belong to the cargo task TM-14)
	world.orders.register_handler(SimOrder.T_MOVE, SimOrderMove.new(SimOrder.T_MOVE))
	world.orders.register_handler(SimOrder.T_PATROL, SimOrderMove.new(SimOrder.T_PATROL))
	world.orders.register_handler(SimOrder.T_FOLLOW, SimOrderMove.new(SimOrder.T_FOLLOW))
	world.orders.register_handler(SimOrder.T_FACE, SimOrderMove.new(SimOrder.T_FACE))
	world.orders.register_handler(SimOrder.T_LAND, SimOrderAir.new())
	ready = true


func _mirrors_ok() -> bool:
	return MapTerrain.MC_FOOT == DefEnums.MoveClass.FOOT and MapTerrain.MC_AMPHIBIOUS == DefEnums.MoveClass.AMPHIBIOUS \
		and MapTerrain.MC_SUBMERGED == DefEnums.MoveClass.SUBMERGED and MapTerrain.MC_AIR_HOVER == DefEnums.MoveClass.AIR_HOVER \
		and MapTerrain.MC_STATIC == DefEnums.MoveClass.STATIC and MapTerrain.TK_SHALLOW == DefEnums.TerrainKind.SHALLOW \
		and MapTerrain.TK_DEEP == DefEnums.TerrainKind.DEEP and SimEntity.Layer.SURFACE == DefEnums.Layer.SURFACE_WATER \
		and SimEntity.Layer.UNDERWATER == DefEnums.Layer.UNDERWATER and SimEntity.Layer.AIR == DefEnums.Layer.AIR


# ---- hooks ----------------------------------------------------------------------------------------------------

func on_spawn(_world: SimWorld, e: SimEntity) -> void:
	if not ready or e.kind != SimEntity.Kind.UNIT or e.def_idx < 0 or e.def_idx >= prof.count or prof.can_move[e.def_idx] == 0:
		return
	var mv: SimCompMove = SimCompMove.new()
	prof.fill(mv, e.def_idx)
	mv.cell = clampi(e.y >> 10, 0, _h - 1) * _w + clampi(e.x >> 10, 0, _w - 1)
	mv.cell_kind = _kind[mv.cell]
	mv.stuck_x = e.x
	mv.stuck_y = e.y
	if mv.mc == MapTerrain.MC_NAVAL or mv.mc == MapTerrain.MC_SUBMERGED:
		mv.flags |= SimMoveConfig.MF_ON_WATER
	elif mv.mc == MapTerrain.MC_AMPHIBIOUS and (mv.cell_kind == MapTerrain.TK_SHALLOW or mv.cell_kind == MapTerrain.TK_DEEP):
		mv.flags |= SimMoveConfig.MF_ON_WATER
		mv.hl = SimMoveConfig.HL_WATER
	if (mv.flags & SimMoveConfig.MF_ON_WATER) != 0:
		e.flags |= SimFlags.F_ON_WATER
	e.move = mv
	_movers.append(e.id)  # ids are monotonic: stays ascending


func on_dying(_world: SimWorld, e: SimEntity, _cause: int, _killer_id: int, _killer_pid: int) -> void:
	if path != null:
		path.cancel(e.id)


func on_remove(_world: SimWorld, e: SimEntity, _reason: int) -> void:
	if e.move == null:
		return
	if path != null:
		path.cancel(e.id)
	var i: int = _movers.bsearch(e.id)
	if i < _movers.size() and _movers[i] == e.id:
		_movers.remove_at(i)


func on_owner_changed(world: SimWorld, e: SimEntity, _old_owner: int) -> void:
	if e.move != null:
		SimMovement.stop(world, e, false)


func hash_state(_world: SimWorld, buf: PackedInt32Array) -> void:
	if path != null:
		path.state_ints(buf)


func dump_state(world: SimWorld) -> Dictionary:
	var buf: PackedInt32Array = PackedInt32Array()
	hash_state(world, buf)
	return {"movers": _movers.size(), "path_pending": path.pending() if path != null else 0, "state": buf}


## True when the def of this entity produced a move slot with a ground / naval / submerged class.
func is_immobile(_world: SimWorld, e: SimEntity) -> bool:
	if _has_immob:
		return _c_immob.call(e)
	return (e.flags & (SimFlags.F_DEPLOYED | SimFlags.F_DEPLOYING)) != 0


## Top speed in units per tick as the facade reports it (abilities' speed_units or the def's base speed).
func speed_units(e: SimEntity) -> int:
	if _has_speed:
		return _c_speed.call(e)
	return e.move.speed_base if e.move != null else 0


## abilities.request_pack (once per PACK_RETRY_TICKS per unit).
func request_pack(world: SimWorld, e: SimEntity) -> void:
	if not _has_pack:
		return
	var mv: SimCompMove = e.move
	if world.tick - mv.pack_t < SimMoveConfig.PACK_RETRY_TICKS:
		return
	mv.pack_t = world.tick
	_c_pack.call(e)


# ---- the stage ---------------------------------------------------------------------------------------------------

func update(world: SimWorld) -> void:
	if not ready:
		return
	_nav.flush_dirty(SimMoveConfig.NAV_DIRTY_BUDGET)
	path.process(world)
	# collect the movers of this tick (ascending id)
	_ents.resize(0)
	_air.resize(0)
	var by_id: Array[SimEntity] = world.by_id
	for id: int in _movers:
		var e: SimEntity = by_id[id]
		if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE | SimFlags.F_SCRIPTED_MOVE)) != 0:
			continue
		if e.move.mc >= MapTerrain.MC_AIR_FIXED:
			if e.move.air_mode != SimMoveConfig.AM_PARKED:  # parked aircraft cost nothing
				_air.append(e)
			continue
		_ents.append(e)
	var n: int = _ents.size()
	_n = n
	if n == 0:
		_fly(world)
		return
	if _sx.size() < n:
		var cap: int = maxi(n, _sx.size() * 2)
		_sx.resize(cap)
		_sy.resize(cap)
		_pd.resize(cap * 2)
	for np: int in MapTerrain.NP_COUNT:
		_wg[np] = _nav.wgt_array(np)
	sep.refresh_relations(world)
	sep.rebuild(world, _ents, n)
	var tick: int = world.tick
	for i: int in n:
		_phase_a(world, i, _ents[i], _ents[i].move)
	sep.predict(_sx, _sy, n)
	sep.compute_all(n, tick, _pd)
	for i: int in n:
		_phase_c(world, i, _ents[i], _ents[i].move)
	for i: int in n:
		var mvm: SimCompMove = _ents[i].move
		var stm: int = mvm.state
		if stm == SimMoveConfig.MS_MOVING or stm == SimMoveConfig.MS_BLOCKED or stm == SimMoveConfig.MS_WAIT_PATH or mvm.stuck_cnt != 0:
			_maintain(world, i, _ents[i], mvm)
	_fly(world)


## Aircraft phase: flight step of every airborne aircraft in ascending id (no terrain, path or separation).
func _fly(world: SimWorld) -> void:
	for e: SimEntity in _air:
		SimAirMove.step(world, e, e.move)


# ---- phase A ------------------------------------------------------------------------------------------------------

func _phase_a(world: SimWorld, i: int, e: SimEntity, mv: SimCompMove) -> void:
	var st0: int = mv.state
	if mv.spd_q4 == 0 and (st0 == SimMoveConfig.MS_IDLE or st0 == SimMoveConfig.MS_ARRIVED or st0 == SimMoveConfig.MS_NO_PATH):
		# resting unit: nothing to steer; only its separation attributes
		_sx[i] = 0
		_sy[i] = 0
		sep.eact[i] = 0
		if _has_immob:
			sep.eimm[i] = 1 if _c_immob.call(e) else 0
		else:
			sep.eimm[i] = 1 if (e.flags & (SimFlags.F_DEPLOYED | SimFlags.F_DEPLOYING)) != 0 else 0
		mv.vcur_q4 = 0
		return
	var cell: int = (e.y >> 10) * _w + (e.x >> 10)
	mv.cell = cell
	var kind: int = _kind[cell]
	mv.cell_kind = kind
	var speed_upt: int = mv.speed_base
	if _has_speed:
		speed_upt = _c_speed.call(e)
	var imm: bool = ((e.flags & (SimFlags.F_DEPLOYED | SimFlags.F_DEPLOYING)) != 0)
	if _has_immob:
		imm = _c_immob.call(e)
	var tlock: bool = false
	if _has_lock:
		tlock = _c_lock.call(e)
	var kbp: int = _sp[mv.mc * MapTerrain.TK_COUNT + kind]
	var vcur: int
	if kind == MapTerrain.TK_DEEP or kind == MapTerrain.TK_SHALLOW or (e.flags & SimFlags.F_SUPPRESSED) != 0:
		if mv.mc == MapTerrain.MC_AMPHIBIOUS and kind == MapTerrain.TK_DEEP and prof.deep_speed_bp[e.def_idx] > 0:
			kbp = prof.deep_speed_bp[e.def_idx]
		var supp: int = 10000
		if mv.mc == MapTerrain.MC_FOOT and _has_supp and (e.flags & SimFlags.F_SUPPRESSED) != 0:
			supp = _c_supp.call(e)
		vcur = SimSteering.top_speed_q4(speed_upt, kbp, kind == MapTerrain.TK_DEEP or kind == MapTerrain.TK_SHALLOW, prof.water_mult_bp[e.def_idx], supp, mv.speed_cap_q4)
	else:
		vcur = (speed_upt * 16 * kbp + 5000) / 10000
		if mv.speed_cap_q4 > 0 and vcur > mv.speed_cap_q4:
			vcur = mv.speed_cap_q4
	if imm:
		vcur = 0
	mv.vcur_q4 = vcur
	sep.eimm[i] = 1 if imm else 0
	_sx[i] = 0
	_sy[i] = 0
	var st: int = mv.state
	var spd: int = mv.spd_q4
	if st == SimMoveConfig.MS_GLIDE:
		sep.eact[i] = 0
		return
	if st == SimMoveConfig.MS_EVICT:
		sep.eact[i] = 1
		_evict_step(world, i, e, mv, vcur)
		return
	if st == SimMoveConfig.MS_MOVING or st == SimMoveConfig.MS_BLOCKED or st == SimMoveConfig.MS_SIDESTEP:
		sep.eact[i] = 0 if imm else 1
		_steer(world, i, e, mv, vcur, tlock, cell)
		return
	var facing: int = e.facing
	sep.eact[i] = 0
	if st == SimMoveConfig.MS_WAIT_PATH:
		sep.eact[i] = 0 if imm else 1
		mv.wait += 1
		if mv.wait > SimMoveConfig.PATH_WAIT_MAX:
			path.cancel(e.id)
			mv.req_id = 0
			mv.state = SimMoveConfig.MS_NO_PATH
			mv.result = SimMoveConfig.RS_NO_PATH
			mv.goal_kind = SimMoveConfig.GK_NONE
		elif mv.turn_mode != SimMoveConfig.TM_ARC and not tlock:
			var dx: int = mv.goal_x - e.x
			var dy: int = mv.goal_y - e.y
			if mv.goal_kind == SimMoveConfig.GK_FOLLOW or mv.goal_kind == SimMoveConfig.GK_APPROACH:
				var t: SimEntity = world.by_id[mv.goal_target] if mv.goal_target >= 0 and mv.goal_target < world.by_id.size() else null
				if t != null:
					dx = t.x - e.x
					dy = t.y - e.y
			if dx != 0 or dy != 0:
				var rate: int = SimSteering.turn_step_rate(mv.turn_mode, mv.turn_rate, absi(spd), vcur)
				facing = (facing + clampi(SimSteering.angle_err(Fp.atan2(dy, dx), facing), -rate, rate)) & 4095
	elif st == SimMoveConfig.MS_FACING:
		var err: int = SimSteering.angle_err(mv.goal_x, facing)
		if absi(err) < 64:
			mv.state = SimMoveConfig.MS_IDLE
			mv.result = SimMoveConfig.RS_OK
			mv.goal_kind = SimMoveConfig.GK_NONE
		elif not tlock:
			var rate2: int = SimSteering.turn_step_rate(mv.turn_mode, mv.turn_rate, absi(spd), vcur)
			facing = (facing + clampi(err, -rate2, rate2)) & 4095
	spd = SimSteering.speed_law(spd, 0, mv.accel_q4, mv.decel_q4)
	e.facing = facing
	mv.spd_q4 = spd
	if spd != 0:
		_sx[i] = SimSteering.vel_x(spd, facing)
		_sy[i] = SimSteering.vel_y(spd, facing)


## MS_EVICT (5.9): a unit boxed in a footprint drives straight out to the chosen cell, ignoring cell weights, for at
## most EVICT_TICKS ticks.
func _evict_step(world: SimWorld, i: int, e: SimEntity, mv: SimCompMove, vcur: int) -> void:
	var dx: int = mv.goal_x - e.x
	var dy: int = mv.goal_y - e.y
	var d: int = Fp.dist(dx, dy)
	if d <= SimExitMove.EVICT_ARRIVE or world.tick - mv.goal_tick >= SimExitMove.EVICT_TICKS:
		mv.state = SimMoveConfig.MS_IDLE
		mv.goal_kind = SimMoveConfig.GK_NONE
		mv.result = SimMoveConfig.RS_OK if d <= SimExitMove.EVICT_ARRIVE else SimMoveConfig.RS_STUCK
		mv.spd_q4 = 0
		return
	var step: int = mini(d, maxi(SimExitMove.EVICT_MIN_STEP, (vcur + 15) >> 4))
	var ang: int = Fp.atan2(dy, dx)
	e.facing = ang
	mv.spd_q4 = step << 4
	_sx[i] = Fp.step_x(ang, step)
	_sy[i] = Fp.step_y(ang, step)


## Goal / waypoint logic and steering of one moving unit (5.4.2).
func _steer(world: SimWorld, i: int, e: SimEntity, mv: SimCompMove, vcur: int, tlock: bool, cell: int) -> void:
	var w: int = _w
	var x: int = e.x
	var y: int = e.y
	var facing: int = e.facing
	var spd: int = mv.spd_q4
	var spd_abs: int = absi(spd)
	var gk: int = mv.goal_kind
	var gx: int = mv.goal_x
	var gy: int = mv.goal_y
	var extra: int = 0
	if gk == SimMoveConfig.GK_FOLLOW or gk == SimMoveConfig.GK_APPROACH:
		var t: SimEntity = world.by_id[mv.goal_target] if mv.goal_target >= 0 and mv.goal_target < world.by_id.size() else null
		if t == null or (t.flags & SimFlags.F_GONE) != 0:
			path.cancel(e.id)
			mv.req_id = 0
			mv.state = SimMoveConfig.MS_NO_PATH
			mv.result = SimMoveConfig.RS_BAD_TARGET
			mv.goal_kind = SimMoveConfig.GK_NONE
			_brake(i, e, mv)
			return
		gx = t.x
		gy = t.y
		extra = t.radius
	var pth: PackedInt32Array = mv.path
	var n: int = pth.size()
	var wp: int = mv.wp
	var final: bool = true
	var tx: int = gx
	var ty: int = gy
	var rd: int = 0
	var reach: int = maxi(SimMoveConfig.WP_REACH_MIN, (spd_abs >> 4) * 3)
	var adv: int = 0
	while wp < n:
		var c: int = pth[wp]
		tx = (c % w) * 1024 + 512
		ty = (c / w) * 1024 + 512
		rd = Fp.dist(tx - x, ty - y)
		if adv < 2:
			if rd <= reach:
				wp += 1
				adv += 1
				continue
			if wp + 1 < n and rd <= 1536 and _nav.los(mv.np, mv.nav_size, cell, pth[wp + 1]):
				wp += 1
				adv += 1
				continue
		final = false
		break
	mv.wp = wp
	var range_u: int = mv.goal_range
	if not final and range_u > 0 and Fp.dist(gx - x, gy - y) - extra <= range_u:
		final = true  # already within range of the goal: no need to walk the rest of the path
		wp = n
	elif not final and mv.route_x >= 0 and gk == SimMoveConfig.GK_POINT and Fp.dist(gx - x, gy - y) <= SLOT_CUT_DIST \
			and _nav.los(mv.np, mv.nav_size, cell, clampi(gy >> 10, 0, _h - 1) * w + clampi(gx >> 10, 0, _w - 1)):
		final = true  # formation slot in sight within 6 cells: cut straight to it (5.5)
		wp = n
	if final:
		tx = gx
		ty = gy
		rd = Fp.dist(tx - x, ty - y)
		if (mv.flags & SimMoveConfig.MF_PATH_PARTIAL) != 0:
			if _partial_consumed(world, e, mv, cell):
				_brake(i, e, mv)
				return
	var rd_eff: int = maxi(0, rd - extra)
	var des: int = Fp.atan2(ty - y, tx - x) if rd > 0 else facing
	var err: int = ((des - facing + 2048) & 4095) - 2048
	var aerr: int = absi(err)
	var flags: int = mv.flags
	var reversing: bool = (flags & SimMoveConfig.MF_REVERSING) != 0
	var mode: int = mv.turn_mode
	var decel: int = mv.decel_q4
	if (final or wp + 1 >= n) and mv.reverse_pct > 0 and (mv.goal_opts & SimMoveConfig.OPT_REVERSE_OK) != 0:  # the last leg
		if reversing:
			if aerr < 1024:
				reversing = false
		elif aerr > 1536 and rd <= 4096 and spd_abs <= vcur / 4:
			reversing = true
	else:
		reversing = false
	var target: int
	if reversing:
		flags |= SimMoveConfig.MF_REVERSING
		target = -mini(vcur * mv.reverse_pct / 100, Fp.isqrt(32 * decel * maxi(0, maxi(0, rd_eff - range_u) - (spd_abs >> 4))))
	else:
		flags &= ~SimMoveConfig.MF_REVERSING
		var step: int = 0
		if not tlock:
			var rate: int = mv.turn_rate
			if mode == SimMoveConfig.TM_ARC:
				var frac: int = mini(256, spd_abs * 256 / maxi(1, vcur))
				rate = (rate * (64 + ((192 * frac) >> 8))) >> 8
			step = clampi(err, -rate, rate)
			facing = (facing + step) & 4095
		var a: int = absi(err - step)
		var f: int = 256
		if mode != SimMoveConfig.TM_BANK and a > 256:
			if mode == SimMoveConfig.TM_ARC:
				f = maxi(64, 256 - ((a - 256) * 192) / 768)
			elif a <= 768:
				f = 256 - ((a - 256) * 256) / 512
			else:
				f = 0
		target = (vcur * f) >> 8
		if final:
			target = mini(target, Fp.isqrt(32 * decel * maxi(0, maxi(0, rd_eff - range_u) - (spd_abs >> 4))))
	mv.flags = flags
	# speed law (signed)
	if target > spd:
		spd = mini(spd + mv.accel_q4, target)
	else:
		spd = maxi(spd - decel, target)
	# arrival (final leg): stop radius, slow enough or about to overshoot
	if final and gk != SimMoveConfig.GK_FOLLOW:
		var stop_r: int = range_u
		if stop_r <= 0:
			stop_r = SimMoveConfig.ARRIVE_EPS_PRECISE if (flags & SimMoveConfig.MF_PRECISE) != 0 else SimMoveConfig.ARRIVE_EPS
		var sa: int = absi(spd)
		# an ARC unit cannot turn inside ~2 stop radii: a goal that close and behind / beside it counts as reached
		var orbit: bool = mode == SimMoveConfig.TM_ARC and rd_eff <= 2 * stop_r and aerr > 1024
		if rd_eff <= stop_r and (sa <= 2 * decel or rd_eff <= (sa >> 4) + 1) or orbit:
			mv.spd_q4 = 0
			mv.state = SimMoveConfig.MS_IDLE if gk == SimMoveConfig.GK_SIDESTEP else SimMoveConfig.MS_ARRIVED
			if gk == SimMoveConfig.GK_SIDESTEP:
				mv.goal_kind = SimMoveConfig.GK_NONE
			mv.result = SimMoveConfig.RS_OK
			mv.flags = flags & ~SimMoveConfig.MF_REVERSING
			e.facing = facing
			if (flags & SimMoveConfig.MF_PRECISE) != 0:
				_sx[i] = gx - x
				_sy[i] = gy - y
			return
	e.facing = facing
	mv.spd_q4 = spd
	var vx: int = (spd * _sin[(facing + 1024) & 4095] + 524288) >> 20
	var vy: int = (spd * _sin[facing & 4095] + 524288) >> 20
	if mv.nudge_t > 0:
		mv.nudge_t -= 1
		var lat: int = ((vcur * 40 / 100) >> 4)
		var la: int = facing + mv.nudge_dir
		vx += Fp.step_x(la, lat)
		vy += Fp.step_y(la, lat)
	_sx[i] = vx
	_sy[i] = vy


func _brake(i: int, e: SimEntity, mv: SimCompMove) -> void:
	var spd: int = SimSteering.speed_law(mv.spd_q4, 0, mv.accel_q4, mv.decel_q4)
	mv.spd_q4 = spd
	if spd != 0:
		_sx[i] = SimSteering.vel_x(spd, e.facing)
		_sy[i] = SimSteering.vel_y(spd, e.facing)


## A partial path was walked to its end: repath when the goal is reachable from here (rate limited), else the
## unit has arrived as near as it can (RS_PARTIAL). Returns true when the unit must brake this tick.
func _partial_consumed(world: SimWorld, e: SimEntity, mv: SimCompMove, cell: int) -> bool:
	var goal: int = clampi(mv.goal_y >> 10, 0, _h - 1) * _w + clampi(mv.goal_x >> 10, 0, _w - 1)
	if mv.goal_kind == SimMoveConfig.GK_FOLLOW or mv.goal_kind == SimMoveConfig.GK_APPROACH:
		var t: SimEntity = world.by_id[mv.goal_target]
		goal = clampi(t.y >> 10, 0, _h - 1) * _w + clampi(t.x >> 10, 0, _w - 1)
	if _nav.same_region(mv.np, mv.nav_size, cell, goal) and cell != goal:
		if world.tick >= mv.repath_at:
			mv.repath_at = world.tick + SimMoveConfig.REPATH_MIN_INTERVAL
			request_path(world, e, mv, SimPathService.PRIO_REPATH, 0, PackedInt32Array())
			mv.state = SimMoveConfig.MS_WAIT_PATH
			mv.wait = 0
		return true
	mv.state = SimMoveConfig.MS_ARRIVED
	mv.result = SimMoveConfig.RS_PARTIAL
	mv.spd_q4 = 0
	return true


## Queues a path request for the unit's current goal (start = its cell).
func request_path(world: SimWorld, e: SimEntity, mv: SimCompMove, prio: int, flags: int, avoid: PackedInt32Array) -> void:
	var gx: int = mv.goal_x
	var gy: int = mv.goal_y
	var extra: int = 0
	if mv.goal_kind == SimMoveConfig.GK_FOLLOW or mv.goal_kind == SimMoveConfig.GK_APPROACH:
		var t: SimEntity = world.by_id[mv.goal_target] if mv.goal_target >= 0 and mv.goal_target < world.by_id.size() else null
		if t != null:
			gx = t.x
			gy = t.y
			extra = t.radius
	if mv.goal_kind == SimMoveConfig.GK_POINT and mv.route_x >= 0:  # formation slot: search the shared group target
		gx = mv.route_x
		gy = mv.route_y
	var cell: int = clampi(gy >> 10, 0, _h - 1) * _w + clampi(gx >> 10, 0, _w - 1)
	var goal_r: int = 0
	if mv.goal_range > 0:
		goal_r = ((mv.goal_range + extra) * 5 / 8) >> 10
	mv.goal_cell = cell
	path.request(e, cell, goal_r, prio, flags, avoid)


# ---- phase C ------------------------------------------------------------------------------------------------------

func _phase_c(world: SimWorld, i: int, e: SimEntity, mv: SimCompMove) -> void:
	var st: int = mv.state
	if (st == SimMoveConfig.MS_IDLE or st == SimMoveConfig.MS_ARRIVED or st == SimMoveConfig.MS_NO_PATH) and _sx[i] == 0 and _sy[i] == 0 \
			and _pd[i * 2] == 0 and _pd[i * 2 + 1] == 0 and mv.spd_q4 == 0 and mv.lr_layer < 0 and mv.mc != MapTerrain.MC_AMPHIBIOUS \
			and (e.flags & (SimFlags.F_MOVING | SimFlags.F_BLOCKED)) == 0:
		mv.vx = 0
		mv.vy = 0
		mv.blocked_t = 0
		return
	var tick: int = world.tick
	if st == SimMoveConfig.MS_GLIDE:
		_glide_step(world, e, mv)
		_mirror(e, mv)
		return
	var dx: int = _sx[i] + _pd[i * 2]
	var dy: int = _sy[i] + _pd[i * 2 + 1]
	var rejected: bool = false
	var moved: bool = false
	if dx != 0 or dy != 0:
		var ox: int = e.x
		var oy: int = e.y
		var nx: int = clampi(ox + dx, 2048, _max_x - 2047)
		var ny: int = clampi(oy + dy, 2048, _max_y - 2047)
		var w: int = _w
		var cx: int = ox >> 10
		var cy: int = oy >> 10
		var ncx: int = nx >> 10
		var ncy: int = ny >> 10
		if (ncx != cx or ncy != cy) and st != SimMoveConfig.MS_EVICT:
			var wg: PackedByteArray = _wg[mv.np]
			var ok: bool = wg[ncy * w + ncx] != 0
			if ok and ncx != cx and ncy != cy:
				ok = wg[cy * w + ncx] != 0 and wg[ncy * w + cx] != 0
			if not ok:
				if ncx == cx or wg[cy * w + ncx] != 0:
					ny = oy
				elif ncy == cy or wg[ncy * w + cx] != 0:
					nx = ox
				else:
					nx = ox
					ny = oy
					mv.spd_q4 = mv.spd_q4 / 2
					rejected = true
		if nx != ox or ny != oy:
			world.set_pos(e, nx, ny)
			moved = true
			mv.cell = (ny >> 10) * w + (nx >> 10)
			mv.cell_kind = _kind[mv.cell]
	mv.vx = e.x - e.prev_x if moved else 0
	mv.vy = e.y - e.prev_y if moved else 0
	if st == SimMoveConfig.MS_MOVING or st == SimMoveConfig.MS_BLOCKED:
		if rejected:
			mv.blocked_t += 1
			if mv.blocked_t >= 3:
				mv.state = SimMoveConfig.MS_BLOCKED
		elif dx != 0 or dy != 0:
			mv.blocked_t = 0
			if st == SimMoveConfig.MS_BLOCKED:
				mv.state = SimMoveConfig.MS_MOVING
	elif st != SimMoveConfig.MS_WAIT_PATH and st != SimMoveConfig.MS_SIDESTEP:
		mv.blocked_t = 0
	if mv.mc == MapTerrain.MC_AMPHIBIOUS:
		var wk: bool = mv.cell_kind == MapTerrain.TK_SHALLOW or mv.cell_kind == MapTerrain.TK_DEEP
		if wk != ((mv.flags & SimMoveConfig.MF_ON_WATER) != 0) and tick - mv.water_t >= SimMoveConfig.WATER_HYSTERESIS:
			mv.water_t = tick
			mv.flags ^= SimMoveConfig.MF_ON_WATER
			mv.hl = SimMoveConfig.HL_WATER if wk else SimMoveConfig.HL_GROUND
			world.emit(SimMoveConfig.EV_MEDIUM_CHANGED, e.x, e.y, e.id, 1 if wk else 0)
	if mv.lr_layer >= 0:
		mv.lr_t -= 1
		if mv.lr_t <= 0:
			world.set_layer(e, mv.lr_layer)
			mv.hl = SimMoveConfig.HL_SUB if mv.lr_layer == SimEntity.Layer.UNDERWATER else SimMoveConfig.HL_WATER
			world.emit(SimMoveConfig.EV_LAYER_CHANGED, e.x, e.y, e.id, mv.lr_layer)
			mv.lr_layer = -1
	_mirror(e, mv)


func _glide_step(world: SimWorld, e: SimEntity, mv: SimCompMove) -> void:
	mv.g_t += 1
	var t: int = mini(mv.g_t, mv.g_n)
	var nx: int = mv.g_x1 if t >= mv.g_n else Fp.lerp_i(mv.g_x0, mv.g_x1, t, mv.g_n)
	var ny: int = mv.g_y1 if t >= mv.g_n else Fp.lerp_i(mv.g_y0, mv.g_y1, t, mv.g_n)
	world.set_pos(e, nx, ny)
	mv.vx = e.x - e.prev_x
	mv.vy = e.y - e.prev_y
	mv.cell = (e.y >> 10) * _w + (e.x >> 10)
	if mv.g_t >= mv.g_n:
		mv.state = SimMoveConfig.MS_ARRIVED
		mv.result = SimMoveConfig.RS_OK
		mv.goal_kind = SimMoveConfig.GK_NONE
		mv.spd_q4 = 0


## Flag mirrors (bits 16-19 only).
func _mirror(e: SimEntity, mv: SimCompMove) -> void:
	var st: int = mv.state
	var bits: int = 0
	if mv.spd_q4 != 0 or st == SimMoveConfig.MS_MOVING or st == SimMoveConfig.MS_GLIDE:
		bits |= SimFlags.F_MOVING
	if st == SimMoveConfig.MS_BLOCKED or mv.blocked_t >= 3:
		bits |= SimFlags.F_BLOCKED
	if (mv.flags & SimMoveConfig.MF_ON_WATER) != 0:
		bits |= SimFlags.F_ON_WATER
	if e.layer == SimEntity.Layer.AIR:
		bits |= SimFlags.F_AIRBORNE
	var f: int = (e.flags & ~SimMoveConfig.F_MIRROR_MASK) | bits
	if f != e.flags:
		e.flags = f


# ---- strided maintenance (g) ---------------------------------------------------------------------------------------

func _maintain(world: SimWorld, i: int, e: SimEntity, mv: SimCompMove) -> void:
	var st: int = mv.state
	if st != SimMoveConfig.MS_MOVING and st != SimMoveConfig.MS_BLOCKED and st != SimMoveConfig.MS_WAIT_PATH:
		if mv.stuck_cnt != 0:
			mv.stuck_cnt = 0
		return
	var tick: int = world.tick
	var phase: int = (tick + e.id) % SimMoveConfig.STUCK_STRIDE
	if st != SimMoveConfig.MS_WAIT_PATH:
		if phase == 0:
			_stuck_check(world, i, e, mv)
			if mv.state != SimMoveConfig.MS_MOVING and mv.state != SimMoveConfig.MS_BLOCKED:
				return
		if mv.path_ver != map_version(world) and mv.req_id == 0 and (tick + e.id) % SimMoveConfig.VALIDITY_STRIDE == 0:
			_validate_path(world, e, mv)
		var gk: int = mv.goal_kind
		if (gk == SimMoveConfig.GK_FOLLOW or gk == SimMoveConfig.GK_APPROACH) and (tick + e.id) % SimMoveConfig.FOLLOW_STRIDE == 0:
			_follow_replan(world, e, mv)


func map_version(world: SimWorld) -> int:
	return world.map.nav_version


func _validate_path(world: SimWorld, e: SimEntity, mv: SimCompMove) -> void:
	var n: int = mv.path.size()
	if mv.wp >= n:
		mv.path_ver = world.map.nav_version
		return
	var cell: int = mv.cell
	var ok: bool = _nav.los(mv.np, mv.nav_size, cell, mv.path[mv.wp])
	var k: int = mv.wp
	var segs: int = 0
	while ok and segs < 2 and k + 1 < n:
		ok = _nav.los(mv.np, mv.nav_size, mv.path[k], mv.path[k + 1])
		k += 1
		segs += 1
	if ok:
		mv.path_ver = world.map.nav_version
	else:
		mv.repath_at = world.tick + SimMoveConfig.REPATH_MIN_INTERVAL
		request_path(world, e, mv, SimPathService.PRIO_REPATH, SimPathService.RQ_REPATH, PackedInt32Array())


func _follow_replan(world: SimWorld, e: SimEntity, mv: SimCompMove) -> void:
	if mv.req_id != 0 or world.tick < mv.repath_at:
		return
	var t: SimEntity = world.by_id[mv.goal_target] if mv.goal_target >= 0 and mv.goal_target < world.by_id.size() else null
	if t == null:
		return
	if maxi(absi(t.x - mv.goal_x), absi(t.y - mv.goal_y)) > 3 * SimMoveConfig.CELL:
		mv.goal_x = t.x
		mv.goal_y = t.y
		mv.repath_at = world.tick + SimMoveConfig.REPATH_MIN_INTERVAL
		request_path(world, e, mv, SimPathService.PRIO_REPATH, SimPathService.RQ_REPATH, PackedInt32Array())


## Stuck detection and escalation (5.4.6). Called every STUCK_STRIDE ticks per unit.
func _stuck_check(world: SimWorld, i: int, e: SimEntity, mv: SimCompMove) -> void:
	if sep.eimm[i] == 1 or mv.vcur_q4 == 0:
		mv.stuck_cnt = 0
		mv.stuck_x = e.x
		mv.stuck_y = e.y
		return
	var expected: int = (((mv.vcur_q4 * 10) >> 4) * SimMoveConfig.STUCK_MIN_PCT) / 100
	var dx: int = e.x - mv.stuck_x
	var dy: int = e.y - mv.stuck_y
	var prev_x: int = mv.stuck_x
	var prev_y: int = mv.stuck_y
	mv.stuck_x = e.x
	mv.stuck_y = e.y
	# crowded destination: jostled around the goal without closing in counts as arrived after 4 strides (the plain
	# displacement test below misses it because pushes keep the unit moving)
	if mv.wp >= mv.path.size() and mv.goal_kind != SimMoveConfig.GK_FOLLOW:
		var gd_now: int = _dist_to_goal(world, mv, e)
		var gd_prev: int = Fp.dist(mv.goal_x - prev_x, mv.goal_y - prev_y)
		if gd_now <= 6 * SimMoveConfig.CELL and gd_prev - gd_now < expected / 2:
			mv.wait += 1
			if mv.wait >= 4:
				mv.wait = 0
				mv.stuck_cnt = 0
				mv.state = SimMoveConfig.MS_ARRIVED
				mv.result = SimMoveConfig.RS_OK
				mv.spd_q4 = 0
				return
		else:
			mv.wait = 0
	if dx * dx + dy * dy < expected * expected:
		mv.stuck_cnt += 1
	else:
		mv.stuck_cnt = 0
		mv.blocked_by = -1
		return
	var cnt: int = mv.stuck_cnt
	if cnt == 1:
		var b: SimEntity = _find_blocker(world, e, mv)
		if b != null and b.move != null and world.are_allied(e.owner, b.owner) and b.move.goal_kind == SimMoveConfig.GK_NONE \
				and (b.flags & SimFlags.F_DEPLOYED) == 0:
			SimMovement.sidestep(world, b, mv_heading(e), 0)
	elif cnt == 2:
		# lateral nudge toward the id-parity side, or the other side when that one is a wall; none in a 1-cell lane
		var pref: int = 1024 if (e.id & 1) == 0 else -1024
		mv.nudge_t = 0
		for side: int in [pref, -pref]:
			var lx: int = clampi(e.x + Fp.step_x(e.facing + side, SimMoveConfig.CELL), 0, _max_x)
			var ly: int = clampi(e.y + Fp.step_y(e.facing + side, SimMoveConfig.CELL), 0, _max_y)
			if _wg[mv.np][(ly >> 10) * _w + (lx >> 10)] != 0:
				mv.nudge_t = 10
				mv.nudge_dir = side
				break
	elif cnt == 4 or cnt == 6:
		if cnt == 6 and _dist_to_goal(world, mv, e) <= 6 * SimMoveConfig.CELL:
			mv.state = SimMoveConfig.MS_ARRIVED
			mv.result = SimMoveConfig.RS_OK
			mv.spd_q4 = 0
			return
		_repath_avoiding(world, e, mv)
	elif cnt >= 8:
		world.emit(SimMoveConfig.EV_STUCK, e.x, e.y, e.id, cnt)
		path.cancel(e.id)
		mv.req_id = 0
		mv.state = SimMoveConfig.MS_NO_PATH
		mv.result = SimMoveConfig.RS_STUCK
		mv.goal_kind = SimMoveConfig.GK_NONE
		mv.stuck_cnt = 0


func mv_heading(e: SimEntity) -> int:
	return e.facing


func _dist_to_goal(world: SimWorld, mv: SimCompMove, e: SimEntity) -> int:
	var gx: int = mv.goal_x
	var gy: int = mv.goal_y
	if mv.goal_kind == SimMoveConfig.GK_FOLLOW or mv.goal_kind == SimMoveConfig.GK_APPROACH:
		var t: SimEntity = world.by_id[mv.goal_target] if mv.goal_target >= 0 and mv.goal_target < world.by_id.size() else null
		if t != null:
			gx = t.x
			gy = t.y
	return Fp.dist(gx - e.x, gy - e.y)


## Nearest other unit ahead of `e` (within its radius + 1 cell); ties: lowest id. Sets and returns blocked_by.
func _find_blocker(world: SimWorld, e: SimEntity, mv: SimCompMove) -> SimEntity:
	var reach: int = mv.radius + SimMoveConfig.CELL
	var cx: int = e.x + Fp.step_x(e.facing, reach / 2)
	var cy: int = e.y + Fp.step_y(e.facing, reach / 2)
	_qbuf.resize(0)
	world.query_circle(cx, cy, reach, _qbuf, SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.UNIT))
	var best: SimEntity = null
	var best_d: int = 0
	for id: int in _qbuf:
		if id == e.id:
			continue
		var o: SimEntity = world.by_id[id]
		if (o.flags & (SimFlags.F_INSIDE | SimFlags.F_NO_COLLISION)) != 0:
			continue
		var d: int = Fp.dist2(o.x - e.x, o.y - e.y)
		if best == null or d < best_d or (d == best_d and o.id < best.id):
			best = o
			best_d = d
	mv.blocked_by = best.id if best != null else -1
	return best


## Repath with the cells of the blocker and up to 3 nearest idle / immobile neighbours as `avoid`.
func _repath_avoiding(world: SimWorld, e: SimEntity, mv: SimCompMove) -> void:
	_avoid_buf = PackedInt32Array()
	var b: SimEntity = _find_blocker(world, e, mv)
	if b != null:
		_avoid_buf.append(clampi(b.y >> 10, 0, _h - 1) * _w + clampi(b.x >> 10, 0, _w - 1))
	_qbuf.resize(0)
	world.query_circle(e.x, e.y, 2 * SimMoveConfig.CELL, _qbuf, SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.UNIT))
	var picked: int = 0
	var last_key: int = -1
	while picked < 3:
		var best: SimEntity = null
		var best_key: int = 0
		for id: int in _qbuf:
			if id == e.id or (b != null and id == b.id):
				continue
			var o: SimEntity = world.by_id[id]
			if o.move == null or (o.flags & SimFlags.F_INSIDE) != 0:
				continue
			var idle: bool = o.move.goal_kind == SimMoveConfig.GK_NONE or (o.flags & SimFlags.F_DEPLOYED) != 0
			if not idle:
				continue
			var key: int = (Fp.dist2(o.x - e.x, o.y - e.y) << 16) | o.id
			if key <= last_key:
				continue
			if best == null or key < best_key:
				best = o
				best_key = key
		if best == null:
			break
		last_key = best_key
		picked += 1
		var c: int = clampi(best.y >> 10, 0, _h - 1) * _w + clampi(best.x >> 10, 0, _w - 1)
		if not _avoid_buf.has(c):
			_avoid_buf.append(c)
	mv.repath_at = world.tick + SimMoveConfig.REPATH_MIN_INTERVAL
	request_path(world, e, mv, SimPathService.PRIO_REPATH, SimPathService.RQ_REPATH, _avoid_buf)
