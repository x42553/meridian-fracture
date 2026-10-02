extends RefCounted
## SimMatchSetup (INT1): footprints and neutral defs on a real MapData, the neutral entity kind, the DEPLOY executor's
## refusal of non-MCVs, the occupancy invariants (INV-4 / INV-16) and the rotatable placement search.

const K := preload("res://tests/support/sim_test_kit.gd")


func _real_map() -> MapData:
	var m: MapData = MapData.create(MapTerrain.load_default(), 64)
	for k: int in 2:
		m.spawns.append_array(PackedInt32Array([k, (20 + k * 20) * 64 + 20 + k * 20, 0, 0, k & 1, 0]))
	m.slots = 2
	m.players = 2
	m.neutral_ids = MapData.NEUTRAL_IDS_DEFAULT.duplicate()
	m.neutrals.append_array(PackedInt32Array([1, 30 * 64 + 10, 2, 2, 0, 0, 0, 0]))  # a substation (2x2) at cell (10, 30)
	m.finalize()
	return m


func test_register_map_defs(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	var m: MapData = _real_map()
	t.is_null(m.footprint_of(SimEntity.Kind.STRUCTURE, d.structure_idx("structure.shared.barracks")), "nothing registered yet")
	SimMatchSetup.register_map_defs(m, d)
	var dock: MapFootprint = m.footprint_of(SimEntity.Kind.STRUCTURE, d.structure_idx("structure.shared.dock"))
	t.check(dock.rotatable, "only the shoreline Dock rotates")
	t.check_false(m.footprint_of(SimEntity.Kind.STRUCTURE, d.structure_idx("structure.shared.factory")).rotatable, "Factory does not")
	var sub: int = d.neutral_idx("neutral.substation")
	t.eq(m.neutral_def_for_kind(1), sub, "substation kind -> DefNeutral")
	t.eq(m.neutral_ent_kind(1), SimEntity.Kind.NEUTRAL, "spawned as Kind.NEUTRAL")
	t.eq(m.neutral_ent_kind(0), SimEntity.Kind.NEUTRAL, "every default neutral id resolves")
	t.eq(m.clone_fresh().neutral_ent_kind(1), SimEntity.Kind.NEUTRAL, "the clone keeps the entity kinds")
	t.eq(K.make_map().neutral_ent_kind(0), SimEntity.Kind.STRUCTURE, "the small-data kit keeps the STRUCTURE convention")
	# a world from it spawns the substation with its footprint
	var pl: Array = [
		{"pid": 0, "kind": "ai", "roster": "roster.napc.vanilla", "team": 1, "color": 0, "start": 0},
		{"pid": 1, "kind": "ai", "roster": "roster.nec.vanilla", "team": 2, "color": 1, "start": 1}]
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 1, "map": {}, "rules": {}, "players": pl})
	var w: SimWorld = SimMatchSetup.create_world(d, cfg, m)
	if not t.not_null(w, "world"):
		return
	t.eq(w.neutrals.size(), 1, "one neutral entity")
	var n: SimEntity = w.neutrals[0]
	t.eq(w.struct_at(10, 30), n.id, "and it occupies (10, 30)")
	t.eq(w.struct_at(11, 31), n.id, "and (11, 31)")
	t.eq(w.struct_at(12, 30), 0, "but not (12, 30)")
	t.eq(SimInvariants.check(w), PackedStringArray(), "invariants clean (INV-4 / INV-16 included)")


func test_occupancy_invariants_detect_corruption(t: TestCtx) -> void:
	var w: SimWorld = K.make_world({"movers": false})
	var s: SimEntity = w.structures_of(0)[0]
	t.eq(SimInvariants.check(w), PackedStringArray(), "healthy")
	# a stray occupant id
	var stray: int = w.map.idx(3, 3)
	w.map.occ[stray] = 9999
	var msgs: PackedStringArray = SimInvariants.check(w)
	t.check(msgs.size() >= 1 and msgs[0].begins_with("INV-16"), "an occupant without an entity is INV-16 (%s)" % str(msgs))
	w.map.occ[stray] = -1
	# a hole in a footprint
	var fp: MapFootprint = w.map.footprint_of(s.kind, s.def_idx)
	var cx: int = (s.x - fp.w * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT
	var cy: int = (s.y - fp.h * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT
	var idx: int = w.map.idx(cx, cy)
	var keep: int = w.map.occ[idx]
	w.map.occ[idx] = -1
	msgs = SimInvariants.check(w)
	t.check(msgs.size() >= 1 and msgs[0].begins_with("INV-4"), "a missing footprint cell is INV-4 (%s)" % str(msgs))
	w.map.occ[idx] = keep
	t.eq(SimInvariants.check(w), PackedStringArray(), "healthy again")


func test_find_site_rot_zero_equals_find_site(t: TestCtx) -> void:
	var w: SimWorld = K.make_world({"movers": false})
	var barracks: int = K.structure_def(DefTestKit.S_BARRACKS)
	var a: PackedInt32Array = PackedInt32Array([0, 0])
	var b: PackedInt32Array = PackedInt32Array([0, 0])
	var ok_a: bool = SimPlacement.find_site(w, 0, barracks, 22, 22, 6, a)
	var ok_b: bool = SimPlacement.find_site_rot(w, 0, barracks, 22, 22, 6, 0, b)
	t.eq([ok_a, a], [ok_b, b] as Array, "find_site == find_site_rot(rot 0)")
