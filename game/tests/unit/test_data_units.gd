extends RefCounted
## DATA-04: unit sheets, weapon instances, summons, ability instantiation, derived caches, structure numbers
## (data_balance 7.3 / 7.6 / 7.7 / 7.8 / 10.1 "unit sheets", "abilities registry", "global.json consumption").
## Stub balance (DefTestKit) with the spec's example unit numbers patched in, so the expectations are the printed ones.

const K := DefEnums.Kind
const AK := DefEnums.AbilityKind

static var _cache: GameData = null


static func _unit(sheet: Dictionary, id: String) -> Dictionary:
	for u: Dictionary in sheet["units"]:
		if u["id"] == id:
			return u
	return {}


static func _put_weapon(sheet: Dictionary, w: Dictionary) -> void:
	var list: Array = sheet["weapons"]
	for i: int in list.size():
		if (list[i] as Dictionary)["id"] == w["id"]:
			list[i] = w
			return
	list.append(w)


## Stub sources with the spec's worked-example units (Guardian, Beaver, Raptor, Sunlance) and Charlemagne patched in.
static func patched_sources() -> DefSources:
	var s: DefSources = DefTestKit.stub_sources()
	var napc: Dictionary = s.balance["units_napc.json"]
	var g: Dictionary = _unit(napc, "unit.napc.guardian_tank")
	g.merge({"cost_credits": 850, "build_time_s": 27.5, "health": 907, "speed_cells_s": 2.0, "vision_cells": 9.0, "radius_cells": 0.55,
		"weapons": ["weapon.napc.guardian_cannon"], "abilities": []}, true)
	_put_weapon(napc, {"id": "weapon.napc.guardian_cannon", "archetype": "tank_cannon", "damage": 141, "hits_per_volley": 1, "reload_s": 1.2, "range_cells": 7.0})
	var b: Dictionary = _unit(napc, "unit.napc.beaver_amphibious_apc")
	b.merge({"cost_credits": 485, "build_time_s": 15.5, "health": 602, "speed_cells_s": 3.2, "vision_cells": 12.0, "radius_cells": 0.45,
		"weapons": ["weapon.napc.beaver_mg"], "abilities": ["amphibious"], "movement_class": "amphibious"}, true)
	_put_weapon(napc, {"id": "weapon.napc.beaver_mg", "archetype": "machine_gun", "damage": 9, "hits_per_volley": 2, "reload_s": 1.0, "range_cells": 6.0})
	var r: Dictionary = _unit(napc, "unit.napc.raptor_multirole_fighter")
	r.merge({"rearm_s_full": 8, "weapons": ["weapon.napc.raptor_aam", "weapon.napc.raptor_agm"], "abilities": ["multirole"]}, true)
	_put_weapon(napc, {"id": "weapon.napc.raptor_aam", "archetype": "aa_missile", "damage": 86, "reload_s": 1.0, "range_cells": 8.0, "ammo_volleys": 6, "modes": [0]})
	_put_weapon(napc, {"id": "weapon.napc.raptor_agm", "archetype": "air_missile", "damage": 70, "reload_s": 1.5, "range_cells": 6.0, "ammo_volleys": 4, "modes": [1]})
	var olm: Dictionary = s.balance["units_olm.json"]
	var sl: Dictionary = _unit(olm, "unit.olm.sunlance_beam_tank")
	sl["weapons"] = ["weapon.olm.sunlance_beam"]
	_put_weapon(olm, {"id": "weapon.olm.sunlance_beam", "archetype": "beam_thermal", "damage": 50, "reload_s": 0.25, "range_cells": 9.0, "ramp_seconds": 5.0, "ramp_max_pct": 150})
	var nec: Dictionary = s.balance["units_nec.json"]
	var ch: Dictionary = _unit(nec, "unit.nec.charlemagne_siege_tank")
	ch["abilities"] = ["deployable_mode"]
	ch["ability_params"] = {"deployable_mode": {"deploy_s": 4, "range_bonus_pct": 25}}
	return s


static func data() -> GameData:
	if _cache == null:
		_cache = GameData.load_from_sources(patched_sources())
	return _cache


func _load_mutated(mutate: Callable) -> DefLoadReport:
	var s: DefSources = patched_sources()
	mutate.call(s)
	var d: GameData = GameData.load_from_sources(s)
	t_last_loaded = d
	return GameData.last_report


var t_last_loaded: GameData = null


func test_guardian(t: TestCtx) -> void:
	var d: GameData = data()
	if not t.not_null(d, "patched stub sources load: " + GameData.last_report.text(6)):
		return
	var u: DefUnit = d.units[d.unit_idx("unit.napc.guardian_tank")]
	t.eq(u.cost, 850, "cost")
	t.eq(u.build_ticks, 550, "build ticks (27.5 s)")
	t.eq(u.health, 907, "health")
	t.eq(u.speed, 102, "speed 2.0 c/s")
	t.eq(u.sight, 9216, "sight")
	t.eq(u.radius, 563, "radius 0.55")
	t.eq(u.turn_rate, 85, "medium hull turn")
	t.eq(u.accel_t, 6, "medium accel")
	t.eq(u.size_class, DefEnums.SizeClass.MEDIUM, "size class")
	t.eq(u.armor_class, DefEnums.ArmorClass.MEDIUM_ARMOR, "armor class")
	t.eq(u.move_class, DefEnums.MoveClass.TRACKED, "move class")
	t.eq(u.pop, 1, "pop")
	t.eq(u.unit_class, DefEnums.UnitClass.BASELINE, "class")
	var w: DefWeaponSlot = u.weapons[0]
	t.eq(w.arch, 3, "arch tank_cannon")
	t.eq(w.slot, 0, "slot")
	t.eq(w.mount, 1, "turret mount")
	t.eq(w.mode_mask, 0, "always active")
	t.eq(w.damage, 141, "damage")
	t.eq(w.hits_per_volley, 1, "hits")
	t.eq(w.dtype, 1, "dtype ap")
	t.eq(w.interceptable, 0, "interceptable")
	t.eq(w.proj_kind, 1, "shell")
	t.eq(w.range, 7168, "range")
	t.eq(w.min_range, 0, "min range")
	t.eq(w.reload_mt, 24000, "reload_mt")
	t.eq(w.reload_ticks, 24, "reload_ticks")
	t.eq(w.proj_speed, 819, "proj speed")
	t.check(w.homing, "homing")
	t.eq(w.splash_radius, 512, "splash")
	t.eq(w.splash_edge_bp, 5000, "splash edge")
	t.eq(w.scatter, 0, "scatter")
	t.eq(w.target_mask, 5, "targets ground|water")
	t.eq(w.flags, 16, "WF_HOMING only")
	t.eq(w.turret_turn, 51, "turret turn")
	t.eq(w.fire_arc, 4096, "360 deg")
	t.eq(w.ramp_t, 0, "no ramp")
	t.eq(w.ramp_max_bp, 10000, "ramp default")
	t.eq(w.ui_label, "weapon.napc.guardian_cannon", "instance label")
	# derived caches
	t.eq(u.max_range, 7168, "max_range")
	t.eq(u.attack_layer_mask, 5, "attack_layer_mask")
	t.eq(u.weapon_tags, DefEnums.WT_DIRECT_FIRE | DefEnums.WT_ANTI_GROUND, "weapon_tags")
	t.eq(u.speed_water, 0, "tracked cannot enter deep water")


func test_beaver_and_abilities(t: TestCtx) -> void:
	var d: GameData = data()
	if d == null:
		t.fail("no data")
		return
	var u: DefUnit = d.units[d.unit_idx("unit.napc.beaver_amphibious_apc")]
	t.eq(u.cost, 485, "cost")
	t.eq(u.build_ticks, 310, "build 15.5 s")
	t.eq(u.speed, 164, "speed 3.2 c/s")
	t.eq(u.move_class, DefEnums.MoveClass.AMPHIBIOUS, "amphibious")
	t.eq(u.size_class, 1, "light")
	t.eq(u.armor_class, 1, "light vehicle")
	t.eq(u.abilities.size(), 2, "DETECTOR + TRANSPORT (implicit), amphibious makes none")
	t.eq(u.abilities[0].kind, AK.DETECTOR, "tag:detector first")
	t.eq(u.abilities[0].params["radius_u"], 5120, "default radius 5 cells")
	t.eq(u.abilities[1].kind, AK.TRANSPORT, "archetype veh_scout transport")
	t.eq(u.abilities[1].params["capacity_squads_n"], 2, "two squads")
	t.eq(u.ability_slot_of_kind[AK.TRANSPORT], 1, "slot of kind")
	t.eq(u.transport_squads, 2, "derived transport_squads")
	t.eq(u.detect_radius, 5120, "derived detect_radius")
	t.eq(u.speed_water, 115, "amphibious deep table value 70 % of 164, one rounding")
	t.check(u.has_ability(AK.DETECTOR) and not u.has_ability(AK.DEPLOY), "ability_mask")


func test_raptor_and_beam(t: TestCtx) -> void:
	var d: GameData = data()
	if d == null:
		t.fail("no data")
		return
	var r: DefUnit = d.units[d.unit_idx("unit.napc.raptor_multirole_fighter")]
	t.eq(r.rearm_t, 160, "rearm 8 s")
	t.eq(r.weapons[0].mode_mask, 1, "mode 0 -> bit 0")
	t.eq(r.weapons[1].mode_mask, 2, "mode 1 -> bit 1")
	t.eq(r.weapons[0].ammo_volleys, 6, "ammo")
	t.eq(r.weapons[1].slot, 1, "slot number = list position")
	t.eq(r.weapons[0].mount, 0, "aircraft weapons are hull mounted")
	t.check(r.has_ability(AK.MODE_SWITCH) and r.has_ability(AK.SORTIE), "multirole + implicit sortie")
	t.eq(r.attack_layer_mask, DefEnums.L_AIR | DefEnums.L_GROUND | DefEnums.L_WATER, "aa + air_missile targets")
	var sl: DefUnit = d.units[d.unit_idx("unit.olm.sunlance_beam_tank")]
	var b: DefWeaponSlot = sl.weapons[0]
	t.eq(b.reload_mt, 5000, "0.25 s")
	t.eq(b.reload_ticks, 5, "ticks")
	t.eq(b.ramp_t, 100, "ramp 5 s")
	t.eq(b.ramp_max_bp, 15000, "ramp 150 %")
	t.eq(b.proj_speed, 0, "beam is hitscan")
	t.eq(b.dtype, DefEnums.DamageType.THERMAL, "thermal")
	t.check((sl.weapon_tags & DefEnums.WT_THERMAL_BEAM) != 0, "thermal_beam weapon tag")


func test_charlemagne_defaults_materialised(t: TestCtx) -> void:
	var d: GameData = data()
	if d == null:
		t.fail("no data")
		return
	var u: DefUnit = d.units[d.unit_idx("unit.nec.charlemagne_siege_tank")]
	var a: DefAbility = u.ability_of(AK.DEPLOY)
	t.not_null(a, "deploy ability")
	if a == null:
		return
	var want: Dictionary = {
		"command_radius_bonus_u": 0, "damage_bonus_bp": 0, "deploy_t": 80, "deployed_slots_n": [], "immobile": true,
		"pack_t": 40, "range_bonus_bp": 2500, "turn_locked": false,
	}
	t.eq(a.params.size(), want.size(), "every default materialised, nothing else")
	for k: Variant in want.keys():
		t.check(a.params.has(k) and a.params[k] == want[k], "param %s" % str(k))
	t.eq(a.params.keys(), want.keys(), "keys are sorted")
	t.eq(a.template, d.ids.index_of(K.ABILITY, "ability.deploy.default"), "template index")
	t.eq(a.slot, 0, "slot")


func test_ability_rules(t: TestCtx) -> void:
	# an explicit transport_3 replaces the implicit two-squad transport in place
	var rep: DefLoadReport = _load_mutated(func(s: DefSources) -> void:
		_unit(s.balance["units_napc.json"], "unit.napc.beaver_amphibious_apc")["abilities"] = ["transport_3"])
	t.check(rep.is_ok(), "loads: " + rep.text(4))
	var d: GameData = t_last_loaded
	if d != null:
		var u: DefUnit = d.units[d.unit_idx("unit.napc.beaver_amphibious_apc")]
		t.eq(u.abilities.size(), 2, "still two abilities")
		t.eq(u.ability_slot_of_kind[AK.TRANSPORT], 1, "TRANSPORT slot unchanged")
		t.eq(u.ability_of(AK.TRANSPORT).params["capacity_squads_n"], 3, "three squads")
	# two entries of one kind: the later wins
	_load_mutated(func(s: DefSources) -> void:
		_unit(s.balance["units_napc.json"], "unit.napc.beaver_amphibious_apc")["abilities"] = ["transport_3", "ability.transport.squads4"])
	if t_last_loaded != null:
		t.eq(t_last_loaded.units[t_last_loaded.unit_idx("unit.napc.beaver_amphibious_apc")].ability_of(AK.TRANSPORT).params["capacity_squads_n"], 4, "later entry wins")
	# unknown param, unknown ability
	rep = _load_mutated(func(s: DefSources) -> void:
		var u: Dictionary = _unit(s.balance["units_nec.json"], "unit.nec.charlemagne_siege_tank")
		u["ability_params"] = {"deployable_mode": {"deploy_s": 4, "no_such_param": 1}})
	t.check(rep.has_rule("V-ABL-01"), "unknown param -> V-ABL-01")
	rep = _load_mutated(func(s: DefSources) -> void:
		_unit(s.balance["units_napc.json"], "unit.napc.guardian_tank")["abilities"] = ["no_such_ability"])
	t.check(rep.has_rule("V-ABL-01"), "unknown ability entry -> V-ABL-01")


func test_registry_types_win_over_suffix(t: TestCtx) -> void:
	# rate_pct_per_s is registry type pcts (percent per second -> bp per second), not a duration
	var d: GameData = data()
	if d == null:
		t.fail("no data")
		return
	var a: DefAbility = DefLoaderBalance.instantiate_template(DefAbilityKinds.from_json(DefTestKit.read_json("res://data/balance/ability_kinds.json"), DefLoadReport.new()), "ability.heal.default", {}, "test", d, DefLoadReport.new())
	t.eq(a.params["rate_bps"], 200, "2 %/s = 200 bp/s")
	t.eq(a.params["radius_u"], 4096, "4 cells")
	t.eq(DefLoaderBalance.runtime_key("s", "cooldown_s"), "cooldown_t", "seconds key")
	t.eq(DefLoaderBalance.runtime_key("pcts", "rate_pct_per_s"), "rate_bps", "pcts key")
	t.eq(DefLoaderBalance.runtime_key("cells", "radius_cells"), "radius_u", "cells key")
	t.eq(DefLoaderBalance.convert_number("s", 1.05, "t", DefLoadReport.new()), 21, "1.05 s = 21 ticks")


func test_weapon_rules(t: TestCtx) -> void:
	var rep: DefLoadReport = _load_mutated(func(s: DefSources) -> void:
		_put_weapon(s.balance["units_napc.json"], {"id": "weapon.napc.guardian_cannon", "archetype": "tank_cannon", "damage_type": "he", "damage": 141, "reload_s": 1.2, "range_cells": 7.0}))
	t.check(rep.has_rule("V-CNF-08"), "a weapon instance may not set a locked attribute")
	rep = _load_mutated(func(s: DefSources) -> void:
		var napc: Dictionary = s.balance["units_napc.json"]
		napc["units"] = (napc["units"] as Array).filter(func(u: Dictionary) -> bool: return u["id"] != "unit.napc.guardian_tank"))
	t.check(rep.has_rule("V-CMP-01"), "a bible unit without a sheet entry -> V-CMP-01")
	rep = _load_mutated(func(s: DefSources) -> void:
		_put_weapon(s.balance["units_napc.json"], {"id": "weapon.napc.guardian_cannon", "archetype": "no_such_arch", "damage": 141, "reload_s": 1.2, "range_cells": 7.0}))
	t.check(rep.has_rule("V-REF-01"), "unknown weapon archetype")


func test_merge_policy_for_units(t: TestCtx) -> void:
	# bible cost of the service units is authoritative: a different sheet value is V-CNF-01
	var rep: DefLoadReport = _load_mutated(func(s: DefSources) -> void:
		_unit(s.balance["units_shared.json"], "unit.shared.collector")["cost_credits"] = 1300)
	t.check(rep.has_rule("V-CNF-01"), "sheet contradicts the bible")
	rep = _load_mutated(func(s: DefSources) -> void:
		_unit(s.balance["units_shared.json"], "unit.shared.collector")["cost_credits"] = 1400)
	t.check(rep.is_ok() and rep.has_rule("V-CNF-02"), "an equal repeat is only an INFO")
	rep = _load_mutated(func(s: DefSources) -> void:
		var u: Dictionary = _unit(s.balance["units_napc.json"], "unit.napc.guardian_tank")
		u.erase("cost_credits")
		u["archetype"] = "no_such_role")
	t.check(rep.has_rule("V-REF-01"), "unknown archetype")


func test_summons_and_service_units(t: TestCtx) -> void:
	var d: GameData = DefTestKit.stub_game_data(true)
	if not t.not_null(d, "real sheets load: " + GameData.last_report.text(6)):
		return
	var uav: DefUnit = d.units[d.unit_idx("summon.napc.uav")]
	t.eq(uav.unit_class, DefEnums.UnitClass.SUMMON, "summon class")
	t.eq(uav.cost, -1, "summons are not purchasable")
	t.eq(uav.pop, 0, "no unit cap")
	t.check((uav.flags & DefEnums.UF_NO_COMBAT_MODS) != 0, "no combat modifiers")
	t.check((uav.tags & DefEnums.UT_COMBAT) == 0, "summons never carry combat")
	t.eq(uav.faction, d.faction_idx("faction.napc"), "faction from the id")
	t.check(uav.lifetime_t > 0, "lifetime")
	var col: DefUnit = d.units[d.unit_idx("unit.shared.collector")]
	t.eq(col.cost, 1400, "bible cost")
	t.eq(col.pop, 0, "collector is cap exempt")
	t.check(col.has_ability(AK.HARVEST), "harvest (implicit service.collector)")
	var mcv: DefUnit = d.units[d.unit_idx("unit.shared.mobile_construction_vehicle")]
	t.check(mcv.has_ability(AK.DEPLOY_STRUCTURE), "MCV deploys")
	t.eq(mcv.ability_of(AK.DEPLOY_STRUCTURE).params["structure_idx"], d.structure_idx("structure.shared.headquarters"), "deploy target")
	t.check(d.units[d.unit_idx("unit.shared.engineer")].has_ability(AK.CAPTURE), "engineer captures")
	var condor: DefUnit = d.units[d.unit_idx("unit.napc.condor_stealth_bomber")]
	t.eq(condor.cloak_delay_t, 120, "derived cloak_delay_t (6 s)")
	t.check(condor.ability_of(AK.CAMOUFLAGE).params["moving_ok"], "stealth alias = the moving camouflage template")
	# drones: replacement cost / time from the sheet
	var drones: int = 0
	for u: DefUnit in d.units:
		if u.unit_class == DefEnums.UnitClass.DRONE:
			drones += 1
			t.check(u.cost > 0 and u.build_ticks > 0, "drone %s carries the replacement cost / time" % u.id)
	t.check(drones >= 1, "at least one carrier drone")


func test_structures(t: TestCtx) -> void:
	var d: GameData = data()
	if d == null:
		t.fail("no data")
		return
	var g: DefStructure = d.structures[d.structure_idx("structure.shared.generator")]
	t.eq(g.cost, 600, "cost")
	t.eq(g.build_ticks, 500, "25 s")
	t.eq(g.health, 1200, "health")
	t.eq(g.armor_class, 8, "building_light")
	t.eq(g.fp_w, 2, "fp w")
	t.eq(g.fp_h, 2, "fp h")
	t.eq(g.radius, 1024, "radius")
	t.eq(g.sight, 6144, "sight")
	t.eq(g.power, 150, "power")
	var relay: DefStructure = d.structures[d.structure_idx("structure.nec.relay")]
	t.eq(relay.cost, 600, "relay cost")
	t.eq(relay.build_ticks, 300, "relay 15 s")
	t.eq(relay.power, -20, "relay power")
	t.eq(relay.health, 900, "relay hp")
	t.eq(relay.sight, 8192, "relay sight")
	t.eq(relay.fp_w * 10 + relay.fp_h, 11, "1x1")
	t.check((relay.flags & DefEnums.SF_RELAY) != 0 and (relay.flags & DefEnums.SF_REPAIRABLE) != 0 and (relay.flags & DefEnums.SF_SELLABLE) != 0, "relay flags")
	t.check((relay.flags & DefEnums.SF_PRODUCTION) == 0, "no unit names the relay as producer")
	t.eq(relay.place_mask, DefEnums.PLACE_NO_RADIUS_EXTENSION, "placement")
	var rf: DefAbility = relay.ability_of(AK.RELAY_FIELD)
	t.not_null(rf, "relay_field")
	if rf != null:
		t.eq(rf.params["radius_u"], 6144, "6 cells")
		t.eq(rf.params["damage_bonus_bp"], 1000, "+10 %")
		t.eq(rf.params["powered_required"], true, "default")
		t.eq(rf.params["retain_after_power_loss_t"], 0, "default")
		t.eq(rf.params["radius_upgradeable"], true, "default")
		t.eq(d.stack_groups[rf.stack_group], "relay_field", "stack group registry")
	var wt: DefStructure = d.structures[d.structure_idx("structure.shared.watchtower")]
	t.eq(wt.detect_radius, 4096, "watchtower detector 4 cells")
	t.eq(wt.weapons.size(), 1, "watchtower gun")
	t.check((wt.tags & d.tags.structure_bit("anti_ground")) != 0 and (wt.tags & d.tags.structure_bit("anti_sub")) == 0, "derived free structure tags")
	var aa: DefStructure = d.structures[d.structure_idx("structure.shared.aa_battery")]
	t.check((aa.tags & d.tags.structure_bit("anti_air")) != 0, "aa battery is anti_air")
	t.eq(aa.detect_radius, 5120, "aa detector 5 cells")
	var af: DefStructure = d.structures[d.structure_idx("structure.shared.airfield")]
	t.eq(af.pads, 4, "airfield pads")
	t.not_null(af.ability_of(AK.SERVICE_PADS), "service pads ability")
	t.eq(af.fp_w * 10 + af.fp_h, 63, "6x3")
	t.eq(af.fp_mask.size(), 18, "footprint mask")
	t.eq(af.exit_dy, 3, "exit")
	var hq: DefStructure = d.structures[d.structure_idx("structure.shared.headquarters")]
	t.check((hq.flags & DefEnums.SF_NO_BUILD) != 0, "hq is not buildable")
	t.eq(hq.deploy_t, 60, "3 s deploy")
	t.eq(hq.build_ticks, 0, "no build time")
	t.eq(d.structures[d.structure_idx("structure.shared.refinery")].ability_of(AK.REFINERY).params["free_collector_idx"], d.unit_idx("unit.shared.collector"), "free collector")
	var adv: DefStructure = d.structures[d.structure_idx("structure.olm.sunwall_projector")]
	t.eq(adv.health, 3300, "advanced defense uses the faction health")
	t.eq(adv.weapons[0].ramp_t, 100, "sunwall beam ramps 5 s")
	t.check((adv.weapon_tags & DefEnums.WT_THERMAL_BEAM) != 0, "thermal beam structure")
	t.eq(adv.weapons[0].mount, 1, "turret")


func test_structure_merge_policy(t: TestCtx) -> void:
	var rep: DefLoadReport = _load_mutated(func(s: DefSources) -> void:
		((s.balance["global.json"] as Dictionary)["structures"] as Dictionary)["generator"]["power_delta"] = 140)
	t.check(rep.has_rule("V-CNF-01"), "global.json power_delta must equal the bible")
	rep = _load_mutated(func(s: DefSources) -> void:
		(s.balance["structures.json"] as Dictionary)["structures"].append({"id": "structure.shared.no_such"}))
	t.check(rep.has_rule("V-REF-01"), "overlay entry of an unknown structure")


func test_malformed_files_are_reported_not_crashed(t: TestCtx) -> void:
	var cases: Array = [
		["units_napc.json", func(b: Dictionary) -> void: b["units"] = 5],
		["units_napc.json", func(b: Dictionary) -> void: (b["units"] as Array)[0] = "x"],
		["units_napc.json", func(b: Dictionary) -> void: (b["units"] as Array)[0]["abilities"] = "detector"],
		["units_napc.json", func(b: Dictionary) -> void: (b["units"] as Array)[0]["ability_params"] = []],
		["units_napc.json", func(b: Dictionary) -> void: b["weapons"] = [1, 2]],
		["units_napc.json", func(b: Dictionary) -> void: b["summons"] = {}],
		["structures.json", func(b: Dictionary) -> void: b["structures"] = {}],
		["research_effects.json", func(b: Dictionary) -> void: (b["research"] as Dictionary)["research.ae.circular_armor"]["effects"] = "no"],
		["research_effects.json", func(b: Dictionary) -> void: (b["research"] as Dictionary)["research.ae.circular_armor"]["effects"] = [3]],
		["research_effects.json", func(b: Dictionary) -> void: (b["research"] as Dictionary)["research.ae.circular_armor"]["effects"][0]["selector"] = 5],
		["research_effects.json", func(b: Dictionary) -> void: b["research"] = []],
		["power_actions.json", func(b: Dictionary) -> void: (b["powers"] as Dictionary)["power.napc.uav_sweep"] = []],
		["power_actions.json", func(b: Dictionary) -> void: (b["powers"] as Dictionary)["power.napc.uav_sweep"]["actions"] = {}],
		["zone_templates.json", func(b: Dictionary) -> void: b["zones"] = []],
		["faction_traits.json", func(b: Dictionary) -> void: (b["factions"] as Dictionary)["faction.ae"]["traits"] = 3],
		["neutral_structures.json", func(b: Dictionary) -> void: (b["neutrals"] as Dictionary)["neutral.substation"] = 3],
		["ability_kinds.json", func(b: Dictionary) -> void: b["kinds"] = []],
	]
	for i: int in cases.size():
		var s: DefSources = patched_sources()
		var c: Array = cases[i]
		(c[1] as Callable).call(s.balance[c[0]])
		var d: GameData = GameData.load_from_sources(s)
		t.check(d == null, "case %d (%s) refuses to load" % [i, c[0]])
		t.check(not GameData.last_report.errors.is_empty(), "case %d reports an error: %s" % [i, GameData.last_report.text(2)])
	# a missing file is reported by the manifest check
	var s2: DefSources = patched_sources()
	s2.balance.erase("units_pd.json")
	s2.manifest_files.remove_at(s2.manifest_files.find("units_pd.json"))
	t.check(GameData.load_from_sources(s2) == null and GameData.last_report.has_rule("V-SCH-01"), "missing sheet -> V-SCH-01")
