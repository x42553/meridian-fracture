extends RefCounted
## E8 summon autonomy on the REAL data through the superweapon framework: the Tempest swarm and the Dragonfall engines
## attack on their own, respect their leash / targets, expire, and are queryable through SimSummonBrain.

const A := preload("res://tests/support/ab2_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")

const CELL: int = 1024


func _w(a: String, b: String) -> SimWorld:
	var w: SimWorld = A.world({"rosters": [a, b], "movement": true, "invariants_every": 25})
	S.base(w, 0, 10, 10)
	S.base(w, 1, 44, 44, false)
	return w


func _fire(w: SimWorld, cx: int, cy: int) -> SimWarning:
	S.force_ready(w, 0)
	S.launch(w, 0, cx, cy)
	w.step()
	return w.strategic.warnings[w.strategic.warnings.size() - 1]


func test_tempest_drones_attack_ground_enemies_and_expire(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.pd.vanilla", "roster.nec.vanilla")
	var tank: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 32, 32)
	w.set_hp_max(tank, 100000)
	tank.hp = 100000
	var jet: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 60, 10)
	A.hold_fire(w)
	var wr: SimWarning = _fire(w, 32, 32)
	A.run_to(w, wr.exec_tick + 1)
	var ids: PackedInt32Array = PackedInt32Array()
	SimSummonBrain.swarm_drones(w, 0, ids)
	t.eq(ids.size(), 24, "24 drones")
	t.eq(SimSummonBrain.phase_of(w.by_id[ids[0]]), SimSummonBrain.PHASE_APPROACH, "they start flying to the zone")
	var area: PackedInt32Array = PackedInt32Array()
	t.check(SimSummonBrain.work_area(w.by_id[ids[0]], area), "work area known")
	t.eq(area[2], 6 * CELL, "zone radius 6")
	A.run(w, 250)
	SimSummonBrain.swarm_drones(w, 0, ids)
	t.gt(ids.size(), 0, "still there")
	var attacking: int = 0
	for id: int in ids:
		if SimSummonBrain.phase_of(w.by_id[id]) == SimSummonBrain.PHASE_ATTACK:
			attacking += 1
			var e: SimEntity = w.by_id[id]
			t.le(e.expire_tick - w.by_id[id].born, SimZoneConsts.SWARM_HARD_CAP_TICKS, "within the hard cap")
	t.gt(attacking, 12, "most drones reached the zone")
	t.lt(tank.hp, 100000, "the tank inside the zone is being shot")
	t.eq(jet.hp, jet.hp_max, "a unit far outside the zone is left alone")
	A.run(w, SimZoneConsts.SWARM_HARD_CAP_TICKS)
	SimSummonBrain.swarm_drones(w, 0, ids)
	t.eq(ids.size(), 0, "all drones expired (400 ticks after arrival at the latest 1200 after spawn)")


func test_tempest_inside_a_trident_dome_bypasses_it(t: TestCtx) -> void:
	# a Trident dome over the swarm zone: the drones fire from INSIDE it, and "weapons fired from inside bypass": the dome
	# keeps its charges and the tank takes full damage
	var w: SimWorld = A.world({"rosters": ["roster.pd.vanilla", "roster.sap.vanilla"], "movement": true})
	S.base(w, 0, 10, 10)
	S.base(w, 1, 44, 44)
	var tank: SimEntity = A.spawn(w, "unit.sap.combat_pioneer", 1, 32, 32)
	w.set_hp_max(tank, 100000)
	tank.hp = 100000
	A.hold_fire(w)
	S.force_ready(w, 1)
	S.launch(w, 1, 32, 32)
	A.run(w, 125)
	var dome: SimZone = null
	for z: SimZone in w.zones.active_zones():
		if z.kind == DefEnums.ZoneKind.INTERCEPT:
			dome = z
	t.not_null(dome, "Trident dome up")
	if dome == null:
		return
	var wr: SimWarning = _fire(w, 32, 32)
	A.run_to(w, wr.exec_tick + 400)
	t.eq(dome.charges, 24, "shots fired from inside the dome bypass it")
	t.lt(tank.hp, 100000, "and hit")


func test_dragonfall_engines_march_on_structures_and_vanish(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.han.vanilla", "roster.nec.vanilla")
	var bar: SimEntity = A.structure(w, "structure.shared.barracks", 1, 32, 34)
	w.set_hp_max(bar, 100000)
	bar.hp = 100000
	var wr: SimWarning = _fire(w, 32, 32)
	A.run_to(w, wr.exec_tick + 2)
	var ids: PackedInt32Array = PackedInt32Array()
	SimSummonBrain.capsules(w, 0, ids)
	t.eq(ids.size(), 3, "three capsules")
	t.eq(SimSummonBrain.phase_of(w.by_id[ids[0]]), SimSummonBrain.PHASE_ASSEMBLING, "unfolding")
	A.run_to(w, wr.exec_tick + 104)
	SimSummonBrain.engines(w, 0, ids)
	t.eq(ids.size(), 3, "engines after 5 s")
	var e: SimEntity = w.by_id[ids[0]]
	t.le(absi(SimSummonBrain.expires_at(e) - (wr.exec_tick + 100 + 1200)), 12, "engines expire 60 s after unfolding (driver period 10)")
	A.run_to(w, wr.exec_tick + 100 + 700)
	t.lt(bar.hp, 100000, "the engines shelled the nearest enemy structure")
	A.run_to(w, wr.exec_tick + 100 + 1210)
	SimSummonBrain.engines(w, 0, ids)
	t.eq(ids.size(), 0, "gone after 60 s")
	t.eq(w.zones.debug_validate(w), PackedStringArray(), "zones validate")
	t.eq(w.abilities.debug_validate(w), PackedStringArray(), "abilities validate")
