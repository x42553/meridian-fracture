extends RefCounted
## Movement test helpers (no class_name; tests preload it): ASCII terrain maps on the REAL terrain table, a world
## builder on DefTestKit.small_data() with START_NONE, adjustable ability stubs and spawn helpers.
##   '.' grass  '#' cliff  '~' deep  ',' shallow  'f' ford  'F' forest  'r' road  'b' beach  'm' marsh
##   'R' rock   'X' grass + SF_BLOCK

const K := preload("res://tests/support/sim_test_kit.gd")
const CELL: int = 1024
const LEGEND: Dictionary = {
	".": MapTerrain.T_GRASS, "#": MapTerrain.T_CLIFF, "~": MapTerrain.T_DEEP, ",": MapTerrain.T_SHALLOW,
	"f": MapTerrain.T_FORD, "F": MapTerrain.T_FOREST, "r": MapTerrain.T_ROAD, "b": MapTerrain.T_BEACH,
	"m": MapTerrain.T_MARSH, "R": MapTerrain.T_ROCK, "X": MapTerrain.T_GRASS,
}


## Stand-in for the abilities adapters movement reads (5.1 / 3.10.1).
class AbilStub:
	extends SimAbilitySystem
	var mult_bp: int = 10000
	var mult_for_def: Dictionary = {}  ## def_idx -> bp (overrides mult_bp)
	var immobile: bool = false
	var immobile_ids: Dictionary = {}  ## entity id -> true
	var locked: bool = false
	var pack_calls: int = 0

	func speed_units(e: SimEntity) -> int:
		var bp: int = mult_for_def.get(e.def_idx, mult_bp)
		return (e.move.speed_base * bp + 5000) / 10000

	func is_immobile(e: SimEntity) -> bool:
		return immobile or immobile_ids.has(e.id)

	func is_turn_locked(_e: SimEntity) -> bool:
		return locked

	func request_pack(_e: SimEntity) -> void:
		pack_calls += 1


## size x size rows of '.' with a 2-cell cliff border.
static func grid(size: int) -> PackedStringArray:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in size:
		var s: String = ""
		for x: int in size:
			s += "#" if (x < 2 or y < 2 or x >= size - 2 or y >= size - 2) else "."
		rows.append(s)
	return rows


static func rect(rows: PackedStringArray, x0: int, y0: int, x1: int, y1: int, ch: String) -> void:
	for y: int in range(y0, y1 + 1):
		var r: String = rows[y]
		rows[y] = r.substr(0, x0) + ch.repeat(x1 - x0 + 1) + r.substr(x1 + 1)


## Finalised map (8 spawns, default neutral ids, terrain from `rows`).
static func map_from(rows: PackedStringArray) -> MapData:
	var size: int = rows.size()
	var m: MapData = MapData.create(MapTerrain.load_default(), size)
	for y: int in size:
		for x: int in size:
			var ch: String = rows[y][x]
			m.terrain[y * size + x] = LEGEND[ch]
			m.flags[y * size + x] = MapData.SF_BLOCK if ch == "X" else 0
	for k: int in 8:
		m.spawns.append_array(PackedInt32Array([k, 10 * size + 10 + k, 0, 0, k & 1, 0]))
	m.slots = 8
	m.players = 8
	m.neutral_ids = MapData.NEUTRAL_IDS_DEFAULT.duplicate()
	m.finalize()
	return m


static func open_map(size: int) -> MapData:
	return map_from(grid(size))


## Fresh small_data() with the movement-relevant numbers of the spec's worked examples: tank = Guardian (tracked,
## medium, speed 102, accel_t 6, turn 85), rifleman = infantry (speed 87, accel_t 2), collector = light wheeled.
static func data() -> GameData:
	var d: GameData = DefTestKit.small_data()
	var inf: DefUnit = d.units[d.unit_idx(DefTestKit.U_RIFLEMAN)]
	inf.speed = 87
	inf.accel_t = 2
	var gd: DefUnit = d.units[d.unit_idx(DefTestKit.U_TANK)]
	gd.accel_t = 6
	# the players' roster clones were resolved before these edits: keep them equal (abilities' SimStats reads them)
	for r: DefRoster in d.rosters:
		if r.has_unit(d.unit_idx(DefTestKit.U_RIFLEMAN)):
			r.unit(d.unit_idx(DefTestKit.U_RIFLEMAN)).speed = 87
	return d


## `no_combat` disables the real combat system (its T_ATTACK_MOVE handler would replace the tests' stand-ins).
static func world(map: MapData, d: GameData = null, abil: SimAbilitySystem = null, players: int = 2, no_combat: bool = false) -> SimWorld:
	var cfg: SimMatchConfig = K.make_config(players, 4242, {"start_mode": SimMatchRules.START_NONE, "victory": 0, "neutral_structures": 0})
	var opts: Dictionary = {}
	if no_combat:
		opts["disable"] = ["SimCombatSystem"]
	if abil != null:
		opts["systems"] = [abil]
	return SimWorld.create(d if d != null else data(), cfg, map, opts)


static func spawn(w: SimWorld, id: String, cx: int, cy: int, owner: int = 0, facing: int = 0) -> SimEntity:
	return w.spawn_unit(w.data.unit_idx(id), owner, cx * CELL + CELL / 2, cy * CELL + CELL / 2, facing)


static func tank(w: SimWorld, cx: int, cy: int, owner: int = 0) -> SimEntity:
	return spawn(w, DefTestKit.U_TANK, cx, cy, owner)


static func rifle(w: SimWorld, cx: int, cy: int, owner: int = 0) -> SimEntity:
	return spawn(w, DefTestKit.U_RIFLEMAN, cx, cy, owner)


static func scout(w: SimWorld, cx: int, cy: int, owner: int = 0) -> SimEntity:
	return spawn(w, DefTestKit.U_COLLECTOR, cx, cy, owner)


## Steps until `pred` (Callable() -> bool) holds or `max_ticks` passed; returns the ticks stepped, -1 on timeout.
static func run_until(w: SimWorld, pred: Callable, max_ticks: int) -> int:
	for i: int in max_ticks:
		w.step()
		if pred.call():
			return i + 1
	return -1


## Counts events of `type` in the world's buffer (optionally with field b == `b`).
static func count_events(w: SimWorld, type: int, b: int = -1) -> int:
	var n: int = 0
	var d: PackedInt32Array = w.events.data
	for i: int in d.size() / SimEvent.STRIDE:
		if d[i * SimEvent.STRIDE] == type and (b < 0 or d[i * SimEvent.STRIDE + SimEvent.I_B] == b):
			n += 1
	return n


## Cell index of an entity.
static func cell_of(w: SimWorld, e: SimEntity) -> int:
	return (e.y >> 10) * w.map.w + (e.x >> 10)


## Re-classifies a unit def of `d` (movement fields only).
static func reclass(d: GameData, id: String, move_class: int, radius: int, size_class: int, home_layer: int, speed: int = 102) -> int:
	var i: int = d.unit_idx(id)
	var u: DefUnit = d.units[i]
	u.move_class = move_class
	u.radius = radius
	u.size_class = size_class
	u.home_layer = home_layer
	u.speed = speed
	for r: DefRoster in d.rosters:  # the roster clones feed abilities' SimStats (speed)
		if r.has_unit(i):
			r.unit(i).speed = speed
	return i


## Two ponds joined by one channel (`width` cells wide, rows centred on y = 32), rest land. `ch` = channel terrain.
static func sea_map(width: int, ch: String = "~") -> PackedStringArray:
	var rows: PackedStringArray = grid(64)
	rect(rows, 4, 4, 20, 59, "~")
	rect(rows, 44, 4, 59, 59, "~")
	var y0: int = 32 - (width - 1) / 2
	rect(rows, 21, y0, 43, y0 + width - 1, ch)
	return rows


## Random cliff clutter (same generator as tests/fixtures/path_fixture.gd) as a map with spawns.
static func clutter_map(size: int, pct: int, seed_value: int) -> MapData:
	var Pf: GDScript = load("res://tests/fixtures/path_fixture.gd")
	var rows: PackedStringArray = grid(size)
	var rng: RefCounted = Pf.Lcg.new(seed_value)
	var blocked: Dictionary = {}
	var target: int = size * size * pct / 100
	while blocked.size() < target:
		var rw: int = 2 + int(rng.call("next", 6))
		var rh: int = 2 + int(rng.call("next", 6))
		var x0: int = 2 + int(rng.call("next", size - 4 - rw))
		var y0: int = 2 + int(rng.call("next", size - 4 - rh))
		rect(rows, x0, y0, x0 + rw - 1, y0 + rh - 1, "#")
		for y: int in range(y0, y0 + rh):
			for x: int in range(x0, x0 + rw):
				blocked[y * size + x] = true
	return map_from(rows)


## Street grid: streets `street` wide every `pitch` cells, blocks between them are cliff.
static func urban_map(size: int, pitch: int, street: int) -> MapData:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in size:
		var r: String = ""
		for x: int in size:
			r += "#" if ((x % pitch) >= street and (y % pitch) >= street) or x < 2 or y < 2 or x >= size - 2 or y >= size - 2 else "."
		rows.append(r)
	return map_from(rows)
