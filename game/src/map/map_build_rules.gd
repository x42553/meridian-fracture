class_name MapBuildRules
extends RefCounted
## Terrain-side placement predicates (terrain_movement 3.6 / 5.10). Pure terrain / occupancy facts: economy's
## SimPlacement composes them with radius, prerequisites, units, aprons and zones. Static helpers only.

const PR_OK: int = 0
const PR_OUT_OF_BOUNDS: int = 1
const PR_TERRAIN: int = 2
const PR_OCCUPIED: int = 3
const PR_NOBUILD: int = 4
const PR_NEEDS_WATER: int = 5
const PR_WATER_EXIT: int = 6
const NAVAL_COMPONENT_MIN: int = 100  ## a dock's water needs a naval component of at least this many cells


## First failing rule, in this order (each rule over ALL cells before the next): any cell outside
## [margin, w - margin) x [margin, h - margin) -> PR_OUT_OF_BOUNDS; terrain not buildable (TF_BUILD, or also
## TF_BUILD_SHORE when shore_ok) -> PR_TERRAIN; SF_NOBUILD / SF_BLOCK -> PR_NOBUILD; occ >= 0 -> PR_OCCUPIED.
static func check_land(map: MapData, cells: PackedInt32Array, shore_ok: bool = false, margin: int = 1) -> int:
	var w: int = map.w
	var h: int = map.h
	for c: int in cells:
		if c < 0 or c >= map.n:
			return PR_OUT_OF_BOUNDS
		var x: int = c % w
		var y: int = c / w
		if x < margin or y < margin or x >= w - margin or y >= h - margin:
			return PR_OUT_OF_BOUNDS
	var okmask: int = MapTerrain.TF_BUILD | (MapTerrain.TF_BUILD_SHORE if shore_ok else 0)
	for c: int in cells:
		if (map.tt.flags(map.terrain[c]) & okmask) == 0:
			return PR_TERRAIN
	for c: int in cells:
		if (map.flags[c] & (MapData.SF_NOBUILD | MapData.SF_BLOCK)) != 0:
			return PR_NOBUILD
	for c: int in cells:
		if map.occ[c] >= 0:
			return PR_OCCUPIED
	return PR_OK


## sim_core name: check_land for a MapFootprint `fp` rotated by `orient` at the top-left (cx, cy) of its oriented
## bounding box. A footprint leaving the map -> PR_OUT_OF_BOUNDS.
static func check(map: MapData, fp: MapFootprint, orient: int, cx: int, cy: int, shore_ok: bool = false,
		margin: int = 1) -> int:
	var cells: PackedInt32Array = PackedInt32Array()
	if fp.cells_at(orient, cx, cy, cells, map.w, map.h) < 0:
		return PR_OUT_OF_BOUNDS
	return check_land(map, cells, shore_ok, margin)


## Shared berth water test (generator validation and sim placement): every cell is DEEP water, all in one water body
## of >= min_size cells. No graph lookup (a berth cell next to the shore has SZ_2 clearance 1, see check_berth).
static func berth_in_deep_body(map: MapData, cells: PackedInt32Array, min_size: int) -> bool:
	var comp: int = -2
	for c: int in cells:
		if map.kind[c] != MapTerrain.TK_DEEP:
			return false
		if comp == -2:
			comp = map.water_comp[c]
		elif map.water_comp[c] != comp:
			return false
	return comp >= 0 and map.water_size[comp] >= min_size


## Dock shoreline rule: every berth cell is DEEP water (a ship of any size can leave), all in one water body of
## >= min_body cells (map.water_body_size) whose naval component has >= NAVAL_COMPONENT_MIN cells, else
## PR_NEEDS_WATER (a cell is not deep water) / PR_WATER_EXIT (pond or land-locked). The naval component is the
## abstract-graph region of NP_NAVAL when a graph exists; without a graph the water body size stands in for it.
static func check_berth(map: MapData, berth_cells: PackedInt32Array, min_body: int = 30) -> int:
	if berth_cells.is_empty():
		return PR_NEEDS_WATER
	var comp: int = -2
	for c: int in berth_cells:
		if c < 0 or c >= map.n:
			return PR_OUT_OF_BOUNDS
		if map.kind[c] != MapTerrain.TK_DEEP:
			return PR_NEEDS_WATER
	for c: int in berth_cells:
		if comp == -2:
			comp = map.water_comp[c]
		elif map.water_comp[c] != comp:
			return PR_WATER_EXIT
	var body: int = map.water_size[comp]
	if body < min_body:
		return PR_WATER_EXIT
	var naval: int = body
	if map.nav.has_graph(MapTerrain.NP_NAVAL, MapTerrain.SZ_2):
		# the best berth cell: cells next to the dock have clearance 1 (no SZ_2 region) and would refuse every real dock
		var best: int = 0
		for c: int in berth_cells:
			best = maxi(best, map.nav.region_size(MapTerrain.NP_NAVAL, MapTerrain.SZ_2, c))
		if best > 0:
			naval = best
	if naval < NAVAL_COMPONENT_MIN:
		return PR_WATER_EXIT
	return PR_OK


## AI helper: valid top-left cells (check_land == PR_OK) within Chebyshev `radius` of (ccx, ccy), nearest ring
## first then row-major inside a ring; at most `max_out` results and (2 * radius + 1)^2 checks (the whole square:
## the spec's "4 * radius^2" bound would cut the last ring short). `out` is
## cleared and receives cell indices; returns the count.
static func scan(map: MapData, fp_w: int, fp_h: int, fp_mask: PackedByteArray, orient: int, ccx: int, ccy: int,
		radius: int, out: PackedInt32Array, max_out: int) -> int:
	out.clear()
	var cells: PackedInt32Array = PackedInt32Array()
	var budget: int = (2 * radius + 1) * (2 * radius + 1)
	for r: int in range(0, radius + 1):
		for y: int in range(ccy - r, ccy + r + 1):
			var step: int = 1 if (absi(y - ccy) == r) else 2 * r
			var x: int = ccx - r
			while x <= ccx + r:
				if budget <= 0 or out.size() >= max_out:
					return out.size()
				budget -= 1
				if MapFootprint.cells(fp_w, fp_h, fp_mask, orient, x, y, cells, map.w, map.h) >= 0 \
						and check_land(map, cells) == PR_OK:
					out.append(y * map.w + x)
				x += step
	return out.size()
