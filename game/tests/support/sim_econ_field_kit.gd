class_name SimEconFieldKit
extends RefCounted
## Harvest test kit of the economy slice (E5): a flat 96x96 map with deposit FIELDS (disc of cells, per-cell credits)
## and worlds on it with HQ / Generator / Refinery / Collector, built on SimEconKit. Never lives under src/.

const K := preload("res://tests/support/sim_econ_kit.gd")
const CELL: int = SimConfig.CELL
const SIZE: int = 96


## `fields` = [{cx, cy, r (cells), per_cell, kind (MapData.FK_*), klass (0 / 1 rich)}]; footprints of the kit registered.
static func make_map(fields: Array, real: GameData = null) -> MapData:
	var m: MapData = MapData.create(MapTerrain.load_default(), SIZE)
	m.terrain.fill(MapTerrain.T_GRASS)
	m.spawns.append_array(PackedInt32Array([0, 20 * SIZE + 20, 0, 0, 0, 0, 1, 70 * SIZE + 70, 0, 0, 1, 0]))
	m.slots = 2
	m.players = 2
	for k: int in fields.size():
		var f: Dictionary = fields[k]
		var cells: int = 0
		var r: int = int(f["r"])
		for y: int in range(int(f["cy"]) - r, int(f["cy"]) + r + 1):
			for x: int in range(int(f["cx"]) - r, int(f["cx"]) + r + 1):
				if (x - int(f["cx"])) * (x - int(f["cx"])) + (y - int(f["cy"])) * (y - int(f["cy"])) <= r * r:
					m.field_of[y * SIZE + x] = k + 1
					m.deposit_max[y * SIZE + x] = int(f["per_cell"])
					cells += 1
		var c: int = int(f["cy"]) * SIZE + int(f["cx"])
		m.fields.append_array(PackedInt32Array([k + 1, c, r, cells, cells * int(f["per_cell"]), int(f.get("kind", MapData.FK_START)), 0, c, int(f.get("klass", 0)), 0]))
	m.finalize()
	if real != null:
		for sd: DefStructure in real.structures:
			m.set_footprint(SimEntity.Kind.STRUCTURE, sd.index, MapFootprint.new(sd.fp_w, sd.fp_h, sd.fp_mask, (sd.place_mask & DefEnums.PLACE_SHORELINE) != 0))
		return m
	var d: GameData = K.data()
	var S: int = SimEntity.Kind.STRUCTURE
	m.set_footprint(S, d.structure_idx(DefTestKit.S_HQ), MapFootprint.new(3, 3))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_BARRACKS), MapFootprint.new(2, 2))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_FACTORY), MapFootprint.new(3, 2, PackedByteArray(), true))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_GENERATOR), MapFootprint.new(2, 2))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_REFINERY), MapFootprint.new(3, 3))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_TURRET), MapFootprint.new(1, 1))
	return m


## HQ (start) + Generator + Refinery at (23, 22) with its free Collector. Combat is disabled so raids do not kill.
static func make_world(fields: Array, o: Dictionary = {}) -> SimWorld:
	var opts: Dictionary = {"disable": ["SimCombatSystem"]}
	var w: SimWorld = K.make_world({"start_mode": 0, "map": make_map(fields), "opts": opts, "rules": o.get("rules", {})})
	if bool(o.get("base", true)):
		K.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 23, 19)
		K.spawn_struct(w, DefTestKit.S_REFINERY, 0, 23, 22)
	w.step()  # flush the spawn queue: the free Collector is in the unit lists
	return w


static func collectors(w: SimWorld, pid: int = 0) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	var cu: int = K.uidx(DefTestKit.U_COLLECTOR)
	for u: SimEntity in w.units_of(pid):
		if u.def_idx == cu:
			out.append(u)
	return out
