extends RefCounted
## AiTechGraph: missing() vectors of ai.md 10.1 (HQ is a preset), depth, unit prerequisites.


func _g() -> AiTechGraph:
	var d: GameData = SimMatchKit.data()
	return AiTechGraph.build(d, d.rosters[d.roster_idx("roster.napc.vanilla")])


func _names(g: AiTechGraph, l: PackedInt32Array) -> Array:
	var out: Array = []
	for s: int in l:
		out.append(g.data.structures[s].id.get_slice(".", 2))
	return out


func test_missing_vectors(t: TestCtx) -> void:
	var g: AiTechGraph = _g()
	var d: GameData = g.data
	t.eq(_names(g, g.missing(d.structure_idx("structure.shared.radar"))), ["generator", "refinery", "factory", "radar"] as Array)
	var have: PackedInt32Array = PackedInt32Array()
	have.resize(d.structures.size())
	for n: String in ["generator", "refinery", "factory", "radar"]:
		have[d.structure_idx("structure.shared." + n)] = 1
	t.eq(_names(g, g.missing(d.structure_idx("structure.shared.laboratory"), have)), ["laboratory"] as Array)
	t.eq(_names(g, g.missing(d.structure_idx("structure.napc.atlas_kinetic_array"))), ["generator", "refinery", "factory", "radar", "laboratory", "atlas_kinetic_array"] as Array)
	t.eq(_names(g, g.missing(d.structure_idx("structure.shared.dock"))), ["generator", "refinery", "dock"] as Array)
	t.eq(_names(g, g.missing(d.structure_idx("structure.shared.watchtower"))), ["generator", "barracks", "watchtower"] as Array)


func test_pending_and_depth(t: TestCtx) -> void:
	var g: AiTechGraph = _g()
	var d: GameData = g.data
	var pend: PackedInt32Array = PackedInt32Array()
	pend.resize(d.structures.size())
	pend[d.structure_idx("structure.shared.generator")] = 1
	t.eq(_names(g, g.missing(d.structure_idx("structure.shared.refinery"), PackedInt32Array(), pend)), ["refinery"] as Array, "under construction is excluded")
	t.eq(g.tier_of(d.structure_idx("structure.shared.headquarters")), 0)
	t.eq(g.tier_of(d.structure_idx("structure.shared.radar")), 4, "radar chain: gen, ref, factory, radar (+HQ root)")
	t.gt(g.tier_of(d.structure_idx("structure.shared.laboratory")), g.tier_of(d.structure_idx("structure.shared.radar")))


func test_unit_prerequisites(t: TestCtx) -> void:
	var g: AiTechGraph = _g()
	var d: GameData = g.data
	var tank: int = d.unit_idx("unit.napc.guardian_tank")
	var need: PackedInt32Array = g.missing_for_unit(tank)
	t.check(need.size() >= 1, "a tank needs at least the factory chain")
	t.eq(g.data.structures[need[need.size() - 1]].queue_kind, DefEnums.QueueKind.VEHICLE, "last = the producer")
