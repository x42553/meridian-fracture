extends RefCounted
## AB-02 / AB-03 against the REAL balance data: every ability-bearing unit spawns with its slots, real rosters give
## the stats, the start HQs see their surroundings and the enemy stays in the shroud.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const CELL: int = 1024


func _world(rules: Dictionary = {}) -> SimWorld:
	var d: GameData = GameData.load_default()
	var cells: PackedInt32Array = PackedInt32Array([20 * 96 + 20, 70 * 96 + 70])
	var m: MapData = MapData.for_test(96, 96, cells, PackedInt32Array(), 0x5EED)
	for s: DefStructure in d.structures:
		m.set_footprint(SimEntity.Kind.STRUCTURE, s.index, MapFootprint.new(s.fp_w, s.fp_h, s.fp_mask, (s.place_mask & DefEnums.PLACE_SHORELINE) != 0))
	var pl: Array = []
	for i: int in 2:
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": "roster.napc.usa" if i == 0 else "roster.nec.vanilla", "team": i + 1, "color": i, "start": i, "handicap": 100})
	var r: Dictionary = {"victory": 0, "fog": true}
	for k: Variant in rules.keys():
		r[k] = rules[k]
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 7, "map": {"id": "real"}, "rules": r, "players": pl})
	return SimWorld.create(d, cfg, m, {"disable": ["SimMovementSystem"]})


func test_every_ability_unit_gets_its_slots(t: TestCtx) -> void:
	var w: SimWorld = _world({"start_mode": SimMatchRules.START_NONE})
	if not t.not_null(w, "world"):
		return
	var spawned: Array[SimEntity] = []
	var i: int = 0
	for u: DefUnit in w.data.units:
		if (u.ability_mask & K.EXECUTED_MASK) == 0:
			continue
		var e: SimEntity = w.spawn_unit(u.index, 0, (10 + (i % 20) * 3) * CELL + 512, (10 + (i / 20) * 3) * CELL + 512)
		if e != null:
			spawned.append(e)
		i += 1
	t.gt(spawned.size(), 60, "many ability-bearing unit defs (%d)" % spawned.size())
	w.run(30)
	var cloakers: int = 0
	var detectors: int = 0
	var subs: int = 0
	for e2: SimEntity in spawned:
		var expect: int = 0
		for a: DefAbility in w.abilities.abilities_of(w, e2):
			if ((K.EXECUTED_MASK >> a.kind) & 1) != 0:
				expect += 1
		if w.data.units[e2.def_idx].params.has("summon_attached_idx"):
			expect += 1  # AB3: the Lagos carrier's summon_orbit slot for its repair drone
		t.eq(e2.abil.n_slots, mini(expect, K.MAX_SLOTS), "%s: one slot per executed ability" % w.data.units[e2.def_idx].id)
		if e2.abil.slot_of_kind(K.AK_CAMOUFLAGE) >= 0:
			cloakers += 1
			t.check(e2.abil.watch & K.WF_CLOAK != 0, "cloakers are on the watch list")
		if e2.abil.slot_of_kind(K.AK_DETECTOR) >= 0:
			detectors += 1
		if e2.abil.slot_of_kind(K.AK_SUBMERGE) >= 0:
			subs += 1
			t.eq(e2.vis.concealed, 1, "submarines start concealed")
		var rs: PackedInt32Array = w.players[0].view.resolved_stats(DefEnums.Kind.UNIT, e2.def_idx)
		t.eq(w.abilities.speed_units(e2), rs[DefEnums.Stat.SPEED], "speed_units = the roster's resolved speed")
	t.gt(cloakers, 3, "camouflage units exist (%d)" % cloakers)
	t.gt(detectors, 10, "detector units exist (%d)" % detectors)
	t.ge(subs, 1, "submarines exist")
	t.eq(w.abilities.debug_validate(w).size(), 0, "debug_validate clean")
	t.eq(w.vision.debug_rebuild_compare(w), 0, "grids consistent")


func test_start_bases_fog(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if not t.not_null(w, "world"):
		return
	w.run(6)
	var hq0: SimEntity = w.structures_of(0)[0]
	var hq1: SimEntity = w.structures_of(1)[0]
	t.check(w.cell_visible(0, hq0.x >> 10, hq0.y >> 10), "own HQ cell visible")
	t.check_false(w.cell_visible(0, hq1.x >> 10, hq1.y >> 10), "enemy HQ cell not visible")
	t.check_false(w.cell_explored(0, hq1.x >> 10, hq1.y >> 10), "and still shroud")
	t.check_false(w.fog.entity_visible(0, hq1), "enemy HQ hidden")
	t.check(w.fog.entity_visible(1, hq1), "own HQ visible to its owner")
	t.eq(hq0.vis.r_cells, SimDisc.radius_cells(w.data.structures[hq0.def_idx].sight), "HQ sight radius from the def")
	w.run(400)
	t.eq(w.vision.debug_rebuild_compare(w), 0, "grids consistent after 400 ticks")
	t.eq(w.abilities.debug_validate(w).size(), 0, "debug_validate clean")
