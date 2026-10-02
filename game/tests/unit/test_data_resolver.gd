extends RefCounted
## DATA-06: the static modifier fold (data_balance 5.5 / 5.6 / 10.1 "modifier folding", golden 158 applications).
## Expected numbers are computed here with plain integer half-up arithmetic from the BASE def values and the bible's
## percentages, independent of DefStatMath.

const K := DefEnums.Kind
const S := DefEnums.Stat

static var _real: GameData = null


static func real() -> GameData:
	if _real == null:
		_real = DefTestKit.stub_game_data(true)
	return _real


## half_up(n / d)
static func hu(n: int, d: int) -> int:
	return (2 * n + d) / (2 * d)


func _u(d: GameData, roster: String, sub: String, unit_id: String) -> DefUnit:
	return d.roster_for(roster, sub).unit(d.unit_idx(unit_id))


func _s(d: GameData, roster: String, sub: String, id: String) -> DefStructure:
	return d.roster_for(roster, sub).structure(d.structure_idx(id))


func _base(d: GameData, unit_id: String) -> DefUnit:
	return d.units[d.unit_idx(unit_id)]


## Bible percent (x100 = bp) of modifier `id`.
func _bp(d: GameData, id: String) -> int:
	return d.modifiers[d.ids.index_of(K.MODIFIER, id)].delta_bp


func test_golden_158_applications(t: TestCtx) -> void:
	var d: GameData = real()
	if not t.not_null(d, "load: " + GameData.last_report.text(6)):
		return
	var apps: int = 0
	var mismatches: int = 0
	for r: DefRoster in d.rosters:
		var lines: PackedStringArray = DefRosterBuilder.golden_mismatches(d, r)
		mismatches += lines.size()
		apps += (d._sources.bible["rosters"][r.id]["resolved"]["modifier_applications"] as Array).size()
		for l: String in lines:
			t.fail("%s: %s" % [r.id, l])
	t.eq(apps, 158, "158 modifier applications in the bible")
	t.eq(mismatches, 0, "0 mismatches: selectors, conditions, unresolved domains, superweapon matches, lists")
	t.eq(d.rosters.size(), 32, "32 rosters")


func test_layer_products_of_5_6(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	# 1: NAPC vanilla Guardian, parent layer only: cost +10 %, health +10 %, build time untouched
	var g0: DefUnit = _base(d, "unit.napc.guardian_tank")
	var g: DefUnit = _u(d, "napc", "", "unit.napc.guardian_tank")
	t.eq(g.cost, hu(g0.cost * 11000, 10000), "cost x1.10")
	t.eq(g.health, hu(g0.health * 11000, 10000), "health x1.10 (996.6 -> 997)")
	t.eq(g.build_ticks, g0.build_ticks, "build ticks unchanged")
	t.eq(g0.health, 906, "the base def is never touched")
	# 2: Canada Narwhal: parent + subfaction layers multiply with ONE rounding
	var n0: DefUnit = _base(d, "unit.napc.narwhal_amphibious_tank")
	var n: DefUnit = _u(d, "napc", "canada", "unit.napc.narwhal_amphibious_tank")
	t.eq(n.health, hu(n0.health * 11000 * 11000, 100000000), "health x1.21 in one rounding")
	t.eq(n.cost, hu(n0.cost * 11000, 10000), "cost x1.10")
	t.eq(n.health, 1102, "911 -> 1102")
	# 3 + 4: Beaver: rounding half up, ON_WATER goes to water_mult only
	var b0: DefUnit = _base(d, "unit.napc.beaver_amphibious_apc")
	var b: DefUnit = _u(d, "napc", "canada", "unit.napc.beaver_amphibious_apc")
	t.eq(b.health, hu(b0.health * 12100, 10000), "health x1.21")
	t.eq(b.cost, hu(b0.cost * 11000, 10000), "cost x1.10 half-up (533.5 -> 534)")
	t.eq(b.water_mult_bp, 12000, "canada.03 folded into water_mult_bp only")
	t.eq(b.speed, b0.speed, "land speed unchanged")
	t.eq(b.speed_water, DefMoveTable.effective_speed(d.moves, b.speed, b.move_class, DefEnums.TerrainKind.DEEP, 0, 12000), "speed_water = ONE rounding of table x water multiplier")
	t.eq(b.speed_water, hu(b0.speed * 7000 * 12000, 100000000), "independent: half_up(speed * 0.7 * 1.2)")
	t.eq(b0.water_mult_bp, 10000, "base water multiplier")
	# 5: Paladin reload +15 % (the modifier makes the interval LONGER: no floor involved)
	var p0: DefUnit = _base(d, "unit.napc.paladin_howitzer")
	var p: DefUnit = _u(d, "napc", "canada", "unit.napc.paladin_howitzer")
	for i: int in p0.weapons.size():
		t.eq(p.weapons[i].reload_mt, hu(p0.weapons[i].reload_mt * 11500, 10000), "reload_mt x1.15 slot %d" % i)
		t.eq(p.weapons[i].reload_ticks, DefConvert.ceil_div(p.weapons[i].reload_mt, 1000), "reload_ticks = ceil")
		t.check(p.weapons[i] != p0.weapons[i], "clone slots do not alias the base")
	# 6: USA aircraft cost -15 %, rearm -20 %, land-vehicle build time +15 %
	var r0: DefUnit = _base(d, "unit.napc.raptor_multirole_fighter")
	var r: DefUnit = _u(d, "napc", "usa", "unit.napc.raptor_multirole_fighter")
	t.eq(r.cost, hu(r0.cost * 8500, 10000), "cost x0.85")
	t.eq(r.rearm_t, hu(r0.rearm_t * 8000, 10000), "rearm x0.80")
	t.eq(r.rearm_t, 128, "160 -> 128")
	var ug0: DefUnit = _base(d, "unit.napc.guardian_tank")
	t.eq(_u(d, "napc", "usa", "unit.napc.guardian_tank").build_ticks, hu(ug0.build_ticks * 11500, 10000), "build time x1.15")
	t.eq(_u(d, "napc", "usa", "unit.napc.guardian_tank").build_ticks, 633, "550 -> 633")
	# 7: Han China: parent -10 % health, sub +15 %  (1.10 x 0.90 pattern of the bible)
	var i0: DefUnit = _base(d, "unit.han.imperial_guard_tank")
	t.eq(_u(d, "han", "china", "unit.han.imperial_guard_tank").health, hu(i0.health * 9000 * 11500, 100000000), "health x0.9 x1.15")
	# 8: Russia Ural
	var ur0: DefUnit = _base(d, "unit.def.ural_assault_tank")
	var ur: DefUnit = _u(d, "def", "russia", "unit.def.ural_assault_tank")
	t.eq(ur.cost, hu(ur0.cost * 9000 * 11000, 100000000), "cost x0.99")
	t.eq(ur.speed, hu(ur0.speed * 9000 * 9000, 100000000), "speed x0.81")
	# 9: Generator: OLM parent +25 %, Saudi sub +20 %
	var gen0: DefStructure = d.structures[d.structure_idx("structure.shared.generator")]
	t.eq(_s(d, "olm", "", "structure.shared.generator").power, hu(gen0.power * 12500, 10000), "OLM vanilla 187.5 -> 188")
	t.eq(_s(d, "olm", "", "structure.shared.generator").power, 188, "188")
	t.eq(_s(d, "olm", "saudi_arabia", "structure.shared.generator").power, hu(gen0.power * 12500 * 12000, 100000000), "Saudi 225")
	t.eq(gen0.power, 150, "base generator")
	t.eq(_s(d, "olm", "", "structure.shared.radar").power, d.structures[d.structure_idx("structure.shared.radar")].power, "power modifiers only touch generators (power > 0)")
	# 10: Eurocorps Marte: parent +5 % all combat units, sub +10 % tanks
	var m0: DefUnit = _base(d, "unit.nec.marte_heavy_mbt")
	t.eq(_u(d, "nec", "eurocorps", "unit.nec.marte_heavy_mbt").cost, hu(m0.cost * 10500 * 11000, 100000000), "cost x1.155")
	# 12: Cambodia Firefly (unmanned -15 %) and the carrier drone replacement cost (U1)
	var f0: DefUnit = _base(d, "unit.han.firefly_aa_drone")
	t.eq(_u(d, "han", "cambodia", "unit.han.firefly_aa_drone").cost, hu(f0.cost * 8500, 10000), "cost x0.85")
	var cam: DefRoster = d.roster_for("han", "cambodia")
	var unmanned: int = 0
	for cu: DefUnit in cam.units:
		if cu != null and (cu.tags & DefEnums.UT_COMBAT) != 0 and (cu.tags & DefEnums.UT_UNMANNED) != 0 and d.units[cu.index].cost > 0:
			unmanned += 1
			t.eq(cu.cost, hu(d.units[cu.index].cost * 8500, 10000), "unmanned combat unit / carrier drone cost x0.85 (%s)" % cu.id)
	t.check(unmanned >= 4, "Cambodia's unmanned combat units (%d)" % unmanned)
	var china_drone: int = d.unit_idx("summon.han.emperor_strike_drone")
	t.eq(d.roster_for("han", "china").units[china_drone].cost, d.units[china_drone].cost, "other rosters keep the drone cost")


func test_scoped_modifiers(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	# Nigeria: structure build time on non-superweapon structures only (HQ has no build time, Horizon is a superweapon)
	var mid: String = ""
	for m: DefModifier in d.modifiers:
		if m.stat == S.BUILD_TIME and m.owner_is_roster and m.owner == d.roster_idx("roster.ae.nigeria"):
			mid = m.id
	t.ne(mid, "", "Nigeria has a build-time modifier")
	var nb: int = _bp(d, mid)
	var gen0: DefStructure = d.structures[d.structure_idx("structure.shared.generator")]
	t.eq(_s(d, "ae", "nigeria", "structure.shared.generator").build_ticks, hu(gen0.build_ticks * (10000 + nb), 10000), "generator build time scaled")
	t.eq(_s(d, "ae", "nigeria", "structure.shared.headquarters").build_ticks, 0, "HQ has no build time")
	var hz: DefStructure = d.structures[d.structure_idx("structure.ae.horizon_mass_driver")]
	t.eq(_s(d, "ae", "nigeria", "structure.ae.horizon_mass_driver").build_ticks, hz.build_ticks, "Horizon (superweapon) untouched")
	t.eq(d.roster_for("ae", "nigeria").superweapon_def.recharge_t, d.superweapons[d.roster_for("ae", "nigeria").superweapon].recharge_t, "recharge is a superweapon field")
	# Kazakhstan: refinery discount, not the free Collector
	var kz: DefRoster = d.roster_for("def", "kazakhstan")
	var ref0: DefStructure = d.structures[d.structure_idx("structure.shared.refinery")]
	t.eq(kz.structure(d.structure_idx("structure.shared.refinery")).cost, hu(ref0.cost * 8500, 10000), "refinery -15 %")
	t.eq(kz.unit(d.unit_idx("unit.shared.collector")).cost, 1400, "collector cost is the bible's 1400")
	# Indonesia: transport bonus includes the Landing Transport
	var lt0: DefUnit = _base(d, "unit.shared.landing_transport")
	t.eq(_u(d, "pd", "indonesia", "unit.shared.landing_transport").health, hu(lt0.health * 12000, 10000), "Landing Transport health +20 %")
	t.eq(_u(d, "pd", "japan", "unit.shared.landing_transport").health, lt0.health, "other PD rosters do not get it")
	# AE paid repair: static fold into repair_cost_bp of every land vehicle incl. service ones
	for sub: String in ["", "kongo", "nigeria", "south_africa"]:
		var ae: DefRoster = d.roster_for("ae", sub)
		for id: String in ["unit.shared.collector", "unit.shared.mobile_construction_vehicle", "unit.shared.landing_transport"]:
			t.eq(ae.unit(d.unit_idx(id)).repair_cost_bp, 3750, "%s repair cost in AE %s" % [id, sub])
		t.eq(ae.unit(d.unit_idx("unit.shared.engineer")).repair_cost_bp, 5000, "engineer is infantry")
		for au: DefUnit in ae.units:
			if au != null and au.unit_class != DefEnums.UnitClass.SUMMON and au.unit_class != DefEnums.UnitClass.DRONE:
				t.eq(au.repair_cost_bp, 3750 if (au.tags & DefEnums.UT_LAND_VEHICLE) != 0 else 5000, "%s repair cost in AE %s" % [au.id, sub])
	t.eq(_u(d, "napc", "", "unit.napc.guardian_tank").repair_cost_bp, 5000, "other factions pay the full price")
	# El Andalus: +20 % damage inside a civilian garrison, as a conditional value only
	var gg0: DefUnit = _base(d, "unit.olm.gate_guard")
	var gg: DefUnit = _u(d, "olm", "el_andalus", "unit.olm.gate_guard")
	for i: int in gg.weapons.size():
		t.eq(gg.weapons[i].damage, gg0.weapons[i].damage, "unconditional damage unchanged")
		t.eq(gg.weapons[i].cond_vals.size(), 1, "one conditional value")
		t.eq(gg.weapons[i].cond_vals[0].stat, S.DAMAGE, "stat")
		t.eq(gg.weapons[i].cond_vals[0].cond, DefEnums.Cond.IN_CIVILIAN_GARRISON, "cond 2")
		t.eq(gg.weapons[i].cond_vals[0].value, hu(gg0.weapons[i].damage * 12000, 10000), "value = full layered value, not a delta")
	t.eq(_u(d, "olm", "", "unit.olm.wayfarer_guard").weapons[0].cond_vals.size(), 0, "vanilla infantry has none")
	t.eq(_u(d, "olm", "el_andalus", "unit.olm.mirage_observer").cond_vals.size(), 0, "the unarmed Mirage Observer is a documented no-op")
	# Saudi: thermal-beam damage +15 % on beam slots only, Helios packets scaled through additional_superweapon_ids
	var saudi: DefRoster = d.roster_for("olm", "saudi_arabia")
	var ifr0: DefUnit = _base(d, "unit.olm.ifrit_prism_tank")
	var ifr: DefUnit = saudi.unit(d.unit_idx("unit.olm.ifrit_prism_tank"))
	for i2: int in ifr0.weapons.size():
		var beam: bool = (d.weapon_archs[ifr0.weapons[i2].arch].tags & DefEnums.WT_THERMAL_BEAM) != 0
		t.eq(ifr.weapons[i2].damage, hu(ifr0.weapons[i2].damage * 11500, 10000) if beam else ifr0.weapons[i2].damage, "beam slots only (slot %d)" % i2)
	var hel: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.olm.helios_reflector")]
	t.eq(saudi.superweapon_def.packets[0].damage, hu(hel.packets[0].damage * 11500, 10000), "Helios packet +15 %")
	t.eq(saudi.superweapon_def.packets[0].damage, 713, "620 -> 713")
	t.eq(d.roster_for("olm", "algeria").superweapon_def.packets[0].damage, hel.packets[0].damage, "other OLM rosters unchanged")
	t.eq(saudi.superweapon_def.recharge_t, hel.recharge_t, "reach and timing unaffected")
	t.check(saudi.superweapon_def != hel, "the roster owns a clone")
	# Pakistan: projectile speed of ordinary guided missiles only
	var pak: DefRoster = d.roster_for("sap", "pakistan")
	var hit: int = 0
	for u: DefUnit in pak.units:
		if u == null:
			continue
		var b: DefUnit = d.units[u.index]
		for i3: int in u.weapons.size():
			var missile: bool = d.weapon_archs[b.weapons[i3].arch].interceptable == DefEnums.Interceptable.APS_TRIDENT
			var want: int = hu(b.weapons[i3].proj_speed * 12000, 10000) if missile and b.weapons[i3].proj_speed > 0 else b.weapons[i3].proj_speed
			t.eq(u.weapons[i3].proj_speed, want, "%s slot %d projectile speed" % [u.id, i3])
			if missile:
				hit += 1
	t.check(hit > 0, "Pakistan has ordinary guided missiles")


func test_service_units_only_in_the_allowed_combat_matches(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	# V-MOD-10: the only (modifier, service unit) matches are pd.indonesia.02 -> landing transport, ae.01 -> collector / mcv / landing transport
	var pairs: Dictionary = {}
	for r: DefRoster in d.rosters:
		for mi: int in r.modifier_list:
			var m: DefModifier = d.modifiers[mi]
			for ui: int in r.selector_units(m.selector):
				if r.units[ui].unit_class == DefEnums.UnitClass.SERVICE:
					pairs["%s>%s" % [m.id, r.units[ui].id]] = true
	var keys: Array = pairs.keys()
	keys.sort()
	t.eq(keys, [
		"modifier.ae.01>unit.shared.collector", "modifier.ae.01>unit.shared.landing_transport",
		"modifier.ae.01>unit.shared.mobile_construction_vehicle", "modifier.pd.indonesia.02>unit.shared.landing_transport",
	], "exactly the four documented service-unit matches")
	# summons never take combat modifiers
	for r2: DefRoster in d.rosters:
		for ui2: int in r2.spawnables:
			var s: DefUnit = r2.units[ui2]
			if s.unit_class == DefEnums.UnitClass.SUMMON:
				t.eq(s.health, d.units[ui2].health, "summon %s untouched in %s" % [s.id, r2.id])


func test_static_sums_and_conditional_applications(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var canada: DefRoster = d.roster_for("napc", "canada")
	var n: int = d.unit_idx("unit.napc.narwhal_amphibious_tank")
	t.eq(canada.static_sums(K.UNIT, n, S.HEALTH), PackedInt32Array([1000, 1000]), "parent +10 % and subfaction +10 %")
	t.eq(canada.static_sums(K.UNIT, n, S.COST), PackedInt32Array([1000, 0]), "cost: parent only")
	t.eq(canada.static_sums(K.UNIT, n, S.RANGE), PackedInt32Array([0, 0]), "none")
	t.eq(d.roster_for("napc").static_sums(K.UNIT, d.unit_idx("unit.napc.guardian_tank"), S.HEALTH), PackedInt32Array([1000, 0]), "vanilla: layer 1 only")
	var conds: int = 0
	for r: DefRoster in d.rosters:
		var apps: Array[DefCondApplication] = r.conditional_applications()
		conds += apps.size()
		if r.id == "roster.napc.canada":
			t.eq(apps.size(), 1, "Canada: ON_WATER")
			t.eq(apps[0].cond, DefEnums.Cond.ON_WATER, "cond")
			t.eq(apps[0].stat, S.SPEED, "speed")
			t.check(apps[0].units.has(n), "narwhal")
		elif r.id == "roster.olm.el_andalus":
			t.eq(apps.size(), 1, "El Andalus: garrison")
			t.eq(apps[0].cond, DefEnums.Cond.IN_CIVILIAN_GARRISON, "cond 2")
		elif r.id.begins_with("roster.ae."):
			t.eq(apps.size(), 1, "AE: paid repair (%s)" % r.id)
			t.eq(apps[0].cond, DefEnums.Cond.PAID_VEHICLE_REPAIR, "cond 3")
		else:
			t.eq(apps.size(), 0, "no conditional modifiers in %s" % r.id)
	t.eq(conds, 6, "6 conditional applications in the bible (1 + 1 + 4)")


func test_resolver_errors(t: TestCtx) -> void:
	# an unsupported conditional combination (ON_WATER on health) is V-MOD-07
	var s: DefSources = DefTestKit.stub_sources(true)
	((s.bible["modifiers"] as Dictionary)["modifier.napc.canada.03"] as Dictionary)["stat"] = "health"
	t.check(GameData.load_from_sources(s) == null, "unsupported conditional combination refuses to load")
	t.check(GameData.last_report.has_rule("V-MOD-07"), "V-MOD-07")
	# two modifiers with the same (owner, stat, selector) in one roster: V-MOD-09
	var s2: DefSources = DefTestKit.stub_sources(true)
	var mods: Dictionary = s2.bible["modifiers"]
	var dup: Dictionary = (mods["modifier.napc.01"] as Dictionary).duplicate(true)
	mods["modifier.napc.09"] = dup
	((s2.bible["factions"] as Dictionary)["faction.napc"] as Dictionary)["passive_modifier_ids"].append("modifier.napc.09")
	t.check(GameData.load_from_sources(s2) == null, "duplicate (owner, stat, selector) refuses to load")
	t.check(GameData.last_report.has_rule("V-MOD-09"), "V-MOD-09")
