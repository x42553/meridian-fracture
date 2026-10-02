extends RefCounted
## E2 power (10.1-E, S2 power part): balance, strict shortage, events, derived flags, the SAP reserve timelines.

const KIT := preload("res://tests/support/sim_econ_kit.gd")


func _base(extra: Dictionary = {}) -> SimWorld:
	var w: SimWorld = KIT.make_world(extra)
	KIT.spawn_struct(w, DefTestKit.S_HQ, 0, 10, 10)
	return w


func test_balance_and_strict_shortage(t: TestCtx) -> void:
	var w: SimWorld = _base()
	KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600)
	for i: int in 5:
		KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 14 + i * 3, 14, 500)  # 5 x -30 = -150
	w.step()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.eq([w.power.supply(0), w.power.demand(0)], [150, 150] as Array, "balance")
	t.check_false(w.power.is_shortage(0), "exactly balanced is normal")
	t.eq(pe.power_state, SimEconConst.PW_NORMAL, "state")
	t.eq(w.players[0].power_supply, 150, "mirrored to the kernel record for HUD / AI")
	KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 14 + 15, 14, 500)
	w.step()
	t.check(w.power.is_shortage(0), "180 > 150 is a shortage")
	t.eq(w.power.production_rate_bp(0), 5000, "half speed")
	t.check_false(w.power.powered(0), "powered() false")
	var ev: Array[PackedInt32Array] = KIT.events_of(w, SimEconConst.EVT_POWER_SHORTAGE)
	t.eq(ev.size(), 1, "one EVT_POWER_SHORTAGE")
	t.eq([ev[0][4], ev[0][5], ev[0][6]], [0, 150, 180] as Array, "pid, supply, demand")
	t.check(pe.rates_dirty, "rates dirty on the transition")
	KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 20, 600)
	w.step()
	t.check_false(w.power.is_shortage(0), "a second generator restores")
	t.eq(w.power.production_rate_bp(0), 10000, "normal speed")
	t.eq(KIT.events_of(w, SimEconConst.EVT_POWER_RESTORED).size(), 1, "EVT_POWER_RESTORED")


func test_sell_and_death_update_on_the_same_pass(t: TestCtx) -> void:
	var w: SimWorld = _base()
	var g1: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600)
	KIT.spawn_struct(w, DefTestKit.S_FACTORY, 0, 20, 10, 2000)
	w.step()
	t.eq([w.power.supply(0), w.power.demand(0)], [150, 60] as Array, "start")
	w.submit_raw(0, SimCmd.sell(PackedInt32Array([g1.id])))
	w.step()
	t.eq(w.power.supply(0), 0, "sale drops the supply in the same tick")
	t.check(w.power.is_shortage(0), "and the shortage shows in the same stage 4")


func test_emp_shutdown_still_consumes(t: TestCtx) -> void:
	var w: SimWorld = _base()
	KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600)
	var bar: SimEntity = KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 18, 10, 500)
	w.step()
	bar.econ.shutdown_until = w.tick + 100
	w.step()
	t.eq(w.power.demand(0), 30, "an EMP-shut structure still counts as demand")
	t.check_false(w.economy.life.structure_online(w, bar), "but it is offline")
	t.check((bar.flags & SimFlags.F_POWERED) == 0, "F_POWERED cleared")
	KIT.run(w, 101)
	t.check(w.economy.life.structure_online(w, bar), "online again after the shutdown")


func test_power_classes_and_flags_under_shortage(t: TestCtx) -> void:
	var w: SimWorld = _base()
	var tur: SimEntity = KIT.spawn_struct(w, DefTestKit.S_TURRET, 0, 14, 10, 800)  # DEFENSE, demand 20
	var bar: SimEntity = KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 18, 10, 500)
	var ref: SimEntity = KIT.spawn_struct(w, DefTestKit.S_REFINERY, 0, 22, 10, 1800)
	w.step()
	t.check(w.power.is_shortage(0), "no generator: shortage")
	t.check_false(w.power.defenses_online(0), "non-SAP defenses go offline at once")
	t.check_false(w.economy.life.structure_online(w, tur), "defense offline")
	t.check(w.economy.life.structure_online(w, bar), "producers slow down instead of stopping")
	t.check(w.economy.life.structure_online(w, ref), "the Refinery keeps working")
	t.eq(w.economy.life.power_class_of(tur.def_idx), SimEconConst.PC_DEFENSE, "class table")
	t.eq(w.economy.life.power_class_of(ref.def_idx), SimEconConst.PC_ECON, "class table")
	t.eq(w.economy.life.power_class_of(bar.def_idx), SimEconConst.PC_PRODUCER, "class table")
	t.eq(w.economy.life.prod_kind_of(bar.def_idx), SimEconConst.PROD_BARRACKS, "producer kind")
	t.check(w.power.is_powered(bar.id) and not w.power.is_powered(tur.id), "is_powered(eid)")


func _sap_world() -> SimWorld:
	var w: SimWorld = _base()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	pe.flags |= SimEconConst.PF_SAP_RESERVE
	w.economy.set_knob_base(w, 0, SimEconConst.K_SAP_RESERVE_TICKS, 400)
	return w


## Steps until world.tick == `until`; returns the first evaluated tick at which `defenses_online` was false (or -1).
func _first_offline(w: SimWorld, until: int) -> int:
	var first: int = -1
	while w.tick < until:
		var at: int = w.tick
		w.step()
		if first < 0 and not w.power.defenses_online(0):
			first = at
	return first


func test_sap_reserve_timeline(t: TestCtx) -> void:
	var w: SimWorld = _sap_world()
	KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 14, 10, 500)
	var gen: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 18, 10, 600)
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.eq(pe.reserve_left, 400, "full reserve (20 s)")
	t.eq(_first_offline(w, 1000), -1, "powered until tick 1000")
	w.kill(gen, SimWorld.Cause.DAMAGE, 0, 1)  # shortage from tick 1000
	var off: int = _first_offline(w, 1500)
	t.eq(off, 1400, "defenses keep firing 400 ticks, offline from tick 1400")
	t.eq(pe.reserve_left, 0, "drained")
	t.eq(KIT.events_of(w, SimEconConst.EVT_SAP_RESERVE_EMPTY).size(), 1, "EVT_SAP_RESERVE_EMPTY")
	KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 18, 10, 600)  # adequate from tick 1500
	KIT.run(w, 1200)
	t.eq(w.tick, 2700, "clock")
	t.eq(pe.reserve_left, 0, "1200 adequate ticks (1500-2699) do not refill yet")
	t.check(w.power.defenses_online(0), "defenses are back at once when powered")
	w.step()
	t.eq(pe.reserve_left, 400, "refilled when tick 2700 is evaluated (1500 + 1200)")


func test_sap_short_outage_and_second_shortage(t: TestCtx) -> void:
	var w: SimWorld = _sap_world()
	KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 14, 10, 500)
	var gen: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 18, 10, 600)
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	KIT.run(w, 1000)
	w.kill(gen, SimWorld.Cause.DAMAGE, 0, 1)
	KIT.run(w, 200)
	t.eq(pe.reserve_left, 200, "shortage 1000-1200 leaves 200")
	var gen2: SimEntity = KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 18, 10, 600)  # adequate from 1200
	KIT.run(w, 600)  # tick 1800: before the refill at 2400
	t.eq(pe.reserve_left, 200, "not refilled yet")
	w.kill(gen2, SimWorld.Cause.DAMAGE, 0, 1)
	var off: int = _first_offline(w, 2100)
	t.eq(off, 2000, "the remaining 200 drain by tick 2000")


func test_sap_reserve_capacitors(t: TestCtx) -> void:
	var w: SimWorld = _sap_world()
	KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 18, 10, 600)
	w.step()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	w.economy.set_knob_base(w, 0, SimEconConst.K_SAP_RESERVE_TICKS, 700)
	t.eq([pe.reserve_max, pe.reserve_left], [700, 700] as Array, "a full reserve becomes 700 at once")
	pe.reserve_left = 100
	w.economy.set_knob_base(w, 0, SimEconConst.K_SAP_RESERVE_TICKS, 900)
	t.eq(pe.reserve_left, 100, "a partial reserve is unchanged")


func test_non_sap_has_no_reserve(t: TestCtx) -> void:
	var w: SimWorld = _base()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.eq([pe.reserve_max, pe.reserve_left], [0, 0] as Array, "no reserve")
	KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 14, 10, 500)
	w.step()
	t.check_false(w.power.defenses_online(0), "immediately offline")
	t.eq(w.power.reserve_left_ticks(0), 0, "reserve_left_ticks")
