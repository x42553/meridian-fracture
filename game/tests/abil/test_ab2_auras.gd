extends RefCounted
## AB-05 on the REAL balance data: Han command fields (S09), NEC Relay (S10), free healing (S19), regen, suppression
## support, the EW jammer, the detector state mirror, the near-friendly research conditions.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")

const LINK: String = "unit.han.link_operator"
const DRONE: String = "unit.han.nest_rocket_drone"
const HAN: String = "roster.han.china"


func _dmg(w: SimWorld, e: SimEntity) -> int:
	return A.lease_bp(w, e, C.STAT_DMG_OUT)


func test_s09_han_command_field(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": [HAN, "roster.nec.vanilla"]})
	if not t.not_null(w, "world"):
		return
	var op: SimEntity = A.spawn(w, LINK, 0, 30, 30)
	var d_in: SimEntity = A.spawn(w, DRONE, 0, 35, 30)  # 5 cells: inside the 5-cell disc
	var d_out: SimEntity = A.spawn(w, DRONE, 0, 36, 30)  # 6 cells: outside
	var inf: SimEntity = null  # a manned Han combat infantry unit: no unmanned recipient
	for u: DefUnit in w.data.units:
		if u.faction == 2 and (u.tags & DefEnums.UT_INFANTRY) != 0 and (u.tags & DefEnums.UT_COMBAT) != 0 and w.players[0].roster.has_unit(u.index):
			inf = A.spawn(w, u.id, 0, 31, 30)
			break
	A.run(w, 3)
	t.eq(_dmg(w, d_in), 1000, "drone inside holds DMG_OUT +1000")
	t.eq(_dmg(w, d_out), 0, "drone outside does not")
	t.eq(_dmg(w, inf), 0, "a manned unit is not an unmanned recipient")
	t.check(w.abilities.aura.is_covered(d_in, SimAuraSystem.G_CMD), "aura bit set")
	# a second operator: still one lease, no stacking
	var op2: SimEntity = A.spawn(w, LINK, 0, 33, 31)
	A.run(w, 4)
	t.eq(_dmg(w, d_in), 1000, "two operators still one lease")
	# kill the first: the second still covers
	w.kill(op, SimWorld.Cause.SCRIPT, 0, -1)
	A.run(w, 3)
	t.eq(_dmg(w, d_in), 1000, "covered by the second operator")
	# suppress the second: the field goes off within 2 ticks
	op2.combat.sup_left_q8 = 9999
	A.run(w, 2)
	t.eq(_dmg(w, d_in), 0, "suppressed provider switches the field off")
	op2.combat.sup_left_q8 = 0
	A.run(w, 2)
	t.eq(_dmg(w, d_in), 1000, "and it returns after the suppression ends")
	# destroying the last provider clears at once
	w.kill(op2, SimWorld.Cause.SCRIPT, 0, -1)
	A.run(w, 2)
	t.eq(_dmg(w, d_in), 0, "provider death clears the lease")
	t.check(not w.abilities.aura.is_covered(d_in, SimAuraSystem.G_CMD), "bit cleared")
	t.eq(w.abilities.debug_validate(w).size(), 0, "debug_validate clean")


func test_s09_research_and_windows(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": [HAN, "roster.nec.vanilla"]})
	A.spawn(w, LINK, 0, 30, 30)
	var d6: SimEntity = A.spawn(w, DRONE, 0, 36, 30)
	var d8: SimEntity = A.spawn(w, DRONE, 0, 38, 30)
	A.run(w, 3)
	t.eq(_dmg(w, d6), 0, "6 cells: outside the base field")
	# Distributed Cognition: base radius 7 cells
	var r: int = w.data.research_idx("research.han.distributed_cognition")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	A.run(w, 3)
	t.eq(_dmg(w, d6), 1000, "Distributed Cognition: 7 cells cover the drone at 6")
	t.eq(_dmg(w, d8), 0, "8 cells still outside")
	# Reserve Bandwidth: +3 cells for 400 ticks
	var t0: int = w.tick
	w.abilities.aura.set_window(0, SimAuraSystem.G_CMD, 0, 3072, t0 + 400)
	A.run(w, 3)
	t.eq(_dmg(w, d8), 1000, "Reserve Bandwidth adds 3 cells")
	A.run_to(w, t0 + 400 + 2)
	t.eq(_dmg(w, d8), 0, "the window ended after 400 ticks")
	t.eq(_dmg(w, d6), 1000, "the permanent field is untouched")
	# Central Priority: 20 % damage
	w.abilities.aura.set_window(0, SimAuraSystem.G_CMD, 2000, 0, w.tick + 100)
	A.run(w, 3)
	t.eq(_dmg(w, d6), 2000, "Central Priority raises the lease to +2000")
	A.run(w, 110)
	t.eq(_dmg(w, d6), 1000, "and back to +1000")


func test_hidden_relays_keeps_the_field(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": [HAN, "roster.nec.vanilla"]})
	var op: SimEntity = A.spawn(w, LINK, 0, 30, 30)
	var d: SimEntity = A.spawn(w, DRONE, 0, 33, 30)
	var r: int = w.data.research_idx("research.han.hidden_relays")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	A.run(w, 150)
	t.eq(op.vis.concealed, 1, "the operator cloaked")
	t.eq(_dmg(w, d), 1000, "a cloaked operator keeps its field")


func test_long_walker_and_mekong(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.han.china", "roster.han.cambodia"]})
	var lw: SimEntity = A.spawn(w, "unit.han.long_command_walker", 0, 30, 30)
	var d7: SimEntity = A.spawn(w, DRONE, 0, 37, 30)
	A.run(w, 3)
	t.eq(_dmg(w, d7), 0, "7 cells: outside the undeployed walker")
	w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([lw.id])))
	A.run(w, 70)
	t.eq(lw.combat.ext_deployed, 1, "walker deployed")
	t.eq(_dmg(w, d7), 1000, "deployed walker: +2 cells reach the drone at 7")
	# Mekong: the field exists only when deployed (40 ticks after the order)
	var mk: SimEntity = A.spawn(w, "unit.han.mekong_field_engineer", 1, 30, 40)
	var dm: SimEntity = A.spawn(w, DRONE, 1, 32, 40)
	A.run(w, 3)
	t.eq(_dmg(w, dm), 0, "undeployed Mekong has no field")
	var s: int = mk.abil.slot_of_kind(K.AK_COMMAND_FIELD)
	w.submit_raw(1, SimCmd.build(SimCmd.DEPLOY, [s], PackedInt32Array([mk.id])))
	A.run(w, 30)
	t.eq(_dmg(w, dm), 0, "still deploying")
	A.run(w, 15)
	t.eq(_dmg(w, dm), 1000, "the field starts after the 40-tick deploy")
	w.submit_raw(1, SimCmd.build(SimCmd.UNDEPLOY, [s], PackedInt32Array([mk.id])))
	A.run(w, 3)
	t.eq(_dmg(w, dm), 0, "packing switches it off")


func _relay_world(extra: Dictionary = {}) -> SimWorld:
	var o: Dictionary = {"rosters": ["roster.nec.vanilla", "roster.napc.usa"]}
	for k: Variant in extra.keys():
		o[k] = extra[k]
	return A.world(o)


func test_s10_relay(t: TestCtx) -> void:
	var w: SimWorld = _relay_world()
	var gen: SimEntity = A.structure(w, "structure.shared.generator", 0, 20, 20)
	var relay: SimEntity = A.structure(w, "structure.nec.relay", 0, 30, 30)
	var tank: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 35, 30)  # 5 cells
	var far: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 37, 30)  # 7 cells
	A.run(w, 5)
	t.check(relay.abil != null and relay.abil.slot_of_kind(K.AK_RELAY_FIELD) >= 0, "relay has the field slot")
	t.eq(_dmg(w, tank), 1000, "Leopard at 5 cells holds +1000")
	t.eq(_dmg(w, far), 0, "Leopard at 7 cells does not (6 cells)")
	t.check(tank.abil.cond_ext & (1 << DefEnums.Cond.IN_RELAY_FIELD) != 0, "IN_RELAY_FIELD condition pushed")
	# Treaty Coordination window: re-issued at 1500
	w.abilities.aura.set_window(0, SimAuraSystem.G_RELAY, 1500, 0, w.tick + 60)
	A.run(w, 3)
	t.eq(_dmg(w, tank), 1500, "Treaty raises the lease to 1500")
	A.run(w, 65)
	t.eq(_dmg(w, tank), 1000, "and back to 1000")
	# power shortage at tick 100: the generator goes away
	A.run_to(w, 100)
	w.remove_entity(gen.id, SimEvent.REM_SCRIPT)
	w.step()  # tick 100
	t.eq(_dmg(w, tank), 0, "field off at tick 100")
	t.check(not tank.abil.cond_ext & (1 << DefEnums.Cond.IN_RELAY_FIELD) != 0, "IN_RELAY_FIELD cleared")
	# power back: the field returns
	A.structure(w, "structure.shared.generator", 0, 20, 20)
	A.run(w, 4)
	t.eq(_dmg(w, tank), 1000, "the field returns with the power")
	# a destroyed relay clears at once
	w.kill(relay, SimWorld.Cause.SCRIPT, 0, -1)
	A.run(w, 2)
	t.eq(_dmg(w, tank), 0, "destroyed relay clears the lease")


func test_s10_distributed_control(t: TestCtx) -> void:
	var w: SimWorld = _relay_world()
	var gen: SimEntity = A.structure(w, "structure.shared.generator", 0, 20, 20)
	A.structure(w, "structure.nec.relay", 0, 30, 30)
	var tank: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 37, 30)  # 7 cells
	var r: int = w.data.research_idx("research.nec.distributed_control")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	A.run(w, 5)
	t.eq(_dmg(w, tank), 1000, "Distributed Control: radius 8 covers 7 cells")
	A.run_to(w, 100)
	w.remove_entity(gen.id, SimEvent.REM_SCRIPT)
	A.run_to(w, 299)
	t.eq(_dmg(w, tank), 1000, "the field is kept for 200 ticks after the power loss")
	A.run_to(w, 301)
	t.eq(_dmg(w, tank), 0, "and ends at tick 300")


func test_relay_destroyed_ignores_grace(t: TestCtx) -> void:
	var w: SimWorld = _relay_world()
	A.structure(w, "structure.shared.generator", 0, 20, 20)
	var relay: SimEntity = A.structure(w, "structure.nec.relay", 0, 30, 30)
	var tank: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 33, 30)
	var r: int = w.data.research_idx("research.nec.distributed_control")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	A.run(w, 5)
	t.eq(_dmg(w, tank), 1000, "covered")
	w.kill(relay, SimWorld.Cause.SCRIPT, 0, -1)
	A.run(w, 2)
	t.eq(_dmg(w, tank), 0, "destruction ends it immediately, no grace")


func test_fen_mast_relay_in_shortage(t: TestCtx) -> void:
	var w: SimWorld = _relay_world({"rosters": ["roster.nec.nordics", "roster.napc.usa"]})
	var fen: SimEntity = A.spawn(w, "unit.nec.fen_recon_carrier", 0, 30, 30)
	var tank: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 33, 30)  # 3 cells
	var r: int = w.data.research_idx("research.nec.dispersed_links")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	A.run(w, 5)
	t.eq(_dmg(w, tank), 0, "an undeployed Fen has no field")
	w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [fen.abil.slot_of_kind(K.AK_SENSOR_MAST)], PackedInt32Array([fen.id])))
	A.run(w, 46)
	t.eq(_dmg(w, tank), 1000, "the deployed Fen is a 4-cell relay - and there is no power at all")


func test_s19_factory_apron_heal(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var fac: SimEntity = A.structure(w, "structure.shared.factory", 0, 30, 30)
	t.gt(fac.abil.slot_of_kind(K.AK_AURA_REGEN), -1, "the NAPC trait grants the apron to the Factory")
	var g: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 34, 30)
	A.hold_fire(w)
	g.hp = g.hp_max / 2
	var hp0: int = g.hp
	var hp_max: int = g.hp_max
	var per: int = hp_max * 100 / 20  # milli-hp per 10-tick pulse at 100 bps
	g.combat.last_hit_tick = w.tick  # hit at tick 0: 120 quiet ticks needed
	A.run_to(w, 120)
	t.eq(g.hp, hp0, "no healing before 120 quiet ticks")
	var acc: int = 0
	var expect: int = hp0
	for pulse: int in 10:  # ticks 120, 130, ... 210
		w.step()
		acc += per
		var whole: int = acc / 1000
		acc -= whole * 1000
		expect += whole
		A.run(w, 9)
		t.eq(g.hp, expect, "pulse %d: exactly hp_max x 1 %% / 2 s" % pulse)
	# it stops at the 75 % cap
	A.run(w, 1500)
	t.eq(g.hp, hp_max * 7500 / 10000, "the apron stops at 75 %% of max health")
	t.eq(w.abilities.debug_validate(w).size(), 0, "debug_validate clean")


func test_apron_only_vehicles_and_only_the_owner_team(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.napc.usa"]})
	A.structure(w, "structure.shared.factory", 0, 30, 30)
	var enemy: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 1, 33, 30)
	var rifle: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 33, 32)
	enemy.hp = enemy.hp_max / 2
	rifle.hp = rifle.hp_max / 2
	A.hold_fire(w)
	var e0: int = enemy.hp
	var r0: int = rifle.hp
	A.run(w, 300)
	t.eq(enemy.hp, e0, "an enemy vehicle is not healed")
	t.eq(rifle.hp, r0, "infantry is not an apron target")


func test_medic_and_field_hospital_share_the_group(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var medic: SimEntity = A.spawn(w, "unit.napc.combat_medic", 0, 30, 30)
	var hosp: SimEntity = A.neutral(w, "neutral.field_hospital", 34, 30)
	w.change_owner(hosp.id, 0)
	var inf: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 32, 30)
	var veh: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 31, 31)
	inf.hp = inf.hp_max / 2
	veh.hp = veh.hp_max / 2
	var v0: int = veh.hp
	var i0: int = inf.hp
	A.run(w, 100)
	# medic 300 bps and hospital 200 bps in ONE group: the highest applies (300), never 500
	var gain: int = inf.hp - i0
	var milli_med: int = inf.hp_max * 300 / 20 * 10
	t.check(gain >= milli_med / 1000 - 1 and gain <= milli_med / 1000 + 1, "infantry heals at the medic rate only (got %d, medic %d)" % [gain, milli_med / 1000])
	t.eq(veh.hp, v0, "vehicles are never healed by the medic or the hospital")
	# the medic does not heal itself
	medic.hp = medic.hp_max / 2
	var m0: int = medic.hp
	A.run(w, 100)
	t.gt(medic.hp, m0, "a medic beside a hospital is healed by the hospital (2 %/s)")


func test_medic_does_not_heal_itself(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var medic: SimEntity = A.spawn(w, "unit.napc.combat_medic", 0, 30, 30)
	medic.hp = medic.hp_max / 2
	var m0: int = medic.hp
	A.run(w, 200)
	t.eq(medic.hp, m0, "not_self")
	var m2: SimEntity = A.spawn(w, "unit.napc.combat_medic", 0, 32, 30)
	A.run(w, 100)
	t.gt(medic.hp, m0, "another medic heals it")
	t.eq(m2.hp, m2.hp_max, "full health medic untouched")


func test_hospital_needs_an_owner(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var hosp: SimEntity = A.neutral(w, "neutral.field_hospital", 34, 30)
	var inf: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 32, 30)
	inf.hp = inf.hp_max / 2
	var i0: int = inf.hp
	A.run(w, 100)
	t.eq(inf.hp, i0, "an unowned hospital heals nobody")
	w.change_owner(hosp.id, 0)
	A.run(w, 100)
	t.gt(inf.hp, i0, "the owner's infantry heals once it is captured")


func test_section_logistics_regen(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	A.structure(w, "structure.shared.generator", 0, 20, 20)
	var bar: SimEntity = A.structure(w, "structure.shared.barracks", 0, 30, 30)
	var near: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 34, 30)
	var far: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 45, 30)
	near.hp = near.hp_max / 2
	far.hp = far.hp_max / 2
	var n0: int = near.hp
	var f0: int = far.hp
	A.run(w, 200)
	t.eq(near.hp, n0, "no regen without the research")
	var r: int = w.data.research_idx("research.napc.section_logistics")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	t.gt(near.abil.slot_of_kind(K.AK_REGEN), -1, "the infantry got the regen slot")
	A.run(w, 100)
	t.gt(near.hp, n0, "regen beside a powered barracks")
	t.eq(far.hp, f0, "no regen out of the 6-cell source radius")
	# unpowered barracks: no regen (shortage)
	var mid: int = near.hp
	A.structure(w, "structure.shared.factory", 0, 40, 40)  # demand > supply? generator gives 150
	w.kill(bar, SimWorld.Cause.SCRIPT, 0, -1)
	A.run(w, 100)
	t.eq(near.hp, mid, "the source structure is gone")


func test_watershed_logistics_passengers(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.ae.kongo", "roster.nec.vanilla"]})
	var ok: SimEntity = A.spawn(w, "unit.ae.okapi_amphibious_carrier", 0, 30, 30)
	var inf: SimEntity = A.spawn(w, "unit.ae.civic_rifle_team", 0, 31, 30)
	inf.hp = inf.hp_max / 2
	ok.hp = ok.hp_max / 2
	var hp0: int = inf.hp
	t.check(SimTransport.board(w, ok, inf), "boarded")
	var r: int = w.data.research_idx("research.ae.watershed_logistics")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	A.run(w, 200)
	t.gt(inf.hp, hp0, "the passenger regenerates aboard")
	t.eq(ok.hp, ok.hp_max / 2, "the carrier is not healed")


func test_suppression_support(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.def.russia", "roster.nec.vanilla"]})
	var so: SimEntity = A.spawn(w, "unit.def.signal_officer", 0, 30, 30)
	var near: SimEntity = A.spawn(w, "unit.def.rifle_squad", 0, 33, 30) if A.uid("unit.def.rifle_squad") >= 0 else null
	if near == null:
		for u: DefUnit in w.data.units:
			if u.faction == 1 and (u.tags & DefEnums.UT_INFANTRY) != 0 and (u.tags & DefEnums.UT_COMBAT) != 0 and w.players[0].roster.has_unit(u.index):
				near = A.spawn(w, u.id, 0, 33, 30)
				break
	var far: SimEntity = A.spawn(w, near_id(w, near), 0, 40, 30)
	var vehicle: SimEntity = A.spawn(w, "unit.def.saker_missile_truck", 0, 32, 32)
	A.run(w, 4)
	t.eq(A.lease_bp(w, near, C.STAT_SUP_RECOVER), 5000, "infantry within 5 cells recovers 50 % faster")
	t.eq(A.lease_bp(w, far, C.STAT_SUP_RECOVER), 0, "out of range: nothing")
	t.eq(A.lease_bp(w, vehicle, C.STAT_SUP_RECOVER), 0, "vehicles are no recipients")
	# suppressing the officer switches the support off
	so.combat.sup_left_q8 = 9999
	A.run(w, 3)
	t.eq(A.lease_bp(w, near, C.STAT_SUP_RECOVER), 0, "a suppressed provider gives nothing")


func near_id(w: SimWorld, e: SimEntity) -> String:
	return w.data.units[e.def_idx].id


func test_ew_jammer_sight(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.nec.vanilla", "roster.napc.usa"]})
	var aster: SimEntity = A.spawn(w, "unit.nec.aster_ew_aircraft", 0, 30, 30)
	var victim: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 1, 33, 30)
	var safe: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 1, 40, 30)
	var friend: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 32, 30)
	var base: int = SimStats.peek(w, victim, DefEnums.Stat.SIGHT)
	A.run(w, 4)
	var jammed: int = SimStats.peek(w, victim, DefEnums.Stat.SIGHT)
	t.lt(jammed, base, "enemy sight is reduced")
	t.check(absi(jammed - base * 7500 / 10000) <= 2, "by 25%% (%d -> %d)" % [base, jammed])
	t.eq(SimStats.peek(w, safe, DefEnums.Stat.SIGHT), base, "outside 5 cells: unaffected")
	t.eq(SimStats.peek(w, friend, DefEnums.Stat.SIGHT), SimStats.peek(w, friend, DefEnums.Stat.SIGHT), "own units unaffected")
	t.eq(w.abilities.sight_units(friend), w.players[0].view.layer3.effective_unit_stat(DefEnums.Stat.SIGHT, friend.def_idx, 0), "own sight is the plain value")
	# two jammers do not stack
	A.spawn(w, "unit.nec.aster_ew_aircraft", 0, 31, 31)
	A.run(w, 4)
	t.eq(SimStats.peek(w, victim, DefEnums.Stat.SIGHT), jammed, "same source group: -25 % once")
	# the jammer dies: sight returns
	w.kill(aster, SimWorld.Cause.SCRIPT, 0, -1)
	A.run(w, 3)
	t.lt(SimStats.peek(w, victim, DefEnums.Stat.SIGHT), base, "the second jammer still works")


func test_detector_state_follows_emp_and_power(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "fog": true})
	var gen: SimEntity = A.structure(w, "structure.shared.generator", 0, 20, 20)
	var wt: SimEntity = A.structure(w, "structure.shared.watchtower", 0, 30, 30)
	A.run(w, 5)
	var s: int = wt.abil.slot_of_kind(K.AK_DETECTOR)
	t.eq(wt.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], K.DET_ON, "powered watchtower detects")
	t.gt(wt.vis.det_r, 0, "detection disc stamped")
	# power loss: the detector goes off and the disc is removed
	w.remove_entity(gen.id, SimEvent.REM_SCRIPT)
	A.run(w, 4)
	t.eq(wt.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], K.DET_OFF, "unpowered: detector OFF")
	A.run(w, 4)
	t.lt(wt.vis.det_cx, 0, "detection disc restamped away")
	A.structure(w, "structure.shared.generator", 0, 20, 20)
	A.run(w, 6)
	t.eq(wt.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], K.DET_ON, "power back: ON")
	# EMP
	wt.combat.emp_until = w.tick + 40
	A.run(w, 4)
	t.eq(wt.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], K.DET_OFF, "EMP switches it off")
	A.run(w, 50)
	t.eq(wt.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE], K.DET_ON, "and back on when the EMP ends")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "vision grids consistent")


func test_near_friendly_structure_condition(t: TestCtx) -> void:
	# Layered Fieldworks: infantry within 4 cells of a defensive structure take 10 % less explosive damage
	var w: SimWorld = A.world({"rosters": ["roster.sap.vanilla", "roster.nec.vanilla"]})
	var inf: SimEntity = null
	for u: DefUnit in w.data.units:
		if u.faction == 7 and (u.tags & DefEnums.UT_INFANTRY) != 0 and (u.tags & DefEnums.UT_COMBAT) != 0 and w.players[0].roster.has_unit(u.index):
			inf = A.spawn(w, u.id, 0, 30, 30)
			break
	var wt: SimEntity = A.structure(w, "structure.shared.watchtower", 0, 33, 30)
	var r: int = w.data.research_idx("research.sap.layered_fieldworks")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	t.gt(inf.stats.cond_fx.size(), 0, "the conditional effect is bound")
	A.run(w, 25)
	t.gt(inf.abil.cond_bits, 0, "near a defensive structure: condition true")
	w.kill(wt, SimWorld.Cause.SCRIPT, 0, -1)
	A.run(w, 25)
	t.eq(inf.abil.cond_bits, 0, "without the structure: condition false")


func test_target_near_friendly_condition(t: TestCtx) -> void:
	# Observer Network: Shaheen reloads 10 % faster while its target is within 6 cells of a Watchpost Recon Team
	var w: SimWorld = A.world({"rosters": ["roster.sap.pakistan", "roster.nec.vanilla"]})
	var sh: SimEntity = A.spawn(w, "unit.sap.shaheen_missile_battery", 0, 30, 30)
	var wp: SimEntity = A.spawn(w, "unit.sap.watchpost_recon_team", 0, 40, 40)
	var enemy: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 42, 40)
	var r: int = w.data.research_idx("research.sap.observer_network")
	w.players[0].view.layer3.apply_research(r)
	w.abilities.on_research_complete(0, r)
	A.hold_fire(w)
	sh.combat.target_id = enemy.id
	A.run(w, 8)
	t.gt(sh.abil.cond_bits, 0, "target near a friendly watchpost: the reload lease is held")
	sh.combat.target_id = -1
	A.run(w, 8)
	t.eq(sh.abil.cond_bits, 0, "no target: released")
	t.check(wp.hp > 0, "watchpost alive")
