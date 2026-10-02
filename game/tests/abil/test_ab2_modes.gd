extends RefCounted
## AB-04 on the REAL balance data: deploy / pack (S01), deployed leases (S02), submarine surfacing (S06), the sensor mast,
## mode_switch, the mode commands with their reject reasons, the want_* / ext_* protocol.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")
const PAL: String = "unit.napc.paladin_howitzer"
const CHARL: String = "unit.nec.charlemagne_siege_tank"
const BOREAL: String = "unit.def.boreal_missile_submarine"
const FEN: String = "unit.nec.fen_recon_carrier"
const SHINANO: String = "unit.pd.shinano_adaptive_tank"


func _deploy(w: SimWorld, e: SimEntity, slot: int = -1) -> void:
	w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [slot], PackedInt32Array([e.id])))


func test_s01_deploy_and_pack(t: TestCtx) -> void:
	var w: SimWorld = A.world()
	if not t.not_null(w, "world"):
		return
	var p: SimEntity = A.spawn(w, PAL, 0, 20, 20)
	t.eq(p.abil.n_slots, 1, "paladin has one slot")
	t.eq(p.abil.slots[K.SL_KIND], K.AK_DEPLOY, "deploy slot")
	t.eq(p.abil.slots[K.SL_AUX0], -1, "no transition yet")
	_deploy(w, p)
	w.step()  # tick 0: the command is executed in stage 1
	t.check(SimStats.has_flag(p, K.DF_IMMOBILE), "DF_IMMOBILE from tick 0")
	t.check(w.abilities.is_immobile(p), "movement adapter sees it")
	t.check((p.flags & SimFlags.F_DEPLOYING) != 0, "F_DEPLOYING mirror")
	t.eq(p.combat.ext_deployed, 0, "not deployed yet")
	A.run_to(w, 60)
	t.eq(p.combat.ext_deployed, 0, "ext_deployed = 0 until tick 60")
	w.step()  # tick 60
	t.eq(p.combat.ext_deployed, 1, "ext_deployed = 1 at tick 60")
	t.check((p.flags & SimFlags.F_DEPLOYED) != 0 and (p.flags & SimFlags.F_DEPLOYING) == 0, "F_DEPLOYED mirror")
	t.eq(A.count_events(w, K.EV_MODE_CHANGED, p.id), 1, "EV_MODE_CHANGED once")
	t.eq(A.count_events(w, K.EV_MODE_STARTED, p.id), 1, "EV_MODE_STARTED once")
	t.check(SimStats.has_flag(p, K.DF_IMMOBILE), "still immobile while deployed")
	# a move order at tick 100 asks to pack first (pack_t = 40)
	A.run_to(w, 100)
	var x0: int = p.x
	w.submit_raw(0, SimCmd.build(SimCmd.MOVE, [40 * 1024, 20 * 1024 + 512, 0, 0], PackedInt32Array([p.id])))
	w.step()  # tick 100
	t.eq(p.combat.ext_deployed, 0, "ext_deployed = 0 at once when packing starts")
	t.check(w.abilities.is_immobile(p), "packing keeps the unit immobile")
	A.run_to(w, 139)
	t.eq(p.x, x0, "no movement while packing")
	A.run_to(w, 160)
	t.check(not w.abilities.is_immobile(p), "packed and free to move")
	t.gt(p.x, x0, "movement resumed after the pack")
	t.eq(w.abilities.debug_validate(w).size(), 0, "debug_validate clean")


func test_deploy_command_rejects(t: TestCtx) -> void:
	var w: SimWorld = A.world()
	var p: SimEntity = A.spawn(w, PAL, 0, 20, 20)
	var rifle: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 22, 20)
	# a unit without a deploy slot -> WRONG_KIND with RJ_NO_SLOT
	var c: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([rifle.id])))
	c.actors = [rifle]
	var err: int = SimAbilityCmds.execute(w, c)
	t.eq(err, SimCommand.Err.WRONG_KIND, "no slot -> WRONG_KIND")
	t.eq(c.detail, SimAbilityEvents.RJ_NO_SLOT, "reason NO_SLOT")
	# deploy, then deploy again -> BAD_STATE
	var c2: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([p.id])))
	c2.actors = [p]
	t.eq(SimAbilityCmds.execute(w, c2), SimCommand.Err.OK, "first deploy accepted")
	t.eq(SimAbilityCmds.execute(w, c2), SimCommand.Err.NOT_ALLOWED, "second while transitioning refused")
	t.eq(c2.detail, SimAbilityEvents.RJ_BAD_STATE, "reason BAD_STATE")
	A.run(w, 70)
	t.eq(SimAbilityCmds.execute(w, c2), SimCommand.Err.NOT_ALLOWED, "deploy while deployed refused")
	# an unknown slot
	var c3: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.DEPLOY, [5], PackedInt32Array([p.id])))
	c3.actors = [p]
	t.eq(SimAbilityCmds.execute(w, c3), SimCommand.Err.WRONG_KIND, "slot 5 does not exist")
	# undeploy
	var c4: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.UNDEPLOY, [0], PackedInt32Array([p.id])))
	c4.actors = [p]
	t.eq(SimAbilityCmds.execute(w, c4), SimCommand.Err.OK, "undeploy accepted")
	A.run(w, 45)
	t.eq(p.combat.ext_deployed, 0, "packed")
	t.check(not SimStats.has_flag(p, K.DF_IMMOBILE), "mobile again")
	t.check((p.flags & SimFlags.F_DEPLOYED) == 0, "F_DEPLOYED cleared")


func test_deploy_refused_when_shut_down(t: TestCtx) -> void:
	var w: SimWorld = A.world()
	var p: SimEntity = A.spawn(w, PAL, 0, 20, 20)
	p.combat.emp_until = w.tick + 200
	var c: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([p.id])))
	c.actors = [p]
	t.eq(SimAbilityCmds.execute(w, c), SimCommand.Err.DISABLED, "EMP-shut unit cannot deploy")
	t.eq(c.detail, SimAbilityEvents.RJ_DISABLED, "reason DISABLED")


func test_s02_deployed_leases_and_turn_lock(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.eurocorps"]})
	var ch: SimEntity = A.spawn(w, CHARL, 1, 30, 30)
	var base_range: int = w.combat.range_max_eff(w, ch)
	t.gt(base_range, 0, "charlemagne has a weapon range")
	w.submit_raw(1, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([ch.id])))
	A.run_to(w, 80)
	t.eq(A.lease_bp(w, ch, SimCombatConsts.STAT_RANGE), 0, "no lease before completion")
	t.check(not w.abilities.is_turn_locked(ch), "not turn locked yet")
	w.step()  # tick 80
	t.eq(A.lease_bp(w, ch, SimCombatConsts.STAT_RANGE), 2500, "deployed range lease +2500")
	t.check(w.abilities.is_turn_locked(ch), "turn locked once deployed")
	t.gt(w.combat.range_max_eff(w, ch), base_range, "range grew")
	# an extra lease (Armored Overwatch style) adds up to +3500
	SimCombatMods.apply(w, ch, K.fxk(K.SRC_RESEARCH, 5), SimCombatConsts.STAT_RANGE, 1000, 0, 100000)
	t.eq(A.lease_bp(w, ch, SimCombatConsts.STAT_RANGE), 3500, "aggregate +3500")
	# pack drops the deployed lease only
	w.submit_raw(1, SimCmd.build(SimCmd.UNDEPLOY, [-1], PackedInt32Array([ch.id])))
	w.step()
	t.eq(A.lease_bp(w, ch, SimCombatConsts.STAT_RANGE), 1000, "the deploy lease ended with the pack request")
	t.check(not w.abilities.is_turn_locked(ch), "turn lock lifted")


func test_want_deploy_auto_deploy(t: TestCtx) -> void:
	var w: SimWorld = A.world()
	var p: SimEntity = A.spawn(w, PAL, 0, 20, 20)
	# combat asks (level) - the unit deploys itself
	p.combat.want_deploy = 1
	w.step()
	t.check(SimStats.has_flag(p, K.DF_IMMOBILE), "want_deploy starts the deploy")
	A.run_to(w, 61)
	t.eq(p.combat.ext_deployed, 1, "deployed for combat")


func test_s06_submarine(t: TestCtx) -> void:
	var rows: PackedStringArray = A.MV.grid(64)
	A.MV.rect(rows, 10, 10, 40, 40, "~")
	var w: SimWorld = A.world({"rows": rows, "rosters": ["roster.def.russia", "roster.nec.vanilla"]})
	var sub: SimEntity = A.spawn(w, BOREAL, 0, 20, 20)
	t.eq(sub.layer, SimEntity.Layer.UNDERWATER, "starts submerged")
	t.eq(sub.vis.concealed, 1, "concealed while submerged")
	for tk: int in 51:  # want_surface = 1 from tick 0 to tick 50
		sub.combat.want_surface = 1
		w.step()
		if tk == 0:
			t.eq(sub.vis.concealed, 0, "concealment ends at once")
		if tk == 19:
			t.eq(sub.layer, SimEntity.Layer.UNDERWATER, "layer unchanged while SURFACING (tick 19 done)")
		if tk == 20:
			t.eq(sub.layer, SimEntity.Layer.SURFACE, "layer SURFACE at tick 20")
	t.eq(sub.layer, SimEntity.Layer.SURFACE, "surfaced")
	A.run_to(w, 210)
	t.eq(sub.layer, SimEntity.Layer.SURFACE, "stays up until 50 + 160")
	t.eq(A.slot_state(sub, K.AK_SUBMERGE), K.SUB_SURFACED, "state SURFACED")
	w.step()  # tick 210
	t.eq(A.slot_state(sub, K.AK_SUBMERGE), K.SUB_DIVING, "DIVING from tick 210")
	A.run_to(w, 230)
	t.eq(sub.layer, SimEntity.Layer.SURFACE, "still on the surface while diving")
	w.step()  # tick 230
	t.eq(sub.layer, SimEntity.Layer.UNDERWATER, "UNDERWATER at 230")
	t.eq(sub.vis.concealed, 1, "concealed again")
	t.eq(A.slot_state(sub, K.AK_SUBMERGE), K.SUB_SUBMERGED, "state SUBMERGED")


func test_sensor_mast(t: TestCtx) -> void:
	var w: SimWorld = A.world({"fog": true, "rosters": ["roster.napc.usa", "roster.nec.nordics"]})
	var fen: SimEntity = A.spawn(w, FEN, 1, 30, 30)
	var s: int = fen.abil.slot_of_kind(K.AK_SENSOR_MAST)
	t.gt(s, -1, "fen has a sensor mast")
	A.run(w, 4)
	t.eq(fen.vis.det_r, 5, "an undeployed Fen detects 5 cells")
	w.submit_raw(1, SimCmd.build(SimCmd.DEPLOY, [s], PackedInt32Array([fen.id])))
	A.run(w, 39)
	t.check(not SimStats.has_flag(fen, K.DF_EXPOSED), "not exposed while deploying")
	t.check(SimStats.has_flag(fen, K.DF_IMMOBILE), "immobile while deploying")
	A.run(w, 3)
	t.check(SimStats.has_flag(fen, K.DF_EXPOSED), "deployed mast is exposed (camouflage locked)")
	t.eq(A.slot_state(fen, K.AK_SENSOR_MAST), SimMode.MODE_DEPLOYED, "mast deployed")
	t.eq(fen.combat.ext_deployed, 1, "ext_deployed for the deployed mast")
	A.run(w, 4)
	t.eq(fen.vis.det_r, 6, "the deployed mast detects reveal_radius = 6 cells")
	# pack ends the exposure
	w.submit_raw(1, SimCmd.build(SimCmd.UNDEPLOY, [s], PackedInt32Array([fen.id])))
	A.run(w, 60)
	t.check(not SimStats.has_flag(fen, K.DF_EXPOSED), "packed mast hides again")
	t.check(not SimStats.has_flag(fen, K.DF_IMMOBILE), "mobile again")


func test_mode_switch_shinano(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.pd.japan", "roster.nec.vanilla"]})
	var sh: SimEntity = A.spawn(w, SHINANO, 0, 20, 20)
	var s: int = sh.abil.slot_of_kind(K.AK_MODE_SWITCH)
	t.gt(s, -1, "mode_switch slot")
	t.eq(sh.combat.ext_mode, 0, "starts in mode 0")
	w.step()
	t.eq(sh.combat.ext_mode, 0, "mode 0 stable")
	w.submit_raw(0, SimCmd.build(SimCmd.SET_MODE, [s, 1], PackedInt32Array([sh.id])))
	w.step()
	t.eq(sh.combat.ext_mode, -1, "no weapon set during the switch")
	t.check(SimStats.has_flag(sh, K.DF_IMMOBILE), "immobile while switching")
	A.run(w, 58)
	t.eq(sh.combat.ext_mode, -1, "still switching")
	A.run(w, 3)
	t.eq(sh.combat.ext_mode, 1, "mode 1 after switch_t = 60")
	t.check(not SimStats.has_flag(sh, K.DF_IMMOBILE), "mobile after the switch")
	t.eq(A.count_events(w, K.EV_MODE_CHANGED, sh.id), 1, "EV_MODE_CHANGED")
	# cycle (-1) goes back to mode 0
	w.submit_raw(0, SimCmd.build(SimCmd.SET_MODE, [s, -1], PackedInt32Array([sh.id])))
	A.run(w, 70)
	t.eq(sh.combat.ext_mode, 0, "cycle returns to mode 0")
	# the same mode again is a BAD_STATE
	var c: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.SET_MODE, [s, 0], PackedInt32Array([sh.id])))
	c.actors = [sh]
	t.eq(SimAbilityCmds.execute(w, c), SimCommand.Err.NOT_ALLOWED, "already in mode 0")
	t.eq(c.detail, SimAbilityEvents.RJ_BAD_STATE, "reason BAD_STATE")


func test_want_mode_from_combat(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.pd.japan", "roster.nec.vanilla"]})
	var sh: SimEntity = A.spawn(w, SHINANO, 0, 20, 20)
	sh.combat.want_mode = 1
	w.step()
	t.eq(sh.combat.ext_mode, -1, "combat's want_mode starts the switch")
	A.run(w, 62)
	t.eq(sh.combat.ext_mode, 1, "switched")


func test_predictive_maintenance_shortens_switch(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.pd.japan", "roster.nec.vanilla"]})
	var sh: SimEntity = A.spawn(w, SHINANO, 0, 20, 20)
	var r: int = w.data.research_idx("research.pd.predictive_maintenance")
	t.gt(r, -1, "research exists")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	w.submit_raw(0, SimCmd.build(SimCmd.SET_MODE, [0, 1], PackedInt32Array([sh.id])))
	A.run(w, 41)
	t.eq(sh.combat.ext_mode, 1, "switch takes 2 s (40 ticks) after Predictive Maintenance")


func test_mobile_dispatch_instant_pack(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.def.kazakhstan", "roster.nec.vanilla"]})
	var sk: SimEntity = A.spawn(w, "unit.def.saker_missile_truck", 0, 20, 20)
	var r: int = w.data.research_idx("research.def.mobile_dispatch")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([sk.id])))
	A.run(w, 25)
	t.eq(sk.combat.ext_deployed, 1, "saker deploys in 20 ticks")
	w.submit_raw(0, SimCmd.build(SimCmd.UNDEPLOY, [-1], PackedInt32Array([sk.id])))
	w.step()
	t.check(not SimStats.has_flag(sk, K.DF_IMMOBILE), "pack_t 0: mobile at once")
	t.eq(sk.combat.ext_deployed, 0, "packed at once")


func test_modes_determinism(t: TestCtx) -> void:
	var sums: PackedInt64Array = PackedInt64Array()
	for _run: int in 2:
		var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.pd.japan"]})
		var p: SimEntity = A.spawn(w, PAL, 0, 20, 20)
		var sh: SimEntity = A.spawn(w, SHINANO, 1, 30, 30)
		w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([p.id])))
		w.submit_raw(1, SimCmd.build(SimCmd.SET_MODE, [0, 1], PackedInt32Array([sh.id])))
		A.run(w, 150)
		sums.append(w.checksum())
	t.eq(sums[0], sums[1], "double run: identical checksum")


func test_move_order_during_deploy_queues_the_pack(t: TestCtx) -> void:
	var w: SimWorld = A.world()
	var p: SimEntity = A.spawn(w, PAL, 0, 20, 20)
	_deploy(w, p)
	A.run(w, 10)
	var x0: int = p.x
	w.submit_raw(0, SimCmd.build(SimCmd.MOVE, [40 * 1024, 20 * 1024 + 512, 0, 0], PackedInt32Array([p.id])))
	A.run(w, 40)
	t.eq(p.x, x0, "still deploying: no movement")
	A.run_to(w, 62)
	t.eq(A.count_events(w, K.EV_MODE_CHANGED, p.id), 1, "the deploy completed first")
	A.run_to(w, 110)
	t.eq(p.combat.ext_deployed, 0, "and the queued pack started right after it")
	A.run(w, 200)
	t.gt(p.x, x0 + 3 * 1024, "the howitzer drives off after unpacking")
	t.eq(w.abilities.debug_validate(w).size(), 0, "validate")


func test_killed_deployed_unit_leaves_no_state(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.eurocorps"]})
	var ch: SimEntity = A.spawn(w, CHARL, 1, 30, 30)
	w.submit_raw(1, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([ch.id])))
	A.run(w, 90)
	w.kill(ch, SimWorld.Cause.SCRIPT, 0, -1)
	A.run(w, 5)
	t.check(not w.is_alive(ch.id), "removed")
	t.eq(w.abilities.mode_ids.find(ch.id), -1, "and gone from the mode list")
	t.eq(w.abilities.debug_validate(w).size(), 0, "validate")
