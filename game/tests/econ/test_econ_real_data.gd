extends RefCounted
## The economy against the REAL balance data (GameData.load_default): resolved generator output (OLM 188, Saudi
## 225), Kazakhstan's cheaper Refinery, power classes of all 29 structure defs, the SAP reserve flag, the real
## HQ / MCV pair (deploy, undeploy) and placement of a real Barracks.

const CELL: int = SimConfig.CELL


func _world(rosters: PackedStringArray) -> SimWorld:
	var d: GameData = GameData.load_default()
	var cells: PackedInt32Array = PackedInt32Array([20 * 96 + 20, 70 * 96 + 70])
	var m: MapData = MapData.for_test(96, 96, cells, PackedInt32Array(), 0x5EED)
	for s: DefStructure in d.structures:
		m.set_footprint(SimEntity.Kind.STRUCTURE, s.index, MapFootprint.new(s.fp_w, s.fp_h, s.fp_mask, (s.place_mask & DefEnums.PLACE_SHORELINE) != 0))
	var pl: Array = []
	for i: int in rosters.size():
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": rosters[i], "team": i + 1, "color": i, "start": i, "handicap": 100})
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 7, "map": {"id": "real"}, "rules": {"victory": 0}, "players": pl})
	return SimWorld.create(d, cfg, m)


func test_resolved_power_and_flags(t: TestCtx) -> void:
	var w: SimWorld = _world(PackedStringArray(["roster.olm.vanilla", "roster.sap.india"]))
	if not t.not_null(w, "world"):
		return
	var gi: int = w.data.structure_idx("structure.shared.generator")
	var hq0: SimEntity = w.structures_of(0)[0]
	t.eq(hq0.def_idx, 24, "the roster's start HQ")
	t.eq(hq0.econ.st, SimEconConst.ST_ACTIVE, "start HQ ACTIVE")
	t.check((hq0.econ.flags & SimEconConst.EF_FREE) != 0, "free")
	var g: SimEntity = w.spawn_structure(gi, 0, 24 * CELL + 1024, 20 * CELL + 1024, 0, 0, 600)
	w.step()
	t.eq(w.power.supply(0), 188, "OLM generator output +25 %, half-up")
	t.check((w.players[1].econ.flags & SimEconConst.PF_SAP_RESERVE) != 0, "SAP has the reserve trait")
	t.eq([w.players[1].econ.reserve_left, w.players[1].econ.reserve_max], [400, 400] as Array, "20 s")
	t.eq(w.players[0].econ.reserve_max, 0, "OLM has none")
	t.check(g.econ.st == SimEconConst.ST_ACTIVE and g.econ.power_delta == 188, "registered delta")


func test_saudi_and_kazakhstan_tables(t: TestCtx) -> void:
	var w: SimWorld = _world(PackedStringArray(["roster.olm.saudi_arabia", "roster.def.kazakhstan"]))
	var gi: int = w.data.structure_idx("structure.shared.generator")
	var ri: int = w.data.structure_idx("structure.shared.refinery")
	w.spawn_structure(gi, 0, 24 * CELL + 1024, 20 * CELL + 1024, 0, 0, 600)
	w.step()
	t.eq(w.power.supply(0), 225, "Saudi Arabia: layers multiply")
	t.eq(w.players[1].view.struct_cost[ri], 1530, "Kazakhstan Refinery cost")


func test_power_classes_of_all_structures(t: TestCtx) -> void:
	var w: SimWorld = _world(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]))
	var life: SimStructureLife = w.economy.life
	var want: Dictionary = {
		"structure.shared.headquarters": SimEconConst.PC_NONE, "structure.shared.generator": SimEconConst.PC_NONE,
		"structure.shared.refinery": SimEconConst.PC_ECON, "structure.shared.barracks": SimEconConst.PC_PRODUCER,
		"structure.shared.factory": SimEconConst.PC_PRODUCER, "structure.shared.dock": SimEconConst.PC_PRODUCER,
		"structure.shared.airfield": SimEconConst.PC_PRODUCER, "structure.shared.radar": SimEconConst.PC_SENSOR,
		"structure.shared.laboratory": SimEconConst.PC_SENSOR, "structure.shared.watchtower": SimEconConst.PC_DEFENSE,
		"structure.shared.anti_tank_turret": SimEconConst.PC_DEFENSE, "structure.shared.aa_battery": SimEconConst.PC_DEFENSE,
		"structure.nec.relay": SimEconConst.PC_RELAY, "structure.nec.lance_rail_emplacement": SimEconConst.PC_DEFENSE,
		"structure.nec.aurora_microwave_array": SimEconConst.PC_STRATEGIC, "structure.napc.atlas_kinetic_array": SimEconConst.PC_STRATEGIC,
	}
	for id: String in want:
		t.eq(life.power_class_of(w.data.structure_idx(id)), want[id], id)
	t.eq(life.prod_kind_of(w.data.structure_idx("structure.shared.dock")), SimEconConst.PROD_DOCK, "dock queue")
	t.check(life.is_hq_def(24) and not life.is_hq_def(w.data.structure_idx("structure.shared.barracks")), "HQ marker")


func test_mcv_deploy_and_undeploy(t: TestCtx) -> void:
	var w: SimWorld = _world(PackedStringArray(["roster.napc.usa", "roster.nec.vanilla"]))
	var mcv_idx: int = w.players[0].roster.mcv_idx
	var mcv: SimEntity = w.spawn_unit(mcv_idx, 0, 40 * CELL + 512, 40 * CELL + 512, 0, 0, 3000)
	w.step()
	var hq_id: int = w.economy.life.deploy_mcv(w, mcv)
	t.check(hq_id > 0, "the real MCV deploys into the real HQ")
	KIT_run(w, 70)
	var hq: SimEntity = w.get_entity(hq_id)
	t.eq(hq.econ.st, SimEconConst.ST_ACTIVE, "active after the deploy time (3 s)")
	t.eq(w.players[0].econ.active_hq_count, 2, "start HQ + deployed HQ: two construction anchors")
	# a real Barracks next to the second HQ is inside its radius (7.5 cells), not the first HQ's
	var res: SimPlacementResult = SimPlacementResult.new()
	var bi: int = w.data.structure_idx("structure.shared.barracks")
	t.eq(SimPlacement.validate(w, 0, bi, 47, 40, 0, res), SimEconConst.RSN_OK, "within 8 cells of the new HQ")
	t.eq(SimPlacement.validate(w, 0, bi, 60, 40, 0, res), SimEconConst.RSN_OUT_OF_RADIUS, "beyond both")
	w.submit_raw(0, SimCmd.undeploy_hq(PackedInt32Array([hq_id])))
	KIT_run(w, 50)
	var back: int = 0
	for u: SimEntity in w.units_of(0):
		if u.def_idx == mcv_idx:
			back += 1
			t.eq(u.paid_cost, 3000, "value restored")
	t.eq(back, 1, "one MCV again")


func KIT_run(w: SimWorld, n: int) -> void:
	for _i: int in n:
		w.step()
