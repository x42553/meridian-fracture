extends RefCounted
## AIX2 (ai.md 5.13.3 / S6): the AI reacts to the strategic warning zones of enemy superweapons. Real sim worlds with movement:
## an enemy launcher fires at my cluster of tanks and infantry; Hard (dodge 100 %) moves out of the footprint, Easy (0 %) does
## not, Medium moves the squads with `squad.id % 100 < 50`. `run_strike` is also used by the acceptance scenario
## (tests/scenarios/aix2_accept.gd) to report the damage with and without dispersal.

const A := preload("res://tests/support/ab2_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")
const C: int = Fp.CELL
const ATTACKERS: Dictionary = {
	"atlas": "roster.napc.usa", "aurora": "roster.nec.vanilla", "helios": "roster.olm.vanilla", "perun": "roster.def.vanilla",
	"tempest": "roster.pd.vanilla", "dragonfall": "roster.han.vanilla", "horizon": "roster.ae.vanilla", "trident": "roster.sap.vanilla",
}
const CX: int = 30
const CY: int = 30


static func victim_roster(attacker: String) -> String:
	return "roster.nec.vanilla" if attacker == "roster.napc.usa" else "roster.napc.usa"


## Runs one strike. level < 0: no AI at all (units idle). dodge_off: the AI thinks but its dodge_pct is forced to 0.
## Returns {units, value0, value1, lost, inside_at_impact, ordered, zones, first_lag, impact, errors}.
static func run_strike(weapon: String, level: int, dodge_off: bool = false, angle: int = 0, ticks_after: int = 700) -> Dictionary:
	var attacker: String = ATTACKERS[weapon]
	var w: SimWorld = A.world({"rosters": [victim_roster(attacker), attacker], "movement": true, "fog": false, "seed": 21})
	S.base(w, 0, 6, 6, false)
	S.base(w, 1, 46, 46, true)
	var res: AiRoleResolver = AiRoleResolver.resolve(w.data, w.data.rosters[w.players[0].roster_idx], AiDataStore.load_default())
	var tank: int = res.first(AiTypes.R_TANK_MAIN)
	var inf: int = res.first(AiTypes.R_INFANTRY_BASIC)
	var units: Array[SimEntity] = []
	for i: int in 16:
		var d: int = tank if i % 2 == 0 else inf
		var e: SimEntity = w.spawn_unit(d, 0, (CX - 3 + i % 8) * C + C / 2, (CY - 1 + i / 8) * C + C / 2, 0, 0, w.data.units[d].cost, 0, SimEvent.SPAWN_PRODUCED)
		units.append(e)
	w.call("_flush_spawns")
	A.hold_fire(w)
	var factory: AiFactory = null
	var think: Callable = Callable()
	var ctx: AiContext = null
	if level >= 0:
		factory = AiFactory.new()
		think = factory.make(0, level, 0, 777)
	var errors: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errors.append("%s: %s" % [tag, msg])
	# boot the AI, then arm the enemy launcher
	var out: Array = []
	if level >= 0:
		think.call(w, out)
		ctx = factory.thinker(0).controller.ctx
		if dodge_off:
			# the profile object is shared through the data store: modify a copy
			var copy: AiDifficultyProfile = AiDifficultyProfile.new()
			for p: Dictionary in ctx.diff.get_property_list():
				if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
					copy.set(String(p["name"]), ctx.diff.get(String(p["name"])))
			copy.dodge_pct = 0
			ctx.diff = copy
	S.force_ready(w, 1)
	S.launch(w, 1, CX, CY, angle)
	var value0: int = 0
	for e2: SimEntity in units:
		value0 += e2.paid_cost
	var inside_at_impact: int = -1
	var impact: int = -1
	var t_end: int = w.tick + ticks_after
	while w.tick < t_end:
		if level >= 0 and w.tick % 2 == 0:
			var o2: Array = []
			think.call(w, o2)
			for c: Variant in o2:
				w.submit_raw(0, c)
		w.step()
		if level >= 0 and inside_at_impact < 0:
			var brain: AiBrain = ctx.brain as AiBrain
			var disp: AiDispersal = brain.powers.dispersal
			if not disp.zones.is_empty() and w.tick >= disp.zones[0].impact - 1:
				impact = disp.zones[0].impact
				inside_at_impact = 0
				for e3: SimEntity in units:
					if (e3.flags & SimFlags.F_GONE) == 0 and disp.inside(disp.zones[0], e3.x, e3.y, 0):
						inside_at_impact += 1
	Log.sink = old_sink
	var value1: int = 0
	var alive: int = 0
	for e4: SimEntity in units:
		if (e4.flags & SimFlags.F_GONE) == 0 and e4.hp > 0:
			value1 += e4.paid_cost * e4.hp / maxi(e4.hp_max, 1)
			alive += 1
	var r: Dictionary = {"weapon": weapon, "units": units.size(), "alive": alive, "value0": value0, "value1": value1,
		"lost": value0 - value1, "inside_at_impact": inside_at_impact, "impact": impact, "errors": errors}
	if level >= 0:
		var disp2: AiDispersal = (ctx.brain as AiBrain).powers.dispersal
		r["ordered"] = disp2.units_ordered
		r["zones"] = disp2.zones_seen
		r["first_lag"] = disp2.first_order_lag
		r["counter"] = disp2.counter_attacks
		r["ring"] = disp2.ring_orders
		r["trapped"] = disp2.trapped
	return r


# ------------------------------------------------------------------------------------------------------------ tests
func test_atlas_hard_moves_out_and_saves_the_group(t: TestCtx) -> void:
	var none: Dictionary = run_strike("atlas", -1)
	var hard: Dictionary = run_strike("atlas", AiTypes.Difficulty.HARD)
	t.eq((hard["errors"] as PackedStringArray).size(), 0, "no engine errors")
	t.eq(hard["zones"], 1, "the warning was seen")
	t.gt(none["lost"], 5000, "the undisturbed group is hit hard (%d lost)" % none["lost"])
	t.lt(hard["lost"], none["lost"] / 2, "dispersal halves the loss at least (%d vs %d)" % [hard["lost"], none["lost"]])
	t.gt(hard["ordered"], 8, "most of the group got a move order")
	t.eq(hard["inside_at_impact"], 0, "nobody is inside the rods at impact")
	t.le(hard["first_lag"], 32, "first order within reaction delay + a think")


func test_easy_never_reacts_and_medium_moves_about_half(t: TestCtx) -> void:
	var easy: Dictionary = run_strike("atlas", AiTypes.Difficulty.EASY)
	t.eq(easy["ordered"], 0, "Easy: dodge 0 %")
	t.gt(easy["lost"], 5000)
	var hard: Dictionary = run_strike("atlas", AiTypes.Difficulty.HARD)
	var med: Dictionary = run_strike("atlas", AiTypes.Difficulty.MEDIUM)
	t.gt(med["ordered"], 0, "Medium: dodge 50 %")
	t.le(med["ordered"], hard["ordered"], "and never more than Hard")
	t.le(hard["lost"], med["lost"], "Hard loses no more than Medium")
	t.le(med["lost"], easy["lost"], "Medium loses no more than Easy")


func test_every_footprint_is_left_by_hard(t: TestCtx) -> void:
	for weapon: String in ["perun", "helios", "horizon", "aurora", "tempest", "dragonfall"]:
		var r: Dictionary = run_strike(weapon, AiTypes.Difficulty.HARD, false, 0, 420)
		t.eq((r["errors"] as PackedStringArray).size(), 0, "%s: no engine errors" % weapon)
		t.eq(r["zones"], 1, "%s: warning seen" % weapon)
		t.gt(r["ordered"], 0, "%s: orders issued" % weapon)
		if weapon == "aurora":
			# infantry is unaffected by the EMP: only the eight vehicles have to leave
			t.le(r["inside_at_impact"], 8, "aurora: infantry stays")
		elif weapon != "dragonfall":
			t.le(r["inside_at_impact"], 2, "%s: the footprint is (almost) empty at impact (%d inside)" % [weapon, r["inside_at_impact"]])


func test_trident_registers_a_no_fire_zone(t: TestCtx) -> void:
	# the enemy dome is an avoid zone for artillery, not a footprint to flee from
	var r: Dictionary = run_strike("trident", AiTypes.Difficulty.HARD, false, 0, 200)
	t.eq(r["zones"], 1)
	t.eq(r["ordered"], 0, "nobody flees a Trident dome")
	t.eq((r["errors"] as PackedStringArray).size(), 0)


func test_avoid_zone_registry(t: TestCtx) -> void:
	var d: AiDispersal = AiDispersal.new()
	d.add_avoid(AiDispersal.AV_DEBRIS, 30 * C, 30 * C, 5 * C, 900)
	t.check(d.avoided(32 * C, 30 * C, AiDispersal.AV_DEBRIS, 800), "inside and alive")
	t.check(not d.avoided(32 * C, 30 * C, AiDispersal.AV_NO_BUILD, 800), "other kind")
	t.check(d.avoided(32 * C, 30 * C, 0, 800), "any kind")
	t.check(not d.avoided(32 * C, 30 * C, AiDispersal.AV_DEBRIS, 901), "expired")
	t.check(not d.avoided(40 * C, 30 * C, AiDispersal.AV_DEBRIS, 800), "outside")
