extends RefCounted
## AB3 determinism (DR-1..15): the composite zones / summons / powers scenario run twice in one process (identical
## checksum chain, event digest, state dump), by two worlds ticked alternately, with reads in between (a read must never
## change state), plus the invariants over the whole run and proof that the scenario really exercised the features.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")


func test_double_run(t: TestCtx) -> void:
	var a: PackedInt64Array = Ab3Kit.run_chain(false)
	var b: PackedInt64Array = Ab3Kit.run_chain(false)
	t.gt(a.size(), 60, "a chain of checkpoints")
	t.eq(a, b, "two runs: identical checkpoints, checksum, event digest, state dump, timer digest")


func test_reads_do_not_change_state(t: TestCtx) -> void:
	t.eq(Ab3Kit.run_chain(true), Ab3Kit.run_chain(false), "checksum / validate reads in between change nothing")


func test_two_worlds_ticked_alternately(t: TestCtx) -> void:
	var w1: SimWorld = Ab3Kit.build()
	var w2: SimWorld = Ab3Kit.build()
	for s: int in 700:
		Ab3Kit.script(w1, s)
		Ab3Kit.script(w2, s)
		w1.step()
		w2.step()
		if s % 50 == 0:
			t.eq(w1.checksum(), w2.checksum(), "tick %d: alternate stepping agrees" % s)
	t.eq(Ab3Kit.digest(w1), Ab3Kit.digest(w2), "final digests agree")


func test_the_scenario_exercises_the_features_and_stays_valid(t: TestCtx) -> void:
	var w: SimWorld = Ab3Kit.build()
	var bad: int = 0
	for s: int in Ab3Kit.TICKS:
		Ab3Kit.script(w, s)
		w.step()
		if s % 25 == 0:
			var msgs: PackedStringArray = w.abilities.debug_validate(w)
			if not msgs.is_empty():
				bad += 1
				if bad < 4:
					t.fail("tick %d: %s" % [w.tick, "; ".join(msgs)])
	t.eq(bad, 0, "debug_validate stayed clean every 25 ticks")
	var cov: Dictionary = Ab3Kit.coverage(w)
	t.gt(int(cov.get(SimZoneConsts.EV_ZONE_SPAWNED, 0)), 12, "zones were created (%d)" % int(cov.get(SimZoneConsts.EV_ZONE_SPAWNED, 0)))
	t.gt(int(cov.get(SimZoneConsts.EV_ZONE_ENDED, 0)), 6, "zones ended")
	t.gt(int(cov.get(SimZoneConsts.EV_SUMMONED, 0)), 40, "summons were created (%d)" % int(cov.get(SimZoneConsts.EV_SUMMONED, 0)))
	t.gt(int(cov.get(SimZoneConsts.EV_SUMMON_EXPIRED, 0)), 0, "summons expired")
	t.gt(int(cov.get(K.EV_FX_APPLIED, 0)), 10, "timed effects were applied")
	t.gt(int(cov.get(K.EV_BUFF_APPLIED, 0)), 3, "buffs were cast")
	t.gt(int(cov.get(SimCombatConsts.EV_FIRE, 0)), 20, "the armies actually fought")
