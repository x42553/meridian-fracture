extends RefCounted
## DATA-07: DefLayer3 (data_balance 3.7 / 5.8 / 10.1 "layer 3"): permanent research accumulators, stack groups,
## parameter mods, flags, grants, conditional effects, checksum.

const K := DefEnums.Kind
const S := DefEnums.Stat
const AK := DefEnums.AbilityKind

static var _real: GameData = null


static func real() -> GameData:
	if _real == null:
		_real = DefTestKit.stub_game_data(true)
	return _real


static func hu(n: int, d: int) -> int:
	return (2 * n + d) / (2 * d)


func _l3(d: GameData, roster: String, sub: String = "") -> DefLayer3:
	return DefLayer3.new(d, d.roster_for(roster, sub))


func test_circular_armor_health(t: TestCtx) -> void:
	var d: GameData = real()
	if not t.not_null(d, "load: " + GameData.last_report.text(6)):
		return
	var l3: DefLayer3 = _l3(d, "ae")
	var buffalo: int = d.unit_idx("unit.ae.buffalo_tank")
	var r: int = d.research_idx("research.ae.circular_armor")
	t.eq(l3.version, 0, "fresh")
	t.check(not l3.is_done(r), "not done")
	l3.apply_research(r)
	t.eq(l3.version, 1, "version incremented")
	t.check(l3.is_done(r), "done")
	t.eq(l3.completed, PackedInt32Array([r]), "completion order")
	t.eq(l3.unit_stat_bp(S.HEALTH, buffalo), 1000, "+10 % health")
	var base: int = l3.roster.unit(buffalo).health
	t.eq(l3.effective_unit_stat(S.HEALTH, buffalo), hu(base * 11000, 10000), "effective health = apply_bp(resolved, +1000)")
	t.eq(l3.effective_unit_stat(S.HEALTH, buffalo, 1500), hu(base * 12500, 10000), "temporary deltas ADD to research in the same layer")
	t.eq(l3.unit_stat_bp(S.COST, buffalo), 0, "other stats untouched")
	t.eq(l3.unit_stat_bp(S.HEALTH, d.unit_idx("unit.ae.union_guard")), 0, "infantry untouched")
	# a second call is a no-op + push_error
	t.expect_errors(1)
	l3.apply_research(r)
	t.eq(l3.version, 1, "no version change")
	t.eq(l3.completed.size(), 1, "no double completion")
	t.eq(l3.unit_stat_bp(S.HEALTH, buffalo), 1000, "no double delta")


func test_resistance_groups(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var l3: DefLayer3 = _l3(d, "napc")
	var g: int = d.unit_idx("unit.napc.guardian_tank")
	l3.apply_research(d.research_idx("research.napc.adaptive_plating"))
	var DT := DefEnums.DamageType
	t.eq(l3.unit_resist_bp(DT.AP, g), 1000, "ap carries the explosive group")
	t.eq(l3.unit_resist_bp(DT.HE, g), 1000, "he carries the explosive group")
	t.eq(l3.unit_resist_bp(DT.BULLET, g), 0, "bullet")
	t.eq(l3.unit_resist_bp(DT.THERMAL, g), 0, "thermal (beam|thermal)")
	t.eq(l3.unit_resist_bp(DT.RAIL, g), 0, "rail")
	t.eq(l3.unit_resist_bp(DT.KINETIC, g), 0, "kinetic")
	t.eq(l3.unit_resist_bp(DT.EMP, g), 0, "emp")
	t.eq(l3.unit_resist_bp(DT.AP, d.unit_idx("unit.napc.rifle_squad")), 0, "infantry are not land combat vehicles")
	t.eq(l3.unit_resist_bp(DT.AP, -1), 0, "bad index")
	# group_mask 0 = every weapon group except EMP
	var e: DefEffect = DefEffect.new()
	e.op = DefEnums.EffectOp.RESIST_MOD
	e.delta_bp = 700
	e.selector = d.selector_idx("selector.land_combat_vehicles")
	l3._apply_effect(e)
	for dt: int in DT.COUNT:
		t.eq(l3.unit_resist_bp(dt, g), (1000 if dt == DT.AP or dt == DT.HE else 0) + (0 if dt == DT.EMP else 700), "default groups, damage type %d" % dt)


func test_param_mods_and_grants(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var sap: DefLayer3 = _l3(d, "sap", "india")
	var arjun: int = d.unit_idx("unit.sap.arjun_assault_tank")
	var gaj: int = d.unit_idx("unit.sap.gaj_siege_platform")
	t.eq(sap.ability_param(arjun, AK.INTERCEPTOR, "cooldown_t", 300), 300, "before")
	sap.apply_research(d.research_idx("research.sap.integrated_protection"))
	t.eq(sap.ability_param(arjun, AK.INTERCEPTOR, "cooldown_t", 300), 200, "15 s -> 10 s")
	t.eq(sap.ability_param(gaj, AK.INTERCEPTOR, "cooldown_t", 300), 300, "the Gaj only gains the ability")
	var granted: Array[DefAbility] = sap.granted_abilities(gaj)
	t.eq(granted.size(), 1, "granted")
	t.eq(granted[0].kind, AK.INTERCEPTOR, "interceptor")
	t.eq(granted[0].params["cooldown_t"], 200, "with the grant's own cooldown")
	t.check(granted[0] != d.research[d.research_idx("research.sap.integrated_protection")].effects[1].ability, "runtime copy, not the def's object")
	t.eq(sap.granted_abilities(arjun).size(), 0, "the Arjun already has an interceptor (skipped)")
	# replacement inherits: Fen replaces the Surveyor APC in the Nordics
	var nord: DefLayer3 = _l3(d, "nec", "nordics")
	var fen: int = d.unit_idx("unit.nec.fen_recon_carrier")
	nord.apply_research(d.research_idx("research.nec.sensor_fusion"))
	t.eq(nord.ability_param(fen, AK.DETECTOR, "radius_u", 5120), 7168, "+2 cells through include_replacements")
	t.eq(_l3(d, "nec", "nordics").ability_param(fen, AK.DETECTOR, "radius_u", 5120), 5120, "another layer 3 is independent")
	# set -> add -> mul_bp, several factors multiply, in completion order
	var l3: DefLayer3 = _l3(d, "napc")
	var g: int = d.unit_idx("unit.napc.guardian_tank")
	var sel: int = d.selector_idx("selector.land_combat_vehicles")
	for spec: Array in [[DefEnums.ParamOp.MUL_BP, 12500], [DefEnums.ParamOp.ADD, 10], [DefEnums.ParamOp.SET, 50], [DefEnums.ParamOp.SET, 60], [DefEnums.ParamOp.MUL_BP, 8000]]:
		var e: DefEffect = DefEffect.new()
		e.op = DefEnums.EffectOp.PARAM_MOD
		e.scope = DefEnums.ParamScope.ABILITY
		e.ability_kind = AK.DEPLOY
		e.key = "x_t"
		e.param_op = spec[0]
		e.value = spec[1]
		e.selector = sel
		l3._apply_effect(e)
	# set 60 (last wins) -> add 10 = 70 -> x1.25 = 87.5 -> x0.8 = 70 (each factor rounds half-up)
	t.eq(l3.ability_param(g, AK.DEPLOY, "x_t", 999), 70, "order: sets, adds, factors")
	t.eq(l3.ability_param(g, AK.DEPLOY, "y_t", 5), 5, "other keys untouched")
	t.eq(l3.ability_param(d.unit_idx("unit.napc.rifle_squad"), AK.DEPLOY, "x_t", 5), 5, "non-matching def untouched")
	t.eq(l3.param_effects_for(g, AK.DEPLOY, "x_t").size(), 5, "effects exposed for filter evaluation")
	# structure ability params and def-scope params
	var nec: DefLayer3 = _l3(d, "nec")
	nec.apply_research(d.research_idx("research.nec.distributed_control"))
	var relay: int = d.structure_idx("structure.nec.relay")
	t.eq(nec.struct_ability_param(relay, AK.RELAY_FIELD, "radius_u", 6144), 8192, "relay radius 6 -> 8 cells")
	t.eq(nec.struct_ability_param(relay, AK.RELAY_FIELD, "retain_after_power_loss_t", 0), 200, "10 s")
	var napc: DefLayer3 = _l3(d, "napc")
	napc.apply_research(d.research_idx("research.napc.dispersed_runways"))
	t.eq(napc.struct_ability_param(d.structure_idx("structure.shared.airfield"), AK.SERVICE_PADS, "pads_n", 4), 6, "+2 pads")
	var def: DefLayer3 = _l3(d, "def")
	def.apply_research(d.research_idx("research.def.buried_command_lines"))
	t.eq(def.struct_def_param(d.structure_idx("structure.shared.radar"), "emp_recovery_bp", 10000), 7500, "radar recovers 25 % faster")
	t.eq(def.struct_def_param(d.structure_idx("structure.shared.watchtower"), "emp_recovery_bp", 10000), 7500, "defensive structures too")
	t.eq(def.struct_def_param(d.structure_idx("structure.shared.factory"), "emp_recovery_bp", 10000), 10000, "other structures untouched")
	# player scope
	var sp: DefLayer3 = _l3(d, "sap")
	sp.apply_research(d.research_idx("research.sap.reserve_capacitors"))
	t.eq(sp.player_param("reserve_t", 400), 700, "reserve 20 -> 35 s")
	t.eq(sp.player_param("defense_power_reserve.reserve_t", 400), 700, "kind-qualified key")
	t.eq(sp.player_param("recharge_t", 1200), 1200, "other keys untouched")
	# flags
	var han: DefLayer3 = _l3(d, "han", "china")
	var igt: int = d.unit_idx("unit.han.imperial_guard_tank")
	t.check(not han.has_flag(igt, "command_field_eligible"), "before")
	han.apply_research(d.research_idx("research.han.guard_integration"))
	t.check(han.has_flag(igt, "command_field_eligible"), "flag set")
	t.check(not han.has_flag(d.unit_idx("unit.han.link_operator"), "command_field_eligible"), "only the named unit")


func test_conditional_effects_stay_out_of_the_sums(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var l3: DefLayer3 = _l3(d, "napc")
	var sentinel: int = d.unit_idx("unit.napc.sentinel_aa")
	l3.apply_research(d.research_idx("research.napc.joint_tactical_links"))
	t.eq(l3.cond_effects_of_unit(sentinel).size(), 1, "exposed as a conditional effect")
	t.eq(l3.unit_stat_bp(S.RANGE, sentinel), 0, "and not summed")
	t.eq(l3.cond_effects_of_unit(sentinel)[0].cond_codes, PackedInt32Array([DefEnums.Cond.NEAR_FRIENDLY_UNIT]), "cond codes for the abilities domain")
	t.eq(l3.cond_effects_of_unit(d.unit_idx("unit.napc.guardian_tank")).size(), 0, "other defs")
	t.eq(l3.cond_effects_of_struct(0).size(), 0, "no structure effects")
	# on_water resistance and the fire-mode / arc filters are conditional too
	var sc: DefLayer3 = _l3(d, "napc", "canada")
	sc.apply_research(d.research_idx("research.napc.sealed_compartments"))
	var narwhal: int = d.unit_idx("unit.napc.narwhal_amphibious_tank")
	t.eq(sc.cond_effects_of_unit(narwhal).size(), 1, "sealed compartments")
	t.eq(sc.unit_resist_bp(DefEnums.DamageType.AP, narwhal), 0, "not a static resistance")
	var e: DefEffect = DefEffect.new()
	e.op = DefEnums.EffectOp.RESIST_MOD
	e.delta_bp = 2500
	e.group_mask = 1
	e.frontal_arc_a = 2048
	e.selector = d.selector_idx("selector.land_combat_vehicles")
	sc._apply_effect(e)
	t.eq(sc.unit_resist_bp(DefEnums.DamageType.BULLET, narwhal), 0, "frontal arc makes it conditional")
	t.eq(sc.cond_effects_of_unit(narwhal).size(), 2, "kept in cond_effects")


func test_stack_groups(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var l3: DefLayer3 = _l3(d, "napc")
	var g: int = d.unit_idx("unit.napc.guardian_tank")
	var sel: int = d.selector_idx("selector.land_combat_vehicles")
	var grp: int = d.stack_groups.find("relay_field")
	t.check(grp >= 0, "a registered group")
	# two overlapping relays = one +10 %; Treaty Coordination raises the group's value to +15 % instead of adding
	for delta_bp: int in [1000, 1000, 1500, 1200]:
		var e: DefEffect = DefEffect.new()
		e.op = DefEnums.EffectOp.STAT_MOD
		e.stat = S.DAMAGE
		e.delta_bp = delta_bp
		e.selector = sel
		e.stack_group = grp
		l3._apply_effect(e)
	t.eq(l3.unit_stat_bp(S.DAMAGE, g), 1500, "the larger |delta| wins within a group, equal or smaller ones are ignored")
	# a different group and an ungrouped effect ADD (same layer)
	var e2: DefEffect = DefEffect.new()
	e2.op = DefEnums.EffectOp.STAT_MOD
	e2.stat = S.DAMAGE
	e2.delta_bp = 1000
	e2.selector = sel
	e2.stack_group = d.stack_groups.find("command_field")
	l3._apply_effect(e2)
	var e3: DefEffect = DefEffect.new()
	e3.op = DefEnums.EffectOp.STAT_MOD
	e3.stat = S.DAMAGE
	e3.delta_bp = 500
	e3.selector = sel
	l3._apply_effect(e3)
	t.eq(l3.unit_stat_bp(S.DAMAGE, g), 3000, "1500 + 1000 + 500")
	t.eq(DefStatMath.apply_bp(140, 1000 + 1000), 168, "140 with Relay + Combined Arms Window = 168 (adds, does not multiply)")
	# ties keep the earlier source
	var l3b: DefLayer3 = _l3(d, "napc")
	for v: int in [-1000, 1000]:
		var e4: DefEffect = DefEffect.new()
		e4.op = DefEnums.EffectOp.STAT_MOD
		e4.stat = S.SPEED
		e4.delta_bp = v
		e4.selector = sel
		e4.stack_group = grp
		l3b._apply_effect(e4)
	t.eq(l3b.unit_stat_bp(S.SPEED, g), -1000, "tie: the earlier -1000 stays")


func test_unconditional_repair_cost_research(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var l3: DefLayer3 = _l3(d, "def")
	l3.apply_research(d.research_idx("research.def.standardized_parts"))
	var tank: int = d.unit_idx("unit.def.hammer_tank")
	t.eq(l3.unit_stat_bp(S.REPAIR_COST, tank), -1500, "-15 % repair cost")
	t.eq(l3.effective_unit_stat(S.REPAIR_COST, tank), 4250, "5000 bp -> 4250 bp")
	t.eq(l3.effective_unit_stat(S.REPAIR_COST, d.unit_idx("unit.shared.collector")), 4250, "service land vehicles too (selector without the combat tag)")


func test_checksum(t: TestCtx) -> void:
	var d: GameData = real()
	if d == null:
		t.fail("no data")
		return
	var a: DefLayer3 = _l3(d, "napc")
	var b: DefLayer3 = _l3(d, "napc")
	t.eq(a.checksum(), b.checksum(), "fresh layers agree")
	var seen: Dictionary = {a.checksum(): true}
	for id: String in ["research.napc.adaptive_plating", "research.napc.joint_tactical_links", "research.napc.dispersed_runways"]:
		a.apply_research(d.research_idx(id))
		var c: int = a.checksum()
		t.check(not seen.has(c), "checksum changes with %s" % id)
		seen[c] = true
	for id2: String in ["research.napc.adaptive_plating", "research.napc.joint_tactical_links", "research.napc.dispersed_runways"]:
		b.apply_research(d.research_idx(id2))
	t.eq(a.checksum(), b.checksum(), "identical sequences give identical checksums")
	var c2: DefLayer3 = _l3(d, "napc")
	c2.apply_research(d.research_idx("research.napc.dispersed_runways"))
	c2.apply_research(d.research_idx("research.napc.adaptive_plating"))
	c2.apply_research(d.research_idx("research.napc.joint_tactical_links"))
	t.ne(c2.checksum(), a.checksum(), "completion order is part of the state")
