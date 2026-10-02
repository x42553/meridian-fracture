extends RefCounted
## 10.1-J (economy tests): the support-power framework on the REAL data, through CMD_USE_POWER: ready when first unlocked,
## absolute cooldowns, powered prerequisites, credits, the vision rules, the ten effect kinds, S8 windows, and one activation
## of every one of the 48 powers with its effect measured in sim state.

const A := preload("res://tests/support/ab2_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")


func _w(rosters: Array = ["roster.napc.usa", "roster.nec.vanilla"], o: Dictionary = {}) -> SimWorld:
	var d: Dictionary = {"rosters": rosters, "movement": false}
	for k: Variant in o.keys():
		d[k] = o[k]
	return A.world(d)


func _pidx(w: SimWorld, pid: int, slot: int) -> int:
	return w.players[pid].econ.slots[slot].def_idx


func _rsn(w: SimWorld, pid: int, slot: int, cx: int = 30, cy: int = 30, angle: int = 0, target: int = 0) -> int:
	return w.strategic.can_activate(w, pid, slot, S.c(cx), S.c(cy), angle, target)


# ---- unlock, ready when first unlocked, cooldown -------------------------------------------------------------------------

func test_ready_when_first_unlocked(t: TestCtx) -> void:
	var w: SimWorld = _w()
	w.players[0].credits = 5000
	t.eq(_rsn(w, 0, 0), SimEconConst.RSN_PREREQ, "no Radar: PREREQ")
	S.base(w, 0, 10, 10)
	t.eq(w.strategic.slot_info(0, 0).ready_tick, 0, "ready_tick 0: ready since unlock (no opening cooldown)")
	t.eq(_rsn(w, 0, 0), SimEconConst.RSN_OK, "T2 power (Radar) usable at once")
	t.eq(_rsn(w, 0, 1), SimEconConst.RSN_OK, "T3 power (Radar + Laboratory) usable at once")
	t.eq(w.strategic.cooldown_left_ticks(w, 0, 0), 0, "cooldown_left 0")
	t.eq(S.n_events(w, SimEconConst.EVT_POWER_UNLOCKED), 3, "EVT_POWER_UNLOCKED once per unlocked slot")
	S.launch(w, 0, 30, 30)
	A.run(w, 40)
	t.eq(S.n_events(w, SimEconConst.EVT_POWER_UNLOCKED), 3, "and never again")


func test_t3_needs_the_laboratory(t: TestCtx) -> void:
	var w: SimWorld = _w()
	S.base(w, 0, 10, 10, false, false)
	t.eq(_rsn(w, 0, 0), SimEconConst.RSN_OK, "T2 power without a Laboratory")
	t.eq(_rsn(w, 0, 1), SimEconConst.RSN_PREREQ, "T3 power without a Laboratory: PREREQ")
	t.eq(S.n_events(w, SimEconConst.EVT_POWER_UNLOCKED), 2, "two slots unlocked (T2, T2)")


func test_cooldown_is_absolute_and_survives_losing_the_radar(t: TestCtx) -> void:
	var w: SimWorld = _w()
	S.base(w, 0, 10, 10)
	var pw: int = _pidx(w, 0, 0)
	var cd: int = w.data.powers[pw].cooldown_t
	S.use(w, 0, pw, 30, 30)
	w.step()
	var s: SimPowerSlot = w.strategic.slot_info(0, 0)
	var t0: int = w.tick - 1
	t.eq(s.ready_tick, t0 + cd, "ready_tick = activation tick + cooldown")
	t.eq(s.uses, 1, "uses")
	t.eq(_rsn(w, 0, 0), SimEconConst.RSN_COOLDOWN, "COOLDOWN right after")
	var radar: SimEntity = null
	for e: SimEntity in w.structures_of(0):
		if w.data.structures[e.def_idx].id == "structure.shared.radar":
			radar = e
	w.kill(radar, SimWorld.Cause.SCRIPT)
	A.run(w, 5)
	t.eq(_rsn(w, 0, 0), SimEconConst.RSN_COOLDOWN, "still COOLDOWN (checked before the prerequisite)")
	A.structure(w, "structure.shared.radar", 0, 10, 17)
	A.run(w, 5)
	t.eq(s.ready_tick, t0 + cd, "destroy + rebuild never resets the cooldown")
	A.run_to(w, t0 + cd - 1)
	t.eq(_rsn(w, 0, 0), SimEconConst.RSN_COOLDOWN, "one tick early")
	t.eq(w.strategic.cooldown_left_ticks(w, 0, 0), 1, "one tick left")
	w.clear_events()
	w.step()
	t.eq(_rsn(w, 0, 0), SimEconConst.RSN_OK, "ready at ready_tick")
	w.step()
	t.eq(S.n_events(w, SimEconConst.EVT_POWER_READY), 1, "EVT_POWER_READY once")


func test_shortage_blocks_use_but_the_cooldown_keeps_running(t: TestCtx) -> void:
	var w: SimWorld = _w()
	S.base(w, 0, 10, 10)
	var pw: int = _pidx(w, 0, 0)
	S.use(w, 0, pw, 30, 30)
	w.step()
	var ready: int = w.strategic.slot_info(0, 0).ready_tick
	# cut the power: sell out the generators by killing them
	for e: SimEntity in w.structures_of(0):
		if w.data.structures[e.def_idx].id == "structure.shared.generator":
			w.kill(e, SimWorld.Cause.SCRIPT)
	A.run(w, 6)
	t.check(w.power.is_shortage(0), "shortage")
	t.eq(_rsn(w, 0, 1), SimEconConst.RSN_NO_POWER, "NO_POWER (Radar offline)")
	t.eq(w.strategic.slot_info(0, 0).ready_tick, ready, "the cooldown is untouched")
	var left: int = w.strategic.cooldown_left_ticks(w, 0, 0)
	A.run(w, 100)
	t.eq(w.strategic.cooldown_left_ticks(w, 0, 0), left - 100, "and keeps running during the shortage")


func test_credits_are_charged_once_and_refused_when_short(t: TestCtx) -> void:
	var w: SimWorld = _w()
	S.base(w, 0, 10, 10)
	var pw: int = _pidx(w, 0, 0)
	var cost: int = w.data.powers[pw].cost
	w.players[0].credits = cost - 1
	t.eq(_rsn(w, 0, 0), SimEconConst.RSN_NO_CREDITS, "NO_CREDITS")
	S.use(w, 0, pw, 30, 30)
	w.step()
	t.eq(w.players[0].credits, cost - 1, "nothing charged")
	t.eq(w.strategic.slot_info(0, 0).ready_tick, 0, "no cooldown started")
	t.eq(w.strategic.slot_info(0, 0).uses, 0, "not used")
	w.players[0].credits = cost + 100
	S.use(w, 0, pw, 30, 30)
	w.step()
	t.eq(w.players[0].credits, 100, "charged once")
	S.use(w, 0, pw, 30, 30)
	w.step()
	t.eq(w.players[0].credits, 100, "the second command is refused (cooldown), no second charge")
	t.eq(w.players[0].econ.stat_spent_powers, cost, "statistic")


func test_rejection_is_reported_with_the_reason(t: TestCtx) -> void:
	var w: SimWorld = _w()
	S.base(w, 0, 10, 10)
	w.players[0].credits = 0
	S.use(w, 0, _pidx(w, 0, 0), 30, 30)
	w.step()
	t.eq(A.event_field(w, SimEvent.CMD_REJECTED, 0, SimEvent.I_C), SimCommand.Err.NO_CREDITS, "CMD_REJECTED carries the error")
	S.use(w, 0, w.data.power_idx("power.def.mobilization_order"), 30, 30)
	w.step()
	t.eq(w.strategic.slot_info(0, 0).uses, 0, "a power of another roster is NOT_AVAILABLE")


# ---- vision rules -------------------------------------------------------------------------------------------------------

func test_vision_rules(t: TestCtx) -> void:
	var w: SimWorld = _w(["roster.napc.usa", "roster.nec.vanilla"], {"fog": true})
	S.base(w, 0, 10, 10)
	w.players[0].credits = 20000
	# napc: slot 0 UAV Sweep (recon: any), slot 1 Field Repair Drop (current), slot 2 Rapid Turnaround (own structure)
	t.eq(_rsn(w, 0, 0, 55, 55), SimEconConst.RSN_OK, "reconnaissance: any map location")
	t.eq(_rsn(w, 0, 1, 55, 55), SimEconConst.RSN_NO_VISION, "current-vision power on a shrouded cell: NO_VISION")
	t.eq(_rsn(w, 0, 1, 12, 12), SimEconConst.RSN_OK, "current-vision power inside the base")
	t.eq(_rsn(w, 0, 1, -1, 30), SimEconConst.RSN_TERRAIN, "outside the map: TERRAIN")
	var fc: String = _roster_with(A.data(), A.data().power_idx("power.olm.false_convoy"))
	var w2: SimWorld = _w([fc, "roster.nec.vanilla"], {"fog": true})
	S.base(w2, 0, 10, 10)
	var slot_decoy: int = -1
	for i: int in 3:
		if w2.data.powers[_pidx(w2, 0, i)].target_vision == DefEnums.TargetVision.EXPLORED:
			slot_decoy = i
	t.check(slot_decoy >= 0, "the OLM roster has a decoy power")
	if slot_decoy >= 0:
		t.eq(_rsn(w2, 0, slot_decoy, 55, 55), SimEconConst.RSN_NOT_EXPLORED, "decoys need an explored cell")
		t.eq(_rsn(w2, 0, slot_decoy, 12, 12), SimEconConst.RSN_OK, "explored: fine even where nothing is visible now")


func test_own_structure_target_rapid_turnaround(t: TestCtx) -> void:
	var w: SimWorld = _w()
	S.base(w, 0, 10, 10)
	var af: SimEntity = A.structure(w, "structure.shared.airfield", 0, 30, 30)
	var pw: int = _pidx(w, 0, 2)
	t.eq(w.data.powers[pw].id, "power.napc.rapid_turnaround", "slot 2")
	t.eq(_rsn(w, 0, 2, 30, 30, 0, 0), SimEconConst.RSN_BAD_TARGET, "no target")
	var gen: SimEntity = w.structures_of(0)[0]
	t.eq(_rsn(w, 0, 2, 30, 30, 0, gen.id), SimEconConst.RSN_WRONG_KIND, "a Generator is the wrong kind")
	var foe: SimEntity = A.structure(w, "structure.shared.airfield", 1, 45, 45)
	t.eq(_rsn(w, 0, 2, 30, 30, 0, foe.id), SimEconConst.RSN_BAD_TARGET, "not an own structure")
	A.run(w, 3)
	t.eq(_rsn(w, 0, 2, 30, 30, 0, af.id), SimEconConst.RSN_OK, "own Airfield")
	S.use(w, 0, pw, 30, 30, 0, af.id)
	w.step()
	t.eq(w.strategic.slot_info(0, 2).uses, 1, "activated")
	t.eq(SimCombatMods.sum_bp(af.combat, C.STAT_REARM_RATE, w.tick), 5000, "the Airfield rearms +50 % (rearm boost lease)")
	t.eq(w.strategic.window_active(w, 0, pw), true, "window registry")
	A.run(w, 405)
	t.eq(SimCombatMods.sum_bp(af.combat, C.STAT_REARM_RATE, w.tick), 0, "for 400 ticks only")
	t.eq(w.strategic.window_active(w, 0, pw), false, "window closed")
	t.eq(S.n_events(w, SimEconConst.EVT_POWER_EFFECT_END), 1, "EVT_POWER_EFFECT_END")


# ---- the ten kinds -------------------------------------------------------------------------------------------------------

func test_classification_counts(t: TestCtx) -> void:
	var d: GameData = A.data()
	var w: SimWorld = _w()
	var n: PackedInt32Array = PackedInt32Array()
	n.resize(11)
	for p: DefPower in d.powers:
		n[SimStrategicEffects.kind_of(w, p)] += 1
	t.eq(d.powers.size(), 48, "48 powers")
	t.eq(n[SimEconConst.EK_REVEAL_ZONE], 3, "REVEAL_ZONE 3")
	t.eq(n[SimEconConst.EK_RECON_SUMMON], 4, "RECON_SUMMON 4")
	t.eq(n[SimEconConst.EK_BUFF], 19, "BUFF 19")
	t.eq(n[SimEconConst.EK_WINDOW], 6, "WINDOW 6")
	t.eq(n[SimEconConst.EK_STRUCT_BUFF], 1, "STRUCT_BUFF 1")
	t.eq(n[SimEconConst.EK_REPAIR], 6, "REPAIR 6")
	t.eq(n[SimEconConst.EK_SMOKE], 2, "SMOKE 2")
	t.eq(n[SimEconConst.EK_DECOY], 3, "DECOY 3")
	t.eq(n[SimEconConst.EK_BOMBARD], 3, "BOMBARD 3")
	t.eq(n[SimEconConst.EK_MARK], 1, "MARK 1")
	var rec: int = 0
	for p2: DefPower in d.powers:
		if SimStrategicEffects.kind_of(w, p2) in [SimEconConst.EK_REVEAL_ZONE, SimEconConst.EK_RECON_SUMMON, SimEconConst.EK_MARK] or p2.id.ends_with("counterlaunch_plot"):
			t.eq(SimStrategicEffects.vision_rule(p2), SimEconConst.VR_NONE, "%s is reconnaissance" % p2.id)
			rec += 1
	t.eq(rec, 9, "9 'any' powers (3 reveal, 4 recon, 2 fire-log)")
	for p3: DefPower in d.powers:
		if SimStrategicEffects.kind_of(w, p3) == SimEconConst.EK_DECOY:
			t.eq(SimStrategicEffects.vision_rule(p3), SimEconConst.VR_EXPLORED, "%s: explored" % p3.id)
		t.check(p3.requires_powered, "%s: powered prerequisites" % p3.id)


func test_window_mobilization_order(t: TestCtx) -> void:
	var w: SimWorld = _w(["roster.def.vanilla", "roster.nec.vanilla"])
	S.base(w, 0, 10, 10)
	var pw: int = w.data.power_idx("power.def.mobilization_order")
	t.check(w.players[0].roster.power_slot(pw) >= 0, "DEF vanilla has Mobilization Order")
	t.eq(w.economy.knob(0, SimEconConst.K_PROD_RATE_BARRACKS_BP), 10000, "neutral before")
	w.clear_events()
	S.use(w, 0, pw, 30, 30)
	w.step()
	var t0: int = w.tick - 1
	t.eq(w.economy.knob(0, SimEconConst.K_PROD_RATE_BARRACKS_BP), 12500, "Barracks 12500")
	t.eq(w.economy.knob(0, SimEconConst.K_PROD_RATE_FACTORY_BP), 12500, "Factory 12500")
	A.run_to(w, t0 + 399)
	t.eq(w.economy.knob(0, SimEconConst.K_PROD_RATE_BARRACKS_BP), 12500, "still on at +399")
	t.eq(w.strategic.window_active(w, 0, pw), true, "window active")
	A.run_to(w, t0 + 400)
	t.eq(w.economy.knob(0, SimEconConst.K_PROD_RATE_BARRACKS_BP), 10000, "restored at exactly +400")
	w.step()
	t.eq(w.economy.knob(0, SimEconConst.K_PROD_RATE_FACTORY_BP), 10000, "Factory restored")
	t.eq(w.strategic.window_active(w, 0, pw), false, "window closed")
	t.eq(S.n_events(w, SimEconConst.EVT_POWER_EFFECT_END), 1, "EVT_POWER_EFFECT_END")


func test_bombard_warns_and_the_shells_leave_when_it_ends(t: TestCtx) -> void:
	var w: SimWorld = _w(["roster.nec.vanilla", "roster.napc.usa"])
	S.base(w, 0, 10, 10)
	A.spawn(w, "unit.napc.rifle_squad", 1, 40, 40)
	var slot: int = -1
	for i: int in 3:
		if w.data.powers[_pidx(w, 0, i)].id == "power.nec.counterbattery_mission":
			slot = i
	t.check(slot >= 0, "NEC has Counterbattery Mission")
	var pw: int = _pidx(w, 0, slot)
	S.use(w, 0, pw, 40, 40)
	w.step()
	var t0: int = w.tick - 1
	var out: Array[SimWarning] = []
	w.strategic.warnings_affecting(0, out)
	t.eq(out.size(), 1, "the caster sees the warning")
	var wr: SimWarning = out[0]
	t.eq(wr.kind, SimEconConst.WK_POWER, "kind POWER")
	t.eq(wr.exec_tick, t0 + 100, "warning 100 ticks")
	t.eq(wr.phase, SimEconConst.AT_WARNING, "WARNING phase")
	var vic: Array[SimWarning] = []
	w.strategic.warnings_affecting(1, vic)
	t.eq(vic.size(), 1, "the player with units inside the zone sees it too (fog cannot hide it)")
	var against: Array[SimWarning] = []
	w.strategic.attacks_pending_against(1, against)
	t.eq(against.size(), 1, "attacks_pending_against lists it for the victim")
	var own: Array[SimWarning] = []
	w.strategic.attacks_pending_against(0, own)
	t.eq(own.size(), 0, "but not for the caster")
	t.eq(w.combat.proj.live_count() > 0, true, "shells are queued at activation (positions and marks fixed now)")
	A.run_to(w, t0 + 101)
	t.eq(wr.phase, SimEconConst.AT_EXEC, "EXEC after the warning")
	t.eq(S.n_events(w, SimEconConst.EVT_SW_EXEC_START), 1, "EVT_SW_EXEC_START")
	A.run(w, 400)
	t.eq(wr.phase, SimEconConst.AT_DONE, "DONE")
	t.eq(S.n_events(w, SimEconConst.EVT_SW_DONE), 1, "EVT_SW_DONE")
	A.run(w, 60)
	t.check(w.strategic.warnings.is_empty(), "removed after the history period")


func test_broadcast_widescan_records_a_scan_warning(t: TestCtx) -> void:
	var w: SimWorld = _w(["roster.han.vanilla", "roster.nec.vanilla"])
	S.base(w, 0, 10, 10)
	var pw: int = w.data.power_idx("power.han.wideband_scan")
	if w.players[0].roster.power_slot(pw) < 0:
		t.skip("Han vanilla roster lacks Wideband Scan")
		return
	S.use(w, 0, pw, 40, 40)
	w.step()
	var out: Array[SimWarning] = []
	w.strategic.warnings_affecting(0, out)
	t.eq(out.size(), 1, "scan warning")
	t.eq(out[0].kind, SimEconConst.WK_SCAN, "WK_SCAN")
	t.eq(out[0].exec_tick - out[0].start_tick, 40, "40 ticks")


# ---- every one of the 48 powers, through the command path --------------------------------------------------------------

func _footprint(w: SimWorld) -> int:
	var fp: int = w.zones.zone_count() * 1000003 + w.entities.size() * 7919 + w.combat.proj.live_count() * 104729
	fp += w.zones.pend.size() * 31 + w.strategic.warnings.size() * 65537 + w.strategic.windows.size() * 13
	for p: SimPlayer in w.players:
		if p.fx != null:
			fp += p.fx.n_active * 15485863
		fp += p.econ.knob_until[SimEconConst.K_SALVAGE_TICKS] + p.econ.knob_until[SimEconConst.K_PROD_RATE_BARRACKS_BP] + p.econ.knob_until[SimEconConst.K_PROD_RATE_FACTORY_BP]
	for e: SimEntity in w.entities:
		if e.abil != null:
			fp += e.abil.n_fx * 2038073
		if e.combat != null and not e.combat.mods.is_empty():
			for i: int in SimCombatConsts.MAX_MODS:
				if e.combat.mods[i * SimCombatConsts.MODS_STRIDE + SimCombatConsts.MOD_STAT] != SimCombatConsts.STAT_NONE:
					fp += 611953
	for i2: int in w.abilities.aura.win_until.size():
		fp += w.abilities.aura.win_until[i2]
	return fp


func _roster_with(d: GameData, p_idx: int) -> String:
	for r: DefRoster in d.rosters:
		if r.power_slot(p_idx) >= 0:
			return r.id
	return ""


func test_all_48_powers_activate_through_the_framework(t: TestCtx) -> void:
	var d: GameData = A.data()
	var used_kinds: Dictionary = {}
	for pi: int in d.powers.size():
		var p: DefPower = d.powers[pi]
		var rid: String = _roster_with(d, pi)
		if rid == "":
			t.fail("%s belongs to no roster" % p.id)
			continue
		var foe_roster: String = "roster.nec.vanilla" if not rid.contains(".nec.") else "roster.napc.usa"
		var w: SimWorld = _w([rid, foe_roster])
		S.base(w, 0, 10, 10)
		var ids: Array[String] = ["unit.shared.engineer", "unit.shared.collector"]
		for u: DefUnit in d.units:
			if w.players[0].roster.has_unit(u.index) and not u.id.begins_with("summon.") and not u.id.begins_with("unit.drone") and ids.size() < 24 and u.cost > 0:
				ids.append(u.id)
		var n: int = 0
		for id: String in ids:
			if d.unit_idx(id) >= 0 and w.players[0].roster.has_unit(d.unit_idx(id)):
				A.spawn(w, id, 0, 28 + n % 6, 28 + n / 6)
				n += 1
		A.structure(w, "structure.shared.watchtower", 0, 31, 34)
		A.structure(w, "structure.shared.barracks", 0, 34, 31)
		var foe: SimEntity = A.spawn(w, "unit.nec.archer_spg" if w.players[1].roster.has_unit(d.unit_idx("unit.nec.archer_spg")) else "unit.napc.paladin_howitzer", 1, 30, 30)
		foe.combat.last_fire_tick = w.tick
		A.hold_fire(w)
		var target: int = 0
		if p.params.has("target_structure_idx"):
			target = A.structure(w, d.structures[(p.params["target_structure_idx"] as PackedInt32Array)[0]].id, 0, 45, 45).id
		A.run(w, 3)
		var slot: int = w.players[0].roster.power_slot(pi)
		var credits: int = w.players[0].credits
		var before: int = _footprint(w)
		t.eq(_rsn(w, 0, slot, 30, 30, 0, target), SimEconConst.RSN_OK, "%s validates" % p.id)
		w.clear_events()
		S.use(w, 0, pi, 30, 30, 0, target)
		w.step()
		A.run(w, 3)
		t.eq(S.n_events(w, SimEconConst.EVT_POWER_ACTIVATED), 1, "%s: EVT_POWER_ACTIVATED" % p.id)
		t.eq(A.event_field(w, SimEconConst.EVT_POWER_ACTIVATED, 0, SimEvent.I_C), pi, "%s: event carries the power index" % p.id)
		t.eq(w.players[0].credits, credits - p.cost, "%s: cost charged once" % p.id)
		t.eq(w.strategic.slot_info(0, slot).ready_tick, w.strategic.slot_info(0, slot).last_activation_tick + p.cooldown_t, "%s: cooldown" % p.id)
		t.check(_footprint(w) != before, "%s changed the sim (zones, entities, leases, windows, projectiles or warnings)" % p.id)
		t.eq(S.kind_effect(w, p, pi), "", "%s: its stated effect is present in sim state" % p.id)
		if p.warning_t > 0:
			var out: Array[SimWarning] = []
			w.strategic.warnings_affecting(0, out)
			t.eq(out.size(), 1, "%s: warning visible to the caster" % p.id)
		t.eq(w.zones.debug_validate(w), PackedStringArray(), "%s: zones validate" % p.id)
		used_kinds[SimStrategicEffects.kind_of(w, p)] = int(used_kinds.get(SimStrategicEffects.kind_of(w, p), 0)) + 1
	t.eq(used_kinds.size(), 10, "all ten effect kinds were exercised")


# ---- S8 windows ---------------------------------------------------------------------------------------------------------

func _roster_and_slot(d: GameData, power_id: String) -> Array:
	var pi: int = d.power_idx(power_id)
	var rid: String = _roster_with(d, pi)
	return [rid, pi]


func _window_case(t: TestCtx, power_id: String, knob: int, during: int, base: int, ticks: int) -> void:
	var d: GameData = A.data()
	var rp: Array = _roster_and_slot(d, power_id)
	var w: SimWorld = _w([rp[0], "roster.nec.vanilla" if not str(rp[0]).contains(".nec.") else "roster.napc.usa"])
	S.base(w, 0, 10, 10)
	var pi: int = int(rp[1])
	t.eq(w.economy.knob(0, knob), base, "%s: base before" % power_id)
	S.use(w, 0, pi, 30, 30)
	w.step()
	var t0: int = w.tick - 1
	t.eq(w.economy.knob(0, knob), during, "%s: knob during" % power_id)
	A.run_to(w, t0 + ticks - 1)
	t.eq(w.economy.knob(0, knob), during, "%s: still on one tick before the end" % power_id)
	A.run_to(w, t0 + ticks)
	t.eq(w.economy.knob(0, knob), base, "%s: restored at exactly +%d" % [power_id, ticks])
	w.step()
	t.eq(w.strategic.window_active(w, 0, pi), false, "%s: window closed" % power_id)
	t.eq(S.n_events(w, SimEconConst.EVT_POWER_EFFECT_END), 1, "%s: EVT_POWER_EFFECT_END" % power_id)


func test_s8_windows_restore_their_knobs(t: TestCtx) -> void:
	_window_case(t, "power.nec.treaty_coordination", SimEconConst.K_RELAY_DAMAGE_BP, 1500, 1000, 400)
	_window_case(t, "power.han.central_priority", SimEconConst.K_CMD_DAMAGE_BP, 2000, 1000, 300)
	_window_case(t, "power.han.reserve_bandwidth", SimEconConst.K_CMD_RADIUS_CELLS, 8, 5, 400)
	_window_case(t, "power.pd.joint_landing", SimEconConst.K_JOINT_LANDING, 1, 0, 300)
	_window_case(t, "power.ae.recovery_priority", SimEconConst.K_SALVAGE_TICKS, 60, 160, 400)
	_window_case(t, "power.ae.recovery_priority", SimEconConst.K_RECOVERY_PRIORITY, 1, 0, 400)
	_window_case(t, "power.def.mobilization_order", SimEconConst.K_PROD_RATE_FACTORY_BP, 12500, 10000, 400)


func test_recovery_priority_speeds_up_new_units(t: TestCtx) -> void:
	var d: GameData = A.data()
	var rp: Array = _roster_and_slot(d, "power.ae.recovery_priority")
	var w: SimWorld = _w([rp[0], "roster.nec.vanilla"])
	S.base(w, 0, 10, 10)
	var eng: SimEntity = A.spawn(w, "unit.shared.engineer", 0, 30, 30)
	var base: int = SimStats.peek(w, eng, DefEnums.Stat.SPEED)
	S.use(w, 0, int(rp[1]), 30, 30)
	w.step()
	t.eq(SimStats.get_val(w, eng, DefEnums.Stat.SPEED), base * 125 / 100, "an existing Engineer moves +25 %")
	var eng2: SimEntity = A.spawn(w, "unit.shared.engineer", 0, 31, 30)
	A.run(w, 3)
	t.eq(SimStats.get_val(w, eng2, DefEnums.Stat.SPEED), base * 125 / 100, "one created inside the window too")
	A.run(w, 405)
	t.eq(SimStats.get_val(w, eng, DefEnums.Stat.SPEED), base, "back to normal after 400 ticks")
