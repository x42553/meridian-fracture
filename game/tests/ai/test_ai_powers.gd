extends RefCounted
## AIX2 (ai.md 5.12 / 10.1 test_ai_powers): the 48 support-power heuristics. Table integrity against the resolved data, the
## archetype evaluators on synthetic snapshots (a positive and a negative case for every evaluator family, including the worked
## examples of the spec) and the decision loop on a live sim world (a damaged group is repaired by the AI's power).

const C: int = Fp.CELL
const A := preload("res://tests/support/ab2_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")


func _ctx(tick: int = 5000) -> AiContext:
	var v: AiMockWorldView = AiMockWorldView.new(0)
	v.add_player(0, "roster.napc.vanilla", Vector2i(15, 15))
	v.add_player(1, "roster.nec.vanilla", Vector2i(80, 80))
	v.mock_tick = tick
	var ctx: AiContext = AiMockWorldView.make_ctx(v)
	ctx.tick = tick
	return ctx


func _arch(ctx: AiContext) -> AiPowerArch:
	var a: AiPowerArch = AiPowerArch.new()
	a.snap_tick = ctx.tick  # the synthetic arrays below replace the snapshot
	a._ctx = ctx
	return a


func _entry(id: String) -> AiPowerArch.Entry:
	var d: GameData = GameData.load_default()
	var idx: int = d.power_idx(id)
	return AiPowers.make_entry(d.powers[idx], idx)


func _unit(a: AiPowerArch, x: int, y: int, v: int, sel: int, miss: int = 0, eng: int = 0, moving: int = 0) -> void:
	a.u_row.append(0)
	a.u_eid.append(100 + a.un)
	a.u_x.append(x)
	a.u_y.append(y)
	a.u_v.append(v)
	a.u_paid.append(v)
	a.u_sel.append(sel)
	a.u_miss.append(miss)
	a.u_flags.append(0)
	a.u_eng.append(eng)
	a.u_move.append(moving)
	a.un += 1


func _foe(a: AiPowerArch, x: int, y: int, v: int, armed: int = 1, stat: int = 1, kind: int = 0, arty: int = 0) -> void:
	a.e_x.append(x)
	a.e_y.append(y)
	a.e_v.append(v)
	a.e_armed.append(armed)
	a.e_stat.append(stat)
	a.e_kind.append(kind)
	a.e_arty.append(arty)
	a.e_row.append(-1)
	a.en += 1


func _budget() -> AiBudget:
	var b: AiBudget = AiBudget.new()
	b.reset(100000, 100000)
	return b


func _need(e: AiPowerArch.Entry, eager_pct: int = 100) -> int:
	return e.cost * e.ratio / 100 * eager_pct / 100


# ------------------------------------------------------------------------------------------------ table integrity
func test_table_covers_all_48_powers_with_matching_actions(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	t.eq(d.powers.size(), 48)
	t.eq(AiPowers.TABLE.size(), 48, "one row per power")
	var op_ok: Dictionary = {
		AiTypes.PowerArch.REVEAL: [DefEnums.PowerOp.ZONE, DefEnums.PowerOp.SUMMON],
		AiTypes.PowerArch.REVEAL_CORRIDOR: [DefEnums.PowerOp.SUMMON],
		AiTypes.PowerArch.STRIKE: [DefEnums.PowerOp.STRIKE],
		AiTypes.PowerArch.MARK: [DefEnums.PowerOp.MARK],
		AiTypes.PowerArch.PRODUCTION: [DefEnums.PowerOp.GLOBAL_EFFECT],
		AiTypes.PowerArch.FIELD_BOOST: [DefEnums.PowerOp.GLOBAL_EFFECT],
		AiTypes.PowerArch.REPAIR_ZONE: [DefEnums.PowerOp.ZONE, DefEnums.PowerOp.SUMMON],
	}
	for i: int in d.powers.size():
		var pd: DefPower = d.powers[i]
		t.check(AiPowers.TABLE.has(pd.id), "row for %s" % pd.id)
		var e: AiPowerArch.Entry = AiPowers.make_entry(pd, i)
		t.check(e != null, "entry for %s" % pd.id)
		if e == null:
			continue
		t.gt(e.cost, 0, "price of %s" % pd.id)
		t.gt(e.radius, 0, "radius of %s" % pd.id)
		if op_ok.has(e.arch):
			for a: DefPowerAction in pd.actions:
				t.check((op_ok[e.arch] as Array).has(a.op), "%s: op %d fits archetype %d" % [pd.id, a.op, e.arch])
	# every roster's three powers have rows
	for r: DefRoster in d.rosters:
		t.eq(r.power_list.size(), 3, r.id)
		for pidx: int in r.power_list:
			t.check(AiPowers.TABLE.has(d.powers[pidx].id), "%s: %s" % [r.id, d.powers[pidx].id])


func test_easy_uses_only_reveal_and_repair(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	for i: int in d.powers.size():
		var e: AiPowerArch.Entry = AiPowers.make_entry(d.powers[i], i)
		var recon_or_repair: bool = e.arch == AiTypes.PowerArch.REVEAL or e.arch == AiTypes.PowerArch.REVEAL_CORRIDOR or e.arch == AiTypes.PowerArch.REPAIR_ZONE
		t.eq(e.min_level <= 1, recon_or_repair, "%s level gate" % e.id)


# ----------------------------------------------------------------------------------------------------- repair zones
func test_field_repair_drop_worked_example(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.napc.field_repair_drop")
	t.eq(e.cost, 900)
	t.eq(e.eff, 51)
	# 6 tanks worth 1000 each at 40 % missing (q8 102): 6 x 1000 x min(51, 102) / 256 = 1195 >= 1080
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	for i: int in 6:
		_unit(a, (30 + i % 3) * C, (30 + i / 3) * C, 1000, AiPowerArch.SEL_VEH, 102)
	t.check(a.evaluate(ctx, e, _budget()), "6 damaged tanks: a repair zone is worth casting")
	t.eq(a.benefit, 6 * (1000 * 51 / 256), "benefit = sum(v x eff / 256)")
	t.ge(a.benefit, _need(e), "1195 >= 1080")
	t.le(absi(a.bx - 31 * C), C, "at the centroid")
	# 5 tanks: 996 < 1080
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 5:
		_unit(b, (30 + i2 % 3) * C, (30 + i2 / 3) * C, 1000, AiPowerArch.SEL_VEH, 102)
	b.evaluate(ctx, e, _budget())
	t.lt(b.benefit, _need(e), "5 tanks: 996 < 1080 => hold")
	# an armed enemy within 12 cells
	var c: AiPowerArch = _arch(ctx)
	for i3: int in 6:
		_unit(c, (30 + i3 % 3) * C, (30 + i3 / 3) * C, 1000, AiPowerArch.SEL_VEH, 102)
	_foe(c, 40 * C, 31 * C, 500)
	t.check(not c.evaluate(ctx, e, _budget()), "enemy within 12 cells => hold")
	# not more than 15 % missing => nothing to repair
	var d: AiPowerArch = _arch(ctx)
	for i4: int in 6:
		_unit(d, (30 + i4 % 3) * C, (30 + i4 / 3) * C, 1000, AiPowerArch.SEL_VEH, 20)
	t.check(not d.evaluate(ctx, e, _budget()), "healthy units")
	# a running repair zone within 10 cells forbids the second one
	var f: AiPowerArch = _arch(ctx)
	for i5: int in 6:
		_unit(f, (30 + i5 % 3) * C, (30 + i5 / 3) * C, 1000, AiPowerArch.SEL_VEH, 102)
	f.repair_zones = PackedInt32Array([33 * C, 31 * C, ctx.tick + 500])
	t.check(not f.evaluate(ctx, e, _budget()), "no stacking within 10 cells")


func test_field_refurbishment_needs_five_vehicles_missing_30(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.ae.field_refurbishment")
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	for i: int in 5:
		_unit(a, (30 + i) * C, 30 * C, 1500, AiPowerArch.SEL_VEH, 100)
	t.check(a.evaluate(ctx, e, _budget()), "5 vehicles missing 39 %")
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 4:
		_unit(b, (30 + i2) * C, 30 * C, 1500, AiPowerArch.SEL_VEH, 100)
	t.check(not b.evaluate(ctx, e, _budget()), "4 vehicles: not enough")
	var c: AiPowerArch = _arch(ctx)
	for i3: int in 5:
		_unit(c, (30 + i3) * C, 30 * C, 1500, AiPowerArch.SEL_VEH, 50)
	t.check(not c.evaluate(ctx, e, _budget()), "missing only 20 %: below 30 %")
	# enemy within 14 cells
	var d: AiPowerArch = _arch(ctx)
	for i4: int in 5:
		_unit(d, (30 + i4) * C, 30 * C, 1500, AiPowerArch.SEL_VEH, 100)
	_foe(d, 45 * C, 30 * C, 400)
	t.check(not d.evaluate(ctx, e, _budget()), "enemy at 14 cells")


func test_floating_workshop_counts_ships(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.napc.floating_workshop")
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	for i: int in 4:
		_unit(a, (30 + i) * C, 30 * C, 1600, AiPowerArch.SEL_SHIP, 120)
	t.check(a.evaluate(ctx, e, _budget()), "four damaged ships")
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 4:
		_unit(b, (30 + i2) * C, 30 * C, 1600, AiPowerArch.SEL_INF, 120)
	t.check(not b.evaluate(ctx, e, _budget()), "infantry is not eligible")


# ------------------------------------------------------------------------------------------------------------ buffs
func test_combined_arms_window_needs_a_big_engaged_group(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.napc.combined_arms_window")
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	for i: int in 10:
		_unit(a, (30 + i % 5) * C, (30 + i / 5) * C, 1800, AiPowerArch.SEL_VEH, 0, 1)
	t.check(a.evaluate(ctx, e, _budget()), "10 engaged units worth 18000")
	t.ge(a.benefit, _need(e), "beyond the price")
	# the same group not engaged
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 10:
		_unit(b, (30 + i2 % 5) * C, (30 + i2 / 5) * C, 1800, AiPowerArch.SEL_VEH, 0, 0)
	t.check(not b.evaluate(ctx, e, _budget()), "not engaged")
	# engaged but cheap: 8 units worth 500
	var c: AiPowerArch = _arch(ctx)
	for i3: int in 8:
		_unit(c, (30 + i3) * C, 30 * C, 500, AiPowerArch.SEL_INF, 0, 1)
	c.evaluate(ctx, e, _budget())
	t.lt(c.benefit, _need(e), "V 4000 x 7.6 % = 305 < 1080")
	# ships are not eligible for the Combined Arms Window
	var d: AiPowerArch = _arch(ctx)
	for i4: int in 10:
		_unit(d, (30 + i4) * C, 30 * C, 1800, AiPowerArch.SEL_SHIP, 0, 1)
	t.check(not d.evaluate(ctx, e, _budget()), "ships excluded")


func test_precision_window_and_assault_coordination_selectors(t: TestCtx) -> void:
	var ctx: AiContext = _ctx()
	var pw: AiPowerArch.Entry = _entry("power.pd.precision_window")
	var a: AiPowerArch = _arch(ctx)
	for i: int in 5:
		_unit(a, (30 + i) * C, 30 * C, 2500, AiPowerArch.SEL_AIR, 0, 1)
	t.check(a.evaluate(ctx, pw, _budget()), "5 engaged aircraft")
	t.ge(a.benefit, _need(pw))
	var ac: AiPowerArch.Entry = _entry("power.sap.assault_coordination")
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 5:
		_unit(b, (30 + i2) * C, 30 * C, 2000, AiPowerArch.SEL_VEH | AiPowerArch.SEL_TANK, 0, 1)
	t.check(b.evaluate(ctx, ac, _budget()), "5 engaged tanks")
	var c: AiPowerArch = _arch(ctx)
	for i3: int in 5:
		_unit(c, (30 + i3) * C, 30 * C, 2000, AiPowerArch.SEL_VEH, 0, 1)
	t.check(not c.evaluate(ctx, ac, _budget()), "vehicles that are not tanks")


func test_armored_overwatch_needs_stationary_tanks_and_an_enemy(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.nec.armored_overwatch")
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	for i: int in 6:
		_unit(a, (30 + i) * C, 30 * C, 2500, AiPowerArch.SEL_VEH | AiPowerArch.SEL_TANK, 0, 1, 0)
	_foe(a, 45 * C, 30 * C, 900)
	t.check(a.evaluate(ctx, e, _budget()), "stationary tanks with an enemy in range")
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 6:
		_unit(b, (30 + i2) * C, 30 * C, 2500, AiPowerArch.SEL_VEH | AiPowerArch.SEL_TANK, 0, 1, 1)
	_foe(b, 45 * C, 30 * C, 900)
	t.check(not b.evaluate(ctx, e, _budget()), "moving tanks")


func test_steel_advance_holds_when_the_enemy_is_pursued_by_a_small_force(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.def.steel_advance")
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	for i: int in 8:
		_unit(a, (30 + i % 4) * C, (30 + i / 4) * C, 2200, AiPowerArch.SEL_VEH, 0, 1)
	_foe(a, 33 * C, 34 * C, 1200)
	t.check(not a.evaluate(ctx, e, _budget()), "pursuing a weak enemy: never")
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 8:
		_unit(b, (30 + i2 % 4) * C, (30 + i2 / 4) * C, 2200, AiPowerArch.SEL_VEH, 0, 1)
	for k: int in 6:
		_foe(b, (44 + k) * C, 31 * C, 2000)
	t.check(b.evaluate(ctx, e, _budget()), "about to fight a strong defense")


func test_finisher_never_opens_a_fight(t: TestCtx) -> void:
	# Capacitor Discharge: needs the enemy hp inside the window; no enemy rows with profiles in the synthetic set => refuse
	var e: AiPowerArch.Entry = _entry("power.olm.capacitor_discharge")
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	for i: int in 5:
		_unit(a, (30 + i) * C, 30 * C, 2600, AiPowerArch.SEL_VEH, 0, 0)
	t.check(not a.evaluate(ctx, e, _budget()), "nobody engaged: never opens a fight")


# ---------------------------------------------------------------------------------------------------------- strikes
func test_tremor_barrage_on_stationary_artillery(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.def.tremor_barrage")
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	for i: int in 5:
		_foe(a, (50 + i % 3) * C, (50 + i / 3) * C, 1800, 1, 1, 0, 1)
	t.check(a.evaluate(ctx, e, _budget()), "five stationary artillery pieces")
	t.ge(a.benefit, _need(e), "5 x 1800 x 0.59 = 5300 >= 1560")
	# the same group on the move counts a quarter
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 5:
		_foe(b, (50 + i2 % 3) * C, (50 + i2 / 3) * C, 1800, 1, 0, 0, 1)
	b.evaluate(ctx, e, _budget())
	t.lt(b.benefit, a.benefit / 3, "moving targets count w = 64 / 256")
	# my own units inside the circle: friendly fire forbids it
	var c: AiPowerArch = _arch(ctx)
	for i3: int in 5:
		_foe(c, (50 + i3 % 3) * C, (50 + i3 / 3) * C, 1800, 1, 1, 0, 1)
	for k: int in 4:
		_unit(c, 51 * C + k * C / 2, 50 * C, 3000, AiPowerArch.SEL_VEH)
	t.check(not c.evaluate(ctx, e, _budget()), "own value inside the circle")


func test_counterlaunch_needs_a_value_of_1500(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.sap.counterlaunch_plot")
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	# no artillery has fired (the synthetic rows have no entity table row) => hold
	_foe(a, 50 * C, 50 * C, 2500, 1, 1, 0, 1)
	t.check(not a.evaluate(ctx, e, _budget()), "nothing fired recently: hold")


# ------------------------------------------------------------------------------------------------------- smoke, guard
func test_dust_screen_two_sided_gate(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.olm.dust_screen")
	var ctx: AiContext = _ctx()
	ctx.view = AiMockWorldView.new(0)
	# my ground group taking fire from outside the smoke
	var a: AiPowerArch = _arch(ctx)
	var t_own: AiEntityTable = ctx.kb.own
	for i: int in 6:
		var r: int = t_own.upsert(500 + i)
		t_own.last_dmg[r] = ctx.tick - 20
		t_own.hp[r] = 50
		t_own.hp_max[r] = 100
		_unit(a, (30 + i) * C, 30 * C, 1500, AiPowerArch.SEL_VEH, 128)
		a.u_row[a.un - 1] = r
	_foe(a, 50 * C, 30 * C, 4000)
	t.check(a.evaluate(ctx, e, _budget()), "under fire from outside the circle")
	# the enemy is inside the circle: the smoke would protect it too
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 6:
		var r2: int = t_own.row(500 + i2)
		_unit(b, (30 + i2) * C, 30 * C, 1500, AiPowerArch.SEL_VEH, 128)
		b.u_row[b.un - 1] = r2
	_foe(b, 32 * C, 30 * C, 4000)
	t.check(not b.evaluate(ctx, e, _budget()), "enemy direct-fire value inside > 30 % of mine")


func test_emergency_fortification_needs_a_base_under_attack(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.sap.emergency_fortification")
	var ctx: AiContext = _ctx()
	var a: AiPowerArch = _arch(ctx)
	for i: int in 5:
		a.s_x.append((20 + i) * C)
		a.s_y.append(20 * C)
		a.s_v.append(1500)
		a.s_kind.append(AiTypes.StructKind.AT_TURRET)
		a.s_flags.append(0)
		a.s_eid.append(900 + i)
		a.sn += 1
	t.check(not a.evaluate(ctx, e, _budget()), "no attackers")
	for k: int in 7:
		_foe(a, (26 + k % 3) * C, (24 + k / 3) * C, 600)
	t.check(a.evaluate(ctx, e, _budget()), "seven armed enemies at the defenses")
	t.ge(a.benefit, _need(e), "7500 x 25 % x 0.75 = 1400 >= 900 x 1.2")


# ---------------------------------------------------------------------------------------------------------- anti EMP
func test_redundant_orders_needs_a_trapped_group_at_impact_minus_30(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.def.redundant_orders")
	var ctx: AiContext = _ctx(6000)
	var a: AiPowerArch = _arch(ctx)
	t.check(not a.evaluate(ctx, e, _budget()), "no Aurora warning: never")
	a.trapped = PackedInt32Array([40 * C, 40 * C, 4, ctx.tick + 30])
	t.check(not a.evaluate(ctx, e, _budget()), "only 4 vehicles trapped")
	a.trapped = PackedInt32Array([40 * C, 40 * C, 7, ctx.tick + 120])
	t.check(not a.evaluate(ctx, e, _budget()), "too early")
	a.trapped = PackedInt32Array([40 * C, 40 * C, 7, ctx.tick + 28])
	t.check(a.evaluate(ctx, e, _budget()), "7 vehicles, 28 ticks before impact")
	t.eq(a.bx, 40 * C)


# ------------------------------------------------------------------------------------------------------------ reveal
func test_uav_sweep_scouts_a_stale_base(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.napc.uav_sweep")
	var ctx: AiContext = _ctx(6000)
	var kb: AiKnowledge = ctx.kb
	kb.enemy_pids = PackedInt32Array([1])
	# the presumed HQ (synthetic eid < 0) of the enemy is never scouted, the match is past 240 s
	kb.ghosts.upsert(-2, 0, 1, 80 * C, 80 * C, 0, 100, 0, AiTypes.StructKind.HQ, 3000)
	var a: AiPowerArch = _arch(ctx)
	t.check(a.evaluate(ctx, e, _budget()), "unscouted enemy base")
	t.eq(a.benefit, 100 * e.cost / 60, "info 100 => benefit 833")
	t.ge(a.benefit, _need(e, 125), "beyond the Medium threshold")
	t.eq(a.bx, 80 * C)
	# never twice on the same cell within 6000 ticks
	a.note_cast(e, a.bx, a.by, ctx.tick - 100)
	var b: AiPowerArch = _arch(ctx)
	b.reveal_hist = a.reveal_hist
	t.check(not b.evaluate(ctx, e, _budget()), "the same cell was revealed 100 ticks ago")
	# a base seen a moment ago is not stale
	var ctx2: AiContext = _ctx(6000)
	ctx2.kb.enemy_pids = PackedInt32Array([1])
	ctx2.kb.ghosts.upsert(77, 0, 1, 80 * C, 80 * C, 5900, 100, 0, AiTypes.StructKind.HQ, 3000)
	var c: AiPowerArch = _arch(ctx2)
	t.check(not c.evaluate(ctx2, e, _budget()), "fresh sighting")


func test_wideband_scan_detection_mode_needs_a_camo_alert(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.han.wideband_scan")
	var ctx: AiContext = _ctx(6000)
	ctx.kb.enemy_pids = PackedInt32Array([1])
	ctx.kb.ghosts.upsert(77, 0, 1, 80 * C, 80 * C, 1000, 100, 0, AiTypes.StructKind.HQ, 3000)
	var a: AiPowerArch = _arch(ctx)
	t.check(not a.evaluate(ctx, e, _budget()), "a scouted base and no camo alert: nothing to scan")
	ctx.kb.camo[0] = 40 * C
	ctx.kb.camo[1] = 41 * C
	ctx.kb.camo[2] = ctx.tick - 100
	var b: AiPowerArch = _arch(ctx)
	t.check(b.evaluate(ctx, e, _budget()), "camouflage alert")
	t.eq(b.bx, 40 * C)


func test_maritime_patrol_corridor_follows_the_route(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.pd.maritime_patrol")
	var ctx: AiContext = _ctx(6000)
	ctx.kb.primary = 1
	var a: AiPowerArch = _arch(ctx)
	t.check(a.evaluate(ctx, e, _budget()))
	t.gt(a.bx, 30 * C, "midpoint of the route between (15, 15) and (80, 80)")
	t.check(absi(a.bangle - 512) <= 8, "bearing 45 degrees = binary angle 512")
	ctx.tick = 100
	var b: AiPowerArch = _arch(ctx)
	t.check(not b.evaluate(ctx, e, _budget()), "too early")


# -------------------------------------------------------------------------------------------- live decision loop
func _live_world() -> SimWorld:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false, "fog": false})
	S.base(w, 0, 10, 10, false)
	S.base(w, 1, 44, 44, false)
	return w


func _attach(level: int) -> Dictionary:
	var factory: AiFactory = AiFactory.new()
	var think: Callable = factory.make(0, level, 0, 4242)
	return {"factory": factory, "think": think}


func _drive(w: SimWorld, h: Dictionary, ticks: int) -> void:
	for _i: int in ticks:
		if w.tick % 2 == 0:
			var out: Array = []
			(h["think"] as Callable).call(w, out)
			for c: Variant in out:
				w.submit_raw(0, c)
		w.step()


func test_live_hard_ai_repairs_a_damaged_group_with_field_repair_drop(t: TestCtx) -> void:
	var w: SimWorld = _live_world()
	var h: Dictionary = _attach(AiTypes.Difficulty.HARD)
	var tanks: Array[SimEntity] = []
	for i: int in 7:
		var e: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 20 + i % 4, 24 + i / 4)
		tanks.append(e)
	for e2: SimEntity in tanks:
		e2.hp = e2.hp / 3
	A.hold_fire(w)
	var pidx: int = S.power_idx(w, "power.napc.field_repair_drop")
	var before: int = 0
	for e3: SimEntity in tanks:
		before += e3.hp
	_drive(w, h, 1600)
	var after: int = 0
	for e4: SimEntity in tanks:
		after += e4.hp
	var c: AiController = (h["factory"] as AiFactory).thinker(0).controller
	var brain: AiBrain = c.ctx.brain as AiBrain
	t.check(brain != null and brain.powers != null, "the brain carries the power module")
	t.eq(brain.powers.entries.size(), 3, "three powers in the roster")
	t.gt(brain.powers.casts, 0, "at least one power was cast")
	var e_frd: AiPowerArch.Entry = brain.powers.entry_of("power.napc.field_repair_drop")
	t.gt(e_frd.casts, 0, "Field Repair Drop cast on the damaged group")
	t.gt(after, before, "the group healed (%d -> %d hp)" % [before, after])
	t.gt(w.players[0].econ.slots[1].ready_tick, 0, "the power went on cooldown")
	t.eq(pidx >= 0, true)


func test_live_uav_sweep_reveals_the_unscouted_enemy_base(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": true, "fog": true})
	S.base(w, 0, 10, 10, false)
	S.base(w, 1, 44, 44, false)
	var h: Dictionary = _attach(AiTypes.Difficulty.HARD)
	var visible_before: int = _visible_cells(w, 0, 44, 44, 7)
	var c: AiController = (h["factory"] as AiFactory).thinker(0).controller
	_drive(w, h, 2)
	# the test map has no start positions, so no presumed enemy HQ was seeded: the base is unscouted knowledge
	c.ctx.kb.ghosts.upsert(-2, 0, 1, 44 * Fp.CELL + Fp.CELL / 2, 44 * Fp.CELL + Fp.CELL / 2, 0, 100, 0, AiTypes.StructKind.HQ, 3000)
	_drive(w, h, 5400)
	var brain: AiBrain = c.ctx.brain as AiBrain
	var uav: AiPowerArch.Entry = brain.powers.entry_of("power.napc.uav_sweep")
	t.ge(uav.casts, 1, "the UAV Sweep was cast at the unscouted base")
	t.eq(uav.why_hist.get("nothing to reveal", 0) >= 0, true)
	var seen: bool = false
	for rec: PackedInt32Array in brain.powers.cast_log:
		if rec[1] == uav.pidx:
			t.le(Fp.dist(rec[2] - (44 * Fp.CELL + Fp.CELL / 2), rec[3] - (44 * Fp.CELL + Fp.CELL / 2)) / Fp.CELL, 10, "aimed at the enemy start")
			seen = true
	t.check(seen, "cast logged")
	t.eq(visible_before, 0, "nothing was visible there before")
	t.gt(w.strategic.stat_activations, 0, "the sim accepted the command")


func _visible_cells(w: SimWorld, pid: int, cx: int, cy: int, r: int) -> int:
	var n: int = 0
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r and w.cell_visible(pid, cx + dx, cy + dy):
				n += 1
	return n


func _det_run() -> Array:
	var m: Dictionary = AiSoakKit.make({"seed": 3, "rosters": PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), "levels": [2, 2], "family": 0,
		"fog": true, "credits": 15000, "ai_seed": 777, "pers_over": {0: {"sw_priority": 100}, 1: {"sw_priority": 100}}})
	var w: SimWorld = m["world"]
	while w.tick < 6500:
		AiSoakKit.step_once(m)
	var casts: int = 0
	for pid: int in m["brains"]:
		casts += (m["brains"][pid] as AiBrain).powers.casts
	return [w.checksum(), (m["factory"] as AiFactory).state_hash(), casts, (m["errors"] as PackedStringArray).size()]


func test_determinism_double_run(t: TestCtx) -> void:
	var a: Array = _det_run()
	var b: Array = _det_run()
	t.eq(a, b, "the same match twice: world checksum, AI state hash, cast count, error count")
	t.eq(a[3], 0, "no engine errors")
	t.gt(a[2], 0, "the AIs cast powers in the window (the hash covers them)")


# -------------------------------------------------------------------------------------- marks and field boosts
func _enemy_row(ctx: AiContext, eid: int, role: int, cx: int, cy: int, stat: bool = true) -> int:
	var et: AiEntityTable = ctx.kb.enemy_units
	var r: int = et.upsert(eid)
	et.def[r] = _enemy_res(ctx).first(role)
	et.owner[r] = 1
	et.kind[r] = AiTypes.KIND_UNIT
	et.x[r] = cx * C
	et.y[r] = cy * C
	et.hp[r] = 100
	et.hp_max[r] = 100
	et.paid[r] = 1200
	et.last_seen[r] = ctx.tick
	et.last_moved[r] = 0 if stat else ctx.tick
	return r


func _enemy_res(ctx: AiContext) -> AiRoleResolver:
	return ctx.shared.resolver(ctx.view.roster_of(1))


func test_counterbattery_solution_marks_artillery_that_fired(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.ae.counterbattery_solution")
	var ctx: AiContext = _ctx(9000)
	var mock: AiMockWorldView = ctx.view as AiMockWorldView
	var a: AiPowerArch = _arch(ctx)
	var r1: int = _enemy_row(ctx, 8001, AiTypes.R_ARTILLERY, 50, 50)
	var r2: int = _enemy_row(ctx, 8002, AiTypes.R_ARTILLERY, 52, 50)
	for r: int in [r1, r2]:
		a.e_x.append(ctx.kb.enemy_units.x[r])
		a.e_y.append(ctx.kb.enemy_units.y[r])
		a.e_v.append(1200)
		a.e_armed.append(1)
		a.e_stat.append(1)
		a.e_kind.append(AiPowerArch.KIND_UNIT_ITEM)
		a.e_arty.append(1)
		a.e_row.append(r)
		a.en += 1
	for i: int in 6:
		_unit(a, (44 + i) * C, 50 * C, 2000, AiPowerArch.SEL_VEH, 0, 1)
	mock.last_fire[8001] = ctx.tick - 60
	t.check(not a.evaluate(ctx, e, _budget()), "one piece fired: two are needed")
	mock.last_fire[8002] = ctx.tick - 100
	t.check(a.evaluate(ctx, e, _budget()), "two pieces fired within 8 s")
	t.eq(a.benefit, 6 * 2000 * 15 / 100 * 12 / 20, "0.15 x V(engaged) x 12 / 20")
	t.le(absi(a.bx - 51 * C), C, "centred on the artillery")
	mock.last_fire[8001] = ctx.tick - 400
	mock.last_fire[8002] = ctx.tick - 400
	t.check(not a.evaluate(ctx, e, _budget()), "shots older than 8 s do not count")


func test_counterlaunch_plot_targets_stationary_artillery(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.sap.counterlaunch_plot")
	var ctx: AiContext = _ctx(9000)
	var mock: AiMockWorldView = ctx.view as AiMockWorldView
	var a: AiPowerArch = _arch(ctx)
	var rows: PackedInt32Array = PackedInt32Array()
	for i: int in 3:
		rows.append(_enemy_row(ctx, 8100 + i, AiTypes.R_ARTILLERY, 50 + i, 50))
		mock.last_fire[8100 + i] = ctx.tick - 80
	for r: int in rows:
		a.e_x.append(ctx.kb.enemy_units.x[r])
		a.e_y.append(ctx.kb.enemy_units.y[r])
		a.e_v.append(1200)
		a.e_armed.append(1)
		a.e_stat.append(1)
		a.e_kind.append(AiPowerArch.KIND_UNIT_ITEM)
		a.e_arty.append(1)
		a.e_row.append(r)
		a.en += 1
	t.check(a.evaluate(ctx, e, _budget()), "3600 of stationary artillery that fired")
	t.ge(a.benefit, _need(e))
	var b: AiPowerArch = _arch(ctx)
	for r2: int in rows:
		b.e_x.append(ctx.kb.enemy_units.x[r2])
		b.e_y.append(ctx.kb.enemy_units.y[r2])
		b.e_v.append(1200)
		b.e_armed.append(1)
		b.e_stat.append(0)
		b.e_kind.append(AiPowerArch.KIND_UNIT_ITEM)
		b.e_arty.append(1)
		b.e_row.append(r2)
		b.en += 1
	t.check(not b.evaluate(ctx, e, _budget()), "units that moved away do not count (w_stat)")


func test_central_priority_needs_engaged_unmanned_in_a_provider_field(t: TestCtx) -> void:
	var e: AiPowerArch.Entry = _entry("power.han.central_priority")
	var ctx: AiContext = _ctx(9000)
	var a: AiPowerArch = _arch(ctx)
	var t_own: AiEntityTable = ctx.kb.own
	var r: int = t_own.upsert(9100)
	t_own.kind[r] = AiTypes.KIND_UNIT
	t_own.hp[r] = 100
	t_own.hp_max[r] = 100
	t_own.x[r] = 40 * C
	t_own.y[r] = 40 * C
	t_own.role_mask[r] = 1 << AiTypes.R_COMMAND_PROVIDER
	for i: int in 5:
		_unit(a, (38 + i) * C, 41 * C, 3000, AiPowerArch.SEL_UNMANNED | AiPowerArch.SEL_VEH, 0, 1)
	t.check(a.evaluate(ctx, e, _budget()), "five engaged unmanned units in the field of a provider")
	t.ge(a.benefit, _need(e))
	var b: AiPowerArch = _arch(ctx)
	for i2: int in 5:
		_unit(b, (38 + i2) * C, 41 * C, 2500, AiPowerArch.SEL_UNMANNED | AiPowerArch.SEL_VEH, 0, 0)
	t.check(not b.evaluate(ctx, e, _budget()), "not engaged")
	# Reserve Bandwidth extends the field by 3 cells: units outside r but inside r + 3
	var rb: AiPowerArch.Entry = _entry("power.han.reserve_bandwidth")
	var c: AiPowerArch = _arch(ctx)
	for i3: int in 5:
		_unit(c, (49 + i3 % 2) * C, (40 + i3) * C, 2600, AiPowerArch.SEL_UNMANNED | AiPowerArch.SEL_VEH, 0, 1)
	c.evaluate(ctx, rb, _budget())
	t.gt(c.benefit, 0, "units in the ring (r, r + 3] of the provider")
