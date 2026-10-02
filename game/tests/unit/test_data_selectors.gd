extends RefCounted
## DATA-06: selector compilation and matching (data_balance 5.4 / 5.9 / 10.1 "selectors"; appendix 5.14.1 counts).

const K := DefEnums.Kind

## selector id -> [matching bible units, matching structures] by base tags (appendix 5.14.1)
const COUNTS: Dictionary = {
	"aircraft": [19, 0], "aircraft_or_ships": [45, 0], "airfields": [0, 1], "all_transports": [18, 0],
	"amphibious_combat_units": [12, 0], "amphibious_combat_vehicles": [12, 0], "amphibious_vehicles": [12, 0],
	"amphibious_vehicles_on_water": [12, 0], "combat_infantry": [37, 0], "combat_units": [152, 0],
	"defensive_structures": [0, 11], "garrisoned_combat_infantry": [37, 0], "generators": [0, 1],
	"ground_combat_units": [107, 0], "land_artillery": [16, 0], "land_combat_vehicles": [70, 0],
	"land_vehicle_repairs": [73, 0], "light_land_vehicles": [19, 0], "non_superweapon_structures": [0, 21],
	"ordinary_guided_missiles": [0, 0], "refineries": [0, 1], "scouts_or_artillery": [40, 0], "ships": [26, 0],
	"structures": [0, 29], "tanks": [25, 0], "thermal_beam_weapons": [0, 0], "unmanned_combat_units": [6, 0],
}

static var _real: GameData = null


static func real() -> GameData:
	if _real == null:
		_real = DefTestKit.stub_game_data(true)
	return _real


func test_27_selectors_compile_and_match_by_base_tags(t: TestCtx) -> void:
	var d: GameData = real()
	if not t.not_null(d, "load: " + GameData.last_report.text(6)):
		return
	var bible_sel: Dictionary = d._sources.bible["selectors"]
	t.eq(bible_sel.size(), 27, "27 bible selectors")
	for id: Variant in bible_sel.keys():
		var idx: int = d.selector_idx(str(id))
		if not t.check(idx >= 0, "%s compiled" % str(id)):
			continue
		var sel: DefSelector = d.selectors[idx]
		var want: Array = COUNTS[str(id).trim_prefix("selector.")]
		var units: int = 0
		for u: DefUnit in d.units:
			if u.id.begins_with("unit.") and DefResolver.matches_unit(sel, u.tags, u.index, u.unit_class, u.weapon_tags):
				units += 1
		var structs: int = 0
		for s: DefStructure in d.structures:
			if DefResolver.matches_structure(sel, s.tags, s.index, s.weapon_tags):
				structs += 1
		t.eq([units, structs], want, "%s matches" % str(id))


func test_named_selector_details(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var water: DefSelector = d.selectors[d.selector_idx("selector.amphibious_vehicles_on_water")]
	t.eq(water.cond, DefEnums.Cond.ON_WATER, "cond 1")
	t.eq(d.selectors[d.selector_idx("selector.garrisoned_combat_infantry")].cond, DefEnums.Cond.IN_CIVILIAN_GARRISON, "cond 2")
	t.eq(d.selectors[d.selector_idx("selector.land_vehicle_repairs")].cond, DefEnums.Cond.PAID_VEHICLE_REPAIR, "cond 3")
	t.eq(d.selectors[d.selector_idx("selector.unmanned_combat_units")].unresolved, 1, "U1")
	var th: DefSelector = d.selectors[d.selector_idx("selector.thermal_beam_weapons")]
	t.eq(th.unresolved, 2, "U2")
	t.check((th.weapon_all & DefEnums.WT_THERMAL_BEAM) != 0, "U2 adds the derived thermal_beam tag")
	t.eq(th.extra_superweapons, PackedInt32Array([d.superweapon_idx("superweapon.olm.helios_reflector")]), "Helios via additional_superweapon_ids")
	var gm: DefSelector = d.selectors[d.selector_idx("selector.ordinary_guided_missiles")]
	t.eq(gm.unresolved, 3, "U3")
	t.check((gm.proj_all & DefEnums.WT_GUIDED_MISSILE) != 0, "U3 adds guided_missile")
	# weapon / projectile matching through the archetype tags
	var beam: int = d.weapon_archs[DefEnums.WeaponArch.BEAM_THERMAL].tags
	t.check(DefResolver.matches_weapon(th, beam) and not DefResolver.matches_weapon(th, d.weapon_archs[DefEnums.WeaponArch.TANK_CANNON].tags), "thermal_beam_weapons = beam_thermal only")
	var missiles: Array[int] = [DefEnums.WeaponArch.AT_MISSILE, DefEnums.WeaponArch.AA_MISSILE, DefEnums.WeaponArch.MISSILE_ARTILLERY, DefEnums.WeaponArch.AIR_MISSILE, DefEnums.WeaponArch.CRUISE_MISSILE, DefEnums.WeaponArch.DRONE_MISSILE]
	for a: int in missiles:
		t.check(DefResolver.matches_projectile(gm, d.weapon_archs[a].tags), "%s is an ordinary guided missile" % DefEnums.WEAPON_ARCH_NAMES[a])
	t.check(not DefResolver.matches_projectile(gm, d.weapon_archs[DefEnums.WeaponArch.ARTILLERY_SHELL].tags), "shells are not guided missiles")
	t.check(not DefResolver.matches_projectile(gm, d.weapon_archs[DefEnums.WeaponArch.TANK_CANNON].tags), "cannon shells neither")
	# Saudi has beam slots (the modifier is not dead), Pakistan has guided-missile slots
	var found_beam: bool = false
	for u: DefUnit in d.roster_for("olm", "saudi_arabia").units:
		if u != null and (u.weapon_tags & DefEnums.WT_THERMAL_BEAM) != 0:
			found_beam = true
	t.check(found_beam, "V-MOD-13: Saudi Arabia owns a thermal-beam slot")
	var found_missile: bool = false
	for u2: DefUnit in d.roster_for("sap", "pakistan").units:
		if u2 != null and (u2.weapon_tags & DefEnums.WT_GUIDED_MISSILE) != 0:
			found_missile = true
	t.check(found_missile, "V-MOD-13: Pakistan owns a guided-missile slot")


func test_selector_errors(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var rep: DefLoadReport = DefLoadReport.new()
	var base: Dictionary = {"entity_kinds": ["unit"], "all_tags": ["combat"], "any_tags": [], "exclude_tags": [], "explicit_entity_ids": [], "conditions": [], "additional_superweapon_ids": [], "unresolved_target_domain": null}
	var bad_cond: Dictionary = base.duplicate(true)
	bad_cond["conditions"] = ["The unit is on fire."]
	DefResolver.compile_selector(d, bad_cond, "selector.t1", rep)
	t.check(rep.has_rule("V-MOD-04"), "unknown condition string -> V-MOD-04")
	var two: Dictionary = base.duplicate(true)
	two["conditions"] = [DefEnums.COND_TEXT_ON_WATER, DefEnums.COND_TEXT_GARRISON]
	rep = DefLoadReport.new()
	DefResolver.compile_selector(d, two, "selector.t2", rep)
	t.check(rep.has_rule("V-MOD-04"), "two conditions -> V-MOD-04")
	var dom: Dictionary = base.duplicate(true)
	dom["unresolved_target_domain"] = "Something new."
	rep = DefLoadReport.new()
	DefResolver.compile_selector(d, dom, "selector.t3", rep)
	t.check(rep.has_rule("V-MOD-05"), "unknown unresolved domain -> V-MOD-05")
	var tag: Dictionary = base.duplicate(true)
	tag["all_tags"] = ["combat", "no_such_tag"]
	rep = DefLoadReport.new()
	var dead: DefSelector = DefResolver.compile_selector(d, tag, "selector.t4", rep)
	t.check(rep.has_rule("V-MOD-02"), "unknown all_tags member in every namespace -> V-MOD-02")
	t.check(not DefResolver.matches_unit(dead, DefEnums.UT_COMBAT, 0, 1, 0), "and the selector never matches")
	var any_tag: Dictionary = base.duplicate(true)
	any_tag["any_tags"] = ["no_such_tag", "infantry"]
	rep = DefLoadReport.new()
	var live: DefSelector = DefResolver.compile_selector(d, any_tag, "selector.t5", rep)
	t.check(rep.is_ok() and rep.warnings.size() == 1, "unknown any_tags member is only a WARN")
	t.check(DefResolver.matches_unit(live, DefEnums.UT_COMBAT | DefEnums.UT_INFANTRY, 0, 1, 0), "and is ignored")
	var ids: Dictionary = base.duplicate(true)
	ids["explicit_entity_ids"] = ["unit.no.such"]
	rep = DefLoadReport.new()
	DefResolver.compile_selector(d, ids, "selector.t6", rep)
	t.check(rep.has_rule("V-REF-01"), "unknown explicit id")


func test_inline_shape_and_match_semantics(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var rep: DefLoadReport = DefLoadReport.new()
	var tank: int = d.unit_idx("unit.napc.guardian_tank")
	var narwhal: int = d.unit_idx("unit.napc.narwhal_amphibious_tank")
	var sel: DefSelector = DefResolver.compile_selector(d, {"unit_ids": ["unit.napc.guardian_tank"], "include_replacements": true}, "inline.t#0", rep)
	t.eq(sel.kind_mask, 1 << K.UNIT, "kinds inferred from unit_ids")
	var g: DefUnit = d.units[tank]
	var n: DefUnit = d.units[narwhal]
	t.check(DefResolver.unit_matches(d, sel, g), "explicit id matches")
	t.check(DefResolver.unit_matches(d, sel, n), "include_replacements closure reaches the Narwhal (replaces the Guardian)")
	var sel2: DefSelector = DefResolver.compile_selector(d, {"unit_ids": ["unit.napc.guardian_tank"]}, "inline.t#1", rep)
	t.check(DefResolver.unit_matches(d, sel2, g) and not DefResolver.unit_matches(d, sel2, n), "without the flag the replacement does not match")
	var both: DefSelector = DefResolver.compile_selector(d, {"unit_ids": ["unit.nec.fen_recon_carrier"], "structure_ids": ["structure.nec.relay"]}, "inline.t#2", rep)
	t.eq(both.kind_mask, (1 << K.UNIT) | (1 << K.STRUCTURE), "both kinds inferred")
	var relay: DefStructure = d.structures[d.structure_idx("structure.nec.relay")]
	t.check(DefResolver.matches_structure(both, relay.tags, relay.index, relay.weapon_tags), "relay matched")
	t.check(not DefResolver.matches_structure(both, relay.tags, d.structure_idx("structure.shared.radar"), 0), "other structures not")
	var classes: DefSelector = DefResolver.compile_selector(d, {"kinds": ["unit"], "tags_all": ["combat"], "classes": ["unique"]}, "inline.t#3", rep)
	t.check(DefResolver.matches_unit(classes, DefEnums.UT_COMBAT, 0, DefEnums.UnitClass.UNIQUE, 0) and not DefResolver.matches_unit(classes, DefEnums.UT_COMBAT, 0, DefEnums.UnitClass.BASELINE, 0), "class filter")
	var hw: DefSelector = DefResolver.compile_selector(d, {"kinds": ["unit", "structure"], "has_weapon_tags": ["thermal_beam"]}, "inline.t#4", rep)
	t.check(DefResolver.matches_unit(hw, 0, 0, 1, DefEnums.WT_THERMAL_BEAM) and not DefResolver.matches_unit(hw, 0, 0, 1, DefEnums.WT_DIRECT_FIRE), "has_weapon_tags clause")
	t.check(rep.is_ok(), "no reports: " + rep.text(3))
