extends RefCounted
## DATA-05: rules loader (research, powers, zones, neutrals, faction traits) and the effect / superweapon compiler
## (data_balance 5.10 / 7.5 / 7.9-7.14, docs/RULES_DATA_NOTES.md, 10.1 "superweapons").

const K := DefEnums.Kind
const EO := DefEnums.EffectOp

static var _real: GameData = null


## Real sheets + real rules files (the tempest / dragonfall summons exist only in the real sheets).
static func real() -> GameData:
	if _real == null:
		_real = DefTestKit.stub_game_data(true)
	return _real


func _fx(d: GameData) -> DefLoaderEffects.Fx:
	return DefLoaderEffects.make_ctx(d._sources, d, DefLoadReport.new())


func test_counts(t: TestCtx) -> void:
	var d: GameData = real()
	if not t.not_null(d, "load: " + GameData.last_report.text(6)):
		return
	t.eq(d.research.size(), 40, "40 research")
	t.eq(d.powers.size(), 48, "48 powers")
	t.eq(d.superweapons.size(), 8, "8 superweapons")
	t.eq(d.neutrals.size(), 8, "8 neutrals")
	t.eq(d.factions.size(), 8, "8 factions")
	for r: DefResearch in d.research:
		t.check(not r.effects.is_empty(), "%s has effects" % r.id)
		if r.effects.is_empty():
			break
	for p: DefPower in d.powers:
		t.check(not p.actions.is_empty(), "%s has actions" % p.id)
		if p.actions.is_empty():
			break
	t.eq(d.zones.size(), d.ids.count(K.ZONE), "one zone def per zone id (templates + inline)")
	t.check(d.ids.index_of(K.ZONE, "zone.smoke_dust_screen") >= 0 and d.ids.index_of(K.ZONE, "zone.ae.civil_defense_net") >= 0, "shared template + inline power zone ids")
	for z: DefZone in d.zones:
		t.check(z.duration_t > 0 or z.zone_kind == DefEnums.ZoneKind.DECOY or z.zone_kind == DefEnums.ZoneKind.INTERCEPT, "zone %s has a duration" % z.id)


func test_jtl_effect(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var r: DefResearch = d.research[d.research_idx("research.napc.joint_tactical_links")]
	t.eq(r.effects.size(), 1, "one effect")
	var e: DefEffect = r.effects[0]
	t.eq(e.op, EO.STAT_MOD, "op")
	t.eq(e.stat, DefEnums.Stat.RANGE, "weapon_range_cells")
	t.eq(e.delta_bp, 1000, "+10 %")
	t.eq(e.cond_codes, PackedInt32Array([DefEnums.Cond.NEAR_FRIENDLY_UNIT]), "cond code 10")
	t.eq(e.cond_params.size(), 1, "parallel params")
	var p: Dictionary = e.cond_params[0]
	t.eq(p["radius_u"], 6144, "6 cells")
	t.eq(p["include_replacements"], true, "flag kept")
	t.eq(p["unit_idx"], PackedInt32Array([d.unit_idx("unit.napc.javelin_team"), d.unit_idx("unit.napc.rifle_squad")]), "ascending unit indices")
	t.eq(e.duration_t, 0, "permanent")
	t.eq(d.stack_groups[e.stack_group], "research.napc.joint_tactical_links", "stack group")
	var sel: DefSelector = d.selectors[e.selector]
	t.eq(sel.id, "inline.research.napc.joint_tactical_links#0", "deterministic inline id")
	t.check(sel.include_replacements and sel.explicit_units.size() == 2, "inline selector clauses")
	t.eq(sel.kind_mask, 1 << K.UNIT, "unit kind")


func test_resist_effects(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var ap: DefEffect = d.research[d.research_idx("research.napc.adaptive_plating")].effects[0]
	t.eq(ap.op, EO.RESIST_MOD, "op")
	t.eq(ap.delta_bp, 1000, "10 %")
	t.eq(ap.group_mask, DefEnums.RG_EXPLOSIVE, "explosive group")
	t.eq(ap.fire_mode_mask, 0, "any fire mode")
	t.eq(ap.frontal_arc_a, 0, "all directions")
	t.eq(ap.selector, d.selector_idx("selector.land_combat_vehicles"), "named selector")
	var dust: DefZone = d.zones[d.zone_idx("zone.smoke_dust_screen")]
	var de: DefEffect = dust.effects[0]
	t.eq(de.delta_bp, 3000, "dust screen 30 %")
	t.eq(de.group_mask, 0, "every group except EMP")
	t.eq(de.fire_mode_mask, 1, "direct fire only")
	t.eq(dust.zone_kind, DefEnums.ZoneKind.SMOKE, "smoke")
	t.eq(dust.affects, DefEnums.AFFECTS_ALL, "affects all")
	t.eq(dust.radius, 6144, "radius 6")
	t.eq(dust.duration_t, 240, "12 s")
	# the Gate Guard shield spelling of the spec: frontal arc 180 deg = 2048
	var fx: DefLoaderEffects.Fx = _fx(d)
	var gs: Array[DefEffect] = DefLoaderEffects.compile_effect(fx, {"op": "resist_mod", "pct": 25, "groups": ["bullet"], "frontal_arc_deg": 180, "selector": "selector.combat_infantry"}, "test", "test")
	t.eq(gs.size(), 1, "one effect")
	t.eq(gs[0].group_mask, 1, "bullet")
	t.eq(gs[0].frontal_arc_a, 2048, "180 deg")
	t.check(fx.rep.is_ok(), "clean: " + fx.rep.text(3))


func test_param_and_grant_effects(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var ip: DefResearch = d.research[d.research_idx("research.sap.integrated_protection")]
	t.eq(ip.effects.size(), 2, "param_mod + grant")
	var pm: DefEffect = ip.effects[0]
	t.eq(pm.op, EO.PARAM_MOD, "param_mod")
	t.eq(pm.scope, DefEnums.ParamScope.ABILITY, "ability scope")
	t.eq(pm.ability_kind, DefEnums.AbilityKind.INTERCEPTOR, "interceptor")
	t.eq(pm.key, "cooldown_t", "runtime key")
	t.eq(pm.param_op, DefEnums.ParamOp.SET, "set")
	t.eq(pm.value, 200, "10 s = 200 ticks")
	var gr: DefEffect = ip.effects[1]
	t.eq(gr.op, EO.GRANT_ABILITY, "grant")
	t.eq(gr.ability.kind, DefEnums.AbilityKind.INTERCEPTOR, "granted kind")
	t.eq(gr.ability.params["cooldown_t"], 200, "grant cooldown")
	t.eq(gr.ability.params["charges_n"], 1, "grant charges")
	# mul_pct stores a factor
	var tw: DefEffect = d.research[d.research_idx("research.nec.tunnel_workshops")].effects[0]
	t.eq(tw.param_op, DefEnums.ParamOp.MUL_BP, "mul")
	t.eq(tw.value, 12500, "mul_pct 125 = 12500")
	t.eq(tw.key, "rate_bps", "rate_pct_per_s is percent per second")
	t.eq(tw.filter.get("target_structure_mask", 0), d.tags.structure_bit("defense"), "filter converted to a mask")
	var bd: DefEffect = d.research[d.research_idx("research.def.buried_command_lines")].effects[0]
	t.eq(bd.scope, DefEnums.ParamScope.DEF, "def scope")
	t.eq(bd.key, "emp_recovery_bp", "def key")
	t.eq(bd.value, 7500, "0.75x")
	# a selector union becomes one effect per selector
	t.eq(d.research[d.research_idx("research.def.buried_command_lines")].effects.size(), 2, "radar + defensive structures")
	var pl: DefEffect = d.research[d.research_idx("research.sap.reserve_capacitors")].effects[0]
	t.eq(pl.scope, DefEnums.ParamScope.PLAYER, "player scope")
	t.eq(pl.key, "defense_power_reserve.reserve_t", "player key is kind-qualified")
	t.eq(pl.value, 700, "35 s")
	t.eq(pl.selector, -1, "no selector for player params")
	var fl: DefEffect = d.research[d.research_idx("research.han.guard_integration")].effects[0]
	t.eq(fl.op, EO.SET_FLAG, "set_flag")
	t.eq(fl.flag, "command_field_eligible", "flag")


func test_conditions(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var sc: DefEffect = d.research[d.research_idx("research.napc.sealed_compartments")].effects[0]
	t.eq(sc.cond_codes, PackedInt32Array([DefEnums.Cond.ON_WATER_RT]), "on_water inside an effect is runtime code 21")
	var ob: DefEffect = d.research[d.research_idx("research.def.coordinated_barrages")].effects[0]
	t.eq(ob.cond_codes, PackedInt32Array([DefEnums.Cond.STATIONARY]), "stationary")
	t.eq(ob.cond_params[0]["for_t"], 80, "4 s")
	var lf: DefEffect = d.research[d.research_idx("research.sap.layered_fieldworks")].effects[0]
	t.eq(lf.cond_params[0]["radius_u"], 4096, "4 cells")
	t.eq(lf.cond_params[0]["selector_idx"], d.selector_idx("selector.defensive_structures"), "selector by id inside a condition")
	var fx: DefLoaderEffects.Fx = _fx(d)
	var bad: Array[DefEffect] = DefLoaderEffects.compile_effect(fx, {"op": "stat_mod", "stat": "health", "delta_pct": 5, "selector": "selector.combat_units", "cond": [{"code": "paid_repair"}]}, "test", "test")
	t.check(fx.rep.has_rule("V-EFF-01"), "paid_repair is not allowed inside an effect (%d)" % bad.size())
	var fx2: DefLoaderEffects.Fx = _fx(d)
	DefLoaderEffects.compile_effect(fx2, {"op": "stat_mod", "stat": "health", "delta_pct": 5, "selector": "selector.combat_units", "cond": [{"code": "no_such_cond"}]}, "test", "test")
	t.check(fx2.rep.has_rule("V-MOD-04"), "unknown condition code")
	var fx3: DefLoaderEffects.Fx = _fx(d)
	DefLoaderEffects.compile_effect(fx3, {"op": "no_such_op"}, "test", "test")
	t.check(fx3.rep.has_rule("V-EFF-01"), "unknown op")
	var fx4: DefLoaderEffects.Fx = _fx(d)
	DefLoaderEffects.compile_effect(fx4, {"op": "param_mod", "scope": "ability", "ability": "interceptor", "key": "cooldown_s", "set": 1, "add": 2, "selector": "selector.combat_units"}, "test", "test")
	t.check(fx4.rep.has_rule("V-EFF-01"), "param_mod needs exactly one operator")


func test_inline_selectors_and_stack_groups(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var sorted_groups: PackedStringArray = d.stack_groups.duplicate()
	sorted_groups.sort()
	t.eq(d.stack_groups, sorted_groups, "stack-group registry is sorted")
	t.check(d.stack_groups.has("relay_field") and d.stack_groups.has("command_field") and d.stack_groups.has("smoke"), "registry has the shared groups")
	var seen: Dictionary = {}
	var inline_n: int = 0
	for i: int in d.selectors.size():
		var s: DefSelector = d.selectors[i]
		t.eq(s.index, i, "selector index == position")
		if s.id.begins_with("inline."):
			inline_n += 1
			t.check(not seen.has(s.id), "inline id %s unique" % s.id)
			seen[s.id] = true
			if inline_n > 3:
				continue
	t.check(inline_n >= 40, "inline selectors were created (%d)" % inline_n)
	var d2: GameData = GameData.load_from_sources(DefTestKit.stub_sources(true))
	t.eq(d2.data_hash(), d.data_hash(), "a second load gives the same hash (ids, selectors, groups deterministic)")


func test_powers(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var cb: DefPower = d.powers[d.power_idx("power.nec.counterbattery_mission")]
	t.eq(cb.warning_t, 100, "5 s warning")
	t.eq(cb.target_mode, DefEnums.TargetMode.POINT, "point")
	t.eq(cb.target_vision, DefEnums.TargetVision.CURRENT, "current")
	t.eq(cb.radius, 4096, "radius")
	t.eq(cb.actions.size(), 1, "one action")
	var a: DefPowerAction = cb.actions[0]
	t.eq(a.op, DefEnums.PowerOp.STRIKE, "strike")
	t.eq(a.count, 6, "6 shells")
	t.eq(a.duration_t, 80, "over 4 s")
	t.eq(a.radius, 4096, "zone radius")
	t.eq(a.impacts.size(), 1, "prototype packet")
	var p: DefImpactPacket = a.impacts[0]
	t.eq(p.damage, 320, "shell damage")
	t.eq(p.dtype, DefEnums.DamageType.HE, "artillery shell is HE")
	t.eq(p.radius, 1638, "1.6 cells")
	t.eq(p.edge_bp, 3000, "30 %")
	t.eq(p.delay_t, 0, "delay comes from the schedule")
	t.eq(p.non_lethal, false, "lethal")
	var sched: Array[int] = []
	for k: int in a.count:
		sched.append(DefLoaderEffects.strike_delay(a.duration_t, a.count, k))
	t.eq(sched, [0, 13, 26, 40, 53, 66] as Array[int], "shell schedule k * 80 / 6")
	t.eq(a.params["pattern"], "random_in_radius", "pattern")
	var tb: DefPowerAction = d.powers[d.power_idx("power.def.tremor_barrage")].actions[0]
	t.eq(tb.count, 6, "6 shells per wave")
	t.eq(tb.params["waves_n"], 4, "4 waves")
	t.eq(tb.duration_t, 160, "8 s")
	var cl: DefPowerAction = d.powers[d.power_idx("power.sap.counterlaunch_plot")].actions[0]
	t.eq(cl.op, DefEnums.PowerOp.MARK, "mark")
	t.eq(cl.count, 3, "3 shells per mark")
	t.eq(cl.params["shell_gap_t"], 12, "0.6 s")
	t.eq(cl.params["max_marks_n"], 6, "max marks")
	t.eq(cl.params["lookback_t"], 160, "8 s")
	t.eq(cl.params["find_selector_idx"], d.selector_idx("selector.land_artillery"), "find selector")
	# zone / summon / global effect actions
	var uav: DefPowerAction = d.powers[d.power_idx("power.napc.uav_sweep")].actions[0]
	t.eq(uav.op, DefEnums.PowerOp.SUMMON, "summon")
	t.eq(uav.summon, d.unit_idx("summon.napc.uav"), "summon def")
	t.eq(uav.duration_t, 240, "12 s lifetime")
	var ds: DefPowerAction = d.powers[d.power_idx("power.olm.dust_screen")].actions[0]
	t.eq(ds.op, DefEnums.PowerOp.ZONE, "zone")
	t.eq(ds.zone, d.zone_idx("zone.smoke_dust_screen"), "shared template")
	t.eq(ds.radius, 6144, "radius")
	t.eq(ds.duration_t, 240, "12 s")
	var cp: DefPowerAction = d.powers[d.power_idx("power.han.central_priority")].actions[0]
	t.eq(cp.op, DefEnums.PowerOp.GLOBAL_EFFECT, "global effect")
	t.eq(cp.duration_t, 300, "15 s")
	t.eq(cp.effects[0].op, EO.PARAM_MOD, "param_mod inside")
	t.eq(cp.effects[0].value, 2000, "damage_bonus 20 %")
	var ra: DefPower = d.powers[d.power_idx("power.napc.rapid_turnaround")]
	t.eq(ra.target_mode, DefEnums.TargetMode.OWN_STRUCTURE, "own structure")
	t.eq(ra.params["target_structure_idx"], PackedInt32Array([d.structure_idx("structure.shared.airfield")]), "airfield target")
	t.eq(ra.params["target_powered_required"], true, "powered")
	var fr: DefPower = d.powers[d.power_idx("power.napc.field_repair_drop")]
	t.eq(fr.actions.size(), 2, "summon + zone")
	t.eq(fr.actions[1].params["delay_t"], 100, "5 s approach")
	t.eq(fr.actions[1].params["fizzle_if_summon_lost"], true, "flag")
	var cd: DefZone = d.zones[d.zone_idx("zone.ae.civil_defense_net")]
	t.eq(cd.zone_kind, DefEnums.ZoneKind.BUFF, "inline zone")
	t.eq(cd.effects.size(), 2, "sight + suppression immunity")
	t.eq(cd.effects[1].op, EO.IMMUNITY, "immunity")
	t.eq(cd.effects[1].duration_t, 300, "15 s")
	t.eq(cd.effects[1].params["kind"], "suppression", "kind kept")
	var hl: DefEffect = d.zones[d.zone_idx("zone.napc.floating_workshop")].effects[0]
	t.eq(hl.op, EO.HEAL, "heal effect")
	t.eq(hl.params["rate_bps"], 150, "1.5 %/s")
	t.eq(hl.params["cost"], "free", "free")


func test_superweapons(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var atlas: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.napc.atlas_kinetic_array")]
	t.eq(atlas.action_kind, DefEnums.SwAction.KINETIC_VOLLEY, "atlas action")
	t.eq(atlas.recharge_t, 9600, "480 s")
	t.eq(atlas.warning_t, 200, "10 s")
	t.eq(atlas.max_charges, 1, "one charge")
	t.eq(atlas.starts_charged, false, "starts empty")
	t.eq(atlas.target_vision, DefEnums.TargetVision.EXPLORED, "explored")
	t.eq(atlas.packets.size(), 3, "three rods")
	for i: int in 3:
		var p: DefImpactPacket = atlas.packets[i]
		t.eq(p.damage, 2400, "damage")
		t.eq(p.dtype, DefEnums.DamageType.KINETIC, "kinetic")
		t.eq(p.radius, 2048, "2 cells")
		t.eq(p.edge_bp, 5000, "50 %")
		t.eq(p.offset_x, (i - 1) * 3072, "offset %d" % i)
		t.eq(p.delay_t, 0, "same tick")
	var au: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.nec.aurora_microwave_array")]
	t.eq(au.action_kind, DefEnums.SwAction.EMP_BURST, "aurora action")
	t.eq(au.recharge_t, 8400, "420 s")
	t.eq(au.warning_t, 160, "8 s")
	t.eq(au.radius, 8192, "8 cells")
	t.eq(au.packets[0].damage, 150, "emp damage")
	t.eq(au.packets[0].dtype, DefEnums.DamageType.EMP, "emp")
	t.eq(au.packets[0].edge_bp, 10000, "flat")
	t.eq(au.packets[0].non_lethal, true, "non lethal")
	t.eq(au.params["weapon_disable_t"], 160, "8 s weapons")
	t.eq(au.params["structure_shutdown_t"], 360, "18 s structures")
	t.eq(au.params["infantry_unaffected"], true, "infantry immune")
	var he: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.olm.helios_reflector")]
	t.eq(he.action_kind, DefEnums.SwAction.BEAM_SWEEP, "helios action")
	t.eq(he.packets[0].damage, 620, "dps")
	t.eq(he.packets[0].dtype, DefEnums.DamageType.THERMAL, "thermal")
	t.eq(he.packets[0].radius, 1536, "half the width")
	t.eq(he.params["hit_every_t"], 5, "4 hits per second")
	t.eq(he.params["traverse_t"], 240, "12 s")
	t.eq(he.params["line_len_u"], 16384, "16 cells")
	t.eq(he.params["width_u"], 3072, "3 cells")
	t.eq(DefConvert.rdiv(he.packets[0].damage * 5, 20), 155, "per-hit damage 155")
	var pe: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.def.perun_missile_complex")]
	t.eq(pe.packets.size(), 2, "core + ring")
	t.eq(pe.packets[0].damage, 5200, "core")
	t.eq(pe.packets[0].radius, 3072, "core radius")
	t.eq(pe.packets[1].radius, 7168, "ring radius")
	t.eq(pe.packets[1].edge_bp, 3000, "ring edge")
	t.eq(pe.packets[0].dtype, DefEnums.DamageType.HE, "he")
	var te: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.pd.tempest_swarm_hub")]
	t.eq(te.action_kind, DefEnums.SwAction.DRONE_SWARM, "tempest action")
	t.eq(te.summon_count, 24, "24 drones")
	t.eq(te.radius, 6144, "6 cells")
	t.eq(te.duration_t, 400, "20 s window")
	t.eq(te.summon, d.unit_idx("summon.pd.tempest_strike_drone"), "drone def")
	var df: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.han.dragonfall_field_foundry")]
	t.eq(df.action_kind, DefEnums.SwAction.ENGINE_DROP, "dragonfall action")
	t.eq(df.summon_count, 3, "3 capsules")
	t.eq(df.radius, 5120, "5 cells")
	t.eq(df.duration_t, 1200, "engine lifetime 60 s")
	t.eq(df.params["unfold_t"], 100, "5 s unfold")
	t.eq(df.summon, d.unit_idx("summon.han.dragonfall_engine"), "engine def")
	var ho: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.ae.horizon_mass_driver")]
	t.eq(ho.action_kind, DefEnums.SwAction.RAIL_STRIKE, "horizon action")
	t.eq(ho.packets.size(), 3, "three packets")
	t.eq(ho.packets[0].offset_x, -5120, "-5 cells")
	t.eq(ho.packets[2].offset_x, 5120, "+5 cells")
	t.eq([ho.packets[0].delay_t, ho.packets[1].delay_t, ho.packets[2].delay_t], [0, 90, 180], "at 0 / 4.5 / 9 s")
	t.eq(ho.packets[1].damage, 1300, "damage")
	t.eq(ho.packets[1].radius, 3072, "3 cells")
	t.eq(ho.duration_t, 180, "9 s")
	t.eq(ho.params["line_len_u"], 10240, "10 cells")
	t.eq(ho.params["debris_speed_bp"], 6500, "65 %")
	t.eq(ho.params["debris_duration_t"], 400, "20 s")
	t.eq(ho.zone, d.zone_idx("zone.horizon_debris"), "debris zone")
	var tri: DefSuperweapon = d.superweapons[d.superweapon_idx("superweapon.sap.trident_interception_array")]
	t.eq(tri.action_kind, DefEnums.SwAction.INTERCEPT_ZONE, "trident action")
	t.eq(tri.recharge_t, 7200, "360 s")
	t.eq(tri.warning_t, 120, "6 s")
	t.eq(tri.radius, 6144, "6 cells")
	t.eq(tri.duration_t, 500, "25 s")
	t.eq(tri.params["charges_n"], 24, "charges")
	t.eq(tri.params["charges_per_strategic_packet_n"], d.economy.intercept_packet_charges_n, "= economy value")
	t.eq(tri.params["strategic_reduction_bp"], 5000, "50 %")
	t.eq(tri.zone, d.zone_idx("zone.trident_interception"), "interception zone")


func test_superweapon_timing_is_verified_against_the_bible(t: TestCtx) -> void:
	var s: DefSources = DefTestKit.stub_sources(true)
	((s.balance["global.json"] as Dictionary)["superweapons"] as Dictionary)["atlas"]["recharge_s"] = 470
	t.check(GameData.load_from_sources(s) == null, "a recharge that differs from the bible refuses to load")
	t.check(GameData.last_report.has_rule("V-CNF-05"), "V-CNF-05")


func test_neutrals(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var sf: DefNeutral = d.neutrals[d.neutral_idx("neutral.salvage_field")]
	t.eq(sf.neutral_kind, DefEnums.NeutralKind.DEPOSIT, "deposit")
	t.eq(sf.health, 1, "health")
	t.eq(sf.armor_class, 8, "building_light")
	t.eq(sf.fp_w, 3, "w")
	t.eq(sf.fp_h, 3, "h")
	t.eq(sf.sight, 0, "no sight")
	t.eq(sf.capturable, false, "not capturable")
	t.eq(sf.reward["cells_n"], 24, "24 cells")
	t.eq(sf.reward["credits_per_cell_cr"], 600, "600 per cell")
	t.eq(d.neutrals[d.neutral_idx("neutral.salvage_field_rich")].reward["credits_per_cell_cr"], d.economy.deposit_rich_cr_per_cell, "rich deposit mirrors the economy value")
	var cg: DefNeutral = d.neutrals[d.neutral_idx("neutral.civilian_garrison")]
	t.eq(cg.garrison_squads, d.economy.garrison_squads_n, "4 squads = bible")
	t.check(cg.radius > 0, "radius derived from the footprint")
	var ht: DefNeutral = d.neutrals[d.neutral_idx("neutral.harbor_terminal")]
	t.eq(ht.params["berth"], [0, 3, 3, 2], "berth kept as ints")
	t.eq(ht.params["needs_shore"], true, "flag")
	t.eq(d.neutrals[d.neutral_idx("neutral.salvage_depot")].reward["income_mcpt"], 250, "5 credits/s = 250 milli-credits per tick")
	t.eq(d.neutrals[d.neutral_idx("neutral.substation")].reward["power_n"], 100, "power")


func test_factions_and_traits(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var napc: DefFaction = d.factions[d.faction_idx("faction.napc")]
	t.eq(napc.grants.size(), 1, "factory apron grant")
	var g: DefEffect = napc.grants[0]
	t.eq(g.op, EO.GRANT_ABILITY, "grant")
	t.eq(g.ability.kind, DefEnums.AbilityKind.AURA_REGEN, "aura_regen")
	t.eq(g.ability.params["radius_u"], 5120, "5 cells")
	t.eq(g.ability.params["rate_bps"], 100, "1 %/s")
	t.eq(g.ability.params["cap_bp"], 7500, "75 %")
	t.eq(g.ability.params["idle_t"], 120, "6 s")
	t.eq(g.ability.params["target_selector"], "selector.land_combat_vehicles", "selector name kept for the ability")
	t.eq(d.selectors[g.selector].explicit_structs, PackedInt32Array([d.structure_idx("structure.shared.factory")]), "factory")
	var ae: DefFaction = d.factions[d.faction_idx("faction.ae")]
	t.eq(ae.grants.size(), 1, "salvage grant")
	t.eq(ae.grants[0].ability.kind, DefEnums.AbilityKind.SALVAGE, "salvage")
	var sap: DefFaction = d.factions[d.faction_idx("faction.sap")]
	t.eq(sap.player_params["defense_power_reserve.reserve_t"], 400, "20 s reserve")
	t.eq(sap.player_params["defense_power_reserve.recharge_t"], 1200, "60 s recharge")
	t.eq(sap.pres_palette, "palette.sap", "palette id")
	var napc_r: DefRoster = d.roster_for("napc", "canada")
	t.eq(napc_r.player_params, napc.player_params, "roster inherits player params")


func test_trait_coverage_is_enforced(t: TestCtx) -> void:
	var s: DefSources = DefTestKit.stub_sources(true)
	var traits: Dictionary = ((s.balance["faction_traits.json"] as Dictionary)["factions"] as Dictionary)["faction.napc"]["traits"]
	traits.erase("trait.napc.strengths")
	t.check(GameData.load_from_sources(s) == null, "an uncovered bible trait text refuses to load")
	t.check(GameData.last_report.has_rule("V-CMP-03"), "V-CMP-03")
	var s2: DefSources = DefTestKit.stub_sources(true)
	((s2.balance["faction_traits.json"] as Dictionary)["factions"] as Dictionary)["faction.napc"]["traits"]["trait.napc.strengths"]["covers"] = [0, 2]
	t.check(GameData.load_from_sources(s2) == null, "double coverage refuses to load")
	t.check(GameData.last_report.has_rule("V-CMP-03"), "V-CMP-03 (twice)")
	var s3: DefSources = DefTestKit.stub_sources(true)
	((s3.balance["research_effects.json"] as Dictionary)["research"] as Dictionary).erase("research.ae.circular_armor")
	t.check(GameData.load_from_sources(s3) == null, "a research without effects refuses to load")
	t.check(GameData.last_report.has_rule("V-CMP-03"), "V-CMP-03 (research)")


func test_no_float_reaches_a_def(t: TestCtx) -> void:
	DefHash.float_hits = 0
	var d: GameData = GameData.load_from_sources(DefTestKit.stub_sources(true))
	if not t.not_null(d, "load"):
		return
	t.eq(DefHash.float_hits, 0, "V-DET-01: no float in any hashed def (converted params, effects, packets, rosters)")
	t.check(DefValidator.check_frozen(d), "re-hash equals the stored data_hash")
