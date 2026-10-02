extends RefCounted
## UI commands executed by a REAL SimWorld (ui.md 10.4): selection -> resolver -> command bus -> loopback net port ->
## `SimWorld.submit_raw` -> `step()`. Proves the move, attack, produce and place effects, and that `UiSimPortWorld`
## obeys the shared port contract on live data.

const Contract := preload("res://tests/ui/contract_ui_sim_port.gd")
const KIT := preload("res://tests/support/sim_econ_kit.gd")
const CELL: int = SimConfig.CELL


class Rig extends RefCounted:
	var w: SimWorld
	var port: UiSimPortWorld
	var net: UiNetPortLoopback
	var audio: UiAudioPortRecorder = UiAudioPortRecorder.new()
	var fb: UiFeedback = UiFeedback.new()
	var bus: UiCommandBus = UiCommandBus.new()
	var sel: UiSelection = UiSelection.new()

	func step(n: int = 1) -> void:
		for _i: int in n:
			w.step()

	## Resolves a right click on `tgt` for the current selection and dispatches it.
	func click(tgt: UiTarget, mods: int = 0) -> int:
		var info: UiSelectionInfo = UiSelectionInfo.build(sel, port)
		return bus.dispatch(UiContextResolver.resolve(info, tgt, mods, UiModes.Armed.NONE))


func _rig(credits: int = 9000) -> Rig:
	var r := Rig.new()
	r.w = KIT.make_world({"start_mode": 0, "rules": {"start_credits": credits}})
	r.port = UiSimPortWorld.new(r.w, 0)
	r.net = UiNetPortLoopback.new(r.w, 0)
	r.fb.setup(null, null, r.audio, null)
	r.bus.setup(r.net, r.port, null, r.audio, r.fb)
	return r


func _base(r: Rig) -> void:
	KIT.spawn_struct(r.w, DefTestKit.S_REFINERY, 0, 23, 22)
	KIT.spawn_struct(r.w, DefTestKit.S_GENERATOR, 0, 23, 19)
	KIT.spawn_struct(r.w, DefTestKit.S_BARRACKS, 0, 27, 19)
	r.w.step()


func _find_hq(r: Rig) -> SimEntity:
	for e: SimEntity in r.w.structures_of(0):
		if e.def_idx == r.w.players[0].roster.hq_idx:
			return e
	return null


func test_port_contract_on_a_live_world(t: TestCtx) -> void:
	var r: Rig = _rig()
	_base(r)
	SimTestKit.spawn_tank(r.w, 0, 30 * CELL, 30 * CELL)
	SimTestKit.spawn_rifle(r.w, 0, 31 * CELL, 30 * CELL)
	SimTestKit.spawn_rifle(r.w, 1, 60 * CELL, 60 * CELL)
	r.w.submit_raw(0, SimCmd.build_start(KIT.sidx(DefTestKit.S_FACTORY)))
	r.step(30)
	Contract.check(t, r.port, "world")


func test_rule_mapping_and_queue_state_tables(t: TestCtx) -> void:
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_OK), UiSimPort.Rule.OK)
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_PREREQ), UiSimPort.Rule.NO_PREREQ)
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_NO_HQ), UiSimPort.Rule.NO_PREREQ)
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_LOCKED), UiSimPort.Rule.NOT_AVAILABLE)
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_QUEUE_FULL), UiSimPort.Rule.QUEUE_FULL)
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_OUT_OF_RADIUS), UiSimPort.Rule.BAD_SITE)
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_NOT_EXPLORED), UiSimPort.Rule.NO_VISION)
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_COOLDOWN), UiSimPort.Rule.NOT_READY)
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_NO_POWER), UiSimPort.Rule.BLOCKED)
	t.eq(UiSimPortWorld.rule_of_rsn(SimEconConst.RSN_NOT_OWNER), UiSimPort.Rule.NOT_ALLOWED)
	t.eq(UiSimPortWorld.place_reason_of(SimEconConst.RSN_OUT_OF_RADIUS), 1)
	t.eq(UiSimPortWorld.place_reason_of(SimEconConst.RSN_UNIT_BLOCK), 2)
	t.eq(UiSimPortWorld.place_reason_of(SimEconConst.RSN_NEEDS_SHORE), 3)
	t.eq(UiSimPortWorld.place_reason_of(SimEconConst.RSN_STRATEGIC_LIMIT), 4)
	t.eq(UiSimPortWorld.place_reason_of(SimEconConst.RSN_NOT_EXPLORED), 5)
	t.eq(UiSimPortWorld.queue_state_of(SimEconConst.QS_HOLD, false), UiSimPort.QueueState.HELD)
	t.eq(UiSimPortWorld.queue_state_of(SimEconConst.QS_PAUSED_FUNDS, false), UiSimPort.QueueState.WAIT_FUNDS)
	t.eq(UiSimPortWorld.queue_state_of(SimEconConst.QS_ACTIVE, true), UiSimPort.QueueState.LOW_POWER)
	t.eq(UiSimPortWorld.queue_state_of(SimEconConst.QS_ACTIVE, false), UiSimPort.QueueState.RUNNING)
	t.eq(UiSimPortWorld.queue_state_of(SimEconConst.QS_PAUSED_PREREQ, false), UiSimPort.QueueState.PREREQ_LOST)


func test_rows_mirror_the_sim(t: TestCtx) -> void:
	var r: Rig = _rig()
	_base(r)
	var tank: SimEntity = SimTestKit.spawn_tank(r.w, 0, 30 * CELL, 30 * CELL)
	tank.hp -= 100
	var row := UiEntityRow.new()
	t.check(r.port.read(tank.id, row))
	t.eq(row.x, tank.x)
	t.eq(row.y, tank.y)
	t.eq(row.hp, tank.hp)
	t.eq(row.kind, UiEntityRow.K_UNIT)
	t.eq(row.order_kind, UiEntityRow.O_IDLE)
	t.eq(row.stance, tank.combat.stance)
	r.w.submit_raw(0, SimCmd.move(PackedInt32Array([tank.id]), 40 * CELL, 30 * CELL))
	r.step(3)
	r.port.read(tank.id, row)
	t.eq(row.order_kind, UiEntityRow.O_MOVING, "the move order shows as moving")
	var q := PackedInt32Array()
	t.eq(r.port.order_queue(tank.id, q), 1)
	t.eq(q[0], SimOrder.T_MOVE)
	t.eq(Vector2i(q[1], q[2]), Vector2i(40 * CELL, 30 * CELL))
	var hq: SimEntity = _find_hq(r)
	t.check(hq != null and r.port.read(hq.id, row))
	t.eq(row.kind, UiEntityRow.K_STRUCTURE)
	t.check((row.flags & UiEntityRow.F_STRUCT) != 0)
	var centers := PackedInt32Array()
	t.check(r.port.build_radius_centers(centers) >= 1, "the HQ extends the build radius")
	t.eq(Vector2i(centers[0], centers[1]), Vector2i(hq.x, hq.y))
	t.eq(r.port.credits(), r.w.players[0].credits)
	t.eq(r.port.rel(0, 1), UiSimPort.Rel.ENEMY)
	t.check(r.port.can_target(tank.id))
	t.check(r.port.alive(tank.id))
	r.w.kill(tank, SimWorld.Cause.DAMAGE, 0, 1)
	t.check(not r.port.alive(tank.id), "a killed entity is gone for the UI")
	t.check(not r.port.read(tank.id, row))


func test_move_order_effect(t: TestCtx) -> void:
	var r: Rig = _rig()
	var a: SimEntity = SimTestKit.spawn_tank(r.w, 0, 30 * CELL, 30 * CELL)
	var b: SimEntity = SimTestKit.spawn_rifle(r.w, 0, 31 * CELL, 30 * CELL)
	r.w.step()
	r.sel.replace(PackedInt32Array([b.id, a.id]), r.port)
	t.eq(r.sel.mode, UiSelection.Mode.UNITS)
	var goal := UiTarget.ground(50 * CELL + 512, 30 * CELL + 512)
	t.eq(r.click(goal), 1, "one MOVE command for the whole selection")
	t.eq(r.net.pending_count(), 1)
	r.step(2)
	for e: SimEntity in [a, b]:
		t.check(not e.orders.is_empty(), "entity %d has an order" % e.id)
		t.eq(e.orders[0].type, SimOrder.T_MOVE)
		t.eq(Vector2i(e.orders[0].x, e.orders[0].y), Vector2i(50 * CELL + 512, 30 * CELL + 512))
	var before: int = absi(a.x - (50 * CELL + 512))
	r.step(200)
	t.lt(absi(a.x - (50 * CELL + 512)), before, "the tank actually moved toward the goal")
	# Shift queues a second leg
	var goal2 := UiTarget.ground(50 * CELL, 45 * CELL)
	r.click(goal2, UiContextResolver.MOD_QUEUE)
	r.step(2)
	t.eq(a.orders.back().type, SimOrder.T_MOVE)
	t.eq(Vector2i(a.orders.back().x, a.orders.back().y), Vector2i(50 * CELL, 45 * CELL), "the queued leg was appended")
	t.check(a.orders.size() >= 2 or a.orders[0].x == 50 * CELL, "queue mode reached the sim")


func test_attack_order_effect(t: TestCtx) -> void:
	var r: Rig = _rig()
	var a: SimEntity = SimTestKit.spawn_tank(r.w, 0, 30 * CELL, 30 * CELL)
	var foe: SimEntity = SimTestKit.spawn_tank(r.w, 1, 45 * CELL, 30 * CELL)
	r.w.step()
	r.sel.replace(PackedInt32Array([a.id]), r.port)
	var row := UiEntityRow.new()
	r.port.read(foe.id, row)
	var tgt: UiTarget = UiContextResolver.from_row(r.port, row, 0, UiUnitCaps.shared_for(r.port))
	t.eq(tgt.kind, UiTarget.Kind.ENEMY)
	t.check(tgt.visible)
	var info: UiSelectionInfo = UiSelectionInfo.build(r.sel, r.port)
	t.check((info.caps_any & UiUnitCaps.CAP_ARMED) != 0, "the test tank is armed")
	var it: UiOrderIntent = UiContextResolver.resolve(info, tgt, 0, UiModes.Armed.NONE)
	t.eq(it.kind, UiOrderIntent.Kind.ATTACK)
	t.eq(r.bus.dispatch(it), 1)
	r.step(2)
	t.check(not a.orders.is_empty(), "the tank has an order")
	t.eq(a.orders[0].type, SimOrder.T_ATTACK, "the sim accepted ATTACK")
	t.eq(a.orders[0].target_id, foe.id)
	r.step(400)
	t.check(foe.hp < foe.hp_max or (foe.flags & SimFlags.F_GONE) != 0 or not r.w.is_alive(foe.id), "the attack order engaged the target")
	# attacking an own unit needs the force modifier
	var own: SimEntity = SimTestKit.spawn_rifle(r.w, 0, 33 * CELL, 30 * CELL)
	r.w.step()
	r.port.read(own.id, row)
	var own_t: UiTarget = UiContextResolver.from_row(r.port, row, 0, UiUnitCaps.shared_for(r.port))
	t.eq(own_t.kind, UiTarget.Kind.OWN)
	var forced: UiOrderIntent = UiContextResolver.resolve(info, own_t, UiContextResolver.MOD_FORCE, UiModes.Armed.NONE)
	t.check(forced.kind == UiOrderIntent.Kind.ATTACK and forced.force)
	r.net.submit(SimCmd.attack(PackedInt32Array([a.id]), own.id, 0, 0))
	r.step(2)
	t.check(a.orders.is_empty() or a.orders[0].target_id != own.id, "without the forced flag the sim refuses a friendly target")


func test_produce_order_effect(t: TestCtx) -> void:
	var r: Rig = _rig()
	_base(r)
	var barracks: PackedInt32Array = PackedInt32Array()
	t.check(r.port.producers(DefEnums.QueueKind.INFANTRY, barracks) >= 1, "the barracks is registered as an infantry producer")
	var rifle_def: int = KIT.uidx(DefTestKit.U_RIFLEMAN)
	t.eq(r.port.check_train(barracks[0], rifle_def), UiSimPort.Rule.OK)
	var credits_before: int = r.port.credits()
	var units_before: int = r.w.units_of(0).size()
	t.check(r.bus.train(barracks[0], rifle_def, 2), "TRAIN x2 goes through the bus")
	r.step(3)
	var q := PackedInt32Array()
	t.eq(r.port.queue_of(barracks[0], q), 2, "both units are queued in the sim")
	var info := PackedInt32Array()
	r.port.queue_info(barracks[0], info)
	t.gt(info[UiSimPort.QI_PROGRESS] + info[UiSimPort.QI_ETA], 0, "progress / eta are live")
	t.eq(info[UiSimPort.QI_RATE], 100)
	t.lt(r.port.credits(), credits_before, "payment is progressive")
	var n: int = 0
	while r.w.units_of(0).size() < units_before + 2 and n < 3000:
		r.w.step()
		n += 1
	t.eq(r.w.units_of(0).size(), units_before + 2, "both riflemen were produced (%d ticks)" % n)
	t.eq(r.port.queue_of(barracks[0], q), 0)
	# cancel refunds through the bus as well
	r.bus.train(barracks[0], rifle_def, 1)
	r.step(50)
	var mid: int = r.port.credits()
	t.check(r.bus.train_cancel_def(barracks[0], rifle_def))
	r.step(3)
	t.eq(r.port.queue_of(barracks[0], q), 0, "cancelled")
	t.gt(r.port.credits(), mid, "the paid part was refunded")


func test_place_structure_effect(t: TestCtx) -> void:
	var r: Rig = _rig(12000)
	_base(r)
	var factory: int = KIT.sidx(DefTestKit.S_FACTORY)
	t.eq(r.port.check_build(factory), UiSimPort.Rule.OK)
	t.check(r.bus.build_start(factory), "BUILD_START through the bus")
	r.step(2)
	var cs := PackedInt32Array()
	r.port.construction_state(cs)
	t.eq(cs[UiSimPort.CS_STATE], UiSimPort.Construction.BUILDING)
	t.eq(cs[UiSimPort.CS_DEF], factory)
	t.gt(cs[UiSimPort.CS_ETA], 0)
	t.eq(cs[UiSimPort.CS_RATE], 100)
	var n: int = 0
	while cs[UiSimPort.CS_STATE] != UiSimPort.Construction.READY_TO_PLACE and n < 2000:
		r.step(10)
		n += 10
		r.port.construction_state(cs)
	t.eq(cs[UiSimPort.CS_STATE], UiSimPort.Construction.READY_TO_PLACE, "the factory finishes")
	t.eq(cs[UiSimPort.CS_READY_DEF], factory)
	# find a legal top-left cell near the HQ through the port's own check (the ghost's validity check)
	var hq: SimEntity = _find_hq(r)
	var site: Vector2i = Vector2i(-1, -1)
	for ring: int in range(3, 9):
		for dx: int in range(-ring, ring + 1):
			for dy: int in [-ring, ring]:
				var cx: int = (hq.x >> 10) + dx
				var cy: int = (hq.y >> 10) + dy
				if site.x < 0 and r.port.check_place(factory, cx, cy, 0) == UiSimPort.Rule.OK:
					site = Vector2i(cx, cy)
	t.check(site.x >= 0, "a legal site exists near the HQ")
	t.eq(r.port.check_place(factory, -5, -5, 0), UiSimPort.Rule.BAD_SITE, "off-map is a bad site")
	t.gt(r.port.place_reason(), 0, "off-map has a reason")
	t.eq(r.port.check_place(factory, 90, 90, 0), UiSimPort.Rule.BAD_SITE)
	t.eq(r.port.place_reason(), 1, "reason: outside the build radius")
	var structs_before: int = r.w.structures_of(0).size()
	t.check(not r.bus.build_place(factory, 90, 90, 0), "an illegal site is refused by the bus")
	t.eq(r.audio.last_args(&"ui")[0], UiAudioPort.PLACE_FAIL)
	t.check(r.bus.build_place(factory, site.x, site.y, 0), "BUILD_PLACE at the legal site")
	r.step(3)
	t.eq(r.w.structures_of(0).size(), structs_before + 1, "the sim placed the structure")
	var placed: SimEntity = r.w.structures_of(0).back()
	t.eq(placed.def_idx, factory)
	var origin := PackedInt32Array([0, 0])
	SimPlacement.entity_origin(r.w, placed, origin)
	t.eq(Vector2i(origin[0], origin[1]), site, "top-left cell = the cell the UI sent")
	r.port.construction_state(cs)
	t.eq(cs[UiSimPort.CS_STATE], UiSimPort.Construction.IDLE, "the queue is free again")


func test_selection_survives_kill_and_sell_effect(t: TestCtx) -> void:
	var r: Rig = _rig()
	_base(r)
	var a: SimEntity = SimTestKit.spawn_tank(r.w, 0, 30 * CELL, 30 * CELL)
	var b: SimEntity = SimTestKit.spawn_tank(r.w, 0, 31 * CELL, 30 * CELL)
	r.w.step()
	r.sel.replace(PackedInt32Array([a.id, b.id]), r.port)
	r.w.kill(a, SimWorld.Cause.DAMAGE, 0, 1)
	r.w.step()
	var events: PackedInt32Array = r.port.take_events()
	var saw_death: bool = false
	for i: int in UiEv.count(events):
		if UiEv.field(events, i, UiEv.I_TYPE) == UiEv.DEATH:
			saw_death = true
			r.sel.on_removed(UiEv.field(events, i, UiEv.I_A), UiEv.REM_KILLED, -1)
	t.check(saw_death, "the death event reached the UI through the port")
	t.eq(r.sel.ids, PackedInt32Array([b.id]))
	# sell an owned structure through the armed SELL mode
	var refinery: SimEntity = null
	for e: SimEntity in r.w.structures_of(0):
		if e.def_idx == KIT.sidx(DefTestKit.S_REFINERY):
			refinery = e
	refinery.paid_cost = 1000
	t.gt(r.port.sell_value(refinery.id), 0, "sellable structure")
	var row := UiEntityRow.new()
	r.port.read(refinery.id, row)
	var tgt: UiTarget = UiContextResolver.from_row(r.port, row, 0, UiUnitCaps.shared_for(r.port))
	var credits_before: int = r.port.credits()
	var it: UiOrderIntent = UiContextResolver.resolve(UiSelectionInfo.new(), tgt, 0, UiModes.Armed.SELL)
	t.eq(it.kind, UiOrderIntent.Kind.SELL)
	t.eq(r.bus.dispatch(it), 1)
	r.step(3)
	t.check((refinery.flags & SimFlags.F_SELLING) != 0 or r.port.credits() > credits_before, "the sim started selling")


func test_fog_integrity_on_a_live_world(t: TestCtx) -> void:
	var r := Rig.new()
	r.w = KIT.make_world({"start_mode": 0, "rules": {"start_credits": 1000, "fog": 1}})
	r.port = UiSimPortWorld.new(r.w, 0)
	SimTestKit.spawn_rifle(r.w, 0, 20 * CELL, 20 * CELL)
	var foe: SimEntity = SimTestKit.spawn_rifle(r.w, 1, 80 * CELL, 80 * CELL)
	var near: SimEntity = SimTestKit.spawn_rifle(r.w, 1, 22 * CELL, 20 * CELL)
	r.step(6)
	var row := UiEntityRow.new()
	t.check(not r.port.can_target(foe.id), "an enemy far outside vision is not targetable")
	t.check(not r.port.read(foe.id, row), "and cannot be read live")
	t.check(r.port.can_target(near.id), "an enemy in sight is")
	t.check(r.port.read(near.id, row))
	t.eq(r.port.visibility(80, 80), UiSimPort.Vis.SHROUD, "unexplored")
	t.eq(r.port.visibility(20, 20), UiSimPort.Vis.VISIBLE)
	var snap := UiEntitySnapshot.new()
	r.port.snapshot(snap)
	t.check(snap.index_of(foe.id) < 0, "the minimap snapshot omits unseen enemies")
	t.check(snap.index_of(near.id) >= 0)
	Contract.check(t, r.port, "world-fog")
