class_name ViewTerrainSource
extends RefCounted
## Adapter from MapData to the arrays the terrain view needs (render spec 3.4). The ONLY view file that touches MapData:
## everything else in the terrain stack reads this record. Heights are a pure view asset (the sim only uses terrain ids).
##
## DEVIATION (MapData is the authority): `MapData.heights` holds lattice-corner heights in 1/32 m, so the metre
## conversion is `HEIGHT_M_PER_UNIT = 1/32` (the spec's 0.05 m per level belonged to a draft without MapImages), and the sea
## plane is the generator's `water_level_u` (same unit) when the map has water.

const HEIGHT_M_PER_UNIT: float = 1.0 / 32.0
const NO_WATER: float = -1000.0
const T_DEEP: int = 0
const T_SHALLOW: int = 1
const T_FORD: int = 2
const DEPTH_DEEP_M: float = 3.0  ## carved water depth below the sea plane
const DEPTH_SHALLOW_M: float = 1.0
const DEPTH_FORD_M: float = 0.35
const BANK_ABOVE_M: float = 0.2  ## corners between land and water sit just above the plane
const BANK_SLOPE_M: float = 2.4  ## relaxation: max height step to the lowest neighbour near carved water

var width: int = 0  ## cells
var height: int = 0
var seed_value: int = 0
var family: int = 0  ## 0 open, 1 urban, 2 coast
var biome: int = 0  ## 0 temperate, 1 desert, 2 arctic, 3 tropical
var deco_seed: int = 0
var corner_m: PackedFloat32Array = PackedFloat32Array()  ## (width + 1) * (height + 1) lattice-corner heights (m)
var terrain: PackedByteArray = PackedByteArray()  ## width * height terrain ids (MapTerrain.T_*), shared copy-on-write
var flags: PackedByteArray = PackedByteArray()  ## MapData.SF_* bits
var deco: PackedByteArray = PackedByteArray()  ## per-cell hash byte (decor scatter, urban block heights)
var moisture: PackedByteArray = PackedByteArray()  ## per-cell moisture 0..255 (generator phase A)
var shore_dist: PackedByteArray = PackedByteArray()  ## chamfer 3-4 distance from land in 1/3 cell, 0 on land
var sea_level_m: float = NO_WATER
var start_cells: PackedInt32Array = PackedInt32Array()  ## cell index per spawn record, slot order
var neutrals: PackedInt32Array = PackedInt32Array()  ## MapData.neutrals (stride 8)
var fields: PackedInt32Array = PackedInt32Array()  ## MapData.fields (stride 10)

var _map: MapData = null


static func from_map(m: MapData) -> ViewTerrainSource:
	var s: ViewTerrainSource = ViewTerrainSource.new()
	s._map = m
	s.width = m.w
	s.height = m.h
	s.seed_value = m.seed_value
	s.family = m.family
	s.biome = m.biome
	s.deco_seed = m.deco_seed
	s.terrain = m.terrain
	s.flags = m.flags
	s.deco = m.deco
	s.moisture = m.moisture
	s.shore_dist = m.shore_dist
	s.neutrals = m.neutrals
	s.fields = m.fields
	var n_corner: int = (m.w + 1) * (m.h + 1)
	s.corner_m.resize(n_corner)
	for i: int in n_corner:
		s.corner_m[i] = float(m.heights[i]) * HEIGHT_M_PER_UNIT
	for k: int in m.spawns.size() / MapData.SPAWN_STRIDE:
		s.start_cells.append(m.spawns[k * MapData.SPAWN_STRIDE + 1])
	s.sea_level_m = _sea_level(m)
	if s.has_water():
		s._carve_water()
	return s


## Sea plane in metres: the generator's water_level_u; a map without one (fixtures) derives (highest corner of any water
## cell + 0.5 unit); -1000 when the map holds no water cell.
static func _sea_level(m: MapData) -> float:
	if m.water_level_u > 0:
		return float(m.water_level_u) * HEIGHT_M_PER_UNIT
	var best: int = -1000000
	var stride: int = m.w + 1
	for i: int in m.n:
		var t: int = m.terrain[i]
		if t != T_DEEP and t != T_SHALLOW:
			continue
		var o: int = (i / m.w) * stride + (i % m.w)
		best = maxi(best, maxi(maxi(m.heights[o], m.heights[o + 1]), maxi(m.heights[o + stride], m.heights[o + stride + 1])))
	if best == -1000000:
		return NO_WATER
	return (float(best) + 0.5) * HEIGHT_M_PER_UNIT


## The generator paints bays and canals into the terrain ids after its height pass, so ~10 % of the water cells of a
## coast map lie above the sea plane and would render as dry sand. The view lowers every lattice corner that touches
## water to its cell's depth (corners between land and water to just above the plane) and relaxes the banks
## (two passes, corners within two rings of a carved one only). A no-op wherever the heights already agree (a bed below the
## plane keeps the generator's bathymetry).
func _carve_water() -> void:
	var w: int = width
	var h: int = height
	var stride: int = w + 1
	var depth: PackedFloat32Array = PackedFloat32Array()  # per cell: depth below the plane, -1 on land
	depth.resize(w * h)
	for i: int in w * h:
		var t: int = terrain[i]
		depth[i] = DEPTH_DEEP_M if t == T_DEEP else (DEPTH_SHALLOW_M if t == T_SHALLOW else (DEPTH_FORD_M if t == T_FORD else -1.0))
	var carved: PackedByteArray = PackedByteArray()
	carved.resize(stride * (h + 1))
	var any: bool = false
	for cy: int in h + 1:
		for cx: int in stride:
			var n_water: int = 0
			var n_cells: int = 0
			var min_depth: float = 100.0
			for k: int in 4:
				var x: int = cx - 1 + (k & 1)
				var y: int = cy - 1 + (k >> 1)
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				n_cells += 1
				var d: float = depth[y * w + x]
				if d >= 0.0:
					n_water += 1
					min_depth = minf(min_depth, d)
			if n_water == 0:
				continue
			var all_water: bool = n_water == n_cells
			var target: float = sea_level_m - min_depth if all_water else sea_level_m + BANK_ABOVE_M
			var idx: int = cy * stride + cx
			# a bed already below the plane keeps the generator's bathymetry; only beds above it are carved
			var trigger: float = sea_level_m if all_water else target
			if corner_m[idx] > trigger + 0.05:
				corner_m[idx] = target
				carved[idx] = 1
				any = true
	if not any:
		return
	# limit the bank slope near the carved corners (two rings)
	var near: PackedByteArray = carved.duplicate()
	for ring: int in 2:
		var grown: PackedByteArray = near.duplicate()
		for cy: int in h + 1:
			for cx: int in stride:
				if near[cy * stride + cx] != 0:
					for dy: int in range(-1, 2):
						for dx: int in range(-1, 2):
							var x: int = cx + dx
							var y: int = cy + dy
							if x >= 0 and y >= 0 and x < stride and y <= h:
								grown[y * stride + x] = 1
		near = grown
	for pass_i: int in 2:
		var prev: PackedFloat32Array = corner_m.duplicate()
		for cy: int in h + 1:
			for cx: int in stride:
				var idx: int = cy * stride + cx
				if near[idx] == 0 or carved[idx] != 0:
					continue
				var lowest: float = prev[idx]
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var x: int = cx + dx
						var y: int = cy + dy
						if x >= 0 and y >= 0 and x < stride and y <= h:
							lowest = minf(lowest, prev[y * stride + x])
				corner_m[idx] = minf(prev[idx], lowest + BANK_SLOPE_M)


func size_m() -> Vector2:
	return Vector2(float(width), float(height)) * ViewConsts.CELL_M


func has_water() -> bool:
	return sea_level_m > NO_WATER * 0.5


## deposit[i] / deposit_max[i]; 0.0 where the cell holds no deposit.
func deposit_fraction(i: int) -> float:
	if _map == null or i < 0 or i >= _map.n:
		return 0.0
	var mx: int = _map.deposit_max[i]
	if mx <= 0:
		return 0.0
	return float(_map.deposit[i]) / float(mx)


## Cell indices with deposit_max > 0 (initial decor build); returns the count.
func deposit_cells(out: PackedInt32Array) -> int:
	out.clear()
	if _map == null:
		return 0
	var dm: PackedInt32Array = _map.deposit_max
	for i: int in dm.size():
		if dm[i] > 0:
			out.append(i)
	return out.size()


## Cells whose deposit changed since the previous call (each once); MapData clears its list. Only the view calls this.
func drain_deposit_changes(out: PackedInt32Array) -> int:
	if _map == null:
		out.clear()
		return 0
	return _map.drain_deposit_dirty(out)


## Lattice-corner height (m) of corner (cx, cy), clamped to the grid.
func corner_at(cx: int, cy: int) -> float:
	return corner_m[clampi(cy, 0, height) * (width + 1) + clampi(cx, 0, width)]
