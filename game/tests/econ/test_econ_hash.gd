extends RefCounted
## DR-13 / determinism of the economy records: every int field of every economy record is hashed, economy state
## reaches the world checksum, and a lifecycle-heavy scenario (sell, undeploy, capture, shortage, SAP reserve)
## replays identically.

const KIT := preload("res://tests/support/sim_econ_kit.gd")


func test_hash_coverage(t: TestCtx) -> void:
	var classes: Dictionary = {
		"SimPlayerEcon": SimPlayerEcon, "SimCompEcon": SimCompEcon, "SimCompProd": SimCompProd,
		"SimCompWreck": SimCompWreck, "SimCompTemp": SimCompTemp, "SimPowerSlot": SimPowerSlot,
		"SimWarning": SimWarning, "SimScheduled": SimScheduled,
	}
	for n: String in classes:
		var cls: GDScript = classes[n]
		var problems: PackedStringArray = KIT.K.check_hash_coverage(cls, cls.get("HASH_EXEMPT"))
		t.eq(problems, PackedStringArray(), "%s: every int field is hashed" % n)


func test_economy_state_reaches_the_checksum(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	KIT.spawn_struct(w, DefTestKit.S_HQ, 0, 10, 10)
	KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 14, 10, 500)
	w.step()
	var base: int = w.checksum()
	var pe: SimPlayerEcon = KIT.econ(w, 0)
	pe.stat_harvested += 1
	t.check(w.checksum() != base, "a player-econ statistic")
	pe.stat_harvested -= 1
	t.eq(w.checksum(), base, "and back")
	var bar: SimEntity = w.structures_of(0)[1]
	bar.prod.head_paid += 1
	t.check(w.checksum() != base, "a producer's queue state")
	bar.prod.head_paid -= 1
	bar.econ.repair_acc_cost += 1
	t.check(w.checksum() != base, "a structure's econ component")
	bar.econ.repair_acc_cost -= 1
	pe.slots[SimEconConst.SLOT_SW].charge += 1
	t.check(w.checksum() != base, "a power slot")


func _build() -> SimWorld:
	return KIT.make_world({"players": 3, "start_mode": 0, "rules": {"start_credits": 20000}})


func _script(w: SimWorld, s: int) -> void:
	var gi: int = KIT.sidx(DefTestKit.S_GENERATOR)
	var bi: int = KIT.sidx(DefTestKit.S_BARRACKS)
	match s:
		1:
			# structures placed by the script (a production system is not part of this test)
			KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 23, 19, 600, false)
			KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 27, 19, 500, false)
			KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 1, 73, 69, 600)
			KIT.spawn_struct(w, DefTestKit.S_REFINERY, 2, 23, 66, 1800)
			w.economy.set_knob_base(w, 1, SimEconConst.K_SAP_RESERVE_TICKS, 400)
			w.players[1].econ.flags |= SimEconConst.PF_SAP_RESERVE
		100:
			w.submit_raw(0, SimCmd.sell(PackedInt32Array([w.structures_of(0)[2].id])))
		140:
			w.change_owner(w.structures_of(1)[1].id, 0, SimEvent.OWNER_CAPTURE)
		200:
			w.submit_raw(0, SimCmd.set_struct_repair(PackedInt32Array([w.structures_of(0)[1].id]), 1))
			w.kill(w.structures_of(0)[1], SimWorld.Cause.DAMAGE, 0, 2)
		260:
			w.submit_raw(2, SimCmd.undeploy_hq(PackedInt32Array([w.structures_of(2)[0].id])))
		400:
			w.economy.earn(w, 0, 1000, SimEconConst.CR_HARVEST, 3000, 3000)
			w.economy.spend(w, 0, 700, SimEconConst.CR_PRODUCTION)
		_:
			if gi < 0 or bi < 0:
				return


func test_lifecycle_double_run(t: TestCtx) -> void:
	var r: Dictionary = KIT.K.double_run(_build, _script, 700)
	t.check(r["ok"], "identical chains, events, checksums and dumps")
	var w: SimWorld = _build()
	KIT.K.run_script(w, 700, _script)
	t.check(w.economy.q_income_per_minute(0) > 0, "the scenario really ran (income recorded)")
	t.eq(w.players[2].rebuilders, 1, "the HQ of P2 became an MCV again")
