extends RefCounted
## AIX1 aircraft sorties and fleets (ai.md 5.10.3 / 5.10.4): the strike group launches when a flight is ready, the AA penalty
## holds it back, fighters scramble at enemy aircraft near my assets; the naval op forms around Dock and escorts.


func _budget() -> AiBudget:
	var bg: AiBudget = AiBudget.new()
	bg.reset(1000000, 1000000)
	return bg


func _air_match(ticks: int) -> Dictionary:
	return AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [1, 0], ticks, {"seed": 5})


## An airfield with `n` parked aircraft of `def_id` for pid 0; returns their entity ids.
func _flight(m: Dictionary, def_id: String, n: int) -> PackedInt32Array:
	var w: SimWorld = AiXKit.world(m)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var af: SimEntity = w.spawn_structure(w.data.structure_idx("structure.shared.airfield"), 0, h[0] + 9 * AiXKit.CELL, h[1] + 9 * AiXKit.CELL, 0, SimFlags.F_POWERED, 1000)
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		var e: SimEntity = w.spawn_unit(w.data.unit_idx(def_id), 0, af.x, af.y, 0, 0, 1000)
		SimAirSortie.on_aircraft_spawned(w, e, af.id)
		out.append(e.id)
	return out


func test_strike_group_launches_a_sortie_at_a_valuable_target(t: TestCtx) -> void:
	var m: Dictionary = _air_match(3600)
	var b: AiBrain = AiXKit.brain(m, 0)
	var c: AiContext = AiXKit.ctx(m, 0)
	var flight: PackedInt32Array = _flight(m, "unit.napc.titan_gunship", 4)
	AiSoakKit.play(m, 500)
	t.gt(b.count_ops(AiTypes.OpType.AIR), 0, "the air op owns the aircraft")
	var op: AiOpAir = null
	for o: AiOp in b.ops:
		if o is AiOpAir:
			op = o
	t.not_null(op)
	if op == null:
		return
	AiSoakKit.play(m, 900)
	t.gt(op.sorties, 0, "a sortie was flown")
	t.ge(op.sortie_units, 3, "min_sortie: at least three aircraft went together")
	t.gt(b.stat("air_sortie"), 0)
	t.eq((m["errors"] as PackedStringArray).size(), 0)
	t.check(c.kb.ghosts.count > 0)
	t.ge(flight.size(), 4)


func test_aa_penalty_holds_the_flight_back(t: TestCtx) -> void:
	var m: Dictionary = _air_match(3600)
	var b: AiBrain = AiXKit.brain(m, 0)
	var c: AiContext = AiXKit.ctx(m, 0)
	_flight(m, "unit.napc.titan_gunship", 4)
	AiSoakKit.play(m, 500)
	var op: AiOpAir = null
	for o: AiOp in b.ops:
		if o is AiOpAir:
			op = o
	t.not_null(op)
	if op == null:
		return
	var ready: PackedInt32Array = op._strike_ids.duplicate()
	t.gt(ready.size(), 0, "the strike group exists")
	var hp_pool: int = 4 * 800
	var open: Dictionary = op.pick_target(c, _budget(), ready, hp_pool, 4000, false)
	t.check(not open.is_empty(), "with no AA around, some enemy structure is a target")
	if open.is_empty():
		return
	var aa0: int = op._aa_dps(c, int(open["x"]), int(open["y"]) + 2500)
	# ring the target with anti-air units: their dps against air x 8 s over the bomber hp pool decides the penalty
	for i: int in 8:
		AiXKit.spawn(m, "unit.nec.rapier_aa", 1, int(open["x"]) + (i - 4) * 700, int(open["y"]) + 2500, 600)
	AiSoakKit.play(m, 140)
	var aa1: int = op._aa_dps(c, int(open["x"]), int(open["y"]) + 2500)
	t.gt(aa1, aa0, "the AI counts the anti-air it has seen around the target (%d -> %d dps)" % [aa0, aa1])
	var again: Dictionary = op.pick_target(c, _budget(), ready, hp_pool, 4000, false)
	if not again.is_empty() and int(again["x"]) == int(open["x"]) and int(again["y"]) == int(open["y"]):
		t.gt(int(again["aa_pen"]), int(open["aa_pen"]), "the same target now carries an AA penalty")


func test_gunships_attach_to_an_engaged_wave(t: TestCtx) -> void:
	var m: Dictionary = _air_match(3600)
	var b: AiBrain = AiXKit.brain(m, 0)
	var c: AiContext = AiXKit.ctx(m, 0)
	# a wave in a fight with two held enemy tanks
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var eh: PackedInt32Array = AiXKit.home(m, 1)
	var mid: PackedInt32Array = AiXKit.toward(h, eh, 20)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 6:
		ids.append(AiXKit.spawn(m, "unit.napc.guardian_tank", 0, mid[0] + i * 700, mid[1], 1100))
	var foes: PackedInt32Array = PackedInt32Array()
	for k: int in 2:
		foes.append(AiXKit.spawn(m, "unit.nec.leopard_tank", 1, mid[0] + 6 * AiXKit.CELL, mid[1] + k * 900, 1000))
	AiXKit.world(m).submit_raw(1, SimCmd.hold(foes))
	AiXKit.settle(m)
	var wave: AiOpAttack = AiOpAttack.new()
	wave.setup_wave(AiTypes.SquadKind.MAIN, ids, {"x": eh[0], "y": eh[1], "eid": -1, "value": 500}, 400)
	wave.start_state = AiTypes.OpState.ENGAGING
	t.check(b.add_op(c, wave))
	_flight(m, "unit.napc.titan_gunship", 4)
	AiSoakKit.play(m, 600)
	var op: AiOpAir = null
	for o: AiOp in b.ops:
		if o is AiOpAir:
			op = o
	t.not_null(op)
	if op != null:
		t.gt(op.cas_orders, 0, "ready gunships attack-moved to the engaged wave")
		t.gt(b.stat("air_cas"), 0)


func test_fighters_scramble_at_enemy_aircraft_near_the_base(t: TestCtx) -> void:
	var m: Dictionary = _air_match(3600)
	var b: AiBrain = AiXKit.brain(m, 0)
	_flight(m, "unit.napc.falcon_interceptor", 3)
	AiSoakKit.play(m, 500)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	AiXKit.spawn(m, "unit.nec.kestrel_interceptor", 1, h[0] + 14 * AiXKit.CELL, h[1], 1200)
	AiSoakKit.play(m, 300)
	var op: AiOpAir = null
	for o: AiOp in b.ops:
		if o is AiOpAir:
			op = o
	t.not_null(op)
	if op != null:
		t.gt(op.scrambles, 0, "fighters attack-moved at the intruder")


func test_naval_op_needs_a_dock_and_escorts(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [1, 0], 400, {"seed": 2, "family": 2})
	var w: SimWorld = AiXKit.world(m)
	var b: AiBrain = AiXKit.brain(m, 0)
	var c: AiContext = AiXKit.ctx(m, 0)
	t.check(not AiOpNaval.try_launch(c, b, _budget()), "no ships, no fleet")
	# a Dock at the shore next to the base and four ships on the water in front of it
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var water: PackedInt32Array = PackedInt32Array()
	for ring: int in range(4, 40):
		for oy: int in range(-ring, ring + 1, 2):
			for ox: int in range(-ring, ring + 1, 2):
				if water.is_empty() and maxi(absi(ox), absi(oy)) == ring and w.map.passable((h[0] >> 10) + ox, (h[1] >> 10) + oy, AiTypes.MoveClass.NAVAL):
					water = PackedInt32Array([((h[0] >> 10) + ox) * 1024 + 512, ((h[1] >> 10) + oy) * 1024 + 512])
	t.check(not water.is_empty(), "the coast map has water near the base")
	if water.is_empty():
		return
	w.spawn_structure(w.data.structure_idx("structure.shared.dock"), 0, water[0], water[1], 0, SimFlags.F_POWERED, 900)
	AiSoakKit.play(m, 40)
	for i: int in 2:
		AiXKit.spawn(m, "unit.napc.aegis_frigate", 0, water[0] + i * 1500, water[1] + 1500, 1700)
	AiXKit.spawn(m, "unit.napc.riverwatch_patrol_boat", 0, water[0] + 3000, water[1] + 1500, 600)
	AiSoakKit.play(m, 500)
	t.gt(b.count_ops(AiTypes.OpType.NAVAL), 0, "a fleet op formed around two escorts and a boat")
	t.gt(b.stat("naval_ops"), 0)
	t.eq((m["errors"] as PackedStringArray).size(), 0)
