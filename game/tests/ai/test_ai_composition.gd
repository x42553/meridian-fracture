extends RefCounted
## AiComposition + AiTech counters + AiProduction (ai.md 5.5.5 / 5.6): the army composition follows the roster's doctrine, the
## phase, the personality, and REACTS to what the AI has scouted of the enemy (air -> anti-air, heavy armor -> anti-armor,
## camouflage -> detectors). Every reaction is compared with a control match that differs only by the sighting.

const SCOUT_TICK: int = 5400
const REACT_TICKS: int = 3600


func _match(extra: Dictionary = {}) -> Dictionary:
	var o: Dictionary = {"seed": 1, "waves": false, "rosters": PackedStringArray(["roster.nec.vanilla", "roster.napc.vanilla"]), "level": AiTypes.Difficulty.HARD, "fog": true}
	o.merge(extra, true)
	return AiEconKit.make(o)


## Runs a control and a "scouted" match to SCOUT_TICK + REACT_TICKS; `sight` (Callable(ctx)) is the sighting injected into p0's knowledge base.
func _pair(sight: Callable) -> Array:
	var out: Array = []
	for scouted: bool in [false, true]:
		var m: Dictionary = _match()
		AiEconKit.run(m, SCOUT_TICK)
		if scouted:
			sight.call(AiEconKit.ctx_of(m, 0))
		AiEconKit.run(m, 150)
		out.append({"eco": AiEconKit.eco_of(m, 0), "share": AiEconKit.eco_of(m, 0).comp.share_q8.duplicate(), "weight": AiEconKit.eco_of(m, 0).comp.weight.duplicate()})
		AiEconKit.run(m, REACT_TICKS - 150)
	return out


func _count_kind(eco: AiEconomy, ctx: AiContext, kind: int) -> int:
	var n: int = 0
	for s: int in eco.struct_own.size():
		if ctx.res.kind_of_structure(s) == kind:
			n += eco.struct_own[s] + eco.struct_q[s]
	return n


func test_opening_composition_is_normalised_and_gated_by_tech(t: TestCtx) -> void:
	var m: Dictionary = _match({"fog": false})
	AiEconKit.run(m, 2600)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var sum: int = 0
	for r: int in AiTypes.ROLE_COUNT:
		sum += eco.comp.share_q8[r]
		if eco.comp.share_q8[r] > 0:
			t.eq(eco.comp.producible[r], 1, "a role with a share is producible (%s)" % AiTypes.ROLE_NAMES[r])
	t.le(absi(sum - 256), eco.comp.roles.size(), "shares sum to 256 (%d)" % sum)
	t.gt(eco.comp.share_q8[AiTypes.R_INFANTRY_BASIC], 0, "infantry: the Barracks is up")
	t.eq(eco.comp.share_q8[AiTypes.R_AA_MOBILE], 0, "anti-air needs the Radar")
	t.eq(eco.comp.phase, AiTypes.Phase.OPENING)
	t.eq(eco.comp.weight[AiTypes.R_HEAVY], 0, "no Heavy weight in the opening")
	t.check(ctx.res.has_role(AiTypes.R_HEAVY))
	# the opener's minimum counts are served: two rifle-class infantry, one scout, tanks
	AiEconKit.run(m, 4200)
	t.ge(eco.production.trained_role[AiTypes.R_INFANTRY_BASIC], 2, "opener inf1: two basic infantry")
	t.ge(eco.production.trained_role[AiTypes.R_TANK_MAIN], 2, "opener tank1: two tanks once the factory runs")


func test_tank_of_t2_rosters_waits_for_the_radar(t: TestCtx) -> void:
	# ai.md 5.5.1: Canada, Eurocorps, Russia, China, Japan, India and South Africa have a T2 tank
	var m: Dictionary = _match({"rosters": PackedStringArray(["roster.nec.eurocorps", "roster.def.russia"]), "fog": false})
	AiEconKit.run(m, 50)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	t.eq(ctx.res.min_tier(AiTypes.R_TANK_MAIN), 2, "Eurocorps: TANK_MAIN is a tier-2 role")
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var rad: int = ctx.res.structure_of_kind(AiTypes.StructKind.RADAR)
	var ticks: int = 0
	while ticks < 7000 and ctx.view.struct_count(rad) == 0:
		AiEconKit.run(m, 100)
		ticks += 100
		if ctx.view.struct_count(rad) == 0:
			t.eq(eco.production.trained_role[AiTypes.R_TANK_MAIN], 0, "no tank is queued before the Radar (tick %d)" % ctx.tick)
	t.gt(ctx.view.struct_count(rad), 0, "the Radar comes")
	t.gt(eco.production.trained_role[AiTypes.R_INFANTRY_BASIC], 0, "the line is held with infantry meanwhile")


func test_air_sighting_brings_anti_air(t: TestCtx) -> void:
	var pair: Array = _pair(func(ctx: AiContext) -> void: ctx.kb.profiles[1].observe(AiTypes.Cat.AIR, 3000, ctx.tick))
	var control: Dictionary = pair[0]
	var react: Dictionary = pair[1]
	var ceco: AiEconomy = control["eco"]
	var reco: AiEconomy = react["eco"]
	t.check_false(ceco.tech.trigger_active(AiTypes.Cat.AIR), "control: no air trigger")
	t.check(reco.tech.trigger_active(AiTypes.Cat.AIR), "air trigger active")
	t.gt((react["share"] as PackedInt32Array)[AiTypes.R_AA_MOBILE], (control["share"] as PackedInt32Array)[AiTypes.R_AA_MOBILE], "AA_MOBILE share rises")
	t.gt((react["weight"] as PackedInt32Array)[AiTypes.R_AA_MOBILE], 2 * (control["weight"] as PackedInt32Array)[AiTypes.R_AA_MOBILE] * 9 / 10, "AA_MOBILE weight ~x2 or more")
	t.ge(reco.production.trained_role[AiTypes.R_AA_MOBILE] + reco.struct_own[reco._ctx.res.structure_of_kind(AiTypes.StructKind.AA_BATTERY)] + reco.struct_q[reco._ctx.res.structure_of_kind(AiTypes.StructKind.AA_BATTERY)], 1, "anti-air was produced or built")
	t.gt(reco.tech.switches, ceco.tech.switches)
	t.note("AA units trained: control %d, scouted %d; AA share %d -> %d" % [ceco.production.trained_role[AiTypes.R_AA_MOBILE], reco.production.trained_role[AiTypes.R_AA_MOBILE],
		(control["share"] as PackedInt32Array)[AiTypes.R_AA_MOBILE], (react["share"] as PackedInt32Array)[AiTypes.R_AA_MOBILE]])


func test_air_sighting_builds_aa_batteries(t: TestCtx) -> void:
	var results: Array = []
	for scouted: bool in [false, true]:
		var m: Dictionary = _match()
		AiEconKit.run(m, SCOUT_TICK)
		var ctx: AiContext = AiEconKit.ctx_of(m, 0)
		if scouted:
			ctx.kb.profiles[1].observe(AiTypes.Cat.AIR, 3000, ctx.tick)
		AiEconKit.run(m, REACT_TICKS)
		results.append(_count_kind(AiEconKit.eco_of(m, 0), ctx, AiTypes.StructKind.AA_BATTERY))
	t.eq(results[0], 0, "control: no AA battery")
	t.ge(results[1], 1, "scouted air: AA battery COUNTER wants were built (%d)" % results[1])


func test_armor_sighting_brings_anti_armor(t: TestCtx) -> void:
	var results: Array = []
	var weights: Array = []
	for scouted: bool in [false, true]:
		var m: Dictionary = _match()
		AiEconKit.run(m, SCOUT_TICK)
		var ctx: AiContext = AiEconKit.ctx_of(m, 0)
		var eco: AiEconomy = AiEconKit.eco_of(m, 0)
		if scouted:
			ctx.kb.profiles[1].observe(AiTypes.Cat.ARMOR, 6000, ctx.tick)
		AiEconKit.run(m, 150)
		weights.append(eco.comp.weight.duplicate())
		AiEconKit.run(m, REACT_TICKS - 150)
		results.append(_count_kind(eco, ctx, AiTypes.StructKind.AT_TURRET))
		if scouted:
			t.check(eco.tech.trigger_active(AiTypes.Cat.ARMOR), "armor trigger active")
	var c: PackedInt32Array = weights[0]
	var r: PackedInt32Array = weights[1]
	t.gt(r[AiTypes.R_INFANTRY_AT], c[AiTypes.R_INFANTRY_AT] * 16 / 10, "INFANTRY_AT weight x1.8")
	t.lt(r[AiTypes.R_TANK_MAIN], c[AiTypes.R_TANK_MAIN], "TANK_MAIN weight x0.9")
	t.ge(results[1], results[0] + 1, "armor: an AT turret was added (%d vs control %d)" % [results[1], results[0]])


func test_camouflage_and_hysteresis(t: TestCtx) -> void:
	var m: Dictionary = _match({"rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"])})
	AiEconKit.run(m, SCOUT_TICK)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	AiEconKit.run(m, 150)
	ctx.kb.profiles[1].camo_seen = true
	AiEconKit.run(m, 100)
	t.check(eco.tech.trigger_active(AiTypes.Cat.CAMO), "camouflage trigger")
	# the composition rule itself: < 10 %% detectors in the army doubles the roles whose def is a detector
	var b: AiBudget = AiBudget.new()
	var weights: Array = []
	for detectors: int in [0, 5]:
		eco.army_units = 10
		eco.detector_alive = detectors
		eco.comp._calc_tick = -100000
		b.reset(100000, 100000)
		eco.comp.update(ctx, b)
		weights.append(eco.comp.weight.duplicate())
	var low: PackedInt32Array = weights[0]
	var ok: PackedInt32Array = weights[1]
	var doubled: int = 0
	for r: int in eco.comp.roles:
		var d: int = eco.comp.def_pick[r]
		if d >= 0 and ctx.res.has_bit(d, AiTypes.R_DETECTOR) and ok[r] > 0:
			t.eq(low[r], ok[r] * 2, "%s (detector def) doubled" % AiTypes.ROLE_NAMES[r])
			doubled += 1
		elif ok[r] > 0:
			t.eq(low[r], ok[r], "%s unchanged" % AiTypes.ROLE_NAMES[r])
	t.ge(doubled, 1, "at least one composition role provides detectors")
	# hysteresis: the trigger outlives its cause for 300 s
	ctx.kb.profiles[1].camo_seen = false
	AiEconKit.run(m, 600)
	t.check(eco.tech.trigger_active(AiTypes.Cat.CAMO), "still active 600 ticks after the cause vanished")
	t.gt(eco.tech.until[AiTypes.Cat.CAMO], ctx.tick + 3000, "300 s hysteresis")


func test_personality_and_phase_shape_the_weights(t: TestCtx) -> void:
	var usa: Dictionary = _match({"rosters": PackedStringArray(["roster.napc.usa", "roster.napc.vanilla"]), "fog": false})
	var eco: AiEconomy = AiEconKit.eco_of(usa, 0)
	var van: AiEconomy = AiEconKit.eco_of(usa, 1)
	eco.comp.phase_override = AiTypes.Phase.MIDGAME
	van.comp.phase_override = AiTypes.Phase.MIDGAME
	AiEconKit.run(usa, 400)
	t.eq(eco.comp.phase, AiTypes.Phase.MIDGAME, "the brain may force a phase")
	t.gt(eco.comp.weight[AiTypes.R_FIGHTER], 3 * van.comp.weight[AiTypes.R_FIGHTER], "USA (air 65) weights fighters far above vanilla")
	t.eq(eco.comp.weight[AiTypes.R_HEAVY], 0, "USA's doctrine drops the Heavy")
	# roles that want a structure that is not there pull it
	t.check(eco.comp.pull.has(AiTypes.R_FIGHTER), "fighters pull the Airfield (tech pull)")
	AiEconKit.run(usa, 9400)  # the Airfield target is due at 7:00 (AIT), the tech pull of the fighters may bring it earlier
	var af: int = AiEconKit.ctx_of(usa, 0).res.structure_of_kind(AiTypes.StructKind.AIRFIELD)
	t.check(eco.struct_own[af] + eco.struct_q[af] > 0 or eco.find_want(AiTypes.WantKind.STRUCT, af, AiTypes.WantOrigin.TARGET) != null or eco.find_want(AiTypes.WantKind.STRUCT, af, AiTypes.WantOrigin.TECH) != null, "USA builds (or has asked for) an Airfield")


func test_stat_multiplier_uses_resolved_damage_against_the_seen_armor(t: TestCtx) -> void:
	var m: Dictionary = _match({"fog": false})
	AiEconKit.run(m, SCOUT_TICK)
	var ctx: AiContext = AiEconKit.ctx_of(m, 0)
	var eco: AiEconomy = AiEconKit.eco_of(m, 0)
	var b: AiBudget = AiBudget.new()
	b.reset(100000, 100000)
	eco.comp._calc_tick = -100000
	eco.comp.update(ctx, b)
	t.eq(eco.comp.stat_mult_q8[AiTypes.R_INFANTRY_AT], 256 if eco.comp.armor_mix[0] + eco.comp.armor_mix[1] == 0 else eco.comp.stat_mult_q8[AiTypes.R_INFANTRY_AT], "neutral without a sighting")
	# six heavy tanks are visible: rockets beat rifles, and everything stays inside the clamp
	var tank: int = SimMatchKit.data().unit_idx("unit.napc.bastion_heavy_tank")
	var t_e: AiEntityTable = ctx.kb.enemy_units
	var prof: AiUnitProfile = ctx.unit_profile_of(1, tank)
	for i: int in 6:
		var r: int = t_e.upsert(90000 + i)
		t_e.def[r] = tank
		t_e.owner[r] = 1
		t_e.kind[r] = AiTypes.KIND_UNIT
		t_e.hp[r] = prof.hp
		t_e.hp_max[r] = prof.hp
		t_e.paid[r] = prof.value
		t_e.last_seen[r] = ctx.tick
	eco.comp._calc_tick = -100000
	b.reset(100000, 100000)
	eco.comp.update(ctx, b)
	var at: int = eco.comp.stat_mult_q8[AiTypes.R_INFANTRY_AT]
	var rifle: int = eco.comp.stat_mult_q8[AiTypes.R_INFANTRY_BASIC]
	t.gt(at, rifle, "anti-tank infantry beats rifles against heavy armor (%d vs %d)" % [at, rifle])
	for r2: int in eco.comp.roles:
		t.check(eco.comp.stat_mult_q8[r2] >= AiComposition.STAT_MULT_MIN_Q8 and eco.comp.stat_mult_q8[r2] <= AiComposition.STAT_MULT_MAX_Q8, "clamped")
	# Easy never uses it
	var easy: Dictionary = _match({"fog": false, "level": AiTypes.Difficulty.EASY})
	AiEconKit.run(easy, 100)
	var ectx: AiContext = AiEconKit.ctx_of(easy, 0)
	var e_e: AiEntityTable = ectx.kb.enemy_units
	for i2: int in 6:
		var r3: int = e_e.upsert(91000 + i2)
		e_e.def[r3] = tank
		e_e.owner[r3] = 1
		e_e.paid[r3] = prof.value
		e_e.last_seen[r3] = ectx.tick
	var ec: AiComposition = AiEconKit.eco_of(easy, 0).comp
	ec._calc_tick = -100000
	b.reset(100000, 100000)
	ec.update(ectx, b)
	t.eq(ec.stat_mult_q8[AiTypes.R_INFANTRY_AT], 256, "Easy: neutral")
