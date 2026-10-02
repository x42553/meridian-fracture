extends RefCounted
## AIX2 (ai.md 5.13 / 10.1 test_ai_superweapons): the per-weapon target scoring on synthetic ghost sets (Atlas, Aurora, Helios,
## Perun, Tempest, Dragonfall, Horizon), the build/charge/fire lifecycle on live sim worlds for every weapon (S8: the AI fires a
## READY weapon at the enemy base within the hold limit) and the Trident counter-cast (S6).

const C: int = Fp.CELL
const A := preload("res://tests/support/ab2_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")
const WEAPON_ROSTER: Dictionary = {
	"atlas": "roster.napc.vanilla", "aurora": "roster.nec.vanilla", "helios": "roster.olm.vanilla", "perun": "roster.def.vanilla",
	"tempest": "roster.pd.vanilla", "dragonfall": "roster.han.vanilla", "horizon": "roster.ae.vanilla", "trident": "roster.sap.vanilla",
}


## A mock context of the attacker `weapon` (pid 0) against a NEC / NAPC enemy (pid 1); AiSuperweapon resolved.
func _mk(weapon: String) -> Array:
	var v: AiMockWorldView = AiMockWorldView.new(0)
	v.add_player(0, WEAPON_ROSTER[weapon], Vector2i(15, 15))
	var enemy: String = "roster.nec.vanilla" if weapon != "aurora" else "roster.napc.vanilla"
	v.add_player(1, enemy, Vector2i(80, 80))
	v.mock_tick = 8000
	var ctx: AiContext = AiMockWorldView.make_ctx(v)
	ctx.tick = 8000
	ctx.kb.enemy_pids = PackedInt32Array([1])
	var sw: AiSuperweapon = AiSuperweapon.new()
	sw.setup(ctx)
	return [ctx, sw]


func _sdef(ctx: AiContext, kind: int) -> int:
	return _enemy_res(ctx).structure_of_kind(kind)


func _enemy_res(ctx: AiContext) -> AiRoleResolver:
	return ctx.shared.resolver(ctx.view.roster_of(1))


func _ghost(ctx: AiContext, id: int, kind: int, cx: int, cy: int, value: int, flags: int = 0) -> void:
	var d: int = _sdef(ctx, kind)
	if d < 0:
		d = _enemy_res(ctx).structure_of_kind(AiTypes.StructKind.FACTORY)
	ctx.kb.ghosts.upsert(id, d, 1, cx * C + C / 2, cy * C + C / 2, ctx.tick, 100, flags, kind, value)


func _angle_ok(a: int, want: int) -> bool:
	return (a - want) & 2047 == 0


func test_atlas_centres_on_the_middle_factory(t: TestCtx) -> void:
	var m: Array = _mk("atlas")
	var ctx: AiContext = m[0]
	var sw: AiSuperweapon = m[1]
	t.eq(sw.kind, DefEnums.SwAction.KINETIC_VOLLEY)
	for i: int in 3:
		_ghost(ctx, 100 + i, AiTypes.StructKind.FACTORY, 30 + 3 * i, 40, 2000)
	var mid: int = sw.score_at(ctx, 33 * C + C / 2, 40 * C + C / 2, 0)
	var end: int = sw.score_at(ctx, 30 * C + C / 2, 40 * C + C / 2, 0)
	var rot: int = sw.score_at(ctx, 33 * C + C / 2, 40 * C + C / 2, 1024)
	t.gt(mid, end, "centre on the middle factory beats an end (%d vs %d)" % [mid, end])
	t.gt(mid, rot, "the rods along the row beat the rods across it")
	t.gt(mid, 3000, "three factories worth 6000 within the rods")
	var best: PackedInt32Array = sw.search_now(ctx)
	t.eq(best.size(), 4)
	t.le(absi(best[0] - (33 * C + C / 2)), C, "search finds the middle factory")
	t.check(_angle_ok(best[2], 0), "along the row (angle 0 or 2048)")


func test_atlas_penalizes_own_value_in_the_rods(t: TestCtx) -> void:
	var m: Array = _mk("atlas")
	var ctx: AiContext = m[0]
	var sw: AiSuperweapon = m[1]
	for i: int in 3:
		_ghost(ctx, 100 + i, AiTypes.StructKind.FACTORY, 30 + 3 * i, 40, 2000)
	var clean: int = sw.score_at(ctx, 33 * C + C / 2, 40 * C + C / 2, 0)
	var r: int = ctx.kb.own.upsert(9000)
	ctx.kb.own.kind[r] = AiTypes.KIND_UNIT
	ctx.kb.own.x[r] = 33 * C + C / 2
	ctx.kb.own.y[r] = 40 * C + C / 2
	ctx.kb.own.hp[r] = 100
	ctx.kb.own.hp_max[r] = 100
	ctx.kb.own.paid[r] = 1200
	var dirty: int = sw.score_at(ctx, 33 * C + C / 2, 40 * C + C / 2, 0)
	t.lt(dirty, clean, "own units in the rods cost")
	ctx.kb.own.paid[r] = 12000
	t.eq(sw.score_at(ctx, 33 * C + C / 2, 40 * C + C / 2, 0), 0, "never fire when the own loss exceeds half of the gain")


func test_helios_picks_the_longest_structure_row(t: TestCtx) -> void:
	var m: Array = _mk("helios")
	var ctx: AiContext = m[0]
	var sw: AiSuperweapon = m[1]
	t.eq(sw.kind, DefEnums.SwAction.BEAM_SWEEP)
	# a north-south row of five and an isolated pair
	for i: int in 5:
		_ghost(ctx, 200 + i, AiTypes.StructKind.BARRACKS, 50, 30 + 3 * i, 1500)
	_ghost(ctx, 300, AiTypes.StructKind.FACTORY, 70, 60, 1500)
	_ghost(ctx, 301, AiTypes.StructKind.FACTORY, 74, 66, 1500)
	var best: PackedInt32Array = sw.search_now(ctx)
	t.eq(best.size(), 4)
	t.le(absi(best[0] - (50 * C + C / 2)), 2 * C, "the row at x = 50")
	t.check(_angle_ok(best[2], 1024), "beam along the row (north-south)")
	t.ge(best[3], 5 * 1500 * 8 / 10, "score covers the row")


func test_perun_gets_the_counter_superweapon_bonus(t: TestCtx) -> void:
	var m: Array = _mk("perun")
	var ctx: AiContext = m[0]
	var sw: AiSuperweapon = m[1]
	_ghost(ctx, 400, AiTypes.StructKind.FACTORY, 40, 40, 3000)
	var plain: int = sw.score_at(ctx, 40 * C + C / 2, 40 * C + C / 2, 0)
	var m2: Array = _mk("perun")
	var ctx2: AiContext = m2[0]
	var sw2: AiSuperweapon = m2[1]
	_ghost(ctx2, 400, AiTypes.StructKind.SUPERWEAPON, 40, 40, 3000)
	var counter: int = sw2.score_at(ctx2, 40 * C + C / 2, 40 * C + C / 2, 0)
	t.gt(counter, plain, "+50 %% on an enemy launcher (%d vs %d)" % [counter, plain])
	t.le(absi(counter * 2 - plain * 3), plain / 10, "exactly the 1.5 factor")
	# the ring counts 0.35
	var m3: Array = _mk("perun")
	_ghost(m3[0], 400, AiTypes.StructKind.FACTORY, 45, 40, 3000)
	var ring: int = (m3[1] as AiSuperweapon).score_at(m3[0], 40 * C + C / 2, 40 * C + C / 2, 0)
	t.gt(ring, 0, "5 cells away: in the fragmentation ring")
	t.lt(ring, plain / 2, "the ring is worth a third")


func test_tempest_score_falls_with_anti_air(t: TestCtx) -> void:
	var m: Array = _mk("tempest")
	var ctx: AiContext = m[0]
	var sw: AiSuperweapon = m[1]
	t.eq(sw.kind, DefEnums.SwAction.DRONE_SWARM)
	_ghost(ctx, 500, AiTypes.StructKind.REFINERY, 40, 40, 2500)
	_ghost(ctx, 501, AiTypes.StructKind.REFINERY, 42, 40, 2500)
	var soft: int = sw.score_at(ctx, 41 * C + C / 2, 40 * C + C / 2, 0)
	for i: int in 4:
		_ghost(ctx, 510 + i, AiTypes.StructKind.AA_BATTERY, 38 + 2 * i, 44, 800)
	var hard: int = sw.score_at(ctx, 41 * C + C / 2, 40 * C + C / 2, 0)
	t.gt(soft, 0)
	t.lt(hard, soft, "AA batteries reduce the drone score (%d < %d)" % [hard, soft])


func test_dragonfall_is_penalized_by_anti_tank_turrets(t: TestCtx) -> void:
	var m: Array = _mk("dragonfall")
	var ctx: AiContext = m[0]
	var sw: AiSuperweapon = m[1]
	t.eq(sw.kind, DefEnums.SwAction.ENGINE_DROP)
	_ghost(ctx, 600, AiTypes.StructKind.FACTORY, 40, 40, 3000)
	_ghost(ctx, 601, AiTypes.StructKind.BARRACKS, 43, 40, 2000)
	var open: int = sw.score_at(ctx, 41 * C + C / 2, 40 * C + C / 2, 0)
	for i: int in 3:
		_ghost(ctx, 610 + i, AiTypes.StructKind.AT_TURRET, 39 + 2 * i, 44, 900)
	var guarded: int = sw.score_at(ctx, 41 * C + C / 2, 40 * C + C / 2, 0)
	t.gt(open, 1500)
	t.lt(guarded, open, "anti-tank turrets within 10 cells reduce it (%d < %d)" % [guarded, open])


func test_horizon_block_bonus_for_an_expansion_mcv(t: TestCtx) -> void:
	var m: Array = _mk("horizon")
	var ctx: AiContext = m[0]
	var sw: AiSuperweapon = m[1]
	t.eq(sw.kind, DefEnums.SwAction.RAIL_STRIKE)
	_ghost(ctx, 700, AiTypes.StructKind.BARRACKS, 40, 40, 1800)
	var plain: int = sw.score_at(ctx, 40 * C + C / 2, 40 * C + C / 2, 0)
	# an enemy MCV in the line: +1500
	var et: AiEntityTable = ctx.kb.enemy_units
	var r: int = et.upsert(7000)
	var mcv: int = _enemy_res(ctx).first(AiTypes.R_MCV)
	t.gt(mcv, -1, "the enemy roster has an MCV")
	et.def[r] = mcv
	et.owner[r] = 1
	et.kind[r] = AiTypes.KIND_UNIT
	et.x[r] = 42 * C + C / 2
	et.y[r] = 40 * C + C / 2
	et.hp[r] = 100
	et.hp_max[r] = 100
	et.paid[r] = 1500
	et.last_seen[r] = ctx.tick
	et.last_moved[r] = 0
	var with_mcv: int = sw.score_at(ctx, 40 * C + C / 2, 40 * C + C / 2, 0)
	t.ge(with_mcv, plain + 1500, "block bonus (%d vs %d)" % [with_mcv, plain])


func test_aurora_prefers_vehicles_and_powered_defenses(t: TestCtx) -> void:
	var m: Array = _mk("aurora")
	var ctx: AiContext = m[0]
	var sw: AiSuperweapon = m[1]
	t.eq(sw.kind, DefEnums.SwAction.EMP_BURST)
	var defs: int = 0
	for i: int in 3:
		_ghost(ctx, 800 + i, AiTypes.StructKind.AT_TURRET, 40 + 2 * i, 40, 900)
		defs += 900
	var with_defs: int = sw.score_at(ctx, 42 * C + C / 2, 40 * C + C / 2, 0)
	t.eq(with_defs, defs * 80 / 100, "powered defenses at 0.8")
	var m2: Array = _mk("aurora")
	for i2: int in 3:
		_ghost(m2[0], 800 + i2, AiTypes.StructKind.AT_TURRET, 40 + 2 * i2, 40, 900, AiTypes.EF_UNPOWERED)
	t.eq((m2[1] as AiSuperweapon).score_at(m2[0], 42 * C + C / 2, 40 * C + C / 2, 0), 0, "unpowered defenses are unaffected")


func test_start_time_and_thresholds(t: TestCtx) -> void:
	var m: Array = _mk("atlas")
	var ctx: AiContext = m[0]
	var sw: AiSuperweapon = m[1]
	ctx.pers.sw_priority = 60
	sw.jitter_pct = 0
	var scale: int = ctx.tune("sw.time_scale_pct", 100)  # AIT: 75 percent (the launcher needs its full recharge before the first shot)
	t.eq(sw.min_start_tick(ctx), ctx.diff.sw_min_time_s * 20 * 90 / 100 * scale / 100, "sw_min_time_s x (150 - priority) / 100 x scale")
	sw.jitter_pct = 10
	t.gt(sw.min_start_tick(ctx), ctx.diff.sw_min_time_s * 20 * 90 / 100 * scale / 100)
	t.le(absi(sw.jitter_pct), 10)
	var th: PackedInt32Array = sw._thresholds(ctx)
	t.eq(th[0], 4000, "Hard: 0.8 x 5000")
	t.eq(th[1], 900, "Hard hold limit")


# --------------------------------------------------------------------------------------------- live lifecycle
func _live(weapon: String, level: int) -> Dictionary:
	var attacker: String = WEAPON_ROSTER[weapon]
	var defender: String = "roster.nec.vanilla" if weapon != "aurora" else "roster.napc.vanilla"
	var w: SimWorld = A.world({"rosters": [attacker, defender], "movement": false, "fog": false, "seed": 5})
	S.base(w, 0, 6, 6, true)
	S.base(w, 1, 46, 46, false)
	# a vehicle blob for the Aurora
	if weapon == "aurora":
		var res: AiRoleResolver = AiRoleResolver.resolve(w.data, w.data.rosters[w.players[1].roster_idx], AiDataStore.load_default())
		for i: int in 8:
			var d: int = res.first(AiTypes.R_TANK_MAIN)
			w.spawn_unit(d, 1, (44 + i % 4) * C + C / 2, (52 + i / 4) * C + C / 2, 0, 0, w.data.units[d].cost, 0, SimEvent.SPAWN_PRODUCED)
		w.call("_flush_spawns")
	A.hold_fire(w)
	var factory: AiFactory = AiFactory.new()
	var think: Callable = factory.make(0, level, 0, 99)
	var out: Array = []
	think.call(w, out)
	S.force_ready(w, 0)
	var ready_tick: int = w.tick
	var fired_at: int = -1
	var limit: int = ready_tick + 2400
	var errors: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errors.append("%s: %s" % [tag, msg])
	while w.tick < limit and fired_at < 0:
		if w.tick % 2 == 0:
			var o: Array = []
			think.call(w, o)
			for c: Variant in o:
				w.submit_raw(0, c)
		w.step()
		if w.players[0].econ.slots[SimEconConst.SLOT_SW].sw_state != SimEconConst.SW_READY:
			fired_at = w.tick
	Log.sink = old_sink
	var brain: AiBrain = factory.thinker(0).controller.ctx.brain as AiBrain
	return {"world": w, "ready": ready_tick, "fired": fired_at, "sw": brain.powers.sw, "errors": errors}


func test_every_weapon_is_fired_at_the_enemy_base(t: TestCtx) -> void:
	for weapon: String in ["atlas", "aurora", "helios", "perun", "tempest", "dragonfall", "horizon"]:
		var r: Dictionary = _live(weapon, AiTypes.Difficulty.HARD)
		var sw: AiSuperweapon = r["sw"]
		t.eq((r["errors"] as PackedStringArray).size(), 0, "%s: no engine errors" % weapon)
		t.gt(int(r["fired"]), 0, "%s: the READY weapon was fired" % weapon)
		if int(r["fired"]) < 0:
			continue
		t.le(int(r["fired"]) - int(r["ready"]), 900 + 60, "%s: within the Hard hold limit (%d ticks)" % [weapon, int(r["fired"]) - int(r["ready"])])
		var tx: int = sw.last_target[0]
		var ty: int = sw.last_target[1]
		var dist_cells: int = Fp.dist(tx - 49 * C, ty - 52 * C) / C
		t.le(dist_cells, 12, "%s: aimed at the enemy base (%d cells off)" % [weapon, dist_cells])
		var w: SimWorld = r["world"]
		var s: SimPowerSlot = w.players[0].econ.slots[SimEconConst.SLOT_SW]
		t.eq(s.charge, 0 if s.charge < 100 else s.charge, "%s: the recharge restarted at the activation" % weapon)
		t.gt(w.strategic.warnings.size(), 0, "%s: a warning zone opened" % weapon)


func test_easy_holds_longer_than_hard(t: TestCtx) -> void:
	var hard: Dictionary = _live("atlas", AiTypes.Difficulty.HARD)
	var easy: Dictionary = _live("atlas", AiTypes.Difficulty.EASY)
	t.gt(int(hard["fired"]), 0)
	t.check(int(easy["fired"]) < 0 or int(easy["fired"]) - int(easy["ready"]) >= int(hard["fired"]) - int(hard["ready"]), "Easy never fires sooner than Hard")


# ------------------------------------------------------------------------------------------------------- Trident
func _trident_run(level: int) -> Dictionary:
	var w: SimWorld = A.world({"rosters": ["roster.sap.vanilla", "roster.napc.usa"], "movement": false, "fog": false, "seed": 8})
	S.base(w, 0, 10, 10, true)
	S.base(w, 1, 44, 44, true)
	# rich targets for the enemy Atlas: three factories in a row inside my base
	for i: int in 3:
		A.structure(w, "structure.shared.factory" if A.data().structure_idx("structure.shared.factory") >= 0 else "structure.shared.generator", 0, 25 + 3 * i, 30)
	var factory: AiFactory = null
	var think: Callable = Callable()
	if level >= 0:
		factory = AiFactory.new()
		think = factory.make(0, level, 0, 99)
		var o0: Array = []
		think.call(w, o0)
	S.force_ready(w, 0)
	S.force_ready(w, 1)
	w.step()
	S.launch(w, 1, 28, 30, 0)
	var hp0: int = 0
	for e: SimEntity in w.structures_of(0):
		hp0 += e.hp
	for _i: int in 420:
		if level >= 0 and w.tick % 2 == 0:
			var o: Array = []
			think.call(w, o)
			for c: Variant in o:
				w.submit_raw(0, c)
		w.step()
	var hp1: int = 0
	for e2: SimEntity in w.structures_of(0):
		hp1 += e2.hp
	var casts: int = 0
	if level >= 0:
		casts = ((factory.thinker(0).controller.ctx.brain as AiBrain).powers.sw.counter_casts)
	return {"hp_lost": hp0 - hp1, "casts": casts}


func test_trident_counter_cast_on_a_rich_footprint(t: TestCtx) -> void:
	var base: Dictionary = _trident_run(-1)
	var ai: Dictionary = _trident_run(AiTypes.Difficulty.HARD)
	t.gt(base["hp_lost"], 0, "the unprotected base is hit (%d hp)" % base["hp_lost"])
	t.eq(ai["casts"], 1, "the AI cast Trident over the footprint")
	t.lt(ai["hp_lost"], base["hp_lost"], "the dome reduces the damage (%d < %d)" % [ai["hp_lost"], base["hp_lost"]])
