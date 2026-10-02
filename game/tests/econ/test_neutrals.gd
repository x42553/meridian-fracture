extends RefCounted
## The neutral structure effects catalog (economy 5.13) on REAL match worlds: substation power, salvage depot income, field
## hospital heal aura, observation tower vision, civilian block garrison data, harbor terminal forward Dock queue.

const K := preload("res://tests/support/sim_work_kit.gd")


func _own(w: SimWorld, n: SimEntity, pid: int) -> void:
	t_change(w, n, pid)


func t_change(w: SimWorld, n: SimEntity, pid: int) -> void:
	w.change_owner(n.id, pid, SimEvent.OWNER_CAPTURE)
	K.run(w, 1)


func test_depot_income(t: TestCtx) -> void:
	var w: SimWorld = K.world({})
	var depot: SimEntity = K.neutral(w, "neutral.salvage_depot")
	var pe: SimPlayerEcon = w.players[0].econ
	var before: int = pe.stat_depot
	var c0: int = w.players[0].credits
	_own(w, depot, 0)
	var start: int = w.tick
	K.run(w, 1000)
	t.eq(pe.stat_depot - before, 250, "5 payouts of 50 in 1000 ticks (300 per minute)")
	t.check(w.players[0].credits >= c0 + 250, "credits arrived")
	t.check(pe.stat_depot >= 250 and w.economy.q_income_per_minute(0) >= 250, "counted in the income ring")
	t.check(K.events(w, SimEconConst.EVT_CREDITS_GAINED).size() >= 5, "EVT_CREDITS_GAINED at the depot")
	# ownership change moves the stream
	var p1: SimPlayerEcon = w.players[1].econ
	_own(w, depot, 1)
	K.run(w, 400)
	t.check(p1.stat_depot >= 100, "the new owner is paid (%d)" % p1.stat_depot)
	t.check(start >= 0, "tick base")


func test_substation_power(t: TestCtx) -> void:
	var w: SimWorld = K.world({})
	var sub: SimEntity = K.neutral(w, "neutral.substation")
	var pe: SimPlayerEcon = w.players[0].econ
	var s0: int = pe.power_supply
	_own(w, sub, 0)
	K.run(w, 2)
	t.eq(pe.power_supply, s0 + 100, "+100 supply while owned")
	w.kill(sub, SimWorld.Cause.SCRIPT, 0, 1)
	K.run(w, 3)
	t.eq(pe.power_supply, s0, "destroying it removes the +100")


func test_observation_tower_vision(t: TestCtx) -> void:
	var w: SimWorld = K.world({"rules": {"fog": true}})
	var tower: SimEntity = K.neutral(w, "neutral.observation_tower")
	var cx: int = tower.x >> SimConfig.CELL_SHIFT
	var cy: int = tower.y >> SimConfig.CELL_SHIFT
	# a cell 12 cells from the tower that none of player 0's things can see yet
	var far_x: int = cx + 12
	var far_y: int = cy
	var before: bool = w.cell_visible(0, far_x, far_y)
	_own(w, tower, 0)
	K.run(w, 6)
	t.check(not before, "not visible before the capture")
	t.check(w.cell_visible(0, far_x, far_y), "visible 12 cells away once owned (sight 14)")
	t.check(not w.cell_visible(0, cx + 17, cy), "but not 17 cells away")
	_own(w, tower, 1)
	K.run(w, 6)
	t.check(not w.cell_visible(0, far_x, far_y), "and gone again when the enemy takes it")
	t.check(w.cell_visible(1, far_x, far_y), "now the enemy sees it")


func _find(w: SimWorld, pid: int, u_idx: int) -> SimEntity:
	for u: SimEntity in w.units_of(pid):
		if u.def_idx == u_idx and (u.flags & SimFlags.F_GONE) == 0:
			return u
	return null


func _hurt_inf(w: SimWorld, id: String, pid: int, x: int, y: int) -> SimEntity:
	var u: SimEntity = K.unit_near(w, id, pid, x, y, 100)
	u.hp = maxi(1, u.hp_max / 2)
	return u


func test_field_hospital_aura(t: TestCtx) -> void:
	var w: SimWorld = K.world({})
	var h: SimEntity = K.neutral(w, "neutral.field_hospital")
	var near_inf: SimEntity = _hurt_inf(w, "unit.shared.engineer", 0, h.x + 3 * K.CELL, h.y)
	var far_inf: SimEntity = _hurt_inf(w, "unit.shared.engineer", 0, h.x + 9 * K.CELL, h.y)
	var enemy_inf: SimEntity = _hurt_inf(w, "unit.shared.engineer", 1, h.x - 3 * K.CELL, h.y)
	var tank: SimEntity = K.unit_near(w, "unit.shared.mobile_construction_vehicle", 0, h.x, h.y + 4 * K.CELL, 3000)  # an unarmed vehicle
	tank.hp = tank.hp_max / 2
	K.run(w, 100)
	t.eq(near_inf.hp, maxi(1, near_inf.hp_max / 2), "an unowned hospital heals nobody")
	_own(w, h, 0)
	var hp0: int = near_inf.hp
	var tank0: int = tank.hp
	K.run(w, 200)  # 10 s
	var gain: int = near_inf.hp - hp0
	var expect: int = near_inf.hp_max * 200 * 200 / SimEconomyWork.HP_UNIT
	t.check(absi(gain - expect) <= 1, "infantry heal 2 %%/s (%d vs %d)" % [gain, expect])
	t.check(far_inf.hp == maxi(1, far_inf.hp_max / 2), "outside 5 cells: nothing")
	t.eq(enemy_inf.hp, maxi(1, enemy_inf.hp_max / 2), "enemy infantry are not healed")
	t.eq(tank.hp, tank0, "vehicles are not healed")
	# a second hospital does not stack (same-source rule)
	var h2: SimEntity = w.spawn_entity(SimEntity.Kind.NEUTRAL, h.def_idx, -1, near_inf.x + K.CELL, near_inf.y + 3 * K.CELL, 0, SimFlags.F_INITIAL)
	if h2 != null:
		_own(w, h2, 0)
		var hp1: int = near_inf.hp
		K.run(w, 200)
		var gain2: int = near_inf.hp - hp1
		t.check(absi(gain2 - expect) <= 1, "two hospitals still heal once (%d)" % gain2)


func test_civilian_garrison_data(t: TestCtx) -> void:
	var w: SimWorld = K.world({"family": 1})
	var g: SimEntity = K.neutral(w, "neutral.civilian_garrison")
	t.check(g != null, "urban maps have civilian blocks")
	t.check(SimNeutrals.is_civilian_garrison(w, g), "marked civilian garrison")
	t.eq(SimNeutrals.garrison_squads(w, g), 4, "holds 4 infantry squads")
	t.eq(g.hp_max, 2000, "2000 hp")
	t.check(not w.data.neutrals[g.def_idx].capturable, "not capturable")
	var sub: SimEntity = K.neutral(w, "neutral.substation")
	t.eq(SimNeutrals.garrison_squads(w, sub), 0, "others hold none")


func test_harbor_terminal_forward_queue(t: TestCtx) -> void:
	var w: SimWorld = K.world({"family": 2, "size": 128, "seed": 3, "credits": 30000})
	var ht: SimEntity = K.neutral(w, "neutral.harbor_terminal")
	t.check(ht != null, "coast maps have harbor terminals")
	if ht == null:
		return
	t.check(ht.prod != null, "the terminal has a queue component")
	var pe: SimPlayerEcon = w.players[0].econ
	var docks0: int = pe.producer_ids[SimEconConst.PROD_DOCK].size()
	t.eq(w.production.can_queue_unit(w, 0, ht.id, 0), SimEconConst.RSN_NOT_OWNER, "not usable while neutral")
	_own(w, ht, 0)
	t.eq(pe.producer_ids[SimEconConst.PROD_DOCK].size(), docks0 + 1, "registered as a Dock producer")
	var ok_units: Array[int] = []
	var bad_units: Array[int] = []
	for u: int in w.players[0].roster.producible_units:
		if w.economy.life.prod_kind_of(w.data.units[u].producer) != SimEconConst.PROD_DOCK:
			continue
		if SimNeutrals.forward_prereqs_ok(w, ht, w.data.units[u]):
			ok_units.append(u)
		else:
			bad_units.append(u)
	t.check(not ok_units.is_empty(), "some Dock units are dock-only (patrol boat / Landing Transport)")
	for u2: int in ok_units:
		t.eq(w.production.can_queue_unit(w, 0, ht.id, u2), SimEconConst.RSN_OK, "%s queueable at the terminal" % w.data.units[u2].id)
	for u3: int in bad_units:
		t.eq(w.production.can_queue_unit(w, 0, ht.id, u3), SimEconConst.RSN_PREREQ, "%s needs more than a dock" % w.data.units[u3].id)
	var boat: int = ok_units[0]
	var c0: int = w.players[0].credits
	K.cmd(w, 0, SimCmd.train(ht.id, boat, 1))
	var made: int = K.run_until(w, func(ww: SimWorld) -> bool: return _find(ww, 0, boat) != null, 2500)
	t.check(made > 0, "the boat was built (%d ticks)" % made)
	var u_ent: SimEntity = _find(w, 0, boat)
	t.check(u_ent != null and u_ent.layer != SimEntity.Layer.GROUND, "a surface unit appeared for player 0")
	t.check(w.players[0].credits < c0, "paid")
	# losing the terminal clears its queue and refunds the old owner
	K.cmd(w, 0, SimCmd.train(ht.id, boat, 2))
	K.run(w, 200)
	var before_loss: int = w.players[0].credits
	_own(w, ht, 1)
	K.run(w, 2)
	t.check(ht.prod.q_def.is_empty(), "queue cleared on capture")
	t.check(w.players[0].credits > before_loss, "the paid head cost was refunded to the old owner")
	t.eq(pe.producer_ids[SimEconConst.PROD_DOCK].size(), docks0, "unregistered from the old owner")
