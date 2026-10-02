extends RefCounted
## Map test helpers (no class_name; tests preload it). ASCII maps are square; the outer NAV_BORDER cells are
## impassable by the nav layer whatever they contain.
##   '.' grass  '#' cliff  '~' deep  ',' shallow  'f' ford  'F' forest  'r' road  'b' beach  'm' marsh
##   'R' rock   'p' pavement  'X' grass + SF_BLOCK  'n' grass + SF_NOBUILD

const MoveTable := preload("res://tests/fixtures/fixture_move_table.gd")
const LEGEND: Dictionary = {
	".": MapTerrain.T_GRASS, "#": MapTerrain.T_CLIFF, "~": MapTerrain.T_DEEP, ",": MapTerrain.T_SHALLOW,
	"f": MapTerrain.T_FORD, "F": MapTerrain.T_FOREST, "r": MapTerrain.T_ROAD, "b": MapTerrain.T_BEACH,
	"m": MapTerrain.T_MARSH, "R": MapTerrain.T_ROCK, "p": MapTerrain.T_PAVEMENT, "X": MapTerrain.T_GRASS,
	"n": MapTerrain.T_GRASS,
}


static func tt() -> MapTerrain:
	return MapTerrain.from_dict(MoveTable.terrain_dict(), MoveTable.make())


## Builds and finalizes a square map from ASCII rows (see the legend above).
static func ascii(rows: PackedStringArray) -> MapData:
	var size: int = rows.size()
	var m: MapData = MapData.create(tt(), size)
	for y: int in size:
		for x: int in size:
			var ch: String = rows[y][x]
			m.terrain[y * size + x] = LEGEND[ch]
			m.flags[y * size + x] = MapData.SF_BLOCK if ch == "X" else (MapData.SF_NOBUILD if ch == "n" else 0)
	m.finalize()
	return m


## size x size grass map (no rim) built through create(), finalized; `patch` cells (Dictionary cell -> type) are
## overridden before finalize.
static func open(size: int, patch: Dictionary = {}) -> MapData:
	var m: MapData = MapData.create(tt(), size)
	m.terrain.fill(MapTerrain.T_GRASS)
	m.flags.fill(0)
	for c: int in patch:
		m.terrain[c] = patch[c]
	m.finalize()
	return m


## Rectangle of terrain `t` into an unfinalized map's layers.
static func rect(m: MapData, x0: int, y0: int, x1: int, y1: int, t: int) -> void:
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			m.terrain[y * m.w + x] = t
