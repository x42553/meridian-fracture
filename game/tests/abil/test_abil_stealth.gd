extends RefCounted
## AB-03: camouflage arming, detection and submarines (abilities 10.2 S03 - S06).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const CELL: int = 1024


func _seen(w: SimWorld, pid: int, e: SimEntity) -> bool:
	return w.fog.entity_visible(pid, e)


func test_s03_camouflage_and_detector_radius(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({"players": 4})
	var camo: SimEntity = AbilKit.rifle(w, 0, 30, 30)
	var near: SimEntity = AbilKit.tank(w, 1, 35, 30)  # detector 5 cells: cell distance 5 = inside
	var far: SimEntity = AbilKit.tank(w, 2, 36, 30)  # cell distance 6 = outside
	var eye: SimEntity = AbilKit.rifle(w, 3, 30, 36)  # sees the cell, has no detector
	AbilKit.run_to(w, 100)
	t.eq(camo.vis.concealed, 0, "arming at tick 100")
	t.check(_seen(w, 1, camo) and _seen(w, 2, camo) and _seen(w, 3, camo), "visible to everyone who sees the cell")
	AbilKit.run_to(w, 120)
	t.eq(camo.vis.concealed, 0, "not yet at tick 120 (before its step)")
	w.step()
	t.eq(camo.vis.concealed, 1, "concealed at tick 120 (delay_t 120, stationary since spawn)")
	t.check(_seen(w, 1, camo), "the detector at 5 cells sees it")
	t.check_false(_seen(w, 2, camo), "the one at 6 cells does not")
	t.check_false(_seen(w, 3, camo), "an observer without a detector does not")
	t.check(_seen(w, 0, camo), "the owner always does")
	t.check(w.fog.entity_revealed(1, camo) and not w.fog.entity_revealed(2, camo), "entity_revealed = detection only")
	# firing at tick 300 decloaks at 301, re-cloaks at 420 while stationary
	AbilKit.run_to(w, 301)
	camo.combat.last_fire_tick = 300
	w.step()
	t.eq(camo.vis.concealed, 0, "decloaked at tick 301")
	AbilKit.run_to(w, 420)
	t.eq(camo.vis.concealed, 0, "still visible before 420")
	w.step()
	t.eq(camo.vis.concealed, 1, "re-cloaked at tick 420")
	# moving resets combat's still_ticks: the re-arming needs delay_t quiet ticks
	camo.combat.ext_moving = 1
	w.run(2)
	t.eq(camo.vis.concealed, 0, "moving decloaks a stationary-only camouflage")
	camo.combat.ext_moving = 0
	AbilKit.run_to(w, w.tick + 100)
	t.eq(camo.vis.concealed, 0, "and it needs delay_t quiet ticks to re-arm")
	AbilKit.run_to(w, w.tick + 25)
	t.eq(camo.vis.concealed, 1, "re-armed after 120 quiet ticks")
	t.check_false(near == null or far == null or eye == null, "cast alive")


func test_s03_watchtower_radius_4(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({"players": 3})
	var camo: SimEntity = AbilKit.rifle(w, 0, 30, 30)
	AbilKit.spawn_struct(w, DefTestKit.S_TURRET, 1, 34, 30)  # 4 cells
	AbilKit.spawn_struct(w, DefTestKit.S_TURRET, 2, 25, 30)  # 5 cells
	AbilKit.run_to(w, 125)
	t.eq(camo.vis.concealed, 1, "concealed")
	t.check(_seen(w, 1, camo), "Watchtower at 4 cells detects")
	t.check_false(_seen(w, 2, camo), "at 5 cells it does not")


func test_s04_dune_rover_reveal_windows(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({"players": 2})
	var dune: SimEntity = AbilKit.spawn(w, DefTestKit.U_COLLECTOR, 0, 30, 30)
	AbilKit.set_sight(w.data, DefTestKit.U_RIFLEMAN, 7168)
	var eye: SimEntity = AbilKit.rifle(w, 1, 33, 30)
	var det: SimEntity = AbilKit.tank(w, 1, 60, 60)
	t.check(eye != null and det != null, "cast")
	dune.combat.ext_moving = 1  # cloaks while moving: no stationary requirement
	AbilKit.run_to(w, 121)
	t.eq(dune.vis.concealed, 1, "cloaked from tick 120 while moving")
	t.check_false(_seen(w, 1, dune), "invisible to the observer")
	AbilKit.run_to(w, 301)
	dune.combat.last_hit_tick = 300
	w.step()
	t.eq(dune.vis.concealed, 0, "damage reveals at 301")
	AbilKit.run_to(w, 349)
	AbilKit.teleport_cell(w, det, 33, 31)  # a detector arrives
	w.run(2)
	t.eq(dune.vis.revealed_until, 470, "detection at 350 extends the reveal to 350 + reveal_t")
	AbilKit.teleport_cell(w, det, 60, 60)  # and leaves
	AbilKit.run_to(w, 440)
	t.eq(dune.vis.concealed, 0, "revealed until 470 although the damage window (420) is over")
	AbilKit.run_to(w, 472)
	t.eq(dune.vis.concealed, 1, "hidden again after 470")


func test_s05_silent_watch(t: TestCtx) -> void:
	var sw: DefEffect = AbilKit.fx_op(DefEnums.EffectOp.CAMOUFLAGE, 0, {"end_on": ["move", "fire", "detected"]})
	var d: GameData = AbilKit.data()
	AbilKit.add_zone_effects(d, [sw])
	var w: SimWorld = AbilKit.world({}, d)
	var eye: SimEntity = AbilKit.rifle(w, 1, 33, 34)  # sees all seven (7 cells), has no detector
	var units: Array[SimEntity] = []
	for k: int in 7:
		units.append(AbilKit.spawn(w, DefTestKit.U_ENGINEER, 0, 30 + k, 32))
	w.run(3)
	units[5].combat.ext_moving = 1
	SimStats.set_flag(units[6], K.DF_EXPOSED, true)
	var granted: int = 0
	for k2: int in 7:
		if w.abilities.apply_timed_effect(units[k2].id, AbilKit.fx_index(w, sw), 300, 0, 99):
			granted += 1
	t.eq(granted, 5, "5 stationary units get it; the mover and the exposed mast do not")
	w.run(2)
	var hidden: int = 0
	for k3: int in 7:
		if not _seen(w, 1, units[k3]):
			hidden += 1
	t.eq(hidden, 5, "5 concealed from the observer, the moving one and the Fen mast are not")
	t.check(_seen(w, 1, units[5]) and _seen(w, 1, units[6]), "mover and mast visible")
	AbilKit.run_to(w, 60)
	units[0].combat.ext_moving = 1
	w.step()
	t.check(_seen(w, 1, units[0]), "a unit that moves at tick 60 loses it")
	units[0].combat.ext_moving = 0
	w.run(4)
	t.check(_seen(w, 1, units[0]), "and does not get it back")
	# detection removes it permanently
	var det: SimEntity = AbilKit.tank(w, 1, 60, 60)
	AbilKit.teleport_cell(w, det, 32, 37)  # exactly 5 cells from unit 2, 5.1+ from its neighbours
	w.run(3)
	t.check(_seen(w, 1, units[2]), "detected: visible")
	AbilKit.teleport_cell(w, det, 60, 60)
	w.run(4)
	t.check(_seen(w, 1, units[2]), "and the effect is gone for good")
	t.check_false(SimStatus.has(units[2], AbilKit.fx_index(w, sw)), "removed by DETECTED")
	t.check_false(_seen(w, 1, units[3]), "an undetected neighbour still hides")
	t.check(eye != null, "cast")


func test_s06_submarine_concealment(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({"players": 2})
	var sub: SimEntity = AbilKit.spawn(w, DefTestKit.U_TANK2, 0, 30, 30)
	var eye: SimEntity = AbilKit.rifle(w, 1, 33, 30)
	w.run(2)
	t.check(SimStealth.is_submerged(sub), "spawns submerged")
	t.eq(sub.vis.concealed, 1, "and concealed from tick 0")
	t.check_false(_seen(w, 1, sub), "the observer cannot see it")
	var asw: SimEntity = AbilKit.tank(w, 1, 35, 30)  # detector at 5 cells
	w.run(3)
	t.check(_seen(w, 1, sub), "a detector at 5 cells reveals it while submerged")
	AbilKit.teleport_cell(w, asw, 60, 60)
	w.run(3)
	t.check_false(_seen(w, 1, sub), "and it hides again when the detector leaves")
	var b: int = sub.abil.slot_of_kind(K.AK_SUBMERGE) * K.SLOT_STRIDE
	sub.abil.slots[b + K.SL_STATE] = K.SUB_SURFACED  # SimMode's surfaced phase (AB-04)
	w.run(2)
	t.eq(sub.vis.concealed, 0, "surfaced: an ordinary surface target")
	t.check(_seen(w, 1, sub) and eye != null, "visible")


func test_force_reveal_and_events(t: TestCtx) -> void:
	var w: SimWorld = AbilKit.world({"players": 2})
	var camo: SimEntity = AbilKit.rifle(w, 0, 30, 30)
	var eye: SimEntity = AbilKit.rifle(w, 1, 33, 30)
	AbilKit.run_to(w, 125)
	t.check_false(_seen(w, 1, camo), "concealed")
	SimVision.add_reveal_entity(w, 0, camo.id, w.tick + 40)
	t.check(_seen(w, 1, camo), "Counterbattery Solution: revealed at once")
	AbilKit.run_to(w, w.tick + 45)
	t.check_false(_seen(w, 1, camo), "and hidden again afterwards")
	var ev: Array[PackedInt32Array] = []
	for r: PackedInt32Array in AbilKit.events(w, K.EV_CLOAK_CHANGED):
		if r[SimEvent.I_A] == camo.id:
			ev.append(r)
	t.eq(ev.size(), 3, "cloak, reveal, cloak")
	t.eq([ev[0][SimEvent.I_B], ev[1][SimEvent.I_B], ev[2][SimEvent.I_B]], [1, 0, 1] as Array, "payload p1")
	t.check(eye != null, "cast")
