extends RefCounted
## AIX1 micro / retreat / repair (ai.md 5.9.1, 5.9.2, S4): focus-fire priorities, focus orders and leases, kiting only at a fast think
## cadence, per-unit retreat to the repair point (NAPC service apron) and the return, Engineers repairing vehicles. Real matches.


func _two(levels: Array, ticks: int = 400, o: Dictionary = {}) -> Dictionary:
	return AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), levels, ticks, o)


func _enemy_row(c: AiContext, id: int, def: int, owner: int, hp_pct: int, mask: int, x: int, y: int) -> int:
	var t: AiEntityTable = c.kb.enemy_units
	var r: int = t.upsert(id)
	t.def[r] = def
	t.owner[r] = owner
	t.x[r] = x
	t.y[r] = y
	t.hp[r] = hp_pct
	t.hp_max[r] = 100
	t.flags[r] = 0
	t.role_mask[r] = mask
	t.last_seen[r] = c.tick
	t.kind[r] = AiTypes.KIND_UNIT
	return r


func test_focus_priority_classes(t: TestCtx) -> void:
	var m: Dictionary = _two([1, 1], 0)
	var c: AiContext = AiXKit.ctx(m, 0)
	c.tick = 100
	var rows: Dictionary = {}
	var masks: Dictionary = {
		"command": 1 << AiTypes.R_COMMAND_PROVIDER, "healer": 1 << AiTypes.R_HEALER, "arty": 1 << AiTypes.R_ARTILLERY,
		"at": 1 << AiTypes.R_INFANTRY_AT, "aa": 1 << AiTypes.R_AA_MOBILE, "tank": 1 << AiTypes.R_TANK_MAIN,
		"inf": 1 << AiTypes.R_INFANTRY_BASIC, "col": 1 << AiTypes.R_COLLECTOR, "scout": 1 << AiTypes.R_SCOUT_LIGHT,
	}
	var n: int = 0
	for k: String in masks:
		n += 1
		rows[k] = _enemy_row(c, 9000 + n, 0, 1, 100, int(masks[k]), 0, 0)
	# decoy row
	var decoy: int = _enemy_row(c, 9100, 0, 1, 100, 1 << AiTypes.R_TANK_MAIN, 0, 0)
	c.kb.enemy_units.flags[decoy] = AiTypes.EF_DECOY
	t.eq(AiMicro.base_prio(c, rows["command"], 0, false), 90)
	t.eq(AiMicro.base_prio(c, rows["healer"], 0, false), 85)
	t.eq(AiMicro.base_prio(c, rows["arty"], 0, false), 75)
	t.eq(AiMicro.base_prio(c, rows["at"], 60, false), 70, "anti-tank infantry counts when my squad is armored")
	t.eq(AiMicro.base_prio(c, rows["at"], 20, false), 50, "... and is plain infantry otherwise")
	t.eq(AiMicro.base_prio(c, rows["aa"], 0, true), 70, "AA counts when my air is present")
	t.lt(AiMicro.base_prio(c, rows["aa"], 0, false), 60)
	t.eq(AiMicro.base_prio(c, rows["tank"], 0, false), 60)
	t.eq(AiMicro.base_prio(c, rows["inf"], 0, false), 50)
	t.eq(AiMicro.base_prio(c, rows["col"], 0, false), 45)
	t.eq(AiMicro.base_prio(c, rows["scout"], 0, false), 20)
	t.eq(AiMicro.base_prio(c, decoy, 0, false), 0, "a decoy is never worth a shot")


func test_focus_fire_orders_the_squad_and_leases_it(t: TestCtx) -> void:
	var m: Dictionary = _two([1, 1], 3600)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var eh: PackedInt32Array = AiXKit.home(m, 1)
	var mid: PackedInt32Array = AiXKit.toward(h, eh, 14)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 5:
		ids.append(AiXKit.spawn(m, "unit.napc.guardian_tank", 0, mid[0] + i * 600, mid[1], 1100))
	var tgt_pos: PackedInt32Array = AiXKit.toward(mid, eh, 6)
	var foe: PackedInt32Array = PackedInt32Array()
	for k: int in 3:
		foe.append(AiXKit.spawn(m, "unit.nec.spike_team", 1, tgt_pos[0] + k * 500, tgt_pos[1], 200))
	var op: AiOpDefend = AiXKit.defend_op(m, 0, ids, mid[0], mid[1])
	t.check(op.id > 0, "the defend op started")
	AiSoakKit.play(m, 400)
	var b: AiBrain = AiXKit.brain(m, 0)
	t.gt(b.micro.focus_orders, 0, "Medium focus-fires (micro_focus)")
	t.gt(b.stat("focus"), 0)
	t.eq((m["errors"] as PackedStringArray).size(), 0, "no engine errors")
	# Easy has micro_period 0 and no focus fire
	var m2: Dictionary = _two([0, 0], 3600)
	var h2: PackedInt32Array = AiXKit.home(m2, 0)
	var mid2: PackedInt32Array = AiXKit.toward(h2, AiXKit.home(m2, 1), 14)
	var ids2: PackedInt32Array = PackedInt32Array()
	for i2: int in 5:
		ids2.append(AiXKit.spawn(m2, "unit.napc.guardian_tank", 0, mid2[0] + i2 * 600, mid2[1], 1100))
	for k2: int in 3:
		AiXKit.spawn(m2, "unit.nec.spike_team", 1, mid2[0] + 6 * 1024 + k2 * 500, mid2[1], 200)
	AiXKit.defend_op(m2, 0, ids2, mid2[0], mid2[1])
	AiSoakKit.play(m2, 400)
	t.eq(AiXKit.brain(m2, 0).micro.focus_orders, 0, "Easy never focus-fires")


func test_kiting_needs_a_fast_think_interval(t: TestCtx) -> void:
	var c: AiContext = AiXKit.ctx(_two([1, 1], 0), 0)
	# kiter classes: a ranged non-deployable unit, never artillery / stationary-fire
	var res: AiRoleResolver = c.res
	var kiters: int = 0
	var arty_kite: int = 0
	for d: int in c.view.game_data().units.size():
		var dd: DefUnit = c.view.unit_def(d)
		if dd == null or not c.view.roster().producible_units.has(d):
			continue
		if AiMicro.is_kiter(c, d):
			kiters += 1
			if res.has_bit(d, AiTypes.R_ARTILLERY) or res.has_bit(d, AiTypes.R_STATIONARY_FIRE):
				arty_kite += 1
	t.gt(kiters, 0, "NAPC fields at least one kiter")
	t.eq(arty_kite, 0, "artillery and stationary-fire units are never kited")
	# Hard (think dt 4 in the harness) kites, Medium (dt 6) does not
	for lv: int in [1, 2]:
		var m: Dictionary = _two([lv, lv], 3600)
		var cc: AiContext = AiXKit.ctx(m, 0)
		var kiter_def: int = -1
		for d2: int in cc.view.game_data().units.size():
			if cc.view.roster().producible_units.has(d2) and AiMicro.is_kiter(cc, d2) and cc.unit_profile(d2).speed >= 60:
				kiter_def = d2
				break
		t.gt(kiter_def, -1)
		var h: PackedInt32Array = AiXKit.home(m, 0)
		var mid: PackedInt32Array = AiXKit.toward(h, AiXKit.home(m, 1), 16)
		var did: String = cc.view.game_data().units[kiter_def].id
		var ids: PackedInt32Array = PackedInt32Array()
		for i: int in 4:
			ids.append(AiXKit.spawn(m, did, 0, mid[0] + i * 700, mid[1]))
		var rng: int = cc.unit_profile(kiter_def).range
		# a slow melee-ish enemy inside 0.6 x the range of the kiters
		for k: int in 2:
			AiXKit.spawn(m, "unit.nec.spike_team", 1, mid[0] + rng * 5 / 10 + k * 400, mid[1] + 800)
		AiXKit.defend_op(m, 0, ids, mid[0], mid[1])
		AiSoakKit.play(m, 300)
		var kites: int = AiXKit.brain(m, 0).micro.kite_orders
		if lv == 1:
			t.eq(kites, 0, "Medium (think interval > 4) never kites")
		else:
			t.gt(kites, 0, "Hard kites (%d orders)" % kites)
		t.eq((m["errors"] as PackedStringArray).size(), 0)


func test_wounded_tanks_retreat_to_the_apron_and_return(t: TestCtx) -> void:
	# S4: six tanks at 30 % in combat; NAPC (APRON_RETREAT) sends them to within 5 cells of a Factory and takes them back at 75 %
	var m: Dictionary = _two([2, 1], 5200)
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	t.check(c.pers.has_flag(AiTypes.doctrine_bit("APRON_RETREAT")), "NAPC retreats to the service apron")
	t.eq(c.pers.return_hp_pct, 75)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var mid: PackedInt32Array = AiXKit.toward(h, AiXKit.home(m, 1), 10)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 6:
		ids.append(AiXKit.spawn(m, "unit.napc.guardian_tank", 0, mid[0] + i * 700, mid[1], 1100))
	AiXKit.defend_op(m, 0, ids, mid[0], mid[1])
	AiSoakKit.play(m, 60)
	for id: int in ids:
		AiXKit.set_hp_pct(m, id, 30)
	AiSoakKit.play(m, 80)
	var rep: AiSquad = b.squads().squad(b.repair.squad_id)
	t.not_null(rep)
	var gone: int = 0
	for id2: int in ids:
		if rep.has(id2):
			gone += 1
	t.ge(gone, 5, "the wounded left their squad for the REPAIR squad within 140 ticks (%d of 6)" % gone)
	t.gt(b.repair.retreats, 0)
	t.eq(b.repair.source, 1, "the apron is the repair source")
	# they walk to the Factory area
	AiSoakKit.play(m, 500)
	var near: int = 0
	var w: SimWorld = AiXKit.world(m)
	for id3: int in ids:
		if not AiXKit.alive(m, id3):
			continue
		var e: SimEntity = w.get_entity(id3)
		if AiForce.dist(e.x, e.y, b.repair.point_x, b.repair.point_y) <= 6 * AiXKit.CELL:
			near += 1
	t.ge(near, 3, "the retreating tanks reached the repair point (%d)" % near)
	# healed to 80 %: they return to the reserve (the op is over) - not to the wave they came from
	for id4: int in ids:
		if AiXKit.alive(m, id4):
			AiXKit.set_hp_pct(m, id4, 90)
	AiSoakKit.play(m, 200)
	var back: int = 0
	for id5: int in ids:
		if AiXKit.alive(m, id5) and not b.squads().squad(b.repair.squad_id).has(id5):
			back += 1
	t.gt(back, 0, "healed units left the REPAIR squad (%d)" % back)
	t.eq((m["errors"] as PackedStringArray).size(), 0)


func test_no_retreat_without_anything_that_repairs(t: TestCtx) -> void:
	# NEC has no apron / tender: without an Engineer a wounded tank stays and fights
	var m: Dictionary = _two([1, 2], 3000)
	var b: AiBrain = AiXKit.brain(m, 1)
	var c: AiContext = AiXKit.ctx(m, 1)
	t.check(not c.pers.has_flag(AiTypes.doctrine_bit("APRON_RETREAT")))
	var w: SimWorld = AiXKit.world(m)
	# remove every engineer of the player
	for e: SimEntity in w.units_of(1):
		if w.data.units[e.def_idx].id == "unit.shared.engineer":
			w.remove_entity(e.id, SimEvent.REM_KILLED)
	var h: PackedInt32Array = AiXKit.home(m, 1)
	var mid: PackedInt32Array = AiXKit.toward(h, AiXKit.home(m, 0), 8)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 4:
		ids.append(AiXKit.spawn(m, "unit.nec.leopard_tank", 1, mid[0] + i * 700, mid[1], 1000))
	AiXKit.defend_op(m, 1, ids, mid[0], mid[1])
	AiSoakKit.play(m, 40)
	for id: int in ids:
		AiXKit.set_hp_pct(m, id, 20)
	var before: int = b.repair.retreats
	AiSoakKit.play(m, 120)
	t.eq(b.repair.source, 0, "no repair source")
	t.eq(b.repair.retreats, before, "no retreat without a repair source")


func test_engineers_are_wanted_and_repair_vehicles(t: TestCtx) -> void:
	var m: Dictionary = _two([2, 1], 6600)
	var b: AiBrain = AiXKit.brain(m, 1)
	var c: AiContext = AiXKit.ctx(m, 1)
	t.gt(b.repair.engineer_want, 0, "an Engineer crew is wanted once the opener is done")
	# put a damaged vehicle next to the repair point and an idle Engineer: it gets repaired
	var w: SimWorld = AiXKit.world(m)
	var eng: int = AiXKit.spawn(m, "unit.shared.engineer", 1, b.repair.point_x + 1500, b.repair.point_y, 500)
	var tank: int = AiXKit.spawn(m, "unit.nec.leopard_tank", 1, b.repair.point_x + 2500, b.repair.point_y, 1000)
	AiXKit.set_hp_pct(m, tank, 40)
	w.players[1].credits = 5000
	var hp0: int = w.get_entity(tank).hp
	AiSoakKit.play(m, 500)
	t.gt(b.repair.repair_orders, 0, "an idle Engineer was sent to repair")
	t.gt(w.get_entity(tank).hp, hp0, "the vehicle was repaired")
	t.eq(c.kb.own.has(eng), true)
	t.eq((m["errors"] as PackedStringArray).size(), 0)


func test_wounded_reserve_units_go_to_the_repair_point(t: TestCtx) -> void:
	var m: Dictionary = _two([2, 0], 5200)
	var b: AiBrain = AiXKit.brain(m, 0)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var far: PackedInt32Array = AiXKit.toward(h, AiXKit.home(m, 1), 12)
	var tank: int = AiXKit.spawn(m, "unit.napc.guardian_tank", 0, far[0], far[1], 1100)
	AiXKit.settle(m, 30)
	AiXKit.set_hp_pct(m, tank, 40)
	AiSoakKit.play(m, 80)
	var rep: AiSquad = b.squads().squad(b.repair.squad_id)
	t.check(rep != null and rep.has(tank), "a wounded unit of the reserve is sent to be repaired")
	AiXKit.set_hp_pct(m, tank, 95)
	AiSoakKit.play(m, 120)
	t.check(not b.squads().squad(b.repair.squad_id).has(tank), "... and released when healed")
	t.eq((m["errors"] as PackedStringArray).size(), 0)
