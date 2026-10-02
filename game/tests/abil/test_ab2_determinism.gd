extends RefCounted
## AB2 determinism: a composite scenario of the ability core, auras and containers on the real data, run twice in one
## process (identical checksum chain, event digest, state dump), by two worlds ticked alternately, and with the checksum
## read at different moments (a read must never change state).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")


func _build() -> SimWorld:
	var rows: PackedStringArray = A.MV.grid(64)
	A.MV.rect(rows, 40, 10, 58, 40, "~")
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.nordics", "roster.han.china"], "teams": [1, 2, 1], "rows": rows, "seed": 5, "rules": {"fog": true}})
	A.spawn(w, "unit.napc.paladin_howitzer", 0, 12, 12)
	A.structure(w, "structure.shared.generator", 0, 10, 20)
	A.structure(w, "structure.shared.factory", 0, 20, 20)
	var g: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 24, 20)
	g.hp = g.hp_max / 2
	var apc: SimEntity = A.spawn(w, "unit.napc.pathfinder_apc", 0, 12, 30)
	var s1: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 14, 32)
	var s2: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 15, 32)
	A.spawn(w, "unit.napc.combat_medic", 0, 16, 30)
	w.submit_raw(0, SimCmd.build(SimCmd.LOAD, [apc.id, 0], PackedInt32Array([s1.id, s2.id])))
	A.structure(w, "structure.shared.generator", 1, 50, 50)
	A.structure(w, "structure.nec.relay", 1, 52, 50)
	A.spawn(w, "unit.nec.leopard_tank", 1, 50, 52)
	A.spawn(w, "unit.nec.aster_ew_aircraft", 1, 36, 44)
	A.spawn(w, "unit.han.link_operator", 2, 20, 8)
	A.spawn(w, "unit.han.nest_rocket_drone", 2, 22, 8)
	w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([1])))
	return w


func _script(w: SimWorld, s: int) -> void:
	if s == 100:
		for u: SimEntity in w.units_of(0):
			if u.cargo != null and u.cargo.n_pax > 0:
				w.submit_raw(0, SimCmd.build(SimCmd.UNLOAD, [0, 0, u.x, u.y], PackedInt32Array([u.id])))
	if s == 200:
		var gens: Array[SimEntity] = w.structures_of(1)
		if not gens.is_empty():
			w.remove_entity(gens[0].id, SimEvent.REM_SCRIPT)


func _digest(w: SimWorld) -> PackedInt64Array:
	return PackedInt64Array([w.checksum(), w.events.digest(), Checksum.fnv_string(w.dump_state()), w.abilities.timer_digest])


func _run(ticks: int, peek: bool) -> PackedInt64Array:
	var w: SimWorld = _build()
	for s: int in ticks:
		_script(w, s)
		w.step()
		if peek and s % 7 == 0:
			w.checksum()  # a read must not change anything
			w.abilities.debug_validate(w)
	return _digest(w)


func test_double_run(t: TestCtx) -> void:
	var a: PackedInt64Array = _run(400, false)
	var b: PackedInt64Array = _run(400, false)
	t.eq(a, b, "two runs: checksum, events, state dump and timer digest identical")


func test_reads_do_not_change_state(t: TestCtx) -> void:
	t.eq(_run(300, false), _run(300, true), "checksum / debug_validate reads are side-effect free")


func test_two_worlds_ticked_alternately(t: TestCtx) -> void:
	var w1: SimWorld = _build()
	var w2: SimWorld = _build()
	for s: int in 300:
		_script(w1, s)
		w1.step()
		_script(w2, s)
		w2.step()
		if s % 50 == 0:
			t.eq(w1.checksum(), w2.checksum(), "tick %d: identical" % s)
	t.eq(_digest(w1), _digest(w2), "final digests identical")
	t.eq(w1.abilities.debug_validate(w1).size(), 0, "validate clean")


func test_scenario_exercises_the_features(t: TestCtx) -> void:
	var w: SimWorld = _build()
	for s: int in 400:
		_script(w, s)
		w.step()
	t.gt(A.count_events(w, K.EV_MODE_CHANGED), 0, "a mode completed")
	t.gt(A.count_events(w, K.EV_LOADED), 1, "passengers loaded")
	t.gt(A.count_events(w, K.EV_UNLOADED), 0, "and unloaded")
	var covered: int = 0
	for g: int in SimAuraSystem.G_COUNT:
		covered += w.abilities.aura.cov_ids[g].size()
	t.gt(w.abilities.aura.stat_polls, 0, "the aura polls ran")
	t.ge(covered, 0, "coverage sets exist")
