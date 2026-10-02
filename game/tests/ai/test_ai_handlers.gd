extends RefCounted
## AIX1 special-unit handlers (ai.md 5.9.3 - 5.9.5): handler bits derived from the abilities of the resolved defs, and the
## documented rules on real matches (mode switch with a minimum dwell, air loadout by the enemy air share, deployables pack when
## enemies close in without escorts, healers and provider follow-ups, mast deployment).


func _res_of(roster_id: String) -> AiRoleResolver:
	var gd: GameData = SimMatchKit.data()
	return AiRoleResolver.resolve(gd, gd.rosters[gd.roster_idx(roster_id)], AiDataStore.load_default())


func _has(res: AiRoleResolver, unit_id: String, hname: String) -> bool:
	var d: int = SimMatchKit.data().unit_idx(unit_id)
	return (res.handlers_of(d) & (1 << AiTypes.handler_bit(hname))) != 0


func test_handler_bits_come_from_the_abilities(t: TestCtx) -> void:
	var napc: AiRoleResolver = _res_of("roster.napc.usa")
	t.check(_has(napc, "unit.napc.paladin_howitzer", "DEPLOY_SIEGE"), "Paladin deploys")
	t.check(_has(napc, "unit.napc.raptor_multirole_fighter", "LOADOUT"), "Raptor loadout")
	t.check(_has(napc, "unit.napc.combat_medic", "HEALER_FOLLOW"), "Medic follows")
	t.check(_has(napc, "unit.napc.condor_stealth_bomber", "CAMO_HOLD"), "Condor camouflage")
	t.check(_has(_res_of("roster.pd.japan"), "unit.pd.shinano_adaptive_tank", "MODE_SWITCH"), "Shinano")
	t.check(_has(_res_of("roster.pd.japan"), "unit.pd.shogun_drone_carrier", "WING_SWITCH"), "Shogun wing")
	t.check(_has(_res_of("roster.pd.vanilla"), "unit.pd.reef_technician", "REPAIR_FOLLOW"), "Reef Technician")
	t.check(_has(_res_of("roster.ae.south_africa"), "unit.ae.protea_gun_carrier", "MODE_SWITCH"), "Protea")
	t.check(_has(_res_of("roster.nec.nordics"), "unit.nec.fen_recon_carrier", "MAST_DEPLOY"), "Fen mast")
	t.check(_has(_res_of("roster.nec.eurocorps"), "unit.nec.charlemagne_siege_tank", "DEPLOY_SIEGE"), "Charlemagne")
	t.check(_has(_res_of("roster.han.vanilla"), "unit.han.link_operator", "ESCORT_PROVIDER"), "Link Operator")
	t.check(_has(_res_of("roster.def.north_korea"), "unit.def.echo_team", "DECOY_PLACE"), "Echo Team decoys")
	t.check(_has(_res_of("roster.def.north_korea"), "unit.def.fortress_guard", "COVER_DEPLOY"), "Fortress Guard deploys")
	t.check(_has(_res_of("roster.olm.el_andalus"), "unit.olm.gate_guard", "GARRISON_PREF"), "Gate Guard garrisons")
	t.check(_has(_res_of("roster.han.vietnam"), "unit.han.canopy_ranger", "CAMO_HOLD"), "Canopy Ranger")
	t.check(_has(_res_of("roster.sap.pakistan"), "unit.sap.shaheen_missile_battery", "DEPLOY_SIEGE"), "Shaheen")
	t.check(_has(_res_of("roster.nec.alpine_brotherhood"), "unit.nec.alpine_pioneer", "COVER_DEPLOY"), "Alpine Pioneer cover")


func _hu(b: AiBrain) -> AiUnitHandlers:
	return b.handlers


func test_protea_switches_with_a_minimum_dwell(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray(["roster.ae.south_africa", AiXKit.R_NEC]), [1, 0], 200)
	var b: AiBrain = AiXKit.brain(m, 0)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var pos: PackedInt32Array = AiXKit.toward(h, AiXKit.home(m, 1), 12)
	var pr: int = AiXKit.spawn(m, "unit.ae.protea_gun_carrier", 0, pos[0], pos[1], 1500)
	var w: SimWorld = AiXKit.world(m)
	# enemies at 5 cells: canister (mode 1)
	var foe: int = AiXKit.spawn(m, "unit.nec.jager_squad", 1, pos[0] + 5 * AiXKit.CELL, pos[1], 200)
	AiSoakKit.play(m, 120)
	t.gt(b.stat("h_mode_switch"), 0, "an enemy inside 8 cells switches the Protea to canister")
	t.eq(w.get_entity(pr).combat.ext_mode, 1, "canister mode")
	# no oscillation inside the dwell time: the enemy goes, the mode holds for 120 ticks
	w.remove_entity(foe, SimEvent.REM_KILLED)
	var n0: int = b.stat("h_mode_switch")
	AiSoakKit.play(m, 60)
	t.eq(b.stat("h_mode_switch"), n0, "no switch back inside the minimum dwell")
	t.eq((m["errors"] as PackedStringArray).size(), 0)


func test_mode_decision_has_hysteresis(t: TestCtx) -> void:
	var cell: int = AiXKit.CELL
	t.eq(AiUnitHandlers.mode_decision(0, 0, 1, 5 * cell, false), 1, "siege mode + enemy within 8 cells: close mode")
	t.eq(AiUnitHandlers.mode_decision(0, 0, 1, 10 * cell, true), 0, "between 8 and 12 cells the mode is kept")
	t.eq(AiUnitHandlers.mode_decision(1, 0, 1, 10 * cell, false), 1, "close mode is kept while the enemy is within 12 cells")
	t.eq(AiUnitHandlers.mode_decision(1, 0, 1, 13 * cell, true), 0, "nobody within 12 cells and a target in range: siege mode")
	t.eq(AiUnitHandlers.mode_decision(1, 0, 1, 13 * cell, false), 1, "no target: stays in the close mode")


func test_raptor_loadout_follows_the_enemy_air_share(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray(["roster.napc.usa", AiXKit.R_NEC]), [1, 0], 300)
	var w: SimWorld = AiXKit.world(m)
	var b: AiBrain = AiXKit.brain(m, 0)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var af_def: int = w.data.structure_idx("structure.shared.airfield")
	var af: SimEntity = w.spawn_structure(af_def, 0, h[0] + 8 * AiXKit.CELL, h[1] + 8 * AiXKit.CELL, 0, SimFlags.F_POWERED, 1000)
	t.not_null(af)
	var rp: SimEntity = w.spawn_unit(w.data.unit_idx("unit.napc.raptor_multirole_fighter"), 0, af.x, af.y, 0, 0, 1400)
	SimAirSortie.on_aircraft_spawned(w, rp, af.id)
	AiSoakKit.play(m, 200)
	t.eq(AiXKit.ctx(m, 0).view.e_air_state(rp.id), AiTypes.AIR_PARKED, "the Raptor is parked on its pad")
	t.gt(b.stat("h_loadout"), 0, "no enemy air seen: the ground loadout is fitted")
	var ground: int = rp.combat.ext_mode
	t.eq(ground, 1, "ground loadout")
	# an enemy fighter appears
	AiXKit.spawn(m, "unit.nec.kestrel_interceptor", 1, h[0] + 20 * AiXKit.CELL, h[1], 1200)
	AiSoakKit.play(m, 260)
	t.eq(rp.combat.ext_mode, 0, "enemy aircraft in sight: the air loadout")
	t.eq((m["errors"] as PackedStringArray).size(), 0)


func test_charlemagne_packs_when_enemies_close_in_without_escort(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray(["roster.nec.eurocorps", AiXKit.R_NAPC]), [1, 0], 200)
	var w: SimWorld = AiXKit.world(m)
	var b: AiBrain = AiXKit.brain(m, 0)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var pos: PackedInt32Array = AiXKit.toward(h, AiXKit.home(m, 1), 20)
	var ch: int = AiXKit.spawn(m, "unit.nec.charlemagne_siege_tank", 0, pos[0], pos[1], 2200)
	w.submit_raw(0, SimCmd.deploy(PackedInt32Array([ch])))
	AiSoakKit.play(m, 120)
	var e: SimEntity = w.get_entity(ch)
	t.check((e.flags & SimFlags.F_DEPLOYED) != 0, "the Charlemagne is deployed")
	# a rifle squad walks up to 4 cells and no escort is near
	AiXKit.spawn(m, "unit.napc.rifle_squad", 1, pos[0] + 4 * AiXKit.CELL, pos[1], 200)
	AiSoakKit.play(m, 160)
	t.gt(b.stat("h_deploy_siege"), 0, "the deployed piece was ordered to pack")
	t.eq((m["errors"] as PackedStringArray).size(), 0)


func test_medic_guards_its_infantry_squad(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [1, 0], 200)
	var b: AiBrain = AiXKit.brain(m, 0)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var pos: PackedInt32Array = AiXKit.toward(h, AiXKit.home(m, 1), 14)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 4:
		ids.append(AiXKit.spawn(m, "unit.napc.rifle_squad", 0, pos[0] + i * 700, pos[1], 200))
	var medic: int = AiXKit.spawn(m, "unit.napc.combat_medic", 0, pos[0] - 9 * AiXKit.CELL, pos[1], 485)
	ids.append(medic)
	AiXKit.defend_op(m, 0, ids, pos[0], pos[1])
	AiSoakKit.play(m, 200)
	t.gt(b.stat("h_healer_follow"), 0, "the medic got a guard order on an infantry unit")
	t.eq(AiXKit.order_of(m, 0, medic), AiTypes.OrderKind.GUARD, "the medic guards")


func test_command_field_provider_moves_to_the_unmanned_units(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray(["roster.han.vanilla", AiXKit.R_NEC]), [1, 0], 200)
	var b: AiBrain = AiXKit.brain(m, 0)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var pos: PackedInt32Array = AiXKit.toward(h, AiXKit.home(m, 1), 18)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 4:
		ids.append(AiXKit.spawn(m, "unit.han.nest_rocket_drone", 0, pos[0] + i * 800, pos[1], 700))
	var prov: int = AiXKit.spawn(m, "unit.han.link_operator", 0, pos[0] - 10 * AiXKit.CELL, pos[1], 400)
	ids.append(prov)
	AiXKit.defend_op(m, 0, ids, pos[0], pos[1])
	AiSoakKit.play(m, 120)
	t.gt(b.stat("h_escort_provider"), 0, "coverage < 60 %: the provider moves to the field centroid")
	var w: SimWorld = AiXKit.world(m)
	var e: SimEntity = w.get_entity(prov)
	t.lt(absi(e.x - (pos[0] + 1200)), 10 * AiXKit.CELL, "the provider came closer to its drones")


func test_fen_deploys_its_mast_at_the_staging_point(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray(["roster.nec.nordics", AiXKit.R_NAPC]), [1, 0], 200)
	var b: AiBrain = AiXKit.brain(m, 0)
	var pr: AiProduction = b.eco().production
	var fen: int = AiXKit.spawn(m, "unit.nec.fen_recon_carrier", 0, pr.stage_x, pr.stage_y, 700)
	AiSoakKit.play(m, 200)
	t.gt(b.stat("h_mast_deploy"), 0, "the mast was deployed")
	var w: SimWorld = AiXKit.world(m)
	t.check((w.get_entity(fen).flags & (SimFlags.F_DEPLOYED | SimFlags.F_DEPLOYING)) != 0, "the Fen is deploying / deployed")
	# an armed enemy at 8 cells packs it again
	AiXKit.spawn(m, "unit.napc.rifle_squad", 1, pr.stage_x + 8 * AiXKit.CELL, pr.stage_y, 200)
	AiSoakKit.play(m, 240)
	t.gt(b.stat("h_mast_deploy"), 1, "enemy within 12 cells: pack")
	t.eq((m["errors"] as PackedStringArray).size(), 0)
