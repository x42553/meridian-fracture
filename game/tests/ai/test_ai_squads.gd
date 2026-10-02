extends RefCounted
## AiSquad / AiSquadManager (ai.md 4.3, 3.5b, 5.8.3): reserve assignment, claim by role and distance, priority arbitration,
## release, statistics upkeep and the removal of dead units. Runs on a real match so the own-entity table is the real one.


func _setup() -> Dictionary:
	var m: Dictionary = AiEconKit.make({"seed": 1, "waves": false, "rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), "credits": 20000, "level": AiTypes.Difficulty.HARD})
	AiEconKit.run(m, 3600)
	return m


func _step(m: Dictionary) -> void:
	AiEconKit.run(m, 40)


func test_reserve_holds_exactly_the_combat_units(t: TestCtx) -> void:
	var m: Dictionary = _setup()
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var sm: AiSquadManager = eco.squads
	t.gt(eco.army_units, 4, "an army exists")
	var combat: int = 0
	var t_own: AiEntityTable = ctx.kb.own
	for r: int in t_own.count:
		if sm.eligible(r):
			combat += 1
			t.eq(t_own.squad[r], 0, "combat unit %d is in the reserve" % t_own.eid[r])
		elif t_own.kind[r] == AiTypes.KIND_UNIT:
			t.eq(t_own.squad[r], -1, "collectors and utility units stay out of squads")
	t.eq(sm.reserve.size(), combat, "reserve == all combat units")
	t.eq(sm.total_units(), combat)


func test_claim_prefers_the_nearest_and_respects_priority(t: TestCtx) -> void:
	var m: Dictionary = _setup()
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var sm: AiSquadManager = eco.squads
	var before: int = sm.reserve.size()
	var hx: int = ctx.kb.sites.home_x
	var hy: int = ctx.kb.sites.home_y
	var main: AiSquad = sm.create(AiTypes.SquadKind.MAIN, 1)
	var got: int = sm.claim(0, 3, hx, hy, 0, main.prio, main)
	t.eq(got, 3)
	t.eq(main.size(), 3)
	t.eq(sm.reserve.size(), before - 3, "the reserve lost them")
	for eid: int in main.units:
		t.eq(sm.squad_of(eid), main.id)
	# nearest first: every claimed unit is at least as close as every unit left in the reserve
	var t_own: AiEntityTable = ctx.kb.own
	var worst_taken: int = 0
	for eid2: int in main.units:
		var r: int = t_own.row(eid2)
		worst_taken = maxi(worst_taken, (t_own.x[r] - hx) * (t_own.x[r] - hx) / 1024 + (t_own.y[r] - hy) * (t_own.y[r] - hy) / 1024)
	for eid3: int in sm.reserve.units:
		var r2: int = t_own.row(eid3)
		t.ge((t_own.x[r2] - hx) * (t_own.x[r2] - hx) / 1024 + (t_own.y[r2] - hy) * (t_own.y[r2] - hy) / 1024, worst_taken, "reserve units are not nearer than the claimed ones")
	# a squad of the same or higher priority cannot be raided; a higher one can
	var flank: AiSquad = sm.create(AiTypes.SquadKind.FLANK, 2)
	t.eq(sm.claim(0, 10, hx, hy, 0, flank.prio, flank), before - 3, "the flank takes what is left of the reserve but not the main squad (same prio)")
	t.eq(main.size(), 3)
	var defense: AiSquad = sm.create(AiTypes.SquadKind.DEFENSE, 3)
	t.gt(defense.prio, main.prio)
	var stolen: int = sm.claim(0, 2, hx, hy, 0, defense.prio, defense)
	t.eq(stolen, 2, "a defense squad steals from lower-priority squads")
	# a role mask filters
	var infantry: AiSquad = sm.create(AiTypes.SquadKind.HARASS, 4)
	sm.release(defense.id)
	sm.release(flank.id)
	var n_inf: int = sm.claim(1 << AiTypes.R_INFANTRY_BASIC, 99, hx, hy, 0, infantry.prio, infantry)
	for eid4: int in infantry.units:
		t.check((t_own.role_mask[t_own.row(eid4)] & (1 << AiTypes.R_INFANTRY_BASIC)) != 0, "only the requested role")
	t.gt(n_inf, 0)


func test_release_refresh_and_death(t: TestCtx) -> void:
	var m: Dictionary = _setup()
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var sm: AiSquadManager = eco.squads
	var sq: AiSquad = sm.create(AiTypes.SquadKind.MAIN, 7)
	sm.claim(0, 5, ctx.kb.sites.home_x, ctx.kb.sites.home_y, 0, 100, sq)
	_step(m)
	t.eq(sq.size(), 5)
	t.gt(sq.value, 0, "value upkeep")
	t.gt(sq.speed_min, 0, "slowest speed upkeep")
	t.gt(sq.cx, 0)
	t.gt(sq.hp_frac_q8, 200, "full health")
	var sum_roles: int = 0
	for n: int in sq.role_counts:
		sum_roles += n
	t.ge(sum_roles, 5, "role counts filled")
	# kill one member: the squad forgets it
	var victim: int = sq.units[0]
	(m["world"] as SimWorld).remove_entity(victim, SimEvent.REM_KILLED)
	_step(m)
	_step(m)
	t.eq(sq.size(), 4, "the dead unit left the squad")
	t.check_false(sq.has(victim))
	# release returns the rest to the reserve
	var reserve_before: int = sm.reserve.size()
	sm.release(sq.id)
	t.eq(sm.reserve.size(), reserve_before + 4)
	t.check(sm.squad(sq.id) == null, "the squad is gone")
	t.eq(sm.squad_of(sq.units[0] if not sq.units.is_empty() else -1), 0 if not sq.units.is_empty() else -1)


func test_squad_container_helpers(t: TestCtx) -> void:
	var s: AiSquad = AiSquad.new(9, AiTypes.SquadKind.SCOUT, 3)
	s.add(30)
	s.add(10)
	s.add(20)
	s.add(20)
	t.eq(s.units, PackedInt32Array([10, 20, 30]), "ascending, no duplicates")
	t.check(s.has(20))
	s.remove(20)
	t.check_false(s.has(20))
	t.eq(s.size(), 2)
	t.eq(s.prio, AiSquad.PRIO_BY_KIND[AiTypes.SquadKind.SCOUT])
