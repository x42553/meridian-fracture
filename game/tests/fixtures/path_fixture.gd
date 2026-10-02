extends RefCounted
## Deterministic path-test maps (no class_name; tests preload it): random cliff clutter at a given density and a
## street grid ("urban maze"), plus a tiny LCG and a random-pair picker. Shared by the MapNavGraph / MapPathSearch
## tests and the micro-bench.

const Fx := preload("res://tests/fixtures/map_fixture.gd")


class Lcg extends RefCounted:
	var s: int = 1

	func _init(seed_value: int) -> void:
		s = (seed_value * 2654435761 + 12345) & 0x7FFFFFFF

	func next(n: int) -> int:
		s = (s * 1103515245 + 12345) & 0x7FFFFFFF
		return (s >> 8) % n


## size x size map: NAV_BORDER only, grass with random cliff rectangles (2..7 x 2..7) until `pct` percent of the
## cells are blocked.
static func clutter(size: int, pct: int, seed_value: int) -> MapData:
	var m: MapData = MapData.create(Fx.tt(), size)
	m.terrain.fill(MapTerrain.T_GRASS)
	m.flags.fill(0)
	var rng: Lcg = Lcg.new(seed_value)
	var target: int = size * size * pct / 100
	var blocked: int = 0
	while blocked < target:
		var rw: int = 2 + rng.next(6)
		var rh: int = 2 + rng.next(6)
		var x0: int = 2 + rng.next(size - 4 - rw)
		var y0: int = 2 + rng.next(size - 4 - rh)
		for y: int in range(y0, y0 + rh):
			for x: int in range(x0, x0 + rw):
				if m.terrain[y * size + x] != MapTerrain.T_CLIFF:
					m.terrain[y * size + x] = MapTerrain.T_CLIFF
					blocked += 1
	m.finalize()
	return m


## Street grid: streets `street` wide every `pitch` cells, the blocks between them are cliff.
static func urban(size: int, pitch: int, street: int) -> MapData:
	var m: MapData = MapData.create(Fx.tt(), size)
	m.terrain.fill(MapTerrain.T_GRASS)
	m.flags.fill(0)
	for y: int in size:
		for x: int in size:
			if (x % pitch) >= street and (y % pitch) >= street:
				m.terrain[y * size + x] = MapTerrain.T_CLIFF
	m.finalize()
	return m


## `count` (start, goal) cell pairs, both with clearance >= size, Chebyshev distance >= min_dist (flat array).
static func pairs(m: MapData, np: int, size: int, count: int, min_dist: int, seed_value: int) -> PackedInt32Array:
	var rng: Lcg = Lcg.new(seed_value)
	var out: PackedInt32Array = PackedInt32Array()
	var guard: int = 0
	while out.size() < count * 2 and guard < count * 5000:
		guard += 1
		var a: int = rng.next(m.n)
		var b: int = rng.next(m.n)
		if not m.nav.passable(np, size, a) or not m.nav.passable(np, size, b):
			continue
		if maxi(absi(a % m.w - b % m.w), absi(a / m.w - b / m.w)) < min_dist:
			continue
		out.append(a)
		out.append(b)
	return out


## Horizontally mirrored copy of a finalized map's terrain (x -> w - 1 - x).
static func mirrored(src: MapData) -> MapData:
	var m: MapData = MapData.create(Fx.tt(), src.w)
	for y: int in src.h:
		for x: int in src.w:
			m.terrain[y * src.w + x] = src.terrain[y * src.w + src.w - 1 - x]
			m.flags[y * src.w + x] = 0
	m.finalize()
	return m
