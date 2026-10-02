class_name MapTerrainData
extends RefCounted
## Deterministic terrain layers for one map (ints and packed int arrays only; no engine objects).
## Sim-facing contract the view builds on: corner heights, per-cell type/flags, road polylines,
## salvage fields and a shore-distance field. Height is view-only for the sim (2D + layers).

const HEIGHT_UNITS_PER_M: int = 32   ## 1 height unit = 1/32 m
const CELL_M: float = 3.0            ## metres per cell (Architecture section 3)

const T_GRASS: int = 0
const T_DIRT: int = 1
const T_ROCK: int = 2
const T_SAND: int = 3
const T_SNOW: int = 4
const T_SALVAGE: int = 5
const T_ASPHALT: int = 6

const F_WATER: int = 1
const F_CLIFF: int = 2
const F_ROAD: int = 4
const F_SALVAGE: int = 8

var width: int = 0
var height: int = 0
var seed_value: int = 0
var water_level_u: int = 0
## (width+1)*(height+1) cell-corner heights in 1/32 m.
var heights: PackedInt32Array = PackedInt32Array()
## width*height visual base type (T_*), gameplay flags (F_*), moisture 0..255 (visual only).
var types: PackedByteArray = PackedByteArray()
var flags: PackedByteArray = PackedByteArray()
var moisture: PackedByteArray = PackedByteArray()
## width*height chamfer distance from land for water cells, in 1/3 cell, capped at 255 (0 on land).
var shore_dist: PackedByteArray = PackedByteArray()
## Road polylines: [x0, y0, x1, y1, ...] in 1/16 cell units.
var roads: Array[PackedInt32Array] = []
## Salvage fields: (cx, cy, radius_cells).
var salvage_fields: Array[Vector3i] = []
var start_cells: Array[Vector2i] = []


func corner_index(cx: int, cy: int) -> int:
	return cy * (width + 1) + cx


func height_u(cx: int, cy: int) -> int:
	return heights[cy * (width + 1) + cx]


func cell_flags(cx: int, cy: int) -> int:
	return flags[cy * width + cx]


func size_m() -> Vector2:
	return Vector2(width, height) * CELL_M
