extends RefCounted
## AB-02: a changed effective max health rescales hp through combat (abilities 5.2.3, test_abil_hp).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")


func test_bound_health_condition_rescales(t: TestCtx) -> void:
	var d: GameData = AbilKit.data()
	var reserves: DefEffect = AbilKit.fx_stat(DefEnums.Stat.HEALTH, 1000)
	reserves.cond_codes = PackedInt32Array([DefEnums.Cond.DEPLOYED])
	reserves.cond_params = [{}]
	AbilKit.add_research_effects(d, [reserves])
	var w: SimWorld = AbilKit.world({}, d)
	AbilKit.bind_cond(w, 0, DefTestKit.U_RIFLEMAN, reserves)
	var e: SimEntity = AbilKit.rifle(w, 0, 30, 30)
	var base: int = e.hp_max
	t.eq(base, 400, "rifleman 400 hp")
	e.hp = 240
	SimCond.set_code(w, e, DefEnums.Cond.DEPLOYED, true)
	w.step()
	t.eq(e.hp_max, 440, "field entered: max +10 %")
	t.eq(e.hp, 264, "hp keeps its fraction (240 / 400 = 264 / 440)")
	SimCond.set_code(w, e, DefEnums.Cond.DEPLOYED, false)
	w.step()
	t.eq(e.hp_max, 400, "field left: max back")
	t.eq(e.hp, 240, "hp back: leaving never heals or kills")
	e.hp = 1
	SimCond.set_code(w, e, DefEnums.Cond.DEPLOYED, true)
	w.step()
	SimCond.set_code(w, e, DefEnums.Cond.DEPLOYED, false)
	w.step()
	t.ge(e.hp, 1, "never below 1 hp")


func test_research_completion_rescales_existing_units(t: TestCtx) -> void:
	var d: GameData = AbilKit.data()
	var w: SimWorld = AbilKit.world({}, d)
	var e: SimEntity = AbilKit.tank(w, 0, 30, 30)
	w.step()  # spawns join the world's lists (own_ids) at the next flush
	var before: int = e.hp_max
	var l3: DefLayer3 = w.players[0].view.layer3
	# what DefLayer3.apply_research does for an unconditional +10 % health research
	l3._unit_bp[e.def_idx * DefEnums.Stat.COUNT + DefEnums.Stat.HEALTH] += 1000
	l3.version += 1
	l3.completed.append(0)
	w.abilities.on_research_complete(0, 0)
	w.step()
	t.eq(e.hp_max, DefStatMath.apply_bp(before, 1000), "max health +10 % after the research")
	t.eq(e.hp, e.hp_max, "a full-health unit stays full")
	t.eq(e.stats.hp_max_last, e.hp_max, "hp_max_last follows")
