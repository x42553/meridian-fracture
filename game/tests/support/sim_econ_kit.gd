class_name SimEconKit
extends RefCounted
## Test kit of the economy slice (E0 / E2 / E4): DefTestKit.small_data() with exit cells patched in (the stub
## structures carry none), sandbox worlds without start entities, structure spawn helpers and the two seams of the
## slice (placement result, command submission). Never lives under src/.

const K := preload("res://tests/support/sim_test_kit.gd")
const CELL: int = SimConfig.CELL

static var _data: GameData = null


static func data() -> GameData:
	if _data == null:
		_data = DefTestKit.small_data()
		var ex: Dictionary = {
			DefTestKit.S_BARRACKS: 2, DefTestKit.S_FACTORY: 2, DefTestKit.S_REFINERY: 3, DefTestKit.S_HQ: 3,
		}
		for id: String in ex:
			var s: DefStructure = _data.structures[_data.structure_idx(id)]
			s.exit_dx = 0
			s.exit_dy = ex[id]
		for r: DefRoster in _data.rosters:
			for id: String in ex:
				var rs: DefStructure = r.structures[_data.structure_idx(id)]
				if rs != null:
					rs.exit_dy = ex[id]
	return _data


## A 96x96 map with a beach island (3x3 at 36..38 x 40..42) in a lake (32..50) and two spawns; `footprints` = {s_idx: fp}
## are registered on it. For shoreline (Dock) placement tests.
static func make_lake_map(footprints: Dictionary) -> MapData:
	var m: MapData = MapData.create(MapTerrain.load_default(), 96)
	m.terrain.fill(MapTerrain.T_GRASS)
	for y: int in range(32, 51):
		for x: int in range(32, 51):
			m.terrain[y * 96 + x] = MapTerrain.T_DEEP
	for y: int in range(40, 43):
		for x: int in range(36, 39):
			m.terrain[y * 96 + x] = MapTerrain.T_BEACH
	m.spawns.append_array(PackedInt32Array([0, 20 * 96 + 20, 0, 0, 0, 0, 1, 70 * 96 + 70, 0, 0, 1, 0]))
	m.slots = 2
	m.players = 2
	m.finalize()
	for si: int in footprints:
		m.set_footprint(SimEntity.Kind.STRUCTURE, si, footprints[si])
	return m


static func sidx(id: String) -> int:
	return data().structure_idx(id)


static func uidx(id: String) -> int:
	return data().unit_idx(id)


## Sandbox world: no start entities (start_mode NONE), victory off, `players` players (pid 0 human).
static func make_world(o: Dictionary = {}) -> SimWorld:
	var rules: Dictionary = {"start_mode": int(o.get("start_mode", 2)), "victory": 0}
	for k: String in (o.get("rules", {}) as Dictionary):
		rules[k] = o["rules"][k]
	var cfg: SimMatchConfig = K.make_config(int(o.get("players", 2)), int(o.get("seed", K.SEED)), rules, o.get("teams", PackedInt32Array()))
	var opts: Dictionary = (o.get("opts", {}) as Dictionary).duplicate()
	if o.has("handicap"):
		for s: SimPlayerSlot in cfg.players:
			s.handicap = int(o["handicap"])
	var d: GameData = o["data"] if o.has("data") else data()
	var m: MapData = o["map"] if o.has("map") else K.make_map()
	return SimWorld.create(d, cfg, m, opts)


## Structure with its origin (top-left) cell at (ox, oy). `active` false = BUILDUP (as placement spawns it).
static func spawn_struct(w: SimWorld, id: String, pid: int, ox: int, oy: int, paid: int = 0, active: bool = true, rot: int = 0) -> SimEntity:
	var si: int = sidx(id)
	var x: int = SimPlacement.footprint_center_x(w, si, ox, rot)
	var y: int = SimPlacement.footprint_center_y(w, si, oy, rot)
	var flags: int = 0 if active else SimFlags.F_UNDER_CONSTRUCTION
	return w.spawn_structure(si, pid, x, y, rot * 1024, flags, paid, 0, SimEvent.SPAWN_PLACED)


static func econ(w: SimWorld, pid: int) -> SimPlayerEcon:
	return w.players[pid].econ


static func run(w: SimWorld, n: int) -> void:
	for _i: int in n:
		w.step()


## Events of the buffer since the last clear: rows of [type, tick, x, y, a, b, c, d, e, f].
static func events_of(w: SimWorld, type: int) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var buf: PackedInt32Array = w.events.data
	var n: int = buf.size() / SimEvent.STRIDE
	for i: int in n:
		if buf[i * SimEvent.STRIDE] == type:
			out.append(buf.slice(i * SimEvent.STRIDE, (i + 1) * SimEvent.STRIDE))
	return out
