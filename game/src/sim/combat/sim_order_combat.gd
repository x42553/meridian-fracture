class_name SimOrderCombat
extends SimOrderHandler
## Combat orders (combat 5.10.6 / 6.1, task CB-06): T_ATTACK, T_ATTACK_MOVE, T_GUARD, T_HOLD, T_FORCE_FIRE, T_RETURN_BASE
## as SimOrderHandler instances (one per type, `SimOrderCombat.new(type)`), plus the idle engagement handler
## (`SimOrderCombat.new(SimOrder.T_NONE)` registered with register_idle: chase, leash, return to the anchor).
##
## The kernel's built-in command executors already turn commands 40..44 / 47 into these orders and run the validation
## through `can_issue`; `SimCombatSystem.init_world` registers the executors of CMD_SET_STANCE and CMD_SCUTTLE.
## Order fields: ATTACK target_id + OF_FORCED; ATTACK_MOVE x,y + p1 state (AM_MOVE / AM_ENGAGE / 2 = waiting for unpack),
## arg,arg2 origin of the engagement, p0 no-target-since tick; GUARD target_id or x,y + p1 saved stance + 1; FORCE_FIRE
## target_id or x,y, arg = salvo count (arg2 = 1 when counting), p0 salvo counter; all handler state is hashed.

const AM_WAIT_PACK: int = 2
const CHASE_GAP: int = 10  ## ticks between two movement goals of one chase
const GUARD_FOLLOW: int = 4096  ## an idle guard follows a guarded unit that is farther than this
const GUARD_RECENT: int = 40  ## ticks an attacker of the guarded unit stays a candidate
const PACK_TIMEOUT: int = 600
const BACKOFF_EXTRA: int = 1024

var order_type: int = SimOrder.T_NONE


func _init(p_type: int = SimOrder.T_NONE) -> void:
	order_type = p_type
	requires_target = p_type == SimOrder.T_ATTACK or p_type == SimOrder.T_GUARD or p_type == SimOrder.T_FORCE_FIRE


# ---------------------------------------------------------------------------------------------- validation
func can_issue(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var cc: SimCompCombat = e.combat
	match order_type:
		SimOrder.T_ATTACK:
			if cc == null or cc.n_mounts == 0:
				return SimCommand.Err.NOT_ALLOWED
			var t: SimEntity = world.get_entity(o.target_id)
			if t == null or (t.flags & SimFlags.F_GONE) != 0:
				return SimCommand.Err.NO_TARGET
			var forced: bool = (o.flags & SimOrder.OF_FORCED) != 0
			if t.kind == SimEntity.Kind.WRECK and not forced:
				return SimCommand.Err.WRONG_KIND  # wrecks are force-fire only
			if not forced and world.rel(e.owner, t.owner) != SimCombatConsts.REL_ENEMY:
				return SimCommand.Err.NOT_ALLOWED  # own / allied / neutral only with the forced flag
			if not _known(world, e, t):
				return SimCommand.Err.NO_VISION
			if not SimTargeting.can_attack(world, e, t, forced, true):
				return SimCommand.Err.NOT_ALLOWED
		SimOrder.T_ATTACK_MOVE:
			if e.move == null:
				return SimCommand.Err.NOT_ALLOWED
		SimOrder.T_GUARD:
			if cc == null:
				return SimCommand.Err.NOT_ALLOWED
			if o.target_id != 0:
				var g: SimEntity = world.get_entity(o.target_id)
				if g == null or (g.flags & SimFlags.F_GONE) != 0:
					return SimCommand.Err.NO_TARGET
				var r: int = world.rel(e.owner, g.owner)
				if g == e or (r != SimCombatConsts.REL_SELF and r != SimCombatConsts.REL_ALLY):
					return SimCommand.Err.NOT_ALLOWED
		SimOrder.T_FORCE_FIRE:
			if cc == null or cc.n_mounts == 0:
				return SimCommand.Err.NOT_ALLOWED
			if o.target_id != 0:
				var ft: SimEntity = world.get_entity(o.target_id)
				if ft == null or (ft.flags & SimFlags.F_GONE) != 0 or ft == e:
					return SimCommand.Err.NO_TARGET
				if not SimTargeting.can_attack(world, e, ft, true, true):
					return SimCommand.Err.NOT_ALLOWED
		SimOrder.T_RETURN_BASE:
			if not _is_air(e):
				return SimCommand.Err.NOT_ALLOWED
	return SimCommand.Err.OK


## An explicit order accepts a visible target or a remembered structure.
static func _known(world: SimWorld, e: SimEntity, t: SimEntity) -> bool:
	if t.owner == e.owner or world.fog.entity_visible(e.owner, t):
		return true
	return t.kind == SimEntity.Kind.STRUCTURE or t.kind == SimEntity.Kind.NEUTRAL


# ---------------------------------------------------------------------------------------------- lifecycle
func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var cc: SimCompCombat = e.combat
	o.t0 = world.tick
	if cc != null:
		cc.hold_pos = 0
	match order_type:
		SimOrder.T_ATTACK:
			return _begin_attack(world, e, o, cc)
		SimOrder.T_ATTACK_MOVE:
			return _begin_attack_move(world, e, o, cc)
		SimOrder.T_GUARD:
			return _begin_guard(world, e, o, cc)
		SimOrder.T_HOLD:
			return _begin_hold(world, e, cc)
		SimOrder.T_FORCE_FIRE:
			return _begin_force_fire(world, e, o, cc)
		SimOrder.T_RETURN_BASE:
			if not SimAirSortie.assign_mission(world, e, SimCombatConsts.MI_RETURN, 0, 0, 0, 0):
				o.fail = SimCommand.Err.NOT_ALLOWED
				return SimOrder.FAILED
	return SimOrder.RUNNING


func on_update(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var cc: SimCompCombat = e.combat
	match order_type:
		SimOrder.T_ATTACK:
			return _update_attack(world, e, o, cc)
		SimOrder.T_ATTACK_MOVE:
			return _update_attack_move(world, e, o, cc)
		SimOrder.T_GUARD:
			return _update_guard(world, e, o, cc)
		SimOrder.T_FORCE_FIRE:
			return _update_force_fire(world, e, o, cc)
		SimOrder.T_RETURN_BASE:
			return _update_return(world, e, o)
	return SimOrder.RUNNING  # T_HOLD runs until replaced


func on_end(world: SimWorld, e: SimEntity, o: SimOrder, reason: int) -> void:
	var cc: SimCompCombat = e.combat
	if cc == null or (e.flags & SimFlags.F_GONE) != 0 or reason == SimOrder.END_DIED:
		return
	match order_type:
		SimOrder.T_ATTACK, SimOrder.T_FORCE_FIRE:
			if cc.target_src == SimCombatConsts.TS_ORDER or cc.target_src == SimCombatConsts.TS_FORCE:
				SimTargeting.clear_target(e)
			_stop_own_goal(world, e, o)
		SimOrder.T_ATTACK_MOVE:
			cc.anchor_on = 0
			_stop_own_goal(world, e, o)
		SimOrder.T_GUARD:
			if cc.stance == SimCombatConsts.ST_GUARD and o.p1 > 0:
				cc.stance = o.p1 - 1
			cc.anchor_on = 0
			_stop_own_goal(world, e, o)
		SimOrder.T_HOLD:
			cc.hold_pos = 0
		SimOrder.T_RETURN_BASE:
			pass
	if _is_air(e) and (reason == SimOrder.END_CANCELLED) and order_type != SimOrder.T_RETURN_BASE:
		SimAirSortie.assign_mission(world, e, SimCombatConsts.MI_RETURN, 0, 0, 0, 0)  # a stopped aircraft goes home


func on_target_lost(_world: SimWorld, _e: SimEntity, _o: SimOrder) -> int:
	return SimOrder.DONE  # the target (or the guarded unit) died: the order is done


## Stops the unit if the movement goal in force was set by this order.
func _stop_own_goal(world: SimWorld, e: SimEntity, o: SimOrder) -> void:
	var mv: SimCompMove = e.move
	if mv != null and mv.goal_kind != SimMoveConfig.GK_NONE and mv.goal_tick >= o.t0 and mv.mc < MapTerrain.MC_AIR_FIXED:
		SimMovement.stop(world, e, false)


# ---------------------------------------------------------------------------------------------- T_ATTACK
func _begin_attack(world: SimWorld, e: SimEntity, o: SimOrder, cc: SimCompCombat) -> int:
	if _is_air(e):  # the sortie machine binds the target itself once the aircraft is in the air
		if not SimAirSortie.assign_mission(world, e, SimCombatConsts.MI_ATTACK, o.target_id, 0, 0, 0):
			o.fail = SimCommand.Err.NOT_ALLOWED  # no fuel / no ammo
			return SimOrder.FAILED
		return SimOrder.RUNNING
	var src: int = SimCombatConsts.TS_FORCE if (o.flags & SimOrder.OF_FORCED) != 0 else SimCombatConsts.TS_ORDER
	if not SimTargeting.set_target(world, e, o.target_id, src):
		o.fail = SimCommand.Err.NOT_ALLOWED
		return SimOrder.FAILED
	cc.target_since = world.tick
	return SimOrder.RUNNING


func _update_attack(world: SimWorld, e: SimEntity, o: SimOrder, cc: SimCompCombat) -> int:
	var t: SimEntity = world.get_entity(o.target_id)
	if t == null or (t.flags & SimFlags.F_GONE) != 0:
		return SimOrder.DONE
	var forced: bool = (o.flags & SimOrder.OF_FORCED) != 0
	if _is_air(e):
		return _air_progress(e, o)
	if cc.target_id != o.target_id:
		return SimOrder.DONE  # hidden for too long / dropped by the validation
	var cd: SimCombatDef = world.combat.def_for(world, e)
	if cd == null:
		return SimOrder.DONE
	var m: int = best_mount(world, world.combat, e, cd, t, forced)
	if m < 0:
		o.fail = SimCommand.Err.NOT_ALLOWED  # e.g. a submarine dived
		return SimOrder.FAILED
	engage_move(world, e, cc, cd, t, m, true)  # (the result is only interesting to the idle handler)
	return SimOrder.RUNNING


## An aircraft order lasts while the sortie lasts: done when it is on the ground with nothing to resume.
func _air_progress(e: SimEntity, o: SimOrder) -> int:
	var a: SimCompAir = e.air
	if (a.state == SimCombatConsts.AIR_PARKED or a.state == SimCombatConsts.AIR_REARM) and a.resume_mission == SimCombatConsts.MI_NONE \
			and a.mission == SimCombatConsts.MI_NONE and a.state_t0 >= o.t0:
		return SimOrder.DONE
	if a.state == SimCombatConsts.AIR_NO_BASE and a.mission == SimCombatConsts.MI_RETURN:
		o.fail = SimCommand.Err.NOT_AVAILABLE
		return SimOrder.FAILED
	return SimOrder.RUNNING


# ---------------------------------------------------------------------------------------------- T_ATTACK_MOVE
func _begin_attack_move(world: SimWorld, e: SimEntity, o: SimOrder, cc: SimCompCombat) -> int:
	o.p1 = SimCombatConsts.AM_MOVE
	o.p0 = 0
	if _is_air(e):
		if not SimAirSortie.assign_mission(world, e, SimCombatConsts.MI_ATTACK_MOVE, 0, o.x, o.y, 0):
			o.fail = SimCommand.Err.NOT_ALLOWED
			return SimOrder.FAILED
		return SimOrder.RUNNING
	if cc != null:
		cc.anchor_on = 0
	return _am_go(world, e, o)


func _am_go(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var opts: int = SimMoveConfig.OPT_ATTACK_MOVE
	if (o.flags & SimOrder.OF_REVERSE_OK) != 0:
		opts |= SimMoveConfig.OPT_REVERSE_OK
	if (o.flags & SimOrder.OF_SPEED_MATCH) != 0:
		opts |= SimMoveConfig.OPT_SPEED_MATCH
	if SimMovement.go_to(world, e, o.x, o.y, opts):
		o.p1 = SimCombatConsts.AM_MOVE
		return SimOrder.RUNNING
	if e.move != null and e.move.result == SimMoveConfig.RS_IMMOBILE:
		o.p1 = AM_WAIT_PACK  # unpacking: retry
		return SimOrder.RUNNING
	o.fail = SimCommand.Err.NOT_ALLOWED
	return SimOrder.FAILED


func _update_attack_move(world: SimWorld, e: SimEntity, o: SimOrder, cc: SimCompCombat) -> int:
	if _is_air(e):
		var a: SimCompAir = e.air
		if a.mission != SimCombatConsts.MI_ATTACK_MOVE and a.resume_mission != SimCombatConsts.MI_ATTACK_MOVE:
			return SimOrder.DONE
		return SimOrder.RUNNING
	var cd: SimCombatDef = world.combat.def_for(world, e)
	var mv: SimCompMove = e.move
	var tick: int = world.tick
	if o.p1 == AM_WAIT_PACK:
		if tick - o.t0 > PACK_TIMEOUT:
			o.fail = SimCommand.Err.NOT_ALLOWED
			return SimOrder.FAILED
		if tick % CHASE_GAP == 0:
			return _am_go(world, e, o)
		return SimOrder.RUNNING
	var t: SimEntity = live_target(world, cc) if (cc != null and cd != null and cc.stance != SimCombatConsts.ST_HOLD_FIRE) else null
	if o.p1 == SimCombatConsts.AM_MOVE:
		if t != null and not _fire_on_move(world, e, cd, t):
			SimMovement.pause(world, e)
			o.arg = e.x
			o.arg2 = e.y
			o.p0 = 0
			o.p1 = SimCombatConsts.AM_ENGAGE
		else:
			if mv.state == SimMoveConfig.MS_NO_PATH:
				SimMovement.ack(world, e)
				o.fail = SimCommand.Err.BLOCKED
				return SimOrder.FAILED
			var arrived: bool = mv.state == SimMoveConfig.MS_ARRIVED or Fp.dist(o.x - e.x, o.y - e.y) <= 1024
			if arrived and t == null:
				if mv.state == SimMoveConfig.MS_ARRIVED:
					SimMovement.ack(world, e)
				return SimOrder.DONE
			if arrived and t != null:
				o.arg = e.x
				o.arg2 = e.y
				o.p0 = 0
				o.p1 = SimCombatConsts.AM_ENGAGE
			return SimOrder.RUNNING
	# AM_ENGAGE: chase like an idle unit with the leash measured from the origin of the engagement
	cc.anchor_on = 1
	cc.anchor_x = o.arg
	cc.anchor_y = o.arg2
	if t != null:
		o.p0 = 0
		idle_chase(world, e, cc, cd, t, true)
		return SimOrder.RUNNING
	if o.p0 == 0:
		o.p0 = tick
	elif tick - o.p0 >= 10:
		o.p0 = 0
		cc.anchor_on = 0
		return _am_go(world, e, o)
	return SimOrder.RUNNING


## true when every mount that can hit `t` fires while moving (no stationary-fire weapon among them).
static func _fire_on_move(world: SimWorld, e: SimEntity, cd: SimCombatDef, t: SimEntity) -> bool:
	if cd.am_mode == 1:
		return true
	for m: int in cd.n_mounts:
		if cd.pf(m, SimWeaponProfile.PF_SETTLE) > 0 and SimTargeting.can_engage(world, e, cd, m, t, false):
			return false
	return true


# ---------------------------------------------------------------------------------------------- T_GUARD
func _begin_guard(world: SimWorld, e: SimEntity, o: SimOrder, cc: SimCompCombat) -> int:
	if cc.stance != SimCombatConsts.ST_HOLD_FIRE:
		o.p1 = cc.stance + 1
		cc.stance = SimCombatConsts.ST_GUARD
	var g: SimEntity = world.get_entity(o.target_id) if o.target_id != 0 else null
	var ax: int = g.x if g != null else o.x
	var ay: int = g.y if g != null else o.y
	if _is_air(e):
		if not SimAirSortie.assign_mission(world, e, SimCombatConsts.MI_PATROL, 0, ax, ay, 0):
			o.fail = SimCommand.Err.NOT_ALLOWED
			return SimOrder.FAILED
	cc.anchor_on = 1
	cc.anchor_x = ax
	cc.anchor_y = ay
	return SimOrder.RUNNING


func _update_guard(world: SimWorld, e: SimEntity, o: SimOrder, cc: SimCompCombat) -> int:
	var g: SimEntity = world.get_entity(o.target_id) if o.target_id != 0 else null
	if o.target_id != 0 and (g == null or (g.flags & SimFlags.F_GONE) != 0):
		return SimOrder.DONE
	var ax: int = g.x if g != null else o.x
	var ay: int = g.y if g != null else o.y
	var tick: int = world.tick
	if _is_air(e):
		if g != null and tick % CHASE_GAP == 0 and Fp.dist(e.air.m_x - ax, e.air.m_y - ay) > 2048:
			SimAirSortie.assign_mission(world, e, SimCombatConsts.MI_PATROL, 0, ax, ay, 0)
		return SimOrder.RUNNING
	cc.anchor_on = 1
	cc.anchor_x = ax
	cc.anchor_y = ay
	var cd: SimCombatDef = world.combat.def_for(world, e)
	if cd == null:
		return SimOrder.RUNNING
	if g != null and cc.target_id < 0 and cc.stance != SimCombatConsts.ST_HOLD_FIRE and g.combat != null:
		var gc: SimCompCombat = g.combat
		if gc.last_attacker_id > 0 and tick - gc.last_hit_tick <= GUARD_RECENT:
			var atk: SimEntity = world.get_entity(gc.last_attacker_id)
			if atk != null and (atk.flags & SimFlags.F_GONE) == 0 and world.rel(e.owner, atk.owner) == SimCombatConsts.REL_ENEMY \
					and world.fog.entity_visible(e.owner, atk) and SimTargeting.can_attack(world, e, atk, false, false):
				SimTargeting.set_target(world, e, atk.id, SimCombatConsts.TS_GUARD)
	var t: SimEntity = live_target(world, cc) if cc.stance != SimCombatConsts.ST_HOLD_FIRE else null
	if t != null:
		idle_chase(world, e, cc, cd, t, true)
		return SimOrder.RUNNING
	if _mobile(world, e):
		var mv: SimCompMove = e.move
		var d: int = Fp.dist(ax - e.x, ay - e.y)
		var far: bool = d > (GUARD_FOLLOW if g != null else SimCombatConsts.RETURN_SLACK)
		if far and not SimMovement.is_moving(e) and tick - mv.goal_tick >= CHASE_GAP:
			SimMovement.go_near(world, e, ax, ay, 2048 if g != null else 0)
	return SimOrder.RUNNING


# ---------------------------------------------------------------------------------------------- T_HOLD
func _begin_hold(world: SimWorld, e: SimEntity, cc: SimCompCombat) -> int:
	if _is_air(e):
		SimAirSortie.assign_mission(world, e, SimCombatConsts.MI_RETURN, 0, 0, 0, 0)
	elif e.move != null and e.move.mc < MapTerrain.MC_AIR_FIXED:
		SimMovement.stop(world, e, false)
	if cc != null:
		cc.hold_pos = 1
	return SimOrder.RUNNING


# ---------------------------------------------------------------------------------------------- T_FORCE_FIRE
func _begin_force_fire(world: SimWorld, e: SimEntity, o: SimOrder, cc: SimCompCombat) -> int:
	o.arg2 = 1 if o.arg > 0 else 0
	if _is_air(e):
		var cda: SimCombatDef = world.combat.def_for(world, e)
		o.p0 = salvo_sum(cc, cda) if cda != null else 0
		if not SimAirSortie.assign_mission(world, e, SimCombatConsts.MI_ATTACK, o.target_id, o.x, o.y, 0):
			o.fail = SimCommand.Err.NOT_ALLOWED
			return SimOrder.FAILED
		return SimOrder.RUNNING
	if o.target_id != 0:
		if not SimTargeting.set_target(world, e, o.target_id, SimCombatConsts.TS_FORCE):
			o.fail = SimCommand.Err.NOT_ALLOWED
			return SimOrder.FAILED
	else:
		SimTargeting.set_ground_target(e, o.x, o.y)
	var cd: SimCombatDef = world.combat.def_for(world, e)
	o.p0 = salvo_sum(cc, cd) if cd != null else 0
	if _is_air(e) and not SimAirSortie.assign_mission(world, e, SimCombatConsts.MI_ATTACK, o.target_id, o.x, o.y, 0):
		SimTargeting.clear_target(e)
		o.fail = SimCommand.Err.NOT_ALLOWED
		return SimOrder.FAILED
	return SimOrder.RUNNING


func _update_force_fire(world: SimWorld, e: SimEntity, o: SimOrder, cc: SimCompCombat) -> int:
	var cd: SimCombatDef = world.combat.def_for(world, e)
	if cd == null:
		return SimOrder.DONE
	var s: int = salvo_sum(cc, cd)
	if s != o.p0:
		o.p0 = s
		if o.arg2 == 1:
			o.arg -= 1
			if o.arg <= 0:
				return SimOrder.DONE
	if _is_air(e):
		return _air_progress(e, o)
	var t: SimEntity = null
	if o.target_id != 0:
		t = world.get_entity(o.target_id)
		if t == null or (t.flags & SimFlags.F_GONE) != 0 or cc.target_id != o.target_id:
			return SimOrder.DONE
	elif cc.ground_on == 0:
		return SimOrder.DONE  # the validation dropped the point
	if cc.hold_pos == 1:
		return SimOrder.RUNNING
	if t != null:
		var m: int = best_mount(world, world.combat, e, cd, t, true)
		if m < 0:
			o.fail = SimCommand.Err.NOT_ALLOWED
			return SimOrder.FAILED
		engage_move(world, e, cc, cd, t, m, true)
	else:
		_move_to_point(world, e, cc, cd, o.x, o.y)
	return SimOrder.RUNNING


func _move_to_point(world: SimWorld, e: SimEntity, _cc: SimCompCombat, cd: SimCombatDef, gx: int, gy: int) -> void:
	if not _mobile(world, e):
		return
	var cs: SimCombatSystem = world.combat
	var range_u: int = cs.range_max_eff(world, e, -1)
	var d: int = Fp.dist(gx - e.x, gy - e.y)
	var mv: SimCompMove = e.move
	if d > range_u:
		var want: int = SimDamage.mul(range_u, SimCombatConsts.APPROACH_BP)
		var ended: bool = mv.state == SimMoveConfig.MS_IDLE or mv.state == SimMoveConfig.MS_ARRIVED or mv.state == SimMoveConfig.MS_NO_PATH
		if (mv.goal_kind != SimMoveConfig.GK_NEAR or ended) and world.tick - mv.goal_tick >= CHASE_GAP:
			SimMovement.go_near(world, e, gx, gy, want)
	elif mv.goal_kind == SimMoveConfig.GK_NEAR and SimMovement.is_moving(e):
		SimMovement.stop(world, e, false)
	elif not SimMovement.is_moving(e):
		_face_if_needed(world, e, cd, best_mount_point(cd), gx, gy)


static func best_mount_point(cd: SimCombatDef) -> int:
	return 0 if cd.n_mounts > 0 else -1


# ---------------------------------------------------------------------------------------------- T_RETURN_BASE
func _update_return(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	var a: SimCompAir = e.air
	if a.state == SimCombatConsts.AIR_PARKED or a.state == SimCombatConsts.AIR_REARM:
		if world.tick > o.t0:
			return SimOrder.DONE
	elif a.state == SimCombatConsts.AIR_NO_BASE:
		o.fail = SimCommand.Err.NOT_AVAILABLE
		return SimOrder.FAILED
	return SimOrder.RUNNING


# ---------------------------------------------------------------------------------------------- idle engagement
## Handler registered with register_idle: units with an empty queue engage, chase inside the leash and go back.
func on_idle(world: SimWorld, e: SimEntity) -> void:
	if order_type == SimOrder.T_NONE:
		step_idle(world, e)


static func step_idle(world: SimWorld, e: SimEntity) -> void:
	var cc: SimCompCombat = e.combat
	if cc == null or cc.n_mounts == 0 or e.kind != SimEntity.Kind.UNIT or e.air != null:
		return
	if cc.stance == SimCombatConsts.ST_HOLD_FIRE or (cc.cflags & SimCombatConsts.CF_DEAD) != 0:
		return
	var mv: SimCompMove = e.move
	if mv != null and (mv.state == SimMoveConfig.MS_GLIDE or mv.state == SimMoveConfig.MS_EVICT or (e.flags & SimFlags.F_SCRIPTED_MOVE) != 0):
		cc.anchor_on = 0  # scripted movement (exits, docking): not an idle position
		return
	if cc.anchor_on == 0:
		cc.anchor_on = 1
		cc.anchor_x = e.x
		cc.anchor_y = e.y
	var cd: SimCombatDef = world.combat.def_for(world, e)
	if cd == null:
		return
	var t: SimEntity = live_target(world, cc)
	if t != null:
		idle_chase(world, e, cc, cd, t)
		return
	if cc.anchor_on == 2 and cc.hold_pos == 0 and _mobile(world, e):  # 2 = pulled away from the anchor by a chase
		if Fp.dist(cc.anchor_x - e.x, cc.anchor_y - e.y) <= SimCombatConsts.RETURN_SLACK:
			cc.anchor_on = 1
		elif not SimMovement.is_moving(e) and world.tick - mv.goal_tick >= CHASE_GAP:
			SimMovement.go_to(world, e, cc.anchor_x, cc.anchor_y)


## Chase (or hold and turn) for a non-order target: stance decides whether the unit may leave its place.
static func idle_chase(world: SimWorld, e: SimEntity, cc: SimCompCombat, cd: SimCombatDef, t: SimEntity, order_owned: bool = false) -> void:
	var cs: SimCombatSystem = world.combat
	var m: int = best_mount(world, cs, e, cd, t, false)
	if m < 0:
		return
	var range_u: int = cs.range_max_eff(world, e, m)
	var chase: bool = cc.hold_pos == 0 and (cc.stance == SimCombatConsts.ST_AGGRESSIVE or cc.stance == SimCombatConsts.ST_GUARD \
			or (cc.stance == SimCombatConsts.ST_DEFENSIVE and cc.target_src == SimCombatConsts.TS_RETAL))
	if chase and not SimTargeting.within_leash(e, cc, t, range_u):
		chase = false
	# the idle handler stops only chases it started itself (anchor_on 2), never a goal set by a direct movement call
	if engage_move(world, e, cc, cd, t, m, chase, order_owned or cc.anchor_on == 2) and cc.anchor_on == 1 and not order_owned:
		cc.anchor_on = 2


# ---------------------------------------------------------------------------------------------- shared helpers
## The valid auto-style target (AUTO / RETAL / GUARD) of `cc`, else null.
static func live_target(world: SimWorld, cc: SimCompCombat) -> SimEntity:
	if cc.target_id < 0 or cc.ground_on == 1:
		return null
	var src: int = cc.target_src
	if src != SimCombatConsts.TS_AUTO and src != SimCombatConsts.TS_RETAL and src != SimCombatConsts.TS_GUARD:
		return null
	var t: SimEntity = world.get_entity(cc.target_id)
	if t == null or (t.flags & SimFlags.F_GONE) != 0:
		return null
	return t


static func salvo_sum(cc: SimCompCombat, cd: SimCombatDef) -> int:
	var n: int = 0
	for m: int in cd.n_mounts:
		n += cc.mnt[m * SimCombatConsts.MS + SimCombatConsts.M_DOT]
	return n


static func _is_air(e: SimEntity) -> bool:
	return e.air != null and e.air.is_airfield == 0


static func _mobile(world: SimWorld, e: SimEntity) -> bool:
	return e.move != null and e.move.mc < MapTerrain.MC_AIR_FIXED and e.kind == SimEntity.Kind.UNIT and not world.movement.is_immobile(world, e)


## The mount with the longest effective range among those that can engage `t` (-1 = none).
static func best_mount(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cd: SimCombatDef, t: SimEntity, force: bool) -> int:
	var best: int = -1
	var best_r: int = -1
	for m: int in cd.n_mounts:
		if not SimTargeting.can_engage(world, e, cd, m, t, force):
			continue
		var r: int = cs.range_max_eff(world, e, m)
		if r > best_r:
			best_r = r
			best = m
	return best


## Moves the unit to where mount `m` can shoot `t`: chase when too far (if `chase`), back off inside the minimum
## range, stop at the shooting position (if `stop_ok`), turn a fixed mount toward the target. Returns true when it
## issued a movement goal (the idle handler then marks the unit as pulled away from its anchor).
static func engage_move(world: SimWorld, e: SimEntity, cc: SimCompCombat, cd: SimCombatDef, t: SimEntity, m: int, chase: bool, stop_ok: bool = true) -> bool:
	if not _mobile(world, e):
		_face_if_needed(world, e, cd, m, t.x, t.y)
		return false
	var cs: SimCombatSystem = world.combat
	var mv: SimCompMove = e.move
	var tick: int = world.tick
	var visible: bool = world.fog.entity_visible(e.owner, t)
	var tx: int = t.x if visible else cc.seen_x
	var ty: int = t.y if visible else cc.seen_y
	var range_u: int = cs.range_max_eff(world, e, m)
	var rmin: int = cs.range_min_of(world, e, m)
	var d: int = Fp.dist(tx - e.x, ty - e.y)
	if visible:
		d = maxi(d - t.radius, 0)
	var want: int = maxi(SimDamage.mul(range_u, SimCombatConsts.APPROACH_BP), rmin + BACKOFF_EXTRA)
	var approaching: bool = (mv.goal_kind == SimMoveConfig.GK_APPROACH and mv.goal_target == t.id) \
			or (mv.goal_kind == SimMoveConfig.GK_NEAR and Fp.dist(mv.goal_x - tx, mv.goal_y - ty) <= 2048)
	var ended: bool = mv.state == SimMoveConfig.MS_IDLE or mv.state == SimMoveConfig.MS_ARRIVED or mv.state == SimMoveConfig.MS_NO_PATH
	if d > range_u:
		if chase and (not approaching or (ended and tick - mv.goal_tick >= CHASE_GAP)):
			if visible:
				return SimMovement.approach_entity(world, e, t.id, want)
			return SimMovement.go_near(world, e, tx, ty, want)
		return false
	if rmin > 0 and d < rmin and chase:
		if tick - mv.goal_tick >= CHASE_GAP and not SimMovement.is_moving(e):
			var dx: int = e.x - tx
			var dy: int = e.y - ty
			var dl: int = maxi(Fp.dist(dx, dy), 1)
			var back: int = rmin + BACKOFF_EXTRA
			return SimMovement.go_to(world, e, tx + dx * back / dl, ty + dy * back / dl)
		return false
	if stop_ok and approaching and SimMovement.is_moving(e) and (cd.pf(m, SimWeaponProfile.PF_SETTLE) > 0 or d <= want):
		SimMovement.stop(world, e, false)
		return false
	if not SimMovement.is_moving(e):
		_face_if_needed(world, e, cd, m, tx, ty)
	return false


## A fixed (hull) mount that does not cover the bearing: turn the hull. Turreted mounts aim by themselves.
static func _face_if_needed(world: SimWorld, e: SimEntity, cd: SimCombatDef, m: int, tx: int, ty: int) -> void:
	if m < 0 or e.move == null or e.move.mc >= MapTerrain.MC_AIR_FIXED or e.move.state == SimMoveConfig.MS_FACING:
		return
	if cd.mount_val(m, SimCombatDef.MT_TURN) > 0:
		return
	var half: int = cd.mount_val(m, SimCombatDef.MT_ARC_HALF)
	if half >= Fp.ANGLE_HALF:
		return
	var center: int = cd.mount_val(m, SimCombatDef.MT_ARC_CENTER)
	var bearing: int = Fp.atan2(ty - e.y, tx - e.x)
	var rel: int = SimCombatConsts.wrap_signed(bearing - e.facing - center)
	if absi(rel) > maxi(half - cd.mount_val(m, SimCombatDef.MT_AIM_TOL), 0):
		SimMovement.turn_to(world, e, bearing - center)


# ---------------------------------------------------------------------------------------------- command executors
## CMD_SET_STANCE: mode 0..3 (aggressive / defensive / hold fire / guard). A new stance re-anchors the unit.
static func cmd_set_stance(world: SimWorld, c: SimCommand) -> int:
	if c.mode < 0 or c.mode > SimCombatConsts.ST_GUARD:
		return SimCommand.Err.BAD_FIELD
	var ok: bool = false
	for e: SimEntity in c.actors:
		if e.combat == null or e.combat.n_mounts == 0:
			continue
		world.combat.set_stance(e, c.mode)
		e.combat.anchor_on = 0
		if c.mode == SimCombatConsts.ST_HOLD_FIRE:
			SimTargeting.clear_target(e, true)
		ok = true
	return SimCommand.Err.OK if ok else SimCommand.Err.NO_ACTORS


## CMD_SCUTTLE: own units only (structures use sell); no wreck, no salvage.
static func cmd_scuttle(world: SimWorld, c: SimCommand) -> int:
	for e: SimEntity in c.actors:
		world.combat.scuttle(world, e)
	return SimCommand.Err.OK
