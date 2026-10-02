extends RefCounted
## DATA-07: DefPlayerView (data_balance 3.13 / 10.1 "player view"): economy / abilities / combat shaped accessors on
## top of a roster and its DefLayer3.

const K := DefEnums.Kind
const S := DefEnums.Stat

static var _real: GameData = null


static func real() -> GameData:
	if _real == null:
		_real = DefTestKit.stub_game_data(true)
	return _real


static func hu(n: int, d: int) -> int:
	return (2 * n + d) / (2 * d)


func test_flat_tables_of_a_roster(t: TestCtx) -> void:
	var d: GameData = real()
	if not t.not_null(d, "load: " + GameData.last_report.text(6)):
		return
	var r: DefRoster = d.roster_for("napc")
	var v: DefPlayerView = DefPlayerView.new(d, r)
	var g: int = d.unit_idx("unit.napc.guardian_tank")
	var clone: DefUnit = r.unit(g)
	t.eq(v.unit_cost.size(), d.units.size(), "unit table sized to the unit defs")
	t.eq(v.struct_cost.size(), d.structures.size(), "structure table sized to the structure defs")
	t.eq(v.unit_cost[g], clone.cost, "unit_cost = roster clone")
	t.eq(v.unit_cost[g], 935, "935 (850 + 10 %)")
	t.eq(v.unit_ticks[g], clone.build_ticks, "unit_ticks")
	t.eq(v.unit_available[g], 1, "producible")
	t.eq(v.unit_cap_cost[g], 1, "cap weight")
	t.eq(v.unit_cap_cost[d.unit_idx("unit.shared.collector")], 0, "collector is cap exempt")
	t.eq(v.unit_repair_cost_bp[g], 5000, "repair price")
	t.eq(v.unit_cost[d.unit_idx("unit.napc.beaver_amphibious_apc")], 0, "not in the roster: 0")
	t.eq(v.unit_available[d.unit_idx("unit.napc.beaver_amphibious_apc")], 0, "not available")
	t.eq(v.unit_available[d.unit_idx("summon.napc.uav")], 0, "summons are never producible")
	t.eq(v.struct_power[d.structure_idx("structure.shared.generator")], 150, "generator power")
	t.eq(v.struct_power[d.structure_idx("structure.shared.refinery")] < 0, true, "consumers are negative")
	t.eq(v.struct_cost[d.structure_idx("structure.shared.factory")], d.structures[d.structure_idx("structure.shared.factory")].cost, "factory cost")
	t.eq(v.struct_available[d.structure_idx("structure.shared.headquarters")], 0, "HQ is not buildable")
	t.eq(v.struct_available[d.structure_idx("structure.shared.radar")], 1, "radar")
	t.eq(v.struct_available[d.structure_idx("structure.nec.relay")], 0, "not in the roster")
	t.eq(v.struct_repair_rate_bp[d.structure_idx("structure.shared.radar")], 10000, "repair rate base")
	t.eq(v.struct_repair_cost_bp[d.structure_idx("structure.shared.radar")], 5000, "structure repair price")
	t.eq(v.struct_ticks[d.structure_idx("structure.shared.generator")], 500, "structure build ticks")
	t.eq(v.research_available.size(), d.research.size(), "research table")
	var avail: int = 0
	for x: int in v.research_available:
		avail += x
	t.eq(avail, 2, "vanilla: 2 research")
	t.eq(v.research_available[d.research_idx("research.napc.adaptive_plating")], 1, "adaptive plating")
	t.eq(v.power_of_slot, r.power_list, "power per slot")
	t.eq(v.super_idx, d.superweapon_idx("superweapon.napc.atlas_kinetic_array"), "superweapon")
	t.eq(v.version, 0, "layer 3 version")
	t.eq(v.data, d, "data")
	t.eq(v.roster, r, "roster")
	t.eq(v.layer3.roster, r, "layer 3 shares the roster")


func test_stats_shapes(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var r: DefRoster = d.roster_for("napc")
	var v: DefPlayerView = DefPlayerView.new(d, r)
	var g: int = d.unit_idx("unit.napc.guardian_tank")
	var clone: DefUnit = r.unit(g)
	var st: PackedInt32Array = v.resolved_stats(K.UNIT, g)
	t.eq(st.size(), S.COUNT, "indexed by DefEnums.Stat")
	t.eq(st[S.HEALTH], clone.health, "health equals the roster clone")
	t.eq(st[S.HEALTH], 997, "997")
	t.eq(st[S.COST], clone.cost, "cost")
	t.eq(st[S.BUILD_TIME], clone.build_ticks, "build time")
	t.eq(st[S.SPEED], clone.speed, "speed")
	t.eq(st[S.SIGHT], clone.sight, "sight")
	t.eq(st[S.RANGE], clone.max_range, "range")
	t.eq(st[S.DAMAGE], clone.weapons[0].damage, "damage of slot 0")
	t.eq(st[S.RELOAD], clone.weapons[0].reload_mt, "reload of slot 0 in milli-ticks")
	t.eq(st[S.REARM], 0, "not applicable: 0")
	t.eq(st[S.POWER], 0, "units have no power")
	t.eq(v.resolved_stats(K.UNIT, g), st, "cached")
	var base: PackedInt32Array = v.base_stats(K.UNIT, g)
	t.eq(base[S.HEALTH], 906, "unmodified base health")
	t.eq(base[S.COST], 850, "unmodified base cost")
	var gen: PackedInt32Array = v.resolved_stats(K.STRUCTURE, d.structure_idx("structure.shared.generator"))
	t.eq(gen[S.POWER], 150, "structure power")
	t.eq(gen[S.HEALTH], 1200, "structure health")
	t.eq(v.base_stats(K.STRUCTURE, d.structure_idx("structure.shared.generator"))[S.POWER], 150, "base power")
	t.eq(v.resolved_stats(K.UNIT, 99999).size(), S.COUNT, "unknown def: all zero")
	# combat shaped
	var s0: DefWeaponSlot = v.slot(g, 0)
	t.check(s0 == clone.weapons[0], "the roster clone's slot")
	t.check(v.slot(g, 5) == null and v.slot(d.unit_idx("unit.napc.beaver_amphibious_apc"), 0) == null, "absent slot / unit")
	t.eq(v.effective_slot_value(g, 0, S.DAMAGE), s0.damage, "no research: the resolved value")
	t.eq(v.effective_slot_value(g, 0, S.DAMAGE, 2000), hu(s0.damage * 12000, 10000), "temporaries add")
	t.eq(v.effective_slot_value(g, 0, S.RELOAD, -9000), maxi(1, DefConvert.ceil_div(d.units[g].weapons[0].reload_mt * 5000, 10000)), "50 % reload floor")
	t.eq(v.effective_slot_value(g, 0, S.RANGE), s0.range, "range")
	t.eq(v.effective_slot_value(g, 0, S.HEALTH), 0, "not a slot stat")


func test_research_updates_the_view(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var r: DefRoster = d.roster_for("napc")
	var v: DefPlayerView = DefPlayerView.new(d, r)
	var g: int = d.unit_idx("unit.napc.guardian_tank")
	t.eq(v.research_resist_bp(K.UNIT, g, DefEnums.DamageType.AP), 0, "before")
	v.apply_research(d.research_idx("research.napc.adaptive_plating"))
	t.eq(v.research_resist_bp(K.UNIT, g, DefEnums.DamageType.AP), 1000, "adaptive plating: explosive")
	t.eq(v.research_resist_bp(K.UNIT, g, DefEnums.DamageType.BULLET), 0, "not bullet")
	t.eq(v.research_resist_bp(K.STRUCTURE, 0, DefEnums.DamageType.AP), 0, "structures")
	t.eq(v.version, 1, "version incremented")
	t.eq(v.layer3.version, 1, "layer 3 too")
	# refresh() is a no-op when nothing changed: a marker survives it
	v.unit_cost[g] = 12345
	v.refresh()
	t.eq(v.unit_cost[g], 12345, "no rebuild without a version change")
	v.apply_research(d.research_idx("research.napc.dispersed_runways"))
	t.eq(v.unit_cost[g], r.unit(g).cost, "rebuilt after a research completion")
	t.eq(v.checksum(), v.layer3.checksum(), "checksum == layer3.checksum()")
	# health research feeds resolved_stats and the effective slot values
	var ae: DefRoster = d.roster_for("ae")
	var va: DefPlayerView = DefPlayerView.new(d, ae)
	var buffalo: int = d.unit_idx("unit.ae.buffalo_tank")
	var before: int = va.resolved_stats(K.UNIT, buffalo)[S.HEALTH]
	va.apply_research(d.research_idx("research.ae.circular_armor"))
	t.eq(va.resolved_stats(K.UNIT, buffalo)[S.HEALTH], hu(before * 11000, 10000), "resolved health after research")
	t.eq(va.base_stats(K.UNIT, buffalo)[S.HEALTH], d.units[buffalo].health, "base stays")
	# research that touches the flat tables: rearm and repair price
	var pd: DefPlayerView = DefPlayerView.new(d, d.roster_for("pd"))
	var fighter: int = -1
	for i: int in d.units.size():
		var u: DefUnit = pd.roster.unit(i)
		if u != null and u.rearm_t > 0 and (u.tags & DefEnums.UT_COMBAT) != 0 and (u.tags & DefEnums.UT_AIRCRAFT) != 0:
			fighter = i
			break
	t.check(fighter >= 0, "PD owns a rearming aircraft")
	var rearm0: int = pd.unit_rearm_ticks[fighter]
	pd.apply_research(d.research_idx("research.pd.integrated_flight_decks"))
	t.eq(pd.unit_rearm_ticks[fighter], hu(rearm0 * 8500, 10000), "rearm -15 % in the flat table")
	var dv: DefPlayerView = DefPlayerView.new(d, d.roster_for("def"))
	var tank: int = d.unit_idx("unit.def.hammer_tank")
	t.eq(dv.unit_repair_cost_bp[tank], 5000, "before")
	dv.apply_research(d.research_idx("research.def.standardized_parts"))
	t.eq(dv.unit_repair_cost_bp[tank], 4250, "Standardized Parts")


func test_base_roster_view(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var v: DefPlayerView = DefPlayerView.new(d, d.base_roster)
	var g: int = d.unit_idx("unit.napc.guardian_tank")
	t.eq(v.unit_cost[g], d.units[g].cost, "the neutral view shows the unmodified defs")
	t.eq(v.resolved_stats(K.UNIT, g)[S.HEALTH], 906, "base health")
	t.eq(v.research_available.size(), d.research.size(), "tables exist")
	v.apply_research(0)
	t.eq(v.version, 1, "research on the base roster just records (no selector matches)")
