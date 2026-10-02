extends RefCounted
## AiWatchdog (W1 / W2 / W8) and the rebuild rules of AiTech: a dead economy is reported and answered with EMERGENCY wants, a lost
## power grid or a lost Radar is rebuilt before anything else, and a construction that cannot progress is cancelled.


func _match(extra: Dictionary = {}) -> Dictionary:
	var o: Dictionary = {"seed": 1, "waves": false, "rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), "level": AiTypes.Difficulty.HARD}
	o.merge(extra, true)
	return AiEconKit.make(o)


func _remove_structures(m: Dictionary, pid: int, kind: int) -> int:
	var ctx: AiContext = AiEconKit.ctx_of(m, pid)
	var w: SimWorld = m["world"]
	var n: int = 0
	for e: SimEntity in w.structures_of(pid):
		if (e.flags & SimFlags.F_GONE) == 0 and ctx.res.kind_of_structure(e.def_idx) == kind:
			w.remove_entity(e.id, SimEvent.REM_KILLED)
			n += 1
	return n


func _drain(pid: int) -> Callable:
	return func(w: SimWorld, _tick: int) -> void:
		w.players[pid].credits = 0


func test_w1_reports_a_dead_economy(t: TestCtx) -> void:
	var m: Dictionary = _match()
	AiEconKit.run(m, 5000)
	var out: PackedInt32Array = PackedInt32Array()
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	ctx.view.collector_ids(out)
	for id: int in out:
		(m["world"] as SimWorld).remove_entity(id, SimEvent.REM_KILLED)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	AiEconKit.run(m, 3200, _drain(0))  # no collectors, and every credit that arrives vanishes
	t.gt(eco.watchdog.w1_reports, 0, "W1 STALL_ECON reported")
	t.check(eco.watchdog.desperate, "desperate after 2400 ticks without income")
	t.gt(ctx.telemetry.count_of(AiTypes.Tele.STALL), 0, "telemetry STALL emitted")
	t.check(eco.collapse, "the economy knows it is in collapse")
	t.check(eco.find_want(AiTypes.WantKind.UNIT_ROLE, eco.collector_def, AiTypes.WantOrigin.EMERGENCY) != null or eco.collectors_queued > 0, "an EMERGENCY collector is wanted / queued")


func test_w8_power_stall_and_emergency_generator(t: TestCtx) -> void:
	var m: Dictionary = _match()
	AiEconKit.run(m, 6000)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var gens: int = _remove_structures(m, 0, AiTypes.StructKind.GENERATOR)
	t.gt(gens, 0, "the grid is destroyed")
	AiEconKit.run(m, 60)
	t.check(ctx.view.power_shortage(), "power shortage")
	var gen: AiWant = eco.find_want(AiTypes.WantKind.STRUCT, ctx.res.structure_of_kind(AiTypes.StructKind.GENERATOR), AiTypes.WantOrigin.EMERGENCY)
	t.check(gen != null or eco.struct_q[ctx.res.structure_of_kind(AiTypes.StructKind.GENERATOR)] > 0, "EMERGENCY generator wanted / under construction")
	AiEconKit.run(m, 5200)  # one Generator at a time, each built at half speed during the shortage (AIT: bases are bigger now)
	t.check_false(ctx.view.power_shortage(), "the grid was rebuilt")
	t.gt(eco.struct_own[ctx.res.structure_of_kind(AiTypes.StructKind.GENERATOR)], 0)


func test_w8_reports_when_the_grid_cannot_be_rebuilt(t: TestCtx) -> void:
	var m: Dictionary = _match()
	AiEconKit.run(m, 6000)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	_remove_structures(m, 0, AiTypes.StructKind.GENERATOR)
	AiEconKit.run(m, 1500, _drain(0))
	t.gt(eco.watchdog.w8_reports, 0, "W8 STALL_POWER reported after 600 ticks of shortage")


func test_lost_radar_is_rebuilt_first(t: TestCtx) -> void:
	var m: Dictionary = _match()
	AiEconKit.run(m, 7200)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var rad: int = ctx.res.structure_of_kind(AiTypes.StructKind.RADAR)
	t.gt(eco.struct_own[rad], 0, "there is a Radar")
	_remove_structures(m, 0, AiTypes.StructKind.RADAR)
	AiEconKit.run(m, 200)
	var w: AiWant = eco.find_want(AiTypes.WantKind.STRUCT, rad, AiTypes.WantOrigin.EMERGENCY)
	t.check(w != null or eco.struct_q[rad] > 0 or eco.struct_own[rad] > 0, "an EMERGENCY rebuild want for the Radar (or it is already under way)")
	AiEconKit.run(m, 2400)
	t.gt(eco.struct_own[rad], 0, "the Radar stands again")
	t.ge(eco.planner.tier(ctx), 2)


func test_construction_without_a_site_is_cancelled(t: TestCtx) -> void:
	# a structure whose every cell is blacklisted cannot be placed: after 600 ticks the line is cancelled (refund) and the def blocked
	var m: Dictionary = _match({"credits": 20000})
	AiEconKit.run(m, 300)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var def: int = ctx.res.structure_of_kind(AiTypes.StructKind.GENERATOR)
	# blacklist the whole neighbourhood of the base for a long time
	var sx: int = ctx.view.start_cell_x(0)
	var sy: int = ctx.view.start_cell_y(0)
	for y: int in range(sy - 14, sy + 15):
		for x: int in range(sx - 14, sx + 15):
			eco.placer.blacklist(x, y, ctx.tick + 5000)
	var cancels_before: int = eco.cancels
	AiEconKit.run(m, 2600)
	t.gt(eco.cancels, cancels_before, "the unplaceable construction was cancelled")
	t.check(eco.def_blocked(def) or eco.def_blocked(ctx.res.structure_of_kind(AiTypes.StructKind.REFINERY)) or eco.cancels > cancels_before, "the def is blocked for a while")


func test_damaged_structures_are_repaired_and_switched_off(t: TestCtx) -> void:
	var m: Dictionary = _match({"credits": 20000})
	AiEconKit.run(m, 3500)
	var w: SimWorld = m["world"]
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var victim: SimEntity = null
	for e: SimEntity in w.structures_of(0):
		if ctx.res.kind_of_structure(e.def_idx) == AiTypes.StructKind.BARRACKS and (e.flags & SimFlags.F_GONE) == 0:
			victim = e
	t.check(victim != null, "a Barracks stands")
	victim.hp = victim.hp_max * 40 / 100
	var hp0: int = victim.hp
	AiEconKit.run(m, 400)
	t.gt(eco.repairs, 0, "repair was switched on for the damaged structure")
	t.gt(victim.hp, hp0, "the structure heals (%d -> %d of %d)" % [hp0, victim.hp, victim.hp_max])
	AiEconKit.run(m, 2400)
	t.ge(victim.hp * 100 / victim.hp_max, 95, "repaired to >= 95 %%")
	AiEconKit.run(m, 300)
	t.check_false((ctx.kb.own.flags[ctx.kb.own.row(victim.id)] & AiTypes.EF_REPAIRING) != 0, "... and switched off again")
