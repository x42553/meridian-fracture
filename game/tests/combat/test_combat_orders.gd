extends RefCounted
## CB-06: combat commands and order handlers on the REAL kernel, movement and combat systems. U-ORD-1..5, command
## validation, stances, idle engagement, determinism of a command mix.

const C: int = SimConfig.CELL


func _world(n: int = 2, teams: PackedInt32Array = PackedInt32Array()) -> SimWorld:
	var w: SimWorld = CombatWK.world(n, 4242, teams)
	CombatWK.set_matrix_all(w, 10000)
	return w


func _at(w: SimWorld, e: SimEntity, cx: int, cy: int) -> void:
	w.set_pos(e, cx * C + C / 2, cy * C + C / 2, true)


## A target that never shoots back and does not die from stray fire.
func _quiet(e: SimEntity, hp: int = 400) -> SimEntity:
	e.combat.stance = SimCombatConsts.ST_HOLD_FIRE
	CombatWK.set_hp(e, hp)
	return e


func _sim_tank(w: SimWorld, cx: int, cy: int, owner: int = 0) -> SimEntity:
	var tk: SimEntity = CombatWK.tank(w, owner, cx, cy)
	CombatWK.make_hitscan(w, tk, 100, 10, 7168)
	return tk


func _order_of(e: SimEntity) -> SimOrder:
	return e.orders[0] if not e.orders.is_empty() else null


func _fires(w: SimWorld) -> int:
	return CombatWK.evs(w, SimCombatConsts.EV_FIRE).size()


# ---------------------------------------------------------------------------------------------- U-ORD-1
func test_ord_1_attack_chases_and_fires(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = _sim_tank(w, 30, 40)
	var foe: SimEntity = _quiet(CombatWK.rifle(w, 1, 48, 40))
	var start: int = tk.x
	w.submit_raw(0, SimCmd.attack([tk.id], foe.id))
	w.run(6)
	t.eq([tk.orders.size(), tk.orders[0].type], [1, SimOrder.T_ATTACK], "ATTACK order queued and running")
	t.eq([tk.combat.target_id, tk.combat.target_src], [foe.id, SimCombatConsts.TS_ORDER], "explicit target, order source")
	t.check(SimMovement.is_moving(tk), "out of range: chases")
	for _i: int in 900:
		w.step()
		if not w.is_alive(foe.id):
			break
	t.check(not w.is_alive(foe.id), "the target was destroyed")
	t.gt(tk.x, start + 8 * C, "it drove towards the target first")
	t.gt(_fires(w), 0, "and fired")
	w.run(3)
	t.check(tk.orders.is_empty(), "the order is DONE when the target dies")
	t.eq(tk.combat.target_id, -1, "no leftover target")


func test_ord_1_fixed_mount_turns_the_hull(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = _sim_tank(w, 40, 40)
	CombatWK.mt_set(w, tk, 0, {SimCombatDef.MT_TURN: 0, SimCombatDef.MT_ARC_HALF: 128})
	var foe: SimEntity = _quiet(CombatWK.rifle(w, 1, 35, 40))  # behind the tank (it faces +x)
	w.submit_raw(0, SimCmd.attack([tk.id], foe.id))
	w.run(4)
	t.eq(tk.move.state, SimMoveConfig.MS_FACING, "in range but outside the arc: it turns in place")
	for _i: int in 200:
		w.step()
		if not w.is_alive(foe.id):
			break
	t.check(not w.is_alive(foe.id), "and fires once it points at the target")
	t.check(absi(SimSteering.angle_err(2048, tk.facing)) < 300, "hull now faces west (%d)" % tk.facing)
	t.lt(absi(tk.x - (40 * C + C / 2)), C, "it did not drive off")


func test_ord_1_min_range_backoff_and_not_engageable(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = _sim_tank(w, 40, 40)
	CombatWK.slot_set(w, DefTestKit.U_TANK, 0, {"min_range": 4 * C})
	var foe: SimEntity = _quiet(CombatWK.rifle(w, 1, 42, 40))  # 2 cells: inside the minimum range
	w.submit_raw(0, SimCmd.attack([tk.id], foe.id))
	w.run(40)
	t.gt(Fp.dist(foe.x - tk.x, foe.y - tk.y), 3 * C, "backs off inside the minimum range")
	# a target that no mount can hit any more fails the order
	var w2: SimWorld = _world()
	var t2: SimEntity = _sim_tank(w2, 40, 40)
	var sub: SimEntity = _quiet(CombatWK.rifle(w2, 1, 44, 40))
	w2.submit_raw(0, SimCmd.attack([t2.id], sub.id))
	w2.run(3)
	w2.set_layer(sub, SimCombatConsts.LAYER_UNDERWATER)
	w2.run(3)
	t.check(t2.orders.is_empty(), "target no longer engageable: the order ended")
	t.gt(CombatWK.evs(w2, SimEvent.ORDER_FAILED).size(), 0, "as a failure (ORDER_FAILED)")


# ---------------------------------------------------------------------------------------------- U-ORD-2
func test_ord_2_attack_move_engages_then_resumes(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = _sim_tank(w, 30, 40)
	CombatWK.prof_set(w, tk, 0, {SimWeaponProfile.PF_SETTLE: 6})  # stationary-fire weapon: must stop to shoot
	var foe: SimEntity = _quiet(CombatWK.rifle(w, 1, 44, 43), 400)
	w.submit_raw(0, SimCmd.attack_move([tk.id], 70 * C, 40 * C))
	var saw_engage: bool = false
	var stopped_x: int = -1
	for _i: int in 300:
		w.step()
		var o: SimOrder = _order_of(tk)
		if o != null and o.p1 == SimCombatConsts.AM_ENGAGE:
			saw_engage = true
			stopped_x = tk.x
		if not w.is_alive(foe.id):
			break
	t.check(saw_engage, "sees an enemy on the way: stops and engages (AM_ENGAGE)")
	t.check(not w.is_alive(foe.id), "and destroys it")
	t.lt(stopped_x, 60 * C, "it did not run past the enemy")
	var x_dead: int = tk.x
	w.run(60)
	var o2: SimOrder = _order_of(tk)
	t.check(o2 != null and o2.p1 == SimCombatConsts.AM_MOVE, "no target for 10 ticks: back to AM_MOVE")
	t.gt(tk.x, x_dead, "and moving on")
	for _i: int in 900:
		w.step()
		if tk.orders.is_empty():
			break
	t.check(tk.orders.is_empty(), "arrival ends the order")
	t.lt(Fp.dist(70 * C - tk.x, 40 * C - tk.y), 1600, "at the destination")


func test_ord_2_attack_move_keeps_moving_when_weapons_fire_on_the_move(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = _sim_tank(w, 30, 40)
	var foe: SimEntity = _quiet(CombatWK.rifle(w, 1, 40, 42), 100000)
	w.submit_raw(0, SimCmd.attack_move([tk.id], 60 * C, 40 * C))
	var engaged: bool = false
	for _i: int in 200:
		w.step()
		var o: SimOrder = _order_of(tk)
		if o != null and o.p1 == SimCombatConsts.AM_ENGAGE:
			engaged = true
	t.check(not engaged, "every mount fires on the move: the unit never stops")
	t.gt(tk.x, 45 * C, "it drove past while shooting")
	t.gt(_fires(w), 0, "and shot")
	t.check(foe.hp < 100000, "the enemy took damage")


# ---------------------------------------------------------------------------------------------- U-ORD-3
func test_ord_3_guard_leash_and_return(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = _sim_tank(w, 40, 40)
	var near: SimEntity = _quiet(CombatWK.rifle(w, 1, 40, 49))  # 9 cells: inside the guard radius, needs a chase
	var far: SimEntity = _quiet(CombatWK.rifle(w, 1, 40, 24), 400)  # 16 cells north: outside every radius
	w.submit_raw(0, SimCmd.guard([tk.id], 0, 40 * C + C / 2, 40 * C + C / 2))
	w.run(2)
	t.eq(tk.combat.stance, SimCombatConsts.ST_GUARD, "guarding switches to the guard stance")
	var max_d: int = 0
	for _i: int in 500:
		w.step()
		max_d = maxi(max_d, Fp.dist(tk.x - (40 * C + C / 2), tk.y - (40 * C + C / 2)))
	t.check(not w.is_alive(near.id), "the intruder inside the guard radius was engaged")
	t.check(w.is_alive(far.id), "the far one was never touched")
	t.le(max_d, 6144 + 1024, "the chase stayed inside the leash (%d)" % max_d)
	t.lt(Fp.dist(tk.x - (40 * C + C / 2), tk.y - (40 * C + C / 2)), 2048 + 1024, "and it returned to its post")
	t.eq(tk.orders.size(), 1, "guard runs until replaced")
	w.submit_raw(0, SimCmd.stop([tk.id]))
	w.run(2)
	t.eq(tk.combat.stance, SimCombatConsts.ST_AGGRESSIVE, "stop restores the stance")


func test_ord_3_guard_unit_ends_when_it_dies(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var g: SimEntity = CombatWK.tank(w, 0, 40, 40)
	var buddy: SimEntity = CombatWK.rifle(w, 0, 43, 40)
	var foe_side: SimEntity = CombatWK.tank(w, 1, 20, 20)
	t.check(foe_side != null, "spawned")
	w.submit_raw(0, SimCmd.guard([g.id], buddy.id))
	w.run(3)
	t.eq(g.orders[0].type, SimOrder.T_GUARD, "guarding a friendly unit")
	w.set_pos(buddy, buddy.x + 12 * C, buddy.y, true)
	w.run(110)
	t.check(Fp.dist(g.x - buddy.x, g.y - buddy.y) < 5 * C, "an idle guard follows the guarded unit (%d)" % Fp.dist(g.x - buddy.x, g.y - buddy.y))
	w.kill(buddy, SimWorld.Cause.SCRIPT)
	w.run(3)
	t.check(g.orders.is_empty(), "guarded unit dead: order done")


# ---------------------------------------------------------------------------------------------- U-ORD-4
func test_ord_4_hold_does_not_chase(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = _sim_tank(w, 40, 40)
	var foe: SimEntity = _quiet(CombatWK.rifle(w, 1, 50, 40), 100000)  # 10 cells: out of range
	w.submit_raw(0, SimCmd.hold([tk.id]))
	w.run(120)
	t.eq(tk.combat.hold_pos, 1, "hold_pos set")
	t.eq([tk.x, tk.y], [40 * C + C / 2, 40 * C + C / 2], "never moved")
	t.eq(_fires(w), 0, "nothing in range: no shot")
	_at(w, foe, 45, 40)  # 5 cells: in range
	w.run(40)
	t.gt(_fires(w), 0, "fires at what comes into range")
	t.eq([tk.x, tk.y], [40 * C + C / 2, 40 * C + C / 2], "still holding")
	w.submit_raw(0, SimCmd.move([tk.id], 30 * C, 40 * C))
	w.run(2)
	t.eq(tk.combat.hold_pos, 0, "any other order clears hold_pos")


# ---------------------------------------------------------------------------------------------- U-ORD-5
func test_ord_5_force_fire_ground_hurts_friendlies(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = CombatWK.tank(w, 0, 30, 40)
	var mine: SimEntity = CombatWK.rifle(w, 0, 34, 40)
	var hp0: int = mine.hp
	w.submit_raw(0, SimCmd.force_fire([tk.id], 0, mine.x, mine.y, 1))
	w.run(4)
	t.eq(tk.orders[0].type, SimOrder.T_FORCE_FIRE, "force-fire on the ground")
	t.eq(tk.combat.ground_on, 1, "ground point mode")
	w.run(80)
	t.gt(_fires(w), 0, "the tank fired")
	t.lt(mine.hp, hp0, "splash hurts the friendly unit standing there")
	t.check(tk.orders.is_empty(), "count 1: the order ended after one salvo")
	t.eq(tk.combat.ground_on, 0, "ground target dropped")
	# an entity target of any relation: force-fire at an allied unit is accepted
	var friend: SimEntity = CombatWK.rifle(w, 0, 33, 44)
	w.submit_raw(0, SimCmd.force_fire([tk.id], friend.id))
	w.run(3)
	t.eq([tk.combat.target_id, tk.combat.target_src], [friend.id, SimCombatConsts.TS_FORCE], "entity force-fire: TS_FORCE")


# ---------------------------------------------------------------------------------------------- commands
func _exec(w: SimWorld, pid: int, ints: PackedInt32Array) -> int:
	var c: SimCommand = SimCommand.from_ints(pid, ints)
	if c == null:
		return SimCommand.Err.UNKNOWN_OP
	return w.commands.execute(w, c)


func test_command_validation(t: TestCtx) -> void:
	var w: SimWorld = _world(3, PackedInt32Array([1, 2, 1]))  # pid 2 is allied with pid 0
	var tk: SimEntity = CombatWK.tank(w, 0, 30, 30)
	var rf: SimEntity = CombatWK.rifle(w, 0, 31, 30)
	var col: SimEntity = CombatWK.unit(w, DefTestKit.U_COLLECTOR, 0, 32, 30)
	var foe: SimEntity = CombatWK.tank(w, 1, 50, 30)
	var ally: SimEntity = CombatWK.tank(w, 2, 40, 40)
	var neutral: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_RIFLEMAN), -1, 60 * C, 60 * C)
	var Err: Variant = SimCommand.Err
	t.eq(_exec(w, 0, SimCmd.attack([tk.id], foe.id)), Err.OK, "attack an enemy")
	t.eq(tk.orders[0].type, SimOrder.T_ATTACK, "order created")
	t.eq(_exec(w, 0, SimCmd.attack([tk.id], ally.id)), Err.NOT_ALLOWED, "attacking an ally is refused")
	t.eq(_exec(w, 0, SimCmd.attack([tk.id], rf.id)), Err.NOT_ALLOWED, "attacking an own unit is refused")
	t.eq(_exec(w, 0, SimCmd.attack([tk.id], neutral.id)), Err.NOT_ALLOWED, "a neutral only by force-fire")
	t.eq(_exec(w, 0, SimCmd.attack([tk.id], rf.id, 0, 1)), Err.OK, "the forced flag allows own targets")
	t.eq(_exec(w, 0, SimCmd.attack([tk.id], 987654)), Err.NO_TARGET, "unknown target")
	t.eq(_exec(w, 0, SimCmd.attack([col.id], foe.id)), Err.NOT_ALLOWED, "an unarmed unit cannot attack")
	t.eq(_exec(w, 1, SimCmd.attack([tk.id], ally.id)), Err.NO_ACTORS, "not the issuer's units")
	var mixed: int = _exec(w, 0, SimCmd.attack([col.id, rf.id], foe.id))
	t.eq(mixed, Err.OK, "a mixed group: the unarmed member is skipped")
	t.eq([col.orders.size(), rf.orders.size()], [0, 1], "only the armed unit got the order")
	var wreck: SimEntity = w.spawn_wreck(foe, true, 100, 1200)
	t.eq(_exec(w, 0, SimCmd.attack([tk.id], wreck.id)), Err.WRONG_KIND, "a wreck is force-fire only")
	t.eq(_exec(w, 0, SimCmd.force_fire([tk.id], wreck.id)), Err.OK, "force-fire accepts the wreck")
	t.eq(_exec(w, 0, SimCmd.attack_move([tk.id], 96 * C + 5, 10 * C)), Err.BAD_FIELD, "attack-move out of the map")
	t.eq(_exec(w, 0, SimCmd.attack_move([tk.id], 60 * C, 30 * C)), Err.OK, "attack-move inside")
	t.eq(_exec(w, 0, SimCmd.guard([tk.id], foe.id)), Err.NOT_ALLOWED, "guarding an enemy is refused")
	t.eq(_exec(w, 0, SimCmd.guard([tk.id], ally.id)), Err.OK, "guarding an ally is accepted")
	t.eq(_exec(w, 0, SimCmd.force_fire([tk.id], 987654)), Err.NO_TARGET, "force-fire at nothing")
	t.eq(_exec(w, 0, SimCmd.force_fire([tk.id], 0, 50 * C, 50 * C)), Err.OK, "force-fire at the ground")
	t.eq(_exec(w, 0, SimCmd.hold([tk.id])), Err.OK, "hold")
	t.eq(_exec(w, 0, SimCmd.return_to_base([tk.id])), Err.NOT_ALLOWED, "return to base is for aircraft")
	t.eq(_exec(w, 0, SimCmd.set_stance([tk.id], 9)), Err.BAD_FIELD, "stance 0..3 only")
	t.eq(_exec(w, 0, SimCmd.set_stance([tk.id], SimCombatConsts.ST_DEFENSIVE)), Err.OK, "set stance")
	t.eq(tk.combat.stance, SimCombatConsts.ST_DEFENSIVE, "stance stored")
	t.eq(_exec(w, 0, SimCmd.set_stance([col.id], 1)), Err.NO_ACTORS, "unarmed units have no stance")


func test_scuttle_and_hold_fire_stance(t: TestCtx) -> void:
	var w: SimWorld = _world()
	w.combat.salvage_enabled = 1
	var tk: SimEntity = CombatWK.unit(w, DefTestKit.U_TANK, 0, 30, 30)
	tk.paid_cost = 850
	w.submit_raw(0, SimCmd.scuttle([tk.id]))
	w.run(2)
	t.check(CombatWK.dead(tk) or w.get_entity(tk.id) == null, "scuttled")
	t.eq(CombatWK.evs(w, SimCombatConsts.EV_WRECK_ADD).size(), 0, "a scuttled unit leaves no wreck")
	var deaths: Array[PackedInt32Array] = CombatWK.evs(w, SimCombatConsts.EV_DEATH)
	t.eq((deaths[0][SimEvent.I_C] >> 4) & 15, SimCombatConsts.CAUSE_SCUTTLE, "EV_DEATH carries the scuttle cause")
	# hold fire: never shoots on its own but obeys an explicit attack
	var a: SimEntity = _sim_tank(w, 50, 50)
	var foe: SimEntity = _quiet(CombatWK.rifle(w, 1, 54, 50), 100000)
	w.submit_raw(0, SimCmd.set_stance([a.id], SimCombatConsts.ST_HOLD_FIRE))
	w.run(60)
	t.eq(_fires(w), 0, "hold fire: silent")
	w.submit_raw(0, SimCmd.attack([a.id], foe.id))
	w.run(20)
	t.gt(_fires(w), 0, "but an attack order is obeyed")


# ---------------------------------------------------------------------------------------------- idle engagement
func test_idle_unit_chases_inside_leash_and_returns(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = _sim_tank(w, 40, 40)
	var foe: SimEntity = _quiet(CombatWK.rifle(w, 1, 40, 48))  # 8 cells: acquired (range 7 + 2), needs a chase
	w.run(1)
	t.eq(tk.combat.anchor_on, 1, "the idle position is remembered as the anchor")
	var moved: bool = false
	for _i: int in 400:
		w.step()
		moved = moved or SimMovement.is_moving(tk)
	t.check(moved, "an aggressive idle unit chases")
	t.check(not w.is_alive(foe.id), "and kills")
	t.lt(Fp.dist(tk.x - (40 * C + C / 2), tk.y - (40 * C + C / 2)), 2048 + 1024, "then walks back to its anchor")
	# defensive stance does not chase a target that never attacked it
	var w2: SimWorld = _world()
	var d: SimEntity = _sim_tank(w2, 40, 40)
	d.combat.stance = SimCombatConsts.ST_DEFENSIVE
	var foe2: SimEntity = _quiet(CombatWK.rifle(w2, 1, 40, 46), 100000)
	w2.run(150)
	t.check(w2.is_alive(foe2.id) and Fp.dist(d.x - (40 * C + C / 2), d.y - (40 * C + C / 2)) < 512, "defensive: no chase")


func test_command_mix_is_deterministic(t: TestCtx) -> void:
	var sums: Array[int] = []
	for _r: int in 2:
		var w: SimWorld = _world()
		var tk: SimEntity = _sim_tank(w, 30, 40)
		var rf: SimEntity = CombatWK.rifle(w, 0, 31, 44)
		var e1: SimEntity = CombatWK.rifle(w, 1, 50, 40)
		var e2: SimEntity = CombatWK.tank(w, 1, 52, 44)
		w.submit_raw(0, SimCmd.attack_move([tk.id, rf.id], 55 * C, 42 * C))
		w.run(60)
		w.submit_raw(1, SimCmd.guard([e1.id], 0, 50 * C, 40 * C))
		w.submit_raw(0, SimCmd.attack([tk.id], e2.id, 1))
		w.run(60)
		w.submit_raw(1, SimCmd.hold([e2.id]))
		w.submit_raw(0, SimCmd.force_fire([rf.id], 0, 50 * C, 40 * C, 2))
		w.run(200)
		sums.append(w.checksum())
	t.eq(sums[0], sums[1], "same commands, same checksum")


func test_lock_weapons_api(t: TestCtx) -> void:
	var w: SimWorld = _world()
	var tk: SimEntity = _sim_tank(w, 40, 40)
	var foe: SimEntity = _quiet(CombatWK.rifle(w, 1, 44, 40), 100000)
	w.combat.lock_weapons(w, tk, w.tick + 30)
	t.check((tk.flags & SimFlags.F_WEAPONS_OFF) != 0, "weapons-off mirror set")
	w.run(25)
	t.eq(_fires(w), 0, "locked: silent")
	w.run(30)
	t.gt(_fires(w), 0, "fires again after the lock")
	t.check((tk.flags & SimFlags.F_WEAPONS_OFF) == 0, "mirror cleared by the upkeep")
	t.check(foe.hp < 100000, "and hits")
