extends RefCounted
## MapData fixtures for the terrain view tests (no class_name; tests preload it). Built with MapData.create + finalize,
## heights written before finalize (the view layers are not part of the static hash).

const T_GRASS: int = MapTerrain.T_GRASS
const T_ROAD: int = MapTerrain.T_ROAD


static func tt() -> MapTerrain:
	return MapTerrain.load_default()


## size x size grass map with rim, heights from `height_fn(cx, cy) -> int` (1/32 m units) when valid, else a gentle hill.
static func map(size: int, height_fn: Callable = Callable(), family: int = 0, biome: int = 0, patch: Callable = Callable()) -> MapData:
	var m: MapData = MapData.create(tt(), size)
	m.family = family
	m.biome = biome
	m.seed_value = 4242
	for cy: int in size + 1:
		for cx: int in size + 1:
			var v: int = 0
			if height_fn.is_valid():
				v = height_fn.call(cx, cy) as int
			else:
				v = 96 + ((cx * 7 + cy * 13) % 29) * 3 + int(sin(float(cx) * 0.11) * 40.0 + cos(float(cy) * 0.09) * 40.0)
			m.heights[cy * (size + 1) + cx] = v
	if patch.is_valid():
		patch.call(m)
	m.finalize()
	return m


static func source(size: int, height_fn: Callable = Callable(), family: int = 0, biome: int = 0, patch: Callable = Callable()) -> ViewTerrainSource:
	return ViewTerrainSource.from_map(map(size, height_fn, family, biome, patch))


static func paint(m: MapData, x0: int, y0: int, x1: int, y1: int, t: int) -> void:
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			m.terrain[y * m.w + x] = t
