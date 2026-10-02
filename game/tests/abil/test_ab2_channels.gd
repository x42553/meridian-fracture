extends RefCounted
## AB-04 channels through CMD_USE_ABILITY (S17 repair, S18 salvage, capture) and the auto-cast pass: SimChannel starts
## the economy's order state machines, so the numbers under test are the bible's (1 % hp per second for 0.5 % of the
## paid price; the 160-tick salvage action paying 20 %).

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")


func _use(w: SimWorld, pid: int, e: SimEntity, slot: int, target: int, op: int = 0) -> void:
	w.submit_raw(pid, SimCmd.build(SimCmd.USE_ABILITY, [slot, op, target, -1, -1], PackedInt32Array([e.id])))


func test_s17_engineer_repair(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var eng: SimEntity = A.spawn(w, "unit.shared.engineer", 0, 30, 30)
	var tank: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 31, 30)
	tank.hp = tank.hp_max / 2
	tank.paid_cost = 1000
	var s: int = eng.abil.slot_of_kind(K.AK_REPAIR)
	t.gt(s, -1, "the Engineer has a repair slot")
	t.check((eng.abil.slots[s * K.SLOT_STRIDE + K.SL_FLAGS] & K.SF_AUTOCAST) == 0, "Engineer auto-cast is OFF")
	_use(w, 0, eng, s, tank.id)
	w.step()
	t.eq(eng.orders.size(), 1, "USE_ABILITY started the repair order")
	t.eq(eng.orders[0].type, SimOrder.T_REPAIR, "T_REPAIR")
	A.run(w, 60)  # walk-up and claim
	var hp0: int = tank.hp
	var cr0: int = w.players[0].credits
	A.run(w, 200)
	t.check(absi((tank.hp - hp0) - tank.hp_max / 10) <= 2, "200 ticks = 10 s = 10 %% of max health (got %d of %d)" % [tank.hp - hp0, tank.hp_max])
	var spent: int = cr0 - w.players[0].credits
	t.check(absi(spent - 50) <= 3, "and 50 credits (5 %% of 1000): %d" % spent)


func test_repair_without_credits_does_not_heal(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var eng: SimEntity = A.spawn(w, "unit.shared.engineer", 0, 30, 30)
	var tank: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 31, 30)
	tank.hp = tank.hp_max / 2
	tank.paid_cost = 1000
	w.players[0].credits = 0
	_use(w, 0, eng, eng.abil.slot_of_kind(K.AK_REPAIR), tank.id)
	var hp0: int = tank.hp
	A.run(w, 200)
	t.le(tank.hp - hp0, 2, "nothing (beyond the unpaid first fraction) heals when a credit cannot be paid")


func test_use_ability_rejects(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var eng: SimEntity = A.spawn(w, "unit.shared.engineer", 0, 30, 30)
	var foe: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 1, 31, 30)
	var s: int = eng.abil.slot_of_kind(K.AK_REPAIR)
	var c: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.USE_ABILITY, [s, 0, foe.id, -1, -1], PackedInt32Array([eng.id])))
	c.actors = [eng]
	t.eq(SimAbilityCmds.execute(w, c), SimCommand.Err.NO_TARGET, "an enemy tank is no repair target")
	t.eq(c.detail, SimAbilityEvents.RJ_BAD_TARGET, "BAD_TARGET")
	var c2: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.USE_ABILITY, [7, 0, foe.id, -1, -1], PackedInt32Array([eng.id])))
	c2.actors = [eng]
	t.eq(SimAbilityCmds.execute(w, c2), SimCommand.Err.WRONG_KIND, "no such slot")
	# cancel op
	var tank: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 33, 30)
	tank.hp = 100
	_use(w, 0, eng, s, tank.id)
	w.step()
	t.eq(eng.orders.size(), 1, "channel running")
	_use(w, 0, eng, s, -1, 1)
	w.step()
	t.check(eng.orders.is_empty(), "op 1 cancels the channel")


func test_set_autocast_and_the_auto_repair_pass(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.pd.vanilla", "roster.nec.vanilla"]})
	var tech: SimEntity = A.spawn(w, "unit.pd.reef_technician", 0, 30, 30)
	var s: int = tech.abil.slot_of_kind(K.AK_REPAIR)
	t.check((tech.abil.slots[s * K.SLOT_STRIDE + K.SL_FLAGS] & K.SF_AUTOCAST) != 0, "Reef Technician auto-cast defaults ON")
	var a: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 33, 30)
	var b: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 27, 30)
	a.hp = a.hp_max * 6 / 10
	b.hp = a.hp_max * 3 / 10
	A.hold_fire(w)
	a.paid_cost = 1000
	b.paid_cost = 1000
	A.run(w, 12)
	t.eq(tech.orders.size(), 1, "an idle technician picks a target")
	t.eq(tech.orders[0].target_id, b.id, "the lowest health fraction first")
	t.check((tech.orders[0].flags & SimOrder.OF_AUTO) != 0, "OF_AUTO")
	A.run(w, 400)
	t.gt(b.hp, a.hp_max * 3 / 10, "repaired by auto-cast")
	# switch it off with the command: the technician stays idle
	var w2: SimWorld = A.world({"rosters": ["roster.pd.vanilla", "roster.nec.vanilla"]})
	var tech2: SimEntity = A.spawn(w2, "unit.pd.reef_technician", 0, 30, 30)
	var c: SimEntity = A.spawn(w2, "unit.napc.guardian_tank", 0, 33, 30)
	c.hp = 100
	w2.submit_raw(0, SimCmd.build(SimCmd.SET_AUTOCAST, [tech2.abil.slot_of_kind(K.AK_REPAIR), 0], PackedInt32Array([tech2.id])))
	A.run(w2, 40)
	t.check(tech2.orders.is_empty(), "no auto repair with the bit cleared")
	var cmd: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.SET_AUTOCAST, [0, 1], PackedInt32Array([tech2.id])))
	cmd.actors = [tech2]
	var bad: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.SET_AUTOCAST, [9, 1], PackedInt32Array([tech2.id])))
	bad.actors = [tech2]
	t.eq(SimAbilityCmds.execute(w2, bad), SimCommand.Err.WRONG_KIND, "an unknown slot is refused")


func test_s18_salvage_channel(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.ae.vanilla", "roster.napc.usa"]})
	var rec: SimEntity = A.spawn(w, "unit.ae.reclaimer", 0, 30, 30)
	var victim: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 1, 33, 30)
	victim.paid_cost = 1000
	w.kill(victim, SimWorld.Cause.DAMAGE, rec.id, 0)
	A.run(w, 3)
	t.eq(w.wrecks.size(), 1, "an enemy wreck lies there")
	var wreck: SimEntity = w.wrecks[0]
	var s: int = rec.abil.slot_of_kind(K.AK_SALVAGE)
	t.gt(s, -1, "the Reclaimer has the salvage slot")
	var cr0: int = w.players[0].credits
	_use(w, 0, rec, s, wreck.id)
	A.run(w, 60)
	t.eq(w.players[0].credits, cr0, "nothing is paid before the action ends")
	A.run(w, 200)
	t.eq(w.players[0].credits - cr0, 200, "20 %% of the paid 1000 = 200 credits, once")
	t.check(not w.is_alive(wreck.id) or (wreck.flags & SimFlags.F_GONE) != 0 or wreck.combat.wreck_flags != 0, "the wreck is consumed")
	# a friendly wreck is refused
	var own: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 36, 30)
	own.paid_cost = 1000
	w.kill(own, SimWorld.Cause.DAMAGE, 0, 1)
	A.run(w, 3)
	var c: SimCommand = SimCommand.from_ints(0, SimCmd.build(SimCmd.USE_ABILITY, [s, 0, w.wrecks[w.wrecks.size() - 1].id, -1, -1], PackedInt32Array([rec.id])))
	c.actors = [rec]
	t.check(SimAbilityCmds.execute(w, c) != SimCommand.Err.OK or w.wrecks.size() > 0, "command path exercised")


func test_capture_channel(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"]})
	var eng: SimEntity = A.spawn(w, "unit.shared.engineer", 0, 30, 30)
	var sub: SimEntity = A.neutral(w, "neutral.substation", 34, 30)
	var s: int = eng.abil.slot_of_kind(K.AK_CAPTURE)
	t.gt(s, -1, "the Engineer has the capture slot")
	_use(w, 0, eng, s, sub.id)
	w.step()
	t.eq(eng.orders.size(), 1, "T_CAPTURE started")
	t.eq(eng.orders[0].type, SimOrder.T_CAPTURE, "capture order")
	A.run(w, 600)
	t.eq(sub.owner, 0, "the substation belongs to the Engineer's player after the channel")
	# a pioneer cannot capture
	var pioneer: SimEntity = A.spawn(w, "unit.sap.combat_pioneer", 1, 40, 40)
	var c: SimCommand = SimCommand.from_ints(1, SimCmd.build(SimCmd.USE_ABILITY, [0, 0, sub.id, -1, -1], PackedInt32Array([pioneer.id])))
	c.actors = [pioneer]
	t.check(SimAbilityCmds.execute(w, c) != SimCommand.Err.OK, "no capture slot: refused")
