extends RefCounted
## `UiSimPortFixture` obeys the `UiSimPort` contract and derives progress from time (ui.md 7.12, 10.2).

const Contract := preload("res://tests/ui/contract_ui_sim_port.gd")
const HUD: String = "hud_mid_match"


func test_contract_on_hud_fixture(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.load_file(HUD)
	if not t.not_null(f, "fixture loads"):
		return
	Contract.check(t, f, "fixture")


func test_loaded_values(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.load_file(HUD)
	t.eq(f.credits(), 12450)
	t.eq(f.harvested_total(), 61000)
	t.eq(f.power_supply(), 300)
	t.eq(f.power_demand(), 265)
	t.eq(f.tick(), 15200)
	t.eq(f.name_of(1), "AI 2")
	t.eq(f.team_of(2), 1)
	t.eq(f.rel(0, 2), UiSimPort.Rel.ALLY)
	t.eq(f.rel(0, 1), UiSimPort.Rel.ENEMY)
	var cs := PackedInt32Array()
	f.construction_state(cs)
	t.eq(cs[UiSimPort.CS_STATE], UiSimPort.Construction.BUILDING)
	t.eq(cs[UiSimPort.CS_PROGRESS], 372)
	t.eq(cs[UiSimPort.CS_ETA], 377, "eta from the JSON (372 permille, 377 ticks)")
	var q := PackedInt32Array()
	t.eq(f.construction_queue(q), 2)
	t.eq(f.queue_of(88, q), 2)
	var info := PackedInt32Array()
	f.queue_info(88, info)
	t.eq(info[UiSimPort.QI_PROGRESS], 620)
	t.eq(f.selected, PackedInt32Array([1001, 1002]))


func test_fog_and_visibility(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.load_file(HUD)
	t.check(f.can_target(2001), "visible enemy is targetable")
	t.check(not f.can_target(2002), "hidden enemy is not targetable")
	t.check(not f.can_target(2003), "remembered ghost is not targetable")
	var row := UiEntityRow.new()
	t.check(not f.read(2002, row), "an unseen enemy cannot be read (fog integrity)")
	t.check(f.read(2003, row) and (row.flags & UiEntityRow.F_GHOST) != 0, "a remembered ghost can")
	t.check(f.read(2001, row), "a visible enemy can")
	t.check(f.can_target(3001), "ally is always targetable")
	var snap := UiEntitySnapshot.new()
	f.snapshot(snap)
	t.check(snap.index_of(2002) < 0, "hidden enemy absent from the minimap snapshot")
	t.check(snap.index_of(2001) >= 0, "visible enemy present")
	var gi: int = snap.index_of(2003)
	t.check(gi >= 0 and (snap.flags[gi] & UiEntityRow.F_GHOST) != 0, "ghost present with F_GHOST")
	t.eq(snap.kind_of(gi), UiEntityRow.K_STRUCTURE)
	f.set_default_visibility(UiSimPort.Vis.FOG)
	t.eq(f.visibility(5, 5), UiSimPort.Vis.FOG)
	t.eq(f.deposit_at(48, 17), 2400, "explored deposit shows its amount")
	f.set_visibility(48, 17, UiSimPort.Vis.SHROUD)
	t.eq(f.deposit_at(48, 17), 0, "shrouded deposit is unknown")
	f.set_viewer_pid(-1)
	t.eq(f.visibility(48, 17), UiSimPort.Vis.VISIBLE, "omniscient observer sees everything")
	t.check(f.can_target(2002), "observer can target hidden entities")


func test_time_advances_progress(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.load_file(HUD)
	f.advance(100)
	var cs := PackedInt32Array()
	f.construction_state(cs)
	t.eq(f.tick(), 15300)
	t.gt(cs[UiSimPort.CS_PROGRESS], 372, "construction progressed")
	t.lt(cs[UiSimPort.CS_ETA], 377, "eta shrank")
	var before: int = cs[UiSimPort.CS_PROGRESS]
	f.advance(100)
	f.construction_state(cs)
	t.check(absi((cs[UiSimPort.CS_PROGRESS] - before) - (before - 372)) <= 2, "progress is linear in time")
	f.advance(400)
	f.construction_state(cs)
	t.eq(cs[UiSimPort.CS_STATE], UiSimPort.Construction.READY_TO_PLACE, "construction finishes")
	t.gt(cs[UiSimPort.CS_READY_DEF], -1)
	var ev: PackedInt32Array = f.take_events()
	var saw_ready: bool = false
	for i: int in UiEv.count(ev):
		if UiEv.field(ev, i, UiEv.I_TYPE) == UiEv.STRUCTURE_READY:
			saw_ready = true
	t.check(saw_ready, "EVT_STRUCTURE_READY emitted on completion")


func test_events_fire_at_tick(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.load_file(HUD)
	t.eq(f.take_events().size(), 0, "nothing is due at tick 15200")
	f.advance(10)
	var ev: PackedInt32Array = f.take_events()
	t.eq(UiEv.count(ev), 1)
	t.eq(UiEv.field(ev, 0, UiEv.I_TYPE), UiEv.ATTACK_ALERT)
	t.eq(UiEv.field(ev, 0, UiEv.I_TICK), 15210)
	t.eq(UiEv.field(ev, 0, UiEv.I_X), 70000)
	t.eq(UiEv.field(ev, 0, UiEv.I_B), 1001)
	t.eq(f.take_events().size(), 0, "taken once")
	f.advance(100)
	var ev2: PackedInt32Array = f.take_events()
	t.eq(UiEv.field(ev2, 0, UiEv.I_TYPE), UiEv.POWER_SHORTAGE)


func test_powers_and_warnings(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.load_file(HUD)
	var d: GameData = f.data()
	var uav: int = d.power_idx("power.napc.uav_sweep")
	var repair: int = d.power_idx("power.napc.field_repair_drop")
	t.eq(f.power_slot(uav), 0)
	t.eq(f.power_slot(repair), 1)
	t.eq(f.power_status(uav), UiSimPort.PowerStatus.COOLDOWN)
	t.eq(f.power_status(repair), UiSimPort.PowerStatus.READY)
	t.eq(f.power_total_cooldown_ticks(uav), 1800)
	f.advance(1300)
	t.eq(f.power_status(uav), UiSimPort.PowerStatus.READY, "cooldown ends at ready_tick")
	t.eq(f.sw_status(), UiSimPort.SwStatus.CHARGING)
	t.gt(f.sw_charge_permille(), 740)
	var w := PackedInt32Array()
	t.eq(f.strategic_warnings(w), 0, "warning not started at tick 16500")
	f.advance(500)
	t.eq(f.sw_status(), UiSimPort.SwStatus.READY, "superweapon ready after ready_tick")
	t.eq(f.strategic_warnings(w), 1, "warning active at tick 17000")
	t.eq(w[UiSimPort.WARN_STRIDE - 1], 17300, "exec tick is the last field")


func test_programmatic_build(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.blank()
	f.add_player(0, "Me", 1, "roster.napc.canada", 500)
	f.add_player(1, "Foe", 2, "roster.napc.canada")
	f.set_viewer(0)
	var tank: UiEntityRow = f.spawn("unit.napc.guardian_tank", 0, 10 * 1024, 10 * 1024)
	var foe: UiEntityRow = f.spawn("unit.napc.guardian_tank", 1, 20 * 1024, 10 * 1024)
	t.gt(tank.id, 1000)
	t.ne(tank.id, foe.id)
	t.check(f.can_attack(tank.id, foe.id, false), "armed unit can attack an enemy")
	f.remove_entity(foe.id)
	t.check(not f.alive(foe.id), "removed entity is gone")
	f.force_rule("check_train", UiSimPort.Rule.NO_PREREQ)
	t.eq(f.check_train(tank.id, 0), UiSimPort.Rule.NO_PREREQ)
	f.force_rule("check_train", -1)
	f.set_bad_site(3, 4, 5, 2)
	t.eq(f.check_place(3, 4, 5), UiSimPort.Rule.BAD_SITE)
	t.eq(f.place_reason(), 2)
	t.eq(f.check_place(3, 6, 6), UiSimPort.Rule.OK)
