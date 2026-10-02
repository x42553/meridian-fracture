extends RefCounted
## AB-06 on the REAL balance data: transport capacity rules (S12), unload cadence and exit cells, container death and
## drowning, civilian garrisons (S13), the cargo approach orders (TM-14 / S11), disembark buffs, cargo bookkeeping.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")

const APC: String = "unit.napc.pathfinder_apc"
const RIFLE: String = "unit.napc.rifle_squad"
const TANK: String = "unit.napc.guardian_tank"
const LANDING: String = "unit.shared.landing_transport"


func _lake() -> PackedStringArray:
	var rows: PackedStringArray = A.MV.grid(64)
	A.MV.rect(rows, 24, 16, 44, 44, "~")
	return rows


func _mcv_id(w: SimWorld) -> String:
	for u: DefUnit in w.data.units:
		if u.has_ability(DefEnums.AbilityKind.DEPLOY_STRUCTURE):
			return u.id
	return ""


func test_s12_capacities(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	if not t.not_null(w, "world"):
		return
	var apc: SimEntity = A.spawn(w, APC, 0, 20, 20)
	t.check(apc.cargo != null, "an APC has a cargo component")
	t.eq(apc.cargo.cap_slots, 2, "cap 2")
	var s: Array[SimEntity] = []
	for i: int in 4:
		s.append(A.spawn(w, RIFLE, 0, 20 + i, 22))
	t.check(SimTransport.board(w, apc, s[0]), "first squad boards")
	t.check(SimTransport.board(w, apc, s[1]), "second squad boards")
	t.check(not SimTransport.can_board(w, apc, s[2]), "third squad refused by the APC")
	t.eq(SimTransport.free_slots(apc), 0, "no slot left")
	t.check((s[0].flags & SimFlags.F_INSIDE) != 0 and s[0].container_id == apc.id, "passenger inside, container set")
	t.check(not w.spatial.contains(s[0].id), "passenger left the spatial hash")
	t.eq(SimTransport.cargo_of(apc), PackedInt32Array([s[0].id, s[1].id]), "load order")
	t.check(w.abilities.is_immobile(apc), "carrier held for load_t after boarding")
	# an enemy squad and an already loaded one are refused
	var foe: SimEntity = A.spawn(w, RIFLE, 1, 21, 24)
	t.check(not SimTransport.can_board(w, apc, foe), "enemy squad refused")
	t.check(not SimTransport.can_board(w, apc, s[0]), "already inside")
	# Okapi 3, Leviathan 4
	var w2: SimWorld = A.world({"rosters": ["roster.ae.kongo", "roster.pd.vanilla"], "movement": false})
	var ok: SimEntity = A.spawn(w2, "unit.ae.okapi_amphibious_carrier", 0, 20, 20)
	var lev: SimEntity = A.spawn(w2, "unit.pd.leviathan_assault_carrier", 1, 30, 20)
	var oks: int = 0
	var levs: int = 0
	for i2: int in 6:
		if SimTransport.board(w2, ok, A.spawn(w2, "unit.ae.civic_rifle_team", 0, 20 + i2, 24)):
			oks += 1
		if SimTransport.board(w2, lev, A.spawn(w2, "unit.pd.rifle_squad" if A.uid("unit.pd.rifle_squad") >= 0 else _pd_inf(w2), 1, 30 + i2, 26)):
			levs += 1
	t.eq(oks, 3, "Okapi accepts 3")
	t.eq(levs, 4, "Leviathan accepts 4")


func _pd_inf(w: SimWorld) -> String:
	for u: DefUnit in w.data.units:
		if u.faction == 6 and (u.tags & DefEnums.UT_INFANTRY) != 0 and w.players[1].roster.has_unit(u.index):
			return u.id
	return ""


func test_s12_landing_transport(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.canada", "roster.nec.vanilla"], "movement": false})
	var lt: SimEntity = A.spawn(w, LANDING, 0, 10, 10)
	t.eq(lt.cargo.cap_slots, 4, "landing transport: 4 squads")
	var n: int = 0
	for i: int in 5:
		if SimTransport.board(w, lt, A.spawn(w, RIFLE, 0, 12 + i, 12)):
			n += 1
	t.eq(n, 4, "4 squads")
	t.eq(SimTransport.free_slots(lt), 0, "full")
	# two tanks
	var lt2: SimEntity = A.spawn(w, LANDING, 0, 10, 20)
	var t1: SimEntity = A.spawn(w, TANK, 0, 12, 22)
	var t2: SimEntity = A.spawn(w, TANK, 0, 14, 22)
	var t3: SimEntity = A.spawn(w, TANK, 0, 16, 22)
	t.check(SimTransport.board(w, lt2, t1), "first tank (2 slots)")
	t.check(SimTransport.board(w, lt2, t2), "second tank")
	t.check(not SimTransport.can_board(w, lt2, t3), "third tank refused")
	# one vehicle + two squads
	var lt3: SimEntity = A.spawn(w, LANDING, 0, 10, 30)
	t.check(SimTransport.board(w, lt3, A.spawn(w, TANK, 0, 12, 32)), "tank")
	t.check(SimTransport.board(w, lt3, A.spawn(w, RIFLE, 0, 13, 32)), "squad 1")
	t.check(SimTransport.board(w, lt3, A.spawn(w, RIFLE, 0, 14, 32)), "squad 2")
	t.check(not SimTransport.can_board(w, lt3, A.spawn(w, RIFLE, 0, 15, 32)), "no room for a third squad")
	# exclusions: MCV, amphibious Beaver, another transport
	var lt4: SimEntity = A.spawn(w, LANDING, 0, 10, 40)
	var mcv_id: String = _mcv_id(w)
	t.check(mcv_id != "", "an MCV def exists")
	t.check(not SimTransport.can_board(w, lt4, A.spawn(w, mcv_id, 0, 12, 42)), "MCV refused")
	t.check(not SimTransport.can_board(w, lt4, A.spawn(w, "unit.napc.beaver_amphibious_apc", 0, 13, 42)), "amphibious Beaver refused")
	t.check(not SimTransport.can_board(w, lt4, A.spawn(w, LANDING, 0, 14, 42)), "a second landing transport refused")
	t.check(not SimTransport.can_board(w, lt4, A.spawn(w, APC, 0, 15, 42)), "APCs are transports: refused")
	t.check(SimTransport.can_board(w, lt4, A.spawn(w, "unit.shared.engineer", 0, 16, 42)), "an Engineer squad boards like any infantry")
	# an APC only carries infantry
	var apc: SimEntity = A.spawn(w, APC, 0, 30, 30)
	t.check(not SimTransport.can_board(w, apc, A.spawn(w, TANK, 0, 32, 30)), "APC: no vehicles")


func test_unload_cadence_and_exit_cells(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var apc: SimEntity = A.spawn(w, APC, 0, 30, 30)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 31, 33)
	var b: SimEntity = A.spawn(w, RIFLE, 0, 32, 33)
	SimTransport.board(w, apc, a)
	SimTransport.board(w, apc, b)
	A.run(w, 3)
	t.eq(a.x, apc.x, "passengers mirror the carrier")
	var interval: int = SimTransport.unload_interval(w, apc)
	t.eq(interval, 20, "unload_t 20 for the Pathfinder")
	var t0: int = w.tick
	t.check(SimTransport.begin_unload(w, apc, 1, -1, -1, -1), "unload accepted while standing still")
	A.run(w, interval + 1)
	t.eq(SimTransport.cargo_of(apc).size(), 1, "one squad out after unload_t")
	t.eq(A.event_field(w, K.EV_UNLOADED, 0, SimEvent.I_TICK), t0 + interval, "first exit exactly one interval after the order")
	# ring 1, east first: the cell east of the carrier
	t.eq(a.x >> 10, 31, "first exit cell is the east neighbour")
	t.eq(a.y >> 10, 30, "same row")
	t.check((a.flags & SimFlags.F_INSIDE) == 0 and a.container_id == -1, "outside again")
	t.check(w.spatial.contains(a.id), "back in the spatial hash")
	A.run(w, interval)
	t.eq(SimTransport.cargo_of(apc).size(), 0, "second squad out")
	t.eq(A.event_field(w, K.EV_UNLOADED, 1, SimEvent.I_TICK), t0 + 2 * interval, "cadence one squad per unload_t")
	t.eq(b.x >> 10, 31, "the second squad also finds a free slot on ring 1 (east cell holds < 4 units)")
	t.eq(apc.cargo.unload_mode, 0, "unloading finished")
	t.eq(A.slot_state(apc, K.AK_TRANSPORT), 0, "slot back to IDLE")


func test_unload_one_and_blocked(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var apc: SimEntity = A.spawn(w, APC, 0, 30, 30)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 31, 33)
	var b: SimEntity = A.spawn(w, RIFLE, 0, 32, 33)
	SimTransport.board(w, apc, a)
	SimTransport.board(w, apc, b)
	t.check(not SimTransport.begin_unload(w, apc, 2, 9999, -1, -1), "a stranger is no passenger")
	t.check(SimTransport.begin_unload(w, apc, 2, b.id, -1, -1), "unload the second squad only")
	A.run(w, 25)
	t.eq(SimTransport.cargo_of(apc), PackedInt32Array([a.id]), "only b left")
	t.check((b.flags & SimFlags.F_INSIDE) == 0, "b is out")
	# fully blocked: a carrier in a cliff pocket has no exit
	var rows: PackedStringArray = A.MV.grid(64)
	A.MV.rect(rows, 28, 28, 34, 34, "#")
	A.MV.rect(rows, 31, 31, 31, 31, ".")
	var w2: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false, "rows": rows})
	var apc2: SimEntity = A.spawn(w2, APC, 0, 31, 31)
	var c: SimEntity = A.spawn(w2, RIFLE, 0, 20, 20)
	SimTransport.board(w2, apc2, c)
	t.check(SimTransport.begin_unload(w2, apc2, 1, -1, -1, -1), "accepted")
	A.run(w2, 30)
	t.eq(A.count_events(w2, K.EV_UNLOAD_BLOCKED, apc2.id), 1, "EV_UNLOAD_BLOCKED")
	t.eq(SimTransport.cargo_of(apc2).size(), 1, "the passenger stays")
	t.eq(apc2.cargo.unload_mode, 0, "the order ended")


func test_unload_cadence_variants(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.pd.indonesia", "roster.sap.thailand"], "movement": false})
	var kancil: SimEntity = A.spawn(w, "unit.pd.kancil_landing_skimmer", 0, 20, 20)
	t.eq(SimTransport.unload_interval(w, kancil), 13, "Kancil unloads 50 % faster (20 -> 13)")
	var naga: SimEntity = A.spawn(w, "unit.sap.naga_amphibious_carrier", 1, 30, 30)
	t.eq(SimTransport.unload_interval(w, naga), 20, "Naga base")
	var r: int = w.data.research_idx("research.sap.rapid_ferry_drills")
	w.players[1].view.layer3.apply_research(r)
	t.eq(SimTransport.unload_interval(w, naga), 12, "Rapid Ferry Drills: 20 x 60 % = 12")
	t.eq(w.abilities.sp(w, naga, naga.abil.slot_of_kind(K.AK_TRANSPORT), "load_t", 0), 12, "and the loading time too")


func test_eject_all_losses_and_drowning(t: TestCtx) -> void:
	var rows: PackedStringArray = _lake()
	var w: SimWorld = A.world({"rosters": ["roster.napc.canada", "roster.nec.vanilla"], "movement": false, "rows": rows})
	# an APC dies on land: everyone comes out with 40 % less health
	var apc: SimEntity = A.spawn(w, APC, 0, 12, 12)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 14, 14)
	SimTransport.board(w, apc, a)
	var hp_max: int = a.hp_max
	SimTransport.eject_all(w, apc, SimTransport.eject_loss_bp(w, apc))
	t.eq(SimTransport.eject_loss_bp(w, apc), 4000, "transport default loss 4000 bp")
	t.eq(a.hp, hp_max - SimDamage.mul(hp_max, 4000), "40 %% of max health lost")
	t.check((a.flags & SimFlags.F_INSIDE) == 0, "outside")
	t.eq(apc.cargo.n_pax, 0, "cargo empty")
	t.eq(A.count_events(w, K.EV_EJECTED, a.id), 1, "EV_EJECTED")
	# the Beaver: 2000
	var beaver: SimEntity = A.spawn(w, "unit.napc.beaver_amphibious_apc", 0, 16, 16)
	t.eq(SimTransport.eject_loss_bp(w, beaver), 2000, "Beaver: reinforced passenger protection")
	# never below 1 hp
	var weak: SimEntity = A.spawn(w, RIFLE, 0, 18, 18)
	weak.hp = 3
	SimTransport.board(w, apc, weak)
	SimTransport.eject_all(w, apc, 9000)
	t.eq(weak.hp, 1, "at least 1 hp")
	# a Landing Transport dies over deep water: land infantry has no exit cell within ring 3 and drowns
	var lt: SimEntity = A.spawn(w, LANDING, 0, 34, 30)
	var swimmer: SimEntity = A.spawn(w, RIFLE, 0, 14, 20)
	SimTransport.board(w, lt, swimmer)
	w.kill(lt, SimWorld.Cause.DAMAGE, 0, 1)
	A.run(w, 3)
	t.eq(A.count_events(w, K.EV_DROWNED, swimmer.id), 1, "EV_DROWNED")
	t.check(not w.is_alive(swimmer.id) or (swimmer.flags & SimFlags.F_GONE) != 0, "the passenger drowned (killed through CAUSE_CARGO)")


func test_container_death_through_combat(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var apc: SimEntity = A.spawn(w, APC, 0, 30, 30)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 31, 33)
	var b: SimEntity = A.spawn(w, RIFLE, 0, 32, 33)
	SimTransport.board(w, apc, a)
	SimTransport.board(w, apc, b)
	var hp_a: int = a.hp_max
	w.kill(apc, SimWorld.Cause.DAMAGE, 0, 1)
	A.run(w, 3)
	t.check(w.is_alive(a.id) and w.is_alive(b.id), "passengers survive their carrier")
	t.check((a.flags & SimFlags.F_INSIDE) == 0 and a.container_id == -1, "and stand on the map")
	t.eq(a.hp, hp_a - SimDamage.mul(hp_a, 4000), "40 % lost")
	t.gt(a.hp, 0, "alive")
	t.eq(w.abilities.debug_validate(w).size(), 0, "debug_validate clean")


func test_sold_carrier_unloads_unharmed(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var apc: SimEntity = A.spawn(w, APC, 0, 30, 30)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 31, 33)
	SimTransport.board(w, apc, a)
	w.remove_entity(apc.id, SimEvent.REM_CONSUMED)
	A.run(w, 2)
	t.check(w.is_alive(a.id) and (a.flags & SimFlags.F_INSIDE) == 0, "passenger out")
	t.eq(a.hp, a.hp_max, "no loss when the carrier is consumed")


func test_passenger_dies_inside(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var apc: SimEntity = A.spawn(w, APC, 0, 30, 30)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 31, 33)
	var b: SimEntity = A.spawn(w, RIFLE, 0, 32, 33)
	SimTransport.board(w, apc, a)
	SimTransport.board(w, apc, b)
	w.kill(a, SimWorld.Cause.SCRIPT, 0, -1)
	A.run(w, 3)
	t.eq(apc.cargo.n_pax, 1, "the dead passenger left the list")
	t.eq(apc.cargo.used_slots, 1, "and its slot is free")
	t.eq(SimTransport.cargo_of(apc), PackedInt32Array([b.id]), "order kept")


func test_captured_carrier_ejects(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var apc: SimEntity = A.spawn(w, APC, 0, 30, 30)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 31, 33)
	SimTransport.board(w, apc, a)
	w.change_owner(apc.id, 1)
	A.run(w, 2)
	t.check((a.flags & SimFlags.F_INSIDE) == 0, "passengers do not ride with the new owner")
	t.eq(a.owner, 0, "and keep their owner")


func test_s13_garrison(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.olm.el_andalus", "roster.nec.vanilla"], "movement": false})
	var g: SimEntity = A.neutral(w, "neutral.civilian_garrison", 30, 30)
	t.check(g.cargo != null and g.cargo.cap_slots == 4, "a civilian garrison holds 4 squads")
	var sq: Array[SimEntity] = []
	for i: int in 5:
		sq.append(A.spawn(w, "unit.olm.gate_guard" if A.uid("unit.olm.gate_guard") >= 0 else RIFLE, 0, 26 + i, 26))
	var n: int = 0
	for s: SimEntity in sq:
		if SimTransport.garrison_enter(w, g, s):
			n += 1
	t.eq(n, 4, "4 squads, the 5th is refused")
	t.eq(w.abilities.garrison_claim_team(g), w.team_of(0), "claim = the occupying team")
	var foe: SimEntity = A.spawn(w, RIFLE, 1, 26, 34)
	t.check(not SimTransport.can_board(w, g, foe), "enemy squad refused while claimed")
	t.check(w.abilities.in_garrison(sq[0]), "DF_IN_GARRISON set")
	t.check((sq[0].abil.cond_ext >> DefEnums.Cond.IN_CIVILIAN_GARRISON) & 1 == 1, "condition IN_CIVILIAN_GARRISON pushed")
	t.check((g.flags & SimFlags.F_GARRISONED) != 0, "occupied building flag")
	t.eq(A.count_events(w, K.EV_GARRISON_CHANGED), 4, "one EV_GARRISON_CHANGED per entry")
	# everybody out: the claim is released
	w.submit_raw(0, SimCmd.build(SimCmd.UNLOAD, [0, 0, g.x, g.y], PackedInt32Array([g.id])))
	A.run(w, 4 * 12 + 4)
	t.eq(g.cargo.n_pax, 0, "the garrison is empty after the unload command")
	t.eq(w.abilities.garrison_claim_team(g), -1, "claim released with the last squad")
	t.check(not w.abilities.in_garrison(sq[0]), "DF_IN_GARRISON cleared")
	t.check(SimTransport.can_board(w, g, foe), "the enemy may enter a free garrison")


func test_garrison_destroyed_ejects(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.olm.el_andalus", "roster.nec.vanilla"], "movement": false})
	var g: SimEntity = A.neutral(w, "neutral.civilian_garrison", 30, 30)
	var s: SimEntity = A.spawn(w, RIFLE, 0, 26, 26)
	var low: SimEntity = A.spawn(w, RIFLE, 0, 27, 26)
	low.hp = 2
	SimTransport.garrison_enter(w, g, s)
	SimTransport.garrison_enter(w, g, low)
	t.eq(SimTransport.eject_loss_bp(w, g), 3500, "garrison loss 3500 bp")
	var hp_max: int = s.hp_max
	w.kill(g, SimWorld.Cause.DAMAGE, 0, 1)
	A.run(w, 3)
	t.check((s.flags & SimFlags.F_INSIDE) == 0 and w.is_alive(s.id), "the squad comes out")
	t.eq(s.hp, hp_max - SimDamage.mul(hp_max, 3500), "35 % of max health lost")
	t.eq(low.hp, 1, "never below 1 hp")
	t.check(not w.abilities.in_garrison(s), "no longer garrisoned")


func test_s11_cargo_orders(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.canada", "roster.nec.vanilla"], "rows": _lake()})
	var lt: SimEntity = A.spawn(w, LANDING, 0, 26, 30)  # 2 cells off the shore edge (land ends at cell 23)
	var squads: Array[SimEntity] = []
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 4:
		var s: SimEntity = A.spawn(w, RIFLE, 0, 16, 28 + i)
		squads.append(s)
		ids.append(s.id)
	w.submit_raw(0, SimCmd.build(SimCmd.LOAD, [lt.id, 0], ids))
	var t_issue: int = w.tick
	var done: int = A.run_until(w, func() -> bool: return lt.cargo.n_pax == 4, 400)
	t.gt(done, -1, "all four squads boarded (n=%d)" % lt.cargo.n_pax)
	t.check(lt.cargo.n_pax == 4 and (squads[3].flags & SimFlags.F_INSIDE) != 0, "everybody is inside")
	t.eq(A.count_events(w, K.EV_LOADED), 4, "EV_LOADED x 4")
	t.check(squads[0].orders.is_empty(), "the LOAD orders are done")
	t.check(w.abilities.is_immobile(lt), "carrier waits load_t after a boarding")
	t.gt(t_issue, -1, "issue tick recorded")
	# a carrier far out at sea cannot be reached: the order fails
	var far: SimEntity = A.spawn(w, LANDING, 0, 34, 24)
	var lone: SimEntity = A.spawn(w, RIFLE, 0, 16, 40)
	w.submit_raw(0, SimCmd.build(SimCmd.LOAD, [far.id, 0], PackedInt32Array([lone.id])))
	A.run(w, 200)
	t.eq(far.cargo.n_pax, 0, "nobody boarded the far carrier")
	t.check(lone.orders.is_empty(), "the order ended")
	t.gt(A.count_events(w, SimEvent.ORDER_FAILED, lone.id), 0, "ORDER_FAILED reported")


func test_unload_command_moves_and_unloads(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var apc: SimEntity = A.spawn(w, APC, 0, 20, 20)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 21, 22)
	SimTransport.board(w, apc, a)
	# the carrier is driving east; UNLOAD (in place) stops it and unloads
	w.submit_raw(0, SimCmd.build(SimCmd.MOVE, [45 * 1024, 20 * 1024 + 512, 0, 0], PackedInt32Array([apc.id])))
	A.run(w, 40)
	t.gt(apc.x, 22 * 1024, "the APC is driving")
	w.submit_raw(0, SimCmd.build(SimCmd.UNLOAD, [0, 0, apc.x, apc.y], PackedInt32Array([apc.id])))
	A.run(w, 120)
	t.eq(apc.cargo.n_pax, 0, "unloaded after stopping")
	t.check((a.flags & SimFlags.F_INSIDE) == 0, "passenger out")
	t.check(apc.orders.is_empty(), "the UNLOAD order finished")


func test_unload_reject_reasons(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false})
	var apc: SimEntity = A.spawn(w, APC, 0, 20, 20)
	var c: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.UNLOAD, [0, 0, apc.x, apc.y], PackedInt32Array([apc.id])))
	c.actors = [apc]
	t.eq(SimAbilityCmds.execute(w, c), SimCommand.Err.NOT_ALLOWED, "empty carrier: nothing to unload")
	t.eq(c.detail, SimAbilityEvents.RJ_BAD_STATE, "BAD_STATE")
	var a: SimEntity = A.spawn(w, RIFLE, 0, 21, 22)
	SimTransport.board(w, apc, a)
	var c2: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.UNLOAD, [1, 9999, apc.x, apc.y], PackedInt32Array([apc.id])))
	c2.actors = [apc]
	t.eq(SimAbilityCmds.execute(w, c2), SimCommand.Err.NO_TARGET, "unknown passenger")
	t.eq(c2.detail, SimAbilityEvents.RJ_BAD_TARGET, "BAD_TARGET")
	# moving carrier
	apc.flags |= SimFlags.F_MOVING
	t.eq(SimTransport.unload_reject(w, apc, 1, -1), SimAbilityEvents.RJ_NOT_STATIONARY, "NOT_STATIONARY while driving")
	# no room at the carrier for a stranger's squad: the load command
	var b: SimEntity = A.spawn(w, RIFLE, 0, 22, 22)
	var c3: SimEntity = A.spawn(w, RIFLE, 0, 23, 22)
	SimTransport.board(w, apc, b)
	t.eq(SimTransport.board_reject(w, apc, c3), SimAbilityEvents.RJ_NO_ROOM, "NO_ROOM")
	apc.combat.emp_until = w.tick + 100
	t.eq(SimTransport.board_reject(w, apc, c3), SimAbilityEvents.RJ_NO_ROOM, "room is checked before the shutdown")


func test_disembark_buffs(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.pd.indonesia", "roster.sap.thailand"], "movement": false})
	var apc: SimEntity = A.spawn(w, "unit.pd.kancil_landing_skimmer", 0, 20, 20)
	var raider: SimEntity = A.spawn(w, "unit.pd.island_raider", 0, 21, 22)
	SimTransport.board(w, apc, raider)
	A.run(w, 3)
	t.eq(A.lease_bp(w, raider, C.STAT_DMG_OUT), 0, "no buff while aboard")
	SimTransport.begin_unload(w, apc, 1, -1, -1, -1)
	A.run(w, 14)
	t.check((raider.flags & SimFlags.F_INSIDE) == 0, "unloaded")
	t.eq(A.lease_bp(w, raider, C.STAT_DMG_OUT), 2000, "Island Raider: DMG_OUT +2000 after unloading")
	t.check((raider.abil.cond_ext >> DefEnums.Cond.RECENTLY_DISEMBARKED) & 1 == 1, "RECENTLY_DISEMBARKED condition")
	var until: int = raider.abil.disembark_until
	# re-boarding and unloading inside the window changes nothing
	SimTransport.board(w, apc, raider)
	A.run(w, 3)
	SimTransport.begin_unload(w, apc, 1, -1, -1, -1)
	A.run(w, 14)
	t.eq(raider.abil.disembark_until, until, "reboarding cannot refresh the buff")
	A.run_to(w, until + 2)
	t.eq(A.lease_bp(w, raider, C.STAT_DMG_OUT), 0, "the buff ends after 120 ticks")
	t.check((raider.abil.cond_ext >> DefEnums.Cond.RECENTLY_DISEMBARKED) & 1 == 0, "condition cleared")
	# River Marine: damage taken -20 %
	var naga: SimEntity = A.spawn(w, "unit.sap.naga_amphibious_carrier", 1, 40, 40)
	var marine: SimEntity = A.spawn(w, "unit.sap.river_marine", 1, 41, 42)
	SimTransport.board(w, naga, marine)
	A.run(w, 3)
	SimTransport.begin_unload(w, naga, 1, -1, -1, -1)
	A.run(w, 22)
	t.eq(A.lease_bp(w, marine, C.STAT_TAKEN), 2000, "River Marine: TAKEN 2000")


func test_cargo_determinism(t: TestCtx) -> void:
	var sums: PackedInt64Array = PackedInt64Array()
	for _run: int in 2:
		var w: SimWorld = A.world({"rosters": ["roster.napc.canada", "roster.nec.vanilla"], "rows": _lake()})
		var lt: SimEntity = A.spawn(w, LANDING, 0, 26, 30)
		var ids: PackedInt32Array = PackedInt32Array()
		for i: int in 4:
			ids.append(A.spawn(w, RIFLE, 0, 16, 28 + i).id)
		w.submit_raw(0, SimCmd.build(SimCmd.LOAD, [lt.id, 0], ids))
		A.run(w, 200)
		w.submit_raw(0, SimCmd.build(SimCmd.UNLOAD, [0, 0, lt.x, lt.y], PackedInt32Array([lt.id])))
		A.run(w, 150)
		sums.append(w.checksum())
	t.eq(sums[0], sums[1], "double run: identical checksum")


func test_garrisoned_squads_see_and_fire(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false, "fog": true})
	var g: SimEntity = A.neutral(w, "neutral.civilian_garrison", 30, 30)
	var s: SimEntity = A.spawn(w, RIFLE, 0, 26, 26)
	t.check(SimTransport.garrison_enter(w, g, s), "the squad garrisons the building")
	var foe: SimEntity = A.spawn(w, TANK, 1, 34, 30)
	A.run(w, 12)
	t.check(w.fog.entity_visible(0, foe), "an enemy inside the squad's sight is visible to the claimant")
	var hp0: int = foe.hp
	A.run(w, 200)
	t.lt(foe.hp, hp0, "occupants fire out of the building (garrison_fire)")
	t.gt(s.combat.last_fire_tick, 0, "the squad fired")
	# an ordinary passenger never fires
	var apc: SimEntity = A.spawn(w, APC, 0, 40, 40)
	var p: SimEntity = A.spawn(w, RIFLE, 0, 41, 42)
	var foe2: SimEntity = A.spawn(w, TANK, 1, 43, 40)
	SimTransport.board(w, apc, p)
	A.run(w, 100)
	t.lt(p.combat.last_fire_tick, 0, "transport passengers do not shoot")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "vision grids consistent")
	t.check(foe2.hp > 0, "sanity")


func test_amphibious_cargo_over_water(t: TestCtx) -> void:
	# a Beaver swims 2 cells off the shore; its infantry leaves on LAND (ring 3), never into the water
	var w: SimWorld = A.world({"rosters": ["roster.napc.canada", "roster.nec.vanilla"], "movement": false, "rows": _lake()})
	var beaver: SimEntity = A.spawn(w, "unit.napc.beaver_amphibious_apc", 0, 26, 30)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 14, 20)
	var b: SimEntity = A.spawn(w, RIFLE, 0, 15, 20)
	t.check(SimTransport.board(w, beaver, a) and SimTransport.board(w, beaver, b), "cargo is independent of terrain")
	t.check(SimTransport.begin_unload(w, beaver, 1, -1, -1, -1), "unload over water")
	A.run(w, 60)
	t.eq(beaver.cargo.n_pax, 0, "both out")
	for p: SimEntity in [a, b]:
		t.check(not w.map.is_water(p.x >> 10, p.y >> 10), "the squad stands on land, not in the water")
		t.eq(p.x >> 10, 23, "on the first land column within ring 3")
	# too far from any land: no exit cell
	var far: SimEntity = A.spawn(w, "unit.napc.beaver_amphibious_apc", 0, 34, 30)
	var c: SimEntity = A.spawn(w, RIFLE, 0, 16, 20)
	SimTransport.board(w, far, c)
	SimTransport.begin_unload(w, far, 1, -1, -1, -1)
	A.run(w, 40)
	t.eq(A.count_events(w, K.EV_UNLOAD_BLOCKED, far.id), 1, "no legal exit cell over deep water")
	t.eq(far.cargo.n_pax, 1, "the squad stays aboard")
	# an amphibious passenger may leave into the water
	var marine: SimEntity = A.spawn(w, "unit.sap.river_marine", 0, 18, 20)
	var mu: DefUnit = w.abilities.unit_def(w, marine)
	if mu.move_class == MapTerrain.MC_AMPHIBIOUS:
		SimTransport.board(w, far, marine)
		far.cargo.unload_mode = 0
		var cell: int = SimTransport.find_exit_cell(w, far, marine, -1, -1)
		t.ge(cell, 0, "amphibious infantry finds a cell in the water")


func test_mobile_reserve_unload_while_moving(t: TestCtx) -> void:
	# no shipped sheet sets unload_moving_speed_bp (the Mobile Reserve research is data-side), so a private copy of the data
	# gives the Pathfinder 50 % speed while unloading
	var d: GameData = GameData.load_from_paths(GameData.BIBLE_PATH, GameData.BALANCE_DIR)  # uncached: the shared copy stays clean
	var uid: int = d.unit_idx(APC)
	var lists: Array = [d.units[uid].abilities]
	for r: DefRoster in d.rosters:
		if r.has_unit(uid):
			lists.append(r.unit(uid).abilities)
	for lst: Variant in lists:
		for ab: DefAbility in lst:
			if ab.kind == DefEnums.AbilityKind.TRANSPORT:
				ab.params["unload_moving_speed_bp"] = 5000
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "data": d})
	var apc: SimEntity = A.spawn(w, APC, 0, 20, 20)
	var a: SimEntity = A.spawn(w, RIFLE, 0, 21, 22)
	SimTransport.board(w, apc, a)
	w.submit_raw(0, SimCmd.build(SimCmd.MOVE, [58 * 1024, 20 * 1024 + 512, 0, 0], PackedInt32Array([apc.id])))
	A.run(w, 60)
	var v_full: int = w.abilities.speed_units(apc)
	t.check(apc.cargo.n_pax == 1 and (apc.flags & SimFlags.F_MOVING) != 0, "driving with cargo")
	t.check(SimTransport.begin_unload(w, apc, 1, -1, -1, -1), "unloading while moving is legal with Mobile Reserve")
	t.check((apc.stats.flags & K.DF_UNLOAD_MOVING) != 0, "DF_UNLOAD_MOVING")
	A.run(w, 2)
	t.eq(w.abilities.speed_units(apc), v_full * 5000 / 10000, "carrier speed x0.5 while unloading")
	A.run(w, 25)
	t.eq(apc.cargo.n_pax, 0, "the squad stepped out of the moving carrier")
	t.check((apc.stats.flags & K.DF_UNLOAD_MOVING) == 0, "flag cleared")
	A.run(w, 2)
	t.eq(w.abilities.speed_units(apc), v_full, "and the speed is back")


func test_el_andalus_garrison_bonus(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.olm.el_andalus", "roster.nec.vanilla"], "movement": false})
	var g: SimEntity = A.neutral(w, "neutral.civilian_garrison", 30, 30)
	var ca: DefCondApplication = null
	for c: DefCondApplication in w.players[0].roster.conditional_applications():
		if c.cond == DefEnums.Cond.IN_CIVILIAN_GARRISON:
			ca = c
	t.not_null(ca, "El-Andalus carries the garrison modifier")
	var guard: SimEntity = A.spawn(w, w.data.units[ca.units[0]].id, 0, 26, 26)
	t.eq(A.lease_bp(w, guard, C.STAT_DMG_OUT), 0, "no bonus outside")
	SimTransport.garrison_enter(w, g, guard)
	t.eq(A.lease_bp(w, guard, C.STAT_DMG_OUT), ca.delta_bp, "+%d bp damage while garrisoned (the sheet's number)" % ca.delta_bp)
	t.eq(ca.delta_bp, 2000, "+20 %%")
	SimTransport.begin_unload(w, g, 1, -1, -1, -1)
	A.run(w, 25)
	t.eq(A.lease_bp(w, guard, C.STAT_DMG_OUT), 0, "and it ends when the squad leaves")
