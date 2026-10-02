extends RefCounted
## ORD_DEPLOY_MCV (economy 3.7 / 5.3, S5 expansion): deploy in place, drive to a cell first, refuse a blocked site, the second
## HQ extends the build radius, undeploy restores the MCV value.

const K := preload("res://tests/support/sim_work_kit.gd")


func _mcv(w: SimWorld, pid: int, x: int, y: int) -> SimEntity:
	var idx: int = w.players[pid].roster.mcv_idx
	var cell: int = SimMovement.find_free_cell_near(w, w.map.idx(x >> SimConfig.CELL_SHIFT, y >> SimConfig.CELL_SHIFT), SimEntity.Layer.GROUND, 8)
	return w.spawn_unit(idx, pid, w.map.center_x(cell), w.map.center_y(cell), 0, 0, 3000)


func _open_spot(w: SimWorld) -> PackedInt32Array:
	# an open site far from both bases: the map centre region, probing outwards for a valid HQ site
	var cx: int = w.map.w / 2
	var cy: int = w.map.h / 2
	var res: SimPlacementResult = SimPlacementResult.new()
	var hq_idx: int = w.players[0].roster.hq_idx
	for r: int in 30:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				res = SimPlacementResult.new()
				if SimPlacement._validate(w, 0, hq_idx, cx + dx, cy + dy, 0, res, true, 0) == SimEconConst.RSN_OK:
					return PackedInt32Array([cx + dx, cy + dy])
	return PackedInt32Array([-1, -1])


func test_deploy_in_place_and_undeploy(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 20000})
	var spot: PackedInt32Array = _open_spot(w)
	t.check(spot[0] >= 0, "an open HQ site exists")
	var mcv: SimEntity = _mcv(w, 0, (spot[0] + 1) * K.CELL, (spot[1] + 1) * K.CELL)
	var pe: SimPlayerEcon = w.players[0].econ
	t.eq(pe.active_hq_count, 1, "one HQ at the start")
	K.cmd(w, 0, SimCmd.deploy(PackedInt32Array([mcv.id])))
	K.run(w, 2)
	t.check(w.get_entity(mcv.id) == null, "the MCV is gone")
	t.eq(K.events(w, SimEconConst.EVT_HQ_DEPLOYED).size(), 1, "EVT_HQ_DEPLOYED")
	K.run(w, 70)
	t.eq(pe.active_hq_count, 2, "the second HQ is ACTIVE after deploy_t")
	# the second HQ extends the build radius: a Generator right beside it (far from the first HQ) is valid
	var gen_idx: int = -1
	for s: DefStructure in w.data.structures:
		if s.power > 0 and w.players[0].roster.has_structure(s.index):
			gen_idx = s.index
			break
	var res: SimPlacementResult = SimPlacementResult.new()
	t.eq(SimPlacement.validate(w, 0, gen_idx, spot[0] + 5, spot[1], 0, res), SimEconConst.RSN_OK, "build radius from both HQs")
	var hq2: SimEntity = null
	for h: SimEntity in w.structures_of(0):
		if h.econ != null and w.economy.life.is_hq_def(h.def_idx) and h.id != w.structures_of(0)[0].id:
			hq2 = h
	t.check(hq2 != null, "second HQ entity")
	t.eq(hq2.econ.mcv_paid_cost, 3000, "the MCV value is remembered")
	# undeploy restores the same MCV value: no income loop
	K.cmd(w, 0, SimCmd.undeploy_hq(PackedInt32Array([hq2.id])))
	K.run(w, SimEconConst.UNDEPLOY_TICKS + 5)
	var found: SimEntity = null
	for u: SimEntity in w.units_of(0):
		if u.def_idx == w.players[0].roster.mcv_idx:
			found = u
	t.check(found != null, "the MCV is back")
	t.eq(found.paid_cost, 3000, "with the same paid cost")


func test_deploy_with_cell_drives_first(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 20000})
	var spot: PackedInt32Array = _open_spot(w)
	var mcv: SimEntity = _mcv(w, 0, (spot[0] - 12) * K.CELL, (spot[1] + 1) * K.CELL)
	var o: SimOrder = SimOrder.make(SimOrder.T_DEPLOY_MCV, 0, (spot[0] + 1) * K.CELL + K.CELL / 2, (spot[1] + 1) * K.CELL + K.CELL / 2, 1)
	t.eq(w.orders.issue(w, mcv, o, SimOrder.QM_REPLACE), SimCommand.Err.OK, "order accepted")
	K.run(w, 60)
	t.check(w.get_entity(mcv.id) != null, "still driving after 3 s")
	var n: int = K.run_until(w, func(ww: SimWorld) -> bool: return ww.get_entity(mcv.id) == null, 1500)
	t.check(n > 0, "arrived and deployed (%d ticks)" % n)
	var hqs: int = 0
	for h: SimEntity in w.structures_of(0):
		if w.economy.life.is_hq_def(h.def_idx):
			hqs += 1
	t.eq(hqs, 2, "two HQs")


func test_blocked_site_fails(t: TestCtx) -> void:
	var w: SimWorld = K.world({"credits": 20000})
	var hq: SimEntity = w.structures_of(0)[0]
	var mcv: SimEntity = _mcv(w, 0, hq.x + 2 * K.CELL, hq.y)
	K.cmd(w, 0, SimCmd.deploy(PackedInt32Array([mcv.id])))
	K.run(w, 3)
	t.check(w.get_entity(mcv.id) != null, "the MCV stays: the site next to the HQ is blocked")
	t.check(mcv.orders.is_empty(), "order ended")
	var ev: Array[PackedInt32Array] = K.events(w, SimEconConst.EVT_ORDER_FAILED)
	t.check(ev.size() >= 1, "EVT_ORDER_FAILED with the RSN")
	# a non-MCV is refused
	var eng: SimEntity = K.engineer_at(w, 0, hq)
	K.cmd(w, 0, SimCmd.deploy(PackedInt32Array([eng.id])))
	K.run(w, 2)
	t.check(eng.orders.is_empty(), "an Engineer cannot deploy")
