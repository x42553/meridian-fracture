extends RefCounted
## E4 placement (10.1-D): build radius from own ACTIVE HQs, overlap, deposit fields, debris, units, aprons, dock
## shoreline at all rotations, the strategic limit, validate_hq_site.

const KIT := preload("res://tests/support/sim_econ_kit.gd")


## Zone stand-in with a debris cell.
class DebrisZones:
	extends SimZoneSystem
	var cells: PackedInt32Array = PackedInt32Array()

	func blocks_construction(cx: int, cy: int) -> bool:
		return cells.has(cy * 96 + cx)


## Movement stand-in that offers eject_units_from_rect (friendly units stop blocking).
class EjectMove:
	extends SimMovementSystem

	func eject_units_from_rect(_world: SimWorld, _x0: int, _y0: int, _x1: int, _y1: int, _team: int) -> void:
		pass


func _world_with_hq(extra: Dictionary = {}) -> SimWorld:
	var w: SimWorld = KIT.make_world(extra)
	KIT.spawn_struct(w, DefTestKit.S_HQ, 0, 10, 10)
	w.step()
	return w


func _v(w: SimWorld, id: String, ox: int, oy: int, rot: int = 0, pid: int = 0) -> SimPlacementResult:
	var res: SimPlacementResult = SimPlacementResult.new()
	SimPlacement.validate(w, pid, KIT.sidx(id), ox, oy, rot, res)
	return res


func test_build_radius(t: TestCtx) -> void:
	var w: SimWorld = _world_with_hq()
	t.eq(_v(w, DefTestKit.S_BARRACKS, 19, 11).reason, SimEconConst.RSN_OK, "7.5 cells from the HQ centre: valid")
	t.eq(_v(w, DefTestKit.S_BARRACKS, 20, 11).reason, SimEconConst.RSN_OUT_OF_RADIUS, "8.5 cells")
	t.eq(SimPlacement.dist2_point_to_rect(0, 0, 8192, 0, 9216, 1024), 67108864, "exactly 8.0 cells is inside (d2 == r2)")
	t.eq(SimPlacement.dist2_point_to_rect(5, 5, 0, 0, 10, 10), 0, "inside the rect")
	t.eq(SimPlacement.footprint_center_x(w, KIT.sidx(DefTestKit.S_HQ), 10, 0), 11776, "centre x of a 3x3 at cell 10")
	# a second HQ extends the radius; an enemy / BUILDUP HQ does not
	KIT.spawn_struct(w, DefTestKit.S_HQ, 0, 40, 10, 0, false)
	w.step()
	t.eq(_v(w, DefTestKit.S_BARRACKS, 45, 11).reason, SimEconConst.RSN_OUT_OF_RADIUS, "BUILDUP HQ gives no radius")
	KIT.run(w, 35)
	t.eq(_v(w, DefTestKit.S_BARRACKS, 45, 11).reason, SimEconConst.RSN_OK, "valid within 8 of either HQ once ACTIVE")
	KIT.spawn_struct(w, DefTestKit.S_HQ, 1, 60, 60)
	w.step()
	t.eq(_v(w, DefTestKit.S_BARRACKS, 65, 61).reason, SimEconConst.RSN_OUT_OF_RADIUS, "an enemy HQ never extends my radius")


func test_overlap_terrain_and_margin(t: TestCtx) -> void:
	var w: SimWorld = _world_with_hq()
	KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 14, 10, 600)
	w.step()
	var r: SimPlacementResult = _v(w, DefTestKit.S_BARRACKS, 15, 11)
	t.eq(r.reason, SimEconConst.RSN_STRUCTURE_BLOCK, "overlap with a structure")
	t.eq(r.cells[0], SimEconConst.CF_STRUCTURE, "the failing cell is marked")
	t.eq(_v(w, DefTestKit.S_BARRACKS, 0, 10).reason, SimEconConst.RSN_TERRAIN, "outside the 1-cell margin")
	t.eq(_v(w, DefTestKit.S_BARRACKS, 200, 10).reason, SimEconConst.RSN_TERRAIN, "outside the map")
	KIT.spawn_struct(w, DefTestKit.S_HQ, 1, 2, 10)
	w.step()
	t.eq(_v(w, DefTestKit.S_BARRACKS, 1, 10, 0, 1).reason, SimEconConst.RSN_TERRAIN, "the 2-cell nav border is not buildable")


func test_deposit_and_debris(t: TestCtx) -> void:
	var dz: DebrisZones = DebrisZones.new()
	var w: SimWorld = _world_with_hq({"opts": {"systems": [dz]}})
	w.map.field_of[12 * 96 + 16] = 1
	var r: SimPlacementResult = _v(w, DefTestKit.S_BARRACKS, 15, 11)
	t.eq(r.reason, SimEconConst.RSN_DEPOSIT, "deposit field cell")
	t.eq(r.cells[1 * 2 + 1], SimEconConst.CF_DEPOSIT, "marked")
	dz.cells = PackedInt32Array([12 * 96 + 12])
	t.eq(_v(w, DefTestKit.S_BARRACKS, 13, 13).reason, SimEconConst.RSN_OK, "outside the debris")
	t.eq(_v(w, DefTestKit.S_BARRACKS, 12, 12).reason, SimEconConst.RSN_STRUCTURE_BLOCK, "the HQ is there")
	t.eq(_v(w, DefTestKit.S_BARRACKS, 12, 14).reason, SimEconConst.RSN_OK, "clear")
	dz.cells = PackedInt32Array([14 * 96 + 12])
	t.eq(_v(w, DefTestKit.S_BARRACKS, 12, 14).reason, SimEconConst.RSN_DEBRIS, "Horizon debris")


func test_units(t: TestCtx) -> void:
	var w: SimWorld = _world_with_hq()
	var enemy: SimEntity = K_rifle(w, 1, 17 * 1024 + 500, 12 * 1024 + 500)
	t.eq(_v(w, DefTestKit.S_BARRACKS, 17, 12).reason, SimEconConst.RSN_UNIT_BLOCK, "an enemy unit blocks")
	w.remove_entity(enemy.id, SimEvent.REM_SCRIPT)
	w.step()
	var mine: SimEntity = K_rifle(w, 0, 17 * 1024 + 500, 12 * 1024 + 500)
	t.eq(_v(w, DefTestKit.S_BARRACKS, 17, 12).reason, SimEconConst.RSN_OK, "the movement facade ejects friendly units (SimMovement.eject_units_from_rect), so a friendly unit does not block")
	w.remove_entity(mine.id, SimEvent.REM_SCRIPT)
	var w2: SimWorld = _world_with_hq({"opts": {"systems": [EjectMove.new()]}})
	K_rifle(w2, 0, 17 * 1024 + 500, 12 * 1024 + 500)
	t.eq(_v(w2, DefTestKit.S_BARRACKS, 17, 12).reason, SimEconConst.RSN_OK, "a friendly mobile unit is ejected, not blocking")
	K_rifle(w2, 1, 12 * 1024 + 500, 16 * 1024 + 500)
	t.eq(_v(w2, DefTestKit.S_BARRACKS, 12, 16).reason, SimEconConst.RSN_UNIT_BLOCK, "an enemy still blocks")


func K_rifle(w: SimWorld, owner: int, x: int, y: int) -> SimEntity:
	return w.spawn_unit(KIT.uidx(DefTestKit.U_RIFLEMAN), owner, x, y)


func test_aprons(t: TestCtx) -> void:
	var w: SimWorld = _world_with_hq()
	KIT.spawn_struct(w, DefTestKit.S_BARRACKS, 0, 14, 10, 500)  # exit cell (14, 12)
	w.step()
	t.eq(_v(w, DefTestKit.S_GENERATOR, 14, 12).reason, SimEconConst.RSN_APRON, "covers another producer's apron")
	t.eq(_v(w, DefTestKit.S_GENERATOR, 16, 12).reason, SimEconConst.RSN_OK, "next to the apron is fine")
	# own apron blocked: a refinery whose exit cell (x, y + 3) lies on a structure
	KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 10, 16, 600)
	w.step()
	t.eq(_v(w, DefTestKit.S_REFINERY, 10, 13).reason, SimEconConst.RSN_APRON, "own exit cell blocked by a structure")
	t.eq(_v(w, DefTestKit.S_REFINERY, 12, 13).reason, SimEconConst.RSN_OK, "free apron")


func test_dock_shoreline(t: TestCtx) -> void:
	var d: GameData = DefTestKit.small_data()
	var dock: DefStructure = d.structures[d.structure_idx(DefTestKit.S_TURRET)]
	dock.fp_w = 3
	dock.fp_h = 3
	dock.place_mask = DefEnums.PLACE_SHORELINE
	dock.queue_kind = DefEnums.QueueKind.NAVAL
	dock.exit_dx = 0
	dock.exit_dy = 3
	var di: int = d.structure_idx(DefTestKit.S_TURRET)
	var hq: int = d.structure_idx(DefTestKit.S_HQ)
	var w: SimWorld = KIT.make_world({"data": d, "map": KIT.make_lake_map({di: MapFootprint.new(3, 3, PackedByteArray(), true), hq: MapFootprint.new(3, 3)})})
	# the HQ on land at origin (28, 40): the island (36, 40) is 6.5 cells away
	w.spawn_structure(hq, 0, 29 * 1024 + 512, 41 * 1024 + 512, 0, 0, 0, 0, SimEvent.SPAWN_PLACED)
	w.step()
	var res: SimPlacementResult = SimPlacementResult.new()
	for rot: int in 4:
		t.eq(SimPlacement.validate(w, 0, di, 36, 40, rot, res), SimEconConst.RSN_OK, "dock on the island, rotation %d" % rot)
		t.check(res.berth_ok, "berth ok")
	t.eq(SimPlacement.validate(w, 0, di, 22, 40, 0, res), SimEconConst.RSN_NEEDS_SHORE, "land berth")
	t.eq(SimPlacement.validate(w, 0, di, 33, 40, 0, res), SimEconConst.RSN_TERRAIN, "a footprint in deep water is not land")


func test_strategic_limit(t: TestCtx) -> void:
	var d: GameData = DefTestKit.small_data()
	var g: DefStructure = d.structures[d.structure_idx(DefTestKit.S_TURRET)]
	g.max_per_player = 1
	g.flags |= DefEnums.SF_STRATEGIC
	var gi: int = g.index
	var w: SimWorld = KIT.make_world({"data": d})
	KIT.spawn_struct(w, DefTestKit.S_HQ, 0, 10, 10)
	w.step()
	var res: SimPlacementResult = SimPlacementResult.new()
	t.eq(SimPlacement.validate(w, 0, gi, 14, 10, 0, res), SimEconConst.RSN_OK, "the first launcher")
	var x: int = SimPlacement.footprint_center_x(w, gi, 14, 0)
	var y: int = SimPlacement.footprint_center_y(w, gi, 10, 0)
	w.spawn_structure(gi, 0, x, y, 0, SimFlags.F_UNDER_CONSTRUCTION, 5000, 0, SimEvent.SPAWN_PLACED)
	w.step()
	t.eq(SimPlacement.validate(w, 0, gi, 16, 10, 0, res), SimEconConst.RSN_STRATEGIC_LIMIT, "max one per player (BUILDUP counts)")


func test_hq_site_and_find_site(t: TestCtx) -> void:
	var w: SimWorld = KIT.make_world()
	var mcv: SimEntity = w.spawn_unit(KIT.uidx(DefTestKit.U_MCV), 0, 30 * 1024 + 512, 30 * 1024 + 512, 0, 0, 3000)
	w.step()
	var res: SimPlacementResult = SimPlacementResult.new()
	t.eq(SimPlacement.validate_hq_site(w, 0, mcv, res), SimEconConst.RSN_OK, "no radius, no prerequisite: the MCV itself does not block")
	t.eq([res.ox, res.oy, res.w, res.h], [29, 29, 3, 3] as Array, "3x3 centred on the MCV cell")
	KIT.spawn_struct(w, DefTestKit.S_GENERATOR, 1, 31, 31)
	w.step()
	t.eq(SimPlacement.validate_hq_site(w, 0, mcv, res), SimEconConst.RSN_STRUCTURE_BLOCK, "blocked by a structure")
	var out: PackedInt32Array = PackedInt32Array([-1, -1])
	KIT.spawn_struct(w, DefTestKit.S_HQ, 0, 10, 10)
	w.step()
	t.check(SimPlacement.find_site(w, 0, KIT.sidx(DefTestKit.S_BARRACKS), 14, 10, 6, out), "find_site finds a spot")
	var chk: SimPlacementResult = SimPlacementResult.new()
	t.eq(SimPlacement.validate(w, 0, KIT.sidx(DefTestKit.S_BARRACKS), out[0], out[1], 0, chk), SimEconConst.RSN_OK, "and it validates")
	t.check(not SimPlacement.find_site(w, 0, KIT.sidx(DefTestKit.S_BARRACKS), 80, 80, 3, out), "nothing near an unreachable point")
