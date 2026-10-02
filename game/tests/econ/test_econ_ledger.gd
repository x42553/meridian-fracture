extends RefCounted
## E2 ledger (10.1-A): handicap remainder, all-or-nothing spend, income ring, statistics, unit cap room, knobs,
## player init from the match rules.

const KIT := preload("res://tests/support/sim_econ_kit.gd")


func _gain(w: SimWorld, amount: int, reason: int) -> int:
	var before: int = w.players[0].credits
	w.economy.earn(w, 0, amount, reason)
	return w.players[0].credits - before


func test_handicap_scales_income_only(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world({"handicap": 120})
	t.eq(_gain(w, 10, SimEconConst.CR_HARVEST), 12, "10 credits at 120 % pay 12")
	t.eq(_gain(w, 10, SimEconConst.CR_REFUND), 10, "refunds ignore the handicap")
	t.eq(_gain(w, 10, SimEconConst.CR_SELL), 10, "sells ignore the handicap")
	var w2: SimWorld = KIT.make_world({"handicap": 125})
	var got: PackedInt32Array = PackedInt32Array()
	for _i: int in 4:
		got.append(_gain(w2, 10, SimEconConst.CR_HARVEST))
	t.eq(got, PackedInt32Array([12, 13, 12, 13]), "125 %: the remainder accumulator alternates")
	t.eq(_gain(w2, 10, SimEconConst.CR_DEPOT), 12, "depot income is scaled too")


func test_start_credits_from_rules_and_handicap(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world({"handicap": 120, "rules": {"start_credits": 5000}})
	t.eq(w.players[0].credits, 6000, "start credits scaled once")
	w.economy.init_player(w, 0, w.players[0].roster_idx, 1000, 150)
	t.eq(w.players[0].credits, 1500, "init_player override")
	t.eq(KIT.econ(w, 0).unit_cap, w.rules.unit_cap, "unit cap from the rules")
	t.is_null(w.players[3].econ if w.players.size() > 3 else null, "vacant pids have no record")


func test_spend_is_all_or_nothing(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	w.players[0].credits = 500
	t.check_false(w.economy.spend(w, 0, 600, SimEconConst.CR_CONSTRUCTION), "600 from 500 refused")
	t.eq(w.players[0].credits, 500, "unchanged")
	t.check(w.economy.spend(w, 0, 200, SimEconConst.CR_CONSTRUCTION), "200 ok")
	t.check(w.economy.spend(w, 0, 100, SimEconConst.CR_PRODUCTION), "100 ok")
	t.check(w.economy.spend(w, 0, 50, SimEconConst.CR_POWER_USE), "50 ok")
	t.eq(w.players[0].credits, 150, "balance")
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.eq([pe.stat_spent_construction, pe.stat_spent_units, pe.stat_spent_powers], [200, 100, 50] as Array, "category statistics")
	t.check(w.economy.can_afford(0, 150) and not w.economy.can_afford(0, 151), "can_afford")
	t.eq(w.economy.credits(0), 150, "credits()")
	t.check_false(w.economy.spend(w, 0, -5, SimEconConst.CR_OTHER), "negative refused")
	t.check(w.economy.try_spend(0, 150) and w.players[0].credits == 0, "3.11 alias")
	w.economy.add(0, 40)
	t.eq(w.players[0].credits, 40, "add alias")


func test_income_ring_and_stats(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	w.economy.earn(w, 0, 10, SimEconConst.CR_HARVEST)
	w.economy.earn(w, 0, 500, SimEconConst.CR_REFUND)
	w.economy.earn(w, 0, 500, SimEconConst.CR_SELL)
	t.eq(w.economy.q_income_per_minute(0), 10, "refunds and sells are not income")
	for k: int in range(1, 12):
		KIT.run(w, 100)
		w.economy.earn(w, 0, 10, SimEconConst.CR_SALVAGE)
		t.check(k > 0)
	t.eq(w.economy.q_income_per_minute(0), 120, "12 buckets of 10")
	KIT.run(w, 100)
	t.eq(w.economy.q_income_per_minute(0), 110, "the oldest bucket dropped out")
	KIT.run(w, 1200)
	t.eq(w.economy.q_income_per_minute(0), 0, "an idle minute")
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	t.eq([pe.stat_harvested, pe.stat_salvaged, pe.stat_refunded, pe.stat_sold], [10, 110, 500, 500] as Array, "totals")
	t.eq(w.economy.income_total(0), 120, "monotonic income total")


func test_earn_with_position_emits_event(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	w.economy.earn(w, 0, 50, SimEconConst.CR_HARVEST, 5000, 6000)
	var ev: Array[PackedInt32Array] = KIT.events_of(w, SimEconConst.EVT_CREDITS_GAINED)
	t.eq(ev.size(), 1, "EVT_CREDITS_GAINED")
	t.eq([ev[0][2], ev[0][3], ev[0][4], ev[0][5]], [5000, 6000, 0, 50] as Array, "x, y, pid, amount")
	var cash: Array[PackedInt32Array] = KIT.events_of(w, SimEvent.CASH)
	t.check(cash.size() >= 1, "and the kernel CASH event")


func test_unit_cap_room(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world({"rules": {"unit_cap": 20}})
	t.eq(w.economy.unit_cap_room(0), 20, "empty")
	for i: int in 3:
		w.spawn_unit(KIT.uidx(DefTestKit.U_RIFLEMAN), 0, 30000 + i * 700, 30000)
	t.eq(w.economy.unit_cap_room(0), 17, "3 live capped units")
	KIT.econ(w, 0).cap_reserved = 5
	t.eq(w.economy.unit_cap_room(0), 12, "reserved by progressing heads")
	KIT.econ(w, 0).cap_reserved = 40
	t.eq(w.economy.unit_cap_room(0), -23, "may be negative")
	w.spawn_unit(KIT.uidx(DefTestKit.U_COLLECTOR), 0, 30000, 31000)
	t.eq(w.players[0].unit_count, 3, "pop-0 units are exempt")


func test_knobs_combine_modes(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	var e: SimEconomySystem = w.economy
	t.eq(e.knob(0, SimEconConst.K_REARM_RATE_BP), 10000, "MUL default")
	e.set_knob_base(w, 0, SimEconConst.K_PROD_RATE_BARRACKS_BP, 10000)
	e.set_knob_temp(0, SimEconConst.K_PROD_RATE_BARRACKS_BP, 12500, 10)
	t.eq(e.knob(0, SimEconConst.K_PROD_RATE_BARRACKS_BP), 12500, "MUL while the window is open")
	e.set_knob_temp(0, SimEconConst.K_SALVAGE_TICKS, 60, 10)
	t.eq(e.knob(0, SimEconConst.K_SALVAGE_TICKS), 60, "MIN(160, 60)")
	e.set_knob_temp(0, SimEconConst.K_CMD_RADIUS_CELLS, 3, 10)
	t.eq(e.knob(0, SimEconConst.K_CMD_RADIUS_CELLS), 8, "ADD 5 + 3")
	e.set_knob_temp(0, SimEconConst.K_RELAY_DAMAGE_BP, 1500, 10)
	t.eq(e.knob(0, SimEconConst.K_RELAY_DAMAGE_BP), 1500, "OVR")
	KIT.run(w, 10)
	t.eq([e.knob(0, SimEconConst.K_PROD_RATE_BARRACKS_BP), e.knob(0, SimEconConst.K_SALVAGE_TICKS), e.knob(0, SimEconConst.K_CMD_RADIUS_CELLS), e.knob(0, SimEconConst.K_RELAY_DAMAGE_BP)], [10000, 160, 5, 1000] as Array, "restored at the absolute expiry tick")
