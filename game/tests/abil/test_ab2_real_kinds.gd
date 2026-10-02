extends RefCounted
## One behaviour test per ability kind executed by AB2, driven over EVERY real unit / structure def that carries the kind:
## the numbers come from the balance sheets (params of the defs), not from the test.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")


func _units_with(d: GameData, kind: int) -> Array[DefUnit]:
	var out: Array[DefUnit] = []
	for u: DefUnit in d.units:
		if u.has_ability(kind) and not u.id.begins_with("summon."):
			out.append(u)
	return out


func _spawn_anywhere(w: SimWorld, u: DefUnit, owner: int, cx: int, cy: int) -> SimEntity:
	return A.spawn(w, u.id, owner, cx, cy)


func test_every_deploy_unit(t: TestCtx) -> void:
	var d: GameData = A.data()
	var units: Array[DefUnit] = _units_with(d, DefEnums.AbilityKind.DEPLOY)
	t.ge(units.size(), 14, "the sheets carry at least 14 deploy units (%d)" % units.size())
	for u: DefUnit in units:
		var w: SimWorld = A.world({"movement": false})
		var e: SimEntity = _spawn_anywhere(w, u, 0, 20, 20)
		var da: DefAbility = u.ability_of(DefEnums.AbilityKind.DEPLOY)
		var dt: int = int(da.params.get("deploy_t", 0))
		var pt: int = int(da.params.get("pack_t", 0))
		var s: int = e.abil.slot_of_kind(K.AK_DEPLOY)
		w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [s], PackedInt32Array([e.id])))
		A.run_to(w, dt)
		t.eq(e.combat.ext_deployed, 0 if dt > 0 else 1, "%s: not deployed before deploy_t=%d" % [u.id, dt])
		w.step()
		t.eq(e.combat.ext_deployed, 1, "%s: deployed at tick %d" % [u.id, dt])
		t.eq(A.lease_bp(w, e, C.STAT_RANGE), int(da.params.get("range_bonus_bp", 0)), "%s: range lease = sheet" % u.id)
		t.eq(A.lease_bp(w, e, C.STAT_DMG_OUT), int(da.params.get("damage_bonus_bp", 0)), "%s: damage lease = sheet" % u.id)
		t.eq(w.abilities.is_turn_locked(e), bool(da.params.get("turn_locked", false)), "%s: turn lock = sheet" % u.id)
		t.eq(w.abilities.is_immobile(e), bool(da.params.get("immobile", true)), "%s: immobile = sheet" % u.id)
		var t1: int = w.tick
		w.submit_raw(0, SimCmd.build(SimCmd.UNDEPLOY, [s], PackedInt32Array([e.id])))
		w.step()
		t.eq(e.combat.ext_deployed, 0, "%s: pack starts at once" % u.id)
		A.run_to(w, t1 + pt)
		t.eq(w.abilities.is_immobile(e), pt > 0 and false or (pt > 0), "%s: packing for pack_t=%d" % [u.id, pt])
		A.run(w, 1)
		t.check(not w.abilities.is_immobile(e), "%s: mobile after the pack" % u.id)
		t.eq(w.abilities.debug_validate(w).size(), 0, "%s: validate" % u.id)


func test_every_mode_switch_unit(t: TestCtx) -> void:
	var d: GameData = A.data()
	var units: Array[DefUnit] = _units_with(d, DefEnums.AbilityKind.MODE_SWITCH)
	t.ge(units.size(), 3, "mode_switch units exist (%d)" % units.size())
	for u: DefUnit in units:
		var w: SimWorld = A.world({"movement": false})
		var e: SimEntity = _spawn_anywhere(w, u, 0, 20, 20)
		var da: DefAbility = u.ability_of(DefEnums.AbilityKind.MODE_SWITCH)
		var st: int = int(da.params.get("switch_t", 0))
		var pad: int = int(da.params.get("switch_at_structure_idx", -1))
		var modes: Array = da.params.get("modes", []) as Array
		t.eq(e.combat.ext_mode, 0, "%s: starts in mode 0" % u.id)
		var s: int = e.abil.slot_of_kind(K.AK_MODE_SWITCH)
		var c: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.SET_MODE, [s, 1], PackedInt32Array([e.id])))
		c.actors = [e]
		var err: int = SimAbilityCmds.execute(w, c)
		if pad >= 0:
			t.eq(err, SimCommand.Err.NOT_ALLOWED, "%s: the loadout switch needs the airfield pad" % u.id)
			continue
		t.eq(err, SimCommand.Err.OK, "%s: switch accepted" % u.id)
		w.step()
		t.eq(e.combat.ext_mode, -1 if st > 0 else 1, "%s: no weapon set while switching" % u.id)
		A.run_to(w, st + 1)
		t.eq(e.combat.ext_mode, 1, "%s: mode 1 after switch_t=%d" % [u.id, st])
		t.eq(modes.size(), 2, "%s: two modes" % u.id)


func test_raptor_switches_on_the_pad(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var af: SimEntity = A.structure(w, "structure.shared.airfield", 0, 30, 30)
	var r: SimEntity = A.spawn(w, "unit.napc.raptor_multirole_fighter", 0, 30, 30)
	SimAirSortie.on_aircraft_spawned(w, r, af.id)
	A.run(w, 2)
	var s: int = r.abil.slot_of_kind(K.AK_MODE_SWITCH)
	w.submit_raw(0, SimCmd.build(SimCmd.SET_MODE, [s, 1], PackedInt32Array([r.id])))
	w.step()
	t.eq(r.combat.ext_mode, 1, "on the pad the switch is instant (switch_t = 0)")
	w.submit_raw(0, SimCmd.build(SimCmd.SET_MODE, [s, 0], PackedInt32Array([r.id])))
	w.step()
	t.eq(r.combat.ext_mode, 0, "and back")


func test_every_transport_unit(t: TestCtx) -> void:
	var d: GameData = A.data()
	var units: Array[DefUnit] = _units_with(d, DefEnums.AbilityKind.TRANSPORT)
	t.eq(units.size(), 18, "18 transport-tagged units (15 APC-class + Okapi + Leviathan + Landing Transport)")
	var inf_id: String = "unit.napc.rifle_squad"
	for u: DefUnit in units:
		var w: SimWorld = A.world({"movement": false})
		var carrier: SimEntity = _spawn_anywhere(w, u, 0, 20, 20)
		var da: DefAbility = u.ability_of(DefEnums.AbilityKind.TRANSPORT)
		var cap: int = int(da.params.get("capacity_squads_n", 0))
		t.eq(carrier.cargo.cap_slots, cap, "%s: capacity = sheet" % u.id)
		var loaded: int = 0
		for i: int in cap + 2:
			if SimTransport.board(w, carrier, A.spawn(w, inf_id, 0, 10 + i, 30)):
				loaded += 1
		t.eq(loaded, cap, "%s: exactly %d squads fit" % [u.id, cap])
		var unload_t: int = int(da.params.get("unload_t", 20))
		var sp: int = int(da.params.get("unload_speed_bp", 10000))
		t.eq(SimTransport.unload_interval(w, carrier), maxi((unload_t * 10000 + sp / 2) / sp, 1), "%s: unload cadence = sheet" % u.id)
		t.eq(SimTransport.eject_loss_bp(w, carrier), maxi(4000 - int(da.params.get("passenger_damage_reduction_bp", 0)), 0), "%s: death loss" % u.id)
		t.eq(w.abilities.debug_validate(w).size(), 0, "%s: validate" % u.id)


func test_every_command_field_provider(t: TestCtx) -> void:
	var d: GameData = A.data()
	var units: Array[DefUnit] = _units_with(d, DefEnums.AbilityKind.COMMAND_FIELD)
	t.eq(units.size(), 4, "four command-field units")
	for u: DefUnit in units:
		var w: SimWorld = A.world({"rosters": ["roster.han.china", "roster.nec.vanilla"]})
		var p: SimEntity = _spawn_anywhere(w, u, 0, 30, 30)
		var da: DefAbility = u.ability_of(DefEnums.AbilityKind.COMMAND_FIELD)
		var rc: int = (int(da.params.get("radius_u", 5120)) + 512) >> 10
		var dt: int = int(da.params.get("deploy_t", 0))
		var near: SimEntity = A.spawn(w, "unit.han.nest_rocket_drone", 0, 30 + rc, 30)
		var far: SimEntity = A.spawn(w, "unit.han.nest_rocket_drone", 0, 30 + rc + 1, 30)
		A.run(w, 3)
		if dt > 0:
			t.eq(A.lease_bp(w, near, C.STAT_DMG_OUT), 0, "%s: no field until deployed" % u.id)
			w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [p.abil.slot_of_kind(K.AK_COMMAND_FIELD)], PackedInt32Array([p.id])))
			A.run(w, dt + 3)
		t.eq(A.lease_bp(w, near, C.STAT_DMG_OUT), int(da.params.get("damage_bonus_bp", 0)), "%s: lease = sheet at the rim (%d cells)" % [u.id, rc])
		t.eq(A.lease_bp(w, far, C.STAT_DMG_OUT), 0, "%s: none one cell further" % u.id)


func test_every_heal_and_support_aura(t: TestCtx) -> void:
	var d: GameData = A.data()
	# suppression support (Signal Officer, Echo Team) and the jammer read their sheet numbers
	for u: DefUnit in _units_with(d, DefEnums.AbilityKind.SUPPRESSION_SUPPORT):
		var w: SimWorld = A.world({"rosters": ["roster.def.russia", "roster.nec.vanilla"]})
		var p: SimEntity = _spawn_anywhere(w, u, 0, 30, 30)
		var da: DefAbility = u.ability_of(DefEnums.AbilityKind.SUPPRESSION_SUPPORT)
		var rc: int = (int(da.params.get("radius_u", 5120)) + 512) >> 10
		var inf: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 30 + rc, 30)
		var far: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 30 + rc + 1, 30)
		A.run(w, 3)
		t.eq(A.lease_bp(w, inf, C.STAT_SUP_RECOVER), int(da.params.get("recovery_bonus_bp", 0)), "%s: recovery bonus = sheet" % u.id)
		t.eq(A.lease_bp(w, far, C.STAT_SUP_RECOVER), 0, "%s: radius = sheet" % u.id)
		t.check(p.abil != null, "%s: has its slot" % u.id)
	for u2: DefUnit in _units_with(d, DefEnums.AbilityKind.EW_JAMMER):
		var w2: SimWorld = A.world({"rosters": ["roster.nec.vanilla", "roster.napc.usa"]})
		_spawn_anywhere(w2, u2, 0, 30, 30)
		var da2: DefAbility = u2.ability_of(DefEnums.AbilityKind.EW_JAMMER)
		var rc2: int = (int(da2.params.get("radius_u", 5120)) + 512) >> 10
		var victim: SimEntity = A.spawn(w2, "unit.napc.guardian_tank", 1, 30 + rc2, 30)
		var base: int = w2.players[1].view.layer3.effective_unit_stat(DefEnums.Stat.SIGHT, victim.def_idx, 0)
		A.run(w2, 4)
		var pen: int = int(da2.params.get("sight_penalty_bp", 0))
		t.check(absi(w2.abilities.sight_units(victim) - base * (10000 - pen) / 10000) <= 2, "%s: sight -%d bp" % [u2.id, pen])
	for u3: DefUnit in _units_with(d, DefEnums.AbilityKind.HEAL):
		var w3: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
		_spawn_anywhere(w3, u3, 0, 30, 30)
		var da3: DefAbility = u3.ability_of(DefEnums.AbilityKind.HEAL)
		var rc3: int = (int(da3.params.get("radius_u", 4096)) + 512) >> 10
		var hurt: SimEntity = A.spawn(w3, "unit.napc.rifle_squad", 0, 30 + rc3, 30)
		var out: SimEntity = A.spawn(w3, "unit.napc.rifle_squad", 0, 30 + rc3 + 1, 30)
		hurt.hp = hurt.hp_max / 2
		out.hp = out.hp_max / 2
		var h0: int = hurt.hp
		A.hold_fire(w3)
		A.run(w3, 100)
		var milli: int = hurt.hp_max * int(da3.params.get("rate_bps", 0)) / 20 * 10
		t.eq(hurt.hp - h0, milli / 1000, "%s: rate = sheet (%d bp)" % [u3.id, int(da3.params.get("rate_bps", 0))])
		t.eq(out.hp, out.hp_max / 2, "%s: radius = sheet" % u3.id)


func test_every_detector_unit_starts_on(t: TestCtx) -> void:
	var d: GameData = A.data()
	var n: int = 0
	for u: DefUnit in _units_with(d, DefEnums.AbilityKind.DETECTOR):
		if (u.layer_mask & 1) == 0:  # ground units only
			continue
		var w: SimWorld = A.world({"movement": false, "fog": true})
		var e: SimEntity = _spawn_anywhere(w, u, 0, 30, 30)
		A.run(w, 6)
		t.eq(A.slot_state(e, K.AK_DETECTOR), K.DET_ON, "%s: detector ON" % u.id)
		t.gt(e.vis.det_r, 0, "%s: detection disc stamped" % u.id)
		n += 1
	t.gt(n, 15, "many ground detector units (%d)" % n)


func test_every_camouflage_unit_cloaks(t: TestCtx) -> void:
	var d: GameData = A.data()
	var n: int = 0
	for u: DefUnit in _units_with(d, DefEnums.AbilityKind.CAMOUFLAGE):
		var da: DefAbility = u.ability_of(DefEnums.AbilityKind.CAMOUFLAGE)
		var w: SimWorld = A.world({"movement": false, "fog": true})
		var e: SimEntity = _spawn_anywhere(w, u, 0, 30, 30)
		var delay: int = int(da.params.get("delay_t", 0))
		A.run_to(w, maxi(delay - 1, 0))
		t.eq(e.vis.concealed, 0 if delay > 0 else 1, "%s: visible before the %d-tick arming" % [u.id, delay])
		A.run(w, 4)
		t.eq(e.vis.concealed, 1, "%s: concealed after the arming delay" % u.id)
		e.combat.last_fire_tick = w.tick  # a shot reveals it for delay ticks
		A.run(w, 2)
		t.eq(e.vis.concealed, 0, "%s: firing reveals" % u.id)
		n += 1
	t.ge(n, 5, "camouflage units exist (%d)" % n)


func test_spotter_units_serve_target_conditions(t: TestCtx) -> void:
	var d: GameData = A.data()
	var n: int = 0
	for u: DefUnit in _units_with(d, DefEnums.AbilityKind.SPOTTER):
		var w: SimWorld = A.world({"movement": false})
		var e: SimEntity = _spawn_anywhere(w, u, 0, 30, 30)
		t.gt(e.abil.slot_of_kind(K.AK_SPOTTER), -1, "%s: spotter slot" % u.id)
		n += 1
	t.eq(n, 2, "Mirage Observer and Watchpost Recon Team")


func test_sap_power_reserve_matches_the_trait(t: TestCtx) -> void:
	var d: GameData = A.data()
	var reserve_t: int = 0
	for f: DefFaction in d.factions:
		if f.code == "SAP":
			reserve_t = int(f.player_params.get("defense_power_reserve.reserve_t", 0))
	t.eq(reserve_t, 400, "the SAP trait: 20 s reserve")
	var w: SimWorld = A.world({"rosters": ["roster.sap.vanilla", "roster.nec.vanilla"], "fog": true})
	var pe: SimPlayerEcon = w.players[0].econ
	t.eq(pe.reserve_max, reserve_t, "the power system's reserve equals the trait's reserve_t")
	var gen: SimEntity = A.structure(w, "structure.shared.generator", 0, 20, 20)
	var wt: SimEntity = A.structure(w, "structure.shared.watchtower", 0, 30, 30)
	A.run_to(w, 50)
	w.remove_entity(gen.id, SimEvent.REM_SCRIPT)
	var s: int = wt.abil.slot_of_kind(K.AK_DETECTOR)
	while not w.power.is_shortage(0):
		w.step()
	var seen: int = w.tick - 1  # the tick whose stage 4 first saw the shortage
	A.run_to(w, seen + 400)
	t.eq(wt.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], K.DET_ON, "the reserve keeps the defence detector up for 400 ticks")
	w.step()  # tick seen + 400
	t.eq(wt.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], K.DET_OFF, "and it drops at seen + 400")
	t.check(not w.power.defense_online(0), "defenses_online false")
