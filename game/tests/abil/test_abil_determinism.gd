extends RefCounted
## AB-03: determinism of the abilities / vision domain (abilities 10.3 D1, D2, D4).

const S := preload("res://tests/support/abil_scenario.gd")


func test_d1_double_run(t: TestCtx) -> void:
	var r: Dictionary = SimTestKit.double_run(func() -> SimWorld: return S.build(), Callable(S, "script"), 900)
	t.check(r["ok"], "identical checksum chain, event digest, final checksum and state dump")
	t.gt((r["chain"] as PackedInt64Array).size(), 40, "a real chain (every 20 ticks)")


func test_d2_side_by_side(t: TestCtx) -> void:
	var a: SimWorld = S.build()
	var b: SimWorld = S.build()
	for s: int in 600:
		S.script(a, s)
		a.step()
		S.script(b, s)
		b.step()
	t.eq(a.checksum_log, b.checksum_log, "two worlds ticked alternately: same chain (no shared static state)")


func test_d4_rebuild_and_validate(t: TestCtx) -> void:
	var w: SimWorld = S.build()
	var bad_cells: int = 0
	var problems: int = 0
	for s: int in 1500:
		S.script(w, s)
		w.step()
		if w.tick % 100 == 0:
			bad_cells += w.vision.debug_rebuild_compare(w)
			problems += w.abilities.debug_validate(w).size()
	t.eq(bad_cells, 0, "rebuild-compare every 100 ticks: 0 differing cells")
	t.eq(problems, 0, "debug_validate clean")
	var ev: int = w.events.count()
	t.gt(ev, 100, "the scenario produces events (%d)" % ev)
	t.check(w.vision.stat_recomputes > 0 and w.vision.stat_restamps > 0, "vision work happened")


func test_fog_off_and_on_differ_only_in_vision(t: TestCtx) -> void:
	var a: SimWorld = S.build(true)
	var b: SimWorld = S.build(false)
	for s: int in 200:
		S.script(a, s)
		a.step()
		S.script(b, s)
		b.step()
	t.ne(a.checksum(), b.checksum(), "the fog rule is part of the state")
	t.eq(a.units.size(), b.units.size(), "same entities")
